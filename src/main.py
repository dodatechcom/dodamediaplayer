import os
import sys
import traceback

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtQuick import QQuickItem, QQuickWindow
from PyQt6.QtWidgets import QApplication, QMessageBox

from src.app import AppController
from src.core.config import Config

CRASH_LOG = os.path.join(os.path.expanduser("~"), ".config", "doda-player", "crash.log")


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
    engine.load(qml_file)

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
