#requires -Version 7.0
<#
  Invoke-TrackObjectsProbe.ps1 -- the identity-LABELED probe for track.objects 0.2.0 (Module 33).

  The frontier design review's "first probe", scoped to fixtures: New-ProbeFixture.ps1 hand-authors ten
  labeled detection sequences (static / zero-IoU move / same-class crossing / occlusion-miss / camera
  shift / zoom+area-gate / hard scene cut / label flip / long gap / moderate gap); this harness runs
  -Mode greedy AND -Mode stable over every fixture and scores both against the ground-truth labels:

    false_merges         -- tracks whose observations span >1 distinct ground-truth label (the
                            semantically corrupting failure; the review: prioritize this over
                            fragmentation);
    id_switches          -- observation-to-observation label changes inside a track;
    fragments_per_object -- total (label, track) coverage pairs / labels (1.00 = perfect identity);
    correct_links        -- consecutive same-track observation pairs whose labels agree, / total links.

  ACCEPTANCE BAR (asserted): stable has ZERO false merges and ZERO id switches across the entire labeled
  set; stable beats greedy on within-scene moderate-gap fragmentation (moderate_gap + zero_iou_move);
  greedy's characteristic false merges (crossing order-dependence, the hard scene cut, the 6.5 s
  frame-count-blind long gap) are demonstrated, not hidden. Prints the per-fixture comparison table as
  a markdown block ("PROBE TABLE") for the ship report.

  -PwshPath <pwsh>  : the interpreter used to invoke the skill + the generator.
  -Live             : informational banner only (the assertions are identical in both modes).
#>
[CmdletBinding()]
param(
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [switch]$Live
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $moduleRoot 'Invoke-TrackObjects.ps1'
$probeGen = Join-Path $moduleRoot 'New-ProbeFixture.ps1'

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== track.objects labeled PROBE ($mode); pwsh=$PwshPath ==")

$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}

# Ground-truth label map from a fixture doc: "frame|detIndex" -> label
function Get-LabelMap([string]$fixturePath) {
    $doc = (Get-Content -LiteralPath $fixturePath -Raw) | ConvertFrom-Json
    $map = @{}
    foreach ($f in @($doc.frames)) {
        $fi = [long]$f.frame
        $dets = @($f.detections)
        for ($di = 0; $di -lt $dets.Count; $di++) {
            $map["$fi|$di"] = [string]$dets[$di].label
        }
    }
    return $map
}
# Per-mode metric row: track observations -> label sequences -> the four probe metrics.
function Get-Metrics([hashtable]$labels, [object[]]$trackObsLists) {
    $falseMerges = 0; $idSwitches = 0; $correct = 0; $links = 0
    $labelTracks = @{}   # label -> set of track ordinals covering it
    for ($ti = 0; $ti -lt $trackObsLists.Count; $ti++) {
        $seq = @($trackObsLists[$ti])
        $distinct = @($seq | Select-Object -Unique)
        if ($distinct.Count -gt 1) { $falseMerges++ }
        for ($k = 1; $k -lt $seq.Count; $k++) {
            $links++
            if ($seq[$k] -ceq $seq[$k - 1]) { $correct++ } else { $idSwitches++ }
        }
        foreach ($lb in $distinct) {
            if (-not $labelTracks.ContainsKey($lb)) { $labelTracks[$lb] = New-Object 'System.Collections.Generic.HashSet[int]' }
            [void]$labelTracks[$lb].Add($ti)
        }
    }
    $objects = $labelTracks.Keys.Count
    $fragments = 0
    foreach ($k in $labelTracks.Keys) { $fragments += $labelTracks[$k].Count }
    $fpo = if ($objects -gt 0) { [math]::Round($fragments / $objects, 2) } else { 0.0 }
    return [pscustomobject]@{
        false_merges = $falseMerges; id_switches = $idSwitches
        fragments = $fragments; objects = $objects; fragments_per_object = $fpo
        correct_links = $correct; total_links = $links
    }
}
function Get-StableObsLabels([object]$env, [hashtable]$labels) {
    # NOTE: comma-wrapped return -- the pipeline would otherwise unroll the outer array and flatten
    # the per-track label sequences (the repo's known array double-wrap/unroll gotcha, inverted).
    $lists = New-Object System.Collections.Generic.List[object]
    foreach ($t in @($env.result.canonical.tracks)) {
        $seq = New-Object System.Collections.Generic.List[string]
        foreach ($o in @($t.observations)) { $seq.Add([string]$labels["$([long]$o.frame_index)|$([long]$o.detection_index)"]) }
        $lists.Add($seq.ToArray())
    }
    return ,($lists.ToArray())
}
function Get-GreedyObsLabels([object]$env, [hashtable]$labels) {
    $lists = New-Object System.Collections.Generic.List[object]
    foreach ($t in @($env.result.tracks)) {
        $seq = New-Object System.Collections.Generic.List[string]
        foreach ($o in @($t.frames)) { $seq.Add([string]$labels["$([long]$o.frame)|$([long]$o.det_index)"]) }
        $lists.Add($seq.ToArray())
    }
    return ,($lists.ToArray())
}

