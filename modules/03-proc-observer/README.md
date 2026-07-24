# Module 3 — Process & Window Observer (`proc.observer`)

Structured, point-in-time snapshot of running processes and top-level windows — pids, titles, paths,
positions/size, minimized/maximized, and the foreground window — via Win32 queries. No screenshots, no
image processing. The structured-observation counterpart to Module 2's `fs.observer`.

## What it does
Lists processes (`Get-Process`: pid, name, path, start time, working set, main window) and enumerates
top-level windows (Win32 `EnumWindows`: title, owning pid/name, bounds, state, foreground). Emits a
`lifeorch.skill.result/0.1` envelope plus three artifacts: `report.md` (human), `processes.json`, `windows.json`.

## Run
```powershell
pwsh -NoProfile -File .\Invoke-ProcObserver.ps1
pwsh -NoProfile -File .\Invoke-ProcObserver.ps1 -NameFilter 'chrome*'
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"name_filter":"pwsh*"}'
pwsh -NoProfile -File .\tests\Invoke-ProcObserverTests.ps1
```
Through the executor: submit a `task.ps1` that calls the entrypoint; read the envelope from
`runtime/completed/<task_id>/stdout.txt` and artifacts from `runtime/artifacts/<invocation_id>/`.

## Inputs
| name | type | default | notes |
|------|------|---------|-------|
| visible_only | bool | true | only visible top-level windows that have a title |
| name_filter | string | — | glob on process name (narrows processes and windows) |
| max_items | int | 2000 | cap; exceeding → status partial |

## Output
`result` = `{ host, generated_at_utc, name_filter, visible_only, process_count, window_count, foreground,
windows[] }`. Full process/window lists live in `processes.json` / `windows.json`. Deterministic read of
current state (`confidence` null); values differ between runs because the OS state does — this is a
snapshot, not a stream.

## Notes
- Runs in the user's interactive session (the executor is launched there), so it sees the desktop's windows.
- Some processes' Path/StartTime are inaccessible (protected) → null, not an error.
- Window enumeration failure degrades to a warning + `status:partial` (processes still returned).
- Reuses Module 1's `Test-SkillManifest` / `Test-SkillResultEnvelope` and the generic `Invoke-Skill.ps1`.
