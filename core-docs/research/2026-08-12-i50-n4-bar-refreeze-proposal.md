# N4 -- PCB MIGRATION-GATE BAR RE-FREEZE

**RATIFIED 2026-08-12 as D-0140** (Nicholas, all three s7 calls set to the recommended option). This
digest is the reasoning behind the re-freeze; the authoritative frozen rules live in D-0140 and
`modules/44-project-map/eval/results/N4_BAR_REFREEZE.md`. Staged by Fanout Orchestrator i50 (Fable seat).

Scope: replaces ONLY the s7 **efficiency** rules of the frozen `I47_EVAL_PACKET`; the s1-s6 mechanics
(task pick, blinding, isolation, C-adjudication) and the s7 **quality** floors (a)-(d) are UNCHANGED, and
the packet bytes are untouched (the supersession is recorded, not edited in). Grounding:
`eval/results/I47_RESULTS.md` (s3) + `I48_RECHECK_RESULTS.md` (F1-F5) + D-0133/D-0136/D-0138.

## 1. What N4 is

N4 re-freezes the numeric/logic bars the migration gate uses to decide whether booting from the PCB
BOOT_PACKET beats booting from the legacy handoff. It is a **ratification act**, not a code wave and not a
gate run. It exists because amending a frozen experiment mid-arc is exactly the over-claim risk the M2-D
discipline (D-0107/D-0109) guards against -- so it required explicit Nicholas ratification. A *future*
iteration stages and runs the fresh gate against these bars.

## 2. The retired I47 s7 efficiency rules

| rule | I47 definition | i48 re-check |
|---|---|---|
| VOID (a) RT2-F9 | B opens the legacy handoff, no START_HERE route -> all efficiency claims VOID | TRIPPED (B row 19, "wave canon + deferred menu") |
| VOID (b) | B total > 0.9 x A total -> VOID | TRIPPED (862,987 > 628,667) |
| Bar 1 (boot) | B boot <= 0.5 x A boot(narrow) | MISS (18,724 vs 15,920, +17.6%) |
| Bar 2 (total) | B total <= 0.7 x A total | MISS (862,987 vs 488,963; B = 1.24x A) |

The s7 **quality** floors (missing/contradicting an absolute item; B < A by >=1 mean on comprehension or
constraint; a confirmed fabricated citation; step-0 skipped) are unchanged. N4 does not touch quality.

## 3. Why the bars are dead (i48 F1-F4)

**F2 (headline) -- the boot bar is arithmetically unreachable post-CD-1.** Bar 1 = 0.5 x A-narrow =
15,920 B; after the ~3.0 KB dispatch and ~0.6 KB step-0 that leaves ~12.3 KB for the packet -- but the
packet is 16,640 B (i49) *because CD-1 added the OPERATIONS canon the i47 run was faulted for lacking*.
The fix the CONDITIONAL demanded and the frozen bar are in direct tension; a complete packet can no longer
meet a bar calibrated to the pre-canon ~13 KB packet.

**F1 -- the whole-file byte proxy mis-measures the PCB.** The proxy counts the WHOLE file per open. In i48,
B's raw-store fallback -- harvest-eval.json 478,784 + project_map.py 90,116 + arch-positions.json 82,474 =
**651,374 B** -- dominated B's total (~75%) and made B 1.24x A. B fell back to raw greps because the deep
narrative (module `purpose` strings, SCHEMA_NOTES content) was not query-reachable. **i49's N1 fixed that**:
those facts now return as bounded queries -- module purpose **5,662 B**, a SCHEMA_NOTES section **7,684 B**,
versus the **478,784 B** whole-file grep. The bar must credit the query surface N1 built.

**F3 -- the void clause conflates two opens.** RT2-F9 voids on ANY un-routed legacy open, but in i48 the
PCB answered the canon FIRST (probe rows 5-10, from BOOT_PACKET OPERATIONS + `ops:boot-*`); the later
handoff open was corroboration / frontier detail -- a thorough agent double-checking, not a PCB that
couldn't answer. N2 (i49) moved that frontier detail into the overlay, removing the open's i48 reason.

