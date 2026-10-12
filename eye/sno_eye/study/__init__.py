"""«Сравнение ветвей» — сводный анализ всех записей СНО2026
(SNO-F-RES-06; шаг 36 — отбор, тест нагрузки, действия; шаг 37 —
беспорядочность взгляда, средний взгляд ветвей, научение; шаг 38 —
портрет каждого участника, SNO-F-RES-07; шаг 41 — свод средних,
структурированная матрица, итог «в чём ветвь II сильнее и в чём
слабее», SNO-ALG-RES-10).

С шага 43 (решения владельца АО15, АО16 от 12.10.2026) главный анализ —
режим `--interface` («Анализ по интерфейсу», SNO-F-RES-09): группа —
интерфейс, которым участник выбирал книги, полка — против случая и
самой себя, первый контакт с «Галактикой» — против ожиданий, записанных
до данных; ярлык `eye\\Анализ по интерфейсу.cmd`, отчёт — в «Документы\\
Анализ по интерфейсу СНО2026». Сравнение ветвей остаётся режимом по
умолчанию.

Организатор перетаскивает папку с архивами — с обоих ПК и с телефонов,
можно по подпапкам — на `eye\\Сравнение ветвей.cmd`. Ставить ничего не
нужно, сеть не нужна. В «Документах» появляется
`Сравнение ветвей СНО2026\\<дата-время>\\`:

* `index.html` — вверху «Файлы отчёта» со ссылками на все таблицы и
  рисунки (BUG-68); кто вошёл в статистику и с каким весом, какой
  взгляд дал каждый ПК, нагрузка по ветвям, как искали книги, в какой
  ветви взгляд беспорядочнее и как энтропия менялась по ходу сессии,
  средний взгляд ветви, научение, портреты участников, сводка «I
  против II» со средними в единицах меры и матрицей, держится ли вывод
  при другом отборе, «Как читать», итог «в чём ветвь II сильнее и в чём
  слабее» (шаг 41);
* `Портреты\\<код>.html` — портрет каждого участника (лента сессии,
  переходы, возвраты, взгляд назад при чтении, внимание в момент
  долгого взгляда без действий — П5, шаг 40) и `Портреты\\<код>\\` —
  его рисунки и таблицы;
* `моменты.csv` — моменты долгого взгляда без действий: взятые и
  отвергнутые, с причиной;
* `матрица.csv` — структурированная матрица: все меры одной таблицей,
  под ней сумма О'Брайена (шаг 41);
* `участники.csv`, `походы.csv`, `ответы_теста.csv`, `сравнение.csv`,
  `устойчивость.csv` — для Excel;
* `рисунки\\*.png`, `*.svg` — для статьи;
* `исходные.json` — что разобрано и чем: по нему прогон повторяется до
  бита.

Карта скрипта — порядок шагов, откуда что берётся, какая технология что
преобразует (полностью — «Сводный анализ — структура скрипта» в
описательной структуре):

| Файл         | Шаг | Что делает                         | Технология         |
|--------------|-----|------------------------------------|--------------------|
| `collect.py` | 1   | обход папок, годность («Проверка   | pathlib, zipfile,  |
|              |     | записи»), паспорт, эталон, повторы | json, hashlib      |
| `screen_fix  | 1   | ширина экрана, названная файлом    | re, math           |
| .py`         |     | организатора (АМ2): углы записи в  |                    |
|              |     | верной шкале                       |                    |
| `clt.py`     | 2   | ответы теста, шкалы, сверка с      | json, statistics   |
|              |     | приложением                        |                    |
| `honesty.py` | 3   | цвет искренности и вес             | —                  |
| `gaze.py`    | 4   | разбор взгляда — `report.analyse`; | —                  |
|              |     | схема полки, тепловая карта        |                    |
| `actions.py` | 5   | походы за книгой, меры действий    | statistics         |
| `disorder.py`| 6   | беспорядочность: фиксации общим    | numpy              |
|              |     | порогом, энтропии, K, путь, NNI    |                    |
| `noise.py`   | 6   | медиана трёх кадров, доля времени  | —                  |
|              |     | в фиксациях, шум от кадра к кадру  |                    |
|              |     | (BUG-70)                           |                    |
| `average.py` | 7   | средний взгляд ветви, матрицы,     | numpy              |
|              |     | тепловая карта, научение; кривые   |                    |
|              |     | энтропии по ходу (Р16), ленты      |                    |
| `portrait.py`| 7а  | портрет: окна энтропии по ходу,    | numpy              |
|              |     | наклоны, числа участника           |                    |
| `dwell.py`   | 7а  | заходы, возвраты, переходы между   | —                  |
|              |     | зонами, ожидание без памяти, лента |                    |
| `reading_    | 7а  | взгляд назад при чтении, возвраты  | —                  |
| back.py`     |     | на страницу назад по журналу       |                    |
| `moments.py` | 7б  | момент долгого взгляда без         | bisect             |
|              |     | действий: разрезы, «смотрел»,      |                    |
|              |     | два момента, два числа (шаг 40)    |                    |
| `means.py`   | 9а  | средние ветвей в единицах меры,    | numpy              |
|              |     | разница или отношение, g Хеджеса,  |                    |
|              |     | походы иерархическим бутстрепом,   |                    |
|              |     | сумма О'Брайена, итог «сильнее /   |                    |
|              |     | слабее» (шаг 41)                   |                    |
| `table.py`   | 8   | таблицы CSV, `матрица.csv`         | csv                |
| `stats.py`,  | 9   | δ Клиффа по слоям, бутстреп,       | numpy              |
| `compare.py` |     | перестановки, Холм, сценарии;      |                    |
|              |     | кластеры по ходу сессии            |                    |
| `charts.py`  | 10  | рисунки Р1–Р19                     | matplotlib (Agg)   |
|              |     | (Р1–Р14 по образцу журналов — ПК   |                    |
|              |     | формой точки, подписи n, шаг 42)   |                    |
| `portrait_   | 10а | страница портрета, рисунки П1–П5,  | matplotlib, html,  |
| page.py`     |     | таблицы участника                  | base64, csv        |
| `screen_     | 10б | снимок экрана момента: зоны кадра, | pypdfium2, numpy,  |
| shot.py`     |     | страница из архива литературы,     | matplotlib         |
|              |     | пятно и путь фиксаций (П5)         |                    |
| `page.py`    | 11  | отчёт `index.html`                 | html, base64       |
| `order.py`   | 7в  | порядок обхода: ρ с полкой и с     | numpy              |
|              |     | высотой звезды, маршрут против     |                    |
|              |     | случайных перестановок (шаг 43)    |                    |
| `blinks.py`  | 1   | моргания по потоку взгляда, по     | —                  |
|              |     | третям изучения (шаг 43)           |                    |
| `single.py`  | 9   | анализ по интерфейсу: группы,      | numpy (`stats`)    |
|              |     | проверки против случая и себя,     |                    |
|              |     | знаковая перестановка, итог тремя  |                    |
|              |     | списками (шаг 43)                  |                    |
| `prereg.py`  | 9   | «Галактика»: М1–М10, опора на      | —                  |
|              |     | ориентиры, вердикт предрегистрации |                    |
| `interface_  | 10–11 | рисунки Р20–Р22, отчёт и таблицы | matplotlib, html   |
| charts.py`, `interface_page.py` | | анализа по интерфейсу |          |

Скрипт не пересчитывает того, что уже считается: годность архива —
«Проверка записи» (`record_check`), чтение архива, ход сессии, версии
взгляда, фиксации, зоны и доли — «Разбор записи» (`report.archive`,
`report.timeline`, `report.analyse`) без изменений. Своё в нём —
цвет искренности, меры беспорядочности (фиксации заново, одним
порогом на всё исследование), средний взгляд ветви и сравнение.

Единица анализа — участник: одна строка и один вес. Походы сначала
сводятся к участнику медианой, долей или в минуту, и только потом
участники сравниваются.

Встроенный Python спутника: numpy и matplotlib пришли в папку `eye/`
зависимостями MediaPipe (`eye/requirements.lock`) — ставить ничего не
нужно. pandas и scipy нет и не нужно. pypdfium2 — страница книги на
снимке П5 — внесён в замок намеренно (шаг 40, решение владельца АЛ1
(а)); без него снимок рисуется схемой зон.

Страница книги на снимке берётся из архива литературы: его кладут
рядом с архивами записей (или называют ключом `--literature`); книга
находится по отпечатку файла, как в приложении.
"""

