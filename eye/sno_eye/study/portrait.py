"""Шаг 7а — портрет участника: энтропия по ходу сессии и сбор чисел
портрета (SNO-F-RES-07; SNO-ALG-RES-06; шаг 38).

Откуда данные: фиксации общим порогом `study.idt_deg`, клетки сетки
окна и ряды переходов — `study.disorder` (шаг 37) без изменений; походы
за книгой — `study.actions`; ход сессии, экраны и кадры с видами —
«Разбор записи» (`report.timeline`, `report.measures`); заходы,
возвраты и переходы между зонами — `study.dwell`; взгляд назад и
возвраты на страницу — `study.reading_back`.
Технология: numpy — матрица переходов окна (`bincount`), перемешанный
ряд пачкой розыгрышей (`Generator.permuted`), логарифм по основанию 2;
наклон — стандартная библиотека.
Метод:
* энтропия переходов окна — Krejtz K. и др. «Gaze transition entropy»,
  ACM TAP, 2015, 13(1):4; в скользящем окне — Ebeid I., Gwizdka J.
  «Real-time gaze transition entropy», ETRA 2018; окно — по числу
  переходов, а не по минутам: энтропия малой выборки занижена тем
  сильнее, чем переходов меньше (Paninski L., Neural Computation, 2003,
  15:1191), а при равном числе недобор у окон одного порядка;
* нормировка — делением на энтропию совершенно случайного взгляда при
  том же числе зон и переходов (`study.disorder.random_level`) и,
  справочно, на энтропию тех же переходов в перемешанном порядке;
* наклон по окнам — Тейла — Сена: Sen P. K. «Estimates of the
  regression coefficient based on Kendall's tau», JASA, 1968,
  63:1379 — медиана наклонов всех пар окон без общих переходов.
Вход → выход: фиксации и походы записи → окна энтропии трёх рядов,
заходы и возвраты, взгляд назад, лента сессии (`prepare`, когда архив
читается); все записи после отбора → числа участника `portrait.*` для
сравнения семьёй «Д. Портрет» (`finish`).

Портрет строится у каждого — и вне статистики, и у взгляда хуже 3°
(владелец просил меры **каждого** тестировщика); в сравнение числа
идут по прежним правилам отбора.
"""

from __future__ import annotations

import statistics
from collections import Counter

import numpy as np

from ..report.measures import MINUTE_GROUPS
from . import disorder, dwell, reading_back, stats
from .actions import SEARCH_SCREENS, _screen_time

# Пороги по умолчанию; настоящие — раздел `portrait` в
# `thresholds.json` (первые оценки, 11.10.2026).
DEFAULTS = {
    # Окно энтропии всей сессии и чтения и его шаг, в переходах.
    "window_transitions": 60,
    "window_step": 15,
    # Окно энтропии в поиске (пол H_t поиска) и его шаг.
    "search_window": 40,
    "search_step": 10,
    # Окно дольше — растянуто через паузу: линией не соединяется.
    "window_max_s": 180,
    # Розыгрышей перемешанного ряда для справочной нормировки.
    "shuffle_repeats": 200,
    # Корзина кривой поиска на Р16, секунд накопленного поиска.
    "search_bin_s": 30,
    # Просвет с одной зоной по обе стороны — в время захода.
    "bridge_ms": 150,
    # Взгляд назад: порог фиксаций чтения, наименьший скачок и длина,
    # фронт чтения, вторая колонка, промах листания.
    "reading_idt_deg": 3.0,
    "lookback_min_deg": 2.0,
    "lookback_min_ms": 300,
    "front_quantile": 0.8,
    "front_window": 10,
    "column_jump_share": 0.25,
    "misflip_s": 2.0,
}

SESSION = "session"
SEARCH = "search"
READING = "reading"
SERIES = (SESSION, SEARCH, READING)
SERIES_WORDS = {SESSION: "вся сессия", SEARCH: "поиск", READING: "чтение"}
# Ряд → фаза `study.disorder`, чьи ряды переходов он берёт.
PHASE_OF = {SESSION: disorder.ALL, SEARCH: disorder.SEARCH,
            READING: disorder.READING}
GROUP_ORDER = [key for key, _, _ in MINUTE_GROUPS]


def settings(raw: dict | None) -> dict:
    """Пороги портрета: `portrait` из `thresholds.json` поверх значений
    по умолчанию; не число — значение по умолчанию."""
    values = dict(DEFAULTS)
    for key, default in DEFAULTS.items():
        value = (raw or {}).get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            values[key] = value
    return values


# --- энтропия окна --------------------------------------------------------

