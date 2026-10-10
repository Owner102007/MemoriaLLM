"""Шаг 7 — средний взгляд ветви и научение (SNO-ALG-RES-04).

Откуда данные: `gaze_data` записей (`study.gaze`) — доли времени и ход
по минутам «Разбора записи», переходы фазы «всё изучение» и пути
походов (`study.disorder`), время поиска на книгах полки, фиксации на
карте в координатах карты, переходы между категориями; походы за
книгой и время до выбора — `study.actions`; вес участника — цвет
искренности (`study.honesty`) по правилу сценария S0
(`study.compare.scenario_weight`).
Технология: numpy — взвешенные средние, матрицы, сетка тепловой карты
с гауссовыми пятнами, наклон прямой наименьшими квадратами.
Метод: среднее ветви везде взвешенное, `Σ wᵢ · xᵢ / Σ wᵢ`; у 🔴 вес 0.
Это описание ветви, а не сравнение: слои ПК здесь не учитываются.
Кривая научения — закон степени научения: Newell A., Rosenbloom P.
«Mechanisms of skill acquisition and the law of practice». В кн.:
Anderson J. R. (ред.) «Cognitive Skills and Their Acquisition».
Erlbaum, 1981, с. 1–55: `log y = a + b · log(номер похода)`, `b` —
наклон участника.
Вход → выход: записи после отбора → средние ветвей для рисунков
Р7–Р12 и наклоны научения участников (`learn.*`) для сравнения.
"""

from __future__ import annotations

import numpy as np

from ..report.measures import MINUTE_GROUPS
from ..report.zones import BUCKETS
from . import disorder
from .gaze import NO_CATEGORY

BRANCHES = ("I", "II")
GROUP_WORDS = {key: words for key, words, _ in MINUTE_GROUPS}
GROUP_OF = {b: key for key, _, members in MINUTE_GROUPS for b in members}

# Клеток тепловой карты по длинной стороне.
HEAT_CELLS = 160


# --- наклон научения ---------------------------------------------------------

def slope(values: list[tuple[int, float]], minimum: int) -> float | None:
    """Наклон `b` прямой `log y = a + b · log n` наименьшими квадратами;
    [values] — пары (номер похода, y). Нуль и меньше в логарифм не идут.
    Меньше [minimum] точек — пусто."""
    pts = [(n, y) for n, y in values if n > 0 and y is not None and y > 0]
    if len(pts) < minimum:
        return None
    x = np.log([n for n, _ in pts])
    y = np.log([v for _, v in pts])
    xm = x.mean()
    sxx = float(((x - xm) ** 2).sum())
    if sxx <= 0:
        return None
    return float(((x - xm) * (y - y.mean())).sum() / sxx)


def choice_series(e: dict) -> list[tuple[int, float]]:
    """Время до выбора книги по номеру доведённого похода, с."""
    rows = [t for t in e.get("trips") or [] if t.get("complete")]
    return [(i + 1, t["time_to_choice_s"]) for i, t in enumerate(rows)]


def repeat_series(e: dict) -> list[tuple[int, float]]:
    """То же только для походов к уже открывавшейся книге — по номеру
    такого похода."""
    rows = [t for t in e.get("trips") or [] if t.get("complete")
            and t.get("first_time") is False]
    return [(i + 1, t["time_to_choice_s"]) for i, t in enumerate(rows)]


def path_series(e: dict) -> list[tuple[int, float]]:
    """Путь взгляда по номеру доведённого похода, градусы."""
    data = e.get("gaze_data") or {}
    trips = (data.get("disorder") or {}).get("trips") or []
    return [(t["i"], t["path_deg"]) for t in trips]


def learning(entries: list[dict], cfg: dict) -> None:
    """Наклоны научения участников — мера участника, идёт в
    сравнение: по времени до выбора книги (есть у всех, из журнала) и по
    пути взгляда (у вошедших со взглядом)."""
    minimum = int(cfg["min_visits_curve"])
    for e in entries:
        own = e.setdefault("learn", {})
        if e.get("status") != "ok":
            continue
        own["learn.choice_slope"] = slope(choice_series(e), minimum)
        # Путь — на фиксациях общим порогом: у сессии вне М1–М7
        # (`disorder_gate`) наклона пути нет.
        if e.get("disorder_live"):
            own["learn.path_slope"] = slope(path_series(e), minimum)


