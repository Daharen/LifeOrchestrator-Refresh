#!/usr/bin/env python
# mock-worker.py -- stdlib-only stand-in for music_gen_infer.py, for the gen.music cloud pre-ship gate.
# Honours the same args.json / meta.json contract but does NOT load torch/transformers/soundfile: it writes a
# real valid 32 kHz mono PCM16 WAV (via the stdlib `wave` module) whose RMS is driven by the prompt, so the real
# Invoke-GenMusic.ps1 wrapper's parse/confidence/review/envelope path can be exercised on the Linux cloud box
# (a GPU MusicGen model cannot run there). Mirrors gen.image / speech.tts's stdlib mock python worker.
import sys, os, json, time, wave, struct, math


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: mock-worker.py <args.json>\n")
        return 2
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        args = json.load(f)
    meta_path = args.get("meta_path")
    t0 = time.time()

    def write_meta(d):
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(d, f)

    prompt = str(args.get("prompt", ""))
    seed = int(args.get("seed", -1))
    if seed < 0:
        seed = 1234567  # deterministic stand-in for the "random" branch
    duration = float(args.get("duration", 8.0))
    out_wav = args["out_wav"]
    sr = 32000
    frame_rate = 50.0
    max_new_tokens = max(8, min(int(round(duration * frame_rate)), int(round(30.0 * frame_rate))))

    # failure branch
    if "__FAIL__" in prompt:
        write_meta({"ok": False, "error_code": "generation_failed",
                    "error": "mock forced failure", "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stdout.write("MOCK_FAIL\n")
        return 1

    # amplitude / rms branches driven by the prompt
    if "__SILENT__" in prompt:
        amp = 0.0
    elif "__LOWRMS__" in prompt:
        amp = 0.01
    else:
        amp = 0.3

    n = max(1, int(round(duration * sr)))
    frames = bytearray()
    sumsq = 0.0
    peak = 0.0
    for i in range(n):
        v = amp * math.sin(2.0 * math.pi * 220.0 * i / sr)
        if abs(v) > peak:
            peak = abs(v)
        sumsq += v * v
        s = int(max(-1.0, min(1.0, v)) * 32767)
        frames += struct.pack("<h", s)
    with wave.open(out_wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(frames))
    rms = math.sqrt(sumsq / n) if n else 0.0

    write_meta({
        "ok": True, "audio_path": out_wav, "sr": sr, "frame_rate": frame_rate,
        "samples": n, "duration_s": round(n / float(sr), 4),
        "rms": round(rms, 6), "peak_raw": round(peak, 6), "peak_final": round(peak, 6),
        "normalized": False, "has_nan": False,
        "seed": seed, "max_new_tokens": max_new_tokens,
        "guidance": float(args.get("guidance", 3.0)), "temperature": float(args.get("temperature", 1.0)),
        "top_k": int(args.get("top_k", 250)), "top_p": float(args.get("top_p", 0.0)),
        "dtype": str(args.get("dtype", "float32")), "device": str(args.get("device", "cuda:0")),
        "model_path": args.get("model_path"), "transformers": "mock-0", "torch": "mock-0",
        "vram_peak_gb": 2.4, "load_ms": 10, "gen_ms": 20, "runtime_ms": int((time.time() - t0) * 1000),
    })
    sys.stdout.write("MOCK_OK %.2fs sr=%d seed=%d rms=%.4f\n" % (n / float(sr), sr, seed, rms))
    return 0


if __name__ == "__main__":
    sys.exit(main())
