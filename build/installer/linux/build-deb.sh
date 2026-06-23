#!/usr/bin/env bash
set -euo pipefail

# Build a .deb package from the PyInstaller onedir output
# Usage: bash build/installer/linux/build-deb.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DIST="$ROOT/dist/doda-player"
OUTPUT="$ROOT/build/installer/linux/Output"
mkdir -p "$OUTPUT"

VERSION="0.1.0"
PACKAGE="doda-media-player"
ARCH="amd64"
DEB_DIR="$OUTPUT/${PACKAGE}_${VERSION}_${ARCH}"

if [ ! -d "$DIST" ]; then
    echo "ERROR: $DIST not found. Run PyInstaller first."
    exit 1
fi

rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/lib/$PACKAGE"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_DIR/usr/share/doc/$PACKAGE"

# Control file
cat > "$DEB_DIR/DEBIAN/control" <<CONTROL
Package: $PACKAGE
Version: $VERSION
Section: sound
Priority: optional
Architecture: $ARCH
Maintainer: DodaTech <dodatechcom@users.noreply.github.com>
Description: Doda Media Player
 A cross-platform open source media player with PyQt6 QML interface,
 YouTube streaming, audio visualizer, equalizer, and playlist management.
Homepage: https://github.com/dodatechcom/dodamediaplayer
CONTROL

# Copyright file
cat > "$DEB_DIR/usr/share/doc/$PACKAGE/copyright" <<COPYRIGHT
License: GPL-2.0+
Copyright: 2026 DodaTech
COPYRIGHT

# Copy application files
cp -r "$DIST"/* "$DEB_DIR/usr/lib/$PACKAGE/"

# Wrapper script
cat > "$DEB_DIR/usr/bin/doda-player" <<WRAPPER
#!/usr/bin/env bash
exec /usr/lib/$PACKAGE/doda-player "\$@"
WRAPPER
chmod +x "$DEB_DIR/usr/bin/doda-player"

# Desktop file
cat > "$DEB_DIR/usr/share/applications/doda-player.desktop" <<DESKTOP
[Desktop Entry]
Name=Doda Media Player
Comment=Cross-platform media player
Exec=doda-player
Icon=doda-player
Terminal=false
Type=Application
Categories=AudioVideo;Player;
MimeType=audio/mpeg;video/mp4;video/x-matroska;
DESKTOP

# Icon
ICON_SRC="$ROOT/build/installer/linux/doda-player.png"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$DEB_DIR/usr/share/icons/hicolor/256x256/apps/doda-player.png"
fi

# Build .deb
dpkg-deb --build "$DEB_DIR" "$OUTPUT/${PACKAGE}_${VERSION}_${ARCH}.deb"
echo "Debian package built: $OUTPUT/${PACKAGE}_${VERSION}_${ARCH}.deb"
