"""«Перед нажатием» — что было под взглядом перед каждым выбором
источника (BUG-64, правка шага 34; SNO-F-RES-03, SNO-ALG-EYE-05).

Владелец 10.10.2026: «Во время записи специально смотрел на категорию
в галактике и потом почти сразу нажимал на неё. Это главное, что мы
отслеживаем». Мера — на каждое нажатие:

* **по звезде карты** (`galaxy.star`), **по книге полки** и **по
  строке найденного** (`book.open` с полки и из поиска по названию);
* нужная категория — категория нажатой книги;
* что было под взглядом — медиана взгляда за 300–100 мс до нажатия
  (то же окно, что у неявных точек, и та же версия взгляда, что у мер),
  отнесённая к зоне по кадру раскладки: категория полки или карты
  «уверенно / на границе», книга полки или звезда карты;
* расстояние от этой точки до места нажатия, в градусах: нажатие,
  перед которым смотрели на подпись категории, а не на звезду, лежит
  в градусах от взгляда — для поправки дрейфа это «нажал не глядя», а
  здесь — искомое;
* была ли под взглядом нужная категория (строго — «уверенно», мягко —
  и на границе);
* сколько до нажатия взгляд уже был в нужной категории: от начала
  последнего непрерывного захода фиксаций в неё до нажатия, но не
  раньше прежнего нажатия того же похода и не раньше начала похода.
  Заход рвут фиксация вне нужной категории, фиксация на отрезке
  движения раскладки вне неё и просвет между фиксациями дольше
  `press_gap_ms` (дольше моргания: лицо пропало, взгляд ушёл с экрана);
  последняя фиксация до нажатия не в нужной категории или кончилась
  раньше чем за `press_gap_ms` до него — пусто.

У строки найденного (поиск по названию) категория под взглядом — та,
что стоит под названием в строке: поиск по названию — не полка, и
шагам похода по полке категория строки не засчитывается, а нажатию —
засчитывается.

Без взгляда, без кадров раскладки, после смены окна, без годных кадров
в окне и без строки нажатия в потоке ввода ячейки взгляда пусты, а не
нули: миг события открытия книги — уже после открытия.
"""

from __future__ import annotations

import bisect
import math
import statistics

from .idt import Fixation
from .measures import margin_deg
from .screen import Screen
from .timeline import Timeline
from .versions import Sample

# Что нажато: вид события, способ открытия → (экран, слово).
WHAT = {
    "galaxy.star": ("galaxy", "звезда"),
    "shelf": ("shelf", "книга полки"),
    "shelf_search": ("shelf", "строка найденного"),
}


def _int(value) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return int(value)


def _num(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) else None


def _pressed(record) -> list[dict]:
    """Нажатия по источникам в журнале: миг, место и книга."""
    out = []
    seen: set[int] = set()
    for event in record.events:
        kind = event.get("type")
        data = event.get("data") if isinstance(event.get("data"),
                                               dict) else {}
        if kind == "galaxy.star":
            what = "galaxy.star"
            book = data.get("book")
        elif kind == "book.open" and data.get("via") in ("shelf",
                                                         "shelf_search"):
            what = data["via"]
            book = event.get("book")
        else:
            continue
        if not isinstance(book, str):
            continue
        n = _int(event.get("input"))
        row = record.inputs.get(n) if n is not None else None
        if n is not None and n in seen:
            continue
        if n is not None:
            seen.add(n)
        t = _num(row.get("t")) if row else None
        x = _num(row.get("x")) if row else None
        y = _num(row.get("y")) if row else None
        known = t is not None
        if not known:
            # Нажатия в потоке ввода нет — миг события только для
            # порядка: взгляд по нему не берётся.
            t, x, y = _num(event.get("t")), None, None
            if t is None:
                continue
        out.append({"kind": kind, "what": what, "book": book, "t": t,
                    "x": x, "y": y, "input": n, "known": known})
    out.sort(key=lambda p: p["t"])
    return out


def _visit_of(timeline: Timeline, t: float, screen: str):
    for visit in timeline.visits:
        if visit.screen == screen and visit.start <= t <= visit.end + 200:
            return visit
    return None


def _lead(t: float, since: float, target: str, fixes: list[Fixation],
          zones: list[dict], strict: bool, gap: float) -> float | None:
    """Сколько до нажатия в миг [t] взгляд уже был в категории [target]
    — непрерывным заходом фиксаций не раньше [since]; просвет дольше
    [gap] заход рвёт."""
    first = None
    edge = t
    for fix, z in sorted(zip(fixes, zones), key=lambda p: -p[0].start):
        if fix.start >= t:
            continue
        if fix.end < since or edge - fix.end > gap:
            break
        inside = z.get("category") == target and \
            (not strict or z.get("category_sure"))
        if not inside:
            break
        if not fix.moving:
            first = max(fix.start, since)
        edge = fix.start
    return None if first is None else t - first


