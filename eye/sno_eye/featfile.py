"""Файл признаков кадра `features.bin` (SNO-ALG-EYE-01, шаг 6).

Устройство:

* 8 байт `SNOEYEF1`, 4 байта длины заголовка (LE), заголовок — JSON в
  UTF-8: схема `sno2026-eyefeat/1`, поля записи, номера ориентиров,
  версии и сумма модели, сегмент.
* Дальше пачки: 4 байта длины сжатого, 4 байта числа записей, zlib от
  записей подряд. Пачка — за секунду кадров; сброс на диск — по пачке.

Записи фиксированной длины (`record_dtype`). Ориентиры хранятся
float16 **относительно середины внешних уголков и в долях расстояния
между ними**: в пикселях float16 у края кадра 1080p ошибался бы на
пиксель, а так — на десятые доли пикселя. Начало и масштаб лежат в векторе
признаков (`face_x`, `face_y`, `scale_px`), поэтому пиксели
восстанавливаются: p = lm · scale_px + (face_x · w, face_y · h).

Файл, оборванный сбоем, читается до последней целой пачки.
"""

from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path
from typing import BinaryIO, Iterator

import numpy as np

from . import faceparts as fp

MAGIC = b"SNOEYEF1"
SCHEMA = "sno2026-eyefeat/1"

# Флаги записи.
NO_FACE = 1
BLINK = 2
HEAD_TURNED = 4
MULTI_FACE = 8
DROPPED_BEFORE = 16  # перед этим кадром захват выбросил кадры


def record_dtype(n_landmarks: int = len(fp.STORED),
                 n_shapes: int = len(fp.EYE_BLENDSHAPES),
                 n_features: int = len(fp.FEATURE_NAMES)) -> np.dtype:
    return np.dtype([
        ("n", "<u8"),
        ("qpc_us", "<i8"),
        ("flags", "<u2"),
        ("video_frame", "<i4"),
        ("lm", "<f2", (n_landmarks, 3)),
        ("matrix", "<f4", (16,)),
        ("bs", "<f2", (n_shapes,)),
        ("feat", "<f4", (n_features,)),
    ])


def is_ok(flags: int) -> bool:
    return not flags & (NO_FACE | BLINK | HEAD_TURNED)


class FeatWriter:
    def __init__(self, path: Path, header_extra: dict | None = None):
        self.path = Path(path)
        self.dtype = record_dtype()
        header = {
            "schema": SCHEMA,
            "fields": [name for name in self.dtype.names],
            "landmarks": list(fp.STORED),
            "lm_encoding": "relative_to_outer_corners_midpoint_over_outer_corner_distance",
            "blendshapes": list(fp.EYE_BLENDSHAPES),
            "features": list(fp.FEATURE_NAMES),
            "flags": {"no_face": NO_FACE, "blink": BLINK,
                      "head_turned": HEAD_TURNED, "multi_face": MULTI_FACE,
                      "dropped_before": DROPPED_BEFORE},
        }
        header.update(header_extra or {})
        raw = json.dumps(header, ensure_ascii=False).encode("utf-8")
        self._f: BinaryIO = open(self.path, "wb")
        self._f.write(MAGIC + struct.pack("<I", len(raw)) + raw)
        self._f.flush()
        self._pending: list[np.ndarray] = []
        self.records = 0
        self.blocks = 0

    def new_record(self) -> np.ndarray:
        rec = np.zeros((), dtype=self.dtype)
        rec["video_frame"] = -1
        return rec

    def add(self, rec: np.ndarray) -> None:
        self._pending.append(rec)

    def flush_block(self) -> None:
        if not self._pending:
            return
        arr = np.array(self._pending, dtype=self.dtype)
        data = zlib.compress(arr.tobytes(), 6)
        self._f.write(struct.pack("<II", len(data), len(arr)) + data)
        self._f.flush()
        self.records += len(arr)
        self.blocks += 1
        self._pending.clear()

    def close(self) -> None:
        if self._f.closed:
            return
        self.flush_block()
        self._f.close()


def read(path: Path) -> tuple[dict, np.ndarray, bool]:
    """Заголовок, записи и признак «файл цел» (False — хвост отрезан)."""
    raw = Path(path).read_bytes()
    if raw[:8] != MAGIC:
        raise ValueError("не файл признаков")
    (hlen,) = struct.unpack_from("<I", raw, 8)
    header = json.loads(raw[12:12 + hlen].decode("utf-8"))
    dtype = record_dtype(len(header["landmarks"]), len(header["blendshapes"]),
                         len(header["features"]))
    pos = 12 + hlen
    parts: list[np.ndarray] = []
    whole = True
    for chunk in _blocks(raw, pos):
        if chunk is None:
            whole = False
            break
        data, count = chunk
        try:
            arr = np.frombuffer(zlib.decompress(data), dtype=dtype)
        except zlib.error:
            whole = False
            break
        if len(arr) != count:
            whole = False
            break
        parts.append(arr)
    recs = np.concatenate(parts) if parts else np.zeros(0, dtype=dtype)
    return header, recs, whole


def _blocks(raw: bytes, pos: int) -> Iterator[tuple[bytes, int] | None]:
    while pos < len(raw):
        if pos + 8 > len(raw):
            yield None
            return
        size, count = struct.unpack_from("<II", raw, pos)
        pos += 8
        if pos + size > len(raw):
            yield None
            return
        yield raw[pos:pos + size], count
        pos += size


def encode_landmarks(px_stored: np.ndarray, origin: np.ndarray, scale: float) -> np.ndarray:
    """Ориентиры (пиксели, только `STORED`) → запись в долях."""
    rel = (px_stored - np.array([origin[0], origin[1], 0.0])) / scale
    return rel.astype(np.float16)


def decode_landmarks(lm: np.ndarray, feat: np.ndarray, width: int, height: int) -> np.ndarray:
    names = fp.FEATURE_NAMES
    fx = feat[names.index("face_x")] * width
    fy = feat[names.index("face_y")] * height
    scale = feat[names.index("scale_px")]
    return lm.astype(np.float64) * scale + np.array([fx, fy, 0.0])
