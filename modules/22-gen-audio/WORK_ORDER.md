# Work Order: Local Audio Generation (`gen.audio`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork — Module 22 build session) / 2026-07-25 · **Roadmap entry:** `MODULE_ROADMAP.md → Build priority, Phase A #4 (generators, cheapest-first: gen.audio → gen.image → gen.music → gen.video)`

### Problem being solved
The generator track opens with the **cheapest** generator. The system already has *speech* (`speech.tts` #12, neural) and will get *music* (`gen.music`, neural, later) and *images* (`gen.image`, neural, next). What it has **no** way to do is synthesize the small, ubiquitous, non-speech, non-music audio primitives that Widgets and agents actually need on demand: a notification **beep**, an alert **tone** or **chord**, a reference **pitch**, **white/pink/brown noise** for masking/focus/sleep, a **frequency sweep** (chirp) for audio testing, or a block of **digital silence** for padding/fixtures. Today a caller would have to hand-craft `ffmpeg -f lavfi` command lines (and rediscover the machine's ffprobe PATH shim). This module closes that gap with **one deterministic skill that generates a single synthetic audio signal from a compact specification** and reports exactly what it produced — the audio counterpart of `image.util` (deterministic pixels) and `audio.ingest` (deterministic transcode).

**Design decision (probe-driven, `m22-probe-001`, 2026-07-25):** the MVP is a **deterministic, procedural ffmpeg synthesizer**, not a neural text-to-audio model. The probe confirmed (a) ffmpeg 8.1 synthesizes sine/`anoisesrc`/`aevalsrc`/`anullsrc` sources end-to-end to valid 44.1 kHz PCM16 WAV and encodes to mp3 (5/5 synth cases + mp3 all exit 0, ffprobe-valid); and (b) **no** neural audio-generation stack is staged — neither the system python nor the speech venv has `audiocraft`, `diffusers`, `stable_audio_tools`, `audioldm`, `TTS`, or `bark`, and no audio-gen model exists on disk. Going neural would require a library install **plus** a multi-GB model download on a space-constrained C: and an 11 GB (cc 7.5) GPU — the opposite of "cheapest-first." Procedural synthesis is instant, robust, CPU-only, parallel-safe, needs no download, and reuses the proven `audio.ingest` machinery. Neural text-to-audio (SFX via AudioGen/AudioLDM/Stable Audio) is a **documented follow-on / future stochastic tier**, not this MVP.

### Immediate practical use
This week: the **Widget** layer (Phase B) and any agent can call `gen.audio -Kind tone -Note A5 -Duration 0.2` for a notification blip, `-Kind noise -Color pink -Duration 600` for a focus bed, `-Kind chord -Notes "C4,E4,G4"` for a pleasant "done" sound, or `-Kind sweep` / `-Kind silence` for audio test fixtures (including fixtures for the audio track's own tests). It is the cheap, deterministic "make me a sound" primitive the rest of the system can assume, exactly as `audio.ingest` is the "clean up a sound" primitive.

### Explicit scope (in)
- **One spec → one audio file** per invocation (`batch:false`). A single `-Kind` selects the generator:
  - **`tone`** — a single sine partial. Frequency by `-Frequency <hz>` **or** `-Note <name>` (e.g. `A4`, `C#3`, `Bb5`; equal-temperament, A4 = 440). `-Waveform sine|square|triangle|sawtooth`.
  - **`chord`** — several partials summed (amplitude divided across them to avoid clipping). `-Frequencies "261.63,329.63,392"` **or** `-Notes "C4,E4,G4"`. Same `-Waveform`.
  - **`noise`** — `-Color white|pink|brown|blue|violet|velvet` via `anoisesrc`, with a fixed `-Seed` (default 0) so output is **reproducible/deterministic**.
  - **`sweep`** — a linear sine chirp from `-FreqStart` to `-FreqEnd` over the duration (`aevalsrc` phase expression).
  - **`silence`** — digital silence via `anullsrc`.
- **Shaping (all kinds):** `-Duration <s>` (default 1.0; `0 < d <= 3600`), `-SampleRate <hz>` (default 44100), `-Channels 1|2` (default 1; 2 = duplicated stereo), `-Amplitude 0..1` (default 0.5; peak scaling), `-FadeInMs`/`-FadeOutMs` (default 0; `afade` to kill clicks).
- **Output format:** `-Format wav|mp3|flac|opus|ogg|m4a` (default `wav`), `-SampleFormat s16|s24|s32|flt` (wav only; default s16), optional `-Bitrate` (lossy). **Encoded directly in the one ffmpeg pass** (codec map identical to `audio.ingest`) — no child process.
- **Robust tool resolution** identical to `audio.ingest`: `-FfmpegPath`/`-FfprobePath` override → `Get-Command ffmpeg` → known candidates; **ffprobe = sibling of the resolved ffmpeg** (dodges the Python `Scripts\ffprobe.exe` shim). ffprobe is used only to verify/annotate the output; its absence degrades gracefully (a warning, not a failure).
- Emit one contract-valid `lifeorch.skill.result/0.1` envelope on stdout; write `audio.<ext>` + `gen.json` (machine) + `gen.md` (human). Accept the generic `-InputsJson` and `-ArtifactRoot`/`-InvocationId`. Reuse Module 1 validators / `Invoke-Skill.ps1`; run through the executor. `determinism:"deterministic"`, `parallel_safe:true`.

### Non-goals (out — do NOT build)
- **No neural / text-to-audio / text-to-SFX generation** (AudioGen, AudioLDM, Stable Audio, Bark). That is the documented follow-on stochastic tier — it needs a library install + a multi-GB model and belongs in its own work order.
- **No music composition / melody / rhythm sequencing / MIDI** — a chord is a static stack of partials, not a song. Structured music is **`gen.music`** (separate, later).
- **No speech** (that is `speech.tts` #12).
- **No sample playback / mixing of external audio / concatenation / editing** — this generates from parameters only; it never reads an input audio file. Combining/mixing existing audio is a later media module.
- **No loudness normalization / EQ / denoise / arbitrary filtergraphs** beyond amplitude scaling + fades. A caller who wants EBU R128 pipes the output through `audio.ingest -Loudness ebu` (deliberate separation of concerns).
- **No batch / directory / multi-signal** output (`batch:false`); a batch mode is a documented follow-on.
- **No streaming / live playback** — writes a file; it does not play sound through a device.
- **No concealment / persistence / propagation / monitoring-evasion** (executor hard prohibition). Runs once, foreground, as ordinary visible activity.

### Dependencies
- Modules: **1** (`SkillContract.psm1` validators, `Invoke-Skill.ps1` wrapper). Runs through Module **0** (executor). Naturally composes with **10** (`audio.ingest`) downstream for optional loudness/format post-processing, but does **not** depend on it.
- Tools/models: **`ffmpeg` (+ `ffprobe`)** — verified this session on `DESKTOP-PF5FFMF` (`m22-probe-001`): `ffmpeg 8.1-full_build` (Gyan.dev) at `…\WinGet\Links\ffmpeg.exe`, full encoder set; `sine`/`anoisesrc`/`aevalsrc`/`anullsrc` generate valid PCM16 WAV. **No models. No install.** `pwsh>=7.4`.
- Contract features: manifest `lifeorch.skill.manifest/0.1`; result `lifeorch.skill.result/0.1`; the `-InputsJson` generic-arg + artifact-root conventions (v0.2 §3.1; D-0009).

### Skill contract requirements
- `skill_id` = `gen.audio`; `name` = `Local Audio Generation (Procedural)`; `version` = `0.1.0`; `contract_version` = `0.2`.
- `determinism` = **`deterministic`** (fixed synthesis of fixed parameters by a fixed tool; noise seeded → `confidence` = null, `model_provenance` = `[]`). **NOT a review-queue producer** (the seven-producer set + canonical `review_queue.jsonl` untouched).
- `parallel_safe` = **true** (generates from parameters, writes only its own invocation artifact dir; no shared state, no GPU, no port — CPU-bound like `audio.ingest`/`image.util`). `batch` = false; `streaming` = false.
- `requirements`: `executables:["pwsh>=7.4","ffmpeg>=6"]`, `models:[]`, `audio:true`, `filesystem:"read-write"` (writes only its artifact), `network:false`, `gpu:"none"`.
- `result` shape `{ generation, output, source, ffmpeg, ffprobe }` (below). `confidence` null.

### Inputs and outputs
- **Inputs** (named params and/or `-InputsJson` keys): `kind` (**required**: `tone|chord|noise|sweep|silence`); `frequency` (double, tone; def 440); `note` (string, tone); `frequencies` (string csv, chord); `notes` (string csv, chord); `waveform` (`sine|square|triangle|sawtooth`, def sine); `color` (`white|pink|brown|blue|violet|velvet`, def white; noise); `freq_start`/`freq_end` (double, sweep; def 200/2000); `seed` (int, def 0; noise); `duration` (double, def 1.0); `sample_rate` (int, def 44100); `channels` (int, def 1); `amplitude` (double, def 0.5); `fade_in_ms`/`fade_out_ms` (int, def 0); `format` (def `wav`); `sample_fmt` (def `s16`, wav only); `bitrate` (string, lossy); `ffmpeg_path`/`ffprobe_path` (overrides).
- **Outputs:** the `result` object + artifacts under `runtime/artifacts/<invocation_id>/`:
  - `generation` = `{ kind, waveform?, frequency?|frequencies?, note?|notes?, color?, seed?, freq_start?|freq_end?, duration_s, sample_rate, channels, amplitude, fade_in_ms, fade_out_ms }`.
  - `output` = `{ path, format, container, codec, sample_rate, channels, sample_fmt, bitrate, duration_s, bytes, sha256, probe:{…}|null }`.
  - `source` = `{ lavfi }` (the exact `-f lavfi -i` string used — auditable/reproducible).
  - `ffmpeg` = `{ path, version, argv:[…] }`; `ffprobe` = `{ path }`.

### Artifact structure
- `runtime/artifacts/<invocation_id>/audio.<wav|mp3|flac|opus|ogg|m4a>` — the generated signal.
- `runtime/artifacts/<invocation_id>/gen.json` — machine record (`lifeorch.gen.audio/0.1` tag + full result).
- `runtime/artifacts/<invocation_id>/gen.md` — human summary (kind, params, source, argv, output stats).
- `runtime/artifacts/<invocation_id>/stderr.txt`, `result.json` — per contract.

### Proposed implementation
- **Language:** PowerShell wrapping ffmpeg (language policy: wrap a present, verified binary; same stack + the exact `Invoke-Proc`/resolution/envelope machinery reused from `audio.ingest`). No new install, no Python, no model, **no `models.json` change, no Module 7 re-verify**.
- Approach: merge `-InputsJson` with named params (named win when explicitly set). Validate kind/format/waveform/color/channels/amplitude/duration and each frequency against Nyquist (`f < sample_rate/2`). Map `-Note`/`-Notes` → Hz (equal temperament). Build a single `-f lavfi` **source string** per kind:
  - tone/chord: `aevalsrc=exprs=<A/N * sum of waveform(f_i)>:s=<sr>:d=<dur>` where sine=`sin(2*PI*f*t)`, square=`sgn(sin(2*PI*f*t))`, sawtooth=`2*(f*t-floor(0.5+f*t))`, triangle=`2*abs(2*(f*t-floor(f*t+0.5)))-1`.
  - sweep: `aevalsrc=exprs=<A>*sin(2*PI*(f0*t+(f1-f0)/(2*T)*t*t)):s=<sr>:d=<dur>`.
  - noise: `anoisesrc=color=<c>:amplitude=<A>:seed=<seed>:duration=<dur>:sample_rate=<sr>`.
  - silence: `anullsrc=r=<sr>:cl=<mono|stereo>`.
  Then one ffmpeg argv: `-hide_banner -nostdin -y -f lavfi -i <source> -t <dur> [-af afade=in…,afade=out…] -ar <sr> -ac <ch> -c:a <codec> [-b:a <br>] -map_metadata -1 [-bitexact for wav] <out>`. Run via the async-drain `Invoke-Proc` (pipe-deadlock-safe), check exit + file, probe the output, build the shared-shape envelope (UTF-8 no BOM; only the envelope on stdout; `List`→`.ToArray()`; `${var}` interpolation; guard `.Count` before indexing).

### External tools or models
- `ffmpeg` (+ sibling `ffprobe`). Present; **no install** (`m22-probe-001`). No models.

### Installation steps
- None. Files live in `modules/22-gen-audio/`. `TOOL_MODEL_REGISTRY.md` gains a `gen.audio` skill entry (the `ffmpeg`/`ffprobe` tool entry already exists from Module 10).

### Tests (`tests/Invoke-GenAudioTests.ps1`, OS-portable; run off-machine on cloud ffmpeg first, then live on the executor)
- Fixtures are **generated by the skill itself** (no external asset). The harness uses `[IO.Path]::GetTempPath()` + `Get-Command ffmpeg`, so the **same file runs on the cloud Linux box and the Windows executor** — the real-engine-on-cloud gate (like `audio.ingest`/`image.util`).
- **Manifest** validates (`Test-SkillManifest`).
- **tone** (default): valid envelope, status ok, exit 0, `audio.wav` on disk, ffprobe `codec=pcm_s16le`/`sample_rate=44100`/`channels=1`, duration ≈ 1.0 s, WAV magic, file sha256 == `result.output.sha256`.
- **Determinism:** two identical `tone` (and two identical seeded `noise`) invocations produce **byte-identical** output (equal sha256).
- **note mapping:** `-Note A4` ⇒ 440 Hz recorded; `-Note C#3` parses; a bad note ⇒ `invalid_note`.
- **chord:** `-Notes "C4,E4,G4"` ⇒ three partials in `source.lavfi`, valid output.
- **waveforms:** sine/square/triangle/sawtooth each generate valid output.
- **noise:** each color (white/pink/brown/blue/violet/velvet) generates valid output.
- **sweep / silence:** each generates valid output; silence probes as ~digital silence.
- **shaping:** `-Channels 2` ⇒ 2-channel output; `-Duration 0.25` ⇒ dur ≈ 0.25; `-FadeInMs 50 -FadeOutMs 50` runs; `-Amplitude 0.1` runs.
- **format matrix:** wav/mp3/flac/opus/ogg/m4a each produce a real file with the correct codec + magic bytes.
- **error paths** (valid error envelopes, exit 0): `invalid_kind`; `invalid_format`; `invalid_waveform`; `invalid_color`; `invalid_channels`; `invalid_amplitude`; `invalid_duration` (0 or > 3600); `frequency_out_of_range` (f ≥ sr/2); `invalid_note`; `ffmpeg_not_found` (`-FfmpegPath` bogus); `ffmpeg_failed`.
- **Wrapper** integration: `Invoke-Skill.ps1 -SkillDir . -InputsJson '{"kind":"tone",…}'` ⇒ `manifest_valid` & `envelope_valid` true.
- **Pre-ship (cloud, off-machine):** AST-parse every shipped `.ps1` with cloud pwsh 7.4.6, then **run the real skill + full harness on the cloud Linux ffmpeg** before any bytes land on Windows.

### MVP acceptance criteria
- [ ] Manifest validates; entrypoint accepts named params **and** `-InputsJson`.
- [ ] Each kind (tone, chord, noise, sweep, silence) produces a real, ffprobe-valid audio file; sha matches the file; envelope valid; exit 0.
- [ ] Two identical invocations (tone + seeded noise) are byte-identical (deterministic).
- [ ] Note-name mapping, all four waveforms, all six noise colors, and stereo/duration/fade/amplitude shaping each verified.
- [ ] Each of wav/mp3/flac/opus/ogg/m4a produces the correct codec + magic bytes.
- [ ] Every failure mode returns a **valid** `lifeorch.skill.result/0.1` error envelope (exit 0), never a crash.
- [ ] Runs direct, wrapped, and through the executor; artifacts written; all tests pass off-machine **and** live.

### Manual verification procedure
- `gen.audio -Kind tone -Note A4 -Duration 1` → open `audio.wav`; confirm a 1 s 440 Hz tone. `-Kind noise -Color pink -Duration 3` → confirm a pink-noise bed. `-Kind chord -Notes "C4,E4,G4" -Format mp3` → confirm a playable major-chord mp3. Re-run the tone twice → confirm identical bytes.

### Documentation requirements
- Skill `README.md`, `skill.json` manifest, `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add a `gen.audio` skill entry to `TOOL_MODEL_REGISTRY.md` (status installed, location, invocation, kinds, I/O, limitations, last test). The `ffmpeg`/`ffprobe` tool entry already exists (Module 10).

### State updates
- `CURRENT_STATE.md` (Module 22 complete, deps, tests, next action) and `MODULE_ROADMAP.md` (Phase A #4 `gen.audio` → MVP complete; expand its entry). Log the gen.audio-scope decisions (procedural ffmpeg synthesis; deterministic + `parallel_safe:true`; probe-driven rejection of neural-for-MVP; kinds/shaping surface) in `DECISION_LOG.md` (D-0033). Mirror core-docs → the Project.

### Known follow-on work (defer — not this session)
- **Neural text-to-audio SFX tier** (AudioGen / AudioLDM / Stable Audio Open) — the stochastic generation counterpart; its own work order (install stack + stage a model on F:; would add `model_provenance` + a real `confidence` + review-queue producer behaviour).
- Batch/multi-signal output; ADSR envelopes / per-partial amplitudes / detune; DTMF & Morse presets; a metronome/click-track preset; waveform for sweep; arbitrary user `aevalsrc` expression (guarded); stereo panning / binaural beats; direct piping into `audio.ingest` for one-call loudness-normalized output.

### STOP conditions
- Scope would exceed the "Explicit scope" list (e.g. adding neural generation, music sequencing, mixing, or batch) — stop; write it into the roadmap.
- `ffmpeg` turns out to be absent/unusable and installing it is non-trivial — stop; note it in `REVIEW_QUEUE.md`. (Resolved: ffmpeg 8.1 present, synthesis verified `m22-probe-001`.)
- The contract lacks something needed — stop; propose the change in DECISION_LOG; do not freelance.
- **MVP acceptance met — stop; do not start the next module (`gen.image`).**
