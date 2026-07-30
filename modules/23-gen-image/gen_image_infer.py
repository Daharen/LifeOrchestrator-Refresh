#!/usr/bin/env python
# gen_image_infer.py -- Stable Diffusion text-to-image worker for gen.image (Life Orchestrator, Module 23).
#
# Two pipeline families, selected by args["pipeline_family"] (default "sd"):
#   "sd"  -> diffusers StableDiffusionPipeline  (SD 1.5 legacy FAST tier -- unchanged path).
#   "sd3" -> diffusers StableDiffusion3Pipeline (SD 3.5 Medium fp16 QUALITY tier). fp16 + model CPU offload
#           + VAE tiling; T5-XXL text encoder stays CPU-side (offload hooks stream it, never resident);
#           native FlowMatchEuler scheduler (the SD1.5 dpm++/euler swap does NOT apply to SD3). On an
#           11 GB Turing card VRAM is tight, so a safety ladder retries with sequential CPU offload on OOM.
#
# Contract with the PowerShell wrapper (Invoke-GenImage.ps1):
#   argv[1] = path to a JSON args file:
#     { prompt, negative_prompt, width, height, steps, guidance, seed, scheduler,
#       model_path, device, dtype, variant, format, out_image, meta_path,
#       pipeline_family, offload, vae_tiling, drop_t5 }
#   The script loads the pipeline under the speech venv, generates one image, writes out_image, and writes
#   meta_path with a JSON result. Only meta_path is authoritative; stdout/stderr are diagnostics (captured to
#   py.log by the wrapper). Exit 0 on success, non-zero on failure (meta_path is written in both cases when
#   possible). All meta values are plain JSON-serializable scalars (the JSON-serializable-meta rule).
import sys, os, json, time, random, traceback


def _reset_peak():
    try:
        import torch
        torch.cuda.reset_peak_memory_stats()
    except Exception:
        pass


def _vram_peak_gb():
    try:
        import torch
        return round(torch.cuda.max_memory_allocated() / (1024 ** 3), 3)
    except Exception:
        return None


def _free_cuda():
    try:
        import gc, torch
        gc.collect()
        torch.cuda.empty_cache()
    except Exception:
        pass


def _is_oom(e):
    low = repr(e).lower()
    return ("out of memory" in low) or ("cuda" in low and "memory" in low) or ("cublas" in low and "alloc" in low)


def run_sd(torch, model_path, device, dtype, variant, sched_name, width, height,
           steps, guidance, prompt, negative, seed):
    """SD 1.5 legacy path (StableDiffusionPipeline). Behavior identical to the original worker."""
    from diffusers import StableDiffusionPipeline
    tl = time.time()
    kw = dict(torch_dtype=dtype, safety_checker=None, requires_safety_checker=False, local_files_only=True)
    if variant:
        kw["variant"] = variant
    try:
        pipe = StableDiffusionPipeline.from_pretrained(model_path, **kw)
    except Exception:
        if variant:
            kw.pop("variant", None)
            pipe = StableDiffusionPipeline.from_pretrained(model_path, **kw)
            variant = None
        else:
            raise

    from diffusers import (DPMSolverMultistepScheduler, EulerDiscreteScheduler,
                           EulerAncestralDiscreteScheduler, DDIMScheduler)
    sched_map = {
        "dpm++": DPMSolverMultistepScheduler,
        "euler": EulerDiscreteScheduler,
        "euler_a": EulerAncestralDiscreteScheduler,
        "ddim": DDIMScheduler,
    }
    sched_cls = sched_map.get(sched_name, DPMSolverMultistepScheduler)
    pipe.scheduler = sched_cls.from_config(pipe.scheduler.config)

    pipe = pipe.to(device)
    pipe.set_progress_bar_config(disable=True)
    try:
        pipe.enable_attention_slicing()
        pipe.enable_vae_slicing()
    except Exception:
        pass
    load_ms = int((time.time() - tl) * 1000)

    gen_dev = "cuda" if str(device).startswith("cuda") else "cpu"
    generator = torch.Generator(device=gen_dev).manual_seed(int(seed))
    _reset_peak()
    tg = time.time()
    out = pipe(prompt=prompt, negative_prompt=negative,
               num_inference_steps=steps, guidance_scale=guidance,
               width=width, height=height, generator=generator)
    img = out.images[0]
    gen_ms = int((time.time() - tg) * 1000)
    info = {"pipeline_family": "sd", "scheduler": sched_name, "variant": variant,
            "offload": None, "t5": None}
    return img, load_ms, gen_ms, info


