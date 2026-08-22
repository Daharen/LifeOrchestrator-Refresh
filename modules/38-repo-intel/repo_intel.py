#!/usr/bin/env python
# repo_intel.py -- deterministic repository-intelligence worker for repo.intel
#   (Life Orchestrator, Module 38, Wave 2 PRODUCER lane; MEMORY_CONTRACT s1).
#
# Parses the repo BY SOURCE TYPE and emits TYPED record-envelope artifacts conforming to
# core-docs/MEMORY_CONTRACT.md section 1 (the record + provenance envelope, v0.1) so the catalog
# (#36 artifact.search 0.2) can ingest them as FIRST-CLASS records, NOT chunks. CPU-only, stdlib
# only, no model, no network, fully deterministic.
#
# record_kinds emitted: symbol | entity | relationship | skill | summary  (the s1 enum subset).
# Edges are first-class: parent_edges/child_edges on structural records PLUS `relationship` records
# for the cross-cutting dependency graph (imports, file->module, test<->module, schema producer/consumer).
#
# Contract with the PowerShell wrapper (Invoke-RepoIntel.ps1):
#   argv[1] = path to a JSON args file:
#     { op, roots[], root, namespace, source_label, file_budget, output_dir, meta_path,
#       exclude_dirs[], exclude_globs[], include_globs[], records_path }
#   The worker does all (deterministic) work, writes artifact files into output_dir, and writes
#   meta_path with a JSON result. Only meta_path is authoritative; stdout/stderr are diagnostics.
#   Exit 0 on success, non-zero on failure (meta_path is written in both cases when possible).
#
# DETERMINISM CONTRACT (mirrors #36 SCHEMA_NOTES s1):
#   - Canonical artifacts (records.jsonl, records.json, index_manifest.json, inventory.json,
#     ingest_records.json) contain NO absolute paths, NO timestamps, NO random/wall-clock ids.
#     Identical corpus CONTENT => byte-identical canonical artifacts across runs AND machines.
#   - All ids are content+path derived. `created_by_ingest_run` is a DETERMINISTIC content-derived
#     id (never wall-clock). Run provenance (timestamps/host) lives only in the skill envelope.
#   - Paths are repo-relative + forward-slash. Spans are BYTE offsets over raw file bytes (EOL-faithful).
import sys, os, json, time, hashlib, re, ast, traceback

WORKER_VERSION = "0.1.0"
RECORD_SCHEMA = "lifeorch.repo_intel.record/0.1"
INGEST_SCHEMA = "lifeorch.repo_intel.ingest_records/0.1"
RECORD_KINDS = ("symbol", "entity", "relationship", "skill", "summary")

# --- parser / extractor fingerprints (name;version;options) -- a version change invalidates derived records (s4)
FP = {
    "inventory": "repo.intel.inventory/0.1;sorted-walk;sha256",
    "md": "repo.intel.md/0.1;atx-headings;fence-aware",
    "pwsh": "repo.intel.pwsh/0.1;regex;function+class+import+dotsource",
    "python": "repo.intel.python/0.1;ast;def+class+import",
    "skill": "repo.intel.skill-json/0.1;manifest",
    "jsonconfig": "repo.intel.json-config/0.1;toplevel-keys",
    "text": "repo.intel.text/0.1;lines",
    "relationships": "repo.intel.relationships/0.1;imports+module+test+schema",
    "summary": "repo.intel.summary/0.1;file-outline+folder-index",
}

STATUS_CURRENT = "current"          # s5: a freshly-produced record is current (not one of the stale reasons)
AUTHORITY = "canonical_source"      # s1: the repo is the canonical source of truth (single value for Wave 2)
SENSITIVITY = "repo_internal"       # s7: single value now; the field is present from day one

# ---- default privacy exclusions (s7 -- TESTED, not just documented) ----
DEFAULT_EXCLUDE_DIRS = [
    ".git", "runtime", "artifacts", "__pycache__", "node_modules", ".vs", ".idea",
    "bin", "obj", ".pytest_cache", "_to_delete", "venv", ".venv", "env", "python_env",
    ".mypy_cache", ".ipynb_checkpoints",
]
DEFAULT_EXCLUDE_GLOBS = [
    "*.db", "*.db-wal", "*.db-shm", "*.sqlite", "*.sqlite3",
    "*.gguf", "*.safetensors", "*.onnx", "*.pt", "*.pth", "*.ckpt", "*.bin", "*.pkl", "*.npy", "*.npz",
    "*.exe", "*.dll", "*.so", "*.dylib", "*.lib", "*.pyd",
    "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.bmp", "*.tif", "*.tiff", "*.ico",
    "*.mp3", "*.wav", "*.flac", "*.ogg", "*.opus", "*.mp4", "*.mov", "*.avi", "*.mkv", "*.webm",
    "*.zip", "*.gz", "*.7z", "*.tar", "*.rar", "*.pdf", "*.lock",
]
MAX_FILE_BYTES = 5 * 1024 * 1024    # oversize -> parse failure (surfaced), never silently dropped


class RepoError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


# ------------------------------------------------------------------ helpers
def _h(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def _hb(b):
    return hashlib.sha256(b).hexdigest()


def canon(obj):
    """Canonical JSON: sorted keys, ASCII, no spaces. Deterministic across machines."""
    return json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",", ":"))


def slug(s):
    s = (s or "").strip().lower()
    return re.sub(r"[^a-z0-9._-]+", "-", s).strip("-") or "corpus"


def rel_posix(root, path):
    r = os.path.relpath(path, root).replace(os.sep, "/")
    return r


def fnmatch_glob(name, glob):
    return re.fullmatch(_glob_to_re(glob), name) is not None


_GLOB_CACHE = {}
def _glob_to_re(glob):
    r = _GLOB_CACHE.get(glob)
    if r is None:
        # minimal glob: * -> [^/]*, ? -> [^/], case-insensitive on the basename
        out = ["(?i)"]
        for ch in glob:
            if ch == "*":
                out.append("[^/]*")
            elif ch == "?":
                out.append("[^/]")
            else:
                out.append(re.escape(ch))
        r = "".join(out)
        _GLOB_CACHE[glob] = r
    return r


def token_count(text):
    """Deterministic token estimate: whitespace-delimited tokens."""
    if not text:
        return 0
    return len(text.split())


def line_byte_starts(raw):
    """Byte offset of the start of each 1-based line. starts[i] = byte offset of line i (1-based)."""
    starts = [0, 0]  # index 0 unused; line 1 starts at byte 0
    for i, b in enumerate(raw):
        if b == 0x0A:  # '\n'
            starts.append(i + 1)
    return starts


