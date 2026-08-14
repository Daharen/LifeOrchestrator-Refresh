# AUDIT_PIPELINE -- the full human-in-the-loop audit + interpretability program (design TARGET, staged)

**Status:** ADOPTED governing target doc (promoted to `core-docs/AUDIT_PIPELINE.md` at i44, D-0121) -- the `MEMORY_ARCHITECTURE.md` pattern applied to the audit program:
adopt the FULL design as the target now; build increments by evidence, one scoped unit at a time, on a standing
review cadence (section 5). Companion + ENTRY VEHICLE: the 2026-08-05 scoping packet
(`2026-08-05-interpretability-audit-surface-scoping.md`), whose R-1 + Units A/B are tiers A0/A1 of THIS ladder.
Courier: Nicholas (D-0051/D-0052 lane). The authoring session performed NO repo/Project/doc writes.

**Provenance + self-sufficiency (load-bearing):** this program originated in an external frontier agent's
proposal to Nicholas (a "contract-level phenomenology debugger") and was viability-audited 2026-08-05 against
the shipped contracts by an off-box frontier evaluation session. NEITHER conversation is archived or reachable
by future sessions. THIS DOC IS THE CAPTURE: it must remain sufficient on its own for a future designer to
reconstruct intent without those chats. Do not slim section 2 below its ability to serve that purpose.

**Home:** `core-docs/AUDIT_PIPELINE.md` (promoted i44, D-0121; name ratified), budget
24 KB, REPLACE-don't-append per `DOC_PROTOCOL.md`; history to git + archive like every governing doc.

**Cadence header (orchestrator maintains by replacement -- the PROCESS_MANDATE countdown pattern):**
- `last_reviewed: i56` (D-0147 -- the i56 co-scheduled review ran at wave scoping: review_due reached, no tier-prereq flip since i45 (A3 remains designable, prereqs met), next_increment unchanged)
- `review_due: i58` (bumped +2 at i56 -- s5 no-spare-lane bump: the i56 wave is the two-CPU-lane PB-6 decision re-layer build (both lanes consumed), so no audit coding lane is spare; the w08 explain-window-close defect (D-0134) still rides ANY earlier w08 touch)
- `current_tier: A1 + read-only A2 + LRAP v1 -- Widgets 05/06/07 SHIPPED + live-GUI CONFIRMED i43 (expert-forensic descend target); NEW Widget 08 Live-Run Audit Pathway (assembly-side, steps 1-6, replay) SHIPPED + independently verified 87/0/0 (five-fixture 0 FP/FN) + i45 SHIPPED + machine-verified 87/0/0; Nicholas can SEE the machine flags but it is NOT a phenomenological pass even on the built cases (can't adopt the agent's role -- no initial prompt, rationale/agent-view not surfaced; D-0125) -- P9 NOT met (the poser, D-0127, now surfaces per-element rationale/agent-view on-demand)`
- `next_increment (D-0127): the interpretability POSER is SHIPPED (widgets/08 `9f99495`; per-element `?` -> local-9B explain + follow-ups; ungated, read-only held, fail-silent; cloud 104/0/3 + Win -Live 119/0/0) -- it delivered the D-0125 possession/rationale gap from the ergonomic end. The REMAINING set: (1) the raw-prompt FRONT step (initial input to judge against; step-1 INPUT P2 -> upstream emission); (2) the LIVE ride-along (audit-tag launch + per-step pause/unpause; A2.2); (3) the OUTPUT side + instruction<->output reconciliation. Each design-first -> red-team-gated (the poser was the ungated exception, D-0126); 05/06/07/08 stay the descend/replay base`

## 0. Purpose + the decoupling this buys

Nicholas is the audit authority of the whole system (the D-0050 audit-loop spine). The project's scale grows
without bound; his audit cost must NOT. The program's formal goal mirrors the memory architecture's own: a
DECOUPLING -- total system size may grow arbitrarily while the cost of auditing any one behavior stays bounded,
and only deliberately-global audits (full-wave replay, roll-forward forks) pay an explicit slow-path cost. The
mechanism is the same funnel the architecture uses on itself: **map -> gates -> trace -> possession** -- attend
at the top, descend on anomaly, never re-derive the whole system in one head.

