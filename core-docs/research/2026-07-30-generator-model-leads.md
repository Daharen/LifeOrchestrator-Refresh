# Frontier research -- local generator model leads (audio / image / music / video) for #22-#25

**Provenance:** couriered frontier answer, iteration 15, frontier.bridge pack `cc96c95a` (prompt-only;
GPT-5.x via ChatGPT, couriered back by Nicholas 2026-07-30; captured `read-return` valid, 21,536 chars).
This is a faithful DIGEST (every actionable lead preserved). It CLOSES the standing TBD from the
2026-07-28 report (that report covered the LLM tier only; generator leads were deferred). These are
CANDIDATES to fold into the generator modules, NOT yet installed -- staging/wiring is a follow-on wave.

## Fixed constraints the picks honor
RTX 2080 Ti 11 GB, Turing cc7.5 -- **FP16 only** (no BF16 / FP8 / NF4-with-BF16 / MXFP4 / NVFP4 tensor ops);
one large generator resident at a time; CPU offload + VAE tiling where noted; figures are conservative
engineering estimates for this card, NOT measured here. "Fits" via aggressive offload != practical.

## Executive picks (lead / runner-up per module)

| Module | Lead | Runner-up |
|---|---|---|
| **#23 image** | **Z-Image-Turbo Q8_0 GGUF** (~8.5-10.5 GB; Apache-2.0) | **SD 3.5 Medium FP16** (Diffusers-native) |
| **#24 music** | **ACE-Step 1.5 Turbo 2B + 1.7B planner** (MIT) | **Stable Audio 3 Small Music** |
| **#25 video** | **LTX-Video 2B 0.9.8 Distilled FP16** | **Wan2.1 T2V 1.3B** (Diffusers-native, Apache-2.0) |
| **#22 neural audio/SFX** | **Stable Audio 3 Small SFX** | **Stable Audio Open 1.0** (Diffusers-native) |

**Diffusers-0.35.2-native (no new engine):** SD 3.5 Medium, Wan2.1 1.3B, Stable Audio Open 1.0.
**Need a new engine/env:** Z-Image (leejet `stable-diffusion.cpp` CUDA, or ComfyUI-GGUF), ACE-Step (own
runtime), Stable Audio 3 Small (Stability `stable-audio-3` / `stable-audio-tools`), LTX-Video (official repo
/ ComfyUI-LTXVideo). Run new stacks in a PARALLEL venv so they don't collide with the speech venv.

## #23 gen.image (incumbent SD1.5, ~2.6 GB)
- **Lead -- Z-Image-Turbo Q8_0 GGUF** (`leejet/Z-Image-Turbo-GGUF`, 6.58 GB) + `Qwen3-4B-Instruct-2507-Q4_K_M`
  encoder (`unsloth/...`, ~2.5-2.8 GB) + FLUX `ae.safetensors` VAE (`black-forest-labs/FLUX.1-schnell`).
  Engine `stable-diffusion.cpp` (CUDA; Diffusers native support only from 0.36.0 -> invoke as an external
  CLI/service, NOT forced into the 0.35.2 venv). 8 forwards, CFG~1.0. **~8.5-10.5 GB** @1024 with offload
  (Q6_K ~5.26 GB / Q5_0 ~4.54 GB fallbacks). ~12-30 s @768, ~25-60 s @1024. **Apache-2.0** (local+commercial
  OK). Very large quality jump over SD1.5 (photorealism, prompt adherence, text rendering).
- **Runner-up -- SD 3.5 Medium FP16** (`stabilityai/stable-diffusion-3.5-medium`): **Diffusers-native**
  (fp16 + model CPU offload + VAE tiling; keep T5-XXL on CPU; do NOT use the BF16/NF4 card recipe on Turing).
  ~8-10.5 GB @1024; ~14-16 GB disk full (~6-7 GB without T5-XXL). Stability Community License (free < $1M
  rev). Cleanest drop-in upgrade if staying inside the existing venv matters more than max quality.

## #24 gen.music (incumbent MusicGen-Small, ~2.4 GB, instrumental 1-30 s)
- **Lead -- ACE-Step 1.5 Turbo 2B + 1.7B planner** (`ACE-Step/Ace-Step1.5`; subdirs `acestep-v15-turbo` +
  `acestep-5Hz-lm-1.7B`). Keep the planner on CPU (DiT-on-GPU ~5.5-7.5 GB; both resident ~9-10.5 GB = too
  tight). ~9-11 GB disk. **MIT.** Song-scale structure, vocals+lyrics, BPM/key/time-sig, up to 10 min; ~20-45 s
  for a 2-4 min song. NOT a native Diffusers pipeline (own runtime, separate env). Do NOT install the XL 4B
  decoder (12 GB min). Transformational vs MusicGen-Small.
- **Runner-up -- Stable Audio 3 Small Music** (`stabilityai/stable-audio-3-small-music`): ~2.5-3.5 GB, 8 steps,
  up to 120 s, 44.1 kHz stereo; ~2-10 s to generate. Stability Community + Gemma terms. Fast cue/bed generator;
  shares the SAME-S autoencoder + T5Gemma with the SFX model (cheap swap).

