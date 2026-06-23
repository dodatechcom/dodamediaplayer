#!/usr/bin/env bash
set -euo pipefail

# Build AppImage for Doda Media Player
# Requires: appimagetool (downloaded automatically)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST="$ROOT/dist/doda-player"
OUTPUT="$ROOT/build/installer/linux/Output"
mkdir -p "$OUTPUT"

APPDIR="$OUTPUT/DodaMediaPlayer.AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy PyInstaller onedir output
if [ -d "$DIST" ]; then
    cp -r "$DIST"/* "$APPDIR/usr/bin/"
else
    echo "ERROR: $DIST not found. Run PyInstaller first."
    exit 1
fi

# AppRun script
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/usr/bin/env bash
APPDIR="$(dirname "$(readlink -f "$0")")"
export PATH="$APPDIR/usr/bin:$PATH"
exec "$APPDIR/usr/bin/doda-player" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

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

# Icon
ICON_SRC="$ROOT/build/installer/linux/doda-player.png"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/doda-player.png"
    cp "$ICON_SRC" "$APPDIR/doda-player.png"
fi

# Download appimagetool
APPIMAGETOOL="/tmp/appimagetool-x86_64.AppImage"
if [ ! -f "$APPIMAGETOOL" ]; then
    wget -q -O "$APPIMAGETOOL" \
        "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGETOOL"
fi

# Extract if FUSE unavailable
if ! "$APPIMAGETOOL" --help >/dev/null 2>&1; then
    cd /tmp
    "$APPIMAGETOOL" --appimage-extract >/dev/null 2>&1 || true
    APPIMAGETOOL="/tmp/squashfs-root/AppRun"
fi

cd "$OUTPUT"
$APPIMAGETOOL "$APPDIR" "DodaMediaPlayer-0.1.0-x86_64.AppImage"
echo "AppImage built: $OUTPUT/DodaMediaPlayer-0.1.0-x86_64.AppImage"
