"""Шаг 3 — цвет искренности и вес участника (SNO-ALG-RES-01, шаги 8–9).

Откуда данные: два пункта шкалы лжи теста нагрузки — `lie.defer` и
`lie.late`: ответ — файл ответов части (`clt/<сценарий>_<часть>_<t>.json`),
отметка приложения — `clt/scores.json` → `checks.items.<пункт>.flag`,
правило отметки — `flag` пункта в `clt/scenario.json` (`study.clt`).
Технология: стандартная библиотека.
Метод: решение владельца от 10.10.2026 (раздел АК в «06 Решения
владельца»): провален один пункт — работа с отметкой и меньшим весом;
провалены оба — «красная», участник целиком вне статистики. Вес жёлтого
— АК1, «честность неизвестна» — АК3, «провален» — АК2 (то же правило,
что у приложения).
Вход → выход: отметки двух пунктов и состояние теста → цвет, вес,
причина словами.

Прочие отметки теста — `chk.focus`, `chk.books`, быстрые ответы, одна
кнопка подряд, вердикт приложения — цвет не меняют (АК5): они стоят в
таблице участников столбцами «небрежность».
"""

from __future__ import annotations

# Пункты шкалы лжи — `lib/sno/clt/builtin_scenario.dart`, решение АЗ.
LIE_ITEMS = ("lie.defer", "lie.late")

GREEN = "green"
YELLOW = "yellow"
UNKNOWN = "unknown"
RED = "red"

# Цвет словами — для таблиц и отчёта. Значок рядом со словом, а не
# вместо него: цвет не несёт смысл один.
WORDS = {GREEN: "🟢 искренен", YELLOW: "🟡 один пункт провален",
         UNKNOWN: "⚪ честность неизвестна", RED: "🔴 оба пункта провалены"}
SHORT = {GREEN: "🟢", YELLOW: "🟡", UNKNOWN: "⚪", RED: "🔴"}

# Вес по умолчанию; настоящие — `study.yellow_weight` и
# `study.unknown_weight` в `thresholds.json`.
DEFAULT_WEIGHTS = {GREEN: 1.0, YELLOW: 0.5, UNKNOWN: 0.5, RED: 0.0}


def flagged(value, rule: dict | None) -> bool | None:
    """Попал ли ответ в отметку пункта — правило приложения
    (`cltChecks` в `lib/sno/clt/results.dart`): `min` — не меньше,
    `max` — не больше; оба — между. Нет ответа или правила — None."""
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return None
    if not isinstance(rule, dict):
        return None
    lo, hi = rule.get("min"), rule.get("max")
    if lo is None and hi is None:
        return None
    if lo is not None and value < lo:
        return False
    if hi is not None and value > hi:
        return False
    return True


def colour(flags: dict) -> tuple[str, str]:
    """Цвет по отметкам двух пунктов шкалы лжи.

    [flags] — пункт → True (провален), False (отвечен, не провален),
    None (без ответа или теста нет).

    | пункты                                        | цвет |
    |-----------------------------------------------|------|
    | оба отвечены, ни один не провален             | 🟢   |
    | провален один, второй отвечен или без ответа  | 🟡   |
    | провалены оба                                 | 🔴   |
    | провалов нет, но хотя бы один без ответа      | ⚪   |

    Отвечает (цвет, причина словами)."""
    values = [flags.get(item) for item in LIE_ITEMS]
    failed = [item for item, v in zip(LIE_ITEMS, values) if v is True]
    if len(failed) == 2:
        return RED, "провалены оба пункта шкалы лжи"
    if len(failed) == 1:
        return YELLOW, f"провален пункт {failed[0]}"
    if all(v is False for v in values):
        return GREEN, "оба пункта шкалы лжи не провалены"
    missing = [item for item, v in zip(LIE_ITEMS, values) if v is None]
    return UNKNOWN, "нет ответа: " + ", ".join(missing)


def weight(code: str, weights: dict) -> float:
    """Вес участника по цвету: 🟢 — 1, 🟡 — `yellow_weight`,
    ⚪ — `unknown_weight` (АК3 (а): как 🟡), 🔴 — 0."""
    return float(weights.get(code, DEFAULT_WEIGHTS[code]))
