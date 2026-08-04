#!/usr/bin/env python3
# test_selpol.py -- library-direct unit gate for selpol_rrf_v1 (CONTEXT_PACKET_CONTRACT s4, P1-1).
# Runs in the cloud pre-ship gate AND on the -Live executor (pure stdlib; no model/IO/network). Asserts the
# s4 interface, purity, determinism, ADDITIVE output, rescue+demote preserving retrieval_rank, RRF over
# channel ranks, and occurrence-preserving display dedup. Exit 0 = all pass.
import os
import sys
import json
import copy
import hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
if MOD not in sys.path:
    sys.path.insert(0, MOD)
from lib import selpol_rrf_v1 as sp

FAIL = [0]


def check(name, cond):
    print(("PASS  " if cond else "FAIL  ") + name)
    if not cond:
        FAIL[0] += 1


def hit(rank, sp_, cch, score, status="current", auth="source_material", lex=None, vec=None, ns="corpus"):
    return {
        "record_id": "r_" + sp_ + str(rank), "record_version_id": "rv_" + sp_ + "_" + str(rank),
        "record_kind": "source_chunk", "source_path": sp_, "content_hash": "sha256:" + cch,
        "chunk_id": sp_ + "#000", "chunk_content_hash": "sha256:" + cch,
        "span_start": 0, "span_end": 10, "span_label": "L", "status": status, "currentness": status,
        "authority_level": auth, "namespace": ns,
        "retrieval_channels": ["lexical"] + (["vector"] if vec is not None else []),
        "lexical_rank": (rank if lex is None else lex), "lexical_score": score,
        "vector_rank": vec, "vector_similarity": (900000 if vec is not None else None),
        "fused_rank": rank, "fused_score": score, "token_count": 5, "snippet": "s", "rank": rank,
    }


# ---- 1. interface + additive output, purity ----
cands = [hit(1, "a.md", "aa", 900000), hit(2, "b.md", "bb", 800000), hit(3, "c.md", "cc", 700000)]
frozen = copy.deepcopy(cands)
res = sp.select(cands, {"namespace": "corpus"}, "selpol_rrf_v1", None)
check("s4 result has selected/ranked/policy_id/policy_version/features_by_candidate",
      all(k in res for k in ("selected", "ranked", "policy_id", "policy_version", "features_by_candidate")))
check("policy_id + version stamped", res["policy_id"] == "selpol_rrf_v1" and res["policy_version"] == sp.POLICY_VERSION)
check("PURE: input candidates not mutated", cands == frozen)
r0 = res["ranked"][0]
check("ADDITIVE: preserves retrieval_rank + channel ranks",
      r0.get("retrieval_rank") == 1 and r0.get("lexical_rank") == 1 and r0.get("fused_rank") == 1)
check("ADDITIVE: adds selection_rank/selection_score/selection_policy_id/selected/reason_codes",
      all(k in r0 for k in ("selection_rank", "selection_score", "selection_policy_id", "selected", "reason_codes")))
check("ranked length == candidates", len(res["ranked"]) == 3)
check("fusion_rrf reason on every candidate", all("fusion_rrf" in h["reason_codes"] for h in res["ranked"]))

# ---- 2. determinism: byte-identical select on re-run ----
b1 = json.dumps(sp.select(copy.deepcopy(cands), {"namespace": "corpus"})["ranked"], sort_keys=True)
b2 = json.dumps(sp.select(copy.deepcopy(cands), {"namespace": "corpus"})["ranked"], sort_keys=True)
check("DETERMINISTIC: byte-identical selection on re-run", b1 == b2)

# ---- 3. unknown policy -> fail-closed ----
try:
    sp.select(cands, {}, "nope_v9")
    check("unknown policy_id raises", False)
except ValueError:
    check("unknown policy_id raises", True)

# ---- 4. RRF over channel ranks: two channels fuse; monotonic single-channel ----
rrf1 = sp._rrf_millionths(1, 60)
rrf2 = sp._rrf_millionths(2, 60)
check("RRF rank-monotonic (rank1 > rank2)", rrf1 > rrf2)
multi = hit(1, "m.md", "mm", 500000, lex=3, vec=1)  # seen in BOTH channels
res_m = sp.select([multi], {})
occ = res_m["ranked"][0]["retrieval_occurrences"]
check("RRF over channel ranks: multi-channel candidate keeps BOTH occurrences", len(occ) == 2)
check("RRF fuses the two channel ranks (> a single occurrence)",
      res_m["ranked"][0]["rrf_score"] == sp._rrf_millionths(3, 60) + sp._rrf_millionths(1, 60))

