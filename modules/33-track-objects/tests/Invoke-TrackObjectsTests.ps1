#requires -Version 7.0
<#
  Invoke-TrackObjectsTests.ps1 -- regression tests for track.objects (Module 33).

  DUAL-MODE + OS-portable (mirrors media.decompose's real-skill gate, NOT a mock): track.objects is PURE
  deterministic logic -- no CUDA, no model, no OS-specific API, no external binary -- so the SAME harness
  runs the REAL Invoke-TrackObjects.ps1 on the cloud Linux box (pre-ship gate) and on the Windows executor
  (-Live). Fixtures are generated at runtime by New-TrackFixture.ps1 (pure PowerShell) -- crossing paths,
  an occlusion-coast, a mid-sequence birth, an aged-out death (+ new-id rebirth), a per-class no-merge, an
  empty sequence, and a combined scenario -- plus the committed tests/fixtures/scenario.json. It exercises
  every lifecycle transition, determinism (byte-identical tracks across two runs), the param knobs
  (-IouThreshold / -MaxAge / -MinScore / -Classes), every error path, -InputsJson inline frames, an AST
  parse of the shipped .ps1 files, and the Module 1 wrapper.

  -PwshPath <pwsh>  : the interpreter used to invoke the skill + the generator. Passed through explicitly.
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
$genr    = Join-Path $moduleRoot 'New-TrackFixture.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$committedFixture = Join-Path $moduleRoot 'tests/fixtures/scenario.json'

$mode = if ($Live) { 'LIVE (on-device)' } else { 'cloud/real' }
[Console]::Out.WriteLine("== track.objects tests ($mode); pwsh=$PwshPath ==")

$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function Has($o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}
function Frames([object]$track) { return (@($track.frames) | ForEach-Object { [int]$_.frame }) -join ',' }
function TrackById([object]$env, [int]$id) { return (@($env.result.tracks) | Where-Object { [int]$_.track_id -eq $id } | Select-Object -First 1) }

# ---- AST parse of shipped .ps1 (fail closed on a syntax error) ----
foreach ($f in @($entry, $genr)) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Check "AST parses: $(Split-Path -Leaf $f)" (($null -eq $errs) -or (@($errs).Count -eq 0))
}

# ---- manifest ----
$mf = Join-Path $moduleRoot 'skill.json'
$mv = Test-SkillManifest -Path $mf
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$manifest = (Get-Content -LiteralPath $mf -Raw) | ConvertFrom-Json
Check 'manifest skill_id track.objects' ($manifest.skill_id -eq 'track.objects')
Check 'manifest parallel_safe true' ($manifest.parallel_safe -eq $true)
Check 'manifest deterministic' ($manifest.determinism -eq 'deterministic')
Check 'manifest gpu none' ($manifest.requirements.gpu -eq 'none')
Check 'manifest models empty' (@($manifest.requirements.models).Count -eq 0)
Check 'manifest network false' ($manifest.requirements.network -eq $false)

