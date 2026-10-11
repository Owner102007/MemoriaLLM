"""Поправка ширины экрана места записи (шаг 39, решение владельца АМ2
от 11.10.2026).

Откуда данные: файл `ширина экрана.txt`, который организатор кладёт
рядом с архивами (в папку набора или в любую её подпапку, или рядом с
названным архивом). В репозиторий он не попадает: в нём коды
участников.
Технология: стандартная библиотека.
Метод: ширину экрана в «Месте записи» каждая ветвь мерит сама (по
карте или диагонали), и ветвь I на ноутбуке HP записала 396,1 мм при
настоящих 344 (паспорт экрана — 34 см). Градусы такой записи — в
чужой шкале. Поправка заменяет ширину и высоту экрана во всём, что
читает разбор, а углы, которые спутник посчитал по прежней ширине,
пересчитывает: при той же ошибке в точках окна ошибка в миллиметрах
растёт в отношении ширин k, а угол — как atan(k · tg θ). Расстояние
до глаз от ширины не зависит (спутник берёт его по размеру лица), и
поворот головы — тоже.

Чего поправка не меняет: точку взгляда в точках окна. Поправку на
голову спутник считал при записи по прежней ширине (`calib.Geometry`)
— её в разборе не повторить; это сказано в оговорке записи.

Вход → выход: файл ширин → ширина по коду участника или имени архива;
архив, прочитанный «Разбором записи», → тот же архив в верной шкале и
что поменялось.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

WIDTH_FILE = "ширина экрана.txt"

# Ширина экрана правдоподобна: от планшета до большого монитора, мм.
MIN_MM, MAX_MM = 100.0, 1500.0

_LINE = re.compile(r"^\s*(\S+?)\s*[=:\s]\s*([0-9]+(?:[.,][0-9]+)?)\s*"
                   r"(?:мм|mm)?\s*$", re.IGNORECASE)


def _mm(value: float) -> str:
    return f"{round(value, 1):g}".replace(".", ",")


def files(paths: list[str]) -> list[Path]:
    """Файлы ширины для набора [paths]: в папках — с подпапками, рядом
    с названными архивами — в их папке."""
    found: list[Path] = []
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            found.extend(sorted(path.rglob(WIDTH_FILE)))
        elif path.is_file():
            near = path.parent / WIDTH_FILE
            if near.is_file():
                found.append(near)
    seen: set[str] = set()
    out = []
    for f in found:
        key = str(f.resolve())
        if key not in seen:
            seen.add(key)
            out.append(f)
    return out


def _key(text: str) -> str:
    name = text.strip()
    return name[:-4] if name.lower().endswith(".zip") else name


def read(paths: list[str]) -> tuple[dict[str, float], list[str]]:
    """Ширины из файлов набора: ключ — код участника или имя архива без
    `.zip`, значение — ширина экрана, мм. Строка `код = мм`; `#` и всё
    за ним — пояснение. Ответ — ширины и оговорки: строка не понята,
    ширина неправдоподобна, у одного ключа две разные ширины (тогда
    ключ не правится вовсе)."""
    widths: dict[str, float] = {}
    notes: list[str] = []
    spoiled: set[str] = set()
    for path in files(paths):
        try:
            text = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeDecodeError) as e:
            notes.append(f"файл «{path.name}» не читается: {e}")
            continue
        for n, line in enumerate(text.splitlines(), start=1):
            body = line.split("#", 1)[0].strip()
            if not body:
                continue
            m = _LINE.match(body)
            if m is None:
                notes.append(f"«{path.name}», строка {n}: не понята — "
                             "нужно «код участника = ширина в мм»")
                continue
            key = _key(m.group(1))
            mm = float(m.group(2).replace(",", "."))
            if not MIN_MM <= mm <= MAX_MM:
                notes.append(f"«{path.name}», строка {n}: ширина "
                             f"{_mm(mm)} мм вне {_mm(MIN_MM)}–"
                             f"{_mm(MAX_MM)} мм — строка пропущена")
                continue
            if key in widths and abs(widths[key] - mm) > 1e-9:
                spoiled.add(key)
                continue
            widths[key] = mm
    for key in sorted(spoiled):
        notes.append(f"для «{key}» в файлах ширины две разные ширины — "
                     "ширина этой записи не исправлена")
        widths.pop(key, None)
    return widths, notes


def width_for(widths: dict[str, float], participant, archive: str
              ) -> float | None:
    """Ширина для записи: по коду участника, иначе по имени архива."""
    if participant is not None and str(participant) in widths:
        return widths[str(participant)]
    return widths.get(_key(archive))


def _num(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def _angle(value, k: float):
    """Угол на экране в новой шкале: atan(k · tg θ)."""
    v = _num(value)
    if v is None:
        return value
    return round(math.degrees(math.atan(k * math.tan(math.radians(v)))), 4)


def _shift(value, k: float):
    if isinstance(value, list) and len(value) == 2 and \
            all(_num(v) is not None for v in value):
        return [round(float(v) * k, 3) for v in value]
    return value


# Что в архиве меряется углом на экране и сдвигом по экрану. Углы
# головы (`turn_deg`, `tilt_deg`, `roll_deg`) и её место (`dx_mm`,
# `dy_mm`) — не по экрану: их поправка не трогает.
_ANGLES = ("accuracy_deg", "precision_deg", "worst_deg", "start_deg",
           "drift_deg")


def _fix_result(result, k: float) -> None:
    """Итог проверки точности: углы и общий сдвиг."""
    if not isinstance(result, dict):
        return
    for key in _ANGLES:
        if key in result:
            result[key] = _angle(result[key], k)
    if "shift_mm" in result:
        result["shift_mm"] = _shift(result["shift_mm"], k)


def _fix_screen(screen, w_mm: float, k: float) -> None:
    if not isinstance(screen, dict):
        return
    if _num(screen.get("w_mm")) is not None:
        screen["w_mm"] = w_mm
    if _num(screen.get("h_mm")) is not None:
        screen["h_mm"] = float(screen["h_mm"]) * k
    if _num(screen.get("px_per_mm")) is not None:
        screen["px_per_mm"] = float(screen["px_per_mm"]) / k


def old_width(record) -> float | None:
    """Ширина, с которой записан взгляд: экран калибровки спутника, а
    без него — место записи в сведениях."""
    cal = record.calibration if isinstance(record.calibration, dict) else {}
    screen = cal.get("screen") if isinstance(cal.get("screen"), dict) \
        else {}
    width = _num(screen.get("w_mm"))
    if width is None:
        place = (record.eye.get("place") or {})
        width = _num((place.get("screen") or {}).get("w_mm")) \
            if isinstance(place, dict) else None
    return width if width and width > 0 else None


def apply(record, w_mm: float) -> dict | None:
    """Поправить ширину экрана записи [record] на [w_mm] на месте.
    Ответ — что поменялось (`from_mm`, `to_mm`, `k`) или None, если
    поправлять нечего (ширина та же или неизвестна)."""
    old = old_width(record)
    if old is None or abs(w_mm - old) < 0.05:
        return None
    k = w_mm / old
    cal = record.calibration if isinstance(record.calibration, dict) \
        else None
    if cal is not None:
        _fix_screen(cal.get("screen"), w_mm, k)
        for attempt in cal.get("attempts") or []:
            if isinstance(attempt, dict):
                _fix_result(attempt.get("validation"), k)
        for check in cal.get("checks") or []:
            if isinstance(check, dict):
                _fix_result(check.get("result"), k)
    for check in record.checks:
        _fix_result(check, k)
    eye = record.manifest.get("eye_tracker")
    if isinstance(eye, dict):
        place = eye.get("place")
        if isinstance(place, dict):
            _fix_screen(place.get("screen"), w_mm, k)
        _fix_result(eye.get("calibration"), k)
        _fix_result(eye.get("end_check"), k)
    check = record.check
    for key in ("start_deg", "end_deg", "mean_deg"):
        if key in check:
            check[key] = _angle(check[key], k)
    return {"from_mm": old, "to_mm": w_mm, "k": k}


def note(fix: dict) -> str:
    """Оговорка записи словами."""
    return (f"ширина экрана исправлена по файлу «{WIDTH_FILE}»: "
            f"{_mm(fix['from_mm'])} → {_mm(fix['to_mm'])} мм; градусы "
            "пересчитаны, а поправка на голову при записи считалась с "
            "прежней шириной")
