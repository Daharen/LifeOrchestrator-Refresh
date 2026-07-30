# WORK ORDER (research-staged) — strong-tier preflight (`route.tools` #27)

**Staged in `claude/research/` at Nicholas's instruction** (2026-07-30). Revision **R3** of the
self-tasking-orchestration trajectory review
(`claude/research/2026-07-30-self-tasking-orchestration-trajectory-review.md` §6). Consumed by R4. When
promoted, copy into `modules/27-route-tools/WORK_ORDER.md`.

---

## Work Order: strong-tier preflight (`route.tools` #27, consumer `agent.local` #21)

**Contract version targeted:** 0.1 · **Author:** Claude (Opus, review session) 2026-07-30 ·
**Roadmap entry:** `MODULE_ROADMAP.md#27`

### Problem being solved

The vision wants a preflight "**of the exact same strength** as the orchestrator" to pick which tools to
delegate. Today `route.tools` #27 runs its tool-selection at the **MID (3B)** tier; `strong` was originally
HARD-refused (empty 27B output) and since D-0043 only soft-warns. But the strong tier is now the
GPU-resident 9B, and the governor already proved (Exp 1) the 9B routes **more accurately** than mid — subject
to the S0 constraint that the 9B reasons in-content and returns **empty below ~1024 tokens**. So a
same-strength preflight is feasible and is a config/design change, not a new capability.

### Immediate practical use

- Gives the R4 baton-pass demonstrator a same-strength tool-selection stage.
- Gives `agent.local -Route` a higher-accuracy opt-in routing path today, independent of R4.

### Explicit scope (in)

- An **opt-in strong preflight path** on `route.tools`: run the 9B (`-Tier strong`) with `no_think`,
  **≥1024 (use 2048) max tokens**, temp 0, fixed seed, under the whole-task `gpu` lease via
  `Ensure-ResidentModel(9B)`.
- **Keep the deterministic catalog gate** (drop any non-catalog id) — injection-resistant, unchanged.
- Return the minimal validated tool-id subset + provenance (`preflight_tier`, `tokens`, empty-guard state).
- **Empty/length-truncated strong output → fall back to mid** (never worse than today).

### Non-goals (out — do NOT build)

- Multi-stage plan decomposition / which-sub-agents-in-what-order — that is R4.
- Changing the default (mid stays the default; strong is opt-in).
- The sequential orchestrator; any `agent.local` change beyond consuming the new path.

### Dependencies

- Modules: `route.tools` #27, `model.gateway` #7 (strong 9B, ≥1024 tok, `no_think`), `res.lease` #29 gpu /
  the pool manager. Governor S0 lessons (ADAPTIVE_RESOURCE_GOVERNOR §5). R1 (lease split) is **not** a hard
  prereq — this works under the current whole-task lease — but composes with it.

### Skill contract requirements

- `route.tools`: det mixed (one #7 call + the deterministic gate); `parallel_safe:false` (GPU). New result
  fields: `preflight_tier`, `tokens`, `empty_fell_back_to_mid`.

### Inputs and outputs

- **Inputs:** existing `route.tools` request + `-Tier strong` (or `-Preflight strong`).
- **Outputs:** the minimal validated tool-id subset + the provenance fields above.

### Artifact structure

- `modules/27-route-tools/runtime/artifacts/<invocation_id>/` — request, raw model output, gated subset.

### Proposed implementation

- **Language:** PowerShell (matches #27). Reuse the S0 call shape from the governor (9B, `no_think`, 2048
  tok). The catalog gate is unchanged.

### External tools or models

- None new (9B strong tier already wired; `TOOL_MODEL_REGISTRY.md`).

### Installation steps

- None. Ship via `dev.ship`.

### Tests

- **Off-machine (mock):** strong path selectable; empty/truncated → mid fallback; catalog gate still drops
  non-catalog ids.
- **Live (executor):** 9B strong routing on the Exp-1 / calibration set vs mid — report the accuracy delta;
  assert non-empty at 2048 tok; 0 orphans.

### MVP acceptance criteria

- Strong preflight returns a valid **non-empty** tool subset at ≥1024 tok on the calibration set. ✅
- Empty/truncated → mid fallback. ✅ Catalog gate intact. ✅ Default unchanged. ✅
- Measured accuracy ≥ mid (Exp 1 predicts yes). ✅

### Manual verification procedure

- Run the calibration goals through both mid and strong preflight; confirm strong ≥ mid and never empty at
  2048 tok.

### Documentation requirements

- `route.tools` `README.md` + `skill.json` (the opt-in strong path + fallback); a `DECISION_LOG.md` entry +
  index row.

### Registry updates

- `TOOL_MODEL_REGISTRY.md` #27 entry: the strong preflight path, last test.

### State updates

- `CURRENT_STATE.md` + `MODULE_ROADMAP.md` #27 status.

### Known follow-on work

- Per-stage tool allocation for R4; calibrated routing confidence; a `route.tasks` #24 generalization.

### STOP conditions

- If strong routing does **not** beat mid on the calibration set → keep it opt-in + document; do not make it
  the default.
- Scope would exceed which-tools selection (decomposition is R4) → stop.
- MVP acceptance met → stop.
