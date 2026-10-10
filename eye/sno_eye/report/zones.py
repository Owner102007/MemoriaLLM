"""Отнесение взгляда к зонам (SNO-ALG-EYE-05, шаг 5).

Кадр раскладки — последний с `t` кадра не больше начала фиксации
(SNO-ALG-REC-02). Зоны проверяются от верхних к нижним: то, что лежит
поверх страницы, важнее страницы (`layout.locate`).

**Запас** `m` — точность сессии в пикселях: точность проверки в начале,
а после середины записи — линейно к точности проверки в конце.
Фиксация **уверенно** в зоне, если все точки двух кругов вокруг неё —
радиуса `m` и `m/2` (второй ловит зону меньше запаса, например точку
записи) — в той же зоне; **на границе** — если хоть одна в другой:
рядом записываются соседние зоны. То же — на уровне категории полки,
книги и звезды карты: категория крупнее книги, и фиксация бывает
уверенно в категории, но на границе двух книг.

**Вне экрана** — точка за окном дальше 2°. Ближе — у края: она
относится к зоне у края и всегда «на границе».
"""

from __future__ import annotations

import bisect
import math

from .. import layout

# Виды времени и как их назвать — порядок строк в таблицах.
BUCKETS = (
    ("page", "страница"),
    ("page_dimmed", "страница вне полосы"),
    ("around", "поле вокруг листа"),
    ("panels", "панели чтения"),
    ("book_search", "поиск по книге"),
    ("selection", "панель над выделением"),
    ("windows", "оглавление, заметки, диалоги"),
    ("shelf", "полка"),
    ("shelf_search", "поиск по названию"),
    ("nav", "навигация"),
    ("galaxy", "карта"),
    ("recording_dot", "точка записи"),
    ("other_screen", "другой экран"),
    ("border", "на границе зон"),
    ("moving", "движение раскладки"),
    ("outside", "вне экрана"),
    ("no_face", "лица нет"),
    ("blink", "моргание и негодные кадры"),
    ("saccade", "переходы между фиксациями"),
    ("away", "вне приложения"),
    ("unknown", "зоны неизвестны"),
    ("no_frames", "нет кадров взгляда"),
)
BUCKET_NAMES = dict(BUCKETS)

# Виды зон, которые принадлежат полке.
SHELF_KINDS = ("shelf_category", "shelf_book")

# Сколько точек на круге запаса и на круге половины запаса.
RING = 12
INNER = 6


def bucket_of(hit: dict) -> str:
    """Вид времени для ответа `layout.locate`."""
    zone = hit.get("zone")
    zid = hit.get("id") or ""
    info = hit.get("info") or {}
    if zone == "page":
        return "page_dimmed" if hit.get("dimmed") else "page"
    if zone in ("neighbour", "background"):
        return "around"
    if zone in ("panel_top", "panel_bottom"):
        return "panels"
    if zone == "search_dock":
        return "book_search"
    if zone == "selection_panel":
        return "selection"
    if zone == "shelf_book":
        return "shelf_search" if info.get("in") == "results" else "shelf"
    if zone == "shelf_category":
        return "shelf"
    if zone in ("shelf_search", "shelf_results"):
        return "shelf_search"
    if zone == "nav":
        return "nav"
    if zone in ("galaxy_map", "galaxy_card"):
        return "galaxy"
    if zone == "recording_dot":
        return "recording_dot"
    if zone == "dialog":
        if zid == "shelf_search_scrim":
            return "shelf_search"
        if zid == "stop":
            return "recording_dot"
        return "windows"
    if zone in ("note_window", "toc"):
        return "windows"
    if zone == "screen":
        if zid == "shelf":
            return "shelf"
        if zid == "galaxy":
            return "galaxy"
        return "other_screen"
    if zone == "outside":
        return "outside"
    return "other_screen"


def key_of(hit: dict) -> str:
    """Имя зоны для сравнения: вид и имя, у страницы — её номер."""
    zone = hit.get("zone")
    if zone == "page":
        return f"page:{hit.get('page')}"
    zid = hit.get("id") or ""
    return f"{zone}:{zid}" if zid else str(zone)


def _top(frame: dict, x: float, y: float) -> dict | None:
    top = None
    for region in frame.get("regions") or []:
        rect = region.get("rect")
        if not isinstance(rect, list) or len(rect) != 4:
            continue
        left, top_y, width, height = rect
        if left <= x <= left + width and top_y <= y <= top_y + height and \
                (top is None or region.get("z", 0) > top.get("z", 0)):
            top = region
    return top


