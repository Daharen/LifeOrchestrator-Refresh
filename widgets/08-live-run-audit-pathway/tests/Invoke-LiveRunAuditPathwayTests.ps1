<#
    Invoke-LiveRunAuditPathwayTests.ps1 - dual-mode test harness for the Live-Run Audit Pathway (Widget 08).

    Cloud pre-ship gate (Linux, no -Live): AST-parse + ASCII-guard every shipped script; drive the REAL core
    (LiveRunAuditPathway.psm1) + the pinned adapter (LrapReaderAdapter.psm1) over committed REAL fixtures (five
    #40 context_packet/0.2 artifacts minted from the shipped 06/07 routed + flat seeds) --
      - the READER ADAPTER + the CROSS-WIDGET CONTRACT TEST (06/07 shape drift fails closed; recompute excluded);
      - the HONESTY MAP (s3a): every per-step x per-lane cell matches the fixed classification; every P2 cell
        renders a VISIBLE "not emitted yet" lane (never blank, never a computed stand-in);
      - RECONCILE is VERDICT-BACKED ONLY (s2/F1): each identity is a substrate set/count/arithmetic check; a
        corrupted count is caught; semantic judgments are logged as P2, never smuggled into a verdict;
      - the FIVE-FIXTURE machine classification (design s7): clean -> consistent; mis-route -> inconsistent at
        step 3; dropped-candidate -> step 4; wrong-record -> step 6; flat-quirk -> consistent (NOT false-flagged).
        False-positives (clean/quirk flagged) + false-negatives (defect missed) scored separately;
      - DESCEND (s4/F7): the plain-language "why" names the offending records/counts + the failed identity and
        is NOT a raw pane; the raw 06/07 pane is reachable only via the explicit affordance;
      - the INTENT catalog + its own review (s3b): every block cites a contract clause + version; reviewer named;
      - byte-identical re-render; the read-only guarantees (fixtures tree byte-identical; write-guard refuses
        escape; i33 router-trace sanitization + an injected cross-ns key fails closed).

    Live (Windows, via the executor, -Live): the same PLUS launch.bat shape, the WinForms -SelfTest in an STA
    child (SELFTEST_FORM/MODEL/PANES/RECONCILE/DESCEND/SANITIZE/REFRESH/READONLY/LAYOUT _OK), and -- if the
    production runtime is present -- a render of a real on-box #40 artifact with no throw.
#>
[CmdletBinding()]
param([switch]$Live, [string]$PwshPath, [string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$widgetRoot = Split-Path $here -Parent
# Import the core FIRST (it nested-imports the adapter for its own use), then the adapter at session scope so
# the harness can drive the pinned wrappers directly (importing the adapter first, then the core with -Force,
# would let the core's nested re-import steal the adapter out of session scope).
Import-Module (Join-Path $widgetRoot 'LiveRunAuditPathway.psm1') -Force
Import-Module (Join-Path $widgetRoot 'LrapReaderAdapter.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}

$fx = Join-Path $here 'fixtures'
$fClean = Join-Path $fx 'clean_routed.json'
$fMisRoute = Join-Path $fx 'defect_mis_route.json'
$fDropped = Join-Path $fx 'defect_dropped_candidate.json'
$fWrong = Join-Path $fx 'defect_wrong_record.json'
$fFlat = Join-Path $fx 'quirk_flat.json'

$script:pass = 0; $script:fail = 0; $script:skip = 0
function Ok([string]$name, $cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name   $detail" }
}
function Skip([string]$name, [string]$why) { $script:skip++; Write-Host "  [SKIP] $name ($why)" }
$script:tempRoots = New-Object System.Collections.Generic.List[string]
function New-TempDir([string]$tag) {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ($tag + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $d -Force | Out-Null; $script:tempRoots.Add($d); return $d
}
function Get-TreeSig([string]$Root) {
    $acc = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        [void]$acc.Add($f.FullName + '|' + [string]$f.Length + '|' + $f.LastWriteTimeUtc.ToString('o'))
    }
    return ($acc.ToArray() -join "`n")
}

Write-Host "=== Live-Run Audit Pathway tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist (core + adapter)
foreach ($fn in 'Get-LrapModel', 'Get-LrapVerdict', 'Get-LrapSpine', 'Get-LrapStepReconcile', 'Get-LrapHonestyMap',
    'Get-LrapHonestyCell', 'Get-LrapP2Backlog', 'Get-LrapIntentCatalog', 'Get-LrapIntentCatalogReview',
    'Get-LrapStepDescend', 'Get-LrapRawTraceForStep', 'Format-LrapHeader', 'Get-LrapPacketExclusionViolations',
    'Get-LrapUnexplainedDrops', 'Resolve-LrapPaths', 'Assert-UnderRuntime',
    'Read-LrapPacket', 'Get-LrapRouterBracket', 'Get-LrapSelectionBracket', 'Test-LrapTraceSanitized',
    'Get-LrapAdapterInfo', 'Test-LrapAdapterContract') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse + 2b. ASCII-only guard on every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'LiveRunAuditPathway.psm1'),
    (Join-Path $widgetRoot 'LrapReaderAdapter.psm1'),
    (Join-Path $widgetRoot 'Show-LiveRunAuditPathway.ps1'),
    (Join-Path $widgetRoot 'LrapPoser.psm1'),
    (Join-Path $widgetRoot 'Invoke-LrapPoserQuery.ps1'),
    (Join-Path $here 'Invoke-LiveRunAuditPathwayTests.ps1'),
    (Join-Path $here 'mock-poser-gateway.ps1'),
    (Join-Path $fx 'mint-fixtures.ps1'))
foreach ($f in $toParse) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Ok "AST parse: $(Split-Path $f -Leaf)" (@($errs).Count -eq 0) ("errors=" + (@($errs) -join '; '))
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    Ok "ASCII-only: $(Split-Path $f -Leaf)" ($nonAscii -eq 0) ("non-ascii bytes=$nonAscii")
}

# 3. fixtures present (5)
Ok "fixture: clean_routed present" (Test-Path $fClean)
Ok "fixture: defect_mis_route present" (Test-Path $fMisRoute)
Ok "fixture: defect_dropped_candidate present" (Test-Path $fDropped)
Ok "fixture: defect_wrong_record present" (Test-Path $fWrong)
Ok "fixture: quirk_flat present" (Test-Path $fFlat)

# 4. StrictMode-trap helpers
Ok "ConvertTo-Array null -> 0" (@(ConvertTo-Array $null).Count -eq 0)
Ok "ConvertTo-Array string -> 1 (not chars)" (@(ConvertTo-Array 'abc').Count -eq 1)

# 5. READER ADAPTER + cross-widget contract test
$info = Get-LrapAdapterInfo
Ok "adapter: version pinned + >= 9 pinned readers" ($info.adapter_version -eq '1.0.0' -and @($info.pinned_readers).Count -ge 9)
$contract = Test-LrapAdapterContract -SamplePacketPath $fClean
Ok "adapter: cross-widget contract holds (no 06/07 shape drift)" ($contract.ok) ("drift=" + (@($contract.drift) -join '; '))
Ok "adapter: recompute/counterfactual entrypoints EXCLUDED from surface" ($contract.excluded_ok -and @($contract.excluded_leaks).Count -eq 0)
$adapterExports = @(Get-Command -Module LrapReaderAdapter | ForEach-Object { [string]$_.Name })
Ok "adapter: surface carries no *Counterfactual*/*CompileWorker*/*PacketDiff*" (@($adapterExports | Where-Object { $_ -match 'Counterfactual|CompileWorker|PacketDiff' }).Count -eq 0)
$rd = Read-LrapPacket -Path $fClean
Ok "adapter: Read-LrapPacket loads a 0.2 packet (cpkt id, compiler 0.8/0.9)" ($rd.ok -and $rd.schema -eq 'lifeorch.context_packet/0.2' -and $rd.packet_id -match '^cpkt_' -and $rd.compiler_version -match '^0\.[89]\.')

# 6. HONESTY MAP -- every cell matches the fixed classification (s3a); no cell is decided at render time
$expectMap = @{
    1 = @{ intent = 'AUTH'; input = 'P2'; output = 'DATA'; reconcile = 'P2' }
    2 = @{ intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
    3 = @{ intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
    4 = @{ intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
    5 = @{ intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
    6 = @{ intent = 'AUTH'; input = 'DATA'; output = 'DATA'; reconcile = 'VERDICT' }
}
$mapOk = $true
foreach ($n in 1..6) { foreach ($lane in 'intent', 'input', 'output', 'reconcile') { if ((Get-LrapHonestyCell -StepNo $n -Lane $lane) -ne $expectMap[$n][$lane]) { $mapOk = $false } } }
Ok "honesty map: all 24 cells match the fixed s3a classification" $mapOk

# every P2 cell renders a VISIBLE lane (never blank, never a computed stand-in)
$mc = Get-LrapModel -PacketPath $fClean
$step1 = @($mc.steps | Where-Object { $_.step_no -eq 1 })[0]
$p2InputVisible = ($step1.input.class -eq 'P2' -and @($step1.input.lines).Count -ge 1 -and ((@($step1.input.lines) -join ' ') -match 'not a mandated artifact|not emitted|follow-on'))
$p2ReconVisible = ($step1.reconcile.lane_class -eq 'P2' -and $step1.reconcile.verdict -eq 'not_emitted' -and @($step1.reconcile.descend_prose).Count -ge 1)
$step2 = @($mc.steps | Where-Object { $_.step_no -eq 2 })[0]
$p2RecallVisible = (@($step2.reconcile.p2_notes) -join ' ') -match 'RECALL GAP'
Ok "honesty map: step-1 INPUT renders a VISIBLE P2 lane (never blank)" $p2InputVisible
Ok "honesty map: step-1 RECONCILE renders a VISIBLE P2 lane (not_emitted)" $p2ReconVisible
Ok "honesty map: step-2 RECONCILE surfaces the recall-gap P2 note" $p2RecallVisible
Ok "honesty map: P2 backlog is a build output (>= 3 trace-emission + forbidden-judgment gaps)" (@(Get-LrapP2Backlog).Count -ge 5 -and @(Get-LrapP2Backlog | Where-Object { $_.kind -eq 'forbidden_judgment' }).Count -ge 1)

# 7. RECONCILE is VERDICT-BACKED ONLY (no smuggled judgment) + the math is real
$stepsClean = $mc.steps
$verdictSteps = @($stepsClean | Where-Object { $_.reconcile.lane_class -eq 'VERDICT' })
$allHaveIdentities = $true
foreach ($st in $verdictSteps) {
    if ($st.reconcile.verdict -in @('consistent', 'inconsistent')) {
        foreach ($idn in @($st.reconcile.identities)) {
            if (-not ((Test-HasProp $idn 'held') -and (Test-HasProp $idn 'name'))) { $allHaveIdentities = $false }
        }
        if (@($st.reconcile.identities).Count -eq 0) { $allHaveIdentities = $false }
    }
}
Ok "reconcile: every VERDICT lane is backed by named substrate identities (held booleans)" $allHaveIdentities
# forbidden semantic judgments are LOGGED as P2, never turned into a verdict
$forbidden = @(Get-LrapP2Backlog | Where-Object { $_.kind -eq 'forbidden_judgment' })
Ok "reconcile: forbidden semantic judgments (omit-validity / successor / classification) are logged P2" (@($forbidden).Count -ge 3)
# the identity math is REAL: corrupt a router count -> step 3 flips to inconsistent
$badPkt = $rd.packet | ConvertTo-Json -Depth 90 | ConvertFrom-Json -Depth 90
$badPkt.evaluation_hooks.routing_stage_trace[0].candidates_out = 99
$badRouter = Get-LrapRouterBracket -Packet $badPkt
$badRecon = Get-LrapStepReconcile -StepNo 3 -Packet $badPkt -RouterBracket $badRouter -SelectionBracket (Get-LrapSelectionBracket -Packet $badPkt)
Ok "reconcile: a corrupted router count is CAUGHT (step 3 -> inconsistent)" ($badRecon.verdict -eq 'inconsistent')

# 8. FIVE-FIXTURE machine classification (the phenomenological fold smoke) -- FP/FN scored separately
$expect = [ordered]@{ }
$expect[$fClean] = 0; $expect[$fMisRoute] = 3; $expect[$fDropped] = 4; $expect[$fWrong] = 6; $expect[$fFlat] = 0
$fpCount = 0; $fnCount = 0
foreach ($path in $expect.Keys) {
    $mm = Get-LrapModel -PacketPath $path
    $got = [int]$mm.overall.inconsistent_step
    $exp = [int]$expect[$path]
    $name = Split-Path $path -Leaf
    Ok "classify: $name -> $(if($exp -eq 0){'CONSISTENT'}else{'inconsistent@'+$exp})" ($got -eq $exp) ("got inconsistent_step=$got")
    if ($exp -eq 0 -and $got -ne 0) { $fpCount++ }
    if ($exp -ne 0 -and $got -ne $exp) { $fnCount++ }
}
Ok "classify: ZERO false positives (clean + quirk not flagged)" ($fpCount -eq 0) ("fp=$fpCount")
Ok "classify: ZERO false negatives (every defect caught at its step)" ($fnCount -eq 0) ("fn=$fnCount")

# 9. DESCEND is plain-language (names the offender) + NOT a raw pane; raw pane reachable separately
$mWrong = Get-LrapModel -PacketPath $fWrong
$whyWrong = (@(Get-LrapStepDescend -Model $mWrong -StepNo 6) -join "`n")
Ok "descend: wrong-record why names the offending record + the failed identity" ($whyWrong -match 'occ_d73b3615a58ba5f1ab226020' -and $whyWrong -match 'identity failed')
Ok "descend: wrong-record why is PLAIN LANGUAGE, not the raw expert pane" ($whyWrong -notmatch 'TRUST:' -and $whyWrong -notmatch 'R-1 ROUTER STAGE-TRACE')
$mDrop = Get-LrapModel -PacketPath $fDropped
$whyDrop = (@(Get-LrapStepDescend -Model $mDrop -StepNo 4) -join "`n")
Ok "descend: dropped-candidate why names the orphan + 'no omit_reason'" ($whyDrop -match 'occ_dropped_orphan' -and $whyDrop -match 'omit_reason')
$mMis = Get-LrapModel -PacketPath $fMisRoute
$whyMis = (@(Get-LrapStepDescend -Model $mMis -StepNo 3) -join "`n")
Ok "descend: mis-route why names the broken chain (5 in vs 4 out)" ($whyMis -match 'chain is broken' -and $whyMis -match '5' -and $whyMis -match '4')
# the raw pane IS available on demand (the 06 expert pane, via the adapter) and IS the schema view
$rawPane = Get-LrapRawTraceForStep -Packet $mWrong.packet -StepNo 6
Ok "descend: the raw 06 expert pane is reachable ONLY on demand (and carries the raw TRUST banners)" ((@($rawPane.lines) -join "`n") -match 'TRUST')

# 10. INTENT catalog + its own review (s3b)
$review = Get-LrapIntentCatalogReview
Ok "intent: catalog has 6 blocks, each cites a contract clause + version" ($review.block_count -eq 6 -and $review.all_cited)
Ok "intent: review names a reviewer" (-not [string]::IsNullOrWhiteSpace([string]$review.reviewer))

# 11. byte-identical re-render (double-run)
function Render-Model($m) {
    $acc = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Format-LrapHeader -Model $m).header_lines) { [void]$acc.Add($l) }
    foreach ($s in $m.steps) {
        [void]$acc.Add("S$($s.step_no) $($s.step_key) I[$($s.intent.class)] $($s.intent.text)")
        foreach ($l in $s.input.lines) { [void]$acc.Add("  in[$($s.input.class)] $l") }
        foreach ($l in $s.output.lines) { [void]$acc.Add("  out[$($s.output.class)] $l") }
        [void]$acc.Add("  recon[$($s.reconcile.lane_class)] $($s.reconcile.verdict) $($s.reconcile.marker)")
        foreach ($l in $s.reconcile.descend_prose) { [void]$acc.Add("    why $l") }
    }
    return ($acc.ToArray() -join "`n")
}
$r1 = Render-Model (Get-LrapModel -PacketPath $fClean)
$r2 = Render-Model (Get-LrapModel -PacketPath $fClean)
Ok "render: byte-identical on unchanged input (double-run)" ($r1 -ceq $r2)

# 12. READ-ONLY + SANITIZATION
$sigBefore = Get-TreeSig $fx
[void](Get-LrapModel -PacketPath $fClean); [void](Get-LrapModel -PacketPath $fWrong)
$sigAfter = Get-TreeSig $fx
Ok "readonly: fixtures tree byte-identical after a full build + render" ($sigBefore -eq $sigAfter)
$rtDir = New-TempDir 'lrap-rt'
try { [void](Assert-UnderRuntime -Target (Join-Path ([System.IO.Path]::GetTempPath()) 'lrap-escape.json') -RuntimeDir $rtDir); Ok "readonly: write-guard refuses outside-runtime" $false 'no throw' }
catch { Ok "readonly: write-guard refuses outside-runtime" $true }
Ok "readonly: write-guard permits a path under runtime" ((Assert-UnderRuntime -Target (Join-Path $rtDir 'ok.json') -RuntimeDir $rtDir) -like (Join-Path $rtDir '*'))
$san = $mc.sanitize
Ok "sanitize: routed router-trace present + channel-only (i33)" ($san.sanitized -and $san.trace_present -and $san.removed_entry_count -ge 1)
$badTrace = $rd.packet | ConvertTo-Json -Depth 90 | ConvertFrom-Json -Depth 90
$badTrace.evaluation_hooks.routing_stage_trace[1].removed[0] | Add-Member -NotePropertyName namespace -NotePropertyValue 'nsb' -Force
$sanBad = Test-LrapTraceSanitized -Packet $badTrace
Ok "sanitize: an injected cross-ns key is FLAGGED (fail-closed)" (-not $sanBad.sanitized -and @($sanBad.violations).Count -ge 1)

# 13. graceful degradation
$em = Get-LrapModel -PacketPath (Join-Path $fx 'nope.json')
Ok "graceful: missing packet -> ok=false, well-formed (P2 backlog + intent review still present)" ((-not $em.ok) -and @($em.p2_backlog).Count -ge 1 -and $null -ne $em.intent_review)

# 14. POSER (D-0126) -- the interpretability "?": elements, bundle, prompt, protocol, worker (mock gateway, no GPU)
Import-Module (Join-Path $widgetRoot 'LrapPoser.psm1') -Force
foreach ($fn in 'Get-LrapPoserElements', 'Get-LrapPoserBundle', 'Get-LrapPoserPrompt', 'Get-LrapPoserSystemPrompt',
    'New-LrapPoserRequest', 'Read-LrapPoserRequest', 'Write-LrapPoserAnswer', 'Read-LrapPoserAnswer', 'Get-LrapPoserInfo') {
    Ok "poser: function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}
$pm = Get-LrapModel -PacketPath $fDropped
$els = @(Get-LrapPoserElements -Model $pm)
Ok "poser: elements = header + 6 steps + 24 lanes = 31" ($els.Count -eq 31 -and $els[0].element_id -eq 'header' -and @($els | Where-Object { $_.kind -eq 'lane' }).Count -eq 24)
# every element yields a well-formed, non-empty bundle AND building writes nothing
$sigPB = Get-TreeSig $fx
$bundleAllOk = $true
foreach ($e in $els) { $b = Get-LrapPoserBundle -Model $pm -ElementId $e.element_id; if (-not $b.ok -or [string]::IsNullOrWhiteSpace([string]$b.context_text)) { $bundleAllOk = $false } }
Ok "poser: all 31 elements bundle to a non-empty context block" $bundleAllOk
Ok "poser: bundle building writes NOTHING to the fixtures tree (read-only)" ((Get-TreeSig $fx) -eq $sigPB)
# the dropped-candidate reconcile bundle NAMES the offender + carries intent+actual+reconcile together (possession); never asserts correctness
$bd = Get-LrapPoserBundle -Model $pm -ElementId 'step:4:reconcile'
Ok "poser: step-4 bundle names the offending unexplained drop + omit_reason" ($bd.context_text -match 'occ_dropped_orphan' -and $bd.context_text -match 'omit_reason')
Ok "poser: bundle carries INTENT + ACTUAL input/output + RECONCILE together (D-0125 possession)" ($bd.context_text -match 'SUPPOSED TO DO' -and $bd.context_text -match 'ACTUAL INPUT' -and $bd.context_text -match 'ACTUAL OUTPUT' -and $bd.context_text -match 'RECONCILE')
Ok "poser: bundle never asserts correctness (green != correct reminder present)" ($bd.context_text -match 'never a claim the run is correct' -or $bd.context_text -match 'NOT a judgment of correctness')
# graceful: header bundles even on a failed load; an unknown element id -> ok=false (no throw)
$bh = Get-LrapPoserBundle -Model (Get-LrapModel -PacketPath (Join-Path $fx 'nope.json')) -ElementId 'header'
Ok "poser: header bundles even when the model failed to load" ($bh.ok -and $bh.context_text -match 'FAILED to load')
$bu = Get-LrapPoserBundle -Model $pm -ElementId 'step:9:bogus'
Ok "poser: an unknown element id -> ok=false, well-formed (no throw)" (-not $bu.ok)
# the prompt: system guardrail forbids judging correctness; user turn carries the context + question
$pr = Get-LrapPoserPrompt -Bundle $bd -Question 'why was that record dropped?'
Ok "poser: system prompt forbids judging whether the run is CORRECT (F1/P9 line)" ($pr.system -match 'judge whether the run was correct')
Ok "poser: prompt user turn carries the context block + the operator question" (([string](@($pr.messages)[-1].content)) -match 'occ_dropped_orphan' -and ([string](@($pr.messages)[-1].content)) -match 'why was that record dropped')
# the request/answer protocol is RUNTIME-GUARDED
$rt = New-TempDir 'lrap-poser-rt'
try { [void](Write-LrapPoserAnswer -RuntimeDir $rt -RequestId (Join-Path (Join-Path '..' '..') 'escape') -Ok:$true -Text 'x'); Ok "poser: answer write-guard refuses escaping runtime" $false 'no throw' }
catch { Ok "poser: answer write-guard refuses escaping runtime" $true }
$reqInfo = New-LrapPoserRequest -RuntimeDir $rt -Bundle $bd -Question 'explain' -RequestId 'testq1'
Ok "poser: request written under runtime\poser (guarded)" ((Test-Path $reqInfo.request_path) -and $reqInfo.request_path -like (Join-Path $rt '*'))
# the WORKER end-to-end against the MOCK gateway (no GPU): ok=true with text
$worker = Join-Path $widgetRoot 'Invoke-LrapPoserQuery.ps1'
$mockGw = Join-Path $here 'mock-poser-gateway.ps1'
& $PwshPath -NoProfile -File $worker -RequestPath $reqInfo.request_path -GatewayPath $mockGw -PwshPath $PwshPath | Out-Null
$ans = Read-LrapPoserAnswer -AnswerPath $reqInfo.answer_path
Ok "poser: worker (mock gateway) writes ok=true answer with the completion" ($null -ne $ans -and $ans.ok -and ([string]$ans.text) -match 'explanation of the instrument')
# fail-silent: empty model output -> ok=false (no hang)
$reqE = New-LrapPoserRequest -RuntimeDir $rt -Bundle $bd -Question 'MOCK_EMPTY please' -RequestId 'testq2'
& $PwshPath -NoProfile -File $worker -RequestPath $reqE.request_path -GatewayPath $mockGw -PwshPath $PwshPath | Out-Null
$ansE = Read-LrapPoserAnswer -AnswerPath $reqE.answer_path
Ok "poser: empty model output -> fail-silent ok=false answer (no hang)" ($null -ne $ansE -and -not $ansE.ok -and ([string]$ansE.error) -match 'no content')
# fail-silent: gateway crash (no artifact) -> ok=false
$reqF = New-LrapPoserRequest -RuntimeDir $rt -Bundle $bd -Question 'MOCK_FAIL now' -RequestId 'testq3'
& $PwshPath -NoProfile -File $worker -RequestPath $reqF.request_path -GatewayPath $mockGw -PwshPath $PwshPath | Out-Null
$ansF = Read-LrapPoserAnswer -AnswerPath $reqF.answer_path
Ok "poser: a gateway crash (no artifact) -> fail-silent ok=false answer" ($null -ne $ansF -and -not $ansF.ok)
Ok "poser: the whole poser path left the fixtures tree byte-identical (read-only)" ((Get-TreeSig $fx) -eq $sigPB)

# ---------- LIVE (Windows) ----------
if ($Live) {
    if (-not $IsWindows) {
        Skip 'live: WinForms self-test' 'not Windows'; Skip 'live: launch.bat' 'not Windows'; Skip 'live: real #40 render' 'not Windows'
    }
    else {
        $lb = Join-Path $widgetRoot 'launch.bat'
        Ok "live: launch.bat exists" (Test-Path $lb)
        if (Test-Path $lb) {
            $lbTxt = Get-Content -LiteralPath $lb -Raw
            Ok "live: launch.bat runs Show-LiveRunAuditPathway.ps1 under -STA" ($lbTxt -match 'Show-LiveRunAuditPathway\.ps1' -and $lbTxt -match '-STA')
        }
        $show = Join-Path $widgetRoot 'Show-LiveRunAuditPathway.ps1'
        $out = & $PwshPath -NoProfile -STA -File $show -SelfTest 2>&1 | Out-String
        Write-Host "  --- self-test child output ---"
        foreach ($ln in ($out -split "`r?`n")) { if ($ln.Trim()) { Write-Host "    $ln" } }
        foreach ($marker in 'SELFTEST_FORM_OK', 'SELFTEST_MODEL_OK', 'SELFTEST_PANES_OK', 'SELFTEST_RECONCILE_OK',
            'SELFTEST_DESCEND_OK', 'SELFTEST_SANITIZE_OK', 'SELFTEST_REFRESH_OK', 'SELFTEST_INTERACT_OK', 'SELFTEST_READONLY_OK', 'SELFTEST_POSER_OK', 'SELFTEST_LAYOUT_OK') {
            Ok "live: self-test emitted $marker" ($out -match $marker)
        }
        Ok "live: self-test has no FAIL marker" (-not ($out -match 'SELFTEST_\w+_FAIL'))

        # render a real on-box #40 artifact if present (newest that carries a packet)
        $paths = Resolve-LrapPaths -WidgetRoot $widgetRoot -RepoRoot $RepoRoot
        $realPkt = $null
        if (Test-Path -LiteralPath $paths.ArtifactsDir -PathType Container) {
            foreach ($cand in @(Get-ChildItem -LiteralPath $paths.ArtifactsDir -Recurse -File -Filter 'cc_meta.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
                $rm = Get-LrapModel -PacketPath $cand.FullName
                if ($rm.ok) { $realPkt = $cand.FullName; break }
            }
        }
        if ($null -ne $realPkt) {
            $rm = Get-LrapModel -PacketPath $realPkt
            Ok "live: renders a REAL on-box #40 artifact (ok, 6 steps, a verdict)" ($rm.ok -and @($rm.steps).Count -eq 6 -and $null -ne $rm.overall) ("src=" + $realPkt)
        }
        else { Skip 'live: real #40 render' 'no #40 artifact carrying a packet on this box' }
    }
}
else {
    Skip 'live: WinForms self-test' 'cloud gate (use -Live on Windows)'
    Skip 'live: launch.bat shape' 'cloud gate'
    Skip 'live: real #40 render' 'cloud gate'
}

foreach ($t in $script:tempRoots) { try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue } catch { } }

Write-Host ""
Write-Host "=== RESULT: pass=$($script:pass) fail=$($script:fail) skip=$($script:skip) ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
