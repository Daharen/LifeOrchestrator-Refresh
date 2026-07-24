#requires -Version 7.0
param([string]$Runtime = 'C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor\runtime')
$out = Join-Path $PSScriptRoot 'out\status.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$sb = [System.Text.StringBuilder]::new()
function W($s){ [void]$sb.AppendLine([string]$s) }
W ("Life Orchestrator executor status @ " + [DateTime]::Now.ToString('o'))
W ("Runtime: $Runtime")
W ("Lock present: " + (Test-Path (Join-Path $Runtime 'control\executor.lock')))
foreach ($d in 'pending','running','completed','failed') {
    $p = Join-Path $Runtime $d
    $n = if (Test-Path $p) { (Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue).Count } else { 0 }
    W ("{0,-10} {1}" -f "$d`:", $n)
}
$log = Join-Path $Runtime 'logs\executor.log'
if (Test-Path $log) { W "--- last 8 log lines ---"; Get-Content -LiteralPath $log -Tail 8 | ForEach-Object { W $_ } }
$txt = $sb.ToString()
[System.IO.File]::WriteAllText($out, $txt, [System.Text.UTF8Encoding]::new($false))
Write-Output $txt
