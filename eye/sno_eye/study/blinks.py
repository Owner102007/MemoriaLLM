"""Частота морганий по ходу сессии (SNO-ALG-RES-15; шаг 43, решение
владельца АО11 от 12.10.2026).

Откуда данные: поток взгляда `eye/gaze.jsonl` архива, прочитанный
«Разбором записи» (`report.archive.load`, `record.gaze`): на каждом
кадре `conf` — 1 минус наибольший блендшейп `eyeBlink` модели лица
(`sno_eye/gaze.py`, `GazeWriter.add`), поза (`yaw`) — есть, только
когда лицо видно; границы изучения — ход сессии `report.timeline`.
Технология: стандартная библиотека.
Метод:
* кадр моргания — лицо видно, а `conf` меньше `1 − BLINK_SCORE`: тот
  же порог, по которому спутник помечает кадр негодным
  (`sno_eye/blink.py`);
* моргание — подряд идущие кадры моргания (просвет не больше полутора
  кадров) не длиннее `BLINK_MAX_US` (долгое прикрытие глаз — не
  моргание), с годным кадром лица по обе стороны — иначе это потеря
  лица или край сегмента, а не моргание;
* частота — морганий в минуту времени, когда лицо видно; ход —
  ln((последняя треть + 0,5) / (первая треть + 0,5)) по частотам третей
  изучения (+0,5 — чтобы треть без морганий не давала бесконечность).
  Утомление учащает моргание: Stern J. A., Boyer D., Schroeder D.
  «Blink rate: a possible measure of fatigue», Human Factors, 1994,
  36(2):285; бдительность при зрительной задаче — реже: Bentivoglio A.
  R. и др. «Analysis of blink rate patterns in normal subjects»,
  Movement Disorders, 1997, 12(6):1028.
Вход → выход: кадры потока взгляда и границы изучения → моргания и их
частота за изучение и по третям.
"""

from __future__ import annotations

import math

from ..blink import BLINK_MAX_US, BLINK_SCORE

# Частота кадров ниже — моргание в 100–150 мс проходит между кадрами.
MIN_FPS = 15.0
# Соседние кадры дальше этой доли промежутка между кадрами — разрыв.
GAP_PERIODS = 1.5


def _num(value) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if math.isfinite(value) else None


def _period(rows: list[dict]) -> float | None:
    gaps = sorted(b["t"] - a["t"] for a, b in zip(rows, rows[1:])
                  if 0 < b["t"] - a["t"] < 200)
    return gaps[len(gaps) // 2] if gaps else None


def measure(gaze: list[dict], lo: float, hi: float) -> dict:
    """Моргания изучения [lo, hi) по кадрам потока взгляда [gaze].

    Ответ: `per_min` — за изучение, `thirds` — частота по третям,
    `change` — ход (ln последней трети к первой), `count`, `face_min` —
    минут видимого лица, `fps`, `reason` — почему не считается."""
    out: dict = {"count": None, "per_min": None, "thirds": None,
                 "change": None, "face_min": None, "fps": None,
                 "duration_ms": None, "reason": None}
    rows = []
    for r in gaze:
        t = _num(r.get("t"))
        if t is None or not lo <= t < hi:
            continue
        face = _num(r.get("yaw")) is not None
        conf = _num(r.get("conf"))
        rows.append({"t": t, "face": face,
                     "blink": face and conf is not None
                     and conf < 1.0 - BLINK_SCORE,
                     "seg": r.get("seg")})
    if len(rows) < 2:
        out["reason"] = "потока взгляда в изучении нет"
        return out
    period = _period(rows)
    fps = 1000.0 / period if period else None
    out["fps"] = fps
    if fps is None or fps < MIN_FPS:
        out["reason"] = (f"кадров в секунду меньше {MIN_FPS:g} — моргание "
                         "проходит между кадрами")
        return out
    limit = GAP_PERIODS * period
    max_ms = BLINK_MAX_US / 1000
    # Минуты видимого лица — кадр весит промежуток до следующего, не
    # больше полутора кадров.
    third = (hi - lo) / 3
    face_ms = [0.0, 0.0, 0.0]
    for a, b in zip(rows, rows[1:] + [None]):
        if not a["face"]:
            continue
        span = min(limit, (b["t"] - a["t"]) if b else period)
        face_ms[min(2, int((a["t"] - lo) // third))] += max(0.0, span)
    blinks: list[tuple[float, float]] = []
    i = 0
    n = len(rows)
    while i < n:
        if not rows[i]["blink"]:
            i += 1
            continue
        j = i
        while j + 1 < n and rows[j + 1]["blink"] and \
                0 < rows[j + 1]["t"] - rows[j]["t"] <= limit and \
                rows[j + 1]["seg"] == rows[i]["seg"]:
            j += 1
        before = rows[i - 1] if i > 0 else None
        after = rows[j + 1] if j + 1 < n else None
        length = rows[j]["t"] - rows[i]["t"] + period
        framed = (before is not None and after is not None
                  and before["face"] and not before["blink"]
                  and after["face"] and not after["blink"]
                  and 0 < rows[i]["t"] - before["t"] <= limit
                  and 0 < after["t"] - rows[j]["t"] <= limit
                  and before["seg"] == rows[i]["seg"] == after["seg"])
        if framed and length <= max_ms:
            blinks.append((rows[i]["t"], length))
        i = j + 1
    total_min = sum(face_ms) / 60_000
    out["face_min"] = total_min
    if total_min <= 0:
        out["reason"] = "лица в изучении не видно"
        return out
    counts = [0, 0, 0]
    for t, _ in blinks:
        counts[min(2, int((t - lo) // third))] += 1
    rates = [counts[k] / (face_ms[k] / 60_000) if face_ms[k] > 0 else None
             for k in range(3)]
    out["count"] = len(blinks)
    out["per_min"] = len(blinks) / total_min
    out["thirds"] = rates
    out["counts"] = counts
    lengths = sorted(length for _, length in blinks)
    out["duration_ms"] = lengths[len(lengths) // 2] if lengths else None
    if face_ms[0] > 0 and face_ms[2] > 0:
        first = (counts[0] + 0.5) / (face_ms[0] / 60_000)
        last = (counts[2] + 0.5) / (face_ms[2] / 60_000)
        out["change"] = math.log(last / first)
    return out
