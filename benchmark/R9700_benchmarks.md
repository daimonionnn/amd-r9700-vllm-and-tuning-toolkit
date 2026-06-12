# R9700 Benchmark Results (AMD Radeon GFX1201)

## Run Parameters
- **GPU Backend:** Vulkan + Rocm 7.2.3 (reference settings + overclocked)
- **VRAM Offloading:** Full (Enabled, `-ngl 99`)
- **Flash Attention:** Enabled (`-fa 1`)
- **Context Windows (Prompt Tokens):** 1024, 4096, 32768
- **Generation Tokens:** 128
- **llama.cpp Version:** Build `073bb2c`


## Vulkan

## Model: Qwen 3.6 27B

*(Note: `llama-bench` outputs the model designator as `qwen36 27B` rather than 3.6. This is because the internal GGUF metadata architecture maps natively to the `qwen36` structure branch inside `llama.cpp`.)*

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |          pp1024 |        889.16 ± 1.01 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |          pp4096 |        868.53 ± 2.82 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |         pp32768 |        729.89 ± 1.29 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |  1 |           tg128 |         30.33 ± 0.04 |



----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf  + KV cache set to Q8 instead of FP16
----------------------------------------------------------
Command: llama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | type_k | type_v | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | -----: | -----: | --: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |          pp1024 |        874.26 ± 0.90 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |          pp4096 |        839.25 ± 2.74 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |         pp32768 |        628.97 ± 1.94 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | Vulkan     |  99 |   q8_0 |   q8_0 |  1 |           tg128 |         30.04 ± 0.01 |


## Model: Gemma4 31B

----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |          pp1024 |        719.26 ± 0.18 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |          pp4096 |        694.06 ± 0.76 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |         pp32768 |        569.66 ± 0.07 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | Vulkan     |  99 |  1 |           tg128 |         27.73 ± 0.04 |



## Model: Gemma4 26B
----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-vulkan/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128


| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 26B Q4_K - Medium       |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |          pp1024 |      2936.84 ± 27.26 |
| gemma4 26B Q4_K - Medium       |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |          pp4096 |      2860.95 ± 14.30 |
| gemma4 26B Q4_K - Medium       |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |         pp32768 |       2318.21 ± 5.86 |
| gemma4 26B Q4_K - Medium       |  15.63 GiB |    25.23 B | Vulkan     |  99 |  1 |           tg128 |        108.72 ± 0.52 |


## RoCm 7.2.3


## Model: Qwen 3.6 27B

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1036.56 ± 0.79 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |        974.38 ± 2.62 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        659.45 ± 1.73 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         27.42 ± 0.04 |



## Model: Gemma4 31B

----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp1024 |        849.32 ± 0.65 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp4096 |        743.82 ± 0.19 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |         pp32768 |        467.26 ± 0.04 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |           tg128 |         25.53 ± 0.06 |


## Model: Gemma4 26B

----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp1024 |      3427.14 ± 37.01 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp4096 |       3018.94 ± 9.62 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |         pp32768 |       1887.41 ± 9.41 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |           tg128 |         93.39 ± 0.91 |



-----------------------------------------------------------------------------------------------------------------------------
## Memory Overclocked + Undervolt GPU benchmarks
    Memory-clock 1350
    Undervolt -75mV
    TDP 300W (same as reference)
-----------------------------------------------------------------------------------------------------------------------------


## Model: Qwen 3.6 27B
----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1076.88 ± 0.86 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1011.53 ± 1.97 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        690.40 ± 1.08 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         28.80 ± 0.03 |


## Model: Gemma4 31B
----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp1024 |        892.00 ± 0.25 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp4096 |        779.73 ± 0.18 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |         pp32768 |        488.26 ± 0.03 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |           tg128 |         26.77 ± 0.06 |

## Model: Gemma4 26B

----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp1024 |      3440.87 ± 20.10 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp4096 |      3042.79 ± 26.98 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |         pp32768 |       1946.48 ± 4.51 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |           tg128 |         96.61 ± 1.56 |





-----------------------------------------------------------------------------------------------------------------------------
## TDP 210W (Memory Overclocked + Undervolt) GPU benchmarks
    Memory-clock 1350
    Undervolt -75mV
    TDP 210W 
-----------------------------------------------------------------------------------------------------------------------------


## Model: Qwen 3.6 27B
----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: lama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |        962.04 ± 0.67 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |        907.26 ± 1.59 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        619.88 ± 2.20 |
| qwen36 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         26.28 ± 0.03 |



## Model: Gemma4 31B

----------------------------------------------------------
 Benchmarking Model: gemma-4-31B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-31B-it-GGUF/gemma-4-31B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp1024 |        795.82 ± 0.28 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |          pp4096 |        698.59 ± 0.47 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |         pp32768 |        440.89 ± 0.03 |
