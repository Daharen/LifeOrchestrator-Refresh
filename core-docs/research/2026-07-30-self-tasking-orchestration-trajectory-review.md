# Trajectory review — the self-tasking, sequential-baton-pass local orchestrator

**Provenance:** code-review / direction-check requested by Nicholas 2026-07-30 (in a Cowork review
session, NOT the fan-out loop). Question: does the current project trajectory support a **single strong
local agent that tasks itself** — decomposing a complex goal, then running a **sequential, single-GPU,
unload/reload baton-pass** across many local-model instantiations (orchestrator → same-strength preflight →
per-stage executor agents, each loading, running one tool, unloading), with **exactly one powerful model in
VRAM at a time** and warm weights staged in RAM? And is control actually **relinquished to execute and
re-acquired at the end**, or are the gates too harsh?

**Verdict in one line:** the *substrate* for this is largely BUILT and the hardware premise is CONFIRMED,
but the *orchestration shape* currently built is different in two specific, load-bearing ways — control is
**held for the whole task, not relinquished per stage**, and there is **no sequential local multi-agent
baton chain** (only a single self-escalating agent + a parallel *frontier* fan-out). The vision is reachable
from here, but it is **not on the near-term roadmap** and needs the revisions below to become real.

---

## 1. What the vision maps onto (component-by-component)

| Vision element | Nearest built thing | State |
| --- | --- | --- |
| One powerful model in VRAM at a time | Measured hardware truth: 9B Q5 resident → **2902 MiB free**, a 2nd ~7 GB model cannot co-reside | **CONFIRMED** (WARM_POOL_DESIGN §1b). Not a gate to loosen — the foundation. |
| Load / unload / swap a model | `model.gateway` #7 warm server (D-0057) + **pool manager** `Ensure-ResidentModel(model_id, config_key)` (D-0067/68) | **BUILT, tested, DEFAULT-OFF.** Same-model reuse ~1 ms; swap 3B↔9B ~1.6–4.1 s. |
| Unload the strong model, load a stronger/other one, continue | Governor monotonic model-affine epochs M0→M1→S0→X0 | **BUILT + LIVE** (liveB ramped 3B→9B mid-task and finished). Proves the baton mechanic works. |
| Warm-store weights in RAM for a faster RAM→VRAM path | All GGUFs (28.5 GiB) fit the 64 GB page cache | **Feasible but ~0 payoff** — see §3. Swap is GPU-upload-bound, NOT disk-bound. |
| Pre-flight agent of the **same strength** that picks which tools to delegate | `route.tools` #27 | **BUILT but runs at MID (3B), not strong.** Strong routing is proven-accurate (governor Exp 1) but not the default. |
| An orchestrator that hands off to distinct instruction-pack sub-agents | `agent.local` #21 + governor | **PARTIAL / different shape** — one agent that swaps its OWN brain-tier; its tools are DETERMINISTIC modules, not LLM sub-agents. |
| A multi-stage orchestrator | `orchestrate.fanout` #30 | **Wrong shape** — PARALLEL, FRONTIER (Cowork) sessions, human-couriered, **HARD-BARRED from driving any AI session** (D-0051). |
| The deliberative planner / workflow composer | `skill.orchestrator` #26 | **DEFERRED / not built** — this is the architectural home for the user's baton-pass sequencer. |
| "Store my own tokens and bring them back" (cold the orchestrator's context) | llama.cpp `--slot-save-path` + `--cache-reuse` | Engine supports it (both builds); **NOT wired, deferred Stage-2+**; and KV can NEVER be restored across a different model (§4). |
| The DaVinci-Resolve-class job (gen video+image+audio+VO+synthesize) | gen.image #23, gen.video #25, gen.audio #22, gen.music #24, speech.tts #12, speech.stt #11, image.interpret #17; uia.actor #5 / capture.screen #6 for app driving | Capability modules **BUILT**; every generator is `parallel_safe:false` (one at a time) — which **mandates** the sequential swap. App-driving of a specific NLE is thin (UIA patterns only; visual action-executor is long-horizon #38). The **sequencer is the gap.** |

---

## 2. The core misalignment: control is HELD, not relinquished-and-re-acquired

This is exactly the user's stated worry ("I am not clear that it is relinquishing its control to execute and
then grabbing it back at the end"), and the worry is **correct for the current implementation**.

- The governor rule (ADAPTIVE_RESOURCE_GOVERNOR §6; WARM_POOL_DESIGN §4) is: acquire the single `res.lease`
  **`gpu`** lease **once for the whole ramped task** and renew ~30 s — *specifically to PREVENT another
  process from swapping the resident model mid-task*. Mid-task relinquish is treated as a **hazard to
  prevent**, not a feature to enable.
- The frontier red-team already flagged this as a limitation — **Stage-1.1 finding #13**: "A whole-task GPU
  lease across the entire task starves higher-priority work. **Separate a GPU execution/transition lease
  (held only while loading/unloading/generating) from a revocable residency PIN**." That is the user's exact
  vision — hold the GPU only while executing, release between stages so the next agent (or a higher-priority
  model) can take it.
- **Status of finding #13: backlog** ("the res.lease fencing integration (findings 13/14) is a separate
  single-worker infra wave" — WARM_POOL_DESIGN §10 residuals). Not built.

So the "harsh gates" instinct is accurate: the governor's safety rules (whole-task lease, monotonic,
default max-1-swap, no mid-task swap-out) were tuned to make a **single agent's** ramp safe and cheap, and
they structurally **block** the multi-stage per-stage relinquish the user wants.

