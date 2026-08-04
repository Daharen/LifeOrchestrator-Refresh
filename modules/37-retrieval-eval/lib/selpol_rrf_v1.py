#!/usr/bin/env python3
# selpol_rrf_v1.py -- the ONE versioned DETERMINISTIC selection-policy library (Life Orchestrator
# module 37 `retrieval.eval`, contract v0.4 / CONTEXT_PACKET_CONTRACT s4 [PINNED D-0089] + the i32
# amendment [D-0092]; P1-1; plans fo-30-dd453156 / fo-31 / fo-32-0fb25203).
#
# WHAT THIS IS (CONTEXT_PACKET_CONTRACT.md s4 -- the FROZEN interface, PINNED scoring D-0089)
#   ONE selection owner. Extracted from #37's shipped deterministic `rerank()` so there is exactly one
#   selection implementation, OWNED here and CONSUMED by the context compiler #40 AND by #37's own eval
#   A/B -- removing the "two rerankers" problem (P1-1). PURE + DETERMINISTIC: no model, no I/O, no state,
#   no wall-clock, no randomness. Byte-identical selection on re-run, cross-machine.
#
#   INTERFACE (frozen, s4):
#     select(candidates, descriptor, policy_id="selpol_rrf_v1", params=None)
#       -> { selected[], ranked[], policy_id, policy_version, features_by_candidate,
#            omission_manifest[], stages, contradicts_pairs[] }
#
#   INPUTS
#     candidates  -- the MEMORY_CONTRACT s3 retriever-0.2 hit array (normalized dicts; each carries
#                    retrieval_rank (`rank`), lexical_rank, vector_rank, fused_rank + scores, status,
#                    authority_level, namespace, record_kind, source_path, chunk_id, chunk_content_hash,
#                    span_start/span_end/span_label, token_count, snippet, retrieval_channels; and -- i32 --
#                    OPTIONAL retrieval_occurrences[] [{channel,rank}], superseded_by / supersedes /
#                    contradicts / edges|record_edges [{type,target}] supersession + conflict edges).
#     descriptor  -- the UNIFIED selection descriptor (s4 reconciliation of #40's task fields + #37's
#                    rerank_descriptor): { namespace?, component?, relevant_paths?, task_type?,
#                    task_stage?, time_horizon?, seeking_failures?, permission_context?, query_class? }.
#     policy_id   -- namespaced+versioned; only 'selpol_rrf_v1' is known this wave (fail-closed otherwise).
#     params      -- policy knobs + the caller's POLICY SIGNALS (kept out of the candidate scan so the
#                    library stays pure -- the caller supplies what it is permitted/labelled to demote):
#                      rrf_k(int=60), weights{}, authority_rank{}, diversity_penalty, hard_demote,
#                      stale_penalty, current_only(bool), temporal_mode(str), query_class(str),
#                      allowed_namespaces(set|list|str), dedup_display(bool=False),
#                      hard_filter[{source_path, content_hash?, reason}], stale[{source_path, content_hash?}],
#                      required_versions[{source_path, content_hash}], budget{max_selected?, max_tokens?,
#                      per_item_overhead?}.
#                    #40 supplies allowed_namespaces (from task_input.namespace / the control_plane grant),
#                    hard_filter from control_plane.permission_grants / permission_context, query_class from
#                    its compiler front, and relies on the candidate's own s5 `status` + supersession edges
#                    for the temporal stage; #37's eval wrapper maps its benchmark labels
#                    (forbidden/privacy/stale/required version/namespace/query_class) into the same params.
#
#   STAGES (deterministic, versioned baseline -- s4 + the i32 amendment), in order, each accruing reason_codes:
#     (1) NAMESPACE     -- i32/U1: allowed_namespaces is a HARD boundary; a cross-namespace candidate is SUNK
#                          (reason `hard_filter_namespace`). When allowed_namespaces is supplied the soft
#                          namespace/'project-match' descriptor bonus is RETIRED (component/task_stage/failure/
#                          procedural descriptor matches REMAIN, intra-namespace). ABSENT allowed_namespaces =
#                          the 1.0.0 soft-project-bonus path, byte-identical (back-compat; #40 ALWAYS supplies it).
#     (2) HARD FILTERS  -- forbidden / privacy / deleted sink (hard demote) + selected=False.
#     (3) TEMPORAL      -- i32/U4: under the resolved `current_only` mode a non-`current` candidate (its own s5
#                          `status`, an eval `stale[]` label, or a required-version mismatch) is HARD-filtered
#                          (`hard_filter_stale`), NOT soft-demoted. The 1.0.0 SOFT `stale_penalty`/`stale_demote`
#                          SURVIVES ONLY for the non-current_only `prefer_current` mode. `any`/historical/
#                          version-specific modes allow stale (no temporal action). The temporal MODE is resolved
#                          from query_class (U5) / time_horizon / the explicit current_only|temporal_mode knobs.
#     (4) SUPERSESSION  -- i32/U4: RANK-AFFECTING. When a superseded candidate AND its live successor BOTH
#                          survive filtering, the superseded one is ordered STRICTLY BELOW its successor
#                          (`superseded_demote`), independent of selection_score (a stable topological reorder
#                          over the stage-5 order; identity permutation when there are no supersession edges).
#     (5) AUTHORITY     -- epistemic_authority weighting (a TRUST signal, never execution authority).
#     (6) RANK FUSION   -- versioned RRF over CHANNEL RANKS (retrieval_occurrences[]), NOT cross-query raw
#                          scores (P1-2). i32/U5: the channel set is FROZEN OPEN -- an explicit
#                          retrieval_occurrences[] is honored channel-AGNOSTICALLY, so a graph/temporal/etc.
#                          channel fuses with NO code change (lexical+vector are NOT hard-coded).
#     (7) DIVERSITY     -- greedy source-diversity + (dedup_display) occurrence-preserving clustering that
#                          dedups DISPLAY tokens, NEVER provenance: identical text collapses to ONE display
#                          item carrying occurrences[] + evidence_cluster_id (P1-3).
#     (8) BUDGET        -- a budget hook (max_selected / max_tokens); overflow -> omission_manifest.
#   CONTRADICTS (i32/U4): a `contradicts` edge between two SELECTED current items is PROPAGATED (surfaced in
#     `contradicts_pairs[]` + the involved features) for the compiler's `conflicted` disposition. This library
#     PROPAGATES the edge; it does NOT DETECT contradictions (detection is Tier 2).
#
#   OUTPUT is ADDITIVE -- it NEVER re-sorts the retrieval array in place. Each ranked candidate is a COPY of
#   its input hit that PRESERVES retrieval_rank / lexical_rank / vector_rank / fused_rank and ADDS
#   selection_rank, selection_score (integer millionths/points), selection_policy_id, selected (bool),
#   reason_codes[], retrieval_occurrences[], rrf_score, and (in a dedup cluster) occurrences[] +
#   evidence_cluster_id. The input list is not mutated.
#
#   BACK-COMPAT / REGRESSION (1.0.0 -> 1.1.0, additive; SCHEMA_NOTES s14): the i32 stages engage ONLY when
#   their signals are supplied -- allowed_namespaces (namespace boundary + soft-bonus retirement), a resolved
#   current_only mode (hard stale filter), supersession edges (superseded_demote), an explicit
#   retrieval_occurrences[] (open channels), query_class (temporal mode). With NONE of them (the 1.0.0
#   default call) select() reproduces 1.0.0 selection BYTE-IDENTICALLY. A current_only caller on all-`current`
#   candidates is ALSO byte-identical; the ONLY intended divergence is current_only + a stale candidate
#   (1.0.0 soft-demoted -> 1.1.0 hard-excludes -- the A4 semantic; the old soft demote lives on as the
#   `prefer_current` mode). RRF-over-channel-ranks stays the `rrf_score` FEATURE + `fusion_rrf` code; pure
#   rank-RRF as the PRIMARY sort is still the deferred P1-2.

