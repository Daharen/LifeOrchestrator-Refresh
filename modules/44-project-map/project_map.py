#!/usr/bin/env python3
# -*- coding: ascii -*-
"""project.map 0.1.0 -- the Project Comprehension Bootstrap (PCB) mechanism (i46, module:44).

Deterministic stdlib-only worker (Python 3.10-compatible). Harvests mechanical repo facts,
validates the canonical map state fail-closed, idempotently ingests evidence-pointed claims via a
staged-tree atomic swap, and renders bounded progressive-disclosure views (BOOT_PACKET/L0/L1/ALIASES)
only from validated state. READ-ONLY over the repo outside its own map/ generated/ runtime/ fixtures/.

Envelope: SKILL_CONTRACT v0.2 (lifeorch.skill.result/0.1) on stdout. A logical refusal is exit 0 +
status:"error" + a machine error.code from the closed table (see CODES). Nonzero exit = crash only.
Canonical bytes: LF, UTF-8, no BOM, sorted keys + explicitly sorted arrays; every content sha256 is
computed over CRLF->LF-normalized bytes; KB = 1000. No datetime.now()/randomness in any artifact byte.

Governing spec: modules/44-project-map/WORK_ORDER.md (frozen; sha256
439261078ffeb0169e22de4829e9024081b50470187d78901dd9f2479a550725 over LF bytes). RT-1 findings
F1-F24 are folded into the spec and into this implementation.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys

SCHEMA_ENTITIES = "lifeorch.project_map/0.1"
SCHEMA_OVERLAY = "lifeorch.map_overlay/0.1"
SCHEMA_CLAIMS = "lifeorch.map_claims/0.1"
SKILL_ID = "project.map"
SKILL_VERSION = "0.1.0"
CONTRACT_VERSION = "0.2"
WORK_ORDER_SHA256 = "439261078ffeb0169e22de4829e9024081b50470187d78901dd9f2479a550725"
KB = 1000
BOOT_PACKET_HARD = 20000

# ---- closed namespace / enum tables (WO s2) -------------------------------------------------
NS_ENUM = (
    "module", "widget", "plane", "arch", "contract", "doc", "store",
    "decision", "mandate", "pb", "iteration", "wave", "ops", "future",
)
NS_STUB = ("decision", "mandate", "pb", "iteration", "wave", "future")  # meta.json thin stubs
STATUS_ENUM = (
    "proposed", "ready", "in-progress", "blocked", "mvp-complete", "active",
    "design-only", "frozen", "deferred", "deprecated", "replaced",
)
EDGE_TYPES = (
    "produces", "consumes", "invokes", "routes-to", "retrieves-from", "compiles-for",
    "verifies", "authorizes", "audits", "persists", "supersedes", "depends-on",
    "governs", "realizes", "documents",
)
DERIVED_EDGE_TYPES = ("member-of",)
DEEPER_KINDS = (
    "readme", "work-order", "schema-notes", "contract", "decision",
    "failure", "research", "test", "trace", "other",
)
PLANES = ("memory", "intelligence", "capability", "authority", "observability")
ID_RE = re.compile(r"^[a-z]+:[A-Za-z0-9._/-]+$")
# harvestable (mechanical) module fields the map may hold; a mismatch vs harvest = CONFLICT_HARVEST
HARVEST_FIELDS = ("version", "purpose", "determinism", "parallel_safe", "inputs", "outputs", "requirements")

# ---- closed error-code table (WO s3.9) ------------------------------------------------------
CODES = (
    "SCHEMA_INVALID", "ID_GRAMMAR", "UNKNOWN_NS", "UNKNOWN_EDGE_TYPE", "DUP_ID", "DUP_EDGE",
    "DANGLING_REF", "MISSING_PROVENANCE", "FIELD_UNCOVERED", "CLAIM_RESTATES_HARVEST",
    "CONFLICT_HARVEST", "CONFLICT_CLAIMS", "DERIVED_FIELD_AUTHORED", "HARVEST_ORPHAN",
    "ENTITY_UNBACKED", "STALE_LOAD_BEARING", "STALE_BUDGET", "OVERLAY_MANDATE_DRIFT",
    "OVERLAY_PROHIBITIONS_EMPTY", "OVERLAY_DANGLING", "SKELETON_UNRESOLVED", "SKELETON_LOAD_BEARING",
    "DIRTY_TREE", "DRAFT_RENDER", "PACKET_OVER_BUDGET", "GENERATED_DRIFT", "FMT_NONCANONICAL",
    "UNSUPPORTED_QUERY", "PARSE_ROW_FAILED",
)
# deterministic reporting order for a representative error.code when several findings exist
CODE_ORDER = {c: i for i, c in enumerate(CODES)}


class Refuse(Exception):
    """A logical refusal: exit 0, status:error, error.code from CODES."""

    def __init__(self, code, message, findings=None, result=None):
        super().__init__(message)
        assert code in CODES, "unknown error code %r" % code
        self.code = code
        self.message = message
        self.findings = findings or [{"code": code, "message": message}]
        self.result = result


# ---- canonical bytes (WO s0) ----------------------------------------------------------------
def norm(data):
    """CRLF->LF normalization; the basis of every content sha256 (RT1-F5)."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    return data.replace(b"\r\n", b"\n")


def sha256_norm(data):
    return hashlib.sha256(norm(data)).hexdigest()


def sha256_file(path):
    with open(path, "rb") as fh:
        return sha256_norm(fh.read())


# sort keys per array-holding path so filesystem/enumeration order never leaks (RT1-F17)
def _sort_key_for(obj):
    if isinstance(obj, dict):
        if "id" in obj and "ns" in obj:                 # entity record
            return ("\x00id", obj.get("id", ""))
        if "from" in obj and "type" in obj and "to" in obj:   # edge record
            return ("\x01edge", obj.get("from", ""), obj.get("type", ""), obj.get("to", ""))
        if "ref" in obj and "by" in obj:                # source record
            return ("\x02src", obj.get("ref", ""), obj.get("by", ""), _stable(obj.get("fields", [])))
        if "kind" in obj and "ref" in obj:              # deeper pointer
            return ("\x03deep", obj.get("kind", ""), obj.get("ref", ""))
        return ("\x04dict", _stable(obj))
    return ("\x05val", _stable(obj))


def _stable(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))


def sort_arrays(obj):
    """Recursively return obj with every list explicitly sorted by a stated key (deterministic)."""
    if isinstance(obj, dict):
        return {k: sort_arrays(v) for k, v in obj.items()}
    if isinstance(obj, list):
        items = [sort_arrays(v) for v in obj]
        try:
            items.sort(key=_sort_key_for)
        except TypeError:
            items.sort(key=_stable)
        return items
    return obj


def dumps_map(obj):
    """Pinned canonical form for map/ + claims/ files: indent=1, sorted keys + arrays, trailing LF."""
    return json.dumps(sort_arrays(obj), sort_keys=True, indent=1) + "\n"


def dumps_compact(obj):
    """Pinned canonical form for runtime/ harvest + query output: compact separators."""
    return json.dumps(sort_arrays(obj), sort_keys=True, separators=(",", ":"))


def write_lf(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def read_text(path):
    with open(path, "rb") as fh:
        return norm(fh.read()).decode("utf-8")


# ---- parse_budgets import (WO s3.1, RT1-F24) ------------------------------------------------
_GDH_CACHE = {}


def _load_gen_doc_health(repo):
    """importlib path-load ops/audit/gen-doc-health.py; re-implementation is FORBIDDEN (RT1-F24)."""
    path = os.path.join(repo, "ops", "audit", "gen-doc-health.py")
    if path in _GDH_CACHE:
        return _GDH_CACHE[path]
    if not os.path.isfile(path):
        raise Refuse("SCHEMA_INVALID", "cannot import parse_budgets: %s missing" % path)
    spec = importlib.util.spec_from_file_location("gen_doc_health_import", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _GDH_CACHE[path] = mod
    return mod


def imported_parse_budgets(repo, core_dir=None):
    """Call the IMPORTED parse_budgets(). core_dir overrides mod.CORE for fixture parity (RT1-F24)."""
    mod = _load_gen_doc_health(repo)
    saved = getattr(mod, "CORE", None)
    if core_dir is not None:
        mod.CORE = core_dir
    try:
        return dict(mod.parse_budgets())
    finally:
        if core_dir is not None:
            mod.CORE = saved


# ---- harvest (WO s3.1) ----------------------------------------------------------------------
MODULE_DIR_RE = re.compile(r"^(\d{1,2}(?:\.\d+)?)-(.+)$")
WIDGET_DIR_RE = re.compile(r"^(\d{1,2})-(.+)$")
INVENTORY_EXTS = (".py", ".ps1", ".psm1", ".md", ".json", ".txt", ".bat", ".jsonl", ".mermaid", ".svg")
INVENTORY_SKIP_DIRS = ("runtime", "artifacts", "__pycache__", ".git", "node_modules", "venvs",
                       "bin", "obj", "_to_delete", "_to_delete_w07", ".af_editor_tmp")


def _first_sentence(text):
    if not text:
        return ""
    t = " ".join(str(text).split())
    m = re.search(r"[.!?](\s|$)", t)
    return t[:m.start() + 1] if m else t


def _clip160(text):
    t = " ".join(str(text or "").split())
    return t[:160]


def _inventory(repo):
    inv = {}
    for top in ("modules", "widgets", "core-docs", "ops"):
        base = os.path.join(repo, top)
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in INVENTORY_SKIP_DIRS)
            for fn in sorted(files):
                if os.path.splitext(fn)[1].lower() not in INVENTORY_EXTS:
                    continue
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, repo).replace(os.sep, "/")
                try:
                    inv[rel] = sha256_file(full)
                except OSError:
                    continue
    return inv


