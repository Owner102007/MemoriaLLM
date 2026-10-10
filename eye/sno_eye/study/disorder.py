"""Шаг 6 — меры беспорядочности взгляда (SNO-ALG-RES-03).

Откуда данные: выборки взгляда «Разбора записи» той версии, которой он
считает меры (`report.versions`, `report.version`), отрезки движения
раскладки и экран места записи — их отдаёт `report.analyse` (`_samples`,
`_spans`, `_screen`); кадры раскладки и поток ввода — архив
(`report.archive.load`); походы за книгой и момент выбора —
`study.actions.trips`.
Технология: фиксации — `report.idt.fixations` и зоны — `layout.locate`,
`report.zones.bucket_of` (стандартная библиотека); счёт мер — numpy:
подвыборки переходов без возвращения (`Generator.choice`), счётчики
матрицы переходов (`bincount`), логарифм по основанию 2, попарные
расстояния для ближайших соседей, розыгрыши случайного уровня.
Метод:
* энтропия переходов H_t и распределения H_s — Krejtz K., Szmidt T.,
  Duchowski A., Krejtz I. «Entropy-based statistical analysis of eye
  movement transitions», ETRA 2014; Krejtz K. и др. «Gaze transition
  entropy», ACM TAP, 2015, 13(1):4; обзор — Shiferaw B., Downey L.,
  Crewther D., Neuroscience & Biobehavioral Reviews, 2019, 96;
* коэффициент K — Krejtz K., Duchowski A., Krejtz I., Szarkowska A.,
  Kopacz A. «Discerning ambient/focal attention with coefficient K»,
  ACM TAP, 2016, 13(3):11;
* длина пути — Goldberg J., Kotval X. «Computer interface evaluation
  using eye movements», Int. J. Industrial Ergonomics, 1999,
  24(6):631–645;
* повторные заходы и основа (длительность фиксации, амплитуда саккады)
  — Holmqvist K. и др. «Eye Tracking: A comprehensive guide to methods
  and measures», OUP, 2011;
* кучность — Clark P., Evans F. «Distance to nearest neighbor…»,
  Ecology, 1954, 35:445; для взгляда — Di Nocera F., Camilli M.,
  Terenzi M. «A random glance at the flight deck», J. Cognitive
  Engineering and Decision Making, 2007, 1(3).
Вход → выход: запись → сырьё мер по фазам (`prepare`, когда архив
читается); все записи после отбора → меры участника `search.*`,
`reading.*`, `all.*` (`finish`).

**Один порог фиксаций на всё исследование** (`study.idt_deg`, АК12):
порог «Разбора записи» у каждой сессии свой (три прецизионности), и
число и длина фиксаций мерили бы камеру. Сессия, у которой три
прецизионности больше общего порога, в меры М1–М7 не идёт.
"""

from __future__ import annotations

import bisect
import math
import statistics

import numpy as np

from .. import layout
from ..report import idt
from ..report.measures import MINUTE_GROUPS
from ..report.zones import bucket_of
from . import stats
from .actions import SEARCH_SCREENS, Trip, _overlap, _screen_time

SEARCH = "search"
READING = "reading"
ALL = "all"
PHASES = (SEARCH, READING, ALL)
PHASE_WORDS = {SEARCH: "поиск", READING: "чтение", ALL: "всё изучение"}

OUTSIDE = "outside"
OTHER = "other"

# Зоны фазы «чтение» — виды времени чтения «Разбора записи» и ещё два:
# «вне экрана» (так фиксация вне экрана идёт в М1, М2, М5 —
# SNO-ALG-RES-03, краевые случаи) и «прочее» (точка записи, навигация).
# Выбор наш: без них фиксация мимо семи видов выпадала бы, и две
# фиксации по её сторонам склеивались бы в переход, которого не было.
READING_ZONES = ("page", "page_dimmed", "around", "panels", "book_search",
                 "selection", "windows", OUTSIDE, OTHER)

# Зоны фазы «всё изучение» — пять групп видов времени «Разбора записи»
# (`report.measures.MINUTE_GROUPS`): одинаковы у обеих ветвей, у ветви
# I «карта» пуста.
ALL_ZONES = tuple(key for key, _, _ in MINUTE_GROUPS)
GROUP_OF = {b: key for key, _, members in MINUTE_GROUPS for b in members}

