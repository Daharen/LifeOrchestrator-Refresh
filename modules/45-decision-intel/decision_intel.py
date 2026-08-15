#!/usr/bin/env python
# decision_intel.py -- deterministic decision-record producer for decision.intel
#   (Life Orchestrator, Module 45, i56 PB-6 build; the FROZEN contract
#   core-docs/research/2026-08-14-pb6-decision-record-schema.md, D-0077 governing doc).
#
# Parses the append-only DECISION_LOG.md (+ DECISION_LOG_INDEX.md routing rows) and emits TYPED
# record_kind="decision" record-envelope artifacts conforming to MEMORY_CONTRACT s1, so the catalog
# (#36 artifact.search) can ingest them as FIRST-CLASS records. CPU-only, stdlib-only Python, no model,
# no network, fully deterministic. This module EMITS + VALIDATES artifacts only -- it does NOT write the
# catalog DB (#36 owns storage; the orchestrator feeds ingest_records.json into #36 `ingest_records` at
# fold, mirroring the #38->#36 D-0077 pattern verbatim).
#
# Contract with the PowerShell wrapper (Invoke-DecisionIntel.ps1):
#   argv[1] = path to a JSON args file:
#     { op, decision_log_path, decision_log_index_path, namespace, ingested_through,
#       output_dir, meta_path, records_path (validate) }
#   The worker does all (deterministic) work, writes artifact files into output_dir, and writes
#   meta_path with a JSON result. Only meta_path is authoritative; stdout/stderr are diagnostics.
#   Exit 0 on success, non-zero on failure (meta_path is written in both cases when possible).
#
# DETERMINISM CONTRACT (mirrors #38 repo_intel.py SCHEMA_NOTES s1, per the PB-6 frozen contract s2):
#   - Canonical artifacts (records.jsonl, records.json, ingest_records.json, index_manifest.json,
#     coverage.json) contain NO absolute paths, NO timestamps, NO random/wall-clock ids. Identical
#     DECISION_LOG.md + DECISION_LOG_INDEX.md byte CONTENT (+ the same `ingested_through` input) =>
#     byte-identical canonical artifacts across runs AND machines.
#   - All ids are content+path derived. `ingested_through` is supplied by the CALLER (the orchestrator /
#     harness) as an input param -- this worker NEVER shells out to git (mirrors #38's no-git rule).
#   - Paths are repo-relative + forward-slash. Spans are BYTE offsets over raw file bytes (EOL-faithful:
#     core-docs are CRLF).
import sys, os, json, time, hashlib, re, traceback

WORKER_VERSION = "0.1.0"
RECORD_SCHEMA = "lifeorch.decision_intel.record/0.1"
INGEST_SCHEMA = "lifeorch.decision_intel.ingest_records/0.1"
RECORD_KIND = "decision"
NAMESPACE_DEFAULT = "decisions"

FP = {
    "log_entry": "decision.intel.log-entry/0.1;heading-scan;bullet-fields",
    "index_row": "decision.intel.index-row/0.1;pipe-table",
    "markers": "decision.intel.markers/0.1;regex-priority-v1",
}

STATUS_CURRENT = "current"
STATUS_SUPERSEDED = "superseded"
STATUS_FOLDED = "folded"
STATUS_CLOSED = "closed"
AUTHORITY_LEVEL = "canonical_source"   # the DECISION_LOG is the canonical source of truth for a decision
SENSITIVITY = "repo_internal"


class DecisionIntelError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


# ------------------------------------------------------------------ helpers
def _h(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def canon(obj):
    """Canonical JSON: sorted keys, ASCII, no spaces. Deterministic across machines."""
    return json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",", ":"))


def slug(s):
    s = (s or "").strip().lower()
    return re.sub(r"[^a-z0-9._-]+", "-", s).strip("-") or "decisions"


def token_count(text):
    if not text:
        return 0
    return len(text.split())


def line_byte_starts(raw):
    """Byte offset of the start of each 1-based line. starts[i] = byte offset of line i (1-based).
    Mirrors #38 repo_intel.py line_byte_starts (byte-exact, EOL-faithful over CRLF)."""
    starts = [0, 0]
    for i, b in enumerate(raw):
        if b == 0x0A:  # '\n'
            starts.append(i + 1)
    return starts


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


# ------------------------------------------------------------------ DECISION_LOG.md entry parsing
HEADING_RE = re.compile(r"^(#{2,3})\s+(D-(\d{4}))\b(.*)$")

LEAD_DASH_RE = re.compile(r"^\s*[—–\-]{1,2}\s*")
LEAD_PAREN_DATE_DASH_RE = re.compile(r"^\(\d{4}-\d{2}-\d{2}\)\s*[—–\-]{1,2}\s*")
LEAD_BARE_DATE_DASH_RE = re.compile(r"^\d{4}-\d{2}-\d{2}\s*[—–\-]{1,2}\s*")

DATE_RE = re.compile(r"\*\*[Dd]ate:\*\*\s*(\d{4}-\d{2}-\d{2})")
HEAD_PAREN_DATE_RE = re.compile(r"\((\d{4}-\d{2}-\d{2})\)")
HEAD_DASH_DATE_RE = re.compile(r"[—–\-]{1,2}\s*(\d{4}-\d{2}-\d{2})\s*[—–\-]{1,2}")