| gemma4 31B Q4_K - Medium       |  17.39 GiB |    30.70 B | ROCm       |  99 |  1 |           tg128 |         23.82 ± 0.04 |



## Model: Gemma4 26B

----------------------------------------------------------
 Benchmarking Model: gemma-4-26B-A4B-it-Q4_K_M.gguf
----------------------------------------------------------
Command: llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp1024 |      3119.01 ± 13.34 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |          pp4096 |      2763.28 ± 14.72 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |         pp32768 |       1762.45 ± 2.80 |
| gemma4 26B.A4B Q4_K - Medium   |  15.63 GiB |    25.23 B | ROCm       |  99 |  1 |           tg128 |         90.08 ± 0.52 |




## Overclock benchmark UPDATE:

TheRock nightly 7.14.0~20260522

Benchmark run with preset /tunning/tune_r9700_max.sh
( memory-clock 1350, undervolt-offset -120m, tdp 300 )


## PCIe ASPM Performance Mode
echo "performance" | sudo tee /sys/module/pcie_aspm/parameters/policy

## Performance level
rocm-smi --setperflevel auto


---------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128

gml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1147.43 ± 1.18 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1083.27 ± 1.79 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        724.73 ± 1.59 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         28.23 ± 0.05 |


-----------------------------------------------------------------------------------------------------------------------------
## Dual-GPU PCIe Bifurcation Benchmarks
   GPU 0 (0000:03:00.0): R9700 at PCIe Gen3 x8
   GPU 1 (0000:0f:00.0): R9700 at PCIe Gen1 x4
   Tune preset: /tunning/tune_r9700_max.sh (memory-clock 1350, undervolt-offset -120mV, tdp 300W)
   PCIe ASPM: performance
   Performance level: auto
   llama.cpp build: a9883db8e (9127)
-----------------------------------------------------------------------------------------------------------------------------


### Pass 1 — Solo GPU 0 (0000:03:00.0, Gen3 x8)

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128
Env: HIP_VISIBLE_DEVICES=0

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1109.86 ± 1.04 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1041.80 ± 3.69 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |        695.83 ± 0.94 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         28.71 ± 0.06 |


### Pass 2 — Solo GPU 1 (0000:0f:00.0, Gen1 x4)

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128
Env: HIP_VISIBLE_DEVICES=1

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1064.77 ± 2.46 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |        993.76 ± 4.34 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |       598.86 ± 14.52 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         27.75 ± 0.04 |


### Pass 3 — Combined Dual GPU (0000:03:00.0 Gen3 x8 + 0000:0f:00.0 Gen1 x4)

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128
Env: HIP_VISIBLE_DEVICES=0,1

