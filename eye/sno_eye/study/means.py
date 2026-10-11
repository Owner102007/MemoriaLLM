"""Шаг 9а — свод средних ветвей в единицах меры, g Хеджеса,
иерархический бутстреп походов, сумма О'Брайена, итог «сильнее /
слабее» (SNO-ALG-RES-10; шаг 41).

Откуда данные: те же строки «участник — значение, вес, ветвь, ПК», что
у δ (`study.compare._rows`); походы — `e["trips"]` (`study.collect`) и
`gaze_data.disorder.trips` (`study.disorder`); направления «лучше» —
`study.better` в `eye/thresholds.json` (АЛ6, утверждены владельцем
11.10.2026 до основной серии).
Технология: numpy — бутстреп и перестановки пачками; генератор
`numpy.random.default_rng` с зерном `stats.seed_for` — тот же набор
архивов даёт те же числа до бита.
Метод:
* одно число на участника, потом участники (Mumford, Nichols, 2009);
* время и частоты — среднее геометрическое и отношение «II к I»
  (Keene, 1995); у меры, где нулей больше `study.log_zero_share`, — без
  логарифма;
* разница — внутри ПК, ПК сводятся весами λₛ = W_I·W_II / (W_I + W_II),
  как у δ (по образцу van Elteren, 1960); интервал — процентильный
  бутстреп участников внутри ветви и ПК (Efron, Tibshirani, 1993); p —
  перестановки меток внутри ПК (Good, 2005; Phipson, Smyth, 2010);
* g Хеджеса — разница, делённая на объединённое внутри ПК отклонение, с
  поправкой J = 1 − 3 / (4(n₁ + n₂) − 9) (Hedges, 1981);
* походы — иерархический бутстреп: участники внутри ветви и ПК, походы
  внутри участника (Saravanan и др., 2020);
* сумма — ранговая сумма О'Брайена (O'Brien, 1984) с рангами внутри ПК;
  связанные меры делят вес (Song и др., 2013).
Вход → выход: строки меры → средние ветвей и ПК с интервалами, разница
или отношение с интервалом и p, g, интервал по походам; меры участников
→ сумма по семье; вывод сравнения → «сильнее», «слабее» или почему нет.

Слова «больше / меньше» по-прежнему решает δ (АЛ4 (а)); p разницы
средних — справочное и в поправку не идёт.
"""

from __future__ import annotations

import itertools
import math

import numpy as np

from . import stats

# Пачка повторов — как в `stats`.
_CHUNK = 2000
_EPS = 1e-12

# Меры, которые считаются на логарифмах (Keene, 1995): время и частоты —
# скошены вправо, один медленный поход тянет обычное среднее. Остальные
# — доли, шкалы теста, энтропии, наклоны, z — обычным средним.
LOG_MEASURES = frozenset({
    "actions.time_to_choice", "actions.opens_per_min",
    "actions.books_per_min", "actions.card_time",
    "actions.book_search_per_min", "actions.map_views_per_trip",
    "actions.pages_per_min", "actions.read_per_book",
    "actions.away_per_min", "actions.taps_per_min",
    "search.path", "search.fix_ms", "search.sacc_deg", "search.fix_rate",
    "reading.fix_ms", "reading.sacc_deg", "reading.fix_rate",
    "portrait.ui_trans_per_min", "portrait.cat_trans_per_min",
    "portrait.lookbacks_per_min", "portrait.page_backs_per_min",
    "portrait.search_still_s",
})

# Слова итога — и порядок списков в отчёте.
STRONGER = "сильнее"
WEAKER = "слабее"
NOT_HOLD = "не держится"
UNPROVEN = "разница не доказана"
FEW = "мало данных"
NO_ARROW = "направление не задано"
VERDICTS = (STRONGER, WEAKER, UNPROVEN, NOT_HOLD, FEW, NO_ARROW)


def _comma(x: float) -> str:
    return f"{x:.3g}".replace(".", ",")


# --- шкала -------------------------------------------------------------------

