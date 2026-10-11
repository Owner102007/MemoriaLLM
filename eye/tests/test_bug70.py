"""BUG-70: меры беспорядочности пусты почти у всех записей с веб-камеры
(шаг 39, решение владельца АМ1 (а) от 11.10.2026).

Сессию пускали в меры беспорядочности по прецизионности калибровки:
три прецизионности не больше общего порога фиксаций 4,5°. У веб-камер
10–11.10.2026 прецизионность 1,3–2,5°, и из пяти записей проходила одна.
Теперь перед поиском фиксаций для мер и портрета — медиана трёх кадров,
а пропуск решает доля времени в фиксациях на данных самой сессии.

Сначала — воспроизведение: синтетическая выборка, у которой шум кадра
как у веб-камеры (около 1° по оси, прецизионность калибровки 2,2°).
"""

from __future__ import annotations

from pathlib import Path

import pytest

pytest.importorskip("numpy")
pytest.importorskip("matplotlib")

import study_scenario as ss  # noqa: E402
from sno_eye import study  # noqa: E402
from sno_eye.study import compare  # noqa: E402

# Шум кадра веб-камеры: 1° по оси на экране синтетики (340 мм на 1280
# точек, 60 см до глаз — 39,4 точки на градус).
WEBCAM_NOISE_PX = 39.4
WEBCAM_PRECISION_DEG = 2.2


def cfg(**kw):
    c = study.settings()
    c.update(bootstrap=2000, permutations=2000)
    c.update(kw)
    return c


def webcam_plan() -> list[ss.Person]:
    """Выборка шага 37 с шумом веб-камеры у всех; «шумная камера»
    (plan[5]) — втрое шумнее."""
    plan = ss.default_plan()
    for p in plan:
        p.noise = WEBCAM_NOISE_PX
        p.precision_deg = WEBCAM_PRECISION_DEG
    plan[5].noise = 3 * WEBCAM_NOISE_PX
    plan[5].precision_deg = 3 * WEBCAM_PRECISION_DEG
    return plan


@pytest.fixture(scope="module")
def webcam_run(tmp_path_factory):
    folder = tmp_path_factory.mktemp("веб-камера")
    for p in webcam_plan():
        ss.write(folder / p.device, p)
    return study.analyse([str(folder)], cfg=cfg())


def test_bug_70_webcam_sessions_get_disorder_measures(webcam_run):
    """Записи с шумом веб-камеры получают меры беспорядочности, и
    заложенное направление находится: в ветви II поиск упорядоченнее."""
    plan = webcam_plan()
    by = {e["participant"]: e for e in webcam_run["entries"]}
    live = [p for p in plan if by[p.code].get("disorder_live")
            and by[p.code]["in_stats"] and by[p.code]["gaze"]["included"]]
    # В статистике 15 (🔴 вне неё), взгляд хуже 3° — вне мер взгляда;
    # шумная камера — вне мер беспорядочности. Остальные 13 — с мерами.
    assert len(live) == 13, [by[p.code].get("disorder_gate") for p in plan]
    noisy = by[plan[5].code]
    assert noisy["disorder_gate"].startswith("фиксации дробятся")
    r = next(r for r in webcam_run["result"]["table"]
             if r["comparison"] == compare.BRANCH
             and r["measure"].key == "search.H_t")
    res = r["result"]
    assert res.enough
    assert res.delta < -0.5 and res.ci[1] < 0
    assert r["words"] == "в ветви II меньше"


# --- сглаживание -------------------------------------------------------------

from sno_eye.report import idt  # noqa: E402
from sno_eye.report.screen import Screen  # noqa: E402
from sno_eye.report.versions import Sample  # noqa: E402
from sno_eye.study import disorder, noise  # noqa: E402

import noise_ladder as nl  # noqa: E402

SCREEN = Screen(1280.0, 800.0, 340.0, 212.5, 600.0)


def series(xs, *, period=33.0, seg=None, bad=(), t0=0.0, gaps=(), y=100.0):
    """Кадры по иксам [xs]; игрек — [y]. [bad] — номера негодных кадров,
    [seg] — сегменты по номерам, [gaps] — номера кадров, перед которыми
    просвет в два кадра."""
    out = []
    t = t0
    for i, x in enumerate(xs):
        if i in gaps:
            t += 2 * period
        ok = i not in bad
        out.append(Sample(t, float(x) if ok else None,
                          y if ok else None, ok, True,
                          seg[i] if seg else 0))
        t += period
    return out


