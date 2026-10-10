@echo off
rem Memoria SNO2026: branch comparison (SNO-F-RES-06, steps 36-37).
rem Drop a folder with recording archives sno2026_*.zip on this file
rem (subfolders by PC are fine). Without arguments it compares the
rem recordings of the branch builds on this PC.
rem Result: Documents\Sravnenie vetvey SNO2026\DATE-TIME\index.html,
rem tables CSV and figures PNG and SVG; the report folder opens
rem in Explorer when it is ready.
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye study --open %*
echo.
pause
