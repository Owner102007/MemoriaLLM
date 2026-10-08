"""Самопроверка места (SNO-ALG-EYE-04).

Две части: замер (камера, 2 с прогрева и 5 с распознавания) и чистое
правило `evaluate` — по каждой проверке «годится / с оговоркой / не
годится» с причиной словами и общий итог. Правило тестируется на
придуманных замерах; замер — на синтетическом источнике и у владельца.

Строки «окно» (окно приложения на весь выбранный монитор) здесь нет:
окно — забота приложения (ET-02).

Для экрана «Место записи» замер умеет отдавать маленький кадр камеры
(`preview`, шаг 27): JPEG шириной 320 точек не чаще пяти раз в секунду и
рамку лица в долях кадра. Рамку рисует приложение — кадр уходит как
есть.
"""

from __future__ import annotations

import base64
import json
import shutil
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np

from . import features, paths

GOOD, WARN, FAIL = "good", "warn", "fail"
CRITICAL = ("satellite", "camera", "mode", "fps", "face", "iris")
WORDS = {GOOD: "годится", WARN: "годится с оговоркой", FAIL: "не годится"}


def load_thresholds(path: Path | None = None) -> dict:
    return json.loads((path or paths.thresholds_path()).read_text(encoding="utf-8"))


def _row(check: str, verdict: str, value: Any, text: str) -> dict:
    return {"id": check, "verdict": verdict, "value": value, "text": text}


def _higher(value: float, good: float, warn: float) -> str:
    if value >= good:
        return GOOD
    if value >= warn:
        return WARN
    return FAIL


def _lower(value: float, good: float, warn: float) -> str:
    if value <= good:
        return GOOD
    if value <= warn:
        return WARN
    return FAIL


CAMERA_TEXT = {
    "camera_denied": "Камера запрещена в параметрах Windows — разрешите "
                     "классическим приложениям доступ к камере",
    "camera_busy": "Камера занята другой программой — закройте Teams, Zoom, браузер",
    "no_camera": "Камера не найдена",
    "camera_lost": "Камера отключилась во время проверки",
}


