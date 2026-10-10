"""Шаг 10 — рисунки Р1–Р5, Р13, Р14 (SNO-F-RES-06, «Рисунки»).

Откуда данные: записи после отбора (`study.compare.admit`) и итог
сравнения (`study.compare.run`): точки участников с весами, средние
ветвей с интервалом, δ с интервалом, сценарии устойчивости.
Технология: matplotlib с бэкендом Agg — рисует без окна, на ПК
организатора и на раннере CI одинаково; PNG — 200 точек на дюйм,
SVG — с путями букв (шрифт на чужом ПК не нужен). Шрифт — DejaVu Sans
из самого matplotlib: в нём есть кириллица, сеть и системные шрифты не
нужны.
Метод: цвета — проверенная палитра по умолчанию (навык dataviz): ветвь
I — синий `#2a78d6`, ветвь II — оранжевый `#eb6834`; искренность —
цвета статуса с подписью словами. **Цвет искренности дублируется
формой точки**: 🟢 — закрашенный круг, 🟡 и ⚪ — полый круг, 🔴 — крестик
(только там, где красные идут в счёт: сценарий S3 и проверочный
прогон). Так различие видно и на чёрно-белой печати, и людям с
нарушением цветового зрения. Тонкие отметки, сетка — волосяная.
Вход → выход: прогон (`study.analyse`) → файлы `рисунки/Р*.png` и
`*.svg`; ответ — номер рисунка → (подпись, имя PNG).
"""

from __future__ import annotations

import hashlib
import textwrap
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Rectangle  # noqa: E402
from matplotlib.ticker import FuncFormatter  # noqa: E402

from . import compare, honesty  # noqa: E402
from .collect import (ETALON_NO, ETALON_NOT_RESET, ETALON_UNKNOWN,  # noqa
                      ETALON_YES)

# --- палитра (dataviz, references/palette.md) -------------------------

SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"
BRANCH = {"I": "#2a78d6", "II": "#eb6834"}
# Второе сравнение — способ поиска: те же два первых места палитры.
GROUP = {"II": BRANCH["II"], "I": BRANCH["I"],
         "картой": BRANCH["II"], "полкой": BRANCH["I"]}
STATUS = {honesty.GREEN: "#0ca30c", honesty.YELLOW: "#fab219",
          honesty.UNKNOWN: "#b9b7b0", honesty.RED: "#d03b3b"}
STATUS_WORDS = {honesty.GREEN: "зелёный — искренен",
                honesty.YELLOW: "жёлтый — один пункт провален",
                honesty.UNKNOWN: "неизвестно — нет ответа",
                honesty.RED: "красный — оба провалены"}
NEUTRAL = {"in": "#2a78d6", "bad": "#b9b7b0", "none": "#e1e0d9"}

DPI = 200

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 9,
    "axes.edgecolor": AXIS,
    "axes.labelcolor": INK_2,
    "axes.titlesize": 10,
    "axes.titleweight": "bold",
    "axes.titlecolor": INK,
    "axes.facecolor": SURFACE,
    "axes.grid": True,
    "axes.axisbelow": True,
    "grid.color": GRID,
    "grid.linewidth": 0.6,
    "xtick.color": INK_2,
    "ytick.color": INK_2,
    "figure.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "legend.frameon": False,
    "svg.hashsalt": "sno2026-study",
})


def _save(fig, folder: Path, name: str) -> str:
    folder.mkdir(parents=True, exist_ok=True)
    fig.savefig(folder / f"{name}.png", dpi=DPI, bbox_inches="tight")
    fig.savefig(folder / f"{name}.svg", bbox_inches="tight",
                metadata={"Date": None})
    plt.close(fig)
    return f"{name}.png"


def _spines(ax) -> None:
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)


# Дробная часть — через запятую, как в таблицах и отчёте.
_COMMA = FuncFormatter(lambda v, _: f"{v:g}".replace(".", ",")
                       .replace("-", "−"))


