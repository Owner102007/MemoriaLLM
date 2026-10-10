"""Шаг 11 — отчёт `index.html` (SNO-F-RES-06, «Что выходит»).

Откуда данные: прогон `study.analyse` — записи, сравнение, сценарии,
оговорки — и рисунки `study.charts`.
Технология: `html` (экранирование) и `base64` (рисунки внутри файла)
стандартной библиотеки. Страница без внешних скриптов, шрифтов и
картинок — по образцу «Разбора записи» (`report/html.py`), стиль оттуда
же: данные участников остаются на ПК организатора.
Метод: разделы — по «Сводный анализ — структура скрипта»: состав
выборки, качество взгляда по ПК, нагрузка, действия, (беспорядочность,
средний взгляд, научение — шаг 37), сводка «I против II», устойчивость,
«Как читать», оговорки, исходные.
Вход → выход: прогон и рисунки → текст страницы.
"""

from __future__ import annotations

import base64
import html
import statistics
from datetime import datetime
from pathlib import Path

from ..report.html import STYLE as BASE_STYLE
from . import compare, honesty

STYLE = BASE_STYLE + """
.warn { border-left: 3px solid var(--accent); padding: 8px 12px;
  background: var(--surface-2); margin: 12px 0; border-radius: 4px; }
.warn li { color: var(--text); }
.check { border: 2px dashed var(--accent); color: var(--accent);
  padding: 6px 10px; border-radius: 6px; margin: 8px 0; font-weight: 600; }
figure.chart { background: #fcfcfb; }
figure.chart img { display: block; width: 100%; height: auto; }
.later { color: var(--text-3); font-style: italic; }
td.out { color: var(--text-3); }
.main-row td { font-weight: 600; }
details { margin: 8px 0; }
summary { cursor: pointer; color: var(--text-2); }
"""


def _e(value) -> str:
    return html.escape("" if value is None else str(value))


def num(value, digits: int = 2) -> str:
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "да" if value else "нет"
    if isinstance(value, int):
        return str(value)
    return f"{value:.{digits}f}".replace(".", ",")


def p_text(p) -> str:
    if p is None:
        return "—"
    if p < 0.001:
        return "< 0,001"
    return f"{p:.3f}".replace(".", ",")


def ci_text(ci) -> str:
    if not ci:
        return "—"
    return f"[{num(ci[0])}; {num(ci[1])}]"


def _img(folder: Path, name: str | None, caption: str) -> str:
    if not name:
        return f"<p class='later'>{_e(caption)}: данных для рисунка нет.</p>"
    data = (folder / name).read_bytes()
    src = "data:image/png;base64," + base64.b64encode(data).decode("ascii")
    return (f"<figure class='chart'><img src='{src}' alt='{_e(caption)}'>"
            f"<figcaption>{_e(caption)} · файлы — рисунки\\"
            f"{_e(name)} и .svg</figcaption></figure>")


def _check_banner(run: dict) -> str:
    if not run["no_filter"]:
        return ""
    return "<div class='check'>Проверочный прогон, не для выводов</div>"


def _table(header: list[str], rows: list[list[str]], num_cols=()) -> str:
    head = "".join(f"<th class='{'num' if i in num_cols else ''}'>{_e(h)}"
                   "</th>" for i, h in enumerate(header))
    body = []
    for row in rows:
        cls = ""
        if isinstance(row, tuple):
            cls, row = row
        cells = "".join(
            f"<td class='{'num' if i in num_cols else ''}'>{c}</td>"
            for i, c in enumerate(row))
        body.append(f"<tr class='{cls}'>{cells}</tr>")
    return (f"<div class='scroll'><table><tr>{head}</tr>{''.join(body)}"
            "</table></div>")


# --- разделы ----------------------------------------------------------------

