<#
    CompileTraceConsole.psm1 - driver core for the Compile Trace Console (Widget 06).

    The compile/eval-trace altitude of the audit funnel (audit-pipeline tier A1, s2.1 panes 1-4,6 + the
    s2.5a compile-layer counterfactual runner). A STRICTLY READ-ONLY renderer over the artifacts the
    Tier-0/Tier-1 contracts ALREADY mandate: it READS a lifeorch.context_packet/0.2 (a real #40 0.8.0/0.9.0
    compile artifact) plus, optionally, a #37 eval report / the i36 rehearsal report / a D-0077 fold-smoke
    log, and turns them into the five panes. It RENDERS; it never instruments. It never edits #40/#37/#42/#43
    or any core-doc, never calls a model, never holds a lease. The ONLY thing it writes is under the widget's
    OWN runtime/ dir (the compile-layer counterfactual runner's re-compile scratch + diffs), guarded so it can
    never escape that dir.

    Panes (each Get-Pane* returns { header; lines[]; flags[] } -- pure strings a monospace UI or the gate
    asserts on):
      1  TASK TIMELINE          -- the compile's stages in order (normalize -> retrieve -> [route] ->
                                   select raw/post_filter/packet -> budget -> packet), with per-stage counts.
      2  EXACT MODEL VIEW       -- the four packet regions (control_plane / task_input / working_memory /
                                   evidence) each with a TRUST BANNER naming its trust class + source, in the
                                   contract render order; the non_execution frame.
      3  RETRIEVAL + SELECTION  -- selpol ranked[]/reason_codes[]/stages[] + the R-1 router stage-trace
                                   (evaluation_hooks.routing_stage_trace) + retrieval plan/lineage + V3
                                   completeness fields.
      4  RULE / EXCEPTION STACK -- fired / excluded / overridden rules with inputs + outputs (current_only,
                                   hard_filter_namespace/stale, superseded_demote, namespace closure, the
                                   temporal-intent override, the disposition rule).
      6  TOKEN + STATE LEDGER   -- the token budget + transport accounting + consumer_profile ledger + the
                                   #42 working-memory state_version ledger + the omission_manifest.
      (Pane 5 tool+sub-agent tree is OUT -- deferred to A2; no delegation exists yet.)

    Compile-layer counterfactual runner (s2.5a): re-run the SAME pinned mock snapshot through #40's
    deterministic compile worker with exactly ONE varied input (budget / temporal_intent / namespace /
    channel_mask / route / excluded record) and DIFF the two packets. ZERO model calls (mock retriever,
    deterministic re-compile). Get-PacketDiff is the pure differ; Invoke-CompileCounterfactual is the thin
    re-invoke harness (all scratch under the widget runtime dir).

    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate (pwsh 7.4.6 on Linux,
    over committed REAL fixtures) and on Windows. The UI (Show-CompileTraceConsole.ps1) is a thin shell over
    these functions. Shape mirrors ProvenanceMap.psm1 (Widget 05): defensive Get-Prop, List[object] +
    .ToArray() (never a bare @() on a maybe-null / raw List), a write-guarded runtime writer, ASCII-only
    source (the artifacts it PARSES carry non-ASCII; this SOURCE stays ASCII per the 5.1-ANSI/BOM lesson).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CtcWidgetRoot = $PSScriptRoot

# The channel-only keys a router stage-trace `removed[]` entry may carry (CONTEXT_PACKET_CONTRACT s9 / i33
# U1' -- a diagnostic array is namespace-closure-sanitized: channel-only, NEVER identifying metadata).
$script:TraceSafeRemovedKeys = @('channel_id', 'record_id', 'reason_codes')
$script:TraceForbiddenRemovedKeys = @('namespace', 'source_path', 'record_version_id', 'snippet', 'text', 'excerpt', 'path')

# ============================================================================
#  small helpers (shared shape with ProvenanceMap.psm1)
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

function Read-TextFileSafe {
    # Read a UTF-8 text file DEFENSIVELY -> { ok, text, bytes, error }. Never throws.
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; text = ''; bytes = 0; error = 'missing' }
    }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $sr = New-Object System.IO.StreamReader(
            (New-Object System.IO.MemoryStream(, $bytes)), [System.Text.Encoding]::UTF8, $true)
        try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
        return [pscustomobject]@{ ok = $true; text = $txt; bytes = $bytes.Length; error = '' }
    }
    catch { return [pscustomobject]@{ ok = $false; text = ''; bytes = 0; error = 'unreadable' } }
}

function Format-Bool { param($V) if ($null -eq $V) { return 'n/a' } if ([bool]$V) { return 'yes' } return 'no' }

# ============================================================================
#  path resolution
# ============================================================================

