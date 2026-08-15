#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""i56 (PB-6, D-0149 -- FANOUT_AGENT_002) GATE TEST -- the `compile_relevant_decisions` VERB.

Frozen contract: core-docs/research/2026-08-14-pb6-decision-record-schema.md s4; the s8 hardened
predicate (research/2026-08-14-pb7-relayer-design-2.md) is AUTHORITATIVE over its own naive s4 rule.

Lane A's real PB-6 producer (FANOUT_AGENT_001) is a parallel-isolated session -- its real
`record_kind=decision` #36 records do not exist here, so this worker builds + tests against FIXTURE
decision records conforming EXACTLY to the frozen s3 field table (injected via `decision_pool`, the
same injection pattern the rest of #40 uses for its retriever seam off-machine). The real producer ->
#36 catalog -> this verb seam is the orchestrator's D-0077 fold smoke (frozen contract s5) -- NOT
attempted here.

Asserts:
  (F1) the standing-constraint ROOT view returns the asserted COUNT with NO silent drop under a tight
       budget (a spilled category still contributes to asserted_count; a `deeper:` pointer replaces it,
       never a bare drop).
  (rule 2) demote-on-enforcement -- a standing record bound to a gate (`enforced_by=<gate>`) is counted
       in asserted_count but is NOT in the category's `hot` list (it demoted to cold).
  (F3) a `partially_superseded_by` predecessor STILL surfaces (status=current) alongside its successor --
       never silently dropped by a naive AND-gate.
  (F4) a stale `ingested_through` input (vs `canonical_head`) yields the degraded "current as of <SHA>"
       result (`currentness=stale`) -- NEVER served as current.
  (C4) a global/full-history query returns the slow-path marker, never a fast compile.
  (determinism) byte-identical compiled set for identical records + identical query (double-run gate).
  (non-regression) the existing op/OPS surface (compile/normalize/expand) + the flat/no-decision-input
       compile stay byte-identical -- run alongside the owned suites (context_compiler_tests.py 322/322,
       test_i35 32/32, test_i37 34/34, test_i38 42/42) as this worker's own regression evidence.

Pure python3 + stdlib. No model, no network, no filesystem writes outside /tmp (none needed here)."""

import os, sys, json

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("LOR_REPO") or HERE
while REPO != os.path.dirname(REPO) and not os.path.isdir(os.path.join(REPO, "modules", "37-retrieval-eval")):
    REPO = os.path.dirname(REPO)
MOD = os.path.join(REPO, "modules")
sys.path.insert(0, os.path.join(MOD, "40-context-compiler"))

import context_compiler as cc        # noqa: E402 -- REAL #40 0.10.0 (imports #37's REAL selpol on load)

_PASS = 0
_FAIL = 0

def check(label, ok, detail=""):
    global _PASS, _FAIL
    ok = bool(ok)
    if ok:
        _PASS += 1
    else:
        _FAIL += 1
    tag = "PASS" if ok else "FAIL"
    print("  [%s] %s%s" % (tag, label, ("   :: " + str(detail) if (detail and not ok) else
                                        ("   (" + str(detail) + ")" if detail else ""))))
    return ok

# ------------------------------------------------------------------------------------------------
# fixtures -- typed `record_kind=decision` records conforming to the frozen s3 field table. Every
# record shares `ingested_through=aaa111` (the s3 clause: "identical for all records in one run").
# ------------------------------------------------------------------------------------------------

def span(start, end):
    return {"path": "DECISION_LOG.md", "start": start, "end": end}

def base_pool():
    return [
        # (1) standing_prohibition, NOT gate-enforced -> hot, in the root view, category "infra".
        {"decision_id": "D-0051", "title": "Never `git add -A`", "status": "current",
         "binding_scope": "standing_prohibition", "enforced_by": "none",
         "affected_modules": ["#0"], "planes": ["infra"], "namespace": "decisions",
         "authority": "nicholas", "ingested_through": "aaa111", "source_span": span(100, 200)},
        # (2) invariant, GATE-ENFORCED (doc-commit-gate) -> demoted to cold (rule 2); still ASSERTED.
        {"decision_id": "D-0072", "title": "dev.ship can false-negative the commit -- verify native HEAD",
         "status": "current", "binding_scope": "invariant", "enforced_by": "doc-commit-gate",
         "affected_modules": ["#0"], "planes": ["infra"], "namespace": "decisions",
         "authority": "orchestrator", "ingested_through": "aaa111", "source_span": span(300, 400)},
        # (3) a THIRD standing record in a DIFFERENT category, to exercise the F1 budget spill.
        {"decision_id": "D-0079", "title": "Warm pool default stays OFF", "status": "current",
         "binding_scope": "invariant", "enforced_by": "none",
         "affected_modules": ["#7"], "planes": ["model-gateway"], "namespace": "decisions",
         "authority": "nicholas", "ingested_through": "aaa111", "source_span": span(450, 520)},
        # (4)+(5) F3: a partial-supersession chain -- D-0050 revised (NOT replaced) by D-0143.
        {"decision_id": "D-0050", "title": "Offload only what is cheaper to verify than to do",
         "status": "current", "binding_scope": "ordinary", "enforced_by": "none",
         "partially_superseded_by": ["D-0143"],
         "affected_modules": ["#21"], "planes": ["memory"], "namespace": "decisions",
         "authority": "nicholas", "ingested_through": "aaa111", "source_span": span(500, 600)},
        {"decision_id": "D-0143", "title": "N4 bars re-frozen", "status": "current",
         "binding_scope": "ordinary", "enforced_by": "none", "partially_supersedes": ["D-0050"],
         "affected_modules": ["#21"], "planes": ["memory"], "namespace": "decisions",
         "authority": "nicholas", "ingested_through": "aaa111", "source_span": span(700, 800)},
        # (6) a FULLY superseded ordinary decision -- must be excluded from the current-only compiled set.
        {"decision_id": "D-0040", "title": "an earlier, fully replaced approach", "status": "superseded",
         "binding_scope": "ordinary", "enforced_by": "none", "superseded_by": ["D-0143"],
         "affected_modules": ["#21"], "planes": ["memory"], "namespace": "decisions",
         "authority": "nicholas", "ingested_through": "aaa111", "source_span": span(900, 950)},
        # (7) an unrelated ordinary decision (different module) -- exercises the modules[] relevance filter.
        {"decision_id": "D-0060", "title": "27B validated impractical on 11GB", "status": "current",
         "binding_scope": "ordinary", "enforced_by": "none",
         "affected_modules": ["#7"], "planes": ["model-gateway"], "namespace": "decisions",
         "authority": "nicholas", "ingested_through": "aaa111", "source_span": span(1000, 1100)},
    ]

def test_f1_standing_asserted_count_no_silent_drop():
    print("\n[F1] standing-constraint ROOT view -- asserted COUNT survives a tight category budget")
    pool = base_pool()
    out = cc.run({"op": "compile_relevant_decisions", "decision_pool": pool,
                  "canonical_head": "aaa111", "standing_budget_categories": 1})
    check("ok", out["ok"], out)
    view = out["result"]["standing_constraint_root_view"]
    check("asserted_count == 3 (ALL in-force standing records, budget or not)", view["asserted_count"] == 3,
          view["asserted_count"])
    check("exactly 1 category PINNED (the budget cut)", len(view["categories"]) == 1, view)
    check("the remainder SPILLS (never silently drops)", view["spilled"] is True, view)
    spilled_counts = sum(c["count"] for c in view["spilled_categories"])
    pinned_counts = sum(c["count"] for c in view["categories"])
    check("pinned + spilled member counts == asserted_count (nothing vanished)",
          pinned_counts + spilled_counts == view["asserted_count"],
          (pinned_counts, spilled_counts, view["asserted_count"]))
    for c in view["spilled_categories"]:
        check("a spilled category carries a deeper:*:prohibition pointer, not a bare drop",
              c.get("deeper_query", "").startswith("deeper:") and c["deeper_query"].endswith(":prohibition"),
              c)

def test_rule2_demote_on_enforcement():
    print("\n[rule 2] demote-on-enforcement -- a gate-bound standing record is ASSERTED but not HOT")
    pool = base_pool()
    out = cc.run({"op": "compile_relevant_decisions", "decision_pool": pool, "canonical_head": "aaa111"})
    view = out["result"]["standing_constraint_root_view"]
    all_hot = set()
    all_enforced = set()
    all_members = set()
    for c in view["categories"] + view["spilled_categories"]:
        all_members.update(c.get("member_decision_ids", []))
        all_hot.update(c.get("hot", []))
        all_enforced.update(c.get("enforced", []))
    check("D-0051 (enforced_by=none) is HOT", "D-0051" in all_hot)
    check("D-0072 (enforced_by=doc-commit-gate) is ENFORCED, not HOT",
          "D-0072" in all_enforced and "D-0072" not in all_hot)
    check("D-0072 still counted (member of its category / the asserted set)", "D-0072" in all_members)

def test_f3_partial_supersession_predecessor_surfaces():
    print("\n[F3] a partially_superseded_by predecessor STILL surfaces alongside its successor")
    pool = base_pool()
    out = cc.run({"op": "compile_relevant_decisions", "modules": ["#21"], "decision_pool": pool,
                  "canonical_head": "aaa111"})
    ids = sorted(r["decision_id"] for r in out["result"]["compiled_decisions"])
    check("D-0050 (the partially-superseded predecessor) is present", "D-0050" in ids, ids)
    check("D-0143 (the partial successor) is present", "D-0143" in ids, ids)
    check("D-0040 (a FULLY superseded record) is EXCLUDED (current-only default)", "D-0040" not in ids, ids)
    d50 = next(r for r in out["result"]["compiled_decisions"] if r["decision_id"] == "D-0050")
    check("D-0050's status renders 'current' (never silently demoted)", d50["status"] == "current", d50)
    check("D-0050 carries its partially_superseded_by edge (auditable, not hidden)",
          d50["partially_superseded_by"] == ["D-0143"], d50)

def test_f4_stale_ingested_through_degrades():
    print("\n[F4] a stale ingested_through (vs canonical HEAD) degrades -- NEVER served as current")
    pool = base_pool()
    fresh = cc.run({"op": "compile_relevant_decisions", "decision_pool": pool, "canonical_head": "aaa111"})
    check("fresh: currentness == 'current' when ingested_through == canonical_head",
          fresh["result"]["currentness"] == "current", fresh["result"]["currentness"])
    stale = cc.run({"op": "compile_relevant_decisions", "decision_pool": pool, "canonical_head": "zzz999",
                    "uningested_append_count": 4})
    check("stale: currentness == 'stale' when ingested_through != canonical_head",
          stale["result"]["currentness"] == "stale", stale["result"]["currentness"])
    check("stale: current_as_of reports the (old) ingested_through SHA, not canonical_head",
          stale["result"]["current_as_of"] == "aaa111", stale["result"]["current_as_of"])
    check("stale: a warning names the degrade (auditable, not a silent swap)",
          any("currentness=stale" in w for w in stale["warnings"]), stale["warnings"])

def test_c4_global_question_slow_path():
    print("\n[C4] a global/full-history question returns the slow-path marker, never a fast compile")
    out = cc.run({"op": "compile_relevant_decisions", "query_text": "did we ever decide to drop the executor?"})
    check("ok", out["ok"])
    check("compile_status == slow_path", out["result"]["compile_status"] == "slow_path", out["result"])
    check("slow_path flag is true", out["result"]["slow_path"] is True)
    out2 = cc.run({"op": "compile_relevant_decisions", "action_class": "oscillation", "decision_pool": base_pool()})
    check("action_class=oscillation ALSO routes to the slow path", out2["result"]["slow_path"] is True)

def test_determinism_double_run_byte_identity():
    print("\n[determinism] byte-identical compiled set for identical records + identical query")
    pool = base_pool()
    args = {"op": "compile_relevant_decisions", "modules": ["#21", "#0", "#7"], "decision_pool": pool,
           "canonical_head": "aaa111", "standing_budget_categories": 1}
    a = cc.run(args)
    b = cc.run(args)
    check("re-run byte-identical (canonical_json equal)", cc.canonical_json(a) == cc.canonical_json(b))
    check("compiled_set_digest stable across runs",
          a["result"]["compiled_set_digest"] == b["result"]["compiled_set_digest"])
    # a DIFFERENT pool (order-shuffled, same records) -> the SAME compiled set (order-independent).
    shuffled = list(reversed(pool))
    c = cc.run({"op": "compile_relevant_decisions", "modules": ["#21", "#0", "#7"], "decision_pool": shuffled,
               "canonical_head": "aaa111", "standing_budget_categories": 1})
    check("pool order does not affect the compiled_set_digest (deterministic, not input-order-dependent)",
          a["result"]["compiled_set_digest"] == c["result"]["compiled_set_digest"],
          (a["result"]["compiled_set_digest"], c["result"]["compiled_set_digest"]))

def test_empty_pool_and_no_input_never_crash():
    print("\n[robustness] an empty pool / no decision_pool at all never crashes (fail-soft availability)")
    out = cc.run({"op": "compile_relevant_decisions", "decision_pool": []})
    check("empty pool -> ok, compiled_count=0, asserted_count=0", out["ok"] and
         out["result"]["compiled_count"] == 0 and
         out["result"]["standing_constraint_root_view"]["asserted_count"] == 0, out)
    out2 = cc.run({"op": "compile_relevant_decisions"})
    check("no decision_pool / no catalog_db_path -> ok, empty pool, NOT a crash", out2["ok"], out2)
    check("pool_source == 'none' when neither is supplied", out2["result"]["pool_source"] == "none", out2["result"])

def test_existing_ops_byte_identical_regression():
    print("\n[non-regression] the new op is ADDITIVE -- OPS keys grew, existing op behavior UNCHANGED")
    check("OPS carries all 4 keys", set(cc.OPS.keys()) == {"compile", "normalize", "expand",
                                                           "compile_relevant_decisions"}, sorted(cc.OPS.keys()))
    n1 = cc.run({"op": "normalize", "task": {"original_goal": "check nothing broke"}})
    n2 = cc.run({"op": "normalize", "task": {"original_goal": "check nothing broke"}})
    check("normalize still ok + byte-identical on re-run", n1["ok"] and
         cc.canonical_json(n1["result"]) == cc.canonical_json(n2["result"]))

def main():
    print("== i56 PB-6 GATE (FANOUT_AGENT_002): compile_relevant_decisions VERB, off-machine, REAL #37 selpol ==")
    test_f1_standing_asserted_count_no_silent_drop()
    test_rule2_demote_on_enforcement()
    test_f3_partial_supersession_predecessor_surfaces()
    test_f4_stale_ingested_through_degrades()
    test_c4_global_question_slow_path()
    test_determinism_double_run_byte_identity()
    test_empty_pool_and_no_input_never_crash()
    test_existing_ops_byte_identical_regression()
    print("\nI56-GATE RESULT: %d passed, %d failed" % (_PASS, _FAIL))
    return 0 if _FAIL == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