def scale_of(measure, values, cfg: dict) -> tuple[str, str]:
    """Шкала меры на этом наборе: `log` или `lin` и почему.

    Мера из `LOG_MEASURES` — `log`, если значения не отрицательны и
    нулей не больше `study.log_zero_share`: иначе отношение решала бы
    поправка нулей, а не данные. Нули, если они есть, сдвигаются на
    половину наименьшего ненулевого (Keene, 1995, — один из обычных
    приёмов; # Выбор наш: сдвиг только нулей, а не всех значений)."""
    if measure.key not in LOG_MEASURES:
        return "lin", ""
    vals = [float(v) for v in values]
    if not vals:
        return "log", ""
    if min(vals) < 0:
        return "lin", "есть отрицательные значения — без логарифма"
    zeros = sum(1 for v in vals if v == 0)
    share = float(cfg.get("log_zero_share", 0.2))
    if zeros / len(vals) > share + _EPS:
        return "lin", (f"нулей {zeros} из {len(vals)} — больше "
                       f"{_comma(share * 100)} %: без логарифма")
    if zeros:
        low = min(v for v in vals if v > 0)
        return "log", (f"к нулям ({zeros}) прибавлено 0,5 наименьшего "
                       f"ненулевого ({_comma(low)})")
    return "log", ""


def _shift(values) -> float:
    """Чем заменить ноль на логарифмической шкале: половина наименьшего
    ненулевого."""
    pos = [float(v) for v in values if v > 0]
    return min(pos) / 2 if pos else 1.0


def transform(values, scale: str, shift: float | None = None) -> np.ndarray:
    """Значения в шкале счёта: `log` — натуральный логарифм, ноль — на
    [shift]."""
    x = np.asarray(values, dtype=float)
    if scale != "log":
        return x
    if shift is None:
        shift = _shift(x)
    return np.log(np.where(x > 0, x, shift))


def back(value, scale: str):
    """Из шкалы счёта обратно в единицы меры."""
    if value is None:
        return None
    return math.exp(value) if scale == "log" else float(value)


def mean(values, weights, scale: str) -> float | None:
    """Взвешенное среднее: `lin` — Σwx / Σw; `log` — exp(Σw ln x / Σw),
    среднее геометрическое (Keene, 1995)."""
    m = stats.weighted_mean(transform(values, scale), weights)
    return back(m, scale)


# --- слои --------------------------------------------------------------------

def strata(rows, groups=(stats.SECOND, stats.FIRST)):
    """Сравнимые слои строк (значение, вес, группа, ПК), как у
    `stats.compare`: слои, где есть обе группы; таких нет, а группы есть
    обе, — один слой «все» (`pooled`)."""
    second, first = groups
    rows = [r for r in rows if r[1] > 0 and r[2] in groups]
    out = []
    for name in sorted({r[3] for r in rows}):
        part = [r for r in rows if r[3] == name]
        s = stats.Stratum(
            name,
            np.array([r[0] for r in part if r[2] == second], float),
            np.array([r[1] for r in part if r[2] == second], float),
            np.array([r[0] for r in part if r[2] == first], float),
            np.array([r[1] for r in part if r[2] == first], float))
        if s.comparable:
            out.append(s)
    pooled = False
    if not out and any(r[2] == second for r in rows) and \
            any(r[2] == first for r in rows):
        pooled = True
        out = [stats.Stratum(
            "все",
            np.array([r[0] for r in rows if r[2] == second], float),
            np.array([r[1] for r in rows if r[2] == second], float),
            np.array([r[0] for r in rows if r[2] == first], float),
            np.array([r[1] for r in rows if r[2] == first], float))]
    return out, pooled


def _on_scale(rows, scale: str):
    """Строки со значением в шкале счёта (общий сдвиг нулей на набор)."""
    shift = _shift([r[0] for r in rows]) if scale == "log" else None
    vals = transform([r[0] for r in rows], scale, shift)
    return [(float(v),) + tuple(r[1:]) for v, r in zip(vals, rows)]


