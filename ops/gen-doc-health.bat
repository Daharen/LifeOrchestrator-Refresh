@echo off
setlocal
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%d
python "%~dp0audit\gen-doc-health.py" --date %TODAY%
echo.
echo Open ops\out\doc-health-monitor.html in a browser.
pause