#requires -Version 7.0
<#
  Invoke-VideoTimelineReconTests.ps1 -- the i22 ORCHESTRATOR-FOLD reconciliation suite (video.timeline 0.1.1).

  Locks the consumer to the track.objects 0.2.0 EMITTER contract that the two i22 workers -- built in
  deliberate isolation against the same design digest -- read differently, as found by the orchestrator's
  cross-module smoke (plan fo-22-d2c492e7):
    (1) tracks.score_unit 'millionths' declared by the 0.2.0 canonical file => observation detection_score
        is ALREADY integer millionths (no re-quantization; 900000 stays 900000, never 900000000000);
        float mode (score_unit absent/'unit_float') is now FAIL-CLOSED at > 1 instead of silently scaling.
    (2) scene_index -1 = "before the first listed scene" (the 0.2.0 pre-first-cut interpretation) is VALID
        on samples and tracks; -1 is not a listed scene, so it never appears in index.by_scene.
  Fixtures tracks-millionths.json / tracks-prescene.json embed REAL track.objects 0.2.0 canonical output
  (captured from the committed probe fixture + a pre-first-scene input on the box) verbatim.

  Same dual-mode real-skill shape as Invoke-VideoTimelineTests.ps1; prints CANONICAL-HASH lines for the
  two ok fixtures so cloud and -Live runs compare byte-identity cross-environment.
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
$entry = Join-Path $moduleRoot 'Invoke-VideoTimeline.ps1'
$fxDir = Join-Path $moduleRoot 'tests/fixtures'
$tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vtl-recon-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== video.timeline RECON tests ($mode); pwsh=$PwshPath ==")

$script:pass = 0; $script:fail = 0
function Assert([bool]$cond, [string]$name) {
    if ($cond) { $script:pass++; [Console]::Out.WriteLine("PASS $name") }
    else { $script:fail++; [Console]::Out.WriteLine("FAIL $name") }
}

function Invoke-Vtl([string]$fixture, [string]$tag) {
    $art = Join-Path $tmpRoot $tag
    $errFile = Join-Path $tmpRoot ($tag + '.stderr.txt')
    $raw = & $PwshPath -NoProfile -File $entry -InputFile (Join-Path $fxDir $fixture) -ArtifactRoot $art 2>$errFile
    if ($LASTEXITCODE -ne 0) { throw "entrypoint exit $LASTEXITCODE for ${tag}" }
    return (($raw -join "`n") | ConvertFrom-Json)
}

function Get-TimelineDoc($envelope) {
    $p = [string]$envelope.result.timeline.path
    return (Get-Content -Raw -LiteralPath $p | ConvertFrom-Json)
}

# ---------- 1) millionths declaration honored (REAL 0.2.0 emitter bytes inline) ----------
$envA = Invoke-Vtl 'tracks-millionths.json' 'millionths'
Assert ([string]$envA.status -eq 'ok') 'millionths: status ok'
$tlA = Get-TimelineDoc $envA
$tpA = @($tlA.intervals | Where-Object { $_.kind -eq 'track_presence' })
$tgA = @($tlA.intervals | Where-Object { $_.kind -eq 'track_gap' })
Assert ($tpA.Count -eq 2 -and $tgA.Count -eq 1) ("millionths: appearance segmentation 2 spans + 1 gap (got " + $tpA.Count + "+" + $tgA.Count + ")")
$d1 = $tpA[0].evidence.detection
Assert ([long]$d1.mean_detection_score_q -eq 900000 -and [long]$d1.min_detection_score_q -eq 900000 -and [long]$d1.max_detection_score_q -eq 900000) ("millionths: span1 detection q == 900000 verbatim, NOT re-quantized (got mean " + $d1.mean_detection_score_q + ")")
$a1 = $tpA[0].evidence.association
Assert ([long]$a1.iou_link_count -eq 1 -and [long]$a1.centroid_link_count -eq 0 -and [long]$a1.weakest_link_quality_q -eq 454545 -and [long]$a1.maximum_gap_ms -eq 500) 'millionths: span1 association evidence (iou 1, weakest 454545, max_gap 500)'
$a2 = $tpA[1].evidence.association
Assert ([long]$a2.iou_link_count -eq 1 -and [long]$a2.centroid_link_count -eq 1 -and [long]$a2.reacquisition_count -eq 1 -and [long]$a2.weakest_link_quality_q -eq 0 -and [long]$a2.maximum_gap_ms -eq 1500) 'millionths: span2 association evidence (centroid reacquisition, weakest 0, max_gap 1500)'
$d2 = $tpA[1].evidence.detection
Assert ([long]$d2.mean_detection_score_q -eq 900000) 'millionths: span2 detection q == 900000'
Assert ([long]$tgA[0].elapsed_ms -eq 1500 -and [long]$tgA[0].missed_samples -eq 2 -and [string]$tgA[0].reacquired_by -eq 'centroid') 'millionths: first-class gap carried verbatim'
$canonA = Get-Content -Raw -LiteralPath ([string]$envA.result.timeline.path)
Assert (-not ($canonA -match '"confidence"')) 'millionths: no confidence field in canonical bytes'
[Console]::Out.WriteLine("CANONICAL-HASH recon-millionths=" + [string]$envA.result.timeline.sha256)

