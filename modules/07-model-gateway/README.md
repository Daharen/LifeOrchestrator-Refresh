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

All pool switches are also settable via `-InputsJson`. Default is **off** → the classic per-call and D-0057 warm
paths are byte-for-byte unchanged (a non-warm result has no `server.warm.pool` block).

## Stage-1.1 hardening (D-0067 — the pool may be enabled by default once this passes)

The frontier red-team (WARM_POOL_DESIGN §10) found Stage-1 was a functional-but-unhardened first cut. Stage-1.1
closes the integrity invariants. The pure core lives in **`lib/PoolManager.psm1`** (no GPU/Windows dependency,
unit-tested off-machine) and is wired into the live path:

- **Fencing (finding 1).** Residency has a **monotonic fence** (the epoch) + a short **renewable TTL**
  (`-FenceTtlSeconds` ~120 s, not 1800) held under a **machine-global lock**; the fence bumps on each launch and
  is stable across reuse. An inference call may carry **`-ExpectGeneration`** (a per-launch nonce) and/or
  **`-ExpectFence`**; a mismatch is **rejected (`generation_mismatch`) before any completion is issued** — no
  wrong-generation call ever lands.
- **GPU-handoff eviction (findings 2/15).** **`-PrepareGpu -RequiredVramMib N`** evicts the resident
  *before* granting the GPU to another consumer (no blind co-load / OOM), then **confirms VRAM recovery to a
  target headroom over an async interval** (WDDM frees lazily). `evict-before-release`, never "release and hope".
- **Crash-atomic state machine + reconcile (finding 3).** The manifest is a durable machine
  `EMPTY→STOPPING→EMPTY_CONFIRMED→STARTING→RESIDENT` written by **atomic replace**; it is a **claim to VERIFY**.
  Every startup runs **`-Reconcile`** (also implicit on any pool op) under the machine-global lock: a crashed
  transition (dead pid / unhealthy / wrong socket owner) is driven to a clean `EMPTY`; a healthy verified
  resident is **kept** (warmth preserved).
- **Verified-generation endpoint (finding 4).** Each launch records a **unique nonce + unique port + pid +
  creation-time + engine-exe hash**, and the **listening socket owner** is verified (Windows `Get-NetTCPConnection`;
  off-Windows `lsof`/`ss`; undeterminable → advisory) **before publishing RESIDENT**. A `/v1/models` alias is not
  proof; an explicit owner mismatch is a hard, non-bypassable failure.
- **Config-hash / generation split (finding 6).** `resident_config_hash` (deterministic, hashes model + engine-exe
  **contents**, never paths, never the nonce or samplers) is split from `instance_generation` (the per-launch
  fencing nonce). `-Generation` no longer poisons the hash — use **`-ForceReload`**.
- **CanServe (findings 7/8/9).** Reuse vs reload is decided by `CanServe(resident, request)`: **exact** on
  semantic identity (model/sha/engine-exe/KV type/flash/template/mmproj/no_think), **`>=`** on capacity
  (context, parallel). A 32K resident serves 16K; a resident 9B serves an M0 request (no downshift to honor a
  floor). Reload only when the resident cannot correctly serve.
- **Dropped from the correctness path (findings 10/11/12).** **LRU** (meaningless at capacity 1) is removed;
  **idle eviction** is a policy op (`-SweepIdle` re-reads under the lock so it cannot race a refreshing request),
  not an autonomous correctness mechanism; **same-model prefix reuse is removed** — the non-bypassable
  *no-cross-task-KV* invariant is enforced by **erase-on-checkout AND check-in** of the single slot.
- **Framing.** The pool is an **optional** layer: **`-BypassPoolManager`** forces the classic cold isolated-server
  path. Integrity invariants (fencing, single-endpoint ownership, verified routing, no cross-task KV, no blind
  co-load) are **non-bypassable**; the pool still ships **default-OFF** until the live fault-injection pass lands.

**Managed ownership (finding 5) — durable form now SHIPPED (see the supervisor section below).** Every launch
is tagged (`managed_by`) so "0 orphaned llama-server" means **0 UNMANAGED** servers and never counts the intended
warm resident; eviction uses a **tree kill** (`taskkill /T`) so llama.cpp children are reaped, and the PID +
creation-time identity guard refuses to kill a **reused** pid (a foreign process). The **per-call** case is covered
by those guards; the **durable** case — a Windows Job Object owning the tree ACROSS separate invocations — is now
delivered by the **persistent gateway supervisor** (`Start-GatewaySupervisor.ps1` + `lib/Supervisor.psm1`), since a
Job Object created by a per-call gateway dies when that process exits.