def test_bug_70_median_of_three_inside_a_run():
    rows = series([10, 40, 12, 11, 13, 50, 12])
    out, used, fps = noise.smooth(rows, 3, 25)
    assert used == 3 and fps == pytest.approx(1000 / 33)
    assert [s.x for s in out] == [10, 12, 12, 12, 13, 13, 12]
    # Длина, порядок и время — те же: номера кадров фиксаций годятся
    # для обоих рядов.
    assert [s.t for s in out] == [s.t for s in rows]
    assert all(a.ok == b.ok and a.seg == b.seg for a, b in zip(out, rows))
    # Исходный ряд не тронут.
    assert rows[1].x == 40


def test_bug_70_no_smoothing_across_a_break():
    # Негодный кадр: соседи не берут медиану через него.
    rows = series([10, 40, 99, 70, 12], bad={2})
    out, _, _ = noise.smooth(rows, 3, 25)
    assert [s.x for s in out] == [10, 40, None, 70, 12]
    # Смена сегмента — разрыв.
    rows = series([10, 40, 12, 90, 11, 13], seg=[0, 0, 0, 1, 1, 1])
    out, _, _ = noise.smooth(rows, 3, 25)
    assert [s.x for s in out] == [10, 12, 12, 90, 13, 13]
    # Просвет дольше полутора кадров — разрыв.
    rows = series([10, 40, 12, 90, 11, 13], gaps={3})
    out, _, _ = noise.smooth(rows, 3, 25)
    assert [s.x for s in out] == [10, 12, 12, 90, 13, 13]


def test_bug_70_saccade_stays_a_step():
    """Скачок на 5° — ступень: медиана его не размывает и не сдвигает."""
    jump = SCREEN.px_for_deg(5.0)
    rows = series([0.0] * 10 + [jump] * 10)
    out, _, _ = noise.smooth(rows, 3, 25)
    assert [s.x for s in out] == [s.x for s in rows]
    # С одиночным выбросом на краю ступени — сдвиг не больше кадра.
    rows = series([0.0] * 10 + [jump, 0.0] + [jump] * 8)
    out, _, _ = noise.smooth(rows, 3, 25)
    edge = next(i for i, s in enumerate(out) if s.x == jump)
    assert edge in (10, 11)
    assert all(s.x == 0.0 for s in out[:edge])
    assert all(s.x == jump for s in out[edge:])


def test_bug_70_low_frame_rate_is_not_smoothed():
    """10 кадров в секунду: три кадра — 0,3 с, длиннее фиксации."""
    rows = series([10, 40, 12, 11, 13], period=100.0)
    out, used, fps = noise.smooth(rows, 3, 25)
    assert used == 1 and fps == pytest.approx(10.0)
    assert [s.x for s in out] == [s.x for s in rows]
    # Медиана одного кадра — без сглаживания при любой частоте.
    out, used, _ = noise.smooth(series([10, 40, 12]), 1, 25)
    assert used == 1 and [s.x for s in out] == [10, 40, 12]


def test_bug_70_clean_path_keeps_its_fixations():
    """Без шума сглаживание фиксаций не меняет: те же, с точностью до
    кадра."""
    rows = nl.samples(nl.path(1, fixations=200), 0.0, 1)
    cfg = study.report_settings()
    px = SCREEN.px_for_deg(4.5)
    raw = idt.fixations(rows, px, [], cfg, [])
    out, _, _ = noise.smooth(rows, 3, 25)
    smooth = idt.fixations(out, px, [], cfg, [])
    assert len(raw) == len(smooth)
    for a, b in zip(raw, smooth):
        assert abs(a.start - b.start) <= 33.0 and abs(a.end - b.end) <= 33.0


# --- доля в фиксациях и шум от кадра к кадру ---------------------------------

def fixation(first, last, *, moving=False):
    return idt.Fixation(start=first * 33.0, end=(last + 1) * 33.0, x=0.0,
                        y=100.0, first=first, last=last, moving=moving,
                        members=list(range(first, last + 1)))


