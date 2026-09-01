<#
  HCIS - the password was set, so why is sign-in still refused?

  This tests the SAME path the browser uses, one layer at a time, so we can
  see exactly where it breaks instead of guessing:

    A. which database does PostgREST actually talk to?   <- I masked the whole
       db-uri last time, which hid the database name from me as well as the
       password. If psql and PostgREST are pointed at different databases,
       I set the password in one and the site reads the other.
    B. does the stored hash match the password you type? (asked of the database
       directly, with crypt - no guessing)
    C. does hcis_login through the API accept it? (exactly what the site does)

  Read-only. Nothing is changed. The password you type is never shown, never
  put on a command line, never written to a file. Only the PASSWORD portion of
  db-uri is masked this time - the host, port and database name are printed,
  because those are the things we need to see.
#>
$ErrorActionPreference = 'Continue'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$step1 = Join-Path $here 'STEP-1-database.bat'
if (-not (Test-Path -LiteralPath $step1)) {
    Say 'ERROR: put this next to STEP-1-database.bat inside HCIS_gov_aug28.' 'Red'
    Read-Host 'Press Enter to close' | Out-Null; exit 1
}
$txt  = Get-Content -Raw -LiteralPath $step1
$bin  = ([regex]::Match($txt,'(?im)^\s*set\s+PGBIN=(.+)$')).Groups[1].Value.Trim()
$env:PGPASSWORD = ([regex]::Match($txt,'(?im)^\s*set\s+PGPASSWORD=(.+)$')).Groups[1].Value.Trim()
$psql = Join-Path $bin 'psql.exe'

Say ''
Say '============================================================'
Say ' HCIS - where exactly is sign-in failing?'
Say '============================================================'

# ---------- A. which database is which ----------
Say ''
Say '--- A. which database does each side use ---' 'Cyan'
$conf = 'C:\HCIS\postgrest\postgrest.conf'
if (Test-Path -LiteralPath $conf) {
    $line = (Get-Content -LiteralPath $conf | Where-Object { $_ -match 'db-uri' } | Select-Object -First 1)
    # Mask ONLY the password between ':' and '@'. Keep host/port/database.
    $shown = [regex]::Replace($line, '(://[^:/@\s]+:)[^@\s]+(@)', '$1********$2')
    Say ('PostgREST is configured with: ' + $shown) 'Yellow'
} else { Say 'postgrest.conf not found' 'Red' }
Say 'My scripts have been using:  database hcis_db, user postgres, on this machine'
Say ''
Say 'databases that exist on this server:'
'select datname from pg_database where datistemplate = false order by 1;' |
    & $psql -U postgres -d postgres -At -f - 2>&1 | ForEach-Object { Say ('   ' + $_) }

# ---------- ask for the credentials ----------
Say ''
$who = Read-Host 'Username you are trying'
$sec = Read-Host 'The password you set (not shown)' -AsSecureString
$b   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try {
    $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)
    $whoSql = $who -replace "'","''"
    $pwSql  = $pw  -replace "'","''"

    # ---------- B. does the hash match, in the database ----------
    Say ''
    Say '--- B. does the stored password match what you typed ---' 'Cyan'
    $q = @"
select username,
       (password_hash = crypt('$pwSql', password_hash)) as password_matches,
       status, must_change_password, failed_attempts,
       (locked_until is not null and locked_until > now()) as locked_now
  from system_users where username = '$whoSql';
"@
    $q | & $psql -U postgres -d hcis_db -P pager=off -f - 2>&1 | ForEach-Object { Say ('   ' + $_) }

    # ---------- C. does the API accept it ----------
    Say ''
    Say '--- C. does the API accept it (what the website does) ---' 'Cyan'
    $key = ''
    $cfg = 'C:\HCIS\wwwroot\config.js'
    if (Test-Path -LiteralPath $cfg) {
        $m = [regex]::Match((Get-Content -Raw -LiteralPath $cfg), "supabaseKey:\s*'([^']+)'")
        if ($m.Success) { $key = $m.Groups[1].Value }
    }
    $h = @{ 'Content-Type' = 'application/json' }
    if ($key) { $h['apikey'] = $key; $h['Authorization'] = "Bearer $key" }
    $body = @{ p_identifier = $who; p_password = $pw } | ConvertTo-Json -Compress
    try {
        $r = Invoke-WebRequest -Uri 'http://localhost:3000/rpc/hcis_login' -Method POST `
                               -Headers $h -Body $body -UseBasicParsing -TimeoutSec 20
        $out = $r.Content
        # never print a session token
        $out = [regex]::Replace($out, '"token"\s*:\s*"[^"]*"', '"token":"<hidden>"')
        if ($out -match '\[\s*\]') {
            Say '   The API returned an EMPTY result - it refused the sign-in.' 'Red'
        } else {
            Say '   The API ACCEPTED it. Sign-in works at the API level.' 'Green'
            Say ('   ' + $out.Substring(0, [Math]::Min(300, $out.Length)))
        }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $sr = New-Object IO.StreamReader($resp.GetResponseStream())
            Say ('   API said: ' + $sr.ReadToEnd()) 'Red'
        } else { Say ('   Could not reach the API: ' + $_.Exception.Message) 'Red' }
    }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
    Remove-Variable pw, pwSql -ErrorAction SilentlyContinue
    $env:PGPASSWORD = ''
}

Say ''
Say '============================================================'
Say ' Photograph this and send it over.'
Say ' If B says password_matches = t but C refuses, the problem is'
Say ' between the site and the API, not your password.'
Say '============================================================'
Say ''
Read-Host 'Press Enter to close' | Out-Null
