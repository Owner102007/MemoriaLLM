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

Поправка на голову (BUG-60) — три способа, считаются рядом: прежний
(поправка выучена по точкам калибровки), геометрия (глаза выучены при
голове на месте, а поворот и сдвиг головы переносят луч взгляда) и
геометрия с остатком, выученным по фазе движения головы. Живая точка и
итог идут по тому, что назван в `thresholds.json` (`head.model`);
проверка точности меряет все три.
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

PHASES = ("calib", "pursuit", "validate", "head", "check", "off")

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
    kind = d.get("kind")
    if kind == "head":
        return HeadModel.from_json(d)
    return Ridge.from_json(d) if kind == "ridge" else Kernel.from_json(d)


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


# --- голова: поза, геометрия, поправка (BUG-60) ---------------------------
#
# Поправка на позу головы, выученная на калибровке, учит шум: на точках
# голова почти не двигается (у владельца наклон ±0,6°), а место лица в
# кадре само чуть ходит за взглядом — уголки глаз у модели сдвигаются
# вместе с глазом. Модель принимает этот сдвиг за признак взгляда, и
# когда в свободном просмотре голова уходит на градусы и сантиметры, точка
# уезжает на 4–9 см. Поэтому глаза учатся при голове на месте, а голова
# переносится геометрией: глаз в голове смотрит туда же, а голова
# повернулась и сдвинулась — луч взгляда вместе с ней. Остаток, которого
# геометрия не знает (поза у MediaPipe меряется с погрешностью), учится
# по фазе движения головы, где точка стоит, а голова ходит.

HEAD_MODELS = ("learned", "geometry", "phase")

# Признаки головы в `USED`.
_YAW, _PITCH, _ROLL, _FX, _FY, _SC = range(N_EYE, N_EYE + 6)

# Из системы MediaPipe (x вправо по снимку, y вверх, z к человеку) в
# систему человека (x — его право, y вниз, z от него к экрану) — поворот
# на 180° вокруг z. Сверено на кадрах владельца: положительный yaw у
# MediaPipe — голова к левому краю экрана, pitch — вниз, roll — к правому
# плечу.
_MP_TO_PERSON = np.diag([-1.0, -1.0, 1.0])

# Масштаб отклонений головы для остатка: поворот — на 5°, сдвиг — на
# 2 см, расстояние — на 5 %.
HEAD_DELTA_SCALE = np.array([5.0, 5.0, 5.0, 20.0, 20.0, 0.05])


def head_rotations(yaw, pitch, roll) -> np.ndarray:
    """Поворот головы в системе человека по углам MediaPipe (градусы):
    `S · Rz(roll) · Ry(yaw) · Rx(pitch) · S` — тот же порядок, что
    разбирает `features.angles_from_matrix`."""
    y, p, r = (np.radians(np.atleast_1d(np.asarray(v, dtype=np.float64)))
               for v in (yaw, pitch, roll))
    n = len(y)
    cy, sy, cp, sp, cr, sr = np.cos(y), np.sin(y), np.cos(p), np.sin(p), np.cos(r), np.sin(r)
    rz = np.zeros((n, 3, 3))
    rz[:, 0, 0], rz[:, 0, 1], rz[:, 1, 0], rz[:, 1, 1], rz[:, 2, 2] = cr, -sr, sr, cr, 1
    ry = np.zeros((n, 3, 3))
    ry[:, 0, 0], ry[:, 0, 2], ry[:, 1, 1], ry[:, 2, 0], ry[:, 2, 2] = cy, sy, 1, -sy, cy
    rx = np.zeros((n, 3, 3))
    rx[:, 0, 0], rx[:, 1, 1], rx[:, 1, 2], rx[:, 2, 1], rx[:, 2, 2] = 1, cp, -sp, sp, cp
    s = _MP_TO_PERSON
    return s @ rz @ ry @ rx @ s


@dataclass
class HeadSetup:
    """Камера и лицо для геометрии головы: размер кадра камеры, расстояние
    между внешними уголками глаз и высота камеры над верхним краем экрана
    (камера — над серединой экрана и смотрит на человека)."""

    frame: tuple[int, int] = (1920, 1080)
    iod_mm: float = 90.0
    camera_above_mm: float = 8.0

    @staticmethod
    def of(thresholds: dict, frame: tuple[int, int] | None) -> "HeadSetup":
        return HeadSetup(frame=tuple(frame) if frame else (1920, 1080),
                         iod_mm=float(thresholds.get("iod_mm", 90.0)),
                         camera_above_mm=float(thresholds.get("camera_above_mm", 8.0)))

    def as_dict(self) -> dict:
        return {"frame": list(self.frame), "iod_mm": self.iod_mm,
                "camera_above_mm": self.camera_above_mm}


