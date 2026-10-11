"""Шаг 10б — снимок экрана в момент долгого взгляда, пятно внимания и
путь фиксаций — рисунок П5 (SNO-ALG-RES-09, «Снимок экрана», «Пятно и
путь»; шаг 40).

Откуда данные: момент записи (`study.moments.prepare`): кадр раскладки
этого мига — зоны, лист книги, звёзды карты, — фиксации отрезка,
точность и σ; названия и категории книг — ход сессии
(`report.timeline`); подписи групп карты — «Разбор записи» по правилу
художника (BUG-64); страница книги — из архива литературы, который
организатор кладёт рядом с архивами записей (`Library`).
Технология: pypdfium2 — тот же движок PDFium, что у приложения
(лицензии BSD-3-Clause и Apache-2.0; колесо в замке спутника
`eye/requirements.lock`, решение владельца АЛ1 (а)), рисует страницу в
растр; numpy — пятно, сумма гауссовых ядер на сетке; matplotlib (Agg) —
сборка рисунка, PNG и SVG.
Метод:
* снимок **восстанавливается**, а не снимается (АЛ1 (а)): интерфейс —
  зонами кадра раскладки с их местами и названиями; страница — сама
  страница книги в геометрии листа (место и масштаб страницы, рамка
  обрезки, читаемая полоса — вне неё затемнение, соседние листы);
  без архива литературы или без pypdfium2 — прямоугольник с подписью
  «текст страницы не подключён»;
* пятно — каждая фиксация ложится гауссовым ядром с весом её
  длительности, сумма нормируется к 1: цвет — доля времени взгляда (на
  шкале — процент на квадратный градус, чтобы число не зависело от
  шага сетки);
  ширина ядра `σ = √(1² + точность²)` градусов (1° — фовеа: Le Meur,
  Baccino, BRM, 2013, 45:251; Bylinskii и др., IEEE TPAMI, 2019,
  41(3):740); пятно полупрозрачное, один оттенок от прозрачного к
  насыщенному (Špakov, Miniotas, 2007; Bojko, HCII 2009);
* путь — фиксации кружками по порядку, площадь — длительность, номера
  у первых тридцати.
Вход → выход: момент и библиотека книг → рисунок П5 (PNG и SVG) в папке
участника.
"""

from __future__ import annotations

import hashlib
import textwrap
import zipfile
from pathlib import Path

import numpy as np

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.colors import LinearSegmentedColormap  # noqa: E402
from matplotlib.patches import Circle, Rectangle  # noqa: E402

# Сколько байт отпечатка книги берётся с начала и с конца файла —
# как у приложения (`lib/infrastructure/files/file_fingerprint.dart`).
PROBE = 64 * 1024

# Палитра восстановленного экрана — тёмно-красная тема приложения
# (CLAUDE.md, «Оформление и темы»): снимок узнаётся с первого взгляда.
BG = "#0E0708"
SURFACE = "#170D0F"
DIVIDER = "#2A1619"
ACCENT = "#A32F35"
TEXT = "#E8DCD8"
TEXT_2 = "#B9A6A2"
PAGE = "#F4F1EA"

# Цвет категории на снимке — по имени, из восьми различимых оттенков.
# Выбор наш: точный цвет категории приложения выводится из узора
# участка (`category_style.dart`); на снимке важно только различить
# группы, а не повторить оттенок.
CATEGORY = ("#e8a33d", "#5ab4d6", "#c66fd1", "#73c46a", "#e4685e",
            "#d8cf55", "#6f86e0", "#4fc2a8")

# Пятно — один оттенок (оранжевый) от прозрачного к насыщенному.
SPOT = LinearSegmentedColormap.from_list(
    "sno_spot", [(1.0, 0.55, 0.1, 0.0), (1.0, 0.55, 0.1, 0.35),
                 (1.0, 0.35, 0.0, 0.8)])
PATH = "#22d3ee"

NAV_WORDS = {"shelf": "Полка", "galaxy": "Галактика",
             "testing": "Тестирование", "settings": "Настройки",
             "device": "Устройство"}
KIND_WORDS = {
    "panel_top": "панель чтения", "panel_bottom": "панель чтения",
    "book_search": "поиск по книге", "selection_panel": "над выделением",
    "toc": "оглавление", "dialog": "окно", "shelf_search": "поиск по "
    "названию", "shelf_results": "найденное", "recording_dot": "",
    "screen": "", "nav": "",
}

