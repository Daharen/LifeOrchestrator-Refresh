@echo off
setlocal
set "PWSH=C:\Users\just_\.dotnet\tools\pwsh.exe"
set "EXE=C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor"
if not exist "%~dp0out" mkdir "%~dp0out"
start "LifeOrchestrator Executor" /min "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%EXE%\Start-BootstrapExecutor.ps1"
echo Launched Life Orchestrator executor (minimized) at %DATE% %TIME%> "%~dp0out\start.txt"
echo Life Orchestrator executor launched in a minimized window. Leave it running.
echo (If one is already running, the second exits immediately via the single-instance lock.)
pause