import hashlib

POLICY_ID = "selpol_rrf_v1"
POLICY_VERSION = "1.1.0"
KNOWN_POLICIES = frozenset([POLICY_ID])

PPM = 1000000
RRF_K_DEFAULT = 60

# The ordered stage list (i32: namespace_filter + supersession added to the s4 baseline).
STAGES = ["namespace_filter", "hard_filter", "temporal", "supersession", "authority",
          "rank_fusion_rrf", "diversity", "budget"]

# ---- feature weights (the frozen baseline; the shipped RERANK_W, now owned HERE) ----
RERANK_W = {
    "relevance": 1,          # x direct relevance (the retriever fused/lexical score, millionths)
    "authority": 3 * PPM,    # x authority level rank
    "freshness": 6 * PPM,    # x freshness rank
    "project": 2 * PPM,      # namespace match (i32: soft bonus RETIRED when allowed_namespaces is supplied)
    "component": 2 * PPM,    # path-prefix match
    "task_stage": 2 * PPM,   # record_kind matches the task stage
    "failure": 2 * PPM,      # failure-seeking + record_kind==failure
    "procedural": 2 * PPM,   # action stage + record_kind==procedure
}
RERANK_HARD_DEMOTE = 1000 * PPM      # forbidden / privacy / deleted / namespace / stale -> sink to the bottom
RERANK_STALE_PENALTY = 20 * PPM      # prefer_current + a stale hit (the surviving SOFT demote)
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

