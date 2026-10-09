"""Правка `v0.35.1` шага 29: BUG-62 — остаток поправки на голову,
выученный по непонятой фазе движения головы, уводил точку на сантиметры;
BUG-61 — в фазе движения головы непонятно, что делать.

Участник — та же точная синтетическая голова, что в `test_step29`
(`Sim`), но фаза движения головы у него идёт так, как у владельца
09.10.2026: половину фазы голова стоит, а взгляд — на подсказке над
точкой; потом один поворот до 30°, за краем того, что глаз видел на
калибровке, и признаки глаз там искажены; потом короткий кивок.
"""

import math
import queue
import time

import numpy as np
import pytest

from sno_eye import calib, features, selfcheck, synthetic
from test_protocol import Sat
from test_step29 import (H, SCREEN, SCREEN_OPEN, STILL, VALID, W, Sim, acc,
                         qpc, show_points)

T = selfcheck.load_thresholds()


def owner_like(sec):
    """Фаза движения головы, как у владельца: первые 6,6 с голова стоит,
    а взгляд — на подсказке на 8 см выше точки; потом поворот влево до
    30° и обратно, и дальше 15° признаки глаз уводят оценку вниз; потом
    кивок на ±12°."""
    if sec < 6.6:
        return {"look": (0.0, -80.0)}
    if sec < 9.6:
        yaw = -30.0 * math.sin(math.pi * (sec - 6.6) / 3.0)
        return {"yaw": yaw, "err": (0.0, 0.8 * max(0.0, abs(yaw) - 15.0))}
    return {"pitch": 12.0 * math.sin(2 * math.pi * (sec - 9.6) / 2.4)}


def one_side(sec):
    """Честная фаза, но голова ходит только влево: 0 → −10° → 0."""
    return {"yaw": -10.0 * abs(math.sin(math.pi * sec / 3.0))}


def with_head(**over):
    t = {**T, "head": {**T["head"], **over}}
    return t


@pytest.fixture(scope="module")
def owner():
    s = Sim(noise=0.3, seed=11, motion=owner_like)
    s.fit = s.calibrate()
    s.validate()
    return s


@pytest.mark.parametrize("move", [{"yaw": 5.0}, {"yaw": -5.0},
                                  {"yaw": 5.5, "roll": -4.6}])
def test_bug_62_rest_from_a_misunderstood_phase_does_not_move_the_dot(owner, move):
    # Воспроизведение BUG-62: прежде остаток по такой фазе принимался, и
    # после поворота на 5° способ с остатком уходил на 2,6° (геометрия —
    # 0,1°). Теперь остаток себя не доказал — его нет, и способ с
    # остатком совпадает с геометрией.
    r = owner.check(**move)
    assert acc(r, "phase") <= acc(r, "geometry") + 0.05, r["variants"]
    assert acc(r, "geometry") <= 0.6, r["variants"]


def test_bug_62_misunderstood_phase_is_named_in_fit(owner):
    head = owner.fit["head"]
    assert head["moved"] and head["turn_deg"] > 25
    assert head["accepted"] is False
    assert head["reason"] in ("few_frames", "one_side", "no_gain")
    assert not owner.fit["variants"]["phase"]["rest"]
    # Кадры, где взгляд на подсказке, и поворот за пределом в дело не
    # идут: годных кадров — меньше трети фазы.
    assert head["used"] < head["frames"] / 3


def test_bug_62_geometry_is_the_main_way():
    # Сразу — главным способом геометрия: живая точка и итог по ней.
    assert T["head"]["model"] == "geometry"
    s = Sim(noise=0.3, seed=12)
    fit = s.calibrate(kind="quick")
    assert fit["head_model"] == "geometry"
    assert s.cal.model is s.cal.models["geometry"]


def test_bug_62_one_sided_turn_is_not_learned():
    # Голова ходила только влево — прямая продолжилась бы вправо наугад.
    # Ось поворота не учится, наклона не было — остатка нет, хотя
    # остатку было бы что учить (поза в матрице меньше настоящей).
    s = Sim(noise=0.3, seed=13, motion=one_side, pose_gain=0.8)
    fit = s.calibrate()
    head = fit["head"]
    assert head["moved"] and "turn" not in head["axes"]
    assert head["reason"] == "one_side" and not fit["variants"]["phase"]["rest"]


