# i51 planning pack (DRY RUN)

**Model / settings:** `claude-opus-4-8` (Claude Opus 4.8), Cowork cloud sandbox, i51 the agent, DRY RUN. Sampling = product defaults (not exposed). Boot condition honored: `tree\core-docs\BOOT-DOC` -> the one live BOOT-DOC it names (`BOOT-DOC`) -> that doc's reading path. `BOOT-SOURCE\` NOT opened (excluded from my condition). No writes except this file; no dispatch/lease/commit/executor -- every such step is STATED, not done.

Tagging convention used throughout: **[K]** known (pointer-cited) / **[I]** inferred / **[U]** uncertain.

---

## 1. Understanding (current state, phase, active constraints)

**Phase [K].** "Building the Collective Agent" on cognitive virtual memory (D-0080): external authoritative stores + disposable model contexts; a deterministic coordinator hands a model a small task-specific packet; specialists execute; evaluators verify; success becomes reusable procedure (`PROJECT_DIRECTION.md` s"Present goal"; `CURRENT_STATE.md` Phase). Governed by the D-0050 offload/verify-cost audit loop; Nicholas is the audit authority.

**Where we are [K].** Modules 0-34 + memory #35-#43 + #44 project.map **0.3.0** (BOOT-SOURCE) + widgets 01-08 built; 49 fan-out iterations run; **next wave = iteration 51** (`HANDOFF` s3/s4). HEAD = the i50 docs-close commit (D-0140). Box healthy (`_facts\box-state.txt`: `degraded:false`, `poll_error_streak:0`, 0 orphans; durable `gpu-e3c5ba51.*` lease siblings persist by design).

**The i51 menu [K].** Open Nicholas item: stage the fresh legacy-vs-BOOT-SOURCE migration gate (licensable vs the D-0140 bars; projected ~0.35xA), OR a deferred-menu pick (`HANDOFF` s4/s11). The audit increment is **deferred item (b)**.

**Active constraints binding this task [K]:** boundary D-0051/52 (amended D-0080/0119 -- orchestrator never drives an external AI session; frontier lane human-couriered; in-session cloud subagents inside the boundary); wave clamps TR2 (<=1 GPU, MaxParallel 3, `git` lease serializes, `docs:[]`->0 contention, producer/consumer needs the D-0077 smoke); **P0-1 activation FROZEN**, `non_execution:true` everywhere (TR1); **SEALED_CHECK_47** sealed until i>=54; **audit cadence `review_due: i54`** (D-0137 override) -- the load-bearing constraint here (s2); seat = Fable 5 until settled (D-0134), ratification-critical work elevates to Opus 4.8 Extra (D-0114/16).

---

## 2. Task derivation (what the increment is + how I derived it)

**The audit/interpretability program's own governing documentation = `core-docs/AUDIT_PIPELINE.md`** (ADOPTED target doc, promoted i44 D-0121; budget 24 KB; the `MEMORY_ARCHITECTURE` pattern -- full design adopted, increments built by evidence one unit at a time, on a standing review cadence). Its machine-checkable state is its **cadence header** (s5.2: "the target doc's cadence header is the machine-checkable state").

**What the header says [K]** (`AUDIT_PIPELINE.md` cadence header, `next_increment (D-0127)`): the interpretability **POSER is SHIPPED** (widgets/08 `9f99495`), closing the D-0125 possession/rationale gap ergonomically. **The REMAINING set:** (1) **the raw-prompt FRONT step** (initial input to judge against; step-1 INPUT / P2 lane -> upstream emission); (2) **the LIVE ride-along** (audit-tag launch + per-step pause/unpause; A2.2); (3) **the OUTPUT side + instruction<->output reconciliation**. "Each design-first -> red-team-gated (the poser was the ungated exception, D-0126)." Corroborated by `MODULE_ROADMAP.md` widgets/08: v1 is assembly-side (steps 1-6) only; "the ride-along PAUSE hook + captured OUTPUT / instruction<->output reconciliation + possession/side-by-side are the deferred OUT set = the audit program's next increment."

