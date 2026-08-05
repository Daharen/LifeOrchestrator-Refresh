# WORK ORDER - Widget 05: Provenance Map

- **id:** `widgets/05-provenance-map` · **Phase:** B (Widget layer) #5 · **Status:** MVP (this session)
- **Realizes:** the audit-surface program's ENTRY VEHICLE (tier A1) -- the project's own construction map
  (iteration 36 coding lane; brief `core-docs/fanout/FANOUT_AGENT_003.md`). Governing design:
  `research/2026-08-05-interpretability-audit-surface-scoping.md` s4 (Unit A + the acceptance gates) +
  `research/2026-08-05-audit-pipeline-target.md` s2.9 / s4-A1 / s3 (readers over artifacts; strictly
  read-only). Delivery per **D-0038** (native WinForms + `launch.bat`); architecture per the Widget
  01/02/03/04 pattern (**D-0039 / D-0049 / D-0060 / D-0064**); adopted by **D-0101**.

## Purpose

The construction-map altitude of the audit funnel. It JOINS what the process already maintains -- the roadmap
status, the CURRENT_STATE tests table, the decision index, the git dev.ship trailers, the handoff iteration
ledger, the wave plan dirs, and the Verification Console verdicts -- into one map: what EXISTS (module/widget
-> version -> iteration -> D-entry -> commit -> files -> verification state), what CHANGED since a chosen
iteration, verification state per unit, and what is planned-but-unbuilt. It also compares each hot doc's actual
size against its DOC_PROTOCOL budget and flags the over-budget ones (auto-surfacing the PB-3 doc-debt). It adds
**zero** new doc-upkeep -- it is a READER over already-mandated artifacts.

## Scope (tight MVP)

STRICTLY READ-ONLY over the canonical on-disk docs + read-only `git log`. The **only** write is the "new since
last visit" marker under the widget's OWN `runtime/` (guarded so it can never escape). Views: what exists /
iteration-N build (one click) / new-since / verification / commits / decisions / planned / doc-budget / flags.
Deterministic parses with **graceful degradation**: a malformed / over-budget / missing hot doc becomes a
VISIBLE FLAG, never a throw.

**Non-goals (do NOT build):** any write to a doc / git / a runtime dir outside its own; executor jobs; model
calls; Widget 06 Compile Trace Console (i37-i38); the compile-layer counterfactual runner; any pause /
possession / side-by-side (Phase 2, post-i40, red-team-gated); the memory modules; the P0-1 suite. A brand-new
widget -> **no `skill.json`** (OMIT skill_id/skill_dir). Non-displacing: the memory sequencing keeps priority.

## Architecture (mirrors Widget 04)

- `ProvenanceMap.psm1` -- **WinForms-free driver core** (so the cloud gate tests it for real):
  - `Get-ProvenanceModel (repoRoot [, gitLogText])` -> the whole join model `{ ok, repo_root, units[], planned[],
    decisions[], iterations[], commits[], plans[], verdicts[], doc_flags[], flags[], counts }`. Units = the
    UNION of roadmap-parsed numbered units AND tests-table units (memory modules #35-#42 live only in the
    latter). Defensive throughout: every source degrades to a well-formed shape + a flag, never a throw.
  - `Get-IterationBuild (model, N)` -> the one-click answer (ledger + decisions + units + commits + plans for
    N; a ledger RANGE covering N counts). `Get-NewSince (model, N)` -> everything with iteration > N.
  - `Format-ProvenanceRows` / `Format-IterationBuild` / `Format-NewSince` -> display strings.
  - Per-source parsers: `Get-DocBudgetFlags`, `Get-DecisionIndex`, `Get-ModuleUnits`, `Get-TestTable`,
    `Get-IterationLedger`, `Get-HandoffCandidates`, `ConvertFrom-GitLog` + `Get-GitProvenance` (the SINGLE git
    seam -- injectable log text for the gate), `Get-PlanProvenance`, `Get-VerificationVerdicts`.
  - `Get-LastVisit` / `Set-LastVisit` -- the ONLY writer; `Set-LastVisit` refuses any target outside the
    widget's runtime dir (defense-in-depth on the read-only guarantee).
  - defensive helpers: `Read-JsonFileSafe`, `Read-TextFileSafe`, `ConvertTo-Array`, `ConvertTo-UtcTime`,
    `Get-Prop`, `Limit-Text`, `Get-MatchList`, `Split-TableRow`, `Resolve-ProvenancePaths`.