# ------------------------------------------------------------------ source typing
EXT_TYPE = {
    ".md": "markdown", ".markdown": "markdown", ".mdown": "markdown", ".mkd": "markdown",
    ".ps1": "powershell", ".psm1": "powershell", ".psd1": "powershell",
    ".py": "python",
    ".json": "json", ".config": "json", ".jsonc": "json",
    ".txt": "text", ".bat": "text", ".cmd": "text", ".sh": "text", ".gitignore": "text",
    ".md5": "text", ".csv": "text", ".yaml": "text", ".yml": "text", ".ini": "text", ".cfg": "text",
}


def classify(rel):
    base = os.path.basename(rel)
    if base == "skill.json":
        return "skill_manifest"
    ext = os.path.splitext(base)[1].lower()
    if base.lower() == ".gitignore":
        return "text"
    return EXT_TYPE.get(ext, "other")


def module_of(rel):
    """Return (module_rel, module_nn) if rel is under modules/<NN>-<name>/, else (None, None)."""
    parts = rel.split("/")
    if len(parts) >= 2 and parts[0] == "modules":
        m = re.match(r"^([0-9][0-9A-Za-z.]*)-", parts[1])
        if m:
            return ("modules/" + parts[1], m.group(1))
    return (None, None)


def is_test_path(rel):
    parts = rel.split("/")
    return "tests" in parts


# ------------------------------------------------------------------ walk / inventory
def walk_inventory(root, exclude_dirs, exclude_globs, include_globs, file_budget):
    """Deterministic sorted walk. Returns (files[], budget_hit, excluded_count)."""
    files = []
    excluded = 0
    exdirs = set(d.lower() for d in exclude_dirs)
    root = os.path.abspath(root)
    stack_dirs = []  # collected candidate files (rel) for stable sort
    for dirpath, dirnames, filenames in os.walk(root):
        # prune excluded dirs (by segment name, case-insensitive) -- deterministic order
        dirnames[:] = sorted(d for d in dirnames if d.lower() not in exdirs)
        for fn in sorted(filenames):
            full = os.path.join(dirpath, fn)
            rel = rel_posix(root, full)
            # skip files inside an excluded segment (defensive; os.walk pruning already handles dirs)
            segs = rel.split("/")
            if any(s.lower() in exdirs for s in segs[:-1]):
                excluded += 1
                continue
            if any(fnmatch_glob(fn, g) for g in exclude_globs):
                excluded += 1
                continue
            if include_globs and not any(fnmatch_glob(fn, g) for g in include_globs):
                excluded += 1
                continue
            stack_dirs.append(rel)
    stack_dirs.sort()
    budget_hit = False
    if file_budget and file_budget > 0 and len(stack_dirs) > file_budget:
        stack_dirs = stack_dirs[:file_budget]
        budget_hit = True
    for rel in stack_dirs:
        full = os.path.join(root, rel.replace("/", os.sep))
        try:
            with open(full, "rb") as fh:
                raw = fh.read()
        except Exception as e:
            files.append({"rel": rel, "error": "read_failed:%r" % (e,), "raw": None,
                          "size": 0, "content_hash": None, "source_type": classify(rel)})
            continue
        files.append({
            "rel": rel, "raw": raw, "size": len(raw),
            "content_hash": _hb(raw), "source_type": classify(rel), "error": None,
        })
    return files, budget_hit, excluded


# ------------------------------------------------------------------ record construction
class Emitter:
    def __init__(self, namespace, ingest_run_id):
        self.ns = namespace
        self.run = ingest_run_id
        self.records = []
        self.by_id = {}

    def doc_id(self, rel):
        return "doc_" + _h(self.ns + "\0" + rel)[:24]

    def ver_id(self, rel, content_hash):
        return "ver_" + _h(self.doc_id(rel) + "\0" + content_hash)[:24]

    def add(self, record_id, kind, payload, *, source_rel=None, file_hash=None,
            span=None, derivation_refs=None, parser_fp=None, extractor_fp=None,
            parent_edges=None, child_edges=None):
        assert kind in RECORD_KINDS, kind
        content = canon(payload)
        content_hash = _h(content)
        record_version_id = "rv_" + _h(record_id + "\0" + content_hash)[:24]
        source_version_id = self.ver_id(source_rel, file_hash) if (source_rel and file_hash) else None
        rec = {
            "schema": RECORD_SCHEMA,
            "record_id": record_id,
            "record_version_id": record_version_id,
            "record_kind": kind,
            "namespace": self.ns,
            "content_hash": content_hash,
            "status": STATUS_CURRENT,
            "authority_level": AUTHORITY,
            "sensitivity_class": SENSITIVITY,
            "valid_from": None,
            "valid_to": None,
            "created_by_ingest_run": self.run,
            "source_version_id": source_version_id,
            "source_path": source_rel,                       # repo-relative provenance path
            "source_span": (dict(span) if span else None),   # {start,end} BYTE offsets (object form, s3)
            "derivation_refs": list(derivation_refs or []),
            "parser_fingerprint": parser_fp,
            "chunker_fingerprint": None,                     # repo.intel emits typed records, not chunks
            "extractor_fingerprint": extractor_fp,
            "schema_version": RECORD_SCHEMA,
            "token_count": token_count(payload.get("text") if isinstance(payload, dict) else None),
            "embedding_space_id": None,                       # nullable until embedded (s2)
            "parent_edges": list(parent_edges or []),
            "child_edges": list(child_edges or []),
            "payload": payload,
        }
        if record_id in self.by_id:
            # deterministic de-dup: identical logical record seen twice (e.g. same section id) -> keep first,
            # merge child_edges deterministically. Should be rare; keeps ids unique.
            existing = self.by_id[record_id]
            for e in rec["child_edges"]:
                if e not in existing["child_edges"]:
                    existing["child_edges"].append(e)
            return existing
        self.by_id[record_id] = rec
        self.records.append(rec)
        return rec


def edge(edge_type, target_record_id=None, external=False, external_ref=None):
    e = {"edge_type": edge_type}
    if external:
        e["external"] = True
        e["external_ref"] = external_ref
        e["target_record_id"] = None
    else:
        e["external"] = False
        e["target_record_id"] = target_record_id
    return e