def _harvest_modules(repo):
    out = []
    base = os.path.join(repo, "modules")
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        d = os.path.join(base, name)
        if not os.path.isdir(d):
            continue
        m = MODULE_DIR_RE.match(name)
        if not m:
            continue
        num, slug = m.group(1), m.group(2)
        rec = {"dir": name, "num": num, "dir_slug": slug,
               "has_readme": os.path.isfile(os.path.join(d, "README.md")),
               "has_work_order": os.path.isfile(os.path.join(d, "WORK_ORDER.md")),
               "has_schema_notes": os.path.isfile(os.path.join(d, "SCHEMA_NOTES.md")),
               "has_tests": os.path.isdir(os.path.join(d, "tests")),
               "has_skill_json": os.path.isfile(os.path.join(d, "skill.json"))}
        sj = os.path.join(d, "skill.json")
        if os.path.isfile(sj):
            try:
                man = json.loads(read_text(sj))
            except Exception:
                man = {}
            rec["skill_id"] = man.get("skill_id")
            rec["version"] = man.get("version")
            rec["purpose"] = man.get("purpose")
            rec["purpose_first_sentence"] = _first_sentence(man.get("purpose"))
            rec["determinism"] = man.get("determinism")
            rec["parallel_safe"] = man.get("parallel_safe")
            rec["inputs"] = man.get("inputs")
            rec["outputs"] = man.get("outputs")
            rec["requirements"] = man.get("requirements")
            rec["skill_json_sha256"] = sha256_file(sj)
        out.append(rec)
    return out


def _harvest_widgets(repo):
    out = []
    base = os.path.join(repo, "widgets")
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        d = os.path.join(base, name)
        if not os.path.isdir(d):
            continue
        m = WIDGET_DIR_RE.match(name)
        if not m:
            continue
        out.append({"dir": name, "num": m.group(1), "dir_slug": m.group(2),
                    "has_readme": os.path.isfile(os.path.join(d, "README.md")),
                    "has_launch": os.path.isfile(os.path.join(d, "launch.bat"))})
    return out


def _harvest_core_docs(repo, budgets):
    out = []
    base = os.path.join(repo, "core-docs")
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        p = os.path.join(base, name)
        if not (os.path.isfile(p) and name.endswith(".md")):
            continue
        with open(p, "rb") as fh:
            nb = norm(fh.read())
        out.append({"name": name, "path": "core-docs/" + name, "bytes_lf": len(nb),
                    "budget_kb": budgets.get(name), "sha256": sha256_norm(nb)})
    return out


def _parse_doc_owner_rows(repo):
    """Parse the DOC_PROTOCOL s2 owner table. A row that LOOKS like a data row inside the s2 table
    but fails the `| doc | owns | budget |` shape is a HARD error (PARSE_ROW_FAILED, RT1-F24)."""
    txt = read_text(os.path.join(repo, "core-docs", "DOC_PROTOCOL.md"))
    lines = txt.split("\n")
    rows = []
    in_s2 = False
    seen_header = False
    for ln in lines:
        if ln.startswith("## "):
            was = in_s2
            in_s2 = ln.lstrip("# ").strip().startswith("2.")
            if was and not in_s2:
                break
            seen_header = False
            continue
        if not in_s2:
            continue
        s = ln.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if re.match(r"^\|?\s*:?-{2,}", s) or all(set(c) <= set("-: ") for c in cells):
            continue  # separator row
        if not seen_header:
            seen_header = True
            if [c.lower() for c in cells[:3]] != ["doc", "owns", "budget"]:
                raise Refuse("PARSE_ROW_FAILED",
                             "DOC_PROTOCOL s2 header row is not `| doc | owns | budget |`: %r" % s)
            continue
        if len(cells) < 3 or not cells[0] or not cells[1] or not cells[2]:
            raise Refuse("PARSE_ROW_FAILED", "DOC_PROTOCOL s2 row failed to parse: %r" % s)
        rows.append({"doc": cells[0], "owns": cells[1], "budget": cells[2]})
    return rows


def _parse_decision_ids(repo):
    txt = read_text(os.path.join(repo, "core-docs", "DECISION_LOG_INDEX.md"))
    ids = []
    for ln in txt.split("\n"):
        m = re.match(r"^\|\s*(D-\d{4})\b", ln)
        if m:
            ids.append(m.group(1))
    seen, uniq = set(), []
    for i in ids:
        if i not in seen:
            seen.add(i)
            uniq.append(i)
    return uniq


def _parse_mandate_header(repo):
    txt = read_text(os.path.join(repo, "core-docs", "PROCESS_MANDATE.md"))
    hdr = {}
    for m in re.finditer(r"^-\s*`([a-z_]+):\s*([^`]*)`", txt, re.M):
        hdr[m.group(1)] = m.group(2).strip()
    return hdr


def _parse_arch_spine(repo):
    txt = read_text(os.path.join(repo, "core-docs", "ARCHITECTURE_MAP.md"))
    out = []
    seen = set()
    for ln in txt.split("\n"):
        m = re.match(r"^-\s*\*\*(\d{1,2}(?:\.\d+)?)\b\s*(?:`([^`]+)`)?\s*\*\*\s*(.*)$", ln)
        if not m:
            continue
        num, ident, rest = m.group(1), m.group(2), m.group(3)
        if num in seen:
            continue
        seen.add(num)
        rest = rest.strip()
        # split on ' - ', ' -- ', or an em-dash (U+2014); \u2014 keeps this source ASCII
        prose = re.split("\\s+(?:-{1,2}|\u2014)\\s+", rest, 1)[0]
        prose = prose.strip().strip("*").strip()
        # one_line: strip a leading dash/em-dash separator (arch 0-26 rows lead with one)
        one = re.sub("^(?:-{1,2}|\u2014)\\s*", "", rest).strip()
        display = ident if ident else prose
        out.append({"num": num, "skill_id": ident, "display_name": display,
                    "one_line": _clip160(one if one else prose)})
    return out


def op_harvest(repo, at_commit, dirty):
    repo = os.path.abspath(repo)
    budgets = imported_parse_budgets(repo)
    harvest = {
        "schema": "lifeorch.project_map.harvest/0.1",
        "at_commit": at_commit,
        "dirty": bool(dirty),
        "modules": _harvest_modules(repo),
        "widgets": _harvest_widgets(repo),
        "core_docs": _harvest_core_docs(repo, budgets),
        "doc_owner_rows": _parse_doc_owner_rows(repo),
        "decision_ids": _parse_decision_ids(repo),
        "mandate": _parse_mandate_header(repo),
        "arch": _parse_arch_spine(repo),
        "budgets": budgets,
        "inventory": _inventory(repo),
    }
    harvest["counts"] = {
        "modules": len(harvest["modules"]),
        "widgets": len(harvest["widgets"]),
        "core_docs": len(harvest["core_docs"]),
        "arch": len(harvest["arch"]),
        "decision_ids": len(harvest["decision_ids"]),
        "doc_owner_rows": len(harvest["doc_owner_rows"]),
    }
    return harvest


# ---- map load (WO s1/s2) --------------------------------------------------------------------
ENTITY_FILE_NS = {
    "modules.json": "module", "widgets.json": "widget", "planes.json": "plane",
    "arch-positions.json": "arch", "contracts.json": "contract", "docs.json": "doc",
    "ops.json": "ops", "stores.json": "store", "meta.json": None,   # meta = stub namespaces
}
COVERABLE_FIELDS = (
    "one_line", "plane_primary", "planes_secondary", "status", "version", "purpose",
    "inputs", "outputs", "determinism", "parallel_safe", "requirements", "state_owned",
    "authority_level", "audit_surfaces", "aliases", "authority_docs", "deeper",
)


class MapModel(object):
    def __init__(self):
        self.entities = {}        # id -> record
        self.entity_files = {}    # id -> filename
        self.edges = []           # list of {from,type,to,sources,_file}
        self.overlay = None
        self.raw = {}             # relpath -> raw text (for fmt)
        self.load_errors = []     # (code, message)


def _ns_of(ident):
    return ident.split(":", 1)[0] if ":" in ident else None


def load_map(map_dir):
    m = MapModel()
    ent_dir = os.path.join(map_dir, "entities")
    if os.path.isdir(ent_dir):
        for fn in sorted(os.listdir(ent_dir)):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(ent_dir, fn)
            raw = read_text(path)
            m.raw["entities/" + fn] = raw
            try:
                doc = json.loads(raw)
            except Exception as e:
                m.load_errors.append(("SCHEMA_INVALID", "entities/%s not valid JSON: %s" % (fn, e)))
                continue
            if not isinstance(doc, dict) or doc.get("schema") != SCHEMA_ENTITIES or doc.get("kind") != "entities":
                m.load_errors.append(("SCHEMA_INVALID", "entities/%s bad wrapper (schema/kind)" % fn))
                continue
            for rec in doc.get("items", []):
                if not isinstance(rec, dict) or "id" not in rec:
                    m.load_errors.append(("SCHEMA_INVALID", "entities/%s item missing id" % fn))
                    continue
                rid = rec["id"]
                if rid in m.entities:
                    m.load_errors.append(("DUP_ID", "duplicate id %s (in %s and %s)" %
                                          (rid, m.entity_files.get(rid), fn)))
                    continue
                m.entities[rid] = rec
                m.entity_files[rid] = fn
    rel = os.path.join(map_dir, "relationships.json")
    if os.path.isfile(rel):
        raw = read_text(rel)
        m.raw["relationships.json"] = raw
        try:
            doc = json.loads(raw)
            if doc.get("schema") != SCHEMA_ENTITIES or doc.get("kind") != "relationships":
                m.load_errors.append(("SCHEMA_INVALID", "relationships.json bad wrapper"))
            else:
                seen = set()
                for e in doc.get("items", []):
                    e = dict(e)
                    e["_file"] = "relationships.json"
                    m.edges.append(e)
                    key = (e.get("from"), e.get("type"), e.get("to"))
                    if key in seen:
                        m.load_errors.append(("DUP_EDGE", "duplicate edge %s in relationships.json" % (key,)))
                    seen.add(key)
        except Exception as e:
            m.load_errors.append(("SCHEMA_INVALID", "relationships.json not valid JSON: %s" % e))
    ov = os.path.join(map_dir, "overlay", "state.json")
    if os.path.isfile(ov):
        raw = read_text(ov)
        m.raw["overlay/state.json"] = raw
        try:
            m.overlay = json.loads(raw)
        except Exception as e:
            m.load_errors.append(("SCHEMA_INVALID", "overlay/state.json not valid JSON: %s" % e))
    return m


