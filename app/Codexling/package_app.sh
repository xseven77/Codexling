#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codexling"
BINARY_NAME="Codexling"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
DMG_VOLUME_NAME="${APP_NAME} ${VERSION}"
DMG_STAGING_DIR="${DIST_DIR}/dmg-staging"

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

rm -rf "${DIST_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp ".build/release/${BINARY_NAME}" "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${BINARY_NAME}"

codesign --force --deep --sign - "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

rm -rf "${DMG_STAGING_DIR}"
mkdir -p "${DMG_STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

hdiutil create \
  -volname "${DMG_VOLUME_NAME}" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

rm -rf "${DMG_STAGING_DIR}"

echo "Built ${APP_BUNDLE}"
echo "Version ${VERSION} (${BUILD_NUMBER})"
echo "Archive ${ZIP_PATH}"
echo "Disk image ${DMG_PATH}"
