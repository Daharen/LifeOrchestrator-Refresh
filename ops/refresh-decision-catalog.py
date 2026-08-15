#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ops/refresh-decision-catalog.py -- N7 close-time PB-6 boot-wiring driver (i57, D1+D2).

The sibling close step the PB-6 boot-wiring contract (research/2026-08-15-i57-pb6-boot-wiring-contract.md
s1) names: run the REAL #45 decision.intel producer over core-docs/DECISION_LOG.md at the close HEAD ->
ingest_records into a STANDING #36 catalog at ONE fixed, documented, drop+rebuildable path -> compute the
overlay standing-constraint ROOT view and write it into modules/44-project-map/map/overlay/state.json, so
#44 render emits it into the BOOT_PACKET OVERLAY (D2) and the boot stops needing DECISION_LOG_INDEX.md
whole (D3).

Runs via the EXECUTOR python (exec-job.sh), NOT the mount VM (which cannot delete/tempdir -- the drop is a
real rmtree/rebuild). This script performs NO git writes; the close flow commits map/ + generated/ + the
runtime sidecar is gitignored. Determinism: identity/status/edges/count/currency + the hot predicate are
CODE (the #45 producer + the #40 verb), never judgement; no model synopsis this increment.

Fixed catalog path (DERIVED, gitignored via the repo-root `**/runtime/`): drop+rebuildable every close;
nothing load-bearing lives only here (git + archive/ + the append-only DECISION_LOG.md stay canonical).

  modules/45-decision-intel/runtime/standing-catalog/decisions.sqlite

CLI:
  python3 ops/refresh-decision-catalog.py --repo <root> [--ingested-through <sha>] [--catalog <path>]
          [--no-write-overlay] [--standing-budget-categories <n>]

If --ingested-through is omitted it is read via NATIVE git (`git -C <repo> --no-optional-locks rev-parse
HEAD`) -- the DRIVER reads git, never the producer worker (mirrors #38's D-0072 no-git-in-the-worker rule).
Emits one JSON summary envelope on stdout.
"""

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys

STANDING_SCOPES = ("standing_prohibition", "invariant")
DEFAULT_CATALOG_REL = os.path.join(
    "modules", "45-decision-intel", "runtime", "standing-catalog", "decisions.sqlite")


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def resolve_head(repo):
    """DRIVER-side native git read (never the worker). Returns the HEAD sha or None."""
    try:
        out = subprocess.run(["git", "-C", repo, "--no-optional-locks", "rev-parse", "HEAD"],
                             capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except Exception:  # noqa: BLE001 -- git absent/off-repo -> caller must pass --ingested-through
        return None


def run_producer(repo, ingested_through, workdir):
    """Run the REAL #45 decision.intel producer over the real DECISION_LOG.md (+ index) at `ingested_through`.
    Returns (ingest_records_dict, records_digest, producer_meta). Byte-identical across runs at a fixed HEAD
    (the i56 producer double-run gate)."""
    di = _load("decision_intel", os.path.join(repo, "modules", "45-decision-intel", "decision_intel.py"))
    if os.path.isdir(workdir):
        shutil.rmtree(workdir)
    os.makedirs(workdir, exist_ok=True)
    payload = di.do_index({
        "op": "index",
        "decision_log_path": os.path.join(repo, "core-docs", "DECISION_LOG.md"),
        "decision_log_index_path": os.path.join(repo, "core-docs", "DECISION_LOG_INDEX.md"),
        "ingested_through": ingested_through,
        "namespace": "decisions",
        "output_dir": workdir,
    })
    with open(os.path.join(workdir, "ingest_records.json"), "r", encoding="utf-8") as f:
        ingest = json.load(f)
    return ingest, payload.get("records_digest"), payload


def rebuild_catalog(repo, catalog_path, ingest):
    """DROP + rebuild the standing #36 catalog (drop+rebuildable, D1). #36 owns storage; we feed the
    producer artifacts through the real `ingest-records` op (box python; the mount cannot delete)."""
    A = _load("artifact_search", os.path.join(repo, "modules", "36-artifact-search", "artifact_search.py"))
    cat_dir = os.path.dirname(catalog_path)
    if os.path.isdir(cat_dir):
        # drop ONLY the sqlite family (keep the producer-out/ workdir + sidecar); a clean rebuild each close
        for fn in os.listdir(cat_dir):
            if fn.startswith("decisions.sqlite"):
                os.remove(os.path.join(cat_dir, fn))
    os.makedirs(cat_dir, exist_ok=True)
    res = A.run({"op": "ingest-records", "db": catalog_path,
                 "records": ingest.get("records") or [], "ingest_run": ingest.get("ingest_run") or {}})
    if not res.get("ok"):
        raise RuntimeError("catalog ingest refused: %s" % json.dumps(res)[:400])
    return res


def _root_view_to_overlay(sv, ingested_through):
    """Transform the #40 verb's standing_constraint_root_view into the overlay `standing_constraints`
    field (D2). Carries the asserted_count (completeness, F1), the hot/gate-enforced split (s8 rule 2),
    child-category pointers, and the spill (spill, never compress)."""
    cats = []
    hot_total = 0
    enf_total = 0
    for c in sv.get("categories") or []:
        hot = len(c.get("hot") or [])
        enf = len(c.get("enforced") or [])
        hot_total += hot
        enf_total += enf
        cats.append({
            "category": c.get("category"),
            "count": c.get("count"),
            "hot": hot,
            "enforced": enf,
            "pointer": "deeper:%s:prohibition" % c.get("category"),
        })
    spilled_cats = [{"category": c.get("category"), "count": c.get("count"),
                     "pointer": c.get("deeper_query")} for c in (sv.get("spilled_categories") or [])]
    return {
        "asserted_count": sv.get("asserted_count"),
        "hot_count": hot_total,
        "enforced_count": enf_total,
        "categories": cats,
        "spilled": bool(sv.get("spilled")),
        "spill_pointer": "deeper:*:prohibition",
        "spilled_categories": spilled_cats,
        "synopsis": sv.get("synopsis"),
        "ingested_through": ingested_through,
        "source": DEFAULT_CATALOG_REL.replace(os.sep, "/"),
    }


def compute_standing_constraints(repo, catalog_path, ingested_through, budget_categories=None):
    """Compute the overlay standing-constraint ROOT view by REUSING the #40 verb (never forks): run
    compile_relevant_decisions over the freshly-built catalog at the close HEAD, extract its
    standing_constraint_root_view, and map it to the overlay field."""
    cc = _load("context_compiler", os.path.join(repo, "modules", "40-context-compiler", "context_compiler.py"))
    args = {"op": "compile_relevant_decisions", "catalog_db_path": catalog_path,
            "canonical_head": ingested_through}
    if budget_categories is not None:
        args["standing_budget_categories"] = int(budget_categories)
    out = cc.run(args)
    res = out.get("result") or {}
    sv = res.get("standing_constraint_root_view") or {}
    return _root_view_to_overlay(sv, ingested_through), res.get("currentness"), res.get("pool_source")


def write_overlay_standing(overlay_path, sc):
    """Surgical merge: set ONLY the `standing_constraints` field on the orchestrator-authored overlay,
    preserving every other field, and re-serialize in the map/ canonical form (indent=1, sorted keys,
    UTF-8 LF, trailing newline). Returns the (before, after) standing_constraints for idempotency checks."""
    with open(overlay_path, "r", encoding="utf-8") as f:
        overlay = json.load(f)
    before = overlay.get("standing_constraints")
    overlay["standing_constraints"] = sc
    text = json.dumps(overlay, indent=1, sort_keys=True, ensure_ascii=True) + "\n"
    with open(overlay_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return before, sc


def refresh(repo, ingested_through=None, catalog_path=None, write_overlay=True, budget_categories=None):
    """The whole close-refresh, importable for the D5 catalog-path test. Returns a summary dict."""
    repo = os.path.abspath(repo)
    if not ingested_through:
        ingested_through = resolve_head(repo)
    if not ingested_through:
        raise RuntimeError("no --ingested-through and native git HEAD unresolved -- supply the sha")
    catalog_path = catalog_path or os.path.join(repo, DEFAULT_CATALOG_REL)
    workdir = os.path.join(os.path.dirname(catalog_path), "producer-out")

    ingest, records_digest, prod_meta = run_producer(repo, ingested_through, workdir)
    ingest_res = rebuild_catalog(repo, catalog_path, ingest)
    sc, currentness, pool_source = compute_standing_constraints(
        repo, catalog_path, ingested_through, budget_categories)

    overlay_written = False
    if write_overlay:
        overlay_path = os.path.join(repo, "modules", "44-project-map", "map", "overlay", "state.json")
        write_overlay_standing(overlay_path, sc)
        overlay_written = True

    # sidecar: record the catalog's ingested_through at the fixed path (the catalog "records
    # ingested_through", D1 -- the per-commit currency anchor, s8 rule 5).
    sidecar = os.path.join(os.path.dirname(catalog_path), "CATALOG_STATE.json")
    state = {
        "schema": "lifeorch.standing_decision_catalog_state/0.1",
        "catalog": os.path.relpath(catalog_path, repo).replace(os.sep, "/"),
        "ingested_through": ingested_through,
        "record_count": ingest.get("record_count"),
        "records_digest": records_digest,
        "standing_asserted_count": sc.get("asserted_count"),
        "standing_hot_count": sc.get("hot_count"),
        "standing_enforced_count": sc.get("enforced_count"),
        "produced_by": "ops/refresh-decision-catalog.py",
    }
    with open(sidecar, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(state, indent=1, sort_keys=True, ensure_ascii=True) + "\n")

    return {
        "ok": True,
        "ingested_through": ingested_through,
        "catalog": os.path.relpath(catalog_path, repo).replace(os.sep, "/"),
        "record_count": ingest.get("record_count"),
        "records_digest": records_digest,
        "ingest_counts": (ingest_res.get("result") or {}).get("counts"),
        "standing_constraints": sc,
        "currentness": currentness,
        "pool_source": pool_source,
        "overlay_written": overlay_written,
        "sidecar": os.path.relpath(sidecar, repo).replace(os.sep, "/"),
    }


def main():
    ap = argparse.ArgumentParser(description="i57 PB-6 boot-wiring close-refresh: standing #36 decision "
                                             "catalog + overlay standing-constraint root view.")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--ingested-through", default=None,
                    help="DECISION_LOG.md HEAD sha; if omitted, read via native git")
    ap.add_argument("--catalog", default=None, help="override the fixed standing-catalog path")
    ap.add_argument("--no-write-overlay", action="store_true",
                    help="build+ingest the catalog but do NOT touch map/overlay/state.json")
    ap.add_argument("--standing-budget-categories", type=int, default=None)
    a = ap.parse_args()
    try:
        summary = refresh(a.repo, ingested_through=a.ingested_through, catalog_path=a.catalog,
                          write_overlay=not a.no_write_overlay, budget_categories=a.standing_budget_categories)
        sys.stdout.write(json.dumps(summary, indent=2, sort_keys=True) + "\n")
        return 0
    except Exception as e:  # noqa: BLE001 -- fail-closed: a non-zero exit, a structured error on stdout
        sys.stdout.write(json.dumps({"ok": False, "error": "%s: %s" % (type(e).__name__, e)}) + "\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
