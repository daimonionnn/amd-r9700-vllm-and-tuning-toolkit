# vLLM on R9700 (gfx1201)

This folder contains all vLLM-related automation for 1..N AMD Radeon AI PRO R9700 GPUs.

## Layout

- `baremetal/` — source-build / venv ROCm workflow wrappers.
- `docker/` — Docker workflow wrappers (community/public images).
- baremetal helpers:
  - `baremetal/patch_vllm.py`
  - `baremetal/hipcc-gfx1201-wrapper.sh`

## Baremetal workflow

Use this path when you want full local control and custom patching.

Main entry points:
- `baremetal/install_vllm_rocm.sh`
- `baremetal/run_vllm_server.sh`
- `baremetal/bench-vllm.sh`
- `baremetal/bench-vllm-suite.sh`
- `baremetal/bench-qwen36-27b.sh`
- `baremetal/sweep-qwen36-27b.sh`

Examples:

```bash
cd vllm
./baremetal/install_vllm_rocm.sh
./baremetal/run_vllm_server.sh --gpus all
./baremetal/bench-vllm.sh --num-prompts 4 --input-len 256 --output-len 32
```

## Docker workflow

Use this path when you want parity with public community images.

Main entry points:
- `docker/run_vllm_aiter_0202_tp2.sh` (Tensor Parallel setup - Note: highly sensitive to PCIe speed/bandwidth)
- `docker/run_vllm_aiter_0202_pp2.sh` (Pipeline Parallel setup - highly recommended for dual R9700 on limited PCIe bandwidth)
- `docker/bench_llama_benchy.sh` & `docker/bench_llama_benchy_pp.sh` (1:1 standard benchmarking tool)
- `docker/bench_aiter_image_ab.sh`
- `docker/docker-compose.aiter-0202.tp2-r9700.yml` & `docker-compose.aiter-0202.pp2-r9700.yml`
- `docker/gui/` — browser prompt UI served on port 8080

Examples:

```bash
cd vllm
# Tensor Parallel run
./docker/run_vllm_aiter_0202_tp2.sh pull
./docker/run_vllm_aiter_0202_tp2.sh up
./docker/run_vllm_aiter_0202_tp2.sh logs

# Pipeline Parallel run (Bypasses PCIe bandwidth limitations across GPUs via sequential layer placement)
./docker/run_vllm_aiter_0202_pp2.sh up

# browser GUI (starts vLLM + GUI)
./docker/run_vllm_aiter_0202_tp2.sh gui
./docker/run_vllm_aiter_0202_tp2_gui.sh
./docker/run_vllm_aiter_0202_pp2_gui.sh

# stop / restart the Docker stack
./docker/run_vllm_aiter_0202_tp2_stop.sh
./docker/run_vllm_aiter_0202_tp2_restart.sh
./docker/run_vllm_aiter_0202_pp2_restart.sh
```

A/B image compare and Benchmarking:

The `bench_llama_benchy*.sh` scripts use an installed `llama-benchy` command when available, or `uvx llama-benchy` as a fallback. Set `LLAMA_BENCHY_CMD` to override the command, for example `LLAMA_BENCHY_CMD='uvx llama-benchy'`.

```bash
cd vllm
# Dedicated llama-benchy run (standard metrics via PP2 layout)
./docker/bench_llama_benchy_pp.sh

# Dedicated A/B compare script
./docker/bench_aiter_image_ab.sh

# quick run
DEPTHS="4096 16000" NUM_PROMPTS=8 ./docker/bench_aiter_image_ab.sh

# no re-pull (requires cached images)
PULL_POLICY=never DEPTHS="4096 16000" NUM_PROMPTS=8 ./docker/bench_aiter_image_ab.sh
```

If a matching container image is already running, the benchmark reuses it instead of starting a fresh one.

Artifacts are emitted under `vllm/results/ab_aiter_images_*/`.

## Notes

- First Docker run can take a long time because image layers are large.
- For two GPUs, keep `GPU_MAX_HW_QUEUES=2` in Docker env.
- **PCIe Bandwidth Sensitivity:** Tensor Parallelism (TP) communicates heavily across the PCIe bus. When running dual GPUs on restricted PCIe links (e.g., heavily bifurcated slots like Gen1/Gen2 x4), you will experience severe TTFT and prefill bottlenecks. For setups with restricted PCIe bandwidth, use the **Pipeline Parallel (PP)** scripts instead, which bypass the constant cross-GPU communication.


## Benchmarking Examples on R9700

When splitting Qwen 3.6 27B across 2x R9700 GPUs on restricted PCIe links, Pipeline Parallelism offers significantly higher prompt processing logic (Prefill) than Tensor Parallelism, completely bypassing the PCIe bottlenecks between the GPUs layer computations.

**Pipeline Parallelism (PP=2) (High Prefill, lower Decode):**
| model                |           test |            t/s |     peak t/s |      ttfr (ms) |   est_ppt (ms) |  e2e_ttft (ms) |
| :------------------- | -------------: | -------------: | -----------: | -------------: | -------------: | -------------: |
| Qwen/Qwen3.6-27B-FP8 | pp2048 @ d4096 | 3116.17 ± 0.00 |              | 1972.91 ± 0.00 | 1971.97 ± 0.00 | 1972.91 ± 0.00 |
| Qwen/Qwen3.6-27B-FP8 |   tg32 @ d4096 |   17.88 ± 0.00 | 18.00 ± 0.00 |                |                |                |
| Qwen/Qwen3.6-27B-FP8 | pp2048 @ d8132 | 3174.03 ± 0.00 |              | 3208.23 ± 0.00 | 3207.28 ± 0.00 | 3208.23 ± 0.00 |
| Qwen/Qwen3.6-27B-FP8 |   tg32 @ d8132 |   17.72 ± 0.00 | 18.00 ± 0.00 |                |                |                |

*Using `bench_llama_benchy_pp.sh` & `run_vllm_aiter_0202_pp2.sh`*

**Tensor Parallelism (TP=2) Reference (Low Prefill on heavily bifurcated lanes):**
Without Pipeline Parallelism on a PCIe Gen2 x2/x4 bottleneck, prefill drops significantly (~333-620 t/s) as the constant cross-GPU syncing crushes the available link bandwidth.

**TP=2 on full PCIe 5.0 (June 17, 2026 — Intel Z890 platform):** with both R9700s on
a non-bifurcated PCIe 5.0 link, TP=2 prefill recovers to ~1786–1841 t/s (~3–5.5× the
bifurcated numbers above) **and** keeps high decode (~71–80 t/s vs PP=2's ~18 t/s):

| model                |           test |     t/s | peak t/s |
| :------------------- | -------------: | ------: | -------: |
| Qwen/Qwen3.6-27B-FP8 | pp2048 @ d4096 | 1840.89 |          |
| Qwen/Qwen3.6-27B-FP8 |   tg32 @ d4096 |   80.46 |    83.05 |
| Qwen/Qwen3.6-27B-FP8 | pp2048 @ d8132 | 1786.05 |          |
| Qwen/Qwen3.6-27B-FP8 |   tg32 @ d8132 |   71.00 |    73.29 |

So **PCIe bandwidth — not TP itself — was the problem.** On restricted/bifurcated
lanes prefer **PP=2**; on a full PCIe 4.0/5.0 x8+ link per card, **TP=2** is the better
all-round choice (high prefill *and* high decode). Full results and caveats:
[../benchmark/R9700_benchmarks.md](../benchmark/R9700_benchmarks.md#vllm-tp2--intel-z890-platform-migration-june-17-2026).
