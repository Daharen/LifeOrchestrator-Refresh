# FANOUT_AGENT_003 -- Wave 3 SKILL-CARD lane

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY -- dispatch into a fresh Cowork session (one folder grant: `C:\Users\just_\LifeOrchestrator-Refresh`).
- **Wave / iteration:** i29 (plan id `fo-29-87dbfa0b`)
- **Lane:** CPU -- the GPU lane is SKIPPED this wave
- **Worker id / label:** SKILL-CARD-i29
- **Module/area (exclusive):** NEW `modules/41-skill-card` (skill id `skill.card`)
- **GPU:** false
- **Docs:** `[]`

## Mission

Build the compact skill-card generator + skill index (directive Priority 6 / section 9 'Skill card format') --
the skill-activation substrate: a DETERMINISTIC generator that turns each module's skill.json (+ README /
WORK_ORDER / SKILL_CONTRACT) into a compact, model-facing SKILL CARD; a searchable skill INDEX emitting `skill`
record-envelope artifacts to MEMORY_CONTRACT s1 (for #36 0.2 ingest); Stage-1 deterministic eligibility
filtering; and a Stage-2 semantic-retrieval SEAM (lexical baseline). The half that lets the coordinator decide
WHICH skill applies without loading every command into the 9B. PRODUCER of `skill` records (boundary vs
repo.intel #38 recorded). Governing: `core-docs/MEMORY_CONTRACT.md` (s1 `skill` envelope, s7 privacy) + the
directive section 9 + Priority 6.

## Unit (authoritative work order)

**Your COMPLETE, self-contained work order is the emitted prompt on disk -- READ AND EXECUTE IT IN FULL:**
`modules/30-orchestrate-fanout/runtime/artifacts/76a56943-d4f3-470b-8242-7b4e44be22bc/workers/worker-SKILL-CARD-i29.prompt.md`
(it carries the full scope IN/OUT, acceptance, gates, and the exact res.lease + report command lines for this plan).

Scope digest (orientation only -- the emitted prompt governs):

- Scope IN (`modules/41-skill-card` ONLY): (1) the skill-card format + generator (directive s9 fields: purpose,
  ops, typed inputs, one example, preconditions, side effects, artifacts, latency/resource class, completion
  checks, failure/refusal conditions, version + health; NEVER crash on a partial manifest); (2) a skill INDEX
  emitting `skill` s1 record-envelope artifacts (deterministic ids; idempotent) -- record the #38 boundary
  (richer ACTIVATION card vs #38's structural records); (3) Stage-1 deterministic eligibility filtering;
  (4) a Stage-2 semantic-retrieval SEAM (deterministic lexical baseline over the card index); (5) a validator +
  provenance + sensitivity_class.
- Non-goals: the task classifier (Stage 3), 9B preflight (Stage 5), plan validation (Stage 6) -- Priority 7;
  the PROCEDURE registry (a named follow-on); real embeddings / semantic retrieval (retrieval wave -- lexical
  only); the catalog DB (#36); repo.intel's parsing (#38); the context compiler (#40); UI. Do NOT touch model
  modules / models.json.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' first; obey `SKILL_CONTRACT.md`.
- `docs:[]` -- you NEVER edit core-docs; report and the orchestrator mirrors. Do ONE unit; touch ONLY `modules/41-skill-card`.
- Gate OFF-MACHINE first (cloud python/pwsh, deterministic), THEN `-Live` on the executor over the real
  modules/ corpus; ship via `exec-job.sh devship` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers).
- Acquire the `git` lease ONLY around your dev.ship commit (gpu -> git -> doc order; release in reverse).
  VERIFY the real HEAD via native git (D-0072).
- Report via `-Action report -PlanId fo-29-87dbfa0b -WorkerId SKILL-CARD-i29 -State done` (negative results are
  first-class, D-0061).

## Verification

Compact cards for a fixture skill set AND the real modules/ corpus with all section-9 fields (missing fields
surfaced, never crash); `skill` records PASS the s1 validator + drop into #36 0.2 `ingest_records` (the #38
boundary recorded); Stage-1 eligibility deterministically excludes the right skills (forbidden side-effect /
unavailable dependency / GPU-unavailable); the Stage-2 lexical baseline returns the right candidate skills and
EXCLUDES irrelevant ones (a test that fails if an irrelevant skill surfaces); deterministic re-run (identical
cards/records/ids/order); `-Live` over the real corpus. Report off-machine + `-Live` counts; 0 UNMANAGED
orphans; skill.json 0.1.0 + README + WORK_ORDER + SCHEMA_NOTES to contract.

## Report-back record (ORCHESTRATOR fills at fold from `plans/fo-29-87dbfa0b/reports/`)

(commit, test counts, measurements, residuals -- filled at handoff.)
