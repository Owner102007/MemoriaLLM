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

Калибровка (шаг 28, ET-03; SNO-ALG-EYE-02) идёт внутри открытой
камеры — между `open` и `close`:

* у `open` необязательный `write` (по умолчанию `true`): `false` —
  камера и распознавание без файлов и без папки (быстрая «Проверка
  айтрекера»); `screen` — `{w, h, w_mm, h_mm}`: окно приложения в
  логических пикселях и в миллиметрах, `distance_mm` — расстояние до
  экрана; без них калибровке не в чем считать углы;
* `calibrate {attempt, kind}` → `{reply: calibrate}` — новая попытка
  (`kind`: `full` — как у участника, `quick` — 9 точек без слежения);
* `target {id, x, y, phase, qpc_us, path?}` — без ответа: точка фазы
  `calib`, `pursuit` или `validate` появилась на экране в миг `qpc_us`
  (QPC приложения), `off` — точек нет; у `pursuit` — путь
  `{cx, cy, ax, ay, tx_ms, ty_ms}` (фигура Лиссажу), который спутник
  сам продолжает по времени;
* `samples {phase}` → сколько годных кадров у каждой точки, какие
  повторить (`short`) и доля кадров с лицом (`face`);
* `fit` → модель, ошибка «без одной точки», задержка камеры;
* `validate` → точность, прецизионность, худшая точка, приём;
* `live {on}` → `{reply: live, on}`; пока включено — по строке на кадр
  `{g, s, ok, t}`: оценка взгляда, сглаженная для глаза, годен ли кадр,
  его QPC. Эти строки выбрасываются первыми, если приложение не успевает
  читать.

Поправка на голову (шаг 29, BUG-60): у `target` фаза `head` — точка в
середине, человек водит головой, глядя на неё (её кадры учат остаток
поправки); `samples {phase: head}` — сколько кадров и доля лица. Пока
последняя точка — фазы `head`, спутник шлёт по строке на кадр с лицом
`{hm: [turn, tilt], far, t}` (правка `v0.35.1`, BUG-61): поворот головы к
правому краю экрана и наклон вниз против опоры калибровки (градусы),
`far` — голова дальше того, что остаток может выучить, `t` — QPC кадра.
По ним приложение ведёт подсказку и кольцо фазы. Эти строки
выбрасываются первыми, как строки живой точки. Проверка точности без
новой калибровки:

* `check {n}` → `{reply: check, n}` — начата проверка `n`; точки — `target`
  с фазой `check`;
* `checked` → `{reply: checked, n, accuracy_deg, …, variants, head,
  start_deg}` — точность каждого способа поправки и где была голова против
  калибровки.

У сессии с файлами итог калибровки ложится в `calibration.json` её папки
после `fit`, `validate`, `checked` и `close`, итоги проверок — ещё и в
`checks.json`. Камера, пропавшая во время записи, —
ошибка `camera_lost` без ответа на команду; поиск вернувшейся камеры
придёт с ET-06.
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

from . import PROTOCOL, VERSION, calib, clock, featfile, selfcheck
from .blink import BLINK_SCORE
from .capture import MODES, CameraError
from .landmarks import ModelError
from .processing import Processor, Recorder
from .runtime import CpuMeter, Runtime

