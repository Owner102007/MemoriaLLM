@echo off
rem Memoria SNO2026: analysis by interface, check run (SNO-F-RES-09,
rem step 43). The same as "Analiz po interfeysu.cmd", but every usable
rem archive goes in with weight 1: red, poor gaze, not from the
rem reference state, short. It shows that every part of the report
rem works; not for conclusions.
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye study --interface --no-filter --open %*
echo.
pause
