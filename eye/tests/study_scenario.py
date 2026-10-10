"""Синтетическая выборка с известным ответом — для «Сравнения ветвей»
(SNO-F-RES-06, шаги 36 и 37).

Набор архивов записей в формате приложения: журнал, ввод, кадры
раскладки, поток взгляда, файлы теста нагрузки, снимок начала,
манифест — тем же устройством, что у `report_scenario.py` (шаг 34), но
много участников сразу.

Заложенный ответ (`default_plan`): восемь участников на ветвь, два ПК,
на каждом — обе ветви. В ветви II нагрузка от интерфейса (ECL) ниже, а
книгу выбирают быстрее; Raw TLX и ICL одинаковы. Двое — 🟡, один — 🔴,
у одного точность взгляда хуже 3°, один начат не с эталона. Скрипт
обязан найти направление разницы, не пустить 🔴, взвесить 🟡.

Взгляд (шаг 37). Ветвь I ищет книгу на полке **зигзагом**: короткие
фиксации (250–330 мс) в случайных местах раздела полки, длинные скачки,
и только в конце — нужная книга. Ветвь II ищет на карте **по порядку**:
длинные фиксации (380–460 мс) — середина карты, подпись группы нужной
книги, потом её звёзды всегда в одном и том же порядке (по клеткам
окна, без возвратов), пока взгляд не дойдёт до нужной звезды. Чтение у обеих
одинаково — строки страницы. Поэтому в ветви II энтропия переходов
поиска, путь и возвраты меньше, а коэффициент K, прямота и |1 − NNI|
больше; в чтении разницы нет. Взгляд пишется только там, где участник
что-то делает (поиск, первые 30 секунд чтения): поток весит меньше, а
разбор тот же.

Только стандартная библиотека: генератор запускает и Python раннера
Windows без numpy (работа `eye-windows` в CI).
"""

from __future__ import annotations

import hashlib
import json
import random
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

S = 60_000           # study.start: минута калибровки до него
DAY = "2026-10-12"

# Окно и экран места записи — как у `report_scenario.py`.
W, H = 1280.0, 800.0
SCREEN = {"w": W, "h": H, "w_mm": 340.0, "h_mm": 212.5,
          "distance_mm": 600.0}
LATENCY = 60                   # задержка камеры, мс
PERIOD = 33                    # мс между кадрами взгляда
NAV_H = 56.0                   # полоса навигации
READ_GAZE_MS = 30_000          # сколько чтения пишется взглядом

# Сценарий теста нагрузки — встроенный сценарий версии 3
# (`lib/sno/clt/builtin_scenario.dart`), только то, что читает разбор.
LIKERT = {"type": "likert", "min": 1, "max": 7, "step": 1}
SCENARIO = {
    "schema": "sno2026-clt/1", "id": "sno-clt-main", "version": 3,
    "lang": "ru",
    "parts": [{
        "id": "B", "when": "session_end", "password": True,
        "sections": [
            {"id": "tlx", "title": "Нагрузка", "shuffle": False,
             "scale": {"type": "likert", "min": 0, "max": 100, "step": 5},
             "items": [{"id": f"tlx.{k}", "text": f"TLX {k}"} for k in (
                 "mental", "physical", "temporal", "performance", "effort",
                 "frustration")]},
            {"id": "self", "title": "О себе", "shuffle": False,
             "scale": LIKERT,
             "items": [{"id": "lie.defer", "role": "check",
                        "text": "Мне случалось откладывать…",
                        "flag": {"max": 3}}]},
            {"id": "types", "title": "О задании", "shuffle": True,
             "scale": LIKERT,
             "items": [{"id": i, "text": i} for i in (
                 "icl.1", "icl.2", "ecl.1", "ecl.2", "ecl.3", "gcl.1",
                 "gcl.2")] + [
                {"id": "chk.focus", "role": "check", "text": "Не отвлёкся",
                 "flag": {"min": 7}}]},
            {"id": "orient", "title": "О книгах на полке", "shuffle": False,
             "scale": LIKERT,
             "items": [{"id": "orient.1", "text": "orient.1"},
                       {"id": "chk.books", "role": "check",
                        "text": "Не открыл ни одной", "flag": {"min": 4}},
                       {"id": "orient.2", "text": "orient.2"},
                       {"id": "lie.late", "role": "check",
                        "text": "Ни разу не опоздал", "flag": {"min": 5}},
                       {"id": "orient.3", "text": "orient.3",
                        "reverse": True}]},
        ]}],
}

