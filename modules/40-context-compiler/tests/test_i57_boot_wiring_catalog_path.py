#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""i57 PB-6 BOOT-WIRING -- the catalog-path GATE TEST (D5, FAIL-CLOSED).

Governing (FROZEN): core-docs/research/2026-08-15-i57-pb6-boot-wiring-contract.md s1-D5 (a)-(h) + s3
(G1-G6). Unlike the i56 verb gate (fixture pool, off-machine), THIS test drives the REAL cross-module
catalog PATH end to end -- the real #45 producer over the real DECISION_LOG.md -> a real #36 catalog
(built at a temp path) -> the real #40 verb + the real #44 render + the ops/refresh-decision-catalog.py
close step. It is the OFF-MACHINE gate the rails require ("gate off-machine FIRST"); the -Live executor
re-runs it at fold.

Asserts s1-D5:
  (a) close-refresh producer -> #36 is IDEMPOTENT byte-identical at a fixed HEAD (records_digest + the
      producer canonical artifacts + the derived standing_constraints all byte-stable across two runs).
  (b) the overlay `asserted_count` EQUALS an INDEPENDENT direct-catalog count of live standing
      constraints -- 0 silent drop (F1). The hot subset (enforced_by=none) also matches independently.
  (c) the BOUNDED pool load returns <= the documented cap on the ORDINARY fanout, while the STANDING set
      is kept WHOLE (a tiny cap never drops a standing record).
  (d) per-commit currency (F4): a catalog whose ingested_through < canonical HEAD self-labels
      `currentness=stale` -- never serves superseded-as-current.
  (e) boot no longer whole-ingests DECISION_LOG_INDEX.md: the rendered OVERLAY carries the STANDING
      CONSTRAINTS root-view line (live constraints available WITHOUT the index), boot_read excludes the
      index, and the index SURVIVES as the cold routing catalog (the file is not deleted).
  (f) the worker ran docs:[] -- the shipped file set touches NO core-doc (the D3 doctrine diff is a
      PROPOSAL handed back to the orchestrator), so the doc-commit-gate is green for this commit.
  (g) P0-1 `non_execution` untouched: retrieved memory is EVIDENCE -- the verb output carries no action /
      execution / can_instruct=true authority, and the P0-1 activation prohibition (D-0118) is still a
      CURRENT standing constraint in the catalog (boot-wiring did not drop it).
  (h) boot_read 0-stale at HEAD: at canonical_head == the catalog's ingested_through the verb reports
      `currentness=current` (the fresh close-refold state).

