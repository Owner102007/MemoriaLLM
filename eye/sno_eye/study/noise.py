"""Шум взгляда для мер беспорядочности и портрета (BUG-70, шаг 39;
SNO-ALG-RES-03, решение владельца АМ1 (а) от 11.10.2026).

Откуда данные: выборки взгляда «Разбора записи» (`report.analyse`,
`_samples`) — той версии, что выбрана для мер (`report.version`), и
фиксации общим порогом (`report.idt.fixations`), посчитанные по ним
после сглаживания.
Технология: стандартная библиотека.
Метод:

* **Сглаживание** — медиана [frames] кадров по каждой оси, только
  внутри подряд идущих годных кадров одного сегмента: разрыв сегмента,
  негодный кадр (моргание, лица нет) и просвет дольше полутора кадров
  насквозь не сглаживаются, крайние кадры отрезка остаются как есть.
  Медиана, а не скользящее среднее: скачок взгляда (саккада) остаётся
  ступенью и сдвигается не больше чем на кадр (медианный фильтр
  сохраняет края — Tukey J. W., «Exploratory Data Analysis», 1977;
  для данных айтрекера — Holmqvist K. и др., «Eye Tracking: A
  Comprehensive Guide to Methods and Measures», 2011, гл. 2).
  Частота кадров ниже [min_fps] — сглаживания нет: три кадра при 10
  кадрах в секунду — это 0,3 с, длиннее фиксации.
* **Доля времени в фиксациях** — время годных кадров изучения на
  экране, которые вошли в фиксацию вне отрезка движения раскладки, к
  времени всех годных кадров изучения на экране вне отлучек и отрезков
  движения. Кадр весит промежуток до следующего, не больше [cap_ms] —
  как у долей «Разбора записи» (`report.measures.label_samples`). Шум,
  который дробит фиксации, оставляет кадры между обрывками фиксаций —
  доля падает.
  Выбор наш: только кадры на экране (не дальше `outside_deg` за краем,
  как «вне экрана» у зон). Взгляд вне экрана — тетрадь, клавиатура —
  веб-камера оценивает хуже, и его доля зависит от того, сколько
  участник смотрел мимо экрана, а не от шума: у записей 10–11.10.2026
  вне экрана в фиксациях 61–88 % времени против 79–97 % на экране.
* **Шум от кадра к кадру** — RMS sample-to-sample: корень из среднего
  квадрата угла между соседними кадрами внутри фиксаций (Holmqvist K.,
  Nyström M., Mulvey F., «Eye tracker data quality: what it is and how
  to measure it», ETRA 2012). Соседи — соседние кадры одной фиксации
  не дальше полутора кадров друг от друга.

Вход → выход: выборки и фиксации записи → сглаженные выборки, доля
времени в фиксациях, шум от кадра к кадру до и после сглаживания.
"""

from __future__ import annotations

import bisect
import dataclasses
import math

from ..report import idt
from ..report.versions import Sample

# Соседние кадры дальше этой доли промежутка между кадрами — разрыв.
GAP_PERIODS = 1.5


def smooth(samples: list[Sample], frames: int, min_fps: float
           ) -> tuple[list[Sample], int, float | None]:
    """Медиана [frames] кадров по каждой оси (BUG-70).

    Ответ — выборки той же длины и в том же порядке (номера кадров
    фиксаций годятся для обоих рядов), сколько кадров на самом деле
    взято в медиану (1 — сглаживания не было) и частота кадров."""
    gaps = [b.t - a.t for a, b in zip(samples, samples[1:])
            if 0 < b.t - a.t < 200]
    if not gaps:
        return list(samples), 1, None
    period = idt.period_of(samples)
    fps = 1000.0 / period if period > 0 else None
    if frames < 3 or frames % 2 == 0 or fps is None or fps < min_fps:
        return list(samples), 1, fps
    half = frames // 2
    limit = GAP_PERIODS * period
    out = list(samples)
    for i in range(half, len(samples) - half):
        s = samples[i]
        if not s.ok:
            continue
        window = samples[i - half:i + half + 1]
        if any(not w.ok or w.seg != s.seg for w in window):
            continue
        if any(not 0 < b.t - a.t <= limit
               for a, b in zip(window, window[1:])):
            continue
        xs = sorted(w.x for w in window)
        ys = sorted(w.y for w in window)
        out[i] = dataclasses.replace(s, x=xs[half], y=ys[half])
    return out, frames, fps


def _in_spans(spans: list[tuple[float, float]], starts: list[float],
              t: float) -> bool:
    i = bisect.bisect_right(starts, t) - 1
    return i >= 0 and spans[i][0] <= t < spans[i][1]


def fix_share(samples: list[Sample], fixes: list, lo: float, hi: float,
              spans: list[tuple[float, float]], away, cap_ms: float,
              screen, outside_px: float) -> float | None:
    """Доля времени изучения [lo, hi) на экране в фиксациях (BUG-70).

    [fixes] — фиксации `report.idt.fixations` по [samples]; [away] —
    отлучка ли миг `t` (`Timeline.away_at`); на экране — не дальше
    [outside_px] за краем окна [screen]. Годных кадров на экране нет —
    None."""
    member = {i for f in fixes if not f.moving for i in f.members}
    starts = [a for a, _ in spans]
    inside = total = 0.0
    for i, s in enumerate(samples):
        if not s.ok or not lo <= s.t < hi:
            continue
        if away(s.t) or _in_spans(spans, starts, s.t):
            continue
        if s.x < -outside_px or s.y < -outside_px or \
                s.x > screen.w + outside_px or s.y > screen.h + outside_px:
            continue
        nxt = samples[i + 1].t if i + 1 < len(samples) else s.t + cap_ms
        ms = max(0.0, min(nxt - s.t, cap_ms, hi - s.t))
        total += ms
        if i in member:
            inside += ms
    return inside / total if total > 0 else None


def s2s_deg(samples: list[Sample], fixes: list, screen) -> float | None:
    """RMS sample-to-sample внутри фиксаций, градусы (BUG-70).

    Номера кадров фиксаций — номера в [samples]: так один и тот же
    набор пар меряет и сырой ряд, и сглаженный."""
    period = idt.period_of(samples)
    limit = GAP_PERIODS * period
    total = 0.0
    n = 0
    for f in fixes:
        if f.moving:
            continue
        for a, b in zip(f.members, f.members[1:]):
            sa, sb = samples[a], samples[b]
            if not sa.ok or not sb.ok or not 0 < sb.t - sa.t <= limit:
                continue
            angle = screen.angle_deg((sa.x, sa.y), (sb.x, sb.y))
            total += angle * angle
            n += 1
    return math.sqrt(total / n) if n else None
