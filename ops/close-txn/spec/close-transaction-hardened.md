# PB-9 CLOSE TRANSACTION -- HARDENED CONTRACT (authoritative, complete)

**Class: COLD BACKING (canonical, complete, selectively retrieved -- NOT a routine/bootstrap read; carries NO
ingest budget).** Owner: the close-transaction subsystem (`ops/close-txn/`). Bounded agent-facing projection: the
research digest `core-docs/research/2026-08-21-i62-close-transaction.md` (<=10 KB), which points here. Do not apply
the research-digest ingest budget to this file: completeness governs backing; brevity governs projections (see s9,
the projection/backing distinction -- INV-15).

This is the authoritative i62 deliverable. It supersedes the design draft (`close-transaction-contract.md`, this
directory) by folding the 12 red-team hardening items (`close-transaction-redteam.md`, this directory). The invariant
set (s5), the manifest requirements (s2-s3), and the projection/backing rule (s9) are FROZEN: i63-i67 build against
them; the `ops/close-txn/` schema + validator groundwork derives from them.

Governing model (D-0155): **Frontier Agent in the Deterministic Loop** -- routine close is NOT human-gated; the
human steers via a bounded management/audit projection, plus exactly two by-exception human gates named below
(historical-record deletion; correction-exhausted escalation). The LOCAL repo is canonical; GitHub is an
end-of-iteration convenience mirror, never updated midflight.

**Scope (roadmap i62-i67).** i62 = this contract + red-team + the schema/validator groundwork. i63 = the
manifest/materializer + freshness assertions. i64 = evidence-based impact detection (fingerprints + a dependency
graph + targeted-test selection). i65 = the two deterministic validation stages + bounded Frontier correction loops.
i66 = protected local->GitHub/mirror reconciliation. i67 = fault-inject, resume-from-partial, prove idempotence, cut
over. This document specifies precisely enough that i63+ can implement; it does not implement i63+.

---

## 1. The problem: the close today is a non-transactional chain

A close today is a hand-sequenced multi-step procedure (handoff s4/s7 + `ops/close-refold.ps1`):

1. Author doc content; commit named core-docs via an executor **git-lease** task through the fail-closed
   **doc-commit-gate** (append the D-entry + index row; REPLACE CURRENT_STATE sections; rewrite the handoff in place
   + snapshot the outgoing copy to `archive/handoffs/`; PROCESS_BACKLOG / MODULE_ROADMAP / AUDIT_PIPELINE edits).
   NEVER `git add -A`; named paths; per-file EOL.
2. **N7 close-refold** (`ops/close-refold.ps1`, after the last doc commit, via the executor): a fail-closed guard
   (Ledger + Iteration mandatory; a PRE-RENDER retrieval gate) -> harvest@HEAD -> verify (stale sweep) ->
   reaffirm_batch (a reviewed spec, one process) -> validate (0 errors) -> render -> render `-Check` (drift) ->
   MANAGER_VIEW regenerate + `--check` -> retrieval `--gate` (emits the retrieval-bytes-log row; fail-closed;
   `-MinBoundedFraction`) -> cross-surface `close-consistency-check.py`. Then commit `map/ + generated/ +
   MANAGER_VIEW.md + retrieval-bytes-log.jsonl` as the FINAL close commit.
3. Regenerate monitors (doc-health + retrieval); deliver the doc-health HTML.
4. Re-mirror core-docs to the Claude Project; re-push the GitHub mirror (`git push --force-with-lease origin main`,
   via the executor, D-0149).

### Failure modes this leaves live

- **Half-landing.** Many separate commits + external steps, with no single description of "this close = exactly
  these N changes." A worker bridge dying pre-push (i40), a `dev.ship` false-negative (D-0072), a stale 0-byte
  `.git/index.lock`, a crashed executor task, or a paused session can leave the repo partially closed: some docs
  updated, the map not re-folded, monitors stale, mirrors out of sync -- with no declarative way to know what
  remains or to resume safely.
