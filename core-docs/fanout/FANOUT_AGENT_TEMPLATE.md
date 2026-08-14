# FANOUT_AGENT_TEMPLATE -- worker-brief slot format (D-0066)

Copy this structure when filling a slot (`FANOUT_AGENT_001..003`). The slot doc IS the worker's mission:
Nicholas dispatches a fresh Cowork session with *"Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md`
and execute it"* plus the one folder grant (`C:\Users\just_\LifeOrchestrator-Refresh`). Slot lifecycle
(fill -> READY -> DISPATCHED -> archive to `archive/fanout-agents/i<N>-<id>.md` -> reset to EMPTY):
`DOC_PROTOCOL.md` section 6. The orchestrator usually fills the Unit section with the exact worker prompt
emitted by `orchestrate.fanout` `plan` (they are engineered to be complete); hand-authoring is fine for
pre-plan drafts.

---

## Header (fill every field)

- **Slot:** FANOUT_AGENT_00N
- **Status:** EMPTY | READY | DISPATCHED
- **Wave / iteration:** i<N> (plan id `fo-<N>-<id>` once planned)
- **Lane:** GPU (<=1 per wave) | CPU | CODING
- **Worker id / label:** as in `workers-i<N>.json`
- **Module/area (exclusive):** the ONE module or widget this worker owns this wave
- **GPU:** true|false -- `gpu:true` ONLY on the GPU lane
- **Docs:** `[]` (always -- workers never edit core-docs; the orchestrator mirrors)

## Mission (2-4 lines)

What this unit accomplishes and why it is worth a wave slot. Reference the design doc(s) that govern it.

## Unit (the full worker prompt)

The complete, self-contained instruction block: scope IN/OUT, requirements, gates, live-verification
demands, and the "report plainly if impractical" ethos. If `orchestrate.fanout` emitted a prompt for this
worker, paste it here verbatim.

## Rails (standing rules -- keep in every brief)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Prefer bounded PCB queries (`section:` / `card:` / `--q`) over whole-doc opens; charged retrieval bytes are the cost, so a whole-doc open is a last resort (D-0146 F-i53-eff).
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit. Whole-task gpu lease for any
  resident-model work.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]`.
- Gate off-machine first where possible (cloud pwsh + mock/seam harness), then ship via
  `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers). Files reach the
  box via `SendUserFile` + `device_commit_files` (<=20 MB/file); large binaries download on-device via an
  executor `curl.exe` task.
- Any persistent llama-server launches DETACHED; reap before finalize; assert 0 orphans.
- UI changes need a human live-GUI confirm; runtime-behavior changes need a real-model check (D-0060/D-0064).
- Report back: `-Action report -PlanId <plan> -WorkerId <id> -State done` (+ a plain summary of measured
  results; negative results are first-class -- say so plainly, the D-0061 ethos).

## Verification

What proves the unit worked (test counts, live measurements, a Verification Console `run_module` item if
the output is runnable, expected artifacts + paths).

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

The worker reports via `-Action report`, never by editing this doc (workers run `docs:[]`). Record here:
commit(s), test results, measurements, residuals/follow-ons discovered, anything walked back.
