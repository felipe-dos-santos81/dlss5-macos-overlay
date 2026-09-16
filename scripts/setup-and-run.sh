#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

ZIP_URL="https://github.com/perseval-BLR/NeuralScreen/releases/download/v1.8.2/neuralscreen-v1.8.2-full.zip"
ZIP_MEMBER="native/nvngx_dlssnr.dll"
EXPECTED_SHA256="dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f"
DLL="$PROJECT_ROOT/Models/nvngx_dlssnr.dll"

for tool in curl unzip shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

dll_sha() { shasum -a 256 "$1" | awk '{print $1}'; }

fresh_dll=false
if [ -f "$DLL" ] && [ "$(dll_sha "$DLL")" = "$EXPECTED_SHA256" ]; then
  echo "DLL already cached: $DLL"
else
  if [ -f "$DLL" ]; then
    echo "Cached DLL hash differs from the expected value; re-fetching." >&2
  fi
  echo "Downloading NeuralScreen v1.8.2 release (~225MB)..."
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TEMP_DIR"' EXIT
  curl -fL --retry 3 -o "$TEMP_DIR/neuralscreen.zip" "$ZIP_URL"
  unzip -q "$TEMP_DIR/neuralscreen.zip" "$ZIP_MEMBER" -d "$TEMP_DIR"
  OBSERVED="$(dll_sha "$TEMP_DIR/$ZIP_MEMBER")"
  if [ "$OBSERVED" != "$EXPECTED_SHA256" ]; then
    echo "SHA-256 mismatch for nvngx_dlssnr.dll:" >&2
    echo "  expected: $EXPECTED_SHA256" >&2
    echo "  observed: $OBSERVED" >&2
    echo "See docs/VALIDATION.md." >&2
    exit 1
  fi
  mkdir -p "$PROJECT_ROOT/Models"
  mv "$TEMP_DIR/$ZIP_MEMBER" "$DLL"
  fresh_dll=true
  echo "DLL fetched and verified: $DLL"
fi

MODEL_DIR="$PROJECT_ROOT/Models/NR.dlss"
if [ "$fresh_dll" = true ] || [ ! -f "$MODEL_DIR/manifest.json" ] || [ ! -f "$MODEL_DIR/weights.safetensors" ]; then
  "$PROJECT_ROOT/scripts/prepare-model.sh" "$DLL"
else
  echo "Model already prepared: $MODEL_DIR"
fi

"$PROJECT_ROOT/scripts/build-app.sh"
"$PROJECT_ROOT/Launch.command"