STATE_RE = re.compile(r"\*\*[Ss]tate:\*\*\s*([A-Za-z][A-Za-z \-]*)")

ITER_WORD_RE = re.compile(r"\biteration\s+(\d{1,3})\b", re.IGNORECASE)
ITER_TOKEN_RE = re.compile(r"(?<![A-Za-z0-9])i(\d{1,3})(?!\d)")

MODULE_HASH_RE = re.compile(r"#(\d{1,2}(?:\.\d)?)\b")
MODULE_PATH_RE = re.compile(r"modules/(\d{1,2}(?:\.\d)?)-")
MODULE_COLON_RE = re.compile(r"\bmodule:(\d{1,2}(?:\.\d)?)\b")
MODULE_WORD_RE = re.compile(r"\bModule\s+(\d{1,2}(?:\.\d)?)\b")

# binding_scope markers (frozen contract s3, deterministic priority: standing_prohibition checked
# FIRST, then invariant, else ordinary -- the order named in the field-derivation table).
STANDING_PROHIBITION_RE = re.compile(r"\bFROZEN\b|\bprohibit(?:ed|ion)\b", re.IGNORECASE)
INVARIANT_RE = re.compile(r"\bnever\b|\balways\b|\binviolable\b|\bHARD\b")

# enforced_by allowlist (deterministic scan order; first match wins). Each entry: (gate_id, pattern).
ENFORCED_BY_PATTERNS = [
    ("doc-commit-gate", re.compile(r"doc-commit-gate", re.IGNORECASE)),
    ("dev.ship-ast", re.compile(r"dev\.ship\b.*\bAST\b|\bAST\b.*dev\.ship", re.IGNORECASE | re.DOTALL)),
    ("action-authz-p0-1", re.compile(r"\bP0-1\b.*action[.\-]?authz|action[.\-]?authz.*\bP0-1\b", re.IGNORECASE)),
    ("res.lease-wrapper", re.compile(r"res\.lease\b.*\bwrapper\b|lease wrapper", re.IGNORECASE)),
    ("gen-retrieval-monitor", re.compile(r"gen-retrieval-monitor\.py", re.IGNORECASE)),
    ("gen-doc-health-monitor", re.compile(r"gen-doc-health\.py", re.IGNORECASE)),
    ("close-refold", re.compile(r"close-refold\.ps1", re.IGNORECASE)),
]

# type markers (deterministic priority scan over title then body)
TYPE_PATTERNS = [
    ("gate", re.compile(r"\bGATE\b|\bNO-GO\b|\bGO-GO\b|\bGO\)\b|gate = ", re.IGNORECASE)),
    ("freeze", re.compile(r"\bFROZEN\b|\bfreeze\b", re.IGNORECASE)),
    ("build", re.compile(r"\bSHIPPED\b|\bshipped\b|\bbuilt\b|\bBUILD\b", re.IGNORECASE)),
    ("design", re.compile(r"\bDESIGN\b|\bdesigned\b|design-first", re.IGNORECASE)),
    ("direction", re.compile(r"directive|User-directed|\bpivot\b", re.IGNORECASE)),
]

# authority markers (deterministic priority scan over title then body)
AUTHORITY_PATTERNS = [
    ("nicholas", re.compile(
        r"Nicholas('s)?\s+(directive|ratifie[sd]|declares?|decides?|priority|rules?|deferred)"
        r"|ratified by Nicholas|Nicholas:|User-directed",
        re.IGNORECASE)),
    ("redteam", re.compile(r"red-?team|adversar(?:y|ies)", re.IGNORECASE)),
    ("gate", re.compile(r"\bGATE\b|\bNO-GO\b", re.IGNORECASE)),
]

# full-supersession markers: THIS entry declares it totally replaces prior D-numbers. The cue window
# (bounded lookahead after the keyword, stopped at a sentence boundary) is scanned for EVERY D-number
# token in it -- handles a compact shorthand run ("D-0140/42/45"), a fully-repeated list
# ("D-0140/D-0142/D-0145"), and a comma/and-joined list ("D-0140, D-0142 and D-0145") uniformly, since
# each distinct "D-####" occurrence (plus any compact "/NN" continuation immediately after ONE of them)
# is found independently by the same token regex (see _extract_dnums_in_window).
SUPERSEDES_CUE_RE = re.compile(r"\bsupersedes?\b(.{0,80}?)(?=[.,;\n]|$)", re.IGNORECASE | re.DOTALL)
REPLACES_CUE_RE = re.compile(r"\breplaces?\b(.{0,80}?)(?=[.,;\n]|$)", re.IGNORECASE | re.DOTALL)
DNUM_TOKEN_RE = re.compile(r"D-(\d{4})((?:/\d{2}(?!\d))*)")


def _extract_dnums_in_window(window):
    out = []
    for m in DNUM_TOKEN_RE.finditer(window):
        first = m.group(1)
        prefix = first[:2]
        out.append("D-" + first)
        for suf in re.findall(r"/(\d{2})(?!\d)", m.group(2)):
            out.append("D-" + prefix + suf)
    return out

# partial-supersession cue markers (softer revision language + an explicit target D-number nearby)
PARTIAL_CUE_RE = re.compile(
    r"\b(revises?|refines?|amend(?:s|ed)?|RE-FROZEN|reconciles?|folds? the .*? into)\b.{0,80}?(D-\d{4})",
    re.IGNORECASE | re.DOTALL,
)

