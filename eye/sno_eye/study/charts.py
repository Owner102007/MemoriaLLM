"""Шаг 10 — рисунки Р1–Р19 (SNO-F-RES-06, «Рисунки»; Р16 и Р17 —
шаг 38, портрет участника SNO-F-RES-07; Р15, Р18, Р19 — шаг 41, свод
средних SNO-ALG-RES-10).

Откуда данные: записи после отбора (`study.compare.admit`) и итог
сравнения (`study.compare.run`): точки участников с весами, средние
ветвей с интервалом, δ с интервалом, сценарии устойчивости; средний
взгляд ветвей (`study.average.build`, шаг 37): доли, минуты, матрицы
переходов, тепловая карта, схема полки, кривые научения; кривые
энтропии по ходу сессии с кластерами и ленты участников
(`study.average.entropy_curves`, `ribbons`, шаг 38).
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
Величина (матрицы, тепловая карта, схема полки) — один оттенок,
синий, от светлого к тёмному, с числами в клетках; доли по группам
(Р8) — первые четыре места палитры и серый «прочее», с подписями долей
и таблицей в отчёте.
Вход → выход: прогон (`study.analyse`) → файлы `рисунки/Р*.png` и
`*.svg`; ответ — номер рисунка → (подпись, имя PNG).

Шаг 42 — рисунки Р1–Р14 по образцу журналов (SNO-F-RES-06; что
меняется и почему — «Сводный анализ — графика и сравнение по образцу
журналов», раздел 2): **ПК — форма точки** (круг, квадрат, треугольник…),
заливка — цвет искренности, как на Р15; у долей (Р8) — точки участников
со средним и интервалом; у хода по минутам (Р9) — интервал 95 % среднего
и линии участников; у научения (Р12) — логарифмические оси, линии
участников и прямая ветви с интервалом наклона; рядом с матрицами
ветвей (Р7) — их разница. **Под каждым рисунком — строка подписи**: n по
ветвям, что за интервал и как он посчитан, какой тест (Weissgerber T. L.
и др. «Beyond bar and line graphs: time for a new data presentation
paradigm». PLoS Biol, 2015, 13: e1002128).
"""

from __future__ import annotations

import hashlib
import textwrap
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm  # noqa
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Rectangle  # noqa: E402
from matplotlib.ticker import FuncFormatter, LogLocator  # noqa: E402

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
# Величина — синяя шкала палитры (палитра, «Sequential hue»): от
# поверхности к шагу 700.
SEQUENTIAL = LinearSegmentedColormap.from_list(
    "sno_blue", [SURFACE, "#cde2fb", "#86b6ef", "#3987e5", "#1c5cab",
                 "#0d366b"])
# Группы видов времени (Р8, Р9) — первые четыре места палитры, «прочее»
# серым (проверено `validate_palette.js`: CVD ΔE ≥ 9).
GROUP_COLOURS = {"reading": "#2a78d6", "shelf": "#eb6834",
                 "galaxy": "#1baf7a", "off": "#eda100", "other": "#b9b7b0"}
# Разница «II − I» (Р7, шаг 42) — расходящаяся шкала с нулём посередине:
# синий — больше у ветви I, оранжевый — больше у ветви II (концы — шаги
# 500 и 700 цветов ветвей палитры, середина — поверхность).
DIVERGING = LinearSegmentedColormap.from_list(
    "sno_diff", ["#1c5cab", "#86b6ef", SURFACE, "#f3a37f", "#b84a1d"])

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


def _save(fig, folder: Path, name: str, note: str | None = None) -> str:
    """[note] — строка подписи под рисунком (шаг 42): n, интервал, тест.
    Она встаёт под нижний край фигуры, а `bbox_inches="tight"` забирает
    её в файл."""
    folder.mkdir(parents=True, exist_ok=True)
    if note:
        width = max(70, int(fig.get_size_inches()[0] * 14))
        fig.text(0.01, -0.01, "\n".join(textwrap.wrap(note, width)),
                 ha="left", va="top", fontsize=7, color=INK_2)
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


def _point(colour: str | None, edge: str, pc, markers: dict) -> dict:
    """Шаг 42: точка участника — ПК формой ([markers], `_pc_marker`),
    искренность заливкой; 🔴 — крестик при любом ПК."""
    style = _marker(colour, edge)
    if colour != honesty.RED:
        style["marker"] = markers.get(pc, "o")
    return style


def _pc_handles(markers: dict) -> list:
    return [Line2D([], [], marker=mk, ls="", color=INK_2,
                   label=_wrap(f"ПК {pc}", 44), markersize=6)
            for pc, mk in markers.items()]


def _fill_handles() -> list:
    return [
        Line2D([], [], marker="o", ls="", color=INK_2,
               label="зелёный (вес 1)", markersize=6),
        Line2D([], [], marker="o", ls="", markerfacecolor=SURFACE,
               markeredgecolor=INK_2,
               label="жёлтый и неизвестно (вес меньше)", markersize=6),
        Line2D([], [], marker="x", ls="", color=INK_2,
               label="красный (только S3 и проверочный прогон)",
               markersize=6),
    ]


def _n_range(values: list[int]) -> str:
    values = sorted(set(values))
    if not values:
        return "0"
    return str(values[0]) if len(values) == 1 else \
        f"{values[0]}–{values[-1]}"


def _adjust_words(run: dict) -> str:
    return "Холм" if str(run["cfg"].get("fdr", "bh")) == "holm" \
        else "Бенджамини — Хохберг"


def _measures_note(run: dict, keys: list[str]) -> str:
    """Подпись Р4–Р6 (шаг 42): n по ветвям — участников с весом больше
    нуля, по мерам рисунка; интервал; тест и поправка."""
    rows = _branch_rows(run)
    ns: dict[str, list[int]] = {"I": [], "II": []}
    for key in keys:
        r = rows.get(key)
        if not r or not r.get("points"):
            continue
        for g in ns:
            ns[g].append(sum(1 for x, w, group, *_ in r["points"]
                             if group == g and w > 0))
    return (f"n по мерам рисунка: ветвь I — {_n_range(ns['I'])}, ветвь II "
            f"— {_n_range(ns['II'])} (в статистике, вес больше нуля). "
            "Интервал 95 % взвешенного среднего — бутстреп участников "
            f"внутри ветви, {run['cfg']['bootstrap']} повторов. Тест — "
            "δ Клиффа по слоям ПК, p перестановками внутри ПК; поправка — "
            f"Холм у главных мер, {_adjust_words(run)} в остальных семьях. "
            "Числа — «сравнение.csv», разница средних в единицах меры — "
            "Р15, Р18 и «матрица.csv».")


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
    n = {b: sum(1 for e in entries if e.get("branch") == b)
         for b in branches}
    return _save(fig, folder, "Р1_состав",
                 f"n: годных архивов ветви I — {n['I']}, ветви II — "
                 f"{n['II']}; не годны — {out}. Сколько участников в каждой "
                 "группе — числа на полосах. Описание, не тест.")


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
    shown = {b: 0 for b in ("I", "II")}
    for e in run["entries"]:
        lie = (e.get("test") or {}).get("lie") or {} \
            if e["status"] == "ok" else {}
        if lie.get("lie.defer", {}).get("value") is not None and \
                lie.get("lie.late", {}).get("value") is not None and \
                e.get("branch") in shown:
            shown[e["branch"]] += 1
    return _save(fig, folder, "Р2_шкала_лжи",
                 f"n: ответили на оба пункта — ветвь I {shown['I']}, ветвь "
                 f"II {shown['II']}. Сдвиг точки вбок — от кода участника, "
                 "чтобы одинаковые ответы не слипались; зоны — правило "
                 "цвета (АК2). Описание, не тест.")


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
    n = {b: sum(1 for e in rows if e.get("branch") == b)
         for b in ("I", "II")}
    return _save(fig, folder, "Р3_качество_взгляда",
                 f"n: сессий со взглядом — ветвь I {n['I']}, ветвь II "
                 f"{n['II']}. Точность — средняя ошибка на точках проверки "
                 "после калибровки (полый кружок) и в конце (закрашенный), "
                 f"градусы; линия — порог {limit:g}° (Т19). Описание, не "
                 "тест.")


