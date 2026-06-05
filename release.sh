#!/bin/bash
# Produces a notarized, stapled Snippy.app and a DMG ready for public download.
#
# Required env vars (load via .env.local — see .env.local.example):
#   SNIPPY_SIGN_IDENTITY   — Developer ID Application identity string or hash
#                            e.g. "Developer ID Application: Your Name (TEAMID)"
#                            Find with:  security find-identity -v -p codesigning
#   SNIPPY_NOTARY_PROFILE  — Name of a keychain profile created via
#                            `xcrun notarytool store-credentials`
#                            (stores App Store Connect API key + team id)
#
# Optional:
#   SNIPPY_SKIP_NOTARIZE=1 — Sign but don't notarize (faster iteration on
#                            the signing config).
set -euo pipefail

cd "$(dirname "$0")"

# Load local credentials if present. .env.local is gitignored.
if [ -f .env.local ]; then
    set -a
    # shellcheck disable=SC1091
    . .env.local
    set +a
fi

if [ -z "${SNIPPY_SIGN_IDENTITY:-}" ]; then
    cat <<EOF >&2
SNIPPY_SIGN_IDENTITY is not set.

Create .env.local in the repo root with at minimum:

  SNIPPY_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
  SNIPPY_NOTARY_PROFILE="snippy-notary"

Then create the notary keychain profile once:

  xcrun notarytool store-credentials snippy-notary \\
    --apple-id "you@example.com" \\
    --team-id "TEAMID" \\
    --key /path/to/AuthKey_XXXXXX.p8 \\
    --key-id "XXXXXX" \\
    --issuer "your-issuer-uuid"

(See the README for setup instructions.)
EOF
    exit 1
fi

APP_NAME="Snippy"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
RELEASE_DIR="release"
APP_DIR="${RELEASE_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ENTITLEMENTS="Resources/Snippy.entitlements"
DMG_PATH="${RELEASE_DIR}/${APP_NAME}-${VERSION}.dmg"
ZIP_PATH="${RELEASE_DIR}/${APP_NAME}-${VERSION}.zip"

echo "→ Releasing Snippy v${VERSION}"

# Clean previous release outputs.
rm -rf "$RELEASE_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "→ Building release binary…"
swift build -c release
BIN_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}

echo "→ Assembling app bundle…"
cp "$BIN_PATH" "$MACOS/$APP_NAME"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"

echo "→ Signing with ${SNIPPY_SIGN_IDENTITY}…"
codesign --force --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    --sign "$SNIPPY_SIGN_IDENTITY" \
    "$APP_DIR"

echo "→ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose "$APP_DIR" || \
    echo "  (spctl assessment will fail until notarization is stapled — proceeding)"

if [ "${SNIPPY_SKIP_NOTARIZE:-0}" != "1" ]; then
    if [ -z "${SNIPPY_NOTARY_PROFILE:-}" ]; then
        echo "SNIPPY_NOTARY_PROFILE is required for notarization. Set SNIPPY_SKIP_NOTARIZE=1 to skip." >&2
        exit 1
    fi

    echo "→ Zipping app for notarization…"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

    echo "→ Submitting to Apple notary service (this can take 1-15 minutes)…"
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$SNIPPY_NOTARY_PROFILE" \
        --wait

    echo "→ Stapling notarization ticket to .app…"
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"

    # Re-verify with Gatekeeper now that the ticket is attached.
    spctl --assess --type execute --verbose "$APP_DIR"

    rm -f "$ZIP_PATH"
else
    echo "→ Skipping notarization (SNIPPY_SKIP_NOTARIZE=1)"
fi

echo "→ Building DMG…"
TMP_DMG_DIR=$(mktemp -d)
cp -R "$APP_DIR" "$TMP_DMG_DIR/"
ln -s /Applications "$TMP_DMG_DIR/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TMP_DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null
rm -rf "$TMP_DMG_DIR"

if [ "${SNIPPY_SKIP_NOTARIZE:-0}" != "1" ]; then
    echo "→ Notarizing DMG…"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$SNIPPY_NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

echo
echo "✓ Release ready:"
echo "  App: $APP_DIR"
echo "  DMG: $DMG_PATH"
echo
echo "Upload the DMG to a GitHub Release with:"
echo "  gh release create v${VERSION} \"$DMG_PATH\" --title \"Snippy v${VERSION}\" --notes-file CHANGELOG.md"
