# FANOUT_AGENT_002 -- CODING (CPU) lane: artifact.search DETERMINISTIC MVP (i25, plan fo-25-3b718a13)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** READY -- dispatch by telling a FRESH Cowork session: "Read the Project doc `claude/fanout/FANOUT_AGENT_002.md` and execute it" + grant the one folder `C:\Users\just_\LifeOrchestrator-Refresh`.
- **Wave / iteration:** i25 (plan id `fo-25-3b718a13`)
- **Lane:** CODING (CPU)
- **Worker id:** ARTIFACT-SEARCH-i25
- **Module/area (exclusive):** modules/36-artifact-search (NEW; skill artifact.search)
- **GPU:** false -- gpu:true ONLY on the GPU lane
- **Docs:** `[]` (workers never edit core-docs; the orchestrator mirrors + folds)

## Mission

Build the authoritative SQLite catalog + hybrid LEXICAL (FTS5) search substrate with full provenance, Markdown-aware chunking, deterministic incremental ingest/reconcile, DB integrity, and a MOCK embedding-provider seam (NEW module 36-artifact-search). CONSUMES the embedding-provider interface (mock now; real adapter at fold) and PRODUCES the retriever interface (lane 003 consumes it). Governing: research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md sec 6/7/8; D-0080/D-0081.

## Unit (the full worker prompt -- emitted by orchestrate.fanout `plan`, verbatim)

# Fan-out worker prompt -- worker ARTIFACT-SEARCH-i25 (plan fo-25-3b718a13, iteration 25)

You are one worker in a fan-out build of Life Orchestrator, coordinated by an orchestrator instance.
First read core-docs/START_HERE.md and core-docs/HANDOFF.md, then the docs they route you to.

## Your scoped unit
BUILD the Wave 1 CODING lane -- the `artifact.search` DETERMINISTIC MVP: the authoritative catalog + hybrid LEXICAL search substrate, as a NEW module `modules/36-artifact-search` (skill id `artifact.search`; ARCHITECTURE_MAP destination position 23 -- NOT a directory number). CPU-only, parallel-safe (distinct module). You are the CONSUMER half of the wave's producer/consumer split: build against a MOCK embedding provider now; the orchestrator runs the REAL embedding->search->benchmark smoke at fold (D-0077).

