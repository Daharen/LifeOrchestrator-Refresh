#requires -Version 7.0
<#
.SYNOPSIS
  track.objects -- associate per-frame object detections into stable identity tracks (Life Orchestrator,
  contract v0.2). The SECOND module of the Phase C video spine (architectural position 20), following
  media.decompose #32 (position 19).
.DESCRIPTION
  Given a sequence of PER-FRAME object detections in the detect.objects #16 output shape (each detection
  {class, class_id, score, box{x,y,width,height}}), it associates them across frames so the same object
  keeps ONE track_id. The association is a DETERMINISTIC, PURE frame-by-frame greedy IoU matcher:
    * per-frame, per-CLASS: match active tracks to the frame's detections by IoU (>= -IouThreshold);
    * resolve assignments DETERMINISTICALLY -- candidate pairs sorted by IoU descending, tie-broken by
      detection order then track_id (a total order -> no ambiguity, so the result is seedless-stable);
    * matched  -> extend the track (its box becomes the new last-known box);
    * unmatched detection -> BIRTH a new track (monotonic track_id, assigned in detection order);
    * unmatched track     -> COAST (a simple constant-position predictor keeps its last box) up to
      -MaxAge frames, then DEATH (it can no longer be revived; a later detection births a NEW id).
  No Kalman / constant-velocity motion model, no appearance/embedding re-ID (named follow-ons). No model,
  no CUDA, no loopback port, no randomness -> CPU-only, parallel_safe:true, and byte-identical for
  identical input. MVP is DECOUPLED from live detection: it reads detections from a JSON file (or inline
  via -InputsJson.frames), NOT from a live #16/#32 run (live composition is a named follow-on).

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; exits 0 whenever a valid
  envelope is produced. The tracks artifact (tracks.json) is intentionally free of volatile fields
  (invocation_id / timestamps live in the envelope) so it is byte-identical for identical input.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json
  pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -IouThreshold 0.4 -MaxAge 3
  pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputsJson '{"input":"detections.json","classes":["car"]}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [double]$IouThreshold = 0.3,
    [int]$MaxAge = 2,
    [double]$MinScore = 0.0,
    [string[]]$Classes,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'track.objects'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$TRACKS_SCHEMA = 'lifeorch.track.objects/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
