# FANOUT_AGENT_001 -- Wave 3 CONTEXT-COMPILER lane

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY -- dispatch into a fresh Cowork session (one folder grant: `C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i29 (plan id `fo-29-87dbfa0b`)
- **Lane:** CODING (CPU) -- the GPU lane is SKIPPED this wave (deterministic compiler, no model)
- **Worker id / label:** CONTEXT-COMPILER-i29
- **Module/area (exclusive):** NEW `modules/40-context-compiler` (skill id `context.compile`)
- **GPU:** false
- **Docs:** `[]`

## Mission

Build the context packet compiler (directive Priority 4 / section 8) -- the Collective Agent's architectural
centerpiece: a DETERMINISTIC module that turns a task descriptor into a versioned, token-budgeted
`lifeorch.context_packet/0.1` (normalize -> retrieve via artifact.search #36 retriever 0.2 -> deterministic
rerank/diversify + budget -> a packet with full source provenance, an adaptive-expansion seam, an
omitted-context record, and packet-evaluation hooks). CONSUMER of the FROZEN retriever-0.2 hit shape; PRODUCER
of context packets the orchestrator feeds into retrieval.eval #37 + a fresh 9B at fold (D-0077). Governing:
`core-docs/MEMORY_CONTRACT.md` (s3 retriever hit, s5 staleness, s1 provenance) + the directive section 8 +
Priority 4.

## Unit (authoritative work order)

**Your COMPLETE, self-contained work order is the emitted prompt on disk -- READ AND EXECUTE IT IN FULL:**
`modules/30-orchestrate-fanout/runtime/artifacts/76a56943-d4f3-470b-8242-7b4e44be22bc/workers/worker-CONTEXT-COMPILER-i29.prompt.md`
(it carries the full scope IN/OUT, acceptance, gates, and the exact res.lease + report command lines for this plan).

Scope digest (orientation only -- the emitted prompt governs):

- Scope IN (`modules/40-context-compiler` ONLY): (1) task normalization -> a deterministic query set;
  (2) candidate retrieval via a DEFINED #36 retriever-0.2 seam (mock off-machine, real #36 on `-Live`);
  (3) deterministic rerank + diversity (dedup by content_hash + a source-diversity cap; DEMOTE stale per s5);
  (4) a deterministic token budgeter with EXACT accounting + explicit truncation detection; (5) the
  `lifeorch.context_packet/0.1` schema (source excerpts WITH provenance; skill/procedure/failure/episode REFS;
  omitted-context summary; deterministic packet_id; retrieval provenance); (6) an adaptive `expand` seam;
  (7) packet-evaluation hooks the #37 harness consumes.
- Non-goals: real embeddings / vector search; the retriever or catalog DB (#36); skill-card CONTENT (#41);
  the MEASURED reranker + eval metrics (#37); running the 9B / any model; UI. Do NOT touch model modules /
  models.json. The compiler is DETERMINISTIC, CPU-only; the vector channel may be null -- do not depend on it.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' first; obey `SKILL_CONTRACT.md`.
- `docs:[]` -- you NEVER edit core-docs; report and the orchestrator mirrors. Do ONE unit; touch ONLY `modules/40-context-compiler`.
- Gate OFF-MACHINE first (cloud pwsh + a mock-retriever seam), THEN `-Live` on the executor; ship via
  `exec-job.sh devship` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers). Files reach the box via
  `SendUserFile` + `device_commit_files`.
- Acquire the `git` lease ONLY around your dev.ship commit (gpu -> git -> doc order; release in reverse).
  VERIFY the real HEAD via native git (D-0072), not the dev.ship `committed` field.
- Report via `-Action report -PlanId fo-29-87dbfa0b -WorkerId CONTEXT-COMPILER-i29 -State done` (negative
  results are first-class, D-0061).

## Verification

A deterministic packet within a configured token budget with exact accounting; every excerpt's cited span
reproduces its source text; byte-identical re-run (deterministic packet_id); a diversity test where 10 near-dup
chunks do NOT crowd out a distinct required source; `-Live` over a real core-docs slice for >=3 LO benchmark
questions (required spans present + provenance-valid); the `expand` op returns bounded raw source with valid
provenance. Report off-machine + `-Live` counts; 0 UNMANAGED orphans; skill.json 0.1.0 + README + WORK_ORDER +
SCHEMA_NOTES authored to contract.

## Report-back record (ORCHESTRATOR fills at fold from `plans/fo-29-87dbfa0b/reports/`)

(commit, test counts, measurements, residuals -- filled at handoff.)
