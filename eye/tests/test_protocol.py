"""SNO-ALG-EYE-03 (сторона спутника): подставное «приложение» гоняет
`serve` через трубы с синтетическим источником кадров."""

import json
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

from conftest import EYE, satellite_env
from sno_eye import featfile, eyestrip


class Sat:
    def __init__(self, instance, source="synthetic", extra=()):
        self.p = subprocess.Popen(
            [sys.executable, "-m", "sno_eye", "serve", "--source", source, *extra],
            cwd=EYE, env=satellite_env(instance),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8")
        self.q: queue.Queue = queue.Queue()
        self.lines: list[dict] = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.p.stdout:
            try:
                self.q.put(json.loads(line))
            except ValueError:
                self.q.put({"garbage": line})

    def send(self, msg):
        msg.setdefault("v", 1)
        self.p.stdin.write(json.dumps(msg, ensure_ascii=False) + "\n")
        self.p.stdin.flush()

    def wait(self, pred, timeout=20.0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                m = self.q.get(timeout=0.2)
            except queue.Empty:
                continue
            self.lines.append(m)
            if pred(m):
                return m
        raise AssertionError(f"нет ответа; пришло: {self.lines[-5:]}")

    def reply(self, name, timeout=20.0):
        return self.wait(lambda m: m.get("reply") == name or
                         (m.get("error") and m.get("cmd") == name), timeout)

    def stop(self):
        if self.p.poll() is None:
            self.p.kill()
        self.p.wait(5)


@pytest.fixture
def sat(instance_name):
    s = Sat(instance_name)
    yield s
    s.stop()


def test_sno_alg_eye_03_hello_and_cameras(sat):
    sat.send({"cmd": "hello", "build": "test", "branch": "I"})
    hello = sat.reply("hello")
    assert hello["v"] == 1 and hello["version"]
    assert hello["mediapipe"] == "synthetic"
    sat.send({"cmd": "cameras"})
    cams = sat.reply("cameras")["cameras"]
    assert cams[0]["name"] == "Синтетическая камера"


def test_sno_alg_eye_03_heartbeat(sat):
    hb = sat.wait(lambda m: "hb" in m, timeout=5)
    assert {"fps", "drops", "face", "cpu", "mem"} <= hb.keys()


def test_sno_alg_eye_03_bad_input(sat):
    sat.p.stdin.write("это не json\n")
    sat.p.stdin.flush()
    err = sat.wait(lambda m: "error" in m)
    assert err["error"] == "bad_command"
    sat.send({"cmd": "fly"})
    assert sat.wait(lambda m: "error" in m)["error"] == "bad_command"
    sat.send({"cmd": "cameras", "v": 2})
    err = sat.wait(lambda m: "error" in m)
    assert err["error"] == "bad_command" and "версия обмена" in err["text"]
    # Калибровка без открытой камеры — отказ словами (шаг 28).
    sat.send({"cmd": "fit"})
    err = sat.wait(lambda m: "error" in m)
    assert err["cmd"] == "fit" and "сначала open" in err["text"]


def test_sno_alg_eye_03_open_close_writes_files_in_cyrillic_folder(sat, tmp_path):
    folder = tmp_path / "Записи" / "сессия 1" / "eye"
    sat.send({"cmd": "open", "dir": str(folder), "seg": 0, "n0": 0,
              "qpc0_us": 1, "t0": 0, "camera": {"index": 0},
              "screen": {"w_px": 1920}, "distance_mm": 600, "strip": True,
              "mode": [1280, 720]})
    assert sat.reply("open")["frame"] == [1280, 720]
    time.sleep(2.5)
    sat.send({"cmd": "close"})
    summary = sat.reply("closed")["summary"]
    assert summary["frames"] > 30
    header, recs, whole = featfile.read(folder / "features.bin")
    assert whole and len(recs) == summary["frames"]
    assert header["seg"] == 0 and header["distance_mm"] == 600
    assert list(recs["n"]) == list(range(len(recs)))
    assert eyestrip.count_readable(folder / "eyes.mp4") == summary["strip_frames"]["64x256"]
    assert (folder / "summary.json").exists() and (folder / "log.txt").exists()


def test_sno_alg_eye_03_second_segment_continues_numbers(sat, tmp_path):
    sat.send({"cmd": "open", "dir": str(tmp_path), "seg": 2, "n0": 500,
              "strip": False, "mode": [1280, 720]})
    sat.reply("open")
    time.sleep(1.2)
    sat.send({"cmd": "close"})
    sat.reply("closed")
    header, recs, _ = featfile.read(tmp_path / "features.2.bin")
    assert header["n0"] == 500 and recs["n"][0] == 500
    assert not (tmp_path / "eyes.2.mp4").exists()


def test_sno_alg_eye_03_sync_finds_clock_offset(instance_name):
    offset = 7_345  # мкс
    s = Sat(instance_name, extra=("--clock-offset-us", str(offset)))
    try:
        best = None
        for _ in range(15):
            a1 = time.perf_counter_ns() // 1000
            s.send({"cmd": "sync", "app_qpc_us": a1})
            r = s.reply("sync")
            a2 = time.perf_counter_ns() // 1000
            assert r["app_qpc_us"] == a1
            rtt = a2 - a1
            if best is None or rtt < best[0]:
                best = (rtt, r["eye_qpc_us"] - (a1 + a2) / 2)
        assert abs(best[1] - offset) <= 1000
    finally:
        s.stop()


def test_sno_alg_eye_03_selfcheck_over_pipe(sat, tmp_path):
    sat.send({"cmd": "selfcheck", "seconds": 1, "warmup": 0.3, "dir": str(tmp_path),
              "camera": {"index": 0}})
    res = sat.reply("selfcheck", timeout=30)
    assert res["verdict"] in ("good", "warn")
    assert (tmp_path / "selfcheck.json").exists()
    assert any(m.get("progress") == "selfcheck" for m in sat.lines)


@pytest.mark.parametrize("variant,code", [("denied", "camera_denied"),
                                          ("busy", "camera_busy"),
                                          ("none", "no_camera")])
def test_sno_alg_eye_03_camera_errors(instance_name, tmp_path, variant, code):
    s = Sat(instance_name, source=f"synthetic:{variant}")
    try:
        s.send({"cmd": "open", "dir": str(tmp_path)})
        err = s.wait(lambda m: "error" in m)
        assert err["error"] == code and err["text"]
        s.send({"cmd": "selfcheck", "seconds": 0.5, "warmup": 0})
        res = s.reply("selfcheck")
        cam = [r for r in res["checks"] if r["id"] == "camera"][0]
        assert res["verdict"] == "fail" and cam["value"] == code
    finally:
        s.stop()


def test_sno_alg_eye_03_eof_closes_files_and_exits_fast(sat, tmp_path):
    sat.send({"cmd": "open", "dir": str(tmp_path), "mode": [1280, 720]})
    sat.reply("open")
    time.sleep(1.5)
    t0 = time.monotonic()
    sat.p.stdin.close()
    sat.p.wait(timeout=5)
    assert time.monotonic() - t0 <= 2.0
    _, recs, whole = featfile.read(tmp_path / "features.bin")
    assert whole and len(recs) > 10
    assert eyestrip.count_readable(tmp_path / "eyes.mp4") > 10


def test_sno_alg_eye_03_eof_during_selfcheck_exits_fast(sat):
    sat.send({"cmd": "selfcheck", "seconds": 30, "warmup": 0})
    sat.wait(lambda m: m.get("progress") == "selfcheck")
    t0 = time.monotonic()
    sat.p.stdin.close()
    sat.p.wait(timeout=5)
    assert time.monotonic() - t0 <= 2.0


def test_sno_f_eye_04_second_instance_refuses(sat, instance_name):
    sat.send({"cmd": "hello"})
    sat.reply("hello")
    other = subprocess.run(
        [sys.executable, "-m", "sno_eye", "serve", "--source", "synthetic"],
        cwd=EYE, env=satellite_env(instance_name), input="", capture_output=True,
        text=True, encoding="utf-8", timeout=30)
    assert other.returncode == 3
    msg = json.loads(other.stdout.strip().splitlines()[-1])
    assert msg["error"] == "already_running" and msg["text"] == "Спутник уже запущен"
