"""SNO-F-EYE-04: стенд, пробный запуск и замки поставки."""

import json
import os
import re
import subprocess
import sys

import numpy as np
import pytest

from conftest import EYE, satellite_env
from sno_eye import eyestrip, featfile, paths
from sno_eye.bench import gate_of

REQUIRE_MODEL = os.environ.get("SNO_EYE_REQUIRE_MODEL") == "1"


def test_sno_f_eye_04_bench_writes_bench_json(instance_name, tmp_path):
    out = tmp_path / "стенд"
    r = subprocess.run(
        [sys.executable, "-m", "sno_eye", "bench", "--source", "synthetic",
         "--minutes", "0.05", "--no-window", "--out", str(out),
         "--selfcheck-seconds", "1"],
        cwd=EYE, env=satellite_env(instance_name), capture_output=True, text=True,
        encoding="utf-8", timeout=120, input="")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Ворота Г1" in r.stdout
    b = json.loads((out / "bench.json").read_text(encoding="utf-8"))
    assert b["schema"] == "sno2026-eyebench/1"
    for key in ("camera", "mode", "fps", "drops", "cpu", "memory", "selfcheck",
                "gate_g1", "frames", "face_share", "strip"):
        assert key in b, key
    assert b["fps"]["mean"] > 20 and b["face_share"] == 1.0
    assert "memory_ok" not in b["gate_g1"]          # рост памяти — у 40 минут
    # Полоса в двух размерах — первые две минуты; обе читаются.
    assert eyestrip.count_readable(out / "eyes.mp4") == b["strip"]["frames"]["64x256"]
    assert eyestrip.count_readable(out / "eyes_128x512.mp4") == b["strip"]["frames"]["128x512"]
    _, recs, whole = featfile.read(out / "features.bin")
    assert whole and len(recs) == b["frames"]


def test_sno_f_eye_04_bench_without_camera_says_so(instance_name, tmp_path):
    r = subprocess.run(
        [sys.executable, "-m", "sno_eye", "bench", "--source", "synthetic:none",
         "--minutes", "0.05", "--no-window", "--out", str(tmp_path)],
        cwd=EYE, env=satellite_env(instance_name), capture_output=True, text=True,
        encoding="utf-8", timeout=60, input="")
    assert r.returncode == 1
    assert "Камера не найдена" in r.stdout
    b = json.loads((tmp_path / "bench.json").read_text(encoding="utf-8"))
    assert b["selfcheck"]["verdict"] == "fail"


def test_sno_f_eye_04_gate_g1():
    base = {"fps": {"mean": 29.0}, "drops": {"share": 0.01},
            "cpu": {"mean_percent": 20.0}, "memory": {"growth_mb": 10.0}}
    assert gate_of(base, 2)["pass"] and "memory_ok" not in gate_of(base, 2)
    assert gate_of(base, 40)["memory_ok"]
    assert not gate_of({**base, "fps": {"mean": 24.9}}, 2)["pass"]
    assert not gate_of({**base, "drops": {"share": 0.021}}, 2)["pass"]
    assert not gate_of({**base, "cpu": {"mean_percent": 35.1}}, 2)["pass"]
    assert not gate_of({**base, "memory": {"growth_mb": 51}}, 40)["pass"]


def test_sno_f_eye_04_selftest(instance_name):
    """Настоящая модель: на Linux-раннере CI она скачана по замку
    (`SNO_EYE_REQUIRE_MODEL=1`); в сессии без модели — пропуск."""
    if not paths.model_path().exists() and not REQUIRE_MODEL:
        pytest.skip("модели лица нет — тест идёт в CI")
    r = subprocess.run([sys.executable, "-m", "sno_eye", "--selftest"], cwd=EYE,
                       env=satellite_env(instance_name), capture_output=True,
                       text=True, encoding="utf-8", timeout=180)
    assert r.returncode == 0, r.stdout + r.stderr
    res = json.loads(r.stdout.strip().splitlines()[-1])
    assert res["ok"] and res["blank_frame"] == "no_face" and res["x264"]
    assert res["camera"] in ("ok", "no_camera", "camera_busy", "camera_denied")


def test_sno_f_eye_04_real_landmarker_sees_no_face_on_blank():
    if not paths.model_path().exists() and not REQUIRE_MODEL:
        pytest.skip("модели лица нет — тест идёт в CI")
    from sno_eye.landmarks import MediaPipeLandmarker
    lm = MediaPipeLandmarker()
    try:
        for k in range(3):
            assert lm.detect(np.zeros((480, 640, 3), np.uint8), k * 33).face is None
        # Метки VIDEO обязаны расти — повтор метки не роняет распознавание.
        assert lm.detect(np.zeros((480, 640, 3), np.uint8), 0).face is None
    finally:
        lm.close()


# --- замки поставки ----------------------------------------------------

def test_sno_f_eye_04_python_version_lock():
    kv = paths.read_kv(EYE / "python_version.txt")
    assert re.fullmatch(r"3\.\d+\.\d+", kv["version"])
    assert re.fullmatch(r"[0-9a-f]{64}", kv["sha256_embed_amd64"])
    assert kv["url"].startswith("https://www.python.org/ftp/python/")
    assert kv["version"] in kv["url"]


def test_sno_f_eye_04_model_lock():
    kv = paths.read_kv(paths.model_version_path())
    assert kv["url"].startswith("https://storage.googleapis.com/mediapipe-models/")
    assert re.fullmatch(r"[0-9a-f]{64}", kv["sha256"])


def test_sno_f_eye_04_requirements_lock_is_pinned_and_hashed():
    text = (EYE / "requirements.lock").read_text(encoding="utf-8")
    entries = re.split(r"\n(?=[A-Za-z0-9_.-]+==)", text.split("\n\n", 1)[-1].strip())
    names = set()
    for e in entries:
        if not e.strip() or e.lstrip().startswith("#"):
            continue
        head = e.split()[0]
        assert re.fullmatch(r"[A-Za-z0-9_.-]+==[^\s\\]+", head), head
        assert "--hash=sha256:" in e, head
        names.add(head.split("==")[0].lower())
    for need in ("mediapipe", "opencv-contrib-python", "av", "numpy", "psutil",
                 "cv2-enumerate-cameras"):
        assert need in names, need


def test_sno_f_eye_04_cmd_shortcuts():
    for name in ("Проверка камеры.cmd", "Проверка камеры (40 минут).cmd"):
        raw = (EYE / name).read_bytes()
        raw.decode("ascii")  # содержимое — латиницей: кодовая страница cmd
        text = raw.decode("ascii")
        assert "python.exe -I -m sno_eye bench" in text
        assert "\r\n" in text
    assert "--minutes 40" in (EYE / "Проверка камеры (40 минут).cmd").read_text()