def _comma(ax, which: str = "y") -> None:
    """Числовые подписи оси [which] — с запятой. Только у числовых осей:
    у осей с подписями-словами форматер заменил бы слова."""
    (ax.yaxis if which == "y" else ax.xaxis).set_major_formatter(_COMMA)


def _wrap(text: str, width: int = 30) -> str:
    return "\n".join(textwrap.wrap(text, width)) or text


def _jitter(code: str, spread: float = 0.12) -> float:
    """Сдвиг точки вбок — от кода участника, а не от случая: рисунок
    одинаков при каждом прогоне."""
    h = int(hashlib.sha256(str(code).encode()).hexdigest()[:8], 16)
    return (h / 0xFFFFFFFF - 0.5) * 2 * spread


def _marker(colour: str | None, edge: str) -> dict:
    """Форма точки по цвету искренности."""
    if colour == honesty.RED:
        return {"marker": "x", "color": edge, "s": 36, "linewidths": 1.6}
    if colour in (honesty.YELLOW, honesty.UNKNOWN):
        return {"marker": "o", "facecolors": SURFACE, "edgecolors": edge,
                "s": 36, "linewidths": 1.4}
    return {"marker": "o", "color": edge, "s": 36, "edgecolors": SURFACE,
            "linewidths": 1.0}


def _shape_legend(red: str = "🔴 красный (только S3 и проверочный "
                  "прогон)") -> list:
    return [
        Line2D([], [], marker="o", ls="", color=INK_2, label="🟢 зелёный",
               markersize=6),
        Line2D([], [], marker="o", ls="", markerfacecolor=SURFACE,
               markeredgecolor=INK_2, label="🟡 жёлтый и ⚪ неизвестно",
               markersize=6),
        Line2D([], [], marker="x", ls="", color=INK_2, label=red,
               markersize=6),
    ]


def _labels_safe(labels: list) -> list:
    # DejaVu Sans не знает значков: в подписи рисунка — только слова.
    for item in labels:
        text = item.get_label()
        for mark in ("🟢 ", "🟡 ", "⚪ ", "🔴 "):
            text = text.replace(mark, "")
        item.set_label(text)
    return labels


# --- Р1. Состав выборки -------------------------------------------------

def figure_1(run: dict, folder: Path) -> str:
    entries = [e for e in run["entries"] if e["status"] == "ok"]
    branches = ["I", "II"]
    fig, axes = plt.subplots(1, 3, figsize=(10.5, 3.0), sharey=True)
    panels = (
        ("Искренность", [
            (honesty.GREEN, STATUS[honesty.GREEN], "зелёный"),
            (honesty.YELLOW, STATUS[honesty.YELLOW], "жёлтый"),
            (honesty.UNKNOWN, STATUS[honesty.UNKNOWN], "неизвестно"),
            (honesty.RED, STATUS[honesty.RED], "красный")],
         lambda e: e.get("colour")),
        ("Взгляд", [
            ("in", NEUTRAL["in"], "в анализе (≤ 3°)"),
            ("bad", NEUTRAL["bad"], "хуже 3° или неизвестен"),
            ("none", NEUTRAL["none"], "не записан")],
         lambda e: "in" if e["gaze"]["included"] else
         ("bad" if e["gaze"]["present"] else "none")),
        ("Эталон на старте", [
            (ETALON_YES, "#0ca30c", "да"), (ETALON_NO, "#fab219", "нет"),
            (ETALON_NOT_RESET, "#d03b3b", "не сброшено"),
            (ETALON_UNKNOWN, "#b9b7b0", "неизвестно")],
         lambda e: e.get("etalon")),
    )
    for ax, (title, parts, key) in zip(axes, panels):
        left = [0, 0]
        for code, color, word in parts:
            counts = [sum(1 for e in entries if e.get("branch") == b
                          and key(e) == code) for b in branches]
            ax.barh(branches, counts, left=left, color=color,
                    edgecolor=SURFACE, linewidth=2, height=0.5, label=word)
            for i, c in enumerate(counts):
                if c:
                    ax.text(left[i] + c / 2, i, str(c), ha="center",
                            va="center", fontsize=8,
                            color=INK if color in ("#fab219", "#b9b7b0",
                                                   "#e1e0d9", "#0ca30c")
                            else "white")
            left = [a + b for a, b in zip(left, counts)]
        ax.set_title(title, loc="left")
        ax.grid(axis="y", visible=False)
        ax.xaxis.get_major_locator().set_params(integer=True)
        _comma(ax, "x")
        ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.18),
                  ncol=2, fontsize=7.5, handlelength=1)
        _spines(ax)
    axes[0].set_ylabel("ветвь")
    out = sum(1 for e in run["entries"] if e["status"] != "ok")
    fig.suptitle("Р1. Состав выборки" + (f" (не годны архивов: {out})"
                                         if out else ""),
                 x=0.01, ha="left", fontweight="bold", color=INK)
    fig.tight_layout()
    return _save(fig, folder, "Р1_состав")