RESEARCH_DIGEST_RE = re.compile(r"research/[\w.\-/]+\.md")


def _strip_title(rest):
    t = rest.strip()
    t = LEAD_DASH_RE.sub("", t)
    t = LEAD_PAREN_DATE_DASH_RE.sub("", t)
    t = LEAD_BARE_DATE_DASH_RE.sub("", t)
    t = t.strip()
    return t


def parse_log_entries(raw):
    """Deterministic line-scan for `^(##|###) D-####...` headings (byte-exact spans, EOL-faithful).
    Returns list of dicts: {decision_id, heading_level, title, body, span{start,end}}."""
    text = raw.decode("utf-8")
    lines = text.split("\n")
    starts = line_byte_starts(raw)
    heads = []  # (line_idx 0-based, decision_id, level, title)
    for i, ln in enumerate(lines):
        m = HEADING_RE.match(ln)
        if m:
            did = m.group(2)
            level = m.group(1)
            title = _strip_title(m.group(4))
            heads.append((i, did, level, title))
    entries = []
    for idx, (li, did, level, title) in enumerate(heads):
        start_byte = starts[li + 1] if (li + 1) < len(starts) else len(raw)
        end_byte = starts[heads[idx + 1][0] + 1] if (idx + 1) < len(heads) else len(raw)
        body = raw[start_byte:end_byte].decode("utf-8")
        raw_heading_rest = lines[li][len(HEADING_RE.match(lines[li]).group(1)):].strip()
        entries.append({
            "decision_id": did, "heading_level": level, "title": title,
            "raw_heading_rest": raw_heading_rest,
            "body": body, "span": {"start": start_byte, "end": end_byte},
        })
    return entries


# ------------------------------------------------------------------ DECISION_LOG_INDEX.md row parsing
INDEX_ROW_RE = re.compile(r"^\|\s*(D-\d{4})\s*\|\s*([^|]*)\|\s*([^|]*)\|\s*(.*?)\|\s*$")
IDX_SUPERSEDED_BY_RE = re.compile(r"\[(?:\w+\s+)?superseded by (D-\d{4})\]", re.IGNORECASE)
IDX_FOLDED_BY_RE = re.compile(r"\[(?:\w+\s+)?folded by (D-\d{4})\]", re.IGNORECASE)
IDX_RETIRED_BY_RE = re.compile(r"\[(?:\w+\s+)?retired by (D-\d{4})\]", re.IGNORECASE)


def parse_index_rows(raw):
    text = raw.decode("utf-8")
    rows = []
    for ln in text.split("\n"):
        m = INDEX_ROW_RE.match(ln.rstrip("\r"))
        if not m:
            continue
        did = m.group(1)
        date = m.group(2).strip()
        state_raw = m.group(3).strip()
        decision_cell = m.group(4).strip()
        superseded_by = None
        folded_by = None
        sm = IDX_SUPERSEDED_BY_RE.search(decision_cell)
        if sm:
            superseded_by = sm.group(1)
        rm = IDX_RETIRED_BY_RE.search(decision_cell)
        if rm and not superseded_by:
            superseded_by = rm.group(1)   # "retired by" is treated as full supersession (documented)
        fm = IDX_FOLDED_BY_RE.search(decision_cell)
        if fm:
            folded_by = fm.group(1)
        rows.append({
            "decision_id": did, "date": date, "state_raw": state_raw,
            "decision_cell": decision_cell, "superseded_by": superseded_by, "folded_by": folded_by,
        })
    return rows


# ------------------------------------------------------------------ field derivation (the marker rules)
def derive_date(raw_heading_rest, body):
    m = DATE_RE.search(body)
    if m:
        return m.group(1), "body_date_field"
    m = HEAD_PAREN_DATE_RE.search(raw_heading_rest)
    if m:
        return m.group(1), "heading_paren"
    m = HEAD_DASH_DATE_RE.search(raw_heading_rest)
    if m:
        return m.group(1), "heading_dash"
    return None, None


def derive_state_body(body):
    m = STATE_RE.search(body)
    if m:
        return m.group(1).strip().lower()
    return None


def derive_iteration(title, body):
    m = ITER_WORD_RE.search(title)
    if m:
        return int(m.group(1)), "word_title"
    m = ITER_WORD_RE.search(body)
    if m:
        return int(m.group(1)), "word_body"
    m = ITER_TOKEN_RE.search(title)
    if m:
        return int(m.group(1)), "token_title"
    m = ITER_TOKEN_RE.search(body)
    if m:
        return int(m.group(1)), "token_body"
    return None, None


MODULE_PLANE_MAP = {
    # Deterministic static interpretation (documented SCHEMA_NOTES s3 as an explicit approximation --
    # the real #44 project.map plane assignment is a NAMED FOLLOW-ON; this table is derived from the
    # CURRENT_STATE.md "Completed modules" roster categories at i56 scoping time).
    "0": "infra", "0.1": "infra", "1": "infra", "29": "infra", "30": "infra", "31": "infra",
    "2": "observation", "3": "observation", "4": "observation", "5": "observation", "6": "observation",
    "7": "model_core", "8": "model_core", "9": "model_core", "19": "model_core", "20": "model_core",
    "21": "model_core", "27": "model_core", "28": "model_core",
    "10": "audio", "11": "audio", "12": "audio", "13": "audio",
    "14": "perception", "15": "perception", "16": "perception", "17": "perception", "18": "perception",
    "22": "generators", "23": "generators", "24": "generators", "25": "generators",
    "32": "video", "33": "video", "34": "video",
    "35": "memory", "36": "memory", "37": "memory", "38": "memory", "39": "memory", "40": "memory",
    "41": "memory", "42": "memory", "43": "memory",
    "44": "pcb",
    "45": "memory",  # decision.intel itself is part of the memory/knowledge-surface program (PB-6/PB-7)
}


