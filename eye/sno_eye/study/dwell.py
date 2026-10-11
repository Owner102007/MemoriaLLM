"""Шаг 7а — заходы, возвраты и переходы между зонами (SNO-ALG-RES-07;
портрет участника, SNO-F-RES-07; шаг 38).

Откуда данные: фиксации общим порогом `study.idt_deg` (те же, что у мер
беспорядочности, `study.disorder`); что лежало под фиксацией и под
кругом запаса точности вокруг неё — кадры раскладки и правило «Разбора
записи» (`report.zones`: зона, категория полки или группа звёзд карты,
книга полки, звезда, страница); походы за книгой — `study.actions`;
открытия книги — журнал; время годного взгляда на экране — кадры с
видами «Разбора записи» (`report.measures.label_samples`).
Технология: стандартная библиотека.
Метод:
* заход (dwell) — подряд идущие фиксации в одной зоне; повторный заход
  (revisit) — заход в зону, где взгляд в этом эпизоде уже был:
  Holmqvist K. и др. «Eye Tracking: A comprehensive guide to methods
  and measures», OUP, 2011, гл. 6 и 7;
* ожидание возвратов при поиске без памяти — выбор следующей зоны
  наугад: Peterson M., Kramer A., Wang R., Irwin D., McCarley J.
  «Visual search has memory», Psychological Science, 2001, 12(4):287;
  Gilchrist I., Harvey M. «Refixation frequency and memory mechanisms
  in visual search», Current Biology, 2000, 10(19):1209;
* плотность матрицы переходов — Goldberg J., Kotval X. «Computer
  interface evaluation using eye movements», Int. J. Industrial
  Ergonomics, 1999, 24(6):631.
Вход → выход: фиксации записи с кадрами, походы и открытия книг →
заходы, возвраты и переходы по трём уровням зон, матрица переходов,
ход по минутам, лента сессии (`prepare`).
"""

from __future__ import annotations

import bisect
import math
from dataclasses import dataclass

from .. import layout
from ..report.measures import MINUTE_GROUPS, margin_deg
from ..report.zones import INNER, RING, bucket_of

# Уровень «интерфейс» — общий для обеих ветвей: шесть зон из видов
# времени «Разбора записи» (SNO-ALG-RES-07, «Три уровня зон»).
UI_ZONES = (
    ("page", "страница", ("page", "page_dimmed", "around")),
    ("panels", "панели чтения", ("panels", "book_search", "selection",
                                 "windows")),
    ("shelf", "полка", ("shelf", "shelf_search")),
    ("galaxy", "карта", ("galaxy",)),
    ("other", "прочие экраны", ("nav", "other_screen", "recording_dot")),
    ("outside", "вне экрана", ("outside",)),
)
UI_KEYS = tuple(key for key, _, _ in UI_ZONES)
UI_WORDS = {key: words for key, words, _ in UI_ZONES}
UI_OF = {b: key for key, _, members in UI_ZONES for b in members}

# Виды кадров, когда взгляд не годен или не на экране, — время годного
# взгляда без них (знаменатель «в минуту годного взгляда»).
NOT_VALID = ("away", "no_face", "blink", "outside", "no_frames", "unknown")

# Ожидание без памяти — по походам, где видно не меньше стольких зон.
MIN_VISIBLE = 3

# Лента сессии (П1, Р17): группа видов времени каждой секунды.
GROUP_OF = {b: key for key, _, members in MINUTE_GROUPS for b in members}


# --- что под фиксацией ---------------------------------------------------

def _ring(margin: float) -> list[tuple[float, float]]:
    """Точки двух кругов вокруг фиксации — как у «Разбора записи»
    (`report.zones.Zones.classify`): радиус запаса и половина его."""
    out = [(margin, 2 * math.pi * k / RING) for k in range(RING)]
    out += [(margin / 2, 2 * math.pi * (k + 0.5) / INNER)
            for k in range(INNER)]
    return out


