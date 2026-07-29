<#
    WaveDashboard.psm1 - driver core for the Fan-out Wave Dashboard (Widget 04).

    The wave-status analogue of the Verification Console (Widget 03): a READ-ONLY view over a fan-out wave's
    live runtime state, answering "where is this wave right now?" at a glance. It parses the orchestrate.fanout
    (#30) plan dir (plan.json + reports/*.json) and the res.lease (#29) leases dir (*.lease files) DIRECTLY --
    the runtime files ARE the source of truth -- so the dashboard has ZERO side effects: it never invokes
    orchestrate.fanout or res.lease, never drives a worker, and never writes to the plans/leases dirs.

    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate (against fixture plan /
    lease dirs) and on Windows. The UI (Show-WaveDashboard.ps1) is a thin shell over these functions. It
    reimplements nothing (it reads the same files the orchestrator writes, and computes ready_for_handoff by
    the SAME rule Invoke-OrchestrateFanout.ps1 uses for -Action status). NOT a review-queue producer.

    Design mirrors VerificationConsole.psm1 / ModuleLauncher.psm1: defensive Get-Prop, List[object] + .ToArray()
    (never a bare @() on a maybe-null / on a raw List), [IO.Path]::Combine for a foreign-platform-safe join
    (a cloud-gate RepoRoot like 'C:\...' must not throw "Cannot find drive 'C'"), ASCII-only source.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WaveWidgetRoot = $PSScriptRoot
$script:PlanSchema   = 'lifeorch.fanout.plan/0.1'
$script:ReportSchema = 'lifeorch.fanout.report/0.1'
$script:LeaseSchema  = 'lifeorch.res.lease/0.1'

# terminal worker states, per Invoke-OrchestrateFanout.ps1 status: terminal = done + failed.
$script:TerminalStates = @('done', 'failed')

# ============================================================================
#  small helpers (shared shape with VerificationConsole.psm1 / ModuleLauncher.psm1)
# ============================================================================

function Test-HasProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject -and $null -ne $Object.PSObject.Properties[$Name])
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { $v = $Object[$Name]; if ($null -ne $v) { return $v } ; return $Default }
        return $Default
    }
    if (Test-HasProp $Object $Name) { $v = $Object.$Name; if ($null -ne $v) { return $v } }
    return $Default
}

function ConvertTo-Array {
    # Normalize a maybe-null / scalar / array JSON value to plain elements, WITHOUT the StrictMode empty-unroll
    # or array-double-wrap traps (a string stays one element, not a char array). Emits the elements to the
    # pipeline; callers ALWAYS wrap the call in @( ... ) so a 0/1/n result is a real array with a safe .Count.
    param($Value)
    $acc = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Value) {
        if ($Value -is [string]) { [void]$acc.Add($Value) }   # a string is one element, not a char array
        elseif ($Value -is [System.Collections.IEnumerable]) { foreach ($v in $Value) { [void]$acc.Add($v) } }
        else { [void]$acc.Add($Value) }
    }
    return $acc.ToArray()
}

function Limit-Text {
    param($Text, [int]$Max = 90)
    if ($null -eq $Text) { return '' }
    $s = ([string]$Text) -replace '\s+', ' '
    $s = $s.Trim()
    if ($s.Length -le $Max) { return $s }
    if ($Max -le 3) { return $s.Substring(0, $Max) }
    return $s.Substring(0, $Max - 3) + '...'
}

# Parse a timestamp (ISO-8601 'o', or a [datetime] handed back by ConvertFrom-Json) to a UTC [datetime].
# Robust across timezones (mirrors res.lease ConvertTo-Utc): do NOT re-stringify a Kind=Utc value.
function ConvertTo-UtcTime {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value }
        if ($Value.Kind -eq [System.DateTimeKind]::Local) { return $Value.ToUniversalTime() }
        return [System.DateTime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $dt = [datetime]::MinValue
    # RoundtripKind honours an explicit 'Z'/offset (our stamps are always ISO-8601 'o' with 'Z' -> Kind=Utc).
    # It must NOT be combined with AssumeUniversal/AdjustToUniversal (.NET throws on that mix); the branches
    # below normalise a Local or Unspecified parse to UTC for any offset-less string.
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) {
        if ($dt.Kind -eq [System.DateTimeKind]::Local) { return $dt.ToUniversalTime() }
        if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) { return [System.DateTime]::SpecifyKind($dt, [System.DateTimeKind]::Utc) }
        return $dt
    }
    return $null
}

