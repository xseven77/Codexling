#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codex Light"
BINARY_NAME="CodexLight"
APP_BUNDLE="dist/${APP_NAME}.app"

if ! swift build -c release; then
  if [[ -x ".build/release/${BINARY_NAME}" ]]; then
    newest_source="$(find Sources Resources Package.swift -type f -print0 | xargs -0 stat -f '%m %N' | sort -nr | head -1 | cut -d' ' -f1)"
    binary_mtime="$(stat -f '%m' ".build/release/${BINARY_NAME}")"

    if [[ "${binary_mtime}" -lt "${newest_source}" ]]; then
      echo "swift build failed and the existing release binary is older than the source files." >&2
      echo "Run 'sudo xcodebuild -license' in Terminal, then retry ./package_app.sh." >&2
      exit 1
    fi

    echo "swift build failed; packaging existing up-to-date .build/release/${BINARY_NAME}" >&2
  else
    echo "swift build failed and no release binary exists." >&2
    echo "Run 'sudo xcodebuild -license' in Terminal, then retry ./package_app.sh." >&2
    exit 1
  fi
fi

rm -rf dist
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${BINARY_NAME}" "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"

codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

ditto -c -k --keepParent "${APP_BUNDLE}" "dist/${APP_NAME}.app.zip"

echo "Built ${APP_BUNDLE}"
echo "Archive dist/${APP_NAME}.app.zip"
