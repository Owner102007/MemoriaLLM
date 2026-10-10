"""Синтетическая запись ветви II с картой — для BUG-64 (правка шага 34).

Участник на ПК открывает «Галактику». Две категории — «Ангиология» и
«Математика»; над каждой группой звёзд карта пишет её название (это
делает художник карты, а не виджет, поэтому подписи в кадре раскладки
нет — есть только звёзды-метки). Участник делает то же, что владелец в
пробной записи 10.10.2026 08:11:

1. смотрит на подпись «Ангиология» и, не переводя взгляд, нажимает
   нижнюю звезду группы;
2. смотрит на подпись «Математика» и нажимает звезду этой группы;
3. смотрит прямо на звезду «Ангиологии» и нажимает её;
4. нажимает «Читать» в карточке — открывается книга «Ангиологии».

Подписи стоят по правилу художника (`galaxy_painter.dart`,
`_layoutLabels`): над самой верхней видимой звездой группы, по
середине видимых звёзд, просвет 6 точек; высота строки `titleSmall` —
20 точек, ширина — 0,6 кегля на знак. Ответ теста — где подписи и
что было под взглядом перед каждым нажатием.
"""

from __future__ import annotations

import json

import report_scenario as rs

W, H = rs.W, rs.H
TOP = 56.0                       # полотно карты под полосой навигации

# Звёзды: отпечаток → (категория, x, y в окне, радиус).
STARS = {
    "G1": ("Ангиология", 330.0, 440.0, 8.0),
    "G2": ("Ангиология", 380.0, 500.0, 8.0),
    "G3": ("Ангиология", 300.0, 560.0, 8.0),
    "G4": ("Ангиология", 360.0, 620.0, 8.0),
    "M1": ("Математика", 860.0, 400.0, 8.0),
    "M2": ("Математика", 930.0, 450.0, 8.0),
    "M3": ("Математика", 890.0, 520.0, 8.0),
}

TITLES = {
    "G1": "Ангиология", "G2": "Сосуды", "G3": "Лимфатическая система",
    "G4": "Атлас сосудов", "M1": "Анализ", "M2": "Алгебра",
    "M3": "Статистика",
}

CHAR_W = 14 * 0.6               # ширина знака подписи группы, точек
LINE_H = 20.0                   # высота строки подписи
GAP = 6.0                       # просвет между подписью и звёздами


def label(category: str) -> tuple[float, float, float, float]:
    """Подпись группы в окне — как её поставил бы художник карты."""
    own = [(x, y - TOP, r) for c, x, y, r in STARS.values()
           if c == category]
    mid = sum(x for x, _, _ in own) / len(own)
    top = min(y - r for _, y, r in own)
    w = len(category) * CHAR_W
    left = min(max(mid - w / 2, 6.0), W - w - 6.0)
    place = min(max(top - LINE_H - GAP, 6.0), H - TOP - LINE_H - 6.0)
    return left, place + TOP, w, LINE_H


def label_centre(category: str) -> tuple[float, float]:
    x, y, w, h = label(category)
    return x + w / 2, y + h / 2


def galaxy_regions() -> list[dict]:
    marks = [{"id": key, "x": x, "y": y, "r": r}
             for key, (_, x, y, r) in STARS.items()]
    return [
        {"kind": "screen", "id": "galaxy", "rect": [0, 0, W, H], "z": 0},
        {"kind": "nav", "id": "", "rect": [0, 0, W, TOP], "z": 1},
        {"kind": "galaxy_map", "id": "", "rect": [0, TOP, W, H - TOP],
         "z": 2, "info": {"map": {"scale": 1.0, "cx": 0.5, "cy": 0.5,
                                  "unit": 600.0}, "stars": len(STARS)},
         "marks": marks},
        {"kind": "recording_dot", "id": "", "rect": [1240, 760, 30, 30],
         "z": 3},
    ]


# Нажатия похода: (куда смотрит — подпись категории или звезда, какую
# звезду жмёт).
PLAN = (("label:Ангиология", "G4"), ("label:Математика", "M3"),
        ("star:G2", "G2"))


