# modules/43-action-authz -- P0-1 action reference monitor + adversarial injection SUITE (MVP)

**Iteration 37 | worker `P01-AUTHZ-SUITE-i37` | plan `fo-37-9995475a` | NEW module (no `skill.json`).**

DESIGN-ONLY. This module authorizes **no** execution and enables **no** tool. `context_packet/0.2.non_execution`
remains `true`; the deny-by-default check **A06** deterministically DENYs every authentic packet while it holds.
Nothing in the system becomes action-capable. Built against the FROZEN
`core-docs/ACTION_AUTHORIZATION_CONTRACT.md` (D-0103) and its pinned normative source
`research/2026-08-05-i36-action-authz-freeze-frontier.md` (sections 0-10).

Standard-library-only Python, deterministic, integer-only JSON, byte-identical on re-run.

## What this is

A tiny, deterministic, deny-by-default **action reference monitor** whose one-shot permits bind the exact
canonical action to a trusted grant snapshot -- the single highest-leverage safety element. It flips the threat
model from "the model must resist every injection" to "the model may be fully steered and still cannot exceed
its capability envelope," and gives a **model-independent** P0-1 acceptance gate.

```
action_authz/
  canon.py     strict parser + canonical serializer + canonical_action_digest + the ONE ns_permitted + trust tags
  schemas.py   the four CLOSED schema validators (proposal/manifest/permit/completion) + ClosedArgSchema
  stores.py    MOCK trusted snapshots: packet store, GrantView, PolicyView, manifest registry (+resolver/effect
               profiles), approval store, tool-health, validator/status store, deterministic clock, atomic permit
               store, bounded privileged security log + the CONSTANT caller denial
  monitor.py   the ordered deny-by-default checks A01-A36 -> DENY (constant) or PERMIT (one immutable permit)
  boundary.py  the MOCK coordinator (C) + MOCK executor (D) + three-valued completion evaluation
tests/
  harness.py         baseline (test-only non_execution=false) happy-path scenario + scenario builders
  fixtures_suite.py  fixture family 10 (PRIMARY) + representative 1,2,6,7,9 (pinned canonical hashes)
  properties.py      U-AUTHORITY / U-SCOPE / U-ROLE / U-EFFECT machine assertions
  mutations.py       the seeded-mutation kill harness M-A01..M-E36 (+ kill matrix)
  integration.py     real #40 0.7.0 packets -> deterministic A06 denial; positive permit path
  run_suite.py       aggregate NN/NN + the double-run byte-identity gate
fixtures/real_packets/  four captured REAL #40 0.7.0 context_packet/0.2 outputs (see PROVENANCE.md)
```

## Run

```
python -X utf8 -B modules/43-action-authz/tests/run_suite.py
```

Exit 0 iff: all checks pass, every M-A01..M-E36 is killed, every real #40 packet is denied at A06, the positive
permit path issues exactly one permit under the test-only `non_execution=false` packet, and the two runs are
byte-identical.

## Acceptance result (reference run, off-machine gate)

- **192/192** checks pass (fixtures 77, universal properties 26, mutation kills 66, real integration 23).
- **66/66** mandatory seeded mutations `M-A01..M-E36` KILLED.
- **4/4** authentic #40 0.7.0 packets -> deterministic DENIAL at A06 (`non_execution=true`).
- Positive permit path OK via the test-only `non_execution=false` mock authority packet.
- Double-run BYTE-IDENTICAL (identical property results + canonical fixture hashes + kill matrix).

## COVERED vs STAGED

**COVERED (this MVP):** the strict parser + canonical serializer + `canonical_action_digest` + the four closed
schemas; the deterministic A01-A36 monitor; the 4 universal properties as machine assertions; fixture family 10
(PRIMARY) + a representative subset of families 1, 2, 6, 7, 9; the mock coordinator + mock executor boundary
(C/D); every `M-A01..M-E36` (each killed by >=1 deterministic test); and the real #36/#37/#40 (0.7.0)
integration proving deterministic denial.

**STAGED to i38+** (recorded, never silently dropped):

- the full 10-family fixture corpus (families **3, 4, 5, 8** + the remainder of 1/2/6/7/9);
- the fixed-seed mutational **FUZZER** (s8.7 crit 2);
- per-tool canonical target/effect **PROFILES** + Windows reparse-point/ADS/junction/device depth (Blocker 4).
  Generic resolver/effect interfaces are exercised now; `M-S06/M-E05/M-E06` are killed at the MVP level and
  their OS-specific depth is deferred;
- the **REAL Windows permit-store** authenticity / IPC / ACL / CAS / crash-recovery (Blocker 3). The MVP uses an
  in-process atomic MOCK permit store; `M-E26/M-E28/M-E29/M-E32` are killed logically and their real-store depth
  is deferred;
- the grant / side-effect-policy / approval **SCHEMAS** (Blockers 1/2; the MVP uses byte-equivalent
  `GrantView`/`PolicyView` + approval fixtures);
- the executor / validator status contracts (Blocker 5) + the production privileged security-log contract
  (Blocker 9); the freshness-relaxation policy (Blocker 6); the `non_execution` activation transition (Blocker 7).

No `#36/#37/#40` module or core-doc was modified; `docs:[]`. This module owns the ONE canonical
parse/serialize/`ns_permitted`/digest/grant-match/permit-verify implementation (Blocker 8).
