"""Калибровка, проверка и приём (SNO-ALG-EYE-02).

Отображение «признаки ступени 0 → точка экрана» своё у каждого человека,
камеры, монитора и посадки: его строят заново в начале каждой записи и
меряют, насколько ему можно верить.

Точки рисует приложение и сообщает спутнику, где и когда точка
действительно появилась (`target`); спутник только копит кадры и
считает. Здесь — чистая часть: выборки точки, две модели и выбор между
ними перекрёстной проверкой «без одной точки», задержка камеры по
слежению, проверка в градусах и сантиметрах, приём по порогам и
сглаживание живой точки. Потоков и камеры здесь нет: правило
проверяется на синтетическом участнике (`synthetic.Participant`).

Координаты — логические пиксели окна приложения: окно стоит на весь
монитор места записи, и перевод в миллиметры — одно умножение
(`Screen`).
"""

from __future__ import annotations

import math
import threading
from collections import deque
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from . import faceparts as fp

SCHEMA = "sno2026-eyecal/1"

# Признаки, на которых учится модель: радужки, веки, поза и место лица.
# Диаметр радужки шумит и почти не меняется со взглядом — его нет.
USED = ("r_u", "r_v", "l_u", "l_v", "open_r", "open_l",
        "yaw", "pitch", "roll", "face_x", "face_y", "scale_px")
USED_IDX = [fp.FEATURE_NAMES.index(n) for n in USED]
# Первые шесть — глаза, остальные — голова. Нелинейно модели гнутся
# только по глазам: по позе и месту головы — линейно. Голова за сорок
# минут уходит из того положения, в каком её калибровали, и модель второй
# степени (или ядро) по позе уводила бы взгляд за экран; линейная
# поправка продолжается правильно.
N_EYE = 6
SCALE_IDX = fp.FEATURE_NAMES.index("scale_px")

PHASES = ("calib", "pursuit", "validate", "off")

# Сетки подбора: сила регуляризации и ширина ядра.
RIDGE_ALPHAS = (1e-3, 1e-2, 1e-1, 1.0, 10.0, 100.0)
KRR_GAMMAS = (0.01, 0.03, 0.1, 0.3)
KRR_ALPHAS = (1e-3, 1e-2, 1e-1, 1.0)
# Ядру — не больше стольких выборок: подбор идёт за секунды и на
# слабом ПК.
KRR_MAX_SAMPLES = 320
POINT_SAMPLES_CAP = 20

# Буфер кадров: пять минут при 30 к/с — калибровке и проверке хватает.
BUFFER_FRAMES = 9000


class CalibrationError(Exception):
    """Посчитать нечего: выборок мало, лица нет, экран неизвестен."""

    def __init__(self, code: str, text: str):
        super().__init__(text)
        self.code = code
        self.text = text


# --- экран ---------------------------------------------------------------

@dataclass
class Screen:
    """Окно приложения: размер в логических пикселях и в миллиметрах,
    расстояние от глаз до экрана."""

    w: float
    h: float
    w_mm: float
    h_mm: float
    distance_mm: float

    @staticmethod
    def from_open(screen: Any, distance: Any) -> "Screen | None":
        """Экран из полей `open`; `None` — их нет или они не числа."""
        if not isinstance(screen, dict):
            return None
        try:
            w = float(screen["w"])
            h = float(screen["h"])
            w_mm = float(screen["w_mm"])
            h_mm = float(screen["h_mm"])
            d = float(distance)
        except (KeyError, TypeError, ValueError):
            return None
        if min(w, h, w_mm, h_mm, d) <= 0:
            return None
        return Screen(w, h, w_mm, h_mm, d)

    def mm(self, x: float, y: float) -> tuple[float, float]:
        """Точка окна → миллиметры от середины экрана (x вправо, y вниз)."""
        return ((x - self.w / 2) * self.w_mm / self.w,
                (y - self.h / 2) * self.h_mm / self.h)

    def mm_between(self, a, b) -> float:
        ax, ay = self.mm(*a)
        bx, by = self.mm(*b)
        return math.hypot(ax - bx, ay - by)

    def angle_deg(self, a, b, distance_mm: float | None = None) -> float:
        """Угол между лучами от глаза к точкам окна `a` и `b`. Глаз — напротив
        середины экрана на расстоянии места записи (или `distance_mm`)."""
        d = distance_mm or self.distance_mm
        ax, ay = self.mm(*a)
        bx, by = self.mm(*b)
        va = np.array([ax, ay, d])
        vb = np.array([bx, by, d])
        c = float(va @ vb / (np.linalg.norm(va) * np.linalg.norm(vb)))
        return math.degrees(math.acos(max(-1.0, min(1.0, c))))

    def as_dict(self) -> dict:
        return {"w": self.w, "h": self.h, "w_mm": self.w_mm, "h_mm": self.h_mm,
                "distance_mm": self.distance_mm}


# --- путь движущейся точки ----------------------------------------------

def path_at(path: dict, seconds: float) -> tuple[float, float]:
    """Место точки слежения через `seconds` после её появления.

    Фигура Лиссажу: `x = cx + ax·sin(2πt/Tx)`, `y = cy + ay·sin(2πt/Ty)`;
    размах и периоды выбирает приложение по месту записи так, чтобы точка
    не шла быстрее 10°/с.
    """
    tx = float(path["tx_ms"]) / 1000.0
    ty = float(path["ty_ms"]) / 1000.0
    return (float(path["cx"]) + float(path["ax"]) * math.sin(2 * math.pi * seconds / tx),
            float(path["cy"]) + float(path["ay"]) * math.sin(2 * math.pi * seconds / ty))


