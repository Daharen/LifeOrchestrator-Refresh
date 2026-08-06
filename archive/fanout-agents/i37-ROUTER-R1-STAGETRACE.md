# FANOUT_AGENT_002 -- ROUTER-R1-STAGETRACE-i37

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i37 (plan id `fo-37-9995475a`)
- **Lane:** CPU (Lane B)
- **Worker id / label:** `ROUTER-R1-STAGETRACE-i37`
- **Module/area (exclusive):** modules/40-context-compiler (skill context.compile) -- 0.7.0 -> 0.8.0
- **GPU:** false
- **Docs:** `[]`

## Mission
Realize the multi-channel query ROUTER in #40 (context.compile 0.7.0->0.8.0) and, per R-1 (D-0101/D-0103), make it BORN INSTRUMENTED with the deterministic integer-only stage-trace. Worth a wave slot: the router is the last un-routed retrieval seam and R-1 must land at router birth (retrofitting a shipped router contract is expensive). Governed by `core-docs/CONTEXT_PACKET_CONTRACT.md` (s6/s7 + the NEW s9 R-1 amendment).

## Unit (the full worker prompt)
REALIZE the multi-channel query ROUTER in modules/40-context-compiler (skill `context.compile`, context_packet 0.7.0 -> 0.8.0). EXCLUSIVE to #40; docs:[]; CPU (no GPU); non_execution:true holds; read-only retrieval.

BACKGROUND. Today `query_class` is a STUB: query_class/temporal_intent are already split + versioned and DESCEND_QUERY_CLASSES is defined (i32/i33/i34), but nothing routes on them. This unit makes routing REAL and -- per R-1 (D-0101/D-0103) -- BORN INSTRUMENTED.

BUILD (two coupled parts):
1. A deterministic multi-channel ROUTER. From the normalized query + resolved query_class + temporal_intent + allowed_namespaces, select which retrieval channels/paths run and in what order under a VERSIONED routing policy (`routing_policy_id` + `policy_version`). Channels are the ones #40 already reaches: lexical (FTS), the hierarchy shortlist-and-descend port, and the indexed #36-flat path; a `working_memory` channel MAY be NAMED as a routing target but MUST NOT be hydrated (that region stays reserved/empty -- the #40<->#42 wiring is a separate i38 unit). Deterministic, integer-only where scored, byte-identical on re-run.
2. BORN-INSTRUMENTED stage-trace (R-1; CONTEXT_PACKET_CONTRACT s9, which the orchestrator froze this wave). EVERY staged candidate-transforming step (classification / routing / channel-selection) emits one record `{retrieval_plan_id, stage_id, parent_stage_id?, policy_id, policy_version, candidates_in, removed[]:{record_id|channel_id, reason_codes[]}, candidates_out, tie_break_key?}` into the compile's evaluation_hooks/diagnostics, as an i33 DIAGNOSTIC ARRAY: namespace-closure-checked via the ONE canonical ns_permitted, sanitized fail-closed, NO cross-namespace identifying metadata. Integers only (no wall-clock/float); byte-identical on re-run.

IDENTITY. The `routing_policy_id` + `policy_version` enter packet identity (CONTEXT_PACKET_CONTRACT s6): same task + corpus snapshot + grants + profile + routing policy => identical packet_id.

HARD SCOPE GUARD (do not disturb the frozen #40 the Tier-1 flip validated against): a FLAT / non-routed / legacy compile -- the existing default path -- MUST stay BYTE-IDENTICAL to 0.7.0. The router is additive: existing callers and the i35 public-port path are unaffected. EMISSION + routing realization ONLY -- ZERO change to any frozen record/packet FIELD beyond the additive stage-trace diagnostic + the routing_policy id/version in identity. Do NOT touch #36/#37/#42 or any other module; do NOT edit core-docs.

GATES.
- Off-machine FIRST (cloud pwsh/python deterministic gate over a real #36 tree, in the style of the existing test_i35_public_port.py public-port gate).
- A NEW gate test asserting: (a) the stage-trace is PRESENT + well-formed per s9 on every routed compile; (b) DOUBLE-RUN byte-identity of the trace; (c) namespace-closure sanitization -- under a MIXED-namespace corpus the trace leaks NO cross-ns identifying metadata; (d) a flat/non-routed compile is BYTE-IDENTICAL to 0.7.0; (e) packet_id covers routing_policy id+version (vary the policy -> packet_id changes; hold it -> identical).
- REGRESSION green: the i34 smoke-i34.py (38/38) + the i35 public-port gate test_i35_public_port.py (32/32) + existing #40 tests.
- Ship via exec-job.sh devship (skill context.compile; named files only; AST + tests FAIL-CLOSED). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.

REPORT (`-Action report ... -State done` + plain summary): which channels the router realizes, the routing-policy id/version, the measured determinism, the stage-trace shape, and the byte-identical-flat proof. Negative/partial results are first-class -- say so plainly.

GOVERNING DOCS (read, do not edit): core-docs/CONTEXT_PACKET_CONTRACT.md (s6 identity, s7 eval seam, NEW s9 R-1 amendment) + MEMORY_CONTRACT.md (the canonical ns_permitted, A5/A6) + the DESCEND_QUERY_CLASSES definitions in #40; the R-1 rationale research/2026-08-05-interpretability-audit-surface-scoping.md s3.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit. This unit needs the **git** lease only (no GPU, no doc lease -- `docs:[]`; the orchestrator mirrors core-docs):
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "git" -Holder "ROUTER-R1-STAGETRACE-i37" -TtlSeconds 1800 -WaitSeconds 900
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "git" -Holder "ROUTER-R1-STAGETRACE-i37"
```
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]`.
- Gate off-machine FIRST, then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report when done/blocked (cadence on_all):
```
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId "fo-37-9995475a" -WorkerId "ROUTER-R1-STAGETRACE-i37" -State done -Summary "<one line: what you did>" -PlansDir "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"
```
  Use `-State progress` for interim, `-State blocked -Needs '<what>'` if stuck, `-State failed` if you cannot finish. Negative/partial results are first-class (the D-0061 ethos).

## Verification
A NEW #40 gate test: stage-trace present + well-formed per s9 on every routed compile; double-run byte-identity; namespace-closure sanitization under a mixed-ns corpus (no cross-ns leak); a flat/non-routed compile BYTE-IDENTICAL to 0.7.0; packet_id covers routing_policy id+version. REGRESSION green: i34 smoke-i34.py 38/38 + i35 test_i35_public_port.py 32/32 + existing #40 tests. Expected: #40 -> 0.8.0 committed (named files only, verified via native git); the orchestrator's D-0077 fold will drive the new stage-trace diagnostic through Lane A's P0-1 metadata-injection fixtures.

## Report-back record (ORCHESTRATOR fills from `plans/fo-37-9995475a/reports/` before archiving)
_empty._
