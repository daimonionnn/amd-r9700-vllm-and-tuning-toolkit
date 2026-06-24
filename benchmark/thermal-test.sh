#!/usr/bin/env bash
# thermal-test.sh — deep-prefill thermal test for the AMD Radeon AI PRO R9700.
#
# Reproduces the steady-state thermal characterization used to diagnose card2's
# thermal-interface deficit: runs a long single-pass prefill in llama.cpp while
# thermal-log.sh records junction/edge/memory temps, clocks, fan and power, then
# averages the last 30 % of samples (the steady-state window) and prints a
# summary table including the hotspot-edge delta (the key cooling-contact metric).
#
# Usage:
#   thermal-test.sh [--gpus SEL] [--model PATH] [--prompt N] [--interval S]
#
#   --gpus SEL     GPU selector forwarded to lib/rdna_detect.sh (default: all).
#                  Sets HIP_VISIBLE_DEVICES so llama.cpp targets that card.
#   --model PATH   GGUF model (default: Qwen3.6-27B-Q4_K_M from lmstudio cache).
#   --prompt N     Prefill length in tokens (default: 131072).
#   --interval S   Telemetry sample interval in seconds (default: 2).
#   --flash-attn 0|1  Flash attention (default: 1; required to fit 131072 f16 KV
#                  on a single 32 GB card and to match the original methodology).
#
# Artifacts land in benchmark/results/thermal_<timestamp>.{csv,log}.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$REPO_DIR/lib/rdna_detect.sh"

GPUS_SELECTOR="${RDNA_GPUS:-all}"
MODEL="$HOME/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf"
PROMPT_TOKENS=131072
INTERVAL=2
# Flash attention ON by default: required for a 131072-token f16 KV prefill to
# fit a single 32 GB R9700 (without it KV+model OOMs at the deepest ubatch) and
# matches the original deep-prefill methodology. Override with --flash-attn 0.
FLASH_ATTN=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpus)     GPUS_SELECTOR="$2"; shift 2 ;;
        --gpus=*)   GPUS_SELECTOR="${1#--gpus=}"; shift ;;
        --model)    MODEL="$2"; shift 2 ;;
        --model=*)  MODEL="${1#--model=}"; shift ;;
        --prompt)   PROMPT_TOKENS="$2"; shift 2 ;;
        --prompt=*) PROMPT_TOKENS="${1#--prompt=}"; shift ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --interval=*) INTERVAL="${1#--interval=}"; shift ;;
        --flash-attn) FLASH_ATTN="$2"; shift 2 ;;
        --flash-attn=*) FLASH_ATTN="${1#--flash-attn=}"; shift ;;
        -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "[x] unknown argument: $1" >&2; exit 1 ;;
    esac
done

BENCH_BIN="$REPO_DIR/llm/llama.cpp-rocm/bin/llama-bench"
VENV="$REPO_DIR/llm/rocm-venv/lib/python3.13/site-packages"

[[ -x "$BENCH_BIN" ]] || { echo "[x] $BENCH_BIN missing — compile llama.cpp-rocm first." >&2; exit 1; }
[[ -f "$MODEL"     ]] || { echo "[x] model not found: $MODEL" >&2; exit 1; }

# Full ROCm runtime path (post-OS-migration: no system /opt/rocm; libs live in
# the wheel-installed rocm-venv SDK packages).
export LD_LIBRARY_PATH="\
$REPO_DIR/llm/llama.cpp-rocm/lib:\
$VENV/_rocm_sdk_core/lib:\
$VENV/_rocm_sdk_core/lib/llvm/lib:\
$VENV/_rocm_sdk_libraries_gfx120X_all/lib:${LD_LIBRARY_PATH:-}"

mapfile -t SELECTED_BDFS < <(rdna_resolve_selector "$GPUS_SELECTOR") \
    || { echo "[x] failed to resolve --gpus '$GPUS_SELECTOR'" >&2; exit 1; }
HIP_INDICES="$(printf '%s\n' "${SELECTED_BDFS[@]}" | bdf_to_runtime_indices)"
export HIP_VISIBLE_DEVICES="$HIP_INDICES"
export GPU_MAX_HW_QUEUES=1

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$REPO_DIR/benchmark/results"
mkdir -p "$RESULTS_DIR"
CSV="$RESULTS_DIR/thermal_${STAMP}.csv"
LOG="$RESULTS_DIR/thermal_${STAMP}.log"

