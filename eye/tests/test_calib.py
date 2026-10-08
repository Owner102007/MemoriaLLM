"""SNO-ALG-EYE-02: калибровка, проверка и приём — на синтетическом
участнике.

Участник — параметрическая голова (`synthetic.look_at`): известно, куда
он смотрит, как сидит, на сколько отстаёт камера и как дрожит взгляд.
Кадры подаются в `Calibration` без камеры и без потоков, со своим
временем: 30 кадров в секунду, точка калибровки — 2 с, слежение — 20 с,
точка проверки — 1,5 с, как в приложении.
"""

import json
import math

import numpy as np
import pytest

from sno_eye import calib, features, selfcheck, synthetic

T = selfcheck.load_thresholds()
W, H = 1920, 1080
SCREEN = calib.Screen(W, H, 527, 296, 600)
CALIB = [(0.08, 0.08), (0.5, 0.08), (0.92, 0.08), (0.08, 0.5), (0.5, 0.5),
         (0.92, 0.5), (0.08, 0.92), (0.5, 0.92), (0.92, 0.92),
         (0.29, 0.29), (0.71, 0.29), (0.29, 0.71), (0.71, 0.71)]
VALID = [(a, b) for b in (0.2, 0.5, 0.8) for a in (0.2, 0.5, 0.8)]
# Путь слежения для экрана 527×296 мм на 60 см — как в заметке алгоритма.
PATH = {"cx": W / 2, "cy": H / 2, "ax": 0.4 * W, "ay": 0.35 * H,
        "tx_ms": 16000, "ty_ms": 10667}
STEP_US = 33_333
T0 = 1_000_000_000


class Sim:
    """Сеанс калибровки синтетического участника со своим временем."""

    def __init__(self, noise=0.3, latency_ms=70, seed=1, screen=SCREEN):
        self.cal = calib.Calibration(screen, T)
        self.screen = screen
        self.noise = noise
        self.latency_us = latency_ms * 1000
        self.rng = np.random.default_rng(seed)
        self.t = T0
        self.events: list[calib.Target] = []
        self.offsets: dict[str, tuple[float, float]] = {}
        self.blink: set[str] = set()
        self.no_face = False

    def _looking(self, seen_us):
        cur = None
        for ev in self.events:
            if ev.qpc_us <= seen_us:
                cur = ev
        if cur is None or cur.phase == "off":
            return (W / 2, H / 2), None
        if cur.phase == "pursuit":
            return calib.path_at(cur.path, (seen_us - cur.qpc_us) / 1e6), cur
        dx, dy = self.offsets.get(cur.id, (0.0, 0.0))
        return (cur.x + dx, cur.y + dy), cur

    def frame(self):
        sec = (self.t - T0) / 1e6
        (x, y), cur = self._looking(self.t - self.latency_us)
        if self.no_face:
            self.cal.add(self.t, None, False)
            self.t += STEP_US
            return
        xm, ym = self.screen.mm(x, y)
        noise = tuple(self.rng.normal(0, self.noise, 2)) if self.noise else (0.0, 0.0)
        head = synthetic.look_at(xm, ym, self.screen.distance_mm,
                                 yaw=1.5 * math.sin(sec * 0.31),
                                 pitch=1.0 * math.sin(sec * 0.23), noise=noise)
        face = synthetic.render(head, W, H)
        vec = features.compute(face.landmarks, face.matrix, W, H)
        ok = not (cur is not None and cur.id in self.blink)
        self.cal.add(self.t, vec, ok)
        self.t += STEP_US

    def show(self, tid, x, y, phase, seconds, path=None):
        ev = calib.Target(tid, x, y, phase, self.t, path)
        self.events.append(ev)
        self.cal.target(ev)
        for _ in range(round(seconds * 30)):
            self.frame()

    def off(self):
        ev = calib.Target("off", 0, 0, "off", self.t)
        self.events.append(ev)
        self.cal.target(ev)

    def calibrate(self, kind="full", attempt=1, points=CALIB):
        self.cal.begin(attempt, kind, self.t)
        for i, (fx, fy) in enumerate(points):
            self.show(f"c{i}", fx * W, fy * H, "calib", 2.0)
        self.off()
        if kind == "full":
            self.show("pursuit", PATH["cx"], PATH["cy"], "pursuit", 20.0, PATH)
            self.off()
        return self.cal.fit()

    def validate(self):
        for i, (fx, fy) in enumerate(VALID):
            self.show(f"v{i}", fx * W, fy * H, "validate", 1.5)
        self.off()
        return self.cal.validate()


