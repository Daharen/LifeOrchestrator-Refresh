@echo off
setlocal
set "PWSH=C:\Users\just_\.dotnet\tools\pwsh.exe"
set "WD=C:\Users\just_\LifeOrchestrator-Refresh\modules\00.1-exec-watchdog"
if not exist "%~dp0out" mkdir "%~dp0out"
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%WD%\Recover-Executor.ps1" %* > "%~dp0out\recover.txt" 2>&1
type "%~dp0out\recover.txt"
echo.
echo (On-demand recovery. Pass -Force to kill and restart even a healthy executor,
echo  e.g.  recover-executor.bat -Force  - your "interrupt a stuck/slow run and restart it" button.)
pause
