<#
    LiveRunAuditPathway.psm1 -- driver core for the Live-Run Audit Pathway (Widget 08, the LRAP surface).

    The audit program's PHENOMENOLOGICAL TOP surface (D-0120; AUDIT_PIPELINE.md P9). A STRICTLY READ-ONLY
    renderer that walks a REPLAYED #40 context_packet/0.2 compile as ONE chronological, plain-language,
    INTENT-vs-actual narrative, so a non-expert can find a bad input AT the step where it happens WITHOUT
    prerequisite schema expertise and WITHOUT window-switching. The shipped Widgets 05/06/07 are the
    expert-forensic DESCEND target reached on anomaly, not this top surface.

    Built EXACTLY to research/2026-08-08-i45-lrap-design.md (11 red-team findings folded). Load-bearing rules:
      * SIX-STEP SPINE (s1): normalize -> retrieve -> route -> select -> budget -> packet, over ONE #40
        artifact. Steps 7-8 (gate/verify) are NOT built (no wired end-to-end run exists). A flat (no-router)
        compile renders step 3 as NOT-APPLICABLE (never a blank that could read as "fine").
      * FOUR LANES per step (s2): INTENT / INPUT / OUTPUT / RECONCILE, in plain language, NOT raw schema.
      * HONESTY MAP (s3a): the fixed per-step x per-lane classification AUTH / DATA / VERDICT / P2. Every P2
        cell renders a VISIBLE "not emitted yet -- trace-emission follow-on logged" lane; NEVER a computed
        stand-in, NEVER a fake, NEVER a blank.
      * RECONCILE (s2, F1 -- HARD): a RECONCILE lane re-expresses ONLY a verdict the substrate ALREADY
        COMPUTES -- a set/count identity from the Widget-07 tournament (via the pinned adapter) or a plain
        arithmetic check. It introduces NO semantic judgment (omit_reason VALIDITY / successor-should-exist /
        classification-correctness are FORBIDDEN and logged as P2). Green = "counts reconcile", a
        necessary-not-sufficient signal -- NEVER "correct" (F2).
      * RECONCILE RENDER (F5): a NEUTRAL marker first pass (consistent / INCONSISTENT-here / not-applicable /
        not-emitted); the naming prose is COLLAPSED (Get-LrapStepDescend) until opened.
      * DESCEND (s4, F7): the descend prose is a PLAIN-LANGUAGE "why this step flagged" (records/counts named
        + the identity that failed), NOT a raw re-render of the 06/07 pane; the raw pane is reachable ONLY via
        Get-LrapRawTraceForStep ("show the raw trace" affordance).
      * READER ADAPTER (s5, F8): all 06/07 reuse is via LrapReaderAdapter.psm1 (a pinned, contract-tested
        surface over 06/07's EXISTING public readers; the recompute entrypoints are EXCLUDED). This core does
        NOT import 06/07 directly and NEVER recompiles.

    Contains NO WinForms dependency (runs on the cloud gate, pwsh 7.4.6 Linux, over committed REAL fixtures).
    STRICTLY READ-ONLY: renders pinned identities, writes nothing outside the widget's own runtime/ dir,
    calls no model, holds no lease, defines no pause point. Deterministic, integer-only, byte-identical on
    re-render. ASCII-only source (the 5.1-ANSI/BOM lesson). Shape mirrors CompileTraceConsole.psm1 /
    AuditTimelineTournament.psm1 (defensive Get-Prop, List[object] + .ToArray(), a write-guarded runtime).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LrapWidgetRoot = $PSScriptRoot
Import-Module ([System.IO.Path]::Combine($PSScriptRoot, 'LrapReaderAdapter.psm1')) -Force

$script:LrapVersion = '0.1.0'

# The selpol reason codes that mean a candidate was HARD-EXCLUDED by a rule (the rule FIRED to remove it). A
# packet-present record carrying one of these is a step-6 consistency violation (a record the rules excluded is
# still in the packet). This is a fixed set from CONTEXT_PACKET_CONTRACT s4 / i32 / i33 -- not a heuristic.
$script:LrapHardExclusionCodes = @('hard_filter_forbidden', 'hard_filter_namespace', 'hard_filter_stale', 'namespace_closure_violation')

# ============================================================================
#  small helpers (shared shape with CompileTraceConsole/AuditTimelineTournament; re-implemented locally so the
#  core has NO hidden dependency on a prefixed 06/07 helper -- only the pinned READERS go through the adapter)
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
        if ($Object.Contains($Name)) { $v = $Object[$Name]; if ($null -ne $v) { return $v }; return $Default }
        return $Default
    }
    if (Test-HasProp $Object $Name) { $v = $Object.$Name; if ($null -ne $v) { return $v } }
    return $Default
}

function ConvertTo-Array {
    param($Value)
    $acc = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Value) {
        if ($Value -is [string]) { [void]$acc.Add($Value) }
        elseif ($Value -is [System.Collections.IDictionary]) { [void]$acc.Add($Value) }
        elseif ($Value -is [System.Collections.IEnumerable]) { foreach ($v in $Value) { [void]$acc.Add($v) } }
        else { [void]$acc.Add($Value) }
    }
    return $acc.ToArray()
}

