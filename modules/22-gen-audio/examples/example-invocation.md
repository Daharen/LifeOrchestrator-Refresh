# gen.audio — example invocations

Deterministic, procedural audio generation. One `-Kind` per call. Direct, wrapped, or via the executor.

## Direct

```powershell
# A 1 s 440 Hz reference tone (default: sine, wav, 44.1 kHz mono, amplitude 0.5)
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind tone -Note A4 -Duration 1

# A short notification "blip" (square wave, quick fade to avoid a click), as mp3
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind tone -Note A5 -Waveform square -Duration 0.15 -FadeOutMs 20 -Format mp3

# A pleasant "done" chord (C major), stereo
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind chord -Notes "C4,E4,G4" -Channels 2 -Duration 0.8 -FadeOutMs 60

# A pink-noise focus bed (10 minutes), seeded so it is reproducible
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind noise -Color pink -Duration 600 -Format opus

# A rising sweep (chirp) 200 Hz -> 4 kHz, for audio testing
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind sweep -FreqStart 200 -FreqEnd 4000 -Duration 2

# 500 ms of digital silence (padding / fixture)
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind silence -Duration 0.5
```

## Generic `-InputsJson` (how a router / agent / the wrapper calls it)

```powershell
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -InputsJson '{"kind":"chord","notes":"A3,C#4,E4","waveform":"triangle","duration":1.5,"format":"flac"}'
```

## Through the Module 1 wrapper

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"kind":"tone","frequency":440,"duration":1}'
```

## Notes
- **Deterministic:** the same inputs (including the noise `seed`) produce byte-identical output.
- **Cheapest generator:** CPU-only, no model, no download, `parallel_safe:true`.
- For EBU R128 / peak loudness normalization, pipe the output through `audio.ingest -Loudness ebu|peak`.
- Neural text-to-audio (SFX/music) is out of scope here — see `gen.music` and the neural follow-on in `WORK_ORDER.md`.
