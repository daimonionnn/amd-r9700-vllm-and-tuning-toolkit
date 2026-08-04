# Documentation

Written-up findings, field notes and investigations for the dual-R9700 tuning
toolkit. Usage/how-to lives in each tool folder's own `README.md`
([`../README.md`](../README.md), [`../vllm/README.md`](../vllm/README.md),
[`../benchmark/README.md`](../benchmark/README.md)); this folder is the narrative
"what we learned and why" companion to those.

> **⚠️ Read this first if you are reading the benchmark numbers:**
> [`r9700-mem-vendor-bios-variance.md`](r9700-mem-vendor-bios-variance.md). The
> two cards used for every dual-GPU result in this repo were **not** matched —
> one (Samsung/F40) has a factory thermal-interface defect that throttles it, and
> under TP=2 it gates the healthy card. The repo's ~1841–1894 t/s TP=2 prefill is
> therefore a **lower bound**, not the ceiling for a healthy pair.

## Index

| Document | What it covers |
|:----|:----|
| [r9700-mem-vendor-bios-variance.md](r9700-mem-vendor-bios-variance.md) | The two "identical" R9700s differ in GDDR6 vendor (Hynix vs Samsung) and VBIOS (F50 vs F40), and tune differently. Includes the **thermal investigation** that traced card2's ~7 % prefill/power deficit to a die-to-heatsink defect (an RMA case), not weaker silicon. |
| [r9700-oc-uv-findings.md](r9700-oc-uv-findings.md) | Overclock / undervolt results. On the current ROCm 7.14 / amdgpu DKMS 6.19.4 stack, memory-clock OD and core undervolt are no-ops or slightly harmful for inference; only the fan curve and a couple of boot args matter. Community reference settings included. Also documents why **runtime PM silently breaks the LACT undervolt** ("Failed to upload overdrive table!") and the two fixes. |
| [rdna4-fp8-findings.md](rdna4-fp8-findings.md) | vLLM FP8 prefill investigation (gfx1201): why AITER linear/quant can't compile on RDNA4, what's already in the `aml731/vllm-aiter` image, and the launch flags that closed most of the gap to community runs. |
| [dual-gpu-bifurcation-notes.md](dual-gpu-bifurcation-notes.md) | Hardware field notes from the original B450 + Ryzen 5700G rig: broken `x8/x8` bifurcation, Gen1-x4 link training on the second slot, and the `setpci` Gen2 retrain workaround. |
| [TODO.md](TODO.md) | Open optimization ideas and next steps (the project is currently on hold — see the root README). |

## Related (kept with their tooling)

- [../benchmark/R9700_benchmarks.md](../benchmark/R9700_benchmarks.md) — the raw
  llama.cpp / vLLM benchmark result log (co-located with the benchmark scripts
  that produce it).
