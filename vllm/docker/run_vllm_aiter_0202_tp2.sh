#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# run_vllm_aiter_0202_tp2.sh
#
# Helper around docker compose profile:
#   vllm/docker-compose.aiter-0202.tp2-r9700.yml
#
# Defaults target tp2 R9700 with the Austin-style unified-attention setup.
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.aiter-0202.tp2-r9700.yml"

wait_for_http_ok() {
    local name="$1"
    local url="$2"
    local timeout_seconds="${3:-900}"
    local interval="${4:-5}"
    local waited=0

    echo "Waiting for ${name}: ${url}"
    while true; do
        if curl -fsS "${url}" >/dev/null 2>&1; then
            echo "${name} is ready: ${url}"
            return 0
        fi
        if [[ ${waited} -ge ${timeout_seconds} ]]; then
            echo "Timed out waiting for ${name} after ${timeout_seconds}s."
            echo "Check logs with: $(basename "$0") logs vllm"
            return 1
        fi
        sleep "${interval}"
        waited=$((waited + interval))
    done
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [up|down|logs|ps|pull|gui] [-- additional docker compose args]

Commands:
  up      Start server in detached mode (default)
  down    Stop and remove container
  logs    Tail logs
  ps      Show service status
  pull    Pull image only
    gui     Rebuild and start the browser UI with the vLLM service

Common environment overrides:
  VLLM_IMAGE=aml731/vllm-aiter:v0.20.2
  VLLM_MODEL=Qwen/Qwen3.6-27B-FP8
  VLLM_PORT=8000
  HIP_VISIBLE_DEVICES=0,1
  VLLM_TP_SIZE=2
  VLLM_MAX_MODEL_LEN=131072
  VLLM_MTP_TOKENS=3

Optional host paths (persist caches/tuning data):
  VLLM_HF_CACHE=./.data/hf-cache
  VLLM_TUNABLEOP_DIR=./.data/tunableop
  VLLM_TRITON_CACHE_DIR=./.data/triton-cache
EOF
}

cmd="up"
if [[ $# -gt 0 ]]; then
    case "$1" in
        up|down|logs|ps|pull|gui)
            cmd="$1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
    esac
fi

mkdir -p "${VLLM_HF_CACHE:-${SCRIPT_DIR}/.data/hf-cache}"
mkdir -p "${VLLM_TUNABLEOP_DIR:-${SCRIPT_DIR}/.data/tunableop}"
mkdir -p "${VLLM_TRITON_CACHE_DIR:-${SCRIPT_DIR}/.data/triton-cache}"

case "${cmd}" in
    up)
        docker compose -f "${COMPOSE_FILE}" up -d "$@"
        wait_for_http_ok "vLLM health" "http://127.0.0.1:${VLLM_PORT:-8000}/health"
        echo "vLLM is reachable at: http://127.0.0.1:${VLLM_PORT:-8000}/v1"
        ;;
    gui)
        docker compose -f "${COMPOSE_FILE}" up -d --build vllm gui "$@"
        wait_for_http_ok "vLLM health" "http://127.0.0.1:${VLLM_PORT:-8000}/health"
        wait_for_http_ok "GUI health" "http://127.0.0.1:${GUI_PORT:-8080}/health" 120 2
        echo "Browser GUI is reachable at: http://127.0.0.1:${GUI_PORT:-8080}/"
        ;;
    down)
        docker compose -f "${COMPOSE_FILE}" down "$@"
        ;;
    logs)
        docker compose -f "${COMPOSE_FILE}" logs -f --tail=200 "$@"
        ;;
    ps)
        docker compose -f "${COMPOSE_FILE}" ps "$@"
        ;;
    pull)
        docker compose -f "${COMPOSE_FILE}" pull "$@"
        ;;
esac
