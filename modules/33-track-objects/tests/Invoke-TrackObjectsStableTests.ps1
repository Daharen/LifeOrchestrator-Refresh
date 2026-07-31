#requires -Version 7.0
<#
  Invoke-TrackObjectsStableTests.ps1 -- the STABLE-mode suite for track.objects 0.2.0 (Module 33).

  DUAL-MODE + OS-portable like the baseline suite: pure deterministic logic, so the SAME harness runs the
  REAL Invoke-TrackObjects.ps1 on the cloud Linux box (pre-ship gate) and on the Windows executor (-Live).
  Covers the frontier-review P0s: the richer canonical schema (file-level metadata, sample manifest,
  termination, separated detection/association evidence, per-link association records, first-class gaps),
  canonical-JSON byte rules, scene handling (derivation from the #32 seconds shape, per-frame override,
  pre-first-cut, absent-scene conservative fallback, partial-coverage error), elapsed-time aging (max_gap +
  max_missed_samples), the two association tiers with their gates (dead zone, displacement allowance
  growth, area-ratio rejection), the Hungarian tie-rule contract on symmetric/duplicate/rectangular/
  multiple-optima layouts, double-run byte identity, and every new error path. Emits one
  "CANONHASH <name> <sha256>" line per canonical fixture for the cross-environment hash-equality gate
  (cloud vs -Live sha256 must be EQUAL).

  -PwshPath <pwsh>  : the interpreter used to invoke the skill + the generators.
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
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-TrackObjects.ps1'
$probeGen = Join-Path $moduleRoot 'New-ProbeFixture.ps1'
$probeSuite = Join-Path $moduleRoot 'tests/Invoke-TrackObjectsProbe.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$committedProbeFixture = Join-Path $moduleRoot 'tests/fixtures/probe-moderate-gap.json'

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== track.objects STABLE tests ($mode); pwsh=$PwshPath ==")

$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function TrackById([object]$canon, [long]$id) { return (@($canon.tracks) | Where-Object { [long]$_.track_id -eq $id } | Select-Object -First 1) }

# ---- AST parse of the shipped 0.2.0 .ps1 set (fail closed on a syntax error) ----
foreach ($f in @($entry, $probeGen, $probeSuite)) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Check "AST parses: $(Split-Path -Leaf $f)" (($null -eq $errs) -or (@($errs).Count -eq 0))
}

# ---- manifest 0.2.0 ----
$mf = Join-Path $moduleRoot 'skill.json'
$manifest = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest version 0.2.0' ($manifest.version -eq '0.2.0')
Check 'manifest still deterministic + parallel_safe + gpu none' ($manifest.determinism -eq 'deterministic' -and $manifest.parallel_safe -eq $true -and $manifest.requirements.gpu -eq 'none')
Check 'manifest documents mode input' (@($manifest.inputs | Where-Object { $_.name -eq 'mode' }).Count -eq 1)

$token = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$fxDir = Join-Path ([System.IO.Path]::GetTempPath()) "lo-track-stable-$token"
$artRoot = Join-Path $fxDir 'art'
New-Item -ItemType Directory -Path $fxDir -Force | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)

