#requires -Version 7.0
<#
.SYNOPSIS
  video.timeline -- fuse per-source video artifacts into ONE canonical, deterministic, searchable
  timeline JSON (Life Orchestrator, contract v0.2). Third module of the Phase C video spine
  (architectural position 21), downstream of media.decompose #32 (pos 19) and track.objects #33 (pos 20).
.DESCRIPTION
  Input is a per-source artifact MANIFEST (a JSON file via -InputFile, or inline via -InputsJson):
    media      REQUIRED  {id?, path?, source_media_sha256?, meta: #32 meta shape | inline {frame_width, frame_height, duration_ms}}
    scenes     optional  #32 scenes shape ({scenes:[{index,start,end,score}]} or bare array; SECONDS -> integer ms, round-half-up)
    samples    optional  the reviewed sample manifest [{sample_index, frame_index, timestamp_ms, scene_index?, detection_count?}]
    tracks     optional  a reviewed-schema track file (path or inline): {schema, identity_scope?, timestamp_unit?, tracks:[...], samples?}
    transcript optional  #11-shape segments ({segments:[{t0_ms,t1_ms,text}]} or bare array; start_ms/end_ms accepted as aliases)
    ocr        optional  per-keyframe entries [{timestamp_ms | frame_index, lines: #14-shape lines (each {text,...})}]
    detections optional  per-sample entries [{timestamp_ms, sample_index?, detections: #16 shape [{class, class_id?, score?, box{x,y,width,height}}]}]
  Every provided input is validated STRICTLY against its expected shape; violations produce a FAIL-CLOSED
  error envelope enumerating each one (path + why). Unknown extra fields are tolerated, never repaired.
  Only media meta is required -- the timeline DEGRADES HONESTLY (meta-only; tracks-without-samples with
  coverage "unknown" + explicitly downgraded presence semantics; transcript-only; OCR keyed by frame_index
  maps through the sample manifest or is REFUSED -- timestamps are never invented).

  Output is ONE canonical timeline.json (schema lifeorch.video_timeline/0.1) plus the separate
  lifeorch.skill.result/0.1 diagnostics/invocation envelope. Canonical discipline (per the folded frontier
  review core-docs/research/2026-07-30-track-objects-design-review.md): UTF-8 no BOM, single line + one
  trailing LF, sorted keys (ordinal), compact separators, fixed content-derived array ordering, integer ms
  everywhere, no NaN/Inf, and NO absolute paths / invocation UUIDs / wall-clock times / hostnames in the
  canonical bytes. The canonical file carries schema id + generator name/version/params + input_digest.

  Semantic rules (load-bearing): "sampled with no detection" vs "not sampled" vs "tracker gap" stay
  distinguishable through the sample manifest (coverage.samples), track_gap intervals, and
  detection_sample events; per-track APPEARANCE SEGMENTATION splits contiguous observed spans at recorded
  gaps and NEVER merges across a gap (false continuity is corrupting); identity_scope is carried verbatim
  (track ids never imply cross-video identity); NO field named "confidence" appears anywhere in the
  canonical timeline -- detection evidence and association evidence pass through separated, under their
  review names.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputFile .\manifest.json
  pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputsJson '{"input":"manifest.json"}'
  pwsh -NoProfile -File .\Invoke-VideoTimeline.ps1 -InputsJson '{"media":{"id":"clip-1","meta":{"frame_width":640,"frame_height":360,"duration_ms":12000}}}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'video.timeline'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$TIMELINE_SCHEMA = 'lifeorch.video_timeline/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$bound = $PSBoundParameters
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[video.timeline] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { $v = $o.$n; if ($null -ne $v) { return $v } } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function New-SkillError([string]$code, [string]$message, [bool]$retryable = $false) {
    return [PSCustomObject]@{ code = $code; message = $message; retryable = $retryable }
}
function IsNum($v) { return ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) }
function IsIntegral($v) {
    if ($v -is [int] -or $v -is [long]) { return $true }
    if ($v -is [double])  { return ([math]::Floor([double]$v) -eq [double]$v) -and -not [double]::IsInfinity([double]$v) -and -not [double]::IsNaN([double]$v) }
    if ($v -is [decimal]) { return ([decimal]::Truncate([decimal]$v) -eq [decimal]$v) }
    return $false
}
# non-negative round-half-up (the documented rounding rule for seconds -> ms and score -> q conversions)
function RoundHalfUp([double]$d) { return [long][math]::Floor($d + 0.5) }
function MsFromSeconds([double]$sec) { return (RoundHalfUp ($sec * 1000.0)) }
function QFromScore([double]$s) { return (RoundHalfUp ($s * 1000000.0)) }

# ============================ canonical JSON serializer ============================
# RFC 8785-flavoured: sorted keys (ordinal), compact separators, minimal escapes (\" \\ \b \t \n \f \r,
# \u00xx for other controls; non-ASCII emitted literally as UTF-8), integers only (a double anywhere in the
# canonical model is an internal defect and throws), true/false/null literals.
function Esc-CanonicalString([string]$s) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        $cp = [int][char]$ch
        switch ($ch) {
            '"'  { [void]$sb.Append('\"'); continue }
            '\'  { [void]$sb.Append('\\'); continue }
            default {
                if ($cp -lt 0x20) {
                    switch ($cp) {
                        8  { [void]$sb.Append('\b') }
                        9  { [void]$sb.Append('\t') }
                        10 { [void]$sb.Append('\n') }
                        12 { [void]$sb.Append('\f') }
                        13 { [void]$sb.Append('\r') }
                        default { [void]$sb.Append('\u' + $cp.ToString('x4')) }
                    }
                } else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}
function ConvertTo-CanonicalJson($v) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [string]) { return (Esc-CanonicalString $v) }
    if ($v -is [int] -or $v -is [long]) { return ([long]$v).ToString([Globalization.CultureInfo]::InvariantCulture) }
    if ($v -is [double] -or $v -is [decimal]) { throw (New-SkillError 'canonical_float_leak' "internal defect: non-integer number reached the canonical serializer ($v)") }
    if ($v -is [System.Collections.IDictionary]) {
        $keys = New-Object System.Collections.Generic.List[string]
        foreach ($k in $v.Keys) { $keys.Add([string]$k) }
        $ka = $keys.ToArray()
        [System.Array]::Sort($ka, [System.StringComparer]::Ordinal)
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($k in $ka) { $parts.Add((Esc-CanonicalString $k) + ':' + (ConvertTo-CanonicalJson $v[$k])) }
        return '{' + ($parts.ToArray() -join ',') + '}'
    }
    if ($v -is [System.Collections.IEnumerable]) {
        $parts = New-Object System.Collections.Generic.List[string]
        foreach ($e in $v) { $parts.Add((ConvertTo-CanonicalJson $e)) }
        return '[' + ($parts.ToArray() -join ',') + ']'
    }
    if ($null -ne $v.PSObject -and $v -is [System.Management.Automation.PSCustomObject]) {
        $d = [ordered]@{}
        foreach ($p in $v.PSObject.Properties) { $d[$p.Name] = $p.Value }
        return (ConvertTo-CanonicalJson $d)
    }
    throw (New-SkillError 'canonical_type_leak' "internal defect: unsupported type reached the canonical serializer ($($v.GetType().FullName))")
}

# ============================ strict validation helpers ============================
$script:violations = New-Object System.Collections.Generic.List[object]
function AddViolation([string]$path, [string]$why) { $script:violations.Add([pscustomobject]@{ path = $path; why = $why }) }
# Require an integral numeric >= $min at $path; returns [long] or $null (after recording a violation).
function ReqInt($v, [string]$path, [long]$min = [long]::MinValue) {
    if ($null -eq $v) { AddViolation $path 'required integer is missing/null'; return $null }
    if (-not (IsNum $v)) { AddViolation $path "must be a JSON number (got $($v.GetType().Name))"; return $null }
    if (-not (IsIntegral $v)) { AddViolation $path "must be an integer (got $v)"; return $null }
    $l = [long]$v
    if ($l -lt $min) { AddViolation $path "must be >= ${min} (got $l)"; return $null }
    return $l
}
function OptInt($o, [string]$n, [string]$path, [long]$min = [long]::MinValue) {
    if (-not (Has $o $n)) { return $null }
    $v = $o.$n
    if ($null -eq $v) { return $null }
    return (ReqInt $v "$path.$n" $min)
}
function ReqNum($v, [string]$path) {
    if ($null -eq $v -or -not (IsNum $v)) { AddViolation $path 'must be a JSON number'; return $null }
    $d = [double]$v
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { AddViolation $path 'must be finite (no NaN/Inf)'; return $null }
    return $d
}
function ReqStr($v, [string]$path) {
    if ($null -eq $v -or -not ($v -is [string]) -or [string]::IsNullOrEmpty([string]$v)) { AddViolation $path 'required non-empty string is missing'; return $null }
    return [string]$v
}
function AsArray($v, [string]$path) {
    if ($null -eq $v) { return ,@() }
    if ($v -is [System.Array] -or $v -is [System.Collections.IList]) { return ,@($v) }
    AddViolation $path 'must be a JSON array'
    return ,@()
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$confidence = $null; $modelProvenance = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$producedFiles = New-Object System.Collections.Generic.List[object]
$diagExtra = [ordered]@{}

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw (New-SkillError 'invalid_inputs_json' '-InputsJson is not valid JSON') }
    }
    $inlineManifest = $null
    if ($null -ne $p) {
        if ((Has $p 'input') -and -not $bound.ContainsKey('InputFile')) { $InputFile = [string]$p.input }
        if (Has $p 'manifest') { $inlineManifest = $p.manifest }
        elseif (Has $p 'media') { $inlineManifest = $p }   # InputsJson itself is the manifest
    }

    # ---- resolve the manifest (file wins over inline) ----
    $source = $null; $inFull = $null; $manifest = $null; $manifestDir = $null
    if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
        if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
            throw (New-SkillError 'input_not_found' "input manifest file not found: $InputFile")
        }
        $inFull = (Resolve-Path -LiteralPath $InputFile).Path
        $manifestDir = Split-Path -Parent $inFull
        $raw = Get-Content -LiteralPath $inFull -Raw
        try { $manifest = $raw | ConvertFrom-Json } catch { throw (New-SkillError 'input_parse_failed' "manifest JSON did not parse: $($_.Exception.Message)") }
        $source = 'file'
    }
    elseif ($null -ne $inlineManifest) {
        $manifest = $inlineManifest
        $manifestDir = (Get-Location).Path
        $source = 'inline'
    }
    else {
        throw (New-SkillError 'no_input' 'no input: provide -InputFile, InputsJson.input, InputsJson.manifest, or an inline manifest (InputsJson with a media key)')
    }
    if ($null -eq $manifest -or -not ($manifest -is [System.Management.Automation.PSCustomObject])) {
        throw (New-SkillError 'invalid_input_shape' 'the manifest must be a JSON object')
    }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ================================ 1. STRICT VALIDATION + NORMALIZATION ================================

    # ---- media (REQUIRED) ----
    $mediaId = $null; $frameW = $null; $frameH = $null; $durationMs = $null; $mediaSha = $null; $mediaPath = $null
    if (-not (Has $manifest 'media') -or $null -eq $manifest.media) {
        AddViolation 'media' 'required media object is missing'
    } else {
        $media = $manifest.media
        if (Has $media 'id') { if ($null -ne $media.id -and $media.id -is [string] -and $media.id -ne '') { $mediaId = [string]$media.id } elseif ($null -ne $media.id) { AddViolation 'media.id' 'must be a non-empty string when present' } }
        if (Has $media 'path') { $mediaPath = [string]$media.path; $diagExtra['media_path'] = $mediaPath }   # diagnostics only; NEVER canonical
        $shaRaw = $null
        if (Has $media 'source_media_sha256') { $shaRaw = $media.source_media_sha256 } elseif (Has $media 'sha256') { $shaRaw = $media.sha256 }
        if ($null -ne $shaRaw) {
            if (($shaRaw -is [string]) -and ([string]$shaRaw -match '^[0-9a-f]{64}$')) { $mediaSha = [string]$shaRaw }
            else { AddViolation 'media.source_media_sha256' 'must be 64 lowercase hex chars when present' }
        }
        if (-not (Has $media 'meta') -or $null -eq $media.meta) {
            AddViolation 'media.meta' 'required media.meta is missing (the #32 meta shape or inline {frame_width, frame_height, duration_ms})'
        } else {
            $meta = $media.meta
            $inner = $meta
            if ((Has $meta 'meta') -and $null -ne $meta.meta) { $inner = $meta.meta }   # the #32 meta.json wrapper {schema, meta:{...}}
            # duration: inline duration_ms wins; else meta.duration_s; else container.duration_s (seconds -> ms round-half-up)
            if (Has $inner 'duration_ms') {
                $durationMs = ReqInt $inner.duration_ms 'media.meta.duration_ms' 0
            } elseif ((Has $inner 'duration_s') -and (IsNum $inner.duration_s)) {
                $durationMs = MsFromSeconds ([double]$inner.duration_s)
            } elseif ((Has $inner 'container') -and $null -ne $inner.container -and (Has $inner.container 'duration_s') -and (IsNum $inner.container.duration_s)) {
                $durationMs = MsFromSeconds ([double]$inner.container.duration_s)
            } else {
                AddViolation 'media.meta' 'no resolvable duration (need duration_ms, duration_s, or container.duration_s)'
            }
            if ($null -ne $durationMs -and $durationMs -lt 0) { AddViolation 'media.meta' "duration must be >= 0 (got $durationMs)"; $durationMs = $null }
            # dims: inline frame_width/frame_height; else the first video stream
            if ((Has $inner 'frame_width') -or (Has $inner 'frame_height')) {
                $frameW = OptInt $inner 'frame_width'  'media.meta' 1
                $frameH = OptInt $inner 'frame_height' 'media.meta' 1
            } elseif ((Has $inner 'streams') -and $null -ne $inner.streams) {
                foreach ($st in @($inner.streams)) {
                    if ((Has $st 'codec_type') -and ([string]$st.codec_type -eq 'video')) {
                        $frameW = OptInt $st 'width'  'media.meta.streams[video]' 1
                        $frameH = OptInt $st 'height' 'media.meta.streams[video]' 1
                        break
                    }
                }
            }
        }
    }

    # ---- scenes (optional; #32 shape, seconds -> ms) ----
    $normScenes = New-Object System.Collections.Generic.List[object]   # @{scene_index; start_ms; end_ms}
    $scenesProvided = $false
    if ((Has $manifest 'scenes') -and $null -ne $manifest.scenes) {
        $scenesProvided = $true
        $sceneRaw = $manifest.scenes
        $sceneArr = @()
        if ($sceneRaw -is [System.Array] -or $sceneRaw -is [System.Collections.IList]) { $sceneArr = @($sceneRaw) }
        elseif (Has $sceneRaw 'scenes') { $sceneArr = AsArray $sceneRaw.scenes 'scenes.scenes' }
        else { AddViolation 'scenes' 'must be a scene array or a #32 scenes document ({scenes:[...]})' }
        $seenSceneIdx = New-Object 'System.Collections.Generic.HashSet[long]'
        for ($i = 0; $i -lt @($sceneArr).Count; $i++) {
            $sc = @($sceneArr)[$i]
            $si = $null; $sStart = $null; $sEnd = $null
            if (-not (Has $sc 'index')) { AddViolation "scenes[$i].index" 'required scene index is missing' } else { $si = ReqInt $sc.index "scenes[$i].index" 0 }
            if (-not (Has $sc 'start')) { AddViolation "scenes[$i].start" 'required start (seconds) is missing' } else { $d = ReqNum $sc.start "scenes[$i].start"; if ($null -ne $d) { if ($d -lt 0) { AddViolation "scenes[$i].start" 'must be >= 0' } else { $sStart = MsFromSeconds $d } } }
            if (-not (Has $sc 'end'))   { AddViolation "scenes[$i].end"   'required end (seconds) is missing' }   else { $d = ReqNum $sc.end "scenes[$i].end";   if ($null -ne $d) { if ($d -lt 0) { AddViolation "scenes[$i].end" 'must be >= 0' } else { $sEnd = MsFromSeconds $d } } }
            if ($null -ne $sStart -and $null -ne $sEnd -and $sEnd -lt $sStart) { AddViolation "scenes[$i]" "end ($sEnd ms) precedes start ($sStart ms)" }
            if ($null -ne $si) {
                if (-not $seenSceneIdx.Add([long]$si)) { AddViolation "scenes[$i].index" "duplicate scene index $si" }
            }
            if ($null -ne $si -and $null -ne $sStart -and $null -ne $sEnd) {
                $normScenes.Add([pscustomobject]@{ scene_index = [long]$si; start_ms = [long]$sStart; end_ms = [long]$sEnd })
            }
        }
    }
    $sceneArrSorted = $normScenes.ToArray()
    [System.Array]::Sort($sceneArrSorted, [System.Comparison[object]] { param($a, $b) ([long]$a.scene_index).CompareTo([long]$b.scene_index) })
    # overlap warning (adversarial input tolerated, surfaced, never repaired)
    for ($i = 1; $i -lt $sceneArrSorted.Count; $i++) {
        if ([long]$sceneArrSorted[$i].start_ms -lt [long]$sceneArrSorted[$i - 1].end_ms) {
            $warnings.Add("scenes overlap: scene $($sceneArrSorted[$i-1].scene_index) [$($sceneArrSorted[$i-1].start_ms),$($sceneArrSorted[$i-1].end_ms)) and scene $($sceneArrSorted[$i].scene_index) [$($sceneArrSorted[$i].start_ms),$($sceneArrSorted[$i].end_ms))")
        }
    }

    # ---- tracks (optional; reviewed schema; path or inline) ----
    $tracksProvided = $false; $tracksDoc = $null; $tracksPath = $null; $identityScope = $null
    if ((Has $manifest 'tracks') -and $null -ne $manifest.tracks) {
        $tracksProvided = $true
        $tRaw = $manifest.tracks
        if ($tRaw -is [string]) {
            $tp = [string]$tRaw
            if (-not [System.IO.Path]::IsPathRooted($tp)) { $tp = Join-Path $manifestDir $tp }
            if (-not (Test-Path -LiteralPath $tp -PathType Leaf)) {
                AddViolation 'tracks' "track file not found: $tRaw"
            } else {
                $tracksPath = (Resolve-Path -LiteralPath $tp).Path
                $diagExtra['tracks_path'] = $tracksPath
                try { $tracksDoc = (Get-Content -LiteralPath $tracksPath -Raw) | ConvertFrom-Json }
                catch { AddViolation 'tracks' "track file JSON did not parse: $($_.Exception.Message)" }
            }
        } elseif ($tRaw -is [System.Management.Automation.PSCustomObject]) {
            $tracksDoc = $tRaw
        } else {
            AddViolation 'tracks' 'must be a track-file path (string) or an inline track object'
        }
    }
    if ($null -ne $tracksDoc) {
        if (-not (Has $tracksDoc 'schema') -or -not ($tracksDoc.schema -is [string]) -or [string]::IsNullOrEmpty([string]$tracksDoc.schema)) {
            AddViolation 'tracks.schema' 'required schema id (string) is missing'
        } else { $diagExtra['tracks_schema'] = [string]$tracksDoc.schema }
        if ((Has $tracksDoc 'timestamp_unit') -and $null -ne $tracksDoc.timestamp_unit -and ([string]$tracksDoc.timestamp_unit -ne 'ms')) {
            AddViolation 'tracks.timestamp_unit' "must be 'ms' when present (got '$($tracksDoc.timestamp_unit)')"
        }
        if ((Has $tracksDoc 'identity_scope') -and $null -ne $tracksDoc.identity_scope) {
            if ($tracksDoc.identity_scope -is [string]) { $identityScope = [string]$tracksDoc.identity_scope }
            else { AddViolation 'tracks.identity_scope' 'must be a string when present' }
        }
        $tw = OptInt $tracksDoc 'frame_width'  'tracks' 1
        $th = OptInt $tracksDoc 'frame_height' 'tracks' 1
        if ($null -ne $tw -and $null -ne $frameW -and $tw -ne $frameW) { AddViolation 'tracks.frame_width'  "does not match media frame_width ($tw vs $frameW)" }
        if ($null -ne $th -and $null -ne $frameH -and $th -ne $frameH) { AddViolation 'tracks.frame_height' "does not match media frame_height ($th vs $frameH)" }
        if ($null -eq $mediaSha -and (Has $tracksDoc 'source_media_sha256') -and $null -ne $tracksDoc.source_media_sha256 -and ($tracksDoc.source_media_sha256 -is [string]) -and ([string]$tracksDoc.source_media_sha256 -match '^[0-9a-f]{64}$')) {
            $mediaSha = [string]$tracksDoc.source_media_sha256
        }
        if (-not (Has $tracksDoc 'tracks')) { AddViolation 'tracks.tracks' 'required tracks array is missing' }
    }

    # ---- samples (optional; manifest wins over the track file's own manifest) ----
    $samplesProvided = $false; $samplesSource = $null; $sampleRawArr = @(); $samplesPathLabel = 'samples'
    if ((Has $manifest 'samples') -and $null -ne $manifest.samples) {
        $samplesProvided = $true; $samplesSource = 'manifest'
        $sRaw = $manifest.samples
        if ($sRaw -is [System.Array] -or $sRaw -is [System.Collections.IList]) { $sampleRawArr = @($sRaw) }
        elseif (Has $sRaw 'samples') { $sampleRawArr = AsArray $sRaw.samples 'samples.samples' }
        else { AddViolation 'samples' 'must be a sample array or {samples:[...]}' }
    } elseif ($null -ne $tracksDoc -and (Has $tracksDoc 'samples') -and $null -ne $tracksDoc.samples) {
        $samplesProvided = $true; $samplesSource = 'tracks'; $samplesPathLabel = 'tracks.samples'
        $sampleRawArr = AsArray $tracksDoc.samples 'tracks.samples'
    }
    $normSamples = New-Object System.Collections.Generic.List[object]
    $sampleByIndex = @{}
    $sampleByFrame = @{}
    for ($i = 0; $i -lt @($sampleRawArr).Count; $i++) {
        $sm = @($sampleRawArr)[$i]
        $sIdx = $null; $sFrame = $null; $sTs = $null
        if (-not (Has $sm 'sample_index')) { AddViolation "$samplesPathLabel[$i].sample_index" 'required sample_index is missing' } else { $sIdx = ReqInt $sm.sample_index "$samplesPathLabel[$i].sample_index" 0 }
        if (-not (Has $sm 'frame_index'))  { AddViolation "$samplesPathLabel[$i].frame_index"  'required frame_index is missing' }  else { $sFrame = ReqInt $sm.frame_index "$samplesPathLabel[$i].frame_index" 0 }
        if (-not (Has $sm 'timestamp_ms')) { AddViolation "$samplesPathLabel[$i].timestamp_ms" 'required timestamp_ms is missing' } else { $sTs = ReqInt $sm.timestamp_ms "$samplesPathLabel[$i].timestamp_ms" 0 }
        $sScene = OptInt $sm 'scene_index' "$samplesPathLabel[$i]" 0
        $sDet   = OptInt $sm 'detection_count' "$samplesPathLabel[$i]" 0
        if ($null -ne $sIdx -and $null -ne $sFrame -and $null -ne $sTs) {
            if ($sampleByIndex.ContainsKey([long]$sIdx)) { AddViolation "$samplesPathLabel[$i].sample_index" "duplicate sample_index $sIdx" }
            else {
                $row = [pscustomobject]@{ sample_index = [long]$sIdx; frame_index = [long]$sFrame; timestamp_ms = [long]$sTs; scene_index = $sScene; detection_count = $sDet }
                $normSamples.Add($row)
                $sampleByIndex[[long]$sIdx] = $row
                if (-not $sampleByFrame.ContainsKey([long]$sFrame)) { $sampleByFrame[[long]$sFrame] = $row }
            }
        }
    }
    $sampleArrSorted = $normSamples.ToArray()
    [System.Array]::Sort($sampleArrSorted, [System.Comparison[object]] { param($a, $b) ([long]$a.sample_index).CompareTo([long]$b.sample_index) })

    # ---- tracks[] deep validation + normalization ----
    # normTrack = @{ track_id; class; scene_index; obs = @(@{sample_index;frame_index;timestamp_ms;detection_score_q;low_confidence;assoc_kind;iou_q;gap_ms}); gaps = @(aligned @{afterObs;start_ms;end_ms;elapsed_ms;missed_samples;reacquired_by}) }
    $normTracks = New-Object System.Collections.Generic.List[object]
    if ($null -ne $tracksDoc -and (Has $tracksDoc 'tracks') -and $null -ne $tracksDoc.tracks) {
        $trackArr = AsArray $tracksDoc.tracks 'tracks.tracks'
        $seenTrackIds = New-Object 'System.Collections.Generic.HashSet[long]'
        for ($ti = 0; $ti -lt @($trackArr).Count; $ti++) {
            $tr = @($trackArr)[$ti]
            $tPath = "tracks.tracks[$ti]"
            $tid = $null
            if (-not (Has $tr 'track_id')) { AddViolation "$tPath.track_id" 'required track_id is missing' } else { $tid = ReqInt $tr.track_id "$tPath.track_id" 0 }
            if ($null -ne $tid -and -not $seenTrackIds.Add([long]$tid)) { AddViolation "$tPath.track_id" "duplicate track_id $tid" }
            $tCls = $null
            if (-not (Has $tr 'class')) { AddViolation "$tPath.class" 'required class is missing' } else { $tCls = ReqStr $tr.class "$tPath.class" }
            $tScene = OptInt $tr 'scene_index' $tPath 0
            # observations (non-empty REQUIRED -- presence cannot be fabricated without observations)
            $obsList = New-Object System.Collections.Generic.List[object]
            if (-not (Has $tr 'observations') -or $null -eq $tr.observations) {
                AddViolation "$tPath.observations" 'required observations array is missing'
            } else {
                $obsArr = AsArray $tr.observations "$tPath.observations"
                if (@($obsArr).Count -eq 0) { AddViolation "$tPath.observations" 'must be non-empty (a zero-observation track has no observed presence and cannot be fused honestly)' }
                for ($oi = 0; $oi -lt @($obsArr).Count; $oi++) {
                    $ob = @($obsArr)[$oi]
                    $oPath = "$tPath.observations[$oi]"
                    $oSi = $null; $oTs = $null
                    if (-not (Has $ob 'sample_index')) { AddViolation "$oPath.sample_index" 'required sample_index is missing' } else { $oSi = ReqInt $ob.sample_index "$oPath.sample_index" 0 }
                    if (-not (Has $ob 'timestamp_ms')) { AddViolation "$oPath.timestamp_ms" 'required timestamp_ms is missing' } else { $oTs = ReqInt $ob.timestamp_ms "$oPath.timestamp_ms" 0 }
                    $oFrame = OptInt $ob 'frame_index' $oPath 0
                    # cross-check against the sample manifest (fail-closed: the manifest lists EVERY processed sample)
                    if ($null -ne $oSi -and $samplesProvided) {
                        if (-not $sampleByIndex.ContainsKey([long]$oSi)) {
                            AddViolation "$oPath.sample_index" "sample_index $oSi is not listed in the sample manifest"
                        } elseif ($null -ne $oTs -and ([long]$sampleByIndex[[long]$oSi].timestamp_ms -ne [long]$oTs)) {
                            AddViolation "$oPath.timestamp_ms" "timestamp_ms $oTs disagrees with the sample manifest's $($sampleByIndex[[long]$oSi].timestamp_ms) for sample_index $oSi"
                        }
                    }
                    $dsq = $null
                    if ((Has $ob 'detection_score') -and $null -ne $ob.detection_score) {
                        $ds = ReqNum $ob.detection_score "$oPath.detection_score"
                        if ($null -ne $ds) { if ($ds -lt 0) { AddViolation "$oPath.detection_score" 'must be >= 0' } else { $dsq = QFromScore $ds } }
                    }
                    $lowc = $false
                    if ((Has $ob 'low_confidence') -and $null -ne $ob.low_confidence) {
                        if ($ob.low_confidence -is [bool]) { $lowc = [bool]$ob.low_confidence } else { AddViolation "$oPath.low_confidence" 'must be a boolean when present' }
                    }
                    $aKind = $null; $aIouQ = $null; $aGapMs = $null
                    if ((Has $ob 'association') -and $null -ne $ob.association) {
                        $as = $ob.association
                        if (Has $as 'kind') {
                            $aKind = [string]$as.kind
                            if (@('birth','iou','centroid') -notcontains $aKind) { AddViolation "$oPath.association.kind" "must be birth|iou|centroid (got '$aKind')"; $aKind = $null }
                        }
                        $aIouQ = OptInt $as 'iou_q' "$oPath.association" 0
                        $aGapMs = OptInt $as 'gap_ms' "$oPath.association" 0
                    }
                    if ($null -ne $oSi -and $null -ne $oTs) {
                        $obsList.Add([pscustomobject]@{ sample_index = [long]$oSi; frame_index = $oFrame; timestamp_ms = [long]$oTs; detection_score_q = $dsq; low_confidence = $lowc; assoc_kind = $aKind; iou_q = $aIouQ; gap_ms = $aGapMs })
                    }
                }
            }
            # canonical observation order: (timestamp_ms, frame_index, sample_index)
            $obsSorted = $obsList.ToArray()
            [System.Array]::Sort($obsSorted, [System.Comparison[object]] {
                param($a, $b)
                if ([long]$a.timestamp_ms -ne [long]$b.timestamp_ms) { return ([long]$a.timestamp_ms).CompareTo([long]$b.timestamp_ms) }
                $af = $a.frame_index; $bf = $b.frame_index
                if ($null -ne $af -and $null -ne $bf -and [long]$af -ne [long]$bf) { return ([long]$af).CompareTo([long]$bf) }
                return ([long]$a.sample_index).CompareTo([long]$b.sample_index)
            })
            # gaps: validate + ALIGN to consecutive observations (never invented, never dropped)
            $alignedGaps = New-Object System.Collections.Generic.List[object]
            if ((Has $tr 'gaps') -and $null -ne $tr.gaps) {
                $gapArr = AsArray $tr.gaps "$tPath.gaps"
                $usedBoundaries = New-Object 'System.Collections.Generic.HashSet[int]'
                for ($gi = 0; $gi -lt @($gapArr).Count; $gi++) {
                    $g = @($gapArr)[$gi]
                    $gPath = "$tPath.gaps[$gi]"
                    $gStart = $null; $gEnd = $null
                    if (-not (Has $g 'start_ms')) { AddViolation "$gPath.start_ms" 'required start_ms is missing' } else { $gStart = ReqInt $g.start_ms "$gPath.start_ms" 0 }
                    if (-not (Has $g 'end_ms'))   { AddViolation "$gPath.end_ms"   'required end_ms is missing' }   else { $gEnd = ReqInt $g.end_ms "$gPath.end_ms" 0 }
                    if ($null -ne $gStart -and $null -ne $gEnd -and $gEnd -lt $gStart) { AddViolation $gPath "end_ms ($gEnd) precedes start_ms ($gStart)" }
                    $gAfter  = OptInt $g 'after_sample_index'  $gPath 0
                    $gBefore = OptInt $g 'before_sample_index' $gPath 0
                    $gElapsed = OptInt $g 'elapsed_ms' $gPath 0
                    $gMissed  = OptInt $g 'missed_samples' $gPath 0
                    $gReacq = $null
                    if ((Has $g 'reacquired_by') -and $null -ne $g.reacquired_by) {
                        $gReacq = [string]$g.reacquired_by
                        if (@('iou','centroid') -notcontains $gReacq) { AddViolation "$gPath.reacquired_by" "must be iou|centroid when present (got '$gReacq')"; $gReacq = $null }
                    }
                    if ($null -eq $gStart -or $null -eq $gEnd) { continue }
                    # alignment: prefer (after_sample_index, before_sample_index) on CONSECUTIVE observations; else timestamp bracketing
                    $boundary = -1
                    if ($null -ne $gAfter -and $null -ne $gBefore) {
                        for ($k = 0; $k -lt ($obsSorted.Count - 1); $k++) {
                            if ([long]$obsSorted[$k].sample_index -eq [long]$gAfter -and [long]$obsSorted[$k + 1].sample_index -eq [long]$gBefore) { $boundary = $k; break }
                        }
                        if ($boundary -lt 0) { AddViolation $gPath "gap (after_sample_index=$gAfter, before_sample_index=$gBefore) does not sit between consecutive observations of this track" }
                    } else {
                        for ($k = 0; $k -lt ($obsSorted.Count - 1); $k++) {
                            if ([long]$obsSorted[$k].timestamp_ms -le [long]$gStart -and [long]$obsSorted[$k + 1].timestamp_ms -ge [long]$gEnd) { $boundary = $k; break }
                        }
                        if ($boundary -lt 0) { AddViolation $gPath "gap [$gStart,$gEnd] cannot be aligned between consecutive observations by timestamp" }
                    }
                    if ($boundary -ge 0) {
                        if (-not $usedBoundaries.Add([int]$boundary)) { AddViolation $gPath 'two recorded gaps align to the same observation boundary' }
                        else { $alignedGaps.Add([pscustomobject]@{ afterObs = [int]$boundary; start_ms = [long]$gStart; end_ms = [long]$gEnd; elapsed_ms = $gElapsed; missed_samples = $gMissed; reacquired_by = $gReacq }) }
                    }
                }
            }
            $gapsSorted = $alignedGaps.ToArray()
            [System.Array]::Sort($gapsSorted, [System.Comparison[object]] { param($a, $b) ([int]$a.afterObs).CompareTo([int]$b.afterObs) })
            if ($null -ne $tid -and $null -ne $tCls) {
                $normTracks.Add([pscustomobject]@{ track_id = [long]$tid; class = $tCls; scene_index = $tScene; obs = $obsSorted; gaps = $gapsSorted })
            }
        }
    }
    $trackArrSorted = $normTracks.ToArray()
    [System.Array]::Sort($trackArrSorted, [System.Comparison[object]] { param($a, $b) ([long]$a.track_id).CompareTo([long]$b.track_id) })

    # ---- transcript (optional; #11 shape) ----
    $transcriptProvided = $false
    $normSpeech = New-Object System.Collections.Generic.List[object]
    if ((Has $manifest 'transcript') -and $null -ne $manifest.transcript) {
        $transcriptProvided = $true
        $txRaw = $manifest.transcript
        $segArr = @()
        if ($txRaw -is [System.Array] -or $txRaw -is [System.Collections.IList]) { $segArr = @($txRaw) }
        elseif (Has $txRaw 'segments') { $segArr = AsArray $txRaw.segments 'transcript.segments' }
        else { AddViolation 'transcript' 'must be a segment array or {segments:[...]}' }
        for ($i = 0; $i -lt @($segArr).Count; $i++) {
            $sg = @($segArr)[$i]
            $sgPath = "transcript.segments[$i]"
            $t0 = $null; $t1 = $null
            if (Has $sg 't0_ms') { $t0 = ReqInt $sg.t0_ms "$sgPath.t0_ms" 0 } elseif (Has $sg 'start_ms') { $t0 = ReqInt $sg.start_ms "$sgPath.start_ms" 0 } else { AddViolation "$sgPath" 'required t0_ms (or start_ms) is missing' }
            if (Has $sg 't1_ms') { $t1 = ReqInt $sg.t1_ms "$sgPath.t1_ms" 0 } elseif (Has $sg 'end_ms')   { $t1 = ReqInt $sg.end_ms "$sgPath.end_ms" 0 }   else { AddViolation "$sgPath" 'required t1_ms (or end_ms) is missing' }
            if ($null -ne $t0 -and $null -ne $t1 -and $t1 -lt $t0) { AddViolation $sgPath "t1_ms ($t1) precedes t0_ms ($t0)" }
            $txt = $null
            if (-not (Has $sg 'text')) { AddViolation "$sgPath.text" 'required text is missing' }
            elseif ($null -eq $sg.text -or -not ($sg.text -is [string])) { AddViolation "$sgPath.text" 'must be a string' }
            else { $txt = [string]$sg.text }
            if ($null -ne $t0 -and $null -ne $t1 -and $null -ne $txt) {
                $normSpeech.Add([pscustomobject]@{ start_ms = [long]$t0; end_ms = [long]$t1; text = $txt })
            }
        }
    }

    # ---- ocr (optional; per-keyframe entries) ----
    $ocrProvided = $false
    $normOcr = New-Object System.Collections.Generic.List[object]
    if ((Has $manifest 'ocr') -and $null -ne $manifest.ocr) {
        $ocrProvided = $true
        $ocRaw = $manifest.ocr
        $ocArr = @()
        if ($ocRaw -is [System.Array] -or $ocRaw -is [System.Collections.IList]) { $ocArr = @($ocRaw) }
        elseif (Has $ocRaw 'entries') { $ocArr = AsArray $ocRaw.entries 'ocr.entries' }
        else { AddViolation 'ocr' 'must be an entry array or {entries:[...]}' }
        for ($i = 0; $i -lt @($ocArr).Count; $i++) {
            $oe = @($ocArr)[$i]
            $oePath = "ocr[$i]"
            $ts = $null
            if ((Has $oe 'timestamp_ms') -and $null -ne $oe.timestamp_ms) {
                $ts = ReqInt $oe.timestamp_ms "$oePath.timestamp_ms" 0
            } elseif ((Has $oe 'frame_index') -and $null -ne $oe.frame_index) {
                $fi = ReqInt $oe.frame_index "$oePath.frame_index" 0
                if ($null -ne $fi) {
                    if (-not $samplesProvided) {
                        AddViolation "$oePath.frame_index" "entry is keyed by frame_index ($fi) but no sample manifest was provided to map it to a timestamp -- REFUSED (timestamps are never invented)"
                    } elseif (-not $sampleByFrame.ContainsKey([long]$fi)) {
                        AddViolation "$oePath.frame_index" "frame_index $fi is not listed in the sample manifest -- REFUSED (timestamps are never invented)"
                    } else {
                        $ts = [long]$sampleByFrame[[long]$fi].timestamp_ms
                    }
                }
            } else {
                AddViolation $oePath 'requires timestamp_ms or frame_index'
            }
            $lineTexts = New-Object System.Collections.Generic.List[string]
            if (-not (Has $oe 'lines') -or $null -eq $oe.lines) {
                AddViolation "$oePath.lines" 'required lines array is missing'
            } else {
                $lnArr = AsArray $oe.lines "$oePath.lines"
                for ($li = 0; $li -lt @($lnArr).Count; $li++) {
                    $ln = @($lnArr)[$li]
                    if (-not (Has $ln 'text') -or $null -eq $ln.text -or -not ($ln.text -is [string])) { AddViolation "$oePath.lines[$li].text" 'required text (string) is missing' }
                    else { $lineTexts.Add([string]$ln.text) }
                }
            }
            if ($null -ne $ts) {
                $normOcr.Add([pscustomobject]@{ timestamp_ms = [long]$ts; text = ($lineTexts.ToArray() -join "`n"); line_count = [long]$lineTexts.Count })
            }
        }
    }

    # ---- detections (optional; per-sample entries) ----
    $detectionsProvided = $false
    $normDet = New-Object System.Collections.Generic.List[object]
    if ((Has $manifest 'detections') -and $null -ne $manifest.detections) {
        $detectionsProvided = $true
        $dtRaw = $manifest.detections
        $dtArr = @()
        if ($dtRaw -is [System.Array] -or $dtRaw -is [System.Collections.IList]) { $dtArr = @($dtRaw) }
        elseif (Has $dtRaw 'entries') { $dtArr = AsArray $dtRaw.entries 'detections.entries' }
        else { AddViolation 'detections' 'must be an entry array or {entries:[...]}' }
        for ($i = 0; $i -lt @($dtArr).Count; $i++) {
            $de = @($dtArr)[$i]
            $dePath = "detections[$i]"
            $ts = $null
            if (-not (Has $de 'timestamp_ms')) { AddViolation "$dePath.timestamp_ms" 'required timestamp_ms is missing' } else { $ts = ReqInt $de.timestamp_ms "$dePath.timestamp_ms" 0 }
            $sIdx = OptInt $de 'sample_index' $dePath 0
            $classCounts = [System.Collections.Generic.SortedDictionary[string,long]]::new([System.StringComparer]::Ordinal)
            if (-not (Has $de 'detections') -or $null -eq $de.detections) {
                AddViolation "$dePath.detections" 'required detections array is missing'
            } else {
                $dArr = AsArray $de.detections "$dePath.detections"
                for ($di = 0; $di -lt @($dArr).Count; $di++) {
                    $d = @($dArr)[$di]
                    $dPath = "$dePath.detections[$di]"
                    $cls = $null
                    if (-not (Has $d 'class')) { AddViolation "$dPath.class" 'required class is missing' } else { $cls = ReqStr $d.class "$dPath.class" }
                    if (-not (Has $d 'box') -or $null -eq $d.box) { AddViolation "$dPath.box" 'required box is missing' }
                    else {
                        foreach ($bk in @('x', 'y', 'width', 'height')) {
                            if (-not (Has $d.box $bk)) { AddViolation "$dPath.box.$bk" 'required box field is missing' }
                            elseif ($null -eq (ReqNum $d.box.$bk "$dPath.box.$bk")) { }
                        }
                    }
                    if ((Has $d 'score') -and $null -ne $d.score) { [void](ReqNum $d.score "$dPath.score") }
                    if ($null -ne $cls) {
                        if ($classCounts.ContainsKey($cls)) { $classCounts[$cls] = $classCounts[$cls] + 1 } else { $classCounts[$cls] = [long]1 }
                    }
                }
            }
            if ($null -ne $ts) {
                # cross-check sample_index vs the sample manifest when both are present
                if ($null -ne $sIdx -and $samplesProvided) {
                    if (-not $sampleByIndex.ContainsKey([long]$sIdx)) { AddViolation "$dePath.sample_index" "sample_index $sIdx is not listed in the sample manifest" }
                    elseif ([long]$sampleByIndex[[long]$sIdx].timestamp_ms -ne [long]$ts) { AddViolation "$dePath.timestamp_ms" "timestamp_ms $ts disagrees with the sample manifest's $($sampleByIndex[[long]$sIdx].timestamp_ms) for sample_index $sIdx" }
                }
                $ccOrdered = [ordered]@{}
                foreach ($kv in $classCounts.GetEnumerator()) { $ccOrdered[$kv.Key] = [long]$kv.Value }
                $normDet.Add([pscustomobject]@{ timestamp_ms = [long]$ts; sample_index = $sIdx; class_counts = $ccOrdered })
            }
        }
    }

    # ---- FAIL CLOSED on any violation ----
    if ($script:violations.Count -gt 0) {
        $result = [ordered]@{ violations = @($script:violations.ToArray() | ForEach-Object { [ordered]@{ path = $_.path; why = $_.why } }) }
        throw (New-SkillError 'input_validation_failed' "input validation failed with $($script:violations.Count) violation(s); see result.violations")
    }

    # ================================ 2. FUSE ================================

    # ---- coverage (from the sample manifest; honest degradation when absent) ----
    $presenceSemantics = if ($samplesProvided) { 'observed_vs_unsampled_distinguishable' } else { 'downgraded_no_sample_manifest' }
    if (-not $samplesProvided -and $tracksProvided) {
        $warnings.Add('presence semantics downgraded: tracks provided without a sample manifest -- "sampled with no detection" vs "not sampled" is NOT distinguishable in this timeline')
    }
    $covSamples = New-Object System.Collections.Generic.List[object]
    foreach ($sm in $sampleArrSorted) {
        $covSamples.Add([ordered]@{ detection_count = $sm.detection_count; frame_index = [long]$sm.frame_index; sample_index = [long]$sm.sample_index; scene_index = $sm.scene_index; timestamp_ms = [long]$sm.timestamp_ms })
    }
    $covSpan = $null; $coverageMs = $null
    if ($sampleArrSorted.Count -gt 0) {
        $tsMin = [long]$sampleArrSorted[0].timestamp_ms; $tsMax = [long]$sampleArrSorted[0].timestamp_ms
        foreach ($sm in $sampleArrSorted) {
            if ([long]$sm.timestamp_ms -lt $tsMin) { $tsMin = [long]$sm.timestamp_ms }
            if ([long]$sm.timestamp_ms -gt $tsMax) { $tsMax = [long]$sm.timestamp_ms }
        }
        $coverageMs = $tsMax - $tsMin
        $covSpan = [ordered]@{ coverage_ms = [long]$coverageMs; first_sample_ms = [long]$tsMin; last_sample_ms = [long]$tsMax }
    }
    $coverage = [ordered]@{
        presence_semantics = $presenceSemantics
        sample_count = [long]$sampleArrSorted.Count
        samples = $covSamples.ToArray()
        samples_source = $samplesSource
        span = $covSpan
        status = $(if ($samplesProvided) { 'sampled' } else { 'unknown' })
    }

    # ---- scenes (canonical) ----
    $canonScenes = New-Object System.Collections.Generic.List[object]
    foreach ($sc in $sceneArrSorted) {
        $canonScenes.Add([ordered]@{ end_ms = [long]$sc.end_ms; scene_index = [long]$sc.scene_index; start_ms = [long]$sc.start_ms })
    }

    # ---- intervals: per-track APPEARANCE SEGMENTATION (split at recorded gaps; NEVER merge across a gap) ----
    $intervals = New-Object System.Collections.Generic.List[object]
    $spanCount = 0; $gapIntervalCount = 0
    $classTrackCounts = [System.Collections.Generic.SortedDictionary[string,long]]::new([System.StringComparer]::Ordinal)
    foreach ($tr in $trackArrSorted) {
        if ($classTrackCounts.ContainsKey([string]$tr.class)) { $classTrackCounts[[string]$tr.class] = $classTrackCounts[[string]$tr.class] + 1 } else { $classTrackCounts[[string]$tr.class] = [long]1 }
        $obs = @($tr.obs)
        $gapAt = @{}
        foreach ($g in @($tr.gaps)) { $gapAt[[int]$g.afterObs] = $g }
        $segStart = 0
        for ($k = 0; $k -le ($obs.Count - 1); $k++) {
            $isLast = ($k -eq ($obs.Count - 1))
            $splitHere = (-not $isLast) -and $gapAt.ContainsKey([int]$k)
            if ($isLast -or $splitHere) {
                # close the presence segment obs[segStart..k]
                $seg = @($obs[$segStart..$k])
                $scoreQs = New-Object System.Collections.Generic.List[long]
                $lowCount = 0; $iouLinks = 0; $centroidLinks = 0; $reacq = 0
                $weakest = $null; $maxGapMs = $null
                for ($m = 0; $m -lt $seg.Count; $m++) {
                    $ob = $seg[$m]
                    if ($null -ne $ob.detection_score_q) { $scoreQs.Add([long]$ob.detection_score_q) }
                    if ([bool]$ob.low_confidence) { $lowCount++ }
                    $kind = $ob.assoc_kind
                    if ($kind -eq 'iou' -or $kind -eq 'centroid') {
                        if ($kind -eq 'iou') { $iouLinks++ } else { $centroidLinks++ }
                        if ($m -eq 0 -and $segStart -gt 0) { $reacq++ }   # the first obs after a recorded gap is the reacquisition link
                        $q = if ($null -ne $ob.iou_q) { [long]$ob.iou_q } else { [long]0 }   # a centroid link's IoU is 0 by construction
                        if ($null -eq $weakest -or $q -lt $weakest) { $weakest = $q }
                        if ($null -ne $ob.gap_ms) { if ($null -eq $maxGapMs -or [long]$ob.gap_ms -gt $maxGapMs) { $maxGapMs = [long]$ob.gap_ms } }
                    }
                }
                $meanQ = $null; $minQ = $null; $maxQ = $null
                if ($scoreQs.Count -gt 0) {
                    $sum = [long]0; $minQ = [long]$scoreQs[0]; $maxQ = [long]$scoreQs[0]
                    foreach ($q in $scoreQs) { $sum += $q; if ($q -lt $minQ) { $minQ = $q }; if ($q -gt $maxQ) { $maxQ = $q } }
                    $meanQ = RoundHalfUp ([double]$sum / [double]$scoreQs.Count)
                }
                $intervals.Add([ordered]@{
                    kind = 'track_presence'
                    track_id = [long]$tr.track_id
                    class = [string]$tr.class
                    scene_index = $tr.scene_index
                    start_ms = [long]$seg[0].timestamp_ms
                    end_ms = [long]$seg[$seg.Count - 1].timestamp_ms
                    observation_count = [long]$seg.Count
                    evidence = [ordered]@{
                        association = [ordered]@{
                            centroid_link_count = [long]$centroidLinks
                            iou_link_count = [long]$iouLinks
                            maximum_gap_ms = $maxGapMs
                            reacquisition_count = [long]$reacq
                            weakest_link_quality_q = $weakest
                        }
                        detection = [ordered]@{
                            low_confidence_count = [long]$lowCount
                            max_detection_score_q = $maxQ
                            mean_detection_score_q = $meanQ
                            min_detection_score_q = $minQ
                        }
                    }
                })
                $spanCount++
                if ($splitHere) {
                    $g = $gapAt[[int]$k]
                    $intervals.Add([ordered]@{
                        kind = 'track_gap'
                        track_id = [long]$tr.track_id
                        start_ms = [long]$g.start_ms
                        end_ms = [long]$g.end_ms
                        elapsed_ms = $g.elapsed_ms
                        missed_samples = $g.missed_samples
                        reacquired_by = $g.reacquired_by
                    })
                    $gapIntervalCount++
                    $segStart = $k + 1
                }
            }
        }
    }
    $intervalArr = $intervals.ToArray()   # already deterministic: tracks by id, per-track chronological

    # ---- events (content-canonical order: (sort_time, kind, canonical bytes)) ----
    $eventsPre = New-Object System.Collections.Generic.List[object]   # @{t; kind; obj}
    foreach ($sp in $normSpeech.ToArray()) {
        $eventsPre.Add([pscustomobject]@{ t = [long]$sp.start_ms; kind = 'speech'; obj = [ordered]@{ end_ms = [long]$sp.end_ms; kind = 'speech'; start_ms = [long]$sp.start_ms; text = [string]$sp.text } })
    }
    foreach ($oe in $normOcr.ToArray()) {
        $eventsPre.Add([pscustomobject]@{ t = [long]$oe.timestamp_ms; kind = 'ocr_text'; obj = [ordered]@{ kind = 'ocr_text'; line_count = [long]$oe.line_count; text = [string]$oe.text; timestamp_ms = [long]$oe.timestamp_ms } })
    }
    foreach ($de in $normDet.ToArray()) {
        $eventsPre.Add([pscustomobject]@{ t = [long]$de.timestamp_ms; kind = 'detection_sample'; obj = [ordered]@{ class_counts = $de.class_counts; kind = 'detection_sample'; sample_index = $de.sample_index; timestamp_ms = [long]$de.timestamp_ms } })
    }
    foreach ($sc in $sceneArrSorted) {
        $eventsPre.Add([pscustomobject]@{ t = [long]$sc.start_ms; kind = 'scene_cut'; obj = [ordered]@{ kind = 'scene_cut'; scene_index = [long]$sc.scene_index; timestamp_ms = [long]$sc.start_ms } })
    }
    $eventsTagged = New-Object System.Collections.Generic.List[object]
    foreach ($ev in $eventsPre.ToArray()) {
        $eventsTagged.Add([pscustomobject]@{ t = [long]$ev.t; kind = [string]$ev.kind; canon = (ConvertTo-CanonicalJson $ev.obj); obj = $ev.obj })
    }
    $eventArrTagged = $eventsTagged.ToArray()
    [System.Array]::Sort($eventArrTagged, [System.Comparison[object]] {
        param($a, $b)
        if ([long]$a.t -ne [long]$b.t) { return ([long]$a.t).CompareTo([long]$b.t) }
        $kc = [string]::CompareOrdinal([string]$a.kind, [string]$b.kind)
        if ($kc -ne 0) { return $kc }
        return [string]::CompareOrdinal([string]$a.canon, [string]$b.canon)
    })
    $eventObjs = New-Object System.Collections.Generic.List[object]
    foreach ($ev in $eventArrTagged) { $eventObjs.Add($ev.obj) }
    $eventArr = $eventObjs.ToArray()

    # ---- index (refs are positions into intervals[]/events[]) ----
    $byKind = [ordered]@{}
    foreach ($k in @('detection_sample', 'ocr_text', 'scene_cut', 'speech', 'track_gap', 'track_presence')) {
        $byKind[$k] = [ordered]@{ events = (New-Object System.Collections.Generic.List[object]); intervals = (New-Object System.Collections.Generic.List[object]) }
    }
    $byTrack = @{}
    $byClassIv = @{}
    $byClassEv = @{}
    $bySceneI = @{}
    $bySceneE = @{}
    foreach ($sc in $sceneArrSorted) { $bySceneI[[long]$sc.scene_index] = New-Object System.Collections.Generic.List[object]; $bySceneE[[long]$sc.scene_index] = New-Object System.Collections.Generic.List[object] }
    function Add-ToMapList([hashtable]$map, $key, [long]$idx) {
        if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.Generic.List[object] }
        $map[$key].Add([long]$idx)
    }
    for ($i = 0; $i -lt $intervalArr.Count; $i++) {
        $iv = $intervalArr[$i]
        $k = [string]$iv['kind']
        ($byKind[$k]['intervals']).Add([long]$i)
        Add-ToMapList $byTrack ([long]$iv['track_id']) $i
        if ($k -eq 'track_presence') {
            Add-ToMapList $byClassIv ([string]$iv['class']) $i
            if ($null -ne $iv['scene_index'] -and $bySceneI.ContainsKey([long]$iv['scene_index'])) { ($bySceneI[[long]$iv['scene_index']]).Add([long]$i) }
        } else {
            # a gap belongs to its track's scene (tracks are scene-scoped); resolve via the track's scene_index
            foreach ($tr in $trackArrSorted) {
                if ([long]$tr.track_id -eq [long]$iv['track_id']) {
                    if ($null -ne $tr.scene_index -and $bySceneI.ContainsKey([long]$tr.scene_index)) { ($bySceneI[[long]$tr.scene_index]).Add([long]$i) }
                    break
                }
            }
        }
    }
    for ($i = 0; $i -lt $eventArr.Count; $i++) {
        $ev = $eventArr[$i]
        $k = [string]$ev['kind']
        ($byKind[$k]['events']).Add([long]$i)
        if ($k -eq 'detection_sample') {
            foreach ($cls in @($ev['class_counts'].Keys)) { Add-ToMapList $byClassEv ([string]$cls) $i }
        }
        # scene containment by [start_ms, end_ms) on the event's time
        $t = if ($k -eq 'speech') { [long]$ev['start_ms'] } else { [long]$ev['timestamp_ms'] }
        foreach ($sc in $sceneArrSorted) {
            if ($t -ge [long]$sc.start_ms -and $t -lt [long]$sc.end_ms) { ($bySceneE[[long]$sc.scene_index]).Add([long]$i) }
        }
    }
    $byKindOut = [ordered]@{}
    foreach ($k in @($byKind.Keys)) { $byKindOut[$k] = [ordered]@{ events = ($byKind[$k]['events']).ToArray(); intervals = ($byKind[$k]['intervals']).ToArray() } }
    $byTrackOut = [ordered]@{}
    foreach ($tk in @($byTrack.Keys)) { $byTrackOut[([long]$tk).ToString([Globalization.CultureInfo]::InvariantCulture)] = [ordered]@{ intervals = ($byTrack[$tk]).ToArray() } }
    $classKeys = New-Object System.Collections.Generic.List[string]
    foreach ($ck in @($byClassIv.Keys)) { if (-not $classKeys.Contains([string]$ck)) { $classKeys.Add([string]$ck) } }
    foreach ($ck in @($byClassEv.Keys)) { if (-not $classKeys.Contains([string]$ck)) { $classKeys.Add([string]$ck) } }
    $classKeyArr = $classKeys.ToArray()
    [System.Array]::Sort($classKeyArr, [System.StringComparer]::Ordinal)
    $byClassOut = [ordered]@{}
    foreach ($ck in $classKeyArr) {
        $ivRefs = @(); if ($byClassIv.ContainsKey($ck)) { $ivRefs = ($byClassIv[$ck]).ToArray() }
        $evRefs = @(); if ($byClassEv.ContainsKey($ck)) { $evRefs = ($byClassEv[$ck]).ToArray() }
        $byClassOut[[string]$ck] = [ordered]@{ events = $evRefs; intervals = $ivRefs }
    }
    $bySceneOut = [ordered]@{}
    foreach ($sc in $sceneArrSorted) {
        $skey = ([long]$sc.scene_index).ToString([Globalization.CultureInfo]::InvariantCulture)
        $bySceneOut[$skey] = [ordered]@{ events = ($bySceneE[[long]$sc.scene_index]).ToArray(); intervals = ($bySceneI[[long]$sc.scene_index]).ToArray() }
    }
    $index = [ordered]@{ by_class = $byClassOut; by_kind = $byKindOut; by_scene = $bySceneOut; by_track = $byTrackOut }

    # ---- summary ----
    $evCounts = [ordered]@{ detection_sample = [long]0; ocr_text = [long]0; scene_cut = [long]0; speech = [long]0 }
    foreach ($ev in $eventArr) { $k = [string]$ev['kind']; $evCounts[$k] = [long]$evCounts[$k] + 1 }
    $classOut = [ordered]@{}
    foreach ($kv in $classTrackCounts.GetEnumerator()) { $classOut[$kv.Key] = [long]$kv.Value }
    $summary = [ordered]@{
        class_track_counts = $classOut
        coverage_ms = $coverageMs
        event_counts = $evCounts
        interval_counts = [ordered]@{ track_gap = [long]$gapIntervalCount; track_presence = [long]$spanCount }
        scene_count = [long]$sceneArrSorted.Count
        span_count = [long]$spanCount
        track_count = [long]$trackArrSorted.Count
    }

    # ---- input_digest: sha256 over the CANONICAL bytes of the normalized inputs (presentation-order-free) ----
    $normTracksCanon = New-Object System.Collections.Generic.List[object]
    foreach ($tr in $trackArrSorted) {
        $obsC = New-Object System.Collections.Generic.List[object]
        foreach ($ob in @($tr.obs)) {
            $obsC.Add([ordered]@{ assoc_kind = $ob.assoc_kind; detection_score_q = $ob.detection_score_q; frame_index = $ob.frame_index; gap_ms = $ob.gap_ms; iou_q = $ob.iou_q; low_confidence = [bool]$ob.low_confidence; sample_index = [long]$ob.sample_index; timestamp_ms = [long]$ob.timestamp_ms })
        }
        $gapsC = New-Object System.Collections.Generic.List[object]
        foreach ($g in @($tr.gaps)) {
            $gapsC.Add([ordered]@{ after_obs = [long][int]$g.afterObs; elapsed_ms = $g.elapsed_ms; end_ms = [long]$g.end_ms; missed_samples = $g.missed_samples; reacquired_by = $g.reacquired_by; start_ms = [long]$g.start_ms })
        }
        $normTracksCanon.Add([ordered]@{ class = [string]$tr.class; gaps = $gapsC.ToArray(); observations = $obsC.ToArray(); scene_index = $tr.scene_index; track_id = [long]$tr.track_id })
    }
    $speechCanon = New-Object System.Collections.Generic.List[object]
    foreach ($sp in $normSpeech.ToArray()) { $speechCanon.Add([ordered]@{ end_ms = [long]$sp.end_ms; start_ms = [long]$sp.start_ms; text = [string]$sp.text }) }
    $ocrCanon = New-Object System.Collections.Generic.List[object]
    foreach ($oe in $normOcr.ToArray()) { $ocrCanon.Add([ordered]@{ line_count = [long]$oe.line_count; text = [string]$oe.text; timestamp_ms = [long]$oe.timestamp_ms }) }
    $detCanon = New-Object System.Collections.Generic.List[object]
    foreach ($de in $normDet.ToArray()) { $detCanon.Add([ordered]@{ class_counts = $de.class_counts; sample_index = $de.sample_index; timestamp_ms = [long]$de.timestamp_ms }) }
    # content-canonical order for the digest of unordered inputs
    $speechArrC = $speechCanon.ToArray(); $ocrArrC = $ocrCanon.ToArray(); $detArrC = $detCanon.ToArray()
    $cmpCanon = [System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal((ConvertTo-CanonicalJson $a), (ConvertTo-CanonicalJson $b)) }
    [System.Array]::Sort($speechArrC, $cmpCanon)
    [System.Array]::Sort($ocrArrC, $cmpCanon)
    [System.Array]::Sort($detArrC, $cmpCanon)
    $normInputsDoc = [ordered]@{
        detections = $detArrC
        media = [ordered]@{ duration_ms = $durationMs; frame_height = $frameH; frame_width = $frameW; media_id = $mediaId; source_media_sha256 = $mediaSha }
        ocr = $ocrArrC
        samples = $covSamples.ToArray()
        scenes = $canonScenes.ToArray()
        tracks = [ordered]@{ identity_scope = $identityScope; provided = $tracksProvided; tracks = $normTracksCanon.ToArray() }
        transcript = $speechArrC
    }
    $digestHex = Get-Sha256Hex ($utf8.GetBytes((ConvertTo-CanonicalJson $normInputsDoc)))
    $inputDigest = 'sha256:' + $digestHex

    # ---- the canonical timeline document ----
    $timeline = [ordered]@{
        coverage = $coverage
        events = $eventArr
        generator = [ordered]@{ name = $SKILL_ID; params = [ordered]@{}; version = $SKILL_VERSION }
        identity_scope = $identityScope
        index = $index
        input_digest = $inputDigest
        intervals = $intervalArr
        scenes = $canonScenes.ToArray()
        schema = $TIMELINE_SCHEMA
        source = [ordered]@{ duration_ms = $durationMs; frame_height = $frameH; frame_width = $frameW; media_id = $mediaId; source_media_sha256 = $mediaSha }
        summary = $summary
        timestamp_unit = 'ms'
    }
    $canonicalText = (ConvertTo-CanonicalJson $timeline) + "`n"
    $timelinePath = Join-Path $invDir 'timeline.json'
    [System.IO.File]::WriteAllText($timelinePath, $canonicalText, $utf8)
    $producedFiles.Add([pscustomobject]@{ p = $timelinePath; k = 'json' })
    $canonicalBytes = [System.IO.File]::ReadAllBytes($timelinePath)
    $timelineSha = Get-Sha256Hex $canonicalBytes

    $inputsDigest = $inputDigest
    $result = [ordered]@{
        input = [ordered]@{
            source = $source
            path = $inFull
            provided = [ordered]@{ detections = $detectionsProvided; media = $true; ocr = $ocrProvided; samples = $samplesProvided; scenes = $scenesProvided; tracks = $tracksProvided; transcript = $transcriptProvided }
        }
        schema = $TIMELINE_SCHEMA
        timeline = [ordered]@{ path = $timelinePath; sha256 = $timelineSha; bytes = [long]$canonicalBytes.Length }
        input_digest = $inputDigest
        identity_scope = $identityScope
        coverage_status = [string]$coverage['status']
        presence_semantics = $presenceSemantics
        summary = $summary
        violations = @()
    }
    Write-Diag "ok scenes=$($sceneArrSorted.Count) samples=$($sampleArrSorted.Count) tracks=$($trackArrSorted.Count) intervals=$($intervalArr.Count) events=$($eventArr.Count) sha=$timelineSha"
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
    if ($script:violations.Count -gt 0) {
        foreach ($v in $script:violations.ToArray()) { Write-Diag "violation: $($v.path) -- $($v.why)" }
        if ($null -eq $result) { $result = [ordered]@{ violations = @($script:violations.ToArray() | ForEach-Object { [ordered]@{ path = $_.path; why = $_.why } }) } }
    }
}

