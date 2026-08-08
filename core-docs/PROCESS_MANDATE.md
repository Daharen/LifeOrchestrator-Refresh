# PROCESS_MANDATE -- the live, SUNSETTING process-hygiene mandate (mandate 02)

Machine-checkable header (an orchestrator reads these at session start):
- `mandate_id: 02`
- `opened_iteration: 40`
- `current_iteration: 42`   (updated each orchestrator session)
- `iterations_to_sunset: 5`   (COUNTDOWN -- at 0, state -> REPORT_DUE; s1)
- `sunset_iteration: 47`
- `sealed_check_offset_iterations: 7`
- `state: ACTIVE`   (ACTIVE | REPORT_DUE | SUNSET | RE-LICENSED)
- `governs:` M2-A..M2-E below (PROCESS_BACKLOG PB-1/PB-2/PB-3 successors + the s2 principles)
- `licensed_by:` Nicholas, i40 (D-0110); predecessor: mandate 01 (i32-i40, report
  `research/2026-08-06-process-mandate-01-report.md`, verdict NO -> re-licensed per s3.4)

## 0. Why this doc exists (and why it deletes itself)
Mandate 01 proved the per-session posing machinery works (8/8 countdown discipline, zero re-poking) and proved
posing alone does not converge debt: PB-1 never shipped, the hot docs hit their measured worst on the sunset date,
and both P0-1 over-claims were caught only by the frontier lane. Mandate 02 exists to convert that diagnosis into
mechanization, on the same self-deleting architecture: a SMALL, HIGH-ATTENTION, TIME-BOXED agenda with a hard
expiry + a mandatory report. The DEADLINE is the forcing function; the report is the durable record.

## 1. The per-session check (the ONLY mandatory step; keep it cheap)
At the START of every orchestrator session, after the handoff:
**First, update the COUNTDOWN:** set `current_iteration` to this session's iteration and recompute
`iterations_to_sunset = sunset_iteration - current_iteration` (the handoff TL;DR surfaces it). Then:
1. Read the header. If `current_iteration >= sunset_iteration` -> set state REPORT_DUE and produce the s3 report
   BEFORE new wave work, then archive (s4).
2. Else: for each open item (s2), confirm on-track / blocked / deliberately-deferred, and that no DEADLINE item
   (M2-A) has slipped past its target without a recorded reason. Record a one-line status.
3. That is all -- a status pass + the expiry check, NOT a mandatory build.

## 2. The agenda

Principles (inherited from mandate 01, still governing): mechanize prevention, not cure / the builder obeys the
same contract as the built / budgets are PROPORTIONAL, never static / re-layer at the bounded-read threshold,
don't slim forever. NEW principle (the D-0107/D-0109 lesson): **verification-before-ratification** -- a
self-reported gate result is a CANDIDATE; only the independent as-built review's PASS makes it ratifiable.

