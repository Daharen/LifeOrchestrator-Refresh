# i62 -- PB-9 CLOSE TRANSACTION CONTRACT: adversarial RED-TEAM

Three INDEPENDENT in-session cloud subagents (D-0119; Opus 4.8), each a distinct adversarial lens, attacked the
design-first contract (`2026-08-21-i62-close-transaction-contract.md`). Charter: BREAK it; rubber-stamping = fail.
**22 raw breaks -> 12 clustered hardening items: 5 CRITICAL, 5 HIGH, 2 MEDIUM.** All folded into the hardened
contract (`2026-08-21-i62-close-transaction-hardened.md`). Adversary transcripts summarized below (severity as
returned).

## Adversary A -- atomicity, idempotence & recovery
- **A1 CRITICAL** intra-SHIP lane interleave lands a STALE final map commit and SEALs clean: the lease is not held
  across all of SHIP's commits, so a foreign commit can land between the doc commit and the final map commit.
- **A2 CRITICAL** `base_head` asserted only at PLAN, never re-asserted at SHIP: a whole-file `append` built on a
  stale base clobbers another lane's already-committed D-entry inside the lease (non-fast-forward clobber).
- **A3 CRITICAL** resume (4.9) never re-checks `base_head`: a days-long pause + a HEAD move -> re-fold/ship against
  a mixed base (docs on B, map folded on Z), render `--check` may still pass.
- **A4 HIGH** idempotence (INV-3) defined over an unspecified fingerprint basis: the mount-vs-native / EOL gotcha
  makes an already-applied append look un-applied -> duplicate D-entry.
- **A5 HIGH** SEAL is downstream of RECONCILE and gated on "journal all-verified": a mirror divergence strands the
  transaction permanently UN-sealed, contradicting INV-6.
- **A6 HIGH** ship-false-negative recovery ambiguous under joint committed+stale-lock (double-ship risk); an
  executor WEDGE holding the lease deadlocks SHIP mid-multi-commit (fresh heartbeat -> no timeout).
- **A7 MEDIUM** `replace_section` region location unspecified: a resume re-applies one region op and corrupts an
  adjacent already-applied op (byte-offset drift).

## Adversary B -- fingerprints, EOL/bytes & determinism
- **B1 CRITICAL** fingerprint byte-domain undefined: a PLAN-time (cloud/staged, LF) postcondition sha can never
  equal an APPLY-time (device-native, CRLF) recompute -> every Frontier content op fails its postcondition assert;
  no conforming close can complete.
- **B2 CRITICAL** the naive EOL-normalizing fix to B1 collapses the section 4.2 already-applied test: an EOL-correction
  close (LF->CRLF) hashes equal pre/post -> silently skipped -> the fix never lands.
- **B3 CRITICAL** fingerprint recompute source unspecified: a stale `device_stage_files` snapshot on resume makes
  an already-applied append look un-applied -> duplicate D-entry (symmetric case: false `verified`).
- **B4 HIGH** `view_rebuild` postcondition "render --check clean" is self-referential: MANAGER_VIEW embeds the
  commit sha/freshness that only exists AFTER SHIP -> a resume re-render never matches (or is non-idempotent under
  a wall-clock stamp).
- **B5 HIGH** the map-refold postcondition is a SINGLE `render --check`, not the DOUBLE-RUN byte-identity gate that
  is the only thing that historically caught randomized-order non-determinism (seed-dependent render).
- **B6 HIGH** `append` "base-content anchor" moves when a prior op in the SAME manifest edits the same file ->
  false `precondition-divergence` on the second append (every real close appends >=2x to DECISION_LOG).
- **B7 MEDIUM** `replace_section` region-identification function undefined: a heading collision replaces the WRONG
  region and its postcondition (over that same wrong region) is satisfied -> silent mis-apply seals clean.

## Adversary C -- frontier loop, mirrors & declared-impact completeness
- **C1 CRITICAL** content-op postcondition = `sha256(own payload)`: the Frontier BOTH authors and grades,
  recreating the self-grading failure mode (D-0107/D-0109) -- an over-claim ships green because every gate is a
  consistency check, none a truth check; no independent grader in the loop.
- **C2 CRITICAL** SEAL "journal all-verified" vs mirror-divergence "local STANDS SEALED": a stuck mirror during a
  multi-day pause makes the close non-terminable (== A5, converged).
- **C3 HIGH** an inbound reference outside `boot_read  U  map-rendered` is invisible to declared-impact AND to the
  OQ7 net -> a real stale neighbour ships, violating D-0155 "no stale neighbours."
- **C4 HIGH** correction termination unbounded: the budget is PER-OP (a cross-op flip-flop never trips it), not
  journalled (resume resets it), and escalation "waits for a human" hangs the close for days with a dirty tree.
