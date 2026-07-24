# uia.actor — example invocations

## Preview an action (dry-run — resolves and reports, performs nothing)
```powershell
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Calculator*' -Action invoke -AutomationId num5Button -WhatIf
```

## Invoke a button (by automation id)
```powershell
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Calculator*' -Action invoke -AutomationId num5Button
```

## Set a text field's value (by control type)
```powershell
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Notepad*' -Action setvalue -ControlType Edit -Value 'hello world'
```

## Toggle a checkbox located by the inspector's child-path
```powershell
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'MyApp*' -Action toggle -Path '3.1.4'
```

## Focus a control (by name glob)
```powershell
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'MyApp*' -Action focus -Name '*Search*'
```

## Generic -InputsJson convention
```powershell
pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -InputsJson '{"title":"Calculator*","action":"invoke","automation_id":"num5Button","dry_run":true}'
```

## Through the generic wrapper (Module 1)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"action":"focus","path":"","dry_run":true}'
```

Typical flow: run `uia.inspector` on the target window, pick the element you want from `elements.json`
(its `automation_id` / `name` / `control_type` / `path`), then call `uia.actor` with that locator and the
action. The single JSON envelope conforms to `lifeorch.skill.result/0.1` (see `example-result.json`).
Artifacts `action.md` + `action.json` are written under `runtime/artifacts/<invocation_id>/`.
