# Live-Run Audit Pathway (LRAP) -- the phenomenological audit surface (i43 design spec)

**Status:** DESIGN SPEC (provisional; name ratifiable). Captures the i43 human live-GUI-confirm finding
(D-0120) and reprioritizes the AUDIT_PIPELINE program (`research/2026-08-05-audit-pipeline-target.md`).
DESIGN ONLY -- no build this session; the surface itself is design-first + red-team-gated per the A3 pattern.

## 0. The finding (i43, Nicholas)

The Widgets 05/06/07 D-0064 live-GUI confirm PASSED on the technical basis: all three render real data
correctly (toolbars intact, panes populated, tournament/timeline reconciliations green, `non_execution`
holds; a fresh -Live pre-flight on HEAD `3db60ce` returned 113/0 + 98/0 + 93/0, every `SELFTEST_*_OK`).
But Nicholas -- the D-0050 audit authority -- judged the audit SURFACE grossly inadequate for its actual
purpose:

- they are EXPERT FORENSIC CONTROL PANELS, not an audit pathway: using them needs prerequisite vocabulary
  (`packet_id`, selpol, `routing_stage_trace`, reconciliation), switching between three windows, knowing
  which pane answers which question, and doing the reconciliation in one's own head;
- they are POST-HOC -- read-only views of artifacts that already completed; NONE rides along a live run;
- he can answer specific questions if prompted, but cannot derive an intuitive auditing PATH across the
  three widgets for a live local-model run: "control panels without instructions that allow expert
  auditability, not phenomenological natural pathways that let me see bad inputs as they happen in the
  pipeline where I reconcile intuitive instructions against intuitive outputs before the agents and tools
  move on to the next step in chronological order to find breakpoints."

The consequence he named: until the auditability surface is completed correctly, the project scope is too
opaque for him to audit -- and that IS the purpose of this surface. So the VERIFY half of the D-0050 audit
loop (offload only what is cheaper to VERIFY than to do; Nicholas verifies) is not yet real. This is a
governability finding, not a UX-polish item.

## 1. Where this sits in the A0-A5 ladder (no reinvention)

The AUDIT_PIPELINE program already anticipated this -- its ORIGIN was a "contract-level phenomenology
debugger." What shipped is the READ-ONLY, EXPERT altitude:

- BUILT: A1 construction map (Widget 05) + A1 compile trace (Widget 06) + the READ-ONLY half of A2
  (Widget 07 tournament + stitched timeline).
- NOT BUILT -- and this is exactly the phenomenology Nicholas needs: A2 RIDE-ALONG (s2.2: the run halts
  BEFORE each model call / new context; he walks in, inspects the exact inputs, steps forward) and A3
  POSSESSION + SIDE-BY-SIDE (s2.3/2.4). These were slated LATER + evidence-gated; the finding reprioritizes
  them to the FRONT, because their absence is what blocks auditability today.
- MISSING AS A PRINCIPLE: legibility. The ladder assumed an expert operator. Nicholas requires the surface
  be legible WITHOUT prerequisite schema expertise.

## 2. New load-bearing principle (adds to AUDIT_PIPELINE s3)

**P9 -- phenomenological legibility.** An audit surface is not done when it RENDERS the artifacts; it is
done when Nicholas can FOLLOW a run without prerequisite expertise. Every audited step must present, in
plain language and chronological order, a paired [what this step is SUPPOSED to do] against [its actual
input] and [its actual output], with anomalies surfaced AT the step where they occur, in ONE pathway with
no window-switching. The expert forensic panels (05/06/07) are the DESCENT target, not the top surface.

## 3. The target: the Live-Run Audit Pathway (LRAP)

ONE guided surface that walks a run (live, or a replayed artifact chain) stage by stage in chronological
order. For each pipeline step (normalize -> retrieve -> route -> select -> budget -> packet -> model
invocation -> tool/effect -> verify) it shows four ALIGNED lanes:

1. INTENT (plain language): what this step is for and what a correct result looks like -- authored once per
   stage TYPE, not per run; the "instructions" Nicholas said are missing.
2. INPUT: the actual input to this step, in human terms (not raw schema).
3. OUTPUT: the actual output.
4. RECONCILE: does OUTPUT follow from INPUT under INTENT? a green check, or a plain-language ANOMALY flag
   ("this step dropped record X for reason Y -- expected?") -- the breakpoint.

Descend on anomaly: any step opens the matching forensic widget (05/06/07) already scoped to that step, so
the expert panels become the drill-down REACHED FROM the narrative, never the starting point. Ride-along
(A2.2): at each model-invocation boundary the run can PAUSE (the gateway hold hook, OUTSIDE lease windows --
AUDIT_PIPELINE P3), so Nicholas inspects before the agent moves on. Read-only through A2; the pause hook and
any possession are design-first + red-team-gated (A3 pattern).

## 4. What it reuses (readers over instrumentation -- AUDIT_PIPELINE P1)

Every lane above already has its substrate: the compile stages + counts (Widget 06 pane 1), the four packet
regions (pane 2), selpol `ranked[]`/`reason_codes[]`/`stages[]` + the R-1 `routing_stage_trace` (pane 3),
the fired/excluded/overridden rules (pane 4), the token/state ledger (pane 6), the stitched cross-context
timeline + tournament reconciliations (Widget 07), the omission manifest, #39/#42 lineage. LRAP INSTRUMENTS
NOTHING NEW -- it re-sequences these into a chronological, plain-language, expected-vs-actual narrative and
authors the per-stage INTENT text. Where a plain-language INTENT/RECONCILE cannot be written from existing
artifacts, that gap is a missing trace-emission requirement (P2), never a widget-side fake.

## 5. Reprioritization + recommended sequence (for Nicholas to ratify)

- The audit-program `next_increment` BECOMES LRAP (was A2 ride-along / A3), ahead of A4/A5.
- Recommended (a dedicated step, deferred from i43 to keep this ONE scoped unit): PROMOTE
  `research/2026-08-05-audit-pipeline-target.md` to `core-docs/AUDIT_PIPELINE.md` (its designed home, 24 KB)
  -- add P9, update the cadence header (`last_reviewed i43`, `review_due i47`, `next_increment LRAP`), add
  it to DOC_PROTOCOL s2 + the doc-gate core-doc list. This finding + this note carry current truth until
  then (the AUDIT_PIPELINE doc's own cadence review was due i42 -- this note IS that overdue review).
- Then LRAP proper: its OWN design doc -> a frontier/subagent red-team (the b4c90545 / A3 pattern) -> a
  read-only build increment (the chronological narrative + INTENT authoring + descend-to-widget) on a spare
  coding lane; the ride-along pause hook is a SEPARATE design-first + red-team-gated increment.
- Non-displacement (AUDIT_PIPELINE s6) still holds: LRAP is the audit program's lane, not a jump over the
  standing gates (the rehearsal, #40 sequencing, PB-3).

## 6. Acceptance (what "adequate" means -- the finding's own test)

LRAP is adequate when Nicholas can take a single live/replayed run and, WITHOUT prerequisite schema
knowledge and WITHOUT switching windows, read each step's intent-vs-actual in order and correctly locate a
deliberately-injected bad input (a wrong record, a mis-route, a dropped candidate) AT the step where it
happens -- the phenomenological equivalent of the fold smoke. That "the human found the breakpoint" run is
the gate, mirrored from the side-by-side fixture-minting idea (A3 / AUDIT_PIPELINE 3.5).
