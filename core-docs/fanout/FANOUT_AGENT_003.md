# FANOUT_AGENT_003 -- Wave 2 PRODUCER lane: episode.record (NEW module 39) (READY)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY (dispatch on Nicholas's go)
- **Wave / iteration:** i27 (plan id `fo-27-bab47060`)
- **Lane:** CPU
- **Worker id / label:** EPISODE-MEMORY-i27
- **Module/area (exclusive):** `modules/39-episode-memory` (NEW module; skill `episode.record`)
- **GPU:** false
- **Docs:** `[]`

## Mission

A NEW module that DEFINES the EPISODE and FAILURE record schemas (**MEMORY_CONTRACT s1** envelope; directive 5.3/5.4/10) + a DETERMINISTIC RECORDER (run trace -> a complete episode record, even on failure) + a failure-signature retrieval SEAM. PRODUCER half of the split; the orchestrator feeds a real episode + failure record into #36 0.2 `ingest_records` at fold (D-0077). Governing: `core-docs/MEMORY_CONTRACT.md` s1/s5/s7 + the directive s5.3/s5.4/s10.

## Unit (full worker prompt)

Your COMPLETE mission is the emitted worker prompt -- read it IN FULL and execute it:
`modules/30-orchestrate-fanout/runtime/artifacts/24c6dcd3-15d7-49d7-a102-b0038a34a5ae/workers/worker-EPISODE-MEMORY-i27.prompt.md` (also delivered to Nicholas as a file for direct paste-dispatch).

SCOPE IN (create ONLY `modules/39-episode-memory/` + tests/fixtures): EPISODE schema (10.1 fields) as an `episode` record + `episode_stage` children (parent/child edges); FAILURE schema (5.4/10.2 fields incl. a deterministic task-conditioned `failure_signature`) as `failure` records; a DETERMINISTIC RECORDER (input = a run TRACE + its schema; output = a complete episode even when the run FAILED); a failure-signature retrieval SEAM (a task-context query shape + a deterministic signature-match baseline over a fixture failure corpus); provenance + sensitivity_class + an s1 VALIDATOR; canonical JSON.
NON-GOALS: auto-capture wired into agent.local #21; failure MINING / procedure discovery; embeddings; the catalog DB (#36 owns storage); the context compiler; UI.
SHARED CONTRACT (D-0077): MEMORY_CONTRACT s1 envelope (record_kind `episode`/`failure`/`episode_stage`); record every interpretation in `modules/39-episode-memory/SCHEMA_NOTES.md`.

## Verification

Schemas frozen to s1 in SCHEMA_NOTES; the recorder turns a fixture SUCCESS trace AND a fixture FAILURE trace into COMPLETE deterministic episodes (+ stages); failure records validate; the failure-signature seam returns the RIGHT failure for a task-context query AND excludes unrelated ones (a test that FAILS if an unrelated failure surfaces); DETERMINISTIC re-run; records drop into #36 0.2 `ingest_records`. skill.json 0.1.0; report off-machine + live counts.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' IN FULL first; obey `SKILL_CONTRACT.md` + **`MEMORY_CONTRACT.md`** (the frozen Wave-2 shared contract) + `MODULE_WORK_ORDER_TEMPLATE.md` (author skill.json + README + WORK_ORDER + SCHEMA_NOTES to CONTRACT).
- res.lease #29: **git only** (docs:[] -> no doc lease; CPU lane -> no gpu lease). Take git ONLY around your `dev.ship` commit, release after. Ship via `exec-job.sh devship` (sha256+AST+tests, FAIL-CLOSED, named files only, trailers). Files reach the box via SendUserFile + device_commit_files. Verify the real HEAD via native `git log`/`git show --stat`, NOT dev.ship's `committed` (D-0072).
- Do ONE unit; never touch another module/area or ANY core-doc (`docs:[]`). CPU-only, no model, no network; assert 0 UNMANAGED llama-server/python orphans; `review_queue.jsonl` before==after.
- Gate OFF-MACHINE first (cloud pwsh/python, deterministic) THEN `-Live` on the executor; canonical outputs double-run byte-identical. Report via `-Action report -PlanId fo-27-bab47060 -WorkerId <id> -State done` + a plain summary (negative results are first-class, D-0061).

## Report-back record (ORCHESTRATOR fills from `plans/fo-27-bab47060/reports/` before archiving)

(pending -- commit(s), test counts, measurements, residuals/follow-ons discovered.)