def evaluate(m: dict, t: dict) -> dict:
    """Замеры `m` → строки проверки и итог.

    Ключи `m`: `satellite` (True или текст причины), `camera` (`ok` или
    код ошибки), `width`, `height`, `fps`, `face_share`, `iris_px`,
    `light`, `backlight`, `glare`, `position`, `disk_free_bytes`,
    `cpu_percent`. Чего не намерили (камера не открылась) — нет в ответе.
    """
    rows: list[dict] = []
    sat = m.get("satellite", True)
    if sat is not True:
        rows.append(_row("satellite", FAIL, None, f"Айтрекер не запустился: {sat}"))
        return _summary(rows)
    rows.append(_row("satellite", GOOD, True, "Спутник запущен"))

    cam = m.get("camera", "ok")
    if cam != "ok":
        rows.append(_row("camera", FAIL, cam, CAMERA_TEXT.get(cam, f"Камера: {cam}")))
        _disk(rows, m, t)
        return _summary(rows)
    rows.append(_row("camera", GOOD, "ok", "Камера открылась"))

    w, h = int(m.get("width", 0)), int(m.get("height", 0))
    mt = t["mode"]
    if h >= mt["good_h"]:
        rows.append(_row("mode", GOOD, [w, h], f"Режим {w}×{h}"))
    elif h >= mt["warn_h"]:
        rows.append(_row("mode", WARN, [w, h], f"Режим {w}×{h}: 1080p камера не держит"))
    else:
        rows.append(_row("mode", FAIL, [w, h], f"Камера слишком слабая: {w}×{h}"))

    fps = float(m.get("fps", 0.0))
    v = _higher(fps, t["fps"]["good"], t["fps"]["warn"])
    rows.append(_row("fps", v, round(fps, 1), _fps_text(fps, v, fps_limit(m, t))))

    share = float(m.get("face_share", 0.0))
    v = _higher(share, t["face_share"]["good"], t["face_share"]["warn"])
    pct = round(100 * share)
    text = {GOOD: f"Лицо в кадре: {pct} %",
            WARN: f"Лицо в кадре не всё время: {pct} %",
            FAIL: f"Камера не видит лица — сядьте напротив ({pct} %)"}[v]
    rows.append(_row("face", v, round(share, 3), text))

    if share > 0 and m.get("iris_px") is not None:
        iris = float(m["iris_px"])
        v = _higher(iris, t["iris_px"]["good"], t["iris_px"]["warn"])
        text = {GOOD: f"Радужка {iris:.0f} пикс.",
                WARN: f"Мелко: радужка {iris:.0f} пикс. — проверьте режим камеры "
                      "и расстояние по метке",
                FAIL: f"Глаза в кадре слишком мелкие ({iris:.0f} пикс.): нужен 1080p "
                      "или камера ближе к экрану"}[v]
        rows.append(_row("iris", v, round(iris, 1), text))
    else:
        rows.append(_row("iris", FAIL, None, "Глаз не видно — радужку не измерить"))

    if m.get("light") is not None:
        light = float(m["light"])
        lt = t["light"]
        if lt["good_min"] <= light <= lt["good_max"]:
            v, text = GOOD, f"Свет {light:.0f}"
        elif light < lt["warn_min"]:
            v, text = FAIL, f"Добавьте свет спереди ({light:.0f})"
        elif light > lt["fail_max"]:
            v, text = FAIL, f"Пересвет ({light:.0f})"
        elif light < lt["good_min"]:
            v, text = WARN, f"Темновато ({light:.0f}) — добавьте свет спереди"
        else:
            v, text = WARN, f"Светловато ({light:.0f})"
        rows.append(_row("light", v, round(light, 1), text))

    if m.get("backlight") is not None:
        b = float(m["backlight"])
        v = _higher(b, t["backlight"]["good"], t["backlight"]["warn"])
        text = {GOOD: f"Свет сзади не мешает ({b:.2f})",
                WARN: f"Сзади светло ({b:.2f})",
                FAIL: f"Окно или лампа за спиной ({b:.2f})"}[v]
        rows.append(_row("backlight", v, round(b, 3), text))

    if m.get("glare") is not None:
        g = float(m["glare"])
        v = GOOD if g < t["glare"]["good"] else (WARN if g <= t["glare"]["warn"] else FAIL)
        text = {GOOD: "Бликов нет",
                WARN: f"Есть блики ({100 * g:.1f} %)",
                FAIL: f"Блики на глазах — поверните лампу ({100 * g:.1f} %)"}[v]
        rows.append(_row("glare", v, round(g, 4), text))

    if m.get("position") is not None:
        p = float(m["position"])
        v = _lower(p, t["position"]["good"], t["position"]["warn"])
        text = {GOOD: "Лицо по центру кадра",
                WARN: f"Лицо не по центру ({100 * p:.0f} % ширины)",
                FAIL: f"Сядьте по центру камеры ({100 * p:.0f} % ширины)"}[v]
        rows.append(_row("position", v, round(p, 3), text))

    _disk(rows, m, t)

    if m.get("cpu_percent") is not None:
        c = float(m["cpu_percent"])
        v = _lower(c, t["cpu_percent"]["good"], t["cpu_percent"]["warn"])
        text = {GOOD: f"Процессор {c:.0f} %",
                WARN: f"Процессор {c:.0f} %: взгляд может прерываться",
                FAIL: f"Слабый ПК: процессор {c:.0f} %, взгляд может прерываться"}[v]
        rows.append(_row("cpu", v, round(c, 1), text))
    return _summary(rows)


