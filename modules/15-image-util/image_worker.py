#!/usr/bin/env python
# image_worker.py -- Pillow+numpy imaging worker for image.util (Life Orchestrator, Module 15).
#
# Contract with the PowerShell wrapper (Invoke-ImageUtil.ps1):
#   argv[1] = path to a JSON args file:
#     { input, op, output_dir, meta_path, hash_size, no_perceptual_hash,
#       width, height, mode, max_dimension, resample, allow_upscale,
#       x, y, crop_width, crop_height, normalized, region, region_fraction,
#       format, quality, output_name,
#       tile_cols, tile_rows, tile_width, tile_height, tile_overlap,
#       compare_to }
#   The worker does all (deterministic) pixel work, writes any output image(s) into output_dir,
#   and writes meta_path with a JSON result. Only meta_path is authoritative; stdout/stderr are
#   diagnostics (captured to worker.log by the wrapper). Exit 0 on success, non-zero on failure
#   (meta_path is written in both cases when possible).
import sys, os, json, time, hashlib, traceback


class ImgError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


ALLOWED_OUT = {"png": "PNG", "jpg": "JPEG", "jpeg": "JPEG", "webp": "WEBP",
               "bmp": "BMP", "tiff": "TIFF", "tif": "TIFF"}

# EXIF tags kept in the "lite" block (tag number -> name). Bounded on purpose (no maker notes).
EXIF_WHITELIST = {
    271: "Make", 272: "Model", 274: "Orientation", 282: "XResolution", 283: "YResolution",
    296: "ResolutionUnit", 305: "Software", 306: "DateTime", 36867: "DateTimeOriginal",
    33434: "ExposureTime", 33437: "FNumber", 34855: "ISOSpeedRatings", 37386: "FocalLength",
}


def resample_filter(name):
    from PIL import Image
    return {
        "lanczos": Image.Resampling.LANCZOS, "bicubic": Image.Resampling.BICUBIC,
        "bilinear": Image.Resampling.BILINEAR, "box": Image.Resampling.BOX,
        "hamming": Image.Resampling.HAMMING, "nearest": Image.Resampling.NEAREST,
    }.get(str(name or "lanczos").lower(), Image.Resampling.LANCZOS)


def has_alpha(im):
    return im.mode in ("RGBA", "LA", "PA") or (im.mode == "P" and "transparency" in im.info)


def _safe_exif(v):
    try:
        if isinstance(v, bytes):
            return v.decode("utf-8", "replace").strip("\x00").strip()[:120]
        if isinstance(v, bool):
            return v
        if isinstance(v, (int, float)):
            return v
        if isinstance(v, str):
            return v.strip("\x00").strip()[:200]
        return str(v)[:120]
    except Exception:
        return None


def exif_lite(im):
    out = {}
    try:
        ex = im.getexif()
    except Exception:
        return out
    if not ex:
        return out
    for tag, name in EXIF_WHITELIST.items():
        try:
            if tag in ex:
                val = _safe_exif(ex[tag])
                if val is not None and val != "":
                    out[name] = val
        except Exception:
            pass
    try:
        if 34853 in ex:  # GPSInfo IFD pointer
            out["GPSInfo"] = True
    except Exception:
        pass
    return out


def _dct_matrix(np, N):
    n = np.arange(N)
    k = n.reshape((N, 1))
    return np.cos(np.pi * (2 * n + 1) * k / (2.0 * N))  # shape (k, n)


def _bits_to_hex(bits):
    n = 0
    for b in bits:
        n = (n << 1) | (1 if b else 0)
    width = (len(bits) + 3) // 4
    return format(n, "0%dx" % width)


def phash(np, Image, im, hash_size=8, highfreq_factor=4):
    size = hash_size * highfreq_factor
    g = im.convert("L").resize((size, size), Image.Resampling.LANCZOS)
    a = np.asarray(g, dtype=np.float64)
    C = _dct_matrix(np, size)
    dct = C @ a @ C.T
    low = dct[:hash_size, :hash_size]
    med = np.median(low)
    diff = (low > med).flatten()
    return _bits_to_hex(diff)


