"""Страница разбора `index.html` (SNO-F-RES-03).

Одна страница без внешних скриптов, шрифтов и картинок: взгляд —
биометрия, и всё остаётся на ПК организатора. Рисунки — SVG прямо в
странице: ход изучения по минутам, схема полки или карты на каждый
поход с фиксациями поверх, «перед нажатием» — что было под взглядом
перед каждым выбором источника (BUG-64), «куда смотрели на странице»
по книгам. Схема рисуется по кадрам раскладки — прямоугольники зон,
без PDF; на карте — звёзды, области групп и подписи категорий там, где
их поставил бы художник карты.

Цвета — проверенная палитра по умолчанию (навык dataviz): синий —
чтение, оранжевый — полка, бирюзовый — карта; вне экрана и прочее —
серые. Тёмная тема — свои шаги тех же оттенков.
"""

from __future__ import annotations

import html
import math

from .measures import MINUTE_GROUPS
from .zones import BUCKETS

# Сколько походов и книг рисуется — больше страница не держит.
MAX_VISIT_MAPS = 24
MAX_BOOKS = 12

STYLE = """
:root {
  color-scheme: light;
  --surface: #fcfcfb; --surface-2: #f3f2ef; --line: #dcdad4;
  --text: #0b0b0b; --text-2: #52514e; --text-3: #7a7873;
  --accent: #a32f35;
  --s-reading: #2a78d6; --s-shelf: #eb6834; --s-galaxy: #1baf7a;
  --s-off: #52514e; --s-other: #c9c7c0;
  --fix-in: #2a78d6; --fix-out: #eb6834;
  --cat: rgba(42, 120, 214, 0.06); --target: rgba(235, 104, 52, 0.18);
}
@media (prefers-color-scheme: dark) {
  :root:where(:not([data-theme="light"])) {
    color-scheme: dark;
    --surface: #1a1a19; --surface-2: #242422; --line: #3a3936;
    --text: #f0efec; --text-2: #c3c2b7; --text-3: #8f8d86;
    --accent: #e0676c;
    --s-reading: #3987e5; --s-shelf: #d95926; --s-galaxy: #199e70;
    --s-off: #8f8d86; --s-other: #4a4945;
    --fix-in: #3987e5; --fix-out: #d95926;
    --cat: rgba(57, 135, 229, 0.10); --target: rgba(217, 89, 38, 0.25);
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --surface: #1a1a19; --surface-2: #242422; --line: #3a3936;
  --text: #f0efec; --text-2: #c3c2b7; --text-3: #8f8d86;
  --accent: #e0676c;
  --s-reading: #3987e5; --s-shelf: #d95926; --s-galaxy: #199e70;
  --s-off: #8f8d86; --s-other: #4a4945;
  --fix-in: #3987e5; --fix-out: #d95926;
  --cat: rgba(57, 135, 229, 0.10); --target: rgba(217, 89, 38, 0.25);
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--surface); color: var(--text);
  font: 15px/1.5 system-ui, "Segoe UI", Roboto, sans-serif; }
main { max-width: 1040px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 22px; margin: 0 0 4px; overflow-wrap: anywhere; }
h2 { font-size: 17px; margin: 32px 0 8px; }
p, li { color: var(--text-2); }
.sub { color: var(--text-2); margin: 0 0 12px; }
.badge { display: inline-block; padding: 2px 10px; border-radius: 999px;
  font-size: 13px; border: 1px solid var(--line); margin-right: 6px; }
.badge.in { border-color: var(--s-reading); }
.badge.out { border-color: var(--accent); color: var(--accent); }
table { border-collapse: collapse; width: 100%; font-size: 14px; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid
  var(--line); vertical-align: top; }
th { color: var(--text-2); font-weight: 600; }
td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
.scroll { overflow-x: auto; }
.legend { display: flex; flex-wrap: wrap; gap: 6px 16px; font-size: 13px;
  color: var(--text-2); margin: 8px 0; }
.legend i { display: inline-block; width: 10px; height: 10px;
  border-radius: 2px; margin-right: 6px; vertical-align: -1px; }
.maps { display: grid; grid-template-columns: repeat(auto-fill,
  minmax(min(100%, 300px), 1fr)); gap: 16px; }
.maps.wide { grid-template-columns: repeat(auto-fill,
  minmax(min(100%, 460px), 1fr)); }
figure { margin: 0; background: var(--surface-2); border-radius: 8px;
  padding: 10px; }
figcaption { font-size: 13px; color: var(--text-2); margin-top: 6px; }
svg { display: block; width: 100%; height: auto; }
.notes li { margin: 2px 0; }
.yes { color: var(--s-reading); font-weight: 600; }
.no { color: var(--accent); font-weight: 600; }
"""