def fps_limit(m: dict, t: dict) -> str | None:
    """Кто упёрся в частоту кадров (BUG-58): `camera` — камера сама даёт
    столько кадров (обычно от недостатка света: в тусклом свете камера
    удлиняет выдержку), `pc` — ПК не успевает их обрабатывать, `None` —
    замер этого не знает (самопроверка прежней версии).

    ПК не успевает, если захват выбросил заметную долю кадров или
    обработка кадра занимает почти весь промежуток между кадрами камеры.
    """
    grabbed_fps = m.get("camera_fps")
    proc_ms = m.get("proc_ms")
    drops = m.get("drop_share")
    if grabbed_fps is None or proc_ms is None or drops is None:
        return None
    lim = t.get("fps_limit", {"drop_share": 0.05, "proc_share": 0.8})
    interval_ms = 1000.0 / max(1e-6, float(grabbed_fps))
    if float(drops) > lim["drop_share"] or float(proc_ms) > lim["proc_share"] * interval_ms:
        return "pc"
    return "camera"


def _fps_text(fps: float, verdict: str, limit: str | None) -> str:
    if verdict == GOOD:
        return f"Частота {fps:.1f} к/с"
    if limit == "camera":
        if verdict == WARN:
            return (f"Частота {fps:.1f} к/с — камере мало света: "
                    "поставьте лампу перед лицом")
        return (f"Камера сама даёт {fps:.1f} к/с — ей мало света: "
                "поставьте лампу перед лицом")
    if limit == "pc":
        if verdict == WARN:
            return f"Частота {fps:.1f} к/с — ПК едва успевает"
        return f"ПК не успевает: {fps:.1f} к/с"
    if verdict == WARN:
        return f"Частота {fps:.1f} к/с"
    return f"Мало света или слабый ПК: {fps:.1f} к/с"


def _disk(rows: list[dict], m: dict, t: dict) -> None:
    if m.get("disk_free_bytes") is None:
        return
    gb = float(m["disk_free_bytes"]) / 1e9
    v = _higher(gb, t["disk_gb"]["good"], t["disk_gb"]["warn"])
    text = {GOOD: f"Свободно {gb:.1f} ГБ",
            WARN: f"Мало места: {gb:.1f} ГБ",
            FAIL: f"Мало места на диске для взгляда: {gb:.1f} ГБ"}[v]
    rows.append(_row("disk", v, round(gb, 2), text))


def _summary(rows: list[dict]) -> dict:
    if any(r["verdict"] == FAIL and r["id"] in CRITICAL for r in rows):
        verdict = FAIL
    elif any(r["verdict"] != GOOD for r in rows):
        verdict = WARN
    else:
        verdict = GOOD
    return {"verdict": verdict, "words": WORDS[verdict], "checks": rows}


# --- замер ---------------------------------------------------------------

@dataclass
class Measures:
    frames: int = 0
    face: int = 0
    iris: list = field(default_factory=list)
    light: list = field(default_factory=list)
    backlight: list = field(default_factory=list)
    glare: list = field(default_factory=list)
    position: list = field(default_factory=list)

    def add(self, frame) -> None:
        """Замер кадра. Свет, блики и место лица меряются на каждом пятом
        кадре и по серой копии: замер не вправе съедать частоту, которую
        сам же и меряет."""
        self.frames += 1
        if frame.px is None:
            return
        self.face += 1
        self.iris.append(float(frame.feat[-1]))
        if self.face % 5 != 1:
            return
        import cv2

        img = frame.grabbed.frame
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img
        w, h = frame.width, frame.height
        vals, bright, total = [], 0, 0
        for x0, y0, x1, y1 in features.eye_boxes(frame.px, w, h):
            patch = gray[y0:y1, x0:x1]
            if patch.size:
                vals.append(float(patch.mean()))
                bright += int(np.count_nonzero(patch >= 250))
                total += patch.size
        if vals:
            self.light.append(float(np.mean(vals)))
            self.glare.append(bright / max(1, total))
        fx0, fy0, fx1, fy1 = features.face_box(frame.px, w, h)
        face = gray[fy0:fy1, fx0:fx1]
        all_sum = float(gray.sum(dtype=np.int64))
        face_sum = float(face.sum(dtype=np.int64))
        rest_n = gray.size - face.size
        if face.size and rest_n > 0:
            rest_mean = (all_sum - face_sum) / rest_n
            self.backlight.append((face_sum / face.size) / max(1.0, rest_mean))
        cx, cy = (fx0 + fx1) / 2, (fy0 + fy1) / 2
        self.position.append(float(np.hypot(cx - w / 2, cy - h / 2) / w))

    def result(self, seconds: float) -> dict:
        med = (lambda xs: float(np.median(xs)) if xs else None)
        return {
            "fps": self.frames / seconds if seconds > 0 else 0.0,
            "face_share": self.face / self.frames if self.frames else 0.0,
            "iris_px": med(self.iris),
            "light": med(self.light),
            "backlight": med(self.backlight),
            "glare": med(self.glare),
            "position": med(self.position),
        }


