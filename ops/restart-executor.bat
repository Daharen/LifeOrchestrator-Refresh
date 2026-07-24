@echo off
setlocal
set "PWSH=C:\Users\just_\.dotnet\tools\pwsh.exe"
set "EXE=C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor"
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%EXE%\Stop-BootstrapExecutor.ps1"
echo Waiting for shutdown...
timeout /t 8 /nobreak >nul
start "LifeOrchestrator Executor" /min "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%EXE%\Start-BootstrapExecutor.ps1"
echo Restarted (stop requested, then relaunched minimized).
pause
