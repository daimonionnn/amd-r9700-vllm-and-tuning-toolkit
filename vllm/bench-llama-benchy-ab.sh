#!/bin/bash
set -e

# Configuration
PORT=8000
BASE_IMAGE="aml731/vllm-aiter:v0.20.2"
CANDIDATE_IMAGE="aml731/vllm-aiter-v20.2:v0.20.2" # Assuming this based on Reddit user post
CONTAINER_NAME="vllm-llama-benchy-test"
SERVED_MODEL="Qwen/Qwen3.6-27B-FP8"
# Resolve the HF cache the same way huggingface_hub does: HF_HOME if set,
# otherwise ~/.cache/huggingface.  Override MODEL_PATH to point elsewhere.
MODEL_PATH="${MODEL_PATH:-${HF_HOME:-$HOME/.cache/huggingface}/hub/models--Qwen--Qwen3.6-27B-FP8}"
OUT_DIR="$(pwd)/results/llama_benchy_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUT_DIR"

run_llama_benchy_cli() {
    local -a llama_benchy_cmd
    if [[ -n "${LLAMA_BENCHY_CMD:-}" ]]; then
        read -r -a llama_benchy_cmd <<< "${LLAMA_BENCHY_CMD}"
    elif command -v llama-benchy >/dev/null 2>&1; then
        llama_benchy_cmd=(llama-benchy)
    elif command -v uvx >/dev/null 2>&1; then
        llama_benchy_cmd=(uvx llama-benchy)
    else
        echo "[x] llama-benchy is not installed and uvx was not found." >&2
        echo "[x] Install it with: uv tool install llama-benchy" >&2
        echo "[x] Or set LLAMA_BENCHY_CMD, for example: LLAMA_BENCHY_CMD='uvx llama-benchy'" >&2
        exit 1
    fi

    "${llama_benchy_cmd[@]}" "$@"
}

cleanup() {
    echo "[i] Cleaning up any existing containers..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT
cleanup

run_benchy() {
    local image="$1"
    local run_name="$2"

    echo "=========================================================="
    echo "[i] Starting container with image: $image"
    docker run -d --name "$CONTAINER_NAME" \
        --network host \
        --device /dev/kfd --device /dev/dri \
        -v "${MODEL_PATH}:/app/model" \
        "$image" \
        --model /app/model \
        --served-model-name "$SERVED_MODEL" \
        --tensor-parallel-size 2 \
        --max-model-len 32768 \
        --enable-chunked-prefill \
        --port $PORT

    echo "[i] Waiting for server to become healthy..."
    until curl -s http://127.0.0.1:${PORT}/health > /dev/null; do
        sleep 2
    done
    echo "[i] Server is healthy."

    echo "[i] Running llama-benchy for $run_name"
    run_llama_benchy_cli \
        --base-url "http://127.0.0.1:${PORT}/v1" \
        --served-model-name "$SERVED_MODEL" \
        --tokenizer "$MODEL_PATH" \
        --pp 2048 \
        --tg 32 \
        --runs 3 \
        --depth 4096 8132 16000 30000 \
        --save-result "${OUT_DIR}/${run_name}.md" \
        --format md

    echo "[i] Run complete for $run_name"
    cleanup
}

run_benchy "$BASE_IMAGE" "base_run"
run_benchy "$CANDIDATE_IMAGE" "candidate_run"

echo "=========================================================="
echo "Results available in: $OUT_DIR"
