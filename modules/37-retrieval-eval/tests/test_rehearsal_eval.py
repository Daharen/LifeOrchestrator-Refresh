#!/usr/bin/env python3
# test_rehearsal_eval.py -- OFF-MACHINE deterministic gate for the i35 Tier-1 ACCEPTANCE-GATE rehearsal harness
# (module 37, plan fo-35-0a5bf334). Drives the REAL #36/#40 cores (portable stdlib+sqlite) over the committed
# real foreign corpus sample via the external_command adapter, and pins the s10 criteria + tier1_accepted +
# determinism. Stdlib-only; CPU-only; no model; no network.
import os
import sys
import json
import tempfile
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..")))
import rehearsal_eval as R  # noqa

# The CROSS-ENV STABLE structural digest (corpus + metrics + criteria + tier1_accepted, EXCLUDING the measured
# #36/#40 CLI-version identity). report_digest is byte-identical on a re-run of the SAME machine, but ACROSS
# machines it legitimately tracks which #36/#40 BUILD was measured (CLI-agnostic by design); structural_digest
# does not, so it is what the cloud gate + the -Live executor both pin.
PINNED_STRUCTURAL_DIGEST = "sha256:9675c82a7f2e98f5b848792142a92442a6e5eb4396fd8b3576eb1b15a2c9b21b"

PASS = 0
FAIL = 0


def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("ok   - %s" % name)
    else:
        FAIL += 1
        print("FAIL - %s" % name)


def run(out_dir, **kw):
    req = {"op": "rehearsal", "out_dir": out_dir}
    req.update(kw)
    return R.run_request(req)