function Resolve-CompileTracePaths {
    <#
        Resolve the widget root, the repo root, and every read-only data source + the write-guarded runtime
        dir. -RepoRoot (or the env override LIFEORCH_CTC_REPO) points the whole console at a fixture/other
        tree so the cloud gate runs without the production repo. [IO.Path]::Combine is a pure string join so a
        foreign-platform RepoRoot ('C:\...') in a cloud-gate test does not throw "Cannot find drive 'C'".
    #>
    [CmdletBinding()]
    param([string]$WidgetRoot, [string]$RepoRoot)

    if (-not $WidgetRoot) { $WidgetRoot = $script:CtcWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    if (-not $RepoRoot) {
        if ($env:LIFEORCH_CTC_REPO) { $RepoRoot = $env:LIFEORCH_CTC_REPO }
        else {
            $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
            if ($rp) { $RepoRoot = $rp.Path } else { $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }
        }
    }

    $compilerDir = [System.IO.Path]::Combine($RepoRoot, 'modules', '40-context-compiler')
    return [pscustomobject]@{
        WidgetRoot     = $WidgetRoot
        RepoRoot       = $RepoRoot
        CompilerDir    = $compilerDir
        CompilerWorker = [System.IO.Path]::Combine($compilerDir, 'context_compiler.py')
        CompilerEntry  = [System.IO.Path]::Combine($compilerDir, 'Invoke-ContextCompiler.ps1')
        ArtifactsDir   = [System.IO.Path]::Combine($compilerDir, 'runtime', 'artifacts')
        RuntimeDir     = [System.IO.Path]::Combine($WidgetRoot, 'runtime')
    }
}

# ============================================================================
#  artifact loading -- a packet in any of its carrier shapes, plus companion reports
# ============================================================================

function Get-PacketFromObject {
    # Normalize any carrier of a context_packet to the inner packet object, or $null.
    #   - a raw packet          : has schema starting 'lifeorch.context_packet' + a packet_id
    #   - a skill.result env    : .result.result.packet   (Invoke-ContextCompiler.ps1 stdout)
    #   - a worker cc_meta      : .result.packet          (context_compiler.py meta)
    param($Obj)
    if ($null -eq $Obj) { return $null }
    $schema = [string](Get-Prop $Obj 'schema' '')
    if ($schema -like 'lifeorch.context_packet*' -and (Test-HasProp $Obj 'packet_id')) { return $Obj }
    $result = Get-Prop $Obj 'result' $null
    if ($null -ne $result) {
        $inner = Get-Prop $result 'result' $null           # skill.result envelope: result.result.packet
        if ($null -ne $inner) { $p = Get-Prop $inner 'packet' $null; if ($null -ne $p) { return $p } }
        $p2 = Get-Prop $result 'packet' $null               # worker cc_meta: result.packet
        if ($null -ne $p2) { return $p2 }
    }
    $p3 = Get-Prop $Obj 'packet' $null                      # bare { packet: {...} }
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

function Read-EvalReport {
    # Load a #37 eval report OR the i36 rehearsal report -> { ok, kind, report, schema, error }. Never throws.
    [CmdletBinding()]
    param([string]$Path)
    $o = Read-JsonFileSafe -Path $Path
    if ($null -eq $o) { return [pscustomobject]@{ ok = $false; kind = 'unknown'; report = $null; schema = ''; error = 'unreadable_or_missing_json' } }
    $schema = [string](Get-Prop $o 'schema' '')
    $kind = 'eval'
    if ($schema -like '*rehearsal*' -or (Test-HasProp $o 'tier1_criteria') -or (Test-HasProp $o 'wired_descend')) { $kind = 'rehearsal' }
    return [pscustomobject]@{ ok = $true; kind = $kind; report = $o; schema = $schema; error = '' }
}

function Read-FoldSmoke {
    # Parse a D-0077 fold-smoke TEXT log (the project's fold output format: '  [PASS]/[FAIL] label' lines +
    # a 'FOLD RESULT: N/M checks' line + 'FOLD PASSED'/'FOLD FAILED') -> { ok, checks[], passed, failed,
    # result_line, verdict }. Never throws.
    [CmdletBinding()]
    param([string]$Path)
    $r = Read-TextFileSafe -Path $Path
    if (-not $r.ok) { return [pscustomobject]@{ ok = $false; checks = @(); passed = 0; failed = 0; result_line = ''; verdict = 'unknown'; error = $r.error } }
    $checks = New-Object System.Collections.Generic.List[object]
    $pass = 0; $fail = 0; $resultLine = ''; $verdict = 'unknown'
    foreach ($ln in ($r.text -split "`r?`n")) {
        $m = [regex]::Match($ln, '^\s*\[(PASS|FAIL)\]\s+(.*)$')
        if ($m.Success) {
            $ok = ($m.Groups[1].Value -eq 'PASS'); if ($ok) { $pass++ } else { $fail++ }
            [void]$checks.Add([pscustomobject]@{ passed = $ok; label = ([string]$m.Groups[2].Value).Trim() })
            continue
        }
        if ($ln -match 'FOLD RESULT:') { $resultLine = $ln.Trim() }
        if ($ln -match 'FOLD PASSED') { $verdict = 'passed' }
        if ($ln -match 'FOLD FAILED') { $verdict = 'failed' }
    }
    return [pscustomobject]@{ ok = $true; checks = $checks.ToArray(); passed = $pass; failed = $fail; result_line = $resultLine; verdict = $verdict; error = '' }
}

# ============================================================================
#  namespace-closure sanitization guard (CONTEXT_PACKET_CONTRACT s9 / i33 U1')
# ============================================================================

function Get-EffectiveNamespaces {
    # The effective_allowed_namespaces the compile enforced (identity.namespace_closure.effective, else
    # task_input.allowed_namespaces). Plain string[].
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
    # removed_entry_count }. The trace is sanitized at EMISSION by #40; this is the render-side re-assertion
    # (the console must never become a namespace side-channel).
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

# ============================================================================
#  Pane 1 -- TASK TIMELINE
# ============================================================================

function Get-Pane1Timeline {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $ti = Get-Prop $Packet 'task_input' $null
    $rp = Get-Prop $Packet 'retrieval_provenance' $null
    $sel = Get-Prop $Packet 'selection' $null
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $tb = Get-Prop $Packet 'token_budget' $null

    $qset = @(ConvertTo-Array (Get-Prop $rp 'query_set' $null))
    $stages = Get-Prop $eh 'stages' $null
    $raw = @(ConvertTo-Array (Get-Prop $stages 'raw_retrieval' $null))
    $post = @(ConvertTo-Array (Get-Prop $stages 'post_filter' $null))
    $pkt = @(ConvertTo-Array (Get-Prop $stages 'packet' $null))
    $trace = @(ConvertTo-Array (Get-Prop $eh 'routing_stage_trace' $null))

    $steps = New-Object System.Collections.Generic.List[object]
    [void]$steps.Add(@('normalize', ("query_class=" + [string](Get-Prop $ti 'query_class' '?') + "  temporal_intent=" + [string](Get-Prop $ti 'temporal_intent' '?') + "  task_type=" + [string](Get-Prop $ti 'task_type' '?'))))
    [void]$steps.Add(@('retrieve', ("queries=" + $qset.Count + "  candidates=" + [string](Get-Prop $rp 'candidate_count' '?') + "  fusion=" + [string](Get-Prop $rp 'fusion_algo' '?'))))
    if ($trace.Count -gt 0) {
        foreach ($st in $trace) {
            [void]$steps.Add(@(('route:' + [string](Get-Prop $st 'stage_id' '?')), ("in=" + [string](Get-Prop $st 'candidates_in' '?') + " out=" + [string](Get-Prop $st 'candidates_out' '?') + "  policy=" + [string](Get-Prop $st 'policy_id' '?') + "/" + [string](Get-Prop $st 'policy_version' '?'))))
        }
    }
    else { [void]$steps.Add(@('route', 'FLAT compile (router not engaged) -- no routing_stage_trace')) }
    [void]$steps.Add(@('select:raw', ("candidates=" + $raw.Count)))
    [void]$steps.Add(@('select:post_filter', ("candidates=" + $post.Count)))
    [void]$steps.Add(@('select:packet', ("selected=" + $pkt.Count)))
    [void]$steps.Add(@('budget', ("used=" + [string](Get-Prop $tb 'used' '?') + "/" + [string](Get-Prop $tb 'budget' '?') + " tokens  omitted=" + [string](Get-Prop $tb 'omitted_count' '0'))))
    [void]$steps.Add(@('packet', ("disposition=" + [string](Get-Prop (Get-Prop $Packet 'disposition' $null) 'packet_disposition' '?') + "  packet_id=" + [string](Get-Prop $Packet 'packet_id' '?'))))

    $i = 0
    foreach ($step in $steps) {
        $i++
        [void]$lines.Add(("{0,2}. {1,-22} {2}" -f $i, [string]$step[0], [string]$step[1]))
    }
    $hdr = 'compile stages in order (candidate counts per stage)'
    return [pscustomobject]@{ header = $hdr; lines = $lines.ToArray(); flags = $flags.ToArray() }
}

# ============================================================================
#  Pane 2 -- EXACT MODEL VIEW (the four regions + trust banners, in render order)
# ============================================================================

function Get-Pane2ModelView {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $ne = Get-Prop $Packet 'non_execution' $null
    [void]$lines.Add('NON_EXECUTION = ' + (Format-Bool $ne) + '   (no packet region grants side-effect authority; P0-1 hard gate)')
    if ($ne -ne $true) { [void]$flags.Add('non_execution is NOT true -- expected true for a read-only compile') }
    [void]$lines.Add('render order: control_plane -> task_input -> working_memory -> evidence')
    [void]$lines.Add('')

    # --- region 1: control_plane ---
    $cp = Get-Prop $Packet 'control_plane' $null
    [void]$lines.Add('== [1] control_plane ==  TRUST: AUTHORITATIVE (coordinator/user store ONLY; NEVER from retrieval)')
    [void]$lines.Add('   policy              : ' + [string](Get-Prop $cp 'policy' '?'))
    [void]$lines.Add('   side_effect_policy  : ' + [string](Get-Prop $cp 'side_effect_policy' '?'))
    [void]$lines.Add('   request_authority   : ' + [string](Get-Prop $cp 'request_authority' '?'))
    [void]$lines.Add('   provenance          : ' + [string](Get-Prop $cp 'provenance' '?'))
    $grants = @(ConvertTo-Array (Get-Prop $cp 'permission_grants' $null))
    [void]$lines.Add('   permission_grants   : ' + $grants.Count + ' grant(s)')
    foreach ($g in $grants) {
        $ns = @(ConvertTo-Array (Get-Prop $g 'namespaces' $null))
        [void]$lines.Add('      - namespaces: ' + (($ns | ForEach-Object { [string]$_ }) -join ', '))
    }
    $cc = Get-Prop $cp 'completion_contract' $null
    [void]$lines.Add('   completion_contract : goal=' + (Limit-Text (Get-Prop $cc 'goal' '(none)') 60) + '  criteria=' + @(ConvertTo-Array (Get-Prop $cc 'success_criteria' $null)).Count)
    [void]$lines.Add('   escalation_conds    : ' + @(ConvertTo-Array (Get-Prop $cp 'escalation_conditions' $null)).Count)
    [void]$lines.Add('   grant_snapshot_ref  : ' + (Limit-Text (Get-Prop $cp 'grant_snapshot_ref' '?') 60))
    [void]$lines.Add('')

    # --- region 2: task_input ---
    $ti = Get-Prop $Packet 'task_input' $null
    [void]$lines.Add('== [2] task_input ==  TRUST: REQUEST (user/coordinator; requested side effects are REQUESTS, not grants)')
    [void]$lines.Add('   original_goal       : ' + (Limit-Text (Get-Prop $ti 'original_goal' '?') 74))
    [void]$lines.Add('   normalized_task     : ' + (Limit-Text (Get-Prop $ti 'normalized_task' '?') 74))
    [void]$lines.Add('   task_type           : ' + [string](Get-Prop $ti 'task_type' '?') + '   query_class: ' + [string](Get-Prop $ti 'query_class' '?'))
    [void]$lines.Add('   namespace           : ' + [string](Get-Prop $ti 'namespace' '?'))
    [void]$lines.Add('   temporal_intent     : ' + [string](Get-Prop $ti 'temporal_intent' '?') + '   (basis: ' + [string](Get-Prop $ti 'temporal_intent_basis' '?') + ')')
    $rse = @(ConvertTo-Array (Get-Prop $ti 'requested_side_effects' $null))
    [void]$lines.Add('   requested_side_effects: ' + (($rse | ForEach-Object { [string]$_ }) -join ', ') + '   (matched vs control_plane grants -- self-grant impossible)')
    [void]$lines.Add('')

    # --- region 3: working_memory ---
    $wm = Get-Prop $Packet 'working_memory' $null
    [void]$lines.Add('== [3] working_memory ==  TRUST: CONTINUITY-authoritative (this task''s state; content_role=working_state; can_instruct=false; NOT execution authority)')
    [void]$lines.Add('   present             : ' + (Format-Bool (Get-Prop $wm 'present' $false)) + '   item_count: ' + [string](Get-Prop $wm 'item_count' '0'))
    [void]$lines.Add('   content_role        : ' + [string](Get-Prop $wm 'content_role' '?') + '   can_instruct: ' + (Format-Bool (Get-Prop $wm 'can_instruct' $false)))
    [void]$lines.Add('   access_policy       : ' + [string](Get-Prop $wm 'access_policy' '?'))
    [void]$lines.Add('   state_version       : ' + [string](Get-Prop $wm 'state_version' '(null -- reserved; #42 store wiring is i38)'))
    [void]$lines.Add('')

    # --- region 4: evidence ---
    $ev = Get-Prop $Packet 'evidence' $null
    $exc = @(ConvertTo-Array (Get-Prop $ev 'excerpts' $null))
    $nav = @(ConvertTo-Array (Get-Prop $ev 'navigation_refs' $null))
    [void]$lines.Add('== [4] evidence ==  TRUST: EVIDENCE (content_role=evidence; can_instruct=false; imperative text is DATA describing a source, NEVER an instruction)')
    [void]$lines.Add('   excerpts=' + $exc.Count + '   navigation_refs=' + $nav.Count + ' (navigation NEVER answer-evidence)')
    [void]$lines.Add('   ' + ('{0,-26} {1,-14} {2,-14} {3,-10} {4}' -f 'excerpt_id', 'trust_domain', 'authority', 'current', 'source / provenance_mode'))
    foreach ($e in $exc) {
        $eid = [string](Get-Prop $e 'excerpt_id' '?')
        $td = [string](Get-Prop $e 'trust_domain' (Get-Prop $e 'source' '?'))
        $auth = [string](Get-Prop $e 'epistemic_authority' '?')
        $cur = [string](Get-Prop $e 'currentness' '?')
        $src = [string](Get-Prop $e 'source_path' (Get-Prop $e 'source' '?'))
        $pm = [string](Get-Prop $e 'provenance_mode' '?')
        $ci = Get-Prop $e 'can_instruct' $null
        if ($ci -eq $true) { [void]$flags.Add("evidence excerpt $eid has can_instruct=true -- contract violation") }
        [void]$lines.Add('   ' + ('{0,-26} {1,-14} {2,-14} {3,-10} {4}' -f (Limit-Text $eid 26), (Limit-Text $td 14), (Limit-Text $auth 14), (Limit-Text $cur 10), (Limit-Text ($src + '  [' + $pm + ']') 44)))
    }

    return [pscustomobject]@{ header = 'the packet IS the model''s whole context -- four regions, four trust classes'; lines = $lines.ToArray(); flags = $flags.ToArray() }
}

# ============================================================================
#  Pane 3 -- RETRIEVAL + SELECTION TRACE
# ============================================================================

function Get-Pane3RetrievalTrace {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $sel = Get-Prop $Packet 'selection' $null
    $eh = Get-Prop $Packet 'evaluation_hooks' $null
    $rp = Get-Prop $Packet 'retrieval_provenance' $null

    # selection policy header
    [void]$lines.Add('SELECTION POLICY: ' + [string](Get-Prop $sel 'policy_id' '?') + '/' + [string](Get-Prop $sel 'policy_version' '?') + '  owner=' + [string](Get-Prop $sel 'owner' '?'))
    [void]$lines.Add('')

    # --- R-1 router stage-trace (i37) ---
    $trace = @(ConvertTo-Array (Get-Prop $eh 'routing_stage_trace' $null))
    [void]$lines.Add('-- R-1 ROUTER STAGE-TRACE (evaluation_hooks.routing_stage_trace) --')
    if ($trace.Count -eq 0) { [void]$lines.Add('   (flat compile -- router not engaged; the trace is additive to a routed compile)') }
    foreach ($st in $trace) {
        [void]$lines.Add('   [' + [string](Get-Prop $st 'stage_id' '?') + '] in=' + [string](Get-Prop $st 'candidates_in' '?') + ' out=' + [string](Get-Prop $st 'candidates_out' '?') + '  policy=' + [string](Get-Prop $st 'policy_id' '?') + '/' + [string](Get-Prop $st 'policy_version' '?') + '  parent=' + [string](Get-Prop $st 'parent_stage_id' '(root)'))
        foreach ($rem in @(ConvertTo-Array (Get-Prop $st 'removed' $null))) {
            $ch = [string](Get-Prop $rem 'channel_id' (Get-Prop $rem 'record_id' '?'))
            $rc = @(ConvertTo-Array (Get-Prop $rem 'reason_codes' $null))
            [void]$lines.Add('        - removed ' + $ch + ' :: ' + (($rc | ForEach-Object { [string]$_ }) -join ', '))
        }
        $tbk = [string](Get-Prop $st 'tie_break_key' '')
        if ($tbk) { [void]$lines.Add('        tie_break: ' + (Limit-Text $tbk 80)) }
    }
    [void]$lines.Add('')

    # --- selpol ranked[] + reason_codes[] + stages[] ---
    [void]$lines.Add('-- SELPOL RANKED (selection_rank : rvid : reason_codes) --')
    $ranked = @(ConvertTo-Array (Get-Prop $eh 'retrieved' $null))
    $feat = Get-Prop $sel 'features_by_candidate' $null
    # order by selection_rank when present
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($r in $ranked) {
        $rvid = [string](Get-Prop $r 'record_version_id' (Get-Prop $r 'record_id' '?'))
        $f = Get-Prop $feat $rvid $null
        $srank = Get-Prop $r 'selection_rank' (Get-Prop $f 'selection_rank' 9999)
        $rc = @(ConvertTo-Array (Get-Prop $r 'reason_codes' (Get-Prop $f 'reason_codes' $null)))
        $seld = Get-Prop $r 'selected' (Get-Prop $f 'selected' $null)
        [void]$rows.Add([pscustomobject]@{ rvid = $rvid; srank = [int]$srank; rc = $rc; selected = $seld })
    }
    foreach ($row in ($rows | Sort-Object srank)) {
        $mark = if ($row.selected -eq $true) { '*' } else { ' ' }
        [void]$lines.Add(('   {0}{1,3}  {2,-30} {3}' -f $mark, $row.srank, (Limit-Text $row.rvid 30), ((@($row.rc) | ForEach-Object { [string]$_ }) -join ', ')))
    }
    if ($rows.Count -eq 0) { [void]$lines.Add('   (no ranked candidates in evaluation_hooks.retrieved)') }
    [void]$lines.Add('')

    # --- selection stages ---
    $stages = Get-Prop $sel 'stages' $null
    if ($null -ne $stages) {
        [void]$lines.Add('-- SELPOL STAGES (selection.stages) --')
        foreach ($sn in @(Get-PropNames $stages)) {
            [void]$lines.Add('   ' + $sn)
        }
        [void]$lines.Add('')
    }

    # --- retrieval plan / lineage ---
    [void]$lines.Add('-- RETRIEVAL PLAN / LINEAGE (retrieval_provenance) --')
    [void]$lines.Add('   retriever          : ' + [string](Get-Prop $rp 'retriever' '?') + '/' + [string](Get-Prop $rp 'retriever_version' '?'))
    [void]$lines.Add('   corpus_version     : ' + [string](Get-Prop $rp 'corpus_version' '?'))
    [void]$lines.Add('   fusion             : ' + [string](Get-Prop $rp 'fusion_algo' '?') + '/' + [string](Get-Prop $rp 'fusion_version' '?'))
    [void]$lines.Add('   vector_channel     : ' + [string](Get-Prop $rp 'vector_channel_status' 'empty'))
    [void]$lines.Add('   embedding_space_id : ' + [string](Get-Prop $rp 'embedding_space_id' '(none)'))
    $pqhc = Get-Prop $rp 'per_query_hit_counts' $null
    if ($null -ne $pqhc) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($k in @(Get-PropNames $pqhc)) { [void]$parts.Add($k + '=' + [string](Get-Prop $pqhc $k '?')) }
        [void]$lines.Add('   per_query_hits     : ' + ($parts.ToArray() -join '  '))
    }
    [void]$lines.Add('')

    # --- V3 retrieval completeness (i34; present on a descend compile) ---
    [void]$lines.Add('-- V3 RETRIEVAL COMPLETENESS (i34; a hierarchy MISS is not proved ABSENCE) --')
    $rc3 = Get-Prop $Packet 'retrieval_completeness' $null
    if ($null -eq $rc3) { $rc3 = Get-Prop $rp 'retrieval_completeness' $null }
    if ($null -eq $rc3) {
        [void]$lines.Add('   (flat compile -- no hierarchy frontier; completeness fields not emitted)')
    }
    else {
        foreach ($k in 'frontier_exhausted', 'pruned_branch_count', 'fallback_used', 'stale_navigation_encountered', 'unresolved_branch_count', 'prune_policy_id', 'prune_policy_version') {
            if (Test-HasProp $rc3 $k) { [void]$lines.Add('   ' + ('{0,-30}' -f $k) + ': ' + [string](Get-Prop $rc3 $k '?')) }
        }
        foreach ($pr in @(ConvertTo-Array (Get-Prop $rc3 'prune_reasons' $null))) { [void]$lines.Add('   prune_reason: ' + [string]$pr) }
    }

    return [pscustomobject]@{ header = 'ranked[] + reason_codes[] + stages[] + R-1 router trace + retrieval lineage + V3 completeness'; lines = $lines.ToArray(); flags = $flags.ToArray() }
}

# ============================================================================
#  Pane 4 -- RULE / EXCEPTION STACK
# ============================================================================

function Get-Pane4RuleStack {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $ti = Get-Prop $Packet 'task_input' $null
    $idn = Get-Prop $Packet 'identity' $null
    $disp = Get-Prop $Packet 'disposition' $null
    $sel = Get-Prop $Packet 'selection' $null

    # temporal rule
    $temporal = [string](Get-Prop $ti 'temporal_intent' '?')
    $tbasis = [string](Get-Prop $ti 'temporal_intent_basis' '?')
    $co = Get-Prop $ti 'current_only' $null
    [void]$lines.Add('RULE temporal_intent -> ' + $temporal + '   FIRED  (basis: ' + $tbasis + ')')
    if ($tbasis -eq 'explicit_temporal_intent') { [void]$lines.Add('   EXCEPTION: an explicit user time/version OUTRANKS the query_class default (i33 U5'')') }
    if ($co -eq $true) { [void]$lines.Add('   -> current_only ACTIVE: a non-current candidate is HARD-filtered (hard_filter_stale); a superseded candidate whose successor is live is EXCLUDED (candidate-independent, i33 U4'')') }

    # namespace closure rule
    $nc = Get-Prop $idn 'namespace_closure' $null
    if ($null -ne $nc) {
        $req = (@(ConvertTo-Array (Get-Prop $nc 'request' $null)) | ForEach-Object { [string]$_ }) -join ','
        $grant = (@(ConvertTo-Array (Get-Prop $nc 'grant' $null)) | ForEach-Object { [string]$_ }) -join ','
        $eff = (@(ConvertTo-Array (Get-Prop $nc 'effective' $null)) | ForEach-Object { [string]$_ }) -join ','
        [void]$lines.Add('RULE namespace_closure -> effective = intersection(request, grant)   FIRED  enforced=' + (Format-Bool (Get-Prop $nc 'enforced' $false)))
        [void]$lines.Add('   request=[' + $req + ']  grant=[' + $grant + ']  effective=[' + $eff + ']   (request can NEVER widen scope; empty intersection FAILS CLOSED -- i33 U1'')')
    }

    # reason-code driven exclusions/overrides, tallied across candidates
    [void]$lines.Add('')
    [void]$lines.Add('FIRED / EXCLUDED / OVERRIDDEN rules by reason_code (count of candidates):')
    $feat = Get-Prop $sel 'features_by_candidate' $null
    $tally = @{}
    foreach ($cand in @(Get-PropNames $feat)) {
        $f = Get-Prop $feat $cand $null
        foreach ($rc in @(ConvertTo-Array (Get-Prop $f 'reason_codes' $null))) {
            $key = [string]$rc
            if (-not $tally.ContainsKey($key)) { $tally[$key] = 0 }
            $tally[$key] = [int]$tally[$key] + 1
        }
    }
    $codeClass = @{
        'hard_filter_forbidden' = 'EXCLUDED'; 'hard_filter_namespace' = 'EXCLUDED'; 'hard_filter_stale' = 'EXCLUDED'
        'namespace_closure_violation' = 'EXCLUDED'; 'superseded_demote' = 'OVERRIDDEN'; 'stale_demote' = 'OVERRIDDEN'
        'diversity_capped' = 'OVERRIDDEN'; 'budget_omitted' = 'EXCLUDED'; 'authority_boost' = 'FIRED'
        'fusion_rrf' = 'FIRED'; 'rescued' = 'FIRED'; 'selected' = 'FIRED'
    }
    foreach ($k in ($tally.Keys | Sort-Object)) {
        $cls = if ($codeClass.ContainsKey($k)) { $codeClass[$k] } else { 'FIRED' }
        [void]$lines.Add(('   {0,-11} {1,-28} {2} candidate(s)' -f $cls, $k, $tally[$k]))
    }
    if ($tally.Count -eq 0) { [void]$lines.Add('   (no per-candidate reason codes in selection.features_by_candidate)') }

    # disposition rule
    [void]$lines.Add('')
    $dispVal = [string](Get-Prop $disp 'packet_disposition' '?')
    [void]$lines.Add('RULE disposition -> ' + $dispVal + '   ' + [string](Get-Prop $disp 'rule' ''))
    $missing = @(ConvertTo-Array (Get-Prop $disp 'missing_requirements' $null))
    $contra = @(ConvertTo-Array (Get-Prop $disp 'contradictions' $null))
    [void]$lines.Add('   requirements: satisfied=' + @(ConvertTo-Array (Get-Prop $disp 'coverage_results' $null) | Where-Object { (Get-Prop $_ 'satisfied' $false) -eq $true }).Count + '/' + @(ConvertTo-Array (Get-Prop $disp 'evidence_requirements' $null)).Count + '  missing=' + $missing.Count + '  contradictions=' + $contra.Count)
    if ($dispVal -ne 'answerable') { [void]$flags.Add('packet_disposition=' + $dispVal + ' -- a normal answer is permitted ONLY when answerable') }

    return [pscustomobject]@{ header = 'fired / excluded / overridden rules with inputs + outputs'; lines = $lines.ToArray(); flags = $flags.ToArray() }
}

# ============================================================================
#  Pane 6 -- TOKEN + STATE LEDGER
# ============================================================================

function Get-Pane6TokenLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet)
    $lines = New-Object System.Collections.Generic.List[string]
    $flags = New-Object System.Collections.Generic.List[string]
    $tb = Get-Prop $Packet 'token_budget' $null
    $ta = Get-Prop $Packet 'transport_accounting' $null
    $cprof = Get-Prop $Packet 'consumer_profile' $null
    $wm = Get-Prop $Packet 'working_memory' $null
    $om = @(ConvertTo-Array (Get-Prop $Packet 'omission_manifest' $null))

    [void]$lines.Add('-- BUDGET LEDGER (token_budget; excerpt-fill accounting -- token_fn is a HEURISTIC upper bound) --')
    [void]$lines.Add('   budget=' + [string](Get-Prop $tb 'budget' '?') + '  used=' + [string](Get-Prop $tb 'used' '?') + '  remaining=' + [string](Get-Prop $tb 'remaining' '?') + '  excerpts=' + [string](Get-Prop $tb 'excerpt_count' '?') + '/' + [string](Get-Prop $tb 'max_excerpts' '?'))
    [void]$lines.Add('   excerpt_body_tokens=' + [string](Get-Prop $tb 'excerpt_body_tokens' '?') + '  overhead_tokens=' + [string](Get-Prop $tb 'overhead_tokens' '?') + '  omitted=' + [string](Get-Prop $tb 'omitted_count' '0') + '  token_fn=' + [string](Get-Prop $tb 'token_fn' '?'))
    [void]$lines.Add('')

    [void]$lines.Add('-- TRANSPORT ACCOUNTING (the authority that gates ''answerable'' -- P0-4) --')
    [void]$lines.Add('   counted_on   : ' + [string](Get-Prop $ta 'counted_on' '?'))
    [void]$lines.Add('   count_method : ' + [string](Get-Prop $ta 'count_method' '?') + '  count_is_exact=' + (Format-Bool (Get-Prop $ta 'count_is_exact' $false)))
    [void]$lines.Add('   rendered_tokens=' + [string](Get-Prop $ta 'rendered_tokens' '?') + '  reserved_total=' + [string](Get-Prop $ta 'reserved_total_tokens' '?') + '  transport_budget=' + [string](Get-Prop $ta 'transport_budget_tokens' '?') + '  max_context=' + [string](Get-Prop $ta 'max_context' '?'))
    [void]$lines.Add('   fits=' + (Format-Bool (Get-Prop $ta 'fits' $false)) + '  transport_overflow=' + (Format-Bool (Get-Prop $ta 'transport_overflow' $false)) + '  dropped_for_transport=' + [string](Get-Prop $ta 'dropped_for_transport' '0'))
    if ((Get-Prop $ta 'transport_overflow' $false) -eq $true) { [void]$flags.Add('transport_overflow=true -- the packet must NOT ship as answerable') }
    [void]$lines.Add('')

    [void]$lines.Add('-- CONSUMER PROFILE (names exactly which consumer the budget was computed for) --')
    [void]$lines.Add('   model_id     : ' + [string](Get-Prop $cprof 'model_id' '?'))
    [void]$lines.Add('   tokenizer    : ' + [string](Get-Prop $cprof 'tokenizer_id' '?') + '  fingerprint=' + (Limit-Text (Get-Prop $cprof 'tokenizer_fingerprint' '?') 44))
    [void]$lines.Add('   chat_template: ' + [string](Get-Prop $cprof 'chat_template_id' '?') + '  max_context=' + [string](Get-Prop $cprof 'max_context' '?'))
    [void]$lines.Add('   reserved     : system=' + [string](Get-Prop $cprof 'reserved_system_tokens' '?') + '  tool=' + [string](Get-Prop $cprof 'reserved_tool_tokens' '?') + '  generation=' + [string](Get-Prop $cprof 'reserved_generation_tokens' '?'))
    [void]$lines.Add('')

    [void]$lines.Add('-- STATE LEDGER (#42 working-memory state_version; reserved at Tier 0, store wiring is i38) --')
    $rsf = Get-Prop $wm 'reserved_store_fields' $null
    [void]$lines.Add('   present=' + (Format-Bool (Get-Prop $wm 'present' $false)) + '  lifecycle_state=' + [string](Get-Prop $rsf 'lifecycle_state' '?') + '  state_version=' + [string](Get-Prop $wm 'state_version' '(null)'))
    [void]$lines.Add('   task_id=' + (Limit-Text (Get-Prop $rsf 'task_id' '?') 40) + '  parent_state_version=' + [string](Get-Prop $rsf 'parent_state_version' '(null)'))
    [void]$lines.Add('')

    $omWord = if ($om.Count -eq 1) { 'entry' } else { 'entries' }
    [void]$lines.Add('-- OMISSION MANIFEST (' + $om.Count + ' ' + $omWord + ' -- part of packet identity) --')
    foreach ($o in $om) {
        [void]$lines.Add('   - ' + (Limit-Text (Get-Prop $o 'record_version_id' (Get-Prop $o 'record_id' '?')) 34) + '  reason=' + [string](Get-Prop $o 'reason' (Get-Prop $o 'drop_reason' '?')) + '  hint=' + (Limit-Text (Get-Prop $o 'expand_hint' '') 30))
    }
    if ($om.Count -eq 0) { [void]$lines.Add('   (nothing omitted)') }

    return [pscustomobject]@{ header = 'budget + transport + consumer_profile + #42 state_version + omission manifest'; lines = $lines.ToArray(); flags = $flags.ToArray() }
}

