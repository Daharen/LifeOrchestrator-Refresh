#!/usr/bin/env python
# skill_card.py -- deterministic skill-card generator + skill index + Stage-1 eligibility
# + Stage-2 lexical-retrieval seam for Life Orchestrator (Module 41, skill `skill.card`, Wave 3).
#
# CPU-only, Python STDLIB ONLY (json, hashlib, re, os, sys, time, traceback -- NO third-party),
# NO model, NO network. Turns each module's skill.json (+ sibling README/WORK_ORDER) into a COMPACT,
# model-facing SKILL CARD (directive section 9 "Skill card format"), emits each card as a
# MEMORY_CONTRACT s1 `skill` record-envelope artifact (drop-in for #36 0.2 `ingest_records`), and ships
# a DETERMINISTIC Stage-1 eligibility filter + a DETERMINISTIC Stage-2 lexical retrieval baseline over
# the card index (the semantic-retrieval SEAM; real embeddings fold in at the retrieval wave).
#
# Invoked by Invoke-SkillCard.ps1 with argv[1] = a JSON args file:
#   { op: cards|eligible|retrieve|validate, roots|root, namespace, cards_path?, records_path?,
#     query?, k?, task?{...}, exclude_dirs?, output_dir, meta_path }
# The worker writes canonical artifacts + a meta.json; the wrapper hashes them + emits the envelope.
#
# DETERMINISM: identical corpus CONTENT => byte-identical canonical artifacts across runs AND machines.
#   All ids are content+path derived; NO absolute paths, timestamps, or wall-clock ids in any canonical
#   artifact. canon() = json.dumps(sort_keys, ascii, no-spaces). (D-0077 / MEMORY_CONTRACT s1.)
import os
import sys
import json
import time
import hashlib
import re
import traceback

WORKER_VERSION = "0.2.0"
RECORD_SCHEMA = "lifeorch.skill_card.record/0.1"
INGEST_SCHEMA = "lifeorch.skill_card.ingest_records/0.1"
CARD_SCHEMA = "lifeorch.skill_card.card/0.1"

# The full frozen MEMORY_CONTRACT s1 record_kind enum (D-0085, CLOSED). skill.card EMITS `summary`
# (a skill-ACTIVATION card that DERIVES FROM #38's structural `skill` record -- Amendment A3, D-0087) so
# repo.intel #38 stays the SOLE `record_kind=skill` owner; the validator accepts the whole enum for
# forward-compat / validating foreign records.
S1_RECORD_KINDS = ("symbol", "summary", "decision", "claim", "episode", "failure",
                   "procedure", "skill", "reminder", "entity", "relationship")
EMITTED_KIND = "summary"                  # A3 (D-0087): skill.card is a `summary` producer, NOT a 2nd `skill`
SUMMARY_TYPE = "skill_activation_card"    # attrs.summary_type (A3) -- distinguishes the card from #38's summaries
EDGE_DERIVES_FROM = "derives_from"        # A3: navigational derivative edge to #38's structural `skl_` record

# parser / extractor fingerprints (name;version;options) -- a version change invalidates derived records (s4)
FP_MANIFEST = "skill.card.manifest/0.1;json"       # parses the skill.json manifest
FP_CARDGEN = "skill.card.cardgen/0.2;section9;summary-activation"  # A3 kind flip -> derivation version bump (s4)

STATUS_CURRENT = "current"          # s5: a freshly-produced record is current (the STRING form, D-0085)
AUTHORITY_DERIVED = "derived"       # s1: the card is a DERIVED activation view (BOUNDARY vs #38's "canonical_source")
SENSITIVITY = "repo_internal"       # s7: single value now; the field is present from day one

# ---- privacy exclusions for skill DISCOVERY (s7 -- TESTED). We only ever open skill.json + sibling
#      README.md / WORK_ORDER.md, so model/binary globs are irrelevant; we prune noise + nested corpora. ----
DEFAULT_EXCLUDE_DIRS = [
    ".git", "runtime", "artifacts", "__pycache__", "node_modules", ".vs", ".idea",
    "bin", "obj", ".pytest_cache", "_to_delete", "venv", ".venv", "env", "python_env",
    ".mypy_cache", ".ipynb_checkpoints",
    # skill.card-specific: never descend into a module's fixtures/tests/examples (nested skill.json
    # manifests there are NOT real skills of the corpus) -- keeps the real modules/ discovery to the
    # top-level modules/<NN>-*/skill.json set.
    "fixtures", "tests", "examples",
]
MAX_DOC_BYTES = 256 * 1024          # sibling README/WORK_ORDER read cap
MAX_SKILL_JSON_BYTES = 2 * 1024 * 1024

# ---- card size bounds (the COMPACT model-facing view, NOT the full docs) ----
CAP_PURPOSE = 400
CAP_INPUT_DESC = 140
CAP_INPUTS = 40
CAP_OPERATIONS = 40
CAP_EXAMPLE = 600
CAP_ARTIFACTS = 300
CAP_LIST_ITEM = 160
CAP_TEXT = 1600

# section-9 card fields that must be present for a card to be "ok"
SECTION9_FIELDS = ("purpose", "operations", "inputs", "example", "preconditions", "side_effects",
                   "artifacts", "latency_class", "resource_class", "completion_checks",
                   "failure_conditions", "version_health")


class CardError(Exception):
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
    return os.path.relpath(path, root).replace(os.sep, "/")


def cap(s, n):
    if s is None:
        return ""
    s = str(s)
    if len(s) <= n:
        return s
    return s[:n].rstrip() + "..."


def token_count(text):
    """Deterministic token estimate: whitespace-delimited tokens."""
    if not text:
        return 0
    return len(text.split())


# lexical tokenizer (Stage 2 baseline): lowercase, split on non-alphanumerics, drop tiny/stop tokens.
_TOKEN_RE = re.compile(r"[a-z0-9]+")
STOPWORDS = frozenset("""
a an and are as at be by for from in into is it its of on or over the their them then there these this to
with without your you our we us do does done can could should would may might will shall via per each any all
some no not that which who whom whose what when where how why be been being have has had a's it's
""".split())


def tokenize(text):
    if not text:
        return []
    out = []
    for m in _TOKEN_RE.findall(text.lower()):
        if len(m) <= 1:
            continue
        if m in STOPWORDS:
            continue
        out.append(m)
    return out


def _pascalish_ok(tok):
    return bool(re.fullmatch(r"[a-z][a-z0-9._-]*", tok or ""))


