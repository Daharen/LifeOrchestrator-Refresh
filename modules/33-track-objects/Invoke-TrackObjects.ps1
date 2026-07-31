#requires -Version 7.0
<#
.SYNOPSIS
  track.objects -- associate per-frame object detections into stable identity tracks (Life Orchestrator,
  contract v0.2). The SECOND module of the Phase C video spine (architectural position 20), following
  media.decompose #32 (position 19).
.DESCRIPTION
  Given a sequence of PER-FRAME object detections in the detect.objects #16 output shape (each detection
  {class, class_id, score, box{x,y,width,height}}), it associates them across frames so the same object
  keeps ONE track_id. TWO tracker modes (skill 0.2.0):

  -Mode stable (THE DEFAULT, new in 0.2.0) -- a DETERMINISTIC GEOMETRIC ASSOCIATION tracker built for the
  sparse, irregularly-timed keyframes media.decompose #32 actually emits, per the folded frontier design
  review (core-docs/research/2026-07-30-track-objects-design-review.md):
    * scene-boundary HARD separation -- never associate across a known cut (death_reason scene_boundary);
      scenes come from per-frame scene_index and/or a scenes[] list (the #32 seconds shape accepted);
      scene info absent -> warn + a documented more-conservative max gap;
    * elapsed-TIME aging -- a track terminates on max_gap_ms (real elapsed ms since last observation) OR
      max_missed_samples (processed samples with no match), whichever first; frame_index = provenance only;
    * exact-class matching -- one immutable class per track, separate cost matrix per class;
    * two explicit association tiers: tier 1 = IoU on quantized integer boxes (>= iou_threshold);
      tier 2 = a TIGHTLY-GATED normalized-centroid fallback ONLY when integer IoU == 0 (class+scene match,
      elapsed <= max_gap_ms, squared-integer normalized displacement within a time-growing hard-capped
      allowance, cross-multiplied area-ratio sanity gate). IoU edges STRICTLY outrank fallback edges;
    * deterministic GLOBAL one-to-one assignment per class per scene via a small pinned integer-cost
      Hungarian in pure PowerShell (no SciPy, no binary dep); THE TIE RULE IS CONTRACT: among
      equal-min-total-cost assignments pick the lexicographically smallest ordered (track_id,
      detection_rank) list;
    * fixed-point THROUGHOUT (boxes in integer milli-pixels, scores in integer millionths, timestamps in
      integer ms; squared integer distances; cross-multiplied ratio compares; no sqrt, no float epsilon,
      no NaN); canonical-JSON output SPLIT from a diagnostics envelope (no volatile fields in the
      canonical bytes).
  Emits the RICHER track schema video.timeline (arch position 21) consumes: file-level metadata +
  identity_scope + tracker_params + input_digest, a samples[] manifest of EVERY processed sample,
  track-level lifecycle + termination + SEPARATED detection/association evidence, per-link association
  records, and first-class gap records (coast boxes are NEVER fabricated). See SCHEMA_NOTES.md.

  -Mode greedy -- the i17 baseline tracker RETAINED BYTE-IDENTICAL (regression oracle / debug path): a
  deterministic, per-class, frame-by-frame greedy IoU matcher with birth / constant-position coast /
  age-out death and monotonic ids. Its tracks.json output is byte-identical to skill 0.1.0.

  No model, no CUDA, no loopback port, no randomness -> CPU-only, parallel_safe:true, and byte-identical
  for identical input in BOTH modes. Both modes are DECOUPLED from live detection: they read detections
  from a JSON file (or inline via -InputsJson.frames), NOT from a live #16/#32 run (live composition is a
  named follow-on). Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; exits 0
  whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json
  pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\detections.json -Mode greedy -MaxAge 3
  pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputFile .\d.json -MaxGapMs 3000 -MaxMissedSamples 2
  pwsh -NoProfile -File .\Invoke-TrackObjects.ps1 -InputsJson '{"input":"d.json","mode":"stable","scenes":[{"index":0,"start":0.0,"end":4.0}]}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Mode = 'stable',
    [double]$IouThreshold = 0.3,
    [int]$MaxAge = 2,
    [double]$MinScore = 0.0,
    [string[]]$Classes,
    [int]$MaxGapMs = 5000,
    [int]$MaxMissedSamples = 3,
    [int]$NoSceneMaxGapMs = 2000,
    [double]$CentroidBaseAllowance = 0.25,
    [double]$CentroidAllowancePerSecond = 0.25,
    [double]$CentroidMaxAllowance = 1.0,
    [double]$MaxAreaRatio = 4.0,
    [double]$LowConfidenceThreshold = 0.5,
    [string]$ScenesFile,
    [int]$FrameWidth = 0,
    [int]$FrameHeight = 0,
    [string]$SourceMediaId,
    [string]$SourceMediaSha256,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'track.objects'; $SKILL_VERSION = '0.2.0'; $CONTRACT = '0.2'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$TRACKS_SCHEMA_GREEDY = 'lifeorch.track.objects/0.1'
$TRACKS_SCHEMA_STABLE = 'lifeorch.track.objects/0.2'
$ALGORITHM_STABLE = 'stable-geometric-association/1'
$LINK_QUALITY_FORMULA = 'link_quality/1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
$bound = $PSBoundParameters
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

$SCALE_BOX = [long]1000          # milli-pixels
$SCALE_Q = [long]1000000         # millionths (scores, ratios, IoU)
$EDGE_INF = [long]1000000000000  # forbidden-edge cost (1e12); >> any real total, << long overflow

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

# ============================ fixed-point helpers (stable mode) ============================
# Rounding contract: non-negative round-half-up toward +infinity: floor(v*scale + 0.5). The same
# expression is applied to any negative value (still rounds halves toward +infinity). Documented in
# SCHEMA_NOTES.md.
function Test-FiniteNumber($v) { return ($null -ne $v -and -not [double]::IsNaN([double]$v) -and -not [double]::IsInfinity([double]$v)) }
function QScale([double]$v, [long]$scale) {
    $s = $v * [double]$scale
    if ($s -gt 9.0e15 -or $s -lt -9.0e15) { throw (New-SkillError 'invalid_detection' "numeric value out of quantizable range: $v") }
    return [long][math]::Floor($s + 0.5)
}
function QMilli([double]$v) { return (QScale $v $SCALE_BOX) }
function QMillionths([double]$v) { return (QScale $v $SCALE_Q) }
function BigFloorDiv([bigint]$n, [bigint]$d) { return [System.Numerics.BigInteger]::Divide($n, $d) }  # non-negative use only
function BigRoundHalfUpDiv([bigint]$n, [bigint]$d) {
    # round-half-up of n/d for n>=0, d>0: floor((2n+d)/(2d))
    return [System.Numerics.BigInteger]::Divide((([bigint]2 * $n) + $d), ([bigint]2 * $d))
}
function ToIntegralLong($v, [string]$what) {
    $d = ToDouble $v
    if ($null -eq $d -or -not (Test-FiniteNumber $d)) { throw (New-SkillError 'invalid_detection' "$what must be an integer number") }
    $t = [math]::Floor($d)
    if ($t -ne $d) { throw (New-SkillError 'invalid_detection' "$what must be integral (got $v)") }
    return [long]$t
}

