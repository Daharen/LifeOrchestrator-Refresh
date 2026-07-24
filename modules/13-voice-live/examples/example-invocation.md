# voice.live — example invocation

A full voice turn: a spoken question in, a transcript + a concise answer + a spoken reply out.

```powershell
pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputFile 'F:\Local_TTS_Large_Data\external\whisper.cpp_cuda\samples\jfk.wav'
```

Via `-InputsJson` (the generic channel the wrapper uses), answering with a stronger tier and an mp3 reply:

```powershell
pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputsJson '{
  "input": "C:\\Users\\just_\\Downloads\\question.wav",
  "respond": true,
  "speak": true,
  "tier": "mid",
  "speaker": "Aiden",
  "format": "mp3",
  "system": "You are a terse voice assistant. Answer in one sentence."
}'
```

Transcribe-and-read-back only (no LLM), useful as a captioning + playback loop:

```powershell
pwsh -NoProfile -File .\Invoke-VoiceLive.ps1 -InputFile .\memo.wav -Respond:$false -ReadbackTranscript:$true
```

Through the Module 1 wrapper, or as an executor task package (read the envelope from
`runtime/completed/<task_id>/stdout.txt`).

The envelope goes to **stdout** (single JSON object); diagnostics to **stderr**. The turn record is written as
`voice.json` / `voice.md`, and the spoken reply as `reply.wav`, under `runtime/artifacts/<invocation_id>/`
(alongside `stt/`, `gateway/`, `tts/` child artifact subdirs). See `example-result.json` for a real result.
