"""Захват камеры (SNO-ALG-EYE-01, шаг 1).

OpenCV через DirectShow; Media Foundation — только запасным путём: на
части камер он открывается десятки секунд. Формат MJPG, затем частота,
затем размер. Метка времени ставится в миг, когда кадр получен.
Очередь на два кадра: если обработка отстаёт, старый кадр выбрасывается,
а пропуск считается. Поток захвата — с повышенным приоритетом, чтобы
метки не дрожали.
"""

from __future__ import annotations

import sys
import threading
import time
from collections import deque
from dataclasses import dataclass, field

import numpy as np

from . import clock, privacy
from .synthetic import Head

MODES = ((1920, 1080), (1280, 720))


class CameraError(Exception):
    def __init__(self, code: str, text: str):
        super().__init__(text)
        self.code = code
        self.text = text


@dataclass
class CameraInfo:
    index: int
    name: str
    path: str = ""
    backend: str = ""

    def as_dict(self) -> dict:
        return {"index": self.index, "name": self.name, "path": self.path,
                "backend": self.backend}


def set_thread_priority(level: int) -> None:
    """+1 — выше обычного (захват), −1 — ниже (распознавание).
    Только на Windows; в остальных системах ничего не делает."""
    if sys.platform != "win32":
        return
    import ctypes

    k32 = ctypes.windll.kernel32
    k32.SetThreadPriority(k32.GetCurrentThread(), int(level))


# --- источники кадров ----------------------------------------------------

class Source:
    name = "?"
    width = 0
    height = 0

    def open(self, mode: tuple[int, int]) -> None: ...
    def read(self) -> tuple[bool, np.ndarray | None, dict]: ...
    def close(self) -> None: ...


class CvSource(Source):
    def __init__(self, info: CameraInfo):
        self.info = info
        self.name = info.name
        self._cap = None

    def open(self, mode: tuple[int, int]) -> None:
        import cv2

        if privacy.denied_here():
            raise CameraError("camera_denied",
                              "Камера запрещена в параметрах Windows")
        # Номер камеры из перечня DirectShow годится только DirectShow:
        # у Media Foundation свой перечень (виртуальных камер в нём нет), и
        # тот же номер открыл бы другую камеру. Запасной путь — когда
        # перечня DirectShow нет вовсе (номер найден пробой, CAP_ANY).
        backends = [cv2.CAP_DSHOW] if self.info.backend == "dshow" else [cv2.CAP_ANY]
        for backend in backends:
            cap = cv2.VideoCapture(self.info.index, backend)
            if not cap.isOpened():
                cap.release()
                continue
            cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
            cap.set(cv2.CAP_PROP_FPS, 30)
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, mode[0])
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, mode[1])
            ok, frame = cap.read()
            if not ok or frame is None:
                cap.release()
                continue
            self._cap = cap
            self.height, self.width = frame.shape[:2]
            return
        raise CameraError("camera_busy",
                          "Камера занята другой программой — закройте Teams, "
                          "Zoom, браузер")

    def read(self):
        ok, frame = self._cap.read()
        return ok, frame, {}

    def close(self) -> None:
        if self._cap is not None:
            self._cap.release()
            self._cap = None


class SyntheticSource(Source):
    """Кадры с заданной частотой и известной головой в `meta['head']`.

    `scenario` — функция секунды от начала → `Head` или `None` (лица
    нет). `light` — яркость фона кадра (самопроверка света).
    """

    name = "Синтетическая камера"

    def __init__(self, fps: float = 30.0, scenario=None, light: int = 120,
                 fail: str | None = None, max_mode: tuple[int, int] = (1920, 1080),
                 faces: int = 1, lose_after: int | None = None):
        self.fps = fps
        self.scenario = scenario or default_scenario
        self.light = light
        self.fail = fail
        self.max_mode = max_mode
        self.faces = faces
        self.lose_after = lose_after
        self._count = 0
        self._t0 = 0.0
        self._next = 0.0
        self._base: np.ndarray | None = None

    def open(self, mode):
        if self.fail == "denied":
            raise CameraError("camera_denied", "Камера запрещена в параметрах Windows")
        if self.fail == "busy":
            raise CameraError("camera_busy", "Камера занята другой программой — "
                                             "закройте Teams, Zoom, браузер")
        if self.fail == "none":
            raise CameraError("no_camera", "Камера не найдена")
        self.width = min(mode[0], self.max_mode[0])
        self.height = min(mode[1], self.max_mode[1])
        self._base = np.full((self.height, self.width, 3), self.light, np.uint8)
        self._t0 = time.perf_counter()
        self._next = self._t0

    def read(self):
        self._count += 1
        if self.lose_after is not None and self._count > self.lose_after:
            time.sleep(0.005)
            return False, None, {}
        self._next += 1.0 / self.fps
        delay = self._next - time.perf_counter()
        if delay > 0:
            time.sleep(delay)
        sec = time.perf_counter() - self._t0
        head = self.scenario(sec)
        frame = self._base.copy()
        if head is not None:
            # Лицо светлее фона, чтобы проверка «свет сзади» видела лицо.
            cx, cy = int(head.cx * self.width), int(head.cy * self.height)
            r = int(90 * head.px_per_mm)
            frame[max(0, cy - r):cy + r, max(0, cx - r):cx + r] = min(255, self.light + 30)
        return True, frame, {"head": head, "faces": self.faces}

    def close(self):
        self._base = None


