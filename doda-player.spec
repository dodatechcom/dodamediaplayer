# -*- mode: python ; coding: utf-8 -*-
import os, sys, glob

block_cipher = None

datas = []
# include QML files
for f in glob.glob("src/ui/*.qml"):
    datas.append((f, "src/ui"))
# include icons
for f in glob.glob("src/ui/icons/*.svg"):
    datas.append((f, "src/ui/icons"))

a = Analysis(
    ["src/main.py"],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=[
        "PyQt6.QtMultimedia",
        "PyQt6.QtQml",
        "PyQt6.QtQuick",
        "PyQt6.QtGui",
        "src.app",
        "src.core.playlist",
        "src.core.visualizer",
        "src.core.subtitles",
        "src.core.config",
        "av",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
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
    app = BUNDLE(
        exe,
        name="DodaMediaPlayer.app",
        icon="build/installer/macos/icon.icns",
        bundle_identifier="com.doda.mediaplayer",
        info_plist={
            "CFBundleDisplayName": "Doda Media Player",
            "CFBundleName": "DodaMediaPlayer",
            "CFBundleVersion": "0.1.0",
            "CFBundleShortVersionString": "0.1.0",
            "NSHighResolutionCapable": True,
        },
    )