def _e(value) -> str:
    return html.escape("" if value is None else str(value))


def pct(value) -> str:
    if value is None:
        return "—"
    return f"{value * 100:.0f} %"


def deg(value) -> str:
    if value is None:
        return "—"
    return f"{value:.1f}°".replace(".", ",")


def sec(ms) -> str:
    if ms is None:
        return "—"
    return f"{ms / 1000:.1f} с".replace(".", ",")


def _rows(pairs: list[tuple[str, str]]) -> str:
    return "".join(f"<tr><th>{_e(a)}</th><td>{b}</td></tr>"
                   for a, b in pairs)


def _quality(result: dict) -> str:
    q = result["quality"]
    fps = q.get("fps_by_screen") or {}
    fps_text = ", ".join(f"{_e(SCREEN_WORDS.get(k, k))} "
                         f"{str(v).replace('.', ',')}"
                         for k, v in sorted(fps.items())) or "—"
    implicit = q.get("implicit") or {}
    pairs = [
        ("Точность в начале / в конце",
         f"{deg(q.get('start_deg'))} / {deg(q.get('end_deg'))} · средняя "
         f"{deg(q.get('mean_deg'))} (порог {deg(q.get('include_deg'))})"),
        ("Прецизионность", deg(q.get("precision_deg"))),
        ("Годных кадров за изучение", pct(q.get("valid_share"))),
        ("Кадров в секунду по экранам", fps_text),
        ("Задержка камеры",
         "—" if q.get("latency_ms") is None else
         f"{q['latency_ms']:.0f} мс"
         + ("" if q.get("latency_known") else " (не найдена — 0)")),
        ("Неявные точки",
         f"{implicit.get('pairs', 0)} (отброшено «нажал не глядя» "
         f"{q.get('dropped', 0)})"),
        ("Остаток неявных точек: как записано → с поправкой",
         f"{deg(implicit.get('raw_deg'))} → "
         f"{deg(implicit.get('drift_deg'))} (каждая — по поправке без "
         "неё)"),
        ("Наибольший сдвиг поправки дрейфа", deg(q.get("drift_max_deg"))),
        ("Проверка в конце дала поправку",
         "да" if q.get("end_anchor") else "нет"),
        ("Порог фиксаций", f"{deg(q.get('idt_deg'))} "
         f"({q.get('idt_px', 0):.0f} пикс.)"),
        ("Фиксаций", f"{q.get('fixations', 0)} · медиана "
         f"{sec(q.get('fixation_median_ms'))}"),
        ("Экран места записи",
         "из калибровки" if q.get("screen_known") else
         "неизвестен — типичный монитор, градусы приблизительны"),
    ]
    return f"<table>{_rows(pairs)}</table>"


SCREEN_WORDS = {"shelf": "полка", "reader": "страница", "galaxy": "карта",
                "testing": "тестирование", "settings": "настройки"}

OUTCOME_WORDS = {"book": "открыта книга", "left": "ушли", "end":
                 "кончилось изучение"}

