#requires -Version 7.0
<#
  Invoke-VideoTimelineTests.ps1 -- regression tests for video.timeline (Module 34).

  DUAL-MODE + OS-portable (the #32/#33 real-skill gate, NOT a mock): video.timeline is PURE deterministic
  logic -- no CUDA, no model, no OS-specific API, no external binary -- so the SAME harness runs the REAL
  Invoke-VideoTimeline.ps1 on the cloud Linux box (pre-ship gate) and on the Windows executor (-Live).
  Fixtures are COMMITTED under tests/fixtures/ (no generator: the fixtures are the documentation of the
  consumed reviewed-track/sample/scene/transcript/ocr/detection shapes):
    fused.json / fused-scrambled.json  the full fuse + its order-scrambled twin (canonical-ordering proof)
    meta-only / tracks-nosamples / transcript-only / ocr-map / ocr-refuse   the documented degradation modes
    adversarial-scenes / gap-heavy / zero-observation / unlisted-sample / empty-sections / tracks-embedded-samples
  It exercises strict validation refusal (fail-closed violation envelopes), canonical byte discipline
  (sorted keys, single LF, no CR/BOM, no abs paths / invocation ids / wall-clock, no "confidence" field),
  appearance segmentation (splits at recorded gaps; NEVER merges across one), separated detection vs
  association evidence, event ordering, the index refs, every degradation mode, double-run byte-identity,
  and the Module 1 wrapper. It PRINTS `CANONICAL-HASH <fixture>=<sha256>` lines so the cloud and -Live
  runs can be compared for cross-environment byte-identity.

  -PwshPath <pwsh>  : the interpreter used to invoke the skill. Passed through explicitly.
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
$entry   = Join-Path $moduleRoot 'Invoke-VideoTimeline.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$fxDirC  = Join-Path $moduleRoot 'tests/fixtures'

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== video.timeline tests ($mode); pwsh=$PwshPath ==")

$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function TimelineArtifact([object]$env) { return (@($env.artifacts | Where-Object { $_.path -match 'timeline\.json$' }) | Select-Object -First 1) }
function ReadTimeline([object]$env) {
    $a = TimelineArtifact $env
    if ($null -eq $a) { return $null }
    return [pscustomobject]@{ text = [System.IO.File]::ReadAllText([string]$a.path); bytes = [System.IO.File]::ReadAllBytes([string]$a.path); sha = [string]$a.sha256; path = [string]$a.path }
}
function ViolationPaths([object]$env) { return @(@($env.result.violations) | ForEach-Object { [string]$_.path }) }

# ---- AST parse of the shipped .ps1 (fail closed on a syntax error) ----
$errs = $null; $toks = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($entry, [ref]$toks, [ref]$errs)
Check 'AST parses: Invoke-VideoTimeline.ps1' (($null -eq $errs) -or (@($errs).Count -eq 0))

# ---- manifest ----
$mf = Join-Path $moduleRoot 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$manifest = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest skill_id video.timeline' ($manifest.skill_id -eq 'video.timeline')
Check 'manifest parallel_safe true' ($manifest.parallel_safe -eq $true)
Check 'manifest deterministic' ($manifest.determinism -eq 'deterministic')
Check 'manifest gpu none' ($manifest.requirements.gpu -eq 'none')
Check 'manifest models empty' (@($manifest.requirements.models).Count -eq 0)
Check 'manifest network false' ($manifest.requirements.network -eq $false)
Check 'manifest pwsh-only executables' ((@($manifest.requirements.executables).Count -eq 1) -and ([string]@($manifest.requirements.executables)[0] -like 'pwsh*'))

# ---- workspace ----
$token = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "lo-vtl-fx-$token"
$artRoot = Join-Path $tmpDir 'art'
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)

