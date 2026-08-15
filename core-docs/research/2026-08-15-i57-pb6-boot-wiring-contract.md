# PB-6 BOOT-WIRING -- FROZEN CONTRACT (i57; the ONE governing doc for FANOUT_AGENT_001)

**Status: FROZEN at i57 scoping (orchestrator-inline, Opus 4.8 Extra seat). This is the ONE governing
design doc the PB-6 boot-wiring lane builds against.** Single lane (no D-0077 pair). Authoritative
upstream spec: `research/2026-08-14-pb7-relayer-design-2.md` s7-s9 (the s8 hardened ruleset is
authoritative) + `research/2026-08-14-pb6-decision-record-schema.md` s4 + `research/2026-08-12-knowledge-surface-relayer-program.md`. Reuses, never forks: #45 decision.intel producer (BUILT i56), #40
`compile_relevant_decisions` verb 0.10.0 (BUILT i56), #36 artifact.search catalog, #44 project.map overlay/render.

## 0. What boot-wiring proves (why this is the increment)

i56 BUILT the producer + verb + proved the producer->#36->verb seam (D-0150). It did NOT wire the result into
BOOT: a booting session still learns its live constraints by reading whole docs. Boot-wiring closes PB-6 by
making the HOT bootstrap surface carry a bounded, COUNT-ASSERTED standing-constraint view sourced from a
STANDING decision catalog, so the boot stops needing to ingest `DECISION_LOG_INDEX.md` whole. This proves the
decoupling (design C1-C4) on the real boot surface: G1 bounded-hot, G2 completeness-provable, G5 spill-not-
compress, G6 gates-intact (design s9), as the decision corpus grows.

## 1. The five deliverables (frozen scope -- do exactly these; nothing else)

**D1 -- STANDING #36 decision catalog, refreshed each close.**
A durable #36 catalog holding the #45 `record_kind=decision` records, at ONE fixed documented path, DERIVED
(drop+rebuildable from `DECISION_LOG.md`; may live under a gitignored `runtime/` since the box persists it and
every close rebuilds it -- nothing load-bearing lives only here). The wave-close flow (extend
`ops/close-refold.ps1` or add a sibling close step, executor python -- the mount cannot delete/tempdir) runs the
REAL #45 producer over `DECISION_LOG.md` at the close HEAD -> `ingest_records` into the standing catalog. The
catalog records `ingested_through` = that HEAD (design s8 rule 5). Idempotent: re-running at the same HEAD is a
byte-identical rebuild (the i56 producer double-run gate already guarantees deterministic records).

**D2 -- the overlay standing-constraint ROOT view (design s8 rule 3; kills F1).**
The #44 overlay (`map/overlay/state.json`) gains a `standing_constraints` root view, COMPUTED DETERMINISTICALLY
from the standing catalog (recommended: the close step computes it and writes it into the overlay; #44 render
then emits it -- keeps the tested render pure). It carries:
  - `asserted_count` -- the count of LIVE standing constraints: `binding_scope in {standing_prohibition,
    invariant}` AND the hot predicate `status=current AND enforced_by=none` (rule 2 demote-on-enforcement).
  - `categories[]` -- child-category pointers (by binding_scope and/or action-class), each `{label, count,
    pointer}` where pointer is a bounded cold query (e.g. `deeper:*:prohibition` / a #40 verb call).
  - `spill` -- below the overlay budget cut, SPILL to the cold query, never compress (rule 3). Record what spilled.
The root view REPLACES the current hand-authored flat `prohibitions[]` list (4 entries) as the source of truth
for live constraints -- now catalog-derived + count-asserted + COMPLETE (no binding constraint ever silently
absent). The existing `prohibitions[]` may stay as the always-pinned top-severity subset, but the ASSERTED
COUNT + categories prove completeness without every leaf. #44 render emits into the BOOT_PACKET OVERLAY:
`STANDING CONSTRAINTS: <asserted_count> live -- <categories>; expand via <spill pointer>`.

**D3 -- boot stops ingesting `DECISION_LOG_INDEX.md` whole (the payoff).**
Update the RETRIEVAL PROTOCOL (the BOOT_PACKET-rendered table + `START_HERE.md`/doctrine as needed): a booting
session gets live constraints from the overlay root view (D2) and task-relevant decisions from
`compile_relevant_decisions` (D4) -- NOT a whole-file `DECISION_LOG_INDEX.md` open. The index SURVIVES as the
complete human-readable routing catalog (cold, retrievable, still the append-a-row upkeep target, growth-exempt
D-0139) but is no longer a bootstrap whole-ingest. This is a doctrine + render change, not a deletion.

**D4 -- bounded pool load in the verb.**
`compile_relevant_decisions` loads its decision pool from the STANDING catalog (D1) with BOUNDED fanout: a
documented top-k / hierarchy cap + #37 `selpol_rrf_v1` ranking, current-only by default (the i56 seam fix moved
it to `list-records`; make that load BOUNDED, not whole-catalog). Global/full-history questions stay the C4
explicit slow path.

