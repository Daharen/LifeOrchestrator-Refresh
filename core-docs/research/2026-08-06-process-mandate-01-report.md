# PROCESS MANDATE 01 -- SUNSET METASTABILITY REPORT (i40, 2026-08-06)

**Produced per `PROCESS_MANDATE.md` s3 at `sunset_iteration=40` (opened i32, D-0094), BEFORE any i40 wave work.**
State transition: ACTIVE -> REPORT_DUE -> SUNSET. The mandate doc is archived to
`archive/mandates/mandate-01-i32-i40.md` and removed from (or replaced in) `core-docs/` per s4; THIS report is the
durable record. All numbers below are measured (byte counts from `wc -c` at HEAD `2c7ee0e`; trend rows from
`ops/out/doc-health-log.jsonl`; session discipline from `git log -- core-docs/PROCESS_MANDATE.md`).

## 1. Item dispositions (s3.1)

**PB-1 -- the deterministic fail-closed doc-hygiene commit GATE: DEFERRED (not built).** Highest-priority item;
its trigger ("next doc-tooling touch") occurred at least once -- the i38-close build of the doc-health MONITOR
(`ops/audit/gen-doc-health.py`, D-0101 tier A0.5), which already parses the DOC_PROTOCOL s2 budget table (the
gate's exact input) -- yet no gate was built. What exists is DETECTION only: 8 monitor rows since 2026-08-05, every
one recording `over: 4` docs while doc-growing commits continued (worst_pct 162 -> 181 -> 184 -> 191 across heads
`a0a21ab`/`e6b0684`/`a213050`); nothing refused anything. Disposition: carried into mandate 02 (s4 below) as a
NAMED BUILD UNIT with a hard deadline -- the prose trigger demonstrably does not fire action.

**PB-2 -- the reserved subagent delegation seam: DEFERRED (correctly; reserve-don't-build held).** No premature
router was built. NOTE for the license decision: the trigger state CHANGED at sunset -- subagents ARE now available
in the cloud orchestrator workflow (the Agent tool), and >=3 recurring judgment-hygiene tasks have accrued (handoff
slim every close; CURRENT_STATE/MODULE_ROADMAP currency; producer/consumer reconciliation, e.g. PB-5; index density
upkeep). Whether in-session cloud subagents sit inside the D-0051-as-amended boundary (external/frontier driving
prohibited; a deterministic LOCAL coordinator authorized) is NICHOLAS'S ruling to make, not an orchestrator call.
Disposition: carried into mandate 02 as a decision item, build only if licensed.

**PB-3 -- slim the over-budget hot docs: DEFERRED to its own deadline (i40); being executed THIS session.**
Measured at the sunset date: CURRENT_STATE 63,108 B / 34 KB budget (185%), FANOUT_ORCHESTRATOR_HANDOFF 47,286 B /
24 KB (197%), MODULE_ROADMAP 48,983 B / 37 KB (132%); also over: PROJECT_DIRECTION 120%, ARCHITECTURE_MAP 110%,
MEMORY_ARCHITECTURE 101%. These are the WORST readings in the monitor's log window -- the debt grew UNDER the
mandate. Two pre-slim snapshot rounds exist (`archive/doc-snapshots/2026-07-29/`, `2026-08-03/`) and re-bloat
followed each (the D-0090/91/92 index re-bloat one session after a slim was already PB-1's evidence row).

**PB-4 (added post-open) -- audit-pipeline increments: PARTIALLY SHIPPED, healthy.** A0.5 monitor (i38 close), A1
widgets/05 (`3ad71d3`) + widgets/06 (`c912854`), A2 widgets/07 (`855c242`). Its cadence header (review_due) was
honored -- bent and recorded, never silently dropped. Carries forward under its own PROCESS_BACKLOG row regardless
of mandate outcome.

**PB-5 (added i39) -- #37 fold-reconciliation + version hygiene: SCHEDULED.** Deterministic trigger ("next #37
touch OR i40") fires now; it is an i40 lane (D-0108).

## 2. The four control dimensions (s3.2)

**(a) Stale-content PREVENTION: manual-only.** The rules exist (DOC_PROTOCOL s3 REPLACE-don't-append; s9 step-5
size check) but nothing refuses a violating commit, and the checklist was measurably skipped: the i39 close +
D-0109 commits grew the handoff 40,692 -> 45,944 -> 47,286 B (170% -> 197%) while the monitor logged it. The
monitor detects bloat post-hoc; it prevents nothing.

**(b) RECOVERY: partially-mechanized.** Deterministic RESTORE exists and is exercised: git history + immutable
`archive/doc-snapshots/<date>/` + `ARCHIVE_INDEX.md`; nothing is ever destroyed; doc commits are named-files-only
under the git lease. RE-LAYERING does not: three docs now exceed the ~40 KB bounded-read threshold (mandate s6)
with no re-layer plan on file -- the s2 "shard + route to retrieval" path was never invoked.

**(c) MEMORY: partially-mechanized.** The substrate the docs were meant to migrate into EXISTS and is
acceptance-proven (Tier-1 accepted i36 D-0102; #36 0.7.0 fast-beam i39), and the measurement layer exists (per-doc
density + worker-spec growth: 8,604 B at i9 -> 39,128 B peak at i34 -> 23,537 B at i39). But the docs corpus is
NOT onboarded -- zero core-docs are #36-retrievable records; the hot set is NOT bounded in practice (see PB-3).

**(d) LOCAL controls (what holds without a frontier agent): partially-mechanized, with a known epistemic gap.**
Local + deterministic and real: dev.ship fail-closed gates (sha256/AST/tests), the D-0077 fold harnesses, res.lease
serialization, heartbeat/watchdog, the doc-health monitor. But BOTH material over-claims of this epoch (the i38
and i39 `p0_1_gate_status=pass` claims, D-0107/D-0109) were caught ONLY by the couriered frontier review -- no
local mechanism caught either. Local controls hold infrastructure invariants, not yet epistemic ones.

## 3. Metastability verdict (s3.3): **NO** (evidence-based)

What DID hold under the mandate -- the posing machinery worked: the countdown was updated 8/8 orchestrator sessions
i32 -> i39 with zero human re-poking (commits `c689d92`, `41410d8`, `289fed1`, `efb58e8`, `ac726bd`, `9d9c4cc`,
`30854a4`, `a213050`); PB-4's cadence was honored; PB-5 was captured as a backlog row per the capture rule instead
of a drifting handoff residual; the monitor was built unprompted.

Why the verdict is still NO for the forward-looking question ("will roadmap + backlogs keep being considered +
posed WITHOUT front-loading or a human re-poking?"):

1. The forcing function that produced the 8/8 discipline was the MANDATE ITSELF (per-session check + hard sunset),
   and it self-deletes today. What remains is prose (handoff standing lines, DOC_PROTOCOL s9) -- the exact control
   class that measurably failed both before the mandate (the i25->i32 drift that motivated it) and during it (s9
   step-5 skips, section 2a).
2. Posing did not converge the debt: the highest-priority mechanization (PB-1) shipped nothing in 8 iterations,
   and the hot-doc debt is at its measured worst on the sunset date (section 1, PB-3).
3. The epoch's two substantive self-report failures (D-0107, D-0109) were caught only by the frontier lane --
   consideration-at-intervals is not the same as self-correction, and nothing local yet enforces the difference.

Per s3.4, a NO verdict requires proposing mandate 02 for Nicholas to license. The s5 sealed check is NOT initiated
(it activates only on YES).

## 4. Proposed MANDATE 02 (for Nicholas to license; draft delivered alongside this report)

Same architecture (small, high-attention, time-boxed, self-deleting; cheap per-session check; sealed-check design
carried). Proposed knobs: `opened_iteration: 40`, `sunset_iteration: 47`, budget 12 KB. Governs:

- **M2-A (PB-1, now a BUILD unit with a deadline, target <= i42):** the deterministic fail-closed doc gate wired
  into the executor doc-commit path -- density + proportional budget + re-layer trigger; reuse
  `gen-doc-health.py`'s budget parsing as the library. The monitor stays the dashboard; the gate becomes the pawl.
- **M2-B (PB-3 completion + hold):** the i40 slim closes the acute debt; the gate (M2-A) holds it; any doc still
  over the bounded-read threshold after slimming gets a recorded re-layer plan instead of endless re-slims.
- **M2-C (docs-into-memory, the s2 principle, now unblocked):** Tier-1 is accepted and #36 is proven -- onboard
  the docs corpus (sharded history/cold layers as #36-retrievable records) as the re-layer path.
- **M2-D (verification-before-ratification, the D-0107/D-0109 lesson made structural):** any gate-status flip
  (p0_1_gate_status or successor safety gates) requires the independent as-built review PASS to be IN HAND before
  the orchestrator ratifies the contract section. This is a mandate PRINCIPLE so it survives handoff compression.
- **M2-E (PB-2 decision item):** Nicholas rules whether in-session cloud subagents are inside the D-0051-as-amended
  boundary; build the delegation seam only if licensed AND the >=3-recurring-tasks condition still holds.

If mandate 02 is licensed, it replaces `core-docs/PROCESS_MANDATE.md` in place (s4); if declined, the live doc is
deleted, PB-1/PB-2/PB-3 remain PROCESS_BACKLOG rows with their existing (weaker, prose) triggers, and the next
forcing function is whatever PB-1's row eventually bites on.

## 5. Sunset mechanics (s4) -- executed this session

Header set to `current_iteration: 40 / iterations_to_sunset: 0 / state: SUNSET`; doc copied to
`archive/mandates/mandate-01-i32-i40.md`; one line appended to `archive/ARCHIVE_INDEX.md`; live doc deleted or
replaced per the license decision; this report committed at `core-docs/research/2026-08-06-process-mandate-01-report.md`
and mirrored to the Project. Recorded as a D-entry (D-0110) with the license outcome.