---

## 3. Correction to the RAM-staging assumption (measured negative result)

The user's instinct — "warm-store on RAM so there's speedup RAM→VRAM vs SSD→VRAM" — is **measured to give
essentially no per-swap benefit** (WARM_POOL_DESIGN §0, §1a, §8):

- A model swap is **GPU-upload/init-bound (~1.6 s → 3B, ~4.1 s → 9B)**, and cache-warm vs cache-cold samples
  were **indistinguishable** because every GGUF is already RAM-resident on a 64 GB box. Page-cache warmth
  only saves the **one-time first disk read after boot**.
- The only near-free path is **same-model GPU residency (~1 ms reuse)**.
- **Design consequence:** the lever is **swap-minimization**, not RAM staging. Order pipeline stages to
  **group same-model work** (each reuse ~1 ms) and minimize distinct-model transitions. The pool manager's
  policy is already "**task-affinity, not LRU**" for this reason.
- **Good news for the patience budget:** even at ~4 s/swap, a 20–30-stage LLM chain is ~1–2 min of swap
  overhead total — trivial against the user's "30 min → 2 h is fine." The real time sinks are the
  **generator loads** (e.g. SD 3.5 ~92 s cold / ~43 s warm), not the LLM swaps. Sequence to reuse a resident
  generator across all of its stages before swapping models.

---

## 4. "Bring my context back" is a re-ingest, not a free VRAM-state restore

The user wants the orchestrator to dump its own context to RAM/disk (go cold) and reload it later.

- `--slot-save-path` (KV save/restore) + `--cache-reuse` (prefix reuse) exist on **both** engine builds, but
  are **NOT wired** (deferred Stage-2+; Stage-1.1 even removed prefix-reuse from the correctness path for KV
  isolation).
- **Hard constraint (WARM_POOL_DESIGN §9):** NEVER restore KV across a different model / quant / build /
  template / mmproj. So when the orchestrator yields the GPU to a **different-model** stage and later
  resumes, its context comes back by **prompt re-ingest** (replay the saved transcript through the reloaded
  orchestrator model) — a prompt-eval cost (sub-second to a few seconds for several-thousand tokens), not a
  zero-cost state restore. `--slot-save-path` only helps the **same-model-returns** case.

---

## 5. Trajectory & state summary

