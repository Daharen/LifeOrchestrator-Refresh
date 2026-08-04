# WORK_ORDER -- module 42 working.memory (i34 Lane B, plan fo-34-45fcbd0d)

**Status:** SHIPPED 0.1.0 (i34). **Brief:** `core-docs/fanout/FANOUT_AGENT_002.md`. **Contracts:**
`MEMORY_CONTRACT.md` A5 (U3'), `CONTEXT_PACKET_CONTRACT.md` i32/i33 (U3'), `MEMORY_ARCHITECTURE.md` s4/s9/s10.

## Goal
Build the per-`task_id` WORKING-MEMORY STORE A5 U3' reserved but did not build (Tier 1). A new module #42; the
PRODUCER half whose `get_active_head` read op the compiler #40 (slot 003) consumes for the packet
`working_memory` region (D-0077 fold).

## Delivered
- `working_memory.py` -- deterministic stdlib-only Python worker (SQLite store): the `working` record envelope +
  the reserved A5 store fields; ops put_state / get_active_head / list_by_task / fork / close / archive /
  promote / search; CAS on `parent_state_version`; exactly one active head per task (partial UNIQUE index +
  `BEGIN IMMEDIATE`); a separate working-memory body budget; conjunctive isolation reusing #37's canonical
  `ns_permitted` (imported READ-ONLY) with #37's sanitized `NamespaceRejectionPolicy`; promotion -> a NEW derived
  `summary` record (never re-labels); search rejects `record_kind=working`.
- `Invoke-WorkingMemory.ps1` -- thin contract wrapper (persistent `-StorePath`; `lifeorch.skill.result/0.1`).
- `skill.json` (0.1.0, contract 0.2), `SCHEMA_NOTES.md` (the `working_state/0.1` sub-contract + every
  interpretation for the fold), `README.md`, `examples/`, `tests/`.

## Verification
- `tests/test_working_memory.py` (off-machine gate): 30/30 -- CAS fail-closed, one-active-head, immutable
  versions, fork, close/archive removal, conjunctive fail-closed + sanitized (count only, no leakage), search
  rejection, promote non-relabel + derives_from, double-run byte-identity, `ns_permitted` parity with #37.
- `tests/Invoke-WorkingMemoryTests.ps1` (-Live / dev.ship): the Python gate + pwsh skill-level invocations
  (persistent store, CAS, conjunctive fail-closed, search rejection, promote, close).

## Non-goals (later)
Packet assembly / the `working_memory` region rendering (#40). Promotion POLICY / triggers / consolidation
(Tier 2). Embeddings, model use, network. No changes to #36/#37/#40 (import #37's `namespace_policy` READ-ONLY).
