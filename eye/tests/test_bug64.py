"""BUG-64 (правка шага 34, SNO-F-RES-03, SNO-ALG-EYE-05): разбор
записи видит взгляд на категорию на карте.

Владелец в пробной записи 10.10.2026 смотрел на название категории
над группой звёзд и сразу нажимал звезду этой категории — «это главное,
что мы отслеживаем». Разбор относил такой взгляд к «карте» без
категории: подписи групп рисует художник карты, в кадре раскладки их
нет. Синтетическая запись — `report_map_scenario.py`.
"""

import csv
from pathlib import Path
import math

import pytest

import report_map_scenario as ms
import report_scenario as rs
from sno_eye import report
from sno_eye.report import archive as arc
from sno_eye.report import zones


def _limits():
    from sno_eye import record_check as rc
    return rc.thresholds()


@pytest.fixture(scope="module")
def mapped(tmp_path_factory):
    folder = tmp_path_factory.mktemp("bug64")
    path, scenario = ms.make(folder)
    record = arc.load(path)
    result = report.analyse(record, report.settings(), _limits())
    return path, scenario, result


def _fixation_at(result, t):
    """Фиксация, которая идёт в миг [t]."""
    for fix in result["fixations"]:
        if fix["start"] <= t <= fix["end"]:
            return fix
    raise AssertionError(f"нет фиксации в {t}")


def test_bug_64_gaze_on_category_label_is_that_category(mapped):
    """BUG-64: взгляд на подпись категории над группой звёзд — фиксация
    уверенно в этой категории карты, а не «карта без категории»."""
    _, scenario, result = mapped
    for press in scenario.presses[:2]:
        fix = _fixation_at(result, press["t"] - 200)
        assert fix["zone"] == "galaxy_map"
        assert fix.get("mark") is None          # не на звезде
        assert fix["category"] == press["category"], fix
        assert fix["category_sure"] is True, fix


def test_bug_64_presses_table_says_what_was_under_gaze(mapped):
    """BUG-64: на каждое нажатие по звезде — что было под взглядом за
    300–100 мс до него: нужная категория, звезда, расстояние до точки
    нажатия и с какого мига взгляд был в нужной категории."""
    _, scenario, result = mapped
    rows = [r for r in result["presses"] if r["kind"] == "galaxy.star"]
    assert [r["book"] for r in rows] == \
        [p["star"] for p in scenario.presses]
    for row, press in zip(rows, scenario.presses):
        assert row["target"] == press["category"]
        assert row["category"] == press["category"]
        assert row["in_target_soft"] is True
        assert row["in_target_strict"] is True
        # Взгляд пришёл в категорию, когда начался этот заход.
        lead = press["t"] - press["since"]
        assert row["lead_ms_soft"] == pytest.approx(lead, abs=120)
    first, second, third = rows
    # Первые два — «не глядя» на звезду: взгляд у подписи, в градусах
    # от звезды; третий — на самой звезде.
    assert first["distance_deg"] > 4 and second["distance_deg"] > 3
    assert first["star"] is None and second["star"] is None
    assert third["distance_deg"] < 1
    assert third["star"] == "G2"
    summary = result["press_summary"]
    assert summary["galaxy"]["presses"] == 3
    assert summary["galaxy"]["in_target_soft"] == 3
    assert summary["galaxy"]["in_target_strict"] == 3


def test_bug_64_map_visit_is_measured_by_category(mapped):
    """BUG-64: поход на карту меряется категориями, как на полке: путь,
    время до нужной категории, прямая находка; время до звезды открытой
    книги — отдельно."""
    _, scenario, result = mapped
    visits = [v for v in result["visits"] if v["screen"] == "galaxy"]
    assert len(visits) == 1
    visit = visits[0]
    assert visit["target"] == "Ангиология" and visit["outcome"] == "book"
    assert visit["path_soft"] == ["Ангиология", "Математика", "Ангиология"]
    assert visit["categories_soft"] == 2
    assert visit["direct_soft"] is True
    start = scenario.answer["galaxy_visit"]["start"]
    assert visit["first_target_ms_soft"] == pytest.approx(300, abs=120)
    # До звезды открытой книги (G2) — третий заход.
    third = scenario.presses[2]["since"] - start
    assert visit["first_star_ms_soft"] == pytest.approx(third, abs=120)
    summary = result["galaxy_summary"]
    assert summary["visits"] == 1 and summary["opened"] == 1
    assert summary["direct_share_soft"] == 1.0


