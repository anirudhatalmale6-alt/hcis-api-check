@echo off
REM ============================================================
REM  HCIS - are the stored passwords still intact?
REM
REM  Read-only. It never prints a password or a hash. It reports
REM  only the LENGTH of each stored hash and whether it still has
REM  the shape of a proper bcrypt hash.
REM
REM  Why: the catch-up adds password_hash with "ADD COLUMN IF NOT
REM  EXISTS ... DEFAULT ''". If that column already existed - which
REM  it should have - nothing happened and everyone's password is
REM  untouched. But if it had been missing, every row would now
REM  hold an empty hash, and hcis_login refuses an empty hash
REM  outright. That would look exactly like "details not
REM  recognised". This tells us which world we are in.
REM ============================================================
setlocal
cd /d "%~dp0"

if not exist "%~dp0STEP-1-database.bat" (
  echo  ERROR: put this next to STEP-1-database.bat inside HCIS_gov_aug28.
  pause
  exit /b 1
)

for /f "tokens=2 delims==" %%A in ('findstr /b /c:"set PGBIN=" "%~dp0STEP-1-database.bat"') do set PGBIN=%%A
for /f "tokens=2 delims==" %%A in ('findstr /b /c:"set PGPASSWORD=" "%~dp0STEP-1-database.bat"') do set PGPASSWORD=%%A
set PSQL=%PGBIN%\psql.exe

echo.
echo  Checking whether stored passwords survived. Nothing is changed,
echo  and no password or hash is shown - only lengths and shapes.
echo.

echo  --- how many accounts have a USABLE password ---
"%PSQL%" -U postgres -d hcis_db -P pager=off -c "select case when password_hash is null or password_hash = '' then 'EMPTY - cannot sign in' when password_hash like '$2%%' then 'OK - proper bcrypt hash' else 'ODD - not a bcrypt hash' end as password_state, count(*) from system_users group by 1 order by 2 desc;"

echo.
echo  --- the account you are trying, specifically ---
"%PSQL%" -U postgres -d hcis_db -P pager=off -c "select username, role, status, length(password_hash) as hash_length, (password_hash like '$2%%') as looks_like_bcrypt, must_change_password, last_login from system_users where username = 'mgt';"

echo.
echo  --- when were these accounts last touched ---
"%PSQL%" -U postgres -d hcis_db -P pager=off -c "select username, role, status, updated_at from system_users order by updated_at desc nulls last limit 8;"

echo.
echo  ============================================================
echo   Photograph this and send it over.
echo   If the first table says EMPTY for everyone, tell me at once -
echo   there is a backup from this morning and I can put it right.
echo  ============================================================
echo.
pause
