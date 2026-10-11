"""Собирает «Обновить сборку исследования.cmd» (SNO-F-CFG-07, шаг 35).

Ярлык — один файл, чтобы организатор мог переслать его на второй ПК
сообщением: сверху несколько строк cmd (только ASCII), за ними —
`update_study.ps1` целиком после строки `#<PS>`. cmd ставит в переменную
`MEMORIA_SELF` свой путь и отдаёт PowerShell текст после метки; сам до
метки не доходит (`exit /b`).

Файл — UTF-8 без метки порядка байтов (с ней cmd не узнаёт первую
строку) и с переводами строк CRLF (с одним LF cmd путается в метках).

    python3 tool/study_update/build_cmd.py          # собрать
    python3 tool/study_update/build_cmd.py --check  # совпадает ли собранный
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "update_study.ps1"
TARGET = HERE / "Обновить сборку исследования.cmd"
MARK = "#<PS>"

HEADER = r"""@echo off
rem Memoria SNO2026: update the study build in this folder (SNO-F-CFG-07).
rem Put this file into the _MemoriaTest folder, next to the folders I and
rem II, and run it. It takes the latest sno2026-N release from GitHub,
rem checks SHA256SUMS.txt, keeps the old I and II in _prezhnie and puts
rem the new ones in their place. Records and the shelf are not touched.
chcp 65001 >nul
title Memoria SNO2026 - study build update
set "MEMORIA_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:MEMORIA_SELF,[Text.Encoding]::UTF8);$i=$t.IndexOf('#'+'<PS>');& ([ScriptBlock]::Create($t.Substring($i)))"
echo.
pause
exit /b
"""


def build() -> bytes:
    script = SOURCE.read_text(encoding="utf-8")
    if not script.startswith(MARK):
        raise SystemExit(f"{SOURCE.name} должен начинаться строкой {MARK}")
    if MARK in HEADER:
        raise SystemExit("метка не должна встречаться в строках cmd")
    if not HEADER.isascii():
        raise SystemExit("строки cmd — только ASCII")
    text = HEADER + script
    text = text.replace("\r\n", "\n").replace("\n", "\r\n")
    return text.encode("utf-8")


def main(argv: list[str]) -> int:
    data = build()
    if "--check" in argv:
        if not TARGET.exists() or TARGET.read_bytes() != data:
            print(f"{TARGET.name} не совпадает с {SOURCE.name} — соберите заново")
            return 1
        print(f"{TARGET.name} совпадает с {SOURCE.name}")
        return 0
    TARGET.write_bytes(data)
    print(f"{TARGET} — {len(data)} байт")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
