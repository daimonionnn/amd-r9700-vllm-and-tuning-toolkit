#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# run_llm_benchmark_vllm.sh — full vLLM benchmark suite (ROCm).
#
# Runs `vllm bench throughput` for each model across a sweep of
# (input_len, output_len) shapes. With >1 GPU selected, runs each
# GPU individually and then a combined tensor-parallel pass (TP=N),
# mirroring run_llm_benchmark_rocm.sh.
#
# Default model: Qwen 3.6 27B FP8 (single model — keeps the run quick).
# Override with MODELS="repo/id another/id" environment variable.
# ================================================================

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$REPO_DIR/lib/rdna_detect.sh"

LLM_DIR="${REPO_DIR}/llm"
VLLM_VENV="${VLLM_VENV:-${LLM_DIR}/vllm-venv}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--gpus SELECTOR] [--no-per-gpu-sweep]
                        [--model NAME] [--shapes "IN/OUT,IN/OUT,..."]

$(rdna_print_usage_block)

  --no-per-gpu-sweep   When >1 GPU is selected, skip per-GPU passes
                       and only run the combined TP=N pass.
  --model NAME         Single model to benchmark
                       (overrides MODELS env var; default Qwen3-30B-A3B FP8).
  --shapes LIST        Comma-separated INPUT/OUTPUT length pairs
                       (default: 1024/128,4096/128,8192/256).

Environment overrides:
  MODELS              space-separated list of HF model IDs / local paths
  VLLM_NUM_PROMPTS    prompts per pass (default 128)
  VLLM_GPU_MEM_UTIL   GPU memory utilization (default 0.92)
  VLLM_KV_CACHE_DTYPE auto | fp8 | fp8_e4m3 (default auto)
EOF
}

GPUS_SELECTOR="${RDNA_GPUS:-all}"
PER_GPU_SWEEP=1
SHAPES_CSV="1024/128,4096/128,8192/256"
OVERRIDE_MODEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpus)              GPUS_SELECTOR="$2"; shift 2 ;;
        --gpus=*)            GPUS_SELECTOR="${1#--gpus=}"; shift ;;
        --no-per-gpu-sweep)  PER_GPU_SWEEP=0; shift ;;
        --model)             OVERRIDE_MODEL="$2"; shift 2 ;;
        --shapes)            SHAPES_CSV="$2"; shift 2 ;;
        -h|--help)           usage; exit 0 ;;
        *)                   echo "[x] Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# Default model list (pure-MoE Qwen3 FP8 — verified working on R9700 TP=2).
# Override via env or --model. Avoid hybrid Qwen3.6-*-FP8 (mamba/GDN hangs AITER).
DEFAULT_MODELS=( "Qwen/Qwen3-30B-A3B-Instruct-2507-FP8" )
if [[ -n "${OVERRIDE_MODEL}" ]]; then
    MODELS_ARR=( "${OVERRIDE_MODEL}" )
elif [[ -n "${MODELS:-}" ]]; then
    # shellcheck disable=SC2206
    MODELS_ARR=( ${MODELS} )
else
    MODELS_ARR=( "${DEFAULT_MODELS[@]}" )
fi

# Activate vLLM venv if present.
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

# ROCm runtime knobs
export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-12.0.1}"
export VLLM_USE_TRITON_FLASH_ATTN="${VLLM_USE_TRITON_FLASH_ATTN:-1}"
export VLLM_WORKER_MULTIPROC_METHOD="${VLLM_WORKER_MULTIPROC_METHOD:-spawn}"
export NCCL_DEBUG="${NCCL_DEBUG:-WARN}"

NUM_PROMPTS="${VLLM_NUM_PROMPTS:-128}"
GPU_MEM_UTIL="${VLLM_GPU_MEM_UTIL:-0.92}"
KV_CACHE_DTYPE="${VLLM_KV_CACHE_DTYPE:-auto}"
DTYPE="${VLLM_DTYPE:-auto}"
QUANTIZATION="${VLLM_QUANTIZATION:-}"

RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/vllm_benchmark_results_$(date +%Y%m%d_%H%M%S).txt"

