#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
MODEL="$PROJECT_ROOT/Models/NR.dlss"
if [ ! -f "$MODEL/manifest.json" ] || [ ! -f "$MODEL/weights.safetensors" ]; then
  echo 'Models/NR.dlss is required. Run scripts/prepare-model.sh before building.' >&2
  exit 1
fi
JOBS="${DLSS_BUILD_JOBS:-6}"
swift build -c release --jobs "$JOBS"
BIN_PATH="$(swift build -c release --show-bin-path)"
METAL_SOURCE="$PROJECT_ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx"
METAL_BUILD="$PROJECT_ROOT/.build/mlx-metallib"
cmake -S "$METAL_SOURCE" -B "$METAL_BUILD" -G Ninja \
  -DMLX_BUILD_TESTS=OFF -DMLX_BUILD_EXAMPLES=OFF -DMLX_BUILD_BENCHMARKS=OFF \
  -DMLX_BUILD_PYTHON_BINDINGS=OFF -DMLX_BUILD_GGUF=OFF -DMLX_BUILD_SAFETENSORS=OFF \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0
cmake --build "$METAL_BUILD" --target mlx-metallib --parallel "$JOBS"
cp "$METAL_BUILD/mlx/backend/metal/kernels/mlx.metallib" "$BIN_PATH/mlx.metallib"
APP="$PROJECT_ROOT/dist/DLSS_5_APPLE_SILICON.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/DLSS_5_APPLE_SILICON" "$APP/Contents/MacOS/"
cp "$BIN_PATH/mlx.metallib" "$APP/Contents/MacOS/"
RESOURCE="$BIN_PATH/DLSS_5_APPLE_SILICON_NeuralScreenMac.bundle"
ditto "$RESOURCE" "$APP/Contents/Resources/$(basename "$RESOURCE")"
ditto "$MODEL" "$APP/Contents/Resources/NR.dlss"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$PROJECT_ROOT/LICENSE" "$APP/Contents/Resources/Licenses/NeuralScreenMac.txt"
cp "$PROJECT_ROOT/Resources/NeuralScreen-LICENSE.txt" "$APP/Contents/Resources/Licenses/Original-NeuralScreen.txt"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/Licenses/NOTICES.md"
cp "$PROJECT_ROOT/Vendor/MLX-DLSS/LICENSE" "$APP/Contents/Resources/Licenses/MLX-DLSS.txt"
cp "$PROJECT_ROOT/Vendor/MLX-DLSS/NOTICE" "$APP/Contents/Resources/Licenses/MLX-DLSS-NOTICE.txt"
for dependency in mlx-swift swift-numerics swift-argument-parser; do
  if [ -f "$PROJECT_ROOT/.build/checkouts/$dependency/LICENSE" ]; then
    cp -f "$PROJECT_ROOT/.build/checkouts/$dependency/LICENSE" "$APP/Contents/Resources/Licenses/$dependency.txt"
  elif [ -f "$PROJECT_ROOT/.build/checkouts/$dependency/LICENSE.txt" ]; then
    cp -f "$PROJECT_ROOT/.build/checkouts/$dependency/LICENSE.txt" "$APP/Contents/Resources/Licenses/$dependency.txt"
  fi
done
plutil -lint "$APP/Contents/Info.plist"
"$PROJECT_ROOT/scripts/sign-app.sh" "$APP"
echo "$APP"
