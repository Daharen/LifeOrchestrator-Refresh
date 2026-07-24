# MODULE_WORK_ORDER_TEMPLATE

Copy this into the module's own folder as `modules/<NN>-<name>/WORK_ORDER.md`. A fresh Claude instance normally receives
**only** the hot-context docs plus one filled-in work order. Keep it bounded — the point is to prevent
scope creep, not to specify the universe.

---

## Work Order: <Module Name> (`<module.id>`)

**Contract version targeted:** 0.1 · **Author:** <agent/date> · **Roadmap entry:** `MODULE_ROADMAP.md#<id>`

### Problem being solved
<One paragraph. What concrete gap does this close?>

### Immediate practical use
<Who calls this and to do what, this week — not eventually.>

### Explicit scope (in)
- <bullet> … <the smallest set that is genuinely useful>

### Non-goals (out — do NOT build)
- <bullet> … <the tempting adjacent work that belongs in a later module/work order>

### Dependencies
- Modules: <ids> · Tools/models: <registry ids> · Contract features: <fields used>

### Skill contract requirements
- `skill_id`, `name`, `version`, `determinism`, `parallel_safe`, `batch`, `streaming` values.
- Result `result` shape; whether `confidence`/`model_provenance` are populated; artifact kinds.

### Inputs and outputs
- **Inputs:** <name/type/required/default, per contract>
- **Outputs:** <shape of `result`; artifact files and kinds>

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → <list expected files>

### Proposed implementation
- **Language:** <C++ / Python / PowerShell / wrap existing binary> and **why** (per language policy).
- <Short approach; wrap existing tools where they already solve it.>

### External tools or models
- <what must exist; check `TOOL_MODEL_REGISTRY.md` first — do not reinstall what is present>

### Installation steps
- <exact, reproducible; prefer no-admin; record versions>

### Tests
- **Direct:** <how to run the skill standalone and assert a schema-valid envelope>
- **Through the executor:** <submit a task package; assert `result.json` + artifacts>

### MVP acceptance criteria
- <checklist; each item objectively verifiable — the "done" definition>

### Manual verification procedure
- <steps a human runs to confirm it really works>

### Documentation requirements
- Skill `README.md` + `skill.json` manifest + example invocation/result.

### Registry updates
- Add/refresh the `TOOL_MODEL_REGISTRY.md` entry (status, location, invocation, last test).

### State updates
- Update `CURRENT_STATE.md` and the module's `MODULE_ROADMAP.md` status.

### Known follow-on work
- <deferred items → future work orders / roadmap, NOT this session>

### STOP conditions (when to halt instead of expanding)
- Scope would exceed the "Explicit scope" list above.
- A dependency is missing/broken and installing it is itself non-trivial.
- The contract lacks something this module needs (stop, propose the contract change, do not freelance it).
- MVP acceptance is met — **stop; do not start the next module.**
