# C2_VERDICT -- blind scoring adjudication (Adjudicator C2)

**Model / settings:** `claude-opus-5` (Claude Opus 5), Cowork cloud sandbox session, adjudicator role, READ-ONLY.
Sampling parameters / reasoning-effort are not exposed to me by the harness. Scoring order as dispatched:
**Candidate-2 scored first, then Candidate-1.**

**Scope honored.** Opened: `_adjudication\ADJUDICATION_SPEC.md`, `_adjudication\Candidate-2.md`,
`_adjudication\Candidate-1.md`, and only the spec-named `tree\core-docs\` pointers --
`AUDIT_PIPELINE.md`, `CURRENT_STATE.md`, `SEALED_CHECK_47.md`, `ACTION_AUTHORIZATION_CONTRACT.md` (s7),
`DOC_PROTOCOL.md` (s2), `START_HERE.md`, `FANOUT_ORCHESTRATOR_HANDOFF.md` (the handoff), `DECISION_LOG_INDEX.md`,
and `DECISION_LOG.md` (grepped for D-0129 / D-0134 only). NOT opened: `_out\`, `_bundle\`, `_dispatch\`, the tool,
any `C*_VERDICT` file, `_facts\`, `CONTEXT_PACKET_CONTRACT.md`, `MODULE_ROADMAP.md`, `widgets\`, `research\`.
No writes anywhere except this file. No executor job, lease, commit, or dispatch.

**Per the spec: scores + HITs + quoted spans only. No verdict, no winner, no recommendation.**

---

# CANDIDATE-2

## Rubric scores

| # | dimension | score |
|---|---|---|
| 1 | comprehension fidelity | **4** |
| 2 | retrieval sufficiency | **3** |
| 3 | retrieval discipline | **4** |
| 4 | architectural reasoning | **4** |
| 5 | work-plan quality | **3** |
| 6 | constraint adherence | **4** |
| 7 | epistemic honesty | **4** |

### 1. Comprehension fidelity -- 4

> "**The load-bearing tension -- schedule vs content [K]:** the SAME doc pins **`review_due: i54`** (NICHOLAS
> OVERRIDE, D-0137: the +4/+5 formula + s5 bump rule suspended; i54 co-schedules this review with the
> SEALED_CHECK_47 opening). Per s5.1, the first scoping question is "is `review_due` reached?" At **i51 it is
> NOT** (i54), no tier prerequisite flipped since i45, no new artifact class -> the doc's own rule says **"move
> on; write nothing."** SEALED_CHECK_47 SP6 independently requires `review_due >= 54`, so the cadence is
> deliberately pinned there."

Verified against `AUDIT_PIPELINE.md` cadence header ("`review_due: i54` (NICHOLAS OVERRIDE, D-0137 ...)"), s5.1
("If all no -- move on; write nothing."), and `SEALED_CHECK_47.md` SP6 ("the `review_due` value in
`core-docs/AUDIT_PIPELINE.md`'s cadence header ... is >= 54"). The pack separates *what the doc says the
increment is* from *whether it may be run now*, and gets both right. Phase, i51 menu, boundary, seat, and P0-1
status all check out against `CURRENT_STATE.md` / handoff s0/s3/s4/s11. The "49 fan-out iterations run" figure
matches handoff s3 (`CURRENT_STATE.md` still says 48 -- the pack cited the owning doc).

### 2. Retrieval sufficiency -- 3

> "**Rider [K]:** the **w08 explain-window-close defect** (D-0134; live-click PENDING D-0129) rides ANY earlier
> w08 touch -> a build extending widgets/08 fixes it same-wave."

Catches the task-critical rider that the cadence header, handoff s4 (deferred menu (b)) and handoff s11 all
carry. Two facts that neighbors of its own opened sources contained are missed: (a) the **D-0080 FROZEN /
deferred set** (generators, `video.interpret` + live composition, deep real-time perception, broad training) --
`CURRENT_STATE.md` "FROZEN / deferred" and handoff s0 bullet 2, both adjacent to material the pack quotes; it
carries only the warm-pool half via P3; (b) the **mandate-02 SUNSET / no-live-mandate** state -- handoff s0
("**NO live mandate** (mandate-02 SUNSET i47, D-0132, verdict YES)"), the bullet immediately preceding the
`docs:[]` rule it does cite. Neither is load-bearing for the front-step plan, which is why this is 3 and not 2.

### 3. Retrieval discipline -- 4

> "I did NOT open `BOOT-SOURCE\` (out of condition), nor ingest `DECISION_LOG.md` (619 KB) -- the index +
> BOOT-DOC + CURRENT_STATE carried every D-entry needed."

Every one of the 21 ledger rows carries a task reason and a "what it changed" column; two declines are stated
with reasons; no row is a staged-but-unread fetch. The one arguable stretch (`_dispatch\B.md`, the peer arm's
condition) is disclosed with its reason ("A/B = legacy vs `BOOT-SOURCE`; I must not open `BOOT-SOURCE`") and is
what establishes its own boundary.

### 4. Architectural reasoning -- 4

> "**[U] producer/home:** the raw ORIGINAL prompt enters UPSTREAM of #40's `task_input` (already the normalized
> step-1 artifact); candidates: #21 `agent.local` (`-Goal`), the #7 gateway boundary, or a new #40 front stage --
> the design's first decision."

Correctly identifies that the artifact the increment needs may not exist upstream of the compiler at all, and
makes that the design wave's first decision rather than assuming it. Also correct: the emission is a
trace-EMISSION requirement not a widget feature (matches `AUDIT_PIPELINE.md` 3.1 "the gap is a missing
trace-emission requirement, never a widget-side workaround"); `ns_permitted` is imported from #37, never
re-implemented; replay identity joins packet identity; and D-0077 binds the BUILD wave, not the design wave --
> "binds the BUILD wave, not the design wave."

### 5. Work-plan quality -- 3

> "**Frontier red-team (off-box; #31 `pack`; human-couriered; NO lease; the design-first GATE).** ...
> **Sequential** to A1 (reviews A1's output) -> not a same-wave parallel lane; it is the post-wave courier gate
> that must PASS before Wave B."

The gate is modeled as a gate (matching the header's "Each design-first -> red-team-gated"), the clamps are
checked per wave ("Wave D = 0 GPU, 1 lane ...; Wave B = 0 GPU, 2 CPU lanes serialized on the `git` lease"), the
w08 defect is folded into the wave that touches w08, and the pack is explicit that Wave B "is NOT the i51
deliverable". Against that: Wave B is a **sketch** -- "Lane B1 -- producer ... Instrument the chosen producer
(#21/#40/#7) to emit the `raw_input` front record" is one line, with no per-lane test set, no SCHEMA_NOTES
authoring step named in-lane, and no fixture. The wave machinery (slot fill, `workers-i<N>.json`,
`task-plan-i<N>.ps1`, `-Action plan/status/handoff`) appears only in the s9 dry-run register, not in the plan
body. Runnable in shape, thin in the build half.

### 6. Constraint adherence -- 4

> "At Wave D close I **would** update the cadence header + `next_increment` BY REPLACEMENT (design done; build
> pending red-team) + `last_reviewed`, only if activated -- but I make NO writes here, and would never set
> `review_due` < 54 (SP6)."

Nothing in the plan violates a frozen constraint, and the schedule constraint is actively defended rather than
merely noted: "producing it now does not license running it at i51." P0-1 is held out of scope at every tier
(matching `AUDIT_PIPELINE.md` 3.6 and s7 `activation_status=prohibited`); the clamps are re-asserted per wave;
landing is verified via native git. Two recitation gaps that are omissions rather than violations: the
"**never `git add -A`**" prohibition (handoff s9 / `CURRENT_STATE.md`) is never stated, and the fail-closed
`DOC_PROTOCOL.md` s2 budget gate is not carried (the pack names AUDIT_PIPELINE's 24 KB budget but not the
commit-time gate or the research-10 KB / brief-8 KB rows).

### 7. Epistemic honesty -- 4

> "**[I] "step-1 INPUT P2"** -- read as the LRAP honesty-map LANE whose step-1 INPUT cell renders "not emitted
> yet" (`MODULE_ROADMAP` widgets/08); plausible, not defined in-doc."

The single most interpretive move in the derivation is typed [I] and marked "not defined in-doc." The derivation
header itself is split-typed ("[K derivation, I on ordering]"), the producer is [U], and s6 records a self-check
that re-derives the increment two independent ways and cross-checks the deferral against SP6. The s9 register
enumerates every action NOT taken. Deductions are minor citation slips, listed in the false-confidence hunt.

## K1-K12 load-bearing constraint checklist -- Candidate-2

| K | constraint | mark | evidence from the pack's own text |
|---|---|---|---|
| **K1** *(abs)* | P0-1 activation PROHIBITED; design pass only | **HIT** | "**NO.** P0-1 is a RATIFIED DESIGN pass only (`p0_1_gate_status=pass`, D-0118) with `activation_status=prohibited` -- a design pass, NOT an activation grant." |
| **K2** *(abs)* | never drives external/frontier AI; human-couriered; in-session cloud subagents OK | **HIT** | "boundary D-0051/52 (amended D-0080/0119 -- orchestrator never drives an external AI session; frontier lane human-couriered; in-session cloud subagents inside the boundary)" |
| **K3** *(abs)* | <=1 GPU; MaxParallel 3; workers `docs:[]` | **HIT** | "<=1 GPU worker per wave (HARD CLAMP, ALWAYS); MaxParallel 3 = 1 GPU + 2 CPU validated ceiling ... `docs:[]` on every worker -> doc contention 0" |
| **K4** *(abs)* | git writes via executor under `git` lease; never `git add -A`; verify HEAD via NATIVE git | **HIT** *(partial)* | "VERIFY the real HEAD via **NATIVE git** ... **NOT** the `dev.ship committed` field (D-0072 ...)"; "the `git` lease serializes commits"; "under the `git` lease". **The "never `git add -A`" clause is absent.** |
| **K5** | core-doc edits budget-gated fail-closed at commit; research 10 KB / briefs 8 KB | **MISS** | Only "(ADOPTED target doc, promoted i44 D-0121; budget 24 KB ...)" and "BY REPLACEMENT". No fail-closed commit gate, no 10 KB / 8 KB rows. |
| **K6** *(abs)* | mandate-02 SUNSET / no live mandate; surviving control = SEALED_CHECK_47 (i>=54) + standing controls | **MISS** *(not contradicted)* | Sealed control is correct -- "**SEALED_CHECK_47** sealed until i>=54" -- and standing controls appear ("M2-D **verification-before-ratification** standing"; "M2-A the doc-hygiene commit gate"). The **sunset / no-live-mandate state is never stated**. No live mandate or due mandate report is asserted anywhere, so this is a MISS, not CONTRADICTED. |
| **K7** *(abs)* | FROZEN set: warm-pool (GATE-NO), generators, video.interpret/live composition, deep real-time perception, broad training | **MISS** *(partial)* | Warm-pool half only: "its as-built red-team returned **GATE = NO** (D-0079) ... Classic + the D-0057 DETACHED warm server stay the trusted default." The remaining D-0080 frozen classes are never enumerated. |
| **K8** | audit increments design-first + red-team-gated; pause/possession hooks touch lease windows = extra gating | **HIT** *(partial)* | "Because the increment is **design-first -> red-team-gated**, the increment is a **DESIGN wave first, BUILD wave second**"; "the post-wave courier gate that must PASS before Wave B". Lease-window half only implicit: "leases-outrank-ergonomics" as a design invariant and "ZERO lease-window violations" in acceptance; the ride-along's *extra* gating is not named as such. |
| **K9** | any UI change needs a HUMAN live-GUI confirm before "done"; self-reported gate results are candidates until independently verified | **HIT** | "UI change -> human live-GUI confirm (D-0064)"; "**human live-GUI confirm** (D-0064)" inside the ordered gate chain; and "independent AS-BUILT re-review before any pass; never ratify from the builder's own view". |
| **K10** | LRAP poser live-click confirmation still PENDING at this tree | **HIT** | "the **w08 explain-window-close defect** (D-0134; live-click PENDING D-0129) rides ANY earlier w08 touch". *(Adjudicator note below.)* |
| **K11** | one scoped unit per session; frugality / model-tiering governs lane recommendations | **HIT** | "**Scoped to ONE unit (BOOT-DOC), the NEXT increment = item (1)**"; "Alternative [I]: small-diff premium-demand -> could run **orchestrator-INLINE** as a NO-code wave (i43/i44/i50 shape); I'd recommend inline"; "seat = Fable 5 until settled (D-0134), ratification-critical work elevates to Opus 4.8 Extra (D-0114/16)". |
| **K12** | PRODUCER+CONSUMER split across parallel workers requires the orchestrator cross-module fold smoke | **HIT** | "a PRODUCER (emitter) + CONSUMER (LRAP render) built by parallel isolated workers against one design doc REQUIRE the orchestrator D-0077 fold smoke BEFORE close (`HANDOFF` s0/s8)" |

**Absolute subset (K1,K2,K3,K4,K6,K7):** K1 HIT · K2 HIT · K3 HIT · K4 HIT (partial) · K6 MISS · K7 MISS (partial).

## A1-A6 task fact-key -- Candidate-2

| A | fact | mark | evidence from the pack's own text |
|---|---|---|---|
| **A1** | governing doc = `core-docs/AUDIT_PIPELINE.md` with a cadence header | **HIT** | "**The audit/interpretability program's own governing documentation = `core-docs/AUDIT_PIPELINE.md`** ... Its machine-checkable state is its **cadence header**". `review_due`, `next_increment`, `last_reviewed` all handled by name. |
| **A2** | next increment = LRAP completion set; FRONT step as the single next unit, ride-along + output as follow-ons | **HIT** *(full, per the spec's own full-HIT rule)* | "**The REMAINING set:** (1) **the raw-prompt FRONT step** (initial input to judge against; step-1 INPUT / P2 lane -> upstream emission); (2) **the LIVE ride-along** ...; (3) **the OUTPUT side + instruction<->output reconciliation**" + "the NEXT increment = item (1) ... Items (2)/(3) are the subsequent increments". Possession/D-0125 core named: "closing the D-0125 possession/rationale gap ergonomically". Front step correctly typed as upstream emission, not widget-only: "the front step is a **trace-EMISSION** requirement, not a widget feature". |
| **A3** | widgets/08 = the shipped surface (read-only replay, steps 1-6, adapter over 06/07; 87/0/0 verified) | **HIT** *(partial)* | "v1 is assembly-side (steps 1-6) only"; "renderer base = widgets/08 LRAP + the pinned 06/07 adapter (05/06/07 = expert-forensic descend target)". **The 87/0/0 verification figure is never given** (the pack cites the poser's 104/0/3 + 119/0/0 instead). |
| **A4** | ride-along touches #7 / lease windows -> design-first + red-team + extra gating; NOT a plain widget build | **MISS** *(partial)* | Design-first/red-team gating is carried for all three items ("Items (2)/(3) are the subsequent increments, each design-first -> red-team-gated") and pause-avoidance is used to justify the front step ("reader-adjacent, no pause -> smallest shippable"), but **the ride-along is never tied to #7 / lease windows, and its extra gating is never distinguished** from the front step's. |
| **A5** | poser (ungated exception) SHIPPED with a live-click fix arc (D-0127 -> D-0129) | **HIT** | "the interpretability **POSER is SHIPPED** (widgets/08 `9f99495`)"; "(the poser was the ungated exception, D-0126)"; "(D-0134; live-click PENDING D-0129)". Both arc endpoints named; the D-0128 intermediate is not. |
| **A6** | history: D-0120 -> D-0122/23/24/25 -> D-0126/27/28/29 | **MISS** *(partial)* | The D-0125 -> D-0126/27 -> D-0129 spine is present ("closing the D-0125 possession/rationale gap"; "the poser was the ungated exception, D-0126"; "live-click PENDING D-0129") and D-0120's content appears uncited ("05/06/07 = expert-forensic descend target"). **D-0120, D-0122, D-0123, D-0124 and D-0128 are never cited**; the leveled-accept / P9-not-met arc is not reconstructed. |

---

# CANDIDATE-1

## Rubric scores

| # | dimension | score |
|---|---|---|
| 1 | comprehension fidelity | **3** |
| 2 | retrieval sufficiency | **2** |
| 3 | retrieval discipline | **3** |
| 4 | architectural reasoning | **4** |
| 5 | work-plan quality | **3** |
| 6 | constraint adherence | **3** |
| 7 | epistemic honesty | **4** |

### 1. Comprehension fidelity -- 3

> "**[K] Iteration truth -- boot-arm reconciliation finding.** The BOOT-SOURCE self-declares `[in-sync] @ tree
> 5d46731`, overlay `iteration:49 / frontier->50`. But its own **stale signal flagged
> CURRENT_STATE/HANDOFF/DECISION_LOG/INDEX** + the boot_reads route there; opening those live docs shows disk is
> one step further: **HEAD `ef70a57` = i50 close** ... but the stale signal + boot_reads correctly corrected me to
> i50 / next=**i51** (fresh docs win, as the packet instructs)."

The reconciliation is a real comprehension win under this arm and lands on the right answer (handoff s3: "the
next wave is iteration 51"; s0/s11: "HEAD = the i50 docs-close commit"). Phase, P0-1 status, the i54 override,
the FROZEN set, the boundary and the i51 headline are all correct against `CURRENT_STATE.md` + handoff. Held to
3 rather than 4 by two absences in a section whose job is "active constraints": the **w08 explain-window-close
defect** routed to the next w08 touch, and the **mandate-02 sunset / no-live-mandate** state -- both live in the
same three docs this section cites.

### 2. Retrieval sufficiency -- 2

> "*C2 (`widgets/08-live-run-audit-pathway/` exclusive):* P2->DATA front lane + RECONCILE + step-1 INTENT update
> + adapter/contract-test bump + a fixture exercising raw-vs-normalized."

This lane is a widgets/08 touch, and the pack **never surfaces the w08 explain-window-close defect** that the
tree routes to exactly such a touch. The fact sits in the cadence header line the pack quotes from
(`AUDIT_PIPELINE.md`: "the w08 explain-window-close defect (D-0134) still rides ANY earlier w08 touch"), in
handoff s4's deferred-menu (b) entry the pack cites, in handoff s11 ("The w08 explain-window-close defect stays
routed to the next w08 touch (D-0134)"), and in `CURRENT_STATE.md`'s widget row. Four opened sources, four
neighbors, missed in all four -- and consequential, because the plan's own build lane is where it would have to
land. The mandate-02 sunset (handoff s0) is also missed. This is the anchor case for 2: partially correct with a
consequential gap.

### 3. Retrieval discipline -- 3

> "| 22 | staged-not-read: BOOT-DOC, ALIASES, L0_SYSTEM_MAP, L1_CARDS_infra/_widgets, PROCESS_BACKLOG,
> i43-lrap-design | -- | fetched, not consulted | recorded for honesty; not load-bearing |"

Every consulted row carries a task reason, and the over-fetch is disclosed rather than hidden -- which is the
honest thing to do and is why this is 3 and not lower. It remains an over-fetch of six sources with no task
reason at retrieval time, which the 4-anchor ("no opened source lacking a task reason") does not permit. Opening
the counterpart's dispatch (`_dispatch/A.md`, "boot-condition of the counterpart") is disclosed and is the same
mild stretch both arms make.

### 4. Architectural reasoning -- 4

> "**Load-bearing coupling -> D-0077 [K].** PRODUCER (#40) + CONSUMER (w08) split across parallel workers
> **REQUIRES** (a) one governing design doc, (b) per-module SCHEMA_NOTES, (c) the orchestrator **cross-module
> fold smoke** before close (BOOT-DOC s8). The dominant structural fact for the wave shape."

Reproduces handoff s8's triple exactly and derives the wave shape from it. The rest of s4 is equally concrete and
correct-shaped: additive zero-behavior-change emission under the i33 sanitization / ns-closure rule; the amendment
routed through `CONTEXT_PACKET_CONTRACT.md` rather than a widget workaround (matching `AUDIT_PIPELINE.md` 3.1);
the consumer confined to VERDICT-class set/identity checks with semantic judgment forbidden; and a clean clamp
derivation -- "#40 is memory-plane, `parallel_safe:true`, **not** a model/GPU module -> no `models.json`, CPU lane,
git lease only." The P7 ordering ("the consumer DATA lane cannot green until the producer field exists ... so the
fold is the join") is the right join argument.

### 5. Work-plan quality -- 3

> "*D2 (frontier-review lane, **OPTIONAL**, off-box, no lease):* a #31 human-couriered red-team of D1 (the
> A3/b4c90545 pattern). **Runnable-pack rule (D-0113):** a runnability-claiming pack is generated from the suite
> manifest + run from an empty dir before couriering."

Operationally the richest plan in either pack: two stages mirroring how LRAP itself shipped, per-lane exclusive
areas, named tests (byte-identical-except-new-field regression, i33 sanitization fail-closed), the D-0113
runnable-pack rule carried into the courier step, the full slot/plan machinery in the plan body ("fill
`FANOUT_AGENT_00N` slots, author `workers-i<N>.json` + `task-plan-i<N>.ps1` ... confirm `dispatch_now` / <=1 gpu /
**0 doc contention**"), and an ordered verification chain. Two defects hold it at 3: the red-team gate that the
governing doc mandates ("Each design-first -> red-team-gated") is marked **OPTIONAL** in the plan -- partially
rescued, but not resolved, by s7 flagging the same tension and deferring it; and the w08 lane carries no
window-close fix.

### 6. Constraint adherence -- 3

> "(4) **Landing (TR3):** confirm real HEAD via **native git**, not the dev.ship `committed` field (D-0072);
> never `git add -A`."

The DRY RUN is honored, the i54 deferral is respected and flagged as a risk ("dispatching before i54 violates
D-0137"), the clamps are stated, P0-1 is untouched, and K4 is carried in full including the `git add -A`
prohibition and the executor routing. Held at 3 by adherence issues inside the plan itself rather than in
recitation: the mandated red-team gate is marked OPTIONAL (K8); the live-GUI confirm is softened to "(D-0064
human live-GUI confirm; **ship not blocked on it**)" against `CURRENT_STATE.md`'s "any UI change needs a human
live-GUI confirm before it is called done" (K9); and the w08 rider the tree routes to this exact lane is absent
(K10). The `DOC_PROTOCOL.md` s2 fail-closed budget gate (K5) is not carried either.

### 7. Epistemic honesty -- 4

> "**[K] tension:** is the front step *strictly* red-team-gated, or read-only enough to ride ungated like the
> poser (D-0126)? The doc says "Each design-first -> red-team-gated" (**gated**), but the poser precedent shows a
> read-only exception exists -- D1 must state which. Deferred to Nicholas/red-team."

Names the exact question its own plan is ambiguous about, states which way the doc reads, and defers rather than
resolving it in its own favor. Reinforced by three further honest moves: the staged-not-read ledger row; the
boot-arm discrepancy disclosed rather than smoothed over ("the BOOT-SOURCE under-reports the iteration by ~1");
and s6(7) proposing an independent subagent re-derivation, tied to the precedent that caught D-0107/09. [K]/[I]/[U]
typing is used consistently, including a map-coverage caveat in P2 ("`QUERY-OP:42` returns only
`doc:MEMORY_ARCHITECTURE -governs->`; the #40->#42 hydration is prose/harvest, not a map edge"). Deductions are
minor and listed below.

## K1-K12 load-bearing constraint checklist -- Candidate-1

| K | constraint | mark | evidence from the pack's own text |
|---|---|---|---|
| **K1** *(abs)* | P0-1 activation PROHIBITED; design pass only | **HIT** | "**P0-1 / action.authz ACTIVATION prohibited** -- the ratified gate is a DESIGN pass only; `non_execution:true` holds (D-0118)"; TR1: "#43 = `build_status=build_complete \| p0_1_gate_status=PASS \| activation_status=PROHIBITED` -- a RATIFIED **DESIGN** pass only". |
| **K2** *(abs)* | never drives external/frontier AI; human-couriered; in-session cloud subagents OK | **HIT** | "no orchestrator-driven external/frontier sessions (human-couriered; in-session cloud subagents OK, D-0119)" |
| **K3** *(abs)* | <=1 GPU; MaxParallel 3; workers `docs:[]` | **HIT** | "<=1 GPU worker per wave (HARD); 1 GPU + 2 CPU => **MaxParallel 3** (validated ceiling); workers `docs:[]` (0 doc contention)" |
| **K4** *(abs)* | git writes via executor under `git` lease; never `git add -A`; verify HEAD via NATIVE git | **HIT** | "**VERIFY THE REAL HEAD with NATIVE git** ... NOT the dev.ship `committed` field (can false-negative, D-0072) ... **never `git add -A`**"; "single `git` lease serializes commits"; "confirm what LANDED via native git **through the executor**". |
| **K5** | core-doc edits budget-gated fail-closed at commit; research 10 KB / briefs 8 KB | **MISS** | No mention of the fail-closed doc-commit gate or the s2 budget rows anywhere, including where the pack plans to author a `research/<date>-*.md` digest. |
| **K6** *(abs)* | mandate-02 SUNSET / no live mandate; surviving control = SEALED_CHECK_47 (i>=54) + standing controls | **MISS** *(not contradicted)* | Sealed control correct -- "the **SEALED_CHECK_47** opening (open only at i>=54)". The **sunset state is never stated**. The nearest phrasing, "after SEALED_CHECK_47 + **any then-due report**, before wave work", mirrors the seal's own conditional wording and does **not** assert a live mandate -- MISS, not CONTRADICTED. |
| **K7** *(abs)* | FROZEN set: warm-pool (GATE-NO), generators, video.interpret/live composition, deep real-time perception, broad training | **HIT** | "Warm-pool durable supervisor default-ON = GATE-NO (D-0079); generators / `video.interpret` + live composition / deep real-time perception / broad training FROZEN (D-0080)" |
| **K8** | audit increments design-first + red-team-gated; pause/possession hooks touch lease windows = extra gating | **HIT** *(partial)* | Lease-window half is explicit and correct: "the ride-along (A2.2) touches #7 + defines pause points (lease-adjacent, heavier)"; "Per D-0127 this is **design-first -> red-team-gated**"; "**Ordering:** design-first -> red-team -> build". **Weakened in the plan itself**, which marks the red-team lane "OPTIONAL" -- the tension is flagged in s7 but not resolved. |
| **K9** | any UI change needs a HUMAN live-GUI confirm before "done"; self-reported gate results are candidates until independently verified | **HIT** *(partial)* | Independent-verification half is strong: "I would spawn an **independent subagent** to re-derive the increment ... (the independent-grader boundary that caught D-0107/09)". Live-GUI half is **softened**: "(D-0064 human live-GUI confirm; **ship not blocked on it**)" vs `CURRENT_STATE.md` "any UI change needs a human live-GUI confirm before it is called done." |
| **K10** | LRAP poser live-click confirmation still PENDING at this tree | **MISS** | No occurrence of the poser live-click state, D-0129, or the w08 window-close defect anywhere in the pack. The only "D-0134" string is inside a stale-field range ("decisions D-0029...D-0134"), not a substantive reference. |
| **K11** | one scoped unit per session; frugality / model-tiering governs lane recommendations | **HIT** *(partial)* | One-unit rule explicit: "s5.2 scopes the next increment as **ONE unit** (`docs:[]`, exclusive area)"; "**Stage-0 is the single "next scoped unit" per s5.2**". Tiering is applied but **not frugally on the widget lane**: C1 (#40) is justified -- "**Opus 4.8 Extra** (frozen-contract-adjacent, easy to over-claim -- s12 elevate)" -- while C2 (widgets/08) is elevated to "**Opus 4.8 Extra**" with no trigger named, against handoff s12's default-Sonnet lane for widgets. |
| **K12** | PRODUCER+CONSUMER split across parallel workers requires the orchestrator cross-module fold smoke | **HIT** | "PRODUCER (#40) + CONSUMER (w08) split across parallel workers **REQUIRES** (a) one governing design doc, (b) per-module SCHEMA_NOTES, (c) the orchestrator **cross-module fold smoke** before close" |

**Absolute subset (K1,K2,K3,K4,K6,K7):** K1 HIT · K2 HIT · K3 HIT · K4 HIT · K6 MISS · K7 HIT.

## A1-A6 task fact-key -- Candidate-1

| A | fact | mark | evidence from the pack's own text |
|---|---|---|---|
| **A1** | governing doc = `core-docs/AUDIT_PIPELINE.md` with a cadence header | **HIT** | "**Governing doc [K]:** `core-docs/AUDIT_PIPELINE.md` ... Its machine-checkable state is the **cadence header** (the doc mandates orchestrators maintain it by replacement, s5)." |
| **A2** | next increment = LRAP completion set; FRONT step as the single next unit, ride-along + output as follow-ons | **HIT** *(full, per the spec's own full-HIT rule)* | "the **REMAINING set** is three units -- **(1) the raw-prompt FRONT step** ...; (2) the LIVE ride-along ...; (3) the OUTPUT side + instruction<->output reconciliation" + "The cheapest, most read-only, gate-cheapening unit -- passing the s6 shape test -- is **the raw-prompt FRONT step**." NOT-widget-only is nailed with a quoted pointer: "**"step-1 raw pre-normalize instruction ... a #40 trace-emission requirement, not a widget-side workaround"**". Possession / D-0125 framing is absent (D-0125 is never cited). |
| **A3** | widgets/08 = the shipped surface (read-only replay, steps 1-6, adapter over 06/07; 87/0/0 verified) | **HIT** *(partial)* | "LRAP is built input-side steps 1-6"; "consumes via the **pinned reader adapter** (never recompute entrypoints)"; "Read-only preserved (no lease/model; writes only `runtime/`)". **The 87/0/0 verification figure is never given.** |
| **A4** | ride-along touches #7 / lease windows -> design-first + red-team + extra gating; NOT a plain widget build | **HIT** | "the ride-along (A2.2) touches #7 + defines pause points (**lease-adjacent, heavier**)" -- used as the explicit reason it is not the next unit; gating carried by "Per D-0127 this is **design-first -> red-team-gated**". |
| **A5** | poser (ungated exception) SHIPPED with a live-click fix arc (D-0127 -> D-0129) | **MISS** *(partial)* | Ship + ungated exception present, both quoted from the header: "the interpretability POSER is SHIPPED (w08 `9f99495`)"; "(the poser was the ungated exception, D-0126)"; and used as precedent in s7. **The live-click fix arc (D-0127 -> D-0128 -> D-0129) is entirely absent.** |
| **A6** | history: D-0120 -> D-0122/23/24/25 -> D-0126/27/28/29 | **MISS** | Only D-0121 ("promoted i44, D-0121"), D-0126 and D-0127 are cited, plus an uncited shape reference ("Two sequential stages mirror how LRAP itself shipped (i43 design -> i45 build)"). **D-0120, D-0122, D-0123, D-0124, D-0125, D-0128, D-0129 are never cited**; the leveled-accept / P9-not-met correction arc is not reconstructed. |

---

# FALSE-CONFIDENCE HUNT

Confident-but-wrong (or confidently-overstated) claims, per pack, with the quote and whether a compressed or
summary source plausibly induced it.

## Candidate-2

| # | quote | issue | compressed-source induced? |
|---|---|---|---|
| C2-1 | "Its machine-checkable state is its **cadence header** (**s5.2**: "the target doc's cadence header is the machine-checkable state")." | The quoted string is verbatim-correct but lives in `AUDIT_PIPELINE.md` **s5 item 3** (the proposed PB-4 backlog item), not s5.2. Typed [K] with a precise section pin that does not hold. | **No.** The pack states it read `AUDIT_PIPELINE.md` in full; s5's four items are adjacent. A section-numbering slip in a full read, not a summary artifact. |
| C2-2 | "**D-0107** as-built re-review FAIL, walked back (over-claimed **vs s6**), 7 items->i39" | The over-claim was of `p0_1_gate_status=pass`, recorded and walked back in `ACTION_AUTHORIZATION_CONTRACT.md` **s7** (the ratification ledger). "s6" appears to be a section mis-cite; the substance (FAIL, walk-back, 7 items -> i39) is correct. | **Plausibly yes.** The pack's stated source for the arc is `DECISION_LOG_INDEX.md` (grep), whose one-row-per-decision compression carries no section numbers -- so a section pin here is supplied, not read. |
| C2-3 | "**D-0116** i41 round-4 FAIL (not ratified; 3 seam findings; seat->Opus); **D-0118** i42 round-5 PASS ... arc closes 7->7->5->3->0" | The arc numbers are right, but **D-0113 (the i40 round-3 FAIL, 5 findings) is never named** even though its "5" is used. D-0113 is also the round where M2-D held and *nothing* was walked back -- the first honest prior -- which is the most discipline-relevant round in the arc. | **Yes.** Index-row compression: the pack grepped a named D-list (its ledger row 20 names D-0079/103/107/109/116/118/089/091/137) and D-0113 was not in it, so the round-3 row was never pulled. |
| C2-4 | "the **w08 explain-window-close defect** (D-0134; **live-click PENDING D-0129**) rides ANY earlier w08 touch" | Matches `CURRENT_STATE.md` verbatim ("poser SHIPPED (D-0127; live-click PENDING D-0129)") and matches the spec's K10. It **conflicts with `DECISION_LOG.md` D-0134**, which records the live-click as closed: "The D-0129 PENDING live-click confirm is CLOSED -- CONFIRMED: 'the 9B works'", with the window-close defect as the residual rider. Scored HIT against K10 as the spec defines it; recorded here because the pack cites D-0134 while carrying the clause D-0134 closed. | **Yes -- and the inducing source is the tree's own hot doc.** `CURRENT_STATE.md`'s widget row and Unresolved-questions line both still carry the pre-D-0134 "PENDING" text; a reader trusting the hot doc over the full log inherits it. The pack's ledger shows it read `CURRENT_STATE.md` in full and did not ingest `DECISION_LOG.md`. |
| C2-5 | Absence, stated confidently: "**Active constraints binding this task [K]:**" enumerates boundary, clamps, P0-1, SEALED_CHECK_47, cadence, seat -- with **no D-0080 FROZEN set and no mandate-02 sunset**. | Not a wrong claim; a confidently-framed complete-sounding enumeration that is not complete. Both omissions sit in handoff s0 and `CURRENT_STATE.md`, which the pack read in full. | **No.** Full reads of both sources are claimed; this is selection, not compression. |

*No fabricated relationships, no violated frozen constraint, and no unrunnable plan step were found in this pack.*

## Candidate-1

| # | quote | issue | compressed-source induced? |
|---|---|---|---|
| C1-1 | "**Increment definition [K]:** ... **#40 emits the raw pre-normalize instruction** as a mandated, deterministic, sanitized artifact" | Typed **[K]** at the section header, but the pack's own s4 types the artifact "[I, design-pending]" and s7 types the seam "[I] Exact emission site in #40 ... **and whether the raw instruction is always available to #40 or must be threaded from the caller**". If the raw instruction may not reach #40 at all, the producer identity is not [K]. Internal typing inconsistency in the load-bearing claim. | **Partly.** The pack's cited support is a `w08 WORK_ORDER` follow-on line -- a work order is a summary surface for a contract-level question, and it names a *requirement owner*, not a proven emission site. The pack's own s7 caveat shows it knew this. |
| C1-2 | "*D2 (frontier-review lane, **OPTIONAL**, off-box, no lease)*" | The governing doc it quotes two sections earlier says "Each design-first -> **red-team-gated**", and s6 makes anything past a reader "design-first + red-team-gated". Marking the mandated gate optional is a plan-level constraint softening. The pack flags the tension in s7 but does not reconcile the plan to it. | **No.** The mandate is in the same quoted `next_increment` string the pack reproduces. |
| C1-3 | "(D-0064 human live-GUI confirm; **ship not blocked on it**)" | `CURRENT_STATE.md`: "**any UI change needs a human live-GUI confirm before it is called done.**" Ship-vs-done is a defensible distinction (LRAP shipped then confirmed), but the pack asserts the non-blocking half flatly and never states the "not done until confirmed" half. | **No.** The rule is stated in `CURRENT_STATE.md` "Current tests", a section the pack read. |
| C1-4 | "(b) reviewer reconstructs all **47 pack files** + runs `run_suite.py` (**364/364**) + `selfverify.py` (VERIFIED:True) **from an empty dir** (**D-0113**)" | Attribution conflated. D-0113 established the empty-dir/manifest-generated **rule** (its finding 5, on the i40 pack); the 47-file / 364/364 / VERIFIED:True **execution** is D-0118's round-5 review. Substance correct, D-number wrong for the numbers. | **Yes.** The pack's stated source is `research/2026-08-08-i42-...round5-ratification.md` -- a digest that carries both the rule and the run; a digest is exactly where two D-entries collapse into one narrative. |
| C1-5 | Absence, in a section that claims completeness: s4 "Dependency + contract analysis" and s5's widgets/08 lane carry **no w08 explain-window-close defect**, though the pack's own quoted cadence header line and its cited handoff s4/s11 both route it to "ANY earlier w08 touch". | The plan would dispatch a w08 lane that silently drops a routed, Nicholas-flagged UI defect. Not a false claim -- a confident plan with a known-missing obligation. | **Yes, plausibly.** This arm boots via a map/query surface; its own s1 records that surface as stale on `CURRENT_STATE`/`HANDOFF`/`DECISION_LOG` and its ledger shows the D-0134 material was never pulled from the log (`DECISION_LOG.md` explicitly not opened; the index not grepped for D-0134). A compressed boot surface plus an unopened log is a coherent path to this exact miss. |
| C1-6 | "**Readers:** ... `#37` selpol scores it" | Loose relationship statement: #37 **owns** the canonical selpol library and #40 imports it; describing #37 as a *reader* that "scores" the produced packet inverts the compile-time direction the same pack states elsewhere ("`#40 context.compiler` -- the sole `[governs]` target"). Could not be adjudicated against `CONTEXT_PACKET_CONTRACT.md`, which is outside my permitted pointer set. | **Plausibly yes.** The stated support is `QUERY-OP` edge queries -- a compressed edge view whose direction labels are easy to read backwards, and the same pack flags that surface's edge coverage as sparse. |