# ============================================================================
#  the whole model -- panes + companion artifacts + sanitization state
# ============================================================================

function Get-CompileTraceModel {
    <#
        Build the full trace model for one packet (+ optional companion eval/rehearsal/fold artifacts). Never
        throws to the UI: a failure yields a well-formed ok=false model the header renders. READ-ONLY.
    #>
    [CmdletBinding()]
    param([string]$PacketPath, [string]$EvalPath, [string]$RehearsalPath, [string]$FoldPath, [string]$RepoRoot, [string]$WidgetRoot)

    $flags = New-Object System.Collections.Generic.List[string]
    $rd = Read-ContextPacket -Path $PacketPath
    if (-not $rd.ok) {
        return [pscustomobject]@{
            ok = $false; error = $rd.error; source_path = [string]$PacketPath
            packet_id = ''; schema = ''; compiler_version = ''; non_execution = $null; disposition = ''
            panes = $null; companion = $null; sanitize = $null
            flags = @('packet load failed: ' + $rd.error)
            counts = [ordered]@{ excerpts = 0; navigation = 0; ranked = 0; omissions = 0; trace_stages = 0 }
        }
    }
    $p = $rd.packet
    $disp = Get-Prop $p 'disposition' $null
    $eh = Get-Prop $p 'evaluation_hooks' $null
    $ev = Get-Prop $p 'evidence' $null

    # build each pane INDEPENDENTLY so one pane's failure degrades only that pane (never nukes the rest)
    $panes = [ordered]@{ timeline = $null; modelview = $null; retrieval = $null; rules = $null; ledger = $null }
    $paneBuilders = [ordered]@{
        timeline  = { param($pk) Get-Pane1Timeline -Packet $pk }
        modelview = { param($pk) Get-Pane2ModelView -Packet $pk }
        retrieval = { param($pk) Get-Pane3RetrievalTrace -Packet $pk }
        rules     = { param($pk) Get-Pane4RuleStack -Packet $pk }
        ledger    = { param($pk) Get-Pane6TokenLedger -Packet $pk }
    }
    foreach ($name in @($paneBuilders.Keys)) {
        try {
            $pane = & $paneBuilders[$name] $p
            $panes[$name] = $pane
            foreach ($f in @($pane.flags)) { [void]$flags.Add([string]$f) }
        }
        catch {
            $panes[$name] = [pscustomobject]@{ header = "pane build failed"; lines = @('ERROR: ' + $_.Exception.Message); flags = @() }
            [void]$flags.Add("pane '$name' build threw: " + $_.Exception.Message)
        }
    }

    try {
        $sanitize = Test-TraceSanitized -Packet $p
        $sanitize | Add-Member -NotePropertyName effective_namespaces -NotePropertyValue (Get-EffectiveNamespaces -Packet $p) -Force
        if (-not $sanitize.sanitized) { foreach ($v in @($sanitize.violations)) { [void]$flags.Add('SANITIZATION: ' + $v) } }
    }
    catch { [void]$flags.Add('sanitize check threw: ' + $_.Exception.Message) }

    # companion artifacts (optional)
    $companion = [ordered]@{ eval = $null; rehearsal = $null; fold = $null }
    if ($EvalPath) { $companion.eval = Read-EvalReport -Path $EvalPath }
    if ($RehearsalPath) { $companion.rehearsal = Read-EvalReport -Path $RehearsalPath }
    if ($FoldPath) { $companion.fold = Read-FoldSmoke -Path $FoldPath }

    $counts = [ordered]@{
        excerpts   = @(ConvertTo-Array (Get-Prop $ev 'excerpts' $null)).Count
        navigation = @(ConvertTo-Array (Get-Prop $ev 'navigation_refs' $null)).Count
        ranked     = @(ConvertTo-Array (Get-Prop $eh 'retrieved' $null)).Count
        omissions  = @(ConvertTo-Array (Get-Prop $p 'omission_manifest' $null)).Count
        trace_stages = @(ConvertTo-Array (Get-Prop $eh 'routing_stage_trace' $null)).Count
    }

    return [pscustomobject]@{
        ok = $true; error = ''; source_path = [string]$PacketPath
        packet_id = $rd.packet_id; schema = $rd.schema; compiler_version = $rd.compiler_version
        non_execution = (Get-Prop $p 'non_execution' $null)
        disposition = [string](Get-Prop $disp 'packet_disposition' '?')
        packet = $p
        panes = $panes; companion = $companion; sanitize = $sanitize
        flags = $flags.ToArray(); counts = $counts
    }
}

