# TODO — open optimization ideas & next steps

The project is **on hold** (see the [root README](../README.md#project-status)) —
most of these need the 2× R9700 hardware back before they can be done. They are
ordered roughly by expected payoff. Each notes whether it is **blocked** on
hardware or **doable now** on paper.

## 1. Re-baseline on a healthy pair (biggest win) — *blocked*
The headline TP=2 prefill (~1841–1894 t/s) was gated by card2's factory
thermal-interface defect. Before anything else:
- Complete the card2 RMA (or repaste/reseat its cooler) and re-baseline TP=2.
- Expect **~1965 t/s prefill from the hardware alone** (~6–10 %), *before* any
  software tuning is stacked on top.
- **Gate the measurement:** confirm both cards hold full clocks at the 300 W cap and
  a sane hotspot−edge delta (`benchmark/thermal-test.sh` / `thermal-log.sh`) so a
  thermal defect can't silently cap the result again.
- Background: [r9700-mem-vendor-bios-variance.md](r9700-mem-vendor-bios-variance.md#consequence-for-the-tp2-prefill-benchmarks).

## 2. Self-tune the missing FP8 block-GEMM configs — *blocked (needs GPU)*
The one un-pulled software lever from
[rdna4-fp8-findings.md](rdna4-fp8-findings.md#open-lever-not-done). vLLM ships **zero**
R9700 configs; 5 Qwen3.6-27B shapes fall back to a default kernel config:
`(17408,5120)` gate_up, `(5120,8704)` down, `(8192,5120)` qkv, `(7168,5120)`
qkv-gated, `(5120,3072)` o_proj.
- Patch `get_weight_shapes` (hardcoded to DeepSeek-V3/R1) to the shapes above and run
  `benchmarks/kernels/benchmark_w8a8_block_fp8.py --tp-size 1`.
- Multi-hour CPU-bound Triton grind for a bounded but real gain on top of the
  committed launch flags.

## 3. Track newer vLLM / AITER images — *doable now (monitor), verify later*
- `aml731/vllm-aiter:v0.21.0` **hangs on startup** (TP worker stalls on
  `allreduce_rms_fusion`). Re-test each newer tag for a fix.
- `VLLM_ROCM_USE_AITER_LINEAR=1` can't compile on gfx1201 (`module_quant` needs
  `vmem-to-lds-load-insts`). Re-test when the image's ROCm/LLVM toolchain updates —
  if it ever compiles, it's a potential fast path.

## 4. Re-check OD MCLK semantics on newer amdgpu DKMS — *doable now (monitor)*
amdgpu DKMS 6.19.4 silently caps `OD_MCLK` to the 1258 MHz DPM top (an earlier build
let `m 1 1350` replace the top DPM step and gave ~+4–5 %). Watch DKMS release notes;
if replacement-DPM semantics return, re-test memory OC.
See [r9700-oc-uv-findings.md](r9700-oc-uv-findings.md).

## 5. Re-validate boot-arg wins on the Z890 platform — *blocked*
`pcie_aspm.policy=performance` (+10.8 % dense decode) and `amdgpu.ras_enable=0` were
measured on the old B450/Ryzen rig. Confirm they still help on the Intel Z890 / full
PCIe 5.0 platform.

## 6. Promote `--kv-cache-dtype fp8` to a documented toggle — *doable now (docs)*
It adds ~3 % prefill but costs ~20 % deep-context decode, so it's not a default.
Wire it as an opt-in flag in the compose/launch scripts for prefill-heavy workloads
rather than leaving it only as a note.

## 7. Pre-benchmark health-check script — *doable now (code)*
A small wrapper that samples per-card junction/edge/power/clock during warm-up and
**refuses to benchmark (or warns loudly)** if the hotspot−edge delta or a
power-ceiling shortfall signals a thermal defect. This would have caught card2's
defect before it silently capped the TP=2 numbers.

## 8. PP=2 vs TP=2 decision doc — *doable now (docs)*
The PP-vs-TP guidance is scattered across README notes. A short decision doc keyed on
measured per-slot PCIe width (`lspci -vv … LnkSta`) would make the choice mechanical.

## 9. Broaden model coverage — *blocked*
Benchmarks are Qwen3.6-27B and Gemma4. Adding a couple more architectures (dense vs
MoE) would show how well the tuning findings generalize.

## 10. Add a summary table to the raw benchmark log — *doable now (docs, low priority)*
`benchmark/R9700_benchmarks.md` is a long append-only log. A "best result per
model/backend" summary table at the top would make it navigable. (Clear transcription
typos in the command echoes were fixed; the `qwen35` vs `qwen36` model-label
difference in the captured `llama-bench` tables is left as-is, since it may reflect
genuinely different output between llama.cpp builds rather than a typo.)
