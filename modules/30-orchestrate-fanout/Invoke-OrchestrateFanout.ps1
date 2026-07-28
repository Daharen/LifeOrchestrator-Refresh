#requires -Version 7.0
<#
.SYNOPSIS
  orchestrate.fanout -- the fan-out orchestrator scaffolding (Life Orchestrator, contract v0.2).
  The deterministic coordination layer for N parallel worker Cowork sessions (D-0050/D-0051),
  built ON TOP OF res.lease (#29). A skill cannot spawn Claude sessions; it produces + manages
  every deterministic artifact around them.
.DESCRIPTION
  One action per invocation:
    - plan    : turn a list of worker unit-specs into a collision-safe fan-out plan. For each worker it
                assigns the ordered lease set (acquire-order gpu -> git -> doc:<path>, release reverse) and
                the exact res.lease acquire/release command lines; computes dispatch_now (trial of
                -MaxParallel, default 2, clamped to at most ONE gpu worker) vs. queued; flags doc-ownership
                contention (>1 worker editing a doc) + gpu serialization; emits one worker prompt per worker
                + exactly one Nicholas check-in prompt (+ the report-back cadence); persists the plan. An
                optional read-only res.lease `list` PREFLIGHT snapshots current holdings and warns on a live
                conflict (skips cleanly if res.lease is not resolvable / -NoPreflight).
    - report  : a worker (or the orchestrator on its behalf) records a progress report
                {state: started|progress|blocked|done|failed, summary, needs}. One file per report (so N
                workers append concurrently with no contention -> parallel_safe).
    - status  : the roster of workers + each worker's latest report state + ready_for_handoff per the cadence
                (on_all = every worker terminal; on_each = >=1 terminal).
    - handoff : assemble the final handoff -- a summary, the next-iteration worker prompts (from -NextWorkersJson
                or the same plan's workers), exactly one check-in prompt, and a Verification Console packet
                (lifeorch.verification.packet/0.1: one run_module/human_action item per worker output) that is
                the orchestrator's human-I/O.
    - list    : every persisted plan in the plans dir.

  DETERMINISTIC + a tool, not a model: confidence:null, empty model_provenance, NOT a review-queue producer.
  Pure PowerShell + .NET -- no external binary / Python / model / models.json change. parallel_safe:TRUE
  (report writes are per-file; plan/handoff are per-invocation). batch:false, streaming:false. Emits one
  lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes fanout.json/fanout.md + prompts.
  Exits 0 whenever a valid envelope is produced.

  Plans live in a SHARED dir every process resolves identically: -PlansDir, else $env:LIFEORCH_FANOUT_DIR,
  else $PSScriptRoot/runtime/plans. Each plan = plans/<plan_id>/plan.json + reports/<worker>.<guid8>.json.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-OrchestrateFanout.ps1 -Action plan -Title "iter 5" -WorkersJson '[{"id":"w1","unit":"build gen.image tier","gpu":true},{"id":"w2","unit":"doc.io regex mode","docs":["CURRENT_STATE.md"]}]'
  pwsh -NoProfile -File .\Invoke-OrchestrateFanout.ps1 -Action report -PlanId <id> -WorkerId w1 -State done -Summary "shipped"
  pwsh -NoProfile -File .\Invoke-OrchestrateFanout.ps1 -InputsJson '{"action":"handoff","plan_id":"<id>"}'
#>
[CmdletBinding()]
param(
    [string]$Action,
    [string]$Title,
    [int]$Iteration = 1,
    [int]$MaxParallel = 2,
    [string]$ReportBack = 'on_all',
    [string]$WorkersJson,
    [string]$NextWorkersJson,
    [string]$PlanId,
    [string]$WorkerId,
    [string]$State,
    [string]$Summary,
    [string]$Needs,
    [string]$PlansDir,
    [string]$LeaseDir,
    [string]$ResLeasePath,
    [string]$PwshPath,
    [switch]$NoPreflight,
    [int]$LeaseTtlSeconds = 1800,
    [double]$LeaseWaitSeconds = 900,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'orchestrate.fanout'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$PLAN_SCHEMA = 'lifeorch.fanout.plan/0.1'
$REPORT_SCHEMA = 'lifeorch.fanout.report/0.1'
$PACKET_SCHEMA = 'lifeorch.verification.packet/0.1'
$TERMINAL = @('done', 'failed')
$VALID_STATES = @('started', 'progress', 'blocked', 'done', 'failed')
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[orchestrate.fanout] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { $v = $o.$n; if ($null -ne $v) { return $v } } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-', '').ToLowerInvariant() } finally { $s.Dispose() }
}
function Fail([string]$code, [string]$msg) { throw [PSCustomObject]@{ code = $code; message = $msg; retryable = $false } }
function Safe-Name([string]$s) {
    $x = ($s -replace '[^A-Za-z0-9._-]', '_')
    if ($x.Length -gt 64) { $x = $x.Substring(0, 64) }
    return $x
}
function Write-TextAtomic([string]$path, [string]$text) {
    $tmp = "$path.tmp-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    [System.IO.File]::WriteAllText($tmp, $text, $utf8)
    [System.IO.File]::Move($tmp, $path, $true)
}
function Resolve-ChildPwsh {
    if (-not [string]::IsNullOrWhiteSpace($script:PwshPath) -and (Test-Path -LiteralPath $script:PwshPath)) { return $script:PwshPath }
    $c1 = Join-Path $PSHOME 'pwsh.exe'; if (Test-Path -LiteralPath $c1) { return $c1 }
    $c2 = Join-Path $PSHOME 'pwsh'; if (Test-Path -LiteralPath $c2) { return $c2 }
    return 'pwsh'
}

# ---- worker spec -> normalized ordered record ----
function Normalize-Worker($w, [int]$idx) {
    $id = [string](Prop $w 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { $id = "w$($idx + 1)" }
    $docsList = New-Object System.Collections.Generic.List[string]
    if (Has $w 'docs') { foreach ($d in @($w.docs)) { $ds = [string]$d; if (-not [string]::IsNullOrWhiteSpace($ds)) { $docsList.Add($ds) } } }
    $needsGit = $true
    if (Has $w 'needs_git') { $needsGit = [bool]$w.needs_git }
    return [ordered]@{
        id         = $id
        safe_id    = (Safe-Name $id)
        label      = [string](Prop $w 'label' $id)
        unit       = [string](Prop $w 'unit' '')
        gpu        = [bool](Prop $w 'gpu' $false)
        docs       = $docsList.ToArray()
        needs_git  = $needsGit
        skill_id   = [string](Prop $w 'skill_id' '')
        skill_dir  = [string](Prop $w 'skill_dir' '')
        inputs     = (Prop $w 'inputs' $null)
        notes      = [string](Prop $w 'notes' '')
    }
}
# ordered lease set: gpu -> git -> doc:<path> (deadlock-avoidance acquire order; release reverse)
function Get-WorkerLeases($w) {
    $L = New-Object System.Collections.Generic.List[string]
    if ($w.gpu) { $L.Add('gpu') }
    if ($w.needs_git) { $L.Add('git') }
    foreach ($d in ($w.docs | Sort-Object)) { $L.Add("doc:$d") }
    return $L.ToArray()
}
function Q([string]$s) { return '"' + ($s -replace '"', '\"') + '"' }
function Get-LeaseArgs {
    $a = " -TtlSeconds $script:LeaseTtlSeconds -WaitSeconds $script:LeaseWaitSeconds"
    if (-not [string]::IsNullOrWhiteSpace($script:LeaseDir)) { $a += " -LeaseDir $(Q $script:LeaseDir)" }
    return $a
}
function Get-AcquireCommands($w, [string[]]$leases) {
    $c = New-Object System.Collections.Generic.List[string]
    foreach ($r in $leases) {
        $c.Add("pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource $(Q $r) -Holder $(Q $w.id)$(Get-LeaseArgs)")
    }
    return $c.ToArray()
}
function Get-ReleaseCommands($w, [string[]]$leases) {
    $c = New-Object System.Collections.Generic.List[string]
    $rev = @($leases); [array]::Reverse($rev)
    foreach ($r in $rev) {
        $rel = "pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource $(Q $r) -Holder $(Q $w.id)"
        if (-not [string]::IsNullOrWhiteSpace($script:LeaseDir)) { $rel += " -LeaseDir $(Q $script:LeaseDir)" }
        $c.Add($rel)
    }
    return $c.ToArray()
}
function Get-ReportCommand([string]$planId, $w, [string]$state) {
    $r = "pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId $(Q $planId) -WorkerId $(Q $w.id) -State $state -Summary $(Q '<one line: what you did>')"
    if (-not [string]::IsNullOrWhiteSpace($script:PlansDir)) { $r += " -PlansDir $(Q $script:PlansDir)" }
    return $r
}

function Build-WorkerPrompt([string]$planId, [int]$iter, $w, [string[]]$leases, [string[]]$acq, [string[]]$rel, [string]$reportBack) {
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add("# Fan-out worker prompt -- worker " + $w.id + " (plan " + $planId + ", iteration " + $iter + ")")
    $L.Add("")
    $L.Add("You are one worker in a fan-out build of Life Orchestrator, coordinated by an orchestrator instance.")
    $L.Add("First read core-docs/START_HERE.md and core-docs/HANDOFF.md, then the docs they route you to.")
    $L.Add("")
    $L.Add("## Your scoped unit")
    $L.Add(($w.unit))
    if (-not [string]::IsNullOrWhiteSpace($w.notes)) { $L.Add(""); $L.Add("Notes: " + $w.notes) }
    $L.Add("")
    $L.Add("## Resource leases (collision safety -- res.lease #29)")
    if ($leases.Count -eq 0) {
        $L.Add("This worker declares no exclusive resources. Still take the `git` lease before you commit.")
    } else {
        $L.Add("Acquire these BEFORE the work they guard, in THIS order (gpu -> git -> doc); each blocks up to the wait:")
        $L.Add('```')
        foreach ($a in $acq) { $L.Add($a) }
        $L.Add('```')
        $L.Add("Acquire returns a lease_id; keep each one. Renew before its TTL if the work runs long.")
        $L.Add("Release in REVERSE order when the guarded work is done, or immediately if you block/abort:")
        $L.Add('```')
        foreach ($r in $rel) { $L.Add($r) }
        $L.Add('```')
        $L.Add("(Release-by-holder is shown; releasing with the exact `-LeaseId` is stronger.)")
    }
    $L.Add("")
    $L.Add("## Report back (cadence: " + $reportBack + ")")
    $L.Add("Report at least once when you finish or block. Run:")
    $L.Add('```')
    $L.Add((Get-ReportCommand $planId $w 'done'))
    $L.Add('```')
    $L.Add("Use -State progress for interim updates, -State blocked with -Needs '<what you need>' if stuck, -State failed if you cannot finish.")
    $L.Add("")
    $L.Add("## Ship + stop")
    $L.Add("Ship your unit through the job-runner (dev.ship). Do ONE scoped unit. Do NOT touch another worker's")
    $L.Add("module, and do NOT edit the shared core-docs the orchestrator owns -- report and let the orchestrator")
    $L.Add("mirror them (it serialises doc + git writes via res.lease). Then release your leases and report done.")
    if (-not [string]::IsNullOrWhiteSpace($w.skill_id)) {
        $L.Add("")
        $L.Add("Your output (" + $w.skill_id + ") will become a Verification Console item Nicholas audits.")
    }
    $L.Add("")
    return (($L.ToArray() -join "`n") + "`n")
}

function Build-CheckInPrompt([string]$planId, [int]$iter, [string]$title, [string[]]$dispatchNow, [string[]]$queued, $conflicts, [string]$reportBack) {
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add("# Fan-out check-in for Nicholas -- plan " + $planId + " (iteration " + $iter + ")")
    if (-not [string]::IsNullOrWhiteSpace($title)) { $L.Add(""); $L.Add($title) }
    $L.Add("")
    $L.Add("Dispatch now (" + $dispatchNow.Count + "): " + ($dispatchNow -join ", "))
    if ($queued.Count -gt 0) { $L.Add("Queued (start as a running one finishes): " + ($queued -join ", ")) }
    $L.Add("")
    $L.Add("1. Start a new Cowork session for each 'dispatch now' worker and paste its prompt")
    $L.Add("   (from workers/worker-<id>.prompt.md).")
    if ($reportBack -eq 'on_each') {
        $L.Add("2. As EACH worker finishes, run:  -Action status -PlanId " + $planId + "  -- when ready_for_handoff is true,")
        $L.Add("   run:  -Action handoff -PlanId " + $planId + "  and verify the emitted packet in the Verification Console.")
    } else {
        $L.Add("2. When ALL workers have reported done/failed, run:  -Action status -PlanId " + $planId)
        $L.Add("   then:  -Action handoff -PlanId " + $planId + "  and verify the emitted packet in the Verification Console.")
    }
    $L.Add("3. Start the queued workers as slots free up.")
    if ($conflicts.gpu_serialized.Count -gt 0) {
        $L.Add("")
        $L.Add("GPU note: only ONE of {" + ($conflicts.gpu_serialized -join ", ") + "} may run at a time (single GPU lease).")
    }
    if ($conflicts.doc_contention.Count -gt 0) {
        $L.Add("")
        $L.Add("Doc-ownership note: these docs are claimed by more than one worker -- they serialise on doc:<path>,")
        $L.Add("or re-scope so the orchestrator owns the shared-doc edit:")
        foreach ($dc in $conflicts.doc_contention) { $L.Add("  - " + $dc.doc + " : " + (($dc.workers) -join ", ")) }
    }
    $L.Add("")
    return (($L.ToArray() -join "`n") + "`n")
}

# read the latest report state per worker (worker_id -> {state, summary, reported_at})
function Get-WorkerStates([string]$planDir) {
    $latest = @{}
    $reportsDir = Join-Path $planDir 'reports'
    if (Test-Path -LiteralPath $reportsDir -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $reportsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $r = $null
            try { $r = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
            if ($null -eq $r) { continue }
            $wid = [string](Prop $r 'worker_id' '')
            if ([string]::IsNullOrWhiteSpace($wid)) { continue }
            $ra = [string](Prop $r 'reported_at_utc' '')
            if ((-not $latest.ContainsKey($wid)) -or ($ra -gt [string]$latest[$wid].reported_at)) {
                $latest[$wid] = [ordered]@{ state = [string](Prop $r 'state' ''); summary = [string](Prop $r 'summary' ''); reported_at = $ra }
            }
        }
    }
    return $latest
}
function Resolve-PlanDir([string]$plansDir, [string]$planId) {
    if ([string]::IsNullOrWhiteSpace($planId)) { Fail 'missing_parameter' "$($script:Action) needs a plan_id" }
    $pd = Join-Path $plansDir (Safe-Name $planId)
    if (-not (Test-Path -LiteralPath (Join-Path $pd 'plan.json') -PathType Leaf)) { Fail 'plan_not_found' "no plan '$planId' in $plansDir" }
    return $pd
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { Fail 'invalid_inputs_json' '-InputsJson is not valid JSON' }
    }
    if ($null -ne $p) {
        if ((Has $p 'action')          -and -not $bound.ContainsKey('Action'))          { $Action = [string]$p.action }
        if ((Has $p 'title')           -and -not $bound.ContainsKey('Title'))           { $Title = [string]$p.title }
        if ((Has $p 'iteration')       -and -not $bound.ContainsKey('Iteration'))       { $Iteration = [int]$p.iteration }
        if ((Has $p 'max_parallel')    -and -not $bound.ContainsKey('MaxParallel'))     { $MaxParallel = [int]$p.max_parallel }
        if ((Has $p 'report_back')     -and -not $bound.ContainsKey('ReportBack'))      { $ReportBack = [string]$p.report_back }
        if ((Has $p 'plan_id')         -and -not $bound.ContainsKey('PlanId'))          { $PlanId = [string]$p.plan_id }
        if ((Has $p 'worker_id')       -and -not $bound.ContainsKey('WorkerId'))        { $WorkerId = [string]$p.worker_id }
        if ((Has $p 'state')           -and -not $bound.ContainsKey('State'))           { $State = [string]$p.state }
        if ((Has $p 'summary')         -and -not $bound.ContainsKey('Summary'))         { $Summary = [string]$p.summary }
        if ((Has $p 'needs')           -and -not $bound.ContainsKey('Needs'))           { $Needs = [string]$p.needs }
        if ((Has $p 'plans_dir')       -and -not $bound.ContainsKey('PlansDir'))        { $PlansDir = [string]$p.plans_dir }
        if ((Has $p 'lease_dir')       -and -not $bound.ContainsKey('LeaseDir'))        { $LeaseDir = [string]$p.lease_dir }
        if ((Has $p 'res_lease_path')  -and -not $bound.ContainsKey('ResLeasePath'))    { $ResLeasePath = [string]$p.res_lease_path }
        if ((Has $p 'pwsh_path')       -and -not $bound.ContainsKey('PwshPath'))        { $PwshPath = [string]$p.pwsh_path }
        if ((Has $p 'lease_ttl_seconds') -and -not $bound.ContainsKey('LeaseTtlSeconds')) { $LeaseTtlSeconds = [int]$p.lease_ttl_seconds }
        if ((Has $p 'lease_wait_seconds') -and -not $bound.ContainsKey('LeaseWaitSeconds')) { $LeaseWaitSeconds = [double]$p.lease_wait_seconds }
    }
    $noPre = [bool]$NoPreflight
    if ($null -ne $p -and (Has $p 'no_preflight') -and -not $bound.ContainsKey('NoPreflight')) { $noPre = [bool]$p.no_preflight }

    if ([string]::IsNullOrWhiteSpace($Action)) { Fail 'missing_parameter' 'action is required (plan|report|status|handoff|list)' }
    $Action = $Action.ToLowerInvariant()
    if (@('plan', 'report', 'status', 'handoff', 'list') -notcontains $Action) { Fail 'invalid_action' "action must be plan|report|status|handoff|list (got '$Action')" }
    if ($ReportBack -notin @('on_all', 'on_each')) { $ReportBack = 'on_all' }
    if ($MaxParallel -lt 1) { $MaxParallel = 1 }
    if ($LeaseTtlSeconds -lt 1) { $LeaseTtlSeconds = 1 }
    if ($LeaseWaitSeconds -lt 0) { $LeaseWaitSeconds = 0 }

    # ---- resolve plans dir ----
    if ([string]::IsNullOrWhiteSpace($PlansDir)) {
        $PlansDir = $env:LIFEORCH_FANOUT_DIR
        if ([string]::IsNullOrWhiteSpace($PlansDir)) { $PlansDir = Join-Path $PSScriptRoot 'runtime/plans' }
    }
    New-Item -ItemType Directory -Path $PlansDir -Force | Out-Null
    $PlansDir = (Resolve-Path -LiteralPath $PlansDir).Path

    # ---- worker specs (WorkersJson wins over InputsJson.workers) ----
    $workerSpecs = @()
    if (-not [string]::IsNullOrWhiteSpace($WorkersJson)) {
        try { $workerSpecs = @($WorkersJson | ConvertFrom-Json) } catch { Fail 'invalid_workers_json' '-WorkersJson is not valid JSON' }
    } elseif ($null -ne $p -and (Has $p 'workers')) { $workerSpecs = @($p.workers) }
    $nextSpecs = @()
    if (-not [string]::IsNullOrWhiteSpace($NextWorkersJson)) {
        try { $nextSpecs = @($NextWorkersJson | ConvertFrom-Json) } catch { Fail 'invalid_workers_json' '-NextWorkersJson is not valid JSON' }
    } elseif ($null -ne $p -and (Has $p 'next_workers')) { $nextSpecs = @($p.next_workers) }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    switch ($Action) {
        'plan' {
            if ($workerSpecs.Count -lt 1) { Fail 'missing_parameter' 'plan needs a non-empty workers array' }
            # normalize + uniqueness
            $workers = New-Object System.Collections.Generic.List[object]
            $seen = New-Object System.Collections.Generic.HashSet[string]
            $idx = 0
            foreach ($ws in $workerSpecs) {
                $w = Normalize-Worker $ws $idx; $idx++
                if (-not $seen.Add([string]$w.id)) { Fail 'invalid_workers' "duplicate worker id: $($w.id)" }
                $leases = Get-WorkerLeases $w
                $w['leases'] = $leases
                $w['acquire_commands'] = Get-AcquireCommands $w $leases
                $w['release_commands'] = Get-ReleaseCommands $w $leases
                if ([string]::IsNullOrWhiteSpace($w.unit)) { $warnings.Add("worker $($w.id) has an empty unit") }
                $workers.Add($w)
            }
            $planId = "fo-$Iteration-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
            $planDir = Join-Path $PlansDir $planId
            New-Item -ItemType Directory -Path (Join-Path $planDir 'reports') -Force | Out-Null

            # schedule: dispatch_now = up to MaxParallel, at most one gpu worker; rest queued
            $dispatch = New-Object System.Collections.Generic.List[string]
            $queued = New-Object System.Collections.Generic.List[string]
            $gpuUsed = $false
            foreach ($w in $workers) {
                if ($dispatch.Count -lt $MaxParallel -and (-not ($w.gpu -and $gpuUsed))) {
                    $dispatch.Add([string]$w.id); if ($w.gpu) { $gpuUsed = $true }
                } else { $queued.Add([string]$w.id) }
            }
            # conflicts
            $gpuIds = New-Object System.Collections.Generic.List[string]
            foreach ($w in $workers) { if ($w.gpu) { $gpuIds.Add([string]$w.id) } }
            $gpuSerialized = @(); if ($gpuIds.Count -gt 1) { $gpuSerialized = $gpuIds.ToArray() }
            $docMap = @{}
            foreach ($w in $workers) { foreach ($d in $w.docs) { if (-not $docMap.ContainsKey($d)) { $docMap[$d] = (New-Object System.Collections.Generic.List[string]) }; $docMap[$d].Add([string]$w.id) } }
            $docContention = New-Object System.Collections.Generic.List[object]
            foreach ($d in ($docMap.Keys | Sort-Object)) { if ($docMap[$d].Count -gt 1) { $docContention.Add([ordered]@{ doc = $d; workers = $docMap[$d].ToArray() }) } }
            $conflicts = [ordered]@{ gpu_serialized = $gpuSerialized; doc_contention = $docContention.ToArray() }

            # preflight: read-only res.lease list snapshot (composition; skip cleanly if unresolvable)
            $preflight = [ordered]@{ ran = $false; held = @(); note = $null }
            if (-not $noPre) {
                $rlp = $ResLeasePath
                if ([string]::IsNullOrWhiteSpace($rlp)) {
                    $repoGuess = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
                    $rlp = Join-Path $repoGuess 'modules/29-resource-lease/Invoke-ResLease.ps1'
                }
                if (Test-Path -LiteralPath $rlp -PathType Leaf) {
                    try {
                        $childPwsh = Resolve-ChildPwsh
                        $rlArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $rlp, '-Action', 'list')
                        if (-not [string]::IsNullOrWhiteSpace($LeaseDir)) { $rlArgs += @('-LeaseDir', $LeaseDir) }
                        $errf = [System.IO.Path]::GetTempFileName()
                        $rlOut = & $childPwsh @rlArgs 2> $errf
                        Remove-Item -LiteralPath $errf -Force -ErrorAction SilentlyContinue
                        $rlEnv = $null; try { $rlEnv = ($rlOut | Out-String).Trim() | ConvertFrom-Json } catch { }
                        $heldList = New-Object System.Collections.Generic.List[string]
                        if ($null -ne $rlEnv -and (Has $rlEnv 'result') -and (Has $rlEnv.result 'leases')) {
                            foreach ($l in @($rlEnv.result.leases)) { if ((Prop $l 'held' $false) -eq $true) { $heldList.Add([string](Prop $l 'resource' '')) } }
                            $preflight.ran = $true; $preflight.held = $heldList.ToArray()
                        } else { $preflight.note = 'res.lease list returned no parseable leases' }
                    } catch { $preflight.note = "preflight error: $($_.Exception.Message)" }
                } else { $preflight.note = "res.lease not found at $rlp; preflight skipped" }
            } else { $preflight.note = 'preflight disabled' }
            # warn on live conflicts
            if ($preflight.ran -and @($preflight.held).Count -gt 0) {
                $heldSet = @($preflight.held)
                foreach ($w in $workers) { foreach ($r in $w.leases) { if ($heldSet -contains $r) { $warnings.Add("resource '$r' (needed by worker $($w.id)) is currently held live") } } }
            }

            # emit worker prompts
            $workersDir = Join-Path $invDir 'workers'
            New-Item -ItemType Directory -Path $workersDir -Force | Out-Null
            foreach ($w in $workers) {
                $txt = Build-WorkerPrompt $planId $Iteration $w $w.leases $w.acquire_commands $w.release_commands $ReportBack
                $pp = Join-Path $workersDir ("worker-" + $w.safe_id + ".prompt.md")
                Write-TextAtomic $pp $txt
                $w['prompt_path'] = $pp
            }
            # emit the single Nicholas check-in prompt
            $checkTxt = Build-CheckInPrompt $planId $Iteration $Title $dispatch.ToArray() $queued.ToArray() $conflicts $ReportBack
            $checkPath = Join-Path $invDir 'check-in.prompt.md'
            Write-TextAtomic $checkPath $checkTxt

            # persist the plan
            $planObj = [ordered]@{
                schema = $PLAN_SCHEMA; plan_id = $planId; iteration = $Iteration; title = $Title
                max_parallel = $MaxParallel; report_back = $ReportBack; created_at_utc = $startedAt.ToString('o')
                lease_ttl_seconds = $LeaseTtlSeconds; lease_wait_seconds = $LeaseWaitSeconds; lease_dir = $LeaseDir
                workers = ($workers.ToArray()); dispatch_now = $dispatch.ToArray(); queued = $queued.ToArray()
                conflicts = $conflicts
            }
            Write-TextAtomic (Join-Path $planDir 'plan.json') ($planObj | ConvertTo-Json -Depth 20)

            # result (a slimmed worker view)
            $wOut = New-Object System.Collections.Generic.List[object]
            foreach ($w in $workers) {
                $wOut.Add([ordered]@{
                    id = $w.id; gpu = $w.gpu; docs = $w.docs; leases = $w.leases
                    acquire_commands = $w.acquire_commands; release_commands = $w.release_commands; prompt_path = $w.prompt_path
                })
            }
            $result = [ordered]@{
                action = 'plan'; plan_id = $planId; iteration = $Iteration; title = $Title
                max_parallel = $MaxParallel; report_back = $ReportBack
                workers = $wOut.ToArray(); dispatch_now = $dispatch.ToArray(); queued = $queued.ToArray()
                conflicts = $conflicts; preflight = $preflight
                check_in_prompt_path = $checkPath; plan_dir = $planDir
            }
            $normInputs = [ordered]@{ action = 'plan'; iteration = $Iteration; worker_ids = @($workers | ForEach-Object { [string]$_.id }) }
            Write-Diag "plan $planId workers=$($workers.Count) dispatch_now=$($dispatch.Count) queued=$($queued.Count) gpu_serialized=$($gpuSerialized.Count) doc_contention=$($docContention.Count)"
        }
        'report' {
            if ([string]::IsNullOrWhiteSpace($WorkerId)) { Fail 'missing_parameter' 'report needs a worker_id' }
            if ([string]::IsNullOrWhiteSpace($State)) { Fail 'missing_parameter' 'report needs a state (started|progress|blocked|done|failed)' }
            $State = $State.ToLowerInvariant()
            if ($VALID_STATES -notcontains $State) { Fail 'invalid_state' "state must be started|progress|blocked|done|failed (got '$State')" }
            $planDir = Resolve-PlanDir $PlansDir $PlanId
            $reportsDir = Join-Path $planDir 'reports'
            New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
            $rep = [ordered]@{
                schema = $REPORT_SCHEMA; plan_id = $PlanId; worker_id = $WorkerId; state = $State
                summary = $(if ($null -ne $Summary) { $Summary } else { '' }); needs = $(if ($null -ne $Needs) { $Needs } else { '' })
                reported_at_utc = ([DateTime]::UtcNow).ToString('o')
            }
            $rf = Join-Path $reportsDir ((Safe-Name $WorkerId) + '.' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
            Write-TextAtomic $rf ($rep | ConvertTo-Json -Depth 8)
            $result = [ordered]@{ action = 'report'; plan_id = $PlanId; worker_id = $WorkerId; state = $State; recorded = $true; report_file = $rf }
            $normInputs = [ordered]@{ action = 'report'; plan_id = $PlanId; worker_id = $WorkerId; state = $State }
            Write-Diag "report plan=$PlanId worker=$WorkerId state=$State"
        }
        'status' {
            $planDir = Resolve-PlanDir $PlansDir $PlanId
            $planObj = Get-Content -LiteralPath (Join-Path $planDir 'plan.json') -Raw | ConvertFrom-Json
            $latest = Get-WorkerStates $planDir
            $wStates = New-Object System.Collections.Generic.List[object]
            $done = 0; $failed = 0; $blocked = 0; $running = 0; $noReport = 0
            foreach ($w in @($planObj.workers)) {
                $wid = [string](Prop $w 'id' '')
                $st = 'no_report'; $sum = ''; $ra = $null
                if ($latest.ContainsKey($wid)) { $st = [string]$latest[$wid].state; $sum = [string]$latest[$wid].summary; $ra = [string]$latest[$wid].reported_at }
                switch ($st) {
                    'done' { $done++ } 'failed' { $failed++ } 'blocked' { $blocked++ }
                    'started' { $running++ } 'progress' { $running++ } default { $noReport++ }
                }
                $wStates.Add([ordered]@{ id = $wid; state = $st; last_summary = $sum; reported_at = $ra })
            }
            $total = @($planObj.workers).Count
            $terminal = $done + $failed
            $rb = [string](Prop $planObj 'report_back' 'on_all')
            $ready = if ($rb -eq 'on_each') { $terminal -ge 1 } else { ($total -gt 0) -and ($terminal -eq $total) }
            $result = [ordered]@{
                action = 'status'; plan_id = [string]$planObj.plan_id; iteration = [int](Prop $planObj 'iteration' 1); report_back = $rb
                workers = $wStates.ToArray()
                counts = [ordered]@{ total = $total; done = $done; failed = $failed; blocked = $blocked; running = $running; no_report = $noReport }
                ready_for_handoff = [bool]$ready
            }
            $normInputs = [ordered]@{ action = 'status'; plan_id = $PlanId }
            Write-Diag "status plan=$PlanId done=$done failed=$failed blocked=$blocked running=$running no_report=$noReport ready=$ready"
        }
        'handoff' {
            $planDir = Resolve-PlanDir $PlansDir $PlanId
            $planObj = Get-Content -LiteralPath (Join-Path $planDir 'plan.json') -Raw | ConvertFrom-Json
            $latest = Get-WorkerStates $planDir
            $iter = [int](Prop $planObj 'iteration' 1)
            $rb = [string](Prop $planObj 'report_back' 'on_all')
            $nextIter = $iter + 1

            # verification packet: one item per worker output
            $items = New-Object System.Collections.Generic.List[object]
            $sumLines = New-Object System.Collections.Generic.List[string]
            $ci = 0
            foreach ($w in @($planObj.workers)) {
                $ci++
                $wid = [string](Prop $w 'id' '')
                $st = 'no_report'; $sum = ''
                if ($latest.ContainsKey($wid)) { $st = [string]$latest[$wid].state; $sum = [string]$latest[$wid].summary }
                $sumLines.Add("- " + $wid + " [" + $st + "]" + $(if ($sum) { ": " + $sum } else { "" }))
                $skillId = [string](Prop $w 'skill_id' '')
                $skillDir = [string](Prop $w 'skill_dir' '')
                $expected = $(if ($sum) { $sum } else { "worker " + $wid + " reported " + $st })
                if (-not [string]::IsNullOrWhiteSpace($skillId) -and -not [string]::IsNullOrWhiteSpace($skillDir)) {
                    $it = [ordered]@{
                        id = $wid; kind = 'run_module'; title = "Verify worker " + $wid + " (" + $skillId + ")"
                        skill_id = $skillId; skill_dir = $skillDir; inputs_json = (Prop $w 'inputs' ([ordered]@{}))
                        expected = $expected
                        checklist = @('status == ok', 'the worker output matches its scoped unit')
                    }
                } else {
                    $it = [ordered]@{
                        id = $wid; kind = 'human_action'; title = "Verify worker " + $wid
                        action_text = "Review what worker " + $wid + " produced for: " + [string](Prop $w 'unit' '') + ". Reported state: " + $st + "."
                        expected = $expected
                        checklist = @('the worker completed its scoped unit', 'no shared-doc or cross-worker collision')
                    }
                }
                $items.Add($it)
            }
            $packet = [ordered]@{
                schema = $PACKET_SCHEMA; packet_id = ("vp-" + [string]$planObj.plan_id + "-i" + $iter)
                title = ("Fan-out " + [string]$planObj.plan_id + " iteration " + $iter + " -- verify worker outputs")
                created_by = 'claude'; created_at_utc = $startedAt.ToString('o'); report_back = $rb
                intro = 'Run each run_module item locally through Invoke-Skill.ps1, work the checklist + overall verdict, and export the result.'
                items = $items.ToArray()
            }
            $packetPath = Join-Path $invDir 'verification-packet.json'
            Write-TextAtomic $packetPath ($packet | ConvertTo-Json -Depth 20)

            # next-iteration worker prompts (from next_workers, else re-emit this plan's workers as a template)
            $nextUsed = $nextSpecs
            $fromTemplate = $false
            if (@($nextUsed).Count -lt 1) { $nextUsed = @($planObj.workers); $fromTemplate = $true }
            $nextDir = Join-Path $invDir 'next-workers'
            New-Item -ItemType Directory -Path $nextDir -Force | Out-Null
            $nextPaths = New-Object System.Collections.Generic.List[string]
            $nidx = 0
            foreach ($ns in $nextUsed) {
                $nw = Normalize-Worker $ns $nidx; $nidx++
                $nl = Get-WorkerLeases $nw
                $na = Get-AcquireCommands $nw $nl
                $nr = Get-ReleaseCommands $nw $nl
                $txt = Build-WorkerPrompt ([string]$planObj.plan_id) $nextIter $nw $nl $na $nr $rb
                $np = Join-Path $nextDir ("worker-" + $nw.safe_id + ".prompt.md")
                Write-TextAtomic $np $txt
                $nextPaths.Add($np)
            }

            # one check-in prompt for the next iteration
            $L = New-Object System.Collections.Generic.List[string]
            $L.Add("# Fan-out handoff -- plan " + [string]$planObj.plan_id + " -> iteration " + $nextIter)
            $L.Add("")
            $L.Add("Iteration " + $iter + " results:")
            foreach ($s in $sumLines) { $L.Add($s) }
            $L.Add("")
            $L.Add("1. Verify iteration " + $iter + " in the Verification Console: load verification-packet.json,")
            $L.Add("   run each run_module item through Invoke-Skill.ps1, and export the result.")
            $L.Add("2. Iteration " + $nextIter + " prompts are ready in next-workers/ (" + $nextPaths.Count + " worker(s)" + $(if ($fromTemplate) { ", re-emitted from this plan as a template -- edit before dispatch" } else { "" }) + ").")
            $L.Add("   Persist the next plan with:  -Action plan -Iteration " + $nextIter + " -WorkersJson '<next specs>'  then dispatch per its check-in.")
            $L.Add("")
            $handoffCheckTxt = ($L.ToArray() -join "`n") + "`n"
            $handoffCheckPath = Join-Path $invDir 'check-in.prompt.md'
            Write-TextAtomic $handoffCheckPath $handoffCheckTxt

            $summaryText = ($sumLines.ToArray() -join "`n")
            $handoffObj = [ordered]@{
                schema = 'lifeorch.fanout.handoff/0.1'; plan_id = [string]$planObj.plan_id; from_iteration = $iter; next_iteration = $nextIter
                summary = $summaryText; verification_packet = $packetPath; worker_prompts_next = $nextPaths.ToArray()
                check_in_prompt = $handoffCheckPath; next_from_template = $fromTemplate
            }
            $handoffJsonPath = Join-Path $invDir 'handoff.json'
            Write-TextAtomic $handoffJsonPath ($handoffObj | ConvertTo-Json -Depth 20)
            Write-TextAtomic (Join-Path $invDir 'handoff.md') ("# Fan-out handoff -- " + [string]$planObj.plan_id + "`n`n## Iteration " + $iter + " results`n`n" + $summaryText + "`n`n## Next`n`nIteration " + $nextIter + ": " + $nextPaths.Count + " worker prompt(s) in next-workers/; verify this iteration via verification-packet.json.`n")

            $result = [ordered]@{
                action = 'handoff'; plan_id = [string]$planObj.plan_id; from_iteration = $iter; next_iteration = $nextIter
                summary = $summaryText; worker_prompts_next = $nextPaths.ToArray()
                check_in_prompt_path = $handoffCheckPath; verification_packet_path = $packetPath; handoff_path = $handoffJsonPath
                next_from_template = $fromTemplate
            }
            $normInputs = [ordered]@{ action = 'handoff'; plan_id = $PlanId }
            Write-Diag "handoff plan=$($planObj.plan_id) next_iter=$nextIter items=$($items.Count) next_prompts=$($nextPaths.Count)"
        }
        'list' {
            $plans = New-Object System.Collections.Generic.List[object]
            $dirs = @(Get-ChildItem -LiteralPath $PlansDir -Directory -ErrorAction SilentlyContinue)
            foreach ($d in $dirs) {
                $pj = Join-Path $d.FullName 'plan.json'
                if (-not (Test-Path -LiteralPath $pj -PathType Leaf)) { continue }
                $po = $null; try { $po = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json } catch { continue }
                if ($null -eq $po) { continue }
                $plans.Add([ordered]@{
                    plan_id = [string](Prop $po 'plan_id' $d.Name); iteration = [int](Prop $po 'iteration' 1)
                    title = [string](Prop $po 'title' ''); worker_count = @($po.workers).Count; created_at_utc = [string](Prop $po 'created_at_utc' '')
                })
            }
            $result = [ordered]@{ action = 'list'; plans_dir = $PlansDir; count = $plans.Count; plans = $plans.ToArray() }
            $normInputs = [ordered]@{ action = 'list'; plans_dir = $PlansDir }
            Write-Diag "list plans_dir=$PlansDir count=$($plans.Count)"
        }
    }

    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) -- $($errorObj.message)"
}

# ---- artifacts: fanout.json + fanout.md ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $rj = [ordered]@{ schema = 'lifeorch.fanout.result/0.1'; invocation_id = $InvocationId; generated_at_utc = $startedAt.ToString('o'); result = $result }
        $rjPath = Join-Path $invDir 'fanout.json'
        [System.IO.File]::WriteAllText($rjPath, ($rj | ConvertTo-Json -Depth 30), $utf8)
        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# orchestrate.fanout -- $($result.action)")
        [void]$mb.AppendLine('')
        foreach ($k in $result.Keys) {
            $v = $result.$k
            if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) { [void]$mb.AppendLine("- **${k}:** $(@($v).Count) item(s)") }
            else { [void]$mb.AppendLine("- **${k}:** $v") }
        }
        [void]$mb.AppendLine('')
        $mdPath = Join-Path $invDir 'fanout.md'
        [System.IO.File]::WriteAllText($mdPath, $mb.ToString(), $utf8)
        # collect every artifact file written under the invocation dir
        foreach ($f in @(Get-ChildItem -LiteralPath $invDir -Recurse -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -eq 'stderr.txt') { continue }
            $b = [byte[]]([System.IO.File]::ReadAllBytes($f.FullName))
            $kind = switch -Regex ($f.Extension) { '\.json$' { 'json' } '\.md$' { 'markdown' } default { 'text' } }
            $artifacts += , ([ordered]@{ path = $f.FullName; kind = $kind; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[orchestrate.fanout] invocation $InvocationId action=$Action status=$status`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds
    inputs_digest = $(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result = $result; confidence = $null; artifacts = $artifacts; model_provenance = @()
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
