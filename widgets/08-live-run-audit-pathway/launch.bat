@echo off
rem ============================================================================
rem  Live-Run Audit Pathway (Widget 08) launcher - double-click to open.
rem  Renders a REPLAYED #40 context_packet as ONE chronological, plain-language,
rem  intent-vs-actual pathway (the audit program's phenomenological top surface,
rem  D-0120 / AUDIT_PIPELINE.md P9), under the per-user PowerShell 7 in STA mode.
rem  STRICTLY READ-ONLY: it reads an existing compile artifact, calls no model,
rem  holds no lease, pauses nothing, re-compiles nothing, and writes nothing
rem  outside its own runtime\ dir.
rem ============================================================================
setlocal
set "PWSH=%USERPROFILE%\.dotnet\tools\pwsh.exe"
if not exist "%PWSH%" set "PWSH=pwsh.exe"
"%PWSH%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-LiveRunAuditPathway.ps1" %*
if not "%ERRORLEVEL%"=="0" echo(& echo The Live-Run Audit Pathway exited with an error (code %ERRORLEVEL%).& pause
endlocal
