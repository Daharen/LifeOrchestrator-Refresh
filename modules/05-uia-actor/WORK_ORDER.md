# Work Order: UI Automation Actor (`uia.actor`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork — Module 5 build session) / 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#5 uia.actor`

### Problem being solved
`uia.inspector` (Module 4) can *read* the accessible control tree and hand back stable per-element
descriptors (control type, name, automation id, and a child-index `path`), but nothing can yet *act* on
those elements. This module closes that gap: the **acting half** of UI Automation. Given a target window
and a locator that uniquely identifies one element, it performs exactly one UIA control-pattern action on
that element (invoke, toggle, select, expand, collapse, set-value, focus). It is the first skill with
side effects, so it is scoped narrowly and ships with a dry-run mode.

### Immediate practical use
An agent (frontier or local) inspects a window with `uia.inspector`, picks the element it wants (by its
`automation_id` / `name` / `control_type` / `path`), and calls `uia.actor` to press a button, tick a
checkbox, choose a list item, expand a tree node, type a value into a field, or focus a control — through
the accessible layer, without screenshots or synthetic mouse/keyboard input. This is what lets local
automation drive real Windows apps deterministically.

### Explicit scope (in)
- Resolve a **target** exactly like `uia.inspector`: `-Hwnd` | `-ProcessId` | `-Title` (glob), else the
  desktop root.
- Resolve a **single element** within that target by any combination of: `automation_id` (exact),
  `name` (glob), `control_type` (exact, e.g. `Button`), and `path` (the child-index path from the
  inspector; authoritative when supplied). Report ambiguity (>1 match) and not-found as structured errors.
- Perform **one** action via a UIA control pattern:
  - `invoke`   → InvokePattern.Invoke()
  - `toggle`   → TogglePattern.Toggle()          (before/after ToggleState captured)
  - `select`   → SelectionItemPattern.Select()    (before/after IsSelected)
  - `expand`   → ExpandCollapsePattern.Expand()   (before/after ExpandCollapseState)
  - `collapse` → ExpandCollapsePattern.Collapse()
  - `setvalue` → ValuePattern.SetValue(value)     (before/after Value; requires `value`, refuses read-only)
  - `focus`    → AutomationElement.SetFocus()      (after HasKeyboardFocus)
- **Dry-run / `-WhatIf`** (also `dry_run:true` in `-InputsJson`): resolve the element, determine the
  required pattern and whether it is supported/enabled, read current state, and report the *intended*
  action **without performing it** (`performed:false`, `actionable:<bool>`, `blockers[]`).
- Emit one contract-valid `lifeorch.skill.result/0.1` envelope on stdout; write `action.md` (human) +
  `action.json` (machine) artifacts. Reuse Module 1 validators and run through the executor.

### Non-goals (out — do NOT build)
- **No synthetic global input** — no SendKeys, `mouse_event`, `keybd_event`, `SetCursorPos`, or any
  simulated mouse/keyboard. UIA control patterns only. (If a target exposes no usable pattern, that is a
  structured `pattern_unsupported` error, not a fallback to clicking coordinates.)
