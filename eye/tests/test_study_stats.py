"""Шаг 36, SNO-ALG-RES-05: статистика сравнения ветвей — против второй
реализации на чистом Python и учебных чисел.

Вторая реализация здесь же — без numpy, циклами по определению: δ
Клиффа с весами, свод слоёв, точный перестановочный тест полным
перебором, U Манна — Уитни, поправка Холма, взвешенная медиана,
Спирмен. Модуль `sno_eye.study.stats` обязан сходиться с ней.
"""

from __future__ import annotations

import itertools
import math
import random
import statistics

import pytest

np = pytest.importorskip("numpy")

from sno_eye.study import stats  # noqa: E402


# --- вторая реализация --------------------------------------------------

def py_sign(a, b):
    return (a > b) - (a < b)


def py_cliff(x2, w2, x1, w1):
    num = sum(wi * wj * py_sign(xi, xj)
              for xi, wi in zip(x2, w2) for xj, wj in zip(x1, w1))
    return num / (sum(w2) * sum(w1))


def py_stratified(strata):
    """strata: [(x2, w2, x1, w1)]; λ = W_I · W_II / (W_I + W_II)."""
    num = den = 0.0
    for x2, w2, x1, w1 in strata:
        if not x2 or not x1:
            continue
        W2, W1 = sum(w2), sum(w1)
        lam = W1 * W2 / (W1 + W2)
        num += lam * py_cliff(x2, w2, x1, w1)
        den += lam
    return num / den


def py_mann_whitney_u(x2, x1):
    """U для ветви II: пары «II больше» + ½ ничьих."""
    return sum(1.0 if a > b else 0.5 if a == b else 0.0
               for a in x2 for b in x1)


def py_exact_p(strata):
    """Полный перебор разметок внутри слоёв."""
    observed = abs(py_stratified(strata))
    per = []
    for x2, w2, x1, w1 in strata:
        xs = x2 + x1
        ws = w2 + w1
        k = len(x2)
        options = []
        for chosen in itertools.combinations(range(len(xs)), k):
            a = [xs[i] for i in chosen]
            wa = [ws[i] for i in chosen]
            rest = [i for i in range(len(xs)) if i not in chosen]
            options.append((a, wa, [xs[i] for i in rest],
                            [ws[i] for i in rest]))
        per.append(options)
    hits = total = 0
    for combo in itertools.product(*per):
        total += 1
        if abs(py_stratified(list(combo))) >= observed - 1e-12:
            hits += 1
    return hits / total


def py_holm(ps):
    m = len(ps)
    order = sorted(range(m), key=lambda i: ps[i])
    out = [0.0] * m
    running = 0.0
    for k, i in enumerate(order):
        running = max(running, min(1.0, (m - k) * ps[i]))
        out[i] = running
    return out


def as_strata(strata):
    return [stats.Stratum(f"s{k}", np.array(x2, float), np.array(w2, float),
                          np.array(x1, float), np.array(w1, float))
            for k, (x2, w2, x1, w1) in enumerate(strata)]


# --- описание --------------------------------------------------------

def test_sno_alg_res_05_n_eff_kish_example():
    """Пятеро 🟢 и двое 🟡 при весе 0,5 — n_eff ≈ 6,5, а не 7."""
    w = [1] * 5 + [0.5] * 2
    assert stats.n_eff(w) == pytest.approx(36 / 5.5)
    assert stats.n_eff([1, 1, 1]) == pytest.approx(3)


@pytest.mark.parametrize("seed", range(20))
def test_sno_alg_res_05_weighted_median_equal_weights_is_median(seed):
    rng = random.Random(seed)
    xs = [rng.randint(0, 9) for _ in range(rng.randint(1, 9))]
    assert stats.weighted_median(xs, [1.0] * len(xs)) == \
        pytest.approx(statistics.median(xs))


def test_sno_alg_res_05_weighted_median_crosses_half():
    # Накопленный вес: 0,5 · 1,5 · 2,5 из 2,5 — половину (1,25)
    # переходит на втором значении.
    assert stats.weighted_median([1, 2, 3], [0.5, 1, 1]) == 2
    assert stats.weighted_median([1, 2, 3], [3, 1, 1]) == 1


def test_sno_alg_res_05_weighted_mean_and_sd():
    x, w = [1, 2, 4], [1, 0.5, 0.5]
    mean = (1 + 1 + 2) / 2
    assert stats.weighted_mean(x, w) == pytest.approx(mean)
    sd = math.sqrt((1 * (1 - mean) ** 2 + 0.5 * (2 - mean) ** 2
                    + 0.5 * (4 - mean) ** 2) / 2)
    assert stats.weighted_sd(x, w) == pytest.approx(sd)


# --- δ Клиффа ------------------------------------------------------------

