# Module 4 — UI Automation Inspector (`uia.inspector`)

Read-only inspection of the UI Automation accessible control tree for a target window (or the whole
desktop). Returns stable per-element info — control type, name, automation id, class, bounds, supported
patterns, state — that a later actor (Module 5) can use to act on elements. No screenshots, no actions.

## What it does
Resolves a target (by `-Hwnd`, `-ProcessId`, `-Title`, else the desktop root) and walks its UIA tree
(depth-bounded, element-capped, pre-order). Emits a `lifeorch.skill.result/0.1` envelope plus `tree.md`
(human) and `elements.json` (machine).

## Run
```powershell
pwsh -NoProfile -File .\Invoke-UiaInspector.ps1                        # desktop root
pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 -Title 'Calculator*' -Depth 6
pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 -ProcessId 1234 -NameFilter '*Save*'
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"title":"Calculator*","depth":6}'
pwsh -NoProfile -File .\tests\Invoke-UiaInspectorTests.ps1
```
Through the executor: submit a `task.ps1` that calls the entrypoint; read the envelope from
`runtime/completed/<task_id>/stdout.txt` and artifacts from `runtime/artifacts/<invocation_id>/`.

## Inputs
| name | type | default | notes |
|------|------|---------|-------|
| hwnd | int | — | target window handle (highest precedence) |
| pid | int | — | target process's main window |
| title | string | — | top-level window title glob |
| depth | int | 4 | max tree depth from the target |
| max_elements | int | 500 | cap; exceeding → status partial |
| name_filter | string | — | glob on element Name for a matches list |

No target → the desktop root (always a rich, reliable tree).

## Output
`result` = `{ target, depth, element_count, truncated, name_filter, match_count, matches[], elements[] }`.
Full tree in `elements.json`. Each element: `ref`, `path` (child-index path), `depth`, `control_type`,
`name`, `automation_id`, `class_name`, bounds, `enabled`/`offscreen`/`keyboard_focusable`, `patterns[]`.
Deterministic read of current UI state (`confidence` null); it changes as the UI does.

## Notes
- **Read-only** — never invokes/focuses/moves anything (that is Module 5 `uia.actor`).
- Uses managed UI Automation (`System.Windows.Automation`) via `Add-Type`.
- Elements with no accessible bounds report `0x0 @ 0,0`; unreadable properties degrade to empty, not errors.
- Reuses Module 1's `Test-SkillManifest` / `Test-SkillResultEnvelope` and the generic `Invoke-Skill.ps1`.