try {
    # ---- probe fixtures double as the canonical schema/determinism fixtures ----
    $genTxt = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probeGen -OutputDir (Join-Path $fxDir 'probe')
    $genObj = ([string]($genTxt | Out-String)).Trim() | ConvertFrom-Json
    Check 'probe fixture generator ok' ($genObj.ok -eq $true)
    $fx = $genObj.fixtures
    $fxNames = @('static','zero_iou_move','crossing','occlusion_miss','camera_shift','zoom_reframe','scene_cut','label_flip','long_gap','moderate_gap')
    $allPresent = $true
    foreach ($n in $fxNames) { if (-not ((Has $fx $n) -and (Test-Path -LiteralPath $fx.$n))) { $allPresent = $false } }
    Check 'all 10 labeled probe fixtures created' $allPresent

    # ================= the richer canonical schema (moderate_gap: links + a gap + a reacquisition) =================
    $sTxt = RunEntry @('-InputFile', $fx.moderate_gap, '-ArtifactRoot', $artRoot, '-InvocationId', 'schema-1')
    Check 'stable exit 0' ($script:code -eq 0)
    $ev = Test-SkillResultEnvelope -Json $sTxt
    Check 'stable envelope validates' ([bool]$ev.valid)
    if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
    $s = $sTxt | ConvertFrom-Json
    Check 'stable status ok (scenes present -> no warning)' ($s.status -eq 'ok')
    Check 'stable skill_version 0.2.0' ($s.skill_version -eq '0.2.0')
    Check 'stable confidence null (deterministic)' ($null -eq $s.confidence)
    $c = $s.result.canonical
    Check 'canonical schema id' ($c.schema -eq 'lifeorch.track.objects/0.2')
    Check 'canonical algorithm + tracker_version' ($c.algorithm -eq 'stable-geometric-association/1' -and $c.tracker_version -eq '0.2.0')
    $fileKeys = @($c.PSObject.Properties.Name)
    $wantKeys = @('algorithm','box_format','box_unit','coordinate_space','detector_provenance','frame_height','frame_width','identity_scope','input_digest','samples','schema','score_unit','source_media_id','source_media_sha256','summary','timestamp_unit','tracker_params','tracker_version','tracks')
    $missingK = @($wantKeys | Where-Object { $fileKeys -notcontains $_ })
    Check 'canonical file-level key set complete' ($missingK.Count -eq 0)
    Check 'canonical identity_scope + units' ($c.identity_scope -eq 'source_media+scene+tracker_invocation' -and $c.timestamp_unit -eq 'ms' -and $c.box_unit -eq 'milli_pixel' -and $c.score_unit -eq 'millionths')
    Check 'canonical input_digest well-formed + equals envelope inputs_digest' (($c.input_digest -match '^sha256:[0-9a-f]{64}$') -and ($c.input_digest -eq $s.inputs_digest))
    # sample manifest: EVERY processed sample, including the two empty ones
    Check 'sample manifest lists all 6 samples' (@($c.samples).Count -eq 6)
    $s2 = @($c.samples)[2]
    Check 'empty sample present with detection_count 0' ([long]$s2.detection_count -eq 0 -and [long]$s2.timestamp_ms -eq 1000 -and [long]$s2.scene_index -eq 0)
    Check 'sample manifest ordered by sample_index' ((@($c.samples | ForEach-Object { [long]$_.sample_index }) -join ',') -eq '0,1,2,3,4,5')
    # one track, richer track fields
    Check 'moderate_gap: ONE stable track' ([long]$c.summary.track_count -eq 1)
    $t0 = TrackById $c 0
    Check 'track lifecycle fields' ([long]$t0.observation_count -eq 4 -and [long]$t0.spanned_sample_count -eq 6 -and [long]$t0.start_ms -eq 0 -and [long]$t0.end_ms -eq 2500 -and [long]$t0.duration_ms -eq 2500)
    Check 'track termination end_of_input' ($t0.termination.reason -eq 'end_of_input' -and [long]$t0.termination.terminated_at_ms -eq 2500 -and [long]$t0.termination.last_observed_ms -eq 2500)
    Check 'association_summary separated evidence' ([long]$t0.association_summary.iou_link_count -eq 2 -and [long]$t0.association_summary.centroid_link_count -eq 1 -and [long]$t0.association_summary.reacquisition_count -eq 1 -and [long]$t0.association_summary.maximum_gap_ms -eq 1500)
    Check 'score_summary detection evidence' ([long]$t0.score_summary.scored_observation_count -eq 4 -and [long]$t0.score_summary.mean_detection_score_q -eq 900000 -and [long]$t0.score_summary.low_confidence_observation_count -eq 0)
    # observations: birth then links; the centroid reacquisition carries the gap metrics
    $obs = @($t0.observations)
    Check 'birth association metrics all null' ($obs[0].association.kind -eq 'birth' -and $null -eq $obs[0].association.gap_ms -and $null -eq $obs[0].association.iou_q -and $null -eq $obs[0].association.previous_frame_index)
    Check 'iou link records iou_q + gap_ms' ($obs[1].association.kind -eq 'iou' -and [long]$obs[1].association.iou_q -eq 454545 -and [long]$obs[1].association.gap_ms -eq 500 -and [long]$obs[1].association.missed_samples -eq 0)
    $reac = $obs[2]
    Check 'centroid reacquisition link metrics' ($reac.association.kind -eq 'centroid' -and [long]$reac.association.gap_ms -eq 1500 -and [long]$reac.association.missed_samples -eq 2 -and [long]$reac.association.iou_q -eq 0 -and [long]$reac.association.normalized_center_distance_q -eq 551250)
    # first-class gap record; NO fabricated coast boxes (observation_count == real detections only)
    Check 'gap record fields' ([long]$t0.gap_count -eq 1 -and (@($t0.gaps)[0].reacquired_by -eq 'centroid') -and [long](@($t0.gaps)[0].elapsed_ms -eq 1500) -and [long](@($t0.gaps)[0].missed_samples) -eq 2 -and [long](@($t0.gaps)[0].start_ms) -eq 500 -and [long](@($t0.gaps)[0].end_ms) -eq 2000)
    Check 'no coast pseudo-observations' ([long]$c.summary.observation_total -eq 4)
    # box quantization: milli-pixel integers
    Check 'boxes are integer milli-pixels' ([long]$obs[0].box.x -eq 40000 -and [long]$obs[0].box.width -eq 40000)
    Check 'detection_score quantized to millionths' ([long]$obs[0].detection_score -eq 900000)

    # ---- canonical BYTES: sorted keys, compact, no floats, one trailing LF; artifact sha matches ----
    $tracksArt = @($s.artifacts | Where-Object { $_.path -match 'tracks\.json$' })[0]
    $rawBytes = [System.IO.File]::ReadAllBytes($tracksArt.path)
    $rawText = $utf8.GetString($rawBytes)
    Check 'canonical starts with sorted first key' ($rawText.StartsWith('{"algorithm":"stable-geometric-association/1"'))
    Check 'canonical single line + one trailing LF' ($rawText.EndsWith("`n") -and -not $rawText.EndsWith("`n`n") -and (@($rawText -split "`n").Count -eq 2))
    Check 'canonical has no whitespace separators' (-not ($rawText -match ': ') -and -not ($rawText -match ', '))
    Check 'canonical contains no float literals' (-not ($rawText -match '[:,\[]-?[0-9]+\.[0-9]'))
    Check 'canonical sha256 matches envelope + artifact' ($s.result.canonical_sha256 -eq $tracksArt.sha256)
    Check 'diagnostics artifact split from canonical' (@($s.artifacts | Where-Object { $_.path -match 'diagnostics\.json$' }).Count -eq 1 -and -not ($rawText -match [regex]::Escape($s.invocation_id)))

    # ================= scene handling =================
    # scenes in the #32 seconds shape; derived indexes; pre-first-cut sample -> (first index - 1)
    $sc = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;    detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=10;y=10;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 4500; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=10;y=10;width=40;height=40} }) },
            [ordered]@{ frame = 2; timestamp_ms = 9000; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=10;y=10;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 4.0; end = 8.0; score = 0.8 }, [ordered]@{ index = 1; start = 8.0; end = 10.0; score = 0.7 } )
    } | ConvertTo-Json -Depth 10
    $scPath = Join-Path $fxDir 'scenes-derive.json'
    [System.IO.File]::WriteAllText($scPath, $sc, $utf8)
    $r = (RunEntry @('-InputFile', $scPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    $cs = $r.result.canonical
    Check 'scene derivation from #32 seconds shape' ((@($cs.samples | ForEach-Object { [long]$_.scene_index }) -join ',') -eq '-1,0,1')
    Check 'pre-first-cut sample gets implicit scene -1' ([long]@($cs.samples)[0].scene_index -eq -1)
    Check 'scene cuts terminate (2x scene_boundary)' ([long]$cs.summary.termination_reasons.scene_boundary -eq 2 -and [long]$cs.summary.track_count -eq 3)
    Check 'tracker_params.scene_info scenes_list' ($cs.tracker_params.scene_info -eq 'scenes_list')

    # per-frame explicit scene_index wins over the list
    $sc2 = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;   scene_index = 7; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=10;y=10;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 500; scene_index = 7; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=12;y=10;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 1.0; score = 0.8 } )
    } | ConvertTo-Json -Depth 10
    $sc2Path = Join-Path $fxDir 'scenes-override.json'
    [System.IO.File]::WriteAllText($sc2Path, $sc2, $utf8)
    $r2 = (RunEntry @('-InputFile', $sc2Path, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'explicit per-frame scene_index wins' ((@($r2.result.canonical.samples | ForEach-Object { [long]$_.scene_index }) -join ',') -eq '7,7' -and [long]$r2.result.canonical.summary.track_count -eq 1)
    Check 'tracker_params.scene_info per_frame+scenes_list' ($r2.result.canonical.tracker_params.scene_info -eq 'per_frame+scenes_list')

    # absent scene info: warning + partial + conservative effective gap; 1500 ms gap still links (<= 2000)
    $ns = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;    detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=40;y=60;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 500;  detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=55;y=60;width=40;height=40} }) },
            [ordered]@{ frame = 2; timestamp_ms = 1000; detections = @() },
            [ordered]@{ frame = 3; timestamp_ms = 1500; detections = @() },
            [ordered]@{ frame = 4; timestamp_ms = 2000; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=97;y=60;width=40;height=40} }) }
        )
    } | ConvertTo-Json -Depth 10
    $nsPath = Join-Path $fxDir 'no-scenes.json'
    [System.IO.File]::WriteAllText($nsPath, $ns, $utf8)
    $rn = (RunEntry @('-InputFile', $nsPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'no-scene input warns -> status partial' ($rn.status -eq 'partial' -and (@($rn.warnings) -match 'no scene information').Count -ge 1)
    Check 'no-scene conservative max_gap_ms_effective 2000' ([long]$rn.result.canonical.tracker_params.max_gap_ms_effective -eq 2000 -and $rn.result.canonical.tracker_params.scene_info -eq 'absent')
    Check 'no-scene 1500 ms reacquisition still under conservative gap' ([long]$rn.result.canonical.summary.track_count -eq 1 -and [long]$rn.result.canonical.summary.centroid_link_total -eq 1)

    # absent scene info + a gap beyond the conservative cap -> max_gap termination
    $ns2 = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;    detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=40;y=60;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 2500; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=42;y=60;width=40;height=40} }) }
        )
    } | ConvertTo-Json -Depth 10
    $ns2Path = Join-Path $fxDir 'no-scenes-overgap.json'
    [System.IO.File]::WriteAllText($ns2Path, $ns2, $utf8)
    $rn2 = (RunEntry @('-InputFile', $ns2Path, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'no-scene 2500 ms gap > conservative 2000 -> max_gap death + new id' ([long]$rn2.result.canonical.summary.track_count -eq 2 -and [long]$rn2.result.canonical.summary.termination_reasons.max_gap -eq 1)

    # ================= elapsed-time aging: max_missed_samples =================
    $mm = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;    detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 400;  detections = @() },
            [ordered]@{ frame = 2; timestamp_ms = 800;  detections = @() },
            [ordered]@{ frame = 3; timestamp_ms = 1200; detections = @() },
            [ordered]@{ frame = 4; timestamp_ms = 1600; detections = @() },
            [ordered]@{ frame = 5; timestamp_ms = 2000; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 3.0; score = 0.9 } )
    } | ConvertTo-Json -Depth 10
    $mmPath = Join-Path $fxDir 'missed-samples.json'
    [System.IO.File]::WriteAllText($mmPath, $mm, $utf8)
    $rm = (RunEntry @('-InputFile', $mmPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    $cm = $rm.result.canonical
    $tm = TrackById $cm 0
    Check 'max_missed_samples terminates at the 4th miss' ([long]$cm.summary.termination_reasons.max_missed_samples -eq 1 -and $tm.termination.reason -eq 'max_missed_samples' -and [long]$tm.termination.missed_samples_at_termination -eq 4 -and [long]$tm.termination.terminated_at_ms -eq 1600)
    Check 'reappearance after missed-death births a NEW id' ([long]$cm.summary.track_count -eq 2 -and $null -ne (TrackById $cm 1))
    # tightening the knob to 1 kills at the second miss
    $rm1 = (RunEntry @('-InputFile', $mmPath, '-MaxMissedSamples', '1', '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check '-MaxMissedSamples 1 terminates earlier' ([long](TrackById $rm1.result.canonical 0).termination.terminated_at_ms -eq 800)

    # ================= association tiers =================
    # dead zone: 0 < IoU < threshold qualifies for NEITHER tier (uncertainty -> end the track)
    $dz = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;   detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=0;y=0;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 400; detections = @([ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=30;y=0;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 1.0; score = 0.9 } )
    } | ConvertTo-Json -Depth 10
    $dzPath = Join-Path $fxDir 'dead-zone.json'
    [System.IO.File]::WriteAllText($dzPath, $dz, $utf8)
    $rd = (RunEntry @('-InputFile', $dzPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'sub-threshold overlap (dead zone) fragments -- no tier links' ([long]$rd.result.canonical.summary.track_count -eq 2 -and [long]$rd.result.canonical.summary.iou_link_total -eq 0 -and [long]$rd.result.canonical.summary.centroid_link_total -eq 0)

    # exact-class: identical box, different class string -> never merges (stable path)
    $mcJson = ([ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;   detections = @([ordered]@{ class='car'; class_id=2; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 400; detections = @([ordered]@{ class='person'; class_id=0; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 1.0; score = 0.9 } )
    } | ConvertTo-Json -Depth 10)
    $mcPath = Join-Path $fxDir 'stable-multiclass.json'
    [System.IO.File]::WriteAllText($mcPath, $mcJson, $utf8)
    $rmc = (RunEntry @('-InputFile', $mcPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'stable exact-class never cross-links' ([long]$rmc.result.canonical.summary.track_count -eq 2 -and [long]$rmc.result.canonical.summary.iou_link_total -eq 0)

    # ================= the Hungarian tie-rule contract =================
    # (a) SYMMETRIC / MULTIPLE EQUAL OPTIMA: two identical tracks x two identical detections -- every
    # pairing has EQUAL cost; the lexicographic (track_id, detection_rank) contract must pick
    # track0->rank0, track1->rank1 (ranks tie-break by original index).
    $sym = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;   detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 400; detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=100;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 1.0; score = 0.9 } )
    } | ConvertTo-Json -Depth 10
    $symPath = Join-Path $fxDir 'tie-symmetric.json'
    [System.IO.File]::WriteAllText($symPath, $sym, $utf8)
    $rs = (RunEntry @('-InputFile', $symPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    $st0 = TrackById $rs.result.canonical 0; $st1 = TrackById $rs.result.canonical 1
    Check 'symmetric equal-cost: lex tie rule -> t0-d0 / t1-d1' ([long]@($st0.observations)[1].detection_index -eq 0 -and [long]@($st1.observations)[1].detection_index -eq 1 -and [long]$rs.result.canonical.summary.track_count -eq 2)

    # (b) duplicate-cost pair on ONE detection: two equally-overlapping tracks, one detection -- the
    # lex rule gives it to the SMALLER track_id; the other track misses.
    $dup = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;   detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=0;y=0;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=30;y=0;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 400; detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=15;y=0;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 1.0; score = 0.9 } )
    } | ConvertTo-Json -Depth 10
    $dupPath = Join-Path $fxDir 'tie-duplicate.json'
    [System.IO.File]::WriteAllText($dupPath, $dup, $utf8)
    $rdup = (RunEntry @('-InputFile', $dupPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    $dt0 = TrackById $rdup.result.canonical 0; $dt1 = TrackById $rdup.result.canonical 1
    Check 'equal-IoU single detection -> smaller track_id wins' ([long]$dt0.observation_count -eq 2 -and [long]$dt1.observation_count -eq 1)

    # (c) RECTANGULAR wide (2 tracks x 3 detections): the far detection births a third track
    $rw = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;   detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=0;y=0;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=0;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 400; detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=5;y=0;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=105;y=0;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=300;y=0;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 1.0; score = 0.9 } )
    } | ConvertTo-Json -Depth 10
    $rwPath = Join-Path $fxDir 'rect-wide.json'
    [System.IO.File]::WriteAllText($rwPath, $rw, $utf8)
    $rrw = (RunEntry @('-InputFile', $rwPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'rectangular 2x3: both tracks extend, far det births' ([long]$rrw.result.canonical.summary.track_count -eq 3 -and [long]$rrw.result.canonical.summary.iou_link_total -eq 2)

    # (d) RECTANGULAR tall (3 tracks x 1 detection): only the best-cost track extends
    $rt = [ordered]@{
        frames = @(
            [ordered]@{ frame = 0; timestamp_ms = 0;   detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=0;y=0;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=15;y=0;width=40;height=40} },
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=100;y=0;width=40;height=40} }) },
            [ordered]@{ frame = 1; timestamp_ms = 400; detections = @(
                [ordered]@{ class='obj'; class_id=1; score=0.9; box=[ordered]@{x=15;y=0;width=40;height=40} }) }
        )
        scenes = @( [ordered]@{ index = 0; start = 0.0; end = 1.0; score = 0.9 } )
    } | ConvertTo-Json -Depth 10
    $rtPath = Join-Path $fxDir 'rect-tall.json'
    [System.IO.File]::WriteAllText($rtPath, $rt, $utf8)
    $rrt = (RunEntry @('-InputFile', $rtPath, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    $tt1 = TrackById $rrt.result.canonical 1
    Check 'rectangular 3x1: exact-overlap track (id 1) takes the detection' ([long]$tt1.observation_count -eq 2 -and [long]$rrt.result.canonical.summary.iou_link_total -eq 1)

    # ================= determinism: double-run byte identity over EVERY probe fixture =================
    $allIdentical = $true; $allDigestsEqual = $true
    $hashLines = New-Object System.Collections.Generic.List[string]
    foreach ($n in $fxNames) {
        $o1 = (RunEntry @('-InputFile', $fx.$n, '-ArtifactRoot', $artRoot, '-InvocationId', "d1-$n")) | ConvertFrom-Json
        $o2 = (RunEntry @('-InputFile', $fx.$n, '-ArtifactRoot', $artRoot, '-InvocationId', "d2-$n")) | ConvertFrom-Json
        $h1 = $o1.result.canonical_sha256; $h2 = $o2.result.canonical_sha256
        if ([string]::IsNullOrWhiteSpace($h1) -or $h1 -ne $h2) { $allIdentical = $false }
        if ($o1.inputs_digest -ne $o2.inputs_digest) { $allDigestsEqual = $false }
        $hashLines.Add("CANONHASH $n $h1")
    }
    Check 'double-run canonical byte identity on all 10 fixtures' $allIdentical
    Check 'double-run input digests identical' $allDigestsEqual
    foreach ($l in $hashLines.ToArray()) { [Console]::Out.WriteLine($l) }

    # ================= committed canonical fixture (the Verification Console item) =================
    Check 'committed probe-moderate-gap fixture exists' (Test-Path -LiteralPath $committedProbeFixture)
    $rc = (RunEntry @('-InputFile', $committedProbeFixture, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'committed fixture: ONE track via centroid reacquisition' ($rc.status -eq 'ok' -and [long]$rc.result.canonical.summary.track_count -eq 1 -and [long]$rc.result.canonical.summary.centroid_link_total -eq 1)
    [Console]::Out.WriteLine("CANONHASH committed-moderate-gap $($rc.result.canonical_sha256)")

    # ================= passthrough metadata + clipping =================
    $pt = (RunEntry @('-InputFile', $fx.static, '-FrameWidth', '120', '-FrameHeight', '130',
                      '-SourceMediaId', 'clip-001', '-SourceMediaSha256', ('ab' * 32), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    $cpt = $pt.result.canonical
    Check 'frame dims + source media recorded' ([long]$cpt.frame_width -eq 120 -and [long]$cpt.frame_height -eq 130 -and $cpt.source_media_id -eq 'clip-001' -and $cpt.source_media_sha256 -eq ('ab' * 32))
    $ptObs = @((TrackById $cpt 0).observations)[0]
    Check 'boxes clipped to source dims (x 100..140 -> width 20 px)' ([long]$ptObs.box.x -eq 100000 -and [long]$ptObs.box.width -eq 20000)
    # detector_provenance via InputsJson rides into the canonical file
    $dpJson = ([ordered]@{ input = "$($fx.static)"; detector_provenance = [ordered]@{ model_id = 'detect.yolox.nano'; label_map_sha256 = ('cd' * 32) } } | ConvertTo-Json -Compress)
    $rdp = (RunEntry @('-InputsJson', $dpJson, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'detector_provenance passthrough' ($rdp.result.canonical.detector_provenance.model_id -eq 'detect.yolox.nano')

    # stable params via InputsJson
    $pjJson = ([ordered]@{ input = "$($fx.long_gap)"; max_gap_ms = 10000 } | ConvertTo-Json -Compress)
    $rpj = (RunEntry @('-InputsJson', $pjJson, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'InputsJson max_gap_ms widens the gap (6500 ms now survives)' ([long]$rpj.result.canonical.summary.track_count -eq 1 -and [long]$rpj.result.canonical.tracker_params.max_gap_ms -eq 10000)

    # ================= new error paths =================
    $e1 = (RunEntry @('-InputFile', $fx.static, '-Mode', 'sideways')) | ConvertFrom-Json
    Check 'invalid_mode error' ($e1.status -eq 'error' -and $e1.error.code -eq 'invalid_mode')
    $ntPath = Join-Path $fxDir 'no-ts.json'
    [System.IO.File]::WriteAllText($ntPath, '{"frames":[{"frame":0,"detections":[{"class":"car","class_id":2,"score":0.9,"box":{"x":1,"y":1,"width":10,"height":10}}]}]}', $utf8)
    $e2 = (RunEntry @('-InputFile', $ntPath)) | ConvertFrom-Json
    Check 'missing_timestamp error (stable requires real time)' ($e2.status -eq 'error' -and $e2.error.code -eq 'missing_timestamp')
    $psPath = Join-Path $fxDir 'partial-scene.json'
    [System.IO.File]::WriteAllText($psPath, '{"frames":[{"frame":0,"timestamp_ms":0,"scene_index":0,"detections":[]},{"frame":1,"timestamp_ms":500,"detections":[]}]}', $utf8)
    $e3 = (RunEntry @('-InputFile', $psPath)) | ConvertFrom-Json
    Check 'invalid_scene on partial per-frame coverage' ($e3.status -eq 'error' -and $e3.error.code -eq 'invalid_scene')
    $e4 = (RunEntry @('-InputFile', $fx.static, '-MaxGapMs', '-5')) | ConvertFrom-Json
    Check 'invalid_max_gap_ms error' ($e4.status -eq 'error' -and $e4.error.code -eq 'invalid_max_gap_ms')
    $e5 = (RunEntry @('-InputFile', $fx.static, '-MaxAreaRatio', '0.5')) | ConvertFrom-Json
    Check 'invalid_area_ratio error (must be >= 1)' ($e5.status -eq 'error' -and $e5.error.code -eq 'invalid_area_ratio')
    $e6 = (RunEntry @('-InputFile', $fx.static, '-FrameWidth', '100')) | ConvertFrom-Json
    Check 'invalid_frame_dims error (width without height)' ($e6.status -eq 'error' -and $e6.error.code -eq 'invalid_frame_dims')
    $e7 = (RunEntry @('-InputFile', $fx.static, '-ScenesFile', (Join-Path $fxDir 'nope.json'))) | ConvertFrom-Json
    Check 'scenes_file_not_found error' ($e7.status -eq 'error' -and $e7.error.code -eq 'scenes_file_not_found')
    $e8 = (RunEntry @('-InputFile', $fx.static, '-MaxMissedSamples', '-1')) | ConvertFrom-Json
    Check 'invalid_max_missed_samples error' ($e8.status -eq 'error' -and $e8.error.code -eq 'invalid_max_missed_samples')

    # ================= Module 1 wrapper in stable mode =================
    $wjson = ([ordered]@{ input = "$($fx.moderate_gap)" } | ConvertTo-Json -Compress)
    $rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson $wjson -PwshPath $PwshPath -ArtifactRoot $artRoot
    $repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
    Check 'wrapper stable: manifest + envelope valid' ($repObj.manifest_valid -eq $true -and $repObj.envelope_valid -eq $true)
    Check 'wrapper stable: canonical track count 1' ([long]$repObj.envelope.result.canonical.summary.track_count -eq 1)
}
finally {
    try { if (Test-Path -LiteralPath $fxDir) { Remove-Item -LiteralPath $fxDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
