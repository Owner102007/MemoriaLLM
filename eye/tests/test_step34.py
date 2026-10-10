"""Шаг 34, SNO-F-RES-03, SNO-ALG-EYE-05: «Разбор записи» — куда
смотрел участник.

Синтетическая запись с известным ответом (`report_scenario.py`):
истинный путь взгляда, шум, постоянный дрейф и задержка камеры,
кадры полки и страницы, нажатия мышью. Разбор обязан найти дрейф,
фиксации, зоны, походы на полку и меры — те, что заложены.
"""

import json
import math
import subprocess
import sys
import time
from pathlib import Path

import pytest

import report_scenario as rs
from sno_eye import layout
from sno_eye import report
from sno_eye.report import archive as arc
from sno_eye.report import idt, measures, timeline as tl, versions, zones
from sno_eye.report.screen import Screen, screen_of

EYE = Path(__file__).resolve().parent.parent
GOLDEN = (EYE.parent / "test" / "goldens" / "layout_frame.json")


@pytest.fixture(scope="module")
def scenario():
    return rs.Scenario().build()


@pytest.fixture(scope="module")
def analysed(tmp_path_factory, scenario):
    folder = tmp_path_factory.mktemp("report")
    path = rs.make(folder, scenario=scenario)
    record = arc.load(path)
    result = report.analyse(record, report.settings(), _limits())
    return record, result


def _limits():
    from sno_eye import record_check as rc
    return rc.thresholds()


def _screen():
    return Screen(**rs.SCREEN)


# --- экран ------------------------------------------------------------

def test_sno_alg_eye_05_screen_degrees_and_pixels():
    """SNO-ALG-EYE-05: градусы ↔ пиксели — как у калибровки; без экрана
    в записи — типичный монитор с пометкой."""
    screen = _screen()
    px = screen.px_for_deg(1.0)
    assert screen.deg_for_px(px) == pytest.approx(1.0)
    # Угол между серединой и точкой на px вправо — тот же градус.
    assert screen.angle_deg((640, 400), (640 + px, 400)) == \
        pytest.approx(1.0, abs=1e-6)
    fallback = screen_of(None, [{"viewport": {"w": 1920, "h": 1080}}])
    assert fallback.known is False and fallback.w == 1920


# --- ход сессии -------------------------------------------------------

def test_sno_alg_rec_06_timeline_from_journal(analysed, scenario):
    """SNO-ALG-REC-06: изучение — от `study.start` до остановки; задержка
    камеры, точность и отлучка — из записи; экраны — по `nav.screen`."""
    record, _ = analysed
    line = tl.build(record)
    assert line.study_start == rs.S
    assert line.study_end == scenario.end
    assert line.latency_ms == rs.LATENCY and line.latency_known
    assert (line.start_deg, line.end_deg) == (1.0, 1.2)
    a, b = scenario.answer["away"]
    assert line.away == [(a, b, "hidden")]
    assert line.screen_at(rs.S) == "testing"
    assert line.screen_at(rs.S + 2000) == "shelf"
    assert [v.target for v in line.visits] == ["Физиология", "Анатомия"]
    assert [v.book for v in line.visits] == ["F2", "A3"]
    assert [v.searches for v in line.visits] == [0, 1]


# --- неявные точки и дрейф -------------------------------------------

def test_sno_alg_eye_05_drift_is_found_from_clicks(analysed):
    """SNO-ALG-EYE-05, шаги 2–3: заложенный дрейф находится по нажатиям
    мышью — с ослаблением `k = n / (n + 5)` и с точностью до шума."""
    record, result = analysed
    cfg = report.settings()
    line = tl.build(record)
    screen = screen_of(record.calibration, record.frames)
    raw = versions.raw_samples(record, line.latency_ms)
    pairs, dropped = versions.implicit_pairs(record, raw, screen, line, cfg)
    assert dropped == 0
    assert len(pairs) >= 80
    drift = versions.build_drift(pairs, line, None, cfg)
    mid = (line.study_start + line.study_end) / 2
    i = min(range(len(drift.centers)),
            key=lambda j: abs(drift.centers[j] - mid))
    n = drift.counts[i]
    want = n / (n + cfg["drift_k"])
    dx, dy = drift.at(drift.centers[i])
    assert dx == pytest.approx(-rs.DRIFT[0] * want, abs=2.0)
    assert dy == pytest.approx(-rs.DRIFT[1] * want, abs=2.0)
    # Остаток неявных точек — «без своей точки»: с поправкой меньше.
    implicit = result["quality"]["implicit"]
    assert implicit["drift_deg"] < implicit["raw_deg"] / 3


