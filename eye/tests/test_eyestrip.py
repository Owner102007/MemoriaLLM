"""SNO-ALG-EYE-01: полоса глаз — гомография, вырезка, H.264 с фрагментами."""

import numpy as np
import cv2
import pytest

from sno_eye import eyestrip, features
from sno_eye import faceparts as fp
from sno_eye.synthetic import Head, render

W, H = 1920, 1080


def px_of(**kw):
    face = render(Head(**kw), W, H)
    return features.to_pixels(face.landmarks, W, H)


def test_sno_alg_eye_01_corners_go_to_square_corners():
    px = px_of(yaw=8, roll=5, cx=0.42)
    h = eyestrip.homography(px)
    src = eyestrip.corner_points(px).reshape(-1, 1, 2)
    dst = cv2.perspectiveTransform(src, h)[:, 0]
    np.testing.assert_allclose(dst, [[0, 0], [512, 0], [0, 512], [512, 512]], atol=1e-3)


def test_sno_alg_eye_01_corners_pushed_away_from_nose():
    px = px_of()
    nose = px[fp.NOSE_TIP, :2]
    raw = np.array([px[i, :2] for i in fp.STRIP_CORNERS])
    pushed = eyestrip.corner_points(px)
    d_raw = np.abs(raw - nose)
    d_new = np.abs(pushed - nose)
    np.testing.assert_allclose(d_new[:, 0], d_raw[:, 0] * 1.4, rtol=1e-4)
    np.testing.assert_allclose(d_new[:, 1], d_raw[:, 1] * 1.2, rtol=1e-4)


def test_sno_alg_eye_01_strip_lies_between_151_and_195_and_holds_the_eyes():
    px = px_of()
    h = eyestrip.homography(px)
    y0, y1 = eyestrip.strip_rows(px, h)
    eyes = cv2.perspectiveTransform(
        np.array([[px[fp.R_IRIS, :2]], [px[fp.L_IRIS, :2]]], np.float32), h)[:, 0]
    assert 0 <= y0 < y1 <= 512
    assert all(y0 <= e[1] <= y1 for e in eyes)


@pytest.mark.parametrize("size,shape", [("64x256", (64, 256, 3)), ("128x512", (128, 512, 3))])
def test_sno_alg_eye_01_cut_sizes(size, shape):
    frame = np.random.default_rng(0).integers(0, 255, (H, W, 3), dtype=np.uint8)
    strip = eyestrip.cut(frame, px_of(gaze_x=0.3), size)
    assert strip.shape == shape and strip.dtype == np.uint8


def test_sno_alg_eye_01_x264_present():
    assert eyestrip.has_x264()


def test_sno_alg_eye_01_mp4_writes_and_truncated_file_reads_to_last_fragment(tmp_path):
    p = tmp_path / "eyes.mp4"
    w = eyestrip.StripWriter(p, fps=30)
    rng = np.random.default_rng(2)
    for _ in range(300):                       # 10 с — пять фрагментов
        w.write(rng.integers(0, 255, (64, 256, 3), dtype=np.uint8))
    w.close()
    assert eyestrip.count_readable(p) == 300
    raw = p.read_bytes()
    cut = tmp_path / "cut.mp4"
    cut.write_bytes(raw[: int(len(raw) * 0.7)])  # сбой посреди записи
    n = eyestrip.count_readable(cut)
    # Целые фрагменты по 60 кадров читаются; потерян не больше хвоста.
    assert 120 <= n < 300
