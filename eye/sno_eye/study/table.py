"""Шаг 8 — таблицы: участник — строка, поход — строка, ответ — строка
(SNO-F-RES-06, «Что выходит»); сравнение и устойчивость — тоже здесь.

Откуда данные: записи `study.collect` после отбора (`study.compare.admit`)
и итог сравнения (`study.compare.run`).
Технология: `csv` стандартной библиотеки.
Метод: формат — как у «Разбора записи» (`report._write`): разделитель
«;», UTF-8 с меткой порядка байт — так таблицы открывает Excel с
русскими настройками; дробная часть — через запятую.
Вход → выход: записи и итог → `участники.csv`, `походы.csv`,
`ответы_теста.csv`, `сравнение.csv`, `устойчивость.csv`.

Числа пишутся шестью значащими цифрами: тот же набор на тех же версиях
даёт те же строки до знака (проверяет `test_study_scenario.py`).
"""

from __future__ import annotations

import csv
from pathlib import Path

from . import clt, compare, honesty


def cell(value) -> str:
    """Ячейка: пусто — пусто, да/нет словами, число — шесть значащих
    цифр с запятой."""
    if value is None:
        return ""
    if isinstance(value, bool):
        return "да" if value else "нет"
    if isinstance(value, float):
        if value != value:  # NaN — не число, ячейка пустая
            return ""
        text = f"{value:.6g}"
        if "e" in text:
            text = f"{value:.6f}".rstrip("0").rstrip(".")
        return text.replace(".", ",")
    if isinstance(value, (list, tuple)):
        return " | ".join(str(v) for v in value)
    return str(value)


def write(path: Path, header: list[str], rows: list[list]) -> None:
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, delimiter=";")
        writer.writerow(header)
        for row in rows:
            writer.writerow([cell(v) for v in row])


def _test(e: dict, *path):
    value = e.get("test") or {}
    for key in path:
        value = value.get(key) if isinstance(value, dict) else None
    return value


ACTION_COLUMNS = [m for m in compare.MEASURES if m.key.startswith("actions.")]
GAZE_COLUMNS = [m for m in compare.MEASURES if m.family in ("В", "Г")
                or m.key == "search.H_t"]


def _gd(e: dict, *path):
    """Поле `gaze_data` записи по пути ключей."""
    value = e.get("gaze_data") or {}
    for key in path:
        value = value.get(key) if isinstance(value, dict) else None
    return value


def _transitions(e: dict, phase: str):
    return (e.get("gaze_measures") or {}).get(f"{phase}.transitions")

