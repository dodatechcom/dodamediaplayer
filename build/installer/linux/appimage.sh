#!/usr/bin/env bash
set -euo pipefail

# Build AppImage for Doda Media Player
# Requires: linuxdeploy (downloaded automatically)

ROOT="$(dirname "$(readlink -f "$0")")/../.."
OUTPUT="$ROOT/build/installer/linux/Output"
mkdir -p "$OUTPUT"

# Get linuxdeploy
if [ ! -f /tmp/linuxdeploy-x86_64.AppImage ]; then
    wget -q -O /tmp/linuxdeploy-x86_64.AppImage \
        "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
    chmod +x /tmp/linuxdeploy-x86_64.AppImage
fi

# linuxdeploy may not run in Docker without FUSE
# Use --appimage-extract in that case
export LDAI_EXEC="/tmp/linuxdeploy-x86_64.AppImage"
if ! "$LDAI_EXEC" --appimage-extract >/dev/null 2>&1; then
    # Extract manually
    cd /tmp
    "$LDAI_EXEC" --appimage-extract >/dev/null 2>&1 || true
    LDAI_EXEC="/tmp/squashfs-root/AppRun"
fi

# Create AppDir structure
APPDIR="$OUTPUT/DodaMediaPlayer.AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy PyInstaller build
cp -r "$ROOT/dist/doda-player"/* "$APPDIR/usr/bin/"
ln -sf "../usr/bin/doda-player" "$APPDIR/AppRun"

# Desktop file
cat > "$APPDIR/usr/share/applications/doda-player.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Doda Media Player
Comment=Cross-platform media player
Exec=doda-player
Icon=doda-player
Terminal=false
Type=Application
Categories=AudioVideo;Player;
DESKTOP
cp "$APPDIR/usr/share/applications/doda-player.desktop" "$APPDIR/"

# Icon (use generated PNG)
if [ -f "$ROOT/build/installer/linux/doda-player.png" ]; then
    cp "$ROOT/build/installer/linux/doda-player.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/doda-player.png"
    cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/doda-player.png" "$APPDIR/doda-player.png"
fi

# Run linuxdeploy
cd "$OUTPUT"
$LDAI_EXEC --appdir "$APPDIR" --output appimage \
    --desktop-file "$APPDIR/usr/share/applications/doda-player.desktop" \
    --icon-file "$APPDIR/doda-player.png" 2>&1 || {
    # Fallback: manual AppImage creation
    echo "linuxdeploy failed, creating manual AppImage..."
    if command -v appimagetool &>/dev/null; then
        appimagetool "$APPDIR"
    else
        wget -q -O /tmp/appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x /tmp/appimagetool
        /tmp/appimagetool "$APPDIR"
    fi
}

# Move result
mv DodaMediaPlayer-*.AppImage "$OUTPUT/" 2>/dev/null || true
echo "AppImage built in $OUTPUT"
