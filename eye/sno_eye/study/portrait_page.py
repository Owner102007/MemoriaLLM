"""Шаг 10а — страница портрета участника, рисунки П1–П4 и таблицы
участника (SNO-F-RES-07; шаг 38).

Откуда данные: портрет записи (`study.portrait.prepare`: окна энтропии,
заходы и возвраты `study.dwell`, взгляд назад `study.reading_back`),
возвраты на страницу назад по журналу (`reading_nav` записи), числа
участника (`study.portrait.numbers`), отбор и цвет (`study.compare`).
Технология: matplotlib с бэкендом Agg — как у рисунков отчёта
(`study.charts`: та же палитра, PNG и SVG); `html` и `base64` — страница
без внешних ресурсов, картинки внутри; `csv` — таблицы для Excel.
Метод: SNO-F-RES-07, «Что видит экспериментатор»: лента сессии с
энтропией по ходу, переходами и возвратами в минуту (П1), матрица
переходов между зонами интерфейса (П2), возвраты против поиска без
памяти (П3), взгляд назад при чтении и возвраты на страницу назад
(П4); пометка «не для выводов» у тех, кто вне статистики или со
взглядом хуже 3°; без взгляда — причина и то, что считается без него.
Вход → выход: прогон (`study.analyse`) → `Портреты\\<код>.html` и
`Портреты\\<код>\\` (П1–П4 PNG и SVG, `окна_энтропии.csv`,
`заходы.csv`, `взгляд_назад.csv`); ответ — строки таблицы портретов для
отчёта.
"""

from __future__ import annotations

import base64
import html
from pathlib import Path
from urllib.parse import quote

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Rectangle  # noqa: E402

from ..report.html import STYLE as BASE_STYLE  # noqa: E402
from . import charts, dwell, honesty, portrait, table  # noqa: E402
from .charts import (AXIS, BRANCH, GRID, GROUP_COLOURS, INK, INK_2,  # noqa
                     MUTED, SEQUENTIAL, SURFACE)

FOLDER = "Портреты"
DPI = 150

GROUP_WORDS = {"reading": "чтение", "shelf": "полка и поиск",
               "galaxy": "карта", "off": "вне экрана и вне приложения",
               "other": "прочее"}

STYLE = BASE_STYLE + """
.warn { border-left: 3px solid var(--accent); padding: 8px 12px;
  background: var(--surface-2); margin: 12px 0; border-radius: 4px; }
figure.chart { background: #fcfcfb; }
figure.chart img { display: block; width: 100%; height: auto; }
.later { color: var(--text-3); font-style: italic; }
"""


def _e(value) -> str:
    return html.escape("" if value is None else str(value))


def _num(value, digits: int = 2) -> str:
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "да" if value else "нет"
    if isinstance(value, int):
        return str(value)
    return f"{value:.{digits}f}".replace(".", ",")


def _save(fig, folder: Path, name: str) -> str:
    folder.mkdir(parents=True, exist_ok=True)
    fig.savefig(folder / f"{name}.png", dpi=DPI, bbox_inches="tight")
    fig.savefig(folder / f"{name}.svg", bbox_inches="tight",
                metadata={"Date": None})
    plt.close(fig)
    return f"{name}.png"


def names(entries: list[dict]) -> dict[int, str]:
    """Имя страницы портрета каждой годной записи: код участника; повтор
    кода — с номером (`код_2`), без кода — имя архива."""
    used: dict[str, int] = {}
    out = {}
    for i, e in enumerate(entries):
        if e.get("status") != "ok":
            continue
        base = str(e.get("participant") or e["archive"].rsplit(".", 1)[0])
        used[base] = used.get(base, 0) + 1
        out[i] = base if used[base] == 1 else f"{base}_{used[base]}"
    return out


