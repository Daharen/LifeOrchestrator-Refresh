@echo off
rem ============================================================================
rem  Provenance Map (Widget 05) launcher - double-click to open.
rem  Runs the read-only WinForms construction map under the per-user PowerShell 7
rem  in STA mode. Reads the canonical on-disk docs + read-only git; writes nothing
rem  outside its own runtime\ dir.
rem ============================================================================
setlocal
set "PWSH=%USERPROFILE%\.dotnet\tools\pwsh.exe"
if not exist "%PWSH%" set "PWSH=pwsh.exe"
"%PWSH%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-ProvenanceMap.ps1" %*
if not "%ERRORLEVEL%"=="0" echo(& echo The Provenance Map exited with an error (code %ERRORLEVEL%).& pause
endlocal