def dhash(np, Image, im, hash_size=8):
    g = im.convert("L").resize((hash_size + 1, hash_size), Image.Resampling.LANCZOS)
    a = np.asarray(g, dtype=np.int32)
    diff = (a[:, 1:] > a[:, :-1]).flatten()
    return _bits_to_hex(diff)


def hamming_hex(a, b):
    if a is None or b is None or len(a) != len(b):
        return None
    return bin(int(a, 16) ^ int(b, 16)).count("1")


def resolve_out(args, input_path):
    f = args.get("format")
    if f:
        f = str(f).lower()
        if f not in ALLOWED_OUT:
            raise ImgError("unsupported_format", "output format '%s' not in png/jpg/webp/bmp/tiff" % f)
    else:
        e = os.path.splitext(input_path)[1].lower().lstrip(".")
        f = e if e in ALLOWED_OUT else "png"
    pil = ALLOWED_OUT[f]
    ext = "jpg" if f in ("jpg", "jpeg") else ("tiff" if f in ("tif", "tiff") else f)
    return ext, pil


def prep_for_save(Image, im, pilfmt):
    mode = im.mode
    if pilfmt in ("JPEG", "BMP"):
        if has_alpha(im):
            rgba = im.convert("RGBA")
            bg = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
            bg.alpha_composite(rgba)
            return bg.convert("RGB")
        if mode not in ("RGB", "L", "CMYK"):
            return im.convert("RGB")
        return im
    if pilfmt in ("PNG", "WEBP", "TIFF"):
        if mode == "P":
            return im.convert("RGBA" if "transparency" in im.info else "RGB")
        return im
    return im


def save_image(Image, im, path, pilfmt, quality):
    out = prep_for_save(Image, im, pilfmt)
    kw = {}
    if pilfmt in ("JPEG", "WEBP"):
        kw["quality"] = int(quality)
    out.save(path, pilfmt, **kw)


def do_resize(Image, im, args):
    ow, oh = im.size
    rf = resample_filter(args.get("resample"))
    allow_up = bool(args.get("allow_upscale", False))
    maxd = args.get("max_dimension")
    w = args.get("width")
    h = args.get("height")
    if maxd:
        maxd = int(maxd)
        if maxd <= 0:
            raise ImgError("missing_params", "max_dimension must be > 0")
        scale = maxd / float(max(ow, oh))
        if scale >= 1.0 and not allow_up:
            scale = 1.0
        nw = max(1, int(round(ow * scale)))
        nh = max(1, int(round(oh * scale)))
        rmode = "max_dimension"
    elif str(args.get("mode", "fit")).lower() == "exact":
        if not w or not h:
            raise ImgError("missing_params", "exact resize needs width and height")
        nw, nh, rmode = int(w), int(h), "exact"
    elif str(args.get("mode", "fit")).lower() == "fill":
        if not w or not h:
            raise ImgError("missing_params", "fill resize needs width and height")
        w, h = int(w), int(h)
        scale = max(w / float(ow), h / float(oh))
        rw, rh = max(1, int(round(ow * scale))), max(1, int(round(oh * scale)))
        tmp = im.resize((rw, rh), rf)
        left, top = (rw - w) // 2, (rh - h) // 2
        out = tmp.crop((left, top, left + w, top + h))
        info = {"mode": "fill",
                "requested": {"width": w, "height": h, "max_dimension": None},
                "original": {"width": ow, "height": oh},
                "result": {"width": w, "height": h},
                "scale_x": round(scale, 6), "scale_y": round(scale, 6),
                "crop_offset": {"x": left, "y": top}}
        return out, info
    else:  # fit
        if not w and not h:
            raise ImgError("missing_params", "fit resize needs width and/or height (or max_dimension)")
        scales = []
        if w:
            scales.append(int(w) / float(ow))
        if h:
            scales.append(int(h) / float(oh))
        scale = min(scales)
        if scale >= 1.0 and not allow_up:
            scale = 1.0
        nw = max(1, int(round(ow * scale)))
        nh = max(1, int(round(oh * scale)))
        rmode = "fit"
    out = im.resize((nw, nh), rf)
    info = {"mode": rmode,
            "requested": {"width": (int(w) if w else None), "height": (int(h) if h else None),
                          "max_dimension": (int(maxd) if maxd else None)},
            "original": {"width": ow, "height": oh},
            "result": {"width": nw, "height": nh},
            "scale_x": round(nw / float(ow), 6), "scale_y": round(nh / float(oh), 6)}
    return out, info


