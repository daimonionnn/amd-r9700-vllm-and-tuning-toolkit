#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# bench-vllm.sh — generic vLLM (ROCm) benchmark wrapper.
# Runs `vllm bench throughput` (offline, in-process) against a model.
# Mirrors bench-rocm7.sh / bench-vulkan.sh conventions.
#
# Usage:
#   ./bench-vllm.sh [--gpus SELECTOR] [--tp N] [--model NAME] [extra args...]
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$REPO_DIR/lib/rdna_detect.sh"

VLLM_VENV="${VLLM_VENV:-${REPO_DIR}/llm/vllm-venv}"

MODEL="${VLLM_MODEL:-Qwen/Qwen3-30B-A3B-Instruct-2507-FP8}"
GPUS_SELECTOR="${RDNA_GPUS:-all}"
TP_SIZE=""
NUM_PROMPTS="${VLLM_NUM_PROMPTS:-256}"
INPUT_LEN="${VLLM_INPUT_LEN:-1024}"
OUTPUT_LEN="${VLLM_OUTPUT_LEN:-128}"
DTYPE="${VLLM_DTYPE:-auto}"
KV_CACHE_DTYPE="${VLLM_KV_CACHE_DTYPE:-auto}"
QUANTIZATION="${VLLM_QUANTIZATION:-}"
GPU_MEM_UTIL="${VLLM_GPU_MEM_UTIL:-0.92}"
# KV cache block size — AITER's Triton unified_attention requires power-of-2
# TILE_SIZE (= block_size in the all_decode path). vLLM's auto-pick on FP8 KV
# can land on non-pow2 values that crash kernel compile, so we pin it.
BLOCK_SIZE="${VLLM_BLOCK_SIZE:-16}"
# Cap model context length.  Many recent Qwen/Llama FP8 checkpoints publish a
# 262144-token max which needs ~12 GiB KV per replica and refuses to start.
# Empty = let vLLM use the model default.
MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-32768}"
EXTRA_ARGS=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- extra vllm-bench args]

Options:
  --model NAME          HF model id or local path (default: ${MODEL})
  --gpus SELECTOR       RDNA GPU selector (default: ${GPUS_SELECTOR})
  --tp N                Tensor-parallel size (default: # selected GPUs)
  --num-prompts N       Number of prompts to run (default: ${NUM_PROMPTS})
  --input-len N         Synthetic input length (default: ${INPUT_LEN})
  --output-len N        Tokens to generate per prompt (default: ${OUTPUT_LEN})
  --dtype DT            Model dtype (default: ${DTYPE})
  --kv-cache-dtype DT   KV cache dtype (default: ${KV_CACHE_DTYPE})
  --quantization Q      e.g. fp8
  --gpu-memory-utilization F   (default: ${GPU_MEM_UTIL})
  -h, --help            Show this help

$(rdna_print_usage_block)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)               MODEL="$2"; shift 2 ;;
        --gpus)                GPUS_SELECTOR="$2"; shift 2 ;;
        --gpus=*)              GPUS_SELECTOR="${1#--gpus=}"; shift ;;
        --tp|--tensor-parallel-size) TP_SIZE="$2"; shift 2 ;;
        --num-prompts)         NUM_PROMPTS="$2"; shift 2 ;;
        --input-len)           INPUT_LEN="$2"; shift 2 ;;
        --output-len)          OUTPUT_LEN="$2"; shift 2 ;;
        --dtype)               DTYPE="$2"; shift 2 ;;
        --kv-cache-dtype)      KV_CACHE_DTYPE="$2"; shift 2 ;;
        --quantization)        QUANTIZATION="$2"; shift 2 ;;
        --gpu-memory-utilization) GPU_MEM_UTIL="$2"; shift 2 ;;
        --max-model-len)       MAX_MODEL_LEN="$2"; shift 2 ;;
        -h|--help)             usage; exit 0 ;;
        --)                    shift; EXTRA_ARGS+=("$@"); break ;;
        *)                     EXTRA_ARGS+=("$1"); shift ;;
    esac
done

