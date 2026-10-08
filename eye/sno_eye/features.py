"""Признаки ступени 0 (SNO-ALG-EYE-01, шаг 3).

Короткий вектор, который меняется вместе со взглядом и мало — с
остальным. Устройство признаков — по образцу EyeTrax (MIT): ориентиры
переносятся в систему головы, а из неё берутся положение радужек
относительно уголков, открытость век, поза головы и место лица в кадре.
Код написан заново; авторство идеи — в THIRD_PARTY_NOTICES.txt.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from . import faceparts as fp

# Поворот головы, за которым кадр негоден (шаг 4).
MAX_YAW = 30.0
MAX_PITCH = 25.0


def to_pixels(landmarks: np.ndarray, width: int, height: int) -> np.ndarray:
    """Доли кадра → пиксели; z MediaPipe отмерен в долях ширины."""
    out = np.array(landmarks, dtype=np.float64, copy=True)
    out[:, 0] *= width
    out[:, 1] *= height
    out[:, 2] *= width
    return out


def angles_from_matrix(matrix: np.ndarray) -> tuple[float, float, float]:
    """yaw, pitch, roll в градусах для R = Rz(roll) · Ry(yaw) · Rx(pitch)."""
    r = np.asarray(matrix, dtype=np.float64)[:3, :3]
    # Матрица MediaPipe несёт масштаб лица; поворот — по нормированным
    # столбцам.
    norms = np.linalg.norm(r, axis=0)
    norms[norms == 0] = 1.0
    r = r / norms
    yaw = math.degrees(math.asin(max(-1.0, min(1.0, -r[2, 0]))))
    pitch = math.degrees(math.atan2(r[2, 1], r[2, 2]))
    roll = math.degrees(math.atan2(r[1, 0], r[0, 0]))
    return yaw, pitch, roll


@dataclass
class HeadFrame:
    origin: np.ndarray
    axes: np.ndarray   # строки — оси x, y, z системы головы
    scale: float       # расстояние между внешними уголками, пиксели

    def apply(self, p: np.ndarray) -> np.ndarray:
        return (self.axes @ (np.asarray(p) - self.origin).T).T / self.scale


def head_frame(px: np.ndarray) -> HeadFrame:
    """Система головы: начало — середина внешних уголков, ось x — от
    правого уголка к левому, y — вниз (от точки 10), масштаб —
    расстояние между уголками."""
    a, b = px[fp.R_OUTER], px[fp.L_OUTER]
    origin = (a + b) / 2
    x = b - a
    scale = float(np.linalg.norm(x))
    if scale <= 1e-9:
        raise ValueError("уголки глаз совпали")
    x = x / scale
    up = px[fp.FOREHEAD_TOP] - origin
    y = -(up - np.dot(up, x) * x)
    ny = float(np.linalg.norm(y))
    if ny <= 1e-9:
        raise ValueError("точка лба на оси глаз")
    y = y / ny
    z = np.cross(x, y)
    return HeadFrame(origin=origin, axes=np.stack([x, y, z]), scale=scale)


def iris_diameter_px(px: np.ndarray) -> float:
    ds = []
    for ring in (fp.R_IRIS_RING, fp.L_IRIS_RING):
        p = px[list(ring), :2]
        ds.append(np.linalg.norm(p[0] - p[2]))
        ds.append(np.linalg.norm(p[1] - p[3]))
    return float(np.mean(ds))


def compute(landmarks: np.ndarray, matrix: np.ndarray,
            width: int, height: int) -> np.ndarray:
    """Вектор признаков (порядок — `faceparts.FEATURE_NAMES`)."""
    px = to_pixels(landmarks, width, height)
    hf = head_frame(px)
    out = []
    for outer, inner, iris in ((fp.R_OUTER, fp.R_INNER, fp.R_IRIS),
                               (fp.L_OUTER, fp.L_INNER, fp.L_IRIS)):
        o, i, c = hf.apply(px[[outer, inner, iris]])
        centre = (o + i) / 2
        width_eye = abs(o[0] - i[0]) or 1e-9
        out.append((c[0] - centre[0]) / width_eye)
        out.append((c[1] - centre[1]) / width_eye)
    for outer, inner, upper, lower in (
        (fp.R_OUTER, fp.R_INNER, fp.R_UPPER, fp.R_LOWER),
        (fp.L_OUTER, fp.L_INNER, fp.L_UPPER, fp.L_LOWER),
    ):
        o, i, u, lo = hf.apply(px[[outer, inner, upper, lower]])
        out.append(float(np.linalg.norm(u - lo) / (np.linalg.norm(o - i) or 1e-9)))
    yaw, pitch, roll = angles_from_matrix(matrix)
    out += [yaw, pitch, roll]
    out += [hf.origin[0] / width, hf.origin[1] / height]
    out.append(float(np.linalg.norm(px[fp.L_OUTER, :2] - px[fp.R_OUTER, :2])))
    out.append(iris_diameter_px(px))
    return np.asarray(out, dtype=np.float32)


def head_turned(vec: np.ndarray) -> bool:
    yaw = vec[fp.FEATURE_NAMES.index("yaw")]
    pitch = vec[fp.FEATURE_NAMES.index("pitch")]
    return abs(yaw) > MAX_YAW or abs(pitch) > MAX_PITCH


def eye_boxes(px: np.ndarray, width: int, height: int) -> list[tuple[int, int, int, int]]:
    """Прямоугольники глаз (x0, y0, x1, y1) с запасом — для яркости и
    бликов самопроверки."""
    boxes = []
    for contour in (fp.R_EYE_CONTOUR, fp.L_EYE_CONTOUR):
        p = px[list(contour), :2]
        x0, y0 = p.min(axis=0)
        x1, y1 = p.max(axis=0)
        pad = 0.25 * (x1 - x0)
        boxes.append((
            int(max(0, x0 - pad)), int(max(0, y0 - pad)),
            int(min(width, x1 + pad)), int(min(height, y1 + pad)),
        ))
    return boxes


def face_box(px: np.ndarray, width: int, height: int) -> tuple[int, int, int, int]:
    p = px[:, :2]
    x0, y0 = p.min(axis=0)
    x1, y1 = p.max(axis=0)
    return (int(max(0, x0)), int(max(0, y0)),
            int(min(width, x1)), int(min(height, y1)))
