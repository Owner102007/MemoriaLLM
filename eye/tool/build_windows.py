"""Собрать папку `eye/` для ZIP ветви на Windows-раннере (SNO-F-EYE-04).

    python eye/tool/build_windows.py build/eye

Запускается Python той же версии, что в `eye/python_version.txt`
(колёса ставятся им в папку `site` чужого, встраиваемого Python).

1. Встраиваемый Python с python.org — сверка SHA-256 по замку и
   подписи `python.exe` (Authenticode, издатель — Python Software
   Foundation).
2. Файл путей `python3XX._pth`: архив стандартной библиотеки, `.` (там
   лежит `sno_eye`) и `site`.
3. Колёса — строго по замку: `--require-hashes --only-binary :all:
   --no-deps`.
4. Чистка: `__pycache__`, папки тестов чужих пакетов, примеры данных
   matplotlib.
5. Наш код, ярлыки, пороги, замки и лицензии; модель лица — по замку.

Любое расхождение суммы — отказ. Размер папки печатается и
проверяется бюджетом.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

EYE = Path(__file__).resolve().parent.parent
BUDGET_MB = 400
COPY = ["sno_eye", "thresholds.json", "model_version.txt", "python_version.txt",
        "requirements.lock", "THIRD_PARTY_NOTICES.txt", "README.md",
        "Проверка камеры.cmd", "Проверка камеры (40 минут).cmd"]


def read_kv(path: Path) -> dict[str, str]:
    out = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


def download(url: str, dest: Path) -> str:
    h = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=180) as r, open(dest, "wb") as f:
        for chunk in iter(lambda: r.read(1 << 20), b""):
            f.write(chunk)
            h.update(chunk)
    return h.hexdigest()


def fail(text: str) -> None:
    print(f"::error title=Спутник взгляда::{text}")
    sys.exit(1)


def folder_mb(path: Path) -> float:
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file()) / 1e6


def main() -> None:
    out = Path(sys.argv[1]).resolve()
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    tmp = out.parent / "eye-tmp"
    tmp.mkdir(exist_ok=True)

    pv = read_kv(EYE / "python_version.txt")
    want_minor = ".".join(pv["version"].split(".")[:2])
    have_minor = f"{sys.version_info.major}.{sys.version_info.minor}"
    if want_minor != have_minor:
        fail(f"сборка запущена Python {have_minor}, а замок — на {want_minor}")
    embed = tmp / "python-embed.zip"
    got = download(pv["url"], embed)
    print(f"встраиваемый Python {pv['version']}: sha256={got}")
    if got != pv["sha256_embed_amd64"]:
        fail(f"сумма встраиваемого Python {got} не равна закреплённой "
             f"{pv['sha256_embed_amd64']} — закрепите в eye/python_version.txt, "
             "если файл тот")
    with zipfile.ZipFile(embed) as z:
        z.extractall(out)

    exe = out / "python.exe"
    sig = subprocess.run(
        ["pwsh", "-NoProfile", "-NonInteractive", "-Command",
         "$s = Get-AuthenticodeSignature -LiteralPath $env:SNO_EYE_EXE; "
         "Write-Output ([string]$s.Status); "
         "Write-Output ([string]$s.SignerCertificate.Subject)"],
        capture_output=True, text=True, env={**os.environ, "SNO_EYE_EXE": str(exe)})
    status, _, subject = sig.stdout.strip().partition("\n")
    print(f"подпись python.exe: {status.strip()}; {subject.strip()}")
    if sig.returncode != 0 or sig.stderr.strip():
        print(sig.stderr)
    if status.strip() != "Valid" or "Python Software Foundation" not in subject:
        fail("python.exe не подписан Python Software Foundation")

    pths = list(out.glob("python3*._pth"))
    if len(pths) != 1:
        fail(f"в встраиваемом Python не один файл путей: {pths}")
    stdlib = next(out.glob("python3*.zip")).name
    pths[0].write_text(f"{stdlib}\n.\nsite\n", encoding="utf-8")

    site = out / "site"
    subprocess.run([sys.executable, "-m", "pip", "install", "--disable-pip-version-check",
                    "--no-compile", "--require-hashes", "--only-binary", ":all:",
                    "--no-deps", "--target", str(site), "-r",
                    str(EYE / "requirements.lock")], check=True)
    # Чужие тесты, кэш байт-кода, примеры данных — сборке не нужны.
    for p in sorted(site.rglob("__pycache__"), reverse=True):
        shutil.rmtree(p, ignore_errors=True)
    for name in ("tests", "testing"):
        for p in sorted(site.glob(f"*/{name}"), reverse=True):
            if p.is_dir() and p.parent.name in ("numpy", "matplotlib", "fontTools",
                                                  "contourpy", "kiwisolver"):
                shutil.rmtree(p, ignore_errors=True)
    for p in site.glob("numpy/*/tests"):
        shutil.rmtree(p, ignore_errors=True)
    shutil.rmtree(site / "matplotlib" / "mpl-data" / "sample_data", ignore_errors=True)
    # Видеоввод OpenCV через FFmpeg (≈ 30 МБ) спутнику не нужен: камера
    # читается через DirectShow, а полоса глаз пишется PyAV.
    for p in site.glob("cv2/opencv_videoio_ffmpeg*.dll"):
        p.unlink()
    for p in site.glob("*.dist-info"):
        # Лицензии остаются; RECORD и прочее — нет: pip в папке не живёт.
        for f in p.iterdir():
            if f.is_file() and not f.name.upper().startswith(("LICENSE", "COPYING",
                                                               "METADATA", "NOTICE")):
                f.unlink()

    for name in COPY:
        src = EYE / name
        if src.is_dir():
            shutil.copytree(src, out / name,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        else:
            shutil.copy2(src, out / name)

    # Байт-код — заранее: иначе первый запуск у участника компилировал бы
    # numpy, matplotlib и MediaPipe и долго не отвечал на `hello`, а в
    # папке без права записи — каждый запуск. Python раннера той же
    # младшей версии, байт-код совместим.
    subprocess.run([sys.executable, "-m", "compileall", "-q", "-j", "0",
                    str(site), str(out / "sno_eye")], check=False)
    # fontTools и mpl_toolkits при работе спутника не загружаются — их
    # байт-код только занимал бы место.
    for name in ("fontTools", "mpl_toolkits"):
        for p in sorted((site / name).rglob("__pycache__"), reverse=True):
            shutil.rmtree(p, ignore_errors=True)

    mv = read_kv(EYE / "model_version.txt")
    (out / "models").mkdir()
    model = out / "models" / "face_landmarker.task"
    got = download(mv["url"], model)
    print(f"модель лица: sha256={got}")
    if got != mv.get("sha256"):
        fail(f"сумма модели {got} не равна закреплённой {mv.get('sha256')} — "
             "закрепите в eye/model_version.txt, если файл тот")

    shutil.rmtree(tmp, ignore_errors=True)
    size = folder_mb(out)
    parts = {p.name: round(folder_mb(p), 1) for p in sorted(site.iterdir()) if p.is_dir()}
    largest = dict(sorted(parts.items(), key=lambda kv: -kv[1])[:8])
    report = {"size_mb": round(size, 1), "budget_mb": BUDGET_MB,
              "python": pv["version"], "largest_mb": largest}
    (out.parent / "eye-build.json").write_text(json.dumps(report, ensure_ascii=False, indent=1),
                                               encoding="utf-8")
    print(f"папка eye/: {size:.0f} МБ (бюджет {BUDGET_MB}); крупнее всего: {largest}")
    if size > BUDGET_MB:
        fail(f"папка eye/ — {size:.0f} МБ, больше бюджета {BUDGET_MB} МБ")


if __name__ == "__main__":
    main()
