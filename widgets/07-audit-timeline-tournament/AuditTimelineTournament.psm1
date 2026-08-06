<#
    AuditTimelineTournament.psm1 - driver core for the Audit Timeline + Tournament console (Widget 07).

    The audit-pipeline tier A2 read-only slice (research/2026-08-05-audit-pipeline-target.md): the s2.6
    tool-selection TOURNAMENT pane and the s2.1 cross-context OMNISCIENT stitched TIMELINE. It trails the
    build by one tier and makes a GATE cheaper to verify; it does not chase total comprehension.

    STRICTLY READ-ONLY. It RENDERS artifacts the Tier-0/Tier-1 contracts and the fan-out runtime ALREADY
    mandate; it never instruments, never calls a model, never holds a lease, never pauses the pipeline, and
    writes NOTHING outside the widget's own runtime/ dir. non_execution holds; it enables no action. The
    ride-along PAUSE (s2.2) and delegation-tree possession (s2.7) are OUT of this tier (design-first,
    red-team-gated) -- this unit is a pure reader.

    TOURNAMENT (s2.6) -- the staged skill/module selection as elimination rounds with per-stage COUNTS +
    REASON CODES, over EXISTING traces, with a machine RECONCILIATION proof (counts must reconcile with the
    underlying stage traces):
      A  ROUTER bracket        -- evaluation_hooks.routing_stage_trace (#40 0.8.0+): classification ->
                                  routing -> channel_selection; per round candidates_in/out + removed[]
                                  {channel_id, reason_codes[]}. Reconcile: in - |removed| == out; chain
                                  out[n] == in[n+1].
      B  SELECTION bracket      -- evaluation_hooks.stages: raw_retrieval -> post_filter -> packet (semantic
                                  retrieval -> rerank -> select), with per-round counts + the omit/reason
                                  codes for eliminated candidates. Reconcile: post subset raw; packet subset
                                  post; every dropped candidate has an omit_reason.
      C  PLAN VALIDATION bracket-- the #30 fan-out deterministic plan validation (plan.json): workers ->
                                  dispatch_now (ACCEPTED) / queued (DEFERRED) / conflicts (REJECTED: the
                                  named gpu_serialized / doc_contention checks). Reconcile: |workers| ==
                                  |dispatch_now| + |queued| + |rejected|.
      (PREFLIGHT over activation cards is s2.6 FUTURE -- no skill-selection module emits it yet; rendered as
      a labeled not-yet-emitted stage, never faked.)

    CROSS-CONTEXT OMNISCIENT TIMELINE (s2.1 REVEAL) -- a single stitched timeline across contexts:
      - WAVE (a #30 plan.json + its reports/): plan_created + per-report worker_reported events, with a
        dispatched-vs-reported reconciliation.
      - EPISODES (#39): each episode's open -> per-stage -> close, stage timestamps derived from valid_from
        + cumulative duration (episodes carry durations, not absolute per-stage stamps).
      - WORKING-MEMORY state_version chains (#42): per task_id, the monotonic state_version CAS chain
        (parent_state_version linkage), rendered even without absolute timestamps.
      - BATONS: rendered when present; a graceful absence note otherwise (delegation/possession is unbuilt).
      All events stitch into ONE deterministically-sorted timeline tagged by context. One wave renders
      end-to-end. It holds NO lease -> ZERO lease-window violations by construction.

    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate (pwsh 7.4.6 on Linux,
    over committed REAL fixtures) and on Windows. The UI (Show-AuditTimelineTournament.ps1) is a thin shell
    over these functions. Shape mirrors CompileTraceConsole.psm1 / ProvenanceMap.psm1 (Widgets 06/05):
    defensive Get-Prop, List[object] + .ToArray() (never a bare @() on a maybe-null / raw List), a
    write-guarded runtime writer used for defense-in-depth only, ASCII-only SOURCE (the artifacts it PARSES
    carry non-ASCII; this source stays ASCII per the 5.1-ANSI/BOM lesson).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AttWidgetRoot = $PSScriptRoot

# The channel-only keys a router stage-trace `removed[]` entry may carry (CONTEXT_PACKET_CONTRACT s9 / i33
# U1' -- a diagnostic array is namespace-closure-sanitized: channel-only, NEVER identifying metadata).
$script:TraceForbiddenRemovedKeys = @('namespace', 'source_path', 'record_version_id', 'snippet', 'text', 'excerpt', 'path', 'body', 'content')

# The ONLY property names a stitched timeline EVENT may carry. The renderer surfaces structural / lineage /
# status fields only -- NEVER a record body, snippet, excerpt, or free text (no cross-context content
# side-channel; audit-target s4 A2 "no cross-ns identifying metadata surfaced").
$script:TimelineEventAllowedKeys = @('sort_key', 'seq', 'ts', 'context', 'source', 'kind', 'detail', 'namespace')
# Substrings that, if they appear as a FIELD NAME on a source artifact, must NOT be surfaced into a rendered
# event line (the render-side re-assertion of the i33 no-content rule).
$script:TimelineForbiddenSourceKeys = @('snippet', 'body_text', 'secret', 'raw_text', 'excerpt_text')

# ============================================================================
#  small helpers (shared shape with CompileTraceConsole.psm1 / ProvenanceMap.psm1)
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
    # Normalize a maybe-null / scalar / array value to plain elements WITHOUT the StrictMode empty-unroll or
    # array-double-wrap traps (a string stays one element). Callers ALWAYS wrap the call in @( ... ).
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
    # The property / key names of an object or dictionary as a plain string[] (0..n). Never throws.
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

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-JsonFileSafe {
    # Read + parse a JSON file DEFENSIVELY (shared read/delete access). Returns the parsed object, or $null on
    # any problem (missing / locked / empty / unparseable). Never throws.
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
    try { return ($txt | ConvertFrom-Json -Depth 80 -ErrorAction Stop) } catch { return $null }
}

function Format-Bool { param($V) if ($null -eq $V) { return 'n/a' } if ([bool]$V) { return 'yes' } return 'no' }

function Get-SortableTicks {
    # Parse an ISO-8601 UTC timestamp to Int64 UtcTicks for deterministic sorting, or $null when unparseable.
    param([string]$Iso)
    if ([string]::IsNullOrWhiteSpace($Iso)) { return $null }
    $dto = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTimeOffset]::TryParse($Iso, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) {
        return [long]$dto.UtcTicks
    }
    return $null
}

function ConvertTo-IsoUtc {
    # Normalize ANY timestamp value to a canonical culture-stable ISO-8601 UTC string
    # (yyyy-MM-ddTHH:mm:ss.fffffffZ). ConvertFrom-Json coerces ISO date-like strings to [datetime] (Kind=Utc),
    # whose default ToString is CULTURE-dependent -- so a raw [string] cast would render US-locale on one box
    # and differently on another, breaking cross-culture byte-identity. Convert from the OBJECT, honoring Kind.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        $dt = [datetime]$Value
        if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) { $dt = [datetime]::SpecifyKind($dt, [System.DateTimeKind]::Utc) }
        return ([datetimeoffset]$dt).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [datetimeoffset]) {
        return ([datetimeoffset]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $dto = [DateTimeOffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    if ([DateTimeOffset]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) {
        return $dto.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $s
}

# ============================================================================
#  path resolution
# ============================================================================

function Resolve-AuditPaths {
    <#
        Resolve the widget root, the repo root, and every read-only data source + the write-guarded runtime
        dir. -RepoRoot (or the env override LIFEORCH_ATT_REPO) points the whole console at a fixture/other
        tree so the cloud gate runs without the production repo. [IO.Path]::Combine is a pure string join so a
        foreign-platform RepoRoot ('C:\...') in a cloud-gate test does not throw "Cannot find drive 'C'".
    #>
    [CmdletBinding()]
    param([string]$WidgetRoot, [string]$RepoRoot)

    if (-not $WidgetRoot) { $WidgetRoot = $script:AttWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    if (-not $RepoRoot) {
        if ($env:LIFEORCH_ATT_REPO) { $RepoRoot = $env:LIFEORCH_ATT_REPO }
        else {
            $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
            if ($rp) { $RepoRoot = $rp.Path } else { $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }
        }
    }

    return [pscustomobject]@{
        WidgetRoot        = $WidgetRoot
        RepoRoot          = $RepoRoot
        PlansDir          = [System.IO.Path]::Combine($RepoRoot, 'modules', '30-orchestrate-fanout', 'runtime', 'plans')
        CompilerArtifacts = [System.IO.Path]::Combine($RepoRoot, 'modules', '40-context-compiler', 'runtime', 'artifacts')
        EpisodesDir       = [System.IO.Path]::Combine($RepoRoot, 'modules', '39-episode-memory', 'runtime', 'artifacts')
        WorkingMemoryDir  = [System.IO.Path]::Combine($RepoRoot, 'modules', '42-working-memory', 'runtime')
        RuntimeDir        = [System.IO.Path]::Combine($WidgetRoot, 'runtime')
    }
}

# ============================================================================
#  artifact readers (all defensive; never throw)
# ============================================================================

function Get-PacketFromObject {
    # Normalize any carrier of a context_packet to the inner packet object, or $null.
    param($Obj)
    if ($null -eq $Obj) { return $null }
    $schema = [string](Get-Prop $Obj 'schema' '')
    if ($schema -like 'lifeorch.context_packet*' -and (Test-HasProp $Obj 'packet_id')) { return $Obj }
    $result = Get-Prop $Obj 'result' $null
    if ($null -ne $result) {
        $inner = Get-Prop $result 'result' $null
        if ($null -ne $inner) { $p = Get-Prop $inner 'packet' $null; if ($null -ne $p) { return $p } }
        $p2 = Get-Prop $result 'packet' $null
        if ($null -ne $p2) { return $p2 }
    }
    $p3 = Get-Prop $Obj 'packet' $null
    if ($null -ne $p3) { return $p3 }
    return $null
}

function Read-ContextPacket {
    # Load a context packet from a file in any carrier shape -> { ok, packet, schema, packet_id,
    # compiler_version, source_path, error }. Never throws.
    [CmdletBinding()]
    param([string]$Path)
    $o = Read-JsonFileSafe -Path $Path
    if ($null -eq $o) { return [pscustomobject]@{ ok = $false; packet = $null; schema = ''; packet_id = ''; compiler_version = ''; source_path = [string]$Path; error = 'unreadable_or_missing_json' } }
    $p = Get-PacketFromObject $o
    if ($null -eq $p) { return [pscustomobject]@{ ok = $false; packet = $null; schema = ''; packet_id = ''; compiler_version = ''; source_path = [string]$Path; error = 'no_context_packet_in_artifact' } }
    $comp = Get-Prop $p 'compiler' $null
    return [pscustomobject]@{
        ok = $true; packet = $p
        schema = [string](Get-Prop $p 'schema' '')
        packet_id = [string](Get-Prop $p 'packet_id' '')
        compiler_version = [string](Get-Prop $comp 'version' '')
        source_path = [string]$Path; error = ''
    }
}

function Read-FanoutPlan {
    # Load a #30 fan-out plan.json -> { ok, plan, plan_id, iteration, created_at_utc, title, workers[],
    # dispatch_now[], queued[], conflicts, error }. Never throws.
    [CmdletBinding()]
    param([string]$Path)
    $o = Read-JsonFileSafe -Path $Path
    if ($null -eq $o) { return [pscustomobject]@{ ok = $false; plan = $null; plan_id = ''; error = 'unreadable_or_missing_json' } }
    $workers = New-Object System.Collections.Generic.List[object]
    foreach ($w in @(ConvertTo-Array (Get-Prop $o 'workers' $null))) {
        [void]$workers.Add([pscustomobject]@{
                id = [string](Get-Prop $w 'id' (Get-Prop $w 'safe_id' '?'))
                label = [string](Get-Prop $w 'label' '')
                gpu = (Get-Prop $w 'gpu' $false)
                leases = [string](Get-Prop $w 'leases' '')
            })
    }
    return [pscustomobject]@{
        ok = $true; plan = $o
        plan_id = [string](Get-Prop $o 'plan_id' '')
        iteration = [string](Get-Prop $o 'iteration' '?')
        created_at_utc = (ConvertTo-IsoUtc (Get-Prop $o 'created_at_utc' ''))
        title = [string](Get-Prop $o 'title' '')
        workers = $workers.ToArray()
        dispatch_now = @(@(ConvertTo-Array (Get-Prop $o 'dispatch_now' $null)) | ForEach-Object { [string]$_ })
        queued = @(@(ConvertTo-Array (Get-Prop $o 'queued' $null)) | ForEach-Object { [string]$_ })
        conflicts = (Get-Prop $o 'conflicts' $null)
        error = ''
    }
}

function Read-FanoutReport {
    # Load a #30 worker report -> { ok, plan_id, worker_id, state, summary, reported_at_utc, error }.
    [CmdletBinding()]
    param([string]$Path)
    $o = Read-JsonFileSafe -Path $Path
    if ($null -eq $o) { return [pscustomobject]@{ ok = $false; worker_id = ''; error = 'unreadable_or_missing_json' } }
    return [pscustomobject]@{
        ok = $true
        plan_id = [string](Get-Prop $o 'plan_id' '')
        worker_id = [string](Get-Prop $o 'worker_id' '')
        state = [string](Get-Prop $o 'state' '?')
        summary = [string](Get-Prop $o 'summary' '')
        reported_at_utc = (ConvertTo-IsoUtc (Get-Prop $o 'reported_at_utc' ''))
        error = ''
    }
}

function Read-Episode {
    # Load a #39 episode record -> { ok, record_id, task_id, namespace, valid_from, valid_to, final_status,
    # original_request, stages[]{stage_index, stage_name, role, status, duration_ms}, error }. Never throws.
    [CmdletBinding()]
    param([string]$Path)
    $o = Read-JsonFileSafe -Path $Path
    if ($null -eq $o) { return [pscustomobject]@{ ok = $false; record_id = ''; error = 'unreadable_or_missing_json' } }
    $body = Get-Prop $o 'body' $null
    $stages = New-Object System.Collections.Generic.List[object]
    foreach ($s in @(ConvertTo-Array (Get-Prop $body 'stage_sequence' $null))) {
        [void]$stages.Add([pscustomobject]@{
                stage_index = [int](Get-Prop $s 'stage_index' 0)
                stage_name = [string](Get-Prop $s 'stage_name' '?')
                role = [string](Get-Prop $s 'role' '?')
                status = [string](Get-Prop $s 'status' '?')
                duration_ms = [long](Get-Prop $s 'duration_ms' 0)
            })
    }
    return [pscustomobject]@{
        ok = $true
        record_id = [string](Get-Prop $o 'record_id' '?')
        record_kind = [string](Get-Prop $o 'record_kind' '?')
        task_id = [string](Get-Prop $body 'task_id' (Get-Prop $o 'task_id' '?'))
        namespace = [string](Get-Prop $o 'namespace' '?')
        valid_from = (ConvertTo-IsoUtc (Get-Prop $o 'valid_from' ''))
        valid_to = (ConvertTo-IsoUtc (Get-Prop $o 'valid_to' ''))
        final_status = [string](Get-Prop $body 'final_status' '?')
        original_request = [string](Get-Prop $body 'original_request' '')
        stages = $stages.ToArray()
        source_path = [string]$Path
        error = ''
    }
}

function Read-WorkingState {
    # Load a #42 working-state record (MEMORY_CONTRACT s1 working envelope) -> the fields the state_version
    # chain needs. Never throws.
    [CmdletBinding()]
    param([string]$Path)
    $o = Read-JsonFileSafe -Path $Path
    if ($null -eq $o) { return [pscustomobject]@{ ok = $false; error = 'unreadable_or_missing_json' } }
    return ConvertFrom-WorkingStateObject -Obj $o -SourcePath $Path
}

function ConvertFrom-WorkingStateObject {
    # Shared normalizer for a #42 working-state envelope (from a file or the packet's working_memory region).
    param($Obj, [string]$SourcePath = '')
    if ($null -eq $Obj) { return [pscustomobject]@{ ok = $false; error = 'null' } }
    $sv = Get-Prop $Obj 'state_version' $null
    return [pscustomobject]@{
        ok = $true
        working_state_id = [string](Get-Prop $Obj 'working_state_id' (Get-Prop $Obj 'record_id' '?'))
        record_version_id = [string](Get-Prop $Obj 'record_version_id' '?')
        task_id = [string](Get-Prop $Obj 'task_id' '?')
        namespace = [string](Get-Prop $Obj 'namespace' (Get-Prop $Obj 'namespace_scope' '?'))
        state_version = $sv
        parent_state_version = (Get-Prop $Obj 'parent_state_version' $null)
        lifecycle_state = [string](Get-Prop $Obj 'lifecycle_state' '?')
        valid_from = (ConvertTo-IsoUtc (Get-Prop $Obj 'valid_from' ''))
        source_path = [string]$SourcePath
        error = ''
    }
}

# ============================================================================
#  sanitization guards (CONTEXT_PACKET_CONTRACT s9 / i33 U1' + the timeline no-content rule)
# ============================================================================

function Get-EffectiveNamespaces {
    # The effective_allowed_namespaces the compile enforced. Plain string[].
    param($Packet)
    $idn = Get-Prop $Packet 'identity' $null
    $nc = Get-Prop $idn 'namespace_closure' $null
    $eff = @(ConvertTo-Array (Get-Prop $nc 'effective' $null))
    if ($eff.Count -gt 0) { return @($eff | ForEach-Object { [string]$_ }) }
    $ti = Get-Prop $Packet 'task_input' $null
    return @(@(ConvertTo-Array (Get-Prop $ti 'allowed_namespaces' $null)) | ForEach-Object { [string]$_ })
}

function Test-TraceSanitized {
    # Assert the R-1 router stage-trace honors i33 diagnostic-array sanitization: every removed[] entry is
    # CHANNEL-ONLY (no forbidden identifying keys). Returns { sanitized, violations[], trace_present,
    # removed_entry_count }.
    param($Packet)
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $trace = @(ConvertTo-Array (Get-Prop $eh 'routing_stage_trace' $null))
    $violations = New-Object System.Collections.Generic.List[string]
    $entryCount = 0
    foreach ($stage in $trace) {
        $sid = [string](Get-Prop $stage 'stage_id' '?')
        foreach ($rem in @(ConvertTo-Array (Get-Prop $stage 'removed' $null))) {
            $entryCount++
            foreach ($k in @(Get-PropNames $rem)) {
                if ($script:TraceForbiddenRemovedKeys -contains $k) {
                    [void]$violations.Add("stage=$sid removed-entry carries forbidden key '$k'")
                }
            }
        }
    }
    return [pscustomobject]@{
        sanitized = ($violations.Count -eq 0)
        violations = $violations.ToArray()
        trace_present = ($trace.Count -gt 0)
        removed_entry_count = $entryCount
    }
}

function Test-TimelineSanitized {
    # Assert every stitched event carries ONLY allowlisted structural fields (no record body / snippet /
    # excerpt / free text). The render-side re-assertion of the i33 no-content rule: the console must never
    # become a cross-context content side-channel. Returns { sanitized, violations[], event_count }.
    param($Events)
    $violations = New-Object System.Collections.Generic.List[string]
    $n = 0
    foreach ($e in @(ConvertTo-Array $Events)) {
        $n++
        foreach ($k in @(Get-PropNames $e)) {
            if ($script:TimelineEventAllowedKeys -notcontains $k) {
                [void]$violations.Add("event #$n carries non-allowlisted field '$k'")
            }
        }
    }
    return [pscustomobject]@{ sanitized = ($violations.Count -eq 0); violations = $violations.ToArray(); event_count = $n }
}

# ============================================================================
#  TOURNAMENT (s2.6) -- elimination brackets with a reconciliation proof
# ============================================================================

function Get-RouterTournament {
    # Bracket A: the router stage-trace as elimination rounds. Reconcile in - |removed| == out per round and
    # out[n] == in[n+1] along the chain. Returns { present, rounds[], reconciled, lines[], flags[] }.
    param($Packet)
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $trace = @(ConvertTo-Array (Get-Prop $eh 'routing_stage_trace' $null))
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $rounds = New-Object System.Collections.Generic.List[object]

    if ($trace.Count -eq 0) {
        [void]$lines.Add('   (flat compile -- router not engaged; no routing_stage_trace to bracket)')
        return [pscustomobject]@{ present = $false; rounds = @(); reconciled = $true; lines = $lines.ToArray(); flags = $flags.ToArray() }
    }

    $reconciled = $true
    $prevOut = $null
    $roundNo = 0
    foreach ($st in $trace) {
        $roundNo++
        $sid = [string](Get-Prop $st 'stage_id' '?')
        $cin = [int](Get-Prop $st 'candidates_in' 0)
        $cout = [int](Get-Prop $st 'candidates_out' 0)
        $removed = @(ConvertTo-Array (Get-Prop $st 'removed' $null))
        $policy = [string](Get-Prop $st 'policy_id' '?') + '/' + [string](Get-Prop $st 'policy_version' '?')
        $countOk = (($cin - $removed.Count) -eq $cout)
        $chainOk = ($null -eq $prevOut) -or ($prevOut -eq $cin)
        if (-not $countOk) { $reconciled = $false; [void]$flags.Add("router round '$sid': in($cin) - removed($($removed.Count)) != out($cout)") }
        if (-not $chainOk) { $reconciled = $false; [void]$flags.Add("router chain break at '$sid': prev out($prevOut) != in($cin)") }

        [void]$rounds.Add([pscustomobject]@{ stage_id = $sid; candidates_in = $cin; candidates_out = $cout; removed_count = $removed.Count; count_ok = $countOk; chain_ok = $chainOk })
        $recWord = if ($countOk -and $chainOk) { 'RECONCILED' } else { 'MISMATCH' }
        [void]$lines.Add(('   round {0}: {1,-18} in={2,3}  -{3,-2} eliminated  -> out={4,-3}  [{5}]  policy={6}' -f $roundNo, $sid, $cin, $removed.Count, $cout, $recWord, $policy))
        foreach ($rem in $removed) {
            $who = [string](Get-Prop $rem 'channel_id' (Get-Prop $rem 'record_id' '?'))
            $rc = @(@(ConvertTo-Array (Get-Prop $rem 'reason_codes' $null)) | ForEach-Object { [string]$_ })
            [void]$lines.Add(('        x {0,-22} :: {1}' -f (Limit-Text $who 22), ($rc -join ', ')))
        }
        $prevOut = $cout
    }
    return [pscustomobject]@{ present = $true; rounds = $rounds.ToArray(); reconciled = $reconciled; lines = $lines.ToArray(); flags = $flags.ToArray() }
}

function Get-SelectionTournament {
    # Bracket B: the selpol stages as elimination rounds (raw_retrieval -> post_filter -> packet). Reconcile
    # post subset raw, packet subset post, and every dropped candidate carries an omit_reason in retrieved[].
    param($Packet)
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $stages = Get-Prop $eh 'stages' $null
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]

    $raw = @(@(ConvertTo-Array (Get-Prop $stages 'raw_retrieval' $null)) | ForEach-Object { [string](Get-Prop $_ 'record_version_id' '?') })
    $post = @(@(ConvertTo-Array (Get-Prop $stages 'post_filter' $null)) | ForEach-Object { [string](Get-Prop $_ 'record_version_id' '?') })
    $pkt = @(@(ConvertTo-Array (Get-Prop $stages 'packet' $null)) | ForEach-Object { [string](Get-Prop $_ 'record_version_id' '?') })

    if ($raw.Count -eq 0 -and $post.Count -eq 0 -and $pkt.Count -eq 0) {
        [void]$lines.Add('   (no selpol stages emitted in evaluation_hooks.stages)')
        return [pscustomobject]@{ present = $false; reconciled = $true; lines = $lines.ToArray(); flags = $flags.ToArray(); raw = 0; post = 0; packet = 0 }
    }

    # omit_reason lookup from retrieved[]
    $omitByRvid = @{}
    foreach ($r in @(ConvertTo-Array (Get-Prop $eh 'retrieved' $null))) {
        $rvid = [string](Get-Prop $r 'record_version_id' (Get-Prop $r 'record_id' '?'))
        $omit = Get-Prop $r 'omit_reason' $null
        $sel = Get-Prop $r 'selected' $null
        $omitByRvid[$rvid] = [pscustomobject]@{ omit = $omit; selected = $sel }
    }

    $postSubset = $true; foreach ($x in $post) { if ($raw -notcontains $x) { $postSubset = $false } }
    $pktSubset = $true; foreach ($x in $pkt) { if ($post -notcontains $x) { $pktSubset = $false } }
    $droppedRawPost = @($raw | Where-Object { $post -notcontains $_ })
    $droppedPostPkt = @($post | Where-Object { $pkt -notcontains $_ })

    if (-not $postSubset) { [void]$flags.Add('selection: post_filter is NOT a subset of raw_retrieval') }
    if (-not $pktSubset) { [void]$flags.Add('selection: packet is NOT a subset of post_filter') }

    # every dropped candidate must be explained (an omit_reason OR selected=false in retrieved[])
    $dropExplained = $true
    foreach ($d in @($droppedRawPost + $droppedPostPkt)) {
        $info = $omitByRvid[$d]
        $hasReason = ($null -ne $info -and ($null -ne $info.omit -or $info.selected -eq $false))
        if (-not $hasReason) { $dropExplained = $false; [void]$flags.Add("selection: dropped candidate '$d' has no omit_reason") }
    }
    $reconciled = ($postSubset -and $pktSubset -and $dropExplained)

    $recWord1 = if ($postSubset) { 'RECONCILED' } else { 'MISMATCH' }
    $recWord2 = if ($pktSubset) { 'RECONCILED' } else { 'MISMATCH' }
    [void]$lines.Add(('   round 1: {0,-18} candidates={1,3}' -f 'raw_retrieval', $raw.Count))
    [void]$lines.Add(('   round 2: {0,-18} candidates={1,3}  (-{2} filtered)  [{3}]' -f 'post_filter', $post.Count, $droppedRawPost.Count, $recWord1))
    foreach ($d in $droppedRawPost) {
        $info = $omitByRvid[$d]; $why = if ($null -ne $info -and $null -ne $info.omit) { [string]$info.omit } else { 'not_selected' }
        [void]$lines.Add(('        x {0,-30} :: {1}' -f (Limit-Text $d 30), $why))
    }
    [void]$lines.Add(('   round 3: {0,-18} selected  ={1,3}  (-{2} dropped)   [{3}]' -f 'packet', $pkt.Count, $droppedPostPkt.Count, $recWord2))
    foreach ($d in $droppedPostPkt) {
        $info = $omitByRvid[$d]; $why = if ($null -ne $info -and $null -ne $info.omit) { [string]$info.omit } else { 'not_selected' }
        [void]$lines.Add(('        x {0,-30} :: {1}' -f (Limit-Text $d 30), $why))
    }
    return [pscustomobject]@{ present = $true; reconciled = $reconciled; lines = $lines.ToArray(); flags = $flags.ToArray(); raw = $raw.Count; post = $post.Count; packet = $pkt.Count }
}

function Get-PlanValidationTournament {
    # Bracket C: the #30 fan-out deterministic plan validation as an accept/defer/reject bracket. Reconcile
    # |workers| == |dispatch_now| + |queued| + |rejected|; name the failed checks (conflicts).
    param($Plan)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Plan -or -not $Plan.ok) {
        [void]$lines.Add('   (no fan-out plan provided -- plan-validation bracket omitted)')
        return [pscustomobject]@{ present = $false; reconciled = $true; lines = $lines.ToArray(); flags = $flags.ToArray() }
    }
    $workerIds = @($Plan.workers | ForEach-Object { [string]$_.id })
    $dispatch = @($Plan.dispatch_now)
    $queued = @($Plan.queued)
    $conflicts = $Plan.conflicts
    $gpuSer = @(@(ConvertTo-Array (Get-Prop $conflicts 'gpu_serialized' $null)) | ForEach-Object { [string]$_ })
    $docCon = @(@(ConvertTo-Array (Get-Prop $conflicts 'doc_contention' $null)) | ForEach-Object { [string]$_ })
    $rejected = @(@($gpuSer + $docCon) | Select-Object -Unique)

    $accountedFor = $dispatch.Count + $queued.Count + $rejected.Count
    $countOk = ($workerIds.Count -eq $accountedFor)
    if (-not $countOk) { [void]$flags.Add("plan-validation: workers($($workerIds.Count)) != dispatch($($dispatch.Count)) + queued($($queued.Count)) + rejected($($rejected.Count))") }
    # every dispatched id must be a real worker
    $dispKnown = $true; foreach ($d in $dispatch) { if ($workerIds -notcontains $d) { $dispKnown = $false; [void]$flags.Add("plan-validation: dispatched id '$d' is not a declared worker") } }
    $reconciled = ($countOk -and $dispKnown)
    $recWord = if ($reconciled) { 'RECONCILED' } else { 'MISMATCH' }

    [void]$lines.Add(('   deterministic plan validation ({0}):  workers={1}  [{2}]' -f $Plan.plan_id, $workerIds.Count, $recWord))
    [void]$lines.Add(('      ACCEPTED (dispatch_now) = {0}' -f $dispatch.Count))
    foreach ($d in $dispatch) { [void]$lines.Add(('         + {0}' -f (Limit-Text $d 48))) }
    [void]$lines.Add(('      DEFERRED (queued)       = {0}' -f $queued.Count))
    foreach ($q in $queued) { [void]$lines.Add(('         ~ {0}' -f (Limit-Text $q 48))) }
    [void]$lines.Add(('      REJECTED (conflicts)    = {0}   gpu_serialized={1} doc_contention={2}' -f $rejected.Count, $gpuSer.Count, $docCon.Count))
    foreach ($r in $rejected) { [void]$lines.Add(('         x {0}' -f (Limit-Text $r 48))) }
    return [pscustomobject]@{ present = $true; reconciled = $reconciled; lines = $lines.ToArray(); flags = $flags.ToArray(); workers = $workerIds.Count; accepted = $dispatch.Count; deferred = $queued.Count; rejected = $rejected.Count }
}

function Get-TournamentPane {
    # Assemble the whole tournament pane over a packet (+ optional plan). Returns { header, lines[], flags[],
    # reconciled, counts }.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet, $Plan)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]

    $router = Get-RouterTournament -Packet $Packet
    $selection = Get-SelectionTournament -Packet $Packet
    $planval = Get-PlanValidationTournament -Plan $Plan

    [void]$lines.Add('== BRACKET A: ROUTER (evaluation_hooks.routing_stage_trace; classification -> routing -> channel_selection) ==')
    foreach ($l in @($router.lines)) { [void]$lines.Add($l) }
    [void]$lines.Add('')
    [void]$lines.Add('== BRACKET B: SELECTION (evaluation_hooks.stages; semantic retrieval -> rerank -> select) ==')
    foreach ($l in @($selection.lines)) { [void]$lines.Add($l) }
    [void]$lines.Add('')
    [void]$lines.Add('== (s2.6 FUTURE) PREFLIGHT over activation cards -- NOT yet emitted (no skill-selection module emits R-1 traces; s2.7 delegation-trigger vocabulary reserved) ==')
    [void]$lines.Add('')
    [void]$lines.Add('== BRACKET C: PLAN VALIDATION (#30 deterministic fan-out dispatch gate; accepted / deferred / rejected-with-named-checks) ==')
    foreach ($l in @($planval.lines)) { [void]$lines.Add($l) }
    [void]$lines.Add('')

    foreach ($f in @($router.flags)) { [void]$flags.Add($f) }
    foreach ($f in @($selection.flags)) { [void]$flags.Add($f) }
    foreach ($f in @($planval.flags)) { [void]$flags.Add($f) }

    $reconciled = ($router.reconciled -and $selection.reconciled -and $planval.reconciled)
    $rlist = New-Object System.Collections.Generic.List[string]
    [void]$rlist.Add('router=' + (Format-Bool $router.reconciled))
    [void]$rlist.Add('selection=' + (Format-Bool $selection.reconciled))
    [void]$rlist.Add('plan_validation=' + (Format-Bool $planval.reconciled))
    [void]$lines.Add('RECONCILIATION: ' + ($rlist.ToArray() -join '  ') + '   =>  OVERALL ' + $(if ($reconciled) { 'RECONCILED' } else { 'MISMATCH (see Flags)' }))

    $counts = [ordered]@{
        router_rounds = @($router.rounds).Count
        router_present = $router.present
        selection_raw = $selection.raw
        selection_packet = $selection.packet
        plan_validation_present = $planval.present
    }
    return [pscustomobject]@{
        header = 'tool-selection tournament (elimination rounds; per-stage counts + reason codes; counts RECONCILE with the stage traces)'
        lines = $lines.ToArray(); flags = $flags.ToArray(); reconciled = $reconciled
        router = $router; selection = $selection; plan_validation = $planval; counts = $counts
    }
}

# ============================================================================
#  CROSS-CONTEXT OMNISCIENT TIMELINE (s2.1) -- stitched, deterministically sorted
# ============================================================================

function New-TimelineEvent {
    # A single stitched event -- FIXED allowlisted shape only (see $TimelineEventAllowedKeys). No record body,
    # snippet, or free text ever enters an event (the i33 no-content rule).
    param([string]$Ts, [string]$Context, [string]$Source, [string]$Kind, [string]$Detail, [string]$Namespace, [long]$Seq)
    $ticks = Get-SortableTicks -Iso $Ts
    $sortKey = if ($null -ne $ticks) { [long]$ticks } else { [long]::MaxValue }
    return [pscustomobject]@{
        sort_key = $sortKey
        seq = $Seq
        ts = if ([string]::IsNullOrWhiteSpace($Ts)) { '' } else { [string]$Ts }
        context = [string]$Context
        source = [string]$Source
        kind = [string]$Kind
        detail = [string]$Detail
        namespace = [string]$Namespace
    }
}

function Get-WaveEvents {
    # Emit the wave (plan + reports) events + the dispatched-vs-reported reconciliation. Returns
    # { events[], reconcile{...}, lines_preface[] }.
    param($Plan, $Reports, [ref]$SeqRef)
    $events = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Plan -or -not $Plan.ok) {
        return [pscustomobject]@{ events = @(); reconcile = [pscustomobject]@{ ok = $false; note = 'no plan' } }
    }
    $planId = $Plan.plan_id
    $s = $SeqRef.Value; $s++
    [void]$events.Add((New-TimelineEvent -Ts $Plan.created_at_utc -Context ('wave:' + $planId) -Source 'plan' -Kind 'plan_created' -Detail ('iteration ' + [string]$Plan.iteration + '  workers=' + @($Plan.workers).Count + '  dispatch_now=' + @($Plan.dispatch_now).Count) -Namespace '' -Seq $s))

    $reportedIds = New-Object System.Collections.Generic.List[string]
    foreach ($rep in @(ConvertTo-Array $Reports)) {
        if (-not $rep.ok) { continue }
        [void]$reportedIds.Add($rep.worker_id)
        $s++
        [void]$events.Add((New-TimelineEvent -Ts $rep.reported_at_utc -Context ('wave:' + $planId + '/worker:' + $rep.worker_id) -Source 'report' -Kind ('report:' + $rep.state) -Detail (Limit-Text $rep.summary 100) -Namespace '' -Seq $s))
        if ($rep.plan_id -and $rep.plan_id -ne $planId) { }
    }
    $SeqRef.Value = $s

    $dispatch = @($Plan.dispatch_now)
    $workerIds = @($Plan.workers | ForEach-Object { [string]$_.id })
    $missing = @($dispatch | Where-Object { $reportedIds -notcontains $_ })
    $orphans = @($reportedIds | Where-Object { $workerIds -notcontains $_ })
    $planMismatch = @()
    foreach ($rep in @(ConvertTo-Array $Reports)) { if ($rep.ok -and $rep.plan_id -and $rep.plan_id -ne $planId) { $planMismatch += $rep.worker_id } }
    $reconcile = [pscustomobject]@{
        ok = ($missing.Count -eq 0 -and $orphans.Count -eq 0 -and @($planMismatch).Count -eq 0)
        dispatched = $dispatch.Count
        reported = $reportedIds.Count
        missing = $missing
        orphans = $orphans
        plan_id_mismatch = @($planMismatch)
    }
    return [pscustomobject]@{ events = $events.ToArray(); reconcile = $reconcile }
}

function Get-EpisodeEvents {
    # Emit per-episode open -> stage -> close events. Stage timestamps are derived from valid_from + the
    # cumulative stage duration (episodes carry durations, not absolute per-stage stamps).
    param($Episodes, [ref]$SeqRef)
    $events = New-Object System.Collections.Generic.List[object]
    $s = $SeqRef.Value
    foreach ($ep in @(ConvertTo-Array $Episodes)) {
        if (-not $ep.ok) { continue }
        $ctx = 'episode:' + $ep.record_id
        $baseTicks = Get-SortableTicks -Iso $ep.valid_from
        $s++
        [void]$events.Add((New-TimelineEvent -Ts $ep.valid_from -Context $ctx -Source 'episode' -Kind 'episode_open' -Detail ('task=' + (Limit-Text $ep.task_id 30) + '  stages=' + @($ep.stages).Count + '  final=' + $ep.final_status) -Namespace $ep.namespace -Seq $s))
        $cum = [long]0
        foreach ($st in @($ep.stages)) {
            $stTs = ''
            if ($null -ne $baseTicks) {
                $stTicks = [long]$baseTicks + ($cum * [long]10000)   # ms -> ticks (1 ms = 10000 ticks)
                $stTs = ([DateTimeOffset]::new($stTicks, [TimeSpan]::Zero)).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
            }
            $s++
            [void]$events.Add((New-TimelineEvent -Ts $stTs -Context $ctx -Source 'episode' -Kind ('stage:' + $st.stage_name) -Detail ('role=' + $st.role + '  status=' + $st.status + '  dur_ms=' + [string]$st.duration_ms) -Namespace $ep.namespace -Seq $s))
            $cum += [long]$st.duration_ms
        }
        $s++
        [void]$events.Add((New-TimelineEvent -Ts $ep.valid_to -Context $ctx -Source 'episode' -Kind 'episode_close' -Detail ('final_status=' + $ep.final_status) -Namespace $ep.namespace -Seq $s))
    }
    $SeqRef.Value = $s
    return $events.ToArray()
}

function Get-WorkingStateEvents {
    # Emit the #42 state_version chain per task_id (monotonic CAS chain; parent_state_version linkage).
    # Ordered by state_version within a task even when absolute timestamps are absent.
    param($States, [ref]$SeqRef)
    $events = New-Object System.Collections.Generic.List[object]
    $s = $SeqRef.Value
    # group by task_id, order by state_version
    $byTask = @{}
    foreach ($ws in @(ConvertTo-Array $States)) {
        if (-not $ws.ok) { continue }
        $t = [string]$ws.task_id
        if (-not $byTask.ContainsKey($t)) { $byTask[$t] = New-Object System.Collections.Generic.List[object] }
        [void]$byTask[$t].Add($ws)
    }
    foreach ($t in ($byTask.Keys | Sort-Object)) {
        $ordered = @($byTask[$t] | Sort-Object { [int](Get-Prop $_ 'state_version' 0) })
        foreach ($ws in $ordered) {
            $s++
            $sv = [string]$ws.state_version
            $parent = if ($null -eq $ws.parent_state_version) { '(root)' } else { [string]$ws.parent_state_version }
            [void]$events.Add((New-TimelineEvent -Ts $ws.valid_from -Context ('working_memory:' + $t) -Source 'working_memory' -Kind ('state_v' + $sv) -Detail ('lifecycle=' + $ws.lifecycle_state + '  parent=' + $parent + '  rvid=' + (Limit-Text $ws.record_version_id 24)) -Namespace $ws.namespace -Seq $s))
        }
    }
    $SeqRef.Value = $s
    return $events.ToArray()
}

function Get-StitchedTimeline {
    <#
        Stitch wave + episode + working-memory (+ baton, when present) events into ONE deterministically
        sorted timeline. Sort by (sort_key ascending, seq ascending) -- both integers, so the order is total
        and byte-stable (no reliance on Sort-Object stability). Returns { ok, events[], header, lines[],
        flags[], reconcile{...}, lease{...}, counts{...} }.
    #>
    [CmdletBinding()]
    param($Plan, $Reports, $Episodes, $States, $Batons)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $seq = [long]0
    $seqRef = [ref]$seq

    $wave = Get-WaveEvents -Plan $Plan -Reports $Reports -SeqRef $seqRef
    $epEvents = Get-EpisodeEvents -Episodes $Episodes -SeqRef $seqRef
    $wsEvents = Get-WorkingStateEvents -States $States -SeqRef $seqRef

    $all = New-Object System.Collections.Generic.List[object]
    foreach ($e in @($wave.events)) { [void]$all.Add($e) }
    foreach ($e in @($epEvents)) { [void]$all.Add($e) }
    foreach ($e in @($wsEvents)) { [void]$all.Add($e) }

    # total deterministic order: composite string key "sortTicks|seq", both zero-padded
    $sorted = @($all.ToArray() | Sort-Object { '{0:D19}|{1:D9}' -f [long]$_.sort_key, [long]$_.seq })

    # span (first / last DATED event)
    $dated = @($sorted | Where-Object { $_.sort_key -ne [long]::MaxValue })
    $spanFrom = if ($dated.Count -gt 0) { [string]$dated[0].ts } else { '' }
    $spanTo = if ($dated.Count -gt 0) { [string]$dated[$dated.Count - 1].ts } else { '' }

    # render the stitched timeline
    foreach ($e in $sorted) {
        $tsShown = if ([string]::IsNullOrWhiteSpace($e.ts)) { '(no-ts, CAS-ordered)      ' } else { $e.ts }
        [void]$lines.Add(('{0,-30} {1,-34} {2,-20} {3}' -f $tsShown, (Limit-Text $e.context 34), (Limit-Text $e.kind 20), $e.detail))
    }
    if ($sorted.Length -eq 0) { [void]$lines.Add('(no events -- no wave, episodes, or working-memory chains found)') }

    # batons (absent by design at this tier)
    [void]$lines.Add('')
    $batonList = @(ConvertTo-Array $Batons)
    if ($batonList.Count -eq 0) {
        [void]$lines.Add('BATONS: none present (delegation/possession is unbuilt -- s2.7 / A3 FUTURE; rendered gracefully).')
    }
    else {
        [void]$lines.Add('BATONS: ' + $batonList.Count + ' present')
    }

    # wave reconciliation surface
    if ($null -ne $wave.reconcile -and (Get-Prop $wave.reconcile 'ok' $null) -ne $null) {
        if (-not $wave.reconcile.ok) {
            if (@($wave.reconcile.missing).Count -gt 0) { [void]$flags.Add('wave: dispatched-but-unreported: ' + (@($wave.reconcile.missing) -join ', ')) }
            if (@($wave.reconcile.orphans).Count -gt 0) { [void]$flags.Add('wave: reported-but-undeclared (orphan): ' + (@($wave.reconcile.orphans) -join ', ')) }
            if (@($wave.reconcile.plan_id_mismatch).Count -gt 0) { [void]$flags.Add('wave: report plan_id mismatch: ' + (@($wave.reconcile.plan_id_mismatch) -join ', ')) }
        }
    }

    # sanitization of the stitched events (no cross-context content leaked)
    $san = Test-TimelineSanitized -Events $sorted
    if (-not $san.sanitized) { foreach ($v in @($san.violations)) { [void]$flags.Add('TIMELINE-SANITIZATION: ' + $v) } }

    $reconcile = [pscustomobject]@{
        wave = $wave.reconcile
        stitched_ok = ($null -ne $Plan -and $Plan.ok -and @($wave.events).Count -ge 1)
    }
    # the widget holds NO lease and defines NO pause point -> zero lease-window boundaries crossed.
    $lease = [pscustomobject]@{ holds = $false; pause_points = 0; window_violations = 0 }

    $counts = [ordered]@{
        total_events = $sorted.Length
        wave_events = @($wave.events).Count
        episode_events = @($epEvents).Count
        working_state_events = @($wsEvents).Count
        baton_count = $batonList.Count
    }
    return [pscustomobject]@{
        ok = $true
        events = $sorted
        header = 'cross-context OMNISCIENT stitched timeline (wave + episodes + state_version chains + batons; one wave end-to-end; holds NO lease)'
        lines = $lines.ToArray(); flags = $flags.ToArray()
        reconcile = $reconcile; lease = $lease; sanitize = $san
        wave_plan_id = if ($null -ne $Plan -and $Plan.ok) { $Plan.plan_id } else { '' }
        span_from = $spanFrom; span_to = $spanTo; counts = $counts
    }
}

# ============================================================================
#  the whole model -- tournament + timeline + sanitization + header
# ============================================================================

function Get-AuditModel {
    <#
        Build the full audit model: the s2.6 tournament (over a packet + optional plan) and the s2.1 stitched
        timeline (over a wave plan + reports + episodes + working states + batons). Never throws to the UI: a
        failure yields a well-formed ok=false model the header renders. READ-ONLY.
    #>
    [CmdletBinding()]
    param(
        [string]$PacketPath,
        [string]$PlanPath,
        [string[]]$ReportPaths,
        [string[]]$EpisodePaths,
        [string[]]$WorkingStatePaths,
        [string[]]$BatonPaths,
        [string]$RepoRoot,
        [string]$WidgetRoot
    )
    $flags = New-Object System.Collections.Generic.List[string]

    # --- tournament source: the packet (+ plan for bracket C) ---
    $rd = Read-ContextPacket -Path $PacketPath
    $plan = if ($PlanPath) { Read-FanoutPlan -Path $PlanPath } else { $null }

    $tournament = $null; $sanitizeTrace = $null
    if ($rd.ok) {
        try {
            $tournament = Get-TournamentPane -Packet $rd.packet -Plan $plan
            foreach ($f in @($tournament.flags)) { [void]$flags.Add([string]$f) }
        }
        catch { [void]$flags.Add('tournament build threw: ' + $_.Exception.Message) }
        try {
            $sanitizeTrace = Test-TraceSanitized -Packet $rd.packet
            if (-not $sanitizeTrace.sanitized) { foreach ($v in @($sanitizeTrace.violations)) { [void]$flags.Add('SANITIZATION: ' + $v) } }
        }
        catch { [void]$flags.Add('trace sanitize threw: ' + $_.Exception.Message) }
    }
    else { [void]$flags.Add('tournament packet load failed: ' + $rd.error) }

    # --- timeline sources ---
    $reports = New-Object System.Collections.Generic.List[object]
    foreach ($rp in @(ConvertTo-Array $ReportPaths)) { [void]$reports.Add((Read-FanoutReport -Path ([string]$rp))) }
    $episodes = New-Object System.Collections.Generic.List[object]
    foreach ($ep in @(ConvertTo-Array $EpisodePaths)) { [void]$episodes.Add((Read-Episode -Path ([string]$ep))) }
    $states = New-Object System.Collections.Generic.List[object]
    foreach ($ws in @(ConvertTo-Array $WorkingStatePaths)) { [void]$states.Add((Read-WorkingState -Path ([string]$ws))) }
    # also hydrate a state event from the packet's working_memory region if present + carrying a state_version
    if ($rd.ok) {
        $wm = Get-Prop $rd.packet 'working_memory' $null
        if ($null -ne $wm -and (Get-Prop $wm 'present' $false) -eq $true -and $null -ne (Get-Prop $wm 'state_version' $null)) {
            [void]$states.Add((ConvertFrom-WorkingStateObject -Obj $wm -SourcePath ($PacketPath + '#working_memory')))
        }
    }
    $batons = New-Object System.Collections.Generic.List[object]
    foreach ($bp in @(ConvertTo-Array $BatonPaths)) { $b = Read-JsonFileSafe -Path ([string]$bp); if ($null -ne $b) { [void]$batons.Add($b) } }

    $timeline = $null
    try {
        $timeline = Get-StitchedTimeline -Plan $plan -Reports $reports.ToArray() -Episodes $episodes.ToArray() -States $states.ToArray() -Batons $batons.ToArray()
        foreach ($f in @($timeline.flags)) { [void]$flags.Add([string]$f) }
    }
    catch { [void]$flags.Add('timeline build threw: ' + $_.Exception.Message) }

    $sanitize = [pscustomobject]@{
        trace = $sanitizeTrace
        timeline = if ($null -ne $timeline) { $timeline.sanitize } else { $null }
        trace_sanitized = if ($null -ne $sanitizeTrace) { $sanitizeTrace.sanitized } else { $null }
        timeline_sanitized = if ($null -ne $timeline -and $null -ne $timeline.sanitize) { $timeline.sanitize.sanitized } else { $null }
    }

    $ok = ($null -ne $tournament -or ($null -ne $timeline -and @($timeline.events).Count -gt 0))

    return [pscustomobject]@{
        ok = $ok
        error = if ($ok) { '' } else { 'no renderable tournament or timeline source' }
        packet_ok = $rd.ok
        packet_id = $rd.packet_id
        schema = $rd.schema
        compiler_version = $rd.compiler_version
        packet_source = [string]$PacketPath
        tournament = $tournament
        timeline = $timeline
        plan = $plan
        sanitize = $sanitize
        reconciled = [pscustomobject]@{
            tournament = if ($null -ne $tournament) { $tournament.reconciled } else { $null }
            timeline_wave = if ($null -ne $timeline -and $null -ne $timeline.reconcile -and $null -ne $timeline.reconcile.wave) { (Get-Prop $timeline.reconcile.wave 'ok' $null) } else { $null }
        }
        flags = $flags.ToArray()
    }
}

function Format-AuditHeader {
    # The header block + a one-line summary a UI status bar / the gate assert on.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model)
    $h = New-Object System.Collections.Generic.List[string]
    if (-not $Model.ok) {
        [void]$h.Add('AUDIT TIMELINE + TOURNAMENT -- nothing to render: ' + [string]$Model.error)
        return [pscustomobject]@{ header_lines = $h.ToArray(); summary_line = [string]$Model.error }
    }
    $tRec = if ($null -ne $Model.tournament) { Format-Bool $Model.tournament.reconciled } else { 'n/a' }
    $wave = if ($null -ne $Model.timeline) { [string]$Model.timeline.wave_plan_id } else { '(none)' }
    $evc = if ($null -ne $Model.timeline) { [string]$Model.timeline.counts.total_events } else { '0' }
    $tSan = if ($null -ne $Model.sanitize.trace_sanitized) { if ($Model.sanitize.trace_sanitized) { 'sanitized' } else { 'SANITIZATION-FLAG' } } else { 'n/a' }
    $tlSan = if ($null -ne $Model.sanitize.timeline_sanitized) { if ($Model.sanitize.timeline_sanitized) { 'sanitized' } else { 'SANITIZATION-FLAG' } } else { 'n/a' }
    [void]$h.Add('AUDIT TIMELINE + TOURNAMENT (widget 07, tier A2)   packet_id=' + $Model.packet_id + '   schema=' + $Model.schema)
    [void]$h.Add('TOURNAMENT reconciled=' + $tRec + '  (router/selection/plan-validation)   trace_diagnostics=' + $tSan)
    [void]$h.Add('TIMELINE wave=' + $wave + '  events=' + $evc + '   holds_lease=no  lease_window_violations=0   events_diagnostics=' + $tlSan)
    if (@($Model.flags).Count -gt 0) { [void]$h.Add('flags: ' + (@($Model.flags).Count) + ' -- see Flags tab') }
    $summary = 'tournament ' + $tRec + ' | wave ' + $wave + ' (' + $evc + ' events) | ' + $tSan + '/' + $tlSan
    return [pscustomobject]@{ header_lines = $h.ToArray(); summary_line = $summary }
}

# ============================================================================
#  write-guard (defense-in-depth) -- the render path writes NOTHING; this exists so any FUTURE runtime write
#  (a persisted "new since last wave" marker) cannot escape the widget's own runtime dir.
# ============================================================================

function Assert-UnderRuntime {
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$RuntimeDir)
    $runtimeFull = [System.IO.Path]::GetFullPath($RuntimeDir)
    $targetFull = [System.IO.Path]::GetFullPath($Target)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $guard = $runtimeFull.TrimEnd($sep) + $sep
    if (-not $targetFull.StartsWith($guard, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Audit Timeline + Tournament refused a write to '$targetFull' -- outside the widget runtime dir '$runtimeFull' (read-only guard)."
    }
    return $targetFull
}

# ============================================================================
#  discovery helpers (read-only; used by the UI to pick real defaults on the box)
# ============================================================================

function Find-NewestRoutedPacket {
    # Newest #40 cc_meta.json that CARRIES a packet AND has a routing_stage_trace (for a rich tournament).
    param([string]$ArtifactsDir)
    if (-not (Test-Path -LiteralPath $ArtifactsDir -PathType Container)) { return $null }
    $fallback = $null
    foreach ($cand in @(Get-ChildItem -LiteralPath $ArtifactsDir -Recurse -File -Filter 'cc_meta.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
        $rd = Read-ContextPacket -Path $cand.FullName
        if ($rd.ok) {
            if ($null -eq $fallback) { $fallback = $cand.FullName }
            $eh = Get-Prop $rd.packet 'evaluation_hooks' $null
            if (@(ConvertTo-Array (Get-Prop $eh 'routing_stage_trace' $null)).Count -gt 0) { return $cand.FullName }
        }
    }
    return $fallback
}

function Find-NewestCompleteWave {
    # Newest plan dir (by plan.json mtime) that has at least one report. Returns { plan_path, report_paths[] }
    # or $null.
    param([string]$PlansDir)
    if (-not (Test-Path -LiteralPath $PlansDir -PathType Container)) { return $null }
    foreach ($d in @(Get-ChildItem -LiteralPath $PlansDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $planPath = Join-Path $d.FullName 'plan.json'
        $repDir = Join-Path $d.FullName 'reports'
        if ((Test-Path -LiteralPath $planPath -PathType Leaf) -and (Test-Path -LiteralPath $repDir -PathType Container)) {
            $reps = @(Get-ChildItem -LiteralPath $repDir -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
            if ($reps.Count -gt 0) { return [pscustomobject]@{ plan_path = $planPath; report_paths = $reps; plan_id = $d.Name } }
        }
    }
    return $null
}

function Find-Episodes {
    # Up to -Max newest episode.json files under the #39 artifacts dir. Read-only discovery.
    param([string]$EpisodesDir, [int]$Max = 6)
    if (-not (Test-Path -LiteralPath $EpisodesDir -PathType Container)) { return @() }
    $acc = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $EpisodesDir -Recurse -File -Filter 'episode.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
        if ($acc.Count -ge $Max) { break }
        [void]$acc.Add($f.FullName)
    }
    return $acc.ToArray()
}

function Find-WorkingStates {
    # Working-state envelopes under the #42 runtime dir (state.json / *.state.json). Read-only discovery.
    param([string]$WorkingMemoryDir, [int]$Max = 20)
    if (-not (Test-Path -LiteralPath $WorkingMemoryDir -PathType Container)) { return @() }
    $acc = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $WorkingMemoryDir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'state.json' -or $_.Name -like '*.state.json' } | Sort-Object FullName)) {
        if ($acc.Count -ge $Max) { break }
        [void]$acc.Add($f.FullName)
    }
    return $acc.ToArray()
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Prop, ConvertTo-Array, Get-PropNames, Limit-Text, Get-Sha256Hex, `
    Read-JsonFileSafe, Format-Bool, Get-SortableTicks, ConvertTo-IsoUtc, Resolve-AuditPaths, `
    Get-PacketFromObject, Read-ContextPacket, Read-FanoutPlan, Read-FanoutReport, Read-Episode, `
    Read-WorkingState, ConvertFrom-WorkingStateObject, `
    Get-EffectiveNamespaces, Test-TraceSanitized, Test-TimelineSanitized, `
    Get-RouterTournament, Get-SelectionTournament, Get-PlanValidationTournament, Get-TournamentPane, `
    New-TimelineEvent, Get-WaveEvents, Get-EpisodeEvents, Get-WorkingStateEvents, Get-StitchedTimeline, `
    Get-AuditModel, Format-AuditHeader, Assert-UnderRuntime, `
    Find-NewestRoutedPacket, Find-NewestCompleteWave, Find-Episodes, Find-WorkingStates