def do_crop(im, args):
    ow, oh = im.size
    x, y = args.get("x"), args.get("y")
    cw, ch = args.get("crop_width"), args.get("crop_height")
    region = args.get("region")
    normalized = bool(args.get("normalized", False))
    warns = []
    if all(v is not None for v in (x, y, cw, ch)):
        if normalized:
            x, y = int(round(float(x) * ow)), int(round(float(y) * oh))
            cw, ch = int(round(float(cw) * ow)), int(round(float(ch) * oh))
        else:
            x, y, cw, ch = int(x), int(y), int(cw), int(ch)
        req = {"x": x, "y": y, "width": cw, "height": ch, "normalized": normalized, "region": None}
    elif region:
        f = min(max(float(args.get("region_fraction", 0.5)), 0.01), 1.0)
        cw, ch = max(1, int(round(ow * f))), max(1, int(round(oh * f)))
        region = str(region).lower()
        if region in ("left", "top-left", "bottom-left"):
            x = 0
        elif region in ("right", "top-right", "bottom-right"):
            x = ow - cw
        else:
            x = (ow - cw) // 2
        if region in ("top", "top-left", "top-right"):
            y = 0
        elif region in ("bottom", "bottom-left", "bottom-right"):
            y = oh - ch
        else:
            y = (oh - ch) // 2
        req = {"x": x, "y": y, "width": cw, "height": ch, "normalized": False, "region": region}
    else:
        raise ImgError("missing_params", "crop needs an explicit rect (x,y,crop_width,crop_height) or a named region")
    ax, ay = max(0, min(x, ow - 1)), max(0, min(y, oh - 1))
    ax2, ay2 = max(ax + 1, min(x + cw, ow)), max(ay + 1, min(y + ch, oh))
    if (ax, ay, ax2 - ax, ay2 - ay) != (x, y, cw, ch):
        warns.append("crop rect clamped to image bounds")
    out = im.crop((ax, ay, ax2, ay2))
    info = {"requested": req, "applied": {"x": ax, "y": ay, "width": ax2 - ax, "height": ay2 - ay}}
    return out, info, warns