VIA_WORDS = {"shelf": "с полки", "shelf_search": "из найденного",
             "galaxy": "с карты"}


def _shares(result: dict) -> str:
    strict = result["shares"]["strict"]
    soft = result["shares"]["soft"]
    rows = []
    for key, name in BUCKETS:
        if strict.get(key, 0) < 0.0005 and soft.get(key, 0) < 0.0005:
            continue
        rows.append(f"<tr><td>{_e(name)}</td>"
                    f"<td class='num'>{pct(strict.get(key))}</td>"
                    f"<td class='num'>{pct(soft.get(key))}</td></tr>")
    return ("<div class='scroll'><table><tr><th>Вид времени</th>"
            "<th class='num'>строго</th><th class='num'>мягко</th></tr>"
            + "".join(rows) + "</table></div>")


GROUP_COLORS = {"reading": "var(--s-reading)", "shelf": "var(--s-shelf)",
                "galaxy": "var(--s-galaxy)", "off": "var(--s-off)",
                "other": "var(--s-other)"}


def _minutes(result: dict) -> str:
    rows = result.get("minutes") or []
    if not rows:
        return "<p>Изучения нет.</p>"
    width, height, pad, top_pad = 960, 180, 40, 10
    n = len(rows)
    slot = (width - pad) / n
    bar = max(2.0, slot - 2)
    parts = [f"<svg viewBox='0 -{top_pad} {width} {height + 22 + top_pad}'"
             " role='img' aria-label='Ход изучения по минутам'>"]
    for y in (0, 0.5, 1):
        yy = height - y * height
        parts.append(f"<line x1='{pad}' x2='{width}' y1='{yy:.1f}' "
                     f"y2='{yy:.1f}' stroke='var(--line)' "
                     "stroke-width='1'/>")
        parts.append(f"<text x='{pad - 4}' y='{yy + 4:.1f}' font-size='11' "
                     "text-anchor='end' fill='var(--text-3)'>"
                     f"{int(y * 100)}%</text>")
    for i, row in enumerate(rows):
        x = pad + i * slot + 1
        top = height
        for key, name, _ in MINUTE_GROUPS:
            share = row.get(key, 0.0)
            h = share * height
            if h < 0.5:
                continue
            top -= h
            parts.append(
                f"<rect x='{x:.1f}' y='{top:.1f}' width='{bar:.1f}' "
                f"height='{max(0.5, h - 1):.1f}' "
                f"fill='{GROUP_COLORS[key]}'><title>{row['minute']}-я "
                f"минута · {_e(name)}: {pct(share)}</title></rect>")
        if n <= 40 or (i + 1) % 5 == 0:
            parts.append(f"<text x='{x + bar / 2:.1f}' y='{height + 16}' "
                         "font-size='10' text-anchor='middle' "
                         f"fill='var(--text-3)'>{row['minute']}</text>")
    parts.append("</svg>")
    legend = "".join(f"<span><i style='background:{GROUP_COLORS[key]}'>"
                     f"</i>{_e(name)}</span>"
                     for key, name, _ in MINUTE_GROUPS)
    return f"<div class='legend'>{legend}</div>" + "".join(parts)


