"""Что общее у `serve`, стенда и пробного запуска: источник кадров,
распознавание, замер процессора и памяти, один экземпляр."""

from __future__ import annotations

import os
import sys
import tempfile
import time
from pathlib import Path

from .capture import (Capture, CameraError, CvSource, SyntheticSource,
                      list_cameras, find_camera, CameraInfo)

ERROR_ALREADY_EXISTS = 183


class Runtime:
    """Источник: `camera` — настоящая камера, `synthetic[:вариант]` —
    синтетика для тестов. Варианты: `denied`, `busy`, `none` (камера не
    открывается по своей причине), `dark` (мало света), `noface`, `slow`
    (1080p даёт 20 к/с, 720p — 30), `twofaces`, `lost` (камера пропадает
    через 60 кадров)."""

    def __init__(self, source: str = "camera"):
        self.source = source
        kind, _, variant = source.partition(":")
        self.synthetic = kind == "synthetic"
        self.variant = variant
        self._landmarker = None
        # Режим, который выбрала последняя самопроверка (1080p или 720p,
        # решение Т24): по нему `open` открывает камеру, если приложение
        # режима не назвало.
        self.mode: tuple[int, int] | None = None

    # камеры
    def cameras(self) -> list[CameraInfo]:
        if self.synthetic:
            if self.variant == "none":
                return []
            return [CameraInfo(0, "Синтетическая камера", "synthetic", "synthetic")]
        return list_cameras()

    def open_capture(self, mode, camera: dict | None = None) -> Capture:
        if self.synthetic:
            src = self._synthetic_source(mode)
        else:
            cams = self.cameras()
            if not cams:
                raise CameraError("no_camera", "Камера не найдена")
            camera = camera or {}
            info = find_camera(cams, camera.get("name"), camera.get("path"),
                               camera.get("index"))
            if info is None:
                raise CameraError("no_camera", "Выбранная камера не найдена")
            src = CvSource(info)
        src.open(mode)
        cap = Capture(src)
        cap.start()
        return cap

    def _synthetic_source(self, mode) -> SyntheticSource:
        v = self.variant
        fail = v if v in ("denied", "busy", "none") else None
        light = 15 if v == "dark" else 120
        fps = 30.0
        if v == "slow" and mode[1] >= 1080:
            fps = 20.0
        scenario = (lambda sec: None) if v == "noface" else None
        return SyntheticSource(fps=fps, scenario=scenario, light=light, fail=fail,
                               faces=2 if v == "twofaces" else 1,
                               lose_after=60 if v == "lost" else None)

    # распознавание
    def landmarker(self):
        if self._landmarker is None:
            if self.synthetic:
                from .landmarks import SyntheticLandmarker
                self._landmarker = SyntheticLandmarker()
            else:
                from .landmarks import MediaPipeLandmarker
                self._landmarker = MediaPipeLandmarker()
        return self._landmarker

    def close(self) -> None:
        if self._landmarker is not None:
            self._landmarker.close()
            self._landmarker = None


class CpuMeter:
    """Загрузка процессора этим процессом, в процентах всей машины."""

    def __init__(self):
        import psutil

        self._p = psutil.Process()
        self._n = psutil.cpu_count() or 1
        self._t = 0.0
        self._c = 0.0

    def start(self) -> None:
        t = self._p.cpu_times()
        self._c = t.user + t.system
        self._t = time.perf_counter()

    def stop(self) -> float:
        t = self._p.cpu_times()
        dt = time.perf_counter() - self._t
        if dt <= 0:
            return 0.0
        return 100.0 * (t.user + t.system - self._c) / dt / self._n

    def rss_mb(self) -> float:
        return self._p.memory_info().rss / 1e6


class SingleInstance:
    """Один спутник на машину: камера у него одна.

    На Windows — именованный мьютекс, в остальных системах — замок файла.
    Имя можно сменить переменной `SNO_EYE_INSTANCE` (тесты).
    """

    def __init__(self):
        self.name = os.environ.get("SNO_EYE_INSTANCE", "MemoriaSnoEye")
        self._handle = None
        self._file = None

    def acquire(self) -> bool:
        if sys.platform == "win32":
            import ctypes
            from ctypes import wintypes

            k32 = ctypes.WinDLL("kernel32", use_last_error=True)
            k32.CreateMutexW.restype = wintypes.HANDLE
            k32.CreateMutexW.argtypes = (ctypes.c_void_p, wintypes.BOOL, wintypes.LPCWSTR)
            handle = k32.CreateMutexW(None, False, "Local\\" + self.name)
            err = ctypes.get_last_error()
            if not handle:
                return False
            if err == ERROR_ALREADY_EXISTS:
                k32.CloseHandle(handle)
                return False
            self._handle = handle
            return True
        import fcntl

        path = Path(tempfile.gettempdir()) / f"{self.name}.lock"
        f = open(path, "w")
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            f.close()
            return False
        self._file = f
        return True

    def release(self) -> None:
        if self._file is not None:
            self._file.close()
            self._file = None
        if self._handle is not None:
            import ctypes

            ctypes.WinDLL("kernel32").CloseHandle(self._handle)
            self._handle = None

