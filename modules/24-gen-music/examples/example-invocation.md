# gen.music — example invocations

## Direct (named params)
```powershell
pwsh -NoProfile -File .\Invoke-GenMusic.ps1 -Prompt "upbeat 8-bit chiptune, energetic" -Duration 8 -Seed 42
```

## Direct (longer, stronger guidance, mp3)
```powershell
pwsh -NoProfile -File .\Invoke-GenMusic.ps1 `
  -Prompt "warm jazz piano trio, relaxed swing" `
  -Duration 12 -Guidance 4 -Temperature 1.0 -TopK 250 -Format mp3
```

## Generic `-InputsJson` (a router / the executor / an orchestrator skill)
```powershell
pwsh -NoProfile -File .\Invoke-GenMusic.ps1 -InputsJson '{
  "prompt": "calm ambient pads, slow evolving, cinematic",
  "duration": 10, "guidance": 3.0, "temperature": 1.0,
  "top_k": 250, "top_p": 0.0, "seed": 2024, "format": "flac"
}'
```

## Through the Module 1 generic wrapper (manifest → run → envelope validation)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"prompt":"a gentle lofi hip hop beat","duration":8}'
```

## Through the executor (task package)
`task.ps1`:
```powershell
pwsh -NoProfile -File C:\Users\just_\LifeOrchestrator-Refresh\modules\24-gen-music\Invoke-GenMusic.ps1 `
  -InputsJson '{"prompt":"an epic orchestral build","duration":10}'
```

Notes:
- `-Seed -1` (default) picks a random seed and records the actual seed used in `result.request.seed`.
  A fixed seed >= 0 is byte-reproducible on this GPU.
- MusicGen produces **32 kHz mono** audio; the WAV is written to
  `runtime/artifacts/<invocation_id>/music.wav`. A non-wav `-Format` (or a non-native `-SampleRate`) is
  produced by composing `audio.ingest` (#10) into `music.<ext>`; its absolute path, bytes, and sha256 are
  in `result.audio`.
- `-Duration` seconds are converted to MusicGen tokens via the model frame rate (~50 Hz); duration is
  bounded to 1..30 s (MusicGen Small's trained horizon).
- A silent or failed generation is flagged to the review queue (`verify_generation`, `flagged_by:"gen.music"`).
- The music is instrumental only (MusicGen does not sing lyrics).
