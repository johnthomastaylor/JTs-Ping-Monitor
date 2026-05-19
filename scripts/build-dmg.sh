#!/bin/bash
# Build the app and bundle it into a drag-to-install DMG that can be attached
# to a GitHub Release. The DMG contains the .app and an /Applications symlink
# so non-technical users can drag-install.
#
# Set DEVELOPER_ID and NOTARY_PROFILE to produce a signed + notarized + stapled
# DMG suitable for distribution (Gatekeeper accepts it silently). Example:
#
#   DEVELOPER_ID="Developer ID Application: Your Name (ABCDE12345)" \
#   NOTARY_PROFILE="ping-monitor" \
#   ./scripts/build-dmg.sh
#
# Without those env vars the DMG is unsigned and users will hit Gatekeeper.
set -euo pipefail

cd "$(dirname "$0")/.."

DISPLAY_NAME="JT's Ping Monitor"
VOLUME_NAME="JT's Ping Monitor"
APP_BUNDLE="build/${DISPLAY_NAME}.app"
DMG_PATH="build/JTs-Ping-Monitor.dmg"
STAGING="build/dmg-staging"

./scripts/build-app.sh

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Expected ${APP_BUNDLE} to exist after build-app.sh; aborting." >&2
    exit 1
fi

echo "==> staging DMG contents"
rm -rf "${STAGING}" "${DMG_PATH}"
mkdir -p "${STAGING}"
cp -R "${APP_BUNDLE}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

echo "==> creating ${DMG_PATH}"
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${STAGING}"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    echo "==> codesigning DMG with ${DEVELOPER_ID}"
    codesign --force --sign "${DEVELOPER_ID}" --timestamp "${DMG_PATH}" >/dev/null
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    if [[ -z "${DEVELOPER_ID:-}" ]]; then
        echo "NOTARY_PROFILE is set but DEVELOPER_ID is not; cannot notarize an unsigned DMG." >&2
        exit 1
    fi
    echo "==> submitting to Apple notary service (this can take 1-5 minutes)"
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    echo "==> stapling notarization ticket onto DMG"
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
fi

echo "Built ${DMG_PATH}"
