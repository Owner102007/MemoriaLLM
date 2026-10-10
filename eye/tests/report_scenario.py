"""Синтетическая запись с известным ответом — для разбора (шаг 34).

Участник на ПК: калибровка, затем полка (поход 1: смотрит на книгу
«Анатомии», на край соседней, на «Физиологию» между книгами и
открывает книгу «Физиологии»), чтение с перелистыванием и нажатиями
мышью по панели, взгляд за экран, лицо пропало, отлучка, второй поход
на полку с запросом по названию — сразу в нужную категорию — и снова
чтение до остановки. Взгляд — истинный путь плюс шум, постоянный
дрейф и задержка камеры; всё это разбор обязан найти.

Формат — как у приложения: журнал (`encodeEvent`), ввод
(`input_tap.dart`), кадры раскладки (`layout_frames.dart`), взгляд
(`gaze.py`), манифест (`archive.dart`). Что тот же разбор читает архив,
собранный самим приложением, проверяет `test/sno/record_report_test.dart`.
"""

from __future__ import annotations

import hashlib
import json
import random
import zipfile
from pathlib import Path

W, H = 1280.0, 800.0
SCREEN = {"w": W, "h": H, "w_mm": 340.0, "h_mm": 212.5,
          "distance_mm": 600.0}
S = 60_000                     # study.start: минута калибровки до него
LATENCY = 60                   # задержка камеры, мс
DRIFT = (30.0, -20.0)          # оценка ушла на столько пикселей
PERIOD = 33                    # мс между кадрами взгляда

NAME = "sno2026_I_93461318_d10708_20261010-0900.zip"

# Полка: две категории по три книги.
BOOKS = {
    "A1": ("Анатомия", (40, 120, 300, 210), "Анатомия человека"),
    "A2": ("Анатомия", (440, 120, 300, 210), "Атлас анатомии"),
    "A3": ("Анатомия", (840, 120, 300, 210), "Остеология"),
    "F1": ("Физиология", (40, 420, 300, 210), "Нормальная физиология"),
    "F2": ("Физиология", (440, 420, 300, 210), "Физиология сердца"),
    "F3": ("Физиология", (840, 420, 300, 210), "Физиология почки"),
}


def centre(book: str) -> tuple[float, float]:
    x, y, w, h = BOOKS[book][1]
    return x + w / 2, y + h / 2


def shelf_regions(offset: float = 0.0) -> list[dict]:
    regions = [
        {"kind": "screen", "id": "shelf", "rect": [0, 0, W, H], "z": 0,
         "info": {"scroll": offset}},
        {"kind": "nav", "id": "", "rect": [0, 0, W, 56], "z": 1},
    ]
    z = 2
    for name, top in (("Анатомия", 70), ("Физиология", 370)):
        regions.append({"kind": "shelf_category", "id": name,
                        "rect": [16, top, 1248, 30], "z": z,
                        "info": {"part": "header"}})
        regions.append({"kind": "shelf_category", "id": name,
                        "rect": [16, top + 30, 1248, 250], "z": z + 1,
                        "info": {"part": "area"}})
        z += 2
        for book, (category, rect, _) in BOOKS.items():
            if category == name:
                regions.append({"kind": "shelf_book", "id": book,
                                "rect": list(rect), "z": z,
                                "info": {"category": category}})
                z += 1
    regions.append({"kind": "recording_dot", "id": "",
                    "rect": [1240, 760, 30, 30], "z": z})
    return regions


PAGE_X = 357.4
SCALE = 0.95


def reader_frame(page: int) -> tuple[list[dict], dict]:
    regions = [
        {"kind": "page", "id": "", "rect": [0, 0, W, H], "z": 0},
        {"kind": "panel_top", "id": "", "rect": [0, 0, W, 56], "z": 1},
        {"kind": "recording_dot", "id": "", "rect": [1240, 760, 30, 30],
         "z": 2},
    ]
    sheet = {"y_down": True, "scale": SCALE,
             "pages": [{"page": page, "x": PAGE_X, "y": 0, "w": 595,
                        "h": 842}],
             "rect": [PAGE_X, 0, 595 * SCALE, 842 * SCALE],
             "content": [PAGE_X, 0, 595 * SCALE, 842 * SCALE],
             "strip": [PAGE_X, 0, 595 * SCALE, 842 * SCALE],
             "strip_index": 1, "strips": 1, "neighbours": []}
    return regions, sheet


def jsonl(rows) -> bytes:
    return "".join(json.dumps(r, ensure_ascii=False) + "\n"
                   for r in rows).encode("utf-8")


