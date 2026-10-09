"""Шаг 32 (ET-06): взгляд пишется всю запись — поток `gaze.jsonl`,
перезапуск спутника той же моделью, сторож лица, итог сегмента
(SNO-F-EYE-02, SNO-F-REC-04).

Подставное «приложение» гоняет настоящий `serve` через трубы с
синтетическим участником, который смотрит на показанные точки."""

import json
import math
import time

import numpy as np
import pytest

from sno_eye import calib, faceparts as fp, selfcheck
from sno_eye.gaze import FaceWatch, GazeWriter, repair_tail
from test_protocol import Sat
from test_step28 import SCREEN, POINTS, qpc, show_points


# --- файл потока -------------------------------------------------------------

def test_sno_f_rec_04_repair_tail_continues_numbers(tmp_path):
    path = tmp_path / "gaze.jsonl"
    assert repair_tail(path) == 1
    path.write_bytes(b'{"n":1}\n{"n":2}\n{"n":3}\n{"n":4,"t":')
    # Оборванная строка отрезана, номер продолжает последнюю целую.
    assert repair_tail(path) == 4
    assert path.read_bytes() == b'{"n":1}\n{"n":2}\n{"n":3}\n'
    # Последняя целая строка не читается — номер по предыдущей.
    path.write_bytes('{"n":7}\nмусор\n'.encode('utf-8'))
    assert repair_tail(path) == 8
    path.write_bytes(b"")
    assert repair_tail(path) == 1


def test_sno_f_rec_04_repair_tail_reads_long_files_from_the_end(tmp_path):
    path = tmp_path / "gaze.jsonl"
    lines = [json.dumps({"n": i, "pad": "x" * 200}) for i in range(2000)]
    path.write_text("\n".join(lines) + "\n" + '{"n":2000,', encoding="utf-8")
    assert repair_tail(path) == 2000
    assert path.read_text(encoding="utf-8").endswith('"n": 1999, "pad": "' + "x" * 200 + '"}\n')


def feat_vector(yaw=1.0, pitch=-2.0, roll=0.5, open_l=0.31, open_r=0.29, scale=200.0):
    v = np.zeros(len(fp.FEATURE_NAMES))
    names = fp.FEATURE_NAMES
    v[names.index("yaw")] = yaw
    v[names.index("pitch")] = pitch
    v[names.index("roll")] = roll
    v[names.index("open_l")] = open_l
    v[names.index("open_r")] = open_r
    v[names.index("scale_px")] = scale
    return v


def test_sno_f_rec_04_gaze_line_schema_and_time(tmp_path):
    w = GazeWriter(tmp_path, seg=0, qpc0_us=5_000_000, t0=1200)
    f = feat_vector()
    assert w.add(5_000_000, (100.04, 200.06), True, feat=f, blink=0.1, dist=1.0234) == 1
    assert w.add(5_033_400, (101.0, 201.0), False, feat=f, blink=0.9) == 2
    assert w.add(5_066_700, None, False, feat=None) == 3
    stats = w.close()
    rows = [json.loads(line) for line in (tmp_path / "gaze.jsonl").read_text().splitlines()]
    assert [r["n"] for r in rows] == [1, 2, 3]
    assert [r["t"] for r in rows] == [1200, 1233, 1267]
    a, b, c = rows
    assert set(a) == {"n", "t", "x", "y", "ok", "conf", "dist", "yaw", "pitch", "roll",
                      "open_l", "open_r", "seg"}
    assert (a["x"], a["y"], a["ok"], a["conf"], a["dist"]) == (100.0, 200.1, True, 0.9, 1.023)
    assert (a["yaw"], a["pitch"], a["roll"], a["open_l"], a["open_r"]) == (1.0, -2.0, 0.5,
                                                                            0.31, 0.29)
    # Негодный кадр: взгляда нет, поза есть; кадр без лица — ничего.
    assert (b["x"], b["y"], b["ok"]) == (None, None, False)
    assert b["yaw"] == 1.0 and b["conf"] == 0.1
    assert (c["x"], c["yaw"], c["conf"], c["dist"]) == (None, None, 0.0, None)
    assert stats["lines"] == 3 and stats["ok"] == 1 and stats["valid_share"] == 0.3333
    assert (stats["first_n"], stats["last_n"]) == (1, 3)

    # Второй сегмент дописывает тот же файл и продолжает номера.
    w2 = GazeWriter(tmp_path, seg=1, qpc0_us=5_000_000, t0=1200)
    assert w2.add(9_000_000, (1.0, 2.0), True, feat=f) == 4
    w2.close()
    rows = [json.loads(line) for line in (tmp_path / "gaze.jsonl").read_text().splitlines()]
    assert [r["n"] for r in rows] == [1, 2, 3, 4] and rows[-1]["seg"] == 1