# Пар (фиксация, следующая саккада) у участника для K — не меньше.
# Выбор наш: среднее по десятку пар уже не одна случайная фиксация.
MIN_K_PAIRS = 10


def search_zones(grid: tuple[int, int]) -> tuple[str, ...]:
    """Зоны фазы «поиск»: клетки сетки окна `cols × rows` и «вне
    экрана». Клетка — доля окна, а не градусы: число зон одинаково на
    любом ПК."""
    cols, rows = grid
    return tuple(f"c{r}{c}" for r in range(rows) for c in range(cols)) \
        + (OUTSIDE,)


# --- кадр раскладки и содержимое ------------------------------------------

class Frames:
    """Кадры раскладки записи и кадр в миг [t]."""

    def __init__(self, frames: list[dict]):
        self.frames = frames
        self.times = [float(f["t"]) for f in frames]

    def at(self, t: float) -> dict | None:
        i = bisect.bisect_right(self.times, t) - 1
        return self.frames[i] if i >= 0 else None


def _num(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) else None


def _inside(rect, x: float, y: float) -> bool:
    left, top, w, h = rect
    return left <= x <= left + w and top <= y <= top + h


def _map_region(frame: dict | None) -> tuple | None:
    """Полотно карты кадра: (left, top, w, h, cx, cy, unit) или None."""
    for region in (frame or {}).get("regions") or []:
        if region.get("kind") != "galaxy_map":
            continue
        cam = (region.get("info") or {}).get("map") or {}
        cx, cy, unit = (_num(cam.get(k)) for k in ("cx", "cy", "unit"))
        if cx is None or cy is None or not unit:
            return None
        return (*region["rect"], cx, cy, unit)
    return None


def _shelf_region(frame: dict | None) -> dict | None:
    for region in (frame or {}).get("regions") or []:
        if region.get("kind") == "screen" and region.get("id") == "shelf":
            return region
    return None


def _shelf_scroll(frame: dict | None) -> float | None:
    """Сдвиг прокрутки полки кадра (`screen`/`shelf`, `info.scroll`)."""
    region = _shelf_region(frame)
    if region is None:
        return None
    return _num((region.get("info") or {}).get("scroll")) or 0.0


def content(frame: dict | None, x: float, y: float) -> tuple:
    """Точка окна → точка содержимого: на полотне карты — координаты
    карты по камере кадра (`x = cx + (точка.x − left − w / 2) / unit`,
    `galaxy_screen.dart`, шаг 31); на полке — со сдвигом прокрутки;
    иначе — та же точка окна."""
    region = _map_region(frame)
    if region is not None and _inside(region[:4], x, y):
        left, top, w, h, cx, cy, unit = region
        return ("map", cx + (x - left - w / 2) / unit,
                cy + (y - top - h / 2) / unit)
    region = _shelf_region(frame)
    if region is not None and _inside(region["rect"], x, y):
        # Прокручивается только раздел полки: точка на полосе
        # навигации или в шапке экрана стоит на месте.
        return ("shelf", x, y + (_shelf_scroll(frame) or 0.0))
    return ("screen", x, y)


def on_screen(frame: dict | None, point: tuple) -> tuple | None:
    """Точка содержимого → где она в окне кадра [frame]; None — в этом
    кадре такого содержимого нет."""
    kind, a, b = point
    if kind == "screen":
        return a, b
    if kind == "map":
        region = _map_region(frame)
        if region is None:
            return None
        left, top, w, h, cx, cy, unit = region
        return left + w / 2 + (a - cx) * unit, top + h / 2 + (b - cy) * unit
    scroll = _shelf_scroll(frame)
    if scroll is None:
        return None
    return a, b - scroll


# --- одна запись: фиксации, зоны, фазы ------------------------------------

def cell_of(x: float, y: float, w: float, h: float, outside_px: float,
            grid: tuple[int, int]) -> str:
    """Клетка сетки окна; дальше `outside_px` за краем — «вне экрана»,
    ближе — клетка у края (как у зон «Разбора записи»)."""
    if x < -outside_px or y < -outside_px or x > w + outside_px or \
            y > h + outside_px:
        return OUTSIDE
    cols, rows = grid
    c = min(cols - 1, max(0, int(x / (w / cols))))
    r = min(rows - 1, max(0, int(y / (h / rows))))
    return f"c{r}{c}"


