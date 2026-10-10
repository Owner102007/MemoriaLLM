"""Меры сессии и качество взгляда (SNO-ALG-EYE-05, шаги 6–7).

Меры **строгие** (в зону идёт только фиксация «уверенно», остальные —
в «на границе») и **мягкие** (фиксация на границе — в зону своей
середины):

* доли времени изучения по видам зон — и по минутам. Время делится по
  кадрам взгляда: кадр фиксации — её зона, годный кадр вне фиксаций —
  «переходы» или «вне экрана», негодный — «лица нет» или «моргание»,
  кадр в отлучке — «вне приложения», то, чего кадры не покрыли, — «нет
  кадров»; отрезки движения раскладки — отдельно;
* **походы на полку** — от прихода на полку до ухода с неё: сколько
  категорий и книг осмотрено до нажатия, когда взгляд впервые попал в
  нужную категорию, была ли «прямая находка» (первая фиксация на полке
  — уже в нужной категории), путь взгляда по категориям. Нужная
  категория — категория книги, которую открыли в конце похода;
* то же на карте — для ветви II: звёзды, на которые смотрели, и когда
  взгляд дошёл до звезды открытой книги.

Качество: точность в начале и в конце, прецизионность, доля годного,
кадров в секунду — отдельно на полке и на странице, неявные точки и их
остаток до поправки и после, дрейф. **Включение** (Т8, Т19): средняя
точность проверок в начале и в конце не хуже 3° — иначе меры взгляда
сессии помечены `excluded`.
"""

from __future__ import annotations

import statistics

from .idt import Fixation
from .screen import Screen
from .timeline import Timeline, Visit
from .versions import Sample
from .zones import BUCKETS

# Точность, когда сессия её не назвала, — порог приёма калибровки.
FALLBACK_DEG = 2.5

# Группы видов времени для хода по минутам.
MINUTE_GROUPS = (
    ("reading", "чтение",
     ("page", "page_dimmed", "around", "panels", "book_search",
      "selection", "windows")),
    ("shelf", "полка и поиск по названию", ("shelf", "shelf_search")),
    ("galaxy", "карта", ("galaxy",)),
    ("off", "вне экрана и вне приложения",
     ("outside", "no_face", "away")),
    ("other", "прочее",
     ("nav", "recording_dot", "other_screen", "border", "moving", "blink",
      "saccade", "unknown", "no_frames")),
)


def margin_deg(t: float, timeline: Timeline) -> float:
    """Запас в градусах в миг [t]: точность в начале, а после середины
    изучения — линейно к точности в конце."""
    start = timeline.start_deg
    end = timeline.end_deg
    if start is None and end is None:
        return FALLBACK_DEG
    if start is None:
        return end  # type: ignore[return-value]
    if end is None:
        return start
    lo, hi = timeline.study_start, timeline.study_end
    mid = (lo + hi) / 2
    if t <= mid or hi <= mid:
        return start
    w = min(1.0, (t - mid) / (hi - mid))
    return start + (end - start) * w


def label_samples(samples: list[Sample], fixes: list[Fixation],
                  zones: list[dict], timeline: Timeline, screen: Screen,
                  outside_px: float, cap_ms: float,
                  layout_known: bool) -> list[tuple]:
    """Кадры изучения с долей времени и видом: `(t, ms, строго,
    мягко)`."""
    member: dict[int, int] = {}
    for k, fix in enumerate(fixes):
        for i in fix.members:
            member[i] = k
    lo, hi = timeline.study_start, timeline.study_end
    changed = timeline.window_changed
    out = []
    for i, s in enumerate(samples):
        if not lo <= s.t < hi:
            continue
        nxt = samples[i + 1].t if i + 1 < len(samples) else s.t + cap_ms
        ms = max(0.0, min(nxt - s.t, cap_ms, hi - s.t))
        if timeline.away_at(s.t):
            strict = soft = "away"
        elif not s.face:
            strict = soft = "no_face"
        elif not s.ok:
            strict = soft = "blink"
        elif changed is not None and s.t >= changed:
            strict = soft = "unknown"
        elif i in member:
            fix = fixes[member[i]]
            zone = zones[member[i]]
            if fix.moving:
                strict = soft = "moving"
            elif not layout_known:
                strict = soft = "outside" if zone["bucket"] == "outside" \
                    else "unknown"
            else:
                soft = zone["bucket"]
                strict = soft if zone["sure"] else "border"
        else:
            off = s.x < -outside_px or s.y < -outside_px or \
                s.x > screen.w + outside_px or s.y > screen.h + outside_px
            strict = soft = "outside" if off else "saccade"
        out.append((s.t, ms, strict, soft))
    return out


def shares(labels: list[tuple], study_ms: float) -> dict:
    """Доли времени изучения по видам — строго и мягко."""
    strict = {name: 0.0 for name, _ in BUCKETS}
    soft = {name: 0.0 for name, _ in BUCKETS}
    covered = 0.0
    for _, ms, a, b in labels:
        strict[a] += ms
        soft[b] += ms
        covered += ms
    rest = max(0.0, study_ms - covered)
    strict["no_frames"] += rest
    soft["no_frames"] += rest
    total = study_ms if study_ms > 0 else 1.0
    return {
        "strict": {k: v / total for k, v in strict.items()},
        "soft": {k: v / total for k, v in soft.items()},
        "strict_ms": strict, "soft_ms": soft,
    }


