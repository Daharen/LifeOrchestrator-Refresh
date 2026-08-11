# CLAIMS_NOTES -- i46-repo-claims.json (worker PCB-CLAIMS-i46, Lane B)

WORK_ORDER sha256 built against (LF bytes): `439261078ffeb0169e22de4829e9024081b50470187d78901dd9f2479a550725` (verified match). at_commit = `d7619b41d2742ab8f309e4af908a71ff919ad935` (native `git rev-parse HEAD`; only untracked temp dirs outside modules/44-project-map/ -- effectively clean).

## Coverage counts (142 entities, 98 relationships)

By ns: module 45 (00, 00.1, 01-43) | arch 51 (0-49 + 00.1) | widget 8 | store 7 | decision 12 | contract 5 | plane 5 | ops 4 | doc 2 | mandate 1 | pb 1 | iteration 1.

module:44/project.map is deliberately OUT of scope (COVERAGE names modules 00..43; #44 is the parallel Lane-A build).

## Uncertain (11, each with an inline note)

`arch:21` (doc-staleness: MODULE_ROADMAP says module:34 realizes it MVP-complete, but ARCHITECTURE_MAP's own banner still reads "planned") | `arch:24`, `arch:26` (explicitly PARTIAL realizations) | `contract:doc-protocol` (plane call not source-stated) | `module:07/model.gateway`, `08/classify.batch`, `09/review.processor`, `17/image.interpret` (intelligence-vs-capability split for model-driven modules is my judgment, not verbatim-sourced) | `module:21/agent.local`, `37/retrieval.eval`, `41/skill.card` (plausible plane pairing, not independently confirmed).

`module:30` and `module:40` use plane pairs taken **verbatim** from i46-pcb-design.md s3's own worked examples ("#40 memory+intelligence; #30 intelligence+capability") -- marked `established` since the pairing is directly evidenced, though intelligence+capability for a dispatcher isn't obviously intuitive from the module's own description alone.

## Judgment calls

- **contract: vs doc: for MEMORY_ARCHITECTURE.md / AUDIT_PIPELINE.md** (required decision): both went **doc:**. Each doc's own header calls itself a "governing, versioned" design **target**, distinct from the four contract: entities, each explicitly a D-0077 fold-smoke party as a frozen wire-format interface other modules build to. MEMORY_ARCHITECTURE.md's own text says the memory contracts are "subordinate to" it (sits above them) but defines no frozen field schema of its own.
- **Model-driven plane splits** (classify.batch, review.processor, image.interpret, model.gateway): the design doc gives worked examples only for #30/#40; every other intelligence-vs-capability call is my extrapolation, flagged `uncertain`.
- **realizes edges kept narrow**: only the 0-18 same-number/same-concept pairs + the 6 divergent pairs the prompt names explicitly (32->19, 33->20, 34->21, 36->23, 27(partial)->24, 21(partial)->26). Modules 19-20, 22-26 (except those partials), 28-31, 35, 37-43 get NO realizes edge -- no source states one; inventing it would be false precision.
- **Edge set kept to ~98** (well under ~250) -- favored well-evidenced cited edges over broad weak coverage, per "low rejection with honest uncertainty, not maximal coverage."

## Known gaps (honest, not fabricated)

- `authority_level`/`audit_surfaces`/`state_owned` claimed only where a source stated something concrete (module:29 leases, module:43 monitor); left absent elsewhere.
- Most `store:` entities carry no `plane_primary` (not required for store: ns; not independently evidenced).
- `ops:` limited to the 4 named units; other `.bat` launchers / `setup/*.psm1` internals not entitized.
- module/widget `one_line`+`status` sourced from MODULE_ROADMAP.md + ARCHITECTURE_MAP.md, deliberately NOT each skill.json (restating those = CLAIM_RESTATES_HARVEST). `deeper[]` README/WORK_ORDER pointers are asserted from a real directory listing, not full-content reads.

## Top docs read (by usefulness)

WORK_ORDER.md | worker prompt | i46-pcb-design.md | MODULE_ROADMAP.md | ARCHITECTURE_MAP.md | CURRENT_STATE.md | DECISION_LOG_INDEX.md | FANOUT_ORCHESTRATOR_HANDOFF.md | DOC_PROTOCOL.md | AUDIT_PIPELINE.md | MEMORY_ARCHITECTURE.md | PROCESS_BACKLOG.md | PROCESS_MANDATE.md | START_HERE.md | the 4 *_CONTRACT.md docs (opening sections).
