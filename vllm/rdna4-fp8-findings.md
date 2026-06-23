# RDNA4 (gfx1201 / R9700) FP8 prefill — investigation findings

Context: vLLM TP=2, `Qwen/Qwen3.6-27B-FP8`, docker image `aml731/vllm-aiter:v0.20.2`,
2× AMD Radeon AI PRO R9700 on the Intel Z890 platform. A community user reported
**~2567 t/s** pp2048@d4096 on the *same image*, vs our **~1841**. This documents
what was ruled out and the configuration that closed most of the gap.

## TL;DR

- The hardware and the image's FP8 fast path are both fine; **~1841–1965 t/s is the
  real prefill ceiling** for this hardware + model + stack (an independent
  [localmaxxing](https://www.localmaxxing.com) 2× R9700 run lands at 1965). The 2567
  is an outlier (different bench depth/warmup or a private tuned-config pack).
- A few launch flags from that community run give **+~3 % prefill with no downside**
  and are now the committed default (see below).

## Levers investigated

### Hardware — optimal, not the bottleneck
- Both cards negotiate **PCIe 5.0 x8 at the root port**, trained to max, symmetric
  (read past the on-card PCIe switch — the GPU endpoint's `current_link_*` always
  shows the internal switch link `32 GT/s x16` and is misleading).
- `power1_cap` = 300 W, `power_dpm_force_performance_level` = `auto`, no undervolt.

### AITER linear/quant fast path — impossible on gfx1201
`VLLM_ROCM_USE_AITER_LINEAR=1` (and `fuse_norm_quant:true`) crash at startup because
AITER JIT-compiles `module_quant`, which fails for gfx1201:

```
/app/aiter/csrc/include/opus/opus.hpp:1206:50: error:
'__builtin_amdgcn_raw_ptr_buffer_load_lds' needs target feature vmem-to-lds-load-insts
1 error generated when compiling for gfx1201.
```

This is a **toolchain/RDNA4 incompatibility** (a GCN buffer-load-to-LDS builtin not
enabled for gfx1201 in this image's ROCm/LLVM), not a missing dependency. It fails for
*everyone* on this image + R9700, so it cannot be the source of anyone's speed
advantage. This is exactly why the compose ships with `VLLM_ROCM_USE_AITER_LINEAR=0`.

### Native FP8 WMMA — already present in the image
The "default vLLM dequantizes FP8→FP32 on RDNA4" problem (and its ~2× patch) is
**already applied** in `aml731/vllm-aiter:v0.20.2`:
- `vllm/platforms/rocm.py`: `_ON_MI3XX = any(arch in _GCN_ARCH for arch in ["gfx942","gfx950","gfx1201"])`
  (gfx1201 is in `on_mi3xx()`), and `"0x7551": "AMD_Radeon_R9700"`.
- `fp8_utils.py` uses `w8a8_triton_block_scaled_mm` (native block-scaled FP8 GEMM), not
  `torch._scaled_mm(out_dtype=float32)`.

So there is no 2× to recover from a WMMA patch here.

### Tuned FP8 block GEMM configs — not downloadable
vLLM emits `Using default W8A8 Block FP8 kernel config ... config file not found` for 5
Qwen3.6-27B shapes (post-TP-shard): `(17408,5120)` gate_up, `(5120,8704)` down,
`(8192,5120)` qkv, `(7168,5120)` qkv-gated, `(5120,3072)` o_proj.
- vLLM **upstream ships zero R9700 configs**; the image's R9700 configs are tuned for
  **DeepSeek** shapes (the tuner's `get_weight_shapes` is hardcoded to DeepSeek-V3/R1).
- No public downloadable pack exists for R9700 + Qwen3.6-27B; the RDNA4-FP8 community
  even uses a different naming scheme (`device_name=0x7551` vs `AMD_Radeon_R9700`).
- Generating them via `benchmarks/kernels/benchmark_w8a8_block_fp8.py` is a multi-hour
  **CPU-bound Triton compilation** grind for a bounded gain — not pursued.

### v0.21.0 image — not a drop-in
`aml731/vllm-aiter:v0.21.0` **hangs on startup** with this config (TP worker stalls on
the new `allreduce_rms_fusion` path), so the newer tag is not a simple upgrade.

## What actually helped: launch flags

Borrowed from a reproducible 2× R9700 localmaxxing run (1965 t/s prefill). Benched
pp2048/tg32 at d4096/d8132, `--runs 1`:

| config                                                      |   pp@d4096 |   pp@d8132 | tg@d4096 | tg@d8132 |
| ----------------------------------------------------------- | ---------: | ---------: | -------: | -------: |
| baseline                                                    |     1840.9 |     1786.1 |     80.5 |     71.0 |
| **+max-num-batched-tokens 8192 +disable-custom-all-reduce** | **1893.6** | **1839.4** | **81.6** | **72.2** |
| + kv-cache-dtype fp8                                        |     1959.6 |     1928.5 |     80.8 |     65.1 |
| + max-num-seqs 1 (single-stream)                            |     1903.5 |     1849.7 |     81.1 |     80.7 |

**Committed default** (`docker/docker-compose.aiter-0202.tp2-r9700.yml`):
`--max-num-batched-tokens 8192` + `--disable-custom-all-reduce` → +~3 % prefill, decode
unchanged, no downside.

Optional, situational:
- `--kv-cache-dtype fp8`: +~3 % more prefill but ~20 % worse deep-context decode (71→65). Not default.
- `VLLM_MAX_NUM_SEQS=1`: better deep-context decode (72→81) + a little prefill, at the cost
  of serving concurrency. Use it if you run one request at a time.

## Open lever (not done)
Self-tuning the 5 missing FP8 block configs for the Qwen3.6-27B shapes could add a bit
more on top, but it's a multi-hour offline tune for a bounded, uncertain gain. The
tuner's shape list (`get_weight_shapes`) must be patched to the shapes above and run with
`--tp-size 1`.
