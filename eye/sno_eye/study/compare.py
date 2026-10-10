"""Шаг 9 — сравнение ветвей по всем мерам, устойчивость, слова
(SNO-ALG-RES-05; отбор и вес — SNO-ALG-RES-01).

Откуда данные: записи `study.collect` — паспорт, цвет искренности и вес
(`study.honesty`), эталон, взгляд, шкалы теста (`study.clt`), меры
действий (`study.actions`); числа-пороги — раздел `study` в
`eye/thresholds.json`.
Технология: счёт — `study.stats` (numpy); здесь — кто с каким весом идёт
в каждую меру, семьи мер и поправка, сценарии отбора и слова.
Метод: SNO-ALG-RES-05 — шаги 5–8: семьи мер с поправкой Холма внутри
семьи, вывод словами только при n_eff ≥ `study.n_eff_min` в обеих
ветвях, по одной статистике — δ (интервал не накрывает ноль и p по
Холму < `study.alpha`); шесть сценариев отбора для главных мер; второе
сравнение — по способу поиска (разведка).
Вход → выход: записи → строки `сравнение.csv` и `устойчивость.csv`,
выводы словами, оговорки над результатом.
"""

from __future__ import annotations

from dataclasses import dataclass

from . import honesty, stats
from .collect import ETALON_NOT_RESET, ETALON_YES

# --- меры ----------------------------------------------------------------


@dataclass(frozen=True)
class Measure:
    """Мера сравнения: ключ, слова, семья, что значит «больше»."""

    key: str
    title: str
    family: str
    unit: str
    more: str
    gaze: bool = False
    pending: str | None = None   # мера ещё не считается — где появится


FAMILIES = {
    "0": "Главные меры (АК4)",
    "А": "Нагрузка",
    "Б": "Действия",
    "В": "Беспорядочность взгляда",
    "Г": "Средний взгляд и научение",
}

