# Direct-provision briefing to the i18 fan-out orchestrator (2026-07-30)

**What this is / paper trail.** This is the durable record of an **out-of-band direct provision** to the
fan-out orchestrator: Nicholas pasted the prompt below straight into the orchestrator session (mid-i18
setup, while its device bridge was reconnecting), instead of the normal file-courier + `-Action report`
channel. It captures a self-tasking-orchestration trajectory review + a staged R1→R4 work-order chain + a
ready frontier-review pack produced by a separate Cowork review session (Claude Opus, 2026-07-30). Because
this bypassed the usual channel (no `plan_id`, no worker report), the prompt's **step 1 is to log the
provision** so the audit trail stays intact. The exact prompt body follows.

---

## Exact prompt provided to the orchestrator

Orchestrator — **direct provision from Nicholas, out-of-band** (not a fan-out worker report; your device
bridge is reconnecting, you are mid-i18 setup). A separate Cowork review session (Claude Opus, 2026-07-30)
produced a direction assessment + a staged **R1→R4** work-order chain + a ready frontier-review pack, all in
the attached Project under `claude/research/`. They are **Project-only (not yet on disk)**. Treat them as a
**proposal for your judgment**, not committed work — the review session did not and cannot drive you.

**Files (Project paths):**
- `claude/research/2026-07-30-self-tasking-orchestration-trajectory-review.md` — the direction assessment
  (can the project support a self-tasking, sequential single-GPU baton-pass; §2 = the whole-task-lease
  misalignment you flagged; §6 = revisions R1–R6).
- `claude/research/2026-07-30-work-order-gpu-lease-split.md` — **R1 (keystone):** split the `gpu` lease into
  an execution/transition lease + a revocable residency pin; folds in findings 1/13/14. Single-worker infra
  wave; **already your i18 findings-13/14 CPU candidate.**
- `claude/research/2026-07-30-work-order-strong-preflight.md` — **R3:** an opt-in strong-tier (9B) preflight
  on `route.tools` #27.
- `claude/research/2026-07-30-work-order-baton-pass-minimal-slice.md` — **R4:** a fixed 3-stage demonstrator
  of the baton-pass (**HARD prereq: R1**).
- `claude/research/2026-07-30-frontier-prompt-self-tasking-orchestration.md` — a ready-to-courier
  `frontier.bridge` pack prompt reviewing the review + R1; a shortcut for your frontier lane if you concur.
- `claude/research/2026-07-30-orchestrator-direct-provision-briefing.md` — this record.

**Do, in order:**

1. **LOG THIS FIRST (irregular-channel audit trail).** It arrived by direct provision — no `plan_id`, no
   `-Action report`. Before acting, record provenance: append a new `D-00NN` entry (next id) to
   `DECISION_LOG.md` + its row to `DECISION_LOG_INDEX.md` — *"Out-of-band direct provision (2026-07-30 Cowork
   review session): staged trajectory review + R1–R4 work orders + a frontier pack in `claude/research/`;
   Project-only, pending mirror + evaluation."* If the bridge is still down, record it in your handoff
   working-draft now and commit it with the mirror (step 2) once reconnected. Do not let it enter a wave
   undocumented.
2. **WHEN RECONNECTED, MIRROR + COMMIT.** These docs live in the Project only. Mirror them to
   `core-docs/research/` on disk and commit under the `git` lease (**Project→disk** direction: `project_read`
   each, write to disk via an executor task, **preserve per-file EOL**, **named files only, NEVER
   `git add -A`**). Disk is canonical; until mirrored, a disk-first worker will not see them.
3. **EVALUATE (your call, per D-0050 + the i18 menu).** R1 is already your findings-13/14 CPU-lane candidate
   and doubles as the baton-pass keystone — decide whether to slot it into i18. **R3/R4 are downstream:** R4
   has a HARD prereq on R1; do **not** queue R4 without R1 landed. Nothing here overrides your judgment or
   the D-0051 boundary.
4. **FRONTIER LANE (optional).** If you want a second opinion before committing the direction, use
   `claude/research/2026-07-30-frontier-prompt-self-tasking-orchestration.md` as your `frontier.bridge` pack:
   `prompt` = that file's body, `paths` = the two primaries (mirror them to disk first so the paths resolve).
   Edit it if you disagree with its framing.

**Constraints reaffirmed (this provision changes none of them):** ≤1 GPU worker per wave; single-worker for
core infra (R1 = `res.lease` #29 = infra); workers `docs:[]`; you mirror core-docs; deliver worker prompts as
FILES. R1→R4 is a *proposed* chain, not an instruction to build all four.
