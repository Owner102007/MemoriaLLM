"""Шаг 40 — момент долгого взгляда без действий и карта внимания П5
(SNO-ALG-RES-09, SNO-F-RES-07).

Три слоя: правила на рядах, собранных руками (что режет момент, «смотрел»,
мера — секунды взгляда, пятно, отпечаток книги); страница книги через
pypdfium2 на PDF, собранном здесь же, — в геометрии листа; синтетическая
запись с известным ответом (`report_scenario.py`): заложенные моменты
чтения и поиска находятся до кадра, отрезок с взглядом мимо экрана и
отрезок с застывшим взглядом не берутся, а «Сравнение ветвей» кладёт П5
со страницей из архива литературы и `моменты.csv`.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import sys
import types
import zipfile
from pathlib import Path

import numpy as np
import pytest

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))

import report_scenario as rs  # noqa: E402
from sno_eye import record_check as rc  # noqa: E402
from sno_eye import report  # noqa: E402
from sno_eye.report import archive as arc  # noqa: E402
from sno_eye.study import moments as mo  # noqa: E402
from sno_eye.study import screen_shot as ss  # noqa: E402
from sno_eye import study  # noqa: E402

PC = {"look_share": 0.8, "moment_min_fix": 3, "moment_min_s": 5}


# --- PDF, собранный руками ---------------------------------------------------

def make_pdf(w: float = 595.0, h: float = 842.0,
             box=(100.0, 600.0, 120.0, 80.0)) -> bytes:
    """Одностраничный PDF: синий прямоугольник [box] (`x, y снизу, ширина,
    высота` в пунктах) на белой странице [w] × [h]."""
    x, y, bw, bh = box
    stream = f"0 0 1 rg {x} {y} {bw} {bh} re f".encode()
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {w} {h}] "
        f"/Contents 4 0 R >>".encode(),
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n"
        + stream + b"\nendstream",
    ]
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objs, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += (f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref}\n%%EOF\n").encode()
    return bytes(out)


# --- разрезы ----------------------------------------------------------------

def _record(inputs=(), frames=()):
    return types.SimpleNamespace(
        inputs={i + 1: dict(r, n=i + 1) for i, r in enumerate(inputs)},
        frames=list(frames))


def _line(screens=((0, "reader"),), away=()):
    return types.SimpleNamespace(screens=list(screens), away=list(away))


def test_alg_res_09_actions_cut_and_hover_does_not():
    """SNO-ALG-RES-09: нажатие, отменённое касание, прокрутка, клавиша и
    новый кадр режут отрезок; удержание и протяжка — всем своим
    отрезком; путь мыши — нет."""
    rec = _record(inputs=[
        {"t": 1000, "dt": 80, "dev": "mouse", "kind": "tap"},
        {"t": 3000, "dt": 50, "dev": "touch", "kind": "cancel"},
        {"t": 5000, "dt": 300, "dev": "wheel"},
        {"t": 7000, "dt": 20, "dev": "key"},
        {"t": 9000, "dt": 2000, "dev": "touch", "kind": "long"},
        {"t": 12000, "dt": 900, "dev": "mouse", "kind": "drag"},
        {"t": 14000, "dev": "hover", "trail": [[0, 1, 1], [100, 2, 2]]},
    ], frames=[{"t": 16000}])
    blocks, hover = mo.cuts(rec, _line(), [], 0, 20000)
    got = mo.gaps(blocks, 0, 20000)
    assert got == [(0, 1000), (1080, 3000), (3050, 5000), (5300, 7000),
                   (7020, 9000), (11000, 12000), (12900, 16000),
                   (16000, 20000)]
    assert hover == [(14000, 1.0), (14100, 1.0)]
    assert mo.hover_share(hover, 12900, 16000) == pytest.approx(
        200 / 3100)


def test_alg_res_09_moving_away_and_screen_change_cut():
    rec = _record(frames=[{"t": 0}])
    line = _line(screens=[(0, "reader"), (8000, "shelf")],
                 away=[(4000, 6000, "hidden")])
    blocks, _ = mo.cuts(rec, line, [(2000, 2500)], 0, 10000)
    assert mo.gaps(blocks, 0, 10000) == [(0, 2000), (2500, 4000),
                                        (6000, 8000), (8000, 10000)]


def test_alg_res_09_looked_is_on_screen_gaze_not_length():
    """Мера — секунды взгляда на экране: кадры вне экрана, без лица,
    моргания и вне приложения в неё не идут."""
    labels = mo.Labels([(0, 100, "page", "page"), (100, 100, "x", "outside"),
                        (200, 100, "x", "no_face"), (300, 100, "x", "blink"),
                        (400, 100, "x", "saccade"), (500, 100, "x", "away"),
                        (600, 100, "x", "unknown")])
    assert labels.looked_ms(0, 700) == 300
    assert labels.looked_ms(50, 450) == 100   # пересечение с отрезком


def _fix(t, d=250, x=100.0, y=100.0, moving=False):
    return {"start": t, "end": t + d, "duration": d, "x": x, "y": y,
            "moving": moving}


def test_alg_res_09_verdicts():
    """Мало смотрел — не берётся даже самый длинный; меньше трёх
    фиксаций — «взгляд стоял»; короче 5 с — не момент."""
    full = mo.Labels([(t, 100, "p", "page") for t in range(0, 30000, 100)])
    half = mo.Labels([(t, 100, "p", "page" if t < 6000 else "outside")
                      for t in range(0, 30000, 100)])
    fixes = [_fix(t) for t in range(0, 30000, 300)]
    assert mo.assess(0, 4000, full, fixes, PC)["status"] == mo.SHORT
    assert mo.assess(0, 10000, half, fixes, PC)["status"] == mo.LITTLE
    assert mo.assess(0, 10000, full, [_fix(0, 9000)], PC)["status"] == \
        mo.STARE
    ok = mo.assess(0, 10000, full, fixes + [_fix(5000, moving=True)], PC)
    assert ok["status"] == mo.OK
    assert len(ok["fixations"]) == 34          # фиксация движения не идёт
    # Фиксация, вылезшая за конец отрезка, обрезана им.
    cut = mo.assess(0, 10000, full, [_fix(9900, 400)] * 3, PC)
    assert cut["fixations"][0]["d"] == 100


def test_alg_res_09_nearest_anchor():
    assert mo.nearest_anchor_s([], 5000) is None
    assert mo.nearest_anchor_s([1000, 20000], 5000) == 4.0
    assert mo.nearest_anchor_s([1000, 20000], 18000) == 2.0


# --- пятно ------------------------------------------------------------------

def test_alg_res_09_spot_sums_to_one_peak_at_fixation_sigma_widens():
    fixes = [{"x": 402.0, "y": 202.0, "d": 600.0},
             {"x": 902.0, "y": 602.0, "d": 200.0}]
    grid, step = ss.spot(fixes, 1280, 800, 30.0)
    assert grid.sum() == pytest.approx(1.0)
    r, c = np.unravel_index(grid.argmax(), grid.shape)
    assert abs((c + 0.5) * step - 402) <= step
    assert abs((r + 0.5) * step - 202) <= step
    # Вес — длительность: у долгой фиксации пик выше.
    other = grid[int(602 // step), int(902 // step)]
    assert grid.max() > 2.5 * other
    wide, _ = ss.spot(fixes, 1280, 800, 60.0)
    assert wide.max() < grid.max()
    assert ss.spot([], 100, 100, 10.0)[0].sum() == 0


def test_alg_res_09_sigma_from_accuracy():
    """σ = √(1² + точность²): точность 0 — фовеа, 1°."""
    for acc, sigma in ((0.0, 1.0), (1.0, math.sqrt(2)), (2.0, math.sqrt(5))):
        assert math.sqrt(1 + acc * acc) == pytest.approx(sigma)


# --- книга по отпечатку -------------------------------------------------------

def _dart_fingerprint(data: bytes) -> str:
    """Вторая запись правила `bookFingerprint`
    (`lib/infrastructure/files/file_fingerprint.dart`)."""
    probe = 64 * 1024
    size = len(data)
    head = data[:min(size, probe)]
    tail = b""
    if size > probe:
        start = probe if size - probe < probe else size - probe
        tail = data[start:]
    return f"{size}-{hashlib.sha256(head + tail).hexdigest()}"


@pytest.mark.parametrize("size", [10, 64 * 1024, 64 * 1024 + 7,
                                  100 * 1024, 300 * 1024])
def test_alg_res_09_fingerprint_like_app(size):
    data = bytes((i * 7) % 251 for i in range(size))
    assert ss.fingerprint_of(data) == _dart_fingerprint(data)


def test_alg_res_09_page_from_literature_archive(tmp_path):
    pdf = make_pdf()
    fp = ss.fingerprint_of(pdf)
    lit = tmp_path / "Литература.zip"
    with zipfile.ZipFile(lit, "w") as z:
        z.writestr("01 Физиология/Физиология сердца.pdf", pdf)
        z.writestr("лишнее.txt", b"x")
    lib = ss.Library([str(tmp_path)])
    image, why = lib.page(fp, 1, 1.0)
    assert why is None and image.shape == (842, 595, 3)
    # Синий прямоугольник: x 100–220, y снизу 600–680 → сверху 162–242.
    assert tuple(image[200, 160]) == (0, 0, 255)
    assert tuple(image[100, 160]) == (255, 255, 255)
    assert lib.page(fp, 2, 1.0)[1] == "страницы 2 в книге нет"
    assert lib.page("123-abc", 1, 1.0)[1] == "книги нет в архиве литературы"
    assert ss.Library([]).page(fp, 1, 1.0)[1] == \
        "архива литературы рядом нет"
    # Архив записи литературой не считается.
    with zipfile.ZipFile(tmp_path / "sno2026_I_1_x_y.zip", "w") as z:
        z.writestr("a.pdf", pdf)
    assert sum(1 for _, p, _ in ss.Library([str(tmp_path)]).files
               if p.name.startswith("sno2026_")) == 0


def _moment(frame, fixes=()):
    return {"frame": frame, "fixations": list(fixes), "sigma_px": 20.0,
            "looked_ms": 9000.0, "length_ms": 10000.0, "minute": 3.0,
            "accuracy_deg": 1.0, "sigma_deg": math.sqrt(2),
            "hover_share": 0.1, "anchor_s": 12.0, "groups": []}


def test_alg_res_09_page_in_sheet_geometry(tmp_path):
    """Страница на снимке — в геометрии листа кадра: место и масштаб
    страницы, затемнение вне читаемой полосы."""
    pdf = make_pdf()
    fp = ss.fingerprint_of(pdf)
    (tmp_path / "book.pdf").write_bytes(pdf)
    regions, sheet = rs.reader_frame(7)
    sheet = dict(sheet, strip=[rs.PAGE_X, 100, 595 * rs.SCALE, 300])
    frame = {"t": 0, "viewport": {"w": rs.W, "h": rs.H}, "regions": regions,
             "sheet": sheet, "book": fp}
    fig, ax = plt.subplots()
    lib = ss.Library([str(tmp_path / "book.pdf")])
    lib.page(fp, 1, 1.0)       # книга одностраничная: стр. 7 нет
    why = ss.draw_screen(ax, _moment(frame), {}, {}, lib)
    assert why == "страницы 7 в книге нет"
    plt.close(fig)
    sheet["pages"][0]["page"] = 1
    fig, ax = plt.subplots()
    assert ss.draw_screen(ax, _moment(frame), {}, {}, lib) is None
    image = ax.images[0]
    left, right, bottom, top = image.get_extent()
    assert (left, top) == (rs.PAGE_X, 0)
    assert right == pytest.approx(rs.PAGE_X + 595 * rs.SCALE)
    assert bottom == pytest.approx(842 * rs.SCALE)
    dims = [p for p in ax.patches if p.get_alpha() == 0.45]
    assert [(p.get_y(), p.get_height()) for p in dims] == [
        (0, 100), (400, pytest.approx(842 * rs.SCALE - 400))]
    plt.close(fig)


def test_alg_res_09_without_literature_and_without_frame():
    regions, sheet = rs.reader_frame(1)
    frame = {"t": 0, "viewport": {"w": rs.W, "h": rs.H}, "regions": regions,
             "sheet": sheet, "book": "1-ab"}
    fig, ax = plt.subplots()
    assert ss.draw_screen(ax, _moment(frame), {}, {}, None) == \
        "архива литературы рядом нет"
    texts = " ".join(t.get_text() for t in ax.texts)
    assert ss.NO_TEXT in texts
    plt.close(fig)
    fig, ax = plt.subplots()
    assert ss.draw_screen(ax, _moment(None), {}, {}, None) == \
        "кадра раскладки нет"
    plt.close(fig)


def test_alg_res_09_shelf_zones_on_their_places():
    """Снимок полки: блок книги с её названием на месте зоны кадра."""
    frame = {"t": 0, "viewport": {"w": rs.W, "h": rs.H},
             "regions": rs.shelf_regions()}
    fig, ax = plt.subplots()
    ss.draw_screen(ax, _moment(frame), {"F2": "Физиология сердца"},
                   {"F2": "Физиология"}, None)
    hit = [t for t in ax.texts if "Физиология сердца" in t.get_text()]
    assert hit
    x, y = hit[0].get_position()
    bx, by, bw, bh = rs.BOOKS["F2"][1]
    assert bx <= x <= bx + bw and by <= y <= by + bh
    plt.close(fig)


# --- синтетическая запись с известным ответом -------------------------------

class Still(rs.Scenario):
    """Участник: поход на полку, чтение с нажатиями, затем заложенные
    отрезки без действий — момент чтения (15 с), отрезок длиннее, где
    половину времени смотрит мимо экрана, отрезок ещё длиннее с
    застывшим взглядом — и поход на полку с долгим взглядом по книгам
    (10 с)."""

    def __init__(self, book: str, **kw):
        super().__init__(study_ms=200_000, **kw)
        self.fp = book

    def lines(self, a: int, b: int, page: int) -> None:
        t, line, col = a, 0, 0
        while t < b - 270:
            self.look(t, t + 230, 420 + col * 100, 120 + line * 40)
            t += 270
            col += 1
            if col == 5:
                col, line = 0, (line + 1) % 15

    def build(self) -> "Still":
        S = rs.S
        self.event(0, "recording.start", "testing",
                   {"participant": "93461318", "planned_s": 2400})
        self.frame(0, "testing", [
            {"kind": "screen", "id": "testing", "rect": [0, 0, rs.W, rs.H],
             "z": 0}])
        self.event(S, "study.start", "testing", {"gaze": True})
        self.look(S - 2000, S + 600, 640, 400)
        t = self.visit(S + 1000, first=True)
        self.book = self.fp
        regions, sheet = rs.reader_frame(1)
        self.frame(t, "reader", regions, sheet)
        # Чтение с нажатием по панели раз в 2 с — моментов нет.
        for _ in range(4):
            self.lines(t + 100, t + 1500, 1)
            t += 2000
            self.click(t, 100, 28, "reader", "panel.open", {"panel": "top"})
        a = t
        # Момент чтения: 15 с без действий; первые 2 с мышь двигалась.
        self.lines(a + 100, a + 15_000 - 450, 1)
        self.inputs.append({"n": len(self.inputs) + 1, "t": a + 500,
                            "dev": "hover", "trail": [[k * 100, 600, 300]
                                                      for k in range(20)],
                            "vw": rs.W, "vh": rs.H, "screen": "reader"})
        t = a + 15_000
        self.click(t, 100, 28, "reader", "panel.open", {"panel": "top"})
        self.answer["reading"] = (a + 80, t)
        # Длиннее, но половину времени взгляд за нижним краем экрана.
        b = t
        self.lines(b + 100, b + 11_000, 1)
        self.look(b + 11_000, b + 22_000 - 450, 640, rs.H + 300)
        t = b + 22_000
        self.click(t, 100, 28, "reader", "panel.open", {"panel": "top"})
        self.answer["little"] = (b + 80, t)
        # Ещё длиннее, но взгляд стоит в одной точке.
        c = t
        self.look(c + 100, c + 18_000 - 450, 700, 380)
        t = c + 18_000
        self.click(t, 100, 28, "reader", "panel.open", {"panel": "top"})
        self.answer["stare"] = (c + 80, t)
        # На полку: десять секунд смотрит по книгам, ничего не нажимая.
        t += 600
        self.click(t, 30, 28, "reader", "nav.screen",
                   {"from": "reader", "to": "shelf"})
        self.event(t, "book.close", "reader", {"by": "back"})
        self.book = None
        self.frame(t, "shelf", rs.shelf_regions())
        q = t
        for k, name in enumerate(("A1", "A2", "F1", "F3")):
            x, y = rs.centre(name)
            self.look(q + 100 + k * 2400, q + 2300 + k * 2400, x, y)
        t = q + 10_000
        bx, by = rs.centre("F2")
        n = self.click(t, bx, by, "shelf", "nav.screen",
                       {"from": "shelf", "to": "reader"})
        self.answer["search"] = (q + 80, t)
        self.book = self.fp
        self.event(t + 400, "book.open", "reader",
                   {"via": "shelf", "visit": 2, "page": 1, "pages": 1},
                   input=n)
        self.frame(t + 400, "reader", regions, sheet)
        # Дальше снова чтение с нажатием раз в 2 с — моментов нет.
        t += 400
        while t + 2000 < self.end - 1000:
            self.lines(t + 100, t + 1500, 1)
            t += 2000
            self.click(t, 100, 28, "reader", "panel.open", {"panel": "top"})
        self.look(self.end - 950, self.end + 3000, 640, 400)
        self.event(self.end, "recording.stop", "reader",
                   {"by": "experimenter", "study_ms": self.end - S})
        self.event(self.end + 60_000, "session.finish", "finish",
                   phase="post")
        return self


@pytest.fixture(scope="module")
def planted(tmp_path_factory):
    folder = tmp_path_factory.mktemp("step40")
    pdf = make_pdf()
    fp = ss.fingerprint_of(pdf)
    scen = Still(fp).build()
    path = rs.make(folder, scenario=scen)
    with zipfile.ZipFile(folder / "Литература S1.zip", "w") as z:
        z.writestr("Физиология/Физиология сердца.pdf", pdf)
    limits = rc.thresholds()
    record = arc.load(path, limits)
    report_cfg = report.settings()
    res = report.analyse(record, report_cfg, limits)
    cfg = study.settings()
    got = mo.prepare(res, record, cfg, report_cfg)
    return {"folder": folder, "scen": scen, "got": got, "fp": fp,
            "path": path, "res": res}


def test_alg_res_09_planted_reading_moment_found(planted):
    got, ans = planted["got"], planted["scen"].answer
    m = got["moments"][mo.READING]
    assert m is not None
    assert abs(m["a"] - ans["reading"][0]) <= rs.PERIOD
    assert abs(m["b"] - ans["reading"][1]) <= rs.PERIOD
    assert m["share"] > 0.95
    assert len(m["fixations"]) >= 20
    assert m["hover_share"] == pytest.approx(2000 / (m["b"] - m["a"]),
                                             abs=0.01)
    # Отрезок длиннее, но мимо экрана, — не взят; застывший — тоже, и он
    # назван длиннее взятого.
    by_a = {round(c["a"]): c for c in got["candidates"]}
    little = by_a[ans["little"][0]]
    assert little["status"] == mo.LITTLE and little["share"] < 0.6
    stare = by_a[ans["stare"][0]]
    assert stare["status"] == mo.STARE
    assert m["stare_longer"] == pytest.approx(stare["looked_ms"])
    assert m["frame"]["book"] == planted["fp"]
    assert m["anchor_s"] is not None


def test_alg_res_09_planted_search_moment_and_numbers(planted):
    got, ans = planted["got"], planted["scen"].answer
    q = got["moments"][mo.SEARCH]
    assert q is not None
    assert abs(q["a"] - ans["search"][0]) <= rs.PERIOD
    assert abs(q["b"] - ans["search"][1]) <= rs.PERIOD
    assert q["screen"] == "shelf"
    nums = got["numbers"]
    assert nums["portrait.search_still_s"] == pytest.approx(
        q["looked_ms"] / 1000)
    assert 0 < nums["portrait.search_still_share"] < 1


def test_alg_res_09_study_writes_p5_and_moments_csv(planted, tmp_path):
    out = tmp_path / "отчёт"
    code = study.main([str(planted["folder"])], out=str(out),
                      no_filter=True)
    assert code == 0
    folder = out / "Портреты" / "93461318"
    assert (folder / "П5_чтение.png").exists()
    assert (folder / "П5_поиск.svg").exists()
    page = (out / "Портреты" / "93461318.html").read_text(encoding="utf-8")
    assert "П5. Внимание в момент долгого взгляда" in page
    # Страница нарисована: книга нашлась в архиве литературы рядом.
    assert "страница на снимке не нарисована" not in page
    with open(out / "моменты.csv", encoding="utf-8-sig") as f:
        rows = list(csv.reader(f, delimiter=";"))
    head = rows[0]
    taken = [r for r in rows[1:] if r[head.index("итог")] == "взят — П5"]
    assert sorted(r[head.index("фаза")] for r in taken) == ["поиск",
                                                           "чтение"]
    assert len({len(r) for r in rows}) == 1
    src = json.loads((out / "исходные.json").read_text(encoding="utf-8"))
    # Скрипт шага 40 или новее: номер поднимает каждый следующий шаг.
    assert float(src["script"]) >= 40.0
    assert src["thresholds"]["study"]["portrait"]["look_share"] == 0.8


def test_alg_res_09_study_without_literature_says_so(planted, tmp_path):
    out = tmp_path / "без"
    assert study.main([str(planted["path"])], out=str(out),
                      no_filter=True) == 0
    page = (out / "Портреты" / "93461318.html").read_text(encoding="utf-8")
    assert "страница на снимке не нарисована: архива литературы рядом " \
        "нет" in page


def test_alg_res_09_pypdfium2_in_lock_for_both_platforms():
    """pypdfium2 — в замке спутника с суммами колёс Windows и Linux, и
    версия та же, что названа в `requirements.in` (АЛ1 (а))."""
    eye = Path(__file__).resolve().parent.parent
    lock = (eye / "requirements.lock").read_text(encoding="utf-8")
    pinned = [line for line in (eye / "requirements.in").read_text(
        encoding="utf-8").splitlines() if line.startswith("pypdfium2==")]
    assert len(pinned) == 1
    block = lock.split(pinned[0] + " \\\n", 1)[1].split("\n\n")[0]
    head = []
    for line in block.splitlines():
        if "--hash=sha256:" not in line:
            break
        head.append(line)
    assert len(head) == 2


# --- границы (по независимой проверке шага) ----------------------------------

def test_alg_res_09_verdict_edges_are_inclusive():
    """Ровно 0,8 смотрения, ровно 5 с и ровно три фиксации — момент."""
    labels = mo.Labels([(t, 100, "p", "page" if t < 4000 else "outside")
                        for t in range(0, 5000, 100)])
    fixes = [_fix(0), _fix(1000), _fix(2000)]
    seg = mo.assess(0, 5000, labels, fixes, PC)
    assert seg["share"] == pytest.approx(0.8)
    assert seg["status"] == mo.OK
    assert mo.assess(0, 4999, labels, fixes, PC)["status"] == mo.SHORT
    assert mo.assess(0, 5000, labels, fixes[:2], PC)["status"] == mo.STARE
    # Фиксация, начавшаяся на самом конце отрезка, — уже не его.
    assert len(mo.assess(0, 5000, labels, fixes + [_fix(5000)],
                         PC)["fixations"]) == 3


def test_alg_res_09_cut_edges():
    """Отрицательная длительность строки — точка; точка пути мыши на
    самом конце отрезка в долю не идёт."""
    rec = _record(inputs=[{"t": 1000, "dt": -50, "dev": "key"}])
    blocks, _ = mo.cuts(rec, _line(), [], 0, 2000)
    assert mo.gaps(blocks, 0, 2000) == [(0, 1000), (1000, 2000)]
    assert mo.hover_share([(1000.0, 1.0), (2000.0, 1.0)], 1000, 2000) == \
        pytest.approx(0.1)


def test_alg_res_09_spot_cell_by_hand():
    """Клетка пятна, посчитанная руками: середины клеток — (k + ½)·шаг,
    ядро exp(−r² / 2σ²)."""
    fixes = [{"x": 10.0, "y": 6.0, "d": 300.0},
             {"x": 2.0, "y": 2.0, "d": 100.0}]
    grid, step = ss.spot(fixes, 16, 8, 3.0, step=4.0)

    def raw(cx, cy):
        return sum(f["d"] * math.exp(-((cx - f["x"]) ** 2 +
                                       (cy - f["y"]) ** 2) / 18.0)
                   for f in fixes)
    total = sum(raw((c + 0.5) * 4, (r + 0.5) * 4)
                for r in range(2) for c in range(4))
    assert grid.shape == (2, 4)
    assert grid[1, 2] == pytest.approx(raw(10, 6) / total, rel=1e-12)
    assert grid[0, 0] == pytest.approx(raw(2, 2) / total, rel=1e-12)


def _fake_res(segments, screens, study_end=60_000):
    """Разбор, собранный руками: [segments] — `(от, до, смотрел ли,
    фиксаций)` подряд, между ними нажатия."""
    labels, fixes, inputs = [], [], []
    for a, b, look, n in segments:
        for t in range(a, b, 100):
            labels.append((t, 100, "p", "page" if look else "outside"))
        for k in range(n):
            fixes.append(_fix(a + 100 + k * 300))
        inputs.append({"t": b, "dt": 0, "dev": "mouse", "kind": "tap"})
    line = types.SimpleNamespace(
        study_start=0.0, study_end=float(study_end), window_changed=None,
        screens=list(screens), away=[], start_deg=1.0, end_deg=1.0,
        titles={}, categories={})
    line.screen_at = lambda t: [name for at, name in line.screens
                                if at <= t][-1]
    res = {"_timeline": line, "_labels": labels, "fixations": fixes,
           "_spans": [], "_zones": None, "_anchors": [],
           "_screen": types.SimpleNamespace(px_for_deg=lambda d: d * 40)}
    rec = _record(inputs=inputs)
    return res, rec


def test_alg_res_09_tie_takes_first_and_short_search_counts():
    """Ничья — первый; самый долгий взгляд без действий в поиске берёт и
    отрезок короче порога момента."""
    res, rec = _fake_res([(0, 6000, True, 5), (6000, 12000, True, 5),
                          (12000, 15000, True, 4)],
                         [(0, "reader"), (12000, "shelf")], 15000)
    got = mo.prepare(res, rec, {"portrait": PC}, {"version": "drift"})
    assert got["moments"][mo.READING]["a"] == 0
    assert got["moments"][mo.SEARCH] is None
    assert got["numbers"]["portrait.search_still_s"] == pytest.approx(3.0)
    assert got["numbers"]["portrait.search_still_share"] == 0
    # В поиске не смотрели — ноль, а не пусто; поиска нет — пусто.
    res, rec = _fake_res([(0, 6000, False, 5)], [(0, "shelf")], 6000)
    got = mo.prepare(res, rec, {"portrait": PC}, {"version": "raw"})
    assert got["numbers"]["portrait.search_still_s"] == 0
    res, rec = _fake_res([(0, 6000, True, 5)], [(0, "reader")], 6000)
    got = mo.prepare(res, rec, {"portrait": PC}, {"version": "raw"})
    assert got["numbers"]["portrait.search_still_s"] is None
    assert got["moments"][mo.READING]["anchor_s"] is None