# ---- 5. rescue + demote preserving retrieval_rank (forbidden at rank 1, required current lower) ----
scn = [hit(1, "forbidden.md", "ff", 900000), hit(2, "stale.md", "ss", 850000, status="source_stale"),
       hit(3, "wanted.md", "ww", 700000)]
params = {"current_only": True, "hard_filter": [{"source_path": "forbidden.md", "reason": "forbidden"}],
          "stale": [{"source_path": "stale.md"}]}
rr = sp.select(scn, {}, "selpol_rrf_v1", params)
top = rr["ranked"][0]
check("RESCUE: current required source promoted to selection_rank 1", top["source_path"] == "wanted.md" and top["selection_rank"] == 1)
check("RESCUE: its retrieval_rank (3) is PRESERVED (additive, never re-sorted in place)", top["retrieval_rank"] == 3)
check("RESCUE: reason_codes include 'rescued' + 'selected'", "rescued" in top["reason_codes"] and "selected" in top["reason_codes"])
forb = [h for h in rr["ranked"] if h["source_path"] == "forbidden.md"][0]
check("DEMOTE: forbidden hit hard-demoted below top-1 + not selected", forb["selection_rank"] > 1 and forb["selected"] is False)
check("DEMOTE: forbidden reason_code present", any(c.startswith("hard_filter") for c in forb["reason_codes"]))
stale = [h for h in rr["ranked"] if h["source_path"] == "stale.md"][0]
check("i32 U4: under current_only a stale hit is HARD-filtered (hard_filter_stale), NOT soft-demoted",
      "hard_filter_stale" in stale["reason_codes"] and stale["selected"] is False)

# ---- 6. occurrence-preserving DISPLAY dedup (identical text -> ONE display item, occurrences kept) ----
dup = [hit(1, "dupe1.md", "SAME", 900000), hit(2, "dupe2.md", "SAME", 800000), hit(3, "other.md", "zz", 700000)]
dd = sp.select(dup, {}, "selpol_rrf_v1", {"dedup_display": True})
heads = [h for h in dd["ranked"] if h.get("evidence_cluster_id") and h.get("occurrences")]
check("DEDUP: identical text collapses to ONE display item", len([h for h in dd["selected"] if h["source_path"] in ("dupe1.md", "dupe2.md")]) == 1)
head = [h for h in dd["ranked"] if h["source_path"] == "dupe1.md"][0]
check("DEDUP: display head carries occurrences[] of BOTH members (provenance NOT erased)",
      isinstance(head.get("occurrences"), list) and len(head["occurrences"]) == 2)
paths = sorted(o["source_path"] for o in head["occurrences"])
check("DEDUP: both source occurrences preserved in the cluster", paths == ["dupe1.md", "dupe2.md"])
check("DEDUP: evidence_cluster_id stable + shared", head["evidence_cluster_id"].startswith("ec_"))
folded = [h for h in dd["ranked"] if h["source_path"] == "dupe2.md"][0]
check("DEDUP: folded member flagged (selected False, display_duplicate)", folded["selected"] is False and "display_duplicate" in folded["reason_codes"])
check("DEDUP: cluster RRF fuses both member ranks",
      head["rrf_score"] == sp._rrf_millionths(1, 60) + sp._rrf_millionths(2, 60))

# ---- 7. budget hook -> omission_manifest ----
bud = sp.select([hit(1, "a.md", "a1", 900000), hit(2, "b.md", "b2", 800000), hit(3, "c.md", "c3", 700000)],
                {}, "selpol_rrf_v1", {"budget": {"max_selected": 2}})
check("BUDGET: max_selected caps selected[]", len(bud["selected"]) == 2)
check("BUDGET: overflow recorded in omission_manifest with reason", len(bud["omission_manifest"]) == 1 and bud["omission_manifest"][0]["reason"] == "max_selected")
check("BUDGET: omitted candidate carries budget_omitted reason", any("budget_omitted" in h["reason_codes"] for h in bud["ranked"] if not h["selected"]))

# ================================================================= i33 (D-0096) NAMESPACE CLOSURE + hardening