def test_sno_alg_res_05_cliff_matches_mann_whitney_with_ties():
    """При равных весах и одном слое δ = 2U / (n₁n₂) − 1, U — Манн —
    Уитни для ветви II с ничьими по ½."""
    cases = [
        ([3, 5, 5, 7], [1, 5, 2]),
        ([1, 1, 1], [1, 1]),
        ([10, 20, 30, 40, 50], [5, 15, 25, 35, 45, 55]),
        ([2.5, 2.5, 3], [2.5, 3, 3, 4]),
    ]
    for x2, x1 in cases:
        u = py_mann_whitney_u(x2, x1)
        expected = 2 * u / (len(x2) * len(x1)) - 1
        got = stats.cliff(x2, [1] * len(x2), x1, [1] * len(x1))
        assert got == pytest.approx(expected), (x2, x1)


@pytest.mark.parametrize("seed", range(15))
def test_sno_alg_res_05_weighted_strata_match_second_implementation(seed):
    rng = random.Random(seed)
    strata = []
    for _ in range(rng.randint(1, 3)):
        n2, n1 = rng.randint(1, 5), rng.randint(1, 5)
        strata.append(([rng.randint(1, 7) for _ in range(n2)],
                       [rng.choice([1, 0.5]) for _ in range(n2)],
                       [rng.randint(1, 7) for _ in range(n1)],
                       [rng.choice([1, 0.5]) for _ in range(n1)]))
    assert stats.stratified(as_strata(strata)) == \
        pytest.approx(py_stratified(strata))


def test_sno_alg_res_05_stratum_with_one_branch_does_not_count():
    """Слой с одной ветвью не влияет ни на δ, ни на интервал, ни на p."""
    base = [([5, 6, 7], [1, 1, 1], [1, 2, 3], [1, 1, 1])]
    rows = []
    for x2, w2, x1, w1 in base:
        rows += [(x, w, "II", "pc1") for x, w in zip(x2, w2)]
        rows += [(x, w, "I", "pc1") for x, w in zip(x1, w1)]
    extra = rows + [(100.0, 1.0, "II", "phone"), (90.0, 1.0, "II", "phone")]
    kw = dict(seed=7, bootstrap_repeats=500, permutation_repeats=500,
              exact_limit=20_000, n_eff_min=3)
    a = stats.compare(rows, **kw)
    b = stats.compare(extra, **kw)
    assert a.delta == b.delta == 1.0
    assert a.ci == b.ci
    assert a.p == b.p
    assert b.strata == ["pc1"]


def test_sno_alg_res_05_all_equal_gives_zero_and_p_one():
    rows = [(3.0, 1.0, g, "pc") for g in ("I", "II") for _ in range(4)]
    res = stats.compare(rows, seed=1, bootstrap_repeats=200,
                        permutation_repeats=200, exact_limit=20_000,
                        n_eff_min=3)
    assert res.delta == 0
    assert res.p == 1.0


# --- перестановки -------------------------------------------------------

@pytest.mark.parametrize("seed", range(10))
def test_sno_alg_res_05_exact_permutations_match_brute_force(seed):
    rng = random.Random(100 + seed)
    strata = []
    for _ in range(rng.randint(1, 2)):
        n2, n1 = rng.randint(2, 4), rng.randint(2, 4)
        strata.append(([rng.randint(1, 5) for _ in range(n2)],
                       [rng.choice([1, 0.5]) for _ in range(n2)],
                       [rng.randint(1, 5) for _ in range(n1)],
                       [rng.choice([1, 0.5]) for _ in range(n1)]))
    s = as_strata(strata)
    p, exact = stats.permutation_p(s, stats.stratified(s), seed=1,
                                   repeats=1000, exact_limit=20_000)
    assert exact
    assert p == pytest.approx(py_exact_p(strata))


def test_sno_alg_res_05_random_permutations_never_zero():
    """p = (b + 1) / (B + 1): полное разделение ветвей не даёт нуля."""
    s = as_strata([(list(range(20, 32)), [1] * 12, list(range(12)),
                    [1] * 12)])
    assert stats.permutations_total(s) > 20_000
    p, exact = stats.permutation_p(s, stats.stratified(s), seed=3,
                                   repeats=999, exact_limit=20_000)
    assert not exact
    assert p == pytest.approx(1 / 1000)


def test_sno_alg_res_05_random_permutations_agree_with_exact():
    rng = random.Random(5)
    strata = [([rng.randint(1, 7) for _ in range(5)], [1] * 5,
               [rng.randint(1, 7) for _ in range(5)], [1] * 5)]
    s = as_strata(strata)
    exact, _ = stats.permutation_p(s, stats.stratified(s), seed=1,
                                   repeats=1, exact_limit=20_000)
    sampled, is_exact = stats.permutation_p(s, stats.stratified(s), seed=1,
                                            repeats=20_000, exact_limit=1)
    assert not is_exact
    assert sampled == pytest.approx(exact, abs=0.02)


# --- бутстреп -------------------------------------------------------------

def test_sno_alg_res_05_bootstrap_repeats_with_seed_bit_for_bit():
    s = as_strata([([3, 5, 6, 7], [1, 0.5, 1, 1], [1, 2, 4, 5],
                    [1, 1, 0.5, 1])])
    a = stats.bootstrap(s, seed=42, repeats=2000)
    b = stats.bootstrap(s, seed=42, repeats=2000)
    c = stats.bootstrap(s, seed=43, repeats=2000)
    assert a == b
    assert a != c


