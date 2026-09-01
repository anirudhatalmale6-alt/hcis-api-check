@echo off
REM HCIS - clear the lockout on mgt and prove the sign-in. Writes 2 fields only.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0unlock-account.ps1"
