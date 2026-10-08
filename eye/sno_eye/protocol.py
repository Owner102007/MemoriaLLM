"""Обмен с приложением (SNO-ALG-EYE-03): строки JSON через stdin и stdout.

Сторона спутника. Приложение пишет команду строкой в stdin, спутник
отвечает строкой в stdout; stderr уходит в журнал спутника. Ответы пишет
отдельный поток из ограниченной очереди: анонимный канал Windows
блокирует запись, когда приложение не успевает читать, — тогда
выбрасываются только строки живой точки, а ответы и сердцебиение нет.

Конец stdin значит «приложения больше нет»: спутник дописывает файлы и
выходит не позже чем через две секунды.

В этой версии (ET-01) команды калибровки — `target`, `fit`, `validate`,
`live` — отвечают `bad_command`: они придут с ET-03.
"""

from __future__ import annotations

import json
import logging
import queue
import sys
import threading
import time
from pathlib import Path

from . import PROTOCOL, VERSION, clock
from .capture import MODES, CameraError
from .processing import Processor, Recorder
from .runtime import CpuMeter, Runtime
from . import selfcheck

log = logging.getLogger("sno_eye")

LATER = ("target", "fit", "validate", "live")


class Outbox:
    """Писатель stdout в своём потоке."""

    def __init__(self, stream, maxsize: int = 512):
        self._stream = stream
        self._q: queue.Queue = queue.Queue(maxsize=maxsize)
        self._thread = threading.Thread(target=self._run, name="eye-out", daemon=True)
        self._thread.start()
        self.dropped_live = 0

    def send(self, msg: dict, droppable: bool = False) -> None:
        msg.setdefault("v", PROTOCOL)
        line = json.dumps(msg, ensure_ascii=False, separators=(",", ":"))
        if droppable:
            try:
                self._q.put_nowait(line)
            except queue.Full:
                self.dropped_live += 1
            return
        self._q.put(line)

    def _run(self) -> None:
        while True:
            line = self._q.get()
            if line is None:
                return
            try:
                self._stream.write(line + "\n")
                self._stream.flush()
            except (OSError, ValueError):
                return

    def close(self, timeout: float = 1.0) -> None:
        try:
            self._q.put(None, timeout=timeout)
        except queue.Full:
            return
        self._thread.join(timeout=timeout)


class Session:
    """Запись признаков и полосы в папку — между `open` и `close`."""

    def __init__(self, rt: Runtime, cmd: dict):
        self.dir = Path(cmd["dir"])
        self.dir.mkdir(parents=True, exist_ok=True)
        mode = tuple(cmd.get("mode") or MODES[0])
        self.capture = rt.open_capture(mode, cmd.get("camera"))
        header = {
            "qpc0_us": cmd.get("qpc0_us"), "t0": cmd.get("t0"),
            "camera": cmd.get("camera"), "screen": cmd.get("screen"),
            "distance_mm": cmd.get("distance_mm"),
            "frame": [self.capture.source.width, self.capture.source.height],
            "satellite": VERSION, "mediapipe": rt.landmarker().version,
            "model_sha256": rt.landmarker().model_sha256,
        }
        self.recorder = Recorder(self.dir, seg=int(cmd.get("seg", 0)),
                                 n0=int(cmd.get("n0", 0)),
                                 strip=bool(cmd.get("strip", True)), header=header)
        self.processor = Processor(rt.landmarker())
        self._stop = threading.Event()
        self.frames = 0
        self.face = 0
        self._recent: list[float] = []
        self._thread = threading.Thread(target=self._run, name="eye-proc", daemon=True)
        self._thread.start()

    def _run(self) -> None:
        from .capture import set_thread_priority

        set_thread_priority(-1)
        while not self._stop.is_set():
            g = self.capture.get(0.2)
            if g is None:
                if self.capture.stats.lost:
                    break
                continue
            frame = self.processor.process(g)
            self.recorder.add(frame)
            self.frames += 1
            if frame.px is not None:
                self.face += 1
            self._recent.append(time.perf_counter())

    def fps(self) -> float:
        now = time.perf_counter()
        self._recent = [t for t in self._recent if now - t <= 2.0]
        return len(self._recent) / 2.0

    def close(self) -> dict:
        self._stop.set()
        self._thread.join(timeout=1.0)
        self.capture.stop()
        summary = self.recorder.close()
        summary.update({"dropped": self.capture.stats.dropped,
                        "lost": self.capture.stats.lost})
        (self.dir / "summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")
        return summary


