"""Шаг 38, SNO-ALG-RES-06 и SNO-F-RES-07: энтропия по ходу сессии —
окна, нормировка на случайный уровень и на перемешанный ряд, наклон
Тейла — Сена, ряды поиска без пары на стыке походов, окно через паузу;
кривые ветвей и перестановочный тест кластеров (Р16).

Вторая реализация энтропии окна и наклона Тейла — Сена — здесь же, на
чистом Python, без numpy.
"""

from __future__ import annotations

import math
import random
import statistics
from collections import Counter

import pytest

np = pytest.importorskip("numpy")

from sno_eye import study  # noqa: E402
from sno_eye.study import disorder, portrait, stats  # noqa: E402

N = 13  # сетка 4 × 3 и «вне экрана»


def cfg(**kw):
    c = study.settings()
    c.update(kw)
    return c


def h_t_plain(pairs, n):
    """H_t по формуле Krejtz — вторая реализация, без numpy."""
    rows = Counter(a for a, _ in pairs)
    cells = Counter(pairs)
    total = len(pairs)
    out = 0.0
    for (a, b), c in cells.items():
        pi = rows[a] / total
        p = c / rows[a]
        out -= pi * p * math.log2(p)
    return out


def trans_of(cells, t0=0.0, step=300.0, group="reading"):
    """Переходы ряда из последовательности клеток: каждая фиксация —
    [step] мс."""
    out = []
    for i, (a, b) in enumerate(zip(cells, cells[1:])):
        t = t0 + i * step
        out.append((a, b, t, t + 2 * step, group, group))
    return out


def wins(trans, size=60, step=15, axis=lambda t: t / 60_000, repeats=50,
         seed=1, max_ms=180_000):
    level = portrait.random_level(N, size, 200)
    return portrait.windows(trans, N, size, step, axis, repeats, level,
                            max_ms, seed)


# --- окно -------------------------------------------------------------------

def test_sno_alg_res_06_entropy_batch_is_the_disorder_formula():
    rng = np.random.default_rng(5)
    src = rng.integers(0, N, (7, 60))
    dst = rng.integers(0, N, (7, 60))
    batch = portrait.entropy_batch(src, dst, N)
    for r in range(7):
        pairs = np.column_stack([src[r], dst[r]])
        assert batch[r] == pytest.approx(disorder._entropies(pairs, N)[0])
        assert batch[r] == pytest.approx(
            h_t_plain(list(zip(src[r].tolist(), dst[r].tolist())), N))


@pytest.mark.parametrize("size", [40, 60, 100])
def test_sno_alg_res_06_random_gaze_is_about_one_at_any_window(size):
    """На случайном ряде нормированная H_t окон — около 1 при любом
    размере окна от 40 переходов."""
    rng = random.Random(size)
    cells = [rng.randrange(N) for _ in range(3000)]
    out = wins(trans_of(cells), size=size, step=size)
    assert out
    mean = statistics.mean(w["h"] for w in out)
    assert mean == pytest.approx(1.0, abs=0.05)


def test_sno_alg_res_06_uneven_random_gaze_is_about_one_by_order():
    """Неравномерный случайный взгляд по 4–6 клеткам из 13: делённая
    на перемешанный ряд H_t — около 1, порядка в нём нет. (Делённая на
    случайный уровень при малом окне бывает и около 1, и выше — у
    случайного взгляда по немногим клеткам недобор оценки меньше,
    SNO-ALG-RES-03.)"""
    rng = random.Random(9)
    cells = [rng.choice([0, 1, 2, 5, 5, 6]) for _ in range(1500)]
    out = wins(trans_of(cells), repeats=200)
    assert statistics.mean(w["h_order"] for w in out) == pytest.approx(
        1.0, abs=0.05)


def test_sno_alg_res_06_ordered_gaze_is_low_by_order():
    cells = [i % 4 for i in range(600)]
    out = wins(trans_of(cells))
    assert all(w["h"] < 0.05 for w in out)
    assert all(w["h_order"] < 0.05 for w in out)


def test_sno_alg_res_06_window_has_its_time_and_group():
    cells = [i % 13 for i in range(200)]
    trans = trans_of(cells[:100], group="shelf") + \
        trans_of(cells[100:], t0=100 * 300, group="reading")
    out = wins(trans, size=60, step=15)
    assert out[0]["from"] == 0 and out[0]["to"] == 60
    assert out[0]["t0"] == 0 and out[0]["t1"] == 59 * 300 + 600
    assert out[0]["mid"] == (out[0]["t0"] + out[0]["t1"]) / 2
    assert out[0]["group"] == "shelf"
    assert out[-1]["group"] == "reading"


