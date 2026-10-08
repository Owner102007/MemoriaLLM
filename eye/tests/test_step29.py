"""Шаг 29: BUG-60 — точка взгляда уходила на сантиметры, когда менялась
поза головы. Поправка на голову, выученная по точкам калибровки, учила
шум; теперь глаза учатся при голове на месте, а голова переносится
геометрией (и остатком по фазе движения головы). Проверка точности без
новой калибровки меряет все три способа (SNO-ALG-EYE-02, SNO-F-EYE-03).

Участник — точная синтетическая голова (`synthetic.look_from`): глаза в
известном месте перед экраном, голова повёрнута, глаз в голове смотрит
туда, куда остаётся. Как у настоящей модели, место лица в кадре чуть идёт
за взглядом (уголки глаз сдвигаются вместе с глазом) — на этом прежняя
поправка и училась не тому.
"""

import json
import math
import time

import numpy as np
import pytest

from sno_eye import calib, features, selfcheck, synthetic
from test_protocol import Sat

T = selfcheck.load_thresholds()
W, H = 1920, 1080
SCREEN = calib.Screen(W, H, 527, 296, 600)
CALIB = [(0.08, 0.08), (0.5, 0.08), (0.92, 0.08), (0.08, 0.5), (0.5, 0.5),
         (0.92, 0.5), (0.08, 0.92), (0.5, 0.92), (0.92, 0.92),
         (0.29, 0.29), (0.71, 0.29), (0.29, 0.71), (0.71, 0.71)]
VALID = [(a, b) for b in (0.2, 0.5, 0.8) for a in (0.2, 0.5, 0.8)]
PATH = {"cx": W / 2, "cy": H / 2, "ax": 0.4 * W, "ay": 0.35 * H,
        "tx_ms": 16000, "ty_ms": 10667}
STEP_US = 33_333
T0 = 1_000_000_000
EYE0 = (0.0, -60.0, 600.0)
STILL = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "eye": EYE0}


