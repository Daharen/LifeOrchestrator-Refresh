#!/usr/bin/env python
# music_gen_infer.py -- MusicGen text-to-music worker for gen.music (Life Orchestrator, Module 24).
#
# Contract with the PowerShell wrapper (Invoke-GenMusic.ps1):
#   argv[1] = path to a JSON args file:
#     { prompt, duration, guidance, temperature, top_k, top_p, seed, normalize,
#       model_path, device, dtype, out_wav, meta_path }
#   The script loads the transformers MusicgenForConditionalGeneration under the speech venv, generates one
#   instrumental clip, writes out_wav (32 kHz mono PCM16 via soundfile), and writes meta_path with a JSON
#   result. Only meta_path is authoritative; stdout/stderr are diagnostics (captured to py.log by the
#   wrapper). Exit 0 on success, non-zero on failure (meta_path is written in both cases when possible).
import sys, os, json, time, random, traceback


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: music_gen_infer.py <args.json>\n")
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
        import transformers
        from transformers import AutoProcessor, MusicgenForConditionalGeneration

        # --- resolve the actual seed (record whatever we use) ---
        seed = int(args.get("seed", -1))
        if seed is None or seed < 0:
            seed = random.randint(0, 2**31 - 1)

        model_path = args["model_path"]
        device = str(args.get("device", "cuda:0"))
        dtype_name = str(args.get("dtype", "float32"))
        dtype = getattr(torch, dtype_name, torch.float32)
        duration = float(args.get("duration", 8.0))
        guidance = float(args.get("guidance", 3.0))
        temperature = float(args.get("temperature", 1.0))
        top_k = int(args.get("top_k", 250))
        top_p = float(args.get("top_p", 0.0))
        do_normalize = bool(args.get("normalize", True))
        prompt = args["prompt"]
        out_wav = args["out_wav"]

        # --- load model + processor (offline, from the staged folder) ---
        tl = time.time()
        model = MusicgenForConditionalGeneration.from_pretrained(
            model_path, torch_dtype=dtype, local_files_only=True)
        model = model.to(device)
        model.eval()
        processor = AutoProcessor.from_pretrained(model_path, local_files_only=True)
        sr = int(model.config.audio_encoder.sampling_rate)
        try:
            frame_rate = float(model.config.audio_encoder.frame_rate)
        except Exception:
            frame_rate = 50.0
        if not frame_rate or frame_rate <= 0:
            frame_rate = 50.0
        load_ms = int((time.time() - tl) * 1000)

        # --- tokens from duration (bounded; MusicGen Small trained up to 30 s) ---
        max_new_tokens = int(round(duration * frame_rate))
        max_new_tokens = max(8, min(max_new_tokens, int(round(30.0 * frame_rate))))

        # --- generate ---
        inputs = processor(text=[prompt], padding=True, return_tensors="pt").to(device)
        gen_kw = dict(max_new_tokens=max_new_tokens, guidance_scale=guidance)
        if temperature and temperature > 0:
            gen_kw["do_sample"] = True
            gen_kw["temperature"] = float(temperature)
            if top_k and top_k > 0:
                gen_kw["top_k"] = int(top_k)
            if top_p and top_p > 0:
                gen_kw["top_p"] = float(top_p)
        else:
            gen_kw["do_sample"] = False

        try:
            torch.cuda.reset_peak_memory_stats()
        except Exception:
            pass
        torch.manual_seed(int(seed))
        tg = time.time()
        with torch.no_grad():
            audio = model.generate(**inputs, **gen_kw)
        gen_ms = int((time.time() - tg) * 1000)

        arr = audio[0, 0].detach().float().cpu().numpy()

        # --- peak-normalize to avoid PCM clipping (MusicGen can exceed +-1.0) ---
        peak_raw = float(np.max(np.abs(arr))) if arr.size else 0.0
        normalized = False
        if do_normalize and peak_raw > 0.99:
            arr = arr * (0.99 / peak_raw)
            normalized = True
        peak_final = float(np.max(np.abs(arr))) if arr.size else 0.0
        rms = float(np.sqrt(np.mean(arr ** 2))) if arr.size else 0.0
        has_nan = bool(np.isnan(arr).any())

        # --- save 32 kHz mono PCM16 WAV ---
        import soundfile as sf
        sf.write(out_wav, arr.astype("float32"), sr, subtype="PCM_16")

        vram_peak = None
        try:
            vram_peak = round(torch.cuda.max_memory_allocated() / (1024 ** 3), 3)
        except Exception:
            pass

        write_meta({
            "ok": True,
            "audio_path": out_wav, "sr": sr, "frame_rate": frame_rate,
            "samples": int(arr.shape[0]), "duration_s": round(len(arr) / float(sr), 4),
            "rms": round(rms, 6), "peak_raw": round(peak_raw, 6), "peak_final": round(peak_final, 6),
            "normalized": normalized, "has_nan": has_nan,
            "seed": int(seed), "max_new_tokens": max_new_tokens,
            "guidance": guidance, "temperature": temperature, "top_k": top_k, "top_p": top_p,
            "dtype": dtype_name, "device": device,
            "model_path": model_path, "transformers": transformers.__version__, "torch": torch.__version__,
            "vram_peak_gb": vram_peak, "load_ms": load_ms, "gen_ms": gen_ms,
            "runtime_ms": int((time.time() - t0) * 1000),
        })
        sys.stdout.write("GEN_OK %.2fs sr=%d seed=%d rms=%.4f\n" % (len(arr) / float(sr), sr, seed, rms))
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
