# FANOUT_AGENT_003 -- READY (i52: PCB-N5N6-i52)

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i52 (plan id `fo-52-db941ec2`)
- **Lane:** CODING (CPU)
- **Worker id / label:** PCB-N5N6-i52 -- modules/44 `project.map` 0.3.0 -> 0.4.0 (the D-0142/I51 fix mechanisms: N5 + N6)
- **Module/area (exclusive):** `modules/44-project-map/**` EXCEPT `map/`, `generated/`, `eval/` -- NEVER write those three (fold-owned; read `eval/results/*` as spec only). You DO ship `claims/i52-n6-canon-claims.json` (the fold ingests it).
- **GPU:** false
- **Docs:** `[]`
- **RECOMMENDED MODEL:** Opus 4.8 Extra (D-0114 elevate: gate-adjacent mechanism module; an i51 NO-GO on this surface makes rework the dominant cost)

## Mission (2-4 lines)
The i51 fresh gate returned NO-GO (D-0142): the quality floor tripped on canon coverage (every scored B constraint deduction = a fact the BOOT_PACKET does not carry, F3) and TOTAL missed because prose-governing docs are not query-granular (F1: the T1 answer lives in AUDIT_PIPELINE sections + design digests + a WORK_ORDER block, so the PCB arm paid whole-doc opens ON TOP of its boot layer). This unit closes F1 + F3's packet half so the PCB can carry its canon and serve prose at query granularity. Spec: `modules/44-project-map/eval/results/I51_RESULTS.md` (s5 findings + s7 N5/N6) + the i51 A/B pack ledgers; Nicholas directive = fix the i51 issues, move toward GO.

## Unit (the full worker prompt)
**The verbatim authority is the emitted prompt file** (over this slot's 8 KB budget -- summary + pointer, the i40/i48/i49 pattern):
`modules/30-orchestrate-fanout/runtime/artifacts/91ec8e21-cea7-47ba-92e5-b49e24c22d46/workers/worker-PCB-N5N6-i52.prompt.md`
**READ THAT FILE FIRST AND EXECUTE IT.** Condensed shape:
- **N5 (kills F1):** extend `section:` (i49 module-SCHEMA_NOTES semantics preserved byte-identical) to serve ONE named heading section from any mapped `doc:` entity AND from files reachable via a mapped entity's typed `deeper[]` pointer (min kinds work-order|research|readme) -- bounded, provenance-marked, repo-READ-ONLY, existing error codes (DANGLING_REF / documented missing-heading code). Design + document the selector. Add `card:<id>`: ONE rendered L1 card, content-matching the plane file, bounded. Verb table (single-source, N3) gains both; equality test stays green.
- **N6 (kills F3's packet half):** AUTHOR `claims/i52-n6-canon-claims.json` adding ops: canon entities: D-0064 at FULL STRENGTH (human live-GUI confirm BEFORE done -- no softening), K5 doc budgets + fail-closed commit gate, mandate-02 SUNSET state (SEALED_CHECK_47 armed i>=54; M2-A gate + PB triggers + cadence headers + monitor survive), NON-OPTIONAL red-team gate for audit increments. RENDER: new canon lines in OPERATIONS (degrades LAST) + `open_rulings[]` now rendered into the packet OVERLAY (the K10 drop: the w08 rider was in state.json, absent from the packet). CONTENT TESTS string-assert every canon item (i48 CD-1 pattern) + a negative that FAILS on softened D-0064 phrasing; fixture overlay gains an open_ruling.
- **ACCEPTANCE (mechanical, fixtures + -Live, verbatim outputs + byte counts):** (a) the i51 T1 derivation cluster as bounded queries <= 8,000 B each -- AUDIT_PIPELINE cadence-header / s5 / s6 sections (vs 20,156 B whole-doc), the i45-lrap-design honesty-map section (vs 9,811 B), the w08 WORK_ORDER follow-ons block (vs 10,209 B); T1-style probe with NO whole-doc open; (b) `card:module:40/context.compiler` + one widget card <= 6,000 B each, content-matching the plane file (vs 31,488 B); (c) golden packet carries EVERY N6 canon assertion + >= 1 rendered open_ruling; (d) 0.3.0 byte-identity on unchanged queries; (e) BOOT_PACKET fixture <= 20,000 B HARD -- committed render is 16,943 B, headroom ~3.0 KB is REAL but tight; ladder positions documented; OPERATIONS degrades LAST inviolable.
- **PRESERVE** all WO/0.3.0 invariants; claims file passes standalone validation + fixture-map ingest (NEVER ingest into real map/). skill.json 0.4.0 + purpose addendum. Cloud pwsh FIRST, then -Live via exec-job.sh. NO real map/ generated/ eval/ writes.
- **SHIP** via `exec-job.sh devship` (named files ONLY: project_map.py, skill.json, SCHEMA_NOTES.md, README.md if touched, schema/*.json if extended, claims/i52-n6-canon-claims.json, tests/** + fixtures/** changed; trailers; NATIVE-git HEAD verify D-0072; 0 orphans) then `-Action report -PlanId fo-52-db941ec2 -WorkerId PCB-N5N6-i52 -State done`.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit (this unit: `git` only, at ship time).
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]`.
- Gate off-machine FIRST, then ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-52-db941ec2 -WorkerId PCB-N5N6-i52 -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
Cloud + -Live suite counts; the acceptance-replay outputs with exact byte counts vs the i51 baselines (20,156 / 9,811 / 10,209 / 31,488); the BOOT_PACKET fixture total + ladder proof; the canon-assertion test list; every closed-set/schema extension with its documentation pointers; Verification Console `run_module` item = `project.map` selftest. The orchestrator at fold (N7): ingests the N6 claims, re-authors the overlay (iteration 52), re-harvests at HEAD, validate 0, render, INDEPENDENT acceptance replays + a fresh cloud-subagent canon probe (HITs K5/K6/K9/K10 unsoftened, no tree corroboration), then commits map+generated as the FINAL close commit. N8 re-run re-freeze is staged for Nicholas ratification this wave; NO fresh gate before N5-N7 land + N8 is ratified.

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)
_pending -- wave in flight._
