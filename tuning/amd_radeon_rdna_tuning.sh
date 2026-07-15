#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/rdna_detect.sh
source "$SCRIPT_DIR/../lib/rdna_detect.sh"

PCI_ID=""
GPUS_SELECTOR="${RDNA_GPUS:-}"
MEMORY_CLOCK_MHZ=""
UNDERVOLT_OFFSET_MV=""
TDP_WATTS=""
CORE_CLOCK_MAX_MHZ=""
FAN_SPEED_PCT=""
FAN_CURVE=""
FAN_AUTO=0
FAN_MINIMUM_PWM=""
FAN_TARGET_TEMP=""
ACOUSTIC_TARGET_RPM=""
ACOUSTIC_LIMIT_RPM=""
FAN_ZERO_RPM=""
LOCK_MEM_DPM_HIGH=0
LOCK_CORE_DPM_HIGH=0
DRY_RUN=0
STATUS_ONLY=0
RESET_ONLY=0

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat <<EOF
Usage: sudo ./$SCRIPT_NAME [options]

Tune an AMD Radeon Navi GPU through the amdgpu sysfs interface.

Options:
  --gpus SELECTOR         Which RDNA GPUs to act on. Forms:
                            all              every detected RDNA GPU (default)
                            N                first N RDNA GPUs (PCI-BDF order)
                            i,j,k            specific RDNA indices (zero-based)
                            BDF[,BDF...]     explicit PCI BDFs, e.g. 0000:03:00.0
                          Env-var fallback: RDNA_GPUS=<selector>
  --pci-id ID             Shorthand for --gpus <BDF>. PCI ID in the form
                          0000:XX:YY.Z. Mutually exclusive with --gpus.
  --memory-clock MHz      Set max memory clock. Default: unchanged
  --undervolt-offset mV   Set VDDGFX offset. Default: unchanged
  --tdp watts             Set board power cap in watts. Default: unchanged
  --core-clock-max MHz    Set max GPU core clock. Default: unchanged
  --fan-speed-pct PCT     Set fan speed to a fixed percentage (0-100). Enables manual fan control.
  --fan-curve CURVE       Set a custom 5-point fan curve. Format: "T0 P0 T1 P1 T2 P2 T3 P3 T4 P4"
                          where T=hotspot temp (°C), P=fan speed (%). Temps must be ascending.
                          Example: "25 25 50 30 70 34 85 37 100 40"
  --fan-auto              Return fan to automatic/driver-controlled speed
  --fan-minimum-pwm PCT   Set the minimum fan duty (%) the SMU is allowed to use
                          (gpu_od fan_minimum_pwm). Range is read from the node.
  --fan-target-temp C     Temperature (°C) the SMU tries to hold; below it the
                          fan stays near the acoustic target, above it ramps to
                          the acoustic limit (gpu_od fan_target_temperature).
  --acoustic-target-rpm R Fan RPM the SMU keeps below until fan-target-temp is
                          exceeded (gpu_od acoustic_target_rpm_threshold).
  --acoustic-limit-rpm R  Maximum fan RPM the SMU will ramp to at/above the
                          target temperature (gpu_od acoustic_limit_rpm_threshold).
  --fan-zero-rpm 0|1      Enable (1) or disable (0) zero-RPM idle, i.e. whether
                          the fan is allowed to stop when cool (gpu_od
                          fan_zero_rpm_enable). Not supported on every SKU.
  --lock-mem-dpm-high     Mask pp_dpm_mclk to the highest DPM level so the SMU
                          cannot demote memory clock under load. Useful for
                          memory-bandwidth-bound workloads (LLM decode).
  --lock-core-dpm-high    Same, but for pp_dpm_sclk (GPU core clock).
  --status                Print detected paths and current overdrive values, then exit
  --reset                 Reset overdrive values to driver defaults, then exit
  --dry-run               Show what would be written without changing anything
  -h, --help              Show this help message

Examples:
  sudo ./$SCRIPT_NAME                              # tune ALL detected RDNA GPUs
  sudo ./$SCRIPT_NAME --gpus 1                     # tune only the first one
  sudo ./$SCRIPT_NAME --gpus 0,2 --tdp 200         # tune RDNA indices 0 and 2
  sudo ./$SCRIPT_NAME --pci-id 0000:07:00.0 --core-clock-max 2550
  sudo ./$SCRIPT_NAME --status

Notes:
  * The kernel interface uses millivolts for voltage offset. The requested
    "-80mw" value is applied as -80 mV.
    * Overdrive must be enabled first.
        Fedora/RHEL example:
      sudo grubby --update-kernel=ALL --args="amdgpu.ppfeaturemask=0xffffffff"
        Ubuntu/Debian GRUB example:
            sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 amdgpu.ppfeaturemask=0xffffffff"/' /etc/default/grub
            sudo update-grub
    Then reboot.
EOF
}

