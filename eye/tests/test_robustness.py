"""SNO-ALG-EYE-03, SNO-F-EYE-04: отказы — камера не утекает, сбой записи
слышен, режим самопроверки помнится, разрыв помечен у нужного кадра,
метки VIDEO идут по общим часам."""

import json
import subprocess
import sys
import threading
import time

import numpy as np
import pytest

from conftest import EYE, satellite_env
from sno_eye import featfile
from sno_eye.capture import FrameQueue, Grabbed
from sno_eye.landmarks import Detection, ModelError
from sno_eye.processing import Processor
from sno_eye.protocol import Server
from sno_eye.runtime import Runtime


class FakeOut:
    def __init__(self):
        self.msgs = []

    def send(self, msg, droppable=False):
        msg.setdefault("v", 1)
        self.msgs.append(msg)

    def last(self, key):
        return [m for m in self.msgs if key in m][-1]


def capture_threads():
    return [t for t in threading.enumerate() if t.name == "eye-capture" and t.is_alive()]


def wait_no_capture(timeout=2.0):
    end = time.monotonic() + timeout
    while capture_threads() and time.monotonic() < end:
        time.sleep(0.05)
    return not capture_threads()


def server(source="synthetic"):
    out = FakeOut()
    return Server(Runtime(source), out), out


def cmd(**kw):
    return json.dumps({"v": 1, **kw})


def test_sno_alg_eye_03_bad_open_frees_camera_and_names_command(tmp_path):
    s, out = server()
    s.handle(cmd(cmd="open", dir=str(tmp_path), seg="abc"))
    err = out.last("error")
    assert err["error"] == "bad_command" and err["cmd"] == "open"
    assert wait_no_capture()
    # Сегмент уже записан — отказ, прежний файл цел, камера свободна.
    (tmp_path / "features.bin").write_bytes(b"old")
    s.handle(cmd(cmd="open", dir=str(tmp_path), mode=[1280, 720]))
    err = out.last("error")
    assert err["error"] == "disk" and err["cmd"] == "open"
    assert (tmp_path / "features.bin").read_bytes() == b"old"
    assert wait_no_capture()
    assert s.session is None
    s.shutdown()


def test_sno_alg_eye_03_missing_model_is_model_missing_and_camera_untouched(tmp_path,
                                                                           monkeypatch):
    s, out = server()

    def broken():
        raise ModelError("нет файла модели face_landmarker.task")

    monkeypatch.setattr(s.rt, "landmarker", broken)
    for c in ("open", "selfcheck", "hello"):
        s.handle(cmd(cmd=c, dir=str(tmp_path / c), seconds=0.2, warmup=0))
        err = out.last("error")
        assert err["error"] == "model_missing" and err["cmd"] == c
        assert not capture_threads()
    s.shutdown()


def test_sno_alg_eye_03_camera_lost_during_record_is_reported(tmp_path):
    s, out = server("synthetic:lost")
    s.handle(cmd(cmd="open", dir=str(tmp_path), mode=[1280, 720]))
    assert out.last("reply")["reply"] == "open"
    end = time.monotonic() + 8
    while not any(m.get("error") == "camera_lost" for m in out.msgs) and time.monotonic() < end:
        time.sleep(0.1)
    lost = [m for m in out.msgs if m.get("error") == "camera_lost"]
    assert lost and lost[0]["cmd"] == "record"
    assert s.session.dead
    # Мёртвую сессию закрывает новый open сам; прежние файлы целы.
    s.handle(cmd(cmd="open", dir=str(tmp_path / "2"), mode=[1280, 720]))
    assert out.last("reply")["reply"] == "open"
    _, recs, whole = featfile.read(tmp_path / "features.bin")
    assert whole and len(recs) >= 50
    s.handle(cmd(cmd="close"))
    s.shutdown()
    assert wait_no_capture()


def test_sno_alg_eye_03_open_uses_mode_chosen_by_selfcheck(tmp_path):
    s, out = server("synthetic:slow")   # 1080p даёт 20 к/с, 720p — 30
    s.handle(cmd(cmd="selfcheck", seconds=1, warmup=0.2))
    res = out.last("reply")
    assert res["reply"] == "selfcheck"
    assert [res["measures"]["width"], res["measures"]["height"]] == [1280, 720]
    s.handle(cmd(cmd="open", dir=str(tmp_path)))
    assert out.last("reply")["frame"] == [1280, 720]
    s.handle(cmd(cmd="close"))
    s.shutdown()


def test_sno_alg_eye_03_queued_command_after_eof_is_not_run(instance_name, tmp_path):
    p = subprocess.Popen([sys.executable, "-m", "sno_eye", "serve", "--source", "synthetic"],
                         cwd=EYE, env=satellite_env(instance_name), stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                         encoding="utf-8")
    p.stdin.write(cmd(cmd="selfcheck", seconds=30, warmup=0) + "\n")
    p.stdin.write(cmd(cmd="open", dir=str(tmp_path / "late")) + "\n")
    p.stdin.flush()
    time.sleep(1.0)
    t0 = time.monotonic()
    p.stdin.close()
    p.wait(timeout=5)
    assert time.monotonic() - t0 <= 2.0
    replies = [json.loads(line) for line in p.stdout.read().splitlines() if line.strip()]
    assert not any(m.get("reply") == "open" for m in replies)
    assert not (tmp_path / "late").exists()


def test_sno_alg_eye_01_gap_is_marked_on_the_frame_after_it():
    q = FrameQueue(2)
    frames = [Grabbed(np.zeros(1), {}, k, k) for k in range(5)]
    for f in frames:
        q.put(f)                   # 0 и 1, затем 2 вытесняет 0 и т. д.
    got = [q.get(0) for _ in range(2)]
    assert [g.seq for g in got] == [3, 4]
    # Перед кадром 3 выброшены 0, 1 и 2 — разрыв у него, у 4 разрыва нет.
    assert got[0].dropped_before == 3 and got[1].dropped_before == 0
    assert q.dropped == 3


def test_sno_alg_eye_01_video_timestamps_follow_process_clock():
    seen = []

    class Rec:
        version = "x"
        model_sha256 = "x"

        def detect(self, frame, t_ms, meta=None):
            seen.append(t_ms)
            return Detection(None, 0)

    lm = Rec()
    first, second = Processor(lm), Processor(lm)
    for k in range(3):
        first.process(Grabbed(np.zeros((4, 4, 3), np.uint8), {}, 10_000_000 + k * 33_333, k))
    for k in range(3):
        second.process(Grabbed(np.zeros((4, 4, 3), np.uint8), {}, 90_000_000 + k * 33_333, k))
    # Вторая обработка продолжает те же часы, шаг — настоящий (33 мс).
    assert seen == [10000, 10033, 10066, 90000, 90033, 90066]


def test_sno_alg_eye_03_selfcheck_never_leaks_camera_on_abort(tmp_path):
    s, out = server()
    t = threading.Thread(target=s.handle, args=(cmd(cmd="selfcheck", seconds=20, warmup=0),))
    t.start()
    time.sleep(0.8)
    s.abort.set()
    t.join(timeout=3)
    assert not t.is_alive()
    assert wait_no_capture()
    s.shutdown()
