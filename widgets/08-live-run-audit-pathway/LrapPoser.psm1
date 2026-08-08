<#
    LrapPoser.psm1 -- the Live-Run Audit Pathway (Widget 08) INTERPRETABILITY POSER core (D-0126).

    WHAT: for any element of the LRAP surface (the header verdict, a step, or one of a step's four lanes) it
    builds a per-element CONTEXT BUNDLE -- a plain-language projection of the ALREADY-BUILT Get-LrapModel (no
    recompute, no model call) -- and the {system, messages} prompt that a local-9B query is fed. The widget's
    "?" affordance opens a pop-up chat seeded with that bundle; the actual model call happens OUT-OF-BAND in
    Invoke-LrapPoserQuery.ps1 (a separate process, the res.lease/#7-gateway path), so the read-only widget
    process itself NEVER calls a model and NEVER holds a lease (D-0126 invariant; README/WORK_ORDER poser note).

    THE INFORMATION-ONLY INVARIANT (why this ships ungated, D-0126): this module (1) READS a model object +
    (2) writes ONLY request/answer files UNDER the widget runtime dir (every write goes through
    _AssertPoserUnderRuntime, mirroring the core Assert-UnderRuntime guard). It writes no other state, mutates
    no packet, drives no decision. Its output is ADVISORY (the operator judges it). Any change that breaches
    this (letting the poser tag / verify / mutate anything) RE-OPENS the gating question -- do not make it
    silently.

    THE GUARDRAIL (Get-LrapPoserSystemPrompt): the model EXPLAINS the instrument + the recorded facts and must
    NOT judge whether the run is CORRECT (the F1/P9 line: the widget shows, it does not judge; the human makes
    the comparative determination). A green/consistent verdict = counts reconcile, never "correct".

    Pure + WinForms-free + ASCII-only (runs on the cloud gate). Depends on NOTHING at import time.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LrapPoserVersion = '0.1.0'
$script:LrapPoserModel9b = 'llm.strong.qwen3p5-9b'   # the resident STRONG tier (D-0058 S0); >= ~1024 tok or it returns empty
$script:LrapPoserMaxTokens = 1280
$script:LrapPoserReqSchema = 'lifeorch.lrap_poser_request/0.1'
$script:LrapPoserAnsSchema = 'lifeorch.lrap_poser_answer/0.1'

# ---- private helpers (inlined so the module loads standalone on the cloud gate) ----

function _PGet {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value }
    return $Default
}

function _PArr { param($V) if ($null -eq $V) { return @() } if ($V -is [string]) { return @($V) } if ($V -is [System.Collections.IEnumerable]) { return @($V) } return @($V) }

function _PClip { param([string]$S, [int]$Max = 160) if ($null -eq $S) { return '' } $s = [string]$S; if ($s.Length -le $Max) { return $s } return $s.Substring(0, $Max - 3) + '...' }

function _AssertPoserUnderRuntime {
    # Defense-in-depth, mirrors the core Assert-UnderRuntime: refuse any write outside the widget runtime dir.
    param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$RuntimeDir)
    $runtimeFull = [System.IO.Path]::GetFullPath($RuntimeDir)
    $targetFull = [System.IO.Path]::GetFullPath($Target)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $guard = $runtimeFull.TrimEnd($sep) + $sep
    if (-not $targetFull.StartsWith($guard, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "LRAP poser refused a write to '$targetFull' -- outside the widget runtime dir '$runtimeFull' (read-only guard)."
    }
    return $targetFull
}

# ============================================================================
#  addressable elements (where the UI attaches a "?")
# ============================================================================

function Get-LrapPoserElements {
    # The ordered list of elements a "?" can sit beside, derived from a built model. Header always; then, for an
    # ok model, each step and each of its four lanes. A not-ok model exposes only the header.
    [CmdletBinding()] param([Parameter(Mandatory)]$Model)
    $out = New-Object System.Collections.Generic.List[object]
    [void]$out.Add([pscustomobject]@{ element_id = 'header'; kind = 'verdict'; label = 'Overall verdict'; step_no = 0; lane = '' })
    if (-not (_PGet $Model 'ok' $false)) { return $out.ToArray() }
    foreach ($s in @(_PArr (_PGet $Model 'steps'))) {
        $n = [int](_PGet $s 'step_no' 0)
        $title = [string](_PGet $s 'title' ('step ' + $n))
        [void]$out.Add([pscustomobject]@{ element_id = ('step:' + $n); kind = 'step'; label = ('Step ' + $n + ' - ' + $title); step_no = $n; lane = '' })
        foreach ($lane in 'intent', 'input', 'output', 'reconcile') {
            [void]$out.Add([pscustomobject]@{ element_id = ('step:' + $n + ':' + $lane); kind = 'lane'; label = ('Step ' + $n + ' ' + $lane.ToUpperInvariant()); step_no = $n; lane = $lane.ToUpperInvariant() })
        }
    }
    return $out.ToArray()
}

function _FindStep { param($Model, [int]$N) foreach ($s in @(_PArr (_PGet $Model 'steps'))) { if ([int](_PGet $s 'step_no' 0) -eq $N) { return $s } } return $null }

# ============================================================================
#  the per-element context bundle (a pure projection of Get-LrapModel)
# ============================================================================

function Get-LrapPoserBundle {
    <#
        Build the CONTEXT BUNDLE for one element_id over a built model. Pure: reads the model, writes nothing,
        calls no model. Returns { ok, element_id, kind, label, step_no, lane, packet_id, is_flat, intent,
        actual, reconcile, honesty_class, overall, context_text }. context_text is the plain-language block that
        is BOTH the substrate fed to the 9B AND what the operator can read (the legibility-proxy: if the 9B
        cannot explain the element from this block, the block -- not the operator -- is what is insufficient).
        An unknown element_id yields a well-formed ok=false bundle, never a throw.
    #>
    [CmdletBinding()] param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][string]$ElementId)

    $packetId = [string](_PGet $Model 'packet_id' '')
    $isFlat = _PGet $Model 'is_flat' $null
    $overall = _PGet $Model 'overall' $null
    $overallClass = if ($null -ne $overall) { [string](_PGet $overall 'classification' '') } else { '' }
    $incStep = if ($null -ne $overall) { [int](_PGet $overall 'inconsistent_step' 0) } else { 0 }

    $L = New-Object System.Collections.Generic.List[string]
    $bundle = [ordered]@{
        ok = $true; element_id = $ElementId; kind = ''; label = ''; step_no = 0; lane = ''
        packet_id = $packetId; is_flat = $isFlat
        intent = $null; actual = $null; reconcile = $null; honesty_class = ''
        overall = [pscustomobject]@{ classification = $overallClass; inconsistent_step = $incStep }
        context_text = ''
    }

    if (-not (_PGet $Model 'ok' $false) -and $ElementId -ne 'header') {
        $bundle.ok = $false
    }

    # ---- header ----
    if ($ElementId -eq 'header') {
        $bundle.kind = 'verdict'; $bundle.label = 'Overall verdict'
        [void]$L.Add('ELEMENT: the run''s OVERALL VERDICT (the header).')
        [void]$L.Add('packet_id: ' + $packetId + '   compile: ' + $(if ($isFlat -eq $true) { 'flat (no router)' } elseif ($isFlat -eq $false) { 'routed' } else { 'unknown' }))
        if (-not (_PGet $Model 'ok' $false)) {
            [void]$L.Add('This run FAILED to load: ' + [string](_PGet $Model 'error' ''))
        }
        else {
            [void]$L.Add('VERDICT: ' + $overallClass)
            [void]$L.Add('Per-step reconcile verdicts:')
            foreach ($ps in @(_PArr (_PGet $overall 'per_step'))) {
                [void]$L.Add('  step ' + [string](_PGet $ps 'step_no' '?') + ' (' + [string](_PGet $ps 'step_key' '?') + '): ' + [string](_PGet $ps 'verdict' '?'))
            }
        }
        [void]$L.Add('')
        [void]$L.Add('IMPORTANT: a "consistent"/green verdict means the COUNTS RECONCILE at every step -- it is a')
        [void]$L.Add('necessary-not-sufficient signal, NEVER a claim the run is correct. "INCONSISTENT at step N"')
        [void]$L.Add('means a substrate set/count/arithmetic identity failed at step N.')
        $bundle.context_text = ($L -join "`n")
        return [pscustomobject]$bundle
    }

    # ---- parse a step / lane element id ----
    $m = [regex]::Match($ElementId, '^step:(\d+)(?::(intent|input|output|reconcile))?$')
    if (-not $m.Success) {
        $bundle.ok = $false; $bundle.kind = 'unknown'; $bundle.label = ('unknown element: ' + $ElementId)
        $bundle.context_text = 'No such audit element: ' + $ElementId
        return [pscustomobject]$bundle
    }
    $n = [int]$m.Groups[1].Value
    $lane = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { '' }
    $step = _FindStep -Model $Model -N $n
    if ($null -eq $step) {
        $bundle.ok = $false; $bundle.kind = 'unknown'; $bundle.label = ('no such step: ' + $n)
        $bundle.context_text = 'No such step in this run: step ' + $n
        return [pscustomobject]$bundle
    }

    $title = [string](_PGet $step 'title' ('step ' + $n))
    $intentObj = _PGet $step 'intent' $null
    $inputObj = _PGet $step 'input' $null
    $outputObj = _PGet $step 'output' $null
    $recObj = _PGet $step 'reconcile' $null

    $bundle.step_no = $n
    $bundle.lane = $lane.ToUpperInvariant()
    $bundle.intent = [pscustomobject]@{
        text = [string](_PGet $intentObj 'text' '')
        contract_clause = [string](_PGet $intentObj 'contract_clause' '')
        contract_version = [string](_PGet $intentObj 'contract_version' '')
    }
    $bundle.actual = [pscustomobject]@{
        input_class = [string](_PGet $inputObj 'class' '')
        input_lines = @(_PArr (_PGet $inputObj 'lines'))
        output_class = [string](_PGet $outputObj 'class' '')
        output_lines = @(_PArr (_PGet $outputObj 'lines'))
    }
    $bundle.reconcile = [pscustomobject]@{
        verdict = [string](_PGet $recObj 'verdict' '')
        marker = [string](_PGet $recObj 'marker' '')
        lane_class = [string](_PGet $recObj 'lane_class' '')
        identities = @(_PArr (_PGet $recObj 'identities'))
        offenders = @(_PArr (_PGet $recObj 'offenders'))
        descend_prose = @(_PArr (_PGet $recObj 'descend_prose'))
        p2_notes = @(_PArr (_PGet $recObj 'p2_notes'))
    }

    # Every element gets the FULL step context (intent + input + output + reconcile) so the operator -- and the
    # 9B -- can adopt the agent's role and compare (the D-0125 possession point: intent, actual, and verdict are
    # only useful TOGETHER). A lane element adds a FOCUS marker + drives the default question; it does not strip
    # the rest of the context.
    if ($lane -eq '') { $bundle.kind = 'step'; $bundle.label = ('Step ' + $n + ' - ' + $title); $bundle.honesty_class = '' }
    else {
        $bundle.kind = 'lane'; $bundle.label = ('Step ' + $n + ' ' + $lane.ToUpperInvariant())
        $bundle.honesty_class = switch ($lane) { 'intent' { 'AUTH' } 'input' { $bundle.actual.input_class } 'output' { $bundle.actual.output_class } 'reconcile' { $bundle.reconcile.lane_class } }
    }

    [void]$L.Add('ELEMENT: Step ' + $n + ' (' + $title + ')' + $(if ($lane -ne '') { ' -- FOCUS on the ' + $lane.ToUpperInvariant() + ' lane (full step context follows)' } else { ' -- all four lanes' }))
    [void]$L.Add('This step is part of the six-step packet-assembly pathway: 1 normalize -> 2 retrieve -> 3 route -> 4 select -> 5 budget -> 6 packet.')
    [void]$L.Add('')
    [void]$L.Add('WHAT THIS STEP IS SUPPOSED TO DO (authored INTENT; the yardstick, paraphrasing the contract):')
    [void]$L.Add('  ' + $bundle.intent.text)
    [void]$L.Add('  (contract: ' + $bundle.intent.contract_clause + '  [' + $bundle.intent.contract_version + '])')
    [void]$L.Add('')
    [void]$L.Add('ACTUAL INPUT to this step (recorded facts):')
    foreach ($ln in $bundle.actual.input_lines) { [void]$L.Add('  ' + [string]$ln) }
    [void]$L.Add('')
    [void]$L.Add('ACTUAL OUTPUT of this step (recorded facts):')
    foreach ($ln in $bundle.actual.output_lines) { [void]$L.Add('  ' + [string]$ln) }
    [void]$L.Add('')
    if ($true) {
        [void]$L.Add('RECONCILE -- a machine set/count/arithmetic check the substrate already computed (NOT a judgment of correctness):')
        [void]$L.Add('  verdict: ' + $bundle.reconcile.verdict + '   (' + $bundle.reconcile.marker + ')')
        if (@($bundle.reconcile.identities).Count -gt 0) {
            [void]$L.Add('  identities checked:')
            foreach ($id in $bundle.reconcile.identities) {
                $held = _PGet $id 'held' $null
                [void]$L.Add('    - [' + $(if ($held -eq $true) { 'held' } elseif ($held -eq $false) { 'FAILED' } else { 'n/a' }) + '] ' + [string](_PGet $id 'name' '') + '  (' + (_PClip ([string](_PGet $id 'detail' '')) 120) + ')')
            }
        }
        foreach ($d in $bundle.reconcile.descend_prose) { [void]$L.Add('  - ' + (_PClip ([string]$d) 400)) }
        if (@($bundle.reconcile.offenders).Count -gt 0) { [void]$L.Add('  offending record ids: ' + ((@($bundle.reconcile.offenders)) -join ', ')) }
        foreach ($p in $bundle.reconcile.p2_notes) { [void]$L.Add('  P2 (explicitly NOT judged in v1): ' + (_PClip ([string]$p) 300)) }
        [void]$L.Add('')
    }
    [void]$L.Add('RUN CONTEXT: overall = ' + $overallClass + $(if ($incStep -gt 0) { ' (first inconsistent step: ' + $incStep + ')' } else { '' }) + '.')
    [void]$L.Add('Reminder: green/consistent = counts reconcile, never a claim the run is correct.')
    $bundle.context_text = ($L -join "`n")
    return [pscustomobject]$bundle
}

