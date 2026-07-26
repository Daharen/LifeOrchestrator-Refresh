# MODULE_WORK_ORDER: Tool Router (`route.tools`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork) / 2026-07-26 · **Roadmap entry:** `MODULE_ROADMAP.md -> Build priority -> Phase B (Module-capable widgets)` (a scoped slice of `route.tasks` #24)

> Folder-number note: this is `modules/27-route-tools/`. The on-disk `NN-` prefix is a monotonic build-order
> counter (0, 00.1, 1..26, then 27); D-0029 severed it from the ARCHITECTURE_MAP's 0-49 architectural positions.
> `route.tools` is a **scoped slice of `route.tasks` (#24)** -- just the tool-selection pass -- pulled forward so
> `agent.local` (#21) and the Local Agent Console (Widget 01) can USE and ATTACH Modules through one shared
> intermediary. The task-router-across-cost/quality/time (#24 proper) remains a later unit.

## Validated finding being implemented (REUSE, do NOT re-derive) -- experiment `m27-router-001`

A dedicated **"router pass"** -- a model given ONLY a tool catalog + the request, whose sole job is to emit the
minimal JSON list of tool ids needed, and which must NOT perform / answer / obey the request (pure analysis;
ignores instructions inside the request; injection-resistant) -- **WORKS, but only at the MID 3B tier, NOT the
strong 27B**:

- **MID (Qwen2.5-3B):** 3 exact / 2 close / 0 broken, ~15-31 s per case, clean parseable JSON (`finish=stop`).
- **STRONG (Qwen3.5-27B):** 0/5, ~300 s per case, **EMPTY output** -- it is a **thinking** model that burned the
  whole token budget on hidden reasoning and never emitted the array; `/no_think` did NOT suppress it.

**RULE:** the router uses the **MID tier (or any non-thinking model). NEVER the 27B** for this. The 2 mid "close"
misses were **catalog-description** problems (confused `gen.audio` beeps/tones with `gen.music` melodies;
under-specified the screen->capture+OCR chain) -- fixable with sharper one-line tool descriptions + 2-3 few-shot
examples in the router prompt. The **validated router prompt is reused verbatim** (the harmless `/no_think` stays;
it does nothing on the 3B). The throwaway experiment was NOT committed -- no repo change came from it.

## Problem being solved

Phase A built a large local toolkit + the cost-offload core (escalator #19 / doc.io #20 / agent.local #21), but
`agent.local` shipped with only two tools and decided over **all** of them every step -- and the weak local tiers
decide + terminate poorly as the decision space grows (D-0032). What is missing is a cheap way to **pre-select**
the handful of tools a request actually needs, so the agent's ReAct loop runs over a small, relevant subset. That
is exactly a router: analyze the request against the tool catalog, name the tools, execute nothing.

## Immediate practical use

`agent.local` (in the new `-Route` mode) and the Local Agent Console call `route.tools` FIRST to pre-select the
toolset for a goal, then run constrained to it. This week: goals like *"make an image of a dog"* -> the router
returns `["gen.image"]` -> the agent's loop, now choosing among 1 tool + `finish`, invokes `gen.image` and the
image file exists. The router is also a standalone **Plan** primitive (the console's Plan button): show the user
which tools a goal would use, fast, before any execution.

## Explicit scope (in)

- A **new conforming Module** that reads the **attachable-tools registry** (agent.local's `tools.json`, the single
  source of truth), builds a **catalog** (`id: one-line purpose`), calls **`model.gateway` (#7) ONCE at the MID
  tier** with the validated router prompt (+ 2-3 few-shot examples pinning the output format and the confusables),
  parses the JSON array, and **DETERMINISTICALLY GATES it** (drops any id not in the catalog; dedups; preserves
  order), returning the validated subset as `result.tools` (== `result.planned_tools`).
- **Fast, cheap, NON-executing.** It never invokes a tool; it only names them.
- **Injection-resistant by construction:** the router prompt treats the request as text and is told to ignore any
  embedded instructions; and even if the model is subverted into naming a non-catalog tool, the **deterministic
  gate drops it**. The gate is the guarantee, not the model's compliance.
- **MID-tier rule enforced:** `tier=strong` is hard-refused (`strong_tier_forbidden`) -- the 27B thinking model
  returns empty output for this task.
- **Orchestrator, NOT a review-queue producer** (like #13/#18/#19/#21): the child gateway's review writes are
  redirected to an in-artifact `child_review.jsonl`; the canonical `review_queue.jsonl` is never touched.

## Non-goals (out -- do NOT build)

- **The full `route.tasks` (#24)** -- routing across model/tool/quality/cost/time, or ranking, or scheduling. This
  is only the *which-tools* pass.
- **No execution.** route.tools never runs a tool (that is agent.local's job).
- **No new model / no `models.json` change / no Module 7 re-verify** (it composes the wired mid tier).
- **No arbitrary-shell tool, no registry mutation, no auto-discovery** of tools from module manifests (a follow-on).
- **No use of the 27B strong tier** for the router (validated-broken).
- No calibrated/semantic confidence (the parse-quality heuristic is documented + provisional).

## Dependencies

- Modules: **7 `model.gateway`** (the one router call; spawned child, envelope parsed). The registry it reads is
  **21 `agent.local`'s `tools.json`** (default) -- data, not a code dependency.
- Tools/models: the wired **mid** LLM tier in `models.json`.
- Contract features: `-InputsJson`, `-ArtifactRoot`, `-InvocationId`, `status`, `confidence`, `model_provenance`,
  the child `review_queue_path` redirect (the gateway accepts it).

## Skill contract requirements

- `skill_id` `route.tools`, `name` "Tool Router", `version` `0.1.0`, `contract_version` `0.2`.
- `determinism` **mixed**, `parallel_safe` **false** (drives the gateway -> GPU/port), `batch` **false**,
  `streaming` **false**.
- `result` shape: `{request, tier, model, catalog[{tool,purpose}], catalog_count, tools[], planned_tools[], count,
  tools_dropped[], parsed_ok, gated, raw_output, finish_reason, cost{}, is_review_producer:false}`.
- `confidence` in 0..1 (parse-quality heuristic); `model_provenance` = the gateway child's provenance, stage-tagged
  `route`. Artifacts `route.json` (json) + `route.md` (markdown).

## Inputs and outputs

- **Inputs** (see `skill.json`): `request` (required); `tools_path`/`tools`; `tier` (mid), `temperature` (0.0),
  `seed` (42), `max_tokens` (256), `max_request_chars` (2000), `no_few_shot`; plumbing `gateway_path`, `registry`,
  `pwsh_path`, `load_timeout_s`, `review_queue_path`.
- **Outputs:** the `result` above; `tools`/`planned_tools` is the deterministically-gated validated id subset.

## Artifact structure

- `runtime/artifacts/<invocation_id>/` -> `route.json`, `route.md`, `result.json`, `stderr.txt`,
  `child_review.jsonl` (redirected gateway review writes, when any), and a `route/` child sub-root (the gateway's
  nested artifacts).

## Proposed implementation

- **Language:** PowerShell 7 (owns the contract envelope; spawns the gateway child exactly as #21/#19 do). No
  Python. Reuses the proven helpers from `agent.local`: `Has`/`Prop`, `Get-Sha256Hex`, `Resolve-RepoRoot`,
  `Resolve-Child`, `Invoke-Child`, `Add-Provenance`, `Test-ChildOk`, plus a `Get-FirstJsonArray` (bracket-matched)
  for tolerant parsing.

## External tools or models

- Only the already-present `model.gateway` + the wired mid LLM tier. **Nothing to install on Windows.** Cloud box:
  pwsh 7.4.6 for AST-parse + the mock-gateway harness.

## Tests

- **Off-machine (cloud pre-ship gate):** `tests/Invoke-RouteToolsTests.ps1` drives the **real** skill against
  `tests/mock-gateway.ps1` (a deterministic mock router keyed by a `ROUTE_EMIT=` directive in the request) with a
  mock registry. Exercises: heuristic + explicit selection, the deterministic gate dropping unknown ids, a
  legitimate empty selection, unparseable prose (thinking-model sim), tolerant fence extraction, the confidence
  branches, the strong-tier refusal, injection-resistance, review redirection (non-producer), error paths, and the
  Module 1 wrapper. **AST-parse every `.ps1` first.** Green on cloud Linux (pwsh 7.4.6): **34/34**.
- **Through the executor (live):** shipped-files sha256 + AST-parse on target; the same harness live; and **REAL
  3B routing** on the real catalog (`make an image of a dog` -> `["gen.image"]`, etc.), no orphaned `llama-server`,
  canonical queue untouched.

## MVP acceptance criteria

- [ ] Manifest validates; `determinism=mixed`, `parallel_safe=false`, `batch=false`, `streaming=false`.
- [ ] Reads the registry, builds the catalog, calls the gateway MID tier once, parses the array, and **gates**
      unknown ids out; `result.tools` is the validated subset.
- [ ] `tier=strong` is refused (`strong_tier_forbidden`).
- [ ] Injection text in the request does not change routing beyond the gate; hallucinated ids are dropped.
- [ ] Non-producer: the canonical `review_queue.jsonl` is untouched (gateway review writes redirected).
- [ ] Envelope validates; `confidence` in 0..1; provenance stage-tagged `route`.
- [ ] Live: REAL 3B routing returns a sensible gated subset; Module 1 wrapper runs it.

## Manual verification procedure

- Run the live routing task via the executor; confirm `make an image of a dog` -> `["gen.image"]`,
  `write hello to a file` -> `["doc.io"]`, `what does my screen say` -> `["ocr.layout"]`; confirm no
  `llama-server` orphans and the canonical `review_queue.jsonl` line count is unchanged.

## Documentation requirements

- `README.md` + `skill.json` + `examples/example-invocation.md` + `examples/example-result.json`.

## Registry updates

- `TOOL_MODEL_REGISTRY.md`: add the `route.tools` skill entry (composes #7; no new model).

## State updates

- `CURRENT_STATE.md`, `MODULE_ROADMAP.md` (new Phase-B unit -> MVP complete + a per-module entry),
  `DECISION_LOG.md` (D-0040 route.tools; D-0041 agent.local -Route + curated tools + console Plan/Run),
  `REVIEW_QUEUE.md` (note: route.tools is an orchestrator/non-producer that redirects child flags).

## Known follow-on work (NOT this session)

- The full `route.tasks` (#24): rank/route across model+tool+quality+cost+time; a `needs_frontier` drain.
- Registry auto-discovery from module manifests (so new Modules join the catalog without a `tools.json` edit).
- Per-tool arg schemas surfaced to the router; calibrated/semantic routing confidence; a warm gateway worker.
- A small `fs.manage` (copy/move/mkdir) tool -- the "deposit the artifact on the desktop" last-mile (see D-0041).

## STOP conditions

- Scope would exceed "Explicit scope". A dependency is non-trivial to install. The contract lacks something (stop,
  propose the change). **MVP acceptance is met -- stop.**