# ---- derived facts --------------------------------------------------------------------------
def _overlay_ref_ids(overlay, keys=("phase", "frontier", "prohibitions", "open_rulings", "boot_read")):
    """Ids referenced by the named overlay sections. Default = all pointer sections (dangling check);
    load_bearing derivation passes keys=('prohibitions','frontier') only (RT1-F15, WO s2.2)."""
    ids = set()
    if not isinstance(overlay, dict):
        return ids

    def _collect(v):
        if isinstance(v, str) and ":" in v and _ns_of(v) in NS_ENUM:
            ids.add(v)
        elif isinstance(v, dict):
            for kk, vv in v.items():
                _collect(vv)
        elif isinstance(v, list):
            for vv in v:
                _collect(vv)
    for key in keys:
        if key in overlay:
            _collect(overlay[key])
    return ids


def _inbound_supersedes(edges):
    s = set()
    for e in edges:
        if e.get("type") == "supersedes" and e.get("to"):
            s.add(e["to"])
    return s


def compute_load_bearing(entities, edges, overlay):
    """DERIVED (never authored, RT1-F15): true iff ns==contract OR plane_primary==authority OR
    referenced by overlay prohibitions/frontier OR status in {active,in-progress}."""
    ov_refs = _overlay_ref_ids(overlay, keys=("prohibitions", "frontier"))
    lb = {}
    for rid, rec in entities.items():
        lb[rid] = (
            _ns_of(rid) == "contract"
            or rec.get("plane_primary") == "authority"
            or rid in ov_refs
            or rec.get("status") in ("active", "in-progress")
        )
    return lb


# ---- validate (WO s3.2) ---------------------------------------------------------------------
def _valid_source_shape(s):
    if not isinstance(s, dict):
        return False
    if not isinstance(s.get("ref"), str) or not s["ref"]:
        return False
    if "sha256" in s and s["sha256"] is not None:
        if not (isinstance(s["sha256"], str) and re.match(r"^[0-9a-f]{64}$", s["sha256"])):
            return False
    if not isinstance(s.get("fields"), list) or not all(isinstance(x, str) for x in s["fields"]):
        return False
    if not isinstance(s.get("by"), str) or not s["by"]:
        return False
    return True


def _ref_is_path(ref):
    base = ref.split("#", 1)[0]
    if ":" in base and _ns_of(base) in NS_ENUM:
        return False
    return True


