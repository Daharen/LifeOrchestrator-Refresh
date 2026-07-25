# logic.escalator -- example invocations

## Classify a batch through the full ladder (tiny -> weak -> mid -> strong)

```powershell
pwsh -NoProfile -File .\Invoke-LogicEscalator.ps1 -InputsJson '{
  "kind": "classify",
  "labels": ["animal","vehicle","food","plant","instrument"],
  "tiers": ["tiny","weak","mid","strong"],
  "samples": 1,
  "tasks": [
    { "id": "a", "text": "a golden retriever puppy playing fetch" },
    { "id": "b", "text": "a Jaguar F-Type roaring down the motorway" }
  ]
}'
```

Task `a` is easy: the tiny tier answers `animal`, the weak tier judges and accepts -> **accepted at tiny**.
Task `b` is a trap ("Jaguar" looks like an animal): the tiny tier likely answers `animal` (in-set but wrong);
a higher tier rejects it and produces `vehicle`, which the next tier accepts -> **accepted at weak/mid**. The
result carries, per task, `accepted_tier`, `answer`, `confidence`, `needs_frontier`, and the full `ladder` trace.

## Named parameters + self-consistency (K=3)

```powershell
pwsh -NoProfile -File .\Invoke-LogicEscalator.ps1 `
  -Kind classify -Labels 'animal','vehicle','food' `
  -Tiers 'tiny','weak','mid' -Samples 3 -AcceptConsistency 1.0 `
  -Tasks '[{"id":"x","text":"a steaming bowl of ramen"}]'
```

With `-Samples 3`, each tier answers three times; if all three agree AND the answer passes the deterministic
gate (in-set), the ladder **short-circuits and accepts at that tier with no judge call** -- the cost saver for
easy, self-consistent tasks.

## Field extraction (schema + source-grounding gate)

```powershell
pwsh -NoProfile -File .\Invoke-LogicEscalator.ps1 -InputsJson '{
  "kind": "extract",
  "fields": ["name","email"],
  "tiers": ["tiny","weak","mid"],
  "tasks": [ { "id": "c1", "text": "Contact: Dana Lee, dana.lee@example.com" } ]
}'
```

The deterministic gate here is JSON-schema validity (parseable + all required fields present) plus a
source-grounding check (each extracted value must appear in the source text).

## Calibration (the empirical experiment, via the executor)

```powershell
pwsh -NoProfile -File .\tests\Invoke-EscalatorCalibration.ps1 `
  -Tiers 'tiny','weak','mid','strong' -Samples 1 -LoadTimeoutSec 300 `
  -OutDir .\runtime\calibration\run1
```

Runs `eval/classify-eval.json` through the ladder live and writes `escalation-calibration.{json,md}` with the
resolve-level distribution, accuracy (+ baselines), false-approval rate, and cost.

## Notes

- **Not a review-queue producer.** The child gateway's own review writes are suppressed to an in-artifact
  file; per-task `needs_frontier` is a status signal only. The canonical `review_queue.jsonl` is never written.
- `-InputsJson` and named parameters both work (a named param wins where explicitly set).
- `parallel_safe:false` -- it drives `model.gateway` (a GPU/loopback-port). Reserve `strong` (27B) for the
  hardest items and pass `-LoadTimeoutSec 300` for its cold load.
