#!/usr/bin/env python
# mock-worker.py -- stdlib-only stand-in for gen_image_infer.py, for the gen.image cloud pre-ship gate.
# Honours the same args.json / meta.json contract but does NOT load torch/diffusers/PIL: it writes a real
# valid PNG (hand-rolled via zlib+struct+crc) and a meta whose pixel_std is driven by the prompt, so the real
# Invoke-GenImage.ps1 wrapper's parse/confidence/review/envelope path can be exercised on the Linux cloud box
# (a GPU diffusion model cannot run there). This mirrors speech.tts's stdlib mock python worker.
import sys, os, json, time, struct, zlib, binascii


def write_png(path, w, h, rgb):
    # minimal valid RGB PNG, solid color `rgb`, dimensions clamped small for speed
    w = max(1, min(int(w), 64)); h = max(1, min(int(h), 64))
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", binascii.crc32(tag + data) & 0xffffffff))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    row = b"\x00" + bytes(rgb) * w
    raw = row * h
    idat = zlib.compress(raw, 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


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
    width = int(args.get("width", 512)); height = int(args.get("height", 512))
    fmt = str(args.get("format", "png")).lower()
    out_image = args["out_image"]

    # failure branch
    if "__FAIL__" in prompt:
        write_meta({"ok": False, "error_code": "generation_failed",
                    "error": "mock forced failure", "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stdout.write("MOCK_FAIL\n")
        return 1

    # confidence branches driven by the prompt
    if "__BLANK__" in prompt:
        pixel_std, pixel_mean, color = 0.0, 128.0, (128, 128, 128)
    elif "__LOWDETAIL__" in prompt:
        pixel_std, pixel_mean, color = 5.0, 120.0, (110, 120, 130)
    else:
        pixel_std, pixel_mean, color = 60.0, 100.0, (200, 40, 40)

    # pipeline-family passthrough (mirror the real worker's sd3 meta contract so the cloud gate exercises it)
    family = str(args.get("pipeline_family", "sd")).lower()
    if family == "sd3":
        sched_out = "flow_match_euler"
        offload_out = str(args.get("offload") or "model")
        t5_out = "dropped" if bool(args.get("drop_t5", False)) else "cpu_offload"
        variant_out = None
    else:
        sched_out = str(args.get("scheduler", "dpm++"))
        offload_out = args.get("offload") or None
        t5_out = None
        variant_out = args.get("variant")

    png_bytes = write_png(out_image, width, height, color)
    write_meta({
        "ok": True, "image_path": out_image, "format": fmt,
        "width": width, "height": height, "mode": "RGB", "image_bytes": png_bytes,
        "seed": seed, "steps": int(args.get("steps", 20)), "guidance": float(args.get("guidance", 7.5)),
        "scheduler": sched_out, "pipeline_family": family, "offload": offload_out, "t5": t5_out,
        "pixel_std": pixel_std, "pixel_mean": pixel_mean,
        "dtype": str(args.get("dtype", "float16")), "variant": variant_out,
        "device": str(args.get("device", "cuda:0")), "model_path": args.get("model_path"),
        "diffusers": "mock-0", "torch": "mock-0", "vram_peak_gb": 2.6,
        "load_ms": 10, "gen_ms": 20, "runtime_ms": int((time.time() - t0) * 1000),
    })
    sys.stdout.write("MOCK_OK %s %dx%d seed=%d std=%.1f\n" % (family, width, height, seed, pixel_std))
    return 0


if __name__ == "__main__":
    sys.exit(main())