def derive_modules_planes(title, body):
    hay = title + "\n" + body
    mods = set()
    for pat in (MODULE_HASH_RE, MODULE_PATH_RE, MODULE_COLON_RE, MODULE_WORD_RE):
        for m in pat.finditer(hay):
            mods.add(m.group(1))
    modules = sorted(mods, key=lambda s: (len(s), s))
    planes = sorted(set(MODULE_PLANE_MAP[m] for m in modules if m in MODULE_PLANE_MAP))
    return modules, planes


def derive_type(title, body):
    for name, pat in TYPE_PATTERNS:
        if pat.search(title):
            return name
    for name, pat in TYPE_PATTERNS:
        if pat.search(body):
            return name
    return "process"


def derive_authority(title, body):
    for name, pat in AUTHORITY_PATTERNS:
        if pat.search(title):
            return name
    for name, pat in AUTHORITY_PATTERNS:
        if pat.search(body):
            return name
    return "orchestrator"


def derive_binding_scope(title, body):
    hay = title + "\n" + body
    if STANDING_PROHIBITION_RE.search(hay):
        return "standing_prohibition"
    if INVARIANT_RE.search(hay):
        return "invariant"
    return "ordinary"


def derive_enforced_by(title, body):
    hay = title + "\n" + body
    for gate_id, pat in ENFORCED_BY_PATTERNS:
        if pat.search(hay):
            return gate_id
    return "none"


def derive_edges_for_entry(did, title, body, valid_ids):
    """Full supersession/replacement declared BY this entry (THIS -> older D-numbers), plus a softer
    partial-revision cue. Only emits an edge whose target is a KNOWN valid decision id (else the
    unresolved token is surfaced honestly in `ambiguous.unresolved_targets`, never silently dropped
    and never invented)."""
    hay = title + "\n" + body
    supersedes_targets = []
    unresolved = []
    for cue_re in (SUPERSEDES_CUE_RE, REPLACES_CUE_RE):
        for cm in cue_re.finditer(hay):
            for tok in _extract_dnums_in_window(cm.group(1)):
                (supersedes_targets if tok in valid_ids and tok != did else unresolved).append(tok)
    supersedes_targets = sorted(set(supersedes_targets))

    partial_targets = []
    if not supersedes_targets:
        for m in PARTIAL_CUE_RE.finditer(hay):
            tok = m.group(2)
            if tok in valid_ids and tok != did:
                partial_targets.append(tok)
    partial_targets = sorted(set(partial_targets) - set(supersedes_targets))

    derives_from_research = sorted(set(RESEARCH_DIGEST_RE.findall(hay)))

    return {
        "supersedes": supersedes_targets,
        "partially_supersedes": partial_targets,
        "derives_from_research": derives_from_research,
        "unresolved_targets": sorted(set(unresolved)),
    }


