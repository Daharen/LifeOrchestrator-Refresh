# FANOUT_AGENT_001 -- GPU (<=1 per wave) lane: EMBEDDING ADAPTER (i25, plan fo-25-3b718a13)

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY -- dispatch by telling a FRESH Cowork session: "Read the Project doc `claude/fanout/FANOUT_AGENT_001.md` and execute it" + grant the one folder `C:\Users\just_\LifeOrchestrator-Refresh`.
- **Wave / iteration:** i25 (plan id `fo-25-3b718a13`)
- **Lane:** GPU (<=1 per wave)
- **Worker id:** EMBED-ADAPTER-i25
- **Module/area (exclusive):** modules/35-embedding-local (NEW; skill embedding.local)
- **GPU:** true -- gpu:true ONLY on the GPU lane
- **Docs:** `[]` (workers never edit core-docs; the orchestrator mirrors + folds)

## Mission

Turn the staged-but-UNWIRED `embedding.qwen3-0p6b` into a versioned, tested local embedding capability (NEW module 35-embedding-local) AND define the embedding-provider interface that the rest of the Wave 1 memory substrate consumes (lane 003 mocks it; the orchestrator swaps the real adapter in at fold). The ONLY GPU lane and the ONLY lane permitted to touch model modules / models.json. Governing: research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md sec 6.3 + 16; D-0080/D-0081.

## Unit (the full worker prompt -- emitted by orchestrate.fanout `plan`, verbatim)

# Fan-out worker prompt -- worker EMBED-ADAPTER-i25 (plan fo-25-3b718a13, iteration 25)

You are one worker in a fan-out build of Life Orchestrator, coordinated by an orchestrator instance.
First read core-docs/START_HERE.md and core-docs/HANDOFF.md, then the docs they route you to.

## Your scoped unit
BUILD the Wave 1 GPU lane -- the EMBEDDING ADAPTER: turn the pre-provisioned, staged-but-UNWIRED `embedding.qwen3-0p6b` into a conforming, versioned, testable LOCAL embedding capability as a NEW module `modules/35-embedding-local` (skill id `embedding.local`). This is the ONLY GPU worker in the wave and the ONLY lane permitted to touch model modules / models.json.