def test_bug_64_label_follows_the_map_painter():
    """BUG-64: подпись группы — по правилу художника карты: над самой
    верхней видимой звездой, по середине видимых звёзд, у края окна
    прижата; подписи групп не ложатся друг на друга."""
    frame = {"t": 0, "viewport": {"w": rs.W, "h": rs.H},
             "regions": ms.galaxy_regions()}
    categories = {k: v[0] for k, v in ms.STARS.items()}
    groups = zones.map_groups(frame, categories, font_scale=1.0)
    by = {g["name"]: g for g in groups}
    for name in ("Ангиология", "Математика"):
        assert by[name]["label"] == pytest.approx(ms.label(name))
    # Группа у левого края: подпись прижата к отступу 6 точек.
    edge = dict(frame, regions=[dict(r) for r in frame["regions"]])
    edge["regions"][2] = dict(edge["regions"][2], marks=[
        {"id": "G1", "x": 10.0, "y": 300.0, "r": 8.0},
        {"id": "M1", "x": 900.0, "y": 300.0, "r": 8.0}])
    groups = zones.map_groups(edge, categories, font_scale=1.0)
    assert {g["name"]: g for g in groups}["Ангиология"]["label"][0] == 6.0
    # Две группы, чьи подписи легли бы друг на друга: вторая по имени
    # подписи не получает — как у `pickLabels`.
    crowd = dict(frame, regions=[dict(r) for r in frame["regions"]])
    crowd["regions"][2] = dict(crowd["regions"][2], marks=[
        {"id": "G1", "x": 400.0, "y": 300.0, "r": 8.0},
        {"id": "M1", "x": 420.0, "y": 302.0, "r": 8.0}])
    groups = {g["name"]: g for g in
              zones.map_groups(crowd, categories, font_scale=1.0)}
    assert groups["Ангиология"]["label"] is not None
    assert groups["Математика"]["label"] is None
    # Крупный шрифт устройства — подпись крупнее.
    big = zones.map_groups(frame, categories, font_scale=1.5)
    assert {g["name"]: g for g in big}["Ангиология"]["label"][3] == 30.0


def test_bug_64_between_groups_is_on_the_border():
    """BUG-64: взгляд между двумя группами ближе запаса — категория «на
    границе», и в соседях обе категории."""
    frame = {"t": 0, "viewport": {"w": 800, "h": 600}, "regions": [
        {"kind": "galaxy_map", "id": "", "rect": [0, 0, 800, 600], "z": 0,
         "marks": [{"id": "a", "x": 300, "y": 300, "r": 6},
                   {"id": "b", "x": 420, "y": 300, "r": 6}]}]}
    z = zones.Zones([frame], outside_px=80,
                    categories={"a": "А", "b": "Б"}, map_pad_px=40)
    far = z.classify(1, 290, 300, 20)
    assert far["category"] == "А" and far["category_sure"] is True
    middle = z.classify(1, 345, 300, 30)
    assert middle["category"] == "А"
    assert middle["category_sure"] is False
    assert set(middle["category_near"]) == {"Б"}
    # Вдали от всех групп — категории нет.
    empty = z.classify(1, 700, 100, 20)
    assert empty["category"] is None and empty["zone"] == "galaxy_map"


def test_bug_64_presses_on_shelf_books_too(tmp_path):
    """BUG-64: таблица нажатий берёт и книги полки — в синтетической
    записи ветви I оба открытия книги с полки лежат в ней со взглядом
    на нужной категории."""
    path = rs.make(tmp_path)
    result = report.analyse(arc.load(path), report.settings(), _limits())
    rows = [r for r in result["presses"] if r["screen"] == "shelf"]
    assert [r["book"] for r in rows] == ["F2", "A3"]
    assert [r["target"] for r in rows] == ["Физиология", "Анатомия"]
    assert all(r["in_target_soft"] for r in rows)
    assert all(r["distance_deg"] < 1.5 for r in rows)


