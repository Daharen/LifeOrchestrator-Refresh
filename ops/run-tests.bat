@echo off
if not exist "%~dp0out" mkdir "%~dp0out"
"C:\Users\just_\.dotnet\tools\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\Users\just_\LifeOrchestrator-Refresh\modules\01-skill-bootstrap\tests\Invoke-SkillBootstrapTests.ps1" > "%~dp0out\tests.txt" 2>&1
type "%~dp0out\tests.txt"
pause
