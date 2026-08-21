# i62 -- PB-9 CLOSE TRANSACTION CONTRACT (design-first; pre-red-team)

The pre-red-team design for PB-9 / the i62-i67 block (D-0155). Kept for provenance; **superseded by the HARDENED
contract** (`2026-08-21-i62-close-transaction-hardened.md`), which is authoritative. The 3-adversary red-team
(`2026-08-21-i62-close-transaction-redteam.md`) attacked THIS draft; its s9 open questions seeded that attack.
Governing model (D-0155): Frontier Agent in the Deterministic Loop (routine close NOT human-gated). i62 = contract +
red-team; i63 materializer, i64 impact, i65 validation+correction, i66 mirror, i67 fault-inject/cutover.

## 1. The problem
A close today is hand-sequenced (handoff s4/s7 + `ops/close-refold.ps1`): author doc content -> commit named
core-docs via the executor git-lease through the fail-closed doc-commit-gate -> N7 close-refold (harvest -> verify
-> reaffirm -> validate -> render -> render --Check -> MANAGER_VIEW --check -> retrieval --gate -> consistency) ->
commit map/generated as the FINAL commit -> monitors -> Project mirror -> GitHub `--force-with-lease`. Live failure
modes: **half-landing** (many separate commits/steps, no single description of the close; a bridge death / dev.ship
false-negative / stale index.lock / pause leaves it partly closed with no safe resume), **ordering fragility**
(overlay-before-fold; reaffirm cross-process race fixed D-0147; MANAGER_VIEW staleness fixed D-0158), **no
idempotence**, **manual impact** (the orchestrator picks touched docs by judgment), **unprotected mirrors**.

## 2. Ownership
The transaction OWNS the atomic application of a DECLARED op set: apply content changes, rebuild affected views,
run validators, SHIP via executor/dev.ship/git-lease, reconcile mirrors -- as one resumable/idempotent unit. It
does NOT own authoring semantic content (D-entry prose, CURRENT_STATE text, reaffirm selection) = Frontier judgment
supplied as declared ops; it derives only mechanical ops (view rebuilds, iteration/next + cold-boot stamps, monitor
rows). Declared ownership + evidence-based impact; a required-doc iteration marker never licenses a repo-wide sweep.
Local repo canonical; GitHub an end-of-iteration mirror, never midflight.

## 3. The manifest (one close = one declarative JSON)
- **header:** transaction_id, iteration>0, base_head (precondition anchor), ledger_ref (MANDATORY, inherits
  D-0158), min_bounded_fraction, created_by, model_provenance, governing_model.
- **operations[]:** op_id; kind in {append, replace_section, replace_doc, create, view_rebuild, validator, ack,
  mirror_reconcile}; target; precondition (fingerprint of expected prior state; `absent` for create); payload_ref;
  postcondition (fingerprint after / render --check clean / exit 0 / predicate true); depends_on[] (the ordering
  DAG); semantic_owner in {deterministic, frontier} (a frontier op carries its bounded task spec).
- **phases** derived from op kinds; **journal** = append-only per-op state, the resume substrate.

## 4. Phases + state machine
`PLAN -> PRE-VALIDATE -> APPLY -> REBUILD -> POST-VALIDATE -> SHIP -> RECONCILE -> SEAL`. PLAN: assert base_head==HEAD;
build the acyclic DAG. PRE-VALIDATE: check preconditions (target==postcondition -> idempotent skip); pre-render
retrieval gate. APPLY: content ops in DAG order under the git lease; recompute+assert+journal; never `git add -A`;
per-file EOL. REBUILD: rebuild only views the applied ops touch (map re-fold, MANAGER_VIEW, front doors, monitors);
postcondition = --check clean. POST-VALIDATE: doc-commit-gate, frontdoor-gate, retrieval --gate, consistency,
0-stale on boot_read. SHIP: commit named paths via dev.ship + the git lease (the map commit is the FINAL commit);
VERIFY native HEAD (D-0072). RECONCILE: Project mirror + GitHub managed-ref push. SEAL: assert journal all-verified;
write the durable close SEAL (the idempotence marker).

## 5. Failure taxonomy + recovery
base-head-divergence (PLAN) -> replan; precondition-divergence -> Frontier correction or abort; apply-failure ->
resume from first unapplied op (idempotent); rebuild-drift -> resume/correct; validator-failure -> HALT pre-ship +
correction + resume; ship-false-negative (D-0072) -> verify native HEAD; mirror-divergence -> local close STANDS,
retry mirror independently; crash -> journal + fingerprint recompute drives resume.

## 6. Invariants (pre-hardening)
INV-1 no half-land before SHIP; INV-2 atomic-enough SHIP; INV-3 idempotence (content-addressed done-ness); INV-4
ledger fail-closed; INV-5 declared-impact only; INV-6 canonical-over-mirror; INV-7 Frontier boundary
(deterministic ops mechanically verified; frontier ops carry a task spec; human not in the routine loop).

## 7. Frontier in the Deterministic Loop
The engine runs deterministically; on a bounded semantic gap it emits a bounded correction task and re-validates
via the same postcondition; corrections are scoped + journalled; termination bounded by a per-op budget; routine
close not human-gated -- Nicholas steers via a bounded management/audit projection.

## 8. Subsume, don't rebuild
close-refold.ps1 -> the REBUILD sub-DAG; the audit gates -> validator ops; dev.ship+lease -> SHIP; manual doc-fold
-> append/replace ops; mirrors -> mirror_reconcile ops; overlay/cold-boot stamps -> deterministic ops. i62 adds a
machine-checkable manifest schema + validator groundwork derived from the hardened contract.

## 9. Open questions (seeded to the red-team)
1. Atomicity of a multi-commit SHIP -- is INV-2 sound, or is a staging-ref + ff cutover needed?
2. Fingerprint definition -- region vs whole-file; EOL/CRLF/mount-vs-native (a mount-read sha != the native file).
3. Journal durability across a crash/reset between effect and record.
4. base_head TOCTOU -- HEAD moves between PLAN and SHIP.
5. Frontier-correction non-termination.
6. Managed-ref races on the mirror push.
7. Declared-impact completeness -- an undeclared dependency = a stale neighbour.
8. Idempotence under partial-region edits (adjacent ops on one file).
9. Preserving the close-refold pre-render-gate ordering when wrapped as a sub-DAG.
10. Empty/near-empty (doc-only / ack-only) closes still SEAL + still run the gates.

(The red-team turned 1/2/3/4 into CRITICAL breaks and 5/6/7/8 into HIGH breaks; all are resolved in the hardened
contract -- staging-ref ff cutover, the native-byte fingerprint domain, the SEAL-before-RECONCILE reorder, the
independent-grader edge, the inbound-reference completeness assertion, anchor-located regions, double-run
determinism, and bounded resume-persistent corrections.)
