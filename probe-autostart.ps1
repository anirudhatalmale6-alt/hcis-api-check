<#
  HCIS - WHY does the API fail to start on its own?

  Windows reports -1073741502 (0xC0000142) when the scheduled task runs.
  That code means the program died while Windows was still loading it -
  before a single line of PostgREST's own code ran. So it is NOT a config
  problem, NOT a database problem, and NOT a password problem. Something
  the exe depends on cannot be found when the task runs it.

  I have guessed at this twice already and been wrong twice. So this script
  guesses nothing. It reproduces the failure under the exact same conditions
  Windows uses - running as SYSTEM, through the task scheduler - and captures
  what comes out.

  IT DOES NOT TOUCH THE RUNNING API.
  It never binds port 3000. It only asks postgrest.exe to print its version
  number, which loads every one of the same DLLs but exits immediately. If the
  loading is what's broken, that will fail in exactly the same way. If it
  prints a version, the loading is fine and I am looking in the wrong place.

  It runs that twice as SYSTEM:
     A - exactly as the task does now
     B - with the PostgreSQL program folder added to the search path
  If A fails and B works, we have both the cause and the cure in one go.

  A temporary task called HCIS-PROBE is created and DELETED again at the end.
  Nothing else is changed.
#>
$ErrorActionPreference = 'Continue'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Clean([string]$t) {
    if ($null -eq $t) { return '' }
    $t = [regex]::Replace($t, '(?i)(://[^:/@\s]+:)[^@\s]+(@)', '$1********$2')
    # PGPASSWORD= is not caught by a \bpassword rule - there is no word break
    # between PG and PASSWORD. A task command line or an event log entry can
    # carry it, so it gets its own rule.
    $t = [regex]::Replace($t, '(?i)(\bPG_?PASSWORD\s*=\s*)\S+', '$1********')
    $t = [regex]::Replace($t, '(?im)^(\s*jwt-secret\s*=\s*).*$', '$1<masked>')
    $t = [regex]::Replace($t, '(?i)((?:secret|api-?key)\s*[:=]\s*)\S+', '$1********')
    $t = [regex]::Replace($t, '(?i)(\bpassword\s*[:=]\s*).*?(?=(\s+[A-Za-z_]+\s*=)|"?\s*$)', '$1********')
    $t = [regex]::Replace($t, 'eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]+', '<token-masked>')
    return $t
}
function SayClean($m, $c = 'Gray') { Write-Host (Clean $m) -ForegroundColor $c }

Say ''
Say '============================================================'
Say ' HCIS - why will the API not start by itself?'
Say ' (the running API is NOT touched by this)'
Say '============================================================'

# ---------- 0. am I admin ----------
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Say ''
    Say ' This has to run as Administrator - right-click PROBE-autostart.bat' 'Red'
    Say ' and choose "Run as administrator". Nothing was done.' 'Red'
    Read-Host 'Press Enter to close' | Out-Null
    exit 1
}

# ---------- 1. is the API still up ----------
Say ''
Say '--- 1. the API right now (this must stay up) ---' 'Cyan'
$live = netstat -ano | Select-String ':3000\s' | Select-String 'LISTENING'
if ($live) {
    $live | ForEach-Object { Say ('   ' + $_.ToString().Trim()) 'Green' }
} else {
    Say '   nothing on port 3000 - the API is DOWN right now.' 'Yellow'
    Say '   That is fine for this test, but run FIX-api.bat afterwards.' 'Yellow'
}

# ---------- 2. find the exe ----------
Say ''
Say '--- 2. postgrest.exe ---' 'Cyan'
$exePath = 'C:\HCIS\postgrest\postgrest.exe'
if (-not (Test-Path -LiteralPath $exePath)) {
    $c = Get-ChildItem 'C:\HCIS' -Filter 'postgrest.exe' -Recurse -Force -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if ($c) { $exePath = $c.FullName }
}
if (-not (Test-Path -LiteralPath $exePath)) {
    Say '   postgrest.exe not found - stopping.' 'Red'
    Read-Host 'Press Enter to close' | Out-Null; exit 1
}
$exeDir = Split-Path -Parent $exePath
$ei = Get-Item -LiteralPath $exePath
Say ("   " + $exePath)
Say ("   " + [math]::Round($ei.Length/1MB,1) + " MB, dated " + $ei.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))

