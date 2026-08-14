# N8 -- MIGRATION-GATE RE-RUN PROTOCOL RE-FREEZE (ratified AS AMENDED, D-0144, 2026-08-14)

Freezes the RUN PROTOCOL for the next legacy-vs-PCB gate. The D-0140/N4 **bars are byte-unchanged**
(boot absolute / total 0.7 x A / PCB-insufficiency void); the I47 s1-s6 mechanics + s7 quality floors
carry forward. Ratified by Nicholas with ONE call replaced and TWO amendments (digest with reasoning:
`core-docs/research/2026-08-14-i52-n8-rerun-refreeze-proposal.md`). Grounding: `I51_RESULTS.md`
F1/F4 + s6 anomalies 2-4 + s7 N8.

## Frozen run-protocol rules

1. **Task pool (two-class).** A fresh pre-registered pool of EXACTLY TWO tasks, frozen at staging:
   T-map (map-native) and T-prose (prose-governing). Both arms run BOTH tasks in one ledger, task order
   pinned in the dispatch; quality floors adjudicated per task; efficiency bars computed per task.
   **GO requires every bar met on BOTH tasks**; anything less is CONDITIONAL, the record stating which
   class failed (a map-native-only pass licenses nothing by itself). **Scope guard (Nicholas):** T-map
   and T-prose are MINIMUM LOAD-BEARING CLASSES for THIS migration decision -- NOT a claim that
   orchestrator work has exactly two classes, and NOT a canonical task taxonomy for any future
   benchmark. Do not import this split as architectural terminology.
2. **Directory listings.** Listing OUTPUT bytes are charged to the emitting arm at emitted size. Both
   dispatches carry the identical line: "Directory listings are charged at emitted bytes; prefer
   targeted per-directory listings; a recursive whole-repo listing is charged in full."
3. **Staged-not-read transfers.** Bytes TRANSFERRED into the arm's workspace are charged in full, read
   or not, with the identical dispatch disclosure: "Files you stage/fetch are charged at full size
   whether or not you open them -- stage selectively."
4. **Partial/sliced reads.** A bounded ranged read (tool slice, offset/limit read, grep with bounded
   context) is charged at RETURNED bytes for BOTH arms; a whole-file open stays whole-file.
5. **Adjudicator pin (REPLACED at ratification -- supersedes the staged Call 5).** C1 + C2 =
   **Opus 4.8 Extra**, the project's default frontier tier. A runtime model mismatch is RECORDED and
   **STOPs adjudication before the C round begins** -- no silent substitution, no mid-run adaptation.
   Escalation to **Fable 5** is permitted ONLY if explicitly justified AND frozen at staging BEFORE
   either arm runs. **Opus 5 is NOT the default fallback/escalation tier** (roster judgment, Nicholas
   i52: marginal gain over Opus 4.8 Extra at ~2x token price -- effectively never used here). A/B arms
   stay pinned `claude-opus-4-8`; an A/B pin miss = record + STOP before dispatch.

## AMENDMENT (Nicholas, i52): dual-counter accounting -- retrieval vs model-visible bytes

The ledger records **two counters per arm, per task, NEVER collapsed into one "ingest" number**:

- **Retrieval/materialization bytes** -- what the system CAUSED to be transferred, staged, listed,
  retrieved, or materialized (rules 2-4 above price this counter).
- **Model-visible bytes** -- what actually ENTERED the agent's readable context.

**The N4 0.7 x A pass/fail bar continues to run on charged retrieval bytes** (the pre-ratified metric,
unchanged) -- but both counters are recorded separately in the ledger and reported side-by-side in the
results. Reason (architectural, forward-looking): caches, prefetch, local indexes, background
decomposition, embeddings, and materialized records mean a cheap deterministic layer may soon retrieve
500 KB internally to hand the frontier model 8 KB -- excellent architecture that a single undifferentiated
byte count would punish. Do not confuse how much the computer touched with how much expensive
intelligence had to consume; the partial-read distortion this gate just fixed (F4) was that same
confusion in miniature.

## Standing rules (frozen with N8)

- The absolute checklist (K-keys) + fact keys are RE-DERIVED against the actual staging tree and frozen
  BEFORE dispatch; every adaptation recorded at staging, never at adjudication.
- Staging at HEAD, no side worktree: N7 keeps the shipped map in-sync; a stale map at staging is an N7
  FAIL and blocks the gate.
- Neutralization: the FROZEN I47 s4 dispatch text + the i51-extended scrub table; residual-tell scan
  EMPTY before any C dispatch.
- Blinding + isolation unchanged (coin flip, eval-folder-only grants, frozen tree untouched x3,
  quarantine before C, re-hash after C).
- Efficiency computed orchestrator-side, never disclosed to any arm; NO bracketing -- rules 2-4 leave
  exactly one accounting.
- Boot-total reported-not-gated; VOID unchanged (PCB-insufficiency only).

## Status

The gate is STAGEABLE at any iteration once N5-N7 are verified landed (fresh two-task pool authored +
frozen at staging per rule 1). Until a run PASSES on both classes, the LEGACY handoff remains the
default orchestrator bootstrap.