log = logging.getLogger("sno_eye")

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

    def __init__(self, rt: Runtime, cmd: dict, on_fail, on_frame=None):
        write = cmd.get("write", True)
        if not isinstance(write, bool):
            raise CommandError("bad_command", "«write» — true или false")
        if write and not cmd.get("dir"):
            raise CommandError("bad_command", "нет папки записи")
        seg = _int(cmd, "seg", 0)
        n0 = _int(cmd, "n0", 0)
        mode = _mode(cmd, rt)
        camera = _camera(cmd)
        self.write = write
        self.dir = Path(cmd["dir"]) if write else None
        lm = rt.landmarker()  # модель — до камеры: не загрузилась, камера свободна
        if self.dir is not None:
            self.dir.mkdir(parents=True, exist_ok=True)
        self.capture = rt.open_capture(mode, camera)
        self.recorder: Recorder | None = None
        if write:
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
                                         strip=bool(cmd.get("strip", True)),
                                         header=header)
            except BaseException:
                self.capture.stop()
                raise
        self.processor = Processor(lm)
        self._on_frame = on_frame
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
                if self.recorder is not None:
                    self.recorder.add(frame)
                if self._on_frame is not None:
                    self._on_frame(frame)
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
        if self.recorder is not None:
            try:
                summary = self.recorder.close()
            except OSError as e:
                summary = {"error": str(e)}
        else:
            summary = {"frames": self.frames, "face": self.face}
        summary.update({"dropped": self.capture.stats.dropped,
                        "lost": self.capture.stats.lost, "dead": self.dead,
                        "camera_released": released})
        if self.dir is not None:
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
        # Калибровка открытой сессии (SNO-ALG-EYE-02) и живая точка.
        self.calib: calib.Calibration | None = None
        self.live = False
        self._smoother = calib.Smoother()
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
        elif name == "calibrate":
            self._calibrate(cmd)
        elif name == "target":
            self._target(cmd)
        elif name == "samples":
            self._samples(cmd)
        elif name == "fit":
            self._fit()
        elif name == "validate":
            self._validate()
        elif name == "live":
            self._live(cmd)
        elif name == "check":
            self._check(cmd)
        elif name == "checked":
            self._checked()
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
            screen = calib.Screen.from_open(cmd.get("screen"), cmd.get("distance_mm"))
            self.calib = calib.Calibration(screen, selfcheck.load_thresholds())
            self.live = False
            self._smoother = calib.Smoother()
            self.rt.observe_screen(screen)
            self.session = Session(self.rt, cmd, self._on_session_fail,
                                   on_frame=self._on_frame)
            # Геометрии головы нужен размер кадра камеры (BUG-60).
            src = self.session.capture.source
            self.calib.frame = (int(src.width), int(src.height))
            if self.session.dir is not None:
                handler = logging.FileHandler(self.session.dir / "log.txt",
                                              encoding="utf-8")
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
        self.live = False
        summary = s.close() if s is not None else None
        cal = self.calib
        self.calib = None
        if s is not None and cal is not None and cal.attempts:
            self._write_calibration(s, cal)
            if summary is not None:
                last = cal.attempts[-1]
                summary["calibration"] = {
                    "attempts": len(cal.attempts),
                    "fit": last.fit, "validation": _brief(last.validation)}
        if s is not None:
            log.info("close %s", summary)
        if self._log_handler is not None:
            log.removeHandler(self._log_handler)
            self._log_handler.close()
            self._log_handler = None
        if send:
            self.out.send({"reply": "closed", "summary": summary})

    # --- калибровка (SNO-ALG-EYE-02) ------------------------------------

    def _on_frame(self, frame) -> None:
        """Кадр после распознавания — в буфер калибровки и, если включена,
        в живую точку. Поток распознавания."""
        cal = self.calib
        if cal is None:
            return
        flags = int(frame.record["flags"])
        ok = (frame.feat is not None
              and not flags & (featfile.NO_FACE | featfile.HEAD_TURNED)
              and (frame.blink_score is None or frame.blink_score <= BLINK_SCORE))
        qpc = frame.grabbed.qpc_us
        cal.add(qpc, frame.feat, ok)
        if not flags & featfile.NO_FACE:
            # Фаза движения головы (BUG-61): где голова — приложению на
            # подсказку; моргание позе не мешает.
            try:
                head = cal.head_live(frame.feat)
            except Exception:  # noqa: BLE001 — подсказка не стоит записи
                log.exception("head_live")
                head = None
            if head is not None:
                self.out.send({"hm": [round(head["turn"], 1), round(head["tilt"], 1)],
                               "far": head["far"], "t": qpc}, droppable=True)
        if not self.live:
            return
        g = cal.predict(frame.feat) if ok else None
        if g is None:
            # Моргнул, отвернулся: точка стоит, где стояла, пока не прошло
            # полсекунды, — иначе она мигала бы на каждом моргании (BUG-59).
            held = self._smoother.held
            fresh = self._smoother.t is not None and qpc - self._smoother.t <= self._smoother.gap
            self.out.send({"g": None,
                           "s": [round(held[0], 1), round(held[1], 1)] if held and fresh else None,
                           "ok": False, "t": qpc}, droppable=True)
            return
        sx, sy = self._smoother.push(qpc, g[0], g[1])
        self.out.send({"g": [round(g[0], 1), round(g[1], 1)],
                       "s": [round(sx, 1), round(sy, 1)], "ok": True, "t": qpc},
                      droppable=True)

    def _calibration(self) -> calib.Calibration:
        with self.lock:
            s, cal = self.session, self.calib
        if s is None or cal is None:
            raise CommandError("bad_command", "Калибровке нужна открытая камера: "
                                              "сначала open")
        if s.dead:
            raise CommandError("camera_lost", "Камера пропала")
        return cal

    def _calibrate(self, cmd: dict) -> None:
        cal = self._calibration()
        n = _int(cmd, "attempt", len(cal.attempts) + 1)
        kind = cmd.get("kind", "full")
        try:
            cal.begin(n, kind, clock.qpc_us())
        except calib.CalibrationError as e:
            raise CommandError(e.code, e.text) from None
        self.live = False
        self.out.send({"reply": "calibrate", "attempt": n, "kind": kind})

    def _target(self, cmd: dict) -> None:
        cal = self._calibration()
        try:
            ev = calib.target_from_command(cmd)
            cal.target(ev)
        except ValueError as e:
            raise CommandError("bad_command", f"точка: {e}") from None
        except calib.CalibrationError as e:
            raise CommandError(e.code, e.text) from None
        self.rt.observe_target(ev)

    def _samples(self, cmd: dict) -> None:
        cal = self._calibration()
        phase = cmd.get("phase", "calib")
        if phase not in ("calib", "validate", "head", "check"):
            raise CommandError("bad_command",
                               "«phase» — calib, validate, head или check")
        try:
            res = cal.samples(phase)
        except calib.CalibrationError as e:
            raise CommandError(e.code, e.text) from None
        self.out.send({"reply": "samples", **res})

    def _fit(self) -> None:
        cal = self._calibration()
        try:
            res = cal.fit()
        except calib.CalibrationError as e:
            raise CommandError(e.code, e.text) from None
        self._smoother = calib.Smoother(cal.noise_px)
        self._write_calibration(self.session, cal)
        self.out.send({"reply": "fit", "attempt": cal.attempt.n, **res})

    def _validate(self) -> None:
        cal = self._calibration()
        try:
            res = cal.validate()
        except calib.CalibrationError as e:
            raise CommandError(e.code, e.text) from None
        self._write_calibration(self.session, cal)
        self.out.send({"reply": "validate", "attempt": cal.attempt.n, **res})

    def _check(self, cmd: dict) -> None:
        cal = self._calibration()
        n = _int(cmd, "n", len(cal.checks) + 1)
        try:
            cal.begin_check(n, clock.qpc_us())
        except calib.CalibrationError as e:
            raise CommandError(e.code, e.text) from None
        self.out.send({"reply": "check", "n": n})

    def _checked(self) -> None:
        cal = self._calibration()
        try:
            res = cal.check_result()
        except calib.CalibrationError as e:
            raise CommandError(e.code, e.text) from None
        self._write_calibration(self.session, cal)
        self.out.send({"reply": "checked", **res})

    def _live(self, cmd: dict) -> None:
        on = cmd.get("on")
        if not isinstance(on, bool):
            raise CommandError("bad_command", "«on» — true или false")
        cal = self._calibration()
        if on and cal.model is None:
            raise CommandError("bad_command", "Живой точке нужна модель: сначала fit")
        self._smoother = calib.Smoother(cal.noise_px)
        self.live = on
        self.out.send({"reply": "live", "on": on})

    @staticmethod
    def _write_calibration(s: "Session | None", cal: calib.Calibration) -> None:
        if s is None or s.dir is None:
            return
        try:
            (s.dir / "calibration.json").write_text(
                json.dumps(cal.to_json(), ensure_ascii=False), encoding="utf-8")
            if cal.checks:
                (s.dir / "checks.json").write_text(json.dumps(
                    [c.result for c in cal.checks if c.result is not None],
                    ensure_ascii=False, indent=1), encoding="utf-8")
        except OSError as e:
            log.info("calibration.json: %s", e)

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


def _brief(validation: dict | None) -> dict | None:
    if not validation:
        return None
    return {k: validation.get(k) for k in ("accuracy_deg", "accuracy_cm", "precision_deg",
                                            "worst_deg", "accepted", "reason")}


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