# ---- 8. i33/U1' namespace CLOSURE: a cross-namespace candidate is DROPPED (sanitized), not sunk-in-place ----
ns_cands = [hit(1, "in.md", "IN", 900000, ns="projX"), hit(2, "out.md", "OUT", 950000, ns="projY"),
            hit(3, "in2.md", "IN2", 700000, ns="projX")]
res8 = sp.select(ns_cands, {"namespace": "projX"}, "selpol_rrf_v1", {"allowed_namespaces": ["projX"]})
paths8 = [h["source_path"] for h in res8["ranked"]]
check("U1' closure: cross-namespace candidate DROPPED from ranked[] entirely (no leak)", "out.md" not in paths8)
check("U1' closure: cross-namespace candidate absent from selected[] too",
      "out.md" not in [h["source_path"] for h in res8["selected"]])
check("U1' closure: cross-namespace candidate leaves NO features_by_candidate entry",
      "rv_out.md_2" not in res8["features_by_candidate"])
check("U1' closure: SANITIZED surface -> namespace_violation_count == 1 (the ONLY caller-visible signal)",
      res8["namespace_violation_count"] == 1 and res8["namespace_closure_violated"] is True)
check("U1' closure: in-namespace candidates survive + selected", set(paths8) == {"in.md", "in2.md"})
check("U1' closure: soft project bonus RETIRED when allowed_namespaces supplied (project feature == 0)",
      all(f["project"] == 0 for f in res8["features_by_candidate"].values()))
check("U1' closure: the canonical predicate/policy is stamped in the result (ns_closed_v1)",
      res8["namespace_policy_id"] == sp.NS_POLICY_ID and sp.NS_POLICY_ID == "ns_closed_v1")
# the privileged security log carries the identifying detail (caller routes it to a local sink; NOT the packet)
rp8 = sp.NamespaceRejectionPolicy()
res8p = sp.select(ns_cands, {}, "selpol_rrf_v1", {"allowed_namespaces": ["projX"], "rejection_policy": rp8})
check("U1' closure: privileged security_log captures the dropped candidate's identifying detail",
      len(rp8.security_log) == 1 and rp8.security_log[0]["source_path"] == "out.md"
      and rp8.security_log[0]["reason_code"] == "namespace_closure_violation")
check("U1' closure: caller_summary() is sanitized (count only, NO identifying detail)",
      rp8.caller_summary() == {"namespace_violation_count": 1, "namespace_closure_violated": True})
res8bc = sp.select(ns_cands, {"namespace": "projX"}, "selpol_rrf_v1", None)
check("U1' back-compat: absent allowed_namespaces -> soft project bonus PRESERVED (project == 1 for a match)",
      any(f["project"] == 1 for f in res8bc["features_by_candidate"].values()))
check("U1' back-compat: absent allowed_namespaces -> NO closure (all three candidates present + selectable)",
      len(res8bc["ranked"]) == 3 and res8bc["namespace_violation_count"] == 0)
# empty allowed_namespaces = fail-closed (drop EVERYTHING)
res8e = sp.select(ns_cands, {}, "selpol_rrf_v1", {"allowed_namespaces": []})
check("U1' closure: an EMPTY allowed_namespaces set fails closed (0 ranked, 0 selected, 3 violations)",
      len(res8e["ranked"]) == 0 and len(res8e["selected"]) == 0 and res8e["namespace_violation_count"] == 3)

# ---- 9. current_only HARD stale filter + prefer_current SOFT demote + 'any' allows stale (U4) ----
mix = [hit(1, "cur.md", "CUR", 900000, status="current"),
       hit(2, "stale.md", "STL", 800000, status="source_stale")]
r_co = sp.select(mix, {}, "selpol_rrf_v1", {"current_only": True})
sh = [h for h in r_co["ranked"] if h["source_path"] == "stale.md"][0]
check("U4 current_only: status-stale HARD-excluded (hard_filter_stale, selected False)",
      sh["selected"] is False and "hard_filter_stale" in sh["reason_codes"])
r_pc = sp.select(mix, {}, "selpol_rrf_v1", {"temporal_mode": "prefer_current"})
sh_pc = [h for h in r_pc["ranked"] if h["source_path"] == "stale.md"][0]
check("U4 prefer_current: the surviving SOFT demote (stale_demote, still selectable)",
      sh_pc["selected"] is True and "stale_demote" in sh_pc["reason_codes"])
