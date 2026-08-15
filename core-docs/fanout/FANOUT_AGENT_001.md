# FANOUT_AGENT_001 -- i57 PB-6 boot-wiring (GPU-lane slot, used here as the single CPU core-infra lane)

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** FILLED (i57 scoping)
- **Wave / iteration:** i57 -- plan id `fo-57-<id>` once planned
- **Lane:** single core-infra lane (no GPU worker this wave; no D-0077 pair)
- **Worker id / label:** i57-BOOTWIRE
- **Module/area (exclusive):** the decision boot-wiring seam ONLY -- #45 decision.intel (standing catalog + close refresh) + #40 `compile_relevant_decisions` (bounded pool load) + #44 project.map overlay/render (standing-constraint ROOT view) + the catalog-path test. Proposed RETRIEVAL-PROTOCOL/doctrine core-doc diffs are handed BACK to the orchestrator (worker runs `docs:[]`).
- **GPU:** false
- **Docs:** `[]`
- **Recommended model:** Opus 4.8 Extra (core-infra + the DEFAULT bootstrap surface; D-0114 elevation).

## Mission
Close PB-6 by WIRING the i56-built decision producer+verb into BOOT: the hot bootstrap surface carries a
bounded, COUNT-ASSERTED standing-constraint view from a STANDING #36 decision catalog, so the boot stops
ingesting `DECISION_LOG_INDEX.md` whole. Build EXACTLY the five deliverables D1-D5 in the frozen contract.

## Unit (the full worker prompt)

You are the i57 PB-6 boot-wiring worker (single core-infra lane). Read FIRST, in order:
1. `core-docs/research/2026-08-15-i57-pb6-boot-wiring-contract.md` -- the ONE FROZEN GOVERNING DOC. Build
   exactly its D1-D5; meet its s3 acceptance (G1-G6); obey its s2 guardrails + s4 rails.
2. `core-docs/research/2026-08-14-pb7-relayer-design-2.md` s7-s9 (the s8 hardened ruleset is AUTHORITATIVE) +
   `core-docs/research/2026-08-14-pb6-decision-record-schema.md` s4 (the hot/cold predicate + verb contract).
3. `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' (the gotcha corpus -- read it,
   it will save you); obey `core-docs/SKILL_CONTRACT.md`.
4. The built pieces you REUSE (never fork): `modules/45-decision-intel/` (producer + SCHEMA_NOTES),
   `modules/40-context-compiler/` (the verb 0.10.0 + its catalog loader), `modules/36-artifact-search/`
   (`ingest_records` / `list-records` / SCHEMA_NOTES), `modules/44-project-map/` (overlay + render).

BUILD (contract D1-D5):
- **D1** a STANDING #36 decision catalog at one fixed documented path (derived + drop+rebuildable), refreshed
  each close by the REAL #45 producer -> `ingest_records` at the close HEAD (records `ingested_through`).
- **D2** the overlay `standing_constraints` ROOT view -- `asserted_count` of LIVE standing constraints
  (`binding_scope in {standing_prohibition,invariant}` AND `status=current AND enforced_by=none`), `categories[]`
  child-pointers, and `spill` to a cold query below the budget cut (SPILL, never compress). Recommended: the
  close step computes it and writes it into `map/overlay/state.json`; #44 render emits it into the BOOT_PACKET.
- **D3** stop the whole-file `DECISION_LOG_INDEX.md` bootstrap ingest -- propose the RETRIEVAL-PROTOCOL/doctrine
  diff (hand it back to the orchestrator; you run `docs:[]`). The index SURVIVES as the cold routing catalog.
- **D4** bounded pool load in `compile_relevant_decisions` (documented top-k/hierarchy cap + #37 selpol,
  current-only default) from the standing catalog -- not whole-catalog.
- **D5** the catalog-path test (fail-closed) asserting contract s1-D5 (a)-(h): close-refresh idempotency;
  overlay count == independent catalog count (F1, 0 drop); bounded load <= cap; per-commit currency stale-label
  (F4); boot doesn't whole-ingest the index; doc-gate green; P0-1 `non_execution` untouched; boot_read 0-stale.

DETERMINISM: identity/status/edges/count/currency + the hot predicate are CODE, not judgement; no model synopsis
this increment (`synopsis` stays null). Byte-identity double-run gate on every canonical artifact.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (hand core-doc diffs back).
- No GPU/model work this lane. Gate off-machine FIRST, then ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via NATIVE git (D-0072); assert 0 UNMANAGED orphans.
- The mount VM CANNOT delete/tempdir: any #36 ingest / render --check / rmtree runs via the executor python (exec-job.sh), not the mount.
- Report: `-Action report -PlanId <plan> -WorkerId i57-BOOTWIRE -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos). Leave the commit to the executor if your session lacks pwsh/executor -- that is DONE-minus-ship, not failure (the i40/i48 pattern).

## Verification (orchestrator, at fold)
- Independent re-run of the D5 catalog-path test + the module suites touched (#40/#44/#45) via native git + executor.
- Re-run project.map `verify` + `render --check` (D2 changes the DEFAULT bootstrap surface): 0 stale on boot_read at HEAD; BOOT_PACKET <= 20,000 B with the root view.
- Cross-check: overlay `asserted_count` == a direct standing-catalog count (F1). doc-commit-gate green on the RETRIEVAL-PROTOCOL/doctrine diff. P0-1 `non_execution` untouched.
- N7 close-refold restamps map/+generated/ as the final close commit; regenerate BOTH monitors; re-mirror core-docs to the Project; re-push the GitHub mirror.

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)
_empty._