def validate(model, harvest, is_real=True):
    """Return a list of findings [{code, where, message}]; empty list == valid. ALL findings reported."""
    F = []

    def add(code, where, message):
        F.append({"code": code, "where": where, "message": message})

    for code, msg in model.load_errors:
        add(code, "load", msg)

    ents = model.entities
    lb = compute_load_bearing(ents, model.edges, model.overlay)

    # ---- per-entity structural + provenance ----
    for rid, rec in sorted(ents.items()):
        w = rid
        if not ID_RE.match(rid):
            add("ID_GRAMMAR", w, "id fails grammar ^[a-z]+:[A-Za-z0-9._/-]+$")
        ns = _ns_of(rid)
        if ns not in NS_ENUM:
            add("UNKNOWN_NS", w, "namespace %r not in closed enum" % ns)
        if rec.get("ns") != ns:
            add("SCHEMA_INVALID", w, "ns field %r != id namespace %r" % (rec.get("ns"), ns))
        if not isinstance(rec.get("display_name"), str) or not rec["display_name"]:
            add("SCHEMA_INVALID", w, "display_name required (non-empty string)")
        ol = rec.get("one_line")
        if not isinstance(ol, str) or not ol:
            add("SCHEMA_INVALID", w, "one_line required (non-empty string)")
        elif len(ol) > 160:
            add("SCHEMA_INVALID", w, "one_line exceeds 160 chars (%d)" % len(ol))
        if "load_bearing" in rec:
            add("DERIVED_FIELD_AUTHORED", w, "load_bearing is DERIVED; must not be authored")
        st = rec.get("status")
        if st is not None and st not in STATUS_ENUM:
            add("SCHEMA_INVALID", w, "status %r not in enum" % st)
        pp = rec.get("plane_primary")
        if pp is not None and pp not in PLANES:
            add("SCHEMA_INVALID", w, "plane_primary %r not a plane" % pp)
        for sp in rec.get("planes_secondary", []) or []:
            if sp not in PLANES:
                add("SCHEMA_INVALID", w, "planes_secondary %r not a plane" % sp)
        skeleton = bool(rec.get("skeleton"))
        if ns in ("module", "widget", "ops") and not skeleton and pp is None:
            add("SCHEMA_INVALID", w, "plane_primary required for %s unless skeleton:true" % ns)
        conf = rec.get("confidence")
        if conf is not None and conf not in ("established", "uncertain"):
            add("SCHEMA_INVALID", w, "confidence %r not established|uncertain" % conf)
        if conf == "uncertain" and not rec.get("note"):
            add("SCHEMA_INVALID", w, "confidence:uncertain requires a note")
        for d in rec.get("deeper", []) or []:
            if not isinstance(d, dict) or d.get("kind") not in DEEPER_KINDS or not d.get("ref"):
                add("SCHEMA_INVALID", w, "deeper item malformed or bad kind: %r" % (d,))
        if skeleton and lb.get(rid):
            add("SKELETON_LOAD_BEARING", w, "skeleton:true entity is load-bearing-derived")
        # sources
        srcs = rec.get("sources")
        if not isinstance(srcs, list) or len(srcs) < 1:
            add("MISSING_PROVENANCE", w, "entity has no sources[]")
            srcs = []
        covered = set()
        for s in srcs:
            if not _valid_source_shape(s):
                add("SCHEMA_INVALID", w, "source has invalid pinned shape: %r" % (s,))
                continue
            for fld in s.get("fields", []):
                covered.add(fld)
            ref = s["ref"]
            if _ref_is_path(ref):
                if s.get("sha256") in (None, ""):
                    add("MISSING_PROVENANCE", w, "path source %r missing sha256 (required for path refs)" % ref)
            else:
                tgt = ref.split("#", 1)[0]
                if tgt not in ents:
                    add("DANGLING_REF", w, "source ref %r does not resolve to an entity" % ref)
        # per-field provenance coverage
        if "*" not in covered:
            for fld in COVERABLE_FIELDS:
                if fld in rec and rec.get(fld) not in (None, [], {}) and fld not in covered:
                    add("FIELD_UNCOVERED", w, "field %r not covered by any source.fields" % fld)

    # ---- global uniqueness already handled at load (DUP_ID) ----

    # ---- edges ----
    ef_seen = {}
    for e in model.edges:
        fr, ty, to = e.get("from"), e.get("type"), e.get("to")
        w = "edge %s -[%s]-> %s" % (fr, ty, to)
        if ty in DERIVED_EDGE_TYPES:
            add("DERIVED_FIELD_AUTHORED", w, "member-of is DERIVED; must not be authored")
            continue
        if ty not in EDGE_TYPES:
            add("UNKNOWN_EDGE_TYPE", w, "edge type %r not in closed enum" % ty)
        if fr not in ents:
            add("DANGLING_REF", w, "edge 'from' %r does not resolve" % fr)
        if to not in ents:
            add("DANGLING_REF", w, "edge 'to' %r does not resolve" % to)
        if ty == "realizes" and (_ns_of(fr) not in ("module", "widget") or _ns_of(to) != "arch"):
            add("SCHEMA_INVALID", w, "realizes must be module:/widget: -> arch:")
        if ty in ("persists", "retrieves-from") and _ns_of(to) != "store":
            add("SCHEMA_INVALID", w, "%s must target a store: id" % ty)
        if ty == "governs" and _ns_of(fr) not in ("contract", "doc"):
            add("SCHEMA_INVALID", w, "governs must originate at contract:/doc:")
        es = e.get("sources")
        if not isinstance(es, list) or len(es) < 1:
            add("MISSING_PROVENANCE", w, "edge has no sources[]")
        else:
            for s in es:
                if not _valid_source_shape(s):
                    add("SCHEMA_INVALID", w, "edge source has invalid shape: %r" % (s,))
        key = (e.get("_file"), fr, ty, to)
        if key in ef_seen:
            add("DUP_EDGE", w, "duplicate (from,type,to) within %s" % e.get("_file"))
        ef_seen[key] = True

    # outbound edge-count WARN (>15 of one type) is a warning, collected separately
    warnings = []
    otc = {}
    for e in model.edges:
        otc[(e.get("from"), e.get("type"))] = otc.get((e.get("from"), e.get("type")), 0) + 1
    for (fr, ty), n in sorted(otc.items()):
        if n > 15:
            warnings.append("entity %s has %d outbound %s edges (>15)" % (fr, n, ty))

    # ---- deeper / authority_docs referential integrity ----
    for rid, rec in sorted(ents.items()):
        for d in rec.get("deeper", []) or []:
            if not isinstance(d, dict):
                continue
            ref = d.get("ref", "")
            if isinstance(ref, str) and not _ref_is_path(ref):
                tgt = ref.split("#", 1)[0]
                if tgt not in ents and _ns_of(tgt) not in ("decision", "contract"):
                    add("DANGLING_REF", rid, "deeper ref %r does not resolve" % ref)
        for ref in rec.get("authority_docs", []) or []:
            if isinstance(ref, str):
                tgt = ref.split("#", 1)[0]
                if _ns_of(tgt) in ("doc", "contract") and tgt not in ents:
                    add("DANGLING_REF", rid, "authority_docs ref %r does not resolve" % ref)

    # ---- harvest-dependent checks (coverage / conflict / staleness) ----
    stale_entities = set()
    if harvest is not None:
        inv = harvest.get("inventory", {})
        # coverage: HARVEST_ORPHAN
        for mod in harvest.get("modules", []):
            num, sid, slug = mod.get("num"), mod.get("skill_id"), mod.get("dir_slug")
            cand = set()
            if sid:
                cand.add("module:%s/%s" % (num, sid))
            cand.add("module:%s/%s" % (num, slug))
            if not any(c in ents for c in cand):
                if not any(_ns_of(x) == "module" and ents[x].get("ns") == "module"
                           and x.split(":", 1)[1].split("/", 1)[0] == num for x in ents):
                    add("HARVEST_ORPHAN", "module %s" % mod.get("dir"),
                        "harvested module dir %s has no map entity" % mod.get("dir"))
        for wid in harvest.get("widgets", []):
            eid = "widget:%s/%s" % (wid.get("num"), wid.get("dir_slug"))
            if eid not in ents:
                add("HARVEST_ORPHAN", "widget %s" % wid.get("dir"),
                    "harvested widget dir %s has no map entity" % wid.get("dir"))
        for cd in harvest.get("core_docs", []):
            eid = "doc:" + cd.get("path")
            if eid not in ents:
                add("HARVEST_ORPHAN", "doc %s" % cd.get("path"),
                    "harvested core-doc %s has no map entity" % cd.get("path"))
        # ENTITY_UNBACKED + staleness (per FIELD)
        for rid, rec in sorted(ents.items()):
            for s in rec.get("sources", []) or []:
                if not isinstance(s, dict):
                    continue
                ref = s.get("ref", "")
                if not isinstance(ref, str) or not _ref_is_path(ref):
                    continue
                path = ref.split("#", 1)[0]
                cur = inv.get(path)
                if cur is None:
                    add("ENTITY_UNBACKED", rid, "path source %r no longer exists in the tree" % path)
                    continue
                if s.get("sha256") and s["sha256"] != cur:
                    flds = list(rec.keys()) if "*" in (s.get("fields") or []) else (s.get("fields") or [])
                    stale_entities.add(rid)
                    if lb.get(rid):
                        add("STALE_LOAD_BEARING", rid,
                            "load-bearing entity has stale field(s) %s (source %s)" % (flds, path))
        # STALE_BUDGET
        if ents and (len(stale_entities) / float(len(ents))) > 0.20:
            add("STALE_BUDGET", "map",
                "%d/%d entities carry a stale field (>20%%)" % (len(stale_entities), len(ents)))
        # CONFLICT_HARVEST
        hmods = {}
        for mod in harvest.get("modules", []):
            for cand_id in (("module:%s/%s" % (mod.get("num"), mod.get("skill_id"))) if mod.get("skill_id") else None,
                            "module:%s/%s" % (mod.get("num"), mod.get("dir_slug"))):
                if cand_id:
                    hmods[cand_id] = mod
        for rid, rec in sorted(ents.items()):
            if _ns_of(rid) != "module" or rid not in hmods:
                continue
            hv = hmods[rid]
            for fld in HARVEST_FIELDS:
                if fld in rec and rec.get(fld) is not None and hv.get(fld) is not None:
                    if rec.get(fld) != hv.get(fld):
                        add("CONFLICT_HARVEST", rid,
                            "field %r=%r conflicts harvested %r" % (fld, rec.get(fld), hv.get(fld)))

    # ---- overlay (WO s2.4) ----
    if model.overlay is not None:
        ov = model.overlay
        w = "overlay"
        if ov.get("schema") != SCHEMA_OVERLAY:
            add("SCHEMA_INVALID", w, "overlay schema must be %s" % SCHEMA_OVERLAY)
        for rid in sorted(_overlay_ref_ids(ov)):
            if rid not in ents:
                add("OVERLAY_DANGLING", w, "overlay pointer %s does not resolve to an entity" % rid)
        # mandate cross-check INVARIANT FIELDS ONLY (RT1-F2)
        if harvest is not None and isinstance(ov.get("mandate"), dict):
            hm = harvest.get("mandate", {})
            om = ov["mandate"]
            if hm:
                if str(om.get("id")) != str(hm.get("mandate_id")):
                    add("OVERLAY_MANDATE_DRIFT", w, "mandate id %r != header %r" % (om.get("id"), hm.get("mandate_id")))
                if str(om.get("sunset_iteration")) != str(hm.get("sunset_iteration")):
                    add("OVERLAY_MANDATE_DRIFT", w, "mandate sunset_iteration mismatch")
                order = {"ACTIVE": 0, "REPORT_DUE": 1, "SUNSET": 2, "RE-LICENSED": 0}
                os_, hs_ = om.get("state"), hm.get("state")
                if os_ in order and hs_ in order and order[hs_] < order[os_]:
                    add("OVERLAY_MANDATE_DRIFT", w, "mandate state regressed header=%s overlay=%s" % (hs_, os_))
                try:
                    if int(hm.get("current_iteration")) < int(ov.get("iteration")):
                        add("OVERLAY_MANDATE_DRIFT", w, "header current_iteration < overlay.iteration")
                except (TypeError, ValueError):
                    pass
        # prohibitions
        prohibitions = ov.get("prohibitions", []) or []
        live_freeze = False
        if harvest is not None:
            live_freeze = harvest.get("mandate", {}).get("state") in ("ACTIVE", "REPORT_DUE")
        if any(r.get("status") == "frozen" for r in ents.values()):
            live_freeze = True
        if live_freeze and not prohibitions:
            add("OVERLAY_PROHIBITIONS_EMPTY", w, "no prohibitions listed while a freeze is live")
        insup = _inbound_supersedes(model.edges)
        for pr in prohibitions:
            auth = pr.get("authority")
            if not (isinstance(auth, str) and _ns_of(auth) == "decision"):
                add("OVERLAY_DANGLING", w, "prohibition authority %r is not a decision: id" % auth)
            elif auth not in ents:
                add("OVERLAY_DANGLING", w, "prohibition authority %s missing from meta" % auth)
            elif auth in insup and pr.get("status") == "live":
                add("OVERLAY_DANGLING", w, "live prohibition authority %s has an inbound supersedes edge" % auth)

    return {"findings": F, "warnings": warnings, "stale_entities": sorted(stale_entities),
            "load_bearing": lb}


# ---- claims standalone validation (WO s2.5; fixture #0 must be accepted byte-verbatim) -------
def validate_claims_standalone(claims):
    F = []

    def add(code, where, message):
        F.append({"code": code, "where": where, "message": message})

    if not isinstance(claims, dict) or claims.get("schema") != SCHEMA_CLAIMS:
        add("SCHEMA_INVALID", "claims", "schema must be %s" % SCHEMA_CLAIMS)
        return F
    if not isinstance(claims.get("by"), str) or not claims["by"]:
        add("SCHEMA_INVALID", "claims", "top-level 'by' required")
    if not isinstance(claims.get("entities"), list) or not isinstance(claims.get("relationships"), list):
        add("SCHEMA_INVALID", "claims", "entities and relationships must be arrays (RT1-F6)")
        return F
    for rec in claims["entities"]:
        if not isinstance(rec, dict) or not isinstance(rec.get("id"), str):
            add("SCHEMA_INVALID", "claims.entity", "entity claim needs an id")
            continue
        rid = rec["id"]
        if not ID_RE.match(rid):
            add("ID_GRAMMAR", rid, "claim id fails grammar")
        if _ns_of(rid) not in NS_ENUM:
            add("UNKNOWN_NS", rid, "claim id namespace not in enum")
        if "load_bearing" in rec:
            add("DERIVED_FIELD_AUTHORED", rid, "claims may not set load_bearing (derived)")
        srcs = rec.get("sources")
        if not isinstance(srcs, list) or len(srcs) < 1:
            add("MISSING_PROVENANCE", rid, "claim entity has no sources[]")
            srcs = []
        for s in srcs:
            if not _valid_source_shape(s):
                add("SCHEMA_INVALID", rid, "claim source invalid shape: %r" % (s,))
        covered = set()
        for s in srcs:
            if isinstance(s, dict):
                for fld in s.get("fields", []) or []:
                    covered.add(fld)
        if "*" not in covered:
            for fld in rec:
                if fld in ("id", "sources", "note", "confidence"):
                    continue
                if fld in COVERABLE_FIELDS and fld not in covered:
                    add("FIELD_UNCOVERED", rid, "claimed field %r not covered by a source" % fld)
        if rec.get("confidence") == "uncertain" and not rec.get("note"):
            add("SCHEMA_INVALID", rid, "uncertain claim requires a note")
    for e in claims["relationships"]:
        if not isinstance(e, dict) or not all(k in e for k in ("from", "type", "to")):
            add("SCHEMA_INVALID", "claims.edge", "edge claim needs from/type/to")
            continue
        if e.get("type") in DERIVED_EDGE_TYPES:
            add("DERIVED_FIELD_AUTHORED", "claims.edge", "claims may not author member-of (derived)")
        elif e.get("type") not in EDGE_TYPES:
            add("UNKNOWN_EDGE_TYPE", "claims.edge", "edge type %r not in enum" % e.get("type"))
        if not isinstance(e.get("sources"), list) or len(e["sources"]) < 1:
            add("MISSING_PROVENANCE", "claims.edge", "edge claim has no sources[]")
    # intra-submission DUP_EDGE
    seen = set()
    for e in claims["relationships"]:
        if not isinstance(e, dict):
            continue
        k = (e.get("from"), e.get("type"), e.get("to"))
        if k in seen:
            add("DUP_EDGE", "claims.edge", "duplicate edge %s within submission" % (k,))
        seen.add(k)
    return F