def entropy_batch(src: np.ndarray, dst: np.ndarray, n: int) -> np.ndarray:
    """H_t каждой строки пачки переходов: [src], [dst] — `(R, N)` номера
    зон. Та же формула, что `study.disorder._entropies`:
    `H_t = − Σ_i π_i · Σ_j P_ij · log₂ P_ij`, π — доли начал переходов."""
    rows_n, size = dst.shape
    codes = (np.arange(rows_n)[:, None] * n * n + src * n + dst).ravel()
    counts = np.bincount(codes, minlength=rows_n * n * n).reshape(
        rows_n, n, n).astype(float)
    rows = counts.sum(axis=2)
    total = rows.sum(axis=1, keepdims=True)
    pi = rows / np.where(total > 0, total, 1.0)
    denom = np.where(rows > 0, rows, 1.0)[:, :, None]
    p = counts / denom
    with np.errstate(divide="ignore", invalid="ignore"):
        logp = np.where(p > 0, np.log2(np.where(p > 0, p, 1.0)), 0.0)
    return -(pi * (p * logp).sum(axis=2)).sum(axis=1) + 0.0


def shuffled_level(src: np.ndarray, dst: np.ndarray, n: int, repeats: int,
                   rng) -> float:
    """Средняя H_t тех же переходов, у которых «куда» переставлено
    наугад, — [repeats] розыгрышей. Перестановка сохраняет, по скольким
    клеткам и как часто взгляд бывал (доли начал и концов), и убирает
    только порядок.

    # Выбор наш: переставляются концы переходов окна, а не сами
    фиксации, — окно состоит из переходов, и ряды в нём бывают
    разорваны; так у перемешанного окна те же начала, что у настоящего."""
    if repeats <= 0:
        return float("nan")
    s = np.tile(src, (repeats, 1))
    d = rng.permuted(np.tile(dst, (repeats, 1)), axis=1)
    return float(entropy_batch(s, d, n).mean())


_RANDOM: dict = {}


def random_level(n: int, k: int, repeats: int) -> float:
    """Энтропия совершенно случайного взгляда при [n] зонах и [k]
    переходах — `study.disorder.random_level` с зерном от `n` и `k`:
    одно число на размер окна, у всех участников и прогонов одно."""
    key = (n, k, repeats)
    if key not in _RANDOM:
        _RANDOM[key] = disorder.random_level(
            n, k, repeats, stats.seed_for("portrait", "random", n, k))[0]
    return _RANDOM[key]


def series(fixes: list[dict], name: str, spans, gap_ms: float,
           index: dict) -> list[tuple]:
    """Переходы ряда [name] по клеткам сетки окна: `(откуда, куда, миг
    начала, конец, группа откуда, группа куда)`. Ряды переходов — те
    же, что у меры беспорядочности своей фазы (`disorder.chains`): рвёт
    их движение раскладки, просвет дольше `transition_gap_ms` и смена
    похода; в поиске походы склеены подряд, но пары на стыке нет."""
    out = []
    for run in disorder.chains(fixes, PHASE_OF[name], spans, gap_ms):
        for a, b in zip(run, run[1:]):
            fa, fb = fixes[a], fixes[b]
            out.append((index[fa["cell"]], index[fb["cell"]], fa["t"],
                        fb["end"], fa["group"], fb["group"]))
    return out


def windows(trans: list[tuple], n: int, size: int, step: int, axis,
            repeats: int, level: float, max_ms: float, seed: int
            ) -> list[dict]:
    """Окна по [size] подряд идущих переходов с шагом [step].

    У окна: `h` — H_t, делённая на случайный уровень [level] (те же
    единицы, что у `H_t` поиска, М1); `h_order` — H_t, делённая на H_t
    того же окна с перемешанным порядком (справочно: только порядок);
    `x` — место на оси (минута изучения или накопленного поиска, по
    середине окна); `group` — преобладающая в окне группа видов
    времени; `long` — окно растянуто дольше [max_ms] (отлучка, пауза)."""
    if len(trans) < size or size < 1:
        return []
    arr = np.asarray([(a, b) for a, b, *_ in trans], dtype=np.int64)
    rng = np.random.default_rng(seed)
    out = []
    for k, start in enumerate(range(0, len(trans) - size + 1, step)):
        part = trans[start:start + size]
        src = arr[start:start + size, 0]
        dst = arr[start:start + size, 1]
        h_raw = float(entropy_batch(src[None, :], dst[None, :], n)[0])
        mixed = shuffled_level(src, dst, n, repeats, rng)
        t0, t1 = part[0][2], part[-1][3]
        mid = (t0 + t1) / 2
        groups = Counter([part[0][4]] + [p[5] for p in part])
        top = max(GROUP_ORDER, key=lambda g: (groups.get(g, 0),
                                               -GROUP_ORDER.index(g)))
        out.append({
            "i": k + 1, "from": start, "to": start + size, "t0": t0,
            "t1": t1, "mid": mid, "x": axis(mid), "h_raw": h_raw,
            "h": h_raw / level if level > 0 else None,
            "h_order": h_raw / mixed if mixed and mixed > 0 else None,
            "group": top, "long": (t1 - t0) > max_ms})
    return out


