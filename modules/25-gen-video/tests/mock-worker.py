#!/usr/bin/env python
# mock-worker.py -- stdlib-only stand-in for video_gen_infer.py, for the gen.video cloud pre-ship gate.
# Honours the same args.json / meta.json contract but does NOT load torch/diffusers/ffmpeg: it writes a small
# placeholder output file (a GIF89a or ftyp/mp4 header stub) and a meta whose pixel_std / mean_interframe_diff
# are driven by the prompt, so the real Invoke-GenVideo.ps1 wrapper's parse/confidence/review/envelope path can
# be exercised on the Linux cloud box (a GPU AnimateDiff pipeline + ffmpeg cannot run there). Mirrors
# gen.music / gen.image's stdlib mock python worker.
import sys, os, json, time


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
    out_video = args["out_video"]
    fmt = str(args.get("format", "mp4")).lower()
    nf = int(args.get("num_frames", 16))
    w = int(args.get("width", 512))
    h = int(args.get("height", 512))
    fps = int(args.get("fps", 8))

    # failure branch
    if "__FAIL__" in prompt:
        write_meta({"ok": False, "error_code": "generation_failed",
                    "error": "mock forced failure", "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stdout.write("MOCK_FAIL\n")
        return 1

    # pixel_std / motion branches driven by the prompt
    if "__BLANK__" in prompt:
        pstd, motion = 1.0, 0.0
    elif "__STATIC__" in prompt:
        pstd, motion = 40.0, 0.1
    elif "__LOWMOTION__" in prompt:
        pstd, motion = 40.0, 1.0
    elif "__LOWDETAIL__" in prompt:
        pstd, motion = 10.0, 20.0
    else:
        pstd, motion = 44.0, 41.0

    # write a small placeholder output file (real worker writes the mp4/gif itself)
    if fmt == "gif":
        data = b"GIF89a" + bytes(32)
    else:
        data = b"\x00\x00\x00\x18ftypmp42" + bytes(32)
    with open(out_video, "wb") as f:
        f.write(data)

    write_meta({
        "ok": True, "video_path": out_video,
        "format": ("gif" if fmt == "gif" else "mp4"), "codec": ("gif" if fmt == "gif" else "h264"),
        "num_frames": nf, "width": w, "height": h, "fps": fps,
        "duration_s": round(nf / float(fps), 4) if fps > 0 else None,
        "pixel_std": pstd, "pixel_mean": 118.0, "mean_interframe_diff": motion,
        "per_frame_std_min": max(0.0, pstd - 5.0), "has_nan": False, "nonblank": bool(pstd > 5),
        "seed": seed, "steps": int(args.get("steps", 4)), "guidance": float(args.get("guidance", 1.0)),
        "dtype": str(args.get("dtype", "float16")), "device": str(args.get("device", "cuda")),
        "offload": bool(args.get("offload", False)),
        "base_path": args.get("base_path"), "adapter_ckpt": args.get("adapter_ckpt"),
        "diffusers": "mock-0", "torch": "mock-0",
        "vram_peak_gb": 4.75, "load_ms": 10, "gen_ms": 20, "runtime_ms": int((time.time() - t0) * 1000),
    })
    sys.stdout.write("MOCK_OK frames=%d std=%.1f motion=%.1f seed=%d\n" % (nf, pstd, motion, seed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
