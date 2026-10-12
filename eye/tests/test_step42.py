"""Шаг 42 — рисунки Р1–Р14 по образцу журналов (SNO-F-RES-06,
SNO-ALG-RES-04): данные рисунков на придуманных числах.

Полоса Р9 — интервал 95 % взвешенного среднего, а не 25-й и 75-й
процентили; доли Р8 — у каждого участника и с интервалом; у матриц —
число участников в строке и разница «II − I» по общим зонам; прямая
научения ветви на Р12 — через середину ветви с наклоном из свода средних;
точка — ПК формой, искренность заливкой.
"""

from __future__ import annotations

import math

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("matplotlib")

from sno_eye import study  # noqa: E402
from sno_eye.report.zones import BUCKETS  # noqa: E402
from sno_eye.study import average, charts, disorder, honesty, stats  # noqa

FP = "отпечаток-шага-42"


def cfg(**kw):
    c = study.settings()
    c.update(kw)
    return c


def shares(**kw):
    out = {k: 0.0 for k, _ in BUCKETS}
    out.update(kw)
    return out


def entry(code, colour="green", branch="I", pc="pc1", **gaze):
    data = {"precision_deg": 0.5, "layout": True, "accuracy_deg": 1.2,
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
            "etalon": "да", "etalon_out": None, "stratum": pc,
            "gaze": {"present": True, "included": True},
            "gaze_data": data}


def minutes(values: list[float]) -> list[dict]:
    """Ряд минут участника: доля чтения по минутам, остальное — полка."""
    return [{"minute": i + 1, "reading": v, "shelf": 1 - v}
            for i, v in enumerate(values)]


# --- Р9: полоса — интервал среднего --------------------------------------

def test_sno_alg_res_04_minute_band_is_interval_of_the_mean():
    """Полоса — бутстреп среднего участников этой минуты: тот же расчёт,
    что `stats.mean_interval` с зерном от отпечатка набора, — а не
    процентили людей."""
    values = [i / 11 for i in range(12)]
    people = [entry(f"p{i}", minutes=minutes([v, v]))
              for i, v in enumerate(values)]
    c = cfg(minute_bootstrap=3000)
    out = average.build(people, c, False, None, FP)
    row = out["minutes"]["I"]["reading"][0]
    minute, mean, lo, hi, n = row
    assert (minute, n) == (1, 12)
    assert mean == pytest.approx(0.5)
    want = stats.mean_interval(values, [1.0] * 12,
                               stats.seed_for(FP, "minutes", "I", "reading",
                                              1), 3000)
    assert (lo, hi) == pytest.approx(want)
    # Интервал среднего уже разброса людей — 25-го и 75-го процентилей.
    q1 = average.wquantile(values, [1.0] * 12, 0.25)
    q3 = average.wquantile(values, [1.0] * 12, 0.75)
    assert q1 < lo < mean < hi < q3
    # Ряды участников — для тонких линий.
    people_rows = out["minutes"]["I"]["people"]
    assert [p["code"] for p in people_rows] == [f"p{i}" for i in range(12)]
    assert people_rows[1]["series"]["reading"] == [(1, 1 / 11), (2, 1 / 11)]


def test_sno_alg_res_04_minute_band_same_set_same_numbers():
    people = [entry(f"p{i}", minutes=minutes([i / 10, 0.5]))
              for i in range(4)]
    a = average.build(people, cfg(), False, None, FP)["minutes"]
    b = average.build(people, cfg(), False, None, FP)["minutes"]
    other = average.build(people, cfg(), False, None, "другой")["minutes"]
    assert a["I"]["reading"] == b["I"]["reading"]
    assert a["I"]["reading"][0][2:4] != other["I"]["reading"][0][2:4]


def test_sno_alg_res_04_minute_with_one_value_has_flat_band():
    people = [entry(f"p{i}", minutes=minutes([0.4])) for i in range(3)]
    row = average.build(people, cfg(), False, None, FP)["minutes"]["I"][
        "reading"][0]
    assert row[1:4] == pytest.approx((0.4, 0.4, 0.4))


def test_sno_alg_res_04_minute_below_min_participants_is_not_drawn():
    people = [entry(f"p{i}", minutes=minutes([0.4] * (i + 1)))
              for i in range(3)]
    rows = average.build(people, cfg(min_minute_participants=3), False,
                         None, FP)["minutes"]["I"]["reading"]
    assert [r[0] for r in rows] == [1]


# --- Р8: доли участников ----------------------------------------------------

