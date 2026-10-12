"""Отчёт анализа по интерфейсу — `index.html` и таблицы (SNO-F-RES-09;
шаг 43, решения владельца АО15 и АО16 от 12.10.2026).

Откуда данные: прогон `study.analyse(mode="interface")` — записи с
порядком обхода, морганиями, мерами «Сравнения ветвей», итог
`study.single.run` (группы, проверки, описание, связи, раздел отсева,
вердикт первого контакта, три списка) — и рисунки
`study.interface_charts`; портреты — `study.portrait_page` без
изменений.
Технология: `html` и `base64` стандартной библиотеки; стиль и помощники
— `study.page` (страница без внешних ресурсов: данные участников
остаются на ПК организатора).
Метод: разделы — по функции SNO-F-RES-09: состав, отсев, полка (В1–В5),
«Галактика» против предрегистрации, портреты, итог тремя списками, как
читать, исходные; таблицы — `участники.csv`, `походы.csv`,
`ответы_теста.csv`, `моменты.csv` (как у «Сравнения ветвей») и новые
`маршруты.csv`, `итог.csv`, `предрегистрация.csv`.
Вход → выход: прогон → папка отчёта.
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from . import honesty, interface_charts, prereg, single, table
from .page import (STYLE, _check_banner, _e, _img, _link, _table, ci_text,
                   num, p_text)

OUT_FOLDER = "Анализ по интерфейсу СНО2026"

FILES = (
    ("маршруты.csv", "строка на участника: интерфейс, последовательность "
     "открытий, ρ с полкой и с высотой звезды, маршрут к случайному, p, "
     "стратегия"),
    ("итог.csv", "строка на проверку: вопрос, точка отсчёта, n, сколько в "
     "сторону эффекта, медиана и интервал, p, p с поправкой, вывод, "
     "разведочный ли, держится ли в S0–S5"),
    ("предрегистрация.csv", "строка на участника «Галактики»: М1–М10 — "
     "число и «за / против», годен ли для вердикта"),
    ("участники.csv", "строка на участника: ветвь, ПК, цвет, вес, шкалы "
     "теста, меры действий и взгляда"),
    ("походы.csv", "строка на поход за книгой"),
    ("ответы_теста.csv", "строка на ответ теста нагрузки"),
    ("моменты.csv", "моменты долгого взгляда без действий (П5)"),
    ("исходные.json", "что разобрано и чем: архивы с SHA-256, пороги, "
     "версии"),
)


def _kind(kind: str) -> str:
    cls = {prereg.FOR: "yes", prereg.AGAINST: "no"}.get(kind, "")
    return f"<span class='{cls}'>{_e(kind)}</span>"


# --- таблицы -------------------------------------------------------------

def write_tables(run: dict, folder: Path) -> None:
    entries, result = run["entries"], run["result"]
    table.moments(entries, folder / "моменты.csv")
    table.participants(entries, folder / "участники.csv")
    table.trips(entries, folder / "походы.csv")
    table.answers(entries, folder / "ответы_теста.csv")
    rows = []
    for e in entries:
        o = e.get("order")
        if e.get("status") != "ok" or not o:
            continue
        rows.append([e.get("participant"), e.get("branch"),
                     e.get("interface"), e.get("colour"), e.get("in_stats"),
                     o["books"], o.get("strategy"),
                     o.get("adjacent_share"), o.get("rho_shelf"),
                     o.get("route_shelf"), o.get("p_shelf"),
                     o.get("rho_map"), o.get("route_map"), o.get("p_map"),
                     o.get("cat_switches"), o.get("map_key"),
                     " ".join(str(p) for p in o.get("shelf_places") or [])])
    table.write(folder / "маршруты.csv",
                ["участник", "ветвь", "интерфейс", "цвет", "в статистике",
                 "книг", "стратегия", "к соседней на полке", "ρ с полкой",
                 "маршрут по полке к случайному", "p полки",
                 "ρ с высотой звезды", "маршрут по карте к случайному",
                 "p карты", "смен категории", "карта",
                 "места на полке по порядку открытия"], rows)
    rows = []
    for r in result["table"]:
        c = r["check"]
        sc = r["scenarios"]
        rows.append([c.question, c.title, c.basis, c.against,
                     "главный" if c.main else "разведка",
                     c.exploratory, r["n"], r.get("toward"),
                     r.get("median"), (r.get("ci") or (None, None))[0],
                     (r.get("ci") or (None, None))[1], r.get("p"),
                     r.get("p_adj"), r.get("binom_p"), r["words"]]
                    + [sc[s]["holds"] for s in sc])
    scenarios = list(result["table"][0]["scenarios"]) \
        if result["table"] else []
    table.write(folder / "итог.csv",
                ["вопрос", "мера", "точка отсчёта", "что такое отсчёт",
                 "семья", "разведочный", "n", "в сторону эффекта",
                 "медиана отклонения", "интервал от", "интервал до", "p",
                 "p с поправкой", "биномиальный p", "вывод"]
                + [f"держится в {s}" for s in scenarios], rows)
    pre = result["prereg"]
    rows = []
    for kind, part in (("первый контакт", pre["rows"]),
                       ("справка", pre["reference"])):
        for r in part:
            rows.append([kind, r["participant"], r["started"],
                         r["colour"], r["eligible"],
                         "; ".join(r["why_not"]), r["for_main"],
                         r["against_main"]]
                        + [f"{r['cells'][k]['kind']}: "
                           f"{r['cells'][k]['words']}"
                           for k, _, _ in prereg.MEASURES])
    table.write(folder / "предрегистрация.csv",
                ["запись", "участник", "начало", "цвет", "в вердикте",
                 "почему нет", "главных «за»", "главных «против»"]
                + [f"{k} {t}" for k, t, _ in prereg.MEASURES], rows)


# --- разделы -------------------------------------------------------------

def _files(figures: dict) -> str:
    items = [f"<li>{_link('index.html', 'index.html')} — этот отчёт</li>"]
    for name, words in FILES:
        items.append(f"<li>{_link(name, name)} — {_e(words)}</li>")
    for key, name in figures.items():
        if name:
            items.append(f"<li>{_link('рисунки/' + name, key)} — "
                         f"{_e(name)}</li>")
    items.append(f"<li>{_link('Портреты/', 'Портреты')} — портрет "
                 "каждого участника</li>")
    return "<ul>" + "".join(items) + "</ul>"


def _composition(run: dict) -> str:
    rows = []
    for e in run["entries"]:
        if e["status"] != "ok":
            rows.append(["—", _e(e["archive"]), "—", "—", "—", "—",
                         "<span class='no'>архив не годен</span>: "
                         + _e(e.get("reason"))])
            continue
        o = e.get("order") or {}
        where = "<span class='yes'>в статистике</span>" if e["in_stats"] \
            else "<span class='no'>вне</span>: " + _e("; ".join(e["out"]))
        via = (e.get("actions") or {}).get("actions.via_map")
        rows.append([_e(e.get("interface") or "—"),
                     _e(e.get("participant")) + " " + _e(
                         honesty.SHORT.get(e.get("colour"), "")),
                     _e(e.get("branch")), _e(e.get("stratum")),
                     num(via) + f" <small>({_e(o.get('strategy'))})</small>",
                     _e("да" if (e.get("gaze") or {}).get("included")
                        else (e.get("gaze") or {}).get("reason") or "нет"),
                     where])
    rows.sort(key=lambda r: r[0])
    g = run["result"]["groups"]
    return (_check_banner(run) +
            "<p>Группа — <b>интерфейс, которым участник выбирал книги</b>, "
            "а не ветвь (АО15): доля открытий через карту до "
            f"{num(run['cfg']['via_map'][0])} — полка, от "
            f"{num(run['cfg']['via_map'][1])} — «Галактика», между — "
            "смешанно. Полка в сборках обеих ветвей одинакова. "
            f"Полка — {len(g[single.SHELF])}, «Галактика» — "
            f"{len(g[single.GALAXY])}, смешанно — {len(g[single.MIXED])}."
            "</p>" + _table(["Интерфейс", "Участник", "Ветвь", "ПК",
                             "Доля открытий картой (маршрут)",
                             "Взгляд в анализе", "В статистике"], rows))


def _reds(run: dict) -> str:
    reds = run["result"]["reds"]
    if not reds["people"]:
        return "<p>Участников с проваленными обоими пунктами шкалы лжи нет.</p>"
    rows = []
    for p in reds["people"]:
        vals = "; ".join(f"{single.TITLE.get(k, k)}: {num(v)}"
                         for k, v in p["values"].items())
        rows.append([_e(p["participant"]) + " 🔴", _e(p["interface"]),
                     num(p["lie"].get("lie.defer"), 0),
                     num(p["lie"].get("lie.late"), 0), _e(p["reason"]),
                     _e(vals)])
    main = {r["check"].key: r for r in run["result"]["table"]
            if r["check"].main}
    cmp_rows = []
    for w in reds["with_reds"]:
        own = main.get(w["key"])
        cmp_rows.append([_e(w["question"]),
                         _e(single.TITLE.get(w["key"], w["key"])),
                         f"{own['n'] if own else '—'} → {w['n']}",
                         f"{num(own and own['median'])} → "
                         f"{num(w['median'])}",
                         f"{p_text(own and own.get('p_adj'))} → "
                         f"{p_text(w['p_adj'])}"])
    return ("<p>Шкала лжи — два пункта о мелких слабостях, которые есть у "
            "каждого: «Мне случалось откладывать…» (отметка — несогласие, "
            "1–3) и «Я ни разу в жизни никуда не опоздал» (отметка — "
            "согласие, 5–7). Кто провалил оба — выставляет себя лучше, чем "
            "есть, и его ответам о нагрузке и ориентации верить нельзя: "
            "такой участник вне статистики целиком (решение АК). Ниже — "
            "кто это, что он ответил и что стало бы с главными вопросами "
            "полки, если бы его оставили с весом 1 (АО3).</p>"
            + _table(["Участник", "Интерфейс", "«Откладывал» (1–7)",
                      "«Ни разу не опоздал» (1–7)", "Почему 🔴",
                      "Его числа"], rows)
            + "<p>Главные вопросы полки — как в отчёте → с 🔴:</p>"
            + _table(["Вопрос", "Мера", "n", "Медиана отклонения",
                      "p с поправкой"], cmp_rows))


def _check_rows(run: dict, questions) -> str:
    rows = []
    for r in run["result"]["table"]:
        c = r["check"]
        if c.question not in questions:
            continue
        tag = " <small>(разведочный)</small>" if c.exploratory else ""
        words = r["words"]
        cls = "yes" if words.startswith("установлено") else ""
        rows.append([f"<b>{_e(c.question)}</b>{tag}", _e(c.title),
                     _e(c.basis) + "<br><small>" + _e(c.against)
                     + "</small>",
                     f"{r.get('toward') if r['n'] else '—'} из {r['n']}",
                     num(r.get("median")) + " " + ci_text(r.get("ci")),
                     p_text(r.get("p")), p_text(r.get("p_adj")),
                     f"<span class='{cls}'>{_e(words)}</span>"])
    return _table(["Вопрос", "Мера", "Точка отсчёта",
                   "В сторону эффекта", "Медиана отклонения [95 %]", "p",
                   "p с поправкой", "Вывод"], rows)


def _describe_rows(run: dict, keys) -> str:
    rows = []
    for d in run["result"]["describe"]:
        if d["key"] not in keys or not d.get("n"):
            continue
        q = d.get("q")
        rows.append([_e(d["title"]), _e(d["unit"]), str(d["n"]),
                     num(d.get("median")),
                     f"{num(q[0])}–{num(q[1])}" if q else "—",
                     f"{num(d.get('min'))}–{num(d.get('max'))}"])
    if not rows:
        return "<p class='later'>Данных нет.</p>"
    return _table(["Мера", "Единицы", "n", "Медиана",
                   "Квартили", "Размах"], rows, num_cols=(2, 3))


def _routes(run: dict) -> str:
    rows = []
    for e in run["entries"]:
        o = e.get("order")
        if e.get("interface") is None or not o:
            continue
        rows.append([_e(e.get("interface")),
                     _e(e.get("participant")) + " " + _e(
                         honesty.SHORT.get(e.get("colour"), "")),
                     str(o["books"]), _e(o.get("strategy")),
                     num(o.get("rho_shelf")), num(o.get("route_shelf")),
                     p_text(o.get("p_shelf")), num(o.get("rho_map")),
                     num(o.get("route_map")), p_text(o.get("p_map")),
                     num(o.get("cat_switches"))])
    rows.sort(key=lambda r: r[0], reverse=True)
    return _table(["Интерфейс", "Участник", "Книг", "Стратегия",
                   "ρ с полкой", "Маршрут по полке", "p",
                   "ρ с высотой звезды", "Маршрут по карте", "p",
                   "Смен категории"], rows)


def _prereg(run: dict) -> str:
    pre = run["result"]["prereg"]
    v = pre["verdict"]
    pc = pre["settings"]
    head = (f"<p>Ожидания записаны 12.10.2026 до записей первого контакта "
            "(«Галактика — ожидаемое влияние сортировки "
            "(предрегистрация)»); пороги — <code>study.prereg</code>, "
            "после данных не правятся. Первый контакт — запись, где книги "
            f"выбирались картой, начатая не раньше {_e(pre['after'])}. "
            "Главные ожидания — М2, М3, М4, М5; <b>подтверждено</b>, если "
            f"«за» хотя бы в {pc['of_main']} из четырёх у не меньше чем "
            "двух третей участников со взглядом (точность не хуже 3°) и "
            "пройденным тестом; <b>опровергнуто</b> — так же «против»; "
            "иначе — <b>не решено</b>.</p>")
    word = v["word"]
    cls = "yes" if word == prereg.CONFIRMED else (
        "no" if word == prereg.REFUTED else "")
    verdict = (f"<p><b>Вердикт: <span class='{cls}'>{_e(word)}</span></b>"
               f" — первого контакта {v['first_contact']}, в вердикте "
               f"{v['n']}; «за» в трёх из четырёх главных — {v['for']}, "
               f"«против» — {v['against']}"
               + (f"; нужно не меньше {v['need_people']}"
                  if v.get("need_people") else "") + ".</p>")

    def rows_of(part):
        rows = []
        for r in part:
            cells = [f"{_kind(r['cells'][k]['kind'])}<br><small>"
                     f"{_e(r['cells'][k]['words'])}</small>"
                     for k, _, _ in prereg.MEASURES]
            who = _e(r["participant"]) + " " + _e(
                honesty.SHORT.get(r["colour"], ""))
            state = (f"{r['for_main']} из 4" if r["eligible"] else
                     "вне: " + _e("; ".join(r["why_not"])))
            rows.append([who] + cells + [state])
        return rows

    header = ["Участник"] + [f"{k} {t}" for k, t, _ in prereg.MEASURES] \
        + ["Главных «за»"]
    shelf = {d["key"]: d for d in run["result"]["describe"]}

    def ref(key):
        d = shelf.get(key) or {}
        return num(d.get("median"))

    basis = (f"<p>Опора полки (медианы этого прогона; в предрегистрации — "
             f"ECL {num(pc['M3_shelf'], 1)}, «быстро находил» "
             f"{num(pc['M4_orient1'], 0)}, «помнил» "
             f"{num(pc['M4_orient2'], 0)}, вход "
             f"{num(pc['M7_shelf'], 1)} с): ECL {ref('clt.ecl')}, "
             f"«быстро находил» {ref('orient.1')}, «помнил» "
             f"{ref('orient.2')}, вход {ref('learn.entry_s')} с, выбор "
             f"после первого похода {ref('learn.after_first_s')} с.</p>")
    out = head + verdict + basis
    if pre["rows"]:
        out += _table(header, rows_of(pre["rows"]))
    else:
        out += ("<p class='later'>Записей первого контакта нет: положите "
                "их в ту же папку и прогоните отчёт снова.</p>")
    if pre["reference"]:
        out += ("<h3>Справка: записи «Галактики» до предрегистрации</h3>"
                "<p>Эти записи видели, когда писали ожидания, — в вердикт "
                "они не идут.</p>" + _table(header,
                                            rows_of(pre["reference"])))
    return out


def _portraits(run: dict) -> str:
    rows = []
    for p in run.get("_portraits") or []:
        e = p["entry"]
        rows.append([_link(p["link"], str(e.get("participant"))),
                     _e(e.get("interface")), _e(e.get("stratum")),
                     _e(honesty.SHORT.get(e.get("colour"), "")),
                     _e("; ".join(p.get("marks") or []))])
    if not rows:
        return "<p class='later'>Портреты не собирались.</p>"
    return _table(["Портрет", "Интерфейс", "ПК", "Цвет", "Пометки"], rows)


def _summary(run: dict) -> str:
    s = run["result"]["summary"]

    def items(lines):
        out = []
        for line in lines:
            tag = " <small>(разведочный: найден в этих данных, "\
                "подтверждать на новых)</small>" if line.get("exploratory") \
                else ""
            out.append(f"<li><b>{_e(line['question'])}</b> · "
                       f"{_e(line['title'])}: {_e(line['words'])}{tag}</li>")
        return "<ul>" + "".join(out) + "</ul>" if out else \
            "<p class='later'>Нет.</p>"

    return ("<h3>Установлено</h3>" + items(s["established"])
            + "<h3>Описано</h3>" + items(s["described"])
            + "<h3>Этими данными не сказать</h3><ul>"
            + "".join(f"<li>{_e(x)}</li>" for x in s["cannot"]) + "</ul>")


def _links(run: dict) -> str:
    rows = []
    for link in run["result"]["links"]:
        rows.append([_e(single.TITLE.get(link["a"], link["a"])),
                     _e(single.TITLE.get(link["b"], link["b"])),
                     str(link["n"]), num(link["rho"])])
    return ("<p>Разведка: ранговая связь самооценки нагрузки с "
            "глазодвигательными признаками у тех же людей (ρ Спирмена с "
            "весами, от пяти участников). Это не вывод о причине — "
            "сходится ли честная самооценка с тем, что видно в "
            "записи.</p>" + _table(["Самооценка", "Признак", "n", "ρ"],
                                   rows, num_cols=(2, 3)))


HOW_TO_READ = """
<p><b>Точка отсчёта вместо контрольной группы.</b> Группа одна, поэтому
каждого участника сравнивают со случаем (маршрут — со случайными
перестановками тех же книг; энтропия — со случайным взглядом; возвраты —
с поиском без памяти) или с самим собой (конец сессии — с началом,
чтение — с выбором книги). Отклонение участника от точки отсчёта — одно
число; группа проверяется по этим числам.</p>
<p><b>Знаковая перестановка.</b> Если эффекта нет, каждое отклонение с
равным успехом могло бы быть и со знаком плюс, и со знаком минус.
Перебираются все такие разметки (до 16 участников — все 2ⁿ), p — доля
разметок, у которых взвешенная сумма отклонений по модулю не меньше
настоящей. Рядом — «сколько из скольких»: так результат читается без
статистики.</p>
<p><b>«Не доказано» — не «случайно».</b> Участников мало, и эффект
находится, только если он есть почти у всех: при девяти участниках p
меньше 0,05 даёт сторона эффекта у восьми из девяти. Поэтому «не
доказано» значит «эти данные не решают», а не «эффекта нет».</p>
<p><b>Разведочный вопрос</b> — заданный после того, как данные увидели
(маршрут, чтение против выбора, моргания): его подтверждают на новых
записях.</p>
<p><b>Вердикт «Галактики»</b> — не статистическое сравнение групп:
первый контакт — другие люди и, может быть, другой ПК. Каждое ожидание
показывается по участникам («за» у скольких из скольких), правило
вердикта записано до данных.</p>
"""


def render(run: dict, figures: dict, folder: Path) -> str:
    entries = run["entries"]
    ok = sum(1 for e in entries if e["status"] == "ok")
    when = datetime.now().strftime("%d.%m.%Y %H:%M")
    warn = run["result"]["warnings"]
    warn_html = ("<div class='warn'><ul>" + "".join(
        f"<li>{_e(w)}</li>" for w in warn) + "</ul></div>") if warn else ""
    figs = folder / "рисунки"
    sections = [
        ("Файлы отчёта", _files(figures)),
        ("1. Состав: кто каким интерфейсом выбирал книги",
         _composition(run)),
        ("2. Как отсеивались недостоверные результаты", _reds(run)),
        ("3. Полка: маршрут по библиотеке (В1)",
         _check_rows(run, ("В1",)) + _routes(run)
         + _img(figs, figures.get("Р20"), "Р20. Маршрут по библиотеке")),
        ("4. Полка: ход сессии (В2)",
         _check_rows(run, ("В2",))
         + _describe_rows(run, ("learn.entry_s", "learn.after_first_s",
                                "actions.time_to_choice"))),
        ("5. Полка: упорядоченность взгляда (В3)",
         _check_rows(run, ("В3",))
         + _describe_rows(run, ("search.path", "search.straight",
                                "search.fix_ms", "reading.fix_ms"))),
        ("6. Полка: память расположения (В4)",
         _check_rows(run, ("В4",))
         + _describe_rows(run, ("orient.1", "orient.2"))
         + "<p>Меры запомненного нет: бланк формальный (12.10.2026, "
         "19:57) — самооценка остаётся самоотчётом.</p>"),
        ("7. Полка: нагрузка и утомление (В5)",
         _describe_rows(run, ("clt.ecl", "clt.raw_tlx", "clt.raw_tlx5",
                              "clt.icl", "clt.gcl", "clt.tlx.physical",
                              "blinks.per_min",
                              "portrait.lookbacks_per_min",
                              "portrait.page_backs_per_min",
                              "nav.rewinds", "nav.opened_mid"))
         + _check_rows(run, ("В5",)) + _links(run)
         + _img(figs, figures.get("Р22"), "Р22. Моргания по ходу изучения")),
        ("8. Полка: все проверки одним рисунком",
         _img(figs, figures.get("Р21"), "Р21. Проверки одной группы")),
        ("9. «Галактика»: первый контакт против предрегистрации",
         _prereg(run)),
        ("10. Портреты участников", _portraits(run)),
        ("11. Итог", _summary(run)),
        ("12. Как читать", HOW_TO_READ),
        ("Исходные", f"<p>Отпечаток набора: <code>"
         f"{_e(run['fingerprint'][:16])}</code> · версия взгляда для мер: "
         f"{_e(run['gaze_version'])}. Архивы с SHA-256, пороги и версии — "
         "<code>исходные.json</code>: по нему прогон повторяется до "
         "бита.</p>"),
    ]
    body = "".join(f"<h2>{_e(t)}</h2>{s}" for t, s in sections)
    return f"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Анализ по интерфейсу СНО2026</title>
<style>{STYLE}</style></head>
<body><main>
<h1>Анализ по интерфейсу СНО2026</h1>
<p class="sub">Собрано {when} · архивов {len(entries)}, годных {ok} ·
{_e(run['series'] or 'все серии в папке')} · версия взгляда для мер:
{_e(run['gaze_version'])}</p>
{warn_html}
{body}
</main></body></html>
"""


def write(run: dict, folder: Path, portraits: bool = True,
          literature: list[str] | None = None) -> list[Path]:
    from . import portrait_page, screen_shot, sources
    folder.mkdir(parents=True, exist_ok=True)
    run["_library"] = screen_shot.Library(
        list(literature or []) + list(run.get("paths") or []))
    write_tables(run, folder)
    figures = interface_charts.draw_all(run, folder / "рисунки")
    run["_portraits"] = portrait_page.write_all(run, folder) if portraits \
        else None
    run["_folder"] = str(folder)
    (folder / "исходные.json").write_text(
        json.dumps(sources(run), ensure_ascii=False, indent=1),
        encoding="utf-8")
    (folder / "index.html").write_text(render(run, figures, folder),
                                       encoding="utf-8")
    return [folder / "index.html"]
