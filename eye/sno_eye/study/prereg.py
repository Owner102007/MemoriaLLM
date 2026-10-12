"""Вердикт предрегистрации «Галактики» (SNO-ALG-RES-13) и опора на
ориентиры на карте (SNO-ALG-RES-14); шаг 43, решения владельца АО15 и
АО16 от 12.10.2026.

Откуда данные: ожидания и правило вердикта — заметка «Галактика —
ожидаемое влияние сортировки (предрегистрация)» описательной структуры,
записанная 12.10.2026 до того, как загружены записи первого контакта;
числа порогов — раздел `study.prereg` файла `eye/thresholds.json`
(тест `test_step43.py` сверяет их с таблицей предрегистрации, и
поправить порог, не уронив тест, нельзя). Меры участника — порядок
обхода (`study.order`), тест нагрузки (`study.clt`), действия
(`study.actions`), научение (`study.average`), взгляд
(`study.disorder`), опора на ориентиры (`landmark` ниже, по таблице
«Перед нажатием» «Разбора записи» — `report/presses.py` без изменений).
Технология: стандартная библиотека.
Метод: правило каждой меры — «за», «против», «между» или «не
считается» с причиной; вердикт — по главным ожиданиям М2–М5: «за» хотя
бы в трёх из четырёх у не меньше чем двух третей участников со
взглядом и тестом — подтверждено; «против» так же — опровергнуто;
иначе — не решено. Записи первого контакта — те, где книги выбирались
картой и начатые после `study.prereg.after`; записи «Галактики»
раньше — справкой.
Вход → выход: записи после отбора → таблица «участник × М1–М10» и
вердикт.
"""

from __future__ import annotations

import math
from datetime import datetime

from . import honesty
from .actions import MODE_MAP
from .clt import DONE

FOR = "за"
AGAINST = "против"
BETWEEN = "между"
NONE = "не считается"

CONFIRMED = "подтверждено"
REFUTED = "опровергнуто"
UNDECIDED = "не решено"
FEW = "не решено: мало записей"
EMPTY = "записей первого контакта нет"

# Пороги предрегистрации по умолчанию — те же, что в `thresholds.json`
# и в таблице заметки «Галактика — ожидаемое влияние сортировки
# (предрегистрация)»; выбор исполнителя до данных — там же
# (SNO-ALG-RES-13, «Правила мер»).
DEFAULTS = {
    "after": "2026-10-12T21:00:00+03:00",
    "main": ["M2", "M3", "M4", "M5"],
    "of_main": 3,
    "share": 2 / 3,
    "min_people": 3,
    "M1_rho": 0.8, "M1_alpha": 0.05,
    "M2_for": 0.60, "M2_against": 0.66,
    "M3_shelf": 4.3,
    "M4_orient1": 6, "M4_orient2": 5,
    "M5_for": 0.5, "M5_min_presses": 2,
    "M6_for": 2, "M6_against": 4,
    "M7_shelf": 3.9, "M7_fail": 60,
    "M8_low": 3, "M8_high": 5,
    "M9_for": 1.0,
    "M10_for": 0.30, "M10_against": 0.50,
}

MEASURES = (
    ("M1", "Маршрут следует высоте звёзд", "ρ"),
    ("M2", "Маршрут плавнее по смыслу", "к случайному"),
    ("M3", "Нагрузка от интерфейса (ECL)", "1–7"),
    ("M4", "Самооценка ориентации", "1–7"),
    ("M5", "Опора на ориентиры", "доля выборов"),
    ("M6", "Группы читаются целиком", "смен группы"),
    ("M7", "Цена новизны — вход в интерфейс", "с"),
    ("M8", "Выбор после первого похода", "с"),
    ("M9", "Режимы «где» и «что»", "чтение / выбор"),
    ("M10", "Ложные пробы", "доля карточек"),
)
TITLES = {key: title for key, title, _ in MEASURES}


def settings(raw: dict | None) -> dict:
    out = dict(DEFAULTS)
    for key, default in DEFAULTS.items():
        value = (raw or {}).get(key)
        if isinstance(default, str):
            if isinstance(value, str):
                out[key] = value
        elif isinstance(default, list):
            if isinstance(value, list) and value:
                out[key] = [str(v) for v in value]
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            out[key] = value
    return out


def started(e: dict) -> datetime | None:
    """Начало записи — `clock_anchor` из сведений записи (настенное
    время со смещением пояса)."""
    raw = e.get("clock_anchor")
    if not isinstance(raw, str):
        return None
    try:
        when = datetime.fromisoformat(raw)
    except ValueError:
        return None
    return when if when.tzinfo is not None else None


def first_contact(e: dict, after: datetime) -> bool:
    when = started(e)
    return when is not None and when >= after


