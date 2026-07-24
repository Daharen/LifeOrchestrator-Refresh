# concurrent-task.ps1
# Sleeps briefly so several copies can be observed running at once.
# The executor invokes scripts with -File and passes no arguments, so the
# default sleep duration is used unless the script is edited.
param(
    [int]$Seconds = 5
)

Write-Output "concurrent-task.ps1: started  PID=$PID  at=$([DateTime]::UtcNow.ToString('o'))"
Start-Sleep -Seconds $Seconds
Write-Output "concurrent-task.ps1: finished PID=$PID  at=$([DateTime]::UtcNow.ToString('o'))"
exit 0
