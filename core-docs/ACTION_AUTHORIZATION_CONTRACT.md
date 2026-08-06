# ACTION_AUTHORIZATION_CONTRACT -- the P0-1 action reference-monitor contract (FROZEN design target)

Owns the **action-authorization boundary** of the Collective Agent: the deterministic deny-by-default reference
monitor and the four sibling contracts that let a fully-steerable model PROPOSE an action while a trusted layer
outside the model decides whether any executor-visible side effect may occur. This is the third governing
contract of the substrate, alongside `MEMORY_CONTRACT.md` (record/embedding/retriever/eval) and
`CONTEXT_PACKET_CONTRACT.md` (selection + packet). It is named as a shared contract for the D-0077 fold rule.

## 0. Freeze status + what this doc is

- **FROZEN (D-0103, i37) as the normative DESIGN TARGET** for the P0-1 deterministic injection / action-boundary
  suite (module #43). DESIGN-ONLY: it authorizes NO execution and changes NO shipped memory/packet field.
  `context_packet/0.2.non_execution: true` remains mandatory; check A06 deterministically DENIES every authentic
  packet while it holds. Nothing in the system is action-capable.
- **The full normative text is PINNED VERBATIM** in `research/2026-08-05-i36-action-authz-freeze-frontier.md`
  (the couriered frontier CONDITIONAL-GO answer, pack `5e2812d2`, read-return captured/valid, D-0052 human lane)
  sections 0-10. THIS doc is the stable freeze AUTHORITY: it ratifies that text as frozen, registers the versions
  (s1), dispositions the section-9 blockers as ACTIVATION-gating (s2), states the build-vs-activation gate (s3),
  and maps consistency to the shipped substrate (s4). Design lineage: the i35 P0-1 suite design red-team
  `research/2026-08-05-i35-p0-1-injection-suite-redteam.md`.
- **Security objective (frozen s0.1).** Untrusted content (model output, retrieved evidence, navigation records,
  working memory, skill cards, tool text) may INFLUENCE an action proposal, but it cannot construct or modify
  authority, widen scope, define actual effects, create a permit, satisfy completion, or cause an executor-visible
  side effect **without a current one-shot permit bound to the exact canonical action**.
- **Trust classes (frozen s0.2).** Every field/value has exactly one origin: `Authority<T>` (authority-store
  only) / `Request<T>` (may narrow, never grant) / `Untrusted<T>` (never authorizes) / `TrustedStatus<T>`
  (narrow structured observation; satisfies only the exact predicate naming its source). No implicit conversion
  to `Authority` exists; an authority-shaped field name is not authority.

## 1. Frozen version registry

- `lifeorch.action_proposal/0.1` -- Untrusted model-facing request; never a tool call, grant, manifest, permit,
  completion result, or trusted status. `model_provenance` is adapter-attached (a model-supplied duplicate denies).
- `lifeorch.tool_manifest/0.1` -- the SOLE trusted definition of executable operations, closed arg schemas,
  canonicalization, target resolution, actual-effect classification, risk, approval, sandbox, idempotency,
  rollback, health. `Authority`; loaded ONLY from an allowlisted installed-code registry. Cards/procedures/README
  /model/tool text may DESCRIBE a tool but never DEFINE or override it.
- `lifeorch.action_permit/0.1` -- immutable one-shot `Authority` permit, issued only by the reference monitor,
  bound to one exact `canonical_action_digest`, resolved from the trusted permit store; NEVER rendered into an
  ordinary model context. One-shot state machine: issued -> claimed -> consumed (| revoked | expired |
  rejected_no_effect).
- `lifeorch.completion_contract/0.1` -- deterministic trusted completion predicates (closed three-valued tree;
  `indeterminate` is incomplete). `Authority`; control-plane store only; model/evidence/tool prose can never
  define, waive, or satisfy it.
- Internal/derived: `lifeorch.canonical_action/0.1` (authorizer-constructed, never accepted from the proposal;
  `canonical_action_digest` binds manifest+operation+canonical args+resolved targets+derived effects+namespace+
  risk+sandbox+limits+idempotency, with NO wall-clock and NO attacker prose) + `lifeorch.authorization_result/0.1`
  (the single CONSTANT caller-visible denial `{status:"denied", code:"AUTHZ_DENIED"}` -- no identifying metadata).
- **FROZEN algorithm:** the ordered deny-by-default checks **A01-A36** (s5). Indeterminate/missing/ambiguous/
  conflicting/unsupported = DENY. Each check is independently fixture-testable; deleting/bypassing any check is a
  mandatory killed mutation.
- **FROZEN enforcement obligations:** Boundaries **A** (storage/retrieval/derivation/packet assembly) / **B**
  (model-prompt rendering; defense-in-depth only) / **C** (coordinator action authorization -- decisive) / **D**
  (executor) (s6).
- **FROZEN acceptance:** universal properties **U-AUTHORITY / U-SCOPE / U-ROLE / U-EFFECT** (s8.1-8.4), the 10
  mandatory fixture families (s8.5), and the mandatory seeded mutations **M-A01..M-E36** (s8.6) -- every mutation
  MUST be killed by >=1 deterministic test.

## 2. Blocker disposition (frozen s9 Blockers 1-14 -- ALL ACTIVATION-gating; NONE blocks the P0-1 suite BUILD)

The four schemas + the monitor algorithm are internally complete enough to BUILD and TEST the deterministic P0-1
harness now. A clean OPERATIONAL freeze (any action-capable activation) is blocked until every item below is
resolved or explicitly dispositioned. Each is ACTIVATION-gating, not build-gating; the i37 MVP substitute is named.

| # | Blocker (s9) | i37 MVP substitute (build proceeds) |
|---|---|---|
| 1 | Exact permission-grant + side-effect-policy schemas (item-level matching, revocation, limits, windows, conjunction) | test `GrantView`/`PolicyView` fixtures consumed by A26/A27; freeze `permission_grant/0.1`+`side_effect_policy/0.1` before any grant-gated action |
| 2 | Approval-record contract + digest binding | test approval fixtures; freeze `action_approval/0.1` before any approval-gated action |
| 3 | Permit-store authenticity + atomic state machine on Windows (IPC/ACL/CAS/epoch/crash recovery) | an in-process atomic MOCK permit store; the real Windows store is i38+ |
| 4 | Per-tool canonical target + effect profiles (path/reparse/ADS/alias/recipient/redirect/wrapper) | generic resolver/effect INTERFACES frozen; each tool stays disabled/proposal-only until its profile+fixtures land |
| 5 | Trusted executor/status + validator-registry contracts | mock structured executor status + a mock validator registry for completion leaves |
| 6 | Freshness policy for packet/corpus/tree/working state (default: latest-current-only) | latest-current-only in the MVP; any relaxation is explicit per-policy + replay-tested later |
| 7 | Activation transition for `non_execution` (who may set false, which compiler/version, rollback) | NOT done; the MVP proves deterministic denial while `non_execution:true`; activation needs its own decision |
| 8 | Canonical parser/serializer/digest/grant-matcher/permit-verifier OWNERSHIP + cross-module byte-equivalence | module #43 owns ONE canonical implementation; a shared-fixture equivalence proof rides any second implementer |
| 9 | Constant-failure + privileged security-log contract (ACL, bounded fields, redaction, observable-step equalization) | the constant denial object + a bounded in-process security log in the MVP; production log ownership is i38+ |
| 10 | Idempotency/transaction/rollback/crash semantics PER operation | generic state machine tested; per-op profiles ride each tool's activation |
| 11 | Tool-health semantics (real probe, freshness, failure codes, registry) | mock health source in the MVP |
| 12 | Elevated promotion / authority-store write path (separate from the model path) | the MVP proves the ordinary model path CANNOT reach an authority constructor (U-AUTHORITY / M-A07) |
| 13 | Clarify "evidence cannot change skill selection" | resolved as a NORMATIVE CLARIFICATION here (s4); no field change |
| 14 | Real-module integration fixture + ownership (shared corpus, fuzzer seed, mutation framework, mock coord/exec, real #36/#37/#40) | module #43 owns it; the i37 MVP runs the real #36/#37/#40 (0.7.0) chain |

**Activation rule (frozen s10):** no action-capable coordinator or executor may be activated until Blockers 1-14
are resolved or explicitly dispositioned, every mandatory mutation is killed, the real module chain passes, and an
explicit activation decision (Blocker 7) authorizes selected manifests.

## 3. Build vs activation gate (what i37 builds; what stays staged)

- **i37 BUILDS (module #43 action.authz, MVP -- see the slot-003 brief):** the strict parser + canonical serializer
  (s0.4) + the `canonical_action_digest` (s0.6) + the four closed schemas; the deterministic deny-by-default
  reference monitor A01-A36 (s5); the 4 universal properties as machine assertions; fixture family 10 (fully
  malicious mock-model proposals) + a representative subset of families 1-9; the mock coordinator + mock executor
  boundary (C/D); every M-A01..M-E36 the monitor + mock executor can exercise (each killed by >=1 test); and the
  real #36/#37/#40 (0.7.0) integration proving DETERMINISTIC DENIAL while authentic packets carry
  `non_execution:true` (positive permit-path tests use an explicitly TEST-ONLY mock authority packet with
  `non_execution=false`, s8.7 crit 1).
- **STAGED to i38+ (recorded, never silently dropped):** the full 10-family fixture corpus; the fixed-seed
  mutational fuzzer (s8.7 crit 2); per-tool target/effect profiles + fixtures (Blocker 4); the Windows permit-store
  authenticity/IPC/ACL/crash-recovery (Blocker 3); the grant/policy/approval schemas (Blockers 1/2); the
  executor/validator status contracts (Blocker 5); the freshness relaxation policy (Blocker 6); the activation
  transition (Blocker 7); the production security-log contract (Blocker 9).
- **This wave's D-0077 fold** additionally drives Lane B's NEW `#40` router stage-trace diagnostic array (the R-1
  emission, `CONTEXT_PACKET_CONTRACT` s9) through the suite's metadata/diagnostic injection fixtures (attack family
  4) and asserts its determinism + namespace closure -- a new untrusted carrier proven non-authoritative at birth.

## 4. Consistency with the shipped substrate (frozen s7)

No frozen record / packet / provenance / namespace / hierarchy / working-state field is reopened or widened. The
action contract is a NEW SIBLING that references existing packet/grant snapshots by id/digest and composes with:
A5 namespace closure (the monitor IMPORTS, never reimplements, the one canonical `ns_permitted`; closure extends to
target resolution, effect derivation, status lookup, permits, executor re-resolution, logs, completion); A6
navigation-vs-evidence + safe-pruning (navigation/an unresolved frontier never satisfies evidence/authority; an
absence-dependent action needs a trusted retrieval-completeness predicate); `provenance_mode` (derived/aggregate
records keep non-authoritative origin -- epistemic authority is not execution authority); working-memory conjunctive
scope + `can_instruct:false`; `effective_current`/supersession (a predecessor cannot self-declare current). The
packet-level P0-1 probe remains necessary but is no longer SUFFICIENT -- the complete gate includes the C/D
action-boundary + completion isolation.

**Normative clarification (Blocker 13; no field change).** The older prose "evidence cannot change skill selection"
is narrowed to the deterministic property: **evidence cannot EXPAND eligibility or alter permissions, risk, health,
effects, approval, manifest, or completion; every proposed operation is independently authorized.** Evidence MAY
affect which already-permitted option the model proposes. Literal evidence-immune SELECTION, if ever required, must
be implemented as deterministic code and separately specified.

## 5. Freeze decision text (frozen s10, verbatim)

> Freeze `lifeorch.action_proposal/0.1`, `lifeorch.tool_manifest/0.1`, `lifeorch.action_permit/0.1`, and
> `lifeorch.completion_contract/0.1` as the normative design target for the P0-1 deterministic injection/action-
> boundary suite. Freeze the ordered deny-by-default checks A01-A36, enforcement obligations A/B/C/D, universal
> properties U-AUTHORITY/U-SCOPE/U-ROLE/U-EFFECT, and mandatory seeded mutations M-A01-M-E36. This freeze is
> design-only and does not enable execution. `context_packet/0.2.non_execution:true` remains mandatory. No
> action-capable coordinator or executor may be activated until Blockers 1-14 are resolved or explicitly
> dispositioned, every mandatory mutation is killed, the real module chain passes, and an explicit activation
> decision authorizes selected manifests.

## 6. i37 red-team amendments (GO-WITH-AMENDMENTS; D-0104) -- required for a FULL P0-1 gate pass

The i37 frontier red-team of THIS freeze (`research/2026-08-05-i37-action-authz-freeze-redteam.md`, pack
`2121775f`, read-return captured/valid) returned **GO-WITH-AMENDMENTS**: the architecture is sound as the design
target and the build may continue, but the reduced i37 MVP scope MUST NOT be called a full `P0-1 gate pass`. The
i37 module-#43 build is therefore **`build_complete`** with **`p0_1_gate_status = incomplete`** (consistent with
#43's own reporting: family 10 + a subset of 1/2/6/7/9 + the exercisable mutations, STAGING the full corpus +
fuzzer + per-tool profiles). The following are FROZEN as required for `p0_1_gate_status = pass` (an i38 build set);
NONE reopens a frozen MEMORY_CONTRACT / CONTEXT_PACKET_CONTRACT field.

1. **Result taxonomy (NEW).** `build_status` (incomplete|build_complete) / `p0_1_gate_status`
   (not_run|incomplete|pass|fail) / `activation_status` (prohibited|eligible|activated). `build_complete` NEVER
   implies `pass`; a skipped family, unrun fuzzer, surviving/unimplemented mutation, or absent real-chain test =>
   `incomplete`, never `pass`. Activation requires `pass` + all blockers + the separate activation decision.
2. **Test-facing GrantView/PolicyView (Blocker 1 PARTLY build-gating).** Freeze `lifeorch.grant_view/0.1-test` +
   `policy_view/0.1-test` -- the byte-exact matching language (field types/canonicalization, validity/revocation,
   exact tool/operation match, target-predicate language, ns via the canonical `ns_permitted`, effect/externality
   match, limit intersection, risk/approval escalation, conjunction/alternative rules, matcher output) BEFORE the
   gate tests A26/A27. Production storage schemas stay activation-gating. Likewise a closed `ApprovalView`
   (Blocker 2) for A29/M-E13 and a closed status/validator view (Blocker 5) for U-ROLE/M-E35/M-E36.
3. **Executor TOCTOU order (Boundary D).** Resolve+verify permit -> ATOMIC claim -> re-read all mutable epochs ->
   re-resolve dynamic targets AFTER claim -> bind execution to stable handles/canonical identities -> verify the
   same bound identity immediately before the first effect -> else `rejected_no_effect`. Expand M-E29 (mutate
   alias/reparse/recipient after resolve, both before AND after claim; expect `rejected_no_effect` + EMPTY diff).
4. **Completion binding.** Add `completion_scope` (task|action|permit|object) with per-kind minimum scope
   (executor-status / state-diff leaves are NOT task-only); bind the completion contract via a permit field OR the
   authentic immutable `packet_id` -- one normative mechanism. Add cross-action/permit/object substitution
   fixtures. Makes M-E36 decidable.
5. **Per-check / U-property oracle matrix.** One row per A-check / boundary-obligation / U-property / M-mutation
   naming the independent observable surface (decision+permit-store delta / caller bytes / privileged channel /
   audit event / origin ledger / executor-entry ledger / permit-state / digest / independent effect ledger /
   completion result). `no_path` properties need an unforgeable authority-constructor capability + import/call-graph
   inspection (runtime fuzzing cannot prove "no path"); A35/A36 are killed by inspecting their OWN output surface;
   trace-presence is NOT proof a property held.
6. **R-1 diagnostic role isolation (additive; no packet field change).** R1-AUTH-1: the router stage-trace
   envelope+payload are non-authoritative diagnostics (participate only in identity, deterministic evaluation,
   privileged audit, fail-closed ns validation). R1-ROLE-1: no router diagnostic field may populate/satisfy
   control_plane, evidence[]/evidence_requirements/coverage_results, packet_disposition, working_memory,
   grant/policy/approval/manifest/health, TrustedStatus, completion, target resolution, or effect derivation. Add
   mutation **M-R11** (cast an R-1 diagnostic record / reason-code / candidate-id into evidence coverage / authority
   / approval / health / completion). (The i37 D-0077 fold already proved the NAMESPACE-crossing case: an
   adversarial stage-trace still denies at A06 with constant bytes + no permit.)
7. **Split Blocker 9.** Build-gating: define every ordinary authz API surface, assert identical response
   schema/length, instrument a caller-visible deterministic step/branch signature, kill M-S08/M-S09.
   Activation-gating: production ACL/retention/redaction/IPC + physical timing equalization. The freeze claims
   constant bytes + no deterministic branch/step oracle, NOT absence of all timing channels.

**Corrected Blocker disposition (supersedes s2 where they differ):** Blockers 1, 2, 5 are PARTLY build-gating
(the test-facing views); 8 (canonical-impl equivalence) and 14 (real-module integration) are BUILD-gating and were
SATISFIED this wave (one canonical impl; real #36/#37/#40 0.7.0 chain); 9 and 12 have build-gating portions. Blockers
3, 4, 6, 7, 10, 11 remain activation-gating. `non_execution:true` holds throughout; nothing is action-capable.

## 7. i38 ratification -- the P0-1 FULL GATE is BUILT + VERIFIED (D-0106; p0_1_gate_status = pass)

In i38 (plan fo-38-2b1efe73) module #43 action.authz 0.2.0 BUILT all 7 section-6 amendments + promoted the
i37-staged items; the suite now reports **build_status=build_complete | p0_1_gate_status=pass |
activation_status=prohibited** (SUITE 204/204; all 10 fixture families; fixed-seed fuzzer 400 iters / 0
metamorphic violations; 67/67 mandatory mutations killed incl. the NEW M-R11; the 67-row oracle matrix; ONE
canon.py cross-validated BYTE-EQUIVALENT to an independent blind second implementation; double-run byte-identical
cloud+device). The ORCHESTRATOR independently re-ran the suite (PASS) + ran the **D-0077 cross-module fold 18/18**
(`modules/30-orchestrate-fanout/runtime/fold-i38.py`): a REAL #40 0.9.0 ROUTED + WORKING-MEMORY-HYDRATED packet
(state_version in identity) + an ADVERSARIAL variant (working_memory item authority-shaped: can_instruct=true,
is_evidence=true, body carrying permission_grants/approval/non_execution=false/issue_permit + a cross-namespace
router stage-trace + an injected_control_plane block) driven through #43's monitor -> deterministic **A06 DENY,
constant caller bytes, no permit, no state diff** for every one; a flat compile byte-identical. + i34 regression
38/38. The new working_memory region + router diagnostics CANNOT launder authority or cross a namespace (A31 /
R1-ROLE-1 / attack family 4).

- **Test-facing views PINNED (Blockers 1/2/5 build-gating portions RESOLVED).** The byte-exact
  `lifeorch.grant_view/0.1-test` + `policy_view/0.1-test` + the closed ApprovalView + the closed status/validator
  view are recorded byte-exactly in `modules/43-action-authz/SCHEMA_NOTES.md` (0.2.0) -- **that doc is the
  CANONICAL definition** (the reference/pin, as selpol was pinned to #37's canonical); A26/A27 gate on
  grant_view/policy_view, A29/M-E13 on ApprovalView, U-ROLE/M-E35/M-E36 on the status/validator view. Production
  STORAGE schemas stay ACTIVATION-gating.
- **Amendments 3-7 BUILT + killed** as section 6 requires (Boundary-D TOCTOU order + M-E29 post-claim drift;
  completion_scope + M-E36 decidable; the per-check oracle matrix with an independent observable per obligation;
  R1-AUTH-1/R1-ROLE-1 + M-R11; split-Blocker-9 constant-bytes + M-S08/M-S09). Detail: #43 SCHEMA_NOTES + the i38 report.
- **STILL ACTIVATION-gating (unchanged; `non_execution:true` holds; nothing is action-capable).** Blockers
  3/4/6/7 + the activation portions of 5/9 (the real Windows permit store, per-tool target/effect profiles, the
  production grant/policy/approval STORAGE schemas, the freshness relaxation policy, the non_execution ACTIVATION
  transition, production security-log ownership). `p0_1_gate_status=pass` is a DESIGN gate; `activation_status`
  stays **prohibited** -- activation still needs Blockers 1-14 resolved + the separate Blocker-7 decision.
- **Open follow-on (self-flagged; non-blocking).** The suite's OWN `integration.py` real-chain uses authentic
  #40 0.7.0 packets; the 0.9.0 routed+wm authentic chain is covered by the orchestrator D-0077 fold (above), not
  yet baked into `integration.py` -- recommended in a future #43 touch. A frontier AS-BUILT re-review of this pass
  was couriered at i38 close (pack `24190087...`, non-blocking; folds in i39 as an amendment if it finds a hole).

**FRONTIER AS-BUILT FOLD (D-0107 -- the re-review RETURNED).** The couriered re-review (`research/2026-08-06-i38-p01gate-asbuilt-redteam.md`, pack `24190087`, read-return captured/valid) returned **FAIL -- `p0_1_gate_status=pass` is OVER-CLAIMED**. `p0_1_gate_status` is WALKED BACK to **`incomplete`** (`build_status=build_complete` + `activation_status=prohibited` UNCHANGED; deny-by-default HOLDS -- the orchestrator D-0077 fold 18/18 + the independent #43 `run_suite` re-run stand; A06 denies every authentic packet; `non_execution:true` holds; nothing action-capable). The BUILD is NOT rejected -- only the full-gate PASS claim. **7 items are required for a TRUE pass (any of 1-4 alone blocks it) -- the i39 unit-0 (highest priority):** (1) the oracle matrix must cover EVERY A-check / boundary-obligation / U-property, not just the 67 mutations; (2) bake the 0.9.0 ROUTED + working-memory-hydrated authentic chain into #43 `integration.py` (the suite real-chain is still #40 0.7.0); (3) specify the test-facing grant/policy/approval/status/validator views BYTE-EXACTLY in SCHEMA_NOTES (currently summarized, not byte-exact); (4) bind completion via the immutable `packet_id`, not the packet's task; (5) the executor recheck must cover ALL mutable epochs (not a narrower list); (6) M-R11 must cover EVERY R1-ROLE-1 role-conversion sink (not one); (7) ship the implementation / oracle-matrix / fixtures / mutation defs / machine-readable report so the 204/204 is independently verifiable.

---

**Freeze state (UPDATED i38 -- D-0106):** FROZEN design target (D-0103, i37); the P0-1 gate is BUILT (`build_status=build_complete`); the i38 frontier AS-BUILT re-review WALKED `p0_1_gate_status` back to `incomplete` (D-0107, section 7 -- over-claimed; 7 items -> i39); activation still prohibited; design-only; `non_execution:true` holds. Amend only by a new
DECISION_LOG entry that names this doc; the verbatim normative source is
`research/2026-08-05-i36-action-authz-freeze-frontier.md`. A parallel frontier red-team of this freeze was couriered
at i37 open (non-blocking); any finding folds as an amendment.