log() {
    printf '[*] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

die() {
    printf '[x] %s\n' "$*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

reexec_as_root_if_needed() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        need_cmd sudo
        exec sudo -E bash "$0" "$@"
    fi
}

auto_detect_pci_id() {
    local detected
    detected=$(lspci -Dnnd 1002: | awk '/VGA compatible controller|Display controller|3D controller/ { print $1; exit }')
    [[ -n "$detected" ]] || die "Could not auto-detect an AMD GPU PCI ID. Use --pci-id."
    printf '%s\n' "$detected"
}

validate_pci_id() {
    [[ "$1" =~ ^0000:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]] || die "Invalid PCI ID: $1"
}

require_integer() {
    local value="$1"
    local name="$2"
    [[ "$value" =~ ^-?[0-9]+$ ]] || die "$name must be an integer, got: $value"
}

find_card_name() {
    local pci_id="$1"
    local drm_dir="/sys/bus/pci/devices/$pci_id/drm"
    [[ -d "$drm_dir" ]] || die "PCI device $pci_id not found or it has no DRM node."

    local card_name
    card_name=$(find "$drm_dir" -maxdepth 1 -mindepth 1 -printf '%f\n' | grep -E '^card[0-9]+$' | sort | head -n 1 || true)
    [[ -n "$card_name" ]] || die "Could not resolve a DRM card for $pci_id"
    printf '%s\n' "$card_name"
}

find_hwmon_dir() {
    local card_path="$1"
    find "$card_path/device/hwmon" -mindepth 1 -maxdepth 1 -type d -name 'hwmon*' | head -n 1 || true
}

find_gpu_od_fan_dir() {
    local card_path="$1"
    local d="$card_path/device/gpu_od/fan_ctrl"
    [[ -d "$d" ]] && printf '%s\n' "$d" || true
}

read_file_trimmed() {
    local path="$1"
    [[ -r "$path" ]] || return 1
    tr -d '\000\r' < "$path"
}

kernel_cmdline_has_ppfeaturemask() {
    grep -q 'amdgpu\.ppfeaturemask=' /proc/cmdline
}

die_overdrive_unavailable() {
    local pci_id="$1"
    local card_path="$2"
    local node="$card_path/device/pp_od_clk_voltage"

    if [[ ! -e "$node" ]]; then
        warn "The overdrive sysfs node does not exist for $pci_id: $node"
        if kernel_cmdline_has_ppfeaturemask; then
            die "Overdrive is still unavailable for this GPU even though a ppfeaturemask is present. Check whether this kernel/driver exposes pp_od_clk_voltage for your R9700."
        fi

        die "Overdrive is not enabled for this GPU. Your current kernel command line does not include amdgpu.ppfeaturemask. Enable it, reboot, then try again. On Ubuntu/Debian, add amdgpu.ppfeaturemask=0xffffffff to GRUB and run update-grub."
    fi

    if [[ ! -w "$node" ]]; then
        die "Found $node, but it is not writable. Run the script with sudo/root and make sure overdrive is enabled."
    fi
}

write_value() {
    local value="$1"
    local path="$2"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[dry-run] echo "%s" > %s\n' "$value" "$path"
        return 0
    fi

    printf '%s\n' "$value" > "$path"
}

# Returns 0 (success) on a successful write, or non-zero if the write fails.
# Unlike write_value, never aborts the script — caller decides how to react.
try_write_value() {
    local value="$1"
    local path="$2"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[dry-run] echo "%s" > %s\n' "$value" "$path"
        return 0
    fi

    printf '%s\n' "$value" > "$path" 2>/dev/null
}

# Parse the current OD state out of pp_od_clk_voltage so we can skip writes
# (and the matching commit) that wouldn't actually change anything.  The kernel
# rejects 'c' with -EINVAL ("Failed to upload overdrive table!") when there is
# nothing pending, so re-running the script with identical settings used to
# abort here.
read_current_od() {
    local source="$1" label="$2"
    case "$label" in
        vddgfx_offset)
            sed -nE 's/^OD_VDDGFX_OFFSET:[[:space:]]*$|^([-0-9]+)mV.*$/\1/p' <<< "$source" | grep -E '.' | head -n1
            ;;
        mclk_max)
            sed -nE 's/^1:[[:space:]]*([0-9]+)M[hH]z.*$/\1/p' <<< "$(awk '/^OD_MCLK:/{flag=1;next}/^OD_/{flag=0}flag' <<< "$source")" | head -n1
            ;;
        sclk_offset)
            sed -nE 's/^([-0-9]+)M[hH]z.*$/\1/p' <<< "$(awk '/^OD_SCLK_OFFSET:/{flag=1;next}/^OD_/{flag=0}flag' <<< "$source")" | head -n1
            ;;
    esac
}

extract_range_pair() {
    local label="$1"
    local source="$2"
    sed -nE "s/^(OD_)?${label}(_OFFSET)?:[[:space:]]*([-0-9]+)M[hH][zZ]?[[:space:]]+([-0-9]+)M[hH][zZ]?.*$/\3 \4/p" <<< "$source" | head -n 1
}

extract_voltage_range() {
    local source="$1"
    sed -nE 's/^(OD_)?VDDGFX_OFFSET:[[:space:]]*([-0-9]+)m[vV][[:space:]]+([-0-9]+)m[vV].*$/\2 \3/p' <<< "$source" | head -n 1
}

assert_in_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local label="$4"

    if (( value < min || value > max )); then
        die "$label $value is outside the supported range [$min, $max]"
    fi
}

