# AMD Radeon 9700 AI PRO RDNA vLLM Tuning Toolkit

## Project status

**On hold (2026-07).** This project targeted a specific 2× R9700 rig that no longer
exists as a unit: the second card (Samsung/F40) turned out to have a **factory
thermal-interface defect** and has been returned on a warranty/RMA claim, and the
healthy first card (Hynix/F50) was sold. Without the hardware the tuning and
benchmarks can't be re-run or improved further.

It may resume if the RMA card is repaired/replaced and a second card is re-acquired.
In the meantime the docs, scripts and findings are kept as a reference. Open ideas for
when it restarts live in [docs/TODO.md](docs/TODO.md).

> **Reading the benchmark numbers?** The headline dual-GPU **TP=2 prefill
> (~1841–1894 t/s)** is a *lower bound* — the defective card2 throttled and gated the
> pair under TP=2. A healthy pair should reach ~1965 t/s from the hardware alone;
> details in
> [docs/r9700-mem-vendor-bios-variance.md](docs/r9700-mem-vendor-bios-variance.md#consequence-for-the-tp2-prefill-benchmarks).

## Layout

This workspace includes scripts organised into these folders:

- **`tuning/`** — `amdgpu` sysfs overdrive tuning scripts
- **`llm/`** — ROCm install + llama.cpp source / compiled runtimes (and the heavy vLLM build artefacts: `vllm-venv/`, `vllm-src/`, `flash-attention/`)
- **`vllm/`** — vLLM tooling (now split into `vllm/baremetal/` and `vllm/docker/`). See [vllm/README.md](vllm/README.md).
- **`benchmark/`** — llama.cpp Vulkan + ROCm benchmarking scripts and results
- **`docs/`** — written-up findings, field notes and investigations. Start at [docs/README.md](docs/README.md).

### Tuning scripts
1. `tuning/amd_radeon_rdna_tuning.sh`: A generic script for tuning *any* AMD Radeon RDNA GPU. By default, it applies no hardware limits unless explicitly requested through command-line parameters.
2. `tuning/tune_r9700.sh`: A specific wrapper script for the AMD Radeon AI PRO R9700 that provides default parameter limits.

## Default behavior (tune_r9700.sh)

Running `tune_r9700.sh` with no extra arguments calls the generic script and applies:

- memory clock max: `1350 MHz`
- undervolt offset: `-75 mV`
- board power cap: `300 W`
- fan curve: ramping 25% → 50% (see table below)
- GPU core clock max: unchanged

> **Note:** On the current ROCm 7.14 / amdgpu DKMS 6.19.4 stack, the memory-clock
> overdrive and undervolt offset are effectively no-ops (or slightly hurt)
> throughput for FP8 inference — see
> [docs/r9700-oc-uv-findings.md](docs/r9700-oc-uv-findings.md). The fan curve
> is the knob that actually matters acoustically.

## Usage

Show current state:

```bash
sudo ./tuning/tune_r9700.sh --status
```

Apply the requested defaults:

```bash
sudo ./tuning/tune_r9700.sh
```

Apply defaults and also change max GPU core clock:

```bash
sudo ./tuning/tune_r9700.sh --core-clock-max 2550
```

Target a specific card:

```bash
sudo ./tuning/tune_r9700.sh --pci-id 0000:07:00.0
```

## Multi-GPU support (1..N RDNA cards)

> **Running two R9700s on a B450 / Cezanne ITX system?** Read
> [docs/dual-gpu-bifurcation-notes.md](docs/dual-gpu-bifurcation-notes.md)
> first — there are real PCIe bifurcation quirks (broken `x8/x8` mode,
> Gen1-x4 link training on the secondary slot) documented there.

Every script in `tuning/`, `llm/`, `vllm/` and `benchmark/` accepts a unified `--gpus`
selector for choosing which RDNA GPUs to act on. The selector understands
several forms — pick whichever is most convenient:

| Form                               | Meaning                                           |
| ---------------------------------- | ------------------------------------------------- |
| `--gpus all` *(default)*           | Every detected discrete RDNA GPU                  |
| `--gpus 1`                         | First RDNA GPU only (PCI-BDF order)               |
| `--gpus 2`                         | First N RDNA GPUs                                 |
| `--gpus 0,2`                       | Specific RDNA indices (zero-based, iGPU excluded) |
| `--gpus 0000:03:00.0,0000:0f:00.0` | Explicit PCI BDFs (most robust)                   |

Environment-variable fallback: `export RDNA_GPUS=...` is used when `--gpus`
is not passed (handy for systemd units and the `r9700-tune.service`).

The shared helper `lib/rdna_detect.sh` detects discrete RDNA cards by:

1. Filtering PCI vendor `0x1002` devices driven by the `amdgpu` kernel module.
2. Requiring at least 4 GiB of dedicated VRAM (excludes integrated GPUs like
   Cezanne/Renoir, which only carve out a small system-RAM region).
3. Sorting deterministically by PCI BDF, so "RDNA index 0" means the same
   thing across the tuning, ROCm and Vulkan scripts.

For the benchmarks (`benchmark/run_llm_benchmark_*.sh`), selecting more than
one GPU runs **per-GPU passes followed by a combined multi-GPU pass** so you
can compare scaling. Use `--no-per-gpu-sweep` to skip the individual passes.

Examples:

```bash
# Tune both R9700s with the max-performance profile
sudo ./tuning/tune_r9700_max.sh

# Tune only the second R9700
sudo ./tuning/tune_r9700_max.sh --gpus 1

# Run ROCm inference using both R9700s (layer-split by llama.cpp)
./llm/run_inference_rocm.sh --gpus all ~/models/some-model.gguf

# Benchmark just the first card, ROCm
./benchmark/run_llm_benchmark_rocm.sh --gpus 0

# Serve Qwen3-30B-A3B-Instruct FP8 with vLLM, tensor-parallel across all detected R9700s
./vllm/baremetal/install_vllm_rocm.sh            # first-time setup (RDNA4 stack: AITER + custom RCCL + patches)
./vllm/baremetal/run_vllm_server.sh              # uses all RDNA GPUs, TP=N auto

# Benchmark vLLM (single-shot or full sweep)
./vllm/baremetal/bench-vllm.sh --num-prompts 4 --input-len 256 --output-len 32   # smoke test
./vllm/baremetal/bench-vllm-suite.sh             # per-GPU + combined TP=N passes
```

Dry run:

```bash
sudo ./tuning/tune_r9700.sh --dry-run
```

Reset overdrive values back to driver defaults:

```bash
sudo ./tuning/tune_r9700.sh --reset
```

Set fan to a fixed speed (e.g. 35%):

```bash
sudo ./tuning/tune_r9700.sh --fan-speed-pct 35
```

Set a custom 5-point fan curve (temp °C → speed %):

```bash
sudo ./tuning/tune_r9700.sh --fan-curve "25 25 50 30 70 34 85 37 100 40"
```

Fan control can be combined with other flags:

```bash
sudo ./tuning/tune_r9700.sh --fan-curve "25 25 50 35 70 50 85 70 100 100" --tdp 180
```

Restore automatic (driver-controlled) fan speed:

```bash
sudo ./tuning/tune_r9700.sh --fan-auto
```

> **Note:** Fan settings are not persistent across reboots or driver reloads. Re-run the script after each boot to reapply. `--reset` also restores the fan curve to driver defaults.

## Fan control

The R9700 (Navi 48) does **not** use the standard `hwmon/pwm1_enable` interface. Fan control is via the newer `gpu_od/fan_ctrl/fan_curve` sysfs API, which accepts a 5-point hotspot-temperature-to-fan-speed mapping.

> **Commit required:** Writing the 5 curve points only stages them in the
> in-memory OD table — the SMU keeps using its previous curve until a commit
> (`c`) is written back to `fan_curve`. The new values *do* show up in a sysfs
> read-back even when uncommitted, which makes it look like the curve is active
> when it isn't. `amd_radeon_rdna_tuning.sh` writes that commit automatically
> after staging the points (and after `--fan-auto` / `--reset`). The same applies
> to the sibling nodes (`fan_minimum_pwm`, `fan_target_temperature`,
> `acoustic_target_rpm_threshold`, `fan_zero_rpm_enable`).

### Default fan curve (`tune_r9700.sh`)

| Point | Hotspot temp | Fan speed |
| ----- | ------------ | --------- |
| 0     | 25 °C        | 25%       |
| 1     | 50 °C        | 25%       |
| 2     | 70 °C        | 30%       |
| 3     | 85 °C        | 40%       |
| 4     | 100 °C       | 50%       |

The quieter `tune_r9700_quiet.sh` profile tops out at 35% (25/25/30/30/35) with a
210 W cap; `tune_r9700_max.sh` applies no fan curve and leaves the fan on the
driver's automatic control.

> **Hardware minimum:** The driver enforces a minimum of **25%** fan speed (`OD_RANGE: FAN_CURVE(fan speed): 25% 100%`). Any value below 25% is clamped automatically.

### `--fan-curve` format

```
"T0 P0 T1 P1 T2 P2 T3 P3 T4 P4"
```

- `Tn` — hotspot temperature in °C (must be strictly ascending, range 25–100)
- `Pn` — fan speed in % (range 25–100)

Example — aggressive curve for sustained compute:

```bash
sudo ./tuning/tune_r9700.sh --fan-curve "25 30 50 45 70 60 85 80 100 100"
```

### Other fan knobs

The curve alone is not a strict lookup table — the SMU blends it with several
acoustic targets. These are exposed as separate `gpu_od/fan_ctrl/*` nodes and
can be set independently (each is range-validated against the node's own
`OD_RANGE` and committed automatically):

| Flag                        | Node                            | Meaning                                                               |
| --------------------------- | ------------------------------- | --------------------------------------------------------------------- |
| `--fan-minimum-pwm PCT`     | `fan_minimum_pwm`               | Lowest fan duty the SMU may use (this card's floor is 25%).           |
| `--fan-target-temp C`       | `fan_target_temperature`        | Temp the SMU holds; above it the fan ramps toward the acoustic limit. |
| `--acoustic-target-rpm RPM` | `acoustic_target_rpm_threshold` | RPM the SMU stays under until the target temp is exceeded.            |
| `--acoustic-limit-rpm RPM`  | `acoustic_limit_rpm_threshold`  | Max RPM the SMU ramps to at/above the target temp.                    |
| `--fan-zero-rpm 0\|1`       | `fan_zero_rpm_enable`           | Allow the fan to fully stop when cool (not supported on every SKU).   |

These combine with `--fan-curve` (or each other). Example — a curve that also
lets the fan idle-stop and holds a higher target temperature before ramping:

```bash
sudo ./tuning/tune_r9700.sh \
  --fan-curve "25 25 50 30 70 45 85 70 100 100" \
  --fan-target-temp 80 \
  --acoustic-target-rpm 1500 \
  --fan-zero-rpm 1
```

Inspect the current values of all of these with `--status`.

## Important

The voltage offset exposed by `amdgpu` is in `mV`, so the requested `-80mw` value is implemented as `-80 mV`.

You must enable overdrive support first.

Fedora/RHEL example:

```bash
sudo grubby --update-kernel=ALL --args="amdgpu.ppfeaturemask=0xffffffff"
```

Ubuntu/Debian GRUB example:

```bash
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 amdgpu.ppfeaturemask=0xffffffff"/' /etc/default/grub
sudo update-grub
```

Reboot after changing the kernel arguments.

## ROCm Compatibility

For ROCm installation on this GPU across Ubuntu versions, see the [benchmark README](benchmark/README.md#rocm-ubuntu-compatibility--workarounds).

ROCm and llama.cpp runtimes live in `llm/` — see [llm/install_rocm7_and_compile_llama.sh](llm/install_rocm7_and_compile_llama.sh).

## vLLM on R9700 / gfx1201

The vLLM documentation has moved into [vllm/README.md](vllm/README.md).

Quick links:
- Baremetal workflow: [vllm/baremetal](vllm/baremetal)
- Docker workflow: [vllm/docker](vllm/docker)
- Full guide: [vllm/README.md](vllm/README.md)

## Tested Environment

Validated on two systems (the dual-GPU tooling and benchmarks have been run on both):

**Current rig — Intel (full PCIe 5.0, dual R9700):**
- **CPU**: Intel Core Ultra 5 250K Plus
- **Mainboard**: ASUS ProArt Z890-Creator
- **GPU**: 2× AMD Radeon AI PRO R9700 (Navi 48), each on PCIe 5.0
- **RAM**: 96 GB DDR5-6000 CL30
- **Kernel**: Linux 6.17.0-35-generic x86_64

**Original rig — AMD (bifurcated PCIe, see [docs/dual-gpu-bifurcation-notes.md](docs/dual-gpu-bifurcation-notes.md)):**
- **CPU**: AMD Ryzen 7 5700G
- **GPU**: 1–2× AMD Radeon AI PRO R9700 (Navi 48)
- **RAM**: 64 GB
- **OS**: Ubuntu 25.10
- **Kernel**: Linux 6.17.0-23-generic x86_64

> The migration from the bifurcated AMD rig to the full-PCIe-5.0 Intel rig made
> vLLM **TP=2** viable again (~3–5.5× prefill recovery) — see
> [benchmark/R9700_benchmarks.md](benchmark/R9700_benchmarks.md#vllm-tp2--intel-z890-platform-migration-june-17-2026).
