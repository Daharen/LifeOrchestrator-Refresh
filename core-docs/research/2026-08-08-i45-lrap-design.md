# Live-Run Audit Pathway (LRAP) -- i45 build design (concretizes the i43 spec)

**Status:** BUILD DESIGN (i45), red-team-hardened. Parent:
`research/2026-08-08-i43-live-run-audit-pathway-design.md` (the D-0120 finding + four-lane concept).
Program: `AUDIT_PIPELINE.md` (`next_increment: LRAP`; principle P9). Concretizes that spec into ONE
buildable READ-ONLY increment + gate, per Nicholas's i45 direction. An A3-pattern
red-team ran on the draft (11 findings, verdict NEEDS-REWORK) and is FOLDED here -- each fix tagged
inline `(Fn)`, summarized s10. Build mechanics -> the worker WORK_ORDER.

## 0. What i45 builds -- and its honest scope

BUILDS **Widget 08 -- the LRAP surface**: a read-only STA WinForms window that loads a REPLAYED compile
artifact and renders it as ONE chronological, plain-language, expected-vs-actual narrative -- the
phenomenological top surface P9 requires.

**Honest scope (F2/F4).** v1 audits **packet ASSEMBLY** (input side, steps 1-6). It does NOT render the
model's actual OUTPUT, so it does NOT yet deliver the literal "reconcile intuitive instructions against
intuitive OUTPUTS" half of D-0120 -- that needs a wired live run with captured output (the ride-along
increment, OUT). v1 IS the chronological, legible, find-the-breakpoint pathway over the richest-substrate
half of the pipeline, and the prerequisite for the rest. A green step means "internally CONSISTENT,"
never "correct."

OUT (each a separate later gated unit): the ride-along PAUSE / gateway hold hook (A2.2); possession
(A3 2.3); side-by-side (A3 2.4); instruction<->output reconciliation. LRAP v1 holds
no lease, no pause point, calls no model, writes nothing outside its own `runtime/` -> zero
lease-window/wedge risk by construction (P3/P6).

## 1. The pipeline SPINE (steps 1-6) + substrate (readers over instrumentation -- P1)

Steps 7-8 (gate/verify) are CUT from v1 (F6): #43 is a design-only deny-everything constant and #37 a
standalone eval -- neither is from the SAME run as the #40 packet, so a chronological narrative would
imply a causal run that never happened. Spine = steps 1-6 = ONE #40 `context_packet/0.2` artifact,
substrate already parsed by the 06/07 readers:

1 normalize -- `task_input` region + stage-1 counts; 2 retrieve -- selpol `raw_retrieval`/`ranked[]` +
`retrieval_provenance` + i34 V3 completeness; 3 route -- R-1 `routing_stage_trace`; 4 select -- selpol
`post_filter`->`packet` `stages[]` + rule/exception stack + per-drop `omit_reason`; 5 budget -- token +
transport accounting (P0-4) + `consumer_profile`; 6 packet -- the four assembled regions under the
`non_execution` frame. A flat (no-router) compile drops step 3 and still reconciles.

## 2. The four-lane render model + the RECONCILE honesty rule

Each step shows four lanes in plain language, NOT raw schema: **INTENT** (authored once per step TYPE,
s3b), **INPUT**, **OUTPUT**, **RECONCILE**. RECONCILE (F1) may ONLY re-express a verdict the substrate
already COMPUTES -- a set/count identity from the W07 tournament or an arithmetic check. It may NOT
introduce semantic judgment (is this `omit_reason` justified? should a successor exist?); such judgment
is FORBIDDEN in v1 and logged as a P2 gap. RECONCILE renders as a
neutral consistent / INCONSISTENT-here marker on first pass with the naming prose COLLAPSED until opened
(F5), so the gate tests whether the PATHWAY is legible, not whether a red label is readable. Green =
"counts reconcile," necessary-not-sufficient (F2) -- never "fine."

## 3a. The per-step x per-lane HONESTY MAP (fixed HERE, not deferred to the worker -- F3)

`AUTH`=authored static INTENT; `DATA`=rendered from the artifact verbatim; `VERDICT`=re-expresses a
tournament/arithmetic identity; `P2`=not emitted by any existing artifact -> rendered as an explicit
"trace-emission follow-on logged," NEVER a computed stand-in.

| step | INTENT | INPUT | OUTPUT | RECONCILE |
|---|---|---|---|---|
| 1 normalize | AUTH | **P2** (raw pre-normalize instruction not a mandated artifact) | DATA `task_input` | **P2** (normalize emits no R-1 count) |
| 2 retrieve | AUTH | DATA | DATA `ranked[]` | VERDICT raw count; recall-gap (should-have-been-fetched but was not) = **P2**, undetectable from a presence-only trace (F10) |
| 3 route | AUTH | DATA | DATA trace | VERDICT `in-|removed|==out`, `out[n]==in[n+1]` |
| 4 select | AUTH | DATA `ranked[]` | DATA `packet` | VERDICT `packet<=post<=raw` (subset chain); every drop carries an `omit_reason` (PRESENCE, not validity) |
| 5 budget | AUTH | DATA | DATA ledger | VERDICT `sum(selected)<=budget`; transport identity |
| 6 packet | AUTH | DATA regions | DATA packet | VERDICT packet==step-4 output; trust banners + `non_execution` frame present |

