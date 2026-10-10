"""Шаг 36, SNO-ALG-RES-01: приём записей, отбор, цвет искренности,
эталон (решения владельца АК, 10.10.2026).

Архивы — синтетические (`study_scenario.py`), в формате приложения.
"""

from __future__ import annotations

import itertools
import json
import zipfile

import pytest

pytest.importorskip("numpy")

import study_scenario as ss  # noqa: E402
from sno_eye import record_check as rc  # noqa: E402
from sno_eye import study  # noqa: E402
from sno_eye.study import collect, compare, honesty  # noqa: E402


def cfg(**kw):
    c = study.settings()
    c.update(bootstrap=200, permutations=200)
    c.update(kw)
    return c


def load(path):
    return collect.load(path, rc.thresholds(), cfg())


# --- цвет --------------------------------------------------------------

@pytest.mark.parametrize("defer,late", list(itertools.product(
    (True, False, None), repeat=2)))
def test_sno_alg_res_01_colour_all_nine_combinations(defer, late):
    """Цвет по всем девяти сочетаниям «провален / не провален / без
    ответа» у двух пунктов шкалы лжи."""
    code, _ = honesty.colour({"lie.defer": defer, "lie.late": late})
    failed = [defer, late].count(True)
    if failed == 2:
        assert code == honesty.RED
    elif failed == 1:
        assert code == honesty.YELLOW       # и при неотвеченном втором
    elif defer is False and late is False:
        assert code == honesty.GREEN
    else:
        assert code == honesty.UNKNOWN


def test_sno_alg_res_01_weights_by_colour():
    w = {honesty.GREEN: 1.0, honesty.YELLOW: 0.5, honesty.UNKNOWN: 0.5,
         honesty.RED: 0.0}
    assert honesty.weight(honesty.YELLOW, w) == 0.5
    assert honesty.weight(honesty.RED, w) == 0.0


@pytest.mark.parametrize("value,rule,expected", [
    (1, {"max": 3}, True), (3, {"max": 3}, True), (4, {"max": 3}, False),
    (5, {"min": 5}, True), (4, {"min": 5}, False),
    (None, {"min": 5}, None), (3, None, None), (3, {}, None),
    (4, {"min": 3, "max": 5}, True), (6, {"min": 3, "max": 5}, False),
])
def test_sno_alg_res_01_flag_rule_is_the_apps(value, rule, expected):
    """«Провален» — ответ попал в отметку пункта (`CltRange.holds`)."""
    assert honesty.flagged(value, rule) is expected


def test_sno_alg_res_01_pilot_like_colours(tmp_path):
    """Ответы пилота: 1 / 7 и 2 / 5 — 🔴, 7 / 1 — 🟢."""
    for colour, lie in (("red", (1, 7)), ("red", (2, 5)),
                        ("green", (7, 1))):
        ss.LIE["probe"] = lie
        p = ss.Person(code="1234567" + str(lie[0]), branch="II",
                      colour="probe", seed=lie[0])
        e = load(ss.write(tmp_path, p))
        flags = {i: e["test"]["lie"][i]["flag"] for i in honesty.LIE_ITEMS}
        assert honesty.colour(flags)[0] == colour, lie
    ss.LIE.pop("probe")


def test_sno_alg_res_01_flag_without_scores_is_recomputed(tmp_path):
    """Без `clt/scores.json` отметка считается заново по ответу и `flag`
    сценария — тем же правилом."""
    p = ss.Person(code="22220001", branch="I", colour="yellow")
    path = ss.write(tmp_path, p)
    stripped = tmp_path / "stripped" / path.name
    stripped.parent.mkdir()
    with zipfile.ZipFile(path) as src, \
            zipfile.ZipFile(stripped, "w", zipfile.ZIP_DEFLATED) as dst:
        manifest = json.loads(src.read("manifest.json"))
        manifest["files"].pop("clt/scores.json")
        dst.writestr("manifest.json", json.dumps(manifest))
        for name in src.namelist():
            if name not in ("manifest.json", "clt/scores.json"):
                dst.writestr(name, src.read(name))
    e = load(stripped)
    assert e["status"] == "ok"
    assert e["test"]["lie"]["lie.defer"]["flag"] is True
    assert e["test"]["lie"]["lie.late"]["flag"] is False


