#!/usr/bin/env python3
# retrieval_eval.py -- deterministic core of the retrieval-evaluation harness (Life Orchestrator
# module 37 `retrieval.eval`, contract v0.2, eval-0.2 gates, plan fo-29-87dbfa0b, RETRIEVAL-QUALITY-i29).
#
# WHAT THIS IS
#   A benchmark runner that measures the quality of ANY retriever satisfying the MEMORY_CONTRACT s3
#   retriever-0.2 interface (op `search`; inputs {query, k, filters?}; result = a ranked hit array in
#   DETERMINISTIC order; hit = the s3 shape -- span OBJECT {start,end} + span_label, record_id/
#   record_version_id/record_kind, content_hash (SOURCE VERSION identity), status/currentness +
#   authority_level, and PER-CHANNEL diagnostics: retrieval_channels, lexical_rank+lexical_score,
#   vector_rank+vector_similarity [null until vectors], fused_rank+fused_score, fusion_algo+fusion_version,
#   embedding_space_id, index_snapshot/corpus_version, filter_decisions, tie_break_key). The retriever-0.1
#   hit shape ({source_path, content_hash, chunk_id, span-string, score, snippet}) is STILL accepted
#   (compat/migration), so the shipped 0.1 benchmark stays regression-green.
#
#   eval-0.2 (MEMORY_CONTRACT s6) adds over the shipped 0.1 (recall@K / MRR / stale-source /
#   provenance-presence + forbidden-hit rate):
#     * a richer LABEL schema: must_include_all / must_include_any evidence groups, required version/span,
#       acceptable-equivalent spans, explicitly-stale versions, forbidden_sources, hard privacy exclusions,
#       distractors, no_answer_expected, label rationale/status/reviewer, corpus snapshot. A FILE-level hit
#       is NOT credit (a wrong chunk from the right file must not score -- chunk/span level matching).
#     * TEMPORAL INTENT per query (current_only | historical_as_of | version_specific | any_valid_version);
#       "a stale required source is always a miss" holds ONLY for current_only.
#     * METRICS ADDED: precision@K, nDCG@K, evidence-group coverage, forbidden-hit rate, stale-hit rate,
#       duplicate/near-dup burden, source diversity, provenance VALIDITY, snippet-span correctness,
#       relevant-tokens / total-retrieved-tokens, no-answer false-positive rate, hybrid uplift + regression.
#     * NEGATIVES / ABSTENTION cases (answer absent; only-stale; attractive-but-wrong; a forbidden personal
#       source is the best lexical match; duplicates; exact-error-text; paraphrase; disagreeing sources;
#       explicit historical intent).
#     * HYBRID ATTRIBUTION from the retriever-0.2 per-channel diagnostics (lexical-only / vector-only /
#       hybrid): unique-to-channel, required rescued by vectors, lexical exact-match harmed by fusion,
#       stale/forbidden introduced by a channel, fusion contribution. The vector channel runs EMPTY today
#       (no vectors) -- reported cleanly, never blocking.
#     * PROVENANCE VALIDATION (not presence): for every scored hit verify content_hash identifies the
#       expected source version; the source exists or has an explicit tombstone; the span is in bounds;
#       reading the span reproduces the cited text; the snippet derives from that span; the parser+chunker
#       fingerprint is known; current/stale status is correct.
#     * a DETERMINISTIC RERANKER (directive 8.3 / skill-activation Stage 4): retriever-0.2 hit array +
#       task/query descriptor -> the SAME hit-array shape reordered by deterministic features (direct
#       relevance, authority, freshness/currentness, project/component match, task-stage match, failure
#       likelihood, procedural applicability) + DIVERSITY (dedup + source diversity). The harness MEASURES
#       it: rerank uplift/regression vs the raw retriever order (nDCG@K, precision@K, evidence-group
#       coverage, forbidden/stale-hit rate) + per-query rescue/demote. NO model.
#
# DETERMINISM DISCIPLINE (a re-run -- same corpus+queries+retriever -- is byte-identical, cross-machine):
#   * content_hash is EOL-NORMALIZED (sha256 of UTF-8 text, CRLF/CR -> LF, BOM stripped) so a CRLF (Windows)
#     vs LF (cloud) checkout hashes identically.
#   * canonical JSON: sort_keys, ensure_ascii, compact separators, one trailing LF, UTF-8 no BOM.
#   * NO floats in the canonical output. Scores round to integer MILLIONTHS; every ratio metric is an
#     integer PPM (parts-per-million), integer round-half-up. nDCG uses a fixed millionths log2 discount
#     table (computed once) and the ratio rounds to ppm -- the same cross-env byte-identity gate that pins
#     the BM25 baseline covers it.
#   * NO volatile fields in either report (no timestamps / invocation ids / absolute paths / host / wall
#     clock / latency). Query latency + resource are measured into the SEPARATE volatile worker-summary.json
#     envelope, never the canonical report (s6 asks for latency; determinism forbids it in report.json).
#
# INVOCATION (by the pwsh entrypoint; also runnable directly):
#   python3 retrieval_eval.py --request <request.json>
#   request = { benchmark, base_dir?, corpus_dir?, provenance_corpus_dir?, retriever?, k_values?,
#               retrieval_depth?, out_dir, python? }
#   corpus_dir / provenance_corpus_dir (0.2): the validation corpus for PROVENANCE VALIDATION (the
#   source-of-truth files hits are validated against). Defaults to the lexical baseline's corpus_dir /
#   benchmark.corpus_dir. Writes out_dir/{report.json, report.md, worker-summary.json}.

import sys
import os
import re
import json
import math
import hashlib
import argparse
import subprocess
import time

# The ONE selection-policy library (CONTEXT_PACKET_CONTRACT s4, P1-1) -- OWNED here, CONSUMED by #40 and by
# this harness's own A/B. Self-contained (stdlib only) so #40 can load it by a resolved path.
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
from lib import selpol_rrf_v1 as selpol  # noqa: E402

GENERATOR_NAME = "retrieval.eval"
GENERATOR_VERSION = "0.5.0"
REPORT_SCHEMA = "lifeorch.retrieval_eval_report/0.5"
BENCHMARK_SCHEMA = "lifeorch.retrieval_benchmark/0.2"
BENCHMARK_SCHEMA_V1 = "lifeorch.retrieval_benchmark/0.1"
SELECTION_POLICY_ID = selpol.POLICY_ID
SELECTION_POLICY_VERSION = selpol.POLICY_VERSION
SCORE_UNIT = "millionths"
RATIO_UNIT = "ppm"
PPM = 1000000
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_TOKEN_RE = re.compile(r"[a-z0-9]+")

TEMPORAL_INTENTS = ("current_only", "historical_as_of", "version_specific", "any_valid_version")
# MEMORY_CONTRACT s5 staleness enum (the healthy baseline is `current`; A5/i33 adds the literal `superseded`).
STALE_STATUSES = frozenset([
    "source_stale", "derivation_stale", "embedding_stale", "relationship_stale",
    "summary_stale", "authority_stale", "temporal_expiry", "superseded", "deleted", "unverified",
])
STATUS_ENUM = frozenset(["current"]) | STALE_STATUSES

# A small, FIXED English stopword set for the lexical baseline (BM25-lite). Deterministic + documented in
# SCHEMA_NOTES.md; kept minimal so a real lexical signal (filenames, symbols, terminology) survives.
STOPWORDS = frozenset([
    "a", "an", "and", "are", "as", "at", "be", "been", "before", "but", "by", "can", "do", "does",
    "each", "for", "from", "had", "has", "have", "how", "i", "if", "in", "into", "is", "it", "its",
    "may", "must", "not", "of", "on", "once", "one", "or", "so", "some", "than", "that", "the",
    "their", "then", "there", "these", "this", "to", "up", "was", "we", "what", "when", "which",
    "who", "will", "with", "you", "your",
])


def log(msg):
    sys.stderr.write("[retrieval.eval] " + str(msg) + "\n")


# ------------------------------------------------------------------ determinism helpers

def canon_bytes(obj):
    """Canonical JSON bytes: sorted keys, compact, ensure_ascii, one trailing LF, UTF-8 no BOM."""
    s = json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
    return (s + "\n").encode("utf-8")


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


def normalized_text(raw_bytes):
    """Decode UTF-8, strip a leading BOM, normalize CRLF/CR -> LF."""
    t = raw_bytes.decode("utf-8")
    if t and t[0] == "﻿":
        t = t[1:]
    return t.replace("\r\n", "\n").replace("\r", "\n")


def content_hash_of_text(text):
    return "sha256:" + sha256_hex(text.encode("utf-8"))