def shelf_place(frame: dict, x: float,
                y: float) -> tuple[str | None, str | None]:
    """Категория и книга полки под точкой — только если верхняя зона в
    точке принадлежит полке (а не списку найденного и не затемнению)."""
    region = _top(frame, x, y)
    if region is None or region.get("kind") not in SHELF_KINDS:
        return None, None
    info = region.get("info") or {}
    if region["kind"] == "shelf_book":
        if info.get("in") == "results":
            return None, None
        category = info.get("category")
        return (category if isinstance(category, str) else None,
                region.get("id"))
    return region.get("id"), None


class Zones:
    """Кадры раскладки записи и ответ «что было под точкой»."""

    def __init__(self, frames: list[dict], outside_px: float):
        self.frames = frames
        self.times = [float(f["t"]) for f in frames]
        self.outside_px = outside_px

    def frame_at(self, t: float) -> dict | None:
        i = bisect.bisect_right(self.times, t) - 1
        return self.frames[i] if i >= 0 else None

    def _locate(self, frame: dict, x: float, y: float) -> dict:
        viewport = frame.get("viewport") or {}
        w = float(viewport.get("w") or 0)
        h = float(viewport.get("h") or 0)
        if x < 0 or y < 0 or x > w or y > h:
            return {"zone": "outside"}
        return layout.locate(frame, x, y)

    def classify(self, t: float, x: float, y: float,
                 margin_px: float) -> dict:
        """Зона точки (`x`, `y`) в миг [t] с запасом [margin_px]."""
        frame = self.frame_at(t)
        if frame is None:
            return {"zone": "unknown", "bucket": "unknown", "sure": False,
                    "key": "unknown", "near": []}
        viewport = frame.get("viewport") or {}
        w = float(viewport.get("w") or 0)
        h = float(viewport.get("h") or 0)
        o = self.outside_px
        if x < -o or y < -o or x > w + o or y > h + o:
            return {"zone": "outside", "bucket": "outside", "sure": True,
                    "key": "outside", "near": [], "frame": frame.get("n"),
                    "screen": frame.get("screen")}
        edge = not (0 <= x <= w and 0 <= y <= h)
        cx, cy = min(max(x, 0.0), w), min(max(y, 0.0), h)
        hit = layout.locate(frame, cx, cy)
        key = key_of(hit)
        category, book = shelf_place(frame, cx, cy)
        near: set[str] = set()
        category_sure = category is not None
        book_sure = book is not None
        mark = hit.get("mark")
        mark_sure = mark is not None
        ring = [(margin_px, 2 * math.pi * k / RING) for k in range(RING)]
        ring += [(margin_px / 2, 2 * math.pi * (k + 0.5) / INNER)
                 for k in range(INNER)]
        for radius, angle in ring:
            px = x + radius * math.cos(angle)
            py = y + radius * math.sin(angle)
            other = self._locate(frame, px, py)
            other_key = key_of(other)
            if other_key != key:
                near.add(other_key)
            if mark is not None and other.get("mark") != mark:
                mark_sure = False
            if category is not None or book is not None:
                oc, ob = shelf_place(frame, px, py)
                if oc != category:
                    category_sure = False
                if ob != book:
                    book_sure = False
        if edge:
            near.add("outside")
        out = {
            "zone": hit.get("zone"), "id": hit.get("id") or "", "key": key,
            "bucket": bucket_of(hit), "sure": not near,
            "near": sorted(near), "frame": frame.get("n"),
            "screen": frame.get("screen"), "category": category,
            "category_sure": category_sure, "book": book,
            "book_sure": book_sure, "mark_sure": mark_sure,
        }
        for name in ("page", "x_pt", "y_pt", "dimmed", "info", "mark"):
            if name in hit:
                out[name] = hit[name]
        if hit.get("zone") == "page":
            # Книга и размер страницы — для рисунка «куда смотрели на
            # странице» в отчёте.
            out["reading"] = frame.get("book")
            for page in (frame.get("sheet") or {}).get("pages") or []:
                if page.get("page") == hit.get("page"):
                    out["page_w"] = page.get("w")
                    out["page_h"] = page.get("h")
                    break
        return out
