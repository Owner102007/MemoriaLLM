"""Шаг 37, SNO-ALG-RES-04: средний взгляд ветви на придуманных числах —
взвешенные доли, матрица переходов без строки у участника, перевод в
координаты карты, схема полки при разных наборах категорий, наклон
научения.
"""

from __future__ import annotations

import math

import pytest

np = pytest.importorskip("numpy")

from sno_eye import study  # noqa: E402
from sno_eye.report.zones import BUCKETS  # noqa: E402
from sno_eye.study import average, disorder  # noqa: E402


def cfg(**kw):
    c = study.settings()
    c.update(kw)
    return c


def shares(**kw):
    out = {k: 0.0 for k, _ in BUCKETS}
    out.update(kw)
    return out


def entry(code, colour="green", branch="I", **gaze):
    data = {"precision_deg": 0.5, "layout": True,
            "shares": shares(page=0.6, shelf=0.1, no_frames=0.3),
            "minutes": [], "category_pairs": [], "map_fix": [],
            "shelf_time": {"book": {}, "header": {}, "total_ms": 0.0},
            "map": None,
            "disorder": {"phases": {p: {"transitions": []}
                                    for p in disorder.PHASES},
                         "trips": [], "nni": {}}}
    data.update(gaze)
    return {"status": "ok", "participant": code, "branch": branch,
            "colour": colour, "series": "sno2026-2", "study_s": 2400,
            "etalon": "да", "etalon_out": None, "stratum": "pc",
            "gaze": {"present": True, "included": True},
            "gaze_data": data}


def test_sno_alg_res_04_weighted_shares_sum_to_one_and_red_is_out():
    a = entry("a", shares=shares(page=0.8, no_frames=0.2))
    b = entry("b", colour="yellow", shares=shares(page=0.2, shelf=0.8))
    r = entry("r", colour="red", shares=shares(galaxy=1.0))
    out = average.build([a, b, r], cfg(), False, None)
    groups = out["shares"]["I"]["groups"]
    assert out["n_gaze"]["I"] == 2
    assert sum(groups.values()) == pytest.approx(1.0)
    # 🟡 весит 0,5: (0,8 · 1 + 0,2 · 0,5) / 1,5.
    assert groups["reading"] == pytest.approx(0.9 / 1.5)
    assert groups["galaxy"] == 0.0          # 🔴 не влияет


def test_sno_alg_res_04_matrix_when_a_row_is_missing():
    """Счётчики участника нормируются к сумме 1 и только потом
    складываются: участник без строки «карта» не размывает её."""
    reading, shelf, galaxy = 0, 1, 2
    a = entry("a")
    a["gaze_data"]["disorder"]["phases"]["all"]["transitions"] = \
        [(reading, shelf), (shelf, reading)] * 10
    b = entry("b")
    b["gaze_data"]["disorder"]["phases"]["all"]["transitions"] = \
        [(galaxy, reading), (reading, galaxy)]
    m = average._matrix([(a, 1.0), (b, 1.0)])
    p = np.array(m["p"])
    assert m["n"] == 2
    # Строка «карта» — только у «b», и она целиком в «чтение».
    assert p[galaxy, reading] == pytest.approx(1.0)
    # «Чтение» — у обоих: у «a» в полку, у «b» в карту; веса участников
    # равны, хотя переходов у «a» в десять раз больше.
    assert p[reading, shelf] == pytest.approx(0.5)
    assert p[reading, galaxy] == pytest.approx(0.5)
    assert all(math.isnan(v) for v in p[3])     # строки никто не дал


def test_sno_alg_res_04_map_point_does_not_depend_on_the_camera():
    def frame(scale_unit, cx, cy):
        return {"regions": [{"kind": "galaxy_map", "rect": [0, 56, 1280,
                                                           744],
                             "info": {"map": {"cx": cx, "cy": cy,
                                              "unit": scale_unit}}}]}
    near = frame(250.0, 0.0, 0.0)
    zoomed = frame(1000.0, -1.0, 0.3)
    point = ("map", -1.2, 0.4)
    for f in (near, zoomed):
        x, y = disorder.on_screen(f, point)
        back = disorder.content(f, x, y)
        assert back[0] == "map"
        assert back[1] == pytest.approx(-1.2)
        assert back[2] == pytest.approx(0.4)


