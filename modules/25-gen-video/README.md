# gen.video — Local Video Generation (Module 25)

Turn a text prompt into one short **silent video clip** with a local **AnimateDiff** pipeline, entirely on
this machine. `gen.video` is the fourth and last generator in the Phase-A generator track
(`gen.audio` #22 procedural sound → `gen.image` #23 neural images → `gen.music` #24 neural music →
**`gen.video` #25**), and the third **neural** generator. It is the motion sibling of `gen.image` (neural
stills) — same base model, now animated.

## What it does

Given a `-Prompt` (a text description like *"a drone shot over a misty forest at sunrise"*), it drives a
diffusers **`AnimateDiffPipeline`** — the **Stable Diffusion 1.5** base (reused from `gen.image` #23) plus an
**AnimateDiff-Lightning** temporal MotionAdapter (4-step, fp16) — on the GPU and produces one short clip of
`-NumFrames` frames at `-Width`×`-Height`. The clip is encoded to an **MP4** (H.264, via the present `ffmpeg`)
or an animated **GIF** (via Pillow).

- **Deterministic-seedable** — a fixed `-Seed >= 0` is byte-reproducible on this GPU (`torch.Generator`);
  `-Seed -1` (default) picks a random seed and records the actual value used.
- **Confidence + review** — populates a `confidence` (a generation-completeness / non-blank **and non-static**
  heuristic from the frame pixel std and the mean inter-frame difference, **not** aesthetic quality) and routes
  blank / static / failed / low-confidence generations to the canonical review queue as the **tenth** producer
  (`flagged_by:"gen.video"`, `requested:"verify_generation"`).
- **Fits the 11 GB GPU** — the default 16-frame 512×512 clip peaks **~4.75 GB VRAM** full-GPU (no offload).
  The worker keeps a CUDA-OOM → diffusers CPU-offload auto-retry as a safety valve; `-Offload $true` forces it.

## Architecture (D-0036, following the D-0021 / D-0034 / D-0035 worker+meta pattern)

```
Invoke-GenVideo.ps1  (PowerShell wrapper: contract envelope, validation, registry resolution,
        │                confidence + review-queue producer, ffmpeg resolution)
        │  spawns (child process)               reads meta file (never stdout)
        ▼                                        ▲
video_gen_infer.py  (Python worker under the speech venv: loads the AnimateDiffPipeline on CUDA,
                     generates frames, writes video.mp4 via ffmpeg / video.gif via Pillow + gen_meta.json)
```

The wrapper owns the `lifeorch.skill.result/0.1` envelope (like every skill); the model lives in its native
Python. The **meta-file hand-off** means diffusers/torch console chatter can never corrupt the parsed result.
The model is resolved from the shared registry (`modules/07-model-gateway/models.json`, `type=video-gen`,
`engine=diffusers`) and is **decoupled from the gateway `wired` gate** (the gateway runs `type=llm` only) —
exactly as `speech.tts` / `image.interpret` / `gen.image` / `gen.music` do.

## Model

`video.animatediff-lightning` — **AnimateDiff-Lightning 4-step** (`ByteDance/AnimateDiff-Lightning`,
`animatediff_lightning_4step_diffusers.safetensors`, ~907 MB, **CreativeML-OpenRAIL-M**) staged to
`F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\25-gen-video\animatediff-lightning\`, run on top of the
**Stable Diffusion 1.5** base already staged for `gen.image` (`F:\...\23-gen-image\stable-diffusion-v1-5\`,
fp16). Uses **no new library** — diffusers 0.35.2 (already in the speech venv) ships `AnimateDiffPipeline` +
`MotionAdapter`. Loads fp16, ~4.75 GB VRAM peak on the RTX 2080 Ti, ~57 s warm for a 16-frame 512² clip. The
license is OpenRAIL-M (local generation permitted with behavioral-use restrictions; the same license as the
SD 1.5 base, precedented by `gen.image` D-0034). Larger/longer tiers (AnimateDiff full 25-step, SVD image-to-
video, CogVideoX/LTX on future bf16 hardware) are documented follow-ons.

## Inputs

| param | default | notes |
|-------|---------|-------|
| `-Prompt` | *(required)* | text description of the clip |
| `-NegativePrompt` | `bad quality, worst quality, low resolution, blurry` | what to avoid |
| `-NumFrames` | `16` | frames, 2..64 (AnimateDiff is trained around 16) |
| `-Width` / `-Height` | `512` / `512` | multiple of 8, 128..1024 (SD 1.5 is trained at 512) |
| `-Steps` | `4` | denoising steps, 1..12 (Lightning is 4/8-step) |
| `-Guidance` | `1.0` | classifier-free guidance, 0..15 (Lightning uses ~1.0) |
| `-Fps` | `8` | playback fps, 1..30 (duration_s = num_frames / fps) |
| `-Seed` | `-1` | -1 = random (recorded); ≥0 = byte-reproducible |
| `-Format` | `mp4` | `mp4` (H.264 via ffmpeg) \| `gif` (via Pillow) |
| `-Offload` | `$false` | force diffusers CPU-offload (lower VRAM, slower) |
| `-ConfidenceThreshold` | `0.5` | below this → review queue |
| `-Model` / `-Tier` | `video.animatediff-lightning` / `lightning` | registry `type=video-gen` |

Also accepts a single `-InputsJson '<json>'` (contract §3.1) and `-ArtifactRoot` / `-InvocationId`.

## Output

One `lifeorch.skill.result/0.1` envelope on stdout; artifacts in `runtime/artifacts/<invocation_id>/`:
`video.<mp4|gif>` (the clip), `gen.json` (machine record), `gen.md` (human card), plus `result.json`,
`gen_args.json`, `gen_meta.json`, `py.log`, `stderr.txt`, and (for mp4) a transient `frames/` dir of PNGs.
`result.video` carries the path, format, codec, width, height, num_frames, fps, duration_s, bytes, sha256;
`result.motion` carries `mean_abs_interframe_diff`, `per_frame_std_min`, and `pixel_std`.

## Flags

`determinism: mixed` · `parallel_safe: false` (binds the CUDA context / VRAM) · `batch: false` ·
`streaming: false`. **Tenth review-queue producer** (7/8/11/12/14/16/17/23/24/**25**).

## Tests

`tests/Invoke-GenVideoTests.ps1` — **MOCK mode** (default) runs the **real** `Invoke-GenVideo.ps1` against
`tests/mock-worker.py` (stdlib, no torch/diffusers/ffmpeg) so the full validation / confidence / review /
envelope path runs on the cloud Linux box before any bytes ship; **`-Live`** runs the **real** AnimateDiff
worker + real registry on the Windows executor (a real generation, same-seed byte-reproducibility, MP4 magic
and VRAM fit, plus a GIF-format run).

```powershell
pwsh -NoProfile -File tests\Invoke-GenVideoTests.ps1           # mock gate
pwsh -NoProfile -File tests\Invoke-GenVideoTests.ps1 -Live     # on the Windows executor
```

## Non-goals (this MVP)

Image-to-video / video-to-video; ControlNet / motion-LoRA conditioning; frame interpolation / upscaling;
longer clips via sliding-window continuation; audio tracks / lip-sync; batch / multi-clip; a warm/persistent
pipeline worker; larger tiers (AnimateDiff full, SVD, CogVideoX/LTX); calibrated / motion-quality confidence; a
prompt-safety pass. Each is a documented follow-on (see the work order).