def test_sno_alg_eye_05_implicit_points_only_from_mouse_clicks(analysed):
    """SNO-ALG-EYE-05, шаг 2: касание пальцем, нажатие экспериментатора
    и нажатие «не глядя» в пары не идут."""
    record, _ = analysed
    cfg = report.settings()
    line = tl.build(record)
    screen = _screen()
    raw = versions.raw_samples(record, line.latency_ms)
    base, _ = versions.implicit_pairs(record, raw, screen, line, cfg)
    events = list(record.events)
    inputs = dict(record.inputs)
    t = rs.S + 100_000
    extra = {
        900_001: ("touch", "reader"), 900_002: ("mouse", "recording_dot"),
        900_003: ("mouse", "reader"),
    }
    for n, (dev, where) in extra.items():
        inputs[n] = {"n": n, "t": t + n % 10 * 1000, "dev": dev,
                     "kind": "tap", "x": 1200.0 if n == 900_003 else 100.0,
                     "y": 700.0 if n == 900_003 else 28.0, "screen": where}
        events.append({"seq": 0, "t": t, "type": "panel.open",
                       "screen": "reader", "input": n})
    record2 = arc.Record(path=record.path, check=record.check,
                         manifest=record.manifest, events=events,
                         inputs=inputs, frames=record.frames,
                         gaze=record.gaze)
    pairs, dropped = versions.implicit_pairs(record2, raw, screen, line, cfg)
    assert len(pairs) == len(base)
    assert dropped == 1


# --- фиксации ---------------------------------------------------------

def test_sno_alg_eye_05_idt_finds_planted_fixations(analysed, scenario):
    """SNO-ALG-EYE-05, шаг 4: каждая заложенная фиксация чтения найдена —
    начало до кадра (с поправкой на задержку), место до остатка дрейфа и
    шума."""
    _, result = analysed
    fixes = [f for f in result["fixations"] if not f["moving"]]
    starts = [f["start"] for f in fixes]
    import bisect
    missed = 0
    for t, x, y, _ in scenario.answer["reading"][:400]:
        i = bisect.bisect_left(starts, t - 70)
        near = [f for f in fixes[i:i + 3] if abs(f["start"] - t) <= 70]
        if not near:
            missed += 1
            continue
        f = near[0]
        assert math.hypot(f["x"] - x, f["y"] - y) < 12, (t, f)
    assert missed == 0


def test_sno_alg_eye_05_layout_motion_marks_fixation(analysed, scenario):
    """SNO-ALG-EYE-05, шаг 4: фиксация на отрезке движения раскладки
    помечена и в зоны не идёт — её время отдельно."""
    _, result = analysed
    moving = [f for f in result["fixations"] if f["moving"]]
    planted = scenario.answer["moving"]
    assert len(moving) >= len(planted) - 1
    for a, b in planted:
        assert any(a - 70 <= f["start"] <= b for f in moving), (a, b)
    assert result["shares"]["soft"]["moving"] > 0


