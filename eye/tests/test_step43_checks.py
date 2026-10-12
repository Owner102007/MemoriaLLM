"""Шаг 43 — добавочные тесты независимой проверки: каждый ловит нарочно
внесённую ошибку, которую `test_step43.py` пропускал (ID алгоритма или
дефекта и номер мутанта — в
имени теста)."""

from __future__ import annotations

import itertools
import math
from collections import Counter

import numpy as np
import pytest

from sno_eye.study import average, blinks, order, prereg, reading_back, \
    single, stats
from sno_eye.study.actions import MODE_MAP, MODE_SHELF

from test_step43 import PREREG, _row, _trips, shown
from test_study_reading_back import line_of


# --- порядок обхода -------------------------------------------------------

def test_sno_alg_res_11_o1_shelf_place_follows_category_order_value():
    lay = {"categories": [("Б", 1), ("А", 0), ("В", 1)],
           "books": [("x", "b", "Б", 0.0), ("y", "a", "А", 0.0),
                     ("z", "c", "В", 0.0)]}
    # По значению порядка; при равном — по месту в списке категорий.
    assert order.shelf_places(lay) == {"y": (0, "А"), "x": (1, "Б"),
                                       "z": (2, "В")}


def test_sno_alg_res_11_o3_o4_within_minimum_and_mean_over_categories():
    seq = list("abcdefgh")
    value = {"a": 0, "b": 1, "c": 2, "d": 3,     # А: ρ = 1
             "e": 0, "f": 2, "g": 1, "h": 3}     # Б: ρ = 0,8
    group = {b: ("А" if b in "abcd" else "Б") for b in seq}
    # Категория ровно с [minimum] книгами считается.
    assert order.within(seq[:4], value, group, 4) == pytest.approx(1.0)
    assert order.within(seq[:3], value, group, 4) is None
    # Среднее по категориям, а не худшая.
    assert order.within(seq, value, group, 4) == pytest.approx(0.9)


def test_sno_alg_res_11_o6_route_p_is_plus_one_over_repeats_plus_one():
    pts = np.arange(8.0)[:, None]
    ratio, length, p = order.route(pts, 99, 1)
    assert length == 7.0
    # Ни одна из 99 случайных перестановок 8 книг не короче порядка
    # полки (вероятность 2/8! на розыгрыш): p = (0 + 1) / (99 + 1).
    assert p == pytest.approx(1 / 100)


def test_sno_alg_res_11_o8_sequence_keeps_first_opening_only():
    e = {"trips": [{"complete": True, "book": "a", "via": "полка"},
                   {"complete": True, "book": "b", "via": "полка"},
                   {"complete": True, "book": "a", "via": "карта"},
                   {"complete": False, "book": "c"},
                   {"complete": True, "book": None}]}
    assert order.sequence(e) == [("a", "полка"), ("b", "полка")]


def test_sno_alg_res_11_o10_o11_o12_strategy_boundaries():
    oc = order.settings(None)
    shelf = {"books": 6, "rho_shelf": 0.9, "p_shelf": 0.05}
    assert order.strategy(shelf, MODE_SHELF, oc) == order.SELECTIVE
    assert order.strategy(dict(shelf, p_shelf=0.049), MODE_SHELF, oc) == \
        order.SHELF
    chart = {"books": 6, "rho_map": 0.5, "p_map": 0.001}
    assert order.strategy(chart, MODE_MAP, oc) == order.MAP
    assert order.strategy(dict(chart, rho_map=0.8), MODE_MAP, oc) == \
        order.MAP_DOWN
    assert order.strategy({"books": 3, "rho_shelf": 1.0, "p_shelf": 0.001},
                          MODE_SHELF, oc) == order.TOO_FEW


# --- статистика одной группы ----------------------------------------------