def caveats(e: dict, cfg: dict) -> list[str]:
    """Почему портрет «не для выводов»: вне статистики, взгляд хуже 3°,
    шум больше общего порога."""
    out = list(e.get("out") or [])
    g = e.get("gaze") or {}
    if g.get("present") and not g.get("included"):
        out.append(f"взгляд не в анализе: {g.get('reason')}")
    if e.get("disorder_gate") and (e.get("gaze_data") or {}):
        out.append(f"шумно: {e['disorder_gate']} — энтропия, заходы и "
                   "переходы не идут в сравнение")
    return out


# --- П1. Лента сессии -------------------------------------------------------

def draw_ribbon(ax, ribbon: list, y: float, height: float) -> None:
    """Лента: отрезки `[от, до, группа]` в секундах — полосой по
    минутам, одной группой рисунка на цвет (`broken_barh`)."""
    by: dict = {}
    for a, b, g in ribbon:
        by.setdefault(g, []).append((a / 60, (b - a) / 60))
    for g, spans in by.items():
        ax.broken_barh(spans, (y, height), color=GROUP_COLOURS.get(g, MUTED),
                       lw=0)


def figure_p1(e: dict, data: dict, folder: Path, noisy: bool) -> str | None:
    ribbon = (data.get("dwell") or {}).get("ribbon") or []
    if not ribbon:
        return None
    study_min = (data.get("study_ms") or 0) / 60_000
    ent = data["entropy"][portrait.SESSION]
    d = data.get("dwell") or {}
    fig = plt.figure(figsize=(11.5, 7.4))
    gs = fig.add_gridspec(4, 1, height_ratios=[0.55, 1.7, 1.0, 1.0],
                          hspace=0.35)
    ax0 = fig.add_subplot(gs[0])
    draw_ribbon(ax0, ribbon, 0, 1)
    for t in data.get("opens") or []:
        ax0.plot([t / 60], [0.82], marker="v", color=INK, ms=4,
                 markeredgecolor=SURFACE, zorder=3)
    ax0.set_xlim(0, max(study_min, 1))
    ax0.set_ylim(0, 1)
    ax0.set_yticks([])
    ax0.grid(False)
    ax0.tick_params(labelbottom=False)
    ax0.set_title("Лента: куда смотрел (▼ — открыл книгу)", loc="left",
                  fontsize=9, pad=4)
    for s in ax0.spines.values():
        s.set_visible(False)

    ax1 = fig.add_subplot(gs[1], sharex=ax0)
    wins = [w for w in ent["windows"] if w["h"] is not None]
    ax1.axhline(1.0, color=MUTED, lw=1, ls="--")
    ax1.text(1.0, 1.0, " случайный взгляд", va="bottom", fontsize=7,
             color=MUTED, transform=ax1.get_yaxis_transform())
    run: list = []
    for w in wins + [None]:
        if w is None or (run and w["long"]):
            if len(run) > 1:
                ax1.plot([r["x"] for r in run], [r["h"] for r in run],
                         color=INK_2, lw=1.0, zorder=2)
            run = [] if w is None else [w]
            continue
        run.append(w)
    if wins:
        ax1.scatter([w["x"] for w in wins], [w["h"] for w in wins], s=14,
                    zorder=3, edgecolors=SURFACE, linewidths=0.6,
                    color=[GROUP_COLOURS.get(w["group"], MUTED)
                           for w in wins])
    ax1.set_ylabel("H_t окна\n(доля от случайного)")
    charts._comma(ax1)
    word = " · ШУМНО, не для выводов" if noisy else ""
    title = (f"Энтропия переходов по ходу сессии: окно — {ent['size']} "
             f"переходов, шаг — {ent['step']}; цвет точки — где было "
             f"окно{word}")
    if not wins:
        title = (f"Энтропия по ходу сессии: переходов {ent['transitions']} "
                 f"— меньше одного окна ({ent['size']})")
    ax1.set_title(title, loc="left", fontsize=9)
    charts._spines(ax1)
    ax1.tick_params(labelbottom=False)

    by = (d.get("ui") or {}).get("by_minute") or {}
    valid = d.get("valid_per_min") or []
    minutes = len(valid)

    def per_valid(counts):
        out = []
        for m in range(minutes):
            v = valid[m] if m < len(valid) else 0
            c = counts[m] if m < len(counts) else 0
            out.append(c / v if v >= 0.1 else 0.0)
        return out

    phase = []
    for m in range(minutes):
        best, key = 0.0, "other"
        for a, b, g in ribbon:
            ov = max(0, min(b, (m + 1) * 60) - max(a, m * 60))
            if ov > best:
                best, key = ov, g
        phase.append(key)
    last = None
    for k, (vals, title) in enumerate((
            (per_valid(by.get("transitions") or []),
             "Переходы между зонами интерфейса, в минуту годного взгляда"),
            (per_valid(by.get("revisits") or []),
             "Возвраты в уже осмотренную зону интерфейса, в минуту "
             "годного взгляда"))):
        ax = fig.add_subplot(gs[2 + k], sharex=ax0)
        if vals:
            ax.bar([m + 0.5 for m in range(minutes)], vals, width=0.86,
                   color=[GROUP_COLOURS.get(p, MUTED) for p in phase], lw=0)
        else:
            ax.text(0.5, 0.5, "зон нет", ha="center", va="center",
                    color=MUTED, transform=ax.transAxes)
        ax.set_title(title, loc="left", fontsize=9)
        ax.grid(axis="x", visible=False)
        charts._spines(ax)
        if k == 0:
            ax.tick_params(labelbottom=False)
        last = ax
    last.set_xlabel("минута изучения")
    handles = [Rectangle((0, 0), 1, 1, color=GROUP_COLOURS[k],
                         label=GROUP_WORDS[k]) for k in GROUP_COLOURS]
    fig.legend(handles=handles, loc="lower center", ncol=5, fontsize=7.5,
               bbox_to_anchor=(0.5, 0.0))
    fig.suptitle(f"П1. Портрет участника {e.get('participant')} (ветвь "
                 f"{e.get('branch')}): лента сессии", x=0.01, ha="left",
                 fontweight="bold", color=INK)
    fig.subplots_adjust(left=0.08, right=0.94, top=0.92, bottom=0.11)
    return _save(fig, folder, "П1_лента_сессии")