def test_sno_alg_eye_05_idt_rules_on_made_up_rows():
    """SNO-ALG-EYE-05, шаг 4: короче 100 мс — не фиксация; провал короче
    100 мс склеивается, длиннее — рвёт; граница движения режет."""
    def rows(points):
        return [versions.Sample(t, x, y, x is not None, True)
                for t, x, y in points]

    cfg = report.settings()
    still = rows([(t, 100.0, 100.0) for t in range(0, 66, 33)])
    assert idt.fixations(still, 50, [], cfg) == []
    gap_short = rows([(t, 100.0, 100.0) for t in range(0, 300, 33)]
                     + [(330, None, None), (363, None, None)]
                     + [(t, 100.0, 100.0) for t in range(396, 700, 33)])
    assert len(idt.fixations(gap_short, 50, [], cfg)) == 1
    gap_long = rows([(t, 100.0, 100.0) for t in range(0, 300, 33)]
                    + [(t, None, None) for t in range(330, 500, 33)]
                    + [(t, 100.0, 100.0) for t in range(528, 900, 33)])
    assert len(idt.fixations(gap_long, 50, [], cfg)) == 2
    cut = rows([(t, 100.0, 100.0) for t in range(0, 900, 33)])
    found = idt.fixations(cut, 50, [(400.0, 600.0)], cfg)
    assert len(found) == 3 and [f.moving for f in found] == \
        [False, True, False]


# --- зоны -------------------------------------------------------------

def test_sno_alg_eye_05_zones_sure_and_border_on_shelf(analysed, scenario):
    """SNO-ALG-EYE-05, шаг 5: фиксация в середине книги — уверенно в
    книге и в категории; у края книги — на границе книги, но уверенно в
    категории; между книгами — уверенно в категории."""
    _, result = analysed
    starts = scenario.answer["visits"][0]["starts"]

    def at(name):
        return min(result["fixations"],
                   key=lambda f: abs(f["start"] - starts[name]))

    a2 = at("A2")
    assert (a2["zone"], a2["id"], a2["sure"]) == ("shelf_book", "A2", True)
    assert a2["category"] == "Анатомия" and a2["category_sure"]
    edge = at("A1-edge")
    assert edge["zone"] == "shelf_book" and edge["id"] == "A1"
    assert edge["sure"] is False
    assert "shelf_category:Анатомия" in edge["near"]
    assert edge["category_sure"] is True and edge["book_sure"] is False
    gap = at("gap-F")
    assert (gap["zone"], gap["id"]) == ("shelf_category", "Физиология")
    assert gap["sure"] and gap["book"] is None


def test_sno_alg_eye_05_page_point_in_points(analysed, scenario):
    """SNO-ALG-EYE-05, шаг 5: на странице — номер и точка в пунктах."""
    _, result = analysed
    t, x, y, page = scenario.answer["reading"][0]
    fix = min(result["fixations"], key=lambda f: abs(f["start"] - t))
    assert fix["zone"] == "page" and fix["page"] == page
    assert fix["x_pt"] == pytest.approx((x - rs.PAGE_X) / rs.SCALE, abs=12)
    assert fix["y_pt"] == pytest.approx(y / rs.SCALE, abs=12)
    assert fix["reading"] == "F2" and fix["page_w"] == 595


@pytest.mark.parametrize("case", json.loads(
    GOLDEN.read_text(encoding="utf-8"))["cases"], ids=lambda c: c["name"])
def test_sno_alg_rec_02_report_point_returns_to_golden_symbol(case):
    """SNO-ALG-REC-02: точка на странице через разбор попадает в тот же
    символ, что в эталоне `test/goldens/layout_frame.json`."""
    frame = dict(case["frame"], t=0)
    z = zones.Zones([frame], outside_px=80)
    symbols = case["input"]["symbols"]
    for point in case["points"]:
        expect = point["expect"]
        if expect["zone"] != "page":
            continue
        hit = z.classify(1, point["x"], point["y"], margin_px=0.5)
        assert hit["zone"] == "page" and hit["page"] == expect["page"]
        char = layout.symbol_at(symbols, hit["page"], hit["x_pt"],
                                hit["y_pt"])
        assert char == expect["char"], point


def test_sno_alg_eye_05_outside_and_window_edge():
    """SNO-ALG-EYE-05, шаг 5: за окном дальше 2° — вне экрана; ближе —
    зона у края, всегда на границе."""
    frame = {"t": 0, "viewport": {"w": 1280, "h": 800},
             "regions": rs.shelf_regions()}
    z = zones.Zones([frame], outside_px=80)
    assert z.classify(1, 640, 1000, 40)["bucket"] == "outside"
    near = z.classify(1, 640, 830, 40)
    assert near["bucket"] != "outside" and near["sure"] is False
    assert "outside" in near["near"]


