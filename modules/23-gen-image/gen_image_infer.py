#!/usr/bin/env python
# gen_image_infer.py -- Stable Diffusion text-to-image worker for gen.image (Life Orchestrator, Module 23).
#
# Contract with the PowerShell wrapper (Invoke-GenImage.ps1):
#   argv[1] = path to a JSON args file:
#     { prompt, negative_prompt, width, height, steps, guidance, seed, scheduler,
#       model_path, device, dtype, variant, format, out_image, meta_path }
#   The script loads the diffusers StableDiffusionPipeline under the speech venv, generates one image,
#   writes out_image, and writes meta_path with a JSON result. Only meta_path is authoritative; stdout/stderr
#   are diagnostics (captured to py.log by the wrapper). Exit 0 on success, non-zero on failure (meta_path is
#   written in both cases when possible).
import sys, os, json, time, random, traceback


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
        from diffusers import StableDiffusionPipeline

        # --- resolve the actual seed (record whatever we use) ---
        seed = int(args.get("seed", -1))
        if seed is None or seed < 0:
            seed = random.randint(0, 2**31 - 1)

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

        # --- load pipeline (offline, from the staged folder) ---
        tl = time.time()
        kw = dict(torch_dtype=dtype, safety_checker=None,
                  requires_safety_checker=False, local_files_only=True)
        if variant:
            kw["variant"] = variant
        try:
            pipe = StableDiffusionPipeline.from_pretrained(model_path, **kw)
        except Exception as e:
            # a missing fp16 variant is the most likely load fault -> retry without variant
            if variant:
                kw.pop("variant", None)
                pipe = StableDiffusionPipeline.from_pretrained(model_path, **kw)
                variant = None
            else:
                raise

        # --- scheduler selection ---
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

        # --- generate ---
        gen_dev = "cuda" if str(device).startswith("cuda") else "cpu"
        generator = torch.Generator(device=gen_dev).manual_seed(int(seed))
        try:
            torch.cuda.reset_peak_memory_stats()
        except Exception:
            pass
        tg = time.time()
        out = pipe(prompt=prompt, negative_prompt=negative,
                   num_inference_steps=steps, guidance_scale=guidance,
                   width=width, height=height, generator=generator)
        img = out.images[0]
        gen_ms = int((time.time() - tg) * 1000)

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

        vram_peak = None
        try:
            vram_peak = round(torch.cuda.max_memory_allocated() / (1024**3), 3)
        except Exception:
            pass

        write_meta({
            "ok": True,
            "image_path": out_image, "format": fmt,
            "width": int(img.size[0]), "height": int(img.size[1]), "mode": img.mode,
            "image_bytes": os.path.getsize(out_image),
            "seed": int(seed), "steps": steps, "guidance": guidance, "scheduler": sched_name,
            "pixel_std": round(pixel_std, 3), "pixel_mean": round(pixel_mean, 3),
            "dtype": dtype_name, "variant": variant, "device": device,
            "model_path": model_path, "diffusers": diffusers.__version__, "torch": torch.__version__,
            "vram_peak_gb": vram_peak, "load_ms": load_ms, "gen_ms": gen_ms,
            "runtime_ms": int((time.time() - t0) * 1000),
        })
        sys.stdout.write("GEN_OK %dx%d seed=%d std=%.2f\n" % (img.size[0], img.size[1], seed, pixel_std))
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