Every `P2` cell is a build OUTPUT of i45 (the logged trace-emission backlog) AND renders on the surface
as a visible "not emitted yet" lane, so a blank never reads as "fine." The worker implements THIS map;
it does not decide honesty.

## 3b. The INTENT catalog + its own review gate (F11)

The six per-step INTENT blocks are the yardstick every RECONCILE is judged against; a subtly wrong one
silently mis-judges every run and a non-expert cannot detect a bent yardstick. So the catalog gets its
OWN gate, separate from the find-the-breakpoint gate: each block cites the contract clause it paraphrases
(CONTEXT_PACKET_CONTRACT / selpol / rule set), is version-stamped, and is reviewed against those clauses
(reviewer named in the report).

## 4. Descend-on-anomaly -- plain-language, NOT a raw panel (F7)

Descend is an INLINE drill-down (no window-switching, P9), but NOT a raw re-render of the 06/07 expert
pane -- that would re-import the schema-vocabulary illegibility P9 exists to remove. It shows a
plain-language "WHY this step flagged": the specific records/counts, named in prose, with the identity
that failed. The raw forensic pane stays reachable as an explicit "show the raw trace" affordance, never
the default. A step with no authorable plain-language descend is a P2 gap, not a relocated panel.

## 5. Reader reuse + new-vs-extend (F8/F9)

Importing the 06/07 `.psm1` wholesale would couple LRAP to internal signatures (a future 06/07 refactor
breaks LRAP silently, since their tests exercise WINDOWS not LRAP's consumption) and drag in Widget 06's
counterfactual RE-compile entrypoint (which LRAP must never call). So Widget 08 owns a **pinned,
versioned reader ADAPTER** over 06/07's EXISTING public pure-read functions (read-packet, selpol stages,
routing trace, rule stack, ledger) -- NO 06/07 refactor -- plus a **cross-widget contract test** (in 08's
suite) that fails when a depended-on 06/07 shape drifts; recompute entrypoints EXCLUDED. Chosen: a NEW
Widget 08 (not a tab in 06) --
LRAP's audience/altitude differ from 06's expert console, it needs BOTH 06's panes and 07's tournament,
and keeping 06 unchanged preserves the shipped tool.

## 6. Data source: the replay artifact chain

v1 loads a COMPLETED compile from mandated artifacts alone (AUDIT_PIPELINE 1.1): one #40
`context_packet/0.2` (+ its #30 plan only for step-3/4 tournament context); pinned identities, NO
recompute to render. Default: the newest real #40 runtime artifact, else a bundled fixture (reusing the
Widget 06 resolution order).

## 7. Acceptance -- the phenomenological fold smoke, hardened (F5)

Adequate when Nicholas, WITHOUT schema knowledge and WITHOUT window-switching, walks a replayed run and
correctly CLASSIFIES it. FIVE fixtures, each a real/minted #40 artifact: wrong record
(a record the `current_only` rule FIRED against still present in the packet -- a step-4/6 consistency
violation); mis-route (a `routing_stage_trace` chain break `out[n]!=in[n+1]` at step 3); dropped
candidate (a candidate in `raw` absent from `post` with NO `omit_reason` -- missing, not "unjustified"
-- at step 4); clean control (valid run; he must say "consistent"); natural-quirk control (a legitimate
drop / a flat no-router compile; he must NOT false-flag it). All three defects are machine-detectable
from existing reconciliation (no smuggled judgment). GATE: a human live-GUI confirm (D-0064) with
RECONCILE prose collapsed on first pass; Nicholas STATES WHY at each verdict; FP and FN scored
separately. Each found breakpoint is a candidate #37 fixture (AUDIT_PIPELINE 3.5).

## 8. Binding non-goals + non-displacement

Environment not mind (P8); consistency != correctness (F2); input-side only, no output loop (F4); recall
gaps undetectable, stated on the surface (F10); zero new trace emission, unwritable lanes logged P2 never
faked (P1). Non-displacement (AUDIT_PIPELINE s6): LRAP does not jump the standing gates (rehearsal, #40
sequencing, PB-3, the P0-1 suite); it makes the D-0050 VERIFY half cheaper, not total comprehension.

## 9. Build shape (mechanics -> WORK_ORDER)

A NEW `widgets/08-live-run-audit-pathway/` mirroring 05/06/07: WinForms-free driver core + thin STA
shell (`-SelfTest` off-screen, `SELFTEST_*_OK` incl. `LAYOUT_OK`/`READONLY_OK`) + `launch.bat` +
dual-mode tests (cloud gate FIRST, then `-Live`, then the human live-GUI confirm) + the shared reader
interface & contract test (s5) + the five fixtures. Ships via `dev.ship`, `docs:[]`. Worker on Opus 4.8
Extra (audit-critical; the honesty map is unusually easy to over-claim).

## 10. Red-team (A3, folded)

11 findings, verdict NEEDS-REWORK -> SHIP-WITH-FIXES after folding; each fix tagged `(Fn)` inline.
Criticals: F1 forbid JUDGMENT lanes (s2/s3a); F2 green=consistent-not-correct; F3 honesty map in-design
(s3a); F4 scope stated, output loop deferred (s0). Majors: F5 gate controls (s7), F6 cut 7-8 (s1), F7
plain-language descend (s4), F8 pinned reader interface (s5), F9/F10/F11 (s5/s3a/s3b). Preserved intact:
the four-lane chronological plain-language frame; the read-only/no-lease/`non_execution` posture.