# Generic setter for the single-value gpu_od/fan_ctrl/* nodes
# (fan_minimum_pwm, fan_target_temperature, acoustic_*_rpm_threshold,
# fan_zero_rpm_enable).  Each of these stages the value in an in-memory OD
# table and only applies it once 'c' is written back to the same node, exactly
# like fan_curve.  Validates against the node's own OD_RANGE when present.
#   $1 fan_ctrl dir   $2 card name   $3 node filename
#   $4 requested value   $5 OD_RANGE label   $6 human-readable label
set_od_fan_scalar() {
    local fan_dir="$1" card="$2" node_file="$3" value="$4" range_label="$5" human="$6"
    local node="$fan_dir/$node_file"

    if [[ -z "$fan_dir" || ! -w "$node" ]]; then
        warn "$node_file not available/writable for $card; skipping $human"
        return 0
    fi

    # Validate against the node's advertised OD_RANGE if it exposes one.
    local node_dump rng rmin rmax
    node_dump="$(read_file_trimmed "$node" || true)"
    rng="$(sed -nE "s/^${range_label}:[[:space:]]*([-0-9]+)[[:space:]]+([-0-9]+).*$/\1 \2/p" <<< "$node_dump" | head -n1)"
    if [[ -n "$rng" ]]; then
        read -r rmin rmax <<< "$rng"
        assert_in_range "$value" "$rmin" "$rmax" "$human"
    fi

    log "Setting $human: $value ($node_file)"
    write_value "$value" "$node"
    if ! try_write_value "c" "$node"; then
        warn "$human commit ('c') was rejected; may not have taken effect"
    fi
}