try {
    foreach ($n in @('fused', 'fused-scrambled', 'meta-only', 'tracks-nosamples', 'transcript-only', 'ocr-map', 'ocr-refuse', 'adversarial-scenes', 'gap-heavy', 'zero-observation', 'unlisted-sample', 'empty-sections', 'tracks-embedded-samples')) {
        Check "fixture $n present" (Test-Path -LiteralPath (Join-Path $fxDirC "$n.json"))
    }

    # ================= the full fused fixture =================
    $probe = 'canonical-leak-probe-1'
    $fTxt = RunEntry @('-InputFile', (Join-Path $fxDirC 'fused.json'), '-ArtifactRoot', $artRoot, '-InvocationId', $probe)
    Check 'fused exit 0' ($script:code -eq 0)
    $ev = Test-SkillResultEnvelope -Json $fTxt
    Check 'fused envelope validates' ([bool]$ev.valid)
    if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
    $f = $fTxt | ConvertFrom-Json
    Check 'fused status ok (no warnings on the clean fuse)' ($f.status -eq 'ok')
    Check 'fused contract 0.2' ($f.contract_version -eq '0.2')
    Check 'fused confidence null (deterministic)' ($null -eq $f.confidence)
    Check 'fused model_provenance empty' (@($f.model_provenance).Count -eq 0)
    Check 'fused timeline.json + timeline.md artifacts' ((@($f.artifacts | Where-Object { $_.path -match 'timeline\.json$' }).Count -eq 1) -and (@($f.artifacts | Where-Object { $_.path -match 'timeline\.md$' }).Count -eq 1))
    Check 'fused all inputs marked provided' (($f.result.input.provided.media -eq $true) -and ($f.result.input.provided.scenes -eq $true) -and ($f.result.input.provided.samples -eq $true) -and ($f.result.input.provided.tracks -eq $true) -and ($f.result.input.provided.transcript -eq $true) -and ($f.result.input.provided.ocr -eq $true) -and ($f.result.input.provided.detections -eq $true))

    $ft = ReadTimeline $f
    $tl = $ft.text | ConvertFrom-Json

    # canonical byte discipline
    Check 'canonical: no BOM (first byte {)' ($ft.bytes[0] -eq 0x7B)
    Check 'canonical: single trailing LF, no CR' (($ft.bytes[$ft.bytes.Length - 1] -eq 0x0A) -and (@($ft.bytes | Where-Object { $_ -eq 0x0A }).Count -eq 1) -and (@($ft.bytes | Where-Object { $_ -eq 0x0D }).Count -eq 0))
    Check 'canonical: sorted keys (starts {"coverage":)' ($ft.text.StartsWith('{"coverage":'))
    Check 'canonical: sorted keys (ends "timestamp_unit":"ms"})' ($ft.text.TrimEnd("`n").EndsWith('"timestamp_unit":"ms"}'))
    Check 'canonical: schema id present' ($tl.schema -eq 'lifeorch.video_timeline/0.1')
    Check 'canonical: generator name+version+params' (($tl.generator.name -eq 'video.timeline') -and ($tl.generator.version -eq '0.1.0') -and (Has $tl.generator 'params'))
    Check 'canonical: input_digest sha256 format' ([string]$tl.input_digest -match '^sha256:[0-9a-f]{64}$')
    Check 'canonical: NO "confidence" field anywhere' (-not $ft.text.Contains('"confidence"'))
    Check 'canonical: no invocation id leak' (-not $ft.text.Contains($probe))
    Check 'canonical: no path leak (no "path" key, no artifact root)' ((-not $ft.text.Contains('"path"')) -and (-not $ft.text.Contains('runtime')) -and (-not $ft.text.Contains(':\\')))
    Check 'canonical: no wall-clock leak (no utc/started keys)' ((-not $ft.text.Contains('_utc')) -and (-not $ft.text.Contains('started_at')))
    Check 'envelope timeline sha matches recomputed file hash' ((Get-FileHash -LiteralPath $ft.path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $f.result.timeline.sha256)
    Check 'envelope inputs_digest == timeline input_digest' ($f.inputs_digest -eq [string]$tl.input_digest)

    # source + identity + coverage
    Check 'source dims + duration + media_id + sha' (($tl.source.frame_width -eq 640) -and ($tl.source.frame_height -eq 360) -and ($tl.source.duration_ms -eq 12000) -and ($tl.source.media_id -eq 'fixture-fused-001') -and ([string]$tl.source.source_media_sha256 -match '^[0-9a-f]{64}$'))
    Check 'identity_scope carried verbatim' ($tl.identity_scope -eq 'source_media+scene+tracker_invocation')
    Check 'coverage status sampled, 8 samples' (($tl.coverage.status -eq 'sampled') -and ($tl.coverage.sample_count -eq 8) -and (@($tl.coverage.samples).Count -eq 8))
    Check 'coverage presence semantics distinguishable' ($tl.coverage.presence_semantics -eq 'observed_vs_unsampled_distinguishable')
    Check 'coverage span 500..10500 => 10000' (($tl.coverage.span.first_sample_ms -eq 500) -and ($tl.coverage.span.last_sample_ms -eq 10500) -and ($tl.coverage.span.coverage_ms -eq 10000))
    Check 'coverage sample rows keep detection_count (s3 sampled-no-detection distinguishable)' ((@($tl.coverage.samples | Where-Object { $_.sample_index -eq 3 })[0].detection_count) -eq 0)
    Check 'coverage samples_source manifest' ($tl.coverage.samples_source -eq 'manifest')

    # scenes normalized (seconds -> ms, round-half-up: 11.6667 s -> 11667 ms)
    Check 'scenes normalized to integer ms' ((@($tl.scenes).Count -eq 2) -and ($tl.scenes[0].scene_index -eq 0) -and ($tl.scenes[0].start_ms -eq 500) -and ($tl.scenes[0].end_ms -eq 6000) -and ($tl.scenes[1].start_ms -eq 6000) -and ($tl.scenes[1].end_ms -eq 11667))

    # intervals: appearance segmentation
    $iv = @($tl.intervals)
    Check 'intervals: 6 total = 5 presence + 1 gap' (($iv.Count -eq 6) -and ($tl.summary.interval_counts.track_presence -eq 5) -and ($tl.summary.interval_counts.track_gap -eq 1))
    Check 'track0 split at the recorded gap (NEVER merged)' (($iv[0].kind -eq 'track_presence') -and ($iv[0].track_id -eq 0) -and ($iv[0].start_ms -eq 500) -and ($iv[0].end_ms -eq 2500) -and ($iv[0].observation_count -eq 3))
    Check 'track0 gap interval first-class' (($iv[1].kind -eq 'track_gap') -and ($iv[1].track_id -eq 0) -and ($iv[1].start_ms -eq 2500) -and ($iv[1].end_ms -eq 4500) -and ($iv[1].elapsed_ms -eq 2000) -and ($iv[1].missed_samples -eq 1) -and ($iv[1].reacquired_by -eq 'centroid'))
    Check 'track0 reacquired span separate' (($iv[2].kind -eq 'track_presence') -and ($iv[2].track_id -eq 0) -and ($iv[2].start_ms -eq 4500) -and ($iv[2].end_ms -eq 4500) -and ($iv[2].observation_count -eq 1))
    Check 'no presence interval spans the gap (false continuity guard)' (@($iv | Where-Object { $_.kind -eq 'track_presence' -and $_.track_id -eq 0 -and $_.start_ms -le 2500 -and $_.end_ms -ge 4500 }).Count -eq 0)
    Check 'tracks 1/2/3 single spans' (($iv[3].track_id -eq 1) -and ($iv[3].start_ms -eq 1500) -and ($iv[3].end_ms -eq 2500) -and ($iv[4].track_id -eq 2) -and ($iv[4].start_ms -eq 6500) -and ($iv[4].end_ms -eq 10500) -and ($iv[5].track_id -eq 3) -and ($iv[5].observation_count -eq 1))
    Check 'presence carries class + scene_index' (($iv[0].class -eq 'person') -and ($iv[0].scene_index -eq 0) -and ($iv[4].class -eq 'person') -and ($iv[4].scene_index -eq 1))

    # separated detection vs association evidence (quantized integer millionths)
    $e0 = $iv[0].evidence
    Check 'evidence.detection q-summaries (mean 880000, min 850000, max 910000)' (($e0.detection.mean_detection_score_q -eq 880000) -and ($e0.detection.min_detection_score_q -eq 850000) -and ($e0.detection.max_detection_score_q -eq 910000) -and ($e0.detection.low_confidence_count -eq 0))
    Check 'evidence.association segment 1 (2 iou links, weakest 550000, max_gap 1000)' (($e0.association.iou_link_count -eq 2) -and ($e0.association.centroid_link_count -eq 0) -and ($e0.association.reacquisition_count -eq 0) -and ($e0.association.weakest_link_quality_q -eq 550000) -and ($e0.association.maximum_gap_ms -eq 1000))
    $e2 = $iv[2].evidence
    Check 'evidence segment 2 (centroid reacquisition, low_confidence counted)' (($e2.association.centroid_link_count -eq 1) -and ($e2.association.reacquisition_count -eq 1) -and ($e2.association.weakest_link_quality_q -eq 0) -and ($e2.association.maximum_gap_ms -eq 2000) -and ($e2.detection.low_confidence_count -eq 1) -and ($e2.detection.mean_detection_score_q -eq 440000))
    $e5 = $iv[5].evidence
    Check 'evidence birth-only span (no links -> null weakest/max_gap)' (($e5.association.iou_link_count -eq 0) -and ($e5.association.centroid_link_count -eq 0) -and ($null -eq $e5.association.weakest_link_quality_q) -and ($null -eq $e5.association.maximum_gap_ms))

    # events: kinds, content, canonical (start_ms, kind, content) ordering
    $evs = @($tl.events)
    Check 'events: 10 total (2 speech + 2 ocr + 4 detection_sample + 2 scene_cut)' (($evs.Count -eq 10) -and ($tl.summary.event_counts.speech -eq 2) -and ($tl.summary.event_counts.ocr_text -eq 2) -and ($tl.summary.event_counts.detection_sample -eq 4) -and ($tl.summary.event_counts.scene_cut -eq 2))
    $kindSeq = @($evs | ForEach-Object { [string]$_.kind }) -join ','
    Check 'events sorted (t, kind, content)' ($kindSeq -eq 'detection_sample,scene_cut,speech,detection_sample,ocr_text,detection_sample,scene_cut,speech,ocr_text,detection_sample')
    $tSeq = @($evs | ForEach-Object { if (Has $_ 'timestamp_ms') { [long]$_.timestamp_ms } else { [long]$_.start_ms } })
    $sortedOk = $true
    for ($i = 1; $i -lt $tSeq.Count; $i++) { if ($tSeq[$i] -lt $tSeq[$i - 1]) { $sortedOk = $false } }
    Check 'events non-decreasing in time' $sortedOk
    Check 'speech event shape' (($evs[2].kind -eq 'speech') -and ($evs[2].start_ms -eq 600) -and ($evs[2].end_ms -eq 2400) -and ($evs[2].text -eq 'hello from scene one'))
    Check 'ocr_text joined lines + line_count' (($evs[4].kind -eq 'ocr_text') -and ($evs[4].timestamp_ms -eq 2500) -and ($evs[4].line_count -eq 2) -and ($evs[4].text -eq "EXIT`nSTAGE LEFT"))
    Check 'ocr frame_index mapped through samples (frame 255 -> 8500 ms)' (($evs[8].kind -eq 'ocr_text') -and ($evs[8].timestamp_ms -eq 8500) -and ($evs[8].text -eq 'SCENE TWO SIGN'))
    Check 'detection_sample class_counts' (($evs[3].kind -eq 'detection_sample') -and ($evs[3].timestamp_ms -eq 1500) -and ($evs[3].class_counts.person -eq 1) -and ($evs[3].class_counts.car -eq 1))
    Check 'detection_sample empty counts at sampled-no-detection instant' (($evs[5].kind -eq 'detection_sample') -and ($evs[5].timestamp_ms -eq 3500) -and (@($evs[5].class_counts.PSObject.Properties).Count -eq 0))
    Check 'scene_cut events at scene starts' (($evs[1].kind -eq 'scene_cut') -and ($evs[1].timestamp_ms -eq 500) -and ($evs[6].kind -eq 'scene_cut') -and ($evs[6].timestamp_ms -eq 6000))

    # index refs
    Check 'index.by_track track 0 -> [0,1,2]' ((@($tl.index.by_track.'0'.intervals) -join ',') -eq '0,1,2')
    Check 'index.by_track tracks 1/2/3' (((@($tl.index.by_track.'1'.intervals) -join ',') -eq '3') -and ((@($tl.index.by_track.'2'.intervals) -join ',') -eq '4') -and ((@($tl.index.by_track.'3'.intervals) -join ',') -eq '5'))
    Check 'index.by_class person' (((@($tl.index.by_class.person.intervals) -join ',') -eq '0,2,4') -and ((@($tl.index.by_class.person.events) -join ',') -eq '0,3,9'))
    Check 'index.by_class car' (((@($tl.index.by_class.car.intervals) -join ',') -eq '3,5') -and ((@($tl.index.by_class.car.events) -join ',') -eq '3,9'))
    Check 'index.by_scene 0' (((@($tl.index.by_scene.'0'.intervals) -join ',') -eq '0,1,2,3') -and ((@($tl.index.by_scene.'0'.events) -join ',') -eq '0,1,2,3,4,5'))
    Check 'index.by_scene 1' (((@($tl.index.by_scene.'1'.intervals) -join ',') -eq '4,5') -and ((@($tl.index.by_scene.'1'.events) -join ',') -eq '6,7,8,9'))
    Check 'index.by_kind interval kinds' (((@($tl.index.by_kind.track_presence.intervals) -join ',') -eq '0,2,3,4,5') -and ((@($tl.index.by_kind.track_gap.intervals) -join ',') -eq '1'))
    Check 'index.by_kind event kinds' (((@($tl.index.by_kind.detection_sample.events) -join ',') -eq '0,3,5,9') -and ((@($tl.index.by_kind.scene_cut.events) -join ',') -eq '1,6') -and ((@($tl.index.by_kind.speech.events) -join ',') -eq '2,7') -and ((@($tl.index.by_kind.ocr_text.events) -join ',') -eq '4,8'))
    $allIvRefs = New-Object System.Collections.Generic.List[long]
    foreach ($k in @('track_presence', 'track_gap')) { foreach ($r in @($tl.index.by_kind.$k.intervals)) { $allIvRefs.Add([long]$r) } }
    $allEvRefs = New-Object System.Collections.Generic.List[long]
    foreach ($k in @('detection_sample', 'ocr_text', 'scene_cut', 'speech')) { foreach ($r in @($tl.index.by_kind.$k.events)) { $allEvRefs.Add([long]$r) } }
    Check 'index completeness: every interval + event indexed by kind exactly once' (($allIvRefs.Count -eq $iv.Count) -and ($allEvRefs.Count -eq $evs.Count))

    # summary
    Check 'summary counts' (($tl.summary.track_count -eq 4) -and ($tl.summary.span_count -eq 5) -and ($tl.summary.scene_count -eq 2) -and ($tl.summary.coverage_ms -eq 10000))
    Check 'summary class_track_counts {car:2, person:2}' (($tl.summary.class_track_counts.car -eq 2) -and ($tl.summary.class_track_counts.person -eq 2))

    # ================= determinism =================
    $d2 = (RunEntry @('-InputFile', (Join-Path $fxDirC 'fused.json'), '-ArtifactRoot', $artRoot, '-InvocationId', 'det-2')) | ConvertFrom-Json
    Check 'double-run byte-identity (timeline sha equal)' (($d2.result.timeline.sha256 -eq $f.result.timeline.sha256) -and -not [string]::IsNullOrWhiteSpace([string]$f.result.timeline.sha256))
    Check 'double-run inputs_digest identical' ($d2.inputs_digest -eq $f.inputs_digest)
    $sc2 = (RunEntry @('-InputFile', (Join-Path $fxDirC 'fused-scrambled.json'), '-ArtifactRoot', $artRoot, '-InvocationId', 'det-3')) | ConvertFrom-Json
    Check 'canonical ordering: scrambled twin -> identical bytes' ($sc2.result.timeline.sha256 -eq $f.result.timeline.sha256)
    Check 'canonical ordering: scrambled twin -> identical input_digest' ($sc2.inputs_digest -eq $f.inputs_digest)
    [Console]::Out.WriteLine("CANONICAL-HASH fused=$($f.result.timeline.sha256)")

    # ================= degradation modes =================
    # meta-only: a valid timeline; sections present but empty; coverage unknown
    $mo = (RunEntry @('-InputFile', (Join-Path $fxDirC 'meta-only.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'meta-only status ok' ($mo.status -eq 'ok')
    $mot = ReadTimeline $mo
    $motl = $mot.text | ConvertFrom-Json
    Check 'meta-only coverage unknown + downgraded semantics' (($motl.coverage.status -eq 'unknown') -and ($motl.coverage.presence_semantics -eq 'downgraded_no_sample_manifest') -and ($null -eq $motl.coverage.span))
    Check 'meta-only empty sections + zero summary' ((@($motl.intervals).Count -eq 0) -and (@($motl.events).Count -eq 0) -and (@($motl.scenes).Count -eq 0) -and ($motl.summary.track_count -eq 0) -and ($null -eq $motl.summary.coverage_ms))
    Check 'meta-only source carried' (($motl.source.frame_width -eq 320) -and ($motl.source.duration_ms -eq 5000) -and ($null -eq $motl.source.source_media_sha256))
    Check 'meta-only by_kind shape stable (all six kinds present, empty)' ((@($motl.index.by_kind.PSObject.Properties.Name).Count -eq 6) -and (@($motl.index.by_kind.track_presence.intervals).Count -eq 0))
    [Console]::Out.WriteLine("CANONICAL-HASH meta-only=$($mo.result.timeline.sha256)")

    # tracks without samples: coverage unknown + EXPLICITLY downgraded presence semantics (warning -> partial)
    $tn = (RunEntry @('-InputFile', (Join-Path $fxDirC 'tracks-nosamples.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'tracks-nosamples status partial (explicit downgrade warning)' (($tn.status -eq 'partial') -and (@($tn.warnings | Where-Object { $_ -match 'presence semantics downgraded' }).Count -eq 1))
    $tnt = ReadTimeline $tn
    $tntl = $tnt.text | ConvertFrom-Json
    Check 'tracks-nosamples coverage unknown, samples_source null' (($tntl.coverage.status -eq 'unknown') -and ($null -eq $tntl.coverage.samples_source) -and ($tntl.coverage.sample_count -eq 0))
    Check 'tracks-nosamples still splits at the recorded gap' ((@($tntl.intervals).Count -eq 3) -and ($tntl.intervals[0].kind -eq 'track_presence') -and ($tntl.intervals[1].kind -eq 'track_gap') -and ($tntl.intervals[1].start_ms -eq 1600) -and ($tntl.intervals[1].end_ms -eq 5200) -and ($tntl.intervals[2].kind -eq 'track_presence'))
    [Console]::Out.WriteLine("CANONICAL-HASH tracks-nosamples=$($tn.result.timeline.sha256)")

    # transcript-only
    $to = (RunEntry @('-InputFile', (Join-Path $fxDirC 'transcript-only.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'transcript-only ok, 3 speech events only' (($to.status -eq 'ok') -and ($to.result.summary.event_counts.speech -eq 3) -and ($to.result.summary.event_counts.ocr_text -eq 0) -and ($to.result.summary.track_count -eq 0))
    [Console]::Out.WriteLine("CANONICAL-HASH transcript-only=$($to.result.timeline.sha256)")

    # OCR keyed by frame_index WITH samples -> mapped
    $om = (RunEntry @('-InputFile', (Join-Path $fxDirC 'ocr-map.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'ocr-map ok' ($om.status -eq 'ok')
    $omt = ReadTimeline $om
    $omtl = $omt.text | ConvertFrom-Json
    $ocrEvs = @($omtl.events | Where-Object { $_.kind -eq 'ocr_text' })
    Check 'ocr-map frame_index -> sample timestamps (1000, 7000)' (($ocrEvs.Count -eq 2) -and ($ocrEvs[0].timestamp_ms -eq 1000) -and ($ocrEvs[1].timestamp_ms -eq 7000) -and ($ocrEvs[1].line_count -eq 2))
    [Console]::Out.WriteLine("CANONICAL-HASH ocr-map=$($om.result.timeline.sha256)")

    # OCR keyed by frame_index WITHOUT samples -> REFUSED (never invent timestamps)
    $orf = (RunEntry @('-InputFile', (Join-Path $fxDirC 'ocr-refuse.json'), '-ArtifactRoot', $artRoot))
    $orfEnv = Test-SkillResultEnvelope -Json $orf
    $or = $orf | ConvertFrom-Json
    Check 'ocr-refuse fail-closed error envelope (valid, exit 0)' (([bool]$orfEnv.valid) -and ($script:code -eq 0) -and ($or.status -eq 'error') -and ($or.error.code -eq 'input_validation_failed'))
    Check 'ocr-refuse violation enumerated (path + why)' ((@(ViolationPaths $or) -like 'ocr`[0`]*').Count -eq 1 -and ([string]@($or.result.violations)[0].why -match 'never invented'))
    Check 'ocr-refuse writes NO timeline' ($null -eq (TimelineArtifact $or))

    # embedded samples fall back from the track file
    $te = (RunEntry @('-InputFile', (Join-Path $fxDirC 'tracks-embedded-samples.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'tracks-embedded-samples ok, coverage from tracks file' (($te.status -eq 'ok') -and ($te.result.coverage_status -eq 'sampled'))
    $tet = ReadTimeline $te
    $tetl = $tet.text | ConvertFrom-Json
    Check 'embedded samples_source tracks + distinguishable semantics' (($tetl.coverage.samples_source -eq 'tracks') -and ($tetl.coverage.presence_semantics -eq 'observed_vs_unsampled_distinguishable') -and ($tetl.coverage.sample_count -eq 3))

    # ================= adversarial fixtures =================
    # overlapping/out-of-order scenes: canonical order + surfaced overlap warning (tolerated, never repaired)
    $as = (RunEntry @('-InputFile', (Join-Path $fxDirC 'adversarial-scenes.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'adversarial scenes partial + overlap warning' (($as.status -eq 'partial') -and (@($as.warnings | Where-Object { $_ -match 'overlap' }).Count -eq 1))
    $ast = ReadTimeline $as
    $astl = $ast.text | ConvertFrom-Json
    Check 'adversarial scenes canonically ordered by index' (($astl.scenes[0].scene_index -eq 0) -and ($astl.scenes[0].start_ms -eq 0) -and ($astl.scenes[1].scene_index -eq 1) -and ($astl.scenes[1].start_ms -eq 3000))

    # gap-heavy track: N gaps -> N gap intervals + N+1 presence spans; strict alternation; never merged
    $gh = (RunEntry @('-InputFile', (Join-Path $fxDirC 'gap-heavy.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'gap-heavy ok' ($gh.status -eq 'ok')
    $ght = ReadTimeline $gh
    $ghtl = $ght.text | ConvertFrom-Json
    $ghiv = @($ghtl.intervals)
    Check 'gap-heavy 4 presence + 3 gaps' (($ghiv.Count -eq 7) -and ($ghtl.summary.interval_counts.track_presence -eq 4) -and ($ghtl.summary.interval_counts.track_gap -eq 3))
    $ghSeq = @($ghiv | ForEach-Object { [string]$_.kind }) -join ','
    Check 'gap-heavy strict alternation presence/gap' ($ghSeq -eq 'track_presence,track_gap,track_presence,track_gap,track_presence,track_gap,track_presence')
    Check 'gap-heavy final span [7000,8000] with iou reacquisition' (($ghiv[6].start_ms -eq 7000) -and ($ghiv[6].end_ms -eq 8000) -and ($ghiv[6].evidence.association.reacquisition_count -eq 1) -and ($ghiv[6].evidence.association.iou_link_count -eq 2) -and ($ghiv[6].evidence.association.weakest_link_quality_q -eq 350000))
    Check 'gap-heavy by_track key 7' ((@($ghtl.index.by_track.'7'.intervals)).Count -eq 7)
    [Console]::Out.WriteLine("CANONICAL-HASH gap-heavy=$($gh.result.timeline.sha256)")

    # zero-observation track -> fail-closed refusal
    $zo = (RunEntry @('-InputFile', (Join-Path $fxDirC 'zero-observation.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'zero-observation refused' (($zo.status -eq 'error') -and ($zo.error.code -eq 'input_validation_failed') -and ((@(ViolationPaths $zo) -like 'tracks.tracks`[0`].observations*').Count -ge 1))

    # observation at a sample not listed in the manifest -> fail-closed refusal
    $ul = (RunEntry @('-InputFile', (Join-Path $fxDirC 'unlisted-sample.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'unlisted-sample refused (manifest is authoritative)' (($ul.status -eq 'error') -and (@(@($ul.result.violations) | Where-Object { [string]$_.why -match 'not listed in the sample manifest' }).Count -ge 1))

    # empty-everything-but-meta: present-but-empty sections are valid
    $es = (RunEntry @('-InputFile', (Join-Path $fxDirC 'empty-sections.json'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'empty-sections ok (present-but-empty is valid)' (($es.status -eq 'ok') -and ($es.result.summary.track_count -eq 0) -and ($es.result.summary.scene_count -eq 0))
    $est = ReadTimeline $es
    $estl = $est.text | ConvertFrom-Json
    Check 'empty-sections coverage sampled-with-zero (distinct from unknown)' (($estl.coverage.status -eq 'sampled') -and ($estl.coverage.sample_count -eq 0) -and ($null -eq $estl.coverage.span))
    [Console]::Out.WriteLine("CANONICAL-HASH empty-sections=$($es.result.timeline.sha256)")

    # ================= strict validation refusals (targeted temp fixtures) =================
    function WriteTmp([string]$name, [string]$json) {
        $pth = Join-Path $tmpDir $name
        [System.IO.File]::WriteAllText($pth, $json, $utf8)
        return $pth
    }
    $e1 = (RunEntry @()) | ConvertFrom-Json
    Check 'no_input error' (($e1.status -eq 'error') -and ($e1.error.code -eq 'no_input') -and ($script:code -eq 0))
    $e2 = (RunEntry @('-InputFile', (Join-Path $tmpDir 'does-not-exist.json'))) | ConvertFrom-Json
    Check 'input_not_found error' (($e2.status -eq 'error') -and ($e2.error.code -eq 'input_not_found'))
    $e3 = (RunEntry @('-InputFile', (WriteTmp 'bad.json' '{ not json '))) | ConvertFrom-Json
    Check 'input_parse_failed error' (($e3.status -eq 'error') -and ($e3.error.code -eq 'input_parse_failed'))
    $e4 = (RunEntry @('-InputFile', (WriteTmp 'arr.json' '[1,2,3]'))) | ConvertFrom-Json
    Check 'invalid_input_shape (manifest must be an object)' (($e4.status -eq 'error') -and ($e4.error.code -eq 'invalid_input_shape'))
    $e5 = (RunEntry @('-InputFile', (WriteTmp 'nomedia.json' '{"scenes":[]}'))) | ConvertFrom-Json
    Check 'missing media violation' (($e5.status -eq 'error') -and ($e5.error.code -eq 'input_validation_failed') -and ((@(ViolationPaths $e5) -contains 'media')))
    $e6 = (RunEntry @('-InputFile', (WriteTmp 'nometa.json' '{"media":{"id":"x"}}'))) | ConvertFrom-Json
    Check 'missing media.meta violation' (($e6.status -eq 'error') -and ((@(ViolationPaths $e6) -contains 'media.meta')))
    $e7 = (RunEntry @('-InputFile', (WriteTmp 'nodur.json' '{"media":{"meta":{"frame_width":10,"frame_height":10}}}'))) | ConvertFrom-Json
    Check 'unresolvable duration violation' (($e7.status -eq 'error') -and (@(@($e7.result.violations) | Where-Object { [string]$_.why -match 'duration' }).Count -ge 1))
    $e8 = (RunEntry @('-InputFile', (WriteTmp 'badseg.json' '{"media":{"meta":{"duration_ms":1000}},"transcript":{"segments":[{"t0_ms":0,"t1_ms":10}]}}'))) | ConvertFrom-Json
    Check 'transcript segment missing text violation' (($e8.status -eq 'error') -and ((@(ViolationPaths $e8) -like 'transcript.segments`[0`]*').Count -ge 1))
    $e9 = (RunEntry @('-InputFile', (WriteTmp 'badseg2.json' '{"media":{"meta":{"duration_ms":1000}},"transcript":[{"t0_ms":500,"t1_ms":100,"text":"backwards"}]}'))) | ConvertFrom-Json
    Check 'transcript end-before-start violation' (($e9.status -eq 'error') -and (@(@($e9.result.violations) | Where-Object { [string]$_.why -match 'precede' }).Count -ge 1))
    $e10 = (RunEntry @('-InputFile', (WriteTmp 'baddet.json' '{"media":{"meta":{"duration_ms":1000}},"detections":[{"detections":[{"class":"cat","box":{"x":0,"y":0,"width":5,"height":5}}]}]}'))) | ConvertFrom-Json
    Check 'detections entry missing timestamp_ms violation' (($e10.status -eq 'error') -and ((@(ViolationPaths $e10) -like 'detections`[0`].timestamp_ms').Count -eq 1))
    $e11 = (RunEntry @('-InputFile', (WriteTmp 'badbox.json' '{"media":{"meta":{"duration_ms":1000}},"detections":[{"timestamp_ms":10,"detections":[{"class":"cat","box":{"x":0,"y":0,"width":5}}]}]}'))) | ConvertFrom-Json
    Check 'detection box missing height violation' (($e11.status -eq 'error') -and ((@(ViolationPaths $e11) -like '*box.height').Count -eq 1))
    $e12 = (RunEntry @('-InputFile', (WriteTmp 'dupsample.json' '{"media":{"meta":{"duration_ms":1000}},"samples":[{"sample_index":0,"frame_index":0,"timestamp_ms":0},{"sample_index":0,"frame_index":10,"timestamp_ms":100}]}'))) | ConvertFrom-Json
    Check 'duplicate sample_index violation' (($e12.status -eq 'error') -and (@(@($e12.result.violations) | Where-Object { [string]$_.why -match 'duplicate sample_index' }).Count -eq 1))
    $e13 = (RunEntry @('-InputFile', (WriteTmp 'duptrack.json' '{"media":{"meta":{"duration_ms":1000}},"tracks":{"schema":"s","timestamp_unit":"ms","tracks":[{"track_id":1,"class":"a","observations":[{"sample_index":0,"timestamp_ms":0}]},{"track_id":1,"class":"b","observations":[{"sample_index":1,"timestamp_ms":10}]}]}}'))) | ConvertFrom-Json
    Check 'duplicate track_id violation' (($e13.status -eq 'error') -and (@(@($e13.result.violations) | Where-Object { [string]$_.why -match 'duplicate track_id' }).Count -eq 1))
    $e14 = (RunEntry @('-InputFile', (WriteTmp 'badunit.json' '{"media":{"meta":{"duration_ms":1000}},"tracks":{"schema":"s","timestamp_unit":"frames","tracks":[]}}'))) | ConvertFrom-Json
    Check 'non-ms timestamp_unit violation' (($e14.status -eq 'error') -and ((@(ViolationPaths $e14) -contains 'tracks.timestamp_unit')))
    $e15 = (RunEntry @('-InputFile', (WriteTmp 'badgap.json' '{"media":{"meta":{"duration_ms":9000}},"tracks":{"schema":"s","tracks":[{"track_id":0,"class":"a","observations":[{"sample_index":0,"timestamp_ms":0},{"sample_index":1,"timestamp_ms":1000}],"gaps":[{"after_sample_index":5,"before_sample_index":9,"start_ms":4000,"end_ms":8000}]}]}}'))) | ConvertFrom-Json
    Check 'unalignable gap violation' (($e15.status -eq 'error') -and (@(@($e15.result.violations) | Where-Object { [string]$_.why -match 'consecutive observations' }).Count -ge 1))
    $e16 = (RunEntry @('-InputsJson', 'not json')) | ConvertFrom-Json
    Check 'invalid_inputs_json error' (($e16.status -eq 'error') -and ($e16.error.code -eq 'invalid_inputs_json'))
    $e17 = (RunEntry @('-InputFile', (WriteTmp 'trackpath.json' '{"media":{"meta":{"duration_ms":1000}},"tracks":"no-such-tracks.json"}'))) | ConvertFrom-Json
    Check 'track file path not found violation' (($e17.status -eq 'error') -and (@(@($e17.result.violations) | Where-Object { [string]$_.why -match 'not found' }).Count -eq 1))
    $e18 = (RunEntry @('-InputFile', (WriteTmp 'tsmismatch.json' '{"media":{"meta":{"duration_ms":9000}},"samples":[{"sample_index":0,"frame_index":0,"timestamp_ms":0}],"tracks":{"schema":"s","tracks":[{"track_id":0,"class":"a","observations":[{"sample_index":0,"timestamp_ms":777}]}]}}'))) | ConvertFrom-Json
    Check 'observation timestamp disagrees with manifest violation' (($e18.status -eq 'error') -and (@(@($e18.result.violations) | Where-Object { [string]$_.why -match 'disagrees' }).Count -eq 1))
    $e19 = (RunEntry @('-InputFile', (WriteTmp 'fracms.json' '{"media":{"meta":{"duration_ms":1000}},"transcript":[{"t0_ms":10.5,"t1_ms":20,"text":"frac"}]}'))) | ConvertFrom-Json
    Check 'fractional ms violation (integer ms everywhere)' (($e19.status -eq 'error') -and (@(@($e19.result.violations) | Where-Object { [string]$_.why -match 'integer' }).Count -ge 1))

    # ================= inline manifests =================
    $inline1 = '{"media":{"id":"inline-1","meta":{"frame_width":100,"frame_height":50,"duration_ms":2000}}}'
    $il1 = (RunEntry @('-InputsJson', $inline1, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'InputsJson-as-manifest (media key) ok' (($il1.status -eq 'ok') -and ($il1.result.input.source -eq 'inline') -and ($il1.result.summary.track_count -eq 0))
    $il2 = (RunEntry @('-InputsJson', ('{"manifest":' + $inline1 + '}'), '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'InputsJson.manifest ok + identical bytes to the media-key form' (($il2.status -eq 'ok') -and ($il2.result.timeline.sha256 -eq $il1.result.timeline.sha256))

    # ================= Module 1 wrapper =================
    $wjson = ([ordered]@{ input = (Join-Path $fxDirC 'fused.json') } | ConvertTo-Json -Compress)
    $rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson $wjson -PwshPath $PwshPath -ArtifactRoot $artRoot
    $repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
    Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
    Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)
    Check 'wrapper skill_id' ($repObj.skill_id -eq 'video.timeline')
    Check 'wrapper envelope fused summary' (([int]$repObj.envelope.result.summary.track_count -eq 4) -and ($repObj.envelope.result.timeline.sha256 -eq $f.result.timeline.sha256))
}
finally {
    try { if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
