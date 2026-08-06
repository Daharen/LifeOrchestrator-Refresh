# FANOUT_AGENT_003 -- P01-AUTHZ-SUITE-i37

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i37 (plan id `fo-37-9995475a`)
- **Lane:** CODING / CPU (Lane A)
- **Worker id / label:** `P01-AUTHZ-SUITE-i37`
- **Module/area (exclusive):** NEW modules/43-action-authz (brand-new -- no skill.json; OMIT skill_id)
- **GPU:** false
- **Docs:** `[]`

## Mission
BUILD the P0-1 deterministic deny-by-default action reference monitor + adversarial injection SUITE (MVP) as NEW module #43 action.authz, against the FROZEN `core-docs/ACTION_AUTHORIZATION_CONTRACT.md`. Worth a wave slot: this is the single highest-leverage safety element -- it flips the threat model from 'the model must resist every injection' to 'the model may be fully steered and still cannot exceed its capability envelope', and gives a model-independent P0-1 acceptance gate. non_execution:true holds; nothing becomes action-capable.

## Unit (the full worker prompt)
BUILD the P0-1 action-authorization reference monitor + adversarial injection SUITE as a NEW module modules/43-action-authz (a brand-new module -- OMIT skill_id/skill_dir; no skill.json yet). EXCLUSIVE to modules/43-action-authz; docs:[]; CPU (no GPU); pure Python, STANDARD-LIBRARY ONLY, deterministic, integer-only JSON, byte-identical on re-run. non_execution:true holds -- this authorizes NO execution and enables NO tool; NOTHING becomes action-capable.

BUILD AGAINST THE FROZEN CONTRACT: core-docs/ACTION_AUTHORIZATION_CONTRACT.md (the freeze AUTHORITY -- version registry, blocker disposition, build-vs-activation gate) + its pinned verbatim normative source research/2026-08-05-i36-action-authz-freeze-frontier.md sections 0-8 (the four schemas, the A01-A36 algorithm, the U-properties, the M-A01..M-E36 mutations, the 10 fixture families). Read both first.

MVP DELIVERABLES (this is a SCOPED MVP; the orchestrator explicitly staged the rest -- see STAGED below):
1. STRICT PARSER + CANONICAL SERIALIZER (s0.4: valid-UTF8, duplicate-key rejection, integer-only, no coercion, closed-object unknown-field rejection, exact byte limits, sorted-key canonical JSON, one trailing LF) + the `canonical_action_digest` (s0.6) + the four CLOSED schema validators (action_proposal / tool_manifest / action_permit / completion_contract 0.1).
2. The deterministic DENY-BY-DEFAULT reference monitor implementing the ordered checks A01-A36 (s5) as a PURE function over explicitly-supplied trusted snapshots (packet store + integrity verifier, grant snapshot, side-effect policy, tool-manifest registry, approval store, tool-health, validator registry, a trusted clock, an atomic permit store, a privileged logger) -> EXACTLY `DENY` (the CONSTANT caller-visible denial object, no permit, no state diff) or `PERMIT` (one immutable permit in the trusted store + a privileged reference). Indeterminate / missing / ambiguous / unsupported = DENY.
3. The 4 UNIVERSAL PROPERTIES as machine assertions over the fixtures: U-AUTHORITY (s8.1), U-SCOPE (s8.2), U-ROLE (s8.3), U-EFFECT (s8.4).
4. FIXTURES: family 10 (fully malicious mock-model proposals against the mock authz+executor, incl. raw tool-call + permit-shaped output) as the PRIMARY family, PLUS a representative subset of families 1-9 the monitor + mock executor can exercise deterministically: 1 (direct evidence/fake-control/fake-completion injection, incl. split-across-chunks), 2 (delimiter / unicode / bidi / zero-width / homoglyph / base64 / hex / NUL), 6 (cross-namespace leakage incl. the CONSTANT-denial side-channel: a violation count / timing / error-variant must NOT become an existence oracle), 7 (stale / superseded reassertion), 9 (parser / canonicalization / replay / TOCTOU: duplicate keys, coercion, wrappers, symlinks/junctions, wildcard/env expansion, arg substitution, grant revocation, manifest drift, permit reuse). Pin canonical fixture HASHES + named security-PROPERTY expectations, NOT whole-packet byte snapshots.
5. The MOCK coordinator + MOCK executor boundary (Boundaries C/D): a raw proposal / raw model tool-call / caller-created permit object NEVER reaches the executor; the executor accepts ONLY a privileged permit reference resolving to an `issued` permit in the trusted store; permit reuse / expiry / nonce / store-epoch / revocation / manifest-drift / target-drift fail CLOSED; one permit -> exactly one consumed canonical action; every denial -> no permit + no state diff.
6. SEEDED-MUTATION KILLS M-A01..M-E36 (s8.6): a mutation harness that applies each seeded defect, runs the suite, and asserts the named security-property test FAILS on the mutated impl (a test green on the reference impl must go red on the mutant). Cover EVERY M-* the MVP's monitor + mock authz/executor surface reaches. For any M-* that requires a per-tool profile, the fuzzer, or the real Windows permit store, mark it explicitly STAGED with the reason (do NOT silently skip).
7. REAL-MODULE INTEGRATION (s8.7 crit 9): run the same producer->consumer assertions on REAL #36/#37/#40 (0.7.0) packet outputs -- the authentic #40 packet path proves DETERMINISTIC DENIAL (A06 denies every packet while non_execution:true); positive permit-path tests use an explicitly TEST-ONLY mock authority packet with non_execution=false (s8.7 crit 1).

