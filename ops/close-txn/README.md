# ops/close-txn -- close-transaction subsystem (i62 contract + i63 materializer, corrected D-0163, PB-9)

**Status: i62 shipped the CONTRACT + validator groundwork; i63 shipped the MATERIALIZER + freshness/preservation
seam; i63 was then RE-CLOSED corrective (D-0163) after an independent red-team disproved the D-0162 durable-stage-only
claims with 14 executable counterexamples -- the materializer was rebuilt as a genuinely durable git-staging engine
(C63-01..14 fixed; T63-01..20 controls; 99 tests green natively AND in the cloud gate).** The LIVE production cutover
of `main` remains DEFERRED (i67, INV-9): the materializer's ONLY durable effect is a CAS-guarded staging ref
`refs/lo/close/<txid>`; it NEVER fast-forwards `main` -- the live-cutover code was REMOVED (no `--allow-live-cutover`,
no `_ff_main`; AST + source-string asserted).

The AUTHORITATIVE, complete contract is COLD BACKING under `spec/` in this directory:
`spec/close-transaction-hardened.md` (design -> red-team -> hardened triad; D-0161/D-0162). It carries NO ingest
budget -- read it selectively, not as a bootstrap read. Its bounded HOT PROJECTION (routine read, 10 KB budget) is
`core-docs/research/2026-08-21-i62-close-transaction.md`, which points here. This directory ships the machine-checkable
part of that contract:

- `schema/close_manifest.schema.json` -- the FROZEN contract-level JSON schema for a close manifest
  (`lifeorch.close_manifest/0.1`).
- `safepath.py` -- the repository path-safety guard (i63): every file-path a manifest names (an op `target`, a
  `backing_ref`, a string `payload_ref`) must resolve INSIDE the authorized repo. Rejects parent traversal,
  absolute / Windows-drive / UNC paths, the protected `.git` directory, and symlink/junction escapes. The single
  chokepoint the validator (static) and the materializer (before any write) both call.
- `validate_manifest.py` -- a fail-closed, stdlib-only, deterministic validator. Enforces the statically-checkable
  hardened invariants (taxonomy/INV-12 no `replace_doc` + monotonic-target protection; unique op_ids; acyclic +
  resolvable `depends_on`/INV-5; mandatory header incl. `ledger_ref`+`iteration>0`/INV-4; per-op `eol`/INV-8;
  `region_anchor` presence + single-span resolvability/INV-10; single-file multi-edit serialization + non-overlap/
  INV-11; a mandatory independent-grader edge on every `frontier` content op/CB-GRADE+INV-7; no pre-declared
  frontier postcondition sha/CB-FP; the `doc_class` projection/backing classification incl. unknown-class + stray
  projection-field rejection/INV-15; path safety on every file-path reference/Amd2.1). `--repo <root>` adds INV-10
  native-byte span resolution AND fail-closed missing-edit-target detection (an `append`/`replace_section` on an
  absent target is a HARD finding, not an anchor-check SKIP; a target a `create` op in the same manifest produces is
  exempt). Exit 0 valid / 1 invalid / 2 usage. It VALIDATES a manifest; it does not execute one.
- `materialize.py` -- the MATERIALIZER (corrective rebuild, D-0163). Executes a validated manifest through
  `PLAN -> PRE-VALIDATE -> APPLY -> REBUILD -> POST-VALIDATE -> SEAL`; its ONLY durable effect is a private,
  CAS-guarded staging ref `refs/lo/close/<txid>` built via git plumbing on a throwaway index -- it NEVER touches
  `main`. Every git object/ref write passes a LEASE write-guard first (a production write with no verified
  executor/git-lease context is REFUSED fail-closed, C63-14). The CANDIDATE-TREE (git-blob) FINGERPRINT DOMAIN the
  engine transacts is environment-independent of the checkout (a clone's autocrlf must not drift the source
  fingerprint; C63-09/D-0163 finding); an append-only DURABLE JOURNAL lives OUTSIDE the candidate tree
  (`modules/44-project-map/runtime/close-txn`, gitignored) and a record is verified only AFTER a git-object
  readback -- no in-memory false-seal (C63-05). IDEMPOTENCE / resume (a SEALED transaction re-runs as a total
  no-op, INV-3); the transaction_id is validated BEFORE any filesystem side effect (C63-01); fail-closed missing
  edit targets + repo-escape refusal before any write; and
  the i63 PRESERVATION / PROJECTION-BACKING seam -- backing refs must resolve to real canonical source, projection
  freshness is checkable against the source, and a projection is PREFLIGHTED against its budget so an over-budget
  projection returns a precise overflow / **backing-spill** result (the full source stays lossless; the
  materializer NEVER trims prose or semantic-compresses to recover). Evidence (source size, projection size,
  freshness validity, overflow occurrences, avoidable trim retries) is captured in the journal. Deliberately
  DEFERRED: the live `main` cutover (i67), evidence-based impact (i64), the bounded correction LOOP (i65), and
  mirror reconciliation (i66) are RECOGNISED + journalled `deferred`, not executed. No routine-close human gate:
  a `correction-exhausted` writes a durable resumable ABORT and frees the session (never a human wait).
- `spec/` -- the COMPLETE canonical backing (no ingest budget): `close-transaction-hardened.md` (authoritative),
  `close-transaction-contract.md` (design-first, provenance), `close-transaction-redteam.md` (full 22-break record).
  Discoverable through the memory index via `ops/repo-intel-roots.json` (a narrow explicit repo.intel root).
- `examples/` -- `canonical-close.json` (a full i62-style close), `two-edit-one-file.json` (INV-11 positive), and
  `i63-backing-projection.json` (a REAL classified backing/projection pair: the hardened spec as `backing` + the
  research digest as `projection`).
- `tests/` -- `test_validate_manifest.py` (validator invariants + path-safety/classification/missing-target),
  `test_safepath.py` (adversarial repository-escape incl. the V63-01..14 corpus + txid grammar),
  `test_materialize.py` (PLAN..SEAL, durable journal, idempotence/resume, DAG-ordered freshness, full-candidate
  overflow-without-information-loss, no-cutover, lease-gating, deterministic mismatch), `test_real_pair.py` (T63-17:
  the REAL backing/projection manifest EXECUTES stage-only in a disposable clone + the T63-17b autocrlf-drift
  regression), and `test_native_junction.py` (T63-14: a REAL native NTFS junction via `mklink /J` is rejected --
  Windows-only, skips in the Linux gate). 99 green natively on the box AND 99 in the cloud gate. On-box controls
  (executor-run) also prove the public repo.intel `-RootsManifest` discoverability + #36 catalog retrieval (C63-12)
  and a REAL `#29` res.lease gating a disposable canonical-repo clone (T63-19).

Run: `python3 -m unittest discover -s tests -p 'test_*.py'` (from this dir; the junction control runs natively on
Windows and skips elsewhere).

What later iterations own (deferred, per the hardened contract section 9): evidence-based impact derivation (i64);
the two validation stages + bounded Frontier correction loops + the independent grader wiring (i65); protected
mirror reconciliation (i66); fault-inject / resume / idempotence proof / the LIVE cutover (i67). The LIVE cutover is
gated on i64 by INV-9.
