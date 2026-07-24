# DECISION_LOG

Owns **architectural rationale** so no instance must reread every discussion. Append-only; newest last.
Read only when a prior decision may bear on your task. **Entry fields:** id · date · decision · reason ·
alternatives · consequences · affects · state (provisional | locked) · revisit-if.

---

### D-0001 — Trusted bootstrap executor, not a sandbox
- **date:** 2026-07-24 · **state:** locked
- **decision:** The initial execution channel is a trust-based filesystem-queue executor. Queue-write
  access equals the Windows user's authority; no allowlists/approvals in-band.
- **reason:** Speed and unblocking real local work now; sandboxing is a large separate effort with its
  own failure modes. Honestly labeled risk beats a false safety claim.
- **alternatives:** OS sandbox, container, restricted runspace, HTTP service with auth.
- **consequences:** Only trusted agents/processes may write the queue. Modules are **forbidden** to add
  concealment, shutdown resistance, unauthorized propagation, monitoring evasion, or covert persistence.
- **affects:** Module 0, `PROJECT_DIRECTION.md`. · **revisit-if:** untrusted submitters become possible,
  or the executor is exposed beyond the local user.

### D-0002 — Isolated skill processes before persistent sessions
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Skills and tasks run as fresh isolated processes for now; no long-lived shared runspaces.
- **reason:** Simplicity, crash isolation, restart-recoverability; avoids shared-state bugs early.
- **alternatives:** persistent PowerShell sessions / warm model workers.
- **consequences:** Per-invocation startup cost (notably higher with the dotnet-tool pwsh shim).
- **affects:** Module 0, Module 1. · **revisit-if:** startup latency dominates a real workload
  (e.g. model warm-up) — then introduce persistent workers for that skill only.

### D-0003 — Filesystem queue before any local HTTP service
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Coordinate via atomic directory moves on one volume; no local network listener yet.
- **reason:** Zero infra, inspectable, restart-safe, no ports/auth to secure.
- **alternatives:** local HTTP/gRPC service; named pipes.
- **consequences:** Poll latency; single-volume requirement. · **affects:** Module 0.
  · **revisit-if:** cross-machine or low-latency streaming coordination is needed.

### D-0004 — Skill contract provides modularity; language does not
- **date:** 2026-07-24 · **state:** locked
- **decision:** Modularity is defined by `SKILL_CONTRACT.md` (manifest + result envelope), not by
  implementation language. C++ preferred for durable/central components; Python/PowerShell/wrapped
  binaries acceptable for faster/better MVPs.
- **reason:** Lets us ship useful MVPs immediately while keeping the option to reimplement in C++ later
  behind a stable interface.
- **alternatives:** mandate C++ (too slow to MVP); mandate one scripting language (poor fit for models).
- **affects:** all modules, `PROJECT_DIRECTION.md`, `SKILL_CONTRACT.md`. · **revisit-if:** the contract
  proves insufficient to hide an implementation swap.

### D-0005 — Contract starts minimal; grows only on real need
- **date:** 2026-07-24 · **state:** locked
- **decision:** `SKILL_CONTRACT.md` v0.1 is intentionally small. Extend only when a real module exposes
  a missing requirement; bump the contract version and log it here.
- **reason:** Avoids a speculative plugin framework nobody has stressed yet.
- **affects:** `SKILL_CONTRACT.md`, Module 1. · **revisit-if:** each new contract change.

### D-0006 — Long-horizon Proteus deferred to cold reference
- **date:** 2026-07-24 · **state:** **superseded by D-0010** (was: locked)
- **decision:** Deterministic canonical collapse, world simulation, projection, and structured memory
  are **not** near-term admission requirements. Their architecture lives in `cold-reference/` and is not
  loaded into ordinary module sessions.
- **reason:** Keep every fresh instance's context light and focused on shippable MVPs.
- **affects:** `PROJECT_DIRECTION.md`, `START_HERE.md`. · **revisit-if:** a module's value genuinely
  depends on one of those systems.