# --- П2. Матрица переходов -------------------------------------------------

def figure_p2(e: dict, data: dict, folder: Path) -> str | None:
    import numpy as np
    d = data.get("dwell") or {}
    ui = d.get("ui") or {}
    m = ui.get("matrix")
    if not m or not any(any(r) for r in m):
        return None
    arr = np.array(m, dtype=float)
    keep = [i for i in range(len(arr)) if arr[i].sum() or arr[:, i].sum()]
    arr = arr[np.ix_(keep, keep)]
    labels = [dwell.UI_WORDS[dwell.UI_KEYS[i]] for i in keep]
    rows = arr.sum(axis=1, keepdims=True)
    with np.errstate(invalid="ignore", divide="ignore"):
        p = np.where(rows > 0, arr / np.where(rows > 0, rows, 1), 0.0)
    fig, ax = plt.subplots(figsize=(7.2, 5.6))
    ax.imshow(p, cmap=SEQUENTIAL, vmin=0, vmax=1)
    for i in range(len(keep)):
        for j in range(len(keep)):
            if arr[i, j]:
                ax.text(j, i, f"{int(arr[i, j])}", ha="center", va="center",
                        fontsize=8, color=SURFACE if p[i, j] > 0.55 else INK)
    ax.set_xticks(range(len(keep)))
    ax.set_xticklabels(labels, rotation=35, ha="right")
    ax.set_yticks(range(len(keep)))
    ax.set_yticklabels(labels)
    ax.set_xlabel("куда")
    ax.set_ylabel("откуда")
    ax.grid(False)
    valid = d.get("valid_min") or 0
    per = ui.get("transitions", 0) / valid if valid > 0 else None
    ax.set_title(f"П2. Переходы между зонами интерфейса\nчисло — в клетке, "
                 f"доля строки — цветом\n{ui.get('transitions', 0)} "
                 f"переходов · {_num(per, 1)} в минуту годного взгляда · "
                 f"плотность {_num(ui.get('density'))}", loc="left",
                 fontsize=9)
    fig.tight_layout()
    return _save(fig, folder, "П2_переходы")