def _bucket(frame: dict | None, x: float, y: float, outside_px: float
            ) -> str:
    """Вид времени фиксации — по середине («мягко»), как у долей зон."""
    if frame is None:
        return "unknown"
    vp = frame.get("viewport") or {}
    w, h = float(vp.get("w") or 0), float(vp.get("h") or 0)
    if x < -outside_px or y < -outside_px or x > w + outside_px or \
            y > h + outside_px:
        return OUTSIDE
    cx, cy = min(max(x, 0.0), w), min(max(y, 0.0), h)
    return bucket_of(layout.locate(frame, cx, cy))


def _spans_hit(spans: list[tuple[float, float]], starts: list[float],
               a: float, b: float) -> bool:
    """Лежит ли отрезок движения раскладки между мигами [a] и [b].
    Отрезки не перекрываются и идут по порядку: достаточно последнего,
    начавшегося раньше [b]."""
    i = bisect.bisect_left(starts, b) - 1
    return i >= 0 and spans[i][1] > a


def chains(fixes: list[dict], phase: str, spans, gap_ms: float
           ) -> list[list[int]]:
    """Ряды подряд идущих фиксаций фазы [phase]: переход — только
    внутри ряда. Ряд рвёт фиксация не этой фазы или на отрезке движения,
    отрезок движения раскладки между фиксациями, просвет дольше
    [gap_ms] (лица нет, отлучка) и — в поиске — смена похода: последняя
    фиксация одного похода и первая следующего — не переход."""
    starts = [a for a, _ in spans]
    out: list[list[int]] = []
    run: list[int] = []
    for i, f in enumerate(fixes):
        member = f["phases"].get(phase)
        if member is None or f["moving"]:
            if run:
                out.append(run)
            run = []
            continue
        if run:
            prev = fixes[run[-1]]
            if f["t"] - prev["end"] > gap_ms or \
                    prev["phases"].get(phase) != member or \
                    _spans_hit(spans, starts, prev["end"], f["t"]):
                out.append(run)
                run = []
        run.append(i)
    if run:
        out.append(run)
    return out


def _choice_tap(events: list[dict], inputs: dict, trip: Trip
                ) -> dict | None:
    """Строка ввода, которой выбрали книгу похода: нажатие звезды,
    строки найденного или книги полки (поле `input` события выбора)."""
    kinds = {"galaxy": ("galaxy.star",),
             "shelf_search": ("search.result.open",)}.get(
        trip.via or "", ("book.open",))
    for e in events:
        if float(e["t"]) != trip.choice or e["type"] not in kinds:
            continue
        data = e.get("data") if isinstance(e.get("data"), dict) else {}
        book = data.get("book", e.get("book"))
        if book not in (None, trip.book):
            continue
        n = e.get("input")
        if isinstance(n, int) and n in inputs:
            return inputs[n]
    return None


