# FANOUT_AGENT_003 -- FILLED (i36, plan fo-36-1a676e4b)

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** FILLED
- **Wave / iteration:** iteration 36 -- plan `fo-36-1a676e4b` (Tier-1 ACCEPTANCE wave, 3-lane CPU, GPU skipped)
- **Lane:** CODING lane (CPU) -- NEW widgets/05-provenance-map
- **Worker id / label:** `WIDGET05-PROVENANCE-MAP-i36` -- NEW read-only native WinForms construction map (D-0101 audit tier A1 / PB-4)
- **Module/area (exclusive):** `widgets/05-provenance-map/` ONLY (brand-new widget -> NO skill.json; OMIT skill_id/skill_dir)
- **GPU:** false
- **Docs:** `[]`

## Mission
Build Widget 05 'Provenance Map' -- a read-only native WinForms viewer joining what the process ALREADY maintains (MODULE_ROADMAP status + CURRENT_STATE tests/Known-failures + DECISION_LOG_INDEX + git dev.ship trailers + runtime/plans reports + Verification-Console verdicts) into: what EXISTS (module/widget->version->iteration->D-entry->commit->files->verification), new-since-N, verification-per-unit, planned-but-unbuilt. Reads canonical on-disk docs + read-only git ONLY -- ZERO new doc-upkeep, STRICTLY read-only. The audit funnel's top altitude. NON-DISPLACING (Lanes A/B keep priority). Governing: `research/2026-08-05-interpretability-audit-surface-scoping.md` s4 + `-audit-pipeline-target.md` s2.9/s4-A1.

## Unit (the full worker prompt)
**The FULL worker prompt -- mission + rails + the EXACT res.lease acquire/release + `-Action report` command lines bound to plan `fo-36-1a676e4b` -- is the emitted copy at**
`modules/30-orchestrate-fanout/runtime/artifacts/e2415cac-1e7d-4d68-9104-4c57a9ede05c/workers/worker-WIDGET05-PROVENANCE-MAP-i36.prompt.md`
**(also delivered to Nicholas as a file). Dispatch: start a FRESH Cowork session, hand it that prompt file (or say "read that file and execute it"), grant the ONE folder `C:\Users\just_\LifeOrchestrator-Refresh`. READ + execute exactly that unit.**

Scope (compact -- the emitted prompt is authoritative):
- A read-only join layer over the canonical docs + read-only git trailers + runtime/plans reports + Verification-Console verdicts; DETERMINISTIC parses with GRACEFUL DEGRADATION (a malformed/over-budget hot doc -> a VISIBLE FLAG, auto-surfacing PB-3 debt).
- Views: what-exists / new-since-iteration-N / verification-per-unit / planned-but-unbuilt; a one-click answer to 'what did iteration N build and under which decision?'
- Native WinForms + launch.bat (D-0038); the 'new since last visit' diff persisted ONLY in widgets/05-provenance-map/runtime/. STRICTLY read-only (no doc/git writes, no executor jobs, no model calls).
- SelfTests: headless mock gate + STA SelfTests incl. SELFTEST_LAYOUT_OK (off-screen layout guard) + a read-only assertion.

Acceptance (compact):
(a) renders from canonical docs + read-only git, ZERO doc-upkeep; (b) graceful degradation flags a malformed/over-budget doc; (c) 'new since' diff only in its own runtime dir; (d) STRICTLY read-only (a SelfTest asserts it); (e) one-click 'what did iteration N build + which decision'; (f) native launch.bat; mock + -Live STA SelfTests GREEN; the human live-GUI confirm FLAGGED as the closing step (D-0064).

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit. CPU lane -> NO gpu lease; take `git` ONLY around the dev.ship commit.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine FIRST, then ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-36-1a676e4b -WorkerId <id> -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
Cloud mock gate + -Live STA SelfTests (SELFTEST_LAYOUT_OK + read-only assertion) at fold; a brand-new widget (no skill.json). The rendered UI is NOT 'done' until Nicholas's human LIVE-GUI confirm (D-0064) -- the worker FLAGS it, the orchestrator carries it as the closing follow-on. Assert NO writes outside widgets/05-provenance-map/.

## Report-back record (ORCHESTRATOR fills from `plans/fo-36-1a676e4b/reports/` before archiving)
_empty._
