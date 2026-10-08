"""Обмен с приложением (SNO-ALG-EYE-03): строки JSON через stdin и stdout.

Сторона спутника. Приложение пишет команду строкой в stdin, спутник
отвечает строкой в stdout; stderr уходит в журнал спутника. Ответы пишет
отдельный поток из ограниченной очереди: анонимный канал Windows
блокирует запись, когда приложение не успевает читать, — тогда
выбрасываются только строки живой точки, а ответы и сердцебиение нет.

Конец stdin значит «приложения больше нет»: спутник дописывает файлы и
выходит не позже чем через две секунды — а если что-то застряло, его
снимает собственный сторож.

Поля сверх перечня в схеме: у `selfcheck` и `open` необязательный `dir`
у самопроверки — папка записей (по ней меряется место на диске); у
`open` необязательный `mode` — режим камеры; не назван — берётся тот,
что выбрала последняя самопроверка, без неё — 1080p.

У `selfcheck` необязательный `preview: true` (шаг 27): пока идёт замер,
спутник шлёт `{progress: "preview", jpeg, w, h, face}` — маленький кадр
камеры для экрана «Место записи». Эти строки выбрасываются первыми,
если приложение не успевает читать, как строки живой точки.

В этой версии (ET-01) команды калибровки — `target`, `fit`, `validate`,
`live` — отвечают `bad_command`: они придут с ET-03. Камера, пропавшая
во время записи, — ошибка `camera_lost` без ответа на команду; поиск
вернувшейся камеры придёт с ET-02.
"""

from __future__ import annotations

import json
import logging
import os
import queue
import sys
import threading
import time
from pathlib import Path

from . import PROTOCOL, VERSION, clock, selfcheck
from .capture import MODES, CameraError
from .landmarks import ModelError
from .processing import Processor, Recorder
from .runtime import CpuMeter, Runtime

log = logging.getLogger("sno_eye")

LATER = ("target", "fit", "validate", "live")
EXIT_DEADLINE_S = 1.8


class CommandError(Exception):
    def __init__(self, code: str, text: str):
        super().__init__(text)
        self.code = code
        self.text = text


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


def _int(cmd: dict, key: str, default: int) -> int:
    value = cmd.get(key, default)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise CommandError("bad_command", f"«{key}» — не целое неотрицательное число")
    return value


def _mode(cmd: dict, rt: Runtime) -> tuple[int, int]:
    value = cmd.get("mode")
    if value is None:
        return rt.mode or MODES[0]
    if (not isinstance(value, list) or len(value) != 2
            or not all(isinstance(v, int) and v > 0 for v in value)):
        raise CommandError("bad_command", "«mode» — пара [ширина, высота]")
    return int(value[0]), int(value[1])


def _camera(cmd: dict) -> dict | None:
    value = cmd.get("camera")
    if value is not None and not isinstance(value, dict):
        raise CommandError("bad_command", "«camera» — объект {name, path, index}")
    return value


