<#
    Invoke-AuditTimelineTournamentTests.ps1 - dual-mode test harness for the Audit Timeline + Tournament
    console (Widget 07).

    Cloud pre-ship gate (Linux, no -Live): AST-parse + ASCII-guard every shipped script; drive the REAL core
    (AuditTimelineTournament.psm1) over committed REAL fixtures (a #40 0.8.0 routed packet with a 3-stage
    routing_stage_trace, a flat packet, the real i38 fan-out wave = plan.json + its 3 reports, a real #39
    episode, a real #42 working-state envelope) --
      - the artifact readers (packet carriers / fan-out plan / report / episode / working-state);
      - the TOURNAMENT: the router bracket reconciles (in - removed == out; chain), the selection bracket
        reconciles (subset + omit-reason), the plan-validation bracket reconciles (workers == accepted +
        deferred + rejected), overall RECONCILED; a flat packet has no router bracket but still reconciles;
      - the cross-context TIMELINE: a REAL wave stitched end-to-end (plan_created + per-report events),
        stitched with episode open/stage/close + the #42 state_version chain + a graceful batons-absent note;
        the dispatched-vs-reported wave reconciliation; a deterministic total order (byte-stable);
      - the i33 SANITIZATION: the router trace is channel-only (+ an injected cross-ns key fails closed); the
        timeline events are allowlisted (+ an injected body/snippet field never leaks into a rendered line);
      - byte-identical re-render on unchanged inputs; the read-only guarantees (fixtures tree byte-identical
        after a full build; the write-guard refuses an outside-runtime target); graceful degradation.

    Live (Windows, via the executor, -Live): the same PLUS launch.bat shape, the WinForms -SelfTest in an STA
    child (SELFTEST_FORM_OK / MODEL_OK / TOURNAMENT_OK / TIMELINE_OK / SANITIZE_OK / REFRESH_OK / READONLY_OK
    / LAYOUT_OK), and -- if the production runtime is present -- a render of a real on-box wave with no throw.
#>
[CmdletBinding()]
param([switch]$Live, [string]$PwshPath, [string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$widgetRoot = Split-Path $here -Parent
Import-Module (Join-Path $widgetRoot 'AuditTimelineTournament.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}

$fx = Join-Path $here 'fixtures'
$fRouted = Join-Path $fx 'routed_packet.json'
$fFlat = Join-Path $fx 'flat_packet.json'
$fPlan = Join-Path $fx (Join-Path 'wave' 'plan.json')
$fRepDir = Join-Path $fx (Join-Path 'wave' 'reports')
$fEpDir = Join-Path $fx 'episodes'
$fWs = Join-Path $fx 'working_state.json'

$reportPaths = @(Get-ChildItem -LiteralPath $fRepDir -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } | Sort-Object)
$episodePaths = @(Get-ChildItem -LiteralPath $fEpDir -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } | Sort-Object)

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
function Build-Model {
    Get-AuditModel -PacketPath $fRouted -PlanPath $fPlan -ReportPaths $reportPaths -EpisodePaths $episodePaths -WorkingStatePaths @($fWs)
}

Write-Host "=== Audit Timeline + Tournament tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist
foreach ($fn in 'Get-Prop', 'ConvertTo-Array', 'Get-PropNames', 'Read-JsonFileSafe', 'Get-SortableTicks',
    'Resolve-AuditPaths', 'Read-ContextPacket', 'Read-FanoutPlan', 'Read-FanoutReport', 'Read-Episode',
    'Read-WorkingState', 'Test-TraceSanitized', 'Test-TimelineSanitized', 'Get-RouterTournament',
    'Get-SelectionTournament', 'Get-PlanValidationTournament', 'Get-TournamentPane', 'Get-StitchedTimeline',
    'Get-AuditModel', 'Format-AuditHeader', 'Assert-UnderRuntime', 'Find-NewestCompleteWave') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse + 2b. ASCII-only guard on every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'AuditTimelineTournament.psm1'),
    (Join-Path $widgetRoot 'Show-AuditTimelineTournament.ps1'),
    (Join-Path $here 'Invoke-AuditTimelineTournamentTests.ps1'))
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
Ok "fixture: wave plan + 3 reports present" ((Test-Path $fPlan) -and $reportPaths.Count -eq 3)
Ok "fixture: episode + working-state present" ($episodePaths.Count -ge 1 -and (Test-Path $fWs))

