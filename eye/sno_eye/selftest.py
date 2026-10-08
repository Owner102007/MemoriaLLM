"""Пробный запуск `python -I -m sno_eye --selftest` (SNO-F-EYE-04).

Проверяет, что папка `eye/` собрана правильно и работает на этой
машине без камеры и без человека:

1. версии: Python, MediaPipe, OpenCV, PyAV;
2. модель лица на месте и сверена по SHA-256;
3. на пустом кадре распознавание честно говорит «лица нет»;
4. H.264 пишется и читается обратно;
5. камера: найдена или отказ сказан словами (на раннере камеры нет).

Последняя строка вывода — итог JSON. Код выхода 0 — всё, что от сборки
зависит, в порядке; отсутствие камеры сборку не валит.
`--linger N` держит распознавание ещё N секунд — чтобы CI успел увидеть
сетевые соединения процесса.
"""

from __future__ import annotations

import json
import platform
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

from . import VERSION, PROTOCOL


def run(linger: float = 0.0, source: str = "camera") -> int:
    out: dict = {"satellite": VERSION, "protocol": PROTOCOL,
                 "python": platform.python_version(),
                 "platform": platform.platform(), "ok": False}
    lines: list[str] = []

    def say(text: str) -> None:
        lines.append(text)
        print(text, flush=True)

    import cv2
    import av

    out["opencv"] = cv2.__version__
    out["av"] = av.__version__
    try:
        import mediapipe as mp
        out["mediapipe"] = getattr(mp, "__version__", "?")
    except Exception as e:  # noqa: BLE001
        say(f"MediaPipe не загрузился: {e}")
        print(json.dumps(out, ensure_ascii=False))
        return 1
    say(f"Спутник {VERSION}, Python {out['python']}, MediaPipe {out['mediapipe']}, "
        f"OpenCV {out['opencv']}, PyAV {out['av']}")

    from .landmarks import MediaPipeLandmarker, ModelError

    try:
        lm = MediaPipeLandmarker()
    except ModelError as e:
        say(f"Модель лица: {e}")
        out["model"] = str(e)
        print(json.dumps(out, ensure_ascii=False))
        return 1
    out["model_sha256"] = lm.model_sha256
    say(f"Модель лица сверена: {lm.model_sha256[:12]}…")

    blank = np.full((720, 1280, 3), 128, np.uint8)
    det = lm.detect(blank, 0)
    out["blank_frame"] = "no_face" if det.face is None else "face"
    if det.face is not None:
        say("Ошибка: на пустом кадре найдено лицо")
        print(json.dumps(out, ensure_ascii=False))
        return 1
    say("Пустой кадр: лица нет — как и должно быть")

    from .eyestrip import StripWriter, count_readable, has_x264

    if not has_x264():
        say("H.264 (libx264) в PyAV нет — полосу глаз писать нечем")
        out["x264"] = False
        print(json.dumps(out, ensure_ascii=False))
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp) / "probe.mp4"
        w = StripWriter(p)
        for k in range(45):
            w.write(np.full((64, 256, 3), k * 5 % 255, np.uint8))
        w.close()
        out["x264"] = count_readable(p) == 45
    say("H.264 пишется и читается" if out["x264"] else "H.264: файл не читается")
    if not out["x264"]:
        print(json.dumps(out, ensure_ascii=False))
        return 1

    from .runtime import Runtime
    from .capture import CameraError, MODES

    rt = Runtime(source)
    cams = rt.cameras()
    out["cameras"] = [c.as_dict() for c in cams]
    if not cams:
        out["camera"] = "no_camera"
        say("Камера не найдена")
    else:
        try:
            cap = rt.open_capture(MODES[1])
            cap.stop()
            out["camera"] = "ok"
            say(f"Камера открылась: {cams[0].name}")
        except CameraError as e:
            out["camera"] = e.code
            say(e.text)

    t_end = time.perf_counter() + linger
    k = 1
    while time.perf_counter() < t_end:
        lm.detect(blank, k * 33)
        k += 1
        time.sleep(0.03)
    lm.close()
    out["ok"] = True
    print(json.dumps(out, ensure_ascii=False), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(run())