def _stamp_sources(rec_sources, by_default, at_commit, inventory):
    for s in rec_sources or []:
        if not isinstance(s, dict):
            continue
        s.setdefault("by", by_default)
        s.setdefault("at_commit", at_commit)
        ref = s.get("ref", "")
        if isinstance(ref, str) and _ref_is_path(ref):
            path = ref.split("#", 1)[0]
            if s.get("sha256") in (None, "") and path in inventory:
                s["sha256"] = inventory[path]


def _field_claimants(rec, field):
    out = set()
    for s in rec.get("sources", []) or []:
        if isinstance(s, dict):
            flds = s.get("fields", []) or []
            if field in flds or "*" in flds:
                out.add(s.get("by"))
    return out


def op_ingest_claims(map_dir, claims_file, harvest, override_reason=None):
    claims = json.loads(read_text(claims_file))
    F = validate_claims_standalone(claims)
    if F:
        raise Refuse(_rep_code(F), "claims file failed standalone validation", F,
                     {"phase": "standalone", "findings": F})
    inv = harvest.get("inventory", {}) if harvest else {}
    by_top = claims.get("by")
    at_commit = claims.get("at_commit")

    # CLAIM_RESTATES_HARVEST (needs harvest)
    if harvest is not None:
        hmods = {}
        for mod in harvest.get("modules", []):
            for cid in (("module:%s/%s" % (mod.get("num"), mod.get("skill_id"))) if mod.get("skill_id") else None,
                        "module:%s/%s" % (mod.get("num"), mod.get("dir_slug"))):
                if cid:
                    hmods[cid] = mod
        rF = []
        for rec in claims["entities"]:
            hv = hmods.get(rec.get("id"))
            if not hv:
                continue
            for fld in HARVEST_FIELDS:
                if fld in rec and rec.get(fld) == hv.get(fld):
                    rF.append({"code": "CLAIM_RESTATES_HARVEST", "where": rec["id"],
                               "message": "claim restates harvestable field %r" % fld})
        if rF:
            raise Refuse("CLAIM_RESTATES_HARVEST", "claims restate harvestable facts", rF,
                         {"phase": "restate", "findings": rF})

    # ---- stage a temp copy, apply, validate staged, atomic swap (RT1-F7) ----
    # staged/backup live under the module's runtime/ (declared, gitignored write scope), NOT the
    # module root, so ingest never writes outside {map,generated,runtime} (side_effects contract).
    module_root = os.path.dirname(os.path.abspath(map_dir.rstrip("/\\")))
    stage_root = os.path.join(module_root, "runtime")
    os.makedirs(stage_root, exist_ok=True)
    staged = os.path.join(stage_root, ".map.staged")
    if os.path.exists(staged):
        shutil.rmtree(staged)
    shutil.copytree(map_dir, staged)
    sm = load_map(staged)
    conflicts = []
    upserted_e, upserted_edges = 0, 0

    for rec in claims["entities"]:
        rid = rec["id"]
        _stamp_sources(rec.get("sources"), by_top, at_commit, inv)
        cur = sm.entities.get(rid)
        if cur is None:
            new = {"id": rid, "ns": _ns_of(rid)}
            new.update({k: v for k, v in rec.items() if k != "id"})
            new.setdefault("display_name", rec.get("display_name") or rid.split(":", 1)[1])
            sm.entities[rid] = new
            sm.entity_files[rid] = _file_for_ns(_ns_of(rid))
            upserted_e += 1
            continue
        for fld, val in rec.items():
            if fld in ("id", "sources"):
                continue
            incoming_by = None
            for s in rec.get("sources", []) or []:
                if isinstance(s, dict) and (fld in (s.get("fields") or []) or "*" in (s.get("fields") or [])):
                    incoming_by = s.get("by")
                    break
            incoming_by = incoming_by or by_top
            existing = _field_claimants(cur, fld) if fld in cur else set()
            if not existing or incoming_by in existing:
                cur[fld] = val
            elif override_reason:
                cur[fld] = val
            else:
                conflicts.append({"code": "CONFLICT_CLAIMS", "where": rid,
                                  "message": "field %r held by %s, claim by %s (use --override)"
                                  % (fld, sorted(existing), incoming_by)})
        # merge sources (dedup by (ref,by,fields))
        have = {(s.get("ref"), s.get("by"), _stable(s.get("fields")))
                for s in cur.get("sources", []) if isinstance(s, dict)}
        for s in rec.get("sources", []) or []:
            k = (s.get("ref"), s.get("by"), _stable(s.get("fields")))
            if k not in have:
                cur.setdefault("sources", []).append(s)
                have.add(k)
        if override_reason:
            cur.setdefault("sources", []).append(
                {"ref": rid, "fields": ["*"], "by": by_top, "at_commit": at_commit,
                 "note": "override: " + override_reason})
        upserted_e += 1

    edge_keys = {(e.get("from"), e.get("type"), e.get("to")) for e in sm.edges}
    new_edges = []
    for e in claims["relationships"]:
        _stamp_sources(e.get("sources"), by_top, at_commit, inv)
        k = (e.get("from"), e.get("type"), e.get("to"))
        if k in edge_keys:
            continue
        new_edges.append({kk: vv for kk, vv in e.items() if kk != "_file"})
        edge_keys.add(k)
        upserted_edges += 1
    sm.edges.extend([dict(x, _file="relationships.json") for x in new_edges])

    if conflicts:
        shutil.rmtree(staged)
        raise Refuse("CONFLICT_CLAIMS", "claims conflict with recorded claimants", conflicts,
                     {"phase": "merge", "findings": conflicts})

    # write staged tree canonically, then validate it WITH harvest
    _write_map(sm, staged)
    sm2 = load_map(staged)
    vr = validate(sm2, harvest, is_real=True)
    if vr["findings"]:
        shutil.rmtree(staged)
        raise Refuse(_rep_code(vr["findings"]), "staged tree failed validation; nothing merged",
                     vr["findings"], {"phase": "staged-validate", "findings": vr["findings"]})

    # atomic swap
    backup = os.path.join(stage_root, ".map.backup")
    if os.path.exists(backup):
        shutil.rmtree(backup)
    os.rename(map_dir, backup)
    try:
        os.rename(staged, map_dir)
    except OSError:
        os.rename(backup, map_dir)
        raise
    shutil.rmtree(backup, ignore_errors=True)
    return {"merged": True, "entities_upserted": upserted_e, "edges_upserted": upserted_edges,
            "conflicts": []}


def _file_for_ns(ns):
    for fn, n in ENTITY_FILE_NS.items():
        if n == ns:
            return fn
    return "meta.json"


def _write_map(model, map_dir):
    """Write a MapModel back to canonical per-ns entity files + relationships.json + overlay."""
    ent_dir = os.path.join(map_dir, "entities")
    os.makedirs(ent_dir, exist_ok=True)
    buckets = {fn: [] for fn in ENTITY_FILE_NS}
    for rid, rec in model.entities.items():
        clean = {k: v for k, v in rec.items() if not k.startswith("_")}
        fn = model.entity_files.get(rid) or _file_for_ns(_ns_of(rid))
        if _ns_of(rid) in NS_STUB:
            fn = "meta.json"
        buckets.setdefault(fn, []).append(clean)
    for fn in ENTITY_FILE_NS:
        items = buckets.get(fn, [])
        write_lf(os.path.join(ent_dir, fn),
                 dumps_map({"schema": SCHEMA_ENTITIES, "kind": "entities", "items": items}))
    edges = [{k: v for k, v in e.items() if not k.startswith("_")} for e in model.edges]
    write_lf(os.path.join(map_dir, "relationships.json"),
             dumps_map({"schema": SCHEMA_ENTITIES, "kind": "relationships", "items": edges}))
    if model.overlay is not None:
        write_lf(os.path.join(map_dir, "overlay", "state.json"), dumps_map(model.overlay))


def _rep_code(findings):
    """Representative error.code = the table-order-lowest code among findings."""
    codes = [f["code"] for f in findings if f.get("code") in CODE_ORDER]
    if not codes:
        return "SCHEMA_INVALID"
    return sorted(codes, key=lambda c: CODE_ORDER[c])[0]


# ---- render (WO s3.4 / s4) ------------------------------------------------------------------
GEN_HEADER = ("<!-- GENERATED by project.map render from map/ @ %s -- "
              "DO NOT EDIT; edit map/ + re-render -->")
DRAFT_BANNER = "<!-- DRAFT-STALE: draft render under runtime/; NOT canonical; do not consume -->"
SECTION_BUDGETS = {"1": 2500, "2": 800, "3": 9000, "4": 3000, "5": 2200, "6": 2500}


def _trunc(s, n):
    s = " ".join(str(s or "").split())
    if len(s) <= n:
        return s
    return s[:n - 3] + "..."


def _glance_entities(ents):
    return sorted([r for r in ents.values()
                   if _ns_of(r["id"]) in ("module", "widget", "ops")], key=lambda r: r["id"])


def _member_counts(ents):
    counts = {p: 0 for p in PLANES}
    for r in ents.values():
        pp = r.get("plane_primary")
        if pp in counts:
            counts[pp] += 1
    return counts


