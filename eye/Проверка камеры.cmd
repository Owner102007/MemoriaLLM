@echo off
rem Memoria SNO2026: camera check (SNO-F-EYE-04, gate G1).
rem Self-check of the place, then 2 minutes of measuring. Result: bench.json.
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye bench %*
echo.
pause