class Session:
    """Запись признаков и полосы в папку — между `open` и `close`.

    Если камера пропала или запись упала, сессия не висит молча: она
    сообщает об этом через `on_fail` и считается мёртвой — `close`
    закрывает её как обычно, а новый `open` убирает её сам.
    """

    def __init__(self, rt: Runtime, cmd: dict, on_fail):
        if not cmd.get("dir"):
            raise CommandError("bad_command", "нет папки записи")
        seg = _int(cmd, "seg", 0)
        n0 = _int(cmd, "n0", 0)
        mode = _mode(cmd, rt)
        camera = _camera(cmd)
        self.dir = Path(cmd["dir"])
        lm = rt.landmarker()  # модель — до камеры: не загрузилась, камера свободна
        self.dir.mkdir(parents=True, exist_ok=True)
        self.capture = rt.open_capture(mode, camera)
        try:
            header = {
                "qpc0_us": cmd.get("qpc0_us"), "t0": cmd.get("t0"),
                "camera": camera, "screen": cmd.get("screen"),
                "distance_mm": cmd.get("distance_mm"),
                "frame": [self.capture.source.width, self.capture.source.height],
                "satellite": VERSION, "mediapipe": lm.version,
                "model_sha256": lm.model_sha256,
            }
            self.recorder = Recorder(self.dir, seg=seg, n0=n0,
                                     strip=bool(cmd.get("strip", True)), header=header)
        except BaseException:
            self.capture.stop()
            raise
        self.processor = Processor(lm)
        self._on_fail = on_fail
        self._stop = threading.Event()
        self.dead = False
        self.frames = 0
        self.face = 0
        self._recent: list[float] = []
        self._thread = threading.Thread(target=self._run, name="eye-proc", daemon=True)
        self._thread.start()

    def _run(self) -> None:
        from .capture import set_thread_priority

        set_thread_priority(-1)
        try:
            while not self._stop.is_set():
                g = self.capture.get(0.2)
                if g is None:
                    if self.capture.stats.lost:
                        self._fail("camera_lost", "Камера пропала во время записи")
                        return
                    continue
                frame = self.processor.process(g)
                self.recorder.add(frame)
                self.frames += 1
                if frame.px is not None:
                    self.face += 1
                self._recent.append(time.perf_counter())
        except OSError as e:
            self._fail("disk", f"Запись взгляда остановилась: {e}")
        except Exception as e:  # noqa: BLE001 — о сбое должно узнать приложение
            log.exception("session failed")
            self._fail("camera_lost", f"Запись взгляда остановилась: {e}")

    def _fail(self, code: str, text: str) -> None:
        self.dead = True
        log.info("session %s: %s", code, text)
        self._on_fail(code, text)

    def fps(self) -> float:
        now = time.perf_counter()
        self._recent = [t for t in self._recent if now - t <= 2.0]
        return len(self._recent) / 2.0

    def close(self) -> dict:
        self._stop.set()
        self._thread.join(timeout=0.6)
        released = self.capture.stop(timeout=0.6)
        try:
            summary = self.recorder.close()
        except OSError as e:
            summary = {"error": str(e)}
        summary.update({"dropped": self.capture.stats.dropped,
                        "lost": self.capture.stats.lost, "dead": self.dead,
                        "camera_released": released})
        try:
            (self.dir / "summary.json").write_text(
                json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")
        except OSError:
            pass
        return summary


class Server:
    def __init__(self, rt: Runtime, out: Outbox):
        self.rt = rt
        self.out = out
        self.session: Session | None = None
        self.cpu = CpuMeter()
        self.abort = threading.Event()
        # Сессией и распознаванием распоряжаются рабочий поток и завершение:
        # один замок на всё, иначе `close` и выход закрыли бы файлы дважды.
        self.lock = threading.RLock()
        self._log_handler: logging.Handler | None = None
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
        try:
            self._dispatch(name, cmd)
        except CommandError as e:
            self._error(e.code, e.text, name)
        except CameraError as e:
            self._error(e.code, e.text, name)
        except ModelError as e:
            self._error("model_missing", f"Модель лица: {e}", name)
        except OSError as e:
            self._error("disk", f"Диск: {e}", name)
        except Exception as e:  # noqa: BLE001 — спутник не падает от команды
            log.exception("command %s failed", name)
            self._error("bad_command", f"сбой команды: {e}", name)

    def _dispatch(self, name, cmd: dict) -> None:
        if name == "hello":
            lm = self.rt.landmarker()
            self.out.send({"reply": "hello", "version": VERSION,
                           "mediapipe": lm.version, "model_sha256": lm.model_sha256})
            return
        if cmd.get("v") != PROTOCOL:
            raise CommandError("bad_command", f"версия обмена {cmd.get('v')} — "
                                              f"спутник говорит на {PROTOCOL}")
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
            raise CommandError("bad_command",
                               f"команда «{name}» — в следующей версии спутника")
        else:
            raise CommandError("bad_command", f"неизвестная команда «{name}»")

    def _selfcheck(self, cmd: dict) -> None:
        t = selfcheck.load_thresholds()
        for key, field in (("seconds", "measure_s"), ("warmup", "warmup_s")):
            if cmd.get(key) is not None:
                if not isinstance(cmd[key], (int, float)) or cmd[key] < 0:
                    raise CommandError("bad_command", f"«{key}» — не число секунд")
                t[field] = float(cmd[key])
        camera = _camera(cmd)
        folder = Path(cmd.get("dir") or ".")
        with self.lock:
            if self.session is not None and not self.session.dead:
                raise CommandError("camera_busy", "Камера занята записью")
        result = selfcheck.measure(
            lambda mode: self.rt.open_capture(mode, camera),
            lambda: Processor(self.rt.landmarker()), CpuMeter(), t, folder,
            progress=lambda p: self.out.send({"progress": "selfcheck", **p}),
            abort=self.abort.is_set,
            preview=(lambda p: self.out.send({"progress": "preview", **p},
                                             droppable=True))
            if cmd.get("preview") is True else None,
        )
        if self.abort.is_set():
            return
        m = result.get("measures", {})
        if m.get("camera") == "ok" and m.get("height"):
            self.rt.mode = (int(m["width"]), int(m["height"]))
        if cmd.get("dir"):
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "selfcheck.json").write_text(
                json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
        self.out.send({"reply": "selfcheck", **result})

    def _on_session_fail(self, code: str, text: str) -> None:
        self._error(code, text, "record")

    def _open(self, cmd: dict) -> None:
        with self.lock:
            if self.abort.is_set():
                return
            if self.session is not None:
                if not self.session.dead:
                    raise CommandError("bad_command", "Запись уже идёт")
                self._close_session(send=False)
            self.session = Session(self.rt, cmd, self._on_session_fail)
            handler = logging.FileHandler(self.session.dir / "log.txt", encoding="utf-8")
            handler.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
            log.addHandler(handler)
            self._log_handler = handler
            log.info("open %s", cmd.get("dir"))
            self.out.send({"reply": "open",
                           "frame": [self.session.capture.source.width,
                                     self.session.capture.source.height]})

    def _close(self) -> None:
        with self.lock:
            self._close_session(send=True)

    def _close_session(self, send: bool) -> None:
        s = self.session
        self.session = None
        summary = s.close() if s is not None else None
        if s is not None:
            log.info("close %s", summary)
        if self._log_handler is not None:
            log.removeHandler(self._log_handler)
            self._log_handler.close()
            self._log_handler = None
        if send:
            self.out.send({"reply": "closed", "summary": summary})

    def _error(self, code: str, text: str, cmd: str | None = None) -> None:
        msg = {"error": code, "text": text}
        if cmd:
            msg["cmd"] = cmd
        log.info("error %s: %s", code, text)
        self.out.send(msg)

    def shutdown(self) -> None:
        self._hb_stop.set()
        with self.lock:
            if self.session is not None:
                self._close_session(send=False)
            self.rt.close()


def serve(rt: Runtime) -> int:
    """Главный поток читает stdin, команды исполняет рабочий поток: так
    конец stdin замечается и посреди долгой самопроверки. Команды,
    стоявшие в очереди к концу stdin, уже не исполняются."""
    out = Outbox(sys.stdout)
    server = Server(rt, out)
    server.start()
    commands: queue.Queue = queue.Queue()

    def work() -> None:
        while True:
            line = commands.get()
            if line is None or server.abort.is_set():
                return
            server.handle(line)

    worker = threading.Thread(target=work, name="eye-cmd", daemon=True)
    worker.start()
    try:
        for line in sys.stdin:
            line = line.strip()
            if line:
                commands.put(line)
    finally:
        deadline = time.monotonic() + EXIT_DEADLINE_S
        # Сторож: если завершение застряло (камера не отпускает, драйвер
        # висит), процесс уходит сам — приложение ждать не обязано.
        guard = threading.Timer(EXIT_DEADLINE_S, lambda: os._exit(0))
        guard.daemon = True
        guard.start()
        server.abort.set()
        commands.put(None)
        worker.join(timeout=max(0.0, deadline - time.monotonic() - 0.9))
        server.shutdown()
        out.close(timeout=max(0.05, deadline - time.monotonic() - 0.1))
        guard.cancel()
    return 0
