"""Шаг 41 — свод средних ветвей, структурированная матрица, итог «в чём
ветвь II сильнее» (SNO-ALG-RES-10) и два дефекта того же кода: BUG-71
(оговорка «ветвь совпадает с ПК» обо всём наборе) и BUG-72 (перекрытые
отлучки вычитаются дважды).

Числа — учебные, посчитанные руками или полным перебором: свой код здесь
проверяется против формулы, а не против самого себя.
"""

from __future__ import annotations

import itertools
import math
import statistics

import numpy as np
import pytest

from sno_eye.report.timeline import Timeline
from sno_eye.study import actions, compare, means, stats


def _line(screens, away, start=0.0, end=100.0) -> Timeline:
    line = Timeline(study_start=start, study_end=end, gaze_expected=False,
                    latency_ms=0.0, latency_known=False, start_deg=None,
                    end_deg=None, precision_deg=None, end_shift_mm=None)
    line.screens = list(screens)
    line.away = list(away)
    return line


# --- BUG-72 -----------------------------------------------------------------

def test_bug_72_overlapping_aways_subtract_their_union():
    line = _line([(0.0, "shelf")], [(10.0, 30.0, "hidden"),
                                    (20.0, 40.0, "hidden")])
    # Объединение отлучек — [10, 40), 30 мс; участок — 100 мс.
    assert actions._screen_time(line, 0.0, 100.0, ("shelf",)) == \
        pytest.approx(70.0)


def test_bug_72_example_from_independent_check():
    """Пример независимой проверки шага 40: экраны `galaxy` с 2937 и
    `shelf` с 30998, отлучки 9222–13320 и 11385–13554, изучение
    2979–42606."""
    line = _line([(2937.0, "galaxy"), (30998.0, "shelf")],
                 [(9222.0, 13320.0, "hidden"), (11385.0, 13554.0, "hidden")],
                 2979.0, 42606.0)
    union = 13554.0 - 9222.0
    assert actions._screen_time(line, 2979.0, 42606.0,
                                ("galaxy", "shelf")) == \
        pytest.approx(42606.0 - 2979.0 - union)


def test_bug_72_nested_and_disjoint_aways():
    line = _line([(0.0, "reader")], [(5.0, 50.0, "a"), (10.0, 20.0, "b"),
                                     (60.0, 70.0, "c"), (95.0, 120.0, "d")])
    # Объединение внутри [0, 100): [5, 50) + [60, 70) + [95, 100) = 60.
    assert actions._screen_time(line, 0.0, 100.0, ("reader",)) == \
        pytest.approx(40.0)


# --- BUG-71 -----------------------------------------------------------------

def _row(key, pooled, enough=True):
    res = stats.Result(pooled=pooled, enough=enough)
    return {"comparison": compare.BRANCH, "measure": compare.BY_KEY[key],
            "result": res}


def _entries():
    return [{"in_stats": True, "branch": b, "series": "sno2026-1"}
            for b in ("I", "II", "I", "II")]


def test_bug_71_warning_names_only_pooled_measures():
    result = {"table": [_row("share.reading", True),
                        _row("share.search", True),
                        _row("clt.ecl", False),
                        _row("actions.time_to_choice", False)]}
    words = compare.warnings(_entries(), result, False)
    text = " ".join(words)
    assert "ни на одном ПК не было обеих ветвей" not in text
    assert "Доля изучения: взгляд на чтении" in text
    assert "Доля изучения: взгляд на полке и карте" in text
    assert "ECL" not in text


def test_bug_71_no_pooled_measure_no_warning():
    result = {"table": [_row("clt.ecl", False)]}
    assert not any("ПК" in w for w in compare.warnings(
        _entries(), result, False))


def test_bug_71_all_pooled_keeps_old_words():
    result = {"table": [_row("clt.ecl", True), _row("search.H_t", True)]}
    text = " ".join(compare.warnings(_entries(), result, False))
    assert "ни на одном ПК не было обеих ветвей" in text


