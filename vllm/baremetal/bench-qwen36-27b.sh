#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# bench-qwen36-27b.sh — reproduce Qwen3.6-27B-FP8 on R9700 TP=2.
#
# Qwen3.6 uses hybrid GDN (linear) attention.  vLLM forces
# attention block_size=784 to match the mamba page size, which is
# NOT a power of 2 and therefore breaks AITER's unified_attention
# (`tl.arange(0, TILE_SIZE)` requires pow2).  Symptom with the
# default AITER backend + cudagraph: silent hang, GPUs idle 10–15W.
# With `--enforce-eager` the real error surfaces:
#   ValueError: arange's range must be a power of 2
#
# Workaround: use vLLM's own TRITON_ATTN backend (handles non-pow2)
# via VLLM_BACKEND=triton.  Eager mode is required for now — TRITON
# backend + cudagraph capture not yet validated on this stack.
#
# Verified May 29 2026: 204 tok/s total, 22.7 output tok/s
# (4 prompts × 256 in / 32 out, KV 10.4 GiB/GPU, 9.67x concurrency).
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

MODEL="${MODEL:-RedHatAI/Qwen3.6-27B-FP8}"
NUM_PROMPTS="${NUM_PROMPTS:-4}"
INPUT_LEN="${INPUT_LEN:-256}"
OUTPUT_LEN="${OUTPUT_LEN:-32}"
# Forward MAX_MODEL_LEN to bench-vllm.sh (which reads VLLM_MAX_MODEL_LEN).
if [[ -n "${MAX_MODEL_LEN:-}" ]]; then
    export VLLM_MAX_MODEL_LEN="$MAX_MODEL_LEN"
fi

export VLLM_BACKEND="${VLLM_BACKEND:-triton}"

# EAGER=1 (default) → --enforce-eager, the only mode we've gotten to actually
# produce tokens on this stack (ROCm 7.13 nightly, Triton 3.6, vLLM HEAD).
# EAGER=0 attempts cudagraph capture — currently hangs silently on Qwen3.6-FP8
# with BOTH AITER and TRITON_ATTN backends: workers idle 3%, EngineCore prints
# `shm_broadcast` keepalives forever, no cudagraph-capture progress.  Stays
# stuck after a non-fatal `TypeError: Object of type function is not JSON
# serializable` from torch/_dynamo metrics_context.  kyuz0's toolbox runs the
# cudagraph path successfully at 801 tok/s on ROCm 7.2.5 + Fedora 43, so the
# breakage is most likely stack-version specific (torch.compile + GDN op
# vllm::qwen_gdn_attention_core).  Retry without EAGER=1 after stack updates.
EAGER="${EAGER:-1}"
EXTRA=()
if [[ "$EAGER" == "1" ]]; then
    EXTRA+=(-- --enforce-eager)
fi

exec "$SCRIPT_DIR/bench-vllm.sh" \
    --model "$MODEL" \
    --num-prompts "$NUM_PROMPTS" \
    --input-len "$INPUT_LEN" \
    --output-len "$OUTPUT_LEN" \
    "${EXTRA[@]}" "$@"