# --- Р4, Р5. Меры по ветвям -------------------------------------------

def _measure_panel(ax, row: dict, title: str, ylim=None,
                   markers: dict | None = None) -> None:
    """Панель меры (Р4–Р6): точки участников — ветвь цветом, ПК формой
    (шаг 42), искренность заливкой; взвешенное среднее и интервал."""
    groups = row["groups"]
    second, first = groups
    order = [first, second]
    markers = markers or {}
    for k, g in enumerate(order):
        color = GROUP.get(g, INK_2)
        for point in row.get("points") or []:
            x, w, group, pc, colour, code = point
            if group != g:
                continue
            ax.scatter([k + _jitter(code)], [x], zorder=3,
                       **_point(colour, color, pc, markers))
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
    markers = _pc_marker(run)
    n = len(keys)
    lines = (n + cols - 1) // cols
    legend_in = 0.2 * ((len(markers) + 5 + 2) // 3) + 0.25
    fig, axes = plt.subplots(lines, cols, figsize=(2.55 * cols,
                                                    2.35 * lines + legend_in),
                             squeeze=False)
    for ax, (key, ylim) in zip(axes.flat, keys):
        row = rows.get(key)
        m = compare.BY_KEY[key]
        if row is None:
            ax.set_axis_off()
            continue
        _measure_panel(ax, row, f"{m.title}, {m.unit}", ylim, markers)
    for ax in list(axes.flat)[n:]:
        ax.set_axis_off()
    handles = _pc_handles(markers) + _fill_handles() + [
        Line2D([], [], color=INK, lw=2, label="взвешенное среднее"),
        Line2D([], [], color=INK, lw=1.2,
               label="интервал 95 % (бутстреп)")]
    fig.legend(handles=handles, loc="lower center", ncol=3, fontsize=7.5,
               bbox_to_anchor=(0.5, 0.0))
    fig.suptitle(title, x=0.01, ha="left", fontweight="bold", color=INK)
    height = fig.get_size_inches()[1]
    fig.tight_layout(rect=(0, legend_in / height, 1, 1))
    return _save(fig, folder, name, _measures_note(run, [k for k, _ in keys]))


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
            ax.text(0, y, "появится позже", va="center", ha="center",
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
    return _save(fig, folder, "Р13_сводка",
                 "δ — взвешенная δ Клиффа, сведённая по слоям ПК; интервал "
                 "95 % — бутстреп участников внутри ПК и ветви, "
                 f"{run['cfg']['bootstrap']} повторов; p — перестановки "
                 "меток ветвей внутри ПК; поправка — Холм у главных мер "
                 f"(жирные), {_adjust_words(run)} в остальных семьях. Слова "
                 f"— только при n_eff ≥ {_num(run['cfg']['n_eff_min'], 0)} "
                 "в обеих ветвях. n каждой меры — «сравнение.csv»; разница "
                 "в единицах меры — Р15, Р18, Р19.")


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
    fig.suptitle(_wrap("Р14. Устойчивость главных мер — «мультивселенная» "
                       "правил отбора: S0 — основной, S1 — "
                       "жёлтые с весом 1, S2 — без них, S3 — и красные с "
                       "весом 1, S4 — взгляд хуже 3° с весом, S5 — только с "
                       "эталона", 95),
                 x=0.01, ha="left", fontsize=8.5, fontweight="bold",
                 color=INK)
    fig.tight_layout()
    return _save(fig, folder, "Р14_устойчивость",
                 "Каждый сценарий — тот же расчёт δ (по слоям ПК, интервал "
                 f"95 % бутстрепом, {run['cfg']['bootstrap']} повторов) на "
                 "другом правиле отбора; вывод держится, если направление "
                 "одно во всех сценариях, где данных хватает. Мультивселенная "
                 "— Steegen S. и др. «Increasing transparency through a "
                 "multiverse analysis». Perspect Psychol Sci, 2016, 11: "
                 "702–712. n в каждом сценарии — «устойчивость.csv».")


# --- Р6. Беспорядочность ---------------------------------------------------

# Энтропия — от нуля, верх не задан: при малом `k` бывает и больше 1.
DISORDER_KEYS = [("search.H_t", (0, None)), ("search.K", None),
                 ("search.straight", (-0.05, 1.05)),
                 ("search.returns", (-0.05, 1.05)), ("search.path", None),
                 ("search.nni_dev", None), ("reading.H_t", (0, None)),
                 ("all.H_t", (0, None))]


def figure_6(run: dict, folder: Path) -> str | None:
    rows = _branch_rows(run)
    if not any((rows.get(k) or {}).get("points") for k, _ in DISORDER_KEYS):
        return None
    return figure_measures(
        run, folder, DISORDER_KEYS,
        "Р6. Беспорядочность взгляда: поиск, чтение, всё изучение — точки "
        "участников, взвешенное среднее и интервал 95 %",
        "Р6_беспорядочность", 4)


# --- Р7. Матрицы переходов ------------------------------------------------

def _matrix_panel(ax, zones: list, p: list, title: str,
                  row_n: list | None = None) -> None:
    import numpy as np
    arr = np.array(p, dtype=float) if p else np.zeros((0, 0))
    if arr.size == 0:
        ax.set_axis_off()
        ax.text(0.5, 0.5, "нет данных", ha="center", va="center",
                color=MUTED, transform=ax.transAxes)
        ax.set_title(_wrap(title, 40), loc="left", fontsize=8.5)
        return
    shown = np.nan_to_num(arr, nan=0.0)
    ax.imshow(shown, cmap=SEQUENTIAL, vmin=0, vmax=1, aspect="equal")
    n = len(zones)
    for i in range(n):
        for j in range(n):
            if arr[i, j] != arr[i, j]:
                continue
            ax.text(j, i, f"{arr[i, j]:.2f}".replace(".", ","),
                    ha="center", va="center", fontsize=6.5,
                    color=SURFACE if arr[i, j] > 0.55 else INK)
    labels = [_wrap(str(z), 14) for z in zones]
    ax.set_xticks(range(n))
    ax.set_xticklabels(labels, rotation=45, ha="right", fontsize=6.5)
    ax.set_yticks(range(n))
    # Шаг 42: у строки — участников с переходами из неё.
    ax.set_yticklabels(labels if not row_n else
                       [_wrap(f"{z} (n {k})", 18)
                        for z, k in zip(zones, row_n)], fontsize=6.5)
    ax.set_xlabel("куда", fontsize=7)
    ax.set_ylabel("откуда", fontsize=7)
    ax.grid(False)
    ax.set_title(_wrap(title, 40), loc="left", fontsize=8.5)


def _diff_panel(ax, diff: dict, title: str) -> None:
    """Шаг 42, Р7 — разница матриц «II − I» расходящейся шкалой с нулём
    посередине; строка, где в одной из ветвей меньше трёх участников с
    переходами, — серая, без чисел (`average.matrix_difference`)."""
    import numpy as np
    zones = diff["zones"]
    n = len(zones)
    if not n:
        ax.set_axis_off()
        ax.text(0.5, 0.5, "нет данных", ha="center", va="center",
                color=MUTED, transform=ax.transAxes)
        ax.set_title(_wrap(title, 40), loc="left", fontsize=8.5)
        return
    arr = np.array([[np.nan if v is None else v for v in row]
                    for row in diff["d"]], dtype=float)
    top = max(0.05, float(np.nanmax(np.abs(arr))) if np.isfinite(
        arr).any() else 0.05)
    ax.imshow(np.nan_to_num(arr, nan=0.0), cmap=DIVERGING,
              norm=TwoSlopeNorm(0.0, -top, top), aspect="equal")
    for i in range(n):
        for k in range(n):
            v = arr[i, k]
            if v != v:
                ax.add_patch(Rectangle((k - 0.5, i - 0.5), 1, 1, color=GRID,
                                       lw=0))
                continue
            text = "0,00" if round(v, 2) == 0 else \
                f"{v:+.2f}".replace(".", ",").replace("-", "−")
            ax.text(k, i, text,
                    ha="center", va="center", fontsize=6.5,
                    color=SURFACE if abs(v) > 0.7 * top else INK)
    ax.set_xticks(range(n))
    ax.set_xticklabels([_wrap(str(z), 14) for z in zones], rotation=45,
                       ha="right", fontsize=6.5)
    ax.set_yticks(range(n))
    ax.set_yticklabels([_wrap(f"{z} (n {a}/{b})", 18) for z, a, b in
                        zip(zones, diff["n_first"], diff["n_second"])],
                       fontsize=6.5)
    ax.set_xlabel("куда", fontsize=7)
    ax.grid(False)
    ax.set_title(_wrap(title, 40), loc="left", fontsize=8.5)


def figure_7(run: dict, folder: Path) -> str | None:
    """Р7 — матрицы переходов ветвей и (шаг 42) их разница «II − I»;
    у строки — число участников ветви с переходами из неё."""
    from .average import matrix_difference
    avg = run["result"].get("average") or {}
    branches = [b for b in ("I", "II")
                if (avg.get("matrix", {}).get(b) or {}).get("n")]
    if not branches:
        return None
    both = len(branches) == 2
    cols = 3 if both else len(branches)
    min_n = int(run["cfg"]["min_minute_participants"])
    fig, axes = plt.subplots(2, cols, figsize=(4.6 * cols, 9.0),
                             squeeze=False)
    for line, (key, words) in enumerate((
            ("matrix", "всё изучение, группы видов времени"),
            ("categories", "поиск, категории полки и группы карты"))):
        for k, b in enumerate(branches):
            m = avg[key][b]
            _matrix_panel(axes[line][k], m["zones"], m["p"],
                          f"Ветвь {b}: {words} (участников {m['n']})",
                          m.get("row_n"))
        if both:
            diff = matrix_difference(avg[key]["I"], avg[key]["II"], min_n)
            _diff_panel(axes[line][2], diff,
                        f"Разница II − I: {words}")
    fig.suptitle(_wrap("Р7. Матрица переходов ветви: доля переходов из "
                       "строки в столбец; строка — откуда, столбец — куда"
                       + ("; справа — разница II − I (оранжевый — чаще у "
                          "II, синий — чаще у I)" if both else ""),
                       110), x=0.01, ha="left", fontweight="bold",
                 color=INK)
    fig.tight_layout()
    return _save(fig, folder, "Р7_переходы",
                 "n в строке — участники ветви, у которых из этой зоны были "
                 "переходы (у разницы — I/II). Матрица ветви — взвешенное "
                 "среднее матриц участников, каждая нормирована к сумме 1, "
                 "потом строки делятся на свои суммы. Разница — только в "
                 f"строках, где в обеих ветвях не меньше {min_n} участников "
                 "(серым — нет). Описание, не тест: различие проверяют меры "
                 "беспорядочности (Р6, Р13).")


# --- Р8. Доли времени по группам -------------------------------------------

def figure_8(run: dict, folder: Path) -> str | None:
    """Р8 — доли времени по группам: обзор полосой и (шаг 42) точки
    участников со взвешенным средним и интервалом 95 % по каждой группе."""
    from .average import GROUP_WORDS
    avg = run["result"].get("average") or {}
    shares = avg.get("shares") or {}
    branches = [b for b in ("I", "II") if shares.get(b)]
    if not branches:
        return None
    markers = _pc_marker(run)
    fig = plt.figure(figsize=(10.4, 2.0 + 0.6 * len(branches) + 4.4))
    grid = fig.add_gridspec(2, 1, height_ratios=(0.9 + 0.45 *
                                                 len(branches), 3.4),
                            hspace=0.45)
    ax = fig.add_subplot(grid[0])
    for y, b in enumerate(branches):
        left = 0.0
        groups = shares[b]["groups"]
        for key in GROUP_COLOURS:
            width = groups.get(key) or 0.0
            if width <= 0:
                continue
            # Зазор 2 точки цвета поверхности между частями полосы.
            ax.barh(y, width, left=left, color=GROUP_COLOURS[key],
                    edgecolor=SURFACE, linewidth=1.5, height=0.55)
            if width >= 0.06:
                ax.text(left + width / 2, y, f"{round(width * 100)} %",
                        ha="center", va="center", fontsize=7, color=INK)
            left += width
    ax.set_yticks(range(len(branches)))
    ax.set_yticklabels([f"ветвь {b} (n {shares[b]['n']})"
                        for b in branches])
    ax.set_xlim(0, 1)
    ax.xaxis.set_major_formatter(FuncFormatter(
        lambda v, _: f"{round(v * 100)} %"))
    ax.grid(axis="y", visible=False)
    ax.invert_yaxis()
    handles = [Rectangle((0, 0), 1, 1, color=GROUP_COLOURS[k],
                         label=GROUP_WORDS[k]) for k in GROUP_COLOURS]
    ax.legend(handles=handles, loc="upper center", ncol=5, fontsize=7,
              bbox_to_anchor=(0.5, -0.3))
    ax.set_title("Обзор: взвешенное среднее ветви", loc="left",
                 fontsize=8.5)
    _spines(ax)
    # Шаг 42 — точки участников по группам.
    pts = fig.add_subplot(grid[1])
    keys = list(GROUP_COLOURS)
    shift = {"I": -0.18, "II": 0.18} if len(branches) == 2 else \
        {branches[0]: 0.0}
    for i, key in enumerate(keys):
        for b in branches:
            own = shares[b]
            x0 = i + shift[b]
            for person in own.get("people") or []:
                pts.scatter([x0 + _jitter(person["code"], 0.07)],
                            [person["groups"].get(key, 0.0)], zorder=3,
                            **_point(person["colour"], BRANCH[b],
                                     person["pc"], markers))
            mean = own["groups"].get(key)
            if mean is not None:
                pts.plot([x0 - 0.1, x0 + 0.1], [mean, mean], color=INK,
                         lw=2, zorder=4)
            ci = (own.get("ci") or {}).get(key)
            if ci:
                pts.plot([x0 + 0.13] * 2, ci, color=INK, lw=1.2, zorder=4)
    pts.set_xticks(range(len(keys)))
    pts.set_xticklabels([_wrap(GROUP_WORDS[k], 18) for k in keys],
                        fontsize=8)
    pts.set_xlim(-0.6, len(keys) - 0.4)
    pts.set_ylim(-0.02, 1.02)
    pts.yaxis.set_major_formatter(FuncFormatter(
        lambda v, _: f"{round(v * 100)} %"))
    pts.grid(axis="x", visible=False)
    pts.set_title("Участники: доля времени изучения в группе" +
                  ("; слева в паре — ветвь I, справа — II"
                   if len(branches) == 2 else ""), loc="left", fontsize=8.5)
    _spines(pts)
    handles = _pc_handles(markers) + _fill_handles() + [
        Line2D([], [], color=INK, lw=2,
               label="взвешенное среднее и интервал 95 %")] + [
        Line2D([], [], marker="o", ls="", color=BRANCH[b],
               label=f"ветвь {b}") for b in branches]
    fig.legend(handles=handles, loc="lower center", ncol=3, fontsize=7.5,
               bbox_to_anchor=(0.5, 0.0))
    fig.suptitle(_wrap("Р8. Доли времени изучения по группам видов "
                       "времени (мягко)", 70), x=0.01, ha="left",
                 fontweight="bold", color=INK)
    rows_legend = (len(handles) + 2) // 3
    fig.subplots_adjust(bottom=0.06 + 0.035 * rows_legend, top=0.92)
    n = {b: shares[b]["n"] for b in branches}
    return _save(fig, folder, "Р8_доли_времени",
                 "n: " + ", ".join(f"ветвь {b} — {n[b]}" for b in branches)
                 + " (со взглядом и кадрами раскладки); доли участника в "
                 "сумме дают 1. Интервал 95 % взвешенного среднего — "
                 "бутстреп участников внутри ветви, "
                 f"{run['cfg']['minute_bootstrap']} повторов. Описание, не "
                 "тест: сравнение долей — меры «Доля …» в «сравнение.csv».")


# --- Р9. Ход по минутам --------------------------------------------------

def figure_9(run: dict, folder: Path) -> str | None:
    """Р9 — ход по минутам: среднее ветви, (шаг 42) интервал 95 %
    среднего вместо полосы процентилей и тонкие линии участников."""
    from .average import GROUP_WORDS
    avg = run["result"].get("average") or {}
    minutes = avg.get("minutes") or {}
    keys = ("reading", "shelf", "galaxy", "off")
    if not any(minutes.get(b, {}).get(k) for b in ("I", "II")
               for k in keys):
        return None
    fig, axes = plt.subplots(1, len(keys), figsize=(11.5, 3.3),
                             squeeze=False)
    for ax, key in zip(axes.flat, keys):
        for b in ("I", "II"):
            own = minutes.get(b) or {}
            rows = own.get(key) or []
            if not rows:
                continue
            for person in own.get("people") or []:
                line = person["series"].get(key) or []
                if line:
                    ax.plot([r[0] for r in line], [r[1] for r in line],
                            color=BRANCH[b], lw=0.6, alpha=0.25, zorder=1)
            xs = [r[0] for r in rows]
            ax.fill_between(xs, [r[2] for r in rows], [r[3] for r in rows],
                            color=BRANCH[b], alpha=0.22, lw=0, zorder=2)
            ax.plot(xs, [r[1] for r in rows], color=BRANCH[b], lw=2,
                    label=f"ветвь {b}", zorder=3)
        ax.set_ylim(-0.02, 1.02)
        ax.yaxis.set_major_formatter(FuncFormatter(
            lambda v, _: f"{round(v * 100)} %"))
        ax.set_xlabel("минута изучения")
        ax.set_title(_wrap(GROUP_WORDS[key], 26), loc="left", fontsize=8.5)
        _spines(ax)
    handles = [Line2D([], [], color=BRANCH[b], lw=2,
                      label=f"ветвь {b}: среднее") for b in ("I", "II")]
    handles += [Rectangle((0, 0), 1, 1, color=INK_2, alpha=0.22,
                          label="интервал 95 % среднего (бутстреп)"),
                Line2D([], [], color=INK_2, lw=0.6, alpha=0.5,
                       label="участники")]
    fig.legend(handles=handles, loc="lower center", ncol=4, fontsize=7.5,
               bbox_to_anchor=(0.5, 0.0))
    fig.suptitle("Р9. Ход по минутам: доля минуты в группе — среднее "
                 "ветви, его интервал и линии участников", x=0.01,
                 ha="left", fontweight="bold", color=INK)
    fig.tight_layout(rect=(0, 0.1, 1, 1))
    n = {b: len((minutes.get(b) or {}).get("people") or [])
         for b in ("I", "II")}
    return _save(fig, folder, "Р9_по_минутам",
                 f"n: ветвь I — {n['I']}, ветвь II — {n['II']}; минута, где "
                 "участников меньше "
                 f"{run['cfg']['min_minute_participants']}, не рисуется. "
                 "Полоса — интервал 95 % взвешенного среднего: бутстреп "
                 "участников этой минуты внутри ветви, "
                 f"{run['cfg']['minute_bootstrap']} повторов, зерно — от "
                 "отпечатка набора. Описание; различие ветвей по ходу "
                 "сессии проверяет Р16.")


# --- Р10. Тепловая карта «Галактики» ---------------------------------------

def figure_10(run: dict, folder: Path) -> str | None:
    import numpy as np
    avg = run["result"].get("average") or {}
    heat = (avg.get("heat") or [])[:2]
    panels = [(item, b) for item in heat
              for b in sorted(item["branches"])]
    if not panels:
        return None
    x0, x1, y0, y1 = panels[0][0]["extent"]
    ratio = (y1 - y0) / max(x1 - x0, 1e-9)
    width = 6.0 if len(panels) == 1 else 5.0
    fig, axes = plt.subplots(1, len(panels),
                             figsize=(width * len(panels),
                                      width * ratio + 1.3),
                             squeeze=False)
    for ax, (item, b) in zip(axes.flat, panels):
        x0, x1, y0, y1 = item["extent"]
        grid = np.array(item["branches"][b]["grid"])
        if grid.max() > 0:
            grid = grid / grid.max()
        # Ось y карты — вниз, как на экране.
        ax.imshow(grid, cmap=SEQUENTIAL, vmin=0, vmax=1,
                  extent=(x0, x1, y1, y0), aspect="equal",
                  interpolation="bilinear")
        ax.scatter([p["x"] for p in item["points"]],
                   [p["y"] for p in item["points"]], s=14,
                   facecolors="none", edgecolors=INK, linewidths=0.8,
                   zorder=3)
        ax.set_xticks([])
        ax.set_yticks([])
        ax.grid(False)
        own = item["branches"][b]
        note = f", не с эталона — {own['not_reference']}" \
            if own.get("not_reference") else ""
        ax.set_title(_wrap(f"Карта {item['key']}, ветвь {b}: участников "
                           f"{own['n']}{note}", 44), loc="left",
                     fontsize=8.5)
    fig.suptitle(_wrap("Р10. Куда смотрят на карте: взгляд в поиске на "
                       "полотне карты, в координатах карты; темнее — "
                       "дольше; кружки — звёзды", 95), x=0.01, ha="left",
                 fontweight="bold", color=INK, fontsize=9)
    fig.tight_layout()
    sigma = sorted(s for item in heat for s in item.get("sigma_deg") or [])
    if sigma:
        mid = sigma[len(sigma) // 2] if len(sigma) % 2 else \
            (sigma[len(sigma) // 2 - 1] + sigma[len(sigma) // 2]) / 2
        width = (f"медиана {_num(mid, 1)}° (от {_num(sigma[0], 1)}° до "
                 f"{_num(sigma[-1], 1)}°)")
    else:
        width = "неизвестна"
    n = {b: sum(item["branches"][b]["n"] for item in heat
                if b in item["branches"]) for b in ("I", "II")}
    return _save(fig, folder, "Р10_тепловая_карта",
                 f"n: участников с фиксациями на карте — ветвь I {n['I']}, "
                 f"ветвь II {n['II']}. Величина — доля времени поиска на "
                 "полотне карты: фиксация — гауссово пятно весом в её "
                 "длительность, σ пятна — точность сессии, "
                 f"{width}; карта участника нормирована к 1, карта ветви — "
                 "взвешенное среднее; шкала у каждой панели от её "
                 "наибольшего. Описание, не тест.")


# --- Р11. Схема полки ---------------------------------------------------

def figure_11(run: dict, folder: Path) -> str | None:
    avg = run["result"].get("average") or {}
    shelves = avg.get("shelf") or {}
    branches = [b for b in ("I", "II")
                if (shelves.get(b) or {}).get("rows")
                and (shelves.get(b) or {}).get("n")]
    if not branches:
        return None
    rows_n = max(len(shelves[b]["rows"]) for b in branches)
    cols_n = max(len(r["books"]) for b in branches
                 for r in shelves[b]["rows"]) + 1
    fig, axes = plt.subplots(len(branches), 1,
                             figsize=(min(13.0, 1.05 * cols_n + 1.6),
                                      (0.85 * rows_n + 0.6) * len(branches)
                                      + 0.7),
                             squeeze=False)
    # Шкала одна на обе ветви: одинаковый цвет — одинаковая доля.
    top = max([r["header"] or 0 for b in branches
               for r in shelves[b]["rows"]] +
              [x["share"] or 0 for b in branches
               for r in shelves[b]["rows"] for x in r["books"]] + [1e-9])
    for ax, b in zip(axes.flat, branches):
        rows = shelves[b]["rows"]
        total = sum((r["header"] or 0) + sum(x["share"] or 0
                                             for x in r["books"])
                    for r in rows)
        for i, row in enumerate(rows):
            cells = [("шапка", row["header"])] + [
                (x["title"], x["share"]) for x in row["books"]]
            for j, (title, share) in enumerate(cells):
                if share is None:
                    face = SURFACE
                else:
                    face = SEQUENTIAL(share / top)
                ax.add_patch(Rectangle((j + 0.04, -i - 0.92), 0.92, 0.84,
                                       facecolor=face, edgecolor=AXIS,
                                       linewidth=0.6))
                dark = share is not None and share / top > 0.55
                text = _wrap(title, 12)
                text += "\n" + ("—" if share is None else
                                 f"{share * 100:.0f} %")
                ax.text(j + 0.5, -i - 0.5, text, ha="center", va="center",
                        fontsize=5.8, color=SURFACE if dark else INK)
            ax.text(-0.08, -i - 0.5, _wrap(row["category"], 14),
                    ha="right", va="center", fontsize=7, color=INK_2)
        ax.set_xlim(-1.6, cols_n)
        ax.set_ylim(-len(rows) - 0.1, 0.1)
        ax.set_axis_off()
        ax.set_title(f"Ветвь {b}: участников {shelves[b]['n']}; на полке "
                     f"— {total * 100:.0f} % времени поиска", loc="left",
                     fontsize=8.5)
    fig.suptitle(_wrap("Р11. Куда смотрят на полке: доля времени поиска "
                       "на шапке каждой категории и на каждой книге "
                       "(мягко), взвешенное среднее ветви; «—» — такой "
                       "категории ни у кого не было", 110), x=0.01,
                 ha="left", fontweight="bold", color=INK, fontsize=9)
    fig.tight_layout()
    return _save(fig, folder, "Р11_схема_полки",
                 "n: " + ", ".join(f"ветвь {b} — {shelves[b]['n']}"
                                   for b in branches)
                 + " (со взглядом и кадрами раскладки). Величина — доля "
                 "времени поиска на полке: время фиксаций доведённых "
                 "походов на книге или шапке категории от всего времени "
                 "поиска участника, затем взвешенное среднее участников; "
                 "шкала цвета одна на обе ветви. Описание, не тест.")


# --- Р12. Научение -------------------------------------------------------

def branch_line(lines: dict, mean: dict | None, n_max: float,
                minimum: int) -> dict | None:
    """Шаг 42, Р12 — прямая ветви в логарифмах (SNO-ALG-RES-04):
    `log y = ȳ + b̄ · (log n − x̄)`, (x̄, ȳ) — середина ветви
    (`average._lines`), b̄ и его интервал — из свода средних меры наклона
    (`learn.*_slope`, тот же бутстреп, что в «сравнение.csv»). Полоса —
    прямые с наклоном на краях интервала через ту же середину. Наклонов
    у участников меньше [minimum] — прямой нет: средний наклон одного-
    двух человек выглядел бы законом ветви."""
    import numpy as np
    if not lines or lines.get("centre") is None or not mean or \
            mean.get("mean") is None or lines.get("fitted", 0) < minimum:
        return None
    xm, ym = lines["centre"]
    n = np.exp(np.linspace(0.0, np.log(max(n_max, 2.0)), 60))
    x = np.log(n)
    b = float(mean["mean"])
    out = {"n": n.tolist(), "y": np.exp(ym + b * (x - xm)).tolist(),
           "b": b, "ci": mean.get("ci"), "lo": None, "hi": None}
    if mean.get("ci"):
        ya = np.exp(ym + mean["ci"][0] * (x - xm))
        yb = np.exp(ym + mean["ci"][1] * (x - xm))
        out["lo"] = np.minimum(ya, yb).tolist()
        out["hi"] = np.maximum(ya, yb).tolist()
    return out


def figure_12(run: dict, folder: Path) -> str | None:
    """Р12 — научение (шаг 42): оси в логарифмах (закон степени —
    прямая), линии участников, прямая ветви с интервалом наклона;
    пунктир — медиана повторных походов по их номеру."""
    avg = run["result"].get("average") or {}
    curve = avg.get("curve") or {}
    if not any(curve.get(b, {}).get(k) for b in ("I", "II")
               for k in ("choice", "path")):
        return None
    rows = _branch_rows(run)
    minimum = int(run["cfg"]["min_minute_participants"])
    fig, axes = plt.subplots(1, 2, figsize=(10.6, 3.9), squeeze=False)
    panels = (("choice", "Время до выбора книги, с", "repeat",
               "learn.choice_slope"),
              ("path", "Путь взгляда до книги, °", None,
               "learn.path_slope"))
    counts: dict = {}
    lost = 0
    for ax, (key, title, extra, measure) in zip(axes.flat, panels):
        drawn = False
        for b in ("I", "II"):
            own = curve.get(b) or {}
            lines = (own.get("lines") or {}).get(key) or {}
            counts[(key, b)] = lines.get("fitted", 0)
            lost += lines.get("dropped", 0)
            n_max = 1.0
            for person in lines.get("people") or []:
                pts = person.get("points") or []
                if len(pts) < 2:
                    continue
                ax.plot([n for n, _ in pts], [y for _, y in pts],
                        color=BRANCH[b], lw=0.7, alpha=0.3, marker="o",
                        markersize=2, zorder=1)
                n_max = max(n_max, max(n for n, _ in pts))
                drawn = True
            mean = (((rows.get(measure) or {}).get("means") or {})
                    .get("branch") or {}).get(b)
            line = branch_line(lines, mean, n_max, minimum)
            if line:
                if line["lo"]:
                    ax.fill_between(line["n"], line["lo"], line["hi"],
                                    color=BRANCH[b], alpha=0.18, lw=0,
                                    zorder=2)
                label = f"ветвь {b}: b = {_num(line['b'])}"
                if line["ci"]:
                    label += f" {_ci(line['ci'])}"
                ax.plot(line["n"], line["y"], color=BRANCH[b], lw=2.2,
                        label=label, zorder=3)
                drawn = True
            more = own.get(extra) if extra else None
            if more:
                more = [r for r in more if r[1] is not None and r[1] > 0]
            if more:
                ax.plot([r[0] for r in more], [r[1] for r in more],
                        color=BRANCH[b], lw=1.2, ls="--", zorder=3,
                        label=f"ветвь {b}: повторные походы (медиана)")
        ax.set_xlabel("номер похода за книгой (логарифм)")
        ax.set_title(title + " (логарифм)", loc="left", fontsize=8.5)
        if drawn:
            ax.set_xscale("log")
            ax.set_yscale("log")
            # Деления 1, 2, 5 каждой декады — на логарифмической оси
            # одно «10» на панель не читается.
            for axis in (ax.xaxis, ax.yaxis):
                axis.set_major_locator(LogLocator(10, subs=(1.0, 2.0, 5.0)))
                axis.set_major_formatter(_COMMA)
                axis.set_minor_formatter(FuncFormatter(lambda v, _: ""))
        if ax.get_legend_handles_labels()[0]:
            ax.legend(fontsize=7)
        elif not drawn:
            ax.text(0.5, 0.5, "нет данных", ha="center", va="center",
                    color=MUTED, transform=ax.transAxes)
        _spines(ax)
    fig.suptitle(_wrap("Р12. Научение: закон степени — прямая в "
                       "логарифмах; линии участников, прямая ветви с "
                       "интервалом наклона", 110), x=0.01, ha="left",
                 fontweight="bold", color=INK, fontsize=9)
    fig.tight_layout()
    return _save(fig, folder, "Р12_научение",
                 "n с наклоном: время до выбора — ветвь I "
                 f"{counts.get(('choice', 'I'), 0)}, ветвь II "
                 f"{counts.get(('choice', 'II'), 0)}; путь взгляда — ветвь I "
                 f"{counts.get(('path', 'I'), 0)}, ветвь II "
                 f"{counts.get(('path', 'II'), 0)}; меньше "
                 f"{run['cfg']['min_visits_curve']} доведённых походов — "
                 "наклона нет, участников с наклоном меньше "
                 f"{minimum} — прямой ветви нет. Прямая ветви — log y = ȳ + "
                 "b̄ · (log n − x̄): b̄ — взвешенное среднее наклонов "
                 "участников, полоса — его интервал 95 % (бутстреп, "
                 f"{run['cfg']['bootstrap']} повторов, как в "
                 "«сравнение.csv»); тест наклона — меры «Научение» там же. "
                 "Походов с нулём, не легших на логарифмическую ось: "
                 f"{lost}.")


# --- Р16. Энтропия по ходу сессии: ветви ---------------------------------

def figure_16(run: dict, folder: Path) -> str | None:
    """Две панели: поиск по накопленному времени поиска, чтение — по
    минуте изучения; среднее ветви с полосой 95 %, тонкие линии —
    участники; серым — кластеры различия с p < 0,05 (SNO-ALG-RES-06)."""
    from .portrait import READING, SEARCH
    avg = run["result"].get("average") or {}
    ent = avg.get("entropy") or {}
    if not any((ent.get(n) or {}).get("people") for n in (SEARCH,
                                                           READING)):
        return None
    alpha = float(run["cfg"]["alpha"])
    fig, axes = plt.subplots(1, 2, figsize=(11.6, 4.0),
                             gridspec_kw={"width_ratios": [1, 1.4]})
    panels = ((SEARCH, "Поиск", "накопленное время поиска, мин"),
              (READING, "Чтение", "минута изучения"))
    for ax, (name, title, xlabel) in zip(axes, panels):
        own = ent.get(name) or {}
        width = own.get("width") or 1.0
        for c in (own.get("test") or {}).get("clusters") or []:
            if c.get("p") is None or c["p"] >= alpha:
                continue
            ax.axvspan(c["x"][0], c["x"][1], color=GRID, alpha=0.8, lw=0,
                       zorder=0)
            word = "у II выше" if c["mass"] > 0 else "у II ниже"
            ax.text((c["x"][0] + c["x"][1]) / 2, 0.97,
                    f"{word},\np = {c['p']:.3f}".replace(".", ","),
                    ha="center", va="top", fontsize=7, color=INK,
                    transform=ax.get_xaxis_transform())
        for p in own.get("people") or []:
            pts = sorted(p["values"].items())
            ax.plot([(k + 0.5) * width for k, _ in pts], [v for _, v in pts],
                    color=BRANCH.get(p["branch"], MUTED), lw=0.6, alpha=0.3)
        for b in ("I", "II"):
            rows = (own.get("curves") or {}).get(b) or []
            if not rows:
                continue
            xs = [r["x"] for r in rows]
            band = [r for r in rows if r["ci"]]
            if band:
                ax.fill_between([r["x"] for r in band],
                                [r["ci"][0] for r in band],
                                [r["ci"][1] for r in band],
                                color=BRANCH[b], alpha=0.18, lw=0)
            # Точки на линии: кривая из одной корзины тоже видна.
            ax.plot(xs, [r["mean"] for r in rows], color=BRANCH[b], lw=2.2,
                    marker="o", markersize=3.5, label=f"ветвь {b}")
        ax.axhline(1.0, color=MUTED, lw=0.8, ls="--")
        ax.set_xlabel(xlabel)
        ax.set_ylabel("H_t, доля от случайного")
        _comma(ax)
        _comma(ax, "x")
        ax.set_title(title, loc="left", fontsize=9)
        if ax.get_legend_handles_labels()[0]:
            ax.legend(loc="lower left", fontsize=7.5)
        else:
            ax.text(0.5, 0.5, "мало данных: корзин, где в ветви не "
                    "меньше трёх участников, нет", ha="center",
                    va="center", color=MUTED, fontsize=8,
                    transform=ax.transAxes)
        _spines(ax)
    fig.suptitle("Р16. Энтропия по ходу сессии: среднее ветви с полосой "
                 "95 %, тонкие линии — участники;\nсерое — где ветви "
                 "различаются (перестановочный тест кластеров внутри ПК, "
                 "p < 0,05)", x=0.01, ha="left", fontweight="bold",
                 color=INK, fontsize=9.5)
    fig.tight_layout(rect=(0, 0.02, 1, 0.9))
    return _save(fig, folder, "Р16_энтропия_по_ходу")


# --- Р17. Ленты сессий всех участников -----------------------------------

def figure_17(run: dict, folder: Path) -> str | None:
    """Строка — участник, цвет — группа видов времени по секундам; по
    ветвям; жёлтые и вне статистики подписаны (SNO-ALG-RES-07)."""
    from .average import GROUP_WORDS
    avg = run["result"].get("average") or {}
    rows = avg.get("ribbons") or []
    if not rows:
        return None
    height = 1.6 + 0.32 * len(rows)
    fig, ax = plt.subplots(figsize=(11.0, height))
    y = 0.0
    ticks, labels = [], []
    last = None
    longest = 1.0
    for r in rows:
        if last is not None and r["branch"] != last:
            y += 0.6
        last = r["branch"]
        by: dict = {}
        for a, b, g in r["ribbon"]:
            by.setdefault(g, []).append((a / 60, (b - a) / 60))
        for g, spans in by.items():
            ax.broken_barh(spans, (y + 0.12, 0.76),
                           color=GROUP_COLOURS.get(g, MUTED), lw=0)
        if r["opens"]:
            ax.plot([t / 60 for t in r["opens"]], [y + 0.5] * len(r["opens"]),
                    ls="", marker="v", color=INK, ms=3,
                    markeredgecolor=SURFACE)
        longest = max(longest, r["study_s"] / 60)
        mark = ""
        if r["colour"] == honesty.YELLOW:
            mark = " · жёлтый"
        if not r["in_stats"]:
            mark += " · вне статистики"
        ticks.append(y + 0.5)
        labels.append(f"ветвь {r['branch']} · {r['code']}{mark}")
        y += 1
    ax.set_xlim(0, longest)
    ax.set_ylim(y, -0.3)
    ax.set_yticks(ticks)
    ax.set_yticklabels(labels, fontsize=7)
    ax.set_xlabel("минута изучения")
    ax.grid(False)
    for s in ax.spines.values():
        s.set_visible(False)
    handles = [Rectangle((0, 0), 1, 1, color=GROUP_COLOURS[k],
                         label=GROUP_WORDS[k]) for k in GROUP_COLOURS]
    fig.legend(handles=handles, loc="lower center", ncol=5, fontsize=7.5,
               bbox_to_anchor=(0.5, 0.0))
    ax.set_title("Р17. Ленты сессий всех участников: строка — участник, "
                 "цвет — куда смотрел (▼ — открыл книгу)", loc="left",
                 fontsize=9)
    fig.tight_layout(rect=(0, 0.5 / height, 1, 1))
    return _save(fig, folder, "Р17_ленты_участников")


# --- Р15, Р18, Р19. Свод средних (SNO-ALG-RES-10, шаг 41) ---------------

PC_MARKERS = ("o", "s", "^", "D", "v", "P")


def _pc_marker(run: dict) -> dict:
    """ПК → форма точки: порядок ПК — как в наборе (имена слоёв)."""
    names = sorted({e.get("stratum") for e in run["entries"]
                    if e.get("stratum")}, key=str)
    return {n: PC_MARKERS[i % len(PC_MARKERS)] for i, n in enumerate(names)}


def _num(x, digits: int = 2) -> str:
    if x is None:
        return "—"
    # Мелкие числа (наклоны за минуту) — двумя значащими, иначе «0,00».
    text = f"{x:.2g}" if x != 0 and abs(x) < 0.05 and digits == 2 \
        else f"{x:.{digits}f}"
    return text.replace(".", ",").replace("-", "−")


def _ci(ci, digits: int = 2) -> str:
    if not ci:
        return "—"
    return f"[{_num(ci[0], digits)}; {_num(ci[1], digits)}]"


def _diff_text(diff: dict, digits: int = 2) -> str:
    if diff.get("value") is None:
        return "—"
    mark = "×" if diff.get("kind") == "отношение" else ""
    lo, hi = diff.get("ci") or (None, None)
    return (f"{mark}{_num(diff['value'], digits)} "
            f"[{mark}{_num(lo, digits)}; {mark}{_num(hi, digits)}]")


def _estimation_panel(fig, spec, row: dict, markers: dict,
                      title: str) -> None:
    """Оценочный рисунок одной меры (Gardner — Altman; Ho и др., 2019):
    слева — точки участников (ветвь — цвет, ПК — форма, 🟡 и ⚪ — полые,
    🔴 — крестик), среднее ветви с интервалом 95 %; справа — разница
    средних (или отношение) с распределением бутстрепа и интервалом."""
    sub = spec.subgridspec(1, 2, width_ratios=(3.2, 1.3), wspace=0.08)
    ax = fig.add_subplot(sub[0])
    mm = row.get("means") or {}
    order = ["I", "II"]
    for k, g in enumerate(order):
        color = BRANCH[g]
        for x, w, group, pc, colour, code in row.get("points") or []:
            if group != g:
                continue
            ax.scatter([k + _jitter(code, 0.16)], [x], zorder=3,
                       **_point(colour, color, pc, markers))
        b = (mm.get("branch") or {}).get(g) or {}
        if b.get("mean") is not None:
            ax.scatter([k + 0.38], [b["mean"]], color=INK, s=40, zorder=4)
        if b.get("ci"):
            ax.plot([k + 0.38, k + 0.38], b["ci"], color=INK, lw=1.6,
                    zorder=4)
    ns = {g: ((mm.get("branch") or {}).get(g) or {}).get("n", 0)
          for g in order}
    ax.set_xticks([0, 1])
    ax.set_xticklabels([f"ветвь {g} (n {ns[g]})" for g in order])
    ax.set_xlim(-0.6, 1.7)
    ax.grid(axis="x", visible=False)
    m = row["measure"]
    geo = " (геом.)" if mm.get("scale") == "log" else ""
    ax.set_ylabel(_wrap(f"{m.title}, {m.unit}{geo}", 34), fontsize=8)
    _comma(ax, "y")
    ax.set_title(_wrap(title, 60), loc="left", fontsize=9)
    _spines(ax)
    right = fig.add_subplot(sub[1])
    diff = mm.get("diff") or {}
    ratio = diff.get("kind") == "отношение"
    zero = 1.0 if ratio else 0.0
    right.axhline(zero, color=INK_2, lw=1)
    draws = diff.get("draws")
    if draws:
        import numpy as np
        vals = np.asarray(draws, float)
        hist, edges = np.histogram(vals, bins=40)
        if hist.max() > 0:
            mid = (edges[:-1] + edges[1:]) / 2
            right.fill_betweenx(mid, 0, hist / hist.max(),
                                color=BRANCH["II"], alpha=0.25, lw=0)
    if diff.get("value") is not None:
        right.scatter([0.15], [diff["value"]], color=INK, s=40, zorder=4)
        if diff.get("ci"):
            right.plot([0.15, 0.15], diff["ci"], color=INK, lw=1.6)
    res = row["result"]
    lines = [_diff_text(diff)]
    if res.delta is not None:
        lines.append(f"δ = {_num(res.delta)} {_ci(res.ci)}")
    if row.get("p_adj") is not None:
        lines.append(f"p δ = {_num(res.p, 3)} "
                     f"({_short_adjust(row.get('adjust'))} "
                     f"{_num(row['p_adj'], 3)})")
    lines.append(_wrap(row.get("words") or "", 26))
    # Числа — под полем разницы, а не на нём: точка и распределение
    # могут стоять где угодно по высоте.
    right.set_xlabel("\n".join(lines), fontsize=7, color=INK,
                     loc="left", labelpad=4)
    if diff.get("value") is None:
        right.set_yticks([])
    right.set_xlim(0, 1.1)
    right.set_xticks([])
    right.yaxis.tick_right()
    right.yaxis.set_label_position("right")
    right.set_ylabel("отношение II / I" if ratio else "разница II − I",
                     fontsize=8)
    _comma(right, "y")
    right.grid(axis="x", visible=False)
    for side in ("top", "left", "bottom"):
        right.spines[side].set_visible(False)


def _estimation_legend(fig, markers: dict) -> None:
    handles = [Line2D([], [], marker=mk, ls="", color=INK_2,
                      label=f"ПК {pc}", markersize=6)
               for pc, mk in markers.items()]
    handles += [Line2D([], [], marker="o", ls="", markerfacecolor=SURFACE,
                       markeredgecolor=INK_2, label="жёлтый и неизвестно "
                       "(вес меньше)", markersize=6),
                Line2D([], [], marker="o", color=INK, lw=1.6,
                       label="среднее и интервал 95 %")]
    fig.legend(handles=handles, loc="lower center", ncol=4, fontsize=7.5,
               bbox_to_anchor=(0.5, 0.0))


def figure_15(run: dict, folder: Path) -> str | None:
    """Р15 — оценочный рисунок каждой главной меры (SNO-ALG-RES-10)."""
    rows = _branch_rows(run)
    keys = [m.key for m in compare.primary(run["cfg"])
            if m.key in rows and (rows[m.key].get("means") or {})]
    if not keys:
        return None
    markers = _pc_marker(run)
    fig = plt.figure(figsize=(9.0, 3.8 * len(keys) + 0.8))
    grid = fig.add_gridspec(len(keys), 1, hspace=0.75)
    for i, key in enumerate(keys):
        _estimation_panel(fig, grid[i], rows[key], markers,
                          compare.BY_KEY[key].title)
    _estimation_legend(fig, markers)
    fig.suptitle("Р15. Главные меры: слева — участники, справа — разница "
                 "средних с её распределением бутстрепа", x=0.01,
                 ha="left", fontweight="bold", color=INK)
    return _save(fig, folder, "Р15_оценочный_рисунок")


def figure_18(run: dict, folder: Path) -> str | None:
    """Р18 — меры портрета по ветвям (семья «Д»): точки, среднее,
    интервал, справа — разница средних (SNO-ALG-RES-10)."""
    rows = _branch_rows(run)
    keys = [m.key for m in compare.MEASURES if m.family == "Д"
            and m.key in rows and rows[m.key].get("points")]
    if not keys:
        return None
    markers = _pc_marker(run)
    cols = 2
    lines = (len(keys) + cols - 1) // cols
    fig = plt.figure(figsize=(13.5, 3.6 * lines + 0.9))
    grid = fig.add_gridspec(lines, cols, hspace=0.95, wspace=0.45)
    for i, key in enumerate(keys):
        _estimation_panel(fig, grid[i // cols, i % cols], rows[key],
                          markers, compare.BY_KEY[key].title)
    _estimation_legend(fig, markers)
    fig.suptitle("Р18. Меры портрета по ветвям: точки участников, среднее "
                 "с интервалом 95 % и разница средних", x=0.01, ha="left",
                 fontweight="bold", color=INK)
    return _save(fig, folder, "Р18_меры_портрета")


def figure_19(run: dict, folder: Path) -> str | None:
    """Р19 — структурированная матрица (SNO-ALG-RES-10): строка — мера
    сравнения ветвей; голубая клетка вывода — вывод держится (в итоге
    «сильнее / слабее»). Цвет не говорит «лучше / хуже» — это говорит
    столбец «Лучше»."""
    order = list(compare.FAMILIES)
    rows = [r for r in run["result"]["table"]
            if r["comparison"] == compare.BRANCH and not r["pending"]]
    if not rows:
        return None
    rows.sort(key=lambda r: order.index(r["family"]))
    cols = (("Мера", 0.0), ("Лучше", 0.255), ("Ветвь I", 0.30),
            ("Ветвь II", 0.415), ("II против I", 0.53), ("g", 0.655),
            ("δ [95 %]", 0.695), ("p (поправка)", 0.815),
            ("Вывод", 0.905))
    height = 0.24 * len(rows) + 1.8
    fig = plt.figure(figsize=(16.0, height))
    ax = fig.add_axes((0.04, 0.02, 0.95, 1 - 1.0 / height))
    ax.set_axis_off()
    total = len(rows) + 2.5
    ax.set_ylim(0, total)
    ax.set_xlim(0, 1)
    top = total - 0.5
    for name, x in cols:
        ax.text(x, top, name, fontsize=7.5, fontweight="bold", va="center")
    ax.plot([0, 1], [top - 0.5, top - 0.5], color=AXIS, lw=0.8)
    prev = None
    for i, r in enumerate(rows):
        y = top - 1.2 - i
        if prev is not None and r["family"] != prev:
            ax.plot([0, 1], [y + 0.5, y + 0.5], color=AXIS, lw=0.6)
        if r["family"] != prev:
            ax.text(-0.012, y, compare.FAMILIES[r["family"]].split(" (")[0],
                    fontsize=6, color=MUTED, ha="right", va="center")
        prev = r["family"]
        m = r["measure"]
        mm = r.get("means") or {}
        br = mm.get("branch") or {}
        res = r["result"]
        geo = " (геом.)" if mm.get("scale") == "log" else ""
        cells = [
            _wrap(f"{m.title}, {m.unit}{geo}", 58).split("\n")[0],
            r.get("better") or "—",
            _mean_ci(br.get("I") or {}),
            _mean_ci(br.get("II") or {}),
            _diff_text(mm.get("diff") or {}),
            _num(mm.get("g"), 1),
            "—" if res.delta is None else
            f"{_num(res.delta)} {_ci(res.ci)}",
            "—" if r.get("p_adj") is None else
            f"{_num(r['p_adj'], 3)} ({_short_adjust(r.get('adjust'))})",
            _verdict_cell(r),
        ]
        hold = r.get("verdict") in ("сильнее", "слабее")
        if hold:
            ax.add_patch(Rectangle((0.9, y - 0.42), 0.1, 0.84,
                                   color="#cde2fb", lw=0))
        for (name, x), text in zip(cols, cells):
            bold = (name == "Вывод" and hold) or (name == "Мера"
                                                  and r["family"] == "0")
            ax.text(x + 0.004, y, text, fontsize=6.5, va="center",
                    color=INK, fontweight="bold" if bold else "normal")
    sums = run["result"].get("obrien") or {}
    note = _obrien_note(sums)
    if note:
        ax.text(0, 0.2, note, fontsize=7, color=INK_2, va="bottom")
    fig.suptitle("Р19. Структурированная матрица: направление «лучше» "
                 "записано до основной серии; голубой — вывод держится",
                 x=0.01, ha="left", fontweight="bold", color=INK)
    return _save(fig, folder, "Р19_структурированная_матрица")


def _mean_ci(own: dict) -> str:
    if own.get("mean") is None:
        return "—"
    return f"{_num(own['mean'])} {_ci(own.get('ci'))}"


def _short_adjust(word) -> str:
    return "Холм" if word == "Холм" else "БХ"


def _verdict_cell(r: dict) -> str:
    v = r.get("verdict")
    words = r.get("words") or ""
    if v == "сильнее":
        return words.replace("в ветви ", "у ") + " — лучше"
    if v == "слабее":
        return words.replace("в ветви ", "у ") + " — хуже"
    if words.startswith("мало данных"):
        return "мало данных"
    if v == "не держится":
        return "не держится в S0–S5"
    if words.endswith(("больше", "меньше")):
        return words.replace("в ветви ", "у ")
    return "не доказано"


def _obrien_note(sums: dict) -> str:
    total = sums.get("total") or {}
    if not total:
        return ""
    word = total.get("words") or "мало данных"
    if total.get("delta") is not None:
        word += (f", δ = {_num(total['delta'])}, p = "
                 f"{_num(total.get('p'), 3)}")
    return ("Сумма О'Брайена по всем семьям (ранги внутри ПК по "
            f"направлению «лучше», меры со стрелкой): {word} — вторичный "
            "итог, строк мер не заменяет.")


def draw_all(run: dict, folder: Path) -> dict:
    """Все рисунки; ответ — номер → имя PNG (или None, если данных для
    рисунка нет)."""
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
        "Р6": figure_6(run, folder),
        "Р7": figure_7(run, folder),
        "Р8": figure_8(run, folder),
        "Р9": figure_9(run, folder),
        "Р10": figure_10(run, folder),
        "Р11": figure_11(run, folder),
        "Р12": figure_12(run, folder),
        "Р13": figure_13(run, folder),
        "Р14": figure_14(run, folder),
        "Р15": figure_15(run, folder),
        "Р16": figure_16(run, folder),
        "Р17": figure_17(run, folder),
        "Р18": figure_18(run, folder),
        "Р19": figure_19(run, folder),
    }
    return out
