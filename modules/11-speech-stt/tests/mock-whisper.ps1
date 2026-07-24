#requires -Version 7.0
# mock-whisper.ps1 — a stand-in for whisper-cli.exe for OFF-GPU logic tests (no GPU/model needed).
# It parses the -of <base> argument like whisper-cli and writes <base>.json/.srt/.txt from a captured
# real fixture (tests/fixtures/jfk.whisper.json by default, or $env:MOCK_WHISPER_JSON). This lets the
# REAL Invoke-SpeechStt.ps1 parse/confidence/segment/review/envelope code run unchanged on the cloud
# Linux box before any bytes ship to Windows (mirrors Modules 8/9 mock-gateway.ps1).
param()
$ErrorActionPreference = 'Stop'
$argv = @($args)
$base = $null
for ($i = 0; $i -lt $argv.Count; $i++) {
    if (($argv[$i] -eq '-of') -or ($argv[$i] -eq '--output-file')) { if ($i + 1 -lt $argv.Count) { $base = [string]$argv[$i + 1] }; break }
}
if ([string]::IsNullOrWhiteSpace($base)) { [Console]::Error.WriteLine('mock-whisper: no -of <base> argument'); exit 1 }
$fx = $env:MOCK_WHISPER_JSON
if ([string]::IsNullOrWhiteSpace($fx)) { $fx = Join-Path $PSScriptRoot 'fixtures/jfk.whisper.json' }
if (-not (Test-Path -LiteralPath $fx -PathType Leaf)) { [Console]::Error.WriteLine("mock-whisper: fixture not found: $fx"); exit 1 }
$utf8 = [System.Text.UTF8Encoding]::new($false)
$raw = Get-Content -LiteralPath $fx -Raw
[System.IO.File]::WriteAllText("$base.json", $raw, $utf8)
$o = $raw | ConvertFrom-Json
$segments = @(); if ($o.PSObject.Properties.Name -contains 'transcription') { $segments = @($o.transcription) }
$txt = (($segments | ForEach-Object { ([string]$_.text).Trim() }) -join ' ')
[System.IO.File]::WriteAllText("$base.txt", $txt + "`n", $utf8)
$sb = [System.Text.StringBuilder]::new(); $n = 1
foreach ($s in $segments) {
    [void]$sb.AppendLine([string]$n)
    [void]$sb.AppendLine("$($s.timestamps.from) --> $($s.timestamps.to)")
    [void]$sb.AppendLine(([string]$s.text).Trim())
    [void]$sb.AppendLine('')
    $n++
}
[System.IO.File]::WriteAllText("$base.srt", $sb.ToString(), $utf8)
[Console]::Out.WriteLine("mock-whisper: wrote $base.json/.srt/.txt from $fx")
exit 0