show_status() {
    local pci_id="$1"
    local card_name="$2"
    local card_path="$3"
    local hwmon_dir="$4"

    printf 'PCI ID      : %s\n' "$pci_id"
    printf 'DRM card    : %s\n' "$card_name"
    printf 'Card path   : %s\n' "$card_path"
    if [[ -n "$hwmon_dir" ]]; then
        printf 'HWMON path  : %s\n' "$hwmon_dir"
    else
        printf 'HWMON path  : not found\n'
    fi
    printf '\npp_od_clk_voltage:\n'
    read_file_trimmed "$card_path/device/pp_od_clk_voltage" || true
    printf '\npower_dpm_force_performance_level:\n'
    read_file_trimmed "$card_path/device/power_dpm_force_performance_level" || true
    if [[ -n "$hwmon_dir" && -r "$hwmon_dir/power1_cap" ]]; then
        local power_uw power_w
        power_uw=$(<"$hwmon_dir/power1_cap")
        power_w=$(( power_uw / 1000000 ))
        printf '\npower1_cap  : %s uW (~%s W)\n' "$power_uw" "$power_w"
    fi
    if [[ -n "$hwmon_dir" && -r "$hwmon_dir/pwm1" ]]; then
        local pwm_val pct
        pwm_val=$(<"$hwmon_dir/pwm1")
        pct=$(( pwm_val * 100 / 255 ))
        printf '\nfan pwm     : %s (~%s%%)\n' "$pwm_val" "$pct"
    fi
    local gpu_od_fan_dir
    gpu_od_fan_dir="$(find_gpu_od_fan_dir "$card_path")"
    if [[ -n "$gpu_od_fan_dir" && -r "$gpu_od_fan_dir/fan_curve" ]]; then
        printf '\nfan_curve (gpu_od):\n'
        cat "$gpu_od_fan_dir/fan_curve"
        local fan_node
        for fan_node in fan_minimum_pwm fan_target_temperature \
                        acoustic_target_rpm_threshold acoustic_limit_rpm_threshold \
                        fan_zero_rpm_enable; do
            if [[ -r "$gpu_od_fan_dir/$fan_node" ]]; then
                printf '\n%s (gpu_od):\n' "$fan_node"
                cat "$gpu_od_fan_dir/$fan_node"
            fi
        done
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gpus)
                [[ $# -ge 2 ]] || die "--gpus requires a value"
                GPUS_SELECTOR="$2"
                shift 2
                ;;
            --pci-id)
                [[ $# -ge 2 ]] || die "--pci-id requires a value"
                PCI_ID="$2"
                shift 2
                ;;
            --memory-clock)
                [[ $# -ge 2 ]] || die "--memory-clock requires a value"
                MEMORY_CLOCK_MHZ="$2"
                shift 2
                ;;
            --undervolt-offset)
                [[ $# -ge 2 ]] || die "--undervolt-offset requires a value"
                UNDERVOLT_OFFSET_MV="$2"
                shift 2
                ;;
            --tdp)
                [[ $# -ge 2 ]] || die "--tdp requires a value"
                TDP_WATTS="$2"
                shift 2
                ;;
            --core-clock-max)
                [[ $# -ge 2 ]] || die "--core-clock-max requires a value"
                CORE_CLOCK_MAX_MHZ="$2"
                shift 2
                ;;
            --fan-speed-pct)
                [[ $# -ge 2 ]] || die "--fan-speed-pct requires a value"
                FAN_SPEED_PCT="$2"
                shift 2
                ;;
            --fan-curve)
                [[ $# -ge 2 ]] || die "--fan-curve requires a value"
                FAN_CURVE="$2"
                shift 2
                ;;
            --fan-auto)
                FAN_AUTO=1
                shift
                ;;
            --fan-minimum-pwm)
                [[ $# -ge 2 ]] || die "--fan-minimum-pwm requires a value"
                FAN_MINIMUM_PWM="$2"
                shift 2
                ;;
            --fan-target-temp)
                [[ $# -ge 2 ]] || die "--fan-target-temp requires a value"
                FAN_TARGET_TEMP="$2"
                shift 2
                ;;
            --acoustic-target-rpm)
                [[ $# -ge 2 ]] || die "--acoustic-target-rpm requires a value"
                ACOUSTIC_TARGET_RPM="$2"
                shift 2
                ;;
            --acoustic-limit-rpm)
                [[ $# -ge 2 ]] || die "--acoustic-limit-rpm requires a value"
                ACOUSTIC_LIMIT_RPM="$2"
                shift 2
                ;;
            --fan-zero-rpm)
                [[ $# -ge 2 ]] || die "--fan-zero-rpm requires a value (0 or 1)"
                FAN_ZERO_RPM="$2"
                shift 2
                ;;
            --lock-mem-dpm-high)
                LOCK_MEM_DPM_HIGH=1
                shift
                ;;
            --lock-core-dpm-high)
                LOCK_CORE_DPM_HIGH=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --status)
                STATUS_ONLY=1
                shift
                ;;
            --reset)
                RESET_ONLY=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

apply_to_gpu() {
    local PCI_ID="$1"
    validate_pci_id "$PCI_ID"

    if [[ -n "$MEMORY_CLOCK_MHZ" ]]; then require_integer "$MEMORY_CLOCK_MHZ" "memory clock"; fi
    if [[ -n "$UNDERVOLT_OFFSET_MV" ]]; then require_integer "$UNDERVOLT_OFFSET_MV" "undervolt offset"; fi
    if [[ -n "$TDP_WATTS" ]]; then require_integer "$TDP_WATTS" "TDP"; fi
    if [[ -n "$CORE_CLOCK_MAX_MHZ" ]]; then require_integer "$CORE_CLOCK_MAX_MHZ" "core clock max"; fi
    if [[ -n "$FAN_SPEED_PCT" ]]; then
        require_integer "$FAN_SPEED_PCT" "fan speed"
        (( FAN_SPEED_PCT >= 0 && FAN_SPEED_PCT <= 100 )) || die "Fan speed must be 0-100, got: $FAN_SPEED_PCT"
    fi
    if [[ -n "$FAN_CURVE" ]]; then
        local fc_arr
        read -r -a fc_arr <<< "$FAN_CURVE"
        [[ ${#fc_arr[@]} -eq 10 ]] || die "--fan-curve requires exactly 10 values (T0 P0 T1 P1 ... T4 P4), got ${#fc_arr[@]}"
        local i prev_t=-1
        for (( i=0; i<10; i+=2 )); do
            require_integer "${fc_arr[$i]}" "fan curve temp[$((i/2))]"
            require_integer "${fc_arr[$((i+1))]}" "fan curve speed[$((i/2))]"
            (( fc_arr[i] > prev_t )) || die "Fan curve temperatures must be strictly ascending (point $((i/2)))"
            prev_t=${fc_arr[$i]}
        done
    fi
    if [[ "$FAN_AUTO" -eq 1 && ( -n "$FAN_SPEED_PCT" || -n "$FAN_CURVE" ) ]]; then
        die "--fan-auto cannot be combined with --fan-speed-pct or --fan-curve"
    fi
    if [[ -n "$FAN_SPEED_PCT" && -n "$FAN_CURVE" ]]; then
        die "--fan-speed-pct and --fan-curve are mutually exclusive"
    fi
    if [[ -n "$FAN_MINIMUM_PWM" ]]; then
        require_integer "$FAN_MINIMUM_PWM" "fan minimum pwm"
        (( FAN_MINIMUM_PWM >= 0 && FAN_MINIMUM_PWM <= 100 )) || die "Fan minimum pwm must be 0-100, got: $FAN_MINIMUM_PWM"
    fi
    if [[ -n "$FAN_TARGET_TEMP" ]]; then require_integer "$FAN_TARGET_TEMP" "fan target temperature"; fi
    if [[ -n "$ACOUSTIC_TARGET_RPM" ]]; then require_integer "$ACOUSTIC_TARGET_RPM" "acoustic target rpm"; fi
    if [[ -n "$ACOUSTIC_LIMIT_RPM" ]]; then require_integer "$ACOUSTIC_LIMIT_RPM" "acoustic limit rpm"; fi
    if [[ -n "$FAN_ZERO_RPM" ]]; then
        [[ "$FAN_ZERO_RPM" == "0" || "$FAN_ZERO_RPM" == "1" ]] || die "--fan-zero-rpm must be 0 or 1, got: $FAN_ZERO_RPM"
    fi
    if [[ -n "$ACOUSTIC_TARGET_RPM" && -n "$ACOUSTIC_LIMIT_RPM" ]] \
        && (( ACOUSTIC_TARGET_RPM > ACOUSTIC_LIMIT_RPM )); then
        die "--acoustic-target-rpm ($ACOUSTIC_TARGET_RPM) cannot exceed --acoustic-limit-rpm ($ACOUSTIC_LIMIT_RPM)"
    fi

    local card_name card_path hwmon_dir gpu_od_fan_dir od_dump od_range mclk_range sclk_range vddgfx_range
    local mclk_min mclk_max sclk_min sclk_max vddgfx_min vddgfx_max

    card_name="$(find_card_name "$PCI_ID")"
    card_path="/sys/class/drm/$card_name"
    hwmon_dir="$(find_hwmon_dir "$card_path")"
    gpu_od_fan_dir="$(find_gpu_od_fan_dir "$card_path")"

    [[ -w "$card_path/device/power_dpm_force_performance_level" ]] || die "Cannot write to $card_path/device/power_dpm_force_performance_level"
    die_overdrive_unavailable "$PCI_ID" "$card_path"

    if [[ "$STATUS_ONLY" -eq 1 ]]; then
        show_status "$PCI_ID" "$card_name" "$card_path" "$hwmon_dir"
        return 0
    fi

    log "Target GPU: $card_name ($PCI_ID)"
    log "Using card path: $card_path"

    if [[ "$RESET_ONLY" -eq 1 ]]; then
        log "Resetting overdrive clock/voltage values to defaults"
        # Order matters: OD writes require performance_level=manual.
        try_write_value "manual" "$card_path/device/power_dpm_force_performance_level" \
            || warn "Could not set performance_level=manual"
        try_write_value "r" "$card_path/device/pp_od_clk_voltage" \
            || warn "Could not stage OD reset (pp_od_clk_voltage 'r')"
        try_write_value "c" "$card_path/device/pp_od_clk_voltage" \
            || warn "Could not commit OD reset (pp_od_clk_voltage 'c') — usually means there was nothing to reset"

        # Explicitly unmask pp_dpm_mclk / pp_dpm_sclk by writing every level
        # index back.  Relying on performance_level=auto to clear the mask is
        # unreliable (the auto write itself sometimes fails silently after an
        # OD reset, leaving the previous mask in place — that was the cause
        # of the "one card stuck at 1258 MHz, the other at 96 MHz" asymmetry).
        local dpm_clk dpm_node dpm_levels
        for dpm_clk in mclk sclk; do
            dpm_node="$card_path/device/pp_dpm_${dpm_clk}"
            [[ -w "$dpm_node" ]] || continue
            dpm_levels=$(awk -F: '/^[[:space:]]*[0-9]+:/ { gsub(/ /,"",$1); printf "%s ", $1 }' "$dpm_node")
            if [[ -n "$dpm_levels" ]]; then
                log "Unmasking ${dpm_clk} DPM levels: ${dpm_levels% }"
                try_write_value "${dpm_levels% }" "$dpm_node" \
                    || warn "Could not unmask $dpm_node"
            fi
        done

        # Finally hand control back to the SMU so it can scale freely.
        try_write_value "auto" "$card_path/device/power_dpm_force_performance_level" \
            || warn "Could not switch to performance_level=auto"

        if [[ -n "$hwmon_dir" ]]; then
            local cap_default="$hwmon_dir/power1_cap_default"
            local cap_node="$hwmon_dir/power1_cap"
            if [[ -r "$cap_default" && -w "$cap_node" ]]; then
                local default_uw cur_uw
                default_uw=$(<"$cap_default")
                cur_uw=$(<"$cap_node")
                if [[ "$default_uw" == "$cur_uw" ]]; then
                    log "Power cap already at default $(( default_uw / 1000000 )) W; skipping"
                else
                    log "Resetting power cap to default: $(( default_uw / 1000000 )) W"
                    try_write_value "$default_uw" "$cap_node" \
                        || warn "Could not reset power cap (firmware refused write); leaving at $(( cur_uw / 1000000 )) W"
                fi
            else
                warn "Could not reset power cap: power1_cap_default not readable or power1_cap not writable"
            fi
            if [[ -e "$hwmon_dir/pwm1_enable" && -w "$hwmon_dir/pwm1_enable" ]]; then
                log "Resetting fan control to automatic"
                try_write_value "2" "$hwmon_dir/pwm1_enable" \
                    || warn "Could not reset pwm1_enable to automatic"
            fi
        fi
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            log "Resetting gpu_od fan curve to driver defaults"
            if try_write_value "r" "$gpu_od_fan_dir/fan_curve"; then
                # 'r' only stages the default table; a commit is required for
                # the SMU to actually drop back to the driver-controlled curve.
                try_write_value "c" "$gpu_od_fan_dir/fan_curve" \
                    || warn "Fan curve reset commit ('c') was rejected; curve may not have reverted"
            else
                warn "Could not reset gpu_od fan curve (firmware may have rejected EIO); leaving as-is"
            fi
        fi

        # Sanity report so asymmetric reset state is visible immediately.
        log "Post-reset state:"
        log "  performance_level: $(<"$card_path/device/power_dpm_force_performance_level" 2>/dev/null || echo '?')"
        log "  pp_dpm_mclk: $(awk '/\*/{print $1 $2}' "$card_path/device/pp_dpm_mclk" 2>/dev/null | tr '\n' ' ')(active marked with *)"

        log "Reset complete"
        return 0
    fi

    od_dump="$(read_file_trimmed "$card_path/device/pp_od_clk_voltage")"
    od_range="$(sed -n '/^OD_RANGE:/,$p' <<< "$od_dump")"

    mclk_range="$(extract_range_pair 'MCLK' "$od_range")"
    [[ -n "$mclk_range" ]] || die "Could not read MCLK range from pp_od_clk_voltage"
    read -r mclk_min mclk_max <<< "$mclk_range"

    sclk_range="$(extract_range_pair 'SCLK' "$od_range")"
    [[ -n "$sclk_range" ]] || die "Could not read SCLK range from pp_od_clk_voltage"
    read -r sclk_min sclk_max <<< "$sclk_range"

    vddgfx_range="$(extract_voltage_range "$od_range")"
    [[ -n "$vddgfx_range" ]] || die "Could not read VDDGFX offset range from pp_od_clk_voltage"
    read -r vddgfx_min vddgfx_max <<< "$vddgfx_range"

    if [[ -n "$MEMORY_CLOCK_MHZ" ]]; then assert_in_range "$MEMORY_CLOCK_MHZ" "$mclk_min" "$mclk_max" "Memory clock"; fi
    if [[ -n "$UNDERVOLT_OFFSET_MV" ]]; then assert_in_range "$UNDERVOLT_OFFSET_MV" "$vddgfx_min" "$vddgfx_max" "Undervolt offset"; fi
    if [[ -n "$CORE_CLOCK_MAX_MHZ" ]]; then assert_in_range "$CORE_CLOCK_MAX_MHZ" "$sclk_min" "$sclk_max" "Core clock max"; fi

    log "Switching GPU to manual performance mode"
    write_value "manual" "$card_path/device/power_dpm_force_performance_level"

    # Snapshot current OD state; only stage values that actually differ.
    # The kernel returns -EINVAL on commit if no pending change has actually
    # been queued (firmware refuses the "upload" since the table is identical).
    local cur_vddgfx cur_mclk cur_sclk pending=0
    cur_vddgfx="$(read_current_od "$od_dump" vddgfx_offset)"
    cur_mclk="$(read_current_od "$od_dump" mclk_max)"
    cur_sclk="$(read_current_od "$od_dump" sclk_offset)"

    if [[ -n "$UNDERVOLT_OFFSET_MV" ]]; then
        if [[ "$cur_vddgfx" == "$UNDERVOLT_OFFSET_MV" ]]; then
            log "Undervolt offset already ${UNDERVOLT_OFFSET_MV} mV; skipping"
        else
            log "Applying undervolt offset: ${UNDERVOLT_OFFSET_MV} mV (was ${cur_vddgfx:-?} mV)"
            write_value "vo $UNDERVOLT_OFFSET_MV" "$card_path/device/pp_od_clk_voltage"
            pending=1
        fi
    else
        log "Leaving undervolt offset unchanged"
    fi

    if [[ -n "$MEMORY_CLOCK_MHZ" ]]; then
        if [[ "$cur_mclk" == "$MEMORY_CLOCK_MHZ" ]]; then
            log "Max memory clock already ${MEMORY_CLOCK_MHZ} MHz; skipping"
        else
            log "Applying max memory clock: ${MEMORY_CLOCK_MHZ} MHz (was ${cur_mclk:-?} MHz)"
            write_value "m 1 $MEMORY_CLOCK_MHZ" "$card_path/device/pp_od_clk_voltage"
            pending=1
        fi
    else
        log "Leaving max memory clock unchanged"
    fi

    if [[ -n "$CORE_CLOCK_MAX_MHZ" ]]; then
        if [[ "$cur_sclk" == "$CORE_CLOCK_MAX_MHZ" ]]; then
            log "Core clock offset already ${CORE_CLOCK_MAX_MHZ} MHz; skipping"
        else
            log "Applying max core clock: ${CORE_CLOCK_MAX_MHZ} MHz (was ${cur_sclk:-?} MHz)"
            write_value "s 1 $CORE_CLOCK_MAX_MHZ" "$card_path/device/pp_od_clk_voltage"
            pending=1
        fi
    else
        log "Leaving max core clock unchanged"
    fi

    if (( pending == 1 )); then
        log "Committing overdrive changes"
        if ! try_write_value "c" "$card_path/device/pp_od_clk_voltage"; then
            warn "Commit returned EINVAL — firmware rejected the OD table. Settings may not have been applied. Check 'dmesg | grep overdrive'."
        fi
    else
        log "No overdrive changes to commit"
    fi

    if [[ -n "$TDP_WATTS" ]]; then
        if [[ -z "$hwmon_dir" || ! -e "$hwmon_dir/power1_cap" ]]; then
            warn "Could not find power1_cap under $card_path/device/hwmon; skipping TDP change"
        else
            local power_cap_min power_cap_max power_cap_default power_cap_cur target_power_uw
            target_power_uw=$(( TDP_WATTS * 1000000 ))
            power_cap_min=$(<"$hwmon_dir/power1_cap_min")
            power_cap_max=$(<"$hwmon_dir/power1_cap_max")
            power_cap_default=$(<"$hwmon_dir/power1_cap_default" 2>/dev/null || echo 0)
            power_cap_cur=$(<"$hwmon_dir/power1_cap")
            assert_in_range "$target_power_uw" "$power_cap_min" "$power_cap_max" "Power cap (uW)"

            if [[ "$target_power_uw" == "$power_cap_cur" ]]; then
                log "Board power cap already ${TDP_WATTS} W; skipping"
            else
                log "Applying board power cap: ${TDP_WATTS} W"
                if ! try_write_value "$target_power_uw" "$hwmon_dir/power1_cap"; then
                    # The R9700 firmware advertises power1_cap_max above the
                    # actual supported ceiling (e.g. reports 330 W but rejects
                    # anything > power1_cap_default = 300 W with EIO).  Warn
                    # and fall back to power1_cap_default so the rest of the
                    # tuning (fan curve etc.) still applies.
                    if (( power_cap_default > 0 )) && [[ "$power_cap_cur" != "$power_cap_default" ]]; then
                        warn "Firmware rejected ${TDP_WATTS} W (power1_cap_max=$((power_cap_max/1000000)) W is advertised but not honored). Falling back to default $((power_cap_default/1000000)) W."
                        try_write_value "$power_cap_default" "$hwmon_dir/power1_cap" \
                            || warn "Could not set power cap to default either; leaving at $((power_cap_cur/1000000)) W."
                    else
                        warn "Firmware rejected ${TDP_WATTS} W and current cap already matches default; leaving at $((power_cap_cur/1000000)) W."
                    fi
                fi
            fi
        fi
    else
        log "Leaving board power cap unchanged"
    fi

    # Pin DPM tables to top level so the SMU cannot demote clocks while
    # the workload looks "idle" (decode phase of an LLM is memory-bound but
    # very bursty and the SMU often drops mclk to 96/456 MHz mid-batch).
    local dpm_node
    for dpm_node in mclk:LOCK_MEM_DPM_HIGH sclk:LOCK_CORE_DPM_HIGH; do
        local clk="${dpm_node%%:*}"
        local flagvar="${dpm_node##*:}"
        local flagval="${!flagvar}"
        local sysnode="$card_path/device/pp_dpm_${clk}"
        if [[ "$flagval" != "1" ]]; then
            continue
        fi
        if [[ ! -w "$sysnode" ]]; then
            warn "Cannot write to $sysnode; skipping --lock-${clk}-dpm-high"
            continue
        fi
        # Each non-header line is "<index>: <freq>Mhz [*]". Pick the largest
        # index (top DPM state). Skip lines whose index isn't a digit (e.g.
        # the bogus "S: 0Mhz *" line some firmwares print for sclk).
        local top_idx
        top_idx=$(awk -F: '/^[[:space:]]*[0-9]+:/ { gsub(/ /,"",$1); idx=$1 } END { print idx }' "$sysnode")
        if [[ -z "$top_idx" ]]; then
            warn "Could not parse top DPM level from $sysnode; skipping"
            continue
        fi
        local top_freq
        top_freq=$(awk -v i="$top_idx" -F: '$1+0==i { sub(/[*[:space:]]/,"",$2); print $2 }' "$sysnode" | head -n1)
        log "Pinning ${clk} DPM to top level $top_idx (${top_freq})"
        if ! try_write_value "$top_idx" "$sysnode"; then
            warn "Failed to pin $sysnode to level $top_idx"
        fi
    done

    if [[ -n "$FAN_SPEED_PCT" ]]; then
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            # Clamp to hardware minimum of 25%
            local clamped_pct=$FAN_SPEED_PCT
            if (( clamped_pct < 25 )); then
                warn "Fan speed ${FAN_SPEED_PCT}% is below hardware minimum 25%; clamping to 25%"
                clamped_pct=25
            fi
            log "Setting flat fan curve: ${clamped_pct}% across all temperature points (gpu_od)"
            write_value "0 25 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "1 50 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "2 70 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "3 85 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            write_value "4 100 ${clamped_pct}" "$gpu_od_fan_dir/fan_curve"
            # The staged points above only modify the in-memory OD table; the
            # SMU keeps using its previous curve until a commit ('c') is written.
            # Without this the new values show up in a sysfs read-back but the
            # fan never actually follows them.
            if ! try_write_value "c" "$gpu_od_fan_dir/fan_curve"; then
                warn "Fan curve commit ('c') was rejected; flat fan curve may not have taken effect"
            fi
        elif [[ -n "$hwmon_dir" && -w "$hwmon_dir/pwm1" ]]; then
            local pwm_max=255
            [[ -r "$hwmon_dir/pwm1_max" ]] && pwm_max=$(<"$hwmon_dir/pwm1_max")
            local pwm_val=$(( FAN_SPEED_PCT * pwm_max / 100 ))
            if [[ -e "$hwmon_dir/pwm1_enable" && -w "$hwmon_dir/pwm1_enable" ]]; then
                log "Enabling manual fan control"
                write_value "1" "$hwmon_dir/pwm1_enable"
            fi
            log "Setting fan speed: ${FAN_SPEED_PCT}% (pwm ${pwm_val}/${pwm_max})"
            write_value "$pwm_val" "$hwmon_dir/pwm1"
        else
            warn "No writable fan control interface found for $card_name; skipping fan control"
        fi
    elif [[ -n "$FAN_CURVE" ]]; then
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            local fc_arr
            read -r -a fc_arr <<< "$FAN_CURVE"
            log "Setting fan curve (gpu_od):"
            local i pt
            for (( i=0, pt=0; i<10; i+=2, pt++ )); do
                local t=${fc_arr[$i]} p=${fc_arr[$((i+1))]}
                if (( p < 25 )); then
                    warn "Fan curve point ${pt}: speed ${p}% below hardware minimum 25%; clamping"
                    p=25
                fi
                log "  point ${pt}: ${t}C → ${p}%"
                write_value "${pt} ${t} ${p}" "$gpu_od_fan_dir/fan_curve"
            done
            # Staged points only modify the in-memory OD table. The SMU keeps
            # using its previous curve until a commit ('c') is written, so the
            # new curve shows up in a sysfs read-back but the fan never follows
            # it without this step.
            if ! try_write_value "c" "$gpu_od_fan_dir/fan_curve"; then
                warn "Fan curve commit ('c') was rejected; fan curve may not have taken effect"
            fi
        else
            warn "gpu_od fan_curve interface not available for $card_name; skipping fan curve"
        fi
    elif [[ "$FAN_AUTO" -eq 1 ]]; then
        if [[ -n "$gpu_od_fan_dir" && -w "$gpu_od_fan_dir/fan_curve" ]]; then
            log "Restoring gpu_od fan curve to driver defaults"
            write_value "r" "$gpu_od_fan_dir/fan_curve"
            # 'r' stages the default table; commit it so the SMU actually
            # returns to the driver-controlled curve.
            if ! try_write_value "c" "$gpu_od_fan_dir/fan_curve"; then
                warn "Fan curve reset commit ('c') was rejected; curve may not have reverted"
            fi
        elif [[ -n "$hwmon_dir" && -e "$hwmon_dir/pwm1_enable" && -w "$hwmon_dir/pwm1_enable" ]]; then
            log "Restoring automatic fan control"
            write_value "2" "$hwmon_dir/pwm1_enable"
        else
            warn "No writable fan control interface found for $card_name; skipping fan auto restore"
        fi
    else
        log "Leaving fan control unchanged"
    fi

    # Independent single-value fan knobs. These shape how the SMU blends the
    # curve with its acoustic targets, so they apply on top of (or instead of)
    # the curve handled above. Each is a no-op unless its flag was passed.
    if [[ -n "$FAN_MINIMUM_PWM" ]]; then
        set_od_fan_scalar "$gpu_od_fan_dir" "$card_name" fan_minimum_pwm \
            "$FAN_MINIMUM_PWM" MINIMUM_PWM "fan minimum pwm (%)"
    fi
    if [[ -n "$FAN_TARGET_TEMP" ]]; then
        set_od_fan_scalar "$gpu_od_fan_dir" "$card_name" fan_target_temperature \
            "$FAN_TARGET_TEMP" TARGET_TEMPERATURE "fan target temperature (°C)"
    fi
    if [[ -n "$ACOUSTIC_TARGET_RPM" ]]; then
        set_od_fan_scalar "$gpu_od_fan_dir" "$card_name" acoustic_target_rpm_threshold \
            "$ACOUSTIC_TARGET_RPM" ACOUSTIC_TARGET "acoustic target (rpm)"
    fi
    if [[ -n "$ACOUSTIC_LIMIT_RPM" ]]; then
        set_od_fan_scalar "$gpu_od_fan_dir" "$card_name" acoustic_limit_rpm_threshold \
            "$ACOUSTIC_LIMIT_RPM" ACOUSTIC_LIMIT "acoustic limit (rpm)"
    fi
    if [[ -n "$FAN_ZERO_RPM" ]]; then
        set_od_fan_scalar "$gpu_od_fan_dir" "$card_name" fan_zero_rpm_enable \
            "$FAN_ZERO_RPM" ZERO_RPM_ENABLE "fan zero-rpm enable"
    fi

    printf '\n'
    show_status "$PCI_ID" "$card_name" "$card_path" "$hwmon_dir"
}

main() {
    parse_args "$@"
    reexec_as_root_if_needed "$@"

    need_cmd lspci
    need_cmd find
    need_cmd grep
    need_cmd sed
    need_cmd awk

    if [[ -n "$PCI_ID" && -n "$GPUS_SELECTOR" ]]; then
        die "--pci-id and --gpus are mutually exclusive"
    fi

    local -a targets=()
    if [[ -n "$PCI_ID" ]]; then
        validate_pci_id "$PCI_ID"
        targets=("$PCI_ID")
    else
        # Default to "all" when nothing is specified.
        local selector="${GPUS_SELECTOR:-all}"
        mapfile -t targets < <(rdna_resolve_selector "$selector") \
            || die "Failed to resolve --gpus selector '$selector'"
    fi

    if (( ${#targets[@]} == 0 )); then
        die "No GPUs selected."
    fi

    log "Selected ${#targets[@]} GPU(s): ${targets[*]}"

    local idx=0 bdf
    for bdf in "${targets[@]}"; do
        idx=$((idx + 1))
        printf '\n==========================================================\n'
        printf ' GPU %d/%d: %s\n' "$idx" "${#targets[@]}" "$bdf"
        printf '==========================================================\n'
        apply_to_gpu "$bdf"
    done
}

main "$@"