# ---- fixtures ----
$token = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$fxDir = Join-Path ([System.IO.Path]::GetTempPath()) "lo-track-fx-$token"
$artRoot = Join-Path $fxDir 'art'
try {
    $genTxt = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $genr -OutputDir $fxDir
    $genObj = ([string]($genTxt | Out-String)).Trim() | ConvertFrom-Json
    Check 'fixture generator ok' ($genObj.ok -eq $true)
    $fx = $genObj.fixtures
    foreach ($n in @('scenario', 'crossing', 'occlusion', 'birth', 'death', 'multiclass', 'empty')) {
        Check "fixture $n created" ((Has $fx $n) -and (Test-Path -LiteralPath $fx.$n))
    }

    # ================= combined scenario: every lifecycle case =================
    $sTxt = RunEntry @('-InputFile', $fx.scenario, '-ArtifactRoot', $artRoot)
    Check 'scenario exit 0' ($script:code -eq 0)
    $ev = Test-SkillResultEnvelope -Json $sTxt
    Check 'scenario envelope validates' ([bool]$ev.valid)
    if (-not $ev.valid) { $ev.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
    $s = $sTxt | ConvertFrom-Json
    Check 'scenario status ok' ($s.status -eq 'ok')
    Check 'scenario contract 0.2' ($s.contract_version -eq '0.2')
    Check 'scenario confidence null (deterministic)' ($null -eq $s.confidence)
    Check 'scenario model_provenance empty' (@($s.model_provenance).Count -eq 0)
    Check 'scenario 6 frames' ([int]$s.result.summary.input_frames -eq 6)
    Check 'scenario 19 detections' ([int]$s.result.summary.input_detections -eq 19)
    Check 'scenario 4 tracks' ([int]$s.result.summary.track_count -eq 4)
    Check 'scenario 4 births' ([int]$s.result.summary.births -eq 4)
    Check 'scenario 1 death' ([int]$s.result.summary.deaths -eq 1)
    Check 'scenario class_summary car=2' ([int]$s.result.summary.class_summary.car -eq 2)
    Check 'scenario class_summary person=2' ([int]$s.result.summary.class_summary.person -eq 2)
    Check 'scenario max_concurrent 4' ([int]$s.result.summary.max_concurrent_tracks -eq 4)
    # tracks ordered by track_id ascending
    $ids = @($s.result.tracks | ForEach-Object { [int]$_.track_id })
    Check 'scenario tracks ordered by id' (($ids -join ',') -eq '0,1,2,3')
    # crossing: the two cars each span all 6 frames
    $t0 = TrackById $s 0; $t1 = TrackById $s 1
    Check 'scenario track0 car full length 6' ($t0.class -eq 'car' -and [int]$t0.length -eq 6 -and (Frames $t0) -eq '0,1,2,3,4,5')
    Check 'scenario track1 car full length 6' ($t1.class -eq 'car' -and [int]$t1.length -eq 6)
    # occlusion-coast: person revived across the frame-2 gap -> frames 0,1,3,4,5
    $t2 = TrackById $s 2
    Check 'scenario track2 person occlusion-coast' ($t2.class -eq 'person' -and (Frames $t2) -eq '0,1,3,4,5' -and [int]$t2.length -eq 5)
    Check 'scenario track2 not aged out' ($t2.aged_out -eq $false)
    # birth mid-sequence + death (aged out): person P2 present only frames 1,2 then aged out
    $t3 = TrackById $s 3
    Check 'scenario track3 person birth mid-sequence' ($t3.class -eq 'person' -and [int]$t3.first_frame -eq 1)
    Check 'scenario track3 aged out (death)' ($t3.aged_out -eq $true -and (Frames $t3) -eq '1,2' -and [int]$t3.last_frame -eq 2)
    # box passthrough preserves integer coords + field order; timestamps carried
    $b0 = @($t0.frames)[0].box
    Check 'scenario box passthrough {x,y,width,height}' ((Has $b0 'x') -and (Has $b0 'width') -and ([int]$b0.width -eq 40))
    Check 'scenario timestamp carried' ($null -ne @($t0.frames)[1].timestamp_s -and [double](@($t0.frames)[1].timestamp_s) -eq 0.5)
    # a tracks.json artifact is present
    Check 'scenario tracks.json artifact present' (@($s.artifacts | Where-Object { $_.path -match 'tracks\.json$' }).Count -eq 1)
    Check 'scenario tracks.md artifact present' (@($s.artifacts | Where-Object { $_.path -match 'tracks\.md$' }).Count -eq 1)

    # ================= targeted fixtures =================
    # crossing: two same-class objects, paths cross, identities stay separate -> 2 full tracks
    $cr = (RunEntry @('-InputFile', $fx.crossing, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'crossing 2 tracks both len 6' ([int]$cr.result.summary.track_count -eq 2 -and (@($cr.result.tracks | Where-Object { [int]$_.length -eq 6 }).Count -eq 2))
    Check 'crossing 0 deaths' ([int]$cr.result.summary.deaths -eq 0)

    # occlusion: one track, revived across the 1-frame gap
    $oc = (RunEntry @('-InputFile', $fx.occlusion, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'occlusion 1 track' ([int]$oc.result.summary.track_count -eq 1)
    Check 'occlusion track frames skip gap' ((Frames (@($oc.result.tracks)[0])) -eq '0,1,3,4,5')

    # occlusion with MaxAge 0: no coasting -> the gap splits it into 2 tracks
    $oc0 = (RunEntry @('-InputFile', $fx.occlusion, '-MaxAge', '0', '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'occlusion MaxAge 0 splits into 2 tracks' ([int]$oc0.result.summary.track_count -eq 2)
    Check 'occlusion MaxAge 0 has a death' ([int]$oc0.result.summary.deaths -ge 1)

    # birth mid-sequence: a second track first appears at frame 3
    $bi = (RunEntry @('-InputFile', $fx.birth, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'birth 2 tracks' ([int]$bi.result.summary.track_count -eq 2)
    $biNew = @($bi.result.tracks | Where-Object { [int]$_.first_frame -eq 3 })
    Check 'birth new track starts at frame 3' ($biNew.Count -eq 1)

    # death + rebirth: gap > max_age(2) ages out the first track; reappearance is a NEW id
    $de = (RunEntry @('-InputFile', $fx.death, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'death 2 tracks (aged out -> new id)' ([int]$de.result.summary.track_count -eq 2)
    Check 'death 1 death counted' ([int]$de.result.summary.deaths -eq 1)
    Check 'death first track aged_out' ((@($de.result.tracks | Where-Object { $_.aged_out -eq $true }).Count) -eq 1)

    # multiclass: identical box, different class -> per-class must NOT merge
    $mc = (RunEntry @('-InputFile', $fx.multiclass, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'multiclass 2 tracks (no cross-class merge)' ([int]$mc.result.summary.track_count -eq 2)
    Check 'multiclass one car + one person' ((@($mc.result.tracks | Where-Object { $_.class -eq 'car' }).Count -eq 1) -and (@($mc.result.tracks | Where-Object { $_.class -eq 'person' }).Count -eq 1))

    # empty: zero detections -> zero tracks, status ok
    $em = (RunEntry @('-InputFile', $fx.empty, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'empty 0 tracks status ok' ($em.status -eq 'ok' -and [int]$em.result.summary.track_count -eq 0 -and [int]$em.result.summary.input_frames -eq 3)

    # ---- -Classes filter: only track 'person' in the scenario -> the two cars drop out ----
    $cf = (RunEntry @('-InputFile', $fx.scenario, '-Classes', 'person', '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'classes filter person -> 2 tracks' ([int]$cf.result.summary.track_count -eq 2 -and (@($cf.result.tracks | Where-Object { $_.class -ne 'person' }).Count -eq 0))

    # ---- -MinScore filter: drop the lowest-scored car (0.85) leaves fewer tracked detections ----
    $ms = (RunEntry @('-InputFile', $fx.scenario, '-MinScore', '0.88', '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'min_score filter drops low-score dets' ([int]$ms.result.summary.tracked_detections -lt 19)

    # ================= determinism: two runs -> byte-identical tracks.json (sha256) + result payload =================
    $d1 = (RunEntry @('-InputFile', $fx.scenario, '-ArtifactRoot', $artRoot, '-InvocationId', 'det-1')) | ConvertFrom-Json
    $d2 = (RunEntry @('-InputFile', $fx.scenario, '-ArtifactRoot', $artRoot, '-InvocationId', 'det-2')) | ConvertFrom-Json
    $sha1 = @($d1.artifacts | Where-Object { $_.path -match 'tracks\.json$' })[0].sha256
    $sha2 = @($d2.artifacts | Where-Object { $_.path -match 'tracks\.json$' })[0].sha256
    Check 'determinism tracks.json sha256 identical' ($sha1 -eq $sha2 -and -not [string]::IsNullOrWhiteSpace($sha1))
    $r1 = ($d1.result | ConvertTo-Json -Depth 20 -Compress)
    $r2 = ($d2.result | ConvertTo-Json -Depth 20 -Compress)
    Check 'determinism result payload identical' ($r1 -eq $r2)
    Check 'determinism inputs_digest identical' ($d1.inputs_digest -eq $d2.inputs_digest)

    # ================= committed fixture is valid + tracks the same scenario =================
    Check 'committed scenario fixture exists' (Test-Path -LiteralPath $committedFixture)
    $cm = (RunEntry @('-InputFile', $committedFixture, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'committed fixture 4 tracks 1 death' ([int]$cm.result.summary.track_count -eq 4 -and [int]$cm.result.summary.deaths -eq 1)

    # ================= -InputsJson inline frames (no file) =================
    $inline = [ordered]@{ frames = @(
            [ordered]@{ frame = 0; detections = @([ordered]@{ class = 'dog'; class_id = 16; score = 0.9; box = [ordered]@{ x = 10; y = 10; width = 40; height = 40 } }) },
            [ordered]@{ frame = 1; detections = @([ordered]@{ class = 'dog'; class_id = 16; score = 0.9; box = [ordered]@{ x = 20; y = 10; width = 40; height = 40 } }) }
        ) } | ConvertTo-Json -Depth 8 -Compress
    $il = (RunEntry @('-InputsJson', $inline, '-ArtifactRoot', $artRoot)) | ConvertFrom-Json
    Check 'inline frames 1 dog track len 2' ([int]$il.result.summary.track_count -eq 1 -and [int](@($il.result.tracks)[0].length) -eq 2 -and $il.result.input.source -eq 'inline')

    # ================= error paths (valid error envelope, exit 0) =================
    $e1 = (RunEntry @()) | ConvertFrom-Json
    Check 'no_input error' ($e1.status -eq 'error' -and $e1.error.code -eq 'no_input')
    Check 'no_input exit 0' ($script:code -eq 0)

    $e2Txt = RunEntry @('-InputFile', (Join-Path $fxDir 'does-not-exist.json'))
    $ev2 = Test-SkillResultEnvelope -Json $e2Txt
    $e2 = $e2Txt | ConvertFrom-Json
    Check 'input_not_found valid envelope' ([bool]$ev2.valid)
    Check 'input_not_found error' ($e2.status -eq 'error' -and $e2.error.code -eq 'input_not_found')

    $badJson = Join-Path $fxDir 'bad.json'; [System.IO.File]::WriteAllText($badJson, '{ not valid json ', ([System.Text.UTF8Encoding]::new($false)))
    $e3 = (RunEntry @('-InputFile', $badJson)) | ConvertFrom-Json
    Check 'input_parse_failed error' ($e3.status -eq 'error' -and $e3.error.code -eq 'input_parse_failed')

    $shape = Join-Path $fxDir 'shape.json'; [System.IO.File]::WriteAllText($shape, '{"unexpected":true}', ([System.Text.UTF8Encoding]::new($false)))
    $e4 = (RunEntry @('-InputFile', $shape)) | ConvertFrom-Json
    Check 'invalid_input_shape error' ($e4.status -eq 'error' -and $e4.error.code -eq 'invalid_input_shape')

    $baddet = Join-Path $fxDir 'baddet.json'; [System.IO.File]::WriteAllText($baddet, '{"frames":[{"frame":0,"detections":[{"class":"car"}]}]}', ([System.Text.UTF8Encoding]::new($false)))
    $e5 = (RunEntry @('-InputFile', $baddet)) | ConvertFrom-Json
    Check 'invalid_detection (missing box) error' ($e5.status -eq 'error' -and $e5.error.code -eq 'invalid_detection')

    $e6 = (RunEntry @('-InputFile', $fx.scenario, '-IouThreshold', '5')) | ConvertFrom-Json
    Check 'invalid_iou_threshold error' ($e6.status -eq 'error' -and $e6.error.code -eq 'invalid_iou_threshold')

    $e7 = (RunEntry @('-InputFile', $fx.scenario, '-MaxAge', '-1')) | ConvertFrom-Json
    Check 'invalid_max_age error' ($e7.status -eq 'error' -and $e7.error.code -eq 'invalid_max_age')

    $e8 = (RunEntry @('-InputsJson', 'not json')) | ConvertFrom-Json
    Check 'invalid_inputs_json error' ($e8.status -eq 'error' -and $e8.error.code -eq 'invalid_inputs_json')

    # ================= Module 1 wrapper =================
    $wjson = ([ordered]@{ input = $fx.scenario } | ConvertTo-Json -Compress)
    $rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson $wjson -PwshPath $PwshPath -ArtifactRoot $artRoot
    $repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
    Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
    Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)
    Check 'wrapper skill_id' ($repObj.skill_id -eq 'track.objects')
    Check 'wrapper envelope 4 tracks' ([int]$repObj.envelope.result.summary.track_count -eq 4)
}
finally {
    try { if (Test-Path -LiteralPath $fxDir) { Remove-Item -LiteralPath $fxDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