- **C5 HIGH** `semantic_owner` is an unenforced free field: a Frontier-authored payload labelled `deterministic`
  skips its task-spec/audit and masquerades as mechanically verified.
- **C6 HIGH** `replace_doc` permitted on the append-only DECISION_LOG with only a content-sha postcondition: a bad
  payload silently truncates the provenance spine; no no-truncation invariant, no human.
- **C7 MEDIUM** GitHub `mirror-divergence` retry cannot distinguish our-stale-lease from independent remote work ->
  the "local STANDS" recovery force-clobbers a legitimate contribution.
- **C8 MEDIUM** the Project mirror re-mirrors only CHANGED docs -> deletions/supersessions leave stale orphans in
  the human's steering projection; "content-idempotent" is false under deletion.

## Clustering -> hardening items (folded into the hardened contract)

| # | cluster | raw breaks | sev |
|---|---|---|---|
| CB-FP | canonical native-byte fingerprint domain (no plan-time frontier sha; native-git source only; raw, no EOL-normalize; declared per-file EOL; frozen for resume) | A4,B1,B2,B3 | CRITICAL |
| CB-SEAL | SEAL bounds CANONICAL only + precedes RECONCILE; mirror ops post-SEAL, terminal `deferred`, excluded from the all-verified assertion | A5,C2 | CRITICAL |
| CB-SHIP | SHIP is lease-atomic via a staging-ref + fast-forward cutover; single lease across all commits; re-assert HEAD  in  {base_head  U  own commits} at SHIP and at resume; appends re-read/merge at commit; strict ship-false-negative recovery; bounded/preemptible lease + wedge detection | A1,A2,A3,A6 | CRITICAL |
| CB-GRADE | a Frontier content op's postcondition is NOT a hash of its own output; a mandatory INDEPENDENT-grader validator edge (claim-vs-evidence) per Frontier content op; SEAL fails without it | C1 | CRITICAL |
| CB-DERIVE | `semantic_owner:deterministic` MEANS engine-reproducible: the engine re-derives the payload and fails closed on mismatch; non-reproducible => `frontier` (task-spec required); validator enforces | C5 | CRITICAL* |
| CB-ANCHOR | region/append identity by STABLE semantic anchors (unique fenced markers); validator asserts exactly-one-span, non-overlapping, dependency-serialized multi-edits per file | A7,B6,B7 | HIGH |
| CB-VIEW | map-refold postcondition = DOUBLE-RUN byte identity (independent processes) with pinned determinism knobs; volatile-field allowlist (embedded sha/freshness excluded); sha-embedding moved to a post-SHIP stamp op | B4,B5 | HIGH |
| CB-IMPACT | REBUILD completeness assertion over the FULL inbound-reference grep-closure of every edited target; fail-closed on an undeclared referrer; refuse to go LIVE (i65/i67) until i64 derivation lands | C3 | HIGH |
| CB-TERM | transaction-level `max_corrections_total` + journalled per-op AND per-transaction counters (resume continues, never resets); escalation writes a terminal ABORTED-resumable leaving canonical untouched -- never a live-held hang | C4 | HIGH |
| CB-LEDGER | forbid `replace_doc` on append-only/monotonic targets; a no-truncation invariant in `doc-commit-gate` (prior ids  subset of  post ids); historical removal requires explicit human authorization | C6 | HIGH |
| CB-MIRROR-FF | GitHub retry: the fetched remote HEAD must be an ancestor of the last mirrored `final_head`; foreign commits (not descended from a prior SEAL) -> surface `mirror-foreign-commits`, never auto-force-clobber | C7 | MEDIUM |
| CB-MIRROR-DEL | the Project mirror is a FULL reconcile (compute + apply the delete/rename set); postcondition Project doc-set == canonical `core-docs/` set (path + content hash) | C8 | MEDIUM |

*CB-DERIVE is rated CRITICAL in the hardened set: it is the enforcement mechanism that makes INV-7 (the Frontier
boundary) non-gameable, without which CB-GRADE can be bypassed by mislabelling.

## Verdict
The design's ARCHITECTURE HELD (manifest + phases + journal + resume + Frontier-in-the-loop is sound); it was
UNDER-SPECIFIED at exactly the load-bearing seams this box has been burned on before: byte/EOL identity,
lease/commit atomicity, self-grading, and mirror/seal ordering. The 12 hardening items close those seams. Two are
ratification-blocking in spirit (CB-GRADE + CB-SEAL): a contract that lets a self-graded over-claim ship, or that
strands a close un-sealed on a mirror hiccup, is not safe to build a live cutover on. The hardened contract is the
authoritative i62 artifact.
