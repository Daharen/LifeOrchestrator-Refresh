# Work Order: Review Queue Processor (`review.processor`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 9 session, 2026-07-24) · **Roadmap entry:** `MODULE_ROADMAP.md#9`

### Problem being solved
Two producers now append flagged items to `review_queue.jsonl`: `model.gateway` (Module 7, low
generation-completeness) and `classify.batch` (Module 8, low classification confidence). Nothing yet
**drains** that queue. The design (D-0007, `REVIEW_QUEUE.md`) is a two-tier split: weak local models do bulk
work and defer hard cases; a **stronger** local model adjudicates only the flagged items, one at a time,
seeing just the distilled item — not the whole batch; and the frontier is reserved for what the local
reviewer cannot settle. This module is that stronger-local-model drainer. It closes the loop so the review
queue does not simply grow forever, and it keeps escalation cheap: the reviewer reads one item + its source
fragment + the weak producer's result, and writes back a `resolution` + `status`, escalating to the frontier
only when it is not confident.

### Immediate practical use
This week: after a `classify.batch` or `model.gateway` run leaves low-confidence items in
`review_queue.jsonl`, an agent (or a scheduled background job) runs `review.processor` to adjudicate a bounded
number of open items with a stronger local model (default `-Tier mid` = Qwen2.5-3B; `-Tier strong` = 27B for
the hardest). Each item comes back `resolved` (with the reviewer's decision) or `escalated` (marked for the
frontier). It is meant to run **slowly in the background**, draining a few items per pass, so the frontier
only ever sees the residue the local reviewer could not settle.

### Explicit scope (in)
- **Read + select open items.** Load `review_queue.jsonl` (`-QueuePath`, default repo-root). Parse one JSON
  object per line. Select items with `status == "open"` (skip `in_review`/`resolved`/`escalated`), bounded by
  `-MaxItems` (default 25) so a pass drains slowly. Optional filters: `-FlaggedBy`
  (`model.gateway`|`classify.batch`), `-Reason`, `-Ids` (explicit id list). **Handle both `flagged_by`
  producers.** A missing queue file, or a queue with no open items, is a normal `status:"ok"` empty result —
  NOT an error. Malformed lines are skipped for selection and **preserved verbatim** on write-back.
- **Single-item adjudication (the core constraint).** For each selected item, the reviewer consumes **only**:
  (1) the item's own fields (`reason`, `requested`, `confidence`, `flagged_by`), (2) the `weak_result` (what
  the weak producer decided), and (3) a **bounded fragment resolved from `source_ref`** — never the whole
  batch/collection (D-0007, `REVIEW_QUEUE.md`). One gateway call per item, `-Tier mid` default, temp 0, fixed
  seed. It builds a `requested`-aware reviewer prompt (`adjudicate_category` → pick the correct label(s) from
  the closed set; `verify_extraction` → correct the fields; `review_generation_quality` → accept / regenerate),
  and parses a small JSON verdict from the model.
- **`source_ref` resolver (best-effort, bounded).** Parse `artifact://<path>#<fragment>` (strip
  `artifact://`/`file://`; split the last `#`). For `classify.batch` (`…/classified.json#<item_id>`): read the
  file, return `{mode, labels|fields, item}` for that one id (this recovers the closed label set the
  `weak_result` lacks). For `model.gateway` (`…/exchange.json`): return a bounded `{request_preview,
  output_preview, finish_reason}`. If the file is missing/unreadable/off-line, `source_fragment_resolved:false`
  and the reviewer proceeds from `weak_result` alone. Cap the fragment (~1500 chars) so escalation stays cheap.
