# AMD RDNA LLM Benchmark Suite

This directory contains benchmarking scripts tailored for testing Large Language Models (LLMs) on AMD RDNA GPUs using `llama.cpp`'s Vulkan and native ROCm backends. It is designed to evaluate generation speed and prompt processing (time-to-first-token) capabilities under varying context loads.                                             

## Included Scripts

**Vulkan Backend (Works Out-of-the-Box):**
- **`run_llm_benchmark_vulkan.sh`**: The primary full benchmarking script using Vulkan.
- **`bench-vulkan.sh`**: Generalized Vulkan backend benchmarking script.

**ROCm Backend (Maximum Performance for RDNA4/GFX12):**
- **`../llm/install_rocm7_and_compile_llama.sh`**: Interactive script that installs ROCm (via [TheRock](https://github.com/ROCm/TheRock) nightly pip packages) into a local Python venv and compiles `llama.cpp` with HIP support for GFX1201. Works on Ubuntu 22.04, 24.04, and **25.10**.
- **`run_llm_benchmark_rocm.sh`**: The primary full benchmarking script using the native ROCm/HIP backend.
- **`bench-rocm7.sh`**: Generalized ROCm backend benchmarking script.

**vLLM Backend (Tensor-Parallel, FP8, OpenAI server):**
- vLLM docs and script catalog are centralized in [../vllm/README.md](../vllm/README.md).
- Baremetal wrappers: [../vllm/baremetal/](../vllm/baremetal/)
- Docker wrappers: [../vllm/docker/](../vllm/docker/)

## Benchmark Parameters

The scripts evaluate the models under the following explicitly configured conditions:
- **Models**:
  - `Qwen 3.6 27B` (Dense) — *(Note: `llama-bench` will output this as `qwen36 27B` because it uses the internal `qwen36` structure branch in `llama.cpp`)*
  - `Gemma 4 31B` (Dense)
  - `Gemma 4 26B` (MoE)
- **Context Sizes (Prompt Tokens)**: `1024`, `4096`, and `32768` tokens.
- **Generation Tokens**: `128` tokens decoded per test.
- **Flash Attention**: Enabled (`-fa` flag) for optimized and memory-efficient scaled dot-product attention.
- **KV Cache Offloading**: Fully offloaded to GPU VRAM (`-ngl 99`).
- **Backend Environment**: Selectable between Vulkan (`radv`) or native ROCm (`HIP`).

## Prerequisites

1. **Models**: The scripts expect the models (in `.gguf` format) to exist in the user's LM Studio community cache directory (`~/.lmstudio/models/lmstudio-community/`).

2. **llama-bench Executable (Vulkan)**: The Vulkan script uses a standalone custom-compiled `llama-bench` binary located at `../llm/llama.cpp-vulkan/bin/llama-bench`.
   - *Note on Version:* This embedded build is based on commit `073bb2c` (April 11, 2026). It is stable for this RDNA benchmarking suite, though not the absolute latest commit.

3. **llama-bench Executable (ROCm)**: The ROCm scripts use a locally compiled `llama-bench` at `../llm/llama.cpp-rocm/bin/llama-bench` and a ROCm runtime venv at `../llm/rocm-venv/`. Both are produced by the install script:
   ```bash
   cd llm
   ./install_rocm7_and_compile_llama.sh
   ```
   This takes ~10–20 minutes (mostly GPU kernel compilation for gfx1201). ROCm 7.13 nightly is installed into `../llm/rocm-venv/` via AMD's [TheRock](https://github.com/ROCm/TheRock) pip index — no system-level install or reboot required.
   - Works on **Ubuntu 25.10** (and 22.04 / 24.04). See [ROCm Ubuntu Compatibility & Workarounds](#rocm-ubuntu-compatibility--workarounds) for details.

## ROCm Ubuntu Compatibility & Workarounds

The AMD Radeon AI PRO R9700 (Navi 48, **gfx1201**, RDNA 4) is a ROCm-capable GPU, but AMD's official `amdgpu-install` packaging only supports specific Ubuntu LTS releases. This table summarises what works on each Ubuntu version and what workaround to use.

| Ubuntu Version | Codename | Official `amdgpu-install` | Recommended Method         | Notes                                                     |
| -------------- | -------- | ------------------------- | -------------------------- | --------------------------------------------------------- |
| 22.04 LTS      | jammy    | ✅ Supported               | Method 2 (AMD apt)         | Official LTS — use `amdgpu-install` directly              |
| 24.04 LTS      | noble    | ✅ Supported               | Method 2 (AMD apt)         | Official LTS — use `amdgpu-install` directly              |
| 24.10          | oracular | ❌ Blocked                 | **Method 1** (TheRock pip) | Non-LTS; `amdgpu-install` rejects codename                |
| 25.04          | plucky   | ❌ Blocked                 | **Method 1** (TheRock pip) | Non-LTS; `amdgpu-install` rejects codename                |
| 25.10          | questing | ❌ Blocked                 | **Method 1** (TheRock pip) | Non-LTS; same kernel 6.17 HWE as noble — fully functional |

> **Why LM Studio works on Ubuntu 25.10:** LM Studio bundles its own self-contained ROCm runtime and does not rely on a system-level install, so it bypasses the distro restriction entirely.

### Installation Methods

The install script supports three methods, selectable via the `METHOD` environment variable (default: `1`):

#### Method 1 — TheRock pip (recommended for Ubuntu 24.10 / 25.04 / 25.10)

Installs ROCm from AMD's community [TheRock](https://github.com/ROCm/TheRock) nightly index into a local Python venv. Distro-agnostic, full **gfx1201** support, no reboot required.

```bash
cd llm
./install_rocm7_and_compile_llama.sh
# ROCm is installed to ./llm/rocm-venv/
```

After building, activate the venv before running benchmarks:

```bash
source llm/rocm-venv/bin/activate
./benchmark/run_llm_benchmark_rocm.sh
```

#### Method 2 — AMD Official 7.2.3 apt repo (Ubuntu 22.04 / 24.04 or questing workaround)

Manually adds AMD's official `noble` apt repository, bypassing the `amdgpu-install` codename check. The packages are ABI-compatible with Ubuntu 25.x because both ship kernel 6.17 (HWE). Requires sudo and a **reboot**.

```bash
METHOD=2 ./install_rocm7_and_compile_llama.sh
```

On Ubuntu 22.04 or 24.04 you can also use the standard `amdgpu-install` tool:

```bash
wget https://repo.radeon.com/amdgpu-install/7.2.3.70203/ubuntu/noble/amdgpu-install_7.2.3.70203-1_all.deb
sudo apt install ./amdgpu-install_7.2.3.70203-1_all.deb
sudo amdgpu-install --usecase=rocm,hiplibsdk --no-dkms --accept-eula -y
```

#### Method 3 — TheRock nightly native .deb packages

Adds the TheRock nightly Debian repository and installs `amdrocm-core-sdk-gfx120x` as a system-wide package. Suitable when you want a conventional `/opt/rocm` layout accessible to all applications. Requires sudo and a **reboot**.

```bash
METHOD=3 ./install_rocm7_and_compile_llama.sh
```

### Why Ubuntu 24.04 (noble) kernel packages work on Ubuntu 25.10 (questing)

AMD's ROCm packages require two things: a compatible **amdgpu kernel driver** and a compatible **glibc**. Ubuntu 25.10 ships the same 6.17 HWE kernel as Ubuntu 24.04 and glibc 2.39, satisfying both requirements. The only barrier is a codename string check in `amdgpu-install`.

### Kernel driver note

For all methods, the `amdgpu` GPU kernel module is provided by the mainline Linux kernel (≥ 6.10 for basic RDNA 4 support, ≥ 6.12 recommended). No proprietary DKMS driver is required on Ubuntu 25.10 with kernel 6.17. The `--no-dkms` flag is set accordingly in the install script.

### Verifying ROCm is working

```bash
# Method 1 (venv)
source llm/rocm-venv/bin/activate
rocminfo | grep -A2 'gfx1201'

# Method 2 / 3 (system-wide)
/opt/rocm/bin/rocminfo | grep -A2 'gfx1201'
```

Expected output includes a device entry with `Name: gfx1201`.

---

## How to Run

### Vulkan benchmark (out-of-the-box)

```bash
cd benchmark
./run_llm_benchmark_vulkan.sh
```

No setup required — uses the pre-compiled `llm/llama.cpp-vulkan/bin/llama-bench` binary and the system Mesa/RADV driver.

### ROCm benchmark (maximum GPU performance)

**Step 1 — Install ROCm + compile llama.cpp** (first time only, ~10–20 min):
```bash
cd llm
./install_rocm7_and_compile_llama.sh
```
This installs ROCm 7.13 (TheRock nightly, gfx1201) into `llm/rocm-venv/` and builds llama.cpp into `llm/llama.cpp-rocm/`.

**Step 2 — Activate the ROCm venv**:
```bash
source llm/rocm-venv/bin/activate
```

**Step 3 — Run the benchmark**:
```bash
cd benchmark
./run_llm_benchmark_rocm.sh
```

Alternatively, skip venv activation by prefixing with the library path directly:
```bash
LD_LIBRARY_PATH=llm/rocm-venv/lib \
  benchmark/run_llm_benchmark_rocm.sh
```

> **Note:** The script auto-discovers all discrete RDNA GPUs and sets `HIP_VISIBLE_DEVICES` accordingly, excluding the integrated Cezanne iGPU. Use `--gpus 1`, `--gpus 0,1`, or `--gpus 0000:03:00.0` (or env-var `RDNA_GPUS=...`) to override. With more than one GPU selected, per-GPU passes plus a combined pass are run; add `--no-per-gpu-sweep` to skip the individual passes.

### vLLM benchmark (tensor parallel + FP8)

vLLM usage has been moved out of this benchmark document to keep concerns separated.

Use:
- [../vllm/README.md](../vllm/README.md)
- [../vllm/baremetal/](../vllm/baremetal/)
- [../vllm/docker/](../vllm/docker/)

Quick examples:

```bash
# Baremetal
cd ../vllm
./baremetal/install_vllm_rocm.sh
./baremetal/bench-vllm.sh --num-prompts 4 --input-len 256 --output-len 32

# Docker
./docker/run_vllm_aiter_0202_2x.sh up
./docker/bench_aiter_image_ab.sh
./docker/run_vllm_aiter_0202_2x.sh gui
./docker/run_vllm_aiter_0202_2x_stop.sh
./docker/run_vllm_aiter_0202_2x_restart.sh
```

## Results

Each benchmark run automatically logs the `llama-bench` output into a timestamped text file inside the `results` directory (e.g., `results/benchmark_results_20260513_153000.txt`).

These results logs can be used to compare baseline performance before and after tuning (e.g., overclocking VRAM or undervolting the core via `amd_radeon_rdna_tuning.sh`).

---

## Known Issue: ROCm High Idle Power Consumption (gfx1201 / R9700)

> **Reference**: [ROCm/ROCm#5706](https://github.com/ROCm/ROCm/issues/5706)

When using the **ROCm/HIP backend**, the R9700 remains at **~70–100W and 100% GFX activity** while idle (model loaded, no inference running). The **Vulkan backend does not have this issue** — Vulkan idles normally at ~10W.

### Root cause

A bug in the **MES (Microcode Engine Scheduler) firmware** causes HIP hardware queues to keep the GPU locked in a high-power state from initialization through process exit. The kernel patch (`drm/amdgpu: fix gpu idle power consumption issue for gfx v12`, commit `a6571045`) fixes this in MES firmware ≥ `0x8b`.

### Status (May 2026)

Ubuntu 25.10 with kernel 6.17 still ships MES firmware `0x84` — the fix has not yet landed in the Ubuntu `linux-firmware` package. You can verify your firmware version:

```bash
sudo cat /sys/kernel/debug/dri/1/amdgpu_firmware_info 2>/dev/null | grep -i mes
# or (if amd-smi is available):
sudo amd-smi firmware | grep -i mes
```

When the firmware reaches `0x8b` via a future `linux-firmware` update, the fix will be included automatically after a reboot.

### Workaround

Set `GPU_MAX_HW_QUEUES=1` before running any ROCm/HIP workload. This limits HIP to a single hardware queue, preventing the issue:

```bash
export GPU_MAX_HW_QUEUES=1
```

**Effect**: confirmed to drop idle power from ~90W to ~19–22W on a single R9700 with no measurable impact on single-GPU inference throughput.

This variable is already set automatically in `run_llm_benchmark_rocm.sh` and `llm/run_inference_rocm.sh`.

> **Note for multi-GPU setups**: `GPU_MAX_HW_QUEUES=1` limits queues globally. For multi-GPU inference set it to the number of GPUs (e.g. `GPU_MAX_HW_QUEUES=2` for two R9700s), otherwise ROCm may crash.

### Alternative: use the Vulkan backend

For single-GPU inference, the Vulkan backend is competitive in performance and has none of these idle power issues:

```bash
cd benchmark
./run_llm_benchmark_vulkan.sh
```