function Get-PropNames {
    param($Object)
    $acc = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Object) {
        if ($Object -is [System.Collections.IDictionary]) { foreach ($k in $Object.Keys) { [void]$acc.Add([string]$k) } }
        elseif ($null -ne $Object.PSObject) { foreach ($p in $Object.PSObject.Properties) { [void]$acc.Add([string]$p.Name) } }
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

function Format-Bool { param($V) if ($null -eq $V) { return 'n/a' } if ([bool]$V) { return 'yes' } return 'no' }

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-UnderRuntime {
    # Defense-in-depth: refuse any write outside the widget's OWN runtime dir. LRAP's render path writes NOTHING;
    # this exists so a FUTURE runtime write (e.g. a persisted "last walked" marker) cannot escape.
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$RuntimeDir)
    $runtimeFull = [System.IO.Path]::GetFullPath($RuntimeDir)
    $targetFull = [System.IO.Path]::GetFullPath($Target)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $guard = $runtimeFull.TrimEnd($sep) + $sep
    if (-not $targetFull.StartsWith($guard, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Live-Run Audit Pathway refused a write to '$targetFull' -- outside the widget runtime dir '$runtimeFull' (read-only guard)."
    }
    return $targetFull
}

# ============================================================================
#  path resolution
# ============================================================================

function Resolve-LrapPaths {
    [CmdletBinding()]
    param([string]$WidgetRoot, [string]$RepoRoot)
    if (-not $WidgetRoot) { $WidgetRoot = $script:LrapWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }
    if (-not $RepoRoot) {
        if ($env:LIFEORCH_LRAP_REPO) { $RepoRoot = $env:LIFEORCH_LRAP_REPO }
        else {
            $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
            if ($rp) { $RepoRoot = $rp.Path } else { $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }
        }
    }
    $compilerDir = [System.IO.Path]::Combine($RepoRoot, 'modules', '40-context-compiler')
    return [pscustomobject]@{
        WidgetRoot   = $WidgetRoot
        RepoRoot     = $RepoRoot
        ArtifactsDir = [System.IO.Path]::Combine($compilerDir, 'runtime', 'artifacts')
        RuntimeDir   = [System.IO.Path]::Combine($WidgetRoot, 'runtime')
    }
}

# ============================================================================
#  s3b -- the INTENT catalog (the yardstick every RECONCILE is judged against) + its OWN review gate
# ============================================================================

function Get-LrapIntentCatalog {
    # Six per-step INTENT blocks, each in plain language, each CITING the contract clause it paraphrases and
    # version-stamped. Authored once per step TYPE (AUTH in the honesty map). This is the yardstick; a subtly
    # wrong block silently mis-judges every run, so it gets its own review (Get-LrapIntentCatalogReview).
    return @(
        [pscustomobject]@{ step_no = 1; step_key = 'normalize'; title = 'Normalize the request'
            intent = 'Turn the raw request into a normalized task, a query class, and a temporal intent, so every later step knows WHAT is being asked and for WHICH point in time.'
            contract_clause = 'CONTEXT_PACKET_CONTRACT s0/i32-U5 (query classification) + i33-U5 (query_class vs temporal_intent are independent; an explicit user time outranks the class default)'
            contract_version = 'context_packet/0.2 (i33)' }
        [pscustomobject]@{ step_no = 2; step_key = 'retrieve'; title = 'Retrieve candidate records'
            intent = 'Search the pinned corpus snapshot for candidate records that might answer the task, across the available channels, and rank them.'
            contract_clause = 'CONTEXT_PACKET_CONTRACT s7 (evaluation seam: evaluation_hooks.retrieved[]) + MEMORY_CONTRACT s3 (the retriever-0.2 hit array)'
            contract_version = 'context_packet/0.2' }
        [pscustomobject]@{ step_no = 3; step_key = 'route'; title = 'Route through the channels'
            intent = 'Classify the query, choose which retrieval channels to use, and select the channel set -- each routing stage recorded as a versioned R-1 trace.'
            contract_clause = 'CONTEXT_PACKET_CONTRACT s9 (i37 R-1 router stage-trace, born instrumented; a flat/non-routed compile emits no trace)'
            contract_version = 'context_packet/0.2 (i37)' }
        [pscustomobject]@{ step_no = 4; step_key = 'select'; title = 'Select the packet contents'
            intent = 'Filter and rank the candidates down to what enters the packet -- namespace + temporal hard filters, supersession, authority, rank fusion, diversity, budget -- recording a reason for every candidate dropped.'
            contract_clause = 'CONTEXT_PACKET_CONTRACT s4 (P1-1: one versioned selection-policy library; the fixed stage order)'
            contract_version = 'selpol_rrf_v1/1.2.0' }
        [pscustomobject]@{ step_no = 5; step_key = 'budget'; title = 'Fit the token + transport budget'
            intent = 'Fit the selected evidence into the consumer model''s token budget and its real transport window; anything dropped for budget is recorded in the omission manifest.'
            contract_clause = 'CONTEXT_PACKET_CONTRACT s3 (P0-4: consumer/tokenizer profile + exact transport accounting; the count gates answerable)'
            contract_version = 'context_packet/0.2' }
        [pscustomobject]@{ step_no = 6; step_key = 'packet'; title = 'Assemble the packet'
            intent = 'Assemble the four regions (control_plane / task_input / working_memory / evidence) under the non_execution frame with trust banners; this IS the model''s whole context.'
            contract_clause = 'CONTEXT_PACKET_CONTRACT s1 (P0-1: control vs evidence, structurally separated) + s6 (packet identity) + s0 (non_execution holds)'
            contract_version = 'context_packet/0.2' }
    )
}

function Get-LrapIntentCatalogReview {
    # s3b own-gate: assert each INTENT block cites a contract clause AND is version-stamped, and name the
    # reviewer. Returns { reviewed, reviewer, block_count, all_cited, blocks[] }.
    [CmdletBinding()] param()
    $blocks = New-Object System.Collections.Generic.List[object]
    $allCited = $true
    foreach ($b in @(Get-LrapIntentCatalog)) {
        $cited = (-not [string]::IsNullOrWhiteSpace([string]$b.contract_clause)) -and (-not [string]::IsNullOrWhiteSpace([string]$b.contract_version)) -and (-not [string]::IsNullOrWhiteSpace([string]$b.intent))
        if (-not $cited) { $allCited = $false }
        [void]$blocks.Add([pscustomobject]@{ step_no = $b.step_no; step_key = $b.step_key; cited = $cited; contract_clause = $b.contract_clause; contract_version = $b.contract_version })
    }
    return [pscustomobject]@{
        reviewed = $true
        reviewer = 'LRAP-WIDGET08-i45 build agent, reviewed against the cited CONTEXT_PACKET_CONTRACT/selpol clauses; independent human live-GUI confirm (D-0064) is the pending acceptance gate'
        block_count = $blocks.Count
        all_cited = $allCited
        blocks = $blocks.ToArray()
    }
}

# ============================================================================
#  s3a -- the HONESTY MAP (fixed here, not decided by the renderer)
# ============================================================================

function Get-LrapHonestyMap {
    # The per-step x per-lane classification. AUTH=authored static INTENT; DATA=rendered from the artifact
    # verbatim; VERDICT=re-expresses a tournament/arithmetic identity the substrate already computes; P2=not
    # emitted by any existing artifact -> rendered as an explicit "not emitted yet" lane, never a stand-in.
    return @(
        [pscustomobject]@{ step_no = 1; step_key = 'normalize'; intent = 'AUTH'; input = 'P2'; output = 'DATA'; reconcile = 'P2' }
        [pscustomobject]@{ step_no = 2; step_key = 'retrieve'; intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
        [pscustomobject]@{ step_no = 3; step_key = 'route'; intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
        [pscustomobject]@{ step_no = 4; step_key = 'select'; intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
        [pscustomobject]@{ step_no = 5; step_key = 'budget'; intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
        [pscustomobject]@{ step_no = 6; step_key = 'packet'; intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
    )
}

function Get-LrapHonestyCell {
    param([int]$StepNo, [string]$Lane)
    foreach ($row in @(Get-LrapHonestyMap)) { if ($row.step_no -eq $StepNo) { return [string](Get-Prop $row $Lane '?') } }
    return '?'
}

function Get-LrapP2Backlog {
    # The logged trace-emission + forbidden-judgment backlog -- a BUILD OUTPUT of i45 (design s3a/s2). Each
    # renders on the surface as a visible "not emitted yet" lane; never faked, never a computed stand-in.
    return @(
        [pscustomobject]@{ id = 'P2-1'; step_no = 1; lane = 'INPUT'; kind = 'trace_emission'
            text = 'The raw pre-normalize instruction (what was actually typed before normalization) is not a mandated artifact, so the pathway cannot show it. Trace-emission follow-on logged.' }
        [pscustomobject]@{ id = 'P2-2'; step_no = 1; lane = 'RECONCILE'; kind = 'trace_emission'
            text = 'Normalize emits no R-1 stage count, so there is no substrate identity to reconcile at step 1. Trace-emission follow-on logged.' }
        [pscustomobject]@{ id = 'P2-3'; step_no = 2; lane = 'RECONCILE'; kind = 'trace_emission'
            text = 'A RECALL GAP -- a record that SHOULD have been fetched but was not -- is undetectable from a presence-only trace; this pathway cannot verify retrieval completeness. Trace-emission follow-on logged.' }
        [pscustomobject]@{ id = 'P2-4'; step_no = 4; lane = 'RECONCILE'; kind = 'forbidden_judgment'
            text = 'Whether a recorded omit_reason is JUSTIFIED (valid) is a semantic judgment; FORBIDDEN in v1 (RECONCILE re-expresses only substrate identities). Logged as a P2 semantic-judgment gap.' }
        [pscustomobject]@{ id = 'P2-5'; step_no = 4; lane = 'RECONCILE'; kind = 'forbidden_judgment'
            text = 'Whether a successor SHOULD exist (supersession correctness) is a semantic judgment; FORBIDDEN in v1. Logged as a P2 semantic-judgment gap.' }
        [pscustomobject]@{ id = 'P2-6'; step_no = 1; lane = 'RECONCILE'; kind = 'forbidden_judgment'
            text = 'Whether the query classification is SEMANTICALLY right is a judgment; FORBIDDEN in v1. Logged as a P2 semantic-judgment gap.' }
    )
}

# ============================================================================
#  substrate accessors (read-only) -- the raw arrays the reconcile identities are computed over
# ============================================================================

function Get-LrapStageIds {
    param($Packet, [string]$StageName)
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $stages = Get-Prop $eh 'stages' $null
    return @(@(ConvertTo-Array (Get-Prop $stages $StageName $null)) | ForEach-Object { [string](Get-Prop $_ 'record_version_id' (Get-Prop $_ 'record_id' '?')) })
}

function Get-LrapSelectedIds {
    param($Packet)
    $idn = Get-Prop $Packet 'identity' $null
    return @(@(ConvertTo-Array (Get-Prop $idn 'selected_record_version_ids' $null)) | ForEach-Object { [string]$_ })
}

function Get-LrapExcerptIds {
    param($Packet)
    $ev = Get-Prop $Packet 'evidence' $null
    return @(@(ConvertTo-Array (Get-Prop $ev 'excerpts' $null)) | ForEach-Object { [string](Get-Prop $_ 'record_version_id' '?') })
}

function Get-LrapReasonCodesForId {
    # The selpol reason codes recorded for one record_version_id, unioned across features_by_candidate + the
    # evaluation_hooks.retrieved[] mirror. Read-only re-expression of the substrate's own reason codes.
    param($Packet, [string]$Id)
    $codes = New-Object System.Collections.Generic.List[string]
    $sel = Get-Prop $Packet 'selection' $null
    $feat = Get-Prop $sel 'features_by_candidate' $null
    $f = Get-Prop $feat $Id $null
    foreach ($rc in @(ConvertTo-Array (Get-Prop $f 'reason_codes' $null))) { [void]$codes.Add([string]$rc) }
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    foreach ($r in @(ConvertTo-Array (Get-Prop $eh 'retrieved' $null))) {
        if ([string](Get-Prop $r 'record_version_id' (Get-Prop $r 'record_id' '')) -eq $Id) {
            foreach ($rc in @(ConvertTo-Array (Get-Prop $r 'reason_codes' $null))) { [void]$codes.Add([string]$rc) }
        }
    }
    return @($codes.ToArray() | Select-Object -Unique)
}

function Get-LrapPacketExclusionViolations {
    # Step-6 identity offenders: every record PRESENT in the packet stage that carries a HARD-EXCLUSION reason
    # code (the rule fired to remove it, yet it is in the packet). A set-membership identity over the
    # substrate's own arrays -- NOT a semantic judgment. Returns [{ id, codes }].
    param($Packet)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($id in @(Get-LrapStageIds -Packet $Packet -StageName 'packet')) {
        $codes = @(Get-LrapReasonCodesForId -Packet $Packet -Id $id)
        $hit = @($codes | Where-Object { $script:LrapHardExclusionCodes -contains $_ })
        if ($hit.Count -gt 0) { [void]$out.Add([pscustomobject]@{ id = $id; codes = @($hit) }) }
    }
    return $out.ToArray()
}

function Get-LrapUnexplainedDrops {
    # Step-4 identity offenders: a candidate present in raw_retrieval but ABSENT from post_filter with NO
    # omit_reason recorded (and not marked selected=false) in retrieved[]. Re-expresses the SAME presence
    # identity the Widget-07 selection bracket verdicts on. Returns [{ id, where }].
    param($Packet)
    $raw = @(Get-LrapStageIds -Packet $Packet -StageName 'raw_retrieval')
    $post = @(Get-LrapStageIds -Packet $Packet -StageName 'post_filter')
    $pkt = @(Get-LrapStageIds -Packet $Packet -StageName 'packet')
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $omitByRvid = @{}
    foreach ($r in @(ConvertTo-Array (Get-Prop $eh 'retrieved' $null))) {
        $rvid = [string](Get-Prop $r 'record_version_id' (Get-Prop $r 'record_id' '?'))
        $omitByRvid[$rvid] = [pscustomobject]@{ omit = (Get-Prop $r 'omit_reason' $null); selected = (Get-Prop $r 'selected' $null) }
    }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($pair in @(@{ from = 'raw_retrieval'; to = 'post_filter'; src = $raw; dst = $post }, @{ from = 'post_filter'; to = 'packet'; src = $post; dst = $pkt })) {
        foreach ($id in @($pair.src | Where-Object { $pair.dst -notcontains $_ })) {
            $info = $omitByRvid[$id]
            $explained = ($null -ne $info -and ($null -ne $info.omit -or $info.selected -eq $false))
            if (-not $explained) { [void]$out.Add([pscustomobject]@{ id = $id; where = ($pair.from + ' -> ' + $pair.to) }) }
        }
    }
    return $out.ToArray()
}

# ============================================================================
#  the per-step RECONCILE (verdict-backed ONLY) -- s2 / s3a
# ============================================================================

function New-LrapIdentity { param([string]$Name, [bool]$Held, [string]$Detail) return [pscustomobject]@{ name = $Name; held = $Held; detail = $Detail } }

function Get-LrapStepReconcile {
    <#
        Compute the RECONCILE lane for one step: its honesty class, its verdict, a NEUTRAL marker, the substrate
        identities checked, the offenders, and the COLLAPSED plain-language descend prose. VERDICT lanes
        re-express ONLY identities the substrate already computes (the Widget-07 brackets via the adapter, or a
        plain arithmetic check). NO semantic judgment. Verdict is one of: consistent | inconsistent |
        not_applicable | not_emitted.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$StepNo, [Parameter(Mandatory)]$Packet, $RouterBracket, $SelectionBracket)

    $cls = Get-LrapHonestyCell -StepNo $StepNo -Lane 'reconcile'
    $identities = New-Object System.Collections.Generic.List[object]
    $offenders = New-Object System.Collections.Generic.List[string]
    $descend = New-Object System.Collections.Generic.List[string]
    $p2notes = New-Object System.Collections.Generic.List[string]
    $verdict = 'not_emitted'

    if ($cls -eq 'P2') {
        # step 1: no substrate identity exists here.
        foreach ($g in @(Get-LrapP2Backlog | Where-Object { $_.step_no -eq $StepNo -and $_.lane -eq 'RECONCILE' })) { [void]$p2notes.Add($g.id + ': ' + $g.text) }
        [void]$descend.Add('No substrate identity is emitted for this step, so there is nothing to reconcile. This is a logged trace-emission follow-on (P2), NOT a fault in the run.')
        return [pscustomobject]@{ step_no = $StepNo; lane_class = 'P2'; verdict = 'not_emitted'; marker = 'not emitted yet (P2)'; identities = @(); offenders = @(); descend_prose = $descend.ToArray(); p2_notes = $p2notes.ToArray() }
    }

    switch ($StepNo) {
        2 {
            $rawCount = @(Get-LrapStageIds -Packet $Packet -StageName 'raw_retrieval').Count
            $eh = Get-Prop $Packet 'evaluation_hooks' $null
            $retCount = @(ConvertTo-Array (Get-Prop $eh 'retrieved' $null)).Count
            $held = ($rawCount -eq $retCount)
            [void]$identities.Add((New-LrapIdentity 'ranked-count = raw-retrieval-count' $held ("retrieved[] has $retCount; raw_retrieval stage lists $rawCount")))
            $verdict = if ($held) { 'consistent' } else { 'inconsistent' }
            if ($held) { [void]$descend.Add("The retriever returned $retCount ranked candidates and the raw-retrieval stage lists $rawCount -- the raw candidate set is reported consistently. (This is a count reconcile, NOT a claim the RIGHT records were retrieved.)") }
            else { [void]$descend.Add("MISMATCH: the retriever returned $retCount ranked candidates but the raw-retrieval stage lists $rawCount. The raw candidate set is not reported consistently. (identity failed: retrieved[] count must equal raw_retrieval stage count)") }
            foreach ($g in @(Get-LrapP2Backlog | Where-Object { $_.step_no -eq 2 -and $_.lane -eq 'RECONCILE' })) { [void]$p2notes.Add($g.id + ': ' + $g.text) }
        }
        3 {
            if ($null -eq $RouterBracket -or -not $RouterBracket.present) {
                [void]$descend.Add('This is a FLAT (no-router) compile: the router was not engaged, so there is no routing to reconcile. This is normal for a flat compile, NOT a defect.')
                return [pscustomobject]@{ step_no = 3; lane_class = 'VERDICT'; verdict = 'not_applicable'; marker = 'not applicable (flat compile -- router not engaged)'; identities = @(); offenders = @(); descend_prose = $descend.ToArray(); p2_notes = @() }
            }
            $held = [bool]$RouterBracket.reconciled
            $rounds = @($RouterBracket.rounds)
            $countAllOk = $true; $chainAllOk = $true
            $prevOut = $null
            foreach ($r in $rounds) {
                if (-not $r.count_ok) { $countAllOk = $false; [void]$offenders.Add([string]$r.stage_id) ; [void]$descend.Add(("Round '" + [string]$r.stage_id + "' does not add up: " + [string]$r.candidates_in + " in, " + [string]$r.removed_count + " removed, but " + [string]$r.candidates_out + " out. (identity failed: in - removed = out)")) }
                if (-not $r.chain_ok) { $chainAllOk = $false; [void]$offenders.Add([string]$r.stage_id); [void]$descend.Add(("The chain is broken at '" + [string]$r.stage_id + "': it reports " + [string]$r.candidates_in + " candidates in, but the previous stage emitted " + [string]$prevOut + " out. A candidate appeared or vanished between stages without being recorded. (identity failed: out[previous] = in[this])")) }
                $prevOut = [int]$r.candidates_out
            }
            [void]$identities.Add((New-LrapIdentity 'each round: candidates_in - removed = candidates_out' $countAllOk 'per-round elimination count'))
            [void]$identities.Add((New-LrapIdentity 'chain: out[n] = in[n+1] across rounds' $chainAllOk 'stage-to-stage continuity'))
            $verdict = if ($held) { 'consistent' } else { 'inconsistent' }
            if ($held) { [void]$descend.Add(('All ' + $rounds.Count + ' routing rounds reconcile: each round''s in - removed = out, and the candidate count carries cleanly from one stage to the next.')) }
        }
        4 {
            if ($null -eq $SelectionBracket -or -not $SelectionBracket.present) {
                [void]$descend.Add('No selection stages were emitted, so there is nothing to reconcile at selection.')
                return [pscustomobject]@{ step_no = 4; lane_class = 'VERDICT'; verdict = 'not_emitted'; marker = 'not emitted yet (P2)'; identities = @(); offenders = @(); descend_prose = $descend.ToArray(); p2_notes = @() }
            }
            $held = [bool]$SelectionBracket.reconciled
            $raw = $SelectionBracket.raw; $post = $SelectionBracket.post; $pkt = $SelectionBracket.packet
            $drops = @(Get-LrapUnexplainedDrops -Packet $Packet)
            $subsetOk = ($held -or $drops.Count -gt 0)  # if the only failure is unexplained drops, subset may still hold
            [void]$identities.Add((New-LrapIdentity 'packet is a subset of post-filter is a subset of raw-retrieval' $held ("raw=$raw post=$post packet=$pkt")))
            [void]$identities.Add((New-LrapIdentity 'every dropped candidate carries an omit_reason (PRESENCE, not validity)' ($drops.Count -eq 0) ("unexplained drops: " + $drops.Count)))
            $verdict = if ($held) { 'consistent' } else { 'inconsistent' }
            if ($held) { [void]$descend.Add("The funnel reconciles: raw retrieval ($raw) -> post-filter ($post) -> packet ($pkt), each a subset of the last, and every dropped candidate carries a recorded reason. (A drop being RECORDED is not a claim the drop was JUSTIFIED -- see the P2 note.)") }
            foreach ($d in $drops) {
                [void]$offenders.Add([string]$d.id)
                [void]$descend.Add(("A candidate was dropped with NO recorded reason: '" + [string]$d.id + "' is present earlier (" + [string]$d.where + ") but vanished with no omit_reason to explain why. (identity failed: every dropped candidate must carry an omit_reason)"))
            }
            foreach ($g in @(Get-LrapP2Backlog | Where-Object { $_.step_no -eq 4 -and $_.lane -eq 'RECONCILE' })) { [void]$p2notes.Add($g.id + ': ' + $g.text) }
        }
        5 {
            $tb = Get-Prop $Packet 'token_budget' $null
            $ta = Get-Prop $Packet 'transport_accounting' $null
            $budget = Get-Prop $tb 'budget' $null; $used = Get-Prop $tb 'used' $null
            $body = Get-Prop $tb 'excerpt_body_tokens' $null; $ovh = Get-Prop $tb 'overhead_tokens' $null
            $rendered = Get-Prop $ta 'rendered_tokens' $null; $reserved = Get-Prop $ta 'reserved_total_tokens' $null
            $maxctx = Get-Prop $ta 'max_context' $null; $overflow = Get-Prop $ta 'transport_overflow' $null; $fits = Get-Prop $ta 'fits' $null
            $checked = 0
            if ($null -ne $used -and $null -ne $budget) { $ok = ([int]$used -le [int]$budget); $checked++; [void]$identities.Add((New-LrapIdentity 'tokens used <= budget' $ok ("used=$used budget=$budget"))); if (-not $ok) { [void]$descend.Add("The packet uses more tokens ($used) than its budget ($budget). (identity failed: used <= budget)") } }
            if ($null -ne $body -and $null -ne $ovh -and $null -ne $used) { $ok = (([int]$body + [int]$ovh) -eq [int]$used); $checked++; [void]$identities.Add((New-LrapIdentity 'excerpt-body + overhead = used' $ok ("$body + $ovh vs $used"))); if (-not $ok) { [void]$descend.Add("The token ledger does not add up: excerpt body ($body) + overhead ($ovh) does not equal used ($used). (identity failed: body + overhead = used)") } }
            if ($null -ne $rendered -and $null -ne $reserved -and $null -ne $maxctx) { $ok = (([int]$rendered + [int]$reserved) -le [int]$maxctx) -and ($overflow -ne $true); $checked++; [void]$identities.Add((New-LrapIdentity 'rendered + reserved <= max_context (no transport overflow)' $ok ("$rendered + $reserved vs $maxctx; overflow=" + (Format-Bool $overflow)))); if (-not $ok) { [void]$descend.Add("The rendered packet ($rendered tokens) plus reserves ($reserved) exceeds the model's context window ($maxctx), or transport overflowed. (identity failed: rendered + reserved <= max_context)") } }
            if ($checked -eq 0) { return [pscustomobject]@{ step_no = 5; lane_class = 'VERDICT'; verdict = 'not_emitted'; marker = 'not emitted yet (P2)'; identities = @(); offenders = @(); descend_prose = @('No budget/transport ledger was emitted, so there is nothing to reconcile.'); p2_notes = @() } }
            $allOk = (@($identities | Where-Object { -not $_.held }).Count -eq 0)
            $verdict = if ($allOk) { 'consistent' } else { 'inconsistent' }
            if ($allOk) { [void]$descend.Add("The budget arithmetic reconciles: $used of $budget tokens used (body $body + overhead $ovh), and the rendered packet fits the transport window ($rendered + $reserved <= $maxctx).") }
        }
        6 {
            $pktSet = @(Get-LrapStageIds -Packet $Packet -StageName 'packet' | Sort-Object)
            $selSet = @(Get-LrapSelectedIds -Packet $Packet | Sort-Object)
            $excSet = @(Get-LrapExcerptIds -Packet $Packet)
            $eqOk = (($pktSet -join '|') -eq ($selSet -join '|'))
            $excSubset = $true; foreach ($e in $excSet) { if ($selSet -notcontains $e) { $excSubset = $false } }
            $ne = Get-Prop $Packet 'non_execution' $null
            $neOk = ($ne -eq $true)
            $banners = Get-LrapTrustBannerCheck -Packet $Packet
            $viol = @(Get-LrapPacketExclusionViolations -Packet $Packet)
            $exclOk = ($viol.Count -eq 0)
            [void]$identities.Add((New-LrapIdentity 'packet stage = selected_record_version_ids (step-4 output = packet)' $eqOk ("packet=" + $pktSet.Count + " selected=" + $selSet.Count)))
            [void]$identities.Add((New-LrapIdentity 'every excerpt is in the selected set' $excSubset ("excerpts=" + $excSet.Count)))
            [void]$identities.Add((New-LrapIdentity 'non_execution frame present (P0-1)' $neOk ('non_execution=' + (Format-Bool $ne))))
            [void]$identities.Add((New-LrapIdentity 'four regions carry their trust banners' $banners.ok ($banners.detail)))
            [void]$identities.Add((New-LrapIdentity 'no packet record carries a hard-exclusion reason code' $exclOk ('rule-excluded-yet-present: ' + $viol.Count)))
            $allOk = $eqOk -and $excSubset -and $neOk -and $banners.ok -and $exclOk
            $verdict = if ($allOk) { 'consistent' } else { 'inconsistent' }
            if ($allOk) { [void]$descend.Add("The assembled packet reconciles: its " + $pktSet.Count + " records match the selected set exactly, every excerpt is a selected record, non_execution is set, the four regions carry their trust banners, and no record the rules excluded is present. (Counts reconcile -- NOT a claim the packet is CORRECT or complete.)") }
            if (-not $eqOk) { [void]$descend.Add("The packet's records do not match the selected set: packet stage has " + $pktSet.Count + " but identity.selected_record_version_ids has " + $selSet.Count + ". (identity failed: packet stage = selected set)") }
            if (-not $neOk) { [void]$descend.Add("The non_execution frame is not set (P0-1 requires non_execution=true for a read-only compile).") }
            foreach ($v in $viol) {
                [void]$offenders.Add([string]$v.id)
                [void]$descend.Add(("A record the rules FIRED against is STILL PRESENT in the packet: '" + [string]$v.id + "' carries the exclusion code(s) [" + ((@($v.codes)) -join ', ') + "] yet appears in the assembled packet. A record the rules excluded should not be in the packet. (identity failed: no packet record may carry a hard-exclusion reason code)"))
            }
        }
        default { $verdict = 'not_emitted' }
    }

    $marker = switch ($verdict) {
        'consistent' { 'consistent -- counts reconcile' }
        'inconsistent' { 'INCONSISTENT here' }
        'not_applicable' { 'not applicable (flat compile -- router not engaged)' }
        default { 'not emitted yet (P2)' }
    }
    return [pscustomobject]@{
        step_no = $StepNo; lane_class = $cls; verdict = $verdict; marker = $marker
        identities = $identities.ToArray(); offenders = @($offenders.ToArray() | Select-Object -Unique)
        descend_prose = $descend.ToArray(); p2_notes = $p2notes.ToArray()
    }
}

function Get-LrapTrustBannerCheck {
    # Presence of the four regions' trust banners (P0-1 structural separation). Presence, not validity.
    param($Packet)
    $cp = Get-Prop $Packet 'control_plane' $null
    $ti = Get-Prop $Packet 'task_input' $null
    $wm = Get-Prop $Packet 'working_memory' $null
    $ev = Get-Prop $Packet 'evidence' $null
    $ec = Get-Prop $ev 'evidence_contract' $null
    $cpOk = ($null -ne $cp -and $null -ne (Get-Prop $cp 'side_effect_policy' $null))
    $tiOk = ($null -ne $ti)
    $wmOk = ($null -ne $wm -and ([string](Get-Prop $wm 'content_role' '') -eq 'working_state'))
    $evOk = ($null -ne $ec -and ((Get-Prop $ec 'can_instruct' $true) -eq $false))
    $ok = $cpOk -and $tiOk -and $wmOk -and $evOk
    return [pscustomobject]@{ ok = $ok; detail = ('control_plane=' + (Format-Bool $cpOk) + ' task_input=' + (Format-Bool $tiOk) + ' working_memory=' + (Format-Bool $wmOk) + ' evidence=' + (Format-Bool $evOk)) }
}

# ============================================================================
#  the four-lane per-step render (INTENT / INPUT / OUTPUT / RECONCILE, plain language)
# ============================================================================

function Get-LrapStepLanes {
    # Build INPUT + OUTPUT display lines (plain language, DATA/P2 classified) for one step.
    param([Parameter(Mandatory)][int]$StepNo, [Parameter(Mandatory)]$Packet, $RouterBracket)
    $inClass = Get-LrapHonestyCell -StepNo $StepNo -Lane 'input'
    $outClass = Get-LrapHonestyCell -StepNo $StepNo -Lane 'output'
    $inLines = New-Object System.Collections.Generic.List[string]
    $outLines = New-Object System.Collections.Generic.List[string]

    $ti = Get-Prop $Packet 'task_input' $null
    $rp = Get-Prop $Packet 'retrieval_provenance' $null
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $tb = Get-Prop $Packet 'token_budget' $null
    $ta = Get-Prop $Packet 'transport_accounting' $null
    $cprof = Get-Prop $Packet 'consumer_profile' $null
    $disp = Get-Prop $Packet 'disposition' $null

    switch ($StepNo) {
        1 {
            foreach ($g in @(Get-LrapP2Backlog | Where-Object { $_.step_no -eq 1 -and $_.lane -eq 'INPUT' })) { [void]$inLines.Add($g.id + ': ' + $g.text) }
            [void]$outLines.Add('normalized task : ' + (Limit-Text (Get-Prop $ti 'normalized_task' '?') 80))
            [void]$outLines.Add('task type       : ' + [string](Get-Prop $ti 'task_type' '?'))
            [void]$outLines.Add('query class     : ' + [string](Get-Prop $ti 'query_class' '?') + '  (basis: ' + [string](Get-Prop $ti 'query_class_basis' '?') + ')')
            [void]$outLines.Add('temporal intent : ' + [string](Get-Prop $ti 'temporal_intent' '?') + '  (basis: ' + [string](Get-Prop $ti 'temporal_intent_basis' '?') + ')')
        }
        2 {
            $qset = @(ConvertTo-Array (Get-Prop $rp 'query_set' $null))
            [void]$inLines.Add('searched the pinned corpus "' + [string](Get-Prop $rp 'corpus_version' '?') + '" with ' + $qset.Count + ' quer' + $(if ($qset.Count -eq 1) { 'y' } else { 'ies' }))
            [void]$inLines.Add('retriever ' + [string](Get-Prop $rp 'retriever' '?') + '/' + [string](Get-Prop $rp 'retriever_version' '?') + '  fusion=' + [string](Get-Prop $rp 'fusion_algo' '?') + '  vector channel=' + [string](Get-Prop $rp 'vector_channel_status' 'empty'))
            $ret = @(ConvertTo-Array (Get-Prop $eh 'retrieved' $null))
            [void]$outLines.Add($ret.Count.ToString() + ' candidate records came back, ranked. Top by selection rank:')
            $top = @($ret | Sort-Object { [int](Get-Prop $_ 'selection_rank' 9999) } | Select-Object -First 3)
            foreach ($r in $top) { [void]$outLines.Add('   #' + [string](Get-Prop $r 'selection_rank' '?') + '  ' + (Limit-Text (Get-Prop $r 'record_version_id' (Get-Prop $r 'record_id' '?')) 40)) }
        }
        3 {
            if ($null -eq $RouterBracket -or -not $RouterBracket.present) {
                [void]$inLines.Add('(flat compile -- the router was not engaged)')
                [void]$outLines.Add('no routing stage-trace (a flat / no-router compile does not route)')
            }
            else {
                $rounds = @($RouterBracket.rounds)
                if ($rounds.Count -gt 0) { [void]$inLines.Add($rounds[0].candidates_in.ToString() + ' candidates entered the router') }
                foreach ($r in $rounds) { [void]$outLines.Add('stage "' + [string]$r.stage_id + '": ' + [string]$r.candidates_in + ' in, ' + [string]$r.removed_count + ' removed, ' + [string]$r.candidates_out + ' out') }
            }
        }
        4 {
            $raw = @(Get-LrapStageIds -Packet $Packet -StageName 'raw_retrieval').Count
            [void]$inLines.Add($raw.ToString() + ' ranked candidates entered selection (namespace/temporal filters, supersession, authority, fusion, diversity, budget)')
            $pkt = @(Get-LrapStageIds -Packet $Packet -StageName 'packet').Count
            [void]$outLines.Add($pkt.ToString() + ' records selected into the packet')
        }
        5 {
            [void]$inLines.Add('budget ' + [string](Get-Prop $tb 'budget' '?') + ' tokens; max excerpts ' + [string](Get-Prop $tb 'max_excerpts' '?') + '; consumer ' + [string](Get-Prop $cprof 'model_id' '?') + ' / tokenizer ' + [string](Get-Prop $cprof 'tokenizer_id' '?'))
            [void]$outLines.Add('used ' + [string](Get-Prop $tb 'used' '?') + ' of ' + [string](Get-Prop $tb 'budget' '?') + ' tokens; ' + [string](Get-Prop $tb 'excerpt_count' '?') + ' excerpts; omitted ' + [string](Get-Prop $tb 'omitted_count' '0'))
            [void]$outLines.Add('transport: rendered ' + [string](Get-Prop $ta 'rendered_tokens' '?') + ' + reserved ' + [string](Get-Prop $ta 'reserved_total_tokens' '?') + ' of ' + [string](Get-Prop $ta 'max_context' '?') + ' (fits=' + (Format-Bool (Get-Prop $ta 'fits' $false)) + ', overflow=' + (Format-Bool (Get-Prop $ta 'transport_overflow' $false)) + ')')
        }
        6 {
            [void]$inLines.Add('the four regions: control_plane (authority), task_input (request), working_memory (state), evidence (data)')
            [void]$outLines.Add('packet_id ' + [string](Get-Prop $Packet 'packet_id' '?'))
            [void]$outLines.Add('disposition ' + [string](Get-Prop $disp 'packet_disposition' '?') + '; ' + @(Get-LrapExcerptIds -Packet $Packet).Count + ' excerpts; non_execution=' + (Format-Bool (Get-Prop $Packet 'non_execution' $null)))
        }
    }
    if ($inLines.Count -eq 0) { [void]$inLines.Add('(none)') }
    if ($outLines.Count -eq 0) { [void]$outLines.Add('(none)') }
    return [pscustomobject]@{ input_class = $inClass; input_lines = $inLines.ToArray(); output_class = $outClass; output_lines = $outLines.ToArray() }
}

function Get-LrapSpine {
    # Build the ordered six-step spine, each step with its four lanes (INTENT/INPUT/OUTPUT/RECONCILE) classified
    # per the honesty map. A flat compile renders step 3 as NOT-APPLICABLE (visible, never a blank).
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet, $RouterBracket, $SelectionBracket)
    $catalog = @{}
    foreach ($b in @(Get-LrapIntentCatalog)) { $catalog[[int]$b.step_no] = $b }
    $steps = New-Object System.Collections.Generic.List[object]
    foreach ($n in 1, 2, 3, 4, 5, 6) {
        $intent = $catalog[$n]
        $lanes = Get-LrapStepLanes -StepNo $n -Packet $Packet -RouterBracket $RouterBracket
        $recon = Get-LrapStepReconcile -StepNo $n -Packet $Packet -RouterBracket $RouterBracket -SelectionBracket $SelectionBracket
        $applicable = -not ($n -eq 3 -and $recon.verdict -eq 'not_applicable')
        [void]$steps.Add([pscustomobject]@{
                step_no = $n; step_key = $intent.step_key; title = $intent.title; applicable = $applicable
                intent = [pscustomobject]@{ class = 'AUTH'; text = $intent.intent; contract_clause = $intent.contract_clause; contract_version = $intent.contract_version }
                input = [pscustomobject]@{ class = $lanes.input_class; lines = $lanes.input_lines }
                output = [pscustomobject]@{ class = $lanes.output_class; lines = $lanes.output_lines }
                reconcile = $recon
            })
    }
    return $steps.ToArray()
}

# ============================================================================
#  the whole model
# ============================================================================

function Get-LrapModel {
    <#
        Build the full LRAP model for one replayed #40 packet. Never throws to the UI: a load failure yields a
        well-formed ok=false model the header renders. STRICTLY READ-ONLY (renders pinned identities; no
        recompute). Returns { ok, error, source_path, packet_id, schema, compiler_version, is_flat, steps[],
        overall{...}, p2_backlog[], sanitize, intent_review, non_execution, disposition }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PacketPath)
    $rd = Read-LrapPacket -Path $PacketPath
    if (-not $rd.ok) {
        return [pscustomobject]@{
            ok = $false; error = $rd.error; source_path = [string]$PacketPath
            packet_id = ''; schema = ''; compiler_version = ''; is_flat = $null; packet = $null
            steps = @(); overall = $null; p2_backlog = @(Get-LrapP2Backlog); sanitize = $null
            intent_review = (Get-LrapIntentCatalogReview); non_execution = $null; disposition = ''
        }
    }
    $p = $rd.packet
    $router = $null; $selection = $null; $sanitize = $null
    try { $router = Get-LrapRouterBracket -Packet $p } catch { }
    try { $selection = Get-LrapSelectionBracket -Packet $p } catch { }
    try { $sanitize = Test-LrapTraceSanitized -Packet $p } catch { }
    $isFlat = -not ($null -ne $router -and $router.present)

    $steps = Get-LrapSpine -Packet $p -RouterBracket $router -SelectionBracket $selection
    $overall = Get-LrapVerdict -Steps $steps

    return [pscustomobject]@{
        ok = $true; error = ''; source_path = [string]$PacketPath
        packet_id = $rd.packet_id; schema = $rd.schema; compiler_version = $rd.compiler_version
        is_flat = $isFlat
        packet = $p
        steps = $steps
        overall = $overall
        p2_backlog = @(Get-LrapP2Backlog)
        sanitize = $sanitize
        intent_review = (Get-LrapIntentCatalogReview)
        non_execution = (Get-Prop $p 'non_execution' $null)
        disposition = [string](Get-Prop (Get-Prop $p 'disposition' $null) 'packet_disposition' '?')
    }
}

function Get-LrapVerdict {
    # The machine classification over a built spine: overall = the LOWEST step whose RECONCILE verdict is
    # 'inconsistent'; else 'consistent'. P2 / not_emitted / not_applicable NEVER make a run inconsistent.
    [CmdletBinding()] param([Parameter(Mandatory)]$Steps)
    $perStep = New-Object System.Collections.Generic.List[object]
    $inconsistentStep = 0
    foreach ($s in @($Steps)) {
        $v = [string]$s.reconcile.verdict
        [void]$perStep.Add([pscustomobject]@{ step_no = $s.step_no; step_key = $s.step_key; verdict = $v; marker = $s.reconcile.marker })
        if ($v -eq 'inconsistent' -and $inconsistentStep -eq 0) { $inconsistentStep = [int]$s.step_no }
    }
    $overall = if ($inconsistentStep -eq 0) { 'consistent' } else { 'inconsistent' }
    return [pscustomobject]@{
        overall = $overall
        inconsistent_step = $inconsistentStep
        classification = if ($inconsistentStep -eq 0) { 'consistent -- counts reconcile at every step (NOT a correctness claim)' } else { ('INCONSISTENT at step ' + $inconsistentStep) }
        per_step = $perStep.ToArray()
    }
}

# ============================================================================
#  descend (plain language) + the raw-trace affordance (behind an explicit call)
# ============================================================================

function Get-LrapStepDescend {
    # The COLLAPSED plain-language "why" for one step -- the specific records/counts named in prose + the
    # identity that failed (or held). NOT a raw pane. This is what the UI reveals when the user opens a step.
    [CmdletBinding()] param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][int]$StepNo)
    foreach ($s in @($Model.steps)) {
        if ($s.step_no -eq $StepNo) {
            $lines = New-Object System.Collections.Generic.List[string]
            foreach ($l in @($s.reconcile.descend_prose)) { [void]$lines.Add([string]$l) }
            foreach ($n in @($s.reconcile.p2_notes)) { [void]$lines.Add('P2: ' + [string]$n) }
            if ($lines.Count -eq 0) { [void]$lines.Add('(no descend detail)') }
            return $lines.ToArray()
        }
    }
    return @('(no such step)')
}

function Get-LrapRawTraceForStep {
    # The EXPLICIT "show the raw trace" affordance (design s4 / F7): reachable ONLY on demand, NEVER the
    # default surface. Delegates to the pinned 06 expert panes via the adapter. Returns { header, lines[] }.
    [CmdletBinding()] param([Parameter(Mandatory)]$Packet, [Parameter(Mandatory)][int]$StepNo)
    $pane = switch ($StepNo) {
        1 { Get-LrapRawModelView -Packet $Packet }
        2 { Get-LrapRawRetrievalTrace -Packet $Packet }
        3 { Get-LrapRawRetrievalTrace -Packet $Packet }
        4 { Get-LrapRawRuleStack -Packet $Packet }
        5 { Get-LrapRawLedger -Packet $Packet }
        6 { Get-LrapRawModelView -Packet $Packet }
        default { $null }
    }
    if ($null -eq $pane) { return [pscustomobject]@{ header = 'no raw trace for this step'; lines = @() } }
    return [pscustomobject]@{ header = ('RAW EXPERT TRACE (Widget 06 pane, via the pinned adapter) -- ' + [string]$pane.header); lines = @($pane.lines) }
}

# ============================================================================
#  header / summary
# ============================================================================

function Format-LrapHeader {
    [CmdletBinding()] param([Parameter(Mandatory)]$Model)
    $h = New-Object System.Collections.Generic.List[string]
    if (-not $Model.ok) {
        [void]$h.Add('LIVE-RUN AUDIT PATHWAY -- load FAILED: ' + [string]$Model.error)
        [void]$h.Add('source: ' + [string]$Model.source_path)
        return [pscustomobject]@{ header_lines = $h.ToArray(); summary_line = 'load failed: ' + [string]$Model.error }
    }
    $san = if ($null -ne $Model.sanitize -and $Model.sanitize.sanitized) { 'sanitized' } else { 'SANITIZATION-FLAG' }
    $flat = if ($Model.is_flat) { 'flat (no-router) compile' } else { 'routed compile' }
    [void]$h.Add('LIVE-RUN AUDIT PATHWAY (widget 08)   packet_id=' + $Model.packet_id + '   ' + $flat)
    [void]$h.Add('schema=' + $Model.schema + '   compiler=' + $Model.compiler_version + '   non_execution=' + (Format-Bool $Model.non_execution) + '   disposition=' + $Model.disposition + '   diagnostics=' + $san)
    [void]$h.Add('VERDICT: ' + [string]$Model.overall.classification + '   (green = counts reconcile, a necessary-not-sufficient signal -- NOT a claim the run is correct)')
    $summary = 'packet ' + $Model.packet_id + ' -- ' + [string]$Model.overall.classification
    return [pscustomobject]@{ header_lines = $h.ToArray(); summary_line = $summary }
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Prop, ConvertTo-Array, Get-PropNames, Limit-Text, Format-Bool, Get-Sha256Hex, `
    Assert-UnderRuntime, Resolve-LrapPaths, `
    Get-LrapIntentCatalog, Get-LrapIntentCatalogReview, Get-LrapHonestyMap, Get-LrapHonestyCell, Get-LrapP2Backlog, `
    Get-LrapStageIds, Get-LrapSelectedIds, Get-LrapExcerptIds, Get-LrapReasonCodesForId, `
    Get-LrapPacketExclusionViolations, Get-LrapUnexplainedDrops, Get-LrapTrustBannerCheck, `
    Get-LrapStepReconcile, Get-LrapStepLanes, Get-LrapSpine, Get-LrapModel, Get-LrapVerdict, `
    Get-LrapStepDescend, Get-LrapRawTraceForStep, Format-LrapHeader
