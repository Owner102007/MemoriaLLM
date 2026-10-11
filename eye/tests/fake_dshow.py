"""Поддельный DirectShow из OpenCV — для BUG-66.

Повторяет то, как `modules/videoio/src/cap_dshow.cpp` OpenCV 5.0.0
(та же версия, что в спутнике) настраивает камеру:

* `VideoCapture_DShow::setProperty` — ширина и высота запоминаются и
  применяются, когда известны обе; формат берёт текущий размер камеры
  и применяется сразу; после каждого применения запомненные ширина,
  высота и формат сбрасываются в −1; частота перенастраивает камеру
  последним применённым размером **без формата**;
* `videoInput::setupDevice(w, h)` и `setupDeviceFourcc(w, h, −1)`
  просят формат по умолчанию RGB24, а когда его нет — первый, какой
  камера даёт этим размером, по порядку OpenCV: несжатые форматы, YUY2
  среди них, раньше MJPG;
* нужного размера нет вовсе — ближайший по сумме разниц ширины и
  высоты, в порядке перечня драйвера; формат при этом не запоминается;
* `stopDevice` пересоздаёт устройство: запрошенная частота и прежний
  формат забываются, частоту возвращает тот, кто перенастраивает;
* `getFPS` — запрошенная частота, а не та, что даёт камера (−1, пока
  её не просили).

Камера — перечень драйвера: формат, ширина, высота и наибольшая
частота. Драйвер принимает любую запрошенную частоту и даёт не больше
своей (так вела себя камера второго ПК: просили 30, получили 10).
Сколько кадров камера даёт на самом деле — `FakeCv2.real_fps`; с
`pace=True` кадры и отдаются с этой частотой. `broken` — форматы, в
которых камера настраивается, но кадров не отдаёт.
"""

from __future__ import annotations

import time
import types

import numpy as np

PRIORITY = ("RGB24", "RGB32", "RGB555", "RGB565", "YUY2", "YVYU", "YUYV",
            "IYUV", "UYVY", "YV12", "YVU9", "Y411", "Y41P", "Y211", "AYUV",
            "MJPG", "Y800", "Y8", "GREY", "I420", "BY8", "Y16", "NV12")

# Модель камеры второго ПК (Chicony USB2.0 Camera, vid_04f2 pid_b729,
# ноутбук Thunderobot): MJPG — 30 к/с на всех размерах, несжатый YUY2
# по USB 2.0 при 720p — 10 к/с; 1080p нет.
CHICONY = (("MJPG", 1280, 720, 30), ("MJPG", 640, 480, 30),
           ("MJPG", 640, 360, 30), ("YUY2", 640, 480, 30),
           ("YUY2", 1280, 720, 10), ("YUY2", 640, 360, 30))

# Камера без MJPG.
YUY2_ONLY = (("YUY2", 640, 480, 30), ("YUY2", 1280, 720, 10))

# Камера с 1080p в MJPG.
FULL_HD = (("MJPG", 1920, 1080, 30), ("MJPG", 1280, 720, 30),
           ("YUY2", 640, 480, 30), ("YUY2", 1280, 720, 10),
           ("YUY2", 1920, 1080, 5))

CONSTANTS = {"CAP_ANY": 0, "CAP_DSHOW": 700, "CAP_MSMF": 1400,
             "CAP_PROP_FRAME_WIDTH": 3, "CAP_PROP_FRAME_HEIGHT": 4,
             "CAP_PROP_FPS": 5, "CAP_PROP_FOURCC": 6,
             "CAP_PROP_SETTINGS": 37}


def fourcc(text: str) -> int:
    a, b, c, d = text
    return ord(a) | ord(b) << 8 | ord(c) << 16 | ord(d) << 24


def _code(subtype: str) -> int:
    # Несжатые RGB у DirectShow — не четыре буквы; код только отличается.
    return fourcc(subtype) if len(subtype) == 4 else 1000 + PRIORITY.index(
        subtype)


def _subtype(code: int) -> str | None:
    for s in PRIORITY:
        if _code(s) == code:
            return s
    return None


