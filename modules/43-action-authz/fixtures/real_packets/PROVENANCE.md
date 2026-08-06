# real_packets/ -- captured REAL #40 context.compile outputs (integration fixtures)

Authentic `lifeorch.context_packet/0.2` outputs used by `tests/integration.py` to prove, deterministically
and without a live #40 run, that the reference monitor behaves correctly on the REAL producer seam. They are
read-only inputs; the suite never mutates them.

## #40 0.7.0 -- legacy flat packets (captured 2026-08-05)

Produced by the committed **#40 context.compile 0.7.0** over real #36/#37 retrieval, captured from
`modules/40-context-compiler/runtime/artifacts/*/compile/context_packet.json`. Each carries
`non_execution: true`, namespace `core-docs` -> the monitor DENIES every one at A06.

| file | packet_id | compiler_version | non_execution |
|---|---|---|---|
| m40_070_pkt_0.json | cpkt_1e0c6b40c9916edb42f5d773cf889640 | 0.7.0 | true |
| m40_070_pkt_1.json | cpkt_d9c0550a32b95cadc28060cea76189ea | 0.7.0 | true |
| m40_070_pkt_2.json | cpkt_b081a0c4d2f5851bd6a820a9198cda0b | 0.7.0 | true |
| m40_070_pkt_3.json | cpkt_994f6f30422809b8daf93f846e45e958 | 0.7.0 | true |

## #40 0.9.0 -- routed + working-memory-hydrated packets (captured i39, red-team Finding 2)

Produced by the committed **#40 context.compile 0.9.0** driving the REAL #36 artifact-search tree + the REAL
#42 working-memory store, via the orchestrator's own producer helpers in
`modules/40-context-compiler/tests/test_i38_working_memory.py` (`build_search_fixture` + `build_wm_store` +
`compile_wm`), i.e. the exact phase-1 of `modules/30-orchestrate-fanout/runtime/fold-i38.py`. Pure
python3 + stdlib + sqlite; deterministic (no wall-clock), so the committed bytes are a fixed function of the
committed producer source. `routed` carries the 0.8.0 router `routing_stage_trace` (3 records) AND a
0.9.0 hydrated `working_memory` region (present, `state_version=2`, `identity.working_state_version=2`).
`routed_adv` is `routed` with the working-memory item authority-shaped (`can_instruct=true`,
`is_evidence=true`, body carrying `permission_grants`/`approval_received`/`non_execution=false`/`issue_permit`)
+ a cross-namespace stage-trace + an injected `control_plane` block -- with valid packet boundaries.
`flat` is the non-routed compile (no trace, no hydrated wm).

`tests/integration.py` runs each authentic (`non_execution=true`) -> A06 DENY, and drives an explicit
TEST-ONLY `non_execution=false` variant of `routed` through A09/A11/A30/A31 + completion (the adversarial
`routed_adv` yields a byte-identical decision + canonical_action_digest -- the 0.9.0 carriers cannot launder
authority or cross a namespace).

| file | packet_id | compiler_version | non_execution | notes |
|---|---|---|---|---|
| m40_090_routed.json | cpkt_bc8ec7dac487496799b006e2ddf8a6b3 | 0.9.0 | true | routed + wm-hydrated (state_version=2) |
| m40_090_routed_adv.json | cpkt_bc8ec7dac487496799b006e2ddf8a6b3 | 0.9.0 | true | authority-shaped wm + trace + injected control-plane |
| m40_090_flat.json | cpkt_a36318c26fc1187ac476e26595baddf0 | 0.9.0 | true | flat (no router trace, no hydrated wm) |