def test_sno_f_eye_02_face_watch_says_lost_after_a_second_and_back():
    w = FaceWatch()
    assert w.push(0, True) is None
    assert w.push(100_000, False) is None
    assert w.push(1_000_000, False) is None
    lost = w.push(1_100_000, False)
    assert lost == {"face": "lost", "t": 1_100_000, "since": 100_000}
    assert w.push(1_500_000, False) is None
    assert w.push(2_000_000, True) == {"face": "back", "t": 2_000_000, "ms": 1900}
    # Короткая потеря (моргнул, отвернулся на полсекунды) — не потеря.
    assert w.push(2_100_000, False) is None
    assert w.push(2_600_000, True) is None


# --- калибровка из файла -----------------------------------------------------

def test_sno_f_eye_02_calibration_restores_the_same_model(follower_cal):
    cal, folder = follower_cal
    data = json.loads((folder / "calibration.json").read_text(encoding="utf-8"))
    back = calib.Calibration.restore(data, cal.screen, selfcheck.load_thresholds())
    assert back.restored and back.head_model == cal.head_model
    assert set(back.models) == set(cal.models)
    assert back.scale_ref == pytest.approx(cal.scale_ref)
    assert len(back.attempts) == len(cal.attempts)
    assert back.attempts[-1].validation == cal.attempts[-1].validation
    feats = [s.feat for s in list(cal._frames) if s.feat is not None][:50]
    for f in feats:
        a = cal.predict(f)
        b = back.predict(f)
        assert a == pytest.approx(b, abs=1e-6)


def test_sno_f_eye_02_restore_without_model_says_so():
    with pytest.raises(calib.CalibrationError) as e:
        calib.Calibration.restore({"attempts": []}, None, selfcheck.load_thresholds())
    assert e.value.code == "model_missing"


@pytest.fixture
def follower_cal(tmp_path):
    """Калибровка синтетического участника на сервере в этом процессе."""
    from sno_eye.protocol import Server
    from sno_eye.runtime import Runtime
    from test_robustness import FakeOut, cmd

    out = FakeOut()
    s = Server(Runtime("synthetic:follow"), out)
    folder = tmp_path / "eye"
    s.handle(cmd(cmd="open", dir=str(folder), screen=SCREEN, distance_mm=600,
                 strip=False, mode=[1280, 720]))
    assert out.last("reply")["reply"] == "open"
    s.handle(cmd(cmd="calibrate", attempt=1, kind="quick"))
    for i, (fx, fy) in enumerate(POINTS):
        s.handle(cmd(cmd="target", id=f"c{i}", x=fx * 1920, y=fy * 1080, phase="calib",
                     qpc_us=qpc()))
        time.sleep(1.2)
    s.handle(cmd(cmd="target", phase="off", qpc_us=qpc()))
    s.handle(cmd(cmd="fit"))
    assert out.last("reply")["reply"] == "fit", out.msgs[-3:]
    cal = s.calib
    yield cal, folder
    s.handle(cmd(cmd="close"))
    s.shutdown()


# --- через обмен -------------------------------------------------------------

@pytest.fixture
def follower(instance_name):
    s = Sat(instance_name, source="synthetic:follow")
    yield s
    s.stop()


def gaze_rows(folder):
    return [json.loads(line) for line in
            (folder / "gaze.jsonl").read_text(encoding="utf-8").splitlines()]


