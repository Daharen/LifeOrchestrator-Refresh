# FANOUT_AGENT_001 -- FILLED (i35 Lane A)

## Header
- **Slot:** FANOUT_AGENT_001
- **Status:** FILLED
- **Wave / iteration:** i35 -- plan `fo-35-0a5bf334`
- **Lane:** CPU (GPU lane SKIPPED this wave -- 0 GPU workers)
- **Worker id / label:** HIERARCHY-PORT-i35
- **Module/area (exclusive):** modules/40-context-compiler (skill `context.compile` 0.6.0 -> 0.7.0)
- **GPU:** false
- **Docs:** `[]`

## Mission
WIRE the REAL hierarchy_port into #40's PUBLIC `-Retriever artifact_search` path so the i34 Tier-1
shortlist-and-descend hierarchy runs end-to-end for real (today it runs ONLY via an INJECTED port). CONSUMER of
#36's shipped ops (READ-ONLY import); a flat/non-descend/unscoped compile stays BYTE-IDENTICAL to 0.6.

## Unit (the full worker prompt)
**Your authoritative full brief is the plan-emitted prompt on disk -- READ IT IN FULL and execute EXACTLY that:**
`modules/30-orchestrate-fanout/runtime/artifacts/f16580a4-caa4-41e3-adbd-7a42faebf8ae/workers/worker-HIERARCHY-PORT-i35.prompt.md`
It embeds: the READ-FIRST gotcha corpus (CURRENT_STATE 'Known failures' in full), the governing contracts
(CONTEXT_PACKET_CONTRACT i34 V1-V5, MEMORY_CONTRACT A6, the i34 hierarchy design + red-team digest), SCOPE IN/OUT,
ACCEPTANCE (a)-(f), GATES, and the exact res.lease (git) acquire/release + `-Action report` lines for plan
`fo-35-0a5bf334`.

Compressed summary (the disk brief governs on any conflict): construct a real `ArtifactSearchHierarchyPort` over
#36's `Catalog(db_path)` / `shortlist` / `descend` / `prune_verdict` (resolved-portable import, the i31/i32/i33
pattern); wire it so a scoped DESCEND-class compile on `-Retriever artifact_search` runs `run_hierarchy_plan` for
real (no injected port needed). SEAM 1 = hydrate descend's BARE `leaf_members` (record_version_id) to evidence via
#36's shipped `search`/`export-chunk-texts` filters (provenance MUST reconstruct to source); STOP + report a fold
reconciliation if #36 cannot serve it. SEAM 2 = compose the no-false-negative prune certificate from REAL per-term
`prune_verdict` (a bounded descriptor / stale synopsis NEVER prunes -> else expand / flat-fallback /
needs_expansion|abstain). Keep V2/V3/V4/V5 + P0-1/P0-3/P0-4/P1-5/A2 + i32/i33 closure + non_execution green.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order (this lane: git ONLY, around the dev.ship commit); release on exit.
- Do ONE unit; never touch modules/areas outside the exclusive claim (#40 only; import #36 READ-ONLY); `docs:[]`.
- Gate off-machine FIRST, then ship via `dev.ship`; VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-35-0a5bf334 -WorkerId HIERARCHY-PORT-i35 -State done` + a plain measured summary.

## Verification
Per ACCEPTANCE (a)-(f) in the disk brief: real port over #36; public artifact_search + descend-class + scoped runs
the plan (non-descend/flat byte-identical to 0.6); SEAM 1 hydration reconstructs to source; SEAM 2 prune-cert from
real `prune_verdict` (bounded / stale never prunes); V2-V5 + shipped invariants green; the gate test passes on a
REAL #36 tree; all shipped 0.6 tests green. Off-machine FIRST, then -Live. SCHEMA_NOTES updated for the D-0077 fold.