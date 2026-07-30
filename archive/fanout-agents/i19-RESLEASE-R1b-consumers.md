# ARCHIVED -- FANOUT_AGENT_001 (i19, plan fo-19-3aa34fe9) -- RESLEASE-R1b-consumers

**Status:** DISPATCHED -> REPORTED -> ARCHIVED (superseded by the i20 R1b' brief in the live slot).
**Lane:** GPU single-worker (core-infra). **Worker id:** `RESLEASE-R1b-consumers`.

## Original mission (i19)

Complete R1 (GPU-lease split): wire R1a's res.lease primitive split into `model.gateway` #7 PoolManager +
`agent.local` #21 governor and PROVE the mid-task GPU hand-off live on the 2080 Ti; on success CLOSE warm-pool
findings 1/13/14. Fallback clause: ship the solid subset behind the additive/default-off surface, keep the
single-agent default byte-identical, do NOT declare 1/13/14 closed, report plainly (D-0061 ethos).

## Report-back record (worker outcome)

Worker took the **documented fallback**. Report: `plans/fo-19-3aa34fe9/reports/RESLEASE-R1b-consumers.1c9c859d.json`.

- **SHIPPED (committed, verified real HEAD `2d45ffe4c8e64baa3ffe3450ea750541eec9780b`, native git):** the R1b
  **PRIMITIVE** layer only -- res.lease #29 `0.3.0` (three-identity fencing + the single scheduler-owned atomic
  `-Transition` + an adversarial MOCK evictor + WDDM stable-headroom discipline; res.lease stays PURE). 4 files,
  +526/-17. Gate: 74/74 v0.1/v0.2 baseline (0 regression) + 36/36 v0.3 adversarial, off-machine + on-box; 0 orphans.
- **NOT shipped:** the #7/#21 consumer wiring, the real nvidia-smi evictor, the live-GPU proof (model-bound). A
  code-level adoption spec (`R1b-consumer-adoption-spec.md`) delivered instead.
- **findings 1/13/14 stay OPEN.** Warm-pool default-ON still gated.

## Folded frontier red-team (pack b823d9db)

Necessary-but-insufficient identities; transition unsafe as ordered (grants an ordinary lease before the new
resident is healthy/published); side effects must be fenced AT THE TARGET. => i20 = R1b' (primitive hardening:
incarnation ids + transition-capability + target-fenced callback CAS + idempotent saga journal + Job-Object
contract + adversarial matrix A-K). Full close-out: the i19 SHIP-STATE + D-0073.