class _Device:
    """`videoDevice`: то, что `stopDevice` пересоздаёт."""

    def __init__(self):
        self.video_type = "RGB24"
        self.width = 0
        self.height = 0
        self.try_w, self.try_h, self.try_type = 640, 480, "RGB24"
        self.try_diff = True
        self.ready = False
        self.frame_fps = -1          # requestedFrameTime, в кадрах/с
        self.applied: tuple[str, int, int, float] | None = None


class FakeCv2:
    """Модуль `cv2` с одной камерой DirectShow."""

    def __init__(self, caps=CHICONY, pace: bool = False,
                 broken: tuple[str, ...] = ()):
        self.caps = tuple(caps)
        self.pace = pace
        self.broken = set(broken)
        self._next = 0.0
        self.dev = _Device()
        self.setups = 0
        self.log: list[tuple] = []
        self.module = types.ModuleType("cv2")
        for k, v in CONSTANTS.items():
            setattr(self.module, k, v)
        self.module.VideoWriter_fourcc = lambda *c: fourcc("".join(c))
        fake = self

        class VideoCapture(_Capture):
            def __init__(self, index, api=0, params=None):
                super().__init__(fake, index, api, params)

        self.module.VideoCapture = VideoCapture
        self.module.__version__ = "5.0.0-fake-dshow"

    # --- videoInput ------------------------------------------------------

    def real_fps(self) -> float:
        """Сколько кадров в секунду камера отдаёт в нынешнем формате."""
        if self.dev.applied is None:
            return 0.0
        return self.dev.applied[3]

    def format(self) -> tuple[str, int, int] | None:
        """Что камера отдаёт на самом деле: формат, ширина, высота."""
        a = self.dev.applied
        return None if a is None else (a[0], a[1], a[2])

    def _cap(self, subtype, w, h):
        for c in self.caps:
            if (c[0], c[1], c[2]) == (subtype, w, h):
                return c
        return None

    def _set_format(self, d: _Device, w: int, h: int, subtype: str) -> bool:
        c = self._cap(subtype, w, h)
        if c is None:
            return False
        # Частоты не просили — остаётся та, что у формата по умолчанию.
        asked = d.frame_fps if d.frame_fps > 0 else self.caps[0][3]
        d.applied = (subtype, w, h, float(min(asked, c[3])))
        return True

    def _closest(self, w: int, h: int):
        near = None
        for c in self.caps:
            if (c[1], c[2]) == (w, h):
                return c
            if near is None or (abs(w - c[1]) + abs(h - c[2])
                                < abs(w - near[1]) + abs(h - near[2])):
                near = c
        return near

    def stop_device(self) -> None:
        self.dev = _Device()

    def set_ideal_framerate(self, fps: float) -> None:
        if not self.dev.ready and fps > 0:
            self.dev.frame_fps = fps

    def get_fps(self) -> float:
        d = self.dev
        return float(d.frame_fps) if d.ready and d.frame_fps > 0 else -1.0

    def get_fourcc(self) -> int:
        return _code(self.dev.video_type) if self.dev.ready else 0

    def setup_device(self, w: int | None = None, h: int | None = None,
                     subtype: str = "RGB24") -> bool:
        d = self.dev
        if d.ready:
            return False
        if w is not None:
            d.try_w, d.try_h, d.try_type, d.try_diff = w, h, subtype, True
        self.setups += 1
        found = False
        if d.try_diff:
            if self._set_format(d, d.try_w, d.try_h, d.try_type):
                d.width, d.height, d.video_type = d.try_w, d.try_h, d.try_type
                found = True
            else:
                for s in PRIORITY:
                    if self._set_format(d, d.try_w, d.try_h, s):
                        d.width, d.height, d.video_type = d.try_w, d.try_h, s
                        found = True
                        break
            if not found:
                c = self._closest(d.try_w, d.try_h)
                if c is not None and self._set_format(d, c[1], c[2], c[0]):
                    # Как в OpenCV: размер запомнен, формат — нет.
                    d.width, d.height = c[1], c[2]
                    found = True
        if not found:
            c = self.caps[0]
            self._set_format(d, c[1], c[2], c[0])
            d.width, d.height = c[1], c[2]
        d.ready = True
        self.log.append(("setup", d.applied))
        return True


