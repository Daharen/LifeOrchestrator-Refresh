# timeout-task.ps1
# Long-running task used to verify timeout termination.
# Submit this with a small timeout_seconds (e.g. 3) to see it killed.
Write-Output "timeout-task.ps1: starting a long sleep at $([DateTime]::UtcNow.ToString('o'))"
Start-Sleep -Seconds 3600
Write-Output "timeout-task.ps1: this line should never be reached if the timeout works."
exit 0
