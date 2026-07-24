# Work Order: UI Automation Inspector (`uia.inspector`)

**Contract version targeted:** 0.1 · **Author:** Claude (Cowork), 2026-07-24 · **Roadmap entry:** `MODULE_ROADMAP.md#uia.inspector`

### Problem being solved
To act on an application an agent must first *see its controls* — buttons, fields, menus — as structured,
addressable elements, not pixels. This reads the UI Automation (accessibility) tree of a target window and
returns stable element info. It is the read-only half of desktop control; the actor (Module 5) is separate.

### Immediate practical use
Answers "what controls does <window> expose, where, and how can they be acted on?" — a human-readable tree
plus a machine-readable element list a router or the future actor can consume to locate a control.

### Explicit scope (in)
- Resolve a target: `-Hwnd` | `-ProcessId` (main window) | `-Title` (glob over top-level windows) | else the desktop root.
- Depth-bounded, element-capped pre-order walk of the UIA control tree.
- Per element: control type, name, automation id, class, bounds, enabled/offscreen/keyboard-focusable,
  supported control patterns, plus `ref` and a child-index `path` for stable in-snapshot addressing.
- Optional `name_filter` glob → bounded matches list. Artifacts `tree.md` + `elements.json`. Contract-valid envelope.

### Non-goals (out — do NOT build)
- **Any action** (invoke/select/expand/focus/move/type) — that is Module 5 `uia.actor`, kept separate on purpose.
- Screenshots / pixels (Module 6). Continuous watching / event subscriptions.
- Full property dump of every UIA property; deep caching/perf tuning (bounded direct reads for MVP).

### Dependencies
- Modules: Module 1 (`skill.bootstrap`) — reuse `lib/SkillContract.psm1` and `Invoke-Skill.ps1`.
- Tools/models: `pwsh>=7.4` + managed UI Automation (`UIAutomationClient`/`UIAutomationTypes` via `Add-Type`).
  Verified available by a smoke test (root Pane, 9 top-level UIA windows, foreground resolvable).

### Skill contract requirements
- `skill_id` `uia.inspector`, `version` `0.1.0`, `determinism` `deterministic` (deterministic read of current
  UI state), `parallel_safe` true, `batch`/`streaming` false.
- `result` = `{ target, depth, element_count, truncated, name_filter, match_count, matches[], elements[] }`;
  `confidence` null; artifact kinds `markdown` + `json`.

### Inputs and outputs
- **Inputs:** `hwnd` (int), `pid` (int), `title` (string glob), `depth` (int, default 4),
  `max_elements` (int, default 500), `name_filter` (string glob). No target → desktop root.
- **Outputs:** result above; artifacts `tree.md`, `elements.json` (+ stderr.txt, result.json).

### Artifact structure
- `runtime/artifacts/<invocation_id>/` → `tree.md`, `elements.json`, `stderr.txt`, `result.json`.

### Proposed implementation
- **Language:** PowerShell 7 + managed UIA via `Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes`.
- Resolve target; iterative pre-order DFS with `FindAll(TreeScope.Children, TrueCondition)`, depth + element
  bounds; per-element property reads each wrapped in try/catch (stale/again-unavailable → empty, not fatal).
  Reuse Module 1 envelope conventions. Window/children unavailable → warning + `status:partial`.

### External tools or models
- None to install; the UIA assemblies ship with the Windows Desktop runtime pwsh uses.

### Installation steps
- None. Files added under `modules/04-uia-inspector/`.

### Tests
- **Direct (desktop root, small depth):** schema-valid envelope, `element_count` > 0, target resolved,
  two artifacts with hashes, `elements.json.element_count` == `result.element_count`.
- **Name filter:** `-NameFilter '*'` → non-empty matches.
- **Target error:** `-Title 'zzz-no-such-window'` → `status:"error"`, code `target_not_found`, valid envelope.
- **Wrapped:** via `Invoke-Skill.ps1 -SkillDir . -InputsJson '{...}'` → manifest+envelope valid.
- **Through the executor:** submit a task package → `completed` + valid envelope + artifacts.

### MVP acceptance criteria
- [ ] `uia.inspector` manifest passes `Test-SkillManifest`.
- [ ] Contract-valid envelope; target resolved; depth-bounded tree with element info + patterns; two artifacts with hashes.
- [ ] `name_filter` narrows; `target_not_found` error path valid; runs through the executor and via the wrapper.
- [ ] `TOOL_MODEL_REGISTRY.md` has a `uia.inspector` entry.

### Manual verification procedure
- Target a known app (`-Title 'Calculator*'` or a `-ProcessId`); open `tree.md`; confirm real controls
  (buttons/edits) with automation ids + `Invoke`/`Value` patterns appear with plausible bounds.

### Documentation requirements
- Module `README.md`, `skill.json`, `examples/` (invocation + a real captured result).

### Registry updates
- Add `uia.inspector` to `TOOL_MODEL_REGISTRY.md`.

### State updates
- Update `CURRENT_STATE.md` and `MODULE_ROADMAP.md` (Module 4 → MVP complete; Module 5 next).

### Known follow-on work (future work orders — NOT this session)
- Module 5 `uia.actor` (act on elements located here). Property caching for perf; event subscriptions; richer selectors.

### STOP conditions
- Scope would exceed the "Explicit scope" list (especially: **no actions**).
- A dependency is missing/broken and installing it is non-trivial.
- The contract lacks something this module needs (stop; propose the change; do not freelance).
- MVP acceptance is met — **stop; do not start Module 5.**
