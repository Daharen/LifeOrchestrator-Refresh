#!/usr/bin/env python3
# test_selpol.py -- library-direct unit gate for selpol_rrf_v1 (CONTEXT_PACKET_CONTRACT s4, P1-1).
# Runs in the cloud pre-ship gate AND on the -Live executor (pure stdlib; no model/IO/network). Asserts the
# s4 interface, purity, determinism, ADDITIVE output, rescue+demote preserving retrieval_rank, RRF over
# channel ranks, and occurrence-preserving display dedup. Exit 0 = all pass.
import os
import sys
import json
import copy

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
check("DEMOTE: stale hit carries stale_demote", "stale_demote" in stale["reason_codes"])

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

print("")
if FAIL[0] == 0:
    print("ALL PASS (selpol_rrf_v1 unit)")
    sys.exit(0)
print("FAILURES: %d" % FAIL[0])
sys.exit(1)
