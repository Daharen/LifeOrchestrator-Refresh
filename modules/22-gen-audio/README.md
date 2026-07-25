# gen.audio — Local Audio Generation (Procedural)

**Module 22 · Phase A #4 (generators, cheapest-first) · `skill_id: gen.audio` · contract v0.2**

Generate a single **synthetic** audio signal from a compact specification by wrapping ffmpeg's
`lavfi` sources. The cheapest generator in the suite: no model, no download, CPU-only, deterministic,
`parallel_safe`. It is the audio counterpart of `image.util` (deterministic pixels) and the generation
counterpart of `audio.ingest` (deterministic transcode).

This module is **procedural** — it synthesizes tones, chords, colored noise, sweeps, and silence from
parameters. It does **not** do neural text-to-audio (SFX) or music composition; those are, respectively,
a documented follow-on and the separate `gen.music` module. It also never reads an input audio file.

## Kinds (one `-Kind` per invocation)

| Kind      | What it makes                                   | Key params |
|-----------|-------------------------------------------------|------------|
| `tone`    | one partial (sine/square/triangle/sawtooth)     | `-Frequency` or `-Note`, `-Waveform` |
| `chord`   | several partials summed (clip-safe)             | `-Frequencies` or `-Notes`, `-Waveform` |
| `noise`   | colored noise (seeded → reproducible)           | `-Color`, `-Seed` |
| `sweep`   | linear sine chirp                               | `-FreqStart`, `-FreqEnd` |
| `silence` | digital silence                                 | — |

Shaping (all kinds): `-Duration` (s), `-SampleRate` (Hz), `-Channels` (1|2), `-Amplitude` (0..1),
`-FadeInMs`, `-FadeOutMs`. Output: `-Format wav|mp3|flac|opus|ogg|m4a`, `-SampleFormat` (wav only),
`-Bitrate` (lossy). Note names are equal-temperament with A4 = 440 (e.g. `A4`, `C#3`, `Bb5`).

## Usage

```powershell
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind tone -Note A4 -Duration 1
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind chord -Notes "C4,E4,G4" -Format mp3
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -Kind noise -Color pink -Duration 600
pwsh -NoProfile -File .\Invoke-GenAudio.ps1 -InputsJson '{"kind":"sweep","freq_start":200,"freq_end":4000,"duration":2}'
```

Every call emits one `lifeorch.skill.result/0.1` envelope on stdout and writes, under
`runtime/artifacts/<invocation_id>/`:

- `audio.<ext>` — the generated signal
- `gen.json` — machine record (`lifeorch.gen.audio/0.1`)
- `gen.md` — human summary (kind, params, `source.lavfi`, argv, output stats)
- `stderr.txt`, `result.json`

## Contract properties

- `determinism: deterministic` — `confidence: null`, `model_provenance: []`. The same inputs (noise
  `seed` included) produce byte-identical output.
- **Not** a review-queue producer (the seven-producer set + canonical `review_queue.jsonl` are untouched).
- `parallel_safe: true` (CPU-bound; writes only its own artifact dir; no GPU, no port, no shared state).
- `batch: false`, `streaming: false`. No `models.json` change; no Module 7 re-verify.

## How it works

A single ffmpeg pass. Per kind, a `-f lavfi -i <source>` string is built:
`aevalsrc=exprs=<waveform expression>` for tone/chord/sweep, `anoisesrc=color=…:seed=…` for noise,
`anullsrc` for silence. The output is encoded to the requested codec in the same command (codec map
identical to `audio.ingest`); `-bitexact` is set for wav. ffmpeg (and its sibling ffprobe, which only
annotates the output) are resolved exactly as in `audio.ingest`, dodging the Python `ffprobe` PATH shim.

## Dependencies

`ffmpeg` (+ sibling `ffprobe`) — present on this machine (`ffmpeg 8.1-full_build`); no install, no models.
Runs through the Module 0 executor and validates through the Module 1 wrapper.

## Not in scope (see `WORK_ORDER.md`)

Neural text-to-audio (AudioGen/AudioLDM/Stable Audio); music composition (`gen.music`); speech
(`speech.tts`); mixing/editing existing audio; loudness normalization (pipe through `audio.ingest`);
batch output; live playback.

## Tests

`tests/Invoke-GenAudioTests.ps1` — OS-portable, real-engine. Generates its own fixtures via the skill, so
the same harness runs off-machine on the cloud ffmpeg (pre-ship gate) and live on the Windows executor.
Covers every kind, determinism (byte-identical re-runs), note mapping, all waveforms/colors, the format
matrix, shaping, and all error paths, plus the Module 1 wrapper.
