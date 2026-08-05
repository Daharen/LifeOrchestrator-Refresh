# PROCESS_MANDATE -- the live, SUNSETTING process-hygiene mandate (mandate 01)

Machine-checkable header (an orchestrator reads these at session start):
- `mandate_id: 01`
- `opened_iteration: 32`
- `current_iteration: 36`   (updated each orchestrator session)
- `iterations_to_sunset: 4`   (COUNTDOWN -- at 0, state -> REPORT_DUE; s1)
- `sunset_iteration: 40`
- `sealed_check_offset_iterations: 7`
- `state: ACTIVE`   (ACTIVE | REPORT_DUE | SUNSET | RE-LICENSED)
- `governs:` PROCESS_BACKLOG PB-1..PB-3 + the s2 principles

## 0. Why this doc exists (and why it deletes itself)
Deferred process/hygiene fixes were either swept under the rug (doc-debt drifted i25->i32) OR would be
front-loaded and stall the primary roadmap. This mandate is the middle path: a SMALL, HIGH-ATTENTION, TIME-BOXED
agenda that MUST be addressed while live, and that DELETES ITSELF at `sunset_iteration` after a mandatory report.
The DEADLINE -- not per-iteration mandatory progress -- is the forcing function (a rule demanding progress every
iteration becomes theater; a hard expiry + a report does not). This doc is the MEMORY of what we owe the process;
the mechanical gate (PB-1) is the ALARM.

## 1. The per-session check (the ONLY mandatory step; keep it cheap)
At the START of every orchestrator session, after the handoff:
**First, update the COUNTDOWN:** set `current_iteration` to this session's iteration and recompute
`iterations_to_sunset = sunset_iteration - current_iteration` (the handoff TL;DR surfaces it) -- the
machine-checkable sunset countdown, so the i40 expiry is never forgotten. Then:
1. Read the header. If `current_iteration >= sunset_iteration` -> set state REPORT_DUE and produce the s3 report
   BEFORE new wave work, then archive (s4).
2. Else: for each open item (s2), confirm on-track / blocked / deliberately-deferred, and that NO item has sat
   untouched past its interval. Record a one-line status. Do NOT force progress on all of them.
3. That is all -- a status pass + the expiry check, NOT a mandatory build.

## 2. The agenda -- principles first (so a fresh session inherits the WHY, not just the tasks)
- **Mechanize prevention, not cure.** Deterministic fail-closed gates make the bad state un-committable;
  "self-healing" needs the same unreliable attention it is meant to fix. Robustness = many small dumb gates, not
  one clever meta-loop.
- **The builder obeys the same contract as the built.** The memory architecture's Tier-0 invariants (bounded hot
  set, deterministic skeleton, provisional+validated model output, explicit slow path) apply to the OPERATING
  docs + the agent loop, not just stored data. An un-gated operating layer bloats the memory it runs.
- **Budgets are PROPORTIONAL, never static.** A fixed byte cap set at the starting size is the "ceiling at the
  start" anti-pattern -- it fires on legitimate growth, trains dismissal, becomes theater. The metric is DENSITY
  (bytes per state); budget = density_cap x state_count x headroom, recomputed. Fire on rising density (bloat),
  never on rising state count (growth).
- **Re-layer at the bounded-read threshold; don't slim forever.** When a hot doc, even at good density, would
  exceed what the WEAKEST operator (the 9B) can ingest whole, shard it + index-the-index + route cold layers to
  retrieval (#36). That IS the memory bounded-fanout hierarchy + slow path -> the docs are the FIRST corpus the
  memory system should own; process-hygiene + memory MERGE at scale.

Open items (detail + triggers in `PROCESS_BACKLOG.md`):
- **PB-1** the doc-hygiene commit GATE (density check + proportional budget + a re-layer trigger). The archetype
  deterministic scope gate + the forcing function for the rest. HIGHEST priority. Interval: every doc-tooling touch.
- **PB-2** the RESERVED subagent delegation seam (build when subagents exist AND >=3 recurring judgment-hygiene
  tasks accrue). Interval: re-check when subagents deploy.
- **PB-3** slim the over-budget hot docs -- at the i32 fold/close + whenever PB-1 forces it.

## 3. The sunset REPORT (MANDATORY at `sunset_iteration`; blocks new wave work until produced)
A `research/<date>-process-mandate-01-report.md` stating, with measured evidence (not vibes):
1. Per item PB-1..PB-3 (+ any added): SHIPPED (commit) / DEFERRED (why + new trigger) / DROPPED (why).
2. The four control dimensions -- what level we can now EXPECT, each scored none / manual-only /
   partially-mechanized / fail-closed-mechanized: (a) stale-content PREVENTION; (b) RECOVERY (can a bloated or
   broken doc be restored / re-layered deterministically?); (c) MEMORY (are docs becoming retrievable records; is
   the hot set bounded?); (d) LOCAL controls (what holds without a frontier agent?).
3. **Metastability verdict (YES/NO + evidence):** will the roadmap + backlogs keep being considered + posed at
   intervals WITHOUT front-loading or a human re-poking?
4. NO -> propose mandate 02 (fresh goals + a new sunset) for Nicholas to license. YES -> initiate the sealed check (s5).
Then set state SUNSET and archive (s4).

## 4. Sunset / archive
On report delivery: copy this doc to `archive/mandates/mandate-01-i32-i<sunset>.md`, add a line to
`archive/ARCHIVE_INDEX.md`, and DELETE the live `PROCESS_MANDATE.md` (or replace it in place with mandate 02 if
re-licensed). The report is the durable record; the mandate itself is disposable by design.

## 5. The SEALED-CHECK protocol (a blind regression test for the process; DESIGN -- activated only on a YES verdict)
Metastability claimed by a report can be self-deceiving, so we prove it blind:
1. At the YES verdict, create `SEALED_CHECK_<open_iter>.md` holding ONLY machine-checkable PREDICATES about system
   health, chosen so intervening sessions cannot teach-to-the-test (they never see the exact predicates). Examples
   (deterministic, evaluable against the repo later): every hot doc's density <= its cap; the PB-1 gate exists AND
   its run-log shows >=1 real firing; no hot doc exceeds its proportional budget without a recorded re-layer plan;
   every PROCESS_BACKLOG open item has a status touched within its interval; the prior mandate's report exists +
   was on time; all DECISION_LOG_INDEX cells <= the density cap. Add `open_after_iteration: <open_iter + offset>`
   + a content hash (tamper-evidence).
2. A `SEALED -- DO NOT OPEN before iteration N` banner; earlier sessions skip it via a one-line header check.
3. At `current_iteration >= N`, a CHECK session opens it, evaluates every predicate deterministically, writes a
   pass/fail per predicate. ALL pass -> the constructs held under real unsupervised operation. ANY fail ->
   re-license a mandate targeting the regressed predicate(s). The seal makes it honest: you cannot optimize for a
   target you cannot read; you can only keep the system actually healthy.

## 6. Knobs (defaults chosen to get off the ground; ratifiable by Nicholas)
- `sunset_iteration` = 40; `sealed_check_offset` = 7 iterations.
- **bounded-read threshold** (PB-1 re-layer trigger) = DEFAULT ~40 KB per hot doc read-whole, pegged to the
  weakest operator (the 9B) -- ADJUST to the 9B's real usable context. The one number most worth setting.
- index density cap ~160 chars/cell; other docs set a per-state cap when PB-1 is built.
- This doc's OWN budget is a legitimate STATIC cap (fixed structure, one mandate, replaced per epoch -- it does
  NOT grow with states), unlike the index/log (which must go proportional).
