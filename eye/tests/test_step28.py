"""Шаг 28: BUG-58 (самопроверка говорит, кто упёрся в частоту, и не
уходит в 720p зря) и калибровка через обмен (SNO-ALG-EYE-02,
SNO-ALG-EYE-03) — подставное «приложение» гоняет спутник с синтетическим
участником, который смотрит на точки."""

import json
import math
import time

import pytest

from sno_eye import calib, selfcheck
from sno_eye.protocol import Server
from sno_eye.runtime import Runtime
from test_protocol import Sat
from test_robustness import FakeOut, cmd, wait_no_capture

T = selfcheck.load_thresholds()
GOOD_M = {
    "satellite": True, "camera": "ok", "width": 1920, "height": 1080,
    "fps": 29.5, "face_share": 0.99, "iris_px": 22.0, "light": 120.0,
    "backlight": 1.1, "glare": 0.0, "position": 0.05,
    "disk_free_bytes": 50e9, "cpu_percent": 20.0,
}


def fps_row(**m):
    res = selfcheck.evaluate({**GOOD_M, **m}, T)
    return [r for r in res["checks"] if r["id"] == "fps"][0]


# --- BUG-58 -----------------------------------------------------------------

def test_bug_58_camera_itself_slow_says_light():
    # Камера сама даёт 20 к/с: пропусков нет, кадр обрабатывается 12 мс
    # из 50 — ПК ни при чём.
    row = fps_row(fps=20.0, camera_fps=20.0, drop_share=0.0, proc_ms=12.0)
    assert row["verdict"] == "fail"
    assert row["text"] == ("Камера сама даёт 20.0 к/с — ей мало света: "
                           "поставьте лампу перед лицом")
    assert "ПК" not in row["text"]


def test_bug_58_pc_too_slow_says_pc():
    row = fps_row(fps=16.0, camera_fps=30.0, drop_share=0.45, proc_ms=60.0)
    assert row["verdict"] == "fail" and row["text"] == "ПК не успевает: 16.0 к/с"
    # Пропусков нет, но обработка съедает почти весь промежуток — тоже ПК.
    row = fps_row(fps=20.0, camera_fps=20.0, drop_share=0.0, proc_ms=45.0)
    assert row["text"] == "ПК не успевает: 20.0 к/с"


def test_bug_58_warn_names_the_cause_too():
    assert "мало света" in fps_row(fps=25.5, camera_fps=25.5, drop_share=0.0,
                                   proc_ms=10.0)["text"]
    assert "ПК едва успевает" in fps_row(fps=25.5, camera_fps=30.0,
                                         drop_share=0.15, proc_ms=38.0)["text"]
    # Годится — просто частота.
    assert fps_row(fps=29.5, camera_fps=30, drop_share=0, proc_ms=10)["text"] == \
        "Частота 29.5 к/с"


def test_bug_58_unknown_cause_keeps_old_words():
    # Замер без новых чисел (самопроверка прежней версии в месте записи).
    assert fps_row(fps=20.0)["text"] == "Мало света или слабый ПК: 20.0 к/с"


def test_bug_58_thresholds_file():
    assert T["mode_switch_gain"] == 1.15
    assert T["fps_limit"] == {"drop_share": 0.05, "proc_share": 0.8}


def server(source):
    out = FakeOut()
    return Server(Runtime(source), out), out


def test_bug_58_dim_camera_stays_1080p_and_says_light(tmp_path):
    # Камера в тусклом свете: 20 к/с и в 1080p, и в 720p — 720p ничего не
    # прибавил, остаётся 1080p, а слова — про свет.
    s, out = server("synthetic:dim")
    s.handle(cmd(cmd="selfcheck", seconds=1.2, warmup=0.2, dir=str(tmp_path)))
    res = out.last("reply")
    m = res["measures"]
    assert [m["width"], m["height"]] == [1920, 1080]
    assert [t["mode"] for t in m["tried"]] == [[1920, 1080], [1280, 720]]
    rows = {r["id"]: r for r in res["checks"]}
    assert rows["fps"]["text"].startswith("Камера сама даёт")
    assert rows["mode"]["verdict"] == "good"
    stages = [msg.get("stage") for msg in out.msgs if msg.get("progress") == "selfcheck"]
    assert "switch" in stages and "keep" in stages
    # open без режима берёт режим самопроверки — 1080p.
    s.handle(cmd(cmd="open", write=False))
    assert out.last("reply")["frame"] == [1920, 1080]
    s.handle(cmd(cmd="close"))
    s.shutdown()
    assert wait_no_capture()


