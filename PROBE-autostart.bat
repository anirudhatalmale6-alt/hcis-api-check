@echo off
REM  HCIS - find out why the API does not start on its own.
REM  Right-click this file and choose "Run as administrator".
REM  It does NOT stop or restart the API that is running now.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probe-autostart.ps1"
