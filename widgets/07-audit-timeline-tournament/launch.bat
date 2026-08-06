@echo off
rem ============================================================================
rem  Audit Timeline + Tournament (Widget 07) launcher - double-click to open.
rem  Renders, STRICTLY READ-ONLY, the audit-pipeline tier A2 slice: the s2.6
rem  tool-selection tournament (router + selpol + plan-validation brackets with a
rem  reconciliation proof) + the s2.1 cross-context omniscient stitched timeline
rem  (a real wave: #30 plan + reports, stitched with #39 episodes + #42
rem  state_version chains + batons-when-present), under the per-user PowerShell 7
rem  in STA mode. It calls no model, holds no lease, pauses nothing, and writes
rem  nothing outside its own runtime\ dir.
rem ============================================================================
setlocal
set "PWSH=%USERPROFILE%\.dotnet\tools\pwsh.exe"
if not exist "%PWSH%" set "PWSH=pwsh.exe"
"%PWSH%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-AuditTimelineTournament.ps1" %*
if not "%ERRORLEVEL%"=="0" echo(& echo The Audit Timeline + Tournament exited with an error (code %ERRORLEVEL%).& pause
endlocal
