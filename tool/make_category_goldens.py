#!/usr/bin/env python3
"""Эталон вида категорий — второй, независимой реализацией.

Зачем. Узор и цвет категории выводятся из её названия, и читатель вправе
ожидать, что «Учёба» выглядит одинаково на телефоне и на ПК, сегодня и
через год. Проверить это тестом, который зовёт ту же функцию, нельзя: он
сверял бы её с самой собой. Поэтому здесь та же математика написана
заново, по описанию, а не переносом кода из Dart, и результат кладётся в
`test/goldens/category_styles.json`. Совпадение двух реализаций до
последнего бита практически исключает ошибку, а случайное изменение
формулы валит тест сразу — как это уже сделано для светофильтров чтения
(`tool/make_filter_goldens.py`).

Запуск:  python3 tool/make_category_goldens.py
"""

import json
import pathlib

# Палитры из lib/domain/theme/app_palette.dart: нужны только поверхность,
# основной текст и признак тёмной темы.
PALETTES = {
    "darkRed": {"surface": 0x170D0F, "text": 0xE8DCD8, "dark": True},
    "nightRed": {"surface": 0x0B0303, "text": 0xF0A8A8, "dark": True},
    "neutralDark": {"surface": 0x17171A, "text": 0xE6E6E9, "dark": True},
    "sepia": {"surface": 0xEDE3CA, "text": 0x3A2F1B, "dark": False},
    "light": {"surface": 0xF5F5F7, "text": 0x1A1A1C, "dark": False},
}

PATTERNS = ["planks", "diagonal", "checker", "dots", "herringbone", "weave"]
HUES = 12
TINT = 0.20
INK = 0.09

TITLES = [
    "Учёба",
    "учёба",
    "  Учёба  ",
    "Художественная литература",
    "Справочники",
    "Фантастика",
    "История",
    "Программирование",
    "Дочитать",
    "Сейчас читаю",
    "Ноты",
    "Без категории",
    "A",
    "Z",
    "日本語",
    "Мои книги 2026",
]


def stable_hash(text: str) -> int:
    """FNV-1a по 32 битам, по одной единице UTF-16 за шаг."""
    h = 0x811C9DC5
    for ch in text:
        code = ord(ch)
        for unit in ([code] if code <= 0xFFFF else [code & 0xFFFF, code >> 16]):
            h ^= unit & 0xFFFF
            h = (h * 16777619) & 0xFFFFFFFF
    return h


def normalize(title: str) -> str:
    return " ".join(title.split()).strip().lower()


def hsl_to_rgb(hue: float, sat: float, light: float) -> tuple:
    h = ((hue % 360) + 360) % 360 / 60.0
    c = (1 - abs(2 * light - 1)) * sat
    x = c * (1 - abs((h % 2) - 1))
    m = light - c / 2
    sector = int(h)
    table = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)]
    r, g, b = table[sector] if sector < 6 else table[5]
    return tuple(max(0, min(255, round((v + m) * 255))) for v in (r, g, b))


def mix(a: int, b: tuple, amount: float) -> int:
    out = 0
    for shift, to in zip((16, 8, 0), b):
        frm = (a >> shift) & 0xFF
        value = max(0, min(255, round(frm + (to - frm) * amount)))
        out |= value << shift
    return out


def channels(argb: int) -> tuple:
    return ((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)


def style_for(title: str) -> dict:
    seed = stable_hash(normalize(title))
    return {
        "seed": seed,
        "pattern": PATTERNS[(seed >> 3) % len(PATTERNS)],
        "hueIndex": (seed >> 9) % HUES,
        "phase": ((seed >> 17) % 1000) / 1000.0,
    }


def main() -> None:
    entries = []
    for title in TITLES:
        style = style_for(title)
        hue = style["hueIndex"] * 360.0 / HUES
        colours = {}
        for name, palette in PALETTES.items():
            tint = hsl_to_rgb(hue, 0.5, 0.34 if palette["dark"] else 0.62)
            background = mix(palette["surface"], tint, TINT)
            ink = mix(background, channels(palette["text"]), INK)
            colours[name] = {
                "background": 0xFF000000 | background,
                "ink": 0xFF000000 | ink,
            }
        entries.append({"title": title, **style, "colours": colours})

    out = pathlib.Path(__file__).resolve().parent.parent / "test/goldens/category_styles.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps({"styles": entries}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"записано {len(entries)} записей в {out}")


if __name__ == "__main__":
    main()