**D5 -- the catalog-path test (fail-closed, in the owning module's tests/).**
Asserts, over the REAL catalog: (a) close-refresh producer->#36 is idempotent byte-identical at a fixed HEAD;
(b) the overlay `asserted_count` EQUALS an independent direct-catalog count of live standing constraints -- 0
silent drop (F1); (c) bounded pool load returns <= the documented cap; (d) per-commit currency (F4): a catalog
whose `ingested_through` < canonical HEAD self-labels `currentness=stale` (or incrementally ingests) -- never
serves superseded-as-current; (e) boot no longer whole-ingests `DECISION_LOG_INDEX.md` (assert the boot path /
retrieval-ledger); (f) doc-commit-gate green on the touched core-docs; (g) P0-1 `non_execution` untouched --
retrieved memory is EVIDENCE (`can_instruct=false`), never control/action; (h) boot_read 0-stale at HEAD after
the close-refold.

## 2. Guardrails (binding)

No loss of history: git + `archive/` + the append-only `DECISION_LOG.md` stay complete + untouched; the standing
catalog is derived + drop+rebuildable. doc-commit-gate + s2 budgets SURVIVE (the producer becomes a commit/close
ingestion trigger, rule 5). P0-1 stays FROZEN: retrieved memory is evidence, `non_execution:true` holds. All of
identity/status/edges/count/currency + the hot predicate are DETERMINISTIC code, not judgement (no model synopsis
this increment -- `synopsis` stays RESERVED null).

## 3. Acceptance (an increment is "done" when -- design s9, boot-surface subset)

G1 bounded-hot: BOOT_PACKET stays <= the N4 bar (20,000 B) with the root view in place; hot bytes flat as
decisions grow (the standing subset is bounded by the rule-3 spill, not linear). G2 completeness: `asserted_count`
+ categories at boot, no live constraint silently absent, "all live constraints of class X" is one bounded
descend. G3 lossless+expandable: each surfaced constraint expands to its `DECISION_LOG.md` span; catalog
drop+rebuild byte-identical. G4 honest currency: a mid-wave HEAD advance never serves superseded-as-current
(re-ingest or self-label stale). G5 no harsher-compression: overlay SPILLS to cold, never compresses. G6 gates:
doc-commit-gate green; P0-1 `non_execution` untouched; boot_read 0-stale at HEAD.

## 4. Rails (single-lane core-infra wave)

ONE unit; `docs:[]`; no GPU (CPU). Ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only);
VERIFY the real HEAD via NATIVE git (D-0072); assert 0 UNMANAGED orphans. Core-doc edits (RETRIEVAL PROTOCOL /
doctrine) are the WORKER's proposed diffs handed back to the orchestrator to mirror under the `git` lease -- the
worker itself runs `docs:[]` and touches only its module/render/close code + tests. Any #44 render change is
still a change to the DEFAULT bootstrap surface: the orchestrator re-runs verify + render --check at fold. Model:
Opus 4.8 Extra (core-infra semantics + the default bootstrap surface; D-0114 elevation).