- **Ordering fragility.** Overlay/claims edits must precede the re-fold; reaffirm raced across processes until
  D-0147; a corrected overlay left MANAGER_VIEW stale until D-0158. Each is a symptom of an order-sensitive,
  non-declarative close.
- **No idempotence.** Re-running after a partial failure is not guaranteed a safe no-op on already-applied steps.
- **Manual impact.** The orchestrator decides by judgment which docs/views a change touches; nothing derives the
  affected surface set or refuses a stale neighbour.
- **Unprotected mirrors.** The Project mirror and the `--force-with-lease` GitHub push are separate manual steps with
  no managed-ref/expected-old-oid protection, remote verify, or in-flight exclusion.

PB-9 consolidates all of the above into ONE manifest-driven, resumable, idempotent transaction so a close cannot
half-land, cannot silently skip, and can always be resumed to a clean verified end state -- with Frontier Agent
judgment inserted only where semantic impact cannot be decided mechanically.

---

## 2. Ownership

**The transaction OWNS** the atomic application of a DECLARED set of close operations against the canonical local
repo, as one resumable/idempotent unit: (a) apply declared content changes to named targets, (b) rebuild exactly the
generated views the applied changes affect, (c) run the declared validators, (d) SHIP via the normal executor /
`dev.ship` / git-lease path, (e) reconcile the protected mirrors (Claude Project + GitHub).

**The transaction does NOT own** authoring the semantic CONTENT of a change -- the D-entry prose, the CURRENT_STATE
replacement text, which entities to reaffirm. That is **Frontier Agent judgment**, supplied INTO the manifest as
`frontier` ops. The engine derives only the *mechanical* ops itself (view rebuilds, iteration/next + cold-boot
stamps, monitor rows).

**[CB-DERIVE] `semantic_owner:deterministic` MEANS engine-reproducible.** The engine independently re-derives the
payload of every `deterministic` op and FAILS CLOSED if the declared payload != its derivation; any op the engine
cannot reproduce is by definition `frontier` and MUST carry its bounded task spec. `deterministic` therefore means
*reproducible*, not *asserted-mechanical* -- the one-word label cannot bypass the boundary.

**Declared-ownership + evidence-based impact.** The manifest enumerates EXACTLY the paths/entities/views/mirrors a
close touches. Applicability = declared ownership + evidence-based impact. A required-doc iteration marker MAY be one
freshness signal but never licenses a touch-every-doc sweep. Because i62/i63 impact edges are DECLARED (i64 derives
them), completeness is enforced by the REBUILD-phase INBOUND-REFERENCE COMPLETENESS assertion (INV-9), not the
author's memory.

**Canonical authority.** The local repo is canonical; the Project mirror is a projection of `core-docs/`; GitHub is
an end-of-iteration convenience mirror. Mirror reconciliation never gates or mutates canonical (INV-6).

---

## 3. The close manifest (contract-level specification)

One close = one declarative JSON manifest. i63 freezes the concrete schema (`ops/close-txn/schema/`) against the
requirements here.

### 3.1 header
- `transaction_id` -- unique per close (the SEAL / idempotence key).
- `iteration` -- int > 0 (inherits the close-refold `-Iteration` guard).
- `base_head` -- the git HEAD the close was PLANNED against; the whole-manifest precondition anchor.
- `ledger_ref` -- the session retrieval ledger path, MANDATORY (inherits the D-0158 fail-closed guard).
- `min_bounded_fraction` -- the retrieval-gate threshold in force.
- `created_by`, `model_provenance`, `governing_model = "frontier-agent-in-deterministic-loop"`.

### 3.2 operations[]
Each op:
- `op_id` -- unique within the manifest.
- `kind` in the FROZEN taxonomy { `append`, `replace_section`, `create`, `view_rebuild`, `validator`, `ack`,
  `mirror_reconcile`, `stamp` }. **[CB-LEDGER]** `replace_doc` is REMOVED; whole-file rewrite of an
  append-only/monotonic target is FORBIDDEN (INV-12).
