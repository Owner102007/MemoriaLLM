"""Шаг 9 — статистика сравнения ветвей (SNO-ALG-RES-05, шаги 1–6, 9).

Откуда данные: таблица «участник — строка» (`study.table`) — значение
меры, вес участника (цвет искренности, `study.honesty`), ветвь и слой
(ПК, `study.collect`).
Технология: numpy — массивы, попарные знаки, повторы бутстрепа и
перестановок пачками; генератор `numpy.random.default_rng` с зерном из
отпечатка набора архивов: тот же набор на тех же версиях Python и numpy
даёт те же числа до бита.
Метод:
* взвешенные среднее, медиана, отклонение; n_eff — Kish L. «Survey
  Sampling», 1965;
* дельта Клиффа — Cliff N. «Dominance statistics: ordinal analyses to
  answer ordinal questions», Psychological Bulletin, 1993, 114(3):494;
  свод слоёв — по образцу van Elteren P. «On the combination of
  independent two-sample tests of Wilcoxon», Bulletin of the ISI,
  1960, 37; слова о величине — Romano J. и др., 2006;
* интервал — процентильный бутстреп: Efron B., Tibshirani R. «An
  Introduction to the Bootstrap», 1993;
* p — перестановочный тест: Good P. «Permutation, Parametric and
  Bootstrap Tests of Hypotheses», 2005; p = (b + 1) / (B + 1) —
  Phipson B., Smyth G. «Permutation p-values should never be zero»,
  SAGMB, 2010, 9(1);
* поправка на множественность — Holm S. «A simple sequentially
  rejective multiple test procedure», Scand. J. Statistics, 1979, 6:65;
* связь мер — ранговая корреляция Спирмена с весами (взвешенный
  Пирсон рангов).
Вход → выход: значения меры с весами, ветвями и слоями → описание
ветвей, δ с интервалом, p, словами.

Без scipy и pandas: их нет во встраиваемом Python спутника, а четыре
нужные вещи — около двухсот строк, и каждая формула лежит на виду.
Вторая реализация на чистом Python — `eye/tests/test_study_stats.py`.
"""

from __future__ import annotations

import hashlib
import itertools
import math
from dataclasses import dataclass, field

import numpy as np

# Ветви: «II» — та, о которой говорит знак δ. δ > 0 — у ветви II больше.
SECOND = "II"
FIRST = "I"

# Пороги слов о величине δ — Romano и др., 2006.
EFFECT_STEPS = ((0.147, "пренебрежимо"), (0.33, "мал"), (0.474, "средний"))

# Пачка повторов: B × n₂ × n₁ чисел за раз — память не растёт с B.
_CHUNK = 2000

# Сравнение |δ| с настоящим — с допуском на сложение в другом порядке.
_EPS = 1e-12


def seed_for(*parts: object) -> int:
    """Зерно генератора из частей: отпечаток набора, сравнение,
    сценарий, мера. Своё у каждой меры — число одной меры не зависит
    от того, какие ещё меры есть в наборе."""
    text = "\x1f".join(str(p) for p in parts)
    return int.from_bytes(hashlib.sha256(text.encode("utf-8")).digest()[:8],
                          "big")


# --- описание ветви --------------------------------------------------

def n_eff(w) -> float:
    """n_eff = (Σw)² / Σw² — со сколькими участниками равного веса
    выборка сравнима по точности среднего (Kish, 1965). Пятеро весом 1
    и двое весом 0,5: 36 / 5,5 ≈ 6,5."""
    w = np.asarray(w, dtype=float)
    s2 = float(np.sum(w * w))
    return float(np.sum(w)) ** 2 / s2 if s2 > 0 else 0.0


def weighted_mean(x, w) -> float | None:
    """Σ wᵢ xᵢ / Σ wᵢ."""
    x = np.asarray(x, dtype=float)
    w = np.asarray(w, dtype=float)
    total = float(np.sum(w))
    return float(np.sum(w * x)) / total if total > 0 else None