# ------------------------------------------------------------------ record construction
def build_record(namespace, ingest_run_id, ingested_through, entry, index_row, valid_ids,
                  supersedes_by_index, folded_by_index):
    did = entry["decision_id"]
    title = entry["title"]
    body = entry["body"]
    span = entry["span"]

    date, date_src = derive_date(entry.get("raw_heading_rest", title), body)
    state_body = derive_state_body(body)
    iteration, iter_src = derive_iteration(title, body)
    modules, planes = derive_modules_planes(title, body)
    dtype = derive_type(title, body)
    authority = derive_authority(title, body)
    binding_scope = derive_binding_scope(title, body)
    enforced_by = derive_enforced_by(title, body)
    edges_info = derive_edges_for_entry(did, title, body, valid_ids)

    ambiguous = []
    idx_state = (index_row or {}).get("state_raw", "") or ""
    idx_state_l = idx_state.lower()
    if index_row is None:
        ambiguous.append("no_index_row")

    # full supersession/fold edges: union of (a) the INDEX bracket-marker on THIS row (DOC_PROTOCOL s4
    # rule 4 -- the predecessor's row carries `[superseded by D-####]`/`[folded by D-####]`) and (b) a
    # later/other entry's own explicit "supersedes/replaces D-<this>" declaration in DECISION_LOG.md
    # (captured via supersedes_by_index, precomputed globally over every entry body).
    superseded_by = []
    if index_row and index_row.get("superseded_by"):
        superseded_by.append(index_row["superseded_by"])
    folded_into = []
    if index_row and index_row.get("folded_by"):
        folded_into.append(index_row["folded_by"])
    superseded_by.extend(supersedes_by_index.get(did, []))
    superseded_by = sorted(set(superseded_by))
    folded_into = sorted(set(folded_into) | set(folded_by_index.get(did, [])))

    # status (PB-6 frozen contract s8 rule 4): demotion to a non-current envelope status happens ONLY
    # on a FULL supersession/fold/close edge -- so status is DRIVEN BY THE EDGE, not by whether a human
    # separately updated the index row's state cell. A `[superseded by ...]`/`[folded by ...]` bracket
    # marker or an explicit body "supersedes D-####" declaration is exactly that full-replacement
    # marker (frozen contract s3 edge rule), so its presence alone demotes this record.
    if superseded_by:
        status = STATUS_SUPERSEDED
    elif folded_into:
        status = STATUS_FOLDED
    elif idx_state_l.startswith("superseded"):
        status = STATUS_SUPERSEDED     # index row says so but no target bracket/body-declaration resolved
        ambiguous_extra = "superseded_index_state_without_resolved_target"
    elif idx_state_l.startswith("folded"):
        status = STATUS_FOLDED
        ambiguous_extra = "folded_index_state_without_resolved_target"
    elif idx_state_l.startswith("closed"):
        status = STATUS_CLOSED
        ambiguous_extra = None
    else:
        status = STATUS_CURRENT
        ambiguous_extra = None
    if status in (STATUS_SUPERSEDED, STATUS_FOLDED) and not superseded_by and not folded_into:
        ambiguous.append(ambiguous_extra)
    if (superseded_by or folded_into) and not (idx_state_l.startswith("superseded") or idx_state_l.startswith("folded")):
        # the edge exists but the index row's state cell was never hand-annotated to match (a real gap
        # in this corpus -- e.g. D-0140/D-0142/D-0145 are only named in D-0146's own prose, per the
        # DOC_PROTOCOL s4 convention that ANNOTATES the predecessor row, which did not happen here).
        # Honest flag; the edge (not the stale index cell) still governs `status` per the rule above.
        ambiguous.append("supersession_edge_without_index_state_annotation")

    if date is None:
        ambiguous.append("date_unresolved")
    if not modules:
        ambiguous.append("no_affected_modules_found")

    payload = {
        "decision_id": did,
        "title": title,
        "date": date,
        "iteration": iteration,
        "affected_modules": modules,
        "planes": planes,
        "type": dtype,
        "authority": authority,
        "binding_scope": binding_scope,
        "enforced_by": enforced_by,
        "ingested_through": ingested_through,
        "lifecycle": status,
        "synopsis": None,
        "index_state_raw": idx_state or None,
        "log_state_raw": state_body,
        "text": did + " " + title,
    }
    content = canon(payload)
    content_hash = _h(content)
    record_id = "dec_" + did[2:]
    record_version_id = "rv_" + _h(record_id + "\0" + content_hash)[:24]

    parent_edges = []
    child_edges = []
    for tgt in superseded_by:
        tgt_rid = "dec_" + tgt[2:]
        child_edges.append({"edge_type": "superseded_by", "external": False, "target_record_id": tgt_rid})
    for tgt in edges_info["supersedes"]:
        tgt_rid = "dec_" + tgt[2:]
        child_edges.append({"edge_type": "supersedes", "external": False, "target_record_id": tgt_rid})
    for tgt in folded_into:
        tgt_rid = "dec_" + tgt[2:]
        child_edges.append({"edge_type": "folded_into", "external": False, "target_record_id": tgt_rid})
    for tgt in edges_info["partially_supersedes"]:
        tgt_rid = "dec_" + tgt[2:]
        child_edges.append({"edge_type": "partially_supersedes", "external": False, "target_record_id": tgt_rid})
    for ref in edges_info["derives_from_research"]:
        child_edges.append({"edge_type": "derives_from", "external": True, "external_ref": ref, "target_record_id": None})

    # D-0077 seam fix (i56): the ENVELOPE status must conform to #36 artifact.search STATUS_ENUM
    # {current, superseded, deleted, *_stale, unverified} -- it has NO `folded`/`closed`. Map the
    # edge-driven lifecycle onto that enum (folded/closed -> superseded); the precise lifecycle is
    # preserved LOSSLESSLY in payload.lifecycle + the folded_into/superseded_by edges, and the #40 verb
    # demotes on the full-demotion EDGE, not the raw status string.
    envelope_status = status if status in (STATUS_CURRENT, STATUS_SUPERSEDED) else STATUS_SUPERSEDED

    rec = {
        "schema": RECORD_SCHEMA,
        "record_id": record_id,
        "record_version_id": record_version_id,
        "record_kind": RECORD_KIND,
        "namespace": namespace,
        "content_hash": content_hash,
        "status": envelope_status,
        "authority_level": AUTHORITY_LEVEL,
        "sensitivity_class": SENSITIVITY,
        "valid_from": None,
        "valid_to": None,
        "created_by_ingest_run": ingest_run_id,
        "source_version_id": None,   # set by caller (keyed on the whole-file ingested_through)
        "source_path": "core-docs/DECISION_LOG.md",
        "source_span": dict(span),
        "derivation_refs": [],
        "parser_fingerprint": FP["log_entry"],
        "chunker_fingerprint": None,
        "extractor_fingerprint": FP["markers"],
        "schema_version": RECORD_SCHEMA,
        "token_count": token_count(payload["text"]),
        "embedding_space_id": None,
        "parent_edges": parent_edges,
        "child_edges": child_edges,
        "payload": payload,
    }
    return rec, ambiguous, edges_info["unresolved_targets"]


