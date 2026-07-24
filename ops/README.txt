Life Orchestrator - ops batch files
===================================
Double-click any of these when Claude asks you to run something for it.
Each writes its output to ops\out\<name>.txt so Claude can read the result.

  start-executor.bat     Launch the Life Orchestrator executor (opens a minimized
                         window). This is the process Claude submits work to -
                         leave it running. Safe to click twice (the extra one exits).
  stop-executor.bat      Ask the executor to stop (finishes its cycle, then exits).
  restart-executor.bat   Stop, wait, then relaunch the executor.
  status.bat             Show executor status (lock, queue counts, recent log).
  run-tests.bat          Run the Module 1 test suite.

Paths (for reference):
  pwsh      C:\Users\just_\.dotnet\tools\pwsh.exe
  executor  modules\00-bootstrap-executor
  outputs   ops\out\
