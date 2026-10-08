"""Собрать замок колёс спутника взгляда (SNO-F-EYE-04) — осознанно!

    python3 eye/tool/make_lock.py

Скачивает колёса по `requirements.in` для Windows (сборка) и Linux
(тесты на раннере) под одну версию Python и пишет `requirements.lock`:
каждая зависимость — точная версия и суммы колёс обеих платформ.
Ставится сборкой строго `--require-hashes --only-binary :all:`.
То же для `requirements-dev.in` (pytest, только Linux).

Версии на двух платформах обязаны совпасть — иначе отказ: тесты
проверяли бы не то, что уезжает в сборку.
"""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

EYE = Path(__file__).resolve().parent.parent
PY = "3.13"
PLATFORMS = {
    "windows": ["win_amd64"],
    "linux": ["manylinux_2_28_x86_64", "manylinux_2_17_x86_64",
              "manylinux2014_x86_64", "manylinux_2_12_x86_64",
              "manylinux2010_x86_64", "linux_x86_64"],
}


def download(req: Path, platforms: list[str], dest: Path) -> dict[str, tuple[str, list[Path]]]:
    cmd = [sys.executable, "-m", "pip", "download", "-q", "-r", str(req),
           "--python-version", PY, "--only-binary=:all:", "-d", str(dest)]
    for p in platforms:
        cmd += ["--platform", p]
    subprocess.run(cmd, check=True)
    out: dict[str, tuple[str, list[Path]]] = {}
    for whl in sorted(dest.glob("*.whl")):
        name, version = whl.name.split("-")[:2]
        key = re.sub(r"[-_.]+", "-", name).lower()
        out.setdefault(key, (version, []))[1].append(whl)
    return out


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_lock(target: Path, sets: list[dict[str, tuple[str, list[Path]]]], note: str) -> None:
    names = sorted(set().union(*sets))
    lines = [f"# {note}",
             f"# Собран tool/make_lock.py для Python {PY}. Руками не править.",
             ""]
    for name in names:
        versions = {s[name][0] for s in sets if name in s}
        if len(versions) != 1:
            raise SystemExit(f"{name}: версии расходятся по платформам: {versions}")
        hashes = sorted({sha(p) for s in sets if name in s for p in s[name][1]})
        lines.append(f"{name}=={versions.pop()} \\")
        lines += [f"    --hash=sha256:{h} \\" for h in hashes[:-1]]
        lines.append(f"    --hash=sha256:{hashes[-1]}")
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{target.name}: {len(names)} пакетов")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        win = download(EYE / "requirements.in", PLATFORMS["windows"], t / "win")
        lin = download(EYE / "requirements.in", PLATFORMS["linux"], t / "lin")
        if set(win) != set(lin):
            raise SystemExit(f"состав расходится: {set(win) ^ set(lin)}")
        write_lock(EYE / "requirements.lock", [win, lin],
                   "Колёса спутника взгляда: Windows (сборка) и Linux (тесты).")
        dev = download(EYE / "requirements-dev.in", PLATFORMS["linux"], t / "dev")
        main_names = set(win)
        dev = {k: v for k, v in dev.items() if k not in main_names}
        write_lock(EYE / "requirements-dev.lock", [dev],
                   "Только тесты на Linux-раннере; ставится вместе с requirements.lock.")


if __name__ == "__main__":
    main()
