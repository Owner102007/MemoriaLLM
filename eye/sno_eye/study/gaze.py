"""Шаг 4 — разбор взгляда каждой записи (SNO-ALG-RES-03, -04).

Откуда данные: «Разбор записи» (`report.analyse`) **без изменений** —
версии взгляда (как записано и с поправкой дрейфа), фиксации I-DT
порогом сессии, зоны по кадрам раскладки «уверенно / на границе», доли
времени изучения и ход по минутам; походы за книгой — `study.actions`;
снимок полки на старте — `snapshot_start.json`; карта — событие
`galaxy.open` журнала.
Технология: стандартная библиотека; перевод точки окна в координаты
карты — по камере кадра раскладки (`study.disorder.content`).
Метод: SNO-ALG-RES-04, шаги 1–5: доли и минуты — как посчитал разбор;
для схемы полки — время поиска на каждой книге и на шапке каждой
категории (поля `book`, `zone`, `info.part` фиксаций, «мягко»); для
тепловой карты — фиксации поиска на полотне карты в координатах карты,
пятно радиусом в точность сессии; для матрицы поиска — переходы между
категориями. Отбор по точности (Т19, `include_deg`) — у записи
(`study.collect.gaze`), по шуму — `study.disorder.gate`.
Вход → выход: запись, её ход и походы → `gaze_data` записи: доли,
минуты, сырьё мер беспорядочности, схема полки, тепловая карта.
"""

from __future__ import annotations

import hashlib

from .. import report
from ..report.measures import FALLBACK_DEG
from . import disorder, stats
from .actions import SEARCH_SCREENS, Trip

# Фиксации «вне категорий» в матрице переходов поиска.
NO_CATEGORY = "вне категорий"


def read(record, trips: list[Trip], cfg: dict, report_cfg: dict,
         limits: dict, sha: str) -> dict | None:
    """Всё о взгляде записи, что нужно сравнению; None — взгляда нет."""
    if not (record.eye.get("present") is True and record.gaze):
        return None
    res = report.analyse(record, report_cfg, limits)
    if not res.get("gaze_used"):
        return None
    line = res["_timeline"]
    screen = res["_screen"]
    q = res.get("quality") or {}
    accuracy = q.get("mean_deg")
    data = {
        "version": report_cfg["version"],
        "accuracy_deg": accuracy,
        "precision_deg": q.get("precision_deg"),
        "idt_session_deg": q.get("idt_deg"),
        "layout": bool(res.get("layout_known")),
        "window_changed": line.window_changed is not None,
        "shares": dict(res["shares"]["soft"]),
        "shares_strict": dict(res["shares"]["strict"]),
        "minutes": list(res.get("minutes") or []),
        "notes": list(res.get("notes") or []),
    }
    seed = stats.seed_for("study", sha)
    data["disorder"] = disorder.prepare(
        res["_samples"], res["_spans"], record.frames, screen, line,
        trips, record.events, record.inputs, cfg, report_cfg, seed)
    # Клетка сетки меньше двух запасов точности сессии — пометка
    # (SNO-ALG-RES-03, «Зоны для переходов»): взгляд у границы клетки
    # уходит в соседнюю от одного шума.
    cell = min(data["disorder"]["cell_deg"])
    data["cell_small"] = accuracy is not None and cell < 2 * accuracy
    views = search_views(res, record, trips, screen,
                         accuracy if accuracy is not None else FALLBACK_DEG)
    data.update(views)
    return data


def map_of(events: list[dict]) -> dict | None:
    """Карта записи — первое `galaxy.open`: звёзды в координатах карты.
    Ключ — отпечаток мест звёзд: одна карта у всех, если одинаков набор
    книг (SNO-ALG-RES-04, шаг 4)."""
    for e in events:
        if e["type"] != "galaxy.open" or e.get("phase") == "post":
            continue
        data = e.get("data") if isinstance(e.get("data"), dict) else {}
        points = []
        for p in data.get("points") or []:
            if not isinstance(p, dict) or not isinstance(p.get("book"), str):
                continue
            x, y = disorder._num(p.get("x")), disorder._num(p.get("y"))
            if x is None or y is None:
                continue
            points.append({"book": p["book"], "x": x, "y": y,
                           "group": p.get("group"),
                           "r": disorder._num(p.get("r"))})
        if not points:
            continue
        text = "\n".join(f"{p['book']} {p['x']:.6f} {p['y']:.6f}"
                         for p in sorted(points, key=lambda p: p["book"]))
        return {"key": hashlib.sha256(text.encode()).hexdigest()[:8],
                "points": points}
    return None


def search_views(res: dict, record, trips: list[Trip], screen,
                 accuracy: float) -> dict:
    """Схема полки, тепловая карта и переходы между категориями — по
    фиксациям «Разбора записи» в поиске доведённых походов."""
    line = res["_timeline"]
    zones = res["_zones"]
    done = [t for t in trips if t.complete]
    shelf: dict = {"book": {}, "header": {}, "total_ms": 0.0}
    heat: list[list[float]] = []
    pairs: list[tuple[str, str]] = []
    radius_px = screen.px_for_deg(accuracy)
    for trip in done:
        stop = trip.choice or trip.end
        last = None
        for f in res["fixations"]:
            if f.get("moving") or not trip.start <= f["start"] < stop:
                continue
            if line.screen_at(f["start"]) not in SEARCH_SCREENS:
                continue
            d = float(f["duration"])
            shelf["total_ms"] += d
            if f.get("book"):
                shelf["book"][f["book"]] = \
                    shelf["book"].get(f["book"], 0.0) + d
            info = f.get("info") if isinstance(f.get("info"), dict) else {}
            if f.get("zone") == "shelf_category" and \
                    info.get("part") == "header":
                key = f.get("id") or ""
                shelf["header"][key] = shelf["header"].get(key, 0.0) + d
            if f.get("zone") == "galaxy_map":
                frame = zones.frame_at(f["start"])
                point = disorder.content(frame, f["x"], f["y"])
                region = disorder._map_region(frame)
                if point[0] == "map" and region is not None:
                    unit = region[6]
                    heat.append([point[1], point[2], d, radius_px / unit])
            name = f.get("category") or NO_CATEGORY
            if last is not None:
                pairs.append((last, name))
            last = name
    return {"shelf_time": shelf, "map_fix": heat, "category_pairs": pairs,
            "map": map_of(record.events)}


def shelf_layout(snapshot: dict | None) -> dict | None:
    """Полка на старте — категории и книги по порядку (для схемы
    полки, SNO-ALG-RES-04, шаг 5)."""
    if not isinstance(snapshot, dict):
        return None
    cats = []
    for c in snapshot.get("categories") or []:
        if isinstance(c, dict) and isinstance(c.get("name"), str):
            order = c.get("order")
            cats.append((c["name"], order if isinstance(order, (int, float))
                         and not isinstance(order, bool) else 0))
    books = []
    for b in snapshot.get("books") or []:
        if not isinstance(b, dict) or \
                not isinstance(b.get("fingerprint"), str):
            continue
        cat = b.get("category") if isinstance(b.get("category"), str) \
            else "Без категории"
        pos = b.get("position")
        books.append((b["fingerprint"], str(b.get("title") or ""), cat,
                      pos if isinstance(pos, (int, float))
                      and not isinstance(pos, bool) else 0))
    if not books:
        return None
    return {"categories": cats, "books": books}
