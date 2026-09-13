#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_ROOT/dist/DLSS_5_APPLE_SILICON.app}"
if [ ! -f "$APP/Contents/Info.plist" ] || [ ! -f "$APP/Contents/MacOS/mlx.metallib" ]; then
  echo 'A complete application bundle is required for signing.' >&2
  exit 1
fi

# Keep the signing identity stable so macOS can recognize permission grants
# after a rebuild. Never store a developer identity or certificate in Git.
IDENTITY="${DLSS_CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITIES=()
  while IFS= read -r candidate; do
    [ -z "$candidate" ] || IDENTITIES+=("$candidate")
  done < <(security find-identity -v -p codesigning 2>/dev/null | \
    sed -nE '/"(Apple Development|Mac Developer):/s/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) .*/\1/p' || true)
  if [ "${#IDENTITIES[@]}" -eq 1 ]; then
    IDENTITY="${IDENTITIES[0]}"
    echo 'Signing with the installed development certificate.'
  else
    IDENTITY='-'
  fi
fi
if [ "$IDENTITY" = '-' ]; then
  echo 'Using ad-hoc signing. Screen Recording permission may need renewal after rebuilds.' >&2
  echo 'Set DLSS_CODESIGN_IDENTITY to an installed signing identity for stable local builds.' >&2
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/MacOS/mlx.metallib"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
