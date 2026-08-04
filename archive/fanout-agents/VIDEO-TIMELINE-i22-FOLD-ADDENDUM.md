# VIDEO-TIMELINE-i22 -- ORCHESTRATOR FOLD ADDENDUM (0.1.1, D-0077)

**Companion to `claude/fanout/VIDEO-TIMELINE-i22-SHIP-STATE.md`** (the worker's 0.1.0 ship state, unchanged).

After both i22 workers reported done, the orchestrator ran the CROSS-MODULE SMOKE neither isolated worker
could run (plan `fo-22-d2c492e7`): real `track.objects 0.2.0 -Mode stable` canonical output fed into
`video.timeline` as the `tracks` input, on the box, via the executor.

## What the smoke found (both predicted by the workers' own SCHEMA_NOTES divergence)

1. **detection_score scale (silent corruption):** #33 declares `score_unit: "millionths"` file-level and
   stores `observation.detection_score` as the ALREADY-quantized integer (900000). #34 0.1.0 assumed a 0..1
   float and re-quantized x1e6 -> an "ok" timeline whose evidence read `mean_detection_score_q:
   900000000000`.
2. **`scene_index: -1` (fail-closed refusal):** #33's documented pre-first-scene interpretation
   (`firstIndex-1`, can be -1) was refused by #34's `>= 0` validation.

## The fix (CONSUMER-side; the emitter's canonical bytes + shipped hashes untouched)

**`video.timeline` 0.1.0 -> 0.1.1, commit `bad9e27`** (9 files; dev.ship green: sha 9/9, AST 3/3, tests
re-run `-Live`): honor the emitter's declared `score_unit` (`millionths` -> integer 0..1000000 used verbatim
as q; absent/`unit_float` -> 0..1 float, and a score > 1 is now a FAIL-CLOSED violation instead of silent
scaling; other units refused); accept `scene_index >= -1` on samples + tracks (-1 = "before the first listed
scene", an opaque partition label, never an `index.by_scene` bucket). `SCHEMA_NOTES.md` notes 34-35; main
suite updated only for `generator.version 0.1.1`.

## Verification

NEW `tests/Invoke-VideoTimelineReconTests.ps1` **20/20** (cloud AND `-Live`; fixtures `tracks-millionths` +
`tracks-prescene` embed REAL 0.2.0 canonical outputs verbatim; 2 refusal fixtures lock the fail-closed
paths); main suite ALL PASSED both environments; recon canonical hashes EQUAL cross-env
(`recon-millionths eec57537...`, `recon-prescene 714e168a...`); smoke re-run green end-to-end (case A
evidence sane at 900000; case B ok with `scene_index -1` carried + 2 scene_cut events).

## The process lesson (now a standing rule, D-0077)

Parallel isolated workers building a schema PRODUCER and its CONSUMER against a shared design digest MUST
get an orchestrator cross-module smoke (real producer bytes into the consumer) at fold before close --
both i22 workers' gates were fully green and the divergences were invisible to both.