def test_bug_71_measures_without_data_do_not_count():
    """Мера, у которой сравнения нет вовсе (только одна ветвь), — не
    «совпадает с ПК»: в ней сравнения нет."""
    result = {"table": [_row("clt.ecl", False),
                        _row("share.off", True, enough=False)]}
    text = " ".join(compare.warnings(_entries(), result, False))
    assert "Доля изучения: вне экрана" in text


# --- средние: учебные числа -------------------------------------------------

def test_sno_alg_res_10_weighted_mean_and_geometric_mean():
    assert means.mean([1, 2, 4], [1, 1, 2], "lin") == pytest.approx(11 / 4)
    # Геометрическое: exp(Σ w ln x / Σ w).
    assert means.mean([1, 2, 4], [1, 1, 1], "log") == pytest.approx(2.0)
    assert means.mean([1, 4], [1, 3], "log") == pytest.approx(
        math.exp(3 * math.log(4) / 4))


def test_sno_alg_res_10_log_scale_falls_back_on_zeros():
    cfg = {"log_zero_share": 0.2}
    # Мера времени без нулей — log.
    assert means.scale_of(compare.BY_KEY["actions.time_to_choice"],
                          [1.0, 2.0, 3.0, 4.0, 5.0], cfg)[0] == "log"
    # Нулей 2 из 5 = 40 % > 20 % — lin.
    scale, why = means.scale_of(compare.BY_KEY["actions.time_to_choice"],
                                [0.0, 0.0, 3.0, 4.0, 5.0], cfg)
    assert scale == "lin" and "нул" in why
    # Нуль один из 10 — log с поправкой половиной наименьшего ненулевого.
    vals = [0.0] + [float(i) for i in range(1, 10)]
    scale, why = means.scale_of(compare.BY_KEY["actions.time_to_choice"],
                                vals, cfg)
    assert scale == "log" and "0,5" in why
    # Доля и шкала теста — всегда lin.
    assert means.scale_of(compare.BY_KEY["clt.ecl"], [1, 2, 3],
                          cfg)[0] == "lin"


def test_sno_alg_res_10_stratified_ratio_one_stratum():
    """Один слой, равные веса: отношение — частное геометрических
    средних."""
    rows = [(2.0, 1, "II", "A"), (8.0, 1, "II", "A"),
            (1.0, 1, "I", "A"), (4.0, 1, "I", "A")]
    out = means.difference(rows, "log", seed=1, repeats=200,
                           perm_repeats=200, exact_limit=1000)
    assert out["value"] == pytest.approx(4.0 / 2.0)


def test_sno_alg_res_10_difference_one_stratum_is_plain_difference():
    rows = [(5.0, 1, "II", "A"), (7.0, 1, "II", "A"),
            (1.0, 1, "I", "A"), (3.0, 1, "I", "A")]
    out = means.difference(rows, "lin", seed=1, repeats=200,
                           perm_repeats=200, exact_limit=1000)
    assert out["value"] == pytest.approx(4.0)