function Format-CompileTraceHeader {
    # The header block + a one-line summary a UI status bar / the gate assert on.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model)
    $h = New-Object System.Collections.Generic.List[string]
    if (-not $Model.ok) {
        [void]$h.Add('COMPILE TRACE CONSOLE -- load FAILED: ' + [string]$Model.error)
        [void]$h.Add('source: ' + [string]$Model.source_path)
        return [pscustomobject]@{ header_lines = $h.ToArray(); summary_line = 'load failed: ' + [string]$Model.error }
    }
    $san = if ($null -ne $Model.sanitize -and $Model.sanitize.sanitized) { 'sanitized' } else { 'SANITIZATION-FLAG' }
    [void]$h.Add('COMPILE TRACE CONSOLE   packet_id=' + $Model.packet_id)
    [void]$h.Add('schema=' + $Model.schema + '   compiler=' + $Model.compiler_version + '   non_execution=' + (Format-Bool $Model.non_execution) + '   disposition=' + $Model.disposition)
    $c = $Model.counts
    [void]$h.Add('excerpts=' + $c.excerpts + '  nav=' + $c.navigation + '  ranked=' + $c.ranked + '  omissions=' + $c.omissions + '  router_stages=' + $c.trace_stages + '  diagnostics=' + $san)
    if (@($Model.flags).Count -gt 0) { [void]$h.Add('flags: ' + (@($Model.flags).Count) + ' -- see Flags tab') }
    $summary = 'packet ' + $Model.packet_id + '  ' + $Model.disposition + '  (' + $c.excerpts + ' excerpts, ' + $c.trace_stages + ' router stages, ' + $san + ')'
    return [pscustomobject]@{ header_lines = $h.ToArray(); summary_line = $summary }
}

