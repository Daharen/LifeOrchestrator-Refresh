@echo off
rem ops\install-doc-gate.bat -- idempotent installer for the M2-A doc-hygiene commit gate's
rem .git\hooks\pre-commit. No admin rights required. Re-running is a no-op when the hook already
rem matches. ASCII only. The ONE canonical hook body plus its sha256 manifest are owned by
rem doc-commit-gate.py (--install-hook); this script only locates a python interpreter and
rem invokes it, so there is never a second copy of the hook text to drift out of sync.
setlocal
set "SCRIPT_DIR=%~dp0"
set "GATE=%SCRIPT_DIR%audit\doc-commit-gate.py"

if not exist "%GATE%" (
  echo install-doc-gate: cannot find %GATE%
  exit /b 1
)

set "PY="
where python >nul 2>nul
if %ERRORLEVEL%==0 set "PY=python"
if not defined PY (
  where python3 >nul 2>nul
  if %ERRORLEVEL%==0 set "PY=python3"
)
if not defined PY (
  echo install-doc-gate: no python or python3 found on PATH.
  exit /b 1
)

"%PY%" "%GATE%" --install-hook --repo "%SCRIPT_DIR%.."
exit /b %ERRORLEVEL%