# ---- artifacts + human summary ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($status -ne 'error' -and $null -ne $result) {
        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine('# video.timeline')
        [void]$mb.AppendLine("source: $($result.input.source)  coverage: $($result.coverage_status)  presence_semantics: $($result.presence_semantics)")
        [void]$mb.AppendLine("scenes: $($result.summary.scene_count)  tracks: $($result.summary.track_count)  presence spans: $($result.summary.span_count)  gaps: $($result.summary.interval_counts.track_gap)  events: $(([long]$result.summary.event_counts.speech + [long]$result.summary.event_counts.ocr_text + [long]$result.summary.event_counts.detection_sample + [long]$result.summary.event_counts.scene_cut))")
        [void]$mb.AppendLine("timeline sha256: $($result.timeline.sha256)")
        [void]$mb.AppendLine('')
        [void]$mb.AppendLine('| kind | count |')
        [void]$mb.AppendLine('|---|---|')
        [void]$mb.AppendLine("| track_presence | $($result.summary.interval_counts.track_presence) |")
        [void]$mb.AppendLine("| track_gap | $($result.summary.interval_counts.track_gap) |")
        [void]$mb.AppendLine("| speech | $($result.summary.event_counts.speech) |")
        [void]$mb.AppendLine("| ocr_text | $($result.summary.event_counts.ocr_text) |")
        [void]$mb.AppendLine("| detection_sample | $($result.summary.event_counts.detection_sample) |")
        [void]$mb.AppendLine("| scene_cut | $($result.summary.event_counts.scene_cut) |")
        if ($warnings.Count -gt 0) { [void]$mb.AppendLine(''); [void]$mb.AppendLine("warnings: $((@($warnings.ToArray())) -join '; ')") }
        $mdPath = Join-Path $invDir 'timeline.md'
        [System.IO.File]::WriteAllText($mdPath, $mb.ToString(), $utf8)
        $producedFiles.Add([pscustomobject]@{ p = $mdPath; k = 'markdown' })
    }
    foreach ($a in $producedFiles.ToArray()) {
        if (Test-Path -LiteralPath $a.p -PathType Leaf) {
            $b = [System.IO.File]::ReadAllBytes($a.p)
            $artifacts += , ([ordered]@{ path = (Resolve-Path -LiteralPath $a.p).Path; kind = $a.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[video.timeline] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

if ($status -eq 'ok' -and $warnings.Count -gt 0) { $status = 'partial' }

$diag = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
foreach ($k in @($diagExtra.Keys)) { $diag[$k] = $diagExtra[$k] }

$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds
    inputs_digest = $(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result = $result; confidence = $confidence; artifacts = $artifacts; model_provenance = $modelProvenance
    diagnostics = $diag
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
