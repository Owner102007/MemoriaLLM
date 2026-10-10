@echo off
rem Memoria SNO2026: branch comparison, check run (SNO-F-RES-06, steps 36-37).
rem The same as "Sravnenie vetvey.cmd", but every usable archive goes in
rem with weight 1: red, poor gaze, not from the reference state, short.
rem It shows that every part of the report works; not for conclusions.
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye study --no-filter --open %*
echo.
pause
