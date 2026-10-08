"""Номера ориентиров MediaPipe Face Mesh (478 точек), которые нужны
признакам, полосе глаз и файлу `features.bin` (SNO-ALG-EYE-01).

Правый глаз — правый глаз человека, то есть левый на снимке.
"""

from __future__ import annotations

# Уголки глаз: внешний и внутренний.
R_OUTER, R_INNER = 33, 133
L_OUTER, L_INNER = 263, 362
# Веки: верхнее и нижнее в середине глаза.
R_UPPER, R_LOWER = 159, 145
L_UPPER, L_LOWER = 386, 374
# Радужки: центр и четыре точки обода.
R_IRIS = 468
R_IRIS_RING = (469, 470, 471, 472)
L_IRIS = 473
L_IRIS_RING = (474, 475, 476, 477)
# Опора системы головы: точка 10 — верх лба.
FOREHEAD_TOP = 10
NOSE_TIP = 4
# Полоса глаз: четыре угла области и две точки, между которыми режется
# полоса (лоб над переносицей и спинка носа).
STRIP_CORNERS = (103, 332, 150, 379)  # левый верх, правый верх, низ...
STRIP_TOP, STRIP_BOTTOM = 151, 195

R_EYE_CONTOUR = (33, 7, 163, 144, 145, 153, 154, 155, 133,
                 173, 157, 158, 159, 160, 161, 246)
L_EYE_CONTOUR = (263, 249, 390, 373, 374, 380, 381, 382, 362,
                 398, 384, 385, 386, 387, 388, 466)
R_BROW = (70, 63, 105, 66, 107, 55, 65, 52, 53, 46)
L_BROW = (300, 293, 334, 296, 336, 285, 295, 282, 283, 276)
REFERENCE = (1, 4, 6, 9, 10, 151, 152, 168, 195,
             103, 150, 332, 379, 234, 454)

IRISES = (R_IRIS,) + R_IRIS_RING + (L_IRIS,) + L_IRIS_RING

# Порядок ориентиров в записи `features.bin`. Меняется только со сменой
# схемы файла: разбор читает их по этому списку из заголовка.
STORED = R_EYE_CONTOUR + L_EYE_CONTOUR + IRISES + R_BROW + L_BROW + REFERENCE

# Блендшейпы глаз — в этом порядке в записи.
EYE_BLENDSHAPES = (
    "eyeBlinkLeft", "eyeBlinkRight",
    "eyeLookDownLeft", "eyeLookDownRight",
    "eyeLookInLeft", "eyeLookInRight",
    "eyeLookOutLeft", "eyeLookOutRight",
    "eyeLookUpLeft", "eyeLookUpRight",
    "eyeSquintLeft", "eyeSquintRight",
    "eyeWideLeft", "eyeWideRight",
)

# Имена признаков ступени 0 — в этом порядке в векторе.
FEATURE_NAMES = (
    "r_u", "r_v", "l_u", "l_v",
    "open_r", "open_l",
    "yaw", "pitch", "roll",
    "face_x", "face_y",
    "scale_px", "iris_px",
)
