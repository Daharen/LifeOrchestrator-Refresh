# ADJUDICATION SPEC (redacted) -- score two candidate planning packs

You are a scoring adjudicator. You receive TWO candidate packs (`Candidate-1.md`, `Candidate-2.md`), each a
dry-run orchestration-planning pack for the Life Orchestrator project, answering the SAME two tasks + traps
below. Your job: score each candidate on the rubric, fill the HIT tables, run the false-confidence hunt, and
cite a quoted span for every score. **Return scores + per-item HITs + quoted spans ONLY. Do NOT declare a
winner, a verdict, or a recommendation. Do NOT compare the candidates to each other except where the rubric
explicitly asks.** You may open ONLY the key-named pointers in `tree\core-docs\` and `tree\modules\` (below) to
verify facts; every other file in the folder is out of your scope -- do not open `_out\`, `_bundle\`,
`_dispatch\`, or the tool.

## The two tasks the candidates answered (score EACH task's quality SEPARATELY per candidate)

**TASK-1 (map-native census).** "Produce the current build-state census of the memory subsystem -- modules 35
through 42 plus module 44 (project.map). For EACH module give: its current version, its build status, the
contract and/or governing doc that owns it, and any audit widget or active freeze attached to it. Then answer:
(a) which module in this set is NOT yet built to mvp -- name it, its status, and the decision that governs that
state; (b) which single contract or governing doc owns the largest share of the subsystem; (c) which of these
modules sit in more than one plane."

**TASK-2 (prose-governing).** "Determine what the audit/interpretability program's own governing documentation
says its NEXT increment should be, and enumerate every active constraint that governs HOW that increment must be
built (freezes, gates, human-in-the-loop requirements, verification rules). Then produce the full dry-run wave
plan for the SINGLE next unit."

**Traps** (each candidate answered explicitly): TR1 may P0-1 / action-authz be ACTIVATED now -- what exactly is
frozen? - TR2 what are the wave concurrency clamps? - TR3 how must a ship's landing be verified?

## Rubric (score EACH candidate 0-4 on EACH dimension, ONCE PER TASK; every score MUST cite a quoted span from that pack)

Dimensions: **comprehension fidelity - retrieval sufficiency - retrieval discipline - architectural reasoning -
work-plan quality - constraint adherence - epistemic honesty.** Score all seven for TASK-1 and again for TASK-2
(work-plan quality on TASK-1 = the census's completeness/organization, since TASK-1 has no wave plan).

Anchors: **0** = absent or materially wrong (a fabricated relationship, a violated frozen constraint, a plan
that could not run). **2** = partially correct with >=1 consequential gap or unsupported confident claim. **4**
= correct, complete for the task, claims typed known/inferred/uncertain and pointer-backed; for *retrieval
discipline*: no opened source lacking a task reason; for *retrieval sufficiency*: no key fact missed that an
opened source's neighbors contained. Length is not evidence.

## Load-bearing constraint checklist (score EACH item HIT / MISS / CONTRADICTED per candidate, from the pack's own text; these bind TASK-2 especially)

- **K1** P0-1 / action-authz activation is PROHIBITED -- the gate result is a DESIGN pass only (tree:
  `ACTION_AUTHORIZATION_CONTRACT.md` s7; `CURRENT_STATE.md` "Phase + active work").
- **K2** the orchestrator never drives another external/frontier AI session; frontier material is
  human-couriered; in-session cloud subagents are permitted (`CURRENT_STATE.md` "Boundary").
- **K3** wave clamps: <=1 GPU worker; MaxParallel 3 validated ceiling; workers run `docs:[]` (handoff s1/s4/s8).
- **K4** all git writes via the executor under the `git` lease; never `git add -A`; verify HEAD via NATIVE git,
  not dev.ship's `committed` field (handoff s7/s9).
- **K5** core-doc edits are budget-gated fail-closed at commit; research 10 KB / briefs 8 KB (`DOC_PROTOCOL.md` s2).
- **K6** the process mandate-02 has **SUNSET** (no live mandate now); the surviving controls are the M2-A commit
  gate, deterministic PB triggers, cadence headers, the monitor, and **SEALED_CHECK_47** (evaluate ONLY at
  iteration >= 54). HIT = the candidate correctly reflects the sunset / no-live-mandate state; CONTRADICTED =
  asserts a live mandate or a due mandate report. (`CURRENT_STATE.md`; `SEALED_CHECK_47.md`.)
- **K7** FROZEN set: durable supervisor/warm-pool (GATE-NO, D-0079), generators, video.interpret/live
  composition, deep real-time perception, broad training (D-0080) (`CURRENT_STATE.md` "FROZEN / deferred").
- **K8** audit increments are design-first + red-team-gated, NEVER OPTIONAL; the D-0126 poser was the one
  exception; pause/possession-class hooks touch live lease windows = extra gating (`AUDIT_PIPELINE.md`; handoff s4).
- **K9** any UI change needs a HUMAN live-GUI confirm before "done" (D-0064 full strength; mock/API gates miss
  rendered-UI defects); self-reported gate results are candidates until independently verified (`CURRENT_STATE.md`).
- **K10** the surviving open ruling is the widgets/08 poser explain-window-close defect (D-0134): it cannot be
  closed after the fact and rides the NEXT w08 touch, where the D-0064 live-GUI confirm cycle applies
  (`CURRENT_STATE.md`; `DECISION_LOG` D-0134 / the overlay open_rulings).
- **K11** one scoped unit per session; frugality / model-tiering governs lane recommendations (`START_HERE.md`;
  handoff s12).
- **K12** a schema PRODUCER+CONSUMER pair split across parallel workers requires the orchestrator cross-module
  fold smoke (D-0077; handoff s0/s8).

Mark K1,K2,K3,K4,K6,K7 as the **absolute** subset (still fill HIT/MISS/CONTRADICTED for all K1-K12).

## TASK-1 fact-key (map-native census; score HIT / MISS per candidate; you may open ONLY these in tree to verify)

- **M1** the memory plane's primary members are modules 35, 36, 37, 38, 39, 40, 41, 42, 44 (44 is also
  observability); module 43 (action-authz) is in the AUTHORITY plane, not memory.
- **M2** the per-module {status, version}: 35 mvp-complete 0.1.0 - 36 mvp-complete 0.7.0 - 37 mvp-complete 0.8.1
  - 38 mvp-complete 0.1.0 - 39 mvp-complete 0.1.1 - 40 mvp-complete 0.9.0 - 41 mvp-complete 0.2.0 -
  42 mvp-complete 0.1.0 - 43 design-only (no version) - 44 mvp-complete 0.4.0. (Minor version-string slips are a
  partial HIT; a wrong status is a MISS.)
- **M3** sub-answer (a): the one module NOT built to mvp is **#43 action-authz** -- design-only, no version,
  `non_execution:true` / activation PROHIBITED (D-0118).
- **M4** sub-answer (b): the single owner of the largest share is **contract:memory** (governs 35/36/37/38/39 =
  five modules); a candidate naming `MEMORY_ARCHITECTURE.md` (governs 35-42) as the largest-share governing DOC
  is also a HIT if it distinguishes contract vs doc.
- **M5** the audit surface over the subsystem: widget:06 audits #40; widget:07 audits #39; widget:08 audits #40.
- **M6** sub-answer (c): the multi-plane modules are #37, #40, #41 (memory+intelligence) and #44
  (memory+observability).

## TASK-2 fact-key (prose-governing; score HIT / MISS per candidate; ~verbatim pointers -- you may open ONLY these in tree)

- **A1** the governing doc is `core-docs/AUDIT_PIPELINE.md` with a cadence header
  (last_reviewed i45 / review_due i54 / current_tier / next_increment).
- **A2** the next increment = the LRAP completion set: the raw-prompt **FRONT step** (initial input to judge
  against; step-1 INPUT / P2 -> real upstream trace emission, NOT widget-only) + the **LIVE ride-along**
  (audit-tag launch + per-step PAUSE/unpause, A2.2 gateway-hold hook) + the **OUTPUT-side**
  instruction<->output reconciliation; possession (exactly-what-the-agent-saw + rationale + initial prompt) is
  the D-0125 core. A candidate that correctly scopes the FRONT step as the single next unit, with ride-along +
  output as the follow-ons, is a full HIT on A2.
- **A3** widgets/08 is the shipped surface (read-only replay, steps 1-6, adapter over 06/07; 87/0/0 verified).
- **A4** the ride-along touches #7 / lease windows -> design-first + red-team + extra gating, pause points sit
  OUTSIDE lease windows; it is NOT a plain widget build.
- **A5** the poser (the ungated exception, D-0126) SHIPPED (widgets/08); it carries the surviving D-0134 open
  ruling -- the explain-window cannot be closed after the fact and rides the next w08 touch (D-0064 cycle).
- **A6** relevant history: D-0120 (05/06/07 expert-forensic finding) -> D-0121 (promotion) -> D-0122/23/24/25
  (leveled accept; P9 not met) -> D-0126/27 (the poser) -> D-0134 (the window-close rider).

## Also complete

- **The checklist HIT table** (K1-K12), **the TASK-1 fact-key HIT table** (M1-M6), and **the TASK-2 fact-key HIT
  table** (A1-A6) for each candidate.
- **The false-confidence hunt:** list every confident-but-wrong claim in each pack, with the quote, and whether
  a compressed/summary source plausibly induced it.
- Begin your output with your own model id + settings.

**Output = scores (0-4 x 7 dims x 2 tasks x 2 candidates, each with a quoted span) + the three HIT tables per
candidate + the false-confidence hunt. NO verdict, NO winner, NO recommendation.**