# --- Р2. Шкала лжи ------------------------------------------------------

def figure_2(run: dict, folder: Path) -> str:
    fig, ax = plt.subplots(figsize=(8.4, 4.8))
    # Зоны цвета: lie.defer ≤ 3 — провален, lie.late ≥ 5 — провален
    # (`flag` пунктов в сценарии, АК2).
    zones = [
        (0.5, 3.5, 4.5, 7.5, STATUS[honesty.RED]),
        (0.5, 3.5, 0.5, 4.5, STATUS[honesty.YELLOW]),
        (3.5, 7.5, 4.5, 7.5, STATUS[honesty.YELLOW]),
        (3.5, 7.5, 0.5, 4.5, STATUS[honesty.GREEN]),
    ]
    for x0, x1, y0, y1, color in zones:
        ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, color=color,
                               alpha=0.12, lw=0))
    ax.text(2.0, 7.25, "оба провалены", ha="center", fontsize=7.5,
            color=INK_2)
    ax.text(5.5, 4.25, "ни один не провален", ha="center", fontsize=7.5,
            color=INK_2)
    for e in run["entries"]:
        if e["status"] != "ok":
            continue
        lie = e["test"]["lie"]
        x = lie.get("lie.defer", {}).get("value")
        y = lie.get("lie.late", {}).get("value")
        if x is None or y is None:
            continue
        code = str(e.get("participant"))
        colour = e.get("colour")
        style = _marker(colour, BRANCH.get(e.get("branch"), INK_2))
        if colour == honesty.RED:
            style = {"marker": "x", "color": BRANCH.get(e.get("branch"),
                                                       INK_2),
                     "s": 40, "linewidths": 1.6}
        ax.scatter(x + _jitter(code, 0.25), y + _jitter(code[::-1], 0.25),
                   zorder=3, **style)
    ax.set_xlim(0.5, 7.5)
    ax.set_ylim(0.5, 7.5)
    ax.set_aspect("equal")
    ax.set_xticks(range(1, 8))
    ax.set_yticks(range(1, 8))
    ax.set_xlabel("lie.defer «Мне случалось откладывать…» (провал — 1–3)")
    ax.set_ylabel("lie.late «Ни разу не опоздал» (провал — 5–7)")
    handles = [Line2D([], [], marker="o", ls="", color=BRANCH[b],
                      label=f"ветвь {b}") for b in ("I", "II")]
    handles += _labels_safe(_shape_legend("🔴 красный — вне статистики"))
    ax.legend(handles=handles, loc="upper left", bbox_to_anchor=(1.02, 1),
              fontsize=7.5)
    ax.set_title("Р2. Шкала лжи и цвет искренности", loc="left")
    _spines(ax)
    fig.tight_layout()
    return _save(fig, folder, "Р2_шкала_лжи")


# --- Р3. Качество взгляда по ПК ----------------------------------------