def _build_sd3(torch, model_path, dtype, drop_t5, offload, vae_tiling):
    """Build an SD3 pipeline with the requested VRAM strategy. Never calls .to(cuda) when offloading."""
    from diffusers import StableDiffusion3Pipeline
    kw = dict(torch_dtype=dtype, local_files_only=True)
    if drop_t5:
        # SD3 runs on the two CLIP encoders alone -- lower fidelity, much smaller VRAM/RAM footprint.
        kw["text_encoder_3"] = None
        kw["tokenizer_3"] = None
    pipe = StableDiffusion3Pipeline.from_pretrained(model_path, **kw)
    pipe.set_progress_bar_config(disable=True)
    if vae_tiling:
        try:
            pipe.enable_vae_tiling()
        except Exception:
            pass
    if offload == "sequential":
        # submodule-level streaming: lowest peak VRAM, slowest; guarantees the fit on an 11 GB card.
        pipe.enable_sequential_cpu_offload()
    elif offload in (None, "", "none"):
        pipe = pipe.to("cuda:0")
    else:  # "model" (default): one component resident at a time; T5-XXL stays CPU-side except while encoding.
        pipe.enable_model_cpu_offload()
    return pipe


def run_sd3(torch, model_path, device, dtype, width, height, steps, guidance,
            prompt, negative, offload, vae_tiling, drop_t5, seed):
    """SD 3.5 Medium path. fp16 + CPU offload + VAE tiling, with an OOM safety ladder.
       Latents seeded via a CPU generator so the seed is byte-reproducible regardless of offload mode."""
    first = (offload or "model")
    ladder = [first]
    if first != "sequential":
        ladder.append("sequential")  # last-resort fit if the faster mode OOMs on this card
    last_exc = None
    for i, mode in enumerate(ladder):
        try:
            _free_cuda()
            _reset_peak()
            tl = time.time()
            pipe = _build_sd3(torch, model_path, dtype, drop_t5, mode, vae_tiling)
            load_ms = int((time.time() - tl) * 1000)
            generator = torch.Generator(device="cpu").manual_seed(int(seed))
            tg = time.time()
            out = pipe(prompt=prompt, negative_prompt=(negative or None),
                       num_inference_steps=steps, guidance_scale=guidance,
                       width=width, height=height, generator=generator)
            img = out.images[0]
            gen_ms = int((time.time() - tg) * 1000)
            info = {"pipeline_family": "sd3", "scheduler": "flow_match_euler", "variant": None,
                    "offload": mode, "t5": ("dropped" if drop_t5 else "cpu_offload")}
            try:
                del pipe
            except Exception:
                pass
            return img, load_ms, gen_ms, info
        except Exception as e:
            last_exc = e
            _free_cuda()
            if _is_oom(e) and i < len(ladder) - 1:
                sys.stderr.write("sd3 OOM on offload=%s -> retrying offload=%s\n" % (mode, ladder[i + 1]))
                continue
            raise
    raise last_exc


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: gen_image_infer.py <args.json>\n")
        return 2
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            args = json.load(f)
    except Exception as e:
        sys.stderr.write("could not read args file: %r\n" % (e,))
        return 2

    meta_path = args.get("meta_path")

    def write_meta(d):
        if not meta_path:
            return
        try:
            with open(meta_path, "w", encoding="utf-8") as f:
                json.dump(d, f)
        except Exception as e:
            sys.stderr.write("meta write failed: %r\n" % (e,))

    t0 = time.time()
    try:
        os.environ.setdefault("HF_HUB_OFFLINE", "1")
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
        os.environ.setdefault("DIFFUSERS_VERBOSITY", "error")
        import torch
        import numpy as np
        import diffusers

        # --- resolve the actual seed (record whatever we use) ---
        seed = int(args.get("seed", -1))
        if seed is None or seed < 0:
            seed = random.randint(0, 2 ** 31 - 1)

        model_path = args["model_path"]
        device = str(args.get("device", "cuda:0"))
        dtype_name = str(args.get("dtype", "float16"))
        dtype = getattr(torch, dtype_name, torch.float16)
        variant = args.get("variant") or None
        sched_name = str(args.get("scheduler", "dpm++")).lower()
        width = int(args.get("width", 512))
        height = int(args.get("height", 512))
        steps = int(args.get("steps", 20))
        guidance = float(args.get("guidance", 7.5))
        fmt = str(args.get("format", "png")).lower()
        prompt = args["prompt"]
        negative = args.get("negative_prompt") or None

        family = str(args.get("pipeline_family", "sd")).lower()
        offload = args.get("offload")
        vae_tiling = bool(args.get("vae_tiling", False))
        drop_t5 = bool(args.get("drop_t5", False))

        if family == "sd3":
            img, load_ms, gen_ms, info = run_sd3(
                torch, model_path, device, dtype, width, height, steps, guidance,
                prompt, negative, offload, vae_tiling, drop_t5, seed)
        else:
            img, load_ms, gen_ms, info = run_sd(
                torch, model_path, device, dtype, variant, sched_name, width, height,
                steps, guidance, prompt, negative, seed)

        # --- save ---
        out_image = args["out_image"]
        save_fmt = {"png": "PNG", "jpg": "JPEG", "jpeg": "JPEG", "webp": "WEBP"}.get(fmt, "PNG")
        save_img = img
        if save_fmt == "JPEG" and img.mode != "RGB":
            save_img = img.convert("RGB")
        save_img.save(out_image, format=save_fmt)

        # --- non-blank signal (numpy std/mean over RGB) ---
        arr = np.asarray(img.convert("RGB")).astype("float32")
        pixel_std = float(arr.std())
        pixel_mean = float(arr.mean())

        vram_peak = _vram_peak_gb()

        write_meta({
            "ok": True,
            "image_path": out_image, "format": fmt,
            "width": int(img.size[0]), "height": int(img.size[1]), "mode": img.mode,
            "image_bytes": os.path.getsize(out_image),
            "seed": int(seed), "steps": steps, "guidance": guidance,
            "scheduler": info.get("scheduler", sched_name),
            "pipeline_family": info.get("pipeline_family", family),
            "offload": info.get("offload"), "t5": info.get("t5"),
            "pixel_std": round(pixel_std, 3), "pixel_mean": round(pixel_mean, 3),
            "dtype": dtype_name, "variant": info.get("variant", variant), "device": device,
            "model_path": model_path, "diffusers": diffusers.__version__, "torch": torch.__version__,
            "vram_peak_gb": vram_peak, "load_ms": load_ms, "gen_ms": gen_ms,
            "runtime_ms": int((time.time() - t0) * 1000),
        })
        sys.stdout.write("GEN_OK %s %dx%d seed=%d std=%.2f offload=%s\n"
                         % (info.get("pipeline_family", family), img.size[0], img.size[1],
                            seed, pixel_std, info.get("offload")))
        return 0
    except Exception as e:
        tb = traceback.format_exc()
        sys.stderr.write(tb + "\n")
        msg = repr(e)
        low = msg.lower()
        code = "generation_failed"
        if ("out of memory" in low) or ("cuda" in low and "memory" in low):
            code = "gpu_oom"
        elif ("no module named" in low) or ("modulenotfound" in low):
            code = "env_error"
        elif ("does not appear to have a file named" in low) or ("cannot load" in low) or ("no such file" in low):
            code = "model_load_failed"
        write_meta({"ok": False, "error_code": code, "error": msg[:600],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