def prepare(samples: list, spans: list, frames: list[dict], screen,
            line, trips: list[Trip], events: list[dict], inputs: dict,
            cfg: dict, report_cfg: dict, seed: int) -> dict:
    """Сырьё мер беспорядочности одной записи — всё, что не зависит от
    других участников: фиксации общим порогом, ряды переходов по фазам,
    пары для K, основа, путь, прямота и возвраты по походам, кучность.

    Что зависит от выборки — число переходов подвыборки `k` и μ, σ
    коэффициента K, — считает `finish`."""
    grid = tuple(int(v) for v in cfg["grid"])
    idt_deg = float(cfg["idt_deg"])
    outside_px = screen.px_for_deg(float(report_cfg["outside_deg"]))
    gap_ms = float(cfg["transition_gap_ms"])
    frame_times = [float(f["t"]) for f in frames]
    fixes_raw = idt.fixations(samples, screen.px_for_deg(idt_deg), spans,
                              report_cfg, frame_times)
    lo = line.study_start
    hi = line.study_end if line.window_changed is None else \
        min(line.study_end, line.window_changed)
    at = Frames(frames)
    # Выбор наш: поиск — только доведённые походы, и во все меры фазы
    # поиска (М1–М7) идут одни и те же фиксации: недоведённый последний
    # поход не идёт ни в одну из них, а не только в М1, М4–М6 — так меры
    # одной фазы описывают один и тот же взгляд.
    done = [t for t in trips if t.complete and t.start < hi]
    fixes: list[dict] = []
    for f in fixes_raw:
        if not lo <= f.start < hi:
            continue
        frame = at.at(f.start)
        vp = (frame or {}).get("viewport") or {}
        w = float(vp.get("w") or screen.w)
        h = float(vp.get("h") or screen.h)
        bucket = _bucket(frame, f.x, f.y, outside_px)
        name = line.screen_at(f.start)
        phases: dict = {ALL: True}
        if name == "reader":
            phases[READING] = True
        if name in SEARCH_SCREENS:
            for k, trip in enumerate(done):
                if trip.start <= f.start < (trip.choice or trip.end):
                    phases[SEARCH] = k
                    break
        fixes.append({
            "t": f.start, "end": f.end, "d": f.duration, "x": f.x,
            "y": f.y, "moving": f.moving, "frame": frame,
            "cell": cell_of(f.x, f.y, w, h, outside_px, grid),
            "group": GROUP_OF.get(bucket, OTHER),
            "rzone": bucket if bucket in READING_ZONES else
            (OUTSIDE if bucket == OUTSIDE else OTHER),
            "phases": phases})

    def amp(a: dict, b: dict) -> float:
        """Амплитуда саккады a → b по экрану, градусы."""
        return screen.angle_deg((a["x"], a["y"]), (b["x"], b["y"]))

    zones = {SEARCH: search_zones(grid), READING: READING_ZONES,
             ALL: ALL_ZONES}
    key = {SEARCH: "cell", READING: "rzone", ALL: "group"}
    out: dict = {"idt_deg": idt_deg, "grid": list(grid),
                 "cell_deg": [screen.deg_for_px(screen.w / grid[0]),
                              screen.deg_for_px(screen.h / grid[1])],
                 "phases": {}}
    # Окно сменили посреди изучения — после этого мига зон нет: походы
    # после него в меры не идут (выше), время поиска обрезается.
    phase_time = {
        SEARCH: sum(t.search_ms if (t.choice or t.end) <= hi else
                    _screen_time(line, t.start, hi, SEARCH_SCREENS)
                    for t in done) / 1000,
        READING: _time_on(line, lo, hi, ("reader",)) / 1000,
        ALL: _time_on(line, lo, hi, None) / 1000,
    }
    for phase in PHASES:
        index = {z: i for i, z in enumerate(zones[phase])}
        rows = chains(fixes, phase, spans, gap_ms)
        trans: list[tuple[int, int]] = []
        k_pairs: list[tuple[float, float]] = []
        amps: list[float] = []
        durations = [fixes[i]["d"] for run in rows for i in run]
        for run in rows:
            for a, b in zip(run, run[1:]):
                fa, fb = fixes[a], fixes[b]
                trans.append((index[fa[key[phase]]], index[fb[key[phase]]]))
                if fa["cell"] != OUTSIDE and fb["cell"] != OUTSIDE:
                    # Амплитуда — между местами на экране; у точки вне
                    # экрана места нет (краевые случаи).
                    size = amp(fa, fb)
                    amps.append(size)
                    k_pairs.append((fa["d"], size))
        out["phases"][phase] = {
            "zones": len(zones[phase]), "transitions": trans,
            "k_pairs": k_pairs, "fixations": len(durations),
            "fix_ms": statistics.median(durations) if durations else None,
            "sacc_deg": statistics.median(amps) if amps else None,
            "time_s": phase_time[phase],
            "fix_rate": (len(durations) / phase_time[phase]
                         if phase_time[phase] > 0 else None),
        }
    out["trips"] = _trips(fixes, done, at, events, inputs, screen)
    out["nni"] = _nni(fixes, done, int(cfg["min_fix_nni"]),
                      int(cfg["nni_mc"]), seed)
    return out


def _time_on(line, a: float, b: float, names) -> float:
    """Время в [a, b) на экранах [names] (None — на любом) без
    отлучек."""
    if names is not None:
        return _screen_time(line, a, b, names)
    total = max(0.0, b - a)
    for x, y, _ in line.away:
        total -= _overlap(a, b, x, y)
    return max(0.0, total)


