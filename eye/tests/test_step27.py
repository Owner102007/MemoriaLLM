"""Шаг 27: модель лица буфером (BUG-56) и кадр самопроверки для экрана
«Место записи» (SNO-F-EYE-05)."""

import base64
import hashlib
import shutil
import sys
import types

import numpy as np
import pytest

from conftest import EYE  # noqa: F401 — путь к пакету
from sno_eye import landmarks, paths
from test_bench_and_build import REQUIRE_MODEL
from test_protocol import Sat


def _stub_mediapipe(monkeypatch, seen: dict):
    """Подставной MediaPipe: запоминает, с чем создавали распознавание."""

    class BaseOptions:
        def __init__(self, **kw):
            seen["base"] = kw

    class FaceLandmarkerOptions:
        def __init__(self, **kw):
            seen["options"] = kw

    class FaceLandmarker:
        @staticmethod
        def create_from_options(options):
            return types.SimpleNamespace(close=lambda: None)

    vision = types.SimpleNamespace(
        FaceLandmarkerOptions=FaceLandmarkerOptions, FaceLandmarker=FaceLandmarker,
        RunningMode=types.SimpleNamespace(VIDEO="VIDEO"))
    base = types.SimpleNamespace(BaseOptions=BaseOptions)
    mp = types.ModuleType("mediapipe")
    mp.__version__ = "stub"
    tasks = types.ModuleType("mediapipe.tasks")
    python = types.ModuleType("mediapipe.tasks.python")
    core = types.ModuleType("mediapipe.tasks.python.core")
    python.vision = vision
    python.core = core
    core.base_options = base
    tasks.python = python
    mp.tasks = tasks
    for name, mod in (("mediapipe", mp), ("mediapipe.tasks", tasks),
                      ("mediapipe.tasks.python", python),
                      ("mediapipe.tasks.python.core", core)):
        monkeypatch.setitem(sys.modules, name, mod)
    monkeypatch.setitem(sys.modules, "mediapipe.tasks.python.vision", vision)
    monkeypatch.setitem(sys.modules, "mediapipe.tasks.python.core.base_options", base)


def test_bug_56_model_goes_to_mediapipe_as_buffer(monkeypatch, tmp_path):
    folder = tmp_path / "Рабочий стол" / "Тест" / "models"
    folder.mkdir(parents=True)
    model = folder / "face_landmarker.task"
    data = b"\x00model-bytes\xff" * 100
    model.write_bytes(data)
    monkeypatch.setattr(landmarks, "expected_model",
                        lambda: {"sha256": hashlib.sha256(data).hexdigest()})
    seen: dict = {}
    _stub_mediapipe(monkeypatch, seen)
    lm = landmarks.MediaPipeLandmarker(model)
    # В MediaPipe не уходит путь вовсе — только байты, уже сверенные.
    assert seen["base"] == {"model_asset_buffer": data}
    assert lm.model_sha256 == hashlib.sha256(data).hexdigest()


def test_bug_56_wrong_or_missing_model_is_model_error(monkeypatch, tmp_path):
    model = tmp_path / "Модель" / "face_landmarker.task"
    with pytest.raises(landmarks.ModelError, match="нет файла"):
        landmarks.load_model(model)
    model.parent.mkdir()
    model.write_bytes(b"abc")
    monkeypatch.setattr(landmarks, "expected_model", lambda: {"sha256": "0" * 64})
    with pytest.raises(landmarks.ModelError, match="не та"):
        landmarks.load_model(model)


def test_bug_56_real_model_from_cyrillic_folder(tmp_path):
    if not paths.model_path().exists() and not REQUIRE_MODEL:
        pytest.skip("модели лица нет — тест идёт в CI")
    folder = tmp_path / "Рабочий стол" / "Тест айтрекера"
    folder.mkdir(parents=True)
    model = folder / "face_landmarker.task"
    shutil.copy(paths.model_path(), model)
    lm = landmarks.MediaPipeLandmarker(model)
    try:
        assert lm.detect(np.zeros((480, 640, 3), np.uint8), 0).face is None
    finally:
        lm.close()


def test_sno_f_eye_05_selfcheck_sends_preview_frames(instance_name, tmp_path):
    import cv2

    s = Sat(instance_name)
    try:
        s.send({"cmd": "selfcheck", "seconds": 1, "warmup": 0.3, "preview": True,
                "camera": {"index": 0}})
        res = s.reply("selfcheck", timeout=30)
        assert res["verdict"] in ("good", "warn")
        shots = [m for m in s.lines if m.get("progress") == "preview"]
        # 1,3 с замера — не больше пяти кадров в секунду, но не ноль.
        assert 2 <= len(shots) <= 9
        shot = shots[-1]
        assert shot["w"] <= 320 and shot["h"] > 0
        img = cv2.imdecode(np.frombuffer(base64.b64decode(shot["jpeg"]), np.uint8),
                           cv2.IMREAD_COLOR)
        assert img.shape[:2] == (shot["h"], shot["w"])
        x0, y0, x1, y1 = shot["face"]
        assert 0 <= x0 < x1 <= 1 and 0 <= y0 < y1 <= 1
    finally:
        s.stop()


def test_sno_f_eye_05_no_preview_unless_asked(instance_name):
    s = Sat(instance_name)
    try:
        s.send({"cmd": "selfcheck", "seconds": 0.5, "warmup": 0, "camera": {"index": 0}})
        s.reply("selfcheck", timeout=30)
        assert not [m for m in s.lines if m.get("progress") == "preview"]
    finally:
        s.stop()
