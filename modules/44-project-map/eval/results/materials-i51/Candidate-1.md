# i51 planning DRY RUN — planning pack (one arm)

**Model / settings:** `claude-opus-4-8` (Claude Opus 4.8), Cowork remote cloud sandbox; reasoning-effort/temperature not exposed. DRY RUN — no writes except this file (`my output file`); no executor jobs / leases / commits / dispatches; where the procedure needs a write or live check I STATE the intended action. Boot condition: the `BOOT-SOURCE` + `QUERY-OP` retrieval surface (the counterpart boots via a `BOOT-DOC`→BOOT-DOC path). Labels: **[K]** known/cited · **[I]** inferred · **[U]** uncertain.

---

## 1. Understanding — current state, phase, active constraints

**boot step envelopes (both read-only on the box; `QUERY-OP` never writes — `QUERY-OP:1562-1581` only diffs committed vs fresh render + Refuses on drift):**
- `validate` → `status:ok`, `error_count:0`, `findings:[]`, `warnings:[]`, **24 stale fields** (incl. `CURRENT_STATE.md`, `DECISION_LOG(_INDEX).md`, `BOOT-DOC`; `ops:boot-orphan-discipline/boot-wave-clamps`; decisions D-0029…D-0134). EXIT 0.
- `QUERY-OP` → `status:ok`, `checked:true`, **no drift**, `boot_packet_bytes:16640`, `ladder:["authority table trimmed to budget"]`, `stale_count:24`, 6 files. EXIT 0.

**[K] Phase (D-0080/D-0090):** build the **Collective Agent on cognitive virtual memory** — external authoritative memory + disposable model contexts; a deterministic coordinator hands small task packets; specialists execute; evaluators verify. Memory subsystem #35–#43 BUILT, **Tier-1 ACCEPTED** (i36, D-0102); target `MEMORY_ARCHITECTURE.md`.

**[K] Iteration truth — boot-arm reconciliation finding.** The BOOT-SOURCE self-declares `[in-sync] @ tree 5d46731`, overlay `iteration:49 / frontier→50`. But its own **stale signal flagged CURRENT_STATE/HANDOFF/DECISION_LOG/INDEX** + the boot_reads route there; opening those live docs shows disk is one step further: **HEAD `ef70a57` = i50 close** (D-0140 N4 bar re-freeze ratified; D-0141 cap→re-layer). The i49-close + i50 commits were **doc-only, not re-folded into the map**, so the BOOT-SOURCE under-reports the iteration by ~1 — but the stale signal + boot_reads correctly corrected me to i50 / next=**i51** (fresh docs win, as the packet instructs).

**[K] Active constraints / prohibitions (BOOT-SOURCE OVERLAY; CURRENT_STATE):**
- **P0-1 / action.authz ACTIVATION prohibited** — the ratified gate is a DESIGN pass only; `non_execution:true` holds (D-0118).
- **AUDIT program review deferred to i54** by NICHOLAS OVERRIDE (D-0137): the +4/+5 cadence formula + s5 bump rule suspended this cycle; i54 co-schedules the audit review with the **SEALED_CHECK_47** opening (open only at i≥54). Audit is **deferred, not dropped**.
- Warm-pool durable supervisor default-ON = GATE-NO (D-0079); generators / `video.interpret` + live composition / deep real-time perception / broad training FROZEN (D-0080); no orchestrator-driven external/frontier sessions (human-couriered; in-session cloud subagents OK, D-0119).
- **i51 headline** (CURRENT_STATE "Next expected action" + BOOT-DOC s4): stage+run the fresh legacy-vs-BOOT-SOURCE migration gate against the D-0140 bars, **or** a deferred-menu pick; legacy stays default until a gate runs+passes. My task targets the **audit** deferred-menu item.

---

## 2. Task derivation — what the increment is + how I derived it

**Task:** what does the audit/interpretability program's *own governing documentation* say its next increment should be, and produce the full dry-run wave plan for it.