def presses(record, timeline: Timeline, samples: list[Sample] | None,
            fixes: list[Fixation], found: list[dict], zones,
            screen: Screen, cfg: dict, gaze: bool,
            zoned: bool) -> list[dict]:
    """Таблица «Перед нажатием»: строка на нажатие по источнику."""
    lo, hi = timeline.study_start, timeline.study_end
    times = [s.t for s in samples] if samples else []
    before = float(cfg["pair_from_ms"])
    after = float(cfg["pair_to_ms"])
    need = int(cfg["pair_min_samples"])
    changed = timeline.window_changed
    rows = []
    last: dict[int, float] = {}
    for press in _pressed(record):
        t = press["t"]
        if not lo <= t <= hi:
            continue
        where, word = WHAT[press["what"]]
        target = timeline.categories.get(press["book"])
        row = {
            "n": len(rows) + 1, "t": t, "study_ms": t - lo,
            "screen": where, "kind": press["kind"], "what": word,
            "book": press["book"],
            "title": timeline.titles.get(press["book"]),
            "target": target, "x": press["x"], "y": press["y"],
            "zone": None, "bucket": None, "category": None,
            "category_sure": None, "star": None, "shelf_book": None,
            "distance_deg": None, "in_target_strict": None,
            "in_target_soft": None, "lead_ms_strict": None,
            "lead_ms_soft": None,
        }
        rows.append(row)
        visit = _visit_of(timeline, t, where)
        since = visit.start if visit is not None else lo
        key = id(visit)
        if key in last:
            since = max(since, last[key])
        last[key] = t
        if not gaze or not zoned or zones is None or not press["known"] \
                or (changed is not None and t >= changed):
            continue
        i = bisect.bisect_left(times, t - before)
        j = bisect.bisect_right(times, t - after)
        window = [s for s in samples[i:j] if s.ok]
        if len(window) < need:
            continue
        gx = statistics.median(s.x for s in window)
        gy = statistics.median(s.y for s in window)
        margin = screen.px_for_deg(margin_deg(t, timeline))
        z = zones.classify(t - (before + after) / 2, gx, gy, margin)
        category = z.get("category")
        sure = z.get("category_sure")
        book = z.get("book")
        info = z.get("info") or {}
        if z.get("zone") == "shelf_book" and info.get("in") == "results":
            # Строка найденного: категория — под названием в строке.
            category = info.get("category") \
                if isinstance(info.get("category"), str) else None
            sure = bool(z.get("sure")) and category is not None
            book = z.get("id") or None
        row.update({
            "zone": z.get("zone"), "bucket": z.get("bucket"),
            "category": category, "category_sure": sure,
            "star": z.get("mark"), "shelf_book": book,
            "gaze_x": gx, "gaze_y": gy,
        })
        if press["x"] is not None and press["y"] is not None:
            row["distance_deg"] = screen.angle_deg(
                (gx, gy), (press["x"], press["y"]))
        if target is not None:
            soft = category == target
            row["in_target_soft"] = soft
            row["in_target_strict"] = soft and bool(sure)
            gap = float(cfg["press_gap_ms"])
            row["lead_ms_soft"] = _lead(t, since, target, fixes, found,
                                        strict=False, gap=gap)
            row["lead_ms_strict"] = _lead(t, since, target, fixes, found,
                                          strict=True, gap=gap)
    return rows


def summary(rows: list[dict]) -> dict:
    """Сводка нажатий по экранам: сколько, у скольких взгляд известен,
    у скольких под ним была нужная категория."""
    out = {}
    for where in ("galaxy", "shelf"):
        own = [r for r in rows if r["screen"] == where]
        known = [r for r in own if r["in_target_soft"] is not None]
        leads = [r["lead_ms_soft"] for r in known
                 if r["lead_ms_soft"] is not None]
        far = [r["distance_deg"] for r in known
               if r["distance_deg"] is not None]
        out[where] = {
            "presses": len(own), "known": len(known),
            "in_target_soft": sum(1 for r in known if r["in_target_soft"]),
            "in_target_strict": sum(1 for r in known
                                    if r["in_target_strict"]),
            "lead_ms_soft": statistics.median(leads) if leads else None,
            "distance_deg": statistics.median(far) if far else None,
        }
    return out