def _num(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def answer(e: dict, item: str) -> float | None:
    test = e.get("test") or {}
    if test.get("state") != DONE:
        return None
    for a in test.get("answers") or []:
        if a.get("item") == item:
            return _num(a.get("value"))
    return None


def landmark(res: dict) -> dict:
    """SNO-ALG-RES-14: доля выборов звезды, перед которыми взгляд был в
    её группе («Перед нажатием», «мягко»), и случайный уровень — доля
    видимого полотна карты, которую то же правило категорий относит к
    этой группе (сетка `GRID` точек по полотну кадра в миг нажатия)."""
    zones = res.get("_zones")
    rows = [r for r in res.get("presses") or []
            if r.get("screen") == "galaxy" and r.get("in_target_soft")
            is not None]
    out = {"presses": len(rows), "hits": sum(1 for r in rows
                                             if r["in_target_soft"]),
           "share": None, "chance": None}
    if not rows:
        return out
    out["share"] = out["hits"] / len(rows)
    if zones is None:
        return out
    from ..report.measures import margin_deg
    screen = res.get("_screen")
    line = res.get("_timeline")
    chances = []
    for r in rows:
        frame = zones.frame_at(r["t"])
        rect = None
        for z in (frame or {}).get("regions") or []:
            if z.get("kind") == "galaxy_map":
                rect = z.get("rect")
        if not rect or screen is None or line is None:
            continue
        margin = screen.px_for_deg(margin_deg(r["t"], line))
        left, top, w, h = (float(v) for v in rect)
        inside = total = 0
        for i in range(GRID[0]):
            for j in range(GRID[1]):
                x = left + (i + 0.5) * w / GRID[0]
                y = top + (j + 0.5) * h / GRID[1]
                z = zones.classify(r["t"] - 200, x, y, margin)
                total += 1
                inside += z.get("category") == r["target"]
        if total:
            chances.append(inside / total)
    if chances:
        out["chance"] = sum(chances) / len(chances)
    return out


# Сетка случайного уровня: столбцов × строк по полотну карты.
GRID = (32, 20)


def measures_of(e: dict, value) -> dict:
    """Числа М1–М10 участника; [value] — `single.value`."""
    order = e.get("order") or {}
    look = ((e.get("gaze_data") or {}).get("landmark")) or {}
    return {
        "M1": (value(e, "order.rho_map"), order.get("p_map")),
        "M2": value(e, "order.route_map"),
        "M3": value(e, "clt.ecl"),
        "M4": (answer(e, "orient.1"), answer(e, "orient.2")),
        "M5": (look.get("share"), look.get("chance"),
               look.get("presses") or 0),
        "M6": value(e, "order.cat_switches"),
        "M7": value(e, "learn.entry_s"),
        "M8": value(e, "learn.after_first_s"),
        "M9": value(e, "gaze.read_vs_search"),
        "M10": value(e, "actions.cards_unread_share"),
    }


def _fmt(x, digits=2) -> str:
    if x is None:
        return "—"
    return f"{x:.{digits}f}".replace(".", ",")


def judge(key: str, m, pc: dict, has_gaze: bool) -> tuple[str, str]:
    """Вид и слова одной меры участника по правилу предрегистрации."""
    if key == "M1":
        rho, p = m
        if rho is None:
            return NONE, "маршрута по карте нет"
        if rho >= pc["M1_rho"]:
            return FOR, f"ρ {_fmt(rho)} ≥ {_fmt(pc['M1_rho'], 1)}"
        if p is not None and p >= pc["M1_alpha"]:
            return AGAINST, (f"ρ {_fmt(rho)}, маршрут от случайного не "
                             f"отличается (p {_fmt(p, 3)})")
        return BETWEEN, f"ρ {_fmt(rho)}"
    if key == "M2":
        if m is None:
            return NONE, "маршрута по карте нет"
        if m <= pc["M2_for"]:
            return FOR, f"{_fmt(m)} ≤ {_fmt(pc['M2_for'])}"
        if m >= pc["M2_against"]:
            return AGAINST, f"{_fmt(m)} ≥ {_fmt(pc['M2_against'])}"
        return BETWEEN, _fmt(m)
    if key == "M3":
        if m is None:
            return NONE, "тест нагрузки не пройден"
        if m < pc["M3_shelf"]:
            return FOR, f"{_fmt(m)} < {_fmt(pc['M3_shelf'], 1)}"
        return AGAINST, f"{_fmt(m)} ≥ {_fmt(pc['M3_shelf'], 1)}"
    if key == "M4":
        a, b = m
        if a is None or b is None:
            return NONE, "тест нагрузки не пройден"
        words = f"{_fmt(a, 0)} и {_fmt(b, 0)}"
        if a >= pc["M4_orient1"] and b >= pc["M4_orient2"]:
            return FOR, words + " — не ниже полки"
        if a < pc["M4_orient1"] and b < pc["M4_orient2"]:
            return AGAINST, words + " — оба ниже полки"
        return BETWEEN, words
    if key == "M5":
        share, chance, n = m
        if not has_gaze:
            return NONE, "взгляд хуже 3° или его нет"
        if share is None or n < pc["M5_min_presses"]:
            return NONE, f"выборов со взглядом {n}"
        words = f"{_fmt(share)} при случайном {_fmt(chance)} ({n} выб.)"
        if chance is not None and share < chance:
            return AGAINST, words
        if share >= pc["M5_for"] and (chance is None or share > chance):
            return FOR, words
        return BETWEEN, words
    if key == "M6":
        if m is None:
            return NONE, "маршрута нет"
        if m <= pc["M6_for"]:
            return FOR, f"{m:.0f} ≤ {pc['M6_for']:g}"
        if m >= pc["M6_against"]:
            return AGAINST, f"{m:.0f} ≥ {pc['M6_against']:g}"
        return BETWEEN, f"{m:.0f}"
    if key == "M7":
        if m is None:
            return NONE, "первого похода нет"
        if m > pc["M7_fail"]:
            return AGAINST, f"{_fmt(m, 1)} с — дольше минуты (провал)"
        if m > pc["M7_shelf"]:
            return FOR, f"{_fmt(m, 1)} с — дольше полки (цена новизны)"
        return BETWEEN, f"{_fmt(m, 1)} с — не дороже полки"
    if key == "M8":
        if m is None:
            return NONE, "походов после первого нет"
        if pc["M8_low"] <= m <= pc["M8_high"]:
            return FOR, f"{_fmt(m, 1)} с — как ожидалось"
        return BETWEEN, f"{_fmt(m, 1)} с"
    if key == "M9":
        if not has_gaze or m is None:
            return NONE, "взгляд хуже 3°, шумный или его нет"
        if m > pc["M9_for"]:
            return FOR, f"×{_fmt(m)}"
        return AGAINST, f"×{_fmt(m)}"
    if key == "M10":
        if m is None:
            return NONE, "карточек не открывали"
        if m <= pc["M10_for"]:
            return FOR, f"{_fmt(m)} ≤ {_fmt(pc['M10_for'])}"
        if m > pc["M10_against"]:
            return AGAINST, f"{_fmt(m)} > {_fmt(pc['M10_against'])}"
        return BETWEEN, _fmt(m)
    raise KeyError(key)


def row_of(e: dict, value, pc: dict) -> dict:
    """Строка участника: М1–М10, «за» и «против» главных, годен ли он для
    вердикта и почему нет."""
    has_gaze = bool((e.get("gaze") or {}).get("included"))
    test_done = (e.get("test") or {}).get("state") == DONE
    nums = measures_of(e, value)
    cells = {}
    for key, _, _ in MEASURES:
        kind, words = judge(key, nums[key], pc, has_gaze)
        cells[key] = {"kind": kind, "words": words}
    main = list(pc["main"])
    why = []
    if not has_gaze:
        why.append("взгляд хуже 3° или его нет")
    if not test_done:
        why.append("тест нагрузки не пройден")
    if e.get("colour") == honesty.RED:
        why.append("🔴 вне статистики")
    return {
        "participant": e.get("participant"), "archive": e["archive"],
        "stratum": e.get("stratum"), "colour": e.get("colour"),
        "started": e.get("clock_anchor"), "cells": cells,
        "for_main": sum(1 for k in main if cells[k]["kind"] == FOR),
        "against_main": sum(1 for k in main
                            if cells[k]["kind"] == AGAINST),
        "eligible": not why, "why_not": why,
    }


def verdict(rows: list[dict], pc: dict) -> dict:
    """Правило предрегистрации по строкам участников вердикта."""
    people = [r for r in rows if r["eligible"]]
    n = len(people)
    need = int(pc["of_main"])
    pros = sum(1 for r in people if r["for_main"] >= need)
    cons = sum(1 for r in people if r["against_main"] >= need)
    out = {"n": n, "first_contact": len(rows), "for": pros,
           "against": cons, "need_people": None, "word": None}
    if not rows:
        out["word"] = EMPTY
        return out
    if n < int(pc["min_people"]):
        out["word"] = FEW
        return out
    share = float(pc["share"])
    # «Не меньше двух третей» — с допуском на запись дроби числом.
    out["need_people"] = math.ceil(share * n - 1e-9)
    if pros >= share * n - 1e-9:
        out["word"] = CONFIRMED
    elif cons >= share * n - 1e-9:
        out["word"] = REFUTED
    else:
        out["word"] = UNDECIDED
    return out


def evaluate(entries: list[dict], cfg: dict, value, hard_out) -> dict:
    """Первый контакт против предрегистрации: строки участников, справка
    (записи «Галактики» до отметки) и вердикт. [hard_out] — почему запись
    вне статистики целиком (`compare.hard_out` с параметрами прогона)."""
    pc = settings(cfg.get("prereg"))
    after = datetime.fromisoformat(pc["after"])
    first, before = [], []
    for e in entries:
        if e.get("status") != "ok" or e.get("search_mode") != MODE_MAP:
            continue
        out = hard_out(e)
        row = row_of(e, value, pc)
        if out:
            row["eligible"] = False
            row["why_not"] = list(out) + row["why_not"]
        if first_contact(e, after):
            first.append(row)
        else:
            before.append(row)
    return {"settings": pc, "after": pc["after"], "rows": first,
            "reference": before, "verdict": verdict(first, pc),
            "measures": [{"key": k, "title": t, "unit": u}
                         for k, t, u in MEASURES]}
