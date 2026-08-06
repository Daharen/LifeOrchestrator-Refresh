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
# i36: generator 0.7.0 -> 0.8.0. The FLAT structural_digest moved ONLY because generator_version is stamped
# 0.8.0 (the measurement skeleton -- which EXCLUDES the version stamp + digests + CLI identity -- is unchanged;
# FLAT_METRICS_SKELETON_DIGEST pins that, regression-proving the flat metrics byte-identical to 0.7.0).
# i40 RE-PIN (PB-5 / D-0108): #36 0.7.0's fast-beam (i39 Lane B) LEGITIMATELY moved the WIRED-descend
# structure, so WIRED_STRUCTURAL_DIGEST was re-derived via this harness's OWN derivation over the committed
# #36 0.7.0 + #40 0.9.0 and re-pinned (fold-verified prefix d0d54aba). The wired metric IMPROVED: 11/11 s10
# criteria hold, hierarchy_path_recall 58823 -> 117647 ppm, guaranteed + packet recall stay 1,000,000 ppm --
# only the fingerprint moved. The FLAT pins are untouched (fast-beam is descend-only; non-wired byte-identical).
PINNED_STRUCTURAL_DIGEST = "sha256:da34250eea25b94f15b33631698ccb9dc5812dd221a8514b52d7bb3b1472c76f"
FLAT_METRICS_SKELETON_DIGEST = "sha256:b6947a21aa90e307be0b9bf3b1db85d5c4ad2e60ee8b98867fb5332d470c3fff"
WIRED_STRUCTURAL_DIGEST = "sha256:d0d54abadce18a65274d8593f7b141b8501fa6ccab50682f0607227000c7e450"

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


