#!/usr/bin/env bash
set -euo pipefail

# ================================================================
#  vLLM (ROCm) Installation Script
#  GPU target: AMD Radeon AI PRO R9700 / RX 9070 (gfx1201, RDNA 4)
#
#  Installs vLLM into a self-contained Python venv at:
#     llm/vllm-venv/
#  Supports 1..N GPUs via --tensor-parallel-size at run time.
#
#  INSTALLATION METHOD OPTIONS:
#
#  METHOD=1 (default): TheRock pip — distro-agnostic, no reboot.
#    - Installs ROCm libraries + PyTorch-ROCm (gfx120X-all) into vllm-venv
#      from AMD's TheRock nightly index.
#    - Builds vLLM from source with VLLM_TARGET_DEVICE=rocm and
#      PYTORCH_ROCM_ARCH=gfx1201.
#    - Applies all kyuz0/RDNA4 source patches (patch_vllm.py + q_gemm.cu shim).
#    - Runs the full post-install stack required for TP>=2 + FP8 MoE:
#         tcmalloc preload, custom RCCL swap (kyuz0 Docker image),
#         hipcc gfx1201 wrapper, AITER from source, CK-free aiter patch,
#         ROCm/flash-attention#main_perf (Triton), TheRock triton restore,
#         amdsmi from the SDK.
#    - Works on Ubuntu 22.04 / 24.04 / 25.04 / 25.10.
#
#  METHOD=2: System ROCm (/opt/rocm) — reuses an existing METHOD=2/3 install.
#    - Assumes /opt/rocm is already populated (ROCm 7.x with gfx1201 libs).
#    - Installs PyTorch-ROCm wheels + builds vLLM, runs the same post-install.
#
#  METHOD=3: Docker (rocm/vllm-dev nightly) — recommended if you do not
#    want to build from source. Pulls the official ROCm vLLM image and
#    writes a thin launcher to vllm/vllm-docker-run.sh.
#
#  METHOD=post: re-run the post-install steps only (after a vLLM rebuild).
#
#  Per-step toggles (set to 0 to skip):
#    DO_VLLM_PATCHES, DO_AMDSMI, DO_RCCL_SWAP, DO_TCMALLOC,
#    DO_HIPCC_WRAPPER, DO_AITER, DO_FLASH_ATTN, DO_TRITON_RESTORE
#
#  Usage:
#    ./install_vllm_rocm.sh                 # METHOD 1 (default), full install
#    METHOD=2 ./install_vllm_rocm.sh
#    METHOD=3 ./install_vllm_rocm.sh
#    METHOD=post ./install_vllm_rocm.sh     # only post-install fix-ups
# ================================================================

METHOD="${METHOD:-1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GPU_ARCH="gfx1201"
GPU_FAMILY="gfx120X-all"
# v2-staging tracks the freshest gfx120X nightly (same channel kyuz0's main
# Dockerfile uses).  v2 stopped publishing torch/triton wheels on 2026-05-13
# even though `rocm` package keeps going, so use v2-staging for any upgrade.
THEROCK_INDEX="https://rocm.nightlies.amd.com/v2-staging/${GPU_FAMILY}/"
# Pinned triton version known to work with vLLM + AITER on gfx1201.
# Newer (3.7.x) wheels hang during fused_moe / fp8 autotune — do not bump
# the MAJOR version without re-running ./vllm/bench-vllm.sh end-to-end.
TRITON_PIN="${TRITON_PIN:-triton==3.6.0+rocm7.14.0a20260529}"

# Heavy build artefacts (venv, vLLM source, flash-attention source) live under
# llm/ so this scripts folder stays small. Override with VLLM_VENV / VLLM_SRC.
VLLM_VENV="${VLLM_VENV:-${REPO_DIR}/llm/vllm-venv}"
VLLM_SRC="${VLLM_SRC:-${REPO_DIR}/llm/vllm-src}"
FLASH_ATTN_SRC="${FLASH_ATTN_SRC:-${REPO_DIR}/llm/flash-attention}"
VLLM_REF="${VLLM_REF:-main}"   # vLLM git ref to build from
AITER_REF="${AITER_REF:-main}"
FLASH_ATTN_REF="${FLASH_ATTN_REF:-main_perf}"
DOCKER_IMAGE="${VLLM_DOCKER_IMAGE:-rocm/vllm-dev:nightly}"