# --- П3. Возвраты ------------------------------------------------------------

def figure_p3(e: dict, data: dict, folder: Path) -> str | None:
    d = data.get("dwell") or {}
    if not d.get("ui"):
        return None
    colour = BRANCH.get(e.get("branch"), INK_2)
    # Интерфейс — в заголовке, а не точкой: к странице возвращаются
    # всегда, и его сотни возвратов сжали бы шкалу остальных.
    rows = []
    cat = d.get("cat") or {}
    rows.append(("категории в поиске — все", cat.get("revisits"), None))
    for name, own in sorted((cat.get("zones") or {}).items(),
                            key=lambda kv: (-kv[1]["revisits"], kv[0]))[:6]:
        rows.append((f"  из них в «{name}»", own["revisits"], None))
    if cat.get("trips_vs"):
        rows.append((f"категории: походы, где видно ≥ "
                     f"{dwell.MIN_VISIBLE} ({cat['trips_vs']})",
                     cat.get("observed_vs"), cat.get("expected")))
    book = d.get("book") or {}
    rows.append(("книги и звёзды до выбора — все", book.get("revisits"),
                 None))
    if book.get("trips_vs"):
        rows.append((f"книги: походы, где видно ≥ {dwell.MIN_VISIBLE} "
                     f"({book['trips_vs']})", book.get("observed_vs"),
                     book.get("expected")))
    fig, ax = plt.subplots(figsize=(8.6, 0.55 * len(rows) + 1.6))
    top = max([r[1] or 0 for r in rows] + [r[2] or 0 for r in rows] + [1])
    for i, (name, obs, exp) in enumerate(rows):
        y = len(rows) - 1 - i
        obs = obs or 0
        if exp is not None:
            ax.plot([obs, exp], [y, y], color=GRID, lw=2, zorder=1)
            ax.scatter([exp], [y], s=44, facecolors=SURFACE,
                       edgecolors=INK_2, linewidths=1.2, zorder=3)
        ax.scatter([obs], [y], s=44, color=colour, zorder=3,
                   edgecolors=SURFACE, linewidths=1.2)
        if exp:
            note = f"{obs} (без памяти ≈ {_num(exp, 1)}; " \
                   f"{_num(obs / exp)})"
        else:
            note = str(obs)
        ax.text(max(obs, exp or 0) + top * 0.02, y, note, va="center",
                fontsize=7.5, color=INK_2)
    ax.set_yticks(range(len(rows)))
    ax.set_yticklabels([r[0] for r in rows][::-1])
    ax.set_xlim(0, top * 1.6)
    ax.set_xlabel("возвратов за изучение")
    ax.grid(axis="y", visible=False)
    ui = d["ui"]
    ax.set_title(f"П3. Возвраты в уже осмотренную зону поиска; ○ — сколько "
                 "ожидалось при поиске без памяти\n(Peterson и др., 2001): "
                 "меньше ожидаемого — помнит, где уже смотрел. Интерфейс: "
                 f"{ui['revisits']} возвратов из {ui['entries']} заходов "
                 "(без ожидания: к странице возвращаются всегда)",
                 loc="left", fontsize=9)
    charts._spines(ax)
    fig.tight_layout()
    return _save(fig, folder, "П3_возвраты")


# --- П4. Чтение: взгляд назад ---------------------------------------------