def _composition(run: dict, folder: Path, figures: dict) -> str:
    rows = []
    for e in run["entries"]:
        if e["status"] != "ok":
            rows.append(("", [_e(e["archive"]), "—", "—", "—", "—", "—", "—",
                              "—", "—", "<span class='no'>архив не годен"
                              f"</span>: {_e(e.get('reason'))}"]))
            continue
        g = e["gaze"]
        gaze = "в анализе" if g["included"] else _e(g.get("reason"))
        where = "<span class='yes'>в статистике</span>" if e["in_stats"] \
            else "<span class='no'>вне</span>: " + _e("; ".join(e["out"]))
        rows.append(("" if e["in_stats"] else "", [
            _e(e.get("participant")), _e(e.get("branch")),
            _e(e.get("stratum")),
            _e(honesty.WORDS.get(e.get("colour"))) + "<br><small>"
            + _e(e.get("colour_reason")) + "</small>",
            num(e.get("weight")), _e(e.get("etalon")) + (
                "<br><small>" + _e("; ".join(e.get("etalon_reasons") or []))
                + "</small>" if e.get("etalon_reasons") else ""),
            gaze, num((e.get("study_s") or 0) / 60, 0),
            _e(e.get("search_mode") or "—"), where]))
    used = [e for e in run["entries"] if e.get("in_stats")]
    by = {b: sum(1 for e in used if e.get("branch") == b) for b in ("I", "II")}
    text = (f"<p>Архивов: {len(run['entries'])}; в статистике — "
            f"{len(used)} (ветвь I — {by['I']}, ветвь II — {by['II']}). "
            "Вес: 🟢 — 1, 🟡 и ⚪ — "
            f"{num(run['cfg']['yellow_weight'])}, 🔴 — вне статистики "
            "целиком.</p>")
    return (_check_banner(run) + text + _table(
        ["Участник", "Ветвь", "ПК (слой)", "Цвет", "Вес", "Эталон",
         "Взгляд", "Изучение, мин", "Способ поиска", "В статистике"],
        rows, num_cols=(4, 7))
        + _img(folder, figures.get("Р1"), "Р1. Состав выборки")
        + _img(folder, figures.get("Р2"),
               "Р2. Шкала лжи: как получился цвет каждого"))


def _quality(run: dict, folder: Path, figures: dict) -> str:
    rows = []
    strata = sorted({e["stratum"] for e in run["entries"]
                     if e["status"] == "ok"})
    for s in strata:
        part = [e for e in run["entries"] if e["status"] == "ok"
                and e["stratum"] == s]
        present = [e for e in part if e["gaze"]["present"]]
        starts = [e["gaze"]["start_deg"] for e in present
                  if e["gaze"]["start_deg"] is not None]
        ends = [e["gaze"]["end_deg"] for e in present
                if e["gaze"]["end_deg"] is not None]
        rows.append([_e(s), str(len(part)),
                     ", ".join(sorted({str(e.get('branch')) for e in part})),
                     str(len(present)),
                     str(sum(1 for e in present if e["gaze"]["included"])),
                     num(statistics.median(starts) if starts else None, 1),
                     num(statistics.median(ends) if ends else None, 1)])
    return (_check_banner(run) +
            "<p>Взгляд сессии входит в анализ, если средняя точность "
            "проверок в начале и в конце не хуже "
            f"{num(run['limits']['include_deg'], 0)}° (Т19). Тест и "
            "действия такая сессия отдаёт всегда. Меры взгляда — шаг 37; "
            "здесь — сколько сессий их дадут.</p>"
            + _table(["ПК (слой)", "Сессий", "Ветви", "Со взглядом",
                      "Взгляд в анализе", "Точность в начале, медиана, °",
                      "В конце, медиана, °"], rows, num_cols=(1, 3, 4, 5, 6))
            + _img(folder, figures.get("Р3"),
                   "Р3. Качество взгляда по сессиям"))


