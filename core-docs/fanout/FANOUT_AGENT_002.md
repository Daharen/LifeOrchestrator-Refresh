# FANOUT_AGENT_002 -- Wave 3 RETRIEVAL-QUALITY lane

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** READY -- dispatch into a fresh Cowork session (one folder grant: `C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i29 (plan id `fo-29-87dbfa0b`)
- **Lane:** CODING (CPU) -- the GPU lane is SKIPPED this wave
- **Worker id / label:** RETRIEVAL-QUALITY-i29
- **Module/area (exclusive):** EXISTING `modules/37-retrieval-eval` (skill `retrieval.eval`) 0.1.0 -> 0.2.0
- **GPU:** false
- **Docs:** `[]`

## Mission

Adopt MEMORY_CONTRACT eval-0.2 (s6) on retrieval.eval #37 AND add a DETERMINISTIC RERANKER (directive 8.3 /
skill-activation Stage 4) that the 0.2 harness MEASURES (uplift/regression vs the raw retriever order). Makes
retrieval + packet quality MEASURABLE so the Wave-3 context/skill layers can be accepted, and provides the
reranker seam the context compiler #40 (this wave) and a later retrieval wave consume. Existing module revision;
CONSUMER of the retriever-0.2 hit shape; no model. Governing: `core-docs/MEMORY_CONTRACT.md` (s6 eval gates,
s3 hit, s5 staleness) + the directive 8.3/11.1 + Priority 2.

## Unit (authoritative work order)

**Your COMPLETE, self-contained work order is the emitted prompt on disk -- READ AND EXECUTE IT IN FULL:**
`modules/30-orchestrate-fanout/runtime/artifacts/76a56943-d4f3-470b-8242-7b4e44be22bc/workers/worker-RETRIEVAL-QUALITY-i29.prompt.md`
(it carries the full scope IN/OUT, acceptance, gates, and the exact res.lease + report command lines for this plan).

Scope digest (orientation only -- the emitted prompt governs):

- Scope IN (`modules/37-retrieval-eval` ONLY): (1) the eval-0.2 label schema (must_include_all/any groups,
  required version/span, acceptable-equivalent spans, explicitly-stale, forbidden_sources, privacy exclusions,
  distractors, no_answer_expected, corpus snapshot -- a file-level hit is NOT credit); (2) temporal intent
  (current_only|historical_as_of|version_specific|any_valid_version); (3) added metrics (precision@K, nDCG@K,
  evidence-group coverage, forbidden/stale-hit rate, dup burden, source diversity, provenance VALIDITY,
  snippet-span correctness, no-answer FP, hybrid uplift/regression); (4) negatives/abstention cases; (5) hybrid
  attribution (lexical/vector/hybrid -- the vector channel runs EMPTY today, reported cleanly); (6) provenance
  VALIDATION (not presence); (7) a DETERMINISTIC reranker (retriever-0.2 hit array in -> reordered out) MEASURED
  vs the raw order; (8) machine- + human-readable reports.
- Non-goals: real embeddings / a vector index / real vector search (retrieval wave -- vector channel scaffolded
  EMPTY); a MODEL-based reranker; the context compiler (#40); the retriever/catalog (#36); skill cards (#41); a
  production router (Priority 7). Do NOT touch model modules / models.json.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' first; obey `SKILL_CONTRACT.md`.
- `docs:[]` -- you NEVER edit core-docs; report and the orchestrator mirrors. Do ONE unit; touch ONLY `modules/37-retrieval-eval`.
- Gate OFF-MACHINE first (cloud python/pwsh, deterministic), THEN `-Live` on the executor over a real slice
  (real #36 `search`); ship via `exec-job.sh devship` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers).
- Bump skill.json 0.1.0 -> 0.2.0 (contract_version 0.2). Acquire the `git` lease ONLY around your dev.ship
  commit; VERIFY the real HEAD via native git (D-0072).
- Report via `-Action report -PlanId fo-29-87dbfa0b -WorkerId RETRIEVAL-QUALITY-i29 -State done` (negative
  results are first-class, D-0061).

## Verification

Eval 0.2 runs deterministically on a fixture corpus with the richer labels + temporal intent + negatives; each
new metric has a KNOWN fixture value; a FAILING test when a required source is absent, when a forbidden source
is returned, and when a returned span does not reproduce its cited text; hybrid attribution runs with the vector
channel EMPTY; the deterministic reranker measurably rescues a required source or demotes a stale/forbidden hit
(A/B delta reported); the shipped 0.1 benchmark stays GREEN (regression); reports byte-identical on re-run;
`-Live` over a real core-docs slice. Report off-machine + `-Live` counts; 0 UNMANAGED orphans; README +
WORK_ORDER + SCHEMA_NOTES to contract.

## Report-back record (ORCHESTRATOR fills at fold from `plans/fo-29-87dbfa0b/reports/`)

(commit, test counts, measurements, residuals -- filled at handoff.)
