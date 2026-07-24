# Work Order: Audio Ingest — Normalize & Convert (`audio.ingest`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 10 build session) / 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#10 audio.ingest`

### Problem being solved
The audio track (Modules 10–13) needs a single, reliable front door that turns *any* audio the
machine encounters — an arbitrary `.mp3`/`.m4a`/`.ogg`/`.flac`/`.wav`, or the audio buried in a
`.mp4`/`.mkv`/`.webm` — into a **canonical, predictable form** that every downstream audio skill can
assume. Right now nothing does this: `speech.stt` (Module 11, whisper.cpp) wants 16 kHz mono PCM WAV,
`speech.tts` (Module 12) and later modules each have their own format expectations, and callers should
not have to hand-craft `ffmpeg` command lines (or discover that the machine's `ffprobe` on PATH is
actually a Python shim). This module closes that gap: **one deterministic skill that normalizes and
converts a single audio/media file** to a requested format + sample rate + channel count + optional
loudness normalization, and reports exactly what it produced.

### Immediate practical use
This week, the very next module (`speech.stt`) can call `audio.ingest -InputFile <anything>` and get back a
whisper-ready **16 kHz mono s16 WAV** without knowing any `ffmpeg` flags — that is the default output.
A frontier or local agent that has a voice memo, a downloaded clip, or a video and wants "just give me
clean audio in format X at rate Y" calls this skill and reads the resolved metadata (duration, codec,
sample rate, channels) from the envelope. It is the normalize/convert primitive the rest of the audio
track builds on.

### Explicit scope (in)
- **One input → one output**, by file path (`-Input`). The input may be any container `ffmpeg` can
  decode; the **first audio stream** is used (audio extracted transparently from video containers).
- **Convert** to a target `-Format` ∈ {`wav`, `mp3`, `flac`, `opus`, `ogg`, `m4a`} with the right codec
  per container (wav→pcm_s16le/s24le/s32le/f32le, mp3→libmp3lame, flac→flac, opus→libopus,
  ogg→libvorbis, m4a→aac).
- **Normalize** the canonical audio characteristics:
  - `-SampleRate` (Hz; default **16000**; `0` = keep source),
  - `-Channels` (1|2; default **1** = mono; `0` = keep source),
  - `-SampleFormat` for PCM/WAV (`s16`|`s24`|`s32`|`flt`; default `s16`),
  - `-Loudness` ∈ {`none`, `peak`, `ebu`} (default `none`):
    - `peak` — two-pass: measure `max_volume` (`volumedetect`), apply a `volume` gain so the peak lands
      at `-PeakDb` (default `-1.0` dBFS). Deterministic; reports measured peak + applied gain.
    - `ebu` — EBU R128 loudness (`loudnorm=I=<i>:TP=<tp>:LRA=<lra>`, defaults `-16`/`-1.5`/`11`).
  - `-Bitrate` (e.g. `192k`) for the lossy formats (mp3/opus/ogg/m4a); sensible per-format default.
- **Defaults produce whisper-ready audio**: `wav`, 16000 Hz, mono, s16, no loudness change — so a
  bare `audio.ingest -Input x.mp3` yields exactly what Module 11 wants.
