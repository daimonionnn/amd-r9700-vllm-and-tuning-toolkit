# R9700 Overclocking / Undervolting Findings

Community findings from [RDNA4 Llama Experiments — Squeezing Every Token/s from the R9700](https://github.com/ggml-org/llama.cpp/discussions/21043).

---

## LACT Settings (reported by zedbytes)

| Setting            | Value    |
| ------------------ | -------- |
| Power limit        | 210 W    |
| GPU Clock Offset   | -500 MHz |
| Max VRAM Clock     | 2518 MHz |
| Min VRAM Clock     | 194 MHz  |
| GPU Voltage Offset | -88 mV   |

---

## Safe Power Boost (reported by digitalscream)

- Set power limit to **330 W** and profile to **COMPUTE** in LACT
- Result: +6% TG on dual-GPU setup (102 → 110 t/s)

> **WARNING:** Do NOT touch memory clocks in LACT — the detected defaults are wrong.
> Changing them can cause fans to max out, GPU to become undetectable, and may
> require booting into recovery mode and deleting `/etc/lact/config.yaml` to recover.

---

## Performance Level

### Option A — sysfs (per card)

```bash
echo "high" > /sys/class/drm/card1/device/power_dpm_force_performance_level
```

### Option B — rocm-smi

```bash
rocm-smi --setperflevel auto
```

> **Finding (yiwiz-sai):** `auto` outperforms `high` during sustained compute workloads.
> Under full LLM inference load, `auto` reaches 3000+ MHz SCLK while using only ~20 W
> idle (vs ~50 W for `high`). Use `auto` unless you have a specific reason for `high`.

---

## PCIe ASPM Performance Mode

**+10.8% decode speed on dense models (27B)** by eliminating PCIe L1 exit latency.

```bash
echo "performance" | sudo tee /sys/module/pcie_aspm/parameters/policy
```

To make persistent, add to kernel boot parameters in `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="... pcie_aspm.policy=performance"
```

Then run `sudo update-grub`.

> **Note:** Only dense models benefit significantly (+10.8%). MoE models see ~0% gain
> because they batch work more efficiently and hide PCIe latency.

---

## Disable ECC (~1 t/s decode gain)

Add to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`:

```
amdgpu.ras_enable=0
```

Run `sudo update-grub` and reboot. Verify with:

```bash
cat /sys/module/amdgpu/parameters/ras_enable
```

---

## Recommended GRUB Cmdline (combined)

```
GRUB_CMDLINE_LINUX_DEFAULT="amdgpu.runpm=0 pcie_aspm.policy=performance amdgpu.ras_enable=0"
```

> `amdgpu.runpm=0` is added to prevent GPU wake-up issues (without it, `rocminfo`
> may fail to detect the GPU on some systems).

---

## Notes

- The R9700 uses a 256-bit memory bus (640 GB/s) — LLM decode is **memory-bandwidth bound**.
  Overclocking the GPU core has diminishing returns; VRAM clock and PCIe bandwidth matter more.
- Under ROCm/HIP with straight compute (no rendering), the GPU can auto-overclock to 3.4 GHz+.
- Trying to squeeze an extra 50–150 MHz from VRAM is the most impactful hardware-level change.

---

## Local bench findings (May 30, 2026 — 2× R9700, ROCm 7.14, kernel 6.17.0-29, amdgpu DKMS 6.19.4)

Hardware: 2× AMD R9700 (gfx1201), BDFs `0000:03:00.0` + `0000:0f:00.0`, vLLM 0.21.1rc1, FP8 (`RedHatAI/Qwen3.6-27B-FP8`), TP=2, cudagraph, 100 prompts × 1024 in / 512 out.

### Tuned vs firmware-default comparison

| Profile                             | total tok/s | output tok/s | runtime |
| ----------------------------------- | ----------- | ------------ | ------- |
| **Firmware defaults (no tuning)**   | **585.87**  | **65.10**    | 3m16s   |
| Tuned (300 W, -50 mV, no MCLK OD)   | 560.38      | 62.26        | 3m25s   |
| Tuned (300 W, MCLK OD=1350, -70 mV) | 559.98      | 62.22        | 3m25s   |
| Tuned (300 W, MCLK OD=1350, -75 mV) | 560.68      | 62.30        | 3m25s   |

→ On this workload **firmware defaults beat the tuned profile by ~4.5 %**. The result is independent of undervolt magnitude — -50, -70 and -75 mV all collapse to ~560 tok/s (run-to-run noise band). The MCLK OD value is irrelevant here because it is silently capped (see DPM section below). **The undervolt itself is the cause**: the SMU treats any VDDGFX offset as a stability hint and shaves boost frequencies regardless of how small the offset is.

### Power-cap firmware limits

- `power1_cap_min` = **210 W** (firmware floor, not a knob we set).
- `power1_cap_default` = **300 W**.
- `power1_cap_max` advertises **330 W** but the SMU rejects any write above 300 W with `EIO ("Input/output error")`. **300 W is the real ceiling** on this card/firmware.
- `amd_radeon_rdna_tunning.sh` now catches the EIO, warns, and falls back to default instead of aborting.

### DPM (PowerPlay) table — actual reachable clocks

```
pp_dpm_mclk:  0:96   1:456  2:772  3:875  4:1124  5:1258 MHz   ← max = 1258 MHz
pp_dpm_sclk:  S:0    1:500           2:2350 MHz                ← max = 2350 MHz
```

- `OD_MCLK 1: 1350MHz` is **silently capped** by the current driver. The DPM table stays topped at 1258 MHz; the SMU never goes above it regardless of what is written to `pp_od_clk_voltage`.
- **Earlier behaviour (different driver build, LM Studio / llama.cpp tests, single GPU)**: the same `m 1 1350` write *did* replace the top DPM step and memory actually ran at 1350 MHz.
- Confirmed cause: **amdgpu DKMS 6.19.4** treats `OD_MCLK` as an OD-range ceiling only, not a replacement for the firmware-defined DPM step table. Single- vs dual-GPU has no effect — `pp_od_clk_voltage` is per-card.
- Workarounds:
  1. Live with 1258 MHz top (~7 % below 1350, and defaults already win the bench anyway).
  2. Remove the DKMS module and rely on the in-tree `amdgpu` (loses other ROCm 7.14 features that depend on DKMS).
  3. Wait for AMD to restore the old OD semantics in a later DKMS release.

### Memory clock behaviour under load

- Without any DPM pinning, the SMU bounces MCLK through every level (`96 / 456 / 772 / 875 / 1124 / 1258` MHz) during inference, including dropping to 96 MHz between micro-batches. Both cards switch synchronously.
- During the FP8 bench the cards drew **150–200 W** of the 300 W cap — the workload is *not* power-limited at this seq length; it is dominated by prefill and (during decode) by the SMU's aggressive memory-clock demotion heuristic.
- `amd_radeon_rdna_tunning.sh` gained `--lock-mem-dpm-high` / `--lock-core-dpm-high` flags that mask `pp_dpm_mclk` / `pp_dpm_sclk` to the top DPM level. Useful to test, but on this driver it only pins to 1258 MHz (not 1350), so the upside is small. The flags are *not* enabled by default in `tune_r9700_max.sh`.

### Tuning script bugs found and fixed

- `pp_od_clk_voltage` commit (`echo c`) returns **EINVAL** when no OD setting actually changed (firmware refuses to "upload overdrive table"). Script now snapshots OD state and only stages writes that differ, and only commits if something is pending.
- `--reset` previously aborted with `printf: write error: Input/output error` because every write used the strict path. All reset writes are now tolerant (`try_write_value`) and only warn on EIO.
- `--reset` and `--status` used `exit 0` inside the per-GPU function, which killed the loop after the first card → second card was left in its previous (often masked) state. Changed to `return 0` so both cards get reset. This was the root cause of the "one card stuck at 1258 MHz, the other at 96 MHz" asymmetry.
- DPM masks set by `--lock-*-dpm-high` are now explicitly cleared by writing every available level index back to `pp_dpm_mclk` / `pp_dpm_sclk` (relying on `performance_level=auto` to clear the mask turned out to be unreliable after an OD reset).
- **Fan curve was never committed.** The `gpu_od/fan_ctrl/fan_curve` interface (and its siblings `fan_minimum_pwm`, `fan_target_temperature`, `acoustic_*_rpm_threshold`, `fan_zero_rpm_enable`) stage writes into an in-memory OD table; the SMU only applies them when you write `c` (commit) back to the node. The script wrote the 5 points (and `r` on reset/auto) but never committed, so the new curve appeared in a sysfs read-back yet the fan kept following the previous/default curve — the "fan curve doesn't behave as expected" symptom. Fixed by writing `c` after staging points in the `--fan-curve` and `--fan-speed-pct` paths, and after `r` in the `--fan-auto` / `--reset` paths. Confirmed against the kernel thermal ABI docs (each of those nodes documents "write 'c' to commit your changes").

### Recommendation for this card on the current stack

For vLLM / Triton FP8 inference on ROCm 7.14 with amdgpu DKMS 6.19.4: **do not apply OD MCLK or undervolt** — both hurt throughput, and the undervolt penalty does not scale with the offset (any offset costs roughly the same ~4.5 %). Useful knobs are limited to:

- Power cap (300 W is already default; only worth setting lower if you want a quieter / cooler profile).
- Fan curve (purely cosmetic / acoustic — no performance impact).
- `pcie_aspm.policy=performance` and `amdgpu.ras_enable=0` boot args (still valid per upstream findings above).

In other words, on this driver `tune_r9700_max.sh` is best run **without** `--memory-clock` and `--undervolt-offset`. The wrapper is left intact for reproducibility but those flags should be considered no-ops (or worse) for inference workloads.

### Editing `tune_r9700_max.sh` safely

A `\` line continuation **cannot** be preceded by a commented-out flag inside the `exec` block. `# ...flag... \` ends the logical command because `\` inside a comment does **not** continue the line — bash sees `exec ... --gpus all` only and silently drops every flag after the first comment, with no error. To disable a flag, delete the line entirely; do not just prefix it with `#`.