def _trips(fixes: list[dict], done: list[Trip], at: Frames,
           events: list[dict], inputs: dict, screen) -> list[dict]:
    """Путь, прямота и возвраты по каждому доведённому походу (М4, М5).

    Путь — сумма амплитуд саккад по **содержимому**: если между двумя
    фиксациями полку прокрутили или карту сдвинули, место первой
    переводится в кадр второй, и в путь идёт только движение глаза.
    Выбор наш: путь замыкается на цели — последний отрезок от последней
    фиксации до места нажатия, которым выбрали книгу; так прямота не
    больше 1, и нажатие «не глядя» путь не укорачивает."""
    out = []
    for k, trip in enumerate(done):
        own = [f for f in fixes if f["phases"].get(SEARCH) == k
               and not f["moving"]]
        row: dict = {"n": trip.n, "i": k + 1, "fixations": len(own),
                     "path_deg": None, "straight": None, "returns": None}
        out.append(row)
        if not own:
            continue
        # М5 — возвраты: заход — подряд идущие фиксации в одной клетке;
        # доля заходов в клетку, где взгляд в этом походе уже был.
        runs = [f["cell"] for i, f in enumerate(own)
                if i == 0 or own[i - 1]["cell"] != f["cell"]]
        seen: set[str] = set()
        back = 0
        for cell in runs:
            if cell in seen:
                back += 1
            seen.add(cell)
        row["returns"] = back / len(runs)
        # М4 — путь и прямота; фиксация вне экрана места не имеет.
        placed = [f for f in own if f["cell"] != OUTSIDE]
        if not placed:
            continue
        path = 0.0
        for a, b in zip(placed, placed[1:]):
            path += _moved(a, b, screen)
        tap = _choice_tap(events, inputs, trip)
        first = placed[0]
        if tap is not None:
            target_frame = at.at(float(tap.get("t", trip.choice)))
            target = (float(tap["x"]), float(tap["y"]))
        else:
            # Строки нажатия нет — цель по кадру раскладки: середина
            # выбранной книги полки или её звезды.
            target_frame, target = _target_in_frames(at, trip)
        if target is None:
            # Цели не найти — путь без последнего отрезка, прямоты нет.
            row["path_deg"] = path
            continue
        last = placed[-1]
        path += _to_target(last, target_frame, target, screen)
        straight = _to_target(first, target_frame, target, screen)
        row["path_deg"] = path
        hit = layout.locate(first["frame"], first["x"], first["y"]) \
            if first["frame"] is not None else {}
        on_target = trip.book is not None and \
            trip.book in (hit.get("id"), hit.get("mark"))
        if on_target or path < 1.0:
            row["straight"] = 1.0
        else:
            row["straight"] = min(1.0, straight / path)
    return out


def _target_in_frames(at: Frames, trip: Trip) -> tuple:
    """Место выбранной книги в последнем кадре до выбора, где она
    видна: блок книги полки (или строка найденного) или звезда карты."""
    stop = bisect.bisect_right(at.times, trip.choice or trip.end)
    for frame in reversed(at.frames[:stop]):
        if float(frame["t"]) < trip.start:
            break
        for region in frame.get("regions") or []:
            if region.get("kind") == "shelf_book" and \
                    region.get("id") == trip.book:
                left, top, w, h = region["rect"]
                return frame, (left + w / 2, top + h / 2)
            for mark in region.get("marks") or []:
                if mark.get("id") == trip.book:
                    return frame, (float(mark["x"]), float(mark["y"]))
    return None, None


def _moved(a: dict, b: dict, screen) -> float:
    """Саккада a → b по содержимому, градусы."""
    point = on_screen(b["frame"], content(a["frame"], a["x"], a["y"]))
    if point is None:
        point = (a["x"], a["y"])
    return screen.angle_deg(point, (b["x"], b["y"]))


def _to_target(f: dict, frame: dict | None, target: tuple, screen
               ) -> float:
    point = on_screen(frame, content(f["frame"], f["x"], f["y"]))
    if point is None:
        point = (f["x"], f["y"])
    return screen.angle_deg(point, target)


def _area(frame: dict | None, name: str) -> list | None:
    """Видимая область поиска кадра: раздел полки или полотно карты."""
    for region in (frame or {}).get("regions") or []:
        if name == "shelf" and region.get("kind") == "screen" and \
                region.get("id") == "shelf":
            return region["rect"]
        if name == "galaxy" and region.get("kind") == "galaxy_map":
            return region["rect"]
    return None


def mean_nn(points: np.ndarray) -> float:
    """Среднее расстояние от точки до ближайшей соседней."""
    d = np.sqrt(((points[:, None, :] - points[None, :, :]) ** 2).sum(-1))
    np.fill_diagonal(d, np.inf)
    return float(d.min(axis=1).mean())


