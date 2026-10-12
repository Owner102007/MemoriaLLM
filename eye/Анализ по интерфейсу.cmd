@echo off
rem Memoria SNO2026: analysis by interface (SNO-F-RES-09, step 43).
rem Drop a folder with recording archives sno2026_*.zip on this file
rem (subfolders by PC are fine). Groups are the interface used to pick
rem books - the shelf or the Galaxy map - not the branch: the shelf is
rem checked against chance and against itself, first contact with the
rem Galaxy against the expectations written before the data.
rem Result: Documents\Analiz po interfeysu SNO2026\DATE-TIME\index.html,
rem tables CSV and figures PNG and SVG; the report folder opens
rem in Explorer when it is ready.
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye study --interface --open %*
echo.
pause
