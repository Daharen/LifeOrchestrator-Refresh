# ops/close-txn -- close-transaction contract groundwork (i62, PB-9)

**Status: i62 CONTRACT + validator groundwork only. The materializer is i63; do NOT execute a close from here.**

The authoritative contract is `core-docs/research/2026-08-21-i62-close-transaction-hardened.md` (design ->
red-team -> hardened triad; D-0161). This directory ships the STATIC, machine-checkable part of that contract:

- `schema/close_manifest.schema.json` -- the FROZEN contract-level JSON schema for a close manifest
  (`lifeorch.close_manifest/0.1`).
- `validate_manifest.py` -- a fail-closed, stdlib-only, deterministic validator. Enforces the statically-checkable
  hardened invariants (taxonomy/INV-12 no `replace_doc` + monotonic-target protection; unique op_ids; acyclic +
  resolvable `depends_on`/INV-5; mandatory header incl. `ledger_ref`+`iteration>0`/INV-4; per-op `eol`/INV-8;
  `region_anchor` presence + single-span resolvability/INV-10; single-file multi-edit serialization + non-overlap/
  INV-11; a mandatory independent-grader edge on every `frontier` content op/CB-GRADE+INV-7; no pre-declared
  frontier postcondition sha/CB-FP). `--repo <root>` adds INV-10 native-byte span resolution. Exit 0 valid / 1
  invalid / 2 usage. It VALIDATES a manifest; it does NOT execute one.
- `examples/` -- `canonical-close.json` (a full i62-style close) + `two-edit-one-file.json` (INV-11 positive).
- `tests/test_validate_manifest.py` -- 26 tests: the examples validate clean; every invariant's negative path
  produces its specific finding; CLI exit codes; helpers.

Run: `python3 -m unittest tests.test_validate_manifest` (from this dir).

What i62 deliberately does NOT do (deferred, per the hardened contract section 9): the materializer /
native-git fingerprint engine (i63), evidence-based impact derivation (i64), the two validation stages + bounded
Frontier correction loops + the independent grader wiring (i65), protected mirror reconciliation (i66),
fault-inject / resume / idempotence / cutover (i67). The LIVE cutover is gated on i64 by INV-9.