def _build_index_ingest_edges(index_rows):
    """Precompute, from index-row bracket markers ONLY, the reverse map: predecessor_id -> [successor_id]."""
    superseded_by_map = {}
    folded_by_map = {}
    for row in index_rows:
        if row.get("superseded_by"):
            superseded_by_map.setdefault(row["decision_id"], []).append(row["superseded_by"])
        if row.get("folded_by"):
            folded_by_map.setdefault(row["decision_id"], []).append(row["folded_by"])
    return superseded_by_map, folded_by_map


def _build_body_declared_supersession(entries, valid_ids):
    """Scan EVERY entry's own body/title for an explicit 'supersedes/replaces D-####[/##]*' declaration
    and invert it into predecessor_id -> [this_id] (a later entry declaring it supersedes an older one)."""
    inv = {}
    for e in entries:
        did = e["decision_id"]
        hay = e["title"] + "\n" + e["body"]
        targets = []
        for cue_re in (SUPERSEDES_CUE_RE, REPLACES_CUE_RE):
            for cm in cue_re.finditer(hay):
                targets.extend(_extract_dnums_in_window(cm.group(1)))
        for tgt in targets:
            if tgt in valid_ids and tgt != did:
                inv.setdefault(tgt, []).append(did)
    return inv


# ------------------------------------------------------------------ index op
def do_index(args):
    op = "index"
    log_path = args.get("decision_log_path")
    idx_path = args.get("decision_log_index_path")
    if not log_path or not os.path.isfile(log_path):
        raise DecisionIntelError("log_not_found", "decision_log_path not found: %r" % (log_path,))
    if not idx_path or not os.path.isfile(idx_path):
        raise DecisionIntelError("index_not_found", "decision_log_index_path not found: %r" % (idx_path,))
    ingested_through = args.get("ingested_through")
    if not ingested_through or not re.match(r"^[0-9a-f]{7,40}$", str(ingested_through)):
        raise DecisionIntelError("missing_ingested_through",
                                  "ingested_through (the DECISION_LOG.md HEAD sha for this run) is "
                                  "REQUIRED and must be supplied by the caller -- this worker never "
                                  "shells out to git (mirrors #38's no-git rule).")
    namespace = slug(args.get("namespace") or NAMESPACE_DEFAULT)
    outdir = args.get("output_dir")

    raw_log = read_bytes(log_path)
    raw_idx = read_bytes(idx_path)

    entries = parse_log_entries(raw_log)
    index_rows = parse_index_rows(raw_idx)
    index_by_id = {r["decision_id"]: r for r in index_rows}
    entry_ids = [e["decision_id"] for e in entries]
    valid_ids = set(entry_ids)

    superseded_by_index, folded_by_index = _build_index_ingest_edges(index_rows)
    body_declared = _build_body_declared_supersession(entries, valid_ids)
    # merge body-declared supersession into the same reverse map used for superseded_by
    for pred, succs in body_declared.items():
        superseded_by_index.setdefault(pred, [])
        for s in succs:
            if s not in superseded_by_index[pred]:
                superseded_by_index[pred].append(s)

    doc_id = "doc_" + _h(namespace + "\0" + "core-docs/DECISION_LOG.md")[:24]
    source_version_id = "ver_" + _h(doc_id + "\0" + str(ingested_through))[:24]

    corpus_key = namespace + "\0" + "\n".join(
        e["decision_id"] + "\t" + _h(e["body"]) for e in entries
    )
    ingest_run_id = "ingest_" + _h(corpus_key)[:24]

    records = []
    ambiguous_report = []
    unresolved_all = []
    for e in entries:
        row = index_by_id.get(e["decision_id"])
        rec, ambiguous, unresolved = build_record(
            namespace, ingest_run_id, ingested_through, e, row, valid_ids,
            superseded_by_index, folded_by_index)
        rec["source_version_id"] = source_version_id
        records.append(rec)
        if ambiguous:
            ambiguous_report.append({"decision_id": e["decision_id"], "flags": ambiguous})
        if unresolved:
            unresolved_all.append({"decision_id": e["decision_id"], "unresolved_targets": unresolved})

    # deterministic global order: by source_path (constant here), span.start, record_id
    records.sort(key=lambda r: (r["source_span"]["start"], r["record_id"]))

    validation = validate_records(records)

    # ---- coverage: every index row has a record; every record maps to a canonical span ----
    index_ids = set(index_by_id.keys())
    missing_records_for_index_rows = sorted(index_ids - valid_ids)
    extra_records_without_index_row = sorted(valid_ids - index_ids)
    span_ok = all(
        0 <= r["source_span"]["start"] < r["source_span"]["end"] <= len(raw_log)
        for r in records
    )
    coverage = {
        "schema": "lifeorch.decision_intel.coverage/0.1",
        "index_row_count": len(index_rows),
        "log_entry_count": len(entries),
        "missing_records_for_index_rows": missing_records_for_index_rows,
        "extra_records_without_index_row": extra_records_without_index_row,
        "span_resolution_ok": span_ok,
        "ok": (not missing_records_for_index_rows and not extra_records_without_index_row and span_ok),
    }

    records_digest = _records_digest(records)
    counts_by_status = {}
    for r in records:
        counts_by_status[r["status"]] = counts_by_status.get(r["status"], 0) + 1
    counts_by_binding_scope = {}
    for r in records:
        bs = r["payload"]["binding_scope"]
        counts_by_binding_scope[bs] = counts_by_binding_scope.get(bs, 0) + 1

    manifest = {
        "schema": "lifeorch.decision_intel.index_manifest/0.1",
        "namespace": namespace,
        "ingested_through": ingested_through,
        "created_by_ingest_run": ingest_run_id,
        "total_records": len(records),
        "record_kind": RECORD_KIND,
        "counts_by_status": counts_by_status,
        "counts_by_binding_scope": counts_by_binding_scope,
        "records_digest": records_digest,
        "validation": {"ok": validation["ok"], "checked": validation["checked"],
                       "error_count": len(validation["errors"]), "errors": validation["errors"][:50]},
        "edge_summary": validation["edge_summary"],
        "coverage": coverage,
        "ambiguous_count": len(ambiguous_report),
        "ambiguous": ambiguous_report,
        "unresolved_supersession_targets": unresolved_all,
        "fingerprints": FP,
        "worker_version": WORKER_VERSION,
    }

    ingest_records_payload = _build_ingest_records_payload(namespace, ingest_run_id, records)

    outputs = []
    if outdir:
        outputs = _write_artifacts(outdir, records, manifest, ingest_records_payload, coverage)

    return {
        "op": op, "namespace": namespace,
        "total_records": len(records),
        "record_kind": RECORD_KIND,
        "counts_by_status": counts_by_status,
        "counts_by_binding_scope": counts_by_binding_scope,
        "records_digest": records_digest,
        "validation": manifest["validation"],
        "edge_summary": validation["edge_summary"],
        "coverage": coverage,
        "ambiguous_count": len(ambiguous_report),
        "ambiguous": ambiguous_report,
        "unresolved_supersession_targets": unresolved_all,
        "ingest_run_id": ingest_run_id,
        "outputs": outputs,
    }


