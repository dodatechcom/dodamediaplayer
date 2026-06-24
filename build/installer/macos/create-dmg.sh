#!/usr/bin/env bash
set -euo pipefail

# Create DMG for Doda Media Player

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUTPUT="$ROOT/build/installer/macos/Output"
mkdir -p "$OUTPUT"

# Try .app bundle first, fall back to onedir
APP_BUNDLE="$ROOT/dist/DodaMediaPlayer.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "WARNING: $APP_BUNDLE not found. Wrapping onedir as .app..."
    ONEDIR="$ROOT/dist/doda-player"
    if [ -d "$ONEDIR" ]; then
        APP_BUNDLE="$OUTPUT/DodaMediaPlayer.app"
        rm -rf "$APP_BUNDLE"
        mkdir -p "$APP_BUNDLE/Contents/MacOS"
        mkdir -p "$APP_BUNDLE/Contents/Resources"
        cp -r "$ONEDIR"/* "$APP_BUNDLE/Contents/MacOS/"
        ln -sf "Contents/MacOS/doda-player" "$APP_BUNDLE/doda-player"
        cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>doda-player</string>
    <key>CFBundleIdentifier</key>
    <string>com.doda.mediaplayer</string>
    <key>CFBundleName</key>
    <string>DodaMediaPlayer</string>
    <key>CFBundleVersion</key>
    <string>0.1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.1</string>
</dict>
</plist>
PLIST
    else
        echo "ERROR: Neither $APP_BUNDLE nor $ONEDIR found. Run PyInstaller first."
        exit 1
    fi
fi

DMG_NAME="DodaMediaPlayer-0.1.1.dmg"
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