def check_path(path: Any) -> dict:
    if not isinstance(path, dict):
        raise ValueError("«path» — объект {cx, cy, ax, ay, tx_ms, ty_ms}")
    for key in ("cx", "cy", "ax", "ay", "tx_ms", "ty_ms"):
        v = path.get(key)
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            raise ValueError(f"«path.{key}» — не число")
    if path["tx_ms"] <= 0 or path["ty_ms"] <= 0:
        raise ValueError("периоды пути — больше нуля")
    return dict(path)


# --- события и выборки --------------------------------------------------

@dataclass
class Target:
    """Точка появилась (или исчезла: `phase == "off"`)."""

    id: str
    x: float
    y: float
    phase: str
    qpc_us: int
    path: dict | None = None


@dataclass
class Sample:
    qpc_us: int
    feat: np.ndarray | None   # полный вектор признаков кадра
    ok: bool                  # лицо есть, голова не отвёрнута, не моргание


def target_from_command(cmd: dict) -> Target:
    """Команда `target` → событие; не то — `ValueError` со словами."""
    phase = cmd.get("phase")
    if phase not in PHASES:
        raise ValueError(f"«phase» — одно из {', '.join(PHASES)}")
    q = cmd.get("qpc_us")
    if isinstance(q, bool) or not isinstance(q, int):
        raise ValueError("«qpc_us» — целое число микросекунд")
    if phase == "off":
        return Target(str(cmd.get("id") or "off"), 0.0, 0.0, "off", q)
    tid = cmd.get("id")
    if not isinstance(tid, (str, int)) or isinstance(tid, bool):
        raise ValueError("«id» — имя точки")
    x, y = cmd.get("x"), cmd.get("y")
    for name, v in (("x", x), ("y", y)):
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            raise ValueError(f"«{name}» — не число")
    path = check_path(cmd.get("path")) if phase == "pursuit" else None
    return Target(str(tid), float(x), float(y), phase, q, path)


def windows(targets: list[Target], phase: str, drop_us: int) -> dict[str, list[tuple[int, int]]]:
    """Отрезки времени, в которые точка фазы `phase` стояла на экране, без
    первых `drop_us` (переход взгляда и задержка). Точка, показанная
    второй раз, получает второй отрезок. Конец отрезка — появление
    следующей точки или `off`; последней точке без конца отрезка нет."""
    out: dict[str, list[tuple[int, int]]] = {}
    for k, t in enumerate(targets):
        if t.phase != phase:
            continue
        if k + 1 >= len(targets):
            continue
        start = t.qpc_us + drop_us
        end = targets[k + 1].qpc_us
        if end > start:
            out.setdefault(t.id, []).append((start, end))
    return out


def robust_keep(feats: np.ndarray, k: float) -> np.ndarray:
    """Маска выборок точки без выбросов: признак дальше `k` MAD от медианы
    по любому из используемых признаков — выброс."""
    if len(feats) < 3:
        return np.ones(len(feats), dtype=bool)
    x = feats[:, USED_IDX].astype(np.float64)
    med = np.median(x, axis=0)
    mad = 1.4826 * np.median(np.abs(x - med), axis=0)
    mad[mad < 1e-9] = np.inf
    dev = np.abs(x - med) / mad
    return np.all(dev <= k, axis=1)


# --- модели ----------------------------------------------------------------

def _poly2(z: np.ndarray) -> np.ndarray:
    n, d = z.shape
    iu = np.triu_indices(d)
    return np.concatenate([z, (z[:, :, None] * z[:, None, :])[:, iu[0], iu[1]]], axis=1)


def _design(z: np.ndarray) -> np.ndarray:
    """Признаки гребневой модели: глаза — до второй степени, голова —
    линейно."""
    return np.concatenate([_poly2(z[:, :N_EYE]), z[:, N_EYE:]], axis=1)


# Масштаб признаков головы — постоянный, а не по разбросу калибровки:
# голова за калибровку почти не двигается, и деление на её крошечный
# разброс раздуло бы случайное покачивание до веса глаз. С постоянным
# масштабом гребень штрафует модель, которая объясняет взгляд позой, а не
# глазами (поворот — на 5°, место лица — на двадцатую долю кадра, размер
# лица — на двадцатую долю от среднего).
HEAD_SCALE = (5.0, 5.0, 5.0, 0.05, 0.05, None)
HEAD_SCALE_SHARE = 0.05


@dataclass
class Norm:
    mean: np.ndarray
    std: np.ndarray

    @staticmethod
    def fit(x: np.ndarray, head_fixed: bool = True) -> "Norm":
        mean = x.mean(axis=0)
        std = x.std(axis=0)
        std[std < 1e-9] = 1.0
        if head_fixed and x.shape[1] == len(USED):
            for k, scale in enumerate(HEAD_SCALE):
                j = N_EYE + k
                std[j] = scale if scale is not None else \
                    max(1e-6, HEAD_SCALE_SHARE * abs(mean[j]))
        return Norm(mean, std)

    def apply(self, x: np.ndarray) -> np.ndarray:
        return (x - self.mean) / self.std

    def to_json(self) -> dict:
        return {"mean": self.mean.tolist(), "std": self.std.tolist()}

    @staticmethod
    def from_json(d: dict) -> "Norm":
        return Norm(np.asarray(d["mean"], dtype=np.float64),
                    np.asarray(d["std"], dtype=np.float64))