def reading_axis(look: dict) -> list[tuple[float, float, float]]:
    """Ось «секунды чтения»: показы страницы встык, без промежутков
    между ними — `(начало, конец, место начала на оси)`."""
    out = []
    x = 0.0
    for s in sorted(look.get("shows") or [], key=lambda s: s["t0"] or 0):
        if s["t0"] is None or s["t1"] is None:
            continue
        out.append((s["t0"], s["t1"], x))
        x += (s["t1"] - s["t0"]) / 1000
    return out


def _on_axis(axis: list, t: float) -> float | None:
    """Миг записи → место на оси чтения; между показами — начало
    следующего показа."""
    for a, b, x in axis:
        if t < a:
            return x
        if t <= b:
            return x + (t - a) / 1000
    return axis[-1][2] + (axis[-1][1] - axis[-1][0]) / 1000 if axis \
        else None


def figure_p4(e: dict, data: dict, folder: Path) -> str | None:
    """Глубина взгляда на странице по секундам чтения (показы встык),
    эпизоды взгляда назад — закрашены и отмечены ▲, возвраты на страницу
    назад по журналу — ◄."""
    look = data.get("lookback") or {}
    nav = e.get("reading_nav") or {}
    points = look.get("points") or []
    backs = [r for r in nav.get("rows") or [] if r["kind"] == "назад"]
    if not points and not backs and not nav.get("reading_min"):
        return None
    colour = BRANCH.get(e.get("branch"), INK_2)
    axis = reading_axis(look)
    if not axis or not points:
        return _p4_journal(e, look, nav, folder)
    fig, ax = plt.subplots(figsize=(11.0, 4.2))
    shows: dict = {}
    for p in points:
        if p["depth"] is not None:
            shows.setdefault(p["show"], []).append(p)
    for own in shows.values():
        xs = [_on_axis(axis, p["t"]) for p in own]
        ys = [p["depth"] * 100 for p in own]
        ax.plot(xs, ys, color=INK_2, lw=0.6)
        ax.scatter(xs, ys, s=3, color=INK_2)
    for a, _, x in axis:
        ax.axvline(x, color=GRID, lw=0.6, zorder=0)
    for ep in look.get("episodes") or []:
        x0, x1 = _on_axis(axis, ep["t0"]), _on_axis(axis, ep["t1"])
        ax.axvspan(x0, x1, color=colour, alpha=0.3, lw=0)
        ax.text(x0, -7, "▲", ha="center", va="center", fontsize=7,
                color=colour)
    if axis:
        for r in backs:
            ax.text(_on_axis(axis, r["t"]), -2, "◄", ha="center",
                    va="center", fontsize=8, color=INK)
    ax.set_ylim(102, -10)
    ax.set_ylabel("место на странице, % высоты\n(верх — 0)")
    ax.set_xlabel("секунды чтения (показы страниц встык; тонкая линия — "
                  "новый показ)")
    ax.grid(axis="x", visible=False)
    if look.get("reason"):
        head = f"взгляда назад по тексту нет: {look['reason']}"
    else:
        head = (f"{look.get('count', 0)} взглядов назад (▲; "
                f"{_num(look.get('per_min'))} в минуту чтения, "
                f"{_num((look.get('share') or 0) * 100, 0)} % времени "
                f"чтения; порог {_num(look.get('L_deg'), 1)}°)")
    ax.set_title(f"П4. Чтение: {head};\nвозвратов на страницу назад "
                 f"{nav.get('backs', 0)} (◄), промахов листания "
                 f"{nav.get('misflips', 0)}, переходов назад по оглавлению "
                 f"и найденному {nav.get('navigation', 0)}", loc="left",
                 fontsize=9)
    charts._spines(ax)
    fig.tight_layout()
    return _save(fig, folder, "П4_чтение_назад")


