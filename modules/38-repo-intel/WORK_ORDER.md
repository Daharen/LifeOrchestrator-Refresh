# Work Order: Repository Intelligence (`repo.intel`)

**Contract version targeted:** SKILL_CONTRACT 0.2 + **MEMORY_CONTRACT s1 (frozen, D-0083)** · **Author:**
FANOUT_AGENT_002 / REPO-INTEL-i27 / 2026-08-01 · **Roadmap entry:** `MODULE_ROADMAP.md#38-repo-intel` ·
**Plan:** `fo-27-bab47060` (Wave 2 PRODUCER lane)

### Problem being solved

The Collective Agent's memory substrate (Wave 1: #35/#36/#37) treats a file chunk as the universal retrievable
unit. MEMORY_CONTRACT s1 warns that file-chunks must NOT silently become the only memory abstraction. This
module closes the "repository intelligence" gap (directive 7.4): it turns the repo's STRUCTURE -- code
symbols, imports, skill manifests, tests, relationships -- into TYPED s1 records so retrieval can reason over
the codebase as a graph of first-class entities, not opaque text chunks.

### Immediate practical use

The orchestrator feeds this module's real `records.jsonl` / `ingest_records.json` into #36 artifact.search
0.2 `ingest_records` at the D-0077 fold, so the catalog stores symbols/skills/relationships as records. A
local agent can then retrieve "where is function X defined", "what imports this module", "which skill produces
schema Y" -- not just lexically-matching chunks.

### Explicit scope (in)

- INVENTORY over allowlisted roots with TESTED exclusions + content hashing + surfaced parse failures.
- Deterministic TYPE-AWARE parsers: Markdown sections, PowerShell defs/imports (regex), Python defs/imports
  (ast), skill.json manifests, JSON/config structure.
- RELATIONSHIPS: file->symbol, imports, file->module, test<->module, schema producer/consumer.
- DETERMINISTIC structural summaries (file outline, folder index, markdown sections) -- NO LLM.
- Canonical s1 record-envelope emitter + an s1 VALIDATOR (op `validate`).
- `skill.json` 0.1.0 + README + this work order + `SCHEMA_NOTES.md`.

### Non-goals (out -- do NOT build)

AST call-graph / full reference resolution (defs + imports only); LLM summaries; embeddings; the catalog DB /
storage (#36 owns it -- EMIT artifacts only); episode/failure schema (#39); the context compiler; UI;
git-history parsing.

### Dependencies

- Modules: consumed by #36 artifact.search 0.2 (`ingest_records`) at fold. · Tools: `pwsh>=7.4`, `python>=3.8`
  (stdlib `ast`/`json`/`hashlib`/`re` ONLY -- no third-party, no model, no network). · Contract features:
  MEMORY_CONTRACT s1 (record+provenance envelope v0.1), s4 (fingerprints), s5 (staleness), s7 (allowlist +
  exclusions); SKILL_CONTRACT 0.2 (manifest, result envelope, `-InputsJson`, artifact root).

### Skill contract requirements

`skill_id=repo.intel`, `version=0.1.0`, `determinism=deterministic`, `parallel_safe=true`, `batch=false`,
`streaming=false`. `result` = counts + record_kinds + records_digest + parse_failures + validation +
edge_summary + ingest_run_id. `confidence=null`, `model_provenance=[]`, no review-queue production. Artifact
kinds: `jsonl`, `json`, `markdown`.

### Inputs and outputs

- **Inputs:** `op` (index|validate), `root`/`roots[]`, `namespace`, `file_budget`, `exclude_dirs[]`/
  `exclude_globs[]`/`include_globs[]`, `records_path` (validate). Per `skill.json`.
- **Outputs:** `records.jsonl` (THE payload), `records.json`, `ingest_records.json`, `index_manifest.json`,
  `inventory.json`, `parse_failures.json`, `summary.md`. Shapes in `SCHEMA_NOTES.md`.

### Artifact structure

`runtime/artifacts/<invocation_id>/` -> `records.jsonl`, `records.json`, `ingest_records.json`,
`index_manifest.json`, `inventory.json`, `parse_failures.json`, `summary.md`, plus `repo_intel_args.json`,
`repo_intel_meta.json`, `worker.log`, `result.json`, `stderr.txt`.

### Proposed implementation

- **Language:** thin PowerShell entrypoint (`Invoke-RepoIntel.ps1`, house pwsh-file convention with
  `-InputsJson` + args-file/meta-file hand-off, mirroring `image.util` #15 / `artifact.search` #36) over a
  **stdlib-only Python worker** (`repo_intel.py`) that owns all deterministic parsing, record construction,
  canonical emission, and validation. Python chosen for robust deterministic text/`ast` parsing + canonical
  JSON; the worker is fully testable off-machine.

### External tools or models

None beyond `pwsh` + a stdlib `python` (both present on the box per `CURRENT_STATE.md`; no install).

### Tests

- **Off-machine (cloud pre-ship gate):** `tests/test_repo_intel.py` (stdlib python) drives the worker over
  the bundled fixture + a bounded real slice, asserting >=4 record_kinds, complete provenance, deterministic
  double-run byte-identity, parser-failure surfacing, exclusion, validator pass + tamper-detection,
  edge-endpoint resolution, and `ingest_records` shaping. `tests/Invoke-RepoIntelTests.ps1` runs the REAL
  entrypoint -> worker + validates the `lifeorch.skill.result/0.1` envelope (SkillContract.psm1); it is the
  cloud gate AND the `-Live` executor gate.
- **Through the executor:** submit `Invoke-RepoIntel.ps1 -Root fixtures/repo`; assert `result.json` +
  artifacts + validation ok.

### MVP acceptance criteria

Index the bundled fixture repo AND a bounded real slice (`modules/` + `core-docs/` under a budget); emit >=4
record_kinds (symbol, relationship, skill, summary) with COMPLETE provenance; deterministic re-run (identical
records + ids + order, byte-identical canonical artifacts); parser failures surfaced; every emitted record
PASSES the s1 validator; records shaped to drop into #36 0.2 `ingest_records`; every edge endpoint resolves
to an emitted record or a declared external ref.

### Manual verification procedure

Run `-Root fixtures\repo`; open `summary.md` + `index_manifest.json`; confirm record counts, `validation.ok`,
`edge_summary` (external == out-of-corpus refs only), and re-run to confirm identical `records_digest`.

### Registry updates

Add the `repo.intel` row to `TOOL_MODEL_REGISTRY.md` (status, location, invocation, last test) -- orchestrator
mirrors (worker holds `docs:[]`).

### State updates

`CURRENT_STATE.md` (completed modules + tests table) + `MODULE_ROADMAP.md#38` status -- orchestrator mirrors.

### Known follow-on work

AST call-graph / reference resolution; git-history parsing; deriving `produces/consumes` schema edges from
richer signals than skill.json token scan; incremental/​watch reindex; the #36 0.2 `ingest_records` op itself
(a #36 revision) and the fold reconciliation.

### STOP conditions

Scope beyond the "Explicit scope" list; a needed contract field missing (propose an amendment per
MEMORY_CONTRACT s0, do not freelance a frozen field); MVP acceptance met -> stop, do not start the next module.
