#!/usr/bin/env python
# tts_infer.py — Qwen3-TTS CustomVoice inference worker for speech.tts (Life Orchestrator, Module 12).
#
# Contract with the PowerShell wrapper (Invoke-SpeechTts.ps1):
#   argv[1] = path to a JSON args file:
#     { text, speaker, language, instruct, model_path, device, dtype, attn, seed,
#       max_new_tokens, out_wav, meta_path }
#   The script loads the model under the speech venv, synthesizes one utterance, writes out_wav
#   (24 kHz mono PCM16 WAV), and writes meta_path with a JSON result. Only meta_path is authoritative;
#   stdout/stderr are diagnostics (captured to py.log by the wrapper). Exit 0 on success, non-zero on failure
#   (meta_path is written in both cases when possible).
import sys, os, json, time, traceback


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: tts_infer.py <args.json>\n")
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
        import torch
        import numpy as np
        import soundfile as sf
        from qwen_tts import Qwen3TTSModel

        seed = int(args.get("seed", -1))
        if seed is not None and seed >= 0:
            torch.manual_seed(seed)
            try:
                torch.cuda.manual_seed_all(seed)
            except Exception:
                pass

        dtype_name = str(args.get("dtype", "bfloat16"))
        dtype = getattr(torch, dtype_name, torch.bfloat16)
        attn = str(args.get("attn", "sdpa"))
        device = str(args.get("device", "cuda:0"))
        model_path = args["model_path"]

        model = Qwen3TTSModel.from_pretrained(
            model_path, device_map=device, dtype=dtype, attn_implementation=attn
        )

        gkw = {}
        mnt = args.get("max_new_tokens")
        if mnt:
            gkw["max_new_tokens"] = int(mnt)

        text = args["text"]
        speaker = args.get("speaker", "Ryan")
        language = args.get("language") or None
        instruct = args.get("instruct") or None

        wavs, sr = model.generate_custom_voice(
            text=text, speaker=speaker, language=language, instruct=instruct, **gkw
        )

        w = wavs[0]
        try:
            w = w.detach().cpu().to(torch.float32).numpy()
        except Exception:
            w = np.asarray(w, dtype="float32")
        w = np.squeeze(np.asarray(w, dtype="float32"))
        w = np.clip(w, -1.0, 1.0)

        out_wav = args["out_wav"]
        sf.write(out_wav, w, int(sr), subtype="PCM_16")
        dur = float(len(w)) / float(sr) if sr else 0.0

        write_meta({
            "ok": True, "sr": int(sr), "samples": int(len(w)), "duration_s": round(dur, 3),
            "wav_path": out_wav, "dtype": dtype_name, "attn": attn, "device": device,
            "speaker": speaker, "language": language, "instruct": instruct, "seed": seed,
            "max_new_tokens": (int(mnt) if mnt else None), "model_path": model_path,
            "runtime_ms": int((time.time() - t0) * 1000),
        })
        sys.stdout.write("SYNTH_OK dur=%.3f sr=%d samples=%d\n" % (dur, sr, len(w)))
        return 0
    except Exception as e:
        tb = traceback.format_exc()
        sys.stderr.write(tb + "\n")
        msg = repr(e)
        low = msg.lower()
        code = "synthesis_failed"
        if "speaker" in low:
            code = "invalid_speaker"
        elif ("out of memory" in low) or ("cuda" in low and "memory" in low):
            code = "gpu_oom"
        elif ("no module named" in low) or ("modulenotfound" in low):
            code = "env_error"
        write_meta({"ok": False, "error_code": code, "error": msg[:500],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