- `target` -- a path, a map entity id, a view id, or a mirror id.
- `region_anchor` (for `append` / `replace_section`) **[CB-ANCHOR]** -- a STABLE, collision-checked anchor, NEVER a
  byte offset: a unique fenced marker (e.g. `<!-- LO:SECTION <id> -->` ... `<!-- /LO:SECTION <id> -->`) or a pinned
  heading/marker line the validator proves resolves to EXACTLY ONE span. `append` anchors on a fixed marker line
  immediately above the insertion point so it is INVARIANT under prior in-manifest appends to the same file.
- `precondition` -- the s3 fingerprint of the expected prior state of the anchored region (`absent` for `create`).
- `payload_ref` -- content bytes (content ops) with required `eol: crlf|lf`; the generator id + inputs
  (`view_rebuild`); the validator id + args (`validator`); the predicate (`ack`); the mirror target + managed-ref
  expectation (`mirror_reconcile`); the derivation source (`stamp`).
- `postcondition` -- the s3 fingerprint after the op / `--check`-clean (rebuild) / exit 0 (validator) / predicate
  true (ack) / remote-HEAD == recorded local HEAD (mirror). **[CB-FP]** A `frontier` content op's postcondition sha
  is NOT carried in the authored manifest (unknowable at PLAN time; never the hash of the Frontier's own output);
  it is computed on-device during APPLY, journalled, and frozen for resume.
- `depends_on[]` -- the ordering DAG. Multi-edits to one file MUST be dependency-serialized (INV-11).
- `semantic_owner` in { `deterministic`, `frontier` } (enforced by CB-DERIVE). A `frontier` op carries its bounded
  task spec AND, if a content op, a mandatory independent-grader edge (s3.3, CB-GRADE).
- **artifact classification (s9, INV-15):** an optional `doc_class` in { `projection`, `backing` } on content ops.
  `projection` requires `budget_bytes` (its declared ingest cap) + `backing_ref` (the canonical backing it projects);
  `backing` carries NO `budget_bytes` and MUST NOT be marked a bootstrap/`boot_read` target by the close.

### 3.3 grader edges [CB-GRADE]
Every `frontier` CONTENT op (`append`/`replace_section`/`create` of prose/claims) MUST have a dependent `validator`
op whose predicate checks the CLAIM against EVIDENCE (not against the payload's own bytes), produced by an
INDEPENDENT grader (a distinct agent/model or the existing independent-grader boundary). The postcondition of the
content op is the GRADER's verdict, never `sha256(own payload)`. SEAL fails closed if any `frontier` content op
lacks a resolved independent-grader edge.

### 3.4 journal (runtime, not authored)
Append-only per-op records { `op_id`, `state` in {pending, applied, verified, failed, deferred}, `observed_pre`,
`observed_post`, `corrections` (int), `at`, `evidence_ref` } + a transaction record { `base_head`,
`corrections_total`, `staging_ref`, `final_head`, per-phase evidence digests }, persisted OUTSIDE the working tree
the close mutates (a tree reset/rollback cannot corrupt the recovery substrate). Correction counters live in the
journal so resume CONTINUES the count (never resets). Journal writes follow the effect they record and are
idempotent (keyed by op_id + observed_post).

---

## 4. Fingerprint domain (normative) [CB-FP]

The single most load-bearing fix. Every fingerprint is defined as:

- **F-1 Native bytes only.** `sha256` over the CANONICAL NATIVE ON-DISK BYTES of the target, obtained ONLY via
  native git on the device (`git show :<path>` / `git hash-object` semantics against the on-disk file), NEVER via a
  Cowork mount read or a `device_stage_files` snapshot. Before trusting any stage/mount-sourced bytes the engine
  asserts the snapshot's oid/mtime against native and raises `stale-snapshot` on drift.
- **F-2 Raw, not normalized.** No EOL normalization inside the fingerprint. EOL is part of content identity, so an
  LF->CRLF correction is a REAL fingerprint delta and can never be a false already-applied skip. Each content op
  declares `eol: crlf|lf`; "as-written" bytes are deterministic. (Note: the repo runs `core.autocrlf=true`, so the
  materializer must reconcile working-tree EOL vs the stored LF blob when computing native fingerprints -- observed
  and pinned during the i62 close fold.)
- **F-3 No plan-time frontier sha.** A `frontier` content op's postcondition is computed on-device at APPLY from the
  payload-as-written-with-declared-EOL, journalled, and FROZEN as the resume-comparison basis (defeats a cloud-LF vs
  native-CRLF mismatch and a producer-graded self-hash). `deterministic` op postconditions MAY be pre-declared
  because the engine re-derives them (CB-DERIVE).
- **F-4 Region location by anchor, never offset.** A region fingerprint is `sha256` of the span the `region_anchor`
  resolves to (F-1/F-2 bytes). The validator proves the anchor resolves to exactly one span (INV-10); a
  moved/duplicated heading is a validation error, not a silent mis-target.
- **F-5 Same basis on resume.** Every resume recompute uses the F-1..F-4 basis byte-for-byte, so idempotence (INV-3)
  has a single ground truth.

---

## 5. Phases + state machine (hardened)

`PLAN -> PRE-VALIDATE -> APPLY -> REBUILD -> POST-VALIDATE -> SHIP -> SEAL -> RECONCILE` -- **[CB-SEAL]** SEAL now
precedes RECONCILE and bounds the CANONICAL close only.

1. **PLAN.** Load + schema-validate the manifest. Assert `base_head == current native HEAD` (else ABORT
   `base-head-divergence` -> replan). Assert `ledger_ref` parseable + `iteration > 0`. Build the DAG; assert acyclic
   + resolvable; topologically order. Create a private **staging ref** `refs/lo/close/<transaction_id>` pointed at
   `base_head` (CB-SHIP; the atomic-cutover target).
2. **PRE-VALIDATE.** For each op compare its `precondition` to the current native state. A mismatch on an un-applied
   op -> if the target already equals the op's postcondition, ALREADY-APPLIED (idempotent skip, journal `verified`);
   else `precondition-divergence`. Run the PRE-RENDER retrieval gate (`gen-retrieval-monitor --gate --check-only`)
   here (inherit D-0158; aborts a bad/zero-bounded ledger before any render).
3. **APPLY.** Execute content ops in DAG order, committing each onto the STAGING REF (not `main`) under the git
   lease. For `append`, re-read the target FROM THE STAGING REF at commit time and insert at the `region_anchor`
   (never a whole-file working-tree snapshot -> defeats a stale-base clobber of another lane's committed entry).
   After each: recompute the fingerprint (s4), assert `== postcondition` (for `frontier` content ops, journal the
   computed postcondition per F-3), journal `verified`. A write/lease error -> `apply-failure` (resumable). NEVER
   `git add -A`; named paths; per-file EOL.
4. **REBUILD.** Run `view_rebuild` ops for exactly the views whose inputs the applied ops touched (declared
   `depends_on`; i64 derives). This is the map re-fold, MANAGER_VIEW regen, front-door rebuild, and the monitors --
   all against the staging ref. **[CB-VIEW]** the map-refold / canonical-bytes postcondition is DOUBLE-RUN BYTE
   IDENTITY (render twice in independent processes with pinned determinism knobs -- `PYTHONHASHSEED=0`, total-order
   sort keys, no in-place sort of a shared copy -- assert byte-equal; journal both digests), not a single `--check`.
   Volatile embedded fields (commit sha, freshness/timestamp) are EXCLUDED from the `--check` comparison domain via a
   declared volatile-field allowlist; the real sha is written later by a post-SHIP `stamp` op (5.6b).
5. **POST-VALIDATE.** Run `validator` ops against the staging ref: `doc-commit-gate` (per doc; **[CB-LEDGER]**
   extended with a no-truncation assertion -- prior D-entry ids / index rows are a SUBSET of the post-commit set),
   `frontdoor-gate`, retrieval `--gate` (emit the bytes-log row; fail-closed; `-MinBoundedFraction`),
   `close-consistency-check`, verify 0-stale on the `boot_read` set, the CB-GRADE independent-grader verdicts, and
   **[CB-IMPACT]** the INBOUND-REFERENCE COMPLETENESS assertion (INV-9). Nothing has touched `main` -> a failure here
   leaves canonical HEAD untouched (INV-1).
6. **SHIP (atomic cutover) [CB-SHIP].** Under a SINGLE git lease held for the whole of SHIP: re-assert `HEAD in
   {base_head} U {commits authored by this transaction on the staging ref}` (defeats a base_head TOCTOU / a pause +
   HEAD move). If `main` is a foreign commit -> `base-head-divergence` -> re-run REBUILD + consistency against the
   new HEAD before cutover. Then fast-forward `main` to the staging ref (the close's durable effect is ONE ref
   advance; the final map commit is the ref tip). VERIFY the real HEAD via native git (guard the `dev.ship`
   false-negative D-0072; ship-false-negative recovery is strict-ordered: (1) verify native HEAD + match the group by
   tree/content; (2) if present -> journal `verified`, NEVER retry; (3) only if absent -> clear a stale
   `.git/index.lock` via an executor task, then retry). Code groups ship via `dev.ship` onto the staging ref before
   the cutover. The lease is bounded/preemptible with a wedge detector that force-releases a lease whose holder task
   is gone-but-heartbeating (defeats the wedge deadlock).
   - **6b. `stamp` (post-cutover) [CB-VIEW].** Write the now-real commit sha / freshness into the volatile fields of
     the generated views via a narrow deterministic `stamp` op with its own precondition/postcondition, then a final
     ff of `main`.
7. **SEAL [CB-SEAL].** Assert the CANONICAL op set (PLAN..SHIP, EXCLUDING `mirror_reconcile`) is all-`verified`;
   write the durable SEAL { `transaction_id`, `iteration`, `final_head`, per-phase evidence digests }. The SEAL is
   the idempotence marker: re-running a SEALED transaction is a total no-op. Mirror ops are NOT part of this
   assertion.
8. **RECONCILE (post-SEAL, independently resumable) [CB-SEAL].** Keyed off the SEAL's `final_head`. (a) Project
   mirror -- a FULL reconcile **[CB-MIRROR-DEL]**: compute + apply the delete/rename set; postcondition = Project
   doc-set == canonical `core-docs/` set by path + content hash (not merely "changed docs applied"). (b) GitHub -- a
   managed-ref push **[CB-MIRROR-FF]**: fetch remote `main`; require it an ANCESTOR of the last mirrored `final_head`;
   push `--force-with-lease=main:<expected-old-oid>` via the executor; verify remote HEAD == local after. Foreign
   commits (not descended from a prior SEAL's `final_head`) -> surface `mirror-foreign-commits` on the audit
   projection, NEVER auto-force-clobber. A mirror op is journalled with a terminal `deferred` state on failure; the
   LOCAL close remains SEALED (INV-6); the mirror is retried as an independent step. End-of-iteration only; never
   midflight.

### 5.9 Resume + idempotence
On resume, the engine FIRST re-runs PLAN's `base_head` assertion [CB-SHIP]: if `main != base_head` AND no SHIP
cutover belongs to this transaction, force `base-head-divergence` -> replan (pre-SHIP working state is trusted only
after `base_head` is confirmed; else discard + re-derive). Otherwise it reads the journal and recomputes each op's
fingerprint on the s4 basis; an op whose target equals its postcondition is `verified` (idempotent skip); the first
non-`verified` op in topological order is the resume point. Because SHIP is an atomic ff of `main` to the staging ref
and SEAL records `final_head`, a crash between cutover and journal-write is recovered (the ref is observed and
journalled). Correction counters resume from the journal (CB-TERM).

---

## 6. Failure taxonomy + recovery

| failure | phase | detection | recovery |
|---|---|---|---|
| `base-head-divergence` | PLAN / SHIP / resume | `main != base_head` (or a foreign commit at cutover) | replan / re-run REBUILD+consistency vs the new HEAD before cutover; never clobber a foreign commit |
| `precondition-divergence` | PRE-VALIDATE | region != declared prior AND != postcondition | Frontier correction re-derived against the actual prior state (bounded; CB-TERM), or ABORT |
| `stale-snapshot` | any fingerprint read | stage/mount oid/mtime != native | refuse; re-read native (F-1); never trust the snapshot |
| `apply-failure` | APPLY | write / lease error on the staging ref | resume: recompute applied ops (idempotent), continue from the first un-applied op |
| `rebuild-drift` | REBUILD | double-run bytes differ / `--check` fails on a non-volatile field | resume the rebuild; persistent -> Frontier correction on the source op |
| `validator-failure` | POST-VALIDATE | a gate exits non-zero (incl. grader verdict, no-truncation, completeness) | HALT pre-cutover (nothing on `main`); bounded Frontier correction targets the failing predicate; resume from POST-VALIDATE |
| `ship-false-negative` | SHIP | `dev.ship committed=false` but native HEAD/tree shows it (D-0072) | strict-ordered recovery (s5.6); never blind-retry a present commit |
| `wedge-deadlock` | SHIP | the lease is held by a gone-but-heartbeating task | the wedge detector force-releases the lease; SHIP holds one lease for its whole duration so no reacquire can deadlock |
| `correction-exhausted` | any correction | per-op or `max_corrections_total` budget hit | write a terminal ABORTED-resumable marker; canonical HEAD untouched (INV-1); the session frees itself; a human's fix is a NEW planned close, not a live-held hang |
| `mirror-divergence` | RECONCILE | remote moved / managed-ref rejected | the LOCAL close STANDS SEALED; retry independently; foreign commits -> `mirror-foreign-commits` (no auto-clobber) |
| `mirror-foreign-commits` | RECONCILE | remote has commits not descended from a prior SEAL | surface on the audit projection for explicit resolution; never auto-force |
| crash / pause | any | journal + s4 fingerprint recompute after the s5.9 base_head re-check | resume from the first non-`verified` op |

---

## 7. Invariants (FROZEN)

- **INV-1 No half-land before the ff-cutover.** All mutation in PLAN..POST-VALIDATE lives on the private staging ref
  / working tree; a failure there leaves canonical `main` unchanged.
- **INV-2 Atomic cutover.** The durable effect of a close is ONE fast-forward of `main` to the staging-ref tip (the
  final map/generated commit at the tip); the SEAL records the exact `final_head`.
- **INV-3 Idempotence over the s4 basis.** Re-applying any op whose target equals its postcondition (native-byte,
  raw, anchor-located, F-1..F-5) is a no-op; re-running a SEALED transaction is a total no-op.
- **INV-4 Ledger fail-closed.** No render/ship without a valid session retrieval ledger + iteration; the retrieval
  gate + `-MinBoundedFraction` abort a non-adopted session BEFORE render (D-0158).
- **INV-5 Declared-impact only.** The transaction touches only manifest-declared targets + their evidence-linked
  views; no repo-wide sweep -- BUT bounded by INV-9.
- **INV-6 Canonical-over-mirror.** Mirror reconciliation is post-SEAL, never gates or mutates canonical, and never
  un-seals a local close; a mirror failure is a `deferred` op.
- **INV-7 The Frontier boundary is ENFORCED, not asserted.** `deterministic` = engine-reproducible (CB-DERIVE);
  `frontier` content ops carry a task spec AND an independent-grader edge (CB-GRADE); the human is out of the routine
  loop (bounded audit projection only), with exactly two by-exception gates (INV-12 historical deletion;
  correction-exhausted escalation).
- **INV-8 Fingerprint domain.** Every fingerprint obeys s4 (native bytes; raw/no-normalize; no plan-time frontier
  sha; anchor-located; the same basis on resume).
- **INV-9 Inbound-reference completeness.** For every edited target, every `core-docs/` referrer is either a
  declared `depends_on` sink or asserted 0-stale, else the close fails closed. The LIVE cutover (i65/i67) is withheld
  until i64 derives impact if the closure cannot be computed.
- **INV-10 Anchor uniqueness.** Every `region_anchor` resolves to exactly one span (validated); regions are located
  by anchor, never byte offset.
- **INV-11 Single-file serialization.** Multiple ops editing one file are dependency-serialized and non-overlapping;
  `append` anchors are invariant under prior in-manifest appends to that file.
- **INV-12 Append-only protection.** `replace_doc` is not in the taxonomy; whole-file rewrite of an append-only /
  monotonic target (DECISION_LOG, its index, any ledger) is forbidden; `doc-commit-gate` asserts no-truncation (prior
  ids subset of post ids); removal of a historical entry requires explicit human authorization.
- **INV-13 Double-run determinism.** Canonical-bytes rebuilds assert double-run byte identity with pinned
  determinism knobs; volatile embedded fields are excluded from `--check` and stamped post-cutover.
- **INV-14 Bounded correction.** Per-op AND transaction-level correction budgets, journalled + resume-persistent;
  exhaustion is a terminal ABORTED-resumable state that never holds canonical or hangs the session.
- **INV-15 Projection / backing separation (s9).** A doc's ingest budget is a PROJECTION budget; canonical BACKING
  carries no ingest budget and never auto-becomes a required bootstrap read. The close machinery validates + rebuilds
  bounded projections without imposing their ingest budget on their backing.

---

## 8. Frontier Agent in the Deterministic Loop -- correction protocol (hardened)

The engine runs deterministically. On a bounded semantic gap it emits a bounded correction task { the failing
op/predicate, the exact drifted state, the constraint the correction must satisfy, the postcondition to re-establish
}. The Frontier returns a bounded payload; the engine re-validates. **[CB-GRADE]** for a content correction the
re-validation is the INDEPENDENT grader's claim-vs-evidence verdict, NOT a hash of the correction's own bytes -- the
producer never grades itself (the D-0107/D-0109 self-grading lesson). The correction has no free-form repo access
(scoped to the failing op) and is journalled as a DELEGATION-DECISION (#39 episode shape). **[CB-TERM]** termination
is bounded by per-op AND `max_corrections_total`, both journalled and resume-persistent; a cross-op flip-flop trips
the transaction budget. Exhaustion writes `correction-exhausted` (terminal ABORTED-resumable, canonical untouched,
session freed) and surfaces the failing predicate on the management/audit projection -- the one by-exception human
touch point for a stuck close (never a live-held wait).

---

## 9. Bounded projection vs selectively-retrieved backing (BINDING) [INV-15]

The governing knowledge-surface direction (D-0141/D-0146/D-0155; F-i53-eff) is to **bound what agents ROUTINELY
INGEST, not to truncate the underlying knowledge.** i62 makes that a first-class, binding distinction with two
document classes:

- **HOT PROJECTION.** A bounded, agent-facing GENERATED (or curated) view meant for ROUTINE ingestion -- e.g. the
  PCB `BOOT_PACKET`, `MANAGER_VIEW`, a front door, a research digest. A projection **DECLARES**: (a) its ingest
  **budget** (the byte cap enforced by the doc-commit-gate / front-door gate), and (b) its authoritative
  **backing_ref** (the canonical source it projects). It is a routine/required read; brevity governs it.

- **COLD BACKING.** The COMPLETE, canonical, authoritative source material -- e.g. the full close-transaction
  contract / red-team / hardened spec (this directory), `DECISION_LOG.md`, the research corpus. Backing is
  **selectively retrieved** (not routinely ingested), carries **NO ingest budget** (completeness governs it), and
  **MUST NOT automatically become a required bootstrap / `boot_read` read.**

**The i62 mistake this corrects:** the 10 KB research-digest ingest budget was applied to the detailed authoritative
contract, forcing semantic compression of canonical backing. That inverts the direction. The fix: backing lives
outside the projection budget regime (`ops/close-txn/spec/`, `DECISION_LOG` growth-exempt, the research corpus), and
a single bounded digest projects it.

**Binding requirement for i63-i67 + later generated-view migrations (i68+).** Future close machinery must
VALIDATE + REBUILD bounded front doors **without imposing their ingest budgets on their underlying source
material.** Concretely: (1) a `projection` doc-class op MUST declare `budget_bytes` + `backing_ref`, and the gate
enforces its budget; (2) a `backing` doc-class op MUST carry NO `budget_bytes` and MUST NOT be added to the
bootstrap/`boot_read` set by the close; (3) a projection's budget is NEVER applied to its backing; (4) a generated
front door is rebuilt from its backing, count-asserted (spill-not-compress), and the backing stays lossless. The
doc-commit-gate's per-doc budgets remain in force for projections (no global weakening); backing is simply outside
that regime. The i62 schema/validator encodes (1)+(2) as the optional `doc_class` classification (s3.2) with narrow
tests; i63+ wires the rebuild path.

---

## 10. Subsume, don't rebuild + i62 groundwork + residuals

**Mapping.** `close-refold.ps1` -> the REBUILD + part of POST-VALIDATE sub-DAG (its harvest->verify->reaffirm->
validate->render->double-run-check->MANAGER_VIEW->retrieval-gate->consistency sequence is exactly a declared
sub-DAG; its fail-closed guards become INV-4). `doc-commit-gate` (+ no-truncation) / `frontdoor-gate` /
`close-consistency-check` / `gen-retrieval-monitor --gate` / render `--check` / MANAGER_VIEW `--check` / the
independent grader / the completeness closure -> `validator` ops. `dev.ship` + the git lease -> the SHIP primitive
onto the staging ref, then the ff cutover. Manual doc-fold + DECISION_LOG append + index row + CURRENT_STATE replace
+ handoff rewrite/snapshot -> `append`/`replace_section` ops with s4 pre/postconditions + anchors. Project + GitHub
mirrors -> post-SEAL `mirror_reconcile` ops. Overlay `iteration`/`next_iteration` + COLD_BOOT_CARD stamps ->
`deterministic` ops the engine re-derives (postconditions == what `close-consistency-check.py` asserts).

**i62 groundwork (`ops/close-txn/`).** The FROZEN `close_manifest.schema.json` + a fail-closed stdlib
`validate_manifest.py` enforcing the statically-checkable invariants (taxonomy/INV-12; unique op_ids; acyclic +
resolvable `depends_on`/INV-5; mandatory header incl. `ledger_ref`/`iteration>0`/INV-4; per-op `eol`/INV-8;
`region_anchor` single-span/INV-10; single-file serialization/INV-11; a grader edge per frontier content op/CB-GRADE;
no pre-declared frontier postcondition/CB-FP; the `doc_class` projection/backing classification/INV-15) + example
manifests + a test suite. It VALIDATES a manifest; the materializer that EXECUTES one is i63.

**Residuals accepted (recorded, not open holes).** Managed-ref `--force-with-lease` races beyond the ancestor check
are GitHub-side only and never touch canonical (INV-6). Validator/ack/stamp ops are re-verified (re-run) on resume,
not content-address-skipped -- safe by default. The independent grader is itself an LLM; CB-GRADE reduces but does
not eliminate correlated blind spots -- the claim-vs-evidence predicate (not a self-hash) + the audit projection are
the mitigations, and i65 owns the grader wiring + its own review. Determinism knobs (INV-13) assume the render
toolchain honours them; the double-run gate is the backstop that catches a knob that does not.
