"""Шаг 7а — взгляд назад при чтении и возвраты на страницу назад
(SNO-ALG-RES-08; портрет участника, SNO-F-RES-07; шаг 38).

Откуда данные: возвраты на страницу назад — журнал `events.jsonl`
(`page.shown`: книга, страница, полоса, откуда и чем листали —
`lib/ui/reader/reader_screen.dart`, `_notePlace`); взгляд назад —
выборки взгляда той версии, которой считаются меры («Разбор записи»,
`report.versions`), кадры раскладки и место точки на странице в пунктах
PDF (`layout.locate`, SNO-ALG-REC-02); точность, прецизионность и
остаток неявных точек — «Разбор записи».
Технология: стандартная библиотека; фиксации — `report.idt.fixations`
одним порогом на всё исследование (`portrait.reading_idt_deg`).
Метод:
* что веб-камера видит при чтении — Rayner K. «Eye movements and
  attention in reading, scene perception, and visual search», QJEP,
  2009, 62(8):1457 (регрессии к слову — 10–15 % скачков); Hutt S. и
  др. «Webcam-based eye tracking to detect mind wandering…», 2024;
  Slim M., Hartsuiker R. «Moving visual world experiments online?»,
  Behavior Research Methods, 2023, 55:3786;
* взгляд назад к прочитанному (look-back) — мера текстового уровня:
  Hyönä J., Lorch R., Kaakinen J. «Individual differences in reading to
  summarize expository text», J. Educational Psychology, 2002,
  94(1):44.
Вход → выход: журнал записи → возвраты на страницу назад
(`page_backs`); выборки, кадры и качество взгляда → эпизоды взгляда
назад по тексту (`lookbacks`).
"""

from __future__ import annotations

import bisect
import statistics

from .. import layout
from ..report import idt
from .actions import _screen_time

# Чем листали — по `data.cause` события `page.shown`. Навигация — не
# перечитывание: переход по оглавлению, к найденному, к пометке.
NAVIGATION = ("toc", "search", "find", "annotation")
# Показ без листания читателем: открытие книги, смена режима или ленты.
NOT_A_FLIP = ("open", "mode", "flow")

# Фиксация, начавшаяся не позже этого после смены кадра, — вторая
# половина фиксации, разрезанной кадром (`report.idt`): глаз ещё не
# двигался — на скачок к новой странице нужно больше (латентность
# саккады около 200 мс — Rayner, 2009).
CUT_MS = 150

CAUSE_WORDS = {"tap_zone": "зона", "key": "клавиша", "volume": "громкость",
               "arrow": "стрелка", "slider": "ползунок", "scroll": "лента",
               "other": "другое", "toc": "оглавление", "search": "поиск",
               "find": "найти в книге", "annotation": "пометка"}


def _int(value) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return int(value)


def reading_minutes(line) -> float:
    """Минуты чтения — время на экране чтения за изучение без
    отлучек."""
    hi = line.study_end
    return _screen_time(line, line.study_start, hi, ("reader",)) / 60_000


# --- возвраты на страницу назад — по журналу ----------------------------

