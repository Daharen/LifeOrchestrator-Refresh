# model.gateway — Local Model Gateway (Module 7)

A common interface for local and frontier agents to **run a local model** on this machine without knowing
the engine. The MVP runs local **LLMs** (GGUF text models) through the built llama.cpp **`llama-server`**,
chosen from a declarative registry by id or tier. It is the first **stochastic/mixed** skill: it records
full `model_provenance` and a `confidence`, and flags low-confidence results to the review queue.

## What it does (MVP)

- Resolves a requested model from `models.json` by **`-Model <id>`**, a **`-Tier`** alias
  (`tiny|weak|mid|strong`), or the registry default.
- Starts one isolated `llama-server` on a free loopback port → waits for `/health` → `POST
  /v1/chat/completions` → parses the OpenAI-shape response → **always stops the server**.
- Returns a contract-valid `lifeorch.skill.result/0.1` envelope with the completion, token counts, timings,
  `finish_reason`, `model_provenance[]`, and a `confidence`.

Only **wired LLMs** execute. STT / TTS / embedding models are **declared** in the registry (staged and
ready) but return a structured `model_not_wired` error until their own modules wire them (STT → 11,
TTS → 12, embeddings → 23).

## Invocation

Direct:

```
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Tier weak -Prompt "Name three primary colors." -MaxTokens 64
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -Model llm.weak.qwen2p5-0p5b -System "You are terse." -Prompt "Ping?" -MaxTokens 16 -Seed 42
```

Via `-InputsJson` (supports a full `messages` array):

```
pwsh -NoProfile -File .\Invoke-ModelGateway.ps1 -InputsJson '{"tier":"weak","messages":[{"role":"system","content":"You label text."},{"role":"user","content":"Category of: invoice #42"}],"max_tokens":8,"temperature":0}'
```

Through the Module 1 wrapper or the executor: same as any skill (see `CURRENT_STATE.md`).

## Selecting / swapping models

Model selection is **config, not code**. `models.json` holds:

- `tiers.llm` — alias → model_id (`tiny`→0.5B, `weak`→1.5B, `mid`→3B, `strong`→27B).
- `defaults.llm` — the model used when neither `-Model` nor `-Tier` is given.
- `models[]` — every declared model with `path`, `engine`, `wired`, `context`, `gpu_layers`, params.

To make a tier use a different/stronger model, edit one line in `tiers`/`defaults`. To add a model, add a
`models[]` entry. Callers never change.

## Confidence semantics (read this)

`confidence` here is **generation completeness, not semantic correctness**:

- `finish_reason == "stop"` (natural end-of-turn) → **0.7**
- `finish_reason == "length"` (hit `max_tokens`, likely truncated) → **0.4** + warning
- empty output → status `partial`, **0.1** + warning

Below **0.5** the skill appends a `lifeorch.review.item/0.1` to `review_queue.jsonl` (repo root, or
`-ReviewQueuePath`). A logprob/self-consistency **semantic** confidence is a documented follow-on
(see `REVIEW_QUEUE.md`). The real signal for consumers is in `model_provenance[]` (finish_reason, token
counts, timings).

## GPU lease (res.lease #29)

The gateway holds the shared **`gpu`** lease around the `llama-server` run so multiple instances never drive the
single GPU at once (every model module is `parallel_safe:false`). It **acquires the lease before starting the
server and releases it after teardown**, by shelling out to `modules/29-resource-lease/Invoke-ResLease.ps1`
(same atomic primitive + same shared lease dir every coordinating process resolves).

`-GpuLease` selects the behaviour, with a **graceful fallback** that never breaks a generation:

- `auto` (default) — non-blocking acquire; if the lease is **contended**, log a warning and **proceed**.
- `wait` — block up to `-GpuLeaseWaitSeconds` for the lease, then proceed if still contended.
- `require` — error (`gpu_lease_unavailable`, retryable) if it cannot acquire.
- `off` — do not touch the lease.

If **res.lease is absent** (or the call fails) the gateway logs and proceeds without arbitration. It only
releases a lease it **freshly acquired** (a same-holder re-attach, `already_held`, is left for the outer owner).
Lease outcome is reported under `result.server.gpu_lease`. Knobs: `-GpuLeaseTtlSeconds`, `-GpuLeaseHolder`
(default `$env:LIFEORCH_INSTANCE` else `model.gateway:<pid>`), `-LeaseDir`, `-ResLeasePath`, `-PwshPath`
(all also settable via `-InputsJson`).