- **Robust tool resolution**: `-FfmpegPath`/`-FfprobePath` override → else `Get-Command ffmpeg` → else a
  known-candidate list. **`ffprobe` is resolved as the sibling of the resolved `ffmpeg`** (dodging the
  Python `Scripts\ffprobe.exe` shim that shadows the real one on this machine's PATH).
- Emit one contract-valid `lifeorch.skill.result/0.1` envelope on stdout; write the output audio +
  `ingest.json` (machine) + `ingest.md` (human) artifacts. Reuse Module 1 validators / `Invoke-Skill.ps1`
  and run through the executor. `parallel_safe: true` (reads an input, writes a fresh artifact; no shared
  state mutated).

### Non-goals (out — do NOT build)
- **No transcription / STT** (Module 11 `speech.stt`) and **no TTS** (Module 12). This skill only shapes
  audio bytes; it never interprets them.
- **No trimming / segmentation / silence-splitting / VAD / concatenation / mixing** — one whole input to
  one whole output. Cutting and multi-file work belong to a later media/`voice.live` module (13) or a
  dedicated follow-on.
- **No video output / muxing / re-encoding video** — the video stream is dropped (`-vn`); only the audio
  stream is ingested.
- **No denoise / EQ / arbitrary filtergraphs** beyond resample + channel + loudness. (A high-pass/denoise
  option is a possible follow-on, not this MVP.)
- **No batch / directory ingest** — one input per invocation (`batch:false`). A batch/`items_path` mode is
  a documented follow-on.
- **No streaming / live capture / recording** (Module 13).
- **No analysis artifacts** (spectrograms, feature/loudness reports beyond the values applied).
- **No concealment / persistence / propagation / monitoring-evasion** (executor hard prohibition). Runs
  once, in the foreground, as ordinary visible activity.

### Dependencies
- Modules: **1** (`SkillContract.psm1` validators, `Invoke-Skill.ps1` wrapper). Runs through Module **0**
  (executor). Consumed next by Module **11** (`speech.stt`).
- Tools/models: **`ffmpeg` + `ffprobe`** — verified present on `DESKTOP-PF5FFMF` this session:
  `ffmpeg 8.1-full_build` (Gyan.dev) on PATH at `…\WinGet\Links\ffmpeg.exe`, full encoder set
  (libmp3lame, aac, flac, libopus, libvorbis, pcm_*). No models. `pwsh>=7.4` (registry `pwsh`).
- Contract features: manifest `lifeorch.skill.manifest/0.1`; result `lifeorch.skill.result/0.1`;
  `-InputsJson` generic arg convention + artifact-root convention (DECISION_LOG D-0009).

### Skill contract requirements
- `skill_id` = `audio.ingest`; `name` = `Audio Ingest (Normalize & Convert)`; `version` = `0.1.0`;
  `determinism` = **`deterministic`** (a fixed transcode of fixed bytes by a fixed tool; no model —
  `confidence` = null, `model_provenance` = `[]`);
  `parallel_safe` = **true** (reads an input, writes only to its own invocation artifact dir — no shared
  external state, unlike `uia.actor`/`model.gateway`; CPU-bound, so heavy fan-out contends CPU only);
  `batch` = false; `streaming` = false. `requirements.audio` = **true**; `filesystem` = `read-write`
  (reads the input, writes the output artifact); `network` = false; `gpu` = none.
- `result` shape: `{ input, output, normalization, ffmpeg, ffprobe }` (detailed below). `confidence` null.
  Artifacts: `audio.<ext>` (kind = format), `ingest.json` (json), `ingest.md` (markdown), plus
  `stderr.txt`, `result.json` per convention.

### Inputs and outputs
- **Inputs** (named params and/or `-InputsJson`):
  - `input` string (**required**) — path to the source audio/media file.
  - `format` string (opt, default `wav`) — `wav|mp3|flac|opus|ogg|m4a`.
  - `sample_rate` int (opt, default `16000`; `0` = keep source).
  - `channels` int (opt, default `1`; `0` = keep source; else `1`|`2`).
  - `sample_fmt` string (opt, default `s16`) — WAV/PCM only (`s16|s24|s32|flt`); ignored+warned otherwise.
  - `loudness` string (opt, default `none`) — `none|peak|ebu`.
  - `peak_db` double (opt, default `-1.0`) — target peak dBFS for `peak`.
  - `loudness_i`/`loudness_tp`/`loudness_lra` double (opt, defaults `-16`/`-1.5`/`11`) — EBU targets.
  - `bitrate` string (opt) — e.g. `192k`, for lossy formats; per-format default when empty.
  - `ffmpeg_path`/`ffprobe_path` string (opt) — explicit tool overrides.
- **Outputs:** the `result` object; artifacts `audio.<ext>` + `ingest.json` + `ingest.md` under
  `runtime/artifacts/<invocation_id>/` (plus `stderr.txt`, `result.json`).
  - `input` = `{ path, exists, audio_stream_present, probe:{format_name,duration_s,size_bytes,bit_rate,
    audio:{codec,sample_rate,channels,channel_layout,bit_rate}} | null }`.
  - `output` = `{ path, format, container, codec, sample_rate, channels, sample_fmt, bitrate,
    duration_s, bytes, sha256, probe:{…} }`.
  - `normalization` = `{ sample_rate, channels, sample_fmt, loudness:{ mode, i,tp,lra | peak_db,
    measured_max_volume_db?, applied_gain_db? } }`.
  - `ffmpeg` = `{ path, version, argv:[…] }` (the exact argument vector, for auditability/repro);
    `ffprobe` = `{ path }`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/audio.<wav|mp3|flac|opus|ogg|m4a>` — the converted audio.
- `runtime/artifacts/<invocation_id>/ingest.json` — machine record (`lifeorch.audio.ingest/0.1` tag + full result).
- `runtime/artifacts/<invocation_id>/ingest.md` — human summary (input→output, params, loudness, argv).
- `runtime/artifacts/<invocation_id>/stderr.txt`, `result.json` — per contract.

### Proposed implementation
- **Language:** PowerShell (per language policy — wrap an existing, verified executable rather than
  reimplement; same stack as the other Windows skills). No new install.
- Approach: merge `-InputsJson` with named params (named win when explicitly set, matching capture.screen).
  Resolve `ffmpeg` (param → `Get-Command` → candidates) and `ffprobe` (param → **sibling of ffmpeg** →
  `Get-Command` excluding `\Python*\Scripts\`). Probe the input with `ffprobe -v error -print_format json
  -show_format -show_streams`; if no audio stream → structured `no_audio_stream` error. Build the argv:
  `ffmpeg -hide_banner -nostdin -y -i <input> -vn -map 0:a:0 [loudness -af] [-ar sr] [-ac ch]
  [-sample_fmt] -c:a <codec> [-b:a bitrate] -map_metadata -1 [-bitexact for wav] <output>`. For
  `loudness=peak`, first run a `volumedetect` pass, parse `max_volume`, compute the gain. Run ffmpeg with
  both stdout/stderr redirected to files (avoid the pipe-deadlock gotcha), check the exit code, then probe
  the output. Build the envelope with the shared shape (UTF-8 no BOM; only the envelope on stdout; lists
  via `.ToArray()`; `${var}` in interpolations; array accumulation via `List` then `.ToArray()`).

### External tools or models
- `ffmpeg` + `ffprobe` (present; see Dependencies). No models. **No install needed** — verified this
  session (`m10-ffprobe-001`).

### Installation steps
- None. Files live in `modules/10-audio-ingest/`. Registry gains an `ffmpeg`/`ffprobe` tool entry.

### Tests (`tests/Invoke-AudioIngestTests.ps1`, OS-portable; run on the executor — and off-machine first)
- Fixtures are **generated by ffmpeg itself** (no external asset): a 2 s 44.1 kHz **stereo** sine via
  `-f lavfi -i sine=…` and a 1 s **audio-less** video via `-f lavfi -i color=…` for the no-audio path.
  The harness uses `[IO.Path]::GetTempPath()` + `Get-Command ffmpeg`, so the **same file runs on the cloud
  Linux box (ffmpeg 6.1) and on the Windows executor (ffmpeg 8.1)**.
- **Manifest** validates (`Test-SkillManifest`).
- **Default ingest** (mp3-or-wav source → wav 16k mono s16): valid envelope, status ok, exit 0, output on
  disk, ffprobe reports `sample_rate=16000`/`channels=1`/`codec=pcm_s16le`, duration ≈ 2 s, WAV magic,
  and the file's bytes' sha256 equals `result.output.sha256`.
- **Format matrix** from the stereo source: `mp3` (codec mp3, MP3 magic), `flac` (codec flac, `fLaC`
  magic, lossless), `opus` (codec opus, `OggS` magic), `m4a` (codec aac, `ftyp` box). Each: valid
  envelope, output probed.
- **Keep-source** (`sample_rate=0 channels=0`): output is 44100 Hz / 2 ch.
- **Loudness** — `ebu`: runs, `normalization.loudness.mode=ebu`, output valid. `peak`: `measured_max_volume_db`
  and `applied_gain_db` populated, output valid.
- **Error paths** (valid error envelopes, exit 0): `input_not_found`; `invalid_format` (`-Format xyz`);
  `invalid_channels` (`-Channels 3`); `no_audio_stream` (the video-only fixture); `ffmpeg_not_found`
  (`-FfmpegPath` to a bogus path).
- **Wrapper** integration: `Invoke-Skill.ps1 -SkillDir . -InputsJson '{input…}'` ⇒ `manifest_valid` &
  `envelope_valid` true.
- **Pre-ship (cloud, off-machine):** AST-parse every shipped `.ps1`
  (`[Management.Automation.Language.Parser]::ParseFile`) with cloud pwsh 7.4.6, then **run the real skill
  and the full test harness on the cloud Linux ffmpeg** — this exercises the actual argv/format/loudness/
  probe logic (not a mock) before any bytes land on Windows.

### MVP acceptance criteria
- [ ] Manifest validates; entrypoint accepts named params **and** `-InputsJson`.
- [ ] Default invocation yields a real 16 kHz mono s16 WAV (probed), sha matches the file, envelope valid,
      exit 0.
- [ ] Each of wav/mp3/flac/opus/ogg/m4a produces a real file with the correct codec + magic bytes.
- [ ] `sample_rate`/`channels` normalization and keep-source both verified via ffprobe; `peak` and `ebu`
      loudness both run and are reported.
- [ ] Every failure mode returns a **valid** `lifeorch.skill.result/0.1` error envelope (exit 0), never a crash.
- [ ] Runs direct, wrapped, and through the executor; artifacts written; all tests pass.

### Manual verification procedure
- `audio.ingest -InputFile <some.mp3>` → open `audio.wav`; confirm it plays and is 16 kHz mono. Run with
  `-Format mp3 -Bitrate 192k` on a wav → confirm a smaller playable mp3. Feed the default WAV to a whisper
  smoke run (Module 11 preview) → confirm it is accepted.

### Documentation requirements
- Skill `README.md`, `skill.json` manifest, `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add an `ffmpeg`/`ffprobe` tool entry and an `audio.ingest` skill entry to `TOOL_MODEL_REGISTRY.md`
  (status installed, location, invocation, formats, I/O, limitations, last test).

### State updates
- `CURRENT_STATE.md` (Module 10 complete, deps, tests, next action) and `MODULE_ROADMAP.md`
  (Module 10 → MVP complete). Log the ingest-scope decisions (wrap ffmpeg; sibling-ffprobe resolution;
  defaults = whisper-ready; deterministic + `parallel_safe:true`) in `DECISION_LOG.md`.

### Known follow-on work (defer — not this session)
- Batch/directory ingest (`items_path`); trimming/segmentation/silence-split/VAD (→ Module 13); high-pass/
  denoise; per-channel handling; concatenation/mixing; an intra-run warm path. TTS-tokenizer dedup and the
  audio models' F: relocation stay with Modules 11/12. → later work orders.

### STOP conditions
- Scope would exceed the "Explicit scope" list (e.g. adding trimming, denoise, batch, or STT) — stop, write
  it into the roadmap.
- `ffmpeg` turns out to be absent or unusable and installing it is non-trivial — stop, note it in
  `REVIEW_QUEUE.md`. (Resolved: ffmpeg 8.1 is present.)
- The contract lacks something needed — stop, propose the change in DECISION_LOG, do not freelance.
- **MVP acceptance met — stop; do not start Module 11.**
