"""Шаг 43 — анализ по интерфейсу (SNO-F-RES-09): порядок обхода
(SNO-ALG-RES-11), проверки одной группы (SNO-ALG-RES-12), вердикт
предрегистрации (SNO-ALG-RES-13), опора на ориентиры (SNO-ALG-RES-14),
моргания (SNO-ALG-RES-15); дефекты BUG-73, BUG-74, BUG-75 — сначала
воспроизведением.
"""

from __future__ import annotations

import itertools
import json
import math
import random
from pathlib import Path

import numpy as np
import pytest

from sno_eye import report
from sno_eye.study import (average, blinks, order, prereg, reading_back,
                           single, stats)

import reading_ladder
from test_study_reading_back import (PC, SCREEN, frame, line_of, reading,
                                     samples_of)

EYE = Path(__file__).resolve().parent.parent


# --- BUG-75: наклон научения решает первый поход -----------------------

def _trips(times):
    return [{"complete": True, "time_to_choice_s": t, "first_time": True,
             "book": f"b{i}"} for i, t in enumerate(times)]


def test_bug_75_first_trip_does_not_decide_the_slope():
    """Первый поход 20 с, остальные 1 ± 0,2 с без тренда: прежний
    наклон наименьших квадратов заметно отрицателен, теперь — около
    нуля, а вход в интерфейс — 20 с отдельной мерой."""
    rng = random.Random(75)
    times = [20.0] + [max(0.3, rng.gauss(1.0, 0.2)) for _ in range(16)]
    e = {"status": "ok", "trips": _trips(times)}
    slope = average.slope(average.choice_series(e), 6)
    assert slope is not None and abs(slope) < 0.1


def test_bug_75_entry_and_after_first_are_measured_apart():
    rng = random.Random(75)
    times = [20.0] + [max(0.3, rng.gauss(1.0, 0.2)) for _ in range(16)]
    e = {"status": "ok", "trips": _trips(times)}
    average.learning([e], {"min_visits_curve": 6, "min_repeat_visits": 3})
    own = e["learn"]
    assert own["learn.entry_s"] == 20.0
    assert own["learn.after_first_s"] == pytest.approx(
        float(np.median(times[1:])))
    assert abs(own["learn.choice_slope"]) < 0.1
    assert abs(own["learn.choice_thirds"]) < 0.4
    # Повторов нет — сравнения повторного обращения нет.
    assert own["learn.repeat_vs_first"] is None


def test_bug_75_real_speedup_after_the_first_trip_is_found():
    """Настоящее ускорение со второго похода — закон степени с b = −0,5:
    наклон находится, последняя треть быстрее первой."""
    times = [15.0] + [8.0 * n ** -0.5 for n in range(2, 19)]
    e = {"status": "ok", "trips": _trips(times)}
    average.learning([e], {"min_visits_curve": 6, "min_repeat_visits": 3})
    assert e["learn"]["learn.choice_slope"] == pytest.approx(-0.5, abs=1e-9)
    assert e["learn"]["learn.choice_thirds"] < -0.5


def test_bug_75_theil_sen_against_pairs_by_hand():
    values = [(1, 30.0), (2, 4.0), (3, 3.0), (4, 3.5), (5, 2.0), (6, 2.5),
              (7, 2.2)]
    a, b, xm = average.fit(values, 3)
    pts = [(math.log(n), math.log(y)) for n, y in values if n > 1]
    slopes = sorted((y2 - y1) / (x2 - x1) for (x1, y1), (x2, y2)
                    in itertools.combinations(pts, 2))
    mid = len(slopes) // 2
    expected = slopes[mid] if len(slopes) % 2 else \
        (slopes[mid - 1] + slopes[mid]) / 2
    assert b == pytest.approx(expected)
    rest = sorted(y - b * x for x, y in pts)
    assert a == pytest.approx((rest[2] + rest[3]) / 2)
    assert xm == pytest.approx(sum(x for x, _ in pts) / len(pts))


def test_bug_75_repeat_against_first_when_repeats_are_enough():
    trips = _trips([10, 4, 4, 4, 4, 4, 2, 2, 2, 2])
    for t in trips[6:]:
        t["first_time"] = False
    e = {"status": "ok", "trips": trips}
    average.learning([e], {"min_visits_curve": 6, "min_repeat_visits": 3})
    assert e["learn"]["learn.repeats"] == 4
    assert e["learn"]["learn.repeat_vs_first"] == pytest.approx(
        math.log(2 / 4))


