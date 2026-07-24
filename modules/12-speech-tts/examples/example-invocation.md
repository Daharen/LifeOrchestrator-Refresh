# speech.tts — example invocation

Synthesize an English sentence with a preset speaker (native 24 kHz mono WAV):

```powershell
pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 `
    -Text "Hello from Life Orchestrator. Your morning brief is ready." `
    -Speaker Ryan -Instruct "Speak in a calm, clear tone."
```

Via `-InputsJson` (the generic channel the wrapper uses), producing an MP3 (re-encoded via `audio.ingest`) with
a fixed seed for reproducibility:

```powershell
pwsh -NoProfile -File .\Invoke-SpeechTts.ps1 -InputsJson '{
  "text": "Good morning. Here is what changed overnight.",
  "speaker": "Aiden",
  "language": "English",
  "instruct": "Cheerful, energetic tone.",
  "format": "mp3",
  "seed": 42
}'
```

Through the Module 1 wrapper:

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
    -InputsJson '{"text":"This is a test.","speaker":"Ryan"}'
```

Through the executor: submit a task package whose `task.ps1` calls `Invoke-SpeechTts.ps1` and read the envelope
from `runtime/completed/<task_id>/stdout.txt`.

The envelope goes to **stdout** (single JSON object); diagnostics go to **stderr**. The audio is written as
`speech.wav` (or the converted format) under `runtime/artifacts/<invocation_id>/`, alongside `tts.json` /
`tts.md`. See `example-result.json` for a real result.
