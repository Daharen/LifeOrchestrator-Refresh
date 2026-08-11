# B_PACK — LifeOrch i47 eval (DRY RUN)

**Runner:** model `claude-opus-4-8` (Claude / Cowork agentic loop). **Settings:** dry-run planning mode; no executor jobs / leases / commits / dispatches; single permitted write = this file (`_out/B_PACK.md`). Temperature/sampling not user-exposed; high-reasoning tool-use config. Where my procedure calls for a write or a live check, I **STATE** it instead of doing it.

**Frozen snapshot** = `tree/` worktree @ `0bcb5e7d9fdcd78a85cd4b646c9e2aca8190520c` (short `0bcb5e7`); live box HEAD `53c211f` is 6 commits ahead (i46 PCB work) — I planned strictly against the frozen SHA. Below, `SNAP:` = `tree/` @0bcb5e7; tags **[known]** (cited) / **[inferred]** / **[uncertain]**.

---

## 1 Understanding (current state, phase, active constraints)

**Phase [known]** — "Building the Collective Agent on cognitive virtual memory" (D-0080). Iteration counter = **45 done; next wave = i46** (`SNAP:core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` §"next wave is iteration 46"; `BOOT_PACKET` OVERLAY). Modules 0–34 + memory #35–#43 + widgets 01–08 built; **Tier-1 ACCEPTED (i36, D-0102)**; audit program **mid-arc** (LRAP shipped i45; poser arc D-0126..D-0129).

**Box (given `_facts`) [known]** — heartbeat `degraded:false`, `active_tasks:0`, `stuck_finalize:0`; leases dir holds only the durable `gpu-e3c5ba51.{fence,state,txn}` siblings (persist by design; **no LIVE lease**); 0 UNMANAGED llama-server/python orphans expected (`SNAP:FANOUT_ORCHESTRATOR_HANDOFF.md` §2). I read the live heartbeat/leases to reconstruct this; the frozen `_facts/box-state.txt` itself sits in the sibling eval folder outside my grant **[uncertain on exact staged process counts]**.

**Active constraints / PROHIBITIONS [known]** (`BOOT_PACKET` OVERLAY; `SNAP:DECISION_LOG_INDEX.md`):
- **P0-1 / action.authz ACTIVATION prohibited** — D-0118 is a **DESIGN pass only** (`p0_1_gate_status=pass`); `non_execution:true` holds; no `non_execution=false` until Nicholas licenses.
- **No orchestrator-driven external/frontier AI** — frontier material is human-couriered (D-0051/52); **in-session cloud subagents ARE permitted** (D-0119).
- **Warm-pool durable supervisor default-ON = GATE-NO / FROZEN** (D-0079); classic detached-warm (D-0057) is the trusted default.
- **FROZEN** (D-0080): generator upgrades #22–#25, video.interpret + live composition, deep real-time perception, broad training.
- **Mandate 02** live (sunsets i47; countdown **45/2 done → i46 = 46/1**); its **M2-D "verify-before-ratify"** discipline is structural.
- **Doc-commit-gate LIVE** on every core-doc commit since i42 (M2-A); over-budget hot docs are REJECTED.
- **Fan-out clamps:** ≤1 GPU worker/wave (HARD); MaxParallel 3 = 1 GPU + 2 CPU ceiling.

---

## 2 Task derivation (what the increment is + how I derived it)

**The governing field [known].** `SNAP:core-docs/AUDIT_PIPELINE.md` cadence header, `next_increment (D-0127)`, states verbatim: the interpretability **POSER is SHIPPED** (`widgets/08` `9f99495`; per-element `?`→local-9B explain; ungated, read-only-held, fail-silent; cloud 104/0/3 + Win -Live 119/0/0) — it "delivered the D-0125 possession/rationale gap from the ergonomic end." **The REMAINING set:** (1) the **raw-prompt FRONT step** (initial input to judge against; step-1 INPUT P2 → upstream emission); (2) the **LIVE ride-along** (audit-tag launch + per-step pause/unpause; A2.2); (3) the **OUTPUT side + instruction↔output reconciliation**. "**Each design-first → red-team-gated** (the poser was the ungated exception, D-0126); 05/06/07/08 stay the descend/replay base." `PB-4` mirrors this and adds the machine-checkable cadence: `last_reviewed i45 / review_due i49 / next_increment = ride-along+output`, **NON-DISPLACING** (gate ratification, M2-A, core memory sequencing outrank it).