# Read + parse a JSON file DEFENSIVELY (shared read/delete access, tolerant of a mid-write file). Returns the
# parsed object, or $null on any problem (missing / locked / empty / unparseable) -- callers turn $null into a
# well-formed 'unknown' row and NEVER throw.
function Read-JsonFileSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $txt = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.UTF8Encoding]::new($false))
            try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
        }
        finally { $fs.Dispose() }
    }
    catch { return $null }
    if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
    try { return ($txt | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

# ============================================================================
#  path resolution
# ============================================================================

function Resolve-WavePaths {
    <#
        Resolve the widget root, repo root, and the two data-source dirs the dashboard reads. Env overrides
        (shared with orchestrate.fanout / res.lease) win so a caller can point at a test tree:
          plans  : $env:LIFEORCH_FANOUT_DIR else <repo>/modules/30-orchestrate-fanout/runtime/plans
          leases : $env:LIFEORCH_LEASE_DIR  else <repo>/modules/29-resource-lease/runtime/leases
        [IO.Path]::Combine is a pure string join (no PSDrive resolution) so a foreign-platform RepoRoot in a
        cloud-gate test does not throw "Cannot find drive 'C'".
    #>
    [CmdletBinding()]
    param([string]$WidgetRoot, [string]$PlansDir, [string]$LeaseDir)

    if (-not $WidgetRoot) { $WidgetRoot = $script:WaveWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    $repoRoot = $null
    $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
    if ($rp) { $repoRoot = $rp.Path } else { $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }

    if (-not $PlansDir) {
        if ($env:LIFEORCH_FANOUT_DIR) { $PlansDir = $env:LIFEORCH_FANOUT_DIR }
        else { $PlansDir = [System.IO.Path]::Combine($repoRoot, 'modules', '30-orchestrate-fanout', 'runtime', 'plans') }
    }
    if (-not $LeaseDir) {
        if ($env:LIFEORCH_LEASE_DIR) { $LeaseDir = $env:LIFEORCH_LEASE_DIR }
        else { $LeaseDir = [System.IO.Path]::Combine($repoRoot, 'modules', '29-resource-lease', 'runtime', 'leases') }
    }
    return [pscustomobject]@{
        WidgetRoot = $WidgetRoot
        RepoRoot   = $repoRoot
        PlansDir   = $PlansDir
        LeaseDir   = $LeaseDir
    }
}

# ============================================================================
#  plan discovery (the plan picker: list the plans dir, newest first)
# ============================================================================

function Get-WavePlans {
    <#
        Scan -PlansDir for <plan_id>/plan.json and return a normalized, NEWEST-FIRST list so the shell can
        offer a plan picker without hunting. Order key = the plan's created_at_utc (parsed), falling back to
        the plan.json file mtime. Each entry:
          { plan_id, dir, path, iteration, title, report_back, created_at, mtime_utc, ok, error }
        A malformed plan.json is INCLUDED with ok=false + a short error (never dropped, never throws). Returns
        @() when the dir is absent/empty. WinForms-free + disk-only, so it is unit-tested off-machine.
    #>
    [CmdletBinding()]
    param([string]$PlansDir, [int]$Max = 100)
    if (-not $PlansDir) { $PlansDir = (Resolve-WavePaths).PlansDir }
    if ([string]::IsNullOrWhiteSpace($PlansDir) -or -not (Test-Path -LiteralPath $PlansDir -PathType Container)) {
        return @()
    }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-ChildItem -LiteralPath $PlansDir -Directory -ErrorAction SilentlyContinue)) {
        $pf = Join-Path $d.FullName 'plan.json'
        if (-not (Test-Path -LiteralPath $pf -PathType Leaf)) { continue }
        $fi = Get-Item -LiteralPath $pf -ErrorAction SilentlyContinue
        $mtime = if ($null -ne $fi) { $fi.LastWriteTimeUtc } else { [datetime]::MinValue }
        $obj = Read-JsonFileSafe -Path $pf
        $ok = ($null -ne $obj)
        $planId = if ($ok) { [string](Get-Prop $obj 'plan_id' (Split-Path -Leaf $d.FullName)) } else { Split-Path -Leaf $d.FullName }
        $createdRaw = if ($ok) { [string](Get-Prop $obj 'created_at_utc' '') } else { '' }
        $createdDt = ConvertTo-UtcTime $createdRaw
        $sortKey = if ($null -ne $createdDt) { $createdDt } else { $mtime }
        $entries.Add([pscustomobject]@{
                plan_id     = $planId
                dir         = $d.FullName
                path        = $pf
                iteration   = if ($ok) { [int](Get-Prop $obj 'iteration' 0) } else { 0 }
                title       = if ($ok) { [string](Get-Prop $obj 'title' '') } else { '' }
                report_back = if ($ok) { [string](Get-Prop $obj 'report_back' 'on_all') } else { '' }
                created_at  = $createdRaw
                mtime_utc   = $mtime
                sort_key    = $sortKey
                ok          = $ok
                error       = if ($ok) { '' } else { 'unreadable or invalid plan.json' }
            })
    }
    $sorted = @($entries.ToArray() | Sort-Object -Property sort_key -Descending)
    if ($sorted.Count -gt $Max) { $sorted = @($sorted[0..($Max - 1)]) }
    return $sorted
}

# ============================================================================
#  worker state (read the latest report per worker) + lane classification
# ============================================================================

function Get-WorkerLane {
    <#
        Classify a worker into a "lane" string distinct from its GPU boolean (the wave has GPU / CPU / coding /
        frontier lanes; the plan record has no explicit lane field). Rule (pure + tested):
          1. an explicit "<word> lane" hint in notes (e.g. "CPU lane." -> cpu, "Coding lane." -> coding),
          2. else 'gpu' when the worker is a GPU worker,
          3. else 'cpu'.
    #>
    [CmdletBinding()]
    param($Worker)
    $notes = [string](Get-Prop $Worker 'notes' '')
    if ($notes) {
        $m = [regex]::Match($notes, '(?i)([A-Za-z]+)\s+lane\b')
        if ($m.Success) {
            $lane = $m.Groups[1].Value.ToLowerInvariant()
            if ($lane) { return $lane }
        }
    }
    if ([bool](Get-Prop $Worker 'gpu' $false)) { return 'gpu' }
    return 'cpu'
}

function Get-LatestWorkerReports {
    <#
        Read reports/*.json under a plan dir and return a hashtable worker_id -> { state, summary, reported_at }
        keeping the LATEST report per worker by reported_at_utc (ISO-8601 'o' sorts lexically), EXACTLY as
        Invoke-OrchestrateFanout.ps1 Get-WorkerStates does. Missing/partial report files are skipped (never
        throw). Returns @{} when there is no reports dir.
    #>
    [CmdletBinding()]
    param([string]$PlanDir)
    $latest = @{}
    if ([string]::IsNullOrWhiteSpace($PlanDir)) { return $latest }
    $reportsDir = Join-Path $PlanDir 'reports'
    if (-not (Test-Path -LiteralPath $reportsDir -PathType Container)) { return $latest }
    foreach ($f in @(Get-ChildItem -LiteralPath $reportsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $r = Read-JsonFileSafe -Path $f.FullName
        if ($null -eq $r) { continue }
        $wid = [string](Get-Prop $r 'worker_id' '')
        if ([string]::IsNullOrWhiteSpace($wid)) { continue }
        $ra = [string](Get-Prop $r 'reported_at_utc' '')
        if ((-not $latest.ContainsKey($wid)) -or ($ra -gt [string]$latest[$wid].reported_at)) {
            $latest[$wid] = [ordered]@{
                state       = [string](Get-Prop $r 'state' '')
                summary     = [string](Get-Prop $r 'summary' '')
                needs       = [string](Get-Prop $r 'needs' '')
                reported_at = $ra
            }
        }
    }
    return $latest
}

# ============================================================================
#  lease panel (parse the res.lease leases dir READ-ONLY)
# ============================================================================

function Get-WaveLeases {
    <#
        Parse every *.lease file in -LeaseDir (lifeorch.res.lease/0.1) into display rows:
          { kind, path, holder, age_s, acquired_at, expires_at, remaining_s, expired, note }
        kind    = the lease's 'resource' (gpu / git / doc:<path>); falls back to the filename stem.
        age_s   = seconds since acquired_at_utc (held-for); remaining_s = seconds until expires_at_utc.
        A partial / unparseable lease (a mid-write file) yields a well-formed row with holder '<writing>' and
        null ages -- never throws. -Now is injectable so ages are deterministic in tests (default UtcNow).
        Sorted gpu, git, doc:*, then other; then by path. Returns @() when the dir is absent/empty.
    #>
    [CmdletBinding()]
    param([string]$LeaseDir, [datetime]$Now = [datetime]::UtcNow)
    if (-not $LeaseDir) { $LeaseDir = (Resolve-WavePaths).LeaseDir }
    if ([string]::IsNullOrWhiteSpace($LeaseDir) -or -not (Test-Path -LiteralPath $LeaseDir -PathType Container)) {
        return @()
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $LeaseDir -Filter '*.lease' -File -ErrorAction SilentlyContinue)) {
        $obj = Read-JsonFileSafe -Path $f.FullName
        if ($null -eq $obj) {
            $rows.Add([pscustomobject]@{
                    kind = '<unknown>'; path = $f.FullName; holder = '<writing>'
                    age_s = $null; acquired_at = ''; expires_at = ''; remaining_s = $null; expired = $false; note = ''
                })
            continue
        }
        $resource = [string](Get-Prop $obj 'resource' '')
        if ([string]::IsNullOrWhiteSpace($resource)) {
            # fall back to the filename stem (Get-LeaseFileName = <safe>-<hash8>.lease)
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $resource = ($stem -replace '-[0-9a-f]{8}$', '')
        }
        $acqRaw = [string](Get-Prop $obj 'acquired_at_utc' '')
        $expRaw = [string](Get-Prop $obj 'expires_at_utc' '')
        $acq = ConvertTo-UtcTime $acqRaw
        $exp = ConvertTo-UtcTime $expRaw
        $ageS = if ($null -ne $acq) { [int][Math]::Round(($Now - $acq).TotalSeconds) } else { $null }
        $remS = if ($null -ne $exp) { [int][Math]::Round(($exp - $Now).TotalSeconds) } else { $null }
        $expired = if ($null -ne $exp) { ($exp -lt $Now) } else { $false }
        $rows.Add([pscustomobject]@{
                kind        = $resource
                path        = $f.FullName
                holder      = [string](Get-Prop $obj 'holder' '')
                age_s       = $ageS
                acquired_at = $acqRaw
                expires_at  = $expRaw
                remaining_s = $remS
                expired     = $expired
                note        = [string](Get-Prop $obj 'note' '')
            })
    }
    $sorted = @($rows.ToArray() | Sort-Object -Property `
        @{ Expression = { Get-LeaseKindRank $_.kind } }, @{ Expression = { [string]$_.path } })
    return $sorted
}

function Get-LeaseKindRank {
    param([string]$Kind)
    $k = ([string]$Kind).ToLowerInvariant()
    if ($k -eq 'gpu') { return 0 }
    if ($k -eq 'git') { return 1 }
    if ($k -like 'doc:*') { return 2 }
    if ($k -eq '<unknown>') { return 9 }
    return 3
}

# ============================================================================
#  Get-WaveState -- the one read that produces the whole dashboard model
# ============================================================================

function Get-WaveState {
    <#
        Read a fan-out wave's live state from its plan dir + the lease dir and return a plain, WinForms-free
        object (the shell renders it; the SelfTest + cloud gate assert it). ZERO side effects: reads only.

          {
            ok, error, plan_id, plan_dir, iteration, title, report_back, max_parallel, created_at,
            dispatch_now (int), queued (int), dispatch_now_ids[], queued_ids[],
            counts { total, done, failed, blocked, running, no_report },
            workers [ { id, lane, gpu, state, summary, updated, needs } ],
            leases  [ { kind, path, holder, age_s, expires_at, remaining_s, expired, note } ],
            ready_for_handoff (bool)
          }

        ready_for_handoff is computed by the SAME rule as Invoke-OrchestrateFanout.ps1 -Action status:
          terminal = done + failed; on_each -> terminal >= 1; on_all -> total > 0 AND terminal == total.
        A missing report for a plan worker yields a well-formed state='unknown' row (counted as no_report),
        never a throw. -Now is injectable for deterministic lease ages.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanDir,
        [string]$LeaseDir,
        [datetime]$Now = [datetime]::UtcNow
    )
    if (-not $LeaseDir) { $LeaseDir = (Resolve-WavePaths).LeaseDir }

    $planFile = Join-Path $PlanDir 'plan.json'
    $plan = Read-JsonFileSafe -Path $planFile
    if ($null -eq $plan) {
        return [pscustomobject]@{
            ok = $false
            error = "plan.json not found or unreadable under: $PlanDir"
            plan_id = ''; plan_dir = $PlanDir; iteration = 0; title = ''; report_back = ''; max_parallel = 0; created_at = ''
            dispatch_now = 0; queued = 0; dispatch_now_ids = @(); queued_ids = @()
            counts = [ordered]@{ total = 0; done = 0; failed = 0; blocked = 0; running = 0; no_report = 0 }
            workers = @()
            leases = @(Get-WaveLeases -LeaseDir $LeaseDir -Now $Now)
            ready_for_handoff = $false
        }
    }

    $reportBack = ([string](Get-Prop $plan 'report_back' 'on_all')).ToLowerInvariant()
    if ($reportBack -ne 'on_each') { $reportBack = 'on_all' }

    $dispatchIds = @(ConvertTo-Array (Get-Prop $plan 'dispatch_now'))
    $queuedIds   = @(ConvertTo-Array (Get-Prop $plan 'queued'))
    $workersRaw  = @(ConvertTo-Array (Get-Prop $plan 'workers'))

    $latest = Get-LatestWorkerReports -PlanDir $PlanDir

    $workers = New-Object System.Collections.Generic.List[object]
    $done = 0; $failed = 0; $blocked = 0; $running = 0; $noReport = 0
    foreach ($w in $workersRaw) {
        $wid = [string](Get-Prop $w 'id' '')
        $state = 'unknown'; $summary = ''; $updated = ''; $needs = ''
        if ($wid -and $latest.ContainsKey($wid)) {
            $st = $latest[$wid]
            $rs = [string]$st.state
            if ($rs) { $state = $rs }
            $summary = [string]$st.summary
            $updated = [string]$st.reported_at
            $needs = [string]$st.needs
        }
        switch ($state) {
            'done' { $done++ }
            'failed' { $failed++ }
            'blocked' { $blocked++ }
            'started' { $running++ }
            'progress' { $running++ }
            default { $noReport++ }
        }
        $workers.Add([pscustomobject]@{
                id      = $wid
                lane    = Get-WorkerLane $w
                gpu     = [bool](Get-Prop $w 'gpu' $false)
                state   = $state
                summary = $summary
                updated = $updated
                needs   = $needs
            })
    }

    $total = $workers.Count
    $terminal = $done + $failed
    $ready = if ($reportBack -eq 'on_each') { $terminal -ge 1 } else { ($total -gt 0) -and ($terminal -eq $total) }

    return [pscustomobject]@{
        ok                = $true
        error             = ''
        plan_id           = [string](Get-Prop $plan 'plan_id' (Split-Path -Leaf $PlanDir))
        plan_dir          = $PlanDir
        iteration         = [int](Get-Prop $plan 'iteration' 0)
        title             = [string](Get-Prop $plan 'title' '')
        report_back       = $reportBack
        max_parallel      = [int](Get-Prop $plan 'max_parallel' 0)
        created_at        = [string](Get-Prop $plan 'created_at_utc' '')
        dispatch_now      = $dispatchIds.Count
        queued            = $queuedIds.Count
        dispatch_now_ids  = $dispatchIds
        queued_ids        = $queuedIds
        counts            = [ordered]@{ total = $total; done = $done; failed = $failed; blocked = $blocked; running = $running; no_report = $noReport }
        workers           = $workers.ToArray()
        leases            = @(Get-WaveLeases -LeaseDir $LeaseDir -Now $Now)
        ready_for_handoff = [bool]$ready
    }
}

# ============================================================================
#  Format-WaveRows -- display rows/strings (padded, for a monospace surface)
# ============================================================================

function Format-Age {
    # Human-friendly duration for an age/remaining in seconds. '-' when null.
    param($Seconds)
    if ($null -eq $Seconds) { return '-' }
    $neg = ($Seconds -lt 0)
    $s = [Math]::Abs([int]$Seconds)
    $txt =
        if ($s -lt 60) { "${s}s" }
        elseif ($s -lt 3600) { "{0}m{1:d2}s" -f [int]($s / 60), ($s % 60) }
        elseif ($s -lt 86400) { "{0}h{1:d2}m" -f [int]($s / 3600), [int](($s % 3600) / 60) }
        else { "{0}d{1:d2}h" -f [int]($s / 86400), [int](($s % 86400) / 3600) }
    if ($neg) { return "-$txt" }
    return $txt
}

function Format-WaveRows {
    <#
        Turn a Get-WaveState object into display strings for a monospace UI (and for the SelfTest / gate to
        assert on). Returns:
          { header_lines[], worker_header, worker_lines[], lease_header, lease_lines[], summary_line, ready_text }
        Pure string work; no WinForms.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)

    $header = New-Object System.Collections.Generic.List[string]
    if (-not [bool](Get-Prop $State 'ok' $false)) {
        $header.Add('NO WAVE LOADED')
        $header.Add('  ' + [string](Get-Prop $State 'error'))
        return [pscustomobject]@{
            header_lines = $header.ToArray(); worker_header = ''; worker_lines = @()
            lease_header = ''; lease_lines = @(); summary_line = 'no plan loaded'; ready_text = 'n/a'
        }
    }

    $counts = Get-Prop $State 'counts'
    $readyText = if ([bool](Get-Prop $State 'ready_for_handoff' $false)) { 'READY FOR HANDOFF' } else { 'not ready' }

    $header.Add('WAVE: ' + [string](Get-Prop $State 'plan_id') + '   (iteration ' + [string](Get-Prop $State 'iteration') + ')')
    $title = [string](Get-Prop $State 'title')
    if ($title) { $header.Add('  ' + (Limit-Text $title 140)) }
    $header.Add('report_back: ' + [string](Get-Prop $State 'report_back') +
        '   dispatch_now: ' + [string](Get-Prop $State 'dispatch_now') +
        '   queued: ' + [string](Get-Prop $State 'queued') +
        '   ready_for_handoff: ' + [string]([bool](Get-Prop $State 'ready_for_handoff')))

    # worker table
    $wh = ('{0,-16} {1,-8} {2,-4} {3,-9} {4}' -f 'ID', 'LANE', 'GPU', 'STATE', 'SUMMARY')
    $wlines = New-Object System.Collections.Generic.List[string]
    foreach ($w in @(Get-Prop $State 'workers')) {
        $gpuTxt = if ([bool](Get-Prop $w 'gpu' $false)) { 'yes' } else { 'no' }
        # NB: wrap the whole (-f ...) in parens -- a bare `$list.Add('fmt' -f a,b,c)` parses the commas as
        # METHOD arguments to .Add(), so -f would see only the first operand and {1}.. would over-run the args.
        $wline = '{0,-16} {1,-8} {2,-4} {3,-9} {4}' -f `
            (Limit-Text (Get-Prop $w 'id') 16), (Limit-Text (Get-Prop $w 'lane') 8), $gpuTxt,
            (Limit-Text (Get-Prop $w 'state') 9), (Limit-Text (Get-Prop $w 'summary') 80)
        [void]$wlines.Add($wline)
    }
    if ($wlines.Count -eq 0) { $wlines.Add('(no workers in this plan)') }

    # lease panel
    $lh = ('{0,-22} {1,-16} {2,-8} {3,-8} {4}' -f 'RESOURCE', 'HOLDER', 'HELD', 'REMAIN', 'EXPIRES')
    $llines = New-Object System.Collections.Generic.List[string]
    foreach ($l in @(Get-Prop $State 'leases')) {
        $exp = if ([bool](Get-Prop $l 'expired' $false)) { '(EXPIRED) ' } else { '' }
        $lline = '{0,-22} {1,-16} {2,-8} {3,-8} {4}' -f `
            (Limit-Text (Get-Prop $l 'kind') 22), (Limit-Text (Get-Prop $l 'holder') 16),
            (Format-Age (Get-Prop $l 'age_s')), (Format-Age (Get-Prop $l 'remaining_s')),
            ($exp + [string](Get-Prop $l 'expires_at'))
        [void]$llines.Add($lline)
    }
    if ($llines.Count -eq 0) { $llines.Add('(no active leases)') }

    $summary = ('workers: ' + [string](Get-Prop $counts 'total') +
        '   done: ' + [string](Get-Prop $counts 'done') +
        '   running: ' + [string](Get-Prop $counts 'running') +
        '   blocked: ' + [string](Get-Prop $counts 'blocked') +
        '   failed: ' + [string](Get-Prop $counts 'failed') +
        '   no_report: ' + [string](Get-Prop $counts 'no_report') +
        '   ->  ' + $readyText)

    return [pscustomobject]@{
        header_lines  = $header.ToArray()
        worker_header = $wh
        worker_lines  = $wlines.ToArray()
        lease_header  = $lh
        lease_lines   = $llines.ToArray()
        summary_line  = $summary
        ready_text    = $readyText
    }
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Prop, ConvertTo-Array, Limit-Text, ConvertTo-UtcTime, Read-JsonFileSafe, `
    Resolve-WavePaths, Get-WavePlans, Get-WorkerLane, Get-LatestWorkerReports, `
    Get-WaveLeases, Get-LeaseKindRank, Get-WaveState, Format-Age, Format-WaveRows