$bound = $PSBoundParameters
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[track.objects] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { $v = $o.$n; if ($null -ne $v) { return $v } } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function ToDouble($v) { # invariant parse; $null when null/unparseable
    if ($null -eq $v) { return $null }
    if ($v -is [double]) { return [double]$v }
    if ($v -is [int] -or $v -is [long]) { return [double]$v }
    $d = 0.0
    if ([double]::TryParse([string]$v, [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { return $d }
    return $null
}
function New-SkillError([string]$code, [string]$message, [bool]$retryable = $false) {
    return [PSCustomObject]@{ code = $code; message = $message; retryable = $retryable }
}
# IoU of two boxes given as (x,y,w,h) top-left corner + size (the detect.objects #16 box shape).
function Get-Iou([double]$ax, [double]$ay, [double]$aw, [double]$ah, [double]$bx, [double]$by, [double]$bw, [double]$bh) {
    $ax2 = $ax + $aw; $ay2 = $ay + $ah; $bx2 = $bx + $bw; $by2 = $by + $bh
    $ix1 = [math]::Max($ax, $bx); $iy1 = [math]::Max($ay, $by)
    $ix2 = [math]::Min($ax2, $bx2); $iy2 = [math]::Min($ay2, $by2)
    $iw = $ix2 - $ix1; $ih = $iy2 - $iy1
    if ($iw -le 0 -or $ih -le 0) { return 0.0 }
    $inter = $iw * $ih
    $areaA = $aw * $ah; $areaB = $bw * $bh
    $union = $areaA + $areaB - $inter
    if ($union -le 0) { return 0.0 }
    return [double]($inter / $union)
}
# Raw frames array out of a parsed top-level document (file mode): a bare array of frames, {frames:[...]},
# {sequence:[...]}, or a single detect.objects result ({detections:[...]}) treated as one frame.
function Get-RawFrames($doc) {
    if ($null -eq $doc) { throw (New-SkillError 'invalid_input_shape' 'input document is null') }
    if ($doc -is [System.Array] -or $doc -is [System.Collections.IList]) { return @($doc) }
    if (Has $doc 'frames')     { return @($doc.frames) }
    if (Has $doc 'sequence')   { return @($doc.sequence) }
    if (Has $doc 'detections') { return @(, $doc) }
    throw (New-SkillError 'invalid_input_shape' 'input must be a frames array, {frames:[...]}, {sequence:[...]}, or a single {detections:[...]} object')
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$confidence = $null; $modelProvenance = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$producedFiles = New-Object System.Collections.Generic.List[object]  # {p;k}

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw (New-SkillError 'invalid_inputs_json' '-InputsJson is not valid JSON') }
    }
    $inlineFrames = $null
    if ($null -ne $p) {
        if ((Has $p 'input')          -and -not $bound.ContainsKey('InputFile'))     { $InputFile = [string]$p.input }
        if ((Has $p 'iou_threshold')  -and -not $bound.ContainsKey('IouThreshold'))  { $IouThreshold = [double]$p.iou_threshold }
        if ((Has $p 'max_age')        -and -not $bound.ContainsKey('MaxAge'))        { $MaxAge = [int]$p.max_age }
        if ((Has $p 'min_score')      -and -not $bound.ContainsKey('MinScore'))      { $MinScore = [double]$p.min_score }
        if ((Has $p 'classes')        -and -not $bound.ContainsKey('Classes'))       { $Classes = @($p.classes | ForEach-Object { [string]$_ }) }
        if (Has $p 'frames') { $inlineFrames = @($p.frames) }
    }

    # ---- normalize the class filter (StrictMode-safe: never touch a $null [string[]]) ----
    $classFilter = @()
    if ($null -ne $Classes) { $classFilter = @($Classes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ }) }

    # ---- validate scalar params ----
    if ($IouThreshold -lt 0 -or $IouThreshold -gt 1) {
        throw (New-SkillError 'invalid_iou_threshold' "iou_threshold must be within 0..1; got $IouThreshold")
    }
    if ($MaxAge -lt 0) {
        throw (New-SkillError 'invalid_max_age' "max_age must be >= 0; got $MaxAge")
    }
    if ($MinScore -lt 0) {
        throw (New-SkillError 'invalid_min_score' "min_score must be >= 0; got $MinScore")
    }

    # ---- resolve the raw frames (file wins over inline) ----
    $source = $null; $inFull = $null; $rawFrames = $null
    if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
        if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
            throw (New-SkillError 'input_not_found' "input file not found: $InputFile")
        }
        $inFull = (Resolve-Path -LiteralPath $InputFile).Path
        $raw = Get-Content -LiteralPath $inFull -Raw
        $doc = $null
        try { $doc = $raw | ConvertFrom-Json } catch { throw (New-SkillError 'input_parse_failed' "input JSON did not parse: $($_.Exception.Message)") }
        $rawFrames = Get-RawFrames $doc
        $source = 'file'
    }
    elseif ($null -ne $inlineFrames) {
        $rawFrames = @($inlineFrames)
        $source = 'inline'
    }
    else {
        throw (New-SkillError 'no_input' 'no input: provide -InputFile, InputsJson.input, or inline InputsJson.frames')
    }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- normalize frames + detections into a chronological, deterministic list ----
    # normFrame = { frame:int; timestamp_s:double|null; dets:@( { class; class_id; score; scoreRaw; x;y;w;h; boxOut; det_index } ) }
    $normList = New-Object System.Collections.Generic.List[object]
    $rawInputDetections = 0
    for ($pos = 0; $pos -lt @($rawFrames).Count; $pos++) {
        $fe = @($rawFrames)[$pos]
        $fi = $pos; $ts = $null; $rawDets = @()
        if ($fe -is [System.Array] -or $fe -is [System.Collections.IList]) {
            $rawDets = @($fe)
        }
        elseif (Has $fe 'detections') {
            $rawDets = @($fe.detections)
            $fiV = $null
            if (Has $fe 'frame') { $fiV = $fe.frame } elseif (Has $fe 'index') { $fiV = $fe.index } elseif (Has $fe 'frame_index') { $fiV = $fe.frame_index }
            if ($null -ne $fiV) { $fi = [int]$fiV }
            $tsV = $null
            if (Has $fe 'timestamp_s') { $tsV = $fe.timestamp_s } elseif (Has $fe 'timestamp') { $tsV = $fe.timestamp }
            $ts = ToDouble $tsV
        }
        else {
            throw (New-SkillError 'invalid_frame' "frame at position ${pos} must be a detections array or an object with a 'detections' field")
        }

        $keptDets = New-Object System.Collections.Generic.List[object]
        for ($di = 0; $di -lt @($rawDets).Count; $di++) {
            $de = @($rawDets)[$di]
            $rawInputDetections++
            $cls = ''
            if (Has $de 'class') { $cls = [string]$de.class }
            if ([string]::IsNullOrWhiteSpace($cls)) {
                throw (New-SkillError 'invalid_detection' "frame ${fi} detection ${di} is missing a 'class'")
            }
            $box = $null
            if (Has $de 'box') { $box = $de.box }
            if ($null -eq $box) {
                throw (New-SkillError 'invalid_detection' "frame ${fi} detection ${di} (class '$cls') is missing a 'box'")
            }
            $bx = ToDouble (Prop $box 'x'); $by = ToDouble (Prop $box 'y')
            $bw = ToDouble (Prop $box 'width'); $bh = ToDouble (Prop $box 'height')
            if ($null -eq $bx -or $null -eq $by -or $null -eq $bw -or $null -eq $bh) {
                throw (New-SkillError 'invalid_detection' "frame ${fi} detection ${di} (class '$cls') has a non-numeric or incomplete box (need x,y,width,height)")
            }
            if ($bw -le 0 -or $bh -le 0) { $warnings.Add("frame ${fi} detection ${di} (class '$cls') has a degenerate box (width/height <= 0); it cannot match by IoU") }

            $scoreRaw = if (Has $de 'score') { $de.score } else { $null }
            $score = ToDouble $scoreRaw
            $cid = if (Has $de 'class_id') { $de.class_id } else { $null }

            # class filter
            if ($classFilter.Count -gt 0 -and ($classFilter -notcontains $cls)) { continue }
            # min-score filter (only drop when a score is present and below the floor)
            if ($MinScore -gt 0 -and $null -ne $score -and $score -lt $MinScore) { continue }

            $boxOut = [ordered]@{ x = (Prop $box 'x'); y = (Prop $box 'y'); width = (Prop $box 'width'); height = (Prop $box 'height') }
            $keptDets.Add([pscustomobject]@{
                class = $cls; class_id = $cid; score = $score; score_raw = $scoreRaw
                x = [double]$bx; y = [double]$by; w = [double]$bw; h = [double]$bh
                box_out = $boxOut; det_index = $di
            })
        }
        $normList.Add([pscustomobject]@{ frame = [int]$fi; timestamp_s = $ts; dets = $keptDets.ToArray(); pos = $pos })
    }

    # chronological order: (frame asc, original position asc) -- a total order, so it is stable + deterministic.
    $normFrames = $normList.ToArray()
    [System.Array]::Sort($normFrames, [System.Comparison[object]] {
        param($a, $b)
        if ($a.frame -ne $b.frame) { return ([int]$a.frame).CompareTo([int]$b.frame) }
        return ([int]$a.pos).CompareTo([int]$b.pos)
    })

    # ================= the deterministic greedy IoU tracker =================
    $allTracks = New-Object System.Collections.Generic.List[object]     # every track ever created, in id order
    $activeTracks = New-Object System.Collections.Generic.List[object]  # currently matchable (matched + coasting)
    $nextId = 0
    $trackedDetections = 0
    $births = 0; $deaths = 0; $coastFrames = 0
    $maxConcurrent = 0

    foreach ($nf in $normFrames) {
        $frameIdx = [int]$nf.frame
        $ts = $nf.timestamp_s
        $dets = @($nf.dets)
        $trackedDetections += $dets.Count

        # ---- build candidate (track,detection) pairs of the SAME class with IoU >= threshold ----
        $cands = New-Object System.Collections.Generic.List[object]
        for ($ti = 0; $ti -lt $activeTracks.Count; $ti++) {
            $t = $activeTracks[$ti]
            for ($di = 0; $di -lt $dets.Count; $di++) {
                $d = $dets[$di]
                if ([string]$t.class -cne [string]$d.class) { continue }
                $iou = Get-Iou $t.last_x $t.last_y $t.last_w $t.last_h $d.x $d.y $d.w $d.h
                if ($iou -ge $IouThreshold) {
                    $cands.Add([pscustomobject]@{ ti = $ti; di = $di; det_index = [int]$d.det_index; tid = [int]$t.track_id; iou = [double]$iou })
                }
            }
        }
        # deterministic total order: IoU desc, then detection order asc, then track_id asc.
        $candArr = $cands.ToArray()
        [System.Array]::Sort($candArr, [System.Comparison[object]] {
            param($a, $b)
            if ($a.iou -gt $b.iou) { return -1 }
            if ($a.iou -lt $b.iou) { return 1 }
            if ($a.det_index -ne $b.det_index) { return ([int]$a.det_index).CompareTo([int]$b.det_index) }
            return ([int]$a.tid).CompareTo([int]$b.tid)
        })

        $assignedTracks = New-Object 'System.Collections.Generic.HashSet[int]'
        $assignedDets = New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($c in $candArr) {
            if ($assignedTracks.Contains([int]$c.ti)) { continue }
            if ($assignedDets.Contains([int]$c.di)) { continue }
            [void]$assignedTracks.Add([int]$c.ti)
            [void]$assignedDets.Add([int]$c.di)
            # extend the matched track
            $t = $activeTracks[[int]$c.ti]; $d = $dets[[int]$c.di]
            $t.frames.Add([ordered]@{ frame = $frameIdx; timestamp_s = $ts; box = $d.box_out; score = $d.score; det_index = [int]$d.det_index })
            $t.last_x = $d.x; $t.last_y = $d.y; $t.last_w = $d.w; $t.last_h = $d.h
            $t.last_frame = $frameIdx; $t.age = 0
        }

        # ---- unmatched detections -> BIRTH (in detection order, for monotonic ids) ----
        for ($di = 0; $di -lt $dets.Count; $di++) {
            if ($assignedDets.Contains($di)) { continue }
            $d = $dets[$di]
            $frs = New-Object System.Collections.Generic.List[object]
            $frs.Add([ordered]@{ frame = $frameIdx; timestamp_s = $ts; box = $d.box_out; score = $d.score; det_index = [int]$d.det_index })
            $trk = [pscustomobject]@{
                track_id = $nextId; class = [string]$d.class; class_id = $d.class_id
                frames = $frs
                last_x = $d.x; last_y = $d.y; last_w = $d.w; last_h = $d.h
                last_frame = $frameIdx; age = 0; aged_out = $false
            }
            $nextId++; $births++
            $allTracks.Add($trk); $activeTracks.Add($trk)
        }

        # ---- unmatched active tracks -> COAST (constant position) up to MaxAge, then DEATH ----
        $survivors = New-Object System.Collections.Generic.List[object]
        for ($ti = 0; $ti -lt $activeTracks.Count; $ti++) {
            $t = $activeTracks[$ti]
            if ($assignedTracks.Contains($ti)) { $survivors.Add($t); continue }   # matched this frame
            if ($t.last_frame -eq $frameIdx) { $survivors.Add($t); continue }      # just born this frame
            $t.age = [int]$t.age + 1
            if ($t.age -gt $MaxAge) { $t.aged_out = $true; $deaths++ }              # DEATH: drop from active
            else { $coastFrames++; $survivors.Add($t) }                            # COAST: keep last box
        }
        $activeTracks = $survivors
        if ($activeTracks.Count -gt $maxConcurrent) { $maxConcurrent = $activeTracks.Count }
    }

    # ================= assemble the tracks output (ordered by track_id) =================
    $trackRows = New-Object System.Collections.Generic.List[object]
    $classCounts = [ordered]@{}
    foreach ($t in $allTracks.ToArray()) {
        $frs = $t.frames.ToArray()
        $first = [int]$frs[0].frame
        $last = [int]$frs[$frs.Count - 1].frame
        $cls = [string]$t.class
        if ($classCounts.Contains($cls)) { $classCounts[$cls] = [int]$classCounts[$cls] + 1 } else { $classCounts[$cls] = 1 }
        $trackRows.Add([ordered]@{
            track_id = [int]$t.track_id
            class = $cls
            class_id = $t.class_id
            frames = $frs
            first_frame = $first
            last_frame = $last
            length = $frs.Count
            aged_out = [bool]$t.aged_out
        })
    }

    $paramsObj = [ordered]@{
        iou_threshold = [double]$IouThreshold
        max_age = [int]$MaxAge
        min_score = [double]$MinScore
        classes = $classFilter
    }
    $summaryObj = [ordered]@{
        input_frames = $normFrames.Count
        input_detections = $rawInputDetections
        tracked_detections = $trackedDetections
        track_count = $trackRows.Count
        births = $births
        deaths = $deaths
        coast_frames = $coastFrames
        max_concurrent_tracks = $maxConcurrent
        class_summary = $classCounts
    }
    $inputObj = [ordered]@{ source = $source; path = $inFull; frames = $normFrames.Count }

    # ---- tracks.json: NO volatile fields (invocation_id/timestamps live in the envelope) => byte-identical
    #      for identical input. This is the determinism guarantee, provable by a repeated-run sha256 compare.
    $tracksDoc = [ordered]@{
        schema = $TRACKS_SCHEMA
        input = $inputObj
        params = $paramsObj
        summary = $summaryObj
        tracks = $trackRows.ToArray()
    }
    $tracksJsonPath = Join-Path $invDir 'tracks.json'
    [System.IO.File]::WriteAllText($tracksJsonPath, ($tracksDoc | ConvertTo-Json -Depth 20), $utf8)
    $producedFiles.Add([pscustomobject]@{ p = $tracksJsonPath; k = 'json' })

    $result = [ordered]@{
        input = $inputObj
        params = $paramsObj
        summary = $summaryObj
        tracks = $trackRows.ToArray()
    }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($tracksDoc | ConvertTo-Json -Depth 20 -Compress)))
    Write-Diag "ok frames=$($normFrames.Count) dets=$rawInputDetections tracks=$($trackRows.Count) births=$births deaths=$deaths iou>=$IouThreshold maxage=$MaxAge"
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code = [string]$ex.code; message = [string]$ex.message; retryable = [bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) -- $($errorObj.message)"
}

