#!/usr/bin/env python
# embed_worker.py -- local text-embedding worker for embedding.local (Life Orchestrator, Module 35).
#
# Contract with the PowerShell wrapper (Invoke-EmbeddingLocal.ps1):
#   argv[1] = path to a JSON args file:
#     { texts: [str, ...],            # inputs, EXACT order preserved in the output
#       normalize: bool,              # L2-normalize each vector (default true)
#       instruction: str|null,        # optional Qwen3-Embedding query-instruct prefix; null = document/raw
#       max_tokens: int,              # oversize threshold (real: token count; mock: whitespace-word count)
#       dtype: "fp32"|"fp16"|"bf16",  # real compute dtype (default fp32 for determinism)
#       device: "cuda"|"cpu",         # real device (default cuda; cpu = the CPU-fallback path)
#       model_path: str,              # HF safetensors dir (real mode)
#       mock: bool,                   # true -> deterministic numpy vectors, NO torch/model load
#       dim: int,                     # mock vector dimension (real reads hidden_size from the model)
#       seed: int,                    # mock determinism seed
#       meta_path: str }              # AUTHORITATIVE output file (JSON) -- written in success AND failure
#
# Only meta_path is authoritative; stdout/stderr are diagnostics (captured to worker.log by the wrapper).
# Exit 0 on success, non-zero on failure (meta_path is written in both cases when reachable).
#
# The REAL path serves Qwen3-Embedding-0.6B (arch Qwen3Model, hidden_size 1024, max_position_embeddings
# 32768) via transformers: LAST-TOKEN pooling (left padding + attention-mask-derived position_ids so a
# batched real token gets the SAME RoPE position as in a single call -> batch == single within fp tolerance),
# then optional L2 normalization. The MOCK path reproduces the exact SAME input classification / order
# reconstruction / normalization / empty-oversize flagging with deterministic seeded numpy vectors and NO
# torch import, so the portable seams are testable off-machine.
import sys, os, json, time, hashlib


class EmbedError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def get_peak_ram_bytes():
    # Cross-platform best-effort process peak working set / max RSS.
    try:
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes

            class PMC(ctypes.Structure):
                _fields_ = [
                    ("cb", wintypes.DWORD),
                    ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]

            counters = PMC()
            counters.cb = ctypes.sizeof(PMC)
            handle = ctypes.windll.kernel32.GetCurrentProcess()
            fn = None
            for lib, name in (("kernel32", "K32GetProcessMemoryInfo"), ("psapi", "GetProcessMemoryInfo")):
                try:
                    fn = getattr(getattr(ctypes.windll, lib), name)
                    break
                except Exception:
                    fn = None
            if fn is not None and fn(handle, ctypes.byref(counters), counters.cb):
                return int(counters.PeakWorkingSetSize)
        else:
            import resource
            return int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss) * 1024
    except Exception:
        pass
    return None


def stable_seed(text, seed):
    # Deterministic across processes (python's hash() is salted -> unusable for reproducibility).
    h = hashlib.sha256(text.encode("utf-8")).digest()
    return (seed ^ int.from_bytes(h[:8], "little")) & 0xFFFFFFFF


def classify(texts, n_tokens_list, max_tokens):
    # Shared by real + mock: decide per-input status from its (already-computed) token count.
    # empty/whitespace-only -> "empty"; token count > max_tokens -> "oversize"; else "ok".
    per_input, ok_indices = [], []
    for i, t in enumerate(texts):
        if t is None or str(t).strip() == "":
            per_input.append({"index": i, "status": "empty", "n_tokens": 0})
            continue
        nt = n_tokens_list[i]
        if nt > max_tokens:
            per_input.append({"index": i, "status": "oversize", "n_tokens": int(nt)})
            continue
        per_input.append({"index": i, "status": "ok", "n_tokens": int(nt)})
        ok_indices.append(i)
    return per_input, ok_indices


