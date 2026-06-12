#!/usr/bin/env bash
# rdna_detect.sh — shared helpers for detecting AMD RDNA discrete GPUs and
# translating user-friendly --gpus selectors into PCI BDFs / runtime indices.
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/rdna_detect.sh"
#
# Public API:
#   rdna_enumerate_pci_ids          -> stdout: BDFs of discrete RDNA GPUs, sorted by BDF
#   amdgpu_enumerate_pci_ids        -> stdout: BDFs of ALL amdgpu devices (incl. iGPU), sorted
#   rdna_resolve_selector SEL       -> stdout: BDFs selected by SEL (one per line)
#   bdf_to_runtime_indices          -> stdin: BDFs, stdout: comma-joined indices for
#                                     HIP_VISIBLE_DEVICES / GGML_VK_VISIBLE_DEVICES
#   rdna_print_usage_block          -> stdout: help text describing --gpus syntax
#
# Discrete-RDNA filter: vendor 0x1002, driver=amdgpu, has DRM node, and
# mem_info_vram_total >= 4 GiB (excludes the Cezanne/RDNA2 iGPU which carves
# out only ~512 MiB / 2 GiB of system RAM).

# Guard against double-sourcing.
[[ -n "${__RDNA_DETECT_SH_SOURCED:-}" ]] && return 0
__RDNA_DETECT_SH_SOURCED=1

# Minimum VRAM (bytes) to be considered a discrete GPU.
: "${RDNA_MIN_VRAM_BYTES:=$((4 * 1024 * 1024 * 1024))}"

amdgpu_enumerate_pci_ids() {
    local dev bdf
    for dev in /sys/bus/pci/devices/*; do
        bdf="$(basename "$dev")"
        [[ -r "$dev/vendor" ]] || continue
        [[ "$(<"$dev/vendor")" == "0x1002" ]] || continue
        [[ -L "$dev/driver" ]] || continue
        [[ "$(basename "$(readlink -f "$dev/driver")")" == "amdgpu" ]] || continue
        [[ -d "$dev/drm" ]] || continue
        printf '%s\n' "$bdf"
    done | sort
}

rdna_enumerate_pci_ids() {
    local bdf dev vram
    while IFS= read -r bdf; do
        dev="/sys/bus/pci/devices/$bdf"
        # Discrete-only: integrated GPUs (e.g. Cezanne/Renoir gfx9 iGPUs)
        # do not populate mem_info_vram_vendor. PyTorch ROCm wheels only
        # ship kernels for the discrete RDNA targets the user opted into,
        # so including a gfx9 iGPU here causes hipErrorInvalidKernelFile
        # in vLLM / torch distributed init.
        [[ -r "$dev/mem_info_vram_vendor" ]] || continue
        if [[ -r "$dev/mem_info_vram_total" ]]; then
            vram="$(<"$dev/mem_info_vram_total")"
            [[ "$vram" =~ ^[0-9]+$ ]] || continue
            (( vram >= RDNA_MIN_VRAM_BYTES )) || continue
        fi
        printf '%s\n' "$bdf"
    done < <(amdgpu_enumerate_pci_ids)
}

rdna_print_usage_block() {
    cat <<'EOF'
--gpus SELECTOR     Which RDNA GPUs to use. Forms:
                      all              every detected RDNA GPU (default)
                      N                first N RDNA GPUs (PCI-BDF order)
                      i,j,k            specific RDNA indices (zero-based)
                      BDF[,BDF...]     explicit PCI BDFs, e.g. 0000:03:00.0
                    Env-var fallback: RDNA_GPUS=<selector>
EOF
}

# Resolve a selector string into PCI BDFs (one per line).
# Returns non-zero and prints an error on stderr if invalid.
rdna_resolve_selector() {
    local sel="${1:-}"
    local -a all
    mapfile -t all < <(rdna_enumerate_pci_ids)
    if (( ${#all[@]} == 0 )); then
        printf 'Error: no discrete RDNA GPUs detected.\n' >&2
        return 1
    fi

    # Empty selector or "all" -> all GPUs.
    local lc="${sel,,}"
    if [[ -z "$sel" || "$lc" == "all" ]]; then
        printf '%s\n' "${all[@]}"
        return 0
    fi

    # Single integer N -> first N GPUs.
    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local n="$sel"
        if (( n < 1 || n > ${#all[@]} )); then
            printf 'Error: requested %s GPU(s) but %s detected.\n' "$n" "${#all[@]}" >&2
            return 1
        fi
        printf '%s\n' "${all[@]:0:$n}"
        return 0
    fi

    # Comma-separated list: indices or BDFs.
    local IFS=','
    local -a parts=($sel)
    unset IFS
    if (( ${#parts[@]} == 0 )); then
        printf 'Error: empty --gpus selector.\n' >&2
        return 1
    fi

    local -a out=()
    local p
    if [[ "${parts[0]}" == *:* ]]; then
        # BDF form.
        for p in "${parts[@]}"; do
            p="${p// /}"
            if [[ ! "$p" =~ ^0000:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]]; then
                printf 'Error: invalid PCI BDF: %s\n' "$p" >&2
                return 1
            fi
            local found=0 a
            for a in "${all[@]}"; do
                [[ "$a" == "$p" ]] && { found=1; break; }
            done
            if (( ! found )); then
                printf 'Error: PCI BDF %s is not a detected RDNA GPU.\n' "$p" >&2
                printf '       Detected: %s\n' "${all[*]}" >&2
                return 1
            fi
            out+=("$p")
        done
    else
        # Index form.
        for p in "${parts[@]}"; do
            p="${p// /}"
            if [[ ! "$p" =~ ^[0-9]+$ ]]; then
                printf 'Error: invalid GPU index: %s\n' "$p" >&2
                return 1
            fi
            if (( p < 0 || p >= ${#all[@]} )); then
                printf 'Error: GPU index %s out of range (valid: 0..%s).\n' "$p" "$((${#all[@]} - 1))" >&2
                return 1
            fi
            out+=("${all[$p]}")
        done
    fi
    printf '%s\n' "${out[@]}"
}

# Convert BDFs on stdin (one per line) to a comma-joined list of runtime
# device indices (positions in the all-amdgpu BDF-sorted list, matching the
# enumeration used by HIP and Vulkan/RADV for amdgpu devices).
bdf_to_runtime_indices() {
    local -a all
    mapfile -t all < <(amdgpu_enumerate_pci_ids)
    local -a out=()
    local bdf i
    while IFS= read -r bdf; do
        [[ -n "$bdf" ]] || continue
        for i in "${!all[@]}"; do
            if [[ "${all[$i]}" == "$bdf" ]]; then
                out+=("$i")
                break
            fi
        done
    done
    (IFS=','; printf '%s\n' "${out[*]}")
}