def px_for_deg(deg):
    """Сколько логических пикселей по x в `deg` градусах у середины."""
    return math.tan(math.radians(deg)) * SCREEN.distance_mm * W / SCREEN.w_mm


def test_sno_alg_eye_02_screen_angle():
    assert SCREEN.angle_deg((960, 540), (960, 540)) == 0
    one_cm = 10 * W / SCREEN.w_mm
    assert SCREEN.angle_deg((960, 540), (960 + one_cm, 540)) == \
        pytest.approx(math.degrees(math.atan(10 / 600)), abs=1e-6)
    # Ближе к экрану — тот же отрезок шире в градусах.
    assert SCREEN.angle_deg((960, 540), (960 + one_cm, 540), 300) > 1.9
    assert calib.Screen.from_open({"w": 1920, "h": 1080, "w_mm": 527, "h_mm": 296}, 600)
    assert calib.Screen.from_open({"w_px": 1920}, 600) is None
    assert calib.Screen.from_open(None, 600) is None


def test_sno_alg_eye_02_windows_skip_start_and_join_repeats():
    ts = [calib.Target("a", 0, 0, "calib", 0), calib.Target("b", 0, 0, "calib", 2_000_000),
          calib.Target("off", 0, 0, "off", 4_000_000),
          calib.Target("a", 0, 0, "calib", 5_000_000),
          calib.Target("off", 0, 0, "off", 7_000_000)]
    w = calib.windows(ts, "calib", 500_000)
    assert w == {"a": [(500_000, 2_000_000), (5_500_000, 7_000_000)],
                 "b": [(2_500_000, 4_000_000)]}


def test_sno_alg_eye_02_path_is_lissajous():
    assert calib.path_at(PATH, 0) == (W / 2, H / 2)
    x, y = calib.path_at(PATH, 4.0)            # четверть периода по x
    assert x == pytest.approx(W / 2 + 0.4 * W)
    with pytest.raises(ValueError):
        calib.check_path({"cx": 1})


def test_sno_alg_eye_02_noise_free_participant_is_accepted_and_latency_found():
    sim = Sim(noise=0.0, latency_ms=70)
    fit = sim.calibrate()
    assert fit["points"] == 13 and fit["excluded"] == []
    assert fit["pursuit"] > 500
    assert abs(fit["latency_ms"] - 70) <= 34          # ±1 кадр
    v = sim.validate()
    assert v["accepted"] and v["reason"] is None
    assert v["accuracy_deg"] < 0.6 and v["worst_deg"] < 1.0
    assert v["precision_deg"] < 0.05
    assert len(v["points"]) == 9


@pytest.mark.parametrize("latency", [0, 120, 200])
def test_sno_alg_eye_02_latency_within_one_frame(latency):
    sim = Sim(noise=0.3, latency_ms=latency, seed=latency + 3)
    fit = sim.calibrate()
    assert abs(fit["latency_ms"] - latency) <= 34


def test_sno_alg_eye_02_precision_matches_noise():
    # Дрожь σ по каждой оси: угол между соседними выборками — разность двух
    # независимых двумерных ошибок, его RMS — 2σ.
    sigma = 0.3
    sim = Sim(noise=sigma, latency_ms=70, seed=11)
    sim.calibrate()
    v = sim.validate()
    assert v["precision_deg"] == pytest.approx(2 * sigma, rel=0.10)
    assert v["accepted"]


def test_sno_alg_eye_02_accuracy_matches_fixation_error():
    # Участник на точках проверки смотрит мимо на 1,5° в случайную сторону:
    # точность проверки — эти 1,5° с точностью 10 %.
    sim = Sim(noise=0.3, latency_ms=70, seed=5)
    sim.calibrate()
    rng = np.random.default_rng(3)
    off = 1.5
    for i in range(9):
        a = rng.uniform(0, 2 * math.pi)
        r_mm = math.tan(math.radians(off)) * SCREEN.distance_mm
        sim.offsets[f"v{i}"] = (r_mm * math.cos(a) * W / SCREEN.w_mm,
                                r_mm * math.sin(a) * H / SCREEN.h_mm)
    v = sim.validate()
    assert v["accuracy_deg"] == pytest.approx(off, rel=0.10)
    assert v["accuracy_cm"] == pytest.approx(math.tan(math.radians(off)) * 60, rel=0.12)