# Resolve GPU selection.
mapfile -t SELECTED_BDFS < <(rdna_resolve_selector "$GPUS_SELECTOR") \
    || { echo "[x] Failed to resolve --gpus '$GPUS_SELECTOR'" >&2; exit 1; }

# Build pass list: "label|bdf_csv|tp_size".
PASSES=()
if (( ${#SELECTED_BDFS[@]} == 1 )); then
    PASSES+=("single GPU ${SELECTED_BDFS[0]}|${SELECTED_BDFS[0]}|1")
else
    if (( PER_GPU_SWEEP )); then
        for bdf in "${SELECTED_BDFS[@]}"; do
            PASSES+=("solo $bdf|$bdf|1")
        done
    fi
    combined="$(IFS=,; echo "${SELECTED_BDFS[*]}")"
    PASSES+=("TP=${#SELECTED_BDFS[@]} ($combined)|$combined|${#SELECTED_BDFS[@]}")
fi

# Parse shapes "IN/OUT,IN/OUT,..." -> arrays
IFS=',' read -r -a SHAPE_PAIRS <<<"$SHAPES_CSV"

{
    echo "=========================================================="
    echo " AMD RDNA LLM Benchmark Suite (vLLM / ROCm)               "
    echo " Backend:        vLLM (gfx1201)                            "
    echo " Models:         ${MODELS_ARR[*]}                          "
    echo " Shapes (in/out):${SHAPES_CSV}                             "
    echo " Prompts/pass:   ${NUM_PROMPTS}                            "
    echo " GPUs selected:  ${#SELECTED_BDFS[@]} (${SELECTED_BDFS[*]})"
    echo " Passes:         ${#PASSES[@]}                             "
    echo " Output log:     ${RESULTS_FILE}                           "
    echo "=========================================================="
} | tee -a "$RESULTS_FILE"

for pass in "${PASSES[@]}"; do
    label="${pass%%|*}"
    rest="${pass#*|}"
    bdf_csv="${rest%%|*}"
    tp_size="${rest##*|}"

    HIP_INDICES="$(printf '%s\n' ${bdf_csv//,/ } | bdf_to_runtime_indices)"
    export HIP_VISIBLE_DEVICES="$HIP_INDICES"
    export ROCR_VISIBLE_DEVICES="$HIP_INDICES"
    export CUDA_VISIBLE_DEVICES="$HIP_INDICES"

    {
        echo ""
        echo "##########################################################"
        echo "# PASS: $label  (TP=$tp_size)"
        echo "# BDFs: $bdf_csv"
        echo "# HIP_VISIBLE_DEVICES=$HIP_INDICES"
        echo "##########################################################"
    } | tee -a "$RESULTS_FILE"

    for MODEL in "${MODELS_ARR[@]}"; do
        {
            echo ""
            echo "----------------------------------------------------------"
            echo " Model: ${MODEL}"
            echo "----------------------------------------------------------"
        } | tee -a "$RESULTS_FILE"

        for shape in "${SHAPE_PAIRS[@]}"; do
            in_len="${shape%%/*}"
            out_len="${shape##*/}"

            CMD=(
                vllm bench throughput
                --model "$MODEL"
                --tensor-parallel-size "$tp_size"
                --gpu-memory-utilization "$GPU_MEM_UTIL"
                --dtype "$DTYPE"
                --kv-cache-dtype "$KV_CACHE_DTYPE"
                --num-prompts "$NUM_PROMPTS"
                --input-len "$in_len"
                --output-len "$out_len"
                --trust-remote-code
            )
            [[ -n "$QUANTIZATION" ]] && CMD+=( --quantization "$QUANTIZATION" )

            {
                echo ""
                echo ">> Shape: input=${in_len}  output=${out_len}"
                echo "Command: ${CMD[*]}"
                echo ""
            } | tee -a "$RESULTS_FILE"

            "${CMD[@]}" 2>&1 | tee -a "$RESULTS_FILE" || {
                echo "[!] vllm bench throughput failed for ${MODEL} ${shape}" \
                    | tee -a "$RESULTS_FILE"
            }
        done
    done
done

{
    echo ""
    echo "=========================================================="
    echo " vLLM benchmarks completed!"
    echo " Results saved to: $RESULTS_FILE"
    echo "=========================================================="
} | tee -a "$RESULTS_FILE"