class Sim:
    """Сеанс синтетического участника со своим временем: калибровка,
    проверка сразу после неё и проверки после того, как голова ушла.

    `artifact` — на сколько пикселей у края экрана место лица в кадре
    идёт за взглядом; `pose_gain` — во сколько раз поза в матрице меньше
    настоящей; `sweep` — водит ли участник головой в фазе движения
    головы."""

    def __init__(self, noise=0.3, seed=1, artifact=3.0, pose_gain=1.0, sweep=True,
                 pivot=None):
        self.cal = calib.Calibration(SCREEN, T, frame=(W, H))
        # Голова поворачивается вокруг шеи: центр поворота — `pivot` мм от
        # глаз (x вправо, y вниз, z к экрану), и глаза при повороте
        # сдвигаются. `None` — глаза стоят на месте.
        self.pivot = None if pivot is None else np.asarray(pivot, dtype=np.float64)
        self.rng = np.random.default_rng(seed)
        self.t = T0
        self.noise = noise
        self.artifact = artifact
        self.pose_gain = pose_gain
        self.sweep = sweep
        self.pose = dict(STILL)
        self.cur: calib.Target | None = None

    def frame(self):
        sec = (self.t - T0) / 1e6
        cur = self.cur
        if cur is None:
            x, y = W / 2, H / 2
        elif cur.phase == "pursuit":
            x, y = calib.path_at(cur.path, (self.t - 70_000 - cur.qpc_us) / 1e6)
        else:
            x, y = cur.x, cur.y
        xm, ym = SCREEN.mm(x, y)
        p = self.pose
        # На точках голова почти не двигается — как у владельца, ±0,6°.
        yaw = p["yaw"] + 0.6 * math.sin(sec * 0.31)
        pitch = p["pitch"] + 0.6 * math.sin(sec * 0.23)
        if cur is not None and cur.phase == "head" and self.sweep:
            sy, sp = synthetic.head_sweep((self.t - cur.qpc_us) / 1e6)
            yaw, pitch = yaw + sy, pitch + sp
        noise = tuple(self.rng.normal(0, self.noise, 2))
        shift = (-self.artifact * xm / (SCREEN.w_mm / 2),
                 self.artifact * ym / (SCREEN.h_mm / 2))
        eye = p["eye"]
        if self.pivot is not None:
            r = synthetic._TO_PERSON @ synthetic.rotation(yaw, pitch, p["roll"]) \
                @ synthetic._TO_PERSON
            d = (np.eye(3) - r) @ self.pivot
            eye = (eye[0] + d[0], eye[1] + d[1], eye[2] - d[2])
        head = synthetic.look_from(xm, ym, eye, screen_h_mm=SCREEN.h_mm,
                                   yaw=yaw, pitch=pitch, roll=p["roll"], noise=noise,
                                   shift_px=shift, pose_gain=self.pose_gain)
        face = synthetic.render(head, W, H)
        self.cal.add(self.t, features.compute(face.landmarks, face.matrix, W, H), True)
        self.t += STEP_US

    def show(self, tid, x, y, phase, seconds, path=None):
        ev = calib.Target(tid, x, y, phase, self.t, path)
        self.cur = ev
        self.cal.target(ev)
        for _ in range(round(seconds * 30)):
            self.frame()

    def off(self):
        self.cur = None
        self.cal.target(calib.Target("off", 0, 0, "off", self.t))

    def calibrate(self, kind="full", head=True):
        self.cal.begin(1, kind, self.t)
        for i, (fx, fy) in enumerate(CALIB if kind == "full" else VALID):
            self.show(f"c{i}", fx * W, fy * H, "calib", 2.0)
        self.off()
        if head:
            self.show("head", W / 2, H / 2, "head", 12.0)
            self.off()
        if kind == "full":
            self.show("pursuit", W / 2, H / 2, "pursuit", 20.0, PATH)
            self.off()
        return self.cal.fit()

    def validate(self):
        for i, (fx, fy) in enumerate(VALID):
            self.show(f"v{i}", fx * W, fy * H, "validate", 1.5)
        self.off()
        return self.cal.validate()

    def check(self, n=1, **pose):
        self.pose = dict(STILL, **pose)
        self.cal.begin_check(n, self.t)
        for i, (fx, fy) in enumerate(VALID):
            self.show(f"k{i}", fx * W, fy * H, "check", 1.5)
        self.off()
        try:
            return self.cal.check_result()
        finally:
            self.pose = dict(STILL)


def acc(result, variant):
    return result["variants"][variant]["accuracy_deg"]


MOVES = {
    "поворот": {"yaw": 8.0},
    "наклон": {"pitch": -6.0},
    "к плечу": {"roll": 4.0},
    "сдвиг": {"eye": (40.0, -80.0, 600.0)},
    "ближе": {"eye": (0.0, -60.0, 540.0)},
    "всё разом": {"yaw": 6.0, "pitch": 4.0, "roll": -3.0, "eye": (-30.0, -40.0, 650.0)},
}


@pytest.fixture(scope="module")
def sim():
    s = Sim(noise=0.3, seed=1)
    s.calibrate()
    s.validate()
    return s


def test_bug_60_learned_head_correction_drifts_when_the_head_moves(sim):
    # Воспроизведение BUG-60: прежняя поправка выучена по точкам, где
    # голова стоит, а место лица чуть ходит за взглядом. Голова ушла — и
    # прежний способ уходит на градусы; сдвиг на 4 см — дальше всего.
    moved = sim.check(**MOVES["сдвиг"])
    assert acc(moved, "learned") > 2.5, moved["variants"]
    both = sim.check(**MOVES["всё разом"])
    assert acc(both, "learned") > 2.5, both["variants"]


