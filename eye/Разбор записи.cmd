@echo off
rem Memoria SNO2026: gaze report (SNO-F-RES-03, step 34).
rem Drop a recording archive sno2026_*.zip or a folder with archives on this file.
rem Without arguments it reports the recordings of the branch builds on this PC.
rem Result: a folder ARCHIVE_eye next to the archive: index.html, tables, quality.
rem Archives from the app records folder go to Documents (folder Razbor zapisey SNO2026).
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python.exe" -I -m sno_eye report %*
echo.
pause
