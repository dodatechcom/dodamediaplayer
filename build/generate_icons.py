#!/usr/bin/env python3
"""Generate application icons (PNG, ICO) for Doda Media Player."""

import os, sys, struct
from PyQt6.QtGui import QImage, QPainter, QColor, QBrush, QPen, QRadialGradient, QPainterPath
from PyQt6.QtCore import Qt, QRectF, QPointF, QBuffer, QIODevice
from PyQt6.QtWidgets import QApplication

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIRS = {
    "win": os.path.join(ROOT, "build", "installer", "windows"),
    "mac": os.path.join(ROOT, "build", "installer", "macos"),
    "linux": os.path.join(ROOT, "build", "installer", "linux"),
}

ICON_SIZES = [16, 24, 32, 48, 64, 96, 128, 256]

MAC_ICONSET_SIZES = [16, 32, 64, 128, 256, 512]

def render_icon(size):
    img = QImage(size, size, QImage.Format.Format_ARGB32_Premultiplied)
    img.fill(Qt.GlobalColor.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)

    r = size * 0.18
    bg = QRectF(0, 0, size, size)
    grad = QRadialGradient(size * 0.3, size * 0.3, size * 0.7)
    grad.setColorAt(0, QColor("#2d2d5e"))
    grad.setColorAt(1, QColor("#0f3460"))
    p.setBrush(QBrush(grad))
    p.setPen(Qt.PenStyle.NoPen)
    p.drawRoundedRect(bg, r, r)

    # Play triangle using QPainterPath
    margin = size * 0.22
    cx, cy = size * 0.52, size * 0.5
    hw = (size - 2 * margin) * 0.5
    path = QPainterPath()
    path.moveTo(QPointF(cx - hw * 0.65, cy - hw * 0.7))
    path.lineTo(QPointF(cx - hw * 0.65, cy + hw * 0.7))
    path.lineTo(QPointF(cx + hw * 0.65, cy))
    path.closeSubpath()
    p.setBrush(QColor("#ffffff"))
    p.setPen(Qt.PenStyle.NoPen)
    p.drawPath(path)

    # Subtle inner glow border
    p.setBrush(Qt.BrushStyle.NoBrush)
    glow = QPen(QColor(255, 255, 255, 25), size * 0.035)
    p.setPen(glow)
    p.drawRoundedRect(QRectF(size*0.02, size*0.02, size*0.96, size*0.96), r*0.8, r*0.8)

    p.end()
    return img


def create_ico(pngs, path):
    with open(path, "wb") as f:
        f.write(struct.pack("<HHH", 0, 1, len(pngs)))
        offset = 6 + 16 * len(pngs)
        entries = []
        for size, img in pngs:
            buf = QBuffer()
            buf.open(QIODevice.OpenModeFlag.WriteOnly)
            img.save(buf, "PNG")
            entries.append((size, bytes(buf.data())))
        for size, data in entries:
            bpp = 32
            f.write(struct.pack("<BBBBHHII",
                size if size < 256 else 0,
                size if size < 256 else 0,
                0, 0, 1, bpp, len(data), offset))
            offset += len(data)
        for _, data in entries:
            f.write(data)


def create_iconset(pngs, path):
    os.makedirs(path, exist_ok=True)
    for size, img in pngs.items():
        name = f"icon_{size}x{size}.png"
        img.save(os.path.join(path, name))
    for size, img in pngs.items():
        if size * 2 <= 512:
            name2x = f"icon_{size}x{size}@2x.png"
            img2 = img.scaled(size * 2, size * 2,
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation)
            img2.save(os.path.join(path, name2x))


def main():
    _ = QApplication(sys.argv)

    all_sizes = sorted(set(ICON_SIZES + MAC_ICONSET_SIZES))
    size_map = {}
    for s in all_sizes:
        size_map[s] = render_icon(s)
        print(f"  Rendered {s}x{s}")

    # Windows .ico
    ico_path = os.path.join(OUT_DIRS["win"], "icon.ico")
    create_ico([(s, size_map[s]) for s in ICON_SIZES], ico_path)
    print(f"  Created: {ico_path}")

    # macOS .iconset
    iconset_path = os.path.join(OUT_DIRS["mac"], "DodaMediaPlayer.iconset")
    create_iconset(size_map, iconset_path)
    print(f"  Created: {iconset_path}/")
    if sys.platform == "darwin":
        import subprocess
        icns_path = os.path.join(OUT_DIRS["mac"], "icon.icns")
        subprocess.run(["iconutil", "-c", "icns", iconset_path, "-o", icns_path], check=True)
        print(f"  Created: {icns_path}")
    else:
        print("  Note: Run on macOS to generate icon.icns from iconset")

    # Linux PNG
    os.makedirs(OUT_DIRS["linux"], exist_ok=True)
    png_path = os.path.join(OUT_DIRS["linux"], "doda-player.png")
    size_map[256].save(png_path)
    print(f"  Created: {png_path}")

    print("Done.")


if __name__ == "__main__":
    main()