def per_minute(labels: list[tuple], timeline: Timeline) -> list[dict]:
    """Ход изучения по минутам: доли групп видов (мягко)."""
    if timeline.study_ms <= 0:
        return []
    minutes = int((timeline.study_ms - 1) // 60_000) + 1
    rows = [{key: 0.0 for key, _, _ in MINUTE_GROUPS}
            for _ in range(minutes)]
    group = {b: key for key, _, members in MINUTE_GROUPS for b in members}
    for t, ms, _, soft in labels:
        # Кадр на стыке минут делится между ними.
        while ms > 0:
            m = int((t - timeline.study_start) // 60_000)
            if not 0 <= m < minutes:
                break
            edge = timeline.study_start + (m + 1) * 60_000
            part = min(ms, edge - t)
            rows[m][group.get(soft, "other")] += part
            t += part
            ms -= part
    out = []
    for m, row in enumerate(rows):
        span = min(60_000.0, timeline.study_ms - m * 60_000)
        covered = sum(row.values())
        row["other"] += max(0.0, span - covered)
        out.append({"minute": m + 1, "span_ms": span,
                    **{k: (v / span if span > 0 else 0.0)
                       for k, v in row.items()}})
    return out


def _ordered(values: list[str]) -> list[str]:
    seen: list[str] = []
    for value in values:
        if not seen or seen[-1] != value:
            seen.append(value)
    return seen


def visit_measures(visit: Visit, fixes: list[Fixation],
                   zones: list[dict], gaze: bool) -> dict:
    """Меры похода за источником."""
    row = {
        "n": visit.n, "screen": visit.screen, "start_ms": visit.start,
        "duration_ms": visit.duration, "outcome": visit.outcome,
        "book": visit.book, "via": visit.via, "target": visit.target,
        "searches": visit.searches,
        "search_after_ms": (None if visit.first_search is None else
                            visit.first_search - visit.start),
    }
    if not gaze:
        return row
    own = [(f, z) for f, z in zip(fixes, zones)
           if visit.start <= f.start < visit.end and not f.moving]
    row["fixations"] = len(own)
    for mode in ("strict", "soft"):
        cats: list[str] = []
        cat_times: list[float] = []
        books: list[str] = []
        stars: list[str] = []
        for f, z in own:
            if z.get("category") is not None and \
                    (mode == "soft" or z.get("category_sure")):
                cats.append(z["category"])
                cat_times.append(f.start)
            if z.get("book") is not None and \
                    (mode == "soft" or z.get("book_sure")):
                books.append(z["book"])
            if z.get("mark") and (mode == "soft" or z.get("sure")):
                stars.append(z["mark"])
        path = _ordered(cats)
        row[f"categories_{mode}"] = len(set(cats))
        row[f"path_{mode}"] = path
        target = visit.target
        first = None
        if target is not None:
            for c, t in zip(cats, cat_times):
                if c == target:
                    first = t - visit.start
                    break
        if visit.screen == "galaxy" and visit.book is not None:
            for f, z in own:
                if z.get("mark") == visit.book and \
                        (mode == "soft" or z.get("sure")):
                    first = f.start - visit.start
                    break
        row[f"first_target_ms_{mode}"] = first
        row[f"direct_{mode}"] = (None if target is None or not cats
                                 else cats[0] == target)
        row[f"books_{mode}"] = len(set(books))
        if visit.screen == "galaxy":
            row[f"stars_{mode}"] = len(set(stars))
    return row


def _median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def _mean(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def visit_summary(rows: list[dict], gaze: bool) -> dict:
    """Сводка походов на полку."""
    shelf = [r for r in rows if r["screen"] == "shelf"]
    opened = [r for r in shelf if r["outcome"] == "book"]
    out = {
        "visits": len(shelf),
        "opened": len(opened),
        "median_s": _median([r["duration_ms"] / 1000 for r in opened]),
        "with_search": sum(1 for r in shelf if r["searches"]),
    }
    if gaze:
        for mode in ("strict", "soft"):
            known = [r[f"direct_{mode}"] for r in opened
                     if r.get(f"direct_{mode}") is not None]
            out[f"direct_share_{mode}"] = (sum(known) / len(known)
                                           if known else None)
            out[f"first_target_s_{mode}"] = _median(
                [r[f"first_target_ms_{mode}"] / 1000 for r in opened
                 if r.get(f"first_target_ms_{mode}") is not None])
            out[f"categories_{mode}"] = _mean(
                [r[f"categories_{mode}"] for r in opened])
            out[f"books_{mode}"] = _mean([r[f"books_{mode}"]
                                          for r in opened])
    return out


def fps_by_screen(samples: list[Sample], timeline: Timeline) -> dict:
    """Кадров взгляда в секунду на каждом экране изучения: по соседним
    кадрам одного экрана; разрыв дольше секунды (подъём спутника) —
    не кадры."""
    frames: dict[str, int] = {}
    time: dict[str, float] = {}
    lo, hi = timeline.study_start, timeline.study_end
    for a, b in zip(samples, samples[1:]):
        if not lo <= a.t < hi or not 0 < b.t - a.t < 1000:
            continue
        name = timeline.screen_at(a.t) or "?"
        if timeline.screen_at(b.t) != name:
            continue
        frames[name] = frames.get(name, 0) + 1
        time[name] = time.get(name, 0.0) + (b.t - a.t)
    return {name: round(frames[name] * 1000 / time[name], 2)
            for name in frames if time[name] > 0}


def valid_share(samples: list[Sample], timeline: Timeline) -> float | None:
    own = [s for s in samples
           if timeline.study_start <= s.t < timeline.study_end]
    if not own:
        return None
    return sum(1 for s in own if s.ok) / len(own)
