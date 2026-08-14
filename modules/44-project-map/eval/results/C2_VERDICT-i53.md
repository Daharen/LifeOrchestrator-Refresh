# C2_VERDICT — blind scoring adjudication (Adjudicator C2)

**Adjudicator model + settings.** Model id `claude-opus-4-8`, running as i53 Agent C2 (blind scoring adjudicator, read-only). No sampling knobs exposed in-session; default config assumed. Scored strictly per `_adjudication/ADJUDICATION_SPEC.md`. Order: **Candidate-2 first, then Candidate-1.** Each candidate scored on both TASK-1 and TASK-2 across the 7 rubric dimensions (0–4), plus the K1–K12 / M1–M6 / A1–A6 HIT tables and a false-confidence hunt. **Scores + HITs + quoted spans only — no verdict, no winner, no recommendation.**

Fact-verification opens (spec-named tree pointers ONLY): `ACTION_AUTHORIZATION_CONTRACT.md` (s0/s1/s7), `CURRENT_STATE.md`, `FANOUT_ORCHESTRATOR_HANDOFF.md`, `DOC_PROTOCOL.md` (s2), `SEALED_CHECK_47.md`, `AUDIT_PIPELINE.md`, `MEMORY_ARCHITECTURE.md`, `START_HERE.md`. No `C*_VERDICT`, `_facts/`, DECISION_LOG body, field contracts, or map tool were opened.

---

# CANDIDATE-2

## Per-task rubric scores (0–4), each with a quoted span

### TASK-1 (map-native census)

| dimension | score | quoted span from Candidate-2 |
|---|---|---|
| comprehension fidelity | **2** | "Planes = the D-0080 **Collective Agent planes** (Memory · Retrieval · Context-compiler · Skill-activation · Episode/failure/procedure · Sandboxed-worker · Unified interface)" — substitutes a 7-way doctrine taxonomy for the map's 5 plane tags (memory/intelligence/capability/authority/observability), so (c) is answered against the wrong concept. |
| retrieval sufficiency | **2** | "I did **not** open … #44's map edges — the roadmap+architecture docs already name owners and planes, so they'd add bytes without changing answers; (c) is thus marked inferred." — the plane/`governs` edges it skipped were exactly the facts that would have changed (b) and (c). |
| retrieval discipline | **4** | "I did **not** open the two large field contracts (MEMORY_CONTRACT 44 KB, CONTEXT_PACKET 35 KB) or #44's map edges … they'd add bytes without changing answers" — every opened source carries a stated task reason; no unjustified opens. |
| architectural reasoning | **2** | "**#36 artifact.search — Memory + Retrieval.** … Strongest case." and "It owns **6 of the 9**: #35, #36, #38, #39, #41, #42." — both the multi-plane set and the contract-ownership membership are constructed wrong. |
| work-plan quality (census completeness/organization) | **3** | Full 9-row table + (a)/(b)/(c) sub-answers, sourced: "Table sources: `MODULE_ROADMAP.md:271-349`, `CURRENT_STATE.md:24-32,126-135,240-250`, `ARCHITECTURE_MAP.md:130-150` …" — complete and well-organized, docked for the materially wrong (c) sub-answer. |
| constraint adherence | **4** | "**Dry-run discipline observed:** no writes except this file in `_out\`; no executor jobs / leases / commits / dispatches." — no frozen-constraint violation; #43 correctly flagged "activation *prohibited*." |
| epistemic honesty | **3** | Exemplary flagging of the inference — "the machine-checkable module→`plane:` edges live in #44's map state, which I did **not** open — so (c) is inferred" — but undercut by typing a wrong count as known: "It owns **6 of the 9** … **[K].**" |

### TASK-2 (prose-governing: next increment + wave plan)

