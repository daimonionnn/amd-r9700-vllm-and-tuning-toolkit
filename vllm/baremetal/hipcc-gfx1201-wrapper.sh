#!/usr/bin/env bash
# hipcc wrapper for R9700 (gfx1201).
#
# Some build systems (notably AITER's JIT) invoke hipcc with
# --offload-arch=native, expecting hipcc to auto-detect the GPU.  On
# TheRock SDK + RDNA4 that path is unreliable: it can pick wrong arch or
# fail outright.  This wrapper rewrites any --offload-arch=native to
# --offload-arch=gfx1201 and forwards everything else to the real hipcc.
#
# Install: place at .../vllm-venv/bin/hipcc with the real shim moved
# aside to hipcc.therock (see install_vllm_rocm.sh).

set -e

# Resolve real hipcc next to us.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_HIPCC="${HIPCC_REAL:-$SELF_DIR/hipcc.therock}"

if [[ ! -x "$REAL_HIPCC" ]]; then
    echo "[hipcc-wrapper] real hipcc not found at $REAL_HIPCC" >&2
    exit 127
fi

args=()
for a in "$@"; do
    case "$a" in
        --offload-arch=native|--amdgpu-target=native|--cuda-gpu-arch=native)
            args+=("--offload-arch=gfx1201")
            ;;
        *)
            args+=("$a")
            ;;
    esac
done

exec "$REAL_HIPCC" "${args[@]}"
