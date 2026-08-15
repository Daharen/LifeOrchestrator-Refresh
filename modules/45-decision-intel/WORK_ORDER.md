# Work Order: Decision Record Intelligence (`decision.intel`)

**Contract version targeted:** SKILL_CONTRACT 0.2 + **MEMORY_CONTRACT s1 (frozen, D-0083)** + the FROZEN
PB-6 field contract `research/2026-08-14-pb6-decision-record-schema.md` · **Author:** FANOUT_AGENT_001 /
DEC-PRODUCER-i56 / 2026-08-15 · **Roadmap entry:** `MODULE_ROADMAP.md#45-decision-intel` · **Plan:**
i56 PB-6 build (the designed first PB-7 increment, D-0149)

### Problem being solved

`DECISION_LOG.md` (~640 KB, append-only, 149 entries at i56) grows without bound; boot must never ingest
it whole. The current boot path ingests `DECISION_LOG_INDEX.md` whole instead, which is itself a
growth-exempt catalog (D-0139) that will keep growing. PB-7's red-team (D-0119, `research/2026-08-14-
pb7-relayer-design-2.md` s8) found the naive "HOT iff current AND in-window" rule breaks on
current-forever standing prohibitions (F1), cross-cutting gotchas (F2), partial supersession (F3), and
between-wave currency (F4). This module is the PRODUCER half of PB-6 -- the first PB-7 build increment --
that turns the decision log into typed, supersession-aware, hardened-field records so the later retrieval
verb (FANOUT_AGENT_002) can serve a bounded hot decision surface instead of a whole-file ingest.

### Immediate practical use

The orchestrator feeds this module's real `records.jsonl` / `ingest_records.json` into #36
artifact.search `ingest_records` at the D-0077 fold, so the catalog stores decisions as typed records
with `binding_scope`/`enforced_by`/`ingested_through`/supersession edges. FANOUT_AGENT_002's
`compile_relevant_decisions` verb (routed via #40 + #37) then serves a bounded task-relevant + standing-
constraint decision set instead of a whole-log or whole-index read.

### Explicit scope (in)

- Deterministic entry parsing of `DECISION_LOG.md` (byte-exact spans, both `##`/`###` heading eras) +
  `DECISION_LOG_INDEX.md` routing-row parsing.
- Deterministic field derivation: `date`, `iteration`, `affected_modules`, `planes` (static documented
  table), `type`, `authority`, `binding_scope`, `enforced_by`, `ingested_through` (caller-supplied).
- Edge derivation: full `supersedes`/`superseded_by`/`folded_into` (index bracket markers UNIONED with
  body-declared full-replacement markers, handling compact + list citation shorthand),
  `partially_supersedes` (conservative, cue+target-required), `derives_from` (cited research digests).
- Envelope `status` derivation, edge-driven (not merely index-row-copied), per the frozen contract s8
  rule 4.
- Honest ambiguity surfacing: `ambiguous[]` (ties per-decision flags to a reason), never a silent drop.
- Coverage validation (`coverage.json`): every index row <-> a record, 1:1; span resolution.
- Canonical s1 record-envelope emitter (`records.jsonl`/`records.json`) + an s1-adapted VALIDATOR
  (op `validate`) + the exact #36 `ingest_records` INPUT-shape drop-in (`ingest_records.json`).
- `skill.json` 0.1.0 + `README.md` + this work order + `SCHEMA_NOTES.md` (every marker/regex documented).

### Non-goals (out -- do NOT build)