# --- разница средних ---------------------------------------------------------

def _diff_draws(live, rng, repeats) -> np.ndarray:
    """Бутстреп разницы средних по слоям: участники вытягиваются
    равновероятно внутри ветви и слоя, вес идёт в среднее."""
    num = np.zeros(repeats)
    den = np.zeros(repeats)
    for s in live:
        for lo in range(0, repeats, _CHUNK):
            hi = min(repeats, lo + _CHUNK)
            a = rng.integers(0, s.x2.size, size=(hi - lo, s.x2.size))
            b = rng.integers(0, s.x1.size, size=(hi - lo, s.x1.size))
            wa, wb = s.w2[a], s.w1[b]
            W2, W1 = wa.sum(axis=1), wb.sum(axis=1)
            m = (np.sum(wa * s.x2[a], axis=1) / W2
                 - np.sum(wb * s.x1[b], axis=1) / W1)
            lam = W1 * W2 / (W1 + W2)
            num[lo:hi] += lam * m
            den[lo:hi] += lam
    return num / den


def _diff_assign(z: np.ndarray, x: np.ndarray, w: np.ndarray):
    """Разница взвешенных средних и λ для пачки разметок [z] (1 — ветвь
    II)."""
    zw = z.astype(float)
    W2 = zw @ w
    W1 = (1.0 - zw) @ w
    m = (zw @ (w * x)) / W2 - ((1.0 - zw) @ (w * x)) / W1
    return m, W1 * W2 / (W1 + W2)


def _diff_perm(live, observed: float, seed: int, repeats: int,
               exact_limit: int) -> tuple[float, bool]:
    """p перестановочного теста для разницы средних по слоям — та же
    процедура, что у δ (`stats.permutation_p`), статистика — разница."""
    target = abs(observed) - _EPS
    total = stats.permutations_total(live)
    if total <= exact_limit:
        num = np.zeros(1)
        den = np.zeros(1)
        for s in live:
            x = np.concatenate([s.x2, s.x1])
            w = np.concatenate([s.w2, s.w1])
            k = s.x2.size
            combos = list(itertools.combinations(range(x.size), k))
            z = np.zeros((len(combos), x.size), dtype=np.int8)
            for row, chosen in enumerate(combos):
                z[row, list(chosen)] = 1
            m, lam = _diff_assign(z, x, w)
            num = (num[:, None] + (lam * m)[None, :]).ravel()
            den = (den[:, None] + lam[None, :]).ravel()
        diffs = num / den
        return int(np.sum(np.abs(diffs) >= target)) / diffs.size, True
    rng = np.random.default_rng(seed)
    num = np.zeros(repeats)
    den = np.zeros(repeats)
    for s in live:
        x = np.concatenate([s.x2, s.x1])
        w = np.concatenate([s.w2, s.w1])
        base = np.zeros(x.size, dtype=np.int8)
        base[:s.x2.size] = 1
        for lo in range(0, repeats, _CHUNK):
            hi = min(repeats, lo + _CHUNK)
            z = rng.permuted(np.tile(base, (hi - lo, 1)), axis=1)
            m, lam = _diff_assign(z, x, w)
            num[lo:hi] += lam * m
            den[lo:hi] += lam
    hits = int(np.sum(np.abs(num / den) >= target))
    return (hits + 1) / (repeats + 1), False


