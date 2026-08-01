#!/usr/bin/env python3
# retrieval_eval.py -- deterministic core of the retrieval-evaluation harness (Life Orchestrator
# module 37 `retrieval.eval`, contract v0.2, Wave 1 CPU lane, plan fo-25-3b718a13).
#
# WHAT THIS IS
#   A benchmark runner that measures the quality of ANY retriever satisfying the D-0077 retriever
#   interface (op `search`; inputs {query, k, filters?}; result = ranked array of
#   {source_path, content_hash, chunk_id, span, score, snippet} in DETERMINISTIC order). It ships:
#     * a LEXICAL BASELINE retriever (deterministic BM25-lite over a fixture corpus) -> a KNOWN baseline,
#     * an EXTERNAL_COMMAND adapter (invoke any conforming retriever; the seam the orchestrator points
#       at the real artifact.search at fold),
#     * metrics: recall@K, MRR, stale-source rate, provenance completeness (+ forbidden-hit rate),
#     * two reports: report.json (machine, canonical) + report.md (human), BOTH deterministic.
#
# DETERMINISM DISCIPLINE (so a re-run -- same corpus+queries+retriever -- is byte-identical, cross-machine):
#   * content_hash is EOL-NORMALIZED: sha256 of the file's UTF-8 text with newlines -> LF and BOM stripped,
#     so a CRLF (Windows) vs LF (cloud) checkout hashes identically.
#   * canonical JSON: sort_keys, ensure_ascii, compact separators, one trailing LF, UTF-8 no BOM.
#   * NO floats in the canonical output. BM25 scores are rounded to integer MILLIONTHS (score_unit);
#     every ratio metric is an integer PPM (parts-per-million) computed by integer round-half-up.
#   * NO volatile fields in either report (no timestamps / invocation ids / absolute paths / host).
#   The lifeorch.skill.result/0.1 envelope (emitted by the pwsh entrypoint) carries the volatile
#   diagnostics; THESE report artifacts stay canonical.
#
# INVOCATION (by the pwsh entrypoint; also runnable directly):
#   python3 retrieval_eval.py --request <request.json>
#   request = {
#     "benchmark": <path-relative-to-base_dir | inline benchmark object>,
#     "base_dir":  <dir used to resolve relative corpus/argv paths; default = benchmark file's dir>,
#     "corpus_dir": <override; else benchmark.corpus_dir>,
#     "retriever":  <override spec; else benchmark.retriever>,
#     "k_values":   <override; else benchmark.k_values; else [1,3,5,10]>,
#     "retrieval_depth": <override; else benchmark.retrieval_depth; else max(k_values)>,
#     "out_dir":    <where report.json / report.md / worker-summary.json are written>,
#     "python":     <python exe to substitute for {PYTHON} in an external retriever argv>
#   }
#   Writes out_dir/{report.json, report.md, worker-summary.json}; prints one line "OK <out_dir>" (exit 0)
#   or "ERR <json>" (exit 1). All logging goes to stderr.

import sys
import os
import io
import re
import json
import math
import hashlib
import argparse
import subprocess