# --- взвешенные средние ------------------------------------------------------

def wquantile(x, w, q: float) -> float | None:
    """Взвешенный квантиль: значение, на котором накопленный вес
    доходит до доли [q]; медиана (q = 0,5) — `stats.weighted_median`:
    при весе ровно в половину — середина между соседями, как у обычной
    медианы."""
    if q == 0.5:
        from .stats import weighted_median
        return weighted_median(list(x), list(w))
    pairs = sorted((float(a), float(b)) for a, b in zip(x, w) if b > 0)
    if not pairs:
        return None
    total = sum(b for _, b in pairs)
    acc = 0.0
    for a, b in pairs:
        acc += b
        if acc >= q * total - 1e-12:
            return a
    return pairs[-1][0]


def _wmean(x, w) -> float | None:
    sw = sum(w)
    return sum(a * b for a, b in zip(x, w)) / sw if sw > 0 else None


def build(entries: list[dict], cfg: dict, no_filter: bool,
          series: str | None) -> dict:
    """Средний взгляд ветвей и кривые научения — для рисунков Р7–Р12."""
    from .compare import scenario_weight
    min_n = int(cfg["min_minute_participants"])

    def gaze_weight(e):
        # Доли и минуты — по кадрам раскладки: без них зон нет.
        if not (e.get("gaze_data") or {}).get("layout"):
            return 0.0
        return scenario_weight(e, "S0", cfg, no_filter, series, True)

    def plain_weight(e):
        return scenario_weight(e, "S0", cfg, no_filter, series, False)

    out: dict = {"shares": {}, "minutes": {}, "matrix": {},
                 "categories": {}, "heat": [], "shelf": {},
                 "curve": {}, "n_gaze": {}}
    for b in BRANCHES:
        part = [(e, gaze_weight(e)) for e in entries
                if e.get("branch") == b and e.get("status") == "ok"]
        part = [(e, w) for e, w in part if w > 0]
        out["n_gaze"][b] = len(part)
        out["shares"][b] = _shares(part)
        out["minutes"][b] = _minutes(part, min_n)
        # Матрица фазы «всё изучение» — на фиксациях общим порогом:
        # сессия, отсечённая по шуму (`disorder_gate`), в неё не идёт.
        out["matrix"][b] = _matrix([(e, w) for e, w in part
                                    if e.get("disorder_live")])
        out["categories"][b] = _category_matrix(part)
        out["shelf"][b] = _shelf(part)
        plain = [(e, plain_weight(e)) for e in entries
                 if e.get("branch") == b and e.get("status") == "ok"]
        plain = [(e, w) for e, w in plain if w > 0]
        out["curve"][b] = {
            "choice": _curve([(choice_series(e), w) for e, w in plain],
                             min_n),
            "repeat": _curve([(repeat_series(e), w) for e, w in plain
                              if len(repeat_series(e)) >=
                              int(cfg["min_repeat_visits"])], min_n),
            "path": _curve([(path_series(e), w) for e, w in part
                            if e.get("disorder_live")],
                           min_n),
        }
    out["heat"] = _heat(entries, gaze_weight)
    return out


def _shares(part: list) -> dict:
    """Шаг 1 — доли времени изучения по видам зон и по пяти группам
    (мягко); сумма долей ветви остаётся равной 1."""
    if not part:
        return {}
    w = [x for _, x in part]
    kinds = {k: _wmean([e["gaze_data"]["shares"].get(k, 0.0)
                        for e, _ in part], w) for k, _ in BUCKETS}
    groups = {key: 0.0 for key in GROUP_WORDS}
    for k, v in kinds.items():
        groups[GROUP_OF.get(k, "other")] += v or 0.0
    return {"kinds": kinds, "groups": groups, "n": len(part)}


