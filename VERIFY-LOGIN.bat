@echo off
REM HCIS - find out exactly where sign-in is failing. Read-only.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify-login.ps1"