ggml_cuda_init: found 2 ROCm devices (Total VRAM: 65248 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
  Device 1: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1265.70 ± 1.24 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1604.70 ± 1.41 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |       1153.24 ± 3.53 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         24.67 ± 0.05 |


#### Observations
- The Gen1 x4 GPU (0f:00.0) shows a modest single-GPU penalty vs the Gen3 x8 GPU (03:00.0): ~4% lower pp1024, ~4.5% lower pp4096, ~14% lower pp32768, ~3% lower tg128 — confirming PCIe bandwidth chiefly impacts long-context prompt processing while small-context PP and TG remain mostly compute-bound.
- Combined dual-GPU PP scales positively at mid/long contexts (pp4096 ≈ 1.54× Gen3-solo, pp32768 ≈ 1.66× Gen3-solo) despite the asymmetric link widths, indicating tensor-split work overlaps PCIe transfers effectively.
- Combined TG is ~14% lower than Gen3-solo (24.67 vs 28.71 t/s) — typical for split single-batch decode where the slower link gates per-token sync.


-----------------------------------------------------------------------------------------------------------------------------
## Dual-GPU PCIe Bifurcation Benchmarks — after `setpci` retrain to Gen2 x4
   GPU 0 (0000:03:00.0): R9700 at PCIe Gen3 x8 (unchanged)
   GPU 1 (0000:0f:00.0): R9700 at **PCIe Gen2 x4** (was Gen1 x4 — see ../tuning/force_pcie_link.sh and ../docs/dual-gpu-bifurcation-notes.md)
   Tune preset: /tunning/tune_r9700_max.sh (memory-clock 1350, undervolt-offset -120mV, tdp 300W)
   PCIe ASPM: performance
   Performance level: auto
   llama.cpp build: a9883db8e (9127)
-----------------------------------------------------------------------------------------------------------------------------


### Pass 1 — Solo GPU 0 (0000:03:00.0, Gen3 x8)

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128
Env: HIP_VISIBLE_DEVICES=0

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1113.00 ± 0.53 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1047.48 ± 2.74 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |       666.27 ± 12.28 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         28.45 ± 0.03 |


### Pass 2 — Solo GPU 1 (0000:0f:00.0, **Gen2 x4** after setpci retrain)

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128
Env: HIP_VISIBLE_DEVICES=1

ggml_cuda_init: found 1 ROCm devices (Total VRAM: 32624 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1089.43 ± 1.83 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1027.64 ± 3.54 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |       641.03 ± 11.94 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         28.04 ± 0.12 |


### Pass 3 — Combined Dual GPU (0000:03:00.0 Gen3 x8 + 0000:0f:00.0 **Gen2 x4**)

----------------------------------------------------------
 Benchmarking Model: Qwen3.6-27B-Q4_K_M.gguf
----------------------------------------------------------
Command: llm/llama.cpp-rocm/bin/llama-bench -m ~/.lmstudio/models/lmstudio-community/Qwen3.6-27B-GGUF/Qwen3.6-27B-Q4_K_M.gguf -ngl 99 -fa 1 -p 1024,4096,32768 -n 128
Env: HIP_VISIBLE_DEVICES=0,1

ggml_cuda_init: found 2 ROCm devices (Total VRAM: 65248 MiB):
  Device 0: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
  Device 1: AMD Radeon AI PRO R9700, gfx1201 (0x1201), VMM: no, Wave Size: 32, VRAM: 32624 MiB
| model                          |       size |     params | backend    | ngl | fa |            test |                  t/s |
| ------------------------------ | ---------: | ---------: | ---------- | --: | --: | --------------: | -------------------: |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp1024 |       1300.77 ± 1.01 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |          pp4096 |       1682.51 ± 2.52 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |         pp32768 |       1210.40 ± 9.58 |
| qwen35 27B Q4_K - Medium       |  15.40 GiB |    26.90 B | ROCm       |  99 |  1 |           tg128 |         24.00 ± 0.04 |


#### Observations — Gen2 x4 vs Gen1 x4 on GPU 1

| Test       |    Solo GPU 1 Gen1 x4 |    Solo GPU 1 **Gen2 x4** |   Δ vs Gen1 |    Gap to Gen3 x8 (GPU 0) |
| ---------- | --------------------: | ------------------------: | ----------: | ------------------------: |
| pp1024     |           1064.77 t/s |               1089.43 t/s |      +2.3 % |                    −2.1 % |
| pp4096     |            993.76 t/s |               1027.64 t/s |      +3.4 % |                    −1.9 % |
| pp32768    |            598.86 t/s |                641.03 t/s |      +7.0 % |                    −3.8 % |
| tg128      |             27.75 t/s |                 28.04 t/s |      +1.0 % |                    −1.4 % |

| Test       |    Combined Gen3+**Gen1** |    Combined Gen3+**Gen2** |        Δ |    vs Solo Gen3 (GPU 0) |
| ---------- | ------------------------: | ------------------------: | -------: | ----------------------: |
| pp1024     |               1265.70 t/s |               1300.77 t/s |   +2.8 % |                   1.17× |
| pp4096     |               1604.70 t/s |               1682.51 t/s |   +4.8 % |                   1.61× |
| pp32768    |               1153.24 t/s |               1210.40 t/s |   +5.0 % |                   1.82× |
| tg128      |                 24.67 t/s |                 24.00 t/s |   −2.7 % |                 −15.6 % |

- **Solo penalty on GPU 1 nearly eliminated.** After the Gen2 retrain, the gap to the Gen3 x8 GPU collapses from ~4–14 % to ~2–4 % across all PP contexts and to ~1 % on TG. The remaining gap at pp32768 (−3.8 %) is consistent with Gen2 x4 still being half the bandwidth of Gen3 x8 — long-context PP is the only test where that gap stays visible.
- **Combined PP scaling improved at every context length** (+3 % at pp1024, +5 % at pp4096/pp32768). Most striking: pp32768 dual-GPU now reaches **1.82× solo Gen3** (up from 1.66× before), so the asymmetric-link tax on tensor-split long-context prompt processing is largely paid off.
- **Combined TG dipped slightly (24.67 → 24.00 t/s, −2.7 %).** Run-to-run variance is plausible, but a real small regression isn't implausible either: with the slower link sped up, ROCm may now schedule more per-token cross-GPU traffic than before. Still well within the expected single-batch split-decode penalty vs solo Gen3.
- **Bottom line:** the `setpci` retrain converts GPU 1 from a clearly-handicapped second-class member into a near-peer of the Gen3 x8 GPU for inference. PP throughput is now the headline win; TG is essentially flat.