def _build_ingest_records_payload(namespace, ingest_run_id, records):
    """The #36 `ingest_records` op INPUT shape (artifact.search SCHEMA_NOTES s4), conformed EXACTLY --
    not merely a re-wrap of the full s1 envelope (the archetype #38 uses; here the exact drop-in shape
    is known in advance from the frozen #36 contract, so we conform to it directly)."""
    out_records = []
    for r in records:
        p = r["payload"]
        edges = []
        for e in r["child_edges"]:
            if e["external"]:
                edges.append({"edge_kind": e["edge_type"], "dst_ref": e["external_ref"], "dst_kind": "external"})
            else:
                edges.append({"edge_kind": e["edge_type"], "dst_ref": e["target_record_id"], "dst_kind": "record"})
        out_records.append({
            "record_id": r["record_id"],
            "record_version_id": r["record_version_id"],
            "record_kind": r["record_kind"],
            "text": p["text"],
            "namespace": r["namespace"],
            "status": r["status"],
            "authority_level": r["authority_level"],
            "sensitivity_class": r["sensitivity_class"],
            "source_version_id": r["source_version_id"],
            "source_path": r["source_path"],
            "source_span": r["source_span"],
            "derivation_refs": [],
            "parser_fingerprint": r["parser_fingerprint"],
            "extractor_fingerprint": r["extractor_fingerprint"],
            "schema_version": r["schema_version"],
            "token_count": r["token_count"],
            "attrs": {
                "decision_id": p["decision_id"], "title": p["title"], "date": p["date"],
                "iteration": p["iteration"], "affected_modules": p["affected_modules"],
                "planes": p["planes"], "type": p["type"], "authority": p["authority"],
                "binding_scope": p["binding_scope"], "enforced_by": p["enforced_by"],
                "ingested_through": p["ingested_through"], "synopsis": p["synopsis"],
            },
            "edges": edges,
        })
    return {
        "schema": INGEST_SCHEMA,
        "op": "ingest-records",
        "db": None,
        "ingest_run": {"producer": "decision.intel", "producer_version": WORKER_VERSION,
                       "namespace": namespace},
        "created_by_ingest_run": ingest_run_id,
        "record_count": len(out_records),
        "records": out_records,
    }


# ------------------------------------------------------------------ validator (s1, adapted)
S1_REQUIRED = ("record_id", "record_version_id", "record_kind", "namespace", "content_hash",
               "status", "authority_level", "sensitivity_class", "valid_from", "valid_to",
               "created_by_ingest_run", "source_version_id", "source_span", "derivation_refs",
               "parser_fingerprint", "chunker_fingerprint", "extractor_fingerprint",
               "schema_version", "token_count", "embedding_space_id", "parent_edges", "child_edges")

VALID_STATUS = (STATUS_CURRENT, STATUS_SUPERSEDED, STATUS_FOLDED, STATUS_CLOSED)
VALID_BINDING_SCOPE = ("standing_prohibition", "invariant", "ordinary")


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
        if r.get("record_kind") != RECORD_KIND:
            errors.append("%s: bad record_kind %r" % (rid, r.get("record_kind")))
        if r.get("status") not in VALID_STATUS:
            errors.append("%s: bad status %r" % (rid, r.get("status")))
        payload = r.get("payload")
        if payload is not None:
            ch = _h(canon(payload))
            if ch != r.get("content_hash"):
                errors.append("%s: content_hash mismatch" % rid)
            expect_rv = "rv_" + _h(r["record_id"] + "\0" + ch)[:24]
            if expect_rv != r.get("record_version_id"):
                errors.append("%s: record_version_id derivation mismatch" % rid)
            if payload.get("binding_scope") not in VALID_BINDING_SCOPE:
                errors.append("%s: bad binding_scope %r" % (rid, payload.get("binding_scope")))
        span = r.get("source_span")
        if not (isinstance(span, dict) and "start" in span and "end" in span):
            errors.append("%s: source_span not a {start,end} object" % rid)
        elif span["start"] is None or span["end"] is None or span["start"] >= span["end"]:
            errors.append("%s: span start>=end" % rid)
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


