# VERIFY-RUNBOOK -- GPU-dependent bring-up verification (run AFTER this wave)

Portability / new-machine bring-up, Stage-1 (ops/setup, FANOUT_AGENT_002, plan fo-14-5ea064b6).

This unit ran the **CPU-only** verify pass live (config resolves, repo paths exist, the generated
`out/models.machine.json` is schema-valid, executor heartbeat fresh + `degraded:false`). It did **NOT**
run any GPU / model job: the single RTX 2080 Ti was occupied by the concurrent GPU-lane worker and this
unit is CPU-only by contract. The GPU-dependent steps below are the remainder of the bring-up verify --
an operator runs them once the GPU is free (or on a freshly-relocated box).

Do not run these while a GPU-lane worker holds the card. Acquire the `res.lease` **gpu** lease first (the
model modules are `parallel_safe:false`), and assert **0 orphaned `llama-server`** after each step.

## 0. Preconditions

1. Repo + F: data-root staged on the target box (see `out/staging-plan.txt` for the download plan).
2. Executor running, heartbeat fresh: `type modules\00-bootstrap-executor\runtime\control\heartbeat.json`
   -> `degraded:false`, `poll_error_streak:0`, `stuck_finalize_count:0`. Or run the CPU verify:
   `pwsh -NoProfile -File ops\setup\setup.ps1 -Action verify` -> `verify.ok = true`.
3. The machine-specific registry reviewed: open `ops/setup/out/models.machine.json` and confirm the
   repointed paths + `gpu_layers` / strong-tier quant pick match the target card. **Applying** it (copying
   the wired-LLM entries into `modules/07-model-gateway/models.json`) is a **model-gateway (#7) owner /
   GPU-lane** action under the gpu lease -- it is explicitly OUT OF SCOPE for this CPU unit, which only
   writes the staging copy under `ops/setup/out/`. Re-run Module 7 tests (28/28 + warm 23/23) after any
   `models.json` change.

## 1. Strong-tier smoke generation

Confirm the resident strong tier loads and returns clean, non-empty JSON on the new card.

```
pwsh -NoProfile -File modules\07-model-gateway\Invoke-ModelGateway.ps1 -Tier strong -Prompt "Reply with the single word: ready." -MaxTokens 32
```

Expect: envelope `status:"ok"`, a non-empty `result` (the 9B is `no_think`, so terse content, not an empty
`finish=length`), `model_provenance` naming `llm.strong.qwen3p5-9b` on engine b10092, and **0 orphaned
`llama-server`** afterward (`Get-Process llama-server` -> none, since the gateway server is detached/warm and
reaped on teardown). A cold first load can take a few seconds; pass a longer `-LoadTimeoutSec` if needed.

If it returns empty at `finish_reason:"length"`, the `no_think` flag / engine pin is wrong for this box --
recheck the `llm.strong.qwen3p5-9b` entry (`no_think:true`, `engine_path` -> the b10092 build) in the
applied `models.json`.

## 2. S0 6/6 calibration (governor)

The governor's Stage-1 calibration: at epoch **S0** the resident 9B must answer the 6-item calibration set
6/6, where the 3B floor scores ~4/6 (the D-0059 result). S0 needs **>= ~1024-2048 generation tokens** or the
9B returns empty -- a HARD trigger. Run the calibration exactly as documented in
`core-docs/ADAPTIVE_RESOURCE_GOVERNOR.md` (the `-AutoRamp` M0 -> M1 -> S0 ladder; `agent.local` #21 with a
pre-frozen `lifeorch.goal_verification/0.1` success contract), for example a routed goal that ramps to S0:

```
pwsh -NoProfile -File modules\21-agent-local\Invoke-AgentLocal.ps1 -Goal "<the S0 calibration goal>" -Route -Profile floor -AutoRamp
```

Expect: the S0 rung reaches **6/6** on the resident 9B (Q5_K_M, ctx 8192) -- apples-to-apples with the prior
Q4 calibration (context kept identical, D-0062). Record the score. Anything below 6/6 on S0 means the strong
tier is not performing as on the reference box -- re-tune `gpu_layers` / context for the new card (start from
`out/models.machine.json`'s sizing, then sweep as Module 9 did for the 27B) before trusting the ladder.

## 3. Sign-off

Record, in the bring-up notes / `DECISION_LOG` (orchestrator, not this worker):

- strong-tier smoke: pass/fail + tok/s;
- S0 calibration: N/6;
- 0-orphan assertion after each GPU step;
- any `gpu_layers` retune vs the generated `models.machine.json` starting point.

Only after 1 + 2 pass is the relocated stack considered GPU-live. On a similar box (same username + F:
layout + similar-VRAM GPU) these should pass unchanged; a very different card is a re-tune, not a redesign.
