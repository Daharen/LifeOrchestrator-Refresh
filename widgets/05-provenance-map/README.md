# Widget 05 - Provenance Map

The **construction-map** surface for the whole project (D-0101; the audit-surface program's ENTRY VEHICLE,
tier A1). Where the Verification Console (Widget 03) audits a single wave's *outputs* and the Fan-out Wave
Dashboard (Widget 04) shows a single wave *in flight*, this widget zooms all the way out: it JOINS what the
process **already maintains** into one map of **how the project was built** -- what EXISTS, what CHANGED since a
chosen iteration, what is VERIFIED, and what is PLANNED-but-unbuilt. It is the audit funnel's top altitude:
map -> gates -> trace; attend at the top, descend on anomaly.

It is **STRICTLY READ-ONLY**. It parses the canonical on-disk docs + read-only `git log` DIRECTLY -- those
files ARE the source of truth -- and adds **zero new doc-upkeep**. It never invokes a module, drives a worker,
writes a doc, runs a git write, submits an executor job, or calls a model. The **only** thing it may persist is
its own "new since last visit" marker under `widgets/05-provenance-map/runtime/`, guarded so a write can never
escape that dir.

## What it shows

1. **What Exists** -- one row per module/widget unit: **kind / num / id / status / version / iteration /
   commit / verified**, joined from the roadmap's numbered units *and* the tests table (so the memory modules
   #35-#42, which live only in the tests table, appear too).
2. **Iteration N** -- the one-click answer to *"what did iteration N build, and under which decision?"*: pick
   an iteration from the toolbar and the tab shows the ledger line, the decisions (D-entries), the units it
   built/touched, the git commits, and the wave plan(s) -- in one click.
3. **New Since** -- everything with an iteration greater than a chosen point (defaults to your last visit,
   persisted only in this widget's own `runtime/`): the new units, commits, and decisions.
4. **Verification** -- the per-unit test-table result, a **`NO TEST-TABLE ROW`** flag for a built unit that is
   unverified, plus the Verification Console's durable per-packet verdicts where parseable.
5. **Commits** -- the `git` dev.ship trailer stream: **commit / date / iteration / subject**, iteration + plan
   id + D-refs parsed from each subject, the module/widget each touched from the file list.
6. **Decisions** -- the `DECISION_LOG_INDEX` rows (id / date / state / label), newest first.
7. **Planned** -- planned-but-unbuilt: unbuilt numbered roadmap units + the handoff's candidate-unit menu.
8. **Doc Budget** -- each hot doc's actual byte size vs its `DOC_PROTOCOL` budget, with **OVER** flags that
   auto-surface the PB-3 doc-debt (green/yellow/red per the doc-health rule) -- zero upkeep.
9. **Flags** -- graceful-degradation flags: any malformed / over-budget / missing hot doc, or git being
   unavailable, surfaces here as a **VISIBLE FLAG** rather than a crash.

Every parse is **deterministic** and degrades gracefully: a malformed or over-budget hot doc becomes a flag,
never an exception. It reimplements nothing -- it reads what `DOC_PROTOCOL` already mandates.

## Data sources (all read-only)

- `core-docs/MODULE_ROADMAP.md` -- numbered module/widget units + status + D-refs (what exists / planned).
- `core-docs/CURRENT_STATE.md` -- the tests table (version / iteration / commit / result per unit).
- `core-docs/DECISION_LOG_INDEX.md` -- one routing row per decision.
- `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` -- the iteration ledger (iteration -> plan -> D-refs -> commits) +
  the candidate menu.
- `core-docs/DOC_PROTOCOL.md` -- the per-doc size budgets (compared against actual on-disk byte sizes).
- **`git log`** (dev.ship trailers) -- commit -> date -> subject -> files -> the unit touched.
- `modules/30-orchestrate-fanout/runtime/plans/<id>/` -- the wave plan dirs (iteration -> plan -> worker states).
- `widgets/03-verification-console/runtime/results/*.json` -- the durable verification verdicts.

`-RepoRoot` (or `$env:LIFEORCH_PROVENANCE_REPO`) points the whole map at a specific repo/fixture tree; the
default is the widget's own `../..`.

## Run it

Double-click **`launch.bat`** (runs `Show-ProvenanceMap.ps1` under the per-user PowerShell 7, STA).
Options: `launch.bat -Iteration <N>` opens a specific wave; `-RepoRoot <dir>` points at another repo.

## Files

- `ProvenanceMap.psm1` -- WinForms-free driver core: `Get-ProvenanceModel` (all sources -> one join model),
  `Get-IterationBuild` (the one-click "what did iteration N build"), `Get-NewSince`, `Format-*` (display
  strings), the per-source parsers (`Get-DocBudgetFlags`, `Get-DecisionIndex`, `Get-ModuleUnits`,
  `Get-TestTable`, `Get-IterationLedger`, `Get-HandoffCandidates`, `ConvertFrom-GitLog` / `Get-GitProvenance`,
  `Get-PlanProvenance`, `Get-VerificationVerdicts`), the guarded `Get-LastVisit` / `Set-LastVisit` (the ONLY
  writer), and the defensive helpers. Every parse + the join lives here, so it is unit-tested off-machine.
- `Show-ProvenanceMap.ps1` -- thin STA WinForms shell (an iteration picker + a "new since" control + Refresh; a
  header box; a tabbed set of monospace lists). `-SelfTest` builds + drives + disposes the form off-screen over
  the fixtures and prints `SELFTEST_*_OK` markers (incl. `SELFTEST_LAYOUT_OK` + `SELFTEST_READONLY_OK`).
- `launch.bat` -- double-click launcher.
- `tests/Invoke-ProvenanceMapTests.ps1` -- dual-mode harness (cloud gate + `-Live` on Windows).
- `tests/fixtures/repo/` -- a small self-contained fixture repo (core-docs + plan dirs incl. a malformed
  plan.json + a verdict sidecar) + `tests/fixtures/git-log.fixture.txt` (a git-log fixture, `<<RS>>`/`<<US>>`
  tokens the harness swaps for the real control chars).

## Verification

Cloud pre-ship gate: `pwsh -NoProfile -File tests/Invoke-ProvenanceMapTests.ps1` (Linux; drives the real core
over the fixture repo + an injected git-log + synthetic temp trees; AST-parses + ASCII-guards every shipped
script; asserts the read-only guarantees). On Windows add `-Live` for the STA form self-test + a render of the
**real** repo. **A rendered-UI widget requires a human live-GUI confirm before it is called done**
(D-0049/D-0060/D-0064): mock/self-test gates miss rendered-UI defects.