Say ''
Say '   DLLs sitting beside it:'
$dlls = Get-ChildItem -LiteralPath $exeDir -Filter '*.dll' -ErrorAction SilentlyContinue
if ($dlls) { $dlls | ForEach-Object { Say ('      ' + $_.Name) } }
else { Say '      NONE. So every DLL it needs must come from the search path.' 'Yellow' }

# ---------- 3. the two search paths ----------
# This is the whole question. A program started by a person inherits that
# person's PATH. A task running as SYSTEM does not - it gets the machine PATH
# only. If libpq.dll lives in a folder that is on one and not the other, the
# program runs for Evans and dies for the scheduler. Same exe, same config.
Say ''
Say '--- 3. the two search paths ---' 'Cyan'
$machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$userPath    = [Environment]::GetEnvironmentVariable('Path','User')
Say '   folders the MACHINE knows about (what SYSTEM tasks get):'
($machinePath -split ';') | Where-Object { $_ } | ForEach-Object { Say ('      ' + $_) }
Say ''
Say '   folders only YOUR account knows about (SYSTEM does NOT get these):'
$u = ($userPath -split ';') | Where-Object { $_ }
if ($u) { $u | ForEach-Object { Say ('      ' + $_) 'Yellow' } } else { Say '      (none)' }

# where does libpq actually live
Say ''
Say '   where libpq.dll can be found:'
$pgbin = @('C:\PostgreSQL\16\bin','C:\Program Files\PostgreSQL\16\bin',
           'C:\Program Files\PostgreSQL\17\bin') | Where-Object { Test-Path -LiteralPath $_ }
