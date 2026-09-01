<#
  HCIS - find out WHY the API will not start.

  This changes nothing. It looks, it reports, and it tries to start PostgREST
  in the open so the error is visible.

  My reload script started it minimised, which hid the very message we need.
  Worse, it printed "Trying directly..." before checking whether the start file
  existed - so if that file is missing it printed that line and then did
  nothing at all. Either way the real error never reached the screen. That is
  what this puts right.

  Anything that looks like a password is masked before it is printed, so this
  window is safe to photograph.
#>
$ErrorActionPreference = 'Continue'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

# Mask user:password@host in anything we print. Applied to EVERY line.
function Clean([string]$t) {
    if ($null -eq $t) { return '' }
    $t = [regex]::Replace($t, '(?i)(://[^:/@\s]+:)[^@\s]+(@)', '$1********$2')
    $t = [regex]::Replace($t, '(?im)^(\s*db-uri\s*=\s*").*(")', '$1<masked>$2')
    $t = [regex]::Replace($t, '(?i)(password\s*[:=]\s*)\S+', '$1********')
    # jwt-secret signs every session token - it must never reach a screenshot.
    $t = [regex]::Replace($t, '(?im)^(\s*jwt-secret\s*=\s*).*$', '$1<masked>')
    $t = [regex]::Replace($t, '(?i)((?:secret|api-?key)\s*[:=]\s*)\S+', '$1********')
    # any JWT-shaped token, wherever it turns up
    $t = [regex]::Replace($t, 'eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]+', '<token-masked>')
    return $t
}
function SayClean($m, $c = 'Gray') { Write-Host (Clean $m) -ForegroundColor $c }

Say ''
Say '============================================================'
Say ' HCIS - why will the API not start?'
Say '============================================================'

# ---------- 1. is anything on port 3000 ----------
Say ''
Say '--- 1. port 3000 ---' 'Cyan'
$net = netstat -ano | Select-String ':3000\s'
if ($net) { $net | ForEach-Object { Say $_.ToString().Trim() } }
else { Say 'nothing is listening on port 3000' 'Yellow' }

# ---------- 2. where does postgrest live ----------
Say ''
Say '--- 2. the files ---' 'Cyan'
foreach ($p in @('C:\HCIS','C:\HCIS\postgrest','C:\HCIS\wwwroot')) {
    if (Test-Path -LiteralPath $p) { Say ("EXISTS  " + $p) } else { Say ("MISSING " + $p) 'Yellow' }
}
# Look where it should be FIRST. The previous version searched the whole of
# C: every time, which sat silently for minutes on a box where the answer was
# always going to be in C:\HCIS\postgrest. Only fall back to a wide search if
# the obvious places come up empty.
$exe = @()
foreach ($guess in @('C:\HCIS\postgrest\postgrest.exe','C:\HCIS\postgrest.exe','C:\postgrest\postgrest.exe')) {
    if (Test-Path -LiteralPath $guess) { $exe += Get-Item -LiteralPath $guess }
}
if (-not $exe) {
    Say 'not in the usual places - searching C:\HCIS...' 'Yellow'
    $exe = Get-ChildItem -Path 'C:\HCIS' -Filter 'postgrest.exe' -Recurse -ErrorAction SilentlyContinue -Force |
           Select-Object -First 3
}
if (-not $exe) {
    Say 'still not found - searching the whole drive, this takes a few minutes...' 'Yellow'
    $exe = Get-ChildItem -Path 'C:\' -Filter 'postgrest.exe' -Recurse -ErrorAction SilentlyContinue -Force |
           Select-Object -First 3
}
if ($exe) { $exe | ForEach-Object { Say ("postgrest.exe -> " + $_.FullName) 'Green' } }
else { Say 'postgrest.exe was NOT FOUND anywhere on C: - that would explain everything' 'Red' }

# PostgREST's config, specifically. The previous version took the first
# *.conf OR *.config it found and got C:\HCIS\deploy\...\wwwroot\web.config -
# an IIS file - then tried to start PostgREST with it. That produces a failure
# that has nothing to do with the real fault. web.config is never PostgREST's.
$conf = @()
foreach ($guess in @('C:\HCIS\postgrest\postgrest.conf','C:\HCIS\postgrest.conf')) {
    if (Test-Path -LiteralPath $guess) { $conf += Get-Item -LiteralPath $guess }
}
if (-not $conf) {
    $conf = Get-ChildItem -Path 'C:\HCIS' -Filter '*.conf' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'web.config' } | Select-Object -First 5
}
if ($conf) { $conf | ForEach-Object { Say ("config -> " + $_.FullName) 'Green' } }
else { Say 'no .conf file found under C:\HCIS' 'Yellow' }