def _measure_rows(run: dict, keys, comparison=compare.BRANCH) -> list:
    rows = []
    table = {(r["comparison"], r["measure"].key): r
             for r in run["result"]["table"]}
    for key in keys:
        r = table.get((comparison, key))
        if r is None:
            continue
        m = r["measure"]
        a, b = r["groups"]
        if r["pending"]:
            rows.append([_e(m.title), "—", "—", "—", "—", "—",
                         f"<span class='later'>{_e(r['words'])}</span>"])
            continue
        res = r["result"]
        da, db = res.describe.get(a, {}), res.describe.get(b, {})
        cls = "main-row" if r["family"] == "0" else ""
        rows.append((cls, [
            _e(m.title) + f"<br><small>{_e(m.unit)}; больше — "
            f"{_e(m.more)}</small>",
            f"{num(db.get('mean'))} <small>(n {db.get('n', 0)}, "
            f"n_eff {num(db.get('n_eff'), 1)})</small>",
            f"{num(da.get('mean'))} <small>(n {da.get('n', 0)}, "
            f"n_eff {num(da.get('n_eff'), 1)})</small>",
            num(res.delta) + (f" <small>{_e(r['effect'])}</small>"
                              if res.delta is not None else ""),
            ci_text(res.ci), p_text(r.get("p_holm")), _e(r["words"])]))
    return rows


MEASURE_HEADER = ["Мера", "Ветвь I: среднее", "Ветвь II: среднее", "δ",
                  "Интервал 95 %", "p по Холму", "Вывод"]


def _load(run: dict, folder: Path, figures: dict) -> str:
    keys = ["clt.ecl", "clt.raw_tlx"] + [k for k, _, _ in
                                         compare_load_keys()]
    return (_check_banner(run) +
            "<p>Шкалы — по правилу «Подсчёт» теста; в сравнение идут числа "
            "приложения (`clt/scores.json`), пересчёт сверяет их. ECL — "
            "главная мера (АК4); ICL показывает, что материал обеим ветвям "
            "достался одинаково трудным.</p>"
            + _table(MEASURE_HEADER, _measure_rows(run, keys))
            + _img(folder, figures.get("Р4"), "Р4. Нагрузка по ветвям"))


def compare_load_keys():
    from . import clt
    return [s for s in clt.SCALES if s[0] not in ("clt.ecl", "clt.raw_tlx")] \
        + list(clt.TLX_ITEMS)


def _actions(run: dict, folder: Path, figures: dict) -> str:
    keys = ["actions.time_to_choice"] + [
        m.key for m in compare.MEASURES if m.key.startswith("actions.")
        and m.key != "actions.time_to_choice"]
    return (_check_banner(run) +
            "<p>Поход за книгой — от выхода из читалки (или от начала "
            "изучения) до следующего открытия книги, сквозь полку, карту и "
            "поиск по названию. Время до выбора — время на полке и карте до "
            "нажатия: на карте — касание звезды, а не кнопки в карточке. "
            "Сначала походы сводятся к участнику медианой, долей или в "
            "минуту, потом участники сравниваются.</p>"
            + _table(MEASURE_HEADER, _measure_rows(run, keys))
            + _img(folder, figures.get("Р5"), "Р5. Действия"))


def _later(title: str) -> str:
    return (f"<p class='later'>{_e(title)} — следующий шаг (шаг 37): "
            "меры взгляда считаются по «Разбору записи» каждой сессии со "
            "взглядом в анализе.</p>")