MEASURES = (
    Measure("search.H_t", "Энтропия переходов взгляда в поиске", "В",
            "доля случайного", "взгляд в поиске беспорядочнее", gaze=True),
    Measure("clt.ecl", "ECL — нагрузка от интерфейса", "А", "1–7",
            "интерфейс мешал больше"),
    Measure("actions.time_to_choice", "Время до выбора книги", "Б", "с",
            "дольше искали книгу"),
    Measure("clt.raw_tlx", "Raw TLX", "А", "0–100", "больше нагрузки"),
    Measure("clt.tlx.mental", "TLX: умственная работа", "А", "0–100",
            "больше нагрузки"),
    Measure("clt.tlx.physical", "TLX: физические усилия", "А", "0–100",
            "больше нагрузки"),
    Measure("clt.tlx.temporal", "TLX: спешка", "А", "0–100",
            "больше нагрузки"),
    Measure("clt.tlx.performance", "TLX: успешность", "А", "0–100",
            "хуже справился"),
    Measure("clt.tlx.effort", "TLX: старание", "А", "0–100",
            "больше нагрузки"),
    Measure("clt.tlx.frustration", "TLX: раздражение", "А", "0–100",
            "больше нагрузки"),
    Measure("clt.icl", "ICL — внутренняя нагрузка", "А", "1–7",
            "материал труднее"),
    Measure("clt.gcl", "GCL — полезная нагрузка", "А", "1–7",
            "больше старания понять"),
    Measure("clt.orient", "Ориентация на полке", "А", "1–7",
            "ориентировался лучше"),
    Measure("actions.opens_per_min", "Открытий книг в минуту", "Б",
            "в мин", "чаще открывали книги"),
    Measure("actions.books_per_min", "Новых книг в минуту", "Б", "в мин",
            "быстрее открывали новые книги"),
    Measure("actions.repeat_share", "Доля повторных открытий", "Б", "доля",
            "чаще возвращались к открытым"),
    Measure("actions.via_map", "Доля открытий через карту", "Б", "доля",
            "чаще открывали с карты"),
    Measure("actions.via_found", "Доля открытий из найденного по названию",
            "Б", "доля", "чаще открывали поиском"),
    Measure("actions.card_time", "Время в карточке книги", "Б", "с",
            "дольше в карточке"),
    Measure("actions.search_trip_share", "Доля походов с поиском по "
            "названию", "Б", "доля", "чаще искали по названию"),
    Measure("actions.last_search_trip", "Последний поход с поиском, доля "
            "пути", "Б", "доля", "дольше не переходили на память"),
    Measure("actions.book_search_per_min", "Поиск по книге, эпизодов в "
            "минуту", "Б", "в мин", "чаще искали в книге"),
    Measure("actions.map_views_per_trip", "Карта: приближений и сдвигов на "
            "поход", "Б", "раз", "больше двигали карту"),
    Measure("actions.cards_unread_share", "Карта: доля карточек без "
            "чтения", "Б", "доля", "чаще открывали карточку зря"),
    Measure("actions.pages_per_min", "Страниц показано в минуту", "Б",
            "в мин", "быстрее листали"),
    Measure("actions.read_per_book", "Чтение на книгу, медиана", "Б", "с",
            "дольше читали книгу"),
    Measure("actions.away_per_min", "Отлучек в минуту", "Б", "в мин",
            "чаще уходили из приложения"),
    Measure("actions.away_share", "Отлучки, доля времени изучения", "Б",
            "доля", "дольше вне приложения"),
    Measure("actions.taps_per_min", "Касаний в минуту", "Б", "в мин",
            "больше касаний"),
    Measure("actions.empty_tap_share", "Доля пустых касаний", "Б", "доля",
            "беспорядочнее рука"),
) + tuple(
    # Беспорядочность взгляда (SNO-ALG-RES-03, шаг 37) — по фазам.
    Measure(f"{phase}.{key}", f"{title} — {words}", "В", unit, more,
            gaze=True)
    for phase, words, keys in (
        ("search", "поиск", (
            ("H_s", "Энтропия распределения взгляда", "доля случайного",
             "внимание размазано"),
            ("K", "Коэффициент K", "z", "сосредоточеннее (K < 0 — "
             "обзорный режим)"),
            ("path", "Путь взгляда до книги, медиана", "°",
             "длиннее путь — беспорядочнее"),
            ("straight", "Прямота похода, медиана", "доля",
             "прямее к цели"),
            ("returns", "Возвраты в клетку, медиана", "доля",
             "чаще возвращался — искал вслепую"),
            ("nni_dev", "Кучность |1 − NNI|", "доля",
             "дальше от случайного разброса — упорядоченнее"),
            ("fix_ms", "Длительность фиксации, медиана", "мс",
             "дольше фиксации"),
            ("sacc_deg", "Амплитуда саккады, медиана", "°",
             "длиннее скачки"),
            ("fix_rate", "Фиксаций в секунду", "в с",
             "чаще фиксации"))),
        ("reading", "чтение", (
            ("H_t", "Энтропия переходов", "доля случайного",
             "беспорядочнее"),
            ("H_s", "Энтропия распределения", "доля случайного",
             "внимание размазано"),
            ("K", "Коэффициент K", "z", "сосредоточеннее"),
            ("fix_ms", "Длительность фиксации, медиана", "мс",
             "дольше фиксации"),
            ("sacc_deg", "Амплитуда саккады, медиана", "°",
             "длиннее скачки"),
            ("fix_rate", "Фиксаций в секунду", "в с", "чаще фиксации"))),
        ("all", "всё изучение", (
            ("H_t", "Энтропия переходов", "доля случайного",
             "беспорядочнее"),
            ("H_s", "Энтропия распределения", "доля случайного",
             "внимание размазано"),
            ("K", "Коэффициент K", "z", "сосредоточеннее"))),
    )
    for key, title, unit, more in keys
) + (
    # Средний взгляд и научение (SNO-ALG-RES-04, шаг 37).
    Measure("share.reading", "Доля изучения: взгляд на чтении", "Г",
            "доля", "больше времени на чтении", gaze=True),
    Measure("share.search", "Доля изучения: взгляд на полке и карте", "Г",
            "доля", "больше времени на поиске", gaze=True),
    Measure("share.off", "Доля изучения: вне экрана и вне приложения",
            "Г", "доля", "дольше мимо экрана", gaze=True),
    Measure("learn.choice_slope", "Научение: наклон времени до выбора",
            "Г", "b", "медленнее ускорялись (b < 0 — ускорение)"),
    Measure("learn.path_slope", "Научение: наклон пути взгляда", "Г",
            "b", "медленнее укорачивался путь (b < 0 — короче)",
            gaze=True),
)