ORDER = ["tlx.mental", "tlx.physical", "tlx.temporal", "tlx.performance",
         "tlx.effort", "tlx.frustration", "lie.defer", "gcl.1", "icl.2",
         "gcl.2", "ecl.2", "ecl.3", "ecl.1", "chk.focus", "icl.1",
         "orient.1", "chk.books", "orient.2", "lie.late", "orient.3"]
CHECKS = ["lie.defer", "chk.focus", "chk.books", "lie.late"]

BOOKS = [(f"{i:06d}-" + hashlib.sha256(str(i).encode()).hexdigest(),
          f"Книга {i}", "Анатомия" if i < 6 else "Физиология")
         for i in range(12)]

# Полка: категория — строка из шести книг под своей шапкой.
SHELF_TOP = {"Анатомия": 70.0, "Физиология": 380.0}


def book_rect(i: int) -> tuple[float, float, float, float]:
    _, _, cat = BOOKS[i]
    j = i % 6
    return 40.0 + 200 * j, SHELF_TOP[cat] + 30, 180.0, 150.0


def book_centre(i: int) -> tuple[float, float]:
    x, y, w, h = book_rect(i)
    return x + w / 2, y + h / 2


def shelf_regions() -> list[dict]:
    regions = [
        {"kind": "screen", "id": "shelf", "rect": [0, NAV_H, W, H - NAV_H],
         "z": 0, "info": {"scroll": 0.0}},
        {"kind": "nav", "id": "", "rect": [0, 0, W, NAV_H], "z": 1},
    ]
    z = 2
    for cat, top in SHELF_TOP.items():
        regions.append({"kind": "shelf_category", "id": cat,
                        "rect": [16, top, 1248, 26], "z": z,
                        "info": {"part": "header"}})
        regions.append({"kind": "shelf_category", "id": cat,
                        "rect": [16, top + 26, 1248, 270], "z": z + 1,
                        "info": {"part": "area"}})
        z += 2
        for i, (book, _, c) in enumerate(BOOKS):
            if c == cat:
                regions.append({"kind": "shelf_book", "id": book,
                                "rect": list(book_rect(i)), "z": z,
                                "info": {"category": cat}})
                z += 1
    regions.append({"kind": "recording_dot", "id": "",
                    "rect": [1240, 760, 30, 30], "z": z})
    return regions


# Карта: полотно под навигацией, камера в середине; звёзды двух групп
# по шесть, сеткой 3 × 2 с шагом 200 точек — дальше общего порога
# фиксаций (4,5° ≈ 177 точек), чтобы взгляд на соседние звёзды давал
# разные фиксации.
MAP_UNIT = 250.0
MAP_RECT = (0.0, NAV_H, W, H - NAV_H)
STAR_PLACES = ((-2.2, -0.6), (-1.4, -0.6), (-0.6, -0.6), (-2.2, 0.4),
               (-1.4, 0.4), (-0.6, 0.4))


# Порядок звёзд группы при поиске ветви II: сначала звёзды одной клетки
# окна, потом другой — так в походе нет возвратов в клетку.
DIRECT_ORDER = (0, 1, 4, 2, 3, 5)


def star_map(i: int) -> tuple[float, float]:
    x, y = STAR_PLACES[i % 6]
    return (x, y) if i < 6 else (-x, y)


def star_px(i: int) -> tuple[float, float]:
    mx, my = star_map(i)
    left, top, w, h = MAP_RECT
    return left + w / 2 + mx * MAP_UNIT, top + h / 2 + my * MAP_UNIT


def galaxy_regions() -> list[dict]:
    marks = []
    for i, (book, _, _) in enumerate(BOOKS):
        x, y = star_px(i)
        marks.append({"id": book, "x": x, "y": y, "r": 8.0})
    return [
        {"kind": "screen", "id": "galaxy", "rect": [0, 0, W, H], "z": 0},
        {"kind": "nav", "id": "", "rect": [0, 0, W, NAV_H], "z": 1},
        {"kind": "galaxy_map", "id": "", "rect": list(MAP_RECT), "z": 2,
         "info": {"map": {"scale": 1.0, "cx": 0.0, "cy": 0.0,
                          "unit": MAP_UNIT}, "stars": len(BOOKS)},
         "marks": marks},
        {"kind": "recording_dot", "id": "", "rect": [1240, 760, 30, 30],
         "z": 3},
    ]


