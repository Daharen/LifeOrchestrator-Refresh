# Work Order: Executor Watchdog & Recovery (`exec.watchdog`)

**Contract version targeted:** n/a (infrastructure service, not a contract-skill — like Module 0) ·
**Author:** Claude (Cowork — Module 00.1 build session) / 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#00.1 exec.watchdog`

### Problem being solved
When the bootstrap executor (Module 0) dies or hangs mid-run, the cloud agent has **no way to restart it** —
its only Windows-execution channel is the executor's own queue, which is exactly what's down (this happened
2026-07-24T06:26:36Z: the executor fatal-crashed and sat dead for hours until the user manually restarted it).
A hung-but-alive executor is even worse: nothing currently detects it. This module gives the *machine* the
ability to recover the executor **autonomously** — restart a crash, kill+restart a hang — **without asking the
user** — while still honoring a deliberate manual stop.

### Immediate practical use
The user double-clicks `ops/start-watchdog.bat` before an unattended run. The watchdog then keeps the executor
alive through crashes and hangs on its own, so a scheduled/away session doesn't stall. The user can also run
`ops/recover-executor.bat` on demand to force-interrupt a stuck/slow executor and restart it.

### The one rule that keeps this inside D-0001 (read this first)
D-0001 forbids "shutdown resistance … re-activation … covert persistence … [and] preserving access after
authorization is revoked." This watchdog stays inside that line by being **cooperative, not perpetual**:

- It restarts the executor **only** after a *failure* (crash / hang / hard-death). It **stands down** when the
  executor was stopped **on purpose** — detected via a durable authorized-stop marker the executor writes on any
  graceful exit (Ctrl+C, `stop-executor.bat`, or window-close via a console-close handler).
- It has **no persistence of its own**: it is a plain visible foreground process the user launches; it installs
  **no** scheduled task, Run key, service, or startup entry; it does **not** survive logout/reboot; it does
  **not** relaunch itself.
- It **does not resist its own shutdown**: `ops/stop-watchdog.bat` (or closing its window) ends it immediately.
- Therefore an authorized stop is *always* honored (of the executor, or of the watchdog itself) — the watchdog
  heals failures, it never preserves access against the user's expressed will.

A **perpetual** watchdog (restart whenever down, ignoring how it stopped) is explicitly **out of scope** — it
cannot distinguish a manual stop from a crash and would restart after a deliberate close, which *is*
shutdown-resistance. We reject it. (See DECISION_LOG D-0013.)

### Explicit scope (in)
**A. Minimal additive changes to Module 0 (`Start-BootstrapExecutor.ps1`)** — needed to make recovery decidable:
- **Heartbeat:** each main-loop iteration, write `control/heartbeat.json {instance_id, pid, at_utc, active_tasks}`
  (throttled to ~2s). A stale heartbeat while the process is alive ⇒ **hung**.
- **Last-exit marker:** in the existing `finally`, write `control/last-exit.json {instance_id, pid, at_utc, reason}`
  with `reason` = `stop_requested` (saw `stop.requested`) | `signal` (Ctrl+C / console-close) | `fatal_error`
  (the `catch` fired). Written before the lock is released.
- **Startup cleanup:** on start, delete any prior `last-exit.json` and `heartbeat.json`, then write a fresh
  heartbeat — so *presence of last-exit.json ⇒ the executor exited gracefully*; *absence after a start ⇒ hard death*.
- **Console-close handler (best-effort):** register `SetConsoleCtrlHandler` for `CTRL_CLOSE_EVENT` (and
  `CTRL_C_EVENT`) to write the `signal` last-exit marker within the OS grace window, so closing the window counts
  as an authorized stop. If the P/Invoke proves unreliable, fall back to documenting "stop via Ctrl+C / Stop button."
- **No change** to the queue protocol, lock semantics, task lifecycle, or result schema. Module 0's 12/12 tests
  must still pass unchanged.

**B. The watchdog (`modules/00.1-exec-watchdog/`):**
- `Watch-Executor.ps1` — a loop (poll ~10s) with two **pure, unit-testable** decision functions:
  - `Get-ExecutorState` → reads the runtime control dir and returns `healthy | hung | down_crashed |
    down_hardkill | down_authorized | absent` (using the lock handle for liveness, `heartbeat.json` freshness for
    hang, and `last-exit.json` for how it ended).
  - `Get-WatchdogDecision` → maps a state (+ recent restart history) to an action: `none | restart | kill_restart
    | stand_down`.
  - The loop applies the decision, launching `Start-BootstrapExecutor.ps1` in a fresh process when restarting,
    and killing the executor's process tree (pid from heartbeat.json) before a `kill_restart` (hang).
  - **Crash-loop backoff:** cap rapid restarts (e.g. ≤5 in 5 min); on exceeding, log and stop restarting
    (surface for manual help) rather than hammering.
  - On `down_authorized` (a deliberate stop) → log "authorized stop; standing down" and **exit**.
  - Writes its own `control/watchdog.json {pid, started_at, last_action}`; honors `control/watchdog.stop.requested`.
- `Recover-Executor.ps1` — on-demand (user-invoked ⇒ authorized): detect state and start-if-down / kill+restart;
  `-Force` kills and restarts even a healthy executor. Prints a machine-readable summary.
