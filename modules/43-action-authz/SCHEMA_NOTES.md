# SCHEMA_NOTES -- module #43 action.authz contract interpretation (i37, P01-AUTHZ-SUITE-i37)

How this module realizes the FROZEN `ACTION_AUTHORIZATION_CONTRACT.md` (D-0103) + its pinned normative source
`research/2026-08-05-i36-action-authz-freeze-frontier.md`. This is the module's record of every frozen-field
interpretation (the D-0077 analog for the action layer). Nothing here reopens a frozen field.

## Trust classes (s0.2)

`Authority / Request / Untrusted / TrustedStatus` are enforced by construction: authority values come only from
the trusted stores (`stores.py`); the monitor never builds an `Authority` from proposal/evidence. `canon.Tagged`
+ `canon.authority_construct` + `canon.derive` + `canon.aggregate_to_authority` make the "no ordinary path from
Untrusted/Request to the Authority constructor" property machine-checkable (U-ROLE; M-A06/M-A07/M-R03).

## The four contracts (s1-s4)

- `action_proposal/0.1` -- validated at A03 (`schemas.validate_action_proposal`), closed field set, Untrusted.
  `model_provenance` is adapter-attached and verified at A04 against `AdapterAttestation`; a model-supplied
  duplicate/forgery denies (M-A09). `claimed_effects` is advisory and never reaches effect derivation or grant
  matching (M-A08).
- `tool_manifest/0.1` -- Authority; loaded ONLY from the allowlisted `ManifestRegistry` (A12); operations,
  closed arg schema, canonicalizer/target-resolver/effect-classifier `CodeProfileRef`s (installed-code profiles
  in `stores.PROFILES`), risk/approval/idempotency/ceilings. A card/procedure/model/tool text can never define
  it (M-A02/M-A10).
- `action_permit/0.1` -- immutable Authority permit built ONLY by the monitor (A34), bound to one exact
  `canonical_action_digest`, resolved from the trusted permit store; never rendered to the model (A35/M-R09).
- `completion_contract/0.1` -- Authority; three-valued closed predicate tree evaluated in `boundary.evaluate_completion`
  over trusted status ONLY; `indeterminate` is incomplete; model/evidence/tool prose can never satisfy it
  (M-R07/M-R08/M-A04/M-E35/M-E36/M-S10).

## Canonicalization + digest (s0.4/s0.6, Blocker 8)

`canon.py` is the ONE canonical implementation of strict parse, canonical serialize, `canonical_action_digest`,
`ns_permitted`, grant-match (in `stores.GrantSnapshot.match`), and permit verify (in `boundary`). Strict parse:
valid UTF-8 + BOM/lone-surrogate reject, duplicate-key reject, integer-only (float/NaN reject), exact byte limit,
depth<=16 / members<=1024 / items<=4096. Canonical serialize: code-point-sorted keys, no insignificant
whitespace, lowercase literals, one trailing LF. The digest binds manifest+operation+canonical args+resolved
targets+derived effects+namespace+risk+sandbox+limits+idempotency (no wall-clock, no attacker prose); a caller
digest is never accepted (M-E18). `canonical_digest()` is exposed so the digest-omission mutations (M-E14..E17)
are individually killable.

## Reference monitor A01-A36 (s5)

Implemented in `monitor.authorize` in the frozen order. A06 (non-execution) is the deterministic headline gate:
while `non_execution=true` it denies every authentic packet. A32 is the TOCTOU barrier (re-reads grant epoch,
policy epoch, installed digest, health, packet currentness/non_execution before issue). Any exception / missing /
ambiguous / unsupported / indeterminate result denies. The caller always receives the CONSTANT denial object
(s0.5); identifiers go only to the bounded privileged security log (M-S08/M-S09).

Minor implementation ordering note: side-effect-policy risk/approval escalation (A27) is folded into the effective
risk/sandbox BEFORE the canonical action is constructed (A25), so the permit's risk/sandbox/limits exactly match
the digest (s3.4.2). The policy DENY decision and approval requirement remain at A27/A28. This is a construction
convenience, not a semantic change: policy can only narrow/escalate/deny, never weaken (M-E11).

## Blocker dispositions realized (s2)

| Blocker | MVP substitute in this module |
|---|---|
| 1 grant/side-effect-policy schemas | `GrantView` (`GrantSnapshot`) + `PolicyView` consumed by A26/A27 |
| 2 approval-record contract | `ApprovalStore` + approval fixtures, digest-bound at A29 |
| 3 Windows permit-store authenticity | in-process atomic MOCK `PermitStore` (CAS/epoch/state machine); real IPC/ACL/crash -> i38 |
| 4 per-tool target/effect profiles | generic resolver/effect INTERFACES (`stores.PROFILES`); Windows reparse/ADS depth -> i38 |
| 5 executor/validator status | mock structured executor status + mock validator/status store |
| 6 freshness policy | latest-current-only (packet.current + corpus_version equality) |
| 7 non_execution activation | NOT done; the MVP proves deterministic denial while `non_execution=true` |
| 8 canonical parser/lib ownership | this module owns the ONE implementation in `canon.py` |
| 9 constant-failure + security log | CONSTANT denial + bounded in-process `SecurityLog`; production log -> i38 |
| 11 tool-health | mock `HealthStore` |
| 12 elevated promotion path | proven unreachable from the ordinary model path (U-AUTHORITY / M-A07) |
| 13 evidence-vs-selection | realized as the normative clarification (evidence cannot expand eligibility/authority) |
| 14 real-module integration | this module owns it; runs the real #36/#37/#40 (0.7.0) chain (see `integration.py`) |