def weighted_median(x, w) -> float | None:
    """Значение, на котором накопленный вес переходит половину.

    # Выбор наш: если накопленный вес ровно равен половине, медиана —
    середина между этим значением и следующим; при равных весах так
    выходит обычная медиана (`statistics.median`)."""
    x = np.asarray(x, dtype=float)
    w = np.asarray(w, dtype=float)
    keep = w > 0
    x, w = x[keep], w[keep]
    if x.size == 0:
        return None
    order = np.argsort(x, kind="stable")
    x, w = x[order], w[order]
    half = float(np.sum(w)) / 2
    acc = 0.0
    for i in range(x.size):
        acc += float(w[i])
        if abs(acc - half) <= 1e-12 * max(1.0, half) and i + 1 < x.size:
            return (float(x[i]) + float(x[i + 1])) / 2
        if acc > half:
            return float(x[i])
    return float(x[-1])


def weighted_sd(x, w) -> float | None:
    """√(Σ wᵢ (xᵢ − x̄)² / Σ wᵢ) — описательное отклонение.

    # Выбор наш: без поправки Бесселя — это описание разброса в
    выборке, а не оценка; в выводы оно не идёт."""
    mean = weighted_mean(x, w)
    if mean is None:
        return None
    x = np.asarray(x, dtype=float)
    w = np.asarray(w, dtype=float)
    return math.sqrt(float(np.sum(w * (x - mean) ** 2)) / float(np.sum(w)))


def describe(x, w) -> dict:
    """Описание меры в ветви: n, Σw, n_eff, среднее, медиана, разброс."""
    x = np.asarray(x, dtype=float)
    w = np.asarray(w, dtype=float)
    if x.size == 0:
        return {"n": 0, "sum_w": 0.0, "n_eff": 0.0, "mean": None,
                "median": None, "sd": None, "min": None, "max": None}
    return {"n": int(x.size), "sum_w": float(np.sum(w)), "n_eff": n_eff(w),
            "mean": weighted_mean(x, w), "median": weighted_median(x, w),
            "sd": weighted_sd(x, w), "min": float(np.min(x)),
            "max": float(np.max(x))}


def mean_interval(x, w, seed: int, repeats: int) -> tuple | None:
    """Интервал 95 % взвешенного среднего — бутстреп внутри ветви:
    участники вытягиваются с возвращением равновероятно, вес идёт в
    среднее (Efron, Tibshirani, 1993). Для рисунков, не для выводов."""
    x = np.asarray(x, dtype=float)
    w = np.asarray(w, dtype=float)
    if x.size < 2:
        return None
    rng = np.random.default_rng(seed)
    out = np.empty(repeats)
    for lo in range(0, repeats, _CHUNK):
        hi = min(repeats, lo + _CHUNK)
        idx = rng.integers(0, x.size, size=(hi - lo, x.size))
        ww = w[idx]
        out[lo:hi] = np.sum(ww * x[idx], axis=1) / np.sum(ww, axis=1)
    return float(np.percentile(out, 2.5)), float(np.percentile(out, 97.5))


# --- дельта Клиффа по слоям -------------------------------------------

@dataclass
class Stratum:
    """Слой (ПК): значения и веса участников ветвей II и I."""

    name: str
    x2: np.ndarray
    w2: np.ndarray
    x1: np.ndarray
    w1: np.ndarray

    @property
    def comparable(self) -> bool:
        return self.x2.size > 0 and self.x1.size > 0


def _pair_sign(x2: np.ndarray, x1: np.ndarray) -> np.ndarray:
    """sign(xᵢ − yⱼ): +1 — у участника ветви II больше, −1 — меньше,
    0 — ничья. Матрица n₂ × n₁."""
    return np.sign(x2[:, None] - x1[None, :])


def cliff(x2, w2, x1, w1) -> float:
    """δ = Σᵢ Σⱼ wᵢ wⱼ · sign(xᵢ − yⱼ) / (Σ wᵢ · Σ wⱼ) — доля пар «у II
    больше» минус доля пар «у II меньше» (Cliff, 1993).

    # Выбор наш: вес пары — произведение весов её участников."""
    x2, w2 = np.asarray(x2, float), np.asarray(w2, float)
    x1, w1 = np.asarray(x1, float), np.asarray(w1, float)
    total = float(np.sum(w2)) * float(np.sum(w1))
    if total <= 0:
        return 0.0
    return float(w2 @ _pair_sign(x2, x1) @ w1) / total


def _lam(W1, W2):
    """λ = W_I · W_II / (W_I + W_II) — вес слоя в своде: слой, где обе
    ветви представлены полнее, весит больше (по образцу van Elteren,
    1960)."""
    return W1 * W2 / (W1 + W2)


