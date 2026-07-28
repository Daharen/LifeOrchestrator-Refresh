# ADAPTIVE RESOURCE GOVERNOR — design (agent.local #21 · logic.escalator #19 · model.gateway #7 · route.tools #27)

**Status:** Phase 1 shipped (D-0043); Phases 2–3 designed, and **Phase 2 (the warm/persistent model server) is now SHIPPED (D-0057)** -- model.gateway #7 detached warm server (commit f8c961a); Phase 3 (auto-ramp) not yet built.
**Owner doc:** this file is the durable design; per-decision history lives in `DECISION_LOG.md`.

## 1. The problem (the user's critique, stated plainly)

The local LLM tiers were run **under spec**. The agent felt more incompetent than the same
local models do in the user's own projects, and so under-prepared that auditing their output
would cost more frontier tokens than the local run saves. Local **token / time / resource**
budgets are *functionally free* on this box (owned RTX 2080 Ti, i9-9900KF, 64 GB) — unlike the
scarce weekly frontier allotment — yet we were capping them low and stopping well short of the
machine's ceiling.

**The directive:** don't *start* at max per task, but build a **dynamic flow that ramps
resource utilization toward the local PC's capacity before ending the run**, rather than
refusing to get there at all.

## 2. What we measured first (3 experiments, executor-live on the real box)

Before changing anything, three measurement-only runs (`m30-exp1/2/3-001`) tested the actual
hypothesis instead of guessing. Temp 0, seed 42; strong = Qwen 27B (thinking), mid = 3B.

