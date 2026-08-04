#!/usr/bin/env python
# artifact_search.py -- deterministic SQLite catalog + hybrid LEXICAL (FTS5) search worker
# for artifact.search (Life Orchestrator, Module 36; skill id artifact.search). SCHEMA v4 / worker 0.4.0.
#
# 0.4 realizes MEMORY_CONTRACT Amendment A5 (D-0096, i33): Tier-0 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING.
# It folds the frontier Tier-0 red-team (pack 159e9cb5): the A4 seams (0.3) are a correct ENVELOPE-level FIRST
# layer but INCOMPLETE. #36 is the retriever/catalog ENFORCEMENT POINT. ADDITIVE + backward-compatible:
#   (U1') namespace CLOSURE -- SAFETY-CRITICAL. ONE canonical predicate `ns_permitted(candidate_ns, effective_
#         allowed)` (the A5 mirror of #37's canonical, byte-identical accept/reject -- asserted at the fold) is
#         enforced at EVERY retrieval stage AND every graph hop (the superseded_by chain walk; list-records edge
#         walk), never only the seed candidate. EVERY returned/graph-reachable object is scope-checked (hit
#         envelope, walked edges, any diagnostic array). A cross-namespace candidate is EXCLUDED before ranking
#         and leaves NO identifying metadata in output -- only `namespace_violation_count` surfaces; identifying
#         detail goes to a PRIVILEGED LOCAL security log (append-only file under the module runtime, NEVER
#         returned). A returned hit outside the effective set is a fail-closed ERROR (`namespace_leak`) that
#         ABORTS. Persisted DERIVED records/aggregates/dedup-clusters/`node`s MUST be namespace-HOMOGENEOUS
#         across their provenance closure -- a cross-namespace derivative is REJECTED at ingest (fail-closed).
#         `effective_allowed` is CALLER-SUPPLIED (the compiler computes intersection(request,grant)); absent =
#         UNSCOPED (back-compat), an explicit EMPTY set => zero hits; NO implicit all/wildcard/prefix/parent.
#   (U4') candidate-INDEPENDENT supersession. NEW s5 value `superseded`; NEW first-class edges `superseded_by`
#         (record -> live successor) + inverse `supersedes`. `effective_current(record)` is computed from the
#         CATALOG/graph -- status==current AND no valid reachable LIVE successor within scope at the snapshot --
#         NOT from the retrieved pair, so `current_only` excludes a predecessor EVEN WHEN its successor is ABSENT
#         from the returned pool (the i32 defect fixed). Chain invariants: acyclic; canonical direction; NO
#         cross-namespace supersession (a cross-ns successor edge is IGNORED per-hop + REJECTED at ingest); a
#         branch (>=2 live successors) is FLAGGED conflicted (surfaced, never a silent pick); a stale/deleted
#         successor does not silently resurrect its predecessor.
#   (U2') provenance_mode-conditional hit shape (A2): direct_span (path+span) | derived_record (record_content_
#         hash + derivation_refs; span OPTIONAL) | aggregate (constituent refs) | tombstone (deletion prov).
#         Hits RESERVE `candidate_role` (navigation|evidence) + retrieval-stage lineage (retrieval_stage_id/
#         parent_stage_id/retrieval_plan_id) -- a compile is MULTI-STAGE (data only; the router is Tier 1).
#   (U3') working-state STORE seam HARDENED. Reserve the store fields on the `working` kind (working_state_id/
#         state_version/parent_state_version/namespace_scope/grant_snapshot_ref/created_from_packet_id/
#         lifecycle_state/writer_authority; task_id/content_role/content_hash already present) as additive
#         columns (NO store lifecycle -- Tier 1). Ordinary `search` REJECTS record_kind=working by DEFAULT;
#         retrievable ONLY by an EXACT op that is CONJUNCTIVE -- task_id AND an in-scope namespace authorization.
# schema_version 3 -> 4 is ADDITIVE in place: `records` gains the provenance_mode + working-store reservation
# columns and a NEW privileged `security_log` table is created; sources/documents/document_versions/chunks are
# rewritten by NONE of it (byte-identical -- the schema-evolution gate test). SCHEMA_NOTES.md is authoritative
# for every A5 interpretation (the canonical-predicate mirror, per-hop + all-object scope-check, sanitized
# rejection + security log, homogeneous-derivation rejection, catalog effective_current + the v3->v4 migration).
#
# 0.2 adopts the FROZEN MEMORY_CONTRACT (D-0083): the s1 record+provenance envelope, a generic
# `ingest_records` SINK for TYPED records (from repo.intel #38 / episode.memory #39), the retriever-0.2
# hit shape (span object + span_label + per-channel diagnostics; opaque `score` retired), the s5 staleness
# ENUM, s4 forward migrations + parser/chunker/extractor fingerprints, and the s2 float32-LE BLOB vector
# storage form keyed on embedding_space_id. SCHEMA_NOTES.md is authoritative for every interpretation.
#
# 0.3 realizes MEMORY_CONTRACT Amendment A4 (D-0092, Tier-0 seam repairs) -- ADDITIVE + backward-compatible:
#   (U1) `namespace` is a HARD retrieval boundary: `search` `filters.namespace` (a single value OR an
#        explicit set) EXCLUDES cross-namespace candidates BEFORE ranking, and the retriever ASSERTS every
#        returned hit matches (a mismatch is a fail-closed `namespace_leak`, never a low-ranked hit).
#   (U4) `current_only` is a real retrieval MODE: a candidate whose s5 status is not `current` is
#        HARD-EXCLUDED (not demoted). The reserved-additive `contradicts` edge joins the edge set.
#   (U2) hierarchy seam (reserved-additive; NO tree built): the CLOSED record_kind enum gains `node`; the
#        edge set gains `member_of_node` (record->node) + `child_of_node` (node->node). #36's flat catalog
#        admits a `node` record via the envelope + record_edges with the schema_version 2->3 bump and NO
#        rewrite of sources/documents/document_versions/chunks.
#   (U3) working-memory seam (reserved-additive; store at Tier 1): the enum gains `working` -- a per-task_id
#        record EXCLUDED from ordinary retrieval unless the request scopes to its `task_id`.
# The schema_version 2->3 migration is additive (a `records.task_id`/`records.content_role` column) and
# rewrites NONE of the shipped tables. SCHEMA_NOTES.md is authoritative for every A4 interpretation.
#
# Contract with the PowerShell wrapper (Invoke-ArtifactSearch.ps1), mirroring the D-0021 worker+meta
# hand-off (robust to library stdout chatter):
#   argv[1] = path to a JSON args file: { op, meta_path, output_dir, db, ... op-specific params }
#   The worker does ALL deterministic work against a SQLite DB (the authoritative catalog), writes any
#   artifact files into output_dir, and writes meta_path with a JSON result. Only meta_path is
#   authoritative; stdout/stderr are diagnostics (captured to worker.log by the wrapper). Exit 0 on
#   success, non-zero on failure (meta_path is written in both cases when possible).
#
# Stdlib only (sqlite3 + FTS5, hashlib, json, os, re, struct, time, math, fnmatch). CPU-only, no model,
# no network. Determinism contract (SCHEMA_NOTES.md is authoritative):
#   * chunk_id / document_id / version_id are content+path derived; the s1 chunk OCCURRENCE id
#     (chunk_occurrence_id) derives ONLY from immutable inputs (document_version_id + chunker_fingerprint
#     + span + chunk_content_hash), NEVER from insertion order.
#   * the SQLite file itself is NOT byte-reproducible (page layout/rowids); the LOGICAL records and the
#     catalog_digest ARE (same corpus content => identical digest across runs AND machines).
#   * search results are emitted in a fully deterministic order with a stable tie-break (tie_break_key).
import sys, os, json, time, hashlib, math, re, sqlite3, fnmatch, struct, traceback

SCHEMA_VERSION = "4"                 # 1->2 (D-0083); 2->3 (A4/D-0092); 3->4 (A5/D-0096); forward-migrated in place
PRIOR_SCHEMA_VERSIONS = ("1", "2", "3")
WORKER_VERSION = "0.4.0"

PARSER_MARKDOWN = ("markdown", "1")
PARSER_TEXT = ("text", "1")

# ---- mock embedding provider (the D-0077 embedding-provider seam; #35 ships the REAL adapter) ----
MOCK_PROVIDER_ID = "mock-hash-v1"
MOCK_MODEL_ID = "mock.embedding.hashvec"
MOCK_MODEL_VERSION = "1"
# a FIXED, deterministic pseudo-sha256 identifying this mock "model" (NOT a real model file hash)
MOCK_MODEL_SHA256 = hashlib.sha256(b"artifact.search/mock-hash-v1").hexdigest()
MOCK_ENGINE_BUILD = "mock"
MOCK_POOLING = "mock-hash-sha256"
DEFAULT_DIM = 64

DEFAULT_MAX_FILE_BYTES = 5_000_000
DEFAULT_MAX_CHUNK_CHARS = 4000
DEFAULT_MAX_EMBED_CHARS = 100_000

# s2 vector storage form: float32 little-endian BLOB, fixed dim, byte-length validated.
VECTOR_ENCODING_VERSION = "f32le/1"

# s5 staleness taxonomy -- status/currentness is an ENUM, never a boolean. 'current' is the healthy state.
# A5/D-0096 adds `superseded` (a valid live successor exists in the supersession chain).
STATUS_CURRENT = "current"
STATUS_SUPERSEDED = "superseded"
STATUS_DELETED = "deleted"
STATUS_ENUM = {
    "current", "source_stale", "derivation_stale", "embedding_stale", "relationship_stale",
    "summary_stale", "authority_stale", "temporal_expiry", "superseded", "deleted", "unverified",
}

# s1 record_kind enum (CLOSED). 'source_chunk' is produced by the chunk pipeline (via the envelope view),
# NOT the ingest_records sink; the sink rejects it as reserved. A4 (D-0092) adds `node` (a navigation node,
# reserved-additive -- the hierarchy seam) + `working` (a per-task_id working-memory record, reserved-additive
# -- the working-memory seam). No tree/store is BUILT here; the kinds + edges are RESERVED so the flat catalog
# admits them additively.
WORKING_KIND = "working"
NODE_KIND = "node"
TYPED_RECORD_KINDS = {
    "symbol", "summary", "decision", "claim", "episode", "failure",
    "procedure", "skill", "reminder", "entity", "relationship",
    "node", "working",                     # A4/D-0092 reserved-additive kinds
}
ALL_RECORD_KINDS = TYPED_RECORD_KINDS | {"source_chunk"}

# s1 record_edge canonical kinds. edge_kind is a free-text column (any producer edge is accepted), but this
# is the DOCUMENTED canonical set; A4 (D-0092) adds `member_of_node` (record->node), `child_of_node`
# (node->node) and `contradicts` (a current-vs-current conflict; detection is Tier 2 -- the edge is reserved).
# A5 (D-0096) adds first-class `superseded_by` (record -> its live successor) + inverse `supersedes` (the
# 0.3 `supersedes` name is kept -- it is now the canonical inverse of `superseded_by`).
RECORD_EDGE_KINDS = {
    "derives_from", "supersedes", "superseded_by", "relates_to", "references", "has_stage",
    "describes_structural_skill",
    "member_of_node", "child_of_node", "contradicts",   # A4/D-0092 reserved-additive edges
}
# A5/U4': the supersession chain edges (record -> successor). `superseded_by` is the canonical forward
# direction (predecessor -> its newer successor); `supersedes` is the inverse (successor -> predecessor).
SUPERSESSION_FWD_KIND = "superseded_by"     # src = predecessor, dst = successor
SUPERSESSION_INV_KIND = "supersedes"        # src = successor,   dst = predecessor
# A5/U1'(c): edge kinds that create a DERIVATION / MEMBERSHIP provenance link -- their target must be
# namespace-HOMOGENEOUS with the source (a cross-namespace target is a laundering path -> REJECT at ingest).
# `supersedes`/`superseded_by` are checked separately (U4'd: no cross-namespace supersession). `relates_to`/
# `references`/`contradicts` are non-derivational cross-references (not a provenance/laundering path).
DERIVATION_EDGE_KINDS = {"derives_from", "member_of_node", "child_of_node"}

# A2/A5 provenance modes -- select the s3 hit's provenance-field validation rule (U2').
PROVENANCE_MODES = {"direct_span", "derived_record", "aggregate", "tombstone"}

DEFAULT_EXCLUDE_DIRS = [
    ".git", "node_modules", "__pycache__", "runtime", "artifacts",
    ".vs", ".idea", "bin", "obj", ".pytest_cache", "_to_delete",
]
DEFAULT_EXCLUDE_GLOBS = ["*.db", "*.db-wal", "*.db-shm", "*.sqlite", "*.sqlite3"]

MARKDOWN_EXTS = {".md", ".markdown", ".mdown", ".mkd"}


class ASError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


# ------------------------------------------------------------------ helpers ----

def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


