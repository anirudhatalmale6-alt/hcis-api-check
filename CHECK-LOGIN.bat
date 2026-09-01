@echo off
REM ============================================================
REM  HCIS - why won't this account sign in?
REM
REM  Read-only. It looks at the account's state - whether it
REM  exists, whether it is active, whether it is locked out, how
REM  many failed attempts it has. It does NOT show or change any
REM  password, and it writes nothing.
REM
REM  It takes the database settings from STEP-1-database.bat
REM  sitting next to it, so no password is written in this file.
REM ============================================================
setlocal EnableDelayedExpansion
cd /d "%~dp0"

if not exist "%~dp0STEP-1-database.bat" (
  echo.
  echo  ERROR: STEP-1-database.bat is not in this folder.
  echo  Put this file next to it, inside HCIS_gov_aug28, and run again.
  echo.
  pause
  exit /b 1
)

for /f "tokens=2 delims==" %%A in ('findstr /b /c:"set PGBIN=" "%~dp0STEP-1-database.bat"') do set PGBIN=%%A
for /f "tokens=2 delims==" %%A in ('findstr /b /c:"set PGPASSWORD=" "%~dp0STEP-1-database.bat"') do set PGPASSWORD=%%A
set PSQL=%PGBIN%\psql.exe
set DB=hcis_db
set DBUSER=postgres

if not exist "%PSQL%" (
  echo  ERROR: psql not found at %PSQL%
  pause
  exit /b 1
)

echo.
set /p WHO=Type the username you are trying to sign in with, then press Enter:
echo.
echo  Looking up "%WHO%" - reading only, nothing will be changed.
echo.

REM -P pager=off so this can never stop at "-- More --" like step 1 did.
"%PSQL%" -U %DBUSER% -d %DB% -P pager=off -c "select username, role, status, must_change_password as must_change, failed_attempts as fails, locked_until, (locked_until is not null and locked_until > now()) as locked_right_now, last_login from system_users where lower(username) = lower('%WHO%') or lower(email) = lower('%WHO%');"

echo.
echo  --- is that name spelt as the database has it? nearest matches ---
"%PSQL%" -U %DBUSER% -d %DB% -P pager=off -c "select username, role, status from system_users where username ilike '%%%WHO%%%' or email ilike '%%%WHO%%%' limit 10;"

echo.
echo  --- how many accounts are active on this box ---
"%PSQL%" -U %DBUSER% -d %DB% -P pager=off -c "select status, count(*) from system_users group by status order by 2 desc;"

echo.
echo  --- are the sign-in functions present ---
"%PSQL%" -U %DBUSER% -d %DB% -P pager=off -c "select proname from pg_proc where proname in ('hcis_login','hcis_login_seyid','hcis_session_user') order by 1;"

echo.
echo  ============================================================
echo   Photograph this window and send it over.
echo   Nothing was changed and no password was displayed.
echo  ============================================================
echo.
pause
