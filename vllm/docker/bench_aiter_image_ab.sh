#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# bench_aiter_image_ab.sh
#
# One-command A/B benchmark for 2x R9700 Docker images using the
# compose profile in docker-compose.aiter-0202.tp2-r9700.yml.
#
# It runs two passes for each context depth:
#   - PP-like pass: output_len=1   (prefill-heavy)
#   - TG-like pass: output_len=32  (decode-mixed)
#
# Benchmark client: vllm bench serve (random dataset, OpenAI endpoint)
# Output: raw JSON files + CSV summaries + markdown comparison table.
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.aiter-0202.tp2-r9700.yml"
VLLM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BASE_IMAGE="${BASE_IMAGE:-aml731/vllm-aiter:v0.19.1}"
CANDIDATE_IMAGE="${CANDIDATE_IMAGE:-aml731/vllm-aiter:v0.20.2}"

MODEL="${VLLM_MODEL:-Qwen/Qwen3.6-27B-FP8}"
SERVED_MODEL="${VLLM_SERVED_MODEL_NAME:-Qwen3.6-27B-FP8}"
PORT="${VLLM_PORT:-8000}"
HIP_DEVICES="${HIP_VISIBLE_DEVICES:-0,1}"
TP_SIZE="${VLLM_TP_SIZE:-2}"
MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-131072}"
GPU_MEM_UTIL="${VLLM_GPU_MEMORY_UTIL:-0.95}"

DEPTHS="${DEPTHS:-4096 8132 16000 30000 60000}"
NUM_PROMPTS="${NUM_PROMPTS:-24}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-1}"
TG_OUTPUT_LEN="${TG_OUTPUT_LEN:-32}"

OUT_DIR="${OUT_DIR:-${VLLM_DIR}/results/ab_aiter_images_$(date +%Y%m%d_%H%M%S)}"
PULL_POLICY="${PULL_POLICY:-missing}"
mkdir -p "${OUT_DIR}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [run]

Environment knobs:
  BASE_IMAGE           default: ${BASE_IMAGE}
  CANDIDATE_IMAGE      default: ${CANDIDATE_IMAGE}
  VLLM_MODEL           default: ${MODEL}
  VLLM_SERVED_MODEL_NAME default: ${SERVED_MODEL}
  HIP_VISIBLE_DEVICES  default: ${HIP_DEVICES}
  VLLM_TP_SIZE         default: ${TP_SIZE}
  VLLM_PORT            default: ${PORT}
  VLLM_MAX_MODEL_LEN   default: ${MAX_MODEL_LEN}
  DEPTHS               default: "${DEPTHS}"
  NUM_PROMPTS          default: ${NUM_PROMPTS}
  MAX_CONCURRENCY      default: ${MAX_CONCURRENCY}
  TG_OUTPUT_LEN        default: ${TG_OUTPUT_LEN}
  OUT_DIR              default: ${OUT_DIR}
    PULL_POLICY          default: ${PULL_POLICY} (missing|always|never)

Examples:
  $(basename "$0")
  DEPTHS="4096 16000 30000" NUM_PROMPTS=8 $(basename "$0")
EOF
}

if [[ "${1:-run}" =~ ^(-h|--help|help)$ ]]; then
    usage
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "[x] docker not found" >&2
    exit 1
fi
# We run benchmarks via HTTP requests from Python stdlib, no host-side
# GPU/runtime bindings needed.

current_container=""
managed_container=0
managed_project=""

find_running_container_for_image() {
    local image="$1"
    docker ps --filter "ancestor=${image}" --filter "status=running" --format '{{.Names}}' | head -n1
}