BY_KEY = {m.key: m for m in MEASURES}

# Главные меры по умолчанию (АК4); настоящие — `study.primary`.
PRIMARY_KEYS = ("search.H_t", "clt.ecl", "actions.time_to_choice")


def family_of(m: Measure, cfg: dict) -> str:
    """Семья меры: главная (АК4, `study.primary`) — «0», иначе своя."""
    return "0" if m.key in tuple(cfg.get("primary") or PRIMARY_KEYS) \
        else m.family


def primary(cfg: dict) -> list[Measure]:
    keys = tuple(cfg.get("primary") or PRIMARY_KEYS)
    return [BY_KEY[k] for k in keys if k in BY_KEY]

# --- сценарии отбора (SNO-ALG-RES-05, шаг 7) ---------------------------

SCENARIOS = (
    ("S0", "основной"),
    ("S1", "🟡 и ⚪ с весом 1"),
    ("S2", "без 🟡 и ⚪"),
    ("S3", "🟡, ⚪ и 🔴 с весом 1"),
    ("S4", "взгляд хуже 3° — с весом"),
    ("S5", "только записи с эталона"),
)

# Сравнения: ключ, слова, что сравнивается.
BRANCH = "ветвь"
MODE_ALL = "способ поиска — все"
MODE_II = "способ поиска — ветвь II"


def hard_out(e: dict, cfg: dict, no_filter: bool,
             series: str | None) -> list[str]:
    """Почему запись вне статистики целиком — при любом сценарии.

    Проверочный прогон (`--no-filter`) оставляет все годные архивы —
    кроме копий и чужой серии, названной ключом."""
    out = []
    if e["status"] != "ok":
        return [e.get("reason") or "архив не годен"]
    if series and e.get("series") != series:
        out.append(f"другая серия: {e.get('series') or 'проверочная'}")
    # Копия и повтор — вне и в проверочном прогоне: один человек — одна
    # строка.
    duplicate = e.get("duplicate")
    if duplicate:
        out.append(duplicate)
    if no_filter:
        return out
    if not e.get("series"):
        out.append("проверочная сборка, а не сборка исследования")
    minimum = float(cfg["min_study_min"])
    if (e.get("study_s") or 0) < minimum * 60:
        out.append(f"изучение {e['study_s'] / 60:.1f} мин — короче "
                   f"{minimum:g} мин".replace(".", ","))
    return out


def admit(entries: list[dict], cfg: dict, no_filter: bool,
          series: str | None) -> None:
    """Цвет, вес и причины для каждой записи — основной сценарий S0.

    Пишет в запись: `colour`, `colour_reason`, `weight`, `out` (почему
    вне статистики), `in_stats`, `etalon_out`."""
    weights = {honesty.GREEN: 1.0,
               honesty.YELLOW: float(cfg["yellow_weight"]),
               honesty.UNKNOWN: float(cfg["unknown_weight"]),
               honesty.RED: 0.0}
    for e in entries:
        out = hard_out(e, cfg, no_filter, series)
        if e["status"] == "ok":
            flags = {item: e["test"]["lie"].get(item, {}).get("flag")
                     for item in honesty.LIE_ITEMS}
            colour, why = honesty.colour(
                flags, complete=e["test"]["state"] == "пройден")
        else:
            colour, why = None, None
        e["colour"], e["colour_reason"] = colour, why
        e["etalon_out"] = _etalon_out(e, cfg)
        if no_filter:
            weight = 1.0 if not out else 0.0
        else:
            weight = honesty.weight(colour, weights) if colour else 0.0
            if colour == honesty.RED:
                out.append("🔴 провалены оба пункта шкалы лжи — участник "
                           "целиком вне статистики")
            elif colour and weight <= 0:
                out.append(f"вес цвета «{honesty.SHORT[colour]}» — 0 "
                           "(study.yellow_weight или study.unknown_weight)")
            if e["etalon_out"]:
                out.append(e["etalon_out"])
            if out:
                weight = 0.0
        e["out"] = out
        e["weight"] = weight
        e["in_stats"] = weight > 0