*No fabricated relationship that I could verify within scope, no violated frozen constraint at the pack's own
stated boundary, and no unrunnable plan step were found in this pack.*

---

## Adjudicator notes on verification limits (not scores)

1. **K10 conflicts with the tree's own log.** `DECISION_LOG.md` D-0134 states: "**The D-0129 PENDING live-click
   confirm is CLOSED -- CONFIRMED:** 'the 9B works' ... **DEFECT recorded:** the explain window 'can't be closed
   after the fact'". `CURRENT_STATE.md` and the `AUDIT_PIPELINE.md` cadence header still carry the pre-D-0134
   "PENDING" phrasing and the surviving window-close rider respectively. I marked K10 exactly as the spec words
   it (PENDING), which favors the pack that reproduces the hot doc's stale line; the substantive discriminator
   between the two packs is the **rider** (present in Candidate-2, absent in Candidate-1), which is uncontested
   in every source.
2. **Out-of-scope claims not adjudicated.** The two packs disagree on the selection-policy pin -- Candidate-2:
   "`CONTEXT_PACKET_CONTRACT.md` **s4** (P1-1 'one versioned selection-policy library')"; Candidate-1:
   "Selection contract = `CONTEXT_PACKET_CONTRACT.md` **s9** (R-1)" -- both typed [K]. `CONTEXT_PACKET_CONTRACT.md`
   and `MODULE_ROADMAP.md` are not spec-named pointers, so I did not open them and neither claim is scored as
   right or wrong. (`CURRENT_STATE.md` names both "0.2 + i32/i33/i34 + s9 R-1" without settling which section
   pins selpol.) Likewise unverified: all `_facts\` claims (HEAD sha, box state, git-log rows), all `widgets\`
   and `research\` pointers, and the boot-surface envelopes in Candidate-1 s1.
3. **Iteration count.** Candidate-2's "49 fan-out iterations run" matches handoff s3 verbatim;
   `CURRENT_STATE.md` still says 48. Not scored as an error -- the pack cited the owning doc.

**End of C2_VERDICT. No verdict, no winner, no recommendation is given, by instruction.**