def test_sno_alg_res_01_app_flag_wins_over_recount(tmp_path):
    """Отметки разошлись — главнее отметка приложения, расхождение — в
    оговорки."""
    p = ss.Person(code="22220002", branch="I", colour="green")
    b = ss.Builder(p).build()
    files = b.files()
    scores = json.loads(files["clt/scores.json"])
    scores["checks"]["items"]["lie.defer"]["flag"] = True
    files["clt/scores.json"] = json.dumps(scores).encode()
    path = tmp_path / ss.archive_name(p)
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("manifest.json", json.dumps(b.manifest(files)))
        for name, data in files.items():
            z.writestr(name, data)
    e = load(path)
    assert e["test"]["lie"]["lie.defer"]["flag"] is True
    assert any("разошлись" in n for n in e["test"]["notes"])


def test_sno_alg_res_01_no_test_is_unknown(tmp_path):
    """Теста нет (сборка без пароля) или «Тест пройти нельзя» — ⚪."""
    for test in ("none", "closed"):
        p = ss.Person(code=f"2222100{len(test)}", branch="I", test=test,
                      seed=len(test))
        entries = [load(ss.write(tmp_path / test, p))]
        compare.admit(entries, cfg(), False, None)
        assert entries[0]["colour"] == honesty.UNKNOWN, test
        assert entries[0]["weight"] == 0.5
    assert entries[0]["test"]["state"] == "закрыт организатором"


# --- эталон ------------------------------------------------------------

@pytest.mark.parametrize("etalon,word", [
    ("yes", collect.ETALON_YES), ("no", collect.ETALON_NO),
    ("not_reset", collect.ETALON_NOT_RESET)])
def test_sno_alg_res_01_etalon_by_each_sign(tmp_path, etalon, word):
    p = ss.Person(code="33330001", branch="II", etalon=etalon)
    e = load(ss.write(tmp_path, p))
    assert e["etalon"] == word
    if etalon == "not_reset":
        joined = " ".join(e["etalon_reasons"])
        assert "сброса не было" in joined
        assert "время в книгах" in joined


@pytest.mark.parametrize("policy,expect_in", [
    ("a", (True, True)), ("b", (True, False)), ("c", (False, False))])
def test_sno_alg_res_01_etalon_policy_ak10(tmp_path, policy, expect_in):
    """АК10: (а) — с оговоркой; (б) — «не сброшено» вне, «отличается» с
    оговоркой; (в) — все не с эталона вне."""
    a = ss.Person(code="33331001", branch="I", etalon="no", seed=1)
    b = ss.Person(code="33331002", branch="I", etalon="not_reset", seed=2)
    entries = [load(ss.write(tmp_path, a)), load(ss.write(tmp_path, b))]
    compare.admit(entries, cfg(etalon=policy), False, None)
    assert (entries[0]["in_stats"], entries[1]["in_stats"]) == expect_in


# --- приём ---------------------------------------------------------------

def test_sno_alg_res_01_walks_subfolders(tmp_path):
    ss.write(tmp_path / "ПК 1", ss.Person(code="44440001", branch="I"))
    ss.write(tmp_path / "ПК 2" / "день 2",
             ss.Person(code="44440002", branch="II", seed=2))
    (tmp_path / "заметка.txt").write_text("не архив")
    found = collect.find([str(tmp_path)])
    assert [p.parent.name for p in found] == ["ПК 1", "день 2"]
    # «Проверка записи» в подпапки не заходит — обход здесь свой.
    assert rc.collect([str(tmp_path)]) == []


def test_sno_alg_res_01_series_and_trial_build(tmp_path):
    people = [ss.Person(code="55550001", branch="I", series="sno2026-1"),
              ss.Person(code="55550002", branch="I", series="sno2026-2",
                        seed=2),
              ss.Person(code="55550003", branch="I", series=None, seed=3)]
    paths = [ss.write(tmp_path, p) for p in people]
    entries = [load(p) for p in paths]
    compare.admit(entries, cfg(), False, "sno2026-2")
    by = {e["participant"]: e for e in entries}
    assert not by["55550001"]["in_stats"]
    assert "другая серия" in by["55550001"]["out"][0]
    assert by["55550002"]["in_stats"]
    assert any("проверочная сборка" in r for r in by["55550003"]["out"])