# --- меры -------------------------------------------------------------

def test_sno_f_res_03_time_shares_match_the_plan(analysed, scenario):
    """SNO-F-RES-03: доли времени — вне экрана, лица нет, вне приложения
    — ровно заложенные; строго и мягко отличаются только «на границе»."""
    _, result = analysed
    soft = result["shares"]["soft"]
    strict = result["shares"]["strict"]
    study = scenario.end - rs.S
    for key in ("outside", "no_face", "away"):
        a, b = scenario.answer[key]
        assert soft[key] * study == pytest.approx(b - a, abs=250), key
    assert soft["page"] > 0.75
    assert sum(soft.values()) == pytest.approx(1.0, abs=1e-6)
    assert sum(strict.values()) == pytest.approx(1.0, abs=1e-6)
    assert strict["border"] > 0 and soft["border"] == 0
    for key in soft:
        if key not in ("border",):
            assert strict[key] <= soft[key] + 1e-9, key
    minutes = result["minutes"]
    assert len(minutes) == 10
    for row in minutes:
        total = sum(row[k] for k, _, _ in measures.MINUTE_GROUPS)
        assert total == pytest.approx(1.0, abs=1e-6)


def test_sno_f_res_03_shelf_visits(analysed):
    """SNO-F-RES-03: походы на полку — категории и книги до нажатия,
    время до нужной категории, прямая находка, поиск по названию."""
    _, result = analysed
    first, second = result["visits"]
    assert (first["outcome"], first["book"], first["target"]) == \
        ("book", "F2", "Физиология")
    assert first["path_strict"] == ["Анатомия", "Физиология"]
    assert first["categories_strict"] == 2
    assert first["books_strict"] == 2 and first["books_soft"] == 3
    assert first["direct_strict"] is False
    assert first["first_target_ms_strict"] == pytest.approx(2450, abs=70)
    assert first["duration_ms"] == 5000
    assert second["direct_strict"] is True
    assert second["searches"] == 1 and second["search_after_ms"] == 500
    summary = result["visit_summary"]
    assert summary["visits"] == 2 and summary["opened"] == 2
    assert summary["direct_share_strict"] == 0.5


def test_sno_f_res_03_raw_version_keeps_the_drift(tmp_path, scenario):
    """SNO-ALG-EYE-05, шаг 1: версия «как записано» не трогает точки —
    фиксации лежат со сдвигом дрейфа."""
    path = rs.make(tmp_path, scenario=scenario)
    cfg = dict(report.settings(), version="raw")
    result = report.analyse(arc.load(path), cfg, _limits())
    t, x, y, _ = scenario.answer["reading"][10]
    fix = min(result["fixations"], key=lambda f: abs(f["start"] - t))
    assert fix["x"] - x == pytest.approx(rs.DRIFT[0], abs=6)
    assert fix["y"] - y == pytest.approx(rs.DRIFT[1], abs=6)
    assert fix["x_raw"] == fix["x"]
    assert result["version"] == "raw"


def test_sno_f_res_03_quality(analysed):
    """SNO-F-RES-03: качество — точность, кадры в секунду на полке и на
    странице, задержка, экран из калибровки, включение в анализ."""
    _, result = analysed
    q = result["quality"]
    assert q["mean_deg"] == pytest.approx(1.1)
    assert q["included"] is True and result["included"] is True
    assert q["fps_by_screen"]["shelf"] == pytest.approx(30.3, abs=0.2)
    assert q["fps_by_screen"]["reader"] == pytest.approx(30.3, abs=0.2)
    assert q["latency_ms"] == rs.LATENCY
    assert q["screen_known"] is True
    assert q["idt_deg"] == pytest.approx(1.5)
    assert q["end_anchor"] is True
    assert result["notes"] == []


# --- отказы и записи без взгляда --------------------------------------

