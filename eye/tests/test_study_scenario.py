"""Шаги 36 и 37, SNO-F-RES-06: «Сравнение ветвей» на синтетической
выборке с известным ответом (`study_scenario.py`).

Восемь участников на ветвь, два ПК, на каждом — обе ветви; в ветви II
ECL ниже и книгу выбирают быстрее. Двое — 🟡, один — 🔴 (с «неправильной»
нагрузкой), у одного взгляд хуже 3°, один — не с эталона. Скрипт обязан
найти направление разницы по главным мерам во всех сценариях, где
данных хватает, не пустить 🔴, взвесить 🟡; на отдельном наборе, где
ветвь совпадает с ПК, — сказать об этом над результатом.

Шаг 37: ветвь I ищет книгу на полке зигзагом, ветвь II — на карте по
порядку. Скрипт обязан найти, что в ветви II взгляд в поиске
упорядоченнее (SNO-ALG-RES-03), а в чтении разницы нет, не дать мер
взгляда сессии хуже 3° и мер беспорядочности шумной камере, нарисовать
Р6–Р12 и повести отчёт к своим файлам (BUG-68).
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
    for n in ("Р6", "Р7", "Р8", "Р9", "Р10", "Р11", "Р12"):
        assert any(f.startswith(n + "_") and f.endswith(".png")
                   for f in figures), n
    page = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert "Как читать" in page and "data:image/png;base64," in page
    assert "следующий шаг" not in page and "шаг 37" not in page
    assert "src='http" not in page and 'src="http' not in page
    sources = json.loads((tmp_path / "исходные.json").read_text("utf-8"))
    assert len(sources["archives"]) == 16
    # `k` и случайный уровень по фазам, μ и σ K — по ним прогон
    # повторяется.
    search = sources["gaze"]["phases"]["search"]
    assert search["k"] >= 40 and search["random"]["H_t"] > 0
    assert set(search["K"]) == {"mu_d", "sd_d", "mu_a", "sd_a"}
    assert sources["script"] == study.SCRIPT_VERSION
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
    ("Сравнение ветвей.cmd", "study --open %*"),
    ("Сравнение ветвей (проверочный).cmd",
     "study --no-filter --open %*")])
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
                         "gaze.py", "disorder.py", "average.py",
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


# --- шаг 37: меры взгляда -----------------------------------------------

def gaze_row(run, key):
    return row(run, key)


@pytest.mark.parametrize("key,sign", [
    ("search.H_t", -1), ("search.path", -1), ("search.returns", -1),
    ("search.K", 1), ("search.straight", 1), ("search.nni_dev", 1),
    ("all.H_t", -1)])
def test_sno_alg_res_03_finds_planted_order_of_search(run, key, sign):
    """В ветви II взгляд в поиске заложен упорядоченнее: энтропия,
    путь и возвраты меньше, K, прямота и кучность больше. Направление —
    по δ и интервалу: слова у разведочных мер решает ещё и поправка
    Холма на всю семью, а при семи участниках на ветвь её выдерживают
    не все меры."""
    r = gaze_row(run, key)
    res = r["result"]
    assert res.enough, key
    assert res.delta * sign > 0.5, key
    lo, hi = res.ci
    assert (lo > 0) if sign > 0 else (hi < 0), key
    if r["family"] == "0":
        assert r["words"] == "в ветви II меньше", key


def test_sno_alg_res_03_h_t_is_primary_and_stable(run):
    r = gaze_row(run, "search.H_t")
    assert r["family"] == "0" and not r["pending"]
    robust = {i["measure"].key: i for i in run["result"]["robust"]}
    item = robust["search.H_t"]
    assert item["verdict"] == "устойчив"
    assert all(c["result"].delta < 0 for c in item["cases"])


def test_sno_alg_res_03_reading_is_the_same_in_both_branches(run):
    assert gaze_row(run, "reading.H_t")["words"] == "разницы не видно"


def test_sno_alg_res_03_who_gets_gaze_measures(run):
    by = {e["participant"]: e for e in run["entries"]}
    plan = ss.default_plan()
    poor, noisy, red = plan[3], plan[5], plan[10]
    # Хуже 3°: тест и действия на месте, мер взгляда в сравнении нет.
    codes = {p[5] for p in gaze_row(run, "search.H_t")["points"]}
    assert poor.code not in codes
    assert poor.code in {p[5] for p in row(run, "clt.ecl")["points"]}
    # Шумная камера: доли зон есть, мер беспорядочности нет.
    e = by[noisy.code]
    assert e["disorder_gate"].startswith("фиксации дробятся")
    assert "search.H_t" not in e["gaze_measures"]
    assert noisy.code in {p[5] for p in
                          gaze_row(run, "share.reading")["points"]}
    # 🔴 — ни в одной мере взгляда.
    for key in ("search.H_t", "share.reading", "learn.path_slope"):
        assert red.code not in {p[5] for p in gaze_row(run, key)["points"]}


def test_sno_alg_res_03_check_run_lifts_the_noise_gate(plan_folder):
    result = study.analyse([str(plan_folder)], cfg=cfg(), no_filter=True)
    noisy = ss.default_plan()[5]
    e = next(x for x in result["entries"]
             if x["participant"] == noisy.code)
    assert e["disorder_gate"] and e["disorder_live"]
    assert noisy.code in {p[5] for p in
                          row(result, "search.H_t")["points"]}


def test_sno_alg_res_04_average_of_the_branches(run):
    avg = run["result"]["average"]
    # Ветвь II искала на карте — тепловая карта одна, на её звёздах.
    assert len(avg["heat"]) == 1
    heat = avg["heat"][0]
    assert set(heat["branches"]) == {"II"} and len(heat["points"]) == 12
    # Схема полки: у ветви I время поиска на полке, у ветви II — нет.
    total = {b: sum(x["share"] or 0 for r in avg["shelf"][b]["rows"]
                    for x in r["books"]) for b in ("I", "II")}
    assert total["I"] > 0.2 and total["II"] == 0
    for b in ("I", "II"):
        groups = avg["shares"][b]["groups"]
        assert sum(groups.values()) == pytest.approx(1.0)
        assert avg["curve"][b]["choice"]
    m = avg["matrix"]["II"]
    assert m["n"] == 7 and len(m["p"]) == 5


def test_bug_68_report_leads_to_its_files(run, tmp_path):
    """BUG-68: из отчёта открывается каждый его файл, и каждый такой
    файл лежит в папке; консоль называет папку."""
    from urllib.parse import unquote
    study.write(run, tmp_path)
    page = (tmp_path / "index.html").read_text(encoding="utf-8")
    links = [unquote(h) for h in re.findall(r"href='([^']+)'", page)]
    for name in ("участники.csv", "походы.csv", "ответы_теста.csv",
                 "сравнение.csv", "устойчивость.csv", "исходные.json",
                 "рисунки/"):
        assert name in links, name
    for link in links:
        assert (tmp_path / link).exists(), link
    assert any(link.startswith("рисунки/Р6_") for link in links)
    lines = study.describe(run, tmp_path)
    assert f"Папка отчёта: {tmp_path}" in lines
    assert any(line.strip().startswith("участники.csv") for line in lines)
    assert str(tmp_path) in page


def test_bug_68_open_flag_opens_the_folder(monkeypatch, tmp_path):
    opened = []
    monkeypatch.setattr(study.os, "startfile", lambda p: opened.append(p),
                        raising=False)
    assert study.open_folder(tmp_path)
    assert opened == [str(tmp_path)]
    monkeypatch.delattr(study.os, "startfile", raising=False)
    assert not study.open_folder(tmp_path)


# --- шаг 38: портрет участника -----------------------------------------

def entry(run, person):
    return next(e for e in run["entries"] if e["participant"] == person.code)


def test_sno_alg_res_06_planted_ordering_of_search_shows_in_slope(run):
    """Участник `learn` (ветвь I): поиск от похода к походу всё чаще по
    порядку — наклон энтропии поиска отрицательный и заметно ниже, чем
    у ищущих зигзагом всю сессию."""
    plan = ss.default_plan()
    learner = entry(run, plan[0])["portrait_measures"]
    assert learner["portrait.search_slope"] < -0.1
    others = [entry(run, p)["portrait_measures"].get(
        "portrait.search_slope") for p in plan[1:8]]
    others = [v for v in others if v is not None]
    assert len(others) >= 5
    assert all(learner["portrait.search_slope"] < v for v in others)
    # Окна П1: в первых походах энтропия выше, чем в последних.
    wins = entry(run, plan[0])["gaze_data"]["portrait"]["entropy"][
        "search"]["windows"]
    assert wins[0]["h"] > wins[-1]["h"]


def test_sno_alg_res_08_planted_lookbacks_in_the_set(run):
    """Взгляд назад заложен на 27-й секунде каждого чтения у двоих — он
    найден там и больше нигде; без закладки — ни одного."""
    plan = ss.default_plan()
    for p in plan:
        e = entry(run, p)
        look = e["gaze_data"]["portrait"]["lookback"]
        if look.get("reason"):
            assert p is plan[5]          # шумная камера
            continue
        if not p.lookback:
            assert look["count"] == 0, p.code
            continue
        lo = e["study_start"]
        opens = [lo + s * 1000 for s in e["gaze_data"]["portrait"]["opens"]]
        assert look["count"] >= len(opens) - 1
        for ep in look["episodes"]:
            near = min(abs(ep["t0"] - (o + 27_000)) for o in opens)
            assert near <= 1000, (p.code, ep["t0"])


def test_sno_alg_res_08_planted_page_back_and_misflip(run):
    plan = ss.default_plan()
    for p in plan:
        nav = entry(run, p)["reading_nav"]
        if p.page_back:
            assert nav["backs"] == 1 and nav["misflips"] == 1
        else:
            assert nav["backs"] == 0 and nav["misflips"] == 0
    assert entry(run, plan[2])["portrait_measures"][
        "portrait.page_backs_per_min"] > 0


def test_sno_f_res_07_family_d_in_the_comparison(run):
    keys = [m.key for m in compare.MEASURES if m.family == "Д"]
    assert "portrait.search_slope" in keys and \
        "portrait.page_backs_per_min" in keys
    plan = ss.default_plan()
    red, noisy = plan[10], plan[5]
    r = row(run, "portrait.page_backs_per_min")
    codes = {p[5] for p in r["points"]}
    # По журналу — у всех в статистике, и у шумной камеры; 🔴 — нет.
    assert noisy.code in codes and red.code not in codes
    # Энтропия по ходу и заходы — без шумной сессии.
    assert noisy.code not in {p[5] for p in row(
        run, "portrait.ui_trans_per_min")["points"]}


def test_sno_f_res_07_portraits_written_for_everyone(run, tmp_path):
    """Страница на каждого участника, ссылка из отчёта; «не для
    выводов» — у 🔴, у взгляда хуже 3° и у шумной камеры; рисунки П1–П4
    и таблицы участника лежат рядом."""
    from urllib.parse import unquote
    study.write(run, tmp_path)
    plan = ss.default_plan()
    page = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert "8. Портреты участников" in page
    links = [unquote(h) for h in re.findall(r"href='([^']+)'", page)]
    for p in plan:
        assert f"Портреты/{p.code}.html" in links, p.code
        own = (tmp_path / "Портреты" / f"{p.code}.html").read_text(
            encoding="utf-8")
        assert "../index.html" in own
        for name in ("П1_лента_сессии.png", "П2_переходы.png",
                     "П4_чтение_назад.png", "окна_энтропии.csv",
                     "заходы.csv", "взгляд_назад.csv"):
            assert (tmp_path / "Портреты" / p.code / name).exists(), name
        marked = "Не для выводов" in own
        assert marked == (p in (plan[3], plan[5], plan[10])), p.code
    assert "шумно" in (tmp_path / "Портреты" / f"{plan[5].code}.html") \
        .read_text(encoding="utf-8")
    for name in ("Р16_энтропия_по_ходу.png", "Р17_ленты_участников.png"):
        assert (tmp_path / "рисунки" / name).exists()
    for link in links:
        assert (tmp_path / link).exists(), link
    head = (tmp_path / "участники.csv").read_text(encoding="utf-8-sig") \
        .splitlines()[0]
    assert "Энтропия поиска по ходу: наклон" in head
    assert "портрет: промахов листания" in head
    # Числа справочных столбцов на месте, а не пустые.
    cols = head.split(";")
    lines = (tmp_path / "участники.csv").read_text(encoding="utf-8-sig") \
        .splitlines()[1:]
    misflips = [ln.split(";")[cols.index("портрет: промахов листания")]
                for ln in lines]
    assert "1" in misflips and "0" in misflips


def test_sno_f_res_07_phone_portrait_says_why_no_gaze(tmp_path):
    """Запись с телефона: портрет говорит «взгляда нет» и показывает
    возвраты на страницу назад по журналу."""
    phone = ss.Person(code="20010007", branch="I", phone=True, gaze=False,
                      device="ph0001", via="shelf", seed=5, trips=6,
                      page_back=True)
    pc = ss.Person(code="20020004", branch="II", seed=6, trips=6)
    for p in (phone, pc):
        ss.write(tmp_path / "архивы", p)
    result = study.analyse([str(tmp_path / "архивы")], cfg=cfg(),
                           no_filter=True)
    study.write(result, tmp_path / "отчёт")
    own = (tmp_path / "отчёт" / "Портреты" / f"{phone.code}.html") \
        .read_text(encoding="utf-8")
    assert "Взгляда нет" in own
    assert (tmp_path / "отчёт" / "Портреты" / phone.code /
            "П4_чтение_назад.png").exists()
    e = next(x for x in result["entries"] if x["participant"] == phone.code)
    assert e["reading_nav"]["backs"] == 1
    assert e["portrait_measures"]["portrait.page_backs_per_min"] > 0


def test_sno_f_res_07_no_portraits_flag(run, tmp_path):
    study.write(run, tmp_path, portraits=False)
    assert not (tmp_path / "Портреты").exists()
    page = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert "--no-portraits" in page


def test_sno_alg_res_06_r16_curves_and_test_ran(run):
    ent = run["result"]["average"]["entropy"]
    reading = ent["reading"]
    assert reading["curves"]["I"] and reading["curves"]["II"]
    # Чтение у ветвей одно — кластера с p < 0,05 нет.
    assert not any(c["p"] < 0.05 for c in reading["test"]["clusters"])
    # Шумная камера в кривые не идёт.
    noisy = ss.default_plan()[5].code
    assert noisy not in {p["code"] for p in reading["people"]}


def test_sno_alg_res_07_observed_and_expected_in_the_same_trips(run):
    """«Было» и «ожидалось без памяти» — в одних и тех же походах; нет
    походов, где видно от трёх зон, — оба пустые, а не 0."""
    for e in run["entries"]:
        d = ((e.get("gaze_data") or {}).get("portrait") or {}).get("dwell")
        if not d or d.get("reason"):
            continue
        for key in ("cat", "book"):
            own = d[key]
            if own["trips_vs"] == 0:
                assert own["expected"] is None and own["observed_vs"] is None
                assert own["ratio"] is None
            else:
                assert own["observed_vs"] <= own["revisits"]


def test_bug_69_branches_of_one_pc_are_compared_within_it(run):
    """У ветвей одного ПК разные коды устройства, путь камеры один:
    слоёв ПК два, на каждом обе ветви, сравнение — внутри ПК."""
    strata = {e["stratum"] for e in run["entries"]
              if e.get("platform") == "ПК"}
    assert strata == {"d10708 + e3a911 · Integrated Camera",
                      "a51c02 + b62f17 · Chicony USB2.0"}
    assert not any("ветвь совпадает с ПК" in w
                   for w in run["result"]["warnings"])
    assert not row(run, "clt.ecl")["result"].pooled