def _ridge_solve(p: np.ndarray, y: np.ndarray, alpha: float) -> np.ndarray:
    return np.linalg.solve(p.T @ p + alpha * len(p) * np.eye(p.shape[1]), p.T @ y)


class Ridge:
    """Гребневая регрессия: глаза — до второй степени, голова — линейно;
    x и y отдельно."""

    kind = "ridge"

    def __init__(self, alphas=(1.0, 1.0)):
        self.alphas = tuple(float(a) for a in alphas)
        self.norm: Norm | None = None
        self.pnorm: Norm | None = None
        self.w: np.ndarray | None = None    # (p, 2)
        self.b: np.ndarray | None = None    # (2,)

    def fit(self, x: np.ndarray, y: np.ndarray) -> "Ridge":
        self.norm = Norm.fit(x)
        phi = _design(self.norm.apply(x))
        self.pnorm = Norm.fit(phi, head_fixed=False)
        # Столбцы головы уже в постоянном масштабе (`HEAD_SCALE`) — только
        # центрируются.
        self.pnorm.std[-(len(USED) - N_EYE):] = 1.0
        p = self.pnorm.apply(phi)
        ym = y.mean(axis=0)
        w = np.zeros((p.shape[1], 2))
        for k in range(2):
            w[:, k] = _ridge_solve(p, y[:, k] - ym[k], self.alphas[k])
        self.w, self.b = w, ym
        return self

    def predict(self, x: np.ndarray) -> np.ndarray:
        p = self.pnorm.apply(_design(self.norm.apply(np.atleast_2d(x))))
        return p @ self.w + self.b

    def to_json(self) -> dict:
        return {"kind": self.kind, "alphas": list(self.alphas),
                "norm": self.norm.to_json(), "pnorm": self.pnorm.to_json(),
                "w": self.w.tolist(), "b": self.b.tolist()}

    @staticmethod
    def from_json(d: dict) -> "Ridge":
        m = Ridge(d["alphas"])
        m.norm = Norm.from_json(d["norm"])
        m.pnorm = Norm.from_json(d["pnorm"])
        m.w = np.asarray(d["w"], dtype=np.float64)
        m.b = np.asarray(d["b"], dtype=np.float64)
        return m


def _rbf(a: np.ndarray, b: np.ndarray, gamma: float) -> np.ndarray:
    d2 = (np.sum(a * a, axis=1)[:, None] + np.sum(b * b, axis=1)[None, :]
          - 2.0 * a @ b.T)
    return np.exp(-gamma * np.maximum(d2, 0.0))


# Линейная часть ядерной модели регуляризуется слабо: её дело — поза
# головы и общий наклон, а не подгонка под точки.
KRR_LINEAR_ALPHA = 1e-2


