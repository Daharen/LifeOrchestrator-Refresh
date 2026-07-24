# model.gateway — example invocation

## Direct (tier alias)

```powershell
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Tier weak -Prompt "Reply with exactly one word: PONG" -MaxTokens 16 -Temperature 0.1 -Seed 42
```

## Direct (explicit model + system)

```powershell
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Model llm.weak.qwen2p5-0p5b -System "You are terse." -Prompt "Name three primary colors." -MaxTokens 48 -Seed 42
```

## Via -InputsJson (messages array)

```powershell
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -InputsJson '{"tier":"weak","messages":[{"role":"system","content":"You classify text into one word."},{"role":"user","content":"Classify: \"the invoice is overdue\""}],"max_tokens":8,"temperature":0,"seed":1}'
```

## Through the executor (task package)

`task.json`:

```json
{ "task_id": "mg-demo-001", "script_file": "task.ps1", "submitted_by": "agent", "description": "model.gateway demo", "timeout_seconds": 120 }
```

`task.ps1`:

```powershell
& 'C:\Users\just_\.dotnet\tools\pwsh.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\Users\just_\LifeOrchestrator-Refresh\modules\07-model-gateway\Invoke-ModelGateway.ps1' -Tier weak -Prompt 'Name three primary colors.' -MaxTokens 64 -Seed 42
exit $LASTEXITCODE
```

Read the envelope from `runtime/completed/mg-demo-001/stdout.txt`.