def _build_section3(ents, lb, stale_set, trunc, collapse_mvp_widgets):
    lines = ["## SYSTEM AT A GLANCE"]
    by_plane = {p: [] for p in PLANES}
    by_plane["UNPLACED"] = []
    collapsed = 0
    mvp_collapsed = 0
    for r in _glance_entities(ents):
        if r.get("status") in ("deprecated", "replaced"):
            collapsed += 1
            continue
        if collapse_mvp_widgets and _ns_of(r["id"]) == "widget" and r.get("status") == "mvp-complete":
            mvp_collapsed += 1
            continue
        pp = r.get("plane_primary") or "UNPLACED"
        mark = ""
        if r.get("confidence") == "uncertain":
            mark += "?"
        if r["id"] in stale_set:
            mark += "~"
        st = r.get("status") or "-"
        by_plane.setdefault(pp, []).append(
            "- %s%s -- %s [%s]" % (r["id"], (" " + mark) if mark else "", _trunc(r.get("one_line"), trunc), st))
    for p in list(PLANES) + ["UNPLACED"]:
        if by_plane.get(p):
            lines.append("")
            lines.append("### plane: %s" % p)
            lines.extend(sorted(by_plane[p]))
    if collapsed:
        lines.append("")
        lines.append("_(%d deprecated/replaced entities collapsed -- see L1 cards)_" % collapsed)
    if mvp_collapsed:
        lines.append("_(%d mvp-complete widgets collapsed -- see L1 cards)_" % mvp_collapsed)
    return "\n".join(lines) + "\n", collapsed, mvp_collapsed


def _doctrine_lines(ents):
    out = []
    for rid, r in sorted(ents.items()):
        if r.get("doctrine"):
            out.append("- %s (%s)" % (r.get("one_line"), rid))
    return out


def _build_boot_packet(model, harvest, stale_set, lb):
    ents = model.entities
    at = harvest.get("at_commit", "?") if harvest else "?"
    ladder = []
    # section 1: identity + doctrine
    s1 = ["# BOOT_PACKET -- Life Orchestrator (project.map render)",
          "purpose: bounded progressive-disclosure comprehension bootstrap (L0 map -> L1 cards -> L2 retrieval).",
          "", "## DOCTRINE"]
    s1 += _doctrine_lines(ents) or ["- (no doctrine metas present)"]
    sec1 = "\n".join(s1) + "\n"
    # section 2: planes
    mc = _member_counts(ents)
    s2 = ["## PLANES (5)"] + ["- plane: %s -- %d members" % (p, mc[p]) for p in PLANES]
    sec2 = "\n".join(s2) + "\n"
    # section 3 with ladder
    trunc_steps = [96, 72, 56]
    collapse = False
    sec3, collapsed, mvpc = _build_section3(ents, lb, stale_set, 96, False)
    for t in trunc_steps:
        sec3, collapsed, mvpc = _build_section3(ents, lb, stale_set, t, collapse)
        if len(sec3.encode("utf-8")) <= SECTION_BUDGETS["3"]:
            if t != 96:
                ladder.append("one_line truncation -> %d" % t)
            break
        if t != 96:
            ladder.append("one_line truncation -> %d" % t)
    if len(sec3.encode("utf-8")) > SECTION_BUDGETS["3"]:
        collapse = True
        sec3, collapsed, mvpc = _build_section3(ents, lb, stale_set, 56, True)
        ladder.append("collapse mvp-complete widgets to counts")
    # section 4: overlay verbatim
    s4 = ["## OVERLAY"]
    ov = model.overlay or {}
    if ov:
        ph = ov.get("phase", {})
        s4.append("iteration: %s -- phase: %s" % (ov.get("iteration"), (ph.get("text") if isinstance(ph, dict) else ph)))
        fr = ov.get("frontier", {})
        if isinstance(fr, dict):
            s4.append("frontier -> %s: %s" % (fr.get("next_iteration"), _trunc(fr.get("summary"), 280)))
        if ov.get("prohibitions"):
            s4.append("PROHIBITIONS (mandatory):")
            for pr in ov["prohibitions"]:
                s4.append("- [%s] %s (%s)" % (pr.get("status"), _trunc(pr.get("text"), 156), pr.get("authority")))
        for br in ov.get("boot_read", []) or []:
            ref = br.get("ref") if isinstance(br, dict) else br
            s4.append("boot_read: %s" % ref)
    else:
        s4.append("(no overlay authored)")
    sec4 = "\n".join(s4) + "\n"
    # section 5: authority table (rows sorted by doc name -> deterministic regardless of harvest order)
    owner_rows = sorted((harvest.get("doc_owner_rows", []) if harvest else []),
                        key=lambda r: r.get("doc", ""))
    s5 = ["## AUTHORITY (owner docs)"]
    for row in owner_rows:
        s5.append("- %s -- %s" % (row.get("doc"), _trunc(row.get("owns"), 90)))
    sec5 = "\n".join(s5) + "\n"
    if len(sec5.encode("utf-8")) > SECTION_BUDGETS["5"]:
        s5 = ["## AUTHORITY (owner docs)"]
        for row in owner_rows:
            s5.append("- %s -- %s" % (row.get("doc"), _trunc(row.get("owns"), 70)))
        sec5 = "\n".join(s5[:40]) + "\n"
        ladder.append("authority table trimmed to budget")
    # section 6: retrieval protocol
    s6 = ["## RETRIEVAL PROTOCOL",
          "Progressive disclosure: read L0 map -> open L1 card -> retrieve L2 only when relevant.",
          "Do NOT ingest a doc until it is relevant. RECORD every open in your ledger (retrieval is measurement).",
          "First step each session: run `verify` / `query stale` before trusting the packet.",
          "Query invocations (mount VM):",
          "  python3 modules/44-project-map/project_map.py query --map <map> --q entity:<id>",
          "  python3 modules/44-project-map/project_map.py query --map <map> --q edges:<id>",
          "  python3 modules/44-project-map/project_map.py query --map <map> --q deeper:<id>:contract",
          "  python3 modules/44-project-map/project_map.py query --map <map> --q stale"]
    for br in (model.overlay or {}).get("boot_read", []) or []:
        ref = br.get("ref") if isinstance(br, dict) else br
        s6.append("boot_read pointer: %s" % ref)
    sec6 = "\n".join(s6) + "\n"

    stale_ct = len(stale_set)
    uncertain_ct = sum(1 for r in ents.values() if r.get("confidence") == "uncertain")
    body = "\n".join([sec1, sec2, sec3, sec4, sec5, sec6])
    total = len(body.encode("utf-8"))
    return body, total, ladder, stale_ct, uncertain_ct, collapsed


def _freshness_line(stale_ct, uncertain_ct, total, at, draft=False):
    tag = "DRAFT" if draft else "freshness"
    return "> %s: %d stale field(s), %d uncertain, %d entities @ %s" % (tag, stale_ct, uncertain_ct, total, at)


def _render_views(model, harvest, draft=False):
    ents = model.entities
    at = harvest.get("at_commit", "?") if harvest else "?"
    vr = validate(model, harvest, is_real=True)
    stale_set = set(vr["stale_entities"])
    lb = vr["load_bearing"]
    total_ent = len(ents)
    files = {}
    header = GEN_HEADER % at
    # BOOT_PACKET
    body, pbytes, ladder, stale_ct, uncertain_ct, collapsed = _build_boot_packet(model, harvest, stale_set, lb)
    fresh = _freshness_line(stale_ct, uncertain_ct, total_ent, at, draft)
    pkt = "\n".join(([DRAFT_BANNER] if draft else []) + [header, fresh, "", body])
    files["BOOT_PACKET.md"] = pkt if pkt.endswith("\n") else pkt + "\n"
    # L0 system map
    l0 = [header, fresh, "", "# L0 SYSTEM MAP", ""]
    l0.append("## Modules / widgets / ops (by id)")
    for r in _glance_entities(ents):
        l0.append("- %s [%s] plane=%s" % (r["id"], r.get("status", "-"), r.get("plane_primary", "-")))
    l0.append("")
    l0.append("## Architecture positions (arch:) and module<->arch collisions")
    archs = sorted([r for r in ents.values() if _ns_of(r["id"]) == "arch"], key=lambda r: r["id"])
    realizes = {}
    for e in model.edges:
        if e.get("type") == "realizes":
            realizes.setdefault(e["to"], []).append(e["from"])
    for r in archs:
        num = r["id"].split(":", 1)[1]
        coll = " collides-with module:%s*" % num if any(_ns_of(x) == "module" and x.split(":", 1)[1].split("/")[0] == num for x in ents) else ""
        rz = (" <- realizes: " + ", ".join(sorted(realizes.get(r["id"], [])))) if realizes.get(r["id"]) else ""
        l0.append("- %s (%s)%s%s" % (r["id"], _trunc(r.get("display_name"), 40), coll, rz))
    l0.append("")
    l0.append("## Edge-type summary")
    etc = {}
    for e in model.edges:
        etc[e.get("type")] = etc.get(e.get("type"), 0) + 1
    for t in sorted(etc):
        l0.append("- %s: %d" % (t, etc[t]))
    l0.append("")
    l0.append("_%d of %d uncertain, %d stale -- query stale / open L1 cards._" % (uncertain_ct, total_ent, stale_ct))
    files["L0_SYSTEM_MAP.md"] = "\n".join(l0) + "\n"
    # L1 cards split by group
    groups = {"modules": lambda r: _ns_of(r["id"]) == "module",
              "widgets": lambda r: _ns_of(r["id"]) == "widget",
              "infra": lambda r: _ns_of(r["id"]) in ("plane", "arch", "contract", "doc", "store", "ops", "future", "decision", "mandate", "pb", "iteration", "wave")}
    inbound = {}
    for e in model.edges:
        inbound.setdefault(e.get("to"), []).append(e)
    outbound = {}
    for e in model.edges:
        outbound.setdefault(e.get("from"), []).append(e)
    for gname, pred in groups.items():
        lines = [header, fresh, "", "# L1 CARDS -- %s" % gname, ""]
        for r in sorted([x for x in ents.values() if pred(x)], key=lambda r: r["id"]):
            rid = r["id"]
            lines.append("## %s" % rid)
            lines.append("- display_name: %s" % r.get("display_name"))
            if r.get("aliases"):
                lines.append("- aliases: %s" % ", ".join(sorted(r["aliases"])))
            lines.append("- planes: primary=%s secondary=%s" % (r.get("plane_primary", "-"), ",".join(r.get("planes_secondary", []) or []) or "-"))
            lines.append("- status: %s  version: %s" % (r.get("status", "-"), r.get("version", "-")))
            lines.append("- one_line: %s" % r.get("one_line"))
            if r.get("purpose"):
                lines.append("- purpose: %s" % _trunc(r.get("purpose"), 300))
            for fld in ("inputs", "outputs", "state_owned", "audit_surfaces"):
                if r.get(fld):
                    lines.append("- %s: %s" % (fld, _stable(r[fld])))
            if r.get("authority_level"):
                lines.append("- authority_level: %s" % r["authority_level"])
            det = r.get("determinism")
            if det is not None or r.get("parallel_safe") is not None:
                lines.append("- side-effects: determinism=%s parallel_safe=%s requirements=%s" % (det, r.get("parallel_safe"), _stable(r.get("requirements")) if r.get("requirements") else "-"))
            oute = outbound.get(rid, [])
            ine = inbound.get(rid, [])
            if oute:
                lines.append("- edges out: %s" % "; ".join(sorted("%s->%s" % (e["type"], e["to"]) for e in oute)))
            if ine:
                lines.append("- edges in: %s" % "; ".join(sorted("%s<-%s" % (e["type"], e["from"]) for e in ine)))
            if r.get("plane_primary"):
                lines.append("- member-of (derived): %s" % ", ".join(["plane:" + r["plane_primary"]] + ["plane:" + p for p in (r.get("planes_secondary") or [])]))
            for d in r.get("deeper", []) or []:
                lines.append("- deeper[%s]: %s" % (d.get("kind"), d.get("ref")))
            if r.get("confidence"):
                lines.append("- confidence: %s%s" % (r["confidence"], (" -- " + r.get("note", "")) if r.get("note") else ""))
            if rid in stale_set:
                lines.append("- STALE: one or more fields need reaffirm")
            lines.append("")
        files["L1_CARDS_%s.md" % gname] = "\n".join(lines) + "\n"
    # ALIASES
    al = [header, fresh, "", "# ALIASES", ""]
    for r in sorted(ents.values(), key=lambda r: r["id"]):
        rid = r["id"]
        ns = _ns_of(rid)
        if ns == "module":
            num = rid.split(":", 1)[1].split("/", 1)[0]
            al.append("- #%s -> %s" % (num, rid))
        if ns == "arch":
            num = rid.split(":", 1)[1]
            al.append("- pos %s -> %s" % (num, rid))
        for a in r.get("aliases", []) or []:
            al.append("- %s -> %s" % (a, rid))
    files["ALIASES.md"] = "\n".join(al) + "\n"
    return files, pbytes, ladder, stale_ct