# ------------------------------------------------------------------ skill discovery
def discover_skills(roots, exclude_dirs):
    """Walk allowlisted roots; every directory that directly contains a skill.json is a skill.
    Returns a deterministic (sorted) list of {root_abs, root_label, rel_dir, skilljson_rel, skilljson_abs}."""
    exset = set(exclude_dirs or DEFAULT_EXCLUDE_DIRS)
    multi = len(roots) > 1
    found = []
    for root in roots:
        root = os.path.abspath(root)
        if not os.path.isdir(root):
            raise CardError("root_not_found", "root not found: %s" % root)
        root_label = os.path.basename(root.rstrip("/\\")) or "root"
        for dirpath, dirnames, filenames in os.walk(root):
            # deterministic order + prune excluded segments in place
            dirnames[:] = sorted(d for d in dirnames if d not in exset)
            if "skill.json" in filenames:
                rel_dir = rel_posix(root, dirpath)
                if rel_dir == ".":
                    rel_dir = ""
                sj_rel = (rel_dir + "/skill.json") if rel_dir else "skill.json"
                if multi:
                    sj_rel = root_label + "/" + sj_rel
                    disp_dir = (root_label + "/" + rel_dir) if rel_dir else root_label
                else:
                    disp_dir = rel_dir
                found.append({
                    "root_abs": root, "root_label": root_label, "rel_dir": disp_dir,
                    "skilljson_rel": sj_rel, "skilljson_abs": os.path.join(dirpath, "skill.json"),
                    "dir_abs": dirpath,
                })
    found.sort(key=lambda d: d["skilljson_rel"])
    return found


def _read_bytes(path, capn):
    with open(path, "rb") as fh:
        return fh.read(capn + 1)


def _read_doc(dir_abs, name):
    """Best-effort read a sibling doc (README.md / WORK_ORDER.md). Returns (text, rel_present) or (None, False)."""
    p = os.path.join(dir_abs, name)
    if not os.path.isfile(p):
        return None
    try:
        b = _read_bytes(p, MAX_DOC_BYTES)
        return b.decode("utf-8", errors="replace")
    except Exception:
        return None


# ------------------------------------------------------------------ section-9 derivations
def module_of(rel_dir):
    """The modules/<NN>-name dir a skill lives under (external edge ref), else None."""
    parts = [p for p in (rel_dir or "").split("/") if p]
    for i, p in enumerate(parts):
        if re.match(r"^\d+", p):  # NN-name style module folder
            return "/".join(parts[: i + 1])
    return parts[0] if parts else None


def domain_of(skill_id):
    """Coarse deterministic domain tag from the skill_id (the dotted prefix)."""
    sid = (skill_id or "").lower()
    return sid.split(".")[0] if "." in sid else sid


def latency_class(timeout_seconds):
    try:
        t = int(timeout_seconds)
    except Exception:
        return "unknown"
    if t <= 0:
        return "unknown"
    if t <= 30:
        return "fast"
    if t <= 120:
        return "medium"
    if t <= 600:
        return "slow"
    return "very_slow"


def _gpu_required(reqs):
    g = str((reqs or {}).get("gpu", "") or "").strip().lower()
    return g not in ("", "none", "no", "false", "cpu", "any", "optional", "0")


def resource_class(reqs):
    reqs = reqs or {}
    if _gpu_required(reqs):
        return "gpu"
    try:
        mem = int(reqs.get("memory_mb", 0) or 0)
    except Exception:
        mem = 0
    if mem >= 2048:
        return "heavy_cpu"
    return "cpu_light"


def derive_operations(manifest, warnings):
    """Extract supported operations deterministically from an op/mode/action input's enum, else the
    invocation args_spec, else a single implicit 'invoke' operation."""
    ops = []
    seen = set()

    def add(tok):
        tok = (tok or "").strip().strip(".;,)( ").strip()
        tok = tok.split()[0] if tok.split() else ""
        tok = tok.strip(".;,)( ")
        if tok and _pascalish_ok(tok) and tok not in seen and tok not in ("default", "e.g", "eg", "etc"):
            seen.add(tok)
            ops.append(tok)

    inputs = manifest.get("inputs") if isinstance(manifest, dict) else None
    op_desc = None
    if isinstance(inputs, list):
        for it in inputs:
            if not isinstance(it, dict):
                continue
            nm = str(it.get("name", "")).lower()
            if nm in ("op", "operation", "action", "mode", "command", "cmd", "subcommand"):
                op_desc = str(it.get("description", "")) + " " + str(it.get("default", ""))
                break
    args_spec = ""
    inv = manifest.get("invocation") if isinstance(manifest, dict) else None
    if isinstance(inv, dict):
        args_spec = str(inv.get("args_spec", ""))

    src = op_desc or ""
    if src:
        # split on pipes / commas / newlines; take the leading token of each piece
        for piece in re.split(r"[|\n]", src):
            add(piece)
    if not ops and args_spec:
        m = re.search(r"-(?:Op|Operation|Mode|Action|Command)\s+([A-Za-z0-9|_\- ]+)", args_spec)
        if m:
            for piece in m.group(1).split("|"):
                add(piece)
    if not ops:
        ops = ["invoke"]
    if len(ops) > CAP_OPERATIONS:
        warnings.append("operations capped at %d (had %d)" % (CAP_OPERATIONS, len(ops)))
        ops = ops[:CAP_OPERATIONS]
    return ops


def derive_inputs(manifest, missing, warnings):
    inputs = manifest.get("inputs") if isinstance(manifest, dict) else None
    if not isinstance(inputs, list) or not inputs:
        missing.append("inputs")
        return []
    out = []
    for it in inputs:
        if not isinstance(it, dict) or not it.get("name"):
            continue
        row = {
            "name": str(it.get("name")),
            "type": str(it.get("type", "")),
            "required": bool(it.get("required", False)),
        }
        if "default" in it and it.get("default") is not None:
            row["default"] = it.get("default")
        if it.get("description"):
            row["description"] = cap(it.get("description"), CAP_INPUT_DESC)
        out.append(row)
    out.sort(key=lambda r: (0 if r["required"] else 1, r["name"]))
    if len(out) > CAP_INPUTS:
        warnings.append("inputs capped at %d (had %d)" % (CAP_INPUTS, len(out)))
        out = out[:CAP_INPUTS]
    if not out:
        missing.append("inputs")
    return out


def derive_preconditions(manifest):
    reqs = (manifest.get("requirements") if isinstance(manifest, dict) else None) or {}
    pre = []
    for exe in (reqs.get("executables") or []):
        pre.append("executable: %s" % cap(exe, 80))
    for mdl in (reqs.get("models") or []):
        pre.append("model: %s" % cap(mdl, 80))
    for lib in (reqs.get("libraries") or []):
        pre.append("library: %s" % cap(lib, 80))
    if _gpu_required(reqs):
        pre.append("gpu: %s" % str(reqs.get("gpu")))
    if bool(reqs.get("network", False)):
        pre.append("network access")
    fsy = str(reqs.get("filesystem", "") or "")
    if fsy:
        pre.append("filesystem: %s" % fsy)
    if not pre:
        pre.append("none declared")
    return [cap(x, CAP_LIST_ITEM) for x in pre]