def test_sno_alg_res_10_difference_permutation_exact_vs_full_enumeration():
    """p разницы средних перестановками внутри слоя — против полного
    перебора, посчитанного здесь отдельно."""
    a2, a1 = [5.0, 7.0, 6.0], [1.0, 3.0, 4.0]
    b2, b1 = [2.0, 9.0], [4.0, 1.0, 0.0]
    rows = ([(x, 1, "II", "A") for x in a2] + [(x, 1, "I", "A") for x in a1]
            + [(x, 1, "II", "B") for x in b2]
            + [(x, 1, "I", "B") for x in b1])
    out = means.difference(rows, "lin", seed=1, repeats=100,
                           perm_repeats=100, exact_limit=10_000)
    assert out["exact"]

    def lam(n1, n2):
        return n1 * n2 / (n1 + n2)

    def stat(sa2, sa1, sb2, sb1):
        la, lb = lam(len(sa1), len(sa2)), lam(len(sb1), len(sb2))
        da = statistics.mean(sa2) - statistics.mean(sa1)
        db = statistics.mean(sb2) - statistics.mean(sb1)
        return (la * da + lb * db) / (la + lb)

    observed = stat(a2, a1, b2, b1)
    pa, pb = a2 + a1, b2 + b1
    hits = total = 0
    for ia in itertools.combinations(range(len(pa)), len(a2)):
        sa2 = [pa[i] for i in ia]
        sa1 = [pa[i] for i in range(len(pa)) if i not in ia]
        for ib in itertools.combinations(range(len(pb)), len(b2)):
            sb2 = [pb[i] for i in ib]
            sb1 = [pb[i] for i in range(len(pb)) if i not in ib]
            total += 1
            if abs(stat(sa2, sa1, sb2, sb1)) >= abs(observed) - 1e-12:
                hits += 1
    assert out["value"] == pytest.approx(observed)
    assert out["p"] == pytest.approx(hits / total)


def test_sno_alg_res_10_hedges_g_against_table():
    """g = J · (m₂ − m₁) / s, s объединяется по n − 1; J = 1 − 3 / (4(n₁ +
    n₂) − 9) (Hedges, 1981): при n₁ = n₂ = 5 J = 1 − 3/31."""
    x2 = [6.0, 7.0, 8.0, 9.0, 10.0]
    x1 = [1.0, 2.0, 3.0, 4.0, 5.0]
    rows = [(x, 1, "II", "A") for x in x2] + [(x, 1, "I", "A") for x in x1]
    g = means.hedges_g(rows, "lin")
    s = math.sqrt((4 * statistics.variance(x2) + 4 * statistics.variance(
        x1)) / 8)
    assert g == pytest.approx((1 - 3 / 31) * 5.0 / s)
    # Таблица Хеджеса: J(10) ≈ 0,9032 (Hedges, 1981, табл. 2 — для
    # m = n₁ + n₂ − 2 = 8: 0,9033).
    assert 1 - 3 / (4 * 10 - 9) == pytest.approx(0.9032, abs=2e-4)


def test_sno_alg_res_10_hedges_pooled_within_pc():
    """SD объединяется внутри ПК: сдвиг всего ПК B на 100 не раздувает
    разброс."""
    rows = []
    for shift, pc in ((0.0, "A"), (100.0, "B")):
        rows += [(shift + x, 1, "II", pc) for x in (6.0, 7.0, 8.0)]
        rows += [(shift + x, 1, "I", pc) for x in (1.0, 2.0, 3.0)]
    g = means.hedges_g(rows, "lin")
    assert g > 3.0


def test_sno_alg_res_10_hierarchical_bootstrap_widens_with_clustering():
    """Иерархический бутстреп (Saravanan и др., 2020): если походы
    одного участника похожи между собой (участники далеко друг от
    друга), интервал шире, чем у походов без связи: разброс участников
    в нём не теряется."""
    import random
    rnd = random.Random(5)
    loose = {}
    tight = {}
    for b in ("I", "II"):
        for i in range(6):
            code = f"{b}{i}"
            level = rnd.gauss(0, 6)
            loose[code] = (b, "A", 1.0,
                           [rnd.gauss(10, 3) for _ in range(8)])
            tight[code] = (b, "A", 1.0,
                           [10 + level + rnd.gauss(0, 0.3)
                            for _ in range(8)])
    lo = means.hierarchical(loose, "lin", seed=3, repeats=2000)
    hi = means.hierarchical(tight, "lin", seed=3, repeats=2000)
    assert (hi[1] - hi[0]) > 1.5 * (lo[1] - lo[0])


# --- слова: δ и знак средних (АЛ4 (а)) -------------------------------------