**Honest scope.** The program debugs the ENVIRONMENT -- packet, rules, evidence, affordances, routing -- not the
model's hidden reasoning. In this architecture that is the correct target (durable intelligence deliberately
lives in the environment, `MEMORY_ARCHITECTURE.md` s12), but it means trace panes can never answer "is the 9B
smart enough"; ONLY side-by-side possession runs (A3) plus #37's curves answer that, statistically.

## 1. What FULL means (the end state, capability by capability)

1. **Everything replayable.** Any compile/run reconstructs from mandated artifacts alone (deterministic
   `packet_id`, pinned `corpus_version`/`tree_version`, selpol + stage traces, omission manifest).
2. **No staged decision without a versioned trace.** Every candidate-transforming stage in retrieval, routing,
   selection, eligibility, and (future) delegation emits `{policy_id, policy_version, in, removed[]+reasons,
   out}` -- the R-1 invariant, generalized (section 3.2).
3. **Every context enterable.** Ride-along stepping at any packet boundary; possession of any context --
   including spawned sub-agents -- with exactly the agent's own visibility and affordances, nothing more.
4. **Every compile forkable.** Compile-layer counterfactuals instantly (deterministic re-compile, one varied
   input); roll-forward counterfactuals as bounded batch runs from a forked checkpoint.
5. **Attribution answerable.** The dependency matrix scoreable per outcome: model intelligence / retrieval luck /
   one critical record / a rule / a summary / the working-state representation / the vector channel / the
   context budget / a sub-agent / the verifier catching an otherwise-invisible failure.
6. **The project renders its own growth.** A construction map: what exists, what is new, which iteration +
   D-entry + commit built it, what is verified by which gate, what is planned-but-unbuilt -- current every wave
   with zero added upkeep (it reads what DOC_PROTOCOL already maintains).
7. **Channels interpretable.** Per-channel contribution renders (lexical / vector / graph / temporal / symbol /
   failure-memory / prior-use), rank matrices, and ablation lines for any hit.

## 2. Mode catalog (the preserved design context -- keep sufficient, keep compact)

### 2.1 Trace/replay console (the minimal instrument)
Six panes: TASK TIMELINE; EXACT MODEL VIEW (the packet, four regions with trust banners); RETRIEVAL + SELECTION
TRACE; RULE/EXCEPTION STACK; TOOL + SUB-AGENT TREE; TOKEN + STATE LEDGER. Four controls: PLAY; PAUSE BEFORE
MODEL; POSSESS THIS CONTEXT; REVEAL OMNISCIENT TRACE (the cross-context stitched timeline). Panes render
contract-mandated artifacts only (section 3.1); the packet's own mapping table names each source.

### 2.2 Ride-along mode
The run halts BEFORE each model invocation / new context / delegation; Nicholas walks in, inspects the exact
inputs, steps forward. Nothing executes unviewed until culmination. Hard rule: pause points sit at packet-ready
boundaries OUTSIDE lease windows (section 3.3).

### 2.3 Possession mode
Nicholas BECOMES the agent at any level. He sees exactly: parent goal, his bounded sub-question, namespace +
permission grant, his evidence packet, his completion contract, the baton schema he must return. He cannot see:
sibling packets, the parent model's hidden reasoning, out-of-scope memory, the final synthesis. Affordances are
the agent's OWN ops only: answer; request expansion (the immutable expand delta); propose a skill/procedure;
report a contradiction; abstain; instantiate a subordinate context (when delegation exists); author the baton
artifact `{finding, supporting_records, contradictions, unresolved, confidence, recommended_next_expansion}`.
On return, he watches how his artifact is integrated. Purpose: feel the difference between holding the whole
task, receiving a bounded subtask, and reporting into a larger process he cannot fully see.

### 2.4 Side-by-side mode
The model runs; Nicholas answers the SAME packet blind; the console renders both trajectories INLINE -- what
each read, invoked, and produced, in order, per instantiation -- plus the culmination diff. Every such run mints
a human-adjudicated labeled fixture for #37 (section 3.5). This mode, not the trace panes, is the model-tier
probe.

