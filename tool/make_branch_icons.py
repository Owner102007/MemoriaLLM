#!/usr/bin/env python3
"""Иконки сборок ветвей СНО2026: иконка приложения с плашкой «I» и «II».

SNO-F-CFG-01: три приложения из одного кода стоят на телефоне рядом, и
экспериментатор должен отличать их по иконке, не открывая. Плашка —
кружок акцентного цвета темы в правом нижнем углу с римской цифрой
ветви.

Скрипт перерисовывает иконки флейворов из иконки основного приложения
(`android/app/src/main/res/mipmap-*/ic_launcher.png`). Запускать заново
нужно, когда меняется она:

    python3 tool/make_branch_icons.py

Нужен Pillow. Шрифт плашки — DejaVu Serif Bold: римская цифра с
засечками читается как цифра, а без них «II» выглядит значком паузы.
Если шрифта нет в системе, скрипт останавливается с ошибкой, а не
рисует другим: иконки лежат в репозитории и должны получаться
одинаковыми.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src"
DENSITIES = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
# Флейвор Android → цифра на плашке.
BRANCHES = {"sno2026core": "I", "sno2026test": "II"}
# Акцент тёмно-красной темы и её основной текст (CLAUDE.md, «Оформление»).
BADGE = (0xA3, 0x2F, 0x35, 0xFF)
INK = (0xE8, 0xDC, 0xD8, 0xFF)
FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf")
# Рисуем вчетверо крупнее и уменьшаем: края плашки выходят гладкими.
SCALE = 4


def badge(icon: Image.Image, label: str) -> Image.Image:
    size = icon.width
    big = size * SCALE
    canvas = icon.convert("RGBA").resize((big, big), Image.LANCZOS)
    draw = ImageDraw.Draw(canvas)
    # Плашка занимает правую нижнюю четверть с небольшим запасом: цифра
    # читается и на самой мелкой иконке (48 точек).
    diameter = round(big * 0.56)
    left = big - diameter
    top = big - diameter
    draw.ellipse((left, top, big - 1, big - 1), fill=BADGE)
    height = round(diameter * (0.62 if len(label) == 1 else 0.52))
    font = ImageFont.truetype(str(FONT), height)
    box = draw.textbbox((0, 0), label, font=font)
    width = box[2] - box[0]
    tall = box[3] - box[1]
    x = left + (diameter - width) / 2 - box[0]
    y = top + (diameter - tall) / 2 - box[1]
    draw.text((x, y), label, font=font, fill=INK)
    return canvas.resize((size, size), Image.LANCZOS)


def main() -> int:
    if not FONT.exists():
        print(f"нет шрифта {FONT}", file=sys.stderr)
        return 1
    for flavor, label in BRANCHES.items():
        for density in DENSITIES:
            source = RES / "main" / "res" / f"mipmap-{density}" / "ic_launcher.png"
            target = RES / flavor / "res" / f"mipmap-{density}" / "ic_launcher.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            badge(Image.open(source), label).save(target, optimize=True)
            print(target.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
