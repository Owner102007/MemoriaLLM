"""Ход сессии по журналу (SNO-ALG-EYE-05, SNO-ALG-REC-06).

Из журнала `events.jsonl` разбор узнаёт:

* где изучение — от `study.start` (на ПК калибровка идёт до него) до
  `recording.stop`; у записи без айтрекера — от старта записи;
* задержку камеры и точность взгляда в начале и в конце — из сведений
  записи и файлов спутника;
* отлучки — время «вне приложения» (`app.foreground` несёт, сколько
  участника не было);
* смену окна во время записи (`eye.window {changed}`) — после неё зоны
  не считаются: модель взгляда учили на другом окне;
* на каком экране был участник — по `nav.screen`;
* походы за источником — отрезки на полке и на карте и чем каждый
  кончился: какую книгу открыли, каким путём, искали ли по названию.

Все времена — `t` записи, мс по монотонным часам приложения; поток
взгляда пишется в них же (`t0 + (qpc − qpc0)`, SNO-ALG-EYE-03).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .archive import Record, _int, _num

# Экраны, на которых участник ищет источник, и как их назвать.
VISIT_SCREENS = {"shelf": "полка", "galaxy": "карта"}

# Сколько после ухода с полки может открываться книга, чтобы считаться
# итогом похода: книга большая, движок занят — открытие идёт секундами.
OPEN_WAIT_MS = 20_000


@dataclass
class Visit:
    """Поход за источником: отрезок на полке или на карте."""

    n: int
    screen: str
    start: float
    end: float
    outcome: str = "left"          # book, left, end
    book: str | None = None
    via: str | None = None
    to: str | None = None
    searches: int = 0
    first_search: float | None = None
    target: str | None = None      # категория открытой книги

    @property
    def duration(self) -> float:
        return self.end - self.start


@dataclass
class Timeline:
    """Ход сессии."""

    study_start: float
    study_end: float
    gaze_expected: bool
    latency_ms: float
    latency_known: bool
    start_deg: float | None
    end_deg: float | None
    precision_deg: float | None
    end_shift_mm: tuple[float, float] | None
    away: list[tuple[float, float, str]] = field(default_factory=list)
    window_changed: float | None = None
    screens: list[tuple[float, str]] = field(default_factory=list)
    visits: list[Visit] = field(default_factory=list)
    categories: dict[str, str | None] = field(default_factory=dict)
    titles: dict[str, str] = field(default_factory=dict)

    @property
    def study_ms(self) -> float:
        return max(0.0, self.study_end - self.study_start)

    def screen_at(self, t: float) -> str | None:
        found = None
        for at, name in self.screens:
            if at <= t:
                found = name
            else:
                break
        return found

    def away_at(self, t: float) -> bool:
        return any(a <= t < b for a, b, _ in self.away)


def _dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def _latency(record: Record) -> tuple[float, bool]:
    calibration = _dict(record.eye.get("calibration"))
    value = _num(calibration.get("latency_ms"))
    if value is not None:
        return value, True
    for attempt in reversed(_dict(record.calibration).get("attempts") or []):
        fit = _dict(_dict(attempt).get("fit"))
        value = _num(fit.get("latency_ms"))
        if value is not None:
            return value, True
    return 0.0, False


def _precision(record: Record) -> float | None:
    value = _num(_dict(record.eye.get("calibration")).get("precision_deg"))
    if value is not None:
        return value
    for attempt in reversed(_dict(record.calibration).get("attempts") or []):
        value = _num(_dict(_dict(attempt).get("validation"))
                     .get("precision_deg"))
        if value is not None:
            return value
    return None


def _end_shift(record: Record) -> tuple[float, float] | None:
    """Общий сдвиг оценки на проверке в конце, мм (оценка минус точка),
    — по последней проверке спутника."""
    for check in reversed(record.checks):
        shift = check.get("shift_mm")
        if isinstance(shift, list) and len(shift) == 2:
            x, y = _num(shift[0]), _num(shift[1])
            if x is not None and y is not None:
                return x, y
    return None


def _book_places(record: Record) -> tuple[dict, dict]:
    """Категория и название книги по отпечатку: по кадрам полки, а чего
    там нет — по снимку полки на старте."""
    categories: dict[str, str | None] = {}
    titles: dict[str, str] = {}
    snapshot = record.snapshot or {}
    for book in snapshot.get("books") or []:
        if not isinstance(book, dict):
            continue
        key = book.get("fingerprint")
        if isinstance(key, str):
            category = book.get("category")
            categories[key] = category if isinstance(category, str) \
                else None
            if isinstance(book.get("title"), str):
                titles[key] = book["title"]
    for frame in record.frames:
        for region in frame.get("regions") or []:
            if not isinstance(region, dict) or \
                    region.get("kind") != "shelf_book":
                continue
            info = _dict(region.get("info"))
            key = region.get("id")
            if isinstance(key, str) and info.get("in") != "results" and \
                    isinstance(info.get("category"), str):
                categories.setdefault(key, info["category"])
    return categories, titles


def build(record: Record) -> Timeline:
    """Ход сессии [record]."""
    events = record.events
    recording = _dict(record.manifest.get("recording"))
    start = None
    stop = None
    gaze_expected = False
    for event in events:
        kind = event["type"]
        if kind == "study.start" and start is None:
            start = float(event["t"])
            gaze_expected = _dict(event.get("data")).get("gaze") is True
        elif kind == "recording.stop" and stop is None:
            stop = float(event["t"])
    if start is None:
        start = 0.0
    if stop is None:
        duration = _num(recording.get("duration_ms"))
        if duration is not None:
            stop = duration
        else:
            stop = float(events[-1]["t"]) if events else start
    latency, known = _latency(record)
    end_check = _dict(record.eye.get("end_check"))
    categories, titles = _book_places(record)
    timeline = Timeline(
        study_start=start, study_end=max(start, stop),
        gaze_expected=gaze_expected or record.eye.get("present") is True,
        latency_ms=latency, latency_known=known,
        start_deg=_num(_dict(record.eye.get("calibration"))
                       .get("accuracy_deg")),
        end_deg=_num(end_check.get("accuracy_deg")),
        precision_deg=_precision(record), end_shift_mm=_end_shift(record),
        categories=categories, titles=titles)

    # Отлучки: `app.foreground` знает, сколько участника не было.
    left_at = None
    for event in events:
        kind = event["type"]
        data = _dict(event.get("data"))
        if kind == "app.background":
            left_at = float(event["t"])
        elif kind == "app.foreground":
            away = _num(data.get("away_ms"))
            t = float(event["t"])
            begin = t - away if away is not None else left_at
            if begin is not None and t > begin:
                timeline.away.append((begin, t, str(data.get("kind") or "")))
            left_at = None
        elif kind == "eye.window" and data.get("changed") is True and \
                timeline.window_changed is None and \
                event.get("phase") != "post":
            timeline.window_changed = float(event["t"])
    if left_at is not None and left_at < timeline.study_end:
        timeline.away.append((left_at, timeline.study_end, "open"))

    # Экраны: первый — у первого события, дальше — по `nav.screen`.
    if events:
        first = events[0].get("screen")
        if isinstance(first, str):
            timeline.screens.append((float(events[0]["t"]), first))
    for event in events:
        if event["type"] == "nav.screen":
            to = _dict(event.get("data")).get("to")
            if isinstance(to, str):
                timeline.screens.append((float(event["t"]), to))
    timeline.visits = _visits(timeline, events)
    return timeline


def _visits(timeline: Timeline, events: list[dict]) -> list[Visit]:
    lo, hi = timeline.study_start, timeline.study_end
    marks = timeline.screens + [(hi, "")]
    visits: list[Visit] = []
    for (t, name), (t_next, next_name) in zip(marks, marks[1:]):
        if name not in VISIT_SCREENS:
            continue
        a, b = max(t, lo), min(t_next, hi)
        if b <= a:
            continue
        visit = Visit(n=len(visits) + 1, screen=name, start=a, end=b,
                      outcome="end" if t_next >= hi else "left",
                      to=next_name or None)
        visits.append(visit)
    for i, visit in enumerate(visits):
        limit = visits[i + 1].start if i + 1 < len(visits) else \
            visit.end + OPEN_WAIT_MS
        for event in events:
            t = float(event["t"])
            data = _dict(event.get("data"))
            if event["type"] == "search.query" and \
                    data.get("scope") == "shelf" and \
                    visit.start <= t <= visit.end:
                visit.searches += 1
                if visit.first_search is None:
                    visit.first_search = t
            if event["type"] == "book.open" and visit.outcome == "left" and \
                    visit.end - 100 <= t <= min(limit,
                                                visit.end + OPEN_WAIT_MS):
                book = event.get("book")
                if isinstance(book, str):
                    visit.outcome = "book"
                    visit.book = book
                    via = data.get("via")
                    visit.via = via if isinstance(via, str) else None
                    visit.target = timeline.categories.get(book)
    return visits


def segment_of(row: dict) -> int:
    return _int(row.get("seg")) or 0
