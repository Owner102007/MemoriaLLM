"""Версии взгляда и поправка дрейфа (SNO-ALG-EYE-05, шаги 1–3).

**Исходное не переписывается.** Каждая версия — свой ряд точек:

* `raw` — оценка спутника из `gaze.jsonl`, как есть;
* `drift` — та же оценка со сдвигом по неявным точкам (`raw+drift`).

`refit` (пересчёт по `features.bin` исправленным кодом признаков) равна
`raw`, пока код признаков не менялся с записи, а ступень 1 (`net`) —
отдельная функция SNO-F-RES-04; в этом шаге их нет.

Все версии сдвинуты на задержку камеры: кадр, полученный в миг `t`,
снят в `t − latency` — её находит калибровка по слежению за точкой.

**Неявные точки** — нажатия мышью по отдельной цели: открыть книгу,
перейти в раздел, выбрать найденное, пункт оглавления, панель, действие
над выделением, переход к записи. Звезда карты — не точка (BUG-64):
перед ней смотрят на название категории. Человек смотрит туда,
куда нажимает, — за 300–100 мс до нажатия. Пара — медиана взгляда в
этом окне и место нажатия; пара дальше 5° — «нажал не глядя», прочь.
Нажатия по зонам листания, колесо и клавиши в пары не идут.

Касание середины страницы, которое прячет и показывает панели
(`panel.open {panel: chrome}`), цели не имеет — в пары оно не идёт.

**Поправка дрейфа**: окна по 5 минут со сдвигом в минуту; сдвиг окна —
медиана остатков его пар, ослабленная к нулю по их числу
(`k = n / (n + 5)`). Окно без пар берёт сдвиг соседних окон с парами —
линейно между ними; опоры по краям — проверка сразу после калибровки в
начале изучения (сдвиг её точек, без него — ноль: модель только что
выучена) и проверка в конце. Между серединами окон сдвиг идёт линейно.
"""

from __future__ import annotations

import math
import statistics
from dataclasses import dataclass, replace

from .archive import Record, _int, _num
from .screen import Screen
from .timeline import Timeline

# События, нажатие которых — неявная точка (SNO-ALG-EYE-05, шаг 2).
# Звезда карты — не точка (BUG-64, правка шага 34): на карте смотрят
# на название категории над группой и жмут звезду под ним, не переводя
# взгляда, — подпись в пределах 5° от звезды, «не глядя» её не ловит,
# и поправка тянула бы взгляд с подписи на звёзды. Карточка книги
# открывается тем же нажатием.
IMPLICIT = (
    "book.open", "nav.screen", "search.result.open", "toc.open",
    "toc.jump", "panel.open", "selection.action", "annotation.jump",
)

# Указатели, у которых нажатие — точка, куда смотрят.
POINTERS = ("mouse", "trackpad")

# Нажатия экспериментатора, а не участника (SNO-F-REC-11).
EXPERIMENTER = ("recording_dot", "stop_dialog")


@dataclass
class Sample:
    """Точка взгляда: время с поправкой на задержку, место, годна ли."""

    t: float
    x: float | None
    y: float | None
    ok: bool
    face: bool
    seg: int = 0


@dataclass
class Pair:
    """Неявная точка: куда нажали и куда смотрели перед этим."""

    t: float
    kind: str
    input: int
    tx: float
    ty: float
    gx: float
    gy: float
    err_deg: float

    @property
    def dx(self) -> float:
        return self.tx - self.gx

    @property
    def dy(self) -> float:
        return self.ty - self.gy


def raw_samples(record: Record, latency_ms: float) -> list[Sample]:
    """Версия `raw`: строки взгляда, сдвинутые на задержку камеры."""
    out = []
    for row in record.gaze:
        t = _num(row.get("t"))
        if t is None:
            continue
        x, y = _num(row.get("x")), _num(row.get("y"))
        ok = row.get("ok") is True and x is not None and y is not None
        face = _num(row.get("yaw")) is not None or ok
        out.append(Sample(t - latency_ms, x if ok else None,
                          y if ok else None, ok, face,
                          _int(row.get("seg")) or 0))
    out.sort(key=lambda s: s.t)
    return out


def _window(samples: list[Sample], times: list[float], a: float,
            b: float) -> list[Sample]:
    import bisect
    i = bisect.bisect_left(times, a)
    j = bisect.bisect_right(times, b)
    return [s for s in samples[i:j] if s.ok]


def implicit_pairs(record: Record, samples: list[Sample], screen: Screen,
                   timeline: Timeline, cfg: dict) -> tuple[list[Pair], int]:
    """Неявные точки записи и сколько пар отброшено как «нажал не
    глядя»."""
    times = [s.t for s in samples]
    lo, hi = timeline.study_start, timeline.study_end
    seen: set[int] = set()
    pairs: list[Pair] = []
    dropped = 0
    before = float(cfg["pair_from_ms"])
    after = float(cfg["pair_to_ms"])
    need = int(cfg["pair_min_samples"])
    for event in record.events:
        if event["type"] not in IMPLICIT:
            continue
        n = _int(event.get("input"))
        if n is None or n in seen:
            continue
        data = event.get("data")
        if isinstance(data, dict) and data.get("panel") == "chrome":
            # Касание середины страницы прячет панели — цели у него нет.
            continue
        row = record.inputs.get(n)
        if row is None or row.get("dev") not in POINTERS or \
                row.get("kind") != "tap" or \
                row.get("screen") in EXPERIMENTER:
            continue
        t = _num(row.get("t"))
        x, y = _num(row.get("x")), _num(row.get("y"))
        if t is None or x is None or y is None or not lo <= t <= hi:
            continue
        seen.add(n)
        window = _window(samples, times, t - before, t - after)
        if len(window) < need:
            continue
        gx = statistics.median(s.x for s in window)
        gy = statistics.median(s.y for s in window)
        err = screen.angle_deg((gx, gy), (x, y))
        if err > float(cfg["pair_max_deg"]):
            dropped += 1
            continue
        pairs.append(Pair(t, event["type"], n, x, y, gx, gy, err))
    pairs.sort(key=lambda p: p.t)
    return pairs, dropped


