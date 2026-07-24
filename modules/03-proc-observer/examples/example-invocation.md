# proc.observer — example invocations

## Direct (all processes + visible windows)
```powershell
pwsh -NoProfile -File .\Invoke-ProcObserver.ps1
```

## Narrow to a process name
```powershell
pwsh -NoProfile -File .\Invoke-ProcObserver.ps1 -NameFilter 'chrome*'
```

## Generic -InputsJson convention
```powershell
pwsh -NoProfile -File .\Invoke-ProcObserver.ps1 -InputsJson '{"visible_only":true,"name_filter":"pwsh*"}'
```

## Through the generic wrapper (Module 1)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"name_filter":"pwsh*"}'
```

The single JSON envelope conforms to `lifeorch.skill.result/0.1` (see `example-result.json`). Artifacts
`report.md`, `processes.json`, `windows.json` are written under `runtime/artifacts/<invocation_id>/`.