READ FIRST (disk is canonical; do NOT skip):
- core-docs/START_HERE.md + core-docs/CURRENT_STATE.md 'Known failures / gotchas' IN FULL (the load-bearing gotcha corpus: the WEDGE class -> launch persistent model servers DETACHED + reap before finalize + assert 0 UNMANAGED orphans; pwsh 7.4.6 traps; per-file EOL; 'trust the heartbeat, not the process list').
- core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md -- THE GOVERNING DESIGN DOC + shared contract for the Wave 1 memory substrate (D-0080/D-0081). Read the sections named in your SCOPE; on any conflict this doc + the live gates win.
- core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md section 8 (worker-spec rules) + core-docs/SKILL_CONTRACT.md + core-docs/MODULE_WORK_ORDER_TEMPLATE.md (author your module's WORK_ORDER.md + skill.json TO CONTRACT).
- core-docs/DECISION_LOG_INDEX.md -> pull D-0080 + D-0081 (direction) and D-0077 (the cross-module smoke rule that governs this wave) only as needed. Governing sections for you: 6.3 (embeddings are semantic ADDRESSES, not compressed docs), 16.1/16.2 (2080 Ti one heavyweight resident; embedding is batchable + CPU-fallback candidate), 21 Priority 1.

SHARED CONTRACT (D-0077 -- the fold depends on this): you DEFINE the EMBEDDING-PROVIDER INTERFACE (governing core-docs/research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md section 6.3): op `embed`; inputs `texts` (array<string>, batch) and/or `text` (single) + optional `normalize` (bool, default true); result (lifeorch.skill.result/0.1 envelope) carries { model_id, model_version, model_sha256, engine_build, dim:int, normalized:bool, count:int, vectors: array of float arrays in EXACT INPUT ORDER (result[i] <-> input[i]), and a per-input status for skipped empties/oversize with the input index }. The artifact.search worker (lane B, module 36) MOCKS this exact shape this same wave, and the orchestrator swaps your REAL adapter in at fold -- so pin it precisely and record it in modules/35-embedding-local/SCHEMA_NOTES.md. Determinism: same text + model + params => identical vector within a DOCUMENTED tolerance (measure + record; note any GPU nondeterminism). Failure modes: empty/whitespace-only and oversize (> the model's max sequence) return a CLEAN per-input flag/skip -- never a crash, never a silent truncated/garbage vector.

SCOPE IN (create ONLY modules/35-embedding-local/ + its tests/examples; you MAY edit models.json to WIRE this model for THIS module -- gateway tiers UNCHANGED): resolve `embedding.qwen3-0p6b` from models.json / its F: large-data home (path + sha256 verified); serve it for embeddings (llama-server embedding endpoint on the correct llama.cpp build -- determine + PIN engine_build; most non-9B tiers use b8661). Launch any persistent server DETACHED under the gpu lease and REAP the whole tree before finalize (the wedge class); assert 0 UNMANAGED orphans. Implement `embed` per the interface (single + batch; L2-normalized by default; dims + full model/version/sha256/engine provenance; input-order preservation; empty/oversize handling). Run a CPU-FALLBACK FEASIBILITY PROBE (can embeddings run CPU-only for idle/low-priority batch per governing 16.2? record feasibility + latency -- you need not ship the CPU path). Measure + record latency (single + batch) and peak VRAM/RAM (driver 591.74 SPILLS a too-big model to system RAM -- 'it loaded' != 'it fits'; the measured-PEAK required_vram is the only real admission control).
NON-GOALS (do NOT build): a vector DB/index, artifact ingestion, chunking, retrieval, routing, re-embedding pipelines. Just the adapter + its contract.

ACCEPTANCE: stable documented schema; repeated-input consistency within the stated tolerance; batch result == single-call result per input; 0 orphaned model procs; model_id/version/sha256 + engine_build recorded; latency + memory measured; fixture vectors + a similarity-ORDER test (a known-near pair ranks above a known-far pair); clean empty/oversize failures.

GATES (fail-closed): OFF-MACHINE FIRST (cloud pwsh 7.4.6 -- portable seams: schema/shape/normalization/input-order/empty-oversize against a MOCK server or deterministic stub) THEN the LIVE `-Live` proof on the 2080 Ti via the executor (real model, real vectors, real latency/VRAM, DETACHED + reaped). If you edit models.json, RE-VERIFY Module 7 stays green (base 42/42). Author skill.json (0.1.0) + README.md + WORK_ORDER.md to SKILL_CONTRACT.

LEASE + SHIP DISCIPLINE (res.lease #29): acquire in gpu -> git -> doc order, each BEFORE the work it guards; release in REVERSE. You hold docs:[] so you take NO doc lease. Take the git lease only around your dev.ship commit, release after. device_bash is a Linux VM and CANNOT run Windows pwsh -- everything runs through the executor (exec-job.sh). Ship via dev.ship (it verifies sha256 + AST + tests FAIL-CLOSED and commits ONLY your named files under the git lease). VERIFY the real HEAD via native git log / git show --stat, NOT the dev.ship 'committed' field (D-0072); if a stale 0-byte .git/index.lock blocks it, clear it via an executor task (assert no git.exe running) then re-commit. The exact res.lease + report command lines (with this plan's id) are appended to this prompt below.

VERIFY / REPORT (docs:[] -- the ORCHESTRATOR mirrors + folds ALL core-docs from your report; do NOT edit any core-doc): report DONE/PARTIAL/DEFERRED per acceptance item with the exact file+function delta and the test that proves it; the off-machine + live counts; 0 UNMANAGED llama-server/python orphans; review_queue.jsonl before==after (you are not a producer). WRITE your module's SCHEMA_NOTES.md recording EVERY schema/interface interpretation -- REQUIRED, the D-0077 cross-module fold smoke depends on it. Fallback (D-0061, negative results are first-class): if you cannot finish safely, ship the coherent TESTED prefix, keep it self-contained, and report PLAINLY what remains and why. Report via the -Action report command appended below (with this plan's id). (SCHEMA_NOTES.md MUST record the embedding-provider interface + engine_build + the measured tolerance.)

SCOPE OUT / do NOT: build a vector store / ingestion (lane B) or the benchmark (lane C); touch models.json beyond wiring THIS model; touch any other module or ANY core-doc (docs:[]). You are the sole GPU holder; the git lease serializes your commit with B/C.

Notes: GPU lane (the ONLY gpu:true worker + the ONLY lane touching model modules / models.json). NEW module modules/35-embedding-local -> OMIT skill_id/skill_dir (no skill.json yet; the worker authors it 0.1.0). Persistent embedding server launches DETACHED under the gpu lease + reaped before finalize; 0 UNMANAGED orphans. If models.json is edited, re-verify Module 7 base 42/42. DEFINES the embedding-provider interface (D-0077 shared contract with lane B). Orchestrator runs the real embedding->artifact.search->benchmark smoke at fold. Brief: core-docs/fanout/FANOUT_AGENT_001.md.

## Resource leases (collision safety -- res.lease #29)
Acquire these BEFORE the work they guard, in THIS order (gpu -> git -> doc); each blocks up to the wait:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "gpu" -Holder "EMBED-ADAPTER-i25" -TtlSeconds 1800 -WaitSeconds 900
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "git" -Holder "EMBED-ADAPTER-i25" -TtlSeconds 1800 -WaitSeconds 900
```
Acquire returns a lease_id; keep each one. Renew before its TTL if the work runs long.
Release in REVERSE order when the guarded work is done, or immediately if you block/abort:
```
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "git" -Holder "EMBED-ADAPTER-i25"
pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "gpu" -Holder "EMBED-ADAPTER-i25"
```
(Release-by-holder is shown; releasing with the exact -LeaseId is stronger.)

## Report back (cadence: on_all)
Report at least once when you finish or block. Run:
```
pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId "fo-25-3b718a13" -WorkerId "EMBED-ADAPTER-i25" -State done -Summary "<one line: what you did>" -PlansDir "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"
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

Stable documented embed schema; repeated-input consistency within a stated tolerance; batch == single per input; 0 orphaned model procs; model_id/version/sha256 + engine_build recorded; latency + peak VRAM/RAM measured; a similarity-ORDER fixture test; clean empty/oversize failures. Gates: off-machine seam tests FIRST, then a `-Live` GPU proof via the executor. If models.json is edited, Module 7 base 42/42 re-verified. ORCHESTRATOR then runs the D-0077 real embedding->artifact.search->benchmark cross-module smoke at fold.

## Report-back record (ORCHESTRATOR fills from plans/fo-25-3b718a13/reports/ before archiving)

_Empty until the worker reports via -Action report (workers run docs:[], never edit this doc). The orchestrator records commit(s), test counts, measurements, and residuals/follow-ons here at fold, then archives this brief to archive/fanout-agents/i25-<id>.md and resets the slot to EMPTY._

## Report-back record (i25 fold, D-0082)

DONE `99b6590` (11 files). embedding.local 0.1.0; Qwen3-Embedding-0.6B dim 1024 transient CUDA worker; embedding-provider interface pinned; det 2.2e-16, batch==single 8.7e-13; 42/42 (26 off + 16 -Live); models.json wired -> #7 42/42; CPU-fallback feasible; 0 orphans.
D-0077 fold smoke PASSED (real embed->store->search->benchmark; recall/provenance 1.0; digest stable; change detected). Reconciliation: `span` object vs string -> bridged at fold -> Wave-2 contract freeze.