def _etalon_out(e: dict, cfg: dict) -> str | None:
    """Эталон по АК10: (а) — в статистику с оговоркой; (б) — «не
    сброшено» вне, «сброшено, но отличается» с оговоркой; (в) — все не
    с эталона вне."""
    word = e.get("etalon")
    policy = str(cfg.get("etalon", "a"))
    if word is None or word == ETALON_YES:
        return None
    if policy == "c":
        return f"запись не с эталона ({word}) — АК10 (в)"
    if policy == "b" and word == ETALON_NOT_RESET:
        return "полку не сбросили к эталону — АК10 (б)"
    return None


def scenario_weight(e: dict, scenario: str, cfg: dict, no_filter: bool,
                    series: str | None, gaze: bool) -> float:
    """Вес записи в мере сценария [scenario].

    | сценарий | 🟡 и ⚪   | 🔴     | взгляд хуже 3° | не с эталона |
    |----------|----------|--------|----------------|--------------|
    | S0       | вес АК1  | вне    | вне            | как решит АК10 |
    | S1       | вес 1    | вне    | вне            | как в S0     |
    | S2       | вне      | вне    | вне            | как в S0     |
    | S3       | вес 1    | вес 1  | вне            | как в S0     |
    | S4       | вес АК1  | вне    | с весом        | как в S0     |
    | S5       | вес АК1  | вне    | вне            | вне          |

    Колонка «взгляд» касается только мер взгляда ([gaze]): тест и
    действия сессия с плохой точностью отдаёт всегда."""
    if hard_out(e, cfg, no_filter, series):
        return 0.0
    colour = e.get("colour")
    if no_filter and scenario == "S0":
        w = 1.0
    else:
        yellow = float(cfg["yellow_weight"])
        unknown = float(cfg["unknown_weight"])
        table = {
            "S0": {honesty.YELLOW: yellow, honesty.UNKNOWN: unknown},
            "S1": {honesty.YELLOW: 1.0, honesty.UNKNOWN: 1.0},
            "S2": {honesty.YELLOW: 0.0, honesty.UNKNOWN: 0.0},
            "S3": {honesty.YELLOW: 1.0, honesty.UNKNOWN: 1.0,
                   honesty.RED: 1.0},
            "S4": {honesty.YELLOW: yellow, honesty.UNKNOWN: unknown},
            "S5": {honesty.YELLOW: yellow, honesty.UNKNOWN: unknown},
        }[scenario]
        w = 1.0 if colour == honesty.GREEN else table.get(colour, 0.0)
        if scenario == "S5" and e.get("etalon") != ETALON_YES:
            w = 0.0
        elif e.get("etalon_out"):
            w = 0.0
    if gaze:
        g = e.get("gaze") or {}
        if not g.get("present"):
            w = 0.0
        elif not g.get("included") and not (
                scenario == "S4" or (no_filter and scenario == "S0")):
            w = 0.0
    return w


def value(e: dict, key: str):
    """Значение меры [key] у записи: тест, действия, научение или
    взгляд (`gaze_measures` — шаг 37: беспорядочность и доли)."""
    if e.get("status") != "ok":
        return None
    if key.startswith("clt."):
        if e.get("clt_excluded"):
            return None
        return e["test"]["measures"].get(key)
    if key.startswith("actions."):
        return e["actions"].get(key)
    if key.startswith("learn."):
        return (e.get("learn") or {}).get(key)
    return (e.get("gaze_measures") or {}).get(key)


# --- сравнение ------------------------------------------------------------

def _rows(entries, measure: Measure, scenario: str, cfg: dict,
          no_filter: bool, series: str | None, label) -> list[tuple]:
    rows = []
    for e in entries:
        x = value(e, measure.key)
        if x is None:
            continue
        w = scenario_weight(e, scenario, cfg, no_filter, series,
                            measure.gaze)
        group = label(e)
        if w > 0 and group is not None:
            # (значение, вес, группа, слой) — для счёта; цвет и код —
            # для формы точки на рисунках.
            rows.append((float(x), w, group, e["stratum"], e.get("colour"),
                         str(e.get("participant"))))
    return rows


COMPARISONS = (
    (BRANCH, ("II", "I"), lambda e: e.get("branch")),
    (MODE_ALL, ("картой", "полкой"), lambda e: e.get("search_mode")),
    (MODE_II, ("картой", "полкой"),
     lambda e: e.get("search_mode") if e.get("branch") == "II" else None),
)