def _res(delta, ci, diff):
    r = stats.Result(enough=True, delta=delta, ci=ci, p=0.01)
    r.diff = diff
    return r


def test_sno_alg_res_10_words_need_same_sign_of_means():
    assert compare.words(_res(0.6, (0.2, 0.9), 3.0), 0.01, 0.05,
                         ("II", "I"), diff=3.0) == "в ветви II больше"
    assert compare.words(_res(0.6, (0.2, 0.9), 3.0), 0.01, 0.05,
                         ("II", "I"), diff=-1.0) == \
        "разница не доказана: среднее и ранги говорят разное"


def test_sno_alg_res_10_no_difference_is_never_claimed():
    w = compare.words(_res(0.1, (-0.3, 0.5), 0.2), 0.5, 0.05, ("II", "I"),
                      diff=0.2)
    assert w == "разница не доказана"
    assert "разницы нет" not in w and "не видно" not in w


# --- поправка Бенджамини — Хохберга ----------------------------------------

def test_sno_alg_res_10_benjamini_hochberg_against_hand():
    ps = [0.01, 0.04, 0.03, 0.20, None]
    # Порядок: 0,01 · 4/1 = 0,04; 0,03 · 4/2 = 0,06; 0,04 · 4/3 = 0,0533;
    # 0,20 · 4/4 = 0,20; накопленный минимум сверху вниз.
    out = stats.bh(ps)
    assert out[0] == pytest.approx(0.04)
    assert out[2] == pytest.approx(0.04 * 4 / 3)
    assert out[1] == pytest.approx(0.04 * 4 / 3)
    assert out[3] == pytest.approx(0.20)
    assert out[4] is None


# --- итог «сильнее / слабее» -------------------------------------------------

def test_sno_alg_res_10_verdict_matches_arrow():
    m_down = compare.BY_KEY["clt.ecl"]
    cfg = {"better": {"clt.ecl": "↓", "clt.gcl": "↑"}}
    assert means.verdict(m_down, "в ветви II меньше", "устойчив",
                         cfg) == "сильнее"
    assert means.verdict(m_down, "в ветви II больше", "устойчив",
                         cfg) == "слабее"
    assert means.verdict(m_down, "в ветви II меньше", "неустойчив",
                         cfg) == "не держится"
    assert means.verdict(compare.BY_KEY["clt.gcl"], "в ветви II больше",
                         "устойчив", cfg) == "сильнее"
    assert means.verdict(compare.BY_KEY["share.off"], "в ветви II больше",
                         "устойчив", cfg) == "направление не задано"
    assert means.verdict(m_down, "мало данных — только описание",
                         "мало данных", cfg) == "мало данных"
    assert means.verdict(m_down, "разница не доказана", "устойчив",
                         cfg) == "разница не доказана"


def test_sno_alg_res_10_every_measure_has_direction_in_thresholds(eye_dir):
    """АЛ6: направление записано у каждой меры — стрелкой или явным «—»,
    до основной серии."""
    import json
    raw = json.loads((eye_dir / "thresholds.json").read_text("utf-8"))
    better = raw["study"]["better"]
    for m in compare.MEASURES:
        assert better.get(m.key) in ("↓", "↑", "—"), m.key
    assert set(better) <= set(compare.BY_KEY)


# --- сумма О'Брайена --------------------------------------------------------

def _obrien_entries(shift_a, shift_b):
    """Шесть участников на ветвь, два ПК; две меры «↓»."""
    out = []
    for b, sign in (("I", 0), ("II", 1)):
        for i in range(6):
            out.append({"branch": b, "stratum": "A" if i % 2 else "B",
                        "w": 1.0,
                        "values": {"m1": i + sign * shift_a,
                                   "m2": (i * 7) % 6 + sign * shift_b}})
    return out


