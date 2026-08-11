# B_PACK -- i48 CD-2 dry run (Agent B)

**Runtime:** model `claude-opus-4-8` (Claude Opus 4.8), Cowork cloud sandbox session; extended-thinking / high reasoning effort; **DRY RUN** posture (non-executing). No writes anywhere except this file (`_out/B_PACK.md`); no executor jobs, leases, commits, or dispatches were issued. Where the procedure calls for a live write/check, I STATE the would-do instead.

**STEP 0 envelopes (run in a Linux shell over a `/tmp` copy of `_bundle`; source is read-only).**
- `validate --map _bundle/map-eval --harvest _bundle/harvest-eval.json` → `status: ok`, `result.ok: true`, `error_count 0`, findings/warnings/stale all empty. (`skill project.map 0.2.0`, contract 0.2.)
- `render --check --map _bundle/map-eval --harvest _bundle/harvest-eval.json --out _bundle/generated-eval` → **first run** `status: error`, `GENERATED_DRIFT @ BOOT_PACKET.md "missing committed file"` — a **staging artifact** (I had not yet staged `generated-eval/BOOT_PACKET.md`), not real drift. After staging that one file, **re-run → `status: ok`, `checked: true`, 6 files with sha256, `stale_count 0`, `boot_packet_bytes 14908`, ladder `["authority table trimmed to budget"]`.** A refusal is a reportable result: the drift code fired correctly on an incomplete tree, which is itself a validation that `render --check` is fail-closed.

---

## 1 Understanding (current state, phase, active constraints)

**Phase (known, D-0080):** building the Collective Agent on cognitive virtual memory. Overlay = **iteration 48**; the memory subsystem #35–#43 is BUILT and **Tier-1 ACCEPTED** (i36, D-0102; `tier1_accepted=TRUE`, 11/11 s10 over a foreign corpus). i47 sunset mandate-02 (verdict YES; `SEALED_CHECK_47` armed, open i≥54); the i47 legacy-vs-PCB migration gate = **CONDITIONAL** (D-0133) — the legacy handoff stays the default bootstrap. i48 shipped the CD-1/CD-3 closures (`project.map` 0.2.0) + the harvest mandate-absence fix (D-0135). [BOOT_PACKET OVERLAY; core-docs/CURRENT_STATE.md §Phase, l.24–32.]

**Immediate frontier (known):** the FIRST work of the next session is the i48 **CONDITIONAL re-check** — (1) CD-1 probe-only dry-run at frozen `EVAL_SHA_2` (= HEAD `2fc483f`), then (2) CD-2 A/B efficiency re-run under the frozen `I47_EVAL_PACKET` s7 mechanics — **before any new wave.** #40 beam-width is on the **deferred menu (D-0134): "(d) #40 beam-WIDTH"**, explicitly **NON-DISPLACING** (gate ratification, M2-A, core-memory sequencing outrank it). [FANOUT_ORCHESTRATOR_HANDOFF.md §4, l.53–61; CURRENT_STATE.md l.360.]

**Active constraints (known, live prohibitions):** P0-1/action-authz **ACTIVATION prohibited**, `non_execution:true` (D-0118); warm-pool durable supervisor default-ON is **GATE-NO** (D-0079); generator/perception/training **FROZEN** (D-0080); no orchestrator-driven frontier AI (D-0119, in-session cloud subagents permitted); `SEALED_CHECK_47` evaluated **only at i≥54** (D-0132). Box healthy: heartbeat `degraded:false`, 1 active task, durable `gpu-e3c5ba51` lease sibling present, **0 UNMANAGED orphans** (`_facts/box-state.txt`).

## 2 Task derivation (what the increment is + how I derived it)

**The increment = the `#40` (context.compile) BEAM-WIDTH lever** — widen the shortlist beam `B` (nodes/level) in the shortlist-and-descend plan so **upper-level recall** recovers the residual scale gap that #36 0.7.0 fast-beam left, ADDITIVE over `context_packet/0.2` (schema string UNCHANGED), module semver **0.9.0 → 0.10.0**, default byte-identical, SAFE-PRUNING [P0] and the `O(B·D)` sub-linear nav-cost bound preserved.

