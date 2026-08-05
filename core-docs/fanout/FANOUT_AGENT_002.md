# FANOUT_AGENT_002 -- FILLED (i36, plan fo-36-1a676e4b)

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** FILLED
- **Wave / iteration:** iteration 36 -- plan `fo-36-1a676e4b` (Tier-1 ACCEPTANCE wave, 3-lane CPU, GPU skipped)
- **Lane:** CPU lane -- artifact.search #36
- **Worker id / label:** `GET-RECORD-BY-RVID-i36` -- 0.5.0->0.6.0: add a clean by-rvid get-record READ op
- **Module/area (exclusive):** `modules/36-artifact-search/` ONLY
- **GPU:** false
- **Docs:** `[]`

## Mission
Close i35 Lane A's FOLD RECONCILIATION (D-0100): #36 has no by-record_version_id body-fetch op, so #40's leaf hydration reads the Catalog `records` table directly. Add the clean, ADDITIVE, READ-ONLY `get-record` op returning a record's full envelope + evidence body by rvid -- so a future i37 #40 change can stop reaching into #36's internals. READ-ONLY, deterministic, CPU-only, NO model, NO migration (schema stays 5). Governing: `MEMORY_CONTRACT.md` A5 (U1' namespace closure; U3' working-kind) + A6.

## Unit (the full worker prompt)
**The FULL worker prompt -- mission + rails + the EXACT res.lease acquire/release + `-Action report` command lines bound to plan `fo-36-1a676e4b` -- is the emitted copy at**
`modules/30-orchestrate-fanout/runtime/artifacts/e2415cac-1e7d-4d68-9104-4c57a9ede05c/workers/worker-GET-RECORD-BY-RVID-i36.prompt.md`
**(also delivered to Nicholas as a file). Dispatch: start a FRESH Cowork session, hand it that prompt file (or say "read that file and execute it"), grant the ONE folder `C:\Users\just_\LifeOrchestrator-Refresh`. READ + execute exactly that unit.**

Scope (compact -- the emitted prompt is authoritative):
- New `get-record`: rvid(s) (`-TargetId` or rvids[] via InputsJson) + effective_allowed_namespaces (caller-supplied CLOSED set; absent=unscoped, explicit-empty=zero) -> full s1 envelope + evidence body (text, source_span, content_hash, chunk_content_hash, source/path, namespace, authority, status/currentness, valid_from/to, section_path/heading, provenance_mode) reusing the shipped provenance derivation.
- Provenance holds (content_hash==source sha256; span reproduces bytes).
- A5 closure: a foreign/out-of-scope rvid FAILS CLOSED count-only, NO identifying metadata (detail -> privileged security_log); a leak aborts; record_kind=working rejected unless CONJUNCTIVELY task_id+namespace scoped.
- Version-exact by default; optional current_only documented; deterministic, envelope-only; NO writes/migration.

Acceptance (compact):
(a) get-record returns the envelope+evidence for #40 hydration; (b) provenance holds; (c) foreign rvid fails closed count-only, working-kind conjunctive-scoped; (d) version-exact default, no migration (schema 5); (e) shipped 0.5.0 tests GREEN + byte-identical existing paths; (f) skill.json/args_spec/output updated, 0.5.0->0.6.0.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit. CPU lane -> NO gpu lease; take `git` ONLY around the dev.ship commit.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine FIRST, then ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-36-1a676e4b -WorkerId <id> -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
The orchestrator smokes get-record over a real catalog at fold (rvid -> evidence reconstructs to source; a foreign rvid returns count-only). NO in-wave consumer (#40 adopts it in i37), so no producer/consumer cross-module smoke binds this lane -- its own gate test + the fold smoke suffice. If a needed field is genuinely unavailable without a schema change -> STOP + report (do NOT migrate).

## Report-back record (ORCHESTRATOR fills from `plans/fo-36-1a676e4b/reports/` before archiving)
_empty._