## Mutation-kill matrix (s8.6) -- 66/66 killed

Every `M-A01..M-E36` is killed by >=1 deterministic test (green on the reference impl, red on the mutant) in
`tests/mutations.py`. The mutations are wired as an in-process seeded-defect switch (a `frozenset` of M-* ids
threaded through the monitor/stores/executor); the reference implementation is the empty set. `M-S06`, `M-E05`,
`M-E06` (per-tool/OS resolution depth) and `M-E26`, `M-E28`, `M-E29`, `M-E32` (real permit-store IPC/crash depth)
are killed at the MVP/logical level; their production Windows/OS enforcement is depth-STAGED to i38
(Blockers 3/4). No `M-*` is silently skipped.

## Universal properties (s8.1-8.4)

`tests/properties.py`: U-AUTHORITY (authority-config digest invariant under untrusted mutation + issued-permit
trusted-origin closure), U-SCOPE (permit targets/effects within one effective namespace; scope violation ->
constant bytes + zero permit delta + empty state diff), U-ROLE (no Untrusted/Request -> Authority path; no
proposal -> executor path; completion only via allowlisted trusted status), U-EFFECT (every state diff maps to
exactly one consumed digest-matching non-reused permit; no valid permit -> empty state diff).

---

## i38 FULL GATE -- the 7 frozen red-team amendments (contract s6, worker P01-GATE-FULL-i38)

This module was extended from the i37 MVP to the full P0-1 gate. `action_authz` VERSION `0.2.0`.
The i38 build reported `p0_1_gate_status = pass`, but the couriered frontier AS-BUILT re-review
(`research/2026-08-06-i38-p01gate-asbuilt-redteam.md`, D-0107) returned **FAIL -- over-claimed** and the
gate was walked back to `incomplete`. The 7 as-built findings are CLOSED in i39 (VERSION `0.3.0`); see
"## i39 FULL GATE (HONEST PASS)" below. `build_status = build_complete` and `activation_status =
prohibited` were UNCHANGED throughout and deny-by-default held.

1. **Result taxonomy (amendment 1).** `tests/run_suite.py` emits `build_status` / `p0_1_gate_status`
   (not_run|incomplete|pass|fail) / `activation_status` and lists every s8.7 criterion as
   pass|fail|not_run|not_applicable. `build_complete` never implies `pass`; a skipped family, unrun fuzzer,
   surviving mutation, or absent real-chain test => `incomplete`.
2. **Test-facing views (amendment 2).** The `GrantView`/`PolicyView`/`ApprovalView` + status/validator view
   the monitor consumes at A26/A27/A29/U-ROLE are the frozen test interfaces (see s58-70 above + `stores.py`).
   Production storage schemas stay activation-gating and must prove byte-equivalence to these at activation.
3. **Executor TOCTOU order (amendment 3).** `boundary.MockExecutor._run_permit` now: verify immutable permit
   -> ATOMIC claim -> re-read mutable epochs (manifest/artifact/revocation) -> re-resolve dynamic targets AFTER
   claim -> bind to the re-resolved canonical identity -> verify before the first effect -> else
   `rejected_no_effect` (empty diff, permit not retriable). Claiming BEFORE re-resolve closes the executor-side
   substitution window (red-team Finding 3). M-E29 substitution is killed with the drift applied post-claim.
4. **Completion binding (amendment 4).** Completion leaves are bound to their subject (task/action/permit/object)
   and evaluated only over allowlisted trusted status; the contract is selected by the authentic packet's task.
   M-E36 (status from another task/action) and M-S10 (out-of-scope status) are decidable and killed.
5. **Oracle matrix (amendment 5).** `tests/oracle_matrix.py` commits one row per mandatory mutation naming its
   INDEPENDENT observable surface (decision + permit-store delta / caller bytes / effect ledger / completion
   result / trust-class origin / no_path capability), never trace-presence alone (red-team Finding 5).
6. **R-1 diagnostic role isolation (amendment 6).** R1-AUTH-1/R1-ROLE-1: the #40 0.8.0 router stage-trace is a
   non-authoritative diagnostic. New mutation **M-R11** (cast the router stage-trace into evidence coverage) is
   killed at A31; fixture F3b proves the router carrier denies. No packet field is reopened.
7. **Split Blocker 9 (amendment 7).** Build-gating: constant caller bytes across distinct denial stages (M-S08,
   fixture F6b) + no attacker payload on the ordinary log (M-S09). Production ACL/retention/timing equalization
   stays activation-gating; the suite claims constant bytes + no deterministic branch/step oracle, not the
   absence of all timing channels.