# 4. StrictMode-trap helpers + tick parse
Ok "ConvertTo-Array null -> 0" (@(ConvertTo-Array $null).Count -eq 0)
Ok "ConvertTo-Array string -> 1 (not chars)" (@(ConvertTo-Array 'abc').Count -eq 1)
Ok "Get-SortableTicks parses UTC iso" ($null -ne (Get-SortableTicks '2026-08-06T00:31:39.4569404Z'))
Ok "Get-SortableTicks null on junk" ($null -eq (Get-SortableTicks 'not-a-date'))
Ok "Get-SortableTicks orders correctly" ((Get-SortableTicks '2026-08-06T02:07:02Z') -gt (Get-SortableTicks '2026-08-06T00:31:39Z'))

# 5. readers
$rdRaw = Read-ContextPacket -Path $fRouted
Ok "reader: routed packet ok + schema 0.2 + cpkt id + compiler 0.8/0.9" ($rdRaw.ok -and $rdRaw.schema -eq 'lifeorch.context_packet/0.2' -and $rdRaw.packet_id -match '^cpkt_' -and $rdRaw.compiler_version -match '^0\.[89]\.')
$pl = Read-FanoutPlan -Path $fPlan
Ok "reader: plan ok + plan_id + 3 workers + dispatch_now" ($pl.ok -and $pl.plan_id -eq 'fo-38-2b1efe73' -and @($pl.workers).Count -eq 3 -and @($pl.dispatch_now).Count -eq 3)
$rep0 = Read-FanoutReport -Path $reportPaths[0]
Ok "reader: report ok + worker_id + state + reported_at_utc" ($rep0.ok -and $rep0.worker_id -and $rep0.state -eq 'done' -and $rep0.reported_at_utc)
$ep0 = Read-Episode -Path $episodePaths[0]
Ok "reader: episode ok + stages + valid_from/to" ($ep0.ok -and @($ep0.stages).Count -ge 1 -and $ep0.valid_from -and $ep0.valid_to)
$ws0 = Read-WorkingState -Path $fWs
Ok "reader: working-state ok + state_version + task_id" ($ws0.ok -and $null -ne $ws0.state_version -and $ws0.task_id)
Ok "reader: missing file -> ok=false, no throw" (-not (Read-ContextPacket -Path (Join-Path $fx 'nope.json')).ok)

# 6. TOURNAMENT -- router bracket
$m = Build-Model
Ok "model: ok" ($m.ok) ("err=" + [string]$m.error)
$router = Get-RouterTournament -Packet $rdRaw.packet
Ok "tournament/router: present + 3 rounds" ($router.present -and @($router.rounds).Count -eq 3)
Ok "tournament/router: RECONCILED (in - removed == out; chain intact)" ($router.reconciled)
$rl = (@($router.lines) -join "`n")
Ok "tournament/router: rounds are classification/routing/channel_selection" ($rl -match 'classification' -and $rl -match 'routing' -and $rl -match 'channel_selection')
Ok "tournament/router: routing round names removed channels + reason codes" ($rl -match 'working_memory' -and $rl -match 'working_memory_reserved_not_hydrated' -and $rl -match 'class_not_descend')
# reconciliation math is real: corrupt a round and expect MISMATCH
$badPkt = (Read-ContextPacket -Path $fRouted).packet | ConvertTo-Json -Depth 90 | ConvertFrom-Json -Depth 90
$badPkt.evaluation_hooks.routing_stage_trace[0].candidates_out = 99
$routerBad = Get-RouterTournament -Packet $badPkt
Ok "tournament/router: a broken count is caught (reconciled=false)" (-not $routerBad.reconciled)

