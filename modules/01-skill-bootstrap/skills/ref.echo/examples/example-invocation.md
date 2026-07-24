# ref.echo — example invocations

## Direct (named params)
```powershell
pwsh -NoProfile -File .\Invoke-RefEcho.ps1 -Message "hello" -Repeat 3
```

## Direct (generic -InputsJson convention)
```powershell
pwsh -NoProfile -File .\Invoke-RefEcho.ps1 -InputsJson '{"message":"hello","repeat":3}'
```

## Through the generic wrapper (validate manifest -> run -> validate envelope)
```powershell
pwsh -NoProfile -File ..\..\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"message":"hello","repeat":3}'
```

## Through the bootstrap executor (Module 0)
Submit a task whose `task.ps1` calls the entrypoint; the single JSON envelope lands in
`runtime/completed/<task_id>/stdout.txt`, and the skill also writes it to
`<skill>/runtime/artifacts/<invocation_id>/result.json`.

The result envelope conforms to `lifeorch.skill.result/0.1`. A representative envelope
is in `example-result.json`.