function Format-CompanionRows {
    # Render the optional eval / rehearsal / fold companion artifacts to display lines.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model)
    $lines = New-Object System.Collections.Generic.List[string]
    $comp = $Model.companion
    if ($null -eq $comp) { return [pscustomobject]@{ lines = @('(no companion artifacts loaded)') } }

    $reh = $comp.rehearsal
    if ($null -ne $reh -and $reh.ok) {
        $r = $reh.report
        [void]$lines.Add('== REHEARSAL REPORT (' + [string](Get-Prop $r 'benchmark_id' '?') + ') ==')
        $ta = Get-Prop $r 'tier1_acceptance' $null
        [void]$lines.Add('   tier1_accepted=' + (Format-Bool (Get-Prop $ta 'accepted' $false)) + '  criteria=' + [string](Get-Prop $r 'tier1_criteria_passed' '?') + '/' + [string](Get-Prop $r 'tier1_criteria_total' '?') + '  mode=' + [string](Get-Prop $r 'measurement_mode' '?'))
        foreach ($cr in @(ConvertTo-Array (Get-Prop $r 'tier1_criteria' $null))) {
            $mk = if ((Get-Prop $cr 'passed' $false) -eq $true) { 'PASS' } else { 'FAIL' }
            [void]$lines.Add('   [' + $mk + '] ' + [string](Get-Prop $cr 's10' '') + ' ' + [string](Get-Prop $cr 'criterion' '?'))
        }
        [void]$lines.Add('')
    }
    $ev = $comp.eval
    if ($null -ne $ev -and $ev.ok) {
        $r = $ev.report
        [void]$lines.Add('== EVAL REPORT (hybrid attribution -- the counterfactual reconcile source) ==')
        $ha = Get-Prop $r 'hybrid_applicability' $null
        if ($null -ne $ha) { [void]$lines.Add('   hybrid_applicability=' + [string](Get-Prop $ha 'status' '?') + '  vector_channel=' + [string](Get-Prop $ha 'vector_channel' '?')) }
        $hattr = @(ConvertTo-Array (Get-Prop $r 'hybrid_attribution' $null))
        $rescuedTotal = 0
        foreach ($q in $hattr) { $rescuedTotal += @(ConvertTo-Array (Get-Prop $q 'required_rescued_by_vector' $null)).Count }
        [void]$lines.Add('   hybrid_attribution queries=' + $hattr.Count + '  required_rescued_by_vector(total)=' + $rescuedTotal + '  => a vector-channel-mask counterfactual should show ZERO packet delta')
        [void]$lines.Add('')
    }
    $fold = $comp.fold
    if ($null -ne $fold -and $fold.ok) {
        [void]$lines.Add('== FOLD SMOKE (' + [string]$fold.verdict + ') ' + [string]$fold.result_line + ' ==')
        foreach ($ck in @($fold.checks)) {
            $mk = if ($ck.passed) { 'PASS' } else { 'FAIL' }
            [void]$lines.Add('   [' + $mk + '] ' + [string]$ck.label)
        }
    }
    if ($lines.Count -eq 0) { [void]$lines.Add('(no companion artifacts loaded)') }
    return [pscustomobject]@{ lines = $lines.ToArray() }
}