def ppm(numer, denom):
    """Integer parts-per-million with round-half-up. denom<=0 -> 0. No float."""
    if denom <= 0:
        return 0
    return (numer * PPM + denom // 2) // denom


def mean_ppm(values):
    """Round-half-up integer mean of a list of ppm integers. Empty -> 0."""
    n = len(values)
    if n == 0:
        return 0
    total = sum(values)
    if total < 0:
        return -(((-total) + n // 2) // n)
    return (total + n // 2) // n


def score_to_millionths(x):
    """Round a non-negative float score to integer millionths, round-half-up."""
    if x <= 0:
        return 0
    return int(math.floor(x * 1000000.0 + 0.5))


# nDCG discount: gain_i / log2(i+1). Precompute log2(i+1) in integer millionths ONCE (round-half-up) so
# nDCG uses a fixed, module-level integer table; the ratio DCG/IDCG then rounds to ppm. i is 1-based rank.
_MAX_DISCOUNT = 4096
_LOG2_MILLIONTHS = [0] * (_MAX_DISCOUNT + 2)
for _i in range(1, _MAX_DISCOUNT + 2):
    _LOG2_MILLIONTHS[_i] = int(math.floor(math.log2(_i + 1) * 1000000.0 + 0.5))


def _discount_millionths(rank_1based):
    if rank_1based < 1:
        rank_1based = 1
    if rank_1based <= _MAX_DISCOUNT:
        return _LOG2_MILLIONTHS[rank_1based]
    return int(math.floor(math.log2(rank_1based + 1) * 1000000.0 + 0.5))


def tokenize(text):
    return _TOKEN_RE.findall(text.lower())


def content_tokens(text):
    """Lexical tokens with stopwords removed -- the terms the baseline indexes and queries on."""
    return [t for t in _TOKEN_RE.findall(text.lower()) if t not in STOPWORDS]


def norm_path(p):
    p = str(p).replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p


def snippet_of(text, limit=160):
    s = re.sub(r"\s+", " ", text).strip()
    return s[:limit]


def collapse_ws(s):
    return re.sub(r"\s+", " ", s).strip()


# ------------------------------------------------------------------ provenance corpus (validation source)

class ProvenanceCorpus:
    """The source-of-truth files a hit is VALIDATED against (s6 provenance validation). Loaded from a
    corpus_dir when available. content_hash is EOL-normalized; spans are byte offsets into the UTF-8 bytes
    of the EOL-normalized text (matching the retriever-0.2 byte-span contract)."""

    def __init__(self, corpus_dir, include_suffixes=None, exclude_dir_names=None):
        self.available = False
        self.files = {}  # rel -> {"text","data","content_hash","nbytes"}
        if not corpus_dir or not os.path.isdir(corpus_dir):
            return
        inc = set(s.lower() for s in include_suffixes) if include_suffixes else None
        exc = set(exclude_dir_names or [])
        for rel, full, suffix in _iter_corpus_files(corpus_dir, inc, exc):
            with open(full, "rb") as fh:
                text = normalized_text(fh.read())
            data = text.encode("utf-8")
            self.files[rel] = {
                "text": text,
                "data": data,
                "content_hash": content_hash_of_text(text),
                "nbytes": len(data),
            }
        self.available = True

    def has(self, rel):
        return norm_path(rel) in self.files

    def content_hash(self, rel):
        f = self.files.get(norm_path(rel))
        return f["content_hash"] if f else None

    def span_text(self, rel, start, end):
        f = self.files.get(norm_path(rel))
        if not f:
            return None
        n = f["nbytes"]
        if start is None or end is None:
            return None
        if not (0 <= start <= end <= n):
            return None
        try:
            return f["data"][start:end].decode("utf-8")
        except Exception:
            return None


# ------------------------------------------------------------------ lexical baseline retriever (0.2 hits)

class Chunk:
    __slots__ = ("source_path", "content_hash", "chunk_id", "span_label", "span_start", "span_end",
                 "text", "tokens", "tf", "length", "chunk_content_hash", "section_path", "heading")

    def __init__(self, source_path, content_hash, chunk_id, span_label, span_start, span_end, text,
                 section_path=None, heading=None):
        self.source_path = source_path
        self.content_hash = content_hash
        self.chunk_id = chunk_id
        self.span_label = span_label
        self.span_start = span_start
        self.span_end = span_end
        self.text = text
        self.section_path = section_path if section_path is not None else span_label
        self.heading = heading if heading is not None else span_label
        self.tokens = content_tokens(text)
        self.length = len(self.tokens)
        self.chunk_content_hash = "sha256:" + sha256_hex(text.encode("utf-8"))
        tf = {}
        for t in self.tokens:
            tf[t] = tf.get(t, 0) + 1
        self.tf = tf


def _iter_corpus_files(corpus_dir, include_suffixes, exclude_dir_names):
    out = []
    for root, dirs, files in os.walk(corpus_dir):
        dirs[:] = sorted(d for d in dirs if d not in exclude_dir_names)
        for fn in sorted(files):
            full = os.path.join(root, fn)
            rel = norm_path(os.path.relpath(full, corpus_dir))
            suffix = os.path.splitext(fn)[1].lower()
            if include_suffixes and suffix not in include_suffixes:
                continue
            out.append((rel, full, suffix))
    out.sort(key=lambda x: x[0])
    return out


def _line_byte_offsets(text):
    """Byte offset of the start of each line in the UTF-8 bytes of `text` (lines split on '\\n')."""
    lines = text.split("\n")
    offs = [0] * (len(lines) + 1)
    acc = 0
    for i, ln in enumerate(lines):
        offs[i] = acc
        acc += len(ln.encode("utf-8")) + 1  # +1 for the '\n' separator
    offs[len(lines)] = acc
    return lines, offs


def _seg_byte_span(offs, start_line, end_line, nbytes):
    """Byte [start,end) of the segment '\\n'.join(lines[start_line:end_line]) in the file bytes."""
    b0 = offs[start_line]
    b1 = offs[end_line] - 1  # drop the trailing '\n' that join does not include
    if b1 < b0:
        b1 = b0
    if b1 > nbytes:
        b1 = nbytes
    return b0, b1


def _chunk_markdown(rel, content_hash, text):
    """Split by ATX headings; a pre-heading preamble is its own chunk. span_label = heading path;
    span = byte offsets of the segment."""
    lines, offs = _line_byte_offsets(text)
    nbytes = len(text.encode("utf-8"))
    chunks = []
    heads = []  # (line_index, level, title)
    for i, ln in enumerate(lines):
        m = re.match(r"^(#{1,6})\s+(.*\S)\s*$", ln)
        if m:
            heads.append((i, len(m.group(1)), m.group(2).strip()))
    segments = []  # (start_line, end_line, span_label, heading)
    if not heads or heads[0][0] > 0:
        first = heads[0][0] if heads else len(lines)
        segments.append((0, first, "(preamble)", "(preamble)"))
    path_stack = []
    for idx, (li, level, title) in enumerate(heads):
        end = heads[idx + 1][0] if idx + 1 < len(heads) else len(lines)
        while path_stack and path_stack[-1][0] >= level:
            path_stack.pop()
        path_stack.append((level, title))
        span_label = " > ".join(t for _, t in path_stack)
        segments.append((li, end, span_label, title))
    ci = 0
    for (start, end, span_label, heading) in segments:
        seg_text = "\n".join(lines[start:end]).strip()
        if seg_text == "":
            continue
        b0, b1 = _seg_byte_span(offs, start, end, nbytes)
        chunks.append(Chunk(rel, content_hash, "%s#%03d" % (rel, ci), span_label, b0, b1, seg_text,
                            section_path=span_label, heading=heading))
        ci += 1
    if not chunks:
        chunks.append(Chunk(rel, content_hash, "%s#000" % rel, "(document)", 0, nbytes, text.strip(),
                            section_path="(document)", heading="(document)"))
    return chunks


def _chunk_text(rel, content_hash, text):
    """Split a plain-text file into blank-line paragraphs. span_label = line range; span = byte offsets."""
    lines, offs = _line_byte_offsets(text)
    nbytes = len(text.encode("utf-8"))
    chunks = []
    ci = 0
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() == "":
            if start is not None:
                seg = "\n".join(lines[start:i]).strip()
                if seg:
                    span_label = "(lines %d-%d)" % (start + 1, i)
                    b0, b1 = _seg_byte_span(offs, start, i, nbytes)
                    chunks.append(Chunk(rel, content_hash, "%s#%03d" % (rel, ci), span_label, b0, b1, seg,
                                        section_path=span_label, heading=span_label))
                    ci += 1
                start = None
        else:
            if start is None:
                start = i
    if start is not None:
        seg = "\n".join(lines[start:]).strip()
        if seg:
            span_label = "(lines %d-%d)" % (start + 1, len(lines))
            b0, b1 = _seg_byte_span(offs, start, len(lines), nbytes)
            chunks.append(Chunk(rel, content_hash, "%s#%03d" % (rel, ci), span_label, b0, b1, seg,
                                section_path=span_label, heading=span_label))
            ci += 1
    if not chunks:
        chunks.append(Chunk(rel, content_hash, "%s#000" % rel, "(document)", 0, nbytes, text.strip(),
                            section_path="(document)", heading="(document)"))
    return chunks


class LexicalBaselineRetriever:
    """Deterministic BM25-lite over a fully-known fixture corpus, emitting retriever-0.2 (s3) hits:
    span OBJECT {start,end} + span_label, record ids, content_hash (SOURCE VERSION identity), status
    (current), authority_level (source_material), and per-channel diagnostics (lexical present; the vector
    channel EMPTY -> vector_rank/vector_similarity null; fused == lexical). Rank key
    (-score_millionths, source_path, chunk_id) -> a stable, cross-platform tie-break. Chunks with zero
    query-term overlap (score 0) are NEVER returned."""

    KIND = "lexical_baseline"
    CHUNKER_FP = "ck:md1txt1:bm25lite/1"
    PARSER_FP = "pf:markdown-atx+blankpara/1"
    FUSION_VERSION = "fusion/1"

    def __init__(self, spec, base_dir):
        corpus_dir = spec.get("corpus_dir")
        if not corpus_dir:
            raise ValueError("lexical_baseline retriever requires corpus_dir")
        self.corpus_dir_label = norm_path(corpus_dir)
        cdir = corpus_dir if os.path.isabs(corpus_dir) else os.path.join(base_dir, corpus_dir)
        cdir = os.path.abspath(cdir)
        if not os.path.isdir(cdir):
            raise ValueError("corpus_dir not found: %s" % self.corpus_dir_label)
        self.resolved_corpus_dir = cdir
        self.k1 = float(spec.get("k1", 1.5))
        self.b = float(spec.get("b", 0.75))
        include = spec.get("include_suffixes", [".md", ".txt"])
        self.include_suffixes = list(include) if include else None
        include_suffixes = set(s.lower() for s in include) if include else None
        self.exclude_dir_names = set(spec.get("exclude_dir_names", []))
        self.namespace = norm_path(corpus_dir)
        self.chunks = []
        self.sources = {}  # rel -> content_hash
        for rel, full, suffix in _iter_corpus_files(cdir, include_suffixes, self.exclude_dir_names):
            with open(full, "rb") as fh:
                text = normalized_text(fh.read())
            chash = content_hash_of_text(text)
            self.sources[rel] = chash
            if suffix == ".md":
                self.chunks.extend(_chunk_markdown(rel, chash, text))
            else:
                self.chunks.extend(_chunk_text(rel, chash, text))
        self.N = len(self.chunks)
        self.avgdl = (sum(c.length for c in self.chunks) / float(self.N)) if self.N else 0.0
        df = {}
        for c in self.chunks:
            for term in c.tf.keys():
                df[term] = df.get(term, 0) + 1
        self.df = df
        self.corpus_version = self._corpus_version()

    def _corpus_version(self):
        lines = []
        for rel in sorted(self.sources.keys()):
            lines.append("SRC\t%s\t%s" % (rel, self.sources[rel]))
        return "sha256:" + sha256_hex(("\n".join(lines) + "\n").encode("utf-8"))

    def _idf(self, term):
        n = self.df.get(term, 0)
        if n == 0:
            return 0.0
        return math.log(1.0 + (self.N - n + 0.5) / (n + 0.5))

    def _passes_filters(self, chunk, filters):
        if not filters:
            return True
        sp = chunk.source_path
        pref = filters.get("path_prefix")
        if pref is not None:
            prefs = pref if isinstance(pref, list) else [pref]
            if not any(sp.startswith(norm_path(p)) for p in prefs):
                return False
        xpref = filters.get("exclude_path_prefix")
        if xpref is not None:
            xprefs = xpref if isinstance(xpref, list) else [xpref]
            if any(sp.startswith(norm_path(p)) for p in xprefs):
                return False
        suf = filters.get("suffix")
        if suf is not None:
            sufs = suf if isinstance(suf, list) else [suf]
            if not any(sp.endswith(s) for s in sufs):
                return False
        return True

    def _record_ids(self, c):
        record_id = "srec_" + sha256_hex((c.source_path + "\0" + c.chunk_id).encode("utf-8"))[:24]
        record_version_id = "occ_" + sha256_hex(
            (c.content_hash + "\0" + self.CHUNKER_FP + "\0" + str(c.span_start) + "\0" +
             str(c.span_end) + "\0" + c.chunk_content_hash).encode("utf-8"))[:24]
        return record_id, record_version_id

    def search(self, query, k, filters=None):
        qterms = content_tokens(query)
        if not qterms:
            return []
        idf_cache = {}
        scored = []
        for c in self.chunks:
            if not self._passes_filters(c, filters):
                continue
            s = 0.0
            for term in qterms:
                tf = c.tf.get(term, 0)
                if tf == 0:
                    continue
                if term not in idf_cache:
                    idf_cache[term] = self._idf(term)
                idf = idf_cache[term]
                if idf == 0.0:
                    continue
                denom = tf + self.k1 * (1.0 - self.b + self.b * (c.length / self.avgdl if self.avgdl else 0.0))
                s += idf * (tf * (self.k1 + 1.0)) / denom
            sm = score_to_millionths(s)
            if sm > 0:
                scored.append((sm, c))
        scored.sort(key=lambda x: (-x[0], x[1].source_path, x[1].chunk_id))
        hits = []
        for rank0, (sm, c) in enumerate(scored[: max(0, int(k))]):
            record_id, record_version_id = self._record_ids(c)
            rank = rank0 + 1
            tie_break_key = "%012d\0%s\0%s" % (max(0, PPM * 1000 - sm), c.source_path, c.chunk_id)
            hits.append({
                "record_id": record_id,
                "record_version_id": record_version_id,
                "record_kind": "source_chunk",
                "source_path": c.source_path,
                "abs_path": None,
                "content_hash": c.content_hash,
                "chunk_id": c.chunk_id,
                "chunk_content_hash": c.chunk_content_hash,
                "span": {"start": c.span_start, "end": c.span_end},
                "span_start": c.span_start,
                "span_end": c.span_end,
                "span_label": c.span_label,
                "section_path": c.section_path,
                "heading": c.heading,
                "chunk_type": "prose",
                "status": "current",
                "currentness": "current",
                "authority_level": "source_material",
                "namespace": self.namespace,
                "source_version_id": c.content_hash,
                "embedding_space_id": None,
                "retrieval_channels": ["lexical"],
                "lexical_rank": rank,
                "lexical_score": sm,
                "vector_rank": None,
                "vector_similarity": None,
                "fused_rank": rank,
                "fused_score": sm,
                "fusion_algo": "lexical_only",
                "fusion_version": self.FUSION_VERSION,
                "index_snapshot": self.corpus_version,
                "corpus_version": self.corpus_version,
                "parser_fingerprint": self.PARSER_FP,
                "chunker_fingerprint": self.CHUNKER_FP,
                "filter_decisions": {},
                "tie_break_key": tie_break_key,
                "token_count": c.length,
                "snippet": snippet_of(c.text),
                "score": sm,
                "rank": rank,
            })
        return hits

    def corpus_manifest(self):
        return {"corpus_dir": self.corpus_dir_label,
                "corpus_version": self.corpus_version,
                "sources": [{"source_path": k, "content_hash": v} for k, v in sorted(self.sources.items())],
                "chunk_count": self.N}


# ------------------------------------------------------------------ external command retriever

def _navigate(obj, pointer):
    if not pointer:
        return obj
    cur = obj
    for part in pointer.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


class ExternalCommandRetriever:
    """Invoke any conforming retriever as a subprocess (the fold seam -> the real #36 artifact.search).
    The request {query,k,filters} is delivered via stdin|file|arg; stdout is parsed as JSON and
    `hits_pointer` navigates to the ranked hits array. The retriever OWNS its ranking (rank=index+1).
    Hits are NORMALIZED (retriever-0.2 s3 shape preferred; retriever-0.1 shape still accepted)."""

    KIND = "external_command"

    def __init__(self, spec, base_dir, python_exe):
        self.argv_tmpl = list(spec.get("argv", []))
        if not self.argv_tmpl:
            raise ValueError("external_command retriever requires argv")
        self.request_via = spec.get("request_via", "stdin")
        if self.request_via not in ("stdin", "file", "arg"):
            raise ValueError("request_via must be stdin|file|arg")
        self.hits_pointer = spec.get("hits_pointer", "result.hits")
        self.timeout = int(spec.get("timeout_seconds", 60))
        self.base_dir = base_dir
        self.python_exe = python_exe or sys.executable
        self.label = spec.get("label", "external_command")

    def _subst(self, s, request_file=None, request_json=None):
        s = s.replace("{PYTHON}", self.python_exe)
        s = s.replace("{BASE_DIR}", self.base_dir)
        s = s.replace("{MODULE_ROOT}", self.base_dir)
        if request_file is not None:
            s = s.replace("{REQUEST_FILE}", request_file)
        if request_json is not None:
            s = s.replace("{REQUEST_JSON}", request_json)
        return s

    def search(self, query, k, filters=None):
        request = {"query": query, "k": int(k), "filters": filters or {}}
        request_json = json.dumps(request, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
        request_file = None
        tmp = None
        try:
            if self.request_via == "file":
                tmp = os.path.join(self.base_dir, "_reqtmp_%s.json" % sha256_hex(request_json.encode())[:16])
                with open(tmp, "wb") as fh:
                    fh.write(request_json.encode("utf-8"))
                request_file = tmp
            argv = []
            has_json_token = any("{REQUEST_JSON}" in a for a in self.argv_tmpl)
            for a in self.argv_tmpl:
                argv.append(self._subst(a, request_file=request_file, request_json=request_json))
            if self.request_via == "arg" and not has_json_token:
                argv.append(request_json)
            stdin_data = request_json.encode("utf-8") if self.request_via == "stdin" else None
            proc = subprocess.run(argv, input=stdin_data, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, timeout=self.timeout)
            if proc.returncode != 0:
                raise RuntimeError("external retriever exit=%d stderr=%s"
                                   % (proc.returncode, proc.stderr.decode("utf-8", "replace")[:400]))
            out = proc.stdout.decode("utf-8", "strict").strip()
            try:
                parsed = json.loads(out)
            except Exception as e:
                raise RuntimeError("external retriever stdout not JSON: %s" % e)
            hits_raw = _navigate(parsed, self.hits_pointer)
            if hits_raw is None and isinstance(parsed, list):
                hits_raw = parsed
            if not isinstance(hits_raw, list):
                raise RuntimeError("external retriever hits pointer '%s' did not resolve to a list"
                                   % self.hits_pointer)
            hits = []
            for rank0, h in enumerate(hits_raw[: max(0, int(k))]):
                hits.append(normalize_hit(h, rank0 + 1))
            return hits
        finally:
            if tmp is not None and os.path.exists(tmp):
                try:
                    os.remove(tmp)
                except OSError:
                    pass


def _as_int_or_none(v):
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def normalize_hit(h, rank):
    """Normalize a raw retriever hit (retriever-0.2 s3 shape, or the retriever-0.1 shape) into the canonical
    internal hit used by the harness. Missing fields coerce sensibly; the array position is authoritative
    for `rank`."""
    if not isinstance(h, dict):
        h = {}
    span = h.get("span")
    span_start = _as_int_or_none(h.get("span_start"))
    span_end = _as_int_or_none(h.get("span_end"))
    span_label = h.get("span_label")
    if isinstance(span, dict):
        if span_start is None:
            span_start = _as_int_or_none(span.get("start"))
        if span_end is None:
            span_end = _as_int_or_none(span.get("end"))
        if span_label is None:
            if span_start is not None and span_end is not None:
                span_label = "bytes:%d-%d" % (span_start, span_end)
            else:
                span_label = ""
    elif isinstance(span, str):
        if span_label is None:
            span_label = span
    elif span_label is None:
        span_label = ""
    ch = h.get("content_hash")
    if not ch:
        ch = h.get("source_version_id") or h.get("version_id") or ""
    score = h.get("fused_score", None)
    if score is None:
        score = h.get("score", 0)
    status = h.get("status")
    if status is None:
        status = h.get("currentness")
    channels = h.get("retrieval_channels")
    if not isinstance(channels, list):
        channels = None
    return {
        "record_id": h.get("record_id"),
        "record_version_id": h.get("record_version_id"),
        "record_kind": h.get("record_kind"),
        "source_path": norm_path(h.get("source_path", "")),
        "abs_path": h.get("abs_path"),
        "content_hash": str(ch or ""),
        "chunk_id": str(h.get("chunk_id", "")),
        "chunk_content_hash": str(h.get("chunk_content_hash", "")),
        "span_start": span_start,
        "span_end": span_end,
        "span_label": str(span_label or ""),
        "section_path": h.get("section_path"),
        "heading": h.get("heading"),
        "chunk_type": h.get("chunk_type"),
        "status": status,
        "currentness": h.get("currentness", status),
        "authority_level": h.get("authority_level"),
        "namespace": h.get("namespace"),
        # i32/U4 (D-0092): preserve the supersession + contradiction edges so selpol_rrf_v1 can order a
        # superseded record below its live successor and propagate a contradicts pair (additive; None when absent).
        "superseded_by": h.get("superseded_by"),
        "supersedes": h.get("supersedes"),
        "contradicts": h.get("contradicts"),
        "record_edges": (h.get("record_edges") if isinstance(h.get("record_edges"), list) else h.get("edges")),
        # i33/U4' (D-0096): preserve the CATALOG-computed, POOL-INDEPENDENT effective_current signals #36 emits so
        # selpol excludes a superseded candidate under current_only even when its successor is absent (additive).
        "effective_current": (h.get("effective_current") if isinstance(h.get("effective_current"), bool) else None),
        "effective_current_successor": h.get("effective_current_successor"),
        "effective_current_successors": h.get("effective_current_successors"),
        "effective_current_branch": (h.get("effective_current_branch") if isinstance(h.get("effective_current_branch"), bool) else None),
        "source_version_id": h.get("source_version_id"),
        "embedding_space_id": h.get("embedding_space_id"),
        "retrieval_channels": channels,
        "lexical_rank": _as_int_or_none(h.get("lexical_rank")),
        "lexical_score": h.get("lexical_score"),
        "vector_rank": _as_int_or_none(h.get("vector_rank")),
        "vector_similarity": h.get("vector_similarity"),
        "fused_rank": _as_int_or_none(h.get("fused_rank")),
        "fused_score": h.get("fused_score"),
        "fusion_algo": h.get("fusion_algo"),
        "fusion_version": h.get("fusion_version"),
        "parser_fingerprint": h.get("parser_fingerprint"),
        "chunker_fingerprint": h.get("chunker_fingerprint"),
        "tie_break_key": h.get("tie_break_key"),
        "token_count": _as_int_or_none(h.get("token_count")),
        "snippet": str(h.get("snippet", "")),
        "score": h.get("score", score),
        "rank": rank,
    }


def build_retriever(spec, base_dir, python_exe):
    kind = spec.get("kind")
    if kind == LexicalBaselineRetriever.KIND:
        return LexicalBaselineRetriever(spec, base_dir)
    if kind == ExternalCommandRetriever.KIND:
        return ExternalCommandRetriever(spec, base_dir, python_exe)
    raise ValueError("unknown retriever kind: %r" % kind)


# ------------------------------------------------------------------ benchmark migration + labels

def _norm_member(m):
    """Normalize one required/group/distractor member spec (0.1 or 0.2)."""
    if not isinstance(m, dict):
        m = {"source_path": str(m)}
    out = {
        "source_path": norm_path(m.get("source_path", "")),
        "content_hash": (str(m["content_hash"]) if m.get("content_hash") else None),
        "chunk_id": (str(m["chunk_id"]) if m.get("chunk_id") else None),
        "span_label": None,
        "require_span": bool(m.get("require_span", False)),
        "span_start": _as_int_or_none(m.get("span_start")),
        "span_end": _as_int_or_none(m.get("span_end")),
        "acceptable_spans": [],
        "must_reproduce_text": (str(m["must_reproduce_text"]) if m.get("must_reproduce_text") else None),
    }
    sp = m.get("span")
    if isinstance(sp, dict):
        out["span_start"] = _as_int_or_none(sp.get("start"))
        out["span_end"] = _as_int_or_none(sp.get("end"))
    elif isinstance(sp, str):
        out["span_label"] = sp
    if m.get("span_label"):
        out["span_label"] = str(m["span_label"])
    for a in (m.get("acceptable_spans") or []):
        if isinstance(a, dict):
            asp = a.get("span")
            entry = {"span_label": None, "span_start": _as_int_or_none(a.get("span_start")),
                     "span_end": _as_int_or_none(a.get("span_end"))}
            if isinstance(asp, dict):
                entry["span_start"] = _as_int_or_none(asp.get("start"))
                entry["span_end"] = _as_int_or_none(asp.get("end"))
            if a.get("span_label"):
                entry["span_label"] = str(a["span_label"])
            elif isinstance(asp, str):
                entry["span_label"] = asp
            out["acceptable_spans"].append(entry)
        elif isinstance(a, str):
            out["acceptable_spans"].append({"span_label": a, "span_start": None, "span_end": None})
    return out


def _member_key(m):
    return (m["source_path"], m.get("content_hash") or "", m.get("chunk_id") or "",
            m.get("span_label") or "", m.get("span_start"), m.get("span_end"))


def normalize_query(q):
    """Migrate a 0.1 or 0.2 query into the canonical normalized query."""
    required = [_norm_member(r) for r in (q.get("required_sources") or [])]
    groups = []
    for g in (q.get("evidence_groups") or []):
        mode = g.get("mode", "all")
        if mode not in ("all", "any"):
            mode = "all"
        members = [_norm_member(m) for m in (g.get("members") or [])]
        groups.append({"group_id": str(g.get("group_id", "g%d" % (len(groups) + 1))),
                       "mode": mode, "members": members})
    ti = q.get("temporal_intent", "current_only")
    if ti not in TEMPORAL_INTENTS:
        ti = "current_only"
    return {
        "query_id": q.get("query_id"),
        "query": q.get("query"),
        "filters": q.get("filters"),
        "temporal_intent": ti,
        # i32 (D-0092) -> i33 (D-0096): U1' hard namespace closure boundary + U5' query_class / temporal split
        # (all optional; absent -> back-compat). explicit_temporal_intent (one of the 4-value enum) OUTRANKS the
        # query_class default; version_specific is an explicit as-of/version request.
        "allowed_namespaces": q.get("allowed_namespaces"),
        "query_class": q.get("query_class"),
        "explicit_temporal_intent": (q.get("explicit_temporal_intent")
                                     if q.get("explicit_temporal_intent") in TEMPORAL_INTENTS else None),
        "version_specific": bool(q.get("version_specific", False)),
        "required_sources": required,
        "evidence_groups": groups,
        "stale_sources": [_norm_member(s) for s in (q.get("stale_sources") or [])],
        "forbidden_sources": [_norm_member(s) for s in (q.get("forbidden_sources") or [])],
        "privacy_exclusions": [_norm_member(s) for s in (q.get("privacy_exclusions") or [])],
        "distractors": [_norm_member(s) for s in (q.get("distractors") or [])],
        "no_answer_expected": bool(q.get("no_answer_expected", False)),
        "label_rationale": q.get("label_rationale"),
        "label_status": q.get("label_status"),
        "reviewer": q.get("reviewer"),
        "corpus_snapshot": q.get("corpus_snapshot"),
        "rerank_descriptor": q.get("rerank_descriptor"),
    }


# ------------------------------------------------------------------ matching

def _span_matches(hit, m):
    candidates = []
    if m.get("span_start") is not None and m.get("span_end") is not None:
        candidates.append(("bytes", m["span_start"], m["span_end"]))
    if m.get("span_label"):
        candidates.append(("label", m["span_label"], None))
    for a in m.get("acceptable_spans") or []:
        if a.get("span_start") is not None and a.get("span_end") is not None:
            candidates.append(("bytes", a["span_start"], a["span_end"]))
        if a.get("span_label"):
            candidates.append(("label", a["span_label"], None))
    if not candidates:
        return True
    for kind, a, b in candidates:
        if kind == "bytes":
            if hit.get("span_start") == a and hit.get("span_end") == b:
                return True
        else:
            if str(hit.get("span_label", "")) == str(a):
                return True
    return False


def hit_matches_member(hit, m):
    """Chunk/version-level match: a FILE-level hit is NOT sufficient credit."""
    if norm_path(hit["source_path"]) != norm_path(m["source_path"]):
        return False
    if m.get("content_hash") and str(hit.get("content_hash", "")) != str(m["content_hash"]):
        return False
    if m.get("chunk_id") and str(hit.get("chunk_id", "")) != str(m["chunk_id"]):
        return False
    if m.get("require_span") or m.get("span_start") is not None or m.get("span_label"):
        if not _span_matches(hit, m):
            return False
    return True


def hit_matches_source_only(hit, m):
    """Path (+ optional version) match, ignoring chunk/span -- for forbidden/stale/distractor accounting."""
    if norm_path(hit["source_path"]) != norm_path(m["source_path"]):
        return False
    if m.get("content_hash") and str(hit.get("content_hash", "")) != str(m["content_hash"]):
        return False
    return True


# ------------------------------------------------------------------ provenance validation

def validate_provenance(hit, corpus, q):
    """s6 provenance VALIDATION (not presence). Returns (valid_bool, checks_dict, failed_list)."""
    checks = {}
    presence = bool(str(hit.get("source_path", "")) and str(hit.get("content_hash", "")) and
                    str(hit.get("chunk_id", "")) and
                    (str(hit.get("span_label", "")) or (hit.get("span_start") is not None and
                                                        hit.get("span_end") is not None)))
    checks["provenance_present"] = presence
    checks["fingerprint_known"] = bool(hit.get("chunker_fingerprint"))
    st = hit.get("status")
    checks["status_in_enum"] = (st is None) or (st in STATUS_ENUM)
    sp = norm_path(hit.get("source_path", ""))
    tombstoned = any(norm_path(t["source_path"]) == sp for t in q.get("tombstones", []))
    if corpus is not None and corpus.available:
        exists = corpus.has(sp)
        checks["source_exists_or_tombstoned"] = bool(exists or tombstoned or (hit.get("status") == "deleted"))
        if exists:
            checks["content_hash_matches_source"] = (str(hit.get("content_hash", "")) == corpus.content_hash(sp))
        else:
            checks["content_hash_matches_source"] = bool(tombstoned or hit.get("status") == "deleted")
        s, e = hit.get("span_start"), hit.get("span_end")
        if s is not None and e is not None and exists:
            span_text = corpus.span_text(sp, s, e)
            checks["span_in_bounds"] = span_text is not None
            if span_text is not None:
                collapsed = collapse_ws(span_text)
                snip = str(hit.get("snippet", ""))
                checks["snippet_derives_from_span"] = (snip == "" or collapsed.startswith(snip))
                mrt = None
                for m in q.get("_all_positive_members", []):
                    if hit_matches_source_only(hit, m) and m.get("must_reproduce_text"):
                        mrt = m["must_reproduce_text"]
                        break
                checks["span_reproduces_cited_text"] = True if mrt is None else (mrt in collapsed)
            else:
                checks["snippet_derives_from_span"] = False
                checks["span_reproduces_cited_text"] = False
        elif s is not None and e is not None and not exists:
            checks["span_in_bounds"] = False
            checks["snippet_derives_from_span"] = False
            checks["span_reproduces_cited_text"] = False
        else:
            checks["span_in_bounds"] = presence
            checks["snippet_derives_from_span"] = presence
            checks["span_reproduces_cited_text"] = True
        checks["status_correct"] = _status_correct(hit, corpus, q, exists, tombstoned)
    else:
        checks["source_exists_or_tombstoned"] = presence
        checks["content_hash_matches_source"] = bool(str(hit.get("content_hash", "")))
        checks["span_in_bounds"] = presence
        checks["snippet_derives_from_span"] = presence
        checks["span_reproduces_cited_text"] = True
        checks["status_correct"] = checks["status_in_enum"]
    failed = sorted([kname for kname, v in checks.items() if not v])
    return (len(failed) == 0), checks, failed


def _status_correct(hit, corpus, q, exists, tombstoned):
    sp = norm_path(hit.get("source_path", ""))
    st = hit.get("status")
    for s in q.get("stale_sources", []):
        if hit_matches_source_only(hit, s):
            return st in STALE_STATUSES if st is not None else True
    if exists and str(hit.get("content_hash", "")) == corpus.content_hash(sp):
        return (st is None) or (st == "current")
    if exists and str(hit.get("content_hash", "")) != corpus.content_hash(sp):
        return (st is None) or (st in STALE_STATUSES)
    if not exists:
        return (st is None) or (st in STALE_STATUSES) or tombstoned
    return True


# ------------------------------------------------------------------ per-query evaluation over an ordering

def _positive_members(q):
    """All positive (relevant) labels: required_sources + every evidence-group member, deduped by key."""
    members = list(q["required_sources"])
    for g in q["evidence_groups"]:
        members.extend(g["members"])
    seen = set()
    uniq = []
    for m in members:
        kk = _member_key(m)
        if kk not in seen:
            seen.add(kk)
            uniq.append(m)
    return uniq


def evaluate_ordering(q, ordered_hits, k_values, retrieval_depth, corpus):
    """Compute all metrics for one ordering (raw or reranked) of the hits."""
    required = q["required_sources"]
    depth_hits = ordered_hits[:retrieval_depth]

    # --- recall / MRR (0.1 semantics, preserved) ---
    req_first_rank = []
    for req in required:
        rank = 0
        for i, h in enumerate(depth_hits):
            if hit_matches_member(h, req):
                rank = i + 1
                break
        req_first_rank.append(rank)
    matched_at = {}
    recall_ppm_at = {}
    for k in k_values:
        matched = sum(1 for r in req_first_rank if 0 < r <= k)
        matched_at[str(k)] = matched
        recall_ppm_at[str(k)] = ppm(matched, len(required)) if required else PPM
    first_relevant_rank = 0
    for i, h in enumerate(depth_hits):
        if any(hit_matches_member(h, req) for req in required):
            first_relevant_rank = i + 1
            break
    rr_ppm = ppm(1, first_relevant_rank) if first_relevant_rank > 0 else 0
    missing_required = []
    for req, rank in zip(required, req_first_rank):
        if rank == 0:
            m = {"source_path": req["source_path"]}
            if req.get("span_label"):
                m["span_label"] = req["span_label"]
            missing_required.append(m)

    # --- positive labels (precision / nDCG / evidence groups) ---
    positives = _positive_members(q)
    credited = set()
    rel_flags = []
    for h in depth_hits:
        earned = 0
        for idx, m in enumerate(positives):
            if idx in credited:
                continue
            if hit_matches_member(h, m):
                credited.add(idx)
                earned = 1
                break
        rel_flags.append(earned)
    num_relevant_labels = len(positives)

    precision_at = {}
    ndcg_at = {}
    for k in k_values:
        topk = rel_flags[:k]
        rel_k = sum(topk)
        denom = min(k, len(depth_hits))
        precision_at[str(k)] = ppm(rel_k, denom) if denom > 0 else PPM
        dcg = 0
        for i, g in enumerate(topk):
            if g:
                dcg += (PPM * PPM) // _discount_millionths(i + 1)
        ideal = min(num_relevant_labels, k)
        idcg = 0
        for i in range(ideal):
            idcg += (PPM * PPM) // _discount_millionths(i + 1)
        ndcg_at[str(k)] = ppm(dcg, idcg) if idcg > 0 else (PPM if num_relevant_labels == 0 else 0)

    # --- evidence-group coverage ---
    group_results = []
    for g in q["evidence_groups"]:
        member_hit = []
        for m in g["members"]:
            member_hit.append(any(hit_matches_member(h, m) for h in depth_hits))
        if g["mode"] == "all":
            satisfied = all(member_hit) if member_hit else True
        else:
            satisfied = any(member_hit)
        group_results.append({"group_id": g["group_id"], "mode": g["mode"], "satisfied": satisfied,
                              "members_hit": sum(1 for x in member_hit if x),
                              "members_total": len(member_hit)})
    groups_total = len(group_results)
    groups_satisfied = sum(1 for gr in group_results if gr["satisfied"])
    evidence_group_coverage_ppm = ppm(groups_satisfied, groups_total) if groups_total else PPM

    # --- staleness (0.1 preserved) + stale-hit rate ---
    stale_set = set((norm_path(s["source_path"]), str(s.get("content_hash") or "")) for s in q["stale_sources"])
    req_by_path = {}
    for req in required:
        if req.get("content_hash"):
            req_by_path.setdefault(norm_path(req["source_path"]), str(req["content_hash"]))
    explicit_stale_hits = []
    wrong_version_hits = []
    stale_status_hits = 0
    for i, h in enumerate(depth_hits):
        hp = norm_path(h["source_path"])
        hc = str(h.get("content_hash", ""))
        if (hp, hc) in stale_set:
            explicit_stale_hits.append({"rank": i + 1, "source_path": hp, "content_hash": hc})
        elif hp in req_by_path and hc and hc != req_by_path[hp]:
            wrong_version_hits.append({"rank": i + 1, "source_path": hp, "content_hash": hc,
                                       "expected_content_hash": req_by_path[hp]})
        if h.get("status") in STALE_STATUSES:
            stale_status_hits += 1
    stale_affected = bool(explicit_stale_hits or wrong_version_hits) or (stale_status_hits > 0)
    stale_hit_rate_ppm = ppm(stale_status_hits + len(explicit_stale_hits) + len(wrong_version_hits),
                             len(depth_hits)) if depth_hits else 0

    # --- forbidden / privacy / distractor accounting ---
    forbidden_hits = []
    for i, h in enumerate(depth_hits):
        for f in q["forbidden_sources"]:
            if hit_matches_source_only(h, f):
                forbidden_hits.append({"rank": i + 1, "source_path": norm_path(h["source_path"])})
                break
    privacy_hits = []
    for i, h in enumerate(depth_hits):
        for f in q["privacy_exclusions"]:
            if hit_matches_source_only(h, f):
                privacy_hits.append({"rank": i + 1, "source_path": norm_path(h["source_path"])})
                break
    distractor_hits = []
    for i, h in enumerate(depth_hits):
        for d in q["distractors"]:
            if hit_matches_source_only(h, d):
                distractor_hits.append({"rank": i + 1, "source_path": norm_path(h["source_path"])})
                break
    irrelevant_ranks = set(x["rank"] for x in forbidden_hits) | set(x["rank"] for x in privacy_hits) | \
        set(x["rank"] for x in distractor_hits) | set(x["rank"] for x in explicit_stale_hits) | \
        set(x["rank"] for x in wrong_version_hits)
    judged_irrelevant_rate_ppm = ppm(len(irrelevant_ranks), len(depth_hits)) if depth_hits else 0

    # --- duplicate / near-dup burden + source diversity ---
    # near-dup = same chunk_content_hash (identical text, possibly a different file), else same
    # (source_path, span) -- catches "ten near-duplicate results crowding out distinct evidence" (8.3).
    seen_pairs = {}
    dup_count = 0
    for h in depth_hits:
        cch = str(h.get("chunk_content_hash", ""))
        if cch:
            key = ("cch", cch)
        else:
            key = ("sp", norm_path(h["source_path"]), str(h.get("span_label", "")),
                   str(h.get("span_start")), str(h.get("span_end")))
        seen_pairs[key] = seen_pairs.get(key, 0) + 1
        if seen_pairs[key] > 1:
            dup_count += 1
    dup_burden_ppm = ppm(dup_count, len(depth_hits)) if depth_hits else 0
    diversity_at = {}
    for k in k_values:
        topk = depth_hits[:k]
        distinct = len(set(norm_path(h["source_path"]) for h in topk))
        diversity_at[str(k)] = ppm(distinct, len(topk)) if topk else PPM

    # --- provenance completeness (presence) + validity (validation) + snippet-span correctness ---
    prov_total = len(depth_hits)
    prov_complete = 0
    prov_valid = 0
    snippet_span_ok = 0
    hit_prov = []
    for i, h in enumerate(depth_hits):
        present = bool(str(h.get("source_path", "")) and str(h.get("content_hash", "")) and
                       str(h.get("chunk_id", "")) and
                       (str(h.get("span_label", "")) or (h.get("span_start") is not None and
                                                         h.get("span_end") is not None)))
        if present:
            prov_complete += 1
        valid, checks, failed = validate_provenance(h, corpus, q)
        if valid:
            prov_valid += 1
        if checks.get("snippet_derives_from_span") and checks.get("span_reproduces_cited_text"):
            snippet_span_ok += 1
        hit_prov.append({"rank": i + 1, "provenance_present": present, "provenance_valid": valid,
                         "failed_checks": failed})

    # --- relevant-token / total-retrieved-token ratio ---
    def _tok(h):
        tc = h.get("token_count")
        if tc is not None:
            return int(tc)
        return len(content_tokens(str(h.get("snippet", ""))))
    total_tokens = sum(_tok(h) for h in depth_hits)
    relevant_tokens = sum(_tok(h) for i, h in enumerate(depth_hits) if rel_flags[i])
    relevant_token_ratio_ppm = ppm(relevant_tokens, total_tokens) if total_tokens else 0

    # --- no-answer false positive (abstention) ---
    no_answer_fp = False
    abstained = (len(depth_hits) == 0)
    if q["no_answer_expected"]:
        if q["distractors"]:
            no_answer_fp = len(distractor_hits) > 0
        else:
            no_answer_fp = len(depth_hits) > 0

    returned = []
    for i, h in enumerate(depth_hits):
        returned.append({
            "rank": i + 1,
            "source_path": norm_path(h["source_path"]),
            "content_hash": str(h.get("content_hash", "")),
            "chunk_id": str(h.get("chunk_id", "")),
            "span_label": str(h.get("span_label", "")),
            "span_start": h.get("span_start"),
            "span_end": h.get("span_end"),
            "record_kind": h.get("record_kind"),
            "status": h.get("status"),
            "authority_level": h.get("authority_level"),
            "channels": h.get("retrieval_channels"),
            "score": h.get("score", 0),
            "relevant": bool(rel_flags[i]),
            "provenance_complete": hit_prov[i]["provenance_present"],
            "provenance_valid": hit_prov[i]["provenance_valid"],
            "provenance_failed_checks": hit_prov[i]["failed_checks"],
            # ADDITIVE selection fields (CONTEXT_PACKET_CONTRACT s4): the retrieval rank is PRESERVED; the
            # selection layer adds its own ordering + reason codes without re-sorting the retrieval array.
            "retrieval_rank": h.get("retrieval_rank", h.get("rank")),
            "selection_rank": h.get("selection_rank"),
            "selection_score": h.get("selection_score"),
            "selection_policy_id": h.get("selection_policy_id"),
            "selected": h.get("selected"),
            "reason_codes": h.get("reason_codes"),
            "evidence_cluster_id": h.get("evidence_cluster_id"),
            "occurrence_count": (len(h["occurrences"]) if isinstance(h.get("occurrences"), list) else None),
        })

    return {
        "query_id": q.get("query_id"),
        "query": q.get("query"),
        "temporal_intent": q["temporal_intent"],
        "num_required": len(required),
        "num_relevant_labels": num_relevant_labels,
        "matched_at_k": matched_at,
        "recall_at_k_ppm": recall_ppm_at,
        "precision_at_k_ppm": precision_at,
        "ndcg_at_k_ppm": ndcg_at,
        "diversity_at_k_ppm": diversity_at,
        "first_relevant_rank": first_relevant_rank,
        "reciprocal_rank_ppm": rr_ppm,
        "all_required_present": (len(missing_required) == 0),
        "missing_required": missing_required,
        "evidence_groups": group_results,
        "evidence_group_coverage_ppm": evidence_group_coverage_ppm,
        "explicit_stale_hits": explicit_stale_hits,
        "wrong_version_hits": wrong_version_hits,
        "stale_affected": stale_affected,
        "stale_hit_rate_ppm": stale_hit_rate_ppm,
        "forbidden_hits": forbidden_hits,
        "privacy_hits": privacy_hits,
        "distractor_hits": distractor_hits,
        "judged_irrelevant_rate_ppm": judged_irrelevant_rate_ppm,
        "duplicate_burden_ppm": dup_burden_ppm,
        "provenance_total": prov_total,
        "provenance_complete": prov_complete,
        "provenance_valid": prov_valid,
        "snippet_span_correct": snippet_span_ok,
        "relevant_token_ratio_ppm": relevant_token_ratio_ppm,
        "no_answer_expected": q["no_answer_expected"],
        "no_answer_false_positive": no_answer_fp,
        "abstained": abstained,
        "returned": returned,
    }


# ------------------------------------------------------------------ deterministic selection (selpol_rrf_v1)
# The selection policy is OWNED by lib/selpol_rrf_v1.py (CONTEXT_PACKET_CONTRACT s4 / P1-1) -- the ONE
# selection owner that the context compiler #40 AND this harness's own A/B both consume (removing the
# "two rerankers" problem). `rerank()` is now a THIN WRAPPER over that library: the measured A/B measures
# the library. The shipped feature weights / authority rank / task-stage kinds / hard-demote / stale
# penalty / diversity now live in the library (its RERANK_W etc.). dedup_display=False + no budget make the
# reranked order + diagnostics BYTE-IDENTICAL to the shipped standalone reranker (regression-green).
# Re-exported here so any downstream import of these names keeps resolving.
RERANK_W = selpol.RERANK_W
RERANK_HARD_DEMOTE = selpol.RERANK_HARD_DEMOTE
RERANK_STALE_PENALTY = selpol.RERANK_STALE_PENALTY
RERANK_DIVERSITY_PENALTY = selpol.RERANK_DIVERSITY_PENALTY
AUTHORITY_RANK = selpol.AUTHORITY_RANK
TASK_STAGE_KINDS = selpol.TASK_STAGE_KINDS


def _policy_params_from_query(q):
    """Map the benchmark query's labels into selpol_rrf_v1 POLICY SIGNALS (kept out of the library so it
    stays pure): forbidden/privacy -> hard_filter; stale_sources -> stale; required version -> required_versions;
    temporal_intent current_only -> current_only. #40 supplies hard_filter from control_plane.permission_grants
    and relies on the candidate's own s5 status for temporal demote -- the SAME library, different signal source."""
    hard_filter = []
    for f in q.get("forbidden_sources", []):
        hard_filter.append({"source_path": f["source_path"], "content_hash": f.get("content_hash"),
                            "reason": "forbidden"})
    for f in q.get("privacy_exclusions", []):
        hard_filter.append({"source_path": f["source_path"], "content_hash": f.get("content_hash"),
                            "reason": "privacy"})
    return {
        # temporal_intent is the benchmark's temporal LABEL; it forces current_only ONLY when NEITHER a
        # query_class NOR an explicit_temporal_intent is supplied. When a query_class IS present (the #40-aligned
        # path) it DRIVES selpol's temporal mode via the versioned class->intent map (U5'); an
        # explicit_temporal_intent OUTRANKS the class default (the i33/U5' split).
        "current_only": (q.get("temporal_intent") == "current_only")
                        and not q.get("query_class") and not q.get("explicit_temporal_intent"),
        # i32/U1 -> i33/U1': allowed_namespaces is the CALLER-computed effective set (a HARD closure boundary).
        # Absent -> None (back-compat: soft project bonus + no closure; #40 always supplies it).
        "allowed_namespaces": q.get("allowed_namespaces"),
        # i33/U5': query_class (semantic) drives the class-default temporal_intent; explicit_temporal_intent
        # (temporal) OUTRANKS it. Both optional; absent -> the byte-identical back-compat path.
        "query_class": q.get("query_class"),
        "temporal_intent": q.get("explicit_temporal_intent"),
        "version_specific": bool(q.get("version_specific", False)),
        "hard_filter": hard_filter,
        "stale": [{"source_path": s["source_path"], "content_hash": s.get("content_hash")}
                  for s in q.get("stale_sources", [])],
        "required_versions": [{"source_path": r["source_path"], "content_hash": r["content_hash"]}
                              for r in q.get("required_sources", []) if r.get("content_hash")],
    }


def rerank(hits, descriptor, q):
    """Deterministic rerank of retriever-0.2 hits -> the SAME hit-array shape reordered, via selpol_rrf_v1
    (CONTEXT_PACKET_CONTRACT s4). Returns (reordered_hits, diagnostics) BYTE-IDENTICAL to the shipped
    standalone reranker. The reordered hits ADDITIVELY carry selection_rank/selection_score/selection_policy_id/
    selected/reason_codes/retrieval_occurrences while preserving retrieval_rank + the channel ranks; a drop-in
    for #40's selection."""
    return selpol.rerank_compat(hits, descriptor, _policy_params_from_query(q))


def select_packet(hits, descriptor, q, budget=None):
    """The packet-STAGE selection (CONTEXT_PACKET_CONTRACT s4 stage 5-6): occurrence-preserving display dedup
    + budget, the shape #40 compiles into a context packet. Returns the full selpol_rrf_v1 result."""
    params = _policy_params_from_query(q)
    params["dedup_display"] = True
    if budget is not None:
        params["budget"] = budget
    return selpol.select(hits, descriptor, selpol.POLICY_ID, params)


def default_descriptor(rawq):
    """Build a deterministic task/query descriptor from the benchmark query (no model)."""
    d = {"query": rawq.get("query"), "query_tokens": content_tokens(str(rawq.get("query", "")))}
    rd = rawq.get("rerank_descriptor") or {}
    for kname in ("namespace", "component", "task_stage", "seeking_failures", "query_class", "time_horizon"):
        if kname in rd:
            d[kname] = rd[kname]
    # i32/U5 (D-0092): a top-level query_class flows into the selection descriptor (drives selpol temporal mode).
    if rawq.get("query_class") and "query_class" not in d:
        d["query_class"] = rawq.get("query_class")
    return d


# ------------------------------------------------------------------ selection conformance (eval-0.5, i33 D-0096)
# eval-0.5 MEASURES the i33 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING leakage paths on the PACKET-STAGE
# selection, over the i32 eval-0.4 measures. Integer-only + deterministic (byte-identical on re-run). Queries
# that supply no signal report trivially (0 violations). The measured properties:
#  * U1' NAMESPACE CLOSURE -- a cross-namespace distractor must NOT be selected AND must NOT appear in ANY
#    selection-output diagnostic array (ranked[]); the sanitized `namespace_violation_count` is the ONLY
#    surface the drop leaves. `cross_namespace_in_ranked == 0` is the leak check the i32 "sink-in-place" failed.
#  * U4' POOL-INDEPENDENT current_only -- a candidate the catalog marks `effective_current == False` (a
#    superseded record, even one whose successor is ABSENT from the pool) must NOT be selected under current_only.
#  * U4' supersession ordering (a live successor above its superseded twin) + branch `supersession_conflicts`.
#  * U5' the query_class / temporal_intent split (the resolved `temporal_intent` + its source + classifier id).
#  * reason-code coverage.

def selection_conformance(q, norm_hits, selres):
    """Per-query i33 selection-conformance record (see the section header). Scored on selres (the packet stage)."""
    allowed = selres.get("allowed_namespaces")             # sorted list | None
    allowed_set = set(allowed) if allowed is not None else None
    mode = selres.get("temporal_mode")
    current_only = (mode == "current_only")
    selected = selres.get("selected") or []
    ranked = selres.get("ranked") or []

    def _is_stale(h):
        return h.get("status") in STALE_STATUSES

    def _not_current(h):
        # POOL-INDEPENDENT: the catalog effective_current verdict when present, else the status-stale fallback.
        ec = h.get("effective_current")
        if isinstance(ec, bool):
            return ec is False
        return _is_stale(h)

    cross_cand = sum(1 for h in norm_hits if allowed_set is not None and h.get("namespace") not in allowed_set)
    cross_sel = sum(1 for h in selected if allowed_set is not None and h.get("namespace") not in allowed_set)
    # U1' leak check: a cross-namespace item must not appear in ANY selection-output diagnostic array (ranked[]).
    cross_ranked = sum(1 for h in ranked if allowed_set is not None and h.get("namespace") not in allowed_set)
    ns_violation_count = int(selres.get("namespace_violation_count") or 0)
    stale_cand = sum(1 for h in norm_hits if _is_stale(h))
    stale_sel_co = sum(1 for h in selected if current_only and _is_stale(h))
    # U4' pool-independent: a candidate flagged not-effective-current must not be selected under current_only.
    noncurrent_cand = sum(1 for h in norm_hits if _not_current(h))
    noncurrent_sel_co = sum(1 for h in selected if current_only and _not_current(h))

    # supersession: a SELECTED superseded record whose live successor is ALSO selected must rank BELOW it.
    sel_by_id = {}
    for h in selected:
        for idv in selpol._identities(h):
            sel_by_id.setdefault(idv, h)
    sup_total = 0
    sup_correct = 0
    for h in selected:
        succ = None
        for sid in selpol._successor_ids(h):               # records that supersede h
            cand = sel_by_id.get(sid)
            if cand is not None and cand is not h:
                succ = cand
                break
        if succ is not None:
            sup_total += 1
            sr, hr = succ.get("selection_rank"), h.get("selection_rank")
            if isinstance(sr, int) and isinstance(hr, int) and sr < hr:
                sup_correct += 1

    codes = set()
    for h in ranked:
        for c in (h.get("reason_codes") or []):
            codes.add(c)

    return {
        "query_id": q.get("query_id"),
        "allowed_namespaces": allowed,
        "temporal_mode": mode,
        # i33/U5' the resolved temporal_intent + its source + the versioned classifier policy (packet identity).
        "temporal_intent": selres.get("temporal_intent"),
        "temporal_intent_source": selres.get("temporal_intent_source"),
        "classifier_policy_id": selres.get("classifier_policy_id"),
        "classifier_policy_version": selres.get("classifier_policy_version"),
        "namespace_policy_id": selres.get("namespace_policy_id"),
        "current_only": current_only,
        "candidate_count": len(norm_hits),
        "selected_count": len(selected),
        "ranked_count": len(ranked),
        "cross_namespace_candidates": cross_cand,
        "cross_namespace_selected": cross_sel,
        # i33/U1' the DIAGNOSTIC-array leak check + the sanitized surface.
        "cross_namespace_in_ranked": cross_ranked,
        "namespace_violation_count": ns_violation_count,
        "namespace_closure_violated": bool(selres.get("namespace_closure_violated")),
        "namespace_isolation_ok": (cross_sel == 0),
        "namespace_closure_ok": (cross_sel == 0 and cross_ranked == 0),
        "stale_candidates": stale_cand,
        "stale_selected_under_current_only": stale_sel_co,
        "current_only_isolation_ok": (stale_sel_co == 0),
        # i33/U4' pool-independent current_only.
        "noncurrent_candidates": noncurrent_cand,
        "noncurrent_selected_under_current_only": noncurrent_sel_co,
        "pool_independent_current_only_ok": (noncurrent_sel_co == 0),
        "supersession_pairs_total": sup_total,
        "supersession_pairs_correct": sup_correct,
        "supersession_order_ok": (sup_total == sup_correct),
        "supersession_conflicts": selres.get("supersession_conflicts") or [],
        "contradicts_pairs": selres.get("contradicts_pairs") or [],
        "conflicted": bool(selres.get("conflicted")),
        "reason_codes_observed": sorted(codes),
    }


def aggregate_selection_conformance(per_q):
    """Aggregate the per-query i33 conformance into integer counters + reason-code coverage (deterministic)."""
    n = len(per_q)
    codes = set()
    for q in per_q:
        codes.update(q["reason_codes_observed"])
    return {
        "num_queries": n,
        "queries_with_allowed_namespaces": sum(1 for q in per_q if q["allowed_namespaces"] is not None),
        "queries_current_only": sum(1 for q in per_q if q["current_only"]),
        "cross_namespace_candidates_total": sum(q["cross_namespace_candidates"] for q in per_q),
        "cross_namespace_selected_total": sum(q["cross_namespace_selected"] for q in per_q),
        # i33/U1' leakage-path totals: the diagnostic-array leak + the sanitized violation count.
        "cross_namespace_in_ranked_total": sum(q["cross_namespace_in_ranked"] for q in per_q),
        "namespace_violations_total": sum(q["namespace_violation_count"] for q in per_q),
        "namespace_isolation_violations": sum(1 for q in per_q if not q["namespace_isolation_ok"]),
        "namespace_closure_violations": sum(1 for q in per_q if not q["namespace_closure_ok"]),
        "queries_with_namespace_drop": sum(1 for q in per_q if q["namespace_closure_violated"]),
        "stale_candidates_total": sum(q["stale_candidates"] for q in per_q),
        "current_only_stale_leaks": sum(q["stale_selected_under_current_only"] for q in per_q),
        "queries_with_current_only_leak": sum(1 for q in per_q if not q["current_only_isolation_ok"]),
        # i33/U4' pool-independent current_only totals.
        "noncurrent_candidates_total": sum(q["noncurrent_candidates"] for q in per_q),
        "pool_independent_current_only_leaks": sum(q["noncurrent_selected_under_current_only"] for q in per_q),
        "queries_with_pool_independent_leak": sum(1 for q in per_q if not q["pool_independent_current_only_ok"]),
        "supersession_pairs_total": sum(q["supersession_pairs_total"] for q in per_q),
        "supersession_pairs_correct": sum(q["supersession_pairs_correct"] for q in per_q),
        "supersession_order_violations": sum(1 for q in per_q if not q["supersession_order_ok"]),
        "queries_with_supersession_branch": sum(1 for q in per_q if q["supersession_conflicts"]),
        "queries_with_contradicts": sum(1 for q in per_q if q["contradicts_pairs"]),
        "queries_conflicted": sum(1 for q in per_q if q["conflicted"]),
        "reason_code_coverage": sorted(codes),
        "reason_code_coverage_count": len(codes),
    }


# ------------------------------------------------------------------ hybrid attribution (per-channel)

def hybrid_attribution(q, ordered_hits, retrieval_depth):
    """s6 hybrid attribution from the retriever-0.2 per-channel diagnostics. Lexical-only / vector-only /
    hybrid. The vector channel runs EMPTY today (no vectors) -> reported cleanly. Reads each hit's
    retrieval_channels + lexical_rank/vector_rank + fused_rank (never re-runs retrieval)."""
    depth_hits = ordered_hits[:retrieval_depth]
    lexical, vector, fused = [], [], []
    lexical_demoted_by_fusion = 0
    for h in depth_hits:
        ch = h.get("retrieval_channels") or []
        lr = h.get("lexical_rank")
        vr = h.get("vector_rank")
        fr = h.get("fused_rank")
        key = (norm_path(h["source_path"]), str(h.get("chunk_id", "")))
        if ("lexical" in ch) or (lr is not None):
            lexical.append((lr if lr is not None else 10 ** 9, key))
        if ("vector" in ch) or (vr is not None):
            vector.append((vr if vr is not None else 10 ** 9, key))
        fused.append((fr if fr is not None else h.get("rank", 0), key))
        if lr is not None and fr is not None and fr > lr:
            lexical_demoted_by_fusion += 1
    lexical_keys = set(k for _, k in lexical)
    vector_keys = set(k for _, k in vector)
    unique_to_lexical = sorted(lexical_keys - vector_keys)
    unique_to_vector = sorted(vector_keys - lexical_keys)
    rescued = []
    for req in q["required_sources"]:
        for h in depth_hits:
            if hit_matches_member(h, req):
                ch = h.get("retrieval_channels") or []
                if ("vector" in ch or h.get("vector_rank") is not None) and \
                        not ("lexical" in ch or h.get("lexical_rank") is not None):
                    rescued.append(norm_path(h["source_path"]))
                break

    def _introduced(pred):
        by_vec = 0
        by_lex = 0
        for h in depth_hits:
            if not pred(h):
                continue
            ch = h.get("retrieval_channels") or []
            in_lex = "lexical" in ch or h.get("lexical_rank") is not None
            in_vec = "vector" in ch or h.get("vector_rank") is not None
            if in_vec and not in_lex:
                by_vec += 1
            elif in_lex and not in_vec:
                by_lex += 1
        return by_lex, by_vec
    stale_lex, stale_vec = _introduced(lambda h: h.get("status") in STALE_STATUSES or
                                       any(hit_matches_source_only(h, s) for s in q["stale_sources"]))
    forb_lex, forb_vec = _introduced(lambda h: any(hit_matches_source_only(h, f)
                                     for f in q["forbidden_sources"] + q["privacy_exclusions"]))
    lex_order = [k for _, k in sorted(lexical)]
    fused_order = [k for _, k in sorted(fused)]
    fusion_reordered = (lex_order != fused_order)
    return {
        "query_id": q.get("query_id"),
        "lexical_hit_count": len(lexical),
        "vector_hit_count": len(vector),
        "unique_to_lexical": [list(k) for k in unique_to_lexical],
        "unique_to_vector": [list(k) for k in unique_to_vector],
        "required_rescued_by_vector": sorted(set(rescued)),
        "lexical_exactmatch_harmed_by_fusion": lexical_demoted_by_fusion,
        "stale_introduced_by_lexical": stale_lex,
        "stale_introduced_by_vector": stale_vec,
        "forbidden_introduced_by_lexical": forb_lex,
        "forbidden_introduced_by_vector": forb_vec,
        "fusion_reordered_vs_lexical": fusion_reordered,
    }


# ------------------------------------------------------------------ aggregation

def aggregate(per_query, k_values, retrieval_depth, label):
    n = len(per_query)
    recall_macro = {}
    recall_micro = {}
    precision_macro = {}
    ndcg_macro = {}
    diversity_macro = {}
    for k in k_values:
        ks = str(k)
        recall_macro[ks] = mean_ppm([q["recall_at_k_ppm"][ks] for q in per_query]) if n else 0
        tot_matched = sum(q["matched_at_k"][ks] for q in per_query)
        tot_required = sum(q["num_required"] for q in per_query)
        recall_micro[ks] = ppm(tot_matched, tot_required) if tot_required else PPM
        precision_macro[ks] = mean_ppm([q["precision_at_k_ppm"][ks] for q in per_query]) if n else 0
        ndcg_macro[ks] = mean_ppm([q["ndcg_at_k_ppm"][ks] for q in per_query]) if n else 0
        diversity_macro[ks] = mean_ppm([q["diversity_at_k_ppm"][ks] for q in per_query]) if n else 0
    mrr = mean_ppm([q["reciprocal_rank_ppm"] for q in per_query]) if n else 0
    stale_rate = ppm(sum(1 for q in per_query if q["stale_affected"]), n) if n else 0
    stale_hit_rate = mean_ppm([q["stale_hit_rate_ppm"] for q in per_query]) if n else 0
    forbidden_rate = ppm(sum(1 for q in per_query if q["forbidden_hits"]), n) if n else 0
    privacy_rate = ppm(sum(1 for q in per_query if q["privacy_hits"]), n) if n else 0
    egroup_qs = [q for q in per_query if q["evidence_groups"]]
    egc = mean_ppm([q["evidence_group_coverage_ppm"] for q in egroup_qs]) if egroup_qs else PPM
    dup_burden = mean_ppm([q["duplicate_burden_ppm"] for q in per_query]) if n else 0
    irr_rate = mean_ppm([q["judged_irrelevant_rate_ppm"] for q in per_query]) if n else 0
    rel_tok = mean_ppm([q["relevant_token_ratio_ppm"] for q in per_query]) if n else 0
    prov_total = sum(q["provenance_total"] for q in per_query)
    prov_complete = sum(q["provenance_complete"] for q in per_query)
    prov_valid = sum(q["provenance_valid"] for q in per_query)
    snippet_ok = sum(q["snippet_span_correct"] for q in per_query)
    prov_completeness = ppm(prov_complete, prov_total) if prov_total else PPM
    prov_validity = ppm(prov_valid, prov_total) if prov_total else PPM
    snippet_span = ppm(snippet_ok, prov_total) if prov_total else PPM
    no_answer_q = [q for q in per_query if q["no_answer_expected"]]
    no_answer_fp_rate = ppm(sum(1 for q in no_answer_q if q["no_answer_false_positive"]),
                            len(no_answer_q)) if no_answer_q else 0
    queries_all_required = sum(1 for q in per_query if q["all_required_present"])
    return {
        "label": label,
        "num_queries": n,
        "k_values": list(k_values),
        "retrieval_depth": retrieval_depth,
        "ratio_unit": RATIO_UNIT,
        "recall_at_k_ppm": recall_macro,
        "recall_at_k_micro_ppm": recall_micro,
        "precision_at_k_ppm": precision_macro,
        "ndcg_at_k_ppm": ndcg_macro,
        "source_diversity_at_k_ppm": diversity_macro,
        "mrr_ppm": mrr,
        "evidence_group_coverage_ppm": egc,
        "stale_source_rate_ppm": stale_rate,
        "stale_hit_rate_ppm": stale_hit_rate,
        "forbidden_hit_rate_ppm": forbidden_rate,
        "privacy_hit_rate_ppm": privacy_rate,
        "judged_irrelevant_rate_ppm": irr_rate,
        "duplicate_burden_ppm": dup_burden,
        "relevant_token_ratio_ppm": rel_tok,
        "provenance_completeness_ppm": prov_completeness,
        "provenance_validity_ppm": prov_validity,
        "snippet_span_correctness_ppm": snippet_span,
        "no_answer_false_positive_rate_ppm": no_answer_fp_rate,
        "queries_all_required_present": queries_all_required,
        "total_hits": prov_total,
        "total_required": sum(q["num_required"] for q in per_query),
        "total_provenance_complete": prov_complete,
        "total_provenance_valid": prov_valid,
    }


def rerank_ab(per_query_raw, per_query_reranked, k_values):
    """A/B: reranked - raw on the key metrics + per-query rescue/demote."""
    def macro(pq, key, k=None):
        if k is None:
            return mean_ppm([q[key] for q in pq]) if pq else 0
        return mean_ppm([q[key][str(k)] for q in pq]) if pq else 0

    def presence_rate(pq, key):
        return ppm(sum(1 for q in pq if q[key]), len(pq)) if pq else 0

    deltas = {}
    for k in k_values:
        ks = str(k)
        deltas["ndcg_at_%s_ppm" % ks] = macro(per_query_reranked, "ndcg_at_k_ppm", k) - macro(per_query_raw, "ndcg_at_k_ppm", k)
        deltas["precision_at_%s_ppm" % ks] = macro(per_query_reranked, "precision_at_k_ppm", k) - macro(per_query_raw, "precision_at_k_ppm", k)
        deltas["recall_at_%s_ppm" % ks] = macro(per_query_reranked, "recall_at_k_ppm", k) - macro(per_query_raw, "recall_at_k_ppm", k)
    deltas["mrr_ppm"] = macro(per_query_reranked, "reciprocal_rank_ppm") - macro(per_query_raw, "reciprocal_rank_ppm")
    deltas["evidence_group_coverage_ppm"] = macro(per_query_reranked, "evidence_group_coverage_ppm") - macro(per_query_raw, "evidence_group_coverage_ppm")
    deltas["forbidden_hit_rate_ppm"] = presence_rate(per_query_reranked, "forbidden_hits") - presence_rate(per_query_raw, "forbidden_hits")
    deltas["stale_hit_rate_ppm"] = macro(per_query_reranked, "stale_hit_rate_ppm") - macro(per_query_raw, "stale_hit_rate_ppm")

    # rescue is measured at the SMALLEST K (a required source pulled INTO the small top-K by reranking).
    mink = min(k_values) if k_values else 1
    per_query = []
    rescued_total = 0
    demoted_total = 0
    for raw, rr in zip(per_query_raw, per_query_reranked):
        raw_recall = raw["recall_at_k_ppm"][str(mink)]
        rr_recall = rr["recall_at_k_ppm"][str(mink)]
        rescued = rr_recall > raw_recall

        def top1_bad(ev):
            return (any(x["rank"] == 1 for x in ev["forbidden_hits"]) or
                    any(x["rank"] == 1 for x in ev["explicit_stale_hits"]) or
                    any(x["rank"] == 1 for x in ev["wrong_version_hits"]) or
                    any(x["rank"] == 1 for x in ev["privacy_hits"]))
        demoted = top1_bad(raw) and not top1_bad(rr)
        if rescued:
            rescued_total += 1
        if demoted:
            demoted_total += 1
        per_query.append({"query_id": raw["query_id"], "required_rescued": rescued,
                          "bad_hit_demoted_from_top1": demoted,
                          "raw_recall_ppm": raw_recall, "reranked_recall_ppm": rr_recall})
    return {"deltas": deltas, "queries_with_rescue": rescued_total,
            "queries_with_demote": demoted_total, "per_query": per_query}


# ------------------------------------------------------------------ packet disposition + per-stage (P0-3 / P1-4)

PACKET_DISPOSITIONS = ("answerable", "needs_expansion", "abstain", "conflicted", "provenance_failed")


def compute_packet_disposition(q, selected_hits, raw_hits, corpus):
    """Deterministic packet_disposition (CONTEXT_PACKET_CONTRACT s2 mapping; the i30 subset). Computed from
    the PACKET-STAGE selection: any provenance failure -> provenance_failed; a no-answer query that surfaced
    evidence is not answerable; an unmet required requirement is needs_expansion when the source appears in
    raw retrieval (expandable) else abstain; otherwise answerable. `conflicted` is a reserved hook (no
    current-vs-current contradiction labels in the i30 fixtures)."""
    for h in selected_hits:
        valid, _c, _f = validate_provenance(h, corpus, q)
        if not valid:
            return "provenance_failed"
    reqs = list(q["required_sources"])
    for g in q["evidence_groups"]:
        if g["mode"] == "all":
            reqs.extend(g["members"])
    unmet = [r for r in reqs if not any(hit_matches_member(h, r) for h in selected_hits)]
    if q["no_answer_expected"]:
        return "abstain" if len(selected_hits) == 0 else "needs_expansion"
    if unmet:
        expandable = any(any(hit_matches_member(h, r) for h in raw_hits) for r in unmet)
        return "needs_expansion" if expandable else "abstain"
    return "answerable"


def packet_disposition_record(rawq, q, selected_hits, raw_hits, corpus):
    """One packet_disposition eval record. `actual` is READ from a supplied #40 context_packet
    (`rawq.context_packet.packet_disposition`) when present -- the fold path -- else COMPUTED deterministically
    from the packet-stage selection. Scored against `expected_packet_disposition` when labelled."""
    computed = compute_packet_disposition(q, selected_hits, raw_hits, corpus)
    packet = rawq.get("context_packet") if isinstance(rawq.get("context_packet"), dict) else None
    supplied = None
    if packet is not None and packet.get("packet_disposition") in PACKET_DISPOSITIONS:
        supplied = packet["packet_disposition"]
    actual = supplied if supplied is not None else computed
    source = "packet" if supplied is not None else "computed"
    expected = rawq.get("expected_packet_disposition")
    if expected not in PACKET_DISPOSITIONS:
        expected = None
    correct = None if expected is None else (actual == expected)
    return {"query_id": q.get("query_id"), "expected": expected, "actual": actual,
            "computed": computed, "supplied": supplied, "source": source, "correct": correct}


def aggregate_disposition(records):
    labeled = [r for r in records if r["expected"] is not None]
    correct = sum(1 for r in labeled if r["correct"])
    return {
        "scored": len(labeled) > 0,
        "num_labeled": len(labeled),
        "num_correct": correct,
        "accuracy_ppm": ppm(correct, len(labeled)) if labeled else PPM,
        "per_query": records,
    }


_STAGE_METRIC_KEYS = ("recall_at_k_ppm", "precision_at_k_ppm", "ndcg_at_k_ppm",
                      "source_diversity_at_k_ppm", "mrr_ppm", "evidence_group_coverage_ppm",
                      "forbidden_hit_rate_ppm", "privacy_hit_rate_ppm", "stale_hit_rate_ppm",
                      "duplicate_burden_ppm", "provenance_validity_ppm", "no_answer_false_positive_rate_ppm",
                      "total_hits")


def stage_compact(agg):
    """A compact per-stage metric projection (P1-4: score per stage -- raw / post-filter / packet)."""
    return {k: agg[k] for k in _STAGE_METRIC_KEYS if k in agg}


# ------------------------------------------------------------------ report rendering

def _ratio_str(ppm_val):
    sign = "-" if ppm_val < 0 else ""
    v = abs(ppm_val)
    return "%s%d.%06d" % (sign, v // PPM, v % PPM)


def render_markdown(report):
    raw = report["aggregate_raw"]
    rr = report["aggregate_reranked"]
    kvals = raw["k_values"]
    L = []
    L.append("# Retrieval evaluation report (eval-0.2)")
    L.append("")
    L.append("- generator: `%s` v%s" % (report["generator"]["name"], report["generator"]["version"]))
    L.append("- schema: `%s`" % report["schema"])
    L.append("- benchmark: `%s` (schema `%s`)" % (report["benchmark_id"], report["benchmark_schema"]))
    L.append("- retriever: `%s`" % report["retriever"]["kind"])
    L.append("- input_digest: `%s`" % report["input_digest"])
    L.append("- provenance corpus: `%s`" % ("present" if report["provenance_validated"] else "absent (presence-only)"))
    L.append("- vector channel: `%s`" % report["vector_channel_status"])
    L.append("- queries: %d | retrieval_depth: %d | ratios in ppm (parts-per-million)"
             % (raw["num_queries"], raw["retrieval_depth"]))
    L.append("")
    L.append("## Aggregate metrics (raw retriever order)")
    L.append("")
    L.append("| metric | value | ppm |")
    L.append("|---|---|---|")
    for k in kvals:
        ks = str(k)
        L.append("| recall@%s (macro) | %s | %d |" % (ks, _ratio_str(raw["recall_at_k_ppm"][ks]), raw["recall_at_k_ppm"][ks]))
    for k in kvals:
        ks = str(k)
        L.append("| precision@%s | %s | %d |" % (ks, _ratio_str(raw["precision_at_k_ppm"][ks]), raw["precision_at_k_ppm"][ks]))
    for k in kvals:
        ks = str(k)
        L.append("| nDCG@%s | %s | %d |" % (ks, _ratio_str(raw["ndcg_at_k_ppm"][ks]), raw["ndcg_at_k_ppm"][ks]))
    for k in kvals:
        ks = str(k)
        L.append("| source-diversity@%s | %s | %d |" % (ks, _ratio_str(raw["source_diversity_at_k_ppm"][ks]), raw["source_diversity_at_k_ppm"][ks]))
    L.append("| MRR | %s | %d |" % (_ratio_str(raw["mrr_ppm"]), raw["mrr_ppm"]))
    L.append("| evidence-group coverage | %s | %d |" % (_ratio_str(raw["evidence_group_coverage_ppm"]), raw["evidence_group_coverage_ppm"]))
    L.append("| stale-source rate | %s | %d |" % (_ratio_str(raw["stale_source_rate_ppm"]), raw["stale_source_rate_ppm"]))
    L.append("| stale-hit rate | %s | %d |" % (_ratio_str(raw["stale_hit_rate_ppm"]), raw["stale_hit_rate_ppm"]))
    L.append("| forbidden-hit rate | %s | %d |" % (_ratio_str(raw["forbidden_hit_rate_ppm"]), raw["forbidden_hit_rate_ppm"]))
    L.append("| privacy-hit rate | %s | %d |" % (_ratio_str(raw["privacy_hit_rate_ppm"]), raw["privacy_hit_rate_ppm"]))
    L.append("| judged-irrelevant rate | %s | %d |" % (_ratio_str(raw["judged_irrelevant_rate_ppm"]), raw["judged_irrelevant_rate_ppm"]))
    L.append("| duplicate burden | %s | %d |" % (_ratio_str(raw["duplicate_burden_ppm"]), raw["duplicate_burden_ppm"]))
    L.append("| relevant-token ratio | %s | %d |" % (_ratio_str(raw["relevant_token_ratio_ppm"]), raw["relevant_token_ratio_ppm"]))
    L.append("| provenance completeness | %s | %d |" % (_ratio_str(raw["provenance_completeness_ppm"]), raw["provenance_completeness_ppm"]))
    L.append("| provenance validity | %s | %d |" % (_ratio_str(raw["provenance_validity_ppm"]), raw["provenance_validity_ppm"]))
    L.append("| snippet-span correctness | %s | %d |" % (_ratio_str(raw["snippet_span_correctness_ppm"]), raw["snippet_span_correctness_ppm"]))
    L.append("| no-answer false-positive rate | %s | %d |" % (_ratio_str(raw["no_answer_false_positive_rate_ppm"]), raw["no_answer_false_positive_rate_ppm"]))
    L.append("| queries with all required present | %d / %d |  |" % (raw["queries_all_required_present"], raw["num_queries"]))
    L.append("")
    L.append("## Reranker A/B (reranked - raw)")
    L.append("")
    ab = report["rerank_ab"]
    L.append("- queries with a required source RESCUED into top-K by reranking: %d" % ab["queries_with_rescue"])
    L.append("- queries with a stale/forbidden hit DEMOTED out of top-1 by reranking: %d" % ab["queries_with_demote"])
    L.append("")
    L.append("| metric | raw | reranked | delta |")
    L.append("|---|---|---|---|")
    for k in kvals:
        ks = str(k)
        L.append("| nDCG@%s | %s | %s | %s |" % (ks, _ratio_str(raw["ndcg_at_k_ppm"][ks]), _ratio_str(rr["ndcg_at_k_ppm"][ks]), _ratio_str(ab["deltas"]["ndcg_at_%s_ppm" % ks])))
    for k in kvals:
        ks = str(k)
        L.append("| precision@%s | %s | %s | %s |" % (ks, _ratio_str(raw["precision_at_k_ppm"][ks]), _ratio_str(rr["precision_at_k_ppm"][ks]), _ratio_str(ab["deltas"]["precision_at_%s_ppm" % ks])))
    L.append("| evidence-group coverage | %s | %s | %s |" % (_ratio_str(raw["evidence_group_coverage_ppm"]), _ratio_str(rr["evidence_group_coverage_ppm"]), _ratio_str(ab["deltas"]["evidence_group_coverage_ppm"])))
    L.append("| forbidden-hit rate | %s | %s | %s |" % (_ratio_str(raw["forbidden_hit_rate_ppm"]), _ratio_str(rr["forbidden_hit_rate_ppm"]), _ratio_str(ab["deltas"]["forbidden_hit_rate_ppm"])))
    L.append("| stale-hit rate | %s | %s | %s |" % (_ratio_str(raw["stale_hit_rate_ppm"]), _ratio_str(rr["stale_hit_rate_ppm"]), _ratio_str(ab["deltas"]["stale_hit_rate_ppm"])))
    L.append("")
    L.append("## Hybrid channel attribution (vector channel: %s)" % report["vector_channel_status"])
    L.append("")
    L.append("| query | lexical hits | vector hits | rescued-by-vector | lexical-harmed-by-fusion | fusion reordered |")
    L.append("|---|---|---|---|---|---|")
    for h in report["hybrid_attribution"]:
        L.append("| %s | %d | %d | %d | %d | %s |" % (
            h["query_id"], h["lexical_hit_count"], h["vector_hit_count"],
            len(h["required_rescued_by_vector"]), h["lexical_exactmatch_harmed_by_fusion"],
            str(h["fusion_reordered_vs_lexical"]).lower()))
    L.append("")
    sp = report["selection_policy"]
    L.append("## Selection policy + per-stage metrics")
    L.append("")
    L.append("- selection policy: `%s` v%s (rrf_k=%d); stages: %s"
             % (sp["policy_id"], sp["policy_version"], sp["rrf_k"], ", ".join(sp["stages"])))
    L.append("- hybrid applicability: `%s` -- %s" % (report["hybrid_applicability"]["status"],
                                                     report["hybrid_applicability"]["note"]))
    L.append("")
    sm = report["stage_metrics"]
    L.append("| metric | raw | post_filter | packet |")
    L.append("|---|---|---|---|")
    for k in kvals:
        ks = str(k)
        L.append("| recall@%s | %s | %s | %s |" % (
            ks, _ratio_str(sm["raw"]["recall_at_k_ppm"][ks]), _ratio_str(sm["post_filter"]["recall_at_k_ppm"][ks]),
            _ratio_str(sm["packet"]["recall_at_k_ppm"][ks])))
    for label, key in (("forbidden-hit rate", "forbidden_hit_rate_ppm"), ("stale-hit rate", "stale_hit_rate_ppm"),
                       ("duplicate burden", "duplicate_burden_ppm"), ("provenance validity", "provenance_validity_ppm")):
        L.append("| %s | %s | %s | %s |" % (label, _ratio_str(sm["raw"][key]),
                                            _ratio_str(sm["post_filter"][key]), _ratio_str(sm["packet"][key])))
    L.append("| total hits | %d | %d | %d |" % (sm["raw"]["total_hits"], sm["post_filter"]["total_hits"],
                                                sm["packet"]["total_hits"]))
    L.append("")
    sc = report.get("selection_conformance")
    if sc is not None:
        L.append("## Selection conformance (i33 / D-0096)")
        L.append("")
        L.append("- namespace CLOSURE (U1'): %d isolation violation(s) + %d diagnostic-array leak(s) over %d query(ies) with a closure set; %d candidate(s) dropped (sanitized)"
                 % (sc["namespace_isolation_violations"], sc["cross_namespace_in_ranked_total"],
                    sc["queries_with_allowed_namespaces"], sc["namespace_violations_total"]))
        L.append("- current_only (U4): %d status-stale leak(s) over %d current_only query(ies)"
                 % (sc["current_only_stale_leaks"], sc["queries_current_only"]))
        L.append("- pool-INDEPENDENT current_only (U4'): %d leak(s) over %d not-effective-current candidate(s)"
                 % (sc["pool_independent_current_only_leaks"], sc["noncurrent_candidates_total"]))
        L.append("- supersession ordering (U4): %d/%d selected superseded/successor pair(s) correctly ordered; %d violation(s); %d branch conflict(s)"
                 % (sc["supersession_pairs_correct"], sc["supersession_pairs_total"],
                    sc["supersession_order_violations"], sc["queries_with_supersession_branch"]))
        L.append("- conflicts (U4'): %d query(ies) surfaced a contradicts pair; %d query(ies) conflicted"
                 % (sc["queries_with_contradicts"], sc["queries_conflicted"]))
        L.append("- reason-code coverage: %d codes -- %s" % (sc["reason_code_coverage_count"],
                 ", ".join("`%s`" % c for c in sc["reason_code_coverage"])))
        L.append("")
    de = report["packet_disposition_eval"]
    L.append("## Packet disposition (P0-3)")
    L.append("")
    if de["scored"]:
        L.append("- disposition accuracy: %d / %d correct (%s)"
                 % (de["num_correct"], de["num_labeled"], _ratio_str(de["accuracy_ppm"])))
        L.append("")
        L.append("| query | expected | actual | source | correct |")
        L.append("|---|---|---|---|---|")
        for r in de["per_query"]:
            if r["expected"] is None:
                continue
            L.append("| %s | %s | %s | %s | %s |" % (r["query_id"], r["expected"], r["actual"],
                                                     r["source"], str(r["correct"]).lower()))
    else:
        L.append("- no `expected_packet_disposition` labels in this benchmark; dispositions computed only.")
    L.append("")
    L.append("## Per-query (raw order)")
    L.append("")
    for q in report["per_query_raw"]:
        L.append("### %s -- %s" % (q["query_id"], q["query"]))
        L.append("- temporal_intent: %s | relevant_labels: %d | no_answer_expected: %s"
                 % (q["temporal_intent"], q["num_relevant_labels"], str(q["no_answer_expected"]).lower()))
        parts = []
        for k in kvals:
            ks = str(k)
            parts.append("recall@%s=%s (%d/%d)" % (ks, _ratio_str(q["recall_at_k_ppm"][ks]), q["matched_at_k"][ks], q["num_required"]))
        L.append("- " + " | ".join(parts))
        pp = []
        for k in kvals:
            ks = str(k)
            pp.append("P@%s=%s" % (ks, _ratio_str(q["precision_at_k_ppm"][ks])))
            pp.append("nDCG@%s=%s" % (ks, _ratio_str(q["ndcg_at_k_ppm"][ks])))
        L.append("- " + " | ".join(pp))
        L.append("- first_relevant_rank: %d | RR: %s | all_required_present: %s | evidence_group_coverage: %s"
                 % (q["first_relevant_rank"], _ratio_str(q["reciprocal_rank_ppm"]),
                    str(q["all_required_present"]).lower(), _ratio_str(q["evidence_group_coverage_ppm"])))
        L.append("- provenance: complete %d/%d, valid %d/%d, snippet-span %d/%d | no_answer_FP: %s | abstained: %s"
                 % (q["provenance_complete"], q["provenance_total"], q["provenance_valid"], q["provenance_total"],
                    q["snippet_span_correct"], q["provenance_total"], str(q["no_answer_false_positive"]).lower(),
                    str(q["abstained"]).lower()))
        if q["missing_required"]:
            L.append("- MISSING required: " + ", ".join(
                m["source_path"] + (" [span:%s]" % m["span_label"] if m.get("span_label") else "") for m in q["missing_required"]))
        if q["explicit_stale_hits"]:
            L.append("- STALE hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["explicit_stale_hits"]))
        if q["wrong_version_hits"]:
            L.append("- WRONG-VERSION hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["wrong_version_hits"]))
        if q["forbidden_hits"]:
            L.append("- FORBIDDEN hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["forbidden_hits"]))
        if q["privacy_hits"]:
            L.append("- PRIVACY-EXCLUSION hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["privacy_hits"]))
        if q["distractor_hits"]:
            L.append("- DISTRACTOR hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["distractor_hits"]))
        L.append("- returned (%d):" % len(q["returned"]))
        for r in q["returned"]:
            L.append("  %d. `%s` [%s] score=%d rel=%s prov=%s%s"
                     % (r["rank"], r["source_path"], r["span_label"], r["score"],
                        "1" if r["relevant"] else "0",
                        "valid" if r["provenance_valid"] else "INVALID",
                        "" if r["provenance_valid"] else (" {" + ",".join(r["provenance_failed_checks"]) + "}")))
        L.append("")
    return ("\n".join(L).rstrip() + "\n")


# ------------------------------------------------------------------ input digest + driver

def compute_input_digest(benchmark, retriever_spec, k_values, retrieval_depth, corpus_manifest):
    material = {
        "report_schema": REPORT_SCHEMA,
        "benchmark_id": benchmark.get("benchmark_id"),
        "queries": benchmark.get("queries", []),
        "retriever_kind": retriever_spec.get("kind"),
        "retriever_spec": {k: v for k, v in retriever_spec.items() if k != "corpus_dir"},
        "corpus": corpus_manifest,
        "k_values": list(k_values),
        "retrieval_depth": retrieval_depth,
    }
    return "sha256:" + sha256_hex(canon_bytes(material))


def resolve_benchmark_path(request):
    b = request.get("benchmark")
    if isinstance(b, str):
        return b if os.path.isabs(b) else os.path.abspath(os.path.join(os.getcwd(), b))
    return None


def load_benchmark(request):
    b = request.get("benchmark")
    if isinstance(b, str):
        path = resolve_benchmark_path(request)
        with open(path, "rb") as fh:
            return json.loads(normalized_text(fh.read()))
    if isinstance(b, dict):
        return b
    raise ValueError("request.benchmark must be a path or an inline object")


def run(request):
    t_start = time.time()
    out_dir = request.get("out_dir")
    if not out_dir:
        raise ValueError("request.out_dir is required")
    os.makedirs(out_dir, exist_ok=True)

    base_dir = request.get("base_dir")
    if not base_dir:
        bp = resolve_benchmark_path(request)
        base_dir = os.path.dirname(bp) if bp else os.path.abspath(out_dir)
    base_dir = os.path.abspath(base_dir)

    benchmark = load_benchmark(request)
    bschema = benchmark.get("schema", BENCHMARK_SCHEMA)
    queries = benchmark.get("queries", [])
    if not isinstance(queries, list) or not queries:
        raise ValueError("benchmark has no queries")
    seen_ids = set()
    for q in queries:
        qid = q.get("query_id")
        if not qid:
            raise ValueError("every query needs a query_id")
        if qid in seen_ids:
            raise ValueError("duplicate query_id: %s" % qid)
        seen_ids.add(qid)
        if "query" not in q:
            raise ValueError("query %s missing 'query' text" % qid)
        ti = q.get("temporal_intent", "current_only")
        if ti not in TEMPORAL_INTENTS:
            raise ValueError("query %s has invalid temporal_intent: %s" % (qid, ti))

    retriever_spec = request.get("retriever") or benchmark.get("retriever")
    if not retriever_spec:
        raise ValueError("no retriever spec (request.retriever or benchmark.retriever)")
    retriever_spec = dict(retriever_spec)
    if request.get("corpus_dir"):
        retriever_spec["corpus_dir"] = request["corpus_dir"]
    elif "corpus_dir" not in retriever_spec and benchmark.get("corpus_dir"):
        retriever_spec["corpus_dir"] = benchmark["corpus_dir"]

    k_values = request.get("k_values") or benchmark.get("k_values") or [1, 3, 5, 10]
    k_values = sorted(set(int(k) for k in k_values))
    retrieval_depth = int(request.get("retrieval_depth") or benchmark.get("retrieval_depth") or max(k_values))
    if retrieval_depth < max(k_values):
        retrieval_depth = max(k_values)

    python_exe = request.get("python") or sys.executable
    retriever = build_retriever(retriever_spec, base_dir, python_exe)
    corpus_manifest = retriever.corpus_manifest() if hasattr(retriever, "corpus_manifest") else None

    prov_dir = request.get("provenance_corpus_dir") or benchmark.get("provenance_corpus_dir")
    if not prov_dir:
        prov_dir = request.get("corpus_dir") or benchmark.get("corpus_dir")
    resolved_prov = None
    if prov_dir:
        resolved_prov = prov_dir if os.path.isabs(prov_dir) else os.path.join(base_dir, prov_dir)
    elif isinstance(retriever, LexicalBaselineRetriever):
        resolved_prov = retriever.resolved_corpus_dir
    corpus = ProvenanceCorpus(resolved_prov) if resolved_prov else ProvenanceCorpus(None)

    tombstones = benchmark.get("tombstones", [])

    default_budget = benchmark.get("selection_budget") if isinstance(benchmark.get("selection_budget"), dict) else None

    per_query_raw = []
    per_query_reranked = []
    per_query_packet = []
    per_query_selconf = []
    dispo_records = []
    hybrid = []
    rerank_diag = []
    vector_seen = False
    for rawq in queries:
        q = normalize_query(rawq)
        q["tombstones"] = [{"source_path": norm_path(t.get("source_path", ""))} for t in tombstones]
        q["_all_positive_members"] = _positive_members(q)
        hits = retriever.search(q.get("query"), retrieval_depth, q.get("filters"))
        norm_hits = [h if "span_start" in h else normalize_hit(h, i + 1) for i, h in enumerate(hits)]
        for h in norm_hits:
            chs = h.get("retrieval_channels") or []
            if (h.get("vector_rank") is not None) or ("vector" in chs):
                vector_seen = True
        raw_eval = evaluate_ordering(q, norm_hits, k_values, retrieval_depth, corpus)
        descriptor = default_descriptor(rawq)
        reranked, diag = rerank(norm_hits, descriptor, q)
        rr_eval = evaluate_ordering(q, reranked, k_values, retrieval_depth, corpus)
        # PACKET STAGE (CONTEXT_PACKET_CONTRACT s4 stage 5-6): occurrence-preserving display dedup + budget.
        q_budget = rawq.get("selection_budget") if isinstance(rawq.get("selection_budget"), dict) else default_budget
        selres = select_packet(norm_hits, descriptor, q, q_budget)
        packet_hits = selres["selected"]
        pk_eval = evaluate_ordering(q, packet_hits, k_values, retrieval_depth, corpus)
        pk_eval["omission_manifest"] = selres["omission_manifest"]
        pk_eval["selection_policy_id"] = selres["policy_id"]
        pk_eval["packet_size"] = len(packet_hits)
        pk_eval["candidate_count"] = len(norm_hits)
        dispo_records.append(packet_disposition_record(rawq, q, packet_hits, norm_hits, corpus))
        per_query_selconf.append(selection_conformance(q, norm_hits, selres))  # i32 (D-0092) eval-0.4
        per_query_raw.append(raw_eval)
        per_query_reranked.append(rr_eval)
        per_query_packet.append(pk_eval)
        hybrid.append(hybrid_attribution(q, norm_hits, retrieval_depth))
        rerank_diag.append({"query_id": q.get("query_id"), "order": diag})

    agg_raw = aggregate(per_query_raw, k_values, retrieval_depth, "raw")
    agg_rr = aggregate(per_query_reranked, k_values, retrieval_depth, "reranked")
    agg_packet = aggregate(per_query_packet, k_values, retrieval_depth, "packet")
    sel_conf_agg = aggregate_selection_conformance(per_query_selconf)  # i32 (D-0092) eval-0.4
    ab = rerank_ab(per_query_raw, per_query_reranked, k_values)
    dispo = aggregate_disposition(dispo_records)
    vstatus = "active" if vector_seen else "empty"
    stage_metrics = {"raw": stage_compact(agg_raw), "post_filter": stage_compact(agg_rr),
                     "packet": stage_compact(agg_packet)}
    hybrid_applicability = {
        "vector_channel": vstatus,
        "status": "applicable" if vector_seen else "not_applicable",
        "note": ("hybrid channel active" if vector_seen else
                 "hybrid uplift/regression is not_applicable while the vector channel is EMPTY "
                 "(P1-4: not_applicable, NOT zero uplift)"),
    }
    input_digest = compute_input_digest(benchmark, retriever_spec, k_values, retrieval_depth, corpus_manifest)

    report = {
        "schema": REPORT_SCHEMA,
        "generator": {"name": GENERATOR_NAME, "version": GENERATOR_VERSION, "score_unit": SCORE_UNIT},
        "benchmark_id": benchmark.get("benchmark_id", "unnamed"),
        "benchmark_schema": bschema,
        "retriever": {"kind": retriever_spec.get("kind")},
        "input_digest": input_digest,
        "provenance_validated": bool(corpus.available),
        "vector_channel_status": vstatus,
        "selection_policy": {"policy_id": SELECTION_POLICY_ID, "policy_version": SELECTION_POLICY_VERSION,
                             "rrf_k": selpol.RRF_K_DEFAULT, "stages": list(selpol.STAGES),
                             # i33 (D-0096): the canonical namespace predicate + versioned classifier policy that
                             # #40 imports (packet identity, CONTEXT_PACKET_CONTRACT s6).
                             "namespace_policy_id": selpol.NS_POLICY_ID,
                             "namespace_policy_version": selpol.NS_POLICY_VERSION,
                             "classifier_policy_id": selpol.CLASSIFIER_POLICY_ID,
                             "classifier_policy_version": selpol.CLASSIFIER_POLICY_VERSION},
        "selection_conformance": sel_conf_agg,
        "hybrid_applicability": hybrid_applicability,
        "corpus": corpus_manifest,
        "aggregate_raw": agg_raw,
        "aggregate_reranked": agg_rr,
        "aggregate_packet": agg_packet,
        "stage_metrics": stage_metrics,
        "rerank_ab": ab,
        "rerank_diagnostics": rerank_diag,
        "hybrid_attribution": hybrid,
        "packet_disposition_eval": dispo,
        "per_query_raw": per_query_raw,
        "per_query_reranked": per_query_reranked,
        "per_query_packet": per_query_packet,
        "per_query_selection_conformance": per_query_selconf,
    }

    report_bytes = canon_bytes(report)
    report_json_path = os.path.join(out_dir, "report.json")
    with open(report_json_path, "wb") as fh:
        fh.write(report_bytes)

    md = render_markdown(report)
    report_md_bytes = md.encode("utf-8")
    report_md_path = os.path.join(out_dir, "report.md")
    with open(report_md_path, "wb") as fh:
        fh.write(report_md_bytes)

    elapsed_ms = int((time.time() - t_start) * 1000)  # VOLATILE -> summary only, never the canonical report
    summary = {
        "ok": True,
        "input_digest": input_digest,
        "benchmark_id": benchmark.get("benchmark_id", "unnamed"),
        "benchmark_schema": bschema,
        "retriever_kind": retriever_spec.get("kind"),
        "num_queries": agg_raw["num_queries"],
        "k_values": agg_raw["k_values"],
        "retrieval_depth": retrieval_depth,
        "ratio_unit": RATIO_UNIT,
        "provenance_validated": bool(corpus.available),
        "vector_channel_status": report["vector_channel_status"],
        "aggregate": agg_raw,
        "aggregate_reranked": agg_rr,
        "aggregate_packet": agg_packet,
        "stage_metrics": stage_metrics,
        "selection_policy": {"policy_id": SELECTION_POLICY_ID, "policy_version": SELECTION_POLICY_VERSION},
        "packet_disposition": {"scored": dispo["scored"], "num_labeled": dispo["num_labeled"],
                               "num_correct": dispo["num_correct"], "accuracy_ppm": dispo["accuracy_ppm"]},
        "selection_conformance": {  # i33 (D-0096) eval-0.5 compact
            "namespace_isolation_violations": sel_conf_agg["namespace_isolation_violations"],
            "namespace_closure_violations": sel_conf_agg["namespace_closure_violations"],
            "cross_namespace_in_ranked_total": sel_conf_agg["cross_namespace_in_ranked_total"],
            "namespace_violations_total": sel_conf_agg["namespace_violations_total"],
            "current_only_stale_leaks": sel_conf_agg["current_only_stale_leaks"],
            "pool_independent_current_only_leaks": sel_conf_agg["pool_independent_current_only_leaks"],
            "supersession_order_violations": sel_conf_agg["supersession_order_violations"],
            "supersession_pairs_total": sel_conf_agg["supersession_pairs_total"],
            "queries_with_supersession_branch": sel_conf_agg["queries_with_supersession_branch"],
            "queries_with_contradicts": sel_conf_agg["queries_with_contradicts"],
            "queries_conflicted": sel_conf_agg["queries_conflicted"],
            "reason_code_coverage_count": sel_conf_agg["reason_code_coverage_count"]},
        "rerank_ab": {"queries_with_rescue": ab["queries_with_rescue"],
                      "queries_with_demote": ab["queries_with_demote"], "deltas": ab["deltas"]},
        "report_json": {"path": os.path.abspath(report_json_path), "sha256": sha256_hex(report_bytes), "bytes": len(report_bytes)},
        "report_md": {"path": os.path.abspath(report_md_path), "sha256": sha256_hex(report_md_bytes), "bytes": len(report_md_bytes)},
        "resource": {"eval_wall_ms": elapsed_ms},  # volatile diagnostics (not in the canonical report)
        "error": None,
    }
    with open(os.path.join(out_dir, "worker-summary.json"), "wb") as fh:
        fh.write(canon_bytes(summary))
    return summary


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True, help="path to the request JSON")
    args = ap.parse_args(argv)
    with open(args.request, "rb") as fh:
        request = json.loads(normalized_text(fh.read()))
    try:
        summary = run(request)
        sys.stdout.write("OK %s\n" % request.get("out_dir"))
        return 0
    except Exception as e:
        err = {"ok": False, "error": {"code": "retrieval_eval_failed", "message": str(e), "retryable": False}}
        out_dir = request.get("out_dir")
        if out_dir:
            try:
                os.makedirs(out_dir, exist_ok=True)
                with open(os.path.join(out_dir, "worker-summary.json"), "wb") as fh:
                    fh.write(canon_bytes(err))
            except Exception:
                pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"], sort_keys=True))
        log("ERROR: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
