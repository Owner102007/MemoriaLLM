"""Шаг 37, SNO-ALG-RES-03: меры беспорядочности взгляда на придуманных
числах — энтропия, подвыборка и случайный уровень, `k` по S0 с полом,
коэффициент K, ряды переходов и фазы, путь и прямота по содержимому,
возвраты, кучность (NNI), отбор по шуму.
"""

from __future__ import annotations

import math
import random

import pytest

np = pytest.importorskip("numpy")

from sno_eye import report  # noqa: E402
from sno_eye.report.screen import Screen  # noqa: E402
from sno_eye.report.timeline import Timeline  # noqa: E402
from sno_eye.report.versions import Sample  # noqa: E402
from sno_eye import study  # noqa: E402
from sno_eye.study import disorder  # noqa: E402
from sno_eye.study.actions import Trip  # noqa: E402

SCREEN = Screen(1280.0, 800.0, 340.0, 212.5, 600.0)
W, H = 1280.0, 800.0


def cfg(**kw):
    c = study.settings()
    c.update(kw)
    return c


# --- М1, М2: формула, подвыборка, случайный уровень --------------------

def test_sno_alg_res_03_entropy_on_full_matrices():
    n = 4
    uniform = np.array([(i, j) for i in range(n) for j in range(n)] * 3)
    h_t, h_s = disorder._entropies(uniform, n)
    assert h_t == pytest.approx(math.log2(n))
    assert h_s == pytest.approx(math.log2(n))
    # Следующая зона известна по текущей — переходы предсказуемы.
    cycle = np.array([(i, (i + 1) % n) for i in range(n)] * 5)
    h_t, h_s = disorder._entropies(cycle, n)
    assert h_t == pytest.approx(0.0)
    assert h_s == pytest.approx(math.log2(n))


@pytest.mark.parametrize("count", [60, 300, 3000])
def test_sno_alg_res_03_random_gaze_is_about_one_at_any_length(count):
    """Случайный взгляд после подвыборки и деления на случайный уровень
    — около 1 при любом числе переходов участника: подвыборка
    выравнивает смещение оценки."""
    n, k = 13, 50
    rng = random.Random(count)
    trans = [(rng.randrange(n), rng.randrange(n)) for _ in range(count)]
    h_t, h_s = disorder.subsampled(trans, n, k, 200, seed=1)
    r_t, r_s = disorder.random_level(n, k, 200, seed=2)
    assert h_t / r_t == pytest.approx(1.0, abs=0.06)
    assert h_s / r_s == pytest.approx(1.0, abs=0.06)
    # Без поправки оценка по малой выборке занижена.
    assert r_t < math.log2(n) * 0.85


def test_sno_alg_res_03_ordered_gaze_is_far_below_one():
    n, k = 13, 50
    trans = [(i % 3, (i + 1) % 3) for i in range(200)]
    h_t, _ = disorder.subsampled(trans, n, k, 200, seed=1)
    r_t, _ = disorder.random_level(n, k, 200, seed=2)
    assert h_t / r_t < 0.05


def test_sno_alg_res_03_no_repeat_random_level():
    n, k = 5, 300
    a, _ = disorder.random_level(n, k, 100, seed=3)
    b, _ = disorder.random_level(n, k, 100, seed=3, no_repeat=True)
    # Без переходов внутри зоны случайный взгляд выбирает из n − 1.
    assert a == pytest.approx(math.log2(n), abs=0.1)
    assert b == pytest.approx(math.log2(n - 1), abs=0.1)


# --- `k` по S0, пол, K по S0 ------------------------------------------

def _phase(trans, pairs=()):
    return {"zones": 13, "transitions": list(trans), "k_pairs": list(pairs),
            "fixations": len(trans) + 1, "fix_ms": 300.0, "sacc_deg": 5.0,
            "time_s": 60.0, "fix_rate": 3.0}