from __future__ import annotations

import json
import os
import platform
import sys
import tempfile
from datetime import datetime
from pathlib import Path

from .. import record_check as rc
from ..report import settings as report_settings

# Версия скрипта сравнения — в `исходные.json`: по ней видно, каким
# кодом считали. Шаг 36 — часть 1, шаг 37 — меры взгляда, шаг 38 —
# портрет участника, шаг 39 — сглаживание и пропуск по доле в фиксациях
# (BUG-70), поправка ширины экрана; шаг 40 — момент долгого взгляда без
# действий (П5); шаг 41 — свод средних, матрица, итог (SNO-ALG-RES-10),
# BUG-71, BUG-72; 41.1 — при малом n_eff только средние; 42.0 — рисунки
# Р1–Р14 по образцу журналов; 43.0 — анализ по интерфейсу (режим
# `--interface`), порядок обхода, вердикт предрегистрации, моргания,
# BUG-73, BUG-74, BUG-75.
SCRIPT_VERSION = "43.0"

OUT_FOLDER = "Сравнение ветвей СНО2026"

# Пороги по умолчанию; настоящие — `study` в `thresholds.json`.
DEFAULTS = {
    # АК1: вес 🟡; АК3 (а): ⚪ — как 🟡.
    "yellow_weight": 0.5,
    "unknown_weight": 0.5,
    # АК11: изучение короче — вне статистики.
    "min_study_min": 20,
    # Доля открытий через карту: до первой — «полкой», от второй —
    # «картой», между — «смешанно».
    "via_map": [1 / 3, 2 / 3],
    # Допуск сверки шкал теста с приложением.
    "scale_tolerance": 0.001,
    # АК4: главные меры.
    "primary": ["search.H_t", "clt.ecl", "actions.time_to_choice"],
    # АК10: запись не с эталона — a, b или c.
    "etalon": "a",
    "bootstrap": 10_000,
    "permutations": 10_000,
    "exact_limit": 20_000,
    "n_eff_min": 3,
    "alpha": 0.05,
    # АК12: общий порог фиксаций для мер беспорядочности, градусы.
    "idt_deg": 4.5,
    # BUG-70 (АМ1 (а)): перед фиксациями мер беспорядочности и портрета
    # — медиана стольких кадров; при частоте ниже — без сглаживания.
    "smooth_frames": 3,
    "smooth_min_fps": 25,
    # BUG-70: доля времени изучения на экране в фиксациях ниже —
    # фиксации дробятся шумом, сессия в меры беспорядочности не идёт
    # (лесенка шума, `tests/noise_ladder.py`).
    "min_fix_share": 0.85,
    # Сетка окна для энтропии поиска: столбцов × строк.
    "grid": [4, 3],
    # Пол числа переходов: поиск, чтение, всё изучение.
    "ht_min_transitions": [40, 200, 200],
    # Подвыборок и розыгрышей случайного уровня энтропии.
    "ht_repeats": 200,
    # Просвет между фиксациями дольше — не переход (лица нет, отлучка).
    "transition_gap_ms": 1000,
    # Фиксаций для NNI; розыгрышей случайных точек.
    "min_fix_nni": 20,
    "nni_mc": 200,
    # |ρ| меры с прецизионностью сессии — «чувствует шум».
    "noise_rho": 0.5,
    # Меньше участников в минуте (и в номере похода) — не рисуется.
    "min_minute_participants": 3,
    # Походов для наклона научения; повторных — для отдельной кривой.
    "min_visits_curve": 6,
    "min_repeat_visits": 3,
    # Шаг 38, Р16: порог |δ| корзины для кластера — «средний» по
    # Romano и др., 2006.
    "cluster_delta": 0.33,
    # Шаг 41 (SNO-ALG-RES-10): поправка разведочных семей — `bh` или
    # `holm` (АЛ5 (а)); у меры времени или частоты нулей больше этой
    # доли — без логарифма; связь мер, при которой они делят вес в сумме
    # О'Брайена; повторов иерархического бутстрепа походов.
    "fdr": "bh",
    "log_zero_share": 0.2,
    "merge_rho": 0.7,
    "hier_bootstrap": 2000,
    # Шаг 42: повторов бутстрепа интервала среднего по каждой минуте
    # (Р9) и по каждой группе долей (Р8) — рисунок, не вывод.
    "minute_bootstrap": 2000,
    # АЛ6: направление «лучше» по мерам — `thresholds.json`; меры, которых
    # там нет, — «—».
    "better": {},
}


