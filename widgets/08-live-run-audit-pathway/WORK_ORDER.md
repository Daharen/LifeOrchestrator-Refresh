# WORK ORDER - Widget 08: Live-Run Audit Pathway (LRAP)

- **id:** `widgets/08-live-run-audit-pathway` - **Phase:** B (Widget layer) #8 - **Status:** MVP (this session, i45; SelfTest-green + cloud-green; human live-GUI confirm PENDING)
- **Realizes:** the audit-pipeline program's `next_increment` **LRAP** -- the PHENOMENOLOGICAL TOP surface
  (D-0120; `AUDIT_PIPELINE.md` principle P9). Brief: `claude/fanout/FANOUT_AGENT_003.md` (i45 plan
  `fo-45-b17a531e`, worker `LRAP-WIDGET08-i45`). **Authoritative spec:**
  `research/2026-08-08-i45-lrap-design.md` (build to it EXACTLY -- s3a the honesty map, s2 the RECONCILE rule;
  11 red-team findings folded). Parent: `research/2026-08-08-i43-live-run-audit-pathway-design.md`. Delivery
  per **D-0038** (native WinForms + `launch.bat`); architecture per the Widget 05/06/07 pattern (**D-0039 /
  D-0049 / D-0060 / D-0064 / D-0068**).

## Purpose

Widgets 05/06/07 render real audit data correctly but are EXPERT-FORENSIC + POST-HOC (D-0120): they assume a
schema-fluent operator. LRAP is the guided TOP surface -- ONE chronological, plain-language, INTENT-vs-actual
narrative of a replayed compile, with anomalies surfaced AT the step where they occur, in ONE pathway with NO
window-switching, so a non-expert can find a bad input WITHOUT prerequisite schema expertise. 05/06/07 are the
DESCEND target reached on anomaly, not the top surface.

**Honest scope (F2/F4).** v1 audits packet ASSEMBLY (the input side, steps 1-6). It does NOT render the
model's actual OUTPUT, so it does not yet deliver the instruction<->output half of D-0120 (that needs a wired
live run with captured output -- the ride-along increment, OUT). A green step means "internally CONSISTENT",
never "correct".

## Scope (the read-only LRAP surface)

The SIX-STEP SPINE (normalize -> retrieve -> route -> select -> budget -> packet) over ONE `#40`
`context_packet/0.2` artifact, each step in FOUR LANES (INTENT / INPUT / OUTPUT / RECONCILE) in plain
language. Steps 7-8 (gate/verify) are NOT built (no wired end-to-end run exists; stitching #43/#37 would imply
a causal run that never happened). A flat (no-router) compile renders step 3 as NOT-APPLICABLE (visible, never
a blank). STRICTLY READ-ONLY: renders pinned identities, RE-COMPILES NOTHING, calls no model, holds no lease,
defines no pause point, writes nothing outside its own `runtime/` dir; `non_execution` holds.

**Non-goals (do NOT build, recorded as follow-ons):** steps 7-8 (gate/verify); the ride-along PAUSE / gateway
hold hook (A2.2); possession (A3 s2.3); side-by-side (A3 s2.4); the instruction<->model-output reconciliation
(needs captured OUTPUT). Any pause point, lease, or model call is OUT. A brand-new widget -> **no `skill.json`**
(OMIT skill_id/skill_dir). Do NOT modify widgets 05/06/07 or #40/#37/#30/#43 or any core-doc (`docs:[]`).

## Architecture (mirrors Widget 05/06/07)

