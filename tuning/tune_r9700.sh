#!/usr/bin/env bash
# tune_r9700.sh — Wrapper around amd_radeon_rdna_tunning.sh with opinionated
# defaults for the AMD Radeon AI PRO R9700 (Navi 48 / gfx1201).
#
# Run with no arguments to apply all defaults below.
# Any flag passed on the command line is forwarded to the generic script and
# will override the corresponding default (e.g. --tdp 180 overrides the 210 W
# default; --fan-curve overrides the built-in curve).
# --reset is handled specially: it bypasses all defaults and resets the card
# to driver defaults via the generic script.
set -euo pipefail

log() {
    printf '[*] %s\n' "$*"
}

# Resolve the generic tuner relative to this script so the wrapper works from
# any working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RDNA_SCRIPT="$SCRIPT_DIR/amd_radeon_rdna_tunning.sh"

if [[ ! -x "$RDNA_SCRIPT" ]]; then
    log "Error: Required script $RDNA_SCRIPT is missing or not executable." >&2
    exit 1
fi

# --reset needs no defaults — pass everything straight through so the generic
# script can cleanly restore driver defaults (clocks, voltage, power cap, fan).
for arg in "$@"; do
    if [[ "$arg" == "--reset" ]]; then
        log "Resetting R9700 overdrive values to driver defaults..."
        exec "$RDNA_SCRIPT" "$@"
    fi
done

log "Delegating to generic RDNA tuner with AMD Radeon AI PRO R9700 defaults..."
# Default values chosen for the R9700 (Navi 48 / gfx1201):
#   --memory-clock 1350   : max MCLK in MHz; the driver default is higher but
#                           causes instability on this chip
#   --undervolt-offset -75: VDDGFX core voltage offset in mV; reduces heat and
#                           power draw without triggering crashes
#   --tdp 210             : board power cap in watts; stock firmware allows ~230 W
#   --fan-curve           : 5-point temperature-to-speed ramp written to
#                           gpu_od/fan_ctrl/fan_curve (the Navi 48 interface).
#                           25% is the hardware minimum enforced by the driver.
#                             25°C → 25%  (idle)
#                             50°C → 30%
#                             70°C → 34%  (typical LLM inference load)
#                             85°C → 37%
#                            100°C → 40%  (peak)
#   "$@"                  : any flags passed by the caller are forwarded last,
#                           so they override the above defaults
exec "$RDNA_SCRIPT" \
    --gpus all \
    --memory-clock 1350 \
    --undervolt-offset -75 \
    --tdp 300 \
    --fan-curve "25 25 50 25 70 30 85 40 100 50" \
    "$@"
