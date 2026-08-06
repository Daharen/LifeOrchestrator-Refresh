$ErrorActionPreference='Stop'
$repo = 'C:\Users\just_\LifeOrchestrator-Refresh'
$lock = Join-Path $repo '.git\index.lock'
$git = @(Get-Process -Name git -ErrorAction SilentlyContinue)
if ($git.Count -gt 0) { Write-Output "ABORT: git.exe running x$($git.Count)"; exit 1 }
if (Test-Path -LiteralPath $lock -PathType Leaf) {
  $len = (Get-Item -LiteralPath $lock).Length
  if ($len -ne 0) { Write-Output "ABORT: index.lock not empty ($len bytes)"; exit 1 }
  Remove-Item -LiteralPath $lock -Force
  Write-Output "REMOVED index.lock (was 0 bytes)"
} else { Write-Output "no index.lock present" }
$head = (& git -C $repo rev-parse HEAD).Trim()
Write-Output "HEAD=$head"
exit 0