def test_sno_f_rec_04_gaze_all_recording_and_restart_with_the_same_model(
        follower, instance_name, tmp_path):
    sat = follower
    folder = tmp_path / "Записи" / ".current" / "sno2026_I_1234567_abcdef" / "eye"
    q0 = qpc()
    sat.send({"cmd": "open", "dir": str(folder), "screen": SCREEN, "distance_mm": 600,
              "strip": False, "mode": [1280, 720], "seg": 0, "qpc0_us": q0, "t0": 5000})
    sat.reply("open")
    # Без модели поток взгляда не начинается.
    sat.send({"cmd": "gaze", "on": True})
    err = sat.wait(lambda m: m.get("cmd") == "gaze")
    assert err["error"] == "bad_command" and "сначала fit" in err["text"]
    sat.send({"cmd": "calibrate", "attempt": 1, "kind": "quick"})
    sat.reply("calibrate")
    show_points(sat, "calib", "c", 1.2)
    sat.send({"cmd": "fit"})
    assert sat.reply("fit", timeout=30)["reply"] == "fit"

    # Участник смотрит в одну точку; поток взгляда идёт.
    sat.send({"cmd": "target", "id": "look", "x": 600, "y": 400, "phase": "calib",
              "qpc_us": qpc()})
    sat.send({"cmd": "gaze", "on": True})
    on = sat.reply("gaze")
    assert on["on"] is True and on["n"] == 1
    time.sleep(2.0)
    sat.send({"cmd": "close"})
    summary = sat.reply("closed")["summary"]
    calibration = (folder / "calibration.json").read_bytes()
    rows = gaze_rows(folder)
    assert len(rows) >= 50, len(rows)
    assert [r["n"] for r in rows] == list(range(1, len(rows) + 1))
    assert all(r["seg"] == 0 for r in rows)
    ts = [r["t"] for r in rows]
    assert ts == sorted(ts) and ts[0] >= 5000
    ok = [r for r in rows if r["ok"]]
    assert len(ok) / len(rows) > 0.9
    last = ok[-1]
    assert math.hypot(last["x"] - 600, last["y"] - 400) < 150
    assert summary["gaze"]["lines"] == len(rows)
    assert summary["gaze"]["valid_share"] > 0.9
    assert summary["seg"] == 0
    saved = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    assert saved["gaze"]["lines"] == len(rows)

    # Спутник поднят заново: следующий сегмент, та же модель, номера дальше.
    sat.stop()
    sat2 = Sat(instance_name, source="synthetic:follow")
    try:
        sat2.send({"cmd": "open", "dir": str(folder), "screen": SCREEN,
                   "distance_mm": 600, "strip": False, "mode": [1280, 720], "seg": 1,
                   "qpc0_us": q0, "t0": 5000,
                   "calibration": str(folder / "calibration.json")})
        sat2.reply("open")
        # Участник смотрит в другую точку — её показывает проверка: точки
        # принимаются только в начатую калибровку или проверку.
        sat2.send({"cmd": "check", "n": 1})
        sat2.reply("check")
        sat2.send({"cmd": "target", "id": "look", "x": 1200, "y": 700, "phase": "check",
                   "qpc_us": qpc()})
        sat2.send({"cmd": "gaze", "on": True})
        assert sat2.reply("gaze")["n"] == len(rows) + 1
        time.sleep(1.5)
        sat2.send({"cmd": "close"})
        summary2 = sat2.reply("closed")["summary"]
    finally:
        sat2.stop()
    rows2 = gaze_rows(folder)
    assert [r["n"] for r in rows2] == list(range(1, len(rows2) + 1))
    assert {r["seg"] for r in rows2[len(rows):]} == {1}
    ok2 = [r for r in rows2[len(rows):] if r["ok"]]
    assert math.hypot(ok2[-1]["x"] - 1200, ok2[-1]["y"] - 700) < 150
    assert summary2["calibration"]["restored"] is True
    assert (folder / "summary.1.json").exists()
    assert (folder / "features.1.bin").exists()
    # Файл калибровки — тот, что оставил первый спутник.
    assert (folder / "calibration.json").read_bytes() == calibration


def test_sno_f_eye_02_restart_without_calibration_file_keeps_camera_free(follower, tmp_path):
    sat = follower
    sat.send({"cmd": "open", "dir": str(tmp_path / "eye"), "screen": SCREEN,
              "distance_mm": 600, "strip": False, "mode": [1280, 720], "seg": 1,
              "calibration": str(tmp_path / "нет.json")})
    err = sat.wait(lambda m: m.get("cmd") == "open")
    assert err["error"] == "model_missing"
    # Камера свободна — открывается обычным open.
    sat.send({"cmd": "open", "write": False, "screen": SCREEN, "distance_mm": 600,
              "mode": [1280, 720]})
    assert sat.reply("open")["reply"] == "open"
    sat.send({"cmd": "close"})
    sat.reply("closed")


def test_sno_f_eye_06_end_check_on_restored_model_knows_start_accuracy(follower, tmp_path):
    sat = follower
    folder = tmp_path / "eye"
    sat.send({"cmd": "open", "dir": str(folder), "screen": SCREEN, "distance_mm": 600,
              "strip": False, "mode": [1280, 720]})
    sat.reply("open")
    sat.send({"cmd": "calibrate", "attempt": 1, "kind": "quick"})
    sat.reply("calibrate")
    show_points(sat, "calib", "c", 1.2)
    sat.send({"cmd": "fit"})
    sat.reply("fit", timeout=30)
    show_points(sat, "validate", "v", 1.2)
    sat.send({"cmd": "validate"})
    start = sat.reply("validate", timeout=30)["accuracy_deg"]
    sat.send({"cmd": "close"})
    sat.reply("closed")
    sat.send({"cmd": "open", "dir": str(folder), "screen": SCREEN, "distance_mm": 600,
              "strip": False, "mode": [1280, 720], "seg": 1,
              "calibration": str(folder / "calibration.json")})
    sat.reply("open")
    sat.send({"cmd": "check", "n": 1})
    sat.reply("check")
    show_points(sat, "check", "k", 1.2)
    sat.send({"cmd": "checked"})
    res = sat.reply("checked", timeout=30)
    assert res["start_deg"] == start
    assert res["accuracy_deg"] < 3.5, res
    sat.send({"cmd": "close"})
    sat.reply("closed")
    checks = json.loads((folder / "checks.json").read_text(encoding="utf-8"))
    assert checks[-1]["accuracy_deg"] == res["accuracy_deg"]
