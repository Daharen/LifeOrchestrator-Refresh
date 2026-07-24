# Module 00.1 — Executor Watchdog & Recovery (`exec.watchdog`)

A **cooperative, session-scoped supervisor** for the Trusted High-Risk Bootstrap Executor (Module 0). It
gives the machine the ability to recover the executor **on its own** — restart a crash, kill-and-restart a
hang — **without asking for approval** — while always honoring a deliberate manual stop.

This is infrastructure (like Module 0), not a contract-skill: no `skill.json`, no result envelope.

## Why this does not violate D-0001 (cooperative, not perpetual)
D-0001 forbids shutdown resistance, re-activation, covert persistence, and "preserving access after
authorization is revoked." This watchdog stays inside that line:

- It restarts the executor **only after a failure** (crash / hang / hard-death). It **stands down** the
  moment the executor was stopped *on purpose*.
- "On purpose" is detected from `runtime/control/last-exit.json`, which the executor writes on every graceful
  exit: `reason` = `stop_requested` (you ran `stop-executor.bat`), `signal` (Ctrl+C or you closed its
  window), or `fatal_error` (a crash). A hard-kill / power-loss writes no marker and is treated as a crash.
- It has **no persistence of its own**: a plain visible process you launch; no scheduled task / service /
  Run key / startup entry; it does not survive logout/reboot and never relaunches itself.
- It **does not resist its own shutdown**: `stop-watchdog.bat` or closing its window ends it at once.

A *perpetual* "always restart whenever down" watchdog is deliberately **not** built — it can't tell your
manual stop from a crash and would restart after you closed the executor on purpose, which *is*
shutdown-resistance. See `DECISION_LOG.md` D-0013.

## What it decides (`Get-WatchdogDecision`, a pure function)
| Executor state | Action |
|----------------|--------|
| alive + fresh heartbeat | `none` (healthy) |
| alive + **stale** heartbeat | `kill_restart` (hung → kill tree + restart) |
| down, last-exit `fatal_error` | `restart` (crashed) |
| down, **no** marker | `restart` (hard-kill / power-loss / never started) |
| down, last-exit `stop_requested`/`signal` | `stand_down` (authorized stop → exit) |
| a restart is due but the crash-loop cap was hit | `backoff` (log, don't hammer) |

Liveness = whether `control/executor.lock` is held (can't be opened exclusively). Hang = `heartbeat.json`
age ≥ `-HeartbeatStaleSeconds` (default 45s; the executor refreshes it ~every 2s).

## Use
```bat
ops\start-watchdog.bat      :: launch the watchdog (minimized) before an unattended run
ops\stop-watchdog.bat       :: stop just the watchdog (or close its window)
ops\recover-executor.bat    :: on-demand: start if down / restart if hung
ops\recover-executor.bat -Force  :: kill + restart even a healthy executor (interrupt a slow/stuck run)
```
Direct:
```powershell
pwsh -NoProfile -File .\Watch-Executor.ps1
pwsh -NoProfile -File .\Recover-Executor.ps1 [-Force]
pwsh -NoProfile -File .\tests\Invoke-WatchdogTests.ps1
```

## Stopping cleanly (so the watchdog stands down)
Stop the executor with **Ctrl+C**, **`stop-executor.bat`**, or by **closing its window** — all three leave
the `last-exit` marker the watchdog honors. Only a **Task-Manager force-kill (`taskkill /F`)** or a power
cut leaves no marker and is treated as a crash (recovered). To fully stop everything, stop the executor
cleanly (the watchdog then stands down on its own), or stop the watchdog first, then the executor.

## Companion change to Module 0 (additive)
`Start-BootstrapExecutor.ps1` now writes `control/heartbeat.json` each loop (hang detection) and
`control/last-exit.json` in its `finally` (authorized-stop vs crash), clears both at startup, and best-effort
records a `signal` exit if its console window is closed. These are additive; Module 0's 12/12 tests are
unaffected. The executor must be **restarted once** to start emitting them.

## Files
`Watch-Executor.ps1` (supervisor loop + pure `Get-ExecutorState` / `Get-WatchdogDecision`),
`Recover-Executor.ps1` (on-demand), `tests/Invoke-WatchdogTests.ps1`, and the `ops/*.bat` launchers.

## Not included (deliberately)
Perpetual/ignore-manual-stop behavior; any OS/boot persistence; self-revival; remote/network control; and
the separate Module 0 *in-process self-heal* (retrying the internal IO op that crashed) — worthwhile, but a
distinct Module 0 hardening pass; the watchdog already recovers that crash externally.