def test_sno_alg_res_12_s1_sign_flip_drops_non_positive_weights():
    assert stats.sign_flip_p([1.0, 2.0], [0.0, -1.0], 1, 100) is None
    # 17 участников, у одного вес 0: остаётся 16 — точный перебор.
    d = [0.5 + 0.01 * i for i in range(17)]
    assert stats.sign_flip_p(d, [1.0] * 16 + [0.0], 1, 100) == \
        pytest.approx(2 / 2 ** 16)


def _exact_bootstrap_quantile(x, w, q):
    """Квантиль точного бутстрепа взвешенной медианы (все разметки
    повторов) и запас вероятности до соседних значений."""
    n = len(x)
    dist = Counter()
    for idx in itertools.combinations_with_replacement(range(n), n):
        c = Counter(idx)
        prob = math.factorial(n) / n ** n
        for k in c.values():
            prob /= math.factorial(k)
        dist[stats.weighted_median([x[i] for i in idx],
                                   [w[i] for i in idx])] += prob
    acc = 0.0
    for v in sorted(dist):
        lo, acc = acc, acc + dist[v]
        if acc >= q:
            return v, min(q - lo, acc - q)


def test_sno_alg_res_12_s5_s6_median_interval_against_exact_bootstrap():
    x, w = [7, 8, 14, 19, 28, 35], [1] * 6
    lo, m_lo = _exact_bootstrap_quantile(x, w, 0.025)
    hi, m_hi = _exact_bootstrap_quantile(x, w, 0.975)
    # 2,5 % — середина 7 и 8 (ровно половина веса), 97,5 % — 31,5;
    # запас ~0,01 вероятности — девять ошибок розыгрыша при 20 000.
    assert (lo, hi) == (7.5, 31.5) and min(m_lo, m_hi) > 0.009
    for seed in (1, 2, 3):
        assert stats.median_interval(x, w, seed, 20_000) == (lo, hi)


# --- научение (BUG-75) ----------------------------------------------------

def test_bug_75_a3_a4_thirds_ratio_by_hand():
    # Первый поход не входит: остальные одинаковы — ln 1 = 0.
    vals = [(1, 100.0)] + [(n, 1.0) for n in range(2, 8)]
    assert average.thirds_ratio(vals, 3) == pytest.approx(0.0)
    # Походы 2…10 (k = 3): медиана 8, 9, 10 к медиане 2, 3, 4.
    vals = [(n, float(n)) for n in range(1, 11)]
    assert average.thirds_ratio(vals, 3) == pytest.approx(math.log(9 / 3))


def test_bug_75_a5_repeat_vs_first_with_exactly_min_repeats():
    trips = _trips([10, 4, 4, 4, 2, 2, 2])
    for t in trips[4:]:
        t["first_time"] = False
    e = {"status": "ok", "trips": trips}
    average.learning([e], {"min_visits_curve": 6, "min_repeat_visits": 3})
    assert e["learn"]["learn.repeats"] == 3
    assert e["learn"]["learn.repeat_vs_first"] == pytest.approx(
        math.log(2 / 4))


# --- BUG-74: перемотка, возврат, мельком ----------------------------------

def _open(page, t=0):
    return {"t": t, "type": "book.open", "book": "b", "data": {"page": page}}


def _quick_back(events, t, start, stop, step_ms=100):
    for page in range(start - 1, stop - 1, -1):
        events.append(shown(t, page, page + 1))
        t += step_ms
    return t


def test_bug_74_r1_dwell_equal_to_threshold_ends_the_chain():
    events = [_open(1), shown(5000, 2, 1), shown(15_000, 3, 2),
              shown(25_000, 4, 3),
              shown(35_000, 3, 4), shown(36_500, 2, 3),   # 1,5 с ровно
              shown(50_000, 3, 2)]
    out = reading_back.page_backs(events, line_of(60_000), 2.0, 1.5)
    assert out["backs"] == 2 and out["rewinds"] == 0


def test_bug_74_r2_rewind_after_reading_forward_is_not_to_start():
    events = [_open(10), shown(5000, 11, 10)]
    t = _quick_back(events, 20_000, 11, 1)
    events.append(shown(t + 30_000, 2, 1))
    out = reading_back.page_backs(events, line_of(t + 60_000), 2.0)
    assert out["rewinds"] == 1 and out["to_start"] == 0