# ============================================================================
#  the prompt (system guardrail + messages)
# ============================================================================

function Get-LrapPoserSystemPrompt {
    # The guardrail. EXPLAIN the instrument + recorded facts; do NOT judge whether the run is correct.
    return @'
You are an interpretability helper embedded in a strictly read-only audit tool called LRAP (the Live-Run Audit
Pathway). LRAP walks a completed context-compile as six steps, each with an INTENT (what it should do), the
ACTUAL input and output, and a RECONCILE line (a machine count/set/arithmetic check).

Your ONLY job: explain, in plain language, WHAT the highlighted element is and WHAT actually happened there,
using ONLY the CONTEXT block the user provides. You are advisory -- the operator will verify you.

Hard rules:
1. Explain the instrument and the RECORDED FACTS. Do NOT judge whether the run was correct, whether a routing or
   selection decision was right, or whether a dropped record SHOULD have been kept. Those judgments belong to
   the operator; surface the facts and the mechanism, not a verdict on them.
2. Use ONLY the provided context. If it does not contain enough to answer, say so plainly (e.g. "the surface
   does not expose that here") instead of guessing or drawing on outside assumptions.
3. A "consistent"/green RECONCILE means the counts reconcile -- it is necessary-not-sufficient, NEVER a claim
   the run is correct. Never imply correctness from a green verdict.
4. Be concise and concrete: name the specific steps, counts, identities, and record ids that appear in the
   context. Do not invent ids or numbers that are not present.
'@
}

function Get-LrapPoserPrompt {
    # Build { system, messages[] } for the gateway. PriorTurns is an array of {role,content} (user/assistant)
    # from earlier in this pop-up conversation; Question is the operator's current question (empty => the
    # default "explain this element" seed).
    [CmdletBinding()] param([Parameter(Mandatory)]$Bundle, [string]$Question = '', $PriorTurns = @())
    $q = if ([string]::IsNullOrWhiteSpace($Question)) { 'Explain this element: what is it, and what did the agent actually do here?' } else { [string]$Question }
    $messages = New-Object System.Collections.Generic.List[object]
    foreach ($t in @(_PArr $PriorTurns)) {
        [void]$messages.Add([pscustomobject]@{ role = [string](_PGet $t 'role' 'user'); content = [string](_PGet $t 'content' '') })
    }
    $userContent = 'CONTEXT (the highlighted element of the audit surface):' + "`n" + [string](_PGet $Bundle 'context_text' '') + "`n`nQUESTION: " + $q
    [void]$messages.Add([pscustomobject]@{ role = 'user'; content = $userContent })
    return [pscustomobject]@{ system = (Get-LrapPoserSystemPrompt); messages = $messages.ToArray() }
}

# ============================================================================
#  the runtime-guarded request / answer file protocol
# ============================================================================

function Get-LrapPoserDir {
    # runtime\poser under the widget runtime dir; creates it (guarded). Returns the full path.
    [CmdletBinding()] param([Parameter(Mandatory)][string]$RuntimeDir)
    $dir = [System.IO.Path]::Combine($RuntimeDir, 'poser')
    [void](_AssertPoserUnderRuntime -Target $dir -RuntimeDir $RuntimeDir)
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    return $dir
}

function New-LrapPoserRequest {
    <#
        Write a request file the out-of-band worker consumes. Runtime-guarded. Returns
        { request_id, request_path, answer_path, model, max_tokens }. The widget then spawns
        Invoke-LrapPoserQuery.ps1 -RequestPath <request_path> DETACHED and polls answer_path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuntimeDir,
        [Parameter(Mandatory)]$Bundle,
        [string]$Question = '',
        $PriorTurns = @(),
        [string]$Model = $script:LrapPoserModel9b,
        [int]$MaxTokens = $script:LrapPoserMaxTokens,
        [string]$RequestId
    )
    $dir = Get-LrapPoserDir -RuntimeDir $RuntimeDir
    if ([string]::IsNullOrWhiteSpace($RequestId)) { $RequestId = 'q-' + ([guid]::NewGuid().ToString('N').Substring(0, 12)) }
    $prompt = Get-LrapPoserPrompt -Bundle $Bundle -Question $Question -PriorTurns $PriorTurns
    $reqPath = [System.IO.Path]::Combine($dir, $RequestId + '.request.json')
    $ansPath = [System.IO.Path]::Combine($dir, $RequestId + '.answer.json')
    [void](_AssertPoserUnderRuntime -Target $reqPath -RuntimeDir $RuntimeDir)
    $req = [ordered]@{
        schema = $script:LrapPoserReqSchema
        request_id = $RequestId
        element_id = [string](_PGet $Bundle 'element_id' '')
        model = $Model
        max_tokens = $MaxTokens
        temperature = 0
        system = $prompt.system
        messages = $prompt.messages
        question = $Question
        created_ticks = [System.DateTime]::UtcNow.Ticks
    }
    $json = $req | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $reqPath -Value $json -Encoding utf8 -NoNewline
    return [pscustomobject]@{ request_id = $RequestId; request_path = $reqPath; answer_path = $ansPath; model = $Model; max_tokens = $MaxTokens }
}