# ---- id helpers (LOGICAL ids: path/name based -> survive content revisions) ----
def id_file(ns, rel):      return "ent_file_" + _h(ns + "\0file\0" + rel)[:20]
def id_dir(ns, rel):       return "ent_dir_" + _h(ns + "\0dir\0" + (rel or "."))[:20]
def id_module(ns, mrel):   return "ent_mod_" + _h(ns + "\0module\0" + mrel)[:20]
def id_symbol(ns, rel, qual, kind): return "sym_" + _h(ns + "\0" + rel + "\0" + qual + "\0" + kind)[:24]
def id_skill(ns, sid):     return "skl_" + _h(ns + "\0" + sid)[:24]
def id_secsum(ns, rel, secpath, ordinal): return "sum_sec_" + _h(ns + "\0" + rel + "\0" + secpath + "\0" + str(ordinal))[:20]
def id_filesum(ns, rel):   return "sum_file_" + _h(ns + "\0" + rel)[:20]
def id_dirsum(ns, rel):    return "sum_dir_" + _h(ns + "\0" + (rel or "."))[:20]
def id_rel(ns, rtype, frm, to): return "rel_" + _h(ns + "\0" + rtype + "\0" + frm + "\0" + to)[:24]


# ------------------------------------------------------------------ type-aware parsers
FENCE_RE = re.compile(r"^(\s*)(```+|~~~+)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")


def parse_markdown(text, raw):
    """Return list of sections: {level, title, section_path, span{start,end}, line}. Fence-aware."""
    starts = line_byte_starts(raw)
    lines = text.split("\n")
    sections = []
    stack = []  # (level, title)
    in_fence = None
    heads = []  # (line_idx 0-based, level, title)
    for i, ln in enumerate(lines):
        fm = FENCE_RE.match(ln)
        if fm:
            marker = fm.group(2)[0]
            if in_fence is None:
                in_fence = marker
            elif in_fence == marker:
                in_fence = None
            continue
        if in_fence is not None:
            continue
        hm = HEADING_RE.match(ln)
        if hm:
            level = len(hm.group(1))
            title = hm.group(2).strip()
            heads.append((i, level, title))
    # build section spans: from a heading line start to the next heading of same-or-higher level (or EOF)
    for idx, (li, level, title) in enumerate(heads):
        # breadcrumb
        while stack and stack[-1][0] >= level:
            stack.pop()
        stack.append((level, title))
        section_path = " > ".join(t for (_l, t) in stack)
        start_byte = starts[li + 1] if (li + 1) < len(starts) else len(raw)
        # find next heading with level <= this level
        end_byte = len(raw)
        for j in range(idx + 1, len(heads)):
            lj, lvlj, _tj = heads[j]
            if lvlj <= level:
                end_byte = starts[lj + 1] if (lj + 1) < len(starts) else len(raw)
                break
        sections.append({
            "level": level, "title": title, "section_path": section_path,
            "span": {"start": start_byte, "end": end_byte}, "ordinal": idx,
        })
    return sections


PWSH_FUNC_RE = re.compile(r"^\s*(?:function|filter)\s+([A-Za-z_][A-Za-z0-9_\-]*)", re.IGNORECASE)
PWSH_CLASS_RE = re.compile(r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)", re.IGNORECASE)
PWSH_IMPORT_RE = re.compile(r"(?i)\bImport-Module\s+(?:-Name\s+)?['\"]?([^\s'\";|]+)")
PWSH_USING_RE = re.compile(r"(?i)^\s*using\s+module\s+['\"]?([^\s'\";|]+)")
PWSH_DOTSRC_RE = re.compile(r"""^\s*\.\s+['"]?([^\s'";|]+\.psm?1)['"]?""", re.IGNORECASE)


def parse_powershell(text, raw):
    """Deterministic regex extraction: function/class DEFS (signature-line span) + imports/dot-source."""
    starts = line_byte_starts(raw)
    lines = text.split("\n")
    symbols = []
    imports = []
    for i, ln in enumerate(lines):
        line_start = starts[i + 1] if (i + 1) < len(starts) else len(raw)
        line_end = starts[i + 2] if (i + 2) < len(starts) else len(raw)
        m = PWSH_FUNC_RE.match(ln)
        if m:
            symbols.append({"name": m.group(1), "kind": "function", "qual": m.group(1),
                            "span": {"start": line_start, "end": line_end}, "line": i + 1})
        m = PWSH_CLASS_RE.match(ln)
        if m:
            symbols.append({"name": m.group(1), "kind": "class", "qual": m.group(1),
                            "span": {"start": line_start, "end": line_end}, "line": i + 1})
        for im in PWSH_IMPORT_RE.finditer(ln):
            imports.append({"target": im.group(1), "kind": "import_module"})
        um = PWSH_USING_RE.match(ln)
        if um:
            imports.append({"target": um.group(1), "kind": "using_module"})
        dm = PWSH_DOTSRC_RE.match(ln)
        if dm:
            imports.append({"target": dm.group(1), "kind": "dot_source"})
    return symbols, imports


def parse_python(text, raw):
    """AST-based extraction: def/class symbols (line-region byte span) + imports. Raises on SyntaxError."""
    starts = line_byte_starts(raw)
    tree = ast.parse(text)
    symbols = []
    imports = []

    def span_of(node):
        ls = node.lineno
        le = getattr(node, "end_lineno", node.lineno) or node.lineno
        start = starts[ls] if ls < len(starts) else len(raw)
        end = starts[le + 1] if (le + 1) < len(starts) else len(raw)
        return {"start": start, "end": end}

    def sig_of(node):
        try:
            args = [a.arg for a in node.args.posonlyargs] if hasattr(node.args, "posonlyargs") else []
            args += [a.arg for a in node.args.args]
            if node.args.vararg: args.append("*" + node.args.vararg.arg)
            args += [a.arg for a in node.args.kwonlyargs]
            if node.args.kwarg: args.append("**" + node.args.kwarg.arg)
            return "(" + ", ".join(args) + ")"
        except Exception:
            return "()"

    def visit(node, prefix):
        for child in node.body:
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                qual = (prefix + "." + child.name) if prefix else child.name
                kind = "method" if prefix else "function"
                symbols.append({"name": child.name, "kind": kind, "qual": qual,
                                "signature": sig_of(child), "span": span_of(child), "line": child.lineno})
            elif isinstance(child, ast.ClassDef):
                qual = (prefix + "." + child.name) if prefix else child.name
                symbols.append({"name": child.name, "kind": "class", "qual": qual,
                                "signature": "", "span": span_of(child), "line": child.lineno})
                visit(child, qual)
    visit(tree, "")
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                imports.append({"target": a.name, "kind": "import"})
        elif isinstance(node, ast.ImportFrom):
            mod = ("." * (node.level or 0)) + (node.module or "")
            imports.append({"target": mod, "kind": "import_from"})
    # deterministic order
    symbols.sort(key=lambda s: (s["span"]["start"], s["qual"], s["kind"]))
    imports.sort(key=lambda x: (x["kind"], x["target"]))
    # de-dup imports
    seen = set(); uniq = []
    for im in imports:
        k = (im["kind"], im["target"])
        if k not in seen:
            seen.add(k); uniq.append(im)
    return symbols, uniq