| dimension | score | quoted span from Candidate-2 |
|---|---|---|
| comprehension fidelity | **4** | "**Derived SINGLE next unit = the raw-prompt FRONT step [I, well-grounded].**" — correctly scopes the front step as the one next unit with ride-along + output as follow-ons. |
| retrieval sufficiency | **2** | "`AUDIT_PIPELINE.md` (AP) … is primary and self-sufficient; the handoff + CURRENT_STATE supplied wave/lane/lease/verification mechanics" — yet the D-0134 w08 window-close rider and the D-0080 FROZEN set, both present in those opened docs, are never surfaced. |
| retrieval discipline | **4** | "**Deliberately not opened:** `DECISION_LOG.md` (635 KB, index-routed; no single D-entry was decision-changing here) and `BOOT-SOURCE-dir\` (out of condition)." — tight, task-justified open set. |
| architectural reasoning | **3** | "the front step both closes the residual D-0125 gap and unblocks (3)" — sound derivation and constraint mapping, but misses the front-step→w08→D-0134 coupling. |
| work-plan quality | **3** | "**Wave i53-AUDIT-FRONT** … **Lane 1 — Design/coding (CPU, no GPU)** … **Lane 2 — Frontier-review (off-box, human-couriered) · REQUIRED**" + a stated follow-on build wave — runnable and correctly clamped, but the w08 build wave omits the mandated D-0134 window-close fix. |
| constraint adherence | **2** | The 14-item constraint list (3b) enumerates design-first/red-team, leases, R-1, non_execution, SEALED_CHECK_47 — but omits the **absolute K7 FROZEN set** and the **K10 D-0134 rider**; e.g. "**SEALED_CHECK_47** stays sealed at i53 (open only i≥54)" is present while the frozen-set and window-close constraints are absent. |
| epistemic honesty | **4** | "**Framing / honesty [K]:** dry-run derivation. i53's actual expected action is the migration-gate staging decision; **AUDIT is one deferred-menu item**, review not due until **i54**." — does not overclaim the increment as the live i53 action. |

## K1–K12 load-bearing checklist (HIT / MISS / CONTRADICTED)

