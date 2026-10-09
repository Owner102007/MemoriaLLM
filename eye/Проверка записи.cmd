@echo off
rem Memoria SNO2026: record check (SNO-F-RES-01, step 33).
rem Drop a recording archive sno2026_*.zip or a folder with archives on this file.
rem Without arguments it checks the recordings of the branch builds on this PC.
rem Result: a verdict for every archive and the table next to them.
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye check %*
echo.
pause