# ============================================================================
#  write-guard (the read-only guarantee) -- every runtime write goes through here
# ============================================================================

function Assert-UnderRuntime {
    # Throw unless the resolved target lives under the widget's OWN runtime dir. Defense-in-depth on the
    # strictly-read-only guarantee (the ONLY writes the widget makes are the counterfactual re-compile
    # scratch + diffs, all under runtime/).
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$RuntimeDir)
    $runtimeFull = [System.IO.Path]::GetFullPath($RuntimeDir)
    $targetFull = [System.IO.Path]::GetFullPath($Target)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $guard = $runtimeFull.TrimEnd($sep) + $sep
    if (-not $targetFull.StartsWith($guard, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Compile Trace Console refused a write to '$targetFull' -- outside the widget runtime dir '$runtimeFull' (read-only guard)."
    }
    return $targetFull
}

# ============================================================================
#  compile-layer counterfactual runner (audit-target s2.5a) -- ZERO model calls
# ============================================================================

function Get-CounterfactualVariations {
    # The varied-input SET for the compile-layer counterfactual (audit-target s2.5a). Each is ONE deterministic
    # varied input on the SAME pinned mock snapshot; the re-compile makes ZERO model calls.
    return @(
        [pscustomobject]@{ id = 'budget'; desc = 'lower the token budget (task.config.token_budget) -> omission delta' }
        [pscustomobject]@{ id = 'temporal_intent'; desc = 'change task.time_horizon -> temporal mode delta' }
        [pscustomobject]@{ id = 'namespace'; desc = 'narrow task.namespace -> effective-namespace / hard-filter delta' }
        [pscustomobject]@{ id = 'channel_mask'; desc = 'mask a retrieval channel (e.g. vector) -> reconciles with #37 hybrid attribution' }
        [pscustomobject]@{ id = 'route'; desc = 'toggle the multi-channel router on/off -> routing_stage_trace + packet-identity delta' }
        [pscustomobject]@{ id = 'exclude_record'; desc = 'drop one record_version_id from the pinned hits -> coverage / disposition delta' }
        [pscustomobject]@{ id = 'selection_policy_version'; desc = 'NAMED but pinned at A1 (#40 imports #37 selpol_rrf_v1; varying it is a follow-on)' }
    )
}