# Шаг 43: разделы `study` со своими словарями порогов.
NESTED = ("order", "single", "prereg")


def settings(path: Path | None = None) -> dict:
    """Пороги сравнения: `study` из `thresholds.json` поверх значений по
    умолчанию; пороги портрета участника (шаг 38) — `portrait`, ключом
    `portrait`."""
    from . import portrait
    values = dict(DEFAULTS)
    values["portrait"] = portrait.settings(None)
    for key in NESTED:
        values[key] = {}
    if path is None:
        path = Path(__file__).resolve().parent.parent.parent / \
            "thresholds.json"
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        values["portrait"] = portrait.settings(raw.get("portrait"))
        own = raw.get("study") or {}
        for key, default in DEFAULTS.items():
            value = own.get(key)
            if isinstance(default, dict):
                if isinstance(value, dict):
                    values[key] = {str(k): str(v) for k, v in value.items()}
            elif isinstance(default, list):
                if isinstance(value, list) and value:
                    values[key] = value
            elif isinstance(default, str):
                if isinstance(value, str):
                    values[key] = value
            elif isinstance(value, (int, float)) and \
                    not isinstance(value, bool):
                values[key] = value
        # Шаг 43: разделы порядка обхода, проверок одной группы и
        # предрегистрации — свои словари; их пороги читают `order`,
        # `single` и `prereg`.
        for key in NESTED:
            if isinstance(own.get(key), dict):
                values[key] = dict(own[key])
    except (OSError, ValueError, AttributeError):
        pass
    return values