def test_wired():
    """i36 WIRED-DESCEND gate: DRIVE #40 0.7.0's public artifact_search shortlist-and-descend port over the
    committed real sample and MEASURE s10 against the WIRED packets -- 11/11 criteria, dual recall (fast-beam
    PARTIAL, guaranteed+packet FULL), sub-linear nav from #40's OWN plan trace, stale-window recall preserved,
    deterministic. tier1_accepted here is the harness's COMPUTED output over the sample+CLI (the orchestrator
    runs the full ~200MB gate vs the frozen #40 0.7.0 at fold + owns the project flip)."""
    tmp = tempfile.mkdtemp(prefix="rehearsal-wired-")
    try:
        base = os.path.join(tmp, "w")
        os.makedirs(base)
        summ = run(base, wired_descend=True)
        rep = json.load(open(os.path.join(base, "rehearsal_report.json")))
        check("wired: measurement_mode wired_descend", rep.get("measurement_mode") == "wired_descend")
        wd = rep["wired_descend"]
        caps = wd["capabilities"]
        check("wired: #40 0.7.0 port CONSTRUCTS + emits retrieval_completeness + navigation_nodes_examined + stage trace",
              caps["wired_port_constructs"] and caps["wired_emits_retrieval_completeness"]
              and caps["wired_emits_navigation_nodes_examined"] and caps["wired_emits_stage_trace"])
        check("wired: NO fold reconciliation (the shipped #40 0.7.0 CLI IS drivable into descend)",
              wd["fold_reconciliation"] == [])
        check("wired: 11/11 criteria + tier1_accepted True",
              wd["tier1_criteria_passed"] == 11 and wd["tier1_criteria_total"] == 11
              and wd["tier1_acceptance"]["accepted"] is True)
        crit = {c["criterion"]: c for c in wd["tier1_criteria"]}
        check("wired: the descend path GENUINELY ran (>=3 descend-class labeled + scale descend queries)",
              crit["wired_descend_path_ran"]["passed"]
              and crit["wired_descend_path_ran"]["detail"]["descend_class_queries"] >= 3
              and crit["wired_descend_path_ran"]["detail"]["scale_descend_queries"] > 0)
        check("wired: cross-namespace contamination 0 across the WIRED packets",
              crit["cross_namespace_contamination"]["passed"]
              and crit["cross_namespace_contamination"]["detail"]["contamination_hits"] == 0)
        check("wired: every WIRED excerpt reconstructs to source (valid_ppm 1000000)",
              crit["provenance_reconstruction"]["passed"]
              and crit["provenance_reconstruction"]["detail"]["valid_ppm"] == 1000000)
        nav = crit["navigation_sublinear_from_plan"]["detail"]
        check("wired: nav SUB-LINEAR from #40's OWN plan (navigation_nodes_examined; grows slower than leaves; 100x span)",
              crit["navigation_sublinear_from_plan"]["passed"] and nav["sublinear"] and nav["sublinear_growth"]
              and nav["leaf_span_x"] == 100 and nav["nav_growth_ppm"] < nav["leaf_growth_ppm"]
              and nav["source"] == "packet.retrieval_completeness.navigation_nodes_examined")
        per = wd["scale_sweep"]["per_scale"]
        ratios = [s["wired_nav_over_leaves_ppm"] for s in per]
        check("wired: nodes/leaf ratio STRICTLY DECREASES across scales (from #40's plan trace)",
              all(ratios[i] > ratios[i + 1] for i in range(len(ratios) - 1)))
        d = wd["scale_sweep"]["dual"]
        check("wired dual: guaranteed == packet == 100% (the exhaustive #36-flat fallback preserves recall)",
              d["guaranteed_path_recall_ppm"] == 1000000 and d["packet_evidence_recall_ppm"] == 1000000)
        check("wired dual: hierarchy-PATH (descend fast-beam, from #40's pure-descend packet) is PARTIAL (< guaranteed)",
              d["hierarchy_path_recall_ppm"] < d["guaranteed_path_recall_ppm"])
        check("wired dual: regret > 0 AND fallback-frequency > 0 (the descend gap the fallback covers)",
              d["shortlist_regret_ppm"] > 0 and d["fallback_frequency_ppm"] > 0)
        check("wired: current-vs-historical honored on the WIRED packets", crit["current_vs_historical"]["passed"])
        check("wired: every WIRED packet within budget + disposition correct",
              crit["bounded_context_cost"]["passed"] and crit["packet_disposition_correct"]["passed"])
        sw = wd["stale_window"]
        check("wired: STALE-WINDOW -> stale flagged, pruned NOT increased, recall preserved (never a silent miss)",
              crit["stale_window_recall_preserved"]["passed"] and sw["leaf_marked_changed"]
              and sw["stale_navigation_encountered"] and sw["stale_pruned_not_increased"]
              and sw["recall_preserved_after_stale"] == 1)
        check("wired: the #36-direct + #40-flat baseline is RETAINED + labeled (descend-vs-flat deltas present)",
              isinstance(rep.get("scale_sweep"), dict) and isinstance(rep.get("tier1_criteria"), list)
              and "descend_vs_flat" in wd and rep["tier1_criteria_passed"] == 9)
        check("wired: tier1_accepted is the harness's COMPUTED output, NOT a project claim",
              "NOT a project-level claim" in wd["tier1_acceptance"]["scope"]
              and "orchestrator" in wd["tier1_acceptance"]["project_flip_owner"])
        check("wired: summary carries the authoritative flip signal + wired counts",
              summ["tier1_accepted"] is True and summ.get("measurement_mode") == "wired_descend"
              and summ.get("wired_tier1_criteria_passed") == 11 and summ.get("wired_fold_reconciliation") == [])
        check("wired: structural_digest == pinned (cross-env stable, deterministic, CLI-version-independent)",
              rep["structural_digest"] == WIRED_STRUCTURAL_DIGEST)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    tmp = tempfile.mkdtemp(prefix="rehearsal-test-")
    try:
        base = os.path.join(tmp, "a")
        os.makedirs(base)
        summ = run(base)
        rep = json.load(open(os.path.join(base, "rehearsal_report.json")))

        # ---- schema / version ----
        check("schema is rehearsal_eval_report/0.1", rep["schema"] == "lifeorch.rehearsal_eval_report/0.1")
        check("generator_version 0.8.0", rep["generator_version"] == "0.8.0")
        check("benchmark is the click 8.1.7 real foreign slice",
              rep["benchmark_id"] == "rehearsal-click-8.1.7-slice")
        check("adapter kind real_cli", rep["adapter_kind"] == "real_cli")

        # ---- i36 regression: the FLAT measured metrics are BYTE-IDENTICAL to 0.7.0 across the 0.8.0 bump
        # (the report skeleton MINUS the version stamp + digests + measured-CLI identity is unchanged) ----
        import hashlib as _hl
        _strip = ("generator_version", "report_digest", "structural_digest", "adapter_calls", "cli_capabilities")
        _skel = {k: v for k, v in rep.items() if k not in _strip}
        _skd = "sha256:" + _hl.sha256(json.dumps(_skel, sort_keys=True, ensure_ascii=True,
                                                 separators=(",", ":")).encode()).hexdigest()
        check("i36: FLAT metrics byte-identical to 0.7.0 (skeleton digest pinned)",
              _skd == FLAT_METRICS_SKELETON_DIGEST)
        check("i36: a non-wired report carries NO wired_descend / measurement_mode keys (additive + gated)",
              "wired_descend" not in rep and "measurement_mode" not in rep)

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

        # ---- determinism: the PINNED structural_digest is the cross-env proof (must match cloud AND the
        # device -Live run; any CLI-version-independent nondeterminism breaks the pin), so a single run pins it
        # (the same-machine byte re-run is subsumed + dropped to bound the subprocess-per-call adapter cost) ----
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

        test_wired()

        print("\n%d passed, %d failed" % (PASS, FAIL))
        return 1 if FAIL else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
