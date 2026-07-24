# Module 2 — Filesystem Observer (`fs.observer`)

Deterministic, depth-bounded directory listing + name search over the local filesystem, without
screenshots. The first useful skill built on the Life Orchestrator skill contract (Module 1).

## What it does
Given a root `path`, walks up to `depth` levels, collecting each entry's type/size/mtime, sorted for
stable output. Emits a `lifeorch.skill.result/0.1` envelope plus two artifacts: `tree.md` (human) and
`index.json` (machine). An optional `pattern` glob adds a bounded `matches` list.

## Run
```powershell
pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -Path 'C:\Users\just_\LifeOrchestrator-Refresh' -Depth 2
pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -Path . -Depth 3 -Pattern '*.md'
# wrapped (manifest + envelope validated):
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"path":".","depth":2}'
# tests:
pwsh -NoProfile -File .\tests\Invoke-FsObserverTests.ps1
```
Through the executor: submit a `task.ps1` that calls the entrypoint; read the envelope from
`runtime/completed/<task_id>/stdout.txt` and artifacts from the skill's `runtime/artifacts/<invocation_id>/`.

## Inputs
| name | type | default | notes |
|------|------|---------|-------|
| path | string | (required) | root directory |
| depth | int | 3 | entries at depths 1..depth |
| pattern | string | — | name glob for the matches list |
| include_hidden | bool | false | include hidden/system entries |
| max_entries | int | 5000 | cap; exceeding → status partial |

## Output
`result` = `{ root, depth, generated_at_utc, entry_count, dir_count, file_count, bytes_total, truncated,
pattern, match_count, matches[] }`. Deterministic (`confidence` null). Artifacts: `tree.md`, `index.json`.
Unreadable subtrees are skipped with a warning (status `partial`); a missing path yields status `error`
(code `path_not_found`) with a still-valid envelope.

## Notes
- Symlinks/junctions are listed but not traversed (cycle-safe).
- Deterministic ordering: entries sorted by relative path (ordinal, case-insensitive) → stable pre-order.
- Reuses Module 1's `Test-SkillManifest` / `Test-SkillResultEnvelope` and the generic `Invoke-Skill.ps1`.