def parse_skill_json(text):
    """Return a normalized skill descriptor, or raise on invalid JSON / missing skill_id."""
    obj = json.loads(text)
    if not isinstance(obj, dict) or "skill_id" not in obj:
        raise RepoError("not_a_manifest", "skill.json lacks skill_id")
    inv = obj.get("invocation") or {}
    inputs = obj.get("inputs") or []
    reqs = obj.get("requirements") or {}
    desc = {
        "skill_id": str(obj.get("skill_id")),
        "name": str(obj.get("name", "")),
        "version": str(obj.get("version", "")),
        "contract_version": str(obj.get("contract_version", "")),
        "determinism": str(obj.get("determinism", "")),
        "parallel_safe": bool(obj.get("parallel_safe", False)),
        "batch": bool(obj.get("batch", False)),
        "streaming": bool(obj.get("streaming", False)),
        "method": str(inv.get("method", "")),
        "entrypoint": str(inv.get("entrypoint", "")),
        "input_names": sorted(str(i.get("name")) for i in inputs if isinstance(i, dict) and i.get("name")),
        "purpose": str(obj.get("purpose", ""))[:280],
        "requirements": {
            "network": bool(reqs.get("network", False)),
            "gpu": str(reqs.get("gpu", "")),
            "filesystem": str(reqs.get("filesystem", "")),
        },
    }
    # schema-id tokens declared in the manifest -> schemas this module PRODUCES
    schema_ids = sorted(set(SCHEMA_ID_RE.findall(text)))
    return desc, schema_ids


SCHEMA_ID_RE = re.compile(r"[a-z_][a-z0-9_.]*\.[a-z0-9_.]+/[0-9]+(?:\.[0-9]+)*")
# Generic contract/envelope wire-schema ids -- present in every skill.json; NOT domain producer/consumer signal.
GENERIC_SCHEMAS = {
    "lifeorch.skill.manifest/0.1", "lifeorch.skill.result/0.1", "lifeorch.skill.invocation_report/0.1",
}


def parse_json_config(text):
    """Top-level structural keys of a JSON config (deterministic). Raises on invalid JSON."""
    obj = json.loads(text)
    if isinstance(obj, dict):
        keys = sorted(str(k) for k in obj.keys())
        return {"kind": "object", "top_level_keys": keys[:200], "key_count": len(obj)}
    if isinstance(obj, list):
        return {"kind": "array", "length": len(obj)}
    return {"kind": "scalar", "type": type(obj).__name__}


# ------------------------------------------------------------------ index op
def _load_roots_manifest(path):
    """i63 (D-0162): load the declarative corpus-roots manifest (ops/repo-intel-roots.json). Roots are
    repo-relative + resolve against the manifest's repo root (its grandparent dir), so indexing is
    CWD-independent. Lets the ordinary corpus (modules/ + core-docs/) plus a NARROW explicit backing root
    (ops/close-txn/spec) be indexed together, so ops/ backing is discoverable through the machinery (INV-15)."""
    with open(path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    roots = doc.get("roots")
    if not isinstance(roots, list) or not roots:
        raise RepoError("bad_roots_manifest", "roots manifest %s has no non-empty 'roots' list" % path)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(path)))
    out = []
    for r in roots:
        if not isinstance(r, str) or not r:
            raise RepoError("bad_roots_manifest", "roots manifest entry not a non-empty string: %r" % r)
        out.append(os.path.join(repo_root, r.replace("/", os.sep)))
    return out


