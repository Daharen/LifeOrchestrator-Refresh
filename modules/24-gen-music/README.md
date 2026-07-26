# gen.music — Local Music Generation (Module 24)

Turn a text prompt into one short **instrumental** music clip with a local **MusicGen** model, entirely on
this machine. `gen.music` is the third generator in the Phase-A generator track
(`gen.audio` #22 procedural sound → `gen.image` #23 neural images → **`gen.music` #24** → `gen.video`), and
the second **neural** generator. It is the music-generation sibling of `gen.audio` (deterministic, procedural
sound) and the audio counterpart of `gen.image` (neural pixels).

## What it does

Given a `-Prompt` (a text description like *"upbeat 8-bit chiptune, energetic"*), it drives the transformers
`MusicgenForConditionalGeneration` model on the GPU and produces one **32 kHz mono** clip. The clip is written
as a PCM16 WAV; an optional non-wav `-Format` (mp3/flac/opus/ogg/m4a) or non-native `-SampleRate` is produced
by composing **`audio.ingest` (#10)**.

- **Deterministic-seedable** — a fixed `-Seed >= 0` is byte-reproducible on this GPU (`torch.manual_seed`);
  `-Seed -1` (default) picks a random seed and records the actual value used.
- **Confidence + review** — populates a `confidence` (a generation-completeness / non-silent heuristic from
  the audio RMS, **not** musical quality) and routes silent / failed / low-confidence generations to the
  canonical review queue as the **ninth** producer (`flagged_by:"gen.music"`, `requested:"verify_generation"`).
- **Peak-normalized** — MusicGen output can exceed ±1.0; `-Normalize` (default on) scales the clip to a 0.99
  peak so the PCM16 WAV does not clip.

## Architecture (D-0035, following the D-0021 / D-0034 worker+meta pattern)

```
Invoke-GenMusic.ps1  (PowerShell wrapper: contract envelope, validation, registry resolution,
        │                review-queue producer, optional audio.ingest format/rate conversion)
        │  spawns (child process)               reads meta file (never stdout)
        ▼                                        ▲
music_gen_infer.py  (Python worker under the speech venv: loads transformers MusicGen on CUDA,
                     generates, peak-normalizes, writes music.wav via soundfile + gen_meta.json)
```

The wrapper owns the `lifeorch.skill.result/0.1` envelope (like every skill); the model lives in its native
Python. The **meta-file hand-off** means transformers/torch console chatter can never corrupt the parsed
result. The model is resolved from the shared registry (`modules/07-model-gateway/models.json`,
`type=music-gen`, `engine=transformers`) and is **decoupled from the gateway `wired` gate** (the gateway runs
`type=llm` only) — exactly as `speech.tts` / `image.interpret` / `gen.image` do.

## Model

`music.musicgen-small` — **MusicGen Small** (`facebook/musicgen-small`, transformers folder format, **CC-BY-NC-4.0**),
staged to `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\24-gen-music\musicgen-small\` (~2.37 GB after
pruning the redundant audiocraft-format weights). Uses **no new library** — transformers 4.57 already ships
MusicGen. Loads fp32, ~2.4 GB VRAM peak on the RTX 2080 Ti, ~50 audio tokens/second. The license is
non-commercial (a deliberate deviation from the project's Apache-2.0 preference, precedented by SD 1.5's
OpenRAIL-M in `gen.image`); larger/permissive tiers (MusicGen Medium/Large, Stable Audio Open) are documented
follow-ons.

## Inputs

| param | default | notes |
|-------|---------|-------|
| `-Prompt` | *(required)* | text description of the music |
| `-Duration` | `8.0` | seconds, 1..30 (→ `round(duration × ~50)` tokens) |
| `-Guidance` | `3.0` | classifier-free guidance, 0..15 |
| `-Temperature` | `1.0` | sampling temperature, 0..2 (0 = greedy) |
| `-TopK` | `250` | top-k cutoff, ≥0 (0 = off) |
| `-TopP` | `0.0` | nucleus cutoff, 0..1 (0 = off) |
| `-Seed` | `-1` | -1 = random (recorded); ≥0 = reproducible |
| `-Normalize` | `$true` | peak-normalize to ≤0.99 |
| `-Format` | `wav` | wav\|mp3\|flac\|opus\|ogg\|m4a (non-wav via audio.ingest) |
| `-SampleRate` | `0` | 0 = native 32000; else 8000..192000 (via audio.ingest) |
| `-ConfidenceThreshold` | `0.5` | below this → review queue |
| `-Model` / `-Tier` | `music.musicgen-small` / `small` | registry `type=music-gen` |

Also accepts a single `-InputsJson '<json>'` (contract §3.1) and `-ArtifactRoot` / `-InvocationId`.

## Output

One `lifeorch.skill.result/0.1` envelope on stdout; artifacts in `runtime/artifacts/<invocation_id>/`:
`music.<ext>` (the audio), `gen.json` (machine record), `gen.md` (human card), plus `result.json`,
`gen_args.json`, `gen_meta.json`, `py.log`, `stderr.txt`. `result.audio` carries the path, format,
sample_rate, channels, samples, duration_s, bytes, sha256, rms, peak, and `converted` flag.

## Flags

`determinism: mixed` · `parallel_safe: false` (binds the CUDA context / VRAM) · `batch: false` ·
`streaming: false`. **Ninth review-queue producer** (7/8/11/12/14/16/17/23/**24**).

## Tests

`tests/Invoke-GenMusicTests.ps1` — **MOCK mode** (default) runs the **real** `Invoke-GenMusic.ps1` against
`tests/mock-worker.py` (stdlib `wave`, no torch/transformers/soundfile) so the full validation / confidence /
review / envelope path runs on the cloud Linux box before any bytes ship; **`-Live`** runs the **real**
MusicGen worker + real registry on the Windows executor (a real generation, same-seed byte-reproducibility,
and mp3/resample conversion via the real `audio.ingest`).

```powershell
pwsh -NoProfile -File tests\Invoke-GenMusicTests.ps1           # mock gate
pwsh -NoProfile -File tests\Invoke-GenMusicTests.ps1 -Live     # on the Windows executor
```

## Non-goals (this MVP)

Vocals/lyrics (MusicGen is instrumental); melody-conditioned generation (`MusicgenMelody`); batch /
`num_images`-style multi-clip; a warm/persistent pipeline worker; larger MusicGen tiers or Stable Audio;
calibrated/aesthetic confidence; a prompt-safety pass. Each is a documented follow-on (see the work order).