def page_backs(events: list[dict], line, misflip_s: float,
               reread_min_s: float = 1.5) -> dict:
    """Возвраты на страницу (или полосу) назад внутри одного открытия
    книги — по событиям `page.shown`.

    Назад — показ, у которого страница меньше прежней или та же
    страница, но полоса выше. Переход по оглавлению, к найденному и к
    пометке — навигация, отдельной строкой. Вперёд и сразу назад быстрее
    [misflip_s] на то же место — «промах листания», отдельный счётчик.

    BUG-74 (шаг 43): шаг назад — **возврат** (перечитывание), только
    если на показанной странице задержались не меньше [reread_min_s]
    (до следующего показа, закрытия книги или конца изучения). Подряд
    идущие шаги назад без задержки — **перемотка**: одна на цепочку, а
    страница, где цепочка остановилась, — её конец, а не возврат.
    Перемотка сразу после открытия книги не на первой странице (вперёд
    ещё не листали) до первой страницы — **возврат к началу**: она о
    том, где книгу оставил прежний читатель, а не о читателе. Одиночный
    быстрый шаг назад — «мельком», не возврат.
    """
    lo, hi = line.study_start, line.study_end
    rows: list[dict] = []
    shows = 0
    opened_mid = 0
    book = None
    place = None
    forward = None          # (миг, откуда) последнего показа вперёд
    pending: dict | None = None   # последний шаг назад — ждёт задержки
    run = 0                 # номер цепочки шагов назад подряд
    moved = False           # листали ли вперёд после открытия
    open_page = None

    def settle(t: float) -> None:
        nonlocal pending
        if pending is not None:
            pending["dwell_s"] = max(0.0, (t - pending["t"]) / 1000)
            pending = None

    for e in events:
        if e.get("phase") == "post":
            continue
        t = float(e["t"])
        if not lo <= t <= hi:
            continue
        kind = e["type"]
        if kind == "book.open":
            settle(t)
            book, place, forward = e.get("book"), None, None
            data = e.get("data") if isinstance(e.get("data"), dict) else {}
            open_page = _int(data.get("page"))
            if open_page is not None and open_page > 1:
                opened_mid += 1
            moved = False
            run += 1
            continue
        if kind == "book.close":
            settle(t)
            book, place, forward = None, None, None
            run += 1
            continue
        if kind != "page.shown" or book is None:
            continue
        settle(t)
        data = e.get("data") if isinstance(e.get("data"), dict) else {}
        page = _int(e.get("page"))
        strip = _int(e.get("strip")) or 1
        if page is None:
            continue
        shows += 1
        was = data.get("from") if isinstance(data.get("from"), dict) \
            else None
        if was is not None and _int(was.get("page")) is not None:
            before = (_int(was.get("page")), _int(was.get("strip")) or 1)
        else:
            before = place
        now = (page, strip)
        place = now
        if before is None or now == before:
            continue
        cause = str(data.get("cause") or "other")
        if now > before:
            if cause not in NOT_A_FLIP and cause not in NAVIGATION:
                forward = (t, before)
                moved = True
            run += 1
            continue
        if cause in NOT_A_FLIP:
            what = "не листание"
        elif cause in NAVIGATION:
            what = "навигация"
        elif forward is not None and t - forward[0] <= misflip_s * 1000 \
                and now == forward[1]:
            what = "промах листания"
        else:
            what = "назад"
        forward = None
        row = {"t": t, "book": book, "page": page, "strip": strip,
               "from_page": before[0], "from_strip": before[1],
               "pages": before[0] - page, "cause": cause, "kind": what,
               "dwell_s": None, "run": run, "moved": moved,
               "open_page": open_page}
        rows.append(row)
        if what == "назад":
            pending = row
        else:
            run += 1
    settle(hi)
    rewinds, to_start = _rewinds(rows, reread_min_s)
    minutes = reading_minutes(line)
    back = [r for r in rows if r["kind"] == "назад"]
    causes: dict = {}
    for r in back:
        causes[r["cause"]] = causes.get(r["cause"], 0) + 1
    return {
        "rows": rows, "shows": shows, "reading_min": minutes,
        "backs": len(back),
        "per_min": len(back) / minutes if minutes > 0 else None,
        "share": len(back) / shows if shows else None,
        "pages_median": statistics.median([r["pages"] for r in back])
        if back else None,
        "navigation": sum(1 for r in rows if r["kind"] == "навигация"),
        "misflips": sum(1 for r in rows if r["kind"] == "промах листания"),
        "glances": sum(1 for r in rows if r["kind"] == "мельком"),
        "rewinds": rewinds,
        "rewind_pages": sum(r["pages"] for r in rows
                            if r["kind"] == "перемотка"),
        "to_start": to_start,
        "opened_mid": opened_mid,
        "reread_min_s": reread_min_s,
        "causes": causes,
    }


def _rewinds(rows: list[dict], reread_min_s: float) -> tuple[int, int]:
    """BUG-74: шаги «назад» по цепочкам — подряд, без показа вперёд и без
    другого шага между ними. Цепочка кончается шагом с задержкой не
    меньше [reread_min_s] (там остановились) или последним шагом.
    Цепочка из одного шага: с задержкой — возврат, без — «мельком».
    Длиннее — перемотка (все её шаги), и возврат к началу, если она
    начата до первого листания вперёд после открытия книги не на первой
    странице и кончилась на первой. Ответ — (перемоток, из них к
    началу); виды шагов правятся в [rows]."""
    chains: list[list[dict]] = []
    for r in rows:
        if r["kind"] != "назад":
            continue
        last = chains[-1] if chains else None
        if last and last[-1]["run"] == r["run"] and \
                (last[-1]["dwell_s"] or 0.0) < reread_min_s:
            last.append(r)
        else:
            chains.append([r])
    rewinds = to_start = 0
    for chain in chains:
        if len(chain) == 1:
            r = chain[0]
            if (r["dwell_s"] or 0.0) < reread_min_s:
                r["kind"] = "мельком"
            continue
        rewinds += 1
        for r in chain:
            r["kind"] = "перемотка"
        head, tail = chain[0], chain[-1]
        if not head["moved"] and (head["open_page"] or 1) > 1 and \
                tail["page"] <= 1:
            to_start += 1
            for r in chain:
                r["to_start"] = True
    return rewinds, to_start


