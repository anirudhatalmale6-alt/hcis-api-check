<#
  HCIS - clear a lockout and prove the sign-in works afterwards.

  Why this exists: hcis_login checks locked_until BEFORE it checks the
  password, and returns an empty result either way. So a locked account and a
  wrong password look identical from the outside - a clean HTTP 200 with [] in
  it, which is exactly what the browser is getting.

  Evans has made a great many attempts this afternoon, most of them because I
  asked him to. Eight failures locks the account for fifteen minutes.

  This WRITES, but only two fields, for one named account: failed_attempts and
  locked_until. It does NOT touch the password, the role, the status, or
  anybody else's row.

  Then it proves the result through the SAME url the browser uses, not the
  shortcut to port 3000 - because testing the wrong path is a mistake I have
  already made once today.
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

$who = 'mgt'

Say ''
Say '============================================================'
Say " HCIS - unlock $who and prove the sign-in"
Say '============================================================'

Say ''
Say '--- BEFORE ---' 'Cyan'
"select username, failed_attempts, locked_until, (locked_until is not null and locked_until > now()) as locked_now, last_login from system_users where username = '$who';" |
    & $psql -U postgres -d hcis_db -P pager=off -f - 2>&1 | ForEach-Object { Say ('   ' + $_) }

Say ''
Say '--- clearing the lock (nothing else is touched) ---' 'Cyan'
"update system_users set failed_attempts = 0, locked_until = NULL where username = '$who';" |
    & $psql -U postgres -d hcis_db -v ON_ERROR_STOP=1 -f - 2>&1 | ForEach-Object { Say ('   ' + $_) }

Say ''
Say '--- AFTER ---' 'Cyan'
"select username, failed_attempts, locked_until, (locked_until is not null and locked_until > now()) as locked_now from system_users where username = '$who';" |
    & $psql -U postgres -d hcis_db -P pager=off -f - 2>&1 | ForEach-Object { Say ('   ' + $_) }

# ---- now prove it, through the browser's own URL ----
Say ''
Say '--- proving the sign-in, through the same address the browser uses ---' 'Cyan'
$sec = Read-Host 'Type the password you are signing in with (not shown)' -AsSecureString
$b   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try {
    $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)

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
        $r = Invoke-WebRequest -Uri 'http://localhost/rest/v1/rpc/hcis_login' -Method POST `
                               -Headers $h -Body $body -UseBasicParsing -TimeoutSec 20
        if ($r.Content -match '\[\s*\]') {
            Say ''
            Say '   STILL REFUSED, and it is NOT a lockout - the lock is now clear.' 'Red'
            Say '   So the password being sent is genuinely not the stored one.' 'Red'
            Say '   Send me this window and I will set it again with you watching.' 'Red'
        } else {
            Say ''
            Say '   ACCEPTED. A real sign-in came back.' 'Green'
            Say '   It was the lockout. Go to the browser and sign in now -' 'Green'
            Say '   and this time it will work.' 'Green'
        }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $sr = New-Object IO.StreamReader($resp.GetResponseStream())
            Say ('   HTTP ' + [int]$resp.StatusCode + ' - ' + $sr.ReadToEnd()) 'Red'
        } else { Say ('   could not reach it: ' + $_.Exception.Message) 'Red' }
    }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
    Remove-Variable pw -ErrorAction SilentlyContinue
    $env:PGPASSWORD = ''
}

Say ''
Say '  Photograph this whole window.'
Say ''
Read-Host 'Press Enter to close' | Out-Null
