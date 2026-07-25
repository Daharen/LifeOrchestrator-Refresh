# ocr_worker.ps1 -- Windows.Media.Ocr inference worker for ocr.layout (Life Orchestrator, Module 14).
# NOTE: this file MUST stay ASCII-only. Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, not UTF-8,
# so any non-ASCII byte here breaks parsing (a UTF-8 em dash once did -- m14-diag-002).
#
# MUST run under Windows PowerShell 5.1 (powershell.exe): pwsh 7 cannot load the WinRT projection on this
# box (confirmed m14-probe-001). Reaches the system OCR engine via the classic System.Runtime.WindowsRuntime
# AsTask/Await reflection pattern.
#
# Contract with the pwsh-7 wrapper (Invoke-OcrLayout.ps1):
#   argv: -ArgsFile <path to a JSON args file>
#     { image_path, meta_path, language, max_dimension? }
#   Recognizes text in image_path, then writes meta_path with a JSON result. Only meta_path is authoritative;
#   stdout/stderr are diagnostics (captured to worker.log by the wrapper). Exit 0 on success, non-zero on
#   failure (meta_path is written in both cases whenever meta_path is known).
#
#   meta (ok):    { ok:true, engine_language, available_languages[], max_image_dimension, image_w, image_h,
#                   text, text_angle, ocr_ms, lines:[ { text, words:[ {text,x,y,w,h} ] } ] }
#   meta (error): { ok:false, error_code, error }
param([string]$ArgsFile)
$ErrorActionPreference = 'Stop'
$u = [System.Text.UTF8Encoding]::new($false)

$metaPath = $null
function Write-Meta($d) {
    if ([string]::IsNullOrWhiteSpace($metaPath)) { return }
    [System.IO.File]::WriteAllText($metaPath, ($d | ConvertTo-Json -Depth 8), $u)
}

try {
    if ([string]::IsNullOrWhiteSpace($ArgsFile) -or -not (Test-Path -LiteralPath $ArgsFile)) {
        throw "args file not found: $ArgsFile"
    }
    $a = (Get-Content -LiteralPath $ArgsFile -Raw) | ConvertFrom-Json
    $metaPath  = [string]$a.meta_path
    $imagePath = [string]$a.image_path
    $language  = ''
    if ($a.PSObject.Properties.Name -contains 'language' -and $null -ne $a.language) { $language = [string]$a.language }

    if ([string]::IsNullOrWhiteSpace($imagePath) -or -not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
        Write-Meta @{ ok = $false; error_code = 'input_not_found'; error = "image not found: $imagePath" }
        Write-Output 'worker-done ok=False (input_not_found)'; exit 1
    }
    $imagePath = (Resolve-Path -LiteralPath $imagePath).Path

    # --- WinRT bootstrap (Await reflection) ---
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    function Await($op, $t) { $mm = $asTaskGeneric.MakeGenericMethod($t); $tk = $mm.Invoke($null, @($op)); $tk.Wait(-1) | Out-Null; $tk.Result }

    [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]                  | Out-Null
    [Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]     | Out-Null
    [Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]    | Out-Null
    [Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]                 | Out-Null
    [Windows.Media.Ocr.OcrResult,Windows.Media.Ocr,ContentType=WindowsRuntime]                 | Out-Null
    [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]          | Out-Null

    $maxDim = [int][Windows.Media.Ocr.OcrEngine]::MaxImageDimension
    $langs = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag })

    # --- create the engine: requested language > user profile > first available ---
    $engine = $null
    if (-not [string]::IsNullOrWhiteSpace($language)) {
        try { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language($language))) } catch { $engine = $null }
        if ($null -eq $engine) {
            Write-Meta @{ ok = $false; error_code = 'language_unavailable'; error = "no OCR recognizer for language '$language'"; available_languages = $langs }
            Write-Output 'worker-done ok=False (language_unavailable)'; exit 1
        }
    }
    if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
    if ($null -eq $engine -and $langs.Count -gt 0) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language($langs[0]))) }
    if ($null -eq $engine) {
        Write-Meta @{ ok = $false; error_code = 'no_ocr_language'; error = 'no OCR language pack available on this machine'; available_languages = $langs }
        Write-Output 'worker-done ok=False (no_ocr_language)'; exit 1
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sf     = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($imagePath)) ([Windows.Storage.StorageFile])
    $stream = Await ($sf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $dec    = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $iw = [int]$dec.PixelWidth; $ih = [int]$dec.PixelHeight

    if ($iw -gt $maxDim -or $ih -gt $maxDim) {
        Write-Meta @{ ok = $false; error_code = 'image_too_large'; error = "image ${iw}x${ih} exceeds MaxImageDimension $maxDim (downscale first; see image.util, Module 15)"; image_w = $iw; image_h = $ih; max_image_dimension = $maxDim }
        Write-Output 'worker-done ok=False (image_too_large)'; exit 1
    }

    $sb  = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res = Await ($engine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
    $sw.Stop()

    $lines = @()
    foreach ($ln in $res.Lines) {
        $words = @()
        foreach ($w in $ln.Words) {
            $r = $w.BoundingRect
            $words += [ordered]@{ text = [string]$w.Text; x = [math]::Round([double]$r.X, 1); y = [math]::Round([double]$r.Y, 1); w = [math]::Round([double]$r.Width, 1); h = [math]::Round([double]$r.Height, 1) }
        }
        $lines += [ordered]@{ text = [string]$ln.Text; words = $words }
    }

    $angle = $null
    if ($null -ne $res.TextAngle) { $angle = [math]::Round([double]$res.TextAngle, 2) }

    Write-Meta ([ordered]@{
        ok = $true
        engine_language = $engine.RecognizerLanguage.LanguageTag
        available_languages = $langs
        max_image_dimension = $maxDim
        image_w = $iw; image_h = $ih
        text = [string]$res.Text
        text_angle = $angle
        ocr_ms = [int]$sw.ElapsedMilliseconds
        lines = $lines
        line_count = $lines.Count
    })
    Write-Output ("worker-done ok=True lines=" + $lines.Count)
    exit 0
}
catch {
    $msg = $_.Exception.Message
    try { Write-Meta @{ ok = $false; error_code = 'ocr_worker_error'; error = "$msg" } } catch { }
    [Console]::Error.WriteLine("ocr_worker error: $msg")
    Write-Output 'worker-done ok=False (exception)'
    exit 1
}
