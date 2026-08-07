# i41 M2-A scope -- the deterministic fail-closed doc-hygiene commit gate (build = i42)

Satisfies the mandate-02 s1 requirement that i41 SCOPE the M2-A build (BUILD deadline: shipped by the i42
close, D-0110). This note is the i42 build lane's governing scope. SINGLE-WORKER wave (core-infra rule,
handoff s8): the gate hooks the executor doc-commit path. RECOMMENDED MODEL (D-0114): Sonnet 5 High --
exact-spec'd deterministic tooling with a reference implementation; ELEVATE to Opus 4.8 Extra on its first
failed gate run.

## Placement + enforcement point

A pure-python gate `ops/audit/doc-commit-gate.py`, enforced at TWO layers, fail-closed:

1. PRIMARY: a git pre-commit hook (`.git/hooks/pre-commit`, installed by an idempotent ASCII
   `ops/install-doc-gate.bat`, no admin) that runs the gate over the STAGED set whenever it intersects
   `core-docs/*.md`. Hooks are machine-local, so presence is ASSERTED: the gate suite + gen-doc-health.py
   check hook existence + content hash (missing/stale hook = red). Why primary: it fires no matter which
   session or task script performs the commit -- convention cannot be forgotten.
2. SECONDARY (defense-in-depth): the commit-task idiom gains one gate invocation on the named file list
   after the staged-set assertion, before `git commit` (handoff s7 cheat-sheet updated at the i42 close).

## Checks (v1 -- deterministic, stdlib-only; non-zero exit = REJECT + a machine-readable report naming
file / measured / budget / rule)

- BUDGET: every staged `core-docs/*.md` <= its DOC_PROTOCOL s2 budget (REUSE
  `ops/audit/gen-doc-health.py::parse_budgets()`; KB=1000). Over-budget REJECTS unless the same commit
  stages a DOC_PROTOCOL s2 change AND the message carries `GATE_OVERRIDE: D-####` (below).
- ACCRETION TRIPWIRES: reject `[prior]` chains and >=2 stacked `Last updated` lines in any staged hot doc
  (the D-0066 REPLACE rule, mechanized).
- PROPORTIONAL BUDGET + RE-LAYER TRIGGER (D-0094): a staged hot doc over the ~40 KB bounded-read threshold
  (mandate s6 knob) is rejected unless the commit message references a re-layer plan note
  (`research/*-relayer-*.md`) -- the M2-C path, not another slim.
- INDEX DENSITY: `DECISION_LOG_INDEX.md` rows > ~200 chars in the staged DIFF produce a WARN line in the
  report (promote to reject in v2 once M2-C lands).

## Override (no silent bypass)

`GATE_OVERRIDE: D-####` in the commit message is honored ONLY when that D-entry id exists in the staged or
committed DECISION_LOG.md; every honored override is appended to `ops/out/doc-gate-log.jsonl`. Nicholas
ratifies overrides after the fact via the log.

## Exemptions

`archive/**`, `modules/**`, `widgets/**` (no s2 budgets), `DECISION_LOG.md` (uncapped by design), non-.md
files. `research/*.md` (10 KB) and `fanout/FANOUT_AGENT_*.md` (8 KB) ARE enforced per s2.

## Acceptance (the mandate's own bar)

FIRST REAL FIRING LOGGED: a deliberately over-budget doc commit attempted through the executor path is
REJECTED with the report, then the corrected commit passes -- both transcripts land in
`ops/out/doc-gate-log.jsonl` and are cited in the closing D-entry. Plus: off-box unit tests (budget parse,
each check, override honor/reject, double-run determinism); the hook-presence assertion wired into
gen-doc-health.py; ship via devship; native-HEAD verify (D-0072).

## Non-goals (v1)

No auto-slimming; no prose-quality judgment; no Project-mirror enforcement; no module-doc budgets; no EOL
policing (per-file EOL stays a handoff s7 rule).
