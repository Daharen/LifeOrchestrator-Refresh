# i62 -- PB-9 CLOSE TRANSACTION CONTRACT: HARDENED (authoritative)

Authoritative i62 deliverable. Supersedes the design draft (`...-contract.md`) by folding the 12 red-team hardening
items (`...-redteam.md`). The INV set (s5) + manifest requirements (s2-s3) are FROZEN; i63-i67 build against them;
the `ops/close-txn/` validator groundwork derives from them. Governing model (D-0155): **Frontier Agent in the
Deterministic Loop** -- routine close NOT human-gated (bounded audit projection + two by-exception gates:
historical-record deletion; correction-exhausted escalation). LOCAL canonical; GitHub an end-of-iteration mirror.

Scope: **i62 = this contract + red-team + schema/validator groundwork.** i63 materializer+freshness; i64 impact
detection; i65 validation stages + bounded correction; i66 mirror reconciliation; i67 fault-inject/cutover. Specifies;
does not implement i63+.

## 1. Problem + ownership
Today's close is a hand-sequenced non-atomic chain that can HALF-LAND, is ORDER-FRAGILE, has NO idempotence, uses
MANUAL impact, and pushes mirrors UNPROTECTED (design contract s1). PB-9 makes it ONE manifest-driven resumable
idempotent transaction. **Owns:** the atomic application of a DECLARED op set -- apply content changes, rebuild affected views, run
validators, SHIP via executor/`dev.ship`/git-lease, reconcile mirrors. **Does NOT own** authoring semantic content
(D-entry prose, CURRENT_STATE text, reaffirm selection) = Frontier judgment supplied as `frontier` ops; the engine
derives only mechanical ops (view rebuilds, iteration/next + cold-boot stamps, monitor rows).
**[CB-DERIVE]** `semantic_owner:deterministic` MEANS engine-reproducible: the engine re-derives the payload and
fails closed on mismatch; a non-reproducible op is `frontier` and needs a task spec. **Declared ownership +
evidence-based impact**; a required-doc iteration marker never licenses a touch-every-doc sweep.

## 2. Manifest (contract-level; i63 freezes the JSON schema -- see `ops/close-txn/schema/`)
- **header:** `transaction_id` (SEAL key), `iteration`>0, `base_head` (plan anchor), `ledger_ref` MANDATORY
  (D-0158), `min_bounded_fraction`, `created_by`, `model_provenance`, `governing_model`.
- **operations[]:** `op_id` | `kind` in the FROZEN taxonomy {`append`,`replace_section`,`create`,`view_rebuild`,
  `validator`,`ack`,`mirror_reconcile`,`stamp`} -- **[CB-LEDGER]** `replace_doc` REMOVED; whole-file rewrite of an
  append-only/monotonic target FORBIDDEN (INV-12) | `target` | `region_anchor` (append/replace_section) **[CB-ANCHOR]**
  a stable collision-checked anchor (unique fenced marker/pinned line), NEVER a byte offset; `append` anchors above
  the insertion point (invariant under prior in-manifest appends) | `precondition`/`postcondition`
  fingerprints (s3) | `payload_ref` (+ `eol: crlf|lf` on content ops) | `depends_on[]` (the ordering DAG) |
  `semantic_owner`. **[CB-GRADE]** every `frontier` CONTENT op carries a task spec AND a dependent
  independent-grader `validator` edge (claim-vs-evidence); its postcondition is that grader verdict, never a
  self-hash.
- **journal (runtime):** append-only per-op {state, observed_pre/post, corrections, evidence_ref} + a txn record
  {base_head, corrections_total, staging_ref, final_head}, stored OUTSIDE the mutated tree; resume-persistent
  correction counters **[CB-TERM]**.

## 3. Fingerprint domain (normative) [CB-FP]
- **F-1** `sha256` over CANONICAL NATIVE ON-DISK BYTES via native git only (`git show :path`/`hash-object`), NEVER a
  mount/`device_stage_files` snapshot (assert snapshot oid vs native, else `stale-snapshot`).
- **F-2** RAW, no EOL normalization -- EOL is identity, so an LF->CRLF fix is a real delta (defeats the false
  already-applied skip); each content op declares `eol`.
- **F-3** a `frontier` content op carries NO plan-time postcondition sha (never a self-hash) -- computed on-device
  at APPLY, journalled, frozen for resume. `deterministic` postconditions may be pre-declared (engine re-derives).
- **F-4** region located by anchor, never offset (validator proves exactly-one-span). **F-5** resume recompute uses
  the same F-1..F-4 basis -> one idempotence ground truth.

## 4. Phases + recovery
`PLAN -> PRE-VALIDATE -> APPLY -> REBUILD -> POST-VALIDATE -> SHIP -> SEAL -> RECONCILE` (SEAL precedes RECONCILE,
bounding the canonical close only -- **[CB-SEAL]**).
1. **PLAN** schema-validate; assert `base_head==HEAD` (else `base-head-divergence`->replan); build+topo-sort the
   acyclic DAG; create a private staging ref at `base_head` **[CB-SHIP]**.
2. **PRE-VALIDATE** compare preconditions; target==postcondition -> idempotent skip; run the PRE-RENDER retrieval
   gate `--check-only`.
3. **APPLY** content ops onto the STAGING REF in DAG order under the git lease; `append` re-reads the target from
   the staging ref at commit (never a whole-file working-tree snapshot -> defeats the stale-base clobber);
   recompute+assert+journal.