PARTICIPANT_COLUMNS = [
    ("код участника", lambda e: e.get("participant")),
    ("архив", lambda e: e.get("archive")),
    ("ветвь", lambda e: e.get("branch")),
    ("ПК (слой)", lambda e: e.get("stratum")),
    ("платформа", lambda e: e.get("platform")),
    ("устройство", lambda e: e.get("device")),
    ("камера", lambda e: e.get("camera")),
    ("серия", lambda e: e.get("series")),
    ("сборка", lambda e: e.get("version")),
    ("начало записи", lambda e: e.get("clock_anchor")),
    ("изучение, мин", lambda e: None if e.get("study_s") is None
     else e["study_s"] / 60),
    ("в статистике", lambda e: e.get("in_stats")),
    ("почему вне статистики", lambda e: e.get("out") or
     ([e["reason"]] if e.get("reason") else None)),
    ("цвет", lambda e: honesty.WORDS.get(e.get("colour"))),
    ("вес", lambda e: e.get("weight")),
    ("почему такой цвет", lambda e: e.get("colour_reason")),
    ("lie.defer", lambda e: _test(e, "lie", "lie.defer", "value")),
    ("lie.late", lambda e: _test(e, "lie", "lie.late", "value")),
    ("эталон", lambda e: e.get("etalon")),
    ("эталон — почему", lambda e: e.get("etalon_reasons")),
    ("взгляд записан", lambda e: (e.get("gaze") or {}).get("present")),
    ("точность в начале, °", lambda e: (e.get("gaze") or {})
     .get("start_deg")),
    ("точность в конце, °", lambda e: (e.get("gaze") or {}).get("end_deg")),
    ("средняя точность, °", lambda e: (e.get("gaze") or {}).get("mean_deg")),
    ("прецизионность, °", lambda e: (e.get("gaze") or {})
     .get("precision_deg")),
    ("взгляд в анализе", lambda e: (e.get("gaze") or {}).get("included")),
    ("почему взгляд не в анализе", lambda e: (e.get("gaze") or {})
     .get("reason")),
    ("тест нагрузки", lambda e: _test(e, "state")),
    ("сценарий теста", lambda e: e.get("clt_version")),
] + [(title, (lambda k: lambda e: compare.value(e, k))(key))
     for key, _, title in clt.SCALES + clt.TLX_ITEMS] + [
    ("время ответа на пункт, медиана, с",
     lambda e: None if _test(e, "rt_median_ms") is None
     else _test(e, "rt_median_ms") / 1000),
    ("небрежность: chk.focus", lambda e: _test(e, "careless", "chk.focus",
                                              "value")),
    ("небрежность: chk.focus отметка",
     lambda e: _test(e, "careless", "chk.focus", "flag")),
    ("небрежность: chk.focus расходится с записью",
     lambda e: _test(e, "careless", "chk.focus", "contradicts")),
    ("небрежность: chk.books", lambda e: _test(e, "careless", "chk.books",
                                              "value")),
    ("небрежность: chk.books отметка",
     lambda e: _test(e, "careless", "chk.books", "flag")),
    ("небрежность: chk.books расходится с записью",
     lambda e: _test(e, "careless", "chk.books", "contradicts")),
    ("небрежность: ответов быстрее секунды",
     lambda e: _test(e, "careless", "fast_answers")),
    ("небрежность: одинаковых подряд",
     lambda e: _test(e, "careless", "longest_same")),
    ("самопроверка ответов приложения",
     lambda e: _test(e, "careless", "verdict")),
    ("способ поиска", lambda e: e.get("search_mode")),
    ("походов за книгой", lambda e: (e.get("actions_info") or {})
     .get("trips")),
    ("из них доведённых", lambda e: (e.get("actions_info") or {})
     .get("complete_trips")),
    ("касаний", lambda e: (e.get("actions_info") or {}).get("taps")),
    ("пустых касаний", lambda e: (e.get("actions_info") or {})
     .get("empty_taps")),
] + [(f"{m.title}, {m.unit}", (lambda k: lambda e: compare.value(e, k))(
    m.key)) for m in ACTION_COLUMNS] + [
    # Взгляд (шаг 37): версия, пороги фиксаций — сессии и общий, почему
    # нет мер беспорядочности, сколько переходов, клетка сетки.
    ("версия взгляда", lambda e: _gd(e, "version")),
    ("порог фиксаций сессии, °", lambda e: _gd(e, "idt_session_deg")),
    ("общий порог фиксаций, °", lambda e: _gd(e, "disorder", "idt_deg")),
    ("меры беспорядочности — почему нет",
     lambda e: None if e.get("disorder_live") else e.get("disorder_gate")),
    ("переходов в поиске", lambda e: _transitions(e, "search")),
    ("переходов в чтении", lambda e: _transitions(e, "reading")),
    ("переходов за всё изучение", lambda e: _transitions(e, "all")),
    ("клетка сетки, ° (ширина)", lambda e: (_gd(e, "disorder", "cell_deg")
                                            or [None])[0]),
    ("клетка сетки, ° (высота)", lambda e: (_gd(e, "disorder", "cell_deg")
                                            or [None, None])[1]),
    ("клетка меньше двух запасов точности", lambda e: _gd(e, "cell_small")),
    ("походов без взгляда", lambda e: (e.get("gaze_measures") or {})
     .get("search.trips_no_gaze")),
    ("H_t поиска без повторов", lambda e: (e.get("gaze_measures") or {})
     .get("search.H_t_norep")),
    ("NNI (сырой)", lambda e: (e.get("gaze_measures") or {})
     .get("search.nni")),
    ("NNI — экран", lambda e: (e.get("gaze_measures") or {})
     .get("search.nni_screen")),
    ("карта (отпечаток мест звёзд)", lambda e: (_gd(e, "map") or {})
     .get("key")),
] + [(f"{m.title}, {m.unit}", (lambda k: lambda e: compare.value(e, k))(
    m.key)) for m in GAZE_COLUMNS] + [
    ("оговорки", lambda e: (e.get("check_notes") or [])
     + ((e.get("test") or {}).get("notes") or [])
     + (_gd(e, "notes") or [])),
]


def participants(entries: list[dict], path: Path) -> None:
    write(path, [t for t, _ in PARTICIPANT_COLUMNS],
          [[fn(e) for _, fn in PARTICIPANT_COLUMNS] for e in entries])


TRIP_COLUMNS = (
    ("№ похода", "n"), ("от начала изучения, с", "start_s"),
    ("длился, с", "duration_s"), ("доведён до книги", "complete"),
    ("книга", "title"), ("отпечаток книги", "book"),
    ("через что", "via"), ("время до выбора, с", "time_to_choice_s"),
    ("время в карточке, с", "card_s"),
    ("поиск по названию", "shelf_search"), ("на карте, с", "map_s"),
    ("приближений и сдвигов карты", "views"),
    ("первое обращение к книге", "first_time"), ("экраны", "screens"),
)