def test_sno_alg_res_10_obrien_same_direction_stronger():
    better = {"m1": "↓", "m2": "↓"}
    same = means.obrien(_obrien_entries(-3, -3), ["m1", "m2"], better,
                        merge_rho=0.99, seed=1, repeats=2000,
                        exact_limit=50_000)
    mixed = means.obrien(_obrien_entries(-3, 3), ["m1", "m2"], better,
                         merge_rho=0.99, seed=1, repeats=2000,
                         exact_limit=50_000)
    # «↓» и у II меньше — у II лучше.
    assert same["delta"] > 0
    assert same["p"] < mixed["p"]
    assert abs(mixed["delta"]) < abs(same["delta"])


def test_sno_alg_res_10_obrien_linked_measures_share_weight():
    better = {"m1": "↓", "m2": "↓", "m3": "↓"}
    rows = []
    for b in ("I", "II"):
        for i in range(5):
            rows.append({"branch": b, "stratum": "A", "w": 1.0,
                         "values": {"m1": i, "m2": i * 2 + 0.1,
                                    "m3": (i * 3) % 5}})
    out = means.obrien(rows, ["m1", "m2", "m3"], better, merge_rho=0.7,
                       seed=1, repeats=500, exact_limit=50_000)
    assert out["weights"]["m1"] == pytest.approx(0.25)
    assert out["weights"]["m2"] == pytest.approx(0.25)
    assert out["weights"]["m3"] == pytest.approx(0.5)


def test_sno_alg_res_10_obrien_skips_measures_without_arrow():
    out = means.obrien(_obrien_entries(-3, -3), ["m1", "m2"],
                       {"m1": "↓", "m2": "—"}, merge_rho=0.99, seed=1,
                       repeats=200, exact_limit=50_000)
    assert out["measures"] == ["m1"]


# --- границы правил (по независимой проверке шага 41) ----------------------

def test_sno_alg_res_10_obrien_link_threshold_is_inclusive():
    """|ρ| = merge_rho — уже связаны (≥, а не >)."""
    rows = [{"branch": b, "stratum": "A", "w": 1.0,
             "values": {"m1": i, "m2": 2 * i, "m3": (i * 3) % 5}}
            for b in ("I", "II") for i in range(5)]
    out = means.obrien(rows, ["m1", "m2", "m3"],
                       {"m1": "↓", "m2": "↓", "m3": "↓"}, merge_rho=1.0,
                       seed=1, repeats=200, exact_limit=50_000)
    assert out["weights"]["m1"] == pytest.approx(0.25)


def test_sno_alg_res_10_obrien_rank_share_is_within_its_pc():
    """Доля — ранг, делённый на число участников **своего** ПК."""
    rows = ([{"branch": "I", "stratum": "A", "w": 1.0, "values": {"m": x}}
             for x in (1.0, 2.0)]
            + [{"branch": "II", "stratum": "B", "w": 1.0, "values": {"m": x}}
               for x in (1.0, 2.0, 3.0, 4.0)])
    out = means.obrien(rows, ["m"], {"m": "↑"}, merge_rho=0.7, seed=1,
                       repeats=100, exact_limit=10_000)
    assert out["scores"] == pytest.approx([0.5, 1.0, 0.25, 0.5, 0.75, 1.0])


def test_sno_alg_res_10_obrien_half_of_the_measures_is_enough():
    rows = [{"branch": "I", "stratum": "A", "w": 1.0,
             "values": {"m1": 1.0}},
            {"branch": "II", "stratum": "A", "w": 1.0,
             "values": {"m1": 2.0, "m2": 3.0}},
            {"branch": "I", "stratum": "A", "w": 1.0,
             "values": {"m2": 1.0}}]
    out = means.obrien(rows, ["m1", "m2"], {"m1": "↑", "m2": "↑"},
                       merge_rho=0.99, seed=1, repeats=100,
                       exact_limit=10_000)
    assert all(s is not None for s in out["scores"])


