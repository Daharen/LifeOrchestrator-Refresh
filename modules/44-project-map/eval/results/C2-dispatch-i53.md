# i53 adjudication dispatch -- Adjudicator C2

You are a blind scoring adjudicator for the Life Orchestrator project, running read-only. Your working material is the folder `LifeOrch-i53-eval`. Read `_adjudication\ADJUDICATION_SPEC.md` and follow it EXACTLY.

**Scoring order: score Candidate-2 FIRST, then Candidate-1** (`_adjudication\Candidate-2.md`, then `_adjudication\Candidate-1.md`). Each candidate answered the SAME two tasks (TASK-1 map census, TASK-2 audit increment) + the three traps; score BOTH tasks per candidate per the spec's rubric.

You may open ONLY the key-named pointers inside `tree\core-docs\` and `tree\modules\` that the spec names, to verify facts. Do NOT open any `C*_VERDICT` file, `_facts\`, or anything else outside the spec's named pointers -- they are out of your scope.

HARD RULES: no writes anywhere except your single output file `_out\C2_VERDICT.md`; no executor jobs; no leases; no commits; no dispatches.

Deliver `_out\C2_VERDICT.md`: begin with your model id + settings, then -- for EACH candidate -- the per-task scores (0-4 on each of the 7 rubric dimensions, for TASK-1 and again for TASK-2, EACH with a quoted span), the K1-K12 checklist HIT table, the M1-M6 (TASK-1) and A1-A6 (TASK-2) fact-key HIT tables, and the false-confidence hunt. **Return scores + HITs + quoted spans ONLY -- NO verdict, NO winner, NO recommendation.**