function New-CounterfactualCase {
    <#
        Produce a varied mock CASE on the SAME pinned snapshot: read the base case (a #40 mock case with
        {task, retrieval_batches, source_texts, ...}), apply EXACTLY ONE varied input, write the varied case
        under the widget runtime dir (write-guarded), and return { path, variation, value, description,
        route }. The retrieval_batches (the pinned snapshot) are preserved except for channel_mask /
        exclude_record, which filter hits deterministically WITHOUT changing the corpus_version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BaseCase,           # a parsed case object OR a path to a case json
        [Parameter(Mandatory)][string]$Variation,
        $Value,
        [Parameter(Mandatory)][string]$RuntimeDir
    )
    $case = $BaseCase
    if ($BaseCase -is [string]) { $case = Read-JsonFileSafe -Path $BaseCase; if ($null -eq $case) { throw "New-CounterfactualCase: base case unreadable: $BaseCase" } }
    # deep clone via JSON round-trip (deterministic; the case is plain JSON)
    $json = $case | ConvertTo-Json -Depth 80
    $c = $json | ConvertFrom-Json -Depth 80
    $route = $false
    $desc = ''
    switch ($Variation) {
        'budget' {
            $v = if ($null -ne $Value) { [int]$Value } else { 90 }
            if (-not (Test-HasProp $c 'task')) { throw 'case has no task' }
            if (-not (Test-HasProp $c.task 'config')) { $c.task | Add-Member -NotePropertyName config -NotePropertyValue ([pscustomobject]@{}) -Force }
            $c.task.config | Add-Member -NotePropertyName token_budget -NotePropertyValue $v -Force
            $desc = "token_budget -> $v"
        }
        'temporal_intent' {
            $v = if ($null -ne $Value) { [string]$Value } else { 'any_valid_version' }
            $c.task | Add-Member -NotePropertyName time_horizon -NotePropertyValue $v -Force
            $desc = "time_horizon -> $v"
        }
        'namespace' {
            $v = if ($null -ne $Value) { [string]$Value } else { 'core-docs-none' }
            $c.task | Add-Member -NotePropertyName namespace -NotePropertyValue $v -Force
            $desc = "namespace -> $v"
        }
        'route' {
            $route = $true
            $desc = 'route -> on'
        }
        'channel_mask' {
            # Mask the CONTRIBUTION of a channel: drop only hits ATTRIBUTED-ONLY to that channel (so masking a
            # channel that contributed nothing is a NO-OP). For 'vector': a hit is vector-only iff it has a
            # NON-NULL vector rank/similarity AND no lexical rank -- in a lexical_only corpus NOTHING is
            # vector-only, so the delta is ZERO (reconciles with #37 hybrid attribution: vector rescued 0).
            $mode = if ($null -ne $Value) { [string]$Value } else { 'vector' }
            $removed = 0
            foreach ($b in @(ConvertTo-Array (Get-Prop $c 'retrieval_batches' $null))) {
                $hits = @(ConvertTo-Array (Get-Prop $b 'hits' $null))
                $kept = New-Object System.Collections.Generic.List[object]
                foreach ($h in $hits) {
                    $channels = @(@(ConvertTo-Array (Get-Prop $h 'retrieval_channels' $null)) | ForEach-Object { [string]$_ })
                    $drop = $false
                    if ($mode -eq 'vector') {
                        $vec = Get-Prop $h 'vector_rank' (Get-Prop $h 'vector_similarity' (Get-Prop $h 'vector_score' $null))
                        $lex = Get-Prop $h 'lexical_rank' (Get-Prop $h 'lexical_score' $null)
                        $vectorOnlyByRank = ($null -ne $vec -and $null -eq $lex)
                        $vectorOnlyByChan = ($channels.Count -eq 1 -and $channels -contains 'vector')
                        if ($vectorOnlyByRank -or $vectorOnlyByChan) { $drop = $true }
                    }
                    else {
                        $hm = [string](Get-Prop $h 'mode' (Get-Prop $h 'channel' ''))
                        if ($hm -eq $mode) { $drop = $true }
                        elseif ($channels.Count -eq 1 -and $channels -contains $mode) { $drop = $true }
                    }
                    if ($drop) { $removed++ } else { [void]$kept.Add($h) }
                }
                $b.hits = $kept.ToArray()
            }
            $desc = "mask channel '$mode' (hits removed=$removed)"
        }
        'exclude_record' {
            if ($null -eq $Value) { throw "exclude_record needs -Value <record_version_id>" }
            $rvid = [string]$Value; $removed = 0
            foreach ($b in @(ConvertTo-Array (Get-Prop $c 'retrieval_batches' $null))) {
                $hits = @(ConvertTo-Array (Get-Prop $b 'hits' $null))
                $kept = New-Object System.Collections.Generic.List[object]
                foreach ($h in $hits) {
                    if ([string](Get-Prop $h 'record_version_id' '') -eq $rvid) { $removed++ } else { [void]$kept.Add($h) }
                }
                $b.hits = $kept.ToArray()
            }
            $desc = "exclude record_version_id '$rvid' (hits removed=$removed)"
        }
        'selection_policy_version' {
            throw "selection_policy_version is NAMED but pinned at tier A1 (#40 imports #37's canonical selpol_rrf_v1); varying it is a follow-on."
        }
        default { throw "unknown variation '$Variation' (see Get-CounterfactualVariations)" }
    }
    if (-not (Test-Path -LiteralPath $RuntimeDir -PathType Container)) { New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null }
    $safeName = 'cf-case-' + ($Variation -replace '[^a-zA-Z0-9_]', '_') + '.json'
    $target = Assert-UnderRuntime -Target ([System.IO.Path]::Combine([System.IO.Path]::GetFullPath($RuntimeDir), $safeName)) -RuntimeDir $RuntimeDir
    [System.IO.File]::WriteAllText($target, ($c | ConvertTo-Json -Depth 80), [System.Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{ path = $target; variation = $Variation; value = $Value; description = $desc; route = $route }
}

function Get-PacketDiff {
    <#
        Pure-logic differ over two packets (base vs a compile-layer counterfactual variant). Deterministic;
        string/int only. Returns { base_packet_id, variant_packet_id, packet_id_changed, disposition_delta,
        selected_added[], selected_removed[], omission_added[], omission_removed[], excerpt_count_delta,
        identity_deltas[], summary_lines[] }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$BasePacket, [Parameter(Mandatory)]$VariantPacket)
    $b = Get-PacketFromObject $BasePacket; if ($null -eq $b) { $b = $BasePacket }
    $v = Get-PacketFromObject $VariantPacket; if ($null -eq $v) { $v = $VariantPacket }

    function _selected([object]$pkt) {
        $idn = Get-Prop $pkt 'identity' $null
        return @(@(ConvertTo-Array (Get-Prop $idn 'selected_record_version_ids' $null)) | ForEach-Object { [string]$_ })
    }
    function _omitted([object]$pkt) {
        $acc = New-Object System.Collections.Generic.List[string]
        foreach ($o in @(ConvertTo-Array (Get-Prop $pkt 'omission_manifest' $null))) { [void]$acc.Add([string](Get-Prop $o 'record_version_id' (Get-Prop $o 'record_id' '?'))) }
        return $acc.ToArray()
    }
    $bs = _selected $b; $vs = _selected $v
    $bo = _omitted $b; $vo = _omitted $v
    $selAdded = @($vs | Where-Object { $bs -notcontains $_ })
    $selRemoved = @($bs | Where-Object { $vs -notcontains $_ })
    $omAdded = @($vo | Where-Object { $bo -notcontains $_ })
    $omRemoved = @($bo | Where-Object { $vo -notcontains $_ })

    $bDisp = [string](Get-Prop (Get-Prop $b 'disposition' $null) 'packet_disposition' '?')
    $vDisp = [string](Get-Prop (Get-Prop $v 'disposition' $null) 'packet_disposition' '?')
    $bExc = @(ConvertTo-Array (Get-Prop (Get-Prop $b 'evidence' $null) 'excerpts' $null)).Count
    $vExc = @(ConvertTo-Array (Get-Prop (Get-Prop $v 'evidence' $null) 'excerpts' $null)).Count

    # identity field deltas (the fields packet identity covers)
    $idDeltas = New-Object System.Collections.Generic.List[string]
    $bId = Get-Prop $b 'identity' $null; $vId = Get-Prop $v 'identity' $null
    foreach ($k in 'budget', 'current_only', 'query_class', 'corpus_version', 'omission_manifest_digest', 'retrieval_plan_digest', 'routing_plan_digest', 'task_descriptor_digest') {
        $bv = [string](Get-Prop $bId $k '(absent)'); $vv = [string](Get-Prop $vId $k '(absent)')
        if ($bv -ne $vv) { [void]$idDeltas.Add($k + ': ' + (Limit-Text $bv 24) + ' -> ' + (Limit-Text $vv 24)) }
    }
    # allowed_namespaces delta
    $bns = (Get-EffectiveNamespaces -Packet $b) -join ','
    $vns = (Get-EffectiveNamespaces -Packet $v) -join ','
    if ($bns -ne $vns) { [void]$idDeltas.Add('effective_namespaces: [' + $bns + '] -> [' + $vns + ']') }

    $bpid = [string](Get-Prop $b 'packet_id' '?'); $vpid = [string](Get-Prop $v 'packet_id' '?')
    $summary = New-Object System.Collections.Generic.List[string]
    $pidChangedWord = if ($bpid -ne $vpid) { 'yes' } else { 'no' }
    [void]$summary.Add('packet_id: ' + $bpid + ' -> ' + $vpid + '  (changed=' + $pidChangedWord + ')')
    [void]$summary.Add('disposition: ' + $bDisp + ' -> ' + $vDisp)
    [void]$summary.Add('excerpts: ' + $bExc + ' -> ' + $vExc + '  (delta ' + ($vExc - $bExc) + ')')
    [void]$summary.Add('selected: +' + @($selAdded).Count + ' / -' + @($selRemoved).Count + '   omitted: +' + @($omAdded).Count + ' / -' + @($omRemoved).Count)
    if (@($selRemoved).Count -gt 0) { [void]$summary.Add('  selected removed: ' + ((@($selRemoved) | ForEach-Object { Limit-Text $_ 28 }) -join ', ')) }
    if (@($selAdded).Count -gt 0) { [void]$summary.Add('  selected added:   ' + ((@($selAdded) | ForEach-Object { Limit-Text $_ 28 }) -join ', ')) }
    foreach ($d in $idDeltas) { [void]$summary.Add('  identity ' + $d) }

    return [pscustomobject]@{
        base_packet_id = $bpid; variant_packet_id = $vpid; packet_id_changed = ($bpid -ne $vpid)
        disposition_delta = [pscustomobject]@{ from = $bDisp; to = $vDisp; changed = ($bDisp -ne $vDisp) }
        selected_added = @($selAdded); selected_removed = @($selRemoved)
        omission_added = @($omAdded); omission_removed = @($omRemoved)
        excerpt_count_delta = ($vExc - $bExc)
        identity_deltas = $idDeltas.ToArray()
        summary_lines = $summary.ToArray()
    }
}