def figure_3(run: dict, folder: Path) -> str | None:
    rows = [e for e in run["entries"] if e["status"] == "ok"
            and e["gaze"]["present"]]
    if not rows:
        return None
    rows.sort(key=lambda e: (e["stratum"], e.get("branch") or "",
                             str(e.get("participant"))))
    limit = float(run["limits"]["include_deg"])
    fig, ax = plt.subplots(figsize=(max(5.0, 0.42 * len(rows) + 2), 3.6))
    top = limit
    for i, e in enumerate(rows):
        g = e["gaze"]
        color = BRANCH.get(e.get("branch"), INK_2)
        a, b = g.get("start_deg"), g.get("end_deg")
        if a is not None and b is not None:
            ax.plot([i, i], [a, b], color=color, lw=2, solid_capstyle="round",
                    zorder=2)
        if a is not None:
            ax.scatter([i], [a], marker="o", facecolors=SURFACE,
                       edgecolors=color, s=34, linewidths=1.4, zorder=3)
        if b is not None:
            ax.scatter([i], [b], marker="o", color=color, s=34,
                       edgecolors=SURFACE, zorder=3)
        top = max(top, a or 0, b or 0)
    ax.axhline(limit, color=INK_2, lw=1)
    ax.text(-0.6, limit, f"{limit:.0f}° — порог взгляда",
            va="bottom", ha="left", fontsize=7.5, color=INK_2)
    # Подписи ПК — группами под осью.
    groups: dict[str, list[int]] = {}
    for i, e in enumerate(rows):
        groups.setdefault(e["stratum"], []).append(i)
    for name, idx in groups.items():
        lo, hi = idx[0], idx[-1]
        if lo > 0:
            ax.axvline(lo - 0.5, color=GRID, lw=1)
        ax.text((lo + hi) / 2, 1.0, name, transform=ax.get_xaxis_transform(),
                ha="center", va="bottom", fontsize=7.5, color=INK_2)
    ax.set_xticks(range(len(rows)))
    ax.set_xticklabels([str(e.get("participant")) for e in rows],
                       rotation=90, fontsize=6.5)
    ax.set_xlim(-0.7, len(rows) - 0.3)
    ax.set_ylim(0, top * 1.15 + 0.2)
    ax.set_ylabel("точность, °")
    _comma(ax, "y")
    ax.grid(axis="x", visible=False)
    handles = [
        Line2D([], [], marker="o", ls="", markerfacecolor=SURFACE,
               markeredgecolor=INK_2, label="в начале"),
        Line2D([], [], marker="o", ls="", color=INK_2, label="в конце"),
    ] + [Line2D([], [], color=BRANCH[b], lw=2, label=f"ветвь {b}")
         for b in ("I", "II")]
    ax.legend(handles=handles, loc="upper left", bbox_to_anchor=(1.01, 1),
              fontsize=7.5)
    ax.set_title("Р3. Качество взгляда: точность в начале и в конце по "
                 "сессиям, группами по ПК", loc="left", pad=18)
    _spines(ax)
    fig.tight_layout()
    return _save(fig, folder, "Р3_качество_взгляда")


# --- Р4, Р5. Меры по ветвям -------------------------------------------

def _measure_panel(ax, row: dict, title: str, ylim=None) -> None:
    groups = row["groups"]
    second, first = groups
    order = [first, second]
    for k, g in enumerate(order):
        color = GROUP.get(g, INK_2)
        for point in row.get("points") or []:
            x, w, group, _, colour, code = point
            if group != g:
                continue
            ax.scatter([k + _jitter(code)], [x], zorder=3,
                       **_marker(colour, color))
        desc = row["result"].describe.get(g) or {}
        mean = desc.get("mean")
        ci = (row.get("means_ci") or {}).get(g)
        if mean is not None:
            ax.plot([k - 0.28, k + 0.28], [mean, mean], color=INK, lw=2,
                    solid_capstyle="round", zorder=4)
        if ci:
            ax.plot([k + 0.34, k + 0.34], ci, color=INK, lw=1.2, zorder=4)
            ax.plot([k + 0.30, k + 0.38], [ci[0], ci[0]], color=INK, lw=1.2)
            ax.plot([k + 0.30, k + 0.38], [ci[1], ci[1]], color=INK, lw=1.2)
    ax.set_xticks([0, 1])
    ax.set_xticklabels([f"«{g}»" if g not in ("I", "II") else f"ветвь {g}"
                        for g in order], fontsize=8)
    ax.set_xlim(-0.6, 1.6)
    if ylim:
        ax.set_ylim(*ylim)
    ax.grid(axis="x", visible=False)
    _comma(ax, "y")
    ax.set_title(_wrap(title, 30), loc="left", fontsize=8.5)
    _spines(ax)


