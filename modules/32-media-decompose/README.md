# Module 32 -- Media Decompose (`media.decompose`)

The **front door for video** and the first module of the Phase C video spine (architectural position 19).
It is the video analog of `audio.ingest` #10 and `image.util` #15: given one video *or* media file, it
decomposes it into its constituent parts by wrapping the machine's `ffmpeg`/`ffprobe`. It emits a
contract-valid `lifeorch.skill.result/0.1` envelope plus the produced artifacts (metadata, audio, keyframes,
scene list) and a human summary. It is **deterministic** (a fixed decode of fixed bytes; no model --
`confidence` is null) and `parallel_safe:true` (reads an input, writes only to its own invocation artifact
dir; no CUDA, no model, no loopback port).

## What it does

`meta` runs **always**; the other three ops are opt-in flags. Keep the surface small.

| op | flag | what it produces |
|----|------|------------------|
| **meta** (always) | -- | `ffprobe -show_format -show_streams -of json` -> a structured record: container/format, duration, and per-stream `{codec, resolution, fps (parsed from `r_frame_rate`), pixel format, bitrate, channel layout, sample rate}` plus stream counts (video/audio/subtitle/data/other/total). The deterministic core. |
| **audio** | `-Audio` | extracts the **primary audio track** to WAV by **composing `audio.ingest` #10** as an isolated child process -- default whisper-ready **16 kHz mono s16**; `-AudioFormat` (`wav\|mp3\|flac\|opus\|ogg\|m4a`) and `-Loudness` (`none\|peak\|ebu`) pass through. Reports `no_audio_stream` cleanly (a warning + `extracted:false`, status `partial`) if the input has no audio. |
| **keyframes** | `-Keyframes N` | extracts up to **N** representative frames as PNGs. **Scene-change frames are preferred** (`select='gt(scene,thr)'`); if there are fewer than N, the remainder is filled with **evenly spaced** timestamps. Deterministic, chronological order; a `keyframes.json` sidecar records `{index, timestamp_s, source (scene\|even), score, path, bytes, sha256}`. |
| **scenes** | `-Scenes` | scene-change detection (ffmpeg `scene` score via `metadata=print`) -> `scenes.json`, a list of `{index, start, end, score}` where each entry is a detected cut: `start` = the cut timestamp, `end` = the next cut (or the clip duration for the last), `score` = its scene score. `-SceneThreshold` (0..1, default 0.4) is the deterministic cut threshold. |

## Tool resolution

`ffmpeg` is resolved from `-FfmpegPath` -> `Get-Command ffmpeg` -> known install locations (WinGet Links,
`C:\Program Files\ffmpeg\bin`, `C:\ffmpeg\bin`). **`ffprobe` is resolved as the sibling of the resolved
`ffmpeg`** (falling back to a non-`Python\Scripts` `Get-Command ffprobe`) -- this deliberately avoids the
Python `Scripts\ffprobe.exe` shim that shadows the real `ffprobe` on this machine's PATH. For `-Audio`, the
composed `audio.ingest` entrypoint is resolved as the `../10-audio-ingest` sibling (override with
`-AudioIngestPath`), spawned with a resolved `pwsh` (`-PwshPath` -> `$PSHOME` -> PATH -> the known
dotnet-tool path) so its result envelope never pollutes this skill's stdout.

Verified present on `DESKTOP-PF5FFMF`: **ffmpeg / ffprobe 8.1** (Gyan.dev full build). No install required.

## Result shape

```
result = {
  input:  { path, exists, bytes },
  meta:   { container:{format_name,format_long_name,duration_s,size_bytes,bit_rate,nb_streams},
            streams:[{index,codec_type,codec_name,codec_long_name,
                      # video: width,height,pix_fmt,r_frame_rate,avg_frame_rate,fps,nb_frames,bit_rate,duration_s
                      # audio: sample_rate,channels,channel_layout,sample_fmt,bit_rate,duration_s
                      # subtitle: language }],
            stream_counts:{video,audio,subtitle,data,other,total}, duration_s },
  operations: { audio:<bool>, keyframes:<int>, scenes:<bool> },
  audio:  null | { requested, extracted, path, format, codec, sample_rate, channels, duration_s, bytes,
                   sha256, composed_skill:"audio.ingest", composed_invocation_id, composed_status }
               | { requested, extracted:false, reason:"no_audio_stream" | "audio_ingest_failed" | ... },
  keyframes: null | { requested_n, source, count, threshold, sidecar_path,
                      frames:[{index,timestamp_s,source,score,path,bytes,sha256}] },
  scenes:    null | { threshold, count, duration_s, path, scenes:[{index,start,end,score}] },
  ffmpeg:  { path, version },
  ffprobe: { path }
}
```

Artifacts land in `runtime/artifacts/<invocation_id>/`: `meta.json`, `decompose.md`, `result.json`,
`stderr.txt`, plus (per op) `keyframe_000.png ...` + `keyframes.json`, `scenes.json`, and the composed
`audio/audio.<ext>` (with its own `audio/result.json`). Every artifact path in the envelope is absolute.

## Errors (always a valid envelope, exit 0)

`input_not_found`, `invalid_audio_format`, `invalid_loudness`, `invalid_scene_threshold`, `ffmpeg_not_found`,
`ffprobe_not_found`, `ffprobe_failed` / `ffprobe_parse_failed`, `invalid_inputs_json`, `unhandled_exception`.
A missing audio track (`-Audio`) or missing video (`-Keyframes`/`-Scenes`) is **not** an error -- it is a
warning + a `reason` field + status `partial`, so a caller always gets whatever else succeeded.

## Scope

**In (this MVP):** deterministic decompose -- probe metadata (always) + primary-audio extraction (composing
#10) + keyframe PNGs (scene-preferred / evenly spaced) + scene-boundary list. CPU-only, `parallel_safe:true`.

**Out (named follow-ons, NOT built here):** subtitle-stream extraction to `.srt`/`.vtt`; clip segmentation by
scene boundary; a low-res proxy transcode; batch / directory input; VAD-based audio segmentation; a
contact-sheet / thumbnail grid; and **any model/VLM frame interpretation** -- that is `video.interpret`
(architectural position #22), a later module. This module is not a review-queue producer.

## Tests

`tests/Invoke-MediaDecomposeTests.ps1` is **dual-mode + OS-portable** (uses `[IO.Path]::GetTempPath()` +
`Get-Command ffmpeg`), so the same harness is both the cloud pre-ship gate (Linux, ffmpeg 6.x) and the live
Windows/executor test (`-Live`, ffmpeg 8.x). Fixtures are generated at runtime by `New-MediaFixture.ps1` via
ffmpeg lavfi -- a 4 s two-segment clip (`testsrc2` -> `smptebars`) with one hard scene cut plus a 440 Hz sine
audio track, and a no-audio variant -- so nothing binary is committed. It AST-parses the shipped `.ps1`
files, validates the manifest, and exercises meta, `-Audio` (real composition of #10), `-Keyframes`,
`-Scenes`, the combined path, the no-audio path, every error path, `-InputsJson`, and the Module 1 wrapper.
