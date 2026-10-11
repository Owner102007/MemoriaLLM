"""Лесенка шума (BUG-70, шаг 39): где шум веб-камеры начинает мерить
сам себя в энтропии поиска.

Путь взгляда поиска с известным ответом — фиксации 200–450 мс по
клеткам сетки окна 4 × 3: с вероятностью [order] взгляд идёт в
следующую клетку по порядку чтения, иначе — в случайную; скачок между
фиксациями — один кадр посередине (скачок на 5–15° длится 30–50 мс:
при 30 кадрах в секунду это кадр). На путь кладётся белый шум σ
градусов по каждой оси, кадр — 33 мс. Дальше — ровно то, что делает
«Сравнение ветвей»: медиана трёх кадров (`study.noise.smooth`),
фиксации общим порогом 4,5° (`report.idt.fixations`), доля времени в
фиксациях (`study.noise.fix_share`), переходы между клетками и
энтропия переходов на одинаковом числе переходов, делённая на
случайный уровень (`study.disorder.subsampled`, `random_level`).

Истина — то же самое без шума: так уход меряет только шум, а не то,
как порог 4,5° склеивает близкие фиксации одной клетки. Порог доли
`study.min_fix_share` — доля, ниже которой энтропия уходит от истины
больше чем на `BIAS` (на шкале «доля случайного уровня»).
"""

from __future__ import annotations

import random

from sno_eye.report import settings as report_settings
from sno_eye.report.screen import Screen
from sno_eye.report.versions import Sample
from sno_eye.report import idt
from sno_eye.study import disorder, noise

SCREEN = Screen(1280.0, 800.0, 340.0, 212.5, 600.0)
GRID = (4, 3)
PERIOD = 33.0
IDT_DEG = 4.5
K = 120              # переходов в подвыборке
REPEATS = 100
BIAS = 0.05          # уход энтропии от истины, доля случайного уровня
SIGMAS = tuple(round(0.1 * i, 1) for i in range(0, 31))
ZONES = disorder.search_zones(GRID)
INDEX = {z: i for i, z in enumerate(ZONES)}


def path(seed: int, fixations: int = 500, order: float = 0.5) -> list:
    """Фиксации пути: (длительность, x, y, клетка)."""
    rng = random.Random(seed)
    cols, rows = GRID
    cw, ch = SCREEN.w / cols, SCREEN.h / rows
    out = []
    cell = rng.randrange(cols * rows)
    for _ in range(fixations):
        if rng.random() < order:
            cell = (cell + 1) % (cols * rows)
        else:
            cell = rng.randrange(cols * rows)
        r, c = divmod(cell, cols)
        x = c * cw + rng.uniform(0.2, 0.8) * cw
        y = r * ch + rng.uniform(0.2, 0.8) * ch
        out.append((rng.uniform(200, 450), x, y, f"c{r}{c}"))
    return out


def samples(fixes: list, sigma_deg: float, seed: int) -> list[Sample]:
    """Кадры пути с белым шумом σ градусов по оси."""
    rng = random.Random(seed * 7919 + 13)
    sigma = SCREEN.px_for_deg(sigma_deg)
    out: list[Sample] = []
    t = 0.0
    prev = None
    for d, x, y, _ in fixes:
        if prev is not None:
            out.append(Sample(t, (prev[0] + x) / 2 + rng.gauss(0, sigma),
                              (prev[1] + y) / 2 + rng.gauss(0, sigma),
                              True, True))
            t += PERIOD
        end = t + d
        while t < end:
            out.append(Sample(t, x + rng.gauss(0, sigma),
                              y + rng.gauss(0, sigma), True, True))
            t += PERIOD
        prev = (x, y)
    return out


def _entropy(trans: list, seed: int) -> float | None:
    if len(trans) < K:
        return None
    n = len(ZONES)
    ht, _ = disorder.subsampled(trans, n, K, REPEATS, seed)
    level, _ = disorder.random_level(n, K, REPEATS, seed + 1)
    return ht / level


def step(fixes: list, sigma_deg: float, seed: int,
         frames: int = 3) -> dict:
    """Одна ступень: доля в фиксациях и энтропия при шуме σ."""
    cfg = report_settings()
    rows = samples(fixes, sigma_deg, seed)
    smoothed, _, _ = noise.smooth(rows, frames, 25)
    found = idt.fixations(smoothed, SCREEN.px_for_deg(IDT_DEG), [], cfg, [])
    share = noise.fix_share(smoothed, found, 0.0, rows[-1].t + PERIOD, [],
                            lambda t: False, float(cfg["sample_cap_ms"]),
                            SCREEN, SCREEN.px_for_deg(2.0))
    cells = [INDEX[disorder.cell_of(f.x, f.y, SCREEN.w, SCREEN.h,
                                    SCREEN.px_for_deg(2.0), GRID)]
             for f in found]
    trans = [(a, b) for (fa, a), (fb, b) in
             zip(zip(found, cells), zip(found[1:], cells[1:]))
             if fb.start - fa.end <= 1000]
    return {"sigma": sigma_deg, "share": share, "h": _entropy(trans, seed),
            "fixations": len(found),
            "s2s": noise.s2s_deg(smoothed, found, SCREEN)}


def ladder(seeds=(1, 2, 3, 4, 5), sigmas=SIGMAS,
           frames: int = 3) -> list[dict]:
    """Ступени лесенки: доля и уход энтропии от истины, по зёрнам."""
    out = []
    for seed in seeds:
        fixes = path(seed)
        h0 = step(fixes, 0.0, seed, frames)["h"]
        for sigma in sigmas:
            row = step(fixes, sigma, seed, frames)
            row["seed"] = seed
            row["bias"] = None if row["h"] is None else row["h"] - h0
            out.append(row)
    return out


if __name__ == "__main__":
    for frames in (1, 3):
        print(f"кадров в медиане: {frames}")
        for r in ladder(frames=frames):
            bias = None if r["bias"] is None else round(r["bias"], 3)
            print(f"  σ {r['sigma']:4.2f}°  зерно {r['seed']}  доля "
                  f"{r['share']:.3f}  фиксаций {r['fixations']:4d}  "
                  f"уход {bias}  s2s {r['s2s'] and round(r['s2s'], 2)}")
