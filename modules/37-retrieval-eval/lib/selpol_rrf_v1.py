#!/usr/bin/env python3
# selpol_rrf_v1.py -- the ONE versioned DETERMINISTIC selection-policy library (Life Orchestrator
# module 37 `retrieval.eval`, contract v0.3 / CONTEXT_PACKET_CONTRACT s4, P1-1; plan fo-30-dd453156,
# SELECTION-POLICY-i30).
#
# WHAT THIS IS (CONTEXT_PACKET_CONTRACT.md s4 -- the FROZEN i30 interface)
#   ONE selection owner. Extracted from #37's shipped deterministic `rerank()` so there is exactly one
#   selection implementation, OWNED here and CONSUMED by the context compiler #40 AND by #37's own eval
#   A/B -- removing the "two rerankers" problem (P1-1). PURE + DETERMINISTIC: no model, no I/O, no state,
#   no wall-clock, no randomness. Byte-identical selection on re-run, cross-machine.
#
#   INTERFACE (frozen, s4):
#     select(candidates, descriptor, policy_id="selpol_rrf_v1", params=None)
#       -> { selected[], ranked[], policy_id, policy_version, features_by_candidate,
#            omission_manifest[], stages }
#
#   INPUTS
#     candidates  -- the MEMORY_CONTRACT s3 retriever-0.2 hit array (normalized dicts; each carries
#                    retrieval_rank (`rank`), lexical_rank, vector_rank, fused_rank + scores, status,
#                    authority_level, namespace, record_kind, source_path, chunk_id, chunk_content_hash,
#                    span_start/span_end/span_label, token_count, snippet, retrieval_channels).
#     descriptor  -- the UNIFIED selection descriptor (s4 reconciliation of #40's task fields + #37's
#                    rerank_descriptor): { namespace?, component?, relevant_paths?, task_type?,
#                    task_stage?, time_horizon?, seeking_failures?, permission_context? }.
#     policy_id   -- namespaced+versioned; only 'selpol_rrf_v1' is known this wave (fail-closed otherwise).
#     params      -- policy knobs + the caller's POLICY SIGNALS (kept out of the candidate scan so the
#                    library stays pure -- the caller supplies what it is permitted/labelled to demote):
#                      rrf_k(int=60), weights{}, authority_rank{}, diversity_penalty, hard_demote,
#                      stale_penalty, current_only(bool), dedup_display(bool=False),
#                      hard_filter[{source_path, content_hash?, reason}], stale[{source_path, content_hash?}],
#                      required_versions[{source_path, content_hash}], budget{max_selected?, max_tokens?,
#                      per_item_overhead?}.
#                    #40 supplies hard_filter from control_plane.permission_grants / permission_context and
#                    relies on the candidate's own s5 `status` for temporal demote; #37's eval wrapper maps
#                    its benchmark labels (forbidden/privacy/stale/required version) into the same params.
#
#   STAGES (deterministic, versioned baseline -- s4), in order, each accruing reason_codes + features:
#     (1) HARD FILTERS   -- forbidden / privacy / deleted sink (hard demote) + selected=False.
#     (2) TEMPORAL       -- stale demote under current_only per MEMORY_CONTRACT s5/s6.
#     (3) AUTHORITY      -- epistemic_authority weighting (a TRUST signal, never execution authority).
#     (4) RANK FUSION    -- versioned RRF over CHANNEL RANKS (retrieval_occurrences[]), NOT cross-query raw
#                           scores (P1-2). Single-occurrence baseline = strictly rank-monotonic (order-
#                           preserving vs the retriever); multi-occurrence (a candidate seen via >1 channel,
#                           or the dedup cluster of stage 5) fuses ranks by RRF.
#     (5) DIVERSITY      -- greedy source-diversity + (dedup_display) occurrence-preserving clustering that
#                           dedups DISPLAY tokens, NEVER provenance: identical text collapses to ONE display
#                           item carrying occurrences[] + evidence_cluster_id (P1-3).
#     (6) BUDGET         -- a budget hook (max_selected / max_tokens); overflow -> omission_manifest.
#
#   OUTPUT is ADDITIVE -- it NEVER re-sorts the retrieval array in place. Each ranked candidate is a COPY of
#   its input hit that PRESERVES retrieval_rank / lexical_rank / vector_rank / fused_rank and ADDS
#   selection_rank, selection_score (integer millionths/points), selection_policy_id, selected (bool),
#   reason_codes[], retrieval_occurrences[], rrf_score, and (in a dedup cluster) occurrences[] +
#   evidence_cluster_id. The input list is not mutated.
#
#   BASELINE COMPATIBILITY (recorded for the D-0077 fold, SCHEMA_NOTES s2): the DEFAULT policy scoring is the
#   shipped `rerank()` composite (direct relevance = the retriever's fused_score -- itself the retriever's
#   fused output per MEMORY_CONTRACT s3 -- + authority + freshness + descriptor matches, hard demote, stale
#   penalty, greedy diversity). With dedup_display=False + no budget, select() reproduces the shipped
#   reranked ORDER + diagnostics BYTE-IDENTICALLY, so #37's shipped benchmark + A/B stay regression-green.
#   The RRF-over-channel-ranks is emitted as a first-class feature + `fusion_rrf` reason code and IS the
#   fusion rule when a candidate carries >1 occurrence (multi-channel or a dedup cluster). Replacing the
#   raw-score direct-relevance term with pure rank-RRF as the PRIMARY sort -- which changes ordering -- is
#   the named P1-2 score-comparability follow-on, exactly as CONTEXT_PACKET_CONTRACT s4 defers it.