def test_bug_74_r10_rewind_must_end_on_the_first_page():
    events = [_open(10)]
    t = _quick_back(events, 1000, 10, 2)
    events.append(shown(t + 30_000, 3, 2))
    out = reading_back.page_backs(events, line_of(t + 60_000), 2.0)
    assert out["rewinds"] == 1 and out["to_start"] == 0
    assert out["opened_mid"] == 1


def test_bug_74_r4_r6_one_second_single_step_back_is_a_glance():
    events = [_open(1), shown(5000, 2, 1), shown(15_000, 3, 2),
              shown(25_000, 2, 3), shown(26_000, 3, 2)]
    out = reading_back.page_backs(events, line_of(60_000), 2.0, 1.5)
    assert out["glances"] == 1 and out["backs"] == 0
    assert out["misflips"] == 0
    assert out["opened_mid"] == 0          # открыта на первой странице


def test_bug_74_r5_forward_show_breaks_the_chain():
    events = [_open(1), shown(5000, 2, 1), shown(15_000, 3, 2),
              shown(25_000, 4, 3),
              shown(35_000, 3, 4),                      # назад, 0,3 с
              shown(35_300, 4, 3, cause="toc"),         # вперёд
              shown(35_600, 3, 4)]                      # назад, долго
    out = reading_back.page_backs(events, line_of(60_000), 2.0, 1.5)
    assert out["rewinds"] == 0
    assert out["glances"] == 1 and out["backs"] == 1


def test_bug_74_r8_misflip_returns_exactly_where_the_flip_came_from():
    events = [_open(1), shown(5000, 2, 1), shown(15_000, 3, 2),
              shown(15_500, 1, 3, cause="slider")]     # не на 2-ю
    out = reading_back.page_backs(events, line_of(60_000), 2.0)
    assert out["misflips"] == 0 and out["backs"] == 1


# --- моргания --------------------------------------------------------------

def _frames(t0, t1, step=33.0, seg=0, conf=0.95, face=True):
    out, t = [], t0
    while t < t1:
        out.append({"t": t, "conf": conf, "yaw": 1.0 if face else None,
                    "seg": seg})
        t += step
    return out


def _blink_at(rows, t0, frames=4):
    """Кадры моргания с [t0]: conf 0,2 у [frames] кадров подряд."""
    i = next(k for k, r in enumerate(rows) if r["t"] >= t0)
    for r in rows[i:i + frames]:
        r["conf"] = 0.2
    return i


def test_sno_alg_res_15_b2_dropped_frame_inside_or_after_blink_is_not_a_blink():
    rows = _frames(0, 60_000)
    i = _blink_at(rows, 10_000, 3)
    del rows[i + 3]                       # после моргания пропал кадр
    j = _blink_at(rows, 30_000, 4)
    del rows[j + 2]                       # посреди моргания пропал кадр
    out = blinks.measure(rows, 0, 60_000)
    assert out["count"] == 0


def test_sno_alg_res_15_b5_face_time_does_not_cover_a_hole_in_the_stream():
    rows = [r for r in _frames(0, 60_000) if not 30_000 <= r["t"] < 31_000]
    out = blinks.measure(rows, 0, 60_000)
    assert out["face_min"] == pytest.approx(59_000 / 60_000, rel=0.002)


def test_sno_alg_res_15_b6_thirds_are_counted_from_the_study_start():
    rows = _frames(60_000, 240_000)
    for t in (70_000, 80_000, 90_000):
        _blink_at(rows, t)
    out = blinks.measure(rows, 60_000, 240_000)
    assert out["counts"] == [3, 0, 0]


def test_sno_alg_res_15_b7_change_divides_each_third_by_its_own_face_time():
    rows = _frames(0, 150_000) + _frames(150_000, 180_000, face=False)
    out = blinks.measure(rows, 0, 180_000)
    assert out["count"] == 0
    # Без морганий: ln((0,5 / 0,5 мин) / (0,5 / 1 мин)) = ln 2.
    assert out["change"] == pytest.approx(math.log(2), rel=0.01)


