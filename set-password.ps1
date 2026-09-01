<#
  HCIS - set the password for an existing account on THIS box.

  This one WRITES. Everything else I have sent you today was read-only;
  this changes one row in system_users, for one named account.

  What it does not do: it does not create accounts, does not touch anyone
  else's row, does not change roles or permissions.

  The password you type is not shown on screen, and it is never passed on
  the command line - it goes to psql through the input pipe, so it does not
  appear in Task Manager or in any log, and it is never written to a file.
  What gets stored is a bcrypt hash, not the password.
#>
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$step1 = Join-Path $here 'STEP-1-database.bat'
if (-not (Test-Path -LiteralPath $step1)) {
    Say 'ERROR: put this next to STEP-1-database.bat inside HCIS_gov_aug28.' 'Red'
    Read-Host 'Press Enter to close' | Out-Null; exit 1
}

$txt  = Get-Content -Raw -LiteralPath $step1
$bin  = ([regex]::Match($txt, '(?im)^\s*set\s+PGBIN=(.+)$')).Groups[1].Value.Trim()
$pw   = ([regex]::Match($txt, '(?im)^\s*set\s+PGPASSWORD=(.+)$')).Groups[1].Value.Trim()
$psql = Join-Path $bin 'psql.exe'
if (-not (Test-Path -LiteralPath $psql)) { Say "ERROR: psql not found at $psql" 'Red'; Read-Host | Out-Null; exit 1 }
$env:PGPASSWORD = $pw

Say ''
Say '============================================================'
Say ' HCIS - set a password for an existing account'
Say '============================================================'
Say ''

$who = Read-Host 'Which username'
if (-not $who) { Say 'nothing typed - stopping.' 'Yellow'; Read-Host | Out-Null; exit 1 }

# Confirm the account exists BEFORE asking for a password, so a typo in the
# username cannot end with "done" against a row that was never there.
$check = "select username || ' | ' || role || ' | ' || status from system_users where username = '$($who -replace "'","''")';"
$found = $check | & $psql -U postgres -d hcis_db -At -f - 2>&1 | Where-Object { $_ -and $_ -notmatch '^\s*$' }
if (-not $found) {
    Say ''
    Say "There is no account called '$who' on this box. Nothing changed." 'Red'
    Say 'Run CHECK-LOGIN.bat if you want to see the nearest matches.'
    Read-Host 'Press Enter to close' | Out-Null; exit 1
}
Say ''
Say ('Found: ' + $found) 'Green'
Say ''

$p1 = Read-Host 'New password (not shown)' -AsSecureString
$p2 = Read-Host 'Type it again'          -AsSecureString
$b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1)
$b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2)
try {
    $s1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
    $s2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)

    if ($s1 -ne $s2)     { Say ''; Say 'They do not match. Nothing changed.' 'Red'; Read-Host | Out-Null; exit 1 }
    if ($s1.Length -lt 8){ Say ''; Say 'Too short - at least 8 characters. Nothing changed.' 'Red'; Read-Host | Out-Null; exit 1 }
    if ($s1 -match "'")  { Say ''; Say "Please avoid the ' character. Nothing changed." 'Red'; Read-Host | Out-Null; exit 1 }

    # Piped to psql on stdin, so the password never appears in the command line.
    # failed_attempts and locked_until are cleared too, otherwise today's four
    # failures would still be sitting against the account.
    $sql = @"
UPDATE system_users
   SET password_hash = crypt('$s1', gen_salt('bf', 10)),
       must_change_password = FALSE,
       failed_attempts = 0,
       locked_until = NULL,
       updated_at = now()
 WHERE username = '$($who -replace "'","''")';
"@
    Say ''
    Say 'Setting it...'
    $res = $sql | & $psql -U postgres -d hcis_db -v ON_ERROR_STOP=1 -f - 2>&1 | Out-String
    Say $res.Trim()

    if ($res -match 'UPDATE 1') {
        # "UPDATE 1" only proves a row changed. It does NOT prove the new
        # password works - last time I reported success on that alone and the
        # sign-in still failed. So prove it, both ways, before saying done.
        Say ''
        Say 'Checking it actually works...' 'Cyan'

        $vq = "select (password_hash = crypt('$s1', password_hash)) as stored_ok from system_users where username = '$($who -replace "'","''")';"
        $vr = ($vq | & $psql -U postgres -d hcis_db -At -f - 2>&1 | Out-String).Trim()
        if ($vr -match '^t') { Say '   the database accepts this password.' 'Green' }
        else { Say '   the database does NOT accept it - something mangled it.' 'Red' }

        $key = ''
        $cfgp = 'C:\HCIS\wwwroot\config.js'
        if (Test-Path -LiteralPath $cfgp) {
            $mm = [regex]::Match((Get-Content -Raw -LiteralPath $cfgp), "supabaseKey:\s*'([^']+)'")
            if ($mm.Success) { $key = $mm.Groups[1].Value }
        }
        $hh = @{ 'Content-Type' = 'application/json' }
        if ($key) { $hh['apikey'] = $key; $hh['Authorization'] = "Bearer $key" }
        $apiOk = $false
        try {
            $rr = Invoke-WebRequest -Uri 'http://localhost:3000/rpc/hcis_login' -Method POST -Headers $hh `
                     -Body (@{ p_identifier = $who; p_password = $s1 } | ConvertTo-Json -Compress) `
                     -UseBasicParsing -TimeoutSec 20
            if ($rr.Content -notmatch '\[\s*\]') { $apiOk = $true }
        } catch { }
        if ($apiOk) { Say '   the website API accepts this sign-in.' 'Green' }
        else { Say '   the API still refuses it - tell me, this is not your typing.' 'Red' }

        Say ''
        if ($vr -match '^t' -and $apiOk) {
            Say "Done, and PROVEN. $who can sign in with this password now." 'Green'
        } else {
            Say 'The password was stored but did not pass both checks above.' 'Yellow'
            Say 'Send me a photo of this window rather than trying to sign in.' 'Yellow'
        }
    } else {
        Say ''
        Say 'That did not report UPDATE 1 - tell me what it says above.' 'Red'
    }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
    Remove-Variable s1, s2 -ErrorAction SilentlyContinue
    $env:PGPASSWORD = ''
}

Say ''
Read-Host 'Press Enter to close' | Out-Null