# Custom RCCL image (kyuz0 toolboxes — contains a librccl.so.1 that actually
# works on gfx1201 multi-GPU, unlike the TheRock stock build).
RCCL_DOCKER_IMAGE="${RCCL_DOCKER_IMAGE:-kyuz0/vllm-therock-gfx1201:latest}"
RCCL_DOCKER_PATH="${RCCL_DOCKER_PATH:-/opt/rocm/lib/librccl.so.1.0}"

# Skip the post-install steps (RCCL swap, AITER, flash_attn, hipcc wrapper,
# vLLM in-tree patches) by setting these to 0. They are required for
# TP>=2 + FP8 MoE inference on R9700; leave enabled unless you know better.
DO_VLLM_PATCHES="${DO_VLLM_PATCHES:-1}"
DO_AMDSMI="${DO_AMDSMI:-1}"
DO_RCCL_SWAP="${DO_RCCL_SWAP:-1}"
DO_TCMALLOC="${DO_TCMALLOC:-1}"
DO_HIPCC_WRAPPER="${DO_HIPCC_WRAPPER:-1}"
DO_AITER="${DO_AITER:-1}"
DO_FLASH_ATTN="${DO_FLASH_ATTN:-1}"
DO_TRITON_RESTORE="${DO_TRITON_RESTORE:-1}"

echo "================================================================"
echo " vLLM ROCm Installation"
echo " GPU target : ${GPU_ARCH} (Radeon AI PRO R9700, RDNA 4)"
echo " Method     : ${METHOD}"
echo " venv path  : ${VLLM_VENV}"
echo " vLLM src   : ${VLLM_SRC}"
echo "================================================================"
echo ""

