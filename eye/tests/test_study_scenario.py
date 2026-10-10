"""Шаг 36, SNO-F-RES-06: «Сравнение ветвей» на синтетической выборке с
известным ответом (`study_scenario.py`).

Восемь участников на ветвь, два ПК, на каждом — обе ветви; в ветви II
ECL ниже и книгу выбирают быстрее. Двое — 🟡, один — 🔴 (с «неправильной»
нагрузкой), у одного взгляд хуже 3°, один — не с эталона. Скрипт обязан
найти направление разницы по главным мерам во всех сценариях, где
данных хватает, не пустить 🔴, взвесить 🟡; на отдельном наборе, где
ветвь совпадает с ПК, — сказать об этом над результатом.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

pytest.importorskip("numpy")
pytest.importorskip("matplotlib")

import study_scenario as ss  # noqa: E402
from sno_eye import study  # noqa: E402
from sno_eye.study import compare, honesty  # noqa: E402

EYE = Path(__file__).resolve().parent.parent
STUDY = EYE / "sno_eye" / "study"


def cfg(**kw):
    c = study.settings()
    c.update(bootstrap=2000, permutations=2000)
    c.update(kw)
    return c


@pytest.fixture(scope="module")
def plan_folder(tmp_path_factory):
    folder = tmp_path_factory.mktemp("набор")
    # По подпапкам ПК — как организатор разложит архивы.
    for p in ss.default_plan():
        ss.write(folder / p.device, p)
    return folder


@pytest.fixture(scope="module")
def run(plan_folder):
    return study.analyse([str(plan_folder)], cfg=cfg())


def row(run, key, comparison=compare.BRANCH):
    return next(r for r in run["result"]["table"]
                if r["comparison"] == comparison and r["measure"].key == key)


def test_sno_f_res_06_finds_planted_direction(run):
    for key in ("clt.ecl", "actions.time_to_choice"):
        r = row(run, key)
        assert r["family"] == "0"
        assert r["result"].delta < -0.5, key
        assert r["result"].ci[1] < 0, key
        assert r["words"] == "в ветви II меньше", key
    # Raw TLX и ICL заложены одинаковыми — «разницы не видно».
    for key in ("clt.raw_tlx", "clt.icl"):
        assert row(run, key)["words"] == "разницы не видно", key
    # Сравнение — внутри ПК: оба слоя сравнимы.
    assert len(row(run, "clt.ecl")["result"].strata) == 2


def test_sno_f_res_06_direction_holds_in_every_scenario(run):
    robust = {item["measure"].key: item for item in run["result"]["robust"]}
    for key in ("clt.ecl", "actions.time_to_choice"):
        item = robust[key]
        assert item["verdict"] == "устойчив", key
        assert [c["scenario"] for c in item["cases"]] == \
            ["S0", "S1", "S2", "S3", "S4", "S5"]
        for case in item["cases"]:
            assert case["result"].enough
            assert case["result"].delta < 0


def test_sno_f_res_06_red_is_in_no_measure_and_yellow_is_weighted(run):
    red = next(e for e in run["entries"] if e["colour"] == honesty.RED)
    yellow = [e for e in run["entries"] if e["colour"] == honesty.YELLOW]
    assert not red["in_stats"]
    assert any("оба пункта" in r for r in red["out"])
    assert len(yellow) == 2 and all(e["weight"] == 0.5 for e in yellow)
    for r in run["result"]["table"]:
        for point in r.get("points") or []:
            assert point[5] != str(red["participant"]), r["measure"].key
            if point[5] in {str(e["participant"]) for e in yellow}:
                assert point[1] == 0.5
    # В S3 красный идёт в счёт — и тянет ECL ветви II вверх.
    robust = {i["measure"].key: i for i in run["result"]["robust"]}
    s0, s3 = (robust["clt.ecl"]["cases"][k]["result"] for k in (0, 3))
    assert s3.describe["II"]["n"] == s0.describe["II"]["n"] + 1
    assert s3.delta > s0.delta


def test_sno_f_res_06_poor_gaze_keeps_test_and_actions(run):
    poor = next(e for e in run["entries"] if e["gaze"]["present"]
                and not e["gaze"]["included"])
    assert poor["in_stats"]
    codes = {p[5] for p in row(run, "clt.ecl")["points"]}
    assert str(poor["participant"]) in codes


def test_sno_f_res_06_not_from_reference_is_out_only_in_s5(run):
    odd = next(e for e in run["entries"] if e["etalon"] != "да")
    assert odd["in_stats"]           # АК10 (а) до ответа
    robust = {i["measure"].key: i for i in run["result"]["robust"]}
    s0, s5 = (robust["clt.ecl"]["cases"][k]["result"] for k in (0, 5))
    assert s5.describe["II"]["n"] == s0.describe["II"]["n"] - 1


def test_sno_f_res_06_confounded_branch_and_pc_is_said(tmp_path):
    ss.make_set(tmp_path, ss.default_plan(confounded=True))
    result = study.analyse([str(tmp_path)], cfg=cfg())
    warnings = result["result"]["warnings"]
    assert any("ветвь совпадает с ПК" in w for w in warnings)
    assert row(result, "clt.ecl")["result"].pooled


def test_sno_f_res_06_one_branch_says_there_is_no_comparison(tmp_path):
    for p in ss.default_plan()[8:]:
        ss.write(tmp_path, p)
    result = study.analyse([str(tmp_path)], cfg=cfg())
    assert any("ветви I в наборе нет" in w
               for w in result["result"]["warnings"])
    r = row(result, "clt.ecl")
    assert r["result"].delta is None
    assert r["words"] == "мало данных — только описание"
    assert r["result"].describe["II"]["n"] == 7


def test_sno_f_res_06_small_n_eff_gives_no_words(tmp_path):
    for p in ss.default_plan()[:2] + ss.default_plan()[8:10]:
        ss.write(tmp_path, p)
    result = study.analyse([str(tmp_path)], cfg=cfg())
    r = row(result, "clt.ecl")
    assert not r["result"].enough
    assert "больше" not in r["words"] and "меньше" not in r["words"]


def test_sno_f_res_06_files_of_the_report(run, tmp_path):
    study.write(run, tmp_path)
    for name in ("index.html", "участники.csv", "походы.csv",
                 "ответы_теста.csv", "сравнение.csv", "устойчивость.csv",
                 "исходные.json"):
        assert (tmp_path / name).is_file(), name
    figures = sorted(p.name for p in (tmp_path / "рисунки").iterdir())
    for n in ("Р1", "Р2", "Р3", "Р4", "Р5", "Р13", "Р14"):
        assert any(f.startswith(n + "_") and f.endswith(".png")
                   for f in figures), n
        assert any(f.startswith(n + "_") and f.endswith(".svg")
                   for f in figures), n
    page = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert "Как читать" in page and "data:image/png;base64," in page
    assert "src='http" not in page and 'src="http' not in page
    sources = json.loads((tmp_path / "исходные.json").read_text("utf-8"))
    assert len(sources["archives"]) == 16
    assert all(len(a["sha256"]) == 64 for a in sources["archives"])
    assert sources["versions"]["numpy"]
    # Excel: «;», UTF-8 с меткой, дробная часть через запятую.
    raw = (tmp_path / "сравнение.csv").read_bytes()
    assert raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    assert ";" in text.splitlines()[0]
    assert re.search(r";-?\d+,\d+;", text)


def test_sno_f_res_06_same_set_gives_same_numbers_to_the_bit(plan_folder,
                                                            tmp_path):
    names = ("сравнение.csv", "устойчивость.csv", "участники.csv",
             "походы.csv", "ответы_теста.csv")
    outs = []
    for k in range(2):
        r = study.analyse([str(plan_folder)], cfg=cfg())
        folder = tmp_path / f"run{k}"
        study.write(r, folder)
        outs.append({n: (folder / n).read_bytes() for n in names})
        outs[-1]["exact"] = repr([
            (x["measure"].key, x["result"].delta, x["result"].ci,
             x["result"].p) for x in r["result"]["table"]])
    assert outs[0] == outs[1]


def test_sno_f_res_06_check_run_takes_everyone_with_weight_one(plan_folder):
    result = study.analyse([str(plan_folder)], cfg=cfg(), no_filter=True)
    assert result["result"]["warnings"][0].startswith("проверочный прогон")
    assert all(e["in_stats"] and e["weight"] == 1.0
               for e in result["entries"])
    red = next(e for e in result["entries"] if e["colour"] == honesty.RED)
    codes = {p[5] for p in row(result, "clt.ecl")["points"]}
    assert str(red["participant"]) in codes


def test_sno_f_res_06_command_line(plan_folder, tmp_path):
    out = tmp_path / "отчёт"
    script = (
        "import sys, json\n"
        "from sno_eye.__main__ import main\n"
        f"code = main(['study', {str(plan_folder)!r}, '--out', "
        f"{str(out)!r}, '--json'])\n"
        "print('CODE', code)\n")
    result = subprocess.run([sys.executable, "-c", script], cwd=EYE,
                            capture_output=True, text=True,
                            encoding="utf-8", timeout=600)
    assert result.returncode == 0, result.stderr
    assert "CODE 0" in result.stdout
    summary = json.loads(result.stdout[:result.stdout.rindex("CODE")])
    assert summary["archives"] == 16
    assert len(summary["in_stats"]) == 15
    words = {r["measure"]: r["words"] for r in summary["primary"]}
    assert words["clt.ecl"] == "в ветви II меньше"
    assert (out / "index.html").is_file()
    empty = subprocess.run(
        [sys.executable, "-c", "from sno_eye.__main__ import main; "
         f"import sys; sys.exit(main(['study', {str(tmp_path / 'нет')!r}]))"],
        cwd=EYE, capture_output=True, text=True, encoding="utf-8")
    assert empty.returncode == 3


def test_sno_f_res_06_check_command_stays_light():
    """`check` по-прежнему не тянет numpy: «Сравнение ветвей» грузит его
    только для себя."""
    script = ("import sys\nfrom sno_eye.__main__ import main\n"
              "main(['check', '--no-csv', 'нет-такого'])\n"
              "print('HEAVY', [m for m in ('numpy', 'matplotlib') "
              "if m in sys.modules])\n")
    result = subprocess.run([sys.executable, "-c", script], cwd=EYE,
                            capture_output=True, text=True, encoding="utf-8")
    assert "HEAVY []" in result.stdout


@pytest.mark.parametrize("name,flag", [
    ("Сравнение ветвей.cmd", "study %*"),
    ("Сравнение ветвей (проверочный).cmd", "study --no-filter %*")])
def test_sno_f_res_06_cmd_shortcuts_go_into_the_zip(name, flag):
    raw = (EYE / name).read_bytes()
    text = raw.decode("ascii")
    assert f'"%~dp0python.exe" -I -m sno_eye {flag}' in text
    assert "\r\n" in text
    sys.path.insert(0, str(EYE / "tool"))
    import build_windows
    assert name in build_windows.COPY
    guide = (EYE / "Инструкция организатора.txt").read_text(
        encoding="utf-8-sig")
    assert "eye\\" + name in guide


def test_sno_f_res_06_every_file_says_where_from():
    """Требование владельца: по коду видно, откуда взята каждая часть и
    какая технология что преобразует. Шапка каждого файла — одного
    вида; строки — не длиннее 80 знаков."""
    for path in sorted(STUDY.glob("*.py")):
        text = path.read_text(encoding="utf-8")
        head = text.split('"""')[1]
        if path.name == "__init__.py":
            assert "Карта скрипта" in head
            for name in ("collect.py", "clt.py", "honesty.py", "actions.py",
                         "table.py", "stats.py", "compare.py", "charts.py",
                         "page.py"):
                assert name in head, name
            continue
        for word in ("Откуда данные", "Технология", "Метод",
                     "Вход → выход"):
            assert word in head, (path.name, word)
        long = [n for n, line in enumerate(text.splitlines(), 1)
                if len(line) > 80]
        assert not long, (path.name, long)


def test_sno_f_res_06_thresholds_section():
    raw = json.loads((EYE / "thresholds.json").read_text(encoding="utf-8"))
    own = raw["study"]
    assert own["yellow_weight"] == 0.5
    assert own["primary"] == ["search.H_t", "clt.ecl",
                              "actions.time_to_choice"]
    assert set(own) == set(study.DEFAULTS)