def test_sno_f_res_03_damaged_file_is_refused_by_name(tmp_path):
    """SNO-F-RES-03: файл не тот — разбор отказывает и называет его."""
    path = rs.make(tmp_path, tamper={
        "events.jsonl": lambda d: d.replace(b"panel.open", b"panel.shut",
                                            1)})
    with pytest.raises(arc.Refused) as e:
        arc.load(path)
    assert "events.jsonl" in e.value.text
    result = report.run(path, report.settings(), _limits(), None, False)
    assert "events.jsonl" in result["refused"]


def test_sno_f_res_03_record_without_gaze(tmp_path, scenario):
    """SNO-F-RES-03: взгляда нет — причина словами и меры без взгляда."""
    path = rs.make(tmp_path, scenario=scenario, gaze=False)
    result = report.run(path, report.settings(), _limits(), None, False)
    assert result["gaze_used"] is False
    assert result["gaze_reason"] == "самопроверка места не прошла"
    assert [v["book"] for v in result["visits"]] == ["F2", "A3"]
    assert "categories_strict" not in result["visits"][0]
    (tmp_path / "phone").mkdir()
    phone = rs.make(tmp_path / "phone", scenario=scenario, gaze=False,
                    pc=False)
    result = report.run(phone, report.settings(), _limits(), None, False)
    assert result["gaze_reason"] == "запись с телефона — взгляд не пишется"


def test_sno_f_res_03_record_without_layout(tmp_path, scenario):
    """SNO-F-RES-03: запись прежней сборки без кадров раскладки — только
    качество и «на экране / вне экрана»."""
    path = rs.make(tmp_path, scenario=scenario, layout=False)
    result = report.run(path, report.settings(), _limits(), None, False)
    assert result["layout_known"] is False
    assert any("кадров раскладки нет" in n for n in result["notes"])
    soft = result["shares"]["soft"]
    assert soft["page"] == 0 and soft["shelf"] == 0
    assert soft["unknown"] > 0.7 and soft["outside"] > 0
    assert result["quality"]["implicit"]["pairs"] > 0


def test_sno_f_res_03_poor_session_is_excluded(tmp_path, scenario):
    """SNO-F-RES-03, Т19: средняя точность хуже 3° — меры взгляда
    помечены и в общую таблицу не идут; меры действий идут."""
    path = rs.make(tmp_path, scenario=scenario, start_deg=3.5, end_deg=4.0)
    result = report.run(path, report.settings(), _limits(), None, False)
    assert result["included"] is False
    assert any("хуже" in n for n in result["notes"])
    row = {title: fn(result) for title, fn in report.TABLE_COLUMNS}
    assert row["страница мягко"] is None
    assert row["прямых находок строго"] is None
    assert row["походов на полку"] == 2


# --- выход ------------------------------------------------------------

def test_sno_f_res_03_files_and_table(tmp_path, scenario, capsys):
    """SNO-F-RES-03: рядом с архивом — папка разбора с пятью файлами,
    для папки архивов — общая таблица; код выхода 0."""
    rs.make(tmp_path, scenario=scenario)
    rs.make(tmp_path, scenario=scenario, gaze=False,
            name="sno2026_I_11111116_d10708_20261010-1000.zip")
    code = report.main([str(tmp_path)])
    assert code == 0
    folder = tmp_path / (rs.NAME[:-4] + "_eye")
    names = sorted(p.name for p in folder.iterdir())
    assert names == ["fixations.csv", "index.html", "measures.csv",
                     "quality.json", "visits.csv"]
    page = (folder / "index.html").read_text(encoding="utf-8")
    assert "<script" not in page and "http" not in page.split("</title>")[1]
    assert "Схема полки по походам" in page
    table = (tmp_path / report.TABLE_NAME).read_text(encoding="utf-8-sig")
    lines = table.strip().splitlines()
    assert len(lines) == 3 and lines[0].startswith("архив;")
    quality = json.loads((folder / "quality.json").read_text("utf-8"))
    assert quality["gaze"] is True and quality["implicit"]["pairs"] > 80
    out = capsys.readouterr().out
    assert "разобрана" in out and "Общая таблица" in out


