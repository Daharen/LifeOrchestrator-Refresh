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
`p0_1_gate_status = pass` (204/204 suite, 67/67 mandatory mutations killed, all 10 families, fixed-seed
fuzzer, double-run byte-identity, real #40 chain). `non_execution:true` holds; `activation_status =
prohibited`. Cross-validated byte-equivalent to an independent second implementation (`p01gate`) over the
canonical parse/serialize/digest/ns surface (Blocker-8 differential check).

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