def difference(rows, scale: str, *, seed: int, repeats: int,
               perm_repeats: int, exact_limit: int,
               groups=(stats.SECOND, stats.FIRST),
               keep_draws: bool = False) -> dict:
    """Разница средних «II − I» (`lin`) или отношение «II / I» (`log`),
    сведённая по ПК весами λₛ, с интервалом 95 % и p перестановками
    внутри ПК. Слоёв нет — пустой ответ. [keep_draws] — сохранить
    повторы бутстрепа в единицах меры (распределение на Р15)."""
    live, pooled = strata(_on_scale(rows, scale), groups)
    out = {"value": None, "ci": None, "p": None, "exact": None,
           "pooled": pooled, "log": None,
           "kind": "отношение" if scale == "log" else "разница"}
    if not live:
        return out
    d = stats.stratified_diff(live)
    if d is None:
        return out
    rng = np.random.default_rng(seed)
    draws = _diff_draws(live, rng, repeats)
    lo, hi = np.percentile(draws, 2.5), np.percentile(draws, 97.5)
    p, exact = _diff_perm(live, d, seed + 1, perm_repeats, exact_limit)
    out.update(value=back(d, scale), log=d, p=p, exact=exact,
               ci=(back(float(lo), scale), back(float(hi), scale)))
    if keep_draws:
        out["draws"] = (np.exp(draws) if scale == "log" else draws).tolist()
    return out


def sign_of(diff: dict) -> int:
    """Знак разницы средних в шкале счёта: +1 — у II больше."""
    d = diff.get("log")
    if d is None:
        return 0
    return (d > _EPS) - (d < -_EPS)


# --- средние ветвей и ПК -----------------------------------------------------

def branch_means(rows, scale: str, *, seed_parts: tuple, repeats: int,
                 groups=(stats.SECOND, stats.FIRST)) -> dict:
    """Среднее каждой ветви (взвешенное или геометрическое) с интервалом
    95 % — бутстреп участников внутри ветви, как у `stats.mean_interval`;
    рядом — среднее каждого ПК."""
    scaled = _on_scale(rows, scale)
    out = {"branch": {}, "pc": {}}
    for g in groups:
        x = [r[0] for r in scaled if r[2] == g]
        w = [r[1] for r in scaled if r[2] == g]
        ci = stats.mean_interval(x, w, stats.seed_for(*seed_parts, g),
                                 repeats) if x else None
        m = stats.weighted_mean(x, w) if x else None
        out["branch"][g] = {
            "mean": back(m, scale), "n": len(x),
            "n_eff": stats.n_eff(w) if w else 0.0,
            "ci": None if ci is None else (back(ci[0], scale),
                                           back(ci[1], scale))}
    for pc in sorted({r[3] for r in scaled}):
        out["pc"][pc] = {}
        for g in groups:
            part = [r for r in scaled if r[3] == pc and r[2] == g]
            if part:
                out["pc"][pc][g] = back(stats.weighted_mean(
                    [r[0] for r in part], [r[1] for r in part]), scale)
    return out


# --- g Хеджеса ---------------------------------------------------------------

def _cell_var(x: np.ndarray, w: np.ndarray) -> tuple[float, float] | None:
    """Несмещённая взвешенная дисперсия клетки (ПК × ветвь) с весами
    надёжности: Σw(x − x̄)² / (V₁ − V₂/V₁), V₁ = Σw, V₂ = Σw²; при весах
    1 — обычная s². Отвечает (дисперсия, n_eff − 1)."""
    V1 = float(np.sum(w))
    V2 = float(np.sum(w * w))
    if x.size < 2 or V1 <= 0:
        return None
    denom = V1 - V2 / V1
    if denom <= 0:
        return None
    m = float(np.sum(w * x)) / V1
    var = float(np.sum(w * (x - m) ** 2)) / denom
    return var, V1 * V1 / V2 - 1.0