def _side_effect_kinds(manifest):
    """The permission-like side-effect kinds a skill needs (drives Stage-1 side-effect/permission rules)."""
    reqs = (manifest.get("requirements") if isinstance(manifest, dict) else None) or {}
    kinds = []
    fsy = str(reqs.get("filesystem", "") or "").lower()
    if fsy in ("write", "read-write", "readwrite", "rw"):
        kinds.append("filesystem_write")
    if bool(reqs.get("network", False)):
        kinds.append("network")
    if bool(reqs.get("screen", False)):
        kinds.append("screen_capture")
    if bool(reqs.get("audio", False)):
        kinds.append("audio_capture")
    if bool(reqs.get("camera", False)):
        kinds.append("camera_capture")
    return kinds


def derive_side_effects(manifest):
    kinds = _side_effect_kinds(manifest)
    if not kinds:
        return ["none (read-only / pure)"]
    label = {
        "filesystem_write": "writes files",
        "network": "network egress",
        "screen_capture": "captures the screen",
        "audio_capture": "captures audio",
        "camera_capture": "captures camera",
    }
    return [label.get(k, k) for k in kinds]


def derive_artifacts(manifest, missing):
    out = ""
    outputs = manifest.get("outputs") if isinstance(manifest, dict) else None
    if isinstance(outputs, dict) and outputs.get("description"):
        out = cap(outputs.get("description"), CAP_ARTIFACTS)
    arts = manifest.get("artifacts") if isinstance(manifest, dict) else None
    root = ""
    if isinstance(arts, dict) and arts.get("root"):
        root = str(arts.get("root"))
    if not out and not root:
        missing.append("artifacts")
        return {"description": "", "root": ""}
    return {"description": out, "root": root}


def derive_completion_checks(manifest, determinism):
    checks = ["envelope.status in {ok, partial}"]
    outputs = manifest.get("outputs") if isinstance(manifest, dict) else None
    shape = ""
    if isinstance(outputs, dict) and outputs.get("result_shape"):
        shape = str(outputs.get("result_shape"))
        checks.append("result matches declared shape '%s'" % shape)
    checks.append("artifacts[] paths exist with matching sha256")
    if determinism == "deterministic":
        checks.append("re-run over identical inputs yields an identical result (deterministic)")
    return [cap(x, CAP_LIST_ITEM) for x in checks]


def derive_failure_conditions(manifest, missing):
    reqs = (manifest.get("requirements") if isinstance(manifest, dict) else None) or {}
    fc = []
    if reqs.get("executables") or reqs.get("models") or reqs.get("libraries"):
        fc.append("a declared dependency is unavailable")
    if _gpu_required(reqs):
        fc.append("GPU unavailable / out of VRAM")
    inputs = manifest.get("inputs") if isinstance(manifest, dict) else None
    req_names = []
    if isinstance(inputs, list):
        req_names = sorted(str(i.get("name")) for i in inputs if isinstance(i, dict) and i.get("required"))
    if req_names:
        fc.append("missing required input(s): %s" % ", ".join(req_names[:8]))
    if bool(reqs.get("network", False)):
        fc.append("network unavailable")
    to = manifest.get("timeout") if isinstance(manifest, dict) else None
    if isinstance(to, dict) and to.get("default_seconds"):
        act = str(to.get("on_timeout", "kill_tree_and_report"))
        fc.append("timeout after %ss (%s)" % (to.get("default_seconds"), act))
    fc.append("invalid inputs -> status:error {code,message,retryable}")
    if not fc:
        missing.append("failure_conditions")
    return [cap(x, CAP_LIST_ITEM) for x in fc]


def synthesize_example(manifest, missing):
    inv = manifest.get("invocation") if isinstance(manifest, dict) else None
    if not isinstance(inv, dict) or not inv.get("entrypoint"):
        missing.append("example")
        return ""
    entry = str(inv.get("entrypoint"))
    method = str(inv.get("method", "pwsh-file"))
    inputs = manifest.get("inputs") if isinstance(manifest, dict) else []
    req = {}
    op_val = None
    if isinstance(inputs, list):
        for it in inputs:
            if not isinstance(it, dict) or not it.get("name"):
                continue
            nm = str(it["name"])
            if nm.lower() in ("op", "operation", "action", "mode") and op_val is None:
                d = it.get("default")
                op_val = str(d) if d else None
            if it.get("required"):
                req[nm] = "<%s>" % str(it.get("type", "value"))
    if op_val and "op" not in req:
        req["op"] = op_val
    inj = canon(req) if req else "{}"
    runner = "python" if method == "python" else "pwsh -NoProfile -File"
    ex = "%s %s -InputsJson '%s'" % (runner, entry, inj)
    return cap(ex, CAP_EXAMPLE)


def _purpose(manifest, docs, missing):
    p = ""
    if isinstance(manifest, dict) and manifest.get("purpose"):
        p = str(manifest.get("purpose"))
    if not p and docs:
        # fallback: first non-heading, non-empty paragraph line of README
        for line in (docs.get("README.md") or "").splitlines():
            t = line.strip()
            if t and not t.startswith("#") and not t.startswith("```"):
                p = t
                break
    if not p:
        missing.append("purpose")
    # keep to the first sentence-ish, bounded
    return cap(p, CAP_PURPOSE)


def _build_text(skill_id, name, purpose, ops, inputs, side_effects, domain):
    parts = [skill_id or "", name or "", purpose or "", domain or ""]
    parts.append(" ".join(ops or []))
    parts.append(" ".join(i.get("name", "") for i in (inputs or [])))
    parts.append(" ".join(side_effects or []))
    return cap(" ".join(p for p in parts if p), CAP_TEXT)