def test_bug_70_share_of_time_in_fixations():
    rows = series([100.0] * 20)
    share = noise.fix_share(rows, [fixation(0, 9)], 0.0, 20 * 33.0, [],
                            lambda t: False, 100.0, SCREEN, 75.0)
    assert share == pytest.approx(0.5)
    # Фиксация на отрезке движения — не в счёт; сам отрезок — ни в
    # числитель, ни в знаменатель.
    spans = [(10 * 33.0, 15 * 33.0)]
    share = noise.fix_share(rows, [fixation(0, 9), fixation(10, 14,
                                                            moving=True)],
                            0.0, 20 * 33.0, spans, lambda t: False, 100.0,
                            SCREEN, 75.0)
    assert share == pytest.approx(10 / 15)
    # Отлучка — тоже.
    share = noise.fix_share(rows, [fixation(0, 9)], 0.0, 20 * 33.0, [],
                            lambda t: t >= 10 * 33.0, 100.0, SCREEN, 75.0)
    assert share == pytest.approx(1.0)
    # Вне изучения — не в счёт.
    share = noise.fix_share(rows, [fixation(0, 9)], 5 * 33.0, 20 * 33.0, [],
                            lambda t: False, 100.0, SCREEN, 75.0)
    assert share == pytest.approx(5 / 15)


def test_bug_70_share_counts_only_gaze_on_screen():
    rows = series([100.0] * 10 + [-500.0] * 10)
    share = noise.fix_share(rows, [fixation(0, 4)], 0.0, 20 * 33.0, [],
                            lambda t: False, 100.0, SCREEN, 75.0)
    assert share == pytest.approx(0.5)
    # Годных кадров на экране нет — доли нет.
    rows = series([-500.0] * 10)
    assert noise.fix_share(rows, [], 0.0, 10 * 33.0, [], lambda t: False,
                           100.0, SCREEN, 75.0) is None


def test_bug_70_rms_sample_to_sample():
    """RMS sample-to-sample: корень из среднего квадрата угла между
    соседними кадрами одной фиксации."""
    one = SCREEN.px_for_deg(1.0)
    rows = series([640.0, 640.0 + one, 640.0, 640.0 + one, 640.0, 640.0],
                  y=400.0)
    fixes = [fixation(0, 5)]
    # Углы: 1, 1, 1, 1, 0 — у середины экрана один градус — один градус.
    value = noise.s2s_deg(rows, fixes, SCREEN)
    assert value == pytest.approx((4 / 5) ** 0.5, rel=1e-3)
    # Просвет между кадрами фиксации — пара не считается.
    rows = series([640.0, 640.0 + one, 640.0], gaps={1}, y=400.0)
    assert noise.s2s_deg(rows, [fixation(0, 2)], SCREEN) == \
        pytest.approx(1.0, rel=1e-3)
    assert noise.s2s_deg(rows, [], SCREEN) is None


# --- пропуск сессии ----------------------------------------------------------

def entry(share):
    return {"status": "ok", "gaze": {"present": True},
            "gaze_data": {"layout": True, "precision_deg": 2.2,
                          "disorder": {"fix_share": share}}}


def test_bug_70_gate_is_the_share_of_time_in_fixations():
    c = study.settings()
    assert c["min_fix_share"] == 0.85
    assert c["smooth_frames"] == 3 and c["smooth_min_fps"] == 25
    # Прецизионность 2,2° сама по себе больше не отсекает.
    assert disorder.gate(entry(0.93), c) is None
    assert disorder.gate(entry(0.52), c) == \
        "фиксации дробятся: в фиксациях 52 % времени, нужно 85 %"
    assert "доли в фиксациях нет" in disorder.gate(entry(None), c)
    no_layout = entry(0.93)
    no_layout["gaze_data"]["layout"] = False
    assert "раскладки" in disorder.gate(no_layout, c)


# --- лесенка шума: откуда порог доли -----------------------------------------