def hedges_g(rows, scale: str, groups=(stats.SECOND, stats.FIRST)
             ) -> float | None:
    """g = J · (разница средних по ПК) / s.

    s² — дисперсия, объединённая **внутри ПК**: Σ (n_eff − 1) s²_клетки /
    Σ (n_eff − 1) по клеткам «ПК × ветвь» — иначе разница камер раздула
    бы её. J = 1 − 3 / (4(n₁ + n₂) − 9) (Hedges, 1981), n — n_eff ветвей:
    у 🟡 вес меньше. У `log` — всё на логарифмах."""
    live, _ = strata(_on_scale(rows, scale), groups)
    if not live:
        return None
    d = stats.stratified_diff(live)
    num = den = 0.0
    for s in live:
        for x, w in ((s.x2, s.w2), (s.x1, s.w1)):
            cell = _cell_var(x, w)
            if cell is None:
                continue
            var, df = cell
            num += df * var
            den += df
    if d is None or den <= 0 or num <= 0:
        return None
    sd = math.sqrt(num / den)
    # Разброса внутри ПК нет (все значения клетки одинаковы, до ошибки
    # округления) — g не определён, а не бесконечен.
    if sd <= 1e-9 * max(1.0, abs(d)):
        return None
    n2 = stats.n_eff(np.concatenate([s.w2 for s in live]))
    n1 = stats.n_eff(np.concatenate([s.w1 for s in live]))
    if 4 * (n1 + n2) - 9 <= 0:
        return None
    j = 1 - 3 / (4 * (n1 + n2) - 9)
    return j * d / sd


# --- походы: иерархический бутстреп -----------------------------------------

def _trip_values(e: dict, key: str) -> list[float]:
    """Значения походов участника для меры из походов."""
    if key == "actions.time_to_choice":
        return [t["time_to_choice_s"] for t in e.get("trips") or []
                if t.get("complete") and t.get("time_to_choice_s")
                is not None]
    if key == "actions.card_time":
        return [t["card_s"] for t in e.get("trips") or []
                if t.get("complete") and t.get("card_s") is not None]
    field = {"search.path": "path_deg", "search.straight": "straight",
             "search.returns": "returns"}.get(key)
    if field is None:
        return []
    raw = ((e.get("gaze_data") or {}).get("disorder") or {}).get("trips") \
        or []
    return [t[field] for t in raw if t.get(field) is not None]


TRIP_MEASURES = ("actions.time_to_choice", "actions.card_time",
                 "search.path", "search.straight", "search.returns")


def trip_table(entries, key: str, weight) -> dict:
    """Участник → (ветвь, ПК, вес, значения походов) для
    `hierarchical`; [weight] — вес записи в мере (0 — не идёт)."""
    out = {}
    for e in entries:
        w = weight(e)
        vals = _trip_values(e, key) if w > 0 else []
        if vals:
            code = str(e.get("participant") or e.get("archive"))
            out[code] = (e.get("branch"), e.get("stratum"), w,
                         [float(v) for v in vals])
    return out


def hierarchical(participants: dict, scale: str, *, seed: int,
                 repeats: int, groups=(stats.SECOND, stats.FIRST)
                 ) -> tuple | None:
    """Интервал 95 % разницы (или отношения) средних — иерархическим
    бутстрепом (Saravanan и др., 2020): в каждом повторе участники
    вытягиваются с возвращением внутри своей ветви и ПК, у каждого
    вытянутого — его походы с возвращением; число участника — медиана
    походов, как у самой меры; дальше — то же среднее и свод ПК, что у
    разницы средних. Проверка главной меры, а не замена: если походы
    одного участника похожи, интервал шире обычного."""
    second, first = groups
    # Медиана — в единицах меры, как у самой меры; на логарифм —
    # потом, со сдвигом нулей по значениям участников, как у точечной
    # оценки (медиана логарифмов при чётном числе походов — не логарифм
    # медианы).
    shift = _shift([float(np.median(vals)) for _, _, _, vals in
                    participants.values()]) if scale == "log" else None
    cells: dict = {}
    for code in sorted(participants):
        branch, pc, w, vals = participants[code]
        if branch not in groups:
            continue
        cells.setdefault(pc, {}).setdefault(branch, []).append(
            (w, np.asarray(vals, float)))
    live = {pc: c for pc, c in cells.items()
            if c.get(second) and c.get(first)}
    if not live:
        if any(c.get(second) for c in cells.values()) and \
                any(c.get(first) for c in cells.values()):
            live = {"все": {g: [p for c in cells.values()
                                for p in c.get(g, [])] for g in groups}}
        else:
            return None
    rng = np.random.default_rng(seed)
    num = np.zeros(repeats)
    den = np.zeros(repeats)
    for pc in sorted(live):
        sums = {}
        for g in groups:
            people = live[pc][g]
            pick = rng.integers(0, len(people), size=(repeats, len(people)))
            ws = np.array([p[0] for p in people], float)
            total_w = np.zeros(repeats)
            total = np.zeros(repeats)
            for j in range(len(people)):
                idx = pick[:, j]
                med = np.empty(repeats)
                wj = ws[idx]
                for i in range(len(people)):
                    hit = idx == i
                    k = int(hit.sum())
                    if not k:
                        continue
                    vals = people[i][1]
                    draw = rng.integers(0, vals.size, size=(k, vals.size))
                    med[hit] = np.median(vals[draw], axis=1)
                if scale == "log":
                    med = transform(med, scale, shift)
                total += wj * med
                total_w += wj
            sums[g] = (total / total_w, total_w)
        m = sums[second][0] - sums[first][0]
        W2, W1 = sums[second][1], sums[first][1]
        lam = W1 * W2 / (W1 + W2)
        num += lam * m
        den += lam
    draws = num / den
    return (back(float(np.percentile(draws, 2.5)), scale),
            back(float(np.percentile(draws, 97.5)), scale))