Model-generated synopsis (RESERVED null); the `compile_relevant_decisions` retrieval verb + hot/cold
predicate (FANOUT_AGENT_002's lane -- reuses #40+#37, no new retrieval arch); real `modules/44-
project-map/` plane integration (a static table stands in, documented as an interpretation gap); internal
decision-to-decision `derives_from` beyond supersession citations; ingestion into the real #36 catalog
(orchestrator-run at fold); any UI; git-history parsing; incremental/per-commit re-ingest optimization.

### Dependencies

- Modules: consumed by #36 artifact.search (`ingest_records`) at fold; downstream consumer = the
  FANOUT_AGENT_002 verb lane (module 40/37 reuse, no new module). · Tools: `pwsh>=7.4`, `python>=3.8`
  (stdlib `json`/`hashlib`/`re`/`os` ONLY -- no third-party, no model, no network). · Contract features:
  the frozen PB-6 field contract (envelope conformance s1, determinism s2, the typed field table s3, edge
  kinds, the D-0077 fold smoke s5); MEMORY_CONTRACT s1 (record+provenance envelope); `modules/36-
  artifact-search/SCHEMA_NOTES.md` s4 (`ingest_records` INPUT shape, consumed verbatim); SKILL_CONTRACT
  0.2 (manifest, result envelope, `-InputsJson`, artifact root).

### Skill contract requirements

`skill_id=decision.intel`, `version=0.1.0`, `determinism=deterministic`, `parallel_safe=true`,
`batch=false`, `streaming=false`. `result` = counts by status/binding_scope + `records_digest` +
`validation` + `edge_summary` + `coverage` + `ambiguous` + `unresolved_supersession_targets` +
`ingest_run_id`. `confidence=null`, `model_provenance=[]`, no review-queue production. Artifact kinds:
`jsonl`, `json`, `markdown`.

### Inputs and outputs

- **Inputs:** `op` (index|validate), `decision_log_path`, `decision_log_index_path`, `namespace`
  (default `decisions`), `ingested_through` (REQUIRED, index; the DECISION_LOG.md HEAD sha, caller-
  supplied), `records_path` (validate). Per `skill.json`.
- **Outputs:** `records.jsonl` (the full-fidelity artifact), `records.json`, `ingest_records.json` (the
  #36 drop-in), `index_manifest.json`, `coverage.json`, `summary.md`. Shapes in `SCHEMA_NOTES.md`.

### Artifact structure

`runtime/artifacts/<invocation_id>/` -> `records.jsonl`, `records.json`, `ingest_records.json`,
`index_manifest.json`, `coverage.json`, `summary.md`, plus `decision_intel_args.json`,
`decision_intel_meta.json`, `worker.log`, `result.json`, `stderr.txt`.

### Proposed implementation

- **Language:** thin PowerShell entrypoint (`Invoke-DecisionIntel.ps1`, house pwsh-file convention with
  `-InputsJson` + args-file/meta-file hand-off, mirroring `repo.intel` #38) over a **stdlib-only Python
  worker** (`decision_intel.py`) that owns all deterministic parsing, field/edge derivation, canonical
  emission, coverage checking, and validation. Python chosen for robust deterministic text/regex parsing
  + canonical JSON; the worker is fully testable off-machine.

### External tools or models

None beyond `pwsh` + a stdlib `python` (both present on the box per `CURRENT_STATE.md`; no install).

### Tests

- **Off-machine (cloud pre-ship gate):** `tests/test_decision_intel.py` (stdlib python) drives the
  worker over the REAL `core-docs/DECISION_LOG.md` + `DECISION_LOG_INDEX.md` (no synthetic fixture needed
  -- the corpus itself is small enough and its structure IS the acceptance surface), asserting: coverage
  ok (0 missing/extra), validator ok (0 errors), deterministic double-run byte-identity (records.jsonl,
  records.json, ingest_records.json, index_manifest.json, coverage.json all byte-identical), a
  `standing_prohibition` case present + correctly derived, an `enforced_by=<gate>` case present, a
  `partially_supersedes` default-conservative case (zero false positives spot-checked), zero unresolved
  supersession targets, `ingest_records.json` conforms to the #36 INPUT shape (required keys present per
  record). `tests/Invoke-DecisionIntelTests.ps1` runs the REAL entrypoint -> real worker + validates the
  `lifeorch.skill.result/0.1` envelope; it is the cloud gate AND the `-Live` executor gate.
- **Through the executor:** submit `Invoke-DecisionIntel.ps1 -DecisionLogPath ... -DecisionLogIndexPath
  ... -IngestedThrough <native-git-HEAD-sha>`; assert `result.json` + artifacts + `coverage.ok` +
  `validation.ok`.

### MVP acceptance criteria

Index the REAL `DECISION_LOG.md` + `DECISION_LOG_INDEX.md` at a frozen HEAD; `coverage.ok=true` (every
index row has a record, every record resolves to a canonical span); every emitted record PASSES the
s1-adapted validator; deterministic re-run (identical records + ids + order, byte-identical canonical
artifacts, proven via double-run); `ingest_records.json` conforms exactly to the #36 `ingest_records`
INPUT shape; every declared full-supersession/fold target resolves to a known decision id (0 unresolved);
every field this producer cannot classify deterministically is HONESTLY flagged in `ambiguous`, never
silently dropped or guessed (D-0107/D-0109 discipline).

### Manual verification procedure

Run against the real `core-docs/DECISION_LOG.md` + `DECISION_LOG_INDEX.md` with a real native-git HEAD
sha; open `summary.md` + `index_manifest.json`; confirm `coverage.ok`, `validation.ok`,
`counts_by_status`/`counts_by_binding_scope` are sane against a manual spot-check of several known
decisions (e.g. D-0079 GATE-NO warm-pool red-team, D-0146 PCB gate GO superseding D-0140/D-0142/D-0145,
D-0009/D-0011 folded into D-0028); re-run to confirm identical `records_digest`.

### Registry updates

Add the `decision.intel` row to `TOOL_MODEL_REGISTRY.md` (status, location, invocation, last test) --
orchestrator mirrors (worker holds `docs:[]`).

### State updates

`CURRENT_STATE.md` (completed modules + tests table) + `MODULE_ROADMAP.md#45` status -- orchestrator
mirrors.

### Known follow-on work

Real `modules/44-project-map/` plane integration (replace the static `MODULE_PLANE_MAP`); the
`compile_relevant_decisions` retrieval verb + hardened hot/cold predicate (FANOUT_AGENT_002, next lane);
model-generated `synopsis` (PB-7 layer-2); internal citation-style `derives_from` beyond supersession;
incremental/per-commit re-ingest (frozen contract s8 rule 5 -- currently always full-reparse, safe but
not yet delta-optimized); the doc-commit-gate wiring so this producer becomes a commit-time ingestion
trigger (frozen contract s6 guardrail).

### STOP conditions

Scope beyond the "Explicit scope" list; a needed contract field missing (propose an amendment per
MEMORY_CONTRACT s0 / the PB-6 frozen doc, do not freelance a frozen field); MVP acceptance met -> stop, do
not start the retrieval-verb lane (that is FANOUT_AGENT_002's scope).
