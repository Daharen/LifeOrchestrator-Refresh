# Work Order: Resource Lease / Lock (`res.lease`)

**Contract version targeted:** 0.2 · **Author:** Claude (Cowork), 2026-07-27 · **Roadmap entry:** `MODULE_ROADMAP.md` -> Build priority (the resource-arbitration lock/lease layer, D-0050/D-0051)

### Problem being solved
The project wants to run **several Claude instances driving this one box concurrently** (D-0050 multi-instance
buildout) and to build a **fan-out orchestrator** (D-0051) on top of that. Concurrency is currently unsafe:
every model module is `parallel_safe:false` (one `llama-server` / one diffusers pipeline at a time — the 11 GB
GPU cannot host two model runs), git `index.lock` collisions have already bitten (D-0048/D-0049), and two
instances editing a shared core-doc (CURRENT_STATE, etc.) would clobber each other. There is no coordination
primitive. This unit builds the smallest one: a filesystem **lease/lock** that N processes on this single
machine use to arbitrate contended resources — the hard prerequisite the multi-instance direction named.

### Immediate practical use
- **GPU lease** (`gpu`): a model module / `agent.local` / a Widget acquires `gpu` before starting a
  `llama-server` or a diffusers pipeline and releases it after — so two instances never fight for VRAM.
- **git/commit lock** (`git`): `dev.ship` (and any git-writing step) acquires `git` around `git add`/`commit`
  so two commits never collide on `.git/index.lock`.
- **doc-ownership** (`doc:<path>`): an instance acquires `doc:CURRENT_STATE.md` before a core-doc edit so two
  instances do not lose each other's edits.
The **fan-out orchestrator** (next unit) is the primary consumer: its N workers coordinate through these leases.

### Explicit scope (in)
- One conforming skill `res.lease` (single `Invoke-ResLease.ps1`, the fs.manage/doc.io single-file pattern).
- Actions: **acquire**, **release**, **renew**, **status**, **list** (one action per invocation).
- A **generic named resource** (any string). Conventional names documented: `gpu`, `git`, `doc:<path>`.
- **Atomic** reservation via `FileMode.CreateNew` (open(O_CREAT|O_EXCL) / CREATE_NEW — atomic-fail-if-exists on
  BOTH Linux and Windows, so the cloud gate is meaningful).
- **TTL + expiry**: a lease carries `expires_at_utc`; an expired lease is reclaimable. **Renew** extends it.
- **Race-safe stale reclaim**: reclaim = an atomic rename of the stale lease aside (a rename CAS on the source —
  exactly one reclaimer wins), then retry the create.
- **Holder identity**: a stable `holder` (from `$env:LIFEORCH_INSTANCE`, else `<host>:<pid>:<guid8>`); acquire
  returns a `lease_id` token; release/renew require it (or a matching holder) so a slow holder can never
  release/renew a lease that was already reclaimed by someone else.
- **Blocking or non-blocking acquire**: `-WaitSeconds` (0 = try once; N = poll up to N seconds).
- **Same-holder re-attach**: acquiring a live lease you already hold (same `holder`) returns your existing
  `lease_id` with `already_held:true` (crash-recovery for the same instance).
- A shared **lease directory** (`runtime/leases/`, resolved identically by every process; `$env:LIFEORCH_LEASE_DIR`
  or `-LeaseDir` override).
- Dual-mode test harness (real skill on the cloud gate + live via the executor) INCLUDING a **concurrency /
  mutual-exclusion** test (N parallel acquirers of one resource -> exactly one wins) and a **stale-reclaim** test.

### Non-goals (out — do NOT build)
- **Wiring** the lease into `model.gateway`/`agent.local`/`dev.ship`/the doc-edit flow (that touches central
  `parallel_safe:false` modules; it is the immediate FOLLOW-ON, done per-consumer, not here). This unit ships
  the primitive + the convention; consumers adopt it next.
- The **fan-out orchestrator** (the next unit; it consumes this).
- A **fair FIFO queue** / priority / reader-writer locks (MVP is TTL + retry, not ordered fairness).
- Cross-machine / networked locks, an HTTP lock service, or an executor-daemon lease concept (D-0003: stay on
  atomic filesystem ops on one volume).
- Deadlock detection across multiple held resources (callers acquire in a documented order instead).

### Dependencies
- Modules: none at runtime (a standalone primitive). Consumed later by `agent.local` #21, `dev.ship` (Module 0),
  the fan-out orchestrator. · Tools/models: none. · Contract features: the standard envelope, `-InputsJson`,
  `-ArtifactRoot`.

### Skill contract requirements
- `skill_id: res.lease`, `name: Resource Lease / Lock`, `version: 0.1.0`, `determinism: deterministic`
  (no model; `confidence:null`, empty `model_provenance`), `parallel_safe: true` (it is DESIGNED for concurrent
  invocation — that is the whole point; concurrent ops on the same resource are exactly what the atomic
  primitive serializes), `batch: false`, `streaming: false`.
- NOT a review-queue producer (the canonical `review_queue.jsonl` + the ten-producer set are untouched).

