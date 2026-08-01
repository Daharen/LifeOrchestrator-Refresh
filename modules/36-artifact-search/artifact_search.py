#!/usr/bin/env python
# artifact_search.py -- deterministic SQLite catalog + hybrid LEXICAL (FTS5) search worker
# for artifact.search (Life Orchestrator, Module 36; skill id artifact.search).
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
#   * chunk_id / document_id / version_id are content+path derived -> same inputs => same ids + order.
#   * the SQLite file itself is NOT byte-reproducible (page layout/rowids); the LOGICAL records and the
#     catalog_digest ARE (same corpus content => identical digest across runs AND machines, via
#     repo-relative paths + byte spans).
#   * search results are emitted in a fully deterministic order with a stable tie-break (chunk_id).
import sys, os, json, time, hashlib, math, re, sqlite3, fnmatch, traceback

SCHEMA_VERSION = "1"
WORKER_VERSION = "0.1.0"

PARSER_MARKDOWN = ("markdown", "1")
PARSER_TEXT = ("text", "1")

# ---- mock embedding provider (the D-0077 embedding-provider seam; lane A ships the REAL adapter) ----
MOCK_PROVIDER_ID = "mock-hash-v1"
MOCK_MODEL_ID = "mock.embedding.hashvec"
MOCK_MODEL_VERSION = "1"
# a FIXED, deterministic pseudo-sha256 identifying this mock "model" (NOT a real model file hash)
MOCK_MODEL_SHA256 = hashlib.sha256(b"artifact.search/mock-hash-v1").hexdigest()
MOCK_ENGINE_BUILD = "mock"
DEFAULT_DIM = 64

DEFAULT_MAX_FILE_BYTES = 5_000_000
DEFAULT_MAX_CHUNK_CHARS = 4000
DEFAULT_MAX_EMBED_CHARS = 100_000

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
    return "chk_" + hashlib.sha256(
        ("%s\x00%s\x00%d" % (rel_path, content_hash, chunk_index)).encode("utf-8")
    ).hexdigest()[:24]


def make_document_id(source_id, rel_path):
    return "doc_" + hashlib.sha256(("%s\x00%s" % (source_id, rel_path)).encode("utf-8")).hexdigest()[:24]


def make_version_id(document_id, content_hash):
    return "ver_" + hashlib.sha256(("%s\x00%s" % (document_id, content_hash)).encode("utf-8")).hexdigest()[:24]


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
        # cut at a blank line boundary once over target; hard-cut far past target even without a blank
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
    """The MOCK embedding-provider (D-0077 contract 1). Deterministic hashed pseudo-vectors of a fixed
    dim; vectors align 1:1 with inputs in EXACT input order (result[i] <-> input[i]); a per-input status
    lists the exceptions (skipped empties / oversize) WITH the input index. Zero-vectors keep alignment +
    dim invariant for skipped inputs. Shape matches the REAL adapter so it drops in unchanged at fold."""
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


def embed_envelope(texts, dim, normalize):
    vectors, statuses = mock_embed(texts, dim, normalize)
    return {
        "provider_id": MOCK_PROVIDER_ID,
        "model_id": MOCK_MODEL_ID,
        "model_version": MOCK_MODEL_VERSION,
        "model_sha256": MOCK_MODEL_SHA256,
        "engine_build": MOCK_ENGINE_BUILD,
        "dim": dim,
        "normalized": bool(normalize),
        "count": len(texts),
        "vectors": vectors,
        "input_status": statuses,
    }