class Scenario:
    """Запись по сценарию: истинный путь взгляда и действия."""

    def __init__(self, *, study_ms: int = 600_000, seed: int = 7,
                 noise: float = 4.0, drift=DRIFT, latency: int = LATENCY,
                 pointer: str = "mouse"):
        self.end = S + study_ms
        self.rng = random.Random(seed)
        self.noise = noise
        self.drift = drift
        self.latency = latency
        self.events: list[dict] = []
        self.inputs: list[dict] = []
        self.frames: list[dict] = []
        self.looks: list[tuple] = []        # (a, b, x, y) или без лица
        self.answer: dict = {"visits": [], "reading": [], "moving": []}
        self.book: str | None = None
        self.pointer = pointer

    # --- действия ----------------------------------------------------
    def event(self, t, kind, screen, data=None, input=None, phase=None):
        row = {"t": int(t), "wall": "2026-10-10T09:00:00+03:00",
               "type": kind, "screen": screen}
        if self.book is not None and screen == "reader":
            row["book"] = self.book
        if input is not None:
            row["input"] = input
        if phase is not None:
            row["phase"] = phase
        if data:
            row["data"] = data
        self.events.append(row)

    def tap(self, t, x, y, screen, dev="mouse", kind="tap") -> int:
        n = len(self.inputs) + 1
        self.inputs.append({"n": n, "t": int(t), "dt": 80, "dev": dev,
                            "button": "primary", "kind": kind, "x": x,
                            "y": y, "x1": x, "y1": y, "path": 0,
                            "vw": W, "vh": H, "screen": screen})
        return n

    def frame(self, t, screen, regions, sheet=None, moving=False):
        row = {"t": int(t), "screen": screen, "moving": moving,
               "viewport": {"w": W, "h": H, "dpr": 1.5,
                            "orientation": "landscape"},
               "regions": regions}
        if sheet is not None:
            row["sheet"] = sheet
        if screen == "reader" and self.book:
            row["book"] = self.book
        self.frames.append(row)

    def look(self, a, b, x, y):
        self.looks.append((a, b, x, y))

    def blank(self, a, b):
        self.looks.append((a, b, None, None))

    def click(self, t, x, y, screen, kind, data=None, after=None):
        """Смотрит на цель 400 мс и нажимает её мышью."""
        self.look(t - 400, t + 50, x, y)
        n = self.tap(t, x, y, screen, dev=self.pointer)
        self.event(t, kind, screen, data, input=n)
        return n

    # --- сценарий ----------------------------------------------------
    def build(self) -> "Scenario":
        self.event(0, "recording.start", "testing",
                   {"participant": "93461318", "planned_s": 2400})
        self.frame(0, "testing", [
            {"kind": "screen", "id": "testing", "rect": [0, 0, W, H],
             "z": 0},
            {"kind": "nav", "id": "", "rect": [0, 0, W, 56], "z": 1}])
        self.event(S, "study.start", "testing", {"gaze": True})
        self.look(S - 2000, S + 500, 640, 400)
        t = self.visit(S + 1000, first=True)
        t = self.reading(t, S + 200_000, page=1)
        # Взгляд за экран, лицо пропало, отлучка.
        self.look(t + 50, t + 3050, 640, H + 200)
        self.answer["outside"] = (t + 50, t + 3050)
        self.blank(t + 3100, t + 5100)
        self.answer["no_face"] = (t + 3100, t + 5100)
        away = t + 6000
        self.look(t + 5150, away - 50, 640, 400)
        self.event(away, "app.background", "reader", {"state": "hidden"})
        self.blank(away, away + 5000)
        self.event(away + 5000, "app.foreground", "reader",
                   {"away_ms": 5000, "kind": "hidden", "hidden_ms": 5000})
        self.answer["away"] = (away, away + 5000)
        t = self.reading(away + 5500, S + 300_000, page=12)
        # Назад на полку.
        self.event(t, "book.close", "reader", {"by": "back"})
        self.book = None
        t = self.visit(t + 400, first=False)
        self.reading(t, self.end - 1000, page=1)
        self.look(self.end - 950, self.end + 3000, 640, 400)
        self.event(self.end, "recording.stop", "reader",
                   {"by": "experimenter", "study_ms": self.end - S})
        self.event(self.end + 60_000, "session.finish", "finish",
                   phase="post")
        return self

    def visit(self, v0: int, first: bool) -> int:
        """Поход на полку; отвечает мигом, когда открылась книга."""
        screen = "testing" if first else "reader"
        self.click(v0, 160 if first else 30, 28, screen, "nav.screen",
                   {"from": screen, "to": "shelf"})
        self.frame(v0, "shelf", shelf_regions())
        if first:
            plan = [("A2", centre("A2")), ("A1-edge", (330.0, 225.0)),
                    ("gap-F", (390.0, 525.0)), ("F2", centre("F2"))]
            target, book = "Физиология", "F2"
            opened = v0 + 5000
        else:
            self.event(v0 + 500, "search.query", "shelf",
                       {"scope": "shelf", "chars": 3, "hits": 1})
            plan = [("A3", centre("A3"))]
            target, book = "Анатомия", "A3"
            opened = v0 + 1400
        a = v0 + 300
        starts = {}
        step = (opened - 400 - a) // max(1, len(plan))
        for i, (name, (x, y)) in enumerate(plan):
            b = opened - 400 if i == len(plan) - 1 else a + step - 100
            self.look(a, b, x, y)
            starts[name] = a
            a = b + 100
        bx, by = centre(book)
        n = self.click(opened, bx, by, "shelf", "nav.screen",
                       {"from": "shelf", "to": "reader"})
        self.book = book
        self.event(opened + 400, "book.open", "reader",
                   {"via": "shelf", "visit": 1, "page": 1, "pages": 300},
                   input=n)
        self.answer["visits"].append({
            "start": v0, "end": opened, "target": target, "book": book,
            "starts": starts, "searches": 0 if first else 1})
        return opened + 400

    def reading(self, t0: int, t1: int, page: int) -> int:
        """Чтение: строки фиксаций, перелистывание раз в 30 с с одной
        фиксацией на отрезке движения, нажатия по панели раз в 6 с."""
        regions, sheet = reader_frame(page)
        self.frame(t0, "reader", regions, sheet)
        t = t0 + 200
        next_tap = t + 3000
        next_turn = t0 + 30_000
        line, col = 0, 0
        while t < t1 - 600:
            if t >= next_turn:
                page += 1
                self.frame(t, "reader", reader_frame(page)[0],
                           reader_frame(page)[1], moving=True)
                self.event(t, "page.shown", "reader",
                           {"cause": "key", "from": page - 1})
                self.look(t + 20, t + 260, 600, 400)
                self.answer["moving"].append((t + 20, t + 260))
                regions, sheet = reader_frame(page)
                self.frame(t + 300, "reader", regions, sheet)
                t += 350
                next_turn = t + 30_000
                line, col = 0, 0
                continue
            if t >= next_tap:
                self.click(t + 400, 100, 28, "reader", "panel.open",
                           {"panel": "top"})
                t += 500
                next_tap = t + 6000
                continue
            x = 420 + col * 100
            y = 120 + line * 40
            self.look(t, t + 230, x, y)
            self.answer["reading"].append((t, x, y, page))
            t += 270
            col += 1
            if col == 5:
                col = 0
                line = (line + 1) % 15
        return t

    # --- взгляд ------------------------------------------------------
    def gaze_rows(self) -> list[dict]:
        looks = sorted(self.looks)
        rows = []
        n = 1
        i = 0
        t = S - 2000
        dx, dy = self.drift
        while t < self.end + 2000:
            while i + 1 < len(looks) and looks[i + 1][0] <= t:
                i += 1
            a, b, x, y = looks[i]
            if t >= b and i + 1 < len(looks):
                # Переход к следующей цели — по прямой; после провала
                # лица — сразу к ней.
                na, _, nx, ny = looks[i + 1]
                if x is None:
                    x, y = nx, ny
                elif nx is not None and na > b:
                    w = (t - b) / (na - b)
                    x, y = x + (nx - x) * w, y + (ny - y) * w
            face = x is not None
            row = {"n": n, "t": t + self.latency, "seg": 0,
                   "conf": 1.0 if face else 0.0}
            if face:
                gx = x + dx + self.rng.gauss(0, self.noise)
                gy = y + dy + self.rng.gauss(0, self.noise)
                row.update({"x": round(gx, 1), "y": round(gy, 1),
                            "ok": True, "dist": 1.0, "yaw": 2.0,
                            "pitch": -3.0, "roll": 0.5, "open_l": 0.3,
                            "open_r": 0.3})
            else:
                row.update({"x": None, "y": None, "ok": False,
                            "dist": None, "yaw": None, "pitch": None,
                            "roll": None, "open_l": None, "open_r": None})
            rows.append(row)
            n += 1
            t += PERIOD
        return rows

    # --- архив -------------------------------------------------------
    def files(self, *, layout: bool = True, gaze: bool = True) -> dict:
        events = sorted(self.events, key=lambda r: r["t"])
        for seq, row in enumerate(events, start=1):
            row["seq"] = seq
        frames = sorted(self.frames, key=lambda r: r["t"])
        for n, row in enumerate(frames, start=1):
            row["n"] = n
        snapshot = {
            "schema": "sno2026-snapshot/1",
            "categories": [{"name": "Анатомия", "order": 0},
                           {"name": "Физиология", "order": 1}],
            "books": [{"fingerprint": key, "title": title,
                       "category": category, "position": i % 3}
                      for i, (key, (category, _, title))
                      in enumerate(BOOKS.items())],
        }
        files = {
            "events.jsonl": jsonl(events),
            "input.jsonl": jsonl(self.inputs),
            "snapshot_start.json": json.dumps(snapshot).encode(),
            "snapshot_end.json": json.dumps(snapshot).encode(),
        }
        if layout:
            files["layout.jsonl"] = jsonl(frames)
        if gaze:
            shift_mm = [self.drift[0] * SCREEN["w_mm"] / W,
                        self.drift[1] * SCREEN["h_mm"] / H]
            files["eye/gaze.jsonl"] = jsonl(self.gaze_rows())
            files["eye/calibration.json"] = json.dumps({
                "schema": "sno2026-eyecal/2", "screen": SCREEN,
                "attempts": [{"attempt": 1, "kind": "full",
                              "fit": {"latency_ms": self.latency},
                              "validation": {"accuracy_deg": 1.0,
                                             "precision_deg": 0.3}}],
            }).encode()
            files["eye/checks.json"] = json.dumps(
                [{"n": 1, "accuracy_deg": 1.2, "shift_mm": shift_mm}]
            ).encode()
            files["eye/features.bin"] = b"\x00" * 1024
        return files

    def manifest(self, files: dict, *, gaze: bool = True,
                 start_deg: float = 1.0, end_deg: float = 1.2,
                 pc: bool = True) -> dict:
        events = files["events.jsonl"].count(b"\n")
        eye = {"present": False, "configured": True,
               "reason": "selfcheck_failed"} if pc else {"present": False}
        if gaze:
            eye = {"present": True, "configured": True, "quality": "ok",
                   "source": "webcam",
                   "calibration": {"attempts": 1, "accepted": True,
                                   "accuracy_deg": start_deg,
                                   "precision_deg": 0.3,
                                   "latency_ms": self.latency},
                   "end_check": {"accuracy_deg": end_deg,
                                 "start_deg": start_deg},
                   "file": "eye/gaze.jsonl", "segments": 1}
        manifest = {
            "schema": "sno2026-recording/1", "branch": "I",
            "app": {"version": "0.39.0-sno2026.I", "commit": "b" * 40,
                    "study_tag": "sno2026-1", "built": "2026-10-10"},
            "device": {"node_id": "d10708aa", "code": "d10708",
                       "os": "windows" if pc else "Android"},
            "participant": {"code": "93461318", "generated": True},
            "recording": {
                "planned_s": 2400, "duration_ms": self.end,
                "duration_s": self.end // 1000, "stopped_by": "experimenter",
                "events": events, "finished": True, "in_background": False,
                "study_t": S if gaze else None,
                "away": {"count": 1, "total_ms": 5000, "hidden_ms": 5000,
                         "longest_ms": 5000}},
            "eye_tracker": eye,
            "clt": {"final": "complete", "checks_flags": 0},
        }
        if "input.jsonl" in files:
            manifest["input"] = {"file": "input.jsonl",
                                 "lines": files["input.jsonl"].count(b"\n")}
        if "layout.jsonl" in files:
            manifest["layout"] = {"file": "layout.jsonl", "units":
                                  "logical_px", "lines":
                                  files["layout.jsonl"].count(b"\n")}
        entries = {}
        for name, data in files.items():
            entry = {"bytes": len(data),
                     "sha256": hashlib.sha256(data).hexdigest()}
            if name.endswith(".jsonl"):
                entry["lines"] = data.count(b"\n")
            entries[name] = entry
        manifest["files"] = entries
        return manifest


def write(folder: Path, files: dict, manifest: dict, name: str = NAME,
          tamper: dict | None = None) -> Path:
    path = Path(folder) / name
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
        for entry, data in files.items():
            if tamper and entry in tamper:
                data = tamper[entry](data)
            z.writestr(entry, data)
    return path


def make(folder: Path, *, scenario: Scenario | None = None,
         layout: bool = True, gaze: bool = True, name: str = NAME,
         tamper: dict | None = None, **manifest_kw) -> Path:
    scenario = scenario or Scenario().build()
    files = scenario.files(layout=layout, gaze=gaze)
    manifest = scenario.manifest(files, gaze=gaze, **manifest_kw)
    return write(folder, files, manifest, name=name, tamper=tamper)