def test_bug_62_rest_is_taken_only_when_it_beats_geometry_on_held_out_seconds():
    # Остатку есть что учить (поза в матрице меньше настоящей) — он
    # доказывает себя на секундах, которых не видел, и принимается.
    s = Sim(noise=0.3, seed=14, pose_gain=0.8)
    fit = s.calibrate()
    head = fit["head"]
    assert head["accepted"] and head["reason"] is None
    p = head["proof"]
    assert p["rest_deg"] < p["geometry_deg"] - max(0.1, 0.1 * p["geometry_deg"])
    r = s.check(yaw=8.0)
    assert acc(r, "phase") < acc(r, "geometry"), r["variants"]
    # Геометрия и так верна — остаток выигрыша не даёт и не берётся, или
    # берётся и почти ничего не меняет.
    s = Sim(noise=0.3, seed=15)
    fit = s.calibrate()
    head = fit["head"]
    assert set(head["proof"]) == {"geometry_deg", "rest_deg"}
    if not head["accepted"]:
        assert head["reason"] == "no_gain"
    r = s.check(yaw=8.0)
    assert abs(acc(r, "phase") - acc(r, "geometry")) <= 0.3, r["variants"]


def test_bug_62_no_gain_means_no_rest():
    # Порог доказательства недостижим — остатка нет при любой фазе.
    s = Sim(noise=0.3, seed=16, pose_gain=0.8,
            thresholds=with_head(prove_min_deg=50.0))
    fit = s.calibrate()
    assert fit["head"]["reason"] == "no_gain"
    assert not fit["variants"]["phase"]["rest"]


def test_bug_62_limits_follow_the_calibrated_eye_range():
    # На экране 527×296 мм с 60 см глаз на точках калибровки ходит на
    # ±20° вбок — поворот ограничен 15°; по высоте — от −6° до 17° от
    # глаз, которые на 6 см выше середины экрана.
    s = Sim(noise=0.0, seed=17)
    s.calibrate(kind="quick", head=False)
    centre = (W / 2, H / 2)
    pts = np.array([(fx * W, fy * H) for fx, fy in
                    [(0.08, 0.08), (0.92, 0.08), (0.08, 0.92), (0.92, 0.92)]])
    lim = calib.head_limits(s.cal.geo, pts, centre, 15.0)
    assert lim["turn"] == (-15.0, 15.0)
    assert lim["tilt"][0] == pytest.approx(-11.4, abs=0.5)
    assert lim["tilt"][1] == pytest.approx(11.8, abs=0.5)
    # Ноутбук 320×200 мм: как у владельца 09.10.2026 — ±12,6° и ±8°.
    small = calib.Screen(1280, 800, 320, 200, 600)
    geo = calib.Geometry(small, calib.HeadSetup(), (0.0, 0.0, 0.0), 0.0, -60.0, 2.0,
                         np.zeros(6))
    pts = np.array([(fx * 1280, fy * 800) for fx, fy in
                    [(0.08, 0.08), (0.92, 0.08), (0.08, 0.92), (0.92, 0.92)]])
    lim = calib.head_limits(geo, pts, (640, 400), 15.0)
    assert lim["turn"][0] == pytest.approx(-12.6, abs=0.3)
    assert lim["turn"][1] == pytest.approx(12.6, abs=0.3)
    assert lim["tilt"][0] == pytest.approx(-7.9, abs=0.3)
    assert lim["tilt"][1] == pytest.approx(8.0, abs=0.3)


def test_bug_62_frames_beyond_the_limits_are_not_used():
    # Кивок на ±14° при пределе ±8° (узкий порог для теста): дальше
    # предела кадры в остаток не идут.
    def nod(sec):
        return {"pitch": 14.0 * math.sin(2 * math.pi * sec / 3.0)}

    s = Sim(noise=0.3, seed=18, motion=nod, pose_gain=0.8,
            thresholds=with_head(max_deg=8.0))
    fit = s.calibrate()
    head = fit["head"]
    assert head["limits"]["tilt"][1] <= 8.0
    # Синус с размахом 14° — дальше 8° почти половина времени.
    assert head["used"] < 0.7 * head["frames"]


# --- BUG-61: где голова, пока идёт фаза движения головы ------------------

