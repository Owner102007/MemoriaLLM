"""Порядок обхода библиотеки (SNO-ALG-RES-11; шаг 43).

Откуда данные: походы за книгой (`study.actions`, строки `trips`
записи: книга — отпечаток файла, через что открыта, первое ли
обращение), полка на старте (`snapshot_start.json` →
`study.gaze.shelf_layout`: категории по порядку, книги с местом),
карта (`galaxy.open` журнала → `study.gaze.map_of`: звезда — отпечаток
книги и её координаты; одна карта на набор литературы, поэтому её
берут у любой записи с тем же набором книг — и меряют на ней и тех,
кто карту не открывал).
Технология: numpy — случайные перестановки.
Метод:
* последовательность — книги в порядке первого открытия за изучение;
* место на полке — сквозное: категории по порядку снимка начала,
  внутри — по месту;
* высота на карте — `y` звезды (на экране вниз растёт, `screenY` в
  `lib/domain/map/map_view.dart`);
* ρ Спирмена порядка открытия с местом на полке и с высотой звезды —
  внутри каждой категории, где открыто не меньше
  `study.order.min_category_books` книг, затем среднее по категориям;
* длина маршрута по полке (Σ |Δ места|) и по карте (Σ расстояний между
  звёздами) — к средней длине `study.permutations` случайных
  перестановок того же набора книг; p — доля перестановок не длиннее
  настоящей, с поправкой «+1» (Phipson B., Smyth G. K. «Permutation
  P-values should never be zero», SAGMB, 2010, 9(1):39); зерно — от
  отпечатка набора и кода участника (`stats.seed_for`);
* смен категории за обход; доля переходов к соседней книге полки;
* стратегия словами — пороги `study.order`.
Вход → выход: записи → у каждой `order` (последовательность, меры, p,
стратегия) и меры `order.*` для отчёта и проверок одной группы.
"""

from __future__ import annotations

import math

import numpy as np

from . import stats

SHELF = "по порядку полки"
MAP = "по карте"
MAP_DOWN = "по карте сверху вниз"
SELECTIVE = "выборочно"
TOO_FEW = "мало книг"

DEFAULTS = {
    # ρ с полкой (или с высотой звезды) не меньше — «по порядку».
    "rho": 0.8,
    # p маршрута меньше — маршрут не случаен.
    "alpha": 0.05,
    # Книг в категории для ρ внутри неё.
    "min_category_books": 4,
    # Книг для маршрута.
    "min_books": 4,
}


def settings(raw: dict | None) -> dict:
    out = dict(DEFAULTS)
    for key, default in DEFAULTS.items():
        value = (raw or {}).get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            out[key] = value
    return out


def sequence(e: dict) -> list[tuple[str, str | None]]:
    """Книги в порядке первого открытия за изучение: (отпечаток, через
    что открыта)."""
    out = []
    seen: set[str] = set()
    for t in e.get("trips") or []:
        book = t.get("book")
        if not t.get("complete") or not isinstance(book, str) or \
                book in seen:
            continue
        seen.add(book)
        out.append((book, t.get("via")))
    return out


def shelf_places(layout: dict | None) -> dict[str, tuple[int, str]]:
    """Отпечаток → (сквозное место на полке, категория)."""
    if not layout:
        return {}
    order = {name: (pos, i) for i, (name, pos) in
             enumerate(layout.get("categories") or [])}
    books = sorted(layout.get("books") or [],
                   key=lambda b: (order.get(b[2], (math.inf, math.inf)),
                                  b[3], b[1], b[0]))
    return {b[0]: (i, b[2]) for i, b in enumerate(books)}


def map_places(chart: dict | None) -> dict[str, tuple[float, float, str]]:
    """Отпечаток → (x, y, группа) звезды."""
    out = {}
    for p in (chart or {}).get("points") or []:
        out[p["book"]] = (float(p["x"]), float(p["y"]),
                          str(p.get("group") or ""))
    return out


def literature_maps(entries: list[dict]) -> list[dict]:
    """Карты набора: у каждой записи, открывавшей «Галактику», — своя
    `map`; один набор книг — одна карта (SNO-ALG-RES-04, шаг 4)."""
    seen: dict[str, dict] = {}
    for e in entries:
        chart = e.get("map")
        if chart and chart.get("points") and chart["key"] not in seen:
            seen[chart["key"]] = chart
    return list(seen.values())


def map_for(e: dict, maps: list[dict]) -> dict | None:
    """Карта для записи: своя, а нет — та, что накрывает больше всего её
    книг полки (тот же набор литературы)."""
    if e.get("map") and e["map"].get("points"):
        return e["map"]
    books = {b[0] for b in (e.get("shelf_layout") or {}).get("books") or []}
    best, cover = None, 0
    for chart in maps:
        have = {p["book"] for p in chart["points"]}
        n = len(books & have)
        if n > cover and n >= 0.9 * max(1, len(books)):
            best, cover = chart, n
    return best


def spearman(a: list[float], b: list[float]) -> float | None:
    """ρ Спирмена — Пирсон рангов с ничьими по среднему рангу."""
    if len(a) < 2:
        return None
    w = np.ones(len(a))
    return stats.spearman(a, b, w) if len(a) >= 3 else None


