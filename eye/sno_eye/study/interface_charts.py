"""Рисунки анализа по интерфейсу (SNO-F-RES-09; шаг 43): Р20 —
маршруты по библиотеке, Р21 — проверки одной группы, Р22 — моргания
по третям изучения.

Откуда данные: записи с порядком обхода (`study.order`), итог проверок
(`study.single.run`), моргания (`study.blinks`).
Технология: matplotlib (Agg); палитра, подписи и сохранение — как у
рисунков «Сравнения ветвей» (`study.charts`): точка участника — цвет
искренности заливкой, ПК — формой.
Метод: макет — «Макет сводного анализа», Р20 (шаг 43).
Вход → выход: прогон → PNG и SVG в папке `рисунки`.
"""

from __future__ import annotations

from pathlib import Path

from matplotlib.ticker import MaxNLocator

from . import charts, honesty, single
from .charts import INK, INK_2, MUTED, STATUS, _save, _spines, plt


def _p(p) -> str:
    if p is None:
        return "—"
    return "< 0,001" if p < 0.001 else f"{p:.3f}".replace(".", ",")

GROUP_COLOURS = ("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#8f5cc8")


def _people(run: dict) -> list[dict]:
    """Участники с маршрутом: группа «полка» в статистике, потом
    «Галактика» и смешанные — случаями."""
    out = []
    for g in (single.SHELF, single.GALAXY, single.MIXED):
        for e in run["entries"]:
            if e.get("interface") != g or not (e.get("order") or {}).get(
                    "books"):
                continue
            out.append(e)
    return out


def figure_20(run: dict, folder: Path) -> str | None:
    """Р20 — порядок открытия против места на полке (полка) или высоты
    звезды на карте («Галактика»): строка точек на участника."""
    people = _people(run)
    if not people:
        return None
    cols = min(5, len(people))
    rows = (len(people) + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(2.6 * cols, 2.5 * rows),
                             squeeze=False)
    for ax in axes.flat:
        ax.set_visible(False)
    for ax, e in zip(axes.flat, people):
        ax.set_visible(True)
        o = e["order"]
        if e["interface"] == single.GALAXY and o.get("map_heights"):
            ys = list(o["map_heights"])
            ax.invert_yaxis()
            ylabel = "высота звезды (верх — выше)"
            rho, route, p = o.get("rho_map"), o.get("route_map"), \
                o.get("p_map")
        else:
            ys = list(o.get("shelf_places") or [])
            ax.invert_yaxis()
            ylabel = "место на полке (1 — первая)"
            rho, route, p = o.get("rho_shelf"), o.get("route_shelf"), \
                o.get("p_shelf")
        xs = list(range(1, len(ys) + 1))
        cats = _categories(e)
        names = sorted(set(cats))
        colour = [GROUP_COLOURS[names.index(c) % len(GROUP_COLOURS)]
                  for c in cats]
        ax.plot(xs, ys, color=MUTED, lw=0.6, zorder=1)
        ax.scatter(xs, ys, c=colour, s=14, zorder=2)
        # Эмодзи цвета в шрифте рисунков нет — словом и только 🔴.
        mark = " · красный" if e.get("colour") == honesty.RED else ""
        ax.set_title(f"{e.get('participant')}{mark}\n{e['interface']}: "
                     f"{o.get('strategy')}", fontsize=7.5, loc="left")
        # Маршрут идёт из левого верхнего угла в правый нижний — числа
        # в правом верхнем, где точек нет.
        ax.text(0.98, 0.97, f"ρ {charts._num(rho)}\nмаршрут "
                f"{charts._num(route)}\np {_p(p)}",
                transform=ax.transAxes, ha="right", va="top",
                fontsize=6.5, color=INK_2,
                bbox={"facecolor": charts.SURFACE, "edgecolor": "none",
                      "alpha": 0.85, "pad": 1.5})
        ax.yaxis.set_major_locator(MaxNLocator(integer=e["interface"]
                                               != single.GALAXY))
        ax.xaxis.set_major_locator(MaxNLocator(integer=True))
        charts._comma(ax)
        ax.set_xlabel("порядок открытия", fontsize=7)
        ax.set_ylabel(ylabel, fontsize=6.5)
        ax.tick_params(labelsize=6.5)
        _spines(ax)
    fig.suptitle("Р20. Маршрут по библиотеке: порядок первого открытия "
                 "книг против места на полке или высоты звезды; цвет — "
                 "категория", x=0.01, ha="left", fontweight="bold",
                 color=INK, fontsize=9)
    fig.tight_layout()
    shelf = sum(1 for e in people if e["interface"] == single.SHELF)
    red = sum(1 for e in people if e.get("colour") == honesty.RED)
    return _save(fig, folder, "Р20_маршруты",
                 f"n: полка {shelf}, «Галактика» и смешанно "
                 f"{len(people) - shelf}; вне статистики (красный) — {red}, "
                 "показаны для примера. ρ Спирмена — внутри категории, "
                 "среднее по категориям; маршрут — длина к средней длине "
                 "случайных перестановок тех же книг (1 — как случайно); "
                 "p — доля перестановок не длиннее настоящей (+1).")