## #25 gen.video (incumbent AnimateDiff-Lightning on SD1.5, ~4.75 GB, ~2 s silent)
- **Lead -- LTX-Video 2B 0.9.8 Distilled FP16** (`Lightricks/LTX-Video`, file
  `ltxv-2b-0.9.8-distilled.safetensors`; T5-XXL 8-bit `Lightricks/T5-XXL-8bit`). Draft 512x288/49f, better
  768x448/65-97f; VAE tiling mandatory near the top; text encoder 8-bit/CPU. ~8.5-10.5 GB; ~10-12 GB disk.
  ~1-3 min draft / 3-8 min better. **LTX custom license** (local/private OK; commercial >= $10M rev needs a
  license). Use the official repo / ComfyUI-LTXVideo, NOT a guaranteed 0.35.2 drop-in. Big jump vs AnimateDiff.
- **Runner-up -- Wan2.1 T2V 1.3B FP16** (`Wan-AI/Wan2.1-T2V-1.3B-Diffusers`): **Diffusers-native**
  (`WanPipeline`; 0.35.2 has the Wan/LTX fixes), 480p ~5 s clips, official req 8.19 GB (~9-10.5 GB w/
  workspace); ~14-18 GB disk. **Apache-2.0.** But ~12-25 min per 5 s clip on this card -> high-patience only.

## #22 gen.audio (incumbent: ffmpeg synthetic signals -- NO neural model)
- **Lead -- Stable Audio 3 Small SFX** (`stabilityai/stable-audio-3-small-sfx`): FP16, 8 steps, up to 120 s,
  44.1 kHz stereo; **~2.5-3.5 GB**; ~1-10 s to generate; ~4.5-6.5 GB disk. Stability Community + Gemma terms.
  Foley/impacts/machinery/ambience/creature/UI SFX; text-to-audio + edit/inpaint/continue. New capability, not
  an upgrade. Official `stable-audio-3` / `stable-audio-tools` (not native to 0.35.2). Keep FFmpeg synthesis
  for deterministic alerts / exact-frequency tones.
- **Runner-up -- Stable Audio Open 1.0 FP16** (`stabilityai/stable-audio-open-1.0`): **Diffusers-native**
  (`StableAudioPipeline`), ~5.5-7.5 GB, up to 47 s, 44.1 kHz stereo; ~30-180 s to generate. CC-trained.
  Compatibility fallback inside the existing venv.

## Residency + backbone notes
- **Keep resident: Stable Audio 3 Small SFX** -- small (~2.5-3.5 GB), interactive latency, most opportunistic;
  its T5Gemma + SAME-S autoencoder are reused by Small Music (cheapest high-value swap); may even coexist with
  the resident 9B LLM (measure). Everything else = load-on-demand, evict SFX before loading a big generator.
- No cheap SD-backbone sharing among the quality picks (Z-Image / SD3.5 / LTX / Wan each bring their own
  transformer + VAE). Keep SD1.5 + AnimateDiff-Lightning as the FAST LEGACY tier alongside the upgrades.
- **Not selected:** ACE-Step XL 4B (12 GB min); FLUX.2 Klein 4B (~13 GB, post-0.35.2); Stable Audio 3 Medium
  (Turing-unfriendly attention path); Wan2.2 5B / HunyuanVideo 1.5 / 8B-14B video (render times/assumptions
  poor on a 2080 Ti); any FP8 checkpoint (Turing has no native FP8 -> no speedup, possible unsupported kernels).

## Suggested implementation order (frontier's)
1) Stable Audio 3 Small SFX (least integration/HW risk; gives #22 a neural path). 2) Z-Image-Turbo Q8 via
stable-diffusion.cpp (largest practical image gain). 3) ACE-Step 1.5 Turbo + CPU planner (music). 4) LTX-Video
2B Distilled (video). 5) Stable Audio 3 Small Music. 6) SD3.5 Medium (Diffusers fallback). 7) Wan2.1 1.3B
(slow video). 8) Stable Audio Open 1.0 (Diffusers audio fallback).

## Orchestrator's read (folded)
Unblocks the generator-upgrade follow-ons (`MODULE_ROADMAP` #22-#25). Each upgrade is a GPU-lane wave (model +
VRAM live-verify) and MOST need a new engine/venv -- so each is `parallel_safe:false` and NOT a CPU-lane unit.
The three Diffusers-native picks (SD3.5 Medium, Wan2.1 1.3B, Stable Audio Open 1.0) are the lowest-integration
starting points; the leads (Z-Image, ACE-Step, Stable Audio 3, LTX) each need a parallel venv + a new engine.
Licenses: Z-Image/ACE-Step/Wan permissive (Apache/MIT); LTX + the Stability models allow local private use but
carry revenue thresholds -- preserve those if this ever becomes a commercial distributed product.