def test_sno_alg_res_15_b8_blink_across_a_segment_start_is_not_a_blink():
    rows = _frames(0, 30_000) + _frames(30_033, 60_000, seg=1)
    _blink_at(rows, 30_033, 4)            # первые кадры нового сегмента
    out = blinks.measure(rows, 0, 60_000)
    assert out["count"] == 0


# --- предрегистрация -------------------------------------------------------

@pytest.mark.parametrize("key,value,gaze,kind", [
    ("M1", (0.5, 0.05), True, prereg.AGAINST),
    ("M5", (0.5, 0.5, 4), True, prereg.BETWEEN),
    ("M5", (0.9, 0.2, 4), False, prereg.NONE),
    ("M7", 50.0, True, prereg.FOR), ("M7", 60.0, True, prereg.FOR),
    ("M7", 3.9, True, prereg.BETWEEN),
    ("M8", 3.0, True, prereg.FOR), ("M8", 5.0, True, prereg.FOR),
    ("M8", 5.01, True, prereg.BETWEEN), ("M8", 2.99, True, prereg.BETWEEN),
    ("M9", 1.8, False, prereg.NONE),
    ("M10", 0.5, True, prereg.BETWEEN),
])
def test_sno_alg_res_13_p_measure_rule_boundaries(key, value, gaze, kind):
    pc = prereg.settings(PREREG)
    assert prereg.judge(key, value, pc, gaze)[0] == kind


def test_sno_alg_res_13_p8_verdict_uses_of_main_and_min_people_apart():
    pc = prereg.settings(dict(PREREG, of_main=2))
    two = {"M2": prereg.FOR, "M3": prereg.FOR}
    assert prereg.verdict([_row(two)] * 3, pc)["word"] == prereg.CONFIRMED
    pc = prereg.settings(dict(PREREG, min_people=4))
    assert prereg.verdict([_row({k: prereg.FOR for k in PREREG["main"]})]
                          * 3, pc)["word"] == prereg.FEW


# --- проверки одной группы -------------------------------------------------

def _check(key):
    return next(c for c in single.CHECKS if c.key == key)


def test_sno_alg_res_12_g2_g3_g6_check_once_by_hand():
    c = _check("order.route_shelf")
    assert single.deviation(c, 0.0) is None
    assert single.deviation(c, -1.0) is None
    rows = [(1.0, 1.0, {}), (0.5, 1.0, {}), (0.5, 1.0, {}), (0.4, 1.0, {}),
            (0.0, 1.0, {})]
    out = single.check_once(c, rows, 1, single.settings(None), True)
    assert out["n"] == 4                      # ln 0 — не мера
    assert out["toward"] == 3                 # ln 1 = 0 — не в сторону
    # Точный двусторонний: исходы 0, 1, 3, 4 из 4 — (1 + 4 + 4 + 1) / 16.
    assert out["binom_p"] == pytest.approx(10 / 16)


def test_sno_alg_res_12_g7_two_sided_check_counts_the_median_side():
    c = _check("search.K")
    rows = [(-0.5, 1.0, {}), (-0.4, 1.0, {}), (-0.3, 1.0, {}),
            (0.2, 1.0, {})]
    out = single.check_once(c, rows, 1, single.settings(None), False)
    assert out["median"] < 0 and out["toward"] == 3


def test_sno_alg_res_12_g4_g5_words_interval_and_n_min():
    c = _check("order.route_shelf")           # эффект — меньше нуля
    holds = {"S0": {"holds": True}}
    own = {"n": 6, "p_adj": 0.01, "median": -0.5, "ci": (-0.9, -0.1)}
    assert single._words(c, own, holds, 6, 0.05).startswith("установлено")
    assert single._words(c, dict(own, ci=(-0.9, 0.1)), holds, 6,
                         0.05).startswith("не доказано: интервал")