def op_render(map_dir, harvest, out, check=False, draft=False):
    model = load_map(map_dir)
    if harvest is None:
        raise Refuse("SCHEMA_INVALID", "render requires --harvest (RT1-F12)")
    if draft:
        if not out or "runtime" not in os.path.abspath(out).replace(os.sep, "/").split("/"):
            raise Refuse("DRAFT_RENDER", "draft render permitted ONLY with --out under runtime/ (RT1-F13)")
        files, pbytes, ladder, stale_ct = _render_views(model, harvest, draft=True)
        for name, text in files.items():
            write_lf(os.path.join(out, name), text)
        raise Refuse("DRAFT_RENDER", "draft render written (not canonical)",
                     result={"out": out, "boot_packet_bytes": pbytes, "ladder": ladder,
                             "files": sorted(files), "draft": True})
    # non-draft: validate first, refuse on ANY error
    vr = validate(model, harvest, is_real=True)
    if vr["findings"]:
        raise Refuse(_rep_code(vr["findings"]), "render refused: map has validation errors",
                     vr["findings"], {"findings": vr["findings"]})
    if harvest.get("dirty"):
        raise Refuse("DIRTY_TREE", "non-draft render refuses on a dirty tree (RT1-F18)")
    skel = sorted([rid for rid, r in model.entities.items() if r.get("skeleton")])
    if skel:
        raise Refuse("SKELETON_UNRESOLVED", "non-draft render refuses while skeletons remain (RT1-F14)",
                     [{"code": "SKELETON_UNRESOLVED", "where": s, "message": "skeleton entity"} for s in skel])
    files, pbytes, ladder, stale_ct = _render_views(model, harvest, draft=False)
    if pbytes > BOOT_PACKET_HARD:
        raise Refuse("PACKET_OVER_BUDGET",
                     "BOOT_PACKET %d B exceeds hard %d B after ladder %s" % (pbytes, BOOT_PACKET_HARD, ladder))
    manifest = []
    for name in sorted(files):
        manifest.append({"name": name, "bytes": len(files[name].encode("utf-8")),
                         "sha256": sha256_norm(files[name])})
    if check:
        drift = []
        for name in sorted(files):
            committed = os.path.join(out, name)
            if not os.path.isfile(committed):
                drift.append({"code": "GENERATED_DRIFT", "where": name, "message": "missing committed file"})
                continue
            cur = read_text(committed)
            if DRAFT_BANNER in cur:
                drift.append({"code": "GENERATED_DRIFT", "where": name, "message": "DRAFT-STALE banner under generated/"})
            if sha256_norm(cur) != sha256_norm(files[name]):
                drift.append({"code": "GENERATED_DRIFT", "where": name, "message": "byte drift vs committed"})
        # also flag committed files not in the fresh render
        for extra in sorted(set(os.listdir(out)) if os.path.isdir(out) else []):
            if extra.endswith(".md") and extra not in files:
                drift.append({"code": "GENERATED_DRIFT", "where": extra, "message": "orphan committed file"})
        if drift:
            raise Refuse("GENERATED_DRIFT", "render --check found drift", drift, {"drift": drift})
        return {"out": out, "checked": True, "files": manifest, "boot_packet_bytes": pbytes,
                "ladder": ladder, "stale_count": stale_ct}
    for name, text in files.items():
        write_lf(os.path.join(out, name), text)
    return {"out": out, "files": manifest, "boot_packet_bytes": pbytes, "ladder": ladder,
            "stale_count": stale_ct, "degraded": bool(ladder)}


# ---- verify / query / reaffirm / fmt / selftest (WO s3.5-3.8) -------------------------------
def op_verify(map_dir, harvest):
    model = load_map(map_dir)
    vr = validate(model, harvest, is_real=True)
    would_refuse = bool(vr["findings"]) or (harvest.get("dirty") if harvest else False) \
        or any(r.get("skeleton") for r in model.entities.values())
    orphans = [f for f in vr["findings"] if f["code"] == "HARVEST_ORPHAN"]
    unbacked = [f for f in vr["findings"] if f["code"] == "ENTITY_UNBACKED"]
    return {"ok": not vr["findings"], "error_count": len(vr["findings"]),
            "findings": vr["findings"], "stale": vr["stale_entities"],
            "coverage": {"orphans": [o["where"] for o in orphans],
                         "unbacked": [u["where"] for u in unbacked]},
            "would_render_refuse": bool(would_refuse)}


def op_query(map_dir, q, harvest=None, paths_file=None):
    model = load_map(map_dir)
    ents = model.entities
    if q == "stale":
        if harvest is None:
            raise Refuse("UNSUPPORTED_QUERY", "query stale requires --harvest")
        vr = validate(model, harvest, is_real=True)
        return {"q": q, "stale": vr["stale_entities"]}
    if q == "changed-since":
        if not paths_file:
            raise Refuse("UNSUPPORTED_QUERY", "changed-since requires --paths-file")
        changed = [ln.strip().replace("\\", "/") for ln in read_text(paths_file).split("\n") if ln.strip()]
        cset = set(changed)
        touched = []
        for rid, r in sorted(ents.items()):
            refs = set()
            for s in r.get("sources", []) or []:
                if isinstance(s, dict) and isinstance(s.get("ref"), str) and _ref_is_path(s["ref"]):
                    refs.add(s["ref"].split("#", 1)[0])
            for d in r.get("deeper", []) or []:
                if isinstance(d, dict) and isinstance(d.get("ref"), str) and _ref_is_path(d["ref"]):
                    refs.add(d["ref"].split("#", 1)[0])
            if refs & cset:
                touched.append(rid)
        return {"q": q, "changed_paths": sorted(cset), "touched_entities": touched}
    if ":" not in q:
        raise Refuse("UNSUPPORTED_QUERY", "query %r not in the closed set" % q)
    verb, arg = q.split(":", 1)
    if verb == "entity":
        if arg not in ents:
            raise Refuse("UNSUPPORTED_QUERY", "no such entity %r" % arg) if False else Refuse("DANGLING_REF", "no such entity %r" % arg)
        return {"q": q, "entity": {k: v for k, v in ents[arg].items() if not k.startswith("_")}}
    if verb == "edges":
        return {"q": q, "edges": sorted(["%s-[%s]->%s" % (e["from"], e["type"], e["to"])
                                         for e in model.edges if e.get("from") == arg])}
    if verb == "redges":
        return {"q": q, "redges": sorted(["%s-[%s]->%s" % (e["from"], e["type"], e["to"])
                                          for e in model.edges if e.get("to") == arg])}
    if verb == "evidence":
        if arg not in ents:
            raise Refuse("DANGLING_REF", "no such entity %r" % arg)
        return {"q": q, "evidence": ents[arg].get("sources", [])}
    if verb == "deeper":
        parts = arg.split(":")
        eid = parts[0] if len(parts) == 1 else ":".join(parts[:-1])
        kind = None
        if len(parts) >= 2:
            eid, kind = ":".join(parts[:-1]), parts[-1]
        rec = ents.get(eid) or ents.get(arg)
        if rec is None:
            raise Refuse("DANGLING_REF", "no such entity for deeper %r" % arg)
        deep = rec.get("deeper", []) or []
        if kind:
            deep = [d for d in deep if d.get("kind") == kind]
        return {"q": q, "deeper": deep}
    if verb == "alias":
        hits = []
        for rid, r in ents.items():
            if arg in (r.get("aliases", []) or []) or arg == rid:
                hits.append(rid)
            num = rid.split(":", 1)[1].split("/", 1)[0] if ":" in rid else ""
            if arg in ("#" + num, "pos " + num):
                hits.append(rid)
        return {"q": q, "resolves_to": sorted(set(hits))}
    raise Refuse("UNSUPPORTED_QUERY", "query verb %r not supported" % verb)