def _documents(name: str = OUT_FOLDER) -> Path:
    home = Path(os.environ.get("USERPROFILE") or Path.home())
    docs = home / "Documents"
    return (docs if docs.is_dir() else home) / name


def out_folder(out: str | None, no_filter: bool,
               mode: str = "compare") -> Path:
    """Куда класть отчёт: [out] как есть или «Документы\\Сравнение
    ветвей СНО2026\\<дата-время>». Не в папку `Записи` приложения: она
    приняла бы такую папку за запись."""
    if out:
        return Path(out)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    if no_filter:
        stamp += "-проверочный"
    if mode == "interface":
        from .interface_page import OUT_FOLDER as INTERFACE_FOLDER
        return _documents(INTERFACE_FOLDER) / stamp
    return _documents() / stamp


def _matplotlib_cache() -> None:
    """Кэш шрифтов matplotlib — во временную папку, если не назван:
    домашняя папка на чужом ПК бывает недоступна для записи."""
    if not os.environ.get("MPLCONFIGDIR"):
        folder = Path(tempfile.gettempdir()) / "sno_eye_matplotlib"
        try:
            folder.mkdir(parents=True, exist_ok=True)
            os.environ["MPLCONFIGDIR"] = str(folder)
        except OSError:
            pass
    os.environ.setdefault("MPLBACKEND", "Agg")


def fingerprint(entries: list[dict]) -> str:
    """Отпечаток набора — SHA-256 отсортированных сумм архивов: от него
    зерно генератора, тот же набор даёт те же числа."""
    import hashlib
    sums = sorted(e.get("sha256") or e["archive"] for e in entries)
    return hashlib.sha256("\n".join(sums).encode()).hexdigest()


def analyse(paths: list[str], *, series: str | None = None,
            no_filter: bool = False, cfg: dict | None = None,
            limits: dict | None = None, progress=None,
            version: str | None = None, mode: str = "compare") -> dict:
    """Весь сводный анализ без записи файлов: записи, отбор, меры
    взгляда, порядок обхода и — по [mode] — сравнение ветвей со
    средними (`compare`) или анализ по интерфейсу (`interface`, шаг 43:
    полка против случая и самой себя, «Галактика» против
    предрегистрации)."""
    from . import (average, collect, compare, disorder, order, portrait,
                   screen_fix, single)
    cfg = cfg or settings()
    limits = limits or rc.thresholds()
    # Версия взгляда для мер — та же, что у «Разбора записи»
    # (`report.version`), или названная ключом `--version`.
    report_cfg = report_settings()
    if version in ("raw", "drift"):
        report_cfg["version"] = version
    archives = collect.find(paths)
    # Шаг 39 (АМ2): ширина экрана, названная организатором файлом
    # `ширина экрана.txt` рядом с архивами.
    widths, width_notes = screen_fix.read(paths)
    entries = []
    for i, path in enumerate(archives, start=1):
        if progress:
            progress(i, len(archives), path)
        entries.append(collect.load(path, limits, cfg, report_cfg, widths))
    pc_notes = collect.name_strata(entries) + width_notes
    for e in entries:
        if e.get("screen_fix"):
            pc_notes.append(f"{e.get('participant') or e['archive']}: "
                            + screen_fix.note(e["screen_fix"]))
    collect.mark_repeats(entries)
    compare.unify_scenarios(entries)
    compare.admit(entries, cfg, no_filter, series)
    entries.sort(key=lambda e: (e.get("branch") or "~",
                                str(e.get("participant") or "~"),
                                e["archive"]))
    print_ = fingerprint(entries)
    # Шаг 6 — меры беспорядочности: `k` и μ, σ — по участникам S0.
    gaze_info = disorder.finish(entries, cfg, fingerprint=print_,
                                no_filter=no_filter, series=series)
    # Шаг 7 — наклоны научения идут в сравнение мерами участника.
    average.learning(entries, cfg)
    # Шаг 7а — числа портрета участника (семья «Д»): энтропия по ходу,
    # заходы и возвраты, взгляд назад, возвраты на страницу.
    portrait.finish(entries, cfg, no_filter=no_filter)
    # Шаг 43 — порядок обхода библиотеки (SNO-ALG-RES-11).
    order.finish(entries, cfg, print_)
    if mode == "interface":
        result = single.run(entries, cfg, fingerprint=print_,
                            no_filter=no_filter, series=series)
        result["gaze_info"] = gaze_info
        result["warnings"] = pc_notes + interface_warnings(entries)
        return {"entries": entries, "result": result, "cfg": cfg,
                "paths": [str(p) for p in paths], "limits": limits,
                "fingerprint": print_, "series": series,
                "no_filter": no_filter, "mode": mode,
                "archives": [str(a) for a in archives],
                "gaze_version": report_cfg["version"]}
    result = compare.run(entries, cfg, fingerprint=print_,
                         no_filter=no_filter, series=series)
    result["gaze_info"] = gaze_info
    result["average"] = average.build(entries, cfg, no_filter, series,
                                      print_)
    result["average"]["entropy"] = average.entropy_curves(
        entries, cfg, no_filter, series, print_)
    result["average"]["ribbons"] = average.ribbons(entries)
    # BUG-69: ПК с разной шириной экрана в местах записи ветвей.
    result["warnings"] = (compare.warnings(entries, result, no_filter)
                          + pc_notes)
    return {"entries": entries, "result": result, "cfg": cfg,
            "paths": [str(p) for p in paths],
            "limits": limits, "fingerprint": print_, "series": series,
            "no_filter": no_filter, "archives": [str(a) for a in archives],
            "gaze_version": report_cfg["version"], "mode": mode}