function Read-LrapPoserRequest {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$RequestPath)
    if (-not (Test-Path -LiteralPath $RequestPath)) { throw "LRAP poser request not found: $RequestPath" }
    return (Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json)
}

function Write-LrapPoserAnswer {
    <#
        Write the answer file (runtime-guarded). Called by the out-of-band worker. FAIL-SILENT contract: on a
        query failure the worker still writes an answer with ok=false + a short note, so the pop-up shows
        "explanation unavailable" rather than hanging forever.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuntimeDir,
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][bool]$Ok,
        [string]$Text = '',
        [string]$FinishReason = '',
        [string]$ErrorText = ''
    )
    $dir = Get-LrapPoserDir -RuntimeDir $RuntimeDir
    $ansPath = [System.IO.Path]::Combine($dir, $RequestId + '.answer.json')
    [void](_AssertPoserUnderRuntime -Target $ansPath -RuntimeDir $RuntimeDir)
    $ans = [ordered]@{
        schema = $script:LrapPoserAnsSchema
        request_id = $RequestId
        ok = $Ok
        text = $Text
        finish_reason = $FinishReason
        error = $ErrorText
        created_ticks = [System.DateTime]::UtcNow.Ticks
    }
    $tmp = $ansPath + '.tmp'
    Set-Content -LiteralPath $tmp -Value ($ans | ConvertTo-Json -Depth 6) -Encoding utf8 -NoNewline
    Move-Item -LiteralPath $tmp -Destination $ansPath -Force   # atomic publish, so a poll never reads a half-written answer
    return $ansPath
}

function Read-LrapPoserAnswer {
    # Poll helper: returns the parsed answer object if present + parseable, else $null (still pending).
    [CmdletBinding()] param([Parameter(Mandatory)][string]$AnswerPath)
    if (-not (Test-Path -LiteralPath $AnswerPath)) { return $null }
    try { return (Get-Content -LiteralPath $AnswerPath -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-LrapPoserInfo {
    return [pscustomobject]@{
        poser_version = $script:LrapPoserVersion
        model = $script:LrapPoserModel9b
        max_tokens = $script:LrapPoserMaxTokens
        request_schema = $script:LrapPoserReqSchema
        answer_schema = $script:LrapPoserAnsSchema
    }
}

Export-ModuleMember -Function `
    Get-LrapPoserElements, Get-LrapPoserBundle, Get-LrapPoserSystemPrompt, Get-LrapPoserPrompt, `
    Get-LrapPoserDir, New-LrapPoserRequest, Read-LrapPoserRequest, Write-LrapPoserAnswer, Read-LrapPoserAnswer, `
    Get-LrapPoserInfo
