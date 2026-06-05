#!/bin/bash
# Builds Snippy and wraps the executable into Snippy.app for local development.
# Uses ad-hoc signing — fine for running on your own Mac, but downloads of this
# build will hit Gatekeeper on other Macs. For a public release build, run
# ./release.sh instead.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Snippy"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ENTITLEMENTS="Resources/Snippy.entitlements"

echo "→ Building Snippy ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}
if [ ! -f "$BIN_PATH" ]; then
    echo "Build did not produce $BIN_PATH"
    exit 1
fi

echo "→ Wrapping into ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH" "$MACOS/$APP_NAME"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"

# Ad-hoc sign with hardened runtime + entitlements so the dev build behaves the
# same way as the release build (catches hardened-runtime issues early).
codesign --force --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign - "$APP_DIR" >/dev/null

echo "✓ Built $APP_DIR"

# If Snippy is already installed in /Applications, replace it so the user keeps
# launching the canonical copy (stable path for Accessibility permissions).
INSTALLED="/Applications/${APP_NAME}.app"
if [ -d "$INSTALLED" ] || [ "${2:-}" = "install" ]; then
    echo "→ Deploying to ${INSTALLED}…"
    pkill -f "${INSTALLED}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    rm -rf "$INSTALLED"
    cp -R "$APP_DIR" "$INSTALLED"
    codesign --force --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign - "$INSTALLED" >/dev/null
    # Remove the staging copy so Spotlight/Launchpad don't show two Snippy.apps.
    rm -rf "$APP_DIR"
    echo "✓ Installed to $INSTALLED"
    echo "  Run with:  open $INSTALLED"
else
    echo
    echo "Run with:   open $APP_DIR"
    echo "Install to /Applications:   ./build.sh release install"
fi
