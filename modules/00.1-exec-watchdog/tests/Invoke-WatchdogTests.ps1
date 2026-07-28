#requires -Version 7.0
# Regression tests for Module 00.1 (exec.watchdog). Run directly or via the executor.
# Pure decision logic is unit-tested; recovery is proven against DISPOSABLE executor instances on temp
# runtime roots (never the canonical live executor). All spawned processes are cleaned up in finally.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
$watch      = Join-Path $moduleRoot 'Watch-Executor.ps1'
$exeScript  = Join-Path $modulesDir '00-bootstrap-executor/Start-BootstrapExecutor.ps1'
$enc = [System.Text.UTF8Encoding]::new($false)
$tmp = [System.IO.Path]::GetTempPath()   # cross-platform (the Windows TEMP env var is not set on Linux)
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function WaitFor([scriptblock]$Cond, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) { try { if (& $Cond) { return $true } } catch { }; Start-Sleep -Milliseconds 400 }
    try { return [bool](& $Cond) } catch { return $false }
}
function Read-Json([string]$Path) {
    for ($i = 0; $i -lt 5; $i++) {
        try { if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } } catch { }
        Start-Sleep -Milliseconds 150
    }
    return $null
}
function Kill-Tree([int]$ProcId) {
    if ($ProcId -le 0) { return }
    if ($IsWindows) { try { & taskkill.exe /PID $ProcId /T /F 2>&1 | Out-Null } catch { } }
    else { try { & kill -9 $ProcId 2>$null } catch { } }
}
function Start-Bg([string[]]$ArgList) {
    # Background pwsh; -WindowStyle is Windows-only (unsupported on PowerShell for Linux).
    if ($IsWindows) { return Start-Process $PwshPath -PassThru -WindowStyle Hidden -ArgumentList $ArgList }
    else { return Start-Process $PwshPath -PassThru -ArgumentList $ArgList }
}