**Scoped to ONE unit (BOOT-DOC), the NEXT increment = item (1), the raw-prompt FRONT step [K derivation, I on ordering].** It is listed first, least invasive (INPUT-side emission, reader-adjacent, no pause -> smallest shippable), and a prerequisite for item (3) reconciliation (you can't reconcile output against an instruction never captured). Concrete deliverable: turn the LRAP honesty-map's **step-1 INPUT / P2-lane "not emitted yet" cell** into a real upstream emission -- capture the raw ORIGINAL task input (which precedes step-1 normalize) as a mandated, replayable trace artifact rendered as timeline boot step. Items (2)/(3) are the subsequent increments, each design-first -> red-team-gated.

**The load-bearing tension -- schedule vs content [K]:** the SAME doc pins **`review_due: i54`** (NICHOLAS OVERRIDE, D-0137: the +4/+5 formula + s5 bump rule suspended; i54 co-schedules this review with the SEALED_CHECK_47 opening). Per s5.1, the first scoping question is "is `review_due` reached?" At **i51 it is NOT** (i54), no tier prerequisite flipped since i45, no new artifact class -> the doc's own rule says **"move on; write nothing."** SEALED_CHECK_47 SP6 independently requires `review_due >= 54`, so the cadence is deliberately pinned there.

**Therefore [K/I]:** the increment is DEFINED (front step) but **DEFERRED at i51**; the i51 default is the BOOT-SOURCE migration gate (`HANDOFF` s4). The audit wave activates at **i54** (with the sealed check), or earlier ONLY by an explicit Nicholas override of D-0137 -- the "i51 pick" s11 flags as open. The s5 plan is for that increment **when it activates**; producing it now does not license running it at i51. It passes the s6 shape test (it captures the ground-truth input that makes reconciliation + #37 fixture-minting checkable), so it legitimately enters a lane when due.

---

## 3. Evidence (what I consulted, why it sufficed)

- **`AUDIT_PIPELINE.md` (full)** -- the governing doc: cadence header (next_increment verbatim), tier ladder A0-A5 (activation gating), s3 the 8 binding principles, s5 the cadence rule, s6 the shape test. Self-declared "the CAPTURE"; machine-state lives in its header.
- **`BOOT-DOC` (full)** -- i51 frontier, deferred (b) + the i54/D-0137 rider, lanes/clamps (TR2), wave loop, ship-verify (TR3), seat/tiering.
- **`CURRENT_STATE.md` (full)** -- P0-1 (TR1), warm-pool default-OFF (P3), packet regions + #42 hydration (P2/P5), Known failures, Next action.
- **`SEALED_CHECK_47.md` (full)** -- SP6 pins `review_due >= 54`, corroborating the cadence trap.
- **`CONTEXT_PACKET_CONTRACT.md` (first 130 lines)** -- packet producer/reader + selpol pin (P5/P1); the i31-i34 amendment chain.
- **`DECISION_LOG_INDEX.md` (grep)** -- rows D-0079/0103/0107/0109/0116/0118/0089/0091/0137 (P1/P3/P4/TR1).
- **`MODULE_ROADMAP.md` (grep + 2 reads)** -- #42 follow-on = #21 wiring (P2); #37 owns selpol / CPC s4 pins it (P1); LRAP OUT-set = the next increment.
- **`PROJECT_DIRECTION.md`, `README.md`, `BOOT-DOC`, `_facts\*`, `_dispatch\{A,B}.md`** -- doctrine, boot route, box/git state, the A/B condition (A=legacy bootstrap, B=`BOOT-SOURCE`). I did NOT open `BOOT-SOURCE\` (out of condition), nor ingest `DECISION_LOG.md` (619 KB) -- the index + BOOT-DOC + CURRENT_STATE carried every D-entry needed.

Why sufficient: this is a governance read and the control-plane docs are canon; no live check was needed to DERIVE the increment, and box facts are given.

---

## 4. Dependency + contract analysis

**Contracts the front-step touches [K/I]:**
- **`CONTEXT_PACKET_CONTRACT.md`** -- the front step is a **trace-EMISSION** requirement, not a widget feature (principle 3.1 "readers over artifacts"; 3.2 "born instrumented or not born"): emit the raw input as a deterministic, versioned record, ns-closure-checked as a diagnostic array (i33 U1'), D-0077-fold-asserted. Field changes follow the s0 amendment protocol (version bump via DECISION_LOG entry + SCHEMA_NOTES re-verify) -- never a silent edit. **[U] producer/home:** the raw ORIGINAL prompt enters UPSTREAM of #40's `task_input` (already the normalized step-1 artifact); candidates: #21 `agent.local` (`-Goal`), the #7 gateway boundary, or a new #40 front stage -- the design's first decision.
- **`ACTION_AUTHORIZATION_CONTRACT.md` (FROZEN, D-0103)** -- untouched; read-only capture under `non_execution:true`; principle 3.6 keeps the P0-1 gate out of scope at every tier (TR1).
- **`MEMORY_CONTRACT.md`** -- the `ns_permitted` predicate is IMPORTED (owned by #37), never re-implemented, for the record's closure check.

**Module deps [K]:** renderer base = widgets/08 LRAP + the pinned 06/07 adapter (05/06/07 = expert-forensic descend target); producer instrumentation in #21/#40/#7; replay identity = the front record joins `packet_id`/`corpus_version`/`tree_version` (CPC s6) so any compile reconstructs boot step (s1.1).

**Contract-critical rule [K]:** a PRODUCER (emitter) + CONSUMER (LRAP render) built by parallel isolated workers against one design doc REQUIRE the orchestrator D-0077 fold smoke BEFORE close (`HANDOFF` s0/s8) -- binds the BUILD wave, not the design wave.

**Rider [K]:** the **w08 explain-window-close defect** (D-0134; live-click PENDING D-0129) rides ANY earlier w08 touch -> a build extending widgets/08 fixes it same-wave.

---

## 5. Proposed wave decomposition (units, lanes, briefs-in-summary)

Because the increment is **design-first -> red-team-gated**, the increment is a **DESIGN wave first, BUILD wave second**. (In the DRY RUN I author nothing and dispatch nothing; each "would" below is stated, not done.)

### Wave D (the increment as the doc names it -- DESIGN)
- **Lane A1 -- design (single lane; Opus 4.8 Extra [design-vs-closure -> D-0114 ELEVATE]; `docs:[]`; no GPU).** Brief-in-summary: *Author `research/<date>-i<N>-audit-front-step-design.md`: (a) the producer of the raw ORIGINAL input + its contract amendment to EMIT a `raw_input` front record {verbatim, `input_hash`, deterministic, in `evaluation_hooks`/diagnostics, ns-closure-checked, D-0077-fold-asserted}; (b) pinning into deterministic replay (joins packet identity); (c) LRAP render as timeline boot step, flipping the honesty-map step-1-INPUT/P2 "not emitted yet" cell to a real lane; (d) invariants: non_execution untouched, environment-not-mind, leases-outrank-ergonomics, read-only, i33 sanitization, writes nothing outside runtime; (e) build acceptance. FILE only; no ship.* Alternative [I]: small-diff premium-demand -> could run **orchestrator-INLINE** as a NO-code wave (i43/i44/i50 shape); I'd recommend inline unless a fresh independent design context is wanted.
- **Frontier red-team (off-box; #31 `pack`; human-couriered; NO lease; the design-first GATE).** Brief: *emit a pack {design doc + the 3 shipped contracts} to REFUTE the design against the 8 principles + the s6 shape test; answer returns between the `<<<FRONTIER-BRIDGE-ANSWER>>>` markers -> fold to a research digest.* **Sequential** to A1 (reviews A1's output) -> not a same-wave parallel lane; it is the post-wave courier gate that must PASS before Wave B.

At Wave D close I **would** update the cadence header + `next_increment` BY REPLACEMENT (design done; build pending red-team) + `last_reviewed`, only if activated -- but I make NO writes here, and would never set `review_due` < 54 (SP6).

### Wave B (follow-on BUILD -- sketch, after the red-team PASSES; NOT the i51 deliverable)
- **Lane B1 -- producer (CPU/coding; `docs:[]`; `git` lease; ship via dev.ship).** Instrument the chosen producer (#21/#40/#7) to emit the `raw_input` front record.
- **Lane B2 -- consumer (CPU/coding; `docs:[]`; `git` lease; ship via dev.ship).** Extend LRAP (widgets/08) + the 06/07 adapter to render boot step from the record; **fix the w08 window-close defect in-wave** (rider). UI change -> human live-GUI confirm (D-0064).
- B1+B2 are a PRODUCER/CONSUMER pair against Lane A1's one design doc -> may run parallel-isolated (2 CPU lanes, MaxParallel<=3, 0 GPU) with per-module SCHEMA_NOTES + **the mandatory orchestrator D-0077 fold smoke** before close.

**Lane/clamp check [K]:** Wave D = 0 GPU, 1 lane (<= the <=1-GPU HARD CLAMP and MaxParallel 3 trivially); Wave B = 0 GPU, 2 CPU lanes serialized on the `git` lease, `docs:[]` -> 0 doc contention. No `models.json` touch -> no GPU lane.

---

## 6. Verification plan + risks

**Verification [K]:**
- *Wave D (design):* deliverable = a design doc -> the FRONTIER RED-TEAM is the gate (not waved through) + orchestrator review vs the 8 principles + the s6 shape test. No code ship (no dev.ship/-Live).
- *Wave B (build) -- standing gates in order:* (1) off-machine cloud gate FIRST -> (2) `-Live` on the Windows executor -> (3) `dev.ship` (sha256+AST+tests, fail-closed) -> the **D-0077 fold smoke** (producer<->consumer) -> **VERIFY real HEAD via NATIVE git, NOT the dev.ship `committed` field** (D-0072; TR3) -> **human live-GUI confirm** (D-0064) -> assert **0 orphaned llama-server/python** + `review_queue.jsonl` before==after. Acceptance (A1/A2 + LRAP): byte-identical re-render; renders REAL artifacts; the honesty-map cell flips truthfully (no faked lane); the record round-trips through replay; ZERO lease-window violations; writes nothing outside runtime.
- *Dry-run check of THIS pack:* re-derived the increment two ways -- (a) `AUDIT_PIPELINE` cadence header, (b) `MODULE_ROADMAP` widgets/08 "deferred OUT set = next increment"; both agree; cross-checked the i54 deferral vs SP6.

**Risks:** (1, highest) **cadence/authority [K]** -- staging at i51 contradicts s5.1 ("review_due i54 -> write nothing") + risks SP6; *mitigation:* PLAN-ONLY, run early only on explicit Nicholas override, never move `review_due` < 54. (2) **non-displacement (s6) [K]** -- rehearsal / P0-1 suite / PB-3 / #40 sequencing outrank audit increments; the i51 default (BOOT-SOURCE gate) must not be displaced. (3) **producer-boundary [U]** -- a mis-chosen emitter captures the normalized step-1 input, not the raw ORIGINAL -> defeats "judge the run against what it was asked"; *mitigation:* resolve the producer FIRST; "born instrumented" (3.2) lands the amendment in the producer contract, not a widget workaround. (4) **scope creep into "mind" [K]** -- environment-not-mind (3.8): capture INPUT + affordances, never hidden reasoning. (5) **w08 rider [K]** -- a build touching widgets/08 fixes the window-close defect same-wave. (6) **worker-lacks-executor / bridge-death (i40/i48) [K]** -- verify what LANDED via native git; orchestrator runs gates + devship + files the report on the worker's behalf.

---

## 7. Unresolved questions (known / inferred / uncertain)

- **[U] Producer/home of the raw-input emission** -- #21 `agent.local` vs #7 gateway vs a new #40 front stage; the design wave's first decision.
- **[I] "step-1 INPUT P2"** -- read as the LRAP honesty-map LANE whose step-1 INPUT cell renders "not emitted yet" (`MODULE_ROADMAP` widgets/08); plausible, not defined in-doc.
- **[I] Granularity** -- front step ALONE (my scoping, per "one scoped unit") vs front+output bundled; Nicholas may bundle.
- **[U] Activation iteration if overridden** -- default i54; an earlier run is a Nicholas call (open s11 item), not derivable.
- **[K] Design lane vs orchestrator-inline** -- both valid; I recommend inline (NO-code wave), a fresh worker if independent design review is wanted. Sequencing of items (2)/(3) after the front step is a later cadence call.

---

## 8. Probe + trap answers (pointer-cited)

**P1 -- who owns the selection-policy canon, what pins it? [K].** #37 `retrieval.eval` owns the canonical `selpol_rrf_v1` selection-policy library (now **selpol 1.2.0**; `CURRENT_STATE` #37 row; `MODULE_ROADMAP` #37: "The canonical `selpol_rrf_v1` selection-policy library (CONTEXT_PACKET_CONTRACT s4 pins it)"). Pinned by: `CONTEXT_PACKET_CONTRACT.md` s4 (P1-1 "one versioned selection-policy library"; i31/D-0089 froze #37's scoring as canon; #40 IMPORTS it, its `selpol_reference.py` stub RETIRED; D-0091 settle) + #37's version single-source (skill.json) with a permanent `-Live` envelope==manifest DRIFT assertion (proven-to-fire; `CURRENT_STATE` #37). Consumed by #40 via import, never re-implemented (D-0088 found divergent impls -> D-0089 pin).

**P2 -- what depends on #42 (working.memory) today; what consumer wiring is a follow-on? [K].** Today #40 `context.compiler` 0.9.0 HYDRATES the packet's `working_memory` region FROM #42 (conjunctive `task_id`+namespace, fail-closed, byte-identical to absence; `state_version` in packet identity -- `CURRENT_STATE`/`MODULE_ROADMAP` #40; CPC i32 U3 / i33 U3'; region carries `content_role: working_state`, `can_instruct:false`). **Still-open consumer wiring:** **#21 `agent.local`** ("persistent working-memory (wire #42)", `MODULE_ROADMAP` #21) + **promote-to-durable + retention policy** (`MODULE_ROADMAP` #42). So #40 = the built compile-time consumer; #21 runtime wiring + promote-to-durable + retention = the follow-on.

**P3 -- why is the warm-pool durable supervisor default-OFF? [K].** Because its as-built red-team returned **GATE = NO** (D-0079): the durable Job-Object supervisor (0.4.0 i16 -> 0.6.0 i23; 10 must-fixes folded, finding-5 closed) is BUILT but NOT soak-ready. Default-ON is gated on: i24 deterministic hardening (9 P0/P1 + 18 tests) -> a trusted deployment config -> the #00.1 recovery driver (MF8) + trusted-hash provisioning (MF10; both HARD blockers) -> an in-process res.lease client -> a grown soak (>=24h, >=1000 transitions). Classic + the D-0057 DETACHED warm server stay the trusted default (`CURRENT_STATE` Known failures; `WARM_POOL_DESIGN.md` s10).

**P4 -- P0-1 ratification-arc failures + resulting discipline? [K].** A twice-repeated over-claim/walk-back (`DECISION_LOG_INDEX` D-0106..0118): D-0106 claimed a full-gate pass -> **D-0107** as-built re-review FAIL, walked back (over-claimed vs s6), 7 items->i39; D-0108 claimed an HONEST pass -> **D-0109** FAIL AGAIN, walked back, 7 findings->i40; **D-0116** i41 round-4 FAIL (not ratified; 3 seam findings; seat->Opus); **D-0118** i42 round-5 PASS = DESIGN pass (`p0_1_gate_status=pass`, pack `6bb613ea`; activation prohibited; arc closes 7->7->5->3->0). **Discipline:** M2-D **verification-before-ratification** standing (independent AS-BUILT re-review before any pass; never ratify from the builder's own view); the independent-grader boundary (fresh contexts caught D-0107/09); elevate the model for ratification-critical semantics (D-0116); + M2-A the doc-hygiene commit gate (i42).

**P5 -- what governs the context packet, who produces/reads it? [K].** `CONTEXT_PACKET_CONTRACT.md` (`context_packet/0.2`, i30 target D-0087; owns the packet + the selection layer; `MEMORY_CONTRACT.md` owns the record/retriever/eval layer). **Producer:** the deterministic coordinator = #40 `context.compiler` (imports #37's selpol; hydrates `working_memory` from #42). **Reader:** a disposable model context/specialist; while `non_execution:true` NO side-effecting consumer may execute from it. Four render-ordered regions: `control_plane` (the ONLY authority) -> `task_input` -> `working_memory` -> `evidence`.

**P6 -- last ~10 commits (`_facts\git-log.txt`)? [K].** The i48->i50 arc: **D-0135** i48 close (#44 CD-path 0.2.0: CD-1 boot canon + CD-3 queries; orchestrator-recovered ship; harvest fix 93->98) -> **D-0136** migration re-check RAN + FAILED on economics (B 1.24x A; VOID x2) -> **D-0137** i49 direction (N1 wave; **AUDIT `review_due` pushed i49->i54 by Nicholas override**) -> **D-0138** #44 0.2.0->**0.3.0** (N1 narrative queries + N2 frontier + N3 verb-table; fold VALIDATE 0) -> **D-0139** DECISION_LOG_INDEX growth-policy correction (INDEX is GROWTH-EXEMPT) -> **D-0140** i50 ratify the **N4 migration-gate bar re-freeze** -> **D-0141** cap exhaustion triggers re-layering, not indefinite compression. Net: #44 -> 0.3.0, the gate economics bars re-frozen (stageable, not run), the audit review deferred to i54.

**TR1 -- may P0-1 / action-authz be ACTIVATED now; what exactly is frozen? [K].** **NO.** P0-1 is a RATIFIED DESIGN pass only (`p0_1_gate_status=pass`, D-0118) with `activation_status=prohibited` -- a design pass, NOT an activation grant. Frozen: (a) the `ACTION_AUTHORIZATION_CONTRACT.md` spec itself is FROZEN (D-0103; changes need a version bump + re-verify); (b) activation of side-effect authority is PROHIBITED -- every `context_packet/0.2` carries `non_execution:true`, no action-capable consumer may execute from a packet while it holds, and #43's A06 denies every authentic packet. The audit program leaves the P0-1 gate untouched at every tier (AUDIT_PIPELINE 3.6). (`CURRENT_STATE` P0-1 row; `HANDOFF` s3.)

**TR2 -- wave concurrency clamps? [K].** <=1 GPU worker per wave (HARD CLAMP, ALWAYS); MaxParallel 3 = 1 GPU + 2 CPU validated ceiling; up to FOUR lanes may be scoped (GPU<=1, CPU(s), coding, frontier-review off-box/optional) but MaxParallel stays 3; the `git` lease serializes commits; `docs:[]` on every worker -> doc contention 0; ONLY the GPU lane touches `models.json` (model modules `parallel_safe:false`, single-worker); producer/consumer pairs REQUIRE the D-0077 fold smoke; assert 0 UNMANAGED orphans every wave; keep `-MaxParallel` at 3 until the heartbeat proves more. (`HANDOFF` s1/s4/s8.)

**TR3 -- how must a ship's landing be verified? [K].** VERIFY the real HEAD via **NATIVE git** (`git log`/`git show --stat`), **NOT** the `dev.ship committed` field (D-0072; dev.ship can FALSE-NEGATIVE). Full path: cloud gate FIRST -> `-Live` on the Windows executor -> `dev.ship` (sha256 + AST + tests, fail-closed, named files only) -> then confirm native HEAD; clear a stale 0-byte `.git/index.lock` via an executor task if needed. If a worker lacked pwsh/executor (i48) or its bridge died pre-push (i40), the orchestrator runs the gates + devship + files the report on its behalf, recording the recovery. Any UI change needs a human live-GUI confirm before "done" (D-0064); assert 0 orphaned llama-server/python + `review_queue.jsonl` before==after every live run. (`HANDOFF` s2/s7/s9.)

---

## 9. RETRIEVAL LEDGER

| seq | path-or-query | bytes | why | what it changed |
|---|---|---|---|---|
| 1 | device_list_dir `LifeOrch-i51-eval` (recursive) | ~145,673 (err) | enumerate tree | too large -> switched to per-dir listing |
| 2 | device_list_dir root | ~180 | top-level layout | found BOOT-SOURCE/_dispatch/_facts/_out/tree/MANIFEST |
| 3 | device_list_dir `_facts` | ~150 | facts inventory | box-state.txt + git-log.txt |
| 4 | device_list_dir `_dispatch` | ~130 | dispatch inventory | A.md + B.md |
| 5 | device_list_dir `_out` | ~20 | confirm output dir | empty (my single write target) |
| 6 | device_list_dir `tree` | ~260 | repo snapshot layout | core-docs/modules/ops/widgets/archive |
| 7 | device_list_dir `tree/core-docs` | ~1,900 | doc inventory + sizes | targeted which docs to stage |
| 8 | `_facts/box-state.txt` | 497 | given box state | degraded:false, durable gpu leases, 0 orphans |
| 9 | `_facts/git-log.txt` | 6,560 | P6 + iteration ledger | i48-i50 arc, D-0137 override, HEAD |
| 10 | `tree/README.md` | 1,222 | project framing | local-skills track; canonical repo path |
| 11 | `tree/core-docs/BOOT-DOC` | 5,423 | boot entry (condition) | routed to BOOT-DOC + always-read hot context |
| 12 | `_dispatch/A.md` | 2,513 | my dispatch | task, hard rules, 9 sections, probes/traps |
| 13 | `_dispatch/B.md` | 3,000 | peer condition | A/B = legacy vs `BOOT-SOURCE`; I must not open `BOOT-SOURCE` |
| 14 | `BOOT-DOC` | 23,891 | the live BOOT-DOC | i51 frontier, deferred (b)=AUDIT@i54, clamps, wave loop, TR2/TR3 |
| 15 | `CURRENT_STATE.md` | 34,295 | reality now | P0-1 (TR1), warm-pool (P3), packet/#42 (P2/P5), Known failures |
| 16 | `PROJECT_DIRECTION.md` | 10,756 | doctrine | Collective-Agent phase, audit-loop spine, boundary |
| 17 | `SEALED_CHECK_47.md` | 2,559 | sealed predicates | SP6 pins review_due>=54 -> confirms i54 cadence trap |
| 18 | `AUDIT_PIPELINE.md` | 20,384 | THE governing doc | next_increment=front step (D-0127); cadence i54; principles/shape test |
| 19 | `CONTEXT_PACKET_CONTRACT.md` (130 lines) | ~14,500 read | P5/P1 | producer=#40, reader=model ctx, selpol pin, non_execution |
| 20 | grep `DECISION_LOG_INDEX.md` (D-0079/103/107/109/116/118/089/091/137, selpol, FO-3) | 20,935 | P1/P3/P4/TR1 | pinned the P0-1 arc, warm-pool, selpol, audit-override rows |
| 21 | grep + 2 reads `MODULE_ROADMAP.md` (#42/#40/#37, audit/LRAP) | 31,826 | P2 + audit follow-on | #42 follow-on=#21 wiring; LRAP OUT-set = next increment; honesty-map P2 cell |

**DRY-RUN write/live-check register (stated, not done):** would have (a) filled + mirrored a `FANOUT_AGENT_00N` design slot; (b) authored `workers-i<N>.json` + `task-plan-i<N>.ps1`, run `-Action plan`, confirmed `dispatch_now`/<=1 gpu/0 doc contention; (c) emitted + couriered the #31 frontier red-team pack; (d) after a PASS, folded + updated the `AUDIT_PIPELINE` cadence header/`next_increment` BY REPLACEMENT under the `git` lease (never `review_due` < 54); (e) run the D-0077 fold smoke + verified native HEAD; (f) regenerated the doc-health monitor. I did NONE of these -- no lease/commit/dispatch/executor/`device_bash` call was made; box facts taken as given from `_facts\`.