def run_mock(args):
    import numpy as np

    texts = [("" if t is None else str(t)) for t in args.get("texts", [])]
    normalize = bool(args.get("normalize", True))
    max_tokens = int(args.get("max_tokens", 32768))
    dim = int(args.get("dim", 1024))
    seed = int(args.get("seed", 0))

    # Mock token count = whitespace word count (deterministic, no tokenizer).
    n_tokens_list = [(0 if t.strip() == "" else len(t.split())) for t in texts]
    per_input, ok_indices = classify(texts, n_tokens_list, max_tokens)

    t0 = time.time()
    vectors = [None] * len(texts)
    for i in ok_indices:
        rng = np.random.default_rng(stable_seed(texts[i], seed))
        v = rng.standard_normal(dim).astype(np.float64)
        if normalize:
            nrm = float(np.linalg.norm(v))
            if nrm > 0:
                v = v / nrm
        vectors[i] = [float(x) for x in v.tolist()]
    embed_ms = int((time.time() - t0) * 1000)

    return {
        "ok": True,
        "dim": dim,
        "normalized": normalize,
        "count": len(texts),
        "pooling": "mock_seeded",
        "dtype": "mock",
        "device": "mock",
        "vectors": vectors,
        "per_input": per_input,
        "model_type": "mock",
        "hidden_size": dim,
        "timings": {"load_ms": 0, "embed_ms": embed_ms},
        "peak_vram_bytes": None,
        "peak_ram_bytes": get_peak_ram_bytes(),
        "provenance": {"mock": True, "numpy": np.__version__},
        "error": None,
    }