NO_TEXT = "текст страницы не подключён"


def fingerprint_of(data: bytes) -> str:
    """Отпечаток книги — как у приложения: длина и SHA-256 первых и
    последних 64 КБ (у книги короче 128 КБ — хвост с 64-го КБ)."""
    size = len(data)
    head = data[:min(size, PROBE)]
    tail = b""
    if size > PROBE:
        start = max(PROBE, size - PROBE)
        tail = data[start:]
    return f"{size}-{hashlib.sha256(head + tail).hexdigest()}"


def _size_of(fingerprint: str) -> int | None:
    head = fingerprint.split("-", 1)[0]
    return int(head) if head.isdigit() else None


class Library:
    """Книги литературы, по отпечатку: PDF рядом с архивами записей или
    внутри архива литературы (любой `.zip`, кроме архивов записей).
    Отпечаток считается лениво и только у файлов нужной длины — длина
    стоит в начале отпечатка."""

    def __init__(self, paths: list[str] | None):
        self.files: list[tuple[int, Path, str | None]] = []
        self._found: dict[str, tuple[Path, str | None] | None] = {}
        self._docs: dict[str, object] = {}
        self.engine = None
        self.engine_error = None
        try:
            import pypdfium2
            self.engine = pypdfium2
        except Exception as e:  # noqa: BLE001 — нет колеса: схема зон
            self.engine_error = f"pypdfium2 не загрузился: {e}"
        for raw in paths or []:
            path = Path(raw)
            items = [path] if path.is_file() else \
                sorted(p for p in path.rglob("*") if p.is_file()) \
                if path.is_dir() else []
            for item in items:
                self._add(item)

    def _add(self, item: Path) -> None:
        name = item.name.lower()
        if name.endswith(".pdf"):
            try:
                self.files.append((item.stat().st_size, item, None))
            except OSError:
                pass
        elif name.endswith(".zip") and not name.startswith("sno2026_"):
            try:
                with zipfile.ZipFile(item) as z:
                    for info in z.infolist():
                        if info.filename.lower().endswith(".pdf") and \
                                not info.is_dir():
                            self.files.append((info.file_size, item,
                                               info.filename))
            except (OSError, zipfile.BadZipFile):
                pass

    @property
    def known(self) -> bool:
        return bool(self.files)

    def _read(self, path: Path, member: str | None) -> bytes:
        if member is None:
            return path.read_bytes()
        with zipfile.ZipFile(path) as z:
            return z.read(member)

    def find(self, fingerprint: str) -> bytes | None:
        """Байты книги с отпечатком [fingerprint] или None."""
        if fingerprint in self._found:
            hit = self._found[fingerprint]
            return None if hit is None else self._read(*hit)
        size = _size_of(fingerprint)
        self._found[fingerprint] = None
        for own, path, member in self.files:
            if own != size:
                continue
            try:
                data = self._read(path, member)
            except (OSError, zipfile.BadZipFile, KeyError):
                continue
            if fingerprint_of(data) == fingerprint:
                self._found[fingerprint] = (path, member)
                return data
        return None

    def page(self, fingerprint: str | None, page: int, scale: float
             ) -> tuple[np.ndarray | None, str | None]:
        """Растр страницы [page] (с единицы) книги [fingerprint] в
        масштабе [scale] пикселей на пункт: `(RGB, None)` или `(None,
        причина)`."""
        if self.engine is None:
            return None, self.engine_error
        if not fingerprint:
            return None, "книга кадра неизвестна"
        if not self.known:
            return None, "архива литературы рядом нет"
        doc = self._docs.get(fingerprint)
        if doc is None:
            data = self.find(fingerprint)
            if data is None:
                return None, "книги нет в архиве литературы"
            try:
                doc = self.engine.PdfDocument(data)
            except Exception as e:  # noqa: BLE001
                return None, f"книга не открылась: {e}"
            self._docs[fingerprint] = doc
        try:
            if not 1 <= page <= len(doc):
                return None, f"страницы {page} в книге нет"
            bitmap = doc[page - 1].render(scale=scale, rev_byteorder=True)
            return np.array(bitmap.to_numpy()[:, :, :3]), None
        except Exception as e:  # noqa: BLE001
            return None, f"страница не нарисовалась: {e}"


# --- пятно --------------------------------------------------------------------

