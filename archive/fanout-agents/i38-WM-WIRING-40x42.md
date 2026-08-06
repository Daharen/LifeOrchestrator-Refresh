# FANOUT_AGENT_002 -- i38 wave (plan fo-38-2b1efe73)

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i38 (plan id `fo-38-2b1efe73`)
- **Lane:** CPU
- **Worker id / label:** `WM-WIRING-40x42-i38`
- **Module/area (exclusive):** `modules/40-context-compiler`
- **GPU:** false
- **Docs:** `[]`

## Mission
Hydrate the context packet's working_memory region from #42's per-task store (get_active_head) -- completing the channel the i37 router NAMED but left reserved. Read-only over the FROZEN #42; conjunctive task_id+namespace; state_version enters packet identity; the region is evidence-ineligible + can_instruct:false; a no-working-memory / no-task compile stays BYTE-IDENTICAL to 0.8.0. Governs: modules/42-working-memory/SCHEMA_NOTES.md (the get_active_head seam) + CONTEXT_PACKET_CONTRACT.md (s6 + the working_memory region) + MEMORY_CONTRACT.md (A5).

## Unit (the full worker prompt)
Dispatch a fresh Cowork session with the one folder grant (`C:\Users\just_\LifeOrchestrator-Refresh`) and execute the unit below. The EXACT `orchestrate.fanout`-emitted prompt (with the res.lease acquire/release commands) is delivered as a file and lives at `modules/30-orchestrate-fanout/runtime/artifacts/c7243036-624d-4819-b5dd-89bf3c024aa8/workers/worker-WM-WIRING-40x42-i38.prompt.md` -- if dispatched by prompt-paste, paste that file; the unit text here is the same mission.

WIRE the packet working_memory region to #42's per-task working-memory store in modules/40-context-compiler (skill context.compile, context_packet 0.8.0 -> 0.9.0). EXCLUSIVE to #40; docs:[]; CPU (no GPU); non_execution:true holds; READ-ONLY over #42.

BACKGROUND. The i37 router (#40 0.8.0) NAMED a working_memory channel as a routing target but left the packet's working_memory REGION reserved/empty. #42 working.memory (0.1.0, FROZEN this wave -- do NOT modify it) exposes get_active_head. This unit HYDRATES the region from #42, exactly as #42's SCHEMA_NOTES already designs the seam ("#40 consults get_active_head (conjunctively -- passing its effective_allowed_namespaces) to render the packet's working_memory region").

BUILD. When the compile is scoped to a task (task_id present) and the routing policy selects the working_memory channel, #40 consults #42.get_active_head(task_id, effective_allowed_namespaces) CONJUNCTIVELY (task_id AND namespace) and renders the returned MEMORY_CONTRACT s1 working-state envelope (record_kind=working) into the packet's working_memory region:
- CONJUNCTIVE ACCESS: pass #40's effective_allowed_namespaces; a cross-namespace / not-permitted task returns NOT-FOUND fail-closed, count-only, ZERO leakage (no existence oracle) -- exactly as #42's cross-ns test specifies (ns_permitted accept/reject via the ONE canonical implementation, imported not reimplemented).
- state_version ENTERS PACKET IDENTITY (CONTEXT_PACKET_CONTRACT s6): same task + corpus snapshot + grants + profile + routing policy + working state_version => identical packet_id; a new state_version => a new packet_id.
- The working_memory region is EVIDENCE-INELIGIBLE and can_instruct:false (MEMORY_CONTRACT A5): it renders in its own region (third), NEVER satisfies evidence[]/coverage, and carries no instruction authority. The store NEVER enters #36's searchable long-term pool (separate DB).
- Only the ACTIVE head hydrates (lifecycle_state=active); closed/archived heads are not retrievable (archive != evidence).

HARD SCOPE GUARD. A compile with NO working_memory channel selected (or no task_id) MUST stay BYTE-IDENTICAL to 0.8.0 -- the region stays reserved/empty exactly as today; the router's flat/legacy path and the frozen i35 public-port path are UNAFFECTED. This is ADDITIVE hydration ONLY: ZERO change to any frozen record/packet FIELD beyond populating the already-reserved working_memory region + adding working state_version to identity. Do NOT modify #42 (read-only), #36/#37/#43, or any core-doc.

GATES.
- Off-machine FIRST (cloud pwsh/python deterministic gate over a real #42 store + a real #36 tree, in the style of test_i35_public_port.py).
- A NEW gate test asserting: (a) a task-scoped compile with an active #42 head HYDRATES the working_memory region with that head's envelope (record_kind=working, can_instruct=false, rendered third, NOT in evidence[]); (b) CONJUNCTIVE ns -- a cross-namespace/not-permitted task returns not-found fail-closed with ZERO leakage + the region stays empty; (c) state_version is in packet_id (vary it -> packet_id changes; hold it -> identical; double-run byte-identity); (d) a no-working-memory / no-task compile is BYTE-IDENTICAL to 0.8.0; (e) working memory NEVER satisfies evidence coverage.
- REGRESSION green: the i34 smoke-i34.py (38/38) + the i35 public-port gate test_i35_public_port.py (32/32) + the i37 router stage-trace gate + existing #40 tests.
- Ship via exec-job.sh devship (skill context.compile; named files only; AST + tests FAIL-CLOSED). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.

REPORT (`-Action report ... -State done` + plain summary): the hydration path, the conjunctive-ns fail-closed proof, the state_version-in-identity proof, the byte-identical-no-wm proof, and confirmation working memory stays evidence-ineligible + can_instruct:false. Negative/partial results are first-class.

GOVERNING DOCS (read, do not edit): modules/42-working-memory/SCHEMA_NOTES.md (the get_active_head contract + the #40 hydration seam + the cross-ns fail-closed test) + core-docs/CONTEXT_PACKET_CONTRACT.md (s6 identity + the working_memory region + s9) + MEMORY_CONTRACT.md (A5 working-memory conjunctive scope + can_instruct:false + the canonical ns_permitted).

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release in reverse. No GPU this wave (CPU lane) -- take `git` for the commit only.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine FIRST, then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId fo-38-2b1efe73 -WorkerId <id> -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
NEW gate test: a task-scoped compile with an active #42 head HYDRATES the region (record_kind=working, can_instruct=false, rendered third, NOT in evidence[]); a cross-ns/not-permitted task -> not-found fail-closed, count-only, ZERO leakage + empty region; state_version is in packet_id (vary->changes, hold->identical, double-run byte-identity); a no-wm/no-task compile is BYTE-IDENTICAL to 0.8.0; working memory NEVER satisfies evidence. Regression: i34 smoke-i34.py 38/38 + i35 public-port 32/32 + the i37 router stage-trace gate + existing #40 tests.

## Report-back record (ORCHESTRATOR fills from `plans/fo-38-2b1efe73/reports/` before archiving)
_empty -- filled at fold._
