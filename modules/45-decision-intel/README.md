# Module 45 -- `decision.intel` (Decision Record Intelligence, PB-6)

Deterministic, CPU-only, stdlib-only **PRODUCER** for the Collective Agent memory substrate (D-0080 wave;
PB-6, the first PB-7 knowledge-surface re-layer increment). It parses the append-only
`core-docs/DECISION_LOG.md` (+ `DECISION_LOG_INDEX.md` routing rows) and emits **typed
`record_kind="decision"` record-envelope artifacts** conforming to `core-docs/MEMORY_CONTRACT.md` section
1, so the catalog (`artifact.search` #36) ingests them as **first-class records**. No model, no network,
no DB writes -- it EMITS artifacts; #36 owns storage.

## Why

`DECISION_LOG.md` is ~640 KB and grows without bound; a session must never read it whole
(`DOC_PROTOCOL.md` section 4). Today the boot path ingests `DECISION_LOG_INDEX.md` whole instead. PB-6
makes the decision surface **losslessly-backed** (git + the append-only log, untouched), **typed-indexed**
(this producer), and **cold-retrievable** (the `compile_relevant_decisions` verb, FANOUT_AGENT_002's lane
-- routed through #40 + #37, no new retrieval arch), while the hot boot surface stays bounded. Governing
design: `research/2026-08-14-pb7-relayer-design.md` + `-2.md` (the hardened hot/cold ruleset); the FROZEN
field contract: `research/2026-08-14-pb6-decision-record-schema.md`.

## What it does

- **Parses** every `D-####` entry in `DECISION_LOG.md` (both the `###` and `##` heading conventions the
  log's history contains) into a byte-exact span, plus every row of `DECISION_LOG_INDEX.md`.
- **Deterministically derives** (every regex documented in `SCHEMA_NOTES.md`): `date`, `iteration`,
  `affected_modules` + `planes`, `type`, `authority`, `binding_scope` (`standing_prohibition` |
  `invariant` | `ordinary`, from FROZEN/prohibited vs never/always/inviolable/HARD markers), `enforced_by`
  (a known deterministic gate id, else `none`).
- **Edges**: full `supersedes`/`superseded_by` from `DECISION_LOG_INDEX.md` bracket annotations UNIONED
  with explicit "supersedes/replaces D-####" declarations in entry bodies (handles a compact citation
  shorthand AND a fully-repeated list); `partially_supersedes` on a softer revision cue naming a specific
  decision (conservative -- never invents, never guesses); `derives_from` on cited research digests.
  `status` (current/superseded/folded/closed) is **edge-driven**, not merely copied from a possibly-stale
  index annotation.
- **Honest ambiguity**: any entry this producer cannot classify deterministically (no module reference; a
  supersession edge whose index-row annotation is missing; an unresolved supersession target) is flagged
  in `ambiguous` / `unresolved_supersession_targets` -- **never silently dropped**.
- **Coverage + validation**: every index row maps to a record and vice versa (`coverage.json`); every
  record passes an s1-adapted validator (`index_manifest.json.validation`).

`record_kind`: `decision` only.

## Invocation

```powershell
# index the real repo (ingested_through is REQUIRED -- the caller's native git HEAD sha; this worker
# never shells out to git)
pwsh -NoProfile -File .\Invoke-DecisionIntel.ps1 `
  -DecisionLogPath ..\..\core-docs\DECISION_LOG.md `
  -DecisionLogIndexPath ..\..\core-docs\DECISION_LOG_INDEX.md `
  -IngestedThrough (git rev-parse HEAD)

# generic form
pwsh -NoProfile -File .\Invoke-DecisionIntel.ps1 -InputsJson '{"op":"index","decision_log_path":"...","decision_log_index_path":"...","ingested_through":"..."}'

# re-validate an emitted records artifact against MEMORY_CONTRACT s1
pwsh -NoProfile -File .\Invoke-DecisionIntel.ps1 -Op validate -RecordsPath .\runtime\artifacts\<id>\records.jsonl
```

Params: `-Op index|validate` (default index) · `-DecisionLogPath` / `-DecisionLogIndexPath` (index) ·
`-Namespace` (default `decisions`) · `-IngestedThrough <sha>` (index; REQUIRED) · `-RecordsPath` (validate)
· `-PythonPath` / `-WorkerPath` · `-InputsJson` · `-ArtifactRoot` / `-InvocationId`.

## Outputs

One `lifeorch.skill.result/0.1` envelope on stdout (`result` = counts, `records_digest`, `validation`,
`edge_summary`, `coverage`, `ambiguous`, `unresolved_supersession_targets`, `ingest_run_id`). Artifacts
under `runtime/artifacts/<invocation_id>/`:

- **`records.jsonl`** -- one canonical MEMORY_CONTRACT s1 record per line (deterministic order). The
  full-fidelity artifact (`parent_edges`/`child_edges` edge-object form).
- `records.json` -- the same records as a canonical array.
- `ingest_records.json` -- conforms EXACTLY to the #36 `ingest_records` op INPUT shape (SCHEMA_NOTES s4):
  `{op,db,ingest_run,created_by_ingest_run,record_count,records:[{...,attrs:{...},edges:[{edge_kind,
  dst_ref,dst_kind}]}]}`.
- `index_manifest.json` -- counts by status/binding_scope + `records_digest` + validation + coverage +
  ambiguous list + fingerprints.
- `coverage.json` -- index-row <-> record 1:1 assertion + span-resolution check.
- `summary.md` -- human-readable rollup.

## Determinism

All ids are content+path derived (`dec_<NNNN>` from the canonical D-number); `created_by_ingest_run` is
content-derived (never wall-clock); `ingested_through` is CALLER-supplied (never git-shelled-out inside
the worker, mirrors #38's D-0072 rule); canonical artifacts contain no absolute paths / timestamps /
random ids. **Verified: identical `DECISION_LOG.md` + `DECISION_LOG_INDEX.md` content + the same
`ingested_through` -> byte-identical artifacts across two independent runs** (double-run byte-identity).
Spans are BYTE offsets over raw `DECISION_LOG.md` bytes (EOL-faithful -- core-docs are CRLF).

## Contract + tests

Builds to `core-docs/research/2026-08-14-pb6-decision-record-schema.md` (the FROZEN D-0077 governing doc
for this producer/consumer pair) + `core-docs/MEMORY_CONTRACT.md` s1 + `core-docs/SKILL_CONTRACT.md` v0.2.
See `SCHEMA_NOTES.md` for EVERY marker/regex interpretation, each cross-checked against the real
`DECISION_LOG.md` (149 decisions, D-0001..D-0149, verified contiguous/no-dupes). Tests:
`tests/test_decision_intel.py` (stdlib python -- the off-machine determinism/coverage/validator harness,
run against the real corpus) and `tests/Invoke-DecisionIntelTests.ps1` (the real entrypoint -> real
worker; the cloud pre-ship gate AND the `-Live` executor gate).

**Real-corpus result** (149 decisions): `validation.ok=true` (0 errors), `coverage.ok=true` (0 missing, 0
extra), `records_digest` byte-stable across runs, `counts_by_status={current:142, superseded:5,
folded:2}`, `counts_by_binding_scope={standing_prohibition:48, invariant:49, ordinary:52}`,
`ambiguous_count=18` (all honestly explained in `SCHEMA_NOTES.md` section 6/11 -- 15 genuinely
module-less process decisions + 3 supersession-edges whose predecessor index row was never hand-annotated
to match), `unresolved_supersession_targets=0`.

## Non-goals (NOT built this increment)

Model-generated `synopsis` (RESERVED null); the `compile_relevant_decisions` retrieval verb + hot/cold
predicate (FANOUT_AGENT_002's lane); real `modules/44-project-map/` plane integration (a static
documented table stands in -- `SCHEMA_NOTES.md` section 6); internal decision-to-decision `derives_from`
beyond supersession citations; ingestion into the real #36 catalog (the orchestrator runs
`ingest_records` at fold); any UI; incremental/per-commit re-ingest (always re-parses the whole log; safe
and idempotent, not yet optimized for a delta).
