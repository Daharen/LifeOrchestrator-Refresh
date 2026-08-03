#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
selpol_reference.py -- Life Orchestrator Module 40, the CONTEXT_PACKET_CONTRACT s4 selection-policy
REFERENCE implementation (`selpol_rrf_v1`), built to the FROZEN interface so context.compile can select
candidates without its retired i29 self-contained composite score.

    THIS IS A SPEC-FAITHFUL REFERENCE IMPL (P1-1 / D-0077 parallel-build seam).
    The CANONICAL `selpol_rrf_v1` is OWNED BY #37 retrieval.eval (modules/37-retrieval-eval/lib/);
    the orchestrator wires #37's real library at the fold and asserts BYTE-IDENTICAL selection on real
    #36 hits. A divergence is reconciled at fold, never silently (the i22/i27 pattern). context.compile
    imports `select` from HERE off-machine; the fold overrides it with the canonical module.

Frozen interface (CONTEXT_PACKET_CONTRACT s4):
    select(candidates, descriptor, policy_id, params)
        -> { selected[], ranked[], policy_id, policy_version, features_by_candidate }

PURE + deterministic: no model, no I/O, no state, NO floats in output (integer millionths only).
The output is ADDITIVE -- it NEVER destroys the retrieval order. Each candidate's channel ranks
(retrieval_rank / lexical_rank / vector_rank / fused_rank) are PRESERVED from the retriever-0.2 hit;
selection produces a SEPARATE `selection_rank` ordering expressed as new fields, not by mutating the
retrieval array.

Deterministic stages (s4), in order:
    (1) hard filters   -- forbidden / privacy / deleted sink to the bottom (reason hard_filter_forbidden)
    (2) temporal       -- stale demote under current_only              (reason stale_demote)
    (3) authority      -- epistemic_authority weighting                (reason authority_boost)
    (4) rank fusion    -- versioned RRF over CHANNEL RANKS across each candidate's
                          retrieval_occurrences[] (P1-2: fuse RANKS, not cross-query raw scores)
                          (reason fusion_rrf)
    (5) diversity      -- cluster IDENTICAL display text (same excerpt_hash) into one representative
                          carrying occurrences[]+evidence_cluster_id; dedup DISPLAY tokens, NEVER
                          provenance (P1-3)                            (reason diversity_capped)
    (6) budget         -- OWNED BY the compiler (token budget / per-source cap / transport), which adds
                          `budget_omitted` reason codes; the library marks `selected` for cluster reps
                          that pass hard filters.

