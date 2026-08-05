#!/usr/bin/env python3
# test_hierarchy_eval.py -- OFF-MACHINE deterministic gate for the Tier-1 hierarchy eval (module 37, i34).
# Stdlib-only; pins the navigation-cost / dual-recall / adversarial / gate-set outcomes + determinism.
import os, sys, json, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))
import hierarchy_eval as he  # noqa

PASS = 0; FAIL = 0
def check(name, cond):
    global PASS, FAIL
    if cond: PASS += 1; print("ok   - %s" % name)
    else: FAIL += 1; print("FAIL - %s" % name)

def run(base, **kw):
    req = {"op": "hierarchy-eval", "out_dir": base, "scales": [16, 64, 256, 1024, 4096],
           "seed": 0, "fanout": 4, "beam": 2}
    req.update(kw)
    return he.run_request(req)

def main():
    tmp = tempfile.mkdtemp(prefix="he-test-")
    try:
        base = os.path.join(tmp, "a"); os.makedirs(base)
        s = run(base)
        rep = json.load(open(os.path.join(base, "hierarchy_report.json")))

        # ---- (1) navigation-cost: sub-linear across >=2 orders of magnitude ----
        per = rep["navigation_cost"]["per_scale"]
        p50 = [x["nodes_examined_p50"] for x in per]
        ratios = [x["nodes_examined_over_leaves_ppm"] for x in per]
        check("nav: p50 grows with N (not constant)", p50 == [2, 3, 4, 5, 6])
        check("nav: nodes/leaf ratio strictly DECREASES (sub-linear)", all(ratios[i] > ratios[i+1] for i in range(len(ratios)-1)))
        check("nav: sublinear+not_constant+log_shaped flags", rep["navigation_cost"]["sublinear"] and rep["navigation_cost"]["not_constant"] and rep["navigation_cost"]["log_shaped"])
        check("nav: localized decisive-term path recall == 1.0", all(x["hierarchy_path_recall_ppm"] == 1000000 for x in per))

        # ---- (2) DUAL recall: fast beam MISSES, guaranteed + packet PRESERVE (the red-team gap) ----
        d = rep["dual_recall"]
        check("dual: fast-beam path recall is PARTIAL (25%)", d["hierarchy_path_recall_ppm"] == 250000)
        check("dual: guaranteed (explore-all) recall == 100%", d["guaranteed_path_recall_ppm"] == 1000000)
        check("dual: end-to-end PACKET recall == 100% (fallback preserves)", d["packet_evidence_recall_ppm"] == 1000000)
        check("dual: shortlist regret == the gap (75%)", d["shortlist_regret_ppm"] == 750000)
        check("dual: fallback frequency > 0 (beam missed -> fell back)", d["fallback_frequency_ppm"] == 1000000)
        check("dual: stale-window recall == 100% (stale routes, never prunes)", d["stale_window_recall_ppm"] == 1000000)
        check("dual: path < guaranteed == packet (the gap fallback covers)", d["hierarchy_path_recall_ppm"] < d["guaranteed_path_recall_ppm"] == d["packet_evidence_recall_ppm"])

        # ---- (3) adversarial fixtures: all pass with the pinned semantics ----
        adv = {f["fixture"]: f for f in rep["adversarial_fixtures"]}
        check("adv: 5/5 fixtures pass", rep["adversarial_passed"] == 5 and rep["adversarial_total"] == 5)
        check("adv: rare-term -> NAIVE silently misses, SAFE falls back", adv["rare_decisive_term_ambiguous"]["detail"]["naive_silent_miss"] and adv["rare_decisive_term_ambiguous"]["detail"]["safe_fallback_used"])
        check("adv: cross-ns -> unauthorized descend fails closed, 0 leakage", adv["cross_namespace_contamination"]["detail"]["unauthorized_descend_failed_closed"] and adv["cross_namespace_contamination"]["detail"]["nsB_leaves_leaked"] == 0)
        check("adv: mutation-during-regen -> naive false-fresh, CAS detects stale", adv["mutation_during_regen_aba"]["detail"]["naive_boolean_false_fresh"] and adv["mutation_during_regen_aba"]["detail"]["cas_generation_detects_stale"])
        check("adv: stale node never false-negative prunes", adv["stale_node_no_false_negative_prune"]["passed"])
        check("adv: exact cheap, global slow (not constant)", adv["exact_cheap_global_slow"]["detail"]["exact_nodes"] < adv["exact_cheap_global_slow"]["detail"]["global_nodes"])

        # ---- (4) Tier-1 gate set: all pass, all 5 dimensions present ----
        check("gates: 11/11 pass", rep["tier1_gates_passed"] == 11 and rep["tier1_gates_total"] == 11)
        dims = set(g["dimension"] for g in rep["tier1_gate_set"])
        check("gates: all 5 dimensions present", dims == {"structural", "security", "mutation_freshness", "retrieval", "complexity"})

        # ---- (5) rehearsal is an OPEN gate; Tier-1 NOT accepted on synthetic-only ----
        check("rehearsal: gate OPEN", rep["rehearsal_gate"]["status"] == "OPEN")
        check("rehearsal: Tier-1 acceptance == False (synthetic not sufficient)", rep["tier1_acceptance"]["accepted"] is False)
        check("rehearsal: synthetic gates DID pass (the necessary pre-check)", rep["tier1_acceptance"]["synthetic_gates_passed"] is True)

        # ---- (6) determinism: a re-run is byte-identical ----
        base2 = os.path.join(tmp, "b"); os.makedirs(base2)
        run(base2)
        b1 = open(os.path.join(base, "hierarchy_report.json"), "rb").read()
        b2 = open(os.path.join(base2, "hierarchy_report.json"), "rb").read()
        check("determinism: report.json byte-identical on re-run", b1 == b2)
        check("determinism: report_digest stable", rep["report_digest"] == json.load(open(os.path.join(base2, "hierarchy_report.json")))["report_digest"])

        # ---- (7) fail-closed inputs ----
        try:
            run(os.path.join(tmp, "c") if os.makedirs(os.path.join(tmp, "c")) is None else os.path.join(tmp, "c"), scales=[10, 20])
            check("failclosed: <2 orders of magnitude rejected", False)
        except he.HEError as e:
            check("failclosed: <2 orders of magnitude rejected", e.code == "bad_scales")
        try:
            os.makedirs(os.path.join(tmp, "d"))
            run(os.path.join(tmp, "d"), adapter={"kind": "external_command"})
            check("failclosed: external_command deferred to the fold", False)
        except he.HEError as e:
            check("failclosed: external_command deferred to the fold", e.code == "external_command_deferred")

        print("\n%d passed, %d failed" % (PASS, FAIL))
        return 1 if FAIL else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    sys.exit(main())
