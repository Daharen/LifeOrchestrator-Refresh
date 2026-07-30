# media.decompose -- example invocation

Decompose a video into its parts: always the structured probe metadata, plus (opt-in) the primary audio
track as whisper-ready WAV, up to N keyframe PNGs, and a scene-change list.

## Direct

```powershell
# metadata only (container + per-stream codec/resolution/fps/... + stream counts)
pwsh -NoProfile -File .\Invoke-MediaDecompose.ps1 -InputFile 'C:\Users\just_\Videos\clip.mp4'

# full decompose: audio + 5 keyframes + scene list
pwsh -NoProfile -File .\Invoke-MediaDecompose.ps1 -InputFile 'C:\Users\just_\Videos\clip.mp4' `
  -Audio -Keyframes 5 -Scenes -SceneThreshold 0.4
```

## Via -InputsJson (how a local/frontier caller or an orchestrator invokes it)

```powershell
pwsh -NoProfile -File .\Invoke-MediaDecompose.ps1 -InputsJson '{
  "input": "C:\\Users\\just_\\Videos\\clip.mp4",
  "audio": true,
  "audio_format": "wav",
  "loudness": "none",
  "keyframes": 5,
  "scenes": true,
  "scene_threshold": 0.4
}'
```

## Wrapped (Module 1 generic runner)

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
  -InputsJson '{"input":"C:\\Users\\just_\\Videos\\clip.mp4","scenes":true}'
```

## Through the executor (task package)

`task.json`:

```json
{ "task_id": "media-decompose-demo", "script_file": "task.ps1", "timeout_seconds": 600,
  "submitted_by": "some-agent", "description": "Decompose a clip: meta + audio + keyframes + scenes." }
```

`task.ps1`:

```powershell
pwsh -NoProfile -File 'C:\Users\just_\LifeOrchestrator-Refresh\modules\32-media-decompose\Invoke-MediaDecompose.ps1' `
  -InputsJson '{"input":"C:\\Users\\just_\\Videos\\clip.mp4","audio":true,"keyframes":5,"scenes":true}'
```

The single `lifeorch.skill.result/0.1` JSON envelope is written to stdout (captured by the executor into
`stdout.txt`); `meta.json`, `decompose.md`, the extracted `audio.wav` (from the composed audio.ingest run,
under `audio/`), the `keyframe_000.png ...` frames + `keyframes.json` sidecar, and `scenes.json` land under
`runtime/artifacts/<invocation_id>/`. A representative envelope is in `example-result.json`.