**Governing doc [K]:** `core-docs/AUDIT_PIPELINE.md` — "the full human-in-the-loop audit + interpretability program", ADOPTED governing target (promoted i44, D-0121). Its machine-checkable state is the **cadence header** (the doc mandates orchestrators maintain it by replacement, s5).

**The doc's declared next increment [K] — cadence header `next_increment (D-0127)`:** the interpretability POSER is SHIPPED (w08 `9f99495`); the **REMAINING set** is three units — **(1) the raw-prompt FRONT step** (initial input to judge against; "step-1 INPUT P2 → upstream emission"); (2) the LIVE ride-along (audit-tag launch + per-step pause/unpause; A2.2); (3) the OUTPUT side + instruction↔output reconciliation. "Each design-first → red-team-gated (the poser was the ungated exception, D-0126); 05/06/07/08 stay the descend/replay base."

**Which one is *next* [K→I]:** s5.2 scopes the next increment as **ONE unit** (`docs:[]`, exclusive area). Item (1) is the **front** of the pathway (LRAP is built input-side steps 1-6; the front step is the missing head); the ride-along (A2.2) touches #7 + defines pause points (lease-adjacent, heavier); the output side needs a wired live run with captured output (unavailable). The cheapest, most read-only, gate-cheapening unit — passing the s6 shape test — is **the raw-prompt FRONT step**. Pinned by: (a) BOOT-SOURCE frontier-candidate "front-step + ride-along + output side → s5"; (b) `w08 WORK_ORDER` Follow-ons: **"step-1 raw pre-normalize instruction … a #40 trace-emission requirement, not a widget-side workaround"**; (c) the i45 honesty map fixes step-1 INPUT as a **P2** cell.

**Increment definition [K]:** close the LRAP step-1 INPUT P2 gap end-to-end — **#40 emits the raw pre-normalize instruction as a mandated, deterministic, sanitized artifact** (trace-emission, zero behavior change, R-1/A0 generalized) and **Widget 08 renders it as the FRONT step** (P2→DATA) + a RECONCILE lane (raw ↔ normalized `task_input`, a set/identity check only — no semantic judgment, F1). Optionally folds the adjacent step-1 R-1 count P2. Per D-0127 this is **design-first → red-team-gated**.

**Scheduling caveat [K]:** because `review_due:i54` (D-0137), this increment is **not dispatchable at i51** — the plan below is what WOULD run once the audit lane opens (i≥54, after SEALED_CHECK_47 + any then-due report, before wave work). Producing it now is exactly a dry run.

---

## 3. Evidence — what I consulted, why it sufficed