**Therefore the next increment = the "LRAP completion" increment**, and by the doc's own rule it must be **design-first, then frontier-red-team-gated** before any build (the poser was the single ungated exception, now spent). **[known]**

**How I scoped the ONE unit [inferred, well-grounded].** Cadence rule 5.2 = "scope the next increment as ONE unit"; frugality D-0114 governs; A3 prereq = "its OWN design doc → frontier red-team → build." So **i46 = the DESIGN + red-team wave**, not a build. I lead the design with the **raw-prompt FRONT step** because D-0125 names "no initial prompt to judge against" as gap #1 — the binding blocker to *adopting the agent's role* — and it is the one purely read-only, upstream-emission item that does **not** touch live lease windows (ride-along/output do; heavier gating per anti-spiral §6). The handoff's front-runner shorthand ("ride-along + OUTPUT side", `FANOUT_ORCHESTRATOR_HANDOFF.md` §4/§9) is the same increment named from the other end; I fold all three into one design doc so the red-team sees the whole completion set. **Non-displacing caveat [known]:** at i46 the audit increment is NOT cadence-due (review_due i49) — it is scoped only because a lane is spare and the LRAP tier-gate is open (D-0125 P9 unmet); if no lane is spare, the correct move is bump review_due +1–2 and record why.

---

## 3 Evidence (what I consulted, why it sufficed)

**STEP 0 tool envelopes (RUN in cloud on the staged `_bundle`) [known]:**
- `validate --map _bundle/map-eval --harvest _bundle/harvest-eval.json` → `{"status":"ok","result":{"ok":true,"error_count":0,"findings":[],"warnings":[],"stale":[]}}`.
- `render --check --map … --out _bundle/generated-eval` → `{"status":"ok","result":{"checked":true,"stale_count":0,...}}`; all 6 cards byte-match (ALIASES/BOOT_PACKET/L0/L1×3), `boot_packet_bytes 12711`. → **The compiled map is in sync with source; the L0/L1 cards are trustworthy as the L2 index.** `query stale` also `[]`.

**Why it sufficed.** The governing question — "what does the audit program's own doc say the next increment is" — is answered by a single canonical field (`AUDIT_PIPELINE.next_increment`, cross-checked against `PB-4` and the handoff), which is machine-current (cadence header + `stale_count 0`). The dependency/contract/probe answers came from the four boot_read owner docs + the two contracts + the decision index/log at the SHA. The map's L1 cards supplied module identity/edges. I did **not** need the legacy prose beyond these (each open is a ledger row, §9).

**Tooling limitation [known, reportable].** `query edges:module:42|30|37` returned `edges:[]` and `query entity:widget:08` returned `DANGLING_REF` — the eval map does not encode module→module edges under those ids and widget ids differ from `widget:NN`. Not a dead end: I fell back to the L1 card `edges in/out` lines + `DECISION_LOG_INDEX` + contracts, which are authoritative.

---

## 4 Dependency + contract analysis

**A0 trace substrate / R-1 invariant [known].** The FRONT-step build must emit an **R-1, integer-only, versioned stage-trace at birth** (raw→decompose→route), carried in `evaluation_hooks`/diagnostics, namespace-closure-checked — `AUDIT_PIPELINE.md` §3.1/§3.2. This turns `widgets/08` step-1 INPUT from a P2 "not emitted yet" honesty-lane into a real trace.

**CONTEXT_PACKET_CONTRACT (`context_packet/0.2`) [known].** Producer = **#40 context.compile** (deterministic 3-region control/evidence compiler); the ride-along **pause hook must sit at packet-ready boundaries** (`AUDIT_PIPELINE` §3.3 "leases outrank ergonomics"). Any new packet/selection field = **versioned bump + a `DECISION_LOG` entry + re-verify #40/#37 + the D-0077 fold** (`CONTEXT_PACKET_CONTRACT.md` §0.2). `query_class` (i32/U6) drives selpol temporal mode, so a FRONT-step that stamps `query_class` earlier is a real coupling to hold stable.

**Selection canon [known].** `selpol_rrf_v1`/1.0.0 owned by **#37 retrieval.eval**, **PINNED** by `CONTEXT_PACKET_CONTRACT.md` §4 (i31, D-0089); **#40 imports it** (no reimplementation). The FRONT step is upstream of selection and must **not** perturb it (read-only; anti-spiral §6).

**res.lease #29 [known].** ride-along pause/unpause + any possession point must sit **OUTSIDE lease windows** (§3.3); GPU lease is whole-task; a live proof harness that acquires real gpu leases must NOT wrap an outer whole-task gpu lease (i21 gotcha).