GENERATOR_NAME = "retrieval.eval"
GENERATOR_VERSION = "0.1.0"
REPORT_SCHEMA = "lifeorch.retrieval_eval_report/0.1"
BENCHMARK_SCHEMA = "lifeorch.retrieval_benchmark/0.1"
SCORE_UNIT = "millionths"
RATIO_UNIT = "ppm"
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_TOKEN_RE = re.compile(r"[a-z0-9]+")

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
    return (numer * 1000000 + denom // 2) // denom


def mean_ppm(values):
    """Round-half-up integer mean of a list of ppm integers. Empty -> 0."""
    n = len(values)
    if n == 0:
        return 0
    return (sum(values) + n // 2) // n


def score_to_millionths(x):
    """Round a non-negative float score to integer millionths, round-half-up."""
    if x <= 0:
        return 0
    return int(math.floor(x * 1000000.0 + 0.5))


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


# ------------------------------------------------------------------ lexical baseline retriever

class Chunk:
    __slots__ = ("source_path", "content_hash", "chunk_id", "span", "text", "tokens", "tf", "length")

    def __init__(self, source_path, content_hash, chunk_id, span, text):
        self.source_path = source_path
        self.content_hash = content_hash
        self.chunk_id = chunk_id
        self.span = span
        self.text = text
        self.tokens = content_tokens(text)
        self.length = len(self.tokens)
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


def _chunk_markdown(rel, content_hash, text):
    """Split by ATX headings; a pre-heading preamble is its own chunk. span = heading path."""
    lines = text.split("\n")
    chunks = []
    # find heading line indices
    heads = []  # (line_index, level, title)
    for i, ln in enumerate(lines):
        m = re.match(r"^(#{1,6})\s+(.*\S)\s*$", ln)
        if m:
            heads.append((i, len(m.group(1)), m.group(2).strip()))
    # segments: [start_line, end_line) with an associated heading path
    segments = []
    if not heads or heads[0][0] > 0:
        first = heads[0][0] if heads else len(lines)
        segments.append((0, first, "(preamble)"))
    path_stack = []  # (level, title)
    for idx, (li, level, title) in enumerate(heads):
        end = heads[idx + 1][0] if idx + 1 < len(heads) else len(lines)
        while path_stack and path_stack[-1][0] >= level:
            path_stack.pop()
        path_stack.append((level, title))
        span = " > ".join(t for _, t in path_stack)
        segments.append((li, end, span))
    ci = 0
    for (start, end, span) in segments:
        seg_text = "\n".join(lines[start:end]).strip()
        if seg_text == "":
            continue
        chunks.append(Chunk(rel, content_hash, "%s#%03d" % (rel, ci), span, seg_text))
        ci += 1
    if not chunks:
        chunks.append(Chunk(rel, content_hash, "%s#000" % rel, "(document)", text.strip()))
    return chunks


def _chunk_text(rel, content_hash, text):
    """Split a plain-text file into blank-line-separated paragraphs. span = line range."""
    lines = text.split("\n")
    chunks = []
    ci = 0
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() == "":
            if start is not None:
                seg = "\n".join(lines[start:i]).strip()
                if seg:
                    span = "(lines %d-%d)" % (start + 1, i)
                    chunks.append(Chunk(rel, content_hash, "%s#%03d" % (rel, ci), span, seg))
                    ci += 1
                start = None
        else:
            if start is None:
                start = i
    if start is not None:
        seg = "\n".join(lines[start:]).strip()
        if seg:
            span = "(lines %d-%d)" % (start + 1, len(lines))
            chunks.append(Chunk(rel, content_hash, "%s#%03d" % (rel, ci), span, seg))
            ci += 1
    if not chunks:
        chunks.append(Chunk(rel, content_hash, "%s#000" % rel, "(document)", text.strip()))
    return chunks


class LexicalBaselineRetriever:
    """Deterministic BM25-lite over a fully-known fixture corpus. Returns already-ranked hits.

    Ranking key: (-score_millionths, source_path, chunk_id) ascending -> a stable, cross-platform
    tie-break. Chunks with zero query-term overlap (score 0) are NEVER returned (a lexical retriever
    surfaces only matching chunks -> recall stays meaningful)."""

    KIND = "lexical_baseline"

    def __init__(self, spec, base_dir):
        corpus_dir = spec.get("corpus_dir")
        if not corpus_dir:
            raise ValueError("lexical_baseline retriever requires corpus_dir")
        self.corpus_dir_label = norm_path(corpus_dir)
        cdir = corpus_dir if os.path.isabs(corpus_dir) else os.path.join(base_dir, corpus_dir)
        cdir = os.path.abspath(cdir)
        if not os.path.isdir(cdir):
            raise ValueError("corpus_dir not found: %s" % self.corpus_dir_label)
        self.k1 = float(spec.get("k1", 1.5))
        self.b = float(spec.get("b", 0.75))
        include = spec.get("include_suffixes", [".md", ".txt"])
        include_suffixes = set(s.lower() for s in include) if include else None
        exclude_dir_names = set(spec.get("exclude_dir_names", []))
        self.chunks = []
        self.sources = {}  # rel -> content_hash
        for rel, full, suffix in _iter_corpus_files(cdir, include_suffixes, exclude_dir_names):
            with open(full, "rb") as fh:
                text = normalized_text(fh.read())
            chash = content_hash_of_text(text)
            self.sources[rel] = chash
            if suffix == ".md":
                self.chunks.extend(_chunk_markdown(rel, chash, text))
            else:
                self.chunks.extend(_chunk_text(rel, chash, text))
        # BM25 corpus statistics (over chunks)
        self.N = len(self.chunks)
        self.avgdl = (sum(c.length for c in self.chunks) / float(self.N)) if self.N else 0.0
        df = {}
        for c in self.chunks:
            for term in c.tf.keys():
                df[term] = df.get(term, 0) + 1
        self.df = df

    def _idf(self, term):
        n = self.df.get(term, 0)
        if n == 0:
            return 0.0
        # BM25+ style non-negative idf
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
        for sm, c in scored[: max(0, int(k))]:
            hits.append({
                "source_path": c.source_path,
                "content_hash": c.content_hash,
                "chunk_id": c.chunk_id,
                "span": c.span,
                "score": sm,
                "snippet": snippet_of(c.text),
            })
        return hits

    def corpus_manifest(self):
        return {"corpus_dir": self.corpus_dir_label,
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
    """Invoke any conforming retriever as a subprocess (the seam the orchestrator points at the real
    artifact.search at fold). The request {query,k,filters} is delivered via stdin|file|arg; stdout is
    parsed as JSON and `hits_pointer` (a dotted path, default 'result.hits') navigates to the ranked
    hits array. The retriever OWNS its ranking -- returned order is authoritative (rank = index+1)."""

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
                aa = self._subst(a, request_file=request_file, request_json=request_json)
                # resolve a relative script path (argv[1..]) against base_dir when it exists there
                argv.append(aa)
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
            for h in hits_raw[: max(0, int(k))]:
                ch = h.get("content_hash")
                if not ch and h.get("version_id"):
                    ch = h.get("version_id")
                hits.append({
                    "source_path": norm_path(h.get("source_path", "")),
                    "content_hash": ch or "",
                    "chunk_id": str(h.get("chunk_id", "")),
                    "span": str(h.get("span", "")),
                    "score": h.get("score", 0),
                    "snippet": str(h.get("snippet", "")),
                })
            return hits
        finally:
            if tmp is not None and os.path.exists(tmp):
                try:
                    os.remove(tmp)
                except OSError:
                    pass


def build_retriever(spec, base_dir, python_exe):
    kind = spec.get("kind")
    if kind == LexicalBaselineRetriever.KIND:
        return LexicalBaselineRetriever(spec, base_dir)
    if kind == ExternalCommandRetriever.KIND:
        return ExternalCommandRetriever(spec, base_dir, python_exe)
    raise ValueError("unknown retriever kind: %r" % kind)


# ------------------------------------------------------------------ matching + metrics

def provenance_complete(hit):
    """A hit is fully attributable iff source_path + content_hash + chunk_id + span are all non-empty.
    content_hash may be a `sha256:<hex>` or an opaque non-empty version id."""
    if not str(hit.get("source_path", "")):
        return False
    if not str(hit.get("content_hash", "")):
        return False
    if not str(hit.get("chunk_id", "")):
        return False
    if not str(hit.get("span", "")):
        return False
    return True


def hit_matches_required(hit, req):
    if norm_path(hit["source_path"]) != norm_path(req["source_path"]):
        return False
    rch = req.get("content_hash")
    if rch and str(hit.get("content_hash", "")) != str(rch):
        return False  # wrong / stale version -> NOT a match
    if req.get("require_span") and req.get("span"):
        if str(hit.get("span", "")) != str(req["span"]):
            return False
    return True


def evaluate_query(q, hits, k_values, retrieval_depth):
    required = q.get("required_sources", [])
    stale = q.get("stale_sources", [])
    forbidden = q.get("forbidden_sources", [])
    depth_hits = hits[:retrieval_depth]

    # per-required first matching rank (1-indexed within depth); 0 = absent
    req_first_rank = []
    for req in required:
        rank = 0
        for i, h in enumerate(depth_hits):
            if hit_matches_required(h, req):
                rank = i + 1
                break
        req_first_rank.append(rank)

    matched_at = {}
    recall_ppm_at = {}
    for k in k_values:
        matched = sum(1 for r in req_first_rank if 0 < r <= k)
        matched_at[str(k)] = matched
        recall_ppm_at[str(k)] = ppm(matched, len(required)) if required else 1000000

    # MRR: first hit matching ANY required source
    first_relevant_rank = 0
    for i, h in enumerate(depth_hits):
        if any(hit_matches_required(h, req) for req in required):
            first_relevant_rank = i + 1
            break
    rr_ppm = ppm(1, first_relevant_rank) if first_relevant_rank > 0 else 0

    missing_required = []
    for req, rank in zip(required, req_first_rank):
        if rank == 0:
            m = {"source_path": norm_path(req["source_path"])}
            if req.get("require_span") and req.get("span"):
                m["span"] = req["span"]
            missing_required.append(m)

    # staleness within depth
    stale_set = set((norm_path(s["source_path"]), str(s.get("content_hash", ""))) for s in stale)
    req_by_path = {}
    for req in required:
        if req.get("content_hash"):
            req_by_path.setdefault(norm_path(req["source_path"]), str(req["content_hash"]))
    explicit_stale_hits = []
    wrong_version_hits = []
    for i, h in enumerate(depth_hits):
        hp = norm_path(h["source_path"])
        hc = str(h.get("content_hash", ""))
        if (hp, hc) in stale_set:
            explicit_stale_hits.append({"rank": i + 1, "source_path": hp, "content_hash": hc})
        elif hp in req_by_path and hc and hc != req_by_path[hp]:
            wrong_version_hits.append({"rank": i + 1, "source_path": hp, "content_hash": hc,
                                       "expected_content_hash": req_by_path[hp]})
    stale_affected = bool(explicit_stale_hits or wrong_version_hits)

    # forbidden within depth (path-only, or path+hash if hash given)
    forbidden_hits = []
    for i, h in enumerate(depth_hits):
        hp = norm_path(h["source_path"])
        hc = str(h.get("content_hash", ""))
        for f in forbidden:
            if norm_path(f["source_path"]) == hp and (not f.get("content_hash") or str(f["content_hash"]) == hc):
                forbidden_hits.append({"rank": i + 1, "source_path": hp})
                break

    prov_total = len(depth_hits)
    prov_complete = sum(1 for h in depth_hits if provenance_complete(h))

    returned = []
    for i, h in enumerate(depth_hits):
        returned.append({
            "rank": i + 1,
            "source_path": norm_path(h["source_path"]),
            "content_hash": str(h.get("content_hash", "")),
            "chunk_id": str(h.get("chunk_id", "")),
            "span": str(h.get("span", "")),
            "score": h.get("score", 0),
            "provenance_complete": provenance_complete(h),
        })

    return {
        "query_id": q.get("query_id"),
        "query": q.get("query"),
        "num_required": len(required),
        "matched_at_k": matched_at,
        "recall_at_k_ppm": recall_ppm_at,
        "first_relevant_rank": first_relevant_rank,
        "reciprocal_rank_ppm": rr_ppm,
        "all_required_present": (len(missing_required) == 0),
        "missing_required": missing_required,
        "explicit_stale_hits": explicit_stale_hits,
        "wrong_version_hits": wrong_version_hits,
        "stale_affected": stale_affected,
        "forbidden_hits": forbidden_hits,
        "provenance_total": prov_total,
        "provenance_complete": prov_complete,
        "returned": returned,
    }


def aggregate(per_query, k_values, retrieval_depth):
    n = len(per_query)
    recall_macro = {}
    recall_micro = {}
    for k in k_values:
        ks = str(k)
        recall_macro[ks] = mean_ppm([q["recall_at_k_ppm"][ks] for q in per_query]) if n else 0
        tot_matched = sum(q["matched_at_k"][ks] for q in per_query)
        tot_required = sum(q["num_required"] for q in per_query)
        recall_micro[ks] = ppm(tot_matched, tot_required) if tot_required else 1000000
    mrr = mean_ppm([q["reciprocal_rank_ppm"] for q in per_query]) if n else 0
    stale_rate = ppm(sum(1 for q in per_query if q["stale_affected"]), n) if n else 0
    forbidden_rate = ppm(sum(1 for q in per_query if q["forbidden_hits"]), n) if n else 0
    prov_total = sum(q["provenance_total"] for q in per_query)
    prov_complete = sum(q["provenance_complete"] for q in per_query)
    prov_completeness = ppm(prov_complete, prov_total) if prov_total else 1000000
    queries_all_required = sum(1 for q in per_query if q["all_required_present"])
    return {
        "num_queries": n,
        "k_values": list(k_values),
        "retrieval_depth": retrieval_depth,
        "ratio_unit": RATIO_UNIT,
        "recall_at_k_ppm": recall_macro,
        "recall_at_k_micro_ppm": recall_micro,
        "mrr_ppm": mrr,
        "stale_source_rate_ppm": stale_rate,
        "forbidden_hit_rate_ppm": forbidden_rate,
        "provenance_completeness_ppm": prov_completeness,
        "queries_all_required_present": queries_all_required,
        "total_hits": prov_total,
        "total_required": sum(q["num_required"] for q in per_query),
        "total_provenance_complete": prov_complete,
    }


# ------------------------------------------------------------------ report rendering

def _ratio_str(ppm_val):
    # "0.750000" style deterministic decimal from integer ppm
    return "%d.%06d" % (ppm_val // 1000000, ppm_val % 1000000)


def render_markdown(report):
    agg = report["aggregate"]
    kvals = agg["k_values"]
    L = []
    L.append("# Retrieval evaluation report")
    L.append("")
    L.append("- generator: `%s` v%s" % (report["generator"]["name"], report["generator"]["version"]))
    L.append("- schema: `%s`" % report["schema"])
    L.append("- benchmark: `%s` (schema `%s`)" % (report["benchmark_id"], report["benchmark_schema"]))
    L.append("- retriever: `%s`" % report["retriever"]["kind"])
    L.append("- input_digest: `%s`" % report["input_digest"])
    L.append("- queries: %d | retrieval_depth: %d | ratios in ppm (parts-per-million)"
             % (agg["num_queries"], agg["retrieval_depth"]))
    L.append("")
    L.append("## Aggregate metrics")
    L.append("")
    L.append("| metric | value | ppm |")
    L.append("|---|---|---|")
    for k in kvals:
        ks = str(k)
        L.append("| recall@%s (macro) | %s | %d |" % (ks, _ratio_str(agg["recall_at_k_ppm"][ks]), agg["recall_at_k_ppm"][ks]))
    for k in kvals:
        ks = str(k)
        L.append("| recall@%s (micro) | %s | %d |" % (ks, _ratio_str(agg["recall_at_k_micro_ppm"][ks]), agg["recall_at_k_micro_ppm"][ks]))
    L.append("| MRR | %s | %d |" % (_ratio_str(agg["mrr_ppm"]), agg["mrr_ppm"]))
    L.append("| stale-source rate | %s | %d |" % (_ratio_str(agg["stale_source_rate_ppm"]), agg["stale_source_rate_ppm"]))
    L.append("| forbidden-hit rate | %s | %d |" % (_ratio_str(agg["forbidden_hit_rate_ppm"]), agg["forbidden_hit_rate_ppm"]))
    L.append("| provenance completeness | %s | %d |" % (_ratio_str(agg["provenance_completeness_ppm"]), agg["provenance_completeness_ppm"]))
    L.append("| queries with all required present | %d / %d |  |" % (agg["queries_all_required_present"], agg["num_queries"]))
    L.append("")
    L.append("## Per-query")
    L.append("")
    for q in report["per_query"]:
        L.append("### %s -- %s" % (q["query_id"], q["query"]))
        parts = []
        for k in kvals:
            ks = str(k)
            parts.append("recall@%s=%s (%d/%d)" % (ks, _ratio_str(q["recall_at_k_ppm"][ks]), q["matched_at_k"][ks], q["num_required"]))
        L.append("- " + " | ".join(parts))
        L.append("- first_relevant_rank: %d | reciprocal_rank: %s | all_required_present: %s"
                 % (q["first_relevant_rank"], _ratio_str(q["reciprocal_rank_ppm"]), str(q["all_required_present"]).lower()))
        if q["missing_required"]:
            L.append("- MISSING required: " + ", ".join(
                m["source_path"] + (" [span:%s]" % m["span"] if m.get("span") else "") for m in q["missing_required"]))
        if q["explicit_stale_hits"]:
            L.append("- STALE hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["explicit_stale_hits"]))
        if q["wrong_version_hits"]:
            L.append("- WRONG-VERSION hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["wrong_version_hits"]))
        if q["forbidden_hits"]:
            L.append("- FORBIDDEN hits: " + ", ".join("%s@rank%d" % (h["source_path"], h["rank"]) for h in q["forbidden_hits"]))
        L.append("- returned (%d):" % len(q["returned"]))
        for r in q["returned"]:
            L.append("  %d. `%s` [%s] score=%d prov=%s"
                     % (r["rank"], r["source_path"], r["span"], r["score"], "ok" if r["provenance_complete"] else "INCOMPLETE"))
        L.append("")
    return ("\n".join(L).rstrip() + "\n")


# ------------------------------------------------------------------ input digest + driver

def compute_input_digest(benchmark, retriever_spec, k_values, retrieval_depth, corpus_manifest):
    material = {
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
    """Resolve the benchmark file path (absolute, or relative to CWD). Returns None for an inline object."""
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
    out_dir = request.get("out_dir")
    if not out_dir:
        raise ValueError("request.out_dir is required")
    os.makedirs(out_dir, exist_ok=True)

    # base_dir (resolves corpus_dir + external argv paths): explicit, else benchmark file's dir, else out_dir
    base_dir = request.get("base_dir")
    if not base_dir:
        bp = resolve_benchmark_path(request)
        base_dir = os.path.dirname(bp) if bp else os.path.abspath(out_dir)
    base_dir = os.path.abspath(base_dir)

    benchmark = load_benchmark(request)
    queries = benchmark.get("queries", [])
    if not isinstance(queries, list) or not queries:
        raise ValueError("benchmark has no queries")
    # validate query ids unique + required present
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

    retriever_spec = request.get("retriever") or benchmark.get("retriever")
    if not retriever_spec:
        raise ValueError("no retriever spec (request.retriever or benchmark.retriever)")
    retriever_spec = dict(retriever_spec)
    # corpus_dir override precedence: request > spec > benchmark
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

    per_query = []
    for q in queries:
        hits = retriever.search(q.get("query"), retrieval_depth, q.get("filters"))
        per_query.append(evaluate_query(q, hits, k_values, retrieval_depth))

    agg = aggregate(per_query, k_values, retrieval_depth)
    input_digest = compute_input_digest(benchmark, retriever_spec, k_values, retrieval_depth, corpus_manifest)

    report = {
        "schema": REPORT_SCHEMA,
        "generator": {"name": GENERATOR_NAME, "version": GENERATOR_VERSION, "score_unit": SCORE_UNIT},
        "benchmark_id": benchmark.get("benchmark_id", "unnamed"),
        "benchmark_schema": benchmark.get("schema", BENCHMARK_SCHEMA),
        "retriever": {"kind": retriever_spec.get("kind")},
        "input_digest": input_digest,
        "corpus": corpus_manifest,
        "aggregate": agg,
        "per_query": per_query,
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

    summary = {
        "ok": True,
        "input_digest": input_digest,
        "benchmark_id": benchmark.get("benchmark_id", "unnamed"),
        "retriever_kind": retriever_spec.get("kind"),
        "num_queries": agg["num_queries"],
        "k_values": agg["k_values"],
        "retrieval_depth": retrieval_depth,
        "ratio_unit": RATIO_UNIT,
        "aggregate": agg,
        "report_json": {"path": os.path.abspath(report_json_path), "sha256": sha256_hex(report_bytes), "bytes": len(report_bytes)},
        "report_md": {"path": os.path.abspath(report_md_path), "sha256": sha256_hex(report_md_bytes), "bytes": len(report_md_bytes)},
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