**F4 -- the packet under-documented the query verbs (closed by N3).** B read the 90 KB tool source; N3
shipped the verb table in the packet, test-asserted equal to the dispatcher.

**F5 (context) -- quality was never the problem.** Comprehension parity repeated in both i47 and i48; the
step-0 fail-closed gate proved itself in the field. The gate's only open deficiency is efficiency.

## 4. Design principles

1. **Boot = boundedness + completeness, not a ratio to A.** The PCB's value is a bounded boot that still
   carries the canon; it wins on bounded-completeness and on the TOTAL economy, not on boot bytes vs a
   hand-curated 24 KB cache.
2. **Total is measured WITH the query surface** -- query OUTPUT bytes for #44-query content, whole-file
   only for raw opens. Credits N1; incentivizes queries over greps.
3. **Void fires on PCB-insufficiency, not corroboration** -- but corroboration bytes still count, so it is
   never free.
4. **Still able to FAIL, still pre-registered.** Frozen in D-0140 before the next run; no post-hoc
   softening (D-0107/D-0109).

## 5. The re-frozen s7 efficiency rules (ratified)

| rule | definition |
|---|---|
| **Boot (absolute)** | `BOOT_PACKET renders <= 20,000 B` (the module's existing HARD guard) AND carries the CD-1 OPERATIONS canon, pointer-backed, degrade-LAST. Boot-total (packet + dispatch + step-0) reported for the record, not a pass/fail gate. Retires the unreachable 0.5 x A ratio (F2). Today: 16,640 B, canon present -> PASS. |
| **Total (with query surface)** | `B total <= 0.7 x A total`, where B total counts **query OUTPUT bytes** for content served by a #44 query op and whole-file bytes only for a genuine raw open; A counts whole-file (unchanged -- legacy has no query surface). Restores the 0.7x intent under accounting that credits N1 (F1). |
| **Void (PCB-insufficiency)** | VOID iff B opens a legacy/handoff doc for an answer **not already PCB-cited earlier in the same ledger**; a corroboration open does NOT void but its bytes still count. Replaces binary RT2-F9 (F3). |
| ~~Void (b)~~ | RETIRED as redundant with the 0.7x total bar. |

**Verdict mapping (unchanged in shape):** quality PASS AND boot PASS AND total PASS AND not-voided ->
migration licensed (PCB becomes default). Any efficiency bar unmet/voided -> stays CONDITIONAL, legacy
default.

## 6. Projected numbers (illustrative)

Re-accounting the i48 T3 B-ledger with N1/N2/N3 in place: B's 651,374 B raw fallback collapses to bounded
queries (~a few purposes ~17 KB + one-two sections ~15 KB, no tool-source read = ~32 KB). B total ~=
862,987 - 651,374 + ~32,000 **~= 244 KB** vs A 698,519 B -> **B ~= 0.35 x A** -- clears the 0.7x bar with
wide margin. The margin is *why* this is crediting a real win, not softening a bar: the PCB now plausibly
wins decisively once the metric stops counting a whole raw store against it, and it can still fail if the
projection is wrong -- which is the point of running the gate. (A fresh gate uses a fresh task; the
mechanism, not the number, is what N1 made query-granular.)

## 7. Ratification (the s7 calls, all recommended)

Total bar **0.7 x A** (over parity / 0.5x); boot **absolute packet <= 20,000 B + canon** (over an absolute
boot-total hard gate); void **PCB-insufficiency only** (over binary RT2-F9 / dropping the void). On
ratification the orchestrator committed D-0140 + the index row, wrote `N4_BAR_REFREEZE.md` beside the
eval results, and refreshed the handoff + CURRENT_STATE. **The gate was NOT run in i50; the LEGACY handoff
stays the default orchestrator bootstrap until a future iteration stages + runs it and it PASSES.**