def test_sno_alg_res_04_shares_of_each_participant_and_interval():
    a = entry("a", shares=shares(page=0.8, no_frames=0.2))
    b = entry("b", colour="yellow", pc="pc2",
              shares=shares(page=0.2, shelf=0.8))
    c = entry("c", shares=shares(page=0.5, shelf=0.5))
    r = entry("r", colour="red", shares=shares(galaxy=1.0))
    own = average.build([a, b, c, r], cfg(), False, None, FP)["shares"]["I"]
    people = own["people"]
    assert [p["code"] for p in people] == ["a", "b", "c"]     # 🔴 вне
    for p in people:
        assert sum(p["groups"].values()) == pytest.approx(1.0)
    assert people[1]["pc"] == "pc2"
    assert people[1]["colour"] == "yellow" and people[1]["w"] == 0.5
    ci = own["ci"]["reading"]
    want = stats.mean_interval([0.8, 0.2, 0.5], [1.0, 0.5, 1.0],
                               stats.seed_for(FP, "shares", "I", "reading"),
                               int(cfg()["minute_bootstrap"]))
    assert ci == pytest.approx(want)
    assert ci[0] <= own["groups"]["reading"] <= ci[1]


# --- Р7: строки и разница -------------------------------------------------

def _trans(pairs):
    return {p: {"transitions": pairs if p == disorder.ALL else []}
            for p in disorder.PHASES}


def test_sno_alg_res_04_matrix_counts_participants_in_each_row():
    a = entry("a", disorder={"phases": _trans([[0, 1], [1, 0], [0, 1]]),
                             "trips": [], "nni": {}}, disorder_live=True)
    b = entry("b", disorder={"phases": _trans([[0, 2]]), "trips": [],
                             "nni": {}})
    a["disorder_live"] = b["disorder_live"] = True
    m = average.build([a, b], cfg(), False, None, FP)["matrix"]["I"]
    assert m["n"] == 2
    assert m["row_n"][:3] == [2, 1, 0]


def test_sno_alg_res_04_matrix_difference_by_common_zones():
    first = {"zones": ["А", "Б"], "p": [[0.5, 0.5], [1.0, 0.0]],
             "row_n": [4, 2]}
    second = {"zones": ["А", "В", "Б"],
              "p": [[0.2, 0.3, 0.5], [0.1, 0.9, 0.0],
                    [0.6, 0.0, 0.4]], "row_n": [5, 3, 4]}
    d = average.matrix_difference(first, second, 3)
    assert d["zones"] == ["А", "Б", "В"]
    assert d["n_first"] == [4, 2, 0]
    assert d["n_second"] == [5, 4, 3]
    # Строка «А»: столбец «В» у ветви I — 0 (переходов в неё не было).
    assert d["d"][0] == pytest.approx([0.2 - 0.5, 0.5 - 0.5, 0.3 - 0.0])
    # «Б» у ветви I — двое, «В» — никого: разницы нет.
    assert d["d"][1] == [None, None, None]
    assert d["d"][2] == [None, None, None]


def test_sno_alg_res_04_matrix_difference_empty_and_nan_cells():
    nan = float("nan")
    first = {"zones": ["А"], "p": [[nan]], "row_n": [3]}
    second = {"zones": ["А"], "p": [[1.0]], "row_n": [3]}
    assert average.matrix_difference(first, second, 3)["d"] == [[None]]
    empty = average.matrix_difference({}, {}, 3)
    assert empty["zones"] == [] and empty["d"] == []


# --- Р12: прямая ветви ----------------------------------------------------

def test_sno_alg_res_04_fit_of_a_power_law():
    values = [(n, 30.0 * n ** -0.4) for n in range(1, 9)]
    a, b, xm = average.fit(values, 6)
    assert b == pytest.approx(-0.4)
    assert a == pytest.approx(math.log(30.0))
    # BUG-75 (шаг 43): первый поход в прямую не идёт.
    assert xm == pytest.approx(np.mean(np.log(range(2, 9))))
    assert average.slope(values, 6) == pytest.approx(b)
    assert average.fit(values[:5], 6) is None
    assert average.dropped([(1, 0.0), (2, 3.0), (3, None), (4, -1)]) == 2


