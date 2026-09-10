import threading
import numpy as np

SAMPLE_RATE = 22050
WINDOW_SIZE = 2048
HOP_SIZE = WINDOW_SIZE // 2
NUM_BARS = 32


class AudioVisualizer:
    def __init__(self):
        self._samples = None
        self._cache = []
        self._cache_ready = False
        self._lock = threading.Lock()

    def load_file(self, path: str, callback=None):
        self.clear()
        threading.Thread(target=self._build_for_file, args=(path, callback), daemon=True).start()

    def _build_for_file(self, path: str, callback=None):
        try:
            import av
            container = av.open(path, metadata_encoding="latin-1", metadata_errors="ignore")
            audio_stream = next(
                (s for s in container.streams if s.type == "audio"), None
            )
            if audio_stream is None:
                container.close()
                return
            resampler = av.AudioResampler("s16", "mono", SAMPLE_RATE)
            raw_chunks = []
            for packet in container.demux(audio_stream):
                for frame in packet.decode():
                    if frame is None:
                        continue
                    for out in resampler.resample(frame):
                        if out and out.planes:
                            raw_chunks.append(bytes(memoryview(out.planes[0])))
            container.close()
            if not raw_chunks:
                return
            raw = b"".join(raw_chunks)
            samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32)
            hanning = np.hanning(WINDOW_SIZE)
            half = WINDOW_SIZE // 2 + 1
            num_windows = (len(samples) - WINDOW_SIZE) // HOP_SIZE + 1
            if num_windows < 1:
                return
            window_msec = HOP_SIZE / SAMPLE_RATE * 1000

            shape = (num_windows, WINDOW_SIZE)
            strides = (samples.strides[0] * HOP_SIZE, samples.strides[0])
            windows = np.lib.stride_tricks.as_strided(samples, shape=shape, strides=strides)
            windows = windows * hanning
            mag = np.abs(np.fft.rfft(windows))
            mag_max = mag.max(axis=1, keepdims=True)
            mag_max = np.where(mag_max < 1e-10, 1.0, mag_max)
            mag = mag / mag_max

            bin_indices = (np.arange(NUM_BARS + 1) / NUM_BARS) ** 1.8 * half
            bin_indices = bin_indices.astype(int)
            bin_indices = np.clip(bin_indices, 0, half - 1)
            bars_out = np.zeros((num_windows, NUM_BARS))
            for j in range(NUM_BARS):
                low, high = bin_indices[j], max(bin_indices[j] + 1, bin_indices[j + 1])
                bars_out[:, j] = mag[:, low:high].mean(axis=1)
            bars_out = np.clip(bars_out ** 0.4 * 1.5, 0.0, 1.0)

            pos_ms_arr = np.arange(num_windows, dtype=np.float64) * window_msec
            local_cache = list(zip(pos_ms_arr.tolist(), bars_out.tolist()))

            with self._lock:
                self._samples = samples
                self._cache = local_cache
                self._cache_ready = True
            if callback:
                callback()
        except Exception:
            self.clear()
            if callback:
                callback()

    def clear(self):
        with self._lock:
            self._samples = None
            self._cache = []
            self._cache_ready = False

    @property
    def active(self) -> bool:
        with self._lock:
            return self._cache_ready

    def get_spectrum(self, position_ms: float) -> list[float]:
        with self._lock:
            if not self._cache_ready or not self._cache:
                return [0.0] * NUM_BARS
            lo, hi = 0, len(self._cache) - 1
            while lo < hi:
                mid = (lo + hi + 1) // 2
                if self._cache[mid][0] <= position_ms:
                    lo = mid
                else:
                    hi = mid - 1
            return self._cache[lo][1]