- `LrapReaderAdapter.psm1` -- the PINNED, versioned reader ADAPTER (design s5 / F8) over 06/07's EXISTING
  public pure readers, imported with a NAME PREFIX so they are reused (never re-implemented) and never collide.
  Re-exports ONLY the readers LRAP consumes (`Read-LrapPacket` <- 06 `Read-ContextPacket`;
  `Get-LrapRouterBracket`/`Get-LrapSelectionBracket` <- 07 tournament brackets; the raw 06 panes for the
  "show raw trace" affordance; `Test-LrapTraceSanitized` <- 06 i33 guard) and EXCLUDES the recompute /
  counterfactual entrypoints (contained in the nested import, never re-exported). Ships a CROSS-WIDGET CONTRACT
  TEST (`Test-LrapAdapterContract`) that fails closed when a depended-on 06/07 shape drifts.
- `LiveRunAuditPathway.psm1` -- the WinForms-free driver core (the cloud gate tests it for real): the s3a
  HONESTY MAP (`Get-LrapHonestyMap`; every per-step x per-lane cell fixed AUTH/DATA/VERDICT/P2), the P2 backlog
  (`Get-LrapP2Backlog`; a build output), the s3b INTENT catalog + its own review (`Get-LrapIntentCatalog` /
  `Get-LrapIntentCatalogReview`), the verdict-backed RECONCILE (`Get-LrapStepReconcile` -- ONLY substrate
  set/count/arithmetic identities; no semantic judgment), the four-lane spine (`Get-LrapSpine`), the whole
  model + machine classification (`Get-LrapModel` / `Get-LrapVerdict`), the PLAIN-LANGUAGE descend
  (`Get-LrapStepDescend`) and the on-demand raw-trace affordance (`Get-LrapRawTraceForStep`), the
  `Assert-UnderRuntime` write-guard. Defensive throughout: a load failure degrades to a well-formed ok=false
  model, never a throw.
- `Show-LiveRunAuditPathway.ps1` -- the thin STA WinForms shell: a Dock=Top toolbar (packet path + Browse +
  Refresh, laid out from the toolbar's ACTUAL width in a Resize handler + on Shown, `.GetNewClosure()` -- the
  widget-04 lesson), a read-only header (the overall verdict), a SplitContainer (left = the six-step spine with
  NEUTRAL reconcile markers, prose COLLAPSED; right = the selected step's four lanes with "Show why" +
  "Show raw trace" toggles). `-SelfTest` builds + drives + disposes the form OFF-SCREEN and prints
  `SELFTEST_*_OK` (FORM/MODEL/PANES/RECONCILE/DESCEND/SANITIZE/REFRESH/READONLY/LAYOUT).
- `launch.bat` -- `pwsh -NoProfile -STA -File Show-LiveRunAuditPathway.ps1 %*`.
- `tests/fixtures/mint-fixtures.ps1` + the five committed fixtures (see Test plan).

## Data contract (consumed, read-only)

`lifeorch.context_packet/0.2` (a `#40` 0.8.0/0.9.0 packet) -- via the pinned adapter over 06/07:
`evaluation_hooks.routing_stage_trace` (step-3 router reconcile), `evaluation_hooks.stages`
raw_retrieval/post_filter/packet + `retrieved[]` (step-2 count + step-4 selection reconcile), `token_budget` +
`transport_accounting` (step-5 arithmetic), `identity.selected_record_version_ids` + `evidence.excerpts` +
`selection.features_by_candidate` + `non_execution` (step-6 packet reconcile). CONTEXT_PACKET_CONTRACT
s1/s3/s4/s6/s9. NO recompute; pinned identities only.

## Test plan

