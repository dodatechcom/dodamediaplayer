import os
import sys

from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtQuick import QQuickItem, QQuickWindow
from PyQt6.QtWidgets import QApplication

from src.app import AppController
from src.core.config import Config


def main():
    QQuickWindow.setDefaultAlphaBuffer(True)

    app = QApplication(sys.argv)
    app.setApplicationName("Doda Media Player")
    app.setOrganizationName("DodaMedia")
    app.setOrganizationDomain("dodamedia.local")

    config = Config()
    controller = AppController(config=config)

    player = QMediaPlayer()
    audio_output = QAudioOutput()
    player.setAudioOutput(audio_output)
    controller.set_player(player, audio_output)

    engine = QQmlApplicationEngine()

    # Support both development (src/ui/) and PyInstaller bundle (ui/)
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
        print("Failed to load QML", file=sys.stderr)
        sys.exit(1)

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
