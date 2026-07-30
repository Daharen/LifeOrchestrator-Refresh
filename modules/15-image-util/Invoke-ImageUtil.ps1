#requires -Version 7.0
<#
.SYNOPSIS
  image.util -- deterministic image utilities (Life Orchestrator, contract v0.1).
.DESCRIPTION
  One image in -> metadata + hashes always, plus an optional op: resize (fit/fill/exact or a single
  max_dimension, reporting scale factors), crop (pixel rect / normalized / named region), convert
  (png/jpg/webp/bmp/tiff + quality), tile/split (grid or fixed size + overlap), or similarity (Hamming
  distance of perceptual hashes vs a second image). Runs a Pillow+numpy Python worker (image_worker.py)
  under the system python and reads the worker's meta file (worker+meta hand-off, robust to library
  stdout chatter), the D-0021 pattern in its deterministic Python variant. CPU-only, parallel-safe, no
  model -> determinism=deterministic, confidence=null, empty model_provenance, no review-queue producer.

  Emits one lifeorch.skill.result/0.1 envelope on stdout; diagnostics to stderr; writes image.json,
  image.md, image_args.json, image_meta.json, worker.log, result.json, stderr.txt (+ output image files).
  Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\photo.png -Op resize -MaxDimension 1024
  pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\a.png -Op similarity -CompareTo .\b.jpg
  pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputsJson '{"input":"page.png","op":"tile","tile_cols":2,"tile_rows":2}'