- **No inspection features** — no tree dumps or search results beyond the minimum needed to resolve and
  confirm the one target element (that is Module 4's job; keep the halves separate).
- **No multi-action scripts / macros / sequences** — one action per invocation. Composition belongs to a
  later orchestration module (#26).
- **No window management** — no move/resize/minimize/close/foreground (that is a later `proc`/window
  concern, and WindowPattern/Transform acting is deliberately out of this MVP).
- **No waiting/retry/polling loops** for elements to appear — resolve against the current tree; absence is
  an error the caller can retry.
- **No concealment, persistence, propagation, or monitoring evasion** (executor hard prohibition). The
  skill runs once, in the foreground, as ordinary visible activity.

### Dependencies
- Modules: **1** (`SkillContract.psm1` validators, `Invoke-Skill.ps1` wrapper), **4** (`uia.inspector`
  produces the locators consumed here). Runs through Module **0** (executor).
- Tools/models: `pwsh>=7.4` (registry `pwsh`); managed UI Automation (`UIAutomationClient`,
  `UIAutomationTypes`) — already proven by Module 4. No models.
- Contract features: manifest `lifeorch.skill.manifest/0.1`; result `lifeorch.skill.result/0.1`;
  `-InputsJson` generic arg convention and artifact-root convention (DECISION_LOG D-0009).

### Skill contract requirements
- `skill_id` = `uia.actor`; `name` = `UI Automation Actor`; `version` = `0.1.0`;
  `determinism` = `deterministic` (definite operation, no model; `confidence` = null);
  `parallel_safe` = **false** (it mutates shared desktop UI — unlike the read-only siblings);
  `batch` = false; `streaming` = false.
- `result` shape: `{ target, action, dry_run, performed, actionable, requested_pattern,
  pattern_supported, locator, resolved_element, candidate_count, candidates[], before_state, after_state,
  blockers[] }`. `confidence` null; `model_provenance` empty. Artifacts: `action.md` (markdown),
  `action.json` (json).

### Inputs and outputs
- **Inputs** (named params and/or `-InputsJson`):
  - `hwnd` int (opt) · `pid` int (opt) · `title` string glob (opt) — target; else desktop root.
  - `action` string (**required**): invoke|toggle|select|expand|collapse|setvalue|focus (aliases
    `set-value`/`set_value` → setvalue).
  - `automation_id` string (opt, exact) · `name` string (opt, glob) · `control_type` string (opt, exact)
    · `path` string (opt, child-index path; authoritative when present). **At least one locator required.**
  - `value` string (required for `setvalue`).
  - `dry_run` bool (opt) / `-WhatIf` switch — preview only.
  - `depth` int (opt, default 12) · `max_elements` int (opt, default 3000) — bound the property search
    walk (ignored when `path` is supplied).
- **Outputs:** the `result` object above in the envelope; artifacts `action.md` + `action.json` under
  `runtime/artifacts/<invocation_id>/` (plus `stderr.txt`, `result.json` per convention).

### Artifact structure
- `runtime/artifacts/<invocation_id>/action.md`   — human summary (target, locator, resolved element,
  action, dry-run/performed, before/after state, blockers).
- `runtime/artifacts/<invocation_id>/action.json` — machine record: full result payload + schema tag.
- `runtime/artifacts/<invocation_id>/stderr.txt`, `result.json` — per contract.

### Proposed implementation
- **Language:** PowerShell (per language policy — Windows UI inspection/glue MVP; same stack as Module 4,
  wraps managed UI Automation via `Add-Type`).
- Approach: resolve target as in Module 4. If `path` given, navigate `FindAll(Children)` by index
  (identical ordering to the inspector, so paths compose). Else do the inspector's bounded DFS, keep the
  live `AutomationElement` beside each element record, and filter by the supplied locators; 0 → not_found,
  >1 → ambiguous (return candidates). Map `action` → required pattern; check support via
  `TryGetCurrentPattern`; in dry-run report only; otherwise perform and capture before/after state. Build
  the envelope with the same helper shape as Module 4 (UTF-8 no BOM; only the envelope on stdout).

### External tools or models
- None beyond `pwsh` + managed UI Automation, both already registered/verified (`TOOL_MODEL_REGISTRY.md`).
  No install needed.

### Installation steps
- None. Files live in `modules/05-uia-actor/`.

### Tests (`tests/Invoke-UiaActorTests.ps1`, run via the executor)
- **Manifest** validates (`Test-SkillManifest`).
- **Dry-run** on a safe, always-present target (desktop root, `path:""`) → envelope valid, status ok,
  `performed:false`, resolves the element, reports `requested_pattern`/`pattern_supported`.
- **Error paths** (all side-effect-free): missing locator → `no_locator`; bad action → `invalid_action`;
  bogus `automation_id` → `element_not_found`; bogus `title` → `target_not_found`; `setvalue` without
  `value` → `value_required`. Each returns a **valid error envelope**.
- **Real actions against a self-contained WinForms probe window** (spun up on an STA runspace in a helper,
  auto-destroys, guaranteed teardown): `setvalue` into the probe TextBox then read-back equals; `toggle`
  the probe CheckBox with before/after ToggleState flip; `invoke` the probe Button confirmed via a signal
  file; plus a `dry_run` invoke that leaves the button un-clicked. Locate probe controls by `control_type`
  (+ `name`/`path`), exercising real Invoke/Toggle/Value patterns with self-verification.
- **Wrapper** integration: `Invoke-Skill.ps1 -SkillDir . -InputsJson '{dry_run…}'` → `manifest_valid` &
  `envelope_valid` true.

### MVP acceptance criteria
- [ ] Manifest validates; entrypoint accepts named params **and** `-InputsJson`.
- [ ] Dry-run resolves + reports the intended action and performs nothing.
- [ ] Each of invoke/toggle/select/expand/collapse/setvalue/focus reachable; ≥ invoke, toggle, setvalue
      proven to really act (self-verified against the probe), with before/after state captured.
- [ ] Locators resolve by `path` and by `automation_id`/`name`/`control_type`; ambiguity and not-found are
      structured errors, not crashes.
- [ ] All failure modes return a **valid** `lifeorch.skill.result/0.1` error envelope (exit 0).
- [ ] Runs direct, wrapped, and through the executor; artifacts written; tests all pass.

### Manual verification procedure
- Open Calculator; `uia.inspector -Title 'Calculator*'` to find a button's `automation_id`; run
  `uia.actor -Title 'Calculator*' -Action invoke -AutomationId <id> -WhatIf` (preview), then without
  `-WhatIf`, and confirm the calculator responds.

### Documentation requirements
- Skill `README.md`, `skill.json` manifest, `examples/example-invocation.md` + `examples/example-result.json`.

### Registry updates
- Add a `uia.actor` entry to `TOOL_MODEL_REGISTRY.md` (status installed, location, invocation, supported
  actions, I/O, limitations, last test).

### State updates
- `CURRENT_STATE.md` (Module 5 complete, tests, next action = Module 6) and `MODULE_ROADMAP.md`
  (Module 5 → MVP complete). Log the first side-effecting skill + `parallel_safe:false` rationale in
  `DECISION_LOG.md`; add any residual uncertainty to `REVIEW_QUEUE.md`.

### Known follow-on work (defer — not this session)
- WindowPattern/Transform actions (move/resize/close), scroll, range-value, multi-select, keyboard-text
  entry where no ValuePattern exists, element-appearance waiting/retry, and action sequencing → later
  work orders / Module 26.

### STOP conditions
- Scope would exceed the "Explicit scope" list (e.g. adding synthetic input or window management) — stop.
- A required pattern/target is missing and working around it needs non-trivial new machinery — stop, note it.
- The contract lacks something needed — stop, propose the change in DECISION_LOG, do not freelance.
- **MVP acceptance met — stop; do not start Module 6.**