def test_sno_f_res_03_exit_codes(tmp_path, capsys):
    """SNO-F-RES-03: неразобранный архив — 2, разбирать нечего — 3."""
    assert report.main([str(tmp_path)]) == 3
    path = rs.make(tmp_path, tamper={
        "events.jsonl": lambda d: d[:-40]})
    assert report.main([str(path)]) == 2
    assert "не разобрана" in capsys.readouterr().out


def test_sno_f_res_03_never_writes_into_app_records(tmp_path, monkeypatch,
                                                    scenario):
    """SNO-F-RES-03: из `Записи` приложения разбор уходит в «Документы»
    — папку в `Записи` приложение приняло бы за запись и упаковало."""
    records = tmp_path / "app" / "sno2026-I" / "Записи"
    records.mkdir(parents=True)
    home = tmp_path / "home"
    (home / "Documents").mkdir(parents=True)
    monkeypatch.setenv("USERPROFILE", str(home))
    path = rs.make(records, scenario=scenario)
    assert report.main([str(path)]) == 0
    assert [p.name for p in records.iterdir()] == [rs.NAME]
    assert (home / "Documents" / report.SAFE_FOLDER /
            (rs.NAME[:-4] + "_eye") / "index.html").exists()


def test_sno_f_res_03_command_line_is_light(tmp_path, scenario):
    """SNO-F-RES-03: `python -m sno_eye report` идёт на стандартной
    библиотеке — numpy, OpenCV и MediaPipe не грузятся."""
    path = rs.make(tmp_path, scenario=scenario)
    script = (
        "import sys, json\n"
        "from sno_eye.__main__ import main\n"
        f"code = main(['report', {str(path)!r}, '--json', '--no-files'])\n"
        "heavy = [m for m in ('numpy', 'cv2', 'mediapipe') if m in "
        "sys.modules]\n"
        "print('CODE', code, 'HEAVY', heavy)\n")
    result = subprocess.run([sys.executable, "-c", script], cwd=EYE,
                            capture_output=True, text=True,
                            encoding="utf-8")
    assert result.returncode == 0, result.stderr
    assert "CODE 0 HEAVY []" in result.stdout
    out = json.loads(result.stdout[:result.stdout.rindex("CODE")])
    assert out[0]["visit_summary"]["visits"] == 2
    assert out[0]["fixation_count"] > 1000


def test_sno_f_res_03_cmd_shortcut_goes_into_the_zip():
    raw = (EYE / "Разбор записи.cmd").read_bytes()
    text = raw.decode("ascii")
    assert '"%~dp0python.exe" -I -m sno_eye report %*' in text
    assert "\r\n" in text
    sys.path.insert(0, str(EYE / "tool"))
    import build_windows
    assert "Разбор записи.cmd" in build_windows.COPY
    guide = (EYE / "Инструкция организатора.txt").read_text(
        encoding="utf-8-sig")
    assert "Разбор записи.cmd" in guide


def test_sno_f_res_03_thresholds_come_from_file():
    raw = json.loads((EYE / "thresholds.json").read_text(encoding="utf-8"))
    assert set(raw["report"]) == set(report.DEFAULTS)
    assert report.settings() == {**report.DEFAULTS, **raw["report"]}


def test_sno_f_res_03_forty_minutes_in_time(tmp_path):
    """SNO-F-RES-03: сорок минут записи разбираются быстро (на ПК
    владельца — не дольше 2 минут); замер — строкой «ЗАМЕР»."""
    long = rs.Scenario(study_ms=2_400_000).build()
    path = rs.make(tmp_path, scenario=long)
    began = time.perf_counter()
    result = report.run(path, report.settings(), _limits(), None, True)
    spent = time.perf_counter() - began
    rows = len(long.gaze_rows())
    print(f"ЗАМЕР SNO-F-RES-03 | разбор 40 минут | {spent:.1f} с | "
          f"кадров взгляда {rows} | фиксаций "
          f"{len(result['fixations'])}")
    assert spent < 60
    assert result["quality"]["fixations"] > 5000


# --- правки по независимой проверке -----------------------------------

def _analyse(path, **cfg):
    return report.analyse(arc.load(path), dict(report.settings(), **cfg),
                          _limits())


