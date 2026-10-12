"""Лесенка шума чтения — BUG-73, шаг 43 (`portrait.reading_fix_share`,
`portrait.lookback_noise_k`).

Синтетическое чтение (три страницы по 15 строк, `test_study_reading_
back.reading`) с заложенным взглядом назад на пять строк вверх на каждой
странице и тем же чтением без взглядов назад; к каждому кадру (33 мс)
прибавлен белый шум от 0 до 2,4° по каждой оси — шум кадра веб-камеры.
Для каждой ступени: доля времени взгляда на странице в фиксациях порога
чтения (после медианы трёх кадров), шум от кадра к кадру, порог скачка
`L`, сколько заложенных взглядов назад найдено и сколько найдено лишних.

Что из этого следует (12.10.2026, 4 повтора на ступень): при доле в
фиксациях от 0,75 (шум до 1,2°) и `k` = 3 находятся все заложенные
взгляды и нет ни одного лишнего; при 0,62 (1,5°) лишних уже 10 на 12
заложенных. Порог доли — 0,7, `k` — 3 (`thresholds.json`, `portrait`).
При `k` = 2,5 лишние появляются уже на 1,2°, при 3,5 — теряются
заложенные на 1,5°.
"""

from __future__ import annotations

import random

from sno_eye import report
from sno_eye.report.versions import Sample
from sno_eye.study import reading_back

from test_study_reading_back import PC, SCREEN, frame, line_of, reading

LEVELS = (0.0, 0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4)


def samples(looks, noise_px: float, seed: int) -> list[Sample]:
    rng = random.Random(seed)
    out = []
    for a, b, x, y in looks:
        t = a
        while t < b:
            out.append(Sample(t, x + rng.gauss(0, noise_px),
                              y + rng.gauss(0, noise_px), True, True))
            t += 33
    return out


def pages(backs: bool):
    """Три страницы чтения; ответ — взгляды, кадры, конец и заложенные
    миги взглядов назад."""
    looks, frames, planted = [], [], []
    t = 0.0
    for page in range(3):
        frames.append(frame(t, page=page + 1))
        part, t2 = reading(t0=t + 300, back_at=8 if backs else None)
        if backs:
            planted += [a for a, b, _, _ in part if b - a == 600]
        looks += part
        t = t2 + 300
    return looks, frames, t, planted


def step(noise_deg: float, seed: int, backs: bool, **portrait) -> dict:
    looks, frames, end, planted = pages(backs)
    pc = dict(PC, **portrait)
    out = reading_back.lookbacks(
        samples(looks, noise_deg * SCREEN.px_for_deg(1.0), seed), [],
        frames, SCREEN, line_of(end + 100), None, pc, report.settings())
    found = [e["t0"] for e in out["episodes"]]
    hits = sum(1 for p in planted if any(abs(f - p) <= 300 for f in found))
    return {"share": out["fix_share"], "s2s": out["s2s_deg"],
            "L": out.get("L_deg"), "reason": out["reason"],
            "planted": len(planted), "hits": hits,
            "extra": len(found) - hits}


def ladder(repeats: int = 4, **portrait) -> list[dict]:
    rows = []
    for level in LEVELS:
        row = {"noise": level, "share": 0.0, "planted": 0, "hits": 0,
               "extra": 0, "gated": 0, "runs": 0}
        for seed in range(repeats):
            for backs in (True, False):
                r = step(level, seed, backs, **portrait)
                row["runs"] += 1
                row["share"] += (r["share"] or 0.0)
                if r["reason"]:
                    row["gated"] += 1
                    continue
                row["planted"] += r["planted"]
                row["hits"] += r["hits"]
                row["extra"] += r["extra"]
        row["share"] /= row["runs"]
        rows.append(row)
    return rows


if __name__ == "__main__":  # pragma: no cover — печать лесенки
    for r in ladder():
        print(r)