STAGED to i38+ (record in the module README + the report; DO NOT attempt this wave): the full 10-family corpus; the fixed-seed mutational FUZZER (s8.7 crit 2); per-tool canonical target/effect PROFILES + fixtures (Blocker 4); the Windows permit-store authenticity / IPC / ACL / crash-recovery (Blocker 3 -- MVP uses an in-process atomic MOCK store); the grant / side-effect-policy / approval SCHEMAS (Blockers 1/2 -- MVP uses byte-equivalent GrantView/PolicyView + approval fixtures); the executor / validator status contracts (Blocker 5); the production security-log contract (Blocker 9).

CONSTRAINTS. Do NOT modify #36/#37/#40 or any core-doc (docs:[]). Do NOT freeze or disposition any Blocker -- the orchestrator froze the contract; you build to it. Do NOT enable execution. Standard-library only; deterministic; integer-only JSON; a DOUBLE-RUN byte-identity gate on every canonical-bytes path.

GATES.
- Off-machine FIRST (pure python, cloud gate). Then exec-job.sh devship (NEW module -- OMIT skill_id/skill_dir; AST + tests FAIL-CLOSED; named files only). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.
- ACCEPTANCE (the s8.7 subset the MVP covers): all MVP fixtures pass on TWO consecutive runs with identical property results + canonical hashes; every COVERED M-* is killed; every denied proposal -> no permit + no state diff; NO raw-model-output path reaches the mock executor; cross-namespace failures return CONSTANT caller bytes with no identifying data; the real #36/#37/#40 chain proves deterministic denial; ONE canonical implementation of parse / serialize / ns_permitted / digest / grant-match / permit-verify.

REPORT (`-Action report ... -State done` + plain summary): the suite test count (NN/NN), the mutation-kill matrix (each M-* COVERED->killed or STAGED->why), the fixture families covered vs staged, the real #40 0.7.0 integration result (deterministic denial), and the double-run byte-identity proof. Negative/partial results are first-class.

GOVERNING DOCS (read, do not edit): core-docs/ACTION_AUTHORIZATION_CONTRACT.md + research/2026-08-05-i36-action-authz-freeze-frontier.md (sections 0-10) + research/2026-08-05-i35-p0-1-injection-suite-redteam.md (the 7-layer harness + attack taxonomy) + CONTEXT_PACKET_CONTRACT.md s1 (P0-1 packet separation) + MEMORY_CONTRACT.md (the canonical ns_permitted).

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit. This unit needs the **git** lease only (no GPU, no doc lease -- `docs:[]`; the orchestrator mirrors core-docs):
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "git" -Holder "P01-AUTHZ-SUITE-i37" -TtlSeconds 1800 -WaitSeconds 900
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "git" -Holder "P01-AUTHZ-SUITE-i37"
```
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]`.
- Gate off-machine FIRST, then ship via `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report when done/blocked (cadence on_all):
```
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId "fo-37-9995475a" -WorkerId "P01-AUTHZ-SUITE-i37" -State done -Summary "<one line: what you did>" -PlansDir "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"
```
  Use `-State progress` for interim, `-State blocked -Needs '<what>'` if stuck, `-State failed` if you cannot finish. Negative/partial results are first-class (the D-0061 ethos).

## Verification
The suite's own test count (NN/NN) on TWO consecutive runs with identical property results + canonical fixture hashes; the mutation-kill matrix (each M-A01..M-E36 COVERED->killed or STAGED->reason); every denied proposal -> no permit + no state diff; NO raw-model-output path reaches the mock executor; cross-namespace failures return CONSTANT caller bytes; the REAL #36/#37/#40 (0.7.0) chain proves DETERMINISTIC DENIAL while non_execution:true (positive permit-path via a test-only mock non_execution=false packet). Expected: NEW modules/43-action-authz committed (OMIT skill_id; named files only; verified via native git); a module README recording COVERED vs STAGED (full 10-family corpus / fuzzer / per-tool profiles / real Windows permit store -> i38).

## Report-back record (ORCHESTRATOR fills from `plans/fo-37-9995475a/reports/` before archiving)
_empty._
