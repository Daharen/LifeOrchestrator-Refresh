<#
    Invoke-WaveDashboardTests.ps1 - dual-mode test harness for the Fan-out Wave Dashboard (Widget 04).

    Cloud pre-ship gate (Linux, no -Live): AST-parse every shipped script; drive the REAL core
    (WaveDashboard.psm1) over the shipped fixture plan/lease dirs + synthetic temp dirs -- plan discovery
    (newest-first), lane classification, latest-report-per-worker, Get-WaveState state mapping for every
    worker state, missing-report -> 'unknown', the ready_for_handoff rule (on_all + on_each), lease parsing
    (age/remaining/expired + a mid-write partial), and Format-WaveRows rendering. Defensive: missing /
    malformed plan.json must return a well-formed ok=false object, never throw.

    Live (Windows, via the executor, -Live): the same tests PLUS launch.bat shape, the WinForms form builds +
    drives (Show-WaveDashboard.ps1 -SelfTest in an STA child, asserting the SELFTEST_*_OK markers), and -- if
    a real orchestrate.fanout plans dir is present -- Get-WaveState renders a REAL plan dir with no throw.
#>
[CmdletBinding()]
param(
    [switch]$Live,
    [string]$PwshPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$widgetRoot = Split-Path $here -Parent
Import-Module (Join-Path $widgetRoot 'WaveDashboard.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}

$fixtures  = Join-Path $here 'fixtures'
$fxPlans   = Join-Path $fixtures 'plans'
$fxLeases  = Join-Path $fixtures 'leases'
$fxTestwave = Join-Path $fxPlans 'fo-99-testwave'
$fxOldwave  = Join-Path $fxPlans 'fo-98-oldwave'

# Fixed clock so lease ages/expiry are deterministic (matches the fixture timestamps).
$NOW = [datetime]::new(2026, 7, 29, 20, 0, 0, [System.DateTimeKind]::Utc)

$script:pass = 0; $script:fail = 0; $script:skip = 0
function Ok([string]$name, $cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name   $detail" }
}
function Skip([string]$name, [string]$why) { $script:skip++; Write-Host "  [SKIP] $name ($why)" }

# Create a throwaway plan dir under temp, returns its path. Reports = @( @{id;state;at} ).
function New-TempPlan {
    param([string]$PlanId, [string]$ReportBack, $Workers, $Reports)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('wdtest-' + $PlanId + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'reports') -Force | Out-Null
    $plan = [ordered]@{
        schema = 'lifeorch.fanout.plan/0.1'; plan_id = $PlanId; iteration = 1; title = "temp $PlanId"
        max_parallel = 3; report_back = $ReportBack; created_at_utc = '2026-07-29T12:00:00.0000000Z'
        workers = $Workers; dispatch_now = @($Workers | ForEach-Object { $_.id }); queued = @()
        conflicts = @{ gpu_serialized = @(); doc_contention = @() }
    }
    [System.IO.File]::WriteAllText((Join-Path $root 'plan.json'), ($plan | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    $n = 0
    foreach ($r in @($Reports)) {
        $n++
        $rep = [ordered]@{
            schema = 'lifeorch.fanout.report/0.1'; plan_id = $PlanId; worker_id = $r.id
            state = $r.state; summary = "s-$($r.id)"; needs = ''; reported_at_utc = $r.at
        }
        [System.IO.File]::WriteAllText((Join-Path $root (Join-Path 'reports' ($r.id + '.' + $n + '.json'))), ($rep | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
    }
    return $root
}
$script:tempRoots = New-Object System.Collections.Generic.List[string]

Write-Host "=== Wave Dashboard tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist
foreach ($fn in 'Get-Prop', 'ConvertTo-Array', 'Limit-Text', 'ConvertTo-UtcTime', 'Read-JsonFileSafe',
    'Resolve-WavePaths', 'Get-WavePlans', 'Get-WorkerLane', 'Get-LatestWorkerReports',
    'Get-WaveLeases', 'Get-LeaseKindRank', 'Get-WaveState', 'Format-Age', 'Format-WaveRows') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'WaveDashboard.psm1'),
    (Join-Path $widgetRoot 'Show-WaveDashboard.ps1'),
    (Join-Path $here 'Invoke-WaveDashboardTests.ps1')
)
foreach ($f in $toParse) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Ok "AST parse: $(Split-Path $f -Leaf)" (@($errs).Count -eq 0) ("errors=" + (@($errs) -join '; '))
}

# 2b. ASCII-only guard on shipped scripts (the 5.1-ANSI / BOM lesson; keep sources portable)
foreach ($f in $toParse) {
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    Ok "ASCII-only: $(Split-Path $f -Leaf)" ($nonAscii -eq 0) ("non-ascii bytes=$nonAscii")
}

# 3. path resolution smoke
$paths = Resolve-WavePaths
Ok "resolve: plans dir path ends in 30-orchestrate-fanout/runtime/plans" ([string]$paths.PlansDir -match '30-orchestrate-fanout' -and [string]$paths.PlansDir -match 'plans')
Ok "resolve: lease dir path ends in 29-resource-lease/runtime/leases" ([string]$paths.LeaseDir -match '29-resource-lease' -and [string]$paths.LeaseDir -match 'leases')

# 4. ConvertTo-Array (StrictMode traps)
Ok "ConvertTo-Array null -> 0" (@(ConvertTo-Array $null).Count -eq 0)
Ok "ConvertTo-Array scalar -> 1" (@(ConvertTo-Array 5).Count -eq 1)
Ok "ConvertTo-Array string -> 1 (not chars)" (@(ConvertTo-Array 'abc').Count -eq 1)
Ok "ConvertTo-Array array -> n" (@(ConvertTo-Array @(1, 2, 3)).Count -eq 3)

# 5. plan discovery (newest-first): fo-99 (created 19:50) before fo-98 (created 18:00)
$plans = @(Get-WavePlans -PlansDir $fxPlans)
Ok "plans: found 2 fixture plans" ($plans.Count -eq 2) ("count=$($plans.Count)")
Ok "plans: newest first = fo-99-testwave" ($plans.Count -ge 1 -and [string]$plans[0].plan_id -eq 'fo-99-testwave') ("first=$([string]$plans[0].plan_id)")
Ok "plans: second = fo-98-oldwave" ($plans.Count -ge 2 -and [string]$plans[1].plan_id -eq 'fo-98-oldwave')
Ok "plans: entry carries iteration + title" ($plans[0].iteration -eq 99 -and [string]$plans[0].title -match 'fixture wave')
Ok "plans: absent dir -> empty array" (@(Get-WavePlans -PlansDir (Join-Path $fixtures 'nope')).Count -eq 0)

# 6. lane classification
Ok "lane: 'CPU lane.' -> cpu" ((Get-WorkerLane ([pscustomobject]@{ notes = 'CPU lane. Edits ops/setup'; gpu = $false })) -eq 'cpu')
Ok "lane: 'Coding lane.' -> coding" ((Get-WorkerLane ([pscustomobject]@{ notes = 'Coding lane. NEW widget'; gpu = $false })) -eq 'coding')
Ok "lane: no hint + gpu -> gpu" ((Get-WorkerLane ([pscustomobject]@{ notes = 'Single GPU worker.'; gpu = $true })) -eq 'gpu')
Ok "lane: no hint + cpu -> cpu" ((Get-WorkerLane ([pscustomobject]@{ notes = ''; gpu = $false })) -eq 'cpu')
Ok "lane: 'broad coding lane' -> coding (word before lane)" ((Get-WorkerLane ([pscustomobject]@{ notes = 'a broad coding lane worker'; gpu = $false })) -eq 'coding')

# 7. latest-report-per-worker (the later 'done' supersedes the earlier 'progress' for W-cpu-done)
$latest = Get-LatestWorkerReports -PlanDir $fxTestwave
Ok "reports: W-cpu-done latest = done" ($latest.ContainsKey('W-cpu-done') -and [string]$latest['W-cpu-done'].state -eq 'done')
Ok "reports: W-gpu-run = progress" ($latest.ContainsKey('W-gpu-run') -and [string]$latest['W-gpu-run'].state -eq 'progress')
Ok "reports: W-code-quiet has NO report" (-not $latest.ContainsKey('W-code-quiet'))

# 8. Get-WaveState over the mixed fixture wave
$st = Get-WaveState -PlanDir $fxTestwave -LeaseDir $fxLeases -Now $NOW
Ok "state: ok" ([bool]$st.ok) ([string]$st.error)
Ok "state: plan_id + iteration + title" ($st.plan_id -eq 'fo-99-testwave' -and $st.iteration -eq 99 -and [string]$st.title -match 'fixture')
Ok "state: report_back on_all" ($st.report_back -eq 'on_all')
Ok "state: dispatch_now=3 queued=0" ($st.dispatch_now -eq 3 -and $st.queued -eq 0)
Ok "state: 3 workers" (@($st.workers).Count -eq 3)
$wg = @($st.workers) | Where-Object { $_.id -eq 'W-gpu-run' } | Select-Object -First 1
$wc = @($st.workers) | Where-Object { $_.id -eq 'W-cpu-done' } | Select-Object -First 1
$wq = @($st.workers) | Where-Object { $_.id -eq 'W-code-quiet' } | Select-Object -First 1
Ok "state: W-gpu-run state=progress lane=gpu gpu=true" ($null -ne $wg -and $wg.state -eq 'progress' -and $wg.lane -eq 'gpu' -and [bool]$wg.gpu)
Ok "state: W-cpu-done state=done lane=cpu gpu=false" ($null -ne $wc -and $wc.state -eq 'done' -and $wc.lane -eq 'cpu' -and -not [bool]$wc.gpu)
Ok "state: W-code-quiet MISSING report -> state=unknown lane=coding" ($null -ne $wq -and $wq.state -eq 'unknown' -and $wq.lane -eq 'coding')
Ok "state: counts done=1 running=1 no_report=1" ($st.counts.done -eq 1 -and $st.counts.running -eq 1 -and $st.counts.no_report -eq 1)
Ok "state: counts total=3 blocked=0 failed=0" ($st.counts.total -eq 3 -and $st.counts.blocked -eq 0 -and $st.counts.failed -eq 0)
Ok "state: on_all + not all terminal -> ready_for_handoff FALSE" (-not [bool]$st.ready_for_handoff)

# 9. Get-WaveState over the fully-done wave -> ready TRUE
$st2 = Get-WaveState -PlanDir $fxOldwave -LeaseDir $fxLeases -Now $NOW
Ok "state(old): 2 workers both done" (@($st2.workers | Where-Object { $_.state -eq 'done' }).Count -eq 2)
Ok "state(old): on_all + all terminal -> ready_for_handoff TRUE" ([bool]$st2.ready_for_handoff)

# 10. lease parsing (fixed Now): gpu/git/doc + partial, order, ages, expiry
$leases = @($st.leases)
Ok "leases: 4 parsed (gpu/git/doc/partial)" ($leases.Count -eq 4) ("count=$($leases.Count)")
Ok "leases: sorted gpu, git, doc:*, unknown" ($leases.Count -eq 4 -and $leases[0].kind -eq 'gpu' -and $leases[1].kind -eq 'git' -and $leases[2].kind -eq 'doc:CURRENT_STATE.md' -and $leases[3].kind -eq '<unknown>')
$lg = $leases[0]; $ld = $leases[2]; $lp = $leases[3]
Ok "leases: gpu holder + age 900s + remaining 900s + not expired" ($lg.holder -eq 'W-gpu-run' -and $lg.age_s -eq 900 -and $lg.remaining_s -eq 900 -and -not [bool]$lg.expired)
Ok "leases: doc lease EXPIRED (remaining negative)" ([bool]$ld.expired -and $ld.remaining_s -lt 0)
Ok "leases: partial (mid-write) -> holder '<writing>' + null age" ($lp.holder -eq '<writing>' -and $null -eq $lp.age_s)
Ok "leases: absent lease dir -> empty" (@(Get-WaveLeases -LeaseDir (Join-Path $fixtures 'nope') -Now $NOW).Count -eq 0)

# 11. synthetic states: every worker state maps; both ready rules
$twOnEach = New-TempPlan -PlanId 'oneach' -ReportBack 'on_each' `
    -Workers @([pscustomobject]@{ id = 'x'; gpu = $false; notes = '' }, [pscustomobject]@{ id = 'y'; gpu = $false; notes = '' }) `
    -Reports @(@{ id = 'x'; state = 'done'; at = '2026-07-29T10:00:00.0000000Z' }, @{ id = 'y'; state = 'progress'; at = '2026-07-29T10:01:00.0000000Z' })
$script:tempRoots.Add($twOnEach)
$se = Get-WaveState -PlanDir $twOnEach -LeaseDir (Join-Path $fixtures 'nope') -Now $NOW
Ok "on_each: >=1 terminal -> ready TRUE" ([bool]$se.ready_for_handoff)
Ok "on_each: counts done=1 running=1" ($se.counts.done -eq 1 -and $se.counts.running -eq 1)

$twFail = New-TempPlan -PlanId 'failwave' -ReportBack 'on_all' `
    -Workers @([pscustomobject]@{ id = 'a'; gpu = $false; notes = '' }, [pscustomobject]@{ id = 'b'; gpu = $false; notes = '' }) `
    -Reports @(@{ id = 'a'; state = 'done'; at = '2026-07-29T10:00:00.0000000Z' }, @{ id = 'b'; state = 'failed'; at = '2026-07-29T10:00:00.0000000Z' })
$script:tempRoots.Add($twFail)
$sf = Get-WaveState -PlanDir $twFail -LeaseDir (Join-Path $fixtures 'nope') -Now $NOW
Ok "failed counts as terminal: on_all done+failed == total -> ready TRUE" ([bool]$sf.ready_for_handoff)
Ok "failed: counts failed=1 done=1" ($sf.counts.failed -eq 1 -and $sf.counts.done -eq 1)

$twBlock = New-TempPlan -PlanId 'blockwave' -ReportBack 'on_all' `
    -Workers @([pscustomobject]@{ id = 'a'; gpu = $false; notes = '' }, [pscustomobject]@{ id = 'b'; gpu = $false; notes = '' }) `
    -Reports @(@{ id = 'a'; state = 'done'; at = '2026-07-29T10:00:00.0000000Z' }, @{ id = 'b'; state = 'blocked'; at = '2026-07-29T10:00:00.0000000Z' })
$script:tempRoots.Add($twBlock)
$sb = Get-WaveState -PlanDir $twBlock -LeaseDir (Join-Path $fixtures 'nope') -Now $NOW
Ok "blocked is NOT terminal: on_all -> ready FALSE" (-not [bool]$sb.ready_for_handoff)
Ok "blocked: counts blocked=1" ($sb.counts.blocked -eq 1)

$twStarted = New-TempPlan -PlanId 'startwave' -ReportBack 'on_all' `
    -Workers @([pscustomobject]@{ id = 'a'; gpu = $false; notes = '' }) `
    -Reports @(@{ id = 'a'; state = 'started'; at = '2026-07-29T10:00:00.0000000Z' })
$script:tempRoots.Add($twStarted)
$ss = Get-WaveState -PlanDir $twStarted -LeaseDir (Join-Path $fixtures 'nope') -Now $NOW
Ok "started -> running bucket, not ready" ($ss.counts.running -eq 1 -and -not [bool]$ss.ready_for_handoff)

# 12. defensive: missing / malformed plan.json -> ok=false, no throw
$missing = Get-WaveState -PlanDir (Join-Path $fixtures 'no-such-plan') -LeaseDir $fxLeases -Now $NOW
Ok "missing plan.json -> ok=false (well-formed, no throw)" (-not [bool]$missing.ok -and [string]$missing.error -match 'plan.json')
Ok "missing plan.json -> still returns leases + empty workers" (@($missing.workers).Count -eq 0 -and @($missing.leases).Count -eq 4)

$badRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wdtest-bad-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $badRoot -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $badRoot 'plan.json'), '{ not valid json ', [System.Text.UTF8Encoding]::new($false))
$script:tempRoots.Add($badRoot)
$badState = Get-WaveState -PlanDir $badRoot -LeaseDir (Join-Path $fixtures 'nope') -Now $NOW
Ok "malformed plan.json -> ok=false (no throw)" (-not [bool]$badState.ok)

# 12b. a garbage file in reports/ must be skipped, not throw
$gj = New-TempPlan -PlanId 'garbagereports' -ReportBack 'on_all' `
    -Workers @([pscustomobject]@{ id = 'a'; gpu = $false; notes = '' }) -Reports @(@{ id = 'a'; state = 'done'; at = '2026-07-29T10:00:00.0000000Z' })
$script:tempRoots.Add($gj)
[System.IO.File]::WriteAllText((Join-Path $gj (Join-Path 'reports' 'garbage.json')), 'not json at all', [System.Text.UTF8Encoding]::new($false))
$gjState = Get-WaveState -PlanDir $gj -LeaseDir (Join-Path $fixtures 'nope') -Now $NOW
Ok "garbage report file skipped, real one read (done=1)" ([bool]$gjState.ok -and $gjState.counts.done -eq 1)

# 13. Format-WaveRows rendering
$rows = Format-WaveRows -State $st
Ok "rows: header names the plan" ((@($rows.header_lines) -join ' ') -match 'fo-99-testwave')
Ok "rows: header shows not-ready" ((@($rows.header_lines) -join ' ') -match 'False' -or $rows.ready_text -eq 'not ready')
Ok "rows: worker header has ID/LANE/GPU/STATE" ($rows.worker_header -match 'ID' -and $rows.worker_header -match 'LANE' -and $rows.worker_header -match 'GPU' -and $rows.worker_header -match 'STATE')
Ok "rows: a worker line shows the coding lane" ((@($rows.worker_lines) -join "`n") -match 'coding')
Ok "rows: lease line shows gpu + holder" ((@($rows.lease_lines) -join "`n") -match 'gpu' -and (@($rows.lease_lines) -join "`n") -match 'W-gpu-run')
Ok "rows: lease line marks the expired doc lease" ((@($rows.lease_lines) -join "`n") -match 'EXPIRED')
Ok "rows: summary line + ready_text for a ready wave" ((Format-WaveRows -State $st2).ready_text -eq 'READY FOR HANDOFF')
$rowsMissing = Format-WaveRows -State $missing
Ok "rows: no-wave state renders 'NO WAVE LOADED' (no throw)" ((@($rowsMissing.header_lines) -join ' ') -match 'NO WAVE LOADED')

# 14. Format-Age
Ok "Format-Age null -> '-'" ((Format-Age $null) -eq '-')
Ok "Format-Age 900 -> 15m00s" ((Format-Age 900) -eq '15m00s')
Ok "Format-Age negative -> leading '-'" ((Format-Age -600) -like '-*')

# ---------- LIVE (Windows) ----------
if ($Live) {
    if (-not $IsWindows) { Skip 'live: WinForms self-test' 'not Windows'; Skip 'live: launch.bat' 'not Windows'; Skip 'live: real plan dir' 'not Windows' }
    else {
        # launch.bat shape
        $lb = Join-Path $widgetRoot 'launch.bat'
        Ok "live: launch.bat exists" (Test-Path $lb)
        if (Test-Path $lb) {
            $lbTxt = Get-Content -LiteralPath $lb -Raw
            Ok "live: launch.bat runs Show-WaveDashboard.ps1 under -STA" ($lbTxt -match 'Show-WaveDashboard\.ps1' -and $lbTxt -match '-STA')
        }
        # WinForms self-test in an STA child
        $show = Join-Path $widgetRoot 'Show-WaveDashboard.ps1'
        $out = & $PwshPath -NoProfile -STA -File $show -SelfTest 2>&1 | Out-String
        Write-Host "  --- self-test child output ---"
        foreach ($ln in ($out -split "`r?`n")) { if ($ln.Trim()) { Write-Host "    $ln" } }
        foreach ($marker in 'SELFTEST_FORM_OK', 'SELFTEST_PICKER_OK', 'SELFTEST_RENDER_OK', 'SELFTEST_READY_OK', 'SELFTEST_REFRESH_OK', 'SELFTEST_LAYOUT_OK') {
            Ok "live: self-test emitted $marker" ($out -match $marker)
        }
        Ok "live: self-test has no FAIL marker" (-not ($out -match 'SELFTEST_\w+_FAIL'))

        # render a REAL orchestrate.fanout plan dir if one is present (proves it reads production files)
        $realPlans = (Resolve-WavePaths).PlansDir
        if (Test-Path -LiteralPath $realPlans -PathType Container) {
            $realList = @(Get-WavePlans -PlansDir $realPlans)
            Ok "live: real plans dir lists >=1 plan" ($realList.Count -ge 1) ("count=$($realList.Count)")
            if ($realList.Count -ge 1) {
                $realState = Get-WaveState -PlanDir ([string]$realList[0].dir) -LeaseDir (Resolve-WavePaths).LeaseDir
                Ok "live: Get-WaveState renders the newest REAL wave (ok, has workers)" ([bool]$realState.ok -and @($realState.workers).Count -ge 1) ("plan=$([string]$realState.plan_id) workers=$(@($realState.workers).Count)")
            }
        }
        else { Skip 'live: real plan dir' 'no plans dir on this box' }
    }
}
else {
    Skip 'live: WinForms self-test' 'cloud gate (use -Live on Windows)'
    Skip 'live: launch.bat shape' 'cloud gate'
    Skip 'live: real plan dir render' 'cloud gate'
}

# cleanup temp dirs
foreach ($t in $script:tempRoots) { try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue } catch { } }

Write-Host ""
Write-Host "=== RESULT: pass=$($script:pass) fail=$($script:fail) skip=$($script:skip) ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