def main():
    tmp = tempfile.mkdtemp(prefix="rehearsal-test-")
    try:
        base = os.path.join(tmp, "a")
        os.makedirs(base)
        summ = run(base)
        rep = json.load(open(os.path.join(base, "rehearsal_report.json")))

        # ---- schema / version ----
        check("schema is rehearsal_eval_report/0.1", rep["schema"] == "lifeorch.rehearsal_eval_report/0.1")
        check("generator_version 0.7.0", rep["generator_version"] == "0.7.0")
        check("benchmark is the click 8.1.7 real foreign slice",
              rep["benchmark_id"] == "rehearsal-click-8.1.7-slice")
        check("adapter kind real_cli", rep["adapter_kind"] == "real_cli")

        # ---- capabilities: real #36 shortlist/descend present; #40 CLI is FLAT-only (documented) ----
        caps = rep["cli_capabilities"]
        check("cap: #36 shortlist+descend+build+search present",
              caps["m36_shortlist"] and caps["m36_descend"] and caps["m36_build"] and caps["m36_search"])
        check("cap: #40 compile present", caps["m40_compile"])
        check("cap: #40 CLI is flat-only (retrieval_completeness absent -> nav measured via #36)",
              caps["m40_emits_retrieval_completeness"] is False)
        check("cap: no volatile python/sqlite version leaked into the report",
              set(caps["m36_worker"].keys()) == {"worker_version", "schema_version"})
        check("no fold reconciliation open", rep["fold_reconciliation"] == [])

        # ---- corpus: three namespaces ingested into real #36 hierarchies ----
        ns = {b["namespace"] for b in rep["corpus"]["built"]}
        check("corpus namespaces = clickcode/clickdocs/clicklog", ns == {"clickcode", "clickdocs", "clicklog"})
        check("all trees valid", all(b["topology_state"] == "valid" for b in rep["corpus"]["built"]))

        # ---- the 9 Tier-1 criteria, all PASS ----
        crit = {c["criterion"]: c for c in rep["tier1_criteria"]}
        check("criteria: 9/9 passed", rep["tier1_criteria_passed"] == 9 and rep["tier1_criteria_total"] == 9)
        check("(a) bounded_context_cost PASS", crit["bounded_context_cost"]["passed"])
        check("(b) cross_namespace_contamination PASS + 0 hits",
              crit["cross_namespace_contamination"]["passed"]
              and crit["cross_namespace_contamination"]["detail"]["contamination_hits"] == 0)
        check("(c) current_vs_historical PASS (both temporal queries honored)",
              crit["current_vs_historical"]["passed"]
              and crit["current_vs_historical"]["detail"]["honored"] == 2)
        check("(d) provenance_reconstruction PASS + valid_ppm 1000000",
              crit["provenance_reconstruction"]["passed"]
              and crit["provenance_reconstruction"]["detail"]["valid_ppm"] == 1000000)
        check("(e) navigation_sublinear PASS + leaf_span 100x",
              crit["navigation_sublinear"]["passed"]
              and crit["navigation_sublinear"]["detail"]["leaf_span_x"] == 100)
        check("dual packet_evidence_recall PASS (labeled + scale == 1000000)",
              crit["packet_evidence_recall"]["passed"]
              and crit["packet_evidence_recall"]["detail"]["labeled_ppm"] == 1000000
              and crit["packet_evidence_recall"]["detail"]["scale_ppm"] == 1000000)
        check("dual guaranteed_path_recall PASS", crit["guaranteed_path_recall"]["passed"])
        check("P0-3 packet_disposition_correct PASS (7/7)",
              crit["packet_disposition_correct"]["passed"]
              and crit["packet_disposition_correct"]["detail"]["correct"] == 7)

        # ---- scale sweep: sub-linear (nodes/leaf strictly decreasing) across >=2 orders of magnitude ----
        per = rep["scale_sweep"]["per_scale"]
        leaves = [s["leaf_count"] for s in per]
        ratios = [s["nodes_examined_over_leaves_ppm"] for s in per]
        check("scale: leaves span >=2 orders (max/min >= 100)", (max(leaves) // min(leaves)) >= 100)
        check("scale: nodes/leaf ratio STRICTLY DECREASES (sub-linear)",
              all(ratios[i] > ratios[i + 1] for i in range(len(ratios) - 1)))
        check("scale: every packet within budget", all(s["packet_within_budget"] for s in per))
        check("scale: sublinear+not_constant flags", rep["scale_sweep"]["navigation_sublinear"]
              and rep["scale_sweep"]["navigation_not_constant"])

        # ---- DUAL recall story on REAL data: fast beam PARTIAL, guaranteed+packet FULL (the red-team gap) ----
        d = rep["scale_sweep"]["dual"]
        check("dual: guaranteed == packet == 100% (exhaustive-flat fallback preserves recall)",
              d["guaranteed_path_recall_ppm"] == 1000000 and d["packet_evidence_recall_ppm"] == 1000000)
        check("dual: fast beam is PARTIAL (< guaranteed) on rare-term queries (bounded descriptor is lossy)",
              d["hierarchy_path_recall_ppm"] < d["guaranteed_path_recall_ppm"])
        check("dual: regret > 0 and fallback > 0 (the gap the fallback covers)",
              d["shortlist_regret_ppm"] > 0 and d["fallback_frequency_ppm"] > 0)

        # ---- tier1_accepted computed over the pointed corpus+CLI (NOT a project claim) ----
        ta = rep["tier1_acceptance"]
        check("tier1_accepted == True on the sample+CLI", ta["accepted"] is True)
        check("tier1 scope is NOT a project-level claim", "NOT a project-level claim" in ta["scope"])
        check("tier1 project flip owned by the orchestrator", "orchestrator" in ta["project_flip_owner"])
        check("worker-summary tier1_accepted matches", summ["tier1_accepted"] is True)

        # ---- determinism: byte-identical on re-run; digest stable + pinned ----
        base2 = os.path.join(tmp, "b")
        os.makedirs(base2)
        run(base2)
        b1 = open(os.path.join(base, "rehearsal_report.json"), "rb").read()
        b2 = open(os.path.join(base2, "rehearsal_report.json"), "rb").read()
        check("determinism: report.json byte-identical on re-run (same machine)", b1 == b2)
        check("determinism: structural_digest == pinned (cross-env stable, CLI-version-independent)",
              rep["structural_digest"] == PINNED_STRUCTURAL_DIGEST)
        check("determinism: report_digest present + tracks the measured CLI (informational)",
              isinstance(rep["report_digest"], str) and rep["report_digest"].startswith("sha256:"))

        # ---- fail-closed inputs ----
        try:
            run(os.path.join(tmp, "c"), scales=[10, 20])
            check("failclosed: <2 orders of magnitude rejected", False)
        except R.RehearsalError as e:
            check("failclosed: <2 orders of magnitude rejected", e.code == "bad_scales")

        print("\n%d passed, %d failed" % (PASS, FAIL))
        return 1 if FAIL else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
