# R9700 Overclocking / Undervolting Findings

Community findings from [RDNA4 Llama Experiments — Squeezing Every Token/s from the R9700](https://github.com/ggml-org/llama.cpp/discussions/21043).

---

## LACT Settings (reported by zedbytes)

| Setting            | Value    |
|--------------------|----------|
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
> may fail to detect the GPU on some systems). It also fixes a second, less obvious
> symptom — LACT silently failing to apply the undervolt when its OD write races an
> SMU resume. If you would rather not disable runtime PM system-wide, a per-card udev
> rule does the same job: see
> [Runtime PM breaks the undervolt](#runtime-pm-breaks-the-undervolt-failed-to-upload-overdrive-table-august-4-2026).

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
|-------------------------------------|-------------|--------------|---------|
| **Firmware defaults (no tuning)**   | **585.87**  | **65.10**    | 3m16s   |
| Tuned (300 W, -50 mV, no MCLK OD)   | 560.38      | 62.26        | 3m25s   |
| Tuned (300 W, MCLK OD=1350, -70 mV) | 559.98      | 62.22        | 3m25s   |
| Tuned (300 W, MCLK OD=1350, -75 mV) | 560.68      | 62.30        | 3m25s   |

→ On this workload **firmware defaults beat the tuned profile by ~4.5 %**. The result is independent of undervolt magnitude — -50, -70 and -75 mV all collapse to ~560 tok/s (run-to-run noise band). The MCLK OD value is irrelevant here because it is silently capped (see DPM section below). **The undervolt itself is the cause**: the SMU treats any VDDGFX offset as a stability hint and shaves boost frequencies regardless of how small the offset is.

> **Platform migration update (June 17, 2026):** the above May-30 TP=2 numbers were
> taken on the Ryzen 5700G / B450 rig where the second card was stuck on a bifurcated
> Gen1/Gen2 x4 link, which crippled TP=2 (prefill ~333–620 t/s) and forced PP=2.
> After moving both R9700s to a new Intel Core Ultra 5 250K / Z890 board at full
> PCIe 5.0, TP=2 prefill recovers to ~1786–1841 t/s (~3–5.5×) while keeping ~80 t/s
> decode. Full results, methodology and caveats:
> [../benchmark/R9700_benchmarks.md](../benchmark/R9700_benchmarks.md#vllm-tp2--intel-z890-platform-migration-june-17-2026).
> The OC/UV conclusions below are unchanged (still a driver/firmware property, not
> platform-dependent).

### Power-cap firmware limits

- `power1_cap_min` = **210 W** (firmware floor, not a knob we set).
- `power1_cap_default` = **300 W**.
- `power1_cap_max` advertises **330 W** but the SMU rejects any write above 300 W with `EIO ("Input/output error")`. **300 W is the real ceiling** on this card/firmware.
- `amd_radeon_rdna_tuning.sh` now catches the EIO, warns, and falls back to default instead of aborting.

> **Superseded (August 2026):** 330 W now applies cleanly on the surviving card —
> `power1_cap` reads `330 W` and the card was measured drawing **393 W peak / ~320 W
> average** under load, which a 300 W cap could not permit. Whether that is a firmware
> or VBIOS change is unknown (the card had been through service). The EIO handling in
> the script is harmless either way. See
> [the undervolt sweep](#undervolt-reversal-it-now-helps-because-the-card-is-power-limited-august-4-2026)
> for what raising it actually buys — under sustained load, very little: the card hits
> the ~104 °C junction limit before the power limit.

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
- `amd_radeon_rdna_tuning.sh` gained `--lock-mem-dpm-high` / `--lock-core-dpm-high` flags that mask `pp_dpm_mclk` / `pp_dpm_sclk` to the top DPM level. Useful to test, but on this driver it only pins to 1258 MHz (not 1350), so the upside is small. The flags are *not* enabled by default in `tune_r9700_max.sh`.

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

---

## Undervolt reversal: it now helps, because the card is power-limited (August 4, 2026)

**This contradicts the May 30 finding above** ("firmware defaults beat the tuned profile
by ~4.5 %", "the SMU shaves boost frequencies") and the June one ("throughput is flat
across offsets"). Both were correct at the time. What changed is the hardware, not the
driver.

**Why the reversal makes sense.** Undervolting only buys throughput when a card is
*power*-limited: fewer watts per MHz means more MHz fit in the same budget. In June this
card was *thermally* limited — a defective cooler pinned it at 222 W, far below the 300 W
cap, so lowering voltage had nothing to give back. After the cooler was fixed
([retest](r9700-mem-vendor-bios-variance.md#post-rma-retest--the-defect-is-gone-august-4-2026))
the card runs at ~295 W against its cap, and the undervolt pays.

### Sweep (llama.cpp, Qwen3.6-27B-Q4_K_M, single GPU, `-r 1`)

| config             | pp2048  | pp32768   | tg32  | max sclk |
|:-------------------|--------:|----------:|------:|---------:|
| stock 0 mV, 300 W  | 997.32  | 674.11    | 27.19 | —        |
| −120 mV, 300 W     | 1093.61 | 734.24    | 27.54 | 3357 MHz |
| −140 mV, 300 W     | 1106.69 | 743.07    | 27.75 | 3369 MHz |
| −150 mV, 300 W     | 1113.28 | 746.89    | 27.75 | 3387 MHz |
| −150 mV, **330 W** | 1131.60 | **crash** | —     | 3355 MHz |
| −120 mV, **330 W** | 1113.69 | 747.97    | 27.78 | 3389 MHz |

Gains flatten fast: stock → −120 mV is **+8.9 %** on pp32768, −120 → −140 adds +1.2 %,
−140 → −150 adds +0.5 %. Beyond ~−120 mV the card is no longer voltage-limited.

### Stability limit: −150 mV + 330 W crashes

`−150 mV` alone was fine at 300 W. Raising the cap to 330 W (higher clocks → more voltage
needed) made the *same* offset fail on the deeper prompt:

```
amdgpu 0000:05:00.0: [gfxhub] page fault (src_id:0 ring:24 vmid:8 pasid:165)
  Process llama-bench ...  Faulty UTCL2 client ID: TCP (0x8)
  PERMISSION_FAULTS: 0x3
```

A compute-pipe page fault is the classic undervolt-instability signature. Note `pp2048`
had already passed in the same run — **short benchmarks do not prove stability**; it took
the deeper `pp32768` to break it. Neither knob was at fault alone; the combination was.
The process died but the GPU did not reset.

### Sustained validation of −120 mV

`benchmark/thermal-test.sh` (`pp131072`, ~10 min, hot card), against the same-day stock run:

| metric             | stock 0 mV         | **−120 mV**             |
|:-------------------|-------------------:|------------------------:|
| prefill            | 323.22 t/s         | **348.02 t/s** (+7.7 %) |
| core clock         | 3066 MHz           | **3303 MHz** (+7.7 %)   |
| power              | 295.3 W            | 293.4 W                 |
| junction           | 104.4 °C           | 104.4 °C                |
| hotspot − edge     | 37.4 (peak 39)     | 38.4 (peak 41)          |
| memory / mem clock | 76.5 °C / 1242 MHz | 76.2 °C / 1155 MHz      |

**+237 MHz for the same power** is the undervolt working exactly as intended. Cooling is
unaffected (delta still ~38 °C, nowhere near the defective 47 °C). Memory clock drops to
1155 MHz — the SMU shifts budget into the core, and since prefill improves, that is a good
trade.

**The 330 W cap barely matters under sustained load.** This run was at 330 W, yet averaged
293–301 W: the card hits the ~104 °C junction limit *before* the power limit. The +1.9 %
that 330 W showed in one-minute tests does not survive a long run. 300 W is fine.

### Recommended

```yaml
voltage_offset: -120     # validated short + 10 min sustained; ~90 % of the available gain
power_cap: 300.0         # 330 W adds nothing once thermally limited
performance_level: auto
# no max_memory_clock — see the memory-OC section below
```

−150 mV is *not* recommended: +0.5 % over −140 mV, and no headroom left if anything else
changes. Also note this card was unstable at −70 mV in June **while thermally defective** —
a hot die needs more voltage, so the fixed cooler is likely what opened up the −120 mV
range. Re-validate after any cooling change.

> **Verify LACT settings actually applied.** During this session three separate LACT
> changes (power cap, memory clock, voltage offset) did not reach the card despite the GUI
> and `/etc/lact/config.yaml` showing them. Always confirm against sysfs:
> `pp_od_clk_voltage` for the offset, `hwmon/*/power1_cap` for the cap, and `pp_dpm_mclk`
> (not `OD_MCLK`) for memory.

---

## Memory OC re-verified on the current stack — still capped, and it makes things worse (August 4, 2026)

Re-check of the `OD_MCLK` question on the surviving Samsung card. Stack: kernel
`7.0.0-28-generic`, **amdgpu DKMS 6.19.4** — i.e. the same DKMS build as the original
finding, so no reason to expect different semantics. Confirmed: none.

**The write is accepted and then ignored.** `m 1 1350` + commit `c` returned no error,
and `OD_MCLK` read back `1: 1350MHz` — but `pp_dpm_mclk` was byte-identical to the
baseline, still topping out at `5: 1258Mhz`. Reading `OD_MCLK` alone would make the OC
look successful; only the DPM table (and the clock under load) tells the truth.

**Under load it is worse than a no-op.** Same `pp32768` run, sampling `mclk` throughout:

| config          | max mclk     | distribution across samples               | prefill   |
|:----------------|-------------:|:------------------------------------------|----------:|
| stock (default) | **1258 MHz** | **1258 MHz in 457 of 488 samples (94 %)** | 674.1 t/s |
| `OD_MCLK` 1300  | **875 MHz**  | 875 (53 %), 96 (43 %), 772 (3 %)          | 676.4 t/s |
| `OD_MCLK` 1350  | **875 MHz**  | 875 / 772 / 96 — **never reached 1258**   | 676.5 t/s |

Stock holds the top memory step 94 % of the time. With either OC value applied it never
got there in 30 samples — at a 94 % base rate that is not sampling noise. So writing an
out-of-range `OD_MCLK` does not raise the ceiling; it **pins the memory clock ~30 % below
it**. This reproduces the "Samsung collapses to ~772–875 MHz" behaviour recorded in
[r9700-mem-vendor-bios-variance.md](r9700-mem-vendor-bios-variance.md#memory-overclock).

**1300 behaves exactly like 1350**, which rules out the obvious hypothesis that the
collapse is a reaction to overreaching: 1300 is only 42 MHz above the 1258 ceiling, 1350 is
92 MHz above, and both land on the same 875 MHz cap with the same prefill. The trigger is
**any** `OD_MCLK` above the firmware DPM top, not how far above it goes. There is therefore
no "safe" memory OC value to search for on this driver.

**Prefill cannot show this problem.** It is unchanged across all three configs
(676.5 / 676.4 / 674.1) because prefill is compute-bound. Only decode is memory-bound, and
the first attempts at measuring it were inconclusive: `tg32` gave 28.12 t/s with the OC vs
27.19 without, i.e. within single-run (`-r 1`) noise and slightly *favouring* the OC.

**A later clean A/B did reproduce the decode regression.** Same undervolt (−120 mV),
same cap (300 vs 299 W), memory OC the only variable:

| config                  | pp2048  | pp32768 | tg32      | max mclk             |
|:------------------------|--------:|--------:|----------:|:---------------------|
| no memory OC            | 1093.61 | 734.24  | **27.54** | 1258 MHz (94 %)      |
| `max_memory_clock` 1329 | 1100.53 | 728.26  | **25.72** | 1124 MHz (0 % @1258) |

Decode drops **−6.6 %** while both prefill figures stay inside noise — exactly the shape
predicted by a memory-clock cap. For scale, every other `tg32` measured that day landed in
a 27.2–28.2 band; 25.72 sits clearly outside it. This is the same direction as the −20 %
recorded for vLLM TP=2 in June, smaller because the stack and workload differ.

Note the clock settled at **1124 MHz** here rather than the 875 MHz seen with 1300/1350 —
the collapse does not land on a fixed value, but the top 1258 MHz step is unreachable in
every case.

**Verdict: no upside, a measurable downside.** Leave `OD_MCLK` alone. Re-test only if a
DKMS release later than 6.19.4 restores replace-the-DPM-step semantics (TODO item 4).

Reverting is `r` + `c` to `pp_od_clk_voltage`; verify with `pp_dpm_mclk`, not `OD_MCLK`.

---

## Runtime PM breaks the undervolt: "Failed to upload overdrive table!" (August 4, 2026)

**Symptom.** With LACT managing the card, the kernel log repeats:

```
amdgpu 0000:05:00.0: Failed to upload overdrive table!
amdgpu 0000:05:00.0: Failed to upload customized OD settings
```

LACT itself logs `configuration applied` for the same moment, so the failure is silent
from userspace — and `pp_od_clk_voltage` still reads back the requested offset, which
makes it *look* applied. (Same trap as the fan curve: a read-back is **not** proof of a
successful SMU commit — see the fan-curve note in the root README.)

**Root cause: the OD upload fails only when it lands during a resume from runtime
suspend.** Correlating LACT's apply events against the kernel's
`SMU is resumed successfully!` lines isolates it exactly:

| time     | what happened                     | result             |
|:---------|:----------------------------------|:-------------------|
| 11:37:44 | apply at boot, card already awake | ✔ no error         |
| 11:52:03 | apply **during** `SMU is resumed` | ✖ failed to upload |
| 11:52:06 | apply, card already awake         | ✔ no error         |
| 11:52:14 | apply **during** `SMU is resumed` | ✖ failed to upload |
| 11:56:23 | apply **during** `SMU is resumed` | ✖ failed to upload |
| 11:59:31 | apply with `power/control=on`     | ✔ no error         |

The 11:52:06 row is the control case: same daemon, same config, but the card was already
awake, so it succeeded. It is **not** every apply that fails — only the ones racing the
SMU resume. Idle cards get suspended by runtime PM (`runtime_status: suspended`, D3hot),
and while suspended most SMU-backed sysfs nodes return `Device or resource busy`
(`power_dpm_force_performance_level`, `pp_dpm_sclk`, hwmon sensors) or hang.

**Two fixes.** Both stop the card from suspending, so an OD write can never race a
resume. The cost is that the card no longer parks in its low-power state — a spot check
showed ~10 W suspended vs ~14 W awake-and-idle (single sample, not a careful power
measurement).

**A — udev rule (targeted, recommended).** Applies to this card only, leaves every other
PCIe device's power management alone, and needs no kernel parameter or reboot-time
cmdline change:

```bash
sudo tee /etc/udev/rules.d/99-amdgpu-r9700-no-runtime-pm.rules >/dev/null <<'EOF'
# R9700 (Navi 48): disable runtime PM — otherwise LACT's OD-table write can land
# during an SMU resume and fail ("Failed to upload overdrive table!")
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x7551", ATTR{power/control}="on"
EOF
sudo udevadm control --reload-rules
```

The `99-` prefix matters: it loads *after* the system's `60-autosuspend.rules`, so it wins.
Verify the rule matches before rebooting (test mode does not write, it only reports):

```bash
udevadm test --action=add /sys/bus/pci/devices/0000:05:00.0 2>&1 | grep power/control
# -> 99-amdgpu-r9700-no-runtime-pm.rules:3 ATTR{power/control}="on": ... skipping writing "on" ...
```

**B — `amdgpu.runpm=0` boot arg (global).** Simpler, but disables runtime PM for *every*
amdgpu device and needs a reboot:

```
GRUB_CMDLINE_LINUX_DEFAULT="... amdgpu.runpm=0"
```

This is the same flag the [combined GRUB cmdline](#recommended-grub-cmdline-combined)
already recommends for a different reason (`rocminfo` failing to detect the GPU) — the
two symptoms share this one root cause.

**Temporary test (no reboot, reverts on reboot):**

```bash
echo on | sudo tee /sys/bus/pci/devices/<BDF>/power/control
sudo systemctl restart lactd
journalctl -k -b | grep -i overdrive   # no new failures = confirmed
```

**Verifying the offset really took.** `rocm-smi --showvoltage` is useless here — on this
card/driver it reports the *offset* (`30`), not VDDGFX. The practical check is the absence
of `Failed to upload overdrive table!` after an apply on an awake card; the read-back
alone is not sufficient.

> **Note on `configuration applied`:** LACT logs that line only when reapplying after a
> kernel DRM event. A fresh `systemctl restart lactd` does not log it (neither does the
> boot-time start), so its absence is normal and is **not** evidence that nothing was
> applied.

