@echo off
rem ============================================================================
rem  Compile Trace Console (Widget 06) launcher - double-click to open.
rem  Renders a real #40 context_packet across the audit panes 1-4,6 + the
rem  compile-layer counterfactual runner, under the per-user PowerShell 7 in STA
rem  mode. STRICTLY READ-ONLY: it reads existing compile/eval artifacts, calls no
rem  model, and writes nothing outside its own runtime\ dir.
rem ============================================================================
setlocal
set "PWSH=%USERPROFILE%\.dotnet\tools\pwsh.exe"
if not exist "%PWSH%" set "PWSH=pwsh.exe"
"%PWSH%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Show-CompileTraceConsole.ps1" %*
if not "%ERRORLEVEL%"=="0" echo(& echo The Compile Trace Console exited with an error (code %ERRORLEVEL%).& pause
endlocal