def test_bug_58_slow_pc_goes_720p_and_says_pc(tmp_path):
    # Слабый ПК: 1080p обрабатывается 100 мс, 720p — 44 мс: 720p дал
    # заметно больше кадров и берётся, а слова — про ПК.
    s, out = server("synthetic:slowproc")
    s.handle(cmd(cmd="selfcheck", seconds=1.5, warmup=0.3, dir=str(tmp_path)))
    res = out.last("reply")
    m = res["measures"]
    assert [m["width"], m["height"]] == [1280, 720]
    rows = {r["id"]: r for r in res["checks"]}
    assert rows["fps"]["text"].startswith("ПК не успевает"), rows["fps"]
    assert m["drop_share"] > 0.05
    s.shutdown()


def test_bug_58_slow_camera_mode_still_switches(tmp_path):
    # Камера, которая в 1080p даёт 20 к/с, а в 720p — 30: 720p берётся,
    # как и прежде (Т24, Т27).
    s, out = server("synthetic:slow")
    s.handle(cmd(cmd="selfcheck", seconds=1, warmup=0.2))
    m = out.last("reply")["measures"]
    assert [m["width"], m["height"]] == [1280, 720]
    s.shutdown()


# --- калибровка через обмен --------------------------------------------------

SCREEN = {"w": 1920, "h": 1080, "w_mm": 527, "h_mm": 296}
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


def test_sno_alg_eye_02_quick_calibration_live_and_file(follower, tmp_path):
    sat = follower
    folder = tmp_path / "Стенд" / "проба"
    sat.send({"cmd": "open", "dir": str(folder), "screen": SCREEN, "distance_mm": 600,
              "strip": False, "mode": [1280, 720]})
    assert sat.reply("open")["frame"] == [1280, 720]
    sat.send({"cmd": "calibrate", "attempt": 1, "kind": "quick"})
    assert sat.reply("calibrate")["attempt"] == 1
    show_points(sat, "calib", "c", 1.3)
    sat.send({"cmd": "samples", "phase": "calib"})
    s = sat.reply("samples")
    assert s["short"] == [] and s["face"] == 1.0
    assert min(s["counts"].values()) >= 15
    sat.send({"cmd": "fit"})
    fit = sat.reply("fit", timeout=30)
    assert fit["model"] == "ridge" and fit["points"] == 9 and fit["cv_deg"] < 3
    assert (folder / "calibration.json").exists()

    show_points(sat, "validate", "v", 1.3)
    sat.send({"cmd": "validate"})
    v = sat.reply("validate", timeout=30)
    # Быстрая калибровка — девять точек за 12 с, и покачивание головы
    # участника за это время почти не меняется: точность грубее полной.
    assert v["accuracy_deg"] < 3.0, v
    assert len(v["points"]) == 9

    # Живая точка: по строке на кадр, около той точки, куда смотрит участник.
    sat.send({"cmd": "target", "id": "look", "x": 400, "y": 300, "phase": "calib",
              "qpc_us": qpc()})
    sat.send({"cmd": "live", "on": True})
    assert sat.reply("live")["on"] is True
    time.sleep(1.2)
    sat.send({"cmd": "live", "on": False})
    sat.reply("live")
    gaze = [m for m in sat.lines if "g" in m and m.get("ok")]
    assert len(gaze) >= 25
    last = gaze[-1]
    assert math.hypot(last["s"][0] - 400, last["s"][1] - 300) < 150
    assert isinstance(last["t"], int)

    sat.send({"cmd": "close"})
    summary = sat.reply("closed")["summary"]
    assert summary["calibration"]["attempts"] == 1
    data = json.loads((folder / "calibration.json").read_text(encoding="utf-8"))
    assert data["schema"] == "sno2026-eyecal/2"
    assert data["attempts"][0]["validation"]["accuracy_deg"] == v["accuracy_deg"]
    # С шага 29 (BUG-60) модель — глаза при голове на опоре и геометрия.
    assert data["model"]["kind"] == "head"
    assert data["model"]["eye"]["kind"] == "ridge"
    assert (folder / "features.bin").exists()


