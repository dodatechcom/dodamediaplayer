import os
import sys
import traceback

os.environ.setdefault("QT_LOGGING_RULES", "qt.multimedia.ffmpeg*=false")

from PyQt6.QtCore import Qt, QUrl
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtQuick import QQuickItem, QQuickWindow
from PyQt6.QtWidgets import QApplication, QMessageBox

from src.app import AppController
from src.core.config import Config

CRASH_LOG = os.path.join(os.path.expanduser("~"), ".config", "doda-player", "crash.log")

_QT_AV_NAMES = {
    "linux": (["libQt6FFmpegStub-ssl.so.3", "libQt6FFmpegStub-crypto.so.3"],
              "libavutil.so.59"),
    "win32": ([], "avutil-59.dll"),
    "darwin": ([], "libavutil.59.dylib"),
}


def _quiet_qt_ffmpeg():
    """Lower the log level of the FFmpeg bundled with Qt Multimedia.

    Qt ships its own FFmpeg (separate from PyAV's) whose av_log messages
    bypass both PyAV's logging settings and Qt logging categories. In
    particular it emits an AV_LOG_ERROR about CUDA hardware setup on every
    video open. Since Qt surfaces real playback problems via its own error
    machinery, we silence anything below FATAL from that copy of FFmpeg.
    """
    try:
        import ctypes
        from PyQt6.QtCore import QLibraryInfo
        libdir = QLibraryInfo.path(QLibraryInfo.LibraryPath.LibrariesPath)
        stubs, avutil = _QT_AV_NAMES.get(sys.platform, ([], "libavutil.so.59"))
        for stub in stubs:
            p = os.path.join(libdir, stub)
            if os.path.exists(p):
                ctypes.CDLL(p, mode=ctypes.RTLD_GLOBAL)
        p = os.path.join(libdir, avutil)
        if os.path.exists(p):
            lib = ctypes.CDLL(p, mode=ctypes.RTLD_GLOBAL)
            lib.av_log_set_level(8)
    except Exception:
        pass


def _crash_handler(exctype, value, tb):
    msg = "".join(traceback.format_exception(exctype, value, tb))
    os.makedirs(os.path.dirname(CRASH_LOG), exist_ok=True)
    with open(CRASH_LOG, "w") as f:
        f.write(msg)
    try:
        app = QGuiApplication.instance()
        if app:
            mb = QMessageBox()
            mb.setWindowTitle("Doda Media Player - Error")
            mb.setText("An unexpected error occurred.\n\nThe application will now exit.")
            mb.setDetailedText(msg)
            mb.setIcon(QMessageBox.Icon.Critical)
            mb.exec()
    except Exception:
        pass
    sys.__excepthook__(exctype, value, tb)


def main():
    sys.excepthook = _crash_handler
    QQuickWindow.setDefaultAlphaBuffer(True)

    try:
        import av
        av.logging.set_level(av.logging.ERROR)
    except Exception:
        pass

    _quiet_qt_ffmpeg()

    app = QApplication(sys.argv)
    app.setApplicationName("Doda Media Player")
    app.setOrganizationName("DodaMedia")
    app.setOrganizationDomain("dodamedia.local")

    config_dir = os.path.join(os.path.expanduser("~"), ".config", "doda-player")
    os.makedirs(config_dir, exist_ok=True)

    config = Config()
    controller = AppController(config=config)

    player = QMediaPlayer()
    audio_output = QAudioOutput()
    player.setAudioOutput(audio_output)
    controller.set_player(player, audio_output)

    engine = QQmlApplicationEngine()

    qml_dir = os.path.join(os.path.dirname(__file__), "ui")
    if not os.path.isdir(qml_dir):
        qml_dir = os.path.join(os.path.dirname(__file__), "src", "ui")
    if not os.path.isdir(qml_dir):
        qml_dir = os.path.abspath("ui")
    engine.addImportPath(qml_dir)

    engine.rootContext().setContextProperty("app", controller)

    qml_file = os.path.join(qml_dir, "main.qml")
    engine.load(QUrl.fromLocalFile(qml_file))

    if not engine.rootObjects():
        raise RuntimeError("Failed to load QML - check crash.log for details")

    window = engine.rootObjects()[0]
    controller.set_window(window)

    video_item = window.findChild(QQuickItem, "videoOutput")
    if video_item:
        video_sink = video_item.property("videoSink")
        if video_sink:
            player.setVideoSink(video_sink)

    vol = config.get("volume")
    if vol is not None:
        audio_output.setVolume(vol / 100.0)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