def build_card(rec, ns):
    """rec = a discover_skills() entry. Returns (card, parse_failure_or_None).
    NEVER raises on a malformed/partial manifest -- emits a degraded card + a surfaced warning."""
    skj_rel = rec["skilljson_rel"]
    rel_dir = rec["rel_dir"]
    warnings = []
    missing = []
    parse_failure = None
    manifest = None
    raw = b""
    file_hash = None

    try:
        raw = _read_bytes(rec["skilljson_abs"], MAX_SKILL_JSON_BYTES)
        if len(raw) > MAX_SKILL_JSON_BYTES:
            raise CardError("oversize", "skill.json exceeds %d bytes" % MAX_SKILL_JSON_BYTES)
        file_hash = _hb(raw)
        manifest = json.loads(raw.decode("utf-8"))
        if not isinstance(manifest, dict):
            raise CardError("not_a_manifest", "skill.json is not a JSON object")
    except CardError as ce:
        parse_failure = {"rel": skj_rel, "reason": ce.code, "detail": ce.message}
    except json.JSONDecodeError as je:
        parse_failure = {"rel": skj_rel, "reason": "invalid_json", "detail": str(je)[:200]}
    except UnicodeDecodeError as ue:
        parse_failure = {"rel": skj_rel, "reason": "not_utf8", "detail": str(ue)[:200]}
    except Exception as e:  # pragma: no cover -- defensive; never crash
        parse_failure = {"rel": skj_rel, "reason": "read_error", "detail": repr(e)[:200]}

    if file_hash is None and raw:
        file_hash = _hb(raw)

    # read sibling docs (best-effort; recorded in derivation_refs)
    docs = {}
    doc_refs = []
    for dn in ("README.md", "WORK_ORDER.md"):
        txt = _read_doc(rec["dir_abs"], dn)
        if txt is not None:
            docs[dn] = txt
            drel = (rel_dir + "/" + dn) if rel_dir else dn
            doc_refs.append({"ref": drel, "kind": "source_doc"})

    degraded = manifest is None or (isinstance(manifest, dict) and "skill_id" not in manifest)

    if degraded:
        # minimal fallback card -- stable logical id from the dir path so re-runs are idempotent
        skill_id = (str(manifest.get("skill_id")) if isinstance(manifest, dict) and manifest.get("skill_id")
                    else "unresolved:" + (rel_dir or skj_rel))
        if parse_failure is None:
            parse_failure = {"rel": skj_rel, "reason": "missing_skill_id", "detail": "manifest lacks skill_id"}
        warnings.append("degraded card for %s (%s)" % (skj_rel, parse_failure["reason"]))
        m = manifest if isinstance(manifest, dict) else {}
        name = str(m.get("name", "")) if m else ""
        version = str(m.get("version", "")) if m else ""
        determinism = str(m.get("determinism", "")) if m else ""
        purpose = _purpose(m, docs, missing)
        operations = derive_operations(m, warnings)
        inputs = derive_inputs(m, missing, warnings)
        example = synthesize_example(m, missing)
        preconditions = derive_preconditions(m)
        side_effects = derive_side_effects(m)
        artifacts = derive_artifacts(m, missing)
        completion = derive_completion_checks(m, determinism)
        failures = derive_failure_conditions(m, missing)
        reqs = (m.get("requirements") if isinstance(m, dict) else {}) or {}
        parallel_safe = bool(m.get("parallel_safe", False)) if m else False
        card_status = "degraded"
        health = {"status": "degraded", "reasons": [parse_failure["reason"]]}
    else:
        m = manifest
        skill_id = str(m.get("skill_id"))
        name = str(m.get("name", ""))
        if not name:
            missing.append("name")
        version = str(m.get("version", ""))
        if not version:
            missing.append("version")
        determinism = str(m.get("determinism", ""))
        purpose = _purpose(m, docs, missing)
        operations = derive_operations(m, warnings)
        inputs = derive_inputs(m, missing, warnings)
        example = synthesize_example(m, missing)
        preconditions = derive_preconditions(m)
        side_effects = derive_side_effects(m)
        artifacts = derive_artifacts(m, missing)
        completion = derive_completion_checks(m, determinism)
        failures = derive_failure_conditions(m, missing)
        reqs = (m.get("requirements") or {})
        parallel_safe = bool(m.get("parallel_safe", False))
        # section-9 completeness -> card_status
        miss9 = sorted(set(f for f in missing if f in SECTION9_FIELDS))
        card_status = "partial" if miss9 else "ok"
        health = {"status": "ok" if not miss9 else "partial",
                  "reasons": (["missing: " + ",".join(miss9)] if miss9 else [])}

    to = (manifest.get("timeout") if isinstance(manifest, dict) else None) or {}
    lat = latency_class(to.get("default_seconds", 0))
    if lat == "unknown":
        missing.append("latency_class")
    res = resource_class(reqs)
    domain = domain_of(skill_id)
    text = _build_text(skill_id, name, purpose, operations, inputs, side_effects, domain)

    missing_fields = sorted(set(missing))
    if missing_fields:
        warnings.append("%s missing section-9 field(s): %s" % (skill_id, ",".join(missing_fields)))

    card = {
        "schema": CARD_SCHEMA,
        "skill_id": skill_id,
        "name": name,
        "version": version,
        "determinism": determinism,
        "parallel_safe": parallel_safe,
        "domain": domain,
        "module": module_of(rel_dir),
        # --- directive section 9 fields ---
        "purpose": purpose,
        "operations": operations,
        "inputs": inputs,
        "example": example,
        "preconditions": preconditions,
        "side_effects": side_effects,
        "side_effect_kinds": _side_effect_kinds(manifest if isinstance(manifest, dict) else {}),
        "artifacts": artifacts,
        "latency_class": lat,
        "resource_class": res,
        "gpu_required": _gpu_required(reqs),
        "network_required": bool(reqs.get("network", False)),
        "required_executables": sorted(str(x) for x in (reqs.get("executables") or [])),
        "required_models": sorted(str(x) for x in (reqs.get("models") or [])),
        "os": str(reqs.get("os", "any") or "any").lower() if isinstance(reqs, dict) else "any",
        "completion_checks": completion,
        "failure_conditions": failures,
        "version_health": {"version": version, "contract_version":
                           str(manifest.get("contract_version", "")) if isinstance(manifest, dict) else "",
                           "determinism": determinism, "health": health},
        # --- card meta ---
        "card_status": card_status,
        "missing_fields": missing_fields,
        "source_path": skj_rel,
        "text": text,
    }
    return {
        "card": card, "warnings": warnings, "parse_failure": parse_failure,
        "file_hash": file_hash, "skj_rel": skj_rel, "rel_dir": rel_dir, "doc_refs": doc_refs,
        "skill_id": skill_id,
    }


# ------------------------------------------------------------------ s1 record emission
def _doc_id(ns, rel):
    return "doc_" + _h(ns + "\0" + rel)[:24]


def _ver_id(ns, rel, content_hash):
    return "ver_" + _h(_doc_id(ns, rel) + "\0" + content_hash)[:24]


def id_card(ns, skill_id):
    # DISTINCT prefix from #38's structural skill record id ("skl_") -> no ingest collision (BOUNDARY).
    return "sklcard_" + _h(ns + "\0" + skill_id)[:24]


def id_struct_skill(ns, skill_id):
    # #38 repo.intel's structural skill record id (recomputed to record the boundary link as an external edge).
    return "skl_" + _h(ns + "\0" + skill_id)[:24]


def edge(edge_type, target_record_id=None, external=False, external_ref=None):
    if external:
        return {"edge_type": edge_type, "external": True, "external_ref": external_ref,
                "target_record_id": None}
    return {"edge_type": edge_type, "external": False, "target_record_id": target_record_id}