# ============================ canonical JSON (stable mode) ============================
# RFC 8785-style: UTF-8 no BOM, sorted keys (ordinal), compact separators, fixed array order, integers
# only (any float in the canonical tree is a defect -> throw), minimal escaping (backslash, quote,
# control chars as \u00XX), one trailing LF. See SCHEMA_NOTES.md.
function Write-CanonicalValue([System.Text.StringBuilder]$sb, $v) {
    if ($null -eq $v) { [void]$sb.Append('null'); return }
    if ($v -is [bool]) { [void]$sb.Append($(if ($v) { 'true' } else { 'false' })); return }
    if ($v -is [string]) {
        [void]$sb.Append('"')
        foreach ($ch in ([string]$v).ToCharArray()) {
            $code = [int]$ch
            if ($ch -eq '"') { [void]$sb.Append('\"') }
            elseif ($ch -eq '\') { [void]$sb.Append('\\') }
            elseif ($code -lt 0x20) { [void]$sb.Append('\u'); [void]$sb.Append($code.ToString('x4', [Globalization.CultureInfo]::InvariantCulture)) }
            else { [void]$sb.Append($ch) }
        }
        [void]$sb.Append('"')
        return
    }
    if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte] -or $v -is [uint32] -or $v -is [uint64]) {
        [void]$sb.Append(([Convert]::ToInt64($v)).ToString([Globalization.CultureInfo]::InvariantCulture)); return
    }
    if ($v -is [System.Numerics.BigInteger]) { [void]$sb.Append($v.ToString([Globalization.CultureInfo]::InvariantCulture)); return }
    if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) {
        throw (New-SkillError 'canonical_float' "canonical JSON forbids non-integer numerics (got $v)")
    }
    if ($v -is [System.Collections.IDictionary]) {
        # MUST be a real [string[]] before Sort: passing an object[] with a Comparison[string] makes
        # pwsh sort a CONVERTED COPY and silently leave the original unsorted (caught by the
        # double-run byte-identity gate: class_summary leaked per-process hashtable order).
        [string[]]$keys = @($v.Keys | ForEach-Object { [string]$_ })
        [System.Array]::Sort($keys, [System.Comparison[string]] { param($a, $b) [string]::CompareOrdinal($a, $b) })
        [void]$sb.Append('{')
        $first = $true
        foreach ($k in $keys) {
            if (-not $first) { [void]$sb.Append(',') }
            $first = $false
            Write-CanonicalValue $sb ([string]$k)
            [void]$sb.Append(':')
            Write-CanonicalValue $sb $v[$k]
        }
        [void]$sb.Append('}')
        return
    }
    if ($v -is [System.Management.Automation.PSCustomObject]) {
        $d = [ordered]@{}
        foreach ($p in $v.PSObject.Properties) { $d[$p.Name] = $p.Value }
        Write-CanonicalValue $sb $d
        return
    }
    if ($v -is [System.Collections.IEnumerable]) {
        [void]$sb.Append('[')
        $first = $true
        foreach ($e in $v) {
            if (-not $first) { [void]$sb.Append(',') }
            $first = $false
            Write-CanonicalValue $sb $e
        }
        [void]$sb.Append(']')
        return
    }
    throw (New-SkillError 'canonical_type' "canonical JSON cannot serialize type $($v.GetType().FullName)")
}
function ConvertTo-CanonicalJson($v) {
    $sb = [System.Text.StringBuilder]::new()
    Write-CanonicalValue $sb $v
    return $sb.ToString()
}
# Sanitize a passthrough object (detector_provenance) for the canonical tree: integral numbers -> long,
# non-integral numbers -> invariant string (+ a warning recorded by the caller), containers recursed.
function ConvertTo-CanonicalSafe($v, [System.Collections.Generic.List[string]]$warnSink) {
    if ($null -eq $v) { return $null }
    if ($v -is [bool] -or $v -is [string]) { return $v }
    if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte]) { return [long]$v }
    if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) {
        $d = [double]$v
        if ((Test-FiniteNumber $d) -and [math]::Floor($d) -eq $d -and [math]::Abs($d) -lt 9.0e15) { return [long]$d }
        $warnSink.Add("detector_provenance: non-integral number $($d.ToString('R', $inv)) stored as a string in the canonical file")
        return $d.ToString('R', $inv)
    }
    if ($v -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $v.Keys) { $o[[string]$k] = (ConvertTo-CanonicalSafe $v[$k] $warnSink) }
        return $o
    }
    if ($v -is [System.Management.Automation.PSCustomObject]) {
        $o = [ordered]@{}
        foreach ($p in $v.PSObject.Properties) { $o[$p.Name] = (ConvertTo-CanonicalSafe $p.Value $warnSink) }
        return $o
    }
    if ($v -is [System.Collections.IEnumerable]) {
        $acc = New-Object System.Collections.Generic.List[object]
        foreach ($e in $v) { $acc.Add((ConvertTo-CanonicalSafe $e $warnSink)) }
        return $acc.ToArray()
    }
    return [string]$v
}

# ============================ geometry (stable mode; integer milli-pixels) ============================
function Get-InterUnion([long]$ax, [long]$ay, [long]$aw, [long]$ah, [long]$bx, [long]$by, [long]$bw, [long]$bh) {
    $ax2 = $ax + $aw; $ay2 = $ay + $ah; $bx2 = $bx + $bw; $by2 = $by + $bh
    $ix1 = [math]::Max($ax, $bx); $iy1 = [math]::Max($ay, $by)
    $ix2 = [math]::Min($ax2, $bx2); $iy2 = [math]::Min($ay2, $by2)
    $iw = $ix2 - $ix1; $ih = $iy2 - $iy1
    $inter = [long]0
    if ($iw -gt 0 -and $ih -gt 0) { $inter = [long]$iw * [long]$ih }
    $areaA = [long]$aw * [long]$ah; $areaB = [long]$bw * [long]$bh
    $union = $areaA + $areaB - $inter
    return [pscustomobject]@{ inter = $inter; union = $union; area_a = $areaA; area_b = $areaB }
}
function Get-IouQ([long]$inter, [long]$union) {
    if ($union -le 0) { return [long]0 }
    return [long](BigRoundHalfUpDiv ([bigint]$inter * $SCALE_Q) ([bigint]$union))
}

# ============================ Hungarian assignment (stable mode) ============================
# Minimum-cost assignment over a rectangular long-cost matrix (rows <= cols required), potentials /
# shortest-augmenting-path formulation, O(rows^2*cols). Costs at $EDGE_INF mark forbidden pairs; because
# EDGE_INF >> any achievable real total, minimizing total cost = maximize real-edge cardinality, then
# minimize real cost. Returns int[] rowMatch (column per row).
function Solve-AssignmentCore($cost, [int]$n, [int]$m) {
    $BIG = [long]4611686018427387903
    $u = [long[]]::new($n + 1); $v = [long[]]::new($m + 1)
    $p = [int[]]::new($m + 1); $way = [int[]]::new($m + 1)
    for ($i = 1; $i -le $n; $i++) {
        $p[0] = $i; $j0 = 0
        $minv = [long[]]::new($m + 1)
        for ($j = 0; $j -le $m; $j++) { $minv[$j] = $BIG }
        $used = [bool[]]::new($m + 1)
        do {
            $used[$j0] = $true
            $i0 = $p[$j0]; $delta = $BIG; $j1 = -1
            for ($j = 1; $j -le $m; $j++) {
                if (-not $used[$j]) {
                    $cur = ($cost[$i0 - 1][$j - 1]) - $u[$i0] - $v[$j]
                    if ($cur -lt $minv[$j]) { $minv[$j] = $cur; $way[$j] = $j0 }
                    if ($minv[$j] -lt $delta) { $delta = $minv[$j]; $j1 = $j }
                }
            }
            for ($j = 0; $j -le $m; $j++) {
                if ($used[$j]) { $u[$p[$j]] += $delta; $v[$j] -= $delta }
                else { $minv[$j] -= $delta }
            }
            $j0 = $j1
        } while ($p[$j0] -ne 0)
        do { $j1 = $way[$j0]; $p[$j0] = $p[$j1]; $j0 = $j1 } while ($j0 -ne 0)
    }
    $rowMatch = [int[]]::new($n)
    for ($i = 0; $i -lt $n; $i++) { $rowMatch[$i] = -1 }
    for ($j = 1; $j -le $m; $j++) { if ($p[$j] -ge 1) { $rowMatch[$p[$j] - 1] = $j - 1 } }
    return ,$rowMatch
}
# Optimum (cardinality, real cost) for an arbitrary rectangular matrix (transposes when rows > cols).
function Get-OptimalScore($cost, [int]$nRows, [int]$nCols) {
    if ($nRows -eq 0 -or $nCols -eq 0) { return [pscustomobject]@{ card = 0; real_cost = [long]0 } }
    $card = 0; $real = [long]0
    if ($nRows -le $nCols) {
        $rm = Solve-AssignmentCore $cost $nRows $nCols
        for ($i = 0; $i -lt $nRows; $i++) {
            $j = $rm[$i]
            if ($j -ge 0 -and $cost[$i][$j] -lt $EDGE_INF) { $card++; $real += $cost[$i][$j] }
        }
    } else {
        $t = [object[]]::new($nCols)
        for ($j = 0; $j -lt $nCols; $j++) {
            $row = [long[]]::new($nRows)
            for ($i = 0; $i -lt $nRows; $i++) { $row[$i] = $cost[$i][$j] }
            $t[$j] = $row
        }
        $rm = Solve-AssignmentCore $t $nCols $nRows
        for ($j = 0; $j -lt $nCols; $j++) {
            $i = $rm[$j]
            if ($i -ge 0 -and $cost[$i][$j] -lt $EDGE_INF) { $card++; $real += $cost[$i][$j] }
        }
    }
    return [pscustomobject]@{ card = $card; real_cost = $real }
}
# THE TIE RULE (contract): among all assignments with maximum real-edge cardinality and minimum total
# real cost, return the lexicographically smallest ordered list of (row, col) pairs -- rows in ascending
# order (rows are tracks ordered by track_id; cols are detections in canonical order). Implemented by
# incremental fixing: rows in order, candidate columns in ascending order; a candidate is committed iff
# an optimal completion still exists (checked by re-solving the residual). Matching a row always
# lexicographically beats leaving it unmatched, so 'unmatched' is only taken when no column preserves
# the optimum.
function Get-CanonicalAssignment($cost, [int]$nRows, [int]$nCols) {
    $pairs = New-Object System.Collections.Generic.List[object]
    if ($nRows -eq 0 -or $nCols -eq 0) { return $pairs }
    $full = Get-OptimalScore $cost $nRows $nCols
    $Kstar = [int]$full.card; $Cstar = [long]$full.real_cost
    if ($Kstar -eq 0) { return $pairs }
    $availCols = New-Object System.Collections.Generic.List[int]
    for ($j = 0; $j -lt $nCols; $j++) { $availCols.Add($j) }
    $fixedCard = 0; $fixedCost = [long]0
    for ($ri = 0; $ri -lt $nRows; $ri++) {
        if ($fixedCard -eq $Kstar) { break }
        $chosen = -1
        foreach ($cj in $availCols) {
            if ($cost[$ri][$cj] -ge $EDGE_INF) { continue }
            # residual: rows ri+1..nRows-1 x availCols minus cj
            $resCols = New-Object System.Collections.Generic.List[int]
            foreach ($c in $availCols) { if ($c -ne $cj) { $resCols.Add($c) } }
            $rRows = $nRows - $ri - 1
            $rCols = $resCols.Count
            $sub = [object[]]::new([math]::Max($rRows, 0))
            for ($a = 0; $a -lt $rRows; $a++) {
                $row = [long[]]::new($rCols)
                for ($b = 0; $b -lt $rCols; $b++) { $row[$b] = $cost[$ri + 1 + $a][$resCols[$b]] }
                $sub[$a] = $row
            }
            $res = Get-OptimalScore $sub $rRows $rCols
            if (($fixedCard + 1 + [int]$res.card) -eq $Kstar -and ($fixedCost + $cost[$ri][$cj] + [long]$res.real_cost) -eq $Cstar) {
                $chosen = $cj; break
            }
        }
        if ($chosen -ge 0) {
            $pairs.Add([pscustomobject]@{ row = $ri; col = $chosen })
            [void]$availCols.Remove($chosen)
            $fixedCard++; $fixedCost += $cost[$ri][$chosen]
        }
    }
    return $pairs
}

