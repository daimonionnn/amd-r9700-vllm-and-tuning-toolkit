# Dual-R9700 silicon variance: memory vendor, VBIOS, and per-card tuning

**Date:** 2026-06-22
**Rig:** 2× Gigabyte Radeon AI PRO R9700 (Navi 48, gfx1201), Intel Z890 platform, full PCIe 5.0 x16 per card
**Workload for validation:** vLLM TP2, `Qwen/Qwen3.6-27B-FP8`, aiter image `aml731/vllm-aiter:v0.20.2`
**Tuning tool:** LACT (`/etc/lact/config.yaml`, `lactd` enabled → re-applies on boot)

## TL;DR

The two "identical" R9700s are **not** identical silicon. They differ in GDDR6 **memory vendor** and **VBIOS revision**, and they tune differently as a result. Tune each card independently — never clone offsets.

- **card1 (03:00.0, SK Hynix, VBIOS F50):** core undervolt **−70 mV**, memory at default. The healthy card.
- **card2 (07:00.0, Samsung, VBIOS F40):** core undervolt **−30 mV** (conservative), memory at default. The flakier card, and — the key finding — it had a **thermal-interface defect** (see "Thermal investigation" below): it hit the ~110 °C junction throttle at ~70 W less power and ~340 MHz lower core than card1, so it ran ~6–10 % slower on prefill even though the silicon was fine. **This is fixed as of August 2026** — after an RMA round trip it now matches card1 (delta 47 → 37.4 °C, full 300 W budget): see [Post-RMA retest](#post-rma-retest--the-defect-is-gone-august-4-2026).
- **This depresses the repo's dual-GPU TP=2 prefill numbers.** vLLM TP=2 drives both cards in lockstep, so the throttled card2 gates the healthy card1 — the pair's ~1841–1894 t/s prefill is a *lower bound*. A healthy, well-cooled pair should land higher (a reproducible community 2× R9700 run reaches ~1965, and one report claims ~2500). See ["Consequence for the TP=2 prefill benchmarks"](#consequence-for-the-tp2-prefill-benchmarks).
- **Memory OC (1349 MHz) is not worth it on either card** — pointless on Hynix, actively harmful on Samsung.
- **Governor: `auto`.** Forcing `high`/`manual` regresses throughput.

> **Hardware status (2026-08):** card2 went out on an RMA claim and spent nearly a month
> in service (claim rejected — "fault not reproduced"); with the rig down to one card for
> that long, card1 (Hynix) was sold. card2 is back and **now measures healthy** — see
> [Post-RMA retest](#post-rma-retest--the-defect-is-gone-august-4-2026). So the pair
> described here no longer exists as a unit and the project is **on hold** until a second
> card is acquired (see the [root README](../README.md#project-status)). The findings below
> stand as the record of what these two specific cards did.

## Hardware identity — what differs and what doesn't

| Property          | card1 / GPU0                     | card2 / GPU1        |
|:------------------|:---------------------------------|:--------------------|
| PCI address       | `0000:03:00.0`                   | `0000:07:00.0`      |
| ASIC              | Navi 48 `1002:7551` rev c0       | identical           |
| Board (subsystem) | Gigabyte `1458:242f`             | identical           |
| **GDDR6 vendor**  | **SK Hynix**                     | **Samsung**         |
| **VBIOS**         | **113-R9700AT-F50** (2025/10/17) | **113-R9700AT-F40** |
| VRAM              | 32 GB, 256-bit GDDR6             | identical           |
| PCIe link         | x16 @ 32 GT/s                    | identical           |
| Power cap         | 300 W (max 330 W)                | identical           |
| SMU firmware      | `00.104.76.00`                   | identical           |

Memory vendor is read from `/sys/class/drm/cardN/device/mem_info_vram_vendor`; VBIOS from `rocm-smi --showvbios` (or the amdgpu dmesg `ATOM BIOS:` line).

So PCIe, power budget, board model, and SMU firmware are all the same. The real differences are **the die bin, the GDDR6 vendor, and the VBIOS V/F-curve revision** — which is why they undervolt and memory-OC differently.

## Undervolt (core VDDGFX offset)

Undervolt headroom is set by each die's minimum stable voltage (Vmin) — the single most die-to-die-variable parameter. The VBIOS V/F curve (F50 vs F40) shifts the absolute voltage a given offset lands at, so identical offsets aren't even the same operating point.

| card                | stable UV  | notes                                              |
|:--------------------|:-----------|:---------------------------------------------------|
| card1 (Hynix/F50)   | **−70 mV** |                                                    |
| card2 (Samsung/F40) | **−30 mV** | −40 mV also tested clean; will **not** take −70 mV |

### card2 undervolt sweep (vLLM TP2, depth 4096, model resident)

| offset                            | pp2048 (t/s) | tg32 (t/s)  | MES soft-timeouts | hard faults |
|----------------------------------:|-------------:|------------:|:-----------------:|:-----------:|
| −20 mV                            | 1762.9       | 78.1        | 1 (pre-existing)  | none        |
| −30 mV                            | 1765.6       | 78.7        | 0                 | none        |
| −40 mV                            | 1755.0       | 78.3        | 0                 | none        |
| **−30 mV** (final, d4096 + d8132) | 1761 / 1750  | 77.7 / 77.7 | 0                 | none        |

Landed at **−30 mV** for a safety margin (10 mV below the deepest validated-clean point). Throughput is flat across offsets — as expected, undervolting doesn't add t/s under a power cap; the win is lower voltage/power/heat at the same clocks.

**card2 pre-existing quirk:** intermittent `amdgpu 0000:07:00.0: MES(1) failed to respond to msg=INVALIDATE_TLBS` soft-timeouts appear under vLLM load **even at stock voltage (0 mV)** — observed at both 0 mV and undervolt. It is *not* undervolt-induced; treat a lone MES timeout as baseline noise. Real UV failure = GPU reset / ring timeout / HIP error / hang / garbled output (none of which occurred).

## Memory overclock

Stock top memory DPM state = **1258 MHz** (`rocm-smi -s` supported levels), so `max_memory_clock: 1349` is a real ~+7% OC. (The OD_MCLK "ceiling" readout fluctuates 1259/1354 and is unreliable — trust the DPM table.)

| card            | mem setting | pp2048 @ d4096 | tg32 @ d4096 | mclk under load      | verdict                   |
|:----------------|:------------|---------------:|-------------:|:---------------------|:--------------------------|
| card1 (Hynix)   | 1349        | 1759.8         | 77.8         | (no regression)      | pointless — no gain       |
| card1 (Hynix)   | **default** | 1754.0         | 78.5         | holds ~1258          | **kept**                  |
| card2 (Samsung) | 1349        | 1754.8         | **62.4**     | thrashes to ~772–875 | **harmful (−20% decode)** |
| card2 (Samsung) | **default** | 1753.9         | 78.5         | stable               | **kept**                  |

- **Samsung (card2)** cannot sustain 1349: the SMU collapses the memory clock to ~772–875 MHz under load and decode drops ~20%, erratically. It doesn't crash (it's "stable") — it just silently loses performance. Reverting restored decode to 78.5.
- **Hynix (card1)** tolerates 1349 with no regression but also no measurable benefit, so it's left at default.
- Earlier combined test (both cards @ 1354 MHz) regressed prefill −5…−8 % and decode −13…−31 % with the same DPM thrashing. Memory OC is a dead-end on this pair.

## Governor (force_performance_level)

`auto` is fastest. Both cards apply their undervolt fine while in `auto`. Tested alternatives regressed:

| governor | pp2048 @ d4096 | tg32 @ d4096 |
|:---------|---------------:|-------------:|
| **auto** | ~1755–1765     | ~78          |
| `high`   | 1710.6         | 64.9 (−20 %) |

Forcing `high` pins the top DPM step, which is *lower* than the auto governor's opportunistic ~3.3 GHz boost, and splits the 300 W budget worse. `manual` pins clocks low. Use `auto`.

## A note on the "benchmark from both cards"

vLLM TP2 runs the model **tensor-parallel across both GPUs simultaneously**, so every throughput number above is the **pair's** combined result — there is no separate per-GPU t/s for a single TP job. Each row isolates *one card's* setting while the other is held fixed, so the deltas are attributable to the changed card. GPU-local behavior (clocks, power, mclk DPM, kernel-log faults) was sampled per card and is reported in the per-card sections.

## Per-card raw silicon comparison (stock, single-GPU llama.cpp)

To test whether a previously-owned (returned) card was better silicon, both current cards were benchmarked **stock (0 mV, default mem, auto)**, one GPU at a time, with the same `llama.cpp` `llama-bench` / Qwen3.6-27B Q4_K_M command used historically. (HIP index→card confirmed by per-GPU power draw.)

| test    | returned card (ROCm 7.2.3, archived) | card1 (Hynix/F50) | card2 (Samsung/F40) |
|:--------|-------------------------------------:|------------------:|--------------------:|
| pp1024  | 1036.6                               | 1028.3            | 991.8               |
| pp4096  | 974.4                                | 958.8             | 916.2               |
| pp32768 | 659.5                                | 654.3             | 610.3               |
| tg128   | 27.42                                | 26.80             | 27.06               |

- **card1 ≈ the returned card** (within ~1–2 %, i.e. driver/run noise — the archived run was on ROCm 7.2.3). No silicon downgrade.
- **card2 is ~4–7 % slower on prefill** than card1 (pp1024 +3.7 %, pp4096 +4.6 %, pp32768 +7.2 % in card1's favour), but **decode is tied**. Prefill is compute/core-clock-bound, so this is card2's weaker **die bin** (same reason it won't undervolt past −30 mV), not the Samsung memory. Decode is memory-latency-bound and both run stock 1258 MHz, so it's equal.
- card2 underperforms three independent ways: shallower undervolt floor, intermittent MES timeouts under load, and ~5 % slower prefill. **Note (later finding):** the prefill/power gap is largely a **thermal-interface defect on card2**, not weaker silicon — see "Thermal investigation" below.

Note: these llama.cpp Q4_K_M single-GPU numbers are **not comparable** to the vLLM FP8 TP2 numbers elsewhere in this repo (different framework, quant, and 1 vs 2 GPUs). The memory OC that helped historically (~+4–5 %) is a no-op on the current driver (`OD_MCLK` capped at 1258 MHz), which explains most of the "OC+UV used to do better" memory.

### Deep prefill (131072-token context, stock, single-GPU)

Same `llama.cpp` run at `pp131072` (`-p 131072 -n 0 --no-warmup -r 1`, f16 KV), with per-GPU telemetry averaged over the active prefill window:

| metric         | card1 (Hynix/F50)    | card2 (Samsung/F40) |
|:---------------|---------------------:|--------------------:|
| prefill        | 320.75 t/s           | 298.26 t/s (−7.0 %) |
| avg power      | 296 W (at 300 W cap) | 230 W               |
| avg core clock | 3029 MHz             | 2808 MHz            |
| avg mem clock  | 1247 MHz             | 1246 MHz            |

- card1 is **+7.5 %** faster and is **power-limited** — it sits at 296 W (≈ the 300 W firmware cap) while holding ~3029 MHz core.
- card2 leaves ~70 W unused (230 W) yet runs ~221 MHz slower core (2808 MHz) → it is **boost/clock-limited, not power-limited**. The SMU/VBIOS won't push its core higher despite available power headroom — the hallmark of the weaker die bin (and/or the F40 boost table).
- Memory clock is **identical** (~1247 MHz, both pinned near the 1258 top) — so the deep-prefill gap is purely **core clock**, not memory. (Deep prefill keeps mclk high, unlike short-context/decode where the SMU thrashes it.)

This pinpoints the cause of card2's deficit: a ~7 % lower sustained core-clock ceiling.

**Power-delivery ruled out:** after physically swapping the PSU power cables between the two cards, the test was rerun and the behavior stayed with the *card*, not the cable — card1 (03:00.0) again held ~297 W / ~3050 MHz / 322.6 t/s, card2 (07:00.0) again only ~229 W / ~2867 MHz / 304.2 t/s. If a cable/rail were starving a card the 229 W ceiling would have moved to card1; it didn't. So it is the card — but **not the silicon** (see the thermal investigation below).

### Thermal investigation — the deficit is cooling, not silicon (corrects earlier conclusion)

Steady-state temps logged during stock `pp131072` (rocm-smi, last 30 % of the run):

| metric             | card1 (03:00.0) | card2 (07:00.0)     |
|:-------------------|----------------:|--------------------:|
| prefill            | 335.9 t/s       | 300.4 t/s           |
| junction (hotspot) | 108 °C          | **110 °C**          |
| edge (heatsink)    | 70 °C           | 62 °C               |
| **hotspot − edge** | 38 °C (peak 51) | **47 °C (peak 62)** |
| memory             | 88 °C           | 71 °C               |
| power              | 294 W           | **222 W**           |
| core clock         | 3171 MHz        | 2828 MHz            |
| fan                | 4568 rpm        | **3648 rpm**        |

Both cards hit the **~110 °C junction throttle limit**, but card2 reaches it at **70 W less power and ~340 MHz lower clock**. The cause is **worse die-to-heatsink heat transfer on card2**, not a weaker chip:

- Hotspot-to-edge delta is ~10 °C higher on card2 (47 vs 38) — the die is hot while the heatsink stays cool → poor thermal-interface contact (paste/mount).
- Edge only 62 °C while junction is 110 °C — heat isn't reaching the cooler body.
- Fan spins *slower* (3648 vs 4568 rpm) despite a *hotter* die, because the stock fan curve tracks heatsink temp, which never rises → the fan under-ramps and the die cooks at the limit.

**Conclusion:** card2's ~6–10 % deficit (and its inability to use the full power budget) is a **thermal-interface defect** (repaste/cooler reseat fixes it), not silicon variance. This supersedes the "weaker silicon bin" wording in the section above — with equal cooling card2 would likely match card1. It is a credible warranty/RMA case (excessive hotspot delta + premature thermal throttling).

> **Resolved — see [the post-RMA retest](#post-rma-retest--the-defect-is-gone-august-4-2026) below.** The card came back
> from service with the claim rejected ("fault not reproduced"), but it now measures
> healthy: the hotspot−edge delta dropped 47 → 37.4 °C and it holds the full 300 W
> budget. The defect described above is no longer present.

## Post-RMA retest — the defect is gone (August 4, 2026)

The card was sent in on a warranty claim. Service **rejected it** — "fault not
reproduced, claim unjustified" — and returned it. Re-running the identical
deep-prefill test shows the card now performs like healthy silicon.

**Method (deliberately identical to the June run):** same
`Qwen3.6-27B-Q4_K_M.gguf`, `pp131072`, `-fa 1`, single GPU, **stock 0 mV**. Stock was
enforced the hard way — `lactd` disabled and a cold reboot — because after a reboot
nothing can have staged an offset, which is a stronger guarantee than a sysfs
read-back (a failed OD commit still reads back the requested value; see
[r9700-oc-uv-findings.md](r9700-oc-uv-findings.md#runtime-pm-breaks-the-undervolt-failed-to-upload-overdrive-table-august-4-2026)).

| metric             | card1 (healthy, June) | this card, June     | **this card, August** |
|:-------------------|----------------------:|--------------------:|----------------------:|
| prefill            | 335.9 t/s             | 300.4 t/s           | **323.2 t/s**         |
| junction (hotspot) | 108 °C                | **110 °C**          | **104.4 °C**          |
| edge (heatsink)    | 70 °C                 | 62 °C               | **67.0 °C**           |
| **hotspot − edge** | 38 °C (peak 51)       | **47 °C (peak 62)** | **37.4 °C (peak 39)** |
| memory             | 88 °C                 | 71 °C               | **76.5 °C**           |
| power              | 294 W                 | **222 W**           | **295.3 W**           |
| core clock         | 3171 MHz              | 2828 MHz            | **3066 MHz**          |
| fan                | 4568 rpm              | **3648 rpm**        | **4394 rpm**          |

Against its own June deep-prefill numbers: **298.3 → 323.2 t/s (+8.4 %)**, power
**230 → 295 W**, core **2808 → 3066 MHz**. It now matches card1 almost exactly
(295 vs 296 W, 3066 vs 3029 MHz, delta 37.4 vs 38) and is **power-limited rather than
thermally limited** — the defining difference from June.

**Why this is not just a better test environment.** The card moved slot
(`07:00.0` → `05:00.0`) and the second R9700 is no longer in the case — so ambient
airflow did change. But the data rules airflow out as the explanation:

- **Junction fell (110 → 104 °C) while edge *rose* (62 → 67 °C).** Better case airflow
  would lower *both*. Heat moving *from* the die *into* the heatsink is the signature of
  a fixed thermal interface.
- **Memory temp rose (71 → 76.5 °C)** — same story, heat now spreads through the cooler.
- **The fan finally ramps (3648 → 4394 rpm).** In June it under-ramped because the stock
  curve tracks edge temp, which stayed cold while the die cooked.
- **hotspot − edge is an intra-card metric** (die→heatsink transfer), largely independent
  of ambient.

**What happened is not determinable from the outside.** Service may have repasted or
reseated the cooler before testing and simply not recorded it on the report, or a marginal
mount may have corrected itself during handling and transport. The service report says only
that the fault did not reproduce. What is certain is that the June measurement was real and
the card now behaves like a normal, healthy R9700 — so the rejected claim is not worth
contesting.

**Caveat:** if the mount was marginal rather than properly redone, the fault can return.
The June and August runs are both archived here with identical methodology, which is a far
stronger position for any future claim than a subjective "it feels slow". Worth re-testing
after some weeks of real load, and again before the warranty expires.

## Consequence for the TP=2 prefill benchmarks

> **Historical, but the conclusion still holds.** The defect was present for every TP=2
> benchmark in this repo, so those numbers remain a lower bound. The card itself is fixed
> as of August 2026 ([retest](#post-rma-retest--the-defect-is-gone-august-4-2026)) — which
> makes the prediction below testable if a second card is ever acquired.

This defect is **not** a single-card curiosity — it caps the headline dual-GPU
number in this repo. vLLM TP=2 shards every layer across both GPUs and syncs them
per step, so the pair runs only as fast as its **slower** card. With card2
throttling ~6–10 % below card1 on prefill, the pair's measured TP=2 prefill of
**~1841 t/s** (baseline) / **~1894 t/s** (with the committed launch flags) is a
**lower bound gated by the defective card**, not the platform ceiling.

That reframes the FP8 investigation in [rdna4-fp8-findings.md](rdna4-fp8-findings.md),
which concluded "hardware is optimal / symmetric" and treated ~1841–1965 t/s as the
ceiling. The hardware was **not** symmetric: card2's cooling defect explains why our
pair sat at the *bottom* of that range while an independent, reproducible 2× R9700
run on [localmaxxing](https://www.localmaxxing.com) reached **~1965 t/s** — roughly
the ~6–7 % that card2's throttle costs. (The community's ~2567 t/s remains an
outlier, likely different bench depth/warmup or a private tuned-config pack.)

**Implication:** with two healthy, well-cooled cards (or after card2's cooler is
reseated/RMA-fixed), TP=2 prefill should recover toward ~1965 t/s **from the
hardware alone**, before any of the software levers in
[rdna4-fp8-findings.md](rdna4-fp8-findings.md) are stacked on top. Any future re-test
must first confirm both cards hold full clocks at the power cap (`rocm-smi`
junction/edge/power telemetry) so a thermal defect isn't silently capping the result
again — see the reusable method in `benchmark/thermal-test.sh` / `thermal-log.sh`.

## Final recommended config

```yaml
# /etc/lact/config.yaml  (excerpt)
gpus:
  1002:7551-1458:242F-0000:03:00.0:   # card1 — Hynix / VBIOS F50
    performance_level: auto
    voltage_offset: -70
  1002:7551-1458:242F-0000:07:00.0:   # card2 — Samsung / VBIOS F40
    performance_level: auto
    power_cap: 300.0
    voltage_offset: -30
```

Both undervolted, neither memory-OC'd, both on the auto governor. Related: [r9700-oc-uv-findings.md](r9700-oc-uv-findings.md).
