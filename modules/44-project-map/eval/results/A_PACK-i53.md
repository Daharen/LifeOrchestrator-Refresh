# i53 migration-gate dispatch — A_PACK (Agent A, DRY RUN)

**Running on:** model `claude-opus-4-8`, as *i53 Agent A* (orchestration-planning, read-only dry run). No sampling settings exposed in-session; default config assumed. **Dry-run discipline observed:** no writes except this file in `_out\`; no executor jobs / leases / commits / dispatches. Where my procedure calls for a live write or check, I STATE it instead. `_bundle\` NOT opened (out of condition). Boot = standard bootstrap: `START_HERE.md` → the one live handoff (`FANOUT_ORCHESTRATOR_HANDOFF.md`) → its reading path; `_facts\` taken as given box/git state. Legend: **[K]** known/cited · **[I]** inferred · **[U]** uncertain.

---

## 1 Understanding (current state, phase, active constraints)

**Phase [K].** "MVP module build-out," repivoted (D-0080) to building the **Collective Agent / cognitive virtual memory**: external stores authoritative, disposable model contexts, a deterministic coordinator hands a small packet to a model, specialists execute, evaluators verify, success becomes reusable procedure. Governed past-MVP by the D-0050 offload/verify-cost **audit loop** (offload only what is cheaper to VERIFY than to do). `CURRENT_STATE.md:15`, `PROJECT_DIRECTION.md:7`, `START_HERE.md:24`.

**Where we are [K].** 52 iterations run. Modules 0–34 + memory **#35–#43** + **#44 project.map 0.4.0 (PCB)** + widgets 01–08 built; Tier-1 memory **ACCEPTED** (i36, D-0102). i52 closed the D-0142 fix wave: #44 → **0.4.0** (`c6c58a8`; N5 doc-section/`card:` granularity + N6 canon + open_rulings render), **N7** close-refold adopted+first-run, **N8** re-run protocol ratified-as-amended (D-0144). `FANOUT…HANDOFF.md:9,33,44`, `CURRENT_STATE.md:24-32`, `git-log.txt:1-2`.

**The active decision — i53 [K].** i53 = "the gate-staging decision" (`git-log.txt:2`). Nicholas call: **STAGE + RUN the fresh two-class migration gate** (legacy-bootstrap vs #44-PCB) under D-0140/N4 bars + D-0144/N8 protocol, **or** the deferred menu (audit next-increment · #40 beam-width · PB-7 re-layer · PB-2). Legacy stays DEFAULT until a gate PASSES both classes. `FANOUT…HANDOFF.md:48-52`, `CURRENT_STATE.md:360`.

**Active constraints in force right now [K]:** ≤1 GPU worker/wave + MaxParallel 3 (1 GPU + 2 CPU); `git` lease serialises commits; `docs:[]` on every worker; frontier lane human-couriered only (D-0051/52). P0-1 activation FROZEN; SEALED_CHECK_47 sealed (evaluate only at i≥54). Ship landing verified via NATIVE git, not dev.ship's `committed` field (D-0072). Every core-doc commit passes the fail-closed doc-gate. Orchestrator seat = Fable 5 until Nicholas declares settled. `FANOUT_ORCHESTRATOR_HANDOFF.md:18,52,55-56,80,84,122`.

---

## 2 TASK-1 — memory-subsystem build-state census (#35–#42 + #44)

"Owner" = field-authority contract/gov doc. "Audit/freeze" = attached audit widget and/or active freeze.

| # · id | ver | build status | owning contract / gov doc | audit widget / active freeze |
|---|---|---|---|---|
| **35 embedding.local** | 0.1.0 | **MVP complete** (i25, D-0082) | MEMORY_CONTRACT (embedding-provider iface; space_id first-class in #36) | freeze: MEMORY_CONTRACT **frozen D-0083**; audit: none direct |
| **36 artifact.search** | 0.7.0 | **MVP complete** (i25→i39; D-0082…0108) | MEMORY_CONTRACT (record envelope + SQLite catalog + FTS5 retriever + Tier-1 hierarchy nodes) | freeze: MEMORY_CONTRACT D-0083; audit: retrieval/span lineage rendered in w06 |
| **37 retrieval.eval** | selpol 1.2.0 / eval 0.8.1 | **MVP complete** (i25→i40; PB-5 closed) | **CONTEXT_PACKET_CONTRACT** (pins canonical `selpol_rrf_v1`, s4) + MEMORY_BENCHMARK (eval) | audit: selpol stage-traces in w06 + w07 tournament; R-1 standing rule |
| **38 repo.intel** | 0.1.0 | **MVP complete** (i27, D-0084) | MEMORY_CONTRACT (typed-record producer; **sole `record_kind=skill` owner**) | freeze: MEMORY_CONTRACT D-0083 |
| **39 episode.record** | 0.1.1 | **MVP complete** (i27/i28, D-0084/85) | MEMORY_CONTRACT (episode + failure record schemas; `has_stage`) | freeze: MEMORY_CONTRACT D-0083; audit: episodes = w07 omniscient timeline substrate |
| **40 context.compiler** | 0.9.0 | **MVP complete** (i29→i38; D-0086…0106) | **CONTEXT_PACKET_CONTRACT** (`context_packet/0.2` compiler + R-1 router + wm-hydration) | audit: **w06** compile-trace + **w08 LRAP** replays #40; R-1 router = A0 trace anchor |
| **41 skill.card** | 0.2.0 | **MVP complete** (i29/i30, D-0086/88) | MEMORY_CONTRACT (`record_kind=summary` / `summary_type=skill_activation_card`) | freeze: MEMORY_CONTRACT D-0083; audit: eligibility stage in w07 tournament |
| **42 working.memory** | 0.1.0 | **MVP complete** (i34, D-0099) | MEMORY_CONTRACT (**A5 U3′** per-task working store; CAS) | freeze: MEMORY_CONTRACT D-0083; audit: `state_version` chains in w06/w07 |
| **44 project.map** | 0.4.0 | **code MVP complete** (i52, D-0145) **but ACCEPTANCE gate NOT passed** — built alongside legacy control; legacy stays default | its own directive (D-0130/31) + **N4 bars (D-0140)** + **N8 protocol (D-0144)** — *not* a memory contract | active freeze: **migration-gate NO-GO (D-0142)** + frozen N4/N8 bars; audit: it *is* the PCB / construction-map producer (kin to A0.5/A1) |

Table sources: `MODULE_ROADMAP.md:271-349`, `CURRENT_STATE.md:24-32,126-135,240-250`, `ARCHITECTURE_MAP.md:130-150`, `HANDOFF.md:22,70-71`.

**(a) Which module is NOT yet built to MVP — and the decision that governs it.**
Strictly, **all nine carry status "MVP complete"** (`MODULE_ROADMAP.md:14` + rows), so by the literal label none is pre-MVP. Trap-aware answer: **#44 project.map** is the one *not built out to its accepted MVP purpose*. Code is complete (0.4.0), but its defining job — be the default **bootstrap** replacing the legacy handoff — is **not accepted**: built "ALONGSIDE the legacy handoff (control)," the fresh migration gate returned **NO-GO** (i51, D-0142: floor-(b) breached + total 2.74×/1.12× A vs the 0.7× bar; BOOT passed), CONDITIONAL until a gate PASSES **both** N8 classes. Governing decision: **D-0142** (NO-GO), under **D-0140** (N4 bars) + **D-0144** (N8 protocol). `MODULE_ROADMAP.md:332-345`, `CURRENT_STATE.md:32,360`. **[K]** facts; **[I]** reading "built to MVP" as "accepted to purpose." (The module usually cited as unfinished — **#43 action.authz**, design-only, activation *prohibited*, D-0118 — is deliberately **outside** this set.)

**(b) Which single contract / governing doc owns the largest share.**
**`MEMORY_CONTRACT.md`** — the record/provenance/embedding/retriever/working-memory field authority (frozen D-0083). It owns **6 of the 9**: #35, #36, #38, #39, #41, #42. `CONTEXT_PACKET_CONTRACT.md` owns 2 (#37 selpol, #40 packet); #44 answers to its own directive + the N4/N8 eval bars. `MEMORY_ARCHITECTURE.md:7,263`, `MODULE_ROADMAP.md:284,301-319`. **[K].** If "governing doc" is read at the *design* level rather than field level, **`MEMORY_ARCHITECTURE.md`** (D-0090) is the single design-target governor over the whole memory substrate #35–#42 (8/9, all but the PCB #44) — I flag this as the alternative reading **[I]**.

**(c) Which of these modules sit in more than one plane.**
Planes = the D-0080 **Collective Agent planes** (Memory · Retrieval · Context-compiler · Skill-activation · Episode/failure/procedure · Sandboxed-worker · Unified interface), `ARCHITECTURE_MAP.md:130-150`. Mapping each module's scope onto those definitions, the multi-plane modules are:
- **#36 artifact.search — Memory + Retrieval.** It *is* the "first SQLite catalog + artifact store" (Memory plane) **and** the FTS+vector+hierarchy hybrid retrieval (Retrieval plane). Strongest case. `ARCHITECTURE_MAP.md:136,138`, `MODULE_ROADMAP.md:275-282`.
- **#40 context.compiler — Retrieval + Context-compiler.** Its R-1 **multi-channel query router** (query classification + routing) is Retrieval-plane work; its packet assembly is the Context-compiler plane's centerpiece. `ARCHITECTURE_MAP.md:139-141`, `MODULE_ROADMAP.md:301-310`.
- **#38 repo.intel — Memory + Skill-activation.** A general typed-record producer (Memory plane) **and** the sole `record_kind=skill` owner feeding the Skill-activation plane (whose cards are #41). `ARCHITECTURE_MAP.md:136,142-143`, `MODULE_ROADMAP.md:292-294`.

Borderline **[I]**: **#37** (its `selpol_rrf_v1` is pinned by CONTEXT_PACKET_CONTRACT and imported by #40 — a shared library straddling Retrieval↔Context-compiler more than "sitting in" both). Single-plane: #35 (Retrieval infra), #39 (Episode/failure/procedure), #41 (Skill-activation), #42 (Memory). **#44** is the *meta-map* owning the `plane:` namespace — it maps planes rather than living in one. **Provenance [I]:** derived from the canonical plane *definitions* + module scope; the machine-checkable module→`plane:` edges live in #44's map state, which I did **not** open — so (c) is inferred, not read from edges.

---

## 3 TASK-2 — the audit/interpretability program's next increment + dry-run wave plan

### 3a Task derivation (what the next increment is, and how I derived it)

The audit/interpretability program's own governing doc is **`AUDIT_PIPELINE.md`** (AP; ADOPTED target, promoted i44/D-0121). Its machine-checkable state is the **cadence header**; `next_increment (D-0127)` records: the interpretability **POSER is SHIPPED** (w08, `9f99495`) — closing the *rationale/agent-view* half of the D-0125 gap — and names the **REMAINING set**: **(1) the raw-prompt FRONT step** (initial input to judge against; step-1 INPUT P2 → upstream emission); (2) the **LIVE ride-along** (pause/unpause; A2.2); (3) the **OUTPUT side** + instruction↔output reconciliation. Each design-first → red-team-gated. `AP:20-22`.

**Derived SINGLE next unit = the raw-prompt FRONT step [I, well-grounded].** Reasoning: (i) D-0125 named *two* gaps in the LRAP top surface — "no initial prompt" and "rationale/agent-view not surfaced"; the poser closed the second, so the **remaining named gap is the raw prompt** = item (1). `CURRENT_STATE.md:346`, `MODULE_ROADMAP.md:378-388`. (ii) It is listed first and is the lowest-risk of the three — a read-only *upstream emission*, whereas the ride-along (2) *pauses the pipeline* (higher A2.2/A3 gate). (iii) "Readers over artifacts" (s3.1): the front step is really a missing trace-emission requirement (the raw instruction must be emitted as a mandated artifact), which is the **prerequisite** for the OUTPUT-side reconciliation (3) — you cannot reconcile instruction↔output without the instruction front. So the front step both closes the residual D-0125 gap and unblocks (3).

**Framing / honesty [K]:** dry-run derivation. i53's actual expected action is the migration-gate staging decision; **AUDIT is one deferred-menu item**, review not due until **i54** (D-0137, co-scheduled with the SEALED_CHECK_47 opening). Final selection among the three is Nicholas's at that review. `HANDOFF.md:52`, `AUDIT_PIPELINE.md:20`.

### 3b Governing constraints (every active freeze / gate / human-in-the-loop / verification rule on HOW it is built)

All cite `AUDIT_PIPELINE.md` (AP) unless noted.
1. **Design-first → frontier red-team gate** (D-0126/0127, AP s6): anything past read-only A2 is design-first + red-team-gated; the poser was the *only* ungated exception — so: design-doc → frontier red-team → build (the A3 `b4c90545` pattern).
2. **Read-only by default; writes nothing outside its own runtime dir** (AP s6 / A1 acceptance).
3. **Readers over artifacts** (AP s3.1): a render gap is a missing *emission* requirement, never a widget-side hack.
4. **R-1 invariant, generalized** (AP s3.2): staged candidate-transforming decisions emit a deterministic, integer-only, versioned stage-trace, ns-closure-checked, D-0077-fold-asserted — "born instrumented or not born."
5. **Leases outrank ergonomics** (AP s3.3): pause/possession points sit OUTSIDE lease windows at packet-ready boundaries — no human holds the `gpu` lease or blocks a finalize (the D-0055/56 wedge, person as orphan).
6. **`non_execution` holds / P0-1 untouched** (AP s3.6): the emitted front stays evidence (`content_role=evidence`, `can_instruct=false`), i33-sanitized; no side-effect authority.
7. **Tool trails the build ~one tier** (AP s3.7): emission ships with/before the render.
8. **Environment, not mind** (AP s3.8): no hidden-reasoning access.
9. **P9 legibility** (AP s3.9, D-0120) = the acceptance bar: each step, plain-language + chronological, [SUPPOSED] vs [actual input] vs [actual output]; anomalies at the step; ONE pathway, no window-switching.
10. **Anti-spiral / non-displacement** (AP s6): rehearsal, P0-1 suite, PB-3, #40 sequencing outrank increments; shape test — "makes a GATE cheaper to verify" not "chase total comprehension."
11. **Cadence** (AP s5): take a spare coding lane only when activatable, else bump `review_due` + record why. `review_due:i54` (D-0137) — building at i53 pulls it forward.
12. **Wave/lane mechanics** (`HANDOFF.md:18,54,60-62`): `docs:[]` on every worker; ≤1 GPU worker; frontier lane human-couriered (D-0051/52); Nicholas dispatches each fresh session + picks its model.
13. **Landing/verification** (build wave; `CURRENT_STATE.md:212-216`, `HANDOFF.md:58,80,84`): cloud gate → `-Live` → `dev.ship` (fail-closed); **native-git HEAD** not dev.ship's field (D-0072); human **live-GUI** confirm for UI (D-0049/60/64); **D-0077 fold smoke** for a producer+consumer pair; 0-orphan assertion; **N7** close-refold 0-stale; M2-D verify-before-ratify.
14. **SEALED_CHECK_47** stays sealed at i53 (open only i≥54). `HANDOFF.md:12,52`.

### 3c Proposed wave decomposition of the SINGLE next unit (dry run)

Because the front step is design-first, the **immediate** single unit is its **DESIGN + red-team gate** (one scoped unit / session); the actual build is the following wave, only on a red-team PASS.

**Wave i53-AUDIT-FRONT (dry run — I would author, not dispatch):**

- **Unit:** *Audit raw-prompt FRONT-step — design + frontier red-team.*
- **Lane 1 — Design/coding (CPU, no GPU) · recommend Opus 4.8 Extra** (ELEVATE: design-vs-closure + audit-surface semantics, D-0114). Brief-in-summary: author `research/2026-08-14-audit-front-step-design.md` specifying — (a) the **upstream emission**: which producer emits the raw initial prompt/instruction as a mandated, deterministic, versioned artifact (the P2 "not emitted yet" step-1 cell on the w08 honesty map becomes a real lane); (b) any `context_packet` identity/field impact + R-1 trace if a staged transform appears; (c) how w08 LRAP renders it as the **front of the one P9 pathway** (SUPPOSED vs INPUT vs OUTPUT); (d) read-only + writes-nothing-outside-runtime + `non_execution` + i33 sanitization; (e) acceptance gates (byte-identical re-render; REAL artifacts; five-fixture 0 FP/FN, the LRAP bar); (f) the **red-team surface** (faked/absent front; raw-prompt injection; lease-window boundary; honesty-map integrity). `docs:[]`; delivers the doc as a FILE + reports; orchestrator mirrors under the `git` lease.
- **Lane 2 — Frontier-review (off-box, human-couriered) · REQUIRED** by the design-first→red-team rule: a #31 `pack {prompt, files:[design doc]}` Nicholas-couriered (D-0051/52) to red-team the design; answer between the `<<<FRONTIER-BRIDGE-ANSWER-…>>>` markers, folded to a digest. **No lease. Gates the build.** (D-0113 manifest-extract-and-run does not apply — no runnable suite claimed.)
- **No GPU lane** (no `models.json` touch); **no 2nd CPU lane** (single exclusive area).
- **Stated, not done (dry run):** fill+mirror `FANOUT_AGENT_001`; author `workers-i53.json` + `task-plan-i53.ps1` (`-Iteration 53 -MaxParallel 3`, no `gpu:true`); run `plan`; confirm `dispatch_now` / ≤1 gpu / 0 doc contention; emit the pack; relay as FILES; poll `status` → `handoff`.

**Concurrency clamps for this wave (TR2):** MaxParallel ≤ 3; here 1 dispatched worker (design) + 1 off-box human-couriered pack (no lease, not counted); **0 GPU** workers (≤1 clamp trivially met); `git` lease serialises the single mirror commit; `docs:[]` → doc contention 0; 0-UNMANAGED-orphan assertion at close.

**Follow-on build wave (stated):** one coding lane builds the w08 front-step render + upstream emission (`docs:[]`, normal dev.ship), verified under 3b#13 — incl. the **D-0077 fold smoke** (emission producer + w08 renderer = a producer/consumer pair) + a human live-GUI P9 confirm.

### 3d Verification plan + risks

**Verification.** *Design wave:* the frontier **red-team verdict is the gate** (D-0126); M2-D verify-before-ratify; the `research/` commit passes the fail-closed doc-gate; the AP cadence header updated **by replacement** (24 KB budget) + a D-entry. *Build wave:* the full standing-gate ladder (3b#13) — cloud → `-Live` → dev.ship, native-git HEAD (D-0072), five-fixture 0 FP/FN + byte-identical re-render + real-artifact render + i33 sanitization, the D-0077 fold smoke, human live-GUI P9 confirm, 0-orphan, N7 0-stale.

**Risks.** (1) *Scope creep* toward ride-along/possession (A3) — hold the anti-spiral shape test; keep it read-only emission (3b#10). (2) *Raw-prompt injection* — the front stays evidence/`can_instruct=false` + i33-sanitized; P0-1 untouched (3b#6). (3) *Lease boundary* if it later feeds the ride-along — pause OUTSIDE lease windows (3b#5). (4) *Readers-over-artifacts* — no hacking the front into w08 without a real upstream emission (3b#3). (5) *Cadence/timing* — review not due until i54 and i53's real call is the migration gate; this pulls the increment forward (3b#11).

---

## 4 Evidence (what I consulted, why it sufficed)

- **BOOT/shared:** the prescribed hot set — `START_HERE.md`, `FANOUT_ORCHESTRATOR_HANDOFF.md`, `CURRENT_STATE.md`, `PROJECT_DIRECTION.md` + `_facts\` box/git state — jointly fix phase, active work, clamps, gates and the i53 decision; sufficient for §1 and all three traps.
- **TASK-1:** `MODULE_ROADMAP.md` + `CURRENT_STATE.md` gave every census row directly; `MEMORY_ARCHITECTURE.md` fixed contract ownership + tier/MVP state; `ARCHITECTURE_MAP.md` supplied the plane definitions. I did **not** open the two large field contracts (MEMORY_CONTRACT 44 KB, CONTEXT_PACKET 35 KB) or #44's map edges — the roadmap+architecture docs already name owners and planes, so they'd add bytes without changing answers; (c) is thus marked inferred.
- **TASK-2:** `AUDIT_PIPELINE.md` (cadence-header `next_increment`, A0–A5 ladder, s3 principles, s5 cadence, s6 guardrails) is primary and self-sufficient; the handoff + CURRENT_STATE supplied wave/lane/lease/verification mechanics and the deferred-menu framing.
- **Deliberately not opened:** `DECISION_LOG.md` (635 KB, index-routed; no single D-entry was decision-changing here) and `_bundle\` (out of condition).

---

## 5 Trap answers (pointer-cited)

**TR1 — May P0-1 / action-authz be ACTIVATED now? What exactly is frozen?**
**No — activation is prohibited.** #43 is a **RATIFIED DESIGN pass** (`build_status=build_complete | p0_1_gate_status=PASS | activation_status=prohibited`); `non_execution:true` holds and A06 denies every authentic packet — "a design pass, NOT an activation grant." What is frozen: (i) the **`ACTION_AUTHORIZATION_CONTRACT.md` is FROZEN (D-0103)** (its s7 is the gate-status record); (ii) the **activation transition itself** — the real `non_execution=false` transition (with Windows permit-store IPC/ACL/CAS, crash recovery, timing-channel hardening, rollback) is a *staged, activation-gating follow-on*, and **P0-1 ACTIVATION stays FROZEN** on the deferred menu. `CURRENT_STATE.md:31`, `MODULE_ROADMAP.md:321-330`, `FANOUT_ORCHESTRATOR_HANDOFF.md:22,52`.

**TR2 — Wave concurrency clamps?**
**≤1 GPU worker per wave (HARD CLAMP).** **MaxParallel 3 = 1 GPU + 2 CPU** (validated ceiling; FANOUT_PROTOCOL); keep `-MaxParallel` at 3 until the heartbeat proves more. Up to **four lanes** may be *scoped* (GPU / CPU(s)+coding / frontier-review), but the frontier lane is off-box + human-couriered + holds no lease. The `git` lease **serialises commits**; `docs:[]` → **doc contention 0**; producer/consumer pairs across workers **require the D-0077 fold smoke**; assert **0 UNMANAGED orphans** every wave. `FANOUT_ORCHESTRATOR_HANDOFF.md:18,54-56,106`, `CURRENT_STATE.md` (test table, MaxParallel 3).

**TR3 — How must a ship's landing be verified?**
**Verify the real HEAD via NATIVE git** (`git log` / `git show --stat` through the executor), **NOT** the `dev.ship` `committed` field — dev.ship can FALSE-NEGATIVE the commit (**D-0072**). `dev.ship` itself is fail-closed (sha256 → AST-parse → tests, named files only, trailers). Because a worker's device bridge can die pre-push (i40), the orchestrator confirms what LANDED via native git and, if needed, runs gates + devship + files the report on the worker's behalf; clear a stale 0-byte `.git/index.lock` via an executor task, then re-commit. `FANOUT_ORCHESTRATOR_HANDOFF.md:80,99`, `CURRENT_STATE.md:325-327,257-261`.

---

## 6 Unresolved questions

- **[K] i53 branch is Nicholas's call** — migration gate vs the deferred menu (incl. this audit increment). I analyzed the audit branch per TASK-2; did not presume the pick. `HANDOFF.md:48-52`.
- **[I] "Built to MVP" for 2(a).** All nine are labelled "MVP complete"; the #44 answer reads the phrase as "accepted to purpose." Literal label → "none in the set." Stated both ways.
- **[I] Exact module→`plane:` edges (2c)** live in #44's map state, not opened; assignments derived from the canonical definitions + module scopes. #37's count is the least certain.
- **[I] The single next audit unit (3a)** — three remain; I derived the front step (first / lowest-risk / gap-closing). Nicholas holds final selection at i54.
- **[U] Whether a coding lane is "spare" at i53** to activate the increment — gated on lane availability (AP s5.2); if not spare, bump `review_due`.
- **[U] CONTEXT_PACKET_CONTRACT freeze status** — MEMORY_CONTRACT (D-0083) + ACTION_AUTHORIZATION (D-0103) are explicitly frozen; I found no explicit freeze D-entry for CONTEXT_PACKET_CONTRACT (0.2, amended i32–i34), so asserted none for #37/#40.

---

## 7 RETRIEVAL LEDGER

Order = access order. Listing `retrieval_bytes` are the emitted JSON sizes (approx, marked ~). Every staged file was fully opened (whole-file open → retrieval = model-visible; no staged-but-unread files).

| seq | task | path-or-query | retrieval_bytes | model_visible_bytes | why | what it changed |
|---|---|---|---|---|---|---|
| 1 | BOOT | `device_list_dir C:\…\LifeOrch-i53-eval` (top) | ~280 | ~280 | confirm listability + top layout | found tree/_facts/_out/_bundle/_dispatch |
| 2 | BOOT | `device_list_dir tree\` | ~330 | ~330 | locate core-docs | found core-docs/modules/ops/widgets |
| 3 | BOOT | `device_list_dir _facts\` | ~180 | ~180 | given box/git state | box-state + git-log present |
| 4 | BOOT | `device_list_dir tree\core-docs\` | ~2500 | ~2500 | find START_HERE + doc sizes | doc inventory + sizes (flagged 635 KB log to avoid) |
| 5 | BOOT | `tree\core-docs\START_HERE.md` | 5423 | 5423 | boot entry | routing + phase; named the live handoff |
| 6 | BOOT | `_facts\box-state.txt` | 497 | 497 | box state | heartbeat fresh, durable gpu leases, 0 orphans |
| 7 | BOOT | `_facts\git-log.txt` | 2901 | 2901 | git state | i52 FINAL; **i53 = gate-staging**; #44 0.4.0 |
| 8 | shared | `tree\core-docs\FANOUT_ORCHESTRATOR_HANDOFF.md` | 24092 | 24092 | the one live handoff | frontier/next=i53, clamps, gates, tiering |
| 9 | shared | `tree\core-docs\CURRENT_STATE.md` | 34319 | 34319 | reality now | module versions, P0-1, freezes, known failures |
| 10 | shared | `tree\core-docs\PROJECT_DIRECTION.md` | 10756 | 10756 | doctrine | Collective Agent + offload/audit-loop framing |
| 11 | T2 | `tree\core-docs\AUDIT_PIPELINE.md` | 20384 | 20384 | audit program's own gov doc | next_increment (D-0127) + ladder/principles/cadence |
| 12 | T1 | `tree\core-docs\MODULE_ROADMAP.md` | 32416 | 32416 | per-module status/owners | census rows; #44 gate state; follow-ons |
| 13 | T1 | `tree\core-docs\MEMORY_ARCHITECTURE.md` | 30427 | 30427 | tiers + contract ownership | (b) owner counts; Tier-1 ACCEPTED; MVP framing |
| 14 | T1 | `tree\core-docs\ARCHITECTURE_MAP.md` | 16496 | 16496 | plane definitions | (c) plane assignments; L0–L5 hierarchy |

**Totals:** retrieval ≈ **181 KB** ≈ model-visible (≈ 3.3 KB listings + 177.7 KB files). No staged-but-unread bytes; `DECISION_LOG.md` (635 KB) + `_bundle\` never transferred — selective staging kept charged bytes ≈ what entered context.