def interface_warnings(entries: list[dict]) -> list[str]:
    """Оговорки анализа по интерфейсу: книги, открытые не с начала
    (сброса к эталону не было — BUG-74), записи без группы."""
    out = []
    for e in entries:
        if e.get("status") != "ok":
            continue
        who = e.get("participant") or e["archive"]
        nav = e.get("reading_nav") or {}
        if nav.get("opened_mid"):
            out.append(f"{who}: книги открывались не с начала "
                       f"({nav['opened_mid']} раз) — сброса к эталону "
                       "не было; перемотка к началу считается отдельно, "
                       "не возвратом")
        if e.get("interface") is None:
            out.append(f"{who}: книг не открывали — интерфейс выбора не "
                       "определён, запись ни в одной группе")
    return out


def sources(run: dict) -> dict:
    """`исходные.json`: что разобрано и чем."""
    import matplotlib
    import numpy
    from . import stats
    return {
        "schema": "sno2026-study/1",
        "script": SCRIPT_VERSION,
        "step": "шаг 36 — отбор, тест нагрузки, действия; шаг 37 — "
                "беспорядочность, средний взгляд, научение; шаг 38 — "
                "портрет участника; шаг 39 — сглаживание и пропуск по "
                "доле в фиксациях (BUG-70), ширина экрана; шаг 40 — "
                "момент долгого взгляда без действий (П5); шаг 41 — "
                "свод средних, матрица, итог «сильнее / слабее»; шаг 42 — "
                "рисунки по образцу журналов; шаг 43 — анализ по "
                "интерфейсу: порядок обхода, проверки одной группы, "
                "вердикт предрегистрации «Галактики», моргания, BUG-73, "
                "BUG-74, BUG-75",
        "mode": run.get("mode", "compare"),
        "series": run["series"], "no_filter": run["no_filter"],
        "gaze_version": run["gaze_version"],
        "fingerprint": run["fingerprint"],
        "seed_rule": "зерно меры — первые 8 байт SHA-256 от «отпечаток, "
                     "сравнение, сценарий, мера» (stats.seed_for)",
        "seed_example": stats.seed_for(run["fingerprint"], "ветвь", "S0",
                                       "clt.ecl"),
        "archives": [{"archive": e["archive"], "path": e["path"],
                      "sha256": e.get("sha256"), "status": e["status"],
                      "reason": e.get("reason"),
                      # Шаг 39 (АМ2): ширина экрана, исправленная файлом
                      # организатора, — по ней прогон повторяется.
                      "screen_fix": e.get("screen_fix")}
                     for e in run["entries"]],
        "thresholds": {"study": run["cfg"], "record_check": run["limits"],
                       "report": report_settings()},
        # Меры беспорядочности (SNO-ALG-RES-03): число переходов
        # подвыборки `k` и случайный уровень энтропии по фазам, μ и σ
        # коэффициента K — одни во всех сценариях; по ним прогон
        # повторяется.
        "gaze": _gaze_sources(run["result"].get("gaze_info") or {}),
        # Портрет (SNO-ALG-RES-06): случайный уровень энтропии на размер
        # окна — одно число на всех; кластеры Р16 — как посчитаны.
        "portrait": _portrait_sources(run),
        "versions": {"python": platform.python_version(),
                     "numpy": numpy.__version__,
                     "matplotlib": matplotlib.__version__,
                     "platform": platform.platform()},
    }


