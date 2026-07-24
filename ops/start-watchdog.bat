@echo off
setlocal
set "PWSH=C:\Users\just_\.dotnet\tools\pwsh.exe"
set "WD=C:\Users\just_\LifeOrchestrator-Refresh\modules\00.1-exec-watchdog"
if not exist "%~dp0out" mkdir "%~dp0out"
start "LifeOrchestrator Executor Watchdog" /min "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%WD%\Watch-Executor.ps1"
echo Launched watchdog (minimized) at %DATE% %TIME%> "%~dp0out\watchdog-start.txt"
echo.
echo Watchdog launched (minimized window).
echo   - It restarts the executor automatically on a CRASH or a HANG. No approval needed.
echo   - It STANDS DOWN (does not restart) when you stop the executor cleanly:
echo       Ctrl+C in the executor window, OR stop-executor.bat, OR closing the executor window.
echo   - A Task-Manager force-kill looks like a crash and WILL be recovered - stop it cleanly instead.
echo.
echo To stop the watchdog: run stop-watchdog.bat, or just close the watchdog window.
pause