def words(res: stats.Result, p_holm: float | None, alpha: float,
          groups: tuple[str, str]) -> str:
    """Вывод словами — по одной статистике, δ (шаг 6)."""
    second, first = groups
    if not res.enough:
        return "мало данных — только описание"
    if res.delta is None or res.ci is None or p_holm is None:
        return "мало данных — только описание"
    lo, hi = res.ci
    who = f"в ветви {second}" if second in ("I", "II") else f"«{second}»"
    if p_holm < alpha and (lo > 0 or hi < 0):
        if res.delta > 0:
            return f"{who} больше"
        return f"{who} меньше"
    return "разницы не видно"


def run(entries: list[dict], cfg: dict, *, fingerprint: str,
        no_filter: bool, series: str | None) -> dict:
    """Все сравнения, устойчивость и связи мер."""
    rep = int(cfg["bootstrap"])
    perm = int(cfg["permutations"])
    exact = int(cfg["exact_limit"])
    neff = float(cfg["n_eff_min"])
    alpha = float(cfg["alpha"])
    table = []
    for name, groups, label in COMPARISONS:
        part = []
        for m in MEASURES:
            row = {"comparison": name, "groups": groups, "measure": m,
                   "family": family_of(m, cfg), "pending": m.pending}
            if m.pending:
                row["result"] = stats.Result()
            else:
                rows = _rows(entries, m, "S0", cfg, no_filter, series,
                             label)
                row["result"] = stats.compare(
                    rows, seed=stats.seed_for(fingerprint, name, "S0",
                                              m.key),
                    bootstrap_repeats=rep, permutation_repeats=perm,
                    exact_limit=exact, n_eff_min=neff, groups=groups)
                row["means_ci"] = {
                    g: stats.mean_interval(
                        [r[0] for r in rows if r[2] == g],
                        [r[1] for r in rows if r[2] == g],
                        stats.seed_for(fingerprint, name, "mean", m.key, g),
                        rep)
                    for g in groups}
                row["points"] = rows
            part.append(row)
        # Поправка Холма внутри семьи. Главная семья — с недостающей
        # мерой как p = 1: главная мера, у которой мало данных, остаётся
        # в поправке, и та идёт на все три названные меры (АК4). Выбор
        # наш: строже, чем выбросить её.
        for family in FAMILIES:
            members = [r for r in part if r["family"] == family]
            if not members:
                continue
            ps = [r["result"].p if not r["pending"] else None
                  for r in members]
            adjusted = stats.holm(ps, missing_as_one=family == "0")
            for r, q in zip(members, adjusted):
                r["p_holm"] = q
        for r in part:
            r.setdefault("p_holm", None)
            r["words"] = "появится — " + r["pending"] if r["pending"] \
                else words(r["result"], r["p_holm"], alpha, groups)
            r["effect"] = stats.effect_words(r["result"].delta)
        table.extend(part)

    robust = []
    for m in primary(cfg):
        if m.pending:
            continue
        cases = []
        for code, title in SCENARIOS:
            rows = _rows(entries, m, code, cfg, no_filter, series,
                         lambda e: e.get("branch"))
            res = stats.compare(
                rows, seed=stats.seed_for(fingerprint, BRANCH, code, m.key),
                bootstrap_repeats=rep, permutation_repeats=perm,
                exact_limit=exact, n_eff_min=neff)
            cases.append({"scenario": code, "title": title, "result": res})
        robust.append({"measure": m, "cases": cases,
                       "verdict": stability(cases)})

    # Шум веб-камеры сам делает взгляд «беспорядочнее» (SNO-ALG-RES-03):
    # по каждой мере взгляда — ранговая связь с прецизионностью сессии
    # по участникам S0 обеих ветвей; |ρ| ≥ `study.noise_rho` — пометка
    # «чувствует шум». При десятке участников это пометка, а не защита.
    limit = float(cfg["noise_rho"])
    for r in table:
        m = r["measure"]
        if r["comparison"] != BRANCH or not m.gaze:
            continue
        xs, ys, ws = [], [], []
        for e in entries:
            x = value(e, m.key)
            prec = ((e.get("gaze_data") or {}).get("precision_deg"))
            w = scenario_weight(e, "S0", cfg, no_filter, series, True)
            if x is not None and prec is not None and w > 0:
                xs.append(float(x))
                ys.append(float(prec))
                ws.append(w)
        rho = stats.spearman(xs, ys, ws)
        r["noise_rho"] = rho
        r["noisy"] = rho is not None and abs(rho) >= limit

    links = []
    names = ("clt.ecl", "search.H_t", "actions.time_to_choice",
             "learn.choice_slope")
    pairs = [(a, b) for i, a in enumerate(names) for b in names[i + 1:]]
    for branch in ("I", "II"):
        for a, b in pairs:
            xs, ys, ws = [], [], []
            for e in entries:
                if e.get("branch") != branch:
                    continue
                va, vb = value(e, a), value(e, b)
                gaze = BY_KEY[a].gaze or BY_KEY[b].gaze
                w = scenario_weight(e, "S0", cfg, no_filter, series, gaze)
                if va is not None and vb is not None and w > 0:
                    xs.append(va)
                    ys.append(vb)
                    ws.append(w)
            links.append({"branch": branch, "a": a, "b": b, "n": len(xs),
                          "rho": stats.spearman(xs, ys, ws)})
    return {"table": table, "robust": robust, "links": links}