def do_index(args):
    op = "index"
    roots = args.get("roots")
    if not roots:
        r = args.get("root")
        roots = [r] if r else None
    if not roots:
        rm = args.get("roots_manifest")
        if rm:
            roots = _load_roots_manifest(rm)
    if not roots:
        raise RepoError("missing_root", "index needs -Roots/-Root/-RootsManifest (roots[]/root/roots_manifest)")
    namespace = slug(args.get("namespace") or args.get("source_label") or "life-orchestrator")
    exclude_dirs = args.get("exclude_dirs") or DEFAULT_EXCLUDE_DIRS
    exclude_globs = args.get("exclude_globs") or DEFAULT_EXCLUDE_GLOBS
    include_globs = args.get("include_globs") or []
    file_budget = int(args.get("file_budget") or 0)
    outdir = args.get("output_dir")

    # ---- inventory across all roots (each root walked independently; rel paths are root-relative,
    #      prefixed by the root label so multiple roots never collide) ----
    inv = []
    budget_hit = False
    excluded_total = 0
    per_root_budget = file_budget
    for root in roots:
        root = os.path.abspath(root)
        if not os.path.isdir(root):
            raise RepoError("root_not_found", "root not found: %s" % root)
        root_label = os.path.basename(root.rstrip("/\\")) or "root"
        files, bh, exc = walk_inventory(root, exclude_dirs, exclude_globs, include_globs, per_root_budget)
        budget_hit = budget_hit or bh
        excluded_total += exc
        for f in files:
            f["root_label"] = root_label
            f["root_abs"] = root
            # namespaced repo-relative path: "<root_label>/<rel>" so multi-root corpora are unambiguous
            f["rel"] = root_label + "/" + f["rel"] if len(roots) > 1 else f["rel"]
            inv.append(f)
    inv.sort(key=lambda f: f["rel"])

    # ---- deterministic content-derived ingest run id (never wall-clock) ----
    corpus_key = namespace + "\0" + "\n".join(
        (f["rel"] + "\t" + (f["content_hash"] or "READFAIL")) for f in inv
    )
    ingest_run_id = "ingest_" + _h(corpus_key)[:24]

    em = Emitter(namespace, ingest_run_id)
    parse_failures = []

    # ---- folder + module entity registry (created on demand, deterministic) ----
    folder_children = {}   # folder_rel -> list of child record_ids
    module_files = {}      # module_rel -> {"nn":.., "files":[file_rel...]}

    def ensure_folder_chain(file_rel):
        parts = file_rel.split("/")
        # register file under its immediate folder
        for depth in range(len(parts) - 1, -1, -1):
            folder = "/".join(parts[:depth]) if depth > 0 else ""
            folder_children.setdefault(folder, [])

    # first pass: file entities + per-type parse -> symbol/summary/skill records + collect imports
    pending_imports = []   # (from_file_rel, target, kind)
    module_schemas_produced = {}  # module_rel -> set(schema_id)
    module_schema_tokens = {}     # module_rel -> set(schema_id) seen anywhere in module text (for consumer detect)
    skill_module = []             # (skill_record_id, module_rel)

    for f in inv:
        rel = f["rel"]
        chash = f["content_hash"]
        st = f["source_type"]
        mrel, mnn = module_of(rel)
        if mrel:
            module_files.setdefault(mrel, {"nn": mnn, "files": []})["files"].append(rel)
        # read failure during inventory
        if f["error"] is not None:
            parse_failures.append({"rel": rel, "reason": "read_failed", "detail": f["error"]})
            continue
        raw = f["raw"]
        # decode
        text = None
        if b"\x00" in raw:
            parse_failures.append({"rel": rel, "reason": "binary", "detail": "NUL byte present"})
        elif len(raw) > MAX_FILE_BYTES:
            parse_failures.append({"rel": rel, "reason": "oversize", "detail": "%d bytes > %d" % (len(raw), MAX_FILE_BYTES)})
        else:
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError as e:
                parse_failures.append({"rel": rel, "reason": "not_utf8", "detail": str(e)})
                text = None

        # ---- file entity ----
        fid = id_file(namespace, rel)
        parent_folder = "/".join(rel.split("/")[:-1])
        ensure_folder_chain(rel)
        file_payload = {
            "entity_type": "file", "path": rel, "source_type": st,
            "size_bytes": f["size"], "content_hash": chash,
            "text": os.path.basename(rel),
        }
        file_rec = em.add(fid, "entity", file_payload, source_rel=rel, file_hash=chash,
                          span={"start": 0, "end": f["size"]}, parser_fp=FP["inventory"])
        folder_children.setdefault(parent_folder, [])
        if fid not in folder_children[parent_folder]:
            folder_children[parent_folder].append(fid)

        if text is None:
            continue  # parse failure already surfaced; entity still emitted (inventory-complete)

        # collect any schema-id tokens in this file for module consumer detection
        if mrel:
            for tok in SCHEMA_ID_RE.findall(text):
                if tok not in GENERIC_SCHEMAS:
                    module_schema_tokens.setdefault(mrel, set()).add(tok)

        # ---- per-type parse ----
        try:
            if st == "markdown":
                sections = parse_markdown(text, raw)
                sec_ids = []
                for sec in sections:
                    sid = id_secsum(namespace, rel, sec["section_path"], sec["ordinal"])
                    payload = {"summary_type": "markdown_section", "path": rel,
                               "heading": sec["title"], "level": sec["level"],
                               "section_path": sec["section_path"],
                               "text": sec["section_path"]}
                    em.add(sid, "summary", payload, source_rel=rel, file_hash=chash,
                           span=sec["span"], parser_fp=FP["md"],
                           parent_edges=[edge("section_of", fid)])
                    sec_ids.append(sid)
                    file_rec["child_edges"].append(edge("has_section", sid))
                # file outline summary
                osid = id_filesum(namespace, rel)
                outline = {"summary_type": "file_outline", "path": rel, "source_type": st,
                           "section_count": len(sections),
                           "sections": [s["section_path"] for s in sections],
                           "text": rel + " :: " + " | ".join(s["title"] for s in sections)}
                em.add(osid, "summary", outline, source_rel=rel, file_hash=chash,
                       span={"start": 0, "end": f["size"]}, extractor_fp=FP["summary"],
                       parent_edges=[edge("outline_of", fid)],
                       child_edges=[edge("includes_section", s) for s in sec_ids])
                file_rec["child_edges"].append(edge("has_outline", osid))

            elif st == "powershell":
                symbols, imports = parse_powershell(text, raw)
                sym_ids = _emit_symbols(em, namespace, rel, chash, fid, symbols, "powershell", file_rec)
                for im in imports:
                    pending_imports.append((rel, im["target"], im["kind"]))
                _emit_file_outline(em, namespace, rel, chash, st, fid, symbols, file_rec, f["size"])

            elif st == "python":
                try:
                    symbols, imports = parse_python(text, raw)
                except SyntaxError as e:
                    parse_failures.append({"rel": rel, "reason": "python_syntax_error",
                                           "detail": "line %s: %s" % (getattr(e, "lineno", "?"), e.msg)})
                    symbols, imports = [], []
                sym_ids = _emit_symbols(em, namespace, rel, chash, fid, symbols, "python", file_rec)
                for im in imports:
                    pending_imports.append((rel, im["target"], im["kind"]))
                _emit_file_outline(em, namespace, rel, chash, st, fid, symbols, file_rec, f["size"])

            elif st == "skill_manifest":
                try:
                    desc, schema_ids = parse_skill_json(text)
                except (json.JSONDecodeError, RepoError) as e:
                    reason = "invalid_json" if isinstance(e, json.JSONDecodeError) else e.code
                    parse_failures.append({"rel": rel, "reason": reason, "detail": str(e)})
                else:
                    skid = id_skill(namespace, desc["skill_id"])
                    payload = dict(desc)
                    payload["path"] = rel
                    payload["text"] = desc["skill_id"] + " " + desc["name"] + " " + desc["purpose"]
                    em.add(skid, "skill", payload, source_rel=rel, file_hash=chash,
                           span={"start": 0, "end": f["size"]}, parser_fp=FP["skill"],
                           parent_edges=[edge("declared_in", fid)])
                    file_rec["child_edges"].append(edge("declares_skill", skid))
                    if mrel:
                        skill_module.append((skid, mrel))
                        module_schemas_produced.setdefault(mrel, set()).update(
                            s for s in schema_ids if s not in GENERIC_SCHEMAS)

            elif st == "json":
                try:
                    struct = parse_json_config(text)
                except json.JSONDecodeError as e:
                    parse_failures.append({"rel": rel, "reason": "invalid_json", "detail": str(e)})
                else:
                    csid = id_filesum(namespace, rel)
                    payload = {"summary_type": "json_config", "path": rel}
                    payload.update(struct)
                    payload["text"] = rel + " :: " + ",".join(struct.get("top_level_keys", []))
                    em.add(csid, "summary", payload, source_rel=rel, file_hash=chash,
                           span={"start": 0, "end": f["size"]}, parser_fp=FP["jsonconfig"],
                           parent_edges=[edge("structure_of", fid)])
                    file_rec["child_edges"].append(edge("has_structure", csid))

            else:  # text / other -> minimal deterministic file summary (line count)
                nlines = text.count("\n") + (0 if text.endswith("\n") or text == "" else 1)
                tsid = id_filesum(namespace, rel)
                payload = {"summary_type": "text_file", "path": rel, "source_type": st,
                           "line_count": nlines, "byte_count": f["size"],
                           "text": os.path.basename(rel)}
                em.add(tsid, "summary", payload, source_rel=rel, file_hash=chash,
                       span={"start": 0, "end": f["size"]}, parser_fp=FP["text"],
                       parent_edges=[edge("summary_of", fid)])
                file_rec["child_edges"].append(edge("has_summary", tsid))
        except Exception as e:  # never crash the whole index on one file
            parse_failures.append({"rel": rel, "reason": "parser_exception",
                                   "detail": repr(e)[:300]})

    # ---- folder + module entities ----
    all_folders = sorted(folder_children.keys())
    for folder in all_folders:
        fid = id_dir(namespace, folder)
        children = sorted(set(folder_children[folder]))
        # child subfolders
        subchildren = []
        for other in all_folders:
            if other == folder:
                continue
            op_parent = "/".join(other.split("/")[:-1]) if other else ""
            if op_parent == folder and other != "":
                subchildren.append(id_dir(namespace, other))
        payload = {"entity_type": "folder", "path": folder or ".",
                   "file_count": len(children), "subfolder_count": len(subchildren),
                   "text": (folder or ".")}
        parent_folder = "/".join(folder.split("/")[:-1]) if folder else None
        pedges = []
        if folder:
            pedges = [edge("contained_in", id_dir(namespace, parent_folder if parent_folder else ""))]
        cedges = ([edge("contains_file", c) for c in children] +
                  [edge("contains_folder", s) for s in sorted(set(subchildren))])
        em.add(fid, "entity", payload, derivation_refs=children + sorted(set(subchildren)),
               extractor_fp=FP["summary"], parent_edges=pedges, child_edges=cedges)

    # module entities + relationships
    for mrel in sorted(module_files.keys()):
        info = module_files[mrel]
        mid = id_module(namespace, mrel)
        file_ids = sorted(id_file(namespace, r) for r in info["files"])
        payload = {"entity_type": "module", "path": mrel, "module_nn": info["nn"],
                   "file_count": len(info["files"]), "text": mrel}
        em.add(mid, "entity", payload, derivation_refs=file_ids, extractor_fp=FP["relationships"],
               child_edges=[edge("contains_file", fi) for fi in file_ids])
        # file -> module relationships + test -> module
        for r in sorted(info["files"]):
            frid = id_file(namespace, r)
            rid = id_rel(namespace, "in_module", frid, mid)
            em.add(rid, "relationship",
                   {"relationship_type": "in_module", "from": r, "to": mrel,
                    "text": r + " in_module " + mrel},
                   extractor_fp=FP["relationships"],
                   derivation_refs=[frid, mid])
            if is_test_path(r):
                trid = id_rel(namespace, "tests", frid, mid)
                em.add(trid, "relationship",
                       {"relationship_type": "tests", "from": r, "to": mrel,
                        "text": r + " tests " + mrel},
                       extractor_fp=FP["relationships"], derivation_refs=[frid, mid])

    # skill -> module BELONGS_TO
    for skid, mrel in sorted(skill_module):
        mid = id_module(namespace, mrel)
        rid = id_rel(namespace, "skill_of_module", skid, mid)
        em.add(rid, "relationship",
               {"relationship_type": "skill_of_module", "from": skid, "to": mrel,
                "text": skid + " skill_of_module " + mrel},
               extractor_fp=FP["relationships"], derivation_refs=[skid, mid])

    # schema producer relationships (module -> schema id it declares)
    for mrel in sorted(module_schemas_produced.keys()):
        mid = id_module(namespace, mrel)
        for sid in sorted(module_schemas_produced[mrel]):
            rid = id_rel(namespace, "produces_schema", mid, sid)
            em.add(rid, "relationship",
                   {"relationship_type": "produces_schema", "from": mrel, "to": sid,
                    "text": mrel + " produces_schema " + sid},
                   extractor_fp=FP["relationships"], derivation_refs=[mid],
                   child_edges=[edge("schema", external=True, external_ref=sid)])
    # schema consumer relationships (module references a schema it does NOT itself produce)
    for mrel in sorted(module_schema_tokens.keys()):
        mid = id_module(namespace, mrel)
        produced = module_schemas_produced.get(mrel, set())
        for sid in sorted(module_schema_tokens[mrel] - produced):
            rid = id_rel(namespace, "consumes_schema", mid, sid)
            em.add(rid, "relationship",
                   {"relationship_type": "consumes_schema", "from": mrel, "to": sid,
                    "text": mrel + " consumes_schema " + sid},
                   extractor_fp=FP["relationships"], derivation_refs=[mid],
                   child_edges=[edge("schema", external=True, external_ref=sid)])

    # ---- import relationships (resolve target to an in-corpus file when possible, else external) ----
    rel_by_basename = {}
    file_rel_set = set(f["rel"] for f in inv)
    for f in inv:
        rel_by_basename.setdefault(os.path.basename(f["rel"]).lower(), []).append(f["rel"])
    for (from_rel, target, kind) in pending_imports:
        frid = id_file(namespace, from_rel)
        resolved_rel = _resolve_import(target, from_rel, file_rel_set, rel_by_basename)
        if resolved_rel:
            trid = id_file(namespace, resolved_rel)
            rid = id_rel(namespace, "imports", from_rel, resolved_rel)
            em.add(rid, "relationship",
                   {"relationship_type": "imports", "import_kind": kind, "external": False,
                    "from": from_rel, "to": resolved_rel, "target": target,
                    "text": from_rel + " imports " + resolved_rel},
                   extractor_fp=FP["relationships"], derivation_refs=[frid, trid])
        else:
            rid = id_rel(namespace, "imports_ext", from_rel, target)
            em.add(rid, "relationship",
                   {"relationship_type": "imports", "import_kind": kind,
                    "from": from_rel, "to": None, "target": target, "external": True,
                    "text": from_rel + " imports(ext) " + target},
                   extractor_fp=FP["relationships"], derivation_refs=[frid],
                   child_edges=[edge("import_target", external=True, external_ref=target)])

    # ---- deterministic global order ----
    kind_order = {k: i for i, k in enumerate(("entity", "skill", "symbol", "summary", "relationship"))}
    em.records.sort(key=lambda r: (
        kind_order.get(r["record_kind"], 99),
        r["source_path"] or "",
        (r["source_span"] or {}).get("start", 0) if r.get("source_span") else 0,
        r["record_id"],
    ))

    # ---- validate ----
    validation = validate_records(em.records)

    # ---- counts ----
    counts_by_kind = {}
    for r in em.records:
        counts_by_kind[r["record_kind"]] = counts_by_kind.get(r["record_kind"], 0) + 1

    records_digest = _records_digest(em.records)

    manifest = {
        "schema": "lifeorch.repo_intel.index_manifest/0.1",
        "namespace": namespace,
        "roots": [os.path.basename(os.path.abspath(r).rstrip("/\\")) for r in roots],
        "created_by_ingest_run": ingest_run_id,
        "total_records": len(em.records),
        "record_counts_by_kind": counts_by_kind,
        "record_kinds": sorted(counts_by_kind.keys()),
        "records_digest": records_digest,
        "file_count": len(inv),
        "excluded_count": excluded_total,
        "file_budget": file_budget,
        "file_budget_hit": budget_hit,
        "parse_failure_count": len(parse_failures),
        "parse_failures": sorted(parse_failures, key=lambda p: (p["rel"], p["reason"])),
        "validation": {"ok": validation["ok"], "checked": validation["checked"],
                       "error_count": len(validation["errors"]),
                       "errors": validation["errors"][:50]},
        "edge_summary": validation["edge_summary"],
        "fingerprints": FP,
        "worker_version": WORKER_VERSION,
    }

    inventory_out = {
        "schema": "lifeorch.repo_intel.inventory/0.1",
        "namespace": namespace,
        "files": [{"path": f["rel"], "source_type": f["source_type"],
                   "size_bytes": f["size"], "content_hash": f["content_hash"]} for f in inv],
    }

    ingest_records_payload = {
        "schema": INGEST_SCHEMA,
        "namespace": namespace,
        "created_by_ingest_run": ingest_run_id,
        "record_count": len(em.records),
        "records": em.records,
    }

    outputs = []
    if outdir:
        outputs = _write_artifacts(outdir, em.records, manifest, inventory_out,
                                   ingest_records_payload, parse_failures)

    return {
        "op": op, "namespace": namespace,
        "total_records": len(em.records),
        "record_counts_by_kind": counts_by_kind,
        "record_kinds": sorted(counts_by_kind.keys()),
        "records_digest": records_digest,
        "file_count": len(inv),
        "excluded_count": excluded_total,
        "file_budget_hit": budget_hit,
        "parse_failures": manifest["parse_failures"],
        "parse_failure_count": len(parse_failures),
        "validation": manifest["validation"],
        "edge_summary": validation["edge_summary"],
        "ingest_run_id": ingest_run_id,
        "outputs": outputs,
    }


