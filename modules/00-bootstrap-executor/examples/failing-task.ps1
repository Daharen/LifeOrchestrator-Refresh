# failing-task.ps1
# Task that fails: writes to stderr and exits non-zero (via throw).
Write-Output "About to fail intentionally (this line goes to stdout)."
Write-Error "failing-task.ps1: intentional error written to stderr."
throw "failing-task.ps1: intentional terminating error (non-zero exit)."