# 6b. selection + plan-validation brackets
$sel = Get-SelectionTournament -Packet $rdRaw.packet
Ok "tournament/selection: present + reconciled (raw->post->packet)" ($sel.present -and $sel.reconciled -and $sel.raw -ge 1)
$pv = Get-PlanValidationTournament -Plan $pl
Ok "tournament/plan-validation: reconciled (workers == accepted + deferred + rejected)" ($pv.present -and $pv.reconciled -and $pv.accepted -eq 3)
$tp = Get-TournamentPane -Packet $rdRaw.packet -Plan $pl
Ok "tournament: overall RECONCILED across all three brackets" ($tp.reconciled)
$tpText = (@($tp.lines) -join "`n")
Ok "tournament: renders A/B/C brackets + PREFLIGHT-future + OVERALL RECONCILED" ($tpText -match 'BRACKET A: ROUTER' -and $tpText -match 'BRACKET B: SELECTION' -and $tpText -match 'BRACKET C: PLAN VALIDATION' -and $tpText -match 'PREFLIGHT' -and $tpText -match 'OVERALL RECONCILED')

# 6c. flat packet -- no router bracket, still reconciles
$mf = Get-AuditModel -PacketPath $fFlat -PlanPath $fPlan -ReportPaths $reportPaths
$routerFlat = Get-RouterTournament -Packet (Read-ContextPacket -Path $fFlat).packet
Ok "tournament/flat: no router bracket, reconciled true" ((-not $routerFlat.present) -and $routerFlat.reconciled)
Ok "tournament/flat: overall model still reconciles" ($mf.tournament.reconciled)

