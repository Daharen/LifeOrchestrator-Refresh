# gen.image — Local Image Generation (Stable Diffusion) · Module 23

Generate one image from a text prompt, entirely on this machine, with a local Stable Diffusion pipeline.
The neural generation counterpart of `image.interpret` (#17, which *reads* an image) and `gen.audio` (#22,
which synthesizes sound). Part of the Phase-A generator set (cheapest-first: `gen.audio → gen.image →
gen.music → gen.video`).

## What it does
Drives the **diffusers `StableDiffusionPipeline`** (fp16, CUDA) through a **Python worker**
(`gen_image_infer.py`, run under the speech venv) with a **meta-file hand-off** to a PowerShell wrapper
(`Invoke-GenImage.ps1`) — the D-0021 pattern from `speech.tts`. The wrapper owns the contract envelope,
registry resolution, confidence, review-queue, and artifacts (all PowerShell); the worker owns model load +
sampling + saving the image + reporting `pixel_std`/dims/timings in a meta JSON the wrapper reads (never the
worker's stdout, so `diffusers`/torch console chatter can't corrupt the parsed result).

- **Models / tiers** (resolved from `models.json`, `type=image-gen`, decoupled from the gateway `wired` gate;
  `-Model <id>` or `-Tier <alias>` selects one, default stays SD 1.5):
  - `image.sd15` (**default**, `-Tier sd15`) — Stable Diffusion 1.5, `StableDiffusionPipeline`, diffusers **fp16**,
    ~2.6 GB VRAM at 512×512. The **fast legacy tier** (CreativeML OpenRAIL-M). Unchanged.
  - `image.sd35-medium` (`-Tier sd35`) — Stable Diffusion 3.5 Medium, `StableDiffusion3Pipeline`, **fp16 +
    model CPU offload + VAE tiling**, T5‑XXL kept CPU-side (offload streams it, never resident); native
    FlowMatchEuler scheduler (the SD1.5 `dpm++/euler` swap does **not** apply). The **higher-quality tier**
    (Stability Community License — free under $1M annual revenue). Turing RTX 2080 Ti is **FP16-only** (no
    bf16/fp8/nf4); the worker's VRAM safety ladder retries **sequential** CPU offload on CUDA OOM. Selected by
    `params.pipeline:"sd3"` in the model entry.
- **determinism:** `mixed` (deterministic orchestration; stochastic sampler, seedable via `-Seed`).
- **parallel_safe:** `false` (binds the CUDA context / VRAM — run one at a time).
- **Review producer (the 8th):** a failed / blank / low-confidence generation appends one
  `verify_generation` item to `review_queue.jsonl` (`flagged_by:"gen.image"`).

## Usage
```powershell
# a basic generation (512x512 PNG, DPM++ 20 steps)
pwsh -NoProfile -File .\Invoke-GenImage.ps1 -Prompt "a cozy reading nook, warm light" -Seed 42

# taller image, more steps, JPEG out
pwsh -NoProfile -File .\Invoke-GenImage.ps1 -Prompt "a lighthouse at dusk" -Width 512 -Height 768 -Steps 25 -Guidance 8 -Format jpg

# SD 3.5 Medium quality tier (1024x1024; lower guidance + more steps suit SD3)
pwsh -NoProfile -File .\Invoke-GenImage.ps1 -Prompt "a coastal town at golden hour, detailed" -Tier sd35 -Width 1024 -Height 1024 -Steps 28 -Guidance 4.5 -Seed 42

# generic InputsJson (any generic caller / the executor / a router)
pwsh -NoProfile -File .\Invoke-GenImage.ps1 -InputsJson '{"prompt":"a small green cactus in a clay pot","negative_prompt":"blurry, lowres","steps":20}'

# through the Module 1 generic wrapper
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"prompt":"a red apple on a table"}'
```

### Inputs
`-Prompt` (required), `-NegativePrompt`, `-Width`/`-Height` (default 512; multiples of 8, 128..1024,
`w*h ≤ 1048576`), `-Steps` (20; 1..150), `-Guidance` (7.5; 0..30), `-Seed` (-1 = random, recorded),
`-Scheduler` (`dpm++`|`euler`|`euler_a`|`ddim`), `-Format` (`png`|`jpg`|`webp`), `-ConfidenceThreshold`
(0.5), `-Model`/`-Tier`; overrides `-Registry`/`-PythonPath`/`-GenInferPath`/`-ReviewQueuePath`.
All inputs are also accepted as `-InputsJson` keys (a named param wins where both are set).

### Output
One `lifeorch.skill.result/0.1` envelope on stdout + artifacts under `runtime/artifacts/<invocation_id>/`:
`image.<png|jpg|webp>`, `gen.json` (machine), `gen.md` (human), `gen_args.json`, `gen_meta.json`, `py.log`,
`stderr.txt`, `result.json`. `result` = `{ input, model, request, image, confidence, review, generation }`.

### Confidence
A documented **generation-completeness / non-blank heuristic** (NOT aesthetic quality, NOT calibrated) from
the image's pixel standard deviation: blank/uniform ≤ 2 → 0.1; very-low-detail < 8 → 0.3; low-detail < 15 →
0.5; has-content ≥ 15 → 0.9. Below `-ConfidenceThreshold` (0.5) the generation is routed to the review queue.

## Requirements
`pwsh ≥ 7.4`; the **speech venv** python (`F:\My_Programs\Local_Computer_Speech_Large_Data\python_env`) with
**diffusers 0.35.2** + torch 2.11+cu128 + transformers + safetensors + numpy + Pillow; the staged
`image.sd15` model on F:; an NVIDIA GPU (RTX 2080 Ti; ~2.6 GB VRAM at 512×512). Runs on the executor.

## Tests
`tests/Invoke-GenImageTests.ps1` — default MOCK mode runs the real wrapper against `tests/mock-worker.py`
(stdlib-only; the cloud pre-ship gate, since a GPU diffusion model can't run on the Linux cloud box); `-Live`
runs the real diffusers worker on the executor (a real SD generation). See the work order for the full list.

## Non-goals / follow-ons
No img2img / inpainting / ControlNet / upscaling / LoRA; no batch / `num_images>1`; no warm/persistent
pipeline worker; no prompt-safety classifier (SD1.5's safety_checker is disabled — it blackout-replaces
images). Each is a documented follow-on. See `WORK_ORDER.md`.

**Named generator follow-ons (each its own GPU-lane wave):**

- **`Z-Image-Turbo Q8`** — the frontier *lead* image pick (bigger quality jump than SD3.5), but it needs the
  `stable-diffusion.cpp` CUDA engine (Diffusers-native only from 0.36.0), i.e. a **new engine + parallel venv**
  — a separate wave, not this Diffusers-native one.
- **SDXL / FLUX.1-schnell** — additional image tiers (FLUX needs offload/quant on 11 GB).
- The other generator upgrades — **#22 audio** (Stable Audio Open / SFX), **#24 music** (ACE-Step), **#25 video**
  (LTX-Video / Wan2.1) — each its own later GPU-lane wave (see the generator-model-leads research).
