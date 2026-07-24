@echo off
setlocal
set "CTRL=C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor\runtime\control"
if not exist "%CTRL%" mkdir "%CTRL%"
type nul > "%CTRL%\watchdog.stop.requested"
echo Watchdog stop requested. It will notice within a poll interval and exit.
echo (This only stops the watchdog. The executor keeps running; stop it separately with stop-executor.bat.)
pause