def test_sno_alg_eye_05_window_change_before_study_is_harmless(tmp_path):
    """SNO-ALG-EYE-05: смена окна во время калибровки зон не гасит —
    приложение калибрует заново; смена посреди изучения гасит зоны с
    этого мига — и в походах на полку тоже."""
    before = rs.Scenario().build()
    before.event(rs.S - 30_000, "eye.window", "testing", {"changed": True})
    result = _analyse(rs.make(tmp_path, scenario=before))
    assert result["shares"]["soft"]["page"] > 0.75
    assert not any("окно" in n for n in result["notes"])
    (tmp_path / "mid").mkdir()
    mid = rs.Scenario().build()
    second = mid.answer["visits"][1]["start"]
    mid.event(second - 5000, "eye.window", "reader", {"changed": True})
    result = _analyse(rs.make(tmp_path / "mid", scenario=mid))
    first, after = result["visits"]
    assert first["categories_strict"] == 2
    assert after["categories_soft"] == 0 and after["path_soft"] == []
    assert any("окно" in n for n in result["notes"])


def test_sno_alg_eye_05_drift_without_clicks_leans_on_checks(tmp_path):
    """SNO-ALG-EYE-05, шаг 3: нажатий мышью нет — поправка идёт от
    проверки после калибровки (ноль) к проверке в конце, а не стоит
    поправкой конца с первой минуты; знак — против ухода оценки."""
    touch = rs.Scenario(pointer="touch").build()
    record = arc.load(rs.make(tmp_path, scenario=touch))
    cfg = report.settings()
    line = tl.build(record)
    screen = screen_of(record.calibration, record.frames)
    raw = versions.raw_samples(record, line.latency_ms)
    pairs, _ = versions.implicit_pairs(record, raw, screen, line, cfg)
    assert pairs == []
    end = versions.end_correction(line, screen)
    assert end[0] == pytest.approx(-rs.DRIFT[0], abs=0.01)
    assert end[1] == pytest.approx(-rs.DRIFT[1], abs=0.01)
    start = versions.start_correction(line, screen)
    assert start == (0.0, 0.0)
    drift = versions.build_drift(pairs, line, end, cfg, start=start)
    assert drift.at(line.study_start) == (0.0, 0.0)
    assert drift.at(line.study_end) == pytest.approx(end)
    mid = drift.at((line.study_start + line.study_end) / 2)
    assert mid[0] == pytest.approx(end[0] / 2, abs=0.5)


def test_sno_alg_eye_05_page_middle_tap_is_not_a_point(analysed):
    """SNO-ALG-EYE-05, шаг 2: касание середины страницы, которое прячет
    панели (`panel.open {panel: chrome}`), — не неявная точка."""
    record, _ = analysed
    cfg = report.settings()
    line = tl.build(record)
    screen = _screen()
    raw = versions.raw_samples(record, line.latency_ms)
    base, _ = versions.implicit_pairs(record, raw, screen, line, cfg)
    events = [dict(e, data={"panel": "chrome"})
              if e["type"] == "panel.open" else e for e in record.events]
    record2 = arc.Record(path=record.path, check=record.check,
                         manifest=record.manifest, events=events,
                         inputs=record.inputs, frames=record.frames,
                         gaze=record.gaze)
    pairs, _ = versions.implicit_pairs(record2, raw, screen, line, cfg)
    panel = sum(1 for p in base if p.kind == "panel.open")
    assert panel > 50 and len(pairs) == len(base) - panel


def test_sno_alg_eye_05_instant_layout_change_cuts_fixation():
    """SNO-ALG-EYE-05, шаг 4: мгновенная смена раскладки (кадр «в
    движении» и устоявшийся с одним `t`) режет фиксацию."""
    rows = [versions.Sample(t, 100.0, 100.0, True, True)
            for t in range(0, 900, 33)]
    frames = [{"t": 400, "moving": True}, {"t": 400, "moving": False}]
    spans = idt.moving_spans(frames)
    assert spans == []
    whole = idt.fixations(rows, 50, spans, report.settings())
    assert len(whole) == 1
    cut = idt.fixations(rows, 50, spans, report.settings(), [400.0, 400.0])
    assert len(cut) == 2 and cut[0].end <= 433 and cut[1].start >= 400


