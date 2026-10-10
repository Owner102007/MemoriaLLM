"""Шаг 5 — походы за книгой и меры действий (SNO-ALG-RES-02).

Откуда данные: журнал `events.jsonl` и поток ввода `input.jsonl` архива,
прочитанные «Разбором записи» (`report.archive.load`); границы
изучения, экраны и отлучки — ход сессии `report.timeline.build`
(SNO-ALG-EYE-05) без изменений.
Технология: стандартная библиотека; медианы — `statistics`.
Метод: SNO-ALG-RES-02, разделы «Поход за книгой», «Выбор книги»,
«Меры действий»:
* поход за книгой — от выхода из читалки (или от начала изучения) до
  следующего открытия книги, сквозь полку, карту и поиск по названию;
  кончившийся остановкой записи без книги — недоведённый;
* момент выбора: с полки — `book.open`; с карты — последнее
  `galaxy.star` по той книге, которую открыли; из найденного по
  названию — открытие строки найденного (`search.result.open`);
* эпизод поиска — от первого `search.query` с данным `scope` до
  `search.close`, открытия найденного или ухода с экрана.
Вход → выход: запись → походы строками и меры участника (в минуту,
долями и медианой — длина изучения у участников разная).

Числа одни для ветвей I и II, для ПК и телефона: эти меры есть у
каждого участника, даже без взгляда.
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field

from ..report.archive import Record
from ..report.timeline import Timeline

# Экраны поиска источника: время на других экранах посреди похода
# («Тестирование», «Настройки») в поиск не идёт.
SEARCH_SCREENS = ("shelf", "galaxy")

# Экран, уход с которого кончает эпизод поиска.
SCOPE_SCREEN = {"shelf": "shelf", "book": "reader"}

# Нажатия экспериментатора, а не участника (слой записи, шаг 23).
OPERATOR_SCREENS = ("recording_dot", "stop_dialog")

# Касание — вид строки ввода `tap` или `long` от указателя, а не путь
# мыши, колесо или клавиша (`lib/sno/recording/input_tap.dart`).
TAP_KINDS = ("tap", "long")
NOT_POINTER = ("hover", "wheel", "key")

VIA_WORDS = {"shelf": "полка", "shelf_search": "найденное по названию",
             "galaxy": "карта"}

# Способ поиска по доле открытий через карту (`study.via_map`).
MODE_SHELF = "полкой"
MODE_MAP = "картой"
MODE_MIXED = "смешанно"


def _dict(value) -> dict:
    return value if isinstance(value, dict) else {}


@dataclass
class Trip:
    """Поход за книгой."""

    n: int
    start: float
    end: float                      # открытие книги или конец изучения
    complete: bool                  # открыта книга
    book: str | None = None
    via: str | None = None
    choice: float | None = None     # момент выбора
    search_ms: float = 0.0          # время на полке и карте до выбора
    card_ms: float | None = None    # от выбора на карте до открытия
    first_time: bool | None = None  # первое ли обращение к книге
    shelf_search: bool = False      # был ли эпизод поиска по названию
    map_ms: float = 0.0             # время на карте
    views: int = 0                  # приближений и сдвигов карты
    screens: list[str] = field(default_factory=list)


def _overlap(a: float, b: float, c: float, d: float) -> float:
    return max(0.0, min(b, d) - max(a, c))


def _screen_time(line: Timeline, a: float, b: float,
                 names: tuple[str, ...]) -> float:
    """Время в [a, b) на экранах [names] без отлучек."""
    marks = line.screens + [(float("inf"), "")]
    total = 0.0
    for (t, name), (t_next, _) in zip(marks, marks[1:]):
        if name not in names:
            continue
        lo, hi = max(t, a), min(t_next, b)
        if hi <= lo:
            continue
        span = hi - lo
        for x, y, _ in line.away:
            span -= _overlap(lo, hi, x, y)
        total += max(0.0, span)
    return total


def episodes(events: list[dict], scope: str) -> list[tuple[float, float]]:
    """Эпизоды поиска [scope]: «ане», «аневри», «аневризма» — один
    поиск. Начало — первый `search.query` с этим `scope`; конец —
    `search.close`, открытие найденного или уход с экрана поиска."""
    out = []
    start = None
    screen = SCOPE_SCREEN.get(scope)
    for e in events:
        kind = e["type"]
        data = _dict(e.get("data"))
        if kind == "search.query" and data.get("scope") == scope:
            if start is None:
                start = float(e["t"])
            continue
        if start is None:
            continue
        ends = (kind in ("search.close", "search.result.open")
                and data.get("scope") == scope) or \
            (kind == "nav.screen" and data.get("from") == screen)
        if ends:
            out.append((start, float(e["t"])))
            start = None
    if start is not None:
        out.append((start, float(events[-1]["t"]) if events else start))
    return out


def trips(record: Record, line: Timeline) -> list[Trip]:
    """Походы за книгой за время изучения."""
    lo, hi = line.study_start, line.study_end
    events = [e for e in record.events if e.get("phase") != "post"]
    shelf_eps = episodes(events, "shelf")
    out: list[Trip] = []
    seen_books: set[str] = set()
    open_now = False
    start: float | None = lo
    # Книга, открытая до начала изучения и не закрытая к нему: первый
    # поход начинается с её закрытия.
    for e in events:
        t = float(e["t"])
        if t >= lo:
            break
        if e["type"] == "book.open":
            open_now = True
        elif e["type"] == "book.close":
            open_now = False
    if open_now:
        start = None
    for e in events:
        t = float(e["t"])
        kind = e["type"]
        if t < lo or t > hi:
            continue
        if kind == "book.close":
            if start is None:
                start = t
            continue
        if kind != "book.open":
            continue
        book = e.get("book") if isinstance(e.get("book"), str) else None
        if start is None:
            # Книга открыта поверх открытой — похода не было.
            continue
        via = _dict(e.get("data")).get("via")
        trip = Trip(n=len(out) + 1, start=start, end=t, complete=True,
                    book=book, via=via if isinstance(via, str) else None)
        trip.choice = _choice(events, trip)
        trip.search_ms = _screen_time(line, trip.start, trip.choice,
                                      SEARCH_SCREENS)
        if trip.via == "galaxy" and trip.choice < t:
            trip.card_ms = t - trip.choice
        trip.first_time = book is not None and book not in seen_books
        if book is not None:
            seen_books.add(book)
        out.append(trip)
        start = None
    if start is not None and start < hi:
        out.append(Trip(n=len(out) + 1, start=start, end=hi, complete=False))
    for trip in out:
        trip.shelf_search = any(trip.start <= a <= trip.end
                                for a, _ in shelf_eps)
        trip.map_ms = _screen_time(line, trip.start, trip.end, ("galaxy",))
        trip.views = sum(1 for e in events if e["type"] == "galaxy.view"
                         and trip.start <= float(e["t"]) <= trip.end)
        # Экраны похода — чем шёл участник; читалка, куда поход
        # приводит, в их число не входит.
        names = [line.screen_at(trip.start) or ""]
        for t, name in line.screens:
            if trip.start < t < trip.end and name not in names:
                names.append(name)
        trip.screens = [n for n in names if n and n != "reader"]
    return out


def _choice(events: list[dict], trip: Trip) -> float:
    """Момент выбора книги похода [trip]."""
    found = None
    if trip.via == "galaxy":
        for e in events:
            t = float(e["t"])
            if trip.start <= t <= trip.end and e["type"] == "galaxy.star" \
                    and _dict(e.get("data")).get("book") == trip.book:
                found = t
    elif trip.via == "shelf_search":
        for e in events:
            t = float(e["t"])
            data = _dict(e.get("data"))
            if trip.start <= t <= trip.end and \
                    e["type"] == "search.result.open" and \
                    data.get("scope") == "shelf" and \
                    data.get("book") in (None, trip.book):
                found = t
    return found if found is not None else trip.end


def search_mode(opens_via: list[str | None], branch: str | None,
                via_map: tuple[float, float]) -> str | None:
    """Чем участник на самом деле искал книги — по доле открытий через
    карту (`study.via_map`): от 2/3 — «картой», до 1/3 — «полкой»,
    между — «смешанно». Ветвь I — всегда «полкой»: карты в ней нет."""
    if branch == "I":
        return MODE_SHELF
    if not opens_via:
        return None
    share = sum(1 for v in opens_via if v == "galaxy") / len(opens_via)
    low, high = via_map
    if share >= high:
        return MODE_MAP
    if share <= low:
        return MODE_SHELF
    return MODE_MIXED


def _median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def study_ms(record: Record, line: Timeline) -> float:
    """Длина изучения: `recording.stop` → `data.study_ms` — её считает
    приложение по большему из двух счётов (SNO-ALG-RES-02, «изучение,
    мин»); нет — по журналу, от начала изучения до остановки."""
    for e in record.events:
        if e["type"] == "recording.stop":
            value = _dict(e.get("data")).get("study_ms")
            if isinstance(value, (int, float)) and \
                    not isinstance(value, bool) and value > 0:
                return float(value)
            break
    return line.study_ms


def measures(record: Record, line: Timeline, found: list[Trip],
             branch: str | None, via_map: tuple[float, float]) -> dict:
    """Меры действий участника за время изучения.

    Время — в секундах, доли — от 0 до 1; счёт — в минуту изучения:
    длина изучения у участников разная."""
    lo, hi = line.study_start, line.study_end
    events = [e for e in record.events if e.get("phase") != "post"
              and lo <= float(e["t"]) <= hi]
    minutes = study_ms(record, line) / 60_000
    per_min = (lambda n: n / minutes) if minutes > 0 else (lambda n: None)
    opens = [e for e in events if e["type"] == "book.open"]
    via = [_dict(e.get("data")).get("via") for e in opens]
    books = [e.get("book") for e in opens if isinstance(e.get("book"), str)]
    repeats = 0
    seen: set[str] = set()
    for book in books:
        if book in seen:
            repeats += 1
        seen.add(book)
    complete = [t for t in found if t.complete]
    through_map = [t for t in complete if t.map_ms > 0]
    with_search = [t for t in complete if t.shelf_search]
    cards = [e for e in events if e["type"] == "galaxy.card.open"]
    unread = 0
    for e in cards:
        t = float(e["t"])
        book = _dict(e.get("data")).get("book")
        trip = next((x for x in found if x.start <= t <= x.end), None)
        if trip is None or not trip.complete or trip.book != book:
            unread += 1
    book_eps = [a for a, _ in episodes(events, "book") if lo <= a <= hi]
    reads = [_dict(e.get("data")).get("read_ms") for e in events
             if e["type"] == "book.close"]
    reads = [r / 1000 for r in reads
             if isinstance(r, (int, float)) and not isinstance(r, bool)]
    away = [(max(a, lo), min(b, hi)) for a, b, _ in line.away
            if min(b, hi) > max(a, lo)]

    # Касания участника и пустые: на касание не сослалось ни одно
    # событие журнала (поле `input`, SNO-F-REC-11).
    referenced = {e.get("input") for e in record.events
                  if isinstance(e.get("input"), int)}
    taps = [n for n, row in record.inputs.items()
            if row.get("kind") in TAP_KINDS
            and row.get("dev") not in NOT_POINTER
            and row.get("screen") not in OPERATOR_SCREENS
            and lo <= float(row.get("t", -1)) <= hi]
    empty = sum(1 for n in taps if n not in referenced)

    n_open = len(opens)
    last = max((t.n for t in with_search), default=None)
    out = {
        "actions.study_min": minutes,
        "actions.opens_per_min": per_min(n_open),
        # Длина изучения у участников разная — счёт в минуту и долями,
        # а не суммой (SNO-ALG-RES-01, шаг 6).
        "actions.books_per_min": per_min(len(seen)),
        "actions.repeat_share": repeats / n_open if n_open else None,
        "actions.via_shelf": via.count("shelf") / n_open if n_open else None,
        "actions.via_found": (via.count("shelf_search") / n_open
                              if n_open else None),
        "actions.via_map": via.count("galaxy") / n_open if n_open else None,
        # Главная мера (АК4): медиана по доведённым походам.
        "actions.time_to_choice": _median([t.search_ms / 1000
                                           for t in complete]),
        "actions.card_time": _median([t.card_ms / 1000 for t in complete
                                      if t.card_ms is not None]),
        "actions.search_trip_share": (len(with_search) / len(complete)
                                      if complete else None),
        # Номер последнего похода с поиском / число походов: когда
        # участник перестал искать и стал открывать по памяти. Не искал
        # ни разу — 0.
        "actions.last_search_trip": ((last or 0) / len(complete)
                                     if complete else None),
        "actions.book_search_per_min": per_min(len(book_eps)),
        "actions.map_views_per_trip": (
            sum(t.views for t in through_map) / len(through_map)
            if through_map else None),
        "actions.cards_unread_share": unread / len(cards) if cards else None,
        "actions.pages_per_min": per_min(
            sum(1 for e in events if e["type"] == "page.shown")),
        "actions.read_per_book": _median(reads),
        "actions.away_per_min": per_min(len(away)),
        "actions.away_share": (sum(b - a for a, b in away) / line.study_ms
                               if line.study_ms > 0 else None),
        "actions.taps_per_min": per_min(len(taps)),
        "actions.empty_tap_share": empty / len(taps) if taps else None,
    }
    info = {
        "trips": len(found), "complete_trips": len(complete),
        "opens": n_open, "books": len(seen), "away_count": len(away),
        "away_s": sum(b - a for a, b in away) / 1000,
        "search_mode": search_mode(via, branch, via_map),
        "taps": len(taps), "empty_taps": empty,
    }
    return {"measures": out, "info": info}
