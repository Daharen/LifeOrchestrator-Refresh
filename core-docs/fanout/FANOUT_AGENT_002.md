# FANOUT_AGENT_002 -- READY (i34 wave scoping)

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i34 (plan id `fo-34-45fcbd0d` once planned)
- **Lane:** CODING (CPU; GPU lane skipped this wave)
- **Worker id / label:** w2-workmem (`42-working-memory`, NEW module)
- **Module/area (exclusive):** `modules/42-working-memory/` ONLY (NEW module; skill `working.memory` 0.1.0)
- **GPU:** false
- **Docs:** `[]`

## Mission
Build the MEMORY_ARCHITECTURE **Tier 1** per-`task_id` **working-memory STORE** -- the seam A5 U3'
(`MEMORY_CONTRACT.md`) fully specified and reserved but did not build. This is the store that lets a deepening
task distinguish its OWN current intermediate state from stale earlier state (the mechanical cure for
"deteriorates on iterative prompts"), kept strictly out of long-term evidence + execution authority. NEW module
#42. Governs: `MEMORY_ARCHITECTURE.md` s4 (working type), s9-s10 (Tier 1); `MEMORY_CONTRACT.md` A4 (U3), A5 (U3');
`CONTEXT_PACKET_CONTRACT.md` i32/i33 (the `working_memory` packet region -- your CONSUMER is #40, slot 003, in
this wave's D-0077 cross-module smoke). Author a small `working_state/0.1` sub-contract (A5 U3' prefers it).

## Unit (the full worker prompt)
You are the #42 working-memory worker for i34 -- a BRAND-NEW module. Read `core-docs/START_HERE.md` +
`core-docs/CURRENT_STATE.md` (esp. Known failures) + `MEMORY_ARCHITECTURE.md` s4 + `MEMORY_CONTRACT.md` A5 U3' +
`CONTEXT_PACKET_CONTRACT.md` i32/i33 first; obey `SKILL_CONTRACT.md`. Follow #39 episode.record / #36
artifact.search as the module-shape + SQLite precedent. Do ONE unit in `modules/42-working-memory/` only;
`docs:[]`. A new module has NO skill.json yet -- create it (skill_id `working.memory`). Ship via `dev.ship`.

**SCOPE IN (new module `working.memory` 0.1.0 + a `working_state/0.1` sub-contract in `SCHEMA_NOTES.md`):**
1. **The `working` record + reserved store fields (A5 U3').** A per-`task_id` state record via the shared
   envelope (`record_kind = working`), CONTINUITY-authoritative (the recorded current state of THIS task, NOT
   world-truth, NOT execution authority): `content_role: working_state`, `can_instruct: false`, permissions live
   ONLY in a packet's `control_plane` (never here). Store fields: `working_state_id`, `task_id`, `state_version`,
   `parent_state_version`, `namespace_scope`, `grant_snapshot_ref`, `created_from_packet_id`, `content_hash`,
   `lifecycle_state` (`active | closed | archived`), `content_role: working_state`, `writer_authority`.
2. **Store semantics (freeze in the sub-contract, build now):** immutable versioned snapshots; **CAS on
   `parent_state_version`** at update (a stale-parent write fails closed); **exactly ONE active head per task**;
   explicit `fork`; a SEPARATE fixed working-memory budget (distinct from the evidence budget); a `closed` state
   is NOT ordinarily retrievable; `archive != evidence`; **PROMOTION creates a NEW derived long-term record** with
   provenance + validation (never re-labels the working record).
3. **Conjunctive isolation (A5 U3').** Access requires `task_id` AND current-namespace authorization -- task-
   isolation and namespace-isolation are DIFFERENT mechanisms; an operation never widens parent scope. Reuse #37's
   canonical `lib/namespace_policy.py` `ns_permitted` (imported READ-ONLY) for the namespace half -- do NOT
   re-implement the predicate (A5 risk-6).
4. **Ops (skill.json).** At least: `put_state` (append a new version under CAS -> new active head), `get_active_head`
   (by `task_id` + effective namespace, conjunctive), `fork`, `close`, `archive`, `list_by_task` (exact-`task_id`
   only), `promote` (emit a derived long-term record + provenance, return its ref). Deterministic; JSON envelope on
   stdout only (diagnostics to stderr).
5. **`search` REJECTS `working` by default (A5 U3').** Working records are retrievable ONLY by an exact-`task_id`
   op here -- NOT by ordinary long-term `search`. Provide/prove the rejection at THIS module's boundary (and note
   the requirement for #36 -- but do not modify #36; #36's own `search` working-rejection is slot 001's / already
   in the contract). "Excluded by default" is too weak: enforce it.

**SCOPE OUT:** NO packet assembly / no `working_memory` packet REGION rendering (that is #40, slot 003 -- you
expose the READ op it calls). NO promotion policy/triggers beyond the mechanical `promote` op (consolidation is
Tier 2). NO 9B/model. NO changes to #36/#37/#40 or any other module. Keep the store a SEPARATE store from #36's
searchable catalog (working memory must never enter the long-term retrieval pool).

**GATES.** Off-machine cloud gate FIRST -> `-Live` on the Windows executor -> `dev.ship`. Prove: CAS rejects a
stale-parent write; exactly one active head invariant holds under concurrent-ish writes; a closed/archived state is
not returned by `get_active_head`; conjunctive access denies a wrong-namespace caller fail-closed with no leakage;
`promote` yields a valid long-term derived record with `derives_from` provenance (never re-labeling). Double-run
byte-identity on canonical outputs (pwsh determinism traps -- CURRENT_STATE). Record every interpretation +
the `working_state/0.1` sub-contract in `modules/42-working-memory/SCHEMA_NOTES.md`. Report plainly if a seam is
impractical (D-0061).

## Rails
Standing rules: `core-docs/fanout/FANOUT_AGENT_TEMPLATE.md`. Acquire res.lease in gpu->git->doc order (git only
this wave); release on exit. ONE unit, module-exclusive, `docs:[]`. New module: OMIT skill_id/skill_dir in the
plan until skill.json exists; create it as part of the unit. Gate off-machine first, then `exec-job.sh devship`;
files reach the box via SendUserFile + device_commit_files; 0 orphaned llama-server/python. Report: `-Action
report -PlanId fo-34-45fcbd0d -WorkerId w2-workmem -State done` + a plain measured summary.

## Verification
- New module scaffolded (`Invoke-WorkingMemory.ps1` + `skill.json` + `tests/` + `SCHEMA_NOTES.md` with the
  `working_state/0.1` sub-contract), invocable via the Module 1 wrapper.
- CAS: a write on a stale `parent_state_version` FAILS CLOSED; a correct-parent write advances the single active head.
- One-active-head invariant proven; `fork` creates an explicit divergent head; `close`/`archive` remove a task
  from `get_active_head`.
- Conjunctive access: right `task_id` + wrong namespace -> fail-closed, no leakage; `ns_permitted` byte-identical
  to #37 canonical.
- Ordinary `search` semantics reject `record_kind = working`; only exact-`task_id` ops return working state.
- `promote` emits a NEW derived long-term record + `derives_from` provenance (working record NOT re-labeled).
- Suite green cloud + `-Live`; a fresh Verification-Console `run_module` item if runnable; 0 orphans.

## Report-back record
_(Orchestrator fills from `plans/fo-34-45fcbd0d/reports/` before archiving.)_
