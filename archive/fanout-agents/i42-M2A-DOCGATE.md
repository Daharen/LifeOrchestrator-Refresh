# FANOUT_AGENT_002 -- READY (i42 Lane A: M2-A doc-hygiene commit gate)

## Header
- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i42 (plan id `fo-42-e5403d74`)
- **Lane:** CPU (ops-exclusive)
- **Worker id / label:** M2A-DOCGATE-i42
- **Module/area (exclusive):** `ops/` (new `ops/audit/doc-commit-gate.py` + `ops/install-doc-gate.bat` + a read-only edit to `ops/audit/gen-doc-health.py`) + the machine-local `.git/hooks/pre-commit` install
- **GPU:** false
- **Docs:** `[]`

## Mission
Ship mandate-02 **M2-A** -- the deterministic FAIL-CLOSED doc-hygiene commit gate (the i42 HARD DEADLINE). A pure-stdlib gate enforced at two layers: a git pre-commit hook PRIMARY (idempotent ASCII installer; presence+hash asserted by `gen-doc-health.py`) + a commit-task `--files` invocation SECONDARY -- reusing `gen-doc-health.py::parse_budgets()`. "The builder obeys the same contract as the built." Governing spec: `research/2026-08-07-i41-m2a-doc-gate-scope.md`.

## Unit (the full worker prompt)
Read + execute the complete engineered prompt (self-contained, ~14 KB) at:
`modules/30-orchestrate-fanout/runtime/artifacts/7ed39a71-20e1-4158-a9e9-4bd3cf6161b2/workers/worker-M2A-DOCGATE-i42.prompt.md`
(Nicholas also pastes this file as the SendUserFile convenience copy.)

Scope in brief -- checks v1: DOC_PROTOCOL s2 budgets (staged-blob size; reuse `parse_budgets()`, KB=1000) + accretion tripwires (`[prior]` chains / >=2 stacked `Last updated`) + the D-0094 re-layer trigger at ~40 KB + index-density WARN. Override: `GATE_OVERRIDE: D-####` honored only when that D-entry exists (staged or committed), logged to `ops/out/doc-gate-log.jsonl`. Exemptions: `archive/**`, `modules/**`, `widgets/**`, `DECISION_LOG.md`, non-.md; `research/*.md` (10 KB) + `fanout/*` (8 KB) ARE enforced. RULINGS: unlisted core-docs/*.md -> WARN (not reject); measure the STAGED blob (not the worktree); FAIL-CLOSED on gate error; double-run byte-identical report. Acceptance: off-box unit tests (each check + override + determinism) THEN a real firing through the executor path (deliberate over-budget REJECTED with report, then a corrected commit PASSES; both transcripts to `doc-gate-log.jsonl`; leave no stray probe). NON-GOALS v1: no auto-slim, no prose judgment, no Project-mirror enforcement, no module-doc budgets, no EOL policing.

RECOMMENDED MODEL: **Sonnet 5 High**; ELEVATE to **Opus 4.8 Extra** on the FIRST failed gate run (D-0114).

## Rails
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire the res.lease `git` lease before committing; release on exit. No GPU.
- Do ONE unit; EXCLUSIVE to `ops/` (+ the `.git/hooks` install); never touch `modules/**` or core-docs; `docs:[]`. The acceptance-probe is the ONE controlled core-docs touch and it lands NOTHING permanent.
- Gate off-machine FIRST (pure python), then `exec-job.sh devship` (named files only; AST/tests fail-closed). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.
- If your device bridge dies before your first push: STOP + report in-session (the i40 lesson) -- the orchestrator runs recovery; do not improvise a second ship path.
- Report: `-Action report -PlanId fo-42-e5403d74 -WorkerId M2A-DOCGATE-i42 -State done` + a plain measured summary (negative results first-class).

## Verification
Shipped files + commit (native HEAD). Unit-test counts per check. The two on-box firing transcripts (reject report + pass) + their `doc-gate-log.jsonl` rows. The hook-presence assertion in `gen-doc-health.py` reading RED when the hook is absent/stale. The exact `--staged` / `--files` / `--worktree` CLI.

## Report-back record (orchestrator fills at fold)
_empty._