def test_sno_alg_res_04_shelf_schema_over_different_category_sets():
    a = entry("a", shelf_time={"book": {"x1": 300.0, "y1": 100.0},
                               "header": {"X": 100.0}, "total_ms": 1000.0})
    a["shelf_layout"] = {"categories": [("X", 0), ("Y", 1)],
                         "books": [("x1", "X1", "X", 0),
                                   ("y1", "Y1", "Y", 0)]}
    b = entry("b", shelf_time={"book": {"x1": 100.0},
                               "header": {}, "total_ms": 1000.0})
    b["shelf_layout"] = {"categories": [("X", 0)],
                         "books": [("x1", "X1", "X", 0)]}
    out = average._shelf([(a, 1.0), (b, 1.0)])
    rows = {r["category"]: r for r in out["rows"]}
    assert list(rows) == ["X", "Y"]
    assert rows["X"]["books"][0]["share"] == pytest.approx(0.2)
    assert rows["X"]["header"] == pytest.approx(0.05)
    # Категории «Y» у «b» не было — у него пусто, а не ноль.
    assert rows["Y"]["books"][0]["share"] == pytest.approx(0.1)


def test_sno_alg_res_04_learning_slope():
    series = [(n, 12.0 * n ** -0.4) for n in range(1, 11)]
    assert average.slope(series, 6) == pytest.approx(-0.4)
    assert average.slope(series[:5], 6) is None
    # Нуль в логарифм не идёт.
    assert average.slope(series + [(11, 0.0)], 6) == pytest.approx(-0.4)


def test_sno_alg_res_04_learning_goes_into_measures():
    a = entry("a")
    a["trips"] = [{"complete": True, "time_to_choice_s": 10 * n ** -0.5,
                   "first_time": True} for n in range(1, 9)]
    a["disorder_live"] = True
    a["gaze_data"]["disorder"]["trips"] = [
        {"i": n, "path_deg": 40.0 * n ** -0.3} for n in range(1, 9)]
    phone = entry("p")
    phone["trips"] = a["trips"][:5]
    average.learning([a, phone], cfg())
    assert a["learn"]["learn.choice_slope"] == pytest.approx(-0.5)
    assert a["learn"]["learn.path_slope"] == pytest.approx(-0.3)
    assert phone["learn"]["learn.choice_slope"] is None   # меньше шести
    assert "learn.path_slope" not in phone["learn"]


def test_sno_alg_res_04_weighted_quantile():
    # Медиана — как у `stats.weighted_median`: при весе ровно в
    # половину — середина между соседями (независимая проверка шага).
    assert average.wquantile([1, 2, 3, 4], [1, 1, 1, 1], 0.5) == 2.5
    assert average.wquantile([1, 2, 3, 4], [1, 1, 1, 5], 0.5) == 4
    assert average.wquantile([1, 2, 3, 4], [1, 1, 1, 1], 0.25) == 1
    assert average.wquantile([1, 2, 3, 4], [1, 1, 1, 1], 0.75) == 3
    assert average.wquantile([], [], 0.5) is None


def test_sno_alg_res_04_minutes_need_three_participants():
    rows = [{"minute": 1, "reading": 0.5, "shelf": 0.5, "galaxy": 0.0,
             "off": 0.0, "other": 0.0}]
    part = [(entry(c, minutes=rows), 1.0) for c in "ab"]
    assert average._minutes(part, 3)["reading"] == []
    part.append((entry("c", minutes=rows), 1.0))
    got = average._minutes(part, 3)["reading"]
    assert got == [(1, 0.5, 0.5, 0.5, 3)]