- `Show-ProvenanceMap.ps1` -- **thin STA WinForms shell**: a toolbar (iteration picker + a "new since" numeric +
  Refresh, laid out from the toolbar's ACTUAL width in a Resize handler + `.GetNewClosure()` -- the widget-04
  off-screen-toolbar lesson), a read-only header box, and a TabControl of monospace lists. It only marshals the
  core's model + `Format-*` output into controls. `.GetNewClosure()` on handlers (D-0060). `-SelfTest` builds +
  drives + disposes the form OFF-SCREEN and prints `SELFTEST_*_OK`.
- `launch.bat` -- `pwsh -NoProfile -STA -File Show-ProvenanceMap.ps1 %*`.

## Data contracts (consumed, read-only)

- `MODULE_ROADMAP.md`: `**<NN> \`id\`** ... status ... (D-refs)` (modules) + `- **<NN> Name** ... status ...`
  (widgets). Status vocabulary per the roadmap. Non-ASCII (em dash / middot) tolerated -- matched structurally.
- `CURRENT_STATE.md`: the `| unit | last result | task / commit | date |` table (version / iteration / commit
  parsed from the cells).
- `DECISION_LOG_INDEX.md`: the `| id | date | state | decision |` table.
- `FANOUT_ORCHESTRATOR_HANDOFF.md`: the iteration-ledger lines (`- iNN \`fo-...\` (D-...): ...`, incl. a range
  `- **i1-i38 ...**`) + the numbered candidate menu.
- `DOC_PROTOCOL.md`: the `| doc | owns | budget |` table (KB budgets, `no cap`, and `KB each` globs).
- `git log --no-color --date=short --name-only --pretty=format:'%h ... %s'` -- read-only.
- `lifeorch.fanout.plan/0.1` + `lifeorch.fanout.report/0.1` (plan dirs); `lifeorch.verification.result/0.1`
  (verdict sidecars).

## Test plan

Dual-mode `tests/Invoke-ProvenanceMapTests.ps1`:
- **Cloud gate (no `-Live`):** AST-parse + ASCII-guard all scripts; every parser over the fixture repo (doc
  budgets incl. over/nocap/missing/glob; decision index; module/widget units + status + name cleanup; tests
  table; iteration ledger single + range; candidate menu; git-log parse; plan provenance incl. a MALFORMED
  plan.json -> ok=false; verdicts); the full JOIN; the one-click `Get-IterationBuild`; `Get-NewSince`; the
  `Format-*` views; and the READ-ONLY guarantees (the repo is byte-identical after a build; `Set-LastVisit`
  writes ONLY under its runtime dir); graceful degradation on an empty repo. **96/96 green** in cloud pwsh
  7.4.6 (Linux).
- **Live (`-Live`, Windows/executor):** launch.bat shape; the WinForms `-SelfTest` (`SELFTEST_FORM_OK` /
  `MODEL_OK` / `ITERATION_OK` / `NEWSINCE_OK` / `FLAGS_OK` / `READONLY_OK` / `REFRESH_OK` / `LAYOUT_OK`); and a
  render of the **real** repo (>=20 units, >=1 commit, a recent iteration build found) with no throw.

## Ship

Through the job-runner (`dev.ship`): sha-verify the shipped files, AST-parse, run the tests `-Live`, commit
exactly the `widgets/05-provenance-map/` files under the `git` lease with trailers. A brand-new widget -> no
`skill.json`. **A human live-GUI confirm is REQUIRED before this is called done** (D-0049/D-0060/D-0064 --
mock/self-test gates miss rendered-UI defects); the worker FLAGS it, the orchestrator carries it as the closing
follow-on.

## Follow-ons (not this session)

Colour/status highlighting (over-budget = red, planned = grey); a per-unit drill-down (all its commits + all its
D-entries); an opt-in auto-refresh; a "reveal in Explorer / open the commit" affordance; wiring the Doc-Health
monitor's history (`ops/out/doc-health-log.jsonl`) for a growth-over-time view; a cross-iteration
growth-vs-verification-coverage curve (audit tier A5).