@pytest.mark.parametrize("move", list(MOVES))
def test_bug_60_geometry_and_phase_hold_when_the_head_moves(sim, move):
    # Голова повернулась, наклонилась, сдвинулась, приблизилась — оценка
    # геометрией и с остатком не уходит дальше 1° сверх заложенного шума.
    r = sim.check(**MOVES[move])
    assert acc(r, "geometry") <= 1.0 + sim.noise, r["variants"]
    assert acc(r, "phase") <= 1.0 + sim.noise, r["variants"]
    # Главные числа итога — у способа из порогов.
    assert r["head_model"] == T["head"]["model"] == "phase"
    assert r["accuracy_deg"] == acc(r, "phase")


def test_bug_60_still_head_all_three_are_good(sim):
    r = sim.check()
    for variant in calib.HEAD_MODELS:
        assert acc(r, variant) < 0.8, r["variants"]
    assert r["start_deg"] == sim.cal.attempt.validation["accuracy_deg"]


def test_bug_60_head_report_names_the_move(sim):
    r = sim.check(**MOVES["поворот"])
    assert r["head"]["turn_deg"] == pytest.approx(8.0, abs=1.0)
    assert abs(r["head"]["tilt_deg"]) < 1.0
    r = sim.check(**MOVES["сдвиг"])
    assert r["head"]["dx_mm"] == pytest.approx(40.0, abs=2.0)
    assert r["head"]["dy_mm"] == pytest.approx(-20.0, abs=2.0)
    r = sim.check(**MOVES["ближе"])
    assert r["head"]["dz_pct"] == pytest.approx(-10.0, abs=1.0)
    r = sim.check(**MOVES["наклон"])
    # Голова вверх — наклон вниз отрицательный.
    assert r["head"]["tilt_deg"] == pytest.approx(-6.0, abs=1.0)


def test_bug_60_check_does_not_change_the_model(sim):
    before = json.dumps(sim.cal.model.to_json())
    sim.check(**MOVES["поворот"])
    assert json.dumps(sim.cal.model.to_json()) == before


def test_bug_60_head_phase_is_reported_in_fit():
    s = Sim(noise=0.3, seed=2)
    fit = s.calibrate(kind="quick")
    head = fit["head"]
    assert head["moved"] and head["used"] >= 200
    assert head["turn_deg"] > 12 and head["tilt_deg"] > 9
    assert fit["head_model"] == "phase" and fit["variants"]["phase"]["rest"]
    # Живая точка — по способу из порогов.
    assert s.cal.model is s.cal.models["phase"]


def test_bug_60_without_head_movement_rest_is_geometry():
    # Фазы движения головы не было — остатка нет, и способ с остатком
    # совпадает с геометрией.
    s = Sim(noise=0.3, seed=3)
    fit = s.calibrate(head=False)
    assert fit["head"]["moved"] is False and fit["head"]["frames"] == 0
    assert not fit["variants"]["phase"]["rest"]
    r = s.check(**MOVES["всё разом"])
    assert acc(r, "phase") == acc(r, "geometry")
    # Фаза была, но голова стояла — тоже без остатка.
    s = Sim(noise=0.3, seed=4, sweep=False)
    fit = s.calibrate()
    assert fit["head"]["frames"] > 300 and fit["head"]["moved"] is False
    assert not fit["variants"]["phase"]["rest"]


def test_bug_60_rest_stays_near_geometry_when_geometry_is_right(sim):
    # Геометрия верна — остаток почти ничего не прибавляет: способы
    # расходятся меньше чем на 0,3°.
    for move in ("поворот", "наклон", "всё разом"):
        r = sim.check(**MOVES[move])
        assert abs(acc(r, "phase") - acc(r, "geometry")) <= 0.3, (move, r["variants"])


def test_bug_60_rest_fixes_what_geometry_does_not_know():
    # Поза в матрице меньше настоящей (MediaPipe меряет её с погрешностью):
    # геометрия недокручивает и уходит, остаток по фазе движения головы
    # это возвращает.
    s = Sim(noise=0.3, seed=5, pose_gain=0.8)
    s.calibrate()
    r = s.check(**MOVES["поворот"])
    assert acc(r, "geometry") > 0.9, r["variants"]
    assert acc(r, "phase") < 0.6, r["variants"]
    r = s.check(**MOVES["наклон"])
    assert acc(r, "phase") < 0.6, r["variants"]