def stratified(strata: list[Stratum]) -> float | None:
    """δ = Σ λₛ δₛ / Σ λₛ по сравнимым слоям."""
    num = 0.0
    den = 0.0
    for s in strata:
        if not s.comparable:
            continue
        W2, W1 = float(np.sum(s.w2)), float(np.sum(s.w1))
        if W2 <= 0 or W1 <= 0:
            continue
        lam = _lam(W1, W2)
        num += lam * cliff(s.x2, s.w2, s.x1, s.w1)
        den += lam
    return num / den if den > 0 else None


def _mean_diff(s: Stratum) -> float:
    return float(np.sum(s.w2 * s.x2) / np.sum(s.w2)
                 - np.sum(s.w1 * s.x1) / np.sum(s.w1))


def stratified_diff(strata: list[Stratum]) -> float | None:
    """Разница взвешенных средних II − I, сведённая по слоям теми же
    λₛ, — справочно рядом с δ."""
    num = 0.0
    den = 0.0
    for s in strata:
        if not s.comparable:
            continue
        lam = _lam(float(np.sum(s.w1)), float(np.sum(s.w2)))
        num += lam * _mean_diff(s)
        den += lam
    return num / den if den > 0 else None


def bootstrap(strata: list[Stratum], seed: int, repeats: int
              ) -> tuple[tuple | None, tuple | None]:
    """Интервалы 95 % для δ по слоям и для разницы средних — бутстреп.

    В каждом повторе участники вытягиваются с возвращением
    **равновероятно** внутри своей ветви и своего слоя; вес участника
    идёт в δ, а не в вероятность вытянуть, иначе он учёлся бы дважды.
    Интервал — от 2,5-го до 97,5-го процентиля (Efron, Tibshirani,
    1993)."""
    live = [s for s in strata if s.comparable]
    if not live:
        return None, None
    rng = np.random.default_rng(seed)
    delta_num = np.zeros(repeats)
    diff_num = np.zeros(repeats)
    den = np.zeros(repeats)
    for s in live:
        sign = _pair_sign(s.x2, s.x1)
        for lo in range(0, repeats, _CHUNK):
            hi = min(repeats, lo + _CHUNK)
            a = rng.integers(0, s.x2.size, size=(hi - lo, s.x2.size))
            b = rng.integers(0, s.x1.size, size=(hi - lo, s.x1.size))
            wa, wb = s.w2[a], s.w1[b]
            W2, W1 = wa.sum(axis=1), wb.sum(axis=1)
            pairs = sign[a[:, :, None], b[:, None, :]]
            d = np.einsum("ki,kij,kj->k", wa, pairs, wb) / (W2 * W1)
            m = (np.sum(wa * s.x2[a], axis=1) / W2
                 - np.sum(wb * s.x1[b], axis=1) / W1)
            lam = _lam(W1, W2)
            delta_num[lo:hi] += lam * d
            diff_num[lo:hi] += lam * m
            den[lo:hi] += lam
    deltas = delta_num / den
    diffs = diff_num / den
    return ((float(np.percentile(deltas, 2.5)),
             float(np.percentile(deltas, 97.5))),
            (float(np.percentile(diffs, 2.5)),
             float(np.percentile(diffs, 97.5))))


def _pooled(s: Stratum) -> tuple[np.ndarray, np.ndarray, int]:
    x = np.concatenate([s.x2, s.x1])
    w = np.concatenate([s.w2, s.w1])
    return x, w, s.x2.size


def _assignments(z: np.ndarray, sign: np.ndarray, w: np.ndarray):
    """δₛ и λₛ для пачки разметок [z] (1 — ветвь II, 0 — ветвь I):
    числитель δ — zᵀ M (1 − z), где M = w wᵀ · sign(xᵢ − xⱼ)."""
    m = (w[:, None] * w[None, :]) * sign
    zw = z.astype(float)
    num = np.einsum("ki,ij,kj->k", zw, m, 1.0 - zw)
    W2 = zw @ w
    W1 = (1.0 - zw) @ w
    return num / (W2 * W1), _lam(W1, W2)


def permutations_total(strata: list[Stratum]) -> int:
    """Сколько разметок даёт перемешивание меток внутри слоёв:
    Π C(nₛ, n_II,ₛ)."""
    total = 1
    for s in strata:
        if s.comparable:
            total *= math.comb(s.x2.size + s.x1.size, s.x2.size)
    return total


