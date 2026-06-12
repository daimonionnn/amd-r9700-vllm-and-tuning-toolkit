#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# sweep-qwen36-27b.sh — context × concurrency sweep for
# RedHatAI/Qwen3.6-27B-FP8 on R9700 TP=2.
#
# Runs bench-qwen36-27b.sh twice per cell:
#   * PP pass (OUTPUT_LEN=1) → prefill throughput
#   * TG pass (OUTPUT_LEN=$TG_OUTPUT_LEN, default 512) → decode-mixed throughput
#
# All cells run with EAGER=1 (cudagraph capture currently hangs on
# Qwen3.6 GDN on this stack — see bench-qwen36-27b.sh header).
#
# Configurable via env:
#   CTXS         space-separated input lengths (default: "4096 16384")
#   CONCS        space-separated concurrencies (default: "1 2")
#   TG_OUTPUT_LEN tokens to generate in TG pass (default: 512)
#   MODE         "pp", "tg", or "both" (default: both)
#   TAG          extra label inserted into log filenames (default: stock)
#   LOG_DIR      where to write per-cell logs (default: /tmp)
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

CTXS="${CTXS:-4096 16384}"
CONCS="${CONCS:-1 2}"
TG_OUTPUT_LEN="${TG_OUTPUT_LEN:-512}"
MODE="${MODE:-both}"
TAG="${TAG:-stock}"
LOG_DIR="${LOG_DIR:-/tmp}"

mkdir -p "$LOG_DIR"

case "$MODE" in
    pp|tg|both) ;;
    *) echo "[x] MODE must be pp|tg|both (got: $MODE)" >&2; exit 1 ;;
esac

summary_file="$LOG_DIR/bench-${TAG}-summary.txt"
: > "$summary_file"

run_cell() {
    local pass="$1" ctx="$2" c="$3" out_len="$4" mml="$5"
    local tag="${pass}-ctx${ctx}_c${c}"
    local log="$LOG_DIR/bench-${TAG}-${tag}.log"

    echo "=================================================="
    echo "===== ${pass^^}  ctx=$ctx  c=$c   out=$out_len   $(date +%H:%M:%S) ====="
    echo "=================================================="

    EAGER=1 NUM_PROMPTS=$c INPUT_LEN=$ctx OUTPUT_LEN=$out_len MAX_MODEL_LEN=$mml \
        "$SCRIPT_DIR/bench-qwen36-27b.sh" 2>&1 \
        | tee "$log" \
        | grep -E "^Throughput:|Total num (prompt|output) tokens|ERROR|out of memory" || true

    local thr
    thr=$(grep -m1 "^Throughput:" "$log" || true)
    printf '%-4s ctx=%-6d c=%-2d  %s\n' "${pass^^}" "$ctx" "$c" "${thr#Throughput: }" >> "$summary_file"
}

echo "===== SWEEP START $(date +%F\ %H:%M:%S) ====="
echo "  CTXS=$CTXS   CONCS=$CONCS   MODE=$MODE   TAG=$TAG"
echo "  log dir: $LOG_DIR"
echo

for ctx in $CTXS; do
    for c in $CONCS; do
        if [[ "$MODE" == "pp" || "$MODE" == "both" ]]; then
            run_cell pp "$ctx" "$c" 1 "$((ctx + 128))"
        fi
        if [[ "$MODE" == "tg" || "$MODE" == "both" ]]; then
            run_cell tg "$ctx" "$c" "$TG_OUTPUT_LEN" "$((ctx + TG_OUTPUT_LEN + 128))"
        fi
    done
done

echo
echo "===== SWEEP DONE $(date +%F\ %H:%M:%S) ====="
echo
echo "Summary ($summary_file):"
cat "$summary_file"
