"""Фиксации — I-DT (SNO-ALG-EYE-05, шаг 4).

* Порог разброса — наибольшее из 1,5° и трёх прецизионностей сессии:
  порог в 1° при 30 кадрах в секунду и дрожании веб-камеры лежит у
  уровня шума и дробил бы фиксации. Разброс окна — сумма размахов по
  осям.
* Длительность — не меньше 100 мс.
* Негодные кадры рвут фиксацию; провал короче 100 мс склеивается.
* Соседние фиксации, центры которых ближе порога, а разрыв короче
  75 мс, склеиваются.
* Место фиксации — медиана её кадров.
* **Отрезки движения раскладки** (листание, прокрутка, анимация — кадры
  `moving: true` до следующего устоявшегося) режут фиксацию; фиксация,
  которая начинается на таком отрезке, помечена `moving` и в меры зон
  не идёт.
"""

from __future__ import annotations

import bisect
import statistics
from dataclasses import dataclass, field

from .versions import Sample


@dataclass
class Fixation:
    """Фиксация: начало и конец по времени записи, место, кадры."""

    start: float
    end: float
    x: float
    y: float
    first: int                    # номер первого кадра в ряду
    last: int                     # номер последнего кадра в ряду
    moving: bool = False
    members: list[int] = field(default_factory=list)

    @property
    def duration(self) -> float:
        return self.end - self.start


def moving_spans(frames: list[dict]) -> list[tuple[float, float]]:
    """Отрезки движения раскладки: от кадра `moving: true` до следующего
    устоявшегося. Устоявшийся кадр помечен мигом последнего изменения,
    поэтому отрезок кончается его `t`."""
    spans: list[tuple[float, float]] = []
    begin = None
    for frame in frames:
        t = float(frame["t"])
        if frame.get("moving") is True:
            if begin is None:
                begin = t
        elif begin is not None:
            if t > begin:
                spans.append((begin, t))
            begin = None
    if begin is not None:
        spans.append((begin, float("inf")))
    return spans


def _in_spans(spans: list[tuple[float, float]], starts: list[float],
              t: float) -> bool:
    i = bisect.bisect_right(starts, t) - 1
    return i >= 0 and spans[i][0] <= t < spans[i][1]


def _runs(samples: list[Sample], spans: list[tuple[float, float]],
          bridge_ms: float) -> list[list[int]]:
    """Ряды годных кадров без разрывов длиннее [bridge_ms] и без границ
    отрезков движения внутри."""
    cuts = sorted({t for span in spans for t in span
                   if t != float("inf")})
    runs: list[list[int]] = []
    run: list[int] = []
    last_t = None
    for i, s in enumerate(samples):
        if not s.ok:
            continue
        if run:
            gap = s.t - last_t
            k = bisect.bisect_right(cuts, last_t)
            crossed = k < len(cuts) and cuts[k] <= s.t
            if gap > bridge_ms or crossed or \
                    s.seg != samples[run[-1]].seg:
                runs.append(run)
                run = []
        run.append(i)
        last_t = s.t
    if run:
        runs.append(run)
    return runs


def _dispersion(xs: list[float], ys: list[float]) -> float:
    return (max(xs) - min(xs)) + (max(ys) - min(ys))


def _make(samples: list[Sample], idx: list[int], period: float) -> Fixation:
    xs = [samples[i].x for i in idx]
    ys = [samples[i].y for i in idx]
    return Fixation(
        start=samples[idx[0]].t, end=samples[idx[-1]].t + period,
        x=statistics.median(xs), y=statistics.median(ys),
        first=idx[0], last=idx[-1], members=list(idx))


def period_of(samples: list[Sample]) -> float:
    """Промежуток между кадрами — медиана по годным соседям."""
    gaps = [b.t - a.t for a, b in zip(samples, samples[1:])
            if 0 < b.t - a.t < 200]
    return statistics.median(gaps) if gaps else 33.0


def fixations(samples: list[Sample], threshold_px: float,
              spans: list[tuple[float, float]], cfg: dict) -> list[Fixation]:
    """Фиксации ряда [samples] — по порогу разброса [threshold_px]."""
    min_ms = float(cfg["min_fix_ms"])
    period = period_of(samples)
    found: list[Fixation] = []
    for run in _runs(samples, spans, float(cfg["bridge_ms"])):
        start = 0
        while start < len(run):
            end = start
            t0 = samples[run[start]].t
            while end < len(run) and \
                    samples[run[end]].t + period - t0 < min_ms:
                end += 1
            if end >= len(run):
                break
            xs = [samples[i].x for i in run[start:end + 1]]
            ys = [samples[i].y for i in run[start:end + 1]]
            if _dispersion(xs, ys) > threshold_px:
                start += 1
                continue
            lo_x, hi_x, lo_y, hi_y = min(xs), max(xs), min(ys), max(ys)
            while end + 1 < len(run):
                s = samples[run[end + 1]]
                nx = (max(hi_x, s.x) - min(lo_x, s.x)) + \
                    (max(hi_y, s.y) - min(lo_y, s.y))
                if nx > threshold_px:
                    break
                lo_x, hi_x = min(lo_x, s.x), max(hi_x, s.x)
                lo_y, hi_y = min(lo_y, s.y), max(hi_y, s.y)
                end += 1
            found.append(_make(samples, run[start:end + 1], period))
            start = end + 1
    starts = [a for a, _ in spans]
    for fix in found:
        fix.moving = _in_spans(spans, starts, fix.start)
    return _merge(samples, found, threshold_px, spans,
                  float(cfg["merge_gap_ms"]), period)


def _merge(samples: list[Sample], found: list[Fixation], threshold: float,
           spans: list[tuple[float, float]], gap_ms: float,
           period: float) -> list[Fixation]:
    cuts = sorted({t for span in spans for t in span
                   if t != float("inf")})
    out: list[Fixation] = []
    for fix in found:
        if out:
            prev = out[-1]
            gap = fix.start - prev.end
            k = bisect.bisect_right(cuts, prev.start)
            crossed = k < len(cuts) and cuts[k] <= fix.start
            near = abs(fix.x - prev.x) + abs(fix.y - prev.y) <= threshold
            if gap < gap_ms and near and not crossed and \
                    fix.moving == prev.moving and \
                    samples[fix.first].seg == samples[prev.last].seg:
                merged = _make(samples, prev.members + fix.members, period)
                merged.moving = prev.moving
                out[-1] = merged
                continue
        out.append(fix)
    return out
