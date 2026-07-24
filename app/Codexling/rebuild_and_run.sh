#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${ROOT_DIR}/dist/Codexling.app"

cd "${ROOT_DIR}"
./package_app.sh

pkill -x Codexling 2>/dev/null || true
sleep 0.5
open "${APP_PATH}"
sleep 0.6
if pgrep -x Codexling >/dev/null; then
  echo "已重启 Codexling（dist/Codexling.app，PID $(pgrep -x Codexling | head -1)）"
  echo "请在菜单栏查看 Codexling 图标；独立窗口需从菜单打开。"
else
  echo "启动失败：未检测到 Codexling 进程" >&2
  exit 1
fi
