# fs.observer — example invocations

## Direct
```powershell
pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -Path 'C:\Users\just_\LifeOrchestrator-Refresh' -Depth 2
```

## With a name search
```powershell
pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -Path . -Depth 3 -Pattern '*.md'
```

## Generic -InputsJson convention
```powershell
pwsh -NoProfile -File .\Invoke-FsObserver.ps1 -InputsJson '{"path":"C:\\src","depth":2,"pattern":"*.ps1"}'
```

## Through the generic wrapper (Module 1)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"path":".","depth":2}'
```

The single JSON envelope conforms to `lifeorch.skill.result/0.1` (see `example-result.json`). Artifacts
`tree.md` + `index.json` are written under `runtime/artifacts/<invocation_id>/`.