### D-0007 — Two-tier local model use with a review queue
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Weak local models do bulk classification/sorting/extraction; a stronger local model
  reviews only flagged/low-confidence/contradictory items via `REVIEW_QUEUE.md`; frontier models handle
  the hardest judgment and adjudication.
- **reason:** Proven cheaper in prior database work (on the separate Proteus game) than having strong models redo whole sets.
- **affects:** Modules 7–9, 24; `REVIEW_QUEUE.md`. · **revisit-if:** local model quality shifts enough to
  change the tier boundaries.

### D-0008 — PowerShell 7 installed per-user via .NET global tool (pinned 7.4.6)
- **date:** 2026-07-24 · **state:** provisional
- **decision:** pwsh 7 provisioned as a .NET global tool (no admin), pinned to 7.4.6.
- **reason:** No admin available; the latest tool package is malformed; this unblocked testing immediately.
- **consequences:** pwsh only on the per-user PATH; the shim reports as `dotnet.exe` (pass explicit
  `-PwshPath`). · **affects:** `CURRENT_STATE.md`, `TOOL_MODEL_REGISTRY.md`, Module 0. · **revisit-if:**
  a system-wide winget/MSI install is preferred for broader use.

### D-0009 — Module 1 skill conventions (provisional, pending contract absorption)
- **date:** 2026-07-24 · **state:** provisional
- **decision:** Building the first reference skill (`ref.echo`) settled three conventions not spelled out
  in `SKILL_CONTRACT.md` v0.1: (1) a skill's artifact root resolves relative to the skill folder
  (`$PSScriptRoot/runtime/artifacts/<invocation_id>/`), and the envelope always reports **absolute**
  artifact paths; (2) skills accept a generic `-InputsJson '<json object>'` argument (in addition to any
  named params) so a generic wrapper need not know each skill's parameters; (3) the wrapper emits a
  `lifeorch.skill.invocation_report/0.1` object `{manifest_valid, manifest_errors, invoked, exit_code,
  envelope_valid, envelope_errors, envelope, stderr_tail}`.
- **reason:** Needed to make `ref.echo` and the generic `Invoke-Skill.ps1` interoperate without expanding
  the contract prematurely (D-0005). Kept out of the normative contract until a second skill confirms them.
- **alternatives:** amend `SKILL_CONTRACT.md` now (risked over-fitting to one skill); per-skill bespoke
  arg passing (defeats a generic wrapper).
- **consequences:** `SKILL_CONTRACT.md` stays v0.1 unchanged; these conventions live in the Module 1
  README + this entry. Fold them in (and bump the contract version) once Module 2 (`fs.observer`) exercises
  them. · **affects:** `SKILL_CONTRACT.md`, Module 1, Module 2. · **revisit-if:** Module 2 needs a different
  arg-passing or artifact-root rule.


### D-0010 — Disentangle: this project is Life Orchestrator, separate from the Proteus game
- **date:** 2026-07-24 · **state:** locked
- **decision:** This refresh repo is **Life Orchestrator** (an AI assistant / local-skills control plane),
  not Project Proteus. "Project Proteus" is a separate systemic-RPG game; the two were accidentally
  cross-named. Actions taken: rebrand project + repo folder to Life Orchestrator (folder
  `Project-Proteus-Refresh` -> `LifeOrchestrator-Refresh`), rename schema IDs `proteus.skill.*`/`proteus.review.*`
  -> `lifeorch.*`, remove the game "long-horizon vision" and delete the `cold-reference/` slot.
- **reason:** Genuinely different projects with no overlapping subject matter; the only shared thing was the
  engineering *value* of determinism. Correct the labels now, while only one module exists.
- **reference sources (kept, not built here):** the earlier assistant codebase `LifeOrchestrator\repo` — to
  fold in later when implementation makes sense; the Proteus game (`Project-Proteus-src`) — unrelated.
- **supersedes:** D-0006 (the long-horizon Proteus / cold-reference deferral was game vision, now out of scope).
- **affects:** all docs, `SKILL_CONTRACT.md` schema IDs, Module 1 code, repo/folder name. · **revisit-if:**
  we ever intentionally re-import game concepts (not expected).
