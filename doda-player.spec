# -*- mode: python ; coding: utf-8 -*-
import os, sys, glob

block_cipher = None

datas = []
# QML files
for f in glob.glob("src/ui/*.qml"):
    datas.append((f, "ui"))
# SVG icons
for f in glob.glob("src/ui/icons/*.svg"):
    datas.append((f, "ui/icons"))

# Collect Qt QML plugins (import paths, etc.)
from PyInstaller.utils.hooks import collect_data_files
qml_plugin_datas = collect_data_files("PyQt6.QtQml")
for src, dst in qml_plugin_datas:
    found = False
    for i, (s, d) in enumerate(datas):
        if s == src and d == dst:
            found = True
            break
    if not found:
        datas.append((src, dst))

# Find yt-dlp binary
ytdlp_bin = None
for c in ["yt-dlp.exe", "yt-dlp"]:
    for p in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(p, c)
        if os.path.isfile(candidate):
            ytdlp_bin = candidate
            break
    if ytdlp_bin:
        break
if not ytdlp_bin:
    for c in ["yt-dlp.exe", "yt-dlp"]:
        candidate = os.path.join(os.path.dirname(sys.executable), c)
        if os.path.isfile(candidate):
            ytdlp_bin = candidate
            break
binaries = []
if ytdlp_bin:
    binaries.append((ytdlp_bin, "."))

a = Analysis(
    ["src/main.py"],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=[
        "PyQt6.QtMultimedia",
        "PyQt6.QtQml",
        "PyQt6.QtQuick",
        "PyQt6.QtGui",
        "PyQt6.QtNetwork",
        "PyQt6.QtCore",
        "src.app",
        "src.core.playlist",
        "src.core.visualizer",
        "src.core.subtitles",
        "src.core.config",
        "av",
        "av.codec",
        "av.container",
        "av.stream",
        "yt_dlp",
    ],
    hookspath=[],
    hooksconfig={"PyQt6": {"plugins": ["multimedia", "qml", "svg", "network"]}},
    runtime_hooks=[],
    excludes=[
        "tkinter",
        "matplotlib",
        "scipy",
        "PIL",
        "curses",
        "distutils",
        "setuptools",
        "pip",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="doda-player",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

if sys.platform == "darwin":
    icns_path = "build/installer/macos/icon.icns"
    if not os.path.isfile(icns_path):
        icns_path = ""
    app = BUNDLE(
        exe,
        name="DodaMediaPlayer.app",
        icon=icns_path if icns_path else None,
        bundle_identifier="com.doda.mediaplayer",
        info_plist={
            "CFBundleDisplayName": "Doda Media Player",
            "CFBundleName": "DodaMediaPlayer",
            "CFBundleVersion": "0.1.0",
            "CFBundleShortVersionString": "0.1.0",
            "NSHighResolutionCapable": True,
        },
    )