def _resolve_import(target, from_rel, file_rel_set, rel_by_basename):
    """Best-effort deterministic resolution of an import/dot-source target to an in-corpus file rel."""
    t = target.strip().strip("'\"")
    if not t:
        return None
    # dot-source of a relative .ps1/.psm1 path
    tnorm = t.replace("\\", "/")
    base = os.path.basename(tnorm)
    # try direct join relative to the importing file's folder
    from_dir = "/".join(from_rel.split("/")[:-1])
    for cand in (
        _norm_join(from_dir, tnorm),
        tnorm.lstrip("./"),
    ):
        if cand in file_rel_set:
            return cand
    # python module path a.b.c -> a/b/c.py (only if uniquely present by basename)
    if base and "." in base and base.lower().endswith((".ps1", ".psm1")):
        hits = rel_by_basename.get(base.lower(), [])
        if len(hits) == 1:
            return hits[0]
    return None


def _norm_join(base_dir, rel):
    parts = []
    combined = (base_dir + "/" + rel) if base_dir else rel
    for seg in combined.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if parts:
                parts.pop()
            continue
        parts.append(seg)
    return "/".join(parts)


_LANG_FP = {"powershell": "pwsh", "python": "python"}
def _emit_symbols(em, ns, rel, chash, fid, symbols, language, file_rec):
    fp = FP[_LANG_FP.get(language, language)]
    sym_ids = []
    for s in symbols:
        sid = id_symbol(ns, rel, s["qual"], s["kind"])
        payload = {"symbol_type": s["kind"], "name": s["name"], "qualified_name": s["qual"],
                   "language": language, "signature": s.get("signature", ""),
                   "line": s.get("line"), "path": rel,
                   "text": s["qual"] + s.get("signature", "")}
        em.add(sid, "symbol", payload, source_rel=rel, file_hash=chash, span=s["span"],
               parser_fp=fp, parent_edges=[edge("defined_in", fid)])
        file_rec["child_edges"].append(edge("defines", sid))
        sym_ids.append(sid)
    return sym_ids