import hashlib

POLICY_ID = "selpol_rrf_v1"
POLICY_VERSION = "1.0.0"
KNOWN_POLICIES = frozenset([POLICY_ID])

PPM = 1000000
RRF_K_DEFAULT = 60

# ---- feature weights (the frozen baseline; the shipped RERANK_W, now owned HERE) ----
RERANK_W = {
    "relevance": 1,          # x direct relevance (the retriever fused/lexical score, millionths)
    "authority": 3 * PPM,    # x authority level rank
    "freshness": 6 * PPM,    # x freshness rank
    "project": 2 * PPM,      # namespace match
    "component": 2 * PPM,    # path-prefix match
    "task_stage": 2 * PPM,   # record_kind matches the task stage
    "failure": 2 * PPM,      # failure-seeking + record_kind==failure
    "procedural": 2 * PPM,   # action stage + record_kind==procedure
}
RERANK_HARD_DEMOTE = 1000 * PPM      # forbidden / privacy / deleted -> sink to the bottom
RERANK_STALE_PENALTY = 20 * PPM      # current_only + a stale hit
RERANK_DIVERSITY_PENALTY = 8 * PPM   # per already-selected hit from the same source_path

# epistemic_authority enum (a TRUST signal, NEVER an execution grant -- P0-1/P1-2).
AUTHORITY_RANK = {"authoritative": 4, "governing": 4, "curated": 3, "source_material": 2, "derived": 1}
TASK_STAGE_KINDS = {
    "implement": ("procedure", "source_chunk"),
    "act": ("procedure",),
    "debug": ("failure", "source_chunk"),
    "plan": ("decision", "summary"),
    "research": ("summary", "source_chunk", "claim"),
}
# MEMORY_CONTRACT s5 staleness enum (the healthy baseline is `current`). Local copy so the library is
# SELF-CONTAINED (stdlib only) and importable by #40 without pulling in the eval harness.
STALE_STATUSES = frozenset([
    "source_stale", "derivation_stale", "embedding_stale", "relationship_stale",
    "summary_stale", "authority_stale", "temporal_expiry", "deleted", "unverified",
])


# ------------------------------------------------------------------ pure helpers

def _norm_path(p):
    p = str(p or "").replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p


def _sha16(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]


def _matches(hit, m):
    """Path (+ optional source-version) match -- the hard-filter / stale / required-version matcher."""
    if _norm_path(hit.get("source_path", "")) != _norm_path(m.get("source_path", "")):
        return False
    if m.get("content_hash") and str(hit.get("content_hash", "")) != str(m["content_hash"]):
        return False
    return True


def _rel_of(hit):
    """Direct-relevance term: the first truthy, non-bool numeric of (fused_score, lexical_score, score).
    Matches the shipped reranker EXACTLY so the frozen baseline order is preserved."""
    for cand in (hit.get("fused_score"), hit.get("lexical_score"), hit.get("score")):
        if isinstance(cand, bool):
            continue
        if isinstance(cand, (int, float)) and cand:
            return int(cand)
    return 0