**P0-1 / #43 action.authz (FROZEN, design-only) [known].** ride-along/possession stay **read-only** and must not enable execution; the A3 acceptance rides the **standing P0-1 injection suite** (a possessed context cannot touch `control_plane`). `non_execution:true` (CPC §0.2).

**working.memory #42 [known/inferred].** Live consumer today = **#40** (wm-hydration, #40 0.9.0, D-0105/06); #42 card shows only `governs<-MEMORY_ARCHITECTURE`. Broader lifecycle consumers (agent-loop snapshot writes, promote→#39 episode, the reserved query seam D-0092) remain follow-ons **[inferred]** — not on this increment's path.

**Producer/consumer + doc rules [known].** #40↔#27/#08 cross-worker pair ⇒ **D-0077 fold smoke** required. The design doc lands in `core-docs/research/`; cadence-header replacement of `AUDIT_PIPELINE.next_increment` + `CURRENT_STATE` + `PROCESS_MANDATE` countdown all pass the **doc-commit-gate**.

---

## 5 Proposed wave decomposition (units, lanes, briefs-in-summary)

**Wave i46 = a DESIGN-FIRST + red-team wave (NO build, NO GPU lane).** Clamps trivially met: 0 GPU, ≤2 on-box lanes, MaxParallel ≤3, `docs:[]` on workers ⇒ 0 doc contention. *(In a live run I would author `workers-i46.json` + `task-plan-i46.ps1` from `task-plan-i40.ps1`, run `plan`, confirm dispatch_now/≤1 gpu/0 contention — **stated, not executed**.)*

**Unit U1 — LRAP-completion DESIGN (on-box CPU/coding lane; `docs:[]`; lease: git for the mirror only).**
Brief-in-summary: *Author `core-docs/research/2026-08-11-i46-lrap-completion-design.md` specifying, as ONE design, the three remaining LRAP items: (1) FRONT step — upstream raw→decompose→route **R-1 emission** at the #40 compile front (+ #27 route trace), rendered at `widgets/08` step-1 INPUT (retire the P2 lane); (2) ride-along A2.2 — a gateway-hold pause hook at packet-ready boundaries with audit-tag launch + per-step pause/unpause, **provably outside lease windows**; (3) OUTPUT side — capture model output + instruction↔output reconciliation to replace verdict-only RECONCILE (F1). Bind every §3 principle; define acceptance = A2 "step a real compile end-to-end, ZERO lease-window violations" + A3 "blind human run yields a #37-ingestible fixture." Enumerate contract deltas (CPC version bump? #40/#37 re-verify + D-0077 fold) and the P0-1 read-only/injection-suite guard. Deliver as a FILE.* Model lane: Sonnet 5 High is spec-able, but this is **ratification-adjacent audit doctrine** → elevate to Opus per D-0114 elevation triggers **[inferred]**.