def random_nn(rect, n: int, repeats: int, rng) -> float:
    """Ожидаемое среднее расстояние до ближайшего соседа у [n] точек,
    разбросанных равномерно по прямоугольнику [rect], — розыгрышем: он
    учитывает и края области (формула Кларка — Эванса их не знает и при
    малых n завышает NNI)."""
    left, top, w, h = rect
    total = 0.0
    for _ in range(repeats):
        pts = np.column_stack([left + rng.random(n) * w,
                               top + rng.random(n) * h])
        total += mean_nn(pts)
    return total / repeats


def _nni(fixes: list[dict], done: list[Trip], min_n: int, repeats: int,
         seed: int) -> dict:
    """М6 — кучность фиксаций поиска: NNI = d̄ / d̄_случ, отдельно для
    полки и для карты, в координатах экрана, по всем походам вместе."""
    out = {}
    for name in ("shelf", "galaxy"):
        rect = None
        pts = []
        for f in fixes:
            if f["phases"].get(SEARCH) is None or f["moving"] or \
                    f["cell"] == OUTSIDE:
                continue
            own = _area(f["frame"], name)
            if own is None or not _inside(own, f["x"], f["y"]):
                continue
            # Область розыгрыша — раздел первого такого кадра: размер
            # окна во время записи не меняется (смена окна гасит меры).
            rect = rect or own
            pts.append((f["x"], f["y"]))
        row = {"n": len(pts), "nni": None}
        if len(pts) >= min_n and rect is not None and rect[2] > 0 \
                and rect[3] > 0:
            rng = np.random.default_rng(stats.seed_for(seed, "nni", name))
            observed = mean_nn(np.asarray(pts, float))
            expected = random_nn(rect, len(pts), repeats, rng)
            row["nni"] = observed / expected if expected > 0 else None
        out[name] = row
    return out


# --- все записи: k, μ и σ, меры участника ---------------------------------

def _entropies(trans: np.ndarray, n: int) -> tuple[float, float]:
    """H_t и H_s одного набора переходов [trans] (пары зон).

    H_t = − Σ_i π_i · Σ_j P_ij · log₂ P_ij, H_s = − Σ_i π_i · log₂ π_i,
    где P_ij — доля переходов из i в j среди переходов из i, π_i — доля
    переходов, начавшихся в i (Krejtz и др., 2015). У Krejtz π —
    стационарное распределение цепи; здесь — доли начал переходов, и в
    отчёте это названо приближением."""
    counts = np.bincount(trans[:, 0] * n + trans[:, 1],
                         minlength=n * n).reshape(n, n).astype(float)
    rows = counts.sum(axis=1)
    total = rows.sum()
    pi = rows / total
    with np.errstate(divide="ignore", invalid="ignore"):
        p = np.where(rows[:, None] > 0, counts / rows[:, None], 0.0)
        logp = np.where(p > 0, np.log2(np.where(p > 0, p, 1.0)), 0.0)
        logpi = np.where(pi > 0, np.log2(np.where(pi > 0, pi, 1.0)), 0.0)
    # «+ 0.0» — без «минус нуля» в таблицах.
    h_t = float(-(pi * (p * logp).sum(axis=1)).sum()) + 0.0
    h_s = float(-(pi * logpi).sum()) + 0.0
    return h_t, h_s


def random_level(n: int, k: int, repeats: int, seed: int,
                 no_repeat: bool = False) -> tuple[float, float]:
    """H_t и H_s совершенно случайного взгляда при тех же [n] зонах и
    [k] переходах: среднее по [repeats] розыгрышам [k] независимых пар
    случайных зон. [no_repeat] — без переходов внутри зоны (столбец
    «без повторов»).

    Выбор наш: пары, а не случайный путь — так же, как подвыборка
    берёт пары переходов участника, а не отрезок его пути. При малом
    `k` единица — не потолок: случайный взгляд по нескольким клеткам
    даёт больше 1, по двум — меньше (в «Как читать» это сказано)."""
    rng = np.random.default_rng(seed)
    ht = hs = 0.0
    for _ in range(repeats):
        a = rng.integers(0, n, k)
        if no_repeat:
            b = (a + rng.integers(1, n, k)) % n
        else:
            b = rng.integers(0, n, k)
        x, y = _entropies(np.column_stack([a, b]), n)
        ht += x
        hs += y
    return ht / repeats, hs / repeats


