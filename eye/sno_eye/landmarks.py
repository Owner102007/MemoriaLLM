"""Ориентиры лица (SNO-ALG-EYE-01, шаг 2).

MediaPipe Tasks `FaceLandmarker`: режим VIDEO, до двух лиц (чтобы
заметить второе и взять крупное), блендшейпы и матрица преобразования
лица включены, на вход — кадр целиком.

Модель `face_landmarker.task` лежит в `eye/models/` и перед загрузкой
сверяется по SHA-256 из `eye/model_version.txt`.
"""

from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import paths
from .synthetic import Face, Head, render

PLACEHOLDER = "не-закреплена"


class ModelError(Exception):
    """Модели нет или она не та."""


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def expected_model() -> dict[str, str]:
    return paths.read_kv(paths.model_version_path())


def verify_model(path: Path | None = None) -> str:
    """Сумма модели, если она совпала с замком; иначе `ModelError`."""
    path = path or paths.model_path()
    want = expected_model().get("sha256", "")
    if not path.exists():
        raise ModelError(f"нет файла модели {path.name}")
    got = file_sha256(path)
    if not want or want == PLACEHOLDER:
        raise ModelError(f"сумма модели не закреплена (у файла {got})")
    if got != want:
        raise ModelError(f"модель не та: сумма {got}, ожидалась {want}")
    return got


@dataclass
class Detection:
    face: Face | None
    faces: int


class MediaPipeLandmarker:
    def __init__(self, model: Path | None = None):
        os.environ.setdefault("MPLBACKEND", "Agg")
        import mediapipe as mp
        from mediapipe.tasks.python import vision
        from mediapipe.tasks.python.core import base_options

        self.model_sha256 = verify_model(model)
        self._mp = mp
        options = vision.FaceLandmarkerOptions(
            base_options=base_options.BaseOptions(
                model_asset_path=str(model or paths.model_path())),
            running_mode=vision.RunningMode.VIDEO,
            num_faces=2,
            output_face_blendshapes=True,
            output_facial_transformation_matrixes=True,
        )
        self._task = vision.FaceLandmarker.create_from_options(options)
        self._last_ms = -1
        self.version = getattr(mp, "__version__", "?")

    def detect(self, frame_bgr: np.ndarray, t_ms: int, meta: dict | None = None) -> Detection:
        import cv2

        # VIDEO требует строго растущих меток.
        t_ms = max(int(t_ms), self._last_ms + 1)
        self._last_ms = t_ms
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        image = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=rgb)
        result = self._task.detect_for_video(image, t_ms)
        n = len(result.face_landmarks)
        if n == 0:
            return Detection(None, 0)
        best, best_area = 0, -1.0
        arrays = []
        for k, lms in enumerate(result.face_landmarks):
            arr = np.array([(p.x, p.y, p.z) for p in lms], dtype=np.float64)
            arrays.append(arr)
            span = arr[:, :2].max(axis=0) - arr[:, :2].min(axis=0)
            area = float(span[0] * span[1])
            if area > best_area:
                best, best_area = k, area
        matrix = np.eye(4)
        if result.facial_transformation_matrixes:
            matrix = np.asarray(result.facial_transformation_matrixes[best])
        shapes: dict[str, float] = {}
        if result.face_blendshapes:
            shapes = {c.category_name: float(c.score) for c in result.face_blendshapes[best]}
        return Detection(Face(arrays[best], matrix, shapes), n)

    def close(self) -> None:
        self._task.close()


class SyntheticLandmarker:
    """Ориентиры из параметров головы, которые синтетический источник
    кладёт в `meta['head']`. Модель не нужна."""

    version = "synthetic"
    model_sha256 = "synthetic"

    def detect(self, frame_bgr: np.ndarray, t_ms: int, meta: dict | None = None) -> Detection:
        head: Head | None = (meta or {}).get("head")
        if head is None:
            return Detection(None, 0)
        h, w = frame_bgr.shape[:2]
        faces = int((meta or {}).get("faces", 1))
        return Detection(render(head, w, h), faces)

    def close(self) -> None:
        pass