def test_bug_61_head_pose_during_the_head_phase():
    s = Sim(noise=0.0, seed=21)
    s.cal.begin(1, "quick", s.t)
    for i, (fx, fy) in enumerate(VALID):
        s.show(f"c{i}", fx * W, fy * H, "calib", 2.0)
    s.off()

    def pose_at(**pose):
        head = synthetic.look_from(0.0, 0.0, STILL["eye"], screen_h_mm=SCREEN.h_mm, **pose)
        face = synthetic.render(head, W, H)
        return features.compute(face.landmarks, face.matrix, W, H)

    # Не фаза головы — ничего.
    assert s.cal.head_live(pose_at(yaw=6.0)) is None
    s.cal.target(calib.Target("head", W / 2, H / 2, "head", s.t))
    s.cur = None
    got = s.cal.head_live(pose_at(yaw=6.0))
    assert got["turn"] == pytest.approx(6.0, abs=0.8)
    assert abs(got["tilt"]) < 0.8 and got["far"] is False
    got = s.cal.head_live(pose_at(pitch=-5.0))
    assert got["tilt"] == pytest.approx(-5.0, abs=0.8) and got["far"] is False
    # Дальше предела — `far`.
    assert s.cal.head_live(pose_at(yaw=20.0))["far"] is True
    assert s.cal.head_live(pose_at(pitch=14.0))["far"] is True
    # Без лица — ничего; точки сменились — тоже.
    assert s.cal.head_live(None) is None
    s.cal.target(calib.Target("off", 0, 0, "off", s.t + 1))
    assert s.cal.head_live(pose_at(yaw=6.0)) is None


def test_bug_61_no_calibration_points_no_pose():
    s = Sim(noise=0.0, seed=22)
    s.cal.begin(1, "quick", s.t)
    s.cal.target(calib.Target("head", W / 2, H / 2, "head", s.t))
    head = synthetic.look_from(0.0, 0.0, STILL["eye"], screen_h_mm=SCREEN.h_mm, yaw=5)
    face = synthetic.render(head, W, H)
    assert s.cal.head_live(features.compute(face.landmarks, face.matrix, W, H)) is None


def test_bug_61_participant_keeps_sweeping_when_the_hint_changes():
    # Приложение шлёт точку фазы заново на смене подсказки — участник
    # продолжает водить головой, а не начинает сначала.
    p = synthetic.Participant(latency_ms=0, noise_deg=0)
    p.target(calib.Target("head", 960, 540, "head", 1_000_000))
    p.target(calib.Target("head", 960, 540, "head", 5_000_000))
    yaw, pitch = p.sweep(1_000_000 + 7_000_000)
    assert yaw == 0.0 and pitch != 0.0


def drain(sat, seconds):
    """Строки спутника за `seconds` — все, без ожидания ответа."""
    end = time.monotonic() + seconds
    got = []
    while time.monotonic() < end:
        try:
            got.append(sat.q.get(timeout=0.1))
        except queue.Empty:
            continue
    sat.lines += got
    return got


@pytest.fixture
def follower(instance_name):
    s = Sat(instance_name, source="synthetic:follow")
    yield s
    s.stop()


def test_bug_61_head_pose_lines_through_the_exchange(follower, tmp_path):
    sat = follower
    sat.send({"cmd": "open", "dir": str(tmp_path / "стенд"), "screen": SCREEN_OPEN,
              "distance_mm": 600, "strip": False, "mode": [1280, 720]})
    sat.reply("open")
    sat.send({"cmd": "calibrate", "attempt": 1, "kind": "quick"})
    sat.reply("calibrate")
    show_points(sat, "calib", "c", 1.2)
    # До фазы головы строк о голове нет.
    assert not [m for m in drain(sat, 0.5) if "hm" in m]
    sat.send({"cmd": "target", "id": "head", "x": 960, "y": 540, "phase": "head",
              "qpc_us": qpc()})
    got = drain(sat, 5.5)
    sat.send({"cmd": "target", "phase": "off", "qpc_us": qpc()})
    poses = [m for m in got if "hm" in m]
    assert len(poses) >= 80
    turns = [m["hm"][0] for m in poses]
    # Участник водит головой на ±9°.
    assert max(turns) > 6 and min(turns) < -6
    assert all(isinstance(m["t"], int) and m["far"] is False for m in poses)
    # Фаза кончилась — строк о голове больше нет.
    drain(sat, 0.3)
    assert not [m for m in drain(sat, 0.5) if "hm" in m]
    sat.send({"cmd": "close"})
    sat.reply("closed")
