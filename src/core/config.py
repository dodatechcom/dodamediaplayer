import json
import os

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".config", "doda-player")
CONFIG_FILE = os.path.join(CONFIG_DIR, "settings.json")

DEFAULTS = {
    "volume": 50,
    "window_width": 960,
    "window_height": 540,
    "recent_files": [],
    "theme": "dark",
    "stats_enabled": False,
    "stats_data": {},
}


class Config:
    def __init__(self):
        self._data = dict(DEFAULTS)
        self._load()

    def _load(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE) as f:
                    loaded = json.load(f)
                    self._data.update(loaded)
            except (json.JSONDecodeError, OSError):
                pass

    def save(self):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(self._data, f, indent=2)

    def get(self, key, default=None):
        value = self._data.get(key, default)
        if default is not None and type(value) is not type(default):
            return default
        return value

    def set(self, key, value):
        self._data[key] = value
        self.save()

    def add_recent_file(self, path):
        recents = self._data.get("recent_files", [])
        if path in recents:
            recents.remove(path)
        recents.insert(0, path)
        self._data["recent_files"] = recents[:10]
        self.save()