def test_sno_alg_res_04_branch_centre_and_participant_lines():
    trips = {"x": [30.0 * n ** -0.5 for n in range(1, 8)],
             "y": [20.0 * n ** -0.1 for n in range(1, 9)] + [0.0]}
    people = []
    for code, ys in trips.items():
        e = entry(code)
        e["trips"] = [{"complete": True, "time_to_choice_s": y}
                      for y in ys]
        people.append(e)
    people.append(entry("мало"))
    people[-1]["trips"] = [{"complete": True, "time_to_choice_s": 5.0}]
    lines = average.build(people, cfg(min_visits_curve=6), False, None,
                          FP)["curve"]["I"]["lines"]["choice"]
    assert lines["fitted"] == 2 and lines["dropped"] == 1
    assert [p["code"] for p in lines["people"]] == ["x", "y", "мало"]
    assert lines["people"][2]["fit"] is None
    assert all(y > 0 for p in lines["people"] for _, y in p["points"])
    # BUG-75 (шаг 43): середина участника — без первого похода.
    xs = [np.mean(np.log(range(2, 8))), np.mean(np.log(range(2, 9)))]
    ys = [math.log(30) - 0.5 * xs[0], math.log(20) - 0.1 * xs[1]]
    assert lines["centre"] == pytest.approx((np.mean(xs), np.mean(ys)))


def test_sno_alg_res_04_branch_line_goes_through_centre_with_band():
    lines = {"centre": (math.log(3.0), math.log(10.0)), "fitted": 4}
    line = charts.branch_line(lines, {"mean": -0.5, "ci": (-0.7, -0.3)},
                              9.0, 3)
    n = np.asarray(line["n"])
    y = np.asarray(line["y"])
    assert n[0] == pytest.approx(1.0) and n[-1] == pytest.approx(9.0)
    # Через середину: при n = 3 — 10, наклон в логарифмах — −0,5.
    assert np.interp(math.log(3.0), np.log(n), np.log(y)) == \
        pytest.approx(math.log(10.0), abs=1e-3)
    assert y[0] == pytest.approx(10.0 * 3.0 ** 0.5)
    lo, hi = np.asarray(line["lo"]), np.asarray(line["hi"])
    assert np.all(lo <= y + 1e-12) and np.all(y <= hi + 1e-12)
    # Полоса сужается к середине.
    k = int(np.argmin(np.abs(np.log(n) - math.log(3.0))))
    assert (hi - lo)[k] < (hi - lo)[0] and (hi - lo)[k] < (hi - lo)[-1]


def test_sno_alg_res_04_no_branch_line_for_few_participants():
    lines = {"centre": (0.5, 1.0), "fitted": 2}
    assert charts.branch_line(lines, {"mean": -0.3, "ci": None}, 8, 3) \
        is None
    lines["fitted"] = 3
    line = charts.branch_line(lines, {"mean": -0.3, "ci": None}, 8, 3)
    assert line["lo"] is None and line["b"] == -0.3
    assert charts.branch_line(lines, {"mean": None}, 8, 3) is None
    assert charts.branch_line({"centre": None, "fitted": 5},
                              {"mean": -0.3}, 8, 3) is None


# --- точка участника --------------------------------------------------------

def test_sno_f_res_06_point_shape_is_pc_and_fill_is_honesty():
    markers = {"ПК-1": "o", "ПК-2": "s"}
    green = charts._point(honesty.GREEN, "#2a78d6", "ПК-2", markers)
    yellow = charts._point(honesty.YELLOW, "#2a78d6", "ПК-2", markers)
    red = charts._point(honesty.RED, "#2a78d6", "ПК-2", markers)
    assert green["marker"] == "s" and green["color"] == "#2a78d6"
    assert yellow["marker"] == "s" and yellow["facecolors"] == \
        charts.SURFACE
    assert red["marker"] == "x"
    assert charts._point(honesty.GREEN, "#000", "чужой", markers)[
        "marker"] == "o"
    labels = [h.get_label() for h in charts._pc_handles(markers)]
    assert labels == ["ПК ПК-1", "ПК ПК-2"]


def test_sno_f_res_06_n_range_words():
    assert charts._n_range([]) == "0"
    assert charts._n_range([5, 5]) == "5"
    assert charts._n_range([7, 5, 6]) == "5–7"


def test_sno_alg_res_04_heat_keeps_sigma_in_degrees():
    pts = [{"book": "a", "x": 0.0, "y": 0.0}, {"book": "b", "x": 1.0,
                                                "y": 1.0}]
    e1 = entry("a", branch="II", accuracy_deg=1.5,
               map={"key": "k", "points": pts},
               map_fix=[[0.5, 0.5, 300.0, 0.1]])
    e2 = entry("b", branch="II", accuracy_deg=0.9,
               map={"key": "k", "points": pts},
               map_fix=[[0.2, 0.2, 200.0, 0.1]])
    heat = average.build([e1, e2], cfg(), False, None, FP)["heat"]
    assert heat[0]["sigma_deg"] == [0.9, 1.5]


