"""SNO-ALG-EYE-01: признаки ступени 0 на синтетической голове."""

import numpy as np
import pytest

from sno_eye import faceparts as fp
from sno_eye import features
from sno_eye.synthetic import Head, render

W, H = 1920, 1080
GAZE = slice(0, 4)  # r_u, r_v, l_u, l_v


def feat(**kw):
    face = render(Head(**kw), W, H)
    return features.compute(face.landmarks, face.matrix, W, H)


def test_sno_alg_eye_01_gaze_features_ignore_shift_and_scale():
    base = feat(gaze_x=0.4, gaze_y=-0.3)
    for kw in ({"cx": 0.3, "cy": 0.6}, {"px_per_mm": 1.2}, {"px_per_mm": 3.1, "cx": 0.62}):
        other = feat(gaze_x=0.4, gaze_y=-0.3, **kw)
        np.testing.assert_allclose(other[GAZE], base[GAZE], atol=1e-5)
        np.testing.assert_allclose(other[4:6], base[4:6], atol=1e-5)


def test_sno_alg_eye_01_gaze_features_ignore_roll():
    base = feat(gaze_x=-0.5, gaze_y=0.2)
    rolled = feat(gaze_x=-0.5, gaze_y=0.2, roll=12)
    np.testing.assert_allclose(rolled[GAZE], base[GAZE], atol=1e-5)


@pytest.mark.parametrize("axis,idx", [("gaze_x", (0, 2)), ("gaze_y", (1, 3))])
def test_sno_alg_eye_01_features_monotonic_in_gaze(axis, idx):
    values = [feat(**{axis: g}) for g in np.linspace(-1, 1, 9)]
    for i in idx:
        series = [v[i] for v in values]
        assert all(b > a for a, b in zip(series, series[1:])), series


def test_sno_alg_eye_01_angles_from_matrix():
    f = feat(yaw=17, pitch=-9, roll=4)
    names = fp.FEATURE_NAMES
    assert f[names.index("yaw")] == pytest.approx(17, abs=1e-4)
    assert f[names.index("pitch")] == pytest.approx(-9, abs=1e-4)
    assert f[names.index("roll")] == pytest.approx(4, abs=1e-4)


def test_sno_alg_eye_01_face_place_scale_and_iris():
    f = feat(cx=0.4, cy=0.55, px_per_mm=2.0)
    names = fp.FEATURE_NAMES
    assert f[names.index("face_x")] == pytest.approx(0.4, abs=1e-6)
    assert f[names.index("face_y")] == pytest.approx(0.55, abs=1e-6)
    assert f[names.index("scale_px")] == pytest.approx(90 * 2.0, rel=1e-6)
    # Обод радужки — 5,8 мм радиуса: диаметр 11,6 мм × 2 пикс/мм.
    assert f[names.index("iris_px")] == pytest.approx(23.2, rel=1e-6)


def test_sno_alg_eye_01_eyelid_openness_follows_lid():
    names = fp.FEATURE_NAMES
    open_ = feat(lid=1.0)[names.index("open_r")]
    half = feat(lid=0.5)[names.index("open_r")]
    assert half == pytest.approx(open_ / 2, rel=1e-6)


def test_sno_alg_eye_01_head_turn_flag():
    assert not features.head_turned(feat(yaw=25, pitch=-20))
    assert features.head_turned(feat(yaw=31))
    assert features.head_turned(feat(pitch=-26))