def _p4_journal(e: dict, look: dict, nav: dict, folder: Path) -> str:
    """П4 без взгляда на странице: возвраты на страницу назад,
    промахи листания и навигация назад — по журналу, по минутам
    изучения."""
    lo = e.get("study_start") or 0.0
    kinds = (("назад", "на страницу назад", "<"),
             ("промах листания", "промах листания", "x"),
             ("навигация", "навигация назад", "o"))
    fig, ax = plt.subplots(figsize=(11.0, 2.6))
    for y, (kind, _, marker) in enumerate(kinds):
        xs = [(r["t"] - lo) / 60_000 for r in nav.get("rows") or []
              if r["kind"] == kind]
        ax.scatter(xs, [y] * len(xs), marker=marker, s=26, color=INK_2,
                   linewidths=1.2)
    ax.set_yticks(range(len(kinds)))
    ax.set_yticklabels([w for _, w, _ in kinds])
    ax.set_ylim(-0.6, len(kinds) - 0.4)
    ax.set_xlim(0, max(1.0, (e.get("study_ms") or 0) / 60_000))
    ax.set_xlabel("минута изучения")
    ax.grid(axis="y", visible=False)
    why = look.get("reason") or "взгляда на странице нет"
    ax.set_title(f"П4. Чтение: взгляда назад по тексту нет — {why};\n"
                 f"по журналу: возвратов на страницу назад "
                 f"{nav.get('backs', 0)} ({_num(nav.get('per_min'))} в "
                 f"минуту чтения), промахов листания "
                 f"{nav.get('misflips', 0)}, навигации назад "
                 f"{nav.get('navigation', 0)}", loc="left", fontsize=9)
    charts._spines(ax)
    fig.tight_layout()
    return _save(fig, folder, "П4_чтение_назад")


# --- таблицы участника -------------------------------------------------------

def _csv_windows(data: dict, path: Path) -> None:
    rows = []
    for name in portrait.SERIES:
        own = data["entropy"][name]
        for w in own["windows"]:
            rows.append([portrait.SERIES_WORDS[name], w["i"],
                         w["from"] + 1, w["to"], w["x"],
                         "мин поиска" if name == portrait.SEARCH
                         else "мин изучения", w["h_raw"], w["h"],
                         w["h_order"], GROUP_WORDS.get(w["group"]),
                         w["long"]])
    table.write(path, ["ряд", "№ окна", "переходы с", "по", "место на оси",
                       "ось", "H_t, бит", "H_t, доля случайного",
                       "H_t, доля перемешанного", "где было окно",
                       "растянуто через паузу"], rows)


def _csv_dwell(data: dict, path: Path) -> None:
    d = data.get("dwell") or {}
    rows = []
    for level, words in (("ui", "интерфейс"), ("cat", "категории в поиске"),
                         ("book", "книги и звёзды в поиске"),
                         ("page", "страницы в чтении")):
        own = d.get(level) or {}
        for zone, z in sorted((own.get("zones") or {}).items()):
            name = dwell.UI_WORDS.get(zone, zone) if level == "ui" else zone
            rows.append([words, name, None, z["entries"], z["revisits"],
                         z["time_ms"] / 1000, None, None])
    for t in d.get("trips") or []:
        rows.append(["поход за книгой", "категории", t["n"],
                     t["cat_entries"], t["cat_revisits"], None,
                     t["cat_visible"], t["cat_expected"]])
        rows.append(["поход за книгой", "книги и звёзды", t["n"],
                     t["book_entries"], t["book_revisits"], None,
                     t["book_visible"], t["book_expected"]])
    table.write(path, ["уровень", "зона", "№ похода", "заходов", "возвратов",
                       "время, с", "видно зон", "ожидалось возвратов без "
                       "памяти"], rows)