# Шея: центр поворота на 10 см позади глаз и на 8 см ниже.
NECK = (0.0, 80.0, -100.0)


@pytest.mark.parametrize("move", ["сдвиг", "выше", "ближе", "поворот", "всё разом"])
def test_bug_60_rest_does_not_spoil_a_pure_shift(move):
    # Независимая проверка шага 29: в фазе движения голова поворачивается
    # вокруг шеи, глаза сдвигаются в ногу с поворотом, и остаток по сдвигам
    # портил чистый сдвиг головы (сдвиг на 4 см — 1,07° против 0,20° у
    # геометрии). Остаток учится только по поворотам; поза в матрице к
    # тому же меньше настоящей, чтобы остатку было что учить.
    moves = {**MOVES, "выше": {"eye": (0.0, -90.0, 600.0)},
             "ближе": {"eye": (0.0, -60.0, 540.0)}}
    s = Sim(noise=0.3, seed=7, pose_gain=0.8, pivot=NECK)
    fit = s.calibrate()
    assert fit["variants"]["phase"]["rest"]
    r = s.check(**moves[move])
    assert acc(r, "phase") <= 1.0 + s.noise, r["variants"]
    if move in ("сдвиг", "выше", "ближе"):
        assert acc(r, "phase") <= acc(r, "geometry") + 0.3, r["variants"]


def test_bug_60_geometry_round_trip():
    # Перенос точки к голове кадра и обратно — та же точка.
    s = Sim(noise=0.0, seed=6)
    s.calibrate(kind="quick", head=False)
    geo = s.cal.geo
    head = synthetic.look_from(10, 20, (30.0, -40.0, 560.0), screen_h_mm=SCREEN.h_mm,
                               yaw=7, pitch=-5, roll=3)
    face = synthetic.render(head, W, H)
    x = features.compute(face.landmarks, face.matrix, W, H)[calib.USED_IDX]
    p0 = np.array([[300.0, 200.0], [1500.0, 900.0]])
    xs = np.vstack([x, x])
    back = geo.inverse(geo.forward(p0, xs), xs)
    assert np.allclose(back, p0, atol=1e-6)


def test_bug_60_model_survives_json(sim):
    sim.check()
    data = json.loads(json.dumps(sim.cal.to_json()))
    assert data["head_model"] == "phase" and set(data["variants"]) == set(calib.HEAD_MODELS)
    assert data["model"]["kind"] == "head" and data["model"]["label"] == "phase"
    assert data["setup"] == {"frame": [W, H], "iod_mm": 90.0, "camera_above_mm": 8.0}
    assert data["schema"] == "sno2026-eyecal/2"
    assert data["checks"] and data["checks"][-1]["result"]["n"] == 1
    head = synthetic.look_from(10, 20, (20.0, -50.0, 580.0), screen_h_mm=SCREEN.h_mm, yaw=4)
    face = synthetic.render(head, W, H)
    x = features.compute(face.landmarks, face.matrix, W, H)[calib.USED_IDX]
    for name in calib.HEAD_MODELS:
        m = calib.model_from_json(data["variants"][name])
        assert np.allclose(m.predict(x), sim.cal.models[name].predict(x))


def test_bug_60_check_needs_a_model_and_a_start():
    cal = calib.Calibration(SCREEN, T, frame=(W, H))
    with pytest.raises(calib.CalibrationError):
        cal.begin_check(1, 0)
    with pytest.raises(calib.CalibrationError):
        cal.check_result()


def test_bug_60_thresholds_head_section():
    h = T["head"]
    assert h["model"] in calib.HEAD_MODELS
    assert h["iod_mm"] == 90 and h["camera_above_mm"] == 8
    assert 0 < h["alpha"] < 1 and h["min_frames"] > 0


# --- через обмен ------------------------------------------------------------

