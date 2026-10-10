"""Шаг 36, SNO-ALG-RES-02: расшифровка теста нагрузки — шкалы по правилу
«Подсчёт», сверка с приложением, ответы строками.

Эталоны шкал — посчитаны руками по правилу приложения
(`lib/sno/clt/results.dart`): группа — идентификатор до последней
точки, обратный пункт — min + max − ответ, маркеры — мимо, среднее.
"""

from __future__ import annotations

import pytest

import study_scenario as ss
from sno_eye.study import clt

ITEMS = clt.scenario_items(ss.SCENARIO)


def answers(values: dict, order=None) -> dict:
    rows = []
    for k, item in enumerate(order or ss.ORDER, start=1):
        if item not in values:
            continue
        meta = ITEMS[item]
        row = {"item": item, "value": values[item], "rt_ms": 1000 * k,
               "order": k, "min": meta["min"], "max": meta["max"]}
        if meta.get("role"):
            row["role"] = meta["role"]
        if meta.get("reverse"):
            row["reverse"] = True
        rows.append(row)
    return {"order": order or ss.ORDER, "checks": ss.CHECKS,
            "answers": rows, "block": None, "complete": True}


FULL = {"tlx.mental": 40, "tlx.physical": 10, "tlx.temporal": 10,
        "tlx.performance": 80, "tlx.effort": 65, "tlx.frustration": 25,
        "lie.defer": 7, "gcl.1": 5, "icl.2": 2, "gcl.2": 7, "ecl.2": 1,
        "ecl.3": 2, "ecl.1": 2, "chk.focus": 2, "icl.1": 5, "orient.1": 7,
        "chk.books": 1, "orient.2": 7, "lie.late": 1, "orient.3": 3}


def test_sno_alg_res_02_scales_match_pilot_numbers():
    """Ответы участника 97956228 пилота: Raw TLX 38,333, ICL 3,5,
    ECL 1,667, GCL 6, ориентация 6,333 — те же числа, что посчитало
    приложение в его `clt/scores.json`."""
    out = clt.scales(answers(FULL), ITEMS)
    assert out["tlx"]["mean"] == pytest.approx(230 / 6)
    assert out["icl"]["mean"] == pytest.approx(3.5)
    assert out["ecl"]["mean"] == pytest.approx(5 / 3)
    assert out["gcl"]["mean"] == pytest.approx(6.0)
    # orient.3 — обратный: 1 + 7 − 3 = 5; (7 + 7 + 5) / 3.
    assert out["orient"]["mean"] == pytest.approx(19 / 3)
    # Маркеры честности в шкалы не входят.
    assert "lie" not in out and "chk" not in out


def test_sno_alg_res_02_half_rule_empties_the_scale():
    """Ответов меньше половины пунктов группы — шкала пустая."""
    partial = {k: v for k, v in FULL.items() if k != "ecl.1"
               and k != "ecl.2"}
    out = clt.scales(answers(partial), ITEMS)
    assert out["ecl"] == {"mean": None, "n": 1, "of": 3}
    # Два из трёх — не меньше половины: шкала есть.
    partial["ecl.2"] = 3
    out = clt.scales(answers(partial), ITEMS)
    assert out["ecl"]["mean"] == pytest.approx(2.5)


def read(values, scores=None, manifest=None, events=()):
    files = {"clt/scenario.json": ss.SCENARIO,
             "clt/sno-clt-main_B_1.json": answers(values)}
    if scores is not None:
        files["clt/scores.json"] = scores
    return clt.read(files, manifest or {"clt": {"final": "complete"}},
                    list(events), 0.001)


def test_sno_alg_res_02_app_numbers_go_in_and_differences_are_named():
    scores = ss.Builder.scores(answers(FULL), "clt/sno-clt-main_B_1.json")
    scores["final"]["scores"]["ecl"]["mean"] = 2.0  # приложение ошиблось
    out = read(FULL, scores)
    # Код главнее: в сравнение идёт число приложения…
    assert out["measures"]["clt.ecl"] == 2.0
    # …а расхождение названо.
    assert any("шкала ecl" in n for n in out["notes"])
    assert out["measures"]["clt.raw_tlx"] == pytest.approx(38.333)
    assert out["measures"]["clt.tlx.performance"] == 80


def test_sno_alg_res_02_rounding_of_the_app_is_not_a_difference():
    scores = ss.Builder.scores(answers(FULL), "clt/sno-clt-main_B_1.json")
    out = read(FULL, scores)
    assert out["notes"] == []


def test_sno_alg_res_02_answers_as_rows_with_text():
    out = read(FULL)
    rows = {r["item"]: r for r in out["answers"]}
    assert len(rows) == 20
    assert rows["orient.3"]["reverse"] is True
    assert rows["lie.defer"]["role"] == "check"
    assert rows["ecl.1"]["section"] == "О задании"
    assert rows["tlx.mental"]["text"]
    assert out["rt_median_ms"] == pytest.approx(10_500)


def test_sno_alg_res_02_old_build_with_blocks_takes_final_part():
    """Записи прежних сборок с `block`: шкалы — итоговой части."""
    block = answers({"tlx.mental": 100})
    block["block"] = 1
    files = {"clt/scenario.json": ss.SCENARIO,
             "clt/sno-clt-main_A_1.json": block,
             "clt/sno-clt-main_B_2.json": answers(FULL)}
    out = clt.read(files, {"clt": {"final": "complete"}}, [], 0.001)
    assert out["measures"]["clt.tlx.mental"] == 40


def test_sno_alg_res_02_closed_by_organizer():
    events = [{"type": "session.finish", "t": 1,
               "data": {"without_test": True}}]
    out = read({"tlx.mental": 40}, manifest={"clt": {"final": "none"}},
               events=events)
    assert out["state"] == clt.CLOSED
    assert out["lie"]["lie.defer"]["flag"] is None
    assert out["measures"]["clt.raw_tlx"] is None   # 1 из 6 — пусто


def test_sno_alg_res_02_no_test_in_build():
    out = clt.read({}, {}, [], 0.001)
    assert out["state"] == clt.NO_TEST
    assert out["measures"] == {}
