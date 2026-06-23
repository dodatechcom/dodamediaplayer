#!/usr/bin/env bash
set -euo pipefail

# Create DMG for Doda Media Player
# Requires: create-dmg (optional, falls back to hdiutil)

ROOT="$(dirname "$(readlink -f "$0")")/../.."
OUTPUT="$ROOT/build/installer/macos/Output"
mkdir -p "$OUTPUT"
APP_BUNDLE="$ROOT/dist/DodaMediaPlayer.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: $APP_BUNDLE not found. Run PyInstaller first."
    exit 1
fi

DMG_NAME="DodaMediaPlayer-0.1.0.dmg"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "Doda Media Player" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "DodaMediaPlayer.app" 150 190 \
        --hide-extension "DodaMediaPlayer.app" \
        --app-drop-link 450 190 \
        "$OUTPUT/$DMG_NAME" \
        "$APP_BUNDLE"
else
    # Fallback: hdiutil
    STAGING="$OUTPUT/staging"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -R "$APP_BUNDLE" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "Doda Media Player" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$OUTPUT/$DMG_NAME"
    rm -rf "$STAGING"
fi

echo "DMG built: $OUTPUT/$DMG_NAME"