# --- по независимой проверке шага 42 ---------------------------------------

def test_sno_alg_res_04_fit_needs_minimum_points_and_two_numbers():
    # BUG-75 (шаг 43): [minimum] — без первого похода.
    values = [(n, 10.0 / n) for n in range(1, 8)]
    assert average.fit(values, 6) is not None        # ровно [minimum]
    assert average.fit(values[:6], 6) is None
    # Один номер похода — наклона нет, сколько бы точек ни было.
    assert average.fit([(3, float(k + 1)) for k in range(12)], 6) is None
    assert average.fit([(0, 1.0), (-1, 2.0)] + values[:4], 6) is None


def test_sno_alg_res_04_branch_centre_is_weighted():
    def person(code, colour, a, b):
        e = entry(code, colour=colour)
        e["trips"] = [{"complete": True,
                       "time_to_choice_s": math.exp(a) * n ** b}
                      for n in range(1, 8)]
        return e
    x = person("x", "green", math.log(30.0), -0.5)
    y = person("y", "yellow", math.log(10.0), -0.1)
    lines = average.build([x, y], cfg(min_visits_curve=6), False, None,
                          FP)["curve"]["I"]["lines"]["choice"]
    # BUG-75 (шаг 43): середина — без первого похода.
    xm = float(np.mean(np.log(range(2, 8))))
    ya = math.log(30.0) - 0.5 * xm
    yb = math.log(10.0) - 0.1 * xm
    # 🟡 весит 0,5.
    assert lines["centre"] == pytest.approx((xm, (ya + 0.5 * yb) / 1.5))


def test_sno_alg_res_04_matrix_difference_row_at_the_threshold_counts():
    first = {"zones": ["А"], "p": [[1.0]], "row_n": [3]}
    second = {"zones": ["А"], "p": [[0.25]], "row_n": [3]}
    assert average.matrix_difference(first, second, 3)["d"] == [[-0.75]]
    # Порог ноль строку без людей не открывает.
    first["row_n"], second["zones"] = [0], ["Б"]
    second["p"], second["row_n"] = [[1.0]], [0]
    assert average.matrix_difference(first, second, 0)["d"] == \
        [[None, None], [None, None]]


def test_sno_alg_res_04_category_matrix_counts_rows():
    # Из «А» переходили оба, из «Б» — никто; по столбцам вышло бы [1, 1].
    a = entry("a", category_pairs=[("А", "А")])
    b = entry("b", category_pairs=[("А", "Б"), ("А", "Б")])
    m = average.build([a, b], cfg(), False, None, FP)["categories"]["I"]
    assert m["zones"] == ["А", "Б"]
    assert m["row_n"] == [2, 0]


def _weighted_people(branch="I"):
    colours = ["green", "yellow"] * 6
    return [entry(f"{branch}{i}", colour=colours[i], branch=branch,
                  minutes=minutes([i / 11]),
                  shares=shares(page=i / 11, shelf=1 - i / 11))
            for i in range(12)]


def test_sno_alg_res_04_intervals_use_weights_and_branch_seed():
    people = _weighted_people("I") + _weighted_people("II")
    reps = int(cfg()["minute_bootstrap"])
    out = average.build(people, cfg(), False, None, FP)
    xs = [i / 11 for i in range(12)]
    ws = [1.0, 0.5] * 6
    for b in ("I", "II"):
        row = out["minutes"][b]["reading"][0]
        want = stats.mean_interval(xs, ws, stats.seed_for(
            FP, "minutes", b, "reading", 1), reps)
        assert row[2:4] == pytest.approx(want)
        ci = out["shares"][b]["ci"]["reading"]
        want = stats.mean_interval(xs, ws, stats.seed_for(
            FP, "shares", b, "reading"), reps)
        assert ci == pytest.approx(want)
    # Свое зерно у каждой ветви: на тех же числах интервалы разные.
    assert out["shares"]["I"]["ci"]["reading"] != \
        out["shares"]["II"]["ci"]["reading"]
    assert out["minutes"]["I"]["reading"][0][2:4] != \
        out["minutes"]["II"]["reading"][0][2:4]


def test_sno_alg_res_04_branch_line_for_one_trip_is_still_a_line():
    line = charts.branch_line({"centre": (0.0, 1.0), "fitted": 3},
                              {"mean": -0.2, "ci": (-0.3, -0.1)}, 1, 3)
    n = np.asarray(line["n"])
    assert n[-1] == pytest.approx(2.0) and np.all(np.isfinite(line["y"]))
    assert len(set(np.round(n, 9))) == 60