# i32/U5: query_class -> temporal MODE (MEMORY_ARCHITECTURE s5 planner). A deterministic Tier-0 STUB -- the
# multi-channel query-aware ROUTER is Tier 1; this is the default when current_only is not explicitly set.
#   current_only    : the question is about the CURRENT truth -> HARD-exclude stale.
#   prefer_current  : prefer current but do not exclude -> SOFT stale_demote (the surviving 1.0.0 soft path).
#   historical_as_of / version_specific / any_valid_version : allow stale (no temporal action).
# Rationale per class in SCHEMA_NOTES s14. (Absent query_class -> `any`, the byte-identical default path.)
QUERY_CLASS_TEMPORAL_MODE = {
    "current_state": "current_only",
    "procedure_selection": "current_only",
    "local_factual": "prefer_current",
    "global_synthesis": "prefer_current",
    "exact_reference": "version_specific",
    "historical_reconstruction": "historical_as_of",
    "temporal_change": "any_valid_version",
    "causal_diagnosis": "any_valid_version",
    "precedent_search": "any_valid_version",
}
# The modes that HARD-exclude / SOFT-demote stale; everything else allows stale.
MODE_CURRENT_ONLY = "current_only"
MODE_PREFER_CURRENT = "prefer_current"
KNOWN_TEMPORAL_MODES = frozenset([
    "current_only", "prefer_current", "historical_as_of", "version_specific", "any_valid_version", "any",
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
    """retrieval_occurrences[] for RRF: the candidate's per-channel ranks (P1-2). i32/U5: the channel set is
    FROZEN OPEN -- an explicit `retrieval_occurrences` list [{channel,rank}] is honored channel-AGNOSTICALLY
    (a graph/temporal/etc. channel fuses with NO code change). Otherwise derive from the named channel ranks
    (lexical/vector) then the fused/retrieval order (a candidate seen only in the fused order contributes one
    `retrieval` occurrence). Back-compat: a hit WITHOUT retrieval_occurrences yields exactly the 1.0.0 set."""
    ro = hit.get("retrieval_occurrences")
    if isinstance(ro, list) and ro:
        occ = []
        for o in ro:
            if isinstance(o, dict) and o.get("channel") is not None and isinstance(o.get("rank"), int):
                occ.append({"channel": str(o["channel"]), "rank": int(o["rank"])})
        if occ:
            return occ
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


def _ident_label(hit):
    """A human/consumer-facing stable identity for supersession + contradicts pairs."""
    for k in ("record_version_id", "record_id"):
        v = hit.get(k)
        if v:
            return str(v)
    return _cand_key(hit)


def _identities(hit):
    """All identity strings by which this candidate can be REFERENCED by an edge (version + logical id)."""
    out = []
    for k in ("record_version_id", "record_id"):
        v = hit.get(k)
        if v and str(v) not in out:
            out.append(str(v))
    return out


def _id_list(v):
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return [str(x) for x in v if x is not None and str(x) != ""]
    s = str(v)
    return [s] if s != "" else []


def _edge_list(hit):
    for key in ("record_edges", "edges"):
        e = hit.get(key)
        if isinstance(e, list):
            return e
    return []


def _edge_targets(hit, types):
    out = []
    for e in _edge_list(hit):
        if isinstance(e, dict) and e.get("type") in types:
            for tk in ("target", "target_record_version_id", "target_record_id"):
                if e.get(tk) is not None and str(e[tk]) != "":
                    out.append(str(e[tk]))
    return out


def _successor_ids(hit):
    """Identities of records that SUPERSEDE this hit (this hit is superseded_by them)."""
    return _id_list(hit.get("superseded_by")) + _edge_targets(hit, ("superseded_by",))


def _supersedes_ids(hit):
    """Identities of records THIS hit supersedes (this hit is the live successor)."""
    return _id_list(hit.get("supersedes")) + _edge_targets(hit, ("supersedes",))


def _contradicts_ids(hit):
    """Identities of records this hit is declared to CONTRADICT (the A4 `contradicts` edge; symmetric)."""
    return _id_list(hit.get("contradicts")) + _edge_targets(hit, ("contradicts",))


# ------------------------------------------------------------------ the staged policy

def _resolve_temporal_mode(params, descriptor):
    """i32/U4+U5: resolve the effective temporal MODE (pure). Precedence: an explicit current_only bool >
    an explicit temporal_mode string > descriptor.time_horizon=='current_only' > the query_class map (U5) >
    a direct time_horizon mode string > `any` (the byte-identical default)."""
    if params.get("current_only") is True:
        return MODE_CURRENT_ONLY
    tm = params.get("temporal_mode_param")
    if isinstance(tm, str) and tm in KNOWN_TEMPORAL_MODES:
        return tm
    if descriptor.get("time_horizon") == "current_only":
        return MODE_CURRENT_ONLY
    qc = descriptor.get("query_class")
    if not (isinstance(qc, str) and qc):
        qc = params.get("query_class")
    if isinstance(qc, str) and qc in QUERY_CLASS_TEMPORAL_MODE:
        return QUERY_CLASS_TEMPORAL_MODE[qc]
    th = descriptor.get("time_horizon")
    if isinstance(th, str) and th in KNOWN_TEMPORAL_MODES:
        return th
    return "any"


def _score_candidate(hit, descriptor, params):
    """Stages 1-3 + 5-6 for ONE candidate: namespace boundary, hard filters, temporal, authority, RRF fusion
    feature. Returns (base_score, features, reason_codes_partial, occurrences). base_score matches the shipped
    `_rerank_base` EXACTLY on the 1.0.0 default path (allowed_namespaces absent, temporal mode `any`)."""
    W = params["weights"]
    auth_rank = params["authority_rank"]
    rrf_k = params["rrf_k"]
    allowed_ns = params["allowed_namespaces"]        # frozenset | None
    temporal_mode = params["temporal_mode"]

    rel = _rel_of(hit)
    auth = auth_rank.get(hit.get("authority_level"), 0)
    fresh = _fresh_rank(hit.get("status"))
    # i32/U1: the soft project/namespace bonus is RETIRED the moment the HARD namespace boundary is engaged
    # (allowed_namespaces supplied). Absent it -> the 1.0.0 soft bonus (back-compat, byte-identical).
    if allowed_ns is None:
        proj = 1 if (descriptor.get("namespace") and hit.get("namespace") == descriptor.get("namespace")) else 0
    else:
        proj = 0
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
    # (5) authority
    if auth > 0:
        reasons.append("authority_boost")

    # (1) NAMESPACE hard boundary (i32/U1) -- SINK a cross-namespace candidate.
    hard = False
    hard_reason = None
    ns_filtered = False
    if allowed_ns is not None and hit.get("namespace") not in allowed_ns:
        hard = True
        hard_reason = "namespace"
        ns_filtered = True

    # (2) HARD FILTERS -- forbidden / privacy / deleted (unchanged 1.0.0 semantics).
    if not hard:
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

    # (3) TEMPORAL (i32/U4) -- under current_only, stale is HARD-filtered; under prefer_current, SOFT-demoted.
    is_status_stale = hit.get("status") in STALE_STATUSES
    is_label_stale = False
    for s in params["stale"]:
        if _matches(hit, s):
            is_label_stale = True
            break
    if not is_label_stale:
        for req in params["required_versions"]:
            if (req.get("content_hash") and
                    _norm_path(hit.get("source_path", "")) == _norm_path(req["source_path"]) and
                    str(hit.get("content_hash", "")) != str(req["content_hash"])):
                is_label_stale = True
                break
    is_stale = is_status_stale or is_label_stale
    stale_flagged = False
    if temporal_mode == MODE_CURRENT_ONLY:
        if is_stale:
            stale_flagged = True
            if not hard:
                hard = True
                base -= params["hard_demote"]
            reasons.append("hard_filter_stale")
    elif temporal_mode == MODE_PREFER_CURRENT:
        # the 1.0.0 current_only SOFT demote, relocated -- survives ONLY for this non-current_only mode.
        if is_stale:
            stale_flagged = True
            base -= params["stale_penalty"]
            reasons.append("stale_demote")
    # else 'any' / historical_as_of / version_specific / any_valid_version -> allow stale (no temporal action)

    # (6) RANK FUSION -- versioned RRF over channel ranks (retrieval_occurrences)
    occ = _occurrences_of(hit)
    rrf = sum(_rrf_millionths(o["rank"], rrf_k) for o in occ)
    reasons.append("fusion_rrf")

    features = {
        "relevance": rel, "authority": auth, "freshness": fresh, "project": proj,
        "component": comp, "task_stage": stage, "failure": fail, "procedural": proc,
        "hard_demote": hard, "stale": stale_flagged, "rrf_score": rrf,
        "occurrence_count": len(occ), "base_score": base,
        "namespace_filtered": ns_filtered, "temporal_mode": temporal_mode,
        "is_stale": is_stale,
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

    # i32/U1: allowed_namespaces -> a frozenset (a str is wrapped; an explicit empty set filters EVERYTHING,
    # fail-closed). ABSENT (None) = the back-compat soft-project path.
    ans = p.get("allowed_namespaces")
    if ans is None:
        allowed_namespaces = None
    elif isinstance(ans, str):
        allowed_namespaces = frozenset([ans])
    else:
        allowed_namespaces = frozenset(str(x) for x in ans)

    return {
        "rrf_k": int(p.get("rrf_k", RRF_K_DEFAULT)),
        "weights": weights,
        "authority_rank": authority_rank,
        "hard_demote": int(p.get("hard_demote", RERANK_HARD_DEMOTE)),
        "stale_penalty": int(p.get("stale_penalty", RERANK_STALE_PENALTY)),
        "diversity_penalty": int(p.get("diversity_penalty", RERANK_DIVERSITY_PENALTY)),
        "current_only": bool(p.get("current_only", False)),
        "temporal_mode_param": p.get("temporal_mode"),
        "query_class": p.get("query_class"),
        "allowed_namespaces": allowed_namespaces,
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


def _superseded_reorder(ordered):
    """i32/U4: stable topological reorder of the stage-5 `ordered` list so that whenever a superseded candidate
    AND its live successor BOTH survive (are not hard-filtered), the successor precedes the superseded one. The
    base (stage-5) position is the tie-break, so with NO supersession edges this is the IDENTITY permutation
    (byte-identical). Returns (new_ordered, demoted_ids) where demoted_ids is the set of scored-dict ids that
    were marked superseded (a surviving successor exists)."""
    n = len(ordered)
    if n < 2:
        return ordered, set()
    survivor = [not s["feats"]["hard_demote"] for s in ordered]
    # map every reference identity -> the positions that expose it (survivors only, first-wins on collision)
    id_to_pos = {}
    for i, s in enumerate(ordered):
        if not survivor[i]:
            continue
        for idv in _identities(s["hit"]):
            id_to_pos.setdefault(idv, i)
    # constraint edges succ_pos -> superseded_pos (successor must come BEFORE the superseded)
    adj = [[] for _ in range(n)]
    indeg = [0] * n
    edges = set()
    demoted = set()
    for i, s in enumerate(ordered):
        if not survivor[i]:
            continue
        hit = s["hit"]
        succ_ids = _successor_ids(hit)                 # records that supersede THIS (i is superseded)
        for sid in succ_ids:
            j = id_to_pos.get(sid)
            if j is not None and j != i and survivor[j]:
                edges.add((j, i))                      # successor j before superseded i
        for sid in _supersedes_ids(hit):               # THIS supersedes sid (i is the successor)
            j = id_to_pos.get(sid)
            if j is not None and j != i and survivor[j]:
                edges.add((i, j))                      # successor i before superseded j
    for (a, b) in edges:
        adj[a].append(b)
        indeg[b] += 1
        demoted.add(id(ordered[b]))
    if not edges:
        return ordered, set()
    # stable Kahn: always emit the smallest-base-index available node.
    avail = sorted(i for i in range(n) if indeg[i] == 0)
    order = []
    while avail:
        i = avail.pop(0)
        order.append(i)
        for j in adj[i]:
            indeg[j] -= 1
            if indeg[j] == 0:
                # insert j keeping avail sorted ascending (deterministic)
                lo, hi = 0, len(avail)
                while lo < hi:
                    mid = (lo + hi) // 2
                    if avail[mid] < j:
                        lo = mid + 1
                    else:
                        hi = mid
                avail.insert(lo, j)
    if len(order) != n:
        # a cycle left some nodes unresolved -> append them in base order (deterministic, cycle broken).
        seen = set(order)
        order.extend(i for i in range(n) if i not in seen)
    return [ordered[i] for i in order], demoted


def select(candidates, descriptor, policy_id=POLICY_ID, params=None):
    """The ONE deterministic selection policy (CONTEXT_PACKET_CONTRACT s4 [PINNED D-0089] + i32 [D-0092]).
    See the module header.

    Returns { selected[], ranked[], policy_id, policy_version, features_by_candidate, omission_manifest[],
    stages, contradicts_pairs[] }. PURE: `candidates` is never mutated; every returned hit is a COPY carrying
    additive fields."""
    if policy_id not in KNOWN_POLICIES:
        raise ValueError("unknown selection policy_id: %r (known: %s)" % (policy_id, sorted(KNOWN_POLICIES)))
    descriptor = descriptor or {}
    P = _resolve_params(params)
    # resolve the effective temporal mode (i32/U4+U5), then expose the boolean the scorer consumes.
    P["temporal_mode"] = _resolve_temporal_mode(P, descriptor)
    P["current_only"] = (P["temporal_mode"] == MODE_CURRENT_ONLY)

    # ---- Stages 1-3,5-6: score every candidate (order-independent) ----
    scored = []
    features_by_candidate = {}
    for idx, hit in enumerate(candidates):
        base, feats, reasons, occ = _score_candidate(hit, descriptor, P)
        orig_rank = hit.get("rank")
        if not isinstance(orig_rank, int):
            orig_rank = idx + 1
        scored.append({"hit": hit, "idx": idx, "base": base, "feats": feats,
                       "reasons": reasons, "occ": occ, "orig_rank": orig_rank})

    # ---- Stage 7a: greedy source-diversity ordering (byte-identical to the shipped reranker) ----
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

    # ---- Stage 4: supersession demote (i32/U4) -- reorder so a live successor precedes its superseded twin.
    ordered, demoted_ids = _superseded_reorder(ordered)
    for s in ordered:
        if id(s) in demoted_ids:
            s["reasons"].append("superseded_demote")

    # ---- Stage 7b: occurrence-preserving DISPLAY dedup (P1-3; optional, default OFF) ----
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

    # ---- Stage 8: budget + emit additive fields ----
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

        # deterministic, de-duplicated reason codes in stable stage order (i32 codes folded in additively)
        order = ["rescued", "hard_filter_namespace", "hard_filter_forbidden", "hard_filter_privacy",
                 "hard_filter_deleted", "hard_filter_source", "hard_filter_stale", "superseded_demote",
                 "stale_demote", "authority_boost", "fusion_rrf", "diversity_capped", "display_duplicate",
                 "budget_omitted", "selected"]
        seen = set()
        codes = []
        for c in s["reasons"]:
            if c not in seen:
                seen.add(c)
                codes.append(c)
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

    # ---- CONTRADICTS propagation (i32/U4) -- surface pairs among SELECTED evidence for #40's `conflicted`. ----
    contradicts_pairs = _contradicts_among(selected, features_by_candidate)

    return {
        "policy_id": POLICY_ID,
        "policy_version": POLICY_VERSION,
        "selected": selected,
        "ranked": ranked,
        "features_by_candidate": features_by_candidate,
        "omission_manifest": omission,
        "stages": list(STAGES),
        "contradicts_pairs": contradicts_pairs,
        "temporal_mode": P["temporal_mode"],
        "allowed_namespaces": (sorted(P["allowed_namespaces"]) if P["allowed_namespaces"] is not None else None),
    }


def _contradicts_among(selected, features_by_candidate):
    """Propagate the `contradicts` edge (i32/U4): every unordered pair of SELECTED items linked by a
    contradicts edge (either direction). Deterministic (sorted). Also stamps `contradicts_with` on the
    involved features so #40 can drive `packet_disposition = conflicted`. Detection is NOT done here."""
    if not selected:
        return []
    id_to_out = {}
    for out in selected:
        for idv in _identities(out):
            id_to_out.setdefault(idv, out)
    pairs = set()
    for out in selected:
        for tgt in _contradicts_ids(out):
            other = id_to_out.get(tgt)
            if other is not None and other is not out:
                a, b = _ident_label(out), _ident_label(other)
                pairs.add((a, b) if a <= b else (b, a))
    if not pairs:
        return []
    involved = {}
    for (a, b) in pairs:
        involved.setdefault(a, set()).add(b)
        involved.setdefault(b, set()).add(a)
    # stamp features (best-effort: the feature key is the cand_key == record_version_id when present)
    for out in selected:
        lbl = _ident_label(out)
        if lbl in involved:
            fk = _cand_key(out)
            if fk in features_by_candidate:
                features_by_candidate[fk]["contradicts_with"] = sorted(involved[lbl])
    return [{"a": a, "b": b} for (a, b) in sorted(pairs)]


def rerank_compat(candidates, descriptor, params=None):
    """Legacy adapter for #37's `rerank()`: returns (reordered_hits, diagnostics) reproducing the shipped
    standalone reranker on the 1.0.0 default path (dedup_display=False, no budget, no i32 signals). The
    measured A/B now measures THIS library. diagnostics carry ONLY the 9 legacy feature keys so the shipped
    report bytes are preserved. (Under an i32 signal -- allowed_namespaces / current_only+stale / supersession
    edges -- the reordering reflects the new stages; the byte-identity holds for the default path.)"""
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