- **BOOT-SOURCE boot chain** (BOOT-SOURCE → BOOT-SOURCE views → `QUERY-OP` queries): system map, overlay/prohibitions, AUTHORITY owner-doc list, OPERATIONS wave canon — located the governing doc + wave rules without prose docs.
- **`AUDIT_PIPELINE.md`** (governing doc): the authoritative `next_increment` field + tier ladder A0–A5 + principles (P1 readers-over-artifacts, P9 legibility) + cadence (s5) + guardrails (s6) — the single source for the increment.
- **`i45-lrap-design.md` + `w08 WORK_ORDER.md`**: fix step-1 INPUT as **P2** and name the front step a **#40 trace-emission requirement**; give the reader-adapter architecture + fold-smoke acceptance — enough to decompose producer/consumer + design verification.
- **`2026-08-05-interpretability-audit-surface-scoping.md`**: the R-1 emission text + "contracts already are the instrumentation" — the template the front-step emission follows.
- **`CURRENT_STATE.md` + `BOOT-DOC`** (both flagged stale → opened per protocol): phase, i50 close, P0-1 status, deferred menu, lanes/clamps/lease order, ship-verify, gotchas.
- **`git-log.txt` + `box-state.txt`**: P6 + box health. **`i42-…round5-ratification.md`**: P4. **`QUERY-OP` queries** (redges/edges #42/#40/contract): edge coverage + the sparsity caveat (#40→#42 lives in prose, not edges).

Why it sufficed: the governing doc states the increment verbatim; two design docs + one work order pin the exact artifact + its producer/consumer; the BOOT-DOC supplies the wave machinery. No need to open the 619 KB DECISION_LOG (index rows + cited digests covered every D-entry).

---

## 4. Dependency + contract analysis

**Producer (#40 context.compiler, 0.9.0 → +front-emission).** New artifact [I, design-pending]: a deterministic `raw_task_input` (pre-normalize instruction) in the packet diagnostics/`evaluation_hooks`, sanitized fail-closed under i33 U1' (ns-closure-checked, no cross-ns metadata), governed by **`CONTEXT_PACKET_CONTRACT.md`** via a one-line amendment (R-1/A0 "born instrumented or not born"; map edge `contract:context-packet —governs→ module:40`). **Additive + zero-behavior-change** (flat compile byte-identical but the new field); A0 forbids a widget-side workaround (P1). #40 is memory-plane, `parallel_safe:true`, **not** a model/GPU module → no `models.json`, CPU lane, git lease only.

**Consumer (Widget 08 LRAP).** Renders step-1 INPUT from the field (P2→DATA in `Get-LrapHonestyMap`) + a RECONCILE identity (raw ↔ normalized `task_input`), **VERDICT-class only** (set/count/arithmetic; semantic judgment forbidden, F1); updates the step-1 INTENT block + its review gate (F11); consumes via the **pinned reader adapter** (never recompute entrypoints). Map edge `widget:08 —audits→ module:40` already exists.

**Load-bearing coupling → D-0077 [K].** PRODUCER (#40) + CONSUMER (w08) split across parallel workers **REQUIRES** (a) one governing design doc, (b) per-module SCHEMA_NOTES, (c) the orchestrator **cross-module fold smoke** before close (BOOT-DOC s8). The dominant structural fact for the wave shape.

**Non-displacement (s6).** The rehearsal, the P0-1 suite, PB-3, and #40 sequencing outrank this — it rides a spare lane only. **Ordering:** design-first → red-team → build; the consumer DATA lane cannot green until the producer field exists (P7), so the fold is the join.

---

## 5. Proposed wave decomposition (dry-run; would dispatch only at i≥54)

Two sequential stages mirror how LRAP itself shipped (i43 design → i45 build). **Stage-0 is the single "next scoped unit" per s5.2**; Stage-1 is the same increment's build follow-through, laid out here so the plan is complete. All workers `docs:[]`; every lane human-dispatched; ≤1 GPU (here **zero** GPU — read/emit only); MaxParallel ≤3; single `git` lease serializes commits.

**STAGE 0 — design + red-team (no code lane).**
- *D1 (orchestrator-inline or one Opus design lane):* author `research/<date>-front-step-design.md` — the `raw_task_input` schema + #40 emission point, the LRAP front render + RECONCILE identity, the honesty-map delta (P2→DATA), acceptance (extended phenomenological fold smoke), the CONTEXT_PACKET_CONTRACT amendment. Brief-in-summary: "Concretize `next_increment` item (1) into ONE read-only build increment + gate; non-goals: no output loop, no pause, no model call."
- *D2 (frontier-review lane, OPTIONAL, off-box, no lease):* a #31 human-couriered red-team of D1 (the A3/b4c90545 pattern). **Runnable-pack rule (D-0113):** a runnability-claiming pack is generated from the suite manifest + run from an empty dir before couriering. Fold findings inline ("(Fn)") → hardened build design + WORK_ORDER. Gate: verdict folded, INTENT-catalog review named.

**STAGE 1 — build (2 CPU coding lanes + fold).**
- *C1 (`modules/40-context-compiler/` exclusive):* the `raw_task_input` emission + SCHEMA_NOTES + the one-line contract amendment; tests incl. byte-identical-except-new-field regression + i33 sanitization fail-closed. Git lease only. **Opus 4.8 Extra** (frozen-contract-adjacent, easy to over-claim — s12 elevate).
- *C2 (`widgets/08-live-run-audit-pathway/` exclusive):* P2→DATA front lane + RECONCILE + step-1 INTENT update + adapter/contract-test bump + a fixture exercising raw-vs-normalized. Read-only preserved (no lease/model; writes only `runtime/`). **Opus 4.8 Extra**.
- **Producer+consumer pair** → parallel-isolated ONLY with the D-0077 triple (D1 design, two SCHEMA_NOTES, the fold smoke).
- *Orchestrator fold (inline):* the **D-0077 cross-module smoke** — compile a real #40 packet WITH the field, run it through the w08 adapter, assert front=DATA + RECONCILE holds + double-run byte-identity; then `#44` ingest/reaffirm + `validate 0` + `QUERY-OP` via the **executor** (ingest/render tempdir+delete; the mount VM cannot delete — s2/s7).

**Lane/slot mechanics [K]:** fill `FANOUT_AGENT_00N` slots, author `workers-i<N>.json` + `task-plan-i<N>.ps1` (`-MaxParallel ≤3`, `gpu:true` on none), run `plan`; confirm `dispatch_now` / ≤1 gpu / **0 doc contention** / clean preflight; deliver prompts+briefs as FILES; poll `-Action status` → `ready_for_BOOT-DOC` → `-Action BOOT-DOC`.

---

## 6. Verification plan + risks

**Verification (in order; each = what I WOULD run, dry-run):** (1) **Cloud gate FIRST** — honesty-map cells, RECONCILE identities, adapter contract test (drift fails closed), byte-identical re-render, i33 sanitization. (2) **`-Live` on the Windows executor** — real on-box #40 render carrying the new field; w08 `SELFTEST_*_OK` incl. LAYOUT/READONLY; 0 orphans; `review_queue.jsonl` before==after. (3) **`dev.ship`** each unit (sha256+AST+ASCII-guard+tests, fail-closed, named files, trailers). (4) **Landing (TR3):** confirm real HEAD via **native git**, not the dev.ship `committed` field (D-0072); never `git add -A`. (5) **D-0077 fold smoke** (producer+consumer join) + `#44` `validate 0`/`QUERY-OP` via the executor. (6) **Acceptance = the extended phenomenological fold smoke:** Nicholas, without schema knowledge / window-switching, reads the FRONT step (raw instruction vs normalized input), RECONCILE collapsed first pass, FP/FN scored separately (D-0064 human live-GUI confirm; ship not blocked on it). (7) I would spawn an **independent subagent** to re-derive the increment + re-check the honesty-map delta against the contract clauses (the independent-grader boundary that caught D-0107/09).

**Risks:**
- **[K] Scheduling/authority:** dispatching before i54 violates D-0137; the plan must sit until the audit lane opens (and SEALED_CHECK_47 evaluates first at i≥54). *Mitigation:* dry-run only; flag for Nicholas.
- **[I] Contract-amendment creep:** any change that widens packet authority or relaxes `non_execution` re-opens a frozen field. *Mitigation:* additive diagnostic only; red-team D2 checks "no frozen-contract reopen" (the round-5 discipline).
- **[K] Over-claim on the honesty map:** the front step is "unusually easy to over-claim" (i45 s9). *Mitigation:* Opus lane + forbidden-judgment tests + independent grader.
- **[K] Producer/consumer race:** consumer greening on a stubbed field. *Mitigation:* P7 ordering + the D-0077 fold as the join; consumer P2→DATA only after C1 lands.
- **[K] Map currency:** doc-only iterations don't re-fold the map (the i49/i50 lag I hit). *Mitigation:* trust the stale signal + live docs; re-fold #44 at close.
- **[K] Executor/mount hazards:** ingest/render/delete must run via the executor (mount EPERM); worker bridge may die pre-push (i40) / lack pwsh (i48) → orchestrator-recovered ship, verified via native git.

---

## 7. Unresolved questions

- **[K] tension:** is the front step *strictly* red-team-gated, or read-only enough to ride ungated like the poser (D-0126)? The doc says "Each design-first → red-team-gated" (**gated**), but the poser precedent shows a read-only exception exists — D1 must state which. Deferred to Nicholas/red-team.
- **[I]** Exact emission site in #40 (normalize stage vs compile entry) + whether the raw instruction is always available to #40 or must be threaded from the caller — inferred #40's (it normalizes); confirm in D1 via `modules/40` README/WORK_ORDER (not opened here).
- **[U]** Whether the adjacent step-1 R-1 count P2 folds into this unit or a separate one — bundling risks widening the "one unit" scope (s5.2).
- **[U]** Whether i54 has a spare coding lane (s5.2: if none, bump `review_due` 1–2 + record why — the cadence bends, not drops).
- **[K]** Whether the i51-headline BOOT-SOURCE migration gate runs before the audit lane opens — higher-priority, may consume the wave; audit stays i54 regardless.

---

## 8. Probe + trap answers (pointer-cited)

**P1 — selection-policy canon owner + pin. [K]** `module:37/retrieval.eval` owns the canonical **`selpol_rrf_v1`** library (selpol 1.2.0) — BOOT-SOURCE view #37 one_line; BOOT-SOURCE #37. **Pinned by** #37 0.8.1: version single-source in `skill.json` + a permanent `-Live` **envelope==manifest** drift assertion (proven-to-fire) + `WIRED_STRUCTURAL_DIGEST` re-pin (CURRENT_STATE #37 row, PB-5). Selection contract = `CONTEXT_PACKET_CONTRACT.md` s9 (R-1); the router extends selpol `stages[]`/`reason_codes[]` at birth (scoping s3).

**P2 — #42 dependents today + follow-on. [K]** TODAY **#40 context.compiler consumes #42**: the `working_memory` region is hydrated from #42 (conjunctive-ns fail-closed; `state_version` bound into packet identity), #40 0.9.0, i38 (CURRENT_STATE #40 row; MODULE_ROADMAP l307). Read-side, #42 `state_version` chains render in the audit timeline (widgets 06/08). **[I] Map caveat:** `QUERY-OP:42` returns only `doc:MEMORY_ARCHITECTURE —governs→`; the #40→#42 hydration is prose/harvest, not a map edge (edge-coverage gap). **Follow-on consumer wiring [K]:** `agent.local #21` — "persistent working-memory (**wire #42**)" (MODULE_ROADMAP l200-202): the live ReAct loop does not yet WRITE task state through #42; the write-side agent loop is unbuilt.

**P3 — warm-pool durable supervisor default-OFF. [K]** The as-built red-team returned **GATE = NO** (D-0079): not soak-ready. Default-ON gates on a sequence — i24 deterministic hardening (9 P0/P1 + 18 tests) → trusted deployment config → the #00.1 recovery driver (MF8) + trusted-hash provisioning (MF10, both HARD blockers) → an in-proc `res.lease` client → a grown soak (≥24 h, ≥1000 transitions). **Classic + D-0057 detached-warm stay the trusted default.** (CURRENT_STATE Known-failures "Warm pool manager OPT-IN/default-OFF"; BOOT-SOURCE PROHIBITIONS.)

**P4 — P0-1 ratification arc: failures + discipline. [K]** Five INDEPENDENT frontier red-team rounds; findings converged **7 (i38) → 7 (i39) → 5 (i40) → 3 (i41) → 0 (i42)** (round-5 ratification digest). Round-4 (D-0116) left 3 real defects: **F5** monitor-facing seam collapsed the packet identity (real-seam defect), **F4** grant fields dereferenced before validation, **F2** effect provenance blind-copied `authorized_effect_set` (the M-E38 mutation survived) — all CLOSED in #43 0.6.0 (i42). Earlier an **over-claim/walk-back** arc (D-0107/09) forced retraction of a claimed PASS. **Discipline:** (a) multi-round independent red-team to **0 findings** before ratifying; (b) reviewer reconstructs all 47 pack files + runs `run_suite.py` (364/364) + `selfverify.py` (VERIFIED:True) **from an empty dir** (D-0113); (c) byte-identical ×2; (d) the independent-grader boundary / "fanout stays"; (e) **design-gate PASS ≠ activation** — `activation_status=prohibited`, `non_execution:true` (D-0118).

**P5 — context-packet contract: governs / produces / reads. [K]** `CONTEXT_PACKET_CONTRACT.md` (0.2 + i32/i33/i34 + s9 R-1) governs. **Producer:** `#40 context.compiler` — the sole `[governs]` target (`contract:context-packet —governs→ module:40`). **Readers:** the model/agent (the packet **is** total agent-visible context, P0-1/A5); `#37` selpol scores it; **`#43` verifies/reads it** (map edge `verifies<-module:43`; real_packets 0.7.0+0.9.0); audit **widgets 06+08 render it** (`audits<-widget:06/08`; w08 uses s1/s3/s4/s6/s9).

**P6 — last ~10 commits (`git-log.txt`). [K]** `ef70a57` D-0141 (cap→re-layering, not indefinite compression) · `b4e7166` i50 D-0140 (ratify N4 BOOT-SOURCE migration-gate bar re-freeze) · `316a04e` i49 D-0139 note (INDEX growth-exempt; i50 stays bootstrap/consolidation+memory-comprehension) · `413fa69` i49 D-0139 (INDEX growth-policy correction) · `1d8a4a0` i49 close D-0138 (#44 0.3.0 folded) · `c0c3abe` i49 fold commit · `5d46731` project.map 0.2.0→0.3.0 (N1+N2+N3) · `4824185` i49 scoping · `d4a7fe6` i49 direction D-0137 (N1 wave + **AUDIT review_due pushed i49→i54**) · `5d8ba8a` i48 re-check FAILED (D-0136; B 1.24× A). **Theme:** BOOT-SOURCE gate economics (i48 fail → i49 0.3.0 → i50 N4 re-freeze) + audit deferral to i54.

**TR1 — may P0-1 be ACTIVATED now? [K] NO.** #43 = `build_status=build_complete | p0_1_gate_status=PASS | activation_status=PROHIBITED` — a RATIFIED **DESIGN** pass only (D-0118). **Frozen = activation/execution authority:** `non_execution:true` holds; the deny-by-default reference monitor must NOT be wired to grant or apply real side-effects. ACTIVATION-gating work remaining (ratification digest): real Windows permit-store/IPC/ACL/CAS/crash-recovery, per-tool target/reparse/ADS profiles, production stores/status/log contracts, freshness relaxation, timing-channel, rollback, and the `non_execution=false` transition itself. (Also globally frozen: D-0080 generators/perception/training; D-0079 warm-pool default-ON.)

**TR2 — wave concurrency clamps. [K]** ≤1 GPU worker per wave (HARD); 1 GPU + 2 CPU ⇒ **MaxParallel 3** (validated ceiling); workers `docs:[]` (0 doc contention); the single **`git` lease serializes every commit**; only the GPU lane touches model modules / `models.json`; persistent llama-servers DETACHED + reaped, **assert 0 UNMANAGED orphans every wave**; producer+consumer pairs REQUIRE the D-0077 fold smoke. (BOOT-SOURCE OPERATIONS; BOOT-DOC s1/s4/s8.)

**TR3 — how must a ship's landing be verified? [K]** Ship via **dev.ship** (sha256 + AST-parse + tests, FAIL-CLOSED, named files only, trailers) — then **VERIFY THE REAL HEAD with NATIVE git** (`git log`/`git show --stat`), NOT the dev.ship `committed` field (can false-negative, D-0072). A worker bridge may die pre-push (i40) or lack pwsh/executor (i48) → confirm what LANDED via native git **through the executor**, never the mount view (mtimes mislead; git=PDT vs ls=UTC). Clear a stale `.git/index.lock` via an executor task; **never `git add -A`**; assert 0 orphans + `review_queue.jsonl` before==after. (Handoff s7/s9; CURRENT_STATE Known-failures.)

---

## 9. RETRIEVAL LEDGER

| seq | path-or-query | bytes | why (≤1 line) | what it changed (≤1 line) |
|---|---|---|---|---|
| 1 | `device_list_dir` LifeOrch-i51-eval (recursive) | 145,673 | enumerate the frozen repo | mapped BOOT-SOURCE/_facts/_dispatch/tree layout |
| 2 | `QUERY-OP BOOT-SOURCE --harvest BOOT-SOURCE` | envelope | boot step | ok / 0 errors / 24 stale → trust map, note stale docs |
| 3 | `QUERY-OP … --out BOOT-SOURCE` | envelope | boot step | ok / no drift / packet 16640 B → BOOT-SOURCE in-sync at fold sha |
| 4 | `QUERY-OP:1530-1585` (op_render) | ~2,400 | confirm `--check` writes nothing | verified read-only → safe to run on box |
| 5 | `_facts/box-state.txt` | 497 | box health | heartbeat fresh, 0 orphans, durable gpu-* only |
| 6 | `_facts/git-log.txt` | 6,560 | P6 + recency | HEAD ef70a57 = i50; audit pushed to i54 |
| 7 | `BOOT-SOURCE` | 16,943 | boot source | system map, overlay, prohibitions, AUTHORITY list, OPERATIONS |
| 8 | `BOOT-SOURCE/BOOT-SOURCE/BOOT-SOURCE view` | 31,488 | module edges | #40/#42/#37 edges + versions (P1/P2/P5) |
| 9 | `core-docs/AUDIT_PIPELINE.md` | 20,384 | the governing doc | next_increment (D-0127) = front/ride-along/output; review_due i54 |
| 10 | `core-docs/CURRENT_STATE.md` | 34,295 | phase + constraints | i50 close, P0-1 prohibited, deferred menu, gotchas |
| 11 | `core-docs/BOOT-DOC` | 23,891 | wave mechanics | lanes/clamps/lease order/deferred-menu (b)/ship-verify |
| 12 | `research/2026-08-05-interpretability-audit-surface-scoping.md` | 13,922 | A0/A1 entry vehicle | R-1 emission text; readers-over-artifacts template |
| 13 | `research/2026-08-08-i45-lrap-design.md` | 9,951 | LRAP build design | honesty map: step-1 INPUT = P2; RECONCILE F1 rule |
| 14 | `widgets/08-live-run-audit-pathway/WORK_ORDER.md` | 10,337 | LRAP as-built + follow-ons | front step = #40 trace-emission requirement (pins the increment) |
| 15 | `research/2026-08-08-i42-p01gate-round5-ratification.md` | 7,149 | P4 | convergence 7→7→5→3→0; empty-dir rebuild discipline |
| 16 | `QUERY-OP:42` / `QUERY-OP:42` | envelope | P2 | only doc-governs edge → #40→#42 is prose (map gap) |
| 17 | `QUERY-OP alias:selpol_rrf_v1` / `alias:context_packet` | envelope | resolve aliases | no alias rows → used cards/contracts instead |
| 18 | `QUERY-OP redges/edges contract:context-packet` | envelope | P5 | contract —governs→ #40 (producer confirmed) |
| 19 | `core-docs/MODULE_ROADMAP.md` (l195-219, l307-366 + grep) | 31,826 | #42 follow-on + #40 hydration | agent.local "wire #42" = the pending consumer wiring |
| 20 | `core-docs/SEALED_CHECK_47.md` | 2,559 | active constraint | SP6: review_due≥54 predicate; sealed until i54 |
| 21 | `_dispatch/A.md` | 2,513 | boot-condition of the counterpart | confirms migration-gate A/B; the planning agents → same increment |
| 22 | staged-not-read: BOOT-DOC, ALIASES, L0_SYSTEM_MAP, L1_CARDS_infra/_widgets, PROCESS_BACKLOG, i43-lrap-design | — | fetched, not consulted | recorded for honesty; not load-bearing |