def op_reaffirm(map_dir, entity, fields, by, at_commit, harvest):
    model = load_map(map_dir)
    if entity not in model.entities:
        raise Refuse("DANGLING_REF", "reaffirm: no such entity %r" % entity)
    rec = model.entities[entity]
    flds = [f.strip() for f in fields.split(",") if f.strip()]
    inv = harvest.get("inventory", {}) if harvest else {}
    for f in flds:
        if f in ("load_bearing",) or f not in rec:
            raise Refuse("SCHEMA_INVALID", "reaffirm: field %r is derived or absent on %s" % (f, entity))
    changed = 0
    for s in rec.get("sources", []) or []:
        if not isinstance(s, dict):
            continue
        cover = s.get("fields", []) or []
        if not (set(flds) & set(cover) or "*" in cover):
            continue
        ref = s.get("ref", "")
        if _ref_is_path(ref):
            path = ref.split("#", 1)[0]
            if path in inv:
                s["sha256"] = inv[path]
        s.setdefault("reaffirmed", []).append({"by": by, "at_commit": at_commit})
        changed += 1
    _write_map(model, map_dir)
    return {"reaffirmed": entity, "fields": flds, "sources_restamped": changed}


def op_fmt(paths, check=True):
    nonconforming = []
    for base in paths:
        if not os.path.exists(base):
            continue
        targets = []
        if os.path.isdir(base):
            for root, dirs, files in os.walk(base):
                dirs[:] = sorted(d for d in dirs if d not in INVENTORY_SKIP_DIRS)
                for fn in sorted(files):
                    if fn.endswith(".json"):
                        targets.append(os.path.join(root, fn))
        else:
            targets.append(base)
        for t in sorted(targets):
            raw = read_text(t)
            try:
                obj = json.loads(raw)
            except Exception:
                nonconforming.append(os.path.relpath(t).replace(os.sep, "/"))
                continue
            if dumps_map(obj) != raw:
                nonconforming.append(os.path.relpath(t).replace(os.sep, "/"))
    if nonconforming:
        raise Refuse("FMT_NONCANONICAL", "non-canonical files found",
                     [{"code": "FMT_NONCANONICAL", "where": p, "message": "not canonical form"} for p in nonconforming],
                     {"ok": False, "nonconforming": sorted(nonconforming)})
    return {"ok": True, "nonconforming": []}


def op_selftest():
    lines = []
    # canonical bytes
    assert dumps_map({"b": 1, "a": [3, 1, 2]}) == '{\n "a": [\n  1,\n  2,\n  3\n ],\n "b": 1\n}\n'
    lines.append("SELFTEST_CANON_OK")
    # crlf/lf hash equivalence
    assert sha256_norm(b"x\r\ny") == sha256_norm(b"x\ny")
    lines.append("SELFTEST_CRLF_OK")
    # id grammar
    assert ID_RE.match("module:36/artifact.search") and not ID_RE.match("module:Bad Id")
    lines.append("SELFTEST_IDGRAMMAR_OK")
    # sort stability
    a = sort_arrays({"items": [{"id": "b:2", "ns": "b"}, {"id": "a:1", "ns": "a"}]})
    assert a["items"][0]["id"] == "a:1"
    lines.append("SELFTEST_SORT_OK")
    # error code table closed
    assert len(set(CODES)) == len(CODES)
    lines.append("SELFTEST_CODES_OK")
    return {"ok": True, "checks": lines}


# ---- envelope + main ------------------------------------------------------------------------
def _utcnow():
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f0Z")


def emit_envelope(status, result=None, error=None, warnings=None, diagnostics=None,
                  started=None, invocation_id="cli"):
    env = {
        "schema": "lifeorch.skill.result/0.1", "skill_id": SKILL_ID,
        "skill_version": SKILL_VERSION, "contract_version": CONTRACT_VERSION,
        "invocation_id": invocation_id, "status": status,
        "started_at_utc": started, "finished_at_utc": _utcnow(), "duration_ms": None,
        "inputs_digest": None, "result": result if result is not None else {},
        "confidence": None, "artifacts": [], "model_provenance": [],
        "diagnostics": diagnostics or {}, "warnings": warnings or [], "error": error,
    }
    sys.stdout.write(json.dumps(env) + "\n")
    sys.stdout.flush()


def _load_harvest(path):
    if not path:
        return None
    return json.loads(read_text(path))


def build_argparser():
    p = argparse.ArgumentParser(prog="project_map.py", add_help=True)
    p.add_argument("action", choices=[
        "harvest", "validate", "ingest-claims", "render", "verify", "query",
        "reaffirm", "fmt", "selftest"])
    p.add_argument("--repo")
    p.add_argument("--map", dest="map_dir")
    p.add_argument("--harvest")
    p.add_argument("--out")
    p.add_argument("--claims")
    p.add_argument("--q")
    p.add_argument("--entity")
    p.add_argument("--fields")
    p.add_argument("--by")
    p.add_argument("--at-commit", dest="at_commit")
    p.add_argument("--dirty", default="false")
    p.add_argument("--paths-file", dest="paths_file")
    p.add_argument("--core-dir", dest="core_dir")
    p.add_argument("--override")
    p.add_argument("--check", action="store_true")
    p.add_argument("--draft", action="store_true")
    p.add_argument("--no-harvest", dest="no_harvest", action="store_true")
    p.add_argument("--fmt-paths", nargs="*", dest="fmt_paths")
    return p


def dispatch(a, started):
    if a.action == "harvest":
        dirty = str(a.dirty).lower() in ("1", "true", "yes")
        h = op_harvest(a.repo, a.at_commit, dirty)
        out = a.out or os.path.join(a.repo or ".", "runtime", "harvest.json")
        write_lf(out, dumps_compact(h))
        return {"status": "ok", "result": {"out": out, "counts": h["counts"],
                                            "at_commit": h["at_commit"], "dirty": h["dirty"]}}
    if a.action == "validate":
        if not a.harvest and not a.no_harvest:
            raise Refuse("SCHEMA_INVALID", "validate requires --harvest or --no-harvest (fixture-only)")
        model = load_map(a.map_dir)
        harvest = _load_harvest(a.harvest) if not a.no_harvest else None
        vr = validate(model, harvest, is_real=not a.no_harvest)
        if vr["findings"]:
            raise Refuse(_rep_code(vr["findings"]), "validation failed",
                         vr["findings"], {"ok": False, "error_count": len(vr["findings"]),
                                          "findings": vr["findings"], "warnings": vr["warnings"]})
        return {"status": "ok", "result": {"ok": True, "error_count": 0, "findings": [],
                                           "warnings": vr["warnings"], "stale": vr["stale_entities"]},
                "warnings": vr["warnings"]}
    if a.action == "ingest-claims":
        harvest = _load_harvest(a.harvest)
        res = op_ingest_claims(a.map_dir, a.claims, harvest, a.override)
        return {"status": "ok", "result": res}
    if a.action == "render":
        harvest = _load_harvest(a.harvest)
        res = op_render(a.map_dir, harvest, a.out, check=a.check, draft=a.draft)
        return {"status": "ok", "result": res}
    if a.action == "verify":
        harvest = _load_harvest(a.harvest)
        return {"status": "ok", "result": op_verify(a.map_dir, harvest)}
    if a.action == "query":
        harvest = _load_harvest(a.harvest) if a.harvest else None
        return {"status": "ok", "result": op_query(a.map_dir, a.q, harvest, a.paths_file)}
    if a.action == "reaffirm":
        harvest = _load_harvest(a.harvest)
        return {"status": "ok", "result": op_reaffirm(a.map_dir, a.entity, a.fields, a.by, a.at_commit, harvest)}
    if a.action == "fmt":
        paths = a.fmt_paths or [p for p in [a.map_dir, a.claims] if p]
        return {"status": "ok", "result": op_fmt(paths, check=a.check)}
    if a.action == "selftest":
        r = op_selftest()
        return {"status": "ok", "result": r, "diagnostics": {"selftest": r["checks"]}}
    raise Refuse("SCHEMA_INVALID", "unknown action")


def main(argv=None):
    started = _utcnow()
    a = build_argparser().parse_args(argv)
    try:
        out = dispatch(a, started)
    except Refuse as r:
        emit_envelope("error", result=r.result if r.result is not None else {"findings": r.findings},
                      error={"code": r.code, "message": r.message, "retryable": False},
                      started=started)
        return 0
    except Exception as e:  # crash -> nonzero, no valid envelope (SKILL_CONTRACT s3)
        sys.stderr.write("CRASH %s: %s\n" % (type(e).__name__, e))
        import traceback
        traceback.print_exc()
        return 2
    emit_envelope(out.get("status", "ok"), result=out.get("result"),
                  warnings=out.get("warnings"), diagnostics=out.get("diagnostics"), started=started)
    return 0


if __name__ == "__main__":
    sys.exit(main())
