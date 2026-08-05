# WORK ORDER -- P01-AUTHZ-SUITE-i37 (module #43 action.authz)

- **Wave / plan:** i37 / `fo-37-9995475a` | **slot:** FANOUT_AGENT_003 | **lane:** CODING / CPU (Lane A)
- **Module (exclusive):** NEW `modules/43-action-authz` (brand-new -- no `skill.json`; `skill_id` OMITTED)
- **GPU:** false | **docs:** `[]` | **lease:** `git` only
- **non_execution:** true holds. This unit authorizes NO execution and enables NO tool.

## Mission

BUILD the P0-1 deterministic deny-by-default action reference monitor + adversarial injection SUITE (MVP) as new
module #43, against the FROZEN `core-docs/ACTION_AUTHORIZATION_CONTRACT.md` (D-0103) + its pinned normative source
`research/2026-08-05-i36-action-authz-freeze-frontier.md`. The single highest-leverage safety element: it flips
the threat model from "the model must resist every injection" to "the model may be fully steered and still cannot
exceed its capability envelope," and gives a model-independent P0-1 acceptance gate.

## Deliverables (MVP -- see README for COVERED vs STAGED)

1. strict parser + canonical serializer + `canonical_action_digest` + the four closed schema validators.
2. the deterministic deny-by-default reference monitor A01-A36 over trusted snapshots -> DENY (constant) | PERMIT.
3. the 4 universal properties (U-AUTHORITY/U-SCOPE/U-ROLE/U-EFFECT) as machine assertions.
4. fixtures: family 10 (PRIMARY) + a representative subset of families 1, 2, 6, 7, 9 (pinned canonical hashes).
5. the mock coordinator + mock executor boundary (C/D): no raw/proposal/permit-shaped path reaches the executor.
6. seeded-mutation kills M-A01..M-E36 (each killed by >=1 test; OS/store depth explicitly STAGED, not skipped).
7. real #36/#37/#40 (0.7.0) integration proving deterministic denial (A06, non_execution=true); positive
   permit-path via a test-only mock non_execution=false packet.

## Gates

- Off-machine FIRST (pure Python, cloud): `python -X utf8 -B modules/43-action-authz/tests/run_suite.py` -> exit 0.
- Then `exec-job.sh devship` (NEW module -- OMIT `skill_id`/`skill_dir`; sha256 + tests FAIL-CLOSED; named files
  only) under the `git` lease (holder `P01-AUTHZ-SUITE-i37`). VERIFY the real HEAD via native git (D-0072).
  Assert 0 UNMANAGED orphans.

## Acceptance (the s8.7 subset the MVP covers)

All MVP fixtures pass on TWO consecutive runs with identical property results + canonical hashes; every COVERED
M-* killed; every denied proposal -> no permit + no state diff; NO raw-model-output path reaches the mock
executor; cross-namespace failures return CONSTANT caller bytes; the real #36/#37/#40 chain proves deterministic
denial; ONE canonical implementation of parse/serialize/ns_permitted/digest/grant-match/permit-verify.

## Constraints

Do NOT modify #36/#37/#40 or any core-doc (`docs:[]`). Do NOT freeze or disposition any Blocker. Do NOT enable
execution. Standard-library only; deterministic; integer-only JSON; double-run byte-identity on every canonical
path.