def subsampled(trans: list, n: int, k: int, repeats: int, seed: int
               ) -> tuple[float, float]:
    """Средние H_t и H_s по [repeats] подвыборкам из [k] переходов без
    возвращения: оценка энтропии по малой выборке занижена, и тем
    сильнее, чем переходов меньше, — у всех участников их поровну."""
    arr = np.asarray(trans, dtype=np.int64)
    if k == len(arr):
        # Все переходы — подвыборка одна и та же.
        return _entropies(arr, n)
    rng = np.random.default_rng(seed)
    ht = hs = 0.0
    for _ in range(repeats):
        pick = arr[rng.choice(len(arr), size=k, replace=False)]
        x, y = _entropies(pick, n)
        ht += x
        hs += y
    return ht / repeats, hs / repeats


def shares(soft: dict) -> dict:
    """Доли времени изучения по трём группам для сравнения: чтение,
    поиск (полка и карта), вне экрана и вне приложения (мягко)."""
    groups = {key: sum(soft.get(b, 0.0) for b in members)
              for key, _, members in MINUTE_GROUPS}
    return {"share.reading": groups["reading"],
            "share.search": groups["shelf"] + groups["galaxy"],
            "share.off": groups["off"]}


def gate(e: dict, cfg: dict) -> str | None:
    """Почему сессия не идёт в М1–М7: шум дробил бы фиксации."""
    data = e.get("gaze_data")
    if not data:
        return (e.get("gaze") or {}).get("reason") or "взгляда нет"
    if not data.get("layout"):
        return "кадров раскладки нет — зон нет"
    precision = data.get("precision_deg")
    limit = float(cfg["idt_deg"])
    if precision is None:
        return "прецизионность неизвестна — шум проверить нечем"
    if 3 * precision > limit:
        return (f"три прецизионности {3 * precision:.1f}° больше общего "
                f"порога фиксаций {limit:.1f}°").replace(".", ",")
    return None


def finish(entries: list[dict], cfg: dict, *, fingerprint: str,
           no_filter: bool, series: str | None) -> dict:
    """Меры М1–М7 всех участников (`gaze_measures`) — после отбора: `k`
    подвыборки и μ, σ коэффициента K берутся по участникам основного
    сценария S0 и одинаковы во всех сценариях.

    Проверочный прогон (`--no-filter`) снимает и отбор по шуму: сессия
    помечена, но меры получает."""
    from .compare import hard_out, scenario_weight
    repeats = int(cfg["ht_repeats"])
    floors = dict(zip(PHASES, (int(v) for v in cfg["ht_min_transitions"])))
    live = []
    for e in entries:
        e.setdefault("gaze_measures", {})
        data = e.get("gaze_data")
        if data and data.get("layout"):
            # Доли времени изучения (SNO-ALG-RES-04, шаг 1) — «Разбора
            # записи», порогом сессии: от шума их не отсекают, только
            # точность 3° (сценарии сравнения).
            e["gaze_measures"].update(shares(data["shares"]))
        why = gate(e, cfg) if e.get("status") == "ok" else None
        e["disorder_gate"] = why
        if data is None or hard_out(e, cfg, no_filter, series):
            continue
        if why is not None and not data.get("layout"):
            continue
        if why is not None and not no_filter:
            continue
        live.append(e)
    main = [e for e in live
            if scenario_weight(e, "S0", cfg, no_filter, series, True) > 0]
    pool = main or live
    info: dict = {"from": "S0" if main else "все записи со взглядом",
                  "idt_deg": float(cfg["idt_deg"]),
                  "grid": list(cfg["grid"]), "phases": {}}
    for phase in PHASES:
        own = info["phases"][phase] = {"floor": floors[phase]}
        n = len(search_zones(tuple(cfg["grid"]))) if phase == SEARCH else \
            len(READING_ZONES if phase == READING else ALL_ZONES)
        own["zones"] = n
        for variant in ("", "_norep"):
            def count(e):
                trans = e["gaze_data"]["disorder"]["phases"][phase][
                    "transitions"]
                if variant:
                    trans = [t for t in trans if t[0] != t[1]]
                return len(trans)
            counts = [count(e) for e in pool if count(e) >= floors[phase]]
            k = min(counts) if counts else None
            own[f"k{variant}"] = k
            if k is not None:
                own[f"random{variant}"] = random_level(
                    n, k, repeats,
                    stats.seed_for(fingerprint, "random", phase, n, k,
                                   variant),
                    no_repeat=bool(variant))
        # Выбор наш: μ и σ — по фазам (у поиска и чтения разные
        # фиксации и скачки) и по парам «фиксация — следующий скачок»
        # участников S0; в S0 никого со взглядом — по всем записям со
        # взглядом, и отчёт об этом говорит.
        pairs = [p for e in pool for p in
                 e["gaze_data"]["disorder"]["phases"][phase]["k_pairs"]]
        if len(pairs) >= 2:
            arr = np.asarray(pairs, float)
            own["K"] = {"mu_d": float(arr[:, 0].mean()),
                        "sd_d": float(arr[:, 0].std()),
                        "mu_a": float(arr[:, 1].mean()),
                        "sd_a": float(arr[:, 1].std())}
        else:
            own["K"] = None
    for e in live:
        e["disorder_live"] = True
        e["gaze_measures"].update(_participant(e, info, repeats,
                                               fingerprint))
    return info


