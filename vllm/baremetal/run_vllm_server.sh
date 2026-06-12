#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# run_vllm_server.sh — launch a vLLM OpenAI-compatible server on
# 1..N RDNA GPUs with tensor-parallel sharding.
#
# Examples:
#   # Default: all detected RDNA GPUs, TP=N auto-derived
#   ./run_vllm_server.sh
#
#   # Pick specific GPUs (BDF-sorted index) and override TP / port
#   ./run_vllm_server.sh --gpus 0,1 \
#       --model Qwen/Qwen3-30B-A3B-Instruct-2507-FP8 \
#       --port 8000 -- --max-model-len 16384
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$REPO_DIR/lib/rdna_detect.sh"

# vLLM venv lives under llm/ to keep the (huge, gitignored) build artifacts
# out of this scripts folder. Override with VLLM_VENV=...
VLLM_VENV="${VLLM_VENV:-${REPO_DIR}/llm/vllm-venv}"

# Defaults — overridable from CLI / env.
# Default to a pure-MoE FP8 Qwen3 model that's verified working on R9700 TP=2.
# Hybrid attention models (Qwen3.6-*-FP8 with mamba/GDN) currently hang AITER.
MODEL="${VLLM_MODEL:-Qwen/Qwen3-30B-A3B-Instruct-2507-FP8}"
HOST="${VLLM_HOST:-0.0.0.0}"
PORT="${VLLM_PORT:-8000}"
GPU_MEM_UTIL="${VLLM_GPU_MEM_UTIL:-0.92}"
# Cap context length — many FP8 ckpts publish a 262144 default that needs
# ~12 GiB KV per GPU and refuses to start. Empty = model default.
MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-32768}"
DTYPE="${VLLM_DTYPE:-auto}"
KV_CACHE_DTYPE="${VLLM_KV_CACHE_DTYPE:-auto}"   # use "fp8" to save VRAM
QUANTIZATION="${VLLM_QUANTIZATION:-}"           # e.g. fp8 (auto for FP8 ckpts)
GPUS_SELECTOR="${RDNA_GPUS:-all}"
TP_SIZE=""                                       # auto from --gpus by default
EXTRA_ARGS=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- extra vllm serve args...]

Options:
  --model NAME            HF model id or local path (default: ${MODEL})
  --gpus SELECTOR         RDNA GPU selector (default: ${GPUS_SELECTOR})
  --tp N                  Tensor parallel size (default: number of selected GPUs)
  --port N                Listen port (default: ${PORT})
  --host ADDR             Listen address (default: ${HOST})
  --max-model-len N       Max context tokens
  --gpu-memory-utilization F   0.0-1.0 (default: ${GPU_MEM_UTIL})
  --dtype DT              Model dtype: auto|float16|bfloat16|float8 (default: ${DTYPE})
  --kv-cache-dtype DT     KV cache dtype: auto|fp8|fp8_e4m3|fp8_e5m2 (default: ${KV_CACHE_DTYPE})
  --quantization Q        Force quantization scheme (e.g. fp8)
  -h, --help              Show this help

$(rdna_print_usage_block)

Environment overrides:
  VLLM_MODEL, VLLM_HOST, VLLM_PORT, VLLM_GPU_MEM_UTIL,
  VLLM_MAX_MODEL_LEN, VLLM_DTYPE, VLLM_KV_CACHE_DTYPE, VLLM_QUANTIZATION,
  RDNA_GPUS
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)               MODEL="$2"; shift 2 ;;
        --gpus)                GPUS_SELECTOR="$2"; shift 2 ;;
        --gpus=*)              GPUS_SELECTOR="${1#--gpus=}"; shift ;;
        --tp|--tensor-parallel-size) TP_SIZE="$2"; shift 2 ;;
        --port)                PORT="$2"; shift 2 ;;
        --host)                HOST="$2"; shift 2 ;;
        --max-model-len)       MAX_MODEL_LEN="$2"; shift 2 ;;
        --gpu-memory-utilization) GPU_MEM_UTIL="$2"; shift 2 ;;
        --dtype)               DTYPE="$2"; shift 2 ;;
        --kv-cache-dtype)      KV_CACHE_DTYPE="$2"; shift 2 ;;
        --quantization)        QUANTIZATION="$2"; shift 2 ;;
        -h|--help)             usage; exit 0 ;;
        --)                    shift; EXTRA_ARGS+=("$@"); break ;;
        *)                     EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# ────────────────────────────────────────────────────────────────