policy_id = "selpol_rrf_v1"; policy_version = "0.2.0-ref".
"""

import hashlib
import json

POLICY_ID = "selpol_rrf_v1"
POLICY_VERSION = "0.2.0-ref"

RRF_K = 60  # standard reciprocal-rank-fusion constant (versioned in policy_version)

# authority_level -> points (higher = more authoritative). s4 stage 3. Unknown -> DEFAULT.
AUTHORITY_POINTS = {
    "governing": 320, "authoritative": 300, "canonical": 280,
    "curated": 220, "source_material": 150, "derived": 100, "default": 80, "low": 40,
}
AUTHORITY_DEFAULT_POINTS = 80

# s5 currentness -> freshness points (s4 stage 2). `deleted`/`unverified` sink via hard filter / 0.
FRESHNESS_POINTS = {
    "current": 200,
    "source_stale": 40, "derivation_stale": 40, "embedding_stale": 60,
    "relationship_stale": 60, "summary_stale": 40, "authority_stale": 30,
    "temporal_expiry": 20, "unverified": 30,
    "deleted": 0,
}
FRESHNESS_DEFAULT_POINTS = 50
STALE_SET = frozenset(k for k in FRESHNESS_POINTS if k != "current")

# integer weights (documented; NO float). selection_score = rrf + AUTH*auth + FRESH*fresh + desc boosts - penalties.
W_RRF = 1
W_AUTHORITY = 30
W_FRESHNESS = 40
STALE_PENALTY = 4000          # current_only: a stale candidate is demoted below an equal-rank current one
HARD_FILTER_SINK = 10 ** 9    # forbidden/privacy/deleted sink far below every real candidate
NAMESPACE_MATCH_POINTS = 1200
COMPONENT_PREFIX_POINTS = 1000
COMPONENT_BASENAME_POINTS = 600
KIND_STAGE_POINTS = 800
SEEKING_FAILURE_POINTS = 800

# record_kind sets used by the (light) descriptor task-stage boost. Kept small on purpose --
# heavy kind_priority tuning is a follow-on (P2); the reference policy is RRF-dominant.
TASK_STAGE_KINDS = {
    "act": {"procedure", "skill", "failure"},
    "implement": {"procedure", "skill", "symbol", "failure"},
    "plan": {"decision", "procedure", "summary"},
    "research": {"summary", "claim", "decision"},
    "verify": {"failure", "procedure", "skill"},
}


def _sha256_hex(s):
    if isinstance(s, bytes):
        b = s
    else:
        b = s.encode("utf-8")
    return hashlib.sha256(b).hexdigest()


def _canonical_json(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _auth_points(level):
    if not level:
        return AUTHORITY_DEFAULT_POINTS
    return AUTHORITY_POINTS.get(str(level).strip().lower(), AUTHORITY_DEFAULT_POINTS)


def _fresh_points(cur):
    if not cur:
        return FRESHNESS_POINTS["current"]
    return FRESHNESS_POINTS.get(str(cur).strip().lower(), FRESHNESS_DEFAULT_POINTS)


def _rrf_millionths(occurrences):
    """Versioned RRF over CHANNEL RANKS across a candidate's retrieval occurrences. Integer millionths.
    Per occurrence: primary channel = fused_rank else lexical_rank else rank; plus a vector term when present."""
    total = 0.0
    for occ in (occurrences or []):
        primary = occ.get("fused_rank")
        if primary is None:
            primary = occ.get("lexical_rank")
        if primary is None:
            primary = occ.get("rank")
        if primary is not None:
            try:
                total += 1.0 / (RRF_K + int(primary))
            except (TypeError, ValueError):
                pass
        vr = occ.get("vector_rank")
        if vr is not None:
            try:
                total += 1.0 / (RRF_K + int(vr))
            except (TypeError, ValueError):
                pass
    return int(round(total * 1000000))


def _is_hard_filtered(cand, descriptor):
    """s4 stage 1: forbidden / privacy / deleted."""
    reasons = []
    cur = str(cand.get("currentness") or cand.get("status") or "current").strip().lower()
    if cur == "deleted":
        reasons.append("deleted")
    sp = cand.get("source_path")
    fdset = descriptor.get("forbidden_sources") or []
    if sp and sp in fdset:
        reasons.append("forbidden_source")
    pvset = descriptor.get("privacy_exclusions") or []
    if sp and sp in pvset:
        reasons.append("privacy_excluded")
    sens = str(cand.get("sensitivity_class") or "").strip().lower()
    if sens in ("secret", "credential", "private_excluded"):
        reasons.append("privacy_excluded")
    fd = cand.get("filter_decisions") or {}
    if isinstance(fd, dict) and fd.get("forbidden") is True:
        reasons.append("forbidden_source")
    return reasons


def select(candidates, descriptor, policy_id=POLICY_ID, params=None):
    """The FROZEN s4 selection interface. `candidates` = pooled retriever-0.2 candidates, each carrying:
      record_version_id, record_id, record_kind, source_path, namespace, authority_level (epistemic),
      currentness/status, sensitivity_class?, filter_decisions?, excerpt_hash? (chunk_content_hash),
      retrieval_rank, lexical_rank, vector_rank, fused_rank (PRESERVED from s3), and
      retrieval_occurrences[] = [{query_index, rank, lexical_rank, vector_rank, fused_rank}].
    Returns {selected[], ranked[], policy_id, policy_version, features_by_candidate} -- ADDITIVE, deterministic."""
    params = params or {}
    descriptor = descriptor or {}
    current_only = str(descriptor.get("time_horizon") or "current_only").strip().lower() in ("current_only", "current", "")
    ns = descriptor.get("namespace")
    relevant_paths = [p for p in (descriptor.get("relevant_paths") or []) if p]
    if not relevant_paths and descriptor.get("component"):
        relevant_paths = [descriptor["component"]]
    task_stage = str(descriptor.get("task_stage") or "").strip().lower()
    seeking_failures = bool(descriptor.get("seeking_failures"))

    features_by_candidate = {}
    rows = []
    for cand in candidates:
        rvid = cand.get("record_version_id") or ("anon_" + _sha256_hex(_canonical_json(cand))[:24])
        reason_codes = []

        hard = _is_hard_filtered(cand, descriptor)
        rrf = _rrf_millionths(cand.get("retrieval_occurrences"))
        auth = _auth_points(cand.get("authority_level"))
        cur = str(cand.get("currentness") or cand.get("status") or "current").strip().lower()
        fresh = _fresh_points(cur)

        score = W_RRF * rrf + W_AUTHORITY * auth + W_FRESHNESS * fresh
        reason_codes.append("fusion_rrf")
        if auth >= AUTHORITY_POINTS["source_material"]:
            reason_codes.append("authority_boost")

        # s4 stage 2: temporal demote (current_only).
        stale = cur in STALE_SET
        if current_only and stale:
            score -= STALE_PENALTY
            reason_codes.append("stale_demote")

        # light descriptor boosts (namespace / component / task-stage / failure-seeking).
        if ns and cand.get("namespace") == ns:
            score += NAMESPACE_MATCH_POINTS
        sp = (cand.get("source_path") or "").replace("\\", "/")
        comp = 0
        for rp in relevant_paths:
            rpn = str(rp).replace("\\", "/").rstrip("/")
            if rpn and sp.startswith(rpn):
                comp = max(comp, COMPONENT_PREFIX_POINTS)
            elif rpn and sp.rsplit("/", 1)[-1] == rpn.rsplit("/", 1)[-1]:
                comp = max(comp, COMPONENT_BASENAME_POINTS)
        score += comp
        kind = cand.get("record_kind") or "source_chunk"
        if task_stage and kind in TASK_STAGE_KINDS.get(task_stage, frozenset()):
            score += KIND_STAGE_POINTS
        if seeking_failures and kind == "failure":
            score += SEEKING_FAILURE_POINTS

        if hard:
            score -= HARD_FILTER_SINK
            reason_codes = ["hard_filter_forbidden"]

        feats = {
            "rrf_millionths": rrf,
            "authority_points": auth,
            "freshness_points": fresh,
            "namespace_match": bool(ns and cand.get("namespace") == ns),
            "component_points": comp,
            "kind_stage_match": bool(task_stage and kind in TASK_STAGE_KINDS.get(task_stage, frozenset())),
            "seeking_failure_match": bool(seeking_failures and kind == "failure"),
            "stale_demoted": bool(current_only and stale),
            "hard_filtered": bool(hard),
            "hard_filter_reasons": sorted(hard),
        }
        features_by_candidate[rvid] = feats
        tie = str(cand.get("tie_break_key") if cand.get("tie_break_key") is not None else rvid)
        rows.append({
            "record_version_id": rvid,
            "record_id": cand.get("record_id"),
            "record_kind": kind,
            "source_path": cand.get("source_path"),
            "excerpt_hash": cand.get("excerpt_hash") or cand.get("chunk_content_hash"),
            "retrieval_rank": cand.get("retrieval_rank"),
            "lexical_rank": cand.get("lexical_rank"),
            "vector_rank": cand.get("vector_rank"),
            "fused_rank": cand.get("fused_rank"),
            "selection_score": int(score),
            "reason_codes": reason_codes,
            "hard_filtered": bool(hard),
            "tie_break": (tie, rvid),
        })

    # deterministic total order: descending selection_score, then tie_break, then rvid.
    rows.sort(key=lambda r: (-r["selection_score"], r["tie_break"][0], r["tie_break"][1]))

    # s4 stage 5: cluster IDENTICAL display text (same excerpt_hash). The FIRST (best-ordered) row is the
    # cluster representative + `selected`; later identical-text rows are diversity_capped (NOT provenance-erased:
    # they keep their record ids + an occurrences ref to the representative).
    seen_hash = {}
    selected = []
    for i, r in enumerate(rows):
        r["selection_rank"] = i + 1
        eh = r.pop("excerpt_hash", None)
        r.pop("tie_break", None)
        if r["hard_filtered"]:
            r["selected"] = False
            r["evidence_cluster_id"] = None
            continue
        if eh is not None and eh in seen_hash:
            rep = seen_hash[eh]
            r["selected"] = False
            if "diversity_capped" not in r["reason_codes"]:
                r["reason_codes"] = r["reason_codes"] + ["diversity_capped"]
            r["evidence_cluster_id"] = rep
            r["duplicate_of"] = rep
            continue
        cluster_id = "clus_" + _sha256_hex((eh or r["record_version_id"]))[:20]
        if eh is not None:
            seen_hash[eh] = r["record_version_id"]
        r["selected"] = True
        r["evidence_cluster_id"] = cluster_id
        r["reason_codes"] = r["reason_codes"] + ["selected"]
        selected.append(r["record_version_id"])

    return {
        "policy_id": policy_id or POLICY_ID,
        "policy_version": POLICY_VERSION,
        "ranked": rows,
        "selected": selected,
        "features_by_candidate": features_by_candidate,
    }