### Inputs and outputs
- **Inputs:** `action` (acquire|release|renew|status|list, required), `resource` (string; required except for
  list), `holder` (string; default stable id), `ttl_seconds` (int, default 120), `wait_seconds` (number,
  default 0), `lease_id` (string; release/renew), `note` (string), `lease_dir` (string; override).
- **Outputs (`result`):**
  - acquire -> `{action, resource, acquired, lease_id, holder, expires_at_utc, ttl_seconds, waited_ms, reclaimed_stale, already_held, held_by, held_expires_at_utc}`
  - release -> `{action, resource, released, reason, held_by}`
  - renew   -> `{action, resource, renewed, lease_id, expires_at_utc, renew_count, reason, held_by}`
  - status  -> `{action, resource, exists, held, stale, holder, lease_id, expires_at_utc, seconds_remaining}`
  - list    -> `{action, lease_dir, count, leases:[{resource, holder, lease_id, expires_at_utc, held, stale, seconds_remaining}]}`
- A non-blocking acquire that loses is `status:"ok"` with `acquired:false` (a normal outcome, not an error).
  Errors are reserved for bad inputs / IO faults (`missing_parameter`, `invalid_action`, `invalid_inputs_json`).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` -> `reslease.json` (the action result), `reslease.md`, `stderr.txt`.
- `runtime/leases/` -> the shared lease files `<sanitized-resource>-<hash8>.lease` (gitignored).

### Proposed implementation
- **Language:** PowerShell + .NET (like `doc.io`/`fs.manage`) — pure, cross-platform `System.IO`, no external
  binary/model. **Why:** the atomic primitive (`File.Open(..CreateNew..)`) and rename-CAS are .NET calls that
  behave identically on the cloud Linux gate and the Windows box, so the real skill runs on both (strongest gate).
- Atomic acquire: `File.Open(path, CreateNew, Write, None)` -> write the lease JSON -> close. Fail (IOException)
  = already held. Stale reclaim: `File.Move(path, path+".reclaim-<lid>")` (source-rename CAS) then retry create.
  Reader opens `FileShare.ReadWrite`; an empty/unparseable lease (a partial write mid-create) is treated as live
  until `mtime + grace`, so an abandoned partial write is reclaimed quickly without a torn read.

### External tools or models
- None. `pwsh>=7.4` only (already on the box; installed in the cloud gate).

### Installation steps
- None (pure PowerShell). Cloud gate: install pwsh 7.4.6 + run the harness.

### Tests
- **Direct/cloud (real skill, OS-portable, ASCII-only):** acquire-free; second acquire non-blocking -> busy;
  release (matching lease_id) then re-acquire; release with wrong lease_id -> refused; renew extends + renew
  with wrong id refused; **TTL expiry -> stale reclaim** (ttl=1, sleep, reclaim); status/list; blocking acquire
  unblocks when the holder releases; **CONCURRENCY: N parallel acquirers -> exactly one `acquired:true`**;
  same-holder re-attach; error paths; the Module 1 wrapper.
- **Through the executor (`-Live`):** the identical harness + a real cross-process concurrency run on the box.

### MVP acceptance criteria
- [ ] Acquire/release/renew/status/list all return schema-valid envelopes.
- [ ] Two non-blocking acquirers of one resource: exactly one gets it; the other reports `acquired:false` + `held_by`.
- [ ] A released lease is immediately re-acquirable; a wrong-lease_id release/renew is refused.
- [ ] An expired lease is reclaimed by the next acquirer (`reclaimed_stale:true`); a live lease is not.
- [ ] **N (>=5) simultaneous acquirers -> exactly one winner** (live, on the box).
- [ ] Cloud gate green (real skill) and `-Live` green via the executor; shipped byte-exact + AST-clean via dev.ship.
- [ ] Not a review producer (canonical queue before==after); 0 orphaned processes.

### Manual verification procedure
- From two shells, `Invoke-ResLease.ps1 -Action acquire -Resource gpu -Holder A` in one; the same in the other
  with `-Holder B` -> B reports `acquired:false held_by=A`. Release from A; B (with `-WaitSeconds 10`) acquires.

### Documentation requirements
- Skill `README.md` (the convention: resource names, the acquire->work->release lifecycle, the acquire-order
  rule) + `skill.json` + example invocation/result.

### Registry updates
- Add a `res.lease` skill entry to `TOOL_MODEL_REGISTRY.md` (status, location, invocation, last test).

### State updates
- Update `CURRENT_STATE.md` (active unit -> shipped), `MODULE_ROADMAP.md` (the lock/lease layer -> MVP complete),
  a `DECISION_LOG.md` D-entry, `HANDOFF.md` (next unit -> the fan-out orchestrator), `REVIEW_QUEUE.md` (a
  non-producer note).

### Known follow-on work
- Wire `gpu` into `model.gateway`/the model modules and `git` into `dev.ship`; wire `doc:<path>` into the
  core-doc edit flow. Build the **fan-out orchestrator** on top. Fair FIFO/priority queuing; a warm-server
  lease that outlives one call (Governor Phase 2); a `held`-count for re-entrant multi-hold; auto-renew helper.

### STOP conditions
- Scope would exceed the "Explicit scope" list (esp. do NOT start wiring consumers or the orchestrator).
- MVP acceptance is met — stop; do not start the next unit.