def sha256_text(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def canon_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def now_utc():
    # ISO-8601 round-trip UTC. Provenance only -- NEVER part of any deterministic id/digest.
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".0000000Z"


def norm_rel(path):
    # repo-relative, forward-slash, no leading ./ -- the CANONICAL identity path (machine-independent).
    p = path.replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p.strip("/")


def classify(rel_path):
    ext = os.path.splitext(rel_path)[1].lower()
    if ext in MARKDOWN_EXTS:
        return ("markdown", PARSER_MARKDOWN[0], PARSER_MARKDOWN[1])
    return ("text", PARSER_TEXT[0], PARSER_TEXT[1])


def make_chunk_id(rel_path, content_hash, chunk_index):
    # PHYSICAL handle (unchanged from 0.1): a stable per-(path,doc-content,position) key used by FTS,
    # vectors, export/store. The CONTRACT occurrence identity is chunk_occurrence_id (index-free) below.
    return "chk_" + hashlib.sha256(
        ("%s\x00%s\x00%d" % (rel_path, content_hash, chunk_index)).encode("utf-8")
    ).hexdigest()[:24]


def make_document_id(source_id, rel_path):
    return "doc_" + hashlib.sha256(("%s\x00%s" % (source_id, rel_path)).encode("utf-8")).hexdigest()[:24]


def make_version_id(document_id, content_hash):
    return "ver_" + hashlib.sha256(("%s\x00%s" % (document_id, content_hash)).encode("utf-8")).hexdigest()[:24]


def make_source_locator_id(source_id, rel_path):
    # PHYSICAL file occurrence identity (a path is a locator, NOT a durable identity). Case-folded so
    # Windows path-casing variants dedup to one locator (NTFS file-ids are evidence only -- not portable,
    # not collected here).
    return "loc_" + hashlib.sha256(("%s\x00%s" % (source_id, rel_path.casefold())).encode("utf-8")).hexdigest()[:24]


def make_source_chunk_record_id(document_id, chunk_index):
    # s1 record_id for a source_chunk: the LOGICAL locator (document + position), survives content revisions.
    return "srec_" + hashlib.sha256(("%s\x00%d" % (document_id, chunk_index)).encode("utf-8")).hexdigest()[:24]


def make_chunk_occurrence_id(document_version_id, chunker_fp, span_start, span_end, chunk_content_hash):
    # s1 IMMUTABLE occurrence identity -- derived ONLY from immutable inputs, NEVER insertion order.
    return "occ_" + hashlib.sha256(
        ("%s\x00%s\x00%d\x00%d\x00%s" %
         (document_version_id, chunker_fp, span_start, span_end, chunk_content_hash)).encode("utf-8")
    ).hexdigest()[:24]


def make_edge_id(src_ref, src_kind, dst_ref, dst_kind, edge_kind):
    return "edg_" + hashlib.sha256(
        ("%s\x00%s\x00%s\x00%s\x00%s" % (src_ref, src_kind, dst_ref, dst_kind, edge_kind)).encode("utf-8")
    ).hexdigest()[:24]


# ---- s4 fingerprints: parser + chunker + extractor on every derived record ----

def parser_fingerprint(parser, parser_version):
    return "pf:%s/%s" % (parser, parser_version)


def chunker_fingerprint(max_chunk_chars):
    # name+version+overlap+max+tokenizer+newline/Unicode normalization+code-fence+heading-context policy.
    # max_chunk_chars is embedded so a chunk-size change INVALIDATES derived chunks even when the source
    # hash is unchanged (s4).
    spec = {
        "name": "md-sections+text-blocks",
        "version": "1",
        "overlap": 0,
        "max_chunk_chars": int(max_chunk_chars),
        "hard_cut_multiple": 2,
        "tokenizer": "byte-span/utf-8",
        "token_estimate": "len//4",
        "newline_norm": "none-byte-exact",
        "unicode_norm": "none",
        "code_fence_policy": "no-split-inside-fence;fenced-heading-ignored",
        "heading_context_policy": "atx1-6;breadcrumb-stack",
    }
    return "ck:md1:mcc%d:%s" % (int(max_chunk_chars), sha256_text(canon_json(spec))[:12])


def embedding_space_id(model_id, model_version, model_sha256, engine_build, dim, normalized,
                       pooling, precision="float32", query_template="", doc_template="",
                       task_instruction="", max_seq=0, truncation="reject"):
    # s2: an IMMUTABLE id that fully defines the vector space. Storage keys on THIS, never provider_id+dim
    # (two providers can share a dim and be mathematically incompatible).
    spec = {
        "model_id": model_id, "model_version": model_version, "model_sha256": model_sha256,
        "engine_build": engine_build, "dim": int(dim), "normalized": bool(normalized),
        "pooling": pooling, "precision": precision, "query_template": query_template,
        "doc_template": doc_template, "task_instruction": task_instruction,
        "max_seq": int(max_seq), "truncation": truncation,
    }
    return "esp_" + sha256_text(canon_json(spec))[:24]


def pack_f32le(vec):
    return struct.pack("<%df" % len(vec), *[float(x) for x in vec])


def unpack_f32le(blob, dim):
    if len(blob) != dim * 4:
        raise ASError("vector_bytes_mismatch", "blob is %d bytes, expected %d (dim %d)" % (len(blob), dim * 4, dim))
    return list(struct.unpack("<%df" % dim, blob))


# ------------------------------------------------------------ chunking (0.1) ----

def split_lines_with_offsets(raw):
    """Return [(byte_start, byte_end)] per line, terminator bytes INCLUDED in the line's span.
    Byte-based => exact spans regardless of LF vs CRLF (the per-file EOL gotcha)."""
    spans = []
    n = len(raw)
    start = 0
    i = 0
    while i < n:
        if raw[i] == 0x0A:  # \n
            spans.append((start, i + 1))
            start = i + 1
        i += 1
    if start < n:
        spans.append((start, n))
    return spans


_FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
_HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")


def _finalize_group(raw, line_spans, group_idxs, section_path, heading, chunk_type):
    if not group_idxs:
        return None
    s = line_spans[group_idxs[0]][0]
    e = line_spans[group_idxs[-1]][1]
    text = raw[s:e].decode("utf-8")
    if text.strip() == "":
        return None
    return {
        "span_start": s, "span_end": e, "section_path": section_path,
        "heading": heading, "chunk_type": chunk_type, "text": text,
    }


def _group_section(raw, line_spans, line_idxs, texts, section_path, heading, chunk_type, max_chars):
    """Split a contiguous run of lines into <= max_chars sub-chunks at blank-line boundaries
    (never inside a code fence). Deterministic."""
    out = []
    buf = []
    buf_chars = 0
    in_fence = False
    for i in line_idxs:
        lt = texts[i]
        stripped = lt.rstrip("\n").rstrip("\r")
        if _FENCE_RE.match(stripped):
            in_fence = not in_fence
        buf.append(i)
        buf_chars += len(lt)
        is_blank = (stripped.strip() == "")
        if (not in_fence) and buf_chars >= max_chars and (is_blank or buf_chars >= max_chars * 2):
            ch = _finalize_group(raw, line_spans, buf, section_path, heading, chunk_type)
            if ch is not None:
                out.append(ch)
            buf = []
            buf_chars = 0
    ch = _finalize_group(raw, line_spans, buf, section_path, heading, chunk_type)
    if ch is not None:
        out.append(ch)
    return out


def chunk_markdown(raw, max_chars):
    line_spans = split_lines_with_offsets(raw)
    texts = [raw[s:e].decode("utf-8") for (s, e) in line_spans]
    in_fence = False
    heading_stack = []  # [(level, title)]
    sections = []       # {'path','heading','lines':[idx]}
    cur = {"path": None, "heading": None, "lines": []}
    for i, lt in enumerate(texts):
        stripped = lt.rstrip("\n").rstrip("\r")
        if _FENCE_RE.match(stripped):
            in_fence = not in_fence
            cur["lines"].append(i)
            continue
        hm = None if in_fence else _HEADING_RE.match(stripped)
        if hm is not None:
            if cur["lines"]:
                sections.append(cur)
            level = len(hm.group(1))
            title = hm.group(2).strip().rstrip("#").strip()
            while heading_stack and heading_stack[-1][0] >= level:
                heading_stack.pop()
            heading_stack.append((level, title))
            path = " / ".join(t for _, t in heading_stack)
            cur = {"path": path, "heading": title, "lines": [i]}
        else:
            cur["lines"].append(i)
    if cur["lines"]:
        sections.append(cur)

    chunks = []
    for sec in sections:
        for ch in _group_section(raw, line_spans, sec["lines"], texts,
                                 sec["path"], sec["heading"], "markdown_section", max_chars):
            chunks.append(ch)
    for idx, ch in enumerate(chunks):
        ch["chunk_index"] = idx
    return chunks


def chunk_text(raw, max_chars):
    line_spans = split_lines_with_offsets(raw)
    texts = [raw[s:e].decode("utf-8") for (s, e) in line_spans]
    all_idxs = list(range(len(texts)))
    chunks = _group_section(raw, line_spans, all_idxs, texts, None, None, "text_block", max_chars)
    for idx, ch in enumerate(chunks):
        ch["chunk_index"] = idx
    return chunks


def chunk_file(rel_path, raw, max_chars):
    src_type, parser, parser_ver = classify(rel_path)
    if parser == "markdown":
        return chunk_markdown(raw, max_chars), src_type, parser, parser_ver
    return chunk_text(raw, max_chars), src_type, parser, parser_ver


# ------------------------------------------------------------- mock embedding ----

def _hash_vector(text, dim, normalize):
    seed = hashlib.sha256(("%s\x00%d\x00%s" % (MOCK_PROVIDER_ID, dim, text)).encode("utf-8")).digest()
    vals = []
    for i in range(dim):
        h = hashlib.sha256(seed + i.to_bytes(4, "little")).digest()
        u = int.from_bytes(h[:4], "little")
        vals.append((u / 4294967295.0) * 2.0 - 1.0)  # deterministic in [-1, 1]
    if normalize:
        norm = math.sqrt(sum(v * v for v in vals))
        if norm > 0.0:
            vals = [v / norm for v in vals]
    return [round(v, 8) for v in vals]


def mock_embed(texts, dim, normalize):
    """The MOCK embedding-provider. Deterministic hashed pseudo-vectors of a fixed dim; vectors align 1:1
    with inputs in EXACT input order; a per-input status lists the exceptions (skipped empties/oversize)
    WITH the input index. Zero-vectors keep alignment + dim invariant for skipped inputs."""
    vectors = []
    statuses = []
    for idx, t in enumerate(texts):
        if t is None or t.strip() == "":
            vectors.append([0.0] * dim)
            statuses.append({"index": idx, "status": "skipped_empty"})
            continue
        if len(t) > DEFAULT_MAX_EMBED_CHARS:
            vectors.append([0.0] * dim)
            statuses.append({"index": idx, "status": "skipped_oversize", "chars": len(t)})
            continue
        vectors.append(_hash_vector(t, dim, normalize))
        statuses.append({"index": idx, "status": "ok"})
    return vectors, statuses


def mock_embedding_space_id(dim, normalize):
    return embedding_space_id(MOCK_MODEL_ID, MOCK_MODEL_VERSION, MOCK_MODEL_SHA256, MOCK_ENGINE_BUILD,
                              dim, normalize, MOCK_POOLING, precision="float32",
                              max_seq=DEFAULT_MAX_EMBED_CHARS, truncation="skip_empty_oversize")


def embed_envelope(texts, dim, normalize):
    vectors, statuses = mock_embed(texts, dim, normalize)
    ok = sum(1 for s in statuses if s["status"] == "ok")
    return {
        "provider_id": MOCK_PROVIDER_ID,
        "model_id": MOCK_MODEL_ID,
        "model_version": MOCK_MODEL_VERSION,
        "model_sha256": MOCK_MODEL_SHA256,
        "engine_build": MOCK_ENGINE_BUILD,
        "embedding_space_id": mock_embedding_space_id(dim, normalize),   # s2 (additive)
        "dim": dim,
        "normalized": bool(normalize),
        "count": len(texts),
        "input_count": len(texts),          # s2 explicit counts (additive)
        "vector_count": ok,
        "failed_count": len(texts) - ok,
        "encoding_version": VECTOR_ENCODING_VERSION,
        "vectors": vectors,
        "input_status": statuses,
    }


# ------------------------------------------------------------------- catalog ----
# v2 schema. FRESH dbs get this directly; a shipped-0.1 (schema_version=1) db is forward-migrated in place
# (Catalog._migrate). chunk_embeddings (0.1 JSON vector column) is RETIRED -> generic `vectors` BLOB table.

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS catalog_meta (
  key   TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS sources (
  source_id   TEXT PRIMARY KEY,
  label       TEXT,
  root_path   TEXT,
  created_at  TEXT,
  last_ingest_at TEXT
);
CREATE TABLE IF NOT EXISTS documents (
  document_id        TEXT PRIMARY KEY,
  source_id          TEXT NOT NULL,
  rel_path           TEXT NOT NULL,
  abs_path           TEXT,
  ext                TEXT,
  source_type        TEXT,
  status             TEXT NOT NULL,           -- active | deleted
  serving_status     TEXT,                    -- active | stale_fallback | deleted   (s4)
  source_locator_id  TEXT,                    -- physical file occurrence identity (s4)
  current_version_id TEXT,                    -- the SERVED (last good) version
  latest_version_id  TEXT,                    -- newest observed version (may be a failed parse)
  deleted_at         TEXT,                    -- tombstone: deletion observation time (s4)
  first_seen_at      TEXT,
  last_seen_at       TEXT,
  UNIQUE(source_id, rel_path)
);
CREATE TABLE IF NOT EXISTS document_paths (
  document_id  TEXT NOT NULL,
  rel_path     TEXT NOT NULL,
  first_seen_at TEXT,
  last_seen_at TEXT,
  PRIMARY KEY (document_id, rel_path)
);
CREATE TABLE IF NOT EXISTS document_versions (
  version_id    TEXT PRIMARY KEY,
  document_id   TEXT NOT NULL,
  content_hash  TEXT NOT NULL,
  size_bytes    INTEGER,
  mtime_utc     TEXT,
  parser        TEXT,
  parser_version TEXT,
  parser_fingerprint TEXT,
  chunker_fingerprint TEXT,
  ingest_run_id TEXT,
  parse_status  TEXT,                         -- ok | failed
  parse_error   TEXT,
  chunk_count   INTEGER,
  is_current    INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT,
  UNIQUE(document_id, content_hash)
);
CREATE TABLE IF NOT EXISTS chunks (
  chunk_id     TEXT PRIMARY KEY,              -- physical handle (0.1 form)
  record_id    TEXT,                          -- s1 source_chunk LOGICAL id (survives revisions)
  chunk_occurrence_id TEXT,                   -- s1 IMMUTABLE occurrence id (index-free)
  chunk_content_hash  TEXT,                   -- s1 two-level identity: hash of THIS chunk's text
  version_id   TEXT NOT NULL,
  document_id  TEXT NOT NULL,
  source_id    TEXT NOT NULL,
  rel_path     TEXT NOT NULL,
  content_hash TEXT NOT NULL,                 -- the DOCUMENT version content hash
  chunk_index  INTEGER NOT NULL,
  span_start   INTEGER NOT NULL,
  span_end     INTEGER NOT NULL,
  section_path TEXT,
  heading      TEXT,
  chunk_type   TEXT,
  parser_fingerprint TEXT,
  chunker_fingerprint TEXT,
  token_estimate INTEGER,
  created_by_run TEXT,
  text         TEXT NOT NULL,
  created_at   TEXT
);
CREATE INDEX IF NOT EXISTS idx_chunks_doc ON chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_ver ON chunks(version_id);
CREATE INDEX IF NOT EXISTS idx_chunks_rel ON chunks(rel_path);
CREATE TABLE IF NOT EXISTS records (
  record_version_id   TEXT PRIMARY KEY,       -- s1 IMMUTABLE revision id
  record_id           TEXT NOT NULL,          -- s1 stable LOGICAL id
  record_kind         TEXT NOT NULL,
  namespace           TEXT,
  content_hash        TEXT,
  status              TEXT,                    -- s5 staleness enum
  authority_level     TEXT,
  sensitivity_class   TEXT,
  valid_from          TEXT,
  valid_to            TEXT,
  created_by_ingest_run TEXT,
  source_version_id   TEXT,
  source_path         TEXT,
  source_span_start   INTEGER,
  source_span_end     INTEGER,
  derivation_refs     TEXT,                    -- json array
  parser_fingerprint  TEXT,
  chunker_fingerprint TEXT,
  extractor_fingerprint TEXT,
  record_schema_version TEXT,
  token_count         INTEGER,
  embedding_space_id  TEXT,
  section_path        TEXT,
  heading             TEXT,
  title               TEXT,
  chunk_type          TEXT,
  attrs_json          TEXT,
  task_id             TEXT,                    -- A4/D-0092: per-task_id working-memory scope (working kind)
  content_role        TEXT,                    -- A4/D-0092: 'evidence' baseline; a working record != evidence
  provenance_mode     TEXT,                    -- A5/A2 (U2'): direct_span|derived_record|aggregate|tombstone
  working_state_id    TEXT,                    -- A5/U3' working-store reservation (store lifecycle = Tier 1)
  state_version       TEXT,                    -- A5/U3'
  parent_state_version TEXT,                   -- A5/U3'
  namespace_scope     TEXT,                    -- A5/U3'
  grant_snapshot_ref  TEXT,                    -- A5/U3'
  created_from_packet_id TEXT,                 -- A5/U3'
  lifecycle_state     TEXT,                    -- A5/U3' active|closed|archived (reserved)
  writer_authority    TEXT,                    -- A5/U3'
  text                TEXT,
  created_at          TEXT
);
CREATE INDEX IF NOT EXISTS idx_records_kind ON records(record_kind);
CREATE INDEX IF NOT EXISTS idx_records_logical ON records(record_id);
CREATE INDEX IF NOT EXISTS idx_records_srcver ON records(source_version_id);
CREATE TABLE IF NOT EXISTS record_edges (
  edge_id     TEXT PRIMARY KEY,               -- deterministic hash of (src,src_kind,dst,dst_kind,kind)
  src_ref     TEXT NOT NULL,
  src_kind    TEXT NOT NULL,                  -- record | chunk | document | document_version
  dst_ref     TEXT NOT NULL,
  dst_kind    TEXT NOT NULL,
  edge_kind   TEXT NOT NULL,                  -- derives_from | supersedes | relates_to | references ...
  attrs_json  TEXT,
  created_by_ingest_run TEXT,
  created_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_edges_src ON record_edges(src_ref);
CREATE INDEX IF NOT EXISTS idx_edges_dst ON record_edges(dst_ref);
CREATE TABLE IF NOT EXISTS vectors (
  target_kind        TEXT NOT NULL,           -- chunk | record
  target_id          TEXT NOT NULL,           -- chunk_id | record_version_id
  embedding_space_id TEXT NOT NULL,           -- s2 storage key (NOT provider_id+dim)
  dim                INTEGER NOT NULL,
  encoding_version   TEXT NOT NULL,           -- f32le/1
  vector_blob        BLOB NOT NULL,           -- float32 little-endian, length == dim*4
  vector_bytes       INTEGER NOT NULL,
  normalized         INTEGER NOT NULL,
  vector_sha256      TEXT,
  provider_id        TEXT,
  model_id           TEXT,
  model_version      TEXT,
  model_sha256       TEXT,
  engine_build       TEXT,
  created_at         TEXT,
  PRIMARY KEY (target_kind, target_id, embedding_space_id)
);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  text, heading, section_path, rel_path UNINDEXED, chunk_id UNINDEXED,
  tokenize = 'unicode61'
);
CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts5(
  text, heading, section_path, record_kind UNINDEXED, record_version_id UNINDEXED, record_id UNINDEXED,
  tokenize = 'unicode61'
);
-- A5/U1'(d): the PRIVILEGED namespace-closure security log. Identifying detail (ids/paths/snippets) of a
-- cross-namespace REJECTED candidate is written HERE and NEVER returned to a caller. EXCLUDED from
-- catalog_digest (determinism) and from every op's result. Append-only in practice.
CREATE TABLE IF NOT EXISTS security_log (
  seq         INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at  TEXT,
  event       TEXT,                            -- namespace_violation | namespace_leak | cross_namespace_derivation
  detail_json TEXT
);
CREATE TABLE IF NOT EXISTS ingest_runs (
  run_id       TEXT PRIMARY KEY,
  source_id    TEXT,
  kind         TEXT,                          -- file_ingest | record_ingest
  producer     TEXT,
  producer_version TEXT,
  repo_commit  TEXT,
  worktree_dirty INTEGER,
  started_at   TEXT,
  finished_at  TEXT,
  added        INTEGER, changed INTEGER, deleted INTEGER, unchanged INTEGER,
  parse_failures INTEGER, moved INTEGER, rejected INTEGER,
  file_budget_hit INTEGER
);
"""

VIEW_SOURCE_CHUNK = """
DROP VIEW IF EXISTS v_records_source_chunk;
CREATE VIEW v_records_source_chunk AS
SELECT
  c.record_id                                                   AS record_id,
  c.chunk_occurrence_id                                         AS record_version_id,
  'source_chunk'                                                AS record_kind,
  c.source_id                                                   AS namespace,
  c.chunk_content_hash                                          AS content_hash,
  CASE WHEN d.serving_status='stale_fallback' THEN 'source_stale' ELSE 'current' END AS status,
  'source_material'                                             AS authority_level,
  'default'                                                     AS sensitivity_class,
  c.created_by_run                                              AS created_by_ingest_run,
  c.version_id                                                  AS source_version_id,
  c.rel_path                                                    AS source_path,
  c.span_start                                                  AS source_span_start,
  c.span_end                                                    AS source_span_end,
  c.parser_fingerprint                                          AS parser_fingerprint,
  c.chunker_fingerprint                                         AS chunker_fingerprint,
  'source_chunk/1'                                              AS record_schema_version,
  c.token_estimate                                              AS token_count,
  (SELECT v.embedding_space_id FROM vectors v
     WHERE v.target_kind='chunk' AND v.target_id=c.chunk_id
     ORDER BY v.embedding_space_id LIMIT 1)                     AS embedding_space_id,
  c.section_path AS section_path, c.heading AS heading, c.chunk_type AS chunk_type,
  c.text AS text, c.chunk_id AS chunk_id, c.chunk_index AS chunk_index, c.document_id AS document_id,
  c.source_id AS source_id, c.content_hash AS doc_content_hash
FROM chunks c JOIN documents d ON c.document_id=d.document_id;
"""


class Catalog:
    def __init__(self, db_path):
        self.db_path = db_path
        d = os.path.dirname(os.path.abspath(db_path))
        if d and not os.path.isdir(d):
            os.makedirs(d, exist_ok=True)
        self.conn = sqlite3.connect(db_path, timeout=30.0)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys=ON")
        self.conn.execute("PRAGMA busy_timeout=30000")
        try:
            self.conn.execute("CREATE VIRTUAL TABLE IF NOT EXISTS _fts_probe USING fts5(x)")
            self.conn.execute("DROP TABLE IF EXISTS _fts_probe")
        except sqlite3.OperationalError as e:
            raise ASError("fts5_unavailable", "SQLite FTS5 is not available in this python's sqlite3: %r" % (e,))
        # detect a pre-existing schema_version BEFORE creating anything new
        prior = None
        try:
            row = self.conn.execute("SELECT value FROM catalog_meta WHERE key='schema_version'").fetchone()
            if row is not None:
                prior = row["value"]
        except sqlite3.OperationalError:
            prior = None  # brand-new db (catalog_meta does not exist yet)
        self.conn.executescript(SCHEMA_SQL)   # idempotent; creates v2 tables that do not yet exist
        self.migration_actions = []
        if prior is None:
            # brand-new db -> stamp v2 directly
            self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('schema_version',?)", (SCHEMA_VERSION,))
            self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('created_at',?)", (now_utc(),))
            self.conn.commit()
        elif prior in PRIOR_SCHEMA_VERSIONS:
            self._migrate(prior)
        elif prior != SCHEMA_VERSION:
            raise ASError("schema_version_unsupported",
                          "catalog schema_version %r is newer/unknown (worker supports up to %s)" % (prior, SCHEMA_VERSION))
        self._ensure_views()

    def close(self):
        try:
            self.conn.close()
        except Exception:
            pass

    def _ensure_views(self):
        # indexes on migration-added columns: created AFTER migration so the column exists on a migrated db
        # (present from the start on a fresh db). idx_records_task backs the A4/D-0092 working-memory scope.
        self.conn.execute("CREATE INDEX IF NOT EXISTS idx_chunks_occ ON chunks(chunk_occurrence_id)")
        self.conn.execute("CREATE INDEX IF NOT EXISTS idx_records_task ON records(task_id)")
        self.conn.executescript(VIEW_SOURCE_CHUNK)
        self.conn.commit()

    # ---- s4 forward migration: shipped-0.1 (schema_version=1) -> 0.2 (2), IN PLACE, no full re-ingest ----
    def _table_cols(self, table):
        return set(r["name"] for r in self.conn.execute("PRAGMA table_info(%s)" % table).fetchall())

    def _add_col(self, table, name, decl):
        if name not in self._table_cols(table):
            self.conn.execute("ALTER TABLE %s ADD COLUMN %s %s" % (table, name, decl))
            self.migration_actions.append("add_col:%s.%s" % (table, name))

    def _migrate(self, from_version):
        # forward, in-place, version-chained: 1->2 (D-0083), 2->3 (A4/D-0092), 3->4 (A5/D-0096). Each step is
        # additive; NONE of them rewrites a shipped table (sources/documents/document_versions/chunks stay
        # byte-identical). Idempotent (a re-open of a current db reports no work).
        acts = self.migration_actions
        acts.append("from:%s" % from_version)
        if from_version == "1":
            self._migrate_1_to_2()
        if from_version in ("1", "2"):
            self._migrate_2_to_3()
        self._migrate_3_to_4()
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('schema_version',?)", (SCHEMA_VERSION,))
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('migrated_at',?)", (now_utc(),))
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('migrated_from',?)", (from_version,))
        self.conn.commit()

    def _migrate_1_to_2(self):
        acts = self.migration_actions
        # 1) additive columns on the shipped tables (fresh v2 already has them; ALTER only if missing)
        self._add_col("documents", "serving_status", "TEXT")
        self._add_col("documents", "source_locator_id", "TEXT")
        self._add_col("documents", "latest_version_id", "TEXT")
        self._add_col("documents", "deleted_at", "TEXT")
        self._add_col("document_versions", "parser_fingerprint", "TEXT")
        self._add_col("document_versions", "chunker_fingerprint", "TEXT")
        self._add_col("document_versions", "ingest_run_id", "TEXT")
        for name in ("kind", "producer", "producer_version", "repo_commit"):
            self._add_col("ingest_runs", name, "TEXT")
        self._add_col("ingest_runs", "worktree_dirty", "INTEGER")
        self._add_col("ingest_runs", "rejected", "INTEGER")
        for name, decl in [
            ("record_id", "TEXT"), ("chunk_occurrence_id", "TEXT"), ("chunk_content_hash", "TEXT"),
            ("parser_fingerprint", "TEXT"), ("chunker_fingerprint", "TEXT"), ("created_by_run", "TEXT"),
        ]:
            self._add_col("chunks", name, decl)
        # 2) backfill document + version derivation metadata (legacy chunker fp: config unknown at 0.1)
        legacy_ck = "ck:legacy-migrated"
        for d in self.conn.execute("SELECT document_id,current_version_id,rel_path,source_id,status,first_seen_at,last_seen_at FROM documents").fetchall():
            self.conn.execute(
                "UPDATE documents SET serving_status=?, source_locator_id=?, latest_version_id=?, deleted_at=? WHERE document_id=?",
                ("deleted" if d["status"] == "deleted" else "active",
                 make_source_locator_id(d["source_id"], d["rel_path"]),
                 d["current_version_id"],
                 (d["last_seen_at"] if d["status"] == "deleted" else None),
                 d["document_id"]))
            self.conn.execute(
                "INSERT OR IGNORE INTO document_paths(document_id,rel_path,first_seen_at,last_seen_at) VALUES(?,?,?,?)",
                (d["document_id"], d["rel_path"], d["first_seen_at"], d["last_seen_at"]))
        for v in self.conn.execute("SELECT version_id,parser,parser_version FROM document_versions").fetchall():
            self.conn.execute(
                "UPDATE document_versions SET parser_fingerprint=?, chunker_fingerprint=? WHERE version_id=?",
                (parser_fingerprint(v["parser"] or "text", v["parser_version"] or "1"), legacy_ck, v["version_id"]))
        # 3) backfill two-level chunk identity + fingerprints on existing chunks (keep chunk_id as the handle)
        for c in self.conn.execute(
                "SELECT c.chunk_id AS chunk_id, c.version_id AS version_id, c.document_id AS document_id, "
                "c.chunk_index AS chunk_index, c.span_start AS span_start, c.span_end AS span_end, c.text AS text, "
                "v.parser AS parser FROM chunks c LEFT JOIN document_versions v ON c.version_id=v.version_id").fetchall():
            cch = sha256_text(c["text"])
            pf = parser_fingerprint(c["parser"] or "text", "1")
            occ = make_chunk_occurrence_id(c["version_id"], legacy_ck, c["span_start"], c["span_end"], cch)
            rid = make_source_chunk_record_id(c["document_id"], c["chunk_index"])
            self.conn.execute(
                "UPDATE chunks SET record_id=?, chunk_occurrence_id=?, chunk_content_hash=?, parser_fingerprint=?, chunker_fingerprint=? WHERE chunk_id=?",
                (rid, occ, cch, pf, legacy_ck, c["chunk_id"]))
        # 4) RETIRE chunk_embeddings (0.1 JSON vector column) -> vectors BLOB keyed on embedding_space_id
        tbls = set(r["name"] for r in self.conn.execute("SELECT name FROM sqlite_master WHERE type='table'"))
        if "chunk_embeddings" in tbls:
            created = now_utc()
            migrated = 0
            for e in self.conn.execute("SELECT * FROM chunk_embeddings").fetchall():
                try:
                    vec = json.loads(e["vector"])
                except Exception:
                    acts.append("emb_parse_fail:%s" % e["chunk_id"])
                    continue
                dim = int(e["dim"]) if e["dim"] else len(vec)
                esp = embedding_space_id(e["model_id"], e["model_version"], e["model_sha256"],
                                         e["engine_build"], dim, bool(e["normalized"]), MOCK_POOLING,
                                         precision="float32", max_seq=DEFAULT_MAX_EMBED_CHARS,
                                         truncation="skip_empty_oversize")
                blob = pack_f32le(vec)
                self.conn.execute(
                    """INSERT OR REPLACE INTO vectors(target_kind,target_id,embedding_space_id,dim,encoding_version,
                       vector_blob,vector_bytes,normalized,vector_sha256,provider_id,model_id,model_version,
                       model_sha256,engine_build,created_at) VALUES('chunk',?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                    (e["chunk_id"], esp, dim, VECTOR_ENCODING_VERSION, blob, len(blob),
                     1 if e["normalized"] else 0, sha256_hex(blob), e["provider_id"], e["model_id"],
                     e["model_version"], e["model_sha256"], e["engine_build"], created))
                migrated += 1
            self.conn.execute("DROP TABLE chunk_embeddings")
            acts.append("retire_chunk_embeddings:%d->vectors" % migrated)

    def _migrate_2_to_3(self):
        # A4/D-0092 Tier-0 reserved-additive seams. ADDITIVE ONLY -- rewrites NO shipped table
        # (sources/documents/document_versions/chunks stay byte-identical -- gate test 2). The `node`+`working`
        # kinds and the `member_of_node`/`child_of_node`/`contradicts` edges need NO new tables (records +
        # record_edges already carry a free-text record_kind/edge_kind); the ONLY schema delta is the
        # working-memory scope columns on `records` (task_id + content_role) + their index.
        self._add_col("records", "task_id", "TEXT")
        self._add_col("records", "content_role", "TEXT")
        # (idx_records_task is created in _ensure_views AFTER migration, once the column exists.)
        self.migration_actions.append("reserve_a4:node+working_kinds;member_of_node+child_of_node+contradicts_edges")

    def _migrate_3_to_4(self):
        # A5/D-0096 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING. ADDITIVE ONLY -- rewrites NO shipped table
        # (sources/documents/document_versions/chunks byte-identical -- the schema-evolution gate test). The
        # `superseded` s5 value + `superseded_by`/`supersedes` edges need NO new column (status/edge_kind are
        # free-text). The deltas: the provenance_mode + working-store reservation columns on `records`, and the
        # new privileged `security_log` table (created by SCHEMA_SQL above; ensured here for an older db).
        for name in ("provenance_mode", "working_state_id", "state_version", "parent_state_version",
                     "namespace_scope", "grant_snapshot_ref", "created_from_packet_id", "lifecycle_state",
                     "writer_authority"):
            self._add_col("records", name, "TEXT")
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS security_log (seq INTEGER PRIMARY KEY AUTOINCREMENT, "
            "created_at TEXT, event TEXT, detail_json TEXT)")
        self.migration_actions.append(
            "reserve_a5:superseded_status+superseded_by/supersedes_edges;provenance_mode+working_store_cols;security_log")

    def schema_version(self):
        r = self.conn.execute("SELECT value FROM catalog_meta WHERE key='schema_version'").fetchone()
        return r["value"] if r else None

    # ---- A4/D-0092: shipped-table schema fingerprint. The four shipped tables (sources / documents /
    # document_versions / chunks) MUST NOT be rewritten by the 2->3 migration; comparing this fingerprint on
    # a v2->v3-migrated db against a fresh v3 db is the 'byte-identical pre/post' proof (gate test 2). ----
    SHIPPED_TABLES = ("sources", "documents", "document_versions", "chunks")

    def shipped_tables_schema(self):
        out = {}
        for t in self.SHIPPED_TABLES:
            row = self.conn.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name=?", (t,)).fetchone()
            out[t] = (row["sql"] if (row is not None and row["sql"] is not None) else None)
        return out

    def shipped_tables_schema_sha(self):
        s = self.shipped_tables_schema()
        return sha256_text("\n".join("%s\x00%s" % (t, s.get(t) or "") for t in self.SHIPPED_TABLES))

    # ---- deletion of a version's derived rows (chunks + fts + vectors) ----
    def _purge_version_derived(self, version_id):
        rows = self.conn.execute("SELECT chunk_id FROM chunks WHERE version_id=?", (version_id,)).fetchall()
        for r in rows:
            self.conn.execute("DELETE FROM chunks_fts WHERE chunk_id=?", (r["chunk_id"],))
            self.conn.execute("DELETE FROM vectors WHERE target_kind='chunk' AND target_id=?", (r["chunk_id"],))
        self.conn.execute("DELETE FROM chunks WHERE version_id=?", (version_id,))

    def _insert_chunks(self, doc, version_id, content_hash, chunks, embed_provider, dim, normalize,
                       created, run_id, chunker_fp, parser_fp):
        rel = doc["rel_path"]
        esp = mock_embedding_space_id(dim, normalize) if embed_provider == "mock" else None
        for ch in chunks:
            cid = make_chunk_id(rel, content_hash, ch["chunk_index"])
            cch = sha256_text(ch["text"])
            occ = make_chunk_occurrence_id(version_id, chunker_fp, ch["span_start"], ch["span_end"], cch)
            rid = make_source_chunk_record_id(doc["document_id"], ch["chunk_index"])
            token_est = max(1, len(ch["text"]) // 4)
            self.conn.execute(
                """INSERT INTO chunks(chunk_id,record_id,chunk_occurrence_id,chunk_content_hash,version_id,
                   document_id,source_id,rel_path,content_hash,chunk_index,span_start,span_end,section_path,
                   heading,chunk_type,parser_fingerprint,chunker_fingerprint,token_estimate,created_by_run,text,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (cid, rid, occ, cch, version_id, doc["document_id"], doc["source_id"], rel, content_hash,
                 ch["chunk_index"], ch["span_start"], ch["span_end"], ch["section_path"], ch["heading"],
                 ch["chunk_type"], parser_fp, chunker_fp, token_est, run_id, ch["text"], created))
            self.conn.execute(
                "INSERT INTO chunks_fts(text,heading,section_path,rel_path,chunk_id) VALUES(?,?,?,?,?)",
                (ch["text"], ch["heading"] or "", ch["section_path"] or "", rel, cid))
            if embed_provider == "mock":
                vec = _hash_vector(ch["text"], dim, normalize) if ch["text"].strip() != "" else [0.0] * dim
                blob = pack_f32le(vec)
                self.conn.execute(
                    """INSERT OR REPLACE INTO vectors(target_kind,target_id,embedding_space_id,dim,encoding_version,
                       vector_blob,vector_bytes,normalized,vector_sha256,provider_id,model_id,model_version,
                       model_sha256,engine_build,created_at) VALUES('chunk',?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                    (cid, esp, dim, VECTOR_ENCODING_VERSION, blob, len(blob), 1 if normalize else 0,
                     sha256_hex(blob), MOCK_PROVIDER_ID, MOCK_MODEL_ID, MOCK_MODEL_VERSION,
                     MOCK_MODEL_SHA256, MOCK_ENGINE_BUILD, created))

    def ingest(self, label, root, include_globs, exclude_dirs, exclude_globs,
               max_files, max_file_bytes, max_chunk_chars, embed_provider, dim, normalize, fault=None):
        if not root or not os.path.isdir(root):
            raise ASError("root_not_found", "ingest root is not a directory: %s" % root)
        source_id = _slug(label) if label else _slug(os.path.basename(os.path.abspath(root)) or "root")
        root_abs = os.path.abspath(root)
        created = now_utc()
        chunker_fp = chunker_fingerprint(max_chunk_chars)
        run_id = "run_" + sha256_text("%s\x00%s\x00%s" % (source_id, created, chunker_fp))[:16]

        src = self.conn.execute("SELECT * FROM sources WHERE source_id=?", (source_id,)).fetchone()
        if src is None:
            self.conn.execute("INSERT INTO sources(source_id,label,root_path,created_at,last_ingest_at) VALUES(?,?,?,?,?)",
                              (source_id, label or source_id, root_abs, created, created))
        else:
            self.conn.execute("UPDATE sources SET root_path=?, last_ingest_at=? WHERE source_id=?",
                              (root_abs, created, source_id))

        seen = []
        budget_hit = False
        for dirpath, dirnames, filenames in os.walk(root_abs):
            dirnames[:] = sorted([d for d in dirnames if d not in exclude_dirs])
            for fn in sorted(filenames):
                ap = os.path.join(dirpath, fn)
                rel = norm_rel(os.path.relpath(ap, root_abs))
                if _excluded(rel, fn, exclude_dirs, exclude_globs):
                    continue
                if include_globs and not any(fnmatch.fnmatch(rel, g) or fnmatch.fnmatch(fn, g) for g in include_globs):
                    continue
                seen.append((rel, ap))
        seen.sort(key=lambda t: t[0])
        if max_files and len(seen) > max_files:
            budget_hit = True
            seen = seen[:max_files]

        seen_rel = set(r for r, _ in seen)
        added, changed, unchanged, parse_failures, stale_fallbacks = [], [], [], [], []

        for rel, ap in seen:
            try:
                with open(ap, "rb") as fh:
                    raw = fh.read()
            except Exception as e:
                parse_failures.append({"rel_path": rel, "reason": "read_error", "detail": repr(e)[:200]})
                self._record_document(source_id, rel, ap, created, raw=b"", content_hash="",
                                      size=0, parse_status="failed", parse_error="read_error: %r" % (e,),
                                      parser="unknown", parser_version="0", chunks=[], src_type="unknown",
                                      embed_provider=embed_provider, dim=dim, normalize=normalize,
                                      run_id=run_id, chunker_fp=chunker_fp, stale_fallbacks=stale_fallbacks)
                continue
            content_hash = sha256_hex(raw)
            doc = self.conn.execute("SELECT * FROM documents WHERE source_id=? AND rel_path=?",
                                    (source_id, rel)).fetchone()
            if doc is not None and doc["status"] == "active" and doc["current_version_id"]:
                cv = self.conn.execute("SELECT content_hash,chunker_fingerprint FROM document_versions WHERE version_id=?",
                                       (doc["current_version_id"],)).fetchone()
                # s4: unchanged ONLY if the DOCUMENT bytes AND the chunker fingerprint are both unchanged.
                same_ck = (cv is not None and cv["chunker_fingerprint"] == chunker_fp)
                if cv is not None and cv["content_hash"] == content_hash and same_ck and doc["serving_status"] != "stale_fallback":
                    self.conn.execute("UPDATE documents SET last_seen_at=? WHERE document_id=?", (created, doc["document_id"]))
                    self.conn.execute("UPDATE document_paths SET last_seen_at=? WHERE document_id=? AND rel_path=?",
                                      (created, doc["document_id"], rel))
                    unchanged.append(rel)
                    continue

            parse_status, parse_error, chunks, src_type, parser, parser_ver = "ok", None, [], "text", "text", "1"
            oversize = len(raw) > max_file_bytes
            if oversize:
                parse_status = "failed"
                parse_error = "oversize: %d bytes > %d" % (len(raw), max_file_bytes)
                parse_failures.append({"rel_path": rel, "reason": "oversize", "detail": parse_error})
            else:
                try:
                    if b"\x00" in raw:
                        raise UnicodeDecodeError("utf-8", b"", 0, 1, "NUL byte (binary)")
                    raw.decode("utf-8")
                except Exception as e:
                    parse_status = "failed"
                    parse_error = "binary_or_undecodable: %r" % (e,)
                    parse_failures.append({"rel_path": rel, "reason": "binary_or_undecodable", "detail": repr(e)[:200]})
            if parse_status == "ok":
                try:
                    chunks, src_type, parser, parser_ver = chunk_file(rel, raw, max_chunk_chars)
                except Exception as e:
                    parse_status = "failed"
                    parse_error = "chunk_error: %r" % (e,)
                    parse_failures.append({"rel_path": rel, "reason": "chunk_error", "detail": repr(e)[:200]})

            is_new = doc is None or doc["status"] != "active" or not doc["current_version_id"]
            served_stale = self._record_document(
                source_id, rel, ap, created, raw=raw, content_hash=content_hash,
                size=len(raw), parse_status=parse_status, parse_error=parse_error,
                parser=parser, parser_version=parser_ver, chunks=chunks, src_type=src_type,
                embed_provider=embed_provider, dim=dim, normalize=normalize,
                run_id=run_id, chunker_fp=chunker_fp, stale_fallbacks=stale_fallbacks)
            if not served_stale:
                (added if is_new else changed).append(rel)

        _maybe_fault(fault, "after_files_before_reconcile")

        # ---- reconcile deletions (tombstone) ----
        deleted = []
        active_docs = self.conn.execute("SELECT * FROM documents WHERE source_id=? AND status='active'",
                                        (source_id,)).fetchall()
        for d in active_docs:
            if d["rel_path"] not in seen_rel:
                if d["current_version_id"]:
                    self._purge_version_derived(d["current_version_id"])
                    self.conn.execute("UPDATE document_versions SET is_current=0 WHERE document_id=?", (d["document_id"],))
                self.conn.execute(
                    "UPDATE documents SET status='deleted', serving_status='deleted', current_version_id=NULL, deleted_at=?, last_seen_at=? WHERE document_id=?",
                    (created, created, d["document_id"]))
                deleted.append(d["rel_path"])

        # ---- moved detection (report-only) ----
        moved = []
        if deleted and added:
            del_hash = {}
            for rel in deleted:
                r = self.conn.execute(
                    """SELECT content_hash FROM document_versions WHERE document_id=
                       (SELECT document_id FROM documents WHERE source_id=? AND rel_path=?)
                       ORDER BY created_at DESC LIMIT 1""", (source_id, rel)).fetchone()
                if r:
                    del_hash.setdefault(r["content_hash"], []).append(rel)
            for rel in added:
                dcur = self.conn.execute("SELECT current_version_id FROM documents WHERE source_id=? AND rel_path=?",
                                         (source_id, rel)).fetchone()
                if dcur and dcur["current_version_id"]:
                    v = self.conn.execute("SELECT content_hash FROM document_versions WHERE version_id=?",
                                          (dcur["current_version_id"],)).fetchone()
                    if v and v["content_hash"] in del_hash and del_hash[v["content_hash"]]:
                        moved.append({"from": del_hash[v["content_hash"]].pop(0), "to": rel})

        # ---- s5 staleness sweep: records whose source version is no longer current become source_stale ----
        stale_marked = self.conn.execute(
            "UPDATE records SET status='source_stale' WHERE status='current' AND source_version_id IN "
            "(SELECT version_id FROM document_versions WHERE is_current=0)").rowcount

        self.conn.execute(
            """INSERT OR REPLACE INTO ingest_runs(run_id,source_id,kind,producer,producer_version,repo_commit,
               worktree_dirty,started_at,finished_at,added,changed,deleted,unchanged,parse_failures,moved,rejected,file_budget_hit)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (run_id, source_id, "file_ingest", "artifact.search", WORKER_VERSION, None, None, created,
             now_utc(), len(added), len(changed), len(deleted), len(unchanged), len(parse_failures),
             len(moved), 0, 1 if budget_hit else 0))

        _maybe_fault(fault, "before_ingest_commit")
        self._set_corpus_version()
        self.conn.commit()

        return {
            "source_id": source_id, "root": root_abs, "run_id": run_id,
            "counts": {"seen": len(seen), "added": len(added), "changed": len(changed),
                       "deleted": len(deleted), "unchanged": len(unchanged),
                       "parse_failures": len(parse_failures), "moved": len(moved),
                       "stale_fallbacks": len(stale_fallbacks), "records_marked_source_stale": stale_marked},
            "added": sorted(added), "changed": sorted(changed), "deleted": sorted(deleted),
            "moved": moved, "parse_failures": parse_failures, "stale_fallbacks": sorted(stale_fallbacks),
            "file_budget_hit": budget_hit, "chunker_fingerprint": chunker_fp,
            "embed_provider": embed_provider, "dim": dim, "normalized": bool(normalize),
        }

    def _record_document(self, source_id, rel, ap, created, raw, content_hash, size, parse_status,
                         parse_error, parser, parser_version, chunks, src_type, embed_provider, dim,
                         normalize, run_id, chunker_fp, stale_fallbacks):
        """Returns True if this observation was served as an EXPLICIT stale fallback (a changed source whose
        NEW content failed to parse -> keep the last good version + chunks, flag the doc stale_fallback)."""
        ext = os.path.splitext(rel)[1].lower()
        pf = parser_fingerprint(parser or "text", parser_version or "1")
        doc = self.conn.execute("SELECT * FROM documents WHERE source_id=? AND rel_path=?", (source_id, rel)).fetchone()
        document_id = make_document_id(source_id, rel)
        locator = make_source_locator_id(source_id, rel)
        had_good_current = bool(doc and doc["current_version_id"] and doc["status"] == "active")
        if doc is None:
            self.conn.execute(
                """INSERT INTO documents(document_id,source_id,rel_path,abs_path,ext,source_type,status,
                   serving_status,source_locator_id,current_version_id,latest_version_id,first_seen_at,last_seen_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (document_id, source_id, rel, ap, ext, src_type, "active", "active", locator, None, None, created, created))
            self.conn.execute("INSERT OR IGNORE INTO document_paths(document_id,rel_path,first_seen_at,last_seen_at) VALUES(?,?,?,?)",
                              (document_id, rel, created, created))
        else:
            document_id = doc["document_id"]

        version_id = make_version_id(document_id, content_hash) if content_hash else \
            ("ver_" + sha256_text(document_id + "\x00noread\x00" + created)[:24])

        # s4: a CHANGED source whose new content FAILS to parse -> serve the last good version as an
        # EXPLICITLY stale fallback (never silently serve old-as-current, never blank the doc).
        if parse_status == "failed" and had_good_current:
            existing_v = self.conn.execute("SELECT version_id FROM document_versions WHERE version_id=?", (version_id,)).fetchone()
            if existing_v is None:
                self.conn.execute(
                    """INSERT INTO document_versions(version_id,document_id,content_hash,size_bytes,mtime_utc,
                       parser,parser_version,parser_fingerprint,chunker_fingerprint,ingest_run_id,parse_status,
                       parse_error,chunk_count,is_current,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,0,?)""",
                    (version_id, document_id, content_hash, size, created, parser, parser_version, pf,
                     chunker_fp, run_id, parse_status, parse_error, 0, created))
            self.conn.execute(
                "UPDATE documents SET abs_path=?, ext=?, source_type=?, status='active', serving_status='stale_fallback', latest_version_id=?, last_seen_at=? WHERE document_id=?",
                (ap, ext, src_type, version_id, created, document_id))
            self.conn.execute("UPDATE document_paths SET last_seen_at=? WHERE document_id=? AND rel_path=?", (created, document_id, rel))
            stale_fallbacks.append(rel)
            return True

        # normal path: purge the OLD current version's derived rows, insert the new version + derived rows.
        # A brand-new (or never-good) file that fails to parse is served as 'unparsed' (no content to serve,
        # surfaced as a parse failure) -- distinct from an 'active' doc that DOES serve parsed content.
        serving = "active" if parse_status == "ok" else "unparsed"
        if doc is not None and doc["current_version_id"]:
            self._purge_version_derived(doc["current_version_id"])
            self.conn.execute("UPDATE document_versions SET is_current=0 WHERE document_id=?", (document_id,))
        self.conn.execute("UPDATE documents SET abs_path=?, ext=?, source_type=?, status='active', serving_status=?, last_seen_at=? WHERE document_id=?",
                          (ap, ext, src_type, serving, created, document_id))
        self.conn.execute("UPDATE document_paths SET last_seen_at=? WHERE document_id=? AND rel_path=?", (created, document_id, rel))

        existing_v = self.conn.execute("SELECT version_id FROM document_versions WHERE version_id=?", (version_id,)).fetchone()
        if existing_v is not None:
            self._purge_version_derived(version_id)
            self.conn.execute(
                """UPDATE document_versions SET size_bytes=?,parser=?,parser_version=?,parser_fingerprint=?,
                   chunker_fingerprint=?,ingest_run_id=?,parse_status=?,parse_error=?,chunk_count=?,is_current=1,created_at=? WHERE version_id=?""",
                (size, parser, parser_version, pf, chunker_fp, run_id, parse_status, parse_error, len(chunks), created, version_id))
        else:
            self.conn.execute(
                """INSERT INTO document_versions(version_id,document_id,content_hash,size_bytes,mtime_utc,
                   parser,parser_version,parser_fingerprint,chunker_fingerprint,ingest_run_id,parse_status,
                   parse_error,chunk_count,is_current,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,1,?)""",
                (version_id, document_id, content_hash, size, created, parser, parser_version, pf,
                 chunker_fp, run_id, parse_status, parse_error, len(chunks), created))
        self.conn.execute("UPDATE documents SET current_version_id=?, latest_version_id=? WHERE document_id=?",
                          (version_id, version_id, document_id))
        if parse_status == "ok" and chunks:
            docrow = {"document_id": document_id, "source_id": source_id, "rel_path": rel}
            self._insert_chunks(docrow, version_id, content_hash, chunks, embed_provider, dim, normalize,
                                created, run_id, chunker_fp, pf)
        return False

    # ------------------------------------------------- ingest_records (SINK) ----
    def ingest_records(self, records, ingest_run, fault=None):
        if not isinstance(records, list):
            raise ASError("invalid_records", "ingest_records needs 'records' (array of s1 envelope records)")
        hdr = ingest_run or {}
        producer = str(hdr.get("producer", "unknown"))
        producer_version = str(hdr.get("producer_version", ""))
        namespace_default = hdr.get("namespace")
        created = now_utc()
        run_id = "rrun_" + sha256_text("%s\x00%s\x00%s\x00%d" % (producer, producer_version, created, len(records)))[:16]

        accepted, rejected, unchanged = [], [], []
        kinds = {}

        def _rvid(r):
            return str(r.get("record_version_id", "")) if isinstance(r, dict) else ""
        ordered = sorted([r for r in records if isinstance(r, dict)], key=lambda r: (_rvid(r), canon_json(_safe(r))))
        for r in [x for x in records if not isinstance(x, dict)]:
            rejected.append({"record_version_id": None, "reason": "not_an_object", "detail": repr(r)[:120]})

        # A5/U1'(c): the in-BATCH namespace map (record_version_id -> declared namespace) so the homogeneity
        # check resolves same-batch parents (a batch may declare a derived record next to its provenance).
        batch_ns = {}
        for r in ordered:
            rv = _rvid(r)
            if rv:
                batch_ns[rv] = (r.get("namespace") or namespace_default)

        for r in ordered:
            rej = self._validate_record(r)
            if rej is not None:
                rejected.append(rej)
                continue
            rvid = str(r["record_version_id"]).strip()
            rid = str(r["record_id"]).strip()
            kind = str(r["record_kind"]).strip()
            text = r.get("text")
            text = "" if text is None else str(text)
            content_hash = r.get("content_hash")
            if not content_hash:
                content_hash = sha256_text(text)
            content_hash = str(content_hash)
            existing = self.conn.execute("SELECT content_hash FROM records WHERE record_version_id=?", (rvid,)).fetchone()
            if existing is not None:
                if existing["content_hash"] == content_hash:
                    unchanged.append(rvid)
                    kinds[kind] = kinds.get(kind, 0) + 1
                    continue
                rejected.append({"record_version_id": rvid, "reason": "record_version_conflict",
                                 "detail": "record_version_id already exists with a different content_hash (immutable revision)"})
                continue

            status = str(r.get("status") or r.get("currentness") or STATUS_CURRENT)
            if status not in STATUS_ENUM:
                rejected.append({"record_version_id": rvid, "reason": "invalid_status", "detail": "status %r not in the s5 enum" % status})
                continue
            namespace = (r.get("namespace") or namespace_default)
            # A5/U1'(c) + U4'd: FAIL-CLOSED reject a persisted cross-namespace derivative (a laundering path).
            # A derived/aggregate/node/member record + every supersession-chain edge MUST be namespace-
            # HOMOGENEOUS across its (resolvable) provenance closure -- Tier 0 forbids cross-namespace
            # derivatives (a shared-scope contract is a later tier).
            hv = self._homogeneity_violation(r, namespace, batch_ns)
            if hv is not None:
                self._security_log("cross_namespace_derivation",
                                   {"record_version_id": rvid, "namespace": namespace,
                                    "relation": hv[0], "ref": hv[1], "other_namespace": hv[2]})
                rejected.append({"record_version_id": rvid, "reason": "cross_namespace_derivation",
                                 "detail": "a %s to %r spans namespace %r != %r (Tier-0 forbids cross-namespace derivatives)"
                                 % (hv[0], hv[1], hv[2], namespace)})
                continue
            span = r.get("source_span") or {}
            ss = span.get("start") if isinstance(span, dict) else None
            se = span.get("end") if isinstance(span, dict) else None
            token_count = r.get("token_count")
            if token_count is None:
                token_count = max(1, len(text) // 4) if text else 0
            derivation_refs = r.get("derivation_refs")
            # A4/D-0092 working-memory scope: task_id (top-level or attrs.task_id) drives isolation; a
            # `working` record is content_role='working' (NEVER evidence), everything else 'evidence' by
            # default (an explicit content_role wins). Non-working records carry task_id=NULL.
            attrs_obj = r.get("attrs") if isinstance(r.get("attrs"), dict) else None
            task_id = r.get("task_id")
            if (task_id is None or str(task_id).strip() == "") and attrs_obj is not None:
                task_id = attrs_obj.get("task_id")
            task_id = str(task_id) if (task_id is not None and str(task_id).strip() != "") else None
            content_role = r.get("content_role")
            if content_role is None and attrs_obj is not None:
                content_role = attrs_obj.get("content_role")
            if content_role is None:
                content_role = "working" if kind == WORKING_KIND else "evidence"
            content_role = str(content_role)
            # A5/U2': provenance_mode (explicit producer value wins; else inferred from the s1 shape).
            prov_mode = r.get("provenance_mode")
            if prov_mode not in PROVENANCE_MODES:
                prov_mode = _infer_provenance_mode(kind, (ss is not None and se is not None), bool(derivation_refs), status)
            # A5/U3': reserved working-store fields (top-level or attrs; NO store lifecycle built -- Tier 1).
            def _wf(name):
                v = r.get(name)
                if (v is None) and attrs_obj is not None:
                    v = attrs_obj.get(name)
                return (str(v) if v is not None else None)
            working_state_id = _wf("working_state_id")
            state_version = _wf("state_version")
            parent_state_version = _wf("parent_state_version")
            namespace_scope = _wf("namespace_scope")
            if namespace_scope is None and kind == WORKING_KIND:
                namespace_scope = namespace          # a working record's default scope is its own namespace
            grant_snapshot_ref = _wf("grant_snapshot_ref")
            created_from_packet_id = _wf("created_from_packet_id")
            lifecycle_state = _wf("lifecycle_state")
            if lifecycle_state is None and kind == WORKING_KIND:
                lifecycle_state = "active"           # reserved default (store promote/demote is Tier 1)
            writer_authority = _wf("writer_authority")
            self.conn.execute(
                """INSERT INTO records(record_version_id,record_id,record_kind,namespace,content_hash,status,
                   authority_level,sensitivity_class,valid_from,valid_to,created_by_ingest_run,source_version_id,
                   source_path,source_span_start,source_span_end,derivation_refs,parser_fingerprint,
                   chunker_fingerprint,extractor_fingerprint,record_schema_version,token_count,embedding_space_id,
                   section_path,heading,title,chunk_type,attrs_json,task_id,content_role,provenance_mode,
                   working_state_id,state_version,parent_state_version,namespace_scope,grant_snapshot_ref,
                   created_from_packet_id,lifecycle_state,writer_authority,text,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (rvid, rid, kind, namespace, content_hash, status,
                 str(r.get("authority_level") or "derived"), str(r.get("sensitivity_class") or "default"),
                 r.get("valid_from"), r.get("valid_to"), run_id, r.get("source_version_id"),
                 r.get("source_path"), ss, se,
                 (canon_json(derivation_refs) if derivation_refs is not None else None),
                 r.get("parser_fingerprint"), r.get("chunker_fingerprint"), r.get("extractor_fingerprint"),
                 str(r.get("schema_version") or (kind + "/1")), int(token_count), r.get("embedding_space_id"),
                 r.get("section_path"), r.get("heading"), r.get("title"), r.get("chunk_type"),
                 (canon_json(r.get("attrs")) if r.get("attrs") is not None else None), task_id, content_role,
                 prov_mode, working_state_id, state_version, parent_state_version, namespace_scope,
                 grant_snapshot_ref, created_from_packet_id, lifecycle_state, writer_authority,
                 text, created))
            if text.strip() != "":
                self.conn.execute(
                    "INSERT INTO records_fts(text,heading,section_path,record_kind,record_version_id,record_id) VALUES(?,?,?,?,?,?)",
                    (text, str(r.get("heading") or ""), str(r.get("section_path") or ""), kind, rvid, rid))
            self._insert_record_edges(rvid, r.get("edges") or [], derivation_refs, run_id, created)
            accepted.append(rvid)
            kinds[kind] = kinds.get(kind, 0) + 1

        _maybe_fault(fault, "before_records_commit")

        self.conn.execute(
            """INSERT OR REPLACE INTO ingest_runs(run_id,source_id,kind,producer,producer_version,repo_commit,
               worktree_dirty,started_at,finished_at,added,changed,deleted,unchanged,parse_failures,moved,rejected,file_budget_hit)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (run_id, namespace_default, "record_ingest", producer, producer_version, hdr.get("repo_commit"),
             (1 if hdr.get("worktree_dirty") else 0), created, now_utc(), len(accepted), 0, 0, len(unchanged),
             0, 0, len(rejected), 0))
        self._set_corpus_version()
        self.conn.commit()
        return {
            "run_id": run_id, "producer": producer, "producer_version": producer_version,
            "counts": {"received": len(records), "accepted": len(accepted), "unchanged": len(unchanged),
                       "rejected": len(rejected), "kinds": kinds},
            "accepted": sorted(accepted), "unchanged": sorted(unchanged), "rejected": rejected,
        }

    # ---- A5/U1'(c) namespace-homogeneity of a derived record's provenance closure ----
    def _resolve_ref_ns(self, ref, batch_ns):
        if ref in batch_ns:
            return batch_ns[ref]
        row = self.conn.execute("SELECT namespace FROM records WHERE record_version_id=?", (str(ref),)).fetchone()
        return row["namespace"] if row else None

    def _source_version_ns(self, source_version_id):
        if not source_version_id:
            return None
        row = self.conn.execute("SELECT source_id FROM chunks WHERE version_id=? LIMIT 1", (str(source_version_id),)).fetchone()
        return row["source_id"] if row else None

    def _homogeneity_violation(self, r, namespace, batch_ns):
        """Return (relation, offending_ref, other_namespace) for the FIRST RESOLVABLE cross-namespace parent /
        derivation / membership / supersession target of `r`, else None. Only RESOLVABLE refs are checked (an
        unresolved forward ref is not proof of a violation). Transitive closure holds by induction: every
        ingested derivative is validated homogeneous with its direct parents, and parents ingest first (or are
        in the same batch map). Non-derivational cross-references (relates_to/references/contradicts) are NOT a
        provenance/laundering path and are not constrained here."""
        def _neq(other):
            # representation-tolerant: a record namespace (raw) vs a chunk source_id (slug) still compares equal
            return other is not None and other != namespace and _slug(other) != _slug(namespace)
        sns = self._source_version_ns(r.get("source_version_id"))
        if _neq(sns):
            return ("source_version", r.get("source_version_id"), sns)
        for d in (r.get("derivation_refs") or []):
            ref = d if isinstance(d, str) else ((d.get("ref") or d.get("dst_ref")) if isinstance(d, dict) else None)
            if not ref:
                continue
            other = self._resolve_ref_ns(ref, batch_ns)
            if _neq(other):
                return ("derivation_ref", ref, other)
        for e in (r.get("edges") or []):
            if not isinstance(e, dict):
                continue
            ek = e.get("edge_kind") or "relates_to"
            dst = e.get("dst_ref") or e.get("dst")
            if not dst:
                continue
            if ek in DERIVATION_EDGE_KINDS or ek in (SUPERSESSION_FWD_KIND, SUPERSESSION_INV_KIND):
                other = self._resolve_ref_ns(dst, batch_ns)
                if _neq(other):
                    return (ek, dst, other)
        return None

    def _validate_record(self, r):
        for req in ("record_id", "record_version_id", "record_kind"):
            if not r.get(req) or not str(r.get(req)).strip():
                return {"record_version_id": (str(r.get("record_version_id")) if r.get("record_version_id") else None),
                        "reason": "missing_required_field", "detail": "missing/empty '%s'" % req}
        kind = str(r["record_kind"]).strip()
        if kind == "source_chunk":
            return {"record_version_id": str(r["record_version_id"]), "reason": "reserved_record_kind",
                    "detail": "source_chunk is produced by the chunk pipeline (envelope view), not ingest_records"}
        if kind not in TYPED_RECORD_KINDS:
            return {"record_version_id": str(r["record_version_id"]), "reason": "unknown_record_kind",
                    "detail": "record_kind %r not in the s1 typed-record enum" % kind}
        if kind == WORKING_KIND:
            tid = r.get("task_id")
            if (tid is None or str(tid).strip() == "") and isinstance(r.get("attrs"), dict):
                tid = r.get("attrs").get("task_id")
            if tid is None or str(tid).strip() == "":
                return {"record_version_id": str(r["record_version_id"]), "reason": "working_requires_task_id",
                        "detail": "a `working` record must carry a task_id (top-level or attrs.task_id) for task-scoped isolation (A4)"}
        text = r.get("text")
        if (text is None or str(text).strip() == "") and not r.get("content_hash"):
            return {"record_version_id": str(r["record_version_id"]), "reason": "missing_content",
                    "detail": "a record needs 'text' (searchable) or an explicit 'content_hash'"}
        return None

    def _insert_record_edges(self, src_rvid, edges, derivation_refs, run_id, created):
        def _add(dst_ref, dst_kind, edge_kind, attrs):
            if not dst_ref:
                return
            eid = make_edge_id(src_rvid, "record", str(dst_ref), str(dst_kind), str(edge_kind))
            self.conn.execute(
                """INSERT OR IGNORE INTO record_edges(edge_id,src_ref,src_kind,dst_ref,dst_kind,edge_kind,attrs_json,created_by_ingest_run,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?)""",
                (eid, src_rvid, "record", str(dst_ref), str(dst_kind), str(edge_kind),
                 (canon_json(attrs) if attrs is not None else None), run_id, created))
        for e in (edges or []):
            if isinstance(e, dict):
                _add(e.get("dst_ref") or e.get("dst"), e.get("dst_kind") or "record", e.get("edge_kind") or "relates_to", e.get("attrs"))
        for d in (derivation_refs or []):
            if isinstance(d, str):
                _add(d, "record", "derives_from", None)
            elif isinstance(d, dict):
                _add(d.get("ref") or d.get("dst_ref"), d.get("kind") or "record", "derives_from", None)

    # -------------------------------------------- record / envelope adapters ----
    def _edges_for(self, rvid, effective_allowed=None):
        """Return (parent_edges, child_edges, dropped_count). A5/U1'(b): when a namespace scope is active, an
        edge whose OTHER endpoint resolves to an out-of-scope record is DROPPED from the returned envelope (a
        cross-namespace `relates_to`/`references`/`contradicts` must not disclose a forbidden record id/ns) --
        only the count surfaces. Derivation/membership/supersession edges are guaranteed intra-namespace at
        ingest, so this only ever redacts non-derivational cross-references."""
        parent, child, dropped = [], [], 0

        def _endpoint_out_of_scope(ref):
            if effective_allowed is None:
                return False
            row = self.conn.execute("SELECT namespace FROM records WHERE record_version_id=?", (str(ref),)).fetchone()
            if row is None:
                return False                    # unresolved endpoint (e.g. a document_version) -> not disclosed
            return not ns_permitted(row["namespace"], effective_allowed)

        for e in self.conn.execute("SELECT dst_ref,dst_kind,edge_kind FROM record_edges WHERE src_ref=? ORDER BY edge_kind,dst_ref", (rvid,)):
            if _endpoint_out_of_scope(e["dst_ref"]):
                dropped += 1; continue
            parent.append({"edge_kind": e["edge_kind"], "dst_ref": e["dst_ref"], "dst_kind": e["dst_kind"]})
        for e in self.conn.execute("SELECT src_ref,src_kind,edge_kind FROM record_edges WHERE dst_ref=? ORDER BY edge_kind,src_ref", (rvid,)):
            if _endpoint_out_of_scope(e["src_ref"]):
                dropped += 1; continue
            child.append({"edge_kind": e["edge_kind"], "src_ref": e["src_ref"], "src_kind": e["src_kind"]})
        return parent, child, dropped

    def _record_envelope(self, row, effective_allowed=None):
        parent, child, dropped = self._edges_for(row["record_version_id"], effective_allowed)
        span = None
        if row["source_span_start"] is not None and row["source_span_end"] is not None:
            span = {"start": row["source_span_start"], "end": row["source_span_end"]}
        env = {
            "record_id": row["record_id"], "record_version_id": row["record_version_id"],
            "record_kind": row["record_kind"], "namespace": row["namespace"],
            "content_hash": row["content_hash"], "status": row["status"],
            "authority_level": row["authority_level"], "sensitivity_class": row["sensitivity_class"],
            "valid_from": row["valid_from"], "valid_to": row["valid_to"],
            "created_by_ingest_run": row["created_by_ingest_run"],
            "source_version_id": row["source_version_id"], "source_path": row["source_path"],
            "source_span": span,
            "derivation_refs": (json.loads(row["derivation_refs"]) if row["derivation_refs"] else None),
            "parser_fingerprint": row["parser_fingerprint"], "chunker_fingerprint": row["chunker_fingerprint"],
            "extractor_fingerprint": row["extractor_fingerprint"], "schema_version": row["record_schema_version"],
            "token_count": row["token_count"], "embedding_space_id": row["embedding_space_id"],
            "section_path": row["section_path"], "heading": row["heading"], "title": row["title"],
            "chunk_type": row["chunk_type"],
            "attrs": (json.loads(row["attrs_json"]) if row["attrs_json"] else None),
            "task_id": row["task_id"], "content_role": row["content_role"],   # A4/D-0092 (working-memory seam)
            # A5/U2' provenance_mode + A5/U3' reserved working-store fields (data only; no store lifecycle).
            "provenance_mode": (row["provenance_mode"] if _has_col(row, "provenance_mode") else None),
            "working_state_id": (row["working_state_id"] if _has_col(row, "working_state_id") else None),
            "state_version": (row["state_version"] if _has_col(row, "state_version") else None),
            "parent_state_version": (row["parent_state_version"] if _has_col(row, "parent_state_version") else None),
            "namespace_scope": (row["namespace_scope"] if _has_col(row, "namespace_scope") else None),
            "grant_snapshot_ref": (row["grant_snapshot_ref"] if _has_col(row, "grant_snapshot_ref") else None),
            "created_from_packet_id": (row["created_from_packet_id"] if _has_col(row, "created_from_packet_id") else None),
            "lifecycle_state": (row["lifecycle_state"] if _has_col(row, "lifecycle_state") else None),
            "writer_authority": (row["writer_authority"] if _has_col(row, "writer_authority") else None),
            "parent_edges": parent, "child_edges": child,
        }
        if effective_allowed is not None:
            env["out_of_scope_edges_dropped"] = dropped   # A5/U1' sanitized (count ONLY)
        return env

    def _source_chunk_envelope(self, row):
        span = {"start": row["source_span_start"], "end": row["source_span_end"]}
        parent = [{"edge_kind": "derives_from", "dst_ref": row["source_version_id"], "dst_kind": "document_version"}]
        return {
            "record_id": row["record_id"], "record_version_id": row["record_version_id"],
            "record_kind": "source_chunk", "namespace": row["namespace"],
            "content_hash": row["content_hash"], "status": row["status"],
            "authority_level": row["authority_level"], "sensitivity_class": row["sensitivity_class"],
            "valid_from": None, "valid_to": None, "created_by_ingest_run": row["created_by_ingest_run"],
            "source_version_id": row["source_version_id"], "source_path": row["source_path"],
            "source_span": span, "derivation_refs": None,
            "parser_fingerprint": row["parser_fingerprint"], "chunker_fingerprint": row["chunker_fingerprint"],
            "extractor_fingerprint": None, "schema_version": row["record_schema_version"],
            "token_count": row["token_count"], "embedding_space_id": row["embedding_space_id"],
            "section_path": row["section_path"], "heading": row["heading"], "title": None,
            "chunk_type": row["chunk_type"], "attrs": None,
            "parent_edges": parent, "child_edges": [],
        }

    def list_records(self, filters, limit):
        filters = filters or {}
        kind = filters.get("record_kind")
        out = []
        if kind is None or kind == "source_chunk":
            q = "SELECT * FROM v_records_source_chunk"
            clauses, params = [], []
            if filters.get("namespace") or filters.get("source"):
                clauses.append("namespace=?"); params.append(_slug(filters.get("namespace") or filters.get("source")))
            if filters.get("path_prefix"):
                clauses.append("source_path LIKE ?"); params.append(norm_rel(filters["path_prefix"]) + "%")
            if clauses:
                q += " WHERE " + " AND ".join(clauses)
            q += " ORDER BY source_path, chunk_index, record_version_id"
            for row in self.conn.execute(q, params):
                out.append(self._source_chunk_envelope(row))
                if limit and len(out) >= limit:
                    return {"count": len(out), "records": out}
        if kind is None or kind in TYPED_RECORD_KINDS:
            q = "SELECT * FROM records"
            clauses, params = [], []
            if kind is not None:
                clauses.append("record_kind=?"); params.append(kind)
            if filters.get("namespace"):
                clauses.append("namespace=?"); params.append(filters["namespace"])
            if filters.get("status"):
                clauses.append("status=?"); params.append(filters["status"])
            # A4/D-0092 (U3): a `working` record surfaces ONLY when the request scopes to its own task_id.
            scope = filters.get("task_id") or filters.get("working_task_id")
            if kind == WORKING_KIND:
                if scope:
                    clauses.append("task_id=?"); params.append(str(scope))
                else:
                    clauses.append("1=0")   # no task scope -> working records never surface
            elif kind is None:
                if scope:
                    clauses.append("(record_kind != ? OR task_id = ?)"); params.extend([WORKING_KIND, str(scope)])
                else:
                    clauses.append("record_kind != ?"); params.append(WORKING_KIND)
            if clauses:
                q += " WHERE " + " AND ".join(clauses)
            q += " ORDER BY record_kind, record_id, record_version_id"
            # A5/U1'(b): when a namespace scope is supplied, pass it so each envelope's edges are scope-checked
            # (a cross-namespace edge target is redacted; only a count surfaces).
            eff = effective_allowed_namespaces(filters)
            for row in self.conn.execute(q, params):
                out.append(self._record_envelope(row, eff))
                if limit and len(out) >= limit:
                    break
        return {"count": len(out), "records": out}

    # --------------------------------------- A5/U4' candidate-independent supersession (graph walk) ----
    def _direct_successors(self, rvid):
        """The IMMEDIATE successors of `rvid` in the supersession chain, with each successor's namespace +
        status, read from the CATALOG/graph (never from a candidate pool). A successor is reachable via a
        forward `superseded_by` edge (src=rvid) OR an inverse `supersedes` edge (dst=rvid). Deterministic order."""
        out = {}
        for e in self.conn.execute(
                "SELECT dst_ref AS svid FROM record_edges WHERE src_ref=? AND edge_kind=?",
                (rvid, SUPERSESSION_FWD_KIND)):
            out[e["svid"]] = True
        for e in self.conn.execute(
                "SELECT src_ref AS svid FROM record_edges WHERE dst_ref=? AND edge_kind=?",
                (rvid, SUPERSESSION_INV_KIND)):
            out[e["svid"]] = True
        res = []
        for svid in sorted(out.keys()):
            row = self.conn.execute("SELECT namespace,status FROM records WHERE record_version_id=?", (svid,)).fetchone()
            res.append((svid, (row["namespace"] if row else None), (row["status"] if row else None), (row is not None)))
        return res

    def _supersession_info(self, rvid, namespace, effective_allowed):
        """Catalog-computed supersession state for one record (A5/U4'). Returns
        {live_successors:[svid...], conflicted:bool, has_live_successor:bool}. Walks the `superseded_by`/
        `supersedes` chain transitively with an ACYCLIC guard; ENFORCES the canonical `ns_permitted` predicate
        at EVERY hop AND same-namespace-only (a cross-namespace successor edge is IGNORED -- NO cross-namespace
        supersession, U4'd), so a walk that would reach an out-of-scope node is blocked per-hop. A `live`
        successor is one whose status == current; the walk continues THROUGH non-live successors to a terminal
        (immediate-vs-terminal distinguished). A branch = >=2 DISTINCT immediate live in-scope successors."""
        immediate_live = []
        any_live = [False]
        seen = set([rvid])

        def walk(node):
            for (svid, sns, sstatus, exists) in self._direct_successors(node):
                if svid in seen:
                    continue                       # acyclic guard
                # per-hop enforcement: same-namespace ALWAYS (no cross-ns supersession); AND within the caller's
                # closed scope when one is supplied (None = UNSCOPED bypasses the predicate, same as every other
                # enforcement site). A cross-namespace or out-of-scope successor edge is IGNORED (blocked per-hop).
                if sns is None or sns != namespace or (effective_allowed is not None and not ns_permitted(sns, effective_allowed)):
                    continue
                seen.add(svid)
                if not exists:
                    continue
                if sstatus == STATUS_CURRENT:
                    any_live[0] = True
                    if node == rvid:
                        immediate_live.append(svid)
                else:
                    walk(svid)                     # non-live successor -> keep walking toward a live terminal

        walk(rvid)
        return {"live_successors": sorted(set(immediate_live)),
                "conflicted": len(set(immediate_live)) >= 2,
                "has_live_successor": any_live[0]}

    def _effective_current(self, rvid, record_kind, status, namespace, effective_allowed):
        """A5/U4': effective_current = (stored status == current) AND (no valid reachable LIVE successor within
        scope at the snapshot). Computed from the CATALOG, so `current_only` excludes a predecessor EVEN WHEN
        its successor is absent from the returned pool (the i32 defect fixed). `source_chunk` has no record
        supersession graph -> its stored status is authoritative."""
        if status != STATUS_CURRENT:
            return False
        if record_kind == "source_chunk":
            return True
        return not self._supersession_info(rvid, namespace, effective_allowed)["has_live_successor"]

    # ------------------------------------------------- A5/U1' privileged namespace security log (sink) ----
    def set_security_log_path(self, path):
        self._security_log_path = path

    def _security_log(self, event, detail):
        """Append-only PRIVILEGED local security log for namespace-closure violations (A5/U1'(d)). Identifying
        detail (ids/paths/snippets) is written HERE and NEVER returned to the caller. A DB `security_log` table
        (privileged, excluded from catalog_digest + never returned by any op) is the durable sink; a configured
        `security_log_path` file additionally receives an append-only JSONL line. Best-effort + fail-safe:
        logging must never break a query (nor leak via an exception message)."""
        try:
            self.conn.execute(
                "INSERT INTO security_log(created_at,event,detail_json) VALUES(?,?,?)",
                (now_utc(), str(event), canon_json(detail)))
            self.conn.commit()
        except Exception:
            pass
        p = getattr(self, "_security_log_path", None)
        if p:
            try:
                d = os.path.dirname(os.path.abspath(p))
                if d and not os.path.isdir(d):
                    os.makedirs(d, exist_ok=True)
                with open(p, "a", encoding="utf-8") as fh:
                    fh.write(canon_json({"at": now_utc(), "event": event, "detail": detail}) + "\n")
            except Exception:
                pass

    # --------------------------------------------------------------- search ----
    def search(self, query, k, mode, filters):
        filters = filters or {}
        if not query or not str(query).strip():
            raise ASError("empty_query", "search query is empty")
        # `mode` is the LEXICAL backend (fts|exact). A4/D-0092 (U4) adds a retrieval TEMPORAL mode
        # `current_only`; #36 locates it under `filters.mode` (canonical) to avoid colliding with the shipped
        # lexical `mode`, but ALSO accepts it in the top-level `mode` slot (the contract's retriever
        # `mode: current_only`) as a compat shim -> the lexical backend defaults to fts.
        top_temporal = None
        if mode == "current_only":
            top_temporal = "current_only"
            mode = "fts"
        if mode not in ("fts", "exact"):
            raise ASError("invalid_mode", "mode must be fts|exact|current_only (got %r)" % mode)
        temporal_mode = str(filters.get("mode") or top_temporal or "default").lower()
        # current_only hard-excludes any non-`current` candidate (NOT a demotion). `filters.exclude_stale`
        # (shipped 0.2) + `filters.current_only` are accepted aliases of the same mode.
        current_only = (temporal_mode == "current_only") or bool(filters.get("current_only")) or bool(filters.get("exclude_stale", False))
        corpus_version = self._get_corpus_version()
        want_status = filters.get("status") or filters.get("currentness")
        kind_filter = filters.get("record_kind")
        # A5/U1': the ONE canonical CLOSED effective-allowed set (or None = unscoped). Enforced at EVERY stage.
        effective_allowed = effective_allowed_namespaces(filters)

        # A5/U1': the searchers scope-check EVERY candidate with the canonical predicate BEFORE any other
        # filter; a cross-namespace candidate is EXCLUDED and its identifying detail is written to the
        # privileged security log (`violations`), NEVER surfaced -- only the COUNT is returned.
        violations = []
        if mode == "fts":
            scored = self._search_fts(query, filters, kind_filter, effective_allowed, violations)
        else:
            scored = self._search_exact(query, filters, kind_filter, effective_allowed, violations)
        # A5/U4': current_only is a real retrieval MODE keyed on CATALOG-computed effective_current (status==
        # current AND no reachable live in-scope successor), so a superseded predecessor is HARD-EXCLUDED EVEN
        # WHEN its successor is absent from this pool (the i32 pool-dependence defect fixed). Per-candidate
        # supersession state is computed once + reused for the hit's reserved conflict flag.
        sinfo = {}
        for x in scored:
            b = x["base"]
            rvid = b.get("record_version_id")
            si = self._supersession_info(rvid, b.get("namespace"), effective_allowed) if b.get("record_kind") != "source_chunk" else {"has_live_successor": False, "conflicted": False, "live_successors": []}
            sinfo[rvid] = si
            x["effective_current"] = (b.get("status") == STATUS_CURRENT) and (b.get("record_kind") == "source_chunk" or not si["has_live_successor"])
        if current_only:
            scored = [x for x in scored if x["effective_current"]]
        # deterministic fused order (lexical-only this wave): (-lexical_score, tie_break_key)
        scored.sort(key=lambda x: (-x["lexical_score"], x["tie_break_key"]))
        for lex_rank, s in enumerate(scored, start=1):
            s["lexical_rank"] = lex_rank
        # A5/U1'(d): only the sanitized COUNT surfaces; the security log (privileged) already holds the detail.
        namespace_violation_count = len(violations)
        for v in violations:
            self._security_log("namespace_violation", v)
        filter_decisions = {
            "mode": mode, "temporal_mode": temporal_mode, "current_only": current_only,
            "record_kind": kind_filter, "source": filters.get("source"),
            "type": filters.get("type"), "path_prefix": filters.get("path_prefix"),
            "content_hash": filters.get("content_hash"), "namespace": filters.get("namespace"),
            "namespace_enforced": (effective_allowed is not None),
            "namespace_allowed": (sorted(effective_allowed) if effective_allowed is not None else None),
            "namespace_violation_count": namespace_violation_count,   # A5/U1' sanitized (count ONLY)
            "task_id": filters.get("task_id"),
            "status": want_status, "exclude_stale": bool(filters.get("exclude_stale", False)),
            "channels": ["lexical"],
        }
        selected = []
        for x in scored:
            st = x["base"].get("status")
            if want_status and st != want_status:
                continue
            selected.append(x)
            if len(selected) >= k:
                break
        hits = []
        for fused_rank, x in enumerate(selected, start=1):
            hit = dict(x["base"])
            hit["retrieval_channels"] = ["lexical"]
            hit["lexical_rank"] = x["lexical_rank"]
            hit["lexical_score"] = round(x["lexical_score"], 6)
            hit["vector_rank"] = None
            hit["vector_similarity"] = None
            hit["fused_rank"] = fused_rank
            hit["fused_score"] = round(x["lexical_score"], 6)
            hit["fusion_algo"] = "lexical_only"
            hit["fusion_version"] = "1"
            hit["index_snapshot"] = corpus_version
            hit["corpus_version"] = corpus_version
            hit["filter_decisions"] = filter_decisions
            hit["tie_break_key"] = x["tie_break_key"]
            hit["snippet"] = x["snippet"]
            hit["rank"] = fused_rank
            # A5/U4': reserved catalog-computed supersession flags on the hit (never a silent pick).
            si = sinfo.get(hit.get("record_version_id")) or {}
            hit["effective_current"] = bool(x.get("effective_current"))
            hit["supersession_conflicted"] = bool(si.get("conflicted"))
            hit["superseded_by"] = list(si.get("live_successors") or [])
            hits.append(hit)
        # A5/U1' all-hits-match assertion (per-hop + all-object closure, defense in depth): if ANY returned hit
        # is outside the effective set, that is a fail-closed ERROR (`namespace_leak`) that ABORTS -- never a
        # low-ranked hit. Uses the SAME canonical predicate as the pre-ranking exclusion, so it can only fire on
        # a real invariant break. The abort message carries NO cross-namespace identifying detail (the leaked
        # record's ids/namespace go to the privileged security log, not the caller-visible error).
        if effective_allowed is not None:
            for h in hits:
                if not ns_permitted(h.get("namespace"), effective_allowed):
                    self._security_log("namespace_leak", {
                        "record_version_id": h.get("record_version_id"), "record_kind": h.get("record_kind"),
                        "namespace": h.get("namespace"), "effective_allowed": sorted(effective_allowed)})
                    raise ASError("namespace_leak",
                                  "retriever produced a hit outside the requested namespace scope (fail-closed abort; "
                                  "detail in the privileged security log)")
        return {"query": query, "mode": mode, "k": k, "count": len(hits),
                "filters": filters, "corpus_version": corpus_version,
                "fusion_algo": "lexical_only", "fusion_version": "1",
                "namespace_enforced": (effective_allowed is not None),
                "namespace_violation_count": namespace_violation_count,   # A5/U1' sanitized (count ONLY)
                "retrieval_channels": ["lexical"], "results": hits}

    def _chunk_hit_base(self, chunk_id):
        row = self.conn.execute("SELECT * FROM v_records_source_chunk WHERE chunk_id=?", (chunk_id,)).fetchone()
        if row is None:
            return None
        d = self.conn.execute("SELECT abs_path FROM documents WHERE document_id=?", (row["document_id"],)).fetchone()
        section = row["section_path"]
        span_label = section if section else ("bytes:%d-%d" % (row["source_span_start"], row["source_span_end"]))
        span = {"start": row["source_span_start"], "end": row["source_span_end"]}
        base = {
            "record_id": row["record_id"], "record_version_id": row["record_version_id"],
            "record_kind": "source_chunk", "chunk_id": chunk_id,
            "source_path": row["source_path"], "abs_path": (d["abs_path"] if d else None),
            # content_hash = the SOURCE VERSION identity (document/file bytes sha256) -- what provenance
            # validation checks (s4: "the content hash identifies the expected source version"). The chunk's
            # own canonical-text hash is exposed separately as chunk_content_hash.
            "content_hash": row["doc_content_hash"],
            "chunk_content_hash": row["content_hash"],
            # A2 provenance hash split (additive; legacy names kept above): a source_chunk's own bytes ARE the
            # cited span, so record_content_hash == excerpt_hash == chunk_content_hash; source_content_hash is
            # the document version identity.
            "record_content_hash": row["content_hash"], "source_content_hash": row["doc_content_hash"],
            "excerpt_hash": row["content_hash"],
            "span": span,
            "span_label": span_label, "section_path": row["section_path"], "heading": row["heading"],
            "chunk_type": row["chunk_type"], "status": row["status"], "currentness": row["status"],
            "authority_level": row["authority_level"], "namespace": row["namespace"],
            "source": row["namespace"], "embedding_space_id": row["embedding_space_id"],
            "source_version_id": row["source_version_id"],
        }
        # A5/U2': provenance_mode-conditional shape + reserved candidate_role + retrieval-stage lineage.
        base["provenance_mode"] = "direct_span"
        base["provenance"] = {"mode": "direct_span", "source_path": row["source_path"], "span": span,
                              "source_content_hash": row["doc_content_hash"], "excerpt_hash": row["content_hash"]}
        base["candidate_role"] = "evidence"
        base.update(_reserved_stage_lineage())
        return base

    def _record_hit_base(self, rvid):
        row = self.conn.execute("SELECT * FROM records WHERE record_version_id=?", (rvid,)).fetchone()
        if row is None:
            return None
        has_span = row["source_span_start"] is not None and row["source_span_end"] is not None
        text = row["text"] or ""
        span = {"start": row["source_span_start"], "end": row["source_span_end"]} if has_span else {"start": 0, "end": len(text.encode("utf-8"))}
        section = row["section_path"]
        if section:
            span_label = section
        elif has_span:
            span_label = "bytes:%d-%d" % (row["source_span_start"], row["source_span_end"])
        else:
            span_label = "record:%s" % row["record_kind"]
        derivation_refs = (json.loads(row["derivation_refs"]) if row["derivation_refs"] else None)
        kind = row["record_kind"]
        pmode = row["provenance_mode"] if _has_col(row, "provenance_mode") and row["provenance_mode"] else \
            _infer_provenance_mode(kind, has_span, bool(derivation_refs), row["status"])
        base = {
            "record_id": row["record_id"], "record_version_id": rvid, "record_kind": kind,
            "chunk_id": None, "source_path": row["source_path"], "abs_path": None,
            "content_hash": row["content_hash"], "record_content_hash": row["content_hash"],
            "source_content_hash": None, "excerpt_hash": None,
            "span": span, "span_label": span_label,
            "section_path": row["section_path"], "heading": row["heading"], "chunk_type": row["chunk_type"],
            "status": row["status"], "currentness": row["status"], "authority_level": row["authority_level"],
            "namespace": row["namespace"], "source": row["namespace"],
            "embedding_space_id": row["embedding_space_id"], "source_version_id": row["source_version_id"],
        }
        # A5/U2': provenance fields CONDITIONAL on provenance_mode (a node/summary/aggregate has no single
        # source span; a tombstone carries deletion provenance). span is retained for back-compat but the
        # `provenance` block is the authoritative per-mode shape.
        if pmode == "direct_span":
            prov = {"mode": pmode, "source_path": row["source_path"], "span": (span if has_span else None)}
        elif pmode == "aggregate":
            prov = {"mode": pmode, "record_content_hash": row["content_hash"], "constituent_refs": (derivation_refs or [])}
        elif pmode == "tombstone":
            prov = {"mode": pmode, "record_content_hash": row["content_hash"], "deleted": True,
                    "derivation_refs": derivation_refs}
        else:  # derived_record (default for a typed record without a single source span)
            prov = {"mode": "derived_record", "record_content_hash": row["content_hash"],
                    "derivation_refs": derivation_refs, "span": (span if has_span else None)}
        base["provenance_mode"] = pmode
        base["provenance"] = prov
        base["candidate_role"] = "navigation" if kind == NODE_KIND else "evidence"
        base.update(_reserved_stage_lineage())
        return base

    # A5/U1': the namespace scope-check is factored OUT of the per-filter passes so the search loops can
    # COUNT + LOG a cross-namespace rejection (sanitized) with the ONE canonical predicate. The passes helpers
    # still assert namespace (defense in depth: export/list-records paths call them directly) using the
    # precomputed effective set.
    def _chunk_passes(self, c, filters, effective_allowed):
        if filters.get("source") and c["source_id"] != _slug(filters["source"]):
            return False
        # A5/U1': enforce the canonical predicate ONLY when a scope is supplied; None = UNSCOPED back-compat
        # BYPASSES the predicate (never widens it -- the predicate itself fail-closes on None).
        if effective_allowed is not None and not ns_permitted(c["source_id"], effective_allowed):
            return False
        if filters.get("type") and c["chunk_type"] != filters["type"]:
            return False
        if filters.get("content_hash") and c["content_hash"] != filters["content_hash"] and c["chunk_content_hash"] != filters["content_hash"]:
            return False
        if filters.get("path_prefix") and not c["rel_path"].startswith(norm_rel(filters["path_prefix"])):
            return False
        return True

    def _record_passes(self, r, filters, effective_allowed):
        # A5/U1': enforce ONLY when a scope is supplied; None = UNSCOPED back-compat BYPASSES the predicate.
        if effective_allowed is not None and not ns_permitted(r["namespace"], effective_allowed):
            return False
        # A5/U3': a `working` record surfaces ONLY under CONJUNCTIVE access -- the request scopes to its exact
        # task_id AND supplies an in-scope namespace authorization (task-isolation and namespace-isolation are
        # DIFFERENT mechanisms). "excluded by default" is too weak: absent EITHER, the working record is hidden.
        if r["record_kind"] == WORKING_KIND:
            scope = filters.get("task_id") or filters.get("working_task_id")
            if not scope or (r["task_id"] or "") != str(scope):
                return False
            if effective_allowed is None:      # no explicit namespace authorization -> not authorized
                return False
        if filters.get("source") and (r["namespace"] or "") != filters["source"] and (r["namespace"] or "") != _slug(filters["source"]):
            return False
        if filters.get("content_hash") and r["content_hash"] != filters["content_hash"]:
            return False
        if filters.get("path_prefix"):
            sp = r["source_path"] or ""
            if not sp.startswith(norm_rel(filters["path_prefix"])):
                return False
        return True

    def _ns_reject(self, violations, kind, ident, ns):
        # A5/U1'(d): record the SANITIZED violation (identifying detail stays in `violations` -> the privileged
        # security log; ONLY the count is ever surfaced to the caller).
        violations.append({"candidate_kind": kind, "id": ident, "namespace": ns})

    def _search_fts(self, query, filters, kind_filter, effective_allowed, violations):
        match = _fts_query(query)
        if not match:
            return []
        out = []
        want_chunks = (kind_filter is None or kind_filter == "source_chunk")
        want_records = (kind_filter is None or kind_filter in TYPED_RECORD_KINDS)
        if want_chunks:
            rows = self.conn.execute(
                "SELECT f.chunk_id AS chunk_id, bm25(chunks_fts) AS bm FROM chunks_fts f WHERE chunks_fts MATCH ?",
                (match,)).fetchall()
            for r in rows:
                c = self.conn.execute("SELECT * FROM chunks WHERE chunk_id=?", (r["chunk_id"],)).fetchone()
                if c is None:
                    continue
                if effective_allowed is not None and not ns_permitted(c["source_id"], effective_allowed):
                    self._ns_reject(violations, "source_chunk", c["chunk_id"], c["source_id"]); continue
                if not self._chunk_passes(c, filters, effective_allowed):
                    continue
                base = self._chunk_hit_base(c["chunk_id"])
                if base is None:
                    continue
                out.append({"base": base, "lexical_score": round(-float(r["bm"]), 6),
                            "tie_break_key": base["record_version_id"],
                            "snippet": _snippet(c["text"], query, mode="fts")})
        if want_records:
            rows = self.conn.execute(
                "SELECT f.record_version_id AS rvid, bm25(records_fts) AS bm FROM records_fts f WHERE records_fts MATCH ?",
                (match,)).fetchall()
            for r in rows:
                rec = self.conn.execute("SELECT * FROM records WHERE record_version_id=?", (r["rvid"],)).fetchone()
                if rec is None:
                    continue
                if effective_allowed is not None and not ns_permitted(rec["namespace"], effective_allowed):
                    self._ns_reject(violations, rec["record_kind"], rec["record_version_id"], rec["namespace"]); continue
                if not self._record_passes(rec, filters, effective_allowed):
                    continue
                if kind_filter is not None and rec["record_kind"] != kind_filter:
                    continue
                base = self._record_hit_base(rec["record_version_id"])
                out.append({"base": base, "lexical_score": round(-float(r["bm"]), 6),
                            "tie_break_key": base["record_version_id"],
                            "snippet": _snippet(rec["text"] or "", query, mode="fts")})
        return out

    def _search_exact(self, query, filters, kind_filter, effective_allowed, violations):
        q = str(query)
        ql = q.lower()
        out = []
        want_chunks = (kind_filter is None or kind_filter == "source_chunk")
        want_records = (kind_filter is None or kind_filter in TYPED_RECORD_KINDS)
        if want_chunks:
            for c in self.conn.execute("SELECT * FROM chunks ORDER BY rel_path, chunk_index, chunk_id").fetchall():
                if effective_allowed is not None and not ns_permitted(c["source_id"], effective_allowed):
                    # count a violation ONLY when the candidate would otherwise match the query (a real leak
                    # attempt), so an unscoped-corpus exact scan does not inflate the count with non-matches.
                    text0 = c["text"]
                    if text0.lower().count(ql) > 0 or ql in c["rel_path"].lower():
                        self._ns_reject(violations, "source_chunk", c["chunk_id"], c["source_id"])
                    continue
                if not self._chunk_passes(c, filters, effective_allowed):
                    continue
                text = c["text"]
                occ = text.lower().count(ql)
                path_hit = ql in c["rel_path"].lower()
                if occ == 0 and not path_hit:
                    continue
                score = float(occ) + (100.0 if path_hit else 0.0)
                base = self._chunk_hit_base(c["chunk_id"])
                if base is None:
                    continue
                out.append({"base": base, "lexical_score": score,
                            "tie_break_key": "0\x00%s\x00%06d\x00%s" % (c["rel_path"], c["chunk_index"], base["record_version_id"]),
                            "snippet": _snippet(text, q, mode="exact")})
        if want_records:
            for rec in self.conn.execute("SELECT * FROM records ORDER BY record_kind, record_id, record_version_id").fetchall():
                text = rec["text"] or ""
                occ = text.lower().count(ql)
                path_hit = bool(rec["source_path"]) and ql in rec["source_path"].lower()
                if effective_allowed is not None and not ns_permitted(rec["namespace"], effective_allowed):
                    if occ > 0 or path_hit:
                        self._ns_reject(violations, rec["record_kind"], rec["record_version_id"], rec["namespace"])
                    continue
                if not self._record_passes(rec, filters, effective_allowed):
                    continue
                if kind_filter is not None and rec["record_kind"] != kind_filter:
                    continue
                if occ == 0 and not path_hit:
                    continue
                score = float(occ) + (100.0 if path_hit else 0.0)
                base = self._record_hit_base(rec["record_version_id"])
                out.append({"base": base, "lexical_score": score,
                            "tie_break_key": "1\x00%s\x00%s" % (rec["record_kind"], rec["record_version_id"]),
                            "snippet": _snippet(text, q, mode="exact")})
        return out

    # ------------------------------------------------------------ integrity ----
    def integrity(self):
        checks = []

        def add(name, ok, detail=""):
            checks.append({"name": name, "ok": bool(ok), "detail": detail})

        r = self.conn.execute("PRAGMA integrity_check").fetchone()
        add("sqlite_integrity_check", r[0] == "ok", str(r[0]))
        fk = self.conn.execute("PRAGMA foreign_key_check").fetchall()
        add("foreign_key_check_empty", len(fk) == 0, "%d violations" % len(fk))

        total = self.conn.execute("SELECT COUNT(*) n FROM chunks").fetchone()["n"]
        distinct = self.conn.execute("SELECT COUNT(DISTINCT chunk_id) n FROM chunks").fetchone()["n"]
        add("no_duplicate_chunk_ids", total == distinct, "total=%d distinct=%d" % (total, distinct))

        docc = self.conn.execute("SELECT COUNT(*) n FROM chunks WHERE chunk_occurrence_id IS NOT NULL").fetchone()["n"]
        distinct_occ = self.conn.execute("SELECT COUNT(DISTINCT chunk_occurrence_id) n FROM chunks WHERE chunk_occurrence_id IS NOT NULL").fetchone()["n"]
        add("no_duplicate_chunk_occurrence_ids", docc == distinct_occ, "occ=%d distinct=%d" % (docc, distinct_occ))

        dup_pos = self.conn.execute(
            "SELECT COUNT(*) n FROM (SELECT version_id,chunk_index,COUNT(*) c FROM chunks "
            "GROUP BY version_id,chunk_index HAVING c>1)").fetchone()["n"]
        add("no_duplicate_chunk_positions", dup_pos == 0, "%d duplicate (version_id,chunk_index)" % dup_pos)

        orphan_chunks = self.conn.execute(
            "SELECT COUNT(*) n FROM chunks c LEFT JOIN document_versions v ON c.version_id=v.version_id "
            "WHERE v.version_id IS NULL").fetchone()["n"]
        add("no_orphan_chunks", orphan_chunks == 0, "%d orphan chunks" % orphan_chunks)

        orphan_vec = self.conn.execute(
            "SELECT COUNT(*) n FROM vectors v WHERE (v.target_kind='chunk' AND v.target_id NOT IN (SELECT chunk_id FROM chunks)) "
            "OR (v.target_kind='record' AND v.target_id NOT IN (SELECT record_version_id FROM records))").fetchone()["n"]
        add("no_orphan_vectors", orphan_vec == 0, "%d orphan vectors" % orphan_vec)

        bad_bytes = self.conn.execute(
            "SELECT COUNT(*) n FROM vectors WHERE vector_bytes != dim*4 OR length(vector_blob) != vector_bytes "
            "OR embedding_space_id IS NULL OR dim<=0").fetchone()["n"]
        add("vectors_f32le_bytes_valid", bad_bytes == 0, "%d bad vector rows" % bad_bytes)

        fts_n = self.conn.execute("SELECT COUNT(*) n FROM chunks_fts").fetchone()["n"]
        add("fts_row_count_equals_chunks", fts_n == total, "fts=%d chunks=%d" % (fts_n, total))

        rec_fts = self.conn.execute("SELECT COUNT(*) n FROM records_fts").fetchone()["n"]
        rec_textful = self.conn.execute("SELECT COUNT(*) n FROM records WHERE text IS NOT NULL AND TRIM(text)!=''").fetchone()["n"]
        add("records_fts_matches_textful_records", rec_fts == rec_textful, "records_fts=%d textful=%d" % (rec_fts, rec_textful))

        rec_dup = self.conn.execute("SELECT COUNT(*) n FROM (SELECT record_version_id,COUNT(*) c FROM records GROUP BY record_version_id HAVING c>1)").fetchone()["n"]
        add("no_duplicate_record_version_ids", rec_dup == 0, "%d dup record_version_ids" % rec_dup)

        bad_status = self.conn.execute(
            "SELECT COUNT(*) n FROM records WHERE status IS NULL OR status NOT IN (%s)" %
            (",".join("'%s'" % s for s in sorted(STATUS_ENUM)))).fetchone()["n"]
        add("records_status_in_enum", bad_status == 0, "%d records with a status outside the s5 enum" % bad_status)

        stale = self.conn.execute(
            "SELECT COUNT(*) n FROM chunks c JOIN document_versions v ON c.version_id=v.version_id "
            "WHERE v.is_current=0").fetchone()["n"]
        add("no_chunks_on_noncurrent_versions", stale == 0, "%d chunks on is_current=0" % stale)

        deleted_chunks = self.conn.execute(
            "SELECT COUNT(*) n FROM chunks c JOIN documents d ON c.document_id=d.document_id "
            "WHERE d.status='deleted'").fetchone()["n"]
        add("no_chunks_on_deleted_documents", deleted_chunks == 0, "%d chunks on deleted docs" % deleted_chunks)

        incomplete_current = self.conn.execute(
            "SELECT COUNT(*) n FROM documents d JOIN document_versions v ON d.current_version_id=v.version_id "
            "WHERE d.status='active' AND d.serving_status='active' AND v.parse_status!='ok'").fetchone()["n"]
        add("serving_docs_point_at_parsed_version", incomplete_current == 0, "%d serving-active docs whose current version is not parse_status=ok" % incomplete_current)

        # A5/U4' supersession-chain invariants (both endpoints must resolve to catalog records to be judged).
        xns = self.conn.execute(
            "SELECT COUNT(*) n FROM record_edges e JOIN records a ON e.src_ref=a.record_version_id "
            "JOIN records b ON e.dst_ref=b.record_version_id "
            "WHERE e.edge_kind IN ('superseded_by','supersedes') AND a.namespace IS NOT b.namespace "
            "AND a.namespace != b.namespace").fetchone()["n"]
        add("no_cross_namespace_supersession", xns == 0, "%d cross-namespace supersession edges" % xns)

        add("supersession_chain_acyclic", not self._supersession_has_cycle(), "a superseded_by/supersedes cycle exists")

        ok = all(c["ok"] for c in checks)
        return {"ok": ok, "checks": checks}

    def _supersession_has_cycle(self):
        """DFS cycle detection over the canonical supersession direction (predecessor -> successor): a
        `superseded_by` edge src->dst, plus an inverse `supersedes` edge dst->src (successor->predecessor)
        read as predecessor(dst)->successor(src). Records-only (both endpoints resolvable)."""
        adj = {}
        for e in self.conn.execute("SELECT src_ref,dst_ref,edge_kind FROM record_edges WHERE edge_kind IN ('superseded_by','supersedes')"):
            if e["edge_kind"] == SUPERSESSION_FWD_KIND:
                a, b = e["src_ref"], e["dst_ref"]     # predecessor -> successor
            else:
                a, b = e["dst_ref"], e["src_ref"]     # supersedes: successor(src) supersedes predecessor(dst)
            adj.setdefault(a, set()).add(b)
        WHITE, GREY, BLACK = 0, 1, 2
        color = {}

        def visit(u):
            color[u] = GREY
            for v in sorted(adj.get(u, ())):
                cv = color.get(v, WHITE)
                if cv == GREY:
                    return True
                if cv == WHITE and visit(v):
                    return True
            color[u] = BLACK
            return False

        for node in sorted(adj.keys()):
            if color.get(node, WHITE) == WHITE:
                if visit(node):
                    return True
        return False

    # -------------------------------------------------------- catalog digest ----
    def catalog_digest(self):
        rows = []
        for c in self.conn.execute(
                "SELECT rel_path,content_hash,chunk_index,span_start,span_end,chunk_id,chunk_content_hash,chunker_fingerprint "
                "FROM chunks ORDER BY rel_path,chunk_index,chunk_id"):
            rows.append("CHK\t%s\t%s\t%d\t%d\t%d\t%s\t%s\t%s" %
                        (c["rel_path"], c["content_hash"], c["chunk_index"], c["span_start"], c["span_end"],
                         c["chunk_id"], (c["chunk_content_hash"] or ""), (c["chunker_fingerprint"] or "")))
        for d in self.conn.execute(
                "SELECT rel_path,status,serving_status,current_version_id FROM documents ORDER BY rel_path"):
            chash = ""
            if d["current_version_id"]:
                v = self.conn.execute("SELECT content_hash,parse_status FROM document_versions WHERE version_id=?",
                                      (d["current_version_id"],)).fetchone()
                if v:
                    chash = "%s|%s" % (v["content_hash"], v["parse_status"])
            rows.append("DOC\t%s\t%s\t%s\t%s" % (d["rel_path"], d["status"], (d["serving_status"] or ""), chash))
        for r in self.conn.execute(
                "SELECT namespace,record_kind,record_id,record_version_id,content_hash,status "
                "FROM records ORDER BY record_kind,record_id,record_version_id"):
            rows.append("REC\t%s\t%s\t%s\t%s\t%s\t%s" %
                        ((r["namespace"] or ""), r["record_kind"], r["record_id"], r["record_version_id"],
                         (r["content_hash"] or ""), (r["status"] or "")))
        for e in self.conn.execute(
                "SELECT src_ref,src_kind,dst_ref,dst_kind,edge_kind FROM record_edges "
                "ORDER BY src_ref,edge_kind,dst_ref,dst_kind"):
            rows.append("REDGE\t%s\t%s\t%s\t%s\t%s" % (e["src_ref"], e["src_kind"], e["dst_ref"], e["dst_kind"], e["edge_kind"]))
        return sha256_text("\n".join(rows))

    def _set_corpus_version(self):
        dg = self.catalog_digest()
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('corpus_version',?)", (dg,))
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('catalog_digest',?)", (dg,))
        return dg

    def _get_corpus_version(self):
        r = self.conn.execute("SELECT value FROM catalog_meta WHERE key='corpus_version'").fetchone()
        return r["value"] if r else self.catalog_digest()

    def counts(self):
        def n(sql):
            return self.conn.execute(sql).fetchone()[0]
        return {
            "sources": n("SELECT COUNT(*) FROM sources"),
            "documents_active": n("SELECT COUNT(*) FROM documents WHERE status='active'"),
            "documents_deleted": n("SELECT COUNT(*) FROM documents WHERE status='deleted'"),
            "documents_stale_fallback": n("SELECT COUNT(*) FROM documents WHERE serving_status='stale_fallback'"),
            "versions": n("SELECT COUNT(*) FROM document_versions"),
            "chunks": n("SELECT COUNT(*) FROM chunks"),
            "records": n("SELECT COUNT(*) FROM records"),
            "record_edges": n("SELECT COUNT(*) FROM record_edges"),
            "embeddings": n("SELECT COUNT(*) FROM vectors WHERE target_kind='chunk'"),
            "record_vectors": n("SELECT COUNT(*) FROM vectors WHERE target_kind='record'"),
            "parse_failures_current": n(
                "SELECT COUNT(*) FROM documents d JOIN document_versions v ON d.current_version_id=v.version_id "
                "WHERE v.parse_status='failed'"),
        }

    # ------------------------------------------------ export / store (fold) ----
    def export_chunk_texts(self, filters, limit):
        rows = self.conn.execute(
            "SELECT chunk_id,rel_path,content_hash,chunk_index,span_start,span_end,text,chunk_content_hash,"
            "chunk_occurrence_id,chunker_fingerprint,source_id,chunk_type FROM chunks "
            "ORDER BY rel_path,chunk_index,chunk_id").fetchall()
        out = []
        eff = effective_allowed_namespaces(filters or {})
        for c in rows:
            if not self._chunk_passes(c, filters or {}, eff):
                continue
            out.append({"chunk_id": c["chunk_id"], "rel_path": c["rel_path"],
                        "content_hash": c["content_hash"],
                        "chunk_content_hash": c["chunk_content_hash"],
                        "chunk_occurrence_id": c["chunk_occurrence_id"],
                        "chunker_fingerprint": c["chunker_fingerprint"],
                        "span": {"start": c["span_start"], "end": c["span_end"]},
                        "text": c["text"]})
            if limit and len(out) >= limit:
                break
        return {"count": len(out), "chunks": out}

    def store_embeddings(self, chunk_ids, vectors, provider_id, dim, normalized,
                         model_id, model_version, model_sha256, engine_build, esp=None, target_kind="chunk"):
        if len(chunk_ids) != len(vectors):
            raise ASError("length_mismatch", "chunk_ids (%d) and vectors (%d) differ" % (len(chunk_ids), len(vectors)))
        if not esp:
            esp = embedding_space_id(model_id or provider_id or "external", model_version or "", model_sha256 or "",
                                     engine_build or "", dim, normalized, "external", precision="float32")
        created = now_utc()
        stored, skipped = 0, 0
        for cid, vec in zip(chunk_ids, vectors):
            if target_kind == "chunk":
                exists = self.conn.execute("SELECT chunk_id FROM chunks WHERE chunk_id=?", (cid,)).fetchone()
            else:
                exists = self.conn.execute("SELECT record_version_id FROM records WHERE record_version_id=?", (cid,)).fetchone()
            if exists is None:
                skipped += 1
                continue
            if dim and len(vec) != dim:
                raise ASError("dim_mismatch", "vector for %s has len %d != dim %d" % (cid, len(vec), dim))
            d = dim or len(vec)
            blob = pack_f32le(vec)
            if len(blob) != d * 4:
                raise ASError("vector_bytes_mismatch", "packed %d bytes != %d for %s" % (len(blob), d * 4, cid))
            self.conn.execute(
                """INSERT OR REPLACE INTO vectors(target_kind,target_id,embedding_space_id,dim,encoding_version,
                   vector_blob,vector_bytes,normalized,vector_sha256,provider_id,model_id,model_version,
                   model_sha256,engine_build,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (target_kind, cid, esp, d, VECTOR_ENCODING_VERSION, blob, len(blob), 1 if normalized else 0,
                 sha256_hex(blob), provider_id, model_id, model_version, model_sha256, engine_build, created))
            stored += 1
        self._set_corpus_version()
        self.conn.commit()
        return {"stored": stored, "requested": len(chunk_ids), "skipped_unknown_target": skipped,
                "provider_id": provider_id, "dim": dim, "embedding_space_id": esp,
                "encoding_version": VECTOR_ENCODING_VERSION, "target_kind": target_kind}

    def get_vector(self, target_kind, target_id, esp=None):
        # round-trip helper (used by tests): return the float32 vector for a target.
        if esp:
            row = self.conn.execute("SELECT * FROM vectors WHERE target_kind=? AND target_id=? AND embedding_space_id=?",
                                    (target_kind, target_id, esp)).fetchone()
        else:
            row = self.conn.execute("SELECT * FROM vectors WHERE target_kind=? AND target_id=? ORDER BY embedding_space_id LIMIT 1",
                                    (target_kind, target_id)).fetchone()
        if row is None:
            return None
        return {"embedding_space_id": row["embedding_space_id"], "dim": row["dim"],
                "encoding_version": row["encoding_version"], "vector_bytes": row["vector_bytes"],
                "normalized": bool(row["normalized"]), "vector_sha256": row["vector_sha256"],
                "vector": unpack_f32le(row["vector_blob"], row["dim"])}


def _slug(s):
    s = str(s).strip().lower()
    s = re.sub(r"[^a-z0-9._-]+", "-", s)
    return s.strip("-") or "src"


# ============================================================================================================
# A5/U1' -- the ONE canonical namespace predicate + rejection policy (MEMORY_CONTRACT A5, D-0096).
#
# CANONICAL-PREDICATE MIRROR NOTE (risk 6): A5(f) requires ONE predicate + rejection policy authored ONCE
# (owned by #37 `lib/`, imported by #40) with #36's retriever implementing the IDENTICAL decision -- the i33
# fold asserts byte-identical accept/reject across #36/#37/#40. #37's standalone `ns_permitted` was NOT yet on
# disk at this worker's build time (only `selpol_rrf_v1.py` existed in modules/37-retrieval-eval/lib/), so per
# the worker prompt's sanctioned fallback this is an EXACT MIRROR of the A5 semantics, kept intentionally
# minimal + pure so the fold's byte-identity check is trivial. The decision is PURE membership of the
# candidate's namespace string in the caller-supplied CLOSED effective set -- no wildcard/prefix/parent/shared.
# ============================================================================================================

def _ns_normalize_allowed(allowed):
    # MIRROR of #37 `namespace_policy.normalize_allowed` (byte-identical decision): None -> None (the UNSCOPED
    # sentinel); a str -> a singleton frozenset; any iterable -> a frozenset of str members (a None member is
    # dropped; an empty input stays empty -> fail-closed). NO expansion of any kind.
    if allowed is None:
        return None
    if isinstance(allowed, str):
        return frozenset([allowed])
    return frozenset(str(x) for x in allowed if x is not None)


def ns_permitted(candidate_namespace, effective_allowed):
    """The canonical Tier-0 namespace predicate (A5/U1') -- a byte-identical-DECISION MIRROR of #37
    `namespace_policy.ns_permitted` (now on disk at `modules/37-retrieval-eval/lib/namespace_policy.py`; the
    fold asserts identical accept/reject across #36/#37/#40). `effective_allowed` is a CLOSED set of permitted
    namespace tokens; membership is EXACT-STRING only -- NO wildcard/prefix/parent/child/shared/`all`. Returns
    True iff the candidate is permitted:
      * effective_allowed is None            -> False (the UNSCOPED SENTINEL: this predicate permits NOTHING.
                                                       #36's 'no namespace filter supplied' back-compat is a
                                                       SEPARATE caller guard that BYPASSES this predicate at the
                                                       enforcement sites -- never a value the predicate invents,
                                                       matching #37's documented design)
      * an EMPTY closed set                   -> False (fail-closed: zero hits)
      * candidate_namespace is None/missing   -> False (a record with no namespace is never in-scope)
      * otherwise                             -> str(candidate_namespace) in effective_allowed  (membership ONLY)
    """
    if effective_allowed is None:
        return False
    allowed = effective_allowed if isinstance(effective_allowed, (set, frozenset)) else _ns_normalize_allowed(effective_allowed)
    if not allowed:
        return False
    if candidate_namespace is None:
        return False
    return str(candidate_namespace) in allowed


def effective_allowed_namespaces(filters):
    """Build #36's CLOSED effective-allowed set from `filters.namespace` (a single value OR an explicit set),
    or None when no namespace filter is present (UNSCOPED back-compat: absent `filters.namespace` = today's
    behavior; the compiler now always supplies it). An explicit EMPTY set/list stays EMPTY (fail-closed: zero
    hits). The set carries BOTH the raw and the `_slug`-normalized form of each requested value: #36 stores TWO
    namespace representations -- record namespaces are the raw envelope value, chunk namespaces are the slugged
    `source_id` -- so both must resolve against the SAME caller request. This dual-form expansion is #36's
    storage-bridging of the effective SET; the PREDICATE (`ns_permitted`, membership) is byte-identical to the
    #37/#40 canonical (the fold asserts identical accept/reject on identical (candidate, set) inputs)."""
    if not filters:
        return None
    if "namespace" not in filters:
        return None
    req = filters.get("namespace")
    if req is None:
        return None
    vals = list(req) if isinstance(req, (list, tuple, set)) else [req]
    allowed = set()
    for v in vals:
        if v is None:
            continue
        allowed.add(str(v))
        allowed.add(_slug(v))
    return frozenset(allowed)


# 0.3 internal names kept as thin aliases (some callers/tests reference the enforced set / predicate by the
# A4 spelling). `_namespace_request` == the effective-allowed builder; `_namespace_ok` == the canonical predicate.
def _namespace_request(filters):
    return effective_allowed_namespaces(filters)


def _namespace_ok(ns, allowed):
    return ns_permitted(ns, allowed)


# A5/U2': reserved retrieval-stage lineage on every hit. A packet compile is MULTI-STAGE (shortlist ->
# descend) with stage-local rankings; #36's flat lexical retrieval is a SINGLE reserved stage this wave (the
# router is Tier 1). Deterministic constant values -- data only, no behavior.
RETRIEVAL_STAGE_ID = "stage:lexical:1"


def _reserved_stage_lineage():
    return {"retrieval_stage_id": RETRIEVAL_STAGE_ID, "parent_stage_id": None, "retrieval_plan_id": None}


def _infer_provenance_mode(record_kind, has_span, has_derivation, status):
    """A2/A5 provenance_mode inference when a producer did not supply one. `tombstone` for a deleted record;
    `aggregate` for a `node` (a navigation synopsis over a bounded child set -- no single source span);
    `direct_span` for a record with a real source span; `derived_record` otherwise."""
    if status == STATUS_DELETED:
        return "tombstone"
    if record_kind == NODE_KIND:
        return "aggregate"
    if has_span:
        return "direct_span"
    return "derived_record"


def _has_col(row, name):
    try:
        return name in row.keys()
    except Exception:
        return False


def _safe(o):
    try:
        json.dumps(o)
        return o
    except Exception:
        return str(o)


def _excluded(rel, fn, exclude_dirs, exclude_globs):
    parts = rel.split("/")
    for p in parts[:-1]:
        if p in exclude_dirs:
            return True
    for g in exclude_globs:
        if fnmatch.fnmatch(fn, g) or fnmatch.fnmatch(rel, g):
            return True
    return False


_WORD_RE = re.compile(r"\w+", re.UNICODE)


def _fts_query(query):
    toks = _WORD_RE.findall(str(query))
    toks = [t for t in toks if t]
    if not toks:
        return None
    return " ".join('"%s"' % t.replace('"', '') for t in toks)


def _snippet(text, query, mode, width=120):
    if not text:
        return ""
    pos = -1
    if mode == "exact":
        pos = text.lower().find(str(query).lower())
    else:
        toks = _WORD_RE.findall(str(query))
        low = text.lower()
        for t in toks:
            p = low.find(t.lower())
            if p >= 0:
                pos = p
                break
    if pos < 0:
        s = text[:width * 2]
        return _collapse_ws(s) + ("..." if len(text) > width * 2 else "")
    start = max(0, pos - width)
    end = min(len(text), pos + width)
    frag = text[start:end]
    prefix = "..." if start > 0 else ""
    suffix = "..." if end < len(text) else ""
    return prefix + _collapse_ws(frag) + suffix


def _collapse_ws(s):
    return re.sub(r"\s+", " ", s).strip()


def _maybe_fault(fault, phase):
    # crash-safety fault injection (s4): raise BEFORE commit at a named phase so the whole transaction
    # rolls back; a fresh open must then see the prior consistent state (no partial rows).
    if fault and str(fault) == phase:
        raise ASError("fault_injected", "fault injected at phase %s (pre-commit; transaction must roll back)" % phase)


# ------------------------------------------------------------------- driver ----

def run(args):
    op = str(args.get("op", "")).lower()
    db_path = args.get("db")
    fault = args.get("_fault")
    out = {"ok": True, "op": op, "artifacts": [], "warnings": [], "result": None}

    output_dir = args.get("output_dir")
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    def art(name, obj, kind="json"):
        if not output_dir:
            return
        p = os.path.join(output_dir, name)
        with open(p, "w", encoding="utf-8") as fh:
            if kind == "json":
                json.dump(obj, fh, ensure_ascii=False, indent=2, sort_keys=True)
            else:
                fh.write(obj if isinstance(obj, str) else str(obj))
        out["artifacts"].append({"path": os.path.abspath(p), "kind": kind})

    if op == "embed":
        texts = args.get("texts")
        if texts is None:
            single = args.get("text")
            texts = [single] if single is not None else []
        if not isinstance(texts, list):
            raise ASError("invalid_inputs", "embed needs 'texts' (array) or 'text' (string)")
        dim = int(args.get("dim", DEFAULT_DIM) or DEFAULT_DIM)
        normalize = bool(args.get("normalize", True))
        env = embed_envelope([("" if t is None else str(t)) for t in texts], dim, normalize)
        out["result"] = env
        art("embeddings.json", env, "json")
        return out

    if not db_path:
        raise ASError("missing_db", "no db path supplied")

    cat = Catalog(db_path)
    # A5/U1'(d): the privileged namespace-closure security log. A DB `security_log` table is always written;
    # a file sink (append-only JSONL) defaults to a `security/` dir beside the catalog db, overridable via
    # `security_log_path`. NEVER surfaced in any result.
    slp = args.get("security_log_path")
    if not slp:
        slp = os.path.join(os.path.dirname(os.path.abspath(db_path)), "security", "namespace_violations.log")
    cat.set_security_log_path(slp)
    try:
        if op == "ingest":
            res = cat.ingest(
                label=args.get("source"),
                root=args.get("root"),
                include_globs=args.get("include"),
                exclude_dirs=(args.get("exclude_dirs") or DEFAULT_EXCLUDE_DIRS),
                exclude_globs=(args.get("exclude") or DEFAULT_EXCLUDE_GLOBS),
                max_files=int(args.get("max_files", 0) or 0),
                max_file_bytes=int(args.get("max_file_bytes", DEFAULT_MAX_FILE_BYTES) or DEFAULT_MAX_FILE_BYTES),
                max_chunk_chars=int(args.get("max_chunk_chars", DEFAULT_MAX_CHUNK_CHARS) or DEFAULT_MAX_CHUNK_CHARS),
                embed_provider=str(args.get("embed_provider", "mock")).lower(),
                dim=int(args.get("dim", DEFAULT_DIM) or DEFAULT_DIM),
                normalize=bool(args.get("normalize", True)),
                fault=fault,
            )
            integ = cat.integrity()
            digest = cat.catalog_digest()
            res["integrity_ok"] = integ["ok"]
            res["catalog_digest"] = digest
            res["schema_version"] = cat.schema_version()
            res["counts_total"] = cat.counts()
            res["db"] = os.path.abspath(db_path)
            if res["file_budget_hit"]:
                out["warnings"].append("file budget hit: only the first %s files indexed" % args.get("max_files"))
            if res["counts"]["parse_failures"] > 0:
                out["warnings"].append("%d parse failure(s) surfaced (see ingest_report.parse_failures)" % res["counts"]["parse_failures"])
            if res["counts"].get("stale_fallbacks"):
                out["warnings"].append("%d source(s) served as EXPLICIT stale fallback (new content failed to parse)" % res["counts"]["stale_fallbacks"])
            if not integ["ok"]:
                out["warnings"].append("integrity check FAILED (see integrity in ingest_report)")
            res["integrity"] = integ
            out["result"] = res
            art("ingest_report.json", res, "json")
            art("catalog_digest.txt", digest + "\n", "text")

        elif op == "ingest-records" or op == "ingest_records":
            res = cat.ingest_records(records=(args.get("records") or []),
                                     ingest_run=(args.get("ingest_run") or {}), fault=fault)
            integ = cat.integrity()
            res["integrity_ok"] = integ["ok"]
            res["integrity"] = integ
            res["catalog_digest"] = cat.catalog_digest()
            res["schema_version"] = cat.schema_version()
            res["counts_total"] = cat.counts()
            res["db"] = os.path.abspath(db_path)
            if res["counts"]["rejected"] > 0:
                out["warnings"].append("%d record(s) REJECTED (see rejected[]); accepted stored" % res["counts"]["rejected"])
            if not integ["ok"]:
                out["warnings"].append("integrity check FAILED after ingest_records")
            out["result"] = res
            art("ingest_records_report.json", res, "json")

        elif op == "list-records" or op == "records":
            res = cat.list_records(args.get("filters") or {}, int(args.get("limit", 0) or 0))
            res["db"] = os.path.abspath(db_path)
            res["counts_total"] = cat.counts()
            out["result"] = res
            art("records.json", res, "json")

        elif op == "migrate":
            res = {"db": os.path.abspath(db_path), "schema_version": cat.schema_version(),
                   "target_schema_version": SCHEMA_VERSION,
                   "migration_actions": cat.migration_actions,
                   "migrated": (len(cat.migration_actions) > 0),
                   "counts": cat.counts(), "integrity": cat.integrity(),
                   "catalog_digest": cat.catalog_digest(),
                   "shipped_tables_schema_sha": cat.shipped_tables_schema_sha()}
            out["result"] = res
            art("migrate_report.json", res, "json")

        elif op == "search":
            res = cat.search(
                query=args.get("query"),
                k=int(args.get("k", 10) or 10),
                mode=str(args.get("mode", "fts")).lower(),
                filters=args.get("filters") or {},
            )
            res["db"] = os.path.abspath(db_path)
            out["result"] = res
            art("search_results.json", res, "json")

        elif op == "integrity":
            res = cat.integrity()
            res["db"] = os.path.abspath(db_path)
            res["schema_version"] = cat.schema_version()
            res["counts"] = cat.counts()
            out["result"] = res
            if not res["ok"]:
                out["warnings"].append("integrity check FAILED")
            art("integrity.json", res, "json")

        elif op == "catalog":
            res = {"db": os.path.abspath(db_path), "schema_version": cat.schema_version(),
                   "digest": cat.catalog_digest(), "counts": cat.counts(),
                   "shipped_tables_schema_sha": cat.shipped_tables_schema_sha()}
            out["result"] = res
            art("catalog.json", res, "json")

        elif op == "export-chunk-texts":
            res = cat.export_chunk_texts(args.get("filters") or {}, int(args.get("limit", 0) or 0))
            res["db"] = os.path.abspath(db_path)
            out["result"] = res
            art("chunk_texts.json", res, "json")

        elif op == "store-embeddings":
            res = cat.store_embeddings(
                chunk_ids=args.get("chunk_ids") or [],
                vectors=args.get("vectors") or [],
                provider_id=args.get("provider_id") or "external",
                dim=int(args.get("dim", 0) or 0),
                normalized=bool(args.get("normalized", True)),
                model_id=args.get("model_id"), model_version=args.get("model_version"),
                model_sha256=args.get("model_sha256"), engine_build=args.get("engine_build"),
                esp=args.get("embedding_space_id"),
                target_kind=str(args.get("target_kind", "chunk")).lower(),
            )
            out["result"] = res

        elif op == "get-vector":
            res = cat.get_vector(str(args.get("target_kind", "chunk")).lower(),
                                 args.get("target_id"), args.get("embedding_space_id"))
            out["result"] = {"vector": res, "db": os.path.abspath(db_path)}

        else:
            raise ASError("invalid_op", "unknown op %r (ingest|ingest-records|list-records|migrate|search|embed|integrity|catalog|export-chunk-texts|store-embeddings|get-vector)" % op)
    finally:
        cat.close()
    return out


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: artifact_search.py <args.json>\n")
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
                json.dump(d, fh, ensure_ascii=False)
        except Exception as e:
            sys.stderr.write("meta write failed: %r\n" % (e,))

    try:
        out = run(args)
        out["worker"] = {"python": sys.version.split()[0], "sqlite": sqlite3.sqlite_version,
                         "worker_version": WORKER_VERSION, "schema_version": SCHEMA_VERSION}
        out["runtime_ms"] = int((time.time() - t0) * 1000)
        write_meta(out)
        sys.stdout.write("ARTIFACT_SEARCH_OK op=%s\n" % out.get("op"))
        return 0
    except ASError as ae:
        write_meta({"ok": False, "op": args.get("op"), "error_code": ae.code, "error": ae.message,
                    "runtime_ms": int((time.time() - t0) * 1000)})
        sys.stderr.write("%s: %s\n" % (ae.code, ae.message))
        return 1
    except Exception as e:
        tb = traceback.format_exc()
        sys.stderr.write(tb + "\n")
        write_meta({"ok": False, "op": args.get("op"), "error_code": "artifact_search_failed",
                    "error": repr(e)[:500], "runtime_ms": int((time.time() - t0) * 1000)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