r_any = sp.select(mix, {}, "selpol_rrf_v1", None)
sh_any = [h for h in r_any["ranked"] if h["source_path"] == "stale.md"][0]
check("U4 default/any: stale allowed (no temporal action, no stale reason code)",
      sh_any["selected"] is True and "hard_filter_stale" not in sh_any["reason_codes"]
      and "stale_demote" not in sh_any["reason_codes"])

# ---- 10. superseded_demote: live successor ordered ABOVE its superseded twin, independent of score (U4) ----
old = hit(1, "decisions/v1.md", "OLD", 900000, status="current")
old["record_version_id"] = "dec_v1"; old["record_id"] = "dec_a"; old["superseded_by"] = ["dec_v2"]
new = hit(2, "decisions/v2.md", "NEW", 100000, status="current")
new["record_version_id"] = "dec_v2"; new["record_id"] = "dec_b"; new["supersedes"] = ["dec_v1"]
r_sup = sp.select([old, new], {}, "selpol_rrf_v1", {"current_only": True})
oldr = [h for h in r_sup["ranked"] if h["record_version_id"] == "dec_v1"][0]
newr = [h for h in r_sup["ranked"] if h["record_version_id"] == "dec_v2"][0]
check("U4 superseded_demote: successor ordered ABOVE superseded despite LOWER score",
      newr["selection_rank"] < oldr["selection_rank"])
check("U4 superseded_demote: superseded carries superseded_demote reason", "superseded_demote" in oldr["reason_codes"])
check("U4: both current records survive current_only (both selected)", oldr["selected"] and newr["selected"])
# no supersession edges -> IDENTITY (byte-identical ordering; the demote is opt-in via edges)
plain = [hit(1, "p1.md", "P1", 900000), hit(2, "p2.md", "P2", 800000)]
r_plain = sp.select(plain, {}, "selpol_rrf_v1", {"current_only": True})
check("U4 superseded_demote: NO edges -> identity order (rank 1 == highest score)",
      r_plain["ranked"][0]["source_path"] == "p1.md" and
      all("superseded_demote" not in h["reason_codes"] for h in r_plain["ranked"]))

# ---- 10b. contradicts propagation (U4): a selected contradicts pair is surfaced, NOT detected ----
c1 = hit(1, "claimA.md", "CA", 900000, status="current"); c1["record_version_id"] = "cl_a"; c1["contradicts"] = ["cl_b"]
c2 = hit(2, "claimB.md", "CB", 800000, status="current"); c2["record_version_id"] = "cl_b"
r_con = sp.select([c1, c2], {}, "selpol_rrf_v1", {"current_only": True})
check("U4 contradicts: a SELECTED contradicts pair is surfaced in contradicts_pairs (propagated, not detected)",
      r_con["contradicts_pairs"] == [{"a": "cl_a", "b": "cl_b"}])
check("U4 contradicts: the edge is stamped on the involved features (contradicts_with)",
      r_con["features_by_candidate"]["cl_a"].get("contradicts_with") == ["cl_b"])

# ---- 11. i33/U5' query_class -> temporal_intent default (semantic vs temporal split) ----
qcstale = hit(1, "s.md", "SS", 900000, status="source_stale")
qccur = hit(2, "c.md", "CC", 800000, status="current")
r_cs = sp.select([qcstale, qccur], {"query_class": "current_state"}, "selpol_rrf_v1", None)
csh = [h for h in r_cs["ranked"] if h["source_path"] == "s.md"][0]
check("U5' current_state -> current_only (HARD): stale excluded; temporal_intent stamped",
      csh["selected"] is False and "hard_filter_stale" in csh["reason_codes"] and r_cs["temporal_intent"] == "current_only")
r_hr = sp.select([qcstale, qccur], {"query_class": "historical_reconstruction"}, "selpol_rrf_v1", None)
hrh = [h for h in r_hr["ranked"] if h["source_path"] == "s.md"][0]
check("U5' historical_reconstruction -> historical_as_of (allow stale): NOT filtered",
      hrh["selected"] is True and "hard_filter_stale" not in hrh["reason_codes"] and r_hr["temporal_intent"] == "historical_as_of")
r_lf = sp.select([qcstale, qccur], {"query_class": "local_factual"}, "selpol_rrf_v1", None)
lfh = [h for h in r_lf["ranked"] if h["source_path"] == "s.md"][0]
check("U5' local_factual -> any_valid_version (allow, NO soft demote): still selectable, no stale reason",
      lfh["selected"] is True and "stale_demote" not in lfh["reason_codes"]
      and "hard_filter_stale" not in lfh["reason_codes"] and r_lf["temporal_intent"] == "any_valid_version")
