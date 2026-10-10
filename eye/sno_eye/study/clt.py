"""Шаг 2 — расшифровка теста нагрузки (SNO-ALG-RES-02, «Тест нагрузки»).

Откуда данные: файлы теста в архиве записи — сценарий таким, каким его
видел участник (`clt/scenario.json`), ответы части
(`clt/<сценарий>_<часть>_<t>.json`, массив `answers`), показатели и
самопроверка ответов, посчитанные приложением (`clt/scores.json`,
`lib/sno/clt/results.dart`).
Технология: `json` и `statistics` стандартной библиотеки.
Метод: правило «Подсчёт» из «Cognitive load test — состав теста»:
группа — идентификатор пункта до последней точки; обратный пункт
переворачивается: min + max − ответ; пункты `role: check` в шкалы не
входят; значение шкалы — среднее ответов группы. Шкала, на которую
ответили меньше чем на половину пунктов, пустая. Шкалы считаются здесь
заново и сверяются с приложением; в сравнение идут числа приложения —
код главнее (АД1).
Вход → выход: файлы теста одной записи → ответы строками, шкалы
нагрузки, отметки шкалы лжи и «небрежности», оговорки.
"""

from __future__ import annotations

import json
import statistics

from . import honesty

# Шкалы — ключ меры, группа пунктов и слова. Порядок — порядок в отчёте.
SCALES = (
    ("clt.raw_tlx", "tlx", "Raw TLX"),
    ("clt.icl", "icl", "ICL — внутренняя нагрузка"),
    ("clt.ecl", "ecl", "ECL — нагрузка от интерфейса"),
    ("clt.gcl", "gcl", "GCL — полезная нагрузка"),
    ("clt.orient", "orient", "Ориентация на полке"),
)

# Шесть шкал NASA-TLX по отдельности — ответ пункта как есть, 0–100.
TLX_ITEMS = (
    ("clt.tlx.mental", "tlx.mental", "TLX: умственная работа"),
    ("clt.tlx.physical", "tlx.physical", "TLX: физические усилия"),
    ("clt.tlx.temporal", "tlx.temporal", "TLX: спешка"),
    ("clt.tlx.performance", "tlx.performance",
     "TLX: успешность (больше — хуже)"),
    ("clt.tlx.effort", "tlx.effort", "TLX: старание"),
    ("clt.tlx.frustration", "tlx.frustration", "TLX: раздражение"),
)

# Состояние теста.
DONE = "пройден"
NOT_DONE = "не пройден"
CLOSED = "закрыт организатором"
NO_TEST = "нет в сборке"


def group_of(item: str) -> str:
    """Группа пункта — идентификатор до последней точки
    (`cltGroupOf` приложения)."""
    return item.rsplit(".", 1)[0] if "." in item else item