@dataclass
class Drift:
    """Сдвиг `raw → drift` во времени: середины окон и сдвиг каждой."""

    centers: list[float]
    shifts: list[tuple[float, float]]
    counts: list[int]
    end: tuple[float, float] | None

    def at(self, t: float) -> tuple[float, float]:
        c = self.centers
        if not c:
            return 0.0, 0.0
        if t <= c[0]:
            return self.shifts[0]
        if t >= c[-1]:
            return self.shifts[-1]
        import bisect
        j = bisect.bisect_right(c, t)
        a, b = c[j - 1], c[j]
        w = (t - a) / (b - a) if b > a else 0.0
        (ax, ay), (bx, by) = self.shifts[j - 1], self.shifts[j]
        return ax + (bx - ax) * w, ay + (by - ay) * w

    @property
    def largest_px(self) -> float:
        return max((math.hypot(*s) for s in self.shifts), default=0.0)


def _correction(shift: tuple[float, float] | None,
                screen: Screen) -> tuple[float, float] | None:
    """Оценка ушла на `shift` мм от точек — поправка в пикселях в
    обратную сторону."""
    if shift is None:
        return None
    return (-shift[0] * screen.w / screen.w_mm,
            -shift[1] * screen.h / screen.h_mm)


def end_correction(timeline: Timeline,
                   screen: Screen) -> tuple[float, float] | None:
    """Поправка по проверке в конце, пиксели."""
    return _correction(timeline.end_shift_mm, screen)


def start_correction(timeline: Timeline,
                     screen: Screen) -> tuple[float, float]:
    """Поправка в начале изучения: по проверке сразу после калибровки,
    без неё — ноль (модель только что выучена)."""
    return _correction(timeline.start_shift_mm, screen) or (0.0, 0.0)


def build_drift(pairs: list[Pair], timeline: Timeline,
                end: tuple[float, float] | None, cfg: dict,
                skip: int | None = None,
                start: tuple[float, float] | None = None) -> Drift:
    """Поправка дрейфа по парам [pairs]; [skip] — номер пары, которую не
    брать (остаток «без своей точки»); [start] и [end] — опоры в начале
    и в конце изучения."""
    t0, t1 = timeline.study_start, timeline.study_end
    step = max(1.0, float(cfg["drift_step_s"])) * 1000
    half = max(1.0, float(cfg["drift_window_s"])) * 1000 / 2
    k0 = float(cfg["drift_k"])
    centers = []
    c = t0
    while True:
        centers.append(c)
        if c >= t1:
            break
        c = min(c + step, t1)
    values: list[tuple[float, float] | None] = []
    counts: list[int] = []
    for c in centers:
        own = [p for i, p in enumerate(pairs)
               if i != skip and c - half <= p.t <= c + half]
        counts.append(len(own))
        if not own:
            values.append(None)
            continue
        k = len(own) / (len(own) + k0)
        values.append((k * statistics.median(p.dx for p in own),
                       k * statistics.median(p.dy for p in own)))
    # Опоры: окна с парами и края изучения.
    anchors: list[tuple[float, tuple[float, float]]] = []
    if start is not None and values[0] is None:
        anchors.append((t0, start))
    anchors += [(centers[i], v) for i, v in enumerate(values)
                if v is not None]
    if end is not None and values[-1] is None:
        anchors.append((t1, end))
    filled: list[tuple[float, float]] = []
    for c, value in zip(centers, values):
        if value is not None:
            filled.append(value)
            continue
        left = [a for a in anchors if a[0] <= c]
        right = [a for a in anchors if a[0] > c]
        if left and right:
            (ta, va), (tb, vb) = left[-1], right[0]
            w = (c - ta) / (tb - ta) if tb > ta else 0.0
            filled.append((va[0] + (vb[0] - va[0]) * w,
                           va[1] + (vb[1] - va[1]) * w))
        elif left or right:
            filled.append((left[-1] if left else right[0])[1])
        else:
            filled.append((0.0, 0.0))
    return Drift(centers, filled, counts, end)


def apply(samples: list[Sample], drift: Drift) -> list[Sample]:
    """Версия `drift`: те же кадры со сдвигом."""
    out = []
    for s in samples:
        if not s.ok:
            out.append(s)
            continue
        dx, dy = drift.at(s.t)
        out.append(replace(s, x=s.x + dx, y=s.y + dy))
    return out


def residuals(pairs: list[Pair], timeline: Timeline,
              end: tuple[float, float] | None, screen: Screen,
              cfg: dict, start: tuple[float, float] | None = None) -> dict:
    """Остаток неявных точек до и после поправки — у каждой пары по
    поправке, посчитанной без неё (иначе поправка проверяла бы сама
    себя)."""
    raw = [p.err_deg for p in pairs]
    fixed = []
    for i, p in enumerate(pairs):
        drift = build_drift(pairs, timeline, end, cfg, skip=i, start=start)
        dx, dy = drift.at(p.t)
        fixed.append(screen.angle_deg((p.gx + dx, p.gy + dy), (p.tx, p.ty)))
    return {
        "pairs": len(pairs),
        "raw_deg": round(statistics.median(raw), 3) if raw else None,
        "drift_deg": round(statistics.median(fixed), 3) if fixed else None,
    }
