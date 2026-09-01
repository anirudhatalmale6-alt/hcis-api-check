@echo off
REM HCIS - find out why the API will not start. Changes nothing.
cd /d "%~dp0"
echo.
echo  Looking at the API. This changes nothing on the machine.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose-api.ps1"