def _num(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value


def _dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def scenario_items(scenario: dict | None) -> dict:
    """Пункты сценария: идентификатор → текст, раздел, края шкалы,
    обратный ли, роль, правило отметки."""
    items: dict = {}
    for part in _dict(scenario).get("parts") or []:
        for section in _dict(part).get("sections") or []:
            section = _dict(section)
            scale = _dict(section.get("scale"))
            for item in section.get("items") or []:
                item = _dict(item)
                key = item.get("id")
                if not isinstance(key, str):
                    continue
                items[key] = {
                    "text": item.get("text"),
                    "section": section.get("id"),
                    "section_title": section.get("title"),
                    "min": scale.get("min"), "max": scale.get("max"),
                    "reverse": item.get("reverse") is True,
                    "role": item.get("role"),
                    "flag": item.get("flag"),
                }
    return items


def final_answers(files: dict, scores: dict | None) -> dict | None:
    """Файл ответов итоговой части: тот, что назвало приложение в
    `scores.json` (`final.file`); без него — завершённый файл без
    блока (у записей прежних сборок блоки читаются, но шкалы — только
    итоговой части)."""
    named = _dict(_dict(scores).get("final")).get("file")
    if isinstance(named, str) and isinstance(files.get(named), dict):
        return files[named]
    best = None
    for name in sorted(files):
        data = files[name]
        if not isinstance(data, dict) or "answers" not in data:
            continue
        if data.get("block") is not None:
            continue
        if best is None or (data.get("complete") is True
                            and best.get("complete") is not True):
            best = data
    return best


def scales(answers: dict, items: dict) -> dict:
    """Шкалы по правилу «Подсчёт»: группа → (среднее, n, of).

    of — сколько пунктов группы участнику показали (`order` файла
    ответов, без маркеров); меньше половины ответов — шкала пустая
    (`mean` None)."""
    order = [i for i in answers.get("order") or [] if isinstance(i, str)]
    if not order:
        # Без показанного порядка — пункты сценария: правило половины
        # всё равно знает, сколько пунктов в группе.
        order = list(items)
    checks = {i for i in answers.get("checks") or [] if isinstance(i, str)}
    shown: dict[str, int] = {}
    for item in order:
        if item in checks or items.get(item, {}).get("role") == "check":
            continue
        shown[group_of(item)] = shown.get(group_of(item), 0) + 1
    scored: dict[str, list[float]] = {}
    for answer in answers.get("answers") or []:
        answer = _dict(answer)
        item = answer.get("item")
        value = _num(answer.get("value"))
        if not isinstance(item, str) or value is None:
            continue
        if answer.get("role") == "check" or item in checks:
            continue
        lo = _num(answer.get("min"))
        hi = _num(answer.get("max"))
        reverse = answer.get("reverse") is True or \
            items.get(item, {}).get("reverse") is True
        if reverse and lo is not None and hi is not None:
            # Обратный пункт: min + max − ответ.
            value = lo + hi - value
        scored.setdefault(group_of(item), []).append(float(value))
    out = {}
    for group in sorted(set(shown) | set(scored)):
        values = scored.get(group, [])
        of = shown.get(group, len(values))
        enough = values and 2 * len(values) >= of
        out[group] = {"mean": sum(values) / len(values) if enough else None,
                      "n": len(values), "of": of}
    return out


def read(files: dict, manifest: dict, events: list[dict],
         tolerance: float) -> dict:
    """Расшифровка теста одной записи.

    [files] — разобранные JSON-файлы `clt/` архива (имя → данные).
    Отвечает: состояние теста, сценарий и его версия, шкалы (`measures`:
    ключ меры → число), ответы строками (`answers`), отметки шкалы лжи
    (`lie`), столбцы «небрежности» (`careless`), оговорки (`notes`)."""
    notes: list[str] = []
    clt = manifest.get("clt")
    without = any(e.get("type") == "session.finish"
                  and _dict(e.get("data")).get("without_test") is True
                  for e in events)
    if not isinstance(clt, dict):
        state = NO_TEST
    elif clt.get("final") == "complete":
        state = DONE
    else:
        state = CLOSED if without else NOT_DONE
    scenario = files.get("clt/scenario.json")
    scores = files.get("clt/scores.json")
    if not isinstance(scenario, dict):
        scenario = None
    if not isinstance(scores, dict):
        scores = None
    items = scenario_items(scenario)
    answers = final_answers(files, scores)
    result = {
        "state": state,
        "scenario": (scenario or {}).get("id") or (scores or {}).get(
            "scenario"),
        "scenario_version": (scenario or {}).get("version") or (
            scores or {}).get("version"),
        "measures": {}, "answers": [], "lie": {}, "careless": {},
        "notes": notes, "rt_median_ms": None,
    }
    if state in (CLOSED, NOT_DONE):
        notes.append("тест нагрузки не пройден" + (
            " — закрыт выходом организатора «Тест пройти нельзя»"
            if state == CLOSED else ""))
    if answers is None:
        for item in honesty.LIE_ITEMS:
            result["lie"][item] = {"value": None, "flag": None}
        return result

    # Ответы строками — для `ответы_теста.csv`.
    by_item: dict[str, dict] = {}
    rts = []
    for answer in answers.get("answers") or []:
        answer = _dict(answer)
        item = answer.get("item")
        if not isinstance(item, str):
            continue
        by_item[item] = answer
        meta = items.get(item, {})
        rt = _num(answer.get("rt_ms"))
        if rt is not None:
            rts.append(rt)
        result["answers"].append({
            "item": item, "text": meta.get("text"),
            "section": meta.get("section_title") or meta.get("section"),
            "value": _num(answer.get("value")),
            "reverse": answer.get("reverse") is True or meta.get("reverse"),
            "role": answer.get("role") or meta.get("role"),
            "rt_ms": rt, "order": _num(answer.get("order")),
        })
    result["rt_median_ms"] = statistics.median(rts) if rts else None

    # Шкалы: свои — для сверки; в сравнение — числа приложения. Часть
    # не завершена (не пройдена, закрыта организатором) — шкалы пустые
    # (SNO-ALG-RES-02, краевые случаи).
    own = scales(answers, items)
    if state != DONE:
        own = {g: dict(v, mean=None) for g, v in own.items()}
    app = _dict(_dict(_dict(scores).get("final")).get("scores"))
    for key, group, _ in SCALES:
        mine = own.get(group, {})
        theirs = _num(_dict(app.get(group)).get("mean"))
        value = theirs if theirs is not None else mine.get("mean")
        if mine.get("mean") is None:
            # Меньше половины ответов — шкала пустая, даже если
            # приложение дало число.
            if theirs is not None and mine.get("n") and state == DONE:
                notes.append(f"шкала {group}: ответов {mine['n']} из "
                             f"{mine['of']} — меньше половины, шкала пустая")
            value = None
        elif theirs is not None and abs(theirs - mine["mean"]) > tolerance:
            notes.append(f"шкала {group}: приложение {theirs}, пересчёт "
                         f"{mine['mean']:.3f} — в сравнение идёт число "
                         "приложения")
        result["measures"][key] = value
    for key, item, _ in TLX_ITEMS:
        answer = by_item.get(item)
        result["measures"][key] = None if answer is None or state != DONE \
            else _num(answer.get("value"))

    # Шкала лжи: отметка приложения главнее пересчёта.
    checks = _dict(_dict(scores).get("checks"))
    marks = _dict(checks.get("items"))
    for item in honesty.LIE_ITEMS:
        value = _num(_dict(by_item.get(item)).get("value"))
        mine = honesty.flagged(value, items.get(item, {}).get("flag"))
        theirs = _dict(marks.get(item)).get("flag")
        theirs = theirs if isinstance(theirs, bool) else None
        flag = theirs if theirs is not None else mine
        if value is None:
            flag = None
        elif theirs is not None and mine is not None and theirs != mine:
            notes.append(f"{item}: отметка приложения ({theirs}) и пересчёт "
                         f"({mine}) разошлись — взята отметка приложения")
        result["lie"][item] = {"value": value, "flag": flag}

    # «Небрежность» — справочно, в вес не идёт (АК5).
    for item in ("chk.focus", "chk.books"):
        mark = _dict(marks.get(item))
        result["careless"][item] = {
            "value": _num(mark.get("value")) if mark else
            _num(_dict(by_item.get(item)).get("value")),
            "flag": mark.get("flag"),
            "contradicts": mark.get("contradicts_record"),
        }
    result["careless"]["fast_answers"] = _num(checks.get("fast_answers"))
    result["careless"]["longest_same"] = _num(checks.get("longest_same"))
    result["careless"]["verdict"] = checks.get("verdict")
    return result


def load_files(archive, names) -> dict:
    """Файлы `clt/*.json` архива: имя → разобранный JSON (или None)."""
    out = {}
    for name in names:
        if not (name.startswith("clt/") and name.endswith(".json")):
            continue
        try:
            out[name] = json.loads(archive.read(name).decode("utf-8"))
        except Exception:  # noqa: BLE001 — порченый файл теста не роняет
            out[name] = None
    return out
