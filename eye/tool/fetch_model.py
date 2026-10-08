"""Скачать модель лица по замку `eye/model_version.txt` и сверить сумму.

    python eye/tool/fetch_model.py [папка]

По умолчанию кладёт в `eye/models/`. Сумма не закреплена или не
совпала — отказ, и посчитанная сумма напечатана: закрепляется она
осознанно, правкой замка.
"""

from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

EYE = Path(__file__).resolve().parent.parent


def read_kv(path: Path) -> dict[str, str]:
    out = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


def fetch(url: str, dest: Path) -> str:
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    h = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=120) as r, open(part, "wb") as f:
        for chunk in iter(lambda: r.read(1 << 20), b""):
            f.write(chunk)
            h.update(chunk)
    part.replace(dest)
    return h.hexdigest()


def main() -> int:
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else EYE / "models"
    kv = read_kv(EYE / "model_version.txt")
    dest = folder / "face_landmarker.task"
    got = fetch(kv["url"], dest)
    print(f"face_landmarker.task: sha256={got}, {dest.stat().st_size} байт")
    if got != kv.get("sha256"):
        print(f"::error title=Модель лица::сумма {got} не равна закреплённой "
              f"{kv.get('sha256')} — закрепите в eye/model_version.txt, если файл тот")
        dest.unlink()
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