**Promoted from i37 staging:** the full 10-family corpus (families 3,4,5,8 added), the fixed-seed mutational
fuzzer, M-R11, and the complete kill matrix. **Real chain:** the 4 authentic #40 0.7.0 outputs deny at A06;
capturing an authentic 0.8.0 routed packet is recommended at fold (the 0.8.0 flat compile is byte-identical to
0.7.0; the 0.8.0 router carrier is proven inert here via F3b/M-R11).

---

## i39 FULL GATE (HONEST PASS) -- the 7 as-built red-team findings CLOSED (worker P01-GATE-COMPLETE-i39)

`action_authz` VERSION **`0.3.0`** extends 0.2.0 to a TRUE `p0_1_gate_status = pass`. Suite 308/308 on TWO
byte-identical runs; `build_status = build_complete`, `activation_status = prohibited`; `non_execution:true`
holds; nothing is action-capable. Governing spec: `research/2026-08-06-i38-p01gate-asbuilt-redteam.md`
(the 7 findings, each mapped below). No frozen MEMORY_CONTRACT / CONTEXT_PACKET_CONTRACT field is reopened;
every change is additive at the action layer.

**Finding 1 -- obligation oracle matrix (`tests/oracle_matrix.py`).** Rebuilt from one-row-per-mutation to
one EXECUTED row per OBLIGATION: every A01-A36, Boundary A1-A7 / B1-B4 / C1-C6 / D1-D8, U-AUTHORITY/SCOPE/
ROLE/EFFECT, AND every M-mutation -- 141 rows total. Each row carries `{obligation_id, fixture_id,
mutant_or_fault_id, baseline_expected, observable_surface, independent_oracle, expected_fault_difference}`
and a status `pass|fail|not_run`, decided on a SEPARATE independent surface (decision + permit-store delta /
caller bytes / privileged audit event / model-facing caller_result / effect ledger / canonical digest /
completion result / trust-class capability / static call-graph) -- never check-trace presence. A35/A36 are
decided on their OWN surfaces (the model-facing caller_result and the privileged security log). `no_path`
(Untrusted/Request -> Authority) uses BOTH an unforgeable authority-constructor capability AND a static
import/call-graph scan proving the ordinary monitor path makes zero `authority_construct(` calls. `run_suite.py`
GATES `p0_1_gate_status` on completeness: ANY `not_run` (or `fail`) => `incomplete` (criterion
`11_obligation_oracle_complete`).