def test_sno_alg_res_05_bootstrap_draws_equiprobably_weight_goes_to_delta():
    """Участники вытягиваются равновероятно: при весе 0,5 у одного из
    двух его доля в выборках та же, что у другого, — вес не учитывается
    второй раз. Проверка — через разницу средних: интервал должен
    накрывать настоящую взвешенную разницу."""
    x2, w2 = [10.0, 0.0], [1.0, 0.5]
    x1, w1 = [0.0, 0.0], [1.0, 1.0]
    s = as_strata([(x2, w2, x1, w1)])
    _, diff_ci = stats.bootstrap(s, seed=1, repeats=4000)
    true = stats.stratified_diff(s)
    assert true == pytest.approx(10 / 1.5)
    assert diff_ci[0] <= true <= diff_ci[1]


def test_sno_alg_res_05_interval_contains_delta_on_separated_groups():
    s = as_strata([([5, 6, 7, 8], [1] * 4, [1, 2, 3, 4], [1] * 4)])
    ci, _ = stats.bootstrap(s, seed=1, repeats=1000)
    assert ci == (1.0, 1.0)


# --- Холм и прочее -------------------------------------------------------

def test_sno_alg_res_05_holm_known_set():
    ps = [0.01, 0.04, 0.03, 0.005]
    assert stats.holm(ps) == pytest.approx(py_holm(ps))
    # Учебный пример: 0,005·4 = 0,02; 0,01·3 = 0,03; 0,03·2 = 0,06;
    # 0,04·1 → накопленный максимум 0,06.
    assert stats.holm(ps) == pytest.approx([0.03, 0.06, 0.06, 0.02])


def test_sno_alg_res_05_holm_missing_measure_counts_as_one():
    """Недостающая главная мера (`H_t` до шага 37) входит с p = 1:
    поправка двух других — как при трёх мерах, и ничего из названного
    «значимым» не отменится, когда третья появится."""
    adjusted = stats.holm([None, 0.01, 0.02], missing_as_one=True)
    assert adjusted[0] is None
    assert adjusted[1:] == pytest.approx([0.03, 0.04])
    for third in (0.0001, 0.02, 0.5, 1.0):
        real = stats.holm([third, 0.01, 0.02])
        assert real[1] <= adjusted[1] + 1e-12
        assert real[2] <= adjusted[2] + 1e-12
    assert stats.holm([None, 0.01, 0.02]) == pytest.approx(
        [None, 0.02, 0.02])


def test_sno_alg_res_05_effect_words_romano():
    assert stats.effect_words(0.1) == "пренебрежимо"
    assert stats.effect_words(-0.2) == "мал"
    assert stats.effect_words(0.4) == "средний"
    assert stats.effect_words(-0.9) == "большой"


def py_spearman(x, y):
    def ranks(v):
        order = sorted(range(len(v)), key=lambda i: v[i])
        r = [0.0] * len(v)
        i = 0
        while i < len(v):
            j = i
            while j + 1 < len(v) and v[order[j + 1]] == v[order[i]]:
                j += 1
            for k in range(i, j + 1):
                r[order[k]] = (i + j) / 2 + 1
            i = j + 1
        return r
    rx, ry = ranks(x), ranks(y)
    return statistics.correlation(rx, ry)


def test_sno_alg_res_05_spearman_equal_weights_matches_definition():
    x = [1, 3, 2, 5, 4, 4]
    y = [2, 1, 4, 3, 6, 5]
    assert stats.spearman(x, y, [1] * 6) == pytest.approx(py_spearman(x, y))


def test_sno_alg_res_05_few_participants_give_description_only():
    """n_eff в сравнимых слоях меньше 3 — только описание."""
    rows = [(1.0, 1.0, "II", "pc"), (2.0, 1.0, "II", "pc"),
            (5.0, 1.0, "I", "pc"), (6.0, 1.0, "I", "pc"),
            (7.0, 1.0, "I", "pc")]
    res = stats.compare(rows, seed=1, bootstrap_repeats=200,
                        permutation_repeats=200, exact_limit=20_000,
                        n_eff_min=3)
    assert not res.enough
    assert res.delta is None and res.ci is None and res.p is None
    assert res.describe["II"]["n"] == 2


def test_sno_alg_res_05_no_shared_pc_compares_pooled():
    """Ветвь I на одном ПК, II — на другом: сравнение без слоёв, с
    пометкой `pooled`."""
    rows = [(float(x), 1.0, "II", "pc2") for x in (1, 2, 3, 4)] + \
        [(float(x), 1.0, "I", "pc1") for x in (5, 6, 7, 8)]
    res = stats.compare(rows, seed=1, bootstrap_repeats=200,
                        permutation_repeats=200, exact_limit=20_000,
                        n_eff_min=3)
    assert res.pooled
    assert res.delta == -1.0