def test_sno_f_res_03_uncategorised_books_have_a_target(tmp_path):
    """SNO-F-RES-03: книга «Без категории» — нужная категория так и
    названа, а не пуста."""
    scenario = rs.Scenario().build()
    files = scenario.files()
    snapshot = json.loads(files["snapshot_start.json"])
    for book in snapshot["books"]:
        if book["fingerprint"] == "F2":
            book["category"] = None
    files["snapshot_start.json"] = json.dumps(snapshot).encode()
    path = rs.write(tmp_path, files, scenario.manifest(files))
    record = arc.load(path)
    record.frames = []
    line = tl.build(record)
    assert line.categories["F2"] == tl.UNCATEGORISED
    assert line.visits[0].target == tl.UNCATEGORISED


def test_sno_f_res_03_broken_frame_does_not_drop_the_record(tmp_path):
    """SNO-F-RES-03: кадр без чисел окна выброшен, зона без места или
    порядка — выброшена или получает порядок 0; разбор идёт дальше."""
    scenario = rs.Scenario().build()
    first = scenario.frames[1]
    first["regions"][0].pop("z")
    first["regions"].append({"kind": "nav", "rect": "мусор"})
    scenario.frames.append({"t": rs.S + 10, "viewport": {"h": 800},
                            "regions": []})
    result = _analyse(rs.make(tmp_path, scenario=scenario))
    assert result["visits"][0]["categories_strict"] == 2
    record = arc.load(rs.make(tmp_path, scenario=scenario))
    assert all(f["viewport"]["w"] > 0 for f in record.frames)


def test_sno_f_res_03_without_layout_no_zone_numbers(tmp_path, scenario):
    """SNO-F-RES-03: без кадров раскладки у походов нет чисел зон —
    пусто, а не ноль."""
    path = rs.make(tmp_path, scenario=scenario, layout=False)
    result = _analyse(path)
    assert "categories_strict" not in result["visits"][0]
    assert "direct_share_strict" not in result["visit_summary"]


def test_sno_f_res_03_shelf_map_reads_scroll():
    """SNO-F-RES-03: прокрутка полки на схеме — `scroll` сведений зоны
    полки, как пишет приложение."""
    from sno_eye.report import html
    frame = {"regions": [{"kind": "screen", "id": "shelf",
                          "info": {"scroll": 250.0}}]}
    assert html._shelf_offset(frame) == 250.0


def test_sno_alg_eye_05_star_needs_its_own_margin():
    """SNO-ALG-EYE-05, шаг 5: взгляд между двумя звёздами карты ближе
    запаса — звезда не «уверенно», хоть зона карты и одна."""
    frame = {"t": 0, "viewport": {"w": 800, "h": 600}, "regions": [
        {"kind": "galaxy_map", "id": "", "rect": [0, 0, 800, 600], "z": 0,
         "marks": [{"id": "a", "x": 400, "y": 300, "r": 6},
                   {"id": "b", "x": 440, "y": 300, "r": 6}]}]}
    z = zones.Zones([frame], outside_px=80)
    far = z.classify(1, 385, 300, 5)
    assert far["mark"] == "a" and far["mark_sure"] is True
    close = z.classify(1, 418, 300, 10)
    assert close["mark"] == "a" and close["mark_sure"] is False
    assert close["sure"] is True


def test_sno_alg_rec_06_study_end_ignores_post_events(tmp_path, scenario):
    """SNO-ALG-REC-06: без остановки в журнале и без длительности конец
    изучения — последнее событие до остановки, а не после неё."""
    files = scenario.files()
    manifest = scenario.manifest(files)
    record = arc.load(rs.write(tmp_path, files, manifest))
    record.events = [e for e in record.events
                     if e["type"] != "recording.stop"]
    record.manifest = dict(record.manifest, recording={
        k: v for k, v in record.manifest["recording"].items()
        if k != "duration_ms"})
    line = tl.build(record)
    assert line.study_end < scenario.end