READ FIRST (disk is canonical; do NOT skip):
- core-docs/START_HERE.md + core-docs/CURRENT_STATE.md 'Known failures / gotchas' IN FULL (the load-bearing gotcha corpus: the WEDGE class -> launch persistent model servers DETACHED + reap before finalize + assert 0 UNMANAGED orphans; pwsh 7.4.6 traps; per-file EOL; 'trust the heartbeat, not the process list').
- core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md -- THE GOVERNING DESIGN DOC + shared contract for the Wave 1 memory substrate (D-0080/D-0081). Read the sections named in your SCOPE; on any conflict this doc + the live gates win.
- core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md section 8 (worker-spec rules) + core-docs/SKILL_CONTRACT.md + core-docs/MODULE_WORK_ORDER_TEMPLATE.md (author your module's WORK_ORDER.md + skill.json TO CONTRACT).
- core-docs/DECISION_LOG_INDEX.md -> pull D-0080 + D-0081 (direction) and D-0077 (the cross-module smoke rule that governs this wave) only as needed. Governing sections for you: 6.1 (SQLite catalog + table set), 6.2 (FTS), 6.3 (embeddings-as-addresses), 6.5 (files remain canonical), 7.1/7.2 (inventory + type-aware parsing), 8.4 (provenance), 21 Priority 1.

SHARED CONTRACTS (D-0077 -- the fold depends on BOTH; record your interpretation in modules/36-artifact-search/SCHEMA_NOTES.md):
1. EMBEDDING-PROVIDER INTERFACE (governing core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md section 6.3): op `embed`; inputs `texts` (array<string>, batch) and/or `text` (single) + optional `normalize` (bool, default true); result (lifeorch.skill.result/0.1 envelope) carries { model_id, model_version, model_sha256, engine_build, dim:int, normalized:bool, count:int, vectors: array of float arrays in EXACT INPUT ORDER (result[i] <-> input[i]), and a per-input status for skipped empties/oversize with the input index }. You MOCK it this wave (lane A / module 35 ships the real one): your mock must be DETERMINISTIC (e.g. a hashed pseudo-vector of a fixed dim) and satisfy this EXACT shape so the real adapter drops in unchanged at fold. Keep the provider behind a clean seam (store provider_id + dim on every vector row) so re-embedding on model change is possible.
2. RETRIEVER INTERFACE (governing core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md section 8): op `search`; inputs { query:string, k:int, filters?:{...} }; result: a ranked array of { source_path, content_hash (or version id), chunk_id, span (byte offsets or heading/section path), score, snippet } in DETERMINISTIC order (stable tie-break). You PRODUCE it (lane C / module 37 consumes it) -- pin it so the retrieval-eval harness can point at you at fold.

SCOPE IN (create ONLY modules/36-artifact-search/ + tests/fixtures): SQLite schema (sources / documents / document_versions / chunks with provenance: source_path, content_hash, span, parser, parser_version, created_at; + a chunk_embeddings table with provider_id + dim + vector keyed to chunks; SQLite owns ids/versions/hashes/status). File inventory + content hash; changed/new/moved/deleted detection; SURFACE parser failures (never silently drop a file). Markdown-AWARE chunking (headings/sections/code blocks) + a generic-text fallback. FTS (SQLite FTS5) over chunk text; metadata filters (source/type/path/version/status). Embedding-provider seam with the MOCK (contract 1). Every result resolves to source_path + content_hash + span (contract 2). INCREMENTAL changed-file ingest that is DETERMINISTIC (same inputs -> same chunk ids + ordering), reconciles changed/deleted, produces NO duplicate chunks; a DB integrity check. A CLI/skill contract exposing at least `ingest` (a root/path set) and `search` (the retriever interface).
NON-GOALS (do NOT build): AST / call-graph / symbol index, summaries, episodes, failure memory, the context compiler, any UI, web search, REAL embeddings (mock only).

ACCEPTANCE: index a bundled FIXTURE repo AND a bounded slice of the REAL repo (e.g. core-docs/ under a bounded file budget); exact + FTS retrieval both return provenance-complete hits; DETERMINISTIC re-ingest (id/order-stable); changed + deleted reconciliation with no dup chunks; a DB integrity check passes; provenance from every result to its source span; mock-embedding contract tests (shape + input-order + dim) that will also pass against the real adapter.

GATES (fail-closed): OFF-MACHINE FIRST (cloud -- system python has sqlite3 with FTS5, or pwsh; deterministic, CPU-only) THEN `-Live` on the executor over the real core-docs slice. Author skill.json (0.1.0) + README.md + WORK_ORDER.md to SKILL_CONTRACT. Keep any canonical output deterministic (double-run stable); if you use pwsh, mind the traps (sort-copy no-op -> cast [string[]]; empty-array unroll; array double-wrap).

LEASE + SHIP DISCIPLINE (res.lease #29): acquire in gpu -> git -> doc order, each BEFORE the work it guards; release in REVERSE. You hold docs:[] so you take NO doc lease. Take the git lease only around your dev.ship commit, release after. device_bash is a Linux VM and CANNOT run Windows pwsh -- everything runs through the executor (exec-job.sh). Ship via dev.ship (it verifies sha256 + AST + tests FAIL-CLOSED and commits ONLY your named files under the git lease). VERIFY the real HEAD via native git log / git show --stat, NOT the dev.ship 'committed' field (D-0072); if a stale 0-byte .git/index.lock blocks it, clear it via an executor task (assert no git.exe running) then re-commit. The exact res.lease + report command lines (with this plan's id) are appended to this prompt below.

VERIFY / REPORT (docs:[] -- the ORCHESTRATOR mirrors + folds ALL core-docs from your report; do NOT edit any core-doc): report DONE/PARTIAL/DEFERRED per acceptance item with the exact file+function delta and the test that proves it; the off-machine + live counts; 0 UNMANAGED llama-server/python orphans; review_queue.jsonl before==after (you are not a producer). WRITE your module's SCHEMA_NOTES.md recording EVERY schema/interface interpretation -- REQUIRED, the D-0077 cross-module fold smoke depends on it. Fallback (D-0061, negative results are first-class): if you cannot finish safely, ship the coherent TESTED prefix, keep it self-contained, and report PLAINLY what remains and why. Report via the -Action report command appended below (with this plan's id). (SCHEMA_NOTES.md MUST record the SQLite schema + BOTH interfaces as implemented.)

SCOPE OUT / do NOT: touch model modules / models.json (lane A only -- your embeddings are a MOCK); build a real embedding server; build the benchmark/metrics (lane C); touch any other module or ANY core-doc (docs:[]).

Notes: Coding lane, CPU-only, parallel-safe (distinct module). NEW module modules/36-artifact-search -> OMIT skill_id/skill_dir (worker authors skill.json 0.1.0). Embeddings are a MOCK (lane A ships the real adapter; do NOT touch models.json). CONSUMES the embedding-provider interface (mock) + PRODUCES the retriever interface (both D-0077 shared contracts). Orchestrator runs the cross-module smoke at fold. Brief: core-docs/fanout/FANOUT_AGENT_002.md.

## Resource leases (collision safety -- res.lease #29)
Acquire these BEFORE the work they guard, in THIS order (gpu -> git -> doc); each blocks up to the wait:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "git" -Holder "ARTIFACT-SEARCH-i25" -TtlSeconds 1800 -WaitSeconds 900
```
Acquire returns a lease_id; keep each one. Renew before its TTL if the work runs long.
Release in REVERSE order when the guarded work is done, or immediately if you block/abort:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "git" -Holder "ARTIFACT-SEARCH-i25"
```
(Release-by-holder is shown; releasing with the exact -LeaseId is stronger.)

## Report back (cadence: on_all)
Report at least once when you finish or block. Run:
```
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId "fo-25-3b718a13" -WorkerId "ARTIFACT-SEARCH-i25" -State done -Summary "<one line: what you did>" -PlansDir "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"
```
Use -State progress for interim updates, -State blocked with -Needs '<what you need>' if stuck, -State failed if you cannot finish.

## Ship + stop
Ship your unit through the job-runner (dev.ship). Do ONE scoped unit. Do NOT touch another worker's
module, and do NOT edit the shared core-docs the orchestrator owns -- report and let the orchestrator
mirror them (it serialises doc + git writes via res.lease). Then release your leases and report done.

## Rails (standing rules -- keep to them)

- Read core-docs/START_HERE.md + core-docs/CURRENT_STATE.md 'Known failures / gotchas' first; obey SKILL_CONTRACT.md; author WORK_ORDER.md to MODULE_WORK_ORDER_TEMPLATE.md.
- Acquire res.lease(s) in gpu -> git -> doc order; release on exit. docs:[] -> no doc lease. Take git only around the dev.ship commit.
- Do ONE unit; build ONLY your exclusive module; never touch another module or ANY core-doc (the orchestrator mirrors + folds).
- Gate OFF-MACHINE first (cloud pwsh 7.4.6 / system python + mock-seam harness), then ship via exec-job.sh devship (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers). VERIFY the real HEAD via native git (D-0072).
- Any persistent llama-server launches DETACHED; reap before finalize; assert 0 UNMANAGED orphans. 'It loaded' != 'it fits' -- the measured-PEAK required_vram is the only real admission control.
- Report via -Action report -PlanId fo-25-3b718a13 -WorkerId <id> -State done + a plain measured summary. Negative results are first-class (the D-0061 ethos): ship the tested prefix and say plainly what remains.

## Verification

Index a fixture repo + a bounded real core-docs slice; exact + FTS retrieval with complete provenance; deterministic re-ingest (id/order stable); changed+deleted reconciliation, no dup chunks; DB integrity check; result->source span provenance; mock-embedding contract tests that will also pass against the real adapter. Gates: off-machine (sqlite3/FTS5, deterministic) FIRST, then `-Live`. ORCHESTRATOR runs the D-0077 cross-module smoke at fold.

## Report-back record (ORCHESTRATOR fills from plans/fo-25-3b718a13/reports/ before archiving)

_Empty until the worker reports via -Action report (workers run docs:[], never edit this doc). The orchestrator records commit(s), test counts, measurements, and residuals/follow-ons here at fold, then archives this brief to archive/fanout-agents/i25-<id>.md and resets the slot to EMPTY._
