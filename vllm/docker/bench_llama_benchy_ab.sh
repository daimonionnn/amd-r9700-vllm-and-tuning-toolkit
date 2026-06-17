#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.aiter-0202.tp2-r9700.yml"
VLLM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-aml731/vllm-aiter:v0.20.2}"

SERVED_MODEL="${VLLM_SERVED_MODEL_NAME:-Qwen3.6-27B-FP8}"
PORT="${VLLM_PORT:-8000}"

DEPTHS="${DEPTHS:-4096 8132 16000 }"
OUT_DIR="${VLLM_DIR}/results/llama_benchy_$(date +%Y%m%d_%H%M%S)"
PULL_POLICY="${PULL_POLICY:-missing}"
mkdir -p "${OUT_DIR}"

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

managed_container=0
managed_project=""
current_container=""

cleanup() {
    stop_server
}
trap cleanup EXIT

stop_server() {
    if [[ "${managed_container}" == "1" && -n "${current_container}" && -n "${managed_project}" ]]; then
        VLLM_CONTAINER_NAME="${current_container}" docker compose -p "${managed_project}" -f "${COMPOSE_FILE}" down || true
    fi
    current_container=""
    managed_container=0
    managed_project=""
}

wait_healthy() {
    local timeout=$1
    local start_time=$(date +%s)
    local check_url="http://127.0.0.1:${PORT}/health"
    while true; do
        if curl -s -f "${check_url}" >/dev/null 2>&1; then
            return 0
        fi
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if (( elapsed >= timeout )); then
            return 1
        fi
        sleep 5
    done
}

start_server() {
    local label="$1"
    local image="$2"
    local effective_pull="never"

    if [[ "${PULL_POLICY}" == "always" || "${PULL_POLICY}" == "missing" ]]; then
        if ! docker image inspect "${image}" >/dev/null 2>&1; then
            effective_pull="always"
        elif [[ "${PULL_POLICY}" == "always" ]]; then
            effective_pull="always"
        fi
    fi

    echo "================================================="
    if docker ps --filter "ancestor=${image}" --filter "status=running" --format "{{.Names}}" | grep -q .; then
        current_container=$(docker ps --filter "ancestor=${image}" --filter "status=running" --format "{{.Names}}" | head -n1)
        echo "[i] Reusing running container ${current_container} for ${label}: ${image}"
        managed_container=0
    else
        echo "[i] Starting ${label} image: ${image} (pull=${effective_pull})"
        managed_project="vllm_bench_${label}_$$"
        export VLLM_IMAGE="${image}"
        export VLLM_CONTAINER_NAME="vllm_${managed_project}_${RANDOM}"

        docker compose -p "${managed_project}" -f "${COMPOSE_FILE}" up -d --pull "${effective_pull}"
        current_container="${VLLM_CONTAINER_NAME}"
        managed_container=1
    fi

    echo "[i] Waiting for health endpoint on :${PORT}"
    if ! wait_healthy 1800; then
        echo "[x] Server did not become healthy in time: ${label}" >&2
        exit 1
    fi
}

run_llama_benchy() {
    local label="$1"
    local image="$2"

    start_server "${label}" "${image}"

    echo "[i] Running llama-benchy for ${label}"
    run_llama_benchy_cli \
        --base-url "http://127.0.0.1:${PORT}/v1" \
        --served-model-name "${SERVED_MODEL}" \
        --tokenizer "Qwen/Qwen3.6-27B-FP8" \
        --pp 2048 \
        --tg 32 \
        --runs 1 \
        --depth ${DEPTHS} \
        --save-result "${OUT_DIR}/${label}_benchy.md" \
        --format md

    stop_server
}

echo "[i] Output directory: ${OUT_DIR}"

run_llama_benchy "v0.20.2" "${IMAGE}"

echo "=========================================================="
echo "[ok] Llama-benchy run completed"
echo "[ok] Check the MD files in ${OUT_DIR}"