PAGE_X = 357.4
PAGE_SCALE = 0.95


def reader_regions(page: int) -> tuple[list[dict], dict]:
    regions = [
        {"kind": "page", "id": "", "rect": [0, 0, W, H], "z": 0},
        {"kind": "panel_top", "id": "", "rect": [0, 0, W, NAV_H], "z": 1},
        {"kind": "recording_dot", "id": "", "rect": [1240, 760, 30, 30],
         "z": 2},
    ]
    rect = [PAGE_X, 0, 595 * PAGE_SCALE, 842 * PAGE_SCALE]
    sheet = {"y_down": True, "scale": PAGE_SCALE,
             "pages": [{"page": page, "x": PAGE_X, "y": 0, "w": 595,
                        "h": 842}],
             "rect": rect, "content": rect, "strip": rect,
             "strip_index": 1, "strips": 1, "neighbours": []}
    return regions, sheet


def testing_regions() -> list[dict]:
    return [{"kind": "screen", "id": "testing", "rect": [0, 0, W, H],
             "z": 0},
            {"kind": "nav", "id": "", "rect": [0, 0, W, NAV_H], "z": 1}]


# Шкала лжи: (lie.defer, lie.late) — 🟢 7/1, 🟡 2/1 (провален defer),
# 🔴 1/7.
LIE = {"green": (7, 1), "yellow": (2, 1), "red": (1, 7), "unknown": None}


def jsonl(rows) -> bytes:
    return "".join(json.dumps(r, ensure_ascii=False) + "\n"
                   for r in rows).encode("utf-8")


@dataclass
class Person:
    """Участник синтетической выборки и его заложенные числа."""

    code: str
    branch: str
    device: str = "d10708"
    camera: str = "Integrated Camera"
    phone: bool = False
    colour: str = "green"
    gaze: bool = True
    start_deg: float = 1.2
    end_deg: float = 1.8
    etalon: str = "yes"          # yes, no, not_reset
    study_min: float = 40.0
    series: str | None = "sno2026-2"
    ecl: float = 4.0             # заложенное среднее ECL, 1–7
    tlx: float = 50.0            # заложенный Raw TLX, 0–100
    icl: float = 4.0
    choice_s: float = 8.0        # заложенное время до выбора книги
    via: str = "galaxy"          # galaxy, shelf, shelf_search
    trips: int = 14
    seed: int = 1
    anchor: str = f"{DAY}T10:00:00.000+03:00"
    finished: bool = True
    rec_id: str | None = None
    test: str = "complete"       # complete, none, closed
    extra: dict = field(default_factory=dict)
    # Взгляд (шаг 37): как ищет книгу — zigzag (по всей полке) или
    # direct (прямо к звезде); шум оценки, пикселей; прецизионность
    # калибровки, градусы.
    style: str | None = None
    noise: float = 4.0
    precision_deg: float = 0.8
    layout: bool = True