class _Capture:
    """`VideoCapture_DShow` — свойства как в OpenCV 5.0.0."""

    def __init__(self, cv: FakeCv2, index: int, api: int, params):
        self.cv = cv
        self.api = api
        self.m_index = -1
        self.m_width = self.m_height = self.m_fourcc = -1
        self.m_width_set = self.m_height_set = -1
        if params:
            p = dict(zip(params[::2], params[1::2]))
            w = p.get(CONSTANTS["CAP_PROP_FRAME_WIDTH"], -1)
            h = p.get(CONSTANTS["CAP_PROP_FRAME_HEIGHT"], -1)
            code = p.get(CONSTANTS["CAP_PROP_FOURCC"], -1)
            if w != -1 and h != -1:
                cv.setup_device(int(w), int(h),
                                _subtype(int(code)) or "RGB24")
        self.open(index)

    def open(self, index: int) -> None:
        self.release()
        if index != 0:
            return
        self.cv.setup_device()
        if self.cv.dev.ready:
            self.m_index = index

    def isOpened(self) -> bool:
        return self.m_index >= 0 and self.cv.dev.ready

    def release(self) -> None:
        if self.m_index >= 0:
            self.cv.stop_device()
            self.m_index = -1
        self.m_width_set = self.m_height_set = -1
        self.m_width = self.m_height = -1

    def read(self):
        cv = self.cv
        if not self.isOpened() or cv.dev.applied is None:
            return False, None
        subtype, w, h, fps = cv.dev.applied
        if subtype in cv.broken:
            return False, None
        if cv.pace:
            now = time.perf_counter()
            cv._next = max(cv._next + 1.0 / fps, now)
            time.sleep(max(0.0, cv._next - now))
        return True, np.zeros((h, w, 3), np.uint8)

    def get(self, prop: int) -> float:
        cv, d = self.cv, self.cv.dev
        if prop == CONSTANTS["CAP_PROP_FRAME_WIDTH"]:
            return float(d.width)
        if prop == CONSTANTS["CAP_PROP_FRAME_HEIGHT"]:
            return float(d.height)
        if prop == CONSTANTS["CAP_PROP_FOURCC"]:
            return float(cv.get_fourcc())
        if prop == CONSTANTS["CAP_PROP_FPS"]:
            return cv.get_fps()
        return -1.0

    def set(self, prop: int, value) -> bool:
        cv = self.cv
        cv.log.append(("set", prop, value))
        handled = False
        if prop == CONSTANTS["CAP_PROP_FRAME_WIDTH"]:
            self.m_width = round(value)
            handled = True
        elif prop == CONSTANTS["CAP_PROP_FRAME_HEIGHT"]:
            self.m_height = round(value)
            handled = True
        elif prop == CONSTANTS["CAP_PROP_FOURCC"]:
            self.m_fourcc = int(value)
            self.m_width = int(self.get(CONSTANTS["CAP_PROP_FRAME_WIDTH"]))
            self.m_height = int(self.get(CONSTANTS["CAP_PROP_FRAME_HEIGHT"]))
            handled = self.m_fourcc != -1
        elif prop == CONSTANTS["CAP_PROP_FPS"]:
            fps = round(value)
            if fps != cv.get_fps():
                cv.stop_device()
                cv.set_ideal_framerate(fps)
                if self.m_width_set > 0 and self.m_height_set > 0:
                    cv.setup_device(self.m_width_set, self.m_height_set)
                else:
                    cv.setup_device()
            return cv.dev.ready
        elif prop == CONSTANTS["CAP_PROP_SETTINGS"]:
            return True
        if not handled:
            return False
        if self.m_width > 0 and self.m_height > 0:
            d = cv.dev
            if (self.m_width != d.width or self.m_height != d.height
                    or self.m_fourcc != cv.get_fourcc()):
                fps = int(cv.get_fps())
                cv.stop_device()
                cv.set_ideal_framerate(fps)
                subtype = (_subtype(self.m_fourcc) if self.m_fourcc != -1
                           else "RGB24")
                if subtype is None:
                    return False
                cv.setup_device(self.m_width, self.m_height, subtype)
            ok = cv.dev.ready
            if ok:
                self.m_width_set = self.m_width
                self.m_height_set = self.m_height
                self.m_width = self.m_height = self.m_fourcc = -1
            return ok
        return True
