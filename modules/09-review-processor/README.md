# review.processor — Review Queue Processor

The stronger-local-model **drainer** for `review_queue.jsonl`. Two producers append flagged items to the
queue — `model.gateway` (Module 7, low generation-completeness) and `classify.batch` (Module 8, low
classification confidence). `review.processor` is the **first consumer**: it selects open items and, for each
one, feeds a **stronger** local model (default `-Tier mid` = Qwen2.5-3B; `-Tier strong` = 27B) via
`model.gateway`, then writes back a `resolution` + `status` — or **escalates** the item to the frontier when
it is not confident. It is meant to run **slowly in the background**, draining a bounded number of items per
pass, so the frontier only sees what the local reviewer could not settle (D-0007).

Skill contract: `lifeorch.skill.result/0.1`. `determinism: mixed` · `batch: true` · `parallel_safe: false`
(it drives the gateway — port + VRAM — and rewrites the shared queue file). Emits **only** the JSON envelope
to stdout; diagnostics to stderr.

## The core constraint: single-item adjudication

The reviewer never redoes a whole batch. For each flagged item it consumes **only**:

1. the item's own fields (`reason`, `requested`, `confidence`, `flagged_by`),
2. the `weak_result` (what the weak producer decided), and
3. a **bounded fragment** resolved from `source_ref` — not the whole collection.

This is what keeps escalation cheap (`REVIEW_QUEUE.md`). One gateway call per item.

### The `source_ref` resolver (best-effort, bounded)

`source_ref` is a pointer like `artifact://<path>#<fragment>`. The resolver strips the scheme, splits the last
`#`, and reads the file:

- **classify.batch** (`…/classified.json#<item_id>`) → `{mode, labels|fields, item}` for that one id. This
  recovers the **closed label set** the `weak_result` alone lacks, so the reviewer can pick a valid label.
- **model.gateway** (`…/exchange.json`) → a bounded `{request_preview, output_preview, finish_reason}`.

If the file is missing/unreadable/offline, `source_fragment_resolved:false` and the reviewer proceeds from the
`weak_result` alone (with lower structural confidence — it will usually escalate). Fragments are capped at
`-MaxFragmentChars` (default 1500).

## Adjudication and the reviewer verdict

The reviewer prompt is chosen from the item's `requested` value: `adjudicate_category` (classify → pick the
correct single label; multilabel → the correct label set), `verify_extraction` (correct the fields),
`review_generation_quality` (accept / regenerate). The model returns a minified JSON verdict:

```json
{"verdict":"confirm|correct|reject|uncertain","answer":<label|labels|fields|"acceptable|regenerate">,"confidence":0.0-1.0,"escalate":true|false,"rationale":"..."}
```

### Reviewer confidence semantics (read this)

The `reviewer_confidence` is a **documented structural completeness + validity heuristic**, NOT a calibrated
correctness score (same doctrine as the gateway and classify.batch — build the stochastic version first,
harden when it earns it). It combines: valid-JSON verdict, an **in-set** corrected label / valid fields, and
the gateway's generation completeness (a `finish_reason=length` truncation caps it at ≤0.4):

- category (single/multi): valid + in-set + clean stop → **0.85**; in-set but truncated → **0.6**;
  `reject` against a known set → **0.7**; answer out-of-set → **0.4**; `uncertain` → **0.4**; unparseable → **0.15**.
- extraction: valid JSON with ≥1 non-null field + stop → **0.8**; some fields → **0.6**; else **0.4**.
- generation: a clean `acceptable`/`regenerate` verdict → **0.8**; inferred from confirm/reject → **0.7**; else **0.4**.

The model's own `confidence` is recorded separately (`model_self_confidence`) but the **structural** heuristic
drives the decision. An item is **escalated** (`status:"escalated"`, `escalated_to:"frontier"`) when the
reviewer confidence is `< -EscalateThreshold` (default 0.5), the model set `escalate:true`, or its output was
unparseable; otherwise it is **resolved**.

## How resolutions are written (without rewriting history)

Only a reviewer sets `resolution`/`status` (`REVIEW_QUEUE.md`). This skill does two things:

1. **Updates the live queue in place.** It re-reads the file immediately before writing, replaces only the
   lines it adjudicated (whose `status` is still `open`) with the **same object plus** an updated `status`,
   a filled `resolution` `{by, decision, at_utc, note, verdict, reviewer_confidence, …}`, and `escalated_to`.
   **All original flagging fields are preserved** (`schema, id, created_at_utc, flagged_by, reason, confidence,
   source_ref, weak_result, requested`). Every other line — producer lines appended during the model calls,
   already-resolved items, and unparseable lines — passes through **verbatim**. The file is written to a temp
   file and atomically replaced (with a small IO retry for the executor's known file-lock class).
2. **Appends an immutable resolution log** `review_resolved.jsonl` (beside the queue): one
   `lifeorch.review.resolution/0.1` per adjudication.

So the live queue reflects current status (re-runs skip resolved items; the queue stays small) **and** an
append-only history survives. `-DryRun` writes **neither** — it only reports the intended transitions.

## Escalation is a status transition, not a frontier call

`review.processor` never calls a frontier model. Escalating sets `status:"escalated"`,
`escalated_to:"frontier"` and records what the local reviewer could determine. Draining `escalated` items is
the frontier agent's job (this Cowork session, or a future `route.tasks`, Module 24).

## Invocation

```powershell
# adjudicate up to 10 open items with the 3B reviewer
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -Tier mid -MaxItems 10

# preview only (writes nothing), just the classify.batch items
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -FlaggedBy classify.batch -DryRun

# the 27B strong reviewer, tuning the partial GPU offload for 11 GB VRAM
pwsh -NoProfile -File .\Invoke-ReviewProcessor.ps1 -InputsJson '{"tier":"strong","gpu_layers":30,"max_items":3}'
```

Through the Module 1 wrapper: `Invoke-Skill.ps1 -SkillDir . -InputsJson '{...}'`. Through the executor: submit
a task package whose `task.ps1` runs the entrypoint (see the module tests).

Key inputs: `queue_path` (default repo-root; `-ReviewQueuePath` alias) · `max_items` (default 25) ·
`flagged_by` / `reason` / `ids` filters · `tier` (`tiny|weak|mid|strong`, default `mid`) or `model` ·
`gpu_layers` (tune the 27B) · `max_tokens` (384) · `temperature` (0.0) · `seed` (42) · `escalate_threshold`
(0.5) · `max_fragment_chars` (1500) · `dry_run` · `resolution_log_path` · `registry`/`gateway_path`/`pwsh_path`.
See `skill.json`.

## Result

`result` = `{ queue_path, dry_run, tier, reviewer_model, selected_from, escalate_threshold, selected_count,
resolved_count, escalated_count, error_count, skipped_malformed, open_remaining, queue_written, items[],
resolution_log_path, resolution_count }`. Each `items[]` = `{ id, flagged_by, reason, requested, kind,
prior_status, new_status, verdict, decision, reviewer_confidence, model_self_confidence, escalated_to,
finish_reason, source_fragment_resolved, error }`.

Artifacts (`runtime/artifacts/<invocation_id>/`): `review.json` (full payload), `review.md` (human table),
`result.json` (envelope), `stderr.txt`, `gateway/` (each per-item reviewer call's own artifacts), and
`_gateway_review_suppressed.jsonl`.

### Why the gateway's own review writes are suppressed

`model.gateway` appends to the review queue on *its* low generation-completeness confidence. If left alone,
adjudicating the queue would **grow** it with meta-items about the reviewer's own generations. So — exactly
like `classify.batch` — this skill points the child gateway's `-ReviewQueuePath` at a discardable in-artifact
`_gateway_review_suppressed.jsonl` (reported in `diagnostics.gateway_reviews_suppressed_to`).

## Robustness

A per-item gateway failure never mutates that item's queue line — it stays `open`, is counted as `error`, and
warned (a later pass or the frontier retries). A first-call batch-fatal gateway config error
(`model_not_found`/`tier_not_found`/…) aborts the pass with a structured `error{code,message,retryable}`. A
missing or empty queue, or one with no open items, is a normal `status:"ok"` empty result — not an error.

## Throughput caveat & the strong (27B) tier

One gateway call per item, and the gateway (D-0002/D-0016) starts and stops an isolated `llama-server` per
call — so a pass is bounded by per-call model load, and the `strong` (27B) tier is slow with partial GPU
offload. That is acceptable for a background drainer; a warm/persistent gateway worker is the shared follow-on
with Module 8. Use `mid` (3B, full GPU offload) for routine draining and reserve `strong` for the hardest items.

Measured 27B tuning on this machine (RTX 2080 Ti, 11 GB VRAM): `gpu_layers` ∈ {20, 28, 36} all load without
OOM; inference speed rises monotonically (1.43 / 1.67 / 1.93 tok/s). The registry default was raised from the
untested guess `28` to **32** (validated-safe: strictly fewer GPU layers than the `36` that loaded, so it fits
with headroom for desktop display VRAM). The **cold** first load reads ~16 GB from F: (~90 s); warm re-loads
are ~7–9 s (OS file cache). Because a cold 27B load can approach the gateway's default 120 s load timeout,
pass `-LoadTimeoutSec 300` (or `load_timeout_s`) for strong-tier runs; the mid tier loads in ~5 s and needs no
override.

## Non-goals

No frontier connector (escalation is a status transition; routing is Module 24), no batch re-runs, no
compaction/archival of resolved items, no warm worker, no calibrated/semantic reviewer confidence, and it
never talks to `llama-server` directly — always through `model.gateway`.

## Tests

`tests/Invoke-ReviewProcessorTests.ps1` (run through the executor — the live checks need the GPU + staged
models): manifest, missing/empty queue, selection + filters + malformed-line preservation, a live `mid`
adjudication that resolves an item in place (history preserved) + writes the resolution log, an escalation, a
`-DryRun` no-op, the source_ref resolver, the Module 1 wrapper, and no-orphaned-`llama-server`. A live
`strong` (27B) check sweeps `-GpuLayers` to record a value that fits 11 GB VRAM. `tests/mock-gateway.ps1` is a
Linux-only stand-in used to validate the select/parse/adjudicate/rewrite logic off-GPU; it is not used on the
device.