#>
[CmdletBinding()]
param(
    [string]$InputFile,
    [string]$Op = 'meta',
    [int]$Width,
    [int]$Height,
    [string]$Mode = 'fit',
    [int]$MaxDimension,
    [string]$Resample = 'lanczos',
    [switch]$AllowUpscale,
    [double]$X,
    [double]$Y,
    [double]$CropWidth,
    [double]$CropHeight,
    [switch]$Normalized,
    [string]$Region,
    [double]$RegionFraction = 0.5,
    [string]$Format,
    [int]$Quality = 90,
    [string]$OutputName,
    [int]$TileCols,
    [int]$TileRows,
    [int]$TileWidth,
    [int]$TileHeight,
    [int]$TileOverlap = 0,
    [string]$CompareTo,
    [int]$HashSize = 8,
    [switch]$NoPerceptualHash,
    [string]$PythonPath,
    [string]$ImageWorkerPath,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'image.util'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bound = $PSBoundParameters
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[image.util] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { return $o.$n } return $d }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}
function Resolve-SystemPython([string]$FallbackLiteral, [string]$StartDir = $PSScriptRoot) {
    # ADDITIVE portability seam (FANOUT_AGENT_002, i17 plan fo-17-3a115347): a machine config
    # (ops\setup\config.json -> python_interpreters.system, resolved via Resolve-LifeorchInterpreter) MAY
    # relocate the SYSTEM python on a fresh box. Return the CONFIGURED interpreter ONLY when it (a) came
    # from config, (b) DIFFERS from the literal, and (c) exists as a file; otherwise return the literal
    # UNCHANGED -- so on-box behavior is byte-identical and nothing breaks if config is absent. Fail-closed
    # to the literal on ANY error. Pure lookup (no probe), ASCII-only. The model-bound SPEECH venv is out
    # of scope (role 'system' only).
    try {
        $p = Get-Item -LiteralPath $StartDir -ErrorAction Stop
        for ($k = 0; $k -lt 8 -and $null -ne $p; $k++) {
            $cfgMod = Join-Path $p.FullName 'ops\setup\LifeorchConfig.psm1'
            if (Test-Path -LiteralPath $cfgMod -PathType Leaf) {
                Import-Module $cfgMod -DisableNameChecking -Force -ErrorAction Stop
                $res = Resolve-LifeorchInterpreter -Role 'system' -Fallback $FallbackLiteral
                $cand = [string]$res.path
                if ($res.source -eq 'config' -and -not [string]::IsNullOrWhiteSpace($cand) -and ($cand -ne $FallbackLiteral) -and (Test-Path -LiteralPath $cand -PathType Leaf)) {
                    return $cand
                }
                break
            }
            $p = $p.Parent
        }
    } catch { }
    return $FallbackLiteral
}
function Test-Python([string]$exe) {
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    try {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $exe -c 'import PIL, numpy' 2>$null | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $prev
        return $ok
    } catch { return $false }
}
function Invoke-Worker([string]$exe, [string[]]$argv) {
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $exe @argv 2> $tmpErr.FullName
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $err = ''; try { $err = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    return @{ exit = $code; out = ($out | Out-String); err = $err }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null
$confidence = $null; $modelProvenance = @(); $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    # ---- merge -InputsJson (explicit named params win) ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw [PSCustomObject]@{ code='invalid_inputs_json'; message='-InputsJson is not valid JSON'; retryable=$false } }
    }
    if ($null -ne $p) {
        if ((Has $p 'input')       -and -not $bound.ContainsKey('InputFile'))        { $InputFile = [string]$p.input }
        if ((Has $p 'op')          -and -not $bound.ContainsKey('Op'))               { $Op = [string]$p.op }
        if ((Has $p 'mode')        -and -not $bound.ContainsKey('Mode'))             { $Mode = [string]$p.mode }
        if ((Has $p 'resample')    -and -not $bound.ContainsKey('Resample'))         { $Resample = [string]$p.resample }
        if ((Has $p 'allow_upscale') -and -not $bound.ContainsKey('AllowUpscale'))   { if ([bool]$p.allow_upscale) { $AllowUpscale = [switch]$true } }
        if ((Has $p 'normalized')  -and -not $bound.ContainsKey('Normalized'))       { if ([bool]$p.normalized) { $Normalized = [switch]$true } }
        if ((Has $p 'no_perceptual_hash') -and -not $bound.ContainsKey('NoPerceptualHash')) { if ([bool]$p.no_perceptual_hash) { $NoPerceptualHash = [switch]$true } }
        if ((Has $p 'region')      -and -not $bound.ContainsKey('Region'))           { $Region = [string]$p.region }
        if ((Has $p 'region_fraction') -and -not $bound.ContainsKey('RegionFraction')) { $RegionFraction = [double]$p.region_fraction }
        if ((Has $p 'format')      -and -not $bound.ContainsKey('Format'))           { $Format = [string]$p.format }
        if ((Has $p 'quality')     -and -not $bound.ContainsKey('Quality'))          { $Quality = [int]$p.quality }
        if ((Has $p 'output_name') -and -not $bound.ContainsKey('OutputName'))       { $OutputName = [string]$p.output_name }
        if ((Has $p 'tile_overlap') -and -not $bound.ContainsKey('TileOverlap'))     { $TileOverlap = [int]$p.tile_overlap }
        if ((Has $p 'compare_to')  -and -not $bound.ContainsKey('CompareTo'))        { $CompareTo = [string]$p.compare_to }
        if ((Has $p 'hash_size')   -and -not $bound.ContainsKey('HashSize'))         { $HashSize = [int]$p.hash_size }
        if ((Has $p 'python_path') -and -not $bound.ContainsKey('PythonPath'))       { $PythonPath = [string]$p.python_path }
        if ((Has $p 'image_worker_path') -and -not $bound.ContainsKey('ImageWorkerPath')) { $ImageWorkerPath = [string]$p.image_worker_path }
    }
    # presence tracking for the conditional numeric fields (0 is a valid value, so we must not send them unset)
    $hasWidth = $bound.ContainsKey('Width');            if ($null -ne $p -and (Has $p 'width') -and -not $hasWidth) { $Width = [int]$p.width; $hasWidth = $true }
    $hasHeight = $bound.ContainsKey('Height');           if ($null -ne $p -and (Has $p 'height') -and -not $hasHeight) { $Height = [int]$p.height; $hasHeight = $true }
    $hasMaxDim = $bound.ContainsKey('MaxDimension');     if ($null -ne $p -and (Has $p 'max_dimension') -and -not $hasMaxDim) { $MaxDimension = [int]$p.max_dimension; $hasMaxDim = $true }
    $hasX = $bound.ContainsKey('X');                     if ($null -ne $p -and (Has $p 'x') -and -not $hasX) { $X = [double]$p.x; $hasX = $true }
    $hasY = $bound.ContainsKey('Y');                     if ($null -ne $p -and (Has $p 'y') -and -not $hasY) { $Y = [double]$p.y; $hasY = $true }
    $hasCW = $bound.ContainsKey('CropWidth');            if ($null -ne $p -and (Has $p 'crop_width') -and -not $hasCW) { $CropWidth = [double]$p.crop_width; $hasCW = $true }
    $hasCH = $bound.ContainsKey('CropHeight');           if ($null -ne $p -and (Has $p 'crop_height') -and -not $hasCH) { $CropHeight = [double]$p.crop_height; $hasCH = $true }
    $hasTCols = $bound.ContainsKey('TileCols');          if ($null -ne $p -and (Has $p 'tile_cols') -and -not $hasTCols) { $TileCols = [int]$p.tile_cols; $hasTCols = $true }
    $hasTRows = $bound.ContainsKey('TileRows');          if ($null -ne $p -and (Has $p 'tile_rows') -and -not $hasTRows) { $TileRows = [int]$p.tile_rows; $hasTRows = $true }
    $hasTW = $bound.ContainsKey('TileWidth');            if ($null -ne $p -and (Has $p 'tile_width') -and -not $hasTW) { $TileWidth = [int]$p.tile_width; $hasTW = $true }
    $hasTH = $bound.ContainsKey('TileHeight');           if ($null -ne $p -and (Has $p 'tile_height') -and -not $hasTH) { $TileHeight = [int]$p.tile_height; $hasTH = $true }

    if ([string]::IsNullOrWhiteSpace($Op)) { $Op = 'meta' }
    $Op = $Op.ToLowerInvariant()
    $validOps = @('meta','resize','crop','convert','tile','similarity')
    if ($validOps -notcontains $Op) {
        throw [PSCustomObject]@{ code='invalid_op'; message="unknown op '$Op' (meta|resize|crop|convert|tile|similarity)"; retryable=$false }
    }

    # ---- resolve + validate input ----
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        throw [PSCustomObject]@{ code='input_not_found'; message='no input image specified (-InputFile / InputsJson.input)'; retryable=$false }
    }
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
        throw [PSCustomObject]@{ code='input_not_found'; message="input image not found: $InputFile"; retryable=$false }
    }
    $imagePath = (Resolve-Path -LiteralPath $InputFile).Path

    $comparePath = $null
    if (-not [string]::IsNullOrWhiteSpace($CompareTo)) {
        if (-not (Test-Path -LiteralPath $CompareTo -PathType Leaf)) {
            throw [PSCustomObject]@{ code='compare_not_found'; message="compare_to image not found: $CompareTo"; retryable=$false }
        }
        $comparePath = (Resolve-Path -LiteralPath $CompareTo).Path
    }
    if ($Op -eq 'similarity' -and $null -eq $comparePath) {
        throw [PSCustomObject]@{ code='missing_params'; message='op=similarity needs -CompareTo (a second image)'; retryable=$false }
    }

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # ---- normalized inputs digest ----
    $normInputs = [ordered]@{ input=$imagePath; op=$Op; mode=$Mode; resample=$Resample;
        max_dimension=$(if ($hasMaxDim) { [int]$MaxDimension } else { $null });
        width=$(if ($hasWidth) { [int]$Width } else { $null }); height=$(if ($hasHeight) { [int]$Height } else { $null });
        allow_upscale=[bool]$AllowUpscale; normalized=[bool]$Normalized;
        x=$(if ($hasX) { [double]$X } else { $null }); y=$(if ($hasY) { [double]$Y } else { $null });
        crop_width=$(if ($hasCW) { [double]$CropWidth } else { $null }); crop_height=$(if ($hasCH) { [double]$CropHeight } else { $null });
        region=$Region; region_fraction=$RegionFraction; format=$Format; quality=$Quality; output_name=$OutputName;
        tile_cols=$(if ($hasTCols) { [int]$TileCols } else { $null }); tile_rows=$(if ($hasTRows) { [int]$TileRows } else { $null });
        tile_width=$(if ($hasTW) { [int]$TileWidth } else { $null }); tile_height=$(if ($hasTH) { [int]$TileHeight } else { $null });
        tile_overlap=$TileOverlap; compare_to=$comparePath; hash_size=$HashSize; no_perceptual_hash=[bool]$NoPerceptualHash }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress -Depth 8)))

    # ---- resolve python (Pillow+numpy) ----
    $cands = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $cands.Add($PythonPath) }
    # ADDITIVE portability seam (FANOUT_AGENT_002, i17): prepend a machine-configured SYSTEM python
    # (config.json python_interpreters.system) BEFORE the literal, ONLY when it differs + exists; adds
    # nothing when config is absent or == the literal (byte-identical on this box). Fail-closed.
    $sysPyLiteral = 'C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe'
    try { $cfgPy = Resolve-SystemPython $sysPyLiteral; if ($cfgPy -ne $sysPyLiteral) { $cands.Add($cfgPy) } } catch { }
    $cands.Add($sysPyLiteral)
    $cands.Add('F:\My_Programs\Local_Computer_Speech_Large_Data\python_env\Scripts\python.exe')
    foreach ($n in @('python','python3','py')) {
        try {
            $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $w = & where.exe $n 2>$null
            $ErrorActionPreference = $prev
            foreach ($line in @([string[]]$w)) { if (-not [string]::IsNullOrWhiteSpace($line)) { $cands.Add($line.Trim()) } }
        } catch { }
    }
    $python = $null
    foreach ($c in $cands.ToArray()) {
        if (Test-Python $c) { $python = $c; break }
    }
    if ([string]::IsNullOrWhiteSpace($python)) {
        throw [PSCustomObject]@{ code='python_not_found'; message="no python with Pillow+numpy found (tried: $((($cands.ToArray()) | Select-Object -Unique) -join ', ')). Set -PythonPath."; retryable=$false }
    }

    # ---- resolve the worker ----
    if ([string]::IsNullOrWhiteSpace($ImageWorkerPath)) { $ImageWorkerPath = Join-Path $PSScriptRoot 'image_worker.py' }
    if (-not (Test-Path -LiteralPath $ImageWorkerPath -PathType Leaf)) {
        throw [PSCustomObject]@{ code='worker_not_found'; message="image_worker.py not found at '$ImageWorkerPath' (set -ImageWorkerPath)"; retryable=$false }
    }
    $ImageWorkerPath = (Resolve-Path -LiteralPath $ImageWorkerPath).Path

    # ---- build worker args (meta-file hand-off) ----
    $metaPath = Join-Path $invDir 'image_meta.json'
    $wargs = [ordered]@{
        input = $imagePath; op = $Op; output_dir = $invDir; meta_path = $metaPath
        hash_size = [int]$HashSize; no_perceptual_hash = [bool]$NoPerceptualHash
        mode = $Mode; resample = $Resample; allow_upscale = [bool]$AllowUpscale; normalized = [bool]$Normalized
        region_fraction = [double]$RegionFraction; quality = [int]$Quality; tile_overlap = [int]$TileOverlap
    }
    if ($hasWidth)  { $wargs.width = [int]$Width }
    if ($hasHeight) { $wargs.height = [int]$Height }
    if ($hasMaxDim) { $wargs.max_dimension = [int]$MaxDimension }
    if ($hasX)      { $wargs.x = [double]$X }
    if ($hasY)      { $wargs.y = [double]$Y }
    if ($hasCW)     { $wargs.crop_width = [double]$CropWidth }
    if ($hasCH)     { $wargs.crop_height = [double]$CropHeight }
    if ($hasTCols)  { $wargs.tile_cols = [int]$TileCols }
    if ($hasTRows)  { $wargs.tile_rows = [int]$TileRows }
    if ($hasTW)     { $wargs.tile_width = [int]$TileWidth }
    if ($hasTH)     { $wargs.tile_height = [int]$TileHeight }
    if (-not [string]::IsNullOrWhiteSpace($Format))     { $wargs.format = $Format }
    if (-not [string]::IsNullOrWhiteSpace($Region))     { $wargs.region = $Region }
    if (-not [string]::IsNullOrWhiteSpace($OutputName)) { $wargs.output_name = $OutputName }
    if ($null -ne $comparePath)                          { $wargs.compare_to = $comparePath }
    $argsFile = Join-Path $invDir 'image_args.json'
    [System.IO.File]::WriteAllText($argsFile, ($wargs | ConvertTo-Json -Depth 8), $utf8)

    Write-Diag "python=$python worker=$ImageWorkerPath op=$Op input=$imagePath"
    $run = Invoke-Worker $python @($ImageWorkerPath, $argsFile)
    try { [System.IO.File]::WriteAllText((Join-Path $invDir 'worker.log'), ("EXIT $($run.exit)`n== STDOUT ==`n" + $run.out + "`n== STDERR ==`n" + $run.err + "`n"), $utf8) } catch { }

    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        $tail = [string]$run.err; if ([string]::IsNullOrWhiteSpace($tail)) { $tail = [string]$run.out }
        if ($tail.Length -gt 700) { $tail = $tail.Substring($tail.Length - 700) }
        throw [PSCustomObject]@{ code='image_util_failed'; message="image worker produced no meta (exit $($run.exit)): $($tail.Trim())"; retryable=$true }
    }
    $meta = (Get-Content -LiteralPath $metaPath -Raw) | ConvertFrom-Json
    if (-not [bool](Prop $meta 'ok' $false)) {
        $ec = [string](Prop $meta 'error_code' 'image_util_failed'); $em = [string](Prop $meta 'error' 'image worker failed')
        throw [PSCustomObject]@{ code=$ec; message=$em; retryable=$false }
    }

    # ---- enrich outputs with sha256 (wrapper owns artifact hashing) ----
    $outList = New-Object System.Collections.Generic.List[object]
    foreach ($om in @(Prop $meta 'outputs' @())) {
        $opath = [string](Prop $om 'path' '')
        $bytes = [int](Prop $om 'bytes' 0); $sha = $null
        if (-not [string]::IsNullOrWhiteSpace($opath) -and (Test-Path -LiteralPath $opath -PathType Leaf)) {
            $b = [System.IO.File]::ReadAllBytes($opath); $sha = (Get-Sha256Hex $b); $bytes = $b.Length
        }
        $outList.Add([ordered]@{ path=$opath; format=(Prop $om 'format' $null); mode=(Prop $om 'mode' $null);
            width=[int](Prop $om 'width' 0); height=[int](Prop $om 'height' 0); bytes=$bytes; sha256=$sha })
    }
    foreach ($w in @(Prop $meta 'warnings' @())) { $warnings.Add([string]$w) }

    $result = [ordered]@{
        input      = (Prop $meta 'input' $null)
        op         = $Op
        params     = [ordered]@{ op=$Op; format=$Format; quality=$Quality; output_name=$OutputName; hash_size=$HashSize; no_perceptual_hash=[bool]$NoPerceptualHash }
        metadata   = (Prop $meta 'metadata' $null)
        hashes     = (Prop $meta 'hashes' $null)
        outputs    = $outList.ToArray()
        resize     = (Prop $meta 'resize' $null)
        crop       = (Prop $meta 'crop' $null)
        tile       = (Prop $meta 'tile' $null)
        similarity = (Prop $meta 'similarity' $null)
        runtime_ms = [int](Prop $meta 'runtime_ms' 0)
        worker     = (Prop $meta 'worker' $null)
    }
    Write-Diag "ok op=$Op outputs=$($outList.Count) sha256=$((Prop $result.hashes 'sha256' ''))"
}
catch {
    $ex = $_.TargetObject
    if ($null -ne $ex -and $ex -is [System.Management.Automation.PSCustomObject] -and (Has $ex 'code')) {
        $status = 'error'; $errorObj = [ordered]@{ code=[string]$ex.code; message=[string]$ex.message; retryable=[bool]$ex.retryable }
    } else {
        $status = 'error'; $errorObj = [ordered]@{ code='unhandled_exception'; message="$($_.Exception.Message)"; retryable=$false }
        Write-Diag "STACK line $($_.InvocationInfo.ScriptLineNumber): $($_.ScriptStackTrace)"
    }
    Write-Diag "ERROR: $($errorObj.code) -- $($errorObj.message)"
}