class Geometry:
    """Где глаза и куда повёрнута голова на кадре — и как от этого
    переезжает точка взгляда.

    Опора — голова на точках калибровки (медианы). Место глаз: середина
    уголков в кадре, переведённая в миллиметры по расстоянию между
    уголками (`iod_mm` на столько пикселей, сколько их между уголками),
    расстояние до экрана — по масштабу лица против опоры. Точка `p0`,
    которую глаза дали бы при опорной голове, переезжает так: луч от опорных
    глаз к ней поворачивается вместе с головой и выходит из нынешних глаз.
    """

    def __init__(self, screen: Screen, setup: HeadSetup, angles, ex: float,
                 ey: float, sc: float, head: np.ndarray):
        self.screen = screen
        self.setup = setup
        self.angles = tuple(float(a) for a in angles)
        self.ex, self.ey, self.sc = float(ex), float(ey), float(sc)
        self.head = np.asarray(head, dtype=np.float64)
        self.r_ref = head_rotations(*self.angles)[0]

    @staticmethod
    def _eff_scale(x: np.ndarray) -> np.ndarray:
        # Повёрнутое лицо сжато по ширине: масштаб — по углу поворота.
        c = np.cos(np.radians(np.clip(x[:, _YAW], -60.0, 60.0)))
        return np.maximum(x[:, _SC], 1e-6) / c

    @staticmethod
    def _place(x: np.ndarray, screen: Screen, setup: HeadSetup):
        sc = Geometry._eff_scale(x)
        k = setup.iod_mm / sc
        w, h = setup.frame
        xc = (x[:, _FX] * w - w / 2) * k
        yc = (x[:, _FY] * h - h / 2) * k
        cam_y = -screen.h_mm / 2 - setup.camera_above_mm
        # Камера смотрит на человека: вправо по снимку — его лево.
        return -xc, yc + cam_y, sc

    @staticmethod
    def fit(x: np.ndarray, screen: Screen, setup: HeadSetup) -> "Geometry":
        """Опора — медианы головы на выборках точек калибровки `x`."""
        x = np.atleast_2d(np.asarray(x, dtype=np.float64))
        ex, ey, sc = Geometry._place(x, screen, setup)
        angles = np.median(x[:, [_YAW, _PITCH, _ROLL]], axis=0)
        return Geometry(screen, setup, angles, float(np.median(ex)), float(np.median(ey)),
                        float(np.median(sc)), np.median(x[:, N_EYE:], axis=0))

    def freeze(self, x: np.ndarray) -> np.ndarray:
        """Признаки с головой на опоре: так их видят глаза."""
        f = np.array(np.atleast_2d(x), dtype=np.float64, copy=True)
        f[:, N_EYE:] = self.head
        return f

    def pose(self, x: np.ndarray):
        """Поворот головы против опоры и место глаз: (R, ex, ey, z), мм."""
        x = np.atleast_2d(np.asarray(x, dtype=np.float64))
        ex, ey, sc = Geometry._place(x, self.screen, self.setup)
        z = self.screen.distance_mm * self.sc / sc
        r = head_rotations(x[:, _YAW], x[:, _PITCH], x[:, _ROLL]) @ self.r_ref.T
        return r, ex, ey, z

    def _mm(self, p: np.ndarray) -> np.ndarray:
        sc = self.screen
        return np.column_stack([(p[:, 0] - sc.w / 2) * sc.w_mm / sc.w,
                                (p[:, 1] - sc.h / 2) * sc.h_mm / sc.h])

    def _px(self, m: np.ndarray) -> np.ndarray:
        sc = self.screen
        return np.column_stack([m[:, 0] * sc.w / sc.w_mm + sc.w / 2,
                                m[:, 1] * sc.h / sc.h_mm + sc.h / 2])

    def forward(self, p0: np.ndarray, x: np.ndarray) -> np.ndarray:
        """Точка `p0` (пиксели окна при опорной голове) — при голове кадра."""
        r, ex, ey, z = self.pose(x)
        m0 = self._mm(np.atleast_2d(p0))
        z0 = self.screen.distance_mm
        d0 = np.column_stack([m0[:, 0] - self.ex, m0[:, 1] - self.ey, np.full(len(m0), z0)])
        d = np.einsum("nij,nj->ni", r, d0)
        dz = np.maximum(d[:, 2], 1e-3 * z0)
        return self._px(np.column_stack([ex + z * d[:, 0] / dz, ey + z * d[:, 1] / dz]))

    def inverse(self, p: np.ndarray, x: np.ndarray) -> np.ndarray:
        """Куда смотрели бы глаза кадра при опорной голове (обратное к
        `forward`)."""
        r, ex, ey, z = self.pose(x)
        m = self._mm(np.atleast_2d(p))
        d = np.column_stack([m[:, 0] - ex, m[:, 1] - ey, z])
        d0 = np.einsum("nji,nj->ni", r, d)
        z0 = self.screen.distance_mm
        dz = np.maximum(d0[:, 2], 1e-3 * z0)
        return self._px(np.column_stack([self.ex + z0 * d0[:, 0] / dz,
                                         self.ey + z0 * d0[:, 1] / dz]))

    def relative(self, x: np.ndarray) -> dict[str, np.ndarray]:
        """Голова против опоры: поворот к правому краю экрана (`turn`),
        наклон вниз (`tilt`), к правому плечу (`roll`) — градусы; сдвиг
        вправо и вниз (`dx`, `dy`) — мм; расстояние (`dz`) — доля, минус —
        ближе."""
        r, ex, ey, z = self.pose(x)
        fwd, right = r[:, :, 2], r[:, :, 0]
        return {"turn": np.degrees(np.arctan2(fwd[:, 0], fwd[:, 2])),
                "tilt": np.degrees(np.arctan2(fwd[:, 1], fwd[:, 2])),
                "roll": np.degrees(np.arctan2(right[:, 1], right[:, 0])),
                "dx": ex - self.ex, "dy": ey - self.ey,
                "dz": z / self.screen.distance_mm - 1.0}

    def deltas(self, x: np.ndarray) -> np.ndarray:
        """Отклонения головы для остатка, в масштабе `HEAD_DELTA_SCALE`."""
        rel = self.relative(x)
        d = np.column_stack([rel[k] for k in ("turn", "tilt", "roll", "dx", "dy", "dz")])
        return d / HEAD_DELTA_SCALE

    def to_json(self) -> dict:
        return {"screen": self.screen.as_dict(), "setup": self.setup.as_dict(),
                "angles": list(self.angles), "ex": self.ex, "ey": self.ey, "sc": self.sc,
                "head": self.head.tolist()}

    @staticmethod
    def from_json(d: dict) -> "Geometry":
        s = d["screen"]
        su = d["setup"]
        return Geometry(Screen(s["w"], s["h"], s["w_mm"], s["h_mm"], s["distance_mm"]),
                        HeadSetup(tuple(su["frame"]), su["iod_mm"], su["camera_above_mm"]),
                        d["angles"], d["ex"], d["ey"], d["sc"], d["head"])