def test_sno_alg_res_01_repeat_by_clock_anchor_and_copy(tmp_path):
    """Повтор — первая по `clock_anchor` завершённая сессия в
    статистике; тот же `recording.id` — копия."""
    first = ss.Person(code="66660001", branch="I", device="zz0001",
                      anchor="2026-10-12T09:00:00.000+03:00", rec_id="A")
    later = ss.Person(code="66660001", branch="I", device="aa0001",
                      anchor="2026-10-12T15:00:00.000+03:00", rec_id="B",
                      seed=2)
    unfinished = ss.Person(code="66660002", branch="I", finished=False,
                           anchor="2026-10-12T08:00:00.000+03:00",
                           rec_id="C", seed=3)
    done = ss.Person(code="66660002", branch="I", device="bb0001",
                     anchor="2026-10-12T10:00:00.000+03:00", rec_id="D",
                     seed=4)
    paths = [ss.write(tmp_path / "a", p) for p in
             (first, later, unfinished, done)]
    copy = tmp_path / "b" / paths[0].name
    copy.parent.mkdir()
    copy.write_bytes(paths[0].read_bytes())
    entries = [load(p) for p in paths + [copy]]
    collect.mark_repeats(entries)
    compare.admit(entries, cfg(), False, None)
    # Имя файла сортируется по коду ПК: «aa0001» раньше «zz0001», но в
    # статистике — первая по времени.
    assert entries[0]["in_stats"]
    assert entries[1]["duplicate"].startswith("повтор")
    assert entries[2]["duplicate"].startswith("повтор")   # не завершена
    assert entries[3]["in_stats"]
    assert entries[4]["duplicate"].startswith("копия")
    # Проверочный прогон берёт повторы, но не копии.
    compare.admit(entries, cfg(), True, None)
    assert entries[1]["in_stats"] and not entries[4]["in_stats"]


def test_sno_alg_res_01_short_study_is_out(tmp_path):
    short = ss.Person(code="77770001", branch="I", study_min=12, trips=3)
    ok = ss.Person(code="77770002", branch="I", study_min=25, seed=2)
    entries = [load(ss.write(tmp_path, short)), load(ss.write(tmp_path, ok))]
    compare.admit(entries, cfg(), False, None)
    assert not entries[0]["in_stats"]
    assert "короче 20 мин" in entries[0]["out"][0]
    assert entries[1]["in_stats"]


def test_sno_alg_res_01_pc_and_phone_strata(tmp_path):
    pc = ss.Person(code="88880001", branch="I", device="d10708",
                   camera="Integrated Camera")
    phone1 = ss.Person(code="88880002", branch="I", phone=True,
                       device="ph0001", seed=2)
    phone2 = ss.Person(code="88880003", branch="II", phone=True,
                       device="ph0002", seed=3)
    entries = [load(ss.write(tmp_path, p)) for p in (pc, phone1, phone2)]
    assert entries[0]["stratum"] == "d10708 · Integrated Camera"
    # Телефоны — один слой, у каждого свой код.
    assert entries[1]["stratum"] == entries[2]["stratum"] == "телефон"
    assert entries[1]["gaze"]["reason"] == "телефон — взгляд не пишется"


def test_sno_alg_res_01_gaze_worse_than_3_degrees(tmp_path):
    p = ss.Person(code="99990001", branch="I", start_deg=2.8, end_deg=6.3)
    e = load(ss.write(tmp_path, p))
    assert e["gaze"]["present"]
    assert not e["gaze"]["included"]
    assert e["gaze"]["mean_deg"] == pytest.approx(4.55)


@pytest.mark.parametrize("share,mode", [
    (0.0, "полкой"), (1 / 3, "полкой"), (0.34, "смешанно"),
    (0.66, "смешанно"), (2 / 3, "картой"), (1.0, "картой")])
def test_sno_alg_res_01_search_mode_edges(share, mode):
    from sno_eye.study import actions
    n = 300
    via = ["galaxy"] * round(share * n) + ["shelf"] * (n - round(share * n))
    assert actions.search_mode(via, "II", (1 / 3, 2 / 3)) == mode
    assert actions.search_mode(via, "I", (1 / 3, 2 / 3)) == "полкой"


def test_sno_alg_res_01_bad_archive_is_named_not_a_crash(tmp_path):
    ss.write(tmp_path, ss.Person(code="10100001", branch="I"))
    (tmp_path / "sno2026_I_10100002_d1_20261012-1000.zip").write_bytes(
        b"PK\x03\x04 broken")
    run = study.analyse([str(tmp_path)], cfg=cfg())
    bad = [e for e in run["entries"] if e["status"] != "ok"]
    assert len(bad) == 1 and "не годен" in bad[0]["reason"]
    assert not bad[0]["in_stats"]