def test_sno_alg_eye_02_acceptance_by_thresholds():
    sim = Sim(noise=0.2, seed=8)
    sim.calibrate()
    for i in range(9):
        sim.offsets[f"v{i}"] = (px_for_deg(3.2), 0.0)
    v = sim.validate()
    assert not v["accepted"] and v["reason"] == "accuracy"
    assert v["thresholds"] == {"accept_deg": 2.5, "worst_deg": 5.0, "min_points": 6}

    sim = Sim(noise=0.2, seed=9)
    sim.calibrate()
    sim.offsets["v4"] = (px_for_deg(6.0), 0.0)   # одна точка далеко
    v = sim.validate()
    assert v["accuracy_deg"] < 2.5
    assert not v["accepted"] and v["reason"] == "worst" and v["worst_id"] == "v4"


def test_sno_alg_eye_02_blinked_point_is_short_and_repeated():
    sim = Sim(noise=0.2, seed=4)
    sim.blink = {"c3"}
    sim.cal.begin(1, "full", sim.t)
    for i, (fx, fy) in enumerate(CALIB):
        sim.show(f"c{i}", fx * W, fy * H, "calib", 2.0)
    sim.off()
    s = sim.cal.samples("calib")
    assert s["short"] == ["c3"] and s["counts"]["c3"] == 0 and s["face"] == 1.0
    # Повтор в конце: глаза открыты — точка набрала выборки.
    sim.blink = set()
    fx, fy = CALIB[3]
    sim.show("c3", fx * W, fy * H, "calib", 2.0)
    sim.off()
    s = sim.cal.samples("calib")
    assert s["short"] == [] and s["counts"]["c3"] >= 40


def test_sno_alg_eye_02_point_without_samples_is_excluded_and_named():
    sim = Sim(noise=0.2, seed=6)
    sim.blink = {"c5"}
    fit = sim.calibrate()
    assert fit["excluded"] == ["c5"] and fit["points"] == 12


def test_sno_alg_eye_02_no_face_stops_without_model():
    sim = Sim(noise=0.2)
    sim.no_face = True
    with pytest.raises(calib.CalibrationError) as e:
        sim.calibrate()
    assert e.value.code == "no_face" and "не видит лица" in e.value.text
    assert sim.cal.samples("calib")["face"] == 0.0
    assert sim.cal.model is None


def test_sno_alg_eye_02_quick_is_ridge_without_pursuit():
    sim = Sim(noise=0.3, seed=12)
    fit = sim.calibrate(kind="quick", points=VALID)
    assert fit["model"] == "ridge" and fit["latency_ms"] is None
    assert fit["pursuit"] == 0 and list(fit["cv_by_model"]) == ["ridge"]
    assert fit["cv_deg"] < 2.5


def test_sno_alg_eye_02_both_models_are_tried_and_better_one_kept():
    sim = Sim(noise=0.3, seed=13)
    fit = sim.calibrate()
    assert set(fit["cv_by_model"]) == {"ridge", "krr"}
    assert fit["cv_deg"] == min(fit["cv_by_model"].values())


def test_sno_alg_eye_02_model_survives_json():
    sim = Sim(noise=0.3, seed=14)
    sim.calibrate()
    data = json.loads(json.dumps(sim.cal.to_json()))
    assert data["schema"] == "sno2026-eyecal/1"
    assert data["attempts"][0]["fit"]["model"] in ("ridge", "krr")
    model = calib.model_from_json(data["model"])
    x = np.array([features.compute(*(lambda f: (f.landmarks, f.matrix))(
        synthetic.render(synthetic.look_at(30, -20, 600), W, H)), W, H)])
    a = model.predict(x[:, calib.USED_IDX])
    b = sim.cal.model.predict(x[:, calib.USED_IDX])
    assert np.allclose(a, b)


