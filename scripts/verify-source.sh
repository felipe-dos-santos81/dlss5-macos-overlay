#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
python3 scripts/check-public-tree.py
for script in scripts/*.sh Launch.command; do bash -n "$script"; done
plutil -lint Resources/Info.plist
swift build -c release --jobs "${DLSS_BUILD_JOBS:-2}" --disable-automatic-resolution
swift test -c release --jobs "${DLSS_BUILD_JOBS:-2}" --disable-automatic-resolution --filter ScreenCoreTests
