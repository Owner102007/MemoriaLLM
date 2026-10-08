"""Стенд «Проверка камеры» (SNO-F-EYE-04, ворота Г1).

Запускается ярлыком `eye\\Проверка камеры.cmd` без приложения: выбор
камеры, самопроверка места, затем замер — по умолчанию две минуты,
`--minutes 40` для долгого прогона. Всё это время спутник делает то же,
что будет делать в записи: распознаёт лицо, считает признаки, пишет
`features.bin` и полосу глаз; первые две минуты полоса пишется ещё и в
размере 128 × 512 — для сравнения в ET-08.

Итог — `bench.json` в папке стенда: камера и режим, частота, пропуски,
загрузка процессора, память, итог самопроверки и решение по воротам Г1.
"""

from __future__ import annotations

import json
import platform
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np

from . import VERSION, paths, selfcheck
from .capture import CameraError
from .processing import Processor, Recorder
from .runtime import CpuMeter, Runtime

SCHEMA = "sno2026-eyebench/1"
EXTRA_STRIP_SECONDS = 120.0
WINDOW = "Memoria SNO - camera check (Esc - stop)"

# Ворота Г1 («Айтрекер — схема системы», раздел «Ворота»).
GATE = {"fps": 25.0, "drops_share": 0.02, "cpu_percent": 35.0, "memory_growth_mb": 50.0}


def choose_camera(rt: Runtime, index: int | None, interactive: bool) -> dict | None:
    cams = rt.cameras()
    if not cams:
        return None
    if index is not None:
        for c in cams:
            if c.index == index:
                return c.as_dict()
        print(f"Камеры с номером {index} нет — беру первую")
    if len(cams) == 1 or not interactive:
        return cams[0].as_dict()
    print("Камеры:")
    for k, c in enumerate(cams, 1):
        print(f"  {k}. {c.name}")
    while True:
        answer = input("Какая камера над экраном? Номер: ").strip()
        if answer.isdigit() and 1 <= int(answer) <= len(cams):
            return cams[int(answer) - 1].as_dict()


def gate_of(result: dict, minutes: float) -> dict:
    g = {
        "fps_ok": result["fps"]["mean"] >= GATE["fps"],
        "drops_ok": result["drops"]["share"] <= GATE["drops_share"],
        "cpu_ok": result["cpu"]["mean_percent"] <= GATE["cpu_percent"],
    }
    # Рост памяти — мера долгого прогона; за две минуты он ни о чём.
    if minutes >= 30:
        g["memory_ok"] = result["memory"]["growth_mb"] <= GATE["memory_growth_mb"]
    g["pass"] = all(g.values())
    return g


