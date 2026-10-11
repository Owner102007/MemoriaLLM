"""SNO-F-CFG-07: «Обновить сборку исследования.cmd» (шаг 35).

Ярлык в `_MemoriaTest` ставит последнюю сборку исследования с GitHub
вместо `I\\` и `II\\`. Здесь его PowerShell-часть
(`tool/study_update/update_study.ps1`) гоняется настоящим PowerShell 7
против подставного GitHub на 127.0.0.1: список релизов и файлы релиза
отдаёт `http.server` из стандартной библиотеки. На Windows ярлык
запускает Windows PowerShell 5.1 — код писан под него; разница путей
между системами — в `Join-Path`.

Нет PowerShell (`pwsh`) — тесты пропускаются; на раннере GitHub он есть.
"""

from __future__ import annotations

import hashlib
import http.server
import io
import json
import os
import shutil
import subprocess
import sys
import threading
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tool" / "study_update"
SCRIPT = TOOL / "update_study.ps1"
REPO = "Owner102007/MemoriaLLM"


def pwsh() -> str | None:
    return os.environ.get("PWSH") or shutil.which("pwsh")


needs_pwsh = pytest.mark.skipif(pwsh() is None, reason="нет PowerShell 7")


def zip_of(tag: str, branch: str) -> bytes:
    """ZIP ветви: memoria.exe, тег в снимке кода, спутник."""
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as z:
        z.writestr("memoria.exe", f"memoria {branch} {tag}")
        z.writestr("data/app.so", b"\x00prefix\x00" + tag.encode() + b"\x00tail")
        z.writestr("eye/python.exe", "python")
        z.writestr("eye/Инструкция организатора.txt", "инструкция")
    return out.getvalue()


class FakeGitHub:
    """API релизов и файлы релизов на 127.0.0.1."""

    def __init__(self):
        self.files: dict[str, bytes] = {}
        self.requests: list[str] = []
        self.releases: list[dict] = []
        handler = self._handler()
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       daemon=True)
        self.thread.start()

    def _handler(self):
        fake = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):  # тихо
                pass

            def do_GET(self):  # noqa: N802
                path = self.path.split("?")[0]
                fake.requests.append(path)
                if path == f"/repos/{REPO}/releases":
                    body = json.dumps(fake.releases).encode()
                    kind = "application/json"
                elif path in fake.files:
                    body = fake.files[path]
                    kind = "application/octet-stream"
                else:
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Type", kind)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        return Handler

    def publish(self, tag: str, published: str, *, broken: str | None = None):
        assets = []
        sums = []
        for branch in ("I", "II"):
            name = f"memoria-sno2026-{branch}-windows.zip"
            data = zip_of(tag, branch)
            sums.append(f"{hashlib.sha256(data).hexdigest()}  {name}")
            if broken == branch:
                data = data[:-10] + b"0123456789"
            self.files[f"/{REPO}/releases/download/{tag}/{name}"] = data
            assets.append({"name": name, "size": len(data)})
        self.files[f"/{REPO}/releases/download/{tag}/SHA256SUMS.txt"] = (
            "\n".join(sums) + "\n").encode()
        self.releases.append({"tag_name": tag, "draft": False,
                              "prerelease": True, "published_at": published,
                              "assets": assets, "body": ""})

    def downloads(self) -> list[str]:
        return [r for r in self.requests if "/releases/download/" in r]

    def close(self):
        self.server.shutdown()
        self.server.server_close()


@pytest.fixture
def github():
    g = FakeGitHub()
    # Чужие релизы в списке тоже есть: катящийся и этапа.
    g.releases.append({"tag_name": "latest", "draft": False, "assets": [],
                       "published_at": "2026-10-11T10:00:00Z"})
    g.releases.append({"tag_name": "v0.45.0-alpha", "draft": False,
                       "assets": [], "published_at": "2026-10-11T11:00:00Z"})
    g.publish("sno2026-1", "2026-10-10T06:30:00Z")
    yield g
    g.close()


@pytest.fixture
def place(tmp_path):
    """_MemoriaTest со сборкой sno2026-1, распакованной руками (без метки)."""
    root = tmp_path / "_MemoriaTest"
    for branch in ("I", "II"):
        with zipfile.ZipFile(io.BytesIO(zip_of("sno2026-1", branch))) as z:
            z.extractall(root / branch)
    (root / "Проверка записи.cmd").write_text("rem", encoding="utf-8")
    data = tmp_path / "AppData" / "HohloBaron" / "Memoria LLM HB"
    data.mkdir(parents=True)
    return root, data


