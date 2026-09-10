import os
import random

from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, pyqtProperty


class Playlist(QObject):
    itemsChanged = pyqtSignal()
    currentIndexChanged = pyqtSignal(int)

    ITEM_ALL = 2
    ITEM_ONE = 1
    ITEM_NONE = 0

    def __init__(self, parent=None):
        super().__init__(parent)
        self._items = []
        self._current = -1
        self._shuffle = False
        self._repeat = 0
        self._history = []

    @pyqtProperty("QVariantList", notify=itemsChanged)
    def items(self):
        return list(self._items)

    @pyqtProperty(int, notify=currentIndexChanged)
    def currentIndex(self):
        return self._current

    @pyqtProperty(bool, notify=itemsChanged)
    def shuffle(self):
        return self._shuffle

    @shuffle.setter
    def shuffle(self, val):
        self._shuffle = bool(val)
        self.itemsChanged.emit()

    @pyqtProperty(int, notify=itemsChanged)
    def repeatMode(self):
        return self._repeat

    @repeatMode.setter
    def repeatMode(self, val):
        self._repeat = int(val)
        self.itemsChanged.emit()

    @pyqtSlot(str)
    def add(self, path):
        self._items.append(path)
        if self._current < 0:
            self._current = 0
            self.currentIndexChanged.emit(self._current)
        self.itemsChanged.emit()

    @pyqtSlot(int)
    def remove(self, index):
        if 0 <= index < len(self._items):
            self._items.pop(index)
            if self._current >= len(self._items):
                self._current = len(self._items) - 1
            elif index < self._current:
                self._current -= 1
            self.currentIndexChanged.emit(self._current)
            self.itemsChanged.emit()

    @pyqtSlot(int, int)
    def moveItem(self, fromIdx, toIdx):
        if 0 <= fromIdx < len(self._items) and 0 <= toIdx < len(self._items):
            item = self._items.pop(fromIdx)
            self._items.insert(toIdx, item)
            if self._current == fromIdx:
                self._current = toIdx
            elif fromIdx < self._current <= toIdx:
                self._current -= 1
            elif toIdx <= self._current < fromIdx:
                self._current += 1
            self.currentIndexChanged.emit(self._current)
            self.itemsChanged.emit()

    @pyqtSlot()
    def clear(self):
        self._items.clear()
        self._current = -1
        self._history.clear()
        self.currentIndexChanged.emit(-1)
        self.itemsChanged.emit()

    @pyqtSlot(result=int)
    def nextIndex(self):
        n = len(self._items)
        if n == 0:
            return -1
        if self._repeat == 1:
            return self._current
        if self._shuffle:
            candidates = [i for i in range(n) if i != self._current]
            if candidates:
                idx = random.choice(candidates)
                self._history.append(self._current)
                return idx
            return self._current
        idx = self._current + 1
        if idx >= n:
            if self._repeat == 2:
                return 0
            return -1
        return idx

    @pyqtSlot(result=int)
    def previousIndex(self):
        n = len(self._items)
        if n == 0:
            return -1
        if self._repeat == 1:
            return self._current
        if self._shuffle and self._history:
            return self._history.pop()
        idx = self._current - 1
        if idx < 0:
            if self._repeat == 2:
                return n - 1
            return 0
        return idx

    @pyqtSlot(result=str)
    def currentPath(self):
        if 0 <= self._current < len(self._items):
            return self._items[self._current]
        return ""

    def save_m3u(self, filepath):
        with open(filepath, "w") as f:
            f.write("#EXTM3U\n")
            for path in self._items:
                f.write(path + "\n")

    def load_m3u(self, filepath):
        items = []
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    if os.path.exists(line):
                        items.append(line)
        self._items = items
        self._current = 0 if items else -1
        self._history.clear()
        self.currentIndexChanged.emit(self._current)
        self.itemsChanged.emit()

    def set_items(self, items):
        self._items = list(items)
        self._current = 0 if items else -1
        self._history.clear()
        self.currentIndexChanged.emit(self._current)
        self.itemsChanged.emit()