@pytest.fixture(scope="module")
def ladder():
    rows = []
    for order in (0.5, 0.8):
        for seed in (1, 2, 3):
            fixes = nl.path(seed, order=order)
            h0 = nl.step(fixes, 0.0, seed)["h"]
            for i in range(0, 25, 2):
                sigma = i / 10
                r = nl.step(fixes, sigma, seed)
                r.update(order=order, seed=seed,
                         bias=None if r["h"] is None else r["h"] - h0)
                rows.append(r)
    return rows


def test_bug_70_threshold_from_the_noise_ladder(ladder):
    """Выше порога доли энтропия поиска уходит от бесшумной истины не
    больше чем на 0,05; ниже — уходит: порог не пустой."""
    limit = study.settings()["min_fix_share"]
    above = [r for r in ladder if r["bias"] is not None
             and r["share"] >= limit]
    below = [r for r in ladder if r["bias"] is not None
             and r["share"] < limit]
    assert above and below
    assert all(abs(r["bias"]) <= nl.BIAS for r in above), \
        [(r["order"], r["seed"], r["sigma"]) for r in above
         if abs(r["bias"]) > nl.BIAS]
    assert any(abs(r["bias"]) > nl.BIAS for r in below)


def test_bug_70_smoothing_keeps_the_measure_at_webcam_noise():
    """Шум 1,2° по оси: без сглаживания энтропия поиска уходит больше
    чем на 0,05 и фиксации дробятся, с медианой трёх кадров — нет."""
    fixes = nl.path(1)
    plain0 = nl.step(fixes, 0.0, 1, frames=1)["h"]
    plain = nl.step(fixes, 1.2, 1, frames=1)
    smooth0 = nl.step(fixes, 0.0, 1)["h"]
    smooth = nl.step(fixes, 1.2, 1)
    assert plain["h"] - plain0 > nl.BIAS
    assert plain["share"] < study.settings()["min_fix_share"]
    assert abs(smooth["h"] - smooth0) <= nl.BIAS
    assert smooth["share"] >= study.settings()["min_fix_share"]


# --- АМ2: ширина экрана, названная организатором ----------------------------

import json  # noqa: E402
import math  # noqa: E402

from sno_eye import record_check as rc  # noqa: E402
from sno_eye.report import archive as arc  # noqa: E402
from sno_eye.study import screen_fix  # noqa: E402

HP = "\\\\?\\usb#vid_0408&pid_5365&mi_00#6&fd6cfa0&0&0000"


def hp(code, branch, width, seed):
    """Запись с ноутбука HP: ширина в «Месте записи» и у спутника."""
    return ss.Person(code=code, branch=branch,
                     device="4aac45" if branch == "I" else "54c8bf",
                     camera="HP TrueVision HD Camera", camera_path=HP,
                     screen_mm=width, calib_screen_mm=width, seed=seed)


def test_am2_width_file_is_read(tmp_path):
    (tmp_path / screen_fix.WIDTH_FILE).write_text(
        "# ноутбук HP: паспорт экрана — 34 см (АМ2)\n"
        "19575578 = 344\n"
        "sno2026_I_1_x.zip 344,5 мм\n"
        "чепуха\n"
        "77777777 = 5\n", encoding="utf-8")
    sub = tmp_path / "ПК 2"
    sub.mkdir()
    (sub / screen_fix.WIDTH_FILE).write_text(
        "19575578 = 344   # то же — не спор\n"
        "88888888 = 300\n88888888 = 310\n", encoding="utf-8")
    widths, notes = screen_fix.read([str(tmp_path)])
    assert widths == {"19575578": 344.0, "sno2026_I_1_x": 344.5}
    assert any("строка 4: не понята" in n for n in notes)
    assert any("5 мм вне 100–1500 мм" in n for n in notes)
    assert any("«88888888»" in n and "две разные" in n for n in notes)
    # Рядом с названным архивом.
    archive = sub / "запись.zip"
    archive.write_bytes(b"")
    widths, _ = screen_fix.read([str(archive)])
    assert widths["19575578"] == 344.0
    assert screen_fix.width_for(widths, "19575578", "x.zip") == 344.0
    assert screen_fix.width_for({"sno2026_I_1_x": 300.0}, None,
                                "sno2026_I_1_x.zip") == 300.0
    assert screen_fix.read([str(tmp_path / "нет такой")]) == ({}, [])