# Взгляд похода (шаг 37, М4, М5): фиксации общим порогом, путь по
# содержимому до места нажатия, прямота, возвраты.
TRIP_GAZE = (("фиксаций поиска", "fixations"), ("путь взгляда, °",
                                                "path_deg"),
             ("прямота", "straight"), ("возвраты", "returns"))


def trips(entries: list[dict], path: Path) -> None:
    rows = []
    for e in entries:
        gaze = {t["n"]: t for t in _gd(e, "disorder", "trips") or []}
        live = bool(e.get("disorder_live"))
        for t in e.get("trips") or []:
            own = gaze.get(t["n"]) if live else None
            rows.append([e.get("participant"), e.get("branch"),
                         e.get("in_stats")]
                        + [t.get(k) for _, k in TRIP_COLUMNS]
                        + [None if own is None else own.get(k)
                           for _, k in TRIP_GAZE])
    write(path, ["код участника", "ветвь", "участник в статистике"]
          + [t for t, _ in TRIP_COLUMNS] + [t for t, _ in TRIP_GAZE],
          rows)


def answers(entries: list[dict], path: Path) -> None:
    rows = []
    for e in entries:
        for a in _test(e, "answers") or []:
            rows.append([e.get("participant"), e.get("branch"),
                         e.get("in_stats"), a["item"], a.get("text"),
                         a.get("section"), a.get("value"), a.get("reverse"),
                         a.get("role"),
                         None if a.get("rt_ms") is None
                         else a["rt_ms"] / 1000, a.get("order")])
    write(path, ["код участника", "ветвь", "участник в статистике", "пункт",
                 "текст", "раздел", "ответ", "обратный", "роль",
                 "время ответа, с", "место в показанном порядке"], rows)


def _ci(ci, k: int):
    return None if ci is None else ci[k]


def comparison(result: dict, path: Path) -> None:
    rows = []
    for r in result["table"]:
        m = r["measure"]
        res = r["result"]
        a, b = r["groups"]
        da = res.describe.get(a, {})
        db = res.describe.get(b, {})
        rows.append([
            r["comparison"], compare.FAMILIES[r["family"]],
            r["family"] == "0", m.key, m.title, m.unit, m.more,
            a, da.get("n"), da.get("n_eff"), res.n_eff_cmp.get(a),
            da.get("mean"), da.get("median"), da.get("sd"),
            b, db.get("n"), db.get("n_eff"), res.n_eff_cmp.get(b),
            db.get("mean"), db.get("median"), db.get("sd"),
            res.delta, _ci(res.ci, 0), _ci(res.ci, 1), r.get("effect"),
            res.p, res.exact, r.get("p_holm"), res.delta_all,
            res.diff, _ci(res.diff_ci, 0), _ci(res.diff_ci, 1),
            " | ".join(res.strata), res.pooled, r.get("words"),
            r.get("noise_rho"), r.get("noisy") if m.gaze else None,
        ])
    write(path, [
        "сравнение", "семья", "главная", "мера", "название", "единицы",
        "больше — значит",
        "группа A", "A: n", "A: n_eff", "A: n_eff в сравнимых слоях",
        "A: среднее", "A: медиана", "A: отклонение",
        "группа B", "B: n", "B: n_eff", "B: n_eff в сравнимых слоях",
        "B: среднее", "B: медиана", "B: отклонение",
        "δ (A против B)", "δ: 2,5 %", "δ: 97,5 %", "величина",
        "p", "p точный", "p по Холму", "δ без слоёв (справочно)",
        "разница средних A − B", "разница: 2,5 %", "разница: 97,5 %",
        "сравнимые слои", "без слоёв (ветвь совпадает с ПК)", "вывод",
        "ρ с прецизионностью сессии", "чувствует шум",
    ], rows)


def robustness(result: dict, path: Path) -> None:
    rows = []
    for item in result["robust"]:
        m = item["measure"]
        for case in item["cases"]:
            res = case["result"]
            rows.append([m.key, m.title, case["scenario"], case["title"],
                         res.n_eff_cmp.get("II"), res.n_eff_cmp.get("I"),
                         res.delta, _ci(res.ci, 0), _ci(res.ci, 1), res.p,
                         "да" if res.enough else "мало данных",
                         item["verdict"]])
    write(path, ["мера", "название", "сценарий", "что в нём",
                 "II: n_eff", "I: n_eff", "δ (II против I)", "δ: 2,5 %",
                 "δ: 97,5 %", "p", "данных хватает", "вывод по мере"], rows)