def _emit_file_outline(em, ns, rel, chash, st, fid, symbols, file_rec, size):
    osid = id_filesum(ns, rel)
    payload = {"summary_type": "file_outline", "path": rel, "source_type": st,
               "symbol_count": len(symbols),
               "symbols": [s["qual"] for s in symbols],
               "text": rel + " :: " + " | ".join(s["qual"] for s in symbols)}
    em.add(osid, "summary", payload, source_rel=rel, file_hash=chash,
           span={"start": 0, "end": size}, extractor_fp=FP["summary"],
           parent_edges=[edge("outline_of", fid)],
           child_edges=[edge("includes_symbol", id_symbol(ns, rel, s["qual"], s["kind"])) for s in symbols])
    file_rec["child_edges"].append(edge("has_outline", osid))
    return osid


# ------------------------------------------------------------------ validator (s1)
S1_REQUIRED = ("record_id", "record_version_id", "record_kind", "namespace", "content_hash",
               "status", "authority_level", "sensitivity_class", "valid_from", "valid_to",
               "created_by_ingest_run", "source_version_id", "source_span", "derivation_refs",
               "parser_fingerprint", "chunker_fingerprint", "extractor_fingerprint",
               "schema_version", "token_count", "embedding_space_id", "parent_edges", "child_edges")


def validate_records(records):
    errors = []
    ids = set(r["record_id"] for r in records)
    edge_total = 0
    edge_resolved = 0
    edge_external = 0
    for r in records:
        rid = r.get("record_id", "?")
        for fld in S1_REQUIRED:
            if fld not in r:
                errors.append("%s: missing field %s" % (rid, fld))
        if r.get("record_kind") not in RECORD_KINDS:
            errors.append("%s: bad record_kind %r" % (rid, r.get("record_kind")))
        # id derivation integrity
        payload = r.get("payload")
        if payload is not None:
            ch = _h(canon(payload))
            if ch != r.get("content_hash"):
                errors.append("%s: content_hash mismatch" % rid)
            expect_rv = "rv_" + _h(r["record_id"] + "\0" + ch)[:24]
            if expect_rv != r.get("record_version_id"):
                errors.append("%s: record_version_id derivation mismatch" % rid)
        # span OR derivation_refs present
        span = r.get("source_span")
        drefs = r.get("derivation_refs") or []
        if span is not None:
            if not (isinstance(span, dict) and "start" in span and "end" in span):
                errors.append("%s: source_span not a {start,end} object" % rid)
            elif span["start"] is not None and span["end"] is not None and span["start"] > span["end"]:
                errors.append("%s: span start>end" % rid)
        elif not drefs:
            errors.append("%s: neither source_span nor derivation_refs present" % rid)
        # edge endpoint integrity
        for e in (r.get("parent_edges") or []) + (r.get("child_edges") or []):
            edge_total += 1
            if e.get("external"):
                edge_external += 1
                if not e.get("external_ref"):
                    errors.append("%s: external edge missing external_ref" % rid)
            else:
                tgt = e.get("target_record_id")
                if tgt in ids:
                    edge_resolved += 1
                else:
                    errors.append("%s: edge target unresolved: %s (%s)" % (rid, tgt, e.get("edge_type")))
        # relationship record derivation_refs must resolve (except explicit external targets)
        if r.get("record_kind") == "relationship":
            for dref in drefs:
                if dref not in ids:
                    errors.append("%s: relationship derivation_ref unresolved: %s" % (rid, dref))
    return {
        "ok": len(errors) == 0,
        "checked": len(records),
        "errors": errors,
        "edge_summary": {"total": edge_total, "resolved_internal": edge_resolved, "external": edge_external},
    }