# Activate vLLM venv (or rely on system install if no venv exists)
# ────────────────────────────────────────────────────────────────
if [[ -d "${VLLM_VENV}" && -f "${VLLM_VENV}/bin/activate" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${VLLM_VENV}/bin/activate"
    # TheRock ships libamd_smi.so inside the venv; make ctypes (amdsmi) find it.
    _sdk_lib="$(python -c 'import _rocm_sdk_devel,os;print(os.path.dirname(_rocm_sdk_devel.__file__))' 2>/dev/null)/lib"
    if [[ -d "${_sdk_lib}" ]]; then
        export LD_LIBRARY_PATH="${_sdk_lib}:${LD_LIBRARY_PATH:-}"
    fi
fi

if ! command -v vllm &>/dev/null; then
    echo "[x] 'vllm' executable not found."
    echo "    Install it first: ${SCRIPT_DIR}/install_vllm_rocm.sh"
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# Resolve GPU selection -> HIP_VISIBLE_DEVICES + tensor-parallel
# ────────────────────────────────────────────────────────────────
mapfile -t SELECTED_BDFS < <(rdna_resolve_selector "$GPUS_SELECTOR") \
    || { echo "[x] Failed to resolve --gpus '$GPUS_SELECTOR'" >&2; exit 1; }
HIP_INDICES="$(printf '%s\n' "${SELECTED_BDFS[@]}" | bdf_to_runtime_indices)"
# IMPORTANT (R9700/gfx1201): only HIP_VISIBLE_DEVICES — setting CUDA_VISIBLE_DEVICES
# or ROCR_VISIBLE_DEVICES alongside it conflicts and breaks RCCL initialisation.
export HIP_VISIBLE_DEVICES="$HIP_INDICES"
unset CUDA_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES

N_GPUS="${#SELECTED_BDFS[@]}"
TP_SIZE="${TP_SIZE:-$N_GPUS}"

if (( TP_SIZE > N_GPUS )); then
    echo "[x] --tp ${TP_SIZE} exceeds selected GPU count (${N_GPUS})" >&2
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# ROCm/HIP runtime knobs
# ────────────────────────────────────────────────────────────────
# Force gfx1201 codepath if the toolchain probes a generic arch.
export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-12.0.1}"
# vLLM ROCm-specific perf flags.
export VLLM_WORKER_MULTIPROC_METHOD="${VLLM_WORKER_MULTIPROC_METHOD:-spawn}"
# NCCL is replaced by RCCL on ROCm; tame logging.
export NCCL_DEBUG="${NCCL_DEBUG:-WARN}"
# RDNA4 / TheRock RCCL stability + perf knobs (per kyuz0/amd-r9700-vllm-toolboxes).
export NCCL_PROTO="${NCCL_PROTO:-Simple}"
export VLLM_DISABLE_COMPILE_CACHE="${VLLM_DISABLE_COMPILE_CACHE:-1}"
export HIP_FORCE_DEV_KERNARG="${HIP_FORCE_DEV_KERNARG:-1}"
export RAY_EXPERIMENTAL_NOSET_ROCR_VISIBLE_DEVICES="${RAY_EXPERIMENTAL_NOSET_ROCR_VISIBLE_DEVICES:-1}"
export ROCBLAS_USE_HIPBLASLT="${ROCBLAS_USE_HIPBLASLT:-1}"
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL="${TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL:-1}"
# flash_attn from ROCm/flash-attention `main_perf` requires this at import time
# to dispatch to Triton kernels instead of importing missing `flash_attn_2_cuda`.
export FLASH_ATTENTION_TRITON_AMD_ENABLE="${FLASH_ATTENTION_TRITON_AMD_ENABLE:-TRUE}"

# Attention backend.  Default to AITER's Triton-based unified attention
# (works on gfx1201 / R9700 and is the only TP>=2 stable backend confirmed
#  by kyuz0).  Override with VLLM_BACKEND={aiter,triton,rocm}.
VLLM_BACKEND="${VLLM_BACKEND:-aiter}"
case "${VLLM_BACKEND}" in
    aiter)
        export VLLM_ATTENTION_BACKEND="${VLLM_ATTENTION_BACKEND:-ROCM_AITER_UNIFIED_ATTN}"
        export VLLM_ROCM_USE_AITER="${VLLM_ROCM_USE_AITER:-1}"
        export VLLM_ROCM_USE_AITER_UNIFIED_ATTENTION="${VLLM_ROCM_USE_AITER_UNIFIED_ATTENTION:-1}"
        # Disable AITER subsystems that use C++/HIP JIT kernels (hang/crash on RDNA4).
        export VLLM_ROCM_USE_AITER_MHA="${VLLM_ROCM_USE_AITER_MHA:-0}"
        export VLLM_ROCM_USE_AITER_PAGED_ATTN="${VLLM_ROCM_USE_AITER_PAGED_ATTN:-0}"
        export VLLM_ROCM_USE_AITER_MOE="${VLLM_ROCM_USE_AITER_MOE:-0}"
        export VLLM_ROCM_USE_AITER_LINEAR="${VLLM_ROCM_USE_AITER_LINEAR:-0}"
        export VLLM_ROCM_USE_AITER_RMSNORM="${VLLM_ROCM_USE_AITER_RMSNORM:-0}"
        export VLLM_ROCM_USE_AITER_FP8BMM="${VLLM_ROCM_USE_AITER_FP8BMM:-0}"
        export VLLM_ROCM_USE_AITER_FP4BMM="${VLLM_ROCM_USE_AITER_FP4BMM:-0}"
        export VLLM_ROCM_USE_AITER_TRITON_ROPE="${VLLM_ROCM_USE_AITER_TRITON_ROPE:-0}"
        export PYTORCH_ALLOC_CONF="${PYTORCH_ALLOC_CONF:-expandable_segments:True}"
        ;;
    rocm)
        export VLLM_ATTENTION_BACKEND="${VLLM_ATTENTION_BACKEND:-ROCM_ATTN}"
        ;;
    triton|*)
        export VLLM_ATTENTION_BACKEND="${VLLM_ATTENTION_BACKEND:-TRITON_ATTN}"
        ;;
