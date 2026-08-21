# i62 -- PB-9 close-transaction contract (research digest / hot projection)

**This is a HOT PROJECTION** (bounded, routine-read; budget: the 10 KB research-digest cap). **Its authoritative
BACKING is COLD and complete:** `ops/close-txn/spec/` (owned by the close-transaction subsystem, `ops/close-txn/`).
Do not treat this digest as the specification -- it points to it. The backing carries NO ingest budget; read it
selectively when you need the full contract, not as a bootstrap read. (This projection/backing rule is itself part
of the contract -- hardened s9 / INV-15; see below.)

## Backing artifacts (complete, canonical)
- `ops/close-txn/spec/close-transaction-hardened.md` -- **the AUTHORITATIVE hardened contract** (INV-1..INV-15; the
  manifest spec; the phase state machine; the failure taxonomy; the correction protocol; the projection/backing
  rule). i63-i67 build against this.
- `ops/close-txn/spec/close-transaction-contract.md` -- the pre-red-team design-first draft (provenance; superseded
  by the hardened).
- `ops/close-txn/spec/close-transaction-redteam.md` -- the complete red-team record (all 22 breaks with full
  scenarios + fixes, the clustering, the verdict).
- `ops/close-txn/` -- the shipped groundwork: `schema/close_manifest.schema.json` (FROZEN) + `validate_manifest.py`
  (fail-closed validator) + examples + tests.

## Purpose (PB-9, the i62-i67 block)
Consolidate the iteration close -- today a hand-sequenced, non-atomic chain (doc commits -> `close-refold.ps1` ->
MANAGER_VIEW -> retrieval gate -> consistency -> final map commit -> monitors -> mirrors) that can HALF-LAND, is
ORDER-FRAGILE, has NO idempotence, uses MANUAL impact, and pushes mirrors UNPROTECTED -- into ONE manifest-driven,
resumable, idempotent transaction. Governing model (D-0155): **Frontier Agent in the Deterministic Loop** (routine
close is NOT human-gated; the human steers via a bounded audit projection). Local repo canonical; GitHub an
end-of-iteration mirror. Roadmap: i62 contract+red-team+groundwork (this); i63 materializer+freshness; i64
evidence-based impact detection; i65 the two validation stages + bounded correction; i66 protected mirror
reconciliation; i67 fault-inject/resume/idempotence/cutover.

## What i62 delivered
1. **Design-first contract** -> **3-adversary red-team** (independent in-session cloud subagents, D-0119; atomicity/
   recovery, fingerprints/EOL/determinism, frontier-loop/mirrors/impact) returning **22 concrete breaks (5 CRITICAL
   clusters, 5 HIGH, 2 MEDIUM)** -> **hardened authoritative contract**. The architecture HELD; it was under-specified
   at the seams this box has been burned on. The 12 clustered hardening items (all in the hardened spec):
   staging-ref fast-forward atomic cutover [CB-SHIP]; a native-byte fingerprint domain -- native git only, raw, no
   EOL normalization, no plan-time frontier self-hash [CB-FP]; SEAL-before-RECONCILE so a stuck mirror can't strand a
   close un-sealed [CB-SEAL]; a mandatory INDEPENDENT-grader edge on every frontier content op vs the D-0107/D-0109
   self-grading failure [CB-GRADE]; `deterministic` = engine-reproducible [CB-DERIVE]; anchor-located regions +
   single-file serialization [CB-ANCHOR]; double-run byte-identity determinism [CB-VIEW]; an inbound-reference
   completeness assertion [CB-IMPACT]; bounded resume-persistent corrections [CB-TERM]; append-only/no-truncation
   protection [CB-LEDGER]; protected mirror reconciliation [CB-MIRROR-*].
2. **Groundwork** (`ops/close-txn/`, shipped): the FROZEN `close_manifest.schema.json` + a fail-closed stdlib
   `validate_manifest.py` enforcing the statically-checkable invariants + example manifests + a test suite. It
   VALIDATES a manifest; the materializer that EXECUTES one is i63.
3. **The projection/backing distinction** (hardened s9 / INV-15; new i62 hardening item): a HOT PROJECTION is a
   bounded, routinely-ingested view that DECLARES its budget + its authoritative backing; a COLD BACKING doc is the
   complete canonical source, carries NO ingest budget, and never auto-becomes a required bootstrap read. **Binding
   for i63-i67 + later generated-view migrations:** future close machinery validates + rebuilds bounded front doors
   WITHOUT imposing their ingest budget on their underlying source. (This digest exists because the research-digest
   budget was wrongly applied to the authoritative contract during the i62 close; the fix is the split you are
   reading now.)

## Boundary respected
i62 did NOT pull forward the i63 materializer / i64 impact derivation / i65 correction loops / i66 mirror / i67
fault-inject-cutover. No global doc-gate weakening; no research migration; no new mandatory index; no unrelated
sweep; the ARCHITECTURE_MAP SP3 exception is unchanged; GitHub sync stays end-of-iteration only.

## Pointers
Decision: D-0161. Backlog: PROCESS_BACKLOG PB-9. Roadmap: `research/2026-08-15-i59-roadmap-reconciliation.md`
(the i62-i67 block). SEALED_CHECK_47 i62 re-eval: integrity intact, SP3 FAIL (standing D-0132, ARCHITECTURE_MAP),
M-03 not licensed. AUDIT review_due i62 -> i64. P0-1 FROZEN.