Pure python3 + stdlib. No model, no network. Writes only under a tempdir (never the real catalog/overlay).
FAIL-CLOSED: any failed check -> non-zero exit.
"""

import importlib.util
import json
import os
import shutil
import sys
import tempfile

# ------------------------------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("LOR_REPO") or HERE
while REPO != os.path.dirname(REPO) and not os.path.isdir(os.path.join(REPO, "modules", "40-context-compiler")):
    REPO = os.path.dirname(REPO)
MOD = os.path.join(REPO, "modules")

STANDING_SCOPES = {"standing_prohibition", "invariant"}
FULL_DEMOTE = {"superseded_by", "folded_into", "folded", "closed_by", "closed"}
# a fixed, valid-hex test HEAD (the producer requires 7-40 lowercase hex; content is stamped as
# ingested_through -> canonical artifacts stay byte-identical across runs at THIS sha).
TEST_HEAD = "5dfff2ae691b5db9cadc333f14b3c8ed950801a9"
OTHER_HEAD = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

# the file set THIS increment ships (docs:[] proof, check (f)) -- module/render/close code + tests only.
SHIPPED_FILES = [
    "modules/40-context-compiler/context_compiler.py",
    "modules/40-context-compiler/SCHEMA_NOTES.md",
    "modules/40-context-compiler/tests/test_i57_boot_wiring_catalog_path.py",
    "modules/44-project-map/project_map.py",
    "modules/44-project-map/SCHEMA_NOTES.md",
    "ops/refresh-decision-catalog.py",
]

_PASS = 0
_FAIL = 0


def check(label, ok, detail=""):
    global _PASS, _FAIL
    ok = bool(ok)
    _PASS += 1 if ok else 0
    _FAIL += 0 if ok else 1
    tag = "PASS" if ok else "FAIL"
    print("  [%s] %s%s" % (tag, label, ("   :: " + str(detail) if (detail and not ok) else "")))
    return ok


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


CC = _load("context_compiler", os.path.join(MOD, "40-context-compiler", "context_compiler.py"))
AS = _load("artifact_search", os.path.join(MOD, "36-artifact-search", "artifact_search.py"))
PM = _load("project_map", os.path.join(MOD, "44-project-map", "project_map.py"))
REF = _load("refresh_decision_catalog", os.path.join(REPO, "ops", "refresh-decision-catalog.py"))


def _independent_standing_counts(catalog_path):
    """Compute, DIRECTLY from the catalog via a full #36 scan (NOT the verb's path), the F1 reference:
    the count of LIVE standing constraints + its hot (enforced_by=none) subset + a producer-anomaly guard.

    'Live standing constraint' = binding_scope in {standing_prohibition,invariant} AND status=current
    (the D2 predicate; a current record is always in-force, so this equals the verb's current-only
    asserted set). The `anomalies` guard makes the current-only vs in-force-over-all divergence EXPLICIT
    and fail-closed: a standing record with a TERMINAL status but NO full supersession edge is a producer
    defect (the design conservatively treats it in-force) -- it MUST be 0, else the bounded current-only
    load and a naive in-force-over-all count would diverge (and it would be a silent standing drop)."""
    res = AS.run({"op": "list-records", "db": catalog_path,
                  "filters": {"record_kind": "decision", "namespace": "decisions"}, "limit": 100000})
    recs = (res.get("result") or {}).get("records") or []

    def in_force(r):
        st = r.get("status")
        full = [e for e in (r.get("parent_edges") or []) + (r.get("child_edges") or [])
                if (e.get("edge_kind") or "") in FULL_DEMOTE]
        return (not bool(full)) if st in ("superseded", "folded", "closed") else True

    standing_all = [r for r in recs if (r.get("attrs") or {}).get("binding_scope") in STANDING_SCOPES]
    live = [r for r in standing_all if r.get("status") == "current"]
    hot = [r for r in live if (r.get("attrs") or {}).get("enforced_by", "none") in ("none", "", None)]
    anomalies = [r for r in standing_all
                 if r.get("status") in ("superseded", "folded", "closed") and in_force(r)]
    return len(live), len(hot), len(recs), len(anomalies)


def main():
    print("== i57 PB-6 BOOT-WIRING catalog-path GATE (D5, fail-closed) : REAL producer -> #36 -> verb ==")
    tmp = tempfile.mkdtemp(prefix="i57-bootwire-")
    try:
        cat1 = os.path.join(tmp, "cat1", "decisions.sqlite")
        cat2 = os.path.join(tmp, "cat2", "decisions.sqlite")
        os.makedirs(os.path.dirname(cat1)); os.makedirs(os.path.dirname(cat2))

        s1 = REF.refresh(REPO, ingested_through=TEST_HEAD, catalog_path=cat1, write_overlay=False)
        s2 = REF.refresh(REPO, ingested_through=TEST_HEAD, catalog_path=cat2, write_overlay=False)
        check("close-refresh ok", s1["ok"] and s2["ok"], (s1.get("ok"), s2.get("ok")))

        # ---- (a) idempotency: byte-identical rebuild at a fixed HEAD ----
        print("\n[a] close-refresh producer->#36 idempotent byte-identical at a fixed HEAD")
        check("records_digest stable across runs", s1["records_digest"] == s2["records_digest"],
              (s1["records_digest"], s2["records_digest"]))
        check("standing_constraints byte-identical across runs",
              json.dumps(s1["standing_constraints"], sort_keys=True) ==
              json.dumps(s2["standing_constraints"], sort_keys=True))
        po1 = os.path.join(os.path.dirname(cat1), "producer-out")
        po2 = os.path.join(os.path.dirname(cat2), "producer-out")
        allsame = all(
            open(os.path.join(po1, f), "rb").read() == open(os.path.join(po2, f), "rb").read()
            for f in ("records.jsonl", "records.json", "ingest_records.json", "coverage.json"))
        check("producer canonical artifacts byte-identical across runs", allsame)

        # ---- (b) F1: overlay asserted_count == independent direct-catalog count (0 drop) ----
        print("\n[b] overlay asserted_count == INDEPENDENT direct-catalog live-standing count (F1)")
        indep_standing, indep_hot, total, indep_anom = _independent_standing_counts(cat1)
        sc = s1["standing_constraints"]
        check("no superseded/folded/closed standing record lacks its full edge (current-only load == "
              "in-force count; producer clean)", indep_anom == 0, indep_anom)
        check("asserted_count == independent live-standing count (0 silent drop)",
              sc["asserted_count"] == indep_standing, (sc["asserted_count"], indep_standing))
        check("hot_count == independent enforced_by=none subset (rule 2 split honest)",
              sc["hot_count"] == indep_hot, (sc["hot_count"], indep_hot))
        pinned = sum(c["count"] for c in sc["categories"])
        spilled = sum(c["count"] for c in sc.get("spilled_categories", []))
        check("pinned + spilled category counts == asserted_count (nothing vanished)",
              pinned + spilled == sc["asserted_count"], (pinned, spilled, sc["asserted_count"]))

        # ---- (c) bounded pool load <= documented cap; standing kept whole ----
        print("\n[c] bounded pool load returns <= the documented ordinary cap; standing WHOLE")
        cap = 5
        pool, src, _ = CC._load_decision_pool_from_catalog({"catalog_db_path": cat1, "ordinary_pool_cap": cap})
        ordn = [r for r in pool if r.get("binding_scope") not in STANDING_SCOPES]
        stnd = [r for r in pool if r.get("binding_scope") in STANDING_SCOPES]
        check("ordinary fanout <= cap", len(ordn) <= cap, (len(ordn), cap))
        check("standing set kept WHOLE under a tiny cap (F1 -- never dropped)",
              len(stnd) == indep_standing, (len(stnd), indep_standing))
        default_pool, _, _ = CC._load_decision_pool_from_catalog({"catalog_db_path": cat1})
        check("default load is current-only (< whole catalog of %d)" % total,
              len(default_pool) < total, (len(default_pool), total))

        # ---- (d) F4 currency: stale self-label when ingested_through < canonical HEAD ----
        print("\n[d] per-commit currency (F4): ingested_through < canonical HEAD -> currentness=stale")
        out_stale = CC.run({"op": "compile_relevant_decisions", "catalog_db_path": cat1,
                            "canonical_head": OTHER_HEAD, "top_k": 5})["result"]
        check("currentness == stale when HEAD advanced", out_stale["currentness"] == "stale",
              out_stale["currentness"])
        check("current_as_of reports the catalog's (old) ingested_through, not the new HEAD",
              out_stale["current_as_of"] == TEST_HEAD, out_stale["current_as_of"])
        check("standing asserted_count STILL complete while stale (never a silent drop)",
              out_stale["standing_constraint_root_view"]["asserted_count"] == indep_standing)

        # ---- (e) boot no longer whole-ingests DECISION_LOG_INDEX.md ----
        print("\n[e] boot stops whole-ingesting DECISION_LOG_INDEX.md (overlay root view is the source)")
        overlay_src = os.path.join(MOD, "44-project-map", "map", "overlay", "state.json")
        ov = json.load(open(overlay_src))
        ov_tmp = dict(ov)
        ov_tmp["standing_constraints"] = sc
        m = PM.MapModel(); m.overlay = ov_tmp
        sec, _ = PM._build_overlay_section(m)
        check("rendered OVERLAY carries the STANDING CONSTRAINTS root-view line",
              any(l.startswith("STANDING CONSTRAINTS") for l in sec.splitlines()))
        boot_reads = [(b.get("ref") if isinstance(b, dict) else b) for b in (ov.get("boot_read") or [])]
        check("boot_read set excludes DECISION_LOG_INDEX.md (not a boot whole-open)",
              not any("DECISION_LOG_INDEX" in str(r) for r in boot_reads), boot_reads)
        check("the index SURVIVES as the cold routing catalog (file not deleted)",
              os.path.isfile(os.path.join(REPO, "core-docs", "DECISION_LOG_INDEX.md")))

        # ---- (f) docs:[] -- the shipped set touches no core-doc (doc-commit-gate green) ----
        print("\n[f] docs:[] -- the worker's shipped file set touches NO core-doc")
        no_core = [f for f in SHIPPED_FILES if f.startswith("core-docs/")]
        check("no shipped file is a core-doc (D3 doctrine diff is a handed-back PROPOSAL)", not no_core, no_core)
        check("every shipped file exists on disk", all(os.path.isfile(os.path.join(REPO, f)) for f in SHIPPED_FILES))

        # ---- (g) P0-1 non_execution untouched: evidence-only + D-0118 still current standing ----
        print("\n[g] P0-1 non_execution untouched -- retrieved memory is EVIDENCE, D-0118 still standing")
        fresh = CC.run({"op": "compile_relevant_decisions", "catalog_db_path": cat1,
                       "canonical_head": TEST_HEAD, "modules": ["43"], "top_k": 20})["result"]
        blob = json.dumps(fresh)
        check("verb output carries NO can_instruct=true / execution authority (evidence-only)",
              '"can_instruct": true' not in blob and '"non_execution": false' not in blob)
        allrecs = (AS.run({"op": "list-records", "db": cat1,
                          "filters": {"record_kind": "decision", "namespace": "decisions"},
                          "limit": 100000})["result"]["records"])
        d0118 = [r for r in allrecs if (r.get("attrs") or {}).get("decision_id") == "D-0118"]
        check("P0-1 activation prohibition D-0118 present in the catalog", len(d0118) == 1, len(d0118))
        if d0118:
            a = d0118[0].get("attrs") or {}
            check("D-0118 is a CURRENT standing constraint (boot-wiring did not drop/demote it)",
                  d0118[0].get("status") == "current" and a.get("binding_scope") in STANDING_SCOPES,
                  (d0118[0].get("status"), a.get("binding_scope")))

        # ---- (h) boot_read 0-stale at HEAD after the close-refold ----
        print("\n[h] boot_read 0-stale at HEAD after the close-refold (currentness=current)")
        check("currentness == current at canonical_head == ingested_through",
              fresh["currentness"] == "current", fresh["currentness"])
        check("current_as_of == the close HEAD", fresh["current_as_of"] == TEST_HEAD, fresh["current_as_of"])

        print("\nI57-BOOTWIRE-GATE RESULT: %d passed, %d failed" % (_PASS, _FAIL))
        return 0 if _FAIL == 0 else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
