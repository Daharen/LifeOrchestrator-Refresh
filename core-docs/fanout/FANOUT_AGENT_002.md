# FANOUT_AGENT_002 -- PB-6 "compile task-relevant decision set" VERB (#40 extension) -- READY

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i56 (plan id `fo-56-<id>` once planned)
- **Lane:** CPU / CODING lane B (no GPU)
- **Worker id / label:** `DEC-VERB-i56`
- **Module/area (exclusive):** `modules/40-context-compiler/` (extend it: the new `compile_relevant_decisions` verb). READ-ONLY everywhere else. You do NOT create `modules/45-*` (lane A), do NOT write `modules/36-*` or `modules/37-*` code (REUSE their shipped interfaces), no core-doc, no `map/`/`generated/`.
- **GPU:** false
- **Docs:** `[]` (you report; the orchestrator mirrors core-docs)
- **Recommended model:** Sonnet 5 High (D-0114 default lane: bounded increment over a frozen retrieval stack + suite-gated; "no new retrieval arch")

## Mission

Build lane B of PB-6 (design `research/2026-08-14-pb7-relayer-design-2.md` s7): the selective **retrieval verb** that compiles a BOUNDED task-relevant decision set from the typed `record_kind=decision` records (lane A's output, ingested into #36), routed through the ALREADY-BUILT engines -- `#40 context.compiler` + `#37 selpol_rrf_v1` -- with **NO new retrieval architecture**. This is the hot-path half of the decoupling: an ordinary session gets a compiled relevant set + the standing-constraint root view instead of ingesting `DECISION_LOG_INDEX.md` whole. You consume lane A's schema, so conform EXACTLY to the frozen contract; you and lane A are a D-0077 producer/consumer pair (orchestrator smokes the seam at fold).

## Unit (ONE scoped extension of `modules/40-context-compiler/`)

**READ FIRST, in order:** `core-docs/research/2026-08-14-pb6-decision-record-schema.md` (THE FROZEN CONTRACT -- s4 is your verb spec: the input signals, the bounded output shape, the s8 hardened hot/cold predicate rules 1-5), then `research/2026-08-14-pb7-relayer-design-2.md` s7/s8/s9, `modules/40-context-compiler/SCHEMA_NOTES.md` + `WORK_ORDER.md` (the three-region context_packet/0.2, the R-1 router, working-memory hydration -- the surfaces you extend), `modules/37-retrieval-eval/SCHEMA_NOTES.md` (`selpol_rrf_v1` -- frozen hit fields, `rank=index+1`, never re-sort), `modules/36-artifact-search/SCHEMA_NOTES.md` s3 (search filters incl. `record_kind`, the frozen hit fields).

**BUILD the `compile_relevant_decisions` verb in `#40`:**
- INPUT `{modules[], planes[], recency_window, action_class?, query_text?}` -> route via `#37 selpol_rrf_v1` over `#36` filtered to `record_kind=decision` -> OUTPUT a bounded top-k set of `status=current` + task-relevant decision records (supersession-aware; current-only by DEFAULT), each row expandable to its `source_span` in `DECISION_LOG.md`.
- **The s8 hardened predicate is AUTHORITATIVE (frozen contract s4):** (1) `binding_scope in {standing_prohibition,invariant}` records are ALWAYS included via the standing-constraint ROOT view -- pin the root synopsis + child-category pointers + an ASSERTED COUNT (completeness proved without every leaf); below the #40 budget cut, SPILL to a cold query (`deeper:*:prohibition`), never compress. (2) demote-on-enforcement: `enforced_by=none` gates hotness. (4) `partially_superseded_by` KEEPS the predecessor `current` (never drop an in-force aspect). (5) per-commit currency: compare `ingested_through` to canonical HEAD; if it advanced, degrade the result to "current as of <SHA>, K un-ingested appends" + `currentness=stale` (do NOT silently serve stale-as-current).
- Global/full-history questions (C4: "did we ever decide X?", oscillation) are the EXPLICIT slow path -- the verb returns a slow-path marker, it does NOT attempt them as a fast query.
- **Determinism (HARD):** byte-identical compiled set for identical records + identical query (double-run gate); flat compile byte-identical for unchanged inputs (preserve #40's existing regression baselines -- re-baseline only where the new region legitimately changes output, and REPORT every re-baseline).
- Update `#40` `skill.json` (minor bump) + `SCHEMA_NOTES.md` (the verb's field/predicate interpretation -- your per-module D-0077 record) + the verb/region docs; PRESERVE every existing #40 invariant (three-region packet, R-1 router, working-memory conjunctive-ns fail-closed).

## Rails (standing)
- Boot from the PCB `modules/44-project-map/generated/BOOT_PACKET.md` (step-0 verify / query stale); read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease in **git** order (no GPU, no doc); release on exit. Do ONE unit; `docs:[]`; touch ONLY `modules/40-context-compiler/**`.
- Because lane A's real records do not exist in your session, build + test against FIXTURE decision records that conform to the frozen contract (include a standing_prohibition, an enforced_by=<gate>, a partially_superseded_by chain, and a stale-`ingested_through` case). The orchestrator runs the REAL cross-module seam at fold.
- Gate off-machine FIRST, then `-Live`, then ship via `exec-job.sh devship` (NAMED FILES ONLY under `modules/40-context-compiler/**`; trailers); **VERIFY the real HEAD via native git** (D-0072); assert 0 UNMANAGED orphans. Same pwsh-determinism gotchas as lane A.

## Verification / report-back
- Suite green cloud + `-Live`: every s8 rule fixture-asserted -- the standing-constraint ROOT view returns the asserted COUNT with NO silent drop under a tight budget (F1); a `partially_superseded_by` predecessor still surfaces (F3); a stale-`ingested_through` input yields the degraded "current as of <SHA>" result, never stale-as-current (F4); double-run byte-identity over the compiled set; #40's prior regression baselines green (re-baselines REPORTED).
- Report (`-Action report -PlanId <plan> -WorkerId DEC-VERB-i56 -State done` + a plain measured summary): the verb I/O contract as built; the fixture set; each s8 rule's asserting test; every #40 baseline re-based with a one-line why; measured compiled-set byte bounds vs fixture N (the C1/C2 evidence); any deviation from the frozen contract flagged in writing (unexplained = FAIL). An honest INCOMPLETE beats a false done (D-0107/D-0109).
- Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving): _empty._
