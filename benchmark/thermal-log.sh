#!/usr/bin/env bash
# thermal-log.sh — sample R9700 telemetry to a clean CSV until killed.
#
# Polls `rocm-smi` at a fixed interval and appends one tidy row per GPU per
# sample. Designed to run in the background alongside a benchmark; stop it with
# SIGTERM/SIGINT (the orchestrator does this automatically).
#
# Usage:  thermal-log.sh OUTPUT.csv [INTERVAL_SEC]   (default interval: 2 s)
#
# Output columns (clean, ready for averaging — no parens / units inline):
#   epoch,device,edge_c,junction_c,memory_c,sclk_mhz,mclk_mhz,fan_rpm,power_w
#
# Column positions are resolved from the rocm-smi CSV header on every sample, so
# this keeps working if the field order changes between rocm-smi versions.
set -euo pipefail

OUT="${1:?usage: thermal-log.sh OUTPUT.csv [INTERVAL_SEC]}"
INTERVAL="${2:-2}"

printf 'epoch,device,edge_c,junction_c,memory_c,sclk_mhz,mclk_mhz,fan_rpm,power_w\n' >"$OUT"

# Clean shutdown on TERM/INT so the orchestrator can stop us mid-run.
RUNNING=1
trap 'RUNNING=0' TERM INT

while [[ "$RUNNING" == 1 ]]; do
    epoch="$(date +%s)"
    rocm-smi --showtemp --showpower --showclocks --showfan --csv 2>/dev/null \
        | awk -F',' -v epoch="$epoch" '
            # Strip everything but digits / dot from a clock cell like "(3171Mhz)".
            function num(s){ gsub(/[^0-9.]/,"",s); return s }
            NR==1 {
                for (i=1;i<=NF;i++) {
                    h=$i
                    if (h ~ /Sensor edge/)      ce=i
                    if (h ~ /Sensor junction/)  cj=i
                    if (h ~ /Sensor memory/)    cm=i
                    if (h ~ /^sclk clock speed/) cs=i
                    if (h ~ /^mclk clock speed/) ck=i
                    if (h ~ /Fan RPM/)          cf=i
                    if (h ~ /Package Power/)    cp=i
                }
                next
            }
            $1 ~ /^card[0-9]+$/ {
                printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n", \
                    epoch, $1, num($ce), num($cj), num($cm), \
                    num($cs), num($ck), num($cf), num($cp)
            }
        ' >>"$OUT"
    sleep "$INTERVAL"
done
