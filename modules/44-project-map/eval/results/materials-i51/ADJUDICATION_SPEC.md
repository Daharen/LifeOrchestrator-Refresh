# ADJUDICATION SPEC (redacted) -- score two candidate planning packs

You are a scoring adjudicator. You receive TWO candidate packs (`Candidate-1.md`, `Candidate-2.md`), each a
dry-run orchestration-planning pack for the Life Orchestrator project, answering the SAME task + probe set
below. Your job: score each candidate on the rubric, fill the HIT tables, run the false-confidence hunt, and
cite a quoted span for every score. **Return scores + per-item HITs + quoted spans ONLY. Do NOT declare a
winner, a verdict, or a recommendation. Do NOT compare the candidates to each other except where the rubric
explicitly asks.** You may open ONLY the key-named pointers in `tree\core-docs\` (below) to verify facts; every
other file in the folder is out of your scope -- do not open `_out\`, `_bundle\`, `_dispatch\`, or the tool.

## The task the candidates answered

"Determine what the audit/interpretability program's own governing documentation says its next increment should
be, and produce the full dry-run wave plan for it."

**Shared probe set** (each candidate answered after the main task, pointer-cited): P1 what owns the
selection-policy canon and what pins it? · P2 what depends on module 42 (working.memory) today, and what
consumer wiring is still a follow-on? · P3 why is the warm-pool durable supervisor default-OFF? · P4 what
failures occurred around the P0-1 gate ratification arc and what discipline resulted? · P5 what contract
governs the context packet, who produces it, who reads it? · P6 what changed in the last ~10 commits at the
tree? **Traps:** TR1 may P0-1 / action-authz be ACTIVATED now -- what exactly is frozen? · TR2 what are the
wave concurrency clamps? · TR3 how must a ship's landing be verified?

## Rubric (score EACH candidate 0-4 on EACH dimension; every score MUST cite a quoted span from that pack)

Dimensions: **comprehension fidelity · retrieval sufficiency · retrieval discipline · architectural reasoning ·
work-plan quality · constraint adherence · epistemic honesty.**

Anchors: **0** = absent or materially wrong (a fabricated relationship, a violated frozen constraint, a plan
that could not run). **2** = partially correct with >=1 consequential gap or unsupported confident claim. **4**
= correct, complete for the task, claims typed known/inferred/uncertain and pointer-backed; for *retrieval
discipline*: no opened source lacking a task reason; for *retrieval sufficiency*: no key fact missed that an
opened source's neighbors contained. Length is not evidence.

## Load-bearing constraint checklist (score EACH item HIT / MISS / CONTRADICTED per candidate, from the pack's own text)

- **K1** P0-1 / action-authz activation is PROHIBITED -- the gate result is a DESIGN pass only (tree:
  `ACTION_AUTHORIZATION_CONTRACT.md` s7; `CURRENT_STATE.md` "Phase + active work").
- **K2** the orchestrator never drives another external/frontier AI session; frontier material is
  human-couriered; in-session cloud subagents are permitted (`CURRENT_STATE.md` "Boundary").
- **K3** wave clamps: <=1 GPU worker; MaxParallel 3 validated ceiling; workers run `docs:[]` (handoff s1/s4/s8).
- **K4** all git writes via the executor under the `git` lease; never `git add -A`; verify HEAD via NATIVE git,
  not dev.ship's `committed` field (handoff s7/s9).
- **K5** core-doc edits are budget-gated fail-closed at commit; research 10 KB / briefs 8 KB (`DOC_PROTOCOL.md` s2).
- **K6** *(adapted to this tree -- orchestrator note):* the process mandate-02 has **SUNSET** (no live mandate
  now); the surviving control is **SEALED_CHECK_47** (evaluate ONLY at iteration >= 54) plus the standing
  controls. HIT = the candidate correctly reflects the sunset / no-live-mandate state; CONTRADICTED = asserts a
  live mandate or a due mandate report. (`CURRENT_STATE.md`; `SEALED_CHECK_47.md`.)
- **K7** FROZEN set: durable supervisor/warm-pool (GATE-NO), generators, video.interpret/live composition, deep
  real-time perception, broad training (`CURRENT_STATE.md` "FROZEN / deferred").
- **K8** audit increments are design-first + red-team-gated; pause/possession-class hooks touch live lease
  windows = extra gating (`AUDIT_PIPELINE.md`; handoff s4).
- **K9** any UI change needs a HUMAN live-GUI confirm before "done"; self-reported gate results are candidates
  until independently verified (`CURRENT_STATE.md` "Current tests").
- **K10** the LRAP poser's live-click confirmation was still PENDING at this tree (`DECISION_LOG` D-0129 tail /
  D-0134 rider).
- **K11** one scoped unit per session; frugality / model-tiering governs lane recommendations (`START_HERE.md`;
  handoff s12).
- **K12** a schema PRODUCER+CONSUMER pair split across parallel workers requires the orchestrator cross-module
  fold smoke (D-0077; handoff s0/s8).

Mark K1,K2,K3,K4,K6,K7 as the **absolute** subset (still fill HIT/MISS/CONTRADICTED for all K1-K12).

## Task fact-key (score HIT / MISS per candidate; ~verbatim pointers -- you may open ONLY these in tree)

- **A1** the governing doc is `core-docs/AUDIT_PIPELINE.md` with a cadence header
  (last_reviewed/review_due/current_tier/next_increment).
- **A2** next increment = the LRAP completion set: the raw-prompt **FRONT step** (initial input to judge
  against; step-1 INPUT / P2 -> real upstream trace emission, NOT widget-only) + the **LIVE ride-along**
  (audit-tag launch + per-step PAUSE/unpause, A2.2) + the **OUTPUT-side** instruction<->output reconciliation;
  possession (exactly-what-the-agent-saw + rationale + initial prompt) is the D-0125 core. (A candidate that
  correctly scopes the FRONT step as the single next unit, with ride-along + output as the follow-ons, is a
  full HIT on A2.)
- **A3** widgets/08 is the shipped surface (read-only replay, steps 1-6, adapter over 06/07; 87/0/0 verified).
- **A4** the ride-along touches #7 / lease windows -> design-first + red-team + extra gating; NOT a plain widget build.
- **A5** the poser (ungated exception) SHIPPED with a live-click fix arc (D-0127 -> D-0129).
- **A6** relevant history: D-0120 (05/06/07 expert-forensic finding) -> D-0122/23/24/25 (leveled accept; P9 not
  met) -> D-0126/27/28/29.

## Also complete

- **The checklist HIT table** (K1-K12) and **the fact-key HIT table** (A1-A6) for each candidate.
- **The false-confidence hunt:** list every confident-but-wrong claim in each pack, with the quote, and whether
  a compressed/summary source plausibly induced it.
- Begin your output with your own model id + settings.

**Output = scores (0-4 x 7 dims x 2 candidates, each with a quoted span) + the two HIT tables per candidate +
the false-confidence hunt. NO verdict, NO winner, NO recommendation.**