def _write_artifacts(outdir, records, manifest, ingest_payload, coverage):
    os.makedirs(outdir, exist_ok=True)
    outputs = []

    p = os.path.join(outdir, "records.jsonl")
    _write_text(p, "".join(canon(r) + "\n" for r in records))
    outputs.append({"path": os.path.abspath(p), "kind": "jsonl", "name": "records.jsonl"})

    p = os.path.join(outdir, "records.json")
    _write_text(p, canon(records))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "records.json"})

    p = os.path.join(outdir, "ingest_records.json")
    _write_text(p, canon(ingest_payload))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "ingest_records.json"})

    p = os.path.join(outdir, "index_manifest.json")
    _write_text(p, canon(manifest))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "index_manifest.json"})

    p = os.path.join(outdir, "coverage.json")
    _write_text(p, canon(coverage))
    outputs.append({"path": os.path.abspath(p), "kind": "json", "name": "coverage.json"})

    p = os.path.join(outdir, "summary.md")
    _write_text(p, _render_summary_md(manifest))
    outputs.append({"path": os.path.abspath(p), "kind": "markdown", "name": "summary.md"})

    return outputs


def _render_summary_md(manifest):
    lines = []
    lines.append("# decision.intel index -- %s" % manifest["namespace"])
    lines.append("")
    lines.append("records: %d  ingested_through: %s" % (manifest["total_records"], manifest["ingested_through"]))
    lines.append("records_digest: %s" % manifest["records_digest"])
    lines.append("")
    lines.append("## status")
    lines.append("")
    for k in sorted(manifest["counts_by_status"].keys()):
        lines.append("- %s: %d" % (k, manifest["counts_by_status"][k]))
    lines.append("")
    lines.append("## binding_scope")
    lines.append("")
    for k in sorted(manifest["counts_by_binding_scope"].keys()):
        lines.append("- %s: %d" % (k, manifest["counts_by_binding_scope"][k]))
    lines.append("")
    lines.append("## coverage")
    lines.append("")
    c = manifest["coverage"]
    lines.append("- index_row_count: %d  log_entry_count: %d  ok: %s" % (
        c["index_row_count"], c["log_entry_count"], c["ok"]))
    if c["missing_records_for_index_rows"]:
        lines.append("- MISSING records for index rows: %s" % ", ".join(c["missing_records_for_index_rows"]))
    if c["extra_records_without_index_row"]:
        lines.append("- EXTRA records without an index row: %s" % ", ".join(c["extra_records_without_index_row"]))
    lines.append("")
    if manifest["ambiguous"]:
        lines.append("## ambiguous (honest flags -- not silently dropped)")
        lines.append("")
        for a in manifest["ambiguous"]:
            lines.append("- %s: %s" % (a["decision_id"], ", ".join(a["flags"])))
        lines.append("")
    if manifest["unresolved_supersession_targets"]:
        lines.append("## unresolved supersession targets (declared but not a known decision id)")
        lines.append("")
        for u in manifest["unresolved_supersession_targets"]:
            lines.append("- %s: %s" % (u["decision_id"], ", ".join(u["unresolved_targets"])))
        lines.append("")
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------ validate op (standalone)
def do_validate(args):
    rp = args.get("records_path")
    if not rp or not os.path.isfile(rp):
        raise DecisionIntelError("records_not_found", "validate needs records_path (records.jsonl or records.json)")
    with open(rp, "r", encoding="utf-8") as fh:
        content = fh.read()
    records = []
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
        sys.stderr.write("usage: decision_intel.py <args.json>\n")
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
            raise DecisionIntelError("invalid_op", "unknown op '%s' (index|validate)" % op)
        meta = {"ok": True, "runtime_ms": int((time.time() - t0) * 1000),
                "worker": {"name": "decision.intel", "version": WORKER_VERSION,
                           "python": sys.version.split()[0]}}
        meta.update(payload)
        meta["warnings"] = []
        if payload.get("ambiguous_count"):
            meta["warnings"].append("%d decision(s) flagged ambiguous (see summary.md)" % payload["ambiguous_count"])
        if payload.get("unresolved_supersession_targets"):
            meta["warnings"].append("%d unresolved supersession target(s)" % len(payload["unresolved_supersession_targets"]))
        write_meta(meta)
        sys.stdout.write("DECISION_INTEL_OK op=%s records=%s\n" % (op, payload.get("total_records", "-")))
        return 0
    except DecisionIntelError as de:
        write_meta({"ok": False, "error_code": de.code, "error": de.message,
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("%s: %s\n" % (de.code, de.message))
        return 1
    except Exception as e:
        tb = traceback.format_exc()
        sys.stderr.write(tb + "\n")
        write_meta({"ok": False, "error_code": "decision_intel_failed", "error": repr(e)[:500],
                    "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
