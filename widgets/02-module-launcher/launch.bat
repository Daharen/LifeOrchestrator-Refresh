@echo off
rem ============================================================================
rem  Module Launcher & Registry Browser (Widget 02) launcher - double-click to open.
rem  Runs the WinForms UI under the per-user PowerShell 7 in STA mode.
rem ============================================================================
setlocal
set "PWSH=%USERPROFILE%\.dotnet\tools\pwsh.exe"
if not exist "%PWSH%" set "PWSH=pwsh.exe"
"%PWSH%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-ModuleLauncher.ps1"
if not "%ERRORLEVEL%"=="0" echo(& echo The launcher exited with an error (code %ERRORLEVEL%).& pause
endlocal
