# Dual-GPU Bifurcation on B450 + Ryzen 5700G — Field Notes

This document captures hardware-level findings from running **2× AMD Radeon AI
PRO R9700** in a Mini-ITX system that was never designed for dual discrete
GPUs. If you are attempting a similar build, read this first — some of these
behaviors look like broken hardware but are actually well-known platform
limitations.

## Test system

| Component         | Value                                                                                                                    |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Motherboard       | ASRock B450 Fatal1ty Gaming-ITX/ac                                                                                       |
| CPU               | AMD Ryzen 7 5700G (Cezanne APU, Vega 8 iGPU)                                                                             |
| PCIe slots        | 1× PCIe 3.0 x16 (CPU-direct) — bifurcation required for 2 GPUs                                                           |
| Bifurcation riser | [AliExpress 1005004545109164 — x8x8 / x4x4x4x4 PCIe 3.0 splitter](https://www.aliexpress.com/item/1005004545109164.html) |
| Riser cables      | 2× PCIe 3.0 x8 ribbon extensions, 20 cm                                                                                  |
| GPUs              | 2× AMD Radeon AI PRO R9700 (Navi 48 / gfx1201, 32 GB each)                                                               |
| OS                | Ubuntu 25.10, kernel 6.17                                                                                                |

## Issue 1 — `x8/x8` bifurcation does **not** work on B450 with Cezanne

### Symptom

| BIOS setting    | Result                                                 |
| --------------- | ------------------------------------------------------ |
| `x16` (default) | Only **GPU #1** detected (expected — second slot dark) |
| `x8/x8`         | Only **GPU #2** detected (broken — first slot dark)    |
| `x8/x4/x4`      | **Both GPUs detected** ✔                               |

### Why

This is a **B450 + Cezanne combo bug**, not a fault of the riser or GPUs:

- B450 silicon predates Cezanne (Ryzen 5xxxG, Zen 3 APU) by about three
  years. AsRock added Cezanne support via late AGESA microcode updates, but
  AMD only fully validated **Vermeer (Ryzen 5xxx non-G)** bifurcation on
  B450 chipsets.
- Cezanne shares the AM4 socket with Vermeer but has a different PCIe
  controller/REFCLK topology. On B450, the `x8/x8` AGESA code path does not
  correctly drive REFCLK and PERST# to the first x8 half for Cezanne, so the
  device on the first slot never finishes link training.
- The `x8/x4/x4` mode uses a different lane-grouping path that *is*
  validated for Cezanne on B450, which is why both cards enumerate.

In practice this means: on this motherboard, **the only working mode is
`x8/x4/x4`**, which effectively gives one slot x8 and the other slot x4 (the
trailing x4 lanes are unused by a 2-slot bifurcation riser).

This would not be an issue on X570 / B550 / X670 boards, where Cezanne
`x8/x8` is properly supported.

## Issue 2 — Second GPU trains to PCIe Gen1 x4 instead of Gen3 x4

### Symptom

With BIOS in `x8/x4/x4` and both cards detected:

- **GPU #1** (in the x8 slot): negotiates **PCIe Gen3 x8** as expected.
- **GPU #2** (in the x4 slot): reported as **PCIe Gen1 x4** instead of the
  expected **Gen3 x4**.

### How to verify (is it real or a display glitch?)

> **⚠ Important — the GPU itself reports the wrong link state.**
> The Navi 48 R9700 integrates an **on-card PCIe switch** between its
> upstream port and the GPU silicon (visible in `lspci` as
> `Navi 10 XL Upstream / Downstream Port of PCI Express Switch`).
> Running `lspci -vvv -s <GPU_BDF>` reads the GPU's own PCIe capability
> block, which reports the *internal* switch→GPU link (always Gen5 x16).
> The amdgpu `current_link_speed` sysfs file is similarly misleading.
>
> **The real CPU-side link is at the upstream root port**, several hops up
> the tree. Walk the PCI ancestry to find it.

Run `lspci -vvv` on the **CPU root port** of the suspect GPU and compare
`LnkCap` (max capability) to `LnkSta` (currently negotiated):

```bash
# Walk the PCI tree to find the root port for a given GPU BDF
GPU=0000:0f:00.0
ROOT=$(readlink -f /sys/bus/pci/devices/$GPU | grep -oE '0000:00:[0-9a-f]{2}\.[0-9a-fA-F]' | head -1)
echo "Root port for $GPU is $ROOT"
sudo lspci -vvv -s "$ROOT" | grep -E "LnkCap:|LnkSta:"
```

Output interpretation:

| `LnkSta` Speed | Meaning                        | Approx. usable bandwidth at x4 |
| -------------- | ------------------------------ | ------------------------------ |
| `2.5GT/s`      | **Gen1** — really running slow | ~1.0 GB/s                      |
| `5.0GT/s`      | Gen2                           | ~2.0 GB/s                      |
| `8.0GT/s`      | **Gen3** — what we expected    | ~3.94 GB/s                     |

The `(downgraded)` annotation in `LnkSta` confirms link training fell back
from `LnkCap` max. **`lspci` reads PCIe config space directly from the
device, so the value is real and not a UI glitch.**

### Empirical bandwidth confirmation

To prove the practical impact, time how long it takes each GPU to load a
large model (model loading is essentially a host→device copy bound by PCIe
bandwidth):

```bash
# GPU 0 (Gen3 x8, fast)
time ./benchmark/bench-rocm7.sh --gpus 0 ~/.lmstudio/models/.../some-16GB-model.gguf

# GPU 1 (suspect link)
time ./benchmark/bench-rocm7.sh --gpus 1 ~/.lmstudio/models/.../some-16GB-model.gguf
```

Rough expectations for a 16 GB model:

| Link state  | Expected load time |
| ----------- | ------------------ |
| Gen3 x8     | ~4–5 s             |
| Gen3 x4     | ~8–10 s            |
| **Gen1 x4** | **~30–40 s**       |

If GPU 1 takes 30 s+, the Gen1 cap is real.

### Verified measurement on this system

Test conditions: 26.62 GiB Q8_0 Qwen3.6-27B model, page cache pre-primed
(so disk I/O is eliminated), `llama-bench -ngl 99 -p 0 -n 1 -r 1`, 3 warm
runs averaged.

| GPU          | Root port LnkSta                    | Wall time   | Effective host→VRAM throughput             |
| ------------ | ----------------------------------- | ----------- | ------------------------------------------ |
| #1 `03:00.0` | `Speed 8GT/s, Width x8` (Gen3 x8)   | **~5.3 s**  | ~6.2 GB/s (≈ 79 % of Gen3 x8 theoretical)  |
| #2 `0f:00.0` | `Speed 2.5GT/s, Width x4` (Gen1 x4) | **~34.4 s** | ~0.85 GB/s (≈ 85 % of Gen1 x4 theoretical) |

The **6.5× wall-time ratio** matches the theoretical Gen3 x8 / Gen1 x4
bandwidth ratio (7.88×) almost exactly after subtracting ~1 s of constant
ROCm/llama.cpp init overhead. Per-GPU effective throughput numbers land
right at the practical efficiency of each link generation. This conclusively
demonstrates that the Gen1 x4 negotiation on GPU #2 is real, not a display
glitch.

Single-token decode (`tg1`) was also affected (10.6 tok/s on GPU #1 vs
~8.1 tok/s on GPU #2 for the same model on the same silicon), suggesting the
degraded link impacts more than just initial weight upload.

### Partial fix: force the link to retrain at Gen2 via `setpci`

The Gen1 cap on the second sub-link turned out to be a **BIOS policy lock**
rather than a hardware training failure. The root port's PCIe Link Control 2
register was programmed by AGESA with:

```
LnkCtl2: Target Link Speed: 2.5GT/s, EnterCompliance- SpeedDis+
```

- `Target Link Speed: 2.5GT/s` (Gen1) — the BIOS told the port to aim for
  Gen1 only, even though `LnkCap2` shows Gen3 is supported.
- `SpeedDis+` — Hardware Autonomous Speed Disable is set, forbidding the
  link from independently negotiating up.

This can be patched at runtime: flip Target Link Speed to Gen3, clear
SpeedDis, and trigger a link retrain. **On this hardware the link will not
stably reach Gen3, but it does reach Gen2 — a free 2× bandwidth boost.**

A ready-to-run helper script is provided:

```bash
sudo ./tuning/force_pcie_link.sh                  # defaults: 00:02.4, Gen3 target
sudo ./tuning/force_pcie_link.sh --help           # all options
sudo ./tuning/force_pcie_link.sh --root-port 00:02.4 --target-gen 2
```

The raw commands it runs (for documentation):

```bash
# PCIe Express cap on 00:02.4 lives at offset 0x58, so:
#   LnkCtl  = 0x58 + 0x10 = 0x68
#   LnkCtl2 = 0x58 + 0x30 = 0x88
# Mask 0x2F = bits[3:0] (Target Link Speed) + bit 5 (SpeedDis).
sudo setpci -s 00:02.4 88.W=03:2F      # Target=Gen3, SpeedDis=0
sudo setpci -s 00:02.4 68.W=20:20      # set Retrain Link bit
sleep 1
sudo lspci -vvv -s 00:02.4 | grep -E 'LnkSta:|LnkCtl2:'
```

**⚠ Not persistent.** PCIe config registers reset to BIOS defaults on every
reboot. Either re-run the script after each boot, or install the included
systemd unit:

```bash
sudo cp tuning/force-pcie-link.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now force-pcie-link.service
sudo systemctl status force-pcie-link.service
```

### Verified result of the setpci retrain on this system

Same `llama-bench -ngl 99 -p 0 -n 1 -r 1` test, 3 warm runs averaged, page
cache pre-primed (so disk I/O is eliminated):

| GPU                               | Root port LnkSta | Wall time   | Effective throughput | tg1               |
| --------------------------------- | ---------------- | ----------- | -------------------- | ----------------- |
| #1 `03:00.0` (Gen3 x8, control)   | `8GT/s × x8`     | 5.25 s      | ~6.2 GB/s            | 10.07–10.49 tok/s |
| #2 `0f:00.0` **before** (Gen1 x4) | `2.5GT/s × x4`   | **34.4 s**  | ~0.85 GB/s           | 8.1 tok/s         |
| #2 `0f:00.0` **after** (Gen2 x4)  | `5GT/s × x4`     | **16.15 s** | ~1.69 GB/s           | **10.08 tok/s**   |

- Model load time on GPU #2: **2.13× faster** (34.4 s → 16.15 s).
- Decode throughput on GPU #2 jumped from 8.1 tok/s to 10.08 tok/s, now
  matching GPU #1 — confirming the Gen1 link was throttling decode too.
- Multiple retrain attempts at Gen3 target all settled at Gen2; this is a
  genuine signal-integrity ceiling of the 20 cm cable + B450 routing on
  this sub-link. Gen3 requires shorter / re-driver / re-timer cables.

**Independently verified that Gen3 is a hard ceiling:** 5 consecutive
retrains plus one full link disable→re-enable cycle (via `LnkCtl` bit 4)
all stabilized at exactly Gen2 x4. The link will not negotiate higher on
this cable.

> **⚠ Do NOT use the link disable→re-enable trick on Navi 48 / R9700.**
> While the simple Retrain Link bit (`LnkCtl` bit 5) is completely safe,
> setting Link Disable (`LnkCtl` bit 4) while `amdgpu` has the device
> bound triggers a `device lost from bus` event in dmesg and corrupts the
> SMU firmware state. The GPU then refuses to report per-die graphics
> power, returns garbage on the energy counter, hangs subsequent
> `llama-bench` runs, and only recovers after a full reboot. The provided
> `force_pcie_link.sh` script deliberately uses only the safe Retrain Link
> bit and never touches Link Disable.



1. **Signal integrity on the riser path** — long ribbon cables, lack of
   PCIe re-drivers/re-timers, or unshielded traces. Cezanne's PCIe PHY is
   strict about eye margins and will fall back to Gen1 to keep the link
   alive when training fails at higher rates.
2. **REFCLK distribution** — bifurcation cards that don't properly buffer/
   regenerate REFCLK for the secondary sub-link send jittery clocks to the
   x4 slot, capping training at Gen1.
3. **AGESA pessimistic auto-negotiation** — sometimes the BIOS picks Gen1
   for bifurcated sub-links by default. Try toggling, in the BIOS:
   - `PCIe ASPM` → **Disabled**
   - `PCIe Gen Speed` (per slot if available) → **force Gen3**
4. **Cable length / quality** — 20 cm Gen3 ribbon cables are at the upper
   end of what reliably trains at Gen3 without re-drivers. A shorter cable
   or a card with re-timers usually helps.

### Practical impact on LLM workloads

- **Model load time** scales linearly with PCIe bandwidth — Gen1 x4 makes
  loading a 30 GB model take ~30 s instead of ~5 s. Annoying but a one-time
  cost per run.
- **Inference throughput** is mostly memory-bandwidth bound (HBM/GDDR on the
  GPU), so a slow PCIe link has **minimal impact on tokens/sec** for single
  long-running inference sessions.
- **Multi-GPU layer-split (tensor parallel)** can be affected if layers
  exchange activations across PCIe each step. For llama.cpp's default
  layer-split mode (`-sm layer`), per-token PCIe traffic is small and the
  impact is usually <10 %. For row-split mode (`-sm row`), it can be
  significant.

When in doubt, benchmark both single-GPU and combined runs with
`./benchmark/run_llm_benchmark_rocm.sh --gpus all` (which does per-GPU +
combined passes automatically) and compare.

## Things that don't help (verified)

### Disabling the integrated GPU (Vega 8) in BIOS

**Hope:** "Maybe disabling the iGPU frees up PCIe lanes so the second slot
can train at Gen3 x4, or so `x8/x8` becomes possible."

**Reality:** No effect. Tested on this system — link state of GPU #2 stayed
at Gen1 x4 and `x8/x8` mode still failed to detect GPU #1.

**Confirmation re-test (BIOS flipped back to `x8/x8`):** the failure mode
is silent and at the AGESA level, not in the OS. Only one R9700 enumerates,
and there is no second root port for it to even hang off — the BIOS simply
does not instantiate it:

```text
$ lspci -tv | head
-[0000:00]-+-00.0  Renoir/Cezanne Root Complex
           +-01.2-[01-03]----00.0-[02-03]----00.0-[03]--+-00.0  Navi 48 [Radeon AI PRO R9700]   ← only GPU
           |                                            \-00.1  Navi 48 HDMI/DP Audio
           +-02.1-[04-0b]--+-00.0  400 Series Chipset USB 3.1
           |               +-00.1  400 Series Chipset SATA
           |               ...
           +-02.2-[0c]----00.0  Kingston NVMe SSD
           +-08.1-[0d]--+-00.0  Cezanne [Radeon Vega] (iGPU)
           ...

$ sudo lspci -vvv -s 00:01.2 | grep LnkSta:
                LnkSta: Speed 8GT/s, Width x8     ← GPU #1 trains perfectly at Gen3 x8
```

Note there is no `00:01.1` / `00:01.3` / `00:02.4` root port for a second
GPU. dmesg has no PCIe link-training errors — the slot was never powered
up. The single detected R9700 trains cleanly at Gen3 x8, proving the
hardware works; AGESA just refuses to bring up the second half of the x16
in `x8/x8` mode on Cezanne. **There is no software workaround** — back to
`x8/x4/x4` it is.

**Why it cannot help:** on AMD APUs the iGPU is **not** on the external
PCIe controller. It lives on the SoC's internal Data Fabric (Infinity
Fabric) and is wired directly to the display engine and memory controller.
It does not consume any of the 24 external PCIe lanes the CPU exposes to
slots and chipset. Disabling it just disconnects the iGPU from the display
PHYs — it does not return any lanes to a pool, because there is no shared
pool.

Lane layout on Ryzen 5700G (Cezanne, Zen 3 APU):

| Lane group             | Count | Where it goes                            | Reclaimable by disabling iGPU?  |
| ---------------------- | ----- | ---------------------------------------- | ------------------------------- |
| PCIe **3.0** x16 (GPP) | 16    | Primary GPU slot (the one you bifurcate) | No                              |
| PCIe 3.0 x4            | 4     | M.2 / chipset uplink                     | No                              |
| PCIe 3.0 x4            | 4     | Second M.2 / chipset                     | No                              |
| Display PHYs (DP/HDMI) | —     | Monitor outputs only                     | iGPU uses these, not PCIe lanes |

Also worth knowing: **Cezanne is the lane-poor AM4 part**. The non-APU
5800X/5900X (Vermeer) exposes the same 16 GPU lanes but at **PCIe 4.0** —
double the bandwidth per lane, and historically more reliable bifurcation
training because there is no shared SoC display block. On a 5700G you are
already capped at Gen3 on the GPU slot; no BIOS toggle can change that.

**What actually might help** (in rough order of effort):

1. Swap the 5700G for a non-APU Ryzen 5000 (5800X / 5900X) — gets you
   Gen4 on the GPU slot, so even a degraded Gen3 x4 sub-link is ~2× faster
   than your current Gen1 x4, and `x8/x8` is much better validated on B450
   AGESA for Vermeer.
2. Move to AM5 (7600 / 7700 + B650E/X670E) — Gen5 lanes, modern AGESA, most
   boards include re-drivers.
3. Use shorter / shielded / re-timer-equipped riser cables.
4. BIOS: disable ASPM on the bifurcated root ports, force PCIe Gen Speed to
   Gen3 (instead of Auto) — sometimes prevents auto-fallback to Gen1.
5. `setpci` post-boot link retrain to a forced target speed (risky, can
   hang the system; only attempt with serial console / recovery plan).

## Summary table

| Symptom                            | Root cause                                            | Workaround                                                                                                                                                                               |
| ---------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `x8/x8` BIOS → only 1 GPU detected | B450 AGESA does not validate `x8/x8` for Cezanne      | Use `x8/x4/x4` mode instead                                                                                                                                                              |
| Second GPU at Gen1 x4 not Gen3 x4  | BIOS pins Target Link Speed to Gen1 with SpeedDis set | Run `sudo ./tuning/force_pcie_link.sh` to retrain at Gen2 (~2× bandwidth); Gen3 unreachable on this riser. Not persistent — re-run after boot or enable `tuning/force-pcie-link.service` |

## Recommended platform for dual R9700

If you are building from scratch and want both cards at full **Gen3 x8** (or
better, Gen4 x8), pick a board with proper PCIe topology:

- **AM5**: X670E / B650E boards with two physical x16 slots wired as `x8/x8`
  from the CPU.
- **AM4**: X570 / B550 boards with `x8/x8` bifurcation support for Cezanne
  (check the QVL — many list it, B450 generally does not).
- **Workstation**: Threadripper or EPYC platforms have plenty of native
  PCIe lanes with no bifurcation tricks required.

The B450 + 5700G setup documented here works, but with the caveats above.

### Cheapest fix: swap only the motherboard to B550

If you already have a working B450 + 5700G build and just want both R9700s
on Gen3 x8, **swapping only the motherboard to B550** is the lowest-effort
upgrade with a high probability of success. Keep the CPU, RAM, riser and
GPUs.

Why it should work: the `x8/x8` failure here is a **B450-specific AGESA
bug** — Cezanne (5xxxG) bifurcation was never properly validated on B450.
B550 launched with Cezanne in its validation matrix, so the `x8/x8` code
path actually exists for APUs on virtually all B550 boards that expose
bifurcation in BIOS.

Outcome you can expect:

|        | Before (B450, `x8/x4/x4`) | After (B550, `x8/x8`)                 |
| ------ | ------------------------- | ------------------------------------- |
| GPU #1 | Gen3 x8 (~7.88 GB/s)      | Gen3 x8                               |
| GPU #2 | Gen1 x4 (~1.0 GB/s)       | **Gen3 x8 (~7.88 GB/s)** — ~8× faster |

Caveats when picking a B550 board:

- **Must have two physical PCIe x16 slots wired from the CPU** (not via the
  chipset). Look for slots labeled `x16/x0` or `x8/x8` in the manual.
  Mini-ITX boards almost never qualify — go **mATX or ATX**.
- **Must expose `PCIe Bifurcation` / `PCIe Lane Configuration` in BIOS**
  with an `x8/x8` option. Not all B550 boards do this even when the
  chipset supports it — verify against the board manual or BIOS
  screenshots before buying. Known-good examples: ASRock B550 Steel
  Legend, MSI B550 Tomahawk, Asus TUF B550-Plus.
- You'll still be on **PCIe Gen3** lanes (Cezanne's PCIe controller is
  Gen3 regardless of chipset). To unlock Gen4 you'd additionally need to
  swap to a non-APU CPU (5800X / 5900X / Vermeer), which doubles per-lane
  bandwidth on top of fixing bifurcation.
