"""«Сравнение ветвей» — сводный анализ всех записей СНО2026
(SNO-F-RES-06, шаг 36 — часть 1: без мер взгляда).

Организатор перетаскивает папку с архивами — с обоих ПК и с телефонов,
можно по подпапкам — на `eye\\Сравнение ветвей.cmd`. Ставить ничего не
нужно, сеть не нужна. В «Документах» появляется
`Сравнение ветвей СНО2026\\<дата-время>\\`:

* `index.html` — кто вошёл в статистику и с каким весом, какой взгляд
  дал каждый ПК, нагрузка по ветвям, как искали книги, сводка «I против
  II», держится ли вывод при другом отборе, «Как читать»;
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
| `clt.py`     | 2   | ответы теста, шкалы, сверка с      | json, statistics   |
|              |     | приложением                        |                    |
| `honesty.py` | 3   | цвет искренности и вес             | —                  |
| — (шаг 37)   | 4   | разбор взгляда — `report.analyse`  | —                  |
| `actions.py` | 5   | походы за книгой, меры действий    | statistics         |
| — (шаг 37)   | 6–7 | беспорядочность, средний взгляд    | numpy              |
| `table.py`   | 8   | таблицы CSV                        | csv                |
| `stats.py`,  | 9   | δ Клиффа по слоям, бутстреп,       | numpy              |
| `compare.py` |     | перестановки, Холм, сценарии       |                    |
| `charts.py`  | 10  | рисунки Р1–Р5, Р13, Р14            | matplotlib (Agg)   |
| `page.py`    | 11  | отчёт `index.html`                 | html, base64       |

Скрипт не пересчитывает того, что уже считается: годность архива —
«Проверка записи» (`record_check`), чтение архива и ход сессии —
«Разбор записи» (`report.archive`, `report.timeline`) без изменений.

Единица анализа — участник: одна строка и один вес. Походы сначала
сводятся к участнику медианой, долей или в минуту, и только потом
участники сравниваются.

Встроенный Python спутника: numpy и matplotlib пришли в папку `eye/`
зависимостями MediaPipe (`eye/requirements.lock`) — ставить ничего не
нужно. pandas и scipy нет и не нужно.
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
# кодом считали. Шаг 36 — часть 1, без мер взгляда.
SCRIPT_VERSION = "36.0"

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
}


def settings(path: Path | None = None) -> dict:
    """Пороги сравнения: `study` из `thresholds.json` поверх значений по
    умолчанию."""
    values = dict(DEFAULTS)
    if path is None:
        path = Path(__file__).resolve().parent.parent.parent / \
            "thresholds.json"
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        own = raw.get("study") or {}
        for key, default in DEFAULTS.items():
            value = own.get(key)
            if isinstance(default, list):
                if isinstance(value, list) and value:
                    values[key] = value
            elif isinstance(default, str):
                if isinstance(value, str):
                    values[key] = value
            elif isinstance(value, (int, float)) and \
                    not isinstance(value, bool):
                values[key] = value
    except (OSError, ValueError, AttributeError):
        pass
    return values


def _documents() -> Path:
    home = Path(os.environ.get("USERPROFILE") or Path.home())
    docs = home / "Documents"
    return (docs if docs.is_dir() else home) / OUT_FOLDER


def out_folder(out: str | None, no_filter: bool) -> Path:
    """Куда класть отчёт: [out] как есть или «Документы\\Сравнение
    ветвей СНО2026\\<дата-время>». Не в папку `Записи` приложения: она
    приняла бы такую папку за запись."""
    if out:
        return Path(out)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    if no_filter:
        stamp += "-проверочный"
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
            limits: dict | None = None, progress=None) -> dict:
    """Весь сводный анализ без записи файлов: записи, отбор, сравнение."""
    from . import collect, compare
    cfg = cfg or settings()
    limits = limits or rc.thresholds()
    archives = collect.find(paths)
    entries = []
    for i, path in enumerate(archives, start=1):
        if progress:
            progress(i, len(archives), path)
        entries.append(collect.load(path, limits, cfg))
    collect.mark_repeats(entries)
    compare.unify_scenarios(entries)
    compare.admit(entries, cfg, no_filter, series)
    entries.sort(key=lambda e: (e.get("branch") or "~",
                                str(e.get("participant") or "~"),
                                e["archive"]))
    print_ = fingerprint(entries)
    result = compare.run(entries, cfg, fingerprint=print_,
                         no_filter=no_filter, series=series)
    result["warnings"] = compare.warnings(entries, result, no_filter)
    return {"entries": entries, "result": result, "cfg": cfg,
            "limits": limits, "fingerprint": print_, "series": series,
            "no_filter": no_filter, "archives": [str(a) for a in archives],
            "gaze_version": report_settings()["version"]}


def sources(run: dict) -> dict:
    """`исходные.json`: что разобрано и чем."""
    import matplotlib
    import numpy
    from . import stats
    return {
        "schema": "sno2026-study/1",
        "script": SCRIPT_VERSION,
        "step": "шаг 36 — часть 1: отбор, тест нагрузки, действия",
        "series": run["series"], "no_filter": run["no_filter"],
        "gaze_version": run["gaze_version"],
        "fingerprint": run["fingerprint"],
        "seed_rule": "зерно меры — первые 8 байт SHA-256 от «отпечаток, "
                     "сравнение, сценарий, мера» (stats.seed_for)",
        "seed_example": stats.seed_for(run["fingerprint"], "ветвь", "S0",
                                       "clt.ecl"),
        "archives": [{"archive": e["archive"], "path": e["path"],
                      "sha256": e.get("sha256"), "status": e["status"],
                      "reason": e.get("reason")} for e in run["entries"]],
        "thresholds": {"study": run["cfg"], "record_check": run["limits"]},
        "versions": {"python": platform.python_version(),
                     "numpy": numpy.__version__,
                     "matplotlib": matplotlib.__version__,
                     "platform": platform.platform()},
    }


def write(run: dict, folder: Path) -> list[Path]:
    """Кладёт отчёт, таблицы, рисунки и исходные в [folder]."""
    from . import charts, page, table
    folder.mkdir(parents=True, exist_ok=True)
    entries, result = run["entries"], run["result"]
    table.participants(entries, folder / "участники.csv")
    table.trips(entries, folder / "походы.csv")
    table.answers(entries, folder / "ответы_теста.csv")
    table.comparison(result, folder / "сравнение.csv")
    table.robustness(result, folder / "устойчивость.csv")
    figures = charts.draw_all(run, folder / "рисунки")
    run["_figures_folder"] = str(folder / "рисунки")
    (folder / "исходные.json").write_text(
        json.dumps(sources(run), ensure_ascii=False, indent=1),
        encoding="utf-8")
    (folder / "index.html").write_text(page.render(run, figures),
                                       encoding="utf-8")
    return [folder / "index.html"]


def summary(run: dict) -> dict:
    """Итог для `--json` и консоли."""
    entries = run["entries"]
    rows = []
    for r in run["result"]["table"]:
        if r["comparison"] != "ветвь" or r["family"] != "0":
            continue
        res = r["result"]
        rows.append({"measure": r["measure"].key, "delta": res.delta,
                     "ci": res.ci, "p": res.p, "p_holm": r["p_holm"],
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
            "search_mode": e.get("search_mode"),
        } for e in entries],
        "primary": rows,
        "warnings": run["result"]["warnings"],
        "fingerprint": run["fingerprint"],
    }


def describe(run: dict, folder: Path | None) -> list[str]:
    """Итог строками для консоли."""
    from . import honesty
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
    if folder is not None:
        lines.append(f"Отчёт: {folder / 'index.html'}")
    return lines


def main(paths: list[str], *, series: str | None = None,
         no_filter: bool = False, out: str | None = None,
         as_json: bool = False, version: str | None = None) -> int:
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
        print("Архивов записи не нашлось. Перетащите на «Сравнение ветвей» "
              "папку с архивами sno2026_….zip (можно с подпапками).")
        return 3

    def progress(i, n, path):
        if not as_json:
            print(f"[{i}/{n}] {path.name}", flush=True)

    run = analyse(paths, series=series, no_filter=no_filter,
                  progress=progress)
    if version in ("raw", "drift"):
        run["gaze_version"] = version
    folder = out_folder(out, no_filter)
    try:
        write(run, folder)
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
    return 0