if [[ -d "${VLLM_VENV}" && -f "${VLLM_VENV}/bin/activate" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${VLLM_VENV}/bin/activate"
    _sdk_lib="$(python -c 'import _rocm_sdk_devel,os;print(os.path.dirname(_rocm_sdk_devel.__file__))' 2>/dev/null)/lib"
    if [[ -d "${_sdk_lib}" ]]; then
        export LD_LIBRARY_PATH="${_sdk_lib}:${LD_LIBRARY_PATH:-}"
    fi
fi

if ! command -v vllm &>/dev/null; then
    echo "[x] 'vllm' not found. Run ${REPO_DIR}/vllm/install_vllm_rocm.sh first." >&2
    exit 1
fi

mapfile -t SELECTED_BDFS < <(rdna_resolve_selector "$GPUS_SELECTOR") \
    || { echo "[x] Failed to resolve --gpus '$GPUS_SELECTOR'" >&2; exit 1; }
HIP_INDICES="$(printf '%s\n' "${SELECTED_BDFS[@]}" | bdf_to_runtime_indices)"
# IMPORTANT (R9700/gfx1201): only HIP_VISIBLE_DEVICES — setting CUDA_VISIBLE_DEVICES
# or ROCR_VISIBLE_DEVICES alongside it conflicts and breaks RCCL initialisation.
export HIP_VISIBLE_DEVICES="$HIP_INDICES"
unset CUDA_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES

N_GPUS="${#SELECTED_BDFS[@]}"
TP_SIZE="${TP_SIZE:-$N_GPUS}"
(( TP_SIZE <= N_GPUS )) || { echo "[x] --tp ${TP_SIZE} > selected GPUs (${N_GPUS})" >&2; exit 1; }

# ROCm 7.14 natively detects gfx1201 (R9700) — setting HSA_OVERRIDE_GFX_VERSION
# now makes HIP's hipGetDeviceCount return hipErrorNoDevice and workers crash
# with "No CUDA GPUs are available".  Only export it if the caller insists; the
# old default of 12.0.1 was required only on ROCm 7.13 and earlier.
if [[ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ]]; then
    export HSA_OVERRIDE_GFX_VERSION
fi
export VLLM_WORKER_MULTIPROC_METHOD="${VLLM_WORKER_MULTIPROC_METHOD:-spawn}"
# AITER >= 0.1.14 eagerly probes the live GPU via the venv's rocminfo wrapper
# at import time; that subprocess returns exit 8 under our HSA_OVERRIDE +
# HIP_VISIBLE_DEVICES setup.  Short-circuit with the explicit arch.
export GPU_ARCHS="${GPU_ARCHS:-gfx1201}"
export NCCL_DEBUG="${NCCL_DEBUG:-WARN}"
# RDNA4 / TheRock RCCL stability + perf knobs (per kyuz0/amd-r9700-vllm-toolboxes).
export NCCL_PROTO="${NCCL_PROTO:-Simple}"
export VLLM_DISABLE_COMPILE_CACHE="${VLLM_DISABLE_COMPILE_CACHE:-1}"
export HIP_FORCE_DEV_KERNARG="${HIP_FORCE_DEV_KERNARG:-1}"
export RAY_EXPERIMENTAL_NOSET_ROCR_VISIBLE_DEVICES="${RAY_EXPERIMENTAL_NOSET_ROCR_VISIBLE_DEVICES:-1}"
export ROCBLAS_USE_HIPBLASLT="${ROCBLAS_USE_HIPBLASLT:-1}"
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL="${TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL:-1}"
# flash_attn is built from ROCm/flash-attention `main_perf` (pure-Python Triton);
# the package's flash_attn_interface.py only dispatches to Triton kernels when
# FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE at *import* time, otherwise it tries to
# import the non-existent `flash_attn_2_cuda` extension and crashes worker init.
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

# Optional tcmalloc preload (kyuz0 reports lower fragmentation / smoother
# allocator behaviour).  Best-effort: skip silently if absent.
if [[ -z "${LD_PRELOAD:-}" ]]; then
    for _tc in /usr/lib/x86_64-linux-gnu/libtcmalloc_minimal.so.4 \
               /usr/lib/x86_64-linux-gnu/libtcmalloc.so.4; do
        if [[ -f "${_tc}" ]]; then
            export LD_PRELOAD="${_tc}"
            break
        fi
    done
fi

echo "=========================================================="
echo " vLLM throughput benchmark (ROCm, gfx1201)"
echo " Model       : ${MODEL}"
echo " GPUs        : ${N_GPUS} (${SELECTED_BDFS[*]}) HIP=${HIP_INDICES}"
echo " TP size     : ${TP_SIZE}"
echo " Prompts     : ${NUM_PROMPTS} x ${INPUT_LEN} in / ${OUTPUT_LEN} out"
echo " dtype/kv    : ${DTYPE} / ${KV_CACHE_DTYPE}"
[[ -n "${QUANTIZATION}" ]] && echo " quant       : ${QUANTIZATION}"
echo "=========================================================="

ARGS=(
    bench throughput
    --model "${MODEL}"
    --tensor-parallel-size "${TP_SIZE}"
    --gpu-memory-utilization "${GPU_MEM_UTIL}"
    --dtype "${DTYPE}"
    --kv-cache-dtype "${KV_CACHE_DTYPE}"
    --num-prompts "${NUM_PROMPTS}"
    --input-len "${INPUT_LEN}"
    --output-len "${OUTPUT_LEN}"
    # vllm bench throughput injects default --random-input-len=1024 / --random-output-len=128
    # which OVERRIDE --input-len / --output-len when both are present (see
    # vllm/benchmarks/throughput.py:1092 "the random version will be preferred").
    # Pin the random ones to the same values so our env-driven INPUT_LEN/OUTPUT_LEN
    # actually take effect.
    --random-input-len "${INPUT_LEN}"
    --random-output-len "${OUTPUT_LEN}"
    --block-size "${BLOCK_SIZE}"
    --trust-remote-code
    # Attention backends are selected via VLLM_BACKEND (env block above).
    --attention-backend "${VLLM_ATTENTION_BACKEND}"
    --mm-encoder-attn-backend "${VLLM_MM_ENCODER_ATTN_BACKEND}"
    --compilation-config '{"pass_config":{"fuse_norm_quant":false}}'
)
[[ -n "${QUANTIZATION}" ]] && ARGS+=( --quantization "${QUANTIZATION}" )
[[ -n "${MAX_MODEL_LEN}" ]] && ARGS+=( --max-model-len "${MAX_MODEL_LEN}" )
ARGS+=( "${EXTRA_ARGS[@]}" )

exec vllm "${ARGS[@]}"
