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

**Категория на карте** (BUG-64, правка шага 34). Подписи групп над
звёздами рисует художник карты, а не виджет, — в кадре раскладки их
нет, есть только звёзды-метки. Разбор ставит подпись сам, по правилу
художника (`lib/ui/galaxy/galaxy_painter.dart`, `_layoutLabels`): над
самой верхней видимой звездой группы, по середине видимых звёзд,
просвет 6 точек, у края полотна прижата на 6 точек; группы — по имени,
подпись, легшая на прежнюю, не встаёт (`pickLabels`). Шрифта разбор не
знает: строка `titleSmall` — 20 точек, знак — 0,6 кегля 14, оба — на
масштаб шрифта устройства; подпись — одна строка, длинная обрезается.
Категория точки на карте — группа звезды, в чей круг она попала, затем
группа подписи, а иначе ближайшая группа, до подписи, оболочки звёзд
или края звезды которой не дальше запаса группы
(`map_group_pad_deg`); при равенстве — та, чья звезда ближе.
«Уверенно / на границе» — те же два круга, что у категории полки;
категории соседних точек кругов — `category_near`.
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

# Подпись группы на карте (BUG-64) — числа художника карты
# (`galaxy_painter.dart`): наибольшая ширина, просвет до звёзд, отступ
# от края; строка и знак `titleSmall` (кегль 14, строка 20); подписей
# на кадре не больше `kMaxLabels`, группы встают первыми.
LABEL_MAX_W = 240.0
LABEL_LIMIT = 24
LABEL_GAP = 6.0
LABEL_EDGE = 6.0
LABEL_LINE = 20.0
LABEL_CHAR = 14.0 * 0.6


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


def _map_region(frame: dict) -> dict | None:
    for region in frame.get("regions") or []:
        rect = region.get("rect")
        if region.get("kind") == "galaxy_map" and isinstance(rect, list) \
                and len(rect) == 4:
            return region
    return None