def build_record(built, ns, ingest_run_id):
    card = built["card"]
    skill_id = card["skill_id"]
    payload = dict(card)  # the card IS the record payload (bounded, deterministic)
    content = canon(payload)
    content_hash = _h(content)
    record_id = id_card(ns, skill_id)
    record_version_id = "rv_" + _h(record_id + "\0" + content_hash)[:24]
    file_hash = built["file_hash"]
    skj_rel = built["skj_rel"]
    source_version_id = _ver_id(ns, skj_rel, file_hash) if file_hash else None
    # span = the whole manifest byte region (primary derivation source); end = file byte length.
    span_end = built.get("_span_end")
    source_span = {"start": 0, "end": span_end} if span_end is not None else None

    # child_edges: skill -> each supported operation (external refs; ops are not separate records)
    child_edges = [edge("has_operation", external=True, external_ref="%s#op:%s" % (skill_id, op))
                   for op in card["operations"]]
    # A3 (D-0087): the card DERIVES FROM #38's structural `skill` record -- a `derives_from` navigational
    # edge (external; external_ref = #38's recomputed `skl_` id; resolves only when both producers share the
    # namespace at fold). REPLACES the 0.1 `describes_structural_skill` cross-link (byte-identical external_ref;
    # the derivation is now expressed as derivation, per A3's navigational-derivative framing).
    child_edges.append(edge(EDGE_DERIVES_FROM, external=True,
                            external_ref=id_struct_skill(ns, skill_id)))
    parent_edges = []
    if card["module"]:
        parent_edges.append(edge("skill_of_module", external=True, external_ref=card["module"]))

    rec = {
        "schema": RECORD_SCHEMA,
        "record_id": record_id,
        "record_version_id": record_version_id,
        "record_kind": EMITTED_KIND,               # A3: `summary` (activation card), NOT a 2nd `skill`
        "attrs": {"summary_type": SUMMARY_TYPE},    # A3: marks this summary as a skill-activation card
        "namespace": ns,
        "content_hash": content_hash,
        "status": STATUS_CURRENT,
        "authority_level": AUTHORITY_DERIVED,      # BOUNDARY vs #38 "canonical_source"
        "sensitivity_class": SENSITIVITY,
        "valid_from": None,
        "valid_to": None,
        "created_by_ingest_run": ingest_run_id,
        "source_version_id": source_version_id,
        "source_path": skj_rel,
        "source_span": source_span,
        "derivation_refs": list(built["doc_refs"]),
        "parser_fingerprint": FP_MANIFEST,
        "chunker_fingerprint": None,               # typed record, not a chunk
        "extractor_fingerprint": FP_CARDGEN,
        "schema_version": RECORD_SCHEMA,
        "token_count": token_count(card.get("text")),
        "embedding_space_id": None,                # nullable until embedded (s2)
        "parent_edges": parent_edges,
        "child_edges": child_edges,
        "payload": payload,
        "text": card.get("text", ""),              # top-level FTS text (additive; #36 records_fts indexes it)
    }
    return rec


# ------------------------------------------------------------------ generate (shared by cards/eligible/retrieve)
def generate(args):
    roots = args.get("roots")
    if not roots:
        r = args.get("root")
        roots = [r] if r else None
    if not roots:
        raise CardError("missing_root", "needs -Roots/-Root (roots[] or root)")
    ns = slug(args.get("namespace") or args.get("source_label") or "life-orchestrator")
    exclude_dirs = args.get("exclude_dirs") or DEFAULT_EXCLUDE_DIRS

    skills = discover_skills(roots, exclude_dirs)

    # deterministic content-derived ingest run id (never wall-clock) -- over the skill.json corpus
    file_hashes = {}
    for s in skills:
        try:
            b = _read_bytes(s["skilljson_abs"], MAX_SKILL_JSON_BYTES)
            file_hashes[s["skilljson_rel"]] = (_hb(b), len(b))
        except Exception:
            file_hashes[s["skilljson_rel"]] = ("READFAIL", 0)
    corpus_key = ns + "\0" + "\n".join(
        (rel + "\t" + file_hashes[rel][0]) for rel in sorted(file_hashes.keys()))
    ingest_run_id = "ingest_" + _h(corpus_key)[:24]

    cards = []
    records = []
    warnings = []
    parse_failures = []
    for s in skills:
        built = build_card(s, ns)
        # precompute the manifest byte length for the record source_span
        fh = file_hashes.get(built["skj_rel"])
        built["_span_end"] = fh[1] if (fh and fh[0] != "READFAIL") else None
        cards.append(built["card"])
        records.append(build_record(built, ns, ingest_run_id))
        for w in built["warnings"]:
            warnings.append(w)
        if built["parse_failure"]:
            parse_failures.append(built["parse_failure"])

    # deterministic order
    cards.sort(key=lambda c: c["skill_id"])
    records.sort(key=lambda r: (r["record_kind"], r["source_path"], r["record_id"]))
    parse_failures.sort(key=lambda x: (x["rel"], x["reason"]))

    validation = validate_records(records)
    cards_digest = _cards_digest(cards)
    records_digest = _records_digest(records)
    counts_by_kind = {}
    for r in records:
        counts_by_kind[r["record_kind"]] = counts_by_kind.get(r["record_kind"], 0) + 1
    status_counts = {}
    for c in cards:
        status_counts[c["card_status"]] = status_counts.get(c["card_status"], 0) + 1
    missing_summary = {}
    for c in cards:
        for f in c["missing_fields"]:
            missing_summary[f] = missing_summary.get(f, 0) + 1
    edge_total = sum(len(r["parent_edges"]) + len(r["child_edges"]) for r in records)
    edge_external = sum(1 for r in records for e in (r["parent_edges"] + r["child_edges"]) if e.get("external"))
    edge_summary = {"total": edge_total, "resolved_internal": edge_total - edge_external, "external": edge_external}

    return {
        "namespace": ns, "roots_labeled": sorted(set(s["root_label"] for s in skills)),
        "ingest_run_id": ingest_run_id, "cards": cards, "records": records,
        "warnings": warnings, "parse_failures": parse_failures, "validation": validation,
        "cards_digest": cards_digest, "records_digest": records_digest,
        "record_counts_by_kind": counts_by_kind, "card_status_counts": status_counts,
        "degraded_count": status_counts.get("degraded", 0),
        "partial_count": status_counts.get("partial", 0),
        "missing_field_summary": missing_summary, "edge_summary": edge_summary,
        "skill_count": len(cards),
    }