# ────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────
ensure_apt_pkgs() {
    local missing=()
    for pkg in "$@"; do
        dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
    done
    if (( ${#missing[@]} )); then
        echo "-> Installing apt packages: ${missing[*]}"
        sudo apt update
        sudo apt install -y "${missing[@]}"
    fi
}

clone_or_update_vllm() {
    if [[ -d "${VLLM_SRC}/.git" ]]; then
        echo "-> Updating existing vLLM checkout in ${VLLM_SRC}"
        # Revert any of our previous in-tree patches before pulling so the
        # fast-forward update can succeed cleanly. The patches are re-applied
        # idempotently by patch_vllm_sources below.
        git -C "${VLLM_SRC}" checkout -- \
            csrc/libtorch_stable/quantization/gptq/q_gemm.cu 2>/dev/null || true
        git -C "${VLLM_SRC}" fetch --all --tags
        git -C "${VLLM_SRC}" checkout "${VLLM_REF}"
        git -C "${VLLM_SRC}" pull --ff-only || true
    else
        echo "-> Cloning vLLM (${VLLM_REF}) into ${VLLM_SRC}"
        git clone https://github.com/vllm-project/vllm.git "${VLLM_SRC}"
        git -C "${VLLM_SRC}" checkout "${VLLM_REF}"
    fi
    patch_vllm_sources
}

# Apply small, idempotent source patches needed to build vLLM on RDNA4
# (gfx1201) with the TheRock ROCm 7.x SDK.
patch_vllm_sources() {
    local f="${VLLM_SRC}/csrc/libtorch_stable/quantization/gptq/q_gemm.cu"
    if [[ -f "$f" ]] && ! grep -q 'RDNA_TOOLKIT_HALF2_ATOMICADD_SHIM' "$f"; then
        echo "-> Patching q_gemm.cu: inject __half2 atomicAdd shim for ROCm"
        # Insert the shim just before the closing '#endif' of the USE_ROCM
        # compat block (the one that ends with '#define rocblas_hgemm ...').
        python3 - "$f" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
shim = r"""
  // RDNA_TOOLKIT_HALF2_ATOMICADD_SHIM
  // Older TheRock ROCm SDKs (HIP < 7.13.60850) did not provide
  // atomicAdd(__half2*, __half2) / atomicAdd(__half*, __half), and RDNA has
  // no hardware half2 atomic add. Emulate via 32-bit CAS on those SDKs.
  // ROCm 7.14+ (HIP_VERSION >= 71360850) ships native overloads in
  // amd_hip_fp16.h, so the shim must be gated to avoid an "ambiguous call"
  // build error.
  #include <hip/hip_version.h>
  #if !defined(HIP_VERSION) || HIP_VERSION < 71360850
  __device__ __forceinline__ __half2 atomicAdd(__half2* address, __half2 val) {
    unsigned int* address_as_ui = reinterpret_cast<unsigned int*>(address);
    unsigned int old = *address_as_ui;
    unsigned int assumed;
    do {
      assumed = old;
      __half2 old_h2 = *reinterpret_cast<__half2*>(&assumed);
      __half2 new_h2 = __halves2half2(
          __hadd(__low2half(old_h2),  __low2half(val)),
          __hadd(__high2half(old_h2), __high2half(val)));
      unsigned int new_ui = *reinterpret_cast<unsigned int*>(&new_h2);
      old = atomicCAS(address_as_ui, assumed, new_ui);
    } while (assumed != old);
    return *reinterpret_cast<__half2*>(&old);
  }

  // Software atomicAdd for __half. Align to 4-byte boundary and CAS the
  // containing 32-bit word, updating the correct 16-bit lane.
  __device__ __forceinline__ __half atomicAdd(__half* address, __half val) {
    unsigned int* base = reinterpret_cast<unsigned int*>(
        reinterpret_cast<uintptr_t>(address) & ~uintptr_t(3));
    bool hi = (reinterpret_cast<uintptr_t>(address) & 2) != 0;
    unsigned int old = *base;
    unsigned int assumed;
    do {
      assumed = old;
      unsigned short cur_bits = hi ? (assumed >> 16) : (assumed & 0xFFFF);
      __half cur = *reinterpret_cast<__half*>(&cur_bits);
      __half sum = __hadd(cur, val);
      unsigned short sum_bits = *reinterpret_cast<unsigned short*>(&sum);
      unsigned int new_ui = hi
          ? ((assumed & 0x0000FFFFu) | (static_cast<unsigned int>(sum_bits) << 16))
          : ((assumed & 0xFFFF0000u) |  static_cast<unsigned int>(sum_bits));
      old = atomicCAS(base, assumed, new_ui);
    } while (assumed != old);
    unsigned short ret_bits = hi ? (old >> 16) : (old & 0xFFFF);
    return *reinterpret_cast<__half*>(&ret_bits);
  }
  #endif  // HIP_VERSION < 71360850
"""
needle = "  #define rocblas_hgemm __compat_hipblasHgemm\n#endif"
if needle not in s:
    sys.stderr.write("patch_vllm_sources: anchor not found in q_gemm.cu\n")
    sys.exit(1)
s = s.replace(needle, "  #define rocblas_hgemm __compat_hipblasHgemm\n" + shim + "#endif")
open(p, "w").write(s)
PYEOF
    fi

    # Apply kyuz0-style Python patches (force gfx1201 ROCm path, mock amdsmi,
    # AITER arch mapping, FP8/INT8 MI300X config fallback, sampler gating, …).
    if [[ "${DO_VLLM_PATCHES}" == "1" && -f "${SCRIPT_DIR}/patch_vllm.py" ]]; then
        echo "-> Applying gfx1201 Python patches (patch_vllm.py)"
        ( cd "${VLLM_SRC}" && "${VLLM_VENV}/bin/python" "${SCRIPT_DIR}/patch_vllm.py" ) \
            || { echo "[!] patch_vllm.py failed (continuing)"; }
    fi
}

build_vllm_from_source() {
    local rocm_home="$1"
    echo "-> Building vLLM from source (ROCm target ${GPU_ARCH})"
    cd "${VLLM_SRC}"

    export ROCM_HOME="${rocm_home}"
    export ROCM_PATH="${rocm_home}"
    export PATH="${rocm_home}/bin:${PATH}"
    export LD_LIBRARY_PATH="${rocm_home}/lib:${LD_LIBRARY_PATH:-}"
    export VLLM_TARGET_DEVICE=rocm
    export PYTORCH_ROCM_ARCH="${GPU_ARCH}"
    export MAX_JOBS="${MAX_JOBS:-$(nproc)}"

    # Use the ROCm-specific requirements files when present.
    # Strip 'amd-quark' (no Python 3.13 wheels for >=0.7; only needed for
    # Quark-quantized models, which we are not running).
    local req_file=""
    if [[ -f requirements/rocm.txt ]];   then req_file="requirements/rocm.txt";   fi
    if [[ -z "$req_file" && -f requirements-rocm.txt ]]; then req_file="requirements-rocm.txt"; fi
    if [[ -n "$req_file" ]]; then
        # Patch the rocm requirements file in place to drop 'amd-quark'.
        # setup.py reads this same file directly into install_requires, so a
        # sibling/temp file is not enough — we must edit it (backup + restore).
        cp -f "$req_file" "${req_file}.bak"
        sed -i -E 's/^([[:space:]]*amd-quark.*)$/# \1  # patched: no py3.13 wheels >=0.7/' "$req_file"
        pip install -r "$req_file"
    fi

    # ROCm-specific build requirements (ninja, cmake, etc.).
    if [[ -f requirements/rocm-build.txt ]]; then
        pip install -r requirements/rocm-build.txt
    fi

    # --no-deps: all runtime deps are already satisfied by the patched
    # requirements file above; this prevents pip from re-resolving and pulling
    # the (unavailable) amd-quark wheel as a transitive vllm dep.
    pip install --no-build-isolation --no-deps -e .

    # Restore the original rocm requirements file (best-effort).
    if [[ -n "$req_file" && -f "${req_file}.bak" ]]; then
        mv -f "${req_file}.bak" "$req_file"
    fi
    cd "${SCRIPT_DIR}"
}

# ────────────────────────────────────────────────────────────────
# Post-install steps for R9700 / gfx1201 multi-GPU.
# Everything below is idempotent — safe to re-run after a vLLM rebuild.
# ────────────────────────────────────────────────────────────────

# Install tcmalloc (apt) — lowers HIP allocator fragmentation under TP.
install_tcmalloc() {
    [[ "${DO_TCMALLOC}" == "1" ]] || { echo "-- DO_TCMALLOC=0, skipping"; return; }
    ensure_apt_pkgs libtcmalloc-minimal4
}

# ROCm 7.14+ HSA runtime needs more locked memory than the systemd default
# of 8 MB.  Without this, rocminfo and torch.cuda init fail for unprivileged
# users with HSA_STATUS_ERROR_OUT_OF_RESOURCES.  Installs a limits.d file —
# requires the user to log out and back in for new sessions to inherit it.
install_memlock_limits() {
    [[ "${DO_MEMLOCK_LIMITS:-1}" == "1" ]] || { echo "-- DO_MEMLOCK_LIMITS=0, skipping"; return; }
    local f=/etc/security/limits.d/30-rocm-memlock.conf
    if [[ -f "${f}" ]] && grep -q 'memlock  unlimited' "${f}"; then
        echo "-- memlock limits.d already installed (${f})"
        return
    fi
    echo "-> Installing ${f} (raises RLIMIT_MEMLOCK to unlimited)"
    sudo tee "${f}" > /dev/null <<'LIMITS_EOF'
# ROCm 7.14+ HSA runtime requires more locked memory than the systemd default
# of 8 MB.  Without this, rocminfo and torch.cuda init fail for unprivileged
# users with HSA_STATUS_ERROR_OUT_OF_RESOURCES.  Installed by
# AMD-RDNA-LLM-Tuning-Toolkit/vllm/install_vllm_rocm.sh.
*  soft  memlock  unlimited
*  hard  memlock  unlimited
LIMITS_EOF
    echo "[!] LOG OUT AND BACK IN for the new memlock limit to take effect."
}

# Run patch_vllm.py against an already-built vLLM source tree. (Used as a
# defensive re-apply after pip installs / vLLM updates.)
apply_vllm_patches() {
    [[ "${DO_VLLM_PATCHES}" == "1" ]] || { echo "-- DO_VLLM_PATCHES=0, skipping"; return; }
    if [[ -f "${SCRIPT_DIR}/patch_vllm.py" && -d "${VLLM_SRC}" ]]; then
        echo "-> (re-)applying patch_vllm.py to ${VLLM_SRC}"
        ( cd "${VLLM_SRC}" && "${VLLM_VENV}/bin/python" "${SCRIPT_DIR}/patch_vllm.py" ) || true
    fi
}

# Install amdsmi Python bindings from the TheRock SDK if missing.
install_amdsmi() {
    [[ "${DO_AMDSMI}" == "1" ]] || { echo "-- DO_AMDSMI=0, skipping"; return; }
    local rocm_devel
    rocm_devel="$(find "${VLLM_VENV}" -name "_rocm_sdk_devel" -type d 2>/dev/null | head -1)"
    [[ -n "${rocm_devel}" ]] || return 0
    if ! "${VLLM_VENV}/bin/pip" show amdsmi &>/dev/null; then
        if [[ -d "${rocm_devel}/share/amd_smi" ]]; then
            echo "-> Installing amdsmi from TheRock SDK"
            "${VLLM_VENV}/bin/pip" install "${rocm_devel}/share/amd_smi"
        fi
    fi
}

# Replace the broken TheRock librccl.so.1 with a known-good build extracted
# from the kyuz0/vllm-therock-gfx1201 Docker image.  Without this swap, ALL
# RCCL allreduce kernels fail with "invalid kernel file" on gfx1201 TP>=2.
install_custom_rccl() {
    [[ "${DO_RCCL_SWAP}" == "1" ]] || { echo "-- DO_RCCL_SWAP=0, skipping"; return; }
    local sdk_lib_dir
    sdk_lib_dir="$(find "${VLLM_VENV}" -path '*_rocm_sdk_libraries_gfx120X_all/lib' -type d 2>/dev/null | head -1)"
    if [[ -z "${sdk_lib_dir}" ]]; then
        echo "[!] _rocm_sdk_libraries_gfx120X_all not found — RCCL swap skipped"
        return
    fi
    local rccl="${sdk_lib_dir}/librccl.so.1"
    # Determine if the active librccl.so.1 is already our custom (small) build.
    # TheRock-shipped librccl is huge (~50-350MB depending on nightly build);
    # the kyuz0 custom build is ~7-8MB.  Use 16MB as a clean threshold so
    # SDK upgrades that re-install a fresh TheRock blob get re-swapped.
    local rccl_size=0
    [[ -f "${rccl}" ]] && rccl_size=$(stat -c %s "${rccl}" 2>/dev/null || echo 0)
    if (( rccl_size > 0 && rccl_size < 16*1024*1024 )); then
        echo "-- custom librccl.so.1 already installed (${rccl_size} bytes), skipping"
    else
        if ! command -v docker &>/dev/null; then
            echo "[!] docker not installed — cannot extract custom RCCL. Skipping."
            echo "    Multi-GPU (TP>=2) inference will likely fail until this is done."
            return
        fi
        echo "-> Extracting custom librccl.so.1 from ${RCCL_DOCKER_IMAGE}"
        docker pull "${RCCL_DOCKER_IMAGE}"
        local cid
        cid="rccl-extract-$$"
        docker create --name "${cid}" "${RCCL_DOCKER_IMAGE}" >/dev/null
        local tmp
        tmp="$(mktemp -d)"
        docker cp "${cid}:${RCCL_DOCKER_PATH}" "${tmp}/librccl.so.1" || {
            docker rm "${cid}" >/dev/null
            echo "[!] librccl.so.1 not at ${RCCL_DOCKER_PATH} in image — skipping"
            return
        }
        docker rm "${cid}" >/dev/null
        if [[ -f "${rccl}" ]]; then
            mv -f "${rccl}" "${sdk_lib_dir}/librccl.so.1.therock.bak"
        fi
        install -m 0755 "${tmp}/librccl.so.1" "${rccl}"
        rm -rf "${tmp}"
        echo "   librccl.so.1 swapped (original kept as librccl.so.1.therock.bak)"
    fi

    # Custom RCCL has RUNPATH '$ORIGIN/../lib' and expects these neighbour
    # .so's beside it; symlink them in from _rocm_sdk_core.
    local core_lib="${sdk_lib_dir%/_rocm_sdk_libraries_gfx120X_all/lib}/_rocm_sdk_core/lib"
    if [[ -d "${core_lib}" ]]; then
        local s
        for s in libamd_smi.so.26 libroctx64.so.4 libamdhip64.so.7 librocprofiler-register.so.0; do
            if [[ -e "${core_lib}/${s}" && ! -e "${sdk_lib_dir}/${s}" ]]; then
                ln -s "../../_rocm_sdk_core/lib/${s}" "${sdk_lib_dir}/${s}"
                echo "   linked ${s} -> _rocm_sdk_core/lib/${s}"
            fi
        done
    fi
}

# AITER's ninja JIT links with `-L${VENV}/lib -lamdhip64`, but the SDK libs
# live deeper under `${VENV}/lib/python3.13/site-packages/_rocm_sdk_devel/lib/`.
# Symlink the libs the linker needs into `${VENV}/lib/` so ld -L finds them.
install_aiter_ld_symlinks() {
    local rocm_devel rel pyver libdir
    rocm_devel="$(find "${VLLM_VENV}" -name "_rocm_sdk_devel" -type d 2>/dev/null | head -1)"
    [[ -n "${rocm_devel}" ]] || return 0
    pyver="$(basename "$(dirname "$(dirname "${rocm_devel}")")")"   # python3.13
    libdir="${VLLM_VENV}/lib"
    rel="${pyver}/site-packages/_rocm_sdk_devel/lib"
    [[ -d "${rocm_devel}/lib" ]] || return 0
    local lib
    for lib in libamdhip64.so libamdhip64.so.7 libhsa-runtime64.so libhsa-runtime64.so.1 librocm_smi64.so; do
        if [[ -e "${rocm_devel}/lib/${lib}" && ! -L "${libdir}/${lib}" ]]; then
            ln -sf "${rel}/${lib}" "${libdir}/${lib}"
            echo "-> linked ${libdir}/${lib} -> ${rel}/${lib}"
        fi
    done
}

# Install hipcc wrapper that rewrites --offload-arch=native to gfx1201,
# required for AITER's JIT-compiled C++ kernels and any out-of-tree build.
install_hipcc_wrapper() {
    [[ "${DO_HIPCC_WRAPPER}" == "1" ]] || { echo "-- DO_HIPCC_WRAPPER=0, skipping"; return; }
    local hipcc="${VLLM_VENV}/bin/hipcc"
    local src="${SCRIPT_DIR}/hipcc-gfx1201-wrapper.sh"
    [[ -f "${src}" ]] || { echo "[!] missing ${src}"; return; }
    if [[ -f "${hipcc}" ]] && head -3 "${hipcc}" 2>/dev/null | grep -q 'hipcc wrapper for R9700'; then
        echo "-- hipcc wrapper already installed"
        return
    fi
    if [[ -f "${hipcc}" && ! -f "${VLLM_VENV}/bin/hipcc.therock" ]]; then
        mv -f "${hipcc}" "${VLLM_VENV}/bin/hipcc.therock"
        echo "-> moved real hipcc to hipcc.therock"
    fi
    install -m 0755 "${src}" "${hipcc}"
    echo "-> installed gfx1201 hipcc wrapper at ${hipcc}"
}

# Build & install AITER from source for gfx1201, then patch its
# cpp_itfs/utils.py so missing composable_kernel headers don't crash
# worker init (we never use AITER's C++ kernels — only Triton).
install_aiter() {
    [[ "${DO_AITER}" == "1" ]] || { echo "-- DO_AITER=0, skipping"; return; }
    if "${VLLM_VENV}/bin/pip" show amd-aiter &>/dev/null; then
        echo "-- amd-aiter already installed, skipping pip install"
    else
        echo "-> Installing AITER from source (PYTORCH_ROCM_ARCH=${GPU_ARCH})"
        PYTORCH_ROCM_ARCH="${GPU_ARCH}" \
        "${VLLM_VENV}/bin/pip" install --no-build-isolation \
            "git+https://github.com/ROCm/aiter.git@${AITER_REF}"
    fi
    patch_aiter_cpp_itfs_utils
}

# Make AITER's C++ JIT tolerate the absence of composable_kernel headers
# (we never build CK kernels on gfx1201).
patch_aiter_cpp_itfs_utils() {
    local f
    f="$("${VLLM_VENV}/bin/python" -c \
        'import aiter_meta, os; print(os.path.join(os.path.dirname(aiter_meta.__file__), "csrc/cpp_itfs/utils.py"))' \
        2>/dev/null)"
    if [[ -z "${f}" || ! -f "${f}" ]]; then
        echo "[!] aiter_meta/csrc/cpp_itfs/utils.py not found — skipping CK-free patch"
        return
    fi
    if grep -q 'CK-free build: silently skip missing CK header paths' "${f}"; then
        echo "-- aiter CK-free patch already applied"
        return
    fi
    echo "-> Patching ${f} for CK-free build"
    python3 - "${f}" <<'PYEOF'
import sys, re
p = sys.argv[1]
s = open(p).read()
# Wrap the offending shutil.copy[tree] block with a missing-path skip.
old = (
    "        for include in includes + [f\"{CK_DIR}/include\"]:\n"
    "            if os.path.isdir(include):\n"
    "                shutil.copytree(include, include_dir, dirs_exist_ok=True)\n"
    "            else:\n"
    "                shutil.copy(include, include_dir)\n"
)
new = (
    "        for include in includes + [f\"{CK_DIR}/include\"]:\n"
    "            if not os.path.exists(include):\n"
    "                # CK-free build: silently skip missing CK header paths\n"
    "                continue\n"
    "            if os.path.isdir(include):\n"
    "                shutil.copytree(include, include_dir, dirs_exist_ok=True)\n"
    "            else:\n"
    "                shutil.copy(include, include_dir)\n"
)
if old not in s:
    sys.stderr.write("patch_aiter: anchor not found — file may have changed upstream\n")
    sys.exit(0)
open(p, "w").write(s.replace(old, new))
PYEOF
}

# Install flash_attn from ROCm/flash-attention#main_perf — pure-Python Triton,
# dispatched when FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE is set at import time
# (the run scripts already export that).
install_flash_attention() {
    [[ "${DO_FLASH_ATTN}" == "1" ]] || { echo "-- DO_FLASH_ATTN=0, skipping"; return; }
    if "${VLLM_VENV}/bin/pip" show flash_attn &>/dev/null; then
        echo "-- flash_attn already installed, skipping"
        return
    fi
    if [[ ! -d "${FLASH_ATTN_SRC}/.git" ]]; then
        echo "-> Cloning ROCm/flash-attention (${FLASH_ATTN_REF}) into ${FLASH_ATTN_SRC}"
        git clone --depth=1 --branch "${FLASH_ATTN_REF}" \
            https://github.com/ROCm/flash-attention.git "${FLASH_ATTN_SRC}"
    fi
    echo "-> Building flash_attn (Triton, pure-Python)"
    PYTORCH_ROCM_ARCH="${GPU_ARCH}" FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE \
    "${VLLM_VENV}/bin/pip" install --no-build-isolation -e "${FLASH_ATTN_SRC}"
}

# AITER's setup pulls in its own triton wheel which may not match the
# pinned triton. Reinstall TRITON_PIN unless the venv already has the exact
# pinned version.
restore_triton() {
    [[ "${DO_TRITON_RESTORE}" == "1" ]] || { echo "-- DO_TRITON_RESTORE=0, skipping"; return; }
    local want="${TRITON_PIN#triton==}"
    local have
    have="$("${VLLM_VENV}/bin/pip" show triton 2>/dev/null | awk '/^Version:/{print $2}')"
    if [[ "${have}" == "${want}" ]]; then
        echo "-- triton ${have} already pinned, skipping restore"
        return
    fi
    echo "-> Installing pinned triton (${TRITON_PIN}), have='${have:-none}'"
    "${VLLM_VENV}/bin/pip" install --force-reinstall --no-deps \
        --index-url "${THEROCK_INDEX}" "${TRITON_PIN}" || \
        echo "[!] triton pin install failed — check that ${GPU_FAMILY} wheel is available"
}

# Wrap up all post-install steps. Safe to invoke multiple times.
run_post_install() {
    # vLLM's torch imports `amdsmi` which dlopens libamd_smi.so via ctypes from
    # the SDK lib dir. If LD_LIBRARY_PATH doesn't include it, every python
    # invocation below crashes before our own logic runs. Set it up now.
    local sdk_lib
    sdk_lib="$("${VLLM_VENV}/bin/python" -c \
        'import _rocm_sdk_devel,os;print(os.path.dirname(_rocm_sdk_devel.__file__))' \
        2>/dev/null)/lib"
    if [[ -d "${sdk_lib}" ]]; then
        export LD_LIBRARY_PATH="${sdk_lib}:${LD_LIBRARY_PATH:-}"
    fi
    install_tcmalloc
    install_memlock_limits
    install_custom_rccl
    install_hipcc_wrapper
    install_aiter_ld_symlinks
    apply_vllm_patches
    install_aiter
    install_flash_attention
    restore_triton
    install_amdsmi
}

# ================================================================
# METHOD 1: TheRock pip — self-contained venv
# ================================================================
install_method1_therock_pip() {
    ensure_apt_pkgs python3-venv python3-pip git build-essential cmake ninja-build pkg-config libdrm-dev libnuma-dev

    echo "-> Creating Python venv at ${VLLM_VENV}"
    python3 -m venv "${VLLM_VENV}"
    # shellcheck disable=SC1090,SC1091
    source "${VLLM_VENV}/bin/activate"
    pip install --upgrade pip wheel setuptools

    echo "-> Installing ROCm libraries + PyTorch for ${GPU_FAMILY} (TheRock)"
    pip install --index-url "${THEROCK_INDEX}" "rocm[libraries,devel]"
    pip install --index-url "${THEROCK_INDEX}" \
        torch torchvision torchaudio || {
            echo "[!] torch wheel not available on TheRock index for ${GPU_FAMILY};"
            echo "    falling back to PyTorch ROCm public wheels (may be gfx94x only)."
            pip install torch torchvision torchaudio \
                --index-url https://download.pytorch.org/whl/rocm6.4
        }

    "${VLLM_VENV}/bin/rocm-sdk" init || true
    local rocm_devel
    rocm_devel="$(find "${VLLM_VENV}" -name "_rocm_sdk_devel" -type d 2>/dev/null | head -1)"
    [[ -n "${rocm_devel}" ]] || { echo "ERROR: _rocm_sdk_devel not found in venv"; exit 1; }

    clone_or_update_vllm
    build_vllm_from_source "${rocm_devel}"

    # Post-install: AITER, flash_attn, custom RCCL, hipcc wrapper, …
    run_post_install

    echo ""
    echo "================================================================"
    echo " vLLM installed (METHOD 1, TheRock venv)"
    echo " Activate with:"
    echo "   source ${VLLM_VENV}/bin/activate"
    echo " Verify:"
    echo "   vllm --version"
    echo " Smoke benchmark (TP=N over all detected R9700s):"
    echo "   ${REPO_DIR}/vllm/bench-vllm.sh --num-prompts 4 --input-len 256 --output-len 32"
    echo "================================================================"
}

# ================================================================
# METHOD 2: System ROCm at /opt/rocm
# ================================================================
install_method2_system_rocm() {
    ensure_apt_pkgs python3-venv python3-pip git build-essential cmake ninja-build pkg-config libdrm-dev libnuma-dev

    if [[ ! -x /opt/rocm/bin/hipcc ]]; then
        echo "ERROR: /opt/rocm/bin/hipcc not found."
        echo "       Run install_rocm7_and_compile_llama.sh with METHOD=2 or 3 first."
        exit 1
    fi

    echo "-> Creating Python venv at ${VLLM_VENV}"
    python3 -m venv "${VLLM_VENV}"
    # shellcheck disable=SC1090,SC1091
    source "${VLLM_VENV}/bin/activate"
    pip install --upgrade pip wheel setuptools

    echo "-> Installing PyTorch ROCm wheels (public index)"
    pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/rocm6.4

    clone_or_update_vllm
    build_vllm_from_source "/opt/rocm"

    run_post_install

    echo ""
    echo "================================================================"
    echo " vLLM installed (METHOD 2, system /opt/rocm)"
    echo " Activate with:"
    echo "   source ${VLLM_VENV}/bin/activate"
    echo "================================================================"
}

# ================================================================
# METHOD 3: Docker (rocm/vllm-dev)
# ================================================================
install_method3_docker() {
    if ! command -v docker &>/dev/null; then
        echo "ERROR: docker not installed. Install Docker + the AMD container"
        echo "       toolkit, then re-run with METHOD=3."
        exit 1
    fi

    echo "-> Pulling Docker image ${DOCKER_IMAGE}"
    docker pull "${DOCKER_IMAGE}"

    local launcher="${SCRIPT_DIR}/vllm-docker-run.sh"
    cat >"${launcher}" <<EOF
#!/usr/bin/env bash
# Auto-generated by install_vllm_rocm.sh (METHOD=3).
# Usage: ./vllm-docker-run.sh [vllm CLI args...]
set -euo pipefail
exec docker run --rm -it \\
    --device=/dev/kfd --device=/dev/dri \\
    --group-add video --group-add render \\
    --ipc=host --shm-size=16g \\
    --security-opt seccomp=unconfined \\
    -v "\${HOME}/.cache/huggingface:/root/.cache/huggingface" \\
    -e HSA_OVERRIDE_GFX_VERSION="\${HSA_OVERRIDE_GFX_VERSION:-12.0.1}" \\
    -e HIP_VISIBLE_DEVICES="\${HIP_VISIBLE_DEVICES:-}" \\
    -p 8000:8000 \\
    ${DOCKER_IMAGE} \\
    "\$@"
EOF
    chmod +x "${launcher}"

    echo ""
    echo "================================================================"
    echo " vLLM Docker image ready (METHOD 3)"
    echo " Launcher written to: ${launcher}"
    echo " Example:"
    echo "   ${launcher} vllm serve Qwen/Qwen3-30B-A3B-Instruct-2507-FP8 --tensor-parallel-size 2"
    echo "================================================================"
}

case "${METHOD}" in
    1)    install_method1_therock_pip ;;
    2)    install_method2_system_rocm ;;
    3)    install_method3_docker ;;
    post) # Re-apply post-install steps only (use after a vLLM rebuild).
          [[ -d "${VLLM_VENV}" ]] || { echo "ERROR: venv ${VLLM_VENV} not found"; exit 1; }
          # shellcheck disable=SC1090,SC1091
          source "${VLLM_VENV}/bin/activate"
          run_post_install
          echo "-> post-install steps complete" ;;
    *) echo "ERROR: unknown METHOD=${METHOD} (use 1, 2, 3 or post)"; exit 1 ;;
esac
