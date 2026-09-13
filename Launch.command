#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$PROJECT_ROOT/dist/DLSS_5_APPLE_SILICON.app"
if [ ! -d "$APP" ]; then "$PROJECT_ROOT/scripts/build-app.sh"; fi
open "$APP"
