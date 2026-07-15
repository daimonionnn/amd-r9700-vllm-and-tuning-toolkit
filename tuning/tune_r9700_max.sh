#!/usr/bin/env bash
# tune_r9700_max.sh — Wrapper around amd_radeon_rdna_tuning.sh with a
# max-performance profile for the AMD Radeon AI PRO R9700 (Navi 48 / gfx1201):
# 300 W cap and no fan curve (fan is left on the driver's automatic control).
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
RDNA_SCRIPT="$SCRIPT_DIR/amd_radeon_rdna_tuning.sh"

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
#   --tdp 300             : board power cap in watts; 300 W is the real firmware
#                           ceiling (the kernel advertises 330 W but the SMU
#                           rejects anything above 300 W — see docs/r9700-oc-uv-findings.md)
#   (no --fan-curve)      : this profile leaves the fan on the driver's automatic
#                           control. Pass --fan-curve "..." to override.
#   "$@"                  : any flags passed by the caller are forwarded last,
#                           so they override the above defaults
exec "$RDNA_SCRIPT" \
    --gpus all \
    --memory-clock 1350 \
    --undervolt-offset -75 \
    --tdp 300 \
    "$@"
# Removed flags (intentionally not applied on amdgpu DKMS 6.19.4):
#
#   --lock-mem-dpm-high     : only useful if DPM table actually has a 1350 step
#   --lock-core-dpm-high    : default SMU scheduling is already optimal
#
# NOTE: 300 W is the real firmware ceiling on the R9700.  The kernel advertises
# power1_cap_max=330 W but the SMU rejects anything above power1_cap_default
# (300 W) with EIO ("Input/output error").  Don't bump --tdp above 300 here.
#
# CAVEAT: a `\` line continuation cannot be preceded by a commented-out flag in
# the exec block above. `# ...flag... \` ends the logical command because `\`
# inside a comment does NOT continue the line — bash sees `exec ... --gpus all`
# only and silently drops every flag after the first comment. If you want to
# disable a flag, delete the line entirely (don't just prefix it with `#`).