# --- взгляд назад по тексту — по взгляду --------------------------------

def _quantile(values: list[float], q: float) -> float:
    """Квантиль по линейной интерполяции (как `numpy.quantile` по
    умолчанию)."""
    xs = sorted(values)
    if len(xs) == 1:
        return xs[0]
    pos = q * (len(xs) - 1)
    i = int(pos)
    frac = pos - i
    if i + 1 >= len(xs):
        return xs[-1]
    return xs[i] + (xs[i + 1] - xs[i]) * frac


def _show_key(frame: dict, page: int):
    """Показ страницы — книга, страница, полоса и геометрия листа."""
    sheet = frame.get("sheet") or {}
    geo = None
    for p in sheet.get("pages") or []:
        if p.get("page") == page:
            geo = (round(float(p.get("x", 0)), 1),
                   round(float(p.get("y", 0)), 1))
    strip = tuple(round(float(v), 1) for v in sheet.get("strip") or ())
    return (frame.get("book"), page, strip,
            round(float(sheet.get("scale") or 0), 4), geo)


def _page_size(frame: dict, page: int) -> tuple[float, float]:
    for p in (frame.get("sheet") or {}).get("pages") or []:
        if p.get("page") == page:
            return float(p.get("w") or 0), float(p.get("h") or 0)
    return 0.0, 0.0


def _visible_pt(frame: dict, page: int) -> tuple[float, float]:
    """Видимая часть страницы по вертикали в пунктах — верх и высота:
    полоса листа (в режимах половины и трети), иначе вся страница."""
    sheet = frame.get("sheet") or {}
    scale = float(sheet.get("scale") or 1)
    for p in sheet.get("pages") or []:
        if p.get("page") != page:
            continue
        top_pt = 0.0
        h_pt = float(p.get("h") or 0)
        strip = sheet.get("strip")
        if isinstance(strip, list) and len(strip) == 4:
            a = (float(strip[1]) - float(p.get("y", 0))) / scale
            b = a + float(strip[3]) / scale
            a, b = max(0.0, a), min(h_pt, b)
            if b > a:
                top_pt, h_pt = a, b - a
        return top_pt, h_pt
    return 0.0, 0.0


def _left_reader(line, a: float, b: float) -> bool:
    """Уходил ли участник из читалки между мигами [a] и [b] — по
    экранам журнала: вернувшись, он видит страницу заново."""
    return any(a < t <= b and name != "reader" for t, name in line.screens)


class _Show:
    """Показ страницы: фронт чтения, колонки, эпизоды взгляда назад."""

    def __init__(self, key, frame, page, n: int):
        self.key = key
        self.n = n
        self.book = frame.get("book")
        self.page = page
        self.scale = float((frame.get("sheet") or {}).get("scale") or 1)
        self.w, self.h = _page_size(frame, page)
        self.vis_top, self.vis_h = _visible_pt(frame, page)
        self.front: float | None = None
        self.recent: list[float] = []
        self.boundary: float | None = None   # левый край нынешней колонки
        self.col_max: float | None = None    # правее всех в колонке
        self.prev: dict | None = None        # прежняя фиксация на странице
        self.episode: dict | None = None
        self.episodes: list[dict] = []
        self.fixes: list[dict] = []
        self.columns = 1
        self.t0: float | None = None
        self.t1: float | None = None