# ---- artifacts ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $ij = [ordered]@{ schema='lifeorch.image.util/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o');
            op=$result.op; input=$result.input; metadata=$result.metadata; hashes=$result.hashes; outputs=$result.outputs;
            resize=$result.resize; crop=$result.crop; tile=$result.tile; similarity=$result.similarity; worker=$result.worker }
        $ijPath = Join-Path $invDir 'image.json'
        [System.IO.File]::WriteAllText($ijPath, ($ij | ConvertTo-Json -Depth 20), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        $md = $result.metadata
        [void]$mb.AppendLine("# image.util -- $($result.op)")
        [void]$mb.AppendLine("input: $((Prop $result.input 'path' ''))")
        [void]$mb.AppendLine("size: $((Prop $md 'width' 0))x$((Prop $md 'height' 0))  format=$((Prop $md 'format' ''))  mode=$((Prop $md 'mode' ''))  alpha=$((Prop $md 'has_alpha' $false))  bytes=$((Prop $result.input 'bytes' 0))")
        $hh = $result.hashes
        [void]$mb.AppendLine("sha256: $((Prop $hh 'sha256' ''))")
        [void]$mb.AppendLine("phash: $((Prop $hh 'phash' ''))  dhash: $((Prop $hh 'dhash' ''))")
        if ($null -ne $result.resize) { $rz = $result.resize; [void]$mb.AppendLine("resize: mode=$((Prop $rz 'mode' '')) $((Prop $rz.original 'width' 0))x$((Prop $rz.original 'height' 0)) -> $((Prop $rz.result 'width' 0))x$((Prop $rz.result 'height' 0))  scale=($((Prop $rz 'scale_x' 0)),$((Prop $rz 'scale_y' 0)))") }
        if ($null -ne $result.crop)   { $cr = $result.crop; $ap=$cr.applied; [void]$mb.AppendLine("crop: applied x=$((Prop $ap 'x' 0)) y=$((Prop $ap 'y' 0)) w=$((Prop $ap 'width' 0)) h=$((Prop $ap 'height' 0))") }
        if ($null -ne $result.tile)   { $tl = $result.tile; [void]$mb.AppendLine("tile: mode=$((Prop $tl 'mode' '')) cols=$((Prop $tl 'cols' 0)) rows=$((Prop $tl 'rows' 0)) count=$((Prop $tl 'count' 0)) overlap=$((Prop $tl 'overlap' 0))") }
        if ($null -ne $result.similarity) { $si = $result.similarity; [void]$mb.AppendLine("similarity: hamming_phash=$((Prop $si 'hamming_phash' '')) / $((Prop $si 'hash_bits' 0))  similarity=$((Prop $si 'similarity' ''))") }
        $outs = @($result.outputs)
        if ($outs.Count -gt 0) {
            [void]$mb.AppendLine('')
            [void]$mb.AppendLine('## outputs')
            [void]$mb.AppendLine('')
            [void]$mb.AppendLine('| # | file | format | wxh | bytes |')
            [void]$mb.AppendLine('|---|------|--------|-----|-------|')
            $oi = 0
            foreach ($o in $outs) {
                if ($oi -ge 60) { [void]$mb.AppendLine("| ... | | | | ($($outs.Count - 60) more -- see image.json) |"); break }
                $nm = Split-Path -Leaf ([string]$o.path)
                [void]$mb.AppendLine("| $oi | $nm | $($o.format) | $($o.width)x$($o.height) | $($o.bytes) |")
                $oi++
            }
        }
        $imPath = Join-Path $invDir 'image.md'
        [System.IO.File]::WriteAllText($imPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        $artList.Add([pscustomobject]@{ p=$ijPath; k='json' })
        $artList.Add([pscustomobject]@{ p=$imPath; k='markdown' })
        foreach ($o in $outs) { if (-not [string]::IsNullOrWhiteSpace([string]$o.path)) { $artList.Add([pscustomobject]@{ p=[string]$o.path; k='image' }) } }
        foreach ($a in $artList.ToArray()) {
            if (Test-Path -LiteralPath $a.p -PathType Leaf) {
                $b = [System.IO.File]::ReadAllBytes($a.p)
                $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
            }
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[image.util] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { Write-Diag "artifact write failed: $($_.Exception.Message)" }

if ($status -eq 'ok' -and $warnings.Count -gt 0) { $status = 'partial' }

$sw.Stop()
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds
    inputs_digest=$(if ($inputsDigest) { $inputsDigest } else { 'sha256:' + (Get-Sha256Hex $utf8.GetBytes('')) })
    result=$result; confidence=$confidence; artifacts=$artifacts; model_provenance=$modelProvenance
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
