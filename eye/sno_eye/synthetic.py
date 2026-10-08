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


def _base_points() -> np.ndarray:
    """Шаблон всех 478 точек: заданные — на месте, остальные — на кончике
    носа (их признаки не читают)."""
    filler = TEMPLATE[fp.NOSE_TIP]
    return np.array([TEMPLATE.get(i, filler) for i in range(N_LANDMARKS)],
                    dtype=np.float64)


_BASE = _base_points()


def render(head: Head, width: int, height: int) -> Face:
    """Ориентиры головы `head` на кадре `width` × `height`."""
    tmpl = _BASE.copy()
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
    q = tmpl @ rot.T * head.px_per_mm + origin
    pts = q / np.array([width, height, width], dtype=np.float64)
    m = np.eye(4)
    m[:3, :3] = rot
    m[:3, 3] = (0.0, 0.0, -60.0)
    shapes = {name: 0.0 for name in fp.EYE_BLENDSHAPES}
    shapes["eyeBlinkLeft"] = head.blink_score
    shapes["eyeBlinkRight"] = head.blink_score
    return Face(landmarks=pts, matrix=m, blendshapes=shapes)


# --- синтетический участник калибровки (SNO-ALG-EYE-02) -----------------

# Взгляд глаза в голове: `gaze_x = 1` — 30° вбок, `gaze_y = 1` — 20° вниз.
EYE_RANGE_X_DEG = 30.0
EYE_RANGE_Y_DEG = 20.0


def look_at(x_mm: float, y_mm: float, distance_mm: float, *, yaw: float = 0.0,
            pitch: float = 0.0, noise: tuple[float, float] = (0.0, 0.0),
            **head) -> Head:
    """Голова, глаза которой смотрят в точку экрана (`x_mm`, `y_mm` от его
    середины, y вниз) с расстояния `distance_mm`. Голова повёрнута на `yaw`
    и `pitch` — глаз в голове поворачивается на столько же меньше;
    `noise` — ошибка взгляда в градусах по осям."""
    ax = math.degrees(math.atan2(x_mm, distance_mm)) + noise[0]
    ay = math.degrees(math.atan2(y_mm, distance_mm)) + noise[1]
    return Head(yaw=yaw, pitch=pitch,
                gaze_x=(ax - yaw) / EYE_RANGE_X_DEG,
                gaze_y=(ay - pitch) / EYE_RANGE_Y_DEG, **head)


class Participant:
    """Участник, который смотрит на точки калибровки: на последнюю
    показанную, а за движущейся — следит. Вариант источника `follow`.

    Экран и расстояние приходят из `open`, точки — из `target` (их передаёт
    `Runtime`). Камера отстаёт на `latency_ms`: в кадре, снятом сейчас,
    глаза смотрят туда, где точка была `latency_ms` назад. Взгляд дрожит
    на `noise_deg` (нормальный шум на каждый кадр), голова слегка
    покачивается. Без экрана или без точки участник смотрит в середину.
    """

    def __init__(self, latency_ms: float | None = None, noise_deg: float | None = None,
                 seed: int = 7):
        import os
        import threading

        self.latency_ms = float(os.environ.get("SNO_EYE_SYNTH_LATENCY_MS", "70")
                                if latency_ms is None else latency_ms)
        self.noise_deg = float(os.environ.get("SNO_EYE_SYNTH_NOISE_DEG", "0.3")
                               if noise_deg is None else noise_deg)
        self._lock = threading.Lock()
        self._rng = np.random.default_rng(seed)
        self.screen = None      # calib.Screen
        self.targets: list = []  # calib.Target по времени

    def set_screen(self, screen) -> None:
        with self._lock:
            self.screen = screen
            self.targets = []

    def target(self, ev) -> None:
        with self._lock:
            self.targets.append(ev)

    def where(self, qpc_us: int) -> tuple[float, float] | None:
        """Куда смотрит участник в миг `qpc_us`: точка окна или `None`
        (середина экрана)."""
        from .calib import path_at

        with self._lock:
            current = None
            for t in self.targets:
                if t.qpc_us <= qpc_us:
                    current = t
                else:
                    break
        if current is None or current.phase == "off":
            return None
        if current.phase == "pursuit" and current.path:
            return path_at(current.path, (qpc_us - current.qpc_us) / 1e6)
        return current.x, current.y

    def head(self, sec: float) -> Head:
        from . import clock

        seen = clock.qpc_us() - int(self.latency_ms * 1000)
        screen = self.screen
        yaw = 1.5 * math.sin(sec * 0.31)
        pitch = 1.0 * math.sin(sec * 0.23)
        if screen is None:
            return Head(yaw=yaw, pitch=pitch)
        point = self.where(seen)
        x_mm, y_mm = screen.mm(*point) if point else (0.0, 0.0)
        noise = tuple(self._rng.normal(0.0, self.noise_deg, 2)) if self.noise_deg else (0.0, 0.0)
        return look_at(x_mm, y_mm, screen.distance_mm, yaw=yaw, pitch=pitch, noise=noise)


PARTICIPANT = Participant()
