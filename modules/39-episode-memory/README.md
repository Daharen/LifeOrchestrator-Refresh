# episode.record (Module 39) -- Episode + Failure Memory Recorder

Wave 2 PRODUCER lane of the Collective Agent memory substrate (D-0080/D-0083; directive 5.3/5.4/10). A NEW
module that DEFINES the **episode** and **failure** record schemas as `MEMORY_CONTRACT` s1 record+provenance
envelopes and ships a DETERMINISTIC RECORDER that turns a run TRACE into a COMPLETE episode record (+
`episode_stage` children) -- even when the run FAILED -- plus a deterministic failure-signature retrieval
SEAM and an s1 validator. CPU-only, no model, no network, `parallel_safe`.

It PRODUCES conforming s1 records; the orchestrator feeds a real episode + failure record into
`artifact.search` #36 0.2 `ingest_records` at fold (D-0077). It does NOT write the catalog DB (#36 owns
storage), auto-capture into `agent.local` #21, mine failures, embed, compile context, or build UI.

## Layout

```
skill.json                 the manifest (contract v0.2, skill 0.1.0)
Invoke-EpisodeRecord.ps1   thin pwsh contract wrapper (dispatches -Op to the worker, builds the envelope)
episode_record.py          the deterministic stdlib-only worker (all schema/recorder/seam/validator logic)
SCHEMA_NOTES.md            EVERY schema/interface interpretation (the D-0077 fold depends on it)
WORK_ORDER.md              scope + acceptance
tests/Invoke-EpisodeRecordTests.ps1   dual-mode regression suite (same harness cloud + -Live)
tests/fixtures/            trace-success.json, trace-failure.json, failure-corpus.json,
                           task-context-queries.json, ingest_records-fixture.schema.json
examples/                  example invocation + result
```

## Operations

Invoke via `pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op <op> <inputs>` (or generically via
`-InputsJson '<json>'` whose keys include `op`). Every invocation returns one `lifeorch.skill.result/0.1`
envelope on stdout and writes canonical artifacts to `runtime/artifacts/<invocation_id>/`.

- **`record`** `-Trace <run_trace.json|inline> [-EmitFailure bool] [-Namespace ns]` -> `episode.json`,
  `episode_stages.json`, `failure.json` (when the run failed and a failure descriptor is present),
  `records.json` (the ingest_records bundle), `validation.json`. A FAILED/TRUNCATED trace still yields a
  COMPLETE episode.
- **`build-failure`** `-Failures <list|path>` (or `-Failure <one|path>`) `[-Namespace ns]` -> `failures.json`,
  `records.json`, `validation.json`. Builds curated failure records (deterministic id + failure_signature +
  match_keys) -- e.g. to author a failure corpus.
- **`search-failures`** `-TaskContext <query|path> -Corpus <records-or-descriptors|path> [-K n]` -> `search.json`.
  The retrieval SEAM: failures ranked by task-conditioned facet overlap; unrelated failures never surface.
- **`validate`** `-Records <list|bundle|path>` -> `validation.json`. Validates records against the s1
  envelope, INCLUDING provenance recomputation of `content_hash` (a tampered record is rejected).

## Examples

```powershell
# record a successful run trace into an episode + stages
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op record -Trace .\tests\fixtures\trace-success.json

# record a FAILED/truncated trace -> a complete episode + a candidate failure record
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op record -Trace .\tests\fixtures\trace-failure.json

# build a failure corpus, then retrieve by task context
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op build-failure -Failures .\tests\fixtures\failure-corpus.json -Namespace life-orchestrator
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op search-failures -TaskContext .\tc.json -Corpus .\tests\fixtures\failure-corpus.json
```

## Determinism

Every id/hash is a pure function of the fixed input + the recorder fingerprints (no wall-clock/uuid/abs-path
feeds any canonical byte). Canonical artifacts are integer-only, UTF-8 no BOM, sorted keys, and
byte-identical on a re-run cross-machine. The `records_digest` (sha256 over sorted per-record lines) is the
cross-env pin; the skill-result envelope carries the volatile diagnostics. See `SCHEMA_NOTES.md`.

## Tests

```
pwsh -NoProfile -File .\tests\Invoke-EpisodeRecordTests.ps1        # cloud/off-machine (pre-ship gate)
pwsh -NoProfile -File .\tests\Invoke-EpisodeRecordTests.ps1 -Live  # on the Windows executor
```

Both run the SAME assertions (a real-skill gate, not a mock): static gates (AST/ASCII/py_compile), manifest
+ envelope contract validation, the recorder on a success AND a failed/truncated trace, s1 validation with
provenance recomputation (a tampered record is rejected), the failure-signature seam (right failure on top,
unrelated failures excluded, a zero-match negative), pinned canonical shas + double-run byte-identity,
fail-closed error envelopes, and the Module 1 wrapper.

## Requirements

`pwsh >= 7.4`, `python >= 3.8` (stdlib only). CPU-only; no model, no GPU, no network.
