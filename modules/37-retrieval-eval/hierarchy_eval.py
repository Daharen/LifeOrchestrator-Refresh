#!/usr/bin/env python3
# hierarchy_eval.py -- the Tier-1 HIERARCHY evaluation harness for retrieval.eval (Life Orchestrator module 37
# `retrieval.eval` 0.6.0, contract v0.6; i34 Lane B HIERARCHY-EVAL, plan fo-34-584fd656, D-0098/D-0090/D-0077).
#
# WHAT THIS IS
#   MEASURES the Tier-1 bounded-fanout hierarchy that #36 (builder + shortlist/descend) and #40 (plan +
#   retrieval_completeness) build, so the hierarchy can be ACCEPTED. It is the eval half of the D-0077 fold:
#   the orchestrator wires the REAL #36 tree + #40 packet behind the same measures via the external_command
#   adapter (the seam retrieval.eval already ships for the retriever). This module MEASURES; it never builds the
#   tree, the compiler plan, the working-memory store, or the router (NON-GOALS).
#
#   THE RED-TEAM CONCERN THIS DEFENDS (pack b4c90545, research/2026-08-04-i34-hierarchy-design-redteam.md):
#   *bounded deterministic navigation is NOT automatically recall-preserving.* A bounded LOSSY synopsis
#   (entity_union / lexical_descriptor / centroid) can omit the feature that makes a required leaf relevant, and
#   a bounded BEAM can silently exclude the sole required branch -- producing a packet that looks answerable
#   having never exposed the evidence. So we measure DUAL recall (hierarchy-PATH reached vs end-to-end
#   PACKET-EVIDENCE retained), the SAFE-PRUNING contract (a branch is excluded ONLY when a sound no-false-negative
#   predicate proves absence; otherwise the compiler falls back / returns needs_expansion), and adversarial
#   scale/mutation fixtures with KNOWN pinned outcomes -- and we FLAG the real ~200MB rehearsal as the open
#   pre-freeze gate (synthetic scale is necessary, NOT sufficient).
#
# DETERMINISM: everything derives from FIXED inputs (a synthetic seed = an integer in the request; leaf content
#   is a pure function of its index) -- NO wall-clock, NO uuid, NO Math.random. Canonical JSON is integer-only
#   (ratios in ppm), sort_keys, ensure_ascii, one trailing LF, UTF-8 no BOM -> byte-identical on a re-run,
#   cross-machine. CPU-only, stdlib-only, no model, no network.
#
# INVOCATION (by the pwsh entrypoint -Op hierarchy-eval; also runnable directly):
#   python3 hierarchy_eval.py --request <request.json>
#   request = { op:"hierarchy-eval", out_dir, scales?:[int...], seed?:int, fanout?:int, beam?:int,
#               adapter?:{kind:"synthetic"} | {kind:"external_command", ...},  ns_policy_path? }
#   Writes out_dir/{hierarchy_report.json, hierarchy_report.md, worker-summary.json}; prints "OK <out_dir>".

import sys
import os
import json
import hashlib
import argparse

GENERATOR_NAME = "retrieval.eval/hierarchy"
GENERATOR_VERSION = "0.6.0"
EVAL_REPORT_SCHEMA = "lifeorch.hierarchy_eval_report/0.1"
HIERARCHY_EVAL_VERSION = "hierarchy_eval_v1"
PRUNE_POLICY_ID = "safe_prune_v1"          # mirrors #36 s13.7 / #40 V3
DEFAULT_SCALES = [16, 64, 256, 1024, 4096]  # >=2 orders of magnitude of leaves
DEFAULT_FANOUT = 4
DEFAULT_BEAM = 2
DESCRIPTOR_TOPN = 8


class HEError(Exception):
    def __init__(self, code, message, retryable=False):
        super().__init__(message)
        self.code = code; self.message = message; self.retryable = retryable


def log(msg):
    s = str(msg)
    if len(s) > 300:
        s = s[:300] + "...[+%d]" % (len(s) - 300)
    sys.stderr.write("[retrieval.eval/hierarchy] " + s + "\n")


# ----------------------------------------------------------------- determinism helpers
def canon_bytes(obj):
    s = json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
    return (s + "\n").encode("utf-8")


def sha256_hex(b):
    return hashlib.sha256(b).hexdigest()


def digest(obj):
    return "sha256:" + sha256_hex(canon_bytes(obj))


def _h(*parts):
    return int(sha256_hex(canon_bytes(list(parts)))[:12], 16)


def ppm(num, den):
    """Integer parts-per-million ratio (deterministic; den==0 -> 0)."""
    if den == 0:
        return 0
    return (num * 1000000) // den


def percentile(sorted_vals, p):
    """Deterministic integer percentile (nearest-rank) over a pre-sorted int list."""
    if not sorted_vals:
        return 0
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    rank = (p * (len(sorted_vals) - 1) + 50) // 100  # nearest-rank on 0..n-1, integer
    if rank < 0:
        rank = 0
    if rank >= len(sorted_vals):
        rank = len(sorted_vals) - 1
    return sorted_vals[rank]


# ----------------------------------------------------------------- Bloom presence filter (SOUND absence)
class PresenceFilter:
    """A deterministic Bloom-style membership filter. `absent(token)` is SOUND: True => the token is DEFINITELY
    absent from the subtree (a valid prune). False => maybe present (keep). No false negatives (recall-safe).
    A false positive only causes an extra branch to be examined -- never a missed leaf."""
    __slots__ = ("bits", "m", "k")

    def __init__(self, tokens, m=None, k=3):
        n = max(1, len(tokens))
        self.m = m if m else max(64, 8 * n)
        self.k = k
        self.bits = 0
        for t in tokens:
            for i in range(self.k):
                self.bits |= (1 << (_h("bloom", i, t) % self.m))

    def _maybe_present(self, token):
        for i in range(self.k):
            if not (self.bits & (1 << (_h("bloom", i, token) % self.m))):
                return False
        return True

    def absent(self, token):
        return not self._maybe_present(token)


