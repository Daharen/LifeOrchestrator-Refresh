#!/usr/bin/env python
# detect_worker.py -- ONNX object-detection worker for detect.objects (Life Orchestrator, Module 16).
#
# Contract with the PowerShell wrapper (Invoke-DetectObjects.ps1):
#   argv[1] = path to a JSON args file:
#     { image, model, meta_path, output_dir?,
#       score_threshold, nms_threshold, max_detections, classes[]?,
#       provider ("cpu"|"cuda"|"dml"), box_scale_x, box_scale_y, class_names[]? }
#   The worker loads the ONNX model with onnxruntime (CPU provider by default -> no GPU/port binding,
#   so the skill is parallel-safe), letterbox-preprocesses the image, runs inference, decodes the
#   YOLOX grid/stride output, applies class-aware NMS, maps boxes back to ORIGINAL image pixels
#   (dividing by the letterbox ratio, then multiplying by box_scale_* to undo any image.util
#   downscale the wrapper applied), and writes meta_path with a JSON result. Only meta_path is
#   authoritative; stdout/stderr are diagnostics (captured to worker.log by the wrapper). Exit 0 on
#   success, non-zero on failure (meta_path is written in both cases when possible).
#
# YOLOX (Apache-2.0) topology: input [1,3,S,S] float32 (letterbox, 114 pad, BGR, raw 0-255, CHW);
# output [1, A, 85] = 4 box (cx,cy,w,h in grid units) + 1 objectness + 80 class logits, over strides
# {8,16,32}. Decode: xy=(raw+grid)*stride, wh=exp(raw)*stride, score=obj*cls. Verified live on the
# executor (m16-probe-001): dog/car/bicycle on the committed fixture, identical to the cloud box.
import sys, os, json, time, traceback

COCO80 = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
    "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
    "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite",
    "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
    "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
    "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch", "potted plant",
    "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote", "keyboard", "cell phone",
    "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors",
    "teddy bear", "hair drier", "toothbrush",
]


class DetError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def providers_for(name):
    n = str(name or "cpu").lower()
    if n in ("cuda", "gpu"):
        return ["CUDAExecutionProvider", "CPUExecutionProvider"]
    if n in ("dml", "directml"):
        return ["DmlExecutionProvider", "CPUExecutionProvider"]
    if n in ("tensorrt", "trt"):
        return ["TensorrtExecutionProvider", "CUDAExecutionProvider", "CPUExecutionProvider"]
    return ["CPUExecutionProvider"]


def preproc(np, Image, pil, size):
    # Letterbox: keep aspect, pad the remainder with 114 (top-left placement), BGR, raw 0-255, CHW.
    pil = pil.convert("RGB")
    w, h = pil.size
    r = min(size[0] / float(h), size[1] / float(w))
    nw, nh = int(round(w * r)), int(round(h * r))
    nw = max(1, min(nw, size[1]))
    nh = max(1, min(nh, size[0]))
    resized = np.asarray(pil.resize((nw, nh), Image.BILINEAR))[:, :, ::-1]  # RGB -> BGR
    padded = np.ones((size[0], size[1], 3), dtype=np.uint8) * 114
    padded[:nh, :nw] = resized
    chw = padded.transpose(2, 0, 1).astype(np.float32)
    return chw[None], r


def decode(np, out, size):
    strides = [8, 16, 32]
    grids, es = [], []
    for s in strides:
        hs, ws = size[0] // s, size[1] // s
        xv, yv = np.meshgrid(np.arange(ws), np.arange(hs))
        grid = np.stack((xv, yv), 2).reshape(1, -1, 2)
        grids.append(grid)
        es.append(np.full((1, grid.shape[1], 1), s))
    grids = np.concatenate(grids, 1)
    es = np.concatenate(es, 1)
    out = out.copy()
    out[..., :2] = (out[..., :2] + grids) * es
    out[..., 2:4] = np.exp(out[..., 2:4]) * es
    return out[0]


