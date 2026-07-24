# speech.stt — example invocation

Transcribe the bundled whisper sample (already whisper-ready 16 kHz mono WAV), letting `-Normalize auto`
feed it straight through:

```powershell
pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 `
    -InputFile 'F:\Local_TTS_Large_Data\external\whisper.cpp_cuda\samples\jfk.wav'
```

Via `-InputsJson` (the generic channel the wrapper uses), forcing normalization through `audio.ingest`
for a non-whisper-ready input and flagging any segment below 0.6 to the review queue:

```powershell
pwsh -NoProfile -File .\Invoke-SpeechStt.ps1 -InputsJson '{
  "input": "C:\\Users\\just_\\Downloads\\voice-memo.m4a",
  "normalize": "always",
  "language": "en",
  "segment_confidence_threshold": 0.6
}'
```

Through the Module 1 wrapper:

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
    -InputsJson '{"input":"jfk.wav","normalize":"never"}'
```

Through the executor: submit a task package whose `task.ps1` calls `Invoke-SpeechStt.ps1` and read the
envelope from `runtime/completed/<task_id>/stdout.txt`.

The envelope goes to **stdout** (single JSON object); diagnostics go to **stderr**. The transcript is also
written as `transcript.json` / `transcript.md` / `whisper.srt` / `whisper.txt` under
`runtime/artifacts/<invocation_id>/`. See `example-result.json` for a real result.