## Warm / persistent server (Governor Phase 2)

By default the gateway starts a **transient** `llama-server` per call and stops it on exit — a fresh cold
load (~1 s for the 0.5B, ~60–90 s for the 9B/27B) every time. **`-Warm`** instead keeps the server
**resident across separate gateway invocations**, recorded in `runtime/warm-server.json` (pid, start-ticks
identity, port, model, ngl/ctx). A later `-Warm` call for the **same** model **reuses** the resident with
no reload (measured **~1 ms warm vs a ~1.1 s cold load** on the 0.5B; the saving scales with model size). A
`-Warm` call for a **different** model — or an unhealthy/foreign resident — **evicts** the old server and
loads the new one, so **at most one** `llama-server` is ever on the GPU.

**Detached launch (why it outlives the job).** On Windows a warm server is launched with
`Win32_Process.Create` (WMI), which parents it to `WmiPrvSE` — **outside** the launching task's Job object
— so it **survives the task that started it** and is reusable by the next, independent invocation. A plain
`Start-Process` child stays in the caller's Job and is killed when that task completes (verified: the
resident died before the next task could reuse it), so warmth would never survive under the executor. The
launching task **returns immediately** after the load + first completion — it never blocks holding the
server (the D-0055/D-0056 executor-wedge lesson). The server stays **PID-tracked and killable**:
`-EvictWarm`, a model-change evict, and the executor's orphan-name sweep all reap it, so a warm server is
**never left orphaned**. (The off-machine/Linux gate keeps the redirected `Start-Process`; CIM
`Win32_Process` is Windows-only.)

**`-EvictWarm`** tears down the resident server and returns immediately (`action=evict_warm`, no
generation) — the clean explicit stop.

**Interaction with the `gpu` lease (the coherent rule).** The `gpu` lease stays **per-call**, *not* held
for the resident's lifetime: **every** gateway call (cold, warm-reuse, or evict) acquires the `gpu` lease
first and only then reuses-or-evicts the single registry-tracked resident. Because whoever holds the lease
is the only one touching the GPU, and they always reconcile with the one resident, **concurrent model runs
stay serialized and at most one server is ever resident** — even though the lease is free *between* calls
while the warm server keeps its VRAM. A warm reuse re-attaches to a caller-held lease via `-GpuLeaseHolder`
(same-holder) rather than contending.

`-Warm` / `-EvictWarm` / `-WarmRegistryPath` are also settable via `-InputsJson` (`warm`, `evict_warm`,
`warm_registry_path`). Default is **off** → the classic per-call spawn/kill is byte-for-byte unchanged.

## Named pool manager (Governor Phase 3 Stage-1, mechanism C — D-0063)

The pool manager extends the one warm server into a **named** manager that keeps **one** model GPU-active and
fast-swaps to a named model on demand. On this box (11 GB VRAM, 64 GB RAM) a probe proved exactly one ~7 GB
model fits at a time and a swap is **GPU-upload-bound (~1.6–4.1 s), not disk-bound** — so the win is *same-model
residency (~1 ms reuse) plus routing that minimises swaps*, not a farm of hot specialists. The native
`llama-server` router, `--slot-save-path`, and any coding specialist are **Stage-2+** and are deliberately not
built here.

**Expanded residency key.** Reuse-vs-swap is decided by an **exact** match of a residency key, not just the
model filename (D-0063): `model_id + model_sha256 + model_size + engine build/path + gpu_layers + context +
no_think + cache_type_k + cache_type_v + flash_attn + parallel(-np) + chat_template(+args) + mmproj_sha256 +
generation_id`. An exact match **reuses** the resident (~1 ms, no reload) and refreshes its keep-resident timer;
**any** change (e.g. a KV type, context, or `no_think` change) is a **real swap** — the resident is terminated
(process-exit **and** VRAM-recovery confirmed via `nvidia-smi`), the requested model is loaded via its registry
engine, `/health` **and** model provenance (`/v1/models`) are confirmed, and a new residency manifest is
published to `runtime/warm-server.json` (`schema lifeorch.model_gateway.warm/0.2`).

**Operations.**