def _gaze_sources(info: dict) -> dict:
    out = {"from": info.get("from"), "idt_deg": info.get("idt_deg"),
           "grid": info.get("grid"), "phases": {}}
    for phase, own in (info.get("phases") or {}).items():
        row = {k: own.get(k) for k in ("zones", "floor", "k", "k_norep",
                                       "K")}
        for name in ("random", "random_norep"):
            if own.get(name) is not None:
                row[name] = {"H_t": own[name][0], "H_s": own[name][1]}
        out["phases"][phase] = row
    return out


def _portrait_sources(run: dict) -> dict:
    from . import portrait
    levels = {}
    for e in run["entries"]:
        ent = ((e.get("gaze_data") or {}).get("portrait") or {}).get(
            "entropy") or {}
        for name, own in ent.items():
            levels[f"{own['size']}"] = own["level"]
    curves = {}
    avg = run["result"].get("average") or {}
    for name, own in (avg.get("entropy") or {}).items():
        test = own.get("test") or {}
        curves[name] = {
            "bin_min": own.get("width"), "bins": test.get("bins"),
            "pooled": test.get("pooled"), "exact": test.get("exact"),
            "permutations": test.get("permutations"),
            "clusters": [{"bins": c["bins"], "mass": c["mass"],
                          "p": c.get("p")} for c in
                         test.get("clusters") or []]}
    return {"zones": len(portrait.disorder.search_zones(
        tuple(run["cfg"]["grid"]))), "random_level_by_window": levels,
        "curves": curves}


# Файлы отчёта и что в каждом — для «Файлов отчёта» вверху `index.html`
# и для консоли (BUG-68).
FILES = (
    ("участники.csv", "строка на участника: ветвь, ПК, цвет, вес, эталон, "
     "шкалы теста, меры действий и взгляда"),
    ("походы.csv", "строка на поход за книгой: время до выбора, путь "
     "взгляда, прямота, возвраты"),
    ("ответы_теста.csv", "строка на ответ теста нагрузки"),
    ("сравнение.csv", "строка на меру: средние ветвей, δ, интервал, p, p "
     "с поправкой, вывод, II лучше / хуже"),
    ("матрица.csv", "структурированная матрица: строка на меру — "
     "направление «лучше», средние ветвей с интервалами, разница или "
     "отношение, g, δ, p, устойчивость, вывод; под ней — сумма "
     "О'Брайена"),
    ("устойчивость.csv", "главные меры в шести сценариях отбора"),
    ("моменты.csv", "строка на момент долгого взгляда без действий: "
     "взятые и отвергнутые, с причиной (П5)"),
    ("исходные.json", "что разобрано и чем: архивы с SHA-256, пороги, "
     "версии, зёрна"),
)


def write(run: dict, folder: Path, portraits: bool = True,
          literature: list[str] | None = None) -> list[Path]:
    """Кладёт отчёт, таблицы, рисунки, портреты участников и исходные в
    [folder]; [portraits] False — без страниц портретов (ключ
    `--no-portraits`). Книги для снимков П5 ищутся в [literature] и среди
    папок прогона (шаг 40)."""
    if run.get("mode") == "interface":
        from . import interface_page
        return interface_page.write(run, folder, portraits, literature)
    from . import charts, page, portrait_page, screen_shot, table
    folder.mkdir(parents=True, exist_ok=True)
    entries, result = run["entries"], run["result"]
    run["_library"] = screen_shot.Library(
        list(literature or []) + list(run.get("paths") or []))
    table.moments(entries, folder / "моменты.csv")
    table.participants(entries, folder / "участники.csv")
    table.trips(entries, folder / "походы.csv")
    table.answers(entries, folder / "ответы_теста.csv")
    table.comparison(result, folder / "сравнение.csv")
    table.matrix(result, folder / "матрица.csv")
    table.robustness(result, folder / "устойчивость.csv")
    figures = charts.draw_all(run, folder / "рисунки")
    run["_portraits"] = portrait_page.write_all(run, folder) if portraits \
        else None
    run["_figures_folder"] = str(folder / "рисунки")
    run["_folder"] = str(folder)
    (folder / "исходные.json").write_text(
        json.dumps(sources(run), ensure_ascii=False, indent=1),
        encoding="utf-8")
    (folder / "index.html").write_text(page.render(run, figures),
                                       encoding="utf-8")
    return [folder / "index.html"]


