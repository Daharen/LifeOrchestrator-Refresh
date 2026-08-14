@echo off
setlocal
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%d
if "%~1"=="" (
  echo usage: gen-retrieval-monitor.bat ^<ledger-path^> ^<iteration^>
  echo   e.g.: gen-retrieval-monitor.bat audit\retrieval-ledger\i55-agent002.jsonl 55
  pause
  exit /b 2
)
python "%~dp0audit\gen-retrieval-monitor.py" --ledger "%~1" --iteration %2 --date %TODAY%
echo.
echo Row appended to ops\out\retrieval-bytes-log.jsonl.
pause