# double-run byte-identity
$envA2 = Invoke-Vtl 'tracks-millionths.json' 'millionths2'
Assert ([string]$envA2.result.timeline.sha256 -eq [string]$envA.result.timeline.sha256) 'millionths: double-run byte-identical'

# ---------- 2) scene_index -1 accepted (REAL 0.2.0 pre-first-scene emitter bytes inline) ----------
$envB = Invoke-Vtl 'tracks-prescene.json' 'prescene'
Assert ([string]$envB.status -eq 'ok') 'prescene: status ok (scene_index -1 no longer refused)'
$tlB = Get-TimelineDoc $envB
$tpB = @($tlB.intervals | Where-Object { $_.kind -eq 'track_presence' })
$sceneVals = @($tpB | ForEach-Object { [long]$_.scene_index } | Sort-Object)
Assert ($tpB.Count -eq 3 -and $sceneVals[0] -eq -1 -and $sceneVals[1] -eq 0 -and $sceneVals[2] -eq 1) ("prescene: presence spans carry scene_index -1/0/1 (got " + ($sceneVals -join ',') + ")")
$cutB = @($tlB.events | Where-Object { $_.kind -eq 'scene_cut' })
Assert ($cutB.Count -eq 2) 'prescene: 2 scene_cut events from the #32-shape scenes'
$bySceneKeys = @($tlB.index.by_scene.PSObject.Properties.Name)
Assert (($bySceneKeys -contains '0') -and ($bySceneKeys -contains '1') -and (-not ($bySceneKeys -contains '-1'))) 'prescene: index.by_scene lists only listed scenes (no -1 bucket)'
Assert ([string]$envB.result.coverage_status -eq 'sampled') 'prescene: coverage sampled (manifest from the track file)'
[Console]::Out.WriteLine("CANONICAL-HASH recon-prescene=" + [string]$envB.result.timeline.sha256)

# ---------- 3) refusal: millionths declared + a float score ----------
$envC = Invoke-Vtl 'tracks-scoreunit-refuse.json' 'su-refuse'
Assert ([string]$envC.status -eq 'error') 'scoreunit-refuse: status error'
$vioC = @($envC.result.violations | ForEach-Object { [string]$_.path + ' ' + [string]$_.why })
Assert ((@($vioC | Where-Object { $_ -match 'detection_score' -and $_ -match 'integer' })).Count -ge 1) 'scoreunit-refuse: names the non-integer detection_score'

# ---------- 4) refusal: float mode + an integer-millionths score (the old silent-corruption case) ----------
$envD = Invoke-Vtl 'tracks-floatscore-refuse.json' 'fs-refuse'
Assert ([string]$envD.status -eq 'error') 'floatscore-refuse: status error (silent x1e6 inflation is now fail-closed)'
$vioD = @($envD.result.violations | ForEach-Object { [string]$_.path + ' ' + [string]$_.why })
Assert ((@($vioD | Where-Object { $_ -match 'detection_score' -and $_ -match 'must be <= 1' })).Count -ge 1) 'floatscore-refuse: names the out-of-unit-interval score'

# ---------- 5) regression: float mode still works for unit-interval scores ----------
$envE = Invoke-Vtl 'tracks-embedded-samples.json' 'float-regress'
Assert ([string]$envE.status -eq 'ok') 'float-regress: embedded-samples fixture still ok'
$tlE = Get-TimelineDoc $envE
$tpE = @($tlE.intervals | Where-Object { $_.kind -eq 'track_presence' })
$dE = $tpE[0].evidence.detection
Assert ([long]$dE.mean_detection_score_q -eq 885000 -and [long]$dE.min_detection_score_q -eq 870000 -and [long]$dE.max_detection_score_q -eq 900000) 'float-regress: 0.9/0.87 quantize to 900000/870000 (mean 885000)'

# ---------- summary ----------
$total = $script:pass + $script:fail
if ($script:fail -eq 0) {
    [Console]::Out.WriteLine("ALL TESTS PASSED ($script:pass/$total)")
    exit 0
} else {
    [Console]::Out.WriteLine("FAILURES: $script:fail of $total")
    exit 1
}
