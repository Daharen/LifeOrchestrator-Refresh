#!/usr/bin/env python
# FROZEN COPY of the shipped artifact.search 0.2.0 worker (schema_version=2).
# USED ONLY as a fixture to seed a v2 SQLite catalog for the 0.2->0.3 (A4/D-0092) migration test.
# DO NOT EDIT. The live worker is ../artifact_search.py (0.3.0, schema_version=3).
#!/usr/bin/env python
# artifact_search.py -- deterministic SQLite catalog + hybrid LEXICAL (FTS5) search worker
# for artifact.search (Life Orchestrator, Module 36; skill id artifact.search). SCHEMA v2 / worker 0.2.0.
#
# 0.2 adopts the FROZEN MEMORY_CONTRACT (D-0083): the s1 record+provenance envelope, a generic
# `ingest_records` SINK for TYPED records (from repo.intel #38 / episode.memory #39), the retriever-0.2
# hit shape (span object + span_label + per-channel diagnostics; opaque `score` retired), the s5 staleness
# ENUM, s4 forward migrations + parser/chunker/extractor fingerprints, and the s2 float32-LE BLOB vector
# storage form keyed on embedding_space_id. SCHEMA_NOTES.md is authoritative for every interpretation.
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

SCHEMA_VERSION = "2"                 # bumped 1 -> 2 (D-0083 adoption); forward-migrated in place
PRIOR_SCHEMA_VERSIONS = ("1",)
WORKER_VERSION = "0.2.0"

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
STATUS_CURRENT = "current"
STATUS_ENUM = {
    "current", "source_stale", "derivation_stale", "embedding_stale", "relationship_stale",
    "summary_stale", "authority_stale", "temporal_expiry", "deleted", "unverified",
}