PREVIEW_WIDTH = 320
PREVIEW_PERIOD_S = 0.2
PREVIEW_QUALITY = 70


def preview_message(frame) -> dict | None:
    """Кадр после распознавания → `{jpeg, w, h, face}` для приложения.

    `jpeg` — base64 кадра, уменьшенного до 320 точек в ширину; `face` —
    рамка лица `[x0, y0, x1, y1]` в долях кадра или `None`. Кадр не
    отдаётся (`None`), если его не удалось сжать: живая картинка — не
    повод для ошибки.
    """
    import cv2

    img = frame.grabbed.frame
    h, w = img.shape[:2]
    if w <= 0 or h <= 0:
        return None
    pw = min(PREVIEW_WIDTH, w)
    ph = max(1, round(h * pw / w))
    small = cv2.resize(img, (pw, ph), interpolation=cv2.INTER_AREA) if pw != w else img
    ok, buf = cv2.imencode(".jpg", small, [int(cv2.IMWRITE_JPEG_QUALITY), PREVIEW_QUALITY])
    if not ok:
        return None
    face = None
    if frame.px is not None:
        x0, y0, x1, y1 = features.face_box(frame.px, frame.width, frame.height)
        face = [round(x0 / frame.width, 4), round(y0 / frame.height, 4),
                round(x1 / frame.width, 4), round(y1 / frame.height, 4)]
    return {"jpeg": base64.b64encode(buf.tobytes()).decode("ascii"),
            "w": pw, "h": ph, "face": face}


class _Preview:
    """Не чаще одного кадра за `PREVIEW_PERIOD_S`."""

    def __init__(self, send):
        self._send = send
        self._last = -1e9

    def offer(self, frame) -> None:
        if self._send is None:
            return
        now = time.perf_counter()
        if now - self._last < PREVIEW_PERIOD_S:
            return
        self._last = now
        msg = preview_message(frame)
        if msg is not None:
            self._send(msg)


def disk_free(folder: Path) -> int:
    folder = Path(folder)
    while not folder.exists() and folder != folder.parent:
        folder = folder.parent
    return shutil.disk_usage(folder).free