class HeadModel:
    """Глаза — модель `eye`, выученная при голове на опоре; голова —
    геометрией `geo`; остаток `w` по отклонениям головы, если он выучен
    (способ `phase`)."""

    kind = "head"

    def __init__(self, eye, geo: Geometry, label: str, w: np.ndarray | None = None):
        self.eye = eye
        self.geo = geo
        self.label = label
        self.w = None if w is None else np.asarray(w, dtype=np.float64)

    def predict(self, x: np.ndarray) -> np.ndarray:
        x = np.atleast_2d(np.asarray(x, dtype=np.float64))
        p = self.geo.forward(self.eye.predict(self.geo.freeze(x)), x)
        if self.w is not None:
            p = p + self.geo.deltas(x) @ self.w
        return p

    def to_json(self) -> dict:
        return {"kind": self.kind, "label": self.label, "eye": self.eye.to_json(),
                "geometry": self.geo.to_json(),
                "w": None if self.w is None else self.w.tolist()}

    @staticmethod
    def from_json(d: dict) -> "HeadModel":
        return HeadModel(model_from_json(d["eye"]), Geometry.from_json(d["geometry"]),
                         d.get("label", "geometry"), d.get("w"))


def fit_head_rest(model: HeadModel, x: np.ndarray, target: np.ndarray, screen: Screen,
                  t: dict) -> tuple[np.ndarray | None, dict]:
    """Остаток поправки на голову по фазе движения головы: человек смотрит
    на неподвижную точку `target` и водит головой. Чего геометрия не
    знает — то, как ошибка зависит от отклонений головы, — линейно, с
    гребнем к нулю (к геометрии). Выборки, где оценка дальше
    `max_err_deg` от точки, — взгляд ушёл с точки; после первого прохода
    выбросы дальше `mad_k` MAD — тоже прочь. Голова почти не двигалась —
    остатка нет."""
    x = np.atleast_2d(np.asarray(x, dtype=np.float64))
    info: dict = {"frames": int(len(x)), "used": 0, "moved": False,
                  "turn_deg": None, "tilt_deg": None}
    if len(x) == 0:
        return None, info
    rel = model.geo.relative(x)
    turn = float(np.percentile(rel["turn"], 95) - np.percentile(rel["turn"], 5))
    tilt = float(np.percentile(rel["tilt"], 95) - np.percentile(rel["tilt"], 5))
    info["turn_deg"], info["tilt_deg"] = round(turn, 2), round(tilt, 2)
    pred = model.predict(x)
    tgt = np.broadcast_to(np.asarray(target, dtype=np.float64), pred.shape)
    err = np.array([screen.angle_deg(tuple(a), tuple(b)) for a, b in zip(pred, tgt)])
    keep = err <= float(t.get("max_err_deg", 8.0))
    info["moved"] = bool(max(turn, tilt) >= float(t.get("min_range_deg", 2.0)))
    if not info["moved"] or keep.sum() < int(t.get("min_frames", 90)):
        info["used"] = int(keep.sum())
        return None, info
    d = model.geo.deltas(x)[keep]
    r = (tgt - pred)[keep]
    alpha = float(t.get("alpha", 0.1))
    w = None
    for _ in range(2):
        dc = d - d.mean(axis=0)
        rc = r - r.mean(axis=0)
        w = np.linalg.solve(dc.T @ dc + alpha * len(dc) * np.eye(dc.shape[1]), dc.T @ rc)
        res = np.hypot(*(rc - dc @ w).T)
        med = float(np.median(res))
        mad = 1.4826 * float(np.median(np.abs(res - med)))
        ok = res <= med + float(t.get("mad_k", 3.0)) * max(mad, 1e-6)
        if ok.all():
            break
        d, r = d[ok], r[ok]
    info["used"] = int(len(d))
    info["w"] = np.round(w, 3).tolist()
    return w, info


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