def interface_summary(run: dict) -> dict:
    """Итог анализа по интерфейсу для `--json` и консоли (шаг 43)."""
    res = run["result"]
    entries = run["entries"]
    return {
        "mode": "interface",
        "archives": len(entries),
        "bad": [e["archive"] for e in entries if e["status"] != "ok"],
        "groups": res["groups"],
        "participants": [{
            "participant": e.get("participant"), "branch": e.get("branch"),
            "interface": e.get("interface"), "colour": e.get("colour"),
            "in_stats": e.get("in_stats"), "out": e.get("out"),
            "strategy": (e.get("order") or {}).get("strategy"),
            "route_shelf": (e.get("order") or {}).get("route_shelf"),
            "route_map": (e.get("order") or {}).get("route_map"),
            "blinks_change": (e.get("blinks_measures") or {}).get(
                "blinks.change"),
            "lookback_reason": ((e.get("gaze_data") or {}).get(
                "portrait") or {}).get("lookback", {}).get("reason"),
        } for e in entries],
        "checks": [{"question": r["check"].question,
                    "measure": r["check"].key, "n": r["n"],
                    "toward": r.get("toward"), "median": r.get("median"),
                    "ci": r.get("ci"), "p": r.get("p"),
                    "p_adj": r.get("p_adj"), "words": r["words"]}
                   for r in res["table"]],
        "verdict": res["prereg"]["verdict"],
        "established": [x["words"] for x in res["summary"]["established"]],
        "warnings": res["warnings"],
        "fingerprint": run["fingerprint"],
    }


def summary(run: dict) -> dict:
    """Итог для `--json` и консоли."""
    if run.get("mode") == "interface":
        return interface_summary(run)
    entries = run["entries"]
    rows = []
    for r in run["result"]["table"]:
        if r["comparison"] != "ветвь" or r["family"] != "0":
            continue
        res = r["result"]
        rows.append({"measure": r["measure"].key, "delta": res.delta,
                     "ci": res.ci, "p": res.p, "p_adj": r["p_adj"],
                     "words": r["words"]})
    return {
        "archives": len(entries),
        "bad": [e["archive"] for e in entries if e["status"] != "ok"],
        "in_stats": [e.get("participant") for e in entries
                     if e.get("in_stats")],
        "participants": [{
            "participant": e.get("participant"), "branch": e.get("branch"),
            "stratum": e.get("stratum"), "colour": e.get("colour"),
            "weight": e.get("weight"), "in_stats": e.get("in_stats"),
            "out": e.get("out"), "etalon": e.get("etalon"),
            "gaze_included": (e.get("gaze") or {}).get("included"),
            "disorder_gate": e.get("disorder_gate"),
            "fix_share": ((e.get("gaze_data") or {}).get("disorder")
                          or {}).get("fix_share"),
            "screen_fix": e.get("screen_fix"),
            "search_mode": e.get("search_mode"),
        } for e in entries],
        "primary": rows,
        # Итог АН2 (шаг 41): ключи мер, где ветвь II сильнее и слабее.
        "stronger": [r["measure"].key for r in run["result"]["table"]
                     if r.get("verdict") == "сильнее"],
        "weaker": [r["measure"].key for r in run["result"]["table"]
                   if r.get("verdict") == "слабее"],
        "warnings": run["result"]["warnings"],
        "fingerprint": run["fingerprint"],
    }