def _summary(run: dict, folder: Path, figures: dict) -> str:
    result = run["result"]
    primary = [m.key for m in compare.primary(run["cfg"])]
    parts = [_check_banner(run)]
    parts.append("<p>Главные меры названы до основной серии (АК4) и "
                 "поправляются по Холму своей семьёй; остальное — "
                 "разведка, и так и подписано. Вывод словами — только когда "
                 "n_eff в сравнимых слоях не меньше "
                 f"{num(run['cfg']['n_eff_min'], 0)} в обеих ветвях, "
                 "интервал δ не накрывает ноль и p по Холму меньше "
                 f"{num(run['cfg']['alpha'])}.</p>")
    parts.append("<h3>Главные меры</h3>")
    parts.append(_table(MEASURE_HEADER, _measure_rows(run, primary)))
    parts.append(_img(folder, figures.get("Р13"),
                      "Р13. Сводка «I против II»"))
    for family, title in compare.FAMILIES.items():
        if family == "0":
            continue
        keys = [r["measure"].key for r in result["table"]
                if r["comparison"] == compare.BRANCH
                and r["family"] == family]
        if not keys:
            continue
        parts.append(f"<details><summary>Разведка — {_e(title)}"
                     "</summary>" + _table(MEASURE_HEADER,
                                           _measure_rows(run, keys))
                     + "</details>")
    for comparison in (compare.MODE_ALL, compare.MODE_II):
        rows = _measure_rows(run, primary + ["clt.raw_tlx"], comparison)
        parts.append(
            f"<details><summary>Разведка — {_e(comparison)}: «картой» "
            "против «полкой»</summary><p>Способ участник выбрал сам, и "
            "разница может быть в людях, которые его выбирают, а не в "
            "способе. «Смешанно» сюда не входит. Все меры — в "
            "<code>сравнение.csv</code>.</p>"
            + _table(["Мера", "«полкой»: среднее", "«картой»: среднее",
                      "δ", "Интервал 95 %", "p по Холму", "Вывод"], rows)
            + "</details>")
    links = result.get("links") or []
    if links:
        rows = [[f"ветвь {_e(x['branch'])}",
                 f"{_e(compare.BY_KEY[x['a']].title)} × "
                 f"{_e(compare.BY_KEY[x['b']].title)}", str(x["n"]),
                 num(x["rho"])] for x in links]
        parts.append("<details><summary>Разведка — связи мер (Спирмен с "
                     "весами)</summary><p>Слов о причинах нет. `H_t` и "
                     "наклон научения добавятся в шаге 37.</p>"
                     + _table(["Ветвь", "Меры", "n", "ρ"], rows,
                              num_cols=(2, 3)) + "</details>")
    return "".join(parts)


def _robust(run: dict, folder: Path, figures: dict) -> str:
    rows = []
    for item in run["result"]["robust"]:
        for case in item["cases"]:
            res = case["result"]
            rows.append([_e(item["measure"].title),
                         f"{case['scenario']} — {_e(case['title'])}",
                         num(res.n_eff_cmp.get("II"), 1),
                         num(res.n_eff_cmp.get("I"), 1),
                         num(res.delta), ci_text(res.ci),
                         "да" if res.enough else "мало данных",
                         _e(item["verdict"])])
    return (_check_banner(run) +
            "<p>Вывод устойчив, если во всех сценариях, где данных хватает, "
            "у δ один знак и |δ| ≥ 0,147. S3 показывает, что меняет отсев по "
            "искренности; S4 — по точности взгляда (для теста и действий "
            "он совпадает с S0); S5 — что меняет запись не с эталона.</p>"
            + _table(["Мера", "Сценарий", "II: n_eff", "I: n_eff", "δ",
                      "Интервал 95 %", "Данных хватает", "Вывод"], rows,
                     num_cols=(2, 3, 4))
            + _img(folder, figures.get("Р14"), "Р14. Устойчивость"))