def _categories(e: dict) -> list[str]:
    layout = e.get("shelf_layout") or {}
    cat = {b[0]: b[2] for b in layout.get("books") or []}
    o = e.get("order") or {}
    if e.get("interface") == single.GALAXY and o.get("map_heights"):
        books = [b for b in o["sequence"]][:len(o["map_heights"])]
    else:
        books = [b for b in o["sequence"] if b in cat]
    return [cat.get(b, "?") for b in books]


def figure_21(run: dict, folder: Path) -> str | None:
    """Р21 — проверки одной группы: отклонение каждого участника от
    точки отсчёта, взвешенная медиана с интервалом 95 %."""
    table = [r for r in run["result"]["table"] if r["n"]]
    if not table:
        return None
    fig, ax = plt.subplots(figsize=(9.5, 0.55 * len(table) + 1.4))
    labels = []
    for i, r in enumerate(table):
        y = len(table) - 1 - i
        c = r["check"]
        for v in r.get("values") or []:
            ax.scatter(v["d"], y + charts._jitter(v["participant"], 0.18),
                       s=18, color=STATUS.get(v["colour"], MUTED),
                       edgecolors="white", linewidths=0.4, zorder=2)
        if r.get("ci"):
            ax.plot(r["ci"], [y, y], color=INK, lw=2.2, zorder=3)
        if r.get("median") is not None:
            ax.scatter([r["median"]], [y], marker="D", s=28, color=INK,
                       zorder=4)
        tag = " (разв.)" if c.exploratory else ""
        labels.append(f"{c.question}{tag}: {c.title}")
    ax.axvline(0, color=MUTED, lw=1, ls="--", zorder=1)
    ax.set_yticks(range(len(table)))
    ax.set_yticklabels([charts._wrap(t, 46) for t in reversed(labels)],
                       fontsize=7)
    ax.set_xlabel("отклонение от точки отсчёта (0 — случай или «без "
                  "изменений»)")
    charts._comma(ax, "x")
    _spines(ax)
    ax.set_title("Р21. Полка: каждый участник против случая и самого себя",
                 loc="left", fontsize=9)
    fig.tight_layout()
    n = max(r["n"] for r in table)
    return _save(fig, folder, "Р21_проверки",
                 f"Группа «полка», до {n} участников. Точка — участник "
                 "(цвет — искренность), ромб — взвешенная медиана, "
                 "линия — интервал 95 % бутстрепом участников; p — точная "
                 "знаковая перестановка (таблица «Итог»).")


def figure_22(run: dict, folder: Path) -> str | None:
    """Р22 — моргания по третям изучения: линия участника."""
    people = [e for e in run["entries"] if e.get("status") == "ok"
              and (e.get("blinks") or {}).get("thirds")]
    if not people:
        return None
    fig, ax = plt.subplots(figsize=(5.2, 3.4))
    for e in people:
        rates = e["blinks"]["thirds"]
        xs = [i + 1 for i, r in enumerate(rates) if r is not None]
        ys = [r for r in rates if r is not None]
        colour = GROUP_COLOURS[0] if e.get("interface") == single.SHELF \
            else GROUP_COLOURS[1]
        ax.plot(xs, ys, color=colour, lw=0.9, alpha=0.7, marker="o",
                markersize=3)
    ax.set_xticks([1, 2, 3])
    ax.set_xticklabels(["первая треть", "вторая", "последняя"])
    ax.set_ylabel("морганий в минуту видимого лица")
    charts._comma(ax)
    _spines(ax)
    ax.set_title("Р22. Моргания по ходу изучения", loc="left", fontsize=9)
    fig.tight_layout()
    shelf = sum(1 for e in people if e.get("interface") == single.SHELF)
    return _save(fig, folder, "Р22_моргания",
                 f"n: полка {shelf} (синие), «Галактика» и смешанно "
                 f"{len(people) - shelf} (оранжевые); моргание — кадры с "
                 "блендшейпом eyeBlink больше 0,5 подряд, не дольше 400 мс, "
                 "с лицом по обе стороны (SNO-ALG-RES-15).")


def draw_all(run: dict, folder: Path) -> dict:
    return {"Р20": figure_20(run, folder), "Р21": figure_21(run, folder),
            "Р22": figure_22(run, folder)}
