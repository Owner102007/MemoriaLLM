"""Шаг 37, SNO-ALG-RES-03, -04: разбор взгляда одной записи для
сравнения (`study.gaze`) — на синтетических записях шага 34 с
известным ответом: «Разбор записи» без изменений, фиксации общим
порогом, схема полки, фиксации на карте в координатах карты.
"""

from __future__ import annotations

import pytest

pytest.importorskip("numpy")

import report_map_scenario as rms  # noqa: E402
import report_scenario as rs  # noqa: E402
from sno_eye import record_check as rc  # noqa: E402
from sno_eye import report, study  # noqa: E402
from sno_eye.report import archive as arc  # noqa: E402
from sno_eye.report import timeline as tl  # noqa: E402
from sno_eye.study import actions, collect, gaze  # noqa: E402


def read(path):
    limits = rc.thresholds()
    record = arc.load(path, limits)
    line = tl.build(record)
    trips = actions.trips(record, line)
    return record, trips, gaze.read(record, trips, study.settings(),
                                    report.settings(), limits, "a" * 64)


def test_sno_alg_res_04_gaze_of_a_shelf_recording(tmp_path):
    path = rs.make(tmp_path)
    record, trips, data = read(path)
    assert data["version"] == report.settings()["version"]
    assert sum(data["shares"].values()) == pytest.approx(1.0)
    assert data["precision_deg"] == 0.3
    # «Разбор записи» без изменений: доли — те же, что в его итоге.
    same = report.analyse(record, report.settings(), rc.thresholds())
    assert data["shares"] == same["shares"]["soft"]
    # Поход 1: взгляд на «A2», край «A1», между книгами «Физиологии» и на
    # «F2» — время поиска на книгах полки.
    books = data["shelf_time"]["book"]
    assert books.get("A2", 0) > 0 and books.get("F2", 0) > 0
    assert data["shelf_time"]["total_ms"] >= sum(books.values())
    phases = data["disorder"]["phases"]
    assert phases["reading"]["fixations"] > 100
    assert phases["search"]["fixations"] >= 4
    assert data["disorder"]["idt_deg"] == 4.5
    assert data["map"] is None and data["map_fix"] == []


def test_sno_alg_res_04_gaze_on_the_map_in_map_coordinates(tmp_path):
    path, scenario = rms.make(tmp_path)
    _, trips, data = read(path)
    assert trips[0].via == "galaxy"
    assert data["map_fix"]
    # Камера кадра: единица карты — 600 точек, середина — (0,5; 0,5).
    for mx, my, ms, radius in data["map_fix"]:
        x = 1280 / 2 + (mx - 0.5) * 600
        y = rms.TOP + (800 - rms.TOP) / 2 + (my - 0.5) * 600
        assert 0 <= x <= 1280 and rms.TOP <= y <= 800
        assert ms > 0 and radius > 0
    # Переходы между категориями карты — подписи «Ангиологии» и
    # «Математики».
    names = {n for pair in data["category_pairs"] for n in pair}
    assert {"Ангиология", "Математика"} <= names


def test_sno_alg_res_04_collect_keeps_test_when_gaze_fails(tmp_path,
                                                           monkeypatch):
    path = rs.make(tmp_path)
    cfg = study.settings()
    entry = collect.load(path, rc.thresholds(), cfg, report.settings())
    assert entry["status"] == "ok" and entry["gaze_data"]
    assert entry["shelf_layout"]["books"]
    plain = collect.load(path, rc.thresholds(), cfg)
    assert "gaze_data" not in plain

    def broken(*a, **k):
        raise RuntimeError("сломано")

    monkeypatch.setattr(gaze, "read", broken)
    entry = collect.load(path, rc.thresholds(), cfg, report.settings())
    assert entry["status"] == "ok"
    assert entry["gaze_data"] is None
    assert "разбор взгляда упал" in entry["gaze"]["reason"]
    assert entry["actions"]                       # действия на месте


def test_sno_alg_res_04_map_of_galaxy_open():
    events = [{"t": 1, "type": "galaxy.open", "data": {"points": [
        {"book": "b", "x": 0.5, "y": -0.2, "r": 8, "group": "Б"},
        {"book": "a", "x": -0.5, "y": 0.1, "r": 8, "group": "А"}]}}]
    one = gaze.map_of(events)
    other = gaze.map_of([{"t": 1, "type": "galaxy.open", "data": {
        "points": list(reversed(events[0]["data"]["points"]))}}])
    assert one["key"] == other["key"] and len(one["points"]) == 2
    assert gaze.map_of([]) is None