# ----------------------------------------------------------------- synthetic corpus + tree
def make_leaf(i, namespace="nsA", rare_terms=None, dominant_entity=None):
    """A deterministic synthetic leaf record. tokens/entities are pure functions of i."""
    rare_terms = rare_terms or {}
    group = i % 8
    sub = (i // 8) % 8
    tokens = set(["common", "t%d" % group, "s%d" % sub, "leaf%d" % (i % 32)])
    entities = set(["e%d" % (i % 16)])
    if dominant_entity is not None:
        entities.add(dominant_entity)          # one entity in (almost) every leaf
    if i in rare_terms:
        tokens.add(rare_terms[i])              # a rare DECISIVE term in exactly one leaf
    return {
        "leaf_id": "L%06d" % i,
        "namespace": namespace,
        "sort_key": "/g%d/s%d/%06d" % (group, sub, i),
        "tokens": tokens,
        "entities": entities,
        "status": "current",
        "version": 1,
    }


def build_tree(leaves, fanout):
    """Deterministic BALANCED bottom-up bounded-fanout build (red-team delta 8): total order by (sort_key,
    leaf_id) -> pages of <= fanout -> internal nodes -> ... -> one root. Returns (nodes, root_id, edges).
    Each node carries a synopsis: entity_union + lexical_descriptor (bounded, RANKING ONLY) + a SOUND
    presence_filter + subtree_generation/synopsis_generation + a canonical subtree token set (for measurement)."""
    ordered = sorted(leaves, key=lambda r: (r["sort_key"], r["leaf_id"]))
    nodes = {}
    edges = []           # (parent_id, child_id)
    node_counter = [0]

    def new_node_id(level):
        node_counter[0] += 1
        return "N%d_%05d" % (level, node_counter[0])

    def leaf_node(members):
        nid = new_node_id(0)
        subtree_tokens = set()
        entity_freq = {}
        for m in members:
            subtree_tokens |= m["tokens"]
            for e in m["entities"]:
                entity_freq[e] = entity_freq.get(e, 0) + 1
        nodes[nid] = _mk_node(nid, 0, [m["leaf_id"] for m in members], members, subtree_tokens, entity_freq)
        for m in members:
            edges.append((nid, m["leaf_id"]))
        return nid

    # bottom level: page leaves
    level_ids = []
    i = 0
    while i < len(ordered):
        page = ordered[i:i + fanout]
        level_ids.append(leaf_node(page))
        i += fanout
    level = 1
    # internal levels
    leaf_by_id = {r["leaf_id"]: r for r in ordered}
    while len(level_ids) > 1:
        parents = []
        j = 0
        while j < len(level_ids):
            group = level_ids[j:j + fanout]
            nid = new_node_id(level)
            subtree_tokens = set()
            entity_freq = {}
            for cid in group:
                subtree_tokens |= nodes[cid]["_subtree_tokens"]
                for e, f in nodes[cid]["_entity_freq"].items():
                    entity_freq[e] = entity_freq.get(e, 0) + f
                edges.append((nid, cid))
            nodes[nid] = _mk_node(nid, level, list(group), None, subtree_tokens, entity_freq)
            parents.append(nid)
            j += fanout
        level_ids = parents
        level += 1
    root_id = level_ids[0]
    return nodes, root_id, edges, leaf_by_id


def _mk_node(nid, level, child_ids, leaf_members, subtree_tokens, entity_freq):
    # bounded lexical_descriptor + entity_union (RANKING ONLY -- never prunes)
    lex = sorted(subtree_tokens)[:DESCRIPTOR_TOPN]
    ent = [e for e, _ in sorted(entity_freq.items(), key=lambda kv: (-kv[1], kv[0]))][:DESCRIPTOR_TOPN]
    return {
        "node_id": nid,
        "level": level,
        "child_ids": list(child_ids),                 # PROJECTION (rebuildable); edges are canonical
        "lexical_descriptor": lex,                     # bounded, RANKING ONLY
        "entity_union": ent,                           # bounded, RANKING ONLY
        "presence_filter": PresenceFilter(subtree_tokens),   # SOUND absence
        "subtree_generation": 1,
        "synopsis_generation": 1,
        "synopsis_stale": False,
        "synopsis_input_digest": sha256_hex(canon_bytes(sorted(subtree_tokens))),
        "_subtree_tokens": subtree_tokens,             # measurement-only ground truth (not a runtime field)
        "_entity_freq": entity_freq,
    }


# ----------------------------------------------------------------- shortlist / descend (safe-pruning)
def descriptor_score(node, query_tokens):
    return len(set(node["lexical_descriptor"]) & query_tokens) + len(set(node["entity_union"]) & query_tokens)


def descend(nodes, root_id, leaf_by_id, query, eff_allowed_ns, beam, guaranteed=False,
            allow_stale_prune=False):
    """The fast-path beam descend with the SAFE-PRUNING contract. Returns a nav result dict measuring nodes
    examined, reached leaves, pruning, fallback, unresolved branches, stale-navigation, and namespace isolation.

    Authorization (H6): every hop is namespace-checked; a node outside eff_allowed_ns is NEVER examined
    (confused-deputy defense). SAFE-PRUNING (s13.7): a child is excluded ONLY if a SOUND predicate proves the
    query term absent (presence_filter.absent). A bounded descriptor/beam may only RE-ORDER; a non-safe-pruned
    child left out of the beam is UNRESOLVED (-> fallback / needs_expansion), never silently dropped. A STALE
    synopsis is NEVER eligible to prune (unless allow_stale_prune models the UNSAFE variant for the gate)."""
    from collections import namedtuple
    q_tokens = set(query["tokens"])
    decisive = query.get("decisive")
    nodes_examined = 0
    pruned = 0
    prune_reasons = {}
    unresolved = 0
    stale_encountered = 0
    ns_violations = 0
    reached = set()
    # a node's namespace is the namespace of its leaves; derive from any subtree leaf deterministically
    def node_ns(nid):
        n = nodes[nid]
        cid = n["child_ids"][0]
        while cid in nodes:
            cid = nodes[cid]["child_ids"][0]
        return leaf_by_id[cid]["namespace"]

    if node_ns(root_id) not in eff_allowed_ns:
        # unauthorized root -> fail closed, no examination, no leakage
        return _navresult(0, 0, {}, 0, 0, 1, set(), True, False)

    frontier = [root_id]
    while frontier:
        nxt = []
        for nid in frontier:
            n = nodes[nid]
            nodes_examined += 1
            # leaf-node: collect leaves (safe-pruned already by parent decision)
            if n["level"] == 0:
                for lid in n["child_ids"]:
                    if leaf_by_id[lid]["namespace"] in eff_allowed_ns:
                        reached.add(lid)
                    else:
                        pass  # cannot happen in a homogeneous tree; homogeneity is asserted at build
                continue
            # rank children by descriptor (RANKING ONLY)
            scored = []
            for cid in n["child_ids"]:
                child = nodes[cid]
                # authorization at every hop
                if node_ns(cid) not in eff_allowed_ns:
                    ns_violations += 1
                    continue
                # SAFE-PRUNING: sound absence only
                stale = child["synopsis_stale"]
                can_prune = False
                if decisive is not None:
                    if stale and not allow_stale_prune:
                        stale_encountered += 1     # stale routes, never prunes (recall-safe)
                    else:
                        if child["presence_filter"].absent(decisive):
                            can_prune = True
                if can_prune:
                    pruned += 1
                    prune_reasons["presence_filter_absent"] = prune_reasons.get("presence_filter_absent", 0) + 1
                else:
                    scored.append((descriptor_score(child, q_tokens), cid))
            # order by descriptor desc, tie-break by id (deterministic)
            scored.sort(key=lambda t: (-t[0], t[1]))
            if guaranteed:
                keep = [cid for _, cid in scored]     # explore ALL non-safe-pruned (guaranteed recall)
            else:
                keep = [cid for _, cid in scored[:beam]]
                dropped = scored[beam:]
                unresolved += len(dropped)            # non-safe-pruned but beam-excluded => UNRESOLVED
            nxt.extend(keep)
        frontier = nxt

    frontier_exhausted = (unresolved == 0 and ns_violations == 0)
    fallback_used = unresolved > 0
    return _navresult(nodes_examined, pruned, prune_reasons, unresolved, stale_encountered,
                      ns_violations, reached, False, frontier_exhausted)


def _navresult(nodes_examined, pruned, prune_reasons, unresolved, stale_encountered, ns_violations,
               reached, unauthorized, frontier_exhausted):
    return {
        "nodes_examined": nodes_examined,
        "pruned_branch_count": pruned,
        "prune_reasons": prune_reasons,
        "unresolved_branch_count": unresolved,
        "stale_navigation_encountered": stale_encountered,
        "namespace_violations": ns_violations,
        "reached_leaves": reached,
        "unauthorized": unauthorized,
        "frontier_exhausted": frontier_exhausted,
        "fallback_used": unresolved > 0,
    }


def model_packet(nav, required_leaf, flat_leaves):
    """Model #40's packet-stage outcome (V3 retrieval_completeness). If the fast path reached the required
    leaf -> answerable + retained. Else if not frontier_exhausted -> fallback injects the FLAT batch (recall
    preserved) -> the required leaf is retained IF present in the corpus -> disposition answerable_via_fallback;
    if fallback still cannot resolve -> needs_expansion. A hierarchy MISS is NEVER a false 'answerable'."""
    reached = nav["reached_leaves"]
    if required_leaf in reached:
        return {"packet_recall": 1, "disposition": "answerable", "retained": True, "fallback_used": False}
    if not nav["frontier_exhausted"]:
        # unresolved branches remain -> fallback / needs_expansion (never a proved absence)
        if required_leaf in flat_leaves:
            return {"packet_recall": 1, "disposition": "answerable_via_fallback", "retained": True,
                    "fallback_used": True}
        return {"packet_recall": 0, "disposition": "needs_expansion", "retained": False, "fallback_used": True}
    # frontier exhausted (safe pruning proved absence) -> a correct non-answer if the leaf truly absent
    if required_leaf not in flat_leaves:
        return {"packet_recall": 1, "disposition": "abstain", "retained": False, "fallback_used": False}
    # required leaf present but frontier_exhausted excluded it -> a SILENT FALSE-NEGATIVE (the bug we guard).
    return {"packet_recall": 0, "disposition": "answerable", "retained": False, "fallback_used": False}


def naive_descend(nodes, root_id, leaf_by_id, query, eff_allowed_ns, beam):
    """The UNSAFE baseline the red-team warns about: a bounded beam that NEGATIVELY excludes non-beam branches
    using the lossy descriptor (no safe-pruning proof, and it treats beam-exclusion as proved absence ->
    frontier_exhausted). Used ONLY to DEMONSTRATE the defect the safe model prevents."""
    q_tokens = set(query["tokens"])
    reached = set()
    nodes_examined = 0
    frontier = [root_id]
    while frontier:
        nxt = []
        for nid in frontier:
            n = nodes[nid]
            nodes_examined += 1
            if n["level"] == 0:
                for lid in n["child_ids"]:
                    reached.add(lid)
                continue
            scored = sorted(((descriptor_score(nodes[cid], q_tokens), cid) for cid in n["child_ids"]),
                            key=lambda t: (-t[0], t[1]))
            nxt.extend([cid for _, cid in scored[:beam]])   # DROP the rest as if proved absent (UNSAFE)
        frontier = nxt
    return {"nodes_examined": nodes_examined, "reached_leaves": reached, "frontier_exhausted": True}


# ----------------------------------------------------------------- measure 1+2: navigation-cost + dual recall
def _query_targets(n):
    q = min(8, n)
    return [(i * n) // q for i in range(q)]


def measure_scales(scales, seed, fanout, beam):
    """Measure NODES EXAMINED vs LEAF COUNT across scales (>=2 orders of magnitude) + DUAL recall.
    Localized decisive-term queries: safe-pruning proves absence of the term in sibling branches, so the
    frontier stays bounded (~ B * depth ~ log_F N) -- NOT constant, NOT linear."""
    per_scale = []
    for n in scales:
        targets = _query_targets(n)
        rare = {i: "decisive_%06d" % i for i in targets}
        leaves = [make_leaf(i, rare_terms=rare) for i in range(n)]
        nodes, root, edges, leaf_by_id = build_tree(leaves, fanout)
        internal = sum(1 for v in nodes.values() if v["level"] > 0) + sum(1 for v in nodes.values() if v["level"] == 0)
        depth = max(v["level"] for v in nodes.values())
        flat = set(r["leaf_id"] for r in leaves)
        cost = []
        path_hits = 0
        packet_hits = 0
        for i in targets:
            q = {"tokens": {"common", rare[i]}, "decisive": rare[i]}
            required = "L%06d" % i
            nav = descend(nodes, root, leaf_by_id, q, {"nsA"}, beam)
            cost.append(nav["nodes_examined"])
            if required in nav["reached_leaves"]:
                path_hits += 1
            pkt = model_packet(nav, required, flat)
            if pkt["packet_recall"] == 1:
                packet_hits += 1
        cost.sort()
        per_scale.append({
            "leaf_count": n,
            "node_count": len(nodes),
            "depth": depth,
            "queries": len(targets),
            "nodes_examined_p50": percentile(cost, 50),
            "nodes_examined_p95": percentile(cost, 95),
            "nodes_examined_max": cost[-1] if cost else 0,
            "nodes_examined_over_leaves_ppm": ppm(percentile(cost, 50), n),
            "hierarchy_path_recall_ppm": ppm(path_hits, len(targets)),
            "packet_evidence_recall_ppm": ppm(packet_hits, len(targets)),
        })
    # sub-linearity: nodes_examined/leaf_count must STRICTLY DECREASE as N grows across >=2 orders of magnitude,
    # and p50 must grow no faster than ~depth (log). Assert not-constant AND sub-linear.
    ratios = [s["nodes_examined_over_leaves_ppm"] for s in per_scale]
    sublinear = all(ratios[k] >= ratios[k + 1] for k in range(len(ratios) - 1)) and ratios[0] > ratios[-1]
    p50s = [s["nodes_examined_p50"] for s in per_scale]
    not_constant = p50s[-1] > p50s[0]                        # depth grows with N (design's "constant" is wrong)
    # log-shaped: doubling-of-scale growth in p50 is bounded (<= fanout per extra level), never multiplicative
    span = scales[-1] // max(1, scales[0])                   # >=2 orders of magnitude
    log_shaped = p50s[-1] <= p50s[0] + fanout * (max(v for v in [s["depth"] for s in per_scale]))
    return {
        "per_scale": per_scale,
        "scale_span_x": span,
        "sublinear": bool(sublinear),
        "not_constant": bool(not_constant),
        "log_shaped": bool(log_shaped),
    }


def measure_dual_recall(seed, fanout, beam):
    """DUAL recall + shortlist regret + fallback frequency + stale-window recall on a corpus with an
    ADVERSARIAL descriptor-masked query set (the beam cannot rank the target; safe-pruning cannot prune it)."""
    n = 256
    # SPAN ALL sort-groups (avoid the synthetic-alignment trap where every target lands in the lowest group the
    # beam always keeps): i*(n//8)+i spreads targets across groups 0..7, so the fast beam GENUINELY misses the
    # higher-group targets while safe-pruning cannot prune them -> the recall gap the fallback must cover.
    targets = [i * (n // 8) + i for i in range(8)]
    # NO decisive term -> nothing is safely prunable -> the beam drops non-target branches as UNRESOLVED.
    leaves = [make_leaf(i) for i in range(n)]
    nodes, root, edges, leaf_by_id = build_tree(leaves, fanout)
    flat = set(r["leaf_id"] for r in leaves)
    path_hits = fast_reach = packet_hits = fallback_count = regret_sum = 0
    guaranteed_hits = 0
    for i in targets:
        required = "L%06d" % i
        # an ambiguous query: only 'common' (shared by all) -> descriptor cannot distinguish the target
        q = {"tokens": {"common"}, "decisive": None}
        nav = descend(nodes, root, leaf_by_id, q, {"nsA"}, beam)
        gnav = descend(nodes, root, leaf_by_id, q, {"nsA"}, beam, guaranteed=True)
        if required in nav["reached_leaves"]:
            fast_reach += 1
        if required in gnav["reached_leaves"]:
            guaranteed_hits += 1
        pkt = model_packet(nav, required, flat)
        if pkt["packet_recall"] == 1:
            packet_hits += 1
        if nav["fallback_used"]:
            fallback_count += 1
        # shortlist regret: best-reachable (guaranteed) minus fast-path reached (1 if fast missed but guar hit)
        regret_sum += (1 if (required in gnav["reached_leaves"] and required not in nav["reached_leaves"]) else 0)
    # stale-window recall: a stale synopsis routes but never prunes -> recall preserved while stale-serving
    for v in nodes.values():
        if v["level"] > 0:
            v["synopsis_stale"] = True
    stale_hits = 0
    stale_targets = _query_targets(n)
    stale_rare = {i: "decisive_%06d" % i for i in stale_targets}
    sleaves = [make_leaf(i, rare_terms=stale_rare) for i in range(n)]
    snodes, sroot, sedges, sleaf_by_id = build_tree(sleaves, fanout)
    for v in snodes.values():
        if v["level"] > 0:
            v["synopsis_stale"] = True
    sflat = set(r["leaf_id"] for r in sleaves)
    for i in stale_targets:
        required = "L%06d" % i
        q = {"tokens": {"common", stale_rare[i]}, "decisive": stale_rare[i]}
        nav = descend(snodes, sroot, sleaf_by_id, q, {"nsA"}, beam)   # stale => no prune, routes
        pkt = model_packet(nav, required, sflat)
        if pkt["packet_recall"] == 1:
            stale_hits += 1
    return {
        "queries": len(targets),
        "hierarchy_path_recall_ppm": ppm(fast_reach, len(targets)),      # fast beam (may be < 1)
        "guaranteed_path_recall_ppm": ppm(guaranteed_hits, len(targets)),  # explore-all (== 1)
        "packet_evidence_recall_ppm": ppm(packet_hits, len(targets)),    # fallback preserves it (== 1)
        "shortlist_regret_ppm": ppm(regret_sum, len(targets)),
        "fallback_frequency_ppm": ppm(fallback_count, len(targets)),
        "stale_window_recall_ppm": ppm(stale_hits, len(stale_targets)),
    }


# ----------------------------------------------------------------- measure 3: adversarial fixtures (pinned)
def adversarial_fixtures(fanout, beam):
    out = []

    def add(name, passed, detail):
        out.append({"fixture": name, "passed": bool(passed), "detail": detail})

    # (A) rare DECISIVE term / ambiguous query -> SAFE model falls back (recall preserved); NAIVE model
    #     silently misses (false answerable). THE core demonstration.
    n = 256
    leaves = [make_leaf(i) for i in range(n)]
    nodes, root, edges, leaf_by_id = build_tree(leaves, fanout)
    flat = set(r["leaf_id"] for r in leaves)
    required = "L%06d" % (n - 1)
    q = {"tokens": {"common"}, "decisive": None}
    safe = descend(nodes, root, leaf_by_id, q, {"nsA"}, beam)
    safe_pkt = model_packet(safe, required, flat)
    naive = naive_descend(nodes, root, leaf_by_id, q, {"nsA"}, beam)
    naive_miss = required not in naive["reached_leaves"] and naive["frontier_exhausted"]
    add("rare_decisive_term_ambiguous",
        (safe_pkt["packet_recall"] == 1 and naive_miss and not safe["frontier_exhausted"]),
        {"safe_disposition": safe_pkt["disposition"], "safe_packet_recall_ppm": ppm(safe_pkt["packet_recall"], 1),
         "naive_silent_miss": naive_miss, "safe_fallback_used": safe["fallback_used"]})

    # (B) cross-namespace CONTAMINATION: an nsA compile must NEVER reach an nsB leaf; descend(nsB) fails closed.
    mixed = [make_leaf(i, namespace=("nsB" if i % 2 else "nsA")) for i in range(64)]
    # homogeneous per-namespace trees (delta 6): build separate trees per namespace
    nsA_leaves = [r for r in mixed if r["namespace"] == "nsA"]
    nsB_leaves = [r for r in mixed if r["namespace"] == "nsB"]
    aN, aR, aE, aL = build_tree(nsA_leaves, fanout)
    bN, bR, bE, bL = build_tree(nsB_leaves, fanout)
    # a query scoped to nsA can never see nsB; an attempt to descend the nsB root under nsA fails closed
    unauth = descend(bN, bR, bL, {"tokens": {"common"}, "decisive": None}, {"nsA"}, beam)
    leak = any(bL.get(lid, {}).get("namespace") == "nsB" for lid in unauth["reached_leaves"])
    add("cross_namespace_contamination",
        (unauth["unauthorized"] and unauth["nodes_examined"] == 0 and not leak),
        {"unauthorized_descend_failed_closed": unauth["unauthorized"], "nsB_leaves_leaked": int(leak),
         "nodes_examined": unauth["nodes_examined"]})

    # (C) MUTATION-during-regen (ABA / lost-update): Boolean-stale falsely clears; monotonic generation + CAS
    #     detects it (fresh IFF synopsis_generation covers subtree_generation AND input_digest matches).
    node = {"subtree_generation": 1, "synopsis_generation": 1, "synopsis_stale": False,
            "synopsis_input_digest": "d1"}
    # mutation 1 -> mark stale + bump subtree gen
    node["subtree_generation"] = 2; node["synopsis_stale"] = True
    # regen starts from the OLD snapshot (still gen1 input) ...
    regen_from = {"gen": 1, "input_digest": "d1"}
    # mutation 2 (concurrent) -> subtree gen 3, new input
    node["subtree_generation"] = 3
    canonical_input_digest = "d3"
    # NAIVE Boolean clear: regen completes -> clears stale -> falsely fresh
    naive_fresh = True   # (a bare boolean clear ignores that the input changed under it)
    # CAS/generation clear: fresh IFF synopsis_generation covers subtree_generation AND input matches
    node["synopsis_generation"] = regen_from["gen"]      # regen only advanced synopsis to gen1's view
    cas_fresh = (node["synopsis_generation"] >= node["subtree_generation"]
                 and regen_from["input_digest"] == canonical_input_digest)
    add("mutation_during_regen_aba",
        (naive_fresh is True and cas_fresh is False),
        {"naive_boolean_false_fresh": naive_fresh, "cas_generation_detects_stale": (not cas_fresh)})

    # (D) STALE node never prunes (routes only): a stale synopsis that WOULD prune a required branch must not.
    sleaves = [make_leaf(i, rare_terms={n - 1: "decisive_%06d" % (n - 1)}) for i in range(0)]
    dn = [make_leaf(i, rare_terms={255: "decisive_000255"}) for i in range(256)]
    dnodes, droot, dedges, dleaf = build_tree(dn, fanout)
    for v in dnodes.values():
        if v["level"] > 0:
            v["synopsis_stale"] = True
    dq = {"tokens": {"common", "decisive_000255"}, "decisive": "decisive_000255"}
    dnav = descend(dnodes, droot, dleaf, dq, {"nsA"}, beam)             # stale => cannot prune
    dnav_unsafe = descend(dnodes, droot, dleaf, dq, {"nsA"}, beam, allow_stale_prune=True)  # models the bug
    add("stale_node_no_false_negative_prune",
        ("L000255" in dnav["reached_leaves"] and dnav["stale_navigation_encountered"] > 0),
        {"stale_routes_reached_required": ("L000255" in dnav["reached_leaves"]),
         "stale_encounters": dnav["stale_navigation_encountered"]})

    # (E) EXACT + GLOBAL mixture: an exact decisive term is cheap (few nodes); a global term is the explicit
    #     slow path (examines far more) -- NOT claimed constant.
    gl = [make_leaf(i, rare_terms={i: "decisive_%06d" % i for i in range(256)}) for i in range(256)]
    glnodes, glroot, gledges, glleaf = build_tree(gl, fanout)
    exact_nav = descend(glnodes, glroot, glleaf,
                        {"tokens": {"decisive_000100"}, "decisive": "decisive_000100"}, {"nsA"}, beam)
    global_nav = descend(glnodes, glroot, glleaf, {"tokens": {"common"}, "decisive": None}, {"nsA"}, beam)
    add("exact_cheap_global_slow",
        (exact_nav["nodes_examined"] < global_nav["nodes_examined"] and not global_nav["frontier_exhausted"]),
        {"exact_nodes": exact_nav["nodes_examined"], "global_nodes": global_nav["nodes_examined"],
         "global_frontier_exhausted": global_nav["frontier_exhausted"]})

    return out


# ----------------------------------------------------------------- measure 4: the Tier-1 gate set
def tier1_gates(scales, seed, fanout, beam, nav_summary, dual, adversarial):
    gates = []

    def g(dim, name, passed, detail):
        gates.append({"dimension": dim, "gate": name, "passed": bool(passed), "detail": detail})

    # STRUCTURAL: deterministic byte-identical rebuild; fanout bound; one parent; projection==edges; no cycles
    n = 256
    leaves = [make_leaf(i) for i in range(n)]
    a_nodes, a_root, a_edges, _ = build_tree(leaves, fanout)
    b_nodes, b_root, b_edges, _ = build_tree(leaves, fanout)
    edge_digest_a = digest(sorted(a_edges))
    edge_digest_b = digest(sorted(b_edges))
    fanout_ok = all(len(v["child_ids"]) <= fanout for v in a_nodes.values())
    parents = {}
    for (p, c) in a_edges:
        parents[c] = parents.get(c, 0) + 1
    one_parent = all(v == 1 for v in parents.values())
    proj_ok = all(sorted([c for (p, c) in a_edges if p == nid]) == sorted(a_nodes[nid]["child_ids"])
                  for nid in a_nodes)
    g("structural", "deterministic_rebuild_byte_identical", edge_digest_a == edge_digest_b,
      {"edge_digest": edge_digest_a})
    g("structural", "fanout_bounded", fanout_ok, {"max_fanout": fanout})
    g("structural", "exactly_one_parent", one_parent, {})
    g("structural", "projection_equals_edges", proj_ok, {})

    # SECURITY/ISOLATION
    contam = next(f for f in adversarial if f["fixture"] == "cross_namespace_contamination")
    g("security", "zero_cross_namespace_leakage_and_failclosed_descend", contam["passed"], contam["detail"])

    # MUTATION/FRESHNESS
    aba = next(f for f in adversarial if f["fixture"] == "mutation_during_regen_aba")
    stale = next(f for f in adversarial if f["fixture"] == "stale_node_no_false_negative_prune")
    g("mutation_freshness", "no_lost_update_stale_clear", aba["passed"], aba["detail"])
    g("mutation_freshness", "stale_node_no_false_negative_prune", stale["passed"], stale["detail"])

    # RETRIEVAL
    rare = next(f for f in adversarial if f["fixture"] == "rare_decisive_term_ambiguous")
    g("retrieval", "guaranteed_or_fallback_preserves_recall", rare["passed"], rare["detail"])
    g("retrieval", "end_to_end_packet_recall_full",
      dual["packet_evidence_recall_ppm"] == 1000000, {"packet_recall_ppm": dual["packet_evidence_recall_ppm"]})
    g("retrieval", "stale_window_recall_full",
      dual["stale_window_recall_ppm"] == 1000000, {"stale_window_recall_ppm": dual["stale_window_recall_ppm"]})

    # COMPLEXITY
    g("complexity", "navigation_cost_sublinear_p50_p95",
      (nav_summary["sublinear"] and nav_summary["not_constant"] and nav_summary["log_shaped"]),
      {"sublinear": nav_summary["sublinear"], "not_constant": nav_summary["not_constant"],
       "log_shaped": nav_summary["log_shaped"]})

    passed_count = sum(1 for x in gates if x["passed"])
    return gates, passed_count


# ----------------------------------------------------------------- measure 5: the real-corpus rehearsal (OPEN)
def rehearsal_scaffold():
    return {
        "status": "OPEN",
        "kind": "real_foreign_corpus_rehearsal",
        "target_bytes": 209715200,
        "reason": "Synthetic scale is NECESSARY but NOT SUFFICIENT: synthetic generation can accidentally align "
                  "query vocabulary / grouping keys / labels in ways a real repository does not. Tier-1 "
                  "acceptance MUST NOT be claimed on synthetic-only.",
        "plan": {
            "corpus": "a >=~200MB slice of a real foreign codebase/doc corpus (never shaped for our schemas)",
            "queries": "manually-labeled cross-cutting + rare-decisive-evidence queries with pinned "
                       "must_include spans (chunk/span level, not file level)",
            "measures": ["hierarchy_path_recall", "packet_evidence_recall", "navigation_cost_p50_p95_vs_leaf_count",
                         "shortlist_regret", "fallback_frequency", "stale_window_recall"],
            "runner": "wire the REAL #36 shortlist/descend + #40 packet behind this harness via the "
                      "external_command adapter (retriever.kind=external_command), then re-run these measures",
        },
        "gate_role": "pre-FREEZE / pre-ACTIVATION gate (the orchestrator or a later wave runs it; NOT this wave)",
    }


# ----------------------------------------------------------------- report + dispatch
def build_report(scales, seed, fanout, beam):
    nav = measure_scales(scales, seed, fanout, beam)
    dual = measure_dual_recall(seed, fanout, beam)
    adversarial = adversarial_fixtures(fanout, beam)
    gates, gates_passed = tier1_gates(scales, seed, fanout, beam, nav, dual, adversarial)
    rehearsal = rehearsal_scaffold()
    adv_passed = sum(1 for f in adversarial if f["passed"])
    synthetic_gates_pass = (gates_passed == len(gates)) and (adv_passed == len(adversarial))
    report = {
        "schema": EVAL_REPORT_SCHEMA,
        "generator": GENERATOR_NAME,
        "generator_version": GENERATOR_VERSION,
        "hierarchy_eval_version": HIERARCHY_EVAL_VERSION,
        "prune_policy_id": PRUNE_POLICY_ID,
        "ratio_unit": "ppm",
        "params": {"scales": list(scales), "seed": seed, "fanout": fanout, "beam": beam,
                   "descriptor_topn": DESCRIPTOR_TOPN},
        "navigation_cost": nav,
        "dual_recall": dual,
        "adversarial_fixtures": adversarial,
        "adversarial_passed": adv_passed,
        "adversarial_total": len(adversarial),
        "tier1_gate_set": gates,
        "tier1_gates_passed": gates_passed,
        "tier1_gates_total": len(gates),
        "rehearsal_gate": rehearsal,
        "tier1_acceptance": {
            "synthetic_gates_passed": bool(synthetic_gates_pass),
            "rehearsal_gate_status": rehearsal["status"],
            "accepted": False,
            "reason": "synthetic gates are a necessary pre-check; Tier-1 acceptance is GATED on the OPEN "
                      "real-corpus rehearsal + the D-0077 fold wiring the real #36/#40 behind these measures.",
        },
    }
    report["report_digest"] = digest(report)
    return report


def render_md(report):
    nav = report["navigation_cost"]
    dual = report["dual_recall"]
    lines = []
    lines.append("# Tier-1 hierarchy eval report (%s)" % report["hierarchy_eval_version"])
    lines.append("")
    lines.append("Prune policy: `%s`. Ratios in ppm. Deterministic (report_digest %s)."
                 % (report["prune_policy_id"], report["report_digest"]))
    lines.append("")
    lines.append("## Navigation cost (nodes examined vs leaf count)")
    lines.append("")
    lines.append("| leaves | nodes | depth | p50 | p95 | p50/leaves(ppm) | path_recall(ppm) | packet_recall(ppm) |")
    lines.append("|--:|--:|--:|--:|--:|--:|--:|--:|")
    for s in nav["per_scale"]:
        lines.append("| %d | %d | %d | %d | %d | %d | %d | %d |" % (
            s["leaf_count"], s["node_count"], s["depth"], s["nodes_examined_p50"], s["nodes_examined_p95"],
            s["nodes_examined_over_leaves_ppm"], s["hierarchy_path_recall_ppm"], s["packet_evidence_recall_ppm"]))
    lines.append("")
    lines.append("sub-linear=%s not_constant=%s log_shaped=%s (scale span %dx)"
                 % (nav["sublinear"], nav["not_constant"], nav["log_shaped"], nav["scale_span_x"]))
    lines.append("")
    lines.append("## Dual recall (fast beam vs guaranteed vs packet)")
    lines.append("")
    lines.append("- hierarchy_path_recall (fast beam): %d ppm" % dual["hierarchy_path_recall_ppm"])
    lines.append("- guaranteed_path_recall (explore-all): %d ppm" % dual["guaranteed_path_recall_ppm"])
    lines.append("- packet_evidence_recall (fallback preserves): %d ppm" % dual["packet_evidence_recall_ppm"])
    lines.append("- shortlist_regret: %d ppm | fallback_frequency: %d ppm | stale_window_recall: %d ppm"
                 % (dual["shortlist_regret_ppm"], dual["fallback_frequency_ppm"], dual["stale_window_recall_ppm"]))
    lines.append("")
    lines.append("## Adversarial fixtures: %d/%d passed" % (report["adversarial_passed"], report["adversarial_total"]))
    for f in report["adversarial_fixtures"]:
        lines.append("- %s: %s" % (f["fixture"], "PASS" if f["passed"] else "FAIL"))
    lines.append("")
    lines.append("## Tier-1 gate set: %d/%d passed" % (report["tier1_gates_passed"], report["tier1_gates_total"]))
    for gt in report["tier1_gate_set"]:
        lines.append("- [%s] %s: %s" % (gt["dimension"], gt["gate"], "PASS" if gt["passed"] else "FAIL"))
    lines.append("")
    lines.append("## Rehearsal gate: %s (OPEN pre-freeze gate)" % report["rehearsal_gate"]["status"])
    lines.append("")
    lines.append("**Tier-1 acceptance: accepted=%s** -- %s" % (
        report["tier1_acceptance"]["accepted"], report["tier1_acceptance"]["reason"]))
    return "\n".join(lines) + "\n"


def run_request(req):
    op = req.get("op", "hierarchy-eval")
    if op != "hierarchy-eval":
        raise HEError("bad_op", "hierarchy_eval.py handles op=hierarchy-eval (got %r)" % op, False)
    out_dir = req.get("out_dir") or "."
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    scales = req.get("scales") or DEFAULT_SCALES
    scales = [int(x) for x in scales]
    seed = int(req.get("seed", 0))
    fanout = int(req.get("fanout", DEFAULT_FANOUT))
    beam = int(req.get("beam", DEFAULT_BEAM))
    if fanout < 2:
        raise HEError("bad_fanout", "fanout must be >= 2", False)
    if len(scales) < 2 or (max(scales) // max(1, min(scales))) < 100:
        raise HEError("bad_scales", "scales must span >= 2 orders of magnitude (max/min >= 100)", False)

    adapter = req.get("adapter") or {"kind": "synthetic"}
    if adapter.get("kind") not in ("synthetic", "external_command"):
        raise HEError("bad_adapter", "adapter.kind must be synthetic | external_command", False)
    # external_command wiring of the REAL #36/#40 is the orchestrator's D-0077 fold step; this worker ships the
    # deterministic synthetic model + the seam. If external_command is requested here, it is a NON-goal stub.
    if adapter.get("kind") == "external_command":
        raise HEError("external_command_deferred",
                      "the external_command adapter (real #36/#40) is wired at the D-0077 fold; run synthetic here",
                      False)

    report = build_report(scales, seed, fanout, beam)
    with open(os.path.join(out_dir, "hierarchy_report.json"), "wb") as f:
        f.write(canon_bytes(report))
    with open(os.path.join(out_dir, "hierarchy_report.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(render_md(report))

    summary = {
        "ok": True,
        "op": "hierarchy-eval",
        "hierarchy_eval_version": HIERARCHY_EVAL_VERSION,
        "scales": scales,
        "sublinear": report["navigation_cost"]["sublinear"],
        "not_constant": report["navigation_cost"]["not_constant"],
        "hierarchy_path_recall_ppm": report["dual_recall"]["hierarchy_path_recall_ppm"],
        "guaranteed_path_recall_ppm": report["dual_recall"]["guaranteed_path_recall_ppm"],
        "packet_evidence_recall_ppm": report["dual_recall"]["packet_evidence_recall_ppm"],
        "fallback_frequency_ppm": report["dual_recall"]["fallback_frequency_ppm"],
        "stale_window_recall_ppm": report["dual_recall"]["stale_window_recall_ppm"],
        "adversarial_passed": report["adversarial_passed"],
        "adversarial_total": report["adversarial_total"],
        "tier1_gates_passed": report["tier1_gates_passed"],
        "tier1_gates_total": report["tier1_gates_total"],
        "rehearsal_gate_status": report["rehearsal_gate"]["status"],
        "tier1_accepted": report["tier1_acceptance"]["accepted"],
        "report_digest": report["report_digest"],
        "input_digest": digest({"scales": scales, "seed": seed, "fanout": fanout, "beam": beam}),
    }
    with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
        f.write(canon_bytes(summary))
    return summary


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    args = ap.parse_args(argv)
    with open(args.request, "r", encoding="utf-8") as f:
        req = json.load(f)
    out_dir = req.get("out_dir") or "."
    try:
        run_request(req)
        sys.stdout.write("OK %s\n" % out_dir)
        return 0
    except HEError as e:
        err = {"ok": False, "error": {"code": e.code, "message": e.message, "retryable": e.retryable}}
        try:
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
                f.write(canon_bytes(err))
        except Exception:
            pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"]))
        log("ERROR %s: %s" % (e.code, e.message))
        return 1
    except Exception as e:  # noqa
        err = {"ok": False, "error": {"code": "unhandled", "message": str(e), "retryable": False}}
        try:
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, "worker-summary.json"), "wb") as f:
                f.write(canon_bytes(err))
        except Exception:
            pass
        sys.stdout.write("ERR %s\n" % json.dumps(err["error"]))
        log("UNHANDLED: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