def _csv_back(e: dict, data: dict, path: Path) -> None:
    lo = e.get("study_start") or 0.0
    rows = []
    for ep in (data.get("lookback") or {}).get("episodes") or []:
        rows.append(["взгляд назад", (ep["t0"] - lo) / 1000,
                     (ep["t1"] - ep["t0"]) / 1000, ep["page"], None,
                     ep["fixations"], ep["jump_deg"], ep["up_share"],
                     ep["old_column"], None])
    for r in (e.get("reading_nav") or {}).get("rows") or []:
        rows.append([r["kind"], (r["t"] - lo) / 1000, None, r["page"],
                     r["from_page"], None, None, None, None,
                     r["cause"]])
    rows.sort(key=lambda r: r[1])
    table.write(path, ["что", "от начала изучения, с", "длилось, с",
                       "страница", "откуда", "фиксаций", "скачок, °",
                       "вверх, доля высоты страницы", "в прежнюю колонку",
                       "чем листал"], rows)


# --- страница ----------------------------------------------------------------

NUMBER_ROWS = (
    ("portrait.search_slope", "Энтропия поиска по ходу: наклон, в минуту "
     "поиска"),
    ("portrait.reading_slope", "Энтропия чтения по ходу: наклон, за 10 мин"),
    ("portrait.search_iqr", "Разброс энтропии окон поиска (межквартильный)"),
    ("portrait.reading_iqr", "Разброс энтропии окон чтения"),
    ("portrait.ui_trans_per_min", "Переходы между зонами интерфейса, в "
     "минуту годного взгляда"),
    ("portrait.ui_density", "Плотность матрицы переходов"),
    ("portrait.cat_trans_per_min", "Переходы между категориями, в минуту "
     "поиска"),
    ("portrait.cat_return_share", "Возвраты в категории, доля заходов"),
    ("portrait.cat_return_ratio", "Возвраты в категории: было / без памяти"),
    ("portrait.book_ratio", "Возвраты к книгам: было / без памяти"),
    ("portrait.page_revisit_share", "Возвраты к страницам, доля заходов"),
    ("portrait.lookbacks_per_min", "Взгляды назад при чтении, в минуту"),
    ("portrait.lookback_share", "Доля чтения во взглядах назад"),
    ("portrait.lookback_jump_deg", "Скачок назад, медиана, °"),
    ("portrait.shows_with_back", "Доля показов страницы со взглядом назад"),
    ("portrait.page_backs_per_min", "Возвраты на страницу назад, в минуту "
     "чтения"),
    ("portrait.misflips", "Промахов листания"),
)


def _img(folder: Path, name: str | None, caption: str, sub: str) -> str:
    if not name:
        return f"<p class='later'>{_e(caption)}: данных для рисунка нет.</p>"
    data = (folder / name).read_bytes()
    src = "data:image/png;base64," + base64.b64encode(data).decode("ascii")
    return (f"<figure class='chart'><img src='{src}' alt='{_e(caption)}'>"
            f"<figcaption>{_e(caption)} · файлы — "
            f"<a href='{_e(quote(sub + '/' + name))}'>PNG</a> и "
            f"<a href='{_e(quote(sub + '/' + name[:-4] + '.svg'))}'>SVG"
            "</a></figcaption></figure>")


