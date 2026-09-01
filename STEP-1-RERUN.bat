@echo off
REM ============================================================
REM  HCIS - run STEP 1 again, properly this time.
REM
REM  Last time the screen stopped at "-- More --" and waited for
REM  a keypress it never got. psql pages its output when it is
REM  printing to a screen, and the run never reached the end, so
REM  the transaction was never committed. Nothing was written.
REM
REM  This sends everything to a file instead of the screen. psql
REM  does not page into a file, so there is nothing to press and
REM  nothing to get stuck on - and we end up with a full log
REM  instead of whatever fits in a window.
REM
REM  This file contains no password. It just calls the real
REM  STEP-1-database.bat, which must be sitting next to it.
REM ============================================================
cd /d "%~dp0"

if not exist "%~dp0STEP-1-database.bat" (
  echo.
  echo  ERROR: STEP-1-database.bat is not in this folder.
  echo.
  echo  Put this file INSIDE the HCIS_gov_aug28 folder, next to
  echo  STEP-1-database.bat, and run it again.
  echo.
  pause
  exit /b 1
)

if not exist C:\HCIS mkdir C:\HCIS
set LOG=C:\HCIS\step1.log

echo.
echo  Running STEP 1 again. Everything goes to:
echo    %LOG%
echo.
echo  This takes a few minutes. The window will look like it is
echo  doing nothing - that is expected, it is writing to the file.
echo  DO NOT CLOSE IT. It will tell you when it is done.
echo.

REM  "< nul" feeds an empty keypress to the pause at the end of the
REM  real script, so it cannot sit there waiting invisibly.
call "%~dp0STEP-1-database.bat" < nul > "%LOG%" 2>&1

echo.
echo  ============================================================
echo   Finished. Opening the log now.
echo.
echo   Scroll to the BOTTOM. If it worked you will see a table
echo   with six numbers - tables, columns, policies, chief_exec,
echo   pension_pct, rounding. Photograph that and send it to me.
echo.
echo   If instead it says IT STOPPED AND NOTHING WAS WRITTEN,
echo   photograph the error above that line and send me it.
echo  ============================================================
echo.
notepad "%LOG%"
pause