# 7. TIMELINE -- stitch a real wave end-to-end + cross-context
$tl = $m.timeline
Ok "timeline: ok + wave = fo-38" ($tl.ok -and $tl.wave_plan_id -eq 'fo-38-2b1efe73')
Ok "timeline: >= 4 stitched events" ($tl.counts.total_events -ge 4)
$tlText = (@($tl.lines) -join "`n")
Ok "timeline: plan_created + 3 report:done events (wave end-to-end)" ($tlText -match 'plan_created' -and (@([regex]::Matches($tlText, 'report:done')).Count -eq 3))
Ok "timeline: cross-context episode open/stage/close" ($tlText -match 'episode_open' -and $tlText -match 'stage:' -and $tlText -match 'episode_close')
Ok "timeline: working_memory state_version chain event" ($tlText -match 'working_memory:' -and $tlText -match 'state_v')
Ok "timeline: batons rendered gracefully when absent" ($tlText -match 'BATONS: none present')
Ok "timeline: holds NO lease -> zero lease-window violations" ($tl.lease.holds -eq $false -and $tl.lease.window_violations -eq 0 -and $tl.lease.pause_points -eq 0)
Ok "timeline: wave reconciliation ok (dispatched == reported, no orphans)" ($tl.reconcile.wave.ok -and $tl.reconcile.wave.dispatched -eq 3 -and $tl.reconcile.wave.reported -eq 3)
# a real event span exists
Ok "timeline: has a dated span (first .. last)" ($tl.span_from -and $tl.span_to)
# deterministic total order (byte-stable across two builds)
$m2 = Build-Model
$order1 = (@($m.timeline.events | ForEach-Object { [string]$_.sort_key + '|' + [string]$_.seq }) -join "`n")
$order2 = (@($m2.timeline.events | ForEach-Object { [string]$_.sort_key + '|' + [string]$_.seq }) -join "`n")
Ok "timeline: deterministic total order (byte-stable)" ($order1 -ceq $order2)
# events sorted ascending by sort_key
$keys = @($m.timeline.events | ForEach-Object { [long]$_.sort_key })
$isSorted = $true; for ($i = 1; $i -lt $keys.Count; $i++) { if ($keys[$i] -lt $keys[$i - 1]) { $isSorted = $false } }
Ok "timeline: events are in ascending stitched order" ($isSorted)
# every timestamp is canonical ISO UTC (culture-stable; not US-locale) or empty
$tsAllIso = $true
foreach ($e in @($m.timeline.events)) { if ($e.ts -ne '' -and $e.ts -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$') { $tsAllIso = $false } }
Ok "timeline: all event timestamps are canonical ISO UTC (culture-stable)" ($tsAllIso)
Ok "ConvertTo-IsoUtc: normalizes a parsed datetime to ISO Z" ((ConvertTo-IsoUtc ('{"t":"2026-08-06T02:07:02Z"}' | ConvertFrom-Json).t) -eq '2026-08-06T02:07:02.0000000Z')

# 8. SANITIZATION -- router trace channel-only + timeline events allowlisted
$san = Test-TraceSanitized -Packet $rdRaw.packet
Ok "sanitize/trace: routed trace present + sanitized (no forbidden identifying keys)" ($san.sanitized -and $san.trace_present -and $san.removed_entry_count -ge 1)
$badTrace = (Read-ContextPacket -Path $fRouted).packet | ConvertTo-Json -Depth 90 | ConvertFrom-Json -Depth 90
$badTrace.evaluation_hooks.routing_stage_trace[1].removed[0] | Add-Member -NotePropertyName namespace -NotePropertyValue 'nsb' -Force
$sanBad = Test-TraceSanitized -Packet $badTrace
Ok "sanitize/trace: injected cross-ns key is FLAGGED (fail-closed)" (-not $sanBad.sanitized -and @($sanBad.violations).Count -ge 1)
$sanTl = Test-TimelineSanitized -Events $m.timeline.events
Ok "sanitize/timeline: every event is allowlisted (no content field)" ($sanTl.sanitized -and $sanTl.event_count -ge 4)
# an event carrying a forbidden field is flagged
$badEvt = [pscustomobject]@{ sort_key = 1; seq = 1; ts = ''; context = 'x'; source = 'y'; kind = 'z'; detail = 'd'; namespace = ''; snippet = 'LEAK' }
$sanTlBad = Test-TimelineSanitized -Events @($badEvt)
Ok "sanitize/timeline: a non-allowlisted event field is FLAGGED" (-not $sanTlBad.sanitized)
# an episode carrying a body/snippet does NOT leak into any rendered event line
$leakDir = New-TempDir 'att-leak'
$leakEp = Join-Path $leakDir 'episode.json'
'{"record_id":"ep_leak","namespace":"nsX","valid_from":"2026-08-01T09:00:00Z","valid_to":"2026-08-01T09:01:00Z","body":{"task_id":"tLeak","final_status":"ok","secret_snippet":"TOPSECRETVALUE","original_request":"ALSO_SECRET_REQUEST","stage_sequence":[{"stage_index":0,"stage_name":"plan","role":"planner","status":"ok","duration_ms":1000}]}}' | Set-Content -LiteralPath $leakEp -Encoding utf8
$mLeak = Get-AuditModel -PacketPath $fRouted -PlanPath $fPlan -ReportPaths $reportPaths -EpisodePaths @($leakEp) -WorkingStatePaths @($fWs)
$leakText = (@($mLeak.timeline.lines) -join "`n")
Ok "sanitize/timeline: an episode body/snippet NEVER leaks into a rendered line" (($leakText -notmatch 'TOPSECRETVALUE') -and ($leakText -notmatch 'ALSO_SECRET_REQUEST') -and ($leakText -match 'ep_leak'))

# 9. byte-identical re-render
$sig1 = ((@($m.tournament.lines) + @($m.timeline.lines)) -join "`n")
$sig2 = ((@($m2.tournament.lines) + @($m2.timeline.lines)) -join "`n")
Ok "render: byte-identical on unchanged input" ($sig1 -ceq $sig2)
$hdr = Format-AuditHeader -Model $m
$hdrText = (@($hdr.header_lines) -join ' ')
Ok "header: names packet_id + wave + holds_lease=no + reconciled" ($hdrText -match 'cpkt_' -and $hdrText -match 'fo-38' -and $hdrText -match 'holds_lease=no' -and $hdrText -match 'reconciled=yes')

# 10. graceful degradation
$em = Get-AuditModel -PacketPath (Join-Path $fx 'nope.json') -PlanPath $fPlan -ReportPaths $reportPaths
Ok "graceful: missing packet -> timeline still renders the wave, no throw" ($em.ok -and (-not $em.packet_ok) -and @($em.flags).Count -ge 1)
$junk = Join-Path $leakDir 'junk.json'; 'not json' | Set-Content -LiteralPath $junk -Encoding utf8
Ok "graceful: junk file -> ok=false, no throw" (-not (Read-ContextPacket -Path $junk).ok)
$emNothing = Get-AuditModel -PacketPath (Join-Path $fx 'nope.json') -PlanPath (Join-Path $fx 'nope.json')
Ok "graceful: no sources at all -> ok=false, well-formed" (-not $emNothing.ok)

# 11. READ-ONLY: fixtures tree byte-identical after a full build; write-guard refuses escape
$sigBefore = Get-TreeSig $fx
[void](Build-Model)
[void](Format-AuditHeader -Model $m)
$sigAfter = Get-TreeSig $fx
Ok "readonly: fixtures tree byte-identical after a full build + render" ($sigBefore -eq $sigAfter)
$rtDir = New-TempDir 'att-rt'
try { [void](Assert-UnderRuntime -Target (Join-Path ([System.IO.Path]::GetTempPath()) 'att-escape.json') -RuntimeDir $rtDir); Ok "readonly: write-guard refuses outside-runtime" $false 'no throw' }
catch { Ok "readonly: write-guard refuses outside-runtime" $true }
Ok "readonly: write-guard permits a path under runtime" ((Assert-UnderRuntime -Target (Join-Path $rtDir 'ok.json') -RuntimeDir $rtDir) -like (Join-Path $rtDir '*'))

# ---------- LIVE (Windows) ----------
if ($Live) {
    if (-not $IsWindows) {
        Skip 'live: WinForms self-test' 'not Windows'; Skip 'live: launch.bat' 'not Windows'; Skip 'live: real wave' 'not Windows'
    }
    else {
        $lb = Join-Path $widgetRoot 'launch.bat'
        Ok "live: launch.bat exists" (Test-Path $lb)
        if (Test-Path $lb) {
            $lbTxt = Get-Content -LiteralPath $lb -Raw
            Ok "live: launch.bat runs Show-AuditTimelineTournament.ps1 under -STA" ($lbTxt -match 'Show-AuditTimelineTournament\.ps1' -and $lbTxt -match '-STA')
        }
        $show = Join-Path $widgetRoot 'Show-AuditTimelineTournament.ps1'
        $out = & $PwshPath -NoProfile -STA -File $show -SelfTest 2>&1 | Out-String
        Write-Host "  --- self-test child output ---"
        foreach ($ln in ($out -split "`r?`n")) { if ($ln.Trim()) { Write-Host "    $ln" } }
        foreach ($marker in 'SELFTEST_FORM_OK', 'SELFTEST_MODEL_OK', 'SELFTEST_TOURNAMENT_OK', 'SELFTEST_TIMELINE_OK',
            'SELFTEST_SANITIZE_OK', 'SELFTEST_REFRESH_OK', 'SELFTEST_READONLY_OK', 'SELFTEST_LAYOUT_OK') {
            Ok "live: self-test emitted $marker" ($out -match $marker)
        }
        Ok "live: self-test has no FAIL marker" (-not ($out -match 'SELFTEST_\w+_FAIL'))

        # render a real on-box wave if present (newest complete wave + newest routed packet)
        $paths = Resolve-AuditPaths -WidgetRoot $widgetRoot -RepoRoot $RepoRoot
        $realWave = Find-NewestCompleteWave -PlansDir $paths.PlansDir
        $realPkt = Find-NewestRoutedPacket -ArtifactsDir $paths.CompilerArtifacts
        if ($null -ne $realWave -and $null -ne $realPkt) {
            $realEps = @(Find-Episodes -EpisodesDir $paths.EpisodesDir -Max 6)
            $rm = Get-AuditModel -PacketPath $realPkt -PlanPath $realWave.plan_path -ReportPaths @($realWave.report_paths) -EpisodePaths $realEps
            Ok "live: renders a REAL on-box wave + tournament (ok, has timeline + tournament)" ($rm.ok -and $null -ne $rm.timeline -and $null -ne $rm.tournament) ("wave=" + $realWave.plan_id + " err=" + [string]$rm.error)
        }
        else { Skip 'live: real wave render' 'no complete wave / routed packet on this box' }
    }
}
else {
    Skip 'live: WinForms self-test' 'cloud gate (use -Live on Windows)'
    Skip 'live: launch.bat shape' 'cloud gate'
    Skip 'live: real wave render' 'cloud gate'
}

foreach ($t in $script:tempRoots) { try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue } catch { } }

Write-Host ""
Write-Host "=== RESULT: pass=$($script:pass) fail=$($script:fail) skip=$($script:skip) ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
