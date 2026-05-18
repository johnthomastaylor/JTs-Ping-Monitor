#!/bin/bash
# Build PingMonitor and bundle the executable into a proper macOS .app
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PingMonitor"
DISPLAY_NAME="JT's Ping Monitor"
CONFIG="${CONFIG:-release}"
OUT_DIR="build"
APP_BUNDLE="${OUT_DIR}/${DISPLAY_NAME}.app"

echo "==> swift build (${CONFIG})"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Build did not produce ${BIN_PATH}" >&2
    exit 1
fi

echo "==> assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

if [[ ! -f "Resources/AppIcon.icns" ]]; then
    echo "==> generating AppIcon.icns"
    swift scripts/generate-icon.swift >/dev/null
fi
cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so login-item registration and TCC behave predictably.
codesign --force --sign - --timestamp=none "${APP_BUNDLE}" >/dev/null

# Nudge macOS to re-read the bundle's icon.
touch "${APP_BUNDLE}"

echo "Built ${APP_BUNDLE}"
