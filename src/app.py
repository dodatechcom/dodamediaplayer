import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time

from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, pyqtProperty, QUrl, QProcess, QTimer
from PyQt6.QtMultimedia import QMediaPlayer, QAudioOutput
from PyQt6.QtWidgets import QFileDialog, QInputDialog, QMessageBox, QProgressDialog

from src.core.playlist import Playlist
from src.core.visualizer import AudioVisualizer
from src.core.subtitles import SubtitleManager

EQ_BANDS = 10
EQ_LABELS = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
EQ_DEFAULT = [1.0] * EQ_BANDS


ALBUM_ART_DIR = os.path.join(tempfile.gettempdir(), "doda-album-art")


def _find_ytdlp():
    candidates = [
        os.path.join(os.path.dirname(sys.executable), "yt-dlp.exe"),
        os.path.join(os.path.dirname(sys.executable), "yt-dlp"),
        "yt-dlp.exe",
        "yt-dlp",
    ]
    for c in candidates:
        try:
            subprocess.run([c, "--version"], capture_output=True, check=False)
            return c
        except FileNotFoundError:
            continue
    return "yt-dlp.exe" if sys.platform == "win32" else "yt-dlp"


def _resolve_url(url):
    """Resolve YouTube/streaming URL to a direct media URL via yt-dlp."""
    if not url.startswith("http"):
        return url
    ytdlp = _find_ytdlp()
    try:
        result = subprocess.run(
            [ytdlp, "-g", "--format", "best[height<=1080]", url],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            direct = result.stdout.strip().split("\n")[0]
            if direct:
                return direct
    except Exception:
        pass
    return url


class AppController(QObject):
    fileOpened = pyqtSignal(str)
    visualizerActiveChanged = pyqtSignal()
    eqChanged = pyqtSignal()
    playlistIndexChanged = pyqtSignal(int)
    audioSourceChanged = pyqtSignal()
    mediaInfoChanged = pyqtSignal()
    subtitlesChanged = pyqtSignal()
    statsEnabledChanged = pyqtSignal()
    statsDataChanged = pyqtSignal()
    currentUrlChanged = pyqtSignal()
    playbackStateChanged = pyqtSignal(int)
    positionChanged = pyqtSignal(int)
    durationChanged = pyqtSignal(int)
    playbackRateChanged = pyqtSignal()
    volumeChanged = pyqtSignal()
    mutedChanged = pyqtSignal()
    errorOccurred = pyqtSignal(int, str)
    sourceChanged = pyqtSignal()
    albumArtChanged = pyqtSignal()

    def __init__(self, parent=None, config=None):
        super().__init__(parent)
        self._window = None
        self._visualizer = AudioVisualizer()
        self._config = config
        self._eq_gains = list(EQ_DEFAULT)
        self._is_audio_source = True
        self._media_info = {}
        self._tracking = False
        self._track_start = 0
        self._track_path = ""
        self._subtitles = SubtitleManager()
        self._sub_visible = False
        self._current_url = ""
        self._last_state = 0
        self._player = None
        self._audio_output = None
        self._ytdlp = _find_ytdlp()
        self._album_art_path = ""

        if config:
            saved = config.get("eq_gains")
            if saved and len(saved) == EQ_BANDS:
                self._eq_gains = [max(0.0, min(4.0, float(v))) for v in saved]
        self._playlist = Playlist(self)
        self._playlist.currentIndexChanged.connect(self.playlistIndexChanged)
        self.loadPlaylist()

    def set_player(self, player, audio_output):
        self._player = player
        self._audio_output = audio_output

        player.playbackStateChanged.connect(self._on_state_changed)
        player.positionChanged.connect(self._on_position_changed)
        player.durationChanged.connect(self._on_duration_changed)
        player.errorOccurred.connect(self._on_error)
        player.sourceChanged.connect(self.sourceChanged.emit)

    def set_window(self, window):
        self._window = window

    def _on_state_changed(self, state):
        mapping = {
            QMediaPlayer.PlaybackState.PlayingState: 1,
            QMediaPlayer.PlaybackState.PausedState: 2,
            QMediaPlayer.PlaybackState.StoppedState: 0,
        }
        new_state = mapping.get(state, 0)
        if new_state != self._last_state:
            self._last_state = new_state
            self.playbackStateChanged.emit(new_state)
            if new_state == 0:
                pos_ms = self._player.position()
                dur_ms = self._player.duration()
                if pos_ms > 30000:
                    if self._config:
                        saved = self._config.get("resume_positions", {})
                        if isinstance(saved, dict):
                            saved[self._playlist.currentPath()] = pos_ms
                            self._config.set("resume_positions", saved)
                if dur_ms > 0 and pos_ms >= dur_ms - 500:
                    QTimer.singleShot(0, self.playNext)

    def _on_position_changed(self, pos):
        self.positionChanged.emit(pos)

    def _on_duration_changed(self, dur):
        self.durationChanged.emit(dur)

    def _on_error(self, error, error_string):
        self.errorOccurred.emit(int(error), error_string)

    def _play(self, path):
        if not path:
            return
        self._is_audio_source = not self._is_real_video(path)
        self.audioSourceChanged.emit()
        if path.startswith("http"):
            url = _resolve_url(path)
            self._player.setSource(QUrl(url))
        else:
            self._player.setSource(QUrl.fromLocalFile(path))
        self._player.play()
        self._load_visualizer(path)
        self._probe_media(path)
        self._subtitles.scan_for_subtitles(path)
        self._extract_album_art(path)
        self.subtitlesChanged.emit()
        self.fileOpened.emit(path)
        self.sourceChanged.emit()
        if not path.startswith("http") and self._config:
            saved = self._config.get("resume_positions", {})
            if isinstance(saved, dict):
                pos = saved.get(path)
                if pos:
                    self._player.setPosition(pos)

    @pyqtSlot(str)
    def copyText(self, text):
        from PyQt6.QtGui import QGuiApplication
        cb = QGuiApplication.clipboard()
        if cb:
            cb.setText(text)

    @pyqtSlot(str, "QVariant")
    def saveConfig(self, key, value):
        if self._config:
            import json
            try:
                value = json.loads(json.dumps(value))
            except Exception:
                value = str(value)
            self._config.set(key, value)

    @pyqtSlot(str, "QVariant", result="QVariant")
    def loadConfig(self, key, default=None):
        if self._config:
            val = self._config.get(key, default)
            import json
            try:
                val = json.loads(json.dumps(val))
            except Exception:
                pass
            return val
        return default

    @pyqtSlot(bool)
    def setAlwaysOnTop(self, on_top: bool):
        from PyQt6.QtCore import Qt
        if self._window:
            if on_top:
                self._window.setFlags(self._window.flags() | Qt.WindowType.WindowStaysOnTopHint)
            else:
                self._window.setFlags(self._window.flags() & ~Qt.WindowType.WindowStaysOnTopHint)
            self._window.show()

    def _load_visualizer(self, path: str):
        if path.startswith("http") or self._is_real_video(path):
            self._visualizer.clear()
            self.visualizerActiveChanged.emit()
        else:
            self._visualizer.load_file(path, callback=self.visualizerActiveChanged.emit)

    def _probe_media(self, path: str):
        self._media_info = {}
        if path.startswith("http"):
            self._media_info["filename"] = path.rsplit("/", 1)[-1] or path
            self._media_info["format"] = "Stream"
            self.mediaInfoChanged.emit()
            return
        try:
            import av
            container = av.open(path, metadata_encoding="latin-1", metadata_errors="ignore")
            info = {}
            info["filename"] = os.path.basename(path)
            info["format"] = container.format.name if container.format else "Unknown"
            dur = float(container.duration) / 1_000_000 if container.duration else 0
            info["duration"] = dur
            for stream in container.streams:
                if stream.type == "video":
                    cc = stream.codec_context
                    info["video_codec"] = cc.name if cc else "Unknown"
                    info["resolution"] = f"{stream.width}x{stream.height}" if stream.width else "Unknown"
                    info["frame_rate"] = f"{float(stream.average_rate):.2f}" if stream.average_rate else "Unknown"
                    if cc and cc.bit_rate:
                        info["video_bitrate"] = f"{cc.bit_rate // 1000} kbps"
                elif stream.type == "audio":
                    cc = stream.codec_context
                    info["audio_codec"] = cc.name if cc else "Unknown"
                    info["sample_rate"] = f"{stream.sample_rate} Hz" if stream.sample_rate else "Unknown"
                    info["channels"] = {1: "Mono", 2: "Stereo", 6: "5.1", 8: "7.1"}.get(stream.channels, str(stream.channels))
                    if stream.channels:
                        info["audio_channels"] = stream.channels
                    if cc and cc.bit_rate:
                        info["audio_bitrate"] = f"{cc.bit_rate // 1000} kbps"
            container.close()
            self._media_info = info
        except Exception:
            self._media_info = {}
        self.mediaInfoChanged.emit()

    def _extract_album_art(self, path: str):
        self._album_art_path = ""
        if path.startswith("http"):
            self.albumArtChanged.emit()
            return
        try:
            import av
            from PyQt6.QtGui import QImage
            container = av.open(path, metadata_encoding="latin-1", metadata_errors="ignore")
            for stream in container.streams:
                if stream.type == "video":
                    d = stream.disposition
                    if bool(d & type(d).attached_pic):
                        os.makedirs(ALBUM_ART_DIR, exist_ok=True)
                        out_path = os.path.join(ALBUM_ART_DIR, f"{abs(hash(path))}.jpg")
                        if not os.path.exists(out_path):
                            for packet in container.demux(stream):
                                for frame in packet.decode():
                                    if frame:
                                        arr = frame.to_ndarray(format="rgb24")
                                        h, w = arr.shape[:2]
                                        img = QImage(arr.tobytes(), w, h, w * 3, QImage.Format.Format_RGB888)
                                        img.save(out_path, "JPEG")
                                        break
                                if os.path.exists(out_path):
                                    break
                        if os.path.exists(out_path):
                            self._album_art_path = out_path
                        break
            container.close()
        except Exception:
            self._album_art_path = ""
        self.albumArtChanged.emit()

    @pyqtProperty(QUrl, notify=albumArtChanged)
    def albumArt(self):
        if self._album_art_path:
            return QUrl.fromLocalFile(self._album_art_path)
        return QUrl()

    @pyqtProperty("QVariantMap", notify=mediaInfoChanged)
    def mediaInfo(self):
        return dict(self._media_info)

    @pyqtSlot(result=str)
    def openFile(self):
        path, _ = QFileDialog.getOpenFileName(
            None,
            "Open Media File",
            "",
            (
                "Media Files (*.mp4 *.mkv *.avi *.mov *.wmv *.flv "
                "*.webm *.mp3 *.wav *.flac *.ogg *.m4a *.aac *.wma);;"
                "All Files (*)"
            ),
        )
        if path:
            if self._current_url:
                self._current_url = ""
                self.currentUrlChanged.emit()
            self._playlist.add(path)
            idx = len(self._playlist._items) - 1
            self._playlist._current = idx
            self.playlistIndexChanged.emit(idx)
            self._play(path)
            return path
        return ""

    @pyqtSlot(str)
    def openPath(self, path):
        if not path.startswith("http"):
            if self._current_url:
                self._current_url = ""
                self.currentUrlChanged.emit()
            self._playlist.add(path)
            idx = len(self._playlist._items) - 1
            self._playlist._current = idx
            self.playlistIndexChanged.emit(idx)
            self._play(path)
        else:
            self._current_url = path
            self.currentUrlChanged.emit()
            self._is_audio_source = False
            self.audioSourceChanged.emit()
            url = _resolve_url(path)
            self._player.setSource(QUrl(url))
            self._player.play()
            self._visualizer.clear()
            self.visualizerActiveChanged.emit()
            self.fileOpened.emit(path)
            self.sourceChanged.emit()

    @pyqtProperty(bool, notify=audioSourceChanged)
    def isAudioSource(self):
        return self._is_audio_source

    @pyqtProperty(str, notify=currentUrlChanged)
    def currentUrl(self):
        return self._current_url

    def _is_real_video(self, path: str) -> bool:
        if path.startswith("http"):
            return True
        try:
            import av
            container = av.open(path, metadata_encoding="latin-1", metadata_errors="ignore")
            result = False
            for stream in container.streams:
                if stream.type == "video":
                    d = stream.disposition
                    is_attached = bool(d & type(d).attached_pic)
                    if not is_attached:
                        result = True
                        break
            container.close()
            return result
        except Exception:
            return False

    @pyqtProperty(bool, notify=visualizerActiveChanged)
    def visualizerActive(self):
        return self._visualizer.active

    @pyqtSlot(float, result=list)
    def getSpectrum(self, position_ms):
        raw = self._visualizer.get_spectrum(position_ms)
        if not raw:
            return raw
        n = len(raw)
        return [min(1.0, raw[i] * self._eq_gains[min(EQ_BANDS - 1, math.floor(i * EQ_BANDS / n))]) for i in range(n)]

    @pyqtProperty("QVariantList", notify=eqChanged)
    def eqGains(self):
        return list(self._eq_gains)

    @pyqtSlot(int, float)
    def setEqGain(self, index, value):
        if 0 <= index < EQ_BANDS:
            self._eq_gains[index] = max(0.0, min(4.0, float(value)))
            self.eqChanged.emit()
            if self._config:
                self._config.set("eq_gains", self._eq_gains)

    @pyqtSlot()
    def resetEq(self):
        self._eq_gains = list(EQ_DEFAULT)
        self.eqChanged.emit()
        if self._config:
            self._config.set("eq_gains", self._eq_gains)

    @pyqtProperty("QVariantList", constant=True)
    def eqBandLabels(self):
        return EQ_LABELS

    @pyqtSlot(int)
    def applyEqPreset(self, preset):
        presets = {
            0: [1.0]*10,
            1: [1.4, 1.2, 1.0, 0.8, 0.6, 0.6, 0.8, 1.0, 1.2, 1.4],
            2: [0.6, 0.8, 1.0, 1.2, 1.4, 1.4, 1.2, 1.0, 0.8, 0.6],
            3: [1.2, 1.2, 1.2, 0.8, 0.6, 0.6, 0.8, 1.2, 1.4, 1.4],
            4: [1.6, 1.4, 1.0, 0.6, 0.4, 0.4, 0.6, 1.0, 1.4, 1.6],
        }
        gains = presets.get(preset, [1.0]*10)
        self._eq_gains = gains
        self.eqChanged.emit()
        if self._config:
            self._config.set("eq_gains", self._eq_gains)

    @pyqtProperty(QObject, constant=True)
    def playlist(self):
        return self._playlist

    def _stats_data(self) -> dict:
        if not self._config:
            return {"files": {}, "daily": {}, "total_ms": 0}
        raw = self._config.get("stats_data", {})
        if not isinstance(raw, dict):
            raw = {}
        raw.setdefault("files", {})
        raw.setdefault("daily", {})
        raw.setdefault("total_ms", 0)
        return raw

    def _save_stats(self, data: dict):
        if self._config:
            self._config.set("stats_data", data)

    @pyqtProperty(bool, notify=statsEnabledChanged)
    def statsEnabled(self):
        if not self._config:
            return False
        return bool(self._config.get("stats_enabled", False))

    @pyqtSlot(bool)
    def setStatsEnabled(self, enabled: bool):
        if self._config:
            self._config.set("stats_enabled", bool(enabled))
            self.statsEnabledChanged.emit()
            self.statsDataChanged.emit()

    @pyqtSlot()
    def resetStats(self):
        self._tracking = False
        self._track_start = 0
        self._track_path = ""
        if self._config:
            self._config.set("stats_data", {"files": {}, "daily": {}, "total_ms": 0})
            self.statsDataChanged.emit()

    @pyqtProperty("QVariantMap", notify=statsDataChanged)
    def statsData(self):
        if not self.statsEnabled:
            return {}
        data = self._stats_data()
        total_ms = data.get("total_ms", 0)
        from datetime import date
        today = date.today().isoformat()
        today_ms = data.get("daily", {}).get(today, 0)
        session_ms = 0
        if self._tracking and self._track_start > 0:
            session_ms = int((time.time() - self._track_start) * 1000)

        files = data.get("files", {})
        sorted_files = sorted(files.items(), key=lambda x: x[1].get("total_ms", 0), reverse=True)
        top = []
        for path, info in sorted_files[:5]:
            top.append({
                "name": os.path.basename(path),
                "count": info.get("play_count", 0),
                "total_ms": info.get("total_ms", 0),
            })

        return {
            "total_ms": total_ms + session_ms,
            "today_ms": today_ms + session_ms,
            "session_ms": session_ms,
            "top_files": top,
        }

    @pyqtSlot(str)
    def trackPlayStart(self, path: str):
        if not self.statsEnabled or not path:
            return
        self._flush_track()
        self._tracking = True
        import time
        self._track_start = time.time()
        self._track_path = path

    @pyqtSlot(str)
    def trackPlayStop(self, path: str = ""):
        if not self._tracking:
            return
        if path and path != self._track_path:
            return
        self._flush_track()
        self._tracking = False
        self._track_start = 0
        self._track_path = ""

    def _flush_track(self):
        if not self._tracking or self._track_start <= 0 or not self._track_path:
            return
        import time
        elapsed_ms = int((time.time() - self._track_start) * 1000)
        if elapsed_ms < 500:
            return
        data = self._stats_data()
        data["total_ms"] = data.get("total_ms", 0) + elapsed_ms
        from datetime import date
        day = date.today().isoformat()
        daily = data.setdefault("daily", {})
        daily[day] = daily.get(day, 0) + elapsed_ms
        files = data.setdefault("files", {})
        f = files.setdefault(self._track_path, {"play_count": 0, "total_ms": 0})
        f["play_count"] = f.get("play_count", 0) + 1
        f["total_ms"] = f.get("total_ms", 0) + elapsed_ms
        self._save_stats(data)
        self.statsDataChanged.emit()

    # ---- end Stats ----

    # ---- Subtitles ----

    @pyqtProperty("QVariantList", notify=subtitlesChanged)
    def subtitleTrackNames(self):
        return list(self._subtitles.track_names)

    @pyqtProperty(int, notify=subtitlesChanged)
    def activeSubtitleIndex(self):
        return self._subtitles.active_index

    @pyqtProperty(bool, notify=subtitlesChanged)
    def subtitleVisible(self):
        return self._sub_visible

    @pyqtSlot(int)
    def setActiveSubtitle(self, idx: int):
        self._subtitles.active_index = idx
        self.subtitlesChanged.emit()

    @pyqtSlot(bool)
    def setSubtitleVisible(self, v: bool):
        self._sub_visible = bool(v)
        self.subtitlesChanged.emit()

    @pyqtSlot(bool)
    def toggleSubtitles(self):
        if self._sub_visible:
            self._sub_visible = False
        elif self._subtitles.track_names:
            self._subtitles.active_index = 0
            self._sub_visible = True
        self.subtitlesChanged.emit()

    @pyqtSlot(int, result=str)
    def getSubtitleText(self, position_ms: int):
        return self._subtitles.get_text(position_ms)

    @pyqtSlot()
    def openSubtitleFile(self):
        path, _ = QFileDialog.getOpenFileName(
            None, "Open Subtitle File", "",
            "Subtitle Files (*.srt *.ass);;All Files (*)"
        )
        if path:
            self._subtitles.add_file(path)
            self.subtitlesChanged.emit()

    # ---- end Subtitles ----

    PLAYLIST_FILE = os.path.join(os.path.expanduser("~"), ".config", "doda-player", "playlist.m3u8")

    @pyqtSlot(result=bool)
    def savePlaylist(self):
        try:
            os.makedirs(os.path.dirname(self.PLAYLIST_FILE), exist_ok=True)
            self._playlist.save_m3u(self.PLAYLIST_FILE)
            return True
        except Exception:
            return False

    @pyqtSlot(result=bool)
    def loadPlaylist(self):
        try:
            if os.path.exists(self.PLAYLIST_FILE):
                self._playlist.load_m3u(self.PLAYLIST_FILE)
                return True
        except Exception:
            pass
        return False

    @pyqtSlot(str)
    def savePlaylistAs(self, path):
        self._playlist.save_m3u(path)

    @pyqtSlot(str)
    def loadPlaylistFrom(self, path):
        self._playlist.load_m3u(path)

    @pyqtSlot()
    def playPause(self):
        if self._player:
            if self._player.playbackState() == QMediaPlayer.PlaybackState.PlayingState:
                self._player.pause()
            else:
                self._player.play()

    @pyqtSlot()
    def playNext(self):
        idx = self._playlist.nextIndex()
        if idx >= 0:
            self._playlist._current = idx
            self.playlistIndexChanged.emit(idx)
            self._play(self._playlist.currentPath())

    @pyqtSlot()
    def playPrevious(self):
        if not self._player:
            return
        pos = self._player.position()
        if pos > 3000:
            self._player.setPosition(0)
            return
        if self._playlist._items:
            idx = self._playlist.previousIndex()
            if idx >= 0:
                self._playlist._current = idx
                self.playlistIndexChanged.emit(idx)
                self._play(self._playlist.currentPath())

    @pyqtSlot()
    def playlistAddFile(self):
        path, _ = QFileDialog.getOpenFileName(
            None, "Add to Playlist", "",
            "Media Files (*.mp4 *.mkv *.avi *.mov *.wmv *.flv "
            "*.webm *.mp3 *.wav *.flac *.ogg *.m4a *.aac *.wma);;All Files (*)"
        )
        if path:
            self._playlist.add(path)

    @pyqtSlot(result=str)
    def openUrl(self):
        url, ok = QInputDialog.getText(None, "Open URL", "Enter YouTube or media URL:")
        if not ok or not url:
            return ""

        msg = QMessageBox()
        msg.setWindowTitle("URL Options")
        msg.setText("What would you like to do?")
        msg.setInformativeText(url)
        stream_btn = msg.addButton("▶  Stream", QMessageBox.ButtonRole.ActionRole)
        dl_mp4_btn = msg.addButton("⬇  Download MP4", QMessageBox.ButtonRole.ActionRole)
        dl_mp3_btn = msg.addButton("⬇  Download MP3", QMessageBox.ButtonRole.ActionRole)
        cancel_btn = msg.addButton("Cancel", QMessageBox.ButtonRole.RejectRole)
        msg.setDefaultButton(stream_btn)
        msg.exec()

        clicked = msg.clickedButton()
        if clicked == cancel_btn:
            return ""
        if clicked in (dl_mp4_btn, dl_mp3_btn):
            fmt = "mp3" if clicked == dl_mp3_btn else "mp4"
            self._download_media(url, fmt)
            return ""

        self._current_url = url
        self.currentUrlChanged.emit()
        self._is_audio_source = False
        self.audioSourceChanged.emit()
        direct = _resolve_url(url)
        self._player.setSource(QUrl(direct))
        self._player.play()
        self._visualizer.clear()
        self.visualizerActiveChanged.emit()
        self.fileOpened.emit(url)
        return url

    @pyqtSlot(str, str)
    def downloadMedia(self, url, fmt):
        self._download_media(url, fmt)

    @pyqtSlot(str)
    def downloadCurrentMedia(self, fmt):
        if self._current_url:
            self._download_media(self._current_url, fmt)

    def _download_media(self, url, fmt):
        output_dir = os.path.expanduser(
            "~/Videos/DodaPlayer" if fmt == "mp4" else "~/Music/DodaPlayer"
        )
        os.makedirs(output_dir, exist_ok=True)

        self._dl_progress = QProgressDialog(
            f"Downloading {fmt.upper()}...", "Cancel", 0, 100
        )
        self._dl_progress.setWindowTitle("Download")
        self._dl_progress.setAutoClose(True)
        self._dl_progress.setMinimumDuration(0)
        self._dl_progress.show()

        self._dl_output_path = None

        cmd = [self._ytdlp, "--no-playlist", "--newline"]
        if fmt == "mp4":
            cmd += ["--format", "best[ext=mp4]/best"]
            cmd += ["-o", os.path.join(output_dir, "%(title)s.%(ext)s")]
        else:
            cmd += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
            cmd += ["-o", os.path.join(output_dir, "%(title)s.%(ext)s")]
        cmd.append(url)

        self._dl_proc = QProcess(self)
        self._dl_proc.readyReadStandardOutput.connect(self._on_dl_stdout)
        self._dl_proc.finished.connect(self._on_dl_finished)
        self._dl_progress.canceled.connect(self._dl_proc.kill)
        self._dl_proc.start(cmd[0], cmd[1:])

    def _on_dl_stdout(self):
        if not hasattr(self, '_dl_proc'):
            return
        data = self._dl_proc.readAllStandardOutput().data().decode('utf-8', errors='replace')
        for line in data.split('\n'):
            line = line.strip()
            if not line:
                continue
            m = re.search(r'\[download\]\s+(\d+\.?\d*)%', line)
            if m:
                pct = float(m.group(1))
                if hasattr(self, '_dl_progress') and self._dl_progress:
                    self._dl_progress.setValue(min(99, int(pct)))
            detected = None
            for pat in [
                r'^\[download\] Destination: (.+)',
                r'\[Merger\] Merging formats into "(.+)"',
                r'\[ExtractAudio\] Destination: (.+)',
                r'\[VideoConvertor\] Not converting video file (.+)',
            ]:
                m2 = re.search(pat, line)
                if m2:
                    detected = m2.group(1).strip().strip('"')
                    break
            if detected:
                self._dl_output_path = detected

    def _on_dl_finished(self, exit_code, exit_status):
        self._on_dl_stdout()
        if hasattr(self, '_dl_progress') and self._dl_progress:
            self._dl_progress.close()
            self._dl_progress = None
        if exit_code == 0 and self._dl_output_path and os.path.exists(self._dl_output_path):
            self._dl_progress = None
            msg = QMessageBox()
            msg.setWindowTitle("Download Complete")
            msg.setText(f"Saved to:\n{self._dl_output_path}")
            play_btn = msg.addButton("▶  Play", QMessageBox.ButtonRole.AcceptRole)
            open_btn = msg.addButton("📂  Open Folder", QMessageBox.ButtonRole.ActionRole)
            msg.addButton("Close", QMessageBox.ButtonRole.RejectRole)
            msg.exec()
            if msg.clickedButton() == play_btn:
                self._play(self._dl_output_path)
            elif msg.clickedButton() == open_btn:
                folder = os.path.dirname(self._dl_output_path)
                if sys.platform == "win32":
                    os.startfile(folder)
                elif sys.platform == "darwin":
                    subprocess.run(["open", folder], check=False)
                else:
                    subprocess.run(["xdg-open", folder], check=False)
        else:
            if hasattr(self, '_dl_progress'):
                self._dl_progress = None
            QMessageBox.critical(None, "Download Failed", "Download failed or was cancelled.")

    @pyqtSlot()
    def closeMedia(self):
        if self._current_url:
            self._current_url = ""
            self.currentUrlChanged.emit()
        if self._player:
            self._player.stop()
            self._player.setSource(QUrl())

    @pyqtProperty(int, notify=playbackStateChanged)
    def playbackState(self):
        return self._last_state

    @pyqtProperty(int, notify=positionChanged)
    def position(self):
        return self._player.position() if self._player else 0

    @position.setter
    def position(self, pos_ms):
        if self._player:
            self._player.setPosition(max(0, pos_ms))

    @pyqtProperty(int, notify=durationChanged)
    def duration(self):
        return self._player.duration() if self._player else 0

    @pyqtProperty(float, notify=playbackRateChanged)
    def playbackRate(self):
        return self._player.playbackRate() if self._player else 1.0

    @playbackRate.setter
    def playbackRate(self, rate):
        if self._player:
            self._player.setPlaybackRate(max(0.25, min(2.0, float(rate))))
            self.playbackRateChanged.emit()

    @pyqtProperty(float, notify=volumeChanged)
    def volume(self):
        return self._audio_output.volume() if self._audio_output else 1.0

    @volume.setter
    def volume(self, val):
        if self._audio_output:
            self._audio_output.setVolume(max(0.0, min(1.0, float(val))))
            self.volumeChanged.emit()

    @pyqtProperty(bool, notify=mutedChanged)
    def muted(self):
        return self._audio_output.isMuted() if self._audio_output else False

    @muted.setter
    def muted(self, val):
        if self._audio_output:
            self._audio_output.setMuted(bool(val))
            self.mutedChanged.emit()
