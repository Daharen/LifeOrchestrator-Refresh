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

**FRONTIER AS-BUILT RE-REVIEW FOLD (D-0109 -- the i39 re-review RETURNED FAIL).** The couriered re-review of the COMPLETED gate (`research/2026-08-06-i39-p01gate-recheck-redteam.md`, pack `b2b1e5fb`, read-return captured/valid) returned **FAIL -- `p0_1_gate_status=pass` is OVER-CLAIMED**. `p0_1_gate_status` is WALKED BACK to **`incomplete`** (`build_status=build_complete` + `activation_status=prohibited` UNCHANGED; deny-by-default HOLDS -- the orchestrator D-0077 fold-i39 18/18 + the independent #43 run_suite 308/308 re-run stand; A06 denies every authentic packet; `non_execution:true` holds; nothing action-capable). The BUILD is real progress; only the full-gate PASS claim is rejected. **7 SUITE-BUILD findings are required for a TRUE pass (none reopens a frozen field) -- the i40 unit-0:** (1) completion must be IMMUTABLY bound at issue time -- require cc.packet_id present AND == permit.packet_id AND a present issue-time binding matching id/version/digest; a NO_COMPLETION_CONTRACT sentinel; reject late contract insertion after permit issuance; (2) Boundary-D must inject faults AFTER the atomic claim (a deterministic post-claim hook), make the issue-snapshot MANDATORY, and consume the captured target handle in the effect ledger (the current oracle mutates PRE-claim); (3) the role matrix must cover ALL 15 frozen R1-ROLE-1 sinks -- it OMITS `manifest` + `working_memory` (26/26 is against a narrowed 13-sink list); (4) GrantView must IMPLEMENT + pin its declared `limits` intersection algebra (the matcher reads only `max_quantity`; A23 uses only the manifest ceiling) OR amend `limits` away; (5) the 0.9.0 chain is authentic at A06 but SYNTHETIC beyond -- a suite-owned EXACT context_packet/0.2 adapter must preserve all carriers/identity beyond A06 (the test-only path sets corpus_version=None, swaps the grant snapshot, reduces the trace/wm to two booleans); (6) no_path must be a real stdlib-ast CALL-GRAPH over every action_authz module (not source-pattern matching), A36 must require exactly one correct bounded audit event (not just absence-of-leak), Boundary-B rows must mutate the real render path; (7) ship a COMPLETE independently-runnable review tree (the 21-file pack omits action_authz/__init__.py, tests/{harness,fixtures_suite,properties,fuzzer,report}.py, the packet fixtures + the report bundle -> run_suite ImportError). Bundle with PB-5 (the #37 lane) as i40 unit-0.

**i39 CLOSURE (D-0108) -- the 7 D-0107 findings BUILT; `p0_1_gate_status` -> `pass` (WALKED BACK to `incomplete` by D-0109 above).** In i39 (plan fo-39-df2e3a67) module #43 action.authz 0.3.0 (`8f01a15`) CLOSED all 7 D-0107 findings and the gate is now an honest DESIGN pass: (1) tests/oracle_matrix.py rebuilt to **141 EXECUTED obligation rows** (one per A01-A36 / Boundary A1-A7,B1-B4,C1-C6,D1-D8 / U-AUTHORITY,SCOPE,ROLE,EFFECT / every mutation; NOT_RUN=0; run_suite GATES on completeness; A35/A36 on their OWN surfaces; no_path via an authority-constructor capability AND a static call-graph scan); (2) a REAL #40 0.9.0 ROUTED+working-memory-hydrated authentic chain BAKED into tests/integration.py in TWO modes (authentic non_execution=true -> A06 DENY; a TEST-ONLY non_execution=false variant preserving trace/wm/state_version/evidence/identity that REACHES A09/A11/A30/A31+completion) + an adversarial authority-shaped variant; (3) the grant/policy/approval/status/validator **0.1-test views specified BYTE-EXACTLY in modules/43-action-authz/SCHEMA_NOTES.md (CANONICAL) + pinned by canonical digest + 37 manually-derived golden vectors**; (4) completion binds via the IMMUTABLE **packet_id** (issue-time binding at A34; NO current-contract-by-task lookup) + the per-leaf-kind MIN_COMPLETION_SCOPE table -> M-E36 decidably killed; (5) Boundary D re-reads **ALL mutable epochs** after the atomic claim + a captured unforgeable resolution-proof handle + a post-claim mutation per epoch; (6) M-R11 -> a **26-sink R1-ROLE-1 matrix** run under the test-only non_execution=false path so A31+completion are REACHED; (7) an independently-auditable evidence bundle (report.json + oracle_matrix + fixture_manifest + mutation_defs + source_digests; bundle_digest f190d95b) + a blind independent `p01gate` byte-equivalence impl (Blocker 8). **SUITE 308/308 double-run byte-identical (sig 8403d2f5), 67/67 mandatory mutations, all 10 families, fuzzer 400/0.** The ORCHESTRATOR independently re-ran run_suite (308/308 pass) + ran the **D-0077 fold-i39 18/18** (a real #40 0.9.0 routed+wm packet -- produced via the i39 #36 0.7.0 fast-beam ranking -- + an adversarial authority-shaped wm/cross-ns stage-trace/injected-control variant -> deterministic A06 DENY, constant caller bytes, no permit, no state diff) + i34 38/38. **Result taxonomy: build_complete | p0_1_gate_status=pass | activation_status=prohibited; `non_execution:true` holds; nothing action-capable.** A frontier as-built RE-REVIEW of the COMPLETED gate was couriered (pack `b2b1e5fb`, 21 files/441KB; non-blocking; folds i40). STILL ACTIVATION-gating (unchanged): Blockers 3/4/6/7 + the activation portions of 5/9.

<!-- D-0107 (i38 as-built FAIL, now CLOSED by D-0108 above) retained for lineage: -->
**FRONTIER AS-BUILT FOLD (D-0107 -- the re-review RETURNED).** The couriered re-review (`research/2026-08-06-i38-p01gate-asbuilt-redteam.md`, pack `24190087`, read-return captured/valid) returned **FAIL -- `p0_1_gate_status=pass` is OVER-CLAIMED**. `p0_1_gate_status` is WALKED BACK to **`incomplete`** (`build_status=build_complete` + `activation_status=prohibited` UNCHANGED; deny-by-default HOLDS -- the orchestrator D-0077 fold 18/18 + the independent #43 `run_suite` re-run stand; A06 denies every authentic packet; `non_execution:true` holds; nothing action-capable). The BUILD is NOT rejected -- only the full-gate PASS claim. **7 items are required for a TRUE pass (any of 1-4 alone blocks it) -- the i39 unit-0 (highest priority):** (1) the oracle matrix must cover EVERY A-check / boundary-obligation / U-property, not just the 67 mutations; (2) bake the 0.9.0 ROUTED + working-memory-hydrated authentic chain into #43 `integration.py` (the suite real-chain is still #40 0.7.0); (3) specify the test-facing grant/policy/approval/status/validator views BYTE-EXACTLY in SCHEMA_NOTES (currently summarized, not byte-exact); (4) bind completion via the immutable `packet_id`, not the packet's task; (5) the executor recheck must cover ALL mutable epochs (not a narrower list); (6) M-R11 must cover EVERY R1-ROLE-1 role-conversion sink (not one); (7) ship the implementation / oracle-matrix / fixtures / mutation defs / machine-readable report so the 204/204 is independently verifiable.

---

**ROUND-3 RATIFICATION FOLD (D-0113 -- the i40 review RETURNED FAIL; M2-D HELD, nothing to walk back).** In i40 module #43 0.4.0 (`663145b`) built the 7 D-0109 findings' EXACT CLOSURE blocks and -- per mandate-02 M2-D -- EMITTED `p0_1_gate_status=incomplete` (the per-finding `exact_closure_built` flags carried the claim; NO pass was self-reported, so this FAIL walks nothing back -- the first review round with an honest prior). The couriered ROUND-3 ratification review (`research/2026-08-06-i40-p01gate-round3-redteam.md`, pack `5807bc3e`, read-return captured/valid, pack_id_match) returned **FAIL -- do not ratify s7**. ACCEPTED AS CLOSED by the reviewer: F3 (the all-15-sink role matrix, 30/30) + F6 (a real stdlib-ast call-graph no_path; A36 exactly-one-bounded-event + deletion/corruption faults; Boundary-B explicitly defense-in-depth) + the quantitative limit-intersection portion of F4 + the post-claim/terminal portion of F2. **5 SUITE-BUILD findings remain (none reopens a frozen field) -> the i41 #43 unit:** (1) completion binding must be WRITE-ONCE in the PermitStore -- `record_completion_binding` is an unrestricted overwrite and the getter returns the live mutable dict, so the NO_COMPLETION_CONTRACT sentinel / original binding can be replaced after issuance (required: write-once per permit_id, reject second recording incl. identical, immutable/defensive-copy representation, vectors for sentinel-overwrite / binding-overwrite / getter-mutation / duplicate recording); (2) the captured target must be a trusted HANDLE CAPABILITY the effect applicator CONSUMES -- the executor currently copies `authorized_effect_set` and tags entries with the `resolution_proof_digest` STRING (required: a distinct TargetHandle object, an applicator API that requires it, the ledger generated from the handle-bound applicator result, one-shot/observably-consumed handles, and a killed blind-copy+tag mutant); (3) the 0.9.0 adapter must be LOSSLESS -- `adapt_packet_view` extracts a subset of identity + carriers (compiler_version / selection_policy / retrieval_provenance / evidence refs / selection stages all collapse; required: preserve the complete packet or canonical bytes + a validated derived view, per-identity-field mutation properties [any change alters the preserved identity or fails closed], round-trip equivalence, overlay flips ONLY non_execution); (4) the pinned closed GrantView must be OPERATIONALLY enforced at the TOP level -- the matcher accepts an unknown top-level grant field (required: validate the exact top-level field set/types before matching, reject unknown/missing/mistyped, vectors, pin the operational validator not just the descriptive view object); (5) the transported review pack must be COMPLETE -- the i40 pack omitted `WORK_ORDER.md` (digest 36e713da..; an ORCHESTRATOR pack-authoring omission -- the file exists on-box; the reviewer's empty-dir run exited 1 at finding_7); future packs are GENERATED from the suite's own required-file manifest and extracted+run from an empty dir BEFORE couriering. Reviewer-observed on the transported tree: behavioral 334/334, mutations 67/67, fuzzer 400/0, oracle 149 rows / 0 not_run, role 30/30, completion 17/17, views 48/48 -- the build substance is accepted; the 5 holes block ratification. No frozen CONTEXT_PACKET_CONTRACT / MEMORY_CONTRACT field needs reopening.

**ROUND-4 RATIFICATION FOLD (D-0116 -- FAIL; F1/F7 CLOSED; 3 findings remain).** The round-4 review of #43 0.5.0 (`107c925`; pack `678163b1`, read-return captured/valid, sha 56a7eb31..; verbatim digest `research/2026-08-07-i41-p01gate-round4-redteam.md`) returned **FAIL -- s7 stays `incomplete`** (M2-D: nothing was claimed, nothing walks back -- the third consecutive no-over-claim round). The reviewer INDEPENDENTLY reconstructed the MANIFEST-DERIVED pack (49/49 byte-recoverable incl. `WORK_ORDER.md`) and ran both documented commands exit 0 (352/352; mutations 68/68; oracle 150 rows / 0 not_run; bundle `ab831c85..`) -- **F7 CLOSED (the D-0113 pack rule proven) and F1 CLOSED** (write-once binding verified); F3/F6 + the accepted F4 limit-algebra + F2 post-claim portions stand. **3 SUITE-BUILD findings -> the next #43 unit (0.5.0 -> 0.6.0; none reopens a frozen field):** (1) **F5**: `build_trusted()` must BEGIN with `adapt_packet_lossless()` -- PacketView/meta derived ONLY from the preserved re-parsed packet, the whole-packet identity digest bound into trusted adapter state, and the per-field + 5 named probes re-run through THAT end-to-end path (the lossless sidecar exists; the monitor-facing seam bypasses it); (2) **F4**: grants validated BEFORE any operational read -- ingress validation or ONE shared validated iterator for `grant_namespaces()` + `match()` (A11 currently KeyErrors on missing `grant_id`/`action_namespace`); end-to-end authorize() vectors -> constant DENY, no exception, no permit, no state diff; (3) **F2**: the effect applicator consumes handle + canonical operation args and RETURNS the effect atoms; `authorized_effect_set` = authorization bound/comparison, never the ledger template; a SUCCESSOR MUTANT (consume-but-discard-result + blind-copy) decisively killed.
**Freeze state (UPDATED i41 -- D-0116):** FROZEN design target (D-0103, i37); the P0-1 gate is BUILT (`build_status=build_complete`; #43 0.5.0 `107c925`, the 7 D-0109 + 4 round-3 exact closures; F1/F7 accepted closed at round-4) with `p0_1_gate_status=incomplete` -- NOT RATIFIED (the round-4 review returned FAIL, D-0116 s7; 3 suite-build findings -> the #43 0.6.0 unit; under M2-D no pass was self-claimed, so nothing was walked back) / `activation_status=prohibited`; deny-by-default holds (the i41 fold: independent suite x2 byte-identical + the D-0077 harness exit 0 + i34 38/38); design-only; `non_execution:true` holds; nothing action-capable. Amend only by a new
DECISION_LOG entry that names this doc; the verbatim normative source is
`research/2026-08-05-i36-action-authz-freeze-frontier.md`. A parallel frontier red-team of this freeze was couriered
at i37 open (non-blocking); any finding folds as an amendment.