def fake(code, search, *, colour="green", precision=0.5, pairs=None,
         branch="I", reading=250):
    rng = random.Random(code)
    trans = [(rng.randrange(13), rng.randrange(13)) for _ in range(search)]
    read = [(rng.randrange(9), rng.randrange(9)) for _ in range(reading)]
    every = [(rng.randrange(5), rng.randrange(5))
             for _ in range(search + reading)]
    pairs = pairs if pairs is not None else \
        [(rng.uniform(200, 400), rng.uniform(2, 10)) for _ in range(30)]
    return {
        "status": "ok", "participant": code, "archive": f"{code}.zip",
        "sha256": f"{code:0>64}", "branch": branch, "stratum": "pc",
        "series": "sno2026-2", "study_s": 2400, "colour": colour,
        "etalon": "да", "etalon_out": None,
        "gaze": {"present": True, "included": True},
        "gaze_data": {
            "precision_deg": precision, "layout": True,
            "shares": {"page": 0.5, "shelf": 0.2, "no_frames": 0.3},
            "disorder": {
                "idt_deg": 4.5, "cell_deg": [7.6, 6.3],
                "phases": {"search": _phase(trans, pairs),
                           "reading": _phase(read, pairs),
                           "all": _phase(every, pairs)},
                "trips": [], "nni": {"shelf": {"n": 0, "nni": None},
                                     "galaxy": {"n": 0, "nni": None}}}},
    }


def test_sno_alg_res_03_k_is_the_smallest_in_s0_above_the_floor():
    entries = [fake("a", 120), fake("b", 80), fake("c", 30),
               fake("r", 50, colour="red")]
    info = disorder.finish(entries, cfg(), fingerprint="f",
                           no_filter=False, series=None)
    search = info["phases"]["search"]
    assert info["from"] == "S0"
    # «c» ниже пола 40 — в k не идёт; «r» (🔴) не в S0 — тоже.
    assert search["floor"] == 40 and search["k"] == 80
    by = {e["participant"]: e["gaze_measures"] for e in entries}
    assert "search.H_t" in by["a"] and "search.H_t" in by["b"]
    assert "search.H_t" not in by["c"]           # ниже пола — пусто
    assert "search.H_t" not in by["r"]           # меньше k — пусто
    assert by["c"]["search.transitions"] == 30
    for code in "ab":
        assert by[code]["search.H_t"] == pytest.approx(1.0, abs=0.12)


def test_sno_alg_res_03_k_and_k_coefficient_ignore_non_s0():
    """μ и σ коэффициента K и `k` — только по участникам S0: 🔴 с
    крайними числами их не сдвигает, и K зелёного не плывёт."""
    base = [fake("a", 120), fake("b", 90)]
    info1 = disorder.finish(base, cfg(), fingerprint="f", no_filter=False,
                            series=None)
    k1 = base[0]["gaze_measures"]["search.K"]
    extreme = [(5000.0, 80.0)] * 40
    more = [fake("a", 120), fake("b", 90),
            fake("r", 45, colour="red", pairs=extreme)]
    info2 = disorder.finish(more, cfg(), fingerprint="f", no_filter=False,
                            series=None)
    assert info1["phases"]["search"]["K"] == info2["phases"]["search"]["K"]
    assert more[0]["gaze_measures"]["search.K"] == k1
    assert info1["phases"]["search"]["k"] == info2["phases"]["search"]["k"]


def test_sno_alg_res_03_k_coefficient_with_known_z():
    pairs = [(100.0, 10.0), (300.0, 2.0)] * 10
    e = fake("a", 60, pairs=pairs)
    info = disorder.finish([e], cfg(), fingerprint="f", no_filter=False,
                           series=None)
    K = info["phases"]["search"]["K"]
    assert K == {"mu_d": 200.0, "sd_d": 100.0, "mu_a": 6.0, "sd_a": 4.0}
    # K_i = (d − μd) / σd − (a − μa) / σa: −1 − 1 и 1 + 1 — в среднем 0.
    assert e["gaze_measures"]["search.K"] == pytest.approx(0.0)
    few = fake("b", 60, pairs=pairs[:4])
    disorder.finish([e, few], cfg(), fingerprint="f", no_filter=False,
                    series=None)
    assert "search.K" not in few["gaze_measures"]   # меньше 10 пар