### 2.5 Counterfactual mode (two classes, never conflated)
**Compile-layer (cheap, deterministic):** re-run the compile on the SAME pinned snapshot with ONE varied input --
channel mask (seed: the MEMORY_CONTRACT s6 hybrid-attribution mandate), selection-policy version, effective
namespace set, `temporal_intent`, budget, an excluded `record_version_id`, a synopsis-staleness toggle, a
`state_version` rollback -- then diff packets. **Roll-forward (expensive, batch-only):** fork from a checkpoint,
change one decision, re-run live to culmination (greedy decoding on the pinned local build keeps it
reproducible); one variation per run, serialized behind the gpu lease, never interactive. Output of either: a
line in the attribution matrix (s1.5), e.g. "without vector retrieval, rec_427 does not enter the top 20."

### 2.6 Tool-selection tournament
Render the staged skill/module selection as elimination rounds with per-stage counts + reasons: eligibility
(removed: wrong task type / unavailable deps / insufficient permission / wrong OS / unhealthy / resource
conflict) -> semantic retrieval of skills+procedures+failures -> task classification -> rerank to a short set ->
9B preflight over activation cards -> deterministic plan validation (accepted, or REJECTED with the failed
checks named). Requires only that those stages emit R-1 traces at birth.

### 2.7 Delegation tree (future; PB-2-gated)
When the local coordinator exists, every spawn renders from its DELEGATION-DECISION event
`{delegation_policy_id, policy_version, trigger_class, reason_codes[], spawned_context_refs[]}` (an EPISODE
STAGE structurally -- the `record_kind` enum stays CLOSED). Trigger vocabulary to preserve for that design:
GLOBAL_SCOPE; SEPARABLE_BRANCHES; CONTEXT_BUDGET_PRESSURE; SPECIALIST_CAPABILITY_REQUIRED;
INDEPENDENT_REVIEW_REQUIRED; UNCERTAINTY_REQUIRES_EXPANSION; CONFLICTING_EVIDENCE; PARALLEL_LATENCY_BENEFIT;
RISK_REQUIRES_SECOND_REVIEW. Children are possessable (2.3); batons render on fold.