# ---- artifacts + human summary ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# track.objects")
        [void]$mb.AppendLine("source: $($result.input.source)  path: $($result.input.path)")
        [void]$mb.AppendLine("frames: $($result.summary.input_frames)  detections: $($result.summary.input_detections)  tracks: $($result.summary.track_count)  (births=$($result.summary.births) deaths=$($result.summary.deaths))")
        [void]$mb.AppendLine("params: iou>=$($result.params.iou_threshold) max_age=$($result.params.max_age) min_score=$($result.params.min_score)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('| track_id | class | length | first->last | aged_out |')
        [void]$mb.AppendLine('|---|---|---|---|---|')
        foreach ($tr in @($result.tracks)) {
            [void]$mb.AppendLine("| $($tr.track_id) | $($tr.class) | $($tr.length) | $($tr.first_frame)->$($tr.last_frame) | $($tr.aged_out) |")
        }
        if ($warnings.Count -gt 0) { [void]$mb.AppendLine(''); [void]$mb.AppendLine("warnings: $((@($warnings.ToArray())) -join '; ')") }
        $mdPath = Join-Path $invDir 'tracks.md'
        [System.IO.File]::WriteAllText($mdPath, $mb.ToString(), $utf8)
        $producedFiles.Add([pscustomobject]@{ p = $mdPath; k = 'markdown' })

        foreach ($a in $producedFiles.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += , ([ordered]@{ path = (Resolve-Path -LiteralPath $a.p).Path; kind = $a.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[track.objects] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

if ($status -eq 'ok' -and $warnings.Count -gt 0) { $status = 'partial' }

$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds
    inputs_digest = $(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result = $result; confidence = $confidence; artifacts = $artifacts; model_provenance = $modelProvenance
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 25
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