$libpqHomes = @()
foreach ($d in @($exeDir) + $pgbin) {
    if (Test-Path -LiteralPath (Join-Path $d 'libpq.dll')) {
        $libpqHomes += $d
        $onMachine = ($machinePath -split ';' | Where-Object { $_.TrimEnd('\') -ieq $d.TrimEnd('\') }).Count -gt 0
        if ($onMachine) { Say ("      $d   (ON the machine path)") 'Green' }
        else            { Say ("      $d   (NOT on the machine path)") 'Red' }
    }
}
if (-not $libpqHomes) { Say '      libpq.dll not found in any of the usual places' 'Yellow' }

# ---------- 4. the current task ----------
Say ''
Say '--- 4. the task as it stands ---' 'Cyan'
$t = schtasks /Query /TN "PostgREST-HCIS" /V /FO LIST 2>&1 | Out-String
if ($t -match 'ERROR') { Say '   no task called PostgREST-HCIS' 'Yellow' }
else {
    ($t -split "`r?`n") | Where-Object {
        $_ -match '^(Task To Run|Start In|Run As User|Status|Last Run Time|Last Result|Scheduled Task State)'
    } | ForEach-Object { SayClean ('   ' + $_.Trim()) }
}

# ---------- 5. REPRODUCE IT, AS SYSTEM ----------
Say ''
Say '--- 5. reproducing the failure as SYSTEM ---' 'Cyan'
Say '    (asking it only to print its version - it will not take port 3000)'

$probeDir = 'C:\HCIS\probe'
New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
$logA = Join-Path $probeDir 'A_as_the_task_runs_it.log'
$logB = Join-Path $probeDir 'B_with_postgres_folder_added.log'
$logP = Join-Path $probeDir 'C_system_path.log'
Remove-Item $logA,$logB,$logP -ErrorAction SilentlyContinue

$addDir = if ($libpqHomes) { ($libpqHomes | Where-Object { $_ -ne $exeDir } | Select-Object -First 1) } else { $null }
if (-not $addDir -and $pgbin) { $addDir = $pgbin[0] }

# Each run writes its own exit code into its own log, so an EMPTY log is
# itself the answer: it means the program never got far enough to write
# anything, which is what a loading failure looks like.
#
# Two details that matter, both of which I got wrong on the first pass:
#  - the whole cmd block is wrapped in brackets and redirected as ONE unit, so
#    the loader's own complaint is captured too, not just the program's output;
#  - /v:on and !errorlevel!, because %errorlevel% inside a one-line cmd is
#    substituted BEFORE anything runs and would always report 0.
$cmdA = "( `"$exePath`" --version & echo ---EXITCODE=!errorlevel!--- ) > `"$logA`" 2>&1"
$cmdB = if ($addDir) {
          "set `"PATH=$addDir;%PATH%`" & ( `"$exePath`" --version & echo ---EXITCODE=!errorlevel!--- ) > `"$logB`" 2>&1"
        } else { $null }
$cmdP = "set PATH > `"$logP`" 2>&1"

function Run-AsSystem($label, $cmdline) {
    $name = 'HCIS-PROBE'
    schtasks /Delete /TN $name /F 2>&1 | Out-Null
    $a = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/v:on /c ' + $cmdline) -WorkingDirectory $exeDir
    $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                                      -ExecutionTimeLimit ([TimeSpan]::FromMinutes(2))
    try {
        Register-ScheduledTask -TaskName $name -Action $a -Principal $p -Settings $s -Force | Out-Null
        Start-ScheduledTask -TaskName $name
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 700
            $ti = Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue
            if ($ti -and $ti.LastTaskResult -ne 267009) { break }   # 267009 = still running
        }
        $ti = Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue
        Say ''
        Say ("   $label")
        if ($ti) {
            $rc = $ti.LastTaskResult
            $hex = '0x{0:X8}' -f ([uint32]($rc -band 0xFFFFFFFF))
            Say ("      Windows returned: $rc  ($hex)")
        }
    } catch {
        Say ("      could not run the probe task: " + $_.Exception.Message) 'Red'
    } finally {
        schtasks /Delete /TN $name /F 2>&1 | Out-Null
    }
}

function Show-Log($path, $what) {
    if (Test-Path -LiteralPath $path) {
        $lines = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
        if ($lines -and ($lines | Where-Object { $_.Trim() }).Count -gt 0) {
            $lines | Select-Object -First 12 | ForEach-Object { if ($_.Trim()) { SayClean ('      | ' + $_) } }
        } else {
            Say '      | (the log is EMPTY - it produced no output at all)' 'Red'
        }
    } else {
        Say '      | (no log was written at all)' 'Red'
    }
}

Run-AsSystem 'A - run exactly the way the task runs it:' $cmdA
Show-Log $logA 'A'

if ($cmdB) {
    Run-AsSystem "B - same thing, but with $addDir added to the path:" $cmdB
    Show-Log $logB 'B'
} else {
    Say ''
    Say '   B - skipped, no PostgreSQL bin folder found to add' 'Yellow'
}

Run-AsSystem 'C - what path does SYSTEM actually get:' $cmdP
if (Test-Path -LiteralPath $logP) {
    $pl = (Get-Content -LiteralPath $logP | Where-Object { $_ -match '^Path=' } | Select-Object -First 1)
    if ($pl) {
        ($pl.Substring(5) -split ';') | Where-Object { $_ } | ForEach-Object { Say ('      ' + $_) }
    }
}

# ---------- 6. what Windows logged ----------
Say ''
Say '--- 6. what Windows logged about it ---' 'Cyan'
try {
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Level = 1,2; StartTime = (Get-Date).AddDays(-3) } `
          -ErrorAction SilentlyContinue |
          Where-Object { $_.Message -match 'postgrest' } | Select-Object -First 5
    if ($ev) { $ev | ForEach-Object { SayClean ('   ' + $_.TimeCreated.ToString('MM-dd HH:mm') + '  ' + ($_.Message -split "`n")[0]) } }
    else { Say '   nothing about postgrest in the application log' }
} catch { Say '   could not read the event log' 'Yellow' }

# ---------- 7. is the API still up ----------
Say ''
Say '--- 7. the API, again (should be unchanged) ---' 'Cyan'
$live2 = netstat -ano | Select-String ':3000\s' | Select-String 'LISTENING'
if ($live2) { Say '   still listening on 3000 - untouched, as intended.' 'Green' }
else { Say '   NOT listening. If it was up in section 1, tell me at once.' 'Red' }

Say ''
Say '============================================================'
Say ' Photograph this whole window - scroll up and take two if it'
Say ' does not all fit. Nothing was changed; the probe task has'
Say ' been deleted.'
Say '============================================================'
Say ''
Read-Host 'Press Enter to close' | Out-Null