def lookbacks(samples: list, spans: list, frames: list[dict], screen,
              line, implicit_deg: float | None, portrait_cfg: dict,
              report_cfg: dict, smooth_frames: int = 3,
              smooth_min_fps: float = 25.0) -> dict:
    """Взгляд назад к прочитанному внутри одного показа страницы.

    1. Выборки — после медианы [smooth_frames] кадров (`study.noise`,
       как у мер беспорядочности); фиксации — одним порогом разброса на
       всё исследование (`portrait.reading_idt_deg`).
       BUG-73 (шаг 43): сессия получает взгляд назад, если в фиксациях
       лежит не меньше `portrait.reading_fix_share` времени её взгляда
       на экране чтения, — а не по прецизионности калибровки: у
       веб-камер три прецизионности 4–7,4°, и прежнее правило гасило
       меру у всех записей.
    2. Порог скачка назад `L = max(lookback_min_deg, k × шум от кадра к
       кадру после сглаживания, остаток неявных точек)`, `k` —
       `portrait.lookback_noise_k`; в пункты страницы — масштабом листа.
    3. Фронт чтения — `front_quantile` глубины последних `front_window`
       фиксаций (не во взгляде назад); фронт только опускается. Первая
       фиксация нового показа на том же месте, где взгляд был до смены
       кадра, — остаток прежней страницы: фронта она не ставит.
    4. Скачок вверх (больше `L`) и вправо больше `column_jump_share`
       ширины страницы в верхнюю треть видимой части — вторая колонка,
       фронт заново.
       # Выбор наш: «вверх» — больше порога `L`, иначе дрожь взгляда по
       строке со скачком вправо через слово выглядела бы сменой
       колонки.
    5. Взгляд назад — фиксация выше фронта больше чем на `L` или в
       прежней колонке; эпизод длится до возврата к фронту ближе `L` или
       ухода со страницы; короче `lookback_min_ms` — не считается.
    """
    from . import noise
    limit = float(portrait_cfg["reading_idt_deg"])
    out: dict = {"episodes": [], "shows": [], "points": [], "reason": None,
                 "idt_deg": limit, "fix_share": None, "s2s_deg": None}
    times = [float(f["t"]) for f in frames]
    smoothed, used, fps = noise.smooth(samples, smooth_frames,
                                       smooth_min_fps)
    out["smooth_frames"] = used
    fixes = idt.fixations(smoothed, screen.px_for_deg(limit), spans,
                          report_cfg, times)
    lo = line.study_start
    hi = line.study_end if line.window_changed is None else \
        min(line.study_end, line.window_changed)

    def not_reading(t: float) -> bool:
        return line.away_at(t) or line.screen_at(t) != "reader"

    share = noise.fix_share(
        smoothed, fixes, lo, hi, spans, not_reading,
        float(report_cfg["sample_cap_ms"]), screen,
        screen.px_for_deg(float(report_cfg["outside_deg"])))
    s2s = noise.s2s_deg(smoothed, fixes, screen)
    out["fix_share"], out["s2s_deg"] = share, s2s
    least = float(portrait_cfg["reading_fix_share"])
    if share is None:
        out["reason"] = "годного взгляда на экране чтения нет"
        return out
    if share < least:
        out["reason"] = (f"шум дробит фиксации чтения: в фиксациях "
                         f"{share:.0%} времени взгляда на странице — "
                         f"меньше {least:.0%}").replace(".", ",")
        return out
    L_deg = max(float(portrait_cfg["lookback_min_deg"]),
                float(portrait_cfg["lookback_noise_k"]) * (s2s or 0.0),
                implicit_deg or 0.0)
    out["L_deg"] = L_deg
    L_px = screen.px_for_deg(L_deg)
    q = float(portrait_cfg["front_quantile"])
    window = int(portrait_cfg["front_window"])
    jump = float(portrait_cfg["column_jump_share"])
    min_ms = float(portrait_cfg["lookback_min_ms"])
    shows: list[_Show] = []
    cur: _Show | None = None
    still_px = screen.px_for_deg(limit)
    last: tuple | None = None     # (конец, x, y) прежней фиксации в окне

    def close_episode(show: _Show) -> None:
        ep = show.episode
        show.episode = None
        if ep is None or ep["t1"] - ep["t0"] < min_ms:
            return
        show.episodes.append(ep)

    prev_t = None
    for f in fixes:
        if f.moving or not lo <= f.start < hi:
            continue
        away = prev_t is not None and _left_reader(line, prev_t, f.start)
        prev_t = f.start
        reader = line.screen_at(f.start) == "reader"
        if away or not reader:
            # Ушёл из читалки — показ кончился: вернувшись, читатель
            # видит страницу заново.
            if cur is not None:
                close_episode(cur)
            cur = None
            last = None
            if not reader:
                continue
        i = bisect.bisect_right(times, f.start) - 1
        frame = frames[i] if i >= 0 else None
        hit = layout.locate(frame, f.x, f.y) if frame is not None and \
            frame.get("sheet") else {"zone": "none"}
        if hit.get("zone") != "page":
            # Взгляд ушёл на панель или с экрана — эпизод кончается,
            # фронт сохраняется до конца показа.
            if cur is not None:
                close_episode(cur)
            last = (f.end, f.x, f.y)
            continue
        page = hit["page"]
        key = _show_key(frame, page)
        was = last
        last = (f.end, f.x, f.y)
        if cur is None or cur.key != key:
            if cur is not None:
                close_episode(cur)
            cur = _Show(key, frame, page, len(shows) + 1)
            shows.append(cur)
            # Перелистнул, а взгляд ещё на прежнем месте: кадр разрезал
            # фиксацию, и её вторая половина легла на новую страницу
            # (началась в миг смены кадра — `CUT_MS`) или та же точка,
            # что до смены. Это не чтение новой страницы — фронта она
            # не ставит. Выбор наш: так же, как смена содержимого под
            # неподвижным взглядом у заходов (SNO-ALG-RES-07).
            cut = f.start - float(frame["t"]) <= CUT_MS
            same = was is not None and f.start - was[0] <= 300 and \
                ((f.x - was[1]) ** 2 + (f.y - was[2]) ** 2) ** 0.5 \
                < still_px
            if cut or same:
                continue
        x, y = float(hit["x_pt"]), float(hit["y_pt"])
        L = L_px / cur.scale if cur.scale > 0 else L_px
        point = {"t": f.start, "end": f.end, "x": x, "y": y,
                 "wx": f.x, "wy": f.y, "show": cur.n, "back": False}
        cur.fixes.append(point)
        cur.t0 = f.start if cur.t0 is None else cur.t0
        cur.t1 = f.end
        prev = cur.prev
        cur.prev = point
        # Вторая колонка: скачок вверх (больше порога — не дрожь на
        # строке) и вправо больше доли ширины страницы — в верхнюю
        # треть видимой части.
        if prev is not None and prev["y"] - y > L and cur.w > 0 and \
                x - prev["x"] > jump * cur.w and \
                y <= cur.vis_top + cur.vis_h / 3:
            # Вторая колонка — не возврат: фронт начинается заново.
            close_episode(cur)
            # Граница колонок — в просвете между ними: правее всех
            # фиксаций прежней колонки на четверть пути к новой (первая
            # фиксация в новой колонке бывает и не у её края).
            right = max(cur.col_max if cur.col_max is not None
                        else prev["x"], prev["x"])
            cur.boundary = right + 0.25 * (x - right)
            cur.columns += 1
            cur.front = y
            cur.recent = [y]
            cur.col_max = x
            continue
        in_old = cur.boundary is not None and x < cur.boundary
        if cur.front is not None and (in_old or y < cur.front - L):
            point["back"] = True
            if cur.episode is None:
                before = prev if prev is not None else point
                cur.episode = {
                    "t0": f.start, "t1": f.end, "show": cur.n,
                    "book": cur.book, "page": cur.page,
                    "front": cur.front, "y": y,
                    "up_share": (cur.front - y) / cur.h if cur.h else None,
                    "jump_deg": screen.angle_deg(
                        (before["wx"], before["wy"]), (f.x, f.y)),
                    "old_column": in_old, "fixations": 0}
            cur.episode["t1"] = f.end
            cur.episode["fixations"] += 1
            continue
        close_episode(cur)
        cur.col_max = x if cur.col_max is None else max(cur.col_max, x)
        cur.recent.append(y)
        cur.recent = cur.recent[-window:]
        front = _quantile(cur.recent, q)
        cur.front = front if cur.front is None else max(cur.front, front)
    if cur is not None:
        close_episode(cur)
    for s in shows:
        out["episodes"] += s.episodes
        out["shows"].append({"n": s.n, "book": s.book, "page": s.page,
                             "t0": s.t0, "t1": s.t1,
                             "fixations": len(s.fixes),
                             "columns": s.columns,
                             "episodes": len(s.episodes), "h": s.h})
        for p in s.fixes:
            out["points"].append({"t": p["t"], "end": p["end"],
                                  "depth": p["y"] / s.h if s.h else None,
                                  "show": s.n, "back": p["back"]})
    minutes = reading_minutes(line)
    eps = out["episodes"]
    out["reading_min"] = minutes
    out["count"] = len(eps)
    out["per_min"] = len(eps) / minutes if minutes > 0 else None
    out["share"] = (sum(e["t1"] - e["t0"] for e in eps) / (minutes * 60_000)
                    if minutes > 0 else None)
    out["jump_deg"] = statistics.median([e["jump_deg"] for e in eps]) \
        if eps else None
    ups = [e["up_share"] for e in eps if e["up_share"] is not None]
    out["up_share"] = statistics.median(ups) if ups else None
    # Доля показов хотя бы с одним взглядом назад — среди показов, где
    # было что читать (от трёх фиксаций).
    real = [s for s in shows if len(s.fixes) >= 3]
    out["shows_with_back"] = (sum(1 for s in real if s.episodes) / len(real)
                              if real else None)
    return out