# --- BUG-74: возвраты на страницу назад считают перемотку ----------------

def shown(t, page, was, cause="tap_zone"):
    return {"t": t, "type": "page.shown", "book": "b", "page": page,
            "strip": 1, "data": {"cause": cause,
                                 "from": {"page": was, "strip": 1}}}


def test_bug_74_rewind_to_the_start_is_not_rereading():
    """Открытие на 19-й странице, 18 шагов назад по 0,1 с к первой,
    чтение вперёд, один шаг назад с задержкой 8 с: прежде — 19
    возвратов, теперь — 1 возврат, 1 перемотка, 1 возврат к началу."""
    events = [{"t": 0, "type": "book.open", "book": "b",
               "data": {"page": 19}}]
    t = 1000.0
    for page in range(18, 0, -1):
        events.append(shown(t, page, page + 1))
        t += 100
    t += 30_000
    for page in range(2, 6):
        events.append(shown(t, page, page - 1))
        t += 20_000
    events.append(shown(t, 4, 5))
    t += 8000
    events.append(shown(t, 5, 4))
    events.append({"t": t + 20_000, "type": "book.close", "book": "b"})
    out = reading_back.page_backs(events, line_of(t + 60_000), 2.0)
    assert out["backs"] == 1
    assert out["rewinds"] == 1
    assert out["to_start"] == 1
    assert out["opened_mid"] == 1
    assert out["rewind_pages"] == 18


def test_bug_74_quick_single_step_back_is_a_glance():
    events = [{"t": 0, "type": "book.open", "book": "b",
               "data": {"page": 1}},
              shown(5000, 2, 1), shown(15_000, 3, 2),
              shown(25_000, 2, 3), shown(25_600, 3, 2)]
    out = reading_back.page_backs(events, line_of(60_000), 2.0, 1.5)
    kinds = [r["kind"] for r in out["rows"]]
    # Вперёд и сразу назад — промах; шаг назад на 0,6 с без продолжения
    # назад — «мельком», не возврат.
    assert out["backs"] == 0
    assert out["glances"] + out["misflips"] == 1
    assert "назад" not in kinds


def test_bug_74_slow_steps_back_each_are_rereads():
    """Читатель листает назад медленно, задерживаясь на каждой странице
    — каждый шаг возврат, перемотки нет."""
    events = [{"t": 0, "type": "book.open", "book": "b",
               "data": {"page": 1}},
              shown(5000, 2, 1), shown(15_000, 3, 2), shown(25_000, 4, 3),
              shown(35_000, 3, 4), shown(41_000, 2, 3)]
    out = reading_back.page_backs(events, line_of(60_000), 2.0, 1.5)
    assert out["backs"] == 2
    assert out["rewinds"] == 0


# --- BUG-73: взгляд назад при чтении пуст у всех записей с веб-камеры ---

def test_bug_73_webcam_noise_reading_gets_its_lookbacks():
    """Шум кадра веб-камеры 1° по оси и прецизионность калибровки 2,2°:
    прежнее правило («три прецизионности больше 3°») меры не давало,
    хотя взгляды назад заложены; теперь они находятся на своих
    секундах."""
    looks, frames, end, planted = reading_ladder.pages(True)
    noisy = reading_ladder.samples(looks, SCREEN.px_for_deg(1.0), 7)
    line = line_of(end + 100, precision=2.2)
    out = reading_back.lookbacks(noisy, [], frames, SCREEN, line, None, PC,
                                 report.settings())
    assert out["reason"] is None
    found = [e["t0"] for e in out["episodes"]]
    assert len(planted) == 3
    for p in planted:
        assert any(abs(f - p) <= 300 for f in found)
    assert len(found) == len(planted)


def test_bug_73_reading_without_lookbacks_has_no_false_ones():
    looks, frames, end, _ = reading_ladder.pages(False)
    noisy = reading_ladder.samples(looks, SCREEN.px_for_deg(1.0), 7)
    out = reading_back.lookbacks(noisy, [], frames, SCREEN,
                                 line_of(end + 100, precision=2.2), None,
                                 PC, report.settings())
    assert out["reason"] is None
    assert out["count"] == 0