# ------------------------------------------------------------------- catalog ----

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
  current_version_id TEXT,
  first_seen_at      TEXT,
  last_seen_at       TEXT,
  UNIQUE(source_id, rel_path)
);
CREATE TABLE IF NOT EXISTS document_versions (
  version_id    TEXT PRIMARY KEY,
  document_id   TEXT NOT NULL,
  content_hash  TEXT NOT NULL,
  size_bytes    INTEGER,
  mtime_utc     TEXT,
  parser        TEXT,
  parser_version TEXT,
  parse_status  TEXT,                         -- ok | failed
  parse_error   TEXT,
  chunk_count   INTEGER,
  is_current    INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT,
  UNIQUE(document_id, content_hash)
);
CREATE TABLE IF NOT EXISTS chunks (
  chunk_id     TEXT PRIMARY KEY,
  version_id   TEXT NOT NULL,
  document_id  TEXT NOT NULL,
  source_id    TEXT NOT NULL,
  rel_path     TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  chunk_index  INTEGER NOT NULL,
  span_start   INTEGER NOT NULL,
  span_end     INTEGER NOT NULL,
  section_path TEXT,
  heading      TEXT,
  chunk_type   TEXT,
  token_estimate INTEGER,
  text         TEXT NOT NULL,
  created_at   TEXT
);
CREATE INDEX IF NOT EXISTS idx_chunks_doc ON chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_ver ON chunks(version_id);
CREATE INDEX IF NOT EXISTS idx_chunks_rel ON chunks(rel_path);
CREATE TABLE IF NOT EXISTS chunk_embeddings (
  chunk_id      TEXT NOT NULL,
  provider_id   TEXT NOT NULL,
  dim           INTEGER NOT NULL,
  normalized    INTEGER NOT NULL,
  model_id      TEXT,
  model_version TEXT,
  model_sha256  TEXT,
  engine_build  TEXT,
  vector        TEXT NOT NULL,                -- json array of floats
  created_at    TEXT,
  PRIMARY KEY (chunk_id, provider_id)
);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  text, heading, section_path, rel_path UNINDEXED, chunk_id UNINDEXED,
  tokenize = 'unicode61'
);
CREATE TABLE IF NOT EXISTS ingest_runs (
  run_id       TEXT PRIMARY KEY,
  source_id    TEXT,
  started_at   TEXT,
  finished_at  TEXT,
  added        INTEGER, changed INTEGER, deleted INTEGER, unchanged INTEGER,
  parse_failures INTEGER, moved INTEGER,
  file_budget_hit INTEGER
);
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
        # confirm FTS5 is actually compiled in (fail-closed, surfaced clearly)
        try:
            self.conn.execute("CREATE VIRTUAL TABLE IF NOT EXISTS _fts_probe USING fts5(x)")
            self.conn.execute("DROP TABLE IF EXISTS _fts_probe")
        except sqlite3.OperationalError as e:
            raise ASError("fts5_unavailable", "SQLite FTS5 is not available in this python's sqlite3: %r" % (e,))
        self.conn.executescript(SCHEMA_SQL)
        cur = self.conn.execute("SELECT value FROM catalog_meta WHERE key='schema_version'")
        row = cur.fetchone()
        if row is None:
            self.conn.execute("INSERT INTO catalog_meta(key,value) VALUES('schema_version',?)", (SCHEMA_VERSION,))
            self.conn.execute("INSERT OR REPLACE INTO catalog_meta(key,value) VALUES('created_at',?)", (now_utc(),))
            self.conn.commit()

    def close(self):
        try:
            self.conn.close()
        except Exception:
            pass

    # ---- deletion of a version's derived rows (chunks + fts + embeddings) ----
    def _purge_version_derived(self, version_id):
        rows = self.conn.execute("SELECT chunk_id FROM chunks WHERE version_id=?", (version_id,)).fetchall()
        for r in rows:
            self.conn.execute("DELETE FROM chunks_fts WHERE chunk_id=?", (r["chunk_id"],))
            self.conn.execute("DELETE FROM chunk_embeddings WHERE chunk_id=?", (r["chunk_id"],))
        self.conn.execute("DELETE FROM chunks WHERE version_id=?", (version_id,))

    def _insert_chunks(self, doc, version_id, content_hash, chunks, embed_provider, dim, normalize, created):
        rel = doc["rel_path"]
        texts_for_embed = []
        chunk_ids = []
        for ch in chunks:
            cid = make_chunk_id(rel, content_hash, ch["chunk_index"])
            token_est = max(1, len(ch["text"]) // 4)
            self.conn.execute(
                """INSERT INTO chunks(chunk_id,version_id,document_id,source_id,rel_path,content_hash,
                   chunk_index,span_start,span_end,section_path,heading,chunk_type,token_estimate,text,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (cid, version_id, doc["document_id"], doc["source_id"], rel, content_hash,
                 ch["chunk_index"], ch["span_start"], ch["span_end"], ch["section_path"], ch["heading"],
                 ch["chunk_type"], token_est, ch["text"], created))
            self.conn.execute(
                "INSERT INTO chunks_fts(text,heading,section_path,rel_path,chunk_id) VALUES(?,?,?,?,?)",
                (ch["text"], ch["heading"] or "", ch["section_path"] or "", rel, cid))
            texts_for_embed.append(ch["text"])
            chunk_ids.append(cid)
        if embed_provider == "mock" and chunk_ids:
            vectors, _ = mock_embed(texts_for_embed, dim, normalize)
            for cid, vec in zip(chunk_ids, vectors):
                self.conn.execute(
                    """INSERT OR REPLACE INTO chunk_embeddings(chunk_id,provider_id,dim,normalized,
                       model_id,model_version,model_sha256,engine_build,vector,created_at)
                       VALUES(?,?,?,?,?,?,?,?,?,?)""",
                    (cid, MOCK_PROVIDER_ID, dim, 1 if normalize else 0,
                     MOCK_MODEL_ID, MOCK_MODEL_VERSION, MOCK_MODEL_SHA256, MOCK_ENGINE_BUILD,
                     json.dumps(vec, separators=(",", ":")), created))

    def ingest(self, label, root, include_globs, exclude_dirs, exclude_globs,
               max_files, max_file_bytes, max_chunk_chars, embed_provider, dim, normalize):
        if not root or not os.path.isdir(root):
            raise ASError("root_not_found", "ingest root is not a directory: %s" % root)
        source_id = _slug(label) if label else _slug(os.path.basename(os.path.abspath(root)) or "root")
        root_abs = os.path.abspath(root)
        created = now_utc()

        src = self.conn.execute("SELECT * FROM sources WHERE source_id=?", (source_id,)).fetchone()
        if src is None:
            self.conn.execute("INSERT INTO sources(source_id,label,root_path,created_at,last_ingest_at) VALUES(?,?,?,?,?)",
                              (source_id, label or source_id, root_abs, created, created))
        else:
            self.conn.execute("UPDATE sources SET root_path=?, last_ingest_at=? WHERE source_id=?",
                              (root_abs, created, source_id))

        # ---- inventory walk (deterministic order) ----
        seen = []  # (rel_path, abs_path)
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
        added, changed, unchanged, parse_failures = [], [], [], []

        for rel, ap in seen:
            try:
                with open(ap, "rb") as fh:
                    raw = fh.read()
            except Exception as e:
                parse_failures.append({"rel_path": rel, "reason": "read_error", "detail": repr(e)[:200]})
                self._record_document(source_id, rel, ap, created, raw=b"", content_hash="",
                                      size=0, parse_status="failed", parse_error="read_error: %r" % (e,),
                                      parser="unknown", parser_version="0", chunks=[], src_type="unknown",
                                      embed_provider=embed_provider, dim=dim, normalize=normalize)
                continue
            content_hash = sha256_hex(raw)
            doc = self.conn.execute("SELECT * FROM documents WHERE source_id=? AND rel_path=?",
                                    (source_id, rel)).fetchone()
            if doc is not None and doc["status"] == "active" and doc["current_version_id"]:
                cv = self.conn.execute("SELECT content_hash FROM document_versions WHERE version_id=?",
                                       (doc["current_version_id"],)).fetchone()
                if cv is not None and cv["content_hash"] == content_hash:
                    self.conn.execute("UPDATE documents SET last_seen_at=? WHERE document_id=?", (created, doc["document_id"]))
                    unchanged.append(rel)
                    continue

            # parse + chunk (or record a parse failure, surfaced)
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
            self._record_document(source_id, rel, ap, created, raw=raw, content_hash=content_hash,
                                  size=len(raw), parse_status=parse_status, parse_error=parse_error,
                                  parser=parser, parser_version=parser_ver, chunks=chunks, src_type=src_type,
                                  embed_provider=embed_provider, dim=dim, normalize=normalize)
            (added if is_new else changed).append(rel)

        # ---- reconcile deletions ----
        deleted = []
        active_docs = self.conn.execute("SELECT * FROM documents WHERE source_id=? AND status='active'",
                                        (source_id,)).fetchall()
        for d in active_docs:
            if d["rel_path"] not in seen_rel:
                if d["current_version_id"]:
                    self._purge_version_derived(d["current_version_id"])
                    self.conn.execute("UPDATE document_versions SET is_current=0 WHERE document_id=?", (d["document_id"],))
                self.conn.execute("UPDATE documents SET status='deleted', current_version_id=NULL, last_seen_at=? WHERE document_id=?",
                                  (created, d["document_id"]))
                deleted.append(d["rel_path"])

        # ---- moved detection (report-only): a deleted path's content reappears at a new added path ----
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
                d = self.conn.execute("SELECT current_version_id FROM documents WHERE source_id=? AND rel_path=?",
                                      (source_id, rel)).fetchone()
                if d and d["current_version_id"]:
                    v = self.conn.execute("SELECT content_hash FROM document_versions WHERE version_id=?",
                                          (d["current_version_id"],)).fetchone()
                    if v and v["content_hash"] in del_hash and del_hash[v["content_hash"]]:
                        moved.append({"from": del_hash[v["content_hash"]].pop(0), "to": rel})

        run_id = "run_" + sha256_text("%s\x00%s\x00%d\x00%d\x00%d" %
                                      (source_id, created, len(added), len(changed), len(deleted)))[:16]
        self.conn.execute(
            """INSERT OR REPLACE INTO ingest_runs(run_id,source_id,started_at,finished_at,added,changed,
               deleted,unchanged,parse_failures,moved,file_budget_hit) VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
            (run_id, source_id, created, now_utc(), len(added), len(changed), len(deleted),
             len(unchanged), len(parse_failures), len(moved), 1 if budget_hit else 0))
        self.conn.commit()

        return {
            "source_id": source_id, "root": root_abs, "run_id": run_id,
            "counts": {"seen": len(seen), "added": len(added), "changed": len(changed),
                       "deleted": len(deleted), "unchanged": len(unchanged),
                       "parse_failures": len(parse_failures), "moved": len(moved)},
            "added": sorted(added), "changed": sorted(changed), "deleted": sorted(deleted),
            "moved": moved, "parse_failures": parse_failures,
            "file_budget_hit": budget_hit,
            "embed_provider": embed_provider, "dim": dim, "normalized": bool(normalize),
        }

    def _record_document(self, source_id, rel, ap, created, raw, content_hash, size, parse_status,
                         parse_error, parser, parser_version, chunks, src_type, embed_provider, dim, normalize):
        ext = os.path.splitext(rel)[1].lower()
        doc = self.conn.execute("SELECT * FROM documents WHERE source_id=? AND rel_path=?", (source_id, rel)).fetchone()
        document_id = make_document_id(source_id, rel)
        if doc is None:
            self.conn.execute(
                """INSERT INTO documents(document_id,source_id,rel_path,abs_path,ext,source_type,status,
                   current_version_id,first_seen_at,last_seen_at) VALUES(?,?,?,?,?,?,?,?,?,?)""",
                (document_id, source_id, rel, ap, ext, src_type, "active", None, created, created))
        else:
            document_id = doc["document_id"]
            # a previously-deleted (or changed) doc: purge the OLD current version's derived rows
            if doc["current_version_id"]:
                self._purge_version_derived(doc["current_version_id"])
                self.conn.execute("UPDATE document_versions SET is_current=0 WHERE document_id=?", (document_id,))
            self.conn.execute("UPDATE documents SET abs_path=?, ext=?, source_type=?, status='active', last_seen_at=? WHERE document_id=?",
                              (ap, ext, src_type, created, document_id))

        version_id = make_version_id(document_id, content_hash) if content_hash else \
            ("ver_" + sha256_text(document_id + "\x00noread\x00" + created)[:24])
        existing_v = self.conn.execute("SELECT version_id FROM document_versions WHERE version_id=?", (version_id,)).fetchone()
        if existing_v is not None:
            # same content seen before (e.g. a revert): purge + rebuild its derived rows deterministically
            self._purge_version_derived(version_id)
            self.conn.execute(
                """UPDATE document_versions SET size_bytes=?,parser=?,parser_version=?,parse_status=?,
                   parse_error=?,chunk_count=?,is_current=1,created_at=? WHERE version_id=?""",
                (size, parser, parser_version, parse_status, parse_error, len(chunks), created, version_id))
        else:
            self.conn.execute(
                """INSERT INTO document_versions(version_id,document_id,content_hash,size_bytes,mtime_utc,
                   parser,parser_version,parse_status,parse_error,chunk_count,is_current,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,1,?)""",
                (version_id, document_id, content_hash, size, created, parser, parser_version,
                 parse_status, parse_error, len(chunks), created))
        self.conn.execute("UPDATE documents SET current_version_id=? WHERE document_id=?", (version_id, document_id))
        if parse_status == "ok" and chunks:
            docrow = {"document_id": document_id, "source_id": source_id, "rel_path": rel}
            self._insert_chunks(docrow, version_id, content_hash, chunks, embed_provider, dim, normalize, created)

    # --------------------------------------------------------------- search ----
    def search(self, query, k, mode, filters):
        filters = filters or {}
        if not query or not str(query).strip():
            raise ASError("empty_query", "search query is empty")
        if mode not in ("fts", "exact"):
            raise ASError("invalid_mode", "mode must be fts|exact (got %r)" % mode)
        if mode == "fts":
            rows = self._search_fts(query, filters)
        else:
            rows = self._search_exact(query, filters)
        results = []
        for rank, r in enumerate(rows[:k], start=1):
            item = self._provenance(r["chunk_id"])
            if item is None:
                continue
            item["score"] = r["score"]
            item["snippet"] = r["snippet"]
            item["rank"] = rank
            results.append(item)
        return {"query": query, "mode": mode, "k": k, "count": len(results),
                "filters": filters, "results": results}

    def _filter_clause(self, filters, alias="c"):
        clauses, params = [], []
        if filters.get("source"):
            clauses.append("%s.source_id=?" % alias); params.append(_slug(filters["source"]))
        if filters.get("type"):
            clauses.append("%s.chunk_type=?" % alias); params.append(filters["type"])
        if filters.get("content_hash"):
            clauses.append("%s.content_hash=?" % alias); params.append(filters["content_hash"])
        if filters.get("path_prefix"):
            clauses.append("%s.rel_path LIKE ?" % alias); params.append(norm_rel(filters["path_prefix"]) + "%")
        return clauses, params

    def _search_fts(self, query, filters):
        match = _fts_query(query)
        if not match:
            return []
        base = ("SELECT f.chunk_id AS chunk_id, bm25(chunks_fts) AS bm "
                "FROM chunks_fts f WHERE chunks_fts MATCH ?")
        rows = self.conn.execute(base, (match,)).fetchall()
        fclauses, fparams = self._filter_clause(filters, "c")
        out = []
        for r in rows:
            c = self.conn.execute("SELECT * FROM chunks WHERE chunk_id=?", (r["chunk_id"],)).fetchone()
            if c is None:
                continue
            if not self._passes_filters(c, filters):
                continue
            score = round(-float(r["bm"]), 6)  # SQLite bm25: lower(more negative)=better -> negate so higher=better
            out.append({"chunk_id": c["chunk_id"], "score": score, "snippet": _snippet(c["text"], query, mode="fts")})
        out.sort(key=lambda x: (-x["score"], x["chunk_id"]))
        return out

    def _search_exact(self, query, filters):
        q = str(query)
        ql = q.lower()
        rows = self.conn.execute("SELECT * FROM chunks ORDER BY rel_path, chunk_index, chunk_id").fetchall()
        out = []
        for c in rows:
            if not self._passes_filters(c, filters):
                continue
            text = c["text"]
            occ = text.lower().count(ql)
            path_hit = ql in c["rel_path"].lower()
            if occ == 0 and not path_hit:
                continue
            score = float(occ) + (100.0 if path_hit else 0.0)  # filename hits rank first, deterministically
            out.append({"chunk_id": c["chunk_id"], "score": score,
                        "snippet": _snippet(text, q, mode="exact"), "rel_path": c["rel_path"],
                        "chunk_index": c["chunk_index"]})
        out.sort(key=lambda x: (-x["score"], x["rel_path"], x["chunk_index"], x["chunk_id"]))
        for x in out:
            x.pop("rel_path", None); x.pop("chunk_index", None)
        return out

    def _passes_filters(self, c, filters):
        if filters.get("source") and c["source_id"] != _slug(filters["source"]):
            return False
        if filters.get("type") and c["chunk_type"] != filters["type"]:
            return False
        if filters.get("content_hash") and c["content_hash"] != filters["content_hash"]:
            return False
        if filters.get("path_prefix") and not c["rel_path"].startswith(norm_rel(filters["path_prefix"])):
            return False
        return True

    def _provenance(self, chunk_id):
        c = self.conn.execute("SELECT * FROM chunks WHERE chunk_id=?", (chunk_id,)).fetchone()
        if c is None:
            return None
        d = self.conn.execute("SELECT abs_path FROM documents WHERE document_id=?", (c["document_id"],)).fetchone()
        return {
            "source_path": c["rel_path"],
            "abs_path": (d["abs_path"] if d else None),
            "content_hash": c["content_hash"],
            "chunk_id": c["chunk_id"],
            "span": {"start": c["span_start"], "end": c["span_end"]},
            "section_path": c["section_path"],
            "heading": c["heading"],
            "chunk_type": c["chunk_type"],
            "source": c["source_id"],
        }

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

        dup_pos = self.conn.execute(
            "SELECT COUNT(*) n FROM (SELECT version_id,chunk_index,COUNT(*) c FROM chunks "
            "GROUP BY version_id,chunk_index HAVING c>1)").fetchone()["n"]
        add("no_duplicate_chunk_positions", dup_pos == 0, "%d duplicate (version_id,chunk_index)" % dup_pos)

        orphan_chunks = self.conn.execute(
            "SELECT COUNT(*) n FROM chunks c LEFT JOIN document_versions v ON c.version_id=v.version_id "
            "WHERE v.version_id IS NULL").fetchone()["n"]
        add("no_orphan_chunks", orphan_chunks == 0, "%d orphan chunks" % orphan_chunks)

        orphan_emb = self.conn.execute(
            "SELECT COUNT(*) n FROM chunk_embeddings e LEFT JOIN chunks c ON e.chunk_id=c.chunk_id "
            "WHERE c.chunk_id IS NULL").fetchone()["n"]
        add("no_orphan_embeddings", orphan_emb == 0, "%d orphan embeddings" % orphan_emb)

        fts_n = self.conn.execute("SELECT COUNT(*) n FROM chunks_fts").fetchone()["n"]
        add("fts_row_count_equals_chunks", fts_n == total, "fts=%d chunks=%d" % (fts_n, total))

        stale = self.conn.execute(
            "SELECT COUNT(*) n FROM chunks c JOIN document_versions v ON c.version_id=v.version_id "
            "WHERE v.is_current=0").fetchone()["n"]
        add("no_chunks_on_noncurrent_versions", stale == 0, "%d chunks on is_current=0" % stale)

        deleted_chunks = self.conn.execute(
            "SELECT COUNT(*) n FROM chunks c JOIN documents d ON c.document_id=d.document_id "
            "WHERE d.status='deleted'").fetchone()["n"]
        add("no_chunks_on_deleted_documents", deleted_chunks == 0, "%d chunks on deleted docs" % deleted_chunks)

        bad_dim = self.conn.execute(
            "SELECT COUNT(*) n FROM chunk_embeddings WHERE provider_id IS NULL OR dim IS NULL OR dim<=0").fetchone()["n"]
        add("embeddings_have_provider_and_dim", bad_dim == 0, "%d bad embedding rows" % bad_dim)

        ok = all(c["ok"] for c in checks)
        return {"ok": ok, "checks": checks}

    # -------------------------------------------------------- catalog digest ----
    def catalog_digest(self):
        rows = []
        for c in self.conn.execute(
                "SELECT rel_path,content_hash,chunk_index,span_start,span_end,chunk_id "
                "FROM chunks ORDER BY rel_path,chunk_index,chunk_id"):
            rows.append("CHK\t%s\t%s\t%d\t%d\t%d\t%s" %
                        (c["rel_path"], c["content_hash"], c["chunk_index"], c["span_start"], c["span_end"], c["chunk_id"]))
        for d in self.conn.execute(
                "SELECT rel_path,status,current_version_id FROM documents ORDER BY rel_path"):
            chash = ""
            if d["current_version_id"]:
                v = self.conn.execute("SELECT content_hash,parse_status FROM document_versions WHERE version_id=?",
                                      (d["current_version_id"],)).fetchone()
                if v:
                    chash = "%s|%s" % (v["content_hash"], v["parse_status"])
            rows.append("DOC\t%s\t%s\t%s" % (d["rel_path"], d["status"], chash))
        digest = sha256_text("\n".join(rows))
        return digest

    def counts(self):
        def n(sql):
            return self.conn.execute(sql).fetchone()[0]
        return {
            "sources": n("SELECT COUNT(*) FROM sources"),
            "documents_active": n("SELECT COUNT(*) FROM documents WHERE status='active'"),
            "documents_deleted": n("SELECT COUNT(*) FROM documents WHERE status='deleted'"),
            "versions": n("SELECT COUNT(*) FROM document_versions"),
            "chunks": n("SELECT COUNT(*) FROM chunks"),
            "embeddings": n("SELECT COUNT(*) FROM chunk_embeddings"),
            "parse_failures_current": n(
                "SELECT COUNT(*) FROM documents d JOIN document_versions v ON d.current_version_id=v.version_id "
                "WHERE v.parse_status='failed'"),
        }

    # ------------------------------------------------ export / store (fold) ----
    def export_chunk_texts(self, filters, limit):
        fclauses, _ = [], []
        rows = self.conn.execute(
            "SELECT chunk_id,rel_path,content_hash,chunk_index,span_start,span_end,text "
            "FROM chunks ORDER BY rel_path,chunk_index,chunk_id").fetchall()
        out = []
        for c in rows:
            if not self._passes_filters(c, filters or {}):
                continue
            out.append({"chunk_id": c["chunk_id"], "rel_path": c["rel_path"],
                        "content_hash": c["content_hash"],
                        "span": {"start": c["span_start"], "end": c["span_end"]},
                        "text": c["text"]})
            if limit and len(out) >= limit:
                break
        return {"count": len(out), "chunks": out}

    def store_embeddings(self, chunk_ids, vectors, provider_id, dim, normalized,
                         model_id, model_version, model_sha256, engine_build):
        if len(chunk_ids) != len(vectors):
            raise ASError("length_mismatch", "chunk_ids (%d) and vectors (%d) differ" % (len(chunk_ids), len(vectors)))
        created = now_utc()
        stored, skipped = 0, 0
        for cid, vec in zip(chunk_ids, vectors):
            c = self.conn.execute("SELECT chunk_id FROM chunks WHERE chunk_id=?", (cid,)).fetchone()
            if c is None:
                skipped += 1
                continue
            if dim and len(vec) != dim:
                raise ASError("dim_mismatch", "vector for %s has len %d != dim %d" % (cid, len(vec), dim))
            self.conn.execute(
                """INSERT OR REPLACE INTO chunk_embeddings(chunk_id,provider_id,dim,normalized,
                   model_id,model_version,model_sha256,engine_build,vector,created_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?)""",
                (cid, provider_id, dim, 1 if normalized else 0, model_id, model_version,
                 model_sha256, engine_build, json.dumps(vec, separators=(",", ":")), created))
            stored += 1
        self.conn.commit()
        return {"stored": stored, "requested": len(chunk_ids),
                "skipped_unknown_chunk": skipped, "provider_id": provider_id, "dim": dim}


def _slug(s):
    s = str(s).strip().lower()
    s = re.sub(r"[^a-z0-9._-]+", "-", s)
    return s.strip("-") or "src"


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
    # Sanitize arbitrary user text into a valid FTS5 MATCH string: extract word tokens, AND them
    # (space-joined = implicit AND in FTS5). Deterministic; avoids FTS5 syntax errors from raw input.
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


# ------------------------------------------------------------------- driver ----

def run(args):
    op = str(args.get("op", "")).lower()
    db_path = args.get("db")
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

    # embed op needs no db
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
            )
            integ = cat.integrity()
            digest = cat.catalog_digest()
            res["integrity_ok"] = integ["ok"]
            res["catalog_digest"] = digest
            res["counts_total"] = cat.counts()
            res["db"] = os.path.abspath(db_path)
            if res["file_budget_hit"]:
                out["warnings"].append("file budget hit: only the first %s files indexed" % args.get("max_files"))
            if res["counts"]["parse_failures"] > 0:
                out["warnings"].append("%d parse failure(s) surfaced (see ingest_report.parse_failures)" % res["counts"]["parse_failures"])
            if not integ["ok"]:
                out["warnings"].append("integrity check FAILED (see integrity in ingest_report)")
            res["integrity"] = integ
            out["result"] = res
            art("ingest_report.json", res, "json")
            art("catalog_digest.txt", digest + "\n", "text")

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
            res["counts"] = cat.counts()
            out["result"] = res
            if not res["ok"]:
                out["warnings"].append("integrity check FAILED")
            art("integrity.json", res, "json")

        elif op == "catalog":
            res = {"db": os.path.abspath(db_path), "digest": cat.catalog_digest(), "counts": cat.counts()}
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
            )
            out["result"] = res

        else:
            raise ASError("invalid_op", "unknown op %r (ingest|search|embed|integrity|catalog|export-chunk-texts|store-embeddings)" % op)
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
