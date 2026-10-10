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
над выделением, переход к записи, звезда карты. Человек смотрит туда,
куда нажимает, — за 300–100 мс до нажатия. Пара — медиана взгляда в
этом окне и место нажатия; пара дальше 5° — «нажал не глядя», прочь.
Нажатия по зонам листания, колесо и клавиши в пары не идут.

**Поправка дрейфа**: окна по 5 минут со сдвигом в минуту; сдвиг окна —
медиана остатков его пар, ослабленная к нулю по их числу
(`k = n / (n + 5)`). Окно без пар берёт сдвиг ближайшего окна с парами,
а конец записи — проверки в конце. Между серединами окон сдвиг идёт
линейно.
"""

from __future__ import annotations

import math
import statistics
from dataclasses import dataclass, replace

from .archive import Record, _int, _num
from .screen import Screen
from .timeline import Timeline

# События, нажатие которых — неявная точка (SNO-ALG-EYE-05, шаг 2).
IMPLICIT = (
    "book.open", "nav.screen", "search.result.open", "toc.open",
    "toc.jump", "panel.open", "selection.action", "annotation.jump",
    "galaxy.star", "galaxy.card.open",
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


def end_correction(timeline: Timeline,
                   screen: Screen) -> tuple[float, float] | None:
    """Сдвиг по проверке в конце, пиксели: оценка ушла на `shift_mm` от
    точек — поправка в обратную сторону."""
    shift = timeline.end_shift_mm
    if shift is None:
        return None
    return (-shift[0] * screen.w / screen.w_mm,
            -shift[1] * screen.h / screen.h_mm)


def build_drift(pairs: list[Pair], timeline: Timeline,
                end: tuple[float, float] | None, cfg: dict,
                skip: int | None = None) -> Drift:
    """Поправка дрейфа по парам [pairs]; [skip] — номер пары, которую не
    брать (остаток «без своей точки»)."""
    t0, t1 = timeline.study_start, timeline.study_end
    step = float(cfg["drift_step_s"]) * 1000
    half = float(cfg["drift_window_s"]) * 1000 / 2
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
    known = [i for i, v in enumerate(values) if v is not None]
    filled: list[tuple[float, float]] = []
    for i, value in enumerate(values):
        if value is not None:
            filled.append(value)
            continue
        after = [j for j in known if j > i]
        if end is not None and not after:
            # Конец записи без пар — по проверке в конце.
            filled.append(end)
        elif known:
            j = min(known, key=lambda j: (abs(j - i), j))
            filled.append(values[j])  # type: ignore[arg-type]
        elif end is not None:
            filled.append(end)
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
              cfg: dict) -> dict:
    """Остаток неявных точек до и после поправки — у каждой пары по
    поправке, посчитанной без неё (иначе поправка проверяла бы сама
    себя)."""
    raw = [p.err_deg for p in pairs]
    fixed = []
    for i, p in enumerate(pairs):
        drift = build_drift(pairs, timeline, end, cfg, skip=i)
        dx, dy = drift.at(p.t)
        fixed.append(screen.angle_deg((p.gx + dx, p.gy + dy), (p.tx, p.ty)))
    return {
        "pairs": len(pairs),
        "raw_deg": round(statistics.median(raw), 3) if raw else None,
        "drift_deg": round(statistics.median(fixed), 3) if fixed else None,
    }