**Finding 2 -- real #40 0.9.0 authentic chain in the suite (`tests/integration.py`).** Captured authentic
#40 **0.9.0** ROUTED + working-memory-hydrated packets (`fixtures/real_packets/m40_090_{routed,routed_adv,
flat}.json`; provenance in that dir's PROVENANCE.md) produced by the REAL committed #40 0.9.0 over the real
#36 tree + #42 store. The suite OWNS + RUNS both modes: (1) AUTHENTIC `non_execution=true` -> A06 DENY,
constant caller bytes, no permit, no diff; (2) an explicit TEST-ONLY `non_execution=false` variant that
PRESERVES the real routing trace / hydrated working_memory / working_state_version / evidence / packet
identity and REACHES A09/A11/A30/A31 + completion (PERMIT bound to the real packet_id, executed through
Boundary D, completion evaluated via packet_id). Adversarial `routed_adv` (authority-shaped working memory,
cross-ns stage-trace, injected control-plane) with valid boundaries yields a BYTE-IDENTICAL decision +
canonical digest. Criterion `14_v090_authentic_chain_in_suite`.

**Finding 3 -- byte-exact test-facing views (this doc + `tests/views_golden.py`).** The five CLOSED test-view
schemas are specified byte-exactly below and pinned by canonical digest; `views_golden.py` runs
MANUALLY-DERIVED golden vectors through the ACTUAL matchers so the contract is independently DECIDABLE
(37 vectors). SCHEMA_NOTES.md is the CANONICAL definition (contract s7); the implementing source is
`action_authz/stores.py` (GrantSnapshot.match / PolicyView.apply / ApprovalStore / StatusStore) +
`action_authz/boundary.py` (MIN_COMPLETION_SCOPE).

- `lifeorch.grant_view/0.1-test` (digest `c956a0ffea3ff7f6411adb6f43e54193bc103e9185b287b670a0311630bfe486`).
  Closed fields + types: `grant_id:id`, `tool_id:nsid`, `operation:nsid|"*"`, `action_namespace:nsid`,
  `allowed_target_ids:array<id>`, `effect_classes:array<nsid>`, `max_quantity:map<nsid,uint63>`,
  `externality_max:enum{local,private_external,public_external}`, `risk_ceiling:uint{0..4}`,
  `validity_from:uint63`, `validity_to:uint63`, `approval_mode:enum{none,policy_dependent,always}`,
  `scopes:array<nsid>`, `limits:array<{limit_id:nsid,max_value:uint63}>`. Canonical serialization = canon.py
  (code-point-sorted keys, integer-only, one trailing LF). MATCHING ALGORITHM (ordered, per grant in the
  snapshot, revoked grants EXCLUDED): (1) `tool_id ==`; (2) `operation ==` (no `"*"` wildcard on the ordinary
  path); (3) `action_namespace ==` the canonical action's single namespace; (4) validity window
  `validity_from <= now < validity_to`; (5) target closure: `resolved_target_set` canonical ids SUBSET of
  `allowed_target_ids`; (6) effect closure: every derived effect's class in `effect_classes` AND
  `quantity <= max_quantity[class]` (limit intersection = MIN) AND `externality_rank <= externality_max` AND
  `effect_risk_class <= risk_ceiling`. A grant that fails ANY dimension does not match (CONJUNCTION within a
  grant). Grants are ALTERNATIVES across the set (union of covered `scopes`). CLOSED matcher result:
  `(sorted_unique matched_grant_ids, ok)`; `ok = matched != [] AND required_permission_scopes SUBSET of the
  union of matched scopes`. Empty grant array, no covering grant, or an uncovered required scope => `ok=False`
  (deny). Malformed/unknown/ambiguous grants never widen: absent => deny.
- `lifeorch.policy_view/0.1-test` (digest `7244a9de66d790d5aeb5e9d3806fc7d451ccafd47f8573b5d04a656b69cc9f00`).
  `policy_ref:id`, `epoch:uint63`, `current:bool`. apply(): any `public_external` OR `irreversible` derived
  effect => `effective_risk >= 3` AND `approval_requirement = always`; otherwise the base risk/approval are
  preserved. Policy may ESCALATE or DENY, NEVER weaken: `effective_risk >= base_risk` and
  `approval_rank(effective) >= approval_rank(base)`.
- `lifeorch.approval_view/0.1-test` (digest `c09474ef17d93957b3ae5e0fe99e188c8e463baa605768da287c4f26fccf5ce8`).
  `approval_ref:id`, `canonical_action_digest:sha256`, `task_id:id`, `namespace:nsid`,
  `manifest_version:uint63`, `manifest_digest:sha256`, `grant_snapshot_ref:id`, `state:enum{approved,...}`,
  `revoked:bool`, `expiry_unix_ms:uint63`. A29 accepts an approval ONLY on EXACT equality of
  `canonical_action_digest` + `task_id` + `namespace` + `manifest_version` + `manifest_digest` +
  `grant_snapshot_ref`, with `state == approved`, `revoked == false`, and `now < expiry_unix_ms`. Any
  mismatch/revoked/expired => not found => deny.
- `lifeorch.status_view/0.1-test` (digest `247c0ba8e8f8956c5b8112ea29496e00e5f86476cfbc0b511cc402ccf3b9240b`).
  `predicate_kind:enum{executor_status,human_approval,test_suite,artifact_hash,object_state,postcondition}`,
  `source_id:nsid`, `source_version:uint63`, `subject:map<str,scalar>`, `namespace:nsid`, `at_ms:uint63`,
  `superseded:bool`, `revoked:bool`. A status satisfies a completion leaf ONLY if `predicate_kind`,
  `source_id`, and `source_version` match, every present `subject` key equals, `now - at_ms <= max_age_ms`,
  NOT `superseded` and NOT `revoked`, and `namespace` is inside the contract's effective namespace (the ONE
  canonical `ns_permitted`). Otherwise indeterminate.
- `lifeorch.validator_view/0.1-test` (digest `fe277edda1c368b85d26a787ec562a1715e07640ad58c68acabd50f168e5bd6c`).
  The per-leaf-kind MINIMUM completion scope: `executor_status:{permit}`, `state_diff:{permit}`,
  `artifact_hash:{action,object,permit}`, `test_suite:{action,object}`, `object_state:{object}`,
  `human_approval:{approval}`, `postcondition:{action,permit}`. Resolution = contract via the immutable
  `packet_id`; each leaf's subject is DERIVED FROM THE PERMIT (task/cad/permit_id/object/approval per scope),
  never from the contract's own text; a leaf whose declared `completion_scope` is weaker than its minimum, or
  whose derived binding is unavailable, => indeterminate.

**Finding 4 -- completion binds via the immutable packet_id (`action_authz/boundary.py`,
`evaluate_completion_via_permit`).** The completion evaluator resolves the contract ONLY through the permit's
immutable `packet_id` (`Stores.completion_contract_for_packet`), verifies the contract's self-digest +
`packet_id` + `task_id` + the IMMUTABLE binding stamped into the permit at A34
(`Stores.completion_binding_for_packet`), and enforces the per-leaf minimum scope above. There is NO
current-contract-by-task lookup on the reference path (M-E36 is the by-task substitution defect). Every
substitution -- cross-action, cross-permit, wrong object, old-contract-vs-new-packet, tampered content,
omitted binding, wrong validator version, superseded status -- resolves to `indeterminate`
(`tests/completion_binding.py`, 11 vectors). Criterion `13_completion_packet_binding`.

**Finding 5 -- Boundary D re-reads ALL mutable epochs (`action_authz/boundary.py`,
`MockExecutor._run_permit`).** After the atomic claim the executor re-reads grant (epoch/current/revocation),
side-effect policy (epoch/current), approval (revocation/expiry), manifest + installed artifact, tool health,
permit-store epoch, and packet/status currentness, all against the ISSUE-TIME snapshot captured at A34
(`PermitStore.record_issue_snapshot`); targets are re-bound to the UNFORGEABLE captured
`resolution_proof_digest` handle (the name is never re-resolved). Any post-claim drift =>
`rejected_no_effect`: a TERMINAL permit + an EMPTY independent effect ledger. `oracle_matrix.py` runs a
post-claim mutation PER epoch (Boundary-D3 rows). Real Windows stable-handle / reparse / crash race-freedom
remains ACTIVATION-gating (recorded; the abstract epoch model is what the logical gate owns).

**Finding 6 -- R1-ROLE-1 sink matrix (`tests/role_matrix.py`, monitor `_rc_launder` hooks).** M-R11 is
generalized to a parameterized matrix over EVERY sink -- evidence / evidence_requirement / coverage_result /
packet_disposition / control_plane / grant / policy / approval / health / TrustedStatus / completion / target
/ effect -- for BOTH carriers (the router stage-trace AND the hydrated working memory): 26 (carrier x sink)
kills, each run under the TEST-ONLY `non_execution=false` path so A31 + completion are REACHED. The reference
monitor never reads a diagnostic/working carrier into any sink; each `M-RC-<CARRIER>-<SINK>` defect routes it
into exactly one sink and is killed. Criterion `12_role_sink_matrix`.

**Finding 7 -- independently-auditable evidence bundle (`tests/report.py`, `tests/p01gate.py`).** `run_suite`
emits `tests/report/` : `report.json` (taxonomy + every criterion + both-run signature + section counts +
mutation/role matrices + integration + fuzzer + completion + p01gate), `oracle_matrix.json` (all 141 rows),
`fixture_manifest.json` (per-fixture canonical sha256 + family map + the real-packet hashes/provenance),
`mutation_defs.json` (the registry + the mutations.py source digest), `source_digests.json` (sha256 of every
module + test source; the tree digest), and `MANIFEST.json` (index + bundle digest). The bundle is
DETERMINISTIC (byte-identical on re-run). `p01gate.py` is a REAL, blind, independent second implementation of
the canonical surface (a hand-rolled serializer/parser/digest/ns predicate sharing no code with canon.py);
its differential harness proves BYTE-EQUIVALENCE to canon over the corpus (criterion
`8_one_canonical_implementation` is now backed by a shipped impl, not an assertion).

**Result taxonomy (unchanged discipline).** `build_status = build_complete | p0_1_gate_status = pass |
activation_status = prohibited`. The pass is a DESIGN gate: `non_execution:true` holds and Blockers 3/4/6/7 +
the activation portions of 5/9 remain ACTIVATION-gating. An honest INCOMPLETE still beats a false PASS -- any
`not_run` obligation, unkilled mutation, unrun family/fuzzer, absent 0.9.0 chain, failed role-sink kill,
completion-substitution leak, view-golden drift, or p01gate divergence forces `incomplete`, never `pass`.

---

## i40 EXACT CLOSURES (VERSION 0.4.0, worker P01-EXACT-CLOSURE-43-i40)

`action_authz` VERSION **`0.4.0`** builds the 7 per-finding EXACT CLOSURES from the i39 as-built
RE-REVIEW (`research/2026-08-06-i39-p01gate-recheck-redteam.md`, D-0109, which returned FAIL --
`p0_1_gate_status=pass` over-claimed a SECOND time). No frozen MEMORY_CONTRACT / CONTEXT_PACKET_CONTRACT
field is reopened; every change is additive at the action layer.

**THE GATE-STATUS RULE (M2-D / D-0110 -- non-negotiable).** The worker does NOT self-report pass.
`p0_1_gate_status` stays **`incomplete`** in EVERY emitted artifact (runner output, this doc, report JSON,
status fields). The claim is carried by per-finding `exact_closure_built: true|false` flags + the suite
evidence; the ORCHESTRATOR ratifies s7 ONLY when the independent as-built re-review returns PASS. Suite
**334/334** double-run byte-identical; **149** obligation rows (NOT_RUN=0); **30** role-sink kills;
67/67 mandatory mutations; fuzzer 400/0; Finding-7 empty-dir self-verification reproduces the bundle
byte-identically. `build_status = build_complete | activation_status = prohibited`; `non_execution:true`
holds; A06 denies every authentic packet; nothing is action-capable.

**Finding 1 -- completion IMMUTABLE at issue (`boundary.evaluate_completion_via_permit`, `stores.py`).**
The issue-time completion binding is MANDATORY (fail-closed when absent). On the reference path REQUIRE:
`cc.packet_id` PRESENT and `== permit.packet_id`; the contract self-digest; `task_id`; and the issue-time
binding's `{completion_contract_id, contract_version, contract_digest}` ALL matching the resolved
contract. A permit issued with NO contract records the immutable `NO_COMPLETION_CONTRACT` sentinel
(`stores.completion_binding_for_packet`) and can NEVER become completable via a later contract insertion.
Vectors: late insertion, missing packet_id, deleted binding, sentinel, binding-changed-after-issue.

**Finding 2 -- Boundary-D POST-claim hook (`boundary.MockExecutor._run_permit`).** A deterministic
`post_claim_hook` fires immediately AFTER the atomic claim and BEFORE every recheck. The issue snapshot is
MANDATORY (absence -> `D3_no_issue_snapshot`, fail closed). One fault per independent mutable surface (14:
grant epoch / grant currentness / MATCHED-grant revocation / policy epoch / policy currentness / approval
revocation / approval EXPIRY / manifest disappearance / installed-artifact drift / health drift /
permit-store epoch / packet currentness / packet non_execution / target identity drift). Every row:
`accepted==false AND state_diff==[] AND permit_state==rejected_no_effect (TERMINAL) AND a 2nd attempt
rejected`. The effect ledger CONSUMES the captured target handle (round-3 upgrade below: a distinct
one-shot `TargetHandle` via `apply_effects_through_handles`), never a blind `authorized_effect_set` copy;
target mutation tested BOTH before and after claim.

**Finding 3 -- role matrix over ALL 15 frozen sinks (`tests/role_matrix.py`, `monitor.py`).** Adds the two
omitted sinks: `manifest` (a carrier attesting installed-artifact currentness at A12 AND A32) and
`working_memory` (a carrier altering the trusted task binding at A05 -- the prohibited
working_memory->working_memory conversion). 15 sinks x 2 carriers = **30** (carrier, sink) kills, each
seeded defect modifying ONLY its sink, run under the test-only `non_execution=false` path.

**Finding 4 -- GrantView limit algebra IMPLEMENTED + pinned (`stores.GrantSnapshot.match`,
`effective_permit_limits`).** `grant_effect_limit(g, cls) = min(max_quantity[cls], every limits[] entry
with limit_id==cls)`; duplicate ids all apply (min); malformed / ambiguous / unknown-field limit entries
FAIL CLOSED (the grant is excluded). `match` returns the CLOSED shape `(matched_grant_ids, ok,
effective_grant_limits)` -- the global MIN over the MATCHED (alternative, scope-union) grants. A23:
`effective_limit[cls] = min(manifest resource ceiling, grant-derived, policy, approval)` per effect class.
The ordered algorithm + closed result shape are pinned AS DATA (`GRANT_MATCH_ALGORITHM`, digest
`ff5f66bd...`); 8 golden-vector classes. The FROZEN MIN intersection rule is UNCHANGED (this is its
implementation, NOT an amendment) -- no freeze amendment required or made.

**Finding 5 -- suite-owned EXACT context_packet/0.2 adapter (`tests/adapter_090.py`).** Preserves
corpus_version (A07 EXERCISED -- the `current_corpus_version=None` bypass is GONE), does NOT rewrite the
packet's grant-snapshot identity (the trusted GrantSnapshot is registered under the packet's OWN ref), and
preserves the complete routed stage-trace / working-memory envelope+items / evidence / provenance / ns
metadata / state_version as DATA (the routing_present/working_present two-boolean reduction is RETIRED).
The overlay flips ONLY `non_execution`. Benign + adversarial 0.9.0 run through THIS seam; carriers proven
INERT at EVERY R1 sink (decision + canonical digest invariant to carrier presence).

**Finding 6 -- decisive oracles (`tests/callgraph.py`, `tests/render.py`, `monitor.py`).** `no_path` is a
real stdlib-`ast` import/CALL-GRAPH over EVERY action_authz module (canon/schemas/stores/monitor/boundary),
resolving imports/aliases/attribute calls with over-approximated unresolved edges, proving
`canon.authority_construct` UNREACHABLE from the ordinary entry points, plus an AST-verified guard (source
-string pattern counting is retired). A36 asserts EXACTLY ONE correctly-shaped bounded audit event with
NEW audit-emission DELETION (`AUDIT-DELETE`) and CORRUPTION (`AUDIT-CORRUPT`) faults (absence FAILS, not the
secure baseline). Boundary-B rows MUTATE the ACTUAL render path (`render.render_packet`) and observe
rendered-bytes / order / delimiter deltas -- defense-in-depth; Boundary C stays decisive.

**Finding 7 -- complete runnable review tree + empty-dir self-verify (`tests/selfverify.py`,
`run_suite.REVIEW_PACK_FILES`).** run_suite verifies pack completeness (every required file present).
`selfverify.py` copies the COMPLETE tree into an EMPTY temp dir, runs the documented command there, and
requires exit 0 + the full suite result + all 150 oracle rows + identical source/fixture digests + a
BYTE-IDENTICAL report MANIFEST (`bundle_digest`); the transcript is committed at
`tests/report/self_verify.json` (deliberately NOT part of the byte-compared bundle).

## i41 round-3 ratification closures (0.4.0 -> 0.5.0; research/2026-08-06-i40-p01gate-round3-redteam.md, D-0113)

The round-3 ratification review returned **FAIL** with 5 findings (F3/F6 accepted closed). F7 (complete
pack transport) is ORCHESTRATOR-owned at fold. These are the 4 WORKER-SIDE exact closures; each carries a
machine-readable `round3_closure_built.{f1_write_once_binding, f2_consumed_target_handle,
f4_toplevel_grantview, f5_lossless_adapter}` flag alongside the (unchanged, still-true) i39
`exact_closure_built` finding_1..7. **M2-D holds: `p0_1_gate_status` stays `incomplete`; the round-4
re-review PASS is the only ratification path.** No frozen contract field was reopened (none needed it).

**Round-3 F1 -- WRITE-ONCE immutable completion binding (`stores.PermitStore`).** `record_completion_binding`
is WRITE-ONCE per `permit_id`: ANY second recording attempt -- even one carrying an identical value --
raises `WriteOnceError` (fail closed), so the `NO_COMPLETION_CONTRACT` sentinel or the original binding can
NEVER be overwritten after issuance. The stored representation is PRIVATE CANONICAL BYTES (immutable);
`completion_binding()` returns a DEFENSIVE COPY (mutating it cannot reach the store). The review's reproduced
5-step overwrite sequence now fails at step 3 (the re-record). Vectors (`tests/completion_binding.py`):
sentinel-overwrite after contract insertion, valid-binding overwrite with a replacement contract,
getter-mutation, duplicate-identical recording.

**Round-3 F2 -- CONSUMED `TargetHandle` on the effect path (`action_authz/boundary.py`).** The captured
target is a DISTINCT trusted one-shot capability object (`TargetHandle`), not a digest string. The
effect-applicator API (`apply_effects_through_handles`) REQUIRES that object; the effect ledger is GENERATED
from the handle's `consume()` result (which supplies `applied_via_handle`), never from
`permit["authorized_effect_set"]`. Handles are one-shot / observably consumed (`ExecResult.consumed_handles`;
a second consume fails closed). The retired 0.4.0 blind-copy+digest-tag behavior is the MANDATORY killed
mutant **M-E37** (mutation kill matrix now **68/68**; oracle `Boundary-D3:D4_handle_consumed` asserts
observable consumption).

**Round-3 F4 -- OPERATIONAL top-level GrantView enforcement (`stores.GrantSnapshot.match`,
`_grant_view_wellformed`).** The pinned CLOSED top-level GrantView field set + exact operational types are
validated BEFORE matching; a grant with an unknown / missing / mistyped / malformed top-level field is
untrustable and EXCLUDED (fail closed) -- closing the hole where the descriptive `GRANT_VIEW` pin and the
operational matcher diverged (the reviewer's arbitrary unknown top-level key now denies). The operational
validator is pinned AS DATA (`stores.GRANT_VIEW_TOPLEVEL`, digest `cd136af2...`), its closed field set ==
the descriptive `GRANT_VIEW` pin, and it is exercised by unknown/missing/mistyped/malformed golden vectors
(`tests/views_golden.py`) + the decidable `M-GV01` skip-defect. The limit-intersection algebra + the
limits[]-ENTRY checks (`_limits_wellformed`) are UNCHANGED.

**Round-3 F5 -- LOSSLESS context_packet/0.2 adapter (`tests/adapter_090.py`).** `adapt_packet_lossless`
preserves the COMPLETE packet as canonical bytes plus a validated derived view: `identity_digest` is the
SHA-256 over the whole packet's canonical bytes, so changing ANY field is detected; the packet round-trips
byte-identically. All identity-covered CORE fields (+ top-level regions) are validated (fail closed). The
five carriers the reviewer proved inert in i40 (`identity.compiler_version`, `identity.selection_policy`,
`retrieval_provenance`, `evidence.current_state_refs`, selection-stage content) now alter the preserved
identity; per-identity-field mutation + round-trip properties run over BOTH authentic 0.7.0 (x4) and 0.9.0
(benign + adversarial + flat) packets (`tests/integration.py`). The overlay alters ONLY `non_execution`
(the preserved bytes / identity digest are unchanged).

## i42 round-4 ratification closures (0.5.0 -> 0.6.0; research/2026-08-07-i41-p01gate-round4-redteam.md, D-0116)

The round-4 ratification review returned **FAIL** with 3 remaining SUITE-BUILD findings (convergence
7 -> 7 -> 5 -> 3; **F1** and **F7** accepted CLOSED; F3/F6 + the accepted F4 limit-algebra and F2 post-claim
portions REMAIN closed). These are the 3 WORKER-SIDE exact closures; each carries a machine-readable
`round4_closure_built.{f5_realseam_lossless, f4_prevalidation, f2_ledger_provenance}` flag alongside the
(unchanged, still-true) i39 `exact_closure_built` finding_1..7 and the D-0113 `round3_closure_built`
f1/f2/f4/f5. **M2-D holds: `p0_1_gate_status` stays `incomplete`; the round-5 re-review PASS is the only
ratification path.** No frozen contract field was reopened (the review confirmed none needed it).
`tests/report/report.json` `as_built_counts` is the SINGLE SOURCE of the as-built suite counts (no hardcoded
summary that can drift); the round-5 pack derives its numbers FROM report.json.

**Round-4 F5 -- REAL-SEAM losslessness (`tests/adapter_090.py`).** `adapt_packet_lossless()` was already
correct, but the ACTUAL trusted construction path `build_trusted()` BYPASSED it: it called
`adapt_packet_view(pkt)` + `full_meta(pkt)` on the RAW packet and stored only those reduced structures, never
obtaining/retaining the `PreservedPacket`, its canonical bytes, or its whole-packet identity digest -- so two
materially different authentic packets still collapsed at the monitor-facing seam (the reviewer proved
`identity.compiler_version`, `identity.selection_policy`, `retrieval_provenance`,
`evidence.current_state_refs`, and `selection.stages` each yielded an identical `PacketView` / packet
metadata / authorization outcome / CAD through `build_trusted`). CLOSURE: `build_trusted()` now BEGINS with
`adapt_packet_lossless()`, derives the `PacketView` AND `packet_meta` ONLY from the preserved / re-parsed
packet, and BINDS the whole-packet canonical identity digest into trusted state that cannot be discarded
before consumption -- the trusted `PacketView.content_digest`, `packet_meta["packet_identity_digest"]`, and
`st.packet_identity`. `adapt_packet_lossless()` itself now also derives its view/meta from the re-parsed
`complete` packet (provenance flows from the preserved bytes). The per-field mutations AND the 5 named probes
are re-run THROUGH the end-to-end `build_trusted` path and required to yield EITHER fail-closed OR a
DISTINGUISHABLE trusted representation (different `PacketView.content_digest` AND `packet_meta` identity)
(`tests/integration.py`). No `CONTEXT_PACKET_CONTRACT` field change is required.

**Round-4 F4 -- grant PRE-VALIDATION before any operational read (`stores.GrantSnapshot`, `monitor.authorize`).**
`_grant_view_wellformed()` and `match()` were correct, but `grant_namespaces()` dereferenced raw
`g["action_namespace"]` / `g["grant_id"]` WITHOUT validation, and the monitor calls `grant_namespaces()` at
**A11 -- BEFORE `match()`** -- so removing `grant_id` or `action_namespace` raised an uncaught `KeyError`
instead of a deterministic constant DENY. CLOSURE: ONE shared validated-grant iterator
(`GrantSnapshot._valid_grants`) now backs BOTH `grant_namespaces()` and `match()`; no raw grant field is
dereferenced before the pinned CLOSED top-level GrantView validation. A grant that is unknown / missing
grant_id / missing action_namespace / mistyped / malformed is EXCLUDED, so the A11 read fails closed to
constant DENY (A11_empty_namespace). END-TO-END `authorize()` vectors (not just direct `match()` calls) assert
CONSTANT DENY + no exception + no permit + no state diff; `M-GV01` remains the decidable skip-defect proving
the A11 pre-validation is load-bearing (a missing-grant_id grant raises ONLY under M-GV01)
(`tests/views_golden.py`). The validator pin (`GRANT_VIEW_TOPLEVEL`) + the accepted limit-intersection algebra
are UNCHANGED.

**Round-4 F2 -- HANDLE-BOUND ledger provenance (`action_authz/boundary.py`).** One-shot `TargetHandle`
consumption was genuine (round-3, CLOSED), but the effect ledger still ORIGINATED from an
`authorized_effect_set` copy: the executor began with `actual = list(permit["authorized_effect_set"])` and the
applicator built each atom via `atom = dict(e)` from that supplied permit effect -- authorized-effect COPY +
handle consumption, not an independently-produced result. A stronger successor defect (consume the handle,
IGNORE `consume()`'s return, blind-copy the authorized effect, read the digest off the handle) still passed
`sec_e37` / `Boundary-D3:D4_handle_consumed`. CLOSURE: the mock applicator now CONSUMES the `TargetHandle`
TOGETHER WITH the operation's canonical semantics (`derive_operation_effects` runs the installed manifest
effect-classifier over the permit's canonical arguments + bound targets -- NOT `authorized_effect_set`) and
ITSELF RETURNS the effect atoms; each atom's applied identity -- `canonical_target_id` AND `applied_via_handle`
-- comes from the handle's `consume()` RESULT, where `applied_via_handle` is a FRESH one-shot CONSUMPTION proof
(`handle_consumption_proof`), NOT the raw captured digest. `permit["authorized_effect_set"]` is now the
authorization BOUND/COMPARISON against the RETURNED result (`_effects_within_bound`), never the source
template. The successor mutant -- consume the handle but DISCARD the applicator result and blind-copy
`authorized_effect_set` (raw digest, no consumption proof, no `canonical_target_id`) -- is the MANDATORY killed
mutant **M-E38** (mutation kill matrix now **69/69**; oracle `Boundary-D3:D4_ledger_provenance` +
`sec_e38`). M-E37 (no-consume blind copy) stays killed; real OS handles remain activation-gating.