def permutation_p(strata: list[Stratum], observed: float, seed: int,
                  repeats: int, exact_limit: int) -> tuple[float, bool]:
    """p перестановочного теста для той же δ по слоям.

    Метки ветвей перемешиваются **внутри слоя**, веса остаются при
    участниках. Разметок не больше [exact_limit] — перебираются все, и
    p — доля разметок с |δ| не меньше настоящего (точный тест, сама
    настоящая разметка в их числе). Иначе [repeats] случайных и
    p = (b + 1) / (B + 1) (Good, 2005; Phipson, Smyth, 2010).
    Отвечает (p, точный ли)."""
    live = [s for s in strata if s.comparable]
    target = abs(observed) - _EPS
    total = permutations_total(live)
    if total <= exact_limit:
        num = np.zeros(1)
        den = np.zeros(1)
        for s in live:
            x, w, k = _pooled(s)
            sign = np.sign(x[:, None] - x[None, :])
            combos = list(itertools.combinations(range(x.size), k))
            z = np.zeros((len(combos), x.size), dtype=np.int8)
            for row, chosen in enumerate(combos):
                z[row, list(chosen)] = 1
            d, lam = _assignments(z, sign, w)
            # Произведение разметок слоёв: числитель и знаменатель свода
            # складываются по всем сочетаниям.
            num = (num[:, None] + (lam * d)[None, :]).ravel()
            den = (den[:, None] + lam[None, :]).ravel()
        deltas = num / den
        hits = int(np.sum(np.abs(deltas) >= target))
        return hits / deltas.size, True
    rng = np.random.default_rng(seed)
    num = np.zeros(repeats)
    den = np.zeros(repeats)
    for s in live:
        x, w, k = _pooled(s)
        sign = np.sign(x[:, None] - x[None, :])
        base = np.zeros(x.size, dtype=np.int8)
        base[:k] = 1
        for lo in range(0, repeats, _CHUNK):
            hi = min(repeats, lo + _CHUNK)
            z = rng.permuted(np.tile(base, (hi - lo, 1)), axis=1)
            d, lam = _assignments(z, sign, w)
            num[lo:hi] += lam * d
            den[lo:hi] += lam
    hits = int(np.sum(np.abs(num / den) >= target))
    return (hits + 1) / (repeats + 1), False


# --- поправка и слова --------------------------------------------------

def holm(ps: list[float | None], missing_as_one: bool = False
         ) -> list[float | None]:
    """Поправка Холма (Holm, 1979): p упорядочиваются по возрастанию,
    k-е умножается на (m − k + 1), берётся накопленный максимум, потолок
    — 1.

    Мера без p (данных мало) в семью не входит. С [missing_as_one] она
    входит с p = 1: так главная мера, которой ещё нет (`H_t` до шага
    37), не делает поправку двух других мягче. Поправленное p не
    убывает, когда растёт любое исходное, поэтому «значимо» с p = 1 у
    недостающей не отменится, когда она появится."""
    present = [(p if p is not None else 1.0) for p in ps
               if p is not None or missing_as_one]
    m = len(present)
    out: list[float | None] = [None] * len(ps)
    order = sorted((p if p is not None else 1.0, i)
                   for i, p in enumerate(ps)
                   if p is not None or missing_as_one)
    running = 0.0
    for k, (p, i) in enumerate(order):
        running = max(running, min(1.0, (m - k) * p))
        out[i] = running if ps[i] is not None else None
    return out


def effect_words(delta: float | None) -> str:
    """Величина δ словами — пороги Romano и др., 2006."""
    if delta is None:
        return "—"
    size = abs(delta)
    for limit, word in EFFECT_STEPS:
        if size < limit:
            return word
    return "большой"


# --- связь мер ---------------------------------------------------------

def _ranks(x: np.ndarray) -> np.ndarray:
    """Ранги с ничьими по среднему рангу."""
    order = np.argsort(x, kind="stable")
    ranks = np.empty(x.size)
    sorted_x = x[order]
    i = 0
    while i < x.size:
        j = i
        while j + 1 < x.size and sorted_x[j + 1] == sorted_x[i]:
            j += 1
        ranks[order[i:j + 1]] = (i + j) / 2 + 1
        i = j + 1
    return ranks