| key | result | quoted span (or absence) |
|---|---|---|
| K1 (absolute) — P0-1 activation PROHIBITED, DESIGN pass only | **HIT** | "**No — activation is prohibited.** #43 is a **RATIFIED DESIGN pass** … 'a design pass, NOT an activation grant.'" |
| K2 (absolute) — no orchestrator-driven frontier; human-couriered; cloud subagents permitted | **HIT** | "frontier lane human-couriered only (D-0051/52)"; "**Lane 2 — Frontier-review (off-box, human-couriered)**" (in-session-subagent clause not stated). |
| K3 (absolute) — ≤1 GPU; MaxParallel 3 ceiling; `docs:[]` | **HIT** | "**≤1 GPU worker per wave (HARD CLAMP).** **MaxParallel 3 = 1 GPU + 2 CPU** (validated ceiling) … `docs:[]` → **doc contention 0**." |
| K4 (absolute) — git via executor/`git` lease; never `git add -A`; verify HEAD native git | **HIT** | "**Verify the real HEAD via NATIVE git** … **NOT** the `dev.ship` `committed` field … (**D-0072**)." (explicit "never `git add -A`" not stated) |
| K5 — core-doc edits budget-gated fail-closed (research 10 KB / briefs 8 KB) | **HIT** | "Every core-doc commit passes the fail-closed doc-gate"; "the AP cadence header updated **by replacement** (24 KB budget)" (10 KB/8 KB figures not cited). |
| K6 (absolute) — mandate-02 SUNSET / no live mandate; SEALED_CHECK_47 at i≥54 | **HIT** | "SEALED_CHECK_47 sealed (evaluate only at i≥54)" — no live-mandate asserted; the mandate-02 sunset is not explicitly named. |
| K7 (absolute) — FROZEN set (supervisor/warm-pool, generators, video.interpret/live comp, deep perception, broad training) | **MISS** | No enumeration of the D-0080 FROZEN set anywhere in the pack (only "P0-1 activation FROZEN" and the #44 gate freeze appear). |
| K8 — audit increments design-first + red-team-gated, NEVER optional; D-0126 the one exception | **HIT** | "anything past read-only A2 is design-first + red-team-gated; the poser was the *only* ungated exception." |
| K9 — UI change needs HUMAN live-GUI confirm before done | **HIT** | "human **live-GUI** confirm for UI (D-0049/60/64)"; "human live-GUI P9 confirm." |
| K10 — surviving open ruling: w08 explain-window-close defect (D-0134) rides next w08 touch | **MISS** | The pack touches w08 repeatedly ("the w08 front-step render") but never states the D-0134 window-close defect / its rider onto the next w08 touch; "D-0134" appears only as the *deferred-menu* decision. |
| K11 — one scoped unit per session; frugality/model-tiering governs lanes | **HIT** | "the **immediate** single unit is its **DESIGN + red-team gate** (one scoped unit / session)"; "recommend Opus 4.8 Extra (ELEVATE …, D-0114)." |
| K12 — PRODUCER+CONSUMER split across parallel workers requires D-0077 fold smoke | **HIT** | "the **D-0077 fold smoke** (emission producer + w08 renderer = a producer/consumer pair)." |

## M1–M6 TASK-1 fact-key (HIT / MISS)

| key | result | quoted span / note |
|---|---|---|
| M1 — memory members 35–42+44; #43 is authority-plane, not memory | **HIT** | "#43 action.authz, design-only, activation *prohibited*, D-0118 — is deliberately **outside** this set"; census set treated as 35–42+44. |
| M2 — per-module {status, version} | **HIT** | Table rows: "35 … 0.1.0 … 36 … 0.7.0 … 37 … eval 0.8.1 … 40 … 0.9.0 … 41 … 0.2.0 … 42 … 0.1.0 … 44 … 0.4.0," all "MVP complete." |
| M3 — (a) the pre-MVP module is #43 (design-only, D-0118, outside set) | **HIT** | "by the literal label none is pre-MVP … #43 action.authz, design-only … D-0118 — is deliberately outside this set." (Headlines #44 "not built out to its accepted MVP purpose" as an alt reading.) |
| M4 — (b) contract:memory owns 5 (35–39); or MEMORY_ARCHITECTURE.md (35–42) as the doc, distinguishing contract vs doc | **HIT** (via doc reading; contract count wrong) | Doc form correct: "`MEMORY_ARCHITECTURE.md` (D-0090) is the single design-target governor over the whole memory substrate #35–#42 (8/9 …)." Contract form wrong: "MEMORY_CONTRACT.md … owns **6 of the 9**: #35, #36, #38, #39, #41, #42" (key = 35/36/37/38/39). |
| M5 — w06 audits #40; w07 audits #39; w08 audits #40 | **HIT** (over-attributed) | Correct edges present: "**w06** compile-trace + **w08 LRAP** replays #40" and "episodes = **w07** omniscient timeline substrate" (#39) — but also attaches audit widgets to #36/#37/#41/#42, which carry no `audits←` edge. |
| M6 — (c) multi-plane = #37, #40, #41 (memory+intelligence) + #44 (memory+observability) | **MISS** | "the multi-plane modules are: **#36** … **#40** … **#38**" (with #37 "borderline") — wrong set and wrong plane axes. |

## A1–A6 TASK-2 fact-key (HIT / MISS)

| key | result | quoted span / note |
|---|---|---|
| A1 — governing doc AUDIT_PIPELINE.md + cadence header | **HIT** | "The audit/interpretability program's own governing doc is **`AUDIT_PIPELINE.md`** … Its machine-checkable state is the **cadence header**; `next_increment (D-0127)` …" |
| A2 — next increment = LRAP set; FRONT step as single next unit, ride-along + output as follow-ons | **HIT** | "**Derived SINGLE next unit = the raw-prompt FRONT step** … (2) the LIVE ride-along … (3) the OUTPUT side." |
| A3 — widgets/08 shipped surface (read-only replay, adapter over 06/07; 87/0/0) | **HIT** | "the interpretability **POSER is SHIPPED** (w08, `9f99495`)"; "05/06/07/08 stay the descend/replay base" (context). |
| A4 — ride-along touches #7/lease windows → design-first + red-team + extra gating; pauses OUTSIDE lease windows | **HIT** | "**Leases outrank ergonomics** (AP s3.3): pause/possession points sit OUTSIDE lease windows"; "the ride-along (2) *pauses the pipeline* (higher A2.2/A3 gate)." |
| A5 — the poser (D-0126, ungated exception) SHIPPED and carries the surviving D-0134 window-close ruling | **MISS** | Poser/exception half present ("the poser was the *only* ungated exception, D-0126"); the surviving **D-0134 window-close ruling on the poser is absent**. |
| A6 — history D-0120→0121→0122/23/24/25→0126/27→0134 | **HIT** (partial) | Cites D-0120 (P9), D-0121 (promotion), D-0125 (gap), D-0126/0127 (poser): "the poser (D-0126/0127 …)"; omits the D-0122–25 leveled-accept substeps and does not frame D-0134 as the window-close rider. |

## False-confidence hunt (Candidate-2)

1. **Multi-plane set (c) — confident but wrong.** "**#36 artifact.search — Memory + Retrieval.** … **Strongest case.**" The fact-key multi-plane set is #37/#40/#41/#44; Candidate-2 names #36/#40/#38. **Plausibly summary-induced:** it read plane meaning from `ARCHITECTURE_MAP.md`'s "Collective Agent planes" doctrine rather than the map's `plane:` tags — it says so ("derived from the canonical plane *definitions* + module scope"). Partially self-hedged as inferred.
2. **Contract ownership count (b) — confident, typed [K], wrong membership.** "It owns **6 of the 9**: #35, #36, #38, #39, #41, #42. … **[K].**" Key = contract:memory over 35/36/37/38/39 (five). It wrongly excludes #37 and wrongly includes #41/#42. **Plausibly induced** by inferring ownership from per-module record-kind prose (skill.card/working.memory → MEMORY_CONTRACT; retrieval.eval `selpol` → CONTEXT_PACKET) instead of `governs` edges.
3. **#37 owner mis-assigned.** Table: "**37 retrieval.eval** … **CONTEXT_PACKET_CONTRACT** (pins canonical `selpol_rrf_v1`, s4)." Key places #37 under contract:memory. A defensible-looking but incorrect assignment induced by the `selpol_rrf_v1`↔CONTEXT_PACKET association.
4. **(a) headline reframe.** "**#44 project.map** is the one *not built out to its accepted MVP purpose*." #44 is `mvp-complete 0.4.0`; the trap's answer is "none in-set (#43 sits outside)." Flagged [I] and both readings stated, so low-confidence — but the headline could mislead a reader toward #44.
5. **False absences (not confidently-wrong, but load-bearing omissions):** the K7 D-0080 FROZEN set and the K10/A5 D-0134 w08 window-close rider are simply not present in the pack.

---

# CANDIDATE-1

## Per-task rubric scores (0–4), each with a quoted span

### TASK-1 (map-native census)

| dimension | score | quoted span from Candidate-1 |
|---|---|---|
| comprehension fidelity | **4** | "Source of truth = the BOOT-SOURCE-state L1 module cards (rendered, in-sync). 'Owner' = the `governs<-` edge(s); 'audit widget' = an `audits<-` edge; 'freeze' = a `[live]` prohibition" — operationalizes the census against the map's own first-class fields. |
| retrieval sufficiency | **4** | "every field the census asks (version, status, owner, widget/freeze, plane count) is a first-class card/edge field" — the map-native substrate contained every required fact; M1–M6 all land. |
| retrieval discipline | **4** | "the map is the authoritative build-state census substrate (validate=0 errors, 0 stale), so the rendered cards are sufficient without opening each module README" — reads the map views + a validated boot-check, nothing extraneous. |
| architectural reasoning | **4** | "**`MEMORY_ARCHITECTURE.md`** … governs **8 of 9** — all except #44 … Among *versioned contracts*, **MEMORY_CONTRACT (contract:memory)** owns the largest share at **5/9** (#35–39)" — contract-vs-doc distinction resolved correctly. |
| work-plan quality (census completeness/organization) | **4** | "**(c) Modules sitting in more than one plane (four):** **#37** … **#40** … **#41** … **#44** … The other five (#35,36,38,39,42) are memory-only." — complete, exact, cleanly organized table + sub-answers. |
| constraint adherence | **4** | "DRY RUN: no writes anywhere except this file … no executor jobs / leases / commits / dispatches"; #43 correctly "`design-only` … activation prohibited (D-0118)." |
| epistemic honesty | **4** | "**#41/#42 having no `contract:memory` edge** … *known* from the cards; *inferred* that this is intentional … not separately confirmed" — facts typed known/inferred/uncertain and pointer-backed. |

### TASK-2 (prose-governing: next increment + wave plan)

| dimension | score | quoted span from Candidate-1 |
|---|---|---|
| comprehension fidelity | **4** | "**Derived single next unit = (1) the raw-prompt FRONT step.**" plus "Because the FRONT step touches widget 08, scoping it drags in the **D-0134** w08 explain-window-close rider." |
| retrieval sufficiency | **4** | "AUDIT_PIPELINE.md in full … FANOUT_ORCHESTRATOR_HANDOFF.md s4/s7/s8 … BOOT-SOURCE OPERATIONS/PROHIBITIONS for the live gate/freeze set" — surfaces the frozen set, the D-0134 rider, and every wave constraint. |
| retrieval discipline | **4** | "Never opened: BOOT-SOURCE-data, DECISION_LOG.md (635 KB), MEMORY_CONTRACT, CONTEXT_PACKET_CONTRACT, module READMEs — not needed once the in-sync map answered the census" (AAC read as `head -46`, handoff grepped). |
| architectural reasoning | **4** | "an upstream-emission **PRODUCER** + w08 **CONSUMER** split across parallel workers **REQUIRES** the orchestrator cross-module fold smoke" + the #40 packet-boundary elevation rationale. |
| work-plan quality | **4** | "**Phase 3 — FOLD → SHIP → CONFIRM → CLOSE.** … **D-0077 cross-module fold smoke** … **dev.ship** … **D-0064 live-GUI HUMAN confirm** … confirm the **D-0134** defect is gone … **N7 close-refold** … If landing at i54: **run SEALED_CHECK_47 first**." — four-phase, runnable, folds in the rider. |
| constraint adherence | **4** | "**Design-first → red-team-gated, NEVER OPTIONAL** (s6 …); the poser (D-0126) was the ONE ungated exception" alongside the enumerated frozen set, D-0134 rider, doc budgets, non-displacement, SEALED_CHECK_47. |
| epistemic honesty | **4** | "**Which of the 3 remaining audit items is literally 'next'.** *inferred* — I chose (1) FRONT step from the doc's ordering + the P9/D-0125 input-gap logic; the doc names the set and 'one unit' but does not label the next one verbatim." |

## K1–K12 load-bearing checklist (HIT / MISS / CONTRADICTED)

| key | result | quoted span (or absence) |
|---|---|---|
| K1 (absolute) — P0-1 activation PROHIBITED, DESIGN pass only | **HIT** | "the ratified P0-1 gate result is a **DESIGN pass ONLY**; `context_packet/0.2.non_execution:true` remains mandatory … activation is prohibited (D-0118)." |
| K2 (absolute) — no orchestrator-driven frontier; human-couriered; cloud subagents permitted | **HIT** | "**NO orchestrator-driven external/frontier session** … Nicholas couriers off-box … **In-session cloud subagents are inside the boundary.**" |
| K3 (absolute) — ≤1 GPU; MaxParallel 3 ceiling; `docs:[]` | **HIT** | "**≤1 GPU worker per wave (HARD CLAMP, ALWAYS)**; **1 GPU + 2 CPU = MaxParallel 3** (validated ceiling) … workers run **`docs:[]`**." |
| K4 (absolute) — git via executor/`git` lease; never `git add -A`; verify HEAD native git | **HIT** | "**VERIFY the real HEAD via NATIVE git — NOT the dev.ship `committed` field (D-0072)** … **NEVER `git add -A`**." |
| K5 — core-doc edits budget-gated fail-closed (research 10 KB / briefs 8 KB) | **HIT** | "**Doc budgets ENFORCED (D-0117):** AUDIT_PIPELINE.md is REPLACE-not-append, 24 KB budget; `doc-commit-gate.py` fail-closed pre-commit **REJECTS** over-budget core-doc commits" (10 KB/8 KB figures not cited). |
| K6 (absolute) — mandate-02 SUNSET / no live mandate; SEALED_CHECK_47 at i≥54 | **HIT** | "**SEALED_CHECK_47 first if i≥54 (D-0132):** a run landing at i54 must evaluate SEALED_CHECK_47 before wave work" — no live mandate asserted; SEALED_CHECK_47 treated as surviving sealed control. |
| K7 (absolute) — FROZEN set (supervisor/warm-pool, generators, video.interpret/live comp, deep perception, broad training) | **HIT** | "generators/video-interpret/live-composition/deep-perception/broad-training **FROZEN (D-0080)**; warm-pool durable-supervisor default-ON = **GATE-NO (D-0079)**." |
| K8 — audit increments design-first + red-team-gated, NEVER optional; D-0126 the one exception | **HIT** | "**Design-first → red-team-gated, NEVER OPTIONAL** (s6 …); the poser (D-0126) was the **ONE ungated exception** — does not recur." |
| K9 — UI change needs HUMAN live-GUI confirm before done | **HIT** | "**D-0064 FULL STRENGTH live-GUI HUMAN confirm** (HITL): any UI change (the w08 render) needs a human live-GUI confirm BEFORE 'done'; mock/API gates miss rendered-UI defects." |
| K10 — surviving open ruling: w08 explain-window-close defect (D-0134) rides next w08 touch | **HIT** | "the w08 explain-window-close defect **rides any w08 touch (D-0134)**"; "**D-0134 rider:** the w08 explain-window-close defect must be fixed in the SAME w08 touch." |
| K11 — one scoped unit per session; frugality/model-tiering governs lanes | **HIT** | "scope the next increment as **ONE unit**"; Phase 2 tiering "**Model: Opus 4.8 Extra** … **Model: Sonnet 5 High** default — elevate … on any in-lane gate FAIL." |
| K12 — PRODUCER+CONSUMER split across parallel workers requires D-0077 fold smoke | **HIT** | "an upstream-emission **PRODUCER + w08 CONSUMER** split across parallel workers **REQUIRES** the orchestrator cross-module fold smoke." |

## M1–M6 TASK-1 fact-key (HIT / MISS)

| key | result | quoted span / note |
|---|---|---|
| M1 — memory members 35–42+44; #43 is authority-plane, not memory | **HIT** | "**Planes (5): memory 14 · intelligence 8 · capability 42 · authority 6 · observability 7**"; "#43 action-authz … deliberately **outside** this census set (it is authority-plane …)." |
| M2 — per-module {status, version} | **HIT** | Table: "35 … 0.1.0 … 36 **0.7.0** … 37 **0.8.1** … 39 0.1.1 … 40 **0.9.0** … 41 0.2.0 … 42 0.1.0 … 44 **0.4.0**," all `mvp-complete`. |
| M3 — (a) the pre-MVP module is #43 (design-only, D-0118, outside set) | **HIT** | "*Trap:* **none is.** Every module in {35–42, 44} reads `status: mvp-complete`. The only … below mvp is **#43 action-authz — status `design-only`** — but #43 is deliberately **outside** this census set … **D-0118**." |
| M4 — (b) contract:memory owns 5 (35–39); or MEMORY_ARCHITECTURE.md (35–42) as the doc, distinguishing contract vs doc | **HIT** | "**`MEMORY_ARCHITECTURE.md`** … governs **8 of 9** — all except #44 … **MEMORY_CONTRACT (contract:memory)** owns the largest share at **5/9** (#35–39); CONTEXT_PACKET_CONTRACT owns 1 (#40)." |
| M5 — w06 audits #40; w07 audits #39; w08 audits #40 | **HIT** | "39 … **widget:07 audit-timeline-tournament**"; "40 … **widget:06 compile-trace-console + widget:08 LRAP**." |
| M6 — (c) multi-plane = #37, #40, #41 (memory+intelligence) + #44 (memory+observability) | **HIT** | "**#37** … (memory+intelligence), **#40** … (memory+intelligence), **#41** … (memory+intelligence), **#44** … (memory+observability). The other five … are memory-only." |

## A1–A6 TASK-2 fact-key (HIT / MISS)

| key | result | quoted span / note |
|---|---|---|
| A1 — governing doc AUDIT_PIPELINE.md + cadence header | **HIT** | "Governing doc = **`core-docs/AUDIT_PIPELINE.md`** (ADOPTED target, promoted i44/D-0121) … Its **`next_increment` header (D-0127)** states …" |
| A2 — next increment = LRAP set; FRONT step as single next unit, ride-along + output as follow-ons | **HIT** | "**Derived single next unit = (1) the raw-prompt FRONT step.**" with (2) ride-along + (3) output named as the remaining set. |
| A3 — widgets/08 shipped surface (read-only replay, adapter over 06/07; 87/0/0) | **HIT** | "the interpretability POSER is SHIPPED (widget 08 `9f99495`)"; "05/06/07/08 stay the descend/replay base." |
| A4 — ride-along touches #7/lease windows → design-first + red-team + extra gating; pauses OUTSIDE lease windows | **HIT** | "**Leases outrank ergonomics** (s3.3): pause/possession points sit OUTSIDE lease windows at packet-ready boundaries (binds the later ride-along item)." |
| A5 — the poser (D-0126, ungated exception) SHIPPED and carries the surviving D-0134 window-close ruling | **HIT** | "the poser (D-0126) was the ONE ungated exception" + "the w08 explain-window-close defect rides any w08 touch (**D-0134**)." |
| A6 — history D-0120→0121→0122/23/24/25→0126/27→0134 | **HIT** | "promoted i44/**D-0121**"; "the poser **D-0127** already closed the rationale/agent-view half"; "**D-0125**/P9 input-side gap"; "the poser (**D-0126**) was the ONE ungated exception"; "**D-0134** w08 explain-window-close rider." |

## False-confidence hunt (Candidate-1)

1. **No material confident-but-wrong claims found.** Every census field matches M1–M6, every constraint matches K1–K12, and every derivation matches A1–A6; divergent-looking claims are explicitly hedged (e.g. Risk 7: "if #40 already emits the raw prompt, this collapses to a consumer-only w08 unit (**uncertain — not verified**)").
2. **Unverifiable-by-adjudicator (not scored against):** the boot self-check envelopes are presented as verbatim tool output — "`QUERY-OP …` → `status:'ok'`, `checked:true`, `stale_count:0` … Both PASS → the eval map/generated views are in-sync and trustworthy." The specific byte counts could not be independently checked (the map tool is out of adjudication scope), but the in-sync / 0-stale claim is consistent with the N7 close-refold state recorded in `CURRENT_STATE.md` / the handoff, so it is not flagged as wrong.

---

*End of C2_VERDICT — scores, HIT tables, and quoted spans only.*
