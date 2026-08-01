# Module 38 -- `repo.intel` (Repository Intelligence)

Deterministic, CPU-only, stdlib-only **PRODUCER** for the Collective Agent memory substrate (D-0080 Wave 2).
It parses the Life Orchestrator repo **by source type** and emits **typed record-envelope artifacts**
conforming to `core-docs/MEMORY_CONTRACT.md` section 1, so the catalog (`artifact.search` #36 0.2) ingests
them as **first-class records, not chunks**. No model, no network, no DB writes -- it EMITS artifacts; #36
owns storage.

## What it does

- **Inventory** -- walks ALLOWLISTED roots (default `modules/` + `core-docs/`) in deterministic sorted order,
  content-hashes each file, classifies by source type, applies TESTED privacy exclusions (`.git`, `runtime`,
  venvs, model files, DBs, binaries, media), and **surfaces parser failures** (never silently omits).
- **Type-aware parsers** (deterministic): Markdown heading/section hierarchy (fence-aware breadcrumbs);
  PowerShell `.ps1`/`.psm1` function/class defs + `Import-Module`/`using`/dot-source imports (regex); Python
  `.py` def/class symbols + imports (stdlib `ast`); `skill.json` manifests; JSON/config structure.
- **Relationships** -- file->symbol (defines), imports/dependencies, file->module, test<->module, schema
  producer/consumer -- emitted as first-class `relationship` records plus `parent_edges`/`child_edges`.
- **Structural summaries** (deterministic, NO LLM) -- per-file outline, per-folder index, Markdown sections.
- **Provenance + validation** -- every record carries content_hash + byte span + parser/extractor
  fingerprints + `schema_version`; an s1 **validator** checks required fields, content-derived id integrity,
  span-or-derivation_refs, and edge-endpoint integrity.

`record_kinds`: `symbol` | `entity` | `relationship` | `skill` | `summary`.

## Invocation

```powershell
# index a single root
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Root .\fixtures\repo -Namespace fixture

# index the real repo slice under a per-root file budget
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Roots ..\..\modules,..\..\core-docs -FileBudget 200

# generic form
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -InputsJson '{"op":"index","root":"fixtures/repo","namespace":"fixture"}'

# re-validate an emitted records artifact against MEMORY_CONTRACT s1
pwsh -NoProfile -File .\Invoke-RepoIntel.ps1 -Op validate -RecordsPath .\runtime\artifacts\<id>\records.jsonl
```

Params: `-Op index|validate` (default index) · `-Root <dir>` / `-Roots <dir[,dir...]>` · `-Namespace` ·
`-FileBudget <int>` · `-ExcludeDirs` / `-ExcludeGlobs` / `-IncludeGlobs` · `-RecordsPath` (validate) ·
`-PythonPath` / `-WorkerPath` · `-InputsJson` · `-ArtifactRoot` / `-InvocationId`.

## Outputs

One `lifeorch.skill.result/0.1` envelope on stdout (`result` = counts, `record_kinds`, `records_digest`,
`parse_failures`, `validation`, `edge_summary`, `ingest_run_id`). Artifacts under
`runtime/artifacts/<invocation_id>/`:

- **`records.jsonl`** -- one canonical MEMORY_CONTRACT s1 record per line (deterministic order). **The primary
  artifact + the `ingest_records` payload.**
- `records.json` -- the same records as a canonical array.
- `ingest_records.json` -- the #36 0.2 `ingest_records` drop-in (`{schema,namespace,created_by_ingest_run,record_count,records[]}`).
- `index_manifest.json` -- counts by kind + `records_digest` + fingerprints + validation.
- `inventory.json` -- path / source_type / size / content_hash per file.
- `parse_failures.json` · `summary.md`.

## Determinism

All ids are content+path derived; `created_by_ingest_run` is content-derived (never wall-clock); canonical
artifacts contain no absolute paths / timestamps / random ids. **Identical corpus content -> byte-identical
artifacts across runs and machines** (double-run byte-identity is a gate). Spans are BYTE offsets over raw
file bytes (EOL-faithful).

## Contract + tests

Builds to `core-docs/MEMORY_CONTRACT.md` s1 (see `SCHEMA_NOTES.md` for every interpretation) and
`core-docs/SKILL_CONTRACT.md` v0.2. Tests: `tests/Invoke-RepoIntelTests.ps1` (the real entrypoint ->
real worker; the cloud pre-ship gate AND the `-Live` executor gate) and `tests/test_repo_intel.py` (the
off-machine stdlib determinism/validator harness). CPU-only, no orphaned processes, not a review-queue
producer.

## Non-goals (NOT built)

AST call-graph / full reference resolution, LLM summaries, embeddings, the catalog DB (#36), episode/failure
schema (#39), the context compiler, any UI, git-history parsing.
