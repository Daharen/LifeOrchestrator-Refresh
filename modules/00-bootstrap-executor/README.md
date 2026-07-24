# Trusted High-Risk Bootstrap Executor

A standalone local module that lets an authorized agent (Claude, ChatGPT, a
local model, or you) run PowerShell task packages on this Windows machine by
dropping them into a filesystem queue. The executor polls the queue, claims
tasks atomically, runs them concurrently in isolated PowerShell 7 processes, and
writes back compact machine-readable results.

It is the first-pass MVP bootstrap mechanism for Project Proteus. It lives under
`tools/trusted-bootstrap-executor/` and is intentionally self-contained and
replaceable — it does **not** integrate with the older Proteus simulation,
canonicalization, database, or responder architecture.

---

## ⚠️ This is a trusted, high-risk executor — not a sandbox

Read this before using it.

- There are **no** command allowlists, content filters, approval prompts, or
  workspace restrictions. That is by design for this first pass.
- **Write access to the queue is the entire trust boundary.** Anyone or anything
  that can place a task directory into `runtime/pending` runs arbitrary
  PowerShell with the **full authority of the Windows user** running the
  executor. Treat "can submit a task" as equal to "can act as this user."
- A submitted script can therefore read, modify, or delete anything that user
  can. This is not hidden or worked around — it is the point of the tool. Only
  let trusted agents and trusted local processes write to the queue directory.

What this executor deliberately does **not** do: it does not conceal itself,
resist shutdown, re-activate itself, propagate, persist covertly, or evade
monitoring. All task processes are ordinary, fully visible Windows processes.
It never restarts itself and installs no startup persistence.

---

## Requirements

- Windows with **PowerShell 7** available as `pwsh.exe` (configurable).
- Run the executor as the user whose authority you intend tasks to have.

---

## Launching the executor

From this folder:

```powershell
pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1
```

Useful overrides (any config value can be overridden on the command line):

```powershell
pwsh -NoProfile -File .\Start-BootstrapExecutor.ps1 `
    -MaxConcurrentTasks 8 -QueuePollSeconds 5 -DefaultTimeoutSeconds 600
```

The executor holds an exclusive lock on the runtime directory, so only one
instance runs against a given `runtime/` at a time. It logs to
`runtime/logs/executor.log` and to the console.

## Submitting a task

Use the helper (it stages the task, then atomically publishes it to `pending`):

```powershell
pwsh -NoProfile -File .\Submit-BootstrapTask.ps1 `
    -TaskId "instruction-000101" `
    -ScriptText 'Write-Output "Hello from the bootstrap executor."' `
    -SubmittedBy "claude" `
    -Description "Verify basic task execution."
```

Or submit an existing script file:

```powershell
pwsh -NoProfile -File .\Submit-BootstrapTask.ps1 `
    -TaskId "instruction-000102" `
    -SourceScriptPath .\examples\hello-world.ps1
```

Optional parameters: `-WorkingDirectory`, `-TimeoutSeconds` (omit to use the
configured default), `-VisibleWindow $true`, `-SubmittedBy`, `-Description`.

You can also construct tasks by hand — see **Queue protocol** below — as long as
you build them under `runtime/staging` and move the finished directory into
`runtime/pending` in a single atomic rename.

## Inspecting results

Each finished task directory ends up in `runtime/completed` (success) or
`runtime/failed` (everything else) and contains:

```
task.json      the original submitted metadata (preserved)
task.ps1       the original submitted script    (preserved)
state.json     the running snapshot (pid, start time, timeout)
stdout.txt     captured standard output
stderr.txt     captured standard error
result.json    final status, exit code, timing
```

`result.json` looks like:

```json
{
  "task_id": "instruction-000101",
  "status": "completed",
  "exit_code": 0,
  "started_at_utc": "2026-07-23T22:00:00.0000000Z",
  "finished_at_utc": "2026-07-23T22:00:05.0000000Z",
  "duration_ms": 5000,
  "stdout_file": "stdout.txt",
  "stderr_file": "stderr.txt",
  "executor_instance_id": "GUID",
  "failure_reason": null
}
```

Final statuses: `completed`, `failed`, `timed_out`, `cancelled`,
`abandoned_after_restart`, `invalid_task`.

## Stopping the executor

Either press **Ctrl+C** in the executor's console, or run:

```powershell
pwsh -NoProfile -File .\Stop-BootstrapExecutor.ps1
```

The stop helper only creates `runtime/control/stop.requested`. On shutdown the
executor stops claiming new tasks, terminates active task process trees, records
their results as `cancelled`, releases its lock, and exits.

---

## How task folders move through the queue

```
staging/  ->  pending/  ->  running/  ->  completed/   (exit code 0)
                                      \->  failed/       (everything else)