def test_sno_alg_res_10_obrien_link_uses_weighted_spearman():
    """Связь мер — Спирмен с весами: несогласные участники с малым весом
    связь не рвут."""
    xs = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    ys = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 7.0]
    zs = [8.0, 7.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    ws = [0.05, 0.05, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    weighted = stats.spearman(xs, zs, ws)
    plain = stats.spearman(xs, zs, [1.0] * 8)
    assert weighted >= 0.7 > plain
    rows = [{"branch": "I" if i % 2 else "II", "stratum": "A", "w": w,
             "values": {"m1": x, "m2": y, "m3": z}}
            for i, (x, y, z, w) in enumerate(zip(xs, ys, zs, ws))]
    out = means.obrien(rows, ["m1", "m3", "m2"],
                       {"m1": "↑", "m2": "↑", "m3": "↑"}, merge_rho=0.7,
                       seed=1, repeats=100, exact_limit=50_000)
    # Все три связаны: m1 — m2 сильно, m1 — m3 — с весами.
    assert out["weights"]["m3"] == pytest.approx(1 / 3)


def test_sno_alg_res_10_zero_share_at_the_limit_stays_log():
    """Нулей ровно 20 % — ещё логарифм (больше доли — нет)."""
    scale, _ = means.scale_of(compare.BY_KEY["actions.time_to_choice"],
                              [0.0, 1.0, 2.0, 3.0, 4.0],
                              {"log_zero_share": 0.2})
    assert scale == "log"


def test_sno_alg_res_10_zero_becomes_half_the_smallest():
    vals = means.transform([0.0, 2.0, 4.0], "log")
    assert list(vals) == pytest.approx([math.log(1.0), math.log(2.0),
                                        math.log(4.0)])


def test_sno_alg_res_10_hedges_unequal_cells():
    """Клетки разного размера: s² = Σ(n − 1)s² / Σ(n − 1)."""
    x2 = [6.0, 8.0, 10.0]
    x1 = [1.0, 2.0, 4.0, 5.0, 7.0, 3.0]
    rows = [(x, 1, "II", "A") for x in x2] + [(x, 1, "I", "A") for x in x1]
    s2 = (2 * statistics.variance(x2) + 5 * statistics.variance(x1)) / 7
    d = statistics.mean(x2) - statistics.mean(x1)
    assert means.hedges_g(rows, "lin") == pytest.approx(
        (1 - 3 / (4 * 9 - 9)) * d / math.sqrt(s2))


def test_sno_alg_res_10_hedges_j_uses_n_eff():
    """В J — n_eff ветвей: у половинных весов он меньше числа людей."""
    x2 = [6.0, 7.0, 8.0, 9.0]
    x1 = [1.0, 2.0, 3.0, 4.0]
    w = [1.0, 1.0, 0.5, 0.5]
    rows = [(x, wi, "II", "A") for x, wi in zip(x2, w)] + \
        [(x, wi, "I", "A") for x, wi in zip(x1, w)]
    neff = stats.n_eff(w)
    assert neff < 4
    g = means.hedges_g(rows, "lin")
    j = 1 - 3 / (4 * (2 * neff) - 9)
    d = stats.weighted_mean(x2, w) - stats.weighted_mean(x1, w)
    cells = [means._cell_var(np.array(x), np.array(w)) for x in (x2, x1)]
    s = math.sqrt(sum(df * v for v, df in cells) / sum(df for _, df in
                                                       cells))
    assert g == pytest.approx(j * d / s)


def test_sno_alg_res_10_permutation_lambda_with_weights():
    """Перестановки с весами и слоями разного размера — против полного
    перебора, где λ считается из весов."""
    a = [(5.0, 1.0, "II"), (6.0, 0.5, "II"), (1.0, 1.0, "I"),
         (2.0, 1.0, "I"), (3.0, 0.5, "I"), (0.5, 1.0, "I"),
         (4.0, 1.0, "I"), (2.5, 0.5, "I")]
    b = [(9.0, 1.0, "II"), (1.0, 0.5, "II"), (7.0, 1.0, "II"),
         (8.0, 1.0, "II"), (4.0, 0.5, "I"), (0.0, 1.0, "I")]
    rows = [(x, w, g, "A") for x, w, g in a] + \
        [(x, w, g, "B") for x, w, g in b]
    out = means.difference(rows, "lin", seed=1, repeats=100,
                           perm_repeats=100, exact_limit=100_000)
    assert out["exact"]

    def part(items, chosen):
        two = [items[i] for i in chosen]
        one = [items[i] for i in range(len(items)) if i not in chosen]
        W2 = sum(w for _, w in two)
        W1 = sum(w for _, w in one)
        d = sum(x * w for x, w in two) / W2 - sum(x * w for x, w in one) \
            / W1
        return d, W1 * W2 / (W1 + W2)

    ia = [(x, w) for x, w, _ in a]
    ib = [(x, w) for x, w, _ in b]
    ka = sum(1 for _, _, g in a if g == "II")
    kb = sum(1 for _, _, g in b if g == "II")
    da, la = part(ia, [i for i, r in enumerate(a) if r[2] == "II"])
    db, lb = part(ib, [i for i, r in enumerate(b) if r[2] == "II"])
    observed = (la * da + lb * db) / (la + lb)
    hits = total = 0
    for ca in itertools.combinations(range(len(ia)), ka):
        d1, l1 = part(ia, ca)
        for cb in itertools.combinations(range(len(ib)), kb):
            d2, l2 = part(ib, cb)
            total += 1
            if abs((l1 * d1 + l2 * d2) / (l1 + l2)) >= abs(observed) - 1e-12:
                hits += 1
    assert out["value"] == pytest.approx(observed)
    assert out["p"] == pytest.approx(hits / total)


def test_sno_alg_res_10_branch_equals_pc_falls_back_to_one_layer():
    rows = [(5.0, 1, "II", "A"), (7.0, 1, "II", "A"),
            (1.0, 1, "I", "B"), (3.0, 1, "I", "B")]
    out = means.difference(rows, "lin", seed=1, repeats=100,
                           perm_repeats=100, exact_limit=1000)
    assert out["pooled"] and out["value"] == pytest.approx(4.0)


def test_sno_alg_res_10_words_need_adjusted_p():
    assert compare.words(_res(0.6, (0.2, 0.9), 3.0), 0.2, 0.05,
                         ("II", "I"), diff=3.0) == "разница не доказана"


def test_sno_alg_res_10_zero_mean_difference_is_not_agreement():
    assert compare.words(_res(0.6, (0.2, 0.9), 0.0), 0.01, 0.05,
                         ("II", "I"), diff=0.0) == \
        "разница не доказана: среднее и ранги говорят разное"


def test_sno_alg_res_10_small_n_eff_gives_only_branch_means():
    """Правка v0.47.1: одна-два участника в ветви — разница с интервалом
    бутстрепа вырождается в точку ([x; x]) и выглядит точной; по
    ALG-RES-10 при n_eff < 3 — только средние."""
    rows = [(5.0, 1.0, "II", "A", None, "a"), (7.0, 1.0, "II", "B", None,
                                                "b"),
            (1.0, 1.0, "I", "A", None, "c"), (3.0, 1.0, "I", "B", None,
                                               "d")]
    cfg = {"log_zero_share": 0.2, "primary": []}
    out = compare._means_row([], compare.BY_KEY["clt.ecl"], rows, cfg,
                             "x", False, None, 200, 200, 1000,
                             enough=False)
    assert out["branch"]["II"]["mean"] == pytest.approx(6.0)
    assert out["diff"]["value"] is None and out["diff"]["ci"] is None
    assert out["g"] is None and out["hier"] is None
