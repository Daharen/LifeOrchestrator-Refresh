# Work Order: Episode + Failure Memory Recorder (`episode.record`)

**Contract version targeted:** 0.2 (SKILL_CONTRACT) + MEMORY_CONTRACT s1 record-envelope **v0.1.1**
(Amendment A1, D-0085 -- string status; episode_stage retired) · **Author:** EPISODE-MEMORY-i27 (0.1.0) /
EPISODE-CONFORM-i28 (0.1.1) / 2026-08-01 · **Roadmap entry:** Wave 2 PRODUCER lane (directive Priority 5)
· **Plan:** fo-27-bab47060 (0.1.0) -> fo-28-45c4ad65 (0.1.1 conformance)

### Problem being solved
The Collective Agent has a memory/retrieval substrate (Wave 1: #35/#36/#37) but no way to REMEMBER what
happened in a run or to RECALL a relevant past failure. This module defines the episode + failure record
schemas (to the frozen MEMORY_CONTRACT s1 envelope) and a deterministic recorder that turns a run trace into
durable, validated memory -- the producer that later mining / procedure discovery / context compilation
build on.

### Immediate practical use
The orchestrator (and, later, `agent.local`) can turn any run trace into a complete episode record and a
candidate failure record, then feed them into `artifact.search` #36 0.2 `ingest_records` at fold. The
failure-signature seam lets a future retriever surface the RIGHT past failure for the active task.

### Explicit scope (in)
- The **episode** schema (directive 10.1) as an s1 `episode` envelope with the full per-stage detail
  carried STRUCTURALLY in `body.stage_sequence` (+ in-body `has_stage` child_edges by ordinal). v0.1.1
  (D-0085): `episode_stage` is NOT a `record_kind`.
- The **failure** schema (directive 5.4/10.2) as an s1 `failure` envelope, incl. a deterministic,
  task-conditioned `failure_signature`.
- A DETERMINISTIC RECORDER: run trace -> a COMPLETE episode (+ stages) EVEN on failure; idempotent ids.
- A FAILURE-SIGNATURE retrieval SEAM: a task-context query shape + a deterministic signature/facet-overlap
  baseline over a fixture failure corpus (right failure surfaces, unrelated ones excluded).
- Provenance + `sensitivity_class` on every record + an s1 VALIDATOR (incl. content_hash recomputation).
- Canonical, integer-only JSON artifacts in deterministic order; an `ingest_records` fixture bundle.

### Non-goals (out -- do NOT build)
- Auto-capture wired into `agent.local` #21 (the recorder is invoked with a trace).
- Failure MINING across a live store / procedure discovery (directive 10.2/10.3 -- later waves).
- Embeddings; the catalog DB / storage (#36 owns it); the context compiler; any UI; web search.

### Dependencies
- Modules: none at runtime (reads a trace, writes JSON). SINK = #36 0.2 `ingest_records` (fold-time, D-0077).
- Contract features: MEMORY_CONTRACT s1 (envelope v0.1), s5 (staleness), s6 (provenance), s7 (privacy);
  SKILL_CONTRACT 0.2 (manifest + result envelope + `-InputsJson` + Module 1 wrapper report).

### Skill contract requirements
- `skill_id=episode.record`, `version=0.1.1`, `determinism=deterministic`, `parallel_safe=true`,
  `batch=false`, `streaming=false`.
- `result` = an op-specific projection (ids, counts, `records_digest`/`search_digest`, `all_valid`);
  `confidence=null` (deterministic); `model_provenance=[]`; artifact kind `json`.

### Inputs and outputs
- **Inputs:** `-Op record|build-failure|search-failures|validate` + op inputs (`-Trace`, `-Failures`/`-Failure`,
  `-TaskContext`+`-Corpus`, `-Records`), or generic `-InputsJson`. See `skill.json` / `README.md`.
- **Outputs:** per op -- `episode.json`, `episode_stages.json`, `failure.json`, `records.json` (ingest
  bundle), `failures.json`, `search.json`, `validation.json`, + `worker-summary.json`. All canonical.

### Artifact structure
- `runtime/artifacts/<invocation_id>/` -> `request.json`, the op's canonical JSON artifacts,
  `worker-summary.json`, `worker-stderr.txt`, `result.json`.

### Proposed implementation
- **Language:** a stdlib-only **Python** worker (`episode_record.py`) for all deterministic logic + a thin
  **PowerShell** contract wrapper (`Invoke-EpisodeRecord.ps1`) -- the same split as #36/#37. Python because
  the logic is pure hashing/normalization/JSON; pwsh because the skill entrypoint contract is pwsh-file.

### External tools or models
- None. `pwsh >= 7.4`, `python >= 3.8` (both already present -- TOOL_MODEL_REGISTRY / CURRENT_STATE). No
  model, no GPU, no network.

### Tests
- **Off-machine (pre-ship):** `pwsh -File tests/Invoke-EpisodeRecordTests.ps1` on the cloud Linux box (real
  skill, deterministic).
- **On the executor (`-Live`):** the SAME harness with `-Live`. Both assert schema-valid envelopes + pinned
  canonical shas + `records_digest` + double-run byte-identity + the seam acceptance.

### MVP acceptance criteria
- [x] episode + failure schemas documented + frozen in SCHEMA_NOTES to s1.
- [x] the recorder turns a fixture SUCCESS trace AND a fixture FAILURE trace into COMPLETE deterministic
      `episode` records (+ stages).
- [x] a `failure` record set validates against s1.
- [x] the failure-signature seam returns the RIGHT failure for a task-context query AND excludes unrelated
      ones (a test that FAILS if an unrelated failure surfaces).
- [x] DETERMINISTIC re-run (identical records/ids/order; pinned shas + double-run byte-identity).
- [x] records shaped to drop into #36 0.2 `ingest_records` (validated vs the frozen s1 envelope / the
      fixture ingest_records schema).
- [x] **v0.1.1 (Amendment A1, D-0085):** envelope `status` is an ENFORCED single s5 STRING on every record;
      the ingest bundle is `episode` + `failure` ONLY (episode_stage retired -- per-stage detail fully
      recoverable in `episode.body.stage_sequence`, a test asserts each s4 field survives); the real
      episode + failure records ingest into #36 0.2 `ingest_records` with ZERO rejections (a local
      #36-shape self-check + the orchestrator D-0077 fold smoke).
- [x] skill.json 0.1.1 + README + WORK_ORDER + SCHEMA_NOTES to the amended contract; off-machine gate green.

### Manual verification procedure
- Run the two `record` examples and inspect `episode.json` (complete on both), `failure.json` (candidate on
  the failed run), and `validation.json` (`all_valid:true`). Run `search-failures` for `q_ffprobe` and
  confirm `media.decompose` is on top and `classify.batch`/`ocr.layout` are absent.

### Registry updates
- Add the `episode.record` entry to `TOOL_MODEL_REGISTRY.md` (orchestrator mirrors; worker is `docs:[]`).

### State updates
- Orchestrator records the module in `CURRENT_STATE.md` / `MODULE_ROADMAP.md` (worker is `docs:[]`).

### Known follow-on work
- Adopt embeddings for episodes/failures (semantic recall) once an embedding space is chosen.
- Failure MINING / procedure discovery (directive 10.2/10.3); auto-capture into `agent.local` #21.
- Reconcile the ingest bundle wrapping against the REAL #36 0.2 `ingest_records` at fold.

### STOP conditions
- Scope beyond the "Explicit scope" list; touching #36/#38/`agent.local`/models/core-docs; MVP met.
