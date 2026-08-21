# PB-9 CLOSE TRANSACTION -- RED-TEAM RECORD (complete)

**Class: COLD BACKING (canonical, complete record -- NOT a routine/bootstrap read; NO ingest budget).** Owner:
`ops/close-txn/`. Projection: `core-docs/research/2026-08-21-i62-close-transaction.md`.

Three INDEPENDENT in-session cloud subagents (D-0119; Opus 4.8), each a distinct adversarial lens, attacked the
design-first contract (`close-transaction-contract.md`, this directory). Charter: BREAK it; rubber-stamping = fail.
**22 raw breaks -> 12 clustered hardening items: 5 CRITICAL, 5 HIGH, 2 MEDIUM.** All folded into the hardened
contract. This is the complete record: every break with its concrete scenario + minimal fix.

## Adversary A -- atomicity, idempotence & recovery

**A1 CRITICAL -- intra-SHIP lane interleave lands a stale FINAL map commit and SEALs clean.** The contract never
states the git lease is held across ALL of SHIP's commits, and dev.ship acquires its own lease, so SHIP releases the
lease between the doc commit and the final map commit. Scenario: REBUILD folds the map against the working tree and
render --check passes; SHIP commits docs (HEAD=D, lease released); a parallel lane commits X (child of D) editing a
doc the map indexes; our txn reacquires the lease and lands the FINAL map commit M on top of X -- M's generated
content predates X, so it does not index X. SEAL asserts the journal all-verified (true, verified against the
pre-interleave tree) and records final_head=M: a half-land that SEALs clean; close-consistency ran before X. FIX:
SHIP must be lease-atomic (one lease across the whole doc->code->final-map sequence); before the final map commit,
re-assert HEAD == this txn's own last commit, else ABORT + re-run REBUILD/consistency vs real HEAD. Better: a
staging-ref + ff cutover (one atomic ref update).