# the surviving prefer_current SOFT mode is now explicit-only (back-compat), not a class default
r_pc2 = sp.select([qcstale, qccur], {}, "selpol_rrf_v1", {"temporal_mode": "prefer_current"})
pch = [h for h in r_pc2["ranked"] if h["source_path"] == "s.md"][0]
check("U5' prefer_current is explicit-only (back-compat soft demote survives via params.temporal_mode)",
      pch["selected"] is True and "stale_demote" in pch["reason_codes"])
check("U5' class->intent map complete: 9 classes + composite + unclassified fallbacks",
      sorted(sp.CLASS_TO_TEMPORAL_INTENT.keys()) == sorted(["exact_reference", "current_state",
            "historical_reconstruction", "temporal_change", "local_factual", "global_synthesis",
            "causal_diagnosis", "procedure_selection", "precedent_search", "composite", "unclassified"]))

# ---- 12. open channel set (U5): an explicit 3rd 'graph' channel fuses with NO code change ----
g = hit(1, "g.md", "GG", 500000)
g["retrieval_occurrences"] = [{"channel": "lexical", "rank": 3}, {"channel": "vector", "rank": 2},
                              {"channel": "graph", "rank": 1}]
r_g = sp.select([g], {}, "selpol_rrf_v1", None)
occ_g = r_g["ranked"][0]["retrieval_occurrences"]
check("U5 open channels: explicit retrieval_occurrences honored channel-agnostically (3 incl. novel 'graph')",
      sorted(o["channel"] for o in occ_g) == ["graph", "lexical", "vector"])
check("U5 open channels: RRF fuses ALL channels incl. the novel one (no lexical+vector hard-coding)",
      r_g["ranked"][0]["rrf_score"] == sp._rrf_millionths(3, 60) + sp._rrf_millionths(2, 60) + sp._rrf_millionths(1, 60))

# ---- 13. 1.0.0 -> 1.1.0 SELECTION byte-identity regression (pins captured from selpol 1.0.0) ----
def _rsha(o):
    return hashlib.sha256(json.dumps(o, sort_keys=True).encode("utf-8")).hexdigest()
rgA = sp.select([hit(1, "a.md", "aa", 900000, ns="corpus"), hit(2, "b.md", "bb", 800000, ns="other"),
                 hit(3, "c.md", "cc", 700000, ns="corpus")],
                {"namespace": "corpus", "component": "a", "task_stage": "debug", "seeking_failures": True},
                "selpol_rrf_v1", None)
check("REGRESSION: default-path ranked BYTE-IDENTICAL to selpol 1.0.0",
      _rsha(rgA["ranked"]) == "47179d1dae4194104a9a7feb1213574854623cabab1facdf675bb4309b9104ec")
rgB = sp.select([hit(1, "x.md", "xx", 900000), hit(2, "y.md", "yy", 800000), hit(3, "z.md", "zz", 700000)],
                {"namespace": "corpus"}, "selpol_rrf_v1", {"current_only": True})
check("REGRESSION: current_only + all-current ranked BYTE-IDENTICAL to 1.0.0 (no stale to filter)",
      _rsha(rgB["ranked"]) == "ca88564248efd54fde54dba4d0caf9105c585d78c6d136e9aa0793b1c9d5e3a2")
rgD = sp.select([hit(1, "f.md", "ff", 900000), hit(2, "d1.md", "SAME", 800000), hit(3, "d2.md", "SAME", 700000),
                 hit(4, "g.md", "gg", 600000)], {}, "selpol_rrf_v1",
                {"hard_filter": [{"source_path": "f.md", "reason": "forbidden"}], "dedup_display": True,
                 "budget": {"max_selected": 2}})
check("REGRESSION: forbidden+dedup+budget ranked BYTE-IDENTICAL to 1.0.0",
      _rsha(rgD["ranked"]) == "d364068bcfb652aff8361d930e379b3d76dd8bc9c7c7c6206988a5e06da0138f")
check("REGRESSION: omission_manifest BYTE-IDENTICAL to 1.0.0",
      _rsha(rgD["omission_manifest"]) == "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945")