def _records_digest(records):
    lines = []
    for r in records:
        lines.append("\t".join([
            r["record_kind"], r["record_id"], r["record_version_id"], r["content_hash"],
            r.get("source_path") or "", str((r.get("source_span") or {}).get("start", "")),
            str((r.get("source_span") or {}).get("end", "")),
        ]))
    lines.sort()
    return _h("\n".join(lines))


# ------------------------------------------------------------------ artifact writing (canonical)
def _write_text(path, s):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(s)


def _write_artifacts(outdir, records, manifest, inventory_out, ingest_payload, parse_failures):
    os.makedirs(outdir, exist_ok=True)
    outputs = []

    # records.jsonl -- one canonical record per line, deterministic order (THE ingest payload)
    p = os.path.join(outdir, "records.jsonl")
    _write_text(p, "".join(canon(r) + "\n" for r in records))
    outputs.append({"path": os.path.abspath(p), "kind": "jsonl", "name": "records.jsonl"})

    # records.json -- canonical array
    p = os.path.join(outdir, "records.json")
    _write_text(p, canon(records))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "records.json"})

    # ingest_records.json -- the #36 0.2 ingest_records drop-in
    p = os.path.join(outdir, "ingest_records.json")
    _write_text(p, canon(ingest_payload))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "ingest_records.json"})

    # index_manifest.json -- canonical (no timestamps/abs paths)
    p = os.path.join(outdir, "index_manifest.json")
    _write_text(p, canon(manifest))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "index_manifest.json"})

    # inventory.json -- canonical
    p = os.path.join(outdir, "inventory.json")
    _write_text(p, canon(inventory_out))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "inventory.json"})

    # parse_failures.json
    p = os.path.join(outdir, "parse_failures.json")
    _write_text(p, canon(sorted(parse_failures, key=lambda x: (x["rel"], x["reason"]))))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "parse_failures.json"})

    # summary.md -- deterministic human-readable structural summary
    p = os.path.join(outdir, "summary.md")
    _write_text(p, _render_summary_md(manifest, records))
    outputs.append({"path": os.path.abspath(p), "kind": "markdown", "name": "summary.md"})

    return outputs


def _render_summary_md(manifest, records):
    lines = []
    lines.append("# repo.intel index -- %s" % manifest["namespace"])
    lines.append("")
    lines.append("roots: %s" % ", ".join(manifest["roots"]))
    lines.append("records: %d  files: %d  parse_failures: %d" % (
        manifest["total_records"], manifest["file_count"], manifest["parse_failure_count"]))
    lines.append("records_digest: %s" % manifest["records_digest"])
    lines.append("")
    lines.append("## record kinds")
    lines.append("")
    for k in sorted(manifest["record_counts_by_kind"].keys()):
        lines.append("- %s: %d" % (k, manifest["record_counts_by_kind"][k]))
    lines.append("")
    lines.append("## edges")
    lines.append("")
    es = manifest["edge_summary"]
    lines.append("- total: %d  resolved_internal: %d  external: %d" % (
        es["total"], es["resolved_internal"], es["external"]))
    lines.append("")
    if manifest["parse_failures"]:
        lines.append("## parse failures (surfaced, not dropped)")
        lines.append("")
        for pf in manifest["parse_failures"]:
            lines.append("- %s: %s (%s)" % (pf["rel"], pf["reason"], pf.get("detail", "")[:80]))
        lines.append("")
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------ validate op (standalone)
def do_validate(args):
    rp = args.get("records_path")
    if not rp or not os.path.isfile(rp):
        raise RepoError("records_not_found", "validate needs records_path (records.jsonl or records.json)")
    records = []
    with open(rp, "r", encoding="utf-8") as fh:
        content = fh.read()
    if rp.endswith(".jsonl"):
        for line in content.splitlines():
            line = line.strip()
            if line:
                records.append(json.loads(line))
    else:
        obj = json.loads(content)
        records = obj["records"] if isinstance(obj, dict) and "records" in obj else obj
    v = validate_records(records)
    return {"op": "validate", "records_path": os.path.abspath(rp), "checked": v["checked"],
            "validation": {"ok": v["ok"], "checked": v["checked"], "error_count": len(v["errors"]),
                           "errors": v["errors"][:50]},
            "edge_summary": v["edge_summary"], "outputs": []}


# ------------------------------------------------------------------ main
def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: repo_intel.py <args.json>\n")
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

    op = str(args.get("op", "index")).lower()
    try:
        if op == "index":
            payload = do_index(args)
        elif op == "validate":
            payload = do_validate(args)
        else:
            raise RepoError("invalid_op", "unknown op '%s' (index|validate)" % op)
        meta = {"ok": True, "runtime_ms": int((time.time() - t0) * 1000),
                "worker": {"name": "repo.intel", "version": WORKER_VERSION,
                           "python": sys.version.split()[0]}}
        meta.update(payload)
        # partial if any parse failures surfaced
        meta["warnings"] = []
        if payload.get("parse_failures"):
            meta["warnings"] = ["%d parse failure(s) surfaced" % len(payload["parse_failures"])]
        write_meta(meta)
        sys.stdout.write("REPO_INTEL_OK op=%s records=%s\n" % (op, payload.get("total_records", "-")))
        return 0
    except RepoError as re_:
        write_meta({"ok": False, "error_code": re_.code, "error": re_.message,
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("%s: %s\n" % (re_.code, re_.message))
        return 1
    except Exception as e:
        tb = traceback.format_exc()
        sys.stderr.write(tb + "\n")
        write_meta({"ok": False, "error_code": "repo_intel_failed", "error": repr(e)[:500],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