def test_sno_alg_res_06_window_through_a_pause_is_marked():
    """Окно, растянутое дольше `window_max_s` (отлучка), помечено и
    линией с соседями не соединяется."""
    cells = [i % 13 for i in range(300)]
    trans = trans_of(cells[:150]) + trans_of(cells[150:], t0=10 * 60_000)
    out = wins(trans, size=60, step=15)
    long = [w for w in out if w["long"]]
    assert long
    assert all(w["from"] < 149 < w["to"] for w in long)
    assert not any(w["long"] for w in out if w["to"] <= 149)


# --- наклон ------------------------------------------------------------------

def theil_sen_plain(points, size, scale=1.0):
    """Тейл — Сен — вторая реализация: все пары без общих переходов."""
    slopes = []
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            (xa, ya, fa), (xb, yb, fb) = points[i], points[j]
            if fb - fa >= size and xb != xa:
                slopes.append((yb - ya) / (xb - xa))
    return statistics.median(slopes) * scale


def test_sno_alg_res_06_slope_down_when_one_transition_grows():
    """От окна к окну растёт доля одного перехода — наклон
    отрицательный; ряд постоянный — около нуля."""
    rng = random.Random(3)
    cells = []
    for k in range(12):
        share = k / 12
        for _ in range(60):
            cells.append(0 if rng.random() < share else rng.randrange(N))
    out = wins(trans_of(cells, step=1000), size=60, step=15)
    slope = portrait.theil_sen(out)
    assert slope < 0
    plain = theil_sen_plain([(w["x"], w["h"], w["from"]) for w in out], 60)
    assert slope == pytest.approx(plain)
    flat = [rng.randrange(N) for _ in range(720)]
    out = wins(trans_of(flat, step=1000), size=60, step=15)
    assert abs(portrait.theil_sen(out)) < abs(slope) / 4


def test_sno_alg_res_06_slope_needs_three_separate_windows():
    rng = random.Random(4)
    cells = [rng.randrange(N) for _ in range(111)]   # 110 переходов
    out = wins(trans_of(cells), size=40, step=10)
    assert portrait.non_overlapping(out) == 2
    assert portrait.theil_sen(out) is None
    cells = [rng.randrange(N) for _ in range(121)]   # 120 переходов
    out = wins(trans_of(cells), size=40, step=10)
    assert portrait.non_overlapping(out) == 3
    assert portrait.theil_sen(out) is not None


def test_sno_alg_res_06_reading_slope_is_per_ten_minutes():
    out = [{"h": 0.5 + 0.01 * k, "x": float(k), "from": 60 * k,
            "to": 60 * (k + 1)} for k in range(5)]
    assert portrait.theil_sen(out, 10.0) == pytest.approx(0.1)


# --- ряды переходов ----------------------------------------------------------

def fix(t, cell, trip=None, end=None, moving=False):
    phases = {disorder.ALL: True}
    if trip is not None:
        phases[disorder.SEARCH] = trip
    return {"t": t, "end": end or t + 200, "cell": cell, "group": "shelf",
            "moving": moving, "phases": phases}


def test_sno_alg_res_06_search_series_has_no_pair_across_trips():
    """Ряд поиска склеен из походов, но пары на стыке нет."""
    fixes = [fix(i * 250, f"c0{i % 4}", trip=0) for i in range(5)] + \
        [fix(1500 + i * 250, f"c1{i % 4}", trip=1) for i in range(4)]
    index = {z: i for i, z in enumerate(disorder.search_zones((4, 3)))}
    trans = portrait.series(fixes, portrait.SEARCH, [], 1000, index)
    # Пять фиксаций первого похода — 4 перехода, четыре второго — 3;
    # пары «последняя первого — первая второго» нет.
    assert len(trans) == 4 + 3
    assert (trans[3][3], trans[4][2]) == (1200, 1500)
    # Сессия — тот же ряд без разрыва по походам.
    whole = portrait.series(fixes, portrait.SESSION, [], 1000, index)
    assert len(whole) == 8


def test_sno_alg_res_06_random_level_is_one_number_per_window():
    a = portrait.random_level(N, 60, 200)
    b = portrait.random_level(N, 60, 200)
    assert a == b
    assert portrait.random_level(N, 40, 200) < a


# --- кривые ветвей и кластеры (Р16) -------------------------------------------

def people(values_by_branch, strata=("A", "B")):
    out = []
    for branch, rows in values_by_branch.items():
        for k, values in enumerate(rows):
            out.append({"branch": branch, "w": 1.0,
                        "stratum": strata[k % len(strata)],
                        "values": dict(enumerate(values))})
    return out


