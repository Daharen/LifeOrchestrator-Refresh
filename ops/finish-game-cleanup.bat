@echo off
setlocal
set "TARGET=C:\Users\just_\Project-Proteus-src\proteus_repo\tools"
if not exist "%TARGET%" ( echo Already clean: %TARGET% does not exist. & pause & exit /b 0 )
echo Removing the leftover bootstrap executor from the game repo...
rmdir /s /q "%TARGET%"
if exist "%TARGET%" (
  echo COULD NOT DELETE - the folder is still open in a running Claude session.
  echo Close the Claude desktop app, then run this again.
) else (
  echo Done. proteus_repo\tools removed; the game repo is fully back to its prior state.
)
pause