# ============================ greedy-mode helpers (RETAINED byte-identical from 0.1.0) ============================
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
$isStable = $true
$stableCanonical = $null; $stableDiagnostics = $null

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw (New-SkillError 'invalid_inputs_json' '-InputsJson is not valid JSON') }
    }
    $inlineFrames = $null
    $inlineScenes = $null
    $detectorProvenanceRaw = $null
    if ($null -ne $p) {
        if ((Has $p 'input')          -and -not $bound.ContainsKey('InputFile'))     { $InputFile = [string]$p.input }
        if ((Has $p 'mode')           -and -not $bound.ContainsKey('Mode'))          { $Mode = [string]$p.mode }
        if ((Has $p 'iou_threshold')  -and -not $bound.ContainsKey('IouThreshold'))  { $IouThreshold = [double]$p.iou_threshold }
        if ((Has $p 'max_age')        -and -not $bound.ContainsKey('MaxAge'))        { $MaxAge = [int]$p.max_age }
        if ((Has $p 'min_score')      -and -not $bound.ContainsKey('MinScore'))      { $MinScore = [double]$p.min_score }
        if ((Has $p 'classes')        -and -not $bound.ContainsKey('Classes'))       { $Classes = @($p.classes | ForEach-Object { [string]$_ }) }
        if ((Has $p 'max_gap_ms')             -and -not $bound.ContainsKey('MaxGapMs'))           { $MaxGapMs = [int]$p.max_gap_ms }
        if ((Has $p 'max_missed_samples')     -and -not $bound.ContainsKey('MaxMissedSamples'))   { $MaxMissedSamples = [int]$p.max_missed_samples }
        if ((Has $p 'no_scene_max_gap_ms')    -and -not $bound.ContainsKey('NoSceneMaxGapMs'))    { $NoSceneMaxGapMs = [int]$p.no_scene_max_gap_ms }
        if ((Has $p 'centroid_base_allowance')       -and -not $bound.ContainsKey('CentroidBaseAllowance'))      { $CentroidBaseAllowance = [double]$p.centroid_base_allowance }
        if ((Has $p 'centroid_allowance_per_second') -and -not $bound.ContainsKey('CentroidAllowancePerSecond')) { $CentroidAllowancePerSecond = [double]$p.centroid_allowance_per_second }
        if ((Has $p 'centroid_max_allowance')        -and -not $bound.ContainsKey('CentroidMaxAllowance'))       { $CentroidMaxAllowance = [double]$p.centroid_max_allowance }
        if ((Has $p 'max_area_ratio')        -and -not $bound.ContainsKey('MaxAreaRatio'))            { $MaxAreaRatio = [double]$p.max_area_ratio }
        if ((Has $p 'low_confidence_threshold') -and -not $bound.ContainsKey('LowConfidenceThreshold')) { $LowConfidenceThreshold = [double]$p.low_confidence_threshold }
        if ((Has $p 'scenes_file')    -and -not $bound.ContainsKey('ScenesFile'))    { $ScenesFile = [string]$p.scenes_file }
        if ((Has $p 'frame_width')    -and -not $bound.ContainsKey('FrameWidth'))    { $FrameWidth = [int]$p.frame_width }
        if ((Has $p 'frame_height')   -and -not $bound.ContainsKey('FrameHeight'))   { $FrameHeight = [int]$p.frame_height }
        if ((Has $p 'source_media_id')     -and -not $bound.ContainsKey('SourceMediaId'))     { $SourceMediaId = [string]$p.source_media_id }
        if ((Has $p 'source_media_sha256') -and -not $bound.ContainsKey('SourceMediaSha256')) { $SourceMediaSha256 = [string]$p.source_media_sha256 }
        if (Has $p 'frames') { $inlineFrames = @($p.frames) }
        if (Has $p 'scenes') { $inlineScenes = @($p.scenes) }
        if (Has $p 'detector_provenance') { $detectorProvenanceRaw = $p.detector_provenance }
    }

    # ---- mode ----
    if ($Mode -cne 'stable' -and $Mode -cne 'greedy') {
        throw (New-SkillError 'invalid_mode' "mode must be 'stable' or 'greedy'; got '$Mode'")
    }
    $isStable = ($Mode -ceq 'stable')

    # ---- normalize the class filter (StrictMode-safe: never touch a $null [string[]]) ----
    $classFilter = @()
    if ($null -ne $Classes) { $classFilter = @($Classes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ }) }

    # ---- validate scalar params (shared) ----
    if ($IouThreshold -lt 0 -or $IouThreshold -gt 1) {
        throw (New-SkillError 'invalid_iou_threshold' "iou_threshold must be within 0..1; got $IouThreshold")
    }
    if ($MinScore -lt 0) {
        throw (New-SkillError 'invalid_min_score' "min_score must be >= 0; got $MinScore")
    }
    if ($isStable) {
        if ($MaxGapMs -lt 0) { throw (New-SkillError 'invalid_max_gap_ms' "max_gap_ms must be >= 0; got $MaxGapMs") }
        if ($MaxMissedSamples -lt 0) { throw (New-SkillError 'invalid_max_missed_samples' "max_missed_samples must be >= 0; got $MaxMissedSamples") }
        if ($NoSceneMaxGapMs -lt 0) { throw (New-SkillError 'invalid_no_scene_max_gap_ms' "no_scene_max_gap_ms must be >= 0; got $NoSceneMaxGapMs") }
        if ($CentroidBaseAllowance -lt 0 -or -not (Test-FiniteNumber $CentroidBaseAllowance)) { throw (New-SkillError 'invalid_centroid_allowance' "centroid_base_allowance must be >= 0; got $CentroidBaseAllowance") }
        if ($CentroidAllowancePerSecond -lt 0 -or -not (Test-FiniteNumber $CentroidAllowancePerSecond)) { throw (New-SkillError 'invalid_centroid_allowance' "centroid_allowance_per_second must be >= 0; got $CentroidAllowancePerSecond") }
        if ($CentroidMaxAllowance -lt 0 -or -not (Test-FiniteNumber $CentroidMaxAllowance)) { throw (New-SkillError 'invalid_centroid_allowance' "centroid_max_allowance must be >= 0; got $CentroidMaxAllowance") }
        if ($MaxAreaRatio -lt 1 -or -not (Test-FiniteNumber $MaxAreaRatio)) { throw (New-SkillError 'invalid_area_ratio' "max_area_ratio must be >= 1; got $MaxAreaRatio") }
        if ($LowConfidenceThreshold -lt 0 -or $LowConfidenceThreshold -gt 1) { throw (New-SkillError 'invalid_low_confidence_threshold' "low_confidence_threshold must be within 0..1; got $LowConfidenceThreshold") }
        if (($FrameWidth -gt 0) -ne ($FrameHeight -gt 0)) { throw (New-SkillError 'invalid_frame_dims' 'frame_width and frame_height must be given together (or neither)') }
        if ($FrameWidth -lt 0 -or $FrameHeight -lt 0) { throw (New-SkillError 'invalid_frame_dims' 'frame_width/frame_height must be positive') }
    } else {
        if ($MaxAge -lt 0) {
            throw (New-SkillError 'invalid_max_age' "max_age must be >= 0; got $MaxAge")
        }
    }

    # ---- resolve the raw frames (file wins over inline) ----
    $source = $null; $inFull = $null; $rawFrames = $null; $docTop = $null
    if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
        if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
            throw (New-SkillError 'input_not_found' "input file not found: $InputFile")
        }
        $inFull = (Resolve-Path -LiteralPath $InputFile).Path
        $raw = Get-Content -LiteralPath $inFull -Raw
        $doc = $null
        try { $doc = $raw | ConvertFrom-Json } catch { throw (New-SkillError 'input_parse_failed' "input JSON did not parse: $($_.Exception.Message)") }
        $rawFrames = Get-RawFrames $doc
        $docTop = $doc
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

    if (-not $isStable) {
        # =====================================================================================
        # ============================ GREEDY MODE (0.1.0 baseline) ===========================
        # =====================================================================================
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
            schema = $TRACKS_SCHEMA_GREEDY
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
        Write-Diag "ok mode=greedy frames=$($normFrames.Count) dets=$rawInputDetections tracks=$($trackRows.Count) births=$births deaths=$deaths iou>=$IouThreshold maxage=$MaxAge"
    }
    else {
        # =====================================================================================
        # ============================ STABLE MODE (0.2.0 default) ============================
        # =====================================================================================
        $iouThresholdQ = QMillionths $IouThreshold
        $minScoreQ = QMillionths $MinScore
        $lowConfQ = QMillionths $LowConfidenceThreshold
        $centroidBaseQ = QMillionths $CentroidBaseAllowance
        $centroidGrowthQ = QMillionths $CentroidAllowancePerSecond
        $centroidCapQ = QMillionths $CentroidMaxAllowance
        $areaRatioQ = QMillionths $MaxAreaRatio
        $frameWq = if ($FrameWidth -gt 0) { [long]$FrameWidth * $SCALE_BOX } else { [long]-1 }
        $frameHq = if ($FrameHeight -gt 0) { [long]$FrameHeight * $SCALE_BOX } else { [long]-1 }

        # ---- doc-level passthroughs (named/InputsJson win over doc top-level) ----
        if ($null -ne $docTop -and -not ($docTop -is [System.Array] -or $docTop -is [System.Collections.IList])) {
            if ($null -eq $inlineScenes -and (Has $docTop 'scenes')) { $inlineScenes = @($docTop.scenes) }
            if ($FrameWidth -le 0 -and (Has $docTop 'frame_width') -and (Has $docTop 'frame_height')) {
                $FrameWidth = [int]$docTop.frame_width; $FrameHeight = [int]$docTop.frame_height
                if ($FrameWidth -gt 0 -and $FrameHeight -gt 0) {
                    $frameWq = [long]$FrameWidth * $SCALE_BOX; $frameHq = [long]$FrameHeight * $SCALE_BOX
                } else { throw (New-SkillError 'invalid_frame_dims' 'input frame_width/frame_height must be positive') }
            }
            if ([string]::IsNullOrWhiteSpace($SourceMediaId) -and (Has $docTop 'source_media_id')) { $SourceMediaId = [string]$docTop.source_media_id }
            if ([string]::IsNullOrWhiteSpace($SourceMediaSha256) -and (Has $docTop 'source_media_sha256')) { $SourceMediaSha256 = [string]$docTop.source_media_sha256 }
            if ($null -eq $detectorProvenanceRaw -and (Has $docTop 'detector_provenance')) { $detectorProvenanceRaw = $docTop.detector_provenance }
        }

        # ---- scenes: -ScenesFile > InputsJson.scenes > doc.scenes. Accept a bare array or {scenes:[...]}
        #      (covers the #32 scenes.json artifact / result subobject). Entry: {index?, start|start_ms,
        #      end?|end_ms?, score?} -- 'start'/'end' are SECONDS (the #32 shape, rounded half-up to ms);
        #      'start_ms'/'end_ms' are integer ms. ----
        $scenesSource = 'none'
        $sceneEntries = $null
        if (-not [string]::IsNullOrWhiteSpace($ScenesFile)) {
            if (-not (Test-Path -LiteralPath $ScenesFile -PathType Leaf)) {
                throw (New-SkillError 'scenes_file_not_found' "scenes file not found: $ScenesFile")
            }
            $sraw = Get-Content -LiteralPath $ScenesFile -Raw
            $sdoc = $null
            try { $sdoc = $sraw | ConvertFrom-Json } catch { throw (New-SkillError 'scenes_parse_failed' "scenes JSON did not parse: $($_.Exception.Message)") }
            if ($sdoc -is [System.Array] -or $sdoc -is [System.Collections.IList]) { $sceneEntries = @($sdoc) }
            elseif (Has $sdoc 'scenes') { $sceneEntries = @($sdoc.scenes) }
            else { throw (New-SkillError 'invalid_scene' 'scenes file must be a scene array or an object with a scenes[] field') }
            $scenesSource = 'file'
        }
        elseif ($null -ne $inlineScenes) {
            $sceneEntries = @($inlineScenes)
            $scenesSource = 'inline'
        }
        $sceneList = $null   # sorted entries: {index:long, start_ms:long}
        if ($null -ne $sceneEntries) {
            $accS = New-Object System.Collections.Generic.List[object]
            for ($si = 0; $si -lt @($sceneEntries).Count; $si++) {
                $se = @($sceneEntries)[$si]
                if ($null -eq $se) { throw (New-SkillError 'invalid_scene' "scene entry $si is null") }
                $startMs = $null
                if (Has $se 'start_ms') {
                    $sv = ToDouble $se.start_ms
                    if ($null -eq $sv -or -not (Test-FiniteNumber $sv)) { throw (New-SkillError 'invalid_scene' "scene entry $si start_ms is not numeric") }
                    $startMs = QScale $sv ([long]1)
                }
                elseif (Has $se 'start') {
                    $sv = ToDouble $se.start
                    if ($null -eq $sv -or -not (Test-FiniteNumber $sv)) { throw (New-SkillError 'invalid_scene' "scene entry $si start is not numeric") }
                    $startMs = QMilli $sv
                }
                else { throw (New-SkillError 'invalid_scene' "scene entry $si must carry start (seconds) or start_ms") }
                $idxV = if (Has $se 'index') { ToDouble $se.index } else { $null }
                $sidx = if ($null -ne $idxV -and (Test-FiniteNumber $idxV) -and [math]::Floor($idxV) -eq $idxV) { [long]$idxV } else { [long]$si }
                $accS.Add([pscustomobject]@{ index = $sidx; start_ms = $startMs; pos = $si })
            }
            $sceneList = $accS.ToArray()
            [System.Array]::Sort($sceneList, [System.Comparison[object]] {
                param($a, $b)
                if ($a.start_ms -ne $b.start_ms) { return ([long]$a.start_ms).CompareTo([long]$b.start_ms) }
                if ($a.index -ne $b.index) { return ([long]$a.index).CompareTo([long]$b.index) }
                return ([int]$a.pos).CompareTo([int]$b.pos)
            })
        }

        # ---- normalize frames -> samples (quantize immediately; timestamps REQUIRED in stable mode) ----
        $sampList = New-Object System.Collections.Generic.List[object]
        $rawInputDetections = 0
        $anyExplicitScene = $false; $missingExplicitScene = $false
        for ($pos = 0; $pos -lt @($rawFrames).Count; $pos++) {
            $fe = @($rawFrames)[$pos]
            $fi = [long]$pos; $tsMs = $null; $rawDets = @(); $sceneExplicit = $null
            if ($fe -is [System.Array] -or $fe -is [System.Collections.IList]) {
                throw (New-SkillError 'missing_timestamp' "frame at position ${pos}: stable mode requires per-frame timestamps (timestamp_ms or timestamp_s); a bare detection array carries none. Use -Mode greedy for timestamp-less input.")
            }
            elseif (Has $fe 'detections') {
                $rawDets = @($fe.detections)
                $fiV = $null
                if (Has $fe 'frame') { $fiV = $fe.frame } elseif (Has $fe 'index') { $fiV = $fe.index } elseif (Has $fe 'frame_index') { $fiV = $fe.frame_index }
                if ($null -ne $fiV) { $fi = ToIntegralLong $fiV "frame index at position ${pos}" }
                if (Has $fe 'timestamp_ms') {
                    $tv = ToDouble $fe.timestamp_ms
                    if ($null -eq $tv -or -not (Test-FiniteNumber $tv)) { throw (New-SkillError 'invalid_frame' "frame ${fi}: timestamp_ms is not a finite number") }
                    $tsMs = QScale $tv ([long]1)
                } else {
                    $tsV = $null
                    if (Has $fe 'timestamp_s') { $tsV = $fe.timestamp_s } elseif (Has $fe 'timestamp') { $tsV = $fe.timestamp }
                    $tsD = ToDouble $tsV
                    if ($null -eq $tsD) { throw (New-SkillError 'missing_timestamp' "frame ${fi}: stable mode requires timestamp_ms (integer ms) or timestamp_s (seconds, rounded half-up to ms)") }
                    if (-not (Test-FiniteNumber $tsD)) { throw (New-SkillError 'invalid_frame' "frame ${fi}: timestamp is not a finite number") }
                    $tsMs = QMilli $tsD
                }
                if (Has $fe 'scene_index') {
                    $sceneExplicit = ToIntegralLong $fe.scene_index "frame ${fi} scene_index"
                    $anyExplicitScene = $true
                } else { $missingExplicitScene = $true }
            }
            else {
                throw (New-SkillError 'invalid_frame' "frame at position ${pos} must be an object with a 'detections' field")
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
                foreach ($vv in @($bx, $by, $bw, $bh)) {
                    if (-not (Test-FiniteNumber $vv)) { throw (New-SkillError 'invalid_detection' "frame ${fi} detection ${di} (class '$cls') has a non-finite box value") }
                }
                $scoreRaw = if (Has $de 'score') { $de.score } else { $null }
                $score = ToDouble $scoreRaw
                if ($null -ne $score -and -not (Test-FiniteNumber $score)) { throw (New-SkillError 'invalid_detection' "frame ${fi} detection ${di} (class '$cls') has a non-finite score") }
                $cid = $null
                if ((Has $de 'class_id') -and $null -ne $de.class_id) { $cid = ToIntegralLong $de.class_id "frame ${fi} detection ${di} class_id" }

                # class filter
                if ($classFilter.Count -gt 0 -and ($classFilter -notcontains $cls)) { continue }
                # quantize immediately
                $qx = QMilli $bx; $qy = QMilli $by; $qw = QMilli $bw; $qh = QMilli $bh
                $qscore = if ($null -ne $score) { QMillionths $score } else { $null }
                # min-score filter on the QUANTIZED score (only drop when a score is present and below the floor)
                if ($minScoreQ -gt 0 -and $null -ne $qscore -and $qscore -lt $minScoreQ) { continue }
                # clip to source dims (half-open [0,W)x[0,H) in milli-pixels) when dims are known
                if ($frameWq -ge 0) {
                    $nx1 = [math]::Min([math]::Max($qx, [long]0), $frameWq)
                    $nx2 = [math]::Min([math]::Max($qx + $qw, [long]0), $frameWq)
                    $ny1 = [math]::Min([math]::Max($qy, [long]0), $frameHq)
                    $ny2 = [math]::Min([math]::Max($qy + $qh, [long]0), $frameHq)
                    $qx = [long]$nx1; $qy = [long]$ny1; $qw = [long]($nx2 - $nx1); $qh = [long]($ny2 - $ny1)
                }
                if ($qw -le 0 -or $qh -le 0) { $warnings.Add("frame ${fi} detection ${di} (class '$cls') has a degenerate box (width/height <= 0 after quantization/clipping); it cannot match by IoU") }
                $lowConf = $false
                if ((Has $de 'low_confidence') -and $null -ne $de.low_confidence) { $lowConf = [bool]$de.low_confidence }
                elseif ($null -ne $qscore) { $lowConf = ($qscore -lt $lowConfQ) }
                $keptDets.Add([pscustomobject]@{
                    class = $cls; class_id = $cid
                    qscore = $qscore; low_confidence = $lowConf
                    qx = $qx; qy = $qy; qw = $qw; qh = $qh
                    det_index = [long]$di
                })
            }
            $sampList.Add([pscustomobject]@{ frame = $fi; ts = [long]$tsMs; scene_explicit = $sceneExplicit; dets = $keptDets; pos = $pos })
        }

        # ---- scene info consistency + presence ----
        $sceneInfoPresent = ($anyExplicitScene -or ($null -ne $sceneList))
        if ($anyExplicitScene -and $missingExplicitScene -and ($null -eq $sceneList)) {
            throw (New-SkillError 'invalid_scene' 'scene_index present on some frames but not all, and no scenes[] list to derive the rest from')
        }
        $maxGapEff = [long]$MaxGapMs
        $sceneInfoTag = 'absent'
        if ($sceneInfoPresent) {
            if ($anyExplicitScene -and ($null -ne $sceneList)) { $sceneInfoTag = 'per_frame+scenes_list' }
            elseif ($anyExplicitScene) { $sceneInfoTag = 'per_frame' }
            else { $sceneInfoTag = 'scenes_list' }
        } else {
            $maxGapEff = [math]::Min([long]$MaxGapMs, [long]$NoSceneMaxGapMs)
            $warnings.Add("no scene information (per-frame scene_index or scenes[]): all samples treated as one scene; using the conservative max gap ${maxGapEff} ms (min of max_gap_ms, no_scene_max_gap_ms)")
        }

        # ---- chronological sample order: (timestamp_ms, frame_index, original position) -- total order ----
        $samples = $sampList.ToArray()
        [System.Array]::Sort($samples, [System.Comparison[object]] {
            param($a, $b)
            if ($a.ts -ne $b.ts) { return ([long]$a.ts).CompareTo([long]$b.ts) }
            if ($a.frame -ne $b.frame) { return ([long]$a.frame).CompareTo([long]$b.frame) }
            return ([int]$a.pos).CompareTo([int]$b.pos)
        })

        # ---- derive per-sample scene_index + canonical detection order + sample_index ----
        for ($siN = 0; $siN -lt $samples.Count; $siN++) {
            $s = $samples[$siN]
            $sceneIdx = [long]0
            if ($null -ne $s.scene_explicit) { $sceneIdx = [long]$s.scene_explicit }
            elseif ($null -ne $sceneList) {
                # derived scene_index = index of the LAST scene entry whose start_ms <= ts; a sample before
                # the first entry gets (first entry's index - 1) -- the implicit pre-first-cut scene.
                $cur = $null
                foreach ($se in $sceneList) { if ([long]$se.start_ms -le [long]$s.ts) { $cur = $se } else { break } }
                if ($null -ne $cur) { $sceneIdx = [long]$cur.index }
                else { $sceneIdx = [long]$sceneList[0].index - 1 }
            }
            # canonical detection ordering: (class_id [null -> -1], class, qx, qy, qw, qh, -qscore
            # [null -> sorts last], original_index) -- a total order.
            $detArr = $s.dets.ToArray()
            [System.Array]::Sort($detArr, [System.Comparison[object]] {
                param($a, $b)
                $acid = if ($null -ne $a.class_id) { [long]$a.class_id } else { [long](-1) }
                $bcid = if ($null -ne $b.class_id) { [long]$b.class_id } else { [long](-1) }
                if ($acid -ne $bcid) { return $acid.CompareTo($bcid) }
                $cc = [string]::CompareOrdinal([string]$a.class, [string]$b.class)
                if ($cc -ne 0) { return $cc }
                if ($a.qx -ne $b.qx) { return ([long]$a.qx).CompareTo([long]$b.qx) }
                if ($a.qy -ne $b.qy) { return ([long]$a.qy).CompareTo([long]$b.qy) }
                if ($a.qw -ne $b.qw) { return ([long]$a.qw).CompareTo([long]$b.qw) }
                if ($a.qh -ne $b.qh) { return ([long]$a.qh).CompareTo([long]$b.qh) }
                $as = if ($null -ne $a.qscore) { [long]$a.qscore } else { [long](-1) }
                $bs = if ($null -ne $b.qscore) { [long]$b.qscore } else { [long](-1) }
                if ($as -ne $bs) { return $bs.CompareTo($as) }   # -qscore: higher score first
                return ([long]$a.det_index).CompareTo([long]$b.det_index)
            })
            for ($r = 0; $r -lt $detArr.Length; $r++) { $detArr[$r] | Add-Member -NotePropertyName rank -NotePropertyValue ([int]$r) -Force }
            $s | Add-Member -NotePropertyName sample_index -NotePropertyValue ([long]$siN) -Force
            $s | Add-Member -NotePropertyName scene -NotePropertyValue $sceneIdx -Force
            $s | Add-Member -NotePropertyName cdets -NotePropertyValue $detArr -Force
        }

        # ---- input_digest: sha256 over the canonical serialization of the normalized, quantized,
        #      FILTERED input the tracker consumed (samples + their kept detections; scenes are baked in
        #      as scene_index). See SCHEMA_NOTES.md. ----
        $digestSamples = New-Object System.Collections.Generic.List[object]
        foreach ($s in $samples) {
            $dd = New-Object System.Collections.Generic.List[object]
            foreach ($d in $s.cdets) {
                $dd.Add([ordered]@{
                    box = [ordered]@{ height = [long]$d.qh; width = [long]$d.qw; x = [long]$d.qx; y = [long]$d.qy }
                    class = [string]$d.class
                    class_id = $d.class_id
                    detection_index = [long]$d.det_index
                    detection_score = $d.qscore
                })
            }
            $digestSamples.Add([ordered]@{
                detections = $dd.ToArray()
                frame_index = [long]$s.frame
                sample_index = [long]$s.sample_index
                scene_index = [long]$s.scene
                timestamp_ms = [long]$s.ts
            })
        }
        $inputDigestHex = Get-Sha256Hex $utf8.GetBytes((ConvertTo-CanonicalJson $digestSamples.ToArray()))

        # ================= the stable deterministic geometric association tracker =================
        $allTracks = New-Object System.Collections.Generic.List[object]
        $activeTracks = New-Object System.Collections.Generic.List[object]
        $nextId = [long]0
        $maxConcurrent = 0
        $iouLinkTotal = 0; $centroidLinkTotal = 0; $gapTotal = 0
        $termCounts = @{ end_of_input = 0; max_gap = 0; max_missed_samples = 0; scene_boundary = 0 }

        $terminate = {
            param($t, [string]$reason, [long]$atMs)
            $t.termination = [ordered]@{
                last_observed_ms = [long]$t.last_ts
                missed_samples_at_termination = [long]$t.missed
                reason = $reason
                terminated_at_ms = $atMs
            }
            $termCounts[$reason] = [int]$termCounts[$reason] + 1
        }

        foreach ($s in $samples) {
            $ts = [long]$s.ts; $scene = [long]$s.scene; $sIdx = [long]$s.sample_index
            # (1) scene-boundary HARD separation: a sample from a new scene terminates every active track
            #     of any other scene BEFORE association (never associate across a known cut).
            $keep = New-Object System.Collections.Generic.List[object]
            foreach ($t in $activeTracks.ToArray()) {
                if ([long]$t.scene_index -ne $scene) { & $terminate $t 'scene_boundary' $ts }
                else { $keep.Add($t) }
            }
            $activeTracks = $keep
            # (2) elapsed-time aging (max_gap): checked BEFORE association so an over-gap track can never link.
            $keep = New-Object System.Collections.Generic.List[object]
            foreach ($t in $activeTracks.ToArray()) {
                if (($ts - [long]$t.last_ts) -gt $maxGapEff) { & $terminate $t 'max_gap' $ts }
                else { $keep.Add($t) }
            }
            $activeTracks = $keep

            # (3) association per class (exact-class; separate cost matrix per class per scene)
            $classesInSample = New-Object System.Collections.Generic.List[string]
            foreach ($d in $s.cdets) { if (-not $classesInSample.Contains([string]$d.class)) { $classesInSample.Add([string]$d.class) } }
            $classesArr = $classesInSample.ToArray()
            [System.Array]::Sort($classesArr, [System.Comparison[string]] { param($a, $b) [string]::CompareOrdinal($a, $b) })

            $linkedDetRanks = New-Object 'System.Collections.Generic.HashSet[int]'
            foreach ($cls in $classesArr) {
                $rows = New-Object System.Collections.Generic.List[object]
                foreach ($t in $activeTracks.ToArray()) { if ([string]$t.class -ceq $cls) { $rows.Add($t) } }
                # rows are in track_id order already (activeTracks holds tracks in birth order and ids are monotonic)
                $cols = New-Object System.Collections.Generic.List[object]
                foreach ($d in $s.cdets) { if ([string]$d.class -ceq $cls) { $cols.Add($d) } }
                if ($rows.Count -eq 0 -or $cols.Count -eq 0) { continue }

                $nR = $rows.Count; $nC = $cols.Count
                $cost = [object[]]::new($nR)
                $meta = [object[]]::new($nR)
                for ($i = 0; $i -lt $nR; $i++) {
                    $t = $rows[$i]
                    $costRow = [long[]]::new($nC)
                    $metaRow = [object[]]::new($nC)
                    $gap = $ts - [long]$t.last_ts
                    for ($j = 0; $j -lt $nC; $j++) {
                        $d = $cols[$j]
                        $iu = Get-InterUnion ([long]$t.qx) ([long]$t.qy) ([long]$t.qw) ([long]$t.qh) ([long]$d.qx) ([long]$d.qy) ([long]$d.qw) ([long]$d.qh)
                        $iouQ = Get-IouQ ([long]$iu.inter) ([long]$iu.union)
                        # link metrics (computed for every admitted edge; recorded on the chosen link)
                        $dcx = (2 * [long]$t.qx + [long]$t.qw) - (2 * [long]$d.qx + [long]$d.qw)   # doubled centers
                        $dcy = (2 * [long]$t.qy + [long]$t.qh) - (2 * [long]$d.qy + [long]$d.qh)
                        $dispSq4 = ([bigint]$dcx * $dcx) + ([bigint]$dcy * $dcy)                    # 4 * squared displacement
                        $areaPrev = [long]$iu.area_a; $areaNew = [long]$iu.area_b
                        $bigBox = if ($areaNew -gt $areaPrev) { $d } else { $t }                    # tie -> the previous (track) box
                        $diagSq = ([bigint][long]$bigBox.qw * [long]$bigBox.qw) + ([bigint][long]$bigBox.qh * [long]$bigBox.qh)
                        $ncdQ = $null
                        if ($diagSq -gt 0) { $ncdQ = [long](BigRoundHalfUpDiv ($dispSq4 * $SCALE_Q) (4 * $diagSq)) }
                        $arQ = $null
                        if ($areaPrev -gt 0 -and $areaNew -gt 0) {
                            $maxA = [math]::Max($areaPrev, $areaNew); $minA = [math]::Min($areaPrev, $areaNew)
                            $arQ = [long](BigRoundHalfUpDiv ([bigint]$maxA * $SCALE_Q) ([bigint]$minA))
                        }
                        $c = $EDGE_INF; $tier = $null
                        if ($iouQ -ge $iouThresholdQ -and $iu.inter -gt 0) {
                            # tier 1: IoU-qualified (quantized integer compare)
                            $c = $SCALE_Q - $iouQ; $tier = 'iou'
                        }
                        elseif ($iouQ -ge $iouThresholdQ -and $iouThresholdQ -eq 0 -and $iu.inter -eq 0) {
                            # iou_threshold 0 admits zero-overlap pairs as tier-1 (greedy parity); keep them tier-1.
                            $c = $SCALE_Q - $iouQ; $tier = 'iou'
                        }
                        elseif ($iu.inter -eq 0) {
                            # tier 2: TIGHTLY-GATED normalized-centroid fallback, ONLY when integer IoU == 0.
                            # Gates: class match (grouping), scene match (grouping), elapsed <= max_gap,
                            # normalized squared displacement within the time-growing hard-capped allowance,
                            # cross-multiplied area-ratio sanity.
                            if ($gap -le $maxGapEff -and $diagSq -gt 0 -and $areaPrev -gt 0 -and $areaNew -gt 0) {
                                $allowQ = [bigint]$centroidBaseQ + (BigFloorDiv ([bigint]$centroidGrowthQ * $gap) ([bigint]1000))
                                if ($allowQ -gt [bigint]$centroidCapQ) { $allowQ = [bigint]$centroidCapQ }
                                $dispOk = (($dispSq4 * $SCALE_Q) -le ($allowQ * 4 * $diagSq))
                                $maxA = [math]::Max($areaPrev, $areaNew); $minA = [math]::Min($areaPrev, $areaNew)
                                $areaOk = (([bigint]$maxA * $SCALE_Q) -le ([bigint]$minA * $areaRatioQ))
                                if ($dispOk -and $areaOk) { $c = (2 * $SCALE_Q) + [long]$ncdQ; $tier = 'centroid' }
                            }
                        }
                        $costRow[$j] = $c
                        $metaRow[$j] = [pscustomobject]@{ tier = $tier; iou_q = [long]$iouQ; ncd_q = $ncdQ; area_ratio_q = $arQ; gap_ms = $gap }
                    }
                    $cost[$i] = $costRow
                    $meta[$i] = $metaRow
                }

                $pairs = Get-CanonicalAssignment $cost $nR $nC
                foreach ($pr in $pairs) {
                    $t = $rows[[int]$pr.row]; $d = $cols[[int]$pr.col]; $mm = $meta[[int]$pr.row][[int]$pr.col]
                    $kind = [string]$mm.tier
                    $missedAtLink = [long]$t.missed
                    $gapMs = [long]$mm.gap_ms
                    if ($missedAtLink -ge 1) {
                        $t.gaps.Add([ordered]@{
                            after_sample_index = [long]$t.last_sample
                            before_sample_index = $sIdx
                            elapsed_ms = $gapMs
                            end_ms = $ts
                            missed_samples = $missedAtLink
                            reacquired_by = $kind
                            start_ms = [long]$t.last_ts
                        })
                        $t.reacq = [int]$t.reacq + 1
                        $gapTotal++
                    }
                    $t.obs.Add([ordered]@{
                        association = [ordered]@{
                            area_ratio_q = $mm.area_ratio_q
                            gap_ms = $gapMs
                            iou_q = [long]$mm.iou_q
                            kind = $kind
                            missed_samples = $missedAtLink
                            normalized_center_distance_q = $mm.ncd_q
                            previous_frame_index = [long]$t.last_frame
                        }
                        box = [ordered]@{ height = [long]$d.qh; width = [long]$d.qw; x = [long]$d.qx; y = [long]$d.qy }
                        detection_index = [long]$d.det_index
                        detection_score = $d.qscore
                        frame_index = [long]$s.frame
                        low_confidence = [bool]$d.low_confidence
                        sample_index = $sIdx
                        timestamp_ms = $ts
                    })
                    # link quality (formula link_quality/1): iou links -> iou_q; centroid links -> max(0, 1e6 - ncd_q)
                    $lq = if ($kind -ceq 'iou') { [long]$mm.iou_q } else { [math]::Max([long]0, $SCALE_Q - [long]$mm.ncd_q) }
                    $t.linkq.Add([long]$lq)
                    if ($kind -ceq 'iou') { $t.iou_links = [int]$t.iou_links + 1; $iouLinkTotal++ }
                    else { $t.centroid_links = [int]$t.centroid_links + 1; $centroidLinkTotal++ }
                    if ($gapMs -gt [long]$t.max_link_gap) { $t.max_link_gap = $gapMs }
                    $t.qx = [long]$d.qx; $t.qy = [long]$d.qy; $t.qw = [long]$d.qw; $t.qh = [long]$d.qh
                    $t.last_ts = $ts; $t.last_frame = [long]$s.frame; $t.last_sample = $sIdx; $t.missed = [long]0
                    [void]$linkedDetRanks.Add([int]$d.rank)
                }
            }

            # (4) births: unmatched detections, in the sample's canonical detection order
            foreach ($d in $s.cdets) {
                if ($linkedDetRanks.Contains([int]$d.rank)) { continue }
                $obs = New-Object System.Collections.Generic.List[object]
                $obs.Add([ordered]@{
                    association = [ordered]@{
                        area_ratio_q = $null
                        gap_ms = $null
                        iou_q = $null
                        kind = 'birth'
                        missed_samples = $null
                        normalized_center_distance_q = $null
                        previous_frame_index = $null
                    }
                    box = [ordered]@{ height = [long]$d.qh; width = [long]$d.qw; x = [long]$d.qx; y = [long]$d.qy }
                    detection_index = [long]$d.det_index
                    detection_score = $d.qscore
                    frame_index = [long]$s.frame
                    low_confidence = [bool]$d.low_confidence
                    sample_index = $sIdx
                    timestamp_ms = $ts
                })
                $trk = [pscustomobject]@{
                    track_id = [long]$nextId; class = [string]$d.class; class_id = $d.class_id
                    scene_index = $scene
                    qx = [long]$d.qx; qy = [long]$d.qy; qw = [long]$d.qw; qh = [long]$d.qh
                    first_ts = $ts; last_ts = $ts
                    first_frame = [long]$s.frame; last_frame = [long]$s.frame
                    first_sample = $sIdx; last_sample = $sIdx
                    missed = [long]0
                    obs = $obs
                    gaps = (New-Object System.Collections.Generic.List[object])
                    linkq = (New-Object System.Collections.Generic.List[long])
                    iou_links = 0; centroid_links = 0; reacq = 0
                    max_link_gap = [long]0
                    termination = $null
                }
                $nextId++
                $allTracks.Add($trk); $activeTracks.Add($trk)
            }

            # (5) missed-sample aging: every active track of this scene that neither matched nor was born
            #     at this sample counts one missed sample; over the cap -> termination (max_missed_samples).
            $keep = New-Object System.Collections.Generic.List[object]
            foreach ($t in $activeTracks.ToArray()) {
                if ([long]$t.last_sample -eq $sIdx) { $keep.Add($t); continue }
                $t.missed = [long]$t.missed + 1
                if ([long]$t.missed -gt [long]$MaxMissedSamples) { & $terminate $t 'max_missed_samples' $ts }
                else { $keep.Add($t) }
            }
            $activeTracks = $keep
            if ($activeTracks.Count -gt $maxConcurrent) { $maxConcurrent = $activeTracks.Count }
        }

        # (6) end of input: every remaining active track terminates at the final sample's timestamp.
        if ($samples.Count -gt 0) {
            $finalTs = [long]$samples[$samples.Count - 1].ts
            foreach ($t in $activeTracks.ToArray()) { & $terminate $t 'end_of_input' $finalTs }
            $activeTracks.Clear()
        }

        # ================= assemble the canonical track file =================
        $trackRows = New-Object System.Collections.Generic.List[object]
        $classCounts = @{}
        $observationTotal = 0
        foreach ($t in $allTracks.ToArray()) {
            $obsArr = $t.obs.ToArray()
            $observationTotal += $obsArr.Length
            $cls = [string]$t.class
            if ($classCounts.ContainsKey($cls)) { $classCounts[$cls] = [int]$classCounts[$cls] + 1 } else { $classCounts[$cls] = 1 }
            # detection evidence (score_summary) -- over observations with a score
            $scored = New-Object System.Collections.Generic.List[long]
            $lowConfCount = 0
            foreach ($o in $obsArr) {
                if ($null -ne $o['detection_score']) { $scored.Add([long]$o['detection_score']) }
                if ([bool]$o['low_confidence']) { $lowConfCount++ }
            }
            $meanQ = $null; $minQ = $null; $maxQ = $null
            if ($scored.Count -gt 0) {
                $sum = [bigint]0
                $minQ = [long]$scored[0]; $maxQ = [long]$scored[0]
                foreach ($q in $scored.ToArray()) {
                    $sum = $sum + $q
                    if ($q -lt $minQ) { $minQ = $q }
                    if ($q -gt $maxQ) { $maxQ = $q }
                }
                $meanQ = [long](BigRoundHalfUpDiv $sum ([bigint]$scored.Count))
            }
            # association evidence
            $lqArr = $t.linkq.ToArray()
            $meanLq = $null; $weakLq = $null
            if ($lqArr.Length -gt 0) {
                $sumL = [bigint]0; $weakLq = [long]$lqArr[0]
                foreach ($q in $lqArr) { $sumL = $sumL + $q; if ($q -lt $weakLq) { $weakLq = $q } }
                $meanLq = [long](BigRoundHalfUpDiv $sumL ([bigint]$lqArr.Length))
            }
            $firstObs = $obsArr[0]; $lastObs = $obsArr[$obsArr.Length - 1]
            $trackRows.Add([ordered]@{
                association_summary = [ordered]@{
                    centroid_link_count = [long]$t.centroid_links
                    iou_link_count = [long]$t.iou_links
                    maximum_gap_ms = [long]$t.max_link_gap
                    mean_link_quality_q = $meanLq
                    reacquisition_count = [long]$t.reacq
                    weakest_link_quality_q = $weakLq
                }
                class = $cls
                class_id = $t.class_id
                duration_ms = ([long]$lastObs['timestamp_ms'] - [long]$firstObs['timestamp_ms'])
                end_ms = [long]$lastObs['timestamp_ms']
                first_frame_index = [long]$firstObs['frame_index']
                gap_count = [long]$t.gaps.Count
                gaps = $t.gaps.ToArray()
                last_frame_index = [long]$lastObs['frame_index']
                observation_count = [long]$obsArr.Length
                observations = $obsArr
                scene_index = [long]$t.scene_index
                score_summary = [ordered]@{
                    low_confidence_observation_count = [long]$lowConfCount
                    max_detection_score_q = $maxQ
                    mean_detection_score_q = $meanQ
                    min_detection_score_q = $minQ
                    scored_observation_count = [long]$scored.Count
                }
                spanned_sample_count = ([long]$lastObs['sample_index'] - [long]$firstObs['sample_index'] + 1)
                start_ms = [long]$firstObs['timestamp_ms']
                termination = $t.termination
                track_id = [long]$t.track_id
            })
        }

        $sampleManifest = New-Object System.Collections.Generic.List[object]
        $sceneSet = New-Object 'System.Collections.Generic.HashSet[long]'
        foreach ($s in $samples) {
            [void]$sceneSet.Add([long]$s.scene)
            $sampleManifest.Add([ordered]@{
                detection_count = [long]$s.cdets.Length
                frame_index = [long]$s.frame
                sample_index = [long]$s.sample_index
                scene_index = [long]$s.scene
                timestamp_ms = [long]$s.ts
            })
        }

        [string[]]$classFilterSorted = @($classFilter | ForEach-Object { [string]$_ })
        if ($classFilterSorted.Count -gt 1) {
            [System.Array]::Sort($classFilterSorted, [System.Comparison[string]] { param($a, $b) [string]::CompareOrdinal($a, $b) })
        }
        $trackerParams = [ordered]@{
            centroid_allowance_growth_per_s_q = [long]$centroidGrowthQ
            centroid_base_allowance_q = [long]$centroidBaseQ
            centroid_max_allowance_q = [long]$centroidCapQ
            class_filter = $classFilterSorted
            iou_threshold_q = [long]$iouThresholdQ
            link_quality_formula = $LINK_QUALITY_FORMULA
            low_confidence_threshold_q = [long]$lowConfQ
            max_area_ratio_q = [long]$areaRatioQ
            max_gap_ms = [long]$MaxGapMs
            max_gap_ms_effective = [long]$maxGapEff
            max_missed_samples = [long]$MaxMissedSamples
            min_score_q = [long]$minScoreQ
            mode = 'stable'
            no_scene_max_gap_ms = [long]$NoSceneMaxGapMs
            rounding = 'round_half_up_toward_positive_infinity'
            scene_info = $sceneInfoTag
            tie_rule = 'lexicographic_smallest_track_id_detection_rank'
        }
        $classSummary = [ordered]@{}
        [string[]]$classKeys = @($classCounts.Keys | ForEach-Object { [string]$_ })
        if ($classKeys.Count -gt 1) { [System.Array]::Sort($classKeys, [System.Comparison[string]] { param($a, $b) [string]::CompareOrdinal($a, $b) }) }
        foreach ($k in $classKeys) { $classSummary[$k] = [long]$classCounts[$k] }
        $summaryObj = [ordered]@{
            births = [long]$allTracks.Count
            centroid_link_total = [long]$centroidLinkTotal
            class_summary = $classSummary
            gap_total = [long]$gapTotal
            iou_link_total = [long]$iouLinkTotal
            max_concurrent_tracks = [long]$maxConcurrent
            observation_total = [long]$observationTotal
            sample_count = [long]$samples.Count
            scene_count = [long]$sceneSet.Count
            termination_reasons = [ordered]@{
                end_of_input = [long]$termCounts['end_of_input']
                max_gap = [long]$termCounts['max_gap']
                max_missed_samples = [long]$termCounts['max_missed_samples']
                scene_boundary = [long]$termCounts['scene_boundary']
            }
            track_count = [long]$allTracks.Count
        }
        $detProvSafe = $null
        if ($null -ne $detectorProvenanceRaw) { $detProvSafe = ConvertTo-CanonicalSafe $detectorProvenanceRaw $warnings }

        $canonicalDoc = [ordered]@{
            algorithm = $ALGORITHM_STABLE
            box_format = 'xywh_top_left_half_open'
            box_unit = 'milli_pixel'
            coordinate_space = 'source_pixels'
            detector_provenance = $detProvSafe
            frame_height = $(if ($FrameHeight -gt 0) { [long]$FrameHeight } else { $null })
            frame_width = $(if ($FrameWidth -gt 0) { [long]$FrameWidth } else { $null })
            identity_scope = 'source_media+scene+tracker_invocation'
            input_digest = ('sha256:' + $inputDigestHex)
            samples = $sampleManifest.ToArray()
            schema = $TRACKS_SCHEMA_STABLE
            score_unit = 'millionths'
            source_media_id = $(if ([string]::IsNullOrWhiteSpace($SourceMediaId)) { $null } else { [string]$SourceMediaId })
            source_media_sha256 = $(if ([string]::IsNullOrWhiteSpace($SourceMediaSha256)) { $null } else { [string]$SourceMediaSha256 })
            summary = $summaryObj
            timestamp_unit = 'ms'
            tracker_params = $trackerParams
            tracker_version = $SKILL_VERSION
            tracks = $trackRows.ToArray()
        }

        # canonical bytes: sorted keys, compact, integers only, one trailing LF, UTF-8 no BOM.
        $canonicalText = (ConvertTo-CanonicalJson $canonicalDoc) + "`n"
        $canonicalBytes = $utf8.GetBytes($canonicalText)
        $canonicalSha = Get-Sha256Hex $canonicalBytes
        $tracksJsonPath = Join-Path $invDir 'tracks.json'
        [System.IO.File]::WriteAllBytes($tracksJsonPath, $canonicalBytes)
        $producedFiles.Add([pscustomobject]@{ p = $tracksJsonPath; k = 'json' })

        # diagnostics / invocation envelope: every volatile fact lives HERE, never in the canonical file.
        $stableDiagnostics = [ordered]@{
            schema = 'lifeorch.track.objects.diagnostics/0.1'
            invocation_id = $InvocationId
            input = [ordered]@{ source = $source; path = $inFull; frames = $samples.Count; raw_detections = $rawInputDetections; scenes_source = $scenesSource }
            artifact_dir = $invDir
            canonical_file = 'tracks.json'
            canonical_sha256 = $canonicalSha
            started_at_utc = $startedAt.ToString('o')
        }
        $diagPath = Join-Path $invDir 'diagnostics.json'
        [System.IO.File]::WriteAllText($diagPath, ($stableDiagnostics | ConvertTo-Json -Depth 8), $utf8)
        $producedFiles.Add([pscustomobject]@{ p = $diagPath; k = 'json' })

        $stableCanonical = $canonicalDoc
        $result = [ordered]@{
            mode = 'stable'
            canonical = $canonicalDoc
            canonical_path = $tracksJsonPath
            canonical_sha256 = $canonicalSha
            diagnostics_path = $diagPath
        }
        $inputsDigest = 'sha256:' + $inputDigestHex
        Write-Diag "ok mode=stable samples=$($samples.Count) dets=$rawInputDetections tracks=$($allTracks.Count) iou_links=$iouLinkTotal centroid_links=$centroidLinkTotal gaps=$gapTotal scenes=$($sceneSet.Count) sha=$canonicalSha"
    }
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
        if (-not $isStable) {
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
        } else {
            $cd = $stableCanonical
            [void]$mb.AppendLine("# track.objects (stable)")
            [void]$mb.AppendLine("samples: $($cd['summary']['sample_count'])  scenes: $($cd['summary']['scene_count'])  tracks: $($cd['summary']['track_count'])  links: iou=$($cd['summary']['iou_link_total']) centroid=$($cd['summary']['centroid_link_total'])  gaps: $($cd['summary']['gap_total'])")
            [void]$mb.AppendLine("canonical: tracks.json sha256=$($result.canonical_sha256)")
            [void]$mb.AppendLine('')
            [void]$mb.AppendLine('| track_id | class | scene | obs | gaps | start_ms->end_ms | termination |')
            [void]$mb.AppendLine('|---|---|---|---|---|---|---|')
            foreach ($tr in @($cd['tracks'])) {
                [void]$mb.AppendLine("| $($tr['track_id']) | $($tr['class']) | $($tr['scene_index']) | $($tr['observation_count']) | $($tr['gap_count']) | $($tr['start_ms'])->$($tr['end_ms']) | $($tr['termination']['reason']) |")
            }
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
$json = $envelope | ConvertTo-Json -Depth 30
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
