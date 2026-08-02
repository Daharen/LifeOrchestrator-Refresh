#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
context_compiler.py -- Life Orchestrator Module 40 (skill `context.compile` 0.1.0)

The Collective Agent's context-packet compiler (directive Priority 4 / section 8.1-8.6).
DETERMINISTIC, CPU-only, NO model, NO network. Turns a task descriptor into a versioned,
token-budgeted `lifeorch.context_packet/0.1` artifact:

    normalize (8.1) -> candidate retrieval via a DEFINED seam (8.2)
    -> deterministic rerank + diversity (8.3) -> token budget with exact accounting (8.4/16.3)
    -> context_packet/0.1 with full source provenance + omitted-context + eval hooks (8.4/8.6)
    -> a deterministic `expand` seam (8.5).

It is the CONSUMER of the FROZEN MEMORY_CONTRACT retriever-0.2 hit shape (s3) and the PRODUCER
of context packets consumed by retrieval.eval #37 0.2 + a fresh 9B at the orchestrator fold (D-0077).

Stdlib only (json, hashlib, re, math, os, sys). The retriever is INJECTED (never called from
here): off-machine the entrypoint injects deterministic mock hits from a fixture; -Live the
entrypoint runs the real artifact.search #36 `search` op and injects the resulting 0.2 hits. The
compiler worker therefore performs NO I/O to other processes and is fully deterministic + testable.

