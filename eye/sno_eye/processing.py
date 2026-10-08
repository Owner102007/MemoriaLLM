"""Кадр → запись: ориентиры, признаки, флаги, полоса глаз.

Общая часть стенда, самопроверки и записи (`open`): одна и та же
обработка, разные потребители.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import eyestrip, faceparts as fp, featfile, features
from .blink import BlinkGate
from .capture import Grabbed


@dataclass
class Frame:
    """Что известно о кадре после распознавания."""

    grabbed: Grabbed
    faces: int
    record: np.ndarray            # запись features.bin (без номера видео)
    px: np.ndarray | None         # ориентиры в пикселях
    feat: np.ndarray | None
    blink_score: float | None
    width: int
    height: int

    @property
    def ok(self) -> bool:
        return featfile.is_ok(int(self.record["flags"]))


class Processor:
    def __init__(self, landmarker, writer_dtype: np.dtype | None = None):
        self.landmarker = landmarker
        self.dtype = writer_dtype or featfile.record_dtype()
        self.n = 0
        self._stored = list(fp.STORED)
        self._shapes = list(fp.EYE_BLENDSHAPES)

    def process(self, g: Grabbed) -> Frame:
        h, w = g.frame.shape[:2]
        # Метка для режима VIDEO — от общих часов процесса, а не от начала
        # этой обработки: распознавание одно на процесс, и у второй сессии
        # отсчёт с нуля шёл бы шагом в 1 мс после первой.
        t_ms = g.qpc_us // 1000
        det = self.landmarker.detect(g.frame, t_ms, g.meta)
        rec = np.zeros((), dtype=self.dtype)
        rec["n"] = self.n
        rec["qpc_us"] = g.qpc_us
        rec["video_frame"] = -1
        self.n += 1
        flags = featfile.DROPPED_BEFORE if g.dropped_before else 0
        if det.face is None:
            rec["flags"] = flags | featfile.NO_FACE
            return Frame(g, 0, rec, None, None, None, w, h)
        if det.faces > 1:
            flags |= featfile.MULTI_FACE
        face = det.face
        try:
            vec = features.compute(face.landmarks, face.matrix, w, h)
        except ValueError:
            rec["flags"] = flags | featfile.NO_FACE
            return Frame(g, det.faces, rec, None, None, None, w, h)
        px = features.to_pixels(face.landmarks, w, h)
        if features.head_turned(vec):
            flags |= featfile.HEAD_TURNED
        names = fp.FEATURE_NAMES
        origin = np.array([vec[names.index("face_x")] * w,
                           vec[names.index("face_y")] * h])
        rec["lm"] = featfile.encode_landmarks(px[self._stored], origin,
                                              float(vec[names.index("scale_px")]))
        rec["matrix"] = np.asarray(face.matrix, dtype=np.float32).reshape(16)
        rec["bs"] = np.array([face.blendshapes.get(n, 0.0) for n in self._shapes],
                             dtype=np.float16)
        rec["feat"] = vec
        rec["flags"] = flags
        score = max(face.blendshapes.get("eyeBlinkLeft", 0.0),
                    face.blendshapes.get("eyeBlinkRight", 0.0))
        return Frame(g, det.faces, rec, px, vec, score, w, h)


def _mark_blink(frame: Frame) -> None:
    frame.record["flags"] = int(frame.record["flags"]) | featfile.BLINK


@dataclass
class RecorderStats:
    frames: int = 0
    ok: int = 0
    face: int = 0
    strip_frames: dict = field(default_factory=dict)


class Recorder:
    """Пишет `features.bin` и полосу глаз в папку.

    Сегмент 0 — `features.bin`, `eyes.mp4`; следующие (после перезапуска
    спутника) — `features.1.bin`, `eyes.1.mp4` и так далее. Полоса
    второго размера (`extra_sizes`) — только стенду.
    """

    def __init__(self, folder: Path, seg: int = 0, n0: int = 0,
                 strip: bool = True, extra_sizes: tuple[str, ...] = (),
                 extra_seconds: float | None = None, fps: int = 30,
                 header: dict | None = None):
        self.folder = Path(folder)
        self.folder.mkdir(parents=True, exist_ok=True)
        suffix = "" if seg == 0 else f".{seg}"
        targets = [self.folder / f"features{suffix}.bin"]
        if strip:
            targets.append(self.folder / f"eyes{suffix}.mp4")
            targets += [self.folder / f"eyes_{size}{suffix}.mp4" for size in extra_sizes]
        for t in targets:
            if t.exists():
                # Тот же сегмент второй раз — ошибка приложения; прежний
                # файл записи дороже нового.
                raise FileExistsError(f"сегмент {seg} уже записан: {t.name}")
        info = {"seg": seg, "n0": n0}
        info.update(header or {})
        self.feat = featfile.FeatWriter(self.folder / f"features{suffix}.bin", info)
        self.strips: dict[str, eyestrip.StripWriter] = {}
        if strip:
            self.strips[eyestrip.DEFAULT_STRIP] = eyestrip.StripWriter(
                self.folder / f"eyes{suffix}.mp4", eyestrip.DEFAULT_STRIP, fps)
            for size in extra_sizes:
                self.strips[size] = eyestrip.StripWriter(
                    self.folder / f"eyes_{size}{suffix}.mp4", size, fps)
        self._extra_until_us: int | None = None
        self._extra_seconds = extra_seconds
        self.n0 = n0
        self.stats = RecorderStats()
        self._gate: BlinkGate[Frame] = BlinkGate(_mark_blink)
        self._last_block_us: int | None = None

    def add(self, frame: Frame) -> None:
        g = frame.grabbed
        frame.record["n"] = self.n0 + self.stats.frames
        self.stats.frames += 1
        if frame.px is not None:
            self.stats.face += 1
            if self.strips:
                if self._extra_until_us is None and self._extra_seconds is not None:
                    self._extra_until_us = g.qpc_us + int(self._extra_seconds * 1e6)
                for size, writer in list(self.strips.items()):
                    if size != eyestrip.DEFAULT_STRIP and self._extra_until_us is not None \
                            and g.qpc_us > self._extra_until_us:
                        writer.close()
                        del self.strips[size]
                        continue
                    n = writer.write(eyestrip.cut(g.frame, frame.px, size))
                    if size == eyestrip.DEFAULT_STRIP:
                        frame.record["video_frame"] = n
                    self.stats.strip_frames[size] = self.stats.strip_frames.get(size, 0) + 1
        for done in self._gate.push(frame, g.qpc_us, frame.blink_score):
            self._write(done)
        if self._last_block_us is None:
            self._last_block_us = g.qpc_us
        elif g.qpc_us - self._last_block_us >= 1_000_000:
            self.feat.flush_block()
            self._last_block_us = g.qpc_us

    def _write(self, frame: Frame) -> None:
        if frame.ok:
            self.stats.ok += 1
        self.feat.add(frame.record)

    def close(self) -> dict:
        for done in self._gate.flush():
            self._write(done)
        self.feat.close()
        for writer in self.strips.values():
            writer.close()
        files = {p.name: p.stat().st_size for p in sorted(self.folder.iterdir())
                 if p.is_file()}
        return {"frames": self.stats.frames, "ok": self.stats.ok,
                "face": self.stats.face, "strip_frames": dict(self.stats.strip_frames),
                "files": files}