**Tests.** `tests/Invoke-ModelGatewayPoolCoreTests.ps1` (pure core, 49), `tests/Invoke-ModelGatewayPoolTests.ps1`
(integration, 48), `tests/Invoke-ModelGatewayFaultInjectionTests.ps1` (the §10 fault-injection gate: crash-at-each-
transition + reconcile, forced fence/generation expiry mid-request, stale-idle-vs-fresh-request, PID-reuse guard,
KV isolation, GPU-handoff eviction — 37), `tests/Invoke-ModelGatewaySupervisorCoreTests.ps1` (supervisor protocol
+ attach handshake + state machine + reconcile + Job-Object seam — 46), and
`tests/Invoke-ModelGatewaySupervisorFaultInjectionTests.ps1` (durable reuse across two invocations, generation
rejection, supervisor-crash tree-reap, restart reconcile, GPU handoff — 25), plus warm (23) and the live box base
(42). All run on the cloud gate against the cross-platform mock except base (live GPU).

## Durable gateway supervisor (Stage-1.1 residual (a) — durable finding 5)

**`Start-GatewaySupervisor.ps1` + `lib/Supervisor.psm1`.** A **persistent, detached process** that owns the warm
resident llama-server **across** separate per-call gateway invocations — the last residual gating warm-pool
default-ON. It is the durable form of the per-call tree-kill above: a per-call Job Object dies with its process,
so cross-invocation ownership needs a process that outlives the calls.

- **Windows Job Object (P/Invoke).** On start it creates ONE Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`
  and assigns every llama-server it launches to it (own by **HANDLE**, never by process-name — `pwsh` and the
  executor both show as `dotnet.exe`). If the supervisor dies for any reason, the OS reaps the **whole** server
  tree (0 unmanaged orphans). Off-Windows the Job-Object seam degrades to `supported=false` (never throws) and the
  reap becomes a live-only guarantee; the supervisor records `job_owned` honestly.
- **Detached like D-0057.** The supervisor itself is launched via `Win32_Process.Create` so it ESCAPES the
  launching executor task's job and survives across invocations; the llama-servers are its own children + in its
  Job Object.
- **Control channel = a file-protocol control dir** (`runtime/supervisor/control/req|resp/`), chosen over a named
  pipe / loopback endpoint because it is crash-atomic (tmp+Move), cross-platform testable, and matches the
  executor/res.lease file idioms. A per-call gateway **ATTACHES** with `-UseSupervisor` and asks the running
  supervisor to `ensure_resident` / `status` / `prepare_gpu` / `evict` / `reconcile`; the resident is reused
  (~1 ms, **no respawn**) instead of each call managing its own server. If no supervisor is live the gateway
  **degrades to the per-call path with a warning** (the pool is an OPTIONAL layer, never the sole authority).
- **Single owner of the transitions.** The supervisor runs the `lib/PoolManager.psm1` integrity core (fencing +
  CAS, `CanServe`, the crash-atomic `EMPTY→STOPPING→EMPTY_CONFIRMED→STARTING→RESIDENT` machine, verified
  socket-owner publish, GPU-handoff planning) — every integrity invariant NON-bypassable; the `-BypassPoolManager`
  cold-isolated escape is untouched. Inference is NOT proxied through the control channel: the supervisor
  publishes the resident to the SAME `runtime/warm-server.json`, so a classic `-Warm` completion reuses it.
- **Lifecycle.** `-Action start | stop | status | reconcile | ping` (and the internal `run` loop). `stop` sends a
  graceful shutdown (evict the resident + close the Job) then hard-kills if needed; on `start`/restart the
  supervisor **reconciles the published manifest as a claim to VERIFY** (a crashed/dead resident is driven to
  `EMPTY`, a healthy one is kept). Idempotent: a second `start` returns `already_running`.

```
# start the durable supervisor (once per box; detached)
pwsh -File Start-GatewaySupervisor.ps1 -Action start
# a per-call gateway attaches + reuses the resident across invocations (no respawn)
pwsh -File Invoke-ModelGateway.ps1 -EnsureResident -UseSupervisor -Model llm.strong.qwen3p5-9b
pwsh -File Invoke-ModelGateway.ps1 -Warm -Model llm.strong.qwen3p5-9b -Prompt 'hi'   # classic inference reuses it
pwsh -File Start-GatewaySupervisor.ps1 -Action status
pwsh -File Start-GatewaySupervisor.ps1 -Action stop
```

**Follow-on (named, NOT built this wave): exec.watchdog #00.1 relaunch integration** — have the watchdog restart a
dead supervisor exactly as it relaunches the executor (a `Recover-Executor`-style check of `supervisor.json`
liveness + a re-`start`). This makes the supervisor self-healing for an unattended soak.

**Still DEFAULT-OFF.** This wave delivers the durable supervisor (finding 5 durable) but does **not** enable the
pool by default — that awaits a soak + the res.lease fencing wave (findings 13/14). The classic per-call and
D-0057 warm paths are byte-for-byte unchanged.

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