**Derivation chain (known, triple-confirmed):**
1. **"i39's ranking ship"** = #36 artifact.search **0.7.0** — the **FAST-BEAM RECALL LEVER** (i39, D-0107 follow-on; RANKING-ONLY, no migration, `schema_version` stays 5; hpr 58823→117647 ppm; flat byte-identical). [harvest module 36 `purpose`; CURRENT_STATE.md tests table l.240.]
2. **The residual after it:** #36's own purpose states "the residual scale gap is **upper-level Bloom saturation over a shared vocabulary** — a bounded-synopsis limit **whose remaining lever is #40's beam width**." [harvest module 36 `purpose`.]
3. **The named follow-on:** MODULE_ROADMAP #36 → "upper-level Bloom saturation is **#40-beam-width-bound (a #40 follow-on, NOT #36)**"; MODULE_ROADMAP #40 follow-ons → "**beam WIDTH (the fast-beam residual scale lever — Lane B i39 measured upper-level Bloom saturation)**." [MODULE_ROADMAP.md l.281–282, l.309–310.] The handoff/CURRENT_STATE deferred menus name it "**#40 beam-width**" (D-0134).

So the lever is **consumer-side (#40), not #36** — #36 fast-beam already ships the wider shortlist surface; the unspent lever is how wide #40's plan descends over it.

## 3 Evidence (what I consulted, why it sufficed)

I booted from the PCB (BOOT_PACKET → L1 cards → map `query` on #36/#37/#40/#42 → `edges/redges`), then read the authoritative per-module narratives in `harvest-eval.json` (the fast-beam sentence + the descend/prune plan), then the governing core-docs: **MODULE_ROADMAP** (the follow-on menu — the naming source), **CONTEXT_PACKET_CONTRACT** + **MEMORY_ARCHITECTURE** (the `context_packet/0.2` descend contract, SAFE-PRUNING [P0], the `B` nodes/level + `D` depth bound, the Tier ladder), **FANOUT_ORCHESTRATOR_HANDOFF** (wave canon + deferred menu + recovery discipline), **DECISION_LOG_INDEX** (the D-pins), and `_facts/` (git-log for P6, box-state for orphans/leases). This sufficed because the follow-on is **triple-confirmed** across three independent docs, the wave mechanics are fully specified in the handoff + BOOT_PACKET OPERATIONS, and the ordering/licensing constraints are explicit in CURRENT_STATE + the handoff. I did **not** open the 597 KB DECISION_LOG (the 20 KB INDEX carries the routing rows) — a bounded-read discipline, not a gap.

## 4 Dependency + contract analysis

- **Producer:** #40 context.compile emits the widened-beam descend plan + additive metrics. **Consumer/measurer:** #37 retrieval.eval drives #40's public wired-descend port READ-ONLY (op `rehearsal`) and scores it. → a **schema producer+consumer pair across parallel workers → D-0077 fold smoke REQUIRED at fold before close.** [FANOUT_ORCHESTRATOR_HANDOFF s6/s7; CONTEXT_PACKET_CONTRACT l.132 "Applies-to: #40 (V1–V5, import #37 READ-ONLY), #37 (the eval measures + fixtures)".]
- **Governing contracts (map `redges:#40`):** `contract:context-packet -[governs]-> #40`; `MEMORY_ARCHITECTURE -[governs]-> #40`; `#43 action-authz -[verifies]-> #40`; audited by widgets/06 + widgets/08. `context_packet/0.2` is the frozen packet schema — the change is **additive within 0.2**, string UNCHANGED (the established pattern of every prior #40 minor bump).
- **Selection canon (unchanged):** `selpol_rrf_v1` is **owned by #37, imported READ-ONLY by #40**, PINNED by **D-0089** (CONTEXT_PACKET_CONTRACT s4 / P1-1). The beam-width lever must NOT touch selpol — it changes only *how many upper-level nodes reach* the existing selpol/budget/packet path.
- **#36 (imported READ-ONLY):** fast-beam is DONE (0.7.0); the lever is #40-side. **Uncertain:** whether #36's current shortlist op exposes enough breadth or needs a bounded param/fold-reconciliation seam (see §7).
- **Invariants that must survive:** SAFE-PRUNING [P0] no-false-negative certificate at the pinned snapshot; the `O(B·D)` sub-linear nav-cost bound (the whole Tier-1 bounded-context guarantee); `guaranteed`+`packet` recall stay 1,000,000 ppm; `effective_allowed_namespaces` (i33 intersection) + `hierarchy_version` + pinned `corpus_version` still passed to shortlist/descend. [CONTEXT_PACKET_CONTRACT l.105–131; MEMORY_ARCHITECTURE §Tier-1 l.279.]

## 5 Proposed wave decomposition (units, lanes, briefs-in-summary)

**Wave shape: CPU-only** (the whole memory substrate is deterministic, no model / CUDA / network) → **no GPU lane**; **MaxParallel 2** (2 CPU), inside the ≤1-GPU / MaxParallel-3 clamp. `git` lease serialises commits; workers run `docs:[]`; orchestrator mirrors core-docs under the `git` lease. *(Dry run — I would author `workers-i<N>.json` + copy `task-plan-i48.ps1` with `-MaxParallel 2`, no `gpu:true` worker; I do not run `plan`.)*

- **Unit-0 (design, single-owner, precedes fan-out):** author the beam-width design note (target `B`, the config cap, the SAFE-PRUNING re-proof obligation, the additive-metric list) into MEMORY_ARCHITECTURE / CONTEXT_PACKET_CONTRACT as the ONE governing design doc the D-0077 pair shares. Red-team the nav-cost/pruning claim design-first (the P0-1 lesson: design before build).
- **Lane C (coding) — #40 0.9.0→0.10.0:** add the beam-width parameter to the shortlist-and-descend plan; gate it (a caller not requesting the wider beam gets 0.9.0 metrics **byte-identical**, regression-proven); assert `O(B·D)` bound + SAFE-PRUNING no-false-negative; emit additive `beam_width`/nav-cost stage-trace fields; `context_packet` stays 0.2. Ship via dev.ship; `docs:[]`.
- **Lane B (CPU) — #37 retrieval.eval:** extend the rehearsal/A-B to MEASURE wider-beam vs current-beam **recall uplift/regression** (navigation-cost across ≥2 orders of magnitude; dual-recall; integer-only ppm, byte-identical on re-run); **re-pin `WIRED_STRUCTURAL_DIGEST`** iff the wired structure legitimately moves (the i39 / PB-5 pattern); keep `tier1_accepted` HARNESS-COMPUTED. `docs:[]`.
- **Optional frontier-review lane (off-box, human-couriered #31 pack, no lease):** an AS-BUILT red-team of the SAFE-PRUNING + recall-pass claim, generated from the suite's own required-file manifest and run from an empty dir before couriering (D-0113). Justified by the P0-1 over-claim history.

## 6 Verification plan + risks

**Verification (dry-run — I STATE, I do not run):**
- Ship each unit via `exec-job.sh devship` (sha256 + AST-parse + tests, FAIL-CLOSED, named files only, trailers); then **VERIFY the real HEAD with NATIVE git**, never the dev.ship `committed` field (D-0072); **never `git add -A`**.
- **D-0077 cross-module fold smoke** (#40 producer + #37 measurer) over a real multi-namespace tree BEFORE close: SAFE-PRUNING holds end-to-end, recall uplift measured, flat/no-beam compile byte-identical to 0.9.0.
- #37 A/B gate: hierarchy_path_recall RISES; `guaranteed`+`packet` recall stay 1,000,000 ppm; re-run the ~200 MB foreign-corpus rehearsal — a wider beam must NOT drop `tier1_accepted`.
- Independent orchestrator re-verify before ship (the ORCHESTRATOR-RECOVERED pattern) + the as-built frontier re-review; **do not over-claim** the pass. Orphan check 0 UNMANAGED (CPU-only → no llama-servers); doc-gate on every core-doc mirror (MEMORY_ARCHITECTURE is grandfathered-over-budget → a >40 KB touch takes a **re-layer plan (FO-3)**, not another slim; PB-3).

**Risks:** (1) widening `B` erodes the bounded-context `O(B·D)` guarantee → cap `B`, measure nav-cost across ≥2 OOM. (2) SAFE-PRUNING regression = a false-negative recall miss → the no-false-negative certificate must be re-proven, fail-closed. (3) **Over-claim** (the D-0106/07/08/09 arc) — synthetic uplift ≠ acceptance; the foreign-corpus rehearsal + as-built re-review gate it. (4) `WIRED_STRUCTURAL_DIGEST` churn → a mechanical, fail-loud #37 re-pin. (5) **Ordering** — the lever is DEFERRED + NON-DISPLACING; a live dispatch is gated behind the i48 CD re-check and core-memory sequencing.

## 7 Unresolved questions (known / inferred / uncertain)

- **Target beam width `B` and its cap — UNCERTAIN.** Not pinned in any doc; a unit-0 design + measurement question.
- **#40-only vs a #36 seam — INFERRED #40-only** (roadmap: "a #40 follow-on, NOT #36"); **UNCERTAIN** whether #36's current shortlist op surfaces enough breadth or needs a bounded param / fold-reconciliation seam.
- **Packet schema — INFERRED additive, `context_packet` stays 0.2** (every prior #40 minor bump was additive); **UNCERTAIN** until designed.
- **Timing — KNOWN deferred + non-displacing (D-0134);** **UNCERTAIN** when a spare CPU/coding lane frees after the i48 re-check + any licensed migration unit (FO-2) at i49.
- **Iteration number — INFERRED "i49-or-later"**, not i49-guaranteed (the CD re-check + a possible migration unit have first claim).

## 8 Probe + trap answers (pointer-cited into `tree\`)

- **P1 — selection-policy canon owner + pin (KNOWN).** #37 retrieval.eval **owns** the one versioned deterministic library `selpol_rrf_v1` (`modules/37-retrieval-eval/lib/selpol_rrf_v1.py`); **pinned by D-0089** (context.compiler must IMPORT it, its `selpol_reference.py` stub retired). [core-docs/CONTEXT_PACKET_CONTRACT.md s4 l.33–36; DECISION_LOG_INDEX.md D-0089; map `entity:#37`.] Consumed READ-ONLY by #40.
- **P2 — what depends on #42 today + the follow-on wiring (KNOWN + one UNCERTAIN in map).** Today **#40 context.compile** hydrates the packet `working_memory` region from #42's per-task store (i38, #40 0.9.0). The still-open **consumer-wiring follow-on = #21 agent.local** ("#21 consumer wiring; promote-to-durable flows; retention policy"). [MODULE_ROADMAP.md #42 follow-ons l.319; CURRENT_STATE.md l.26, l.244.] **Uncertain-in-map:** `redges:#42` returns only `MEMORY_ARCHITECTURE -[governs]-> #42` — the #40↔#42 hydration is in the module narrative, not a typed map edge.
- **P3 — warm-pool durable supervisor default-OFF (KNOWN).** The supervisor red-team **blocked default-on** and expanded the required hardening sequence (**D-0079**); classic detached-warm stays the trusted default. [BOOT_PACKET PROHIBITIONS; DECISION_LOG_INDEX.md D-0078/D-0079; CURRENT_STATE.md l.75 / §Known failures, WARM_POOL_DESIGN §6/9/10.]
- **P4 — the P0-1 ratification arc + the discipline (KNOWN).** A repeated **pass-over-claimed → walked-back** loop: D-0106 ratifies the i38 pass → **D-0107** AS-BUILT re-review FAIL, walked back (7 items → i39) → D-0108 claims an HONEST i39 pass → **D-0109** as-built re-review FAIL **again**, walked back (7 → i40) → resolved at **D-0118** (i42 round-5 = **DESIGN PASS**, activation still prohibited; arc closes 7→7→5→3→0). **Discipline:** an independent AS-BUILT re-review gates every pass claim; a ratified gate is DESIGN-only with `non_execution:true`; ship only after independent verification. [DECISION_LOG_INDEX.md D-0106/07/08/09/18; FANOUT_ORCHESTRATOR_HANDOFF.md s3 l.39.]
- **P5 — the context-packet contract, producer/reader (KNOWN).** `core-docs/CONTEXT_PACKET_CONTRACT.md` governs `context_packet/0.2`. **Producer = #40 context.compile** (sole; `contract:context-packet -[governs]-> #40`). **Readers:** the action-capable consumer (executor/agent — but `non_execution:true`, so no execution from a packet); **audited** by widgets/06 + widgets/08; **verified** by #43 action-authz. Selection inside it is owned by #37 (imported). [CONTEXT_PACKET_CONTRACT.md s0/s2/s4; map `redges:#40`.]
- **P6 — last ~10 commits at this tree (KNOWN, `_facts/git-log.txt`).** `2fc483f` i48 fold (map+generated, D-0135) ← `24347fe` i48 docs close ← `4055dc1` harvest sunset-fix ← `c451890` project.map 0.2.0 CD-1+CD-3 (recovered ship) ← `f1de00c` i48 scoping ← `c98e797` i47 addendum (D-0134 Nicholas rulings) ← `5692de0` i47 close (migration gate CONDITIONAL, D-0133) ← `53c211f` i47 sunset (mandate-02 SUNSET + SEALED_CHECK_47 armed, D-0132) ← `b2aca12` i46 final close ← `fea1fd9` i46 docs close ← `11416a8` project.map 0.1.0 ← `b4ce6ab` i46 claims. **HEAD `2fc483f` = EVAL_SHA_2.**
- **TR1 — may P0-1 / action-authz be ACTIVATED now? NO (KNOWN).** D-0118 ratified a **DESIGN PASS only**; activation is **PROHIBITED**, `non_execution:true` holds. **Frozen =** `core-docs/ACTION_AUTHORIZATION_CONTRACT.md` (FROZEN, D-0103) — the A01–A36 + Boundary A–D registry #43 is built to; #43 is design-only (deny-by-default reference monitor), no enforcement wired into any consumer. [BOOT_PACKET PROHIBITIONS; DECISION_LOG_INDEX.md D-0118/D-0103; map `entity:#43`.]
- **TR2 — wave concurrency clamps (KNOWN).** **≤1 GPU worker HARD**; **1 GPU + 2 CPU ⇒ MaxParallel 3** (validated ceiling); workers run **`docs:[]`** (doc contention 0); the single **`git` lease serialises** every commit. [BOOT_PACKET OPERATIONS "Wave clamps"; FANOUT_ORCHESTRATOR_HANDOFF.md s6 l.63; modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md.]
- **TR3 — how a ship's landing must be verified (KNOWN).** Ship via **dev.ship** (`exec-job.sh devship`: sha256 → AST-parse → tests, **FAIL-CLOSED**, named files only, trailers); then **VERIFY the real HEAD with NATIVE git**, NOT the dev.ship `committed` field (**D-0072**); **never `git add -A`**; executor-only git writes. [BOOT_PACKET OPERATIONS "Ship via dev.ship"; FANOUT_ORCHESTRATOR_HANDOFF.md s6/s8; ops:boot-ship-verify.]

## 9 RETRIEVAL LEDGER

Recording is measurement, not a budget. One row per document/file/query opened or run.

| seq | path-or-query | bytes | why (≤1 line) | what it changed (≤1 line) |
|---|---|---|---|---|
| 1 | `_dispatch/B.md` | 3013 | the task + hard rules | fixed the increment target + dry-run constraints |
| 2 | run `project_map.py validate --map map-eval --harvest` | — | STEP 0 gate 1 | envelope `ok`, 0 findings — map trusted |
| 3 | run `project_map.py render --check --out generated-eval` | — | STEP 0 gate 2 | first `GENERATED_DRIFT` (staging artifact) → after staging BOOT_PACKET, `ok`, 6 files, stale 0 |
| 4 | `_bundle/BOOT_PACKET.md` | 15111 | boot source | planes/overlay/prohibitions/OPERATIONS/frontier |
| 5 | `_bundle/tool/project_map.py` (grep query verbs) | 90116 | learn the closed query set | entity/edges/redges/evidence/deeper/alias/stale |
| 6 | grep `map-eval/entities/*` (scale/rank/follow-on) | — | locate the ranking entities | pointed to #36/#37 + arch:23 |
| 7 | `query entity:#36` | — | artifact.search authority record | retrieval core; realizes arch:23 |
| 8 | `query entity:#37` | — | retrieval.eval authority record | selpol owner + benchmark |
| 9 | `map-eval/entities/arch-positions.json` (arch:23/27/30) | 82474 | the arch position for retrieval | arch:23 = embeddings + reranker |
| 10 | `generated-eval/L1_CARDS_modules.md` (#35–#43) | 31388 | L1 cards, memory plane | module versions/edges/status |
| 11 | `harvest-eval.json` module 36 `purpose` | 478784 | fast-beam ship + residual gap | i39 D-0107 fast-beam; residual = **#40 beam width** |
| 12 | `harvest-eval.json` module 37 `purpose` | (^) | selpol pin + eval measures | D-0089 pin; #37 re-pin = PB-5; P1-2/P1-4 |
| 13 | `harvest-eval.json` module 40 `purpose` | (^) | the descend/beam/synopsis plan | `B` nodes/level; SAFE-PRUNING; imports #37 R-O |
| 14 | `harvest-eval.json` module 39 `purpose` | (^) | episode/failure seam | P2/P4 context |
| 15 | `_facts/git-log.txt` | 9981 | P6 last commits | i48 fold; CD closures; HEAD=EVAL_SHA_2 |
| 16 | `_facts/box-state.txt` | 433 | box state | heartbeat ok; gpu lease sibling; 0 orphans |
| 17 | `core-docs/MODULE_ROADMAP.md` | 31826 | the follow-on menu (naming source) | named it: **#40 beam-WIDTH, a #40 follow-on NOT #36** |
| 18 | `core-docs/PROCESS_BACKLOG.md` | 4826 | confirm beam-width ≠ a PB item | it is a per-module follow-on |
| 19 | `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` | 23891 | wave canon + deferred menu | clamps/lease/ship-verify/fold; "(d) #40 beam-WIDTH" |
| 20 | `core-docs/MEMORY_ARCHITECTURE.md` | 30427 | Tier ladder + bounded-fanout hierarchy | beam is a Tier-1 refinement; PB-3 grandfathered |
| 21 | `core-docs/CONTEXT_PACKET_CONTRACT.md` | 35121 | packet producer/reader + descend contract | #40 produces; selpol D-0089 pin; `B`/`D`; SAFE-PRUNING |
| 22 | `query redges:#42, edges/redges:#40, redges:#36, edges:contract:context-packet` | — | dependency edges | #40 governed by contract+MEM_ARCH; #42 map lacks the #40↔#42 edge |
| 23 | `core-docs/DECISION_LOG_INDEX.md` | 19996 | the D-pins | D-0079/0089/0104/0106/0107/0108/0109/0118 rows |
