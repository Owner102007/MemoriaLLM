"""Синтетика для тестов и для `--source synthetic`.

Параметрическая голова: шаблон нужных ориентиров в миллиметрах,
поворот (yaw, pitch, roll), сдвиг и масштаб в кадре, взгляд —
сдвиг радужек внутри глаз. По ней признаки проверяются без камеры и без
модели: известно, куда смотрит «человек», и известно, как он сидит.

Система шаблона — как у снимка: x вправо по снимку, y вниз, z от камеры.
Правый глаз человека лежит слева на снимке (x < 0).

Матрица позы — как у MediaPipe (BUG-60): камерная система OpenGL (x
вправо по снимку, y вверх, z к камере — лицо на отрицательном z), поэтому
её yaw и roll по знаку обратны повороту шаблона, а pitch тот же. Сверено
на кадрах владельца: у настоящей модели положительный yaw уводит кончик
носа вправо по снимку, положительный pitch — вниз, положительный roll
поднимает правый на снимке уголок глаза (голова к правому плечу
человека).
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

# Камера синтетического участника (BUG-60): фокус — доля ширины кадра
# (на 1080p — 1200 пикс., на 60 см лицо в масштабе 2 пикс./мм), камера —
# над серединой экрана, на столько выше его верхнего края. Так же
# считает спутник (`calib.HeadSetup`).
CAMERA_F_SHARE = 0.625
CAMERA_ABOVE_MM = 8.0

# Из системы снимка (x вправо, y вниз, z от камеры) в систему MediaPipe
# (x вправо, y вверх, z к камере): поворот на 180° вокруг x.
_TO_MP = np.diag([1.0, -1.0, -1.0])
# Из системы снимка в систему человека (x — его право, то есть влево по
# снимку; y вниз; z от него к экрану): поворот на 180° вокруг y.
_TO_PERSON = np.diag([-1.0, 1.0, -1.0])


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
    # Где глаза, если задано (BUG-60): (x, y, z) в мм — x вправо и y вниз
    # от середины экрана, z — от глаз до экрана. Тогда место и масштаб
    # лица в кадре считаются камерой участника, а `cx`, `cy`, `px_per_mm`
    # не читаются. Ещё — высота экрана, над которым стоит камера.
    eye_mm: tuple[float, float, float] | None = None
    screen_h_mm: float = 296.0
    # Погрешности распознавания (BUG-60): ориентиры лица целиком съезжают
    # на столько пикселей (у настоящей модели уголки глаз чуть идут за
    # взглядом), поза в матрице — во столько раз меньше настоящей.
    shift_px: tuple[float, float] = (0.0, 0.0)
    pose_gain: float = 1.0


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
    cx, cy, scale = place_in_frame(head, width, height)
    origin = np.array([cx * width + head.shift_px[0],
                       cy * height + head.shift_px[1], 0.0])
    q = tmpl @ rot.T * scale + origin
    pts = q / np.array([width, height, width], dtype=np.float64)
    g = head.pose_gain
    pose = rot if g == 1.0 else rotation(head.yaw * g, head.pitch * g, head.roll * g)
    m = np.eye(4)
    m[:3, :3] = _TO_MP @ pose @ _TO_MP
    m[:3, 3] = (0.0, 0.0, -60.0)
    shapes = {name: 0.0 for name in fp.EYE_BLENDSHAPES}
    shapes["eyeBlinkLeft"] = head.blink_score
    shapes["eyeBlinkRight"] = head.blink_score
    return Face(landmarks=pts, matrix=m, blendshapes=shapes)


def place_in_frame(head: Head, width: int, height: int) -> tuple[float, float, float]:
    """Где середина глаз в кадре (доли ширины и высоты) и масштаб лица
    (пикс./мм): из `eye_mm` камерой участника или как задано."""
    if head.eye_mm is None:
        return head.cx, head.cy, head.px_per_mm
    ex, ey, z = head.eye_mm
    f = CAMERA_F_SHARE * width
    cam_y = -head.screen_h_mm / 2 - CAMERA_ABOVE_MM
    # Камера смотрит на человека: его право — влево по снимку.
    u = width / 2 + f * (-ex) / z
    v = height / 2 + f * (ey - cam_y) / z
    return u / width, v / height, f / z


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


def look_from(x_mm: float, y_mm: float, eye: tuple[float, float, float], *,
              screen_h_mm: float, yaw: float = 0.0, pitch: float = 0.0,
              roll: float = 0.0, noise: tuple[float, float] = (0.0, 0.0),
              **head) -> Head:
    """Голова, глаза которой смотрят в точку экрана (`x_mm`, `y_mm` от его
    середины, y вниз) из места `eye` (мм: x, y от середины экрана, z — до
    экрана), — точно, без малых углов (BUG-60). Голова повёрнута на `yaw`,
    `pitch`, `roll` (как у `Head`); глаз в голове смотрит туда, куда
    остаётся. `noise` — ошибка взгляда в градусах по осям."""
    ex, ey, z = eye
    g = np.array([x_mm - ex, y_mm - ey, z], dtype=np.float64)
    r_person = _TO_PERSON @ rotation(yaw, pitch, roll) @ _TO_PERSON
    e = r_person.T @ g
    ax = math.degrees(math.atan2(e[0], e[2])) + noise[0]
    ay = math.degrees(math.atan2(e[1], e[2])) + noise[1]
    return Head(yaw=yaw, pitch=pitch, roll=roll,
                gaze_x=ax / EYE_RANGE_X_DEG, gaze_y=ay / EYE_RANGE_Y_DEG,
                eye_mm=(ex, ey, z), screen_h_mm=screen_h_mm, **head)


# Голова во время фазы движения (BUG-60): первые 6 с — влево-вправо,
# следующие 6 с — вверх-вниз, по периоду в 3 с.
HEAD_SWEEP_YAW = 9.0
HEAD_SWEEP_PITCH = 7.0
HEAD_SWEEP_PERIOD_S = 3.0


def head_sweep(seconds: float) -> tuple[float, float]:
    """Поворот головы (yaw, pitch) через `seconds` после начала фазы
    движения головы."""
    w = 2 * math.pi * seconds / HEAD_SWEEP_PERIOD_S
    if seconds < 6.0:
        return HEAD_SWEEP_YAW * math.sin(w), 0.0
    return 0.0, HEAD_SWEEP_PITCH * math.sin(w)


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

    def sweep(self, qpc_us: int) -> tuple[float, float]:
        """Поворот головы сверх покачивания: в фазе движения головы
        участник честно водит головой, глядя на точку (BUG-60)."""
        with self._lock:
            current = None
            for t in self.targets:
                if t.qpc_us <= qpc_us:
                    current = t
        if current is None or current.phase != "head":
            return 0.0, 0.0
        return head_sweep((qpc_us - current.qpc_us) / 1e6)

    def head(self, sec: float) -> Head:
        from . import clock

        seen = clock.qpc_us() - int(self.latency_ms * 1000)
        screen = self.screen
        yaw = 1.5 * math.sin(sec * 0.31)
        pitch = 1.0 * math.sin(sec * 0.23)
        if screen is None:
            return Head(yaw=yaw, pitch=pitch)
        sy, sp = self.sweep(seen)
        point = self.where(seen)
        x_mm, y_mm = screen.mm(*point) if point else (0.0, 0.0)
        noise = tuple(self._rng.normal(0.0, self.noise_deg, 2)) if self.noise_deg else (0.0, 0.0)
        return look_from(x_mm, y_mm, (0.0, -60.0, screen.distance_mm),
                         screen_h_mm=screen.h_mm, yaw=yaw + sy, pitch=pitch + sp,
                         noise=noise)


PARTICIPANT = Participant()