def do_tile(Image, im, args, outdir, base, ext, pilfmt, quality):
    ow, oh = im.size
    overlap = max(0, int(args.get("tile_overlap", 0) or 0))
    tw, th = args.get("tile_width"), args.get("tile_height")
    cols, rows = args.get("tile_cols"), args.get("tile_rows")
    boxes = []
    if tw and th:
        tw, th = int(tw), int(th)
        if tw <= 0 or th <= 0:
            raise ImgError("missing_params", "tile_width/height must be > 0")
        stepx, stepy = max(1, tw - overlap), max(1, th - overlap)
        xs, ys = list(range(0, ow, stepx)), list(range(0, oh, stepy))
        ncols, nrows, tmode = len(xs), len(ys), "size"
        if ncols * nrows > 400:
            raise ImgError("too_many_tiles", "tile count %d exceeds the 400 cap" % (ncols * nrows))
        for ri, y0 in enumerate(ys):
            for ci, x0 in enumerate(xs):
                boxes.append((ri, ci, x0, y0, min(ow, x0 + tw), min(oh, y0 + th)))
        tile_w, tile_h = tw, th
    elif cols and rows:
        cols, rows = int(cols), int(rows)
        if cols <= 0 or rows <= 0:
            raise ImgError("missing_params", "tile_cols/rows must be > 0")
        if cols * rows > 400:
            raise ImgError("too_many_tiles", "tile count %d exceeds the 400 cap" % (cols * rows))
        xb = [int(round(i * ow / cols)) for i in range(cols + 1)]
        yb = [int(round(i * oh / rows)) for i in range(rows + 1)]
        ncols, nrows, tmode = cols, rows, "grid"
        for ri in range(rows):
            for ci in range(cols):
                boxes.append((ri, ci, xb[ci], yb[ri], min(ow, xb[ci + 1] + overlap), min(oh, yb[ri + 1] + overlap)))
        tile_w, tile_h = None, None
    else:
        raise ImgError("missing_params", "tile needs tile_cols+tile_rows or tile_width+tile_height")
    tiles, outputs, idx = [], [], 0
    for (ri, ci, x0, y0, x1, y1) in boxes:
        if x1 <= x0 or y1 <= y0:
            continue
        sub = im.crop((x0, y0, x1, y1))
        name = "%s_tile_r%d_c%d.%s" % (base, ri, ci, ext)
        p = os.path.join(outdir, name)
        save_image(Image, sub, p, pilfmt, quality)
        w2, h2 = sub.size
        tiles.append({"index": idx, "row": ri, "col": ci, "x": x0, "y": y0, "width": w2, "height": h2, "path": os.path.abspath(p)})
        outputs.append(p)
        idx += 1
    info = {"mode": tmode, "cols": ncols, "rows": nrows, "tile_width": tile_w, "tile_height": tile_h,
            "overlap": overlap, "count": len(tiles), "tiles": tiles}
    return outputs, info


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: image_worker.py <args.json>\n")
        return 2
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            args = json.load(f)
    except Exception as e:
        sys.stderr.write("could not read args file: %r\n" % (e,))
        return 2

    meta_path = args.get("meta_path")
    t0 = time.time()

    def write_meta(d):
        if not meta_path:
            return
        try:
            with open(meta_path, "w", encoding="utf-8") as fh:
                json.dump(d, fh)
        except Exception as e:
            sys.stderr.write("meta write failed: %r\n" % (e,))

    try:
        from PIL import Image
        import PIL
        import numpy as np
    except Exception as e:
        write_meta({"ok": False, "error_code": "env_error",
                    "error": "Pillow/numpy import failed: %r" % (e,),
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("import failed: %r\n" % (e,))
        return 1

    try:
        input_path = args.get("input")
        if not input_path or not os.path.isfile(input_path):
            raise ImgError("input_not_found", "input image not found: %s" % input_path)
        outdir = args.get("output_dir") or os.path.dirname(os.path.abspath(meta_path))
        os.makedirs(outdir, exist_ok=True)

        with open(input_path, "rb") as fh:
            raw = fh.read()
        sha = hashlib.sha256(raw).hexdigest()

        try:
            im = Image.open(input_path)
            im.load()
        except Exception as e:
            raise ImgError("decode_failed", "Pillow could not decode the image: %r" % (e,))

        fmt, mode = im.format, im.mode
        ow, oh = im.size
        alpha = bool(has_alpha(im))
        dpi = im.info.get("dpi")
        nframes = int(getattr(im, "n_frames", 1))
        exif = exif_lite(im)

        input_block = {"path": os.path.abspath(input_path), "exists": True, "bytes": len(raw),
                       "sha256": sha, "format": fmt, "mode": mode, "width": ow, "height": oh, "has_alpha": alpha}
        metadata = {"format": fmt, "mode": mode, "width": ow, "height": oh, "has_alpha": alpha,
                    "dpi": (list(dpi) if dpi else None), "n_frames": nframes, "exif": exif}

        hs = int(args.get("hash_size", 8) or 8)
        hashes = {"sha256": sha, "phash": None, "dhash": None, "hash_bits": hs * hs}
        if not bool(args.get("no_perceptual_hash", False)):
            hashes["phash"] = phash(np, Image, im, hs)
            hashes["dhash"] = dhash(np, Image, im, hs)

        op = str(args.get("op", "meta")).lower()
        base = args.get("output_name") or os.path.splitext(os.path.basename(input_path))[0]
        quality = int(args.get("quality", 90) or 90)
        outputs, resize, crop, tile, sim, warns = [], None, None, None, None, []

        if op == "meta":
            pass
        elif op in ("resize", "crop", "convert"):
            ext, pilfmt = resolve_out(args, input_path)
            if op == "resize":
                out_img, resize = do_resize(Image, im, args)
                suffix = "_resized"
            elif op == "crop":
                out_img, crop, cwarn = do_crop(im, args)
                warns += cwarn
                suffix = "_crop"
            else:
                out_img, suffix = im, ""
            name = "%s%s.%s" % (base, suffix, ext)
            p = os.path.join(outdir, name)
            save_image(Image, out_img, p, pilfmt, quality)
            outputs.append(p)
        elif op == "tile":
            ext, pilfmt = resolve_out(args, input_path)
            outs, tile = do_tile(Image, im, args, outdir, base, ext, pilfmt, quality)
            outputs += outs
        elif op == "similarity":
            cmp = args.get("compare_to")
            if not cmp:
                raise ImgError("missing_params", "similarity needs compare_to")
            if not os.path.isfile(cmp):
                raise ImgError("compare_not_found", "compare_to image not found: %s" % cmp)
            try:
                im2 = Image.open(cmp)
                im2.load()
            except Exception as e:
                raise ImgError("decode_failed", "could not decode compare_to: %r" % (e,))
            pa = hashes["phash"] or phash(np, Image, im, hs)
            pb = phash(np, Image, im2, hs)
            da = hashes["dhash"] or dhash(np, Image, im, hs)
            db = dhash(np, Image, im2, hs)
            hp, hd = hamming_hex(pa, pb), hamming_hex(da, db)
            bits = hs * hs
            sim = {"compare_to": os.path.abspath(cmp), "hash_bits": bits,
                   "phash_a": pa, "phash_b": pb, "hamming_phash": hp,
                   "dhash_a": da, "dhash_b": db, "hamming_dhash": hd,
                   "similarity": (round(1.0 - hp / float(bits), 6) if hp is not None else None)}
        else:
            raise ImgError("invalid_op", "unknown op '%s' (meta|resize|crop|convert|tile|similarity)" % op)

        out_meta = []
        for p in outputs:
            try:
                r = Image.open(p)
                r.load()
                out_meta.append({"path": os.path.abspath(p), "format": r.format, "mode": r.mode,
                                 "width": r.size[0], "height": r.size[1], "bytes": os.path.getsize(p)})
                r.close()
            except Exception as e:
                out_meta.append({"path": os.path.abspath(p), "error": repr(e)})

        write_meta({
            "ok": True, "op": op, "input": input_block, "metadata": metadata, "hashes": hashes,
            "outputs": out_meta, "resize": resize, "crop": crop, "tile": tile, "similarity": sim,
            "warnings": warns, "output_dir": os.path.abspath(outdir),
            "worker": {"python": sys.version.split()[0], "pillow_version": PIL.__version__, "numpy_version": np.__version__},
            "runtime_ms": int((time.time() - t0) * 1000),
        })
        sys.stdout.write("IMAGE_OK op=%s outputs=%d\n" % (op, len(outputs)))
        return 0
    except ImgError as ie:
        write_meta({"ok": False, "error_code": ie.code, "error": ie.message,
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("%s: %s\n" % (ie.code, ie.message))
        return 1
    except Exception as e:
        tb = traceback.format_exc()
        sys.stderr.write(tb + "\n")
        write_meta({"ok": False, "error_code": "image_util_failed", "error": repr(e)[:500],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