def test_sno_alg_eye_03_open_without_files(follower, tmp_path):
    sat = follower
    sat.send({"cmd": "open", "write": False, "screen": SCREEN, "distance_mm": 600,
              "mode": [1280, 720]})
    assert sat.reply("open")["frame"] == [1280, 720]
    sat.send({"cmd": "live", "on": True})
    err = sat.wait(lambda m: m.get("cmd") == "live")
    assert err["error"] == "bad_command" and "сначала fit" in err["text"]
    sat.send({"cmd": "close"})
    summary = sat.reply("closed")["summary"]
    assert summary["frames"] > 0 and "files" not in summary
    assert list(tmp_path.iterdir()) == []


def test_sno_alg_eye_03_calibration_commands_are_checked(follower):
    sat = follower
    sat.send({"cmd": "calibrate", "attempt": 1})
    assert "сначала open" in sat.wait(lambda m: m.get("cmd") == "calibrate")["text"]
    sat.send({"cmd": "open", "write": False, "distance_mm": 600, "mode": [1280, 720]})
    sat.reply("open")
    # Без размеров экрана калибровке не в чем считать углы.
    sat.send({"cmd": "calibrate", "attempt": 1})
    assert "размеров экрана" in sat.wait(lambda m: m.get("cmd") == "calibrate")["text"]
    sat.send({"cmd": "close"})
    sat.reply("closed")
    sat.send({"cmd": "open", "write": False, "screen": SCREEN, "distance_mm": 600,
              "mode": [1280, 720]})
    sat.reply("open")
    sat.send({"cmd": "calibrate", "attempt": 1, "kind": "slow"})
    assert sat.wait(lambda m: m.get("cmd") == "calibrate")["error"] == "bad_command"
    sat.send({"cmd": "calibrate", "attempt": 1, "kind": "full"})
    sat.reply("calibrate")
    for bad in ({"phase": "calib", "qpc_us": 1, "x": 1},
                {"phase": "jump", "qpc_us": 1, "id": "a", "x": 1, "y": 1},
                {"phase": "pursuit", "qpc_us": 1, "id": "p", "x": 1, "y": 1}):
        sat.send({"cmd": "target", **bad})
        err = sat.wait(lambda m: m.get("cmd") == "target")
        assert err["error"] == "bad_command" and err["text"].startswith("точка:")
    sat.send({"cmd": "fit"})
    assert sat.wait(lambda m: m.get("cmd") == "fit")["error"] == "no_face"
    sat.send({"cmd": "close"})
    sat.reply("closed")


def test_bug_58_mode_row_names_the_pc_too():
    res = selfcheck.evaluate({**GOOD_M, "width": 1280, "height": 720, "fps": 22.0,
                              "camera_fps": 30.0, "drop_share": 0.3,
                              "proc_ms": 44.0}, T)
    rows = {r["id"]: r for r in res["checks"]}
    assert rows["mode"]["text"] == "Режим 1280×720: в 1080p ПК не успевает"
    res = selfcheck.evaluate({**GOOD_M, "width": 1280, "height": 720}, T)
    rows = {r["id"]: r for r in res["checks"]}
    assert rows["mode"]["text"] == "Режим 1280×720: 1080p камера не держит"