def run(minutes: float = 2.0, camera: int | None = None, window: bool = True,
        source: str = "camera", out_dir: Path | None = None,
        interactive: bool = True, selfcheck_seconds: float | None = None) -> int:
    rt = Runtime(source)
    folder = out_dir or paths.bench_root() / datetime.now().strftime("%Y%m%d-%H%M%S")
    folder.mkdir(parents=True, exist_ok=True)
    started = datetime.now().astimezone().isoformat(timespec="seconds")
    result: dict = {
        "schema": SCHEMA, "satellite": VERSION, "started": started,
        "python": platform.python_version(), "os": platform.platform(),
        "minutes_planned": minutes, "source": source,
    }
    try:
        import os
        import cv2
        import av
        result["opencv"] = cv2.__version__
        result["av"] = av.__version__
        result["cpu_count"] = os.cpu_count()
        result["machine"] = platform.processor() or platform.machine()
    except Exception:  # noqa: BLE001
        pass

    cam = choose_camera(rt, camera, interactive)
    result["camera"] = cam

    print("Самопроверка места: 2 с прогрева и 5 с замера…")
    t = selfcheck.load_thresholds()
    if selfcheck_seconds is not None:
        t["measure_s"] = selfcheck_seconds
        t["warmup_s"] = min(t["warmup_s"], selfcheck_seconds / 2)
    try:
        lm = rt.landmarker()
    except Exception as e:  # noqa: BLE001
        sc = selfcheck.evaluate({"satellite": str(e)}, t)
        _print_check(sc)
        result["selfcheck"] = sc
        _write(folder, result)
        return 1
    result["mediapipe"] = lm.version
    result["model_sha256"] = lm.model_sha256
    if cam is None:
        sc = {**selfcheck.evaluate({"satellite": True, "camera": "no_camera",
                                    "disk_free_bytes": selfcheck.disk_free(folder)}, t)}
    else:
        sc = selfcheck.measure(
            lambda mode: rt.open_capture(mode, cam),
            lambda: Processor(lm), CpuMeter(), t, folder,
            progress=lambda p: _progress(p))
    _print_check(sc)
    result["selfcheck"] = sc
    (folder / "selfcheck.json").write_text(json.dumps(sc, ensure_ascii=False, indent=1),
                                           encoding="utf-8")
    measures = sc.get("measures", {})
    if measures.get("camera") != "ok":
        print("Замер не проводится: камера не открылась.")
        _write(folder, result)
        return 1

    mode = (int(measures["width"]), int(measures["height"]))
    try:
        cap = rt.open_capture(mode, cam)
    except CameraError as e:
        print(e.text)
        result["error"] = e.code
        _write(folder, result)
        return 1
    result["mode"] = [cap.source.width, cap.source.height]
    rec = Recorder(folder, strip=True, extra_sizes=("128x512",),
                   extra_seconds=EXTRA_STRIP_SECONDS,
                   header={"frame": result["mode"], "satellite": VERSION,
                           "mediapipe": lm.version, "model_sha256": lm.model_sha256,
                           "bench": True})
    proc = Processor(lm)
    cpu = CpuMeter()
    mem_start = cpu.rss_mb()
    mem_max = mem_start
    cpu_samples: list[float] = []
    per_second: dict[int, int] = {}
    proc_ms: list[float] = []
    first_qpc = last_qpc = None
    t0 = time.perf_counter()
    t_end = t0 + minutes * 60.0
    next_report = t0 + 5.0
    cpu.start()
    show = window
    stopped_by = "time"
    print(f"Замер {minutes:g} мин. Листайте книгу в приложении, как при чтении. "
          "Esc в окне камеры или Ctrl+C — закончить раньше.")
    try:
        while time.perf_counter() < t_end:
            g = cap.get(0.5)
            if g is None:
                if cap.stats.lost:
                    stopped_by = "camera_lost"
                    print("Камера пропала.")
                    break
                continue
            a = time.perf_counter()
            frame = proc.process(g)
            rec.add(frame)
            proc_ms.append((time.perf_counter() - a) * 1000)
            first_qpc = first_qpc if first_qpc is not None else g.qpc_us
            last_qpc = g.qpc_us
            sec = int((g.qpc_us - first_qpc) // 1_000_000)
            per_second[sec] = per_second.get(sec, 0) + 1
            if show and rec.stats.frames % 2 == 0:
                show = _show(frame)
                if show is None:
                    stopped_by = "user"
                    break
            now = time.perf_counter()
            if now >= next_report:
                c = cpu.stop()
                cpu.start()
                cpu_samples.append(c)
                m = cpu.rss_mb()
                mem_max = max(mem_max, m)
                done = rec.stats.frames
                fps = sum(per_second.get(s, 0) for s in range(sec - 4, sec + 1)) / 5
                face = rec.stats.face / done if done else 0
                drops = cap.stats.dropped / max(1, cap.stats.grabbed)
                left = max(0, t_end - now)
                print(f"{fps:5.1f} к/с · пропуски {100 * drops:.1f} % · процессор "
                      f"{c:.0f} % · память {m:.0f} МБ · лицо {100 * face:.0f} % · "
                      f"осталось {int(left // 60)}:{int(left % 60):02d}", flush=True)
                next_report = now + 5.0
    except KeyboardInterrupt:
        stopped_by = "user"
    seconds = time.perf_counter() - t0
    tail = cpu.stop()
    if seconds > 1:
        cpu_samples.append(tail)
    cap.stop()
    summary = rec.close()
    _close_window(window)
    mem_end = cpu.rss_mb()
    mem_max = max(mem_max, mem_end)
    frames = summary["frames"]
    span_s = ((last_qpc - first_qpc) / 1e6) if first_qpc is not None and last_qpc != first_qpc else 0
    full_seconds = [per_second[s] for s in sorted(per_second)[1:-1]] or list(per_second.values())
    result.update({
        "finished": datetime.now().astimezone().isoformat(timespec="seconds"),
        "stopped_by": stopped_by,
        "seconds": round(seconds, 1),
        "frames": frames,
        "fps": {"mean": round((frames - 1) / span_s, 2) if span_s else 0.0,
                "p5": float(np.percentile(full_seconds, 5)) if full_seconds else 0.0},
        "drops": {"count": cap.stats.dropped,
                  "share": round(cap.stats.dropped / max(1, cap.stats.grabbed), 4)},
        "face_share": round(summary["face"] / frames, 4) if frames else 0.0,
        "ok_share": round(summary["ok"] / frames, 4) if frames else 0.0,
        "process_ms": {"p50": round(float(np.percentile(proc_ms, 50)), 1) if proc_ms else None,
                       "p95": round(float(np.percentile(proc_ms, 95)), 1) if proc_ms else None},
        "cpu": {"mean_percent": round(float(np.mean(cpu_samples)), 1) if cpu_samples else 0.0,
                "p95_percent": round(float(np.percentile(cpu_samples, 95)), 1)
                if cpu_samples else 0.0},
        "memory": {"start_mb": round(mem_start, 1), "end_mb": round(mem_end, 1),
                   "max_mb": round(mem_max, 1), "growth_mb": round(mem_end - mem_start, 1)},
        "strip": {"frames": summary["strip_frames"], "files": summary["files"]},
    })
    result["gate_g1"] = gate_of(result, seconds / 60.0)
    path = _write(folder, result)
    rt.close()
    _print_result(result, path)
    return 0


def _progress(p: dict) -> None:
    stage = p.get("stage")
    if stage == "switch":
        print(f"  1080p даёт {p['fps']} к/с — пробую 720p")


def _print_check(sc: dict) -> None:
    marks = {"good": "  годится    ", "warn": "  оговорка   ", "fail": "  НЕ ГОДИТСЯ "}
    for row in sc.get("checks", []):
        print(marks[row["verdict"]] + row["text"])
    print(f"Итог самопроверки: {sc.get('words')}")


def _show(frame) -> bool | None:
    try:
        import cv2
        img = frame.grabbed.frame
        h, w = img.shape[:2]
        k = 640 / w
        view = cv2.resize(img, (640, int(h * k)))
        if frame.px is not None:
            from .features import eye_boxes, face_box
            x0, y0, x1, y1 = face_box(frame.px, w, h)
            cv2.rectangle(view, (int(x0 * k), int(y0 * k)), (int(x1 * k), int(y1 * k)),
                          (80, 200, 80), 2)
            for bx0, by0, bx1, by1 in eye_boxes(frame.px, w, h):
                cv2.rectangle(view, (int(bx0 * k), int(by0 * k)),
                              (int(bx1 * k), int(by1 * k)), (60, 160, 230), 1)
        cv2.imshow(WINDOW, view)
        key = cv2.waitKey(1) & 0xFF
        if key in (27, ord("q")):
            return None
        return True
    except Exception:  # noqa: BLE001 — окна нет (сборка без highgui)
        return False


def _close_window(window: bool) -> None:
    if not window:
        return
    try:
        import cv2
        cv2.destroyAllWindows()
    except Exception:  # noqa: BLE001
        pass


def _write(folder: Path, result: dict) -> Path:
    path = folder / "bench.json"
    path.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    return path


def _print_result(r: dict, path: Path) -> None:
    g = r["gate_g1"]
    yes = {True: "да", False: "НЕТ"}
    print()
    print(f"Кадров в секунду: {r['fps']['mean']} (нужно ≥ {GATE['fps']:g}) — {yes[g['fps_ok']]}")
    print(f"Пропуски: {100 * r['drops']['share']:.2f} % (нужно ≤ 2 %) — {yes[g['drops_ok']]}")
    print(f"Процессор: {r['cpu']['mean_percent']} % (нужно ≤ 35 %) — {yes[g['cpu_ok']]}")
    if "memory_ok" in g:
        print(f"Рост памяти: {r['memory']['growth_mb']} МБ (нужно ≤ 50) — {yes[g['memory_ok']]}")
    print(f"Лицо в кадре: {100 * r['face_share']:.0f} %")
    print()
    print("Ворота Г1: " + ("пройдены" if g["pass"] else "НЕ пройдены"))
    print(f"Итог записан: {path}")
    print("Пришлите этот файл bench.json и скажите, не тормозило ли листание.")


if __name__ == "__main__":
    sys.exit(run())