class Server:
    def __init__(self, rt: Runtime, out: Outbox):
        self.rt = rt
        self.out = out
        self.session: Session | None = None
        self.cpu = CpuMeter()
        self.abort = threading.Event()
        self._hb_stop = threading.Event()
        self._hb = threading.Thread(target=self._heartbeat, name="eye-hb", daemon=True)

    def start(self) -> None:
        self._hb.start()

    def _heartbeat(self) -> None:
        n = 0
        self.cpu.start()
        while not self._hb_stop.wait(1.0):
            n += 1
            s = self.session
            cpu = self.cpu.stop()
            self.cpu.start()
            self.out.send({
                "hb": n,
                "fps": round(s.fps(), 1) if s else 0.0,
                "drops": s.capture.stats.dropped if s else 0,
                "face": (round(s.face / s.frames, 3) if s and s.frames else None),
                "cpu": round(cpu, 1),
                "mem": round(self.cpu.rss_mb(), 1),
            })

    def handle(self, line: str) -> None:
        try:
            cmd = json.loads(line)
            if not isinstance(cmd, dict):
                raise ValueError
        except ValueError:
            self._error("bad_command", "строка — не JSON-объект")
            return
        name = cmd.get("cmd")
        if name == "hello":
            lm = None
            try:
                lm = self.rt.landmarker()
            except Exception as e:  # noqa: BLE001
                self._error("model_missing", f"модель не загрузилась: {e}", name)
                return
            self.out.send({"reply": "hello", "version": VERSION,
                           "mediapipe": lm.version, "model_sha256": lm.model_sha256})
            return
        if cmd.get("v") != PROTOCOL:
            self._error("bad_command", f"версия обмена {cmd.get('v')} — "
                                       f"спутник говорит на {PROTOCOL}", name)
            return
        try:
            if name == "cameras":
                self.out.send({"reply": "cameras",
                               "cameras": [c.as_dict() for c in self.rt.cameras()]})
            elif name == "selfcheck":
                self._selfcheck(cmd)
            elif name == "open":
                self._open(cmd)
            elif name == "close":
                self._close()
            elif name == "sync":
                self.out.send({"reply": "sync", "app_qpc_us": cmd.get("app_qpc_us"),
                               "eye_qpc_us": clock.qpc_us()})
            elif name in LATER:
                self._error("bad_command", f"команда «{name}» — в следующей версии "
                                           "спутника", name)
            else:
                self._error("bad_command", f"неизвестная команда «{name}»", name)
        except CameraError as e:
            self._error(e.code, e.text, name)
        except OSError as e:
            self._error("disk", f"диск: {e}", name)

    def _selfcheck(self, cmd: dict) -> None:
        t = selfcheck.load_thresholds()
        if cmd.get("seconds"):
            t["measure_s"] = float(cmd["seconds"])
        if cmd.get("warmup") is not None:
            t["warmup_s"] = float(cmd["warmup"])
        folder = Path(cmd.get("dir") or ".")
        if self.session is not None:
            self._error("camera_busy", "камера занята записью", "selfcheck")
            return
        result = selfcheck.measure(
            lambda mode: self.rt.open_capture(mode, cmd.get("camera")),
            lambda: Processor(self.rt.landmarker()), CpuMeter(), t, folder,
            progress=lambda p: self.out.send({"progress": "selfcheck", **p}),
            abort=self.abort.is_set,
        )
        if self.abort.is_set():
            return
        if cmd.get("dir"):
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "selfcheck.json").write_text(
                json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
        self.out.send({"reply": "selfcheck", **result})

    def _open(self, cmd: dict) -> None:
        if self.session is not None:
            self._error("bad_command", "запись уже идёт", "open")
            return
        if not cmd.get("dir"):
            self._error("bad_command", "нет папки записи", "open")
            return
        self.session = Session(self.rt, cmd)
        handler = logging.FileHandler(self.session.dir / "log.txt", encoding="utf-8")
        handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
        log.addHandler(handler)
        self._log_handler = handler
        log.info("open %s", cmd.get("dir"))
        self.out.send({"reply": "open", "frame": [self.session.capture.source.width,
                                                  self.session.capture.source.height]})

    def _close(self) -> None:
        s = self.session
        if s is None:
            self.out.send({"reply": "closed", "summary": None})
            return
        self.session = None
        summary = s.close()
        log.info("close %s", summary)
        handler = getattr(self, "_log_handler", None)
        if handler is not None:
            log.removeHandler(handler)
            handler.close()
        self.out.send({"reply": "closed", "summary": summary})

    def _error(self, code: str, text: str, cmd: str | None = None) -> None:
        msg = {"error": code, "text": text}
        if cmd:
            msg["cmd"] = cmd
        log.info("error %s: %s", code, text)
        self.out.send(msg)

    def shutdown(self) -> None:
        self._hb_stop.set()
        if self.session is not None:
            try:
                self.session.close()
            finally:
                self.session = None
        self.rt.close()


def serve(rt: Runtime) -> int:
    """Главный поток читает stdin, команды исполняет рабочий поток: так
    конец stdin замечается и посреди долгой самопроверки."""
    out = Outbox(sys.stdout)
    server = Server(rt, out)
    server.start()
    commands: queue.Queue = queue.Queue()

    def work() -> None:
        while True:
            line = commands.get()
            if line is None:
                return
            try:
                server.handle(line)
            except Exception as e:  # noqa: BLE001 — спутник не падает от команды
                log.exception("command failed")
                server._error("bad_command", f"сбой команды: {e}")

    worker = threading.Thread(target=work, name="eye-cmd", daemon=True)
    worker.start()
    try:
        for line in sys.stdin:
            line = line.strip()
            if line:
                commands.put(line)
    finally:
        server.abort.set()
        commands.put(None)
        worker.join(timeout=1.0)
        server.shutdown()
        out.close(timeout=0.3)
    return 0