**A2 CRITICAL -- base_head asserted only at PLAN, never re-asserted at SHIP -> an append clobbers another lane's
committed D-entry.** "VERIFY the real HEAD" in SHIP is scoped to the dev.ship false-negative ("did MY commit land"),
not "did HEAD move to someone else's commit before I committed." Scenario: PLAN base_head=B; my `append` op for
DECISION_LOG was authored against B and its working-tree effect is the whole file B+mine; lane-2 commits Y (child of
B) that also appends a D-entry+index row (DECISION_LOG is the single serialization point for every lane's decisions);
SHIP commits the NAMED path DECISION_LOG.md from my working tree (B+mine, missing Y) -> reverts Y's entry inside the
lease (a non-fast-forward clobber). FIX: under the held SHIP lease, assert HEAD in {base_head} U {this txn's
commits}; if foreign, raise base-head-divergence + replan; `append` ops re-read the target at commit time (or
three-way merge), never a whole-file snapshot.

**A3 CRITICAL -- resume never re-checks base_head -> a days-long pause + HEAD move re-folds/ships against the wrong
base.** 4.9 resume recomputes per-op fingerprints but never re-asserts base_head; pre-SHIP mutation is working-tree
only. Scenario: reach REBUILD, pause two days; a lane advances HEAD B->Z and/or an executor restart discards part of
the uncommitted generated tree; resume skips still-matching doc ops as verified, re-runs the map rebuild -- whose
fold is harvest@HEAD (now Z), so the map is folded against Z while the docs reflect B; render --check may still pass;
SHIP ships a mixed base. FIX: 4.9 resume MUST re-run PLAN's base_head assertion FIRST; on HEAD != base_head with no
own SHIP commit, force base-head-divergence -> replan; trust pre-SHIP working state only after base_head is confirmed.

**A4 HIGH -- idempotence (INV-3) defined over an unspecified fingerprint basis -> the mount-vs-native/EOL gotcha
double-appends a D-entry.** "Equals" = sha of a region/file, but the sha BASIS is undefined (mount vs native; CRLF vs
LF). Scenario: APPLY appends to DECISION_LOG (CRLF) and journals verified with observed_post computed one way; a
bridge death near the journal write; resume recomputes via the mount read (LF-normalized) so sha(mount) !=
postcondition(native) -> op judged not-applied -> RE-APPLY -> two copies of the D-entry (append is non-idempotent;
content-addressing was its only guarantee). FIX: fix the fingerprint canonicalization at contract level (native bytes
via the executor, never a mount read; a declared per-file EOL; resume uses the byte-identical basis); INV-3 must name
this basis.

**A5 HIGH -- SEAL is downstream of RECONCILE and gated on "journal all-verified" -> a mirror divergence strands the
txn permanently un-SEALED.** Phase order PLAN..SHIP->RECONCILE->SEAL; a failed mirror op is journalled `failed`; SEAL
cannot then assert all-verified, so SEAL never runs -- contradicting INV-6 ("a mirror failure never un-seals a local
close") and the recovery text ("the local close STANDS SEALED"). FIX: reorder so SEAL bounds the CANONICAL close only
and precedes RECONCILE; mirror ops run post-SEAL, journalled separately, EXCLUDED from the all-verified assertion.

**A6 HIGH -- ship-false-negative recovery ambiguous under joint committed+stale-lock; a wedge holding the lease
deadlocks SHIP mid-multi-commit.** (a) committed-AND-locked is a real joint state (D-0072 false-negative + a crash
leaving a stale index.lock); a recovery that matches "stale lock -> clear + retry" without first confirming the
commit is absent re-commits the group -> a duplicate ship. (b) an executor WEDGE (blocked task holding the git lease,
heartbeat fresh) after the code group commits but before returning: recovery sees the commit + continues, but the
FINAL map commit blocks forever on the held lease (fresh heartbeat -> no timeout), and the "clear the lock via an
executor task" remedy can't run on the same wedged executor -> a non-resumable half-land inside SHIP. FIX: a
strict-ordered recovery (always verify native HEAD + match the group by tree/content first; present -> journal
verified, never retry; absent -> clear lock -> retry) + a preemptible lease with a wedge detector that force-releases
a lease whose holder is gone-but-heartbeating (or SHIP holds one lease for its whole duration).

**A7 MEDIUM -- replace_section region location unspecified -> a resume re-applies one region op and corrupts an
adjacent already-applied op.** Two ops replace adjacent CURRENT_STATE sections; A's replacement shifts B's byte
offsets; a crash after both applied, before B's journal write; resume with byte-offset region location re-applies B
at the wrong/overlapping offset. FIX: promote OQ8 to an invariant -- region ops located by stable semantic anchors,
declared non-overlapping, serialized via depends_on when adjacent; the validator rejects overlapping/adjacent
same-target region ops that are not dependency-ordered; fingerprints locate regions by anchor, never absolute offset.

RESIDUAL (A): managed-ref races beyond A5's local strand (GitHub-side, INV-6); frontier-correction non-termination
(A's lens excludes it); validator/ack predicate ops not content-address-skippable on resume (safe: re-verified).

## Adversary B -- fingerprints, EOL/bytes & determinism

**B1 CRITICAL -- the fingerprint byte-domain is undefined, so a PLAN-time (cloud/staged, LF) postcondition sha can
never equal an APPLY-time (device-native, CRLF) recompute -> every frontier content op fails its postcondition
assert.** The postcondition lives in the authored manifest (fixed at PLAN, from the cloud-staged LF payload); APPLY
writes native CRLF (the contract mandates per-file EOL) then recomputes and asserts == postcondition; the three byte
domains (cloud-LF / native-CRLF / git-blob-with-EOL-filter) hash differently for identical logical content, so the
assert fails on the first real CRLF core-doc edit -- no conforming close can complete. FIX: a normative fingerprint
domain -- sha over the canonical native on-disk bytes via native git only; a frontier content op carries NO plan-time
sha (its postcondition is computed on-device at APPLY from payload-as-written-with-declared-EOL, journalled, frozen
for resume); declare per-op `eol`.

**B2 CRITICAL -- the naive EOL-normalizing fix to B1 collapses the already-applied test -> an EOL-correction close is
silently skipped.** If the fingerprint strips \\r before hashing, then a close whose PURPOSE is an LF->CRLF fix hashes
pre==post (they differ only in \\r) -> PRE-VALIDATE declares it already-applied -> idempotent skip -> the fix never
lands + SEALs clean. So raw fingerprint (B1) blocks every close; normalized fingerprint drops every EOL-semantic
edit. FIX: mandate RAW, non-normalized native-byte fingerprints; solve cross-surface agreement by always reading the
SAME native domain, so an EOL delta is a real fingerprint delta and never a false already-applied skip.

**B3 CRITICAL -- the fingerprint recompute source is unspecified, so a stale device_stage_files snapshot on resume
makes an already-applied append look un-applied -> a duplicate D-entry.** 4.9 "recomputes the current fingerprint"
without stating the read must go to native git; device_stage_files can return a STALE snapshot. Scenario: APPLY
appends D-0159, journals verified; a bridge death before SEAL; resume reads DECISION_LOG via a stale (pre-append)
snapshot -> recomputed sha == precondition -> re-executes the append -> D-0159 twice. Symmetric failure: a stale
snapshot showing NEW bytes when the write failed yields a false verified. FIX: ALL fingerprint reads take native git
on the device, never a stage/mount snapshot; assert the snapshot oid/mtime vs native and refuse (stale-snapshot) on
drift.

**B4 HIGH -- `view_rebuild` postcondition "render --check clean" is self-referential -- MANAGER_VIEW embeds the
commit sha/freshness that only exists AFTER SHIP, so a resume's re-render never matches.** REBUILD renders
MANAGER_VIEW embedding sha=base_head (or "working") and sets its postcondition to --check-clean; SHIP creates sha X;
the committed file embeds a sha != X; any resume/next-close --check re-renders with the now-real HEAD X -> a false
rebuild-drift chasing a moving HEAD; a wall-clock freshness stamp makes --check non-idempotent by construction. FIX:
generated views are a pure function of committed inputs for --check (exclude embedded sha + freshness from the
comparison domain via a declared volatile-field allowlist); move sha-embedding to a deterministic post-SHIP stamp op
with its own pre/postcondition.

**B5 HIGH -- the map-refold postcondition is a SINGLE render --check, not the DOUBLE-RUN byte-identity gate that is
the only thing that historically caught randomized-order non-determinism.** If non-determinism lives in the render's
iteration order (dict/set ordering under a per-process PYTHONHASHSEED), render and --check share the seed within one
process and AGREE (masking drift), while a resume in a fresh process re-renders with a different seed and --check
FAILS -> a false rebuild-drift that "resume the rebuild" can't stably clear. FIX: define the map-refold postcondition
as DOUBLE-RUN BYTE IDENTITY (two independent processes, byte-equal) + pin determinism knobs (PYTHONHASHSEED=0,
total-order sorts, no in-place sort of a shared copy); journal both digests.

**B6 HIGH -- `append` "base-content anchor" moves when a prior op in the SAME manifest edits the same file -> a false
precondition-divergence on the second append.** A normal close appends to DECISION_LOG at least twice; a whole-file
or trailing-region anchor computed at PLAN no longer matches after the first append; the second append sees target !=
declared prior (and hasn't run, so the already-applied escape doesn't fire) -> precondition-divergence blocks a
legitimate two-append close. FIX: define the `append` precondition on a STABLE prior region (a fixed marker/heading
line immediately above the insertion point), invariant under prior in-manifest appends; the validator rejects
unserialized multi-appends to one file.

**B7 MEDIUM -- `replace_section` has no defined region-identification function -> a heading collision replaces the
wrong region.** "sha of the region to be replaced" without a region extractor: a recurring `## Status` / a heading
inside a fenced block can bind to the wrong span -> either a false precondition-divergence, or (worse) a
deterministic wrong-but-consistent bind that satisfies the postcondition over that same wrong region -> a SILENT
mis-apply that SEALs clean. FIX: a deterministic collision-resistant region_anchor (a unique HTML-comment fence or a
validated-unique span) that the validator proves resolves to EXACTLY ONE span; the precondition binds
anchor-identity AND region-sha.

RESIDUAL (B): git-object-hash vs raw-sha domain choice (folded into B1's native-domain fix); base_head TOCTOU + the
managed-ref races (Adversary A/C lens); journal-write-loss (3.4 orders writes after the effect + keys by
op_id+observed_post).

## Adversary C -- frontier loop, mirrors & declared-impact completeness

**C1 CRITICAL -- content-op postconditions are sha256(own payload) -- the Frontier both authors and grades,
recreating the self-grading failure mode (D-0107/D-0109).** On a precondition-divergence the correction re-derives
the payload against the new prior state, so the engine necessarily accepts postcondition = sha(the new payload the
Frontier just wrote). A Frontier that over-claims (CURRENT_STATE "SP3: DONE" when it is at bar N) has its payload
written, sha recomputed, asserted == postcondition -- trivially true. REBUILD folds the map from the over-claim
(render --check passes; consistency passes -- every surface was re-derived from the same over-claim). Every gate is a
consistency/fidelity check, none a truth check; the over-claim ships green -- exactly the burned mode. FIX: a
`frontier` content op's postcondition MUST NOT be a hash of its own output; require a mandatory INDEPENDENT-grader
validator edge whose predicate checks the CLAIM vs EVIDENCE; SEAL fails if any frontier content op lacks it.

**C2 CRITICAL -- SEAL "journal all-verified" contradicts mirror-divergence "the LOCAL close STANDS SEALED" -- a stuck
mirror during a multi-day pause makes the close non-terminable.** (Converges with A5.) A failed mirror op leaves the
journal non-all-verified, so SEAL never writes final_head/the idempotence marker; the close is committed to canonical
yet has no terminal SEAL, and its only outstanding op is a mirror op that may stay divergent for days -- INV-3 ("a
SEALED txn re-run is a no-op") can never engage. FIX: remove mirror ops from the SEAL assertion; SEAL over the
canonical op set only (PLAN..SHIP); mirror ops carry a terminal `deferred` state and run post-SEAL, keyed off
final_head.

**C3 HIGH -- an inbound reference outside boot_read U map-rendered is invisible to declared-impact AND to the OQ7 net
-- a real stale neighbour ships, violating D-0155.** At i62/i63 impact edges are AUTHORED, not derived. Construct a
sink outside both scopes: the close bumps iteration + rewrites CURRENT_STATE, and a research digest / a
PROCESS_BACKLOG cross-reference / a handoff snapshot contains a hand-authored "as of i61, SP3 is at bar N"; the author
forgets a depends_on edge; PRE-VALIDATE never checks it, REBUILD builds no view for it, POST-VALIDATE's "0-stale on
boot_read" + render --check + consistency all skip it (not in their coverage sets) -> it ships stale. FIX: the
REBUILD-phase completeness assertion must cover the FULL inbound-reference closure (a cheap grep-closure over
core-docs), failing closed if any referrer of an edited target is neither a declared depends_on sink nor 0-stale; if
the closure can't be computed, withhold the LIVE cutover until i64 derives impact.

**C4 HIGH -- correction termination is unbounded -- the budget is PER-OP (a cross-op flip-flop never trips it), it is
not journalled (resume resets it), and escalation hangs the close indefinitely.** close-consistency is a global
property; correcting surface A to agree with B re-breaks A<->C (a new failing predicate on op-C), which re-breaks
A<->B: the loop rotates across DIFFERENT ops so no single op's budget exhausts. Even on exhaustion, the journal has no
correction counter, so a multi-day resume re-attempts with a FRESH budget. Genuine escalation ("a human MAY
intervene") has no timeout/default -> an ABORTed close sits with a dirty tree waiting for a human for days. FIX: a
TRANSACTION-level max_corrections_total in addition to per-op; journal the counter per op AND per transaction (resume
continues, never resets); on escalation do NOT block -- write a correction-exhausted terminal ABORTED-resumable state
that leaves canonical HEAD untouched, so the session frees itself and the human's fix is a NEW planned close.

**C5 HIGH -- `semantic_owner` is an unenforced free field -- a Frontier-authored payload labelled `deterministic`
skips its task-spec/audit and masquerades as mechanically verified.** The i62 validator checks field presence, not
that a `deterministic` op's payload is engine-derivable; an op with semantic_owner=deterministic + a hand-written
prose payload + a sha postcondition needs no task spec / DELEGATION-DECISION record; the audit projection then shows
a "deterministic, mechanically verified" op with no delegation record -- the boundary INV-7 hinges on is bypassed by
one word. FIX: `deterministic` MEANS reproducible -- the engine independently derives the payload and fails closed if
declared != derivation; a non-reproducible op is by definition `frontier` and MUST carry a task spec; the validator
enforces the derivability check.

**C6 HIGH -- `replace_doc` is permitted on the append-only DECISION_LOG with only a content-sha postcondition -- a
bad payload silently truncates the provenance spine.** A Frontier correction emits a whole-file replace_doc that
accidentally drops older D-entries; the sha postcondition (of the new whole file) is satisfied; doc-commit-gate
verifies the NEW entry is present + well-formed but nothing asserts the prior entries survived; consistency compares
to the now-truncated ledger; INV-7 keeps the human out of the routine loop -> the append-only decision-provenance
ledger (the substrate independent audits rely on) is truncated, shipped, mirrored, no gate, no human. FIX: forbid
`replace_doc` on append-only/monotonic targets at schema level; add a no-truncation invariant to doc-commit-gate
(prior D-entry ids subset of post); make historical removal a class requiring explicit human authorization.

**C7 MEDIUM -- GitHub mirror-divergence retry has no rule distinguishing our-stale-lease from independent remote work
-- the "local STANDS" recovery force-clobbers a legitimate contribution.** A RECONCILE interrupted before the push +
a two-day pause; a teammate/CI pushes a real commit; on resume the --force-with-lease expected-old-oid is stale ->
correctly REJECTS; the recovery "re-fetch + re-verify" is undefined for independent-work-vs-our-stale-lease and, per
"the local close STANDS / GitHub is a convenience mirror", implies re-fetch the new oid + force-push local ->
destroying the teammate's commit. FIX: before any retry, require the fetched remote HEAD to be an ANCESTOR of the
last mirrored final_head; if the remote has commits NOT descended from a prior SEAL's final_head, do NOT auto-force --
surface `mirror-foreign-commits` for explicit resolution.

**C8 MEDIUM -- the Project mirror re-mirrors only CHANGED docs -- deletions/supersessions leave stale orphans in the
human's steering projection; "content-idempotent" is false under deletion.** A close that deletes/relocates a
core-doc changes nothing "re-mirror the CHANGED docs" will touch for the removed path; the Project retains the
orphaned superseded copy; project_search returns a superseded doc as current -- the human's only steering window
shows a doc canonical no longer has; re-running never converges the Project to canonical. FIX: make the Project
mirror a FULL reconcile -- compute the delete/rename set + REMOVE orphaned/superseded docs; the postcondition asserts
Project doc-set == canonical core-docs set by path + content hash.

RESIDUAL (C): base_head TOCTOU under the git single-commit lock (Adversary A); fingerprint EOL/mount normalization
(Adversary B); adjacent-region idempotence (A7); journal-write-loss durability (3.4) -- all flagged, out of this lens
except where they compound C1/C4.

## Clustering -> hardening items (all folded into the hardened contract)

| # | cluster | raw breaks | sev |
|---|---|---|---|
| CB-FP | canonical native-byte fingerprint domain (no plan-time frontier sha; native-git source only; raw, no EOL-normalize; declared per-file EOL; frozen for resume) | A4,B1,B2,B3 | CRITICAL |
| CB-SEAL | SEAL bounds CANONICAL only + precedes RECONCILE; mirror ops post-SEAL, terminal `deferred`, excluded from the all-verified assertion | A5,C2 | CRITICAL |
| CB-SHIP | SHIP is lease-atomic via a staging-ref + fast-forward cutover; single lease across all commits; re-assert HEAD in {base_head U own commits} at SHIP and at resume; appends re-read/merge at commit; strict ship-false-negative recovery; bounded/preemptible lease + wedge detection | A1,A2,A3,A6 | CRITICAL |
| CB-GRADE | a Frontier content op's postcondition is NOT a hash of its own output; a mandatory INDEPENDENT-grader validator edge (claim-vs-evidence) per Frontier content op; SEAL fails without it | C1 | CRITICAL |
| CB-DERIVE | `semantic_owner:deterministic` MEANS engine-reproducible: the engine re-derives the payload + fails closed on mismatch; non-reproducible => `frontier` (task-spec required); validator enforces | C5 | CRITICAL |
| CB-ANCHOR | region/append identity by STABLE semantic anchors (unique fenced markers); validator asserts exactly-one-span, non-overlapping, dependency-serialized multi-edits per file | A7,B6,B7 | HIGH |
| CB-VIEW | map-refold postcondition = DOUBLE-RUN byte identity (independent processes) with pinned determinism knobs; volatile-field allowlist (embedded sha/freshness excluded); sha-embedding moved to a post-SHIP stamp op | B4,B5 | HIGH |
| CB-IMPACT | REBUILD completeness assertion over the FULL inbound-reference grep-closure of every edited target; fail-closed on an undeclared referrer; refuse to go LIVE (i65/i67) until i64 derivation lands | C3 | HIGH |
| CB-TERM | transaction-level `max_corrections_total` + journalled per-op AND per-transaction counters (resume continues, never resets); escalation writes a terminal ABORTED-resumable leaving canonical untouched -- never a live-held hang | C4 | HIGH |
| CB-LEDGER | forbid `replace_doc` on append-only/monotonic targets; a no-truncation invariant in `doc-commit-gate` (prior ids subset of post ids); historical removal requires explicit human authorization | C6 | HIGH |
| CB-MIRROR-FF | GitHub retry: the fetched remote HEAD must be an ancestor of the last mirrored `final_head`; foreign commits (not descended from a prior SEAL) -> surface `mirror-foreign-commits`, never auto-force-clobber | C7 | MEDIUM |
| CB-MIRROR-DEL | the Project mirror is a FULL reconcile (compute + apply the delete/rename set); postcondition Project doc-set == canonical `core-docs/` set (path + content hash) | C8 | MEDIUM |

## Verdict
The design's ARCHITECTURE HELD (manifest + phases + journal + resume + Frontier-in-the-loop is sound); it was
UNDER-SPECIFIED at exactly the load-bearing seams this box has been burned on before: byte/EOL identity,
lease/commit atomicity, self-grading, and mirror/seal ordering. The 12 hardening items close those seams. Two are
ratification-blocking in spirit (CB-GRADE + CB-SEAL): a contract that lets a self-graded over-claim ship, or that
strands a close un-sealed on a mirror hiccup, is not safe to build a live cutover on. The hardened contract is the
authoritative i62 artifact.