def touch(zones, frame: dict, x: float, y: float, margin: float) -> dict:
    """Что лежало под фиксацией (`x`, `y`) и под кругом запаса вокруг
    неё — на трёх уровнях сразу.

    Ответ: `ui` — зона интерфейса и `ui_near` — другие зоны, которые
    задевает круг; `cat` — категория (полки или группа звёзд карты),
    `cat_sure`, `cat_near`; `book` — книга полки (`shelf:<отпечаток>`)
    или звезда карты (`star:<отпечаток>`) и уверенно ли (`book_sure`);
    `page`, `page_near` — страница книги.

    Правило то же, что у «Разбора записи»: «уверенно» — все точки
    двух кругов в той же зоне; точка за окном дальше `outside_px` — «вне
    экрана», ближе — у края, всегда «на границе»."""
    vp = frame.get("viewport") or {}
    w, h = float(vp.get("w") or 0), float(vp.get("h") or 0)
    o = zones.outside_px
    if x < -o or y < -o or x > w + o or y > h + o:
        return {"ui": "outside", "ui_near": set(), "cat": None,
                "cat_sure": False, "cat_near": set(), "book": None,
                "book_sure": False, "page": None, "page_near": set()}
    edge = not (0 <= x <= w and 0 <= y <= h)
    cx, cy = min(max(x, 0.0), w), min(max(y, 0.0), h)
    hit = layout.locate(frame, cx, cy)
    ui = UI_OF.get(bucket_of(hit))
    cat, shelf_book = zones.place(frame, cx, cy)
    mark = hit.get("mark")
    page = hit.get("page") if hit.get("zone") == "page" else None
    on_map = hit.get("zone") == "galaxy_map"
    ui_near: set = set()
    cat_near: set = set()
    page_near: set = set()
    cat_sure = cat is not None
    book_sure = shelf_book is not None or mark is not None
    for radius, angle in _ring(margin):
        px = x + radius * math.cos(angle)
        py = y + radius * math.sin(angle)
        other = zones._locate(frame, px, py)
        ou = UI_OF.get(bucket_of(other))
        if ou is not None and ou != ui:
            ui_near.add(ou)
        if other.get("zone") == "page" and other.get("page") != page:
            page_near.add(other.get("page"))
        if mark is not None and other.get("mark") != mark:
            book_sure = False
        if cat is not None or shelf_book is not None or on_map:
            oc, ob = zones.place(frame, px, py)
            if oc != cat:
                cat_sure = False
                if oc is not None:
                    cat_near.add(oc)
            if shelf_book is not None and ob != shelf_book:
                book_sure = False
    if edge:
        ui_near.add("outside")
    if shelf_book is not None:
        book = f"shelf:{shelf_book}"
    elif mark is not None:
        book = f"star:{mark}"
    else:
        book = None
    return {"ui": ui, "ui_near": ui_near, "cat": cat, "cat_sure": cat_sure,
            "cat_near": cat_near, "book": book, "book_sure": book_sure,
            "page": page, "page_near": page_near}


# --- заходы ---------------------------------------------------------------

@dataclass
class Dwell:
    """Заход: подряд идущие фиксации в одной зоне."""

    zone: str
    start: float
    end: float
    time: float              # время в зоне, мс (с просветами до bridge)
    revisit: bool            # в эту зону взгляд в эпизоде уже заходил
    content: bool = False    # начат сменой содержимого под взглядом


def _spans_between(spans, starts, a: float, b: float) -> bool:
    i = bisect.bisect_left(starts, b) - 1
    return i >= 0 and spans[i][1] > a


def dwells(seq: list[dict], spans: list[tuple[float, float]],
           gap_ms: float, bridge_ms: float, still_px: float
           ) -> tuple[list[Dwell], list[tuple[str, str, float]]]:
    """Заходы и переходы одного эпизода.

    [seq] — фиксации эпизода по порядку: `t`, `end`, `x`, `y`,
    `frame`, `zone` (None — не зона этого уровня: такая фиксация
    пропускается и ряда не рвёт), `sure` и `near` — зоны, которые задел
    круг запаса.

    * Фиксация «на границе» продолжает заход, если его зона — среди
      задетых; заход кончается только фиксацией «уверенно» в другой
      зоне (или фиксацией на границе, которая зону захода не задела).
    * Ряд рвут просвет дольше [gap_ms] и отрезок движения раскладки:
      после разрыва переход не считается; та же зона по обе стороны
      разрыва — тот же заход (разрыв в данных — не довод, что взгляд
      уходил).
    * Просвет до [bridge_ms] внутри захода идёт в его время.
    * Смена содержимого под неподвижным взглядом: две фиксации,
      разделённые только кадром раскладки (другой кадр, сдвиг меньше
      [still_px]), — новый заход без перехода и без возврата.

    Ответ — заходы и переходы `(откуда, куда, миг)`."""
    starts = [a for a, _ in spans]
    out: list[Dwell] = []
    trans: list[tuple[str, str, float]] = []
    seen: set = set()
    cur: Dwell | None = None
    prev: dict | None = None
    for f in seq:
        z = f["zone"]
        if z is None:
            continue
        if cur is not None and (z == cur.zone or (
                not f["sure"] and cur.zone in f["near"])):
            gap = f["t"] - prev["end"]
            cur.time += (f["end"] - f["t"]) + \
                (gap if 0 < gap <= bridge_ms else 0.0)
            cur.end = f["end"]
            prev = f
            continue
        broken = prev is None or f["t"] - prev["end"] > gap_ms or \
            _spans_between(spans, starts, prev["end"], f["t"])
        content = (not broken and f["frame"] is not prev["frame"] and
                   math.hypot(f["x"] - prev["x"], f["y"] - prev["y"])
                   < still_px)
        d = Dwell(z, f["t"], f["end"], f["end"] - f["t"],
                  revisit=z in seen and not content, content=content)
        if cur is not None and not broken and not content:
            trans.append((cur.zone, z, f["t"]))
        seen.add(z)
        out.append(d)
        cur = d
        prev = f
    return out, trans


