#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
swift test -c release --jobs "${DLSS_BUILD_JOBS:-6}" --filter ScreenCoreTests
BIN_PATH="$(swift build -c release --show-bin-path)"
"$BIN_PATH/DLSS_5_APPLE_SILICON" --self-test "$@"
