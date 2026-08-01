# FANOUT_AGENT_002 -- Wave 2 PRODUCER lane: repo.intel (NEW module 38) (READY)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** READY (dispatch on Nicholas's go)
- **Wave / iteration:** i27 (plan id `fo-27-bab47060`)
- **Lane:** CODING (CPU)
- **Worker id / label:** REPO-INTEL-i27
- **Module/area (exclusive):** `modules/38-repo-intel` (NEW module; skill `repo.intel`)
- **GPU:** false
- **Docs:** `[]`

## Mission

A NEW deterministic module that parses the repo by source TYPE and emits TYPED record-envelope artifacts (code symbols, imports, skill-manifests, tests, relationships, deterministic structural file/folder summaries) conforming to **MEMORY_CONTRACT s1** -- so the catalog (#36 0.2, same wave) ingests them as first-class records, NOT chunks. PRODUCER half of the split; the orchestrator feeds your real output into #36 0.2 `ingest_records` at fold (D-0077). Governing: `core-docs/MEMORY_CONTRACT.md` s1/s4/s7/s9 + the directive s7.

## Unit (full worker prompt)

Your COMPLETE mission is the emitted worker prompt -- read it IN FULL and execute it:
`modules/30-orchestrate-fanout/runtime/artifacts/24c6dcd3-15d7-49d7-a102-b0038a34a5ae/workers/worker-REPO-INTEL-i27.prompt.md` (also delivered to Nicholas as a file for direct paste-dispatch).

SCOPE IN (create ONLY `modules/38-repo-intel/` + tests/fixtures): INVENTORY (allowlisted roots, TESTED exclusions, content hashes, deterministic walk, surfaced parse failures); TYPE-AWARE PARSERS (Markdown heading/section hierarchy; pwsh .ps1/.psm1 + python .py symbol defs + imports; skill.json manifests; JSON/config structure); RELATIONSHIPS (file->symbol, imports, file->module, test<->module, schema producer<->consumer); DETERMINISTIC structural SUMMARIES (file/folder outlines -- NO LLM); provenance + parser/extractor FINGERPRINTS; a canonical-JSON record emitter + an s1 VALIDATOR. record_kinds: `symbol`/`entity`/`relationship`/`skill`/`summary`; edges are first-class.
NON-GOALS: AST call-graph / full reference resolution; LLM summaries; embeddings; the catalog DB (#36 owns storage -- you EMIT artifacts only); episodes/failures (#39); git-history parsing.
SHARED CONTRACT (D-0077): MEMORY_CONTRACT s1 envelope (normative field names + id derivation); record every interpretation in `modules/38-repo-intel/SCHEMA_NOTES.md`.

## Verification

Index a fixture repo AND a bounded real slice (modules/ + core-docs/ under a budget); emit >=4 record_kinds with COMPLETE provenance; DETERMINISTIC re-run (identical records/ids/order); parser failures surfaced; emitted records PASS the s1 validator AND are shaped to drop into #36 0.2 `ingest_records`; every edge endpoint resolves. skill.json 0.1.0; report off-machine + live counts.

## Rails (standing)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures / gotchas' IN FULL first; obey `SKILL_CONTRACT.md` + **`MEMORY_CONTRACT.md`** (the frozen Wave-2 shared contract) + `MODULE_WORK_ORDER_TEMPLATE.md` (author skill.json + README + WORK_ORDER + SCHEMA_NOTES to CONTRACT).
- res.lease #29: **git only** (docs:[] -> no doc lease; CPU lane -> no gpu lease). Take git ONLY around your `dev.ship` commit, release after. Ship via `exec-job.sh devship` (sha256+AST+tests, FAIL-CLOSED, named files only, trailers). Files reach the box via SendUserFile + device_commit_files. Verify the real HEAD via native `git log`/`git show --stat`, NOT dev.ship's `committed` (D-0072).
- Do ONE unit; never touch another module/area or ANY core-doc (`docs:[]`). CPU-only, no model, no network; assert 0 UNMANAGED llama-server/python orphans; `review_queue.jsonl` before==after.
- Gate OFF-MACHINE first (cloud pwsh/python, deterministic) THEN `-Live` on the executor; canonical outputs double-run byte-identical. Report via `-Action report -PlanId fo-27-bab47060 -WorkerId <id> -State done` + a plain summary (negative results are first-class, D-0061).

## Report-back record (ORCHESTRATOR fills from `plans/fo-27-bab47060/reports/` before archiving)

(pending -- commit(s), test counts, measurements, residuals/follow-ons discovered.)