def non_overlapping(wins: list[dict]) -> int:
    """Сколько окон можно взять без общих переходов (жадно слева)."""
    count = 0
    edge = -1
    for w in wins:
        if w["from"] >= edge:
            count += 1
            edge = w["to"]
    return count


def theil_sen(wins: list[dict], scale: float = 1.0) -> float | None:
    """Наклон Тейла — Сена по окнам: медиана наклонов всех пар окон,
    у которых нет общих переходов (Sen, 1968); нужно не меньше трёх
    непересекающихся окон. [scale] — на сколько единиц оси (у чтения —
    на 10 минут)."""
    live = [w for w in wins if w["h"] is not None and w["x"] is not None]
    if non_overlapping(live) < 3:
        return None
    slopes = []
    for i, a in enumerate(live):
        for b in live[i + 1:]:
            if b["from"] < a["to"] or b["x"] == a["x"]:
                continue
            slopes.append((b["h"] - a["h"]) / (b["x"] - a["x"]))
    if not slopes:
        return None
    return statistics.median(slopes) * scale + 0.0


def iqr(wins: list[dict]) -> float | None:
    """Межквартильный размах `h` окон — справочно."""
    hs = sorted(w["h"] for w in wins if w["h"] is not None)
    if len(hs) < 4:
        return None
    q = statistics.quantiles(hs, n=4, method="inclusive")
    return q[2] - q[0]


def search_clock(done: list, line, hi: float):
    """Миг → накопленное время поиска, минуты: время на полке и карте
    по доведённым походам до выбора книги, без отлучек — то же, что у
    фазы «поиск» мер беспорядочности."""
    parts = []
    acc = 0.0
    for trip in done:
        stop = min(trip.choice or trip.end, hi)
        parts.append((trip.start, stop, acc))
        acc += _screen_time(line, trip.start, stop, SEARCH_SCREENS)

    def at(t: float) -> float | None:
        for a, b, base in reversed(parts):
            if a <= t:
                return (base + _screen_time(line, a, min(t, b),
                                            SEARCH_SCREENS)) / 60_000
        return None
    return at


# --- одна запись -----------------------------------------------------------

def prepare(fixes: list[dict], done: list, res: dict, record, line, screen,
            cfg: dict, report_cfg: dict, sha: str) -> dict:
    """Портрет одной записи — всё, что не зависит от других участников:
    окна энтропии трёх рядов, заходы и возвраты, взгляд назад, лента."""
    pc = cfg["portrait"]
    grid = tuple(int(v) for v in cfg["grid"])
    zones = disorder.search_zones(grid)
    index = {z: i for i, z in enumerate(zones)}
    n = len(zones)
    gap_ms = float(cfg["transition_gap_ms"])
    spans = res.get("_spans") or []
    lo = line.study_start
    hi = line.study_end if line.window_changed is None else \
        min(line.study_end, line.window_changed)
    repeats = int(pc["shuffle_repeats"])
    max_ms = float(pc["window_max_s"]) * 1000
    clock = search_clock(done, line, hi)
    sizes = {SESSION: (int(pc["window_transitions"]),
                       int(pc["window_step"])),
             SEARCH: (int(pc["search_window"]), int(pc["search_step"])),
             READING: (int(pc["window_transitions"]),
                       int(pc["window_step"]))}
    entropy: dict = {}
    for name in SERIES:
        size, step = sizes[name]
        trans = series(fixes, name, spans, gap_ms, index)
        axis = clock if name == SEARCH else \
            (lambda t: (t - lo) / 60_000)
        level = random_level(n, size, int(cfg["ht_repeats"]))
        entropy[name] = {
            "transitions": len(trans), "size": size, "step": step,
            "level": level,
            "windows": windows(trans, n, size, step, axis, repeats, level,
                               max_ms,
                               stats.seed_for("portrait", sha, name))}
    quality = res.get("quality") or {}
    implicit = quality.get("implicit") or {}
    residual = implicit.get("drift_deg" if report_cfg.get("version") ==
                            "drift" else "raw_deg")
    return {
        "entropy": entropy, "zones": n,
        "dwell": dwell.prepare(fixes, res, record, done, line, screen, cfg,
                               pc),
        "lookback": reading_back.lookbacks(
            res.get("_samples") or [], spans, record.frames, screen, line,
            residual, pc, report_cfg),
        "study_ms": line.study_ms,
        "opens": [(float(e["t"]) - lo) / 1000 for e in record.events
                  if e["type"] == "book.open" and e.get("phase") != "post"
                  and lo <= float(e["t"]) <= line.study_end],
    }