function Resolve-Python {
    # Find a stdlib python for the re-compile. Mirrors #40's resolution (explicit Windows paths + where.exe)
    # so the on-box runner resolves python the same way #40 does. Order: -PythonPath, env, known Windows
    # paths, python3/python/py by name, then where.exe hits.
    param([string]$PythonPath)
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { [void]$cands.Add($PythonPath) }
    if ($env:LIFEORCH_CTC_PYTHON) { [void]$cands.Add($env:LIFEORCH_CTC_PYTHON) }
    [void]$cands.Add('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe')
    [void]$cands.Add('F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe')
    foreach ($n in 'python3', 'python', 'py') { [void]$cands.Add($n) }
    # where.exe hits (Windows only; ignored elsewhere)
    foreach ($n in 'python', 'python3', 'py') {
        try {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $w = & where.exe $n 2>$null
            $ErrorActionPreference = $prev
            foreach ($line in @([string[]]$w)) { if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$cands.Add($line.Trim()) } }
        }
        catch { }
    }
    foreach ($c in ($cands.ToArray() | Select-Object -Unique)) {
        try {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            & $c -c 'import json,hashlib,re,math,importlib.util' 2>$null | Out-Null
            $ok = ($LASTEXITCODE -eq 0)
            $ErrorActionPreference = $prev
            if ($ok) { return $c }
        }
        catch { }
    }
    return $null
}

function Invoke-CtcCompileWorker {
    # Re-invoke #40's DETERMINISTIC compile worker (context_compiler.py) on a mock case -> the parsed packet.
    # This IS #40's compile engine (the CLI wraps it); we invoke it READ-ONLY, zero model calls, all scratch
    # under the widget runtime dir. Returns { ok, packet, dir, error }.
    param([string]$Python, [string]$Worker, $Case, [bool]$Route, [string]$OutDir, [string]$RuntimeDir)
    $OutDir = Assert-UnderRuntime -Target $OutDir -RuntimeDir $RuntimeDir
    if (-not (Test-Path -LiteralPath $OutDir -PathType Container)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    $caseObj = $Case
    if ($Case -is [string]) { $caseObj = Read-JsonFileSafe -Path $Case; if ($null -eq $caseObj) { return [pscustomobject]@{ ok = $false; packet = $null; dir = $OutDir; error = 'case unreadable' } } }
    # assemble the worker args = the case fields + op=compile [+ route]  (avoid the automatic $args var)
    $workerArgs = [ordered]@{}
    foreach ($n in @(Get-PropNames $caseObj)) { $workerArgs[$n] = $caseObj.$n }
    $workerArgs['op'] = 'compile'
    if ($Route) { $workerArgs['route'] = $true }
    $metaPath = [System.IO.Path]::Combine($OutDir, 'cc_meta.json')
    $workerArgs['output_dir'] = $OutDir
    $workerArgs['meta_path'] = $metaPath
    $argsFile = [System.IO.Path]::Combine($OutDir, 'cc_args.json')
    [System.IO.File]::WriteAllText($argsFile, ($workerArgs | ConvertTo-Json -Depth 80), [System.Text.UTF8Encoding]::new($false))
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $Python $Worker $argsFile 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; packet = $null; dir = $OutDir; error = "worker produced no meta (exit $code): $(Limit-Text ($out | Out-String) 200)" }
    }
    $meta = Read-JsonFileSafe -Path $metaPath
    $p = Get-PacketFromObject $meta
    if ($null -eq $p) { return [pscustomobject]@{ ok = $false; packet = $null; dir = $OutDir; error = 'no packet in worker meta' } }
    return [pscustomobject]@{ ok = $true; packet = $p; dir = $OutDir; error = '' }
}

function Invoke-CompileCounterfactual {
    <#
        The compile-layer counterfactual runner (audit-target s2.5a): re-run the SAME pinned mock snapshot
        through #40's deterministic compile worker with EXACTLY ONE varied input, and DIFF the two packets.
        ZERO model calls (mock retriever, deterministic re-compile). ALL scratch is written under the widget's
        OWN runtime dir (write-guarded). Returns { ok, variation, description, base_packet, variant_packet,
        diff, error }. Never throws to the UI (returns ok=false + error).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseCasePath,
        [Parameter(Mandatory)][string]$Variation,
        $Value,
        [string]$CompilerWorker,
        [string]$PythonPath,
        [string]$RepoRoot,
        [string]$WidgetRoot,
        [string]$RuntimeDir
    )
    try {
        $paths = Resolve-CompileTracePaths -WidgetRoot $WidgetRoot -RepoRoot $RepoRoot
        if (-not $RuntimeDir) { $RuntimeDir = $paths.RuntimeDir }
        if (-not $CompilerWorker) { $CompilerWorker = $paths.CompilerWorker }
        if (-not (Test-Path -LiteralPath $CompilerWorker -PathType Leaf)) { return [pscustomobject]@{ ok = $false; error = "compiler worker not found: $CompilerWorker"; variation = $Variation } }
        $python = Resolve-Python -PythonPath $PythonPath
        if ($null -eq $python) { return [pscustomobject]@{ ok = $false; error = 'no usable python for the re-compile'; variation = $Variation } }

        $cfRoot = [System.IO.Path]::Combine([System.IO.Path]::GetFullPath($RuntimeDir), 'counterfactual')
        [void](Assert-UnderRuntime -Target $cfRoot -RuntimeDir $RuntimeDir)
        if (-not (Test-Path -LiteralPath $cfRoot -PathType Container)) { New-Item -ItemType Directory -Path $cfRoot -Force | Out-Null }

        # base compile (the pinned snapshot, no variation)
        $baseCase = Read-JsonFileSafe -Path $BaseCasePath
        if ($null -eq $baseCase) { return [pscustomobject]@{ ok = $false; error = "base case unreadable: $BaseCasePath"; variation = $Variation } }
        $baseRun = Invoke-CtcCompileWorker -Python $python -Worker $CompilerWorker -Case $baseCase -Route:$false -OutDir ([System.IO.Path]::Combine($cfRoot, 'base')) -RuntimeDir $RuntimeDir
        if (-not $baseRun.ok) { return [pscustomobject]@{ ok = $false; error = 'base compile failed: ' + $baseRun.error; variation = $Variation } }

        # variant: apply ONE varied input, re-compile
        $cf = New-CounterfactualCase -BaseCase $baseCase -Variation $Variation -Value $Value -RuntimeDir $cfRoot
        $variantRun = Invoke-CtcCompileWorker -Python $python -Worker $CompilerWorker -Case $cf.path -Route:$cf.route -OutDir ([System.IO.Path]::Combine($cfRoot, 'variant')) -RuntimeDir $RuntimeDir
        if (-not $variantRun.ok) { return [pscustomobject]@{ ok = $false; error = 'variant compile failed: ' + $variantRun.error; variation = $Variation } }

        $diff = Get-PacketDiff -BasePacket $baseRun.packet -VariantPacket $variantRun.packet
        return [pscustomobject]@{
            ok = $true; error = ''; variation = $Variation; description = $cf.description
            base_packet = $baseRun.packet; variant_packet = $variantRun.packet; diff = $diff
        }
    }
    catch { return [pscustomobject]@{ ok = $false; error = 'counterfactual runner threw: ' + $_.Exception.Message; variation = $Variation } }
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Prop, ConvertTo-Array, Get-PropNames, Limit-Text, Get-Sha256Hex, `
    Read-JsonFileSafe, Read-TextFileSafe, Format-Bool, Resolve-CompileTracePaths, `
    Get-PacketFromObject, Read-ContextPacket, Read-EvalReport, Read-FoldSmoke, `
    Get-EffectiveNamespaces, Test-TraceSanitized, `
    Get-Pane1Timeline, Get-Pane2ModelView, Get-Pane3RetrievalTrace, Get-Pane4RuleStack, Get-Pane6TokenLedger, `
    Get-CompileTraceModel, Format-CompileTraceHeader, Format-CompanionRows, `
    Assert-UnderRuntime, Get-CounterfactualVariations, New-CounterfactualCase, Get-PacketDiff, `
    Resolve-Python, Invoke-CtcCompileWorker, Invoke-CompileCounterfactual