def test_sno_alg_eye_02_target_order_is_checked():
    cal = calib.Calibration(SCREEN, T)
    with pytest.raises(calib.CalibrationError):
        cal.target(calib.Target("a", 0, 0, "calib", 10))
    cal.begin(1, "full", 0)
    cal.target(calib.Target("a", 0, 0, "calib", 10))
    with pytest.raises(calib.CalibrationError):
        cal.target(calib.Target("b", 0, 0, "calib", 5))
    with pytest.raises(calib.CalibrationError):
        calib.Calibration(None, T).begin(1, "full", 0)


def test_sno_alg_eye_02_smoother_follows_and_jumps():
    s = calib.Smoother((30.0, 30.0))
    t = 0
    for _ in range(60):
        x, y = s.push(t, 500.0, 300.0)
        t += STEP_US
    assert (x, y) == pytest.approx((500.0, 300.0), abs=1.0)
    # Одиночный выброс точку не двигает.
    assert s.push(t, 1500.0, 900.0) == pytest.approx((500.0, 300.0))
    t += STEP_US
    assert s.push(t, 500.0, 300.0) == pytest.approx((500.0, 300.0))
    # Саккада: три кадра кучно на новом месте — точка там, без хвоста.
    for _ in range(3):
        t += STEP_US
        x, y = s.push(t, 1500.0, 900.0)
    assert (x, y) == pytest.approx((1500.0, 900.0))
    # Перерыв дольше полусекунды — стоянка заново.
    t += 600_000
    assert s.push(t, 100.0, 100.0) == pytest.approx((100.0, 100.0))
    assert s.held == pytest.approx((100.0, 100.0))


def _fixation(sim, fx, fy, frames, noise):
    """Оценки взгляда участника, который смотрит в одну точку."""
    xm, ym = sim.screen.mm(fx * W, fy * H)
    out = []
    for i in range(frames):
        n = tuple(sim.rng.normal(0, noise, 2))
        head = synthetic.look_at(xm, ym, sim.screen.distance_mm, noise=n)
        face = synthetic.render(head, W, H)
        vec = features.compute(face.landmarks, face.matrix, W, H)
        out.append((T0 + i * STEP_US, sim.cal.predict(vec)))
    return out


@pytest.mark.parametrize("noise", [0.5, 1.5])
def test_bug_59_live_dot_shakes_much_less_than_the_estimate(noise):
    # BUG-59: на ПК владельца живая точка дрожала на 3–5 см. Фильтр Калмана
    # был настроен на шум в 40 пикселей (≈ 1°), а шум оценки там втрое
    # больше; разбор того же синтетического участника показал дрожь
    # сглаженной точки — половину дрожи оценки. Теперь шум меряется на
    # точках калибровки, и точка стоит на среднем стоянки.
    sim = Sim(noise=noise, latency_ms=70, seed=5)
    fit = sim.calibrate(kind="quick", points=CALIB[:9])
    assert fit["noise_deg"] == pytest.approx(noise, rel=0.3)
    s = calib.Smoother(sim.cal.noise_px)
    est = _fixation(sim, 0.3, 0.6, 90, noise)
    raw = np.array([g for _, g in est])
    shown = np.array([s.push(t, *g) for t, g in est])[15:]
    assert shown.std(axis=0).max() < 0.35 * raw[15:].std(axis=0).min()
    # Прыжок взгляда на другую сторону экрана точка проходит за пять кадров.
    jump = _fixation(sim, 0.8, 0.3, 10, noise)
    after = [s.push(t + 90 * STEP_US, *g) for t, g in jump]
    target = np.median([g for _, g in jump], axis=0)
    assert math.hypot(*(np.array(after[4]) - target)) < 1.5 * px_for_deg(noise)


def test_sno_alg_eye_02_kernel_intercept_is_not_shrunk():
    # Линейная часть ядерной модели не штрафует сдвиг: постоянная цель
    # восстанавливается без перекоса (независимая проверка шага 28).
    rng = np.random.default_rng(2)
    x = rng.normal(size=(120, len(calib.USED)))
    y = np.column_stack([np.full(120, 960.0), np.full(120, 540.0)])
    m = calib.Kernel((0.1, 0.1), (0.1, 0.1)).fit(x, y)
    pred = m.predict(rng.normal(size=(20, len(calib.USED))))
    assert np.allclose(pred, [960.0, 540.0], atol=0.5)
