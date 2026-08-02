# FANOUT_AGENT_001 -- CONFORMANCE (CPU) lane: episode.record #39 0.1.0 -> 0.1.1

## Header

- **Slot:** FANOUT_AGENT_001
- **Status:** READY
- **Wave / iteration:** i28 (plan id `fo-28-45c4ad65`)
- **Lane:** CPU (single-worker wave -- GPU + frontier + coding/2nd-CPU lanes SKIPPED)
- **Worker id / label:** `EPISODE-CONFORM-i28` -- conform episode.record #39 to MEMORY_CONTRACT Amendment A1
- **Module/area (exclusive):** `modules/39-episode-memory` (skill `episode.record`) ONLY
- **GPU:** false
- **Docs:** `[]`

## Mission

Conform the shipped episode.record #39 (0.1.0) to the AMENDED `core-docs/MEMORY_CONTRACT.md` (Amendment A1, record-envelope v0.1.1, D-0085) so its `episode` + `failure` records ingest into artifact.search #36 0.2 `ingest_records` with ZERO rejections. This resolves the two i27 D-0077 divergences the Wave-2 fold only BRIDGED. #36 0.2 is the already-shipped, FROZEN consumer -- you conform the PRODUCER. Governing: `MEMORY_CONTRACT.md` s0 Amendment A1 / s1 / s5.

## Unit (executable summary)

The COMPLETE emitted worker prompt is on disk at
`modules/30-orchestrate-fanout/runtime/artifacts/93d716e8-9551-466b-a3fc-c6df1875bf1b/workers/worker-EPISODE-CONFORM-i28.prompt.md`
-- read it IN FULL once the folder is granted. This section is the executable summary.