# s1 record_kind enum. 'source_chunk' is produced by the chunk pipeline (via the envelope view), NOT the
# ingest_records sink; the sink rejects it as reserved.
TYPED_RECORD_KINDS = {
    "symbol", "summary", "decision", "claim", "episode", "failure",
    "procedure", "skill", "reminder", "entity", "relationship",
}
ALL_RECORD_KINDS = TYPED_RECORD_KINDS | {"source_chunk"}

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
        # index on the new occurrence-id column: created AFTER migration so the column exists on a
        # migrated v1 db (it is present from the start on a fresh v2 db).
        self.conn.execute("CREATE INDEX IF NOT EXISTS idx_chunks_occ ON chunks(chunk_occurrence_id)")
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
        acts = self.migration_actions
        acts.append("from:%s" % from_version)
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
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('schema_version',?)", (SCHEMA_VERSION,))
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('migrated_at',?)", (now_utc(),))
        self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('migrated_from',?)", (from_version,))
        self.conn.commit()

    def schema_version(self):
        r = self.conn.execute("SELECT value FROM catalog_meta WHERE key='schema_version'").fetchone()
        return r["value"] if r else None

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
            span = r.get("source_span") or {}
            ss = span.get("start") if isinstance(span, dict) else None
            se = span.get("end") if isinstance(span, dict) else None
            token_count = r.get("token_count")
            if token_count is None:
                token_count = max(1, len(text) // 4) if text else 0
            derivation_refs = r.get("derivation_refs")
            self.conn.execute(
                """INSERT INTO records(record_version_id,record_id,record_kind,namespace,content_hash,status,
                   authority_level,sensitivity_class,valid_from,valid_to,created_by_ingest_run,source_version_id,
                   source_path,source_span_start,source_span_end,derivation_refs,parser_fingerprint,
                   chunker_fingerprint,extractor_fingerprint,record_schema_version,token_count,embedding_space_id,
                   section_path,heading,title,chunk_type,attrs_json,text,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (rvid, rid, kind, (r.get("namespace") or namespace_default), content_hash, status,
                 str(r.get("authority_level") or "derived"), str(r.get("sensitivity_class") or "default"),
                 r.get("valid_from"), r.get("valid_to"), run_id, r.get("source_version_id"),
                 r.get("source_path"), ss, se,
                 (canon_json(derivation_refs) if derivation_refs is not None else None),
                 r.get("parser_fingerprint"), r.get("chunker_fingerprint"), r.get("extractor_fingerprint"),
                 str(r.get("schema_version") or (kind + "/1")), int(token_count), r.get("embedding_space_id"),
                 r.get("section_path"), r.get("heading"), r.get("title"), r.get("chunk_type"),
                 (canon_json(r.get("attrs")) if r.get("attrs") is not None else None), text, created))
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
    def _edges_for(self, rvid):
        parent, child = [], []
        for e in self.conn.execute("SELECT dst_ref,dst_kind,edge_kind FROM record_edges WHERE src_ref=? ORDER BY edge_kind,dst_ref", (rvid,)):
            parent.append({"edge_kind": e["edge_kind"], "dst_ref": e["dst_ref"], "dst_kind": e["dst_kind"]})
        for e in self.conn.execute("SELECT src_ref,src_kind,edge_kind FROM record_edges WHERE dst_ref=? ORDER BY edge_kind,src_ref", (rvid,)):
            child.append({"edge_kind": e["edge_kind"], "src_ref": e["src_ref"], "src_kind": e["src_kind"]})
        return parent, child

    def _record_envelope(self, row):
        parent, child = self._edges_for(row["record_version_id"])
        span = None
        if row["source_span_start"] is not None and row["source_span_end"] is not None:
            span = {"start": row["source_span_start"], "end": row["source_span_end"]}
        return {
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
            "parent_edges": parent, "child_edges": child,
        }

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
            if clauses:
                q += " WHERE " + " AND ".join(clauses)
            q += " ORDER BY record_kind, record_id, record_version_id"
            for row in self.conn.execute(q, params):
                out.append(self._record_envelope(row))
                if limit and len(out) >= limit:
                    break
        return {"count": len(out), "records": out}

    # --------------------------------------------------------------- search ----
    def search(self, query, k, mode, filters):
        filters = filters or {}
        if not query or not str(query).strip():
            raise ASError("empty_query", "search query is empty")
        if mode not in ("fts", "exact"):
            raise ASError("invalid_mode", "mode must be fts|exact (got %r)" % mode)
        corpus_version = self._get_corpus_version()
        want_status = filters.get("status") or filters.get("currentness")
        exclude_stale = bool(filters.get("exclude_stale", False))
        kind_filter = filters.get("record_kind")

        if mode == "fts":
            scored = self._search_fts(query, filters, kind_filter)
        else:
            scored = self._search_exact(query, filters, kind_filter)
        # deterministic fused order (lexical-only this wave): (-lexical_score, tie_break_key)
        scored.sort(key=lambda x: (-x["lexical_score"], x["tie_break_key"]))
        for lex_rank, s in enumerate(scored, start=1):
            s["lexical_rank"] = lex_rank
        filter_decisions = {
            "mode": mode, "record_kind": kind_filter, "source": filters.get("source"),
            "type": filters.get("type"), "path_prefix": filters.get("path_prefix"),
            "content_hash": filters.get("content_hash"), "namespace": filters.get("namespace"),
            "status": want_status, "exclude_stale": exclude_stale, "channels": ["lexical"],
        }
        selected = []
        for x in scored:
            st = x["base"].get("status")
            if want_status and st != want_status:
                continue
            if exclude_stale and st != STATUS_CURRENT:
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
            hits.append(hit)
        return {"query": query, "mode": mode, "k": k, "count": len(hits),
                "filters": filters, "corpus_version": corpus_version,
                "fusion_algo": "lexical_only", "fusion_version": "1",
                "retrieval_channels": ["lexical"], "results": hits}

    def _chunk_hit_base(self, chunk_id):
        row = self.conn.execute("SELECT * FROM v_records_source_chunk WHERE chunk_id=?", (chunk_id,)).fetchone()
        if row is None:
            return None
        d = self.conn.execute("SELECT abs_path FROM documents WHERE document_id=?", (row["document_id"],)).fetchone()
        section = row["section_path"]
        span_label = section if section else ("bytes:%d-%d" % (row["source_span_start"], row["source_span_end"]))
        return {
            "record_id": row["record_id"], "record_version_id": row["record_version_id"],
            "record_kind": "source_chunk", "chunk_id": chunk_id,
            "source_path": row["source_path"], "abs_path": (d["abs_path"] if d else None),
            # content_hash = the SOURCE VERSION identity (document/file bytes sha256) -- what provenance
            # validation checks (s4: "the content hash identifies the expected source version"). The chunk's
            # own canonical-text hash is exposed separately as chunk_content_hash.
            "content_hash": row["doc_content_hash"],
            "chunk_content_hash": row["content_hash"],
            "span": {"start": row["source_span_start"], "end": row["source_span_end"]},
            "span_label": span_label, "section_path": row["section_path"], "heading": row["heading"],
            "chunk_type": row["chunk_type"], "status": row["status"], "currentness": row["status"],
            "authority_level": row["authority_level"], "namespace": row["namespace"],
            "source": row["namespace"], "embedding_space_id": row["embedding_space_id"],
            "source_version_id": row["source_version_id"],
        }

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
        return {
            "record_id": row["record_id"], "record_version_id": rvid, "record_kind": row["record_kind"],
            "chunk_id": None, "source_path": row["source_path"], "abs_path": None,
            "content_hash": row["content_hash"], "span": span, "span_label": span_label,
            "section_path": row["section_path"], "heading": row["heading"], "chunk_type": row["chunk_type"],
            "status": row["status"], "currentness": row["status"], "authority_level": row["authority_level"],
            "namespace": row["namespace"], "source": row["namespace"],
            "embedding_space_id": row["embedding_space_id"], "source_version_id": row["source_version_id"],
        }

    def _chunk_passes(self, c, filters):
        if filters.get("source") and c["source_id"] != _slug(filters["source"]):
            return False
        if filters.get("namespace") and c["source_id"] != _slug(filters["namespace"]):
            return False
        if filters.get("type") and c["chunk_type"] != filters["type"]:
            return False
        if filters.get("content_hash") and c["content_hash"] != filters["content_hash"] and c["chunk_content_hash"] != filters["content_hash"]:
            return False
        if filters.get("path_prefix") and not c["rel_path"].startswith(norm_rel(filters["path_prefix"])):
            return False
        return True

    def _record_passes(self, r, filters):
        if filters.get("namespace") and (r["namespace"] or "") != filters["namespace"]:
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

    def _search_fts(self, query, filters, kind_filter):
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
                if c is None or not self._chunk_passes(c, filters):
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
                if rec is None or not self._record_passes(rec, filters):
                    continue
                if kind_filter is not None and rec["record_kind"] != kind_filter:
                    continue
                base = self._record_hit_base(rec["record_version_id"])
                out.append({"base": base, "lexical_score": round(-float(r["bm"]), 6),
                            "tie_break_key": base["record_version_id"],
                            "snippet": _snippet(rec["text"] or "", query, mode="fts")})
        return out

    def _search_exact(self, query, filters, kind_filter):
        q = str(query)
        ql = q.lower()
        out = []
        want_chunks = (kind_filter is None or kind_filter == "source_chunk")
        want_records = (kind_filter is None or kind_filter in TYPED_RECORD_KINDS)
        if want_chunks:
            for c in self.conn.execute("SELECT * FROM chunks ORDER BY rel_path, chunk_index, chunk_id").fetchall():
                if not self._chunk_passes(c, filters):
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
                if not self._record_passes(rec, filters):
                    continue
                if kind_filter is not None and rec["record_kind"] != kind_filter:
                    continue
                text = rec["text"] or ""
                occ = text.lower().count(ql)
                path_hit = bool(rec["source_path"]) and ql in rec["source_path"].lower()
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

        ok = all(c["ok"] for c in checks)
        return {"ok": ok, "checks": checks}

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
        for c in rows:
            if not self._chunk_passes(c, filters or {}):
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
                   "catalog_digest": cat.catalog_digest()}
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
                   "digest": cat.catalog_digest(), "counts": cat.counts()}
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
