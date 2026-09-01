<#
  HCIS - make the API come back by itself after a reboot.

  What we know:
    - postgrest.exe, postgrest.conf and start-postgrest.bat are all fine.
      Started by hand it connects to PostgreSQL first time.
    - The scheduled task fires and returns -1073741502 (0xC0000142),
      "the application failed to initialise". It has almost certainly never
      worked; somebody started it by hand instead, and the Windows Update
      reboot removed the person.
    - The task runs a BATCH FILE as SYSTEM with no working folder. A console
      program launched that way, in the background session, commonly dies with
      exactly that code.

  The fix: stop asking Task Scheduler to run a batch file through a console.
  Point it straight at postgrest.exe, give it its folder, and start it at boot.

  SAFETY:
    - The existing task definition is exported to a file first, so it can be
      put back exactly as it was.
    - Testing has to stop the copy running now. If the new task fails, this
      script starts PostgREST again itself before it exits, so the site is
      never left down because of me.
#>
$ErrorActionPreference = 'Continue'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Clean([string]$t) {
    if ($null -eq $t) { return '' }
    $t = [regex]::Replace($t, '(?i)(://[^:/@\s]+:)[^@\s]+(@)', '$1********$2')
    $t = [regex]::Replace($t, '(?im)^(\s*db-uri\s*=\s*").*(")', '$1<masked>$2')
    $t = [regex]::Replace($t, '(?i)((?:password|secret|api-?key)\s*[:=]\s*)\S+', '$1********')
    $t = [regex]::Replace($t, 'eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]+', '<token-masked>')
    return $t
}

$TASK = 'PostgREST-HCIS'
$EXE  = 'C:\HCIS\postgrest\postgrest.exe'
$DIR  = 'C:\HCIS\postgrest'
$CONF = 'postgrest.conf'

Say ''
Say '============================================================'
Say ' HCIS - make the API start by itself'
Say '============================================================'

if (-not (Test-Path -LiteralPath $EXE)) {
    Say "postgrest.exe is not at $EXE - stopping, nothing changed." 'Red'
    Read-Host 'Press Enter to close' | Out-Null; exit 1
}

function Get-PortPid {
    $l = netstat -ano | Select-String ':3000\s' | Select-String 'LISTENING' | Select-Object -First 1
    if (-not $l) { return $null }
    return ($l.ToString().Trim() -split '\s+')[-1]
}

# ---------- 1. back the old task up ----------
Say ''
Say '--- 1. saving the current task so it can be put back ---' 'Cyan'
$backup = "C:\HCIS\PostgREST-HCIS-task-backup.xml"
$old = schtasks /Query /TN $TASK /XML 2>&1 | Out-String
if ($old -notmatch 'ERROR') {
    $old | Set-Content -LiteralPath $backup -Encoding UTF8
    Say "saved to $backup" 'Green'
} else { Say 'there was no existing task to save' 'Yellow' }

# ---------- 2. rebuild it ----------
Say ''
Say '--- 2. rebuilding the task ---' 'Cyan'
Say 'It will run postgrest.exe directly (not the .bat), with its folder set,'
Say 'as SYSTEM, at every startup, with no time limit.'

try {
    Unregister-ScheduledTask -TaskName $TASK -Confirm:$false -ErrorAction SilentlyContinue

    $action  = New-ScheduledTaskAction -Execute $EXE -Argument $CONF -WorkingDirectory $DIR
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $princ   = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    # ExecutionTimeLimit 0 = never time out. The default kills long-running
    # tasks after three days, which for an API is a bomb on a timer.
    $set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                   -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 `
                   -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable

    Register-ScheduledTask -TaskName $TASK -Action $action -Trigger $trigger `
        -Principal $princ -Settings $set -Force | Out-Null
    Say 'task rebuilt.' 'Green'
} catch {
    Say ('could not rebuild the task: ' + $_.Exception.Message) 'Red'
}

# ---------- 3. test it for real ----------
Say ''
Say '--- 3. testing it ---' 'Cyan'
$before = Get-PortPid
if ($before) {
    Say "stopping the copy running now (process $before)..."
    taskkill /F /IM postgrest.exe 2>&1 | Out-Null
    Start-Sleep -Seconds 3
}

Say 'starting it through the task...'
schtasks /Run /TN $TASK 2>&1 | Out-String | ForEach-Object { Say $_.Trim() }

$after = $null
foreach ($i in 1..12) {
    Start-Sleep -Seconds 2
    $after = Get-PortPid
    if ($after) { break }
}

$viaTask = $false
if ($after) {
    $viaTask = $true
    Say ''
    Say "THE TASK STARTED IT. PostgREST is process $after on port 3000." 'Green'
} else {
    Say ''
    Say 'The task still could not start it.' 'Red'
    $res = (schtasks /Query /TN $TASK /V /FO LIST 2>&1 | Out-String)
    ($res -split "`r?`n") | Where-Object { $_ -match '^(Last Result|Last Run Time)' } |
        ForEach-Object { Say ('   ' + $_.Trim()) 'Red' }
    Say ''
    Say 'Starting it directly so your site is not left down...' 'Yellow'
    Start-Process -FilePath $EXE -ArgumentList $CONF -WorkingDirectory $DIR -WindowStyle Hidden
    Start-Sleep -Seconds 6
    $after = Get-PortPid
    if ($after) { Say "running again as process $after - but it will NOT survive a reboot yet." 'Yellow' }
    else { Say 'could not start it at all. Tell me - do not reboot.' 'Red' }
}

# ---------- 4. does the API see the new columns ----------
Say ''
Say '--- 4. can the API see the new columns from step 1 ---' 'Cyan'
$key = ''
$cfg = 'C:\HCIS\wwwroot\config.js'
if (Test-Path -LiteralPath $cfg) {
    $m = [regex]::Match((Get-Content -Raw -LiteralPath $cfg), "supabaseKey:\s*'([^']+)'")
    if ($m.Success) { $key = $m.Groups[1].Value }
}
$h = @{}
if ($key) { $h['apikey'] = $key; $h['Authorization'] = "Bearer $key" }

if ($after) {
    try {
        $r = Invoke-WebRequest -Uri 'http://localhost:3000/payroll_records?select=placements,institution_allowance&limit=1' `
                               -Headers $h -UseBasicParsing -TimeoutSec 20
        if ($r.StatusCode -eq 200) {
            Say 'YES - the new columns are there. Step 1 committed properly.' 'Green'
            Say 'You are clear to run STEP-3-deploy-frontend.bat.' 'Green'
        }
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $sr = New-Object IO.StreamReader($resp.GetResponseStream())
            Say 'The API refused that request:' 'Red'
            Say (Clean $sr.ReadToEnd()) 'Red'
            Say 'Do NOT run step 3. Send me this photo.' 'Red'
        } else { Say (Clean ('Could not reach the API: ' + $_.Exception.Message)) 'Red' }
    }
} else { Say 'skipped - the API is not running' 'Yellow' }

Say ''
Say '============================================================'
if ($viaTask) {
    Say ' DONE. It will now start by itself when the machine boots.' 'Green'
    Say ' You can close every black window - it no longer depends on one.' 'Green'
} else {
    Say ' The API is running, but the automatic start still needs work.' 'Yellow'
    Say ' Send me this photo before you reboot that machine.' 'Yellow'
}
Say " The old task was saved to $backup"
Say '============================================================'
Say ''
Read-Host 'Press Enter to close' | Out-Null