def test_sno_alg_res_03_noisy_session_leaves_only_m1_to_m7():
    noisy = fake("n", 120, precision=2.0)
    clean = fake("a", 120)
    disorder.finish([clean, noisy], cfg(), fingerprint="f",
                    no_filter=False, series=None)
    assert "три прецизионности 6,0°" in noisy["disorder_gate"]
    assert not noisy.get("disorder_live")
    assert not any(k.startswith(("search.", "reading.", "all."))
                   for k in noisy["gaze_measures"])
    # Доли зон у неё остаются: они порогом сессии.
    assert noisy["gaze_measures"]["share.reading"] == 0.5
    # Проверочный прогон отбора по шуму не делает — сессия помечена,
    # но меры получает.
    again = fake("n", 120, precision=2.0)
    disorder.finish([fake("a", 120), again], cfg(), fingerprint="f",
                    no_filter=True, series=None)
    assert again["disorder_gate"] and again["disorder_live"]
    assert "search.H_t" in again["gaze_measures"]
    unknown = fake("u", 120, precision=None)
    disorder.finish([unknown], cfg(), fingerprint="f", no_filter=False,
                    series=None)
    assert "неизвестна" in unknown["disorder_gate"]


# --- ряды переходов ----------------------------------------------------------

def fx(t, phases, d=300, moving=False):
    return {"t": t, "end": t + d, "d": d, "moving": moving,
            "phases": phases}


def test_sno_alg_res_03_chains_break_where_they_must():
    fixes = [
        fx(0, {"search": 0}), fx(400, {"search": 0}),
        # Заход на другой экран посреди похода рвёт ряд.
        fx(800, {"all": True}),
        fx(1200, {"search": 0}), fx(1600, {"search": 0}),
        # Следующий поход — новый ряд, даже без просвета.
        fx(1950, {"search": 1}),
        # Просвет дольше секунды — не переход.
        fx(3500, {"search": 1}),
        # Фиксация на отрезке движения рвёт ряд.
        fx(3900, {"search": 1}, moving=True), fx(4300, {"search": 1}),
        fx(4700, {"search": 1}),
    ]
    runs = disorder.chains(fixes, "search", [], 1000)
    assert runs == [[0, 1], [3, 4], [5], [6], [8, 9]]
    # Отрезок движения между фиксациями рвёт ряд и без фиксации на нём.
    runs = disorder.chains(fixes[8:], "search", [(4650.0, 4680.0)], 1000)
    assert runs == [[0], [1]]


# --- одна запись: фазы, путь, прямота, возвраты ----------------------------

def shelf_frame(t, scroll=0.0):
    regions = [
        {"kind": "screen", "id": "shelf", "rect": [0, 56, W, H - 56],
         "z": 0, "info": {"scroll": scroll}},
        {"kind": "nav", "id": "", "rect": [0, 0, W, 56], "z": 1},
        {"kind": "shelf_book", "id": "BOOK",
         "rect": [1000, 600 - scroll, 150, 120], "z": 2,
         "info": {"category": "А"}},
    ]
    return {"t": float(t), "n": 1, "screen": "shelf", "moving": False,
            "viewport": {"w": W, "h": H}, "regions": regions}


def other_frame(t):
    return {"t": float(t), "screen": "testing", "moving": False,
            "viewport": {"w": W, "h": H},
            "regions": [{"kind": "screen", "id": "testing",
                         "rect": [0, 0, W, H], "z": 0}]}


def samples(looks, period=33):
    """Кадры взгляда по взглядам (a, b, x, y) без шума; между взглядами
    — просвет."""
    out = []
    for a, b, x, y in looks:
        t = a
        while t < b:
            out.append(Sample(t=float(t), x=x, y=y, ok=True, face=True))
            t += period
    return out


