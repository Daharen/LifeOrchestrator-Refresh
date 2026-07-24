@echo off
setlocal
set "PWSH=C:\Users\just_\.dotnet\tools\pwsh.exe"
set "EXE=C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor"
if not exist "%~dp0out" mkdir "%~dp0out"
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%EXE%\Stop-BootstrapExecutor.ps1" > "%~dp0out\stop.txt" 2>&1
type "%~dp0out\stop.txt"
echo.
echo Stop requested. The executor exits after finishing its current poll cycle.
pause