# ------------------------------------------------------------------ Stage 1: deterministic eligibility
def _card_index(args):
    """Return (cards, meta) either from a cards_path artifact or by generating from roots."""
    cp = args.get("cards_path")
    if cp:
        if not os.path.isfile(cp):
            raise CardError("cards_not_found", "cards_path not found: %s" % cp)
        with open(cp, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
        if isinstance(obj, dict) and "cards" in obj:
            cards = obj["cards"]
            meta = {"namespace": obj.get("namespace"), "source": "cards_path"}
        elif isinstance(obj, list):
            cards = obj
            meta = {"namespace": None, "source": "cards_path"}
        else:
            raise CardError("bad_cards_artifact", "cards_path is not a cards array or {cards:[]}")
        return cards, meta
    g = generate(args)
    return g["cards"], {"namespace": g["namespace"], "source": "generated", "generate": g}


def _as_bool(v, default):
    if v is None:
        return default
    if isinstance(v, bool):
        return v
    s = str(v).strip().lower()
    if s in ("true", "1", "yes", "y", "on"):
        return True
    if s in ("false", "0", "no", "n", "off"):
        return False
    return default


def eligibility_reasons(card, task):
    """Return a sorted list of exclusion reasons for one card under a task descriptor. Empty => eligible."""
    reasons = []
    # --- side-effect policy / permissions ---
    allow_se = _as_bool(task.get("allow_side_effects"), True)
    se_kinds = card.get("side_effect_kinds") or []
    forbidden = set(task.get("forbidden_side_effects") or [])
    permissions = task.get("permissions")
    if not allow_se and se_kinds:
        reasons.append("side_effects_forbidden: needs %s" % ",".join(sorted(se_kinds)))
    for k in sorted(se_kinds):
        if k in forbidden:
            reasons.append("forbidden_side_effect: %s" % k)
    if permissions is not None:
        granted = set(permissions)
        for k in sorted(se_kinds):
            if k not in granted:
                reasons.append("permission_not_granted: %s" % k)
    # --- gpu ---
    if not _as_bool(task.get("gpu_available"), True) and card.get("gpu_required"):
        reasons.append("gpu_unavailable")
    # --- network ---
    if not _as_bool(task.get("network_available"), True) and card.get("network_required"):
        reasons.append("network_unavailable")
    # --- dependencies (only filter when the task declares availability) ---
    if task.get("available_models") is not None:
        avail = set(task.get("available_models") or [])
        for mdl in card.get("required_models") or []:
            if mdl not in avail:
                reasons.append("model_unavailable: %s" % mdl)
    if task.get("available_executables") is not None:
        availx = set(task.get("available_executables") or [])
        for exe in card.get("required_executables") or []:
            if exe not in availx:
                reasons.append("executable_unavailable: %s" % exe)
    for dep in set(task.get("unavailable_dependencies") or []):
        if dep in set(card.get("required_models") or []) or dep in set(card.get("required_executables") or []):
            reasons.append("dependency_unavailable: %s" % dep)
    # --- health ---
    if _as_bool(task.get("require_healthy"), False):
        hs = ((card.get("version_health") or {}).get("health") or {}).get("status", "ok")
        if hs not in ("ok",):
            reasons.append("health_not_ok: %s" % hs)
    if _as_bool(task.get("exclude_degraded"), False) and card.get("card_status") == "degraded":
        reasons.append("degraded_card")
    # --- os ---
    tos = str(task.get("os", "") or "").lower()
    cos = str(card.get("os", "any") or "any").lower()
    if tos and cos not in ("any", "", tos):
        reasons.append("os_mismatch: needs %s" % cos)
    # --- parallel safety ---
    if _as_bool(task.get("require_parallel_safe"), False) and not card.get("parallel_safe", False):
        reasons.append("not_parallel_safe")
    # --- optional domain / task_type filter (Stage 1 coarse; Stage 3 refines) ---
    req_domains = task.get("required_domains")
    if req_domains:
        if card.get("domain") not in set(req_domains):
            reasons.append("domain_excluded: %s" % card.get("domain"))
    return sorted(set(reasons))


def do_eligible(args):
    cards, meta = _card_index(args)
    task = args.get("task") or {}
    if not isinstance(task, dict):
        raise CardError("bad_task", "task must be an object")
    eligible = []
    excluded = []
    for c in sorted(cards, key=lambda x: x["skill_id"]):
        rs = eligibility_reasons(c, task)
        if rs:
            excluded.append({"skill_id": c["skill_id"], "reasons": rs})
        else:
            eligible.append(c["skill_id"])
    payload = {
        "op": "eligible", "namespace": meta.get("namespace"),
        "task": task, "skill_count": len(cards),
        "eligible": sorted(eligible), "eligible_count": len(eligible),
        "excluded": sorted(excluded, key=lambda x: x["skill_id"]), "excluded_count": len(excluded),
    }
    if meta.get("source") == "generated":
        payload["_generate"] = meta["generate"]
    return payload


# ------------------------------------------------------------------ Stage 2: lexical retrieval seam
FIELD_WEIGHTS = (
    ("skill_id_tokens", 5),
    ("name", 4),
    ("purpose", 3),
    ("operations", 2),
    ("input_names", 1),
    ("aux", 1),
    ("text", 1),
)
_TF_CAP = 3


def _card_field_tokens(card):
    sid = card.get("skill_id", "")
    fields = {
        "skill_id_tokens": tokenize(sid.replace(".", " ").replace("_", " ")),
        "name": tokenize(card.get("name", "")),
        "purpose": tokenize(card.get("purpose", "")),
        "operations": tokenize(" ".join(card.get("operations") or [])),
        "input_names": tokenize(" ".join(i.get("name", "") for i in (card.get("inputs") or []))),
        "aux": tokenize(" ".join((card.get("failure_conditions") or []) + (card.get("preconditions") or [])
                                 + (card.get("side_effects") or []))),
        "text": tokenize(card.get("text", "")),
    }
    counts = {}
    for fname, toks in fields.items():
        c = {}
        for t in toks:
            c[t] = c.get(t, 0) + 1
        counts[fname] = c
    return counts


def score_card(card, qtokens):
    counts = _card_field_tokens(card)
    score = 0
    matched = set()
    for qt in qtokens:
        for fname, w in FIELD_WEIGHTS:
            tf = counts.get(fname, {}).get(qt, 0)
            if tf:
                score += w * min(tf, _TF_CAP)
                matched.add(qt)
    return score, sorted(matched)


def do_retrieve(args):
    cards, meta = _card_index(args)
    query = args.get("query")
    if not query or not str(query).strip():
        raise CardError("missing_query", "retrieve needs -Query")
    k = int(args.get("k") or 5)
    if k <= 0:
        k = 5
    task = args.get("task")
    pool = cards
    prefiltered = False
    if isinstance(task, dict) and task:
        pool = [c for c in cards if not eligibility_reasons(c, task)]
        prefiltered = True
    qtokens = tokenize(str(query))
    scored = []
    for c in pool:
        s, matched = score_card(c, qtokens)
        if s > 0:
            scored.append((s, c["skill_id"], matched, c))
    # deterministic order: higher score first, then skill_id
    scored.sort(key=lambda t: (-t[0], t[1]))
    hits = []
    for rank, (s, sid, matched, c) in enumerate(scored[:k], start=1):
        hits.append({
            "rank": rank, "skill_id": sid, "lexical_score": s, "matched_terms": matched,
            "record_id": id_card(meta.get("namespace") or "life-orchestrator", sid),
            "purpose": c.get("purpose", ""), "domain": c.get("domain"),
            "resource_class": c.get("resource_class"), "card_status": c.get("card_status"),
            "tie_break_key": sid,
        })
    payload = {
        "op": "retrieve", "namespace": meta.get("namespace"),
        "query": str(query), "query_tokens": qtokens, "k": k,
        "prefiltered_by_task": prefiltered, "pool_size": len(pool),
        "retrieval_mode": "lexical_baseline",
        "count": len(hits), "results": hits,
        # --- the SEMANTIC-RETRIEVAL SEAM (real embeddings fold in at the retrieval wave) ---
        "seam": {
            "description": "Stage-2 semantic skill retrieval. This lexical baseline is the deterministic "
                           "fold-in point; the real path embeds the task and searches the card index.",
            "semantic_query_shape": {
                "query_text": "<task intent>", "task_type": "<optional>", "k": k,
                "embedding_space_id": None,
                # A3 (D-0087): activation cards are record_kind=summary (summary_type=skill_activation_card).
                # A record_kind=skill search returns #38's STRUCTURAL records, NOT these cards -> filter on the
                # summary kind + summary_type so retrieval reaches the activation cards.
                "filters": {"record_kind": EMITTED_KIND, "summary_type": SUMMARY_TYPE},
                "candidate_kinds": [EMITTED_KIND, "procedure", "episode", "failure"],
            },
            "artifact_search_call": {
                "op": "search", "query": "<task intent>", "k": k, "mode": "fts",
                "filters": {"record_kind": EMITTED_KIND, "summary_type": SUMMARY_TYPE,
                            "namespace": meta.get("namespace")},
            },
            "notes": "Records emitted here are record_kind=summary (attrs.summary_type=skill_activation_card, "
                     "A3), carrying a top-level `text` field so #36 records_fts indexes them; the fused hybrid "
                     "rank replaces lexical_score once vectors participate (#37 0.2).",
        },
    }
    if meta.get("source") == "generated":
        payload["_generate"] = meta["generate"]
    return payload


# ------------------------------------------------------------------ validator (s1) + digests
def validate_records(records):
    errors = []
    ids = set(r.get("record_id") for r in records)
    edge_total = edge_resolved = edge_external = 0
    ingest_shape_ok = True
    for r in records:
        rid = r.get("record_id", "?")
        for fld in S1_REQUIRED:
            if fld not in r:
                errors.append("%s: missing field %s" % (rid, fld))
        if r.get("record_kind") not in S1_RECORD_KINDS:
            errors.append("%s: bad record_kind %r" % (rid, r.get("record_kind")))
        if r.get("record_kind") == "source_chunk":
            errors.append("%s: source_chunk is reserved (rejected by #36 ingest_records)" % rid)
        # A3 (D-0087): a skill.card record (its own schema) MUST be `summary` -- NOT a 2nd `skill` -- and MUST
        # carry attrs.summary_type='skill_activation_card'. Gated on the skill.card schema so this validator
        # never falsely rejects a FOREIGN `summary` record (e.g. #38's structural summaries).
        if r.get("schema_version") == RECORD_SCHEMA:
            if r.get("record_kind") != EMITTED_KIND:
                errors.append("%s: skill.card record_kind must be '%s' (A3), got %r"
                              % (rid, EMITTED_KIND, r.get("record_kind")))
            if ((r.get("attrs") or {}).get("summary_type")) != SUMMARY_TYPE:
                errors.append("%s: skill.card summary missing attrs.summary_type=%r (A3)" % (rid, SUMMARY_TYPE))
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
            elif span.get("start") is not None and span.get("end") is not None and span["start"] > span["end"]:
                errors.append("%s: span start>end" % rid)
        elif not drefs:
            errors.append("%s: neither source_span nor derivation_refs present" % rid)
        # edge integrity
        for e in (r.get("parent_edges") or []) + (r.get("child_edges") or []):
            edge_total += 1
            if e.get("external"):
                edge_external += 1
                if not e.get("external_ref"):
                    errors.append("%s: external edge missing external_ref" % rid)
            else:
                if e.get("target_record_id") in ids:
                    edge_resolved += 1
                else:
                    errors.append("%s: edge target unresolved: %s (%s)" % (rid, e.get("target_record_id"),
                                                                           e.get("edge_type")))
        # #36 ingest_records drop-in shape: needs text | content_hash + a valid typed kind
        if not (r.get("text") or r.get("content_hash")):
            ingest_shape_ok = False
            errors.append("%s: ingest_records needs text|content_hash" % rid)
    return {
        "ok": len(errors) == 0,
        "checked": len(records),
        "errors": errors,
        "ingest_shape_ok": ingest_shape_ok,
        "edge_summary": {"total": edge_total, "resolved_internal": edge_resolved, "external": edge_external},
    }


S1_REQUIRED = ("record_id", "record_version_id", "record_kind", "namespace", "content_hash",
               "status", "authority_level", "sensitivity_class", "valid_from", "valid_to",
               "created_by_ingest_run", "source_version_id", "source_span", "derivation_refs",
               "parser_fingerprint", "chunker_fingerprint", "extractor_fingerprint",
               "schema_version", "token_count", "embedding_space_id", "parent_edges", "child_edges")


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


def _cards_digest(cards):
    lines = []
    for c in cards:
        lines.append("\t".join([c["skill_id"], _h(canon(c)), c["card_status"]]))
    lines.sort()
    return _h("\n".join(lines))


# ------------------------------------------------------------------ artifact writing (canonical)
def _write_text(path, s):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(s)


def _ingest_payload(ns, ingest_run_id, records):
    return {"schema": INGEST_SCHEMA, "namespace": ns, "created_by_ingest_run": ingest_run_id,
            "producer": "skill.card", "producer_version": WORKER_VERSION,
            "record_count": len(records), "records": records}


def _index_manifest(g):
    return {
        "schema": "lifeorch.skill_card.index_manifest/0.1",
        "namespace": g["namespace"], "roots": g["roots_labeled"],
        "created_by_ingest_run": g["ingest_run_id"],
        "skill_count": g["skill_count"], "total_records": len(g["records"]),
        "record_counts_by_kind": g["record_counts_by_kind"],
        "card_status_counts": g["card_status_counts"],
        "cards_digest": g["cards_digest"], "records_digest": g["records_digest"],
        "missing_field_summary": g["missing_field_summary"],
        "degraded_count": g["degraded_count"], "partial_count": g["partial_count"],
        "parse_failure_count": len(g["parse_failures"]),
        "parse_failures": g["parse_failures"], "edge_summary": g["edge_summary"],
        "validation": {"ok": g["validation"]["ok"], "checked": g["validation"]["checked"],
                       "error_count": len(g["validation"]["errors"])},
    }


def _render_summary_md(man):
    lines = ["# skill.card index -- %s" % man["namespace"], "",
             "roots: %s" % ", ".join(man["roots"]),
             "skills: %d  records: %d  parse_failures: %d" % (
                 man["skill_count"], man["total_records"], man["parse_failure_count"]),
             "cards_digest: %s" % man["cards_digest"],
             "records_digest: %s" % man["records_digest"], "",
             "## card status", ""]
    for k in sorted(man["card_status_counts"].keys()):
        lines.append("- %s: %d" % (k, man["card_status_counts"][k]))
    lines += ["", "## missing section-9 fields (surfaced, never crash)", ""]
    if man["missing_field_summary"]:
        for k in sorted(man["missing_field_summary"].keys()):
            lines.append("- %s: %d" % (k, man["missing_field_summary"][k]))
    else:
        lines.append("- (none)")
    lines += ["", "## edges", "",
              "- total: %d  resolved_internal: %d  external: %d" % (
                  man["edge_summary"]["total"], man["edge_summary"]["resolved_internal"],
                  man["edge_summary"]["external"]), ""]
    if man["parse_failures"]:
        lines += ["## parse failures (surfaced, not dropped)", ""]
        for pf in man["parse_failures"]:
            lines.append("- %s: %s (%s)" % (pf["rel"], pf["reason"], cap(pf.get("detail", ""), 80)))
        lines.append("")
    return "\n".join(lines) + "\n"


def _write_generate_artifacts(outdir, g):
    os.makedirs(outdir, exist_ok=True)
    outputs = []

    def emit(name, text, kind):
        p = os.path.join(outdir, name)
        _write_text(p, text)
        outputs.append({"path": os.path.abspath(p), "kind": kind, "name": name})

    emit("cards.json", canon(g["cards"]), "json")
    emit("cards.jsonl", "".join(canon(c) + "\n" for c in g["cards"]), "jsonl")
    emit("records.jsonl", "".join(canon(r) + "\n" for r in g["records"]), "jsonl")
    emit("records.json", canon(g["records"]), "json")
    ing = _ingest_payload(g["namespace"], g["ingest_run_id"], g["records"])
    emit("ingest_records.json", canon(ing), "json")
    man = _index_manifest(g)
    emit("index_manifest.json", canon(man), "json")
    emit("card_warnings.json", canon({"warnings": sorted(set(g["warnings"])),
                                      "parse_failures": g["parse_failures"]}), "json")
    emit("summary.md", _render_summary_md(man), "markdown")
    return outputs


# ------------------------------------------------------------------ ops
def do_cards(args):
    g = generate(args)
    outdir = args.get("output_dir")
    outputs = _write_generate_artifacts(outdir, g) if outdir else []
    return {
        "op": "cards", "namespace": g["namespace"], "skill_count": g["skill_count"],
        "total_records": len(g["records"]), "record_counts_by_kind": g["record_counts_by_kind"],
        "card_status_counts": g["card_status_counts"], "degraded_count": g["degraded_count"],
        "partial_count": g["partial_count"], "missing_field_summary": g["missing_field_summary"],
        "cards_digest": g["cards_digest"], "records_digest": g["records_digest"],
        "validation": {"ok": g["validation"]["ok"], "checked": g["validation"]["checked"],
                       "error_count": len(g["validation"]["errors"]),
                       "ingest_shape_ok": g["validation"]["ingest_shape_ok"],
                       "errors": g["validation"]["errors"][:50]},
        "edge_summary": g["edge_summary"], "ingest_run_id": g["ingest_run_id"],
        "parse_failure_count": len(g["parse_failures"]), "parse_failures": g["parse_failures"],
        "outputs": outputs,
    }


def do_validate(args):
    rp = args.get("records_path")
    if not rp or not os.path.isfile(rp):
        raise CardError("records_not_found", "validate needs records_path (records.jsonl or records.json)")
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
                           "ingest_shape_ok": v["ingest_shape_ok"], "errors": v["errors"][:50]},
            "edge_summary": v["edge_summary"], "outputs": []}