SCREEN_OPEN = {"w": 1920, "h": 1080, "w_mm": 527, "h_mm": 296}
POINTS = [(0.2, 0.2), (0.5, 0.2), (0.8, 0.2), (0.2, 0.5), (0.5, 0.5), (0.8, 0.5),
          (0.2, 0.8), (0.5, 0.8), (0.8, 0.8)]


def qpc():
    return time.perf_counter_ns() // 1000


def show_points(sat, phase, prefix, seconds):
    for i, (fx, fy) in enumerate(POINTS):
        sat.send({"cmd": "target", "id": f"{prefix}{i}", "x": fx * 1920, "y": fy * 1080,
                  "phase": phase, "qpc_us": qpc()})
        time.sleep(seconds)
    sat.send({"cmd": "target", "phase": "off", "qpc_us": qpc()})


@pytest.fixture
def follower(instance_name):
    s = Sat(instance_name, source="synthetic:follow")
    yield s
    s.stop()


def test_bug_60_head_phase_and_check_through_the_exchange(follower, tmp_path):
    sat = follower
    folder = tmp_path / "Стенд" / "проба"
    sat.send({"cmd": "open", "dir": str(folder), "screen": SCREEN_OPEN, "distance_mm": 600,
              "strip": False, "mode": [1280, 720]})
    assert sat.reply("open")["frame"] == [1280, 720]
    # Проверка — только с моделью.
    sat.send({"cmd": "check", "n": 1})
    err = sat.wait(lambda m: m.get("cmd") == "check")
    assert err["error"] == "bad_command" and "сначала fit" in err["text"]

    sat.send({"cmd": "calibrate", "attempt": 1, "kind": "quick"})
    sat.reply("calibrate")
    show_points(sat, "calib", "c", 1.2)
    # Фаза движения головы: участник водит головой, глядя в середину.
    sat.send({"cmd": "target", "id": "head", "x": 960, "y": 540, "phase": "head",
              "qpc_us": qpc()})
    time.sleep(9.0)
    sat.send({"cmd": "target", "phase": "off", "qpc_us": qpc()})
    sat.send({"cmd": "samples", "phase": "head"})
    s = sat.reply("samples")
    assert s["phase"] == "head" and s["face"] == 1.0 and s["short"] == []
    assert s["counts"]["head"] >= 150
    sat.send({"cmd": "fit"})
    fit = sat.reply("fit", timeout=30)
    assert fit["head_model"] == "phase" and fit["head"]["moved"] is True
    assert set(fit["variants"]) == {"learned", "geometry", "phase"}

    sat.send({"cmd": "check", "n": 1})
    assert sat.reply("check")["n"] == 1
    show_points(sat, "check", "k", 1.2)
    sat.send({"cmd": "checked"})
    r = sat.reply("checked", timeout=30)
    assert r["n"] == 1 and len(r["points"]) == 9
    assert set(r["variants"]) == {"learned", "geometry", "phase"}
    assert r["accuracy_deg"] == r["variants"]["phase"]["accuracy_deg"] < 3.0
    assert set(r["head"]) == {"turn_deg", "tilt_deg", "roll_deg", "dx_mm", "dy_mm", "dz_pct"}
    assert r["start_deg"] is None   # проверки сразу после калибровки не было
    checks = json.loads((folder / "checks.json").read_text(encoding="utf-8"))
    assert [c["n"] for c in checks] == [1]

    # Итог той же проверки можно спросить ещё раз — тот же номер.
    sat.send({"cmd": "checked"})
    assert sat.reply("checked", timeout=30)["n"] == 1
    sat.send({"cmd": "close"})
    sat.reply("closed")
    data = json.loads((folder / "calibration.json").read_text(encoding="utf-8"))
    assert data["model"]["kind"] == "head"
    assert data["checks"][0]["check"] == 1
    assert data["setup"]["frame"] == [1280, 720]
    assert [t["phase"] for t in data["attempts"][0]["targets"]].count("head") == 1
