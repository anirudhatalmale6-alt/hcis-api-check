@echo off
REM HCIS - make the API start by itself after a reboot.
REM Backs the existing task up first, and restarts the API itself if anything fails.
cd /d "%~dp0"
echo.
echo  Repairing the automatic start for the HCIS API.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-api.ps1"