### 2.8 Channel interpretability layer
Per hit: which literal terms lexical matched; the vector neighbors + similarities in the named
`embedding_space_id`; the graph path traversed (e.g. `decision_44 -> superseded_by -> decision_61`); the
temporal filter applied; the symbol matched; the failure-memory signature hit; prior-use statistics. Plus the
rank matrix (per record: LEX / VEC / GRAPH / FAILURE / FINAL) and the ablation line. Rule renders show
fired/excluded/overridden with inputs and outputs, e.g.: RULE current_state -> current_only: FIRED; RULE
exclude non-effective_current: candidate decision_44, live successor decision_61 -> EXCLUDED
(`hard_filter_superseded`); EXCEPTION: explicit user date outranks the class default -> `historical_as_of`
(this override is already contract law -- i33 U5'). NOT in scope at any tier: explaining WHY an embedding is
near beyond neighbors/ranks/ablation (section 6).

### 2.9 Construction map (the project's own provenance)
Module -> version -> iteration -> D-entry -> commit (dev.ship trailers) -> files -> verification state
(Verification Console verdicts, fold smokes, eval curves) -> roadmap next. Views: "new since iteration N";
planned-but-unbuilt; per-module drill; over-budget hot-doc flags (auto-surfacing PB-3-class debt). This is the
funnel's top altitude and the first thing built (A1).

## 3. Load-bearing principles (bind every tier)

1. **Readers over artifacts.** The Tier-0/Tier-1 contracts already mandate the trace substrate (deterministic
   packet identity, selpol `ranked[]`/`reason_codes[]`/`stages[]`, omission manifest, V3 completeness fields,
   `consumer_profile`, #39/#42 lineage). Widgets RENDER; they do not instrument. Where a render is impossible,
   the gap is a missing trace-emission requirement (3.2), never a widget-side workaround.
2. **The R-1 invariant, generalized.** No staged candidate-transforming decision ships without a deterministic,
   integer-only, versioned stage-trace, carried in `evaluation_hooks`/diagnostics, namespace-closure-checked as
   a diagnostic array (i33 U1'), asserted by the D-0077 fold. Born instrumented or not born.
3. **Leases outrank ergonomics.** Pause/possession points sit OUTSIDE lease windows, at packet-ready boundaries.
   A deliberating human must never hold the `gpu` lease or block a finalize (the D-0055/56 wedge, with a person
   as the orphan).
4. **Existing affordances only.** Possession offers the agent's own ops -- never new powers. Isolation comes
   free: the packet IS total agent-visible context by construction (P0-1/A5).
5. **Audit time mints ground truth.** Every side-by-side/possession run emits a #37-ingestible labeled fixture.
   MEMORY_BENCHMARK explicitly reserves scarce human judgment for exactly this.
6. **`non_execution` holds everywhere.** No possessed or replayed context acquires side-effect authority; the
   P0-1 gate is untouched by this program at every tier.
7. **The tool trails the build by ~one tier.** Never build a pane before the artifacts it renders exist (the
   vector pane waits for a live vector channel; the tournament waits for the router's traces).
8. **Environment, not mind.** No tier promises access to hidden reasoning; claims of that kind are out of scope
   by definition.
9. **Phenomenological legibility (P9, D-0120).** An audit surface is done NOT when it renders the artifacts but
   when Nicholas can FOLLOW a run without prerequisite schema expertise: each step presents, in plain language
   and chronological order, [what the step is SUPPOSED to do] vs [its actual input] vs [its actual output],
   with anomalies surfaced AT the step where they occur, in ONE pathway with no window-switching. The expert
   forensic panels (Widgets 05/06/07) are the DESCENT target reached on anomaly, not the top surface; the
   A1-A2 shipped altitude assumed an expert operator and is insufficient alone. Realized by the LRAP increment.

## 4. The tier ladder (A0-A5; each = prerequisites -> deliverables -> acceptance -> activation)

- **A0 -- trace substrate (standing invariant).** Prereq: none. Deliverables: R-1 bound on the i36/i37 router
  unit + one line in its contract amendment; the 3.2 invariant recorded as standing rule for all future staged
  components. Acceptance: the D-0077 fold asserts trace presence + determinism on the first traced component.
  Activation: at adoption of the companion packet. Cost: ~0 (a requirement, not a lane).
- **A1 -- map + trace console (read-only).** Prereq: A0 adopted; i35 fold artifacts exist. Deliverables:
  Widget 05 Provenance Map (2.9) incl. the "new since iteration N" view; Widget 06 Compile Trace Console (2.1
  panes 1-4,6) + the compile-layer counterfactual runner (2.5a). Acceptance: the packet's s4/s5 gates
  (byte-identical re-render; ablation reconciles with #37 hybrid attribution; renders REAL fold/rehearsal
  artifacts; writes nothing outside its own runtime dir; i33 sanitization honored). Activation: next spare
  coding lanes (~i36-i38), never displacing the #40 sequencing or the rehearsal.
- **A2 -- stepping + stitched visibility.** Prereq: router shipped WITH A0 traces; #42 wired into #40 (the i36
  unit-2 wiring). Deliverables: ride-along pause (2.2) via a gateway hold hook at packet boundaries; the
  tournament pane (2.6) over router/eligibility traces; the omniscient cross-context timeline (episodes + plans
  + `state_version` chains + batons). Acceptance: step a real compile end-to-end with ZERO lease-window
  violations; the timeline renders a full wave; tournament counts reconcile with stage traces. Activation:
  ~i37-i39, spare lanes.
- **A3 -- possession + side-by-side (the human-in-the-loop core).** Prereq: i40 sunset report done; Tier-1
  acceptance state known; its OWN design doc -> frontier red-team (the b4c90545 pattern) -> build. Deliverables:
  Possession Harness (2.3) + side-by-side with inline dual traces (2.4) + fixture minting (3.5). Acceptance: a
  blind human run on an identical packet yields a #37-ingestible fixture; an injection probe proves a possessed
  context cannot touch `control_plane` (rides the standing P0-1 suite); every 3.x principle demonstrably holds.
  Activation: post-i40, by explicit go.
- **A4 -- forks + delegation depth (evidence-gated).** Prereq: A3 live; for delegation -- the PB-2 coordinator +
  the 2.7 event exist. Deliverables: roll-forward counterfactual runner (2.5b, batch-only) scoring the
  attribution matrix; delegation-tree possession (2.7). Acceptance: one variation per run, reproducible,
  serialized behind the gpu lease; a documented debugging question A1-A3 could NOT answer, answered. Activation:
  ONLY on such a documented need -- never speculatively.
- **A5 -- horizon (may never activate).** Deeper vector-space interpretability (only if the live vector channel
  produces a measured misretrieval class that neighbors/ranks/ablation cannot explain); cross-iteration
  construction analytics (growth-vs-verification-coverage curves). Each requires a benchmark-style evidence case
  first, per the MEMORY_ARCHITECTURE Tier-3 rule.

## 5. Cadence + upkeep (how this stays alive without becoming a tax)

> **i44 note (D-0121):** the D-0120 finding reprioritized `next_increment` to **LRAP** (ahead of A4/A5); the
> promotion of this doc to `core-docs/` is that step's clean home. LRAP proper is design-first + red-team-gated
> (s6 / A3); spec `research/2026-08-08-i43-live-run-audit-pathway-design.md`.

1. **At every wave scoping** (one line of orchestrator time): is `review_due` reached? did a tier prerequisite
   flip (router shipped; #42 wired; i40 report done; PB-2 opened)? did a new artifact class appear? If all no --
   move on; write nothing.
2. **When due or triggered:** update the cadence header + `next_increment` BY REPLACEMENT; if a coding lane is
   spare, scope the next increment as ONE unit (`docs:[]`, exclusive widget/module area, normal dev.ship +
   fold). If no lane is spare, bump `review_due` by 1-2 iterations and record why -- the cadence bends, it does
   not silently drop.
3. **Proposed PROCESS_BACKLOG item (PB-4):** "AUDIT_PIPELINE increment -- consult `AUDIT_PIPELINE.md`; cadence
   <=4-5 iterations or on tier-gate events; take a spare coding lane when an increment is activatable; the
   target doc's cadence header is the machine-checkable state."
4. **Review cost bound:** the periodic review is a header update + at most one lane -- never a redesign. Redesign
   of THIS doc requires a D-entry, like any governing doc.

## 6. Anti-spiral guardrails (carried from the packet; binding)

Non-displacement: the rehearsal, the P0-1 suite, PB-3, and the #40 sequencing always outrank increments.
Read-only by default: every increment through A2 is a reader; anything that pauses or enters the pipeline (A3+)
is design-first + red-team-gated. Deliberately unbuilt until evidence: roll-forward interactivity (never --
batch only), embedding-explanation research, any live-operate IDE surface. The shape test for every proposed
increment: **does it make a GATE cheaper to verify, or does it chase total comprehension?** Only the first kind
enters a lane. This doc has a 24 KB budget; the mode catalog (s2) may be tightened but never below
self-sufficiency (the provenance note).

## 7. Relationships + adoption

The 2026-08-05 scoping packet = the entry vehicle (A0/A1 concretely scoped; adopt it first). `MEMORY_BENCHMARK`
= where A3 fixtures flow. PB-2 = the delegation dependency (2.7). The Verification Console (Widget 03) = the
existing audit surface this program extends -- same doctrine, next altitude. `MEMORY_ARCHITECTURE.md` = the
structural template (full target adopted, tiers built by evidence, doc amended via D-entry). Adoption mechanics:
one D-entry naming both files; this doc lands `core-docs/research/` via courier and is PROMOTED to
`core-docs/AUDIT_PIPELINE.md` on ratification (name + budgets ratifiable); the cadence header starts counting at
the adopting iteration.