**Exp 1 — "did we starve the 27B?"**
- Routing the dog goal: mid@512 tok returned only `[gen.image]` (a **miss** — the known router
  weakness patched with few-shot in #27); **strong returned the correct `[gen.image, fs.manage]`**
  at finish=stop, non-empty (ctok=111), in 56–74 s (cold load).
- Termination on a done transcript: mid chose `finish` correctly in **2 s**; strong also correct
  but **140 s**.
- **Takeaway:** the 27B is *not* inherently broken for these tasks — the "empty output" that got
  it policy-excluded did **not** reproduce; it was a token-cap/config artifact. The 27B routes
  **more accurately** than mid, just **slowly** (cold load). It is a legitimate rung, not a
  forbidden tier.

**Exp 2 — decision competence on the REAL transcript (where we thought the 3B failed).**
- S1 (image generated, not yet placed → correct = `fs.manage`): mid **correct** in 2 s.
- S2 (image generated AND placed → correct = `finish`): mid **correct** in 2 s.
- strong also correct on both, at 110–149 s.
- **Takeaway:** deciding **in isolation**, the 3B mid tier is **competent** on exactly the
  decisions the live agent was botching. So the live failure was *not* mid being too weak.

**Exp 3 — the decisive one: is the escalator resolving decisions at the 0.5B/1.5B floor?**
Same goal, same gen tier, two decision ladders:
- **Run A — `[tiny, weak, mid]` (the shipped default):** `status=stopped stop=max_steps
  6/6 steps 140 s`; decisions = gen.image, gen.image, fs.manage, gen.image, gen.image,
  gen.image → **5 gen.image invocations, never chose finish**.
- **Run B — `[mid]` only:** `status=completed stop=finish 3/6 steps 37 s`; decisions =
  gen.image, fs.manage, finish → **clean**.
- **Both runs accepted every decision at `accepted_tier=mid`.** So the ladder did not change
  *which tier won* — yet Run A behaves terribly and Run B perfectly.

## 3. Root cause (sharper than "the tiers are too frugal")

The escalator (#19) ladder works by having each **higher tier JUDGE the lower tier's answer**
(accept it, or produce its own). When the floor is tiny/weak, mid is not asked *"what's the best
next action?"* — it is asked *"here is candidate action X (from weak, which judged tiny); is it
right?"* That framing **anchors** the competent mid tier onto the weak tier's answer. On this
goal the weak tiers latch onto `gen.image` (the first, most salient action) and keep re-emitting
it; mid-as-judge rubber-stamps that anchor (consistent with the **0.20 false-approval** rate
measured in D-0030) instead of noticing from the transcript that the image was already produced
and placed. The result compounds with the known termination weakness (D-0032): anchored on
`gen.image`, the loop never selects `finish` and burns to `max_steps`.

**mid-as-fresh-decider ≠ mid-as-judge-over-junk.** Deciding fresh at a competent floor (Run B)
is both **faster and correct**; running the low-floor ladder is **~3.8× slower and wrong**. We
had blamed the 3B; the 3B was fine. The **ladder framing at a low floor** was the defect.

## 4. The design — decide at a competent floor, escalate UP, ramped and warm

Three coordinated pieces (the user chose "Fix + warm server + governor"):

### Phase 1 — decision-floor fix + resource profiles (SHIPPED, D-0043)
- **Decide at the MID floor by default.** `agent.local` default `DecisionTiers` changed
  `[tiny, weak, mid] → [mid]`; default `MaxSteps 4 → 8` (headroom, not a low cap).
- **Escalate UP, never anchor DOWN.** The escalator still exists, but the rungs now go
  `mid → strong` (decide at mid, let the 27B judge/override on doubt) instead of starting under
  mid. There is no tier below the competent floor to anchor on.
- **Un-refuse the 27B.** `route.tools` no longer HARD-throws `strong_tier_forbidden`; it
  soft-warns and proceeds (Exp 1 proved the 27B is a usable rung; the deterministic catalog gate
  already makes an empty/garbage selection safe → the consumer falls back to the full tool set).
- **`-Profile` knob = the governor's rungs**, selectable now and reused by Phase 3:
  - `frugal` = `{tiers:[tiny,weak,mid], gen:mid, steps:6, tokens:512}` — the old ladder, kept for
    A/B and cost-floor runs.
  - `floor`  = `{tiers:[mid], gen:mid, steps:8, tokens:768}` — **the default**; Exp-3 Run B.
  - `max`    = `{tiers:[mid], gen:strong, steps:10, tokens:2048}` — decide at the mid floor,
    **generate with the 27B**, more headroom + steps. (An earlier `max = [mid,strong]` was measured to
    *reintroduce* the 27B empty-output problem at the decision layer — see §5 — so `max` spends the 27B
    on generation, where it helps, and keeps decisions at the competent floor.)
  - Explicit params / InputsJson keys always win; a profile only fills what the caller left unset.

**Key finding while validating `max` (m31-p1-max-001):** an initial `max = [mid,strong]` sent the
decision through the escalator with the 27B as the *judge*. The 27B (a thinking model) burned its
budget on hidden reasoning and emitted an **empty label** (`conf=0.2 → unknown_tool`, stopped at step 1,
326 s), and the escalator **accepted the strong tier's empty answer over mid's valid one** — the same
empty-output failure we saw at routing (Exp 1), now at the decision layer. This is decisive: **the 27B
is a generation/verification/routing rung, not an escalator decision-classifier rung.** Escalating a
*decision* to the 27B must be a **direct classify call with adequate token budget** (Exp 1 showed that
works), and/or the escalator must be fixed to prefer a lower tier's valid answer over a higher tier's
empty one — both are Phase 3 controller concerns, not a static profile.

### Phase 2 — warm / persistent model server (SHIPPED, D-0057 -- f8c961a)
The whole reason escalating to the 27B "costs too much" is that `model.gateway` (#7) starts a
**transient** `llama-server` per call and evicts on model change — a ~60–90 s cold load every time
the tier switches. Phase 2 keeps a **resident** server: reuse it across calls, evict + load only
on an actual model change, and measure warm-vs-cold. This is the enabler that makes `max`
(and Phase 3's ramp) cheap enough to use by default.

### Phase 3 — auto-ramp resource governor (designed)
Wrap the run in a controller that **starts at the `floor` rung and ramps toward the machine
ceiling only when the run isn't succeeding**: run at floor → if unsolved or a verification step
fails, ramp the envelope (escalate decisions to strong, raise gen tier/tokens/steps) → stop at
**verified success OR local ceiling**, not before. The `-Profile` rungs are the ramp steps; the
warm server (Phase 2) is what makes each rung affordable. This is the literal realization of
"up resource utilization to the cap of local PC capacity before ending the run."

## 5. Validation

**Off-machine gate (cloud pwsh 7.4.6, mock children):** agent.local **58/58** (incl. the new
S14 profile-rung suite), route.tools **33/33** (incl. the rewritten S10 strong-soft-allow).

**Live, on the real box (executor):**
- **Default (new mid floor), dog goal, `-Route`:** `status=completed stop=finish 3/8 steps 48 s`;
  decisions gen.image → fs.manage → finish; one gen.image call; a real ~425 KB dog **landed on the
  real OneDrive Desktop**; `profile=(none) decision_tiers=[mid] gen_tier=mid`. This reproduces
  Exp-3 Run B end-to-end and replaces the old default's 6-step/140 s/never-finishing behavior.
- **`profile=max` v1 (`[mid,strong]` decisions), same goal:** the 27B was reached and **accepted**
  (un-refusal works end-to-end; the mid router got `[gen.image,fs.manage]`), but the 27B decision
  came back **empty** (`conf=0.2 → unknown_tool`, stopped at step 1, 326 s) — the §5-referenced
  finding that forced the rung redefinition.
- **`profile=max` v2 (corrected: `[mid]` decisions + 27B generation), same goal:** resolves
  correctly and the empty-decision defect is gone by construction, but it **timed out at the 30-min
  budget** — the 27B is a partial-offload heavyweight on the 11 GB card (VRAM maxed, GPU ~20 %, CPU
  ~96 %; the layers that don't fit run on the i9 and serialize decode) and every gateway call
  cold-loads, so ~2048-token strong generations × cold loads exceed the budget. **The residual is
  pure speed, not correctness** — precisely what Phase 2 (warm server, removes the repeated cold
  loads) and a fitting 27B quant (flips it GPU-bound) are for. The fast, correct path is the `floor`
  default (48 s, fully-GPU-resident 3B); `max` becomes practical once Phase 2 lands.

## 6. Open items / revisit-if
- Phase 2 warm server SHIPPED (D-0057, model.gateway #7 DETACHED warm server via Win32_Process.Create, commit f8c961a; warm reuse load_ms ~1 vs ~1200 cold, per-call gpu lease keeps <=1 server on the GPU, 0 orphans). Phase 3 auto-ramp controller is the next unit -- a ready escalation pack exists (fo-4 worker I: modules/31-frontier-bridge/runtime/artifacts/d9df215c.../governor-phase3-escalation.md).
- A deterministic **goal-satisfied / repeat-action** terminator (the D-0032 #1 follow-on) would
  further harden termination independent of tier.
- Calibrated decision confidence (today's 0.55 is a heuristic) would give the ramp a better
  "am I actually solving this?" signal than status alone.