def expected_revisits(m: int, n: int) -> float | None:
    """Ожидаемое число возвратов за [m] заходов при поиске без памяти
    среди [n] видимых зон.

    Следующий заход — в одну из `n − 1` других зон наугад (в ту же
    зону он быть не может — иначе это тот же заход). Если осмотрено
    `v` зон, новая выпадает с вероятностью `(n − v) / (n − 1)`, возврат
    — `(v − 1) / (n − 1)`. Считается точно, цепью по `v` (Peterson и
    др., 2001, — выбор из всех `n`; # Выбор наш: из `n − 1`, повтор
    подряд невозможен по определению захода)."""
    if m < 1 or n < 2:
        return None
    dist = {1: 1.0}
    expected = 0.0
    for _ in range(m - 1):
        new: dict[int, float] = {}
        for v, p in dist.items():
            back = (v - 1) / (n - 1)
            expected += p * back
            new[v] = new.get(v, 0.0) + p * back
            if v < n:
                new[v + 1] = new.get(v + 1, 0.0) + p * (n - v) / (n - 1)
        dist = new
    return expected


# --- одна запись -----------------------------------------------------------

def _frames_between(frames: list[dict], times: list[float], a: float,
                    b: float) -> list[dict]:
    """Кадры, действовавшие в [a, b): действовавший в миг `a` и все,
    что начались до `b`."""
    lo = max(0, bisect.bisect_right(times, a) - 1)
    hi = bisect.bisect_left(times, b)
    return frames[lo:max(lo + 1, hi)] if frames else []


def visible(frames: list[dict], times: list[float], a: float, b: float,
            zones) -> tuple[set, set]:
    """Категории и книги, видимые хоть раз за [a, b) (SNO-ALG-RES-07:
    `n` ожидания — что было видно; полку прокручивали, карту двигали —
    всё, что попадало в кадр)."""
    cats: set = set()
    books: set = set()
    for frame in _frames_between(frames, times, a, b):
        for region in frame.get("regions") or []:
            kind = region.get("kind")
            info = region.get("info") or {}
            if kind == "shelf_category" and region.get("id"):
                cats.add(region["id"])
            elif kind == "shelf_book" and info.get("in") != "results" and \
                    region.get("id"):
                books.add(f"shelf:{region['id']}")
                if isinstance(info.get("category"), str):
                    cats.add(info["category"])
            elif kind == "galaxy_map":
                left, top, w, h = region["rect"]
                for mark in region.get("marks") or []:
                    mx, my = mark.get("x"), mark.get("y")
                    if isinstance(mx, (int, float)) and \
                            isinstance(my, (int, float)) and \
                            left <= mx <= left + w and top <= my <= top + h:
                        books.add(f"star:{mark.get('id')}")
                for group in zones.groups(frame):
                    if any(left <= sx <= left + w and top <= sy <= top + h
                           for sx, sy, _ in group["stars"]):
                        cats.add(group["name"])
    return cats, books


def openings(events: list[dict], lo: float, hi: float
             ) -> list[tuple[float, float, str | None]]:
    """Открытия книги за изучение: (открыта, закрыта, отпечаток)."""
    out = []
    start = None
    book = None
    for e in events:
        if e.get("phase") == "post":
            continue
        t = float(e["t"])
        if e["type"] == "book.open":
            if start is not None:
                out.append((start, t, book))
            start, book = t, e.get("book")
        elif e["type"] == "book.close" and start is not None:
            out.append((start, t, book))
            start, book = None, None
    if start is not None:
        out.append((start, hi, book))
    return [(max(a, lo), min(b, hi), k) for a, b, k in out
            if min(b, hi) > max(a, lo)]