def _write_op_artifact(outdir, name, payload):
    if not outdir:
        return []
    os.makedirs(outdir, exist_ok=True)
    p = os.path.join(outdir, name)
    _write_text(p, canon(payload))
    return [{"path": os.path.abspath(p), "kind": "json", "name": name}]


# ------------------------------------------------------------------ main
def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: skill_card.py <args.json>\n")
        return 2
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            args = json.load(f)
    except Exception as e:
        sys.stderr.write("could not read args file: %r\n" % (e,))
        return 2

    meta_path = args.get("meta_path")
    outdir = args.get("output_dir")
    t0 = time.time()

    def write_meta(d):
        if not meta_path:
            return
        try:
            with open(meta_path, "w", encoding="utf-8") as fh:
                json.dump(d, fh)
        except Exception as e:
            sys.stderr.write("meta write failed: %r\n" % (e,))

    op = str(args.get("op", "cards")).lower()
    try:
        if op == "cards":
            payload = do_cards(args)
        elif op == "eligible":
            payload = do_eligible(args)
            g = payload.pop("_generate", None)
            outs = _write_op_artifact(outdir, "eligible.json",
                                      {k: v for k, v in payload.items() if k != "outputs"})
            if g and outdir:
                outs += _write_generate_artifacts(outdir, g)
            payload["outputs"] = outs
        elif op == "retrieve":
            payload = do_retrieve(args)
            g = payload.pop("_generate", None)
            outs = _write_op_artifact(outdir, "retrieval.json",
                                      {k: v for k, v in payload.items() if k != "outputs"})
            if g and outdir:
                outs += _write_generate_artifacts(outdir, g)
            payload["outputs"] = outs
        elif op == "validate":
            payload = do_validate(args)
        else:
            raise CardError("invalid_op", "unknown op '%s' (cards|eligible|retrieve|validate)" % op)

        meta = {"ok": True, "runtime_ms": int((time.time() - t0) * 1000),
                "worker": {"name": "skill.card", "version": WORKER_VERSION,
                           "python": sys.version.split()[0]}}
        meta.update(payload)
        meta["warnings"] = []
        if payload.get("parse_failures"):
            meta["warnings"] = ["%d parse failure(s) surfaced" % len(payload["parse_failures"])]
        if payload.get("degraded_count"):
            meta["warnings"].append("%d degraded card(s)" % payload["degraded_count"])
        write_meta(meta)
        sys.stdout.write("SKILL_CARD_OK op=%s skills=%s\n" % (op, payload.get("skill_count", "-")))
        return 0
    except CardError as ce:
        write_meta({"ok": False, "error_code": ce.code, "error": ce.message,
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("%s: %s\n" % (ce.code, ce.message))
        return 1
    except Exception as e:
        tb = traceback.format_exc()
        sys.stderr.write(tb + "\n")
        write_meta({"ok": False, "error_code": "skill_card_failed", "error": repr(e)[:500],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