# ---- 14. version + stages + additive result surface ----
check("POLICY_VERSION is 1.2.0", sp.POLICY_VERSION == "1.2.0")
check("stages list adds namespace_filter + supersession", "namespace_filter" in rgA["stages"] and "supersession" in rgA["stages"])
check("contradicts_pairs present in every result (additive)", "contradicts_pairs" in rgA)
check("i33 additive result keys present", all(k in rgA for k in
      ("supersession_conflicts", "conflicted", "temporal_intent", "classifier_policy_id",
       "classifier_policy_version", "namespace_policy_id", "namespace_violation_count")))

# ================================================================= i33 (D-0096) new-unit gates

# ---- 15. the canonical ns_permitted predicate (accept / reject / empty / None / no-widening) ----
import lib.namespace_policy as nsp  # noqa: E402
import lib.classifier_policy as clsp  # noqa: E402
check("ns_permitted: exact member accepted", nsp.ns_permitted("A", frozenset(["A", "B"])) is True)
check("ns_permitted: non-member rejected", nsp.ns_permitted("C", frozenset(["A", "B"])) is False)
check("ns_permitted: EMPTY set rejects (fail-closed)", nsp.ns_permitted("A", frozenset()) is False)
check("ns_permitted: None set rejects (fail-closed; no implicit all)", nsp.ns_permitted("A", None) is False)
check("ns_permitted: NO prefix widening", nsp.ns_permitted("A/sub", frozenset(["A"])) is False)
check("ns_permitted: NO parent widening", nsp.ns_permitted("A", frozenset(["A/sub"])) is False)
check("ns_permitted: a candidate with no namespace is rejected", nsp.ns_permitted(None, frozenset(["A"])) is False)
check("ns_permitted: accepts a raw list/str (normalizes)", nsp.ns_permitted("A", ["A", "B"]) is True and nsp.ns_permitted("A", "A") is True)

# ---- 16. effective_allowed_namespaces = intersection(request, grant); request cannot widen grant ----
check("intersection(request, grant)", nsp.effective_allowed_namespaces(["A", "B", "C"], ["B", "C", "D"]) == frozenset(["B", "C"]))
check("intersection: request cannot WIDEN the grant", nsp.effective_allowed_namespaces(["A", "Z"], ["A"]) == frozenset(["A"]))
check("intersection: a None grant grants nothing (fail-closed)", nsp.effective_allowed_namespaces(["A"], None) == frozenset())
check("intersection: a None request requests nothing (fail-closed)", nsp.effective_allowed_namespaces(None, ["A"]) == frozenset())
check("intersection: disjoint sets -> empty (fail-closed)", nsp.effective_allowed_namespaces(["A"], ["B"]) == frozenset())

# ---- 17. NamespaceRejectionPolicy: count + privileged log + sanitized summary ----
rp = nsp.NamespaceRejectionPolicy()
rp.reject({"namespace": "nsZ", "record_version_id": "rvZ", "source_path": "z.md"}, frozenset(["nsA"]))
rp.reject({"namespace": "nsY", "record_version_id": "rvY", "source_path": "y.md"}, frozenset(["nsA"]))
check("rejection policy: violation_count accumulates", rp.violation_count == 2)
check("rejection policy: security_log carries the privileged identifying detail", len(rp.security_log) == 2 and rp.security_log[0]["source_path"] == "z.md")
check("rejection policy: caller_summary sanitized (count + flag ONLY, no ids/paths)",
      rp.caller_summary() == {"namespace_violation_count": 2, "namespace_closure_violated": True}
      and "source_path" not in rp.caller_summary())

# ---- 18. pool-INDEPENDENT current_only: effective_current==False with an ABSENT successor is excluded ----
old_abs = hit(1, "old.md", "OLD", 990000, status="superseded", ns="nsA")
old_abs["record_version_id"] = "rv_old"; old_abs["effective_current"] = False
old_abs["effective_current_successor"] = "rv_successor_ABSENT_from_pool"
cur_a = hit(2, "cur.md", "CUR", 400000, status="current", ns="nsA"); cur_a["effective_current"] = True
r_pi = sp.select([old_abs, cur_a], {}, "selpol_rrf_v1", {"allowed_namespaces": ["nsA"], "current_only": True})
oldr = [h for h in r_pi["ranked"] if h["source_path"] == "old.md"][0]
check("U4' pool-independent: superseded w/ ABSENT successor HARD-filtered under current_only",
      oldr["selected"] is False and "hard_filter_stale" in oldr["reason_codes"])
