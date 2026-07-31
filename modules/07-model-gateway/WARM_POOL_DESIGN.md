# WARM MULTI-MODEL POOL + ROUTER -- design (model.gateway #7, Phase 2 evolution)

**Status:** DESIGN + PROBE (iteration 10, plan `fo-10-fbfbae02`, worker `WMP-design`). This unit does **not**
change gateway runtime behaviour. It grounds a target architecture in an **empirical probe run on the real box**
(`modules/07-model-gateway/runtime/warmpool-probe/`, `m10-warmpool-probe-002`, 2026-07-29) and produces a
frontier escalation pack for a second opinion. Stage-1 is built in a **later** iteration after the frontier
answer returns.

**Owner:** `model.gateway` #7. **Composes:** `res.lease` #29 (the single `gpu` lease), the Adaptive Resource
Governor (`agent.local` #21 model-affine epochs M0->M1->S0), and the couriered ChatGPT model-selection report
(`core-docs/research/2026-07-28-frontier-local-model-selection.md`).

---

## 0. TL;DR (what the probe changed about the plan)

The couriered report framed the goal as "one active GPU model + **warm RAM specialists** + a router, because the
binding budget is KV/context, not weight-fit." The probe **confirms the VRAM ceiling and the RAM headroom** but
**partially refutes the premise that a RAM-warm pool makes swapping cheap on this box**:

- **A model swap is GPU-upload/init-bound, not disk-bound.** Swapping the resident model costs **~1.6 s (-> 3B)
  to ~4.1 s (-> 9B)** whether or not the GGUF is already hot in the 64 GB page cache (measured cache-warm and
  cache-cold samples were indistinguishable, because every GGUF is already resident in RAM). Keeping specialists
  "warm in RAM" therefore does **not** buy a cheap swap here -- the cost is uploading ~7 GB of weights to the
  2080 Ti and re-initialising, which page-cache warmth cannot avoid.
- **The only near-free path is same-model GPU residency: ~1 ms warm reuse** (no reload) via the D-0057 warm
  server.
- **Exactly one ~7 GB model fits at a time.** With the 9B Q5 resident, **2902 MiB** VRAM is free -- not enough
  for a second ~7 GB model. KV/context is *not* the binding constraint for a single model (~90k tokens of f16 KV
  would fit in the free VRAM); a **second set of weights** is.

**Consequence for the design:** on this hardware the "warm multi-model pool" is realistically **one GPU-active
model + task-affinity routing that MINIMISES swaps + ~1 ms same-model reuse** -- **not** a farm of hot
specialists that swap cheaply from RAM. The recommended Stage-1 is the smallest slice that delivers that:
**extend the already-shipped single warm server (D-0057) into a named "pool manager" with a residency key and a
swap-minimising policy** -- reusing the hardened detached lifecycle, the `gpu` lease, and the governor's
model-affine epochs. The native `llama-server` **router mode** (which the probe found DOES exist on both engine
builds) is a Stage-2+ optimisation gated on two measured constraints (below). If the frontier concurs, Stage-1 is
a low-risk, high-reuse build; if not, we have avoided over-building a specialist farm the hardware cannot exploit.

---

## 1. Measured constraints (probe `m10-warmpool-probe-002`, real box, 2026-07-29)

Host `DESKTOP-PF5FFMF` -- RTX 2080 Ti **11264 MiB** total VRAM (cc 7.5, Turing), i9-9900KF, **63.9 GiB** RAM.
Engines: **b8661** (default, all tiers) and **b10092** (the 9B hybrid). Full data:
`modules/07-model-gateway/runtime/warmpool-probe/findings.json` + `findings.md`.

### (a) Model-swap cost -- detached warm server (`model.gateway -Warm`)

| measurement | ms | note |
| --- | --- | --- |
| same-model **warm REUSE** (no reload) | **~1** | the pool's payoff -- resident model, no upload |
| 3B first load | 1711 | 3B IQ4_XS (~1.62 GiB) load->health |
| swap **-> 9B** sample 1 | 4178 | evict 3B + load 9B Q5 (~6.62 GiB) |
| swap **-> 9B** sample 2 (cache-warm) | 4140 | ~identical to sample 1 -> **not** disk-bound |
| swap **-> 3B** sample 1 | 1603 | evict 9B + load 3B |
| swap **-> 3B** sample 2 (cache-warm) | 2117 | run-to-run jitter; still GPU-upload-bound, **not** disk |

**Reading:** a genuine model change costs **~1.6-4.2 s of GPU upload + init**, independent of page-cache warmth
(both cache regimes measured the same because all GGUFs are already RAM-resident). A true cold-*disk* load could
not be forced (flushing the Windows page cache needs RAMMap/admin), but that is the point: on a 64 GB box the
disk read is never the swap bottleneck -- the **VRAM upload** is. Same-model reuse is **~1 ms**.

### (b) VRAM ceiling

| state | used MiB | free MiB |
| --- | --- | --- |
| idle (no model resident) | 1270 | **9758** |
| 9B Q5 resident (ctx 8192) | 8126 | **2902** |

- **9B footprint** = 9758 - 2902 = **6856 MiB** (~6.69 GiB) for the ~7.11 GB file + its KV/compute buffers.
- **A second ~7 GB model cannot co-reside** (2902 MiB free vs ~6856 MiB needed). **One active model at a time.**
- **KV is cheap; context is not the ceiling for a single model.** At the report's ~32 KiB/token (f16) for the 9B
  hybrid arch, the 2902 MiB free would hold ~**90k tokens** of additional KV -- so the 9B can comfortably run
  16K-32K context (halve again with `--cache-type-k/v q8_0`). The binding budget for a *pool* is **weights for a
  second model**, which do not fit -- exactly the report's point, seen from the pool angle.

### (c) Engine capabilities -- `llama-server --help` (BOTH builds; measured, not assumed)

Both **b8661** and **b10092** expose the **native router-server** feature set and warmth/KV controls:

| flag | present (b8661 / b10092) | meaning |
| --- | --- | --- |
| `--models-dir PATH` | yes / yes | directory of models **for the router server** |
| `--models-preset PATH` | yes / yes | INI file of model presets for the router server |
| `--models-max N` | yes / yes | router: max models loaded simultaneously (**default 4**, 0=unlimited) |
| `--models-autoload` / `--no-models-autoload` | yes / yes | router: auto-load models on request |
| `-a, --alias STRING` | yes / yes | model name aliases used by the API (route by `model` field) |
| `--slot-save-path PATH` | yes / yes | **slot KV save/restore** (conversation warmth) |
| `--cache-reuse N` | yes / yes | reuse prefix KV via KV-shifting (needs prompt caching enabled) |
| `--cache-type-k` / `--cache-type-v` | yes / yes | **KV quantisation** (f16/q8_0/q4_0/... -> extend context) |
| `-np, --parallel N` | yes / yes | server slots |
| `--props` | yes / yes | change global properties at runtime via `POST /props` |
| `-hf, --hf-repo` | yes / yes | HF download |
| `--prompt-cache` / `--prompt-cache-all` | **no / no** | (these are `llama-cli` flags; server uses `--slot-save-path`+`--cache-reuse`) |

**Decisive finding:** a **multi-model router server is built into the existing engine** (both builds) --
mechanism "A" needs **no** new dependency (no llama-cpp-python). It routes by the request `model` field, aliased
via `-a`, loading up to `--models-max` models. Slot save/restore (`--slot-save-path`) and prefix-KV reuse
(`--cache-reuse`) give conversation warmth; KV quantisation extends context.

### (d) RAM-warm feasibility -- can all GGUFs be page-cache-hot at once?

| set | size |
| --- | --- |
| 4 pool tiers (0.5B + 1.5B + 3B + 9B-Q5) | **9.53 GiB** |
| + 27B (Q4) | +15.95 GiB |
| + VLM 3B + mmproj | +3.04 GiB |
| **ALL of the above** | **28.53 GiB** |
| total RAM / free at probe | 63.9 GiB / 45.1 GiB |

**Every GGUF fits in the page cache simultaneously** (28.5 GiB << 64 GiB; 45 GiB was free even mid-session).
Process-per-model warm-in-RAM is **memory-feasible**. But per (a), RAM warmth does **not** reduce the swap cost
(GPU-upload-bound), so its value is limited to avoiding the *first* disk read after boot -- a one-time cost.

---

## 2. Target architecture

```
                       task / goal
                           |
                    [ router (Stage-2) ]  <- picks a model_id by task affinity
                           |                  (governor epoch M0/M1/S0 already does this)
                           v
   +--------------------- POOL MANAGER (model.gateway) ----------------------+
   |  residency key = model_id + sha256 + engine_build + ngl + ctx + no_think |
   |  Ensure-ResidentModel(model_id):                                         |
   |     exact-match resident?  -> reuse (~1 ms)                              |
   |     else                   -> evict current + load requested (1.6-4.1 s) |
   +------------------------------------------------------------------------+
        | holds the single res.lease #29 `gpu` lease for the whole task
        v
   ONE GPU-ACTIVE llama-server (detached, D-0057)      RAM-warm: every other GGUF
   (~6.7 GiB 9B, or 3B, or VLM...; <= 1 resident)      sits in the 64 GB page cache (free)
```

- **One GPU-active model.** The 11 GB card holds exactly one ~7 GB model + its KV. The "pool" is the set of
  models eligible to become the resident, all page-cache-warm in RAM.
- **A residency key** (already defined by the governor: `model_id + model_sha256 + engine_build + gpu_layers +
  context + no_think + generation_id`) decides reuse vs evict+reload. Exact match -> ~1 ms reuse; mismatch ->
  evict + reload.
- **Routing minimises swaps.** Because a swap is 1.6-4.1 s, the router's job is to **group same-model work** and
  pick the resident by **task affinity**, not to swap eagerly. This maps 1:1 onto the governor's monotonic
  model-affine epochs (M0=3B, S0=9B; VLM for image tasks; a code/math specialist only if it earns the swap).

---

## 3. Candidate mechanisms (with a measured recommendation)

### A -- native `llama-server` router mode (`--models-dir` / `--models-preset` / `--models-max` / `--alias`)
One server process hosts N models and routes by the `model` field. **Available on both builds** (probe c).

- **Pro:** built-in, zero new dependency; clean named-model API; slot save/restore + `--cache-reuse` for warmth;
  a single long-lived process (no per-swap process respawn).
- **Con (measured):** two hard constraints on THIS box.
  1. **Engine split.** The 9B is a hybrid attention-SSM arch that **only b10092 loads**; every other tier runs
     on b8661. A single router process = a single engine build. Mechanism A therefore requires that **one build
     (b10092) can host ALL tiers** (0.5/1.5/3B + 9B + the VLM) -- **unverified** (open question 2). If it cannot,
     A needs *two* router processes and loses its single-process advantage.
  2. **VRAM over-subscription.** `--models-max` defaults to 4, but 4 x ~7 GB cannot fit in 11 GB. The router's
     GPU-vs-RAM residency + eviction behaviour on an over-subscribed card is **unverified** (does it lazy-load +
     LRU-evict to VRAM, or try to co-load and OOM?) -- open question 1. A genuine model change still pays the
     ~4 s GPU upload measured in (a); the router likely cannot make that cheaper.

### B -- process-per-model + slot save/restore (`--slot-save-path`) + page-cache warm-swap
One `llama-server` **per model** (each with its own engine build), only one on the GPU at a time; persist slot
KV to disk so a swap-back can skip prompt re-ingest.

- **Pro:** per-model engine build (solves the b8661/b10092 split cleanly); process isolation; reuses the existing
  gateway spawn/teardown; slot save/restore recovers conversation KV across swaps.
- **Con:** a swap still pays the GPU upload (1.6-4.1 s); slot-save persists *KV*, not *weights*; it is essentially
  the current single-warm-server generalised to a small named set -- i.e. mechanism C with extra process churn.

### C -- extend the shipped single warm server (D-0057) into a named pool manager + swap-minimising policy
Keep the one detached warm server; add a **named residency key** and `Ensure-ResidentModel(model_id)` that reuses
on exact match (~1 ms) or evict+reloads on change (1.6-4.1 s); pick the resident by **task affinity** to minimise
swaps. Router optional/minimal (the governor epoch already picks the model).

- **Pro:** **smallest delta from what already SHIPPED** (D-0057 detached warm server + orphan reaping + `gpu`
  lease + the governor's residency-key matching); per-model engine build is handled naturally (each `-Warm` call
  selects the model's `engine_path`); composes directly with res.lease #29 and the governor.
- **Con:** a genuine model change costs a full evict+reload (no multi-model process sharing). But per (a) that
  cost is GPU-upload-bound and **A/B do not beat it** for a real model change -- so C gives up little.

### Recommendation

**Stage-1 = mechanism C.** The measurements make C the right first slice:

1. **The swap cost is GPU-upload-bound (~1.6-4.1 s) and irreducible by RAM warmth or process sharing**, so
   neither A nor B makes a genuine model change materially cheaper than C's evict+reload. The pool's real value
   is **routing to minimise swaps + ~1 ms same-model reuse**, which C already delivers with the least risk.
2. **The b8661/b10092 engine split argues against a single-process router (A) as Stage-1.** C handles the split
   for free (per-model `engine_path`); A must first prove one build hosts every tier.
3. **C reuses the hardened, already-live D-0057 lifecycle** (detachment, orphan reaping, the `gpu` lease,
   residency-key matching) -- the D-0055/56 wedge class is already closed for it.

**Stage-2+ = evaluate A** (native router) as an optimisation, gated on the two measured constraints, and **RAM-warm
role-specialists** only if routing data shows they earn the ~4 s swap-in.

---

## 4. Composition with res.lease #29 and the governor

- **Single GPU lease serialises residency.** `res.lease` #29's `gpu` lease is acquired **once for the whole
  ramped task** (the governor's rule; per-call leasing would let another instance swap the resident mid-task) and
  renewed ~30 s. The pool manager reuses-or-evicts the one registry-tracked resident under that lease -- so at
  most one `llama-server` is ever GPU-resident even though the lease is free *between* calls (exactly the D-0057
  warm-server + lease rule, unchanged).
- **Governor model-affine epochs map to resident choices.** M0 (3B floor) / M1 (fresh-context 3B retry) / S0
  (escalate to the resident 9B) / X0 (one-shot 27B, impractical -- see negative result) are already
  *model-affine*: every LLM call in an epoch runs on ONE model. The pool manager's `Ensure-ResidentModel(epoch's
  model)` is the exact operation the governor needs -- reuse within an epoch (~1 ms), one swap on an M->S
  escalation (measured 3B->9B ~4.1 s, matching the governor's observed "1 swap" ramp).
- **Residency key = the governor's manifest.** Reuse only on an **exact** match of `model_id + model_sha256 +
  engine_build + gpu_layers + context + no_think`; else stop + reload. No new concept -- the pool manager is the
  governor's residency-key matcher, promoted from "the warm 9B" to "any named tier."

---

## 5. Eviction / residency policy

- **GPU-active:** exactly one model -- the current epoch's / router's choice.
- **RAM-warm:** every other GGUF (all fit; probe d). Free; no action needed beyond first-use disk read.
- **Selection = task affinity, NOT LRU.** Because a swap is expensive (1.6-4.1 s) and same-model reuse is ~1 ms,
  the policy should **group same-model work and avoid thrash**, not react to recency. LRU is only a tiebreak when
  two tasks want different models with equal affinity. Keep-resident-after-task for a short window (the governor's
  ~90 s inter-task reuse window, recorded as `overprovisioned_due_to_residency`).
- **Thrash bounds (inherit the governor's):** monotonic epochs, model-affine, default max-1-swap per task,
  leave-resident-after. A duplicate-side-effect guard already exists post-escalation.
- **Never co-load two big models** (probe b): the manager must evict before loading, and assert `<= 1`
  `llama-server` on the GPU (the D-0055/56 reap-before-finalise + 0-orphan assertion, already shipped).

---

## 6. Phased build plan

- **Stage-1 (smallest useful slice; a LATER iteration, after the frontier answer):** a **pool manager** =
  D-0057's warm server + a named residency key + `Ensure-ResidentModel(model_id)` (reuse on exact match ~1 ms,
  else evict+reload). Driven by an **explicit model choice** (the governor epoch already supplies one -- router
  optional/minimal). No new engine, no new dependency, no models.json wiring change. Composes res.lease (whole-
  task `gpu` lease) + governor residency-key matching. Verify: reuse ~1 ms, swap 3B<->9B ~1.6/4.1 s, 0 orphans,
  <= 1 resident.
- **Stage-2:** a **minimal router** (a `route.tools`-style mid-tier classifier, or a tiny rule map) that turns
  task -> `model_id` and feeds the pool manager; measure the **swap-rate reduction** vs no routing. Optionally
  wire slot save/restore (`--slot-save-path`) + `--cache-reuse` for cross-swap prefix warmth if it measurably
  cuts re-ingest.
- **Stage-3 (optional, gated):** evaluate the **native `llama-server` router** (mechanism A) IF (i) b10092 is
  verified to host ALL tiers (collapsing to one engine build) AND (ii) the router's model change avoids the full
  GPU re-upload; and add **RAM-warm role-specialists** (a code / math model from the report's specialist table)
  ONLY if routing data shows they earn the ~4 s swap-in versus fast-swapping the existing 3B/9B.

---

## 7. Open questions for the frontier second opinion

1. **Native router vs process-per-model.** On this exact HW (11 GB VRAM / 64 GB RAM / llama.cpp b8661+b10092),
   given a model swap is **GPU-upload-bound (~4 s for the 9B) and page-cache warmth does not reduce it**, is the
   native `llama-server` router mode (`--models-dir`/`--models-preset`/`--models-max`) worth adopting over a
   process-per-model warm server? Does the router avoid the full GPU re-upload on a model change, or is ~4 s
   irreducible? What is its GPU-vs-RAM residency + eviction behaviour when `--models-max` > the number of models
   that fit in VRAM (does it lazy-load + LRU-evict, or co-load and OOM)?
2. **Engine split.** Can a single **b10092** router process host **all** tiers (0.5/1.5/3B + the 9B hybrid + the
   Qwen2.5-VL 3B), or is a two-engine design mandatory? If mandatory, mechanism A loses its single-process
   advantage -- is it still worth it?
3. **Residency/eviction policy.** On a 1-GPU-resident box where a swap is 1.6-4.1 s, confirm **task-affinity +
   keep-resident-after** over LRU; what keep-resident window?
4. **Do RAM-warm role-specialists earn their keep here?** Given (a) the swap cost is the same ~1.6-4.1 s
   regardless of RAM warmth and (b) VRAM holds only one model at a time, is a dedicated code/math specialist
   (each use costs a ~4 s swap-in) worth it versus just fast-swapping the existing 3B/9B? If yes, which one(s)
   and at what routing threshold?
5. **Prefix/slot warmth.** Is wiring `--slot-save-path` + `--cache-reuse` (persist the evicted model's session KV
   so a swap-back skips prompt re-ingest) a meaningful win, given KV is cheap (~32 KiB/token for the 9B)?
6. **KV quantisation.** Recommended `--cache-type-k/v` (q8_0 / q4_0) defaults to push the 9B to 16K/32K context
   within the measured ~2902 MiB free?
7. **Pitfalls.** llama.cpp router-mode gotchas on Turing (cc 7.5); OOM behaviour with `--models-max` > 1 on 11 GB;
   any orphan/teardown risks (the D-0055/56 executor-wedge class) the pool manager must guard.

---

## 8. Negative results / honest scope (do not oversell)

- **RAM-warm specialists do NOT make swapping cheap on this box.** The swap is GPU-upload-bound (~1.6-4.1 s), not
  disk-bound; page-cache warmth (confirmed feasible for every GGUF) does not reduce it. The only near-free path is
  **same-model GPU residency (~1 ms reuse).**
- **Multiple models GPU-resident is impossible** (2902 MiB free with the 9B). The pool is **one GPU-active model
  + routing to minimise swaps**, not a farm of hot specialists.
- **The already-shipped single warm server (D-0057) captures most of the available win.** The pool manager's
  incremental value is a **named multi-tier interface + swap-minimising routing**, not a cheaper swap.
- **The 27B remains impractical** (D-0061; no quant fits GPU-bound on 11 GB) -- the resident 9B is the effective
  top rung; the pool does not change that.

If the frontier concurs, Stage-1 (mechanism C) is a small, high-reuse build. If the frontier sees a way the
native router (A) beats the ~4 s swap or collapses the engine split, Stage-3 absorbs it. Either way this design
avoids over-building a specialist farm the 11 GB card cannot exploit.

## 9. Frontier second opinion (folded in 2026-07-29, iteration 10)

Nicholas couriered this design + the probe findings to a ChatGPT Pro session (frontier.bridge pack 12da1fca; answer at modules/31-frontier-bridge/runtime/artifacts/12da1fca-154b-4288-8af7-c8a20eaf9d61/frontier-pack-warmpool.answer.md). The second opinion CONFIRMS mechanism C and sharpens Stage-1.

- Mechanism C confirmed; A/B rejected for Stage-1. The native llama-server router (A) is only a supervisor -- it does NOT remove the ~4 s GPU weight upload, and --models-max is a loaded-instance cap, NOT a VRAM-fitting oracle (real OOM/concurrency risk on this card; needs a direct b8661/b10092 probe before trust). B (process-per-model) does not attack the measured bottleneck (inactive processes cannot keep weights GPU-resident on 11 GB). Ranking: C first, A experimental later (constrained to --models-max 1 + --no-models-autoload it collapses to ~C), B rejected.
- Pool manager shape: an explicit residency service Ensure-ResidentModel(model_id, config_key): reuse if the exact config is resident; else terminate the current owned server, confirm process exit + VRAM recovery, start the requested model via its registry engine, confirm health + provenance, publish the new residency manifest.
- Residency/eviction policy: task-affinity + the governor model-affine epochs are PRIMARY; LRU is only a tie-breaker. M0/M1 reuse the same 3B; escalation does ONE 3B->9B switch and stays on 9B until the task ends (no intra-task downshift) -> default max one swap per task. Hold the WHOLE-TASK gpu lease across residency checks/changes. Keep-resident window: 90 s idle eviction delay (not a reservation). Scheduler cost = execution + swap_in + probable_return_swap (~4.1 s to enter the 9B, ~1.8 s to enter the 3B).
- Expanded residency key (a matching filename is INSUFFICIENT): model_id, model_sha256, engine build/hash, gpu_layers, context_size, no_think/reasoning config, cache_type_k, cache_type_v, flash_attention, parallel slot count, chat template + args, mmproj sha256 (VLM), generation_id.
- Specialists do NOT earn their keep just by being RAM-warm. Only a CODING specialist is a plausible first candidate. Admission gate = a >=30-task benchmark showing >=15 pp verification/pass improvement (or an equivalent frontier-escalation cut), >=10% median total-task-time improvement INCLUDING swaps, and typical specialist residencies of >=3 model calls / ~2000+ tokens / a 30-60 s test-and-repair loop. Declare specialists in the registry but do NOT launch/preload them. Defer a math specialist until the 9B is shown to recur-fail math.
- Slot/prefix warmth: Stage-1 = same-model prefix reuse (normal prompt caching, stable system/tool-schema prefixes; -np 1, explicit id_slot, no cross-task similarity, clear at session boundary). Stage-2 = persistent --slot-save-path across eviction, ONLY when the same conversation returns to the same model, prompts are several-thousand tokens, and >=~500-1000 ms prompt_eval is saved; namespace saved slots by model sha + engine build + ctx + KV types + template + session id; NEVER restore across models/quants/builds/templates/mmproj. Disable slot restore for the VLM until it passes explicit image + text restore tests.
- KV quant: KV is NOT currently binding. 16K f16 is the production default (--ctx-size 16384 --parallel 1 --cache-type-k/v f16). 32K conservative = f16 first; only if margin is short, q8_0/q8_0 + --flash-attn on (q8/q8 tracks f16 closely; do NOT default a decision model K-cache to q4). Before accepting q8/q8: re-pass S0 6/6, a 16K + 32K long-context retrieval test, a structured-output test, a throughput compare, and a 30-min stability/VRAM-peak test.
- Engine split: test b10092 as the candidate UNIVERSAL build across all five fixtures (0.5B/1.5B/3B/9B-Q5/VLM); the VLM is the GATING test (Qwen2.5-VL has had build-specific regressions). If any fixture regresses, keep per-model engine_path -- which mechanism C handles naturally and a single native router cannot.

Net: Stage-1 = the named pool manager (mechanism C) + task-affinity/epoch policy + whole-task lease + 90 s keep-resident + the expanded residency key + same-model prefix reuse; native router (A), slot save/restore, and any coding specialist are gated to Stage-2+ behind explicit probes/benchmarks. See DECISION_LOG D-0063.

## 10. Stage-1 SHIPPED (iteration 14) + frontier red-team -> the Stage-1.1 hardening backlog

**Status update:** Stage-1 (mechanism C) is BUILT and live-verified -- iteration 14, worker WMP-stage1,
commit 09a7e71, model.gateway skill 0.2.0->0.3.0, models.json UNCHANGED, **default OFF** (the classic
per-call + the D-0057 warm paths are byte-for-byte unchanged; a non-warm result carries no
`server.warm.pool` block). Shipped: `Ensure-ResidentModel(model_id, config_key)` (`-EnsureResident`) + the
expanded residency key + reuse-on-exact-match (~1 ms) / else evict (confirm exit + VRAM recovery) + reload +
`/health` + `/v1/models` provenance + a published residency manifest (`lifeorch.model_gateway.warm/0.2`);
`-PoolStatus`; `-SweepIdle` (90 s keep-resident); whole-task gpu lease held (a caller-held governor lease is
honored + never released here); same-model prefix reuse (`--parallel 1` + explicit `id_slot`, `-ClearSlot`
at a session boundary). LIVE-MEASURED through the executor under one whole-task gpu lease: reuse 1 ms, 3B->9B
4219 ms, 9B->3B 1610 ms, a ctx 4096->8192 same-model mismatch forced evict+reload, ~6678 MiB VRAM recovered
on evict, 0 orphaned llama-server, lease released. Gates: base 42/42 + warm 23/23 + NEW pool 43/43. Native
`--models` router, `--slot-save-path`, and any coding specialist remain DEFERRED to Stage-2+.

**Frontier red-team (iteration 14, pack `3edf7218`; Nicholas couriered to GPT-5.x; answer at
`modules/31-frontier-bridge/runtime/artifacts/3edf7218-.../frontier-pack-i14-redteam-stage1.answer.md`).**
VERDICT: **mechanism C is the right architecture, but the shipped Stage-1 is a functional-but-unhardened
first cut** -- safe only because it is default-OFF/additive. It currently conflates five concepts that each
need a separate invariant: a desired config, a launched-server generation, ownership of an active GPU op,
permission to stay resident, and a scheduler swap-preference. Before the pool may be ENABLED BY DEFAULT it
needs the Stage-1.1 hardening below.

**Stage-1.1 hardening backlog (15 ranked findings; * = Critical):**
1. *Lease TTL is abandonment, NOT fencing -- two "owners" can co-exist. Add a monotonic **fencing token** per
   acquire; compare-and-swap it on every kill/start/publish/evict; a task whose renewal lapses loses all
   authority (cancel, stop issuing calls, treat handles invalid). Short renewable TTL (~90-120 s, renew
   ~30 s), NOT 1800 s. Every inference call carries its expected resident generation + is rejected on
   mismatch.
2. *Releasing the lease while the 9B stays resident does NOT free the GPU for another module (~2902 MiB free
   vs ~6.7 GiB needed -> OOM). Define an enforced `AcquirePreparedGpu(owner, required_vram)` handoff (inspect
   owner + free VRAM, evict if incompatible, confirm headroom before granting); or evict-before-release.
3. *Residency transitions are not crash-atomic. Durable state machine
   EMPTY->STOPPING->EMPTY_CONFIRMED->STARTING->RESIDENT via atomic replace; treat the manifest as a claim to
   VERIFY; reconcile on every gateway startup under a machine-global named mutex.
4. *A fixed port + `/health` can validate the WRONG generation. Each launch: a unique nonce + unique port +
   recorded PID/creation-time + exe/backend hashes; verify the listening socket's owner before publish (a
   `/v1/models` alias is not proof).
5. Windows detached-child reaping is not guaranteed by killing the parent PID -- own the whole tree with a
   **Windows Job Object** held by a persistent gateway supervisor; never kill by PID alone; "0 orphaned
   llama-server" must mean 0 UNMANAGED servers, and must NOT kill the intended warm resident.
6. `generation_id` must NOT be in the config fingerprint (a per-launch UUID would defeat all reuse -> the
   ~1 ms payoff vanishes). Split `resident_config_hash` (deterministic immutable launch config) vs
   `instance_generation` (per-launch nonce for fencing); rename any registry rev `registry_config_version`.
7. The key is both incomplete (add LoRA/adapters+order, control vectors, RoPE/YARN, exe+backend-DLL hash, GPU
   device identity, main-gpu/split/tensor-split, batch/ubatch, cache-reuse mode, server mode, VLM projector,
   reasoning parser) AND too strict (seed/temp/top-p/top-k/penalties/logit-bias/grammar/stop/max-tokens/
   per-request no-think/pre-rendered template are REQUEST-scoped). Hash file CONTENTS, not paths.
8. Replace exact-equality with `CanServe(resident, request)`: exact for semantic-identity fields, `>=` for
   capacity (a 32K resident serves 16K; a resident 9B serves an M0 request) -- reload only when the resident
   cannot correctly serve.
9. "Max one swap per task" is FALSE when a task begins with the 9B resident (9B->3B for the M0 floor, then
   3B->9B on escalation = 2 swaps). Treat the 3B as a MINIMUM starting capability; run M0/M1 on an
   already-resident 9B; do not downshift just to honor the floor.
10. Nothing prevents cross-task thrash (A:3B, B:9B, C:3B, D:9B -> a swap per boundary). Add resident-aware
    ADMISSION (prefer a queued task compatible with the resident, with aging/fairness). LRU is meaningless at
    capacity 1 -- REMOVE it from Stage-1.
11. A fixed 90 s idle unload is inferior to contention-driven eviction (and races a refreshing request).
    Leave the model resident until an incompatible demand / another GPU owner / explicit shutdown; if a timer
    is kept it must be a generation-conditional CAS -- a policy, not a correctness mechanism.
12. "Clear at session boundary" is insufficient for KV safety (a crash/cancel skips it -> cross-task KV
    bleed). Erase-on-checkout AND on-check-in + a full slot-owner record; or REMOVE prefix reuse from Stage-1
    (recommended -- it is an incremental optimisation).
13. A whole-task GPU lease across the entire task starves higher-priority work. Separate a GPU
    execution/transition lease (held only while loading/unloading/generating) from a revocable residency
    PIN; or constrain "whole task" to the model-affine LLM segment.
14. `gpu->git` acquisition can hold the GPU idle waiting for git; the lease service should reject lock-order
    inversions. Build worker: edit+test under git, release git, take GPU only for live verify.
15. "Process exit + VRAM recovery" needs a target-headroom invariant + a confirmation interval (WDDM frees
    async), not a brittle return-to-baseline; on OOM kill the Job Object, drain, leave EMPTY.

**Sound + affirmed:** mechanism C; per-model `engine_path` for the b8661/b10092 split (provided the exe hash
is in provenance); sampler params request-scoped; the one-active-model invariant; the 27B excluded; `-np 1`
as a Stage-1 simplification; no claim that RAM page-cache warmth cuts swap cost.

**Recommended Stage-1.1 framing:** a named resident manager that is an OPTIONAL optimised layer, NEVER the
sole model-execution authority -- keep a legacy `--bypass-pool-manager` / cold isolated-server escape; every
new guard is override-safe (explain, auto-investigate, recommend, override with a recorded reason, continue
via a safe degraded path), while integrity invariants (fencing, single-endpoint ownership, verified-model
routing, no cross-task KV, no blind co-load) are NON-bypassable. Required before "done": a fault-injection
suite (crash at each transition point then reconcile; forced lease-expiry during a live request; a stale
idle-callback vs a fresh request; Job-Object tree reap + PID-reuse; KV isolation across crash/cancel; the
GPU-handoff eviction). See DECISION_LOG D-0067.
**Stage-1.1 SHIPPED (iteration 15, D-0068, commit `121a0fc`; integrity core `lib/PoolManager.psm1`).** Closed the
Criticals + enabling fixes: a monotonic fencing token + short renewable TTL + CAS + inference generation-mismatch
REJECTION (1); GPU-handoff evict-before-grant + a target-headroom/WDDM-async confirmation (2/15); a crash-atomic
state machine EMPTY->STOPPING->EMPTY_CONFIRMED->STARTING->RESIDENT + reconcile-on-startup under a machine-global
lock (3); a verified socket-owner publish gate, not a /v1/models alias (4); resident_config_hash (hashes file
CONTENTS) split from instance_generation (6); CanServe() exact-identity + >=capacity (7/8/9); dropped LRU +
timed-idle-as-correctness + same-model prefix-reuse from the correctness path, KV isolation = erase-on-checkout +
on-check-in (10/11/12); a -BypassPoolManager escape with the integrity invariants non-bypassable. Off-machine
157/157 (core 49 + warm 23 + pool 48 + fault-injection 37); LIVE on the box: base 42/42, 3B->9B 4138 ms (2276 MiB
recovered), 9B reuse 1 ms, socket_owner verified TRUE on the real llama-server, a stale-generation inference
REJECTED (generation_mismatch) while the current call passed, 0 orphaned llama-server, whole-task gpu lease
held+released. models.json UNCHANGED; the pool ships DEFAULT-OFF.

**Stage-1.1 RESIDUALS (before the pool may be enabled by default).** (a) DURABLE Windows Job-Object ownership of
the server tree ACROSS separate invocations needs a PERSISTENT gateway supervisor process (the gateway is invoked
per-call, so a per-call named Job Object dies on process exit); the per-call case is covered now by the managed
tag + taskkill /T tree-kill + a PID/creation-time identity guard (finding 5, partially closed). (b) the res.lease
fencing integration (findings 13/14) is a separate single-worker infra wave. (c) enabling the pool BY DEFAULT is
the orchestrator's call after a soak. Findings 5 (durable Job-Object) + 13/14 remain the gate to default-ON. **UPDATE (i18, D-0072):** the res.lease fencing PRIMITIVE shipped as R1a (`e701328`, res.lease 0.2.0 -- monotonic fencing_token + exec/revocable residency_pin split + a prepared-handoff/evict-before-grant PROTOCOL with a none/mock/command evictor seam + lock-order-inversion rejection; 74/74). Per the folded frontier review (`core-docs/research/2026-07-30-frontier-review-self-tasking-orchestration.md`) R1a is PROVISIONAL: findings 1/13/14 CLOSE ONLY AT R1b -- the model.gateway/governor consumer adoption + the live-GPU swap/eviction proof + three-identity fencing (gpu_authority_epoch / resident_generation / exec_lease_id) / one atomic scheduler-owned transition / an adversarial mock / WDDM headroom confirmation. The gate to default-ON is now R1b + a soak. **UPDATE (i19, D-0073):** the R1b PRIMITIVE shipped (res.lease 0.3.0, `2d45ffe`: three-identity fencing gpu_authority_epoch/resident_generation/exec_lease_id + a scheduler-owned atomic transition + an adversarial mock evictor; 74/74 + 36/36, 0 regression). A folded concurrency/safety red-team (pack `b823d9db`) found the identities necessary-but-insufficient + the transition unsafe-as-ordered (grant-before-ready; side effects fire outside the mutex) -> the primitive was HARDENED at R1b'. **UPDATE (i20, D-0075):** R1b' shipped (res.lease 0.4.0, `f6df675`, red-team-driven): incarnation ids (owner_incarnation_id/resident_instance_id + exec_lease UUID, closes ABA) + a two-phase transition-capability (the new server starts under scheduler authority; the first usable exec lease is published only AFTER health = no grant-before-ready) + target-fenced side effects via -Action fence-op (a stale stop/kill/publish naming the wrong resident_instance_id is refused) + an idempotent saga journal + an oplock-serialized renew that cannot resurrect a revoked lease + a durable per-resource state_version for waiters; off-machine adversarial matrix A-K 45/45. The res.lease PRIMITIVE is now hardened + safe to build on, but findings 1/13/14 STAY OPEN: they close ONLY at the R1b CONSUMER wave (model.gateway #7 PoolManager + agent.local #21 governor adoption + the real nvidia-smi/eviction evictor + the live-GPU 3B<->9B swap / pin-revocation / prepared-eviction proof + the live-only tests), then a soak, then default-ON.
**UPDATE (i21, D-0076): the R1b CONSUMER wave shipped + live-proven, AND a supervisor SECURITY red-team reset the default-ON gate.** model.gateway #7 0.5.0 (`-UsePoolLeaseSplit` + the real supervisor-routed nvidia-smi evictor `lib/PoolEvictor.ps1` + supervisor target-fenced evict), agent.local #21 autoramp 0.2.0 (`-SplitLease`), res.lease #29 0.4.1 -- all DEFAULT-OFF, 0 regression + a full live-GPU proof on the 2080 Ti (swap chain; second-owner revoke -> prepared eviction; revoke-during-ACTIVE-inference discard; late-stale-result refused by `check`+`fence-op`; fail-closed prep; real-OOM = driver-spill negative; OFF==ON equality; 0 orphans). Findings 1/13/14 are CLOSE-ELIGIBLE **at the res.lease/consumer LEASE layer**. BUT a PARALLEL off-box frontier SECURITY red-team of THIS durable supervisor + the real evictor (pack `5cbe8913`, captured `.answer.md`; digest `core-docs/research/2026-07-31-frontier-supervisor-redteam.md`), verified against live HEAD `00e5912`, returned **NO** with 7 structural must-fix blockers (spawn-before-Job-assign + nonfatal assignment; one supervisor-wide Job Object + heuristic tree_gone; unauthenticated/optional-target IPC; pool-lock 60s steal + nonce-less release; fail-open EnsureResident; wedged-supervisor-still-"running" + fallback split-brain; provenance-by-timestamp + weak Test-ResidentIdentity). **finding 5 (durable Job-Object custody) is RE-OPENED at the custody layer.** Warm-pool default-ON is therefore NOT soak-only: it now gates on a **SUPERVISOR-HARDENING wave** (the 10 ranked must-fixes) -> an **in-proc res.lease client** (the i21 split-overhead finding: ~6-9 child-pwsh spawns/call dominate) -> a **GROWN soak** (>=24h continuous supervisor, >=1000 transitions, sleep/resume, separate >=25-each fault counts, p99+max + handle-leak + lock-hold + unmanaged-pressure metrics + the 15 enumerated live tests). See the digest for the ranked must-fix list + the grown soak spec.