def _minutes(part: list, min_n: int) -> dict:
    """Шаг 2 — ход по минутам: взвешенное среднее и полоса между 25-м и
    75-м процентилями; минута, где участников меньше [min_n], не
    рисуется."""
    by_minute: dict[int, list] = {}
    for e, w in part:
        for row in e["gaze_data"]["minutes"]:
            by_minute.setdefault(int(row["minute"]), []).append((row, w))
    out = {key: [] for key in GROUP_WORDS}
    for minute in sorted(by_minute):
        rows = by_minute[minute]
        if len(rows) < min_n:
            continue
        ws = [w for _, w in rows]
        for key in GROUP_WORDS:
            xs = [r.get(key, 0.0) for r, _ in rows]
            out[key].append((minute, _wmean(xs, ws), wquantile(xs, ws, 0.25),
                             wquantile(xs, ws, 0.75), len(rows)))
    return out


def _matrix(part: list) -> dict:
    """Шаг 3 — матрица переходов ветви фазы «всё изучение» между пятью
    группами: счётчики участника нормируются к сумме 1, умножаются на
    его вес и складываются; только потом строки делятся на свои суммы.
    Так участник без какой-то строки (не открывал карту) среднее не
    ломает."""
    zones = disorder.ALL_ZONES
    n = len(zones)
    total = np.zeros((n, n))
    used = 0
    for e, w in part:
        trans = e["gaze_data"]["disorder"]["phases"][disorder.ALL][
            "transitions"]
        if not trans:
            continue
        arr = np.asarray(trans, dtype=np.int64)
        counts = np.bincount(arr[:, 0] * n + arr[:, 1],
                             minlength=n * n).reshape(n, n).astype(float)
        total += w * counts / counts.sum()
        used += 1
    rows = total.sum(axis=1, keepdims=True)
    with np.errstate(invalid="ignore", divide="ignore"):
        p = np.where(rows > 0, total / np.where(rows > 0, rows, 1), np.nan)
    return {"zones": [GROUP_WORDS[z] for z in zones], "p": p.tolist(),
            "n": used}


def _category_matrix(part: list) -> dict:
    """Рядом — та же матрица поиска по категориям полки и группам карты.
    Выбор наш: по категориям, а не по книгам и звёздам — книги у ветвей
    одни, но на полке и на карте они разные зоны, а категории общие."""
    names: list[str] = []
    for e, _ in part:
        for a, b in e["gaze_data"]["category_pairs"]:
            for x in (a, b):
                if x not in names:
                    names.append(x)
    names.sort(key=lambda x: (x == NO_CATEGORY, x))
    n = len(names)
    if not n:
        return {"zones": [], "p": [], "n": 0}
    index = {x: i for i, x in enumerate(names)}
    total = np.zeros((n, n))
    used = 0
    for e, w in part:
        pairs = e["gaze_data"]["category_pairs"]
        if not pairs:
            continue
        counts = np.zeros((n, n))
        for a, b in pairs:
            counts[index[a], index[b]] += 1
        total += w * counts / counts.sum()
        used += 1
    rows = total.sum(axis=1, keepdims=True)
    with np.errstate(invalid="ignore", divide="ignore"):
        p = np.where(rows > 0, total / np.where(rows > 0, rows, 1), np.nan)
    return {"zones": names, "p": p.tolist(), "n": used}


def _shelf(part: list) -> dict:
    """Шаг 5 — схема полки: пиксели не складываются (окна разных ПК
    разной ширины), складываются доли времени поиска на каждой книге и
    на шапке каждой категории. Категории — объединение наборов
    участников; категории, которой у участника не было, — у него пустое
    место, а не ноль."""
    cats: dict[str, float] = {}
    books: dict[str, tuple] = {}
    for e, _ in part:
        layout = e.get("shelf_layout") or {}
        for name, order in layout.get("categories") or []:
            cats[name] = min(order, cats.get(name, order))
        for fp, title, cat, pos in layout.get("books") or []:
            if fp not in books or (cat, pos) < books[fp][1:3]:
                books[fp] = (title, cat, pos)
            cats.setdefault(cat, 1e9)
    order = sorted(cats, key=lambda c: (cats[c], c))
    rows = []
    for cat in order:
        own = sorted((fp for fp, v in books.items() if v[1] == cat),
                     key=lambda fp: (books[fp][2], books[fp][0], fp))
        values = {}
        for key in ["header:" + cat] + own:
            xs, ws = [], []
            for e, w in part:
                layout = e.get("shelf_layout") or {}
                has = {c for c, _ in layout.get("categories") or []} | \
                    {b[2] for b in layout.get("books") or []}
                time = e["gaze_data"]["shelf_time"]
                if cat not in has or time["total_ms"] <= 0:
                    continue
                if key.startswith("header:"):
                    ms = time["header"].get(cat, 0.0)
                else:
                    ms = time["book"].get(key, 0.0)
                xs.append(ms / time["total_ms"])
                ws.append(w)
            values[key] = _wmean(xs, ws) if xs else None
        rows.append({"category": cat, "books": [
            {"book": fp, "title": books[fp][0], "share": values[fp]}
            for fp in own], "header": values["header:" + cat]})
    return {"rows": rows, "n": len(part)}


