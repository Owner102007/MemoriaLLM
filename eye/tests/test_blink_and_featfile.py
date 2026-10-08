"""SNO-ALG-EYE-01: моргание и файл `features.bin`."""

from pathlib import Path

import numpy as np

from sno_eye import featfile
from sno_eye.blink import BlinkGate, run

FRAME_US = 33_333


def gate_run(scores):
    marked = []
    items = [(k, k * FRAME_US, s) for k, s in enumerate(scores)]
    out = run(BlinkGate(marked.append), items)
    return out, sorted(marked)


def test_sno_alg_eye_01_short_blink_is_marked():
    scores = [0.1] * 5 + [0.9] * 6 + [0.1] * 5   # 6 кадров ≈ 200 мс
    out, marked = gate_run(scores)
    assert out == list(range(len(scores)))       # порядок и полнота
    assert marked == list(range(5, 11))


def test_sno_alg_eye_01_long_closure_is_not_blink():
    scores = [0.1] * 3 + [0.9] * 20 + [0.1] * 3  # ≈ 670 мс
    out, marked = gate_run(scores)
    assert out == list(range(len(scores)))
    assert marked == []


def test_sno_alg_eye_01_low_openness_without_blink_score_is_kept():
    # Взгляд к низу страницы опускает веки, но eyeBlink низкий — кадры годны.
    out, marked = gate_run([0.3] * 30)
    assert marked == [] and len(out) == 30


def test_sno_alg_eye_01_hold_is_bounded():
    gate = BlinkGate(lambda item: None)
    for k in range(40):
        if gate.push(k, k * FRAME_US, 0.9):
            break
    # Эпизод длиннее 400 мс отпускается, не дожидаясь конца.
    assert k * FRAME_US >= 400_000 and k * FRAME_US < 450_000


def test_sno_alg_eye_01_no_face_ends_episode():
    out, marked = gate_run([0.9] * 3 + [None] + [0.1])
    assert marked == [0, 1, 2] and out == [0, 1, 2, 3, 4]


def _write(path: Path, n: int, per_block: int = 30) -> featfile.FeatWriter:
    w = featfile.FeatWriter(path, {"seg": 0})
    for k in range(n):
        rec = w.new_record()
        rec["n"] = k
        rec["qpc_us"] = 1000 + k * FRAME_US
        rec["feat"][:] = k
        rec["lm"][:] = 0.25
        w.add(rec)
        if (k + 1) % per_block == 0:
            w.flush_block()
    return w


def test_sno_alg_eye_01_featfile_roundtrip(tmp_path):
    p = tmp_path / "features.bin"
    _write(p, 95).close()
    header, recs, whole = featfile.read(p)
    assert whole
    assert header["schema"] == "sno2026-eyefeat/1"
    assert len(recs) == 95
    assert list(recs["n"]) == list(range(95))
    assert np.all(recs["video_frame"] == -1)
    assert recs["feat"][7][0] == 7


def test_sno_alg_eye_01_featfile_truncated_tail_is_cut(tmp_path):
    p = tmp_path / "features.bin"
    _write(p, 90).close()
    raw = p.read_bytes()
    p.write_bytes(raw[:-17])         # сбой посреди последней пачки
    _, recs, whole = featfile.read(p)
    assert not whole
    assert len(recs) == 60           # две целые пачки из трёх


def test_sno_alg_eye_01_landmark_encoding_roundtrip():
    rng = np.random.default_rng(1)
    px = rng.uniform([600, 300, -50], [1300, 800, 50], size=(77, 3))
    origin = np.array([950.0, 520.0])
    scale = 180.0
    lm = featfile.encode_landmarks(px, origin, scale)
    feat = np.zeros(13, np.float32)
    feat[9], feat[10], feat[11] = origin[0] / 1920, origin[1] / 1080, scale
    back = featfile.decode_landmarks(lm, feat, 1920, 1080)
    # float16 в долях расстояния между уголками — доли пикселя.
    assert np.max(np.abs(back[:, :2] - px[:, :2])) < 0.5