def run(root: Path, data: Path, github: FakeGitHub, *extra: str):
    env = dict(os.environ)
    env["NO_PROXY"] = env["no_proxy"] = "127.0.0.1,localhost"
    proc = subprocess.run(
        [pwsh(), "-NoProfile", "-NonInteractive", "-File", str(SCRIPT),
         "-Root", str(root), "-Api", github.url, "-Site", github.url,
         "-DataRoot", str(data), "-Yes", "-NoStop", *extra],
        capture_output=True, text=True, encoding="utf-8", env=env,
        timeout=120)
    return proc.returncode, proc.stdout + proc.stderr


def exe(root: Path, branch: str) -> str:
    return (root / branch / "memoria.exe").read_text(encoding="utf-8")


@needs_pwsh
def test_sno_f_cfg_07_new_study_build_replaces_i_and_ii(place, github):
    root, data = place
    github.publish("sno2026-2", "2026-10-11T18:00:00Z")

    code, out = run(root, data, github)

    assert code == 0, out
    assert "Ветвь I — сборка исследования sno2026-1" in out
    assert "Последняя сборка исследования — sno2026-2" in out
    for branch in ("I", "II"):
        assert exe(root, branch) == f"memoria {branch} sno2026-2"
        assert (root / branch / ".study-tag").read_text().strip() == "sno2026-2"
        assert (root / branch / "eye" / "Инструкция организатора.txt").exists()
        old = root / "_прежние" / "sno2026-1" / branch / "memoria.exe"
        assert old.read_text(encoding="utf-8") == f"memoria {branch} sno2026-1"
    # Загрузки убраны, рядом ничего лишнего; свои файлы папки на месте.
    assert not (root / "_download").exists()
    assert not (root / "I.new").exists()
    assert (root / "Проверка записи.cmd").exists()
    assert "Готово: стоит сборка исследования sno2026-2" in out
    assert "Забыть эталон" in out

    # Второй запуск: та же сборка — ничего не качает.
    github.requests.clear()
    code, out = run(root, data, github)
    assert code == 0, out
    assert "Уже стоит последняя сборка sno2026-2" in out
    assert github.downloads() == []


@needs_pwsh
def test_sno_f_cfg_07_same_build_downloads_nothing(place, github):
    root, data = place
    code, out = run(root, data, github)
    assert code == 0, out
    assert "Уже стоит последняя сборка sno2026-1 — скачивать нечего" in out
    assert github.downloads() == []
    assert exe(root, "I") == "memoria I sno2026-1"


@needs_pwsh
def test_sno_f_cfg_07_broken_zip_replaces_nothing(place, github):
    root, data = place
    github.publish("sno2026-2", "2026-10-11T18:00:00Z", broken="II")

    code, out = run(root, data, github)

    assert code == 1, out
    assert "сумма не сходится" in out
    assert "Ничего не изменено" in out
    # Ни одна ветвь не заменена — и та, чей ZIP цел.
    assert exe(root, "I") == "memoria I sno2026-1"
    assert exe(root, "II") == "memoria II sno2026-1"
    assert not (root / "_прежние").exists()


@needs_pwsh
def test_sno_f_cfg_07_open_session_stops_update(place, github):
    root, data = place
    github.publish("sno2026-2", "2026-10-11T18:00:00Z")
    (data / "sno2026-II" / "Записи" / ".current" /
     "sno2026_II_1234567_abcdef_20261011-1800").mkdir(parents=True)

    code, out = run(root, data, github)

    assert code == 1, out
    assert "В ветви II есть незавершённая сессия записи" in out
    assert github.downloads() == []
    assert exe(root, "II") == "memoria II sno2026-1"


@needs_pwsh
def test_sno_f_cfg_07_wrong_folder_says_where(tmp_path, github):
    code, out = run(tmp_path, tmp_path, github)
    assert code == 1, out
    assert "Положите этот файл в папку _MemoriaTest" in out
    assert github.requests == []


def test_sno_f_cfg_07_cmd_is_built_from_script():
    # Ярлык — один файл: строки cmd в ASCII, без метки порядка байтов,
    # CRLF; за меткой — сценарий PowerShell целиком.
    proc = subprocess.run([sys.executable, str(TOOL / "build_cmd.py"),
                           "--check"], capture_output=True, text=True,
                          encoding="utf-8")
    assert proc.returncode == 0, proc.stdout + proc.stderr
    cmd = (TOOL / "Обновить сборку исследования.cmd").read_bytes()
    assert not cmd.startswith(b"\xef\xbb\xbf")
    assert b"\n" not in cmd.replace(b"\r\n", b"")
    head, _, tail = cmd.decode("utf-8").partition("#<PS>")
    assert head.isascii() and "exit /b" in head
    assert "MEMORIA_SELF=%~f0" in head
    assert tail.replace("\r\n", "\n") == SCRIPT.read_text(
        encoding="utf-8").replace("#<PS>", "", 1)
