# audio.ingest — example invocation

Normalize an arbitrary clip into whisper-ready audio (the default: 16 kHz mono s16 WAV).

## Direct

```powershell
pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputFile 'C:\Users\just_\Music\voice-memo.m4a'
```

## Via -InputsJson (how a local/frontier caller or Module 11 invokes it)

```powershell
pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputsJson '{
  "input": "C:\\Users\\just_\\Music\\voice-memo.m4a",
  "format": "wav",
  "sample_rate": 16000,
  "channels": 1,
  "sample_fmt": "s16",
  "loudness": "none"
}'
```

## Wrapped (Module 1 generic runner)

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
  -InputsJson '{"input":"C:\\Users\\just_\\Music\\voice-memo.m4a"}'
```

## Through the executor (task package)

`task.json`:

```json
{ "task_id": "audio-ingest-demo", "script_file": "task.ps1", "timeout_seconds": 300,
  "submitted_by": "some-agent", "description": "Normalize a clip to whisper-ready WAV." }
```

`task.ps1`:

```powershell
pwsh -NoProfile -File 'C:\Users\just_\LifeOrchestrator-Refresh\modules\10-audio-ingest\Invoke-AudioIngest.ps1' `
  -InputsJson '{"input":"C:\\Users\\just_\\Music\\voice-memo.m4a","format":"wav","sample_rate":16000,"channels":1}'
```

The single `lifeorch.skill.result/0.1` JSON envelope is written to stdout (captured by the executor into
`stdout.txt`); the converted `audio.wav`, `ingest.json`, and `ingest.md` land under
`runtime/artifacts/<invocation_id>/`. A representative envelope is in `example-result.json`.