- **Write resolutions without rewriting history (update-in-place for status + append-only log).** Only a
  reviewer sets `resolution`/`status` (`REVIEW_QUEUE.md`). Mechanism:
  - **Update-in-place** the live queue: re-read the file immediately before writing, replace only the lines we
    adjudicated whose `status` is still `open` with the **same object plus** an updated `status`
    (`resolved`|`escalated`), a filled `resolution` (`{by, decision, at_utc, note, …}`), and `escalated_to`.
    **All original flagging fields are preserved unchanged** (`schema, id, created_at_utc, flagged_by, reason,
    confidence, source_ref, weak_result, requested`) — that is what "never rewrite history in place" protects.
    Every other line (including producer lines appended during our model calls, and unparseable lines) passes
    through **verbatim**. Write to a temp file, then atomic replace (`[System.IO.File]::Move(tmp,dst,$true)`),
    with a small IO retry (the executor's known file-lock class).
  - **Append-only resolution log** `review_resolved.jsonl` (next to the queue): one
    `lifeorch.review.resolution/0.1` per adjudication `{id, at_utc, by, prior_status, verdict, decision,
    new_status, escalated_to, reviewer_confidence, note}` — an immutable audit trail so history survives even
    though the live queue mutates status. (Together this answers the append-vs-update question: **update the
    live status in place so re-runs don't reprocess and the queue stays small; append history separately.**)
- **Escalation path (status transition, not an API call).** When the local reviewer is not confident
  (reviewer confidence `< -EscalateThreshold`, default 0.5), or the model explicitly defers, or its output is
  unparseable, set `status:"escalated"`, `escalated_to:"frontier"`, and record what it could determine in
  `resolution`. `review.processor` does **not** itself call a frontier model — draining `escalated` items is
  the frontier agent's job (this Cowork session, or a future `route.tasks`, Module 24). Confident adjudications
  become `status:"resolved"`.
- **`-DryRun`.** Adjudicate and report exactly what WOULD change, but write **nothing** back (no queue rewrite,
  no resolution-log append). Mirrors `uia.actor`'s dry-run posture for a side-effecting skill.
- **Suppress the gateway's own review writes.** Like `classify.batch`, point the child gateway's
  `-ReviewQueuePath` at an in-artifact `_gateway_review_suppressed.jsonl` so adjudicating the queue never
  **grows** it with meta-items about the reviewer's own generations.
- **Provenance + confidence + artifacts.** Envelope `confidence` = mean reviewer confidence over adjudicated
  items; `model_provenance[]` = one aggregate entry (calls, summed tokens, total runtime) for the reviewer
  model. Artifacts `review.json` (full payload), `review.md` (human table), plus `result.json` + `stderr.txt`,
  under `runtime/artifacts/<invocation_id>/`; nested gateway child artifacts under `gateway/`.

### Non-goals (out — do NOT build)
- **Calling a frontier model / auto-escalation over a network.** Escalation is a queue status transition; the
  frontier drains `escalated` items separately. No frontier connector here (that is routing, Module 24).
- **Re-running whole batches or re-invoking the original producer.** One flagged item = one adjudication.
  Never reclassify the whole `classify.batch` set or re-run a whole `model.gateway` generation sweep.
- **Compaction / archival of resolved items.** `REVIEW_QUEUE.md` notes resolved items "may be compacted to an
  archive later" — that is a separate, opt-in maintenance pass, not the MVP drainer. (Documented follow-on.)
- **A warm/persistent gateway worker or intra-batch prompting.** One gateway call per item (D-0002/D-0016);
  the reviewer runs slowly by design. Throughput hardening is the same documented follow-on as Module 8.
- **Semantic / calibrated reviewer confidence.** Heuristic (structural: valid JSON + in-set corrected answer +
  generation completeness) only, per the stochastic-then-harden doctrine.
- **Reimplementing inference / talking to `llama-server` directly.** It goes **through** `model.gateway`.
- **Changing the producers or the review-item schema.** `review.processor` only fills `resolution`/`status`/
  `escalated_to`; it never edits a producer's flagging fields.

### Dependencies
- Modules: **7 (`model.gateway`** — the reviewer child it invokes, `-Tier mid`/`strong`), **8 (`classify.batch`**
  — a producer whose items it drains + whose gateway-consumer pattern it reuses), **1 (`skill.bootstrap`** —
  `lib/SkillContract.psm1` validators + `Invoke-Skill.ps1`), **0** (executor). · Tools/models: `pwsh` 7.4.6;
  via the gateway, `llama-server` + a GGUF LLM (default the staged **3B**; **27B** for `strong`). · Data:
  `review_queue.jsonl` (`REVIEW_QUEUE.md`). · Contract features: `confidence`, `model_provenance`,
  `determinism:"mixed"`, artifact envelope.

### Skill contract requirements
- `skill_id` `review.processor` · `name` "Review Queue Processor" · `version` `0.1.0` ·
  `determinism` **`mixed`** (deterministic selection/parse/queue-rewrite; stochastic reviewer output) ·
  `parallel_safe` **`false`** (drives the gateway → GPU/port contention, and rewrites the shared queue file) ·
  `batch` **`true`** (adjudicates a bounded set of items per pass) · `streaming` `false`.
- `result` shape (object): `{ queue_path, dry_run, tier, reviewer_model, selected_from, escalate_threshold,
  selected_count, resolved_count, escalated_count, error_count, skipped_malformed, open_remaining,
  items[ {id, flagged_by, reason, requested, prior_status, new_status, verdict, decision, reviewer_confidence,
  model_self_confidence, escalated_to, finish_reason, source_fragment_resolved, error} ], resolution_log_path }`.
- `confidence` populated (envelope-level = mean reviewer confidence over adjudicated items; null if none).
  `model_provenance[]` = one aggregate entry. Artifact kinds: `json` (`review.json`), `markdown` (`review.md`),
  plus `result.json` + `stderr.txt`.

### Inputs and outputs
- **Inputs** (named params + `-InputsJson`): `queue_path` (string, default repo-root `review_queue.jsonl`;
  `-ReviewQueuePath` accepted as an alias); `max_items` (int, default 25); `flagged_by`
  (string, optional — `model.gateway`|`classify.batch`); `reason` (string, optional); `ids` (array, optional —
  adjudicate only these); `tier` (string, default `mid`: `tiny|weak|mid|strong`); `model` (string, optional —
  overrides tier); `gpu_layers` (int, optional — passed to the gateway; **the knob to tune the 27B**);
  `max_tokens` (int, default 384); `temperature` (number, default 0.0); `seed` (int, default 42);
  `escalate_threshold` (number, default 0.5); `max_fragment_chars` (int, default 1500); `dry_run` (bool,
  default false); `resolution_log_path` (string, optional — default `review_resolved.jsonl` beside the queue);
  `registry`/`gateway_path`/`pwsh_path` (plumbing). Standard: `-InputsJson`, `-ArtifactRoot`, `-InvocationId`.
- **Outputs:** the `result` object above; artifacts `review.json`, `review.md`, `stderr.txt`, `result.json`
  (+ nested gateway artifacts + `_gateway_review_suppressed.jsonl`).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `review.json` (full payload), `review.md` (human table),
  `result.json` (envelope), `stderr.txt` (diagnostics), `gateway/` (each per-item reviewer gateway call's own
  artifact dir), `_gateway_review_suppressed.jsonl` (the gateway's own suppressed low-confidence writes).

### Proposed implementation
- **Language: PowerShell** (per policy: fastest correct MVP; orchestrates an existing skill; Windows-native;
  mirrors Modules 7/8). `Invoke-ReviewProcessor.ps1`.
- **Reuse the `classify.batch` gateway-consumer skeleton** verbatim where possible: `Invoke-Gateway` child-spawn
  (`& <pwsh> -File <gateway> -Tier <t> -System <sys> -Prompt <text> -MaxTokens <n> -Temperature 0 -Seed <s>
  -ArtifactRoot <invDir>/gateway -ReviewQueuePath <invDir>/_gateway_review_suppressed.jsonl [-GpuLayers <n>]`,
  capture the single stdout envelope, stderr → temp file); `Get-FirstJsonObject` balanced-brace extractor;
  `FATAL_GW_CODES` batch-abort on a first-call config error; aggregate provenance; StrictMode-safe arrays
  (`@()` first; `List` + `.ToArray()`; no `return ,$out`; `${var}` in strings).
- **Reviewer prompt (requested-aware):** system = "You are a senior reviewer. A weaker model's decision was
  flagged as uncertain. Judge THIS ONE ITEM only and respond with ONLY a minified JSON object
  `{verdict, answer, confidence, escalate, rationale}`", where `verdict ∈ confirm|correct|reject|uncertain`
  and `answer` is the corrected label / label array / fields object / quality verdict per `requested`; user =
  the reason, the weak decision, the closed set (if resolved from the fragment), and the item text preview.
- **Reviewer confidence heuristic (documented, NOT calibrated):** valid JSON + verdict present + (for category)
  answer in the closed set + gateway finish `stop` → **0.85**; valid JSON but answer out-of-set or
  `verdict:"uncertain"` → **0.4**; truncation (`finish_reason=length`) caps ≤**0.4**; unparseable → **0.15**.
  `escalate` when reviewer confidence `< escalate_threshold`, OR the model set `escalate:true`, OR parse failed
  → `status:"escalated"`, `escalated_to:"frontier"`; otherwise `status:"resolved"`. The model's self-reported
  `confidence` is recorded separately (`model_self_confidence`) but the structural heuristic drives the status.
- **Robustness:** a per-item gateway failure never mutates that item's queue line — it stays `open`, is counted
  as `error`, and warned (a later pass or the frontier retries). A first-call batch-fatal gateway config error
  (`model_not_found`/`tier_not_found`/…) aborts the whole pass with a structured `error{code,message,retryable}`.
  Only the JSON envelope to stdout; diagnostics to stderr. UTF-8 no BOM, LF.

### External tools or models (already present — do NOT reinstall)
- `model.gateway` at `modules/07-model-gateway/Invoke-ModelGateway.ps1` (+ `models.json`, the staged
  `llama-server`, the GGUF LLMs — **3B** for `mid`, **27B** for `strong`). Nothing new to install. `pwsh`
  7.4.6 at the dotnet-tool path.

### Installation steps
- None. This module adds PowerShell + docs; it reuses the gateway and Module 1 libraries in place.

### Tests
- **Direct + through the executor** (`Invoke-ReviewProcessorTests.ps1`, run via the executor for GPU + models;
  a cloud-only `tests/mock-gateway.ps1` validates the selection/parse/adjudication/queue-rewrite/log logic
  off-GPU first):
  - Manifest validates (`Test-SkillManifest`); flags `batch=true parallel_safe=false determinism=mixed`.
  - **Empty / missing queue → `status:"ok"`**, `selected_count 0` (an empty queue is normal, not an error).
  - **Selection + filters:** seed a temp queue with open items from **both** producers + a `resolved` item + a
    malformed line; assert only `open` items are selected, `-MaxItems`/`-FlaggedBy`/`-Ids` bound the set, and
    the malformed line is preserved on write-back.
  - **LIVE adjudication on `-Tier mid`** (or `tiny` for speed): a seeded `adjudicate_category` item (with a
    `classified.json` fragment carrying the closed label set) comes back `resolved` with an in-set `decision`,
    a `reviewer_confidence` in 0..1, `resolution.by` = `review.processor:<model>`, and a
    `review_resolved.jsonl` line; the live queue line for that id now has `status:"resolved"` while its
    original `weak_result`/`reason`/`source_ref` are unchanged.
  - **Escalation:** force it (low `-EscalateThreshold`… actually a HIGH threshold, or an unparseable/uncertain
    verdict) → item becomes `escalated`, `escalated_to:"frontier"`, logged.
  - **`-DryRun`:** nothing is written back — the live queue and the resolution log are byte-identical before
    and after; the result still reports the intended transitions.
  - **`source_ref` resolver:** with a seeded `classified.json`, `source_fragment_resolved:true` and the closed
    set reaches the reviewer; with a bogus path, `source_fragment_resolved:false` and it still adjudicates.
  - **27B (`strong`) tune:** a live `-Tier strong` adjudication with `-GpuLayers` swept to find a value that
    loads within 11 GB VRAM and completes; **record the working value + timing** (REVIEW_QUEUE follow-on).
  - Wrapper (`Invoke-Skill.ps1`) reports manifest+envelope valid; no orphaned `llama-server`.

### MVP acceptance criteria
- [ ] `skill.json` validates (`Test-SkillManifest`); flags `mixed`/`false`/`true`.
- [ ] Missing/empty queue and an all-resolved queue both return a valid `status:"ok"` envelope, `selected 0`.
- [ ] A live pass adjudicates a seeded open item to `resolved` with an in-set `decision`, sets `resolution` +
      `status` **in place** preserving the original flagging fields, and appends one
      `lifeorch.review.resolution/0.1` to `review_resolved.jsonl`.
- [ ] An uncertain/unparseable/low-confidence adjudication yields `status:"escalated"`,
      `escalated_to:"frontier"`.
- [ ] Both `flagged_by` producers (`model.gateway`, `classify.batch`) are handled; `source_ref` resolves
      best-effort and degrades gracefully.
- [ ] `-DryRun` writes nothing (queue + log unchanged); the report still shows intended transitions.
- [ ] The gateway's own review writes are suppressed to the artifact dir; a per-item gateway failure leaves
      that item `open` + `error` and does not abort the pass; a first-call config error aborts with a
      structured `error`.
- [ ] Runs direct, wrapped, and through the executor; artifacts written with sha256; no orphaned `llama-server`.
- [ ] The 27B `gpu_layers` is load-tested and a working value + timing recorded in `REVIEW_QUEUE.md`.

### Manual verification procedure
- Seed `review_queue.jsonl` with two open items (one `flagged_by:"classify.batch"` `adjudicate_category`, one
  `flagged_by:"model.gateway"` `review_generation_quality`); submit `review.processor -Tier mid` through the
  executor; confirm `completed`, read the `stdout.txt` envelope + `review.md`, confirm each item is now
  `resolved` or `escalated` in the queue with a sensible `resolution`, the append-only log has matching lines,
  and no `llama-server` lingers.

### Documentation requirements
- Skill `README.md` (selection + filters, single-item adjudication, the source_ref resolver, update-in-place +
  append-only-log write model and why, reviewer confidence semantics, escalation-as-status-transition, the
  gateway-review suppression, throughput caveat, how to tune the tier / 27B gpu_layers), `skill.json`,
  `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add `review.processor` to `TOOL_MODEL_REGISTRY.md` (status, location, invocation, last test). No new model;
  update the 27B entry / `models.json` `gpu_layers` if tuning finds a better value.

### State updates
- `CURRENT_STATE.md` (active module → MVP complete, tests, next action), `MODULE_ROADMAP.md#9` → MVP complete,
  `DECISION_LOG.md` (new entry: review.processor design — single-item adjudication, update-in-place + append-log
  write model, escalation-as-status-transition, gateway-review suppression, reviewer confidence heuristic),
  `REVIEW_QUEUE.md` (note the first consumer/drainer is wired; record the 27B gpu_layers tuning result).

### Known follow-on work (NOT this session)
- Frontier auto-escalation / a `route.tasks` (Module 24) drain of `escalated` items.
- Compaction / archival of `resolved` items to keep the live queue small.
- A warm/persistent gateway worker (removes per-item model-load cost; shared with Module 8's follow-on).
- Calibrated / semantic reviewer confidence (replace the structural heuristic).
- An `in_review` claim marker + a real lock so multiple drainers/producers can run concurrently (today the
  update-in-place re-reads immediately before an atomic write, which covers the single-drainer background case
  but is not a full concurrency protocol).

### STOP conditions
- Scope would exceed the "Explicit scope" list (frontier connector, batch re-run, compaction, warm worker) →
  stop, write it to the roadmap.
- The gateway cannot be invoked (missing/failing) and fixing it is non-trivial → stop, report (separate module).
- The contract lacks something this module needs → stop, propose the contract change, do not freelance it.
- MVP acceptance met → **stop; do not start Module 10.**