def test_bug_64_files_console_and_page(mapped, tmp_path, capsys):
    """BUG-64: таблица нажатий — `presses.csv` и раздел страницы; на
    схеме карты — подписи категорий; в консоли — строка о карте."""
    path, _, _ = mapped
    code = report.main([str(path)], out=str(tmp_path))
    assert code == 0
    folder = tmp_path / (path.name[:-4] + "_eye")
    with open(folder / "presses.csv", encoding="utf-8-sig") as f:
        rows = list(csv.reader(f, delimiter=";"))
    assert len(rows) == 1 + 3
    page = (folder / "index.html").read_text(encoding="utf-8")
    assert "Перед нажатием" in page
    assert "Ангиология" in page and "Математика" in page
    out = capsys.readouterr().out
    assert "нажатий на карте 3" in out
    assert "нужная категория под взглядом 3 из 3" in out


def test_bug_64_without_gaze_presses_are_listed_empty(tmp_path):
    """BUG-64: без взгляда нажатия перечислены, а ячейки взгляда пусты,
    а не нули."""
    scenario = ms.MapScenario(study_ms=120_000).build()
    path = rs.make(tmp_path, scenario=scenario, gaze=False,
                   name="sno2026_II_80032040_d10708_20261010-0812.zip")
    result = report.analyse(arc.load(path), report.settings(), _limits())
    rows = [r for r in result["presses"] if r["kind"] == "galaxy.star"]
    assert len(rows) == 3
    for row in rows:
        assert row["target"] is not None
        assert row["category"] is None and row["distance_deg"] is None
        assert row["in_target_soft"] is None


def test_bug_64_press_without_face_is_empty_not_zero(mapped):
    """BUG-64: нажатие, перед которым годных кадров нет, — пустые
    ячейки взгляда."""
    path, scenario, _ = mapped
    record = arc.load(path)
    press = scenario.presses[0]["t"]
    record.gaze = [dict(r, ok=False, x=None, y=None)
                   if press - 400 <= r["t"] - rs.LATENCY <= press else r
                   for r in record.gaze]
    result = report.analyse(record, report.settings(), _limits())
    row = [r for r in result["presses"] if r["kind"] == "galaxy.star"][0]
    assert row["distance_deg"] is None and row["category"] is None
    assert row["in_target_soft"] is None
    assert math.isfinite(result["press_summary"]["galaxy"]["presses"])


def test_bug_64_real_frame_format_from_the_golden():
    """BUG-64: кадр карты в том виде, что пишет приложение (эталон
    `test/goldens/layout_frame.json`, раздел `screens`): группы и
    подписи встают внутри полотна, карточка книги поверх карты
    категорию закрывает, звезда — в своей категории."""
    import json
    golden = json.loads((Path(__file__).resolve().parents[2] / "test" /
                         "goldens" / "layout_frame.json")
                        .read_text(encoding="utf-8"))
    case = next(c for c in golden["screens"]
                if any(r["kind"] == "galaxy_map"
                       for r in c["frame"]["regions"]))
    frame = dict(case["frame"], t=0)
    region = next(r for r in frame["regions"] if r["kind"] == "galaxy_map")
    ids = [m["id"] for m in region["marks"]]
    categories = {ids[0]: "Анатомия", ids[1]: "Анатомия",
                  ids[2]: "Гистология", ids[3]: "Анатомия"}
    groups = zones.map_groups(frame, categories)
    left, top, w, h = region["rect"]
    for group in groups:
        x, y, lw, lh = group["label"]
        assert left <= x and x + lw <= left + w
        assert top <= y and y + lh <= top + h
    z = zones.Zones([frame], outside_px=80, categories=categories,
                    map_pad_px=40)
    star = region["marks"][1]
    assert z.classify(1, star["x"], star["y"], 10)["category"] == \
        "Анатомия"
    card = next(r for r in frame["regions"] if r["kind"] == "galaxy_card")
    cx = card["rect"][0] + card["rect"][2] / 2
    cy = card["rect"][1] + card["rect"][3] / 2
    under = z.classify(1, cx, cy, 10)
    assert under["zone"] == "galaxy_card" and under["category"] is None
