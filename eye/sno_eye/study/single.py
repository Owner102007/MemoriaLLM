"""Анализ по интерфейсу: полка против случая и самой себя, «Галактика»
против ожиданий (SNO-F-RES-09, SNO-ALG-RES-12; шаг 43, решения
владельца АО, АО15 и АО16 от 12.10.2026).

Откуда данные: записи «Сравнения ветвей» после отбора (`study.collect`,
`study.compare.admit`): цвет искренности и вес, тест нагрузки, походы и
меры действий, научение (`study.average.learning`, BUG-75), меры
взгляда (`study.disorder`), портрет (`study.portrait`), порядок обхода
(`study.order`), моргания (`study.blinks`); вердикт «Галактики» —
`study.prereg`.
Технология: numpy через `study.stats` — точная знаковая перестановка,
бутстреп медианы, поправки Холма и Бенджамини — Хохберга.
Метод (SNO-ALG-RES-12):
* группа — **интерфейс, которым участник выбирал книги** (АО15), а не
  ветвь: «полка» — доля открытий через карту до `study.via_map[0]`
  (ветвь I — всегда полка), «Галактика» — от `study.via_map[1]`,
  между — «смешанно» (случаями);
* одно число на участника — отклонение от точки отсчёта `d`: против
  случая (маршрут к случайному, энтропия к случайному уровню, возвраты
  к «без памяти») или против самого участника (наклон, последняя треть
  против первой, чтение против выбора, конец сессии против начала);
* проверка группы — знаковая перестановка `Σ wᵢ dᵢ`
  (`stats.sign_flip_p`); рядом — «сколько из скольких» и точный
  биномиальный p; взвешенная медиана `d` с интервалом 95 % бутстрепом;
* поправки — Холм у главных вопросов (АО2: В1–В3), Бенджамини —
  Хохберг в разведочной семье (АЛ5);
* слова «установлено» — только если участников с мерой не меньше
  `study.single.n_min`, p с поправкой меньше `study.alpha`, интервал
  медианы не накрывает точку отсчёта и вывод держится во всех
  сценариях отбора S0–S5, где участников хватает; иначе «не доказано»
  (не «случайно» и не «не меняется»); вопросы, заданные после того, как
  данные увидели, — «разведочный» при любом p.
Вход → выход: записи → группы, проверки, описания, связи, раздел
отсева (🔴), вердикт первого контакта и итог тремя списками.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from . import compare, honesty, prereg, stats
from .actions import MODE_MAP, MODE_MIXED, MODE_SHELF

SHELF = "полка"
GALAXY = "Галактика"
MIXED = "смешанно"

DEFAULTS = {
    # Участников с мерой меньше — только числа, без «установлено».
    "n_min": 6,
    # Повторов бутстрепа медианы и розыгрышей знаков (n > 16).
    "bootstrap": 10_000,
    "repeats": 10_000,
}


def settings(raw: dict | None) -> dict:
    out = dict(DEFAULTS)
    for key, default in DEFAULTS.items():
        value = (raw or {}).get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            out[key] = value
    return out


@dataclass(frozen=True)
class Check:
    """Проверка одной группы: мера, вопрос, точка отсчёта, сторона
    эффекта (−1 — меньше опоры, +1 — больше, 0 — в любую), семья."""

    key: str
    question: str
    title: str
    basis: str          # «случай» или «сам участник»
    against: str        # что такое точка отсчёта, словами
    transform: str      # log — ln x; minus1 — x − 1; plain — x
    effect: int
    main: bool
    exploratory: bool
    gaze: bool
    yes: str            # слова «установлено»


CHECKS = (
    Check("order.route_shelf", "В1", "Маршрут по полке к случайному "
          "порядку тех же книг", "случай", "1 — случайный порядок",
          "log", -1, True, True, False,
          "маршрут по полке короче случайного: книги обходят по порядку"),
    Check("learn.choice_slope", "В2", "Наклон времени выбора без первого "
          "похода (Тейл — Сен, логарифмы)", "сам участник",
          "0 — выбор не ускоряется", "plain", -1, True, False, False,
          "выбор книги ускоряется по ходу сессии"),
    Check("search.H_t", "В3", "Энтропия переходов взгляда в поиске к "
          "случайному уровню", "случай", "1 — случайный взгляд",
          "minus1", -1, True, False, True,
          "взгляд при выборе книги упорядоченнее случайного"),
    Check("learn.choice_thirds", "В2", "Выбор: последняя треть походов "
          "против первой (без первого похода), ln отношения",
          "сам участник", "0 — без изменений", "plain", -1, False, False,
          False, "к концу сессии книгу выбирают быстрее"),
    Check("search.K", "В3", "Коэффициент K в поиске (меньше 0 — обзорный "
          "взгляд, больше — сосредоточенный)", "случай",
          "0 — ни обзорный, ни сосредоточенный", "plain", 0, False, False,
          True, "режим взгляда в поиске отличается от среднего"),
    Check("gaze.read_vs_search", "В3", "Фиксации при чтении против "
          "выбора книги, ln отношения длительностей", "сам участник",
          "0 — одинаковы", "log", 1, False, True, True,
          "при чтении фиксации длиннее, чем при выборе книги: режим "
          "«где» сменяется режимом «что»"),
    Check("portrait.cat_return_ratio", "В4", "Возвраты в категории: было "
          "к ожидаемому без памяти", "случай", "1 — без памяти",
          "minus1", -1, False, False, True,
          "в уже осмотренные категории возвращаются реже, чем без памяти"),
    Check("learn.repeat_vs_first", "В4", "Выбор книги повторно против "
          "первого раза, ln отношения", "сам участник", "0 — одинаково",
          "plain", -1, False, False, False,
          "к уже открытой книге путь короче, чем к новой"),
    Check("blinks.change", "В5", "Моргания: конец сессии против начала, "
          "ln отношения частот третей", "сам участник",
          "0 — без изменений", "plain", 1, False, True, False,
          "к концу сессии моргают чаще: утомление"),
)

# Описание группы — числа без проверки.
DESCRIBE = (
    ("learn.entry_s", "Вход в интерфейс — первый поход", "с"),
    ("learn.after_first_s", "Выбор книги после первого похода, медиана",
     "с"),
    ("actions.time_to_choice", "Время до выбора книги, все походы", "с"),
    ("order.adjacent_share", "Переходы к соседней книге полки", "доля"),
    ("order.cat_switches", "Смен категории за обход", "раз"),
    ("order.books", "Книг открыто", "книг"),
    ("clt.ecl", "ECL — нагрузка от интерфейса", "1–7"),
    ("clt.raw_tlx", "Raw TLX", "0–100"),
    ("clt.raw_tlx5", "Raw TLX без пункта «успешность» (АО7)", "0–100"),
    ("clt.icl", "ICL — сложность материала", "1–7"),
    ("clt.gcl", "GCL — полезная нагрузка", "1–7"),
    ("clt.tlx.physical", "TLX: физические усилия", "0–100"),
    ("orient.1", "«Я быстро находил нужную книгу»", "1–7"),
    ("orient.2", "«К концу помнил, где стоят книги»", "1–7"),
    ("blinks.per_min", "Моргания в минуту видимого лица", "в мин"),
    ("share.search", "Доля изучения: взгляд на полке и карте", "доля"),
    ("share.reading", "Доля изучения: взгляд на чтении", "доля"),
    ("search.path", "Путь взгляда до книги, медиана", "°"),
    ("search.straight", "Прямота похода (1 — прямо)", "доля"),
    ("search.fix_ms", "Фиксация при выборе, медиана", "мс"),
    ("reading.fix_ms", "Фиксация при чтении, медиана", "мс"),
    ("portrait.lookbacks_per_min", "Взгляды назад при чтении",
     "в мин чтения"),
    ("portrait.page_backs_per_min", "Возвраты на страницу назад "
     "(с задержкой, BUG-74)", "в мин чтения"),
    ("nav.rewinds", "Перемотки книги назад (BUG-74)", "раз"),
    ("nav.opened_mid", "Книга открылась не с начала", "раз"),
)

# Связи самооценки с глазодвигательными признаками — разведка (В5).
LINKS = (
    ("clt.raw_tlx5", "reading.fix_ms"),
    ("clt.raw_tlx5", "portrait.lookbacks_per_min"),
    ("clt.raw_tlx5", "blinks.per_min"),
    ("clt.tlx.physical", "blinks.change"),
    ("clt.ecl", "search.H_t"),
    ("clt.ecl", "actions.time_to_choice"),
)
TITLE = {key: title for key, title, _ in DESCRIBE}
TITLE.update({c.key: c.title for c in CHECKS})

# Чего эти данные не скажут — независимо от чисел.
CANNOT = (
    "Что «Галактика» лучше полки — или наоборот: у каждого участника был "
    "один интерфейс, и сравнения «с картой и без» внутри человека нет; "
    "группы полки и карты — разные люди, а часто и разные ПК (АО5: новых "
    "сессий с перекрёстным порядком не будет).",
    "Что и сколько запомнилось из прочитанного: письменный бланк "
    "формальный, баллов по вопросам нет (12.10.2026, 19:57); самооценка "
    "«помнил, где стоят» — самоотчёт, а не мера памяти.",
    "Долгое влияние раскладки — лёгкость поиска, возвращение к изучению, "
    "запоминание расположения, путаница тем (Д1–Д7 предрегистрации): у "
    "каждого участника одна сессия.",
    "Что происходило в мозге: о гиппокампе, ретроспленальной коре и "
    "режимах внимания эти записи говорят только через поведенческие и "
    "глазодвигательные маркеры с известной связью (уровни "
    "доказательности — «Анализ ветви II — связь с физиологией "
    "запоминания»).",
)


def group_of(e: dict) -> str | None:
    """Интерфейс, которым участник выбирал книги (АО15)."""
    mode = e.get("search_mode")
    if mode == MODE_SHELF:
        return SHELF
    if mode == MODE_MAP:
        return GALAXY
    if mode == MODE_MIXED:
        return MIXED
    return None


def value(e: dict, key: str):
    """Значение меры у записи: новые меры шага 43 и всё, что знает
    `compare.value`."""
    if e.get("status") != "ok":
        return None
    if key.startswith("order."):
        return (e.get("order_measures") or {}).get(key)
    if key.startswith("blinks."):
        return (e.get("blinks_measures") or {}).get(key)
    if key == "gaze.read_vs_search":
        g = e.get("gaze_measures") or {}
        read, search = g.get("reading.fix_ms"), g.get("search.fix_ms")
        return read / search if read and search else None
    if key in ("orient.1", "orient.2"):
        return prereg.answer(e, key)
    if key.startswith("nav."):
        return (e.get("reading_nav") or {}).get(key[4:])
    if key == "clt.raw_tlx5":
        return (e.get("test") or {}).get("measures", {}).get(key)
    return compare.value(e, key)


def deviation(check: Check, x) -> float | None:
    if x is None:
        return None
    x = float(x)
    if check.transform == "log":
        return math.log(x) if x > 0 else None
    if check.transform == "minus1":
        return x - 1.0
    return x


def _gaze_key(key: str) -> bool:
    m = compare.BY_KEY.get(key)
    if m is not None:
        return m.gaze
    return key.startswith(("search.", "reading.", "all.", "share.",
                           "gaze."))


def _toward(check: Check, median: float | None) -> bool:
    if median is None:
        return False
    if check.effect < 0:
        return median < 0
    if check.effect > 0:
        return median > 0
    return median != 0


def _rows(entries, members: set[int], key: str, weight) -> list[tuple]:
    out = []
    for e in entries:
        if id(e) not in members:
            continue
        x = value(e, key)
        if x is None:
            continue
        w = weight(e)
        if w > 0:
            out.append((x, w, e))
    return out


def check_once(check: Check, rows: list[tuple], seed: int, sc: dict,
               full: bool) -> dict:
    """Одна проверка в одном сценарии: n, сколько в сторону эффекта, p;
    с [full] — ещё медиана с интервалом, среднее и биномиальный p."""
    ds, ws, kept = [], [], []
    for x, w, e in rows:
        d = deviation(check, x)
        if d is None:
            continue
        ds.append(d)
        ws.append(w)
        kept.append((x, w, e, d))
    n = len(ds)
    out = {"n": n, "p": None, "median": None, "toward": None}
    if n == 0:
        return out
    out["median"] = stats.weighted_median(ds, ws)
    side = check.effect if check.effect else (
        1 if (out["median"] or 0) >= 0 else -1)
    out["toward"] = sum(1 for d in ds if d * side > 0)
    out["p"] = stats.sign_flip_p(ds, ws, seed, int(sc["repeats"]))
    if full:
        out["mean"] = stats.weighted_mean(ds, ws)
        out["ci"] = stats.median_interval(ds, ws, seed,
                                          int(sc["bootstrap"]))
        out["binom_p"] = stats.binom_p(out["toward"], n)
        out["n_eff"] = stats.n_eff(ws)
        out["values"] = [{"participant": e.get("participant"),
                          "colour": e.get("colour"),
                          "stratum": e.get("stratum"), "x": float(x),
                          "d": d, "w": w} for x, w, e, d in kept]
    return out


def _adjust(results: list[dict], checks) -> None:
    """p с поправкой: Холм у главных, Бенджамини — Хохберг у
    разведочных — в каждом сценарии отдельно."""
    for main in (True, False):
        idx = [i for i, c in enumerate(checks) if c.main == main]
        ps = [results[i]["p"] for i in idx]
        adj = stats.holm(ps) if main else stats.bh(ps)
        for i, p in zip(idx, adj):
            results[i]["p_adj"] = p


def run(entries: list[dict], cfg: dict, *, fingerprint: str,
        no_filter: bool, series: str | None) -> dict:
    """Весь анализ по интерфейсу."""
    sc = settings(cfg.get("single"))
    alpha = float(cfg["alpha"])
    n_min = int(sc["n_min"])
    groups: dict[str, list[dict]] = {SHELF: [], GALAXY: [], MIXED: []}
    for e in entries:
        g = group_of(e) if e.get("status") == "ok" else None
        e["interface"] = g
        if g:
            groups[g].append(e)
    shelf = {id(e) for e in groups[SHELF]}

    def weight_of(scenario, gaze):
        return lambda e: compare.scenario_weight(e, scenario, cfg,
                                                 no_filter, series, gaze)

    scenarios = [s for s, _ in compare.SCENARIOS]
    by_scenario: dict[str, list[dict]] = {}
    for s in scenarios:
        res = []
        for c in CHECKS:
            rows = _rows(entries, shelf, c.key, weight_of(s, c.gaze))
            res.append(check_once(c, rows, stats.seed_for(
                fingerprint, "single", s, c.key), sc, s == "S0"))
        _adjust(res, CHECKS)
        by_scenario[s] = res
    table = []
    for i, c in enumerate(CHECKS):
        own = by_scenario["S0"][i]
        holds = {}
        for s in scenarios:
            r = by_scenario[s][i]
            enough = r["n"] >= n_min
            holds[s] = {"n": r["n"], "median": r["median"],
                        "p_adj": r.get("p_adj"),
                        "holds": (enough and r.get("p_adj") is not None
                                  and r["p_adj"] < alpha
                                  and _toward(c, r["median"])
                                  and (c.effect != 0 or
                                       (r["median"] or 0) * (
                                           own["median"] or 0) > 0))
                        if enough else None}
        table.append(dict(own, check=c, scenarios=holds,
                          words=_words(c, own, holds, n_min, alpha)))
    describe = []
    for key, title, unit in DESCRIBE:
        gaze = _gaze_key(key)
        rows = _rows(entries, shelf, key, weight_of("S0", gaze))
        xs = [float(x) for x, _, _ in rows]
        ws = [w for _, w, _ in rows]
        d = stats.describe(xs, ws) if xs else {"n": 0}
        if xs and len(xs) >= 2:
            d["q"] = (_quantile(xs, ws, 0.25), _quantile(xs, ws, 0.75))
        describe.append({"key": key, "title": title, "unit": unit, **d})
    links = []
    for a, b in LINKS:
        w_a = weight_of("S0", _gaze_key(a) or _gaze_key(b))
        pairs = [(value(e, a), value(e, b), w_a(e))
                 for e in groups[SHELF]]
        pairs = [(x, y, w) for x, y, w in pairs
                 if x is not None and y is not None and w > 0]
        rho = stats.spearman([p[0] for p in pairs], [p[1] for p in pairs],
                             [p[2] for p in pairs]) if len(pairs) >= 5 \
            else None
        links.append({"a": a, "b": b, "n": len(pairs), "rho": rho})
    reds = _reds(entries, groups, cfg, no_filter, series, fingerprint, sc,
                 alpha, n_min)

    def out_of(e):
        return compare.hard_out(e, cfg, no_filter, series)

    first = prereg.evaluate(entries, cfg, value, out_of)
    return {"groups": {k: [e.get("participant") for e in v]
                       for k, v in groups.items()},
            "table": table, "describe": describe, "links": links,
            "reds": reds, "prereg": first, "n_min": n_min, "alpha": alpha,
            "summary": summary(table, describe, first, n_min)}


def _quantile(xs, ws, q):
    from .average import wquantile
    return wquantile(xs, ws, q)


def _words(c: Check, own: dict, holds: dict, n_min: int,
           alpha: float) -> str:
    n = own["n"]
    if n == 0:
        return "нет данных"
    if n < n_min:
        return f"не доказано: участников с мерой {n} — меньше {n_min}"
    p = own.get("p_adj")
    if p is None or p >= alpha:
        return "не доказано: p с поправкой " + (
            f"{p:.3f}".replace(".", ",") if p is not None else "—")
    if not _toward(c, own["median"]):
        return "не доказано: медиана не в сторону эффекта"
    ci = own.get("ci")
    if ci is None or (c.effect < 0 and ci[1] >= 0) or \
            (c.effect > 0 and ci[0] <= 0) or \
            (c.effect == 0 and ci[0] <= 0 <= ci[1]):
        return "не доказано: интервал медианы накрывает точку отсчёта"
    broken = [s for s, h in holds.items() if h["holds"] is False]
    if broken:
        return "не доказано: не держится в " + ", ".join(broken)
    return "установлено: " + c.yes


def _reds(entries, groups, cfg, no_filter, series, fingerprint, sc,
          alpha, n_min) -> dict:
    """АО3: как отсеивались недостоверные результаты — 🔴 примером: их
    ответы на шкалу лжи, их числа и что стало бы с главными вопросами,
    если бы их оставили (вес 1, остальные — как в S0)."""
    reds = [e for e in entries if e.get("status") == "ok"
            and e.get("colour") == honesty.RED]
    shelf = {id(e) for e in groups[SHELF]}
    people = []
    for e in reds:
        lie = (e.get("test") or {}).get("lie") or {}
        people.append({
            "participant": e.get("participant"),
            "interface": e.get("interface"),
            "stratum": e.get("stratum"),
            "lie": {k: (lie.get(k) or {}).get("value")
                    for k in honesty.LIE_ITEMS},
            "reason": e.get("colour_reason"),
            "values": {c.key: value(e, c.key) for c in CHECKS
                       if c.main}})

    def kept(gaze):
        def w(e):
            if e.get("colour") == honesty.RED:
                if compare.hard_out(e, cfg, no_filter, series):
                    return 0.0
                if gaze:
                    g = e.get("gaze") or {}
                    if not (g.get("present") and g.get("included")):
                        return 0.0
                return 1.0
            return compare.scenario_weight(e, "S0", cfg, no_filter, series,
                                           gaze)
        return w

    mains = [c for c in CHECKS if c.main]
    res = []
    for c in mains:
        rows = _rows(entries, shelf, c.key, kept(c.gaze))
        res.append(check_once(c, rows, stats.seed_for(
            fingerprint, "single", "S0+red", c.key), sc, False))
    _adjust(res, mains)
    return {"people": people,
            "with_reds": [{"key": c.key, "question": c.question,
                           "n": r["n"], "median": r["median"],
                           "toward": r["toward"], "p_adj": r.get("p_adj")}
                          for c, r in zip(mains, res)]}


def summary(table: list[dict], describe: list[dict], first: dict,
            n_min: int) -> dict:
    """Итог тремя списками: установлено, описано, этими данными не
    сказать."""
    established, described = [], []
    for r in table:
        c = r["check"]
        line = {"question": c.question, "title": c.title,
                "exploratory": c.exploratory, "main": c.main,
                "words": r["words"], "n": r["n"], "toward": r["toward"],
                "median": r["median"], "ci": r.get("ci"),
                "p_adj": r.get("p_adj")}
        (established if r["words"].startswith("установлено")
         else described).append(line)
    v = first["verdict"]
    cannot = list(CANNOT)
    line = {"question": "Г", "title": "Мгновенное влияние «Галактики» "
            "по предрегистрации", "exploratory": False, "main": True,
            "n": v["n"]}
    if v["word"] == prereg.CONFIRMED:
        established.append(dict(line, words=(
            f"ожидания подтверждены: «за» хотя бы в трёх из четырёх "
            f"главных у {v['for']} из {v['n']} участников вердикта")))
    elif v["word"] == prereg.REFUTED:
        established.append(dict(line, words=(
            f"ожидания опровергнуты: «против» хотя бы в трёх из четырёх "
            f"главных у {v['against']} из {v['n']} участников вердикта")))
    elif v["word"] == prereg.EMPTY:
        cannot.append("Мгновенное влияние «Галактики» по предрегистрации: "
                      "записей первого контакта нет.")
    else:
        described.append(dict(line, words=v["word"]))
    return {"established": established, "described": described,
            "cannot": cannot,
            "numbers": [d for d in describe if d.get("n")]}