def measure(open_source, processor_factory, cpu_meter, thresholds: dict,
            folder: Path, progress=None, mode=None, abort=None,
            preview=None) -> dict:
    """Замер на камере: прогрев, затем `measure_s` секунд распознавания.

    `processor_factory()` → `Processor` (модель грузится до камеры:
    модель не загрузилась — камера не открыта и не занята);
    `open_source(mode)` → запущенный `Capture` (или `CameraError`);
    `cpu_meter` — `start()`/`stop()` → процент процессора. Если 1080p не
    держит 25 к/с с распознаванием, замер повторяется в 720p (решение
    Т24) — но 720p берётся, только если он дал заметно больше кадров
    (`mode_switch_gain`, решение Т27, BUG-58): когда кадров мало даёт сама
    камера, 720p частоты не прибавляет, а глаза в кадре делает мельче.
    Оба замера лежат в `measures.tried`. Камера закрывается при любом
    исходе. `preview(msg)` — если назван, получает маленький кадр камеры
    (`preview_message`).
    """
    from .capture import MODES, CameraError

    stopped = abort or (lambda: False)
    shots = _Preview(preview)
    m: dict[str, Any] = {"satellite": True, "disk_free_bytes": disk_free(folder)}
    modes = [mode] if mode else list(MODES)
    gain = float(thresholds.get("mode_switch_gain", 1.0))
    chosen = None
    tried: list[dict] = []
    for k, md in enumerate(modes):
        proc = processor_factory()
        try:
            cap = open_source(md)
        except CameraError as e:
            if chosen is not None:
                # 1080p уже намерен: камера, отказавшая в 720p, места не
                # портит — остаётся то, что было.
                break
            m["camera"] = e.code
            return {**evaluate(m, thresholds), "measures": m}
        m["camera"] = "ok"
        try:
            res, lost = _measure_mode(cap, proc, cpu_meter, thresholds, progress,
                                      stopped, shots)
        finally:
            cap.stop()
        if stopped():
            return {"verdict": FAIL, "words": WORDS[FAIL], "checks": [],
                    "measures": m, "aborted": True}
        if lost:
            m["camera"] = "camera_lost"
            return {**evaluate(m, thresholds), "measures": m}
        tried.append({"mode": [res["width"], res["height"]],
                      "fps": round(res["fps"], 1)})
        if chosen is None:
            chosen = res
        elif res["fps"] >= chosen["fps"] * gain:
            chosen = res
        elif progress:
            progress({"stage": "keep", "mode": [chosen["width"], chosen["height"]],
                      "fps": round(chosen["fps"], 1)})
        if chosen["fps"] >= thresholds["mode_switch_fps"] or k == len(modes) - 1:
            break
        if progress:
            progress({"stage": "switch", "from": [res["width"], res["height"]],
                      "fps": round(res["fps"], 1)})
    m.update(chosen or {})
    m["tried"] = tried
    return {**evaluate(m, thresholds), "measures": m}


def _measure_mode(cap, proc, cpu_meter, thresholds, progress, stopped, shots=None):
    shots = shots or _Preview(None)
    if progress:
        progress({"stage": "warmup", "mode": [cap.source.width, cap.source.height]})
    warm_until = time.perf_counter() + thresholds["warmup_s"]
    while time.perf_counter() < warm_until and not stopped():
        g = cap.get(0.5)
        if g is not None:
            shots.offer(proc.process(g))
        elif cap.stats.lost:
            return None, True
    if progress:
        progress({"stage": "measure"})
    meas = Measures()
    proc_ms: list[float] = []
    cpu_meter.start()
    grabbed0, dropped0 = cap.stats.grabbed, cap.stats.dropped
    t0 = time.perf_counter()
    end = t0 + thresholds["measure_s"]
    while time.perf_counter() < end and not stopped():
        g = cap.get(0.5)
        if g is None:
            if cap.stats.lost:
                cpu_meter.stop()
                return None, True
            continue
        p0 = time.perf_counter()
        frame = proc.process(g)
        proc_ms.append(1000.0 * (time.perf_counter() - p0))
        meas.add(frame)
        shots.offer(frame)
    seconds = time.perf_counter() - t0
    cpu = cpu_meter.stop()
    grabbed = cap.stats.grabbed - grabbed0
    dropped = cap.stats.dropped - dropped0
    res = meas.result(seconds)
    # BUG-58: сколько кадров дала сама камера, сколько выбросил захват и
    # сколько длится обработка — по ним видно, кто упёрся в частоту.
    res.update({"width": cap.source.width, "height": cap.source.height,
                "cpu_percent": cpu, "dropped": cap.stats.dropped,
                "camera_fps": grabbed / seconds if seconds > 0 else 0.0,
                "drop_share": dropped / grabbed if grabbed else 0.0,
                "proc_ms": float(np.median(proc_ms)) if proc_ms else None})
    return res, False