- Risers / cables stay the same, but if your current 20 cm cables are
  already marginal (one half fell to Gen1), the *other* slot may now hit
  similar signal-integrity limits. Shorter or re-driver cables are a cheap
  insurance buy.

## Resolution — platform migration to Intel Z890 (June 2026)

The bifurcation/Gen1 saga above was ultimately resolved the way the
"Recommended platform" section predicted: by moving off the lane-poor
B450 + Cezanne combo entirely. The 2× R9700 now run in a modern Intel build.

| Component   | Old (B450 + 5700G)                            | New (Z890 + Core Ultra)                       |
| ----------- | --------------------------------------------- | --------------------------------------------- |
| CPU         | AMD Ryzen 7 5700G (Cezanne APU)               | Intel Core Ultra 5 250K Plus                  |
| Motherboard | ASRock B450 Fatal1ty Gaming-ITX/ac            | ASUS ProArt Z890-Creator                      |
| RAM         | 64 GB DDR4                                    | 96 GB DDR5-6000 CL30                          |
| GPU links   | `x8/x4/x4` bifurcation; #2 stuck Gen1/Gen2 x4 | Both cards on PCIe 5.0, no bifurcation tricks |
| iGPU        | Vega 8 (Cezanne, on Infinity Fabric)          | Intel Arrow Lake (vendor-filtered, unused)    |

