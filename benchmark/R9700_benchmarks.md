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

---

## vLLM TP=2 — Intel Z890 platform migration (June 17, 2026)

Re-test after migrating the 2× R9700 from the Ryzen 5700G / B450 board (PCIe Gen3
x8 + bifurcated Gen1/Gen2 x4 second card) to a new Intel platform. **No code
changes were needed for GPU plumbing** — auto-detection, iGPU exclusion and the
index-based TP2 stack all work unchanged (one blocking bug was fixed: the docker
bench scripts referenced a nonexistent `docker-compose.aiter-0202.2x-r9700.yml`,
now repointed to `…tp2-r9700.yml`).

**New hardware:** Intel Core Ultra 5 250K Plus, ASUS ProArt Z890-Creator,
96 GB DDR5-6000 CL30, 2× R9700 at PCIe 5.0 (BDFs `0000:03:00.0` + `0000:07:00.0`
— the second card's BDF changed from the old `0f:00.0`). Intel Arrow Lake iGPU
present but unused (vendor-filtered out by `rdna_detect.sh`).

**Stack:** docker `aml731/vllm-aiter:v0.20.2`, `Qwen/Qwen3.6-27B-FP8`, TP=2,
`ROCM_AITER_UNIFIED_ATTN`, MTP speculative decode (`num_speculative_tokens=3`),
`--max-num-seqs 2`, 300 W default power cap. Both GPUs ran at 100 % / ~245–250 W;
RCCL all-reduce completed with 0 failed requests, confirming the cross-GPU path
is healthy on the new link.

> **PCIe width note:** sysfs `current_link_speed`/`current_link_width` reports
> `32 GT/s x16` even at 11 W idle, i.e. it shows the card's max capability, not
> the live-negotiated width. Confirm the real per-slot width with
> `sudo lspci -vv -s 03:00.0 -s 07:00.0 | grep LnkSta`. Either way it is PCIe 5.0
> (16–32 GB/s) vs the old second card's ~0.85–1.7 GB/s.

### llama-benchy (`bench_llama_benchy.sh`, depths 4096/8132)

| model                |           test |        t/s (new) |   peak t/s |   ttfr (ms) |
| :------------------- | -------------: | ---------------: | ---------: | ----------: |
| Qwen/Qwen3.6-27B-FP8 | pp2048 @ d4096 |      **1840.89** |            |     3339.04 |
| Qwen/Qwen3.6-27B-FP8 |   tg32 @ d4096 |        **80.46** |      83.05 |             |
| Qwen/Qwen3.6-27B-FP8 | pp2048 @ d8132 |      **1786.05** |            |     5701.25 |
| Qwen/Qwen3.6-27B-FP8 |   tg32 @ d8132 |        **71.00** |      73.29 |             |

**vs old platform (TP=2):** the README's documented old-TP2 reference had prefill
collapsing to ~333–620 t/s on the bifurcated Gen1/Gen2 x4 lanes. New prefill of
~1786–1841 t/s is a **~3–5.5× improvement** — full PCIe 5.0 removes the cross-GPU
sync bottleneck that previously made TP2 unusable.

> Note: the earlier saved `llama_benchy_20260601_105457` result (pp2048 ≈ 3116 t/s,
> tg32 ≈ 17.9 t/s) is a **PP=2** run, not TP=2 — its high-prefill/low-decode shape
> is PP's signature. On the old rig PP=2 was the only workable dual-GPU mode. On
> the new platform TP=2 recovers ~1800 t/s prefill **and** keeps ~80 t/s decode
> (vs PP=2's ~18 t/s) — the best of both, which the bifurcated rig could not do.

### vllm bench serve (100 prompts × 1024 in / 512 out, `--max-num-seqs 2`)

Two runs: `request_rate=inf` (saturation throughput) and `--max-concurrency 2`
(client matched to the server's 2-seq cap, so the latency numbers are real). As
expected the server cap is the bottleneck — throughput and wall time are
identical between the two; only the latency metrics differ.

| metric                          | request_rate=inf | --max-concurrency 2 |
| :------------------------------ | ---------------: | ------------------: |
| Successful / failed requests    |     100 / 0      |      100 / 0        |
| Benchmark duration              |      515.98 s    |       518.20 s      |
| Output token throughput         |    99.23 tok/s   |     98.80 tok/s     |
| Total token throughput          |   299.70 tok/s   |    298.41 tok/s     |
| Mean / P99 TPOT (decode)        |  18.89 / 22.83 ms |   18.90 / 24.14 ms  |
| Mean / median TTFT              | 252703 / 250595 ms ⚠️ | **664.8 / 631.3 ms** |
| Mean / median E2EL              |  262356 ms ⚠️     |  **10321 / 10510 ms** |
| MTP acceptance rate / length    |  64.81 % / 2.94  |    64.36 % / 2.93   |

⚠️ The `request_rate=inf` TTFT/E2EL are **queuing artifacts** — all 100 prompts are
submitted at once against a 2-sequence server cap, so 98 requests sit in the queue.
Use the `--max-concurrency 2` column for real latency: **~665 ms mean TTFT**, ~10.3 s
end-to-end for a 1024-in / 512-out request. TPOT (~18.9 ms, ~53 tok/s/req steady
decode with 64 % MTP acceptance) is identical either way.

> **Not directly comparable to the old findings-doc entry** (585 total / 65 output
> tok/s, 3m16s): that run used a different server config (plain cudagraph, no
> 2-seq cap) and a different throughput definition, so this is **not** a regression.
> Throughput here is intentionally low because the server is capped at
> `--max-num-seqs 2`; raise `VLLM_MAX_NUM_SEQS` for higher aggregate throughput at
> the cost of per-request latency.

### Prefill tuning: closing the gap to community runs (June 17, 2026)

A community member reported ~2567 t/s pp2048@d4096 on the *same* `aml731/vllm-aiter:v0.20.2`
image, vs our ~1841. Investigation (see [vllm/rdna4-fp8-findings.md](../vllm/rdna4-fp8-findings.md))
ruled out every hardware and most software levers:

- **Hardware is optimal** — both cards PCIe 5.0 x8, trained to max, symmetric; 300 W; `auto`; no undervolt.
- **AITER linear/quant fast path is impossible on gfx1201** — `aiter.jit.module_quant` fails to
  compile (`__builtin_amdgcn_raw_ptr_buffer_load_lds needs target feature vmem-to-lds-load-insts`),
  so `VLLM_ROCM_USE_AITER_LINEAR=1` is correctly disabled for everyone on this image.
- **Native FP8 WMMA is already in the image** — `gfx1201` is already in `on_mi3xx()` and the FP8 path
  uses `w8a8_triton_block_scaled_mm`, not naive dequant-to-FP32. No 2× to recover there.
- **Tuned FP8 block configs aren't downloadable** — vLLM upstream ships zero R9700 configs; the image's
  R9700 configs are for DeepSeek shapes, not Qwen3.6-27B (5 shapes fall back to a default). Self-tuning
  them is a multi-hour CPU-bound Triton grind for a bounded gain.

A reproducible community run on [localmaxxing](https://www.localmaxxing.com) (2× R9700, self-patched
vLLM) lands at **1965 t/s prefill** — i.e. ~1841–1965 is the real ceiling for this hardware/model, and
the 2567 is an outlier (different depth/warmup or a private tuned-config pack). Adopting a few of that
run's launch flags closes most of the gap with **no patching or tuning**:

| config (pp2048 / tg32, d4096 / d8132)             | pp@d4096 | pp@d8132 | tg@d4096 | tg@d8132 |
| ------------------------------------------------- | -------: | -------: | -------: | -------: |
| baseline (pre-tuning)                             |  1840.9  |  1786.1  |   80.5   |   71.0   |
| **+`max-num-batched-tokens 8192` +`disable-custom-all-reduce`** (committed) | **1893.6** | **1839.4** | **81.6** | **72.2** |
| + `kv-cache-dtype fp8`                             |  1959.6  |  1928.5  |   80.8   |   65.1 ⚠️ |
| + `max-num-seqs 1` (single-stream)                |  1903.5  |  1849.7  |   81.1   | **80.7** |

- **Committed default:** `--max-num-batched-tokens 8192` + `--disable-custom-all-reduce` →
  **+~3 % prefill, decode unchanged**, no downside. Baked into
  `docker/docker-compose.aiter-0202.tp2-r9700.yml`.
- `--kv-cache-dtype fp8` adds another ~3 % prefill but costs ~20 % deep-context decode (71→65) — **not**
  worth it as a default.
- `--max-num-seqs 1` (single-stream serving) recovers/boosts deep-context decode (72→81) and adds a
  little prefill, at the cost of concurrency. Set `VLLM_MAX_NUM_SEQS=1` if you run one request at a time.