# --- итог «сильнее / слабее» -------------------------------------------------

def arrow(measure, cfg: dict) -> str:
    """Направление «лучше» меры: ↓, ↑ или «—» (`study.better`, АЛ6)."""
    value = (cfg.get("better") or {}).get(measure.key, "—")
    return value if value in ("↓", "↑") else "—"


def verdict(measure, words: str, stability: str, cfg: dict) -> str:
    """Куда мера идёт в итоге (АН2): «сильнее» — вывод совпал со стрелкой
    «лучше», «слабее» — против неё; только если вывод держится во всех
    сценариях устойчивости (S0–S5). Мера без стрелки в списки не идёт."""
    a = arrow(measure, cfg)
    if a == "—":
        return NO_ARROW
    if words.startswith("мало данных"):
        return FEW
    more = words.endswith("больше")
    less = words.endswith("меньше")
    if not (more or less):
        return UNPROVEN
    if stability != "устойчив":
        return NOT_HOLD
    good = (more and a == "↑") or (less and a == "↓")
    return STRONGER if good else WEAKER


# --- сумма О'Брайена ---------------------------------------------------------

def _ranks(x: np.ndarray) -> np.ndarray:
    return stats._ranks(x)


def _scores(rows: list[dict], keys: list[str], better: dict,
            merge_rho: float) -> tuple[dict, list]:
    """Веса мер и сумма каждого участника (или None) — шаги 1–2
    `obrien`."""
    shares: list[dict] = [dict() for _ in rows]
    for k in keys:
        for pc in sorted({r["stratum"] for r in rows}):
            idx = [i for i, r in enumerate(rows) if r["stratum"] == pc
                   and r["values"].get(k) is not None]
            if not idx:
                continue
            x = np.array([float(rows[i]["values"][k]) for i in idx])
            if better[k] == "↓":
                x = -x
            rk = _ranks(x)
            for i, q in zip(idx, rk):
                shares[i][k] = float(q) / len(idx)
    # Связанные меры — компоненты графа «|ρ| ≥ merge_rho».
    parent = {k: k for k in keys}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for a, b in itertools.combinations(keys, 2):
        xs, ys, ws = [], [], []
        for r in rows:
            va, vb = r["values"].get(a), r["values"].get(b)
            if va is not None and vb is not None:
                xs.append(float(va))
                ys.append(float(vb))
                ws.append(r["w"])
        rho = stats.spearman(xs, ys, ws)
        if rho is not None and abs(rho) >= merge_rho - _EPS:
            parent[find(a)] = find(b)
    groups: dict = {}
    for k in keys:
        groups.setdefault(find(k), []).append(k)
    weights = {}
    for members in groups.values():
        for k in members:
            weights[k] = 1.0 / len(groups) / len(members)
    scores = []
    for own in shares:
        have = [k for k in keys if k in own]
        if not have or len(have) * 2 < len(keys):
            scores.append(None)
            continue
        ws = sum(weights[k] for k in have)
        scores.append(sum(weights[k] * own[k] for k in have) / ws)
    return weights, scores


