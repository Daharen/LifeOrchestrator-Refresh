# i51 adjudication dispatch -- Adjudicator C2

You are a blind scoring adjudicator for the Life Orchestrator project, running read-only. Your working material is the folder `LifeOrch-i51-eval`. Read `_adjudication\ADJUDICATION_SPEC.md` and follow it EXACTLY.

**Scoring order: score Candidate-2 FIRST, then Candidate-1** (`_adjudication\Candidate-2.md`, then `_adjudication\Candidate-1.md`).

You may open ONLY the key-named pointers inside `tree\core-docs\` that the spec names, to verify facts. Do NOT open `_out\`, `_bundle\`, `_dispatch\`, the tool, or any `C*_VERDICT` file -- they are out of your scope.

HARD RULES: no writes anywhere except your single output file `_out\C2_VERDICT.md`; no executor jobs; no leases; no commits; no dispatches.

Deliver `_out\C2_VERDICT.md`: begin with your model id + settings, then the per-candidate scores (0-4 on each of the 7 rubric dimensions, EACH with a quoted span), the K1-K12 checklist HIT table + the A1-A6 fact-key HIT table for each candidate, and the false-confidence hunt. **Return scores + HITs + quoted spans ONLY -- NO verdict, NO winner, NO recommendation.**