class MapScenario(rs.Scenario):
    """Поход на карту с нажатиями по звёздам, потом чтение."""

    def __init__(self, *, plan=PLAN, **kw):
        super().__init__(**kw)
        self.plan = plan

    def build(self) -> "MapScenario":
        self.presses: list[dict] = []
        self.event(0, "recording.start", "testing",
                   {"participant": "80032040", "planned_s": 2400})
        self.frame(0, "testing", [
            {"kind": "screen", "id": "testing", "rect": [0, 0, W, H],
             "z": 0},
            {"kind": "nav", "id": "", "rect": [0, 0, W, TOP], "z": 1}])
        self.event(rs.S, "study.start", "testing", {"gaze": True})
        self.look(rs.S - 2000, rs.S + 500, 640, 400)
        v0 = rs.S + 1000
        self.click(v0, 300, 28, "testing", "nav.screen",
                   {"from": "testing", "to": "galaxy"})
        self.frame(v0, "galaxy", galaxy_regions())
        t = v0 + 300
        # Взгляд на подпись — нажатие звезды под ней, не глядя на неё;
        # взгляд на звезду — нажатие её же.
        for where, star in self.plan:
            kind, name = where.split(":")
            if kind == "label":
                gx, gy = label_centre(name)
            else:
                _, gx, gy, _ = STARS[name]
            self.look(t, t + 1350, gx, gy)
            self.star(t + 1300, star, look=False)
            self.presses.append({"t": t + 1300, "star": star,
                                 "category": STARS[star][0],
                                 "gaze": (gx, gy), "since": t})
            t += 1700
        # 4: «Читать» в карточке — книга «Ангиологии».
        n = self.click(t, 1100, 700, "galaxy", "nav.screen",
                       {"from": "galaxy", "to": "reader"})
        self.book = "G2"
        self.event(t + 400, "book.open", "reader",
                   {"via": "galaxy", "visit": 1, "page": 1, "pages": 300},
                   input=n)
        self.answer["galaxy_visit"] = {"start": v0, "end": t,
                                       "target": "Ангиология"}
        t = self.reading(t + 400, self.end - 1000, page=1)
        self.look(self.end - 950, self.end + 3000, 640, 400)
        self.event(self.end, "recording.stop", "reader",
                   {"by": "experimenter", "study_ms": self.end - rs.S})
        self.event(self.end + 60_000, "session.finish", "finish",
                   phase="post")
        return self

    def star(self, t: int, key: str, look: bool = True) -> int:
        _, x, y, _ = STARS[key]
        if look:
            self.look(t - 400, t + 50, x, y)
        n = self.tap(t, x, y, "galaxy", dev=self.pointer)
        self.event(t, "galaxy.star", "galaxy",
                   {"book": key, "selected": False}, input=n)
        self.event(t + 5, "galaxy.card.open", "galaxy", {"book": key},
                   input=n)
        return n

    def files(self, *, layout: bool = True, gaze: bool = True) -> dict:
        files = super().files(layout=layout, gaze=gaze)
        snapshot = {
            "schema": "sno2026-snapshot/1",
            "categories": [{"name": "Ангиология", "order": 0},
                           {"name": "Математика", "order": 1}],
            "books": [{"fingerprint": key, "title": TITLES[key],
                       "category": category, "position": i}
                      for i, (key, (category, *_)) in
                      enumerate(STARS.items())],
        }
        data = json.dumps(snapshot, ensure_ascii=False).encode()
        files["snapshot_start.json"] = data
        files["snapshot_end.json"] = data
        return files

    def manifest(self, files: dict, **kw) -> dict:
        manifest = super().manifest(files, **kw)
        manifest["branch"] = "II"
        manifest["app"]["version"] = "0.39.0-sno2026.II"
        return manifest


def make(folder, **kw):
    scenario = MapScenario(study_ms=120_000).build()
    return rs.make(folder, scenario=scenario,
                   name="sno2026_II_80032040_d10708_20261010-0811.zip",
                   **kw), scenario
