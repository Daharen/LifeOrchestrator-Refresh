# FANOUT_AGENT_003 -- CPU lane: RETRIEVAL-EVALUATION HARNESS (i25, plan fo-25-3b718a13)

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** READY -- dispatch by telling a FRESH Cowork session: "Read the Project doc `claude/fanout/FANOUT_AGENT_003.md` and execute it" + grant the one folder `C:\Users\just_\LifeOrchestrator-Refresh`.
- **Wave / iteration:** i25 (plan id `fo-25-3b718a13`)
- **Lane:** CPU
- **Worker id:** RETRIEVAL-EVAL-i25
- **Module/area (exclusive):** modules/37-retrieval-eval (NEW; skill retrieval.eval)
- **GPU:** false -- gpu:true ONLY on the GPU lane
- **Docs:** `[]` (workers never edit core-docs; the orchestrator mirrors + folds)

## Mission

Make retrieval quality MEASURABLE before any vector integration (NEW module 37-retrieval-eval): a benchmark schema (query + required-source labels), a fixture corpus + initial LO questions, a deterministic lexical baseline retriever, recall@K/MRR/stale-source/provenance metrics, and machine + human reports. Runs fully isolated (own baseline); CONSUMES the retriever interface so the orchestrator can point it at real artifact.search at fold. Governing: research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md sec 11 + 8.6; D-0080/D-0081.

## Unit (the full worker prompt -- emitted by orchestrate.fanout `plan`, verbatim)

# Fan-out worker prompt -- worker RETRIEVAL-EVAL-i25 (plan fo-25-3b718a13, iteration 25)

You are one worker in a fan-out build of Life Orchestrator, coordinated by an orchestrator instance.
First read core-docs/START_HERE.md and core-docs/HANDOFF.md, then the docs they route you to.

## Your scoped unit
BUILD the Wave 1 CPU lane -- the RETRIEVAL-EVALUATION HARNESS: make retrieval quality MEASURABLE before any vector integration, as a NEW module `modules/37-retrieval-eval` (skill id `retrieval.eval`). CPU-only, parallel-safe (distinct module). You run FULLY ISOLATED this wave: you do NOT depend on artifact.search (lane B) being built -- you ship your OWN lexical baseline + fixture corpus, and the orchestrator points you at the real artifact.search at fold (D-0077).

