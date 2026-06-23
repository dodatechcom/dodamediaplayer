# Doda Media Player

A cross-platform media player built with Python, PyQt6, QML, and Qt Multimedia (FFmpeg backend).

## Features

- **Playback**: Video/audio files (MP4, MKV, AVI, MOV, MP3, WAV, FLAC, etc.) and YouTube/URL streams via yt-dlp (ad-free — bypasses YouTube's web player entirely)
- **Dark theme** with auto-hiding controls during playback
- **URL download** — After resolving a YouTube/URL, choose Stream, Download MP4, or Download MP3 (audio-only). Progress bar, auto-saves to `~/Videos/DodaPlayer` / `~/Music/DodaPlayer`. Download button appears in top bar and context menu during streaming
- **Subtitles** — SRT and ASS support, auto-detected alongside media files, CC button in bottom bar, Y shortcut
- **Audio visualizer** — 16 fully rendered modes (Bars, Wave, Circle, Mirror, Glow, Fire, Rings, Bubbles, VU Meter, Pinwheel, Meteor, Waves, Water, Stairs, Orbit, X-Ray) with precomputed FFT spectrum
- **Equalizer** — 10-band graphic EQ with 5 presets (Flat, Rock, Pop, Classical, Dance), gains saved to config
- **Playlist** — add/remove/reorder files, shuffle, repeat (None/One/All), m3u save/load, drag-and-drop
- **Playback speed** — 0.25x–2.0x via button cycling or menu selection
- **Media info panel** — codec, resolution, bitrate, frame rate, sample rate, etc. via PyAV probe
- **True fullscreen** — hides all chrome (menu, bars, panels), shows on mouse move
- **Picture-in-Picture** — floating always-on-top mini window (Ctrl+P), click to pause/play
- **Seek bar preview** — time tooltip on hover, frame preview seeks to hover position
- **Mouse wheel volume** — scroll on any bottom-bar icon adjusts volume
- **Always on Top** — toggle via View menu
- **Resume last position** — saves position every 10s and on stop/close, restores on reopen
- **Window geometry restore** — remembers position and size across sessions
- **Stats tracking** (opt-in) — play counts, daily totals, top files, session tracking
- **Custom SVG icons** — 19 3D-style gradient icons for all controls
- **Settings dialog** — Catppuccin-inspired theme, stats view with Most Played, Reset button
- **Help menu** — Documentation, Donate, About dialog

## Controls

### Top Bar (always visible)

| Button | Action |
|--------|--------|
| Folder icon | Open media file |
| URL icon | Open URL (YouTube, etc.) — then choose Stream / Download MP4 / Download MP3 |
| Track name | Displayed between URL and download buttons |
| ⬇ Download | Download currently streaming video (MP4 or MP3), appears while streaming |
| ✕ Close | Close current media / clear playlist |
| ⏻ Quit | Quit application (turns red on hover) |

### Bottom Bar (auto-hides during playback)

| Control | Action |
|---------|--------|
| Seek bar | Click/drag to seek; hover for time preview |
| ⏪ Previous | Previous track (P) |
| ⏴ Back 10s | Seek backward |
| ▶ / ⏸ Play / Pause | Toggle playback |
| ⏵ Skip 10s | Seek forward |
| ⏭ Next | Next track (N) |
| ♪ / M Mute | Toggle mute (M) |
| Volume slider | Adjust volume 0–100% |
| L | Toggle playlist panel |
| Visualizer icon | Show/cycle visualizer (H) |
| EQ icon | Toggle equalizer (E) |
| Shuffle icon | Toggle shuffle (S) |
| Repeat icon | Cycle repeat (R) |
| Speed `1x` | Cycle speed 0.25x–2.0x (Z) |
| **i** | Toggle media info panel (I) |
| **CC** | Toggle subtitles (Y) — auto-detects .srt/.ass files |
| Fullscreen icon | Toggle fullscreen (F) |
| **PiP** | Toggle Picture-in-Picture mode (Ctrl+P) |

### Menu Bar

| Menu | Items |
|------|-------|
| File | Open File... (O), Open URL... (Ctrl+U), Add to Playlist..., Open Subtitle File..., Quit (Ctrl+Q) |
| Playback | Play/Pause (Space), Mute (M), Visualizer submenu (V), Speed submenu (Z) |
| View | Fullscreen (F), Always on Top, Picture-in-Picture, Visualizer On, Equalizer (E), Media Info (I), Subtitles submenu (Y), EQ Preset submenu |
| Tools | Settings... (Ctrl+T) |
| Help | Documentation, Donate, About |

### Right-click Context Menu

Play/Pause, Mute, Previous (P), Next (N), Open File, Fullscreen (F), Visualizer cycle (V), Picture-in-Picture, Subtitles (Y), Quit

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| **Space** | Play / Pause |
| **O** | Open file dialog |
| **Ctrl+U** | Open URL |
| **Ctrl+Q** | Quit |
| **Ctrl+P** | Toggle Picture-in-Picture |
| **Ctrl+T** | Open settings |
| **Left** | Seek backward 5s |
| **Right** | Seek forward 5s |
| **Up** | Volume +10% |
| **Down** | Volume -10% |
| **F** | Toggle fullscreen |
| **Escape** | Exit fullscreen |
| **M** | Toggle mute |
| **V** | Cycle visualizer mode |
| **H** | Toggle visualizer |
| **E** | Toggle equalizer |
| **L** | Toggle playlist |
| **N** | Next track |
| **P** | Previous track |
| **S** | Toggle shuffle |
| **R** | Cycle repeat mode |
| **Z** | Cycle playback speed |
| **I** | Toggle media info |
| **Y** | Toggle subtitles (auto-detects .srt/.ass) |

## Mouse Controls

- **Click video** — Toggle controls visibility
- **Hover video** — Show controls (auto-hide after 3s during playback)
- **Hover seek bar** — Time tooltip with frame preview (seeks to hover position)
- **Scroll any bottom-bar icon** — Adjust volume
- **Double-click video** — Toggle fullscreen
- **Right-click video** — Context menu
- **Drag & drop** media files onto window — Add to playlist (first plays)

## Dependencies

- Python 3.11+
- PyQt6 >= 6.5
- yt-dlp (for URL playback)
- numpy (for FFT spectrum computation)
- av (PyAV, for audio decoding and media probing)

## Run

```bash
.venv/bin/python -c "import sys; sys.path.insert(0, '.'); from src.main import main; main()"
```

## Project Structure

```
DodaMediaPlayer/
├── src/
│   ├── main.py              # Entry point
│   ├── app.py               # AppController (Python ↔ QML bridge)
│   ├── core/
│   │   ├── config.py        # Settings persistence (JSON)
│   │   ├── visualizer.py    # Audio FFT spectrum analyzer
│   │   ├── subtitles.py     # SRT/ASS parser
│   │   └── playlist.py      # Playlist model with shuffle/repeat
│   └── ui/
│       ├── main.qml         # Main window, all controls and overlays
│       └── icons/           # 19 SVG icons (3D gradient style)
├── tests/
├── requirements.txt
├── pyproject.toml
└── README.md
```