def _compare_scores(rows, scores, *, seed, repeats, exact_limit,
                    bootstrap_repeats, n_eff_min) -> dict:
    data = [(s, r["w"], r["branch"], r["stratum"])
            for r, s in zip(rows, scores) if s is not None]
    res = stats.compare(data, seed=seed, bootstrap_repeats=bootstrap_repeats,
                        permutation_repeats=repeats, exact_limit=exact_limit,
                        n_eff_min=n_eff_min)
    return {"n": len(data), "delta": res.delta, "ci": res.ci, "p": res.p,
            "enough": res.enough, "pooled": res.pooled,
            "n_eff": {g: res.n_eff_cmp.get(g) for g in ("II", "I")}}


def obrien(rows: list[dict], keys: list[str], better: dict, *,
           merge_rho: float, seed: int, repeats: int, exact_limit: int,
           bootstrap_repeats: int = 2000, n_eff_min: float = 0.0) -> dict:
    """Ранговая сумма О'Брайена (O'Brien, 1984) по мерам [keys].

    [rows] — участники: `branch`, `stratum` (ПК), `w` — вес, `values` —
    мера → значение. В сумму идут меры со стрелкой «лучше»:
    1. ранги участников внутри своего ПК (как у ван Эльтерена), у «↓»
       перевёрнуты — больший ранг всегда «лучше»; ранг делится на число
       участников ПК с этой мерой — доля от 0 до 1;
    2. связанные меры (|ρ| ≥ [merge_rho] на всех участниках) делят вес
       поровну (Song и др., 2013), группы связанных — между собой
       поровну; доли участника усредняются с этими весами по мерам, что
       у него есть; у кого есть меньше половины мер, тот в сумму не идёт;
    3. сумма участника сравнивается между ветвями δ Клиффа по ПК с
       перестановками внутри ПК — так же, как каждая мера.
    δ > 0 — у ветви II сумма лучше."""
    keys = [k for k in keys if better.get(k) in ("↓", "↑")]
    rows = [r for r in rows if r["w"] > 0]
    out = {"measures": keys, "weights": {}, "delta": None, "ci": None,
           "p": None, "n": 0, "enough": False, "scores": []}
    if not keys or not rows:
        return out
    weights, scores = _scores(rows, keys, better, merge_rho)
    out["weights"] = weights
    out["scores"] = scores
    out.update(_compare_scores(rows, scores, seed=seed, repeats=repeats,
                               exact_limit=exact_limit,
                               bootstrap_repeats=bootstrap_repeats,
                               n_eff_min=n_eff_min))
    return out


def obrien_total(rows: list[dict], families: dict, *, seed: int,
                 repeats: int, exact_limit: int,
                 bootstrap_repeats: int = 2000,
                 n_eff_min: float = 0.0) -> dict:
    """Общая сумма — семьи с равными весами (АЛ6 (а), «по умолчанию
    семьи равны»): у участника — среднее сумм его семей; участник, у
    кого сумм меньше половины семей, не идёт. [families] — семья →
    результат `obrien` по тем же [rows]."""
    rows = [r for r in rows if r["w"] > 0]
    live = {f: own for f, own in families.items() if own.get("scores")}
    scores = []
    for i in range(len(rows)):
        have = [own["scores"][i] for own in live.values()
                if own["scores"][i] is not None]
        if not live or len(have) * 2 < len(live):
            scores.append(None)
        else:
            scores.append(sum(have) / len(have))
    out = {"families": sorted(live)}
    out.update(_compare_scores(rows, scores, seed=seed, repeats=repeats,
                               exact_limit=exact_limit,
                               bootstrap_repeats=bootstrap_repeats,
                               n_eff_min=n_eff_min))
    return out
