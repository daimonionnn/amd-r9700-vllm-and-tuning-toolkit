# AMD Radeon RDNA LLM Tuning Toolkit

This workspace includes scripts organised into four folders:

- **`tuning/`** — `amdgpu` sysfs overdrive tuning scripts
- **`llm/`** — ROCm install + llama.cpp source / compiled runtimes (and the heavy vLLM build artefacts: `vllm-venv/`, `vllm-src/`, `flash-attention/`)
- **`vllm/`** — vLLM tooling (now split into `vllm/baremetal/` and `vllm/docker/`). See [vllm/README.md](vllm/README.md).
- **`benchmark/`** — llama.cpp Vulkan + ROCm benchmarking scripts and results

### Tuning scripts
1. `tuning/amd_radeon_rdna_tunning.sh`: A generic script for tuning *any* AMD Radeon RDNA GPU. By default, it applies no hardware limits unless explicitly requested through command-line parameters.
2. `tuning/tune_r9700.sh`: A specific wrapper script for the AMD Radeon AI PRO R9700 that provides default parameter limits.

## Default behavior (tune_r9700.sh)

Running `tune_r9700.sh` with no extra arguments calls the generic script and applies:

- memory clock max: `1350 MHz`
- undervolt offset: `-75 mV`
- board power cap: `210 W`
- fan curve: ramping 25% → 40% (see table below)
- GPU core clock max: unchanged

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
is not passed (handy for systemd units and the `tune_r9700-tune.service`).

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

### Default fan curve (`tune_r9700.sh`)

| Point   | Hotspot temp  | Fan speed  |
| ------- | ------------- | ---------- |
| 0       | 25 °C         | 25%        |
| 1       | 50 °C         | 30%        |
| 2       | 70 °C         | 34%        |
| 3       | 85 °C         | 37%        |
| 4       | 100 °C        | 40%        |

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

This script was tested on the following system configuration:

**Hardware:**
- **CPU**: AMD Ryzen 7 5700G
- **GPU**: AMD Radeon AI PRO R9700 (Navi 48)
- **RAM**: 64 GB

**Software:**
- **OS**: Ubuntu 25.10
- **Kernel**: Linux 6.17.0-23-generic x86_64
