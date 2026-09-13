#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo 'Usage: scripts/prepare-model.sh /path/to/nvngx_dlssnr.dll' >&2
  exit 64
fi
DLL="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$PROJECT_ROOT"
python3 -m venv .venv
.venv/bin/python -m pip install 'numpy>=2,<3' 'safetensors>=0.4,<1'
mkdir -p Models
TOOLS="$PROJECT_ROOT/Vendor/MLX-DLSS/python/mlxdlss/tools"
# These standalone tools use NumPy only. Do not import the Python MLX-DLSS
# package, whose __init__ would pull in the unrelated PyTorch backend.
.venv/bin/python "$TOOLS/extract_dlssnr_weights.py" "$DLL" Models/dlssnr-weights-packed.safetensors
.venv/bin/python "$TOOLS/unpack_dlssnr_weights.py" Models/dlssnr-weights-packed.safetensors Models/dlssnr-weights-logical.safetensors
.venv/bin/python "$TOOLS/package_neural_rendering_transformer.py" Models/dlssnr-weights-logical.safetensors Models/NR.dlss
echo "Model ready: $PROJECT_ROOT/Models/NR.dlss"
