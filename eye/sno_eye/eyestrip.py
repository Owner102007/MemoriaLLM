"""Полоса глаз (SNO-ALG-EYE-01, шаг 5).

Нормировка как у BlazeGaze (WebEyeTrack): лицо переносится гомографией
в квадрат 512 × 512 по точкам 103, 332, 150, 379, предварительно
отодвинутым от кончика носа (точка 4) на 0,4 по ширине и 0,2 по высоте;
полоса вырезается между перенесёнными точками 151 и 195 и сжимается до
64 × 256. Сеть ждёт 128 × 512 — поэтому стенд пишет две минуты полосы
в обоих размерах (их сравнит ET-08).

Запись — H.264 через PyAV в MP4 с фрагментами по ключевым кадрам (раз в
2 с): файл, оборванный сбоем, читается до последнего фрагмента.
"""

from __future__ import annotations

from fractions import Fraction
from pathlib import Path

import cv2
import numpy as np

from . import faceparts as fp

SQUARE = 512
STRIP_SIZES = {"64x256": (64, 256), "128x512": (128, 512)}
DEFAULT_STRIP = "64x256"
PUSH_W, PUSH_H = 0.4, 0.2


def corner_points(px: np.ndarray) -> np.ndarray:
    """Четыре угла области лица в порядке «лв, пв, лн, пн» снимка,
    отодвинутые от кончика носа."""
    nose = px[fp.NOSE_TIP, :2]
    ul, ur, ll, lr = (px[i, :2] for i in fp.STRIP_CORNERS)
    pts = np.array([ul, ur, ll, lr], dtype=np.float64)
    pushed = pts + (pts - nose) * np.array([PUSH_W, PUSH_H])
    return pushed.astype(np.float32)


def homography(px: np.ndarray) -> np.ndarray:
    src = corner_points(px)
    dst = np.array([[0, 0], [SQUARE, 0], [0, SQUARE], [SQUARE, SQUARE]],
                   dtype=np.float32)
    return cv2.getPerspectiveTransform(src, dst)


def strip_rows(px: np.ndarray, h: np.ndarray) -> tuple[int, int]:
    """Строки квадрата, между которыми режется полоса."""
    pts = np.array([[px[fp.STRIP_TOP, :2]], [px[fp.STRIP_BOTTOM, :2]]],
                   dtype=np.float32)
    top, bottom = cv2.perspectiveTransform(pts, h)[:, 0, 1]
    y0, y1 = sorted((float(top), float(bottom)))
    y0 = int(max(0, min(SQUARE - 2, round(y0))))
    y1 = int(max(y0 + 2, min(SQUARE, round(y1))))
    return y0, y1


def cut(frame_bgr: np.ndarray, px: np.ndarray, size: str = DEFAULT_STRIP) -> np.ndarray:
    """Полоса глаз размера `size` (высота × ширина), RGB."""
    h = homography(px)
    square = cv2.warpPerspective(frame_bgr, h, (SQUARE, SQUARE),
                                 flags=cv2.INTER_LINEAR)
    y0, y1 = strip_rows(px, h)
    band = square[y0:y1]
    sh, sw = STRIP_SIZES[size]
    band = cv2.resize(band, (sw, sh), interpolation=cv2.INTER_AREA)
    return cv2.cvtColor(band, cv2.COLOR_BGR2RGB)


class StripWriter:
    """MP4 с фрагментами, H.264 (libx264), CRF 23, veryfast,
    ключевой кадр раз в 2 с."""

    def __init__(self, path: Path, size: str = DEFAULT_STRIP, fps: int = 30):
        import av  # тяжёлый модуль — только когда пишем

        self.path = Path(path)
        self.size = size
        h, w = STRIP_SIZES[size]
        self._container = av.open(
            str(self.path), mode="w", format="mp4",
            options={"movflags": "frag_keyframe+empty_moov+default_base_moof"},
        )
        stream = self._container.add_stream("libx264", rate=fps)
        stream.width = w
        stream.height = h
        stream.pix_fmt = "yuv420p"
        stream.codec_context.time_base = Fraction(1, fps)
        stream.options = {
            "crf": "23", "preset": "veryfast",
            "g": str(2 * fps), "keyint_min": str(2 * fps),
            "sc_threshold": "0",
        }
        self._stream = stream
        self._av = av
        self.frames = 0

    def write(self, rgb: np.ndarray) -> int:
        """Кадр полосы; возвращает его номер в видео."""
        frame = self._av.VideoFrame.from_ndarray(np.ascontiguousarray(rgb), format="rgb24")
        frame.pts = self.frames
        for packet in self._stream.encode(frame):
            self._container.mux(packet)
        n = self.frames
        self.frames += 1
        return n

    def close(self) -> None:
        if self._container is None:
            return
        try:
            for packet in self._stream.encode():
                self._container.mux(packet)
        finally:
            self._container.close()
            self._container = None


def count_readable(path: Path) -> int:
    """Сколько кадров файла читается — и у оборванного тоже."""
    import av

    n = 0
    try:
        with av.open(str(path)) as c:
            for _ in c.decode(video=0):
                n += 1
    except (av.FFmpegError, OSError, ValueError):
        pass
    return n


def has_x264() -> bool:
    import av

    return "libx264" in av.codecs_available
