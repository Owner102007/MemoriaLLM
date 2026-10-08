"""Синтетика для тестов и для `--source synthetic`.

Параметрическая голова: шаблон нужных ориентиров в миллиметрах,
поворот (yaw, pitch, roll), сдвиг и масштаб в кадре, взгляд —
сдвиг радужек внутри глаз. По ней признаки проверяются без камеры и без
модели: известно, куда смотрит «человек», и известно, как он сидит.

Система шаблона — как у снимка: x вправо по снимку, y вниз, z от камеры.
Правый глаз человека лежит слева на снимке (x < 0).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

from . import faceparts as fp

N_LANDMARKS = 478

# Радиус радужки и ход её центра при взгляде до упора, мм.
IRIS_R = 5.8
GAZE_X_MM = 6.0
GAZE_Y_MM = 3.5


def _template() -> dict[int, tuple[float, float, float]]:
    t: dict[int, tuple[float, float, float]] = {}
    for sign, contour, upper, lower, outer, inner in (
        (-1, fp.R_EYE_CONTOUR, fp.R_UPPER, fp.R_LOWER,
         fp.R_OUTER, fp.R_INNER),
        (1, fp.L_EYE_CONTOUR, fp.L_UPPER, fp.L_LOWER,
         fp.L_OUTER, fp.L_INNER),
    ):
        cx = 30.0 * sign
        # Контур глаза — эллипс 15 × 5 мм; уголки и середины век — на нём.
        for k, idx in enumerate(contour):
            a = 2 * math.pi * k / len(contour)
            t[idx] = (cx + 15.0 * math.cos(a) * sign, 5.0 * math.sin(a), 0.0)
        t[outer] = (cx + 15.0 * sign, 0.0, 0.0)
        t[inner] = (cx - 15.0 * sign, 0.0, 0.0)
        t[upper] = (cx, -5.0, 0.0)
        t[lower] = (cx, 5.0, 0.0)
    for brow, sign in ((fp.R_BROW, -1), (fp.L_BROW, 1)):
        for k, idx in enumerate(brow):
            t[idx] = (sign * (14.0 + 3.6 * k), -16.0 - 2.0 * math.sin(k / 3), -2.0)
    ref = {
        10: (0.0, -85.0, 8.0), 151: (0.0, -55.0, 2.0), 9: (0.0, -35.0, -2.0),
        168: (0.0, -14.0, -6.0), 6: (0.0, -4.0, -10.0),
        195: (0.0, 18.0, -22.0), 4: (0.0, 36.0, -30.0),
        1: (0.0, 40.0, -29.0), 152: (0.0, 112.0, 0.0),
        234: (-74.0, 25.0, 25.0), 454: (74.0, 25.0, 25.0),
        103: (-48.0, -62.0, 10.0), 332: (48.0, -62.0, 10.0),
        150: (-52.0, 78.0, 12.0), 379: (52.0, 78.0, 12.0),
    }
    t.update(ref)
    return t


TEMPLATE = _template()


def rotation(yaw: float, pitch: float, roll: float) -> np.ndarray:
    """Поворот R = Rz(roll) · Ry(yaw) · Rx(pitch), углы в градусах."""
    y, p, r = (math.radians(v) for v in (yaw, pitch, roll))
    rx = np.array([[1, 0, 0],
                   [0, math.cos(p), -math.sin(p)],
                   [0, math.sin(p), math.cos(p)]])
    ry = np.array([[math.cos(y), 0, math.sin(y)],
                   [0, 1, 0],
                   [-math.sin(y), 0, math.cos(y)]])
    rz = np.array([[math.cos(r), -math.sin(r), 0],
                   [math.sin(r), math.cos(r), 0],
                   [0, 0, 1]])
    return rz @ ry @ rx


@dataclass
class Head:
    """Положение головы и взгляда в кадре."""

    yaw: float = 0.0
    pitch: float = 0.0
    roll: float = 0.0
    cx: float = 0.5           # середина между уголками глаз, доля ширины
    cy: float = 0.45          # и высоты кадра
    px_per_mm: float = 2.0    # масштаб: на 60 см у 1080p примерно 2
    gaze_x: float = 0.0       # −1 … 1: влево … вправо по снимку
    gaze_y: float = 0.0       # −1 … 1: вверх … вниз
    lid: float = 1.0          # открытость век: 1 — обычная, 0 — закрыты
    blink_score: float = 0.0  # блендшейп eyeBlink, который «вернула модель»


@dataclass
class Face:
    """То, что возвращает распознавание одного лица."""

    landmarks: np.ndarray            # (478, 3), доли кадра; z — в долях ширины
    matrix: np.ndarray               # (4, 4)
    blendshapes: dict[str, float] = field(default_factory=dict)


def render(head: Head, width: int, height: int) -> Face:
    """Ориентиры головы `head` на кадре `width` × `height`."""
    pts = np.zeros((N_LANDMARKS, 3), dtype=np.float64)
    tmpl = dict(TEMPLATE)
    # Веки: открытость меняет только их расстояние.
    for upper, lower, sign in ((fp.R_UPPER, fp.R_LOWER, -1),
                               (fp.L_UPPER, fp.L_LOWER, 1)):
        cx = 30.0 * sign
        tmpl[upper] = (cx, -5.0 * head.lid, 0.0)
        tmpl[lower] = (cx, 5.0 * head.lid, 0.0)
    for centre, ring, sign in ((fp.R_IRIS, fp.R_IRIS_RING, -1),
                               (fp.L_IRIS, fp.L_IRIS_RING, 1)):
        ix = 30.0 * sign + GAZE_X_MM * head.gaze_x
        iy = GAZE_Y_MM * head.gaze_y
        tmpl[centre] = (ix, iy, -1.0)
        for k, idx in enumerate(ring):
            a = math.pi / 2 * k
            tmpl[idx] = (ix + IRIS_R * math.cos(a), iy + IRIS_R * math.sin(a), -1.0)
    rot = rotation(head.yaw, head.pitch, head.roll)
    origin = np.array([head.cx * width, head.cy * height, 0.0])
    filler = np.array(tmpl[fp.NOSE_TIP])
    for i in range(N_LANDMARKS):
        p = np.array(tmpl.get(i, filler))
        q = rot @ p * head.px_per_mm + origin
        pts[i] = (q[0] / width, q[1] / height, q[2] / width)
    m = np.eye(4)
    m[:3, :3] = rot
    m[:3, 3] = (0.0, 0.0, -60.0)
    shapes = {name: 0.0 for name in fp.EYE_BLENDSHAPES}
    shapes["eyeBlinkLeft"] = head.blink_score
    shapes["eyeBlinkRight"] = head.blink_score
    return Face(landmarks=pts, matrix=m, blendshapes=shapes)