$token = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$fxDir = Join-Path ([System.IO.Path]::GetTempPath()) "lo-track-probe-$token"
$artRoot = Join-Path $fxDir 'art'
try {
    $genTxt = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probeGen -OutputDir $fxDir
    $genObj = ([string]($genTxt | Out-String)).Trim() | ConvertFrom-Json
    Check 'probe fixture generator ok' ($genObj.ok -eq $true)
    $fx = $genObj.fixtures
    $fxNames = @('static','zero_iou_move','crossing','occlusion_miss','camera_shift','zoom_reframe','scene_cut','label_flip','long_gap','moderate_gap')

    $rows = New-Object System.Collections.Generic.List[object]
    $stableEnv = @{}; $greedyEnv = @{}
    $allOk = $true
    foreach ($n in $fxNames) {
        $se = (RunEntry @('-InputFile', $fx.$n, '-ArtifactRoot', $artRoot, '-InvocationId', "probe-s-$n")) | ConvertFrom-Json
        $ge = (RunEntry @('-InputFile', $fx.$n, '-Mode', 'greedy', '-ArtifactRoot', $artRoot, '-InvocationId', "probe-g-$n")) | ConvertFrom-Json
        if ($se.status -notin @('ok', 'partial') -or $ge.status -notin @('ok', 'partial')) { $allOk = $false }
        $stableEnv[$n] = $se; $greedyEnv[$n] = $ge
        $labels = Get-LabelMap $fx.$n
        $sm = Get-Metrics $labels (Get-StableObsLabels $se $labels)
        $gm = Get-Metrics $labels (Get-GreedyObsLabels $ge $labels)
        $rows.Add([pscustomobject]@{ fixture = $n; stable = $sm; greedy = $gm
            stable_tracks = [long]$se.result.canonical.summary.track_count
            greedy_tracks = [long]$ge.result.summary.track_count })
    }
    Check 'both modes ran every fixture' $allOk

    # ---- the comparison table (markdown, for the ship report) ----
    [Console]::Out.WriteLine('PROBE TABLE')
    [Console]::Out.WriteLine('| fixture | mode | tracks | false_merges | id_switches | fragments/object | correct_links |')
    [Console]::Out.WriteLine('|---|---|---|---|---|---|---|')
    foreach ($r in $rows.ToArray()) {
        [Console]::Out.WriteLine("| $($r.fixture) | greedy | $($r.greedy_tracks) | $($r.greedy.false_merges) | $($r.greedy.id_switches) | $($r.greedy.fragments_per_object.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)) ($($r.greedy.fragments)/$($r.greedy.objects)) | $($r.greedy.correct_links)/$($r.greedy.total_links) |")
        [Console]::Out.WriteLine("| $($r.fixture) | stable | $($r.stable_tracks) | $($r.stable.false_merges) | $($r.stable.id_switches) | $($r.stable.fragments_per_object.ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)) ($($r.stable.fragments)/$($r.stable.objects)) | $($r.stable.correct_links)/$($r.stable.total_links) |")
    }
    [Console]::Out.WriteLine('END PROBE TABLE')

    # ================= THE ACCEPTANCE BAR =================
    $stableMergeTotal = 0; $stableSwitchTotal = 0
    foreach ($r in $rows.ToArray()) { $stableMergeTotal += $r.stable.false_merges; $stableSwitchTotal += $r.stable.id_switches }
    Check 'BAR: stable has ZERO false merges across the entire labeled set' ($stableMergeTotal -eq 0)
    Check 'BAR: stable has ZERO id switches across the entire labeled set' ($stableSwitchTotal -eq 0)

    $rModGap = @($rows.ToArray() | Where-Object { $_.fixture -eq 'moderate_gap' })[0]
    Check 'BAR: moderate_gap -- stable 1 fragment vs greedy 2 (the within-scene moderate-gap win)' ($rModGap.stable.fragments -eq 1 -and $rModGap.greedy.fragments -eq 2 -and $rModGap.stable_tracks -eq 1 -and $rModGap.greedy_tracks -eq 2)
    $rZero = @($rows.ToArray() | Where-Object { $_.fixture -eq 'zero_iou_move' })[0]
    Check 'BAR: zero_iou_move -- stable 1 track vs greedy 5 (gated fallback earns its keep)' ($rZero.stable_tracks -eq 1 -and $rZero.greedy_tracks -eq 5 -and $rZero.stable.correct_links -eq 4)

    # greedy's characteristic failures demonstrated (labels prove them; stable stays clean)
    $rCross = @($rows.ToArray() | Where-Object { $_.fixture -eq 'crossing' })[0]
    Check 'crossing: greedy order-dependence false-merges; global assignment does not' ($rCross.greedy.false_merges -ge 1 -and $rCross.stable.false_merges -eq 0 -and $rCross.stable_tracks -eq 2 -and $rCross.stable.correct_links -eq $rCross.stable.total_links)
    $rCut = @($rows.ToArray() | Where-Object { $_.fixture -eq 'scene_cut' })[0]
    Check 'scene_cut: greedy merges across the cut; stable terminates scene_boundary' ($rCut.greedy.false_merges -eq 1 -and $rCut.stable.false_merges -eq 0 -and [long]$stableEnv['scene_cut'].result.canonical.summary.termination_reasons.scene_boundary -eq 1)
    $rLong = @($rows.ToArray() | Where-Object { $_.fixture -eq 'long_gap' })[0]
    Check 'long_gap: greedy frame-count aging merges across 6.5 s; stable max_gap terminates' ($rLong.greedy.false_merges -eq 1 -and $rLong.stable.false_merges -eq 0 -and [long]$stableEnv['long_gap'].result.canonical.summary.termination_reasons.max_gap -eq 1)

    # conservative-refusal cases: fragmentation is the accepted trade, merges are not
    $rCam = @($rows.ToArray() | Where-Object { $_.fixture -eq 'camera_shift' })[0]
    Check 'camera_shift: capped fallback refuses the pan in BOTH directions (no merge, 2 fragments/object)' ($rCam.stable.false_merges -eq 0 -and $rCam.stable.fragments -eq 4 -and $rCam.stable.objects -eq 2)
    $rZoom = @($rows.ToArray() | Where-Object { $_.fixture -eq 'zoom_reframe' })[0]
    Check 'zoom_reframe: gentle zoom links tier-1; the 16x area ratio is REJECTED' ($rZoom.stable.false_merges -eq 0 -and $rZoom.stable_tracks -eq 3 -and [long]$stableEnv['zoom_reframe'].result.canonical.summary.centroid_link_total -eq 0)
    $rFlip = @($rows.ToArray() | Where-Object { $_.fixture -eq 'label_flip' })[0]
    Check 'label_flip: exact-class fragments (accepted trade), never merges' ($rFlip.stable.false_merges -eq 0 -and $rFlip.stable_tracks -eq 2 -and $rFlip.greedy_tracks -eq 2)
    $rStatic = @($rows.ToArray() | Where-Object { $_.fixture -eq 'static' })[0]
    Check 'static: one track, all links correct, both modes' ($rStatic.stable_tracks -eq 1 -and $rStatic.greedy_tracks -eq 1 -and $rStatic.stable.correct_links -eq 4)
    $rOcc = @($rows.ToArray() | Where-Object { $_.fixture -eq 'occlusion_miss' })[0]
    $occT = @($stableEnv['occlusion_miss'].result.canonical.tracks)[0]
    Check 'occlusion_miss: one track + a first-class gap reacquired_by iou' ($rOcc.stable_tracks -eq 1 -and [long]$occT.gap_count -eq 1 -and (@($occT.gaps)[0].reacquired_by -eq 'iou'))

    # greedy-mode probe runs stay valid envelopes (regression guard on the retained baseline)
    $gv = $true
    foreach ($n in $fxNames) { if ($greedyEnv[$n].skill_version -ne '0.2.0' -or $greedyEnv[$n].status -notin @('ok','partial')) { $gv = $false } }
    Check 'greedy baseline ran clean across the probe set' $gv
}
finally {
    try { if (Test-Path -LiteralPath $fxDir) { Remove-Item -LiteralPath $fxDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