def _participant(e: dict, info: dict, repeats: int, fingerprint: str
                 ) -> dict:
    """Меры одного участника по всем фазам."""
    raw = e["gaze_data"]["disorder"]
    out: dict = {}
    for phase in PHASES:
        own = raw["phases"][phase]
        meta = info["phases"][phase]
        n = meta["zones"]
        out[f"{phase}.transitions"] = len(own["transitions"])
        for variant in ("", "_norep"):
            trans = own["transitions"]
            if variant:
                trans = [t for t in trans if t[0] != t[1]]
            k = meta.get(f"k{variant}")
            # Выбор наш: `k` одно на всех во всех сценариях; участник
            # вне S0, у которого переходов меньше `k`, хоть и больше
            # пола, получает пустую меру, а не свою подвыборку.
            if k is None or len(trans) < max(k, meta["floor"]):
                continue
            ht, hs = subsampled(trans, n, k, repeats, stats.seed_for(
                fingerprint, "H_t", phase, variant, e.get("sha256")))
            r_ht, r_hs = meta[f"random{variant}"]
            out[f"{phase}.H_t{variant}"] = ht / r_ht if r_ht > 0 else None
            if not variant:
                out[f"{phase}.H_s"] = hs / r_hs if r_hs > 0 else None
        K = meta.get("K")
        pairs = own["k_pairs"]
        if K and K["sd_d"] > 0 and K["sd_a"] > 0 and \
                len(pairs) >= MIN_K_PAIRS:
            arr = np.asarray(pairs, float)
            # K_i = (d_i − μ_d) / σ_d − (a_{i+1} − μ_a) / σ_a.
            ks = (arr[:, 0] - K["mu_d"]) / K["sd_d"] - \
                (arr[:, 1] - K["mu_a"]) / K["sd_a"]
            out[f"{phase}.K"] = float(ks.mean()) + 0.0
        out[f"{phase}.fix_ms"] = own["fix_ms"]
        out[f"{phase}.sacc_deg"] = own["sacc_deg"]
        out[f"{phase}.fix_rate"] = own["fix_rate"]
    trips = raw["trips"]
    paths = [t["path_deg"] for t in trips if t["path_deg"] is not None]
    straight = [t["straight"] for t in trips if t["straight"] is not None]
    back = [t["returns"] for t in trips if t["returns"] is not None]
    out["search.path"] = statistics.median(paths) if paths else None
    out["search.straight"] = statistics.median(straight) if straight \
        else None
    out["search.returns"] = statistics.median(back) if back else None
    out["search.trips_no_gaze"] = sum(1 for t in trips
                                      if not t["fixations"])
    nni = raw["nni"]
    # Экран кучности — где у участника больше фиксаций поиска.
    name = max(("shelf", "galaxy"), key=lambda s: (nni[s]["n"], s))
    value = nni[name]["nni"]
    out["search.nni"] = value
    out["search.nni_screen"] = name if value is not None else None
    # Порядок бывает с обеих сторон от 1: в сравнение — отклонение от
    # случайного, меньше — беспорядочнее.
    out["search.nni_dev"] = None if value is None else abs(1 - value)
    return out
