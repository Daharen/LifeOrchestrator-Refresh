# FANOUT_AGENT_003 -- READY (i48: PCB-CD-i48)

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i48 (plan id `fo-48-3d3a4e1b`)
- **Lane:** CODING (CPU)
- **Worker id / label:** PCB-CD-i48 -- modules/44 `project.map` 0.1.0 -> 0.2.0 (the D-0133 CD-1 + CD-3 closures)
- **Module/area (exclusive):** `modules/44-project-map/**` EXCEPT `map/`, `generated/`, `eval/` -- NEVER write those three (map+generated are orchestrator-re-rendered at fold; eval/ is orchestrator-owned, read `eval/results/*` as spec only)
- **GPU:** false
- **Docs:** `[]`
- **RECOMMENDED MODEL:** Opus 4.8 Extra (D-0114 elevate: the mechanism under the ACTIVE migration gate; rework forces another human-dispatched eval round)

## Mission (2-4 lines)
The i47 legacy-vs-PCB migration gate returned **CONDITIONAL** (D-0133): quality PASS, efficiency VOID -- the PCB-booted agent had to open the legacy handoff for wave mechanics (RT2-F9), and three map query probes failed/flagged. This unit closes the two CODE deficiencies -- **CD-1** (boot-surface operational canon) + **CD-3** (query surface) -- so the i48 CONDITIONAL re-check can run. Spec: `modules/44-project-map/eval/results/I47_RESULTS.md` s5 (D-0133-committed).

## Unit (the full worker prompt)
**The verbatim authority is the emitted prompt file** (11,167 B -- over this slot's 8 KB budget, so this slot carries the summary + pointer, the i40 Lane-A pattern):
`modules/30-orchestrate-fanout/runtime/artifacts/528cf631-5033-46e3-bf1d-ccdd357efb9e/workers/worker-PCB-CD-i48.prompt.md`
**READ THAT FILE FIRST AND EXECUTE IT.** Condensed shape:
- **CD-1:** a new OPERATIONS section in the generated BOOT_PACKET, rendered ONLY from validated map state via NEW `ops:` canon entities authored in `claims/i48-ops-canon-claims.json` (`lifeorch.map_claims/0.1`; `by:"cd-lane-i48"`; every field evidence-pointed): wave clamps (<=1 GPU worker HARD; MaxParallel 3 validated ceiling; workers `docs:[]`; only the GPU lane touches models.json), lease order gpu->git->doc, ship-verify canon (dev.ship FAIL-CLOSED; NATIVE-git HEAD verify, D-0072; never `git add -A`; executor-only git writes; doc-gate D-0117), orphan discipline (DETACHED + reaped; 0 UNMANAGED; D-0055/56), the D-0077 fold-smoke rule. Every rendered line pointer-backed; BOOT_PACKET <=20,000 B HARD; documented degrade-LAST ladder position + fixture.
- **CD-3:** short-form/alias id resolution (`ns:NN` + `#NN`) on `entity:/edges:/redges:/evidence:/deeper:` (full-id behavior byte-identical; unresolvable -> the EXISTING DANGLING_REF; NO new error codes, NO new query names); provenance-at-SHA hygiene: `evidence:` marks each source resolvable-at-harvest vs beyond-tree from harvest facts alone (no git calls in the worker, RT1-F21); currency surfaces state BOTH the map-state commit and the harvest/tree commit.
- **ACCEPTANCE (mechanical; fixtures + -Live on the REAL committed map/):** `edges:module:42|30|37` non-empty and identical to their full-id forms; `entity:widget:08` resolves (not DANGLING_REF); the beyond-tree evidence-marking fixture; OPERATIONS content assertions (clamps, native-git verify, never-add-A, lease order, 0 orphans; pointer-backed lines).
- **PRESERVE** every 0.1.0 WORK_ORDER invariant (envelopes, closed error table, canonical bytes, determinism double-run + shuffle, gates, drafts runtime-only, parse_budgets import, stdlib py3.10); skill.json -> 0.2.0 + purpose addendum. Full suite + new fixtures: cloud pwsh FIRST, then -Live. DO NOT re-render the real `generated/` or ingest claims into the real `map/` (fold-owned).
- **SHIP** via `exec-job.sh devship`, named files ONLY (NOTHING under map/ generated/ eval/); VERIFY the real HEAD via native git; assert 0 UNMANAGED orphans; then `-Action report -PlanId fo-48-3d3a4e1b -WorkerId PCB-CD-i48 -State done` with the measured summary the prompt file specifies.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit (this unit: `git` only, at ship time).
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]`.
- Gate off-machine FIRST, then ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-48-3d3a4e1b -WorkerId PCB-CD-i48 -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
Cloud suite + -Live suite counts; the four acceptance-probe outputs verbatim against the real map; OPERATIONS section byte size + golden BOOT_PACKET total + the ladder proof; claims entity/edge counts + at_commit; Verification Console `run_module` item = `project.map` selftest. The orchestrator independently re-runs the probes + content assertions at fold (i46-style re-verify) before the CD-1 dry-run + CD-2 efficiency re-check are staged with Nicholas.

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)
_pending._