def default_scenario(sec: float) -> Head:
    """Взгляд медленно обходит экран, голова почти неподвижна."""
    import math

    return Head(gaze_x=math.sin(sec * 0.7), gaze_y=0.6 * math.sin(sec * 0.45),
                yaw=3 * math.sin(sec * 0.2), pitch=2 * math.sin(sec * 0.15))


def list_cameras() -> list[CameraInfo]:
    """Камеры с именами. Номер — для OpenCV; запомненная камера ищется по
    имени и пути устройства, а не по номеру."""
    if sys.platform == "win32":
        try:
            import cv2
            from cv2_enumerate_cameras import enumerate_cameras

            out = [CameraInfo(c.index, c.name, getattr(c, "path", "") or "", "dshow")
                   for c in enumerate_cameras(cv2.CAP_DSHOW)]
            if out:
                return out
        except Exception:  # noqa: BLE001 — перечисление необязательно
            pass
    try:
        import cv2
    except ImportError:
        return []
    found = []
    for i in range(4):
        cap = cv2.VideoCapture(i)
        if cap.isOpened():
            found.append(CameraInfo(i, f"Камера {i}"))
        cap.release()
    return found


def find_camera(cams: list[CameraInfo], name: str | None, path: str | None,
                index: int | None) -> CameraInfo | None:
    for c in cams:
        if path and c.path == path:
            return c
    for c in cams:
        if name and c.name == name:
            return c
    for c in cams:
        if index is not None and c.index == index:
            return c
    return cams[0] if cams and name is None and path is None and index is None else None


# --- поток захвата -------------------------------------------------------

@dataclass
class Grabbed:
    frame: np.ndarray
    meta: dict
    qpc_us: int
    seq: int
    dropped_before: int = 0


@dataclass
class CaptureStats:
    grabbed: int = 0
    dropped: int = 0
    failures: int = 0
    lost: bool = False


class FrameQueue:
    """Очередь на два кадра. Полная — выбрасывается самый старый, а
    разрыв помечается у кадра, который теперь стоит первым: это перед ним
    пропали кадры."""

    def __init__(self, size: int = 2):
        self._items: deque[Grabbed] = deque()
        self._size = size
        self._cv = threading.Condition()
        self.dropped = 0

    def put(self, item: Grabbed) -> None:
        with self._cv:
            if len(self._items) >= self._size:
                gone = self._items.popleft()
                self.dropped += 1
                head = self._items[0] if self._items else item
                # Разрыв переходит к следующему кадру вместе с теми, что
                # уже были выброшены перед выброшенным.
                head.dropped_before += gone.dropped_before + 1
            self._items.append(item)
            self._cv.notify()

    def get(self, timeout: float) -> Grabbed | None:
        with self._cv:
            if not self._items:
                self._cv.wait(timeout)
            return self._items.popleft() if self._items else None


class Capture:
    """Поток, который читает источник и кладёт кадры в очередь на два."""

    def __init__(self, source: Source):
        self.source = source
        self.q = FrameQueue(2)
        self.stats = CaptureStats()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, name="eye-capture", daemon=True)
        self._thread.start()

    def _run(self) -> None:
        set_thread_priority(1)
        seq = 0
        fails = 0
        while not self._stop.is_set():
            ok, frame, meta = self.source.read()
            stamp = clock.qpc_us()
            if not ok or frame is None:
                fails += 1
                self.stats.failures += 1
                if fails >= 30:
                    self.stats.lost = True
                    break
                time.sleep(0.01)
                continue
            fails = 0
            self.q.put(Grabbed(frame, meta, stamp, seq))
            seq += 1
            self.stats.grabbed += 1
            self.stats.dropped = self.q.dropped

    def get(self, timeout: float = 0.5) -> Grabbed | None:
        return self.q.get(timeout)

    @property
    def alive(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def stop(self, timeout: float = 1.0) -> bool:
        """Остановить поток и освободить камеру. Камера освобождается
        только после выхода потока захвата: `VideoCapture` из двух потоков
        разом не трогают. Не вышел за `timeout` — False, камеру освободит
        выход процесса."""
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=timeout)
            if self._thread.is_alive():
                return False
        self.source.close()
        return True
