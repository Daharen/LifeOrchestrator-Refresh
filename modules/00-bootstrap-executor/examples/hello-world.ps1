# hello-world.ps1
# Minimal successful task: prints a line and exits 0.
Write-Output "Hello from the bootstrap executor."
Write-Output "PID: $PID"
Write-Output "Time (UTC): $([DateTime]::UtcNow.ToString('o'))"
exit 0
