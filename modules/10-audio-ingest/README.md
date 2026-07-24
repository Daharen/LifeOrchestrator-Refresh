# Module 10 — Audio Ingest: Normalize & Convert (`audio.ingest`)

The **front door for the audio track** (Modules 10–13). Given one audio *or* media file, it produces a
single, predictable output: a chosen format + sample rate + channel count + sample format, with optional
loudness normalization — by wrapping the machine's `ffmpeg`/`ffprobe`. It emits a contract-valid
`lifeorch.skill.result/0.1` envelope plus the output audio, a machine record, and a human summary. It is
**deterministic** (a fixed transcode of fixed bytes; no model — `confidence` is null) and
`parallel_safe:true` (reads an input, writes only to its own invocation artifact dir).

## What it does

Every invocation reduces to one `ffmpeg` run over the **first audio stream** of the input (audio is
extracted transparently from video containers; the video is dropped):

| knob | param | default | notes |
|------|-------|---------|-------|
| format/container | `-Format` | `wav` | `wav` \| `mp3` \| `flac` \| `opus` \| `ogg` \| `m4a` |
| sample rate | `-SampleRate` | `16000` | Hz; `0` keeps the source rate |
| channels | `-Channels` | `1` | `1` (mono) \| `2` (stereo); `0` keeps the source layout |
| PCM sample format | `-SampleFormat` | `s16` | wav only: `s16`\|`s24`\|`s32`\|`flt` |
| loudness | `-Loudness` | `none` | `none` \| `peak` (→ `-PeakDb`, default −1 dBFS) \| `ebu` (EBU R128) |
| bitrate (lossy) | `-Bitrate` | per-format | e.g. `192k` (mp3/opus/ogg/m4a) |

**The defaults produce whisper-ready audio** — a bare `audio.ingest -InputFile x.mp3` yields 16 kHz mono
s16 WAV, exactly what `speech.stt` (Module 11, whisper.cpp) wants. Codec per format: wav→`pcm_s16le`
(/s24le/s32le/f32le), mp3→`libmp3lame`, flac→`flac`, opus→`libopus`, ogg→`libvorbis`, m4a→`aac`.

Loudness `peak` is a two-pass measurement: it runs `volumedetect`, reads `max_volume`, and applies a
`volume` gain so the peak lands at `-PeakDb`; the measured peak and applied gain are reported. `ebu` uses
ffmpeg's `loudnorm=I=<i>:TP=<tp>:LRA=<lra>` (defaults −16 LUFS / −1.5 dBTP / 11 LU).

## Tool resolution

`ffmpeg` is resolved from `-FfmpegPath` → `Get-Command ffmpeg` → known install locations (WinGet Links,
`C:\Program Files\ffmpeg\bin`, `C:\ffmpeg\bin`). **`ffprobe` is resolved as the sibling of the resolved
`ffmpeg`** (falling back to a non-`Python\Scripts` `Get-Command ffprobe`) — this deliberately avoids the
Python `Scripts\ffprobe.exe` shim that shadows the real `ffprobe` on this machine's PATH. If `ffprobe`
cannot be found the conversion still runs; only the input/output metadata is limited (a warning is added).

Verified present on `DESKTOP-PF5FFMF` (2026-07-24): **ffmpeg 8.1-full_build** (Gyan.dev) with
`libmp3lame`/`aac`/`flac`/`libopus`/`libvorbis`/`pcm_*`. No install is required.

## Result shape

```
result = {
  input:  { path, exists, audio_stream_present, probe:{format_name,duration_s,size_bytes,bit_rate,
                                                        audio:{codec,sample_rate,channels,channel_layout,bit_rate}} | null },
  output: { path, format, container, codec, sample_rate, channels, sample_fmt, bitrate,
            duration_s, bytes, sha256, probe:{…} },
  normalization: { sample_rate, channels, sample_fmt,
                   loudness:{ mode, i,tp,lra | peak_db, measured_max_volume_db?, applied_gain_db? } },
  ffmpeg:  { path, version, argv:[…] },   // exact argument vector, for audit / reproduction
  ffprobe: { path }
}
```

## Invocation

```powershell
# default → whisper-ready 16 kHz mono s16 WAV
pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputFile .\voice-memo.m4a

# transcode to 192 kbps mp3, keep source rate/channels
pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputFile .\song.wav -Format mp3 -Bitrate 192k -SampleRate 0 -Channels 0

# EBU R128 loudness normalization to flac
pwsh -NoProfile -File .\Invoke-AudioIngest.ps1 -InputsJson '{"input":"clip.mp4","format":"flac","loudness":"ebu"}'

# wrapped (Module 1) or as an exec.bootstrap task package
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"input":"clip.mp3"}'
```

Named params and `-InputsJson` may be combined; named params win where explicitly set. Artifacts land in
`runtime/artifacts/<invocation_id>/` (`audio.<ext>`, `ingest.json`, `ingest.md`, `stderr.txt`, `result.json`).

## Errors (always a valid envelope, exit 0)

`input_not_found`, `invalid_format`, `invalid_channels`, `invalid_sample_rate`, `invalid_sample_format`
(wav), `invalid_loudness`, `no_audio_stream` (input has no audio), `ffmpeg_not_found`, `ffmpeg_failed`
(non-zero ffmpeg exit; stderr tail included), `unhandled_exception`.

## Scope

**In:** one input → one output; convert + resample + rechannel + sample-format + loudness (peak/EBU).
**Out (later modules/follow-ons):** transcription/STT (11), TTS (12), trimming/segmentation/VAD/
concatenation/mixing (13+), denoise/EQ, batch/directory ingest, video output. See `WORK_ORDER.md` and
DECISION_LOG `D-0019`.

## Tests

`tests/Invoke-AudioIngestTests.ps1` is **OS-portable** (uses `[IO.Path]::GetTempPath()` + `Get-Command
ffmpeg`), so the same harness runs on the cloud Linux box (ffmpeg 6.x, pre-ship gate) and on the Windows
executor (ffmpeg 8.x). Fixtures are generated by ffmpeg itself (a 2 s stereo sine + a 1 s audio-less
video). It checks the manifest, a real default WAV (codec/rate/channels via ffprobe, WAV magic, sha256),
the full format matrix (mp3/flac/opus/ogg/m4a magic + codec), keep-source, EBU + peak loudness, every
error path, and the Module 1 wrapper.