def line(screens, end=60_000):
    return Timeline(study_start=0.0, study_end=float(end),
                    gaze_expected=True, latency_ms=0.0, latency_known=True,
                    start_deg=1.0, end_deg=1.0, precision_deg=0.3,
                    end_shift_mm=None, screens=screens)


def run_prepare(looks, frames, screens, trips, events, inputs, **kw):
    return disorder.prepare(samples(looks), [], frames, SCREEN,
                            line(screens), trips, events, inputs,
                            cfg(**kw), report.settings(), seed=7)


def test_sno_alg_res_03_search_phase_and_trips():
    """Поиск — только полка и карта доведённых походов: заход на другой
    экран посреди похода и недоведённый последний поход в поиск не
    идут, и переходы не склеивают соседние походы."""
    pts = [(100, 100), (700, 150), (300, 500), (1100, 650), (600, 700)]
    looks = []
    t = 1000
    for x, y in pts:                      # поход 1, полка
        looks.append((t, t + 400, x, y))
        t += 450
    looks.append((3600, 4000, 640, 400))  # «Тестирование» посреди
    for x, y in pts[:3]:                  # поход 1 продолжается
        looks.append((t + 2000, t + 2400, x, y))
        t += 450
    t2 = 12_000                           # поход 2, недоведённый
    for x, y in pts:
        looks.append((t2, t2 + 400, x, y))
        t2 += 450
    frames = [shelf_frame(0), other_frame(3500), shelf_frame(4100)]
    screens = [(0.0, "shelf"), (3500.0, "testing"), (4100.0, "shelf"),
               (9000.0, "reader"), (11_000.0, "shelf")]
    trips = [Trip(n=1, start=0.0, end=9000.0, complete=True, book="BOOK",
                  via="shelf", choice=9000.0, search_ms=8400.0),
             Trip(n=2, start=11_000.0, end=60_000.0, complete=False)]
    events = [{"t": 9000, "type": "book.open", "book": "BOOK",
               "data": {"via": "shelf"}, "input": 1}]
    inputs = {1: {"t": 8990, "x": 1075.0, "y": 660.0}}
    out = run_prepare(looks, frames, screens, trips, events, inputs)
    search = out["phases"]["search"]
    # 5 фиксаций, разрыв на «Тестировании», ещё 3: 4 + 2 перехода.
    assert search["fixations"] == 8
    assert len(search["transitions"]) == 6
    assert len(out["trips"]) == 1 and out["trips"][0]["fixations"] == 8
    assert out["phases"]["all"]["fixations"] == 14


def _trip_looks(points, start=1000, d=400, gap=60):
    looks, t = [], start
    for x, y in points:
        looks.append((t, t + d, x, y))
        t += d + gap
    return looks, t


def _one_trip(points, target=(1075.0, 660.0), frames=None, first_book=False):
    looks, t = _trip_looks(points)
    end = t + 100
    trips = [Trip(n=1, start=0.0, end=float(end), complete=True,
                  book="BOOK", via="shelf", choice=float(end),
                  search_ms=float(end))]
    events = [{"t": end, "type": "book.open", "book": "BOOK",
               "data": {"via": "shelf"}, "input": 1}]
    inputs = {1: {"t": end - 10, "x": target[0], "y": target[1]}}
    out = run_prepare(looks, frames or [shelf_frame(0)],
                      [(0.0, "shelf"), (float(end), "reader")], trips,
                      events, inputs)
    return out["trips"][0]


