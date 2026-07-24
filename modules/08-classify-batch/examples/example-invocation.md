# Example invocation — classify.batch

## Classify a batch into a closed label set (direct)

```powershell
pwsh -NoProfile -File .\Invoke-ClassifyBatch.ps1 -InputsJson '{
  "mode": "classify",
  "tier": "weak",
  "labels": ["animal", "vehicle", "food"],
  "items": [
    { "id": "a", "text": "a golden retriever puppy playing in the yard" },
    { "id": "b", "text": "a red pickup truck on the highway" },
    { "id": "c", "text": "a steaming bowl of ramen noodles" }
  ]
}'
```

Each item is routed to exactly one of `animal | vehicle | food`; the result carries a `groups` map
(`label -> [ids]`) for the "sorting" view. Items below the confidence threshold (default 0.5) are appended to
`review_queue.jsonl`. See `example-result.json` for the shape.

## Multi-label (comma list, or NONE)

```powershell
pwsh -NoProfile -File .\Invoke-ClassifyBatch.ps1 -InputsJson '{
  "mode": "multilabel",
  "tier": "weak",
  "labels": [
    { "name": "urgent", "description": "needs action today" },
    { "name": "billing", "description": "about payments or invoices" },
    { "name": "bug", "description": "reports something broken" }
  ],
  "items": [ { "id": "t1", "text": "The invoice page crashes when I click pay — need this fixed today." } ]
}'
```

## Extract named fields into JSON

```powershell
pwsh -NoProfile -File .\Invoke-ClassifyBatch.ps1 -InputsJson '{
  "mode": "extract",
  "tier": "weak",
  "fields": [
    { "name": "vendor",  "description": "the company billed from" },
    { "name": "amount",  "description": "total amount, digits only" }
  ],
  "items": [ { "id": "r1", "text": "Acme Corp — receipt total $42.50, paid by card." } ]
}'
```

## From a file, through the Module 1 wrapper

```powershell
# items.jsonl: one {"id":...,"text":...} per line
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
  -InputsJson '{"mode":"classify","tier":"weak","labels":["animal","vehicle","food"],"items_path":"items.jsonl"}'
```

## Through the executor

Submit a task package whose `task.ps1` runs the entrypoint (or the wrapper), reading the JSON envelope from
the completed task's `stdout.txt`. The regression harness `tests/Invoke-ClassifyBatchTests.ps1` is submitted
exactly this way.