- **Trajectory:** aimed correctly at the *substrate* (swap primitive, resource lease, self-escalating agent,
  preflight router, idempotency/resume-from-state, the full modular capability surface). But the *near-term
  roadmap* (video spine #32/#33 → video.timeline/interpret; generator upgrades; warm-pool default-ON;
  portability) does **not** include the baton-pass orchestrator. The full orchestration hierarchy
  (ARCHITECTURE_MAP L3/L4 + #26 + the real-time layer #45–49) is explicitly **long-horizon / deferred**.
  The user's vision is a **deliberate pull-forward** of that layer — legitimate, and now buildable because
  the substrate mostly exists, but it must be **promoted onto the build order**; it is not there today.
- **State:** the swap/load/unload mechanic is BUILT and LIVE-proven; the sequential **local multi-agent**
  baton chain is **not built**; control is **held whole-task, not relinquished per stage** (the user's
  worry, confirmed); RAM warmth buys ~0 swap speedup (correction); orchestrator-context restore across a
  model swap is a re-ingest, not free.

---

## 6. Revisions needed (dependency-ordered)

1. **Split the GPU lease (promote finding #13).** A short-held **execution/transition lease** (held only
   while loading/unloading/generating) + a revocable **residency pin**, keeping the non-bypassable fencing
   invariants (finding #1). *This is the keystone* — it turns mid-task hand-off from a hazard into a
   first-class op and is the literal answer to "relinquish and re-acquire." Prereq for everything below.
2. **Enable the pool manager by default.** Currently default-OFF, gated on a soak + the res.lease fencing
   wave (13/14) + the durable Job-Object supervisor (shipped i16, D-0069). A baton-pass orchestrator must be
   able to rely on `Ensure-ResidentModel` as the standard path.
3. **Add a strong-tier PREFLIGHT.** Give `route.tools` #27 a strong (9B) mode with an adequate token budget
   (≥~1024 tok, per the S0 in-content-reasoning constraint) so the preflight is "the same strength as the
   orchestrator." The 9B is already proven-accurate at routing (governor Exp 1); this is a config/design
   change, not a new build.
4. **Build the missing module: a sequential local orchestrator (the real #26, "baton-pass" mode).** Distinct
   from `orchestrate.fanout` #30 (parallel / frontier / human-couriered) and from `agent.local` #21 (single
   self-escalating agent). It takes a goal → strong preflight decomposes into stages `{instruction-pack,
   tool-subset, model_id}` → for each stage: `Ensure-ResidentModel(stage.model)` → acquire the execution
   lease (R1) → run that stage's agent/tool → release → next. Reuses the pool manager (swap), the split
   lease (R1), `agent.local` (per-stage executor), strong `route.tools` (R3), and the governor's
   idempotency + resume-from-authoritative-state (safe hand-off). **Note the D-0051 boundary is NOT
   violated** — this drives LOCAL models, not another AI *session*; the doc should say so to avoid confusion
   with the fan-out rule.
5. **Design the pipeline planner around swap-minimization (§3), not RAM staging.** Group same-model stages;
   order generator-heavy stages to reuse a resident pipeline; treat distinct-model transitions as the scarce
   ~4 s cost. Consistent with the pool manager's task-affinity policy.
6. **Decide the orchestrator-context cold-store mechanism explicitly (§4).** Same-model-return: wire
   `--slot-save-path` (warm-pool Stage-2). Cross-model hand-off: keep the orchestrator transcript in
   RAM/disk and re-ingest on resume; budget the prompt-eval, don't expect a free restore.

**Build order:** R1 (lease split) → R2 (pool default-ON) → R3 (strong preflight) → R4 (the sequential
orchestrator) → R5/R6 (planner policy + context-restore) fold in during R4.

---

## 7. Where this contradicts current doctrine (flag, don't resolve)

- **D-0050 / PROJECT_DIRECTION:** the near-term spine is the *offload / audit loop under the verify-cost
  rule*, "one scoped unit per session," with the orchestration hierarchy held as long-horizon. The
  baton-pass orchestrator is a **user-track ("useful to Nicholas") deliberative-orchestration** build, not an
  offload build — a direction the user can choose, but it competes with the current queue (video spine,
  generators, warm-pool default, portability). Worth an explicit decision-log entry if pursued.
- The "harsh gates" the user senses are the governor's **single-agent safety rules** (whole-task lease,
  monotonic, max-1-swap). R1 loosens the *right* one (the lease) without giving up the fencing/integrity
  invariants that must stay non-bypassable.
