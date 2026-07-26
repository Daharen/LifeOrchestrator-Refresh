#!/usr/bin/env python
# video_gen_infer.py -- AnimateDiff text-to-video worker for gen.video (Life Orchestrator, Module 25).
#
# Contract with the PowerShell wrapper (Invoke-GenVideo.ps1):
#   argv[1] = path to a JSON args file:
#     { prompt, negative_prompt, num_frames, width, height, steps, guidance, seed, fps,
#       format, base_path, adapter_ckpt, device, dtype, offload, ffmpeg_path,
#       out_video, frames_dir, meta_path }
#   The script loads a diffusers AnimateDiffPipeline (an SD-1.5 base + an AnimateDiff-Lightning MotionAdapter)
#   under the speech venv, generates one short silent clip, writes out_video (MP4 via ffmpeg, or an animated
#   GIF via PIL), and writes meta_path with a JSON result. Only meta_path is authoritative; stdout/stderr are
#   diagnostics (captured to py.log by the wrapper). Exit 0 on success, non-zero on failure (meta_path is
#   written in both cases when possible). If a full-GPU load/generate hits CUDA OOM, it retries once with
#   diffusers model CPU-offload and records which mode was used.
import sys, os, json, time, random, traceback, subprocess, glob


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: video_gen_infer.py <args.json>\n")
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
        os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
        import torch
        import numpy as np
        import diffusers
        from diffusers import AnimateDiffPipeline, MotionAdapter, EulerDiscreteScheduler
        from diffusers.utils import export_to_gif
        from safetensors.torch import load_file

        seed = int(args.get("seed", -1))
        if seed is None or seed < 0:
            seed = random.randint(0, 2**31 - 1)

        base_path = args["base_path"]
        adapter_ckpt = args["adapter_ckpt"]
        device = str(args.get("device", "cuda"))
        dtype_name = str(args.get("dtype", "float16"))
        dtype = getattr(torch, dtype_name, torch.float16)
        num_frames = int(args.get("num_frames", 16))
        width = int(args.get("width", 512))
        height = int(args.get("height", 512))
        steps = int(args.get("steps", 4))
        guidance = float(args.get("guidance", 1.0))
        fps = int(args.get("fps", 8))
        fmt = str(args.get("format", "mp4")).lower()
        prompt = args["prompt"]
        negative = str(args.get("negative_prompt", "") or "")
        want_offload = bool(args.get("offload", False))
        out_video = args["out_video"]
        frames_dir = args.get("frames_dir") or os.path.join(os.path.dirname(out_video), "frames")
        ffmpeg_path = args.get("ffmpeg_path") or "ffmpeg"

        def build(offload):
            adapter = MotionAdapter().to(device, dtype)
            adapter.load_state_dict(load_file(adapter_ckpt, device=device))
            pipe = AnimateDiffPipeline.from_pretrained(
                base_path, motion_adapter=adapter, torch_dtype=dtype,
                variant="fp16", local_files_only=True)
            pipe.scheduler = EulerDiscreteScheduler.from_config(
                pipe.scheduler.config, timestep_spacing="trailing", beta_schedule="linear")
            try:
                pipe.set_progress_bar_config(disable=True)
            except Exception:
                pass
            pipe.enable_vae_slicing()
            if offload:
                pipe.enable_model_cpu_offload()
            else:
                pipe = pipe.to(device)
            return pipe

        def run(pipe):
            try:
                torch.cuda.reset_peak_memory_stats()
            except Exception:
                pass
            g = torch.Generator(device if torch.cuda.is_available() else "cpu").manual_seed(int(seed))
            tg = time.time()
            out = pipe(prompt=prompt, negative_prompt=(negative or None),
                       num_frames=num_frames, guidance_scale=guidance,
                       num_inference_steps=steps, height=height, width=width, generator=g)
            gen_ms = int((time.time() - tg) * 1000)
            return out.frames[0], gen_ms

        # --- load + generate (full GPU first; fall back to CPU-offload on OOM) ---
        tl = time.time()
        offload_used = want_offload
        pipe = build(want_offload)
        load_ms = int((time.time() - tl) * 1000)
        try:
            frames, gen_ms = run(pipe)
        except RuntimeError as e:
            if ("out of memory" in str(e).lower()) and not want_offload:
                sys.stderr.write("full-GPU OOM; retrying with cpu offload\n")
                try:
                    del pipe
                except Exception:
                    pass
                torch.cuda.empty_cache()
                offload_used = True
                tl = time.time()
                pipe = build(True)
                load_ms = int((time.time() - tl) * 1000)
                frames, gen_ms = run(pipe)
            else:
                raise

        # --- quality/motion metrics ---
        arr = np.stack([np.asarray(f) for f in frames]).astype(np.float32)  # (T,H,W,3)
        pixel_std = float(arr.std())
        pixel_mean = float(arr.mean())
        mean_interframe_diff = float(np.mean(np.abs(np.diff(arr, axis=0)))) if arr.shape[0] > 1 else 0.0
        per_frame_std_min = float(min(float(arr[i].std()) for i in range(arr.shape[0])))
        has_nan = bool(np.isnan(arr).any())

        vram_peak = None
        try:
            vram_peak = round(torch.cuda.max_memory_allocated() / (1024 ** 3), 3)
        except Exception:
            pass

        # --- export ---
        codec = None
        if fmt == "gif":
            export_to_gif(frames, out_video)
            codec = "gif"
        else:
            # MP4 via ffmpeg: frames -> PNG -> H.264 yuv420p
            os.makedirs(frames_dir, exist_ok=True)
            for old in glob.glob(os.path.join(frames_dir, "f*.png")):
                try:
                    os.remove(old)
                except Exception:
                    pass
            for i, fr in enumerate(frames):
                fr.save(os.path.join(frames_dir, "f%04d.png" % i))
            cmd = [ffmpeg_path, "-y", "-hide_banner", "-loglevel", "error",
                   "-framerate", str(fps), "-i", os.path.join(frames_dir, "f%04d.png"),
                   "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_video]
            p = subprocess.run(cmd, capture_output=True, text=True)
            if p.returncode != 0 or not os.path.exists(out_video):
                raise RuntimeError("ffmpeg mux failed (rc=%s): %s" % (p.returncode, (p.stderr or "")[:300]))
            codec = "h264"

        duration_s = round(num_frames / float(fps), 4) if fps > 0 else None

        write_meta({
            "ok": True,
            "video_path": out_video, "format": ("gif" if fmt == "gif" else "mp4"), "codec": codec,
            "num_frames": len(frames), "width": width, "height": height, "fps": fps,
            "duration_s": duration_s,
            "pixel_std": round(pixel_std, 4), "pixel_mean": round(pixel_mean, 4),
            "mean_interframe_diff": round(mean_interframe_diff, 4),
            "per_frame_std_min": round(per_frame_std_min, 4),
            "has_nan": has_nan, "nonblank": bool(pixel_std > 5.0),
            "seed": int(seed), "steps": steps, "guidance": guidance,
            "dtype": dtype_name, "device": device, "offload": bool(offload_used),
            "base_path": base_path, "adapter_ckpt": adapter_ckpt,
            "diffusers": diffusers.__version__, "torch": torch.__version__,
            "vram_peak_gb": vram_peak, "load_ms": load_ms, "gen_ms": gen_ms,
            "runtime_ms": int((time.time() - t0) * 1000),
        })
        sys.stdout.write("GEN_OK frames=%d %dx%d seed=%d std=%.2f motion=%.3f offload=%s\n"
                         % (len(frames), width, height, seed, pixel_std, mean_interframe_diff, offload_used))
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
        elif ("does not appear to have a file named" in low) or ("no file named" in low) or ("cannot load" in low) or ("no such file" in low):
            code = "model_load_failed"
        elif "ffmpeg" in low:
            code = "export_failed"
        write_meta({"ok": False, "error_code": code, "error": msg[:600],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
