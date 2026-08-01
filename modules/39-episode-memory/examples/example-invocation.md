# episode.record -- example invocations (0.1.1)

## record: a run trace -> an episode (per-stage detail folded in-body)

```powershell
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op record -Trace .\tests\fixtures\trace-success.json
```

Or generically (any conforming caller / the executor / an orchestrator skill):

```powershell
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -InputsJson '{"op":"record","trace":"tests/fixtures/trace-success.json"}'
```

Emits `episode.json` (one `episode` s1 record whose `body.stage_sequence` carries the FULL per-stage
detail), `episode_stages.json` (a HUMAN/DEBUG view of that in-body stage detail -- NOT a record, NOT
ingested), `records.json` (the `ingest_records` bundle for #36 0.2 = `episode` + `failure` ONLY; v0.1.1
retired `episode_stage` as a record_kind), and `validation.json`. A FAILED/truncated trace
(`tests/fixtures/trace-failure.json`) still yields a COMPLETE episode plus a candidate `failure.json`.

The stdout is the `lifeorch.skill.result/0.1` envelope in `example-result.json`.

## build-failure: author curated failure records

```powershell
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op build-failure -Failures .\tests\fixtures\failure-corpus.json -Namespace life-orchestrator
```

## search-failures: the retrieval seam (task context -> ranked failures)

```powershell
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op search-failures `
  -TaskContext .\my-task-context.json -Corpus .\tests\fixtures\failure-corpus.json
```

where `my-task-context.json` is a `lifeorch.task_context/0.1` query, e.g.:

```json
{
  "schema": "lifeorch.task_context/0.1",
  "components": ["media.decompose"],
  "planned_operations": ["resolve ffprobe path", "probe a video container"],
  "keywords": ["ffprobe", "shim", "python", "scripts", "shadow"]
}
```

surfaces the `media.decompose` ffprobe failure on top; unrelated failures (zero overlap) never appear.

## validate: check records against the s1 envelope (incl. provenance recomputation)

```powershell
pwsh -NoProfile -File .\Invoke-EpisodeRecord.ps1 -Op validate -Records .\records.json
```