def page(e: dict, data: dict | None, numbers: dict, figures: dict,
         sub: str, folder: Path, cfg: dict) -> str:
    """Страница портрета одного участника."""
    marks = caveats(e, cfg)
    g = e.get("gaze") or {}
    head = (f"<p class='sub'>Ветвь {_e(e.get('branch'))} · ПК "
            f"{_e(e.get('stratum'))} · "
            f"{_e(honesty.WORDS.get(e.get('colour')))} · "
            + ("в статистике" if e.get("in_stats") else "вне статистики")
            + f" · изучение {_num((e.get('study_s') or 0) / 60, 1)} мин</p>")
    if g.get("present"):
        head += (f"<p>Взгляд: точность в начале {_num(g.get('start_deg'), 1)}"
                 f"°, в конце {_num(g.get('end_deg'), 1)}°, прецизионность "
                 f"{_num(g.get('precision_deg'), 1)}° · "
                 + ("в анализе" if g.get("included") else "не в анализе")
                 + "</p>")
    warn = ""
    if marks:
        warn = ("<div class='warn'><b>Не для выводов</b><ul>" + "".join(
            f"<li>{_e(m)}</li>" for m in marks) + "</ul></div>")
    body = []
    if data is None:
        why = g.get("reason") or "причина не названа"
        body.append(f"<p>Взгляда нет: {_e(why)}. Ниже — то, что считается "
                    "без взгляда: возвраты на страницу назад по журналу.</p>")
    else:
        d = data.get("dwell") or {}
        if d.get("reason"):
            body.append(f"<p class='later'>Заходов и переходов нет: "
                        f"{_e(d['reason'])}.</p>")
        body.append(_img(folder, figures.get("П1"), "П1. Лента сессии",
                         sub))
        body.append(_img(folder, figures.get("П2"),
                         "П2. Переходы между зонами интерфейса", sub))
        body.append(_img(folder, figures.get("П3"), "П3. Возвраты", sub))
    body.append(_img(folder, figures.get("П4"),
                     "П4. Взгляд назад при чтении и возвраты на страницу",
                     sub))
    rows = "".join(
        f"<tr><td>{_e(words)}</td><td class='num'>{_num(numbers.get(key))}"
        "</td></tr>" for key, words in NUMBER_ROWS
        if numbers.get(key) is not None)
    reason = numbers.get("portrait.lookback_reason")
    note = (f"<p class='later'>Взгляд назад по тексту: {_e(reason)}.</p>"
            if reason else "")
    files = "".join(
        f"<li><a href='{_e(quote(sub + '/' + n))}'>{_e(n)}</a></li>"
        for n in ("окна_энтропии.csv", "заходы.csv", "взгляд_назад.csv")
        if (folder / n).exists())
    return f"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Портрет {_e(e.get('participant'))}</title>
<style>{STYLE}</style></head>
<body><main>
<p><a href="../index.html">← к отчёту «Сравнение ветвей»</a></p>
<h1>Портрет участника {_e(e.get('participant'))}</h1>
{head}{warn}
<p>Числа одного участника, без сравнения с другими. Что значит каждая
мера и в какую сторону «больше» — раздел «Как читать» отчёта; в
сравнение ветвей числа портрета идут семьёй «Д. Портрет» (раздел 8
отчёта) по прежним правилам отбора.</p>
{"".join(body)}
<h2>Числа</h2>
<div class='scroll'><table><tr><th>Мера</th><th class='num'>Значение</th>
</tr>{rows}</table></div>
{note}
<h2>Таблицы участника</h2><ul>{files}</ul>
</main></body></html>
"""


def write_all(run: dict, folder: Path) -> list[dict]:
    """Портреты всех годных записей; ответ — строки таблицы портретов
    отчёта (код, ветвь, ПК, цвет, ключевые числа, ссылка)."""
    root = folder / FOLDER
    root.mkdir(parents=True, exist_ok=True)
    cfg = run["cfg"]
    out = []
    for i, name in names(run["entries"]).items():
        e = run["entries"][i]
        data = (e.get("gaze_data") or {}).get("portrait")
        sub = name
        own = root / sub
        own.mkdir(parents=True, exist_ok=True)
        figures: dict = {}
        noisy = bool(e.get("disorder_gate")) and data is not None
        if data is not None:
            figures["П1"] = figure_p1(e, data, own, noisy)
            figures["П2"] = figure_p2(e, data, own)
            figures["П3"] = figure_p3(e, data, own)
            _csv_windows(data, own / "окна_энтропии.csv")
            _csv_dwell(data, own / "заходы.csv")
        figures["П4"] = figure_p4(e, data or {}, own)
        _csv_back(e, data or {}, own / "взгляд_назад.csv")
        numbers = portrait.numbers(e)
        text = page(e, data, numbers, figures, sub, own, cfg)
        (root / f"{name}.html").write_text(text, encoding="utf-8")
        out.append({"name": name, "entry": e, "numbers": numbers,
                    "marks": caveats(e, cfg),
                    "link": f"{FOLDER}/{name}.html"})
    return out
