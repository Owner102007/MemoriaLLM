"""Поток взгляда записи — `gaze.jsonl` (SNO-F-REC-04, SNO-F-EYE-02).

Строка на кадр, схема `sno2026-gaze/1`:

* `n` — сквозной номер строки с единицы, как у потоков ввода и кадров
  раскладки: через перезапуски спутника он не начинается заново, а
  продолжает последнюю целую строку файла;
* `t` — время кадра по часам записи, мс: `t0 + (qpc - qpc0) / 1000` по
  паре «QPC — t», которую приложение называет в `open`;
* `x`, `y` — оценка взгляда моделью принятой калибровки в логических
  пикселях окна, без сглаживания; `null`, когда кадр негоден;
* `ok` — кадр годен: лицо есть, голова не отвёрнута, не моргание;
* `conf` — уверенность: 0 без лица, иначе один минус сила моргания;
* `dist` — расстояние относительно калибровки (1 — как на ней, больше —
  дальше); `null` без лица;
* `yaw`, `pitch`, `roll` — поза головы, градусы; `open_l`, `open_r` —
  раскрытие глаз; без лица — `null`;
* `seg` — сегмент файлов (номер подъёма спутника).

Строки пишутся пачкой раз в секунду. Оборванная последняя строка —
спутник сняли посреди записи — отрезается при следующем открытии, а
номер продолжает последнюю целую.

Здесь же сторож лица: лица нет дольше секунды — строка `face: lost`
приложению, вернулось — `face: back` с длительностью.
"""

from __future__ import annotations

import json
from pathlib import Path

from . import faceparts as fp

SCHEMA = "sno2026-gaze/1"
GAZE_FILE = "gaze.jsonl"

# Сколько кадров без лица — уже «лица нет» (SNO-F-EYE-02).
FACE_LOST_MS = 1000

# Как часто пачка строк уходит на диск.
FLUSH_US = 1_000_000

_TAIL_BLOCK = 64 * 1024

_I = {name: i for i, name in enumerate(fp.FEATURE_NAMES)}


def repair_tail(path: Path) -> int:
    """Готовит файл к дозаписи и отвечает номером следующей строки.

    Файла нет — единица. Оборванная последняя строка (без перевода
    строки) отрезается. Номер — у последней целой строки, которая
    читается как JSON с `n`, плюс один; таких нет — единица."""
    if not path.exists():
        return 1
    size = path.stat().st_size
    with open(path, "r+b") as f:
        # Конец последней целой строки.
        end = size
        cut = 0
        while end > 0:
            start = max(0, end - _TAIL_BLOCK)
            f.seek(start)
            chunk = f.read(end - start)
            at = chunk.rfind(b"\n")
            if at >= 0:
                cut = start + at + 1
                break
            end = start
        if cut < size:
            f.truncate(cut)
        # Номер последней целой строки, которая читается.
        end = cut
        tail = b""
        while end > 0:
            start = max(0, end - _TAIL_BLOCK)
            f.seek(start)
            tail = f.read(end - start) + tail
            lines = tail.split(b"\n")
            # Первая строка куска может быть неполной, если кусок начат
            # не с начала файла: её не разбираем, пока не дочитаем.
            whole = lines if start == 0 else lines[1:]
            for line in reversed(whole):
                if not line.strip():
                    continue
                try:
                    n = json.loads(line).get("n")
                except (ValueError, AttributeError):
                    continue
                if isinstance(n, int) and not isinstance(n, bool):
                    return n + 1
            if start == 0:
                return 1
            tail = lines[0]
            end = start
        return 1


class GazeWriter:
    """Пишет `gaze.jsonl` в папку записи."""

    def __init__(self, folder: Path, seg: int, qpc0_us: int | None, t0: int | None):
        self.path = Path(folder) / GAZE_FILE
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.n0 = repair_tail(self.path)
        self.n = self.n0
        self.seg = seg
        self.qpc0_us = qpc0_us
        self.t0 = t0
        self._f = open(self.path, "ab")
        self._buf: list[bytes] = []
        self._last_flush: int | None = None
        self.lines = 0
        self.ok = 0
        self.closed = False

    def t_of(self, qpc_us: int) -> int | None:
        if self.qpc0_us is None or self.t0 is None:
            return None
        return int(self.t0 + round((qpc_us - self.qpc0_us) / 1000))

    def add(self, qpc_us: int, g: tuple[float, float] | None, ok: bool,
            feat=None, blink: float | None = None, dist: float | None = None) -> int:
        """Строка кадра; отвечает её номером."""
        if self.closed:
            return -1
        face = feat is not None
        line = {
            "n": self.n,
            "t": self.t_of(qpc_us),
            "x": round(float(g[0]), 1) if ok and g is not None else None,
            "y": round(float(g[1]), 1) if ok and g is not None else None,
            "ok": bool(ok and g is not None),
            "conf": (round(max(0.0, 1.0 - float(blink or 0.0)), 2) if face else 0.0),
            "dist": round(float(dist), 3) if face and dist is not None else None,
            "yaw": round(float(feat[_I["yaw"]]), 1) if face else None,
            "pitch": round(float(feat[_I["pitch"]]), 1) if face else None,
            "roll": round(float(feat[_I["roll"]]), 1) if face else None,
            "open_l": round(float(feat[_I["open_l"]]), 3) if face else None,
            "open_r": round(float(feat[_I["open_r"]]), 3) if face else None,
            "seg": self.seg,
        }
        self._buf.append(json.dumps(line, separators=(",", ":")).encode("utf-8") + b"\n")
        n = self.n
        self.n += 1
        self.lines += 1
        if line["ok"]:
            self.ok += 1
        if self._last_flush is None:
            self._last_flush = qpc_us
        elif qpc_us - self._last_flush >= FLUSH_US:
            self.flush()
            self._last_flush = qpc_us
        return n

    def flush(self) -> None:
        if not self._buf or self.closed:
            return
        data = b"".join(self._buf)
        self._buf = []
        self._f.write(data)
        self._f.flush()

    def close(self) -> dict:
        if not self.closed:
            try:
                self.flush()
            finally:
                self.closed = True
                self._f.close()
        return {
            "file": GAZE_FILE, "schema": SCHEMA, "seg": self.seg,
            "lines": self.lines, "ok": self.ok,
            "valid_share": round(self.ok / self.lines, 4) if self.lines else None,
            "first_n": self.n0 if self.lines else None,
            "last_n": self.n - 1 if self.lines else None,
        }


class FaceWatch:
    """Сторож лица: лица нет дольше [lost_ms] — «лицо потеряно», вернулось
    — «лицо вернулось» с длительностью."""

    def __init__(self, lost_ms: int = FACE_LOST_MS):
        self.lost_us = lost_ms * 1000
        self.missing_since: int | None = None
        self.lost = False

    def push(self, qpc_us: int, face: bool) -> dict | None:
        if face:
            if self.lost:
                since = self.missing_since or qpc_us
                self.lost = False
                self.missing_since = None
                return {"face": "back", "t": qpc_us,
                        "ms": int((qpc_us - since) // 1000)}
            self.missing_since = None
            return None
        if self.missing_since is None:
            self.missing_since = qpc_us
            return None
        if not self.lost and qpc_us - self.missing_since >= self.lost_us:
            self.lost = True
            return {"face": "lost", "t": qpc_us, "since": self.missing_since}
        return None