def test_bug_73_too_noisy_reading_is_gated_with_the_share():
    looks, frames, end, _ = reading_ladder.pages(True)
    noisy = reading_ladder.samples(looks, SCREEN.px_for_deg(2.4), 7)
    out = reading_back.lookbacks(noisy, [], frames, SCREEN,
                                 line_of(end + 100), None, PC,
                                 report.settings())
    assert out["episodes"] == []
    assert "шум дробит фиксации чтения" in out["reason"]
    assert out["fix_share"] < PC["reading_fix_share"]


def test_bug_73_threshold_grows_with_frame_noise_and_residual():
    looks, t = reading()
    out = reading_back.lookbacks(samples_of(looks, noise=2.0), [],
                                 [frame(0)], SCREEN, line_of(t), None, PC,
                                 report.settings())
    assert out["L_deg"] == pytest.approx(2.0)
    looks, frames, end, _ = reading_ladder.pages(True)
    noisy = reading_ladder.samples(looks, SCREEN.px_for_deg(1.0), 7)
    out = reading_back.lookbacks(noisy, [], frames, SCREEN,
                                 line_of(end + 100), None, PC,
                                 report.settings())
    assert out["L_deg"] == pytest.approx(
        PC["lookback_noise_k"] * out["s2s_deg"])
    out = reading_back.lookbacks(noisy, [], frames, SCREEN,
                                 line_of(end + 100), 7.0, PC,
                                 report.settings())
    assert out["L_deg"] == 7.0 and out["count"] == 0


def test_bug_73_ladder_holds_the_chosen_thresholds():
    """Лесенка шума чтения: выше порога доли в фиксациях все заложенные
    взгляды находятся и лишних нет; ниже — сессия без меры."""
    rows = reading_ladder.ladder(repeats=2)
    share = PC["reading_fix_share"]
    for r in rows:
        if r["share"] >= share + 0.03:
            assert r["gated"] == 0, r
            assert r["hits"] == r["planted"], r
            assert r["extra"] == 0, r
        if r["share"] <= share - 0.03:
            assert r["gated"] == r["runs"], r
    assert any(r["share"] < share for r in rows)


# --- SNO-ALG-RES-11: порядок обхода -------------------------------------