def stability(cases: list[dict]) -> str:
    """Устойчив ли вывод: во всех сценариях, где n_eff не меньше
    порога, у δ один знак и |δ| ≥ 0,147. Сценарий с малым n_eff
    помечен «мало данных» и в решение не идёт."""
    live = [c["result"] for c in cases if c["result"].enough
            and c["result"].delta is not None]
    if not live:
        return "мало данных"
    signs = {(d.delta > 0) - (d.delta < 0) for d in live}
    if len(signs) == 1 and 0 not in signs and \
            all(abs(d.delta) >= stats.EFFECT_STEPS[0][0] for d in live):
        return "устойчив"
    return "неустойчив"


def warnings(entries: list[dict], result: dict, no_filter: bool) -> list:
    """Оговорки над результатом: чего нет, что нельзя отделить."""
    out = []
    used = [e for e in entries if e.get("in_stats")]
    branches = {e.get("branch") for e in used}
    for b in ("I", "II"):
        if b not in branches:
            out.append(f"ветви {b} в наборе нет — сравнения ветвей нет")
    if branches >= {"I", "II"}:
        pooled = [r for r in result["table"]
                  if r["comparison"] == BRANCH and r["result"].pooled]
        if pooled:
            out.append("ветвь совпадает с ПК — ни на одном ПК не было "
                       "обеих ветвей: разницу ветвей нельзя отделить от "
                       "разницы камер")
    tags = {}
    for e in used:
        tags[e.get("series") or "проверочная"] = \
            tags.get(e.get("series") or "проверочная", 0) + 1
    if len(tags) > 1:
        out.append("в наборе несколько серий: " + ", ".join(
            f"{k} — {v}" for k, v in sorted(tags.items())))
    versions = {e["clt_version"] for e in used if e.get("clt_version")}
    if len(versions) > 1:
        out.append("в наборе разные версии сценария теста — шкалы "
                   "сравниваются внутри самой частой версии")
    if no_filter:
        out.insert(0, "проверочный прогон, не для выводов: все годные "
                   "архивы с весом 1 — и 🔴, и взгляд хуже 3°, и записи "
                   "не с эталона, и короткие")
    return out


def unify_scenarios(entries: list[dict]) -> None:
    """Разные версии сценария теста: шкалы сравниваются только внутри
    самой частой версии (SNO-ALG-RES-01, краевые случаи); у остальных
    шкалы пустые, с оговоркой."""
    counts: dict = {}
    for e in entries:
        if e.get("status") != "ok":
            continue
        test = e["test"]
        key = (test.get("scenario"), test.get("scenario_version"))
        e["clt_version"] = f"{key[0]} v{key[1]}" if key[0] else None
        if key[0]:
            counts[key] = counts.get(key, 0) + 1
    if len(counts) < 2:
        return
    main = max(sorted(counts, key=str), key=lambda k: counts[k])
    for e in entries:
        if e.get("status") != "ok":
            continue
        test = e["test"]
        key = (test.get("scenario"), test.get("scenario_version"))
        if key[0] and key != main:
            e["clt_excluded"] = True
            test["notes"].append(
                f"сценарий теста {key[0]} v{key[1]} — не самый частый в "
                "наборе: шкалы в сравнение не идут")