def nms(np, boxes, scores, thr):
    x1, y1, x2, y2 = boxes.T
    areas = (x2 - x1) * (y2 - y1)
    order = scores.argsort()[::-1]
    keep = []
    while order.size > 0:
        i = order[0]
        keep.append(int(i))
        xx1 = np.maximum(x1[i], x1[order[1:]])
        yy1 = np.maximum(y1[i], y1[order[1:]])
        xx2 = np.minimum(x2[i], x2[order[1:]])
        yy2 = np.minimum(y2[i], y2[order[1:]])
        w = np.maximum(0.0, xx2 - xx1)
        h = np.maximum(0.0, yy2 - yy1)
        inter = w * h
        ovr = inter / (areas[i] + areas[order[1:]] - inter + 1e-9)
        order = order[1:][ovr <= thr]
    return keep


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: detect_worker.py <args.json>\n")
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
        import numpy as np
        from PIL import Image
        import PIL
        import onnxruntime as ort
    except Exception as e:
        write_meta({"ok": False, "error_code": "env_error",
                    "error": "numpy/Pillow/onnxruntime import failed: %r" % (e,),
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("import failed: %r\n" % (e,))
        return 1

    try:
        image_path = args.get("image")
        model_path = args.get("model")
        if not image_path or not os.path.isfile(image_path):
            raise DetError("input_not_found", "input image not found: %s" % image_path)
        if not model_path or not os.path.isfile(model_path):
            raise DetError("model_not_found", "detector model not found: %s" % model_path)

        score_thr = float(args.get("score_threshold", 0.25))
        nms_thr = float(args.get("nms_threshold", 0.45))
        max_det = int(args.get("max_detections", 100) or 100)
        bsx = float(args.get("box_scale_x", 1.0) or 1.0)
        bsy = float(args.get("box_scale_y", 1.0) or 1.0)
        class_names = args.get("class_names") or COCO80
        req_provider = args.get("provider", "cpu")

        # class filter (by name; case-insensitive). Unknown names are reported as warnings.
        warns = []
        keep_ids = None
        cf = args.get("classes")
        if cf:
            want = [str(c).strip().lower() for c in cf if str(c).strip()]
            lut = {n.lower(): i for i, n in enumerate(class_names)}
            keep_ids = set()
            for w in want:
                if w in lut:
                    keep_ids.add(lut[w])
                else:
                    warns.append("unknown class filter '%s' ignored" % w)

        # session
        try:
            so = ort.SessionOptions()
            sess = ort.InferenceSession(model_path, sess_options=so, providers=providers_for(req_provider))
        except Exception as e:
            raise DetError("session_failed", "onnxruntime could not create a session: %r" % (e,))
        provider_used = (sess.get_providers() or ["?"])[0]
        inp = sess.get_inputs()[0]
        outm = sess.get_outputs()[0]
        try:
            S = (int(inp.shape[2]), int(inp.shape[3]))
        except Exception:
            S = (416, 416)
        num_classes = None
        try:
            num_classes = int(outm.shape[2]) - 5
        except Exception:
            num_classes = len(class_names)

        # image
        try:
            pil = Image.open(image_path)
            pil.load()
        except Exception as e:
            raise DetError("decode_failed", "Pillow could not decode the image: %r" % (e,))
        W, H = pil.size
        # When the wrapper downscaled via image.util, boxes are rescaled to ORIGINAL pixels
        # (box_scale_*), so clamp/report against the original dimensions, not the worker input's.
        OW = int(args.get("orig_width") or 0) or W
        OH = int(args.get("orig_height") or 0) or H

        x, ratio = preproc(np, Image, pil, S)
        t1 = time.time()
        try:
            out = sess.run(None, {inp.name: x})[0]
        except Exception as e:
            raise DetError("inference_failed", "onnxruntime inference failed: %r" % (e,))
        infer_ms = int((time.time() - t1) * 1000)

        pred = decode(np, out, S)
        boxes = pred[:, :4]
        obj = pred[:, 4:5]
        cls = pred[:, 5:]
        scores = obj * cls  # (A, C)
        # cxcywh -> xyxy, then map to original pixels (undo letterbox ratio + any wrapper downscale)
        xyxy = np.empty_like(boxes)
        xyxy[:, 0] = boxes[:, 0] - boxes[:, 2] / 2.0
        xyxy[:, 1] = boxes[:, 1] - boxes[:, 3] / 2.0
        xyxy[:, 2] = boxes[:, 0] + boxes[:, 2] / 2.0
        xyxy[:, 3] = boxes[:, 1] + boxes[:, 3] / 2.0
        xyxy /= ratio
        xyxy[:, 0] *= bsx
        xyxy[:, 2] *= bsx
        xyxy[:, 1] *= bsy
        xyxy[:, 3] *= bsy

        C = scores.shape[1]
        raw = []
        for c in range(C):
            if keep_ids is not None and c not in keep_ids:
                continue
            cs = scores[:, c]
            m = cs > score_thr
            if not m.any():
                continue
            b = xyxy[m]
            sc = cs[m]
            for k in nms(np, b, sc, nms_thr):
                x1, y1, x2, y2 = b[k]
                raw.append((c, float(sc[k]), float(x1), float(y1), float(x2), float(y2)))
        raw.sort(key=lambda d: -d[1])
        if len(raw) > max_det:
            warns.append("detections truncated to max_detections=%d (had %d)" % (max_det, len(raw)))
            raw = raw[:max_det]

        dets = []
        for i, (c, sc, x1, y1, x2, y2) in enumerate(raw):
            ix1 = max(0, min(int(round(x1)), OW))
            iy1 = max(0, min(int(round(y1)), OH))
            ix2 = max(ix1, min(int(round(x2)), OW))
            iy2 = max(iy1, min(int(round(y2)), OH))
            name = class_names[c] if 0 <= c < len(class_names) else str(c)
            dets.append({
                "index": i, "class_id": c, "class": name, "score": round(sc, 6),
                "box": {"x": ix1, "y": iy1, "width": ix2 - ix1, "height": iy2 - iy1},
                "box_xyxy": [ix1, iy1, ix2, iy2],
            })

        write_meta({
            "ok": True,
            "image": {"path": os.path.abspath(image_path), "width": OW, "height": OH,
                      "worker_input": {"width": W, "height": H}},
            "input_size": [S[0], S[1]],
            "model": os.path.abspath(model_path),
            "provider_requested": str(req_provider),
            "provider_used": provider_used,
            "num_classes": num_classes,
            "score_threshold": score_thr, "nms_threshold": nms_thr, "max_detections": max_det,
            "box_scale_x": bsx, "box_scale_y": bsy,
            "detections": dets, "detection_count": len(dets),
            "warnings": warns,
            "infer_ms": infer_ms,
            "runtime_ms": int((time.time() - t0) * 1000),
            "worker": {"python": sys.version.split()[0], "onnxruntime_version": ort.__version__,
                       "numpy_version": np.__version__, "pillow_version": PIL.__version__},
        })
        sys.stdout.write("DETECT_OK n=%d provider=%s\n" % (len(dets), provider_used))
        return 0
    except DetError as de:
        write_meta({"ok": False, "error_code": de.code, "error": de.message,
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("%s: %s\n" % (de.code, de.message))
        return 1
    except Exception as e:
        sys.stderr.write(traceback.format_exc() + "\n")
        write_meta({"ok": False, "error_code": "detect_failed", "error": repr(e)[:500],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