def spot(fixes: list[dict], w: float, h: float, sigma_px: float,
         step: float = 4.0) -> tuple[np.ndarray, float]:
    """Пятно внимания на сетке окна с шагом [step] пикселей: сумма
    гауссовых ядер ширины [sigma_px] с весом длительности фиксации,
    нормированная к сумме 1 (доля времени взгляда в клетке). Ответ —
    `(сетка строки × столбцы, step)`; без фиксаций — нули."""
    cols = max(1, int(np.ceil(w / step)))
    rows = max(1, int(np.ceil(h / step)))
    xs = (np.arange(cols) + 0.5) * step
    ys = (np.arange(rows) + 0.5) * step
    grid = np.zeros((rows, cols))
    s2 = 2.0 * max(sigma_px, 1e-6) ** 2
    for f in fixes:
        gx = np.exp(-((xs - f["x"]) ** 2) / s2)
        gy = np.exp(-((ys - f["y"]) ** 2) / s2)
        grid += float(f["d"]) * np.outer(gy, gx)
    total = grid.sum()
    if total > 0:
        grid /= total
    return grid, step


# --- снимок -------------------------------------------------------------------

def _rect(ax, rect, **kw):
    left, top, w, h = (float(v) for v in rect)
    ax.add_patch(Rectangle((left, top), w, h, **kw))


def _text(ax, x, y, text, size=7.0, colour=TEXT, width=None, **kw):
    if width:
        text = "\n".join(textwrap.wrap(text, width)[:3])
    ax.text(x, y, text, fontsize=size, color=colour, clip_on=True, **kw)


def colour_of(name: str, order: list[str]) -> str:
    return CATEGORY[order.index(name) % len(CATEGORY)] \
        if name in order else TEXT_2


def _sheet(ax, sheet: dict, book: str | None, library: Library | None,
           w: float, h: float) -> str | None:
    """Лист книги: страницы в геометрии кадра, затемнение вне полосы,
    соседние листы. Ответ — почему страницы нет (или None)."""
    scale = float(sheet.get("scale") or 1.0)
    rect = sheet.get("rect") or [0, 0, w, h]
    content = sheet.get("content") or rect
    why = None
    for p in sheet.get("pages") or []:
        x, y = float(p["x"]), float(p["y"])
        pw, ph = float(p["w"]) * scale, float(p["h"]) * scale
        image, reason = (None, "архива литературы рядом нет") \
            if library is None else \
            library.page(book, int(p.get("page") or 1),
                         min(3.0, max(0.5, scale)))
        # Обрезка — рамкой содержимого листа в пределах окна: своя
        # обрезка картинки заменяет обрезку осью.
        cx0, cy0 = max(0.0, content[0]), max(0.0, content[1])
        cx1 = min(w, content[0] + content[2])
        cy1 = min(h, content[1] + content[3])
        clip = Rectangle((cx0, cy0), max(0.0, cx1 - cx0),
                         max(0.0, cy1 - cy0), transform=ax.transData)
        if image is not None:
            im = ax.imshow(image, extent=(x, x + pw, y + ph, y),
                           interpolation="bilinear", zorder=1)
            im.set_clip_path(clip)
        else:
            why = reason
            patch = Rectangle((x, y), pw, ph, color=PAGE, zorder=1)
            ax.add_patch(patch)
            patch.set_clip_path(clip)
            _text(ax, x + pw / 2, max(y, 0) + 40,
                  f"стр. {p.get('page')} — {NO_TEXT}: {reason}",
                  size=8, colour="#555", ha="center", va="top",
                  width=40, zorder=2)
    strip = sheet.get("strip") or content
    sl, st, sw, sh = (float(v) for v in strip)
    cl, ct, cw, chh = (float(v) for v in content)
    # Затемнение вне читаемой полосы — на листе, сверху и снизу.
    for top, height in ((ct, st - ct), (st + sh, ct + chh - st - sh)):
        if height > 0.5:
            _rect(ax, (cl, top, cw, height), color="black", alpha=0.45,
                  lw=0, zorder=2)
    for n in sheet.get("neighbours") or []:
        _rect(ax, n["rect"], color="#6b6158", alpha=0.6, lw=0, zorder=1)
    return why