def test_am2_width_fix_rescales_what_the_satellite_measured(tmp_path):
    p = hp("19575578", "I", 396.1, 1)
    p.start_deg, p.end_deg = 1.241, 1.281
    rec = arc.load(ss.write(tmp_path, p), rc.thresholds())
    assert screen_fix.apply(rec, 396.1) is None        # та же ширина
    fix = screen_fix.apply(rec, 344.0)
    k = 344.0 / 396.1
    assert fix["from_mm"] == pytest.approx(396.1) and fix["k"] == \
        pytest.approx(k)

    def turned(deg):
        return math.degrees(math.atan(k * math.tan(math.radians(deg))))

    screen = rec.calibration["screen"]
    assert screen["w_mm"] == 344.0
    assert screen["h_mm"] == pytest.approx(396.1 * 800 / 1280 * k)
    assert screen["distance_mm"] == 600.0               # не от ширины
    eye = rec.manifest["eye_tracker"]
    assert eye["place"]["screen"]["w_mm"] == 344.0
    assert eye["place"]["screen"]["px_per_mm"] == pytest.approx(1920 / 344,
                                                               abs=1e-3)
    assert eye["calibration"]["accuracy_deg"] == pytest.approx(
        turned(1.241), abs=1e-4)
    assert eye["calibration"]["precision_deg"] == pytest.approx(
        turned(p.precision_deg), abs=1e-4)
    assert eye["end_check"]["accuracy_deg"] == pytest.approx(
        turned(1.281), abs=1e-4)
    assert rec.check["start_deg"] == pytest.approx(turned(1.241), abs=1e-4)
    assert rec.check["end_deg"] == pytest.approx(turned(1.281), abs=1e-4)
    # Углы и место головы — не по экрану: не меняются.
    result = {"accuracy_deg": 2.0, "turn_deg": 10.0, "dx_mm": 5.0,
              "shift_mm": [10.0, -4.0]}
    screen_fix._fix_result(result, k)
    assert result["turn_deg"] == 10.0 and result["dx_mm"] == 5.0
    assert result["shift_mm"] == [pytest.approx(10 * k, abs=1e-3),
                                  pytest.approx(-4 * k, abs=1e-3)]


def test_am2_width_file_unifies_the_pc_and_says_so(tmp_path):
    """Ветвь I ноутбука HP записала 396,1 мм, ветвь II — 344; файл
    ширины называет 344 для записи ветви I — оговорки BUG-69 больше нет,
    а запись получает свою: что исправлено и чего поправка не меняет."""
    folder = tmp_path / "набор"
    a = hp("19575578", "I", 396.1, 1)
    b = hp("59557835", "II", 344.0, 2)
    for p in (a, b):
        ss.write(folder, p)
    before = study.analyse([str(folder)], cfg=cfg())
    assert any("344 и 396,1 мм" in w for w in before["result"]["warnings"])
    (folder / screen_fix.WIDTH_FILE).write_text(
        "19575578 = 344   # паспорт экрана ноутбука HP: 34 см\n",
        encoding="utf-8")
    after = study.analyse([str(folder)], cfg=cfg())
    assert not any("344 и 396,1 мм" in w
                   for w in after["result"]["warnings"])
    assert any(w.startswith("19575578: ширина экрана исправлена")
               and "396,1 → 344 мм" in w
               for w in after["result"]["warnings"])
    by = {e["participant"]: e for e in after["entries"]}
    fixed, kept = by[a.code], by[b.code]
    assert fixed["screen_mm"] == 344.0 and kept["screen_fix"] is None
    assert any("поправка на голову" in n for n in fixed["check_notes"])
    k = 344.0 / 396.1
    assert fixed["gaze"]["start_deg"] < a.start_deg
    assert fixed["gaze"]["start_deg"] == pytest.approx(
        math.degrees(math.atan(k * math.tan(math.radians(a.start_deg)))),
        abs=1e-4)
    # Экран разбора — новый: градусов в точке окна больше.
    old = before["entries"][0]["gaze_data"]["disorder"]["cell_deg"][0]
    new = fixed["gaze_data"]["disorder"]["cell_deg"][0]
    assert new == pytest.approx(old * k, rel=0.02)
    assert json.dumps(fixed["screen_fix"])     # уходит в исходные.json