def run_real(args):
    import torch
    import transformers
    from transformers import AutoTokenizer, AutoModel

    texts_in = args.get("texts", [])
    texts = [("" if t is None else str(t)) for t in texts_in]
    normalize = bool(args.get("normalize", True))
    instruction = args.get("instruction", None)
    max_tokens = int(args.get("max_tokens", 32768))
    dtype_name = str(args.get("dtype", "fp32")).lower()
    device = str(args.get("device", "cuda")).lower()
    model_path = args.get("model_path")

    if not model_path or not os.path.isdir(model_path):
        raise EmbedError("model_not_found", "model_path missing or not a directory: %r" % (model_path,))
    if device == "cuda" and not torch.cuda.is_available():
        raise EmbedError("cuda_unavailable", "device=cuda requested but torch.cuda.is_available() is False")

    torch_dtype = {"fp32": torch.float32, "fp16": torch.float16, "bf16": torch.bfloat16}.get(dtype_name, torch.float32)

    # Determinism knobs (documented; measured tolerance recorded live).
    torch.manual_seed(0)
    try:
        torch.backends.cuda.matmul.allow_tf32 = False
        torch.backends.cudnn.allow_tf32 = False
        torch.use_deterministic_algorithms(False)  # keep kernels available; we measure the residual tolerance
    except Exception:
        pass

    def apply_instruction(t):
        if instruction:
            return "Instruct: %s\nQuery: %s" % (instruction, t)
        return t

    t_load0 = time.time()
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    tokenizer.padding_side = "left"  # last-token pooling needs the real last token in the last column
    model = AutoModel.from_pretrained(model_path, torch_dtype=torch_dtype)
    model = model.to(device).eval()
    if device == "cuda":
        torch.cuda.synchronize()
        torch.cuda.reset_peak_memory_stats()
    load_ms = int((time.time() - t_load0) * 1000)

    hidden_size = int(getattr(model.config, "hidden_size", args.get("dim", 1024)))
    model_type = str(getattr(model.config, "model_type", "unknown"))

    # Per-input token counts (real tokenizer, no truncation) for empty/oversize classification.
    n_tokens_list = []
    for t in texts:
        if t.strip() == "":
            n_tokens_list.append(0)
        else:
            ids = tokenizer(apply_instruction(t), add_special_tokens=True, truncation=False)["input_ids"]
            n_tokens_list.append(len(ids))
    per_input, ok_indices = classify(texts, n_tokens_list, max_tokens)

    vectors = [None] * len(texts)
    embed_ms = 0
    if ok_indices:
        ok_texts = [apply_instruction(texts[i]) for i in ok_indices]
        t_emb0 = time.time()
        with torch.no_grad():
            batch = tokenizer(ok_texts, padding=True, truncation=False, return_tensors="pt", add_special_tokens=True)
            batch = {k: v.to(device) for k, v in batch.items()}
            mask = batch["attention_mask"]
            # Mask-derived position ids: a real token gets positions 0..n-1 regardless of left padding,
            # matching a single (unpadded) call -> batch == single within fp tolerance.
            position_ids = mask.long().cumsum(-1) - 1
            position_ids = position_ids.masked_fill(mask == 0, 0)
            out = model(input_ids=batch["input_ids"], attention_mask=mask, position_ids=position_ids)
            last_hidden = out.last_hidden_state
            # Last-token pooling. padding_side=left -> the last column is always a real token.
            left_padding = bool((mask[:, -1].sum() == mask.shape[0]).item())
            if left_padding:
                emb = last_hidden[:, -1]
            else:
                seq_len = mask.sum(dim=1) - 1
                emb = last_hidden[torch.arange(last_hidden.shape[0], device=last_hidden.device), seq_len]
            emb = emb.to(torch.float32)
            if normalize:
                emb = torch.nn.functional.normalize(emb, p=2, dim=1)
            emb_cpu = emb.detach().cpu().numpy()
        if device == "cuda":
            torch.cuda.synchronize()
        embed_ms = int((time.time() - t_emb0) * 1000)
        for row, i in enumerate(ok_indices):
            vectors[i] = [float(x) for x in emb_cpu[row].tolist()]

    peak_vram = None
    peak_reserved = None
    if device == "cuda":
        try:
            peak_vram = int(torch.cuda.max_memory_allocated())
            peak_reserved = int(torch.cuda.max_memory_reserved())
        except Exception:
            pass

    cuda_ver = None
    try:
        cuda_ver = torch.version.cuda
    except Exception:
        pass

    return {
        "ok": True,
        "dim": hidden_size,
        "normalized": normalize,
        "count": len(texts),
        "pooling": "last_token",
        "dtype": dtype_name,
        "device": device,
        "vectors": vectors,
        "per_input": per_input,
        "model_type": model_type,
        "hidden_size": hidden_size,
        "timings": {"load_ms": load_ms, "embed_ms": embed_ms},
        "peak_vram_bytes": peak_vram,
        "peak_vram_reserved_bytes": peak_reserved,
        "peak_ram_bytes": get_peak_ram_bytes(),
        "provenance": {
            "mock": False,
            "torch": torch.__version__,
            "transformers": transformers.__version__,
            "cuda": cuda_ver,
        },
        "error": None,
    }


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: embed_worker.py <args.json>\n")
        return 2
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            args = json.load(f)
    except Exception as e:
        sys.stderr.write("could not read args file: %r\n" % (e,))
        return 2

    meta_path = args.get("meta_path")
    try:
        meta = run_mock(args) if bool(args.get("mock", False)) else run_real(args)
        code = 0
    except EmbedError as e:
        meta = {"ok": False, "error": {"code": e.code, "message": e.message}, "vectors": [], "per_input": []}
        code = 1
        sys.stderr.write("embed error [%s]: %s\n" % (e.code, e.message))
    except Exception as e:
        import traceback
        meta = {"ok": False, "error": {"code": "worker_exception", "message": repr(e)}, "vectors": [], "per_input": []}
        code = 1
        sys.stderr.write("worker exception: %r\n%s\n" % (e, traceback.format_exc()))

    if meta_path:
        try:
            with open(meta_path, "w", encoding="utf-8") as f:
                json.dump(meta, f)
        except Exception as e:
            sys.stderr.write("could not write meta_path: %r\n" % (e,))
            return 3
    return code


if __name__ == "__main__":
    sys.exit(main())