def within(seq: list[str], value: dict, group: dict, minimum: int
           ) -> float | None:
    """ρ порядка открытия со значением книги внутри каждой группы, где
    открыто не меньше [minimum] книг, — среднее по группам."""
    rhos = []
    by: dict[str, list[str]] = {}
    for book in seq:
        if book in value:
            by.setdefault(group[book], []).append(book)
    for books in by.values():
        if len(books) < minimum:
            continue
        rho = spearman(list(range(len(books))), [value[b] for b in books])
        if rho is not None:
            rhos.append(rho)
    return float(np.mean(rhos)) if rhos else None


def route(points: np.ndarray, repeats: int, seed: int
          ) -> tuple[float, float, float] | None:
    """Длина маршрута по [points] (строка — книга в порядке открытия;
    столбец — координата) к средней длине случайных перестановок и p.

    Ответ — (отношение, длина, p)."""
    n = len(points)
    if n < 2:
        return None

    def length(order_pts: np.ndarray) -> np.ndarray:
        d = np.diff(order_pts, axis=-2)
        return np.sqrt((d ** 2).sum(axis=-1)).sum(axis=-1)

    real = float(length(points))
    rng = np.random.default_rng(seed)
    idx = np.argsort(rng.random((repeats, n)), axis=1)
    lengths = length(points[idx])
    mean = float(lengths.mean())
    if mean <= 0:
        return None
    p = (int(np.sum(lengths <= real + 1e-9)) + 1) / (repeats + 1)
    return real / mean, real, p


def analyse(e: dict, maps: list[dict], cfg: dict, fingerprint: str
            ) -> dict:
    """Порядок обхода одной записи."""
    oc = settings(cfg.get("order"))
    repeats = int(cfg.get("permutations", 10_000))
    seq_via = sequence(e)
    seq = [b for b, _ in seq_via]
    shelf = shelf_places(e.get("shelf_layout"))
    chart = map_for(e, maps)
    stars = map_places(chart)
    who = str(e.get("participant") or e.get("archive"))
    out: dict = {"books": len(seq), "sequence": seq,
                 "via": [v for _, v in seq_via],
                 "map_key": (chart or {}).get("key")}
    on_shelf = [b for b in seq if b in shelf]
    out["shelf_places"] = [shelf[b][0] + 1 for b in on_shelf]
    if len(on_shelf) >= 2:
        places = [shelf[b][0] for b in on_shelf]
        steps = [abs(b - a) for a, b in zip(places, places[1:])]
        out["adjacent_share"] = sum(1 for s in steps if s == 1) / len(steps)
        cats = [shelf[b][1] for b in on_shelf]
        out["cat_switches"] = sum(1 for a, b in zip(cats, cats[1:])
                                  if a != b)
        out["rho_shelf"] = within(on_shelf, {b: shelf[b][0] for b in shelf},
                                  {b: shelf[b][1] for b in shelf},
                                  int(oc["min_category_books"]))
    if len(on_shelf) >= int(oc["min_books"]):
        res = route(np.array([[float(shelf[b][0])] for b in on_shelf]),
                    repeats, stats.seed_for(fingerprint, "order", who,
                                            "shelf"))
        if res:
            out["route_shelf"], out["length_shelf"], out["p_shelf"] = res
    on_map = [b for b in seq if b in stars]
    out["map_heights"] = [stars[b][1] for b in on_map]
    if len(on_map) >= 2:
        out["rho_map"] = within(on_map, {b: stars[b][1] for b in stars},
                                {b: stars[b][2] for b in stars},
                                int(oc["min_category_books"]))
        groups = [stars[b][2] for b in on_map]
        out["map_switches"] = sum(1 for a, b in zip(groups, groups[1:])
                                  if a != b)
    if len(on_map) >= int(oc["min_books"]):
        res = route(np.array([[stars[b][0], stars[b][1]] for b in on_map]),
                    repeats, stats.seed_for(fingerprint, "order", who,
                                            "map"))
        if res:
            out["route_map"], out["length_map"], out["p_map"] = res
    out["strategy"] = strategy(out, e.get("search_mode"), oc)
    return out


def strategy(o: dict, mode: str | None, oc: dict) -> str:
    """Стратегия словами (SNO-ALG-RES-11, шаг 5)."""
    from .actions import MODE_MAP
    if o["books"] < int(oc["min_books"]):
        return TOO_FEW
    alpha = float(oc["alpha"])
    rho = float(oc["rho"])
    if mode == MODE_MAP:
        if o.get("p_map") is not None and o["p_map"] < alpha:
            return MAP_DOWN if (o.get("rho_map") or -1) >= rho else MAP
        return SELECTIVE
    if (o.get("rho_shelf") or -1) >= rho and o.get("p_shelf") is not None \
            and o["p_shelf"] < alpha:
        return SHELF
    return SELECTIVE


def finish(entries: list[dict], cfg: dict, fingerprint: str) -> None:
    """Порядок обхода у каждой годной записи и меры `order.*`."""
    maps = literature_maps(entries)
    for e in entries:
        if e.get("status") != "ok":
            continue
        o = analyse(e, maps, cfg, fingerprint)
        e["order"] = o
        e["order_measures"] = {
            "order.books": o["books"],
            "order.adjacent_share": o.get("adjacent_share"),
            "order.rho_shelf": o.get("rho_shelf"),
            "order.rho_map": o.get("rho_map"),
            "order.route_shelf": o.get("route_shelf"),
            "order.p_shelf": o.get("p_shelf"),
            "order.route_map": o.get("route_map"),
            "order.p_map": o.get("p_map"),
            "order.cat_switches": o.get("cat_switches"),
            "order.map_switches": o.get("map_switches"),
        }