def draw_screen(ax, moment: dict, titles: dict, categories: dict,
                library: Library | None) -> str | None:
    """Восстановленный экран момента на оси [ax] в пикселях окна, ось
    `y` вниз. Ответ — почему страницы книги нет на снимке (или None)."""
    frame = moment.get("frame") or {}
    vp = frame.get("viewport") or {}
    w = float(vp.get("w") or 1280)
    h = float(vp.get("h") or 800)
    ax.set_xlim(0, w)
    ax.set_ylim(h, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    _rect(ax, (0, 0, w, h), color=BG, lw=0, zorder=0)
    why = None
    if not frame:
        _text(ax, w / 2, h / 2, "кадра раскладки нет — запись прежней "
              "сборки: пятно на прямоугольнике окна", size=9,
              ha="center", va="center", width=50)
        return "кадра раскладки нет"
    order = sorted({c for c in categories.values() if isinstance(c, str)})
    regions = sorted(frame.get("regions") or [], key=lambda r: r.get("z", 0))
    sheet = frame.get("sheet")
    for r in regions:
        kind = r.get("kind")
        rid = str(r.get("id") or "")
        info = r.get("info") if isinstance(r.get("info"), dict) else {}
        left, top, rw, rh = (float(v) for v in r["rect"])
        z = 3 + 0.001 * float(r.get("z", 0))
        if kind == "page":
            if sheet:
                why = _sheet(ax, sheet, frame.get("book"), library, w, h)
            continue
        if kind == "screen":
            _rect(ax, r["rect"], color=BG, lw=0, zorder=0.5)
            continue
        if kind == "nav":
            if rid in ("top", "bottom"):
                _rect(ax, r["rect"], color=SURFACE, ec=DIVIDER, lw=0.6,
                      zorder=z)
            else:
                current = rid == info.get("current")
                _text(ax, left + rw / 2, top + rh / 2,
                      NAV_WORDS.get(rid, rid), size=7,
                      colour=TEXT if not current else ACCENT,
                      ha="center", va="center", zorder=z + 0.0005)
            continue
        if kind == "shelf_category":
            colour = colour_of(rid, order)
            if info.get("part") == "header":
                _text(ax, left + 4, top + rh / 2, rid, size=8,
                      colour=colour, va="center", weight="bold",
                      zorder=z)
            else:
                _rect(ax, r["rect"], fill=False, ec=colour, lw=0.6,
                      alpha=0.7, zorder=z)
            continue
        if kind == "shelf_book":
            _rect(ax, r["rect"], color=SURFACE, ec=DIVIDER, lw=0.8,
                  zorder=z)
            colour = colour_of(categories.get(rid) or
                               info.get("category") or "", order)
            _rect(ax, (left, top, rw, min(6.0, rh)), color=colour, lw=0,
                  zorder=z + 0.0002)
            _text(ax, left + 6, top + 12, titles.get(rid) or "книга",
                  size=7, colour=TEXT, va="top",
                  width=max(6, int(rw / 10.5)), zorder=z + 0.0005)
            continue
        if kind == "galaxy_map":
            _rect(ax, r["rect"], color="#05090f", lw=0, zorder=z)
            for mark in r.get("marks") or []:
                colour = colour_of(categories.get(mark.get("id")) or "",
                                   order)
                rad = max(2.0, float(mark.get("r") or 3.0))
                ax.add_patch(Circle((mark["x"], mark["y"]), rad * 2.2,
                                    color=colour, alpha=0.18, lw=0,
                                    zorder=z + 0.0001))
                ax.add_patch(Circle((mark["x"], mark["y"]), rad,
                                    color=colour, lw=0, zorder=z + 0.0002))
            for g in moment.get("groups") or []:
                if g.get("label"):
                    lx, ly, lw_, lh = g["label"]
                    _text(ax, lx, ly + lh / 2, g["name"], size=7.5,
                          colour=colour_of(g["name"], order), va="center",
                          zorder=z + 0.0004)
            continue
        if kind == "recording_dot":
            ax.add_patch(Circle((left + rw / 2, top + rh / 2),
                                min(rw, rh) / 3, color="#e0302a",
                                zorder=z))
            continue
        # Панели, поиск, диалоги и прочее — подложкой поверхности с
        # названием вида.
        alpha = 0.55 if r.get("active") is False else 0.92
        _rect(ax, r["rect"], color=SURFACE, ec=DIVIDER, lw=0.6,
              alpha=alpha, zorder=z)
        words = KIND_WORDS.get(kind, kind)
        if words:
            _text(ax, left + 6, top + min(rh / 2, 14), words, size=7,
                  colour=TEXT_2, va="center", zorder=z + 0.0005)
    return why


def draw_attention(ax, moment: dict, w: float, h: float):
    """Пятно и путь поверх снимка; ответ — изображение пятна (для
    шкалы)."""
    fixes = moment.get("fixations") or []
    sigma_px = float(moment.get("sigma_px") or 30.0)
    grid, step = spot(fixes, w, h, sigma_px)
    # Шкала — процент времени взгляда на квадратный градус: доля клетки
    # сетки зависит от её размера, а градус — нет.
    deg_per_px = float(moment.get("sigma_deg") or 1.0) / sigma_px
    grid = grid / (step * deg_per_px) ** 2 * 100
    vmax = float(grid.max()) if grid.size and grid.max() > 0 else 1.0
    image = ax.imshow(grid, extent=(0, grid.shape[1] * step,
                                    grid.shape[0] * step, 0),
                      cmap=SPOT, vmin=0, vmax=vmax, zorder=10,
                      interpolation="bilinear")
    if fixes:
        xs = [f["x"] for f in fixes]
        ys = [f["y"] for f in fixes]
        ax.plot(xs, ys, color=PATH, lw=0.8, alpha=0.8, zorder=11)
        for k, f in enumerate(fixes):
            rad = 4.0 + 10.0 * min(1.0, float(f["d"]) / 1000) ** 0.5
            ax.add_patch(Circle((f["x"], f["y"]), rad, fill=False,
                                ec=PATH, lw=1.0, zorder=12))
            if k < 30:
                ax.text(f["x"], f["y"], str(k + 1), fontsize=5.5,
                        color="white", ha="center", va="center",
                        zorder=13, clip_on=True)
    return image


def _n(value, digits: int = 1) -> str:
    if value is None:
        return "—"
    return f"{value:.{digits}f}".replace(".", ",")


def caption(moment: dict, phase_words: str) -> str:
    """Подпись П5: экран, время, сколько смотрел из скольких, фиксации,
    точность и σ, мышь, опора дрейфа."""
    parts = [
        f"минута изучения {_n(moment.get('minute'))}",
        f"смотрел {_n(moment['looked_ms'] / 1000)} с из "
        f"{_n(moment['length_ms'] / 1000)} с",
        f"фиксаций {len(moment.get('fixations') or [])}",
        f"точность {_n(moment.get('accuracy_deg'))}°, σ пятна "
        f"{_n(moment.get('sigma_deg'))}°",
        f"мышь двигалась {_n((moment.get('hover_share') or 0) * 100, 0)} %",
    ]
    if moment.get("anchor_s") is not None:
        parts.append(f"до ближайшей опоры дрейфа {_n(moment['anchor_s'], 0)}"
                     " с")
    return (f"П5. {phase_words.capitalize()}: самый долгий взгляд без "
            "действий\n" + " · ".join(parts))


def figure(moment: dict, phase_words: str, titles: dict, categories: dict,
           library: Library | None, folder: Path, name: str) -> tuple:
    """П5 одного момента — PNG и SVG в [folder]. Ответ — `(имя PNG,
    почему страницы нет)`."""
    frame = moment.get("frame") or {}
    vp = frame.get("viewport") or {}
    w = float(vp.get("w") or 1280)
    h = float(vp.get("h") or 800)
    fig_w = 10.0
    fig, ax = plt.subplots(figsize=(fig_w, fig_w * h / w + 0.9))
    why = draw_screen(ax, moment, titles, categories, library)
    image = draw_attention(ax, moment, w, h)
    bar = fig.colorbar(image, ax=ax, fraction=0.025, pad=0.01)
    bar.set_label("% времени взгляда на квадратный градус", fontsize=7)
    bar.ax.tick_params(labelsize=6)
    ax.set_title(caption(moment, phase_words), loc="left", fontsize=8)
    if why:
        ax.text(0, h + 8, f"Страница: {NO_TEXT} — {why}.", fontsize=7,
                color="#555", va="top", clip_on=False)
    folder.mkdir(parents=True, exist_ok=True)
    fig.savefig(folder / f"{name}.png", dpi=150, bbox_inches="tight")
    fig.savefig(folder / f"{name}.svg", bbox_inches="tight",
                metadata={"Date": None})
    plt.close(fig)
    return f"{name}.png", why

