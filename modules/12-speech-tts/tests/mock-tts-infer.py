#!/usr/bin/env python
# mock-tts-infer.py — stand-in for tts_infer.py for OFF-GPU logic tests (no model/qwen_tts/GPU needed).
# Honours the same args-file contract, writes a real PCM16 WAV (stdlib `wave`, silence) whose duration is
# controllable, and writes the meta JSON. Lets the REAL Invoke-SpeechTts.ps1 parse/confidence/review/envelope/
# audio.ingest-conversion logic run unchanged on the cloud box before shipping (mirrors Modules 8/9/11 mocks).
#
# Env controls (set by the harness):
#   MOCK_TTS_DUR   seconds of audio to emit (default: a plausible duration from the text length)
#   MOCK_TTS_FAIL  if set, emit an ok:false meta and exit 1 (to exercise the failure path)
import sys, os, json, time, wave, struct


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: mock-tts-infer.py <args.json>\n"); return 2
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        args = json.load(f)
    meta_path = args.get("meta_path")
    t0 = time.time()

    def write_meta(d):
        if meta_path:
            with open(meta_path, "w", encoding="utf-8") as f:
                json.dump(d, f)

    if os.environ.get("MOCK_TTS_FAIL"):
        write_meta({"ok": False, "error_code": "synthesis_failed", "error": "mock forced failure",
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("mock forced failure\n")
        return 1

    text = args.get("text", "")
    chars = len(text.replace(" ", ""))
    sr = 24000
    if os.environ.get("MOCK_TTS_DUR"):
        dur = float(os.environ["MOCK_TTS_DUR"])
    else:
        dur = max(0.5, 0.06 * max(1, chars))  # plausible: ~0.06 s/char
    n = int(dur * sr)
    out_wav = args["out_wav"]
    with wave.open(out_wav, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(b"\x00\x00" * n)  # PCM16 silence
    write_meta({
        "ok": True, "sr": sr, "samples": n, "duration_s": round(n / float(sr), 3),
        "wav_path": out_wav, "dtype": str(args.get("dtype", "bfloat16")), "attn": str(args.get("attn", "sdpa")),
        "device": str(args.get("device", "cuda:0")), "speaker": args.get("speaker", "Ryan"),
        "language": args.get("language"), "instruct": args.get("instruct"), "seed": args.get("seed", -1),
        "max_new_tokens": args.get("max_new_tokens"), "model_path": args.get("model_path"),
        "runtime_ms": int((time.time() - t0) * 1000),
    })
    sys.stdout.write("MOCK_SYNTH_OK dur=%.3f\n" % (n / float(sr),))
    return 0


if __name__ == "__main__":
    sys.exit(main())