class Builder:
    """Архив одной записи по [Person]."""

    def __init__(self, p: Person):
        self.p = p
        self.rng = random.Random(p.seed)
        self.look_rng = random.Random(p.seed * 7919 + 1)
        self.events: list[dict] = []
        self.inputs: list[dict] = []
        self.frames: list[dict] = []
        self.looks: list[tuple] = []        # (a, b, x, y)
        self.screen = "testing"

    @property
    def watched(self) -> bool:
        return self.p.gaze and not self.p.phone

    def frame(self, t, screen, page: int = 1) -> None:
        """Кадр раскладки нового экрана — только у записи со взглядом."""
        if not self.watched or not self.p.layout:
            return
        sheet = None
        if screen == "shelf":
            regions = shelf_regions()
        elif screen == "galaxy":
            regions = galaxy_regions()
        elif screen == "reader":
            regions, sheet = reader_regions(page)
        else:
            regions = testing_regions()
        row = {"t": int(t), "screen": screen, "moving": False,
               "viewport": {"w": W, "h": H, "dpr": 1.5,
                            "orientation": "landscape"},
               "regions": regions}
        if sheet is not None:
            row["sheet"] = sheet
        self.frames.append(row)

    def look(self, a, b, x, y) -> None:
        if self.watched and b > a:
            self.looks.append((int(a), int(b), float(x), float(y)))

    def tap(self, t, screen, x=None, y=None) -> int:
        n = len(self.inputs) + 1
        if x is None:
            x, y = self.rng.uniform(50, 1200), self.rng.uniform(80, 750)
        self.inputs.append({"n": n, "t": int(t), "dt": 80,
                            "dev": "touch" if self.p.phone else "mouse",
                            "kind": "tap", "x": round(x, 1),
                            "y": round(y, 1), "x1": round(x, 1),
                            "y1": round(y, 1), "path": 0, "vw": 1280.0,
                            "vh": 800.0, "screen": screen})
        return n

    def event(self, t, kind, data=None, book=None, input=None,
              phase=None):
        row = {"t": int(t), "wall": f"{DAY}T10:00:00+03:00",
               "type": kind, "screen": self.screen}
        if book:
            row["book"] = book
        if input is not None:
            row["input"] = input
        if phase:
            row["phase"] = phase
        if data:
            row["data"] = data
        self.events.append(row)

    def nav(self, t, to, tapped=True, x=None, y=None):
        n = self.tap(t, self.screen, x, y) if tapped else None
        self.event(t, "nav.screen", {"from": self.screen, "to": to},
                   input=n)
        self.screen = to
        self.frame(t, to)
        return n

    # --- взгляд -----------------------------------------------------------
    def style(self) -> str:
        p = self.p
        if p.style:
            return p.style
        return "direct" if p.via == "galaxy" and p.branch == "II" \
            else "zigzag"

    def search_looks(self, a: float, b: float, target: tuple,
                     index: int) -> None:
        """Взгляд в поиске от [a] до [b]: зигзагом по полке или по
        порядку по звёздам группы; последние 400 мс — на цели (на неё и
        нажимают)."""
        rng = self.look_rng
        end = b - 400
        t = a
        if self.style() == "direct":
            first = 0 if index < 6 else 6
            group = range(first, first + 6)
            # Подпись группы — над её звёздами.
            top = min(star_px(i)[1] for i in group) - 60
            mid = sum(star_px(i)[0] for i in group) / 6
            left, top_y, w, h = MAP_RECT
            order = [(left + w / 2, top_y + h / 2), (mid, top)] + [
                star_px(i) for i in sorted(
                    group, key=lambda i: (DIRECT_ORDER[i % 6], i))]
            for x, y in order:
                d = rng.uniform(380, 460)
                if t + d > end or (x, y) == target:
                    break
                self.look(t, t + d, x, y)
                t += d + 40
        else:
            while t < end - 200:
                d = rng.uniform(250, 330)
                x = rng.uniform(20, W - 20)
                y = rng.uniform(NAV_H + 14, H - 20)
                self.look(t, min(t + d, end), x, y)
                t += d + 40
        self.look(max(t, end), b, *target)

    def read_looks(self, a: float, b: float) -> None:
        """Чтение: фиксации по строкам страницы по 230 мс."""
        t = a
        line = col = 0
        stop = min(b, a + READ_GAZE_MS)
        while t < stop - 300:
            x = 420 + col * 100
            y = 120 + line * 40
            self.look(t, t + 230, x, y)
            t += 270
            col += 1
            if col == 5:
                col = 0
                line = (line + 1) % 15

    def build(self) -> "Builder":
        p = self.p
        study0 = S if not p.phone else 0
        study_ms = int(p.study_min * 60_000)
        end = study0 + study_ms
        self.event(0, "recording.start", {
            "recording": p.rec_id or f"R{p.code}",
            "participant": p.code, "planned_s": 2400,
            "matches_reference": p.etalon == "yes"})
        self.frame(0, "testing")
        if not p.phone:
            self.event(S, "study.start", {"gaze": p.gaze})
        self.nav(study0 + 10, "shelf", tapped=False)
        t = study0 + 1000
        opened = 0
        for k in range(p.trips):
            if t > end - 60_000:
                break
            index = k % len(BOOKS)
            book, title, _ = BOOKS[index]
            choice = max(1.0, self.rng.gauss(p.choice_s, p.choice_s * 0.2))
            t0 = t
            if p.via == "galaxy" and p.branch == "II":
                if self.screen != "galaxy":
                    self.nav(t0 + 300, "galaxy", x=300.0, y=28.0)
                self.event(t0 + 500, "galaxy.open", {
                    "stars": 12, "points": [
                        {"book": b, "group": c, "x": star_map(i)[0],
                         "y": star_map(i)[1], "r": 8.0, "ms": 0}
                        for i, (b, _, c) in enumerate(BOOKS)]})
                for _ in range(self.rng.randint(0, 2)):
                    self.event(t0 + 700, "galaxy.view", {"cause": "drag"},
                               input=self.tap(t0 + 700, "galaxy",
                                              640.0, 790.0))
                pick = t0 + 300 + choice * 1000
                sx, sy = star_px(index)
                self.search_looks(t0 + 350, pick, (sx, sy), index)
                n = self.tap(pick, "galaxy", sx, sy)
                self.event(pick, "galaxy.star", {"book": book}, input=n)
                self.event(pick, "galaxy.card.open", {"book": book},
                           input=n)
                go = pick + 900
                # Карточка: «Читать» — внизу справа; взгляд уходит с
                # неё до перехода в читалку.
                self.look(pick + 450, go - 300, 1100.0, 700.0)
                self.nav(go, "reader", x=1100.0, y=700.0)
                self.event(go + 50, "book.open", {
                    "via": "galaxy", "visit": 1, "title": title,
                    "pages": 30, "page": 1}, book=book, input=len(self.inputs))
            elif p.via == "shelf_search":
                if self.screen != "shelf":
                    self.nav(t0 + 300, "shelf")
                n = self.tap(t0 + 500, "shelf")
                self.event(t0 + 1200, "search.query",
                           {"scope": "shelf", "chars": 4, "hits": 1},
                           input=n)
                pick = t0 + 300 + choice * 1000
                n = self.tap(pick, "shelf")
                self.event(pick, "search.result.open",
                           {"scope": "shelf", "rank": 1, "of": 1,
                            "book": book}, input=n)
                self.nav(pick + 10, "reader", tapped=False)
                self.event(pick + 60, "book.open", {
                    "via": "shelf_search", "visit": 1, "title": title,
                    "pages": 30, "page": 1}, book=book, input=n)
            else:
                if self.screen != "shelf":
                    self.nav(t0 + 300, "shelf", x=160.0, y=28.0)
                pick = t0 + 300 + choice * 1000
                bx, by = book_centre(index)
                self.search_looks(t0 + 350, pick, (bx, by), index)
                self.nav(pick, "reader", x=bx, y=by)
                self.event(pick + 40, "book.open", {
                    "via": "shelf", "visit": 1, "title": title,
                    "pages": 30, "page": 1}, book=book,
                    input=len(self.inputs))
            opened += 1
            read = self.rng.uniform(60_000, 120_000)
            t_read = self.events[-1]["t"]
            self.read_looks(t_read + 200, min(t_read + read, end) - 500)
            for j in range(4):
                # Зона листания — у правого края, далеко от строк.
                n = self.tap(t_read + 5000 * (j + 1), "reader", 1180.0,
                             400.0)
                self.event(t_read + 5000 * (j + 1), "page.shown",
                           {"cause": "zone"}, book=book, input=n)
            # Пустое касание — мимо всего.
            self.tap(t_read + 30_000, "reader", 20.0, 790.0)
            close = t_read + read
            if close > end - 2000:
                break
            n = self.tap(close, "reader", 30.0, 28.0)
            self.event(close, "book.close", {"read_ms": int(read),
                                             "open_ms": int(read)},
                       book=book, input=n)
            self.screen = "reader"
            to = "galaxy" if p.via == "galaxy" and p.branch == "II" \
                else "shelf"
            self.event(close, "nav.screen", {"from": "reader", "to": to},
                       input=n)
            self.screen = to
            self.frame(close, to)
            t = close + 10
        self.event(end, "recording.stop", {
            "stopped_by": "auto", "duration_ms": end, "study_ms": study_ms})
        if p.test == "closed":
            self.event(end + 60_000, "session.finish",
                       {"without_test": True}, phase="post")
        else:
            self.event(end + 60_000, "session.finish", phase="post")
        self.end = end
        return self

    # --- тест нагрузки -------------------------------------------------
    def answers(self) -> dict:
        p = self.p
        rng = self.rng
        values = {}

        def likert(mean):
            return max(1, min(7, round(rng.gauss(mean, 0.6))))

        for k in ("mental", "physical", "temporal", "performance",
                  "effort", "frustration"):
            values[f"tlx.{k}"] = max(0, min(100, 5 * round(
                rng.gauss(p.tlx, 8) / 5)))
        for i in ("ecl.1", "ecl.2", "ecl.3"):
            values[i] = likert(p.ecl)
        for i in ("icl.1", "icl.2"):
            values[i] = likert(p.icl)
        for i in ("gcl.1", "gcl.2"):
            values[i] = likert(5.5)
        values["orient.1"] = likert(5)
        values["orient.2"] = likert(5)
        values["orient.3"] = likert(3)
        values["chk.focus"] = 3
        values["chk.books"] = 1
        lie = LIE.get(p.colour)
        if lie is not None:
            values["lie.defer"], values["lie.late"] = lie
        rows = []
        t = self.end + 120_000
        items = {}
        for section in SCENARIO["parts"][0]["sections"]:
            for item in section["items"]:
                items[item["id"]] = (section["scale"], item)
        for order, item in enumerate(ORDER, start=1):
            if item not in values:
                continue
            scale, meta = items[item]
            t += 4000
            row = {"item": item, "value": values[item], "rt_ms": 4000,
                   "order": order, "t": t, "min": scale["min"],
                   "max": scale["max"]}
            if meta.get("role"):
                row["role"] = meta["role"]
            if meta.get("reverse"):
                row["reverse"] = True
            rows.append(row)
        return {"schema": "sno2026-clt-result/1", "scenario": "sno-clt-main",
                "version": 3, "participant": p.code, "part": "B",
                "block": None, "t_start": self.end + 120_000, "t_end": t,
                "complete": len(rows) == len(ORDER), "order": ORDER,
                "checks": CHECKS, "answers": rows}

    @staticmethod
    def scores(answers: dict, name: str) -> dict:
        """Показатели по правилу приложения (`lib/sno/clt/results.dart`):
        среднее с тремя знаками, маркеры — отдельно."""
        groups: dict = {}
        shown: dict = {}
        for item in answers["order"]:
            if item in answers["checks"]:
                continue
            g = item.rsplit(".", 1)[0]
            shown[g] = shown.get(g, 0) + 1
        for a in answers["answers"]:
            if a.get("role") == "check":
                continue
            v = a["value"]
            if a.get("reverse"):
                v = a["min"] + a["max"] - v
            g = a["item"].rsplit(".", 1)[0]
            groups.setdefault(g, {"sum": 0, "n": 0, "min": a["min"],
                                  "max": a["max"]})
            groups[g]["sum"] += v
            groups[g]["n"] += 1
        out = {}
        for g, v in groups.items():
            out[g] = {"mean": round(v["sum"] * 1000 / v["n"]) / 1000,
                      "sum": v["sum"], "n": v["n"], "of": shown.get(g),
                      "min": v["min"], "max": v["max"]}
        items = {}
        flags = 0
        rules = {"lie.defer": {"max": 3}, "lie.late": {"min": 5},
                 "chk.focus": {"min": 7}, "chk.books": {"min": 4}}
        for a in answers["answers"]:
            if a["item"] in rules:
                rule = rules[a["item"]]
                flag = (rule.get("min") is None or a["value"] >= rule["min"]) \
                    and (rule.get("max") is None or a["value"] <= rule["max"])
                flags += flag
                items[a["item"]] = {"value": a["value"], "flag": flag}
        verdict = "ok" if flags == 0 else "review" if flags == 1 else "doubt"
        return {"schema": "sno2026-clt-scores/1", "scenario": "sno-clt-main",
                "version": 3, "participant": answers.get("participant"),
                "final": {"file": name, "complete": answers["complete"],
                          "answers": len(answers["answers"]),
                          "items": len(answers["order"]), "scores": out},
                "checks": {"items": items, "fast_answers": 0,
                           "longest_same": 2, "flags": flags,
                           "verdict": verdict}}

    # --- архив -----------------------------------------------------------
    def files(self) -> dict:
        p = self.p
        events = sorted(self.events, key=lambda r: r["t"])
        for seq, row in enumerate(events, start=1):
            row["seq"] = seq
        snapshot = {
            "schema": "sno2026-snapshot/1",
            "categories": [{"name": "Анатомия", "order": 0},
                           {"name": "Физиология", "order": 1}],
            "books": [{"fingerprint": b, "title": title, "category": cat,
                       "position": i} for i, (b, title, cat)
                      in enumerate(BOOKS)],
            "settings": {"sno.book_times": "{}"}
            if p.etalon == "not_reset" else {},
            "traces": 3 if p.etalon == "not_reset" else 0,
            "reference": {"saved_at": f"{DAY}T08:00:00Z",
                          "matches": p.etalon == "yes"},
            "last_reset": None if p.etalon == "not_reset"
            else f"{DAY}T09:00:00Z",
        }
        files = {
            "events.jsonl": jsonl(events),
            "input.jsonl": jsonl(self.inputs),
            "snapshot_start.json": json.dumps(snapshot, ensure_ascii=False)
            .encode(),
        }
        if p.test != "none":
            answers = self.answers()
            if p.test == "closed":
                answers["answers"] = answers["answers"][:5]
                answers["complete"] = False
            name = f"clt/sno-clt-main_B_{answers['t_start']}.json"
            files["clt/scenario.json"] = json.dumps(
                SCENARIO, ensure_ascii=False).encode()
            files[name] = json.dumps(answers, ensure_ascii=False).encode()
            files["clt/scores.json"] = json.dumps(
                self.scores(answers, name), ensure_ascii=False).encode()
        if self.watched:
            files["eye/gaze.jsonl"] = jsonl(self.gaze_rows())
            files["eye/calibration.json"] = json.dumps({
                "schema": "sno2026-eyecal/2", "screen": SCREEN,
                "attempts": [{"attempt": 1, "kind": "full",
                              "fit": {"latency_ms": LATENCY},
                              "validation": {
                                  "accuracy_deg": p.start_deg,
                                  "precision_deg": p.precision_deg}}],
            }).encode()
            if p.layout:
                frames = sorted(self.frames, key=lambda r: r["t"])
                for n, row in enumerate(frames, start=1):
                    row["n"] = n
                files["layout.jsonl"] = jsonl(frames)
        return files

    def gaze_rows(self) -> list[dict]:
        """Поток взгляда: истинный путь плюс шум, сдвинутый на задержку
        камеры. Между взглядами ближе полсекунды — переход по прямой;
        дальше — кадров нет (участник ничего не делает)."""
        rng = random.Random(self.p.seed * 31 + 5)
        looks = sorted(self.looks)
        rows = []
        n = 1
        for i, (a, b, x, y) in enumerate(looks):
            nxt = looks[i + 1] if i + 1 < len(looks) else None
            stop = b
            if nxt is not None and 0 <= nxt[0] - b < 500:
                stop = nxt[0]
            t = a
            while t < stop:
                if t < b or nxt is None:
                    gx, gy = x, y
                else:
                    w = (t - b) / max(1, nxt[0] - b)
                    gx, gy = x + (nxt[2] - x) * w, y + (nxt[3] - y) * w
                rows.append({
                    "n": n, "t": t + LATENCY, "seg": 0, "conf": 1.0,
                    "x": round(gx + rng.gauss(0, self.p.noise), 1),
                    "y": round(gy + rng.gauss(0, self.p.noise), 1),
                    "ok": True, "dist": 1.0, "yaw": 2.0, "pitch": -3.0,
                    "roll": 0.5, "open_l": 0.3, "open_r": 0.3})
                n += 1
                t += PERIOD
        # Кадры идут строго по времени, без повторов: последний взгляд
        # одного отрезка и первый следующего могли сойтись.
        out = []
        last = None
        for row in rows:
            if last is not None and row["t"] <= last:
                continue
            last = row["t"]
            row["n"] = len(out) + 1
            out.append(row)
        return out

    def manifest(self, files: dict) -> dict:
        p = self.p
        eye: dict
        if p.phone:
            eye = {"present": False}
        elif p.gaze:
            eye = {"present": True, "configured": True, "quality": "ok",
                   "source": "webcam",
                   "place": {"camera": {"index": 0, "name": p.camera}},
                   "calibration": {"accepted": True,
                                   "accuracy_deg": p.start_deg,
                                   "precision_deg": p.precision_deg,
                                   "latency_ms": LATENCY},
                   "end_check": {"accuracy_deg": p.end_deg},
                   "file": "eye/gaze.jsonl", "segments": 1}
        else:
            eye = {"present": False, "configured": True,
                   "reason": "skipped",
                   "place": {"camera": {"index": 0, "name": p.camera}}}
        manifest = {
            "schema": "sno2026-recording/1", "branch": p.branch,
            "app": {"version": f"0.41.0-sno2026.{p.branch}",
                    "commit": "c" * 40, "study_tag": p.series,
                    "built": DAY},
            "device": {"os": "Android" if p.phone else "windows",
                       "code": p.device, "node_id": p.device + "00",
                       "manufacturer": "Synth", "model": "Test",
                       "font_scale": 1.0},
            "participant": {"code": p.code, "generated": True},
            "recording": {
                "id": p.rec_id or f"R{p.code}", "clock_anchor": p.anchor,
                "planned_s": 2400, "duration_ms": self.end,
                "duration_s": self.end // 1000, "stopped_by": "auto",
                "events": files["events.jsonl"].count(b"\n"),
                "finished": p.finished, "in_background": False,
                "study_t": None if p.phone else S,
                "away": {"count": 0, "total_ms": 0, "hidden_ms": 0,
                         "longest_ms": 0}},
            "input": {"file": "input.jsonl",
                      "lines": files["input.jsonl"].count(b"\n")},
            "eye_tracker": eye,
        }
        if "layout.jsonl" in files:
            manifest["layout"] = {"file": "layout.jsonl",
                                  "units": "logical_px",
                                  "lines": files["layout.jsonl"].count(
                                      b"\n")}
        if p.test != "none":
            manifest["clt"] = {"final": "complete" if p.test == "complete"
                               else "none", "checks_flags": 0,
                               "files": [n for n in files
                                         if n.startswith("clt/sno")]}
        manifest.update(p.extra)
        entries = {}
        for name, data in files.items():
            entry = {"bytes": len(data),
                     "sha256": hashlib.sha256(data).hexdigest()}
            if name.endswith(".jsonl"):
                entry["lines"] = data.count(b"\n")
            entries[name] = entry
        manifest["files"] = entries
        return manifest