def _num(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return value if math.isfinite(value) else None


def _label_size(name: str, width: float,
                font_scale: float) -> tuple[float, float]:
    """Ширина и высота подписи группы: оценка по числу знаков. Подпись
    — одна строка (`maxLines: 1`, `_painterOf`): длинная обрезается
    многоточием по наибольшей ширине, а не переносится."""
    full = len(name) * LABEL_CHAR * font_scale
    room = min(LABEL_MAX_W, max(0.0, width - 2 * LABEL_EDGE))
    return min(full, room), LABEL_LINE * font_scale


def _overlaps(a, b) -> bool:
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and \
        a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def _hull(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Выпуклая оболочка (монотонная цепь), против часовой стрелки."""
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: list = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _segment(px, py, a, b) -> float:
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    span = dx * dx + dy * dy
    along = (px - ax) * dx + (py - ay) * dy
    w = 0.0 if span == 0 else max(0.0, min(1.0, along / span))
    return math.hypot(px - (ax + w * dx), py - (ay + w * dy))


def _to_hull(hull, x, y) -> float:
    """Расстояние от точки до оболочки; внутри — ноль."""
    if not hull:
        return math.inf
    if len(hull) == 1:
        return math.hypot(x - hull[0][0], y - hull[0][1])
    if len(hull) >= 3:
        inside = True
        for a, b in zip(hull, hull[1:] + hull[:1]):
            if (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]) < 0:
                inside = False
                break
        if inside:
            return 0.0
    edges = zip(hull, hull[1:] + hull[:1]) if len(hull) >= 3 else \
        [(hull[0], hull[1])]
    return min(_segment(x, y, a, b) for a, b in edges)


def _to_rect(rect, x, y) -> float:
    left, top, w, h = rect
    dx = max(left - x, 0.0, x - (left + w))
    dy = max(top - y, 0.0, y - (top + h))
    return math.hypot(dx, dy)


def map_groups(frame: dict, categories: dict, font_scale: float = 1.0
               ) -> list[dict]:
    """Группы звёзд карты в кадре (BUG-64): имя категории, подпись
    (`[x, y, w, h]` в окне или `None` — не встала), звёзды и оболочка.
    Звёзды без известной категории в группы не идут."""
    region = _map_region(frame)
    if region is None:
        return []
    left, top, width, height = (float(v) for v in region["rect"])
    own: dict[str, list[tuple[float, float, float]]] = {}
    for mark in region.get("marks") or []:
        if not isinstance(mark, dict):
            continue
        x, y = _num(mark.get("x")), _num(mark.get("y"))
        r = _num(mark.get("r")) or 0.0
        name = categories.get(mark.get("id")) if \
            isinstance(mark.get("id"), str) else None
        if x is None or y is None or not isinstance(name, str):
            continue
        own.setdefault(name, []).append((x, y, max(r, 0.0)))
    groups = []
    placed: list[tuple] = []
    for name in sorted(own):
        stars = own[name]
        # Видимые — те, чей круг задевает полотно (как у художника).
        seen = [(x - left, y - top, r) for x, y, r in stars
                if not (x + r < left or x - r > left + width or
                        y + r < top or y - r > top + height)]
        label = None
        if seen and len(placed) < LABEL_LIMIT:
            w, h = _label_size(name, width, font_scale)
            if w + 2 * LABEL_EDGE <= width and h + 2 * LABEL_EDGE <= height:
                mid = sum(x for x, _, _ in seen) / len(seen)
                high = min(y - r for _, y, r in seen)
                lx = min(max(mid - w / 2, LABEL_EDGE),
                         width - w - LABEL_EDGE)
                ly = min(max(high - h - LABEL_GAP, LABEL_EDGE),
                         height - h - LABEL_EDGE)
                box = (lx + left, ly + top, w, h)
                if not any(_overlaps(box, other) for other in placed):
                    label = box
                    placed.append(box)
        groups.append({"name": name, "label": label, "stars": stars,
                       "hull": _hull([(x, y) for x, y, _ in stars])})
    return groups


def map_category_at(groups: list[dict], x: float, y: float,
                    pad_px: float) -> str | None:
    """Категория карты под точкой (BUG-64): звезда, в чей круг она
    попала (подпись чужой группы может лечь поверх звезды — смотрят
    тогда на звезду), затем подпись, а иначе ближайшая группа не
    дальше [pad_px]."""
    hit = None
    hit_far = None
    for group in groups:
        for sx, sy, r in group["stars"]:
            far = math.hypot(x - sx, y - sy)
            if far <= r and (hit_far is None or far < hit_far):
                hit, hit_far = group["name"], far
    if hit is not None:
        return hit
    for group in groups:
        label = group["label"]
        if label is not None and _to_rect(label, x, y) == 0.0:
            return group["name"]
    best = None
    best_key = None
    for group in groups:
        star = min((math.hypot(x - sx, y - sy) - r
                    for sx, sy, r in group["stars"]), default=math.inf)
        far = min(max(0.0, star), _to_hull(group["hull"], x, y))
        if group["label"] is not None:
            far = min(far, _to_rect(group["label"], x, y))
        if far > pad_px:
            continue
        key = (far, star)
        if best_key is None or key < best_key:
            best, best_key = group["name"], key
    return best


class Zones:
    """Кадры раскладки записи и ответ «что было под точкой»."""

    def __init__(self, frames: list[dict], outside_px: float,
                 categories: dict | None = None, font_scale: float = 1.0,
                 map_pad_px: float = 0.0):
        self.frames = frames
        self.times = [float(f["t"]) for f in frames]
        self.outside_px = outside_px
        self.categories = categories or {}
        self.font_scale = font_scale
        self.map_pad_px = map_pad_px
        self._groups: dict[int, list[dict]] = {}

    def groups(self, frame: dict) -> list[dict]:
        """Группы карты кадра [frame] — считаются один раз на кадр."""
        key = id(frame)
        if key not in self._groups:
            self._groups[key] = map_groups(frame, self.categories,
                                           self.font_scale)
        return self._groups[key]

    def place(self, frame: dict, x: float, y: float
              ) -> tuple[str | None, str | None]:
        """Категория и книга полки под точкой, а на полотне карты —
        категория группы звёзд (BUG-64); книги у карты нет — у неё
        звезда (`mark`)."""
        category, book = shelf_place(frame, x, y)
        if category is not None or book is not None:
            return category, book
        region = _top(frame, x, y)
        if region is not None and region.get("kind") == "galaxy_map":
            return map_category_at(self.groups(frame), x, y,
                                   self.map_pad_px), None
        return None, None

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
        category, book = self.place(frame, cx, cy)
        on_map = hit.get("zone") == "galaxy_map"
        near: set[str] = set()
        category_near: set[str] = set()
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
            if category is not None or book is not None or on_map:
                oc, ob = self.place(frame, px, py)
                if oc != category:
                    category_sure = False
                    if oc is not None:
                        category_near.add(oc)
                if ob != book:
                    book_sure = False
        if edge:
            near.add("outside")
        out = {
            "zone": hit.get("zone"), "id": hit.get("id") or "", "key": key,
            "bucket": bucket_of(hit), "sure": not near,
            "near": sorted(near), "frame": frame.get("n"),
            "screen": frame.get("screen"), "category": category,
            "category_sure": category_sure,
            "category_near": sorted(category_near), "book": book,
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