Worker protocol (mirrors artifact_search.py): argv[1] is a JSON args file carrying the op inputs
plus `output_dir` and `meta_path`. The worker writes `meta_path` = {ok, op, result, worker,
runtime_ms, warnings, artifacts[]} and any artifact files under output_dir. `run(args)` is also
importable for off-machine python tests.
"""

import sys
import os
import re
import json
import math
import hashlib

WORKER_NAME = "context_compiler.py"
WORKER_VERSION = "0.1.0"
COMPILER_VERSION = "0.1.0"
PACKET_SCHEMA = "lifeorch.context_packet/0.1"
EXPANSION_SCHEMA = "lifeorch.context_expansion/0.1"

# ------------------------------------------------------------------------------------------------
# Deterministic primitives
# ------------------------------------------------------------------------------------------------

def canonical_json(obj):
    """Canonical JSON: sorted keys, compact, UTF-8, no ASCII escaping. The determinism substrate."""
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))

def sha256_hex(s):
    if isinstance(s, bytes):
        b = s
    else:
        b = s.encode("utf-8")
    return hashlib.sha256(b).hexdigest()

def sha256_of_obj(obj):
    return sha256_hex(canonical_json(obj))

def to_micros(x):
    """Deterministically fold a possibly-float score into integer millionths; None -> None.
    We NEVER store raw floats in the deterministic packet (float->JSON formatting is not portable)."""
    if x is None:
        return None
    try:
        return int(round(float(x) * 1000000))
    except (TypeError, ValueError):
        return None

# Token estimate: a fixed, documented heuristic -- NO tokenizer, NO model.
#   est_tokens(text) = ceil(code_point_count / 4).  (SCHEMA_NOTES s5.)
TOKEN_CHARS_PER_TOKEN = 4

def est_tokens(text):
    if not text:
        return 0
    return int(math.ceil(len(text) / float(TOKEN_CHARS_PER_TOKEN)))

# ------------------------------------------------------------------------------------------------
# Defaults / config (every knob documented in SCHEMA_NOTES; overridable via task/config)
# ------------------------------------------------------------------------------------------------

DEFAULT_CONFIG = {
    "token_budget": 2000,          # total excerpt-token budget for the packet body
    "per_source_cap": 3,           # max excerpts from any one source_path (diversity cap)
    "max_excerpts": 40,            # hard cap on excerpt count regardless of budget
    "per_excerpt_overhead_tokens": 12,  # fixed provenance-wrapper cost charged per included excerpt
    "primary_terms_cap": 6,        # terms AND-ed into the primary fts query
    "salient_terms_cap": 12,       # salient terms kept overall
    "literals_cap": 6,             # literal (exact) queries
    "paths_cap": 4,                # path-scoped queries
    "max_queries": 12,             # hard cap on the derived query set
    "candidate_k": 20,             # per-query K hint for the retriever seam
    "expand_max_tokens": 600,      # default budget for an expansion request
}

# authority_level -> points (higher = more authoritative). Unknown -> DERIVED default.
AUTHORITY_POINTS = {
    "governing": 320, "authoritative": 300, "canonical": 280,
    "source_material": 150, "derived": 100, "default": 80, "low": 40,
}
AUTHORITY_DEFAULT_POINTS = 80

# s5 currentness -> freshness points; `deleted` is DROPPED before selection.
FRESHNESS_POINTS = {
    "current": 200,
    "source_stale": 40, "derivation_stale": 40, "embedding_stale": 60,
    "relationship_stale": 60, "summary_stale": 40, "authority_stale": 30,
    "temporal_expiry": 20, "unverified": 30,
    "deleted": 0,
}
FRESHNESS_DEFAULT_POINTS = 50
STALE_SET = {k for k in FRESHNESS_POINTS if k not in ("current",)}

# record_kind priority points per task_type. Row 'default' applies when a task_type is unlisted.
# Columns are the CLOSED MEMORY_CONTRACT s1 kind enum + source_chunk.
KIND_ENUM = ["source_chunk", "symbol", "summary", "decision", "claim", "episode",
             "failure", "procedure", "skill", "reminder", "entity", "relationship"]
KIND_POINTS = {
    "coding":        {"symbol": 180, "source_chunk": 150, "failure": 140, "procedure": 130, "skill": 120,
                      "decision": 90, "relationship": 90, "summary": 70, "claim": 60, "entity": 60,
                      "episode": 80, "reminder": 20},
    "research":      {"summary": 170, "claim": 160, "decision": 150, "source_chunk": 140, "entity": 110,
                      "relationship": 100, "episode": 90, "failure": 70, "procedure": 60, "skill": 50,
                      "symbol": 60, "reminder": 20},
    "documentation": {"summary": 170, "source_chunk": 160, "decision": 140, "claim": 120, "symbol": 90,
                      "relationship": 90, "entity": 90, "procedure": 80, "skill": 70, "failure": 60,
                      "episode": 60, "reminder": 20},
    "life":          {"reminder": 190, "entity": 150, "episode": 130, "decision": 120, "claim": 110,
                      "summary": 110, "relationship": 100, "source_chunk": 90, "failure": 70,
                      "procedure": 80, "skill": 70, "symbol": 40},
    "verification":  {"failure": 180, "procedure": 160, "skill": 130, "source_chunk": 130, "decision": 120,
                      "claim": 110, "symbol": 110, "summary": 90, "relationship": 90, "entity": 70,
                      "episode": 100, "reminder": 20},
    "planning":      {"decision": 170, "procedure": 160, "summary": 150, "skill": 130, "claim": 120,
                      "failure": 120, "source_chunk": 110, "relationship": 100, "entity": 90,
                      "episode": 100, "symbol": 70, "reminder": 60},
    "default":       {"source_chunk": 140, "summary": 130, "decision": 120, "claim": 110, "symbol": 110,
                      "procedure": 110, "skill": 110, "failure": 110, "relationship": 90, "entity": 90,
                      "episode": 90, "reminder": 40},
}
KIND_DEFAULT_POINTS = 60

# Feature weights for the composite score (all integer; documented order in SCHEMA_NOTES).
RELEVANCE_BASE = 1000
RELEVANCE_STEP = 40      # per rank below 1
COVERAGE_BONUS = 30      # per additional distinct query that matched a candidate
NAMESPACE_MATCH_POINTS = 120
PATH_PREFIX_POINTS = 100
PATH_BASENAME_POINTS = 60

# The kinds carried as REFS in the packet (content owned elsewhere: #41 skill cards, #39 episodes/failures).
SKILL_KINDS = {"skill"}
PROCEDURE_KINDS = {"procedure"}
FAILURE_KINDS = {"failure"}
EPISODE_KINDS = {"episode"}
STATE_KINDS = {"decision", "summary"}  # authoritative current-state refs when authority is high

# ------------------------------------------------------------------------------------------------
# 8.1 Task normalization -> deterministic query set
# ------------------------------------------------------------------------------------------------

STOPWORDS = frozenset("""
a an the and or of to in on for with without into onto from by at as is are be been being this that these those
it its it's do does did done can could should would may might will shall must not no yes if then else when while
what which who whom whose how why where i we you they he she them us our your their my me build make made get got
please want need help using use used about over under out up down more most some any all each via per your you're
""".split())

# literal patterns kept verbatim for EXACT retrieval (decision ids, module/issue refs, dotted skill ids,
# quoted phrases). Order matters only for determinism; we normalize + dedup.
_RE_DECISION = re.compile(r"\bD-\d{3,5}\b", re.IGNORECASE)
_RE_MODREF = re.compile(r"#\d{1,4}\b")
_RE_DOTTED = re.compile(r"\b[a-z][a-z0-9]*\.[a-z][a-z0-9.]*[a-z0-9]\b", re.IGNORECASE)
_RE_QUOTED = re.compile(r"\"([^\"]{2,80})\"")
_RE_TERM = re.compile(r"[a-z0-9][a-z0-9_+#-]*")

def _norm_ws(s):
    return re.sub(r"\s+", " ", (s or "").strip())

def _dedup_keep_order(seq):
    seen = set()
    out = []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out

def derive_literals(text, cap):
    lits = []
    for m in _RE_QUOTED.finditer(text or ""):
        lits.append(_norm_ws(m.group(1)))
    for m in _RE_DECISION.finditer(text or ""):
        lits.append(m.group(0).upper())
    for m in _RE_MODREF.finditer(text or ""):
        lits.append(m.group(0))
    for m in _RE_DOTTED.finditer(text or ""):
        lits.append(m.group(0).lower())
    lits = _dedup_keep_order([l for l in lits if l])
    return lits[:cap]

def derive_terms(text, cap):
    toks = _RE_TERM.findall((text or "").lower())
    terms = [t for t in toks if len(t) >= 2 and t not in STOPWORDS and not t.isdigit()]
    return _dedup_keep_order(terms)[:cap]

def normalize_task(task, config):
    """Deterministically derive a normalized task statement + a bounded, deterministic query set.
    The original_goal is preserved verbatim and NEVER rewritten."""
    original_goal = task.get("original_goal", task.get("request_text", "")) or ""
    request_text = task.get("request_text", original_goal) or ""
    namespace = task.get("namespace", task.get("project_id"))
    task_type = (task.get("task_type") or "default").strip().lower() or "default"
    time_horizon = (task.get("time_horizon") or "current_only").strip().lower()
    relevant_paths = [p for p in (task.get("relevant_paths") or []) if p]
    relevant_entities = [e for e in (task.get("relevant_entities") or []) if e]

    salient_terms = derive_terms(request_text + " " + " ".join(relevant_entities),
                                 config["salient_terms_cap"])
    literals = derive_literals(request_text, config["literals_cap"])

    normalized_statement = "[{tt}] {rt}".format(tt=task_type, rt=_norm_ws(request_text))

    base_filters = {}
    if namespace:
        base_filters["namespace"] = namespace
    # Current-only tasks exclude stale sources from the *primary* retrieval; historical intents do not.
    exclude_stale = (time_horizon in ("current_only", "current", ""))

    queries = []

    def add_query(q, mode, purpose, extra_filters=None, kind=None):
        qtext = _norm_ws(q)
        if not qtext:
            return
        filters = dict(base_filters)
        if extra_filters:
            filters.update(extra_filters)
        if kind:
            filters["record_kind"] = kind
        if exclude_stale and purpose in ("primary", "path_scoped"):
            filters["exclude_stale"] = True
        queries.append({
            "query": qtext, "mode": mode, "purpose": purpose,
            "filters": filters, "k": config["candidate_k"],
        })

    # Q0 primary: AND of the top-N salient terms (fts).
    if salient_terms:
        add_query(" ".join(salient_terms[:config["primary_terms_cap"]]), "fts", "primary")

    # Literal exact queries (decision ids, refs, dotted skill ids, quoted phrases).
    for lit in literals:
        add_query(lit, "exact", "literal")

    # Path-scoped: primary terms restricted to each relevant path prefix + an exact filename query.
    for rp in relevant_paths[:config["paths_cap"]]:
        base = os.path.basename(rp.rstrip("/")) or rp
        add_query(base, "exact", "path")
        if salient_terms:
            add_query(" ".join(salient_terms[:config["primary_terms_cap"]]), "fts",
                      "path_scoped", extra_filters={"path_prefix": rp})

    # Kind-targeted recall so high-value non-chunk kinds are not drowned by chunks.
    hi_kinds = _high_value_kinds(task_type)
    for kind in hi_kinds:
        if salient_terms:
            add_query(" ".join(salient_terms[:config["primary_terms_cap"]]), "fts",
                      "kind:" + kind, kind=kind)

    # Dedup queries by (mode, query, canonical(filters)); cap.
    seen = set()
    deduped = []
    for q in queries:
        key = (q["mode"], q["query"], canonical_json(q["filters"]))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    deduped = deduped[:config["max_queries"]]
    for i, q in enumerate(deduped):
        q["query_index"] = i

    return {
        "original_goal": original_goal,
        "normalized_task": normalized_statement,
        "task_type": task_type,
        "time_horizon": time_horizon,
        "namespace": namespace,
        "salient_terms": salient_terms,
        "literals": literals,
        "relevant_paths": relevant_paths,
        "relevant_entities": relevant_entities,
        "exclude_stale": exclude_stale,
        "query_set": deduped,
    }

def _high_value_kinds(task_type):
    table = {
        "coding": ["failure", "procedure", "skill"],
        "verification": ["failure", "procedure", "skill"],
        "research": ["decision", "summary", "claim"],
        "planning": ["decision", "procedure", "summary"],
        "life": ["reminder", "entity"],
        "documentation": ["decision", "summary"],
        "default": ["failure", "procedure", "skill"],
    }
    return table.get(task_type, table["default"])

# ------------------------------------------------------------------------------------------------
# 8.2 candidate pool (from the injected retriever-0.2 batches) + 8.3 deterministic rerank/diversity
# ------------------------------------------------------------------------------------------------

def _hit_get(hit, name, default=None):
    v = hit.get(name, default)
    return v if v is not None else default

def _span_obj(hit):
    sp = hit.get("span")
    if isinstance(sp, dict) and "start" in sp and "end" in sp:
        try:
            return {"start": int(sp["start"]), "end": int(sp["end"])}
        except (TypeError, ValueError):
            return None
    return None

def build_candidate_pool(retrieval_batches):
    """Merge per-query 0.2-hit batches into a deterministic candidate pool keyed by record_version_id.
    Preserves each hit's 0.2 fields; records best (lowest) rank, best fused score, and query coverage.
    rank = index+1 within each batch is treated as authoritative and is NEVER re-sorted here."""
    pool = {}
    per_query_counts = {}
    for batch in (retrieval_batches or []):
        qidx = int(batch.get("query_index", 0))
        hits = batch.get("hits") or []
        per_query_counts[qidx] = len(hits)
        for pos, hit in enumerate(hits):
            rvid = hit.get("record_version_id")
            if not rvid:
                # fall back to a deterministic surrogate identity so nothing is silently dropped
                rvid = "anon_" + sha256_hex(canonical_json(hit))[:24]
            rank = hit.get("rank")
            try:
                rank = int(rank)
            except (TypeError, ValueError):
                rank = pos + 1
            fused_micros = to_micros(hit.get("fused_score"))
            entry = pool.get(rvid)
            if entry is None:
                entry = {"hit": hit, "record_version_id": rvid,
                         "best_rank": rank, "matched_queries": [qidx],
                         "best_fused_micros": fused_micros}
                pool[rvid] = entry
            else:
                if rank < entry["best_rank"]:
                    entry["best_rank"] = rank
                    entry["hit"] = hit  # keep the hit from the query where it ranked best
                if qidx not in entry["matched_queries"]:
                    entry["matched_queries"].append(qidx)
                if fused_micros is not None:
                    if entry["best_fused_micros"] is None or fused_micros > entry["best_fused_micros"]:
                        entry["best_fused_micros"] = fused_micros
    for e in pool.values():
        e["matched_queries"] = sorted(set(e["matched_queries"]))
    return pool, per_query_counts

def _authority_points(level):
    if not level:
        return AUTHORITY_DEFAULT_POINTS
    return AUTHORITY_POINTS.get(str(level).strip().lower(), AUTHORITY_DEFAULT_POINTS)

def _freshness_points(currentness):
    if not currentness:
        return FRESHNESS_POINTS["current"]
    return FRESHNESS_POINTS.get(str(currentness).strip().lower(), FRESHNESS_DEFAULT_POINTS)

def _kind_points(task_type, kind):
    row = KIND_POINTS.get(task_type, KIND_POINTS["default"])
    return row.get(kind, KIND_DEFAULT_POINTS)

def _currentness(hit):
    return (hit.get("currentness") or hit.get("status") or "current")

def score_candidate(entry, norm, config):
    """Deterministic integer composite score from the 8.3 features. Returns (score, feature_points)."""
    hit = entry["hit"]
    task_type = norm["task_type"]
    namespace = norm["namespace"]
    relevant_paths = norm["relevant_paths"]

    best_rank = entry["best_rank"]
    relevance = max(0, RELEVANCE_BASE - (best_rank - 1) * RELEVANCE_STEP)
    coverage = (len(entry["matched_queries"]) - 1) * COVERAGE_BONUS

    authority = _authority_points(hit.get("authority_level"))
    freshness = _freshness_points(_currentness(hit))
    kind = hit.get("record_kind") or "source_chunk"
    kindp = _kind_points(task_type, kind)

    ns_points = NAMESPACE_MATCH_POINTS if (namespace and hit.get("namespace") == namespace) else 0

    sp = (hit.get("source_path") or "")
    comp_points = 0
    for rp in relevant_paths:
        rpn = rp.replace("\\", "/").rstrip("/")
        if rpn and sp.replace("\\", "/").startswith(rpn):
            comp_points = max(comp_points, PATH_PREFIX_POINTS)
        elif rpn and os.path.basename(sp) == os.path.basename(rpn):
            comp_points = max(comp_points, PATH_BASENAME_POINTS)

    feats = {
        "relevance": relevance,
        "query_coverage": coverage,
        "authority": authority,
        "freshness": freshness,
        "kind_priority": kindp,
        "namespace_match": ns_points,
        "component_match": comp_points,
        "best_rank": best_rank,
        "matched_query_count": len(entry["matched_queries"]),
    }
    score = relevance + coverage + authority + freshness + kindp + ns_points + comp_points
    return score, feats

def _tie_break(entry):
    hit = entry["hit"]
    tbk = hit.get("tie_break_key")
    tbk = str(tbk) if tbk is not None else ""
    return (tbk, entry["record_version_id"])

def rank_candidates(pool, norm, config):
    """Score + order the pool. Returns a list of dicts (ranked, deterministic total order)."""
    scored = []
    for rvid, entry in pool.items():
        score, feats = score_candidate(entry, norm, config)
        scored.append({"entry": entry, "score": score, "features": feats,
                       "tie_break": _tie_break(entry)})
    # descending score, then ascending tie_break (stable, fully deterministic)
    scored.sort(key=lambda r: (-r["score"], r["tie_break"][0], r["tie_break"][1]))
    for i, r in enumerate(scored):
        r["rank_in_pool"] = i + 1
    return scored

# ------------------------------------------------------------------------------------------------
# excerpt text resolution + provenance validation
# ------------------------------------------------------------------------------------------------

def _read_span_bytes(path, start, end):
    with open(path, "rb") as f:
        f.seek(start)
        return f.read(max(0, end - start))

def resolve_excerpt_text(hit, source_texts, repo_root, warnings):
    """Resolve the excerpt's cited text so that reading the cited span reproduces it.
    Priority: injected source_texts (mock) -> repo_root/source_path (real) -> abs_path -> hit snippet.
    Returns (text, text_source, provenance_dict)."""
    sp = hit.get("source_path")
    span = _span_obj(hit)
    kind = hit.get("record_kind") or "source_chunk"
    chunk_ch = hit.get("chunk_content_hash")
    content_ch = hit.get("content_hash")

    raw_bytes = None
    text_source = None
    if span is not None and sp:
        if source_texts is not None and sp in source_texts:
            b = source_texts[sp].encode("utf-8")
            raw_bytes = b[span["start"]:span["end"]]
            text_source = "source_texts"
        elif repo_root:
            cand = os.path.join(repo_root, sp.replace("/", os.sep))
            if os.path.isfile(cand):
                try:
                    raw_bytes = _read_span_bytes(cand, span["start"], span["end"])
                    text_source = "repo_root"
                except OSError as e:
                    warnings.append("span_read_failed:%s:%s" % (sp, e))
        if raw_bytes is None and hit.get("abs_path"):
            ap = hit.get("abs_path")
            if os.path.isfile(ap):
                try:
                    raw_bytes = _read_span_bytes(ap, span["start"], span["end"])
                    text_source = "abs_path"
                except OSError as e:
                    warnings.append("span_read_failed_abs:%s" % e)

    reproduced = False
    checked_against = None
    if raw_bytes is not None:
        try:
            text = raw_bytes.decode("utf-8")
        except UnicodeDecodeError:
            text = raw_bytes.decode("utf-8", "replace")
            warnings.append("span_utf8_replace:%s" % sp)
        raw_sha = sha256_hex(raw_bytes)
        # source_chunk identity is chunk_content_hash (== the span bytes hash); records default to content_hash.
        if kind == "source_chunk" and chunk_ch:
            checked_against = "chunk_content_hash"
            reproduced = (raw_sha == chunk_ch)
        elif chunk_ch:
            checked_against = "chunk_content_hash"
            reproduced = (raw_sha == chunk_ch)
        elif content_ch:
            checked_against = "content_hash"
            reproduced = (raw_sha == content_ch)
        else:
            checked_against = None
            reproduced = True  # nothing to check against; span was read successfully
        prov = {"text_source": text_source, "reproduced": reproduced,
                "checked_against": checked_against, "span_sha256": raw_sha}
        return text, text_source, prov

    # Fallback: the hit's own snippet/text (no span reproduction possible).
    text = hit.get("snippet") or hit.get("text") or ""
    warnings.append("no_span_text:%s:used_snippet" % (sp or hit.get("record_version_id")))
    prov = {"text_source": "hit_snippet", "reproduced": False, "checked_against": None,
            "span_sha256": None}
    return text, "hit_snippet", prov

def make_excerpt(ranked_row, norm, source_texts, repo_root, warnings):
    entry = ranked_row["entry"]
    hit = entry["hit"]
    span = _span_obj(hit)
    text, text_source, prov = resolve_excerpt_text(hit, source_texts, repo_root, warnings)
    tok = est_tokens(text)
    exc_id = "exc_" + sha256_hex(
        (hit.get("record_version_id") or "") + "\0" + canonical_json(span))[:24]
    excerpt = {
        "excerpt_id": exc_id,
        "record_id": hit.get("record_id"),
        "record_version_id": hit.get("record_version_id"),
        "record_kind": hit.get("record_kind") or "source_chunk",
        "source_path": hit.get("source_path"),
        "content_hash": hit.get("content_hash"),
        "chunk_content_hash": hit.get("chunk_content_hash"),
        "source_version_id": hit.get("source_version_id"),
        "span": span,
        "span_label": hit.get("span_label"),
        "section_path": hit.get("section_path"),
        "heading": hit.get("heading"),
        "chunk_type": hit.get("chunk_type"),
        "namespace": hit.get("namespace"),
        "currentness": _currentness(hit),
        "authority_level": hit.get("authority_level"),
        "text": text,
        "token_estimate": tok,
        "provenance": prov,
        "selection": {
            "rank_in_pool": ranked_row["rank_in_pool"],
            "composite_score": ranked_row["score"],
            "feature_points": ranked_row["features"],
            "matched_queries": entry["matched_queries"],
            "best_query_rank": entry["best_rank"],
            "fused_score_micros": entry["best_fused_micros"],
        },
    }
    return excerpt

def _dedup_key(hit):
    return hit.get("chunk_content_hash") or hit.get("content_hash") or None

# ------------------------------------------------------------------------------------------------
# selection into the token budget with diversity + exact accounting (8.3 / 8.4 / 16.3)
# ------------------------------------------------------------------------------------------------

def select_into_budget(ranked, norm, config, source_texts, repo_root, warnings):
    budget = int(config["token_budget"])
    per_source_cap = int(config["per_source_cap"])
    max_excerpts = int(config["max_excerpts"])
    overhead = int(config["per_excerpt_overhead_tokens"])

    used = 0
    excerpts = []
    omitted = []
    per_source_count = {}
    seen_dedup = {}
    truncated = False
    budget_exhausted = False

    for row in ranked:
        entry = row["entry"]
        hit = entry["hit"]
        rvid = entry["record_version_id"]
        sp = hit.get("source_path") or "(none)"
        cur = _currentness(hit)
        base_omit = {
            "record_version_id": rvid,
            "record_id": hit.get("record_id"),
            "record_kind": hit.get("record_kind") or "source_chunk",
            "source_path": hit.get("source_path"),
            "currentness": cur,
            "rank_in_pool": row["rank_in_pool"],
            "composite_score": row["score"],
        }

        # 1) drop deleted occurrences (still recorded, with an expansion hint)
        if str(cur).strip().lower() == "deleted":
            o = dict(base_omit); o["reason"] = "deleted"
            o["expand_hint"] = {"type": "raw_source", "target": {"record_version_id": rvid}}
            omitted.append(o)
            continue

        # 2) content dedup (near-dup / identical text) -> keep best-ranked occurrence only
        dk = _dedup_key(hit)
        if dk is not None and dk in seen_dedup:
            o = dict(base_omit); o["reason"] = "duplicate_content"
            o["duplicate_of"] = seen_dedup[dk]
            omitted.append(o)
            continue

        # 3) source-diversity cap -> prevents N near-dups from one source crowding out distinct evidence
        if per_source_count.get(sp, 0) >= per_source_cap:
            o = dict(base_omit); o["reason"] = "source_diversity_cap"
            o["expand_hint"] = {"type": "more_evidence", "target": {"source_path": hit.get("source_path")}}
            omitted.append(o)
            continue

        # 4) hard excerpt count cap
        if len(excerpts) >= max_excerpts:
            o = dict(base_omit); o["reason"] = "max_excerpts"
            omitted.append(o)
            truncated = True
            continue

        # 5) token budget (greedy best-first; a later smaller excerpt may still fit)
        excerpt = make_excerpt(row, norm, source_texts, repo_root, warnings)
        cost = excerpt["token_estimate"] + overhead
        if used + cost > budget:
            o = dict(base_omit); o["reason"] = "token_budget"
            o["token_estimate"] = excerpt["token_estimate"]
            o["expand_hint"] = {"type": "raw_source", "target": {"record_version_id": rvid}}
            omitted.append(o)
            truncated = True
            budget_exhausted = True
            continue

        # accept
        used += cost
        excerpts.append(excerpt)
        per_source_count[sp] = per_source_count.get(sp, 0) + 1
        if dk is not None:
            seen_dedup[dk] = rvid

    accounting = {
        "token_fn": "ceil(chars/%d)" % TOKEN_CHARS_PER_TOKEN,
        "budget": budget,
        "used": used,
        "remaining": budget - used,
        "per_excerpt_overhead_tokens": overhead,
        "excerpt_body_tokens": sum(e["token_estimate"] for e in excerpts),
        "overhead_tokens": overhead * len(excerpts),
        "excerpt_count": len(excerpts),
        "truncated": truncated,
        "budget_exhausted": budget_exhausted,
        "omitted_count": len(omitted),
        "per_source_cap": per_source_cap,
        "max_excerpts": max_excerpts,
    }
    return excerpts, omitted, accounting

# ------------------------------------------------------------------------------------------------
# packet assembly (8.4) + eval hooks (8.6)
# ------------------------------------------------------------------------------------------------

def _ref_of(hit, extra=None):
    ref = {
        "record_id": hit.get("record_id"),
        "record_version_id": hit.get("record_version_id"),
        "record_kind": hit.get("record_kind"),
        "source_path": hit.get("source_path"),
        "namespace": hit.get("namespace"),
        "currentness": _currentness(hit),
        "authority_level": hit.get("authority_level"),
        "span_label": hit.get("span_label"),
    }
    if extra:
        ref.update(extra)
    return ref

def build_packet(task, norm, ranked, excerpts, omitted, accounting,
                 per_query_counts, retrieval_meta, config, warnings):
    excerpt_rvids = set(e["record_version_id"] for e in excerpts)

    # Reference blocks (REFS only; content owned by #41 / #39). Drawn from the whole ranked pool so a
    # relevant skill/procedure/failure/episode that did not win an excerpt slot is still surfaced as a ref.
    candidate_skills, relevant_procedures, relevant_failures, similar_episodes = [], [], [], []
    current_state_refs = []
    ref_caps = {"skill": 8, "procedure": 8, "failure": 8, "episode": 8, "state": 8}
    for row in ranked:
        hit = row["entry"]["hit"]
        kind = hit.get("record_kind")
        r = _ref_of(hit, {"rank_in_pool": row["rank_in_pool"], "composite_score": row["score"],
                          "included_as_excerpt": hit.get("record_version_id") in excerpt_rvids})
        if kind in SKILL_KINDS and len(candidate_skills) < ref_caps["skill"]:
            r["skill_ref"] = hit.get("record_id")
            candidate_skills.append(r)
        elif kind in PROCEDURE_KINDS and len(relevant_procedures) < ref_caps["procedure"]:
            relevant_procedures.append(r)
        elif kind in FAILURE_KINDS and len(relevant_failures) < ref_caps["failure"]:
            relevant_failures.append(r)
        elif kind in EPISODE_KINDS and len(similar_episodes) < ref_caps["episode"]:
            similar_episodes.append(r)
        if kind in STATE_KINDS and _authority_points(hit.get("authority_level")) >= AUTHORITY_POINTS["source_material"] \
                and len(current_state_refs) < ref_caps["state"]:
            current_state_refs.append(r)

    # 8.6 evaluation hooks / context-quality signals: EVERY candidate, why, rank, included/omitted.
    omit_reason_by_rvid = {}
    for o in omitted:
        omit_reason_by_rvid.setdefault(o["record_version_id"], o["reason"])
    retrieved_signals = []
    for row in ranked:
        hit = row["entry"]["hit"]
        rvid = hit.get("record_version_id")
        included = rvid in excerpt_rvids
        retrieved_signals.append({
            "record_version_id": rvid,
            "record_id": hit.get("record_id"),
            "record_kind": hit.get("record_kind"),
            "source_path": hit.get("source_path"),
            "content_hash": hit.get("content_hash"),
            "currentness": _currentness(hit),
            "authority_level": hit.get("authority_level"),
            "rank_in_pool": row["rank_in_pool"],
            "composite_score": row["score"],
            "feature_points": row["features"],
            "matched_queries": row["entry"]["matched_queries"],
            "fused_score_micros": row["entry"]["best_fused_micros"],
            "included": included,
            "omit_reason": None if included else omit_reason_by_rvid.get(rvid),
        })

    distinct_sources = sorted(set(e["source_path"] for e in excerpts if e["source_path"]))
    distinct_kinds = sorted(set(e["record_kind"] for e in excerpts))
    provenance_reproduced = sum(1 for e in excerpts if e["provenance"]["reproduced"])
    packet_metrics = {
        "candidate_count": len(ranked),
        "excerpt_count": len(excerpts),
        "omitted_count": len(omitted),
        "packet_tokens": accounting["used"],
        "budget": accounting["budget"],
        "distinct_source_count": len(distinct_sources),
        "distinct_kind_count": len(distinct_kinds),
        "provenance_reproduced_count": provenance_reproduced,
        "provenance_reproduced_all": (provenance_reproduced == len(excerpts)),
        "dropped_duplicate": sum(1 for o in omitted if o["reason"] == "duplicate_content"),
        "dropped_diversity": sum(1 for o in omitted if o["reason"] == "source_diversity_cap"),
        "dropped_budget": sum(1 for o in omitted if o["reason"] == "token_budget"),
        "dropped_deleted": sum(1 for o in omitted if o["reason"] == "deleted"),
    }

    completion_contract = task.get("completion_contract") or {
        "schema": "lifeorch.goal_verification/0.1",
        "goal": norm["original_goal"],
        "success_criteria": task.get("success_criteria") or [],
        "note": "no explicit success contract supplied; caller must define closing predicate(s).",
    }

    packet_body = {
        "schema": PACKET_SCHEMA,
        "compiler": {"name": "context.compile", "version": COMPILER_VERSION,
                     "worker": WORKER_NAME, "worker_version": WORKER_VERSION},
        "task_descriptor_digest": "sha256:" + sha256_of_obj(_canonical_task(task)),
        "original_goal": norm["original_goal"],
        "normalized_task": norm["normalized_task"],
        "task_type": norm["task_type"],
        "time_horizon": norm["time_horizon"],
        "namespace": norm["namespace"],
        "constraints": task.get("constraints") or [],
        "permissions": {
            "requested_side_effects": task.get("requested_side_effects") or [],
            "authority": task.get("authority"),
        },
        "current_state_refs": current_state_refs,
        "excerpts": excerpts,
        "candidate_skills": candidate_skills,
        "relevant_procedures": relevant_procedures,
        "relevant_failures": relevant_failures,
        "similar_episodes": similar_episodes,
        "open_questions": task.get("open_questions") or [],
        "completion_contract": completion_contract,
        "escalation_conditions": task.get("escalation_conditions") or _default_escalations(),
        "token_budget": accounting,
        "omitted_context": omitted,
        "retrieval_provenance": {
            "retriever": retrieval_meta.get("retriever", "injected"),
            "retriever_version": retrieval_meta.get("retriever_version"),
            "corpus_version": retrieval_meta.get("corpus_version"),
            "index_snapshot": retrieval_meta.get("index_snapshot"),
            "embedding_space_id": retrieval_meta.get("embedding_space_id"),
            "fusion_algo": retrieval_meta.get("fusion_algo"),
            "fusion_version": retrieval_meta.get("fusion_version"),
            "query_set": norm["query_set"],
            "per_query_hit_counts": {str(k): per_query_counts.get(k, 0)
                                     for k in sorted(per_query_counts.keys())},
            "candidate_count": len(ranked),
        },
        "evaluation_hooks": {
            "retrieved": retrieved_signals,
            "packet_metrics": packet_metrics,
        },
        "expansion_affordances": {
            "schema": EXPANSION_SCHEMA,
            "op": "expand",
            "request_shape": {
                "type": ["raw_source", "more_evidence", "related_symbol", "failure_record",
                         "tool_contract", "prior_episode"],
                "target": "{ record_version_id | record_id | source_path | span{start,end} | symbol_ref }",
                "budget": {"max_tokens": config["expand_max_tokens"]},
            },
        },
    }
    if warnings:
        packet_body["warnings"] = sorted(set(warnings))

    packet_id = "cpkt_" + sha256_of_obj(packet_body)[:32]
    packet = {"packet_id": packet_id}
    packet.update(packet_body)
    return packet, packet_metrics

def _default_escalations():
    return [
        "required source could not be retrieved or provenance did not reproduce",
        "token budget exhausted before a required source was included (truncated=true)",
        "only stale versions of a required current source are available",
        "the completion contract has no closing predicate",
    ]

def _canonical_task(task):
    """A stable projection of the descriptor for the digest (excludes volatile injected material)."""
    keep = ("original_goal", "request_text", "namespace", "project_id", "task_type", "time_horizon",
            "authority", "requested_side_effects", "relevant_paths", "relevant_entities",
            "constraints", "open_questions", "completion_contract", "success_criteria",
            "escalation_conditions")
    return {k: task[k] for k in keep if k in task}

# ------------------------------------------------------------------------------------------------
# op: compile
# ------------------------------------------------------------------------------------------------

def _resolve_config(task, args):
    cfg = dict(DEFAULT_CONFIG)
    for src in (task.get("config") or {}, args.get("config") or {}):
        for k, v in src.items():
            if k in cfg and v is not None:
                cfg[k] = v
    # allow a bare token_budget on the task/args for convenience
    for src in (task, args):
        if src.get("token_budget") is not None:
            cfg["token_budget"] = src["token_budget"]
    return cfg

def op_compile(args, warnings):
    task = args.get("task") or {}
    config = _resolve_config(task, args)

    # normalize (use the entrypoint-provided query_set when present so provenance == what actually ran)
    norm = normalize_task(task, config)
    if args.get("query_set"):
        norm["query_set"] = args["query_set"]

    # 8.2 candidate pool from injected retriever-0.2 batches (mock fixture OR real #36 hits)
    batches = args.get("retrieval_batches")
    if batches is None and args.get("candidates") is not None:
        batches = [{"query_index": 0, "hits": args["candidates"]}]
    pool, per_query_counts = build_candidate_pool(batches or [])

    # 8.3 deterministic rerank
    ranked = rank_candidates(pool, norm, config)

    # excerpt-text resolution material
    source_texts = args.get("source_texts")
    repo_root = args.get("repo_root")

    # 8.3/8.4/16.3 diversity + budget selection with exact accounting
    excerpts, omitted, accounting = select_into_budget(
        ranked, norm, config, source_texts, repo_root, warnings)

    retrieval_meta = args.get("retrieval_meta") or {}
    packet, metrics = build_packet(task, norm, ranked, excerpts, omitted, accounting,
                                   per_query_counts, retrieval_meta, config, warnings)

    return {"packet": packet, "packet_id": packet["packet_id"], "metrics": metrics,
            "query_set": norm["query_set"], "config": config}, [
        {"name": "context_packet.json", "obj": packet, "kind": "json"}]

# ------------------------------------------------------------------------------------------------
# op: normalize  (entrypoint calls this to get the query_set before running the real retriever)
# ------------------------------------------------------------------------------------------------

def op_normalize(args, warnings):
    task = args.get("task") or {}
    config = _resolve_config(task, args)
    norm = normalize_task(task, config)
    return {"normalized_task": norm["normalized_task"], "original_goal": norm["original_goal"],
            "task_type": norm["task_type"], "time_horizon": norm["time_horizon"],
            "namespace": norm["namespace"], "salient_terms": norm["salient_terms"],
            "literals": norm["literals"], "query_set": norm["query_set"],
            "exclude_stale": norm["exclude_stale"], "config": config}, []

# ------------------------------------------------------------------------------------------------
# op: expand (8.5) -- deterministic, bounded adaptive expansion seam (NOT a live agent loop)
# ------------------------------------------------------------------------------------------------

VALID_EXPAND_TYPES = ("raw_source", "more_evidence", "related_symbol", "failure_record",
                      "tool_contract", "prior_episode")

def op_expand(args, warnings):
    request = args.get("request") or {}
    rtype = (request.get("type") or "raw_source").strip().lower()
    if rtype not in VALID_EXPAND_TYPES:
        raise CompilerError("invalid_expand_type",
                            "unknown expansion type '%s' (%s)" % (rtype, "|".join(VALID_EXPAND_TYPES)))
    target = request.get("target") or {}
    budget_tokens = int((request.get("budget") or {}).get("max_tokens", DEFAULT_CONFIG["expand_max_tokens"]))
    packet = args.get("packet") or {}
    packet_id = packet.get("packet_id")

    source_texts = args.get("source_texts")
    repo_root = args.get("repo_root")
    # a pool of additional 0.2 hits the caller injected for this expansion (real #36 or fixture)
    exp_candidates = args.get("expansion_candidates") or []

    evidence = []
    truncated = False

    if rtype == "raw_source":
        # Fetch the bounded raw source behind a summary/excerpt: resolve the target's source span.
        hit = _find_target_hit(target, packet, exp_candidates)
        if hit is None:
            raise CompilerError("expand_target_not_found",
                                "raw_source target not resolvable from packet/excerpt/candidates")
        text, tsrc, prov = resolve_excerpt_text(hit, source_texts, repo_root, warnings)
        text, truncated = _bound_text(text, budget_tokens)
        evidence.append(_expansion_excerpt(hit, text, prov, truncated))
    else:
        # evidence-style expansions pull bounded refs/excerpts from the injected candidate pool
        wanted_kind = {
            "failure_record": "failure", "prior_episode": "episode",
            "related_symbol": "symbol", "tool_contract": "skill",
        }.get(rtype)
        pool = exp_candidates
        if wanted_kind:
            pool = [h for h in pool if (h.get("record_kind") == wanted_kind)]
        # deterministic order: by provided rank then record_version_id
        pool = sorted(pool, key=lambda h: (int(h.get("rank", 10**9)) if str(h.get("rank", "")).lstrip("-").isdigit() else 10**9,
                                           str(h.get("record_version_id"))))
        used = 0
        for h in pool:
            text, tsrc, prov = resolve_excerpt_text(h, source_texts, repo_root, warnings)
            tok = est_tokens(text)
            if used + tok > budget_tokens and evidence:
                truncated = True
                break
            if used + tok > budget_tokens and not evidence:
                text, _ = _bound_text(text, budget_tokens)
                tok = est_tokens(text)
                truncated = True
            evidence.append(_expansion_excerpt(h, text, prov, False))
            used += tok

    expansion_id = "cxp_" + sha256_of_obj(
        {"packet_id": packet_id, "request": request,
         "evidence_ids": [e["record_version_id"] for e in evidence]})[:24]

    result = {
        "schema": EXPANSION_SCHEMA,
        "expansion_id": expansion_id,
        "packet_id": packet_id,
        "request": {"type": rtype, "target": target,
                    "budget": {"max_tokens": budget_tokens}},
        "evidence": evidence,
        "evidence_count": len(evidence),
        "token_estimate": sum(e["token_estimate"] for e in evidence),
        "budget_tokens": budget_tokens,
        "bounded": True,
        "truncated": truncated,
    }
    return {"expansion": result}, [{"name": "context_expansion.json", "obj": result, "kind": "json"}]

def _find_target_hit(target, packet, exp_candidates):
    rvid = target.get("record_version_id")
    rid = target.get("record_id")
    sp = target.get("source_path")
    # 1) search expansion candidates
    for h in exp_candidates:
        if rvid and h.get("record_version_id") == rvid:
            return h
        if rid and h.get("record_id") == rid:
            return h
    # 2) search the packet's excerpts (an excerpt carries full provenance -> usable as a hit)
    for e in (packet.get("excerpts") or []):
        if rvid and e.get("record_version_id") == rvid:
            return _excerpt_as_hit(e)
        if rid and e.get("record_id") == rid:
            return _excerpt_as_hit(e)
    # 3) target names a source_path + span directly
    if sp and target.get("span"):
        return {"source_path": sp, "span": target.get("span"),
                "record_kind": "source_chunk",
                "record_version_id": target.get("record_version_id"),
                "record_id": target.get("record_id"),
                "content_hash": target.get("content_hash"),
                "chunk_content_hash": target.get("chunk_content_hash")}
    return None

def _excerpt_as_hit(e):
    return {
        "record_id": e.get("record_id"), "record_version_id": e.get("record_version_id"),
        "record_kind": e.get("record_kind"), "source_path": e.get("source_path"),
        "content_hash": e.get("content_hash"), "chunk_content_hash": e.get("chunk_content_hash"),
        "source_version_id": e.get("source_version_id"), "span": e.get("span"),
        "span_label": e.get("span_label"), "section_path": e.get("section_path"),
        "heading": e.get("heading"), "chunk_type": e.get("chunk_type"),
        "namespace": e.get("namespace"), "currentness": e.get("currentness"),
        "authority_level": e.get("authority_level"), "snippet": e.get("text"),
    }

def _bound_text(text, budget_tokens):
    max_chars = max(0, budget_tokens * TOKEN_CHARS_PER_TOKEN)
    if len(text) <= max_chars:
        return text, False
    return text[:max_chars], True

def _expansion_excerpt(hit, text, prov, truncated):
    return {
        "record_id": hit.get("record_id"),
        "record_version_id": hit.get("record_version_id"),
        "record_kind": hit.get("record_kind"),
        "source_path": hit.get("source_path"),
        "content_hash": hit.get("content_hash"),
        "chunk_content_hash": hit.get("chunk_content_hash"),
        "span": _span_obj(hit),
        "span_label": hit.get("span_label"),
        "currentness": hit.get("currentness") or hit.get("status") or "current",
        "authority_level": hit.get("authority_level"),
        "text": text,
        "token_estimate": est_tokens(text),
        "provenance": prov,
        "truncated": truncated,
    }

# ------------------------------------------------------------------------------------------------
# dispatch / worker protocol
# ------------------------------------------------------------------------------------------------

class CompilerError(Exception):
    def __init__(self, code, message):
        super(CompilerError, self).__init__(message)
        self.code = code
        self.message = message

OPS = {"compile": op_compile, "normalize": op_normalize, "expand": op_expand}

def run(args):
    """Execute one op. Returns a meta dict {ok, op, result, worker, warnings, artifacts}.
    Writes artifact files under args['output_dir'] when provided. Importable for tests."""
    warnings = []
    op = (args.get("op") or "compile").strip().lower()
    if op not in OPS:
        return {"ok": False, "op": op, "error_code": "invalid_op",
                "error": "unknown op '%s' (%s)" % (op, "|".join(sorted(OPS)))}
    try:
        payload, artifact_specs = OPS[op](args, warnings)
    except CompilerError as e:
        return {"ok": False, "op": op, "error_code": e.code, "error": e.message}
    except Exception as e:  # noqa: BLE001 -- surface as a structured worker error, never a raw trace on stdout
        return {"ok": False, "op": op, "error_code": "unhandled_worker_exception",
                "error": "%s: %s" % (type(e).__name__, e)}

    artifacts = []
    out_dir = args.get("output_dir")
    if out_dir:
        try:
            os.makedirs(out_dir, exist_ok=True)
        except OSError:
            pass
        for spec in artifact_specs:
            path = os.path.join(out_dir, spec["name"])
            data = canonical_json(spec["obj"]) + "\n"
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(data)
            artifacts.append({"path": os.path.abspath(path), "kind": spec.get("kind", "json")})

    return {"ok": True, "op": op, "result": payload,
            "worker": {"name": WORKER_NAME, "version": WORKER_VERSION},
            "warnings": sorted(set(warnings)), "artifacts": artifacts}

def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: context_compiler.py <args.json>\n")
        return 2
    args_path = argv[1]
    with open(args_path, "r", encoding="utf-8") as f:
        args = json.load(f)
    meta_path = args.get("meta_path")
    import time
    t0 = time.time()
    meta = run(args)
    meta["runtime_ms"] = int(round((time.time() - t0) * 1000))
    out = canonical_json(meta)
    if meta_path:
        with open(meta_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(out + "\n")
    # a short stdout line (captured to worker.log by the wrapper); the meta file is authoritative
    sys.stdout.write(json.dumps({"ok": meta.get("ok"), "op": meta.get("op"),
                                 "error_code": meta.get("error_code")}) + "\n")
    return 0 if meta.get("ok") else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv))