esac
export VLLM_MM_ENCODER_ATTN_BACKEND="${VLLM_MM_ENCODER_ATTN_BACKEND:-TRITON_ATTN}"

if [[ -z "${LD_PRELOAD:-}" ]]; then
    for _tc in /usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 \
               /usr/lib/x86_64-linux-gnu/libtcmalloc.so.4; do
        if [[ -f "${_tc}" ]]; then
            export LD_PRELOAD="${_tc}"
            break
        fi
    done
fi

# ────────────────────────────────────────────────────────────────
# Compose vllm serve args
# ────────────────────────────────────────────────────────────────
ARGS=(
    serve "${MODEL}"
    --host "${HOST}"
    --port "${PORT}"
    --tensor-parallel-size "${TP_SIZE}"
    --gpu-memory-utilization "${GPU_MEM_UTIL}"
    --dtype "${DTYPE}"
    --kv-cache-dtype "${KV_CACHE_DTYPE}"
    --trust-remote-code
    # Attention backends are selected via VLLM_BACKEND (env block above).
    --attention-backend "${VLLM_ATTENTION_BACKEND}"
    --mm-encoder-attn-backend "${VLLM_MM_ENCODER_ATTN_BACKEND}"
    --compilation-config '{"pass_config":{"fuse_norm_quant":false}}'
)
[[ -n "${MAX_MODEL_LEN}" ]] && ARGS+=( --max-model-len "${MAX_MODEL_LEN}" )
[[ -n "${QUANTIZATION}" ]]  && ARGS+=( --quantization "${QUANTIZATION}" )
ARGS+=( "${EXTRA_ARGS[@]}" )

echo "=========================================================="
echo " vLLM (ROCm) OpenAI-compatible server"
echo " Model    : ${MODEL}"
echo " GPUs     : ${N_GPUS} selected — ${SELECTED_BDFS[*]}"
echo " HIP idx  : ${HIP_INDICES}"
echo " TP size  : ${TP_SIZE}"
echo " Endpoint : http://${HOST}:${PORT}/v1"
echo "=========================================================="
echo "+ vllm ${ARGS[*]}"
exec vllm "${ARGS[@]}"