- **`-EnsureResident`** — make the requested model resident under the residency key, then **return without
  generating** (the governor's `Ensure-ResidentModel(model_id, config_key)`). Forces `-Warm`. Returns
  `mode:"ensure_resident"` with a `pool{action(reuse|evict_reload|cold_start), reused, started_new, evicted,
  evict_confirmed, residency_key, residency_key_sha, swap_count, idle_ms_at_entry, load_ms, provenance, vram}`.
- **`-PoolStatus`** — read-only report of the current resident (pid, model, `residency_key_sha`, idle age,
  `swap_count`, health). No lease, no change.
- **`-SweepIdle`** — evict the resident **iff** it is idle beyond **`-KeepResidentSeconds`** (default **90 s**);
  a higher-priority contender or another module's GPU request calls this to reclaim the card immediately.
  Same-model reuse refreshes the idle timer, so an actively-used resident is never swept.

**Whole-task GPU lease.** A residency check/change is performed **under the `gpu` lease held across the whole
operation** — a per-call lease would let another task swap the model between two calls. The governor acquires
the lease **once for the whole ramped task** with a stable `-GpuLeaseHolder`; the gateway detects that
(`already_held`) and **never releases a caller-held lease** (it only releases one it freshly acquired). So even
across many calls in a task, at most one `llama-server` is ever GPU-resident.

**Swap-minimising policy.** Selection is by **task affinity / the governor's model-affine epochs**, not LRU:
M0/M1 reuse the same 3B; an escalation does **one** 3B→9B switch and stays on 9B until the task ends (no
intra-task downshift); default **max one swap per task**; LRU is only a tie-breaker. The gateway records
`swap_count` per resident lineage so the governor can observe swap-minimisation.

**Same-model prefix reuse (Stage-1).** A pool/warm launch pins **one slot** (`--parallel 1`) and the completion
request sends an explicit **`-IdSlot`**, so a same-model call reuses the cached prompt prefix (normal prompt
caching). **`-ClearSlot`** erases the slot at a session boundary. Persistent `--slot-save-path` across an
eviction is **Stage-2**.

All pool switches are also settable via `-InputsJson` (`ensure_resident`, `pool_status`, `sweep_idle`,
`cache_type_k`, `cache_type_v`, `flash_attn`, `parallel`, `id_slot`, `clear_slot`, `keep_resident_s`,
`generation`). Default is **off** → the classic per-call and D-0057 warm paths are byte-for-byte unchanged (a
non-warm result has no `server.warm.pool` block).

## Result shape

`result = { model, engine, mode, selected_from, request{messages,sampling}, output{role,text},
generation{finish_reason, prompt_tokens, completion_tokens, total_tokens, timings},
server{port, health_ms, gpu_layers, context, gpu_lease{mode, acquired, owned, lease_id, held_by, released},
warm{enabled, reused, started_new, evicted, load_ms, registry_path}} }` (a `-EvictWarm` call instead returns
`result = { action:"evict_warm", warm{registry_path, had_resident, was_alive, identity_ok, evicted, resident_pid} }`).

Artifacts (under `runtime/artifacts/<invocation_id>/`): `output.txt` (raw completion), `exchange.json`
(request + response), `result.json` (the envelope), `stderr.txt`, plus `server.out.log`/`server.err.log`.

## Engine + models (portable copies)

- Engine: llama.cpp **`llama-server`** (CUDA build b8661), staged at
  `…\LifeOrchestrator-Refresh_Large_Data\_pending-model-storage\_engines\llama.cpp\bin\` (verified to run
  standalone; depends on a system CUDA runtime).
- Models: GGUF LLMs staged under `…\_pending-model-storage\llm\`. These are **portable copies** decoupled
  from the original (possibly-obsolete) source folders. See `_pending-model-storage\MIGRATION.md`.

## Limits (MVP)

Synchronous only (no streaming); `parallel_safe:false` (a per-call server binds a port + most of VRAM);
per-call spawn/kill by default, or a single resident server with **`-Warm`** (Governor Phase 2, above); LLM
text only; no routing/auto-selection (Module 24). The 27B
uses **partial** GPU offload (11 GB VRAM) — `gpu_layers` is a conservative starting value; tune it.

See `WORK_ORDER.md` for full scope and `TOOL_MODEL_REGISTRY.md` for the model inventory.