$exe1 = $null; $exe2 = $null; $wd = $null; $r1 = $null; $r2 = $null
$exe3 = $null; $wd3 = $null; $r3 = $null
try {
    # ---------------------------------------------------------------- pure decision
    $realPwsh = $PwshPath
    . $watch -DefineOnly
    $PwshPath = $realPwsh   # dot-sourcing the watchdog re-declared $PwshPath (its own param); restore ours
    Check 'decision healthy->none'       ((Get-WatchdogDecision -Alive $true  -HeartbeatAgeSeconds 3    -HeartbeatStaleSeconds 45 -LastExitReason $null           -RestartsInWindow 0 -MaxRestarts 5) -eq 'none')
    Check 'decision hung->kill_restart'  ((Get-WatchdogDecision -Alive $true  -HeartbeatAgeSeconds 90   -HeartbeatStaleSeconds 45 -LastExitReason $null           -RestartsInWindow 0 -MaxRestarts 5) -eq 'kill_restart')
    Check 'decision crash->restart'      ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds 50   -HeartbeatStaleSeconds 45 -LastExitReason 'fatal_error'    -RestartsInWindow 0 -MaxRestarts 5) -eq 'restart')
    Check 'decision hardkill->restart'   ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds $null -HeartbeatStaleSeconds 45 -LastExitReason $null          -RestartsInWindow 0 -MaxRestarts 5) -eq 'restart')
    Check 'decision stop_requested->stand_down' ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds 5 -HeartbeatStaleSeconds 45 -LastExitReason 'stop_requested' -RestartsInWindow 0 -MaxRestarts 5) -eq 'stand_down')
    Check 'decision signal->stand_down'  ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds 5    -HeartbeatStaleSeconds 45 -LastExitReason 'signal'         -RestartsInWindow 0 -MaxRestarts 5) -eq 'stand_down')
    Check 'decision crashloop->backoff'  ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds $null -HeartbeatStaleSeconds 45 -LastExitReason 'fatal_error'   -RestartsInWindow 5 -MaxRestarts 5) -eq 'backoff')
    # D-0055: a still-heartbeating but WEDGED executor -> kill_restart (fix 3). New params default benign.
    Check 'decision degraded->kill_restart'        ((Get-WatchdogDecision -Alive $true -HeartbeatAgeSeconds 3 -HeartbeatStaleSeconds 45 -LastExitReason $null -RestartsInWindow 0 -MaxRestarts 5 -Degraded $true) -eq 'kill_restart')
    Check 'decision wedged_running->kill_restart'  ((Get-WatchdogDecision -Alive $true -HeartbeatAgeSeconds 3 -HeartbeatStaleSeconds 45 -LastExitReason $null -RestartsInWindow 0 -MaxRestarts 5 -WedgedRunning $true) -eq 'kill_restart')
    Check 'decision pollstreak->kill_restart'      ((Get-WatchdogDecision -Alive $true -HeartbeatAgeSeconds 3 -HeartbeatStaleSeconds 45 -LastExitReason $null -RestartsInWindow 0 -MaxRestarts 5 -PollErrorStreak 5 -PollErrorThreshold 5) -eq 'kill_restart')
    Check 'decision benign-wedge-params->none'     ((Get-WatchdogDecision -Alive $true -HeartbeatAgeSeconds 3 -HeartbeatStaleSeconds 45 -LastExitReason $null -RestartsInWindow 0 -MaxRestarts 5 -Degraded $false -PollErrorStreak 0 -WedgedRunning $false) -eq 'none')

    # ---------------------------------------------------------------- Test-ExecutorAlive
    $tlock = Join-Path $tmp ("lo-lock-" + [guid]::NewGuid().ToString('N') + '.lock')
    Check 'alive absent->false' ((Test-ExecutorAlive -LockPath $tlock) -eq $false)
    $fs = [System.IO.File]::Open($tlock, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    Check 'alive held->true'  ((Test-ExecutorAlive -LockPath $tlock) -eq $true)
    $fs.Close(); $fs.Dispose()
    Check 'alive free->false' ((Test-ExecutorAlive -LockPath $tlock) -eq $false)
    Remove-Item $tlock -Force -ErrorAction SilentlyContinue

    # ---------------------------------------------------------------- Get-ExecutorState (synthetic)
    $sroot = Join-Path $tmp ("lo-state-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $sroot 'control') -Force | Out-Null
    $synthHb = Join-Path $sroot 'control/heartbeat.json'
    [System.IO.File]::WriteAllText($synthHb, (@{ instance_id='x'; pid=1234; at_utc=([DateTime]::UtcNow).ToString('o'); active_tasks=0 } | ConvertTo-Json), $enc)
    (Get-Item -LiteralPath $synthHb).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddSeconds(-5)   # simulate a 5s-old heartbeat via mtime
    [System.IO.File]::WriteAllText((Join-Path $sroot 'control/last-exit.json'), (@{ instance_id='x'; pid=1234; at_utc=([DateTime]::UtcNow).ToString('o'); reason='signal' } | ConvertTo-Json), $enc)
    $st = Get-ExecutorState -Root $sroot
    Check 'state not-alive'          ($st.alive -eq $false)
    Check 'state heartbeat age'      ($null -ne $st.heartbeat_age_seconds -and $st.heartbeat_age_seconds -ge 3 -and $st.heartbeat_age_seconds -le 60)
    Check 'state last_exit=signal'   ($st.last_exit_reason -eq 'signal')
    Remove-Item $sroot -Recurse -Force -ErrorAction SilentlyContinue

    # ---------------------------------------------------------------- Get-ExecutorState wedge signals (synthetic)
    $wroot = Join-Path $tmp ("lo-wedge-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $wroot 'control') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $wroot 'running/wtask') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $wroot 'control/heartbeat.json'), (@{ instance_id='w'; pid=222; at_utc=([DateTime]::UtcNow).ToString('o'); active_tasks=1; degraded=$true; poll_error_streak=6; stuck_finalize_count=1 } | ConvertTo-Json), $enc)
    [System.IO.File]::WriteAllText((Join-Path $wroot 'running/wtask/state.json'), (@{ task_id='wtask'; status='running'; started_at_utc=(([DateTime]::UtcNow).AddSeconds(-120)).ToString('o'); timeout_seconds=2 } | ConvertTo-Json), $enc)
    $wst = Get-ExecutorState -Root $wroot -WedgeGraceSeconds 30
    Check 'state reads degraded'              ($wst.degraded -eq $true)
    Check 'state reads poll_error_streak'     ($wst.poll_error_streak -eq 6)
    Check 'state detects wedged_running'      ($wst.wedged_running -eq $true -and $wst.wedged_running_task -eq 'wtask')
    # a running task WITHIN its timeout must NOT count as wedged (no false positive on a normal long task)
    [System.IO.File]::WriteAllText((Join-Path $wroot 'running/wtask/state.json'), (@{ task_id='wtask'; status='running'; started_at_utc=([DateTime]::UtcNow).ToString('o'); timeout_seconds=600 } | ConvertTo-Json), $enc)
    $wst2 = Get-ExecutorState -Root $wroot -WedgeGraceSeconds 30
    Check 'state: fresh long task not wedged' ($wst2.wedged_running -eq $false)
    Remove-Item $wroot -Recurse -Force -ErrorAction SilentlyContinue

    # ---- regression (D-0055 fix escape): wedge detection must be TIMEZONE-ROBUST. ConvertFrom-Json turns
    # started_at_utc into a [datetime]; the old code re-stringified + re-parsed it, leaking the machine's
    # LOCAL offset -- invisible on a UTC box (local==UTC) but wrong on the Windows executor. Re-run the same
    # check in a CHILD pwsh forced to a non-UTC zone so the UTC gate reproduces the non-UTC condition. TZ
    # takes effect on Linux/macOS; on Windows the box's own (already non-UTC) local zone exercises it. Old
    # code -> wedged_running=$false here.
    $tzRoot = Join-Path $tmp ("lo-wedgetz-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $tzRoot 'running/tztask') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $tzRoot 'running/tztask/state.json'), (@{ task_id='tztask'; status='running'; started_at_utc=(([DateTime]::UtcNow).AddSeconds(-120)).ToString('o'); timeout_seconds=2 } | ConvertTo-Json), $enc)
    $tzProbe = Join-Path $tzRoot 'probe.ps1'
    # NB: the probe's params are named to NOT collide with the watchdog's own param block -- dot-sourcing
    # `. $Watch -DefineOnly` re-declares the watchdog's -Root/-PwshPath (Windows defaults) in this scope, so a
    # probe param called $Root would be clobbered to a C:\ path (same trap the in-process test dodges via $wroot).
    [System.IO.File]::WriteAllText($tzProbe, @'
param([string]$ProbeWatch, [string]$ProbeRoot)
. $ProbeWatch -DefineOnly
$st = Get-ExecutorState -Root $ProbeRoot -WedgeGraceSeconds 30
[Console]::Out.WriteLine("OFFSET=$(([DateTimeOffset](Get-Date)).Offset.TotalHours) WEDGED=$($st.wedged_running) TASK=$($st.wedged_running_task)")
'@, $enc)
    $prevTz = $env:TZ
    $env:TZ = 'America/New_York'
    try { $tzOut = (& $PwshPath -NoProfile -File $tzProbe -ProbeWatch $watch -ProbeRoot $tzRoot 2>&1 | Out-String) }
    finally { if ($null -eq $prevTz) { Remove-Item Env:TZ -ErrorAction SilentlyContinue } else { $env:TZ = $prevTz } }
    Check 'state wedge detection is timezone-robust (non-UTC child)' (($tzOut -match 'WEDGED=True') -and ($tzOut -match 'TASK=tztask'))
    Remove-Item $tzRoot -Recurse -Force -ErrorAction SilentlyContinue

    # ---------------------------------------------------------------- Module 0 markers (real, temp runtime)
    $r1 = Join-Path $tmp ("lo-wd-m0-" + [guid]::NewGuid().ToString('N'))
    $exe1 = Start-Bg @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$exeScript,'-Root',$r1,'-PwshPath',$PwshPath)
    $hb1 = Join-Path $r1 'control/heartbeat.json'
    Check 'm0 heartbeat appears' (WaitFor { Test-Path -LiteralPath $hb1 } 25)
    $first = Read-Json $hb1
    Start-Sleep -Seconds 3
    $second = Read-Json $hb1
    Check 'm0 heartbeat refreshes' ($null -ne $first -and $null -ne $second -and $first.at_utc -ne $second.at_utc)
    [System.IO.File]::WriteAllText((Join-Path $r1 'control/stop.requested'), ([DateTime]::UtcNow.ToString('o')), $enc)
    $le1 = Join-Path $r1 'control/last-exit.json'
    Check 'm0 last-exit appears on stop' (WaitFor { Test-Path -LiteralPath $le1 } 25)
    $leObj = Read-Json $le1
    Check 'm0 last-exit reason=stop_requested' ($null -ne $leObj -and $leObj.reason -eq 'stop_requested')
    Check 'm0 lock removed on clean stop' (WaitFor { -not (Test-Path -LiteralPath (Join-Path $r1 'control/executor.lock')) } 15)

    # ---------------------------------------------------------------- Integration (watchdog)
    $r2 = Join-Path $tmp ("lo-wd-int-" + [guid]::NewGuid().ToString('N'))
    $exe2 = Start-Bg @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$exeScript,'-Root',$r2,'-PwshPath',$PwshPath)
    $hb2 = Join-Path $r2 'control/heartbeat.json'
    Check 'int executor up' (WaitFor { Test-Path -LiteralPath $hb2 } 25)
    $inst1 = (Read-Json $hb2).instance_id
    $wd = Start-Bg @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$watch,'-Root',$r2,'-ExecutorScript',$exeScript,'-PwshPath',$PwshPath,'-PollSeconds','3','-HeartbeatStaleSeconds','20','-MaxRestarts','5','-RestartWindowSeconds','300')
    Start-Sleep -Seconds 2
    # simulate a CRASH: hard-kill the executor (leaves no last-exit marker)
    Kill-Tree $exe2.Id
    # watchdog must restart it autonomously -> a new instance id appears
    $restarted = WaitFor { $o = Read-Json $hb2; $null -ne $o -and $o.instance_id -ne $inst1 } 40
    Check 'int watchdog auto-restarts a crash (no approval)' $restarted
    # now an AUTHORIZED stop -> watchdog must stand down (exit) and NOT restart
    [System.IO.File]::WriteAllText((Join-Path $r2 'control/stop.requested'), ([DateTime]::UtcNow.ToString('o')), $enc)
    Check 'int watchdog stands down on authorized stop' (WaitFor { $wd.Refresh(); $wd.HasExited } 45)
    Start-Sleep -Seconds 4
    Check 'int executor stays stopped (not restarted)' ((Test-ExecutorAlive -LockPath (Join-Path $r2 'control/executor.lock')) -eq $false)

    # ---------------------------------------------------------------- Integration: WEDGE recovery (D-0055 fix 3)
    $r3 = Join-Path $tmp ("lo-wd-wedge-" + [guid]::NewGuid().ToString('N'))
    $exe3 = Start-Bg @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$exeScript,'-Root',$r3,'-PwshPath',$PwshPath)
    $hb3 = Join-Path $r3 'control/heartbeat.json'
    Check 'wedge: executor up' (WaitFor { Test-Path -LiteralPath $hb3 } 25)
    $winst1 = (Read-Json $hb3).instance_id
    # After startup recovery has run, drop a running task already past its timeout that will never be
    # finalized -- a wedge the FRESH heartbeat hides. The watchdog's running/-scan must catch it.
    New-Item -ItemType Directory -Path (Join-Path $r3 'running/stuck-001') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $r3 'running/stuck-001/state.json'), (@{ task_id='stuck-001'; status='running'; started_at_utc=(([DateTime]::UtcNow).AddSeconds(-120)).ToString('o'); timeout_seconds=2 } | ConvertTo-Json), $enc)
    $wd3 = Start-Bg @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$watch,'-Root',$r3,'-ExecutorScript',$exeScript,'-PwshPath',$PwshPath,'-PollSeconds','3','-HeartbeatStaleSeconds','60','-WedgeGraceSeconds','5','-MaxRestarts','5','-RestartWindowSeconds','300')
    # the executor keeps heartbeating (age < 60s) so ONLY the wedge detection can trigger a recovery
    $wrestarted = WaitFor { $o = Read-Json $hb3; $null -ne $o -and $o.instance_id -ne $winst1 } 45
    Check 'wedge: watchdog recovers a wedged-but-heartbeating executor' $wrestarted
    [System.IO.File]::WriteAllText((Join-Path $r3 'control/watchdog.stop.requested'), ([DateTime]::UtcNow.ToString('o')), $enc)
    [void](WaitFor { $wd3.Refresh(); $wd3.HasExited } 30)
}
finally {
    foreach ($p in @($wd, $wd3, $exe1, $exe2, $exe3)) { try { if ($null -ne $p -and -not $p.HasExited) { Kill-Tree $p.Id } } catch { } }
    foreach ($root in @($r1, $r2, $r3)) {
        if ($null -ne $root) {
            try { $o = Read-Json (Join-Path $root 'control/heartbeat.json'); if ($null -ne $o -and $o.pid) { Kill-Tree ([int]$o.pid) } } catch { }
            try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