def _how_to_read(run: dict) -> str:
    items = "".join(
        f"<li><b>{_e(m.title)}</b> ({_e(m.unit)}): больше — "
        f"{_e(m.more)}.</li>" for m in compare.MEASURES)
    return f"""
<p><b>Вес.</b> Цвет искренности — по двум пунктам шкалы лжи теста
(<code>lie.defer</code>, <code>lie.late</code>): ни один не провален — 🟢,
вес 1; провален один — 🟡, вес {num(run['cfg']['yellow_weight'])}; провалены
оба — 🔴, участник целиком вне статистики; нет ответа — ⚪, как 🟡.
Прочие отметки теста («небрежность») стоят в <code>участники.csv</code>
и в вес не идут.</p>
<p><b>n_eff</b> = (Σw)² / Σw² — со сколькими участниками равного веса
выборка сравнима по точности среднего (Kish, 1965).</p>
<p><b>δ Клиффа</b> — доля пар «у ветви II больше» минус доля пар «у ветви
II меньше», с весами пар; от −1 до 1, 0 — разницы нет. Не боится
выбросов и не требует нормального распределения. Считается внутри
каждого ПК, где были обе ветви, и сводится вместе: разница камер не
выдаётся за разницу ветвей. Величина: меньше 0,147 — пренебрежимо, до
0,33 — мала, до 0,474 — средняя, дальше — большая (Romano и др.,
2006).</p>
<p><b>Интервал 95 %</b> — бутстреп: участники вытягиваются с возвращением
внутри своей ветви и своего ПК, {run['cfg']['bootstrap']} повторов. При
пяти–восьми участниках в ветви такой интервал выходит уже настоящего —
читайте его как нижнюю оценку неопределённости.</p>
<p><b>p</b> — перестановочный тест для той же δ: метки ветвей
перемешиваются внутри ПК, веса остаются при участниках; перестановок не
больше {run['cfg']['exact_limit']} — перебираются все (точный тест).
<b>Поправка Холма</b> — внутри семьи мер; у главных мер недостающая пока
<code>H_t</code> входит в поправку с p = 1.</p>
<p><b>Меры</b>:</p><ul>{items}</ul>"""


def _sources(run: dict) -> str:
    import platform
    try:
        import numpy
        import matplotlib
        versions = (f"Python {platform.python_version()}, numpy "
                    f"{numpy.__version__}, matplotlib "
                    f"{matplotlib.__version__}")
    except ImportError:  # pragma: no cover
        versions = f"Python {platform.python_version()}"
    return (f"<p>Отпечаток набора: <code>{_e(run['fingerprint'][:16])}"
            f"</code> · зерно меры — "
            f"<code>stats.seed_for</code> от отпечатка, сравнения, сценария и "
            f"меры · версия взгляда для мер (шаг 37): "
            f"{_e(run['gaze_version'])} · {_e(versions)}. Архивы с "
            "SHA-256, пороги и версии — <code>исходные.json</code>: по нему "
            "прогон повторяется до бита.</p>")


def render(run: dict, figures: dict) -> str:
    folder = Path(run.get("_figures_folder") or ".")
    return _render(run, figures, folder)


def _render(run: dict, figures: dict, folder: Path) -> str:
    entries = run["entries"]
    ok = sum(1 for e in entries if e["status"] == "ok")
    used = sum(1 for e in entries if e.get("in_stats"))
    when = datetime.now().strftime("%d.%m.%Y %H:%M")
    warn = run["result"]["warnings"]
    warn_html = ("<div class='warn'><ul>" + "".join(
        f"<li>{_e(w)}</li>" for w in warn) + "</ul></div>") if warn else ""
    series = run["series"] or "все серии в папке"
    sections = [
        ("1. Состав выборки", _composition(run, folder, figures)),
        ("2. Качество взгляда по ПК", _quality(run, folder, figures)),
        ("3. Нагрузка", _load(run, folder, figures)),
        ("4. Действия", _actions(run, folder, figures)),
        ("5. Беспорядочность взгляда", _later("Беспорядочность взгляда")),
        ("6. Средний взгляд", _later("Средний взгляд ветви")),
        ("7. Научение", _later("Кривая научения")),
        ("8. Сводка «I против II»", _summary(run, folder, figures)),
        ("9. Устойчивость", _robust(run, folder, figures)),
        ("10. Как читать", _how_to_read(run)),
        ("Исходные", _sources(run)),
    ]
    body = "".join(f"<h2>{_e(t)}</h2>{s}" for t, s in sections)
    return f"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Сравнение ветвей СНО2026</title>
<style>{STYLE}</style></head>
<body><main>
<h1>Сравнение ветвей СНО2026</h1>
<p class="sub">Собрано {when} · архивов {len(entries)}, годных {ok}, в
статистике {used} · {_e(series)} · шаг 36: отбор, тест нагрузки, действия
(меры взгляда — шаг 37)</p>
{warn_html}
{body}
</main></body></html>
"""

