# N8 -- MIGRATION-GATE RE-RUN PROTOCOL RE-FREEZE (PROPOSED)

**STATUS: STAGED FOR NICHOLAS RATIFICATION (i52). NOT ratified; NO gate runs until it is.** Staged by
Fanout Orchestrator i52 (Fable seat) per the D-0142 directive. Scope: the D-0140/N4 **bars are byte-
unchanged** (boot absolute / total 0.7 x A / insufficiency void), and the I47 s1-s6 mechanics + s7
quality floors carry forward; N8 freezes the **run protocol** for the next gate -- task pool, accounting
conventions, pins, and checklist derivation -- the four things i51 had to resolve by bracketing or
adaptation DURING the run. Grounding: `modules/44-project-map/eval/results/I51_RESULTS.md` (F1 task-class,
F4 conventions, s6 anomalies 2-4, s7 N8) + the N4 pattern (D-0140).

## 1. Why ratification (M2-D)

i51's verdict is clean, but three protocol gaps were closed mid-run rather than pre-frozen: the listing +
staged-not-read accounting was resolved by BRACKETING (primary vs charitable -- verdict happened to be
identical under both; next time it may not be), adapted-K6 wording was re-scoped at adjudication (floor
(a) then turned on which reading of the adaptation you take), and the C-tier model deviated from its pin
(recorded, symmetric, but a deviation). A future GO decision rests on this experiment; its remaining free
variables get frozen by explicit ratification, not orchestrator discretion (D-0107/D-0109 discipline).

## 2. The calls

**Call 1 -- task pool (two-class).** RECOMMENDED: a fresh pre-registered pool of EXACTLY TWO tasks, frozen
at staging: T-map (map-native: system-structure / where-does-X-live / what-touches-Y -- the class the PCB
won in i48 projection) and T-prose (prose-governing: the answer lives in governing-doc sections/digests --
the i51 T1 class the PCB lost). Both arms run BOTH tasks (same A/B session runs its two tasks in one
ledger, task order pinned in the dispatch); quality floors adjudicated per task; efficiency bars computed
per task. **GO requires every bar met on BOTH tasks.** Anything less: CONDITIONAL, with the record stating
explicitly which class failed (a map-native-only pass licenses NOTHING by itself -- the orchestrator's
actual work is dominated by prose-governing retrieval). Alternative (not recommended): single fresh task
again -- cheaper, but i47/i48/i51 have now each measured a different single class and the claim keeps
escaping scope.

**Call 2 -- directory-listing convention.** RECOMMENDED: listing OUTPUT bytes count toward the ingest
total for whichever arm emits them, at emitted size; and BOTH dispatches carry the identical line:
"Directory listings are charged at emitted bytes; prefer targeted per-directory listings; a recursive
whole-repo listing is charged in full." Removes the i51 luck asymmetry (B's one recursive listing =
145,673 B, ~27% of its primary total; A's recursive attempt happened to error). Alternative: exclude
listings for both arms -- discards a real economy signal and rewards blind bulk navigation.

**Call 3 -- staged-not-read transfers.** RECOMMENDED: bytes TRANSFERRED into the arm's workspace count in
full, read or not (i51 primary treatment; B's 7 unread stages = 80,438 B), with the identical dispatch
disclosure: "Files you stage/fetch are charged at full size whether or not you open them -- stage
selectively." A transfer is a retrieval decision; charging it keeps bulk-staging from laundering ingest.
Alternative: charge only opened bytes (the i51 charitable line) -- simpler to defend as "context actually
ingested", but makes staging free and un-measurable.

**Call 4 -- partial/sliced reads.** RECOMMENDED: a bounded ranged read (tool slice, `Read` offset/limit,
grep -m with context) is charged at RETURNED bytes for BOTH arms; a whole-file open stays whole-file. This
replaces the literal-N4 "whole-file per open" for genuinely bounded reads (i51 charged B's ~8 KB
project_map.py slice at 103,588 B -- charging bounded reads at whole-file punishes exactly the discipline
the PCB exists to reward; post-N3/N5 a B arm should not need the tool source at all, and A gets the same
credit symmetrically). Alternative: keep whole-file-per-open -- simplest, but perpetuates the F4 distortion
in both directions.

**Call 5 -- adjudicator (C-tier) pin refresh.** RECOMMENDED: pin C1 + C2 = `claude-opus-5` (what the
environment actually served in i51; deviation recorded, symmetric) with the same scores-only spec, both
scoring orders; A/B arms stay pinned `claude-opus-4-8`. Any pin miss at run time = record + STOP before
the C round (no mid-run adaptation). Alternative: re-pin C = opus-4-8 -- matches i47 but fights the
roster's reality and invites the same recorded deviation again.

## 3. Standing rules (frozen with N8; not separate calls)

- **Checklist re-derivation:** the absolute checklist (K-keys) + fact keys are RE-DERIVED against the
  actual staging tree and frozen BEFORE dispatch, every adaptation recorded in the staging note (kills the
  i51 adapted-K6 / stale-K10 ambiguity; a key that names a dead state is rewritten at staging, never at
  adjudication).
- **Staging at HEAD, no side worktree:** N7 (close-time re-fold) keeps the shipped map in-sync, so the
  eval bundle is harvested at HEAD directly; a staging that finds the map stale at HEAD is itself a FAIL
  of N7 and blocks the gate.
- **Neutralization:** the FROZEN I47 s4 dispatch text + the i51-extended scrub table (pack filenames,
  `--q`, query-surface, agent labels) + residual-tell scan required EMPTY before any C dispatch.
- **Blinding + isolation:** unchanged (coin flip, eval-folder grant only, frozen tree untouched x3,
  quarantine before C, re-hash after C).
- **Efficiency computed orchestrator-side, never disclosed to any arm; NO bracketing** -- with Calls 2-4
  frozen there is exactly ONE accounting; publishing two readings was an i51 one-off.
- **Boot-total remains reported-not-gated; VOID unchanged (PCB-insufficiency only).**

## 4. On ratification

The orchestrator: writes `modules/44-project-map/eval/results/N8_RERUN_REFREEZE.md` (the frozen rules,
N4-style) + the D-entry + index row; refreshes handoff/CURRENT_STATE. The gate becomes STAGEABLE at any
later iteration once N5-N7 are verified landed (fresh task pool authored at staging, per Call 1; frozen
checklist re-derived per s3). Until a run PASSES on both classes, the LEGACY handoff stays the default
orchestrator bootstrap.
