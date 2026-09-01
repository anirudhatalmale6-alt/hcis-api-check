@echo off
REM HCIS - set the password for an existing account. THIS ONE WRITES.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set-password.ps1"