def test_sno_alg_res_06_cluster_found_where_planted():
    """Разница заложена в корзинах 3–6 — кластер там же, p < 0,05."""
    rng = random.Random(7)
    rows = {"I": [], "II": []}
    for branch in rows:
        for _ in range(8):
            curve = [0.9 + rng.gauss(0, 0.03) for _ in range(10)]
            if branch == "II":
                for b in range(3, 7):
                    curve[b] -= 0.25
            rows[branch].append(curve)
    test = stats.cluster_test(people(rows), threshold=0.33, min_n=3,
                              seed=1, repeats=999, exact_limit=20_000)
    best = min(test["clusters"], key=lambda c: c["p"])
    assert best["bins"] == [3, 4, 5, 6]
    assert best["mass"] < 0
    assert best["p"] < 0.05


def test_sno_alg_res_06_cluster_false_alarms_about_five_percent():
    """Без разницы ветвей кластер с p < 0,05 находится примерно в 5 %
    розыгрышей."""
    rng = random.Random(11)
    hits = 0
    sims = 120
    for s in range(sims):
        rows = {b: [[rng.gauss(0.9, 0.05) for _ in range(8)]
                    for _ in range(6)] for b in ("I", "II")}
        test = stats.cluster_test(people(rows), threshold=0.33, min_n=3,
                                  seed=s, repeats=199, exact_limit=0)
        if any(c["p"] < 0.05 for c in test["clusters"]):
            hits += 1
    assert hits / sims < 0.11


def test_sno_alg_res_06_bin_with_few_participants_is_left_out():
    rows = {"I": [[0.9, 0.9, 0.9], [0.9, 0.9, 0.9], [0.9, 0.9]],
            "II": [[0.5, 0.5, 0.5], [0.5, 0.5], [0.5, 0.5]]}
    test = stats.cluster_test(people(rows, strata=("A",)), threshold=0.33,
                              min_n=3, seed=1, repeats=99,
                              exact_limit=20_000)
    # В корзине 2 у ветви II один участник — корзины нет в тесте.
    assert test["bins"] == [0, 1]


def test_sno_alg_res_06_clusters_need_one_sign_and_neighbours():
    found = stats.clusters([0.5, 0.4, -0.6, 0.1, 0.5, 0.5],
                           [0, 1, 2, 3, 5, 6], 0.33)
    assert [c["bins"] for c in found] == [[0, 1], [2], [5, 6]]
    assert found[0]["mass"] == pytest.approx(0.9)


def test_sno_alg_res_06_cluster_exact_matches_brute_force():
    """Малая выборка — перебор всех разметок; p совпадает с подсчётом
    по формуле δ без numpy."""
    rows = {"I": [[0.9, 0.9], [0.8, 0.95], [0.85, 0.9]],
            "II": [[0.4, 0.5], [0.5, 0.45], [0.45, 0.4]]}
    group = people(rows, strata=("A",))
    test = stats.cluster_test(group, threshold=0.33, min_n=3, seed=1,
                              repeats=99, exact_limit=20_000)
    assert test["exact"] is True and test["permutations"] == 20
    import itertools

    def delta(xs2, xs1):
        s = sum((a > b) - (a < b) for a in xs2 for b in xs1)
        return s / (len(xs2) * len(xs1))

    observed = None
    masses = []
    for chosen in itertools.combinations(range(6), 3):
        lab = ["II" if i in chosen else "I" for i in range(6)]
        cur, sign, best = 0.0, 0, 0.0
        for b in (0, 1):
            x2 = [group[i]["values"][b] for i in range(6) if lab[i] == "II"]
            x1 = [group[i]["values"][b] for i in range(6) if lab[i] == "I"]
            d = delta(x2, x1)
            s = (d > 0) - (d < 0)
            strong = abs(d) >= 0.33 and s != 0
            if strong and s == sign:
                cur += d
            elif strong:
                cur, sign = d, s
            else:
                cur, sign = 0.0, 0
            best = max(best, abs(cur))
        masses.append(best)
        if chosen == (3, 4, 5):
            observed = best
    p = sum(m >= observed - 1e-12 for m in masses) / len(masses)
    assert test["clusters"][0]["p"] == pytest.approx(p)
    assert test["clusters"][0]["mass"] == pytest.approx(-2.0)


def test_sno_alg_res_06_branch_equals_pc_is_pooled():
    rows = {"I": [[0.9], [0.9], [0.9]], "II": [[0.5], [0.5], [0.5]]}
    group = people(rows, strata=("A",))
    for p in group:
        p["stratum"] = "ПК-" + p["branch"]
    test = stats.cluster_test(group, threshold=0.33, min_n=3, seed=1,
                              repeats=99, exact_limit=20_000)
    assert test["pooled"]


def test_sno_alg_res_06_settings_section():
    c = cfg()
    assert c["portrait"]["window_transitions"] == 60
    assert c["portrait"]["search_window"] == 40
    assert c["cluster_delta"] == 0.33
    assert set(c["portrait"]) == set(portrait.DEFAULTS)
