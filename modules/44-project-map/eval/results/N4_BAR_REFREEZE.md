# N4 -- MIGRATION-GATE BAR RE-FREEZE (ratified D-0140, 2026-08-12)

Supersedes the `I47_EVAL_PACKET` s7 **efficiency** rules for the NEXT legacy-vs-PCB gate run. The packet
bytes are UNCHANGED; s1-s6 and the s7 quality floors (a)-(d) carry forward. Ratified by Nicholas (digest:
`core-docs/research/2026-08-12-i50-n4-bar-refreeze-proposal.md`). Grounding: `I47_RESULTS.md` +
`I48_RECHECK_RESULTS.md` (F1-F4).

## Re-frozen s7 efficiency rules

1. **BOOT (absolute):** BOOT_PACKET renders <= 20,000 B (module HARD guard) AND carries the CD-1
   OPERATIONS canon, pointer-backed, degrade-LAST. Boot-total (packet + dispatch + step-0) reported, not
   gated. (Retires 0.5 x A-narrow -- unreachable post-CD-1, F2.)
2. **TOTAL (with query surface):** B total <= 0.7 x A total, counting query OUTPUT bytes for #44-query
   content and whole-file bytes only for raw opens; A counts whole-file (no query surface). (Credits N1;
   closes F1.)
3. **VOID (PCB-insufficiency):** VOID iff B opens a legacy/handoff doc for an answer NOT already
   PCB-cited earlier in its ledger; corroboration opens do not void but their bytes still count.
   (Replaces binary RT2-F9, F3.) The `B total > 0.9 x A` void-(b) is RETIRED (redundant).

## Verdict mapping (unchanged in shape)

Quality PASS (floors + parity) AND boot PASS AND total PASS AND not-voided -> migration licensed (PCB
becomes default). Any efficiency bar unmet/voided -> CONDITIONAL, legacy default.

## Status

The gate is now STAGEABLE against these pre-frozen bars. It was NOT run at ratification (i50). A later
iteration stages + runs it. Until it passes, the LEGACY handoff is the default orchestrator bootstrap.
