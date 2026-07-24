# uia.inspector — example invocations

## Desktop root (default)
```powershell
pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 -Depth 2
```

## A specific window by title
```powershell
pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 -Title 'Calculator*' -Depth 6
```

## By process id, filtering element names
```powershell
pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 -ProcessId 1234 -NameFilter '*Save*'
```

## Generic -InputsJson convention
```powershell
pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 -InputsJson '{"title":"Calculator*","depth":6,"name_filter":"*"}'
```

## Through the generic wrapper (Module 1)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"depth":2}'
```

The single JSON envelope conforms to `lifeorch.skill.result/0.1` (see `example-result.json`). Artifacts
`tree.md` + `elements.json` are written under `runtime/artifacts/<invocation_id>/`.