def test_sno_alg_res_03_path_and_straightness_on_a_line_and_a_zigzag():
    line_pts = [(100.0, 100.0), (400.0, 280.0), (700.0, 460.0),
                (1000.0, 640.0)]
    straight = _one_trip(line_pts, target=(1075.0, 685.0))
    assert straight["straight"] == pytest.approx(1.0, abs=0.01)
    zig = [(100.0, 100.0), (1200.0, 120.0), (100.0, 700.0),
           (1200.0, 300.0), (300.0, 650.0), (1000.0, 640.0)]
    crooked = _one_trip(zig, target=(1075.0, 685.0))
    assert crooked["path_deg"] > 3 * straight["path_deg"]
    assert crooked["straight"] < 0.35
    # Путь замкнут на месте нажатия — прямота не больше 1.
    assert 0 < crooked["straight"] <= 1


def test_sno_alg_res_03_scroll_is_not_eye_movement():
    """Между фиксациями полку прокрутили на 300 точек: точка содержимого
    та же, и скачок взгляда по содержимому — около нуля."""
    frames = [shelf_frame(0, 0.0), shelf_frame(1890, 300.0)]
    pts = [(200.0, 500.0), (600.0, 500.0), (600.0, 200.0)]
    trip = _one_trip(pts, target=(600.0, 200.0), frames=frames)
    # Без прокрутки было бы два скачка; с ней второй — ноль.
    plain = _one_trip(pts, target=(600.0, 200.0))
    assert trip["path_deg"] == pytest.approx(
        SCREEN.angle_deg((200, 500), (600, 500)), abs=0.05)
    assert plain["path_deg"] > trip["path_deg"] + 5


def test_sno_alg_res_03_first_fixation_on_target_is_straight():
    trip = _one_trip([(1070.0, 650.0), (300.0, 300.0), (1070.0, 650.0)])
    assert trip["straight"] == 1.0


def test_sno_alg_res_03_returns_count_revisited_cells():
    # Клетки: (0,0), (0,3), (0,0) снова, (2,3): 4 захода, 1 возврат.
    pts = [(100.0, 100.0), (1200.0, 100.0), (100.0, 120.0),
           (1200.0, 700.0)]
    trip = _one_trip(pts)
    assert trip["returns"] == pytest.approx(0.25)
    once = _one_trip([(100.0, 100.0), (1200.0, 700.0)])
    assert once["returns"] == 0.0


def test_sno_alg_res_03_cells_and_outside():
    grid = (4, 3)
    assert disorder.cell_of(10, 10, W, H, 80, grid) == "c00"
    assert disorder.cell_of(1279, 799, W, H, 80, grid) == "c23"
    # Чуть за краем — клетка у края; дальше запаса — «вне экрана».
    assert disorder.cell_of(-20, 400, W, H, 80, grid) == "c10"
    assert disorder.cell_of(-200, 400, W, H, 80, grid) == "outside"
    assert len(disorder.search_zones(grid)) == 13


# --- М6: кучность ------------------------------------------------------------

def test_sno_alg_res_03_nni_random_grid_and_clusters():
    rect = (0.0, 0.0, 1000.0, 600.0)
    rng = np.random.default_rng(5)
    nni = []
    for _ in range(40):
        pts = np.column_stack([rng.random(30) * 1000, rng.random(30) * 600])
        nni.append(disorder.mean_nn(pts) /
                   disorder.random_nn(rect, 30, 100, rng))
    assert np.mean(nni) == pytest.approx(1.0, abs=0.05)
    gx, gy = np.meshgrid(np.linspace(50, 950, 6), np.linspace(50, 550, 5))
    grid = np.column_stack([gx.ravel(), gy.ravel()])
    g = disorder.mean_nn(grid) / disorder.random_nn(rect, 30, 200, rng)
    assert g > 1.5
    centres = np.array([[200, 150], [800, 450], [500, 300]])
    blob = np.concatenate([c + rng.normal(0, 8, (10, 2)) for c in centres])
    c = disorder.mean_nn(blob) / disorder.random_nn(rect, 30, 200, rng)
    assert c < 0.4
    # В сравнение — отклонение от случайного: у порядка оно больше.
    assert abs(1 - g) > abs(1 - np.mean(nni))
    assert abs(1 - c) > abs(1 - np.mean(nni))