**READ FIRST (disk canonical):** `core-docs/START_HERE.md`; `core-docs/CURRENT_STATE.md` -> 'Known failures / gotchas' IN FULL (esp. the CASE-INSENSITIVE-`$op` gotcha THIS module reported at i27 -> name the local `$opName`; the pwsh 7.4.6 sort-copy / empty-array-unroll / array-double-wrap / `${var}` traps; json.dump exotic-type coercion; dev.ship can FALSE-NEGATIVE `committed` -> verify native git); **`core-docs/MEMORY_CONTRACT.md` IN FULL, esp. s0 Amendment A1, s1 (the `status` field + the CLOSED record_kind enum), s5 (staleness = a STRING)**; your OWN `modules/39-episode-memory/` (SCHEMA_NOTES s2/s3/s4/s8/s10, `episode_record.py`, `skill.json`, `tests/`); `modules/36-artifact-search/SCHEMA_NOTES.md` s4 + `artifact_search.py` `STATUS_ENUM` + `TYPED_RECORD_KINDS` (the EXACT sets #36 enforces).

**The amendment (A1, v0.1.1) -- conform TO it:**
1. Envelope `status`/`currentness` = a SINGLE STRING from the s5 enum (`current` baseline) -- NOT a boolean, NOT an object. Retire `{state, stale_reasons, verified}`. Map LOSSLESSLY: `status` <- `state`; a verify/provenance failure -> `"unverified"`; multi-reason (rare, not at creation) -> optional `attrs.stale_reasons:[...]`. The failure's INVESTIGATION state stays a distinct `body.status` -- UNCHANGED.
2. `record_kind` enum is CLOSED; `episode_stage` is NOT a kind. Per-stage detail is STRUCTURAL -- in the `episode` `body.stage_sequence` (+ `child_edges:has_stage`), NOT a separate ingestable record. The ingest bundle carries ONLY `episode` + `failure`.

**SCOPE IN (touch ONLY `modules/39-episode-memory/`):**
1. STATUS->STRING in `build_envelope` (+ EVERY envelope-status site: episode + failure); preserve info losslessly; do NOT change `body.status`.
2. NO `episode_stage` records: drop it from the emitted set (RECORD_KINDS / recorder / ingest bundle); FOLD the full s4 stage body (stage_index/name/role/status/closed_explicitly/duration_ms/tool_invocations/state_changes/test_results/reviewer_outcomes/human_interventions/errors/notes/model_provenance) INTO `episode.body.stage_sequence` (enrich from lightweight refs to FULL objects) -- NO field lost vs 0.1.0; fix `child_edges` so they do NOT point at nonexistent stage records; `episode_stages.json` may remain a debug artifact but NOT in the ingest bundle.
3. VALIDATOR (op validate, s8): `status` must be a STRING in the s5 enum; remove the `episode_stage` branch; validate stages inside the episode body; keep content_hash recompute + id/edge checks.
4. VERSION+DOCS: extractor_fingerprint `episode.recorder/0.1.0` -> `0.1.1`; skill.json 0.1.0 -> 0.1.1; update README/WORK_ORDER/SCHEMA_NOTES to the amended contract (note ALL record ids/versions change vs 0.1.0 BY DESIGN; re-run still byte-identical).

**ACCEPTANCE:** envelope status is an ENFORCED STRING on every record; ingest bundle = only episode+failure (NO episode_stage); per-stage detail fully recoverable in-body (a test asserts each s4 field survives); recorder still completes an episode from a SUCCESS and a FAILURE/truncated trace; the candidate `failure` still emits with `body.status='unverified'`; failure-signature seam (op search-failures) UNCHANGED + green; records drop into #36 0.2 `ingest_records` with ZERO rejections (SELF-CHECK vs STATUS_ENUM + TYPED_RECORD_KINDS + s4); deterministic byte-identical re-run; `records_digest` reproducible; full suite green (0.1.0 was 114 -> REPORT the new count).

**GATES:** off-machine FIRST (cloud python/pwsh, CPU-only, deterministic) THEN `-Live`; double-run byte-identical; dev.ship (sha256 + AST + tests, fail-closed, named files only).

**NON-GOALS / SCOPE OUT:** do NOT touch #36 / MEMORY_CONTRACT / any core-doc (docs:[]); do NOT re-add `episode_stage` as a kind; do NOT change the failure schema/seam semantics; do NOT touch models.json / model modules / any other module; no embeddings / catalog-DB / context-compiler / agent.local-wiring / UI.

## Rails (standing)

- Read `START_HERE.md` + `CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`. Do ONE unit; `docs:[]`; touch only `modules/39-episode-memory`.
- Everything runs through the executor (`exec-job.sh`); `device_bash` is a Linux VM and CANNOT run Windows pwsh.
- Any persistent llama-server launches DETACHED + is reaped before finalize (N/A here -- no model); assert 0 UNMANAGED orphans anyway.
- Report plainly if a part is impractical (D-0061 -- negative results are first-class): ship the coherent TESTED prefix, say what remains + why.

## Resource leases + report-back (verbatim -- res.lease #29, plan fo-28-45c4ad65)

```
acquire (only around the dev.ship commit): pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action acquire -Resource "git" -Holder "EPISODE-CONFORM-i28" -TtlSeconds 1800 -WaitSeconds 900
release (reverse, after commit):           pwsh -NoProfile -File modules/29-resource-lease/Invoke-ResLease.ps1 -Action release -Resource "git" -Holder "EPISODE-CONFORM-i28"
report:                                     pwsh -NoProfile -File modules/30-orchestrate-fanout/Invoke-OrchestrateFanout.ps1 -Action report -PlanId "fo-28-45c4ad65" -WorkerId "EPISODE-CONFORM-i28" -State done -Summary "<one line>" -PlansDir "C:\Users\just_\LifeOrchestrator-Refresh\modules\30-orchestrate-fanout\runtime\plans"
```

docs:[] -> NO doc lease; CPU lane -> NO gpu lease. VERIFY the real HEAD via native `git log` / `git show --stat`, NOT the dev.ship `committed` field (D-0072); clear a stale 0-byte `.git/index.lock` via an executor task (assert no `git.exe` running) then re-commit.

## Verification

Off-machine + `-Live` test counts (0.1.0 baseline 114); a test proving each per-stage s4 field survives in-body; a self-check that episode+failure ingest into a #36-shape sink with 0 rejections; deterministic re-run byte-identity + reproducible `records_digest`; 0 UNMANAGED orphans; `review_queue.jsonl` before==after. **UPDATE `modules/39-episode-memory/SCHEMA_NOTES.md`** to the amended contract -- REQUIRED, the D-0077 fold smoke depends on it.

## Report-back record (ORCHESTRATOR fills from `plans/fo-28-45c4ad65/reports/` at fold)

_pending -- worker reports via `-Action report` (docs:[]); the orchestrator records commit + counts + the record_kinds/stage representation + residuals here before archiving._
