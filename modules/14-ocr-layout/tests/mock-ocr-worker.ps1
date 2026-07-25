#requires -Version 7.0
# mock-ocr-worker.ps1 — stand-in for ocr_worker.ps1 for OFF-WINDOWS logic tests (no WinRT / no OCR engine).
# It reads the -ArgsFile like the real worker and writes its meta_path from a captured real meta
# (tests/fixtures/ocr-sample.meta.json by default, or $env:MOCK_OCR_META). This lets the REAL
# Invoke-OcrLayout.ps1 parse/reading-order/confidence/review/envelope code run unchanged on the cloud
# Linux box before any bytes ship to Windows (mirrors Modules 8/9/11 mock shims).
param([string]$ArgsFile)
$ErrorActionPreference = 'Stop'
$u = [System.Text.UTF8Encoding]::new($false)
if ([string]::IsNullOrWhiteSpace($ArgsFile) -or -not (Test-Path -LiteralPath $ArgsFile -PathType Leaf)) {
    [Console]::Error.WriteLine("mock-ocr: args file not found: $ArgsFile"); exit 1
}
$a = (Get-Content -LiteralPath $ArgsFile -Raw) | ConvertFrom-Json
$metaPath = [string]$a.meta_path
if ([string]::IsNullOrWhiteSpace($metaPath)) { [Console]::Error.WriteLine('mock-ocr: no meta_path in args'); exit 1 }
$fx = $env:MOCK_OCR_META
if ([string]::IsNullOrWhiteSpace($fx)) { $fx = Join-Path $PSScriptRoot 'fixtures/ocr-sample.meta.json' }
if (-not (Test-Path -LiteralPath $fx -PathType Leaf)) { [Console]::Error.WriteLine("mock-ocr: fixture meta not found: $fx"); exit 1 }
$raw = Get-Content -LiteralPath $fx -Raw
[System.IO.File]::WriteAllText($metaPath, $raw, $u)
[Console]::Out.WriteLine("mock-ocr: wrote meta from $fx")
exit 0