4. **REBUILD** only views the applied ops touch (declared `depends_on`; i64 derives). **[CB-VIEW]** canonical-bytes
   rebuilds assert DOUBLE-RUN byte identity (independent processes, pinned determinism knobs), volatile embedded
   sha/freshness EXCLUDED from `--check` and written by a post-cutover `stamp` op.
5. **POST-VALIDATE** validators vs the staging ref: doc-commit-gate (+ no-truncation **[CB-LEDGER]**),
   frontdoor-gate, retrieval `--gate`, close-consistency-check, 0-stale on boot_read, the CB-GRADE grader verdicts,
   and the INBOUND-REFERENCE COMPLETENESS assertion **[CB-IMPACT]** (INV-9). Nothing touched `main` -> a failure
   leaves canonical unchanged.
6. **SHIP (atomic cutover) [CB-SHIP]** one git lease held across all of SHIP; re-assert `HEAD in {base_head} U {own
   staging commits}` (else re-run REBUILD+consistency vs new HEAD); ff `main` to the staging tip (final map commit
   = tip); VERIFY native HEAD (D-0072); ship-false-negative recovery strict-ordered (present -> never retry; absent
   -> clear lock -> retry); preemptible lease + wedge detector. 6b. post-cutover `stamp` writes the real sha.
7. **SEAL [CB-SEAL]** assert PLAN..SHIP all-verified (mirror ops EXCLUDED); write the SEAL {txn_id, iteration,
   final_head, evidence} -- the idempotence marker.
8. **RECONCILE (post-SEAL, independent)** (a) Project FULL reconcile **[CB-MIRROR-DEL]** (apply delete/rename; assert
   Project set == core-docs set by path+hash). (b) GitHub **[CB-MIRROR-FF]** fetch remote, require it an ANCESTOR of
   the last mirrored `final_head`, `--force-with-lease`, verify remote==local; foreign commits ->
   `mirror-foreign-commits`, never auto-clobber. A failure = `deferred`; the local close stays SEALED (INV-6).

**Resume (4.9):** re-run the `base_head` assertion FIRST (pause + HEAD move -> replan, not a mixed-base ship); then
journal + F-1..F-5 recompute; first non-verified op is the resume point; a crash between cutover and journal is
recovered (the ff is observed). **Failure taxonomy** (each with the recovery above): base-head-divergence,
precondition-divergence, stale-snapshot, apply-failure, rebuild-drift, validator-failure, ship-false-negative,
wedge-deadlock, correction-exhausted, mirror-divergence, mirror-foreign-commits, crash.

## 5. Invariants (FROZEN)
**INV-1** no half-land before the ff-cutover. **INV-2** atomic cutover = one ff of `main`; SEAL records
`final_head`. **INV-3** idempotence over the s3 basis; a SEALED txn re-run is a no-op. **INV-4** ledger fail-closed.
**INV-5** declared-impact only (bounded by INV-9). **INV-6** canonical-over-mirror (mirror post-SEAL, never
gates/mutates/un-seals canonical). **INV-7** the Frontier boundary is ENFORCED (deterministic=engine-reproducible;
frontier content ops carry a task spec + independent-grader edge; human out of the routine loop). **INV-8**
fingerprint domain = s3. **INV-9** inbound-reference completeness: every core-docs referrer of an edited target is a
declared sink or 0-stale, else fail closed (LIVE cutover waits for i64 if uncomputable). **INV-10** anchor
uniqueness (exactly one span, never a byte offset). **INV-11** single-file multi-edits dependency-serialized +
non-overlapping. **INV-12** append-only protection (no `replace_doc`; no monotonic-target rewrite; no-truncation
gate; historical removal needs human authz). **INV-13** double-run determinism (pinned knobs; volatile fields
excluded + stamped post-cutover). **INV-14** bounded correction (per-op + txn budgets, resume-persistent; exhaustion
terminal ABORTED-resumable, never a live hang).

## 6. Frontier-in-the-Deterministic-Loop (correction protocol)
On a bounded semantic gap the engine emits a bounded correction task {failing op/predicate, drifted state,
constraint, postcondition}; the Frontier returns a bounded payload. Re-validation of a CONTENT correction is the
INDEPENDENT grader's claim-vs-evidence verdict, never a self-hash (the D-0107/D-0109 lesson). Scoped, journalled as
a DELEGATION-DECISION (#39 shape), bounded by per-op + `max_corrections_total`; exhaustion = `correction-exhausted`
(canonical untouched, session freed), surfaced on the audit projection -- the one by-exception human touch point.

## 7. i62 groundwork + residuals
Subsumption (design contract s8): close-refold -> REBUILD; audit gates+grader+completeness -> `validator` ops;
dev.ship+lease -> SHIP+ff; manual doc-fold -> `append`/`replace_section`; mirrors -> post-SEAL `mirror_reconcile`;
overlay+cold-boot stamps -> re-derived `deterministic` ops. **i62 ships** (`ops/close-txn/`): the FROZEN
`close_manifest.schema.json` + a fail-closed stdlib `validate_manifest.py` (INV-4/5/8/10/11/12 + CB-GRADE/CB-FP) +
examples + 26 tests -- it VALIDATES; the materializer is i63. **Residuals:** managed-ref races are GitHub-side only
(INV-6); validator/ack/stamp re-verify on resume; the grader is an LLM (claim-vs-evidence + audit projection
mitigate; i65 wires it); the double-run gate backstops an ignored determinism knob.
