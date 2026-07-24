#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${ROOT_DIR}/dist/Codexling.app"

cd "${ROOT_DIR}"
./package_app.sh

pkill -x Codexling 2>/dev/null || true
sleep 0.5
open "${APP_PATH}"
