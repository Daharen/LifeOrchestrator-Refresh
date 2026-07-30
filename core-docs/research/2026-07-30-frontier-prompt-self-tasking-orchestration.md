# Frontier-review pack (prompt) — self-tasking sequential-orchestration trajectory + the GPU-lease-split work order

**Purpose / paper trail.** This is the ready-to-courier `frontier.bridge` #31 pack **prompt** produced by the
2026-07-30 Cowork review session (Claude Opus), staged in `claude/research/` so the next fan-out orchestrator
iteration can find it and — if it agrees with the direction — use it as a shortcut instead of authoring the
pack prompt from scratch. It is a **pure pointer**: the reviewer reads the referenced docs and returns only an
assessment. The orchestrator drives the frontier lane per `FANOUT_ORCHESTRATOR_HANDOFF.md` §4 (`pack` →
courier → paste into the `.answer.md` return file → `read-return` → fold). Set the pack's `paths` to the two
primary docs below (mirror them to `core-docs/research/` on disk first — see the note at the end).

---

**Role.** You are an off-box frontier reviewer (GPT-5.x class) giving a second opinion for the **Life
Orchestrator** project (local-skills track on DESKTOP-PF5FFMF: RTX 2080 Ti **11 GB VRAM**, i9-9900KF, 64 GB
RAM, llama.cpp b8661 + b10092). A Cowork review session (Claude Opus) assessed whether the project can
support a **single strong local agent that tasks itself** — decomposing a goal, then running a **sequential,
single-GPU, unload/reload baton-pass** across many local-model instantiations (orchestrator → same-strength
preflight → per-stage executor agents, exactly one powerful model in VRAM at a time) — and drafted the
keystone work order (splitting the GPU lease). **Review both.** This is a design/direction second opinion, not
a code change.

**Do not restate the documents back to me.** Read them at the paths below and respond only with your
assessment, disagreements, and concrete additions.

## Read these (canonical on disk = `core-docs/…`; mirrored in the attached Project as `claude/…`)

1. **The trajectory review (primary):**
   `core-docs/research/2026-07-30-self-tasking-orchestration-trajectory-review.md`
   (Project: `claude/research/2026-07-30-self-tasking-orchestration-trajectory-review.md`)
2. **The keystone work order — GPU lease split (primary):**
   `core-docs/research/2026-07-30-work-order-gpu-lease-split.md`
   (Project: `claude/research/2026-07-30-work-order-gpu-lease-split.md`)
3. **Design context they build on (read as needed, don't re-summarize):**
   - `modules/07-model-gateway/WARM_POOL_DESIGN.md` — §1 measured swap economics, §4 lease composition,
     §9 the prior frontier opinion, §10 Stage-1.1 findings (esp. **1 fencing**, **2 GPU handoff**, **13 lease
     split**, **14 lock-order inversion**, **15 headroom confirmation**).
   - `core-docs/ADAPTIVE_RESOURCE_GOVERNOR.md` — §6 the whole-task-lease rule + monotonic model-affine epochs.
   - `core-docs/CURRENT_STATE.md` — measured hardware truth, warm-pool default-OFF status, gotchas.
   - `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` §4 — where the res.lease fencing wave (findings 13/14) already
     sits on the i18 candidate menu.

## Assess specifically

1. **Is the trajectory assessment correct?** Given the measured constraints (one ~7 GB model at a time; swaps
   GPU-upload-bound ~1.6–4.1 s and NOT reduced by RAM warmth; ~1 ms same-model reuse; KV never restorable
   across a different model), is anything in the review's §1–§4 wrong, overstated, or missing?
2. **Is the lease split the right keystone, and is the work order safe?** Execution/transition lease vs a
   revocable residency pin + `AcquirePreparedGpu` (evict-before-grant, WDDM-async-safe headroom confirmation)
   + fencing token + lock-order-inversion rejection. Any correctness hole — races, a way two owners co-exist,
   a way the next owner gets a freed lock but not freed VRAM, a Turing (cc 7.5) / WDDM pitfall, an executor
   re-wedge risk (the D-0055/56 class)?
3. **Sequencing.** Should the lease split, warm-pool default-ON, and the strong preflight be one wave or
   strictly ordered? Does closing findings 1/13/14 here actually unblock default-ON, or is the soak still the
   real gate?
4. **Direction call.** Pulling the #26 sequential local orchestrator forward *now* vs the current
   offload/audit-loop doctrine (D-0050, "one scoped unit per session," orchestration held long-horizon): wise
   or premature? If wise, what is the **minimal first slice** of the orchestrator that would prove the
   baton-pass end-to-end on this box (e.g., a 3-stage chain: strong preflight → gen.image stage → fs.manage
   placement, with a pin release + reacquire between stages)?
5. **The context cold-store reality.** The review claims "bring my context back" across a model swap is a
   prompt re-ingest, not a free VRAM restore (never restore KV across models; `--slot-save-path` only helps
   same-model returns). Correct? Any cheaper option we're missing on llama.cpp for this box?
6. **Anything the review or work order got materially wrong or omitted** for THIS hardware/architecture.

**Ethos:** be concrete and quantitative where you can; **negative results are first-class** — if the
direction is a mistake or the work order is unsafe, say so plainly and say why. Ground claims in the measured
facts in the docs above.

---

**Mirror note for the orchestrator.** As of the 2026-07-30 review session, the three docs referenced here
(this prompt + the two primaries) live in the **attached Project only** (`claude/research/…`), NOT yet on the
canonical disk repo. Before couriering with `paths`, mirror them to `core-docs/research/` on disk and commit
under the `git` lease (standard core-docs mirror, Project→disk direction), and fold a one-line pointer into
`CURRENT_STATE.md` → Unresolved questions (or the handoff §4 menu) so a disk-first session also finds them.