def _fresh_rank(status):
    if status is None:
        return 2
    if status == "current":
        return 3
    if status in ("deleted", "unverified"):
        return 0
    if status in STALE_STATUSES:
        return 1
    return 2


def _rrf_millionths(rank, k):
    """One RRF term over a channel rank: round-half-up(PPM / (k + rank)). Integer, deterministic."""
    if rank is None or rank < 1:
        return 0
    d = k + int(rank)
    return (PPM + d // 2) // d


def _occurrences_of(hit):
    """retrieval_occurrences[] for RRF: the candidate's per-channel ranks (P1-2). A candidate seen only in
    the fused/retrieval order (no per-channel rank) contributes one `retrieval` occurrence."""
    occ = []
    lr = hit.get("lexical_rank")
    vr = hit.get("vector_rank")
    if isinstance(lr, int):
        occ.append({"channel": "lexical", "rank": lr})
    if isinstance(vr, int):
        occ.append({"channel": "vector", "rank": vr})
    if not occ:
        fr = hit.get("fused_rank")
        if not isinstance(fr, int):
            fr = hit.get("rank")
        if isinstance(fr, int):
            occ.append({"channel": "retrieval", "rank": fr})
    return occ


def _dedup_key(hit):
    """Identical-TEXT key for occurrence-preserving display dedup (P1-3): the chunk-text hash when present,
    else the source version + byte span, else the source path + span label."""
    cch = str(hit.get("chunk_content_hash") or "")
    if cch:
        return "cch\0" + cch
    ss, se = hit.get("span_start"), hit.get("span_end")
    if ss is not None and se is not None:
        return "sp\0%s\0%s\0%s" % (_norm_path(hit.get("source_path", "")), ss, se)
    return "pl\0%s\0%s" % (_norm_path(hit.get("source_path", "")), str(hit.get("span_label") or ""))


def _cand_key(hit):
    """A stable string identity for features_by_candidate."""
    rv = hit.get("record_version_id")
    if rv:
        return str(rv)
    return "%s\0%s\0%s\0%s" % (_norm_path(hit.get("source_path", "")), str(hit.get("chunk_id", "")),
                               str(hit.get("span_start")), str(hit.get("span_end")))


# ------------------------------------------------------------------ the staged policy

def _score_candidate(hit, descriptor, params):
    """Stages 1-4 for ONE candidate: hard filters, temporal, authority, RRF fusion feature. Returns
    (base_score, features, reason_codes_partial). base_score matches the shipped `_rerank_base` EXACTLY."""
    W = params["weights"]
    auth_rank = params["authority_rank"]
    rrf_k = params["rrf_k"]

    rel = _rel_of(hit)
    auth = auth_rank.get(hit.get("authority_level"), 0)
    fresh = _fresh_rank(hit.get("status"))
    proj = 1 if (descriptor.get("namespace") and hit.get("namespace") == descriptor.get("namespace")) else 0
    comp = 0
    comps = descriptor.get("component")
    if comps:
        comps = comps if isinstance(comps, list) else [comps]
        if any(_norm_path(hit.get("source_path", "")).startswith(_norm_path(c)) for c in comps):
            comp = 1
    stage = 0
    ts = descriptor.get("task_stage")
    if ts and hit.get("record_kind") in TASK_STAGE_KINDS.get(ts, ()):
        stage = 1
    fail = 1 if (descriptor.get("seeking_failures") and hit.get("record_kind") == "failure") else 0
    proc = 1 if (ts in ("act", "implement") and hit.get("record_kind") == "procedure") else 0

    base = (W["relevance"] * rel + W["authority"] * auth + W["freshness"] * fresh +
            W["project"] * proj + W["component"] * comp + W["task_stage"] * stage +
            W["failure"] * fail + W["procedural"] * proc)

    reasons = []
    # (3) authority
    if auth > 0:
        reasons.append("authority_boost")

    # (1) HARD FILTERS -- forbidden / privacy / deleted
    hard = False
    hard_reason = None
    for f in params["hard_filter"]:
        if _matches(hit, f):
            hard = True
            hard_reason = f.get("reason", "forbidden")
            break
    if not hard and hit.get("status") == "deleted":
        hard = True
        hard_reason = "deleted"
    if hard:
        base -= params["hard_demote"]
        reasons.append("hard_filter_" + (hard_reason or "forbidden"))

    # (2) TEMPORAL -- stale demote under current_only
    is_stale = False
    if params["current_only"]:
        is_stale = hit.get("status") in STALE_STATUSES
        if not is_stale:
            for s in params["stale"]:
                if _matches(hit, s):
                    is_stale = True
                    break
        if not is_stale:
            for req in params["required_versions"]:
                if (req.get("content_hash") and
                        _norm_path(hit.get("source_path", "")) == _norm_path(req["source_path"]) and
                        str(hit.get("content_hash", "")) != str(req["content_hash"])):
                    is_stale = True
                    break
        if is_stale:
            base -= params["stale_penalty"]
            reasons.append("stale_demote")

    # (4) RANK FUSION -- versioned RRF over channel ranks (retrieval_occurrences)
    occ = _occurrences_of(hit)
    rrf = sum(_rrf_millionths(o["rank"], rrf_k) for o in occ)
    reasons.append("fusion_rrf")

    features = {
        "relevance": rel, "authority": auth, "freshness": fresh, "project": proj,
        "component": comp, "task_stage": stage, "failure": fail, "procedural": proc,
        "hard_demote": hard, "stale": is_stale, "rrf_score": rrf,
        "occurrence_count": len(occ), "base_score": base,
    }
    return base, features, reasons, occ


def _resolve_params(params):
    """Normalize params + apply defaults (pure)."""
    p = dict(params or {})
    weights = dict(RERANK_W)
    if isinstance(p.get("weights"), dict):
        weights.update({k: int(v) for k, v in p["weights"].items()})
    authority_rank = dict(AUTHORITY_RANK)
    if isinstance(p.get("authority_rank"), dict):
        authority_rank.update({k: int(v) for k, v in p["authority_rank"].items()})
    budget = p.get("budget") if isinstance(p.get("budget"), dict) else None

    def _matchers(key):
        out = []
        for m in (p.get(key) or []):
            if isinstance(m, dict) and m.get("source_path"):
                out.append({"source_path": _norm_path(m.get("source_path")),
                            "content_hash": (str(m["content_hash"]) if m.get("content_hash") else None),
                            "reason": m.get("reason")})
        return out

    return {
        "rrf_k": int(p.get("rrf_k", RRF_K_DEFAULT)),
        "weights": weights,
        "authority_rank": authority_rank,
        "hard_demote": int(p.get("hard_demote", RERANK_HARD_DEMOTE)),
        "stale_penalty": int(p.get("stale_penalty", RERANK_STALE_PENALTY)),
        "diversity_penalty": int(p.get("diversity_penalty", RERANK_DIVERSITY_PENALTY)),
        "current_only": bool(p.get("current_only", False)),
        "dedup_display": bool(p.get("dedup_display", False)),
        "hard_filter": _matchers("hard_filter"),
        "stale": _matchers("stale"),
        "required_versions": _matchers("required_versions"),
        "budget": budget,
        "per_item_overhead": int(p.get("per_item_overhead", 0)),
    }


def _est_tokens(hit):
    """Token cost for the budget hook: the hit's token_count if present, else ceil(chars/4) of the snippet
    (the documented #40 heuristic). Deterministic, integer."""
    tc = hit.get("token_count")
    if isinstance(tc, int):
        return tc
    s = str(hit.get("snippet") or "")
    return (len(s) + 3) // 4


def select(candidates, descriptor, policy_id=POLICY_ID, params=None):
    """The ONE deterministic selection policy (CONTEXT_PACKET_CONTRACT s4). See the module header.

    Returns { selected[], ranked[], policy_id, policy_version, features_by_candidate, omission_manifest[],
    stages }. PURE: `candidates` is never mutated; every returned hit is a COPY carrying additive fields."""
    if policy_id not in KNOWN_POLICIES:
        raise ValueError("unknown selection policy_id: %r (known: %s)" % (policy_id, sorted(KNOWN_POLICIES)))
    descriptor = descriptor or {}
    P = _resolve_params(params)
    if descriptor.get("time_horizon") == "current_only":
        P["current_only"] = True

    # ---- Stages 1-4: score every candidate (order-independent) ----
    scored = []
    features_by_candidate = {}
    for idx, hit in enumerate(candidates):
        base, feats, reasons, occ = _score_candidate(hit, descriptor, P)
        orig_rank = hit.get("rank")
        if not isinstance(orig_rank, int):
            orig_rank = idx + 1
        scored.append({"hit": hit, "idx": idx, "base": base, "feats": feats,
                       "reasons": reasons, "occ": occ, "orig_rank": orig_rank})

    # ---- Stage 5a: greedy source-diversity ordering (byte-identical to the shipped reranker) ----
    remaining = list(scored)
    source_count = {}
    ordered = []
    while remaining:
        best_i = None
        best_key = None
        for i, s in enumerate(remaining):
            sp = _norm_path(s["hit"].get("source_path", ""))
            penalty = P["diversity_penalty"] * source_count.get(sp, 0)
            eff = s["base"] - penalty
            key = (-eff, s["orig_rank"])
            if best_key is None or key < best_key:
                best_key = key
                best_i = i
        chosen = remaining.pop(best_i)
        sp = _norm_path(chosen["hit"].get("source_path", ""))
        chosen["diversity_penalty"] = P["diversity_penalty"] * source_count.get(sp, 0)
        chosen["effective"] = chosen["base"] - chosen["diversity_penalty"]
        if chosen["diversity_penalty"] > 0:
            chosen["reasons"].append("diversity_capped")
        source_count[sp] = source_count.get(sp, 0) + 1
        ordered.append(chosen)

    # ---- Stage 5b: occurrence-preserving DISPLAY dedup (P1-3; optional, default OFF) ----
    # Identical text collapses into ONE display item carrying occurrences[] + evidence_cluster_id, and the
    # cluster's RRF is re-fused over the UNION of member channel ranks. Provenance is NEVER erased -- the
    # folded members are recorded in occurrences[] (and stay in ranked[] flagged display_duplicate).
    cluster_of = {}
    if P["dedup_display"]:
        for s in ordered:
            dk = _dedup_key(s["hit"])
            head = cluster_of.get(dk)
            if head is None:
                s["cluster_head"] = True
                s["cluster_id"] = "ec_" + _sha16(dk)
                s["cluster_members"] = [s]
                cluster_of[dk] = s
            else:
                s["cluster_head"] = False
                s["cluster_id"] = head["cluster_id"]
                s["reasons"].append("display_duplicate")
                head["cluster_members"].append(s)
        # re-fuse RRF over each cluster's combined occurrences
        for head in cluster_of.values():
            combined = []
            for m in head["cluster_members"]:
                combined.extend(m["occ"])
            head["cluster_rrf"] = sum(_rrf_millionths(o["rank"], P["rrf_k"]) for o in combined)
            head["cluster_occurrences"] = combined

    # ---- Stage 6: budget + emit additive fields ----
    omission = []
    max_selected = None
    max_tokens = None
    if P["budget"]:
        if P["budget"].get("max_selected") is not None:
            max_selected = int(P["budget"]["max_selected"])
        if P["budget"].get("max_tokens") is not None:
            max_tokens = int(P["budget"]["max_tokens"])
    kept = 0
    used_tokens = 0
    ranked = []
    selected = []
    for pos, s in enumerate(ordered):
        hit = s["hit"]
        out = dict(hit)  # COPY -- never mutate the input
        selection_rank = pos + 1
        # additive: preserve the channel ranks, add the selection fields
        if "retrieval_rank" not in out:
            out["retrieval_rank"] = s["orig_rank"]
        out["selection_rank"] = selection_rank
        out["selection_score"] = s["effective"]
        out["selection_policy_id"] = POLICY_ID
        out["retrieval_occurrences"] = s["occ"]
        out["rrf_score"] = s["feats"]["rrf_score"]
        out["rank"] = selection_rank  # the reordered view's rank is the selection rank (original untouched)

        is_display_dup = (P["dedup_display"] and not s.get("cluster_head", True))
        hard = s["feats"]["hard_demote"]

        if P["dedup_display"] and s.get("cluster_head"):
            out["evidence_cluster_id"] = s.get("cluster_id")
            occs = []
            for m in s.get("cluster_members", [s]):
                mh = m["hit"]
                occs.append({
                    "record_version_id": mh.get("record_version_id"),
                    "source_path": _norm_path(mh.get("source_path", "")),
                    "chunk_id": str(mh.get("chunk_id", "")),
                    "content_hash": str(mh.get("content_hash", "")),
                    "retrieval_rank": m["orig_rank"],
                    "channels": [o["channel"] for o in m["occ"]],
                })
            out["occurrences"] = occs
            out["rrf_score"] = s.get("cluster_rrf", out["rrf_score"])
        elif is_display_dup:
            out["evidence_cluster_id"] = s.get("cluster_id")

        # selection decision (hard filter -> excluded; display-dup -> not a display item; budget -> omitted)
        sel = True
        if hard:
            sel = False
        elif is_display_dup:
            sel = False
        else:
            cost = _est_tokens(hit) + P["per_item_overhead"]
            if max_selected is not None and kept >= max_selected:
                sel = False
                s["reasons"].append("budget_omitted")
                omission.append({"record_version_id": hit.get("record_version_id"),
                                 "source_path": _norm_path(hit.get("source_path", "")),
                                 "chunk_id": str(hit.get("chunk_id", "")),
                                 "reason": "max_selected", "selection_rank": selection_rank})
            elif max_tokens is not None and (used_tokens + cost) > max_tokens:
                sel = False
                s["reasons"].append("budget_omitted")
                omission.append({"record_version_id": hit.get("record_version_id"),
                                 "source_path": _norm_path(hit.get("source_path", "")),
                                 "chunk_id": str(hit.get("chunk_id", "")),
                                 "reason": "token_budget", "token_estimate": cost,
                                 "selection_rank": selection_rank})
            else:
                kept += 1
                used_tokens += cost

        if sel:
            s["reasons"].append("selected")
            if selection_rank < s["orig_rank"]:
                s["reasons"].insert(0, "rescued")

        # deterministic, de-duplicated reason codes in stable stage order
        order = ["rescued", "hard_filter_forbidden", "hard_filter_privacy", "hard_filter_deleted",
                 "hard_filter_source", "stale_demote", "authority_boost", "fusion_rrf",
                 "diversity_capped", "display_duplicate", "budget_omitted", "selected"]
        seen = set()
        codes = []
        for c in s["reasons"]:
            cc = c if c in order else c
            if cc not in seen:
                seen.add(cc)
                codes.append(cc)
        codes.sort(key=lambda c: (order.index(c) if c in order else len(order), c))
        out["selected"] = sel
        out["reason_codes"] = codes

        feats = dict(s["feats"])
        feats["diversity_penalty"] = s["diversity_penalty"]
        feats["effective_score"] = s["effective"]
        feats["selection_rank"] = selection_rank
        feats["selected"] = sel
        feats["reason_codes"] = codes
        features_by_candidate[_cand_key(hit)] = feats

        ranked.append(out)
        if sel:
            selected.append(out)

    return {
        "policy_id": POLICY_ID,
        "policy_version": POLICY_VERSION,
        "selected": selected,
        "ranked": ranked,
        "features_by_candidate": features_by_candidate,
        "omission_manifest": omission,
        "stages": ["hard_filter", "temporal", "authority", "rank_fusion_rrf", "diversity", "budget"],
    }


def rerank_compat(candidates, descriptor, params=None):
    """Legacy adapter for #37's `rerank()`: returns (reordered_hits, diagnostics) BYTE-IDENTICAL to the
    shipped standalone reranker (dedup_display=False, no budget). The measured A/B now measures THIS library.
    diagnostics carry ONLY the 9 legacy feature keys so the shipped report bytes are preserved."""
    res = select(candidates, descriptor, POLICY_ID, params)
    reordered = res["ranked"]
    diagnostics = []
    legacy_keys = ("relevance", "authority", "freshness", "project", "component",
                   "task_stage", "failure", "procedural", "hard_demote")
    for out in reordered:
        feats = res["features_by_candidate"][_cand_key(out)]
        diagnostics.append({
            "source_path": _norm_path(out.get("source_path", "")),
            "chunk_id": str(out.get("chunk_id", "")),
            "from_rank": out.get("retrieval_rank", out.get("rank")),
            "to_rank": out.get("selection_rank"),
            "features": {k: feats[k] for k in legacy_keys},
            "base_score": feats["base_score"],
            "diversity_penalty": feats["diversity_penalty"],
            "effective_score": feats["effective_score"],
        })
    return reordered, diagnostics

