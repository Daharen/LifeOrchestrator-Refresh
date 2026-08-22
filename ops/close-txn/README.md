# ops/close-txn -- close-transaction subsystem (i62 contract + i63 materializer, PB-9)

**Status: i62 shipped the CONTRACT + validator groundwork; i63 (D-0162) adds the MATERIALIZER + freshness
assertions + the preservation/overflow seam.** The LIVE production cutover of `main` remains DEFERRED (i67,
INV-9): the materializer stages + seals but never fast-forwards `main` without an explicit exercise-only flag.

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
- `materialize.py` -- the i63 MATERIALIZER. Executes a validated manifest through
  `PLAN -> PRE-VALIDATE -> APPLY -> REBUILD -> POST-VALIDATE -> SHIP(staged) -> SEAL` with:
  the native-byte FINGERPRINT DOMAIN (s4: native on-disk raw bytes, declared-EOL, anchor-located, same basis on
  resume); an append-only JOURNAL outside the mutated tree (s3.4); IDEMPOTENCE / resume (a SEALED transaction
  re-runs as a total no-op, INV-3); fail-closed missing edit targets + repo-escape refusal before any write; and
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
- `tests/` -- `test_validate_manifest.py` (validator invariants + i63 path-safety/classification/missing-target),
  `test_safepath.py` (adversarial repository-escape), `test_materialize.py` (PLAN..SEAL, idempotence, freshness,
  overflow-without-information-loss, deferred-cutover). All green natively.

Run: `python3 -m unittest tests.test_validate_manifest tests.test_safepath tests.test_materialize` (from this dir).

What later iterations own (deferred, per the hardened contract section 9): evidence-based impact derivation (i64);
the two validation stages + bounded Frontier correction loops + the independent grader wiring (i65); protected
mirror reconciliation (i66); fault-inject / resume / idempotence proof / the LIVE cutover (i67). The LIVE cutover is
gated on i64 by INV-9.
