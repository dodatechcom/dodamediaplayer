# -*- mode: python ; coding: utf-8 -*-
import os, sys, glob, shutil

block_cipher = None

datas = []
# QML files
for f in glob.glob("src/ui/*.qml"):
    datas.append((f, "ui"))
# SVG icons
for f in glob.glob("src/ui/icons/*.svg"):
    datas.append((f, "ui/icons"))

# Collect required Qt QML imports and FFmpeg DLLs
try:
    import PyQt6
    QT6_DIR = os.path.join(os.path.dirname(PyQt6.__file__), "Qt6")
    QML_IMPORTS_DIR = os.path.join(QT6_DIR, "qml")
    QML_NEEDED = {"QtCore", "QtMultimedia", "QtQml", "QtQuick", "QtNetwork"}
    if os.path.isdir(QML_IMPORTS_DIR):
        for import_name in QML_NEEDED:
            src = os.path.join(QML_IMPORTS_DIR, import_name)
            if os.path.isdir(src):
                for root, dirs, files in os.walk(src):
                    for fn in files:
                        file_path = os.path.join(root, fn)
                        rel = os.path.relpath(os.path.dirname(file_path), QML_IMPORTS_DIR)
                        datas.append((file_path, f"PyQt6/Qt6/qml/{rel}"))

    for lib_dir in ["lib", "bin"]:
        path = os.path.join(QT6_DIR, lib_dir)
        if os.path.isdir(path):
            for fn in os.listdir(path):
                if any(fn.startswith(p) for p in ["libav", "libsw", "av", "sw"]):
                    datas.append((os.path.join(path, fn), f"PyQt6/Qt6/{lib_dir}"))

    mm_plugin_src = os.path.join(QT6_DIR, "plugins", "multimedia")
    if os.path.isdir(mm_plugin_src):
        for fn in os.listdir(mm_plugin_src):
            datas.append((os.path.join(mm_plugin_src, fn), "PyQt6/Qt6/plugins/multimedia"))
except Exception:
    pass

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
    [],
    exclude_binaries=True,
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

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="doda-player",
)

if sys.platform == "darwin":
    icns_path = "build/installer/macos/icon.icns"
    if not os.path.isfile(icns_path):
        icns_path = ""
    app = BUNDLE(
        coll,
        name="DodaMediaPlayer.app",
        icon=icns_path if icns_path else None,
        bundle_identifier="com.doda.mediaplayer",
        info_plist={
            "CFBundleDisplayName": "Doda Media Player",
            "CFBundleName": "DodaMediaPlayer",
            "CFBundleVersion": "0.1.1",
            "CFBundleShortVersionString": "0.1.1",
            "NSHighResolutionCapable": True,
        },
    )
