"""Где лежит папка `eye/` и её файлы.

В сборке `eye/` стоит рядом с `memoria.exe`, а пакет `sno_eye` — внутри
неё; в репозитории — так же. Поэтому корень — родитель пакета.
"""

from __future__ import annotations

import os
from pathlib import Path

EYE_ROOT = Path(__file__).resolve().parent.parent


def model_path() -> Path:
    return EYE_ROOT / "models" / "face_landmarker.task"


def model_version_path() -> Path:
    return EYE_ROOT / "model_version.txt"


def thresholds_path() -> Path:
    return EYE_ROOT / "thresholds.json"


def bench_root() -> Path:
    """Папка стенда: рядом со спутником, а если туда не пишется —
    в папке данных пользователя."""
    here = EYE_ROOT / "bench"
    try:
        here.mkdir(parents=True, exist_ok=True)
        probe = here / ".probe"
        probe.write_bytes(b"")
        probe.unlink()
        return here
    except OSError:
        base = os.environ.get("LOCALAPPDATA") or str(Path.home())
        alt = Path(base) / "Memoria" / "eye-bench"
        alt.mkdir(parents=True, exist_ok=True)
        return alt


def read_kv(path: Path) -> dict[str, str]:
    """Файл вида `ключ=значение`; строки с `#` — комментарии."""
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        out[key.strip()] = value.strip()
    return out