READ FIRST (disk is canonical; do NOT skip):
- core-docs/START_HERE.md + core-docs/CURRENT_STATE.md 'Known failures / gotchas' IN FULL (the load-bearing gotcha corpus: the WEDGE class -> launch persistent model servers DETACHED + reap before finalize + assert 0 UNMANAGED orphans; pwsh 7.4.6 traps; per-file EOL; 'trust the heartbeat, not the process list').
- core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md -- THE GOVERNING DESIGN DOC + shared contract for the Wave 1 memory substrate (D-0080/D-0081). Read the sections named in your SCOPE; on any conflict this doc + the live gates win.
- core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md section 8 (worker-spec rules) + core-docs/SKILL_CONTRACT.md + core-docs/MODULE_WORK_ORDER_TEMPLATE.md (author your module's WORK_ORDER.md + skill.json TO CONTRACT).
- core-docs/DECISION_LOG_INDEX.md -> pull D-0080 + D-0081 (direction) and D-0077 (the cross-module smoke rule that governs this wave) only as needed. Governing sections for you: 11.1 (retrieval verification metrics), 8.6 (context-quality signals), 21 Priority 2, 22 (the final decision rule).

SHARED CONTRACT (D-0077): RETRIEVER INTERFACE (governing core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md section 8): op `search`; inputs { query:string, k:int, filters?:{...} }; result: a ranked array of { source_path, content_hash (or version id), chunk_id, span (byte offsets or heading/section path), score, snippet } in DETERMINISTIC order (stable tie-break). You CONSUME it (lane B / module 36 produces it). Your harness must call ANY retriever satisfying this interface -- your baseline now, artifact.search at fold. Record the interface + your benchmark schema in modules/37-retrieval-eval/SCHEMA_NOTES.md.

SCOPE IN (create ONLY modules/37-retrieval-eval/ + tests/fixtures): a BENCHMARK SCHEMA where each query carries its REQUIRED-SOURCE labels (the source(s)/span(s) a correct retrieval must surface) + optional forbidden/stale sources. A FIXTURE CORPUS (a small fully-known doc set) + an INITIAL Life Orchestrator benchmark question set (a handful of real questions with required core-docs as labels). A LEXICAL BASELINE retriever satisfying the retriever interface (deterministic; term-overlap / BM25-lite over the fixture corpus) giving a KNOWN baseline. METRICS: recall@K, MRR, stale-source rate (a required source present but STALE/superseded counts WRONG), provenance completeness (every hit has source_path + content_hash + span). A REPORT ARTIFACT: machine-readable (JSON) AND human-readable (Markdown), deterministic.
NON-GOALS (do NOT build): a production router, the real embedding provider, artifact.search itself, a UI, summaries.

ACCEPTANCE: a DETERMINISTIC benchmark run (same corpus+queries+retriever -> identical report); the known lexical-baseline numbers reproduced; a test that FAILS when a required source is ABSENT from results; a VERSION/STALENESS test (a stale/superseded source counted as a miss); machine- + human-readable reports emitted.

GATES (fail-closed): OFF-MACHINE FIRST (cloud -- CPU-only python or pwsh; fully deterministic) THEN `-Live` on the executor. Author skill.json (0.1.0) + README.md + WORK_ORDER.md to SKILL_CONTRACT. Keep the report canonical/deterministic (double-run identical).

LEASE + SHIP DISCIPLINE (res.lease #29): acquire in gpu -> git -> doc order, each BEFORE the work it guards; release in REVERSE. You hold docs:[] so you take NO doc lease. Take the git lease only around your dev.ship commit, release after. device_bash is a Linux VM and CANNOT run Windows pwsh -- everything runs through the executor (exec-job.sh). Ship via dev.ship (it verifies sha256 + AST + tests FAIL-CLOSED and commits ONLY your named files under the git lease). VERIFY the real HEAD via native git log / git show --stat, NOT the dev.ship 'committed' field (D-0072); if a stale 0-byte .git/index.lock blocks it, clear it via an executor task (assert no git.exe running) then re-commit. The exact res.lease + report command lines (with this plan's id) are appended to this prompt below.

VERIFY / REPORT (docs:[] -- the ORCHESTRATOR mirrors + folds ALL core-docs from your report; do NOT edit any core-doc): report DONE/PARTIAL/DEFERRED per acceptance item with the exact file+function delta and the test that proves it; the off-machine + live counts; 0 UNMANAGED llama-server/python orphans; review_queue.jsonl before==after (you are not a producer). WRITE your module's SCHEMA_NOTES.md recording EVERY schema/interface interpretation -- REQUIRED, the D-0077 cross-module fold smoke depends on it. Fallback (D-0061, negative results are first-class): if you cannot finish safely, ship the coherent TESTED prefix, keep it self-contained, and report PLAINLY what remains and why. Report via the -Action report command appended below (with this plan's id). (SCHEMA_NOTES.md MUST record the benchmark schema + the retriever interface you code against.)

SCOPE OUT / do NOT: implement artifact.search or a real retriever beyond your baseline; touch model modules / models.json; touch any other module or ANY core-doc (docs:[]).

Notes: CPU lane, CPU-only, parallel-safe (distinct module). NEW module modules/37-retrieval-eval -> OMIT skill_id/skill_dir (worker authors skill.json 0.1.0). Runs fully isolated (ships its own lexical baseline + fixture corpus); CONSUMES the retriever interface so the orchestrator can point it at real artifact.search at fold (D-0077). Brief: core-docs/fanout/FANOUT_AGENT_003.md.

## Resource leases (collision safety -- res.lease #29)
Acquire these BEFORE the work they guard, in THIS order (gpu -> git -> doc); each blocks up to the wait:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "git" -Holder "RETRIEVAL-EVAL-i25" -TtlSeconds 1800 -WaitSeconds 900
```
Acquire returns a lease_id; keep each one. Renew before its TTL if the work runs long.
Release in REVERSE order when the guarded work is done, or immediately if you block/abort:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "git" -Holder "RETRIEVAL-EVAL-i25"
```
(Release-by-holder is shown; releasing with the exact -LeaseId is stronger.)

## Report back (cadence: on_all)
Report at least once when you finish or block. Run:
```
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId "fo-25-3b718a13" -WorkerId "RETRIEVAL-EVAL-i25" -State done -Summary "<one line: what you did>" -PlansDir "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"
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

Deterministic benchmark run (identical report on re-run); known lexical-baseline numbers reproduced; a test that FAILS when a required source is absent; a version/staleness test (stale source counted a miss); machine + human reports emitted. Gates: off-machine (CPU-only, deterministic) FIRST, then `-Live`. ORCHESTRATOR runs the D-0077 cross-module smoke at fold.

## Report-back record (ORCHESTRATOR fills from plans/fo-25-3b718a13/reports/ before archiving)

_Empty until the worker reports via -Action report (workers run docs:[], never edit this doc). The orchestrator records commit(s), test counts, measurements, and residuals/follow-ons here at fold, then archives this brief to archive/fanout-agents/i25-<id>.md and resets the slot to EMPTY._