- `ops/start-watchdog.bat`, `ops/stop-watchdog.bat`, `ops/recover-executor.bat` (each tees output to `ops/out/`).
- `README.md`.

### Non-goals (out — do NOT build)
- **Perpetual / always-restart** behavior; ignoring the authorized-stop marker (rejected — violates D-0001).
- Any **boot/OS persistence** — no scheduled task, service, Run key, startup shortcut. Session-scoped only.
- A watchdog-for-the-watchdog, or the watchdog relaunching itself. One level, user-launched, no self-revival.
- Deep **Module 0 self-heal** (retrying the internal IO op that crashed) — worthwhile, but a *separate* Module 0
  hardening pass; the watchdog already recovers that crash externally. Note it in the roadmap; don't build here.
- Remote/network control, auth, multi-host. Local, single-host, filesystem-signalled only.

### Dependencies
- Module 0 (the executor it supervises) + the additive markers above. pwsh 7.4.6. No models, no network.

### Inputs and outputs
- **Watch-Executor.ps1 inputs:** `-Root <runtime>` (default the canonical), `-ExecutorScript <path>`,
  `-PollSeconds <int=10>`, `-HeartbeatStaleSeconds <int=45>`, `-MaxRestarts <int=5>`, `-RestartWindowSeconds
  <int=300>`, `-PwshPath`.
- **Outputs:** `control/watchdog.json` (status/pid), log lines to `runtime/logs/watchdog.log` + console; on
  restart it starts the executor (which then produces its own log). `Recover-Executor.ps1` prints a
  `{action, prior_state, executor_pid}` JSON summary.

### Artifact / control-file structure (under the executor's `runtime/`)
- Written by Module 0: `control/heartbeat.json`, `control/last-exit.json`.
- Written by the watchdog: `control/watchdog.json`, `control/watchdog.stop.requested` (by stop-watchdog),
  `logs/watchdog.log`.

### Proposed implementation
- **Language:** PowerShell (matches Module 0; filesystem-signalled; no admin). Liveness via trying to open
  `control/executor.lock` exclusively (throws ⇒ alive). Hang via `heartbeat.json.at_utc` age vs threshold.
  Graceful-vs-crash via `last-exit.json.reason`. All decision logic in pure functions for unit tests.

### Tests (`tests/Invoke-WatchdogTests.ps1`, run via the executor)
- **Unit — `Get-WatchdogDecision`** over synthetic control-dir states: healthy→none; hung→kill_restart;
  down + last-exit `fatal_error`→restart; down + no last-exit (hard-kill)→restart; down + last-exit
  `stop_requested`/`signal`→stand_down; absent→restart(start); crash-loop over cap→stop_restarting.
- **Module 0 markers:** start a throwaway executor on a **temp runtime root**; assert `heartbeat.json` appears
  and refreshes; stop it via `stop.requested`; assert `last-exit.json.reason == stop_requested` and lock removed.
- **Integration:** watchdog against a temp-runtime executor — kill the executor process (simulate crash) →
  assert the watchdog starts a new one (new instance id, fresh heartbeat); then write an authorized stop →
  assert the watchdog stands down (no new instance) and exits. Bound with timeouts.
- **Regression:** re-run `modules/00-bootstrap-executor/tests/Invoke-BootstrapTests.ps1` → still **12/12**.
- All executed through the canonical executor as task packages; the temp-runtime instances are disposable and
  never touch the live queue.

### MVP acceptance criteria
- [ ] Module 0 writes `heartbeat.json` (refreshing) and `last-exit.json` with the correct `reason` on each
      graceful exit path; startup clears stale markers; **Module 0 tests still 12/12.**
- [ ] `Get-WatchdogDecision` returns the correct action for every state above (unit tests green).
- [ ] Integration: watchdog **autonomously restarts** a crashed/killed executor **with no approval**, and
      **stands down** on an authorized stop, on a temp runtime.
- [ ] `Recover-Executor.ps1` / `ops/recover-executor.bat` force-restart a running executor on demand.
- [ ] Watchdog is visible, writes its pid, stops on `watchdog.stop.requested` / window-close, installs no
      persistence, and applies crash-loop backoff.

### Manual verification procedure
- Launch `ops/start-watchdog.bat`; confirm `control/watchdog.json` appears. Kill the executor from Task Manager
  (force) → watchdog restarts it within a poll or two. `stop-executor.bat` (or Ctrl+C in the executor window) →
  watchdog logs "authorized stop; standing down" and exits. Relaunch executor + watchdog; `recover-executor.bat
  -Force` → executor is killed and replaced.

### Documentation / registry / state updates
- `README.md` (module) + this work order. Add `exec.watchdog` to `TOOL_MODEL_REGISTRY.md`; add Module 00.1 to
  `MODULE_ROADMAP.md`; update `CURRENT_STATE.md`; record the values decision in `DECISION_LOG.md` (D-0013), plus
  a roadmap note for the separate Module 0 in-process self-heal hardening.

### STOP conditions
- Any drift toward perpetual/ignore-manual-stop behavior, OS persistence, or self-revival — stop; that's the
  forbidden zone.
- Module 0's 12/12 regression breaks and the fix isn't trivial — stop, revert the Module 0 change, reassess.
- The console-close handler can't be made reliable — ship without it and document "stop via Ctrl+C / Stop button"
  (do not block the MVP on it).
- MVP acceptance met — stop.
