#!/usr/bin/env python3
"""Эталонная таблица светофильтров чтения.

Зачем отдельная реализация на Python. Обычные golden-тесты сравнивают
картинки, но картинку фильтра в `flutter test` не получить: шейдеры там
не собираются вовсе, а растеризация отличается от платформы к платформе.
Поэтому «эталоном» здесь служит таблица чисел, посчитанная **другой**
реализацией той же математики: если Dart и Python сходятся до шестого
знака, ошибка в формуле практически исключена, а любое случайное
изменение фильтра сразу валит тест.

Порядок и все числа обязаны совпадать с
`lib/domain/reading/reading_filter.dart` и `shaders/reading_filter.frag`.

Запуск:

    python3 tool/make_filter_goldens.py
"""

from __future__ import annotations

import json
import pathlib

OUTPUT = pathlib.Path("test/goldens/reading_filters.json")

WR, WG, WB = 0.2126, 0.7152, 0.0722
SAT_LOW, SAT_HIGH = 0.10, 0.30

SEPIA = (
    (0.393, 0.769, 0.189),
    (0.349, 0.686, 0.168),
    (0.272, 0.534, 0.131),
)

SAMPLES = [
    (1.0, 1.0, 1.0),      # бумага
    (0.0, 0.0, 0.0),      # текст
    (0.5, 0.5, 0.5),      # серая заливка
    (0.92, 0.89, 0.84),   # желтоватая бумага скана
    (0.2, 0.2, 0.2),      # тёмно-серый
    (0.8, 0.1, 0.1),      # красная иллюстрация
    (0.1, 0.3, 0.8),      # синяя иллюстрация
    (0.95, 0.75, 0.2),    # жёлтая иллюстрация
]

CASES = [
    ("none", 0.0, 1.0, 1.0, 1.0),
    ("nightRed", 0.9, 1.0, 1.0, 1.0),
    ("nightRed", 0.5, 1.0, 1.0, 1.0),
    ("warm", 0.6, 1.0, 1.0, 1.0),
    ("sepia", 0.8, 1.0, 1.0, 1.0),
    ("invert", 1.0, 1.0, 1.0, 1.0),
    ("none", 0.0, 1.0, 1.0, 1.4),
    ("none", 0.0, 1.0, 1.5, 1.0),
    ("none", 0.0, 0.4, 1.0, 1.0),
    ("nightRed", 0.9, 0.5, 1.2, 1.3),
    ("invert", 1.0, 0.8, 1.4, 0.8),
]


def clamp(value: float, low: float, high: float) -> float:
    return low if value < low else (high if value > high else value)


def mix(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def apply(
    color: tuple[float, float, float],
    mode: str,
    intensity: float,
    brightness: float,
    contrast: float,
    gamma: float,
) -> list[float]:
    t = clamp(intensity, 0.0, 1.0)
    br = clamp(brightness, 0.05, 1.0)
    k = clamp(contrast, 0.2, 3.0)
    g = clamp(gamma, 0.2, 3.0)

    r, gr, b = (clamp(c, 0.0, 1.0) ** g for c in color)
    r, gr, b = ((c - 0.5) * k + 0.5 for c in (r, gr, b))

    if t > 0.0:
        if mode == "nightRed":
            lum = WR * r + WG * gr + WB * b
            r, gr, b = mix(r, lum, t), mix(gr, 0.0, t), mix(b, 0.0, t)
        elif mode == "warm":
            gr, b = mix(gr, gr * 0.88, t), mix(b, b * 0.55, t)
        elif mode == "sepia":
            sr = SEPIA[0][0] * r + SEPIA[0][1] * gr + SEPIA[0][2] * b
            sg = SEPIA[1][0] * r + SEPIA[1][1] * gr + SEPIA[1][2] * b
            sb = SEPIA[2][0] * r + SEPIA[2][1] * gr + SEPIA[2][2] * b
            r, gr, b = mix(r, sr, t), mix(gr, sg, t), mix(b, sb, t)
        elif mode == "invert":
            picture = smoothstep(
                SAT_LOW, SAT_HIGH, max(r, gr, b) - min(r, gr, b)
            )
            r = mix(r, mix(1.0 - r, r, picture), t)
            gr = mix(gr, mix(1.0 - gr, gr, picture), t)
            b = mix(b, mix(1.0 - b, b, picture), t)

    return [clamp(c * br, 0.0, 1.0) for c in (r, gr, b)]


def main() -> None:
    cases = []
    for mode, intensity, brightness, contrast, gamma in CASES:
        cases.append(
            {
                "filter": mode,
                "intensity": intensity,
                "brightness": brightness,
                "contrast": contrast,
                "gamma": gamma,
                "samples": [
                    {
                        "in": list(sample),
                        "out": apply(
                            sample, mode, intensity, brightness, contrast, gamma
                        ),
                    }
                    for sample in SAMPLES
                ],
            }
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(
            {
                "note": (
                    "Посчитано tool/make_filter_goldens.py — независимой "
                    "реализацией той же математики. Правится только вместе "
                    "с lib/domain/reading/reading_filter.dart и "
                    "shaders/reading_filter.frag."
                ),
                "cases": cases,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"{OUTPUT}: {len(cases)} наборов по {len(SAMPLES)} цветов")


if __name__ == "__main__":
    main()
