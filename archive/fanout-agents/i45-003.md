# FANOUT_AGENT_003 -- READY

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** READY
- **Wave / iteration:** i45 (plan id `fo-45-b17a531e`)
- **Lane:** CODING (CPU)
- **Worker id / label:** `LRAP-WIDGET08-i45` -- NEW `widgets/08-live-run-audit-pathway` (the Live-Run Audit Pathway)
- **Module/area (exclusive):** `widgets/08-live-run-audit-pathway` ONLY
- **GPU:** false
- **Docs:** `[]`
- **Recommended model:** Opus 4.8 Extra (audit-critical, design-vs-build, first-of-kind; the honesty map is unusually easy to over-claim -- D-0114/D-0116)

## Mission
Build the audit program's phenomenological TOP surface (D-0120; `AUDIT_PIPELINE.md` P9): a STRICTLY
READ-ONLY native WinForms pathway (`widgets/08`) that walks a REPLAYED `#40` compile as ONE chronological,
plain-language, INTENT-vs-actual narrative -- so Nicholas can find a bad input at the step where it happens
WITHOUT prerequisite schema expertise and WITHOUT window-switching. The shipped widgets 05/06/07 are the
expert-forensic DESCEND target, not the top surface. This unit is DESIGN-FIRST + RED-TEAM-HARDENED: build
to `research/2026-08-08-i45-lrap-design.md` EXACTLY (11 red-team findings already folded).

## Unit (build spec)
**THE AUTHORITATIVE SPEC is `research/2026-08-08-i45-lrap-design.md` -- read it whole and build to it
exactly, ESPECIALLY s3a (the per-step x per-lane HONESTY MAP) and s2 (the RECONCILE rule).** The full
worker prompt (identical scope, with lease + report boilerplate) is the convenience copy at
`modules/30-orchestrate-fanout/runtime/artifacts/551f28d4-b2f2-4b22-acb6-ef3643a53fe1/workers/worker-LRAP-WIDGET08-i45.prompt.md`.

Scope in ONE line: a NEW `widgets/08-live-run-audit-pathway` (NO `skill.json` -- a Widget like 05/06/07;
OMIT skill_id/skill_dir), STRICTLY READ-ONLY, `docs:[]`, CPU, `non_execution:true`, no lease/pause/model,
writes nothing outside its own `runtime/`.

Build (all per the spec):
- **Six-step spine** (s1): normalize -> retrieve -> route -> select -> budget -> packet, over one `#40`
  `context_packet/0.2` artifact. Steps 7-8 (gate/verify) are NOT built (unwired). Flat compile drops step 3.
- **Four lanes / step**: INTENT / INPUT / OUTPUT / RECONCILE, plain language, not raw schema.
- **HONESTY MAP** (s3a): implement the exact AUTH/DATA/VERDICT/P2 per-cell classification. Every `P2` cell
  (step-1 INPUT, step-1 RECONCILE, the step-2 recall-gap) renders as a VISIBLE "not emitted yet" lane --
  never a computed stand-in, never a fake, never a blank.
- **RECONCILE** (s2, HARD -- F1): re-express ONLY a verdict the substrate already computes (a W07
  tournament set/count identity or an arithmetic check). NO semantic judgment (omit_reason validity /
  successor-should-exist / classification-correctness) -- that is FORBIDDEN and logged as a `P2` gap.
- **RECONCILE render** (F5): neutral consistent/INCONSISTENT-here marker first pass, naming prose
  COLLAPSED until opened; green = "counts reconcile", never "correct" (F2).
- **INTENT catalog** (s3b): six blocks, each cites the contract clause it paraphrases, version-stamped;
  its own review pass (name the reviewer in the report).
- **Descend** (s4, F7): INLINE plain-language "WHY this step flagged" (records/counts in prose), NOT a raw
  re-render of the 06/07 pane; the raw pane only behind an explicit "show raw trace" affordance.
- **Reader adapter** (s5, F8): a pinned adapter over 06/07's EXISTING public readers (NO 06/07
  modification) + a cross-widget contract test in 08's suite; EXCLUDE the recompute entrypoints.
- **Data source** (s6): newest real `#40` runtime artifact, else a bundled fixture (widget-06 order).

OUT (record, do NOT build): steps 7-8; the ride-along PAUSE / gateway hold hook (A2.2); possession (A3);
side-by-side (A3); the instruction<->model-output loop. Any pause/lease/model call is OUT.

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit. This unit needs only the **git** lease.
- Do ONE unit; never touch modules/areas outside `widgets/08`; do NOT modify widgets/05/06/07 or #40/#37/#30/#43; `docs:[]`.
- Gate off-machine FIRST (cloud pwsh over committed REAL fixtures, in the 05/06/07 test style), then ship via `exec-job.sh devship` (NEW widget -- OMIT skill_id/skill_dir; AST + tests FAIL-CLOSED, named files only, trailers). VERIFY the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.
- Deterministic, integer-only JSON, DOUBLE-RUN byte-identical on every canonical-bytes path; honor the i33 sanitization (no cross-namespace metadata surfaced).
- UI change -> the human live-GUI confirm is the ACCEPTANCE gate (D-0064); ship SelfTest-green + cloud-green and FLAG it pending (the orchestrator drives it at fold). An honest INCOMPLETE beats a false "done".
- Report: `-Action report -PlanId fo-45-b17a531e -WorkerId LRAP-WIDGET08-i45 -State done` + a plain measured summary (negative results first-class).

## Verification
Cloud gate (pwsh 7.4.6 Linux) over committed REAL fixtures: the driver core (readers/adapter, honesty-map
classification, RECONCILE-verdict computation, five-fixture machine-classification, descend prose builder),
byte-identical re-render, the read-only + i33 sanitization guards, the cross-widget contract test. Then
`-Live`: launch.bat shape + STA SelfTest (`SELFTEST_*_OK` incl. `LAYOUT_OK` + `READONLY_OK`) + a real `#40`
artifact render + the five-fixture classification (3 defects flagged at their step; clean + quirk NOT
false-flagged). Expected: a shipped `widgets/08` unit + the OPEN human live-GUI confirm flagged pending.

## Report-back record (ORCHESTRATOR fills from `plans/fo-45-b17a531e/reports/` before archiving)
_empty._