def _branch_rows(run: dict) -> dict:
    return {r["measure"].key: r for r in run["result"]["table"]
            if r["comparison"] == compare.BRANCH and not r["pending"]}


def figure_measures(run: dict, folder: Path, keys: list[tuple],
                    title: str, name: str, cols: int) -> str:
    rows = _branch_rows(run)
    n = len(keys)
    lines = (n + cols - 1) // cols
    fig, axes = plt.subplots(lines, cols, figsize=(2.55 * cols,
                                                    2.35 * lines + 0.6),
                             squeeze=False)
    for ax, (key, ylim) in zip(axes.flat, keys):
        row = rows.get(key)
        m = compare.BY_KEY[key]
        if row is None:
            ax.set_axis_off()
            continue
        _measure_panel(ax, row, f"{m.title}, {m.unit}", ylim)
    for ax in list(axes.flat)[n:]:
        ax.set_axis_off()
    handles = _labels_safe(_shape_legend()) + [
        Line2D([], [], color=INK, lw=2, label="взвешенное среднее"),
        Line2D([], [], color=INK, lw=1.2,
               label="интервал 95 % (бутстреп)")]
    fig.legend(handles=handles, loc="lower center", ncol=3, fontsize=7.5,
               bbox_to_anchor=(0.5, 0.0))
    fig.suptitle(title, x=0.01, ha="left", fontweight="bold", color=INK)
    height = fig.get_size_inches()[1]
    fig.tight_layout(rect=(0, 0.6 / height, 1, 1))
    return _save(fig, folder, name)


LOAD_KEYS = [("clt.ecl", (1, 7)), ("clt.raw_tlx", (0, 100)),
             ("clt.icl", (1, 7)), ("clt.gcl", (1, 7)),
             ("clt.orient", (1, 7)), ("clt.tlx.mental", (0, 100)),
             ("clt.tlx.physical", (0, 100)), ("clt.tlx.temporal", (0, 100)),
             ("clt.tlx.performance", (0, 100)),
             ("clt.tlx.effort", (0, 100)),
             ("clt.tlx.frustration", (0, 100))]
ACTION_KEYS = [("actions.time_to_choice", None), ("actions.card_time", None),
               ("actions.search_trip_share", (-0.05, 1.05)),
               ("actions.via_map", (-0.05, 1.05))]


# --- Р13. Сводка «I против II» -----------------------------------------