def spearman(x, y, w) -> float | None:
    """Ранговая корреляция Спирмена с весами: взвешенный Пирсон рангов.
    Разведка: рисуется точками, слов о причинах нет."""
    x = np.asarray(x, float)
    y = np.asarray(y, float)
    w = np.asarray(w, float)
    if x.size < 3:
        return None
    rx, ry = _ranks(x), _ranks(y)
    mx, my = weighted_mean(rx, w), weighted_mean(ry, w)
    cov = float(np.sum(w * (rx - mx) * (ry - my)))
    vx = float(np.sum(w * (rx - mx) ** 2))
    vy = float(np.sum(w * (ry - my) ** 2))
    if vx <= 0 or vy <= 0:
        return None
    return cov / math.sqrt(vx * vy)


# --- сравнение одной меры ---------------------------------------------

@dataclass
class Result:
    """Сравнение ветвей по одной мере."""

    describe: dict = field(default_factory=dict)   # ветвь → описание
    n_eff_cmp: dict = field(default_factory=dict)  # ветвь → n_eff в слоях
    strata: list[str] = field(default_factory=list)  # сравнимые слои
    pooled: bool = False         # слоёв нет — сравнение без слоёв
    enough: bool = False         # n_eff ≥ порога в обеих ветвях
    delta: float | None = None
    ci: tuple | None = None
    p: float | None = None
    exact: bool | None = None
    delta_all: float | None = None   # без слоёв, справочно
    diff: float | None = None        # разница средних II − I
    diff_ci: tuple | None = None


def compare(rows: list[tuple], *, seed: int, bootstrap_repeats: int,
            permutation_repeats: int, exact_limit: int, n_eff_min: float,
            groups: tuple[str, str] = (SECOND, FIRST)) -> Result:
    """Сравнивает две группы по мере.

    [rows] — (значение, вес, группа, слой); группа — «II» или «I» (или
    любые две метки из [groups]: первая — та, о которой говорит знак
    δ). Мера без значения в [rows] не попадает. Слой, где есть обе
    группы, — сравнимый; если таких нет, а группы есть обе, сравнение
    идёт без слоёв (`pooled`), и отчёт обязан сказать, что группу
    нельзя отделить от ПК."""
    second, first = groups
    res = Result()
    rows = [r for r in rows if r[1] > 0 and r[2] in groups]
    for g in groups:
        xs = [r[0] for r in rows if r[2] == g]
        ws = [r[1] for r in rows if r[2] == g]
        res.describe[g] = describe(xs, ws)
    names = sorted({r[3] for r in rows})
    strata = []
    for name in names:
        part = [r for r in rows if r[3] == name]
        s = Stratum(
            name,
            np.array([r[0] for r in part if r[2] == second], float),
            np.array([r[1] for r in part if r[2] == second], float),
            np.array([r[0] for r in part if r[2] == first], float),
            np.array([r[1] for r in part if r[2] == first], float))
        if s.comparable:
            strata.append(s)
    if not strata and res.describe[second]["n"] and \
            res.describe[first]["n"]:
        res.pooled = True
        strata = [Stratum(
            "все",
            np.array([r[0] for r in rows if r[2] == second], float),
            np.array([r[1] for r in rows if r[2] == second], float),
            np.array([r[0] for r in rows if r[2] == first], float),
            np.array([r[1] for r in rows if r[2] == first], float))]
    res.strata = [s.name for s in strata]
    res.n_eff_cmp = {
        second: n_eff(np.concatenate([s.w2 for s in strata]))
        if strata else 0.0,
        first: n_eff(np.concatenate([s.w1 for s in strata]))
        if strata else 0.0,
    }
    res.enough = bool(strata) and all(
        res.n_eff_cmp[g] >= n_eff_min for g in groups)
    if not res.enough:
        return res
    res.delta = stratified(strata)
    res.diff = stratified_diff(strata)
    res.ci, res.diff_ci = bootstrap(strata, seed, bootstrap_repeats)
    res.p, res.exact = permutation_p(strata, res.delta, seed + 1,
                                     permutation_repeats, exact_limit)
    every = [r for r in rows]
    res.delta_all = cliff([r[0] for r in every if r[2] == second],
                          [r[1] for r in every if r[2] == second],
                          [r[0] for r in every if r[2] == first],
                          [r[1] for r in every if r[2] == first])
    return res