def describe(run: dict, folder: Path | None) -> list[str]:
    """Итог строками для консоли."""
    from . import honesty
    if run.get("mode") == "interface":
        return describe_interface(run, folder)
    lines = []
    for w in run["result"]["warnings"]:
        lines.append(f"! {w}")
    for e in run["entries"]:
        if e["status"] != "ok":
            lines.append(f"{e['archive']} — не годен: {e.get('reason')}")
            continue
        mark = honesty.SHORT.get(e.get("colour"), "·")
        where = "в статистике" if e.get("in_stats") else \
            "вне статистики: " + "; ".join(e.get("out") or [])
        lines.append(f"{mark} {e.get('participant')} · ветвь "
                     f"{e.get('branch')} · {e.get('stratum')} · {where}")
    s = summary(run)
    for row in s["primary"]:
        lines.append(f"  {row['measure']}: {row['words']}")
    # Итог АН2 строкой (шаг 41).
    lines.append("  ветвь II сильнее: " + (", ".join(s["stronger"])
                                         or "не доказано ни по одной мере"))
    lines.append("  ветвь II слабее: " + (", ".join(s["weaker"])
                                        or "не доказано ни по одной мере"))
    if folder is not None:
        # BUG-68: папка отчёта и что в ней, а не только `index.html`.
        lines.append("")
        lines.append(f"Папка отчёта: {folder}")
        lines.append("  index.html — отчёт, открыть в браузере")
        for name, words in FILES:
            lines.append(f"  {name} — {words}")
        lines.append("  рисунки\\ — рисунки отчёта, PNG и SVG")
        if run.get("_portraits") is not None:
            lines.append(f"  Портреты\\ — портрет каждого участника "
                         f"({len(run['_portraits'])} шт.)")
    return lines


def describe_interface(run: dict, folder: Path | None) -> list[str]:
    """Итог анализа по интерфейсу строками для консоли (шаг 43)."""
    from . import honesty
    from .interface_page import FILES as INTERFACE_FILES
    lines = [f"! {w}" for w in run["result"]["warnings"]]
    for e in run["entries"]:
        if e["status"] != "ok":
            lines.append(f"{e['archive']} — не годен: {e.get('reason')}")
            continue
        mark = honesty.SHORT.get(e.get("colour"), "·")
        where = "в статистике" if e.get("in_stats") else \
            "вне статистики: " + "; ".join(e.get("out") or [])
        lines.append(f"{mark} {e.get('participant')} · "
                     f"{e.get('interface') or 'без группы'} · "
                     f"{(e.get('order') or {}).get('strategy')} · {where}")
    for r in run["result"]["table"]:
        if r["check"].main:
            lines.append(f"  {r['check'].question} {r['check'].key}: "
                         f"{r['words']}")
    v = run["result"]["prereg"]["verdict"]
    lines.append(f"  «Галактика», первый контакт: {v['word']} "
                 f"(в вердикте {v['n']})")
    if folder is not None:
        lines.append("")
        lines.append(f"Папка отчёта: {folder}")
        lines.append("  index.html — отчёт, открыть в браузере")
        for name, words in INTERFACE_FILES:
            lines.append(f"  {name} — {words}")
        lines.append("  рисунки\\ — рисунки отчёта, PNG и SVG")
    return lines


def open_folder(folder: Path) -> bool:
    """Открывает папку отчёта в Проводнике (BUG-68, ярлыки `--open`).
    Не Windows или не вышло — молча: путь уже напечатан."""
    starter = getattr(os, "startfile", None)
    if starter is None:
        return False
    try:
        starter(str(folder))
        return True
    except OSError:
        return False


def main(paths: list[str], *, series: str | None = None,
         no_filter: bool = False, out: str | None = None,
         as_json: bool = False, version: str | None = None,
         open_folder: bool = False, portraits: bool = True,
         literature: list[str] | None = None,
         mode: str = "compare") -> int:
    """Вход `python -I -m sno_eye study`. Код выхода: 0 — отчёт готов,
    3 — сравнивать нечего, 4 — отчёт не записался."""
    _matplotlib_cache()
    if not paths:
        paths = rc.default_folders()
        if paths and not as_json:
            print("Архивы не названы — сравниваю записи на этом ПК:")
            for folder in paths:
                print(f"  {folder}")
    from . import collect
    if not collect.find(paths):
        word = "Анализ по интерфейсу" if mode == "interface" else \
            "Сравнение ветвей"
        print(f"Архивов записи не нашлось. Перетащите на «{word}» "
              "папку с архивами sno2026_….zip (можно с подпапками).")
        return 3

    def progress(i, n, path):
        if not as_json:
            print(f"[{i}/{n}] {path.name}", flush=True)

    run = analyse(paths, series=series, no_filter=no_filter,
                  progress=progress, version=version, mode=mode)
    folder = out_folder(out, no_filter, mode)
    try:
        write(run, folder, portraits=portraits, literature=literature)
    except OSError as e:
        print(f"Отчёт записать не удалось: {e}")
        return 4
    if as_json:
        print(json.dumps(summary(run), ensure_ascii=False, indent=1,
                         default=str))
    else:
        print()
        for line in describe(run, folder):
            print(line)
    sys.stdout.flush()
    if open_folder and not as_json:
        _open(folder)
    return 0


# Имя внутри модуля: параметр `open_folder` у `main` его заслоняет.
_open = open_folder