def figure_13(run: dict, folder: Path) -> str:
    rows = [r for r in run["result"]["table"]
            if r["comparison"] == compare.BRANCH]
    order = list(compare.FAMILIES)
    rows.sort(key=lambda r: order.index(r["family"]))
    fig, ax = plt.subplots(figsize=(8.6, 0.26 * len(rows) + 1.4))
    ax.axvspan(-0.147, 0.147, color=GRID, alpha=0.6, lw=0)
    ax.axvline(0, color=INK_2, lw=1)
    labels = []
    for i, r in enumerate(rows):
        y = len(rows) - 1 - i
        res = r["result"]
        m = r["measure"]
        labels.append((y, m.title, r["family"] == "0"))
        if r["pending"]:
            ax.text(0, y, "появится в шаге 37", va="center", ha="center",
                    fontsize=7, color=MUTED)
            continue
        if res.delta is None:
            ax.text(0, y, "мало данных", va="center", ha="center",
                    fontsize=7, color=MUTED)
            continue
        strong = r["words"].endswith(("больше", "меньше"))
        if res.ci:
            ax.plot(res.ci, [y, y], color=INK if strong else INK_2, lw=1.4,
                    solid_capstyle="round")
        ax.scatter([res.delta], [y], color=INK if strong else SURFACE,
                   edgecolors=INK, s=30, zorder=3, linewidths=1.2)
    ax.set_yticks([y for y, _, _ in labels])
    ax.set_yticklabels([t for _, t, _ in labels], fontsize=7.5)
    for tick, (_, _, main) in zip(ax.get_yticklabels(), labels):
        if main:
            tick.set_fontweight("bold")
    ax.set_xlim(-1.05, 1.05)
    ax.set_ylim(-0.7, len(rows) - 0.3)
    _comma(ax, "x")
    ax.set_xlabel("δ Клиффа: < 0 — у ветви II меньше, > 0 — больше; "
                  "серая полоса — пренебрежимо (|δ| < 0,147)")
    ax.grid(axis="y", visible=False)
    ax.set_title("Р13. Сводка «I против II» — δ с интервалом 95 %; "
                 "закрашено — вывод держится после поправки", loc="left")
    _spines(ax)
    fig.tight_layout()
    return _save(fig, folder, "Р13_сводка")


# --- Р14. Устойчивость ---------------------------------------------------

def figure_14(run: dict, folder: Path) -> str | None:
    robust = run["result"]["robust"]
    if not robust:
        return None
    fig, axes = plt.subplots(1, len(robust), figsize=(4.3 * len(robust), 3.2),
                             squeeze=False)
    for ax, item in zip(axes.flat, robust):
        ax.axhspan(-0.147, 0.147, color=GRID, alpha=0.6, lw=0)
        ax.axhline(0, color=INK_2, lw=1)
        for k, case in enumerate(item["cases"]):
            res = case["result"]
            if res.delta is None:
                ax.text(k, 0, "мало\nданных", ha="center", va="center",
                        fontsize=6.5, color=MUTED)
                continue
            if res.ci:
                ax.plot([k, k], res.ci, color=INK, lw=1.4,
                        solid_capstyle="round")
            ax.scatter([k], [res.delta], color=INK, s=30, zorder=3,
                       edgecolors=SURFACE)
        ax.set_xticks(range(len(item["cases"])))
        ax.set_xticklabels([c["scenario"] for c in item["cases"]])
        ax.set_ylim(-1.1, 1.1)
        ax.set_ylabel("δ (II против I)")
        _comma(ax, "y")
        ax.grid(axis="x", visible=False)
        ax.set_title(_wrap(f"{item['measure'].title}: {item['verdict']}",
                           44), loc="left", fontsize=8.5)
        _spines(ax)
    fig.suptitle(_wrap("Р14. Устойчивость главных мер: S0 — основной, S1 — "
                       "жёлтые с весом 1, S2 — без них, S3 — и красные с "
                       "весом 1, S4 — взгляд хуже 3° с весом, S5 — только с "
                       "эталона", 95),
                 x=0.01, ha="left", fontsize=8.5, fontweight="bold",
                 color=INK)
    fig.tight_layout()
    return _save(fig, folder, "Р14_устойчивость")


def draw_all(run: dict, folder: Path) -> dict:
    """Все рисунки части 1; ответ — номер → имя PNG (или None)."""
    out = {
        "Р1": figure_1(run, folder),
        "Р2": figure_2(run, folder),
        "Р3": figure_3(run, folder),
        "Р4": figure_measures(run, folder, LOAD_KEYS,
                              "Р4. Нагрузка по ветвям: точки участников, "
                              "взвешенное среднее и интервал 95 %",
                              "Р4_нагрузка", 4),
        "Р5": figure_measures(run, folder, ACTION_KEYS,
                              "Р5. Действия: как искали книги",
                              "Р5_действия", 4),
        "Р13": figure_13(run, folder),
        "Р14": figure_14(run, folder),
    }
    return out