def valid_minutes(labels: list[tuple], lo: float, minutes: int
                  ) -> tuple[float, list[float]]:
    """Минуты годного взгляда на экране — всего и по минутам изучения
    (кадры с видами «Разбора записи», мягко)."""
    per = [0.0] * minutes
    total = 0.0
    for t, ms, _, soft in labels:
        if soft in NOT_VALID:
            continue
        total += ms
        m = int((t - lo) // 60_000)
        if 0 <= m < minutes:
            per[m] += ms
    return total / 60_000, [v / 60_000 for v in per]


def ribbon(labels: list[tuple], lo: float, hi: float) -> list[list]:
    """Лента сессии: каждая секунда изучения — группа видов времени,
    занимавшая в ней больше всего времени (мягко), соседние секунды
    одной группы — одним отрезком `[от, до, группа]` в секундах от
    начала изучения (SNO-ALG-RES-07, «Лента сессии»)."""
    seconds = int(math.ceil(max(0.0, hi - lo) / 1000))
    acc: list[dict] = [dict() for _ in range(seconds)]
    for t, ms, _, soft in labels:
        while ms > 0:
            s = int((t - lo) // 1000)
            if not 0 <= s < seconds:
                break
            edge = lo + (s + 1) * 1000
            part = min(ms, edge - t)
            g = GROUP_OF.get(soft, "other")
            acc[s][g] = acc[s].get(g, 0.0) + part
            t += part
            ms -= part
    order = [key for key, _, _ in MINUTE_GROUPS]
    out: list[list] = []
    for s, own in enumerate(acc):
        # Секунда без кадров — «прочее»; ничья — по порядку групп.
        g = max(order, key=lambda k: (own.get(k, 0.0), -order.index(k))) \
            if own else "other"
        if out and out[-1][2] == g and out[-1][1] == s:
            out[-1][1] = s + 1
        else:
            out.append([s, s + 1, g])
    return out


def prepare(fixes: list[dict], res: dict, record, done: list, line,
            screen, cfg: dict, portrait_cfg: dict) -> dict:
    """Заходы, возвраты и переходы одной записи по трём уровням.

    [fixes] — фиксации общим порогом (`study.disorder.prepare`): у них
    уже есть кадр, фазы и признак движения; [done] — доведённые походы
    в том же порядке, что номера фазы «поиск» у фиксаций."""
    zones = res.get("_zones")
    spans = res.get("_spans") or []
    labels = res.get("_labels") or []
    lo = line.study_start
    hi = line.study_end if line.window_changed is None else \
        min(line.study_end, line.window_changed)
    gap_ms = float(cfg["transition_gap_ms"])
    bridge_ms = float(portrait_cfg["bridge_ms"])
    still_px = screen.px_for_deg(float(cfg["idt_deg"]))
    minutes = int(math.ceil(max(0.0, line.study_end - lo) / 60_000))
    valid, valid_per = valid_minutes(labels, lo, minutes)
    out: dict = {"valid_min": valid, "valid_per_min": valid_per,
                 "ribbon": ribbon(labels, lo, line.study_end)}
    if zones is None or not res.get("layout_known"):
        out["reason"] = "кадров раскладки нет — зон нет"
        return out
    seq = []
    for f in fixes:
        if f["moving"] or f["frame"] is None:
            continue
        margin = screen.px_for_deg(margin_deg(f["t"], line))
        z = touch(zones, f["frame"], f["x"], f["y"], margin)
        seq.append({"f": f, "t": f["t"], "end": f["end"], "x": f["x"],
                    "y": f["y"], "frame": f["frame"], "z": z,
                    "screen": line.screen_at(f["t"])})

    def level(items, zone_of, sure_of, near_of):
        rows = []
        for s in items:
            rows.append({"t": s["t"], "end": s["end"], "x": s["x"],
                         "y": s["y"], "frame": s["frame"],
                         "zone": zone_of(s["z"]), "sure": sure_of(s["z"]),
                         "near": near_of(s["z"])})
        return dwells(rows, spans, gap_ms, bridge_ms, still_px)

    # Интерфейс — всё изучение одним эпизодом.
    ui_dwells, ui_trans = level(
        seq, lambda z: z["ui"], lambda z: not z["ui_near"],
        lambda z: z["ui_near"])
    out["ui"] = _summary(ui_dwells, ui_trans, UI_KEYS)
    out["ui"]["by_minute"] = _by_minute(ui_dwells, ui_trans, lo, minutes)
    out["ui"]["matrix"] = _matrix(ui_trans, UI_KEYS)

    # Поиск — по доведённым походам: категории и книги (только
    # «уверенно»: звезда меньше круга запаса, на границе книгу не
    # различить).
    times = [float(fr["t"]) for fr in record.frames]
    cat_rows: list[Dwell] = []
    cat_trans: list = []
    book_rows: list[Dwell] = []
    trips = []
    for k, trip in enumerate(done):
        own = [s for s in seq if s["f"]["phases"].get("search") == k]
        cd, ct = level(own, lambda z: z["cat"], lambda z: z["cat_sure"],
                       lambda z: z["cat_near"])
        bd, _ = level(own, lambda z: z["book"] if z["book_sure"] else None,
                      lambda z: True, lambda z: set())
        stop = min(trip.choice or trip.end, hi)
        cats, books = visible(record.frames, times, trip.start, stop, zones)
        row = {"n": trip.n, "i": k + 1, "cat_entries": len(cd),
               "cat_revisits": sum(d.revisit for d in cd),
               "cat_visible": len(cats),
               "cat_expected": expected_revisits(len(cd), len(cats)),
               "book_entries": len(bd),
               "book_revisits": sum(d.revisit for d in bd),
               "book_visible": len(books),
               "book_expected": expected_revisits(len(bd), len(books)),
               "cat_transitions": len(ct)}
        trips.append(row)
        cat_rows += cd
        cat_trans += ct
        book_rows += bd
    out["trips"] = trips
    out["cat"] = _summary(cat_rows, cat_trans, None)
    out["book"] = _summary(book_rows, [], None)
    for key, field in (("cat", "cat"), ("book", "book")):
        # Выбор наш: в отношение идут походы, где видно не меньше трёх
        # зон. При двух каждый заход после второго — возврат при любой
        # памяти: такой поход говорит «1» всегда и тянул бы отношение
        # к единице.
        live = [t for t in trips if t[f"{field}_expected"] is not None
                and t[f"{field}_visible"] >= MIN_VISIBLE]
        obs = sum(t[f"{field}_revisits"] for t in live)
        exp = sum(t[f"{field}_expected"] for t in live)
        # Без таких походов сравнивать не с чем: ожидание пустое, а не 0.
        out[key]["expected"] = exp if live else None
        out[key]["observed_vs"] = obs if live else None
        out[key]["trips_vs"] = len(live)
        out[key]["ratio"] = obs / exp if exp > 0 else None

    # Чтение — по открытиям книги: страницы.
    page_rows: list[Dwell] = []
    page_trans: list = []
    for a, b, _ in openings(record.events, lo, hi):
        own = [s for s in seq if a <= s["t"] < b and s["screen"] == "reader"]
        pd, pt = level(own, lambda z: z["page"],
                       lambda z: not z["page_near"],
                       lambda z: z["page_near"])
        page_rows += pd
        page_trans += pt
    out["page"] = _summary(page_rows, page_trans, None)
    return out


def _summary(rows: list[Dwell], trans: list, keys) -> dict:
    """Заходы, возвраты и время по зонам уровня."""
    zones: dict = {}
    for d in rows:
        own = zones.setdefault(str(d.zone), {"entries": 0, "revisits": 0,
                                             "time_ms": 0.0})
        own["entries"] += 1
        own["revisits"] += int(d.revisit)
        own["time_ms"] += d.time
    entries = len(rows)
    revisits = sum(d.revisit for d in rows)
    out = {"entries": entries, "revisits": revisits,
           "revisit_share": revisits / entries if entries else None,
           "transitions": len(trans), "zones": zones}
    if keys is not None:
        n = len(keys)
        pairs = {(a, b) for a, b, _ in trans if a != b}
        out["density"] = len(pairs) / (n * (n - 1)) if n > 1 else None
    return out


def _matrix(trans: list, keys) -> list[list[int]]:
    index = {k: i for i, k in enumerate(keys)}
    m = [[0] * len(keys) for _ in keys]
    for a, b, _ in trans:
        if a in index and b in index:
            m[index[a]][index[b]] += 1
    return m


def _by_minute(rows: list[Dwell], trans: list, lo: float, minutes: int
               ) -> dict:
    """Переходы и возвраты по минутам изучения — счёт (делится на
    минуты годного взгляда при сборе портрета)."""
    t_per = [0] * minutes
    r_per = [0] * minutes
    for _, _, t in trans:
        m = int((t - lo) // 60_000)
        if 0 <= m < minutes:
            t_per[m] += 1
    for d in rows:
        if not d.revisit:
            continue
        m = int((d.start - lo) // 60_000)
        if 0 <= m < minutes:
            r_per[m] += 1
    return {"transitions": t_per, "revisits": r_per}