cleanup() {
    if [[ "${managed_container}" == "1" && -n "${current_container}" && -n "${managed_project}" ]]; then
        VLLM_CONTAINER_NAME="${current_container}" docker compose -p "${managed_project}" -f "${COMPOSE_FILE}" down >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

wait_healthy() {
    local timeout_s="${1:-900}"
    local start
    start="$(date +%s)"
    while true; do
        if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
            return 0
        fi
        if (( $(date +%s) - start > timeout_s )); then
            return 1
        fi
        sleep 5
    done
}

start_server() {
    local label="$1"
    local image="$2"

    if current_container="$(find_running_container_for_image "${image}")" && [[ -n "${current_container}" ]]; then
        managed_container=0
        managed_project=""
        echo "[i] Reusing running container ${current_container} for ${label}: ${image}"
        echo "[i] Waiting for health endpoint on :${PORT}"
        if ! wait_healthy 1800; then
            echo "[x] Existing server did not become healthy in time: ${label}" >&2
            docker logs --tail=200 "${current_container}" || true
            exit 1
        fi
        return 0
    fi

    current_container="vllm-ab-${label}"
    managed_container=1
    managed_project="vllm-ab-${label}"

    # Use --pull never when the image is already cached locally to avoid
    # unnecessary registry manifest checks that look like (and can become) pulls.
    local effective_pull="${PULL_POLICY}"
    if docker image inspect "${image}" >/dev/null 2>&1; then
        effective_pull="never"
    fi

    echo "[i] Starting ${label} image: ${image} (pull=${effective_pull})"
    VLLM_IMAGE="${image}" \
    VLLM_CONTAINER_NAME="${current_container}" \
    HIP_VISIBLE_DEVICES="${HIP_DEVICES}" \
    VLLM_TP_SIZE="${TP_SIZE}" \
    VLLM_PORT="${PORT}" \
    VLLM_MODEL="${SERVED_MODEL}" \
    VLLM_SERVED_MODEL_NAME="${SERVED_MODEL}" \
    VLLM_MAX_MODEL_LEN="${MAX_MODEL_LEN}" \
    VLLM_GPU_MEMORY_UTIL="${GPU_MEM_UTIL}" \
    docker compose -p "${managed_project}" -f "${COMPOSE_FILE}" up -d --pull "${effective_pull}"

    echo "[i] Waiting for health endpoint on :${PORT}"
    if ! wait_healthy 1800; then
        echo "[x] Server did not become healthy in time: ${label}" >&2
        VLLM_CONTAINER_NAME="${current_container}" docker compose -p "${managed_project}" -f "${COMPOSE_FILE}" logs --tail=200 || true
        exit 1
    fi
}

stop_server() {
    if [[ "${managed_container}" == "1" && -n "${current_container}" && -n "${managed_project}" ]]; then
        VLLM_CONTAINER_NAME="${current_container}" docker compose -p "${managed_project}" -f "${COMPOSE_FILE}" down || true
    fi
    current_container=""
    managed_container=0
    managed_project=""
}

extract_metric() {
    local json_path="$1"
    python3 - "$json_path" <<'PYEOF'
import json, sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    data = json.load(f)

def pick(d, keys):
    for k in keys:
        if isinstance(d, dict) and k in d and isinstance(d[k], (int, float)):
            return float(d[k])
    return None

# Try common schemas first.
if isinstance(data, list) and data:
    data = data[-1]

out_tps = pick(data, [
    'output_throughput',
    'output_token_throughput',
    'output_tokens_per_second',
])
in_tps = pick(data, [
    'input_throughput',
    'input_token_throughput',
    'input_tokens_per_second',
])
ttft_ms = pick(data, [
    'mean_ttft_ms',
    'ttft_mean_ms',
])

def walk(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield k, v
            yield from walk(v)
    elif isinstance(obj, list):
        for x in obj:
            yield from walk(x)

if out_tps is None or in_tps is None:
    flat = {k: v for k, v in walk(data) if isinstance(v, (int, float))}
    if out_tps is None:
        for k in ('output_throughput', 'output_token_throughput', 'output_tokens_per_second'):
            if k in flat:
                out_tps = float(flat[k]); break
    if in_tps is None:
        for k in ('input_throughput', 'input_token_throughput', 'input_tokens_per_second'):
            if k in flat:
                in_tps = float(flat[k]); break
    if ttft_ms is None:
        for k in ('mean_ttft_ms', 'ttft_mean_ms'):
            if k in flat:
                ttft_ms = float(flat[k]); break

if out_tps is None:
    out_tps = -1.0
if in_tps is None:
    in_tps = -1.0
if ttft_ms is None:
    ttft_ms = -1.0

print(f"{in_tps:.6f},{out_tps:.6f},{ttft_ms:.6f}")
PYEOF
}

run_one_bench() {
    local label="$1"
    local phase="$2"
    local depth="$3"
    local out_len="$4"
    local out_json="${OUT_DIR}/${label}_${phase}_d${depth}.json"
    local out_log="${OUT_DIR}/${label}_${phase}_d${depth}.log"

    echo "[i] ${label} ${phase} depth=${depth} out=${out_len}" >&2
    python3 - "${PORT}" "${SERVED_MODEL}" "${NUM_PROMPTS}" "${MAX_CONCURRENCY}" "${depth}" "${out_len}" "${out_json}" "${out_log}" <<'PYEOF'
import json, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

port = int(sys.argv[1])
model = sys.argv[2]
num_prompts = int(sys.argv[3])
max_conc = max(1, int(sys.argv[4]))
depth = int(sys.argv[5])
out_len = int(sys.argv[6])
out_json = sys.argv[7]
out_log = sys.argv[8]

url = f"http://127.0.0.1:{port}/v1/chat/completions"

def mk_prompt(tokens):
    return " ".join(["token"] * max(1, tokens))

payload = {
    "model": model,
    "messages": [{"role": "user", "content": mk_prompt(depth)}],
    "max_tokens": out_len,
    "temperature": 0.0,
}
body = json.dumps(payload).encode("utf-8")

def one_req(i):
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}, method="POST")
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=1800) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    dt = time.perf_counter() - t0
    usage = data.get("usage", {})
    return {
        "latency_s": dt,
        "prompt_tokens": int(usage.get("prompt_tokens", 0)),
        "completion_tokens": int(usage.get("completion_tokens", 0)),
    }