### BDF change

The second card's PCI BDF changed with the new board topology. Anything that
referenced the old BDF by hand needs updating; the toolkit's auto-detection
(`lib/rdna_detect.sh`) handles it transparently, so no scripts required edits.

| Card   | Old platform BDF | New platform BDF |
| ------ | ---------------- | ---------------- |
| GPU #1 | `0000:03:00.0`   | `0000:03:00.0`   |
| GPU #2 | `0000:0f:00.0`   | `0000:07:00.0`   |

> The `GPU=0000:0f:00.0` example earlier in this document and the benchmark
> tables above are kept as the **historical B450 record**; on the current rig
> the second card is `0000:07:00.0`.

### Outcome

Full PCIe 5.0 on both cards removed the cross-GPU bandwidth bottleneck that
forced Pipeline Parallelism on the old rig. vLLM **TP=2** prefill recovered from
~333–620 t/s (bifurcated) to ~1786–1841 t/s (~3–5.5×) while keeping high decode —
see [../benchmark/R9700_benchmarks.md](../benchmark/R9700_benchmarks.md#vllm-tp2--intel-z890-platform-migration-june-17-2026).
The `setpci` Gen2 retrain, `force_pcie_link.sh` and the bifurcation BIOS dance
are no longer needed on the new platform (they remain documented here for anyone
still on B450/AM4).