$bat = 'C:\HCIS\postgrest\start-postgrest.bat'
if (Test-Path -LiteralPath $bat) { Say ("start file EXISTS  " + $bat) 'Green' }
else { Say ("start file MISSING " + $bat + "  <- my reload script expected this") 'Yellow' }

# ---------- 3. the scheduled task ----------
Say ''
Say '--- 3. the scheduled task ---' 'Cyan'
$t = schtasks /Query /TN "PostgREST-HCIS" /V /FO LIST 2>&1 | Out-String
if ($t -match 'ERROR') { Say 'there is no scheduled task called PostgREST-HCIS' 'Red' }
else {
    ($t -split "`r?`n") | Where-Object {
        $_ -match '^(Task To Run|Start In|Run As User|Status|Last Run Time|Last Result|Scheduled Task State|Task Name)'
    } | ForEach-Object { SayClean $_.Trim() }
}

# ---------- 4. the config, masked ----------
Say ''
Say '--- 4. the config (passwords masked) ---' 'Cyan'
if ($conf) {
    $c0 = $conf[0].FullName
    Say ("from " + $c0)
    Get-Content -LiteralPath $c0 -ErrorAction SilentlyContinue |
        Select-Object -First 25 | ForEach-Object { SayClean $_ }
} else { Say 'skipped - no config file found' 'Yellow' }

# ---------- 4b. what the start script actually does ----------
# The scheduled task runs this file and Windows reports 0xC0000142. Its
# contents are the missing piece - a relative path here behaves completely
# differently when Task Scheduler runs it as SYSTEM with no working folder.
Say ''
Say '--- 4b. start-postgrest.bat ---' 'Cyan'
if (Test-Path -LiteralPath $bat) {
    Get-Content -LiteralPath $bat -ErrorAction SilentlyContinue |
        Select-Object -First 30 | ForEach-Object { SayClean ('   ' + $_) }
} else { Say 'not present' 'Yellow' }

# ---------- 5. START IT IN THE OPEN AND CATCH THE ERROR ----------
Say ''
Say '--- 5. starting PostgREST in the open ---' 'Cyan'
if ($exe -and $conf) {
    $out = Join-Path $env:TEMP 'pgrst_out.txt'
    $err = Join-Path $env:TEMP 'pgrst_err.txt'
    Remove-Item $out,$err -ErrorAction SilentlyContinue
    Say ('running: ' + $exe[0].FullName + ' ' + $conf[0].FullName)
    Say 'giving it 12 seconds...'
    $p = Start-Process -FilePath $exe[0].FullName -ArgumentList "`"$($conf[0].FullName)`"" `
                       -RedirectStandardOutput $out -RedirectStandardError $err `
                       -PassThru -NoNewWindow
    Start-Sleep -Seconds 12

    Say ''
    Say 'WHAT IT SAID:' 'Yellow'
    foreach ($f in @($out,$err)) {
        if (Test-Path $f) {
            $lines = Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | Select-Object -First 25
            foreach ($l in $lines) { if ($l.Trim()) { SayClean ('   ' + $l) } }
        }
    }

    $live = netstat -ano | Select-String ':3000\s' | Select-String 'LISTENING'
    Say ''
    if ($live) {
        Say 'IT IS NOW RUNNING on port 3000.' 'Green'
        Say 'Leave this window OPEN - closing it will stop the API again.'
        Say 'Send me a photo, and I will tell you what to do next.' 'Green'
    } else {
        Say 'It still did not come up. The message above is the reason.' 'Red'
        if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
        Say 'Send me a photo of this whole window.' 'Red'
    }
} else {
    Say 'cannot try - postgrest.exe or its config was not found (see section 2)' 'Red'
    Say 'Send me a photo of this window.' 'Red'
}

Say ''
Say '============================================================'
Say ' Photograph this window and send it over. Nothing was changed.'
Say '============================================================'
Say ''
if ($Host.Name -eq 'ConsoleHost') { Read-Host 'Press Enter to close' | Out-Null }