results = []
errors = []
wall_t0 = time.perf_counter()
with ThreadPoolExecutor(max_workers=max_conc) as ex:
    futs = [ex.submit(one_req, i) for i in range(num_prompts)]
    for f in as_completed(futs):
        try:
            results.append(f.result())
        except Exception as e:
            errors.append(str(e))
wall = max(1e-9, time.perf_counter() - wall_t0)

ptoks = sum(r["prompt_tokens"] for r in results)
ctoks = sum(r["completion_tokens"] for r in results)
mean_lat_ms = (sum(r["latency_s"] for r in results) / max(1, len(results))) * 1000.0

obj = {
    "num_requests": len(results),
    "errors": errors,
    "input_token_throughput": ptoks / wall,
    "output_token_throughput": ctoks / wall,
    "ttft_mean_ms": mean_lat_ms,
}

with open(out_json, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
with open(out_log, "w", encoding="utf-8") as f:
    f.write(json.dumps(obj, indent=2) + "\n")

print(f"{obj['input_token_throughput']:.6f},{obj['output_token_throughput']:.6f},{obj['ttft_mean_ms']:.6f}")
PYEOF
}

run_matrix_for_image() {
    local label="$1"
    local image="$2"
    local csv_file="${OUT_DIR}/${label}_metrics.csv"

    echo "phase,depth,input_tps,output_tps,ttft_ms" > "${csv_file}"
    start_server "${label}" "${image}"

    for d in ${DEPTHS}; do
        IFS=',' read -r in_pp out_pp ttft_pp < <(run_one_bench "${label}" "pp" "${d}" 1)
        echo "pp,${d},${in_pp},${out_pp},${ttft_pp}" >> "${csv_file}"

        IFS=',' read -r in_tg out_tg ttft_tg < <(run_one_bench "${label}" "tg" "${d}" "${TG_OUTPUT_LEN}")
        echo "tg,${d},${in_tg},${out_tg},${ttft_tg}" >> "${csv_file}"
    done

    stop_server
}

build_report() {
    local base_csv="${OUT_DIR}/base_metrics.csv"
    local cand_csv="${OUT_DIR}/candidate_metrics.csv"
    local report_md="${OUT_DIR}/comparison.md"

    python3 - "${base_csv}" "${cand_csv}" "${report_md}" <<'PYEOF'
import csv, sys
base_csv, cand_csv, report = sys.argv[1:4]

def load(path):
    m = {}
    with open(path, newline='', encoding='utf-8') as f:
        r = csv.DictReader(f)
        for row in r:
            k = (row['phase'], row['depth'])
            m[k] = {
                'input_tps': float(row['input_tps']),
                'output_tps': float(row['output_tps']),
                'ttft_ms': float(row['ttft_ms']),
            }
    return m

def pct(new, old):
    if old == 0:
        return 0.0
    return (new - old) / old * 100.0

base = load(base_csv)
cand = load(cand_csv)
keys = sorted(set(base.keys()) & set(cand.keys()), key=lambda x: (x[0], int(x[1])))

lines = []
lines.append('# A/B Comparison: base vs candidate')
lines.append('')
lines.append('| Phase |  Depth | Input t/s (base) | Input t/s (cand) |   Delta | Output t/s (base) | Output t/s (cand) |   Delta | TTFR ms (base) | TTFR ms (cand) |   Delta |')
lines.append('|-------|-------:|-----------------:|-----------------:|--------:|------------------:|------------------:|--------:|---------------:|---------------:|--------:|')

for k in keys:
    b = base[k]
    c = cand[k]
    lines.append(
        f"| {k[0]:<5} | {k[1]:>6} | {b['input_tps']:>16.2f} | {c['input_tps']:>16.2f} | {pct(c['input_tps'], b['input_tps']):>+6.1f}% | "
        f"{b['output_tps']:>17.2f} | {c['output_tps']:>17.2f} | {pct(c['output_tps'], b['output_tps']):>+6.1f}% | "
        f"{b['ttft_ms']:>14.2f} | {c['ttft_ms']:>14.2f} | {pct(c['ttft_ms'], b['ttft_ms']):>+6.1f}% |"
    )

with open(report, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
print(report)
PYEOF
}

echo "[i] Output directory: ${OUT_DIR}"

run_matrix_for_image "base" "${BASE_IMAGE}"
run_matrix_for_image "candidate" "${CANDIDATE_IMAGE}"
REPORT_PATH="$(build_report)"

echo "[ok] A/B benchmark completed"
echo "[ok] Base CSV      : ${OUT_DIR}/base_metrics.csv"
echo "[ok] Candidate CSV : ${OUT_DIR}/candidate_metrics.csv"
echo "[ok] Comparison MD : ${REPORT_PATH}"