def archive_name(p: Person) -> str:
    return f"sno2026_{p.branch}_{p.code}_{p.device}_20261012-1000.zip"


def write(folder: Path, p: Person) -> Path:
    b = Builder(p).build()
    files = b.files()
    manifest = b.manifest(files)
    path = Path(folder) / archive_name(p)
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
        for name, data in files.items():
            z.writestr(name, data)
    return path


# Заложенная разница ветвей.
ECL = {"I": 4.6, "II": 2.6}
CHOICE = {"I": 9.0, "II": 4.0}
PCS = (("d10708", "Integrated Camera"), ("a51c02", "Chicony USB2.0"))


def default_plan(*, confounded: bool = False) -> list[Person]:
    """Восемь участников на ветвь, два ПК — на каждом обе ветви (или,
    при [confounded], ветвь I на одном ПК, II — на другом).

    Особые: 🟡 — двое (по одному на ветвь), 🔴 — один в ветви II с
    заложенной «неправильной» нагрузкой (если бы он прошёл в
    статистику, ECL ветви II выросла бы), точность взгляда хуже 3° —
    один, шумная камера — один, не с эталона — один."""
    people = []
    seed = 100
    for branch in ("I", "II"):
        for k in range(8):
            if confounded:
                device, camera = PCS[0] if branch == "I" else PCS[1]
            else:
                device, camera = PCS[k % 2]
            seed += 1
            code = f"{1000 + seed:04d}{seed * 7 % 10000:04d}"
            p = Person(code=code, branch=branch, device=device,
                       camera=camera, seed=seed, ecl=ECL[branch],
                       choice_s=CHOICE[branch],
                       via="galaxy" if branch == "II" else "shelf",
                       anchor=f"{DAY}T{10 + k:02d}:00:00.000+03:00")
            people.append(p)
    people[1].colour = "yellow"
    people[9].colour = "yellow"
    people[10].colour = "red"
    people[10].ecl = 6.8
    people[10].choice_s = 20.0
    people[3].start_deg, people[3].end_deg = 3.5, 5.5
    # Шумная камера: три прецизионности (6°) больше общего порога
    # фиксаций — в меры беспорядочности не идёт, доли зон остаются.
    people[5].precision_deg = 2.0
    people[12].etalon = "not_reset"
    return people


def make_set(folder: Path, people: list[Person] | None = None) -> list[Path]:
    people = people if people is not None else default_plan()
    return [write(folder, p) for p in people]


if __name__ == "__main__":
    # `python study_scenario.py <папка> [--confounded]` — набор для
    # проверки на Windows-раннере.
    import sys
    target = Path(sys.argv[1])
    plan = default_plan(confounded="--confounded" in sys.argv)
    paths = make_set(target, plan)
    print(f"Архивов: {len(paths)} → {target}")