Dual-mode `tests/Invoke-LiveRunAuditPathwayTests.ps1` -- cloud gate **104/0/3** (Linux; **-Live** on Windows adds
the WinForms self-test + the poser pop-up round-trip -> **119/0/0**) (over five committed REAL
fixtures minted from the shipped 06/07 routed + flat #40 seeds): the reader adapter + the cross-widget contract
test (drift fails closed; recompute excluded); the honesty map (all 24 cells fixed; every P2 cell a VISIBLE
lane); verdict-backed RECONCILE (named substrate identities; a corrupted count caught; forbidden judgments
logged P2, never smuggled); the FIVE-FIXTURE machine classification (clean -> consistent; mis-route -> step 3;
dropped-candidate -> step 4; wrong-record -> step 6; flat-quirk -> consistent) with FP/FN scored separately;
plain-language descend (names offenders, not the raw pane) + the raw pane behind the affordance; the INTENT
catalog review; byte-identical re-render; the read-only guarantees + i33 sanitization (an injected cross-ns key
fails closed); graceful degradation. `-Live` adds launch.bat shape + the WinForms `-SelfTest` markers + a real
on-box `#40` render.

## Ship

Through the job-runner (`exec-job.sh devship`): sha-verify the shipped files, AST-parse + ASCII-guard, run the
tests `-Live`, commit exactly the `widgets/08-live-run-audit-pathway/` files under the `git` lease with trailers
(CPU lane -- git lease only, no GPU). A brand-new widget -> no `skill.json` (OMIT skill_id/skill_dir). VERIFY
the real HEAD via native git (D-0072). Assert 0 UNMANAGED orphans.

## Acceptance (design s7 -- the phenomenological fold smoke)

Adequate when Nicholas, WITHOUT schema knowledge and WITHOUT window-switching, walks each of the five replayed
fixtures with the RECONCILE prose COLLAPSED on first pass, STATES WHY at each verdict, and correctly
CLASSIFIES it -- flagging each of the three defects at its step and NOT false-flagging the clean + natural-quirk
controls (false-positives + false-negatives scored separately). All three defects are machine-detectable from
existing reconciliation (no smuggled judgment). **This human live-GUI confirm (D-0064) is the ACCEPTANCE GATE**
-- the widget ships SelfTest-green + cloud-green with the confirm FLAGGED PENDING; the ship is not blocked on
it. Each found breakpoint is a candidate `#37` fixture (AUDIT_PIPELINE 3.5).

## Poser increment (D-0126, ungated -- built after i45)

The interpretability POSER adds a per-element **"?"** ("Ask (local 9B)") that opens a modeless chat seeded with
the element's **context bundle** (INTENT + ACTUAL input/output + RECONCILE, a pure projection of `Get-LrapModel`)
and lets Nicholas ask follow-ups; the local 9B **explains the instrument + recorded facts** and is forbidden to
judge whether the run is correct (the F1/P9 line). It ships **UNGATED** (D-0126: pure information; Nicholas is
the red team; writes nothing; must not impede functionality). The read-only posture is **preserved**: the widget
only reads the model + writes request/answer files under `runtime\poser\` (guarded) and spawns the query worker
**DETACHED**; the widget process makes **no model call and holds no lease**. The one model call is out-of-band in
`Invoke-LrapPoserQuery.ps1` over `model.gateway` (#7) / `res.lease` (#29). **Fail-silent** on any error/empty/
timeout. Files: `LrapPoser.psm1` (pure core), `Invoke-LrapPoserQuery.ps1` (worker), `tests/mock-poser-gateway.ps1`
(the no-GPU test stand-in); `Show-*.ps1` gains the "?" + pop-up + `SELFTEST_POSER_OK`. The **information-only
invariant** is the ungate-ability condition -- any change that lets the poser tag/verify/mutate re-opens the gate.
It delivers the D-0125 possession/rationale gap from the ergonomic end; the raw-prompt FRONT step + LIVE
ride-along + OUTPUT-side reconciliation still follow.

## Follow-ons (not this session)

The human live-GUI confirm (D-0064); the P2 trace-emission backlog (step-1 raw pre-normalize instruction;
step-1 R-1 count; the step-2 recall-gap detector -- each a `#40` trace-emission requirement, not a widget-side
workaround); the ride-along PAUSE / gateway hold hook (A2.2 -- touches #7, design-first + red-team-gated); the
instruction<->model-output reconciliation (needs a wired run with captured OUTPUT); possession + side-by-side
(A3); colour/status highlighting + a persisted "last walked" marker under `runtime/`.