def _layout(n=12):
    cats = [("А", 0), ("Б", 1)]
    books = [(f"f{i:02d}", f"Книга {i}", "А" if i < n // 2 else "Б",
              float(i % (n // 2))) for i in range(n)]
    return {"categories": cats, "books": books}


def _entry(seq, mode="полкой", chart=None, code="1"):
    return {"status": "ok", "participant": code, "archive": f"{code}.zip",
            "search_mode": mode, "shelf_layout": _layout(),
            "map": chart,
            "trips": [{"complete": True, "book": b, "via": "полка"}
                      for b in seq]}


def _chart():
    points = []
    for i in range(12):
        group = "А" if i < 6 else "Б"
        x = (i % 3) * 1.0 + (0 if i < 6 else 5)
        y = (i % 6) // 3 * 1.0
        points.append({"book": f"f{i:02d}", "x": x, "y": y + 0.01 * i,
                       "group": group})
    return {"key": "abcd1234", "points": points}


CFG = {"permutations": 4000, "order": {}}


def test_sno_alg_res_11_shelf_order_is_found_against_chance():
    e = _entry([f"f{i:02d}" for i in range(12)])
    o = order.analyse(e, [], CFG, "fp")
    assert o["rho_shelf"] == pytest.approx(1.0)
    # Место сквозное: из конца категории А — в начало Б, тоже сосед.
    assert o["adjacent_share"] == pytest.approx(1.0)
    assert o["cat_switches"] == 1
    assert o["route_shelf"] < 0.3 and o["p_shelf"] < 0.01
    assert o["strategy"] == order.SHELF


def test_sno_alg_res_11_random_order_is_selective():
    rng = random.Random(11)
    seq = [f"f{i:02d}" for i in range(12)]
    rng.shuffle(seq)
    o = order.analyse(_entry(seq), [], CFG, "fp")
    assert o["strategy"] == order.SELECTIVE
    assert o["p_shelf"] > 0.05


def test_sno_alg_res_11_map_top_down_uses_the_shared_map():
    """Карта набора — у другой записи (того же набора книг); маршрут
    сверху вниз по группам находится и у того, кто открывал картой."""
    chart = _chart()
    seq = sorted((p for p in chart["points"]),
                 key=lambda p: (p["group"], p["y"], p["x"]))
    e = _entry([p["book"] for p in seq], mode="картой")
    other = _entry([], chart=chart, code="2")
    maps = order.literature_maps([e, other])
    o = order.analyse(e, maps, CFG, "fp")
    assert o["map_key"] == "abcd1234"
    assert o["rho_map"] == pytest.approx(1.0)
    assert o["p_map"] < 0.01
    assert o["strategy"] == order.MAP_DOWN


def test_sno_alg_res_11_route_p_against_full_enumeration():
    pts = np.array([[0.0], [1.0], [3.0], [2.0], [5.0], [4.0]])
    real = float(np.abs(np.diff(pts[:, 0])).sum())
    lengths = [float(np.abs(np.diff(pts[list(p), 0])).sum())
               for p in itertools.permutations(range(6))]
    exact_mean = sum(lengths) / len(lengths)
    exact_p = sum(1 for x in lengths if x <= real) / len(lengths)
    ratio, length, p = order.route(pts, 20_000, 5)
    assert length == real
    assert ratio == pytest.approx(real / exact_mean, rel=0.02)
    assert p == pytest.approx(exact_p, abs=0.01)


# --- SNO-ALG-RES-12: проверки одной группы ------------------------------

def test_sno_alg_res_12_sign_flip_against_full_enumeration_with_weights():
    d = [0.4, -0.1, 0.3, 0.25, 0.5, -0.05, 0.2]
    w = [1, 1, 0.5, 1, 1, 0.5, 1]
    z = [a * b for a, b in zip(d, w)]
    observed = abs(sum(z))
    hits = sum(1 for s in itertools.product((1, -1), repeat=len(z))
               if abs(sum(a * b for a, b in zip(s, z))) >= observed - 1e-12)
    assert stats.sign_flip_p(d, w, 1, 1000) == pytest.approx(
        hits / 2 ** len(z))


def test_sno_alg_res_12_sign_flip_draws_beyond_exact_limit():
    rng = random.Random(3)
    d = [abs(rng.gauss(0.5, 0.3)) for _ in range(20)]
    p = stats.sign_flip_p(d, [1] * 20, 9, 5000)
    assert p == pytest.approx(1 / 5001)
    assert stats.sign_flip_p(d, [1] * 20, 9, 5000) == p


def test_sno_alg_res_12_binomial_against_hand_numbers():
    assert stats.binom_p(9, 9) == pytest.approx(2 / 512)
    assert stats.binom_p(8, 9) == pytest.approx(2 * 10 / 512)
    assert stats.binom_p(3, 6) == pytest.approx(1.0)


def _shelf_entries(values: dict, n=9):
    out = []
    for i in range(n):
        e = {"status": "ok", "participant": f"P{i}", "archive": f"P{i}.zip",
             "branch": "II", "stratum": "ПК", "colour": "green",
             "series": "sno2026-2", "study_s": 2400, "duplicate": None,
             "etalon": "да", "etalon_out": None, "search_mode": "полкой",
             "gaze": {"present": True, "included": True},
             "order_measures": {}, "learn": {}, "gaze_measures": {},
             "test": {"state": "пройден", "measures": {}, "answers": [],
                      "lie": {}}, "actions": {}, "portrait_measures": {}}
        for key, xs in values.items():
            x = xs[i]
            if key.startswith("order."):
                e["order_measures"][key] = x
            elif key.startswith("learn."):
                e["learn"][key] = x
            else:
                e["gaze_measures"][key] = x
        out.append(e)
    return out


def _cfg():
    from sno_eye import study
    return study.settings()


def test_sno_alg_res_12_strong_effect_is_established_weak_is_not():
    rng = random.Random(12)
    entries = _shelf_entries({
        "order.route_shelf": [0.2 + 0.05 * rng.random() for _ in range(9)],
        "learn.choice_slope": [rng.gauss(0, 0.2) for _ in range(9)],
        "search.H_t": [0.9 + 0.02 * rng.random() for _ in range(9)]})
    res = single.run(entries, _cfg(), fingerprint="fp", no_filter=False,
                     series=None)
    by = {r["check"].key: r for r in res["table"]}
    assert by["order.route_shelf"]["words"].startswith("установлено")
    assert by["order.route_shelf"]["toward"] == 9
    assert by["order.route_shelf"]["check"].exploratory
    assert by["learn.choice_slope"]["words"].startswith("не доказано")
    assert by["search.H_t"]["words"].startswith("установлено")
    # Холм у главных: три p точного перебора 2/512 → ×3.
    assert by["order.route_shelf"]["p_adj"] == pytest.approx(
        min(1, 3 * 2 / 512))
    summary = res["summary"]
    assert any("маршрут" in x["words"] for x in summary["established"])
    assert summary["cannot"]


def test_sno_alg_res_12_too_few_participants_say_numbers_only():
    entries = _shelf_entries({"order.route_shelf": [0.2] * 5}, n=5)
    res = single.run(entries, _cfg(), fingerprint="fp", no_filter=False,
                     series=None)
    row = next(r for r in res["table"]
               if r["check"].key == "order.route_shelf")
    assert row["n"] == 5
    assert row["words"].startswith("не доказано: участников с мерой 5")


def test_sno_alg_res_12_red_is_out_and_shown_as_example():
    entries = _shelf_entries({"order.route_shelf": [0.2] * 9})
    entries[0]["colour"] = "red"
    entries[0]["test"]["lie"] = {"lie.defer": {"value": 1, "flag": True},
                                 "lie.late": {"value": 7, "flag": True}}
    cfg = _cfg()
    for e in entries:
        e["in_stats"] = e["colour"] != "red"
        e["weight"] = 1.0 if e["in_stats"] else 0.0
        e["out"] = [] if e["in_stats"] else ["🔴"]
    res = single.run(entries, cfg, fingerprint="fp", no_filter=False,
                     series=None)
    row = next(r for r in res["table"]
               if r["check"].key == "order.route_shelf")
    assert row["n"] == 8
    reds = res["reds"]
    assert reds["people"][0]["participant"] == "P0"
    assert reds["people"][0]["lie"] == {"lie.defer": 1, "lie.late": 7}
    kept = next(r for r in reds["with_reds"]
                if r["key"] == "order.route_shelf")
    assert kept["n"] == 9


# --- SNO-ALG-RES-13: вердикт предрегистрации ----------------------------

# Таблица заметки «Галактика — ожидаемое влияние сортировки
# (предрегистрация)» и «SNO-ALG-RES-13 Вердикт предрегистрации», записанная
# до данных: порог в `thresholds.json` не правится без этой таблицы.
PREREG = {
    "after": "2026-10-12T21:00:00+03:00",
    "main": ["M2", "M3", "M4", "M5"], "of_main": 3,
    "share": 2 / 3, "min_people": 3,
    "M1_rho": 0.8, "M1_alpha": 0.05, "M2_for": 0.60, "M2_against": 0.66,
    "M3_shelf": 4.3, "M4_orient1": 6, "M4_orient2": 5, "M5_for": 0.5,
    "M5_min_presses": 2, "M6_for": 2, "M6_against": 4, "M7_shelf": 3.9,
    "M7_fail": 60, "M8_low": 3, "M8_high": 5, "M9_for": 1.0,
    "M10_for": 0.30, "M10_against": 0.50,
}


def test_sno_alg_res_13_thresholds_are_the_preregistered_ones():
    raw = json.loads((EYE / "thresholds.json").read_text(encoding="utf-8"))
    own = raw["study"]["prereg"]
    assert set(own) == set(PREREG)
    for key, value in PREREG.items():
        if isinstance(value, float):
            assert own[key] == pytest.approx(value), key
        else:
            assert own[key] == value, key
    for key, value in PREREG.items():
        if isinstance(value, float):
            assert prereg.DEFAULTS[key] == pytest.approx(value), key
        else:
            assert prereg.DEFAULTS[key] == value, key


def _row(kinds: dict, eligible=True):
    cells = {k: {"kind": kinds.get(k, prereg.BETWEEN), "words": ""}
             for k, _, _ in prereg.MEASURES}
    main = PREREG["main"]
    return {"cells": cells, "eligible": eligible, "why_not": [],
            "for_main": sum(1 for k in main
                            if cells[k]["kind"] == prereg.FOR),
            "against_main": sum(1 for k in main
                                if cells[k]["kind"] == prereg.AGAINST)}


ALL_FOR = {k: prereg.FOR for k in ("M2", "M3", "M4", "M5")}
ALL_AGAINST = {k: prereg.AGAINST for k in ("M2", "M3", "M4", "M5")}


def test_sno_alg_res_13_verdict_rule():
    pc = prereg.settings(PREREG)
    assert prereg.verdict([_row(ALL_FOR)] * 3, pc)["word"] == \
        prereg.CONFIRMED
    assert prereg.verdict([_row(ALL_AGAINST)] * 3, pc)["word"] == \
        prereg.REFUTED
    mixed = [_row(ALL_FOR), _row(ALL_AGAINST), _row({})]
    assert prereg.verdict(mixed, pc)["word"] == prereg.UNDECIDED
    # Две трети из шести — четверо.
    four = [_row(ALL_FOR)] * 4 + [_row({})] * 2
    assert prereg.verdict(four, pc)["word"] == prereg.CONFIRMED
    three = [_row(ALL_FOR)] * 3 + [_row({})] * 3
    assert prereg.verdict(three, pc)["word"] == prereg.UNDECIDED
    # Три из четырёх главных — «за»; два — нет.
    two = {"M2": prereg.FOR, "M3": prereg.FOR}
    assert prereg.verdict([_row(two)] * 3, pc)["word"] == prereg.UNDECIDED
    # Вне вердикта (нет взгляда) не считаются: двое — мало записей.
    few = [_row(ALL_FOR)] * 2 + [_row(ALL_FOR, eligible=False)] * 2
    assert prereg.verdict(few, pc)["word"] == prereg.FEW
    assert prereg.verdict([], pc)["word"] == prereg.EMPTY


@pytest.mark.parametrize("key,value,kind", [
    ("M2", 0.60, prereg.FOR), ("M2", 0.63, prereg.BETWEEN),
    ("M2", 0.66, prereg.AGAINST), ("M3", 4.29, prereg.FOR),
    ("M3", 4.3, prereg.AGAINST), ("M4", (6, 5), prereg.FOR),
    ("M4", (7, 4), prereg.BETWEEN), ("M4", (5, 4), prereg.AGAINST),
    ("M5", (0.5, 0.2, 4), prereg.FOR), ("M5", (0.4, 0.2, 4), prereg.BETWEEN),
    ("M5", (0.1, 0.2, 4), prereg.AGAINST),
    ("M5", (0.9, 0.2, 1), prereg.NONE),
    ("M6", 2, prereg.FOR), ("M6", 3, prereg.BETWEEN),
    ("M6", 4, prereg.AGAINST), ("M7", 20.0, prereg.FOR),
    ("M7", 3.0, prereg.BETWEEN), ("M7", 61.0, prereg.AGAINST),
    ("M9", 1.8, prereg.FOR), ("M9", 0.9, prereg.AGAINST),
    ("M10", 0.3, prereg.FOR), ("M10", 0.4, prereg.BETWEEN),
    ("M10", 0.51, prereg.AGAINST),
    ("M1", (0.9, 0.001), prereg.FOR), ("M1", (0.3, 0.2), prereg.AGAINST),
    ("M1", (0.5, 0.01), prereg.BETWEEN),
])
def test_sno_alg_res_13_measure_rules(key, value, kind):
    pc = prereg.settings(PREREG)
    assert prereg.judge(key, value, pc, True)[0] == kind


def test_sno_alg_res_13_first_contact_is_after_the_mark_only():
    after = prereg.datetime.fromisoformat(PREREG["after"])
    early = {"clock_anchor": "2026-10-12T20:59:59.000+03:00"}
    late = {"clock_anchor": "2026-10-13T10:00:00.000+03:00"}
    utc = {"clock_anchor": "2026-10-12T18:00:00.000+00:00"}
    assert not prereg.first_contact(early, after)
    assert prereg.first_contact(late, after)
    assert prereg.first_contact(utc, after)
    assert not prereg.first_contact({}, after)


# --- SNO-ALG-RES-15: моргания -------------------------------------------

def _gaze(minutes, rate_first, rate_last, seed=1, long_close_at=None,
          face_loss_at=None):
    """Кадры по 33 мс, лицо видно; моргание — 4 кадра (132 мс)."""
    rng = random.Random(seed)
    rows = []
    end = minutes * 60_000
    third = end / 3
    blink_at = []
    t = 0.0
    while t < end:
        rate = rate_first if t < third else (
            rate_last if t >= 2 * third else (rate_first + rate_last) / 2)
        t += rng.expovariate(rate / 60_000)
        if t < end - 1000:
            blink_at.append(t)
    blink_at = [b for i, b in enumerate(blink_at)
                if i == 0 or b - blink_at[i - 1] > 500]
    n = 1
    t = 0.0
    while t < end:
        blink = any(b <= t < b + 132 for b in blink_at)
        if long_close_at is not None and \
                long_close_at <= t < long_close_at + 700:
            blink = True
        face = not (face_loss_at is not None and
                    face_loss_at <= t < face_loss_at + 2000)
        rows.append({"n": n, "t": t, "conf": 0.2 if blink else 0.95,
                     "yaw": 1.0 if face else None, "seg": 0,
                     "ok": face and not blink})
        n += 1
        t += 33
    return rows, blink_at


def test_sno_alg_res_15_blinks_and_their_course():
    rows, planted = _gaze(30, 12, 20)
    out = blinks.measure(rows, 0, 30 * 60_000)
    assert out["count"] == len(planted)
    assert out["thirds"][2] > out["thirds"][0]
    assert out["change"] > 0
    assert out["per_min"] == pytest.approx(len(planted) / 30, rel=0.02)


def test_sno_alg_res_15_long_closing_and_face_loss_are_not_blinks():
    rows, planted = _gaze(6, 0.0001, 0.0001, long_close_at=60_000,
                          face_loss_at=120_000)
    # Кадры вокруг потери лица: моргание у её края — не моргание.
    for r in rows:
        if 119_800 <= r["t"] < 120_000:
            r["conf"] = 0.2
    out = blinks.measure(rows, 0, 6 * 60_000)
    assert out["count"] == 0


def test_sno_alg_res_15_slow_camera_is_not_measured():
    rows = [{"t": t, "conf": 0.9, "yaw": 1.0, "seg": 0}
            for t in range(0, 60_000, 100)]
    out = blinks.measure(rows, 0, 60_000)
    assert out["count"] is None and "кадров в секунду" in out["reason"]


# --- весь путь на синтетической выборке ---------------------------------

def test_sno_f_res_09_interface_analysis_on_synthetic_set(tmp_path):
    """Шесть участников полкой по порядку и трое первого контакта с
    «Галактикой», у которых ожидания заложены «за»: группы по
    интерфейсу, маршрут найден, вердикт — подтверждено; запись карты до
    предрегистрации — справкой."""
    import study_scenario as sc
    from sno_eye import study
    people = [sc.Person(code=f"1000000{i}", branch="I" if i < 2 else "II",
                        via="shelf", seed=i, trips=10, choice_s=2.0,
                        ecl=4.5) for i in range(6)]
    people += [sc.Person(code=f"2000000{i}", branch="II", via="galaxy",
                         seed=20 + i, trips=10, choice_s=4.0, ecl=2.0,
                         orient=6.8, rec_id=f"G{i}", style="direct",
                         anchor="2026-10-13T10:00:00.000+03:00")
               for i in range(3)]
    people.append(sc.Person(code="30000000", branch="II", via="galaxy",
                            seed=40, trips=10, rec_id="G9",
                            anchor="2026-10-11T10:00:00.000+03:00"))
    sc.make_set(tmp_path / "in", people)
    run = study.analyse([str(tmp_path / "in")], mode="interface")
    res = run["result"]
    assert sorted(res["groups"][single.SHELF]) == \
        [f"1000000{i}" for i in range(6)]
    assert len(res["groups"][single.GALAXY]) == 4
    by = {e["participant"]: e for e in run["entries"]}
    assert by["10000000"]["order"]["strategy"] == order.SHELF
    assert by["20000000"]["order"]["strategy"] in (order.MAP_DOWN,
                                                    order.MAP)
    pre = res["prereg"]
    assert [r["participant"] for r in pre["reference"]] == ["30000000"]
    assert len(pre["rows"]) == 3
    for r in pre["rows"]:
        assert r["eligible"], r["why_not"]
        assert r["cells"]["M2"]["kind"] == prereg.FOR
        assert r["cells"]["M3"]["kind"] == prereg.FOR
    assert pre["verdict"]["word"] == prereg.CONFIRMED, pre["rows"]
    route = next(r for r in res["table"]
                 if r["check"].key == "order.route_shelf")
    assert route["n"] == 6 and route["toward"] == 6
    study.write(run, tmp_path / "out", portraits=False)
    page = (tmp_path / "out" / "index.html").read_text(encoding="utf-8")
    assert "Вердикт" in page and "подтверждено" in page
    for name in ("маршруты.csv", "итог.csv", "предрегистрация.csv"):
        assert (tmp_path / "out" / name).exists()
    again = study.analyse([str(tmp_path / "in")], mode="interface")
    assert [r["p"] for r in again["result"]["table"]] == \
        [r["p"] for r in res["table"]]
