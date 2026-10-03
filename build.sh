#!/bin/bash
# Builds Snippy and wraps the executable into Snippy.app for local development.
# Signs with your Developer ID when one is available so the Accessibility grant
# survives rebuilds (macOS ties the grant to the signing identity; an ad-hoc
# signature changes with every build and silently drops it). Not notarized —
# for a public release build, run ./release.sh instead.
set -euo pipefail

cd "$(dirname "$0")"

# Load local credentials if present. .env.local is gitignored.
if [ -f .env.local ]; then
    set -a
    # shellcheck disable=SC1091
    . .env.local
    set +a
fi

# Prefer the release identity; otherwise use the first Developer ID in the
# keychain; otherwise fall back to ad-hoc.
SIGN_IDENTITY="${SNIPPY_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' | head -1)
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

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

# Sign with hardened runtime + entitlements so the dev build behaves the same
# way as the release build (catches hardened-runtime issues early).
codesign --force --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null

echo "✓ Built $APP_DIR"

# If Snippy is already installed in /Applications, replace it so the user keeps
# launching the canonical copy (stable path for Accessibility permissions).
INSTALLED="/Applications/${APP_NAME}.app"
if [ -d "$INSTALLED" ] || [ "${2:-}" = "install" ]; then
    echo "→ Deploying to ${INSTALLED}…"
    pkill -f "${INSTALLED}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    rm -rf "$INSTALLED"
    cp -R "$APP_DIR" "$INSTALLED"
    # Remove the staging copy so Spotlight/Launchpad don't show two Snippy.apps.
    rm -rf "$APP_DIR"
    echo "✓ Installed to $INSTALLED"
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "  ! Ad-hoc signed: macOS will have dropped Snippy's Accessibility grant."
        echo "    Remove and re-add Snippy in System Settings → Privacy & Security → Accessibility."
    fi
    echo "  Run with:  open $INSTALLED"
else
    echo
    echo "Run with:   open $APP_DIR"
    echo "Install to /Applications:   ./build.sh release install"
fi
