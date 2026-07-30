# WORK ORDER (research-staged) — minimal sequential baton-pass slice (the real #26, "baton-pass" mode)

**Staged in `claude/research/` at Nicholas's instruction** (2026-07-30). Revision **R4** of the
self-tasking-orchestration trajectory review
(`claude/research/2026-07-30-self-tasking-orchestration-trajectory-review.md` §5–§6) — the capstone
proof-of-concept. **HARD prereq: R1** (the GPU lease split). Uses **R3** (strong preflight). When promoted,
this becomes a NEW module (next free folder number) = the real `skill.orchestrator` #26 in baton-pass mode;
copy into `modules/<NN>-<name>/WORK_ORDER.md`.

---

## Work Order: minimal sequential baton-pass orchestrator (demonstrator)

**Contract version targeted:** 0.1 · **Author:** Claude (Opus, review session) 2026-07-30 ·
**Roadmap entry:** `MODULE_ROADMAP.md#26` (skill.orchestrator) — baton-pass mode

### Problem being solved

Nothing built today sequences **multiple local-model instantiations with per-stage GPU relinquish**.
`agent.local` #21 swaps its own brain-tier but drives deterministic tools; `orchestrate.fanout` #30 is
parallel/frontier/human-couriered and hard-barred from driving AI sessions (D-0051). This unit is the
**smallest slice that proves the baton-pass end-to-end on this box** — a FIXED demonstrator chain, not a
general planner — so the whole direction is de-risked before investing in the general #26.

### Immediate practical use

- A runnable proof that a local orchestrator can hold the GPU **only while executing**, **relinquish between
  stages**, **swap the resident model**, carry state idempotently, and close on a frozen success contract.
  This is the core mechanic behind the self-tasking vision.

### Explicit scope (in) — the FIXED demonstrator ONLY

- A new local sequential orchestrator (real #26, baton-pass mode), MVP = a **HARD-CODED 3-stage chain**:
  1. **strong preflight** (9B via R3) — confirm the tool subset / plan.
  2. **`gen.image` stage** (#23, a distinct GPU resident — the SD pipeline) — produce an artifact.
  3. **`fs.manage` placement** (#28, CPU, no model) — place the artifact.
- Between stage 1→2: **RELEASE the residency pin** (9B) → `Ensure-ResidentModel(image pipeline)` →
  **reacquire** the execution lease — a real relinquish + swap. Between 2→3: release the GPU entirely
  (stage 3 is CPU).
- **Carry state across stages:** task-scoped idempotency keys (hash of tool-id + normalized args),
  resume-from-authoritative-state, refuse duplicate mutations (reuse the governor's guards).
- **Close on a PRE-FROZEN success contract** (`lifeorch.goal_verification/0.1`) — verified success or
  `completed_unverified`; never the model's own say-so.
- **Orchestrator context across the swap:** keep the transcript in RAM/disk and **re-ingest on resume** (NOT
  a KV restore across models — trajectory review §4); **measure the re-ingest cost.**

### Non-goals (out — do NOT build)

- General N-stage / dynamic decomposition; a planning DAG; the 20–30-stage pipeline.
- The DaVinci / NLE driving; the visual action-executor (#38).
- Running sub-agents hot / in parallel (physically impossible on 11 GB).
- New generator capabilities; changing `agent.local` defaults.
- **Driving another AI session** — this drives LOCAL models only; the D-0051 boundary is intact (state it in
  the module README so it is never confused with the fan-out orchestrator).

### Dependencies

- **Hard:** R1 (lease split, #29), R3 (strong preflight, #27). Also: `model.gateway` #7 pool manager,
  `agent.local` #21 (per-stage executor + idempotency/resume), `res.lease` #29, `gen.image` #23,
  `fs.manage` #28, the frozen-contract verifier.

### Skill contract requirements

- New skill; det mixed; `parallel_safe:false` (GPU); `batch:false`. Result = a per-stage record (`model_id`,
  swap timing, lease/pin events, artifact ids, contract verdict) + a governor-style trace.

### Inputs and outputs

- **Inputs:** a goal + a pre-frozen success contract (+ the fixed-chain flag for the MVP).
- **Outputs:** the per-stage record + trace + the final artifact placement + the contract verdict.

### Artifact structure

- `modules/<NN>-<name>/runtime/artifacts/<invocation_id>/` — per-stage records, the governor trace, the
  produced image, the placement result, the frozen contract + verdict.

### Proposed implementation

- **Language:** PowerShell (composes existing pwsh modules). Reuse `agent.local`'s loop + idempotency/resume;
  the pool manager for residency; the split lease (R1) for relinquish/reacquire.

### External tools or models

- None new (all present).

### Installation steps

- None. Ship via `dev.ship`.

### Tests

- **Off-machine (mock children + a lease/pool seam):** stage sequencing; the pin release + reacquire calls
  occur in order; idempotency refuses a duplicate mutation; contract gating (pass + `completed_unverified`).
- **Live (executor):** the real 3-stage chain — 9B preflight → **pin release → swap to the image pipeline**
  (record swap timing) → `gen.image` artifact → GPU release → `fs.manage` places it; the frozen contract
  passes; **0 orphaned `llama-server`/python**; lease + pin released; the re-ingest cost measured.

### MVP acceptance criteria

- The fixed chain completes end-to-end with a **REAL mid-task GPU relinquish + reacquire + model swap**. ✅
- State carried across stages; a duplicate mutation refused. ✅ Contract-verified close. ✅
- 0 orphans; lease + pin released; measured swap + re-ingest costs recorded. ✅
- **That is "done" — do not generalize.**

### Manual verification procedure

- Watch the trace: confirm the pin is released and reacquired between stages (not held whole-task), the swap
  actually happened, and the artifact landed where the contract requires.

### Documentation requirements

- Module `README.md` + `skill.json` + the D-0051-boundary note; a `DECISION_LOG.md` entry + index row;
  the measured swap + re-ingest numbers.

### Registry updates

- `TOOL_MODEL_REGISTRY.md` new entry.

### State updates

- `CURRENT_STATE.md` + `MODULE_ROADMAP.md` #26 status (baton-pass MVP).

### Known follow-on work

- The general N-stage planner; dynamic decomposition; more stage types (video/audio/tts/stt/vlm); the
  DaVinci pipeline; swap-minimizing stage ordering (R5); slot save/restore for same-model returns (R6).

### STOP conditions

- **R1 not landed → cannot start** (hard dep).
- If a **safe relinquish + reacquire cannot be demonstrated** → stop, report; R1 needs rework.
- Scope beyond the fixed 3-stage chain → stop; write it to the roadmap.
- MVP acceptance met → stop.
