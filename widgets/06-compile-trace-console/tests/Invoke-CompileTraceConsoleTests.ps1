<#
    Invoke-CompileTraceConsoleTests.ps1 - dual-mode test harness for the Compile Trace Console (Widget 06).

    Cloud pre-ship gate (Linux, no -Live): AST-parse + ASCII-guard every shipped script; drive the REAL core
    (CompileTraceConsole.psm1) over the committed REAL fixtures (a #40 0.8.0 routed packet, a flat packet, a
    counterfactual base/variant pair, the i36 rehearsal report, a #37 eval report with hybrid attribution, and
    a real D-0077 fold-i37 smoke log) --
      - the packet readers in all three carrier shapes (raw packet / skill.result envelope / worker cc_meta);
      - the five pane builders (1 timeline, 2 model view + four trust banners, 3 retrieval+selection + the R-1
        router trace, 4 rule/exception stack, 6 token/state ledger) -- each asserted for real content;
      - the i33 diagnostic-array SANITIZATION check (the router trace is channel-only);
      - byte-identical re-render on unchanged inputs;
      - the pure differ Get-PacketDiff over the committed base/variant (budget delta) + New-CounterfactualCase
        (one varied input + the write-guard);
      - the compile-layer counterfactual RUNNER end-to-end via the REAL #40 worker WHEN resolvable (env
        LIFEORCH_CTC_REPO in cloud, or the real repo on the box): a budget delta AND the vector-channel-mask
        reconciliation (ZERO packet delta -- reconciles with #37 hybrid attribution: vector rescued 0);
      - the read-only guarantees (the fixtures tree is byte-identical after a full render + a counterfactual;
        every counterfactual write lands ONLY under a runtime dir) and graceful degradation.

    Live (Windows, via the executor, -Live): the same PLUS launch.bat shape, the WinForms -SelfTest in an STA
    child (asserting SELFTEST_FORM_OK / MODEL_OK / PANES_OK / SANITIZE_OK / COMPANION_OK / COUNTERFACTUAL_OK /
    REFRESH_OK / READONLY_OK / LAYOUT_OK), and -- if the production #40 is present -- a render of the newest
    REAL runtime/artifacts packet with no throw.
#>
[CmdletBinding()]
param([switch]$Live, [string]$PwshPath, [string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$widgetRoot = Split-Path $here -Parent
Import-Module (Join-Path $widgetRoot 'CompileTraceConsole.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}

$fx = Join-Path $here 'fixtures'
$fRouted = Join-Path $fx 'routed_packet.json'
$fFlat = Join-Path $fx 'flat_packet.json'
$fBase = Join-Path $fx 'cf_base_packet.json'
$fVarBudget = Join-Path $fx 'cf_variant_budget_packet.json'
$fEval = Join-Path $fx 'eval_report.json'
$fReh = Join-Path $fx 'rehearsal_report.json'
$fFold = Join-Path $fx 'fold_smoke.log'
$fCase = Join-Path $fx 'base_case.json'

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

Write-Host "=== Compile Trace Console tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist
foreach ($fn in 'Get-Prop', 'ConvertTo-Array', 'Get-PropNames', 'Read-JsonFileSafe', 'Read-TextFileSafe',
    'Resolve-CompileTracePaths', 'Get-PacketFromObject', 'Read-ContextPacket', 'Read-EvalReport', 'Read-FoldSmoke',
    'Get-EffectiveNamespaces', 'Test-TraceSanitized', 'Get-Pane1Timeline', 'Get-Pane2ModelView',
    'Get-Pane3RetrievalTrace', 'Get-Pane4RuleStack', 'Get-Pane6TokenLedger', 'Get-CompileTraceModel',
    'Format-CompileTraceHeader', 'Format-CompanionRows', 'Assert-UnderRuntime', 'Get-CounterfactualVariations',
    'New-CounterfactualCase', 'Get-PacketDiff', 'Invoke-CompileCounterfactual') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse + 2b. ASCII-only guard on every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'CompileTraceConsole.psm1'),
    (Join-Path $widgetRoot 'Show-CompileTraceConsole.ps1'),
    (Join-Path $here 'Invoke-CompileTraceConsoleTests.ps1'))
foreach ($f in $toParse) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Ok "AST parse: $(Split-Path $f -Leaf)" (@($errs).Count -eq 0) ("errors=" + (@($errs) -join '; '))
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    Ok "ASCII-only: $(Split-Path $f -Leaf)" ($nonAscii -eq 0) ("non-ascii bytes=$nonAscii")
}

# 3. fixtures present
Ok "fixture: routed packet present" (Test-Path $fRouted)
Ok "fixture: flat packet present" (Test-Path $fFlat)
Ok "fixture: counterfactual base/variant present" ((Test-Path $fBase) -and (Test-Path $fVarBudget))
Ok "fixture: eval + rehearsal + fold present" ((Test-Path $fEval) -and (Test-Path $fReh) -and (Test-Path $fFold))
Ok "fixture: mock base case present" (Test-Path $fCase)

# 4. StrictMode-trap helpers
Ok "ConvertTo-Array null -> 0" (@(ConvertTo-Array $null).Count -eq 0)
Ok "ConvertTo-Array string -> 1 (not chars)" (@(ConvertTo-Array 'abc').Count -eq 1)
Ok "Get-PropNames on pscustomobject" ((@(Get-PropNames ([pscustomobject]@{ a = 1; b = 2 })) | Sort-Object) -join ',' -eq 'a,b')

# 5. packet readers -- three carrier shapes normalize to the same inner packet
$rdRaw = Read-ContextPacket -Path $fRouted
Ok "reader: raw packet ok + schema 0.2 + packet_id + compiler 0.8.x/0.9.x" ($rdRaw.ok -and $rdRaw.schema -eq 'lifeorch.context_packet/0.2' -and $rdRaw.packet_id -match '^cpkt_' -and $rdRaw.compiler_version -match '^0\.[89]\.')
$env1 = New-TempDir 'ctc-env'
# skill.result envelope shape: { result: { result: { packet: <p> } } }
$innerP = $rdRaw.packet
$envObj = [pscustomobject]@{ schema = 'lifeorch.skill.result/0.1'; result = [pscustomobject]@{ result = [pscustomobject]@{ packet = $innerP } } }
$envPath = Join-Path $env1 'envelope.json'; [System.IO.File]::WriteAllText($envPath, ($envObj | ConvertTo-Json -Depth 90), [System.Text.UTF8Encoding]::new($false))
$rdEnv = Read-ContextPacket -Path $envPath
Ok "reader: skill.result envelope -> same packet_id" ($rdEnv.ok -and $rdEnv.packet_id -eq $rdRaw.packet_id)
# worker cc_meta shape: { result: { packet: <p> } }
$metaObj = [pscustomobject]@{ ok = $true; result = [pscustomobject]@{ packet = $innerP } }
$metaPath = Join-Path $env1 'cc_meta.json'; [System.IO.File]::WriteAllText($metaPath, ($metaObj | ConvertTo-Json -Depth 90), [System.Text.UTF8Encoding]::new($false))
$rdMeta = Read-ContextPacket -Path $metaPath
Ok "reader: worker cc_meta -> same packet_id" ($rdMeta.ok -and $rdMeta.packet_id -eq $rdRaw.packet_id)
Ok "reader: missing file -> ok=false, no throw" (-not (Read-ContextPacket -Path (Join-Path $env1 'nope.json')).ok)

# 6. companion readers
$re = Read-EvalReport -Path $fReh
Ok "reader: rehearsal report detected (kind=rehearsal, tier1_criteria)" ($re.ok -and $re.kind -eq 'rehearsal' -and (Test-HasProp $re.report 'tier1_criteria'))
$ee = Read-EvalReport -Path $fEval
Ok "reader: eval report detected (hybrid_attribution present)" ($ee.ok -and (Test-HasProp $ee.report 'hybrid_attribution'))
$fld = Read-FoldSmoke -Path $fFold
Ok "reader: fold smoke parsed 13/13 PASSED" ($fld.ok -and $fld.passed -eq 13 -and $fld.failed -eq 0 -and $fld.verdict -eq 'passed')

# 7. the full model over the routed packet
$m = Get-CompileTraceModel -PacketPath $fRouted -EvalPath $fEval -RehearsalPath $fReh -FoldPath $fFold
Ok "model: ok, no build flags" ($m.ok -and @($m.flags).Count -eq 0) ("flags=" + (@($m.flags) -join '; '))
Ok "model: non_execution=true" ($m.non_execution -eq $true)
Ok "model: disposition answerable" ($m.disposition -eq 'answerable')
Ok "model: 3 router stages counted" ($m.counts.trace_stages -eq 3)
Ok "model: 6 excerpts, 6 ranked" ($m.counts.excerpts -eq 6 -and $m.counts.ranked -eq 6)

# 8. pane content
$p1 = (@($m.panes.timeline.lines) -join "`n")
Ok "pane1: timeline has normalize/retrieve/route/select/budget/packet" ($p1 -match 'normalize' -and $p1 -match 'route:classification' -and $p1 -match 'select:packet' -and $p1 -match 'budget' -and $p1 -match 'packet')
$p2 = (@($m.panes.modelview.lines) -join "`n")
Ok "pane2: four regions with TRUST banners in order" ($p2 -match 'control_plane.*AUTHORITATIVE' -and $p2 -match 'task_input.*REQUEST' -and $p2 -match 'working_memory.*CONTINUITY' -and $p2 -match 'evidence.*EVIDENCE')
Ok "pane2: non_execution frame present" ($p2 -match 'NON_EXECUTION = yes')
$p3 = (@($m.panes.retrieval.lines) -join "`n")
Ok "pane3: R-1 router stage-trace rendered (classification/routing/channel_selection)" ($p3 -match 'R-1 ROUTER STAGE-TRACE' -and $p3 -match 'classification' -and $p3 -match 'routing' -and $p3 -match 'channel_selection')
Ok "pane3: selpol ranked + reason_codes + selection policy" ($p3 -match 'SELPOL RANKED' -and $p3 -match 'selpol_rrf_v1' -and $p3 -match 'authority_boost')
Ok "pane3: retrieval lineage + vector channel + V3 completeness section" ($p3 -match 'RETRIEVAL PLAN' -and $p3 -match 'vector_channel' -and $p3 -match 'V3 RETRIEVAL COMPLETENESS')
$p4 = (@($m.panes.rules.lines) -join "`n")
Ok "pane4: temporal_intent + namespace-closure + disposition rules" ($p4 -match 'RULE temporal_intent' -and $p4 -match 'RULE namespace_closure' -and $p4 -match 'RULE disposition')
$p6 = (@($m.panes.ledger.lines) -join "`n")
Ok "pane6: budget + transport + consumer_profile + state ledger + omission" ($p6 -match 'BUDGET LEDGER' -and $p6 -match 'TRANSPORT ACCOUNTING' -and $p6 -match 'CONSUMER PROFILE' -and $p6 -match 'STATE LEDGER' -and $p6 -match 'OMISSION MANIFEST')

# 9. sanitization -- the router trace is channel-only (i33 diagnostic-array closure)
$san = Test-TraceSanitized -Packet $m.packet
Ok "sanitize: routed trace present + sanitized (no forbidden identifying keys)" ($san.sanitized -and $san.trace_present -and $san.removed_entry_count -ge 1)
# inject a forbidden key into a copy -> the check must FLAG it
$badP = (Read-ContextPacket -Path $fRouted).packet | ConvertTo-Json -Depth 90 | ConvertFrom-Json -Depth 90
$badP.evaluation_hooks.routing_stage_trace[1].removed[0] | Add-Member -NotePropertyName namespace -NotePropertyValue 'nsb' -Force
$sanBad = Test-TraceSanitized -Packet $badP
Ok "sanitize: an injected cross-ns key is FLAGGED (fail-closed)" (-not $sanBad.sanitized -and @($sanBad.violations).Count -ge 1)

# 10. flat packet -- no router trace; pane3 says flat; sanitize trace_present=false
$mf = Get-CompileTraceModel -PacketPath $fFlat
Ok "flat: ok, 0 router stages" ($mf.ok -and $mf.counts.trace_stages -eq 0)
Ok "flat: pane3 marks 'flat compile' (router additive)" ((@($mf.panes.retrieval.lines) -join "`n") -match 'flat compile')

# 11. byte-identical re-render
$m2 = Get-CompileTraceModel -PacketPath $fRouted
$sig1 = ((@($m.panes.timeline.lines) + @($m.panes.modelview.lines) + @($m.panes.retrieval.lines) + @($m.panes.rules.lines) + @($m.panes.ledger.lines)) -join "`n")
$sig2 = ((@($m2.panes.timeline.lines) + @($m2.panes.modelview.lines) + @($m2.panes.retrieval.lines) + @($m2.panes.rules.lines) + @($m2.panes.ledger.lines)) -join "`n")
Ok "render: byte-identical on unchanged input" ($sig1 -ceq $sig2)
$hdr = Format-CompileTraceHeader -Model $m
Ok "header: names packet_id + schema + disposition + sanitized" ((@($hdr.header_lines) -join ' ') -match 'cpkt_' -and (@($hdr.header_lines) -join ' ') -match 'lifeorch.context_packet/0.2' -and (@($hdr.header_lines) -join ' ') -match 'sanitized')

# 12. companion rendering
$comp = Format-CompanionRows -Model $m
$compText = (@($comp.lines) -join "`n")
Ok "companion: rehearsal criteria + eval hybrid + fold smoke rendered" ($compText -match 'REHEARSAL REPORT' -and $compText -match 'hybrid_applicability' -and $compText -match 'FOLD SMOKE')
Ok "companion: notes vector rescued 0 -> zero-delta expectation" ($compText -match 'ZERO packet delta')

# 13. pure differ over committed base/variant
$bp = (Read-ContextPacket -Path $fBase).packet
$vp = (Read-ContextPacket -Path $fVarBudget).packet
$d = Get-PacketDiff -BasePacket $bp -VariantPacket $vp
Ok "differ: budget variant changes packet_id" ($d.packet_id_changed)
Ok "differ: budget variant drops excerpts (delta < 0)" ($d.excerpt_count_delta -lt 0)
Ok "differ: budget variant adds omissions + removes selected" (@($d.omission_added).Count -ge 1 -and @($d.selected_removed).Count -ge 1)
Ok "differ: identity budget delta reported" ((@($d.identity_deltas) -join "`n") -match 'budget:')
$dv = Get-PacketDiff -BasePacket $bp -VariantPacket $bp
Ok "differ: identical packets -> zero delta (packet_id unchanged)" (-not $dv.packet_id_changed -and $dv.excerpt_count_delta -eq 0 -and @($dv.selected_removed).Count -eq 0)

# 14. New-CounterfactualCase: one varied input + the write-guard
$cfDir = New-TempDir 'ctc-cf'
$nc = New-CounterfactualCase -BaseCase $fCase -Variation budget -Value 77 -RuntimeDir $cfDir
Ok "cfcase: budget case written under the runtime dir" ((Test-Path -LiteralPath $nc.path) -and ([System.IO.Path]::GetFullPath($nc.path)).StartsWith([System.IO.Path]::GetFullPath($cfDir)))
$ncObj = Read-JsonFileSafe -Path $nc.path
Ok "cfcase: exactly the ONE varied input applied (token_budget=77)" ([int]$ncObj.task.config.token_budget -eq 77)
$ncMask = New-CounterfactualCase -BaseCase $fCase -Variation channel_mask -Value vector -RuntimeDir $cfDir
Ok "cfcase: channel_mask vector removes ZERO hits (lexical-only corpus)" ($ncMask.description -match 'removed=0')
try { [void](Assert-UnderRuntime -Target (Join-Path ([System.IO.Path]::GetTempPath()) 'ctc-escape.json') -RuntimeDir $cfDir); Ok "cfcase: write-guard refuses outside-runtime" $false 'no throw' }
catch { Ok "cfcase: write-guard refuses outside-runtime" $true }

# 15. the compile-layer counterfactual RUNNER end-to-end via the REAL #40 worker (when resolvable)
$paths = Resolve-CompileTracePaths -WidgetRoot $widgetRoot -RepoRoot $RepoRoot
$python = Resolve-Python
$runnerRunnable = ((Test-Path -LiteralPath $paths.CompilerWorker -PathType Leaf) -and ($null -ne $python))
if ($runnerRunnable) {
    $rtDir = New-TempDir 'ctc-runner'
    $rB = Invoke-CompileCounterfactual -BaseCasePath $fCase -Variation budget -Value 90 -RepoRoot $RepoRoot -WidgetRoot $widgetRoot -RuntimeDir $rtDir
    Ok "runner: budget re-compile ok" ($rB.ok) ("err=" + [string]$rB.error)
    Ok "runner: budget delta real (packet_id changed + fewer excerpts)" ($rB.ok -and $rB.diff.packet_id_changed -and $rB.diff.excerpt_count_delta -lt 0)
    $rV = Invoke-CompileCounterfactual -BaseCasePath $fCase -Variation channel_mask -Value vector -RepoRoot $RepoRoot -WidgetRoot $widgetRoot -RuntimeDir $rtDir
    Ok "runner: vector-mask RECONCILES with #37 (zero packet delta -- vector rescued 0)" ($rV.ok -and -not $rV.diff.packet_id_changed -and $rV.diff.excerpt_count_delta -eq 0)
    $rR = Invoke-CompileCounterfactual -BaseCasePath $fCase -Variation route -RepoRoot $RepoRoot -WidgetRoot $widgetRoot -RuntimeDir $rtDir
    Ok "runner: route toggle adds routing_plan_digest to identity" ($rR.ok -and ((@($rR.diff.identity_deltas) -join "`n") -match 'routing_plan_digest'))
    # determinism: re-run budget -> identical variant packet_id
    $rB2 = Invoke-CompileCounterfactual -BaseCasePath $fCase -Variation budget -Value 90 -RepoRoot $RepoRoot -WidgetRoot $widgetRoot -RuntimeDir $rtDir
    Ok "runner: deterministic (same variant packet_id on re-run)" ($rB2.ok -and $rB.diff.variant_packet_id -eq $rB2.diff.variant_packet_id)
    # every runner write landed under the runtime dir
    $escaped = $false
    foreach ($f in @(Get-ChildItem -LiteralPath $rtDir -Recurse -File -ErrorAction SilentlyContinue)) {
        if (-not ([System.IO.Path]::GetFullPath($f.FullName)).StartsWith([System.IO.Path]::GetFullPath($rtDir), [System.StringComparison]::OrdinalIgnoreCase)) { $escaped = $true }
    }
    Ok "runner: all re-compile scratch stayed under the runtime dir" (-not $escaped)
}
else {
    Skip 'runner: budget re-compile' 'no #40 worker / python resolvable (set LIFEORCH_CTC_REPO or -RepoRoot)'
    Skip 'runner: vector-mask reconciliation' 'no compiler'
    Skip 'runner: route toggle' 'no compiler'
    Skip 'runner: determinism' 'no compiler'
    Skip 'runner: scratch under runtime' 'no compiler'
}

# 16. graceful degradation
$em = Get-CompileTraceModel -PacketPath (Join-Path $env1 'nope.json')
Ok "graceful: missing packet -> ok=false + a flag, no throw" ((-not $em.ok) -and @($em.flags).Count -ge 1)
$junk = Join-Path $env1 'junk.json'; [System.IO.File]::WriteAllText($junk, 'not json', [System.Text.UTF8Encoding]::new($false))
Ok "graceful: junk file -> ok=false, no throw" (-not (Read-ContextPacket -Path $junk).ok)

# 17. READ-ONLY: the fixtures tree is byte-identical after a full model build + render + differ
$sigBefore = Get-TreeSig $fx
[void](Get-CompileTraceModel -PacketPath $fRouted -EvalPath $fEval -RehearsalPath $fReh -FoldPath $fFold)
[void](Format-CompileTraceHeader -Model $m)
[void](Get-PacketDiff -BasePacket $bp -VariantPacket $vp)
$sigAfter = Get-TreeSig $fx
Ok "readonly: fixtures tree byte-identical after a full build + render + differ" ($sigBefore -eq $sigAfter)

# ---------- LIVE (Windows) ----------
if ($Live) {
    if (-not $IsWindows) {
        Skip 'live: WinForms self-test' 'not Windows'; Skip 'live: launch.bat' 'not Windows'; Skip 'live: real packet' 'not Windows'
    }
    else {
        $lb = Join-Path $widgetRoot 'launch.bat'
        Ok "live: launch.bat exists" (Test-Path $lb)
        if (Test-Path $lb) {
            $lbTxt = Get-Content -LiteralPath $lb -Raw
            Ok "live: launch.bat runs Show-CompileTraceConsole.ps1 under -STA" ($lbTxt -match 'Show-CompileTraceConsole\.ps1' -and $lbTxt -match '-STA')
        }
        $show = Join-Path $widgetRoot 'Show-CompileTraceConsole.ps1'
        $out = & $PwshPath -NoProfile -STA -File $show -SelfTest 2>&1 | Out-String
        Write-Host "  --- self-test child output ---"
        foreach ($ln in ($out -split "`r?`n")) { if ($ln.Trim()) { Write-Host "    $ln" } }
        foreach ($marker in 'SELFTEST_FORM_OK', 'SELFTEST_MODEL_OK', 'SELFTEST_PANES_OK', 'SELFTEST_SANITIZE_OK',
            'SELFTEST_COMPANION_OK', 'SELFTEST_COUNTERFACTUAL_OK', 'SELFTEST_REFRESH_OK', 'SELFTEST_READONLY_OK', 'SELFTEST_LAYOUT_OK') {
            Ok "live: self-test emitted $marker" ($out -match $marker)
        }
        Ok "live: self-test has no FAIL marker" (-not ($out -match 'SELFTEST_\w+_FAIL'))

        # render the newest REAL #40 runtime/artifacts packet if present
        $realPaths = Resolve-CompileTracePaths -WidgetRoot $widgetRoot -RepoRoot $RepoRoot
        if (Test-Path -LiteralPath $realPaths.ArtifactsDir -PathType Container) {
            # newest cc_meta.json that actually CARRIES a packet (skip `normalize`/`expand` op metas)
            $picked = $null
            foreach ($cand in @(Get-ChildItem -LiteralPath $realPaths.ArtifactsDir -Recurse -File -Filter 'cc_meta.json' -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTimeUtc -Descending)) {
                if ((Read-ContextPacket -Path $cand.FullName).ok) { $picked = $cand.FullName; break }
            }
            if ($picked) {
                $rm = Get-CompileTraceModel -PacketPath $picked
                Ok "live: renders a REAL #40 runtime artifact (ok, has panes)" ($rm.ok -and $null -ne $rm.panes) ("src=" + $picked + " err=" + [string]$rm.error)
            }
            else { Skip 'live: real artifact render' 'no compile cc_meta.json (only normalize/expand) on this box' }
        }
        else { Skip 'live: real artifact render' 'no #40 runtime/artifacts dir' }
    }
}
else {
    Skip 'live: WinForms self-test' 'cloud gate (use -Live on Windows)'
    Skip 'live: launch.bat shape' 'cloud gate'
    Skip 'live: real artifact render' 'cloud gate'
}

foreach ($t in $script:tempRoots) { try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue } catch { } }

Write-Host ""
Write-Host "=== RESULT: pass=$($script:pass) fail=$($script:fail) skip=$($script:skip) ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