def _visits_table(result: dict) -> str:
    rows = result.get("visits") or []
    if not rows:
        return "<p>Походов на полку и на карту не было.</p>"
    gaze = result.get("gaze_used")
    head = ["№", "экран", "начало", "длилось", "чем кончился", "книга",
            "нужная категория", "поиск"]
    if gaze:
        head += ["категорий (строго / мягко)", "книг", "до нужной категории",
                 "прямая находка", "путь взгляда"]
    out = ["<div class='scroll'><table><tr>"
           + "".join(f"<th>{_e(h)}</th>" for h in head) + "</tr>"]
    titles = result.get("titles") or {}
    for r in rows:
        book = titles.get(r.get("book")) or r.get("book") or ""
        if book and len(book) > 40:
            book = book[:39] + "…"
        outcome = OUTCOME_WORDS.get(r["outcome"], r["outcome"])
        if r.get("via"):
            outcome += f" ({VIA_WORDS.get(r['via'], r['via'])})"
        cells = [
            str(r["n"]), SCREEN_WORDS.get(r["screen"], r["screen"]),
            _clock(r["start_ms"] - result["study_start"]),
            sec(r["duration_ms"]), outcome, book, r.get("target") or "—",
            str(r["searches"]) if r["searches"] else "—",
        ]
        if gaze and "categories_strict" not in r:
            # Чисел зон у похода нет: кадров раскладки нет или окно
            # сменили.
            cells += ["—"] * 5
        elif gaze:
            direct = r.get("direct_strict")
            soft = r.get("direct_soft")
            cells += [
                f"{r.get('categories_strict', 0)} / "
                f"{r.get('categories_soft', 0)}",
                (f"звёзд {r.get('stars_strict', 0)} / "
                 f"{r.get('stars_soft', 0)}" if r["screen"] == "galaxy"
                 else f"{r.get('books_strict', 0)} / "
                 f"{r.get('books_soft', 0)}"),
                f"{sec(r.get('first_target_ms_strict'))} / "
                f"{sec(r.get('first_target_ms_soft'))}",
                f"{_yes(direct)} / {_yes(soft)}",
                " → ".join(r.get("path_soft") or []) or "—",
            ]
        out.append("<tr>" + "".join(f"<td>{_e(c)}</td>" for c in cells)
                   + "</tr>")
    out.append("</table></div>")
    return "".join(out)


def _yes(value) -> str:
    return "—" if value is None else ("да" if value else "нет")


