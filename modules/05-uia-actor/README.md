# Module 5 — UI Automation Actor (`uia.actor`)

The **acting** half of UI Automation. Given a target window and a locator that uniquely identifies one
element, it performs exactly **one** action through a UIA control pattern. Kept deliberately separate from
inspection (`uia.inspector`, Module 4), which is what produces the locators used here. This is the first
skill with side effects, so it ships with a dry-run preview and acts only through accessibility patterns —
never synthetic mouse/keyboard input.

## What it does
Resolves a target (`-Hwnd`, `-ProcessId`, `-Title`, else the desktop root — same as the inspector), then
resolves a single element by any combination of `-AutomationId` (exact), `-Name` (glob), `-ControlType`
(exact) and/or `-Path` (the inspector's child-index path; authoritative when given). It then performs one of:

| action | UIA pattern | before/after state captured |
|--------|-------------|------------------------------|
| `invoke`   | InvokePattern.Invoke()            | — |
| `toggle`   | TogglePattern.Toggle()            | `toggle_state` |
| `select`   | SelectionItemPattern.Select()     | `is_selected` |
| `expand`   | ExpandCollapsePattern.Expand()    | `expand_collapse_state` |
| `collapse` | ExpandCollapsePattern.Collapse()  | `expand_collapse_state` |
| `setvalue` | ValuePattern.SetValue(value)      | `value`, `is_read_only` |
| `focus`    | AutomationElement.SetFocus()      | `has_keyboard_focus` |

Emits one `lifeorch.skill.result/0.1` envelope on stdout plus `action.md` (human) and `action.json`
(machine) artifacts.

## Run
```powershell
# Preview (resolve + report, performs nothing):
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Calculator*' -Action invoke -AutomationId num5Button -WhatIf
# Act:
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Calculator*' -Action invoke -AutomationId num5Button
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Notepad*'    -Action setvalue -ControlType Edit -Value 'hello'
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'MyApp*'      -Action toggle -Path '3.1.4'
# Generic convention / wrapper:
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -InputsJson '{"title":"Calculator*","action":"invoke","automation_id":"num5Button","dry_run":true}'
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"action":"focus","path":"","dry_run":true}'
pwsh -NoProfile -File .\tests\Invoke-UiaActorTests.ps1
```
Through the executor: submit a `task.ps1` that calls the entrypoint; read the envelope from
`runtime/completed/<task_id>/stdout.txt` and artifacts from `runtime/artifacts/<invocation_id>/`.

## Inputs
| name | type | default | notes |
|------|------|---------|-------|
| hwnd / pid / title | int / int / glob | — | target (else desktop root) |
| action | string | — | **required**: invoke\|toggle\|select\|expand\|collapse\|setvalue\|focus |
| automation_id | string | — | locator, exact |
| name | string | — | locator, glob on Name |
| control_type | string | — | locator, exact (Button, CheckBox, Edit, …) |
| path | string | — | locator, inspector child-index path (authoritative; `""` = the target itself) |
| value | string | — | required for a real `setvalue` |
| dry_run | bool | false | resolve + report, perform nothing (also `-WhatIf`) |
| depth / max_elements | int / int | 12 / 3000 | bound the property-search walk (ignored when `path` given) |

At least one locator is required; `>1` match → `ambiguous_locator` (with candidates); `0` → `element_not_found`.

## Output
`result` = `{ target, action, dry_run, performed, actionable, requested_pattern, pattern_supported,
locator, resolved_element, candidate_count, candidates[], before_state, after_state, blockers[] }`. Full
record in `action.json`; human summary in `action.md`. `confidence` null (no model). Error modes return a
valid error envelope (exit 0) with codes: `invalid_action`, `no_locator`, `value_required`,
`target_not_found`, `element_not_found`, `ambiguous_locator`, `path_not_resolvable`, `pattern_unsupported`,
`element_disabled`, `value_readonly`, `action_failed`, `unhandled_exception`.

## Notes / boundaries
- **UIA control patterns only** — no SendKeys / `mouse_event` / `keybd_event` / cursor moves. If a control
  exposes no usable pattern that is a `pattern_unsupported` error, not a coordinate-click fallback.
- **One action per invocation.** No macros/sequences (that is a later orchestration module). `parallel_safe`
  is **false** — it mutates shared desktop UI.
- No window management (move/resize/close), no wait-for-element retries — resolve against the current tree.
- Honors the executor's hard prohibitions: no concealment, persistence, propagation, or monitoring evasion.
- Reuses Module 1's `Test-SkillManifest` / `Test-SkillResultEnvelope` and the generic `Invoke-Skill.ps1`;
  resolves elements with the same tree walk as Module 4 so its `path` locators compose exactly.
