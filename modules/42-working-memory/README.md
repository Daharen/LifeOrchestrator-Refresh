# Module 42 -- working.memory (Working Memory Store)

The MEMORY_ARCHITECTURE **Tier 1** per-`task_id` working-memory store (i34, `working.memory` 0.1.0). It holds a
task's evolving intermediate STATE across its iterative turns so a deepening task distinguishes its OWN current
state from stale earlier state -- the mechanical cure for iterative-prompt deterioration -- kept STRICTLY out of
long-term evidence and execution authority.

A `working` record (`lifeorch.memory_record/0.1`, `record_kind=working`) is **continuity-authoritative**:
`content_role=working_state`, `can_instruct=false`; permissions live ONLY in a packet's `control_plane`, never
here. The store is separate from #36's searchable catalog (working memory never enters the long-term pool).

**Ops:** `put_state` (append an immutable version as the single active head, CAS on `parent_state_version`),
`get_active_head`, `list_by_task`, `fork`, `close`, `archive`, `promote` (emit a NEW derived long-term `summary`
record; never re-label the working record), `search` (proves ordinary search rejects `record_kind=working`).

**Conjunctive isolation (A5 U3'):** every op requires the exact `task_id` AND namespace authorization; the
namespace half reuses #37's ONE canonical `ns_permitted` (imported READ-ONLY). A cross-namespace access is
fail-closed + sanitized (a violation COUNT only; detail -> a privileged local log).

Thin pwsh wrapper (`Invoke-WorkingMemory.ps1`) over a deterministic stdlib-only Python worker
(`working_memory.py`, SQLite). CPU-only, no model, no network. Contract v0.2. Governing:
`MEMORY_CONTRACT.md` A5, `CONTEXT_PACKET_CONTRACT.md` i33, `MEMORY_ARCHITECTURE.md` s4/s10. Interpretations +
the `working_state/0.1` sub-contract: `SCHEMA_NOTES.md`. Tests: `tests/Invoke-WorkingMemoryTests.ps1` (+ the
Python gate `tests/test_working_memory.py`). Examples: `examples/`.

The context compiler #40 (slot 003) consults `get_active_head` to render the packet `working_memory` region.
