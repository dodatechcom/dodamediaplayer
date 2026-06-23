import os
import re

_SRT_TIMECODE = re.compile(r"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})")
_ASS_TIMECODE = re.compile(r"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{2})")


def _parse_srt_timecode(tc: str) -> int:
    m = _SRT_TIMECODE.match(tc.strip())
    if not m:
        return 0
    h, mi, s, ms = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
    return h * 3600000 + mi * 60000 + s * 1000 + ms


def _parse_ass_timecode(tc: str) -> int:
    m = _ASS_TIMECODE.match(tc.strip())
    if not m:
        return 0
    h, mi, s, cs = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
    return h * 3600000 + mi * 60000 + s * 1000 + cs * 10


def _parse_srt(path: str) -> list[dict]:
    try:
        with open(path, encoding="utf-8-sig") as f:
            content = f.read()
    except UnicodeDecodeError:
        with open(path, encoding="latin-1") as f:
            content = f.read()
    cues = []
    blocks = re.split(r"\n\s*\n", content.strip())
    for block in blocks:
        lines = block.strip().split("\n")
        if len(lines) < 2:
            continue
        timecode_line = None
        text_start = 0
        for i, line in enumerate(lines):
            if "-->" in line:
                timecode_line = line
                text_start = i + 1
                break
        if not timecode_line:
            continue
        parts = timecode_line.split("-->")
        if len(parts) != 2:
            continue
        start_ms = _parse_srt_timecode(parts[0])
        end_ms = _parse_srt_timecode(parts[1])
        text = "\n".join(lines[text_start:])
        text = re.sub(r"<[^>]+>", "", text)
        cues.append({"start_ms": start_ms, "end_ms": end_ms, "text": text})
    return cues


def _parse_ass(path: str) -> list[dict]:
    cues = []
    try:
        with open(path, encoding="utf-8-sig") as f:
            lines = f.readlines()
    except UnicodeDecodeError:
        with open(path, encoding="latin-1") as f:
            lines = f.readlines()

    fmt_line = None
    for line in lines:
        if line.startswith("Format:"):
            fmt_line = line.strip()
            break
    if not fmt_line:
        return cues
    fields = [f.strip() for f in fmt_line[7:].split(",")]
    try:
        start_idx = fields.index("Start")
        end_idx = fields.index("End")
        text_idx = fields.index("Text")
    except ValueError:
        return cues

    for line in lines:
        if not line.startswith("Dialogue:"):
            continue
        parts = line.strip()[9:].split(",", len(fields) - 1)
        if len(parts) < len(fields):
            continue
        start_str = parts[start_idx].strip().replace(".", ",")
        end_str = parts[end_idx].strip().replace(".", ",")
        text = parts[text_idx].strip()
        text = re.sub(r"\{[^}]*\}", "", text)
        text = text.replace("\\N", "\n").replace("\\n", "\n")
        start_ms = _parse_ass_timecode(start_str)
        end_ms = _parse_ass_timecode(end_str)
        if text:
            cues.append({"start_ms": start_ms, "end_ms": end_ms, "text": text})
    return cues


class SubtitleTrack:
    def __init__(self, name: str, cues: list[dict]):
        self.name = name
        self.cues = cues

    def get_text(self, position_ms: int) -> str:
        for cue in self.cues:
            if cue["start_ms"] <= position_ms < cue["end_ms"]:
                return cue["text"]
        return ""


class SubtitleManager:
    def __init__(self):
        self._tracks: list[SubtitleTrack] = []
        self._active = -1

    def clear(self):
        self._tracks = []
        self._active = -1

    def add_file(self, path: str) -> bool:
        if not os.path.isfile(path):
            return False
        ext = os.path.splitext(path)[1].lower()
        if ext == ".srt":
            cues = _parse_srt(path)
        elif ext == ".ass":
            cues = _parse_ass(path)
        else:
            return False
        if not cues:
            return False
        name = os.path.basename(path)
        self._tracks.append(SubtitleTrack(name, cues))
        return True

    def scan_for_subtitles(self, media_path: str):
        self.clear()
        if not media_path or media_path.startswith("http"):
            return
        base = os.path.dirname(media_path)
        stem = os.path.splitext(os.path.basename(media_path))[0]
        if not os.path.isdir(base):
            return
        try:
            for f in sorted(os.listdir(base)):
                fpath = os.path.join(base, f)
                if not os.path.isfile(fpath):
                    continue
                fstem, fext = os.path.splitext(f)
                if fstem == stem and fext.lower() in (".srt", ".ass"):
                    self.add_file(fpath)
        except PermissionError:
            pass

    @property
    def track_names(self) -> list[str]:
        return [t.name for t in self._tracks]

    @property
    def active_index(self) -> int:
        return self._active

    @active_index.setter
    def active_index(self, idx: int):
        if idx < -1 or idx >= len(self._tracks):
            self._active = -1
        else:
            self._active = idx

    @property
    def has_subtitles(self) -> bool:
        return len(self._tracks) > 0

    def get_text(self, position_ms: int) -> str:
        if self._active < 0 or self._active >= len(self._tracks):
            return ""
        return self._tracks[self._active].get_text(position_ms)