def _linear_part(z: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Линейная модель `[веса; сдвиг]`. Сдвиг не штрафуется: признаки и
    цели центрируются, и сдвиг — их средние."""
    zm = z.mean(axis=0)
    ym = y.mean(axis=0)
    w = _ridge_solve(z - zm, y - ym, KRR_LINEAR_ALPHA)
    return np.vstack([w, ym - zm @ w])


def _linear_apply(z: np.ndarray, w: np.ndarray) -> np.ndarray:
    return z @ w[:-1] + w[-1]


class Kernel:
    """Гребневая регрессия с ядром RBF по глазам поверх линейной по всем
    признакам; x и y отдельно."""

    kind = "krr"

    def __init__(self, gammas=(0.1, 0.1), alphas=(0.1, 0.1)):
        self.gammas = tuple(float(g) for g in gammas)
        self.alphas = tuple(float(a) for a in alphas)
        self.norm: Norm | None = None
        self.lin: np.ndarray | None = None  # (13, 2)
        self.z: np.ndarray | None = None    # глаза обучения
        self.c: np.ndarray | None = None    # (n, 2)

    def fit(self, x: np.ndarray, y: np.ndarray) -> "Kernel":
        self.norm = Norm.fit(x)
        z = self.norm.apply(x)
        self.lin = _linear_part(z, y)
        r = y - _linear_apply(z, self.lin)
        self.z = z[:, :N_EYE]
        c = np.zeros((len(x), 2))
        for k in range(2):
            kk = _rbf(self.z, self.z, self.gammas[k])
            c[:, k] = np.linalg.solve(kk + self.alphas[k] * len(x) * np.eye(len(x)), r[:, k])
        self.c = c
        return self

    def predict(self, x: np.ndarray) -> np.ndarray:
        z = self.norm.apply(np.atleast_2d(x))
        out = _linear_apply(z, self.lin)
        for k in range(2):
            out[:, k] += _rbf(z[:, :N_EYE], self.z, self.gammas[k]) @ self.c[:, k]
        return out

    def to_json(self) -> dict:
        return {"kind": self.kind, "gammas": list(self.gammas),
                "alphas": list(self.alphas), "norm": self.norm.to_json(),
                "lin": self.lin.tolist(), "z": self.z.tolist(), "c": self.c.tolist()}

    @staticmethod
    def from_json(d: dict) -> "Kernel":
        m = Kernel(d["gammas"], d["alphas"])
        m.norm = Norm.from_json(d["norm"])
        m.lin = np.asarray(d["lin"], dtype=np.float64)
        m.z = np.asarray(d["z"], dtype=np.float64)
        m.c = np.asarray(d["c"], dtype=np.float64)
        return m


def model_from_json(d: dict):
    return Ridge.from_json(d) if d.get("kind") == "ridge" else Kernel.from_json(d)


# --- подбор -----------------------------------------------------------------

@dataclass
class TrainSet:
    """Выборки обучения: признаки (используемые), цели, номер точки
    (`-1` — слежение: в проверке «без одной точки» не участвует)."""

    x: np.ndarray
    y: np.ndarray
    group: np.ndarray


def _loo_ridge(ts: TrainSet, groups: list[int]) -> dict:
    """Ошибка «без одной точки» по каждой оси для каждой силы
    регуляризации: медиана оценки точки против точки, пиксели."""
    errs = {a: np.zeros((len(groups), 2)) for a in RIDGE_ALPHAS}
    for gi, g in enumerate(groups):
        tr = ts.group != g
        te = ~tr
        if not te.any() or tr.sum() < 10:
            continue
        for a in RIDGE_ALPHAS:
            m = Ridge((a, a)).fit(ts.x[tr], ts.y[tr])
            pred = np.median(m.predict(ts.x[te]), axis=0)
            errs[a][gi] = pred - ts.y[te][0]
    return errs


def _loo_kernel(ts: TrainSet, groups: list[int]) -> dict:
    """То же для ядра: для каждой ширины ядра — одно разложение на точку,
    а все силы регуляризации и обе оси — из него."""
    errs = {(gm, a): np.zeros((len(groups), 2))
            for gm in KRR_GAMMAS for a in KRR_ALPHAS}
    for gi, g in enumerate(groups):
        tr = ts.group != g
        te = ~tr
        if not te.any() or tr.sum() < 10:
            continue
        norm = Norm.fit(ts.x[tr])
        ztr = norm.apply(ts.x[tr])
        zte = norm.apply(ts.x[te])
        lin = _linear_part(ztr, ts.y[tr])
        rtr = ts.y[tr] - _linear_apply(ztr, lin)
        base = _linear_apply(zte, lin)
        n = len(ztr)
        for gm in KRR_GAMMAS:
            k = _rbf(ztr[:, :N_EYE], ztr[:, :N_EYE], gm)
            lam, vec = np.linalg.eigh(k)
            kte = _rbf(zte[:, :N_EYE], ztr[:, :N_EYE], gm)
            proj = vec.T @ rtr                 # (n, 2)
            kv = kte @ vec                     # (m, n)
            for a in KRR_ALPHAS:
                coef = proj / (lam + a * n)[:, None]
                pred = np.median(base + kv @ coef, axis=0)
                errs[(gm, a)][gi] = pred - ts.y[te][0]
    return errs


def _best(errs: dict) -> tuple[Any, Any]:
    """Лучшая настройка для каждой оси по средней ошибке (по модулю;
    в ошибках хранится и знак — по нему считается угол)."""
    keys = list(errs)
    ex = [float(np.abs(errs[k][:, 0]).mean()) for k in keys]
    ey = [float(np.abs(errs[k][:, 1]).mean()) for k in keys]
    return keys[int(np.argmin(ex))], keys[int(np.argmin(ey))]


def _subsample(ts: TrainSet, cap: int, rng: np.random.Generator) -> TrainSet:
    if len(ts.x) <= cap:
        return ts
    # Точки калибровки — все (их немного), слежение — сколько влезет.
    fix = np.flatnonzero(ts.group >= 0)
    pur = np.flatnonzero(ts.group < 0)
    room = max(0, cap - len(fix))
    if len(fix) > cap:
        fix = np.sort(rng.choice(fix, cap, replace=False))
        room = 0
    pur = np.sort(rng.choice(pur, min(room, len(pur)), replace=False)) if room else pur[:0]
    keep = np.concatenate([fix, pur])
    return TrainSet(ts.x[keep], ts.y[keep], ts.group[keep])


def select_model(ts: TrainSet, screen: Screen, kinds=("ridge", "krr")) -> tuple[Any, dict]:
    """Подбор настроек и выбор модели по ошибке «без одной точки».

    Возвращает обученную на всех выборках модель и сведения: ошибку каждой
    модели в градусах (средний угол между медианой оценки точки, которую
    модель не видела, и самой точкой) и выбранную.
    """
    groups = sorted({int(g) for g in ts.group if g >= 0})
    if len(groups) < 5:
        raise CalibrationError("no_face", "Точек с выборками меньше пяти — "
                                          "калибровка не удалась")
    rng = np.random.default_rng(20261008)
    pts = {g: ts.y[ts.group == g][0] for g in groups}
    found: dict[str, dict] = {}

    def cv_deg(errs_axis: dict, kx, ky) -> float:
        angles = []
        for gi, g in enumerate(groups):
            ex, ey = errs_axis[kx][gi, 0], errs_axis[ky][gi, 1]
            t = pts[g]
            angles.append(screen.angle_deg((t[0] + ex, t[1] + ey), tuple(t)))
        return float(np.mean(angles))

    if "ridge" in kinds:
        e = _loo_ridge(ts, groups)
        ax, ay = _best(e)
        found["ridge"] = {"params": (ax, ay), "cv_deg": cv_deg(e, ax, ay)}
    if "krr" in kinds:
        small = _subsample(ts, KRR_MAX_SAMPLES, rng)
        e = _loo_kernel(small, groups)
        kx, ky = _best(e)
        found["krr"] = {"params": (kx, ky), "cv_deg": cv_deg(e, kx, ky)}
    kind = min(found, key=lambda k: found[k]["cv_deg"])
    params = found[kind]["params"]
    if kind == "ridge":
        model = Ridge((params[0], params[1])).fit(ts.x, ts.y)
    else:
        small = _subsample(ts, KRR_MAX_SAMPLES, rng)
        model = Kernel((params[0][0], params[1][0]),
                       (params[0][1], params[1][1])).fit(small.x, small.y)
    info = {"kind": kind,
            "cv_deg": {k: round(v["cv_deg"], 3) for k, v in found.items()}}
    return model, info


# --- проверка ---------------------------------------------------------------

def precision_deg(points: list[np.ndarray], screen: Screen) -> float | None:
    """Прецизионность: RMS угла между соседними выборками в пределах
    точки, по всем точкам."""
    sq = []
    for p in points:
        for a, b in zip(p[:-1], p[1:]):
            sq.append(screen.angle_deg(tuple(a), tuple(b)) ** 2)
    return math.sqrt(sum(sq) / len(sq)) if sq else None


# --- живая точка -----------------------------------------------------------

class Smoother:
    """Сглаживание живой точки для глаза — по фиксациям (SNO-F-EYE-03,
    BUG-59). В запись сглаженное не идёт.

    Взгляд — это стоянки (фиксации) и прыжки между ними (саккады), а шум
    веб-камеры — градус-два на каждом кадре. Пока новая оценка лежит в
    круге шума вокруг середины стоянки, точка стоит на среднем оценок
    стоянки за последние `window_s`: шум делится на корень из числа
    кадров. Оценка вне круга копится; когда `confirm` таких легли кучно —
    началась новая стоянка, и точка переходит сразу на их среднее.
    Одиночный выброс (сбой ориентиров) точку не двигает. Круг — `k` шумов
    по каждой оси (`noise_px` — разброс оценки на точках калибровки той же
    моделью); прошло больше `gap_s` без годных кадров — стоянка заново.
    Прыжок меньше круга ловит второе правило: среднее последних `tail`
    оценок ушло от среднего остальной стоянки дальше `k_tail` шумов
    разности средних, — новая стоянка с них. Порог у него выше, чем у
    круга: проверка идёт на каждом кадре, и ложная тревога сдёргивала бы
    точку.

    Прежний фильтр Калмана был настроен на шум в 40 пикселей; на ПК
    владельца шум втрое больше, и точка дрожала на 3–5 см.
    """

    def __init__(self, noise_px=(40.0, 40.0), window_s: float = 0.8,
                 k: float = 3.0, confirm: int = 3, gap_s: float = 0.5,
                 tail: int = 6, k_tail: float = 5.0):
        nx, ny = (noise_px, noise_px) if isinstance(noise_px, (int, float)) else noise_px
        self.noise = (max(1.0, float(nx)), max(1.0, float(ny)))
        self.window = int(window_s * 1e6)
        self.k = k
        self.confirm = confirm
        self.gap = int(gap_s * 1e6)
        self.tail = tail
        self.k_tail = k_tail
        self.fix: deque[tuple[int, float, float]] = deque()
        self.cand: list[tuple[int, float, float]] = []
        self.t: int | None = None

    @staticmethod
    def _mean(pts) -> tuple[float, float]:
        n = len(pts)
        return (sum(p[1] for p in pts) / n, sum(p[2] for p in pts) / n)

    def _inside(self, a: tuple[float, float], x: float, y: float,
                n: float = 1, k: float | None = None) -> bool:
        dx = (x - a[0]) / self.noise[0]
        dy = (y - a[1]) / self.noise[1]
        k = self.k if k is None else k
        return (dx * dx + dy * dy) * n <= k * k

    def push(self, qpc_us: int, gx: float, gy: float) -> tuple[float, float]:
        if self.t is None or qpc_us - self.t > self.gap or not self.fix:
            self.fix = deque([(qpc_us, gx, gy)])
            self.cand = []
        elif self._inside(self._mean(self.fix), gx, gy):
            self.fix.append((qpc_us, gx, gy))
            self.cand = []
            n = self.tail
            if len(self.fix) >= 2 * n:
                pts = list(self.fix)
                head, last = pts[:-n], pts[-n:]
                lx, ly = self._mean(last)
                # Шум разности двух средних — из шума обоих.
                m = len(head) * n / (len(head) + n)
                if not self._inside(self._mean(head), lx, ly, m, self.k_tail):
                    self.fix = deque(last)
        else:
            self.cand.append((qpc_us, gx, gy))
            if len(self.cand) >= self.confirm:
                c = self._mean(self.cand)
                if all(self._inside(c, x, y) for _, x, y in self.cand):
                    self.fix = deque(self.cand)
                    self.cand = []
                else:
                    self.cand.pop(0)
        self.t = qpc_us
        while len(self.fix) > 1 and qpc_us - self.fix[0][0] > self.window:
            self.fix.popleft()
        return self._mean(self.fix)

    @property
    def held(self) -> tuple[float, float] | None:
        """Где точка стоит сейчас (для кадров без взгляда)."""
        return self._mean(self.fix) if self.fix else None


# --- калибровка целиком -------------------------------------------------------

@dataclass
class Attempt:
    n: int
    kind: str                      # full — как у участника; quick — 9 точек
    targets: list[Target] = field(default_factory=list)
    started_us: int | None = None
    fit: dict | None = None
    validation: dict | None = None


class Calibration:
    """Калибровка одной сессии спутника: кадры, точки, попытки, модель.

    Кадры приходят из потока распознавания (`add`), точки и команды — из
    потока команд; один замок на буфер.
    """

    def __init__(self, screen: Screen | None, thresholds: dict):
        self.screen = screen
        self.t = dict(thresholds.get("calibration", {}))
        self._lock = threading.Lock()
        self._frames: deque[Sample] = deque(maxlen=BUFFER_FRAMES)
        self.attempts: list[Attempt] = []
        self.model = None
        self.noise_px: tuple[float, float] = (40.0, 40.0)
        self.model_info: dict | None = None
        self.scale_ref: float | None = None

    # кадры
    def add(self, qpc_us: int, feat: np.ndarray | None, ok: bool) -> None:
        with self._lock:
            self._frames.append(Sample(int(qpc_us), feat, bool(ok)))

    def _frames_between(self, start: int, end: int) -> list[Sample]:
        with self._lock:
            return [s for s in self._frames if start <= s.qpc_us < end]

    # попытки
    @property
    def attempt(self) -> Attempt | None:
        return self.attempts[-1] if self.attempts else None

    def begin(self, n: int, kind: str, now_us: int) -> Attempt:
        if self.screen is None:
            raise CalibrationError("bad_command", "Нет размеров экрана: "
                                                  "их называет команда open")
        if kind not in ("full", "quick"):
            raise CalibrationError("bad_command", "«kind» — full или quick")
        a = Attempt(n=n, kind=kind, started_us=now_us)
        self.attempts.append(a)
        return a

    def target(self, ev: Target) -> None:
        a = self.attempt
        if a is None:
            raise CalibrationError("bad_command", "Точка до начала калибровки")
        if a.targets and ev.qpc_us < a.targets[-1].qpc_us:
            raise CalibrationError("bad_command", "Точка раньше предыдущей")
        a.targets.append(ev)

    # выборки точек калибровки
    def _point_samples(self, a: Attempt, phase: str) -> dict[str, dict]:
        drop = int(float(self.t.get("drop_s", 0.5)) * 1e6)
        k = float(self.t.get("mad_k", 3.0))
        by_id = {t.id: t for t in a.targets if t.phase == phase}
        out: dict[str, dict] = {}
        for tid, spans in windows(a.targets, phase, drop).items():
            frames: list[Sample] = []
            for s, e in spans:
                frames += self._frames_between(s, e)
            good = [f for f in frames if f.ok and f.feat is not None]
            feats = np.array([f.feat for f in good], dtype=np.float64) \
                if good else np.zeros((0, len(fp.FEATURE_NAMES)))
            keep = robust_keep(feats, k) if len(feats) else np.zeros(0, dtype=bool)
            t = by_id[tid]
            out[tid] = {"x": t.x, "y": t.y, "frames": len(frames),
                        "good": len(good), "used": int(keep.sum()),
                        "feats": feats[keep],
                        "qpc": np.array([f.qpc_us for f in good])[keep]
                        if len(good) else np.zeros(0)}
        return out

    def samples(self, phase: str = "calib") -> dict:
        """Сколько годных кадров набрала каждая точка фазы и какую долю
        времени лицо было в кадре. Точка без `min_samples` — повторить."""
        a = self.attempt
        if a is None:
            raise CalibrationError("bad_command", "Калибровка не начата")
        pts = self._point_samples(a, phase)
        need = int(self.t.get("min_samples", 15))
        counts = {tid: p["used"] for tid, p in pts.items()}
        frames = sum(p["frames"] for p in pts.values())
        good = sum(p["good"] for p in pts.values())
        face = self._face_share(a, phase)
        return {"phase": phase, "counts": counts,
                "short": [tid for tid, n in counts.items() if n < need],
                "face": round(face, 3) if face is not None else None,
                "frames": frames, "good": good}

    def _face_share(self, a: Attempt, phase: str) -> float | None:
        spans = [(t.qpc_us, a.targets[k + 1].qpc_us)
                 for k, t in enumerate(a.targets[:-1]) if t.phase == phase]
        frames: list[Sample] = []
        for s, e in spans:
            frames += self._frames_between(s, e)
        if not frames:
            return None
        return sum(1 for f in frames if f.feat is not None) / len(frames)

    # слежение
    def _pursuit(self, a: Attempt) -> list[tuple[Sample, Target]]:
        drop = int(float(self.t.get("pursuit_drop_s", 1.0)) * 1e6)
        out = []
        for k, t in enumerate(a.targets[:-1]):
            if t.phase != "pursuit" or t.path is None:
                continue
            end = a.targets[k + 1].qpc_us
            for s in self._frames_between(t.qpc_us + drop, end):
                if s.ok and s.feat is not None:
                    out.append((s, t))
        return out

    def fit(self) -> dict:
        """Модель попытки: точки калибровки (и слежение у полной), задержка
        камеры, ошибка «без одной точки». Точка без годных выборок
        исключается и названа."""
        a = self.attempt
        if a is None:
            raise CalibrationError("bad_command", "Калибровка не начата")
        screen = self.screen
        face = self._face_share(a, "calib")
        if face is not None and face < float(self.t.get("face_min", 0.5)):
            raise CalibrationError("no_face", "Камера не видит лица")
        pts = self._point_samples(a, "calib")
        need = int(self.t.get("min_samples", 15))
        used = {tid: p for tid, p in pts.items() if p["used"] >= max(3, need // 3)}
        excluded = sorted(tid for tid in pts if tid not in used)
        if len(used) < 5:
            raise CalibrationError("no_face", "Камера почти не видела глаз: "
                                              "калибровка не удалась")
        rng = np.random.default_rng(a.n)
        xs, ys, gs = [], [], []
        names = sorted(used)
        for gi, tid in enumerate(names):
            p = used[tid]
            f = p["feats"]
            if len(f) > POINT_SAMPLES_CAP:
                f = f[np.sort(rng.choice(len(f), POINT_SAMPLES_CAP, replace=False))]
            xs.append(f[:, USED_IDX])
            ys.append(np.tile([p["x"], p["y"]], (len(f), 1)))
            gs.append(np.full(len(f), gi))
        fix = TrainSet(np.concatenate(xs), np.concatenate(ys).astype(np.float64),
                       np.concatenate(gs))
        all_feats = np.concatenate([used[t]["feats"] for t in names])
        self.scale_ref = float(np.median(all_feats[:, SCALE_IDX]))

        latency_ms = None
        pursuit_n = 0
        ts = fix
        if a.kind == "full":
            pur = self._pursuit(a)
            pursuit_n = len(pur)
            if len(pur) >= 60:
                latency_ms = self._latency(fix, pur)
                lat_us = int(latency_ms * 1000)
                px = np.array([s.feat[USED_IDX] for s, _ in pur], dtype=np.float64)
                py = np.array([path_at(t.path, (s.qpc_us - lat_us - t.qpc_us) / 1e6)
                               for s, t in pur])
                ts = TrainSet(np.concatenate([fix.x, px]), np.concatenate([fix.y, py]),
                              np.concatenate([fix.group, np.full(len(px), -1)]))
        kinds = ("ridge", "krr") if a.kind == "full" else ("ridge",)
        model, info = select_model(ts, screen, kinds=kinds)
        self.model = model
        self.model_info = info
        self.noise_px = self._noise(model, used)
        cv = info["cv_deg"][info["kind"]]
        a.fit = {
            "model": info["kind"], "cv_deg": cv, "cv_by_model": info["cv_deg"],
            "cv_cm": round(math.tan(math.radians(cv)) * screen.distance_mm / 10, 2),
            "latency_ms": latency_ms, "points": len(used), "excluded": excluded,
            "samples": int(len(fix.x)), "pursuit": pursuit_n,
            "counts": {tid: p["used"] for tid, p in pts.items()},
            "face": round(face, 3) if face is not None else None,
            "noise_px": [round(v, 1) for v in self.noise_px],
            "noise_deg": round(self._noise_deg(self.noise_px), 3),
        }
        return dict(a.fit)

    @staticmethod
    def _noise(model, used: dict) -> tuple[float, float]:
        """Шум оценки по каждой оси, пиксели: разброс оценки внутри точки
        калибровки (человек смотрит в одно место), среднеквадратично по
        точкам. По нему живая точка решает, что дрожь, а что прыжок взгляда
        (BUG-59)."""
        var = []
        for p in used.values():
            if len(p["feats"]) >= 3:
                var.append(model.predict(p["feats"][:, USED_IDX]).var(axis=0))
        if not var:
            return (40.0, 40.0)
        v = np.sqrt(np.mean(var, axis=0))
        return (float(v[0]), float(v[1]))

    def _noise_deg(self, noise_px: tuple[float, float]) -> float:
        """Шум в градусах у середины экрана: средний по осям."""
        sc = self.screen
        c = (sc.w / 2, sc.h / 2)
        n = math.sqrt((noise_px[0] ** 2 + noise_px[1] ** 2) / 2)
        return sc.angle_deg(c, (c[0] + n, c[1]))

    def _latency(self, fix: TrainSet, pur: list[tuple[Sample, Target]]) -> float:
        """Задержка камеры: сдвиг 0–200 мс, при котором оценка взгляда на
        слежении лучше всего ложится на путь точки.

        Оценка — линейная модель по неподвижным точкам: она грубее, зато не
        раздувает дрожь взгляда, как модель второй степени на кадрах, которых
        не видела. Дрожь гасится скользящим средним по семи соседним кадрам —
        симметричным, чтобы не сдвигать время. Свой перекос, зависящий от
        места на экране, у оценки есть; чтобы он не тянул сдвиг в сторону,
        при каждом сдвиге оценка сначала подгоняется к пути аффинным
        преобразованием и сравнивается остаток: перекос преобразование
        съедает, а запаздывание — нет.
        """
        step = int(self.t.get("latency_step_ms", 5))
        top = int(self.t.get("latency_max_ms", 200))
        # Масштаб — по разбросу калибровки, и голова тоже: здесь важно
        # объяснить покачивание головы внутри калибровки, а не уйти от неё.
        norm = Norm.fit(fix.x, head_fixed=False)
        lin = _linear_part(norm.apply(fix.x), fix.y)
        x = np.array([s.feat[USED_IDX] for s, _ in pur], dtype=np.float64)
        raw = _linear_apply(norm.apply(x), lin)
        half = 3
        pred = np.array([raw[max(0, i - half):i + half + 1].mean(axis=0)
                         for i in range(len(raw))])
        a = np.column_stack([pred, np.ones(len(pred))])
        best, best_err = 0, math.inf
        for lat in range(0, top + 1, step):
            tgt = np.array([path_at(t.path, (s.qpc_us - lat * 1000 - t.qpc_us) / 1e6)
                            for s, t in pur])
            coef, *_ = np.linalg.lstsq(a, tgt, rcond=None)
            err = float(np.sqrt(np.mean(np.sum((a @ coef - tgt) ** 2, axis=1))))
            if err < best_err:
                best, best_err = lat, err
        return float(best)

    def predict(self, feat: np.ndarray) -> tuple[float, float] | None:
        if self.model is None:
            return None
        g = self.model.predict(np.asarray(feat, dtype=np.float64)[USED_IDX])[0]
        return float(g[0]), float(g[1])

    def distance_for(self, scale: float | None) -> float:
        """Расстояние до экрана с поправкой на относительное расстояние кадра:
        лицо крупнее, чем при калибровке, — человек ближе."""
        d = self.screen.distance_mm
        if scale and self.scale_ref:
            return d * self.scale_ref / scale
        return d

    def validate(self) -> dict:
        """Проверка: точки фазы `validate` той же моделью. Точность — средний
        угол между медианой оценки точки и точкой; прецизионность — RMS угла
        между соседними выборками; худшая точка. Приём — по порогам."""
        a = self.attempt
        if a is None or self.model is None:
            raise CalibrationError("bad_command", "Проверке нужна модель: "
                                                  "сначала fit")
        screen = self.screen
        pts = self._point_samples(a, "validate")
        need = int(self.t.get("min_valid", 10))
        rows, preds_by_point, excluded = [], [], []
        for tid in sorted(pts, key=lambda s: (len(s), s)):
            p = pts[tid]
            if p["used"] < need:
                excluded.append(tid)
                continue
            pred = self.model.predict(p["feats"][:, USED_IDX])
            med = np.median(pred, axis=0)
            dist = self.distance_for(float(np.median(p["feats"][:, SCALE_IDX])))
            err = screen.angle_deg(tuple(med), (p["x"], p["y"]), dist)
            err_mm = screen.mm_between(tuple(med), (p["x"], p["y"]))
            rows.append({"id": tid, "x": p["x"], "y": p["y"],
                         "gx": round(float(med[0]), 1), "gy": round(float(med[1]), 1),
                         "err_deg": round(err, 3), "err_mm": round(err_mm, 1),
                         "n": p["used"]})
            preds_by_point.append(pred)
        accept = float(self.t.get("accept_deg", 2.5))
        worst_max = float(self.t.get("worst_deg", 5.0))
        min_points = int(self.t.get("min_points", 6))
        if rows:
            acc = float(np.mean([r["err_deg"] for r in rows]))
            acc_mm = float(np.mean([r["err_mm"] for r in rows]))
            worst = max(rows, key=lambda r: r["err_deg"])
            prec = precision_deg(preds_by_point, screen)
        else:
            acc = acc_mm = math.inf
            worst = None
            prec = None
        enough = len(rows) >= min_points
        accepted = bool(enough and acc <= accept and worst is not None
                        and worst["err_deg"] <= worst_max)
        if not enough:
            reason = "few_points"
        elif accepted:
            reason = None
        elif acc > accept:
            reason = "accuracy"
        else:
            reason = "worst"
        a.validation = {
            "accuracy_deg": round(acc, 3) if rows else None,
            "accuracy_cm": round(acc_mm / 10, 2) if rows else None,
            "precision_deg": round(prec, 3) if prec is not None else None,
            "worst_deg": worst["err_deg"] if worst else None,
            "worst_id": worst["id"] if worst else None,
            "points": rows, "excluded": excluded, "accepted": accepted,
            "reason": reason,
            "thresholds": {"accept_deg": accept, "worst_deg": worst_max,
                           "min_points": min_points},
        }
        return dict(a.validation)

    # файл
    def to_json(self) -> dict:
        return {
            "schema": SCHEMA,
            "screen": self.screen.as_dict() if self.screen else None,
            "features": list(USED),
            "attempts": [{
                "attempt": a.n, "kind": a.kind, "started_qpc_us": a.started_us,
                "targets": [{"id": t.id, "x": t.x, "y": t.y, "phase": t.phase,
                             "qpc_us": t.qpc_us, **({"path": t.path} if t.path else {})}
                            for t in a.targets],
                "fit": a.fit, "validation": a.validation,
            } for a in self.attempts],
            "model": self.model.to_json() if self.model is not None else None,
            "scale_ref": self.scale_ref,
        }