**Unit U2 — FRONTIER red-team (off-box review lane; #31 courier; NO lease; OPTIONAL-but-expected).**
Brief-in-summary: *Package U1's design as a `frontier.bridge` pack for Nicholas to courier (the A3 `b4c90545` pattern); question = is the front-step emission sound + does the pause hook respect lease windows + does the output-side reconciliation stay read-only under P0-1. Fold the returned verdict (NO-GO / GO-WITH-AMENDMENTS + ranked findings) back into the design.* This lane is why the wave is design-first: the build is **gated on a GO**.

**No GPU lane; no build unit this wave.** The **downstream build increment (i47+, gated on U2 GO)** decomposes as **[inferred sketch, not this wave]:** (B1) FRONT-step upstream R-1 emission on the #40/#27 seam + `widgets/08` render wiring (a real module unit, `docs:[]`, dev.ship + D-0077 fold); (B2) ride-along gateway-hold hook on #07/#29 boundaries (touches live lease windows → extra gating, P3/P6); (B3) output-capture + reconciliation pane. Each stays ≤1-unit, design-honored, live-GUI human-confirmed.

---

## 6 Verification plan + risks

**Verification (this dry-run) [known]:** STEP 0 `validate`+`render --check` both GREEN (§3) — recorded. For U1/U2 the acceptance IS the red-team round: **do NOT claim a pass** before the frontier verdict lands and is folded (M2-D). *(I would then mirror core-docs under the git lease and run the doc-gate on the staged budgets — stated, not executed.)*

**Verification (downstream build, when it runs) [known]:** ship via **`dev.ship` fail-closed** (`exec-job.sh devship` = sha256 → AST-parse → tests, named files only, trailers); **VERIFY the real HEAD via NATIVE git, not the `committed` field** (D-0072 false-negative); **orchestrator INDEPENDENT re-verify** (SELFTEST_*_OK counts, five-fixture 0 FP/FN like the i45 87/0/0); **0 UNMANAGED orphans + heartbeat degraded:false**; **D-0077 fold** for the #40/#27 pair; **live-GUI human confirm** for `widgets/08` (mock/API gates MISS rendered-UI defects); A2 "ZERO lease-window violations."

**Risks:**
1. **Lease-window deadlock** from the ride-along pause — *mitigate:* pauses only at packet-ready boundaries outside leases (§3.3); no outer whole-task gpu wrap (i21). [known]
2. **Human-gate over-claim recurrence** (D-0107/0109/0125 pattern) — *mitigate:* verify-before-ratify, hedge acceptance wording, keep the independent-grader fan-out boundary. [known]
3. **Scope creep past ONE unit** — *mitigate:* design-only this wave; frugality D-0114; non-displacing to gate/M2-A/memory work. [known]
4. **FRONT-step emission perturbing selpol/packet identity** — *mitigate:* versioned bump + #40/#37 re-verify + fold; keep it strictly read-only/additive. [inferred]
5. **P9 "phenomenological" bar is subjective** — *mitigate:* use A3's objective proxy (blind human run → #37-ingestible fixture; injection probe vs control_plane). [known]

---

## 7 Unresolved questions (known / inferred / uncertain)

- **Which single item leads, and is i46 design-only or design+build?** The `next_increment` field lists all three as a set, each "design-first → red-team-gated"; I **inferred** design-only, FRONT-step-led. A Nicholas ruling / the fresh session's lane choice pins it (cadence 5.2). **[inferred]**
- **Is a spare lane actually available at i46?** review_due is **i49**, so the increment is non-displacing and only scoped if a lane is free and higher-priority work (none open on P0-1; M2-A shipped; Tier-2/M2-C memory sequencing) doesn't claim it. **[known constraint / uncertain on lane availability]**
- **Exact staged `_facts/box-state.txt` values** (llama/python process counts at stage time) — reconstructed from the live heartbeat/leases, not read from the sibling eval `_facts`. **[uncertain]**
- **Does the FRONT step require a CPC version bump or is it additive-only?** Depends on whether it adds a packet/selection field vs only a diagnostics trace — to be settled in U1. **[uncertain]**
- **Whether U2 (frontier lane) is mandatory** — the doc says "red-team-gated"; I treat it as required for the build GO. **[inferred]**

---

## 8 Probe + trap answers (pointer-cited; SNAP = tree @0bcb5e7)

**P1 — selection-policy canon owner + pin.** Owner = **#37 retrieval.eval** (`selpol_rrf_v1`/1.0.0). Pinned by **`SNAP:core-docs/CONTEXT_PACKET_CONTRACT.md` §4 (i31, D-0089/0091)** — the composite relevance-primary score + additive output shape are FROZEN as #37's canonical selpol; **#40 IMPORTS it**, its `selpol_reference.py` stub RETIRED; pure-rank-RRF primary = deferred P1-2. (`DECISION_LOG_INDEX` D-0088/0089/0091.) **[known]**

**P2 — #42 working.memory dependents + follow-on.** Live consumer today = **#40 context.compile** via **wm-hydration** (#40 0.9.0, D-0105/06; A2 prereq "#42 wired into #40, the i36 unit-2 wiring"). #42 card (`L1_CARDS_modules.md`) shows only `governs<-MEMORY_ARCHITECTURE`. **Follow-on:** broader lifecycle consumers — agent-loop snapshot writes, promote→#39 episode, the reserved working/query seam (D-0092) — remain unwired. **[known consumer / inferred follow-on list]**

**P3 — why warm-pool durable supervisor default-OFF.** **`SNAP:core-docs/DECISION_LOG.md` D-0079** (i24 frontier-review lane): an **off-box security red-team of the durable supervisor + real evictor (pack `5cbe8913`; digest `research/2026-07-31-frontier-supervisor-redteam.md`) returned GATE = NO with 7 structural blockers** (spawn-before-Job-assign; one supervisor-wide Job Object + heuristic `tree_gone`; pool-lock steal + nonce-less release; fail-open EnsureResident; wedged-supervisor split-brain; provenance-by-timestamp; IPC target-fencing gaps). Custody/fencing/atomic-transition safety is unproven, so **enabling it by default could kill the warm resident or starve higher-priority GPU work**; the classic **detached-warm (D-0057) path stays the trusted default and is unaffected**. Frozen among D-0079/D-0080 items. **[known]**

**P4 — P0-1 gate ratification failures + resulting discipline.** Arc: D-0106 pass → **D-0107 walked back** (as-built re-review FAIL, over-claimed vs s6) → D-0108 "honest pass" → **D-0109 walked back AGAIN** → **D-0110 mandate-02 LICENSED with M2-D verify-before-ratify structural** → D-0111/0112 exact closures (no pass claim) → D-0113 round-3 FAIL → D-0115/**0116 round-4 FAIL** (F1/F7 = manifest-pack rule proven) → D-0117 → **D-0118 round-5 DESIGN PASS** (arc 7→7→5→3→0). **Discipline:** never claim a gate pass before an independent **as-built re-review** (M2-D); **manifest-derived, empty-dir-pre-verified** review packs; the **fan-out independent-grader boundary** (fresh narrow contexts) is what caught D-0107/0109 — "FANOUT STAYS." (`DECISION_LOG_INDEX` D-0106..0118; `FANOUT_ORCHESTRATOR_HANDOFF.md` §"Fanout stays".) **[known]**

**P5 — context-packet contract, producer, consumers.** `SNAP:core-docs/CONTEXT_PACKET_CONTRACT.md` governs `context_packet/0.2` (control/evidence separation + selection layer). **Producer = #40 context.compile.** **Readers:** `widgets/06` compile-trace-console (renders #40 regions), `widgets/08` LRAP (replays a #40 compile), `widgets/03` verification-console (packet in → verdict out), + the model consumer; selection = #37 selpol. Change-control: version bump + `DECISION_LOG` + re-verify #40/#37 + D-0077 fold; `non_execution:true` (no action-capable consumer executes from a packet). **[known]**

**P6 — last ~10 commits (`_facts/git-log.txt` = git log -12 @0bcb5e7).** The **LRAP acceptance→poser arc**: `0bcb5e7` D-0129 poser live no-op ROOT CAUSE fix (dotnet-tool apphost pwsh trap); `da8a05e` real live-click fix; `db0ada8`/`cc3dd81` D-0128 live-click fix (STA spawn + 4096 token floor); `44692b0` D-0127 **poser SHIP + advance audit next_increment**; `9f99495` add the poser (D-0126); `626456c` D-0126 pin poser as next increment; `aa251ff` **D-0125 acceptance CORRECTED — LRAP v1 NOT phenomenological** (can't adopt the agent's role); `e826522` D-0124 scored PASS; `dbea298` D-0123 addendum; `4fd2ecc` D-0122 i45 close (LRAP ship); `6028b9c` LRAP fix pass 1. **[known]**

**TR1 — may P0-1 / action-authz be ACTIVATED now? What is frozen?** **NO.** D-0118 = **DESIGN pass only** (`p0_1_gate_status=pass`); **ACTIVATION PROHIBITED**; `non_execution:true` HOLDS; no `non_execution=false` until Nicholas licenses (s9 Blockers 3/4/6/7 + activation portions of 5/9 gate it). **Frozen = live enforcement/execution:** #43 stays a **design-only deny-by-default reference monitor** (A01–A36 + Boundary A–D); no action-capable consumer may execute from a packet. (`BOOT_PACKET` PROHIBITIONS; `SNAP:ACTION_AUTHORIZATION_CONTRACT.md`; `CONTEXT_PACKET_CONTRACT.md` §0.2.) **[known]**

**TR2 — wave concurrency clamps.** **≤1 GPU worker per wave (HARD CLAMP, ALWAYS)**; **1 GPU + 2 CPU = MaxParallel 3** validated ceiling (`modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md`); **`git` lease serialises commits**; **`docs:[]` ⇒ 0 doc contention**; model modules `parallel_safe:false` (only the GPU lane touches `models.json`); persistent llama-servers DETACHED + reaped, **0-UNMANAGED-orphan check every wave**; producer/consumer pairs across workers REQUIRE the **D-0077 fold**; **single-worker waves for core infra**. Up to **4 lanes** (GPU / CPU / coding / off-box frontier-review). (`SNAP:core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` §1/§4 "Clamps".) **[known]**

**TR3 — how a ship's landing must be verified.** `dev.ship` **fail-closed** (`exec-job.sh devship <id> <inputs.json> <timeout>` = sha256 → AST-parse → tests; named files only; trailers) → **VERIFY the real HEAD via NATIVE git, NOT the dev.ship `committed` field** (D-0072) → **orchestrator INDEPENDENT re-verify** (all SELFTEST_*_OK; e.g. i45 `87/0/0 -Live`, five-fixture 0 FP/FN) → **box clean: 0 UNMANAGED llama-server/python orphans, heartbeat `degraded:false`, leases released** → **D-0077 fold smoke** for any producer/consumer pair → **live-GUI human confirm** for UI widgets (mock/API gates miss rendered-UI defects) → core-doc mirror passes the **doc-commit-gate** (M2-A). (`SNAP:FANOUT_ORCHESTRATOR_HANDOFF.md` §"Ship a unit"/§"Verify"; `CURRENT_STATE.md` §Current tests.) **[known]**

---

## 9 RETRIEVAL LEDGER

Recording is measurement, not a limit. `seq | path-or-query | bytes | why | what it changed`

1 | `LifeOrchestrator-Refresh/.af_editor_tmp/i47eval/task-evalstage-i47.ps1` (device) | 4263 | learn how the eval folder is assembled | located eval @ `C:\Users\just_\LifeOrch-i47-eval` (outside grant); SHA `0bcb5e7`; `_bundle` source = `modules/44-project-map/eval/bundle` → chose to reconstruct in cloud
2 | query `git ls-tree -r --name-only 0bcb5e7` | ~n/a | enumerate the frozen tree, find canon paths | pinned `core-docs/AUDIT_PIPELINE.md` + all contracts in `core-docs/`
3 | `_facts/git-log.txt` = `git log -12 0bcb5e7` | ~2.4k | P6 + audit arc | revealed LRAP→poser arc; confirmed HEAD is 6 behind live
4 | `heartbeat.json` + `29-resource-lease/runtime/leases/` | ~0.4k | box-state facts | box idle, 1 durable gpu lease, 0 orphans → §1
5 | RUN `project_map.py validate` | env | STEP 0 mandate | envelope `ok`, 0 errors → map trustworthy
6 | RUN `project_map.py render --check` | env | STEP 0 mandate | envelope `ok`, 6 cards byte-match, `stale_count 0` → cards current
7 | `_bundle/generated-eval/BOOT_PACKET.md` | 12945 | retrieval protocol + frame | planes/overlay/PROHIBITIONS + owner-doc pointers → §1, TR1, P3, P5
8 | RUN `query stale` / `edges:module:42\|30\|37` / `entity:widget:08` | env | expand via map | stale `[]`; edges `[]`; widget:08 `DANGLING_REF` → recorded tooling limit; fell back to cards+log
9 | `SNAP:core-docs/AUDIT_PIPELINE.md` | 19898 | the governing next_increment | THE increment (D-0127 remaining set; design-first→red-team) + tier ladder A0–A5 + cadence → §2, §4, §6
10 | `SNAP:core-docs/DECISION_LOG_INDEX.md` (D-0087..0129) | ~tail | arcs | P0-1 arc (P4), LRAP acceptance arc, selpol pin → §2, §8
11 | `SNAP:core-docs/CONTEXT_PACKET_CONTRACT.md` | ~ | selection pin + producer/consumer | selpol_rrf_v1 pin (i31/D-0089), non_execution → P1, P5, TR1, §4
12 | `SNAP:core-docs/DECISION_LOG.md` (D-0067/D-0079 region) | ~ | warm-pool "why" | D-0079 GATE=NO verbatim + 7 blockers → P3
13 | `_bundle/generated-eval/L1_CARDS_modules.md` | 30660 | module identity/edges | #42/#40/#30 cards → P2, TR2, §4
14 | `SNAP:core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` | ~ | clamps/lanes/ship-verify/i46 candidates | TR2, TR3 + i46 front-runner → §2, §5, §6
15 | `SNAP:core-docs/CURRENT_STATE.md` | ~34k | phase/box/tests/gotchas | §1 phase + durable-supervisor default-OFF + dev.ship tests → §1, P3, TR3
16 | `SNAP:core-docs/PROCESS_BACKLOG.md` (PB-2/4/5) + `MODULE_ROADMAP.md` | ~ | PB-4 governing state + #42 wiring | confirmed next_increment machine-state + non-displacing rule + #40 as #42's live consumer → §2, P2