Items (detail stays in PROCESS_BACKLOG rows + D-entries; this list is the mandate's scope):

- **M2-A (PB-1 successor) -- the deterministic fail-closed doc-hygiene commit gate. SHIPPED i42 (D-0117; the
  HARD DEADLINE was MET).** `ops/audit/doc-commit-gate.py` (pure stdlib, fail-closed, staged-blob-measured) +
  a git pre-commit hook (installed by `ops/install-doc-gate.bat`; presence/hash asserted by `gen-doc-health.py`)
  + a `--files` commit-task invocation; the three D-0094 parts (accretion tripwires + proportional s2 budgets via
  `parse_budgets()` + the re-layer trigger at the bounded-read threshold). ACCEPTANCE MET -- a real firing through
  the executor path (REJECT the over-budget probe + report, then PASS the corrected commit) logged to
  `ops/out/doc-gate-log.jsonl` (commits `fd3da12`..`25bf2b3`; gate tests 26/26 + hook-presence 5/5). The monitor
  stays the dashboard; the gate is the pawl.
- **M2-B (PB-3 successor) -- hold the hot docs under budget.** From i42 the M2-A gate holds this MECHANICALLY
  (fail-closed at commit). i42 s1 sizes: all hot docs under budget; CURRENT_STATE the tightest at ~99% of its
  34 KB cap -> the first M2-C re-layer candidate. Any doc over the ~40 KB bounded-read threshold gets a recorded
  RE-LAYER plan (M2-C path), not another slim pass.
- **M2-C -- docs-into-memory (the re-layer path, now unblocked).** Tier-1 accepted + #36 proven: onboard the docs
  corpus -- sharded history / cold layers become #36-retrievable records; hot docs keep only NOW + pointers.
  Scope ONE increment when a lane is spare (same non-displacing rule as PB-4); the first increment is a design
  note naming which doc shards first and its record schema. Trigger: first spare coding lane after M2-A ships.
- **M2-D -- verification-before-ratification (structural).** Any safety-gate status flip (p0_1_gate_status or
  successors) is ratified in its contract ONLY with the independent as-built review PASS in hand. The orchestrator
  session that ratifies names the review pack id in the D-entry. (i40 applies this to the P0-1 gate: s7 stays
  walked-back until the re-review returns PASS.) **RESULT (i42, D-0118): the round-5 re-review returned PASS -> s7 ratified to `p0_1_gate_status=pass` naming pack `6bb613ea`; the discipline caught 2 over-claims (D-0107/D-0109) then converged honestly (7->7->5->3->0) to an independently-verified pass -- strong metastability evidence.**
- **M2-E -- RESOLVED i42 (D-0119, Nicholas): in-session cloud subagents are PERMITTED** inside the
  D-0051-as-amended boundary (frontier access stays human-couriered, D-0052). PB-2 (the delegation seam;
  delegation-decision events per D-0101) is UNBLOCKED -- BUILD it when >=3 recurring judgment-hygiene tasks hold
  AND a lane is spare (an i43+ candidate, non-displacing).

## 3. The sunset REPORT (MANDATORY at `sunset_iteration`; blocks new wave work until produced)
A `research/<date>-process-mandate-02-report.md` stating, with measured evidence (not vibes):
1. Per item M2-A..M2-E: SHIPPED (commit) / DEFERRED (why + new trigger) / DROPPED (why).
2. The four control dimensions re-scored (stale-content prevention / recovery / memory / local controls), each
   none / manual-only / partially-mechanized / fail-closed-mechanized, WITH the delta vs the mandate-01 report.
3. **Metastability verdict (YES/NO + evidence):** will the roadmap + backlogs keep being considered + posed at
   intervals WITHOUT front-loading or a human re-poking? (M2-A shipped + firing is the strongest YES evidence.)
4. NO -> propose mandate 03 for Nicholas to license. YES -> initiate the sealed check (s5).
Then set state SUNSET and archive (s4).

## 4. Sunset / archive
On report delivery: copy this doc to `archive/mandates/mandate-02-i40-i<sunset>.md`, add a line to
`archive/ARCHIVE_INDEX.md`, and DELETE the live `PROCESS_MANDATE.md` (or replace it in place with mandate 03 if
re-licensed). The report is the durable record; the mandate itself is disposable by design.

## 5. The SEALED-CHECK protocol (unchanged from mandate 01 s5; DESIGN -- activated only on a YES verdict)
At a YES verdict, create `SEALED_CHECK_<open_iter>.md` holding ONLY machine-checkable predicates about system
health (density caps, gate existence + >=1 real firing, re-layer plans on file, backlog statuses within interval,
report punctuality, index cell density), `open_after_iteration: <open_iter + offset>`, a content hash, and a
`SEALED -- DO NOT OPEN before iteration N` banner. At `current_iteration >= N` a check session evaluates every
predicate deterministically; ALL pass -> the constructs held unsupervised; ANY fail -> re-license a mandate
targeting the regressed predicates. You cannot optimize for a target you cannot read.

## 6. Knobs (ratifiable by Nicholas)
- `sunset_iteration` = 47; `sealed_check_offset` = 7 iterations; M2-A deadline = i42 close.
- bounded-read threshold (M2-B/M2-C re-layer trigger) = ~40 KB per hot doc read-whole, pegged to the weakest
  operator (the 9B) -- adjust to the 9B's real usable context when measured.
- index density cap ~160 chars/cell; per-doc density caps set when M2-A lands.
- This doc's OWN budget stays a legitimate STATIC cap (12 KB; fixed structure, one mandate, replaced per epoch).