@dataclass
class Check:
    """Проверка точности без новой калибровки (BUG-60): девять точек той
    моделью, что есть, — после того как человек посидел и подвигался, и в
    конце пробной калибровки (как будет в конце записи, SNO-F-EYE-06)."""

    n: int
    targets: list[Target] = field(default_factory=list)
    started_us: int | None = None
    result: dict | None = None


class Calibration:
    """Калибровка одной сессии спутника: кадры, точки, попытки, модель.

    Кадры приходят из потока распознавания (`add`), точки и команды — из
    потока команд; один замок на буфер. Точки ложатся в то, что начато
    последним, — попытку (`begin`) или проверку (`begin_check`).
    """

    def __init__(self, screen: Screen | None, thresholds: dict,
                 frame: tuple[int, int] | None = None):
        self.screen = screen
        self.t = dict(thresholds.get("calibration", {}))
        self.h = dict(thresholds.get("head", {}))
        self.head_model = self.h.get("model", "phase")
        if self.head_model not in HEAD_MODELS:
            self.head_model = "phase"
        self.frame = frame
        self._lock = threading.Lock()
        self._frames: deque[Sample] = deque(maxlen=BUFFER_FRAMES)
        self.attempts: list[Attempt] = []
        self.checks: list[Check] = []
        self._current: Attempt | Check | None = None
        self.model = None
        self.models: dict[str, Any] = {}
        self.geo: Geometry | None = None
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

    # попытки и проверки
    @property
    def attempt(self) -> Attempt | None:
        return self.attempts[-1] if self.attempts else None

    @property
    def check(self) -> Check | None:
        return self._current if isinstance(self._current, Check) else None

    def setup(self) -> HeadSetup:
        return HeadSetup.of(self.h, self.frame)

    def begin(self, n: int, kind: str, now_us: int) -> Attempt:
        if self.screen is None:
            raise CalibrationError("bad_command", "Нет размеров экрана: "
                                                  "их называет команда open")
        if kind not in ("full", "quick"):
            raise CalibrationError("bad_command", "«kind» — full или quick")
        a = Attempt(n=n, kind=kind, started_us=now_us)
        self.attempts.append(a)
        self._current = a
        return a

    def begin_check(self, n: int, now_us: int) -> Check:
        if self.model is None:
            raise CalibrationError("bad_command", "Проверке нужна модель: "
                                                  "сначала fit")
        c = Check(n=n, started_us=now_us)
        self.checks.append(c)
        self._current = c
        return c

    def target(self, ev: Target) -> None:
        cur = self._current
        if cur is None:
            raise CalibrationError("bad_command", "Точка до начала калибровки")
        if cur.targets and ev.qpc_us < cur.targets[-1].qpc_us:
            raise CalibrationError("bad_command", "Точка раньше предыдущей")
        cur.targets.append(ev)

    def _owner(self, phase: str):
        owner = self.check if phase == "check" else self.attempt
        if owner is None:
            raise CalibrationError("bad_command", "Проверка не начата" if phase == "check"
                                   else "Калибровка не начата")
        return owner

    # выборки точек
    def _point_samples(self, a, phase: str) -> dict[str, dict]:
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

    def _phase_frames(self, a, phase: str, drop_s: float) -> tuple[np.ndarray, np.ndarray]:
        """Все годные кадры фазы без первых `drop_s` у каждой точки — без
        отбора выбросов: в фазе движения головы признаки и должны ходить.
        Возвращает признаки и точку каждого кадра."""
        drop = int(drop_s * 1e6)
        feats, tgts = [], []
        for k, t in enumerate(a.targets[:-1]):
            if t.phase != phase:
                continue
            for f in self._frames_between(t.qpc_us + drop, a.targets[k + 1].qpc_us):
                if f.ok and f.feat is not None:
                    feats.append(f.feat)
                    tgts.append((t.x, t.y))
        if not feats:
            return np.zeros((0, len(fp.FEATURE_NAMES))), np.zeros((0, 2))
        return np.array(feats, dtype=np.float64), np.array(tgts, dtype=np.float64)

    def samples(self, phase: str = "calib") -> dict:
        """Сколько годных кадров набрала каждая точка фазы и какую долю
        времени лицо было в кадре. Точка без `min_samples` — повторить."""
        a = self._owner(phase)
        pts = self._point_samples(a, phase)
        need = int(self.t.get("min_samples", 15))
        counts = {tid: p["used"] for tid, p in pts.items()}
        frames = sum(p["frames"] for p in pts.values())
        good = sum(p["good"] for p in pts.values())
        face = self._face_share(a, phase)
        out = {"phase": phase, "counts": counts,
               "short": [tid for tid, n in counts.items() if n < need],
               "face": round(face, 3) if face is not None else None,
               "frames": frames, "good": good}
        if phase == "head":
            # В фазе головы годный кадр — любой кадр с лицом: признаки
            # там ходят, и отбор выбросов ей не нужен.
            x, _ = self._phase_frames(a, "head", float(self.h.get("drop_s", 0.5)))
            out["counts"] = {tid: int(len(x)) for tid in counts}
            out["short"] = []
        return out

    def _face_share(self, a, phase: str) -> float | None:
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
        """Модели попытки: точки калибровки (и слежение у полной), задержка
        камеры, ошибка «без одной точки». Точка без годных выборок
        исключается и названа.

        Моделей три (BUG-60): `learned` — прежняя, поправка на голову
        выучена по точкам; `geometry` — глаза выучены при голове на опоре,
        голова — геометрией; `phase` — то же и остаток по фазе движения
        головы (её нет — остатка нет, и `phase` совпадает с `geometry`).
        Живая точка и итог — по `head.model` из порогов."""
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
        # Прежняя: поправка на голову — из самих точек.
        learned, info_learned = select_model(ts, screen, kinds=kinds)
        # Глаза при голове на опоре: цели переведены туда, куда смотрели бы
        # глаза кадра, стой голова как на опоре.
        geo = Geometry.fit(np.concatenate([used[t]["feats"] for t in names])[:, USED_IDX],
                           screen, self.setup())
        eye_ts = TrainSet(geo.freeze(ts.x), geo.inverse(ts.y, ts.x), ts.group)
        eye, info_eye = select_model(eye_ts, screen, kinds=kinds)
        geometry = HeadModel(eye, geo, "geometry")
        hx, htgt = self._phase_frames(a, "head", float(self.h.get("drop_s", 0.5)))
        w, head_info = fit_head_rest(geometry, hx[:, USED_IDX] if len(hx) else hx,
                                     htgt, screen, self.h)
        phase = HeadModel(eye, geo, "phase", w)
        self.geo = geo
        self.models = {"learned": learned, "geometry": geometry, "phase": phase}
        self.model = self.models[self.head_model]
        info = info_learned if self.head_model == "learned" else info_eye
        self.model_info = info
        self.noise_px = self._noise(self.model, used)
        cv = info["cv_deg"][info["kind"]]
        variants = {
            "learned": {"model": info_learned["kind"],
                        "cv_deg": info_learned["cv_deg"][info_learned["kind"]]},
            "geometry": {"model": info_eye["kind"],
                         "cv_deg": info_eye["cv_deg"][info_eye["kind"]]},
            "phase": {"model": info_eye["kind"],
                      "cv_deg": info_eye["cv_deg"][info_eye["kind"]],
                      "rest": w is not None},
        }
        a.fit = {
            "model": info["kind"], "cv_deg": cv, "cv_by_model": info["cv_deg"],
            "cv_cm": round(math.tan(math.radians(cv)) * screen.distance_mm / 10, 2),
            "latency_ms": latency_ms, "points": len(used), "excluded": excluded,
            "samples": int(len(fix.x)), "pursuit": pursuit_n,
            "counts": {tid: p["used"] for tid, p in pts.items()},
            "face": round(face, 3) if face is not None else None,
            "noise_px": [round(v, 1) for v in self.noise_px],
            "noise_deg": round(self._noise_deg(self.noise_px), 3),
            "head_model": self.head_model, "variants": variants, "head": head_info,
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

    def _measure(self, model, pts: dict, need: int) -> dict:
        """Точность модели на точках `pts`: средний угол между медианой
        оценки точки и точкой, прецизионность, худшая точка, средний сдвиг
        оценки (мм, вправо и вниз)."""
        screen = self.screen
        rows, preds_by_point, excluded, shifts = [], [], [], []
        for tid in sorted(pts, key=lambda s: (len(s), s)):
            p = pts[tid]
            if p["used"] < need:
                excluded.append(tid)
                continue
            pred = model.predict(p["feats"][:, USED_IDX])
            med = np.median(pred, axis=0)
            dist = self.distance_for(float(np.median(p["feats"][:, SCALE_IDX])))
            err = screen.angle_deg(tuple(med), (p["x"], p["y"]), dist)
            err_mm = screen.mm_between(tuple(med), (p["x"], p["y"]))
            gx, gy = screen.mm(*med)
            tx, ty = screen.mm(p["x"], p["y"])
            shifts.append((gx - tx, gy - ty))
            rows.append({"id": tid, "x": p["x"], "y": p["y"],
                         "gx": round(float(med[0]), 1), "gy": round(float(med[1]), 1),
                         "err_deg": round(err, 3), "err_mm": round(err_mm, 1),
                         "n": p["used"]})
            preds_by_point.append(pred)
        if rows:
            acc = float(np.mean([r["err_deg"] for r in rows]))
            acc_mm = float(np.mean([r["err_mm"] for r in rows]))
            worst = max(rows, key=lambda r: r["err_deg"])
            prec = precision_deg(preds_by_point, screen)
            sx, sy = np.mean(shifts, axis=0)
        else:
            acc = acc_mm = math.inf
            worst = None
            prec = None
            sx = sy = None
        return {
            "accuracy_deg": round(acc, 3) if rows else None,
            "accuracy_cm": round(acc_mm / 10, 2) if rows else None,
            "precision_deg": round(prec, 3) if prec is not None else None,
            "worst_deg": worst["err_deg"] if worst else None,
            "worst_id": worst["id"] if worst else None,
            "shift_mm": [round(float(sx), 1), round(float(sy), 1)] if rows else None,
            "points": rows, "excluded": excluded,
        }

    @staticmethod
    def _brief(m: dict) -> dict:
        return {k: m[k] for k in ("accuracy_deg", "accuracy_cm", "worst_deg", "shift_mm")}

    def validate(self) -> dict:
        """Проверка: точки фазы `validate` той же моделью. Точность — средний
        угол между медианой оценки точки и точкой; прецизионность — RMS угла
        между соседними выборками; худшая точка. Приём — по порогам. Рядом —
        точность каждого способа поправки на голову (`variants`)."""
        a = self.attempt
        if a is None or self.model is None:
            raise CalibrationError("bad_command", "Проверке нужна модель: "
                                                  "сначала fit")
        pts = self._point_samples(a, "validate")
        need = int(self.t.get("min_valid", 10))
        measured = {name: self._measure(m, pts, need) for name, m in self.models.items()}
        main = measured[self.head_model]
        accept = float(self.t.get("accept_deg", 2.5))
        worst_max = float(self.t.get("worst_deg", 5.0))
        min_points = int(self.t.get("min_points", 6))
        rows = main["points"]
        acc = main["accuracy_deg"]
        enough = len(rows) >= min_points
        accepted = bool(enough and acc is not None and acc <= accept
                        and main["worst_deg"] is not None
                        and main["worst_deg"] <= worst_max)
        if not enough:
            reason = "few_points"
        elif accepted:
            reason = None
        elif acc > accept:
            reason = "accuracy"
        else:
            reason = "worst"
        a.validation = {
            **main, "accepted": accepted, "reason": reason,
            "thresholds": {"accept_deg": accept, "worst_deg": worst_max,
                           "min_points": min_points},
            "head_model": self.head_model,
            "variants": {name: self._brief(m) for name, m in measured.items()},
        }
        return dict(a.validation)

    def head_report(self, owner, phase: str) -> dict | None:
        """Где голова в фазе `phase` против опоры калибровки — медианы:
        поворот, наклон, к плечу (градусы), сдвиг (мм), расстояние (%)."""
        if self.geo is None:
            return None
        x, _ = self._phase_frames(owner, phase, float(self.t.get("drop_s", 0.5)))
        if not len(x):
            return None
        rel = self.geo.relative(x[:, USED_IDX])
        med = {k: float(np.median(v)) for k, v in rel.items()}
        return {"turn_deg": round(med["turn"], 2), "tilt_deg": round(med["tilt"], 2),
                "roll_deg": round(med["roll"], 2), "dx_mm": round(med["dx"], 1),
                "dy_mm": round(med["dy"], 1), "dz_pct": round(med["dz"] * 100, 1)}

    def check_result(self) -> dict:
        """Итог проверки без новой калибровки (BUG-60): точность каждого
        способа на её точках и где была голова против калибровки. Главные
        числа — у способа `head.model`; `start_deg` — точность проверки
        сразу после калибровки, если она была."""
        c = self.check
        if c is None or self.model is None:
            raise CalibrationError("bad_command", "Проверка не начата")
        pts = self._point_samples(c, "check")
        need = int(self.t.get("min_valid", 10))
        measured = {name: self._measure(m, pts, need) for name, m in self.models.items()}
        main = measured[self.head_model]
        start = self.attempt.validation if self.attempt else None
        c.result = {
            "n": c.n, **main, "head_model": self.head_model,
            "variants": {name: self._brief(m) for name, m in measured.items()},
            "head": self.head_report(c, "check"),
            "start_deg": start.get("accuracy_deg") if start else None,
        }
        return dict(c.result)

    # файл
    def to_json(self) -> dict:
        def targets(ts):
            return [{"id": t.id, "x": t.x, "y": t.y, "phase": t.phase,
                     "qpc_us": t.qpc_us, **({"path": t.path} if t.path else {})}
                    for t in ts]

        return {
            "schema": SCHEMA,
            "screen": self.screen.as_dict() if self.screen else None,
            "features": list(USED),
            "setup": self.setup().as_dict(),
            "attempts": [{
                "attempt": a.n, "kind": a.kind, "started_qpc_us": a.started_us,
                "targets": targets(a.targets),
                "fit": a.fit, "validation": a.validation,
            } for a in self.attempts],
            "checks": [{"check": c.n, "started_qpc_us": c.started_us,
                        "targets": targets(c.targets), "result": c.result}
                       for c in self.checks],
            "head_model": self.head_model,
            "model": self.model.to_json() if self.model is not None else None,
            "variants": {name: m.to_json() for name, m in self.models.items()},
            "scale_ref": self.scale_ref,
        }
