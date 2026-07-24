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
function Kill-Tree([int]$ProcId) { if ($ProcId -gt 0) { try { & taskkill.exe /PID $ProcId /T /F 2>&1 | Out-Null } catch { } } }

$exe1 = $null; $exe2 = $null; $wd = $null; $r1 = $null; $r2 = $null
try {
    # ---------------------------------------------------------------- pure decision
    . $watch -DefineOnly
    Check 'decision healthy->none'       ((Get-WatchdogDecision -Alive $true  -HeartbeatAgeSeconds 3    -HeartbeatStaleSeconds 45 -LastExitReason $null           -RestartsInWindow 0 -MaxRestarts 5) -eq 'none')
    Check 'decision hung->kill_restart'  ((Get-WatchdogDecision -Alive $true  -HeartbeatAgeSeconds 90   -HeartbeatStaleSeconds 45 -LastExitReason $null           -RestartsInWindow 0 -MaxRestarts 5) -eq 'kill_restart')
    Check 'decision crash->restart'      ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds 50   -HeartbeatStaleSeconds 45 -LastExitReason 'fatal_error'    -RestartsInWindow 0 -MaxRestarts 5) -eq 'restart')
    Check 'decision hardkill->restart'   ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds $null -HeartbeatStaleSeconds 45 -LastExitReason $null          -RestartsInWindow 0 -MaxRestarts 5) -eq 'restart')
    Check 'decision stop_requested->stand_down' ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds 5 -HeartbeatStaleSeconds 45 -LastExitReason 'stop_requested' -RestartsInWindow 0 -MaxRestarts 5) -eq 'stand_down')
    Check 'decision signal->stand_down'  ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds 5    -HeartbeatStaleSeconds 45 -LastExitReason 'signal'         -RestartsInWindow 0 -MaxRestarts 5) -eq 'stand_down')
    Check 'decision crashloop->backoff'  ((Get-WatchdogDecision -Alive $false -HeartbeatAgeSeconds $null -HeartbeatStaleSeconds 45 -LastExitReason 'fatal_error'   -RestartsInWindow 5 -MaxRestarts 5) -eq 'backoff')

    # ---------------------------------------------------------------- Test-ExecutorAlive
    $tlock = Join-Path $env:TEMP ("lo-lock-" + [guid]::NewGuid().ToString('N') + '.lock')
    Check 'alive absent->false' ((Test-ExecutorAlive -LockPath $tlock) -eq $false)
    $fs = [System.IO.File]::Open($tlock, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    Check 'alive held->true'  ((Test-ExecutorAlive -LockPath $tlock) -eq $true)
    $fs.Close(); $fs.Dispose()
    Check 'alive free->false' ((Test-ExecutorAlive -LockPath $tlock) -eq $false)
    Remove-Item $tlock -Force -ErrorAction SilentlyContinue

    # ---------------------------------------------------------------- Get-ExecutorState (synthetic)
    $sroot = Join-Path $env:TEMP ("lo-state-" + [guid]::NewGuid().ToString('N'))
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

    # ---------------------------------------------------------------- Module 0 markers (real, temp runtime)
    $r1 = Join-Path $env:TEMP ("lo-wd-m0-" + [guid]::NewGuid().ToString('N'))
    $exe1 = Start-Process $PwshPath -PassThru -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$exeScript,'-Root',$r1)
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
    $r2 = Join-Path $env:TEMP ("lo-wd-int-" + [guid]::NewGuid().ToString('N'))
    $exe2 = Start-Process $PwshPath -PassThru -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$exeScript,'-Root',$r2)
    $hb2 = Join-Path $r2 'control/heartbeat.json'
    Check 'int executor up' (WaitFor { Test-Path -LiteralPath $hb2 } 25)
    $inst1 = (Read-Json $hb2).instance_id
    $wd = Start-Process $PwshPath -PassThru -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$watch,'-Root',$r2,'-ExecutorScript',$exeScript,'-PollSeconds','3','-HeartbeatStaleSeconds','20','-MaxRestarts','5','-RestartWindowSeconds','300')
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
}
finally {
    foreach ($p in @($wd, $exe1, $exe2)) { try { if ($null -ne $p -and -not $p.HasExited) { Kill-Tree $p.Id } } catch { } }
    foreach ($root in @($r1, $r2)) {
        if ($null -ne $root) {
            try { $o = Read-Json (Join-Path $root 'control/heartbeat.json'); if ($null -ne $o -and $o.pid) { Kill-Tree ([int]$o.pid) } } catch { }
            try { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