def _clock(ms: float) -> str:
    total = max(0, int(ms // 1000))
    return f"{total // 60:02d}:{total % 60:02d}"


def _shelf_offset(frame: dict) -> float:
    """Прокрутка полки в кадре: `scroll` в сведениях её зоны
    (`library_screen.dart`, `_layoutInfo`)."""
    for region in frame.get("regions") or []:
        if region.get("kind") == "screen" and region.get("id") == "shelf":
            info = region.get("info") or {}
            value = info.get("scroll")
            if isinstance(value, (int, float)) and \
                    not isinstance(value, bool):
                return float(value)
    return 0.0


def _reference_frame(frames: list[dict], start: float,
                     end: float) -> dict | None:
    """Самый устоявшийся кадр похода: дольше всех стоял на экране."""
    best = None
    best_ms = -1.0
    for i, frame in enumerate(frames):
        t = float(frame["t"])
        nxt = float(frames[i + 1]["t"]) if i + 1 < len(frames) else end
        a, b = max(t, start), min(nxt, end)
        if b <= a or frame.get("moving") is True:
            continue
        if b - a > best_ms:
            best, best_ms = frame, b - a
    if best is None:
        for frame in frames:
            if float(frame["t"]) <= start:
                best = frame
    return best


def _hull_path(hull: list, pad: float) -> str:
    """Контур области группы: оболочка звёзд, раздутая на [pad] —
    кругами у вершин и полосами вдоль рёбер, как пишет SVG."""
    if not hull:
        return ""
    if len(hull) == 1:
        x, y = hull[0]
        return (f"<circle cx='{x:.1f}' cy='{y:.1f}' r='{pad:.1f}'/>")
    points = " ".join(f"{x:.1f},{y:.1f}" for x, y in hull)
    return (f"<polygon points='{points}' stroke-width='{2 * pad:.1f}' "
            "stroke-linejoin='round'/>")


def _galaxy_layer(frame: dict, groups: list[dict], target, book,
                  unit: float, pad: float) -> list[str]:
    """Звёзды, области групп и подписи категорий кадра карты."""
    parts = []
    for group in groups:
        # Прозрачность — у группы целиком: заливка и обводка оболочки
        # не складываются в тёмное пятно.
        color = "var(--s-shelf)" if group["name"] == target \
            else "var(--s-reading)"
        shape = _hull_path(group["hull"], pad)
        if shape:
            parts.append(f"<g fill='{color}' stroke='{color}' "
                         f"opacity='0.14'>{shape}</g>")
    for group in groups:
        for x, y, r in group["stars"]:
            parts.append(f"<circle cx='{x:.1f}' cy='{y:.1f}' "
                         f"r='{max(r, 2 * unit):.1f}' fill='var(--text-3)'"
                         " fill-opacity='0.55'/>")
    for region in frame.get("regions") or []:
        if region.get("kind") != "galaxy_map":
            continue
        for mark in region.get("marks") or []:
            if isinstance(mark, dict) and mark.get("id") == book:
                ring = max(mark.get("r", 0), 3 * unit) + 3 * unit
                parts.append(f"<circle cx='{mark.get('x', 0):.1f}' "
                             f"cy='{mark.get('y', 0):.1f}' r='{ring:.1f}'"
                             f" fill='none' stroke='var(--accent)' "
                             f"stroke-width='{2 * unit:.1f}'/>")
    for group in groups:
        label = group["label"]
        if label is None:
            continue
        x, y, w, h = label
        parts.append(f"<rect x='{x:.1f}' y='{y:.1f}' width='{w:.1f}' "
                     f"height='{h:.1f}' fill='var(--surface-2)' "
                     "fill-opacity='0.6' stroke='var(--text-3)' "
                     f"stroke-dasharray='{3 * unit:.1f}' "
                     f"stroke-width='{0.7 * unit:.1f}'/>")
        # Подпись схемы — кеглем схемы над рамкой подписи карты.
        parts.append(f"<text x='{x + w / 2:.1f}' y='{y - 3 * unit:.1f}' "
                     f"font-size='{10 * unit:.1f}' text-anchor='middle' "
                     f"fill='var(--text-2)'>{_e(group['name'])}</text>")
    return parts


def _visit_map(visit: dict, result: dict, frames: list[dict],
               frame_at, groups_of=None) -> str:
    frame = _reference_frame(frames, visit["start_ms"],
                             visit["start_ms"] + visit["duration_ms"])
    if frame is None:
        return ""
    viewport = frame.get("viewport") or {}
    w = float(viewport.get("w") or 1)
    h = float(viewport.get("h") or 1)
    offset = _shelf_offset(frame)
    target = visit.get("target")
    # Рисунок ужимается до ~450 точек: подписи и метки — в долях окна.
    unit = max(w, h) / 450
    parts = [f"<svg viewBox='0 0 {w:.0f} {h:.0f}' role='img' "
             f"aria-label='Схема полки, поход {visit['n']}'>",
             f"<rect width='{w:.0f}' height='{h:.0f}' fill='var(--surface)'"
             " stroke='var(--line)'/>"]
    labels = []
    for region in frame.get("regions") or []:
        rect = region.get("rect")
        if not isinstance(rect, list) or len(rect) != 4:
            continue
        x, y, rw, rh = rect
        kind = region.get("kind")
        if kind == "shelf_category":
            fill = "var(--target)" if region.get("id") == target \
                else "var(--cat)"
            parts.append(f"<rect x='{x}' y='{y}' width='{rw}' "
                         f"height='{rh}' fill='{fill}'/>")
            if (region.get("info") or {}).get("part") == "header":
                labels.append(f"<text x='{x + 4 * unit:.1f}' "
                              f"y='{y + 12 * unit:.1f}' "
                              f"font-size='{11 * unit:.1f}' "
                              "fill='var(--text-2)'>"
                              f"{_e(region.get('id'))}</text>")
        elif kind == "shelf_book":
            if (region.get("info") or {}).get("in") == "results":
                continue
            stroke = "var(--accent)" if region.get("id") == \
                visit.get("book") else "var(--line)"
            width = (2 if region.get("id") == visit.get("book") else 0.7) \
                * unit
            parts.append(f"<rect x='{x}' y='{y}' width='{rw}' "
                         f"height='{rh}' fill='none' stroke='{stroke}' "
                         f"stroke-width='{width}' rx='3'/>")
        elif kind in ("nav", "shelf_search", "shelf_results", "dialog",
                      "galaxy_card"):
            parts.append(f"<rect x='{x}' y='{y}' width='{rw}' "
                         f"height='{rh}' fill='var(--surface-2)' "
                         f"stroke='var(--line)' stroke-width='{unit:.1f}'/>")
    if visit["screen"] == "galaxy" and groups_of is not None:
        pad = float(result.get("map_pad_px") or 0.0)
        parts.extend(_galaxy_layer(frame, groups_of(frame), target,
                                   visit.get("book"), unit, pad))
    parts.extend(labels)
    dots = []
    path = []
    for fix in result["fixations"]:
        if not visit["start_ms"] <= fix["start"] < \
                visit["start_ms"] + visit["duration_ms"] or fix["moving"]:
            continue
        x, y = fix["x"], fix["y"]
        if fix.get("bucket") == "shelf":
            own = frame_at(fix["start"])
            if own is not None:
                y += _shelf_offset(own) - offset
        r = (3 + math.sqrt(max(fix["duration"], 0)) / 8) * unit
        inside = target is not None and fix.get("category") == target
        color = "var(--fix-in)" if inside else "var(--fix-out)"
        path.append(f"{x:.0f},{y:.0f}")
        sure = "уверенно" if fix.get("sure") else "на границе"
        dots.append(f"<circle cx='{x:.1f}' cy='{y:.1f}' r='{r:.1f}' "
                    f"fill='{color}' fill-opacity='0.45' stroke='{color}' "
                    f"stroke-width='{unit:.1f}'>"
                    f"<title>{sec(fix['start'] - visit['start_ms'])} · "
                    f"{sec(fix['duration'])} · "
                    f"{_e(fix.get('category') or fix.get('zone'))} · "
                    f"{sure}</title></circle>")
    if len(path) > 1:
        parts.append(f"<polyline points='{' '.join(path)}' fill='none' "
                     f"stroke='var(--text-3)' stroke-width='{unit:.1f}' "
                     "stroke-opacity='0.6'/>")
    parts.extend(dots)
    parts.append("</svg>")
    book = (result.get("titles") or {}).get(visit.get("book")) or ""
    where = "карта" if visit["screen"] == "galaxy" else "полка"
    caption = (f"Поход {visit['n']} ({where}) · "
               f"{sec(visit['duration_ms'])}"
               + (f" · «{_e(book)}»" if book else "")
               + (f" · нужная категория «{_e(target)}»" if target else ""))
    return f"<figure>{''.join(parts)}<figcaption>{caption}</figcaption>" \
        "</figure>"


def _yes_html(value) -> str:
    if value is None:
        return "—"
    return "<span class='yes'>да</span>" if value else \
        "<span class='no'>нет</span>"


def _presses(result: dict) -> str:
    rows = result.get("presses") or []
    if not rows:
        return "<p>Нажатий по звёздам, книгам полки и строкам найденного " \
            "не было.</p>"
    summary = result.get("press_summary") or {}
    lines = []
    for where, word in (("galaxy", "на карте"), ("shelf", "на полке")):
        p = summary.get(where) or {}
        if not p.get("presses"):
            continue
        text = f"Нажатий {word}: {p['presses']}"
        if p.get("known"):
            text += (f"; нужная категория под взглядом — "
                     f"{p['in_target_soft']} из {p['known']} (строго "
                     f"{p['in_target_strict']})")
            if p.get("lead_ms_soft") is not None:
                text += (f"; была в ней до нажатия — медиана "
                         f"{sec(p['lead_ms_soft'])}")
            if p.get("distance_deg") is not None:
                text += (f"; от взгляда до точки нажатия — медиана "
                         f"{deg(p['distance_deg'])}")
        lines.append(f"<p>{_e(text)}.</p>")
    head = ["№", "время", "экран", "что нажато", "нужная категория",
            "под взглядом", "звезда / книга под взглядом",
            "до точки нажатия", "нужная категория (строго / мягко)",
            "в ней до нажатия"]
    out = ["<div class='scroll'><table><tr>"
           + "".join(f"<th>{_e(h)}</th>" for h in head) + "</tr>"]
    titles = result.get("titles") or {}
    for r in rows:
        name = r.get("title") or r.get("book") or ""
        if len(name) > 40:
            name = name[:39] + "…"
        under = r.get("category")
        if under is not None:
            under += " (уверенно)" if r.get("category_sure") else \
                " (на границе)"
        elif r.get("zone") is not None:
            under = dict(BUCKETS).get(r.get("bucket")) or r.get("zone")
        thing = r.get("star") or r.get("shelf_book")
        thing = titles.get(thing) or thing
        cells = [
            _e(r["n"]), _e(_clock(r["study_ms"])),
            _e(SCREEN_WORDS.get(r["screen"], r["screen"])),
            _e(f"{r['what']} «{name}»"), _e(r.get("target") or "—"),
            _e(under or "—"), _e(thing or "—"),
            _e(deg(r.get("distance_deg"))),
            f"{_yes_html(r.get('in_target_strict'))} / "
            f"{_yes_html(r.get('in_target_soft'))}",
            _e(sec(r.get("lead_ms_soft"))),
        ]
        out.append("<tr>" + "".join(f"<td>{c}</td>" for c in cells)
                   + "</tr>")
    out.append("</table></div>")
    return "".join(lines) + "".join(out)


def _pages(result: dict) -> str:
    books: dict[str, list[dict]] = {}
    for fix in result["fixations"]:
        if fix.get("zone") != "page" or fix["moving"] or \
                not fix.get("page_w") or not fix.get("page_h"):
            continue
        books.setdefault(fix.get("reading") or "?", []).append(fix)
    if not books:
        return "<p>На страницах фиксаций нет.</p>"
    ranked = sorted(books.items(), key=lambda kv: -sum(
        f["duration"] for f in kv[1]))[:MAX_BOOKS]
    figures = []
    titles = result.get("titles") or {}
    for book, fixes in ranked:
        w, h = 200.0, 280.0
        dots = []
        for fix in fixes:
            x = fix["x_pt"] / fix["page_w"] * w
            y = fix["y_pt"] / fix["page_h"] * h
            r = 2 + math.sqrt(max(fix["duration"], 0)) / 8
            color = "var(--text-3)" if fix.get("dimmed") \
                else "var(--fix-in)"
            dots.append(f"<circle cx='{x:.1f}' cy='{y:.1f}' r='{r:.1f}' "
                        f"fill='{color}' fill-opacity='0.35'/>")
        total = sum(f["duration"] for f in fixes)
        name = titles.get(book) or book
        figures.append(
            f"<figure><svg viewBox='0 0 {w:.0f} {h:.0f}' role='img' "
            f"aria-label='Фиксации на страницах книги'>"
            f"<rect width='{w:.0f}' height='{h:.0f}' fill='var(--surface)'"
            f" stroke='var(--line)'/>{''.join(dots)}</svg>"
            f"<figcaption>«{_e(name)}» · фиксаций {len(fixes)} · "
            f"{sec(total)}</figcaption></figure>")
    return f"<div class='maps'>{''.join(figures)}</div>"


def render(result: dict, frames: list[dict], frame_at,
           groups_of=None) -> str:
    """Страница разбора записи."""
    meta = result
    badges = []
    if result.get("gaze_used"):
        cls = "in" if result.get("included") else "out"
        word = "входит в анализ" if result.get("included") else \
            "не входит в анализ взгляда (точность хуже порога)"
        badges.append(f"<span class='badge {cls}'>{_e(word)}</span>")
        badges.append(f"<span class='badge'>версия взгляда: "
                      f"{_e(result.get('version_words'))}</span>")
    else:
        badges.append(f"<span class='badge out'>взгляда нет: "
                      f"{_e(result.get('gaze_reason'))}</span>")
    sub = (f"участник {_e(meta.get('participant') or '—')} · ветвь "
           f"{_e(meta.get('branch') or '—')} · {_e(meta.get('platform'))} "
           f"· сборка {_e(meta.get('app_version') or '—')}"
           + (f" ({_e(meta['study_tag'])})" if meta.get("study_tag")
              else " (проверочная)")
           + f" · изучение {sec(meta.get('study_ms'))}")
    sections = [
        f"<h1>Разбор записи {_e(result['archive'])}</h1>",
        f"<p class='sub'>{sub}</p>", "".join(badges),
    ]
    if result.get("gaze_used"):
        sections += ["<h2>Качество взгляда</h2>", _quality(result)]
    sections += ["<h2>Куда уходило время изучения</h2>",
                 "<p>Строго — в зону идёт только фиксация, уверенно "
                 "лежащая в ней с запасом точности; мягко — и фиксация на "
                 "границе, по своей середине.</p>" if
                 result.get("gaze_used") else "", _shares(result),
                 "<h2>По минутам</h2>", _minutes(result),
                 "<h2>Походы на полку и на карту</h2>",
                 _visits_table(result),
                 "<h2>Перед нажатием</h2>",
                 "<p>На каждое нажатие по звезде карты, книге полки и "
                 "строке найденного — что было под взглядом за 300–100 мс "
                 "до него. Нужная категория — категория нажатой книги; "
                 "«в ней до нажатия» — сколько взгляд уже был в нужной "
                 "категории (не раньше прежнего нажатия того же похода). "
                 "Категория на карте — группа звёзд с её подписью.</p>"
                 if result.get("gaze_used") else "", _presses(result)]
    if result.get("gaze_used") and result.get("layout_known"):
        maps = [_visit_map(v, result, frames, frame_at, groups_of)
                for v in (result.get("visits") or [])
                if v["screen"] in ("shelf", "galaxy")][:MAX_VISIT_MAPS]
        maps = [m for m in maps if m]
        if maps:
            sections += [
                "<h2>Схема полки и карты по походам</h2>",
                "<p>Кадр — тот, что дольше всех стоял за поход; синие — "
                "фиксации в нужной категории, оранжевые — в других; "
                "размер — длительность; линия — порядок. Прокрутка полки "
                "учтена сдвигом. На карте — области групп звёзд и "
                "подписи категорий (пунктир) там, где их ставит карта; "
                "ширина подписи — оценка по числу знаков.</p>",
                f"<div class='maps wide'>{''.join(maps)}</div>"]
        sections += ["<h2>Куда смотрели на странице</h2>",
                     "<p>Все страницы книги наложены на одну; серые — "
                     "вне читаемой полосы.</p>", _pages(result)]
    notes = result.get("notes") or []
    if notes:
        sections += ["<h2>Оговорки</h2><ul class='notes'>"
                     + "".join(f"<li>{_e(n)}</li>" for n in notes)
                     + "</ul>"]
    sections.append("<p class='sub'>Рядом: fixations.csv, visits.csv, "
                    "presses.csv, measures.csv, quality.json.</p>")
    title = f"Разбор записи {_e(result['archive'])}"
    return ("<!doctype html><html lang='ru'><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width, "
            f"initial-scale=1'><title>{title}</title><style>{STYLE}"
            f"</style></head><body><main>{''.join(sections)}</main>"
            "</body></html>")