def test_sno_alg_res_03_nni_needs_twenty_fixations():
    looks, t = _trip_looks([(100.0 + 200 * (i % 6), 100.0 + 200 * (i // 6))
                            for i in range(12)])
    trips = [Trip(n=1, start=0.0, end=float(t), complete=True, book="BOOK",
                  via="shelf", choice=float(t), search_ms=float(t))]
    out = run_prepare(looks, [shelf_frame(0)],
                      [(0.0, "shelf"), (float(t), "reader")], trips, [], {})
    assert out["nni"]["shelf"]["n"] == 12
    assert out["nni"]["shelf"]["nni"] is None
    out = run_prepare(looks, [shelf_frame(0)],
                      [(0.0, "shelf"), (float(t), "reader")], trips, [], {},
                      min_fix_nni=10)
    assert out["nni"]["shelf"]["nni"] > 1.0


# --- по независимой проверке шага 37 --------------------------------------

def test_sno_alg_res_03_scroll_moves_only_the_shelf_section():
    """Прокручивается только раздел полки: две фиксации на полосе
    навигации при разной прокрутке — один и тот же взгляд."""
    a = {"frame": shelf_frame(0, 0.0), "x": 500.0, "y": 20.0}
    b = {"frame": shelf_frame(10, 500.0), "x": 500.0, "y": 20.0}
    assert disorder._moved(a, b, SCREEN) == pytest.approx(0.0)
    assert disorder.content(b["frame"], 500.0, 20.0) == \
        ("screen", 500.0, 20.0)
    assert disorder.content(b["frame"], 500.0, 300.0) == \
        ("shelf", 500.0, 800.0)


def test_sno_alg_res_03_target_from_the_frame_without_a_tap():
    """Строки нажатия нет — цель по кадру: середина выбранной книги."""
    looks, t = _trip_looks([(100.0, 100.0), (600.0, 400.0)])
    trips = [Trip(n=1, start=0.0, end=float(t), complete=True, book="BOOK",
                  via="shelf", choice=float(t), search_ms=float(t))]
    out = run_prepare(looks, [shelf_frame(0)],
                      [(0.0, "shelf"), (float(t), "reader")], trips, [], {})
    trip = out["trips"][0]
    # Книга — [1000, 600, 150, 120], середина (1075, 660).
    straight = SCREEN.angle_deg((100, 100), (1075, 660))
    assert trip["straight"] == pytest.approx(
        straight / trip["path_deg"])
    assert trip["path_deg"] == pytest.approx(
        SCREEN.angle_deg((100, 100), (600, 400))
        + SCREEN.angle_deg((600, 400), (1075, 660)))


def test_sno_alg_res_03_window_change_cuts_the_trips():
    """Окно сменили посреди изучения: походы после этого мига в меры
    поиска не идут и «походами без взгляда» не считаются."""
    looks, t = _trip_looks([(100.0, 100.0), (600.0, 400.0)])
    trips = [Trip(n=1, start=0.0, end=float(t), complete=True, book="BOOK",
                  via="shelf", choice=float(t), search_ms=float(t)),
             Trip(n=2, start=20_000.0, end=25_000.0, complete=True,
                  book="BOOK", via="shelf", choice=25_000.0,
                  search_ms=5000.0)]
    ln = line([(0.0, "shelf"), (float(t), "reader"), (20_000.0, "shelf"),
               (25_000.0, "reader")])
    ln.window_changed = 10_000.0
    out = disorder.prepare(samples(looks), [], [shelf_frame(0)], SCREEN, ln,
                           trips, [], {}, cfg(), report.settings(), seed=7)
    assert [r["n"] for r in out["trips"]] == [1]
    assert out["phases"]["search"]["time_s"] == pytest.approx(t / 1000)


def test_sno_alg_res_03_zero_entropy_is_not_minus_zero():
    h_t, h_s = disorder._entropies(np.array([(0, 0)] * 5), 3)
    assert str(h_t) == "0.0" and str(h_s) == "0.0"