def _curve(series: list[tuple[list, float]], min_n: int) -> list:
    """Кривая ветви — взвешенная медиана по номеру похода; номер, где
    участников меньше [min_n], не рисуется."""
    by_n: dict[int, list] = {}
    for values, w in series:
        for n, y in values:
            if y is not None:
                by_n.setdefault(n, []).append((y, w))
    out = []
    for n in sorted(by_n):
        rows = by_n[n]
        if len(rows) < min_n:
            continue
        out.append((n, wquantile([y for y, _ in rows],
                                 [w for _, w in rows], 0.5), len(rows)))
    return out


def _heat(entries: list[dict], weight) -> list[dict]:
    """Шаг 4 — тепловая карта «Галактики»: фиксации поиска на полотне
    карты в координатах карты (приближение и сдвиг карты не мешают),
    каждая — гауссово пятно весом в её длительность и радиусом в
    точность сессии; карта участника нормируется к сумме 1, карта ветви
    — взвешенное среднее карт участников. Карта у всех одна, если
    одинаков набор книг; встретилось несколько — на каждую своя."""
    maps: dict[str, dict] = {}
    for e in entries:
        data = e.get("gaze_data") or {}
        known = data.get("map")
        w = weight(e)
        if not known or w <= 0 or not data.get("map_fix"):
            continue
        own = maps.setdefault(known["key"], {
            "key": known["key"], "points": known["points"], "people": {}})
        own["people"].setdefault(e.get("branch"), []).append(
            (e, w, data["map_fix"]))
    out = []
    for key in sorted(maps):
        item = maps[key]
        xs = [p["x"] for p in item["points"]]
        ys = [p["y"] for p in item["points"]]
        span = max(max(xs) - min(xs), max(ys) - min(ys), 1e-6)
        pad = 0.12 * span
        x0, x1 = min(xs) - pad, max(xs) + pad
        y0, y1 = min(ys) - pad, max(ys) + pad
        if x1 - x0 >= y1 - y0:
            nx = HEAT_CELLS
            ny = max(20, int(round(HEAT_CELLS * (y1 - y0) / (x1 - x0))))
        else:
            ny = HEAT_CELLS
            nx = max(20, int(round(HEAT_CELLS * (x1 - x0) / (y1 - y0))))
        gx = np.linspace(x0, x1, nx)
        gy = np.linspace(y0, y1, ny)
        X, Y = np.meshgrid(gx, gy)
        branches = {}
        for branch, people in sorted(item["people"].items(),
                                     key=lambda kv: str(kv[0])):
            acc = np.zeros_like(X)
            total_w = 0.0
            marked = 0
            for e, w, fixes in people:
                grid = np.zeros_like(X)
                for mx, my, ms, r in fixes:
                    s = max(r, 1e-6)
                    grid += ms * np.exp(-((X - mx) ** 2 + (Y - my) ** 2)
                                        / (2 * s * s))
                if grid.sum() <= 0:
                    continue
                acc += w * grid / grid.sum()
                total_w += w
                if e.get("etalon") not in (None, "да"):
                    marked += 1
            if total_w > 0:
                branches[branch] = {"grid": (acc / total_w).tolist(),
                                    "n": len(people),
                                    "not_reference": marked}
        if branches:
            out.append({"key": key, "points": item["points"],
                        "extent": [x0, x1, y0, y1], "branches": branches})
    return out