# --- все записи: числа участника ------------------------------------------

def finish(entries: list[dict], cfg: dict, *, no_filter: bool) -> None:
    """Числа портрета, которые идут в сравнение (`portrait_measures`),
    — семья «Д. Портрет» (SNO-ALG-RES-06, -07, -08, «Что идёт в
    сравнение»).

    Энтропия по ходу, заходы и переходы — у сессий с мерами
    беспорядочности (`disorder_live`: шум меньше общего порога; в
    проверочном прогоне — все); взгляд назад — у сессий, где он
    посчитан; возвраты на страницу назад — по журналу, у всех, и у
    записей с телефона."""
    for e in entries:
        own = e["portrait_measures"] = {}
        if e.get("status") != "ok":
            continue
        nav = e.get("reading_nav") or {}
        own["portrait.page_backs_per_min"] = nav.get("per_min")
        data = (e.get("gaze_data") or {}).get("portrait")
        if not data:
            continue
        look = data.get("lookback") or {}
        if not look.get("reason"):
            own["portrait.lookbacks_per_min"] = look.get("per_min")
            own["portrait.lookback_share"] = look.get("share")
        if not e.get("disorder_live"):
            continue
        ent = data["entropy"]
        own["portrait.search_slope"] = theil_sen(ent[SEARCH]["windows"])
        own["portrait.reading_slope"] = theil_sen(ent[READING]["windows"],
                                                  10.0)
        d = data.get("dwell") or {}
        if d.get("reason"):
            continue
        cat = d.get("cat") or {}
        own["portrait.cat_return_share"] = cat.get("revisit_share")
        own["portrait.cat_return_ratio"] = cat.get("ratio")
        ui = d.get("ui") or {}
        valid = d.get("valid_min") or 0.0
        own["portrait.ui_trans_per_min"] = (ui.get("transitions", 0) / valid
                                            if valid > 0 else None)
        search_min = (e["gaze_data"]["disorder"]["phases"]["search"]
                      ["time_s"] or 0.0) / 60
        own["portrait.cat_trans_per_min"] = (
            cat.get("transitions", 0) / search_min
            if search_min > 0 and cat.get("entries") else None)


def numbers(e: dict) -> dict:
    """Числа портрета участника для таблиц и страницы — все, и
    справочные, а не только те, что идут в сравнение."""
    out = dict(e.get("portrait_measures") or {})
    data = (e.get("gaze_data") or {}).get("portrait") or {}
    ent = data.get("entropy") or {}
    for name in (SEARCH, READING):
        own = ent.get(name) or {}
        out[f"portrait.{name}_windows"] = len(own.get("windows") or [])
        out[f"portrait.{name}_iqr"] = iqr(own.get("windows") or [])
    d = data.get("dwell") or {}
    if d and not d.get("reason"):
        out["portrait.ui_density"] = (d.get("ui") or {}).get("density")
        out["portrait.ui_revisits"] = (d.get("ui") or {}).get("revisits")
        out["portrait.cat_revisits"] = (d.get("cat") or {}).get("revisits")
        out["portrait.cat_expected"] = (d.get("cat") or {}).get("expected")
        out["portrait.book_revisits"] = (d.get("book") or {}).get(
            "revisits")
        out["portrait.book_ratio"] = (d.get("book") or {}).get("ratio")
        out["portrait.page_revisit_share"] = (d.get("page") or {}).get(
            "revisit_share")
    look = data.get("lookback") or {}
    out["portrait.lookbacks"] = look.get("count")
    out["portrait.lookback_jump_deg"] = look.get("jump_deg")
    out["portrait.shows_with_back"] = look.get("shows_with_back")
    out["portrait.lookback_reason"] = look.get("reason")
    nav = e.get("reading_nav") or {}
    out["portrait.page_backs"] = nav.get("backs")
    out["portrait.misflips"] = nav.get("misflips")
    out["portrait.navigation"] = nav.get("navigation")
    return out
