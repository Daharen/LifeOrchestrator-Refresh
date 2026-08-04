# SCHEMA_NOTES -- working.memory (module 42) + the `working_state/0.1` sub-contract

**Module 42 `working.memory` 0.1.0 (i34, plan fo-34-45fcbd0d, D-0090/D-0096/D-0077).** The Tier-1 per-`task_id`
WORKING-MEMORY STORE that `MEMORY_CONTRACT.md` Amendment A5 (U3') reserved but did not build. This file is the
NORMATIVE record of every contract interpretation for the D-0077 cross-module fold (consumer = #40, slot 003).

## 1. `working_state/0.1` sub-contract (A5 U3' prefers a small sub-contract)

A working state is an **immutable versioned snapshot** of ONE task's evolving intermediate state. The store is a
SQLite DB (`working_state` table). Each row is a version; `record_version_id` is the immutable PK,
`working_state_id` is the stable LOGICAL id (repeats across a task branch's versions).

Reserved store fields (A5 U3'), each present on every version + surfaced on the `working` envelope:
`working_state_id`, `task_id`, `state_version` (monotonic int per task, from 1), `parent_state_version`
(nullable; the CAS token), `namespace_scope`, `grant_snapshot_ref`, `created_from_packet_id`, `content_hash`
(`sha256:` of the canonical body), `lifecycle_state` (`active | closed | archived`), `content_role`
(`working_state`), `writer_authority`. Plus `forked_from` (the source head `record_version_id` for a fork).

Frozen store semantics (built now):

- **Immutable versioned snapshots.** A state is never mutated in place; a change appends a NEW version. Both the
  old and new versions are retained.
- **CAS on `parent_state_version`.** `put_state` requires `parent_state_version` == the current active head's
  `state_version` (null/0 for a task's v1). A mismatch (stale parent) FAILS CLOSED with `cas_conflict` and writes
  nothing. The advance (demote old head, insert new head) is one `BEGIN IMMEDIATE` transaction.
- **Exactly ONE active head per `task_id`.** Enforced by a partial UNIQUE index
  (`ux_ws_head ON working_state(task_id) WHERE is_active_head = 1`) + the transactional demote-then-insert.
- **Explicit `fork`.** `fork(source_task_id, new_task_id)` creates `new_task_id`'s v1 as a snapshot of the
  source's active head, `forked_from` = the source head `record_version_id`, namespace INHERITED (a fork never
  widens scope). One active head per task_id still holds (the new branch is a distinct task_id).
- **A SEPARATE fixed working-memory budget.** A per-record body cap (`BODY_BUDGET_BYTES = 65536`), distinct from
  the evidence/packet budget; an over-budget body FAILS CLOSED (`working_budget_exceeded`).
- **`closed`/`archived` not ordinarily retrievable.** `get_active_head` returns a head ONLY when its
  `lifecycle_state = active`; `close`/`archive` demote the head out of `get_active_head`. `archive != evidence`.
- **PROMOTION never re-labels.** `promote` emits a NEW derived long-term record `record_kind = summary`
  (`body_schema lifeorch.summary/0.1`, `attrs.summary_type = working_state_promotion`, `provenance_mode =
  derived_record`, a `derives_from` edge to the working `record_version_id`); the working record is left
  untouched (still `record_kind = working`, still retrievable by task). This is the promote/demote lifecycle: a
  working state becomes a long-term summary through a NEW record + provenance, NOT by re-labeling.

## 2. Conjunctive isolation (A5 U3') -- task_id AND namespace, DIFFERENT mechanisms

Every access-controlled op (`put_state`, `get_active_head`, `list_by_task`, `fork`, `close`, `archive`,
`promote`) requires BOTH: (a) the exact `task_id` (task-isolation), AND (b) namespace authorization
(namespace-isolation). The two are independent; an op NEVER widens parent scope.

The namespace half reuses **#37's ONE canonical predicate** `namespace_policy.ns_permitted` (A5 risk-6),
imported READ-ONLY by a resolved portable path (`_load_ns_policy`: a caller `ns_policy_path`, else a sibling
`lib/` [test only], else `../37-retrieval-eval/lib/namespace_policy.py`). It is NEVER re-implemented. The
effective set is `effective_allowed_namespaces(request, grant) = intersection(request, grant)` (`request` =
`allowed_namespaces`, `grant` = `permission_grants`); an empty request/grant/intersection permits nothing
(fail-closed). A cross-namespace access is fail-closed + **sanitized**: only an integer
`namespace_violation_count` + a `namespace_closure_violated` flag surface to the caller; the identifying detail
(namespace, ids, paths) goes to a PRIVILEGED local `ns-security-log.jsonl` and NEVER to a caller/record (via
#37's `NamespaceRejectionPolicy`). `ns_policy_id = ns_closed_v1`, `ns_policy_version = 1.0.0` are stamped on
every summary for the byte-identity the fold asserts against #36/#40.

## 3. Ordinary `search` REJECTS `record_kind = working` (A5 U3')

Working records are retrievable ONLY by an exact-`task_id` op (`get_active_head` / `list_by_task`). The `search`
op is the proof of the boundary: it ALWAYS returns zero results with `working_excluded_from_search = true`.
"Excluded by default" is too weak -- the store never exposes a working record through a search interface.

## 4. The `working` record envelope (record_kind=working) -- for #40 (the consumer)

`get_active_head` returns the head's MEMORY_CONTRACT s1 envelope (`state.json`): `record_kind = working`,
`content_role = "working_state"`, `can_instruct = false`, `provenance_mode = derived_record`, `status =
"current"`, `authority_level = "working"`, the A5 store fields (section 1), and the opaque `body`. #40 (slot 003)
consults `get_active_head` (conjunctively -- passing its `effective_allowed_namespaces`) to render the packet's
**`working_memory` region** (CONTEXT_PACKET_CONTRACT i33 U3'): the region is continuity-authoritative, third in
render order (`control_plane -> task_input -> working_memory -> evidence`), NEVER control-plane authority, and
`state_version` enters packet identity. The store never enters #36's searchable long-term pool (separate DB).

## 5. Determinism (the double-run byte-identity gate)

Every emitted id/hash is a pure function of FIXED content: `working_state_id = ws_<24hex(sha256(task_id,
namespace_scope))>`, `record_version_id = wsv_<24hex(sha256(ws_id, state_version, canonical body))>`,
`content_hash = sha256:<...>`, promoted `sum_`/`sumv_` likewise. `state_version` is a monotonic int per task
(deterministic given the op sequence). No wall-clock / uuid / absolute path feeds any id/hash. Canonical record
artifacts (`state.json` / `records.json` / `promoted.json`) are `sort_keys` + `ensure_ascii` + compact + one
trailing LF + UTF-8 no BOM, and byte-identical on a re-run of the same op sequence on a fresh store; the
`records_digest` (sha256 over the sorted emitted records) is the single cross-env pin. `worker-summary.json`
carries a diagnostic `ns_policy_path` (absolute) and is NOT a canonical record.

## 6. Non-goals (this wave)

No packet assembly / no `working_memory` region rendering (that is #40). No promotion POLICY / triggers /
consolidation (Tier 2). No embeddings, no model, no network. No changes to #36/#37/#40 (import #37's
`namespace_policy` READ-ONLY only). The store is SEPARATE from #36's catalog (working memory never enters the
long-term retrieval pool).

## 7. Fold hooks (D-0077, consumer #40)

At fold the orchestrator drives: `working.memory put_state` (a task head under ns-A) -> `#40 compile` for that
task under an ns-A grant -> assert the `working_memory` region carries the head (conjunctive access passed),
renders third, `can_instruct=false`, and `state_version` is in `packet_id`; and a cross-namespace (ns-B) compile
-> `get_active_head` returns not-found (fail-closed, count only, zero leakage). `ns_permitted` accept/reject is
byte-identical to #36/#37/#40 (the same imported predicate).