```

- **staging** — the submitter builds the task directory here first. The executor
  never reads it.
- **pending** — a fully-written task, published by a single atomic directory
  move. Tasks are picked up in lexicographic name order.
- **running** — the executor claims a task by atomically moving its whole
  directory here, then starts the process and writes `state.json`.
- **completed / failed** — the executor writes `result.json`, then moves the
  directory to its final home. Submitted scripts and metadata are never deleted.

A task is a **directory**, not a mutable file, and each stage is a whole-directory
move on the same volume, which is atomic. This is why staging, pending, and
running must live on the same filesystem volume.

## How concurrent execution works

One executor instance runs up to `max_concurrent_tasks` tasks at once, each in
its own isolated `pwsh` process launched with `-NoLogo -NoProfile -NonInteractive
-ExecutionPolicy Bypass -File`. Tasks are started in submission (lexicographic)
order, but because they run concurrently, **completion order is not guaranteed** —
a later task may finish before an earlier one. There are no inter-task
dependencies or persistent execution lanes in this first pass.

## How restart recovery works

If the executor stops (crash, power loss, kill) while tasks are in `running`,
those directories are left behind. On the next startup the executor inspects
`running/`, and for each leftover task it writes a `result.json` with status
`abandoned_after_restart` and moves it to `failed`. It does **not** re-execute
them, so a task never runs twice. It also does not blindly kill processes by a
recorded PID (which may have been reused); orphaned child processes from a prior
run are left for the OS / user to clean up.

---

## Configuration (`config.json`)

```json
{
  "queue_poll_seconds": 30,
  "process_poll_milliseconds": 1000,
  "max_concurrent_tasks": 4,
  "default_timeout_seconds": 900,
  "pwsh_path": "pwsh.exe"
}
```

A `timeout_seconds` of `0` on a task means "no timeout."

## Task metadata schema (`task.json`)

Required: `task_id`, `script_file`. Optional: `working_directory`,
`timeout_seconds`, `visible_window`, `submitted_by`, `description`. The
`task_id` must equal the task directory name. Inline PowerShell is **not**
executed from JSON — the referenced `.ps1` file is what runs.

## Running the tests

```powershell
pwsh -NoProfile -File .\tests\Invoke-BootstrapTests.ps1
```

The harness spins up isolated executor instances against temporary runtime roots
and verifies the twelve behaviours in the specification (success, failure,
timeout, concurrency, staging-ignored, atomic claim, no double execution,
abandoned-after-restart recovery, duplicate rejection, orderly stop,
single-instance lock, and file preservation). It exits non-zero if any fail.

---

## Current limitations

- First pass uses isolated processes, not persistent PowerShell sessions.
- No inter-task dependencies, priorities, or execution lanes.
- Restart recovery marks in-flight tasks abandoned; it does not attempt to
  resume them or to safely reap their orphaned children by PID.
- Windows-focused: process-tree termination uses `taskkill /T /F`.
- No network listener, HTTP API, authentication, service install, scheduled
  task, or elevation. Hidden task windows are ordinary background execution.

## Roadmap (not implemented here)

Later versions may add a local API for submission/inspection, persistent
execution lanes, model/agent adapters, and resource (e.g. GPU) scheduling. None
of that exists in this first pass.