echo "=========================================================="
echo " R9700 deep-prefill thermal test"
echo " Model   : $MODEL"
echo " Prompt  : $PROMPT_TOKENS tokens (single pass, no warmup, flash-attn=$FLASH_ATTN)"
echo " GPUs    : ${#SELECTED_BDFS[@]} (${SELECTED_BDFS[*]}) HIP_VISIBLE_DEVICES=$HIP_INDICES"
echo " Telemetry: $CSV (every ${INTERVAL}s)"
echo "=========================================================="

# Start telemetry logger in the background, ensure it is stopped on any exit.
"$SCRIPT_DIR/thermal-log.sh" "$CSV" "$INTERVAL" &
LOG_PID=$!
cleanup() { kill "$LOG_PID" 2>/dev/null || true; wait "$LOG_PID" 2>/dev/null || true; }
trap cleanup EXIT

# Run the prefill; tee the bench output so we capture the reported t/s.
# Disable errexit around the pipeline so a benchmark abort (e.g. an OOM at the
# deepest ubatch) still lets us print the steady-state thermal summary — the
# telemetry up to the crash is valid and is the whole point of this test.
set +e
"$BENCH_BIN" -m "$MODEL" -p "$PROMPT_TOKENS" -n 0 --no-warmup -r 1 -ngl 99 -fa "$FLASH_ATTN" 2>&1 | tee "$LOG"
BENCH_RC=${PIPESTATUS[0]}
set -e

cleanup
trap - EXIT

if [[ "$BENCH_RC" -ne 0 ]]; then
    echo
    echo "[!] benchmark exited non-zero (rc=$BENCH_RC) — likely a VRAM OOM at the"
    echo "    deepest ubatch (f16 KV for $PROMPT_TOKENS tokens + model may exceed"
    echo "    card VRAM). Thermal telemetry below is still valid up to the abort;"
    echo "    lower --prompt or quantize KV for a completing run with a t/s number."
fi

echo
echo "=========================================================="
echo " Steady-state averages (last 30 % of ACTIVE samples)"
echo "=========================================================="

# Average only samples under real load (power > 100 W) so model-load ramp and any
# post-crash idle tail don't skew the steady-state window.
awk -F',' '
    NR>1 && $9>100 { n++; for (c=3;c<=9;c++) v[n,c]=$c; dev[n]=$2 }
    END {
        if (n==0) { print "no active telemetry samples captured"; exit 1 }
        start = int(n*0.7); if (start<1) start=1
        cnt=0
        for (i=start;i<=n;i++) {
            cnt++
            edge+=v[i,3]; junc+=v[i,4]; mem+=v[i,5]
            sclk+=v[i,6]; mclk+=v[i,7]; fan+=v[i,8]; pwr+=v[i,9]
            d=v[i,4]-v[i,3]; if (d>peakd) peakd=d
            avgd+=d
            d2=dev[i]
        }
        printf "  device            : %s\n", d2
        printf "  samples (window)  : %d of %d active\n", cnt, n
        printf "  junction (hotspot): %6.1f C\n", junc/cnt
        printf "  edge (heatsink)   : %6.1f C\n", edge/cnt
        printf "  hotspot - edge    : %6.1f C  (peak %.0f)\n", avgd/cnt, peakd
        printf "  memory            : %6.1f C\n", mem/cnt
        printf "  power             : %6.1f W\n", pwr/cnt
        printf "  core clock (sclk) : %6.0f MHz\n", sclk/cnt
        printf "  mem clock (mclk)  : %6.0f MHz\n", mclk/cnt
        printf "  fan               : %6.0f rpm\n", fan/cnt
    }
' "$CSV"

# Pull the t/s cell out of the llama-bench results table (… | ppN | <t/s> ± sd |).
TPS="$(awk -F'|' '/\| *pp[0-9]+ *\|/ { gsub(/ /,"",$(NF-1)); sub(/±.*/,"",$(NF-1)); v=$(NF-1) } END{ print (v?v:"n/a (run did not complete)") }' "$LOG")"
echo
echo "  prefill: $TPS t/s"
echo "  raw telemetry: $CSV"
echo "  bench log    : $LOG"
