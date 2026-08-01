# FANOUT_AGENT_001 -- Wave 2 CONSUMER lane: artifact.search 0.1 -> 0.2 (READY)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY (dispatch on Nicholas's go)
- **Wave / iteration:** i27 (plan id `fo-27-bab47060`)
- **Lane:** CODING (CPU) -- the GPU lane is SKIPPED this wave (no model work)
- **Worker id / label:** ARTIFACT-SEARCH-02-i27
- **Module/area (exclusive):** `modules/36-artifact-search` (EXISTING module; 0.1.0 -> 0.2.0)
- **GPU:** false
- **Docs:** `[]` (the orchestrator mirrors core-docs)

## Mission

Adopt the FROZEN **MEMORY_CONTRACT 0.2** (D-0083) in the shipped catalog and add the generic `ingest_records` SINK so the Wave-2 PRODUCERS (repo.intel #38, episode.memory #39) can land TYPED records -- not chunks. This is the CONSUMER half of the wave's producer/consumer split; the orchestrator runs the real repo.intel/episode -> `ingest_records` -> retrieval smoke at fold (D-0077). Governing: `core-docs/MEMORY_CONTRACT.md` (s1 envelope + s2/s3/s4/s5 gates).

## Unit (full worker prompt)

Your COMPLETE mission is the emitted worker prompt -- read it IN FULL and execute it:
`modules/30-orchestrate-fanout/runtime/artifacts/24c6dcd3-15d7-49d7-a102-b0038a34a5ae/workers/worker-ARTIFACT-SEARCH-02-i27.prompt.md` (also delivered to Nicholas as a file for direct paste-dispatch).

SCOPE IN (touch ONLY `modules/36-artifact-search/`): (1) a `records` VIEW exposing chunks as record_kind=`source_chunk` per the s1 envelope + two-level chunk identity; (2) a generic `ingest_records` op + `records`/`record_edges` tables + FTS, deterministic + idempotent, malformed-record rejection surfaced; (3) schema_version + forward MIGRATIONS of a shipped-0.1 DB IN PLACE; (4) parser/chunker/extractor FINGERPRINTS on every derived record; (5) retriever-0.2 hit shape (span object {start,end} + span_label; per-channel lexical/vector/fused ranks+scores; record fields; retire the opaque score); (6) the s5 STALENESS enum (not a boolean); (7) float32 LE BLOB vectors keyed on embedding_space_id; (8) catalog hardening (transactional current-version swap, tombstones, physical/logical identity, crash-safety fault-injection) as budget allows.
NON-GOALS: a vector index/ANN/vector *search*; REAL embeddings (#35 owns; mock only); #38/#39's work; models.json; UI; the context compiler.
SHARED CONTRACT (D-0077): the MEMORY_CONTRACT s1 record envelope -- you DEFINE `ingest_records` precisely and record every interpretation in `modules/36-artifact-search/SCHEMA_NOTES.md`.

## Verification

Migrate a 0.1 DB to 0.2 (idempotent, no data loss); `ingest_records` stores >=3 record_kinds deterministically + idempotently, retrievable by kind with resolving provenance; the `source_chunk` view reproduces chunk provenance; retriever-0.2 hits carry span{start,end}+span_label + per-channel + record fields; float32 BLOB round-trips; staleness enum exercised; integrity + crash-safety pass; shipped ops regression-green; catalog_digest deterministic + extended to records. Bump skill.json 0.2.0; report off-machine + live counts.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' IN FULL first; obey `SKILL_CONTRACT.md` + **`MEMORY_CONTRACT.md`** (the frozen Wave-2 shared contract) + `MODULE_WORK_ORDER_TEMPLATE.md` (author skill.json + README + WORK_ORDER + SCHEMA_NOTES to CONTRACT).
- res.lease #29: **git only** (docs:[] -> no doc lease; CPU lane -> no gpu lease). Take git ONLY around your `dev.ship` commit, release after. Ship via `exec-job.sh devship` (sha256+AST+tests, FAIL-CLOSED, named files only, trailers). Files reach the box via SendUserFile + device_commit_files. Verify the real HEAD via native `git log`/`git show --stat`, NOT dev.ship's `committed` (D-0072).
- Do ONE unit; never touch another module/area or ANY core-doc (`docs:[]`). CPU-only, no model, no network; assert 0 UNMANAGED llama-server/python orphans; `review_queue.jsonl` before==after.
- Gate OFF-MACHINE first (cloud pwsh/python, deterministic) THEN `-Live` on the executor; canonical outputs double-run byte-identical. Report via `-Action report -PlanId fo-27-bab47060 -WorkerId <id> -State done` + a plain summary (negative results are first-class, D-0061).

## Report-back record (ORCHESTRATOR fills from `plans/fo-27-bab47060/reports/` before archiving)

(pending -- commit(s), test counts, measurements, residuals/follow-ons discovered.)
