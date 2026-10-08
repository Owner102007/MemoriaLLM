@echo off
rem Memoria SNO2026: camera check for 40 minutes (gate G1: memory growth).
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye bench --minutes 40 %*
echo.
pause