check("U4' pool-independent: the current candidate survives", any(h["source_path"] == "cur.md" and h["selected"] for h in r_pi["ranked"]))
# the SAME predecessor is KEPT when temporal intent is not current_only (historical)
r_hist = sp.select([old_abs, cur_a], {}, "selpol_rrf_v1", {"allowed_namespaces": ["nsA"], "temporal_intent": "historical_as_of"})
check("U4' pool-independent: NOT current_only -> the superseded predecessor is retained (historical)",
      any(h["source_path"] == "old.md" and h["selected"] for h in r_hist["ranked"]))

# ---- 19. supersession demote via the CATALOG successor ref (non-current_only ordering) ----
sold = hit(1, "d/v1.md", "V1", 990000, status="current", ns="nsA"); sold["record_version_id"] = "dv1"
sold["effective_current"] = False; sold["effective_current_successor"] = "dv2"
snew = hit(2, "d/v2.md", "V2", 100000, status="current", ns="nsA"); snew["record_version_id"] = "dv2"
snew["effective_current"] = True
r_dem = sp.select([sold, snew], {}, "selpol_rrf_v1", {"allowed_namespaces": ["nsA"], "temporal_intent": "any_valid_version"})
dv1 = [h for h in r_dem["ranked"] if h["record_version_id"] == "dv1"][0]
dv2 = [h for h in r_dem["ranked"] if h["record_version_id"] == "dv2"][0]
check("U4' catalog-ref demote: live successor ordered ABOVE its superseded twin despite lower score",
      dv2["selection_rank"] < dv1["selection_rank"] and "superseded_demote" in dv1["reason_codes"])

# ---- 20. supersession BRANCH -> conflicted (two live successors) ----
br = hit(1, "b.md", "B", 900000, ns="nsA"); br["record_version_id"] = "rvB"
br["effective_current"] = False; br["effective_current_branch"] = True
br["effective_current_successors"] = ["rvS2", "rvS1"]
r_br = sp.select([br, hit(2, "o.md", "O", 800000, ns="nsA")], {}, "selpol_rrf_v1", {"allowed_namespaces": ["nsA"]})
check("U4' branch: supersession_conflicts surfaces the branch (sorted successors)",
      len(r_br["supersession_conflicts"]) == 1 and r_br["supersession_conflicts"][0]["successors"] == ["rvS1", "rvS2"])
check("U4' branch: result.conflicted flag set + 'conflicted' reason on the branch candidate",
      r_br["conflicted"] is True and "conflicted" in [c for h in r_br["ranked"] if h["record_version_id"] == "rvB" for c in h["reason_codes"]])

# ---- 21. classifier split: explicit temporal_intent / version OUTRANKS the query_class default ----
check("classifier: versioned id/version", clsp.CLASSIFIER_POLICY_ID == "clsmap_v1" and clsp.CLASSIFIER_POLICY_VERSION == "1.0.0")
check("classifier: composite + unclassified fall back to any_valid_version",
      clsp.class_to_temporal_intent("composite") == "any_valid_version" and clsp.class_to_temporal_intent(None) == "any_valid_version")
check("classifier: an explicit temporal_intent OUTRANKS the class default",
      clsp.resolve_temporal_intent("current_state", "any_valid_version")[0] == "any_valid_version")
check("classifier: an explicit version request -> version_specific (outranks class)",
      clsp.resolve_temporal_intent("current_state", None, True)[0] == "version_specific")
smix = [hit(1, "s.md", "SS", 900000, status="source_stale", ns="nsA"), hit(2, "c.md", "CC", 800000, status="current", ns="nsA")]
r_ov = sp.select(smix, {"query_class": "current_state"}, "selpol_rrf_v1", {"allowed_namespaces": ["nsA"], "temporal_intent": "any_valid_version"})
sov = [h for h in r_ov["ranked"] if h["source_path"] == "s.md"][0]
check("U5' in selpol: explicit temporal_intent OUTRANKS query_class (current_state stale NOT excluded)",
      sov["selected"] is True and "hard_filter_stale" not in sov["reason_codes"] and r_ov["temporal_intent"] == "any_valid_version")

print("")
if FAIL[0] == 0:
    print("ALL PASS (selpol_rrf_v1 unit)")
    sys.exit(0)
print("FAILURES: %d" % FAIL[0])
sys.exit(1)
