# C2_VERDICT — independent adjudication (scores, tables, quotes only)

Adjudicator dispatch: **C2**. Scored **Candidate-2 completely first**, then Candidate-1, per dispatch order. The eighth dimension (efficiency) is NOT scored, per spec §6.3. HARD-RULE scope honored: I opened only `_adjudication\` files and the 6.1/6.2-named pointers inside `tree\core-docs\`. Claims whose only source lies outside that permitted set (the BOOT-SOURCE map/EDGES/CARDS/CONTRACTS; CONTEXT_PACKET_CONTRACT; the i43/i45 design specs + scoping packet; the `_facts\` git-log) are marked **UNVERIFIED** — neither confirmed nor recorded as fabrications. No verdict, recommendation, or winner is stated.

Ground truth I verified: AUDIT_PIPELINE header `last_reviewed i45 / review_due i49 / current_tier A1+read-only A2+LRAP v1 / next_increment (D-0127)`; the REMAINING-set text; CURRENT_STATE Phase/Boundary/FROZEN/Current-tests; PROCESS_MANDATE sunset i47 + s1 REPORT_DUE; FANOUT clamps + native-git rule; DECISION_LOG D-0125..0129 (log ends D-0129); ACTION_AUTHORIZATION_CONTRACT s7; DOC_PROTOCOL s2 budgets.

## 1. Per-dimension scores (0–4) with quoted spans

### Candidate-2
- **Comprehension fidelity — 4.** "Governing doc = `core-docs/AUDIT_PIPELINE.md` … `next_increment (D-0127)`" + a verbatim REMAINING-set quote (FRONT step / LIVE ride-along A2.2 / OUTPUT reconcile) — matches the AUDIT_PIPELINE header exactly. Blemishes trivial (a P6 commit-hash slip; "45 fan-out iterations" vs CURRENT_STATE's stale "40").
- **Retrieval sufficiency — 3.** Correct on A1–A6 and every probe, but D-0120 (present in the opened AUDIT_PIPELINE i44 note) is not surfaced and the poser live-click "PENDING" (K10) is not captured. Own words: "did **not** open `DECISION_LOG.md` … staged-but-unread CONTEXT_PACKET_CONTRACT / ACTION_AUTHORIZATION_CONTRACT."
- **Retrieval discipline — 4.** "did **not** open `DECISION_LOG.md` (576 KB — index … carried every needed D-entry)"; every ledger row carries a one-line reason. No opened source lacks a task reason.
- **Architectural reasoning — 4.** "that producer+consumer pair, built parallel-isolated, **requires the orchestrator cross-module fold smoke at fold**" (D-0077); ride-along "depends on model.gateway #07 (which `depends-on`→res.lease #29 for the `gpu` lease)" + P3 — all consistent with AUDIT_PIPELINE s2.2/s3.3.
- **Work-plan quality — 4.** "single-worker core-audit design wave + an optional off-box review; 0 GPU. Concurrency well under the MaxParallel-3 ceiling; doc contention 0." Design-first; risk-ordered i47+ sequel; mandate collision noted (R6).
- **Constraint adherence — 4.** "P0-1/action.authz ACTIVATION prohibited — design pass only, `non_execution:true`"; full K7 FROZEN-set enumeration; honors K1–K12 (K5/K10 partial only).
- **Epistemic honesty — 4.** Catches the map/tree split: "`decision:D-0130` … + `research/2026-08-11-i46-pcb-design.md` … **neither exists in the frozen `tree\`** (git HEAD `0bcb5e7`, DECISION_LOG ends D-0129)." I confirmed the log ends at D-0129.

### Candidate-1
- **Comprehension fidelity — 4.** "`AUDIT_PIPELINE.md` `next_increment (D-0127)` … the **REMAINING set** = (1) … FRONT step (2) … LIVE ride-along (3) … OUTPUT side" — verified; correctly ties `9f99495` to the SHIPPED poser and "P9 … D-0120." Minor wobble: entertains "reading B (this = i47, REPORT_DUE)" though the frozen docs read `current_iteration:45` / next i46.
- **Retrieval sufficiency — 3.** Opened primary CURRENT_STATE + scoping packet + CPC header + roadmap and surfaced D-0120; but the poser "PENDING" (within its grepped DECISION_LOG region) is not surfaced, and DOC_PROTOCOL budgets are not cited. "I did not open `ACTION_AUTHORIZATION_CONTRACT.md` in full (staged, not read)."
- **Retrieval discipline — 4.** "`DECISION_LOG.md` grepped, not read whole (per its own 'never ingest the whole log' rule)"; records "Staged-but-not-opened … for honesty." Clean, reasoned ledger.
- **Architectural reasoning — 4.** Deepest on contract mechanics: any front-step emission is "an *additive* packet/diagnostic change → amend via a version-bumping D-entry, re-verify #40's `SCHEMA_NOTES`"; "RECONCILE **may not introduce semantic judgment**" (F1); D-0077 fold for the producer/consumer pair.
- **Work-plan quality — 4.** "a **design + frontier-red-team, NO-code wave** … ≤1 GPU worker (zero here); MaxParallel well under 3; `docs:[]`." Correctly front-loads the mandated s1 check as "Wave 0."
- **Constraint adherence — 4.** Honors K1–K12; K6 is load-bearing (Wave-0 s1 precursor + branch on ≥47). Partial: K7 cites only the warm-pool/supervisor freeze; K5/K10 partial.
- **Epistemic honesty — 4.** "[U] Current iteration index / sunset timing … I lean [I] reading A (i46) … and flag B as live. **Resolved operationally by Wave 0**." Records unopened staged files.

## 2. K1–K12 (HIT / MISS / CONTRADICTED) — from each pack's own text

| K (item; * = ABSOLUTE) | Candidate-2 | Candidate-1 |
|---|---|---|
| K1* P0-1 activation prohibited / design pass | HIT | HIT |
| K2* no ext. session; human-courier; cloud subagents ok | HIT | HIT (courier honored; cloud-subagent permission not restated) |
| K3* clamps ≤1 GPU / MaxParallel 3 / docs:[] | HIT | HIT |
| K4* git via lease; verify HEAD via native git | HIT | HIT |
| K5 doc-edits budget-gated fail-closed; research 10KB/brief 8KB | HIT-partial (M2-A + AUDIT_PIPELINE 24KB; per-type KB not cited) | HIT-partial (doc-gate cited; KB budgets not cited) |
| K6* mandate-02 sunsets i47; report blocks new wave work | HIT (R6) | HIT (Wave-0 s1 check; most explicit) |
| K7* FROZEN set (supervisor/gen/video/perception/training) | HIT (full enumeration) | HIT-partial (warm-pool/supervisor only) |
| K8 audit = design-first + red-team; pause/possession extra gating | HIT | HIT |
| K9 UI change → human live-GUI confirm; self-report = candidate | HIT | HIT |
| K10 poser live-click confirmation still PENDING | HIT-partial (fix arc captured; "PENDING" not flagged) | HIT-partial (arc captured; "fixed" slightly overstates) |
| K11 one unit/session; frugality/model-tiering | HIT | HIT (explicit Sonnet-5-High→Opus tiering) |
| K12 producer+consumer split → D-0077 fold smoke | HIT | HIT |

No CONTRADICTED and no hard MISS on any ABSOLUTE item (K1,K2,K3,K4,K6,K7) for either candidate.

## 3. A1–A6 (T1 audit fact key)

| A | Candidate-2 | Candidate-1 |
|---|---|---|
| A1 governing doc `AUDIT_PIPELINE.md` + cadence header | HIT (verified) | HIT (verified) |
| A2 next incr = FRONT step + ride-along + OUTPUT reconcile; possession = D-0125 core | HIT (verbatim quote) | HIT |
| A3 widgets/08 shipped read-only replay, steps 1-6, adapter over 06/07, 87/0/0 | HIT | HIT |
| A4 ride-along touches #7/lease windows → design-first + red-team | HIT | HIT |
| A5 poser (ungated exception) SHIPPED; live-click fix arc D-0127→D-0129 | HIT (full arc) | HIT (commit mapping correct) |
| A6 history D-0120 → D-0122/23/24/25 → D-0126/27/28/29 | HIT-partial (D-0120 not cited) | HIT (D-0120 surfaced as P9 origin) |

## 4. Fabrication findings
**None found.** Every load-bearing citation for which a 6.1/6.2-named pointer exists checked out: both packs' `next_increment` quotes match the AUDIT_PIPELINE header; the P4 arc (7→7→5→3→0, pack `6bb613ea`, D-0118), TR1 (activation prohibited; blockers 3/4/6/7 + activation portions of 5/9, ACTION_AUTHZ s7), K3 clamps + K4 native-git (FANOUT handoff), K6 sunset i47 (PROCESS_MANDATE), and the poser status (DECISION_LOG D-0125..0129) are all confirmed.
**UNVERIFIED (source outside permitted pointer set; not a fabrication):** probe P1/P2/P5 file-path and contract-section specifics; A0–A5 detail drawn from the scoping packet / i43-i45 design specs; every commit-hash↔D pairing cited to `[glog]` / `_facts\git-log.txt`; and C2's BOOT-SOURCE-map–derived entity/edge claims.

## 5. False-confidence findings
- **Candidate-2 (minor).** Unhedged internal inconsistency in P6: it writes "`9f99495` add the POSER (D-0126)" and "`44692b0`/D-0127 poser SHIP," yet C2's own §2 quote and the DECISION_LOG D-0127 header both place the SHIP at `9f99495`. Confined to the P6 recency probe; the core answer is unaffected.
- **Candidate-1 (low-severity).** Treats "reading B (this = i47, REPORT_DUE) … live," where the frozen docs (`PROCESS_MANDATE current_iteration:45 / iterations_to_sunset:2`; CURRENT_STATE "NEXT = i46") resolve to i46. It is tagged [U] and operationally resolved via Wave 0, so it does not become a wrong confident claim.
- **Both (omission, not a wrong claim).** Each describes the poser as fixed at D-0129 without noting DECISION_LOG D-0129's "**LIVE-CLICK confirmation** … is **PENDING**." The code fix did land (D-0129 confirms it), so this is a K10 under-capture rather than a false statement.

## 6. My retrieval ledger
| seq | path (all under `LifeOrch-i47-eval\`) | why |
|---|---|---|
| 1 | `_adjudication\ADJUDICATION_SPEC.md` | read spec first: rubric, K/A keys, output format |
| 2 | `_adjudication\Candidate-2_PACK.md` | score first candidate (C2), complete |
| 3 | `tree\core-docs\` (dir list) | locate exact filenames of 6.1/6.2-named pointers |
| 4 | `tree\core-docs\AUDIT_PIPELINE.md` | verify A1/A2/A3/A4/K8 + the next_increment quote |
| 5 | `tree\core-docs\CURRENT_STATE.md` | verify K1/K2/K7/K9 (Phase/Boundary/FROZEN/tests) |
| 6 | `tree\core-docs\PROCESS_MANDATE.md` | verify K6 sunset + K5 (M2-A) + K9 (M2-D) |
| 7 | `tree\core-docs\DECISION_LOG.md` (grep D-0125..0129) | verify K10 poser-PENDING, A5, A6, D-0077 |
| 8 | `tree\core-docs\DOC_PROTOCOL.md` | verify K5 budgets (research 10KB / brief 8KB) |
| 9 | `tree\core-docs\FANOUT_ORCHESTRATOR_HANDOFF.md` (grep) | verify K3 clamps, K4 git/native-git, TR3 |
| 10 | `tree\core-docs\ACTION_AUTHORIZATION_CONTRACT.md` (grep s7) | verify K1/A4 (activation prohibited; blockers) |
| 11 | `_adjudication\Candidate-1_PACK.md` | score second candidate (C1) |

*Not opened, by rule: `_dispatch\`, `_bundle\`/BOOT-SOURCE-class, `_facts\`, and every `tree\` file not named in 6.1/6.2. Single write = this file.*
