# Example invocation — review.processor

## Drain the queue with the 3B reviewer (default)

```powershell
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -Tier mid -MaxItems 10
```

Selects up to 10 open items from the repo-root `review_queue.jsonl` (both `model.gateway` and `classify.batch`
producers), adjudicates each one, and writes back `resolution` + `status` in place (plus an append-only
`review_resolved.jsonl`). Items the reviewer is not confident about become `escalated` for the frontier. See
`example-result.json` for the shape.

## Preview only (writes nothing)

```powershell
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -DryRun
```

Reports exactly which items *would* be resolved or escalated, without touching the queue or the log.

## Only a specific producer / reason

```powershell
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -InputsJson '{
  "tier": "mid",
  "flagged_by": "classify.batch",
  "reason": "uncategorized",
  "max_items": 20
}'
```

## The 27B strong reviewer (tuning the partial GPU offload)

```powershell
# ~16 GB Q4 > 11 GB VRAM -> partial offload. gpu_layers 32 is the tuned default; a COLD load reads ~16 GB
# (~90s) so raise the load timeout for the strong tier.
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -InputsJson '{
  "tier": "strong",
  "gpu_layers": 32,
  "load_timeout_s": 300,
  "max_items": 3
}'
```

## Adjudicate specific ids, to a custom queue + log

```powershell
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -InputsJson '{
  "queue_path": "C:\\path\\to\\review_queue.jsonl",
  "resolution_log_path": "C:\\path\\to\\review_resolved.jsonl",
  "ids": ["rq-1a2b3c4d-r1", "rq-1a2b3c4d-r2"],
  "tier": "mid"
}'
```

## Through the Module 1 wrapper

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
  -InputsJson '{"tier":"mid","max_items":5}'
```

## Through the executor

Submit a task package whose `task.ps1` runs the entrypoint (or the wrapper), reading the JSON envelope from
the completed task's `stdout.txt`. The regression harness `tests/Invoke-ReviewProcessorTests.ps1` is submitted
exactly this way.
