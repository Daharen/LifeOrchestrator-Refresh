# FAN-OUT ORCHESTRATOR HANDOFF

**This is the ONE live handoff doc.** It is rewritten IN PLACE at the end of every orchestrator session
(snapshot the outgoing version to `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF-<tag>.md` first --
`DOC_PROTOCOL.md` section 5). Dated `ORCHESTRATOR_HANDOFF_*.md` docs are retired; their content lives here, in
`CURRENT_STATE.md`, and in `archive/handoffs/`.

**You are the fan-out orchestrator** -- the ONE Claude instance that scopes work units, drives
`orchestrate.fanout` (#30) to emit worker prompts, and hands them to Nicholas, who dispatches each into a FRESH
Cowork session. You NEVER drive another AI session (the hard D-0051 boundary) -- every lane is human-dispatched,
including the frontier lane (a human-couriered pack, not a driven session).

## 0. TL;DR

- **DIRECTION RESET (D-0080): build the Collective Agent (cognitive virtual memory).** On
  Nicholas's directive the project pivots to the memory / retrieval / context / skill-activation substrate;
  supervisor/warm-pool hardening (D-0079 GATE-NO), generators, `video.interpret`, real-time perception + broad
  training are FROZEN. **NEXT = Wave 1** (section 4): embedding adapter + `artifact.search` MVP + retrieval-eval
  harness (+ optional memory red-team) -- **SHIPPED + FOLDED (i25, D-0082); the retrieval-record/provenance CONTRACT FREEZE is DONE (i26, D-0083 -- `core-docs/MEMORY_CONTRACT.md`: record-envelope v0.1 + embedding 0.2 + retriever 0.2 + catalog/eval/privacy gates). Wave 2 (memory RECORDS) is SHIPPED + FOLDED (i27, D-0084): #36 artifact.search 0.2 + NEW #38 repo.intel + NEW #39 episode.record; the D-0077 fold smoke PASSED (2 divergences bridged). **i28 (D-0085) SETTLED the contract: MEMORY_CONTRACT Amendment A1 (record-envelope v0.1 -> v0.1.1 -- envelope status = a single s5 STRING; `record_kind` enum CLOSED, `episode_stage` retired) + episode.record #39 -> 0.1.1; the D-0077 re-smoke PASSED 30/30 (0 bridging, 0 rejections) -- the two i27 divergences RESOLVED. **Wave 3 (context compiler + skill retrieval) SHIPPED + FOLDED (i29, D-0086, plan fo-29-87dbfa0b): NEW context.compiler #40 (`lifeorch.context_packet/0.1`) + retrieval.eval #37 0.2 + a deterministic reranker + NEW skill.card #41; the D-0077 fold smoke PASSED on real data; the frontier design red-team (pack d57fead3) FOLDED -- GO for the read-only build, NO-GO for FREEZING the new contracts, NO-GO for side-effecting until the SAFETY-CRITICAL P0-1 (control-plane-vs-evidence separation). NEXT = i30 CONTRACT-HARDENING (P0-1..P0-5 + P1-1).** Directive:
  `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`.
- Read section 2 (orient + verify the box), CONTINUE **iteration 32** (Tier-0 seam repairs). **i32 IN FLIGHT (D-0092): PART 1 (contracts) COMMITTED (`b8c9a3d`) + mirrored -- MEMORY_CONTRACT A4 + CONTEXT_PACKET_CONTRACT i32 amendment (U1 namespace-HARD boundary; U4 current_only mode + supersession-aware ranking + `contradicts` edge; U2/U3 reserved `node`/`working` kinds + `member_of_node`/`child_of_node` edges; U5 frozen-open channels + query-classification seam; budgets 24->28 / 22->25 KB). PART 2 the 3-lane CPU conformance wave (#36 0.2->0.3, #37 selpol 1.0->1.1 + eval 0.3->0.4, #40 0.3->0.4; plan `fo-32-0fb25203`, dispatch_now 3) COMPLETE -- all 3 workers shipped DONE (#36 `ef667f7` [gate tests 1+2], #37 selpol_rrf_v1 1.1.0 + eval 0.4 `26224d7`, #40 `31ebdf7`; gates green; #40's selpol-1.1.0 integration + -Live DEFERRED to the fold), slots 001/002/003 READY; frontier Tier-0 red-team pack `159e9cb5` out. NEXT = **i33 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING** -- the frontier Tier-0 red-team (pack `159e9cb5`, D-0095, digest `research/2026-08-04-tier0-amendment-redteam.md`) FOLDED **NO-GO to close i32 as-written**: U1 namespace is only an ENVELOPE filter (SAFETY-CRITICAL isolation defect -- derived-record laundering, diagnostic/omission metadata leak, per-hop + working-state gaps, task_input wrongly authoritative vs P0-1) and U4 supersession is candidate-set-dependent (a predecessor stays `current` when its successor is absent). ADDITIVELY re-amend BOTH contracts (namespace CLOSURE = intersection(request,grant) + all-packet-visible-fields scope-check + namespace-homogeneous derivations + sanitized rejection + conjunctive task_id+namespace working-state + one canonical predicate/error policy; candidate-INDEPENDENT effective_current + a `superseded` state + chain invariants; conditional-provenance hit shape + candidate_role/multi-stage seam; the working-state store contract; query_class-vs-temporal_intent split) -> re-conform #36/#37/#40 -> run the D-0077 mixed-namespace fold smoke on the HARDENED contracts (now testing the leakage paths) -> fold + close (= PB-3 slim). An as-written D-0077 baseline MAY run first; the CLOSE is gated on i33. **ALSO NOW LIVE: `PROCESS_MANDATE.md` (mandate 01, D-0094) -- a SUNSETTING process-hygiene mandate; READ + address it EVERY session (a cheap status pass + the expiry check); SUNSETS at iteration 40 with a MANDATORY metastability report. Principles + PB-1(corrected)/PB-2/PB-3 live there + in `PROCESS_BACKLOG.md`.** **i31 SELECTION-POLICY SETTLE is DONE** (D-0089 s4 pin + D-0091 wave): #40 context.compile **0.3.0** (`b541df6`) RETIRED selpol_reference.py + IMPORTS #37's canonical `selpol_rrf_v1`/1.0.0; the D-0077 selpol fold PASSED on real #36 data (canonical selection, valid context_packet/0.2, deterministic, 0 orphans) -- the i30 selpol divergence RESOLVED. **DIRECTION (D-0090):** the full long-horizon MEMORY ARCHITECTURE is adopted as the design target (`MEMORY_ARCHITECTURE.md` + `MEMORY_BENCHMARK.md` + `research/2026-08-03-memory-architecture-seam-audit.md`); the memory subsystem now builds by the Tier-0..3 evidence-staged plan -- **NEXT = i32 = Tier-0 seam repairs** (namespace-hard-boundary; hierarchy seam; working-memory store; current-over-stale ranking). Iterations 1-28 are DONE +
  live-confirmed (ledger in section 3; rationale D-0055..D-0085). The 4-lane wave model is VALIDATED (up to 1 GPU
  + 1 CPU + 1 coding + 1 off-box frontier at MaxParallel 3; any lane may be skipped).
- **i23 (D-0078) shipped the SUPERVISOR-HARDENING wave** (single-worker GPU): `model.gateway` #7 0.5.0->**0.6.0**
  (`d289ba9`) folded the i21 frontier red-team's **10 must-fixes** into the DEFAULT-OFF durable Job-Object
  supervisor + integrity layer + real evictor (MF10 partial; **MF1+2 per-resident suspended-create Job custody
  LIVE-PROVEN**), ADDITIVE + defaults byte-identical; 366 off-machine + 74 on-box green, res.lease 74/36/45
  UNCHANGED, 0 orphans. **Finding 5 (durable Job-Object custody) is CLOSED/live-proven.** The i23 as-built supervisor red-team (pack `ff24d3a4`, vs HEAD `d289ba9`) has RETURNED -- **GATE = NO**
  (D-0079): the i23 supervisor is NOT soak-ready. Default-ON is re-gated to an i24 deterministic-hardening wave
  (9 P0/P1 fixes + 18 tests) -> trusted deployment config -> the #00.1 recovery driver -> an in-proc res.lease
  client -> a grown soak; digest `research/2026-07-31-frontier-supervisor-asbuilt-redteam.md`.
- **Warm-pool default-ON now gates (D-0078) on ONLY (1) an in-proc `res.lease` client (the i21 ~6-9
  child-pwsh-spawns/call finding) and (2) a GROWN soak** (>=24h, >=1000 transitions, >=25-each of 5 fault
  classes + the 15 live tests + p99/max/handle-leak/lock-hold/unmanaged-pressure metrics; the full real-model
  fault-injection sweep folds here). The supervisor-hardening gate is CLEARED. NAMED residuals for a follow-on:
  the exec.watchdog #00.1 -> supervisor relaunch DRIVER (MF8 availability half) + the ACL'd app-data state-dir
  move + trusted expected-hash-manifest provisioning (MF10). **Re-offer the in-proc client + soak first**
  (section 4); the baton-pass direction stays Nicholas's call.
- **STANDING RULE (D-0077):** when parallel isolated workers build a schema PRODUCER and its CONSUMER against a
  shared design doc, the orchestrator MUST run a cross-module smoke (real producer output fed into the consumer)
  at fold BEFORE close. (N/A to a single-worker wave like i23.)
- Workers use `docs:[]`; YOU mirror the shared core-docs under the `git` lease (section 7); doc rules in
  `DOC_PROTOCOL.md`. **Doc debt:** CURRENT_STATE + MODULE_ROADMAP are over budget -- a slim pass is a named
  candidate unit (section 4).
- Deliver worker prompts + verification packets + frontier packs to Nicholas as FILES (SendUserFile). Worker
  briefs ALSO go into `core-docs/fanout/FANOUT_AGENT_00N.md` (mirrored to the Project) so Nicholas dispatches
  by telling a fresh session "read `claude/fanout/FANOUT_AGENT_00N.md` and execute it" (section 5). The slots
  were FILLED for i25 then archived + RESET to EMPTY after the i25 fold (D-0082; briefs at archive/fanout-agents/i25-*.md).
- Box state at handoff: section 11.

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit lock,
`doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize). The module emits
prompts; Nicholas starts a fresh session per worker; workers report; the orchestrator mirrors the core-docs.
<=1 GPU worker per wave, ALWAYS. Ship every unit via `dev.ship`. The orchestrator NEVER drives another AI session
(D-0051) -- the frontier lane is a couriered pack (D-0052); automated external-AI access stays OUT.

## 2. First 15 minutes: orient + verify the box

Read (Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/CURRENT_STATE.md`, THIS
doc, `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (the module manual; MaxParallel 3 = 1 GPU + 2 CPU is the
validated ceiling for this box). When editing docs: `core-docs/DOC_PROTOCOL.md`. For the warm pool +
supervisor: `modules/07-model-gateway/WARM_POOL_DESIGN.md` section 10 + the i21 supervisor red-team digest
`core-docs/research/2026-07-31-frontier-supervisor-redteam.md` (the 10 must-fixes -- i23 folded them; the
as-built review answer, once returned, is the next digest). For the video spine: the design review
`research/2026-07-30-track-objects-design-review.md` + both modules' `SCHEMA_NOTES.md`. The gotcha corpus is
owned by `CURRENT_STATE.md` -> Known failures -- read it first.

Verify the box (in `device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`,
  `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> expect no LIVE `<res>.json` lease (durable
  `gpu-*.fence`/`.state`/`.txn` SIBLINGS persist by design -- they are NOT a held lease).
- `git log -1 --format='%h %s'` -> confirm HEAD matches section 11 (read-only git over the mount is fine; ALL
  git writes go through the executor).
- `pgrep -x llama-server; pgrep -x python` -> expect none (0 UNMANAGED orphans).
`device_bash` is a Linux VM -- it CANNOT run Windows pwsh; all pwsh runs through the executor (`exec-job.sh`,
section 7).

## 3. Where things stand

**Now:** modules 0-34 + widgets 01-04 built; the fan-out loop has run 23 iterations; the Verification Console is
the trusted audit surface; the Governor's `-AutoRamp` is DEFAULT-ON (M0->M1->S0); the strong tier is Qwen3.5-9B
Q5_K_M GPU-resident on b10092. The res.lease GPU-lease split is shipped, hardened, consumer-adopted +
live-proven (i18-i21). The **warm pool + durable supervisor stay default-OFF**: after the i23 supervisor-hardening
wave, default-ON is RE-GATED to a full i24 deterministic-hardening wave (D-0079; the as-built red-team returned GATE = NO -- see section 4 + `research/2026-07-31-frontier-supervisor-asbuilt-redteam.md`). **The
Phase C video spine front half is BUILT** (#32 media.decompose + #33 track.objects 0.2.0 stable + #34
video.timeline 0.1.1, contract-proven end-to-end); `video.interpret` (pos 22), the live composition wave, and
the DENSE-STREAM decision gate remain.

**Iteration ledger** (one line each; detail = the D-entry; commits verifiable in git):

- i1-i13 (D-0055..D-0065): res.lease consumers wired; frontier.bridge #31; executor/watchdog hardening;
  Governor Phase 2/3 (`-AutoRamp` default-ON, 9B Q5_K_M); WARM_POOL_DESIGN + Verification Console durable
  verdicts. Full lines: `archive/handoffs/`.
- i14-i17 (D-0067..D-0070): the 4-lane wave model; warm-pool Stage-1/1.1 + the DURABLE supervisor (`cc296fc`);
  portability shims; widget-04; NEW #32 (`5026e2c`) + #33 greedy MVP (`3264dd5`); SD 3.5 image tier; folded
  generator leads + the track/tracker design review.
- i18-i20 (D-0072/73/75): the res.lease GPU-lease-split PRIMITIVE arc -- R1a 0.2.0 `e701328` (74/74) -> R1b
  0.3.0 `2d45ffe` (three-identity fencing + atomic transition; +36/36; red-team pack `b823d9db`) -> R1b' 0.4.0
  `f6df675` (incarnation ids + exec_lease UUID + two-phase capability + target-fenced `fence-op` + saga journal;
  matrix A-K 45/45).
- i21 `fo-21-61c7597b` (D-0076): the **R1b CONSUMER wave** (single GPU worker): model.gateway #7 **0.5.0**
  (`0877c70`+`00e5912`; `-UsePoolLeaseSplit` + the real evictor `lib/PoolEvictor.ps1`), agent.local #21 autoramp
  **0.2.0**, res.lease **0.4.1**; 0 regression + a FULL live-GPU proof; findings 1/13/14 CLOSE-ELIGIBLE. PARALLEL
  frontier SECURITY red-team (pack `5cbe8913`) returned NO with 7 verified must-fix blockers -> default-ON
  re-gated on the SUPERVISOR-HARDENING wave; finding 5 RE-OPENED.
- i22 `fo-22-d2c492e7` (D-0077): the **Phase C TWO-LANE CPU wave**. `track.objects` #33 **0.2.0** (`b60340c`;
  STABLE-IDENTITY tracker default; greedy byte-identical oracle; 169/169 -Live) + NEW **video.timeline #34
  0.1.0** (`e8583d1`) -> the orchestrator cross-module smoke caught 2 consumer-side divergences -> **#34 0.1.1**
  (`bad9e27`; recon 20/20; chain proven on real bytes). Standing smoke rule adopted.
- i23 `fo-23-36f97a35` (D-0078): the **SUPERVISOR-HARDENING wave** (single GPU worker). `model.gateway` #7
  **0.6.0** (`d289ba9`) folded the i21 red-team's 10 must-fixes into the DEFAULT-OFF durable supervisor +
  integrity layer + evictor (MF10 partial; MF1+2 per-resident suspended-create Job custody LIVE-PROVEN; MF3-9
  done; MF8 #00.1 relaunch driver + MF10 ACL'd app-data/trusted-hash-manifest NAMED residuals); 366 off-machine
  + 74 on-box green; res.lease 74/36/45 UNCHANGED; defaults byte-identical; 0 orphans. **Finding 5 CLOSED.** An
  AS-BUILT supervisor red-team pack (`ff24d3a4`, vs `d289ba9`) was emitted for GPT-5.x -- answer PENDING.
  default-ON is RE-GATED (D-0079): a full i24 deterministic-hardening wave (as-built red-team = GATE NO; see the digest) precedes it.

- i24 (D-0079/D-0081): frontier-review iterations -- the as-built supervisor red-team folded (GATE NO) + the whole-project-direction pack 817e52e9 folded (ratifies D-0080); no local worker wave.
- i25 `fo-25-3b718a13` (D-0082): the **WAVE 1 memory-substrate 3-lane wave** -- #35 embedding.local 0.1.0 (`99b6590`) + #36 artifact.search 0.1.0 (`30ef7bd`) + #37 retrieval.eval 0.1.0 (`687edcd`); the D-0077 embedding->artifact.search->benchmark cross-module smoke PASSED (real 1024-dim; recall/provenance 1.0; span object/string divergence bridged); memory red-team 12c8f539 folded GO.
- i26 (D-0083): orchestrator-only, NO worker wave -- the retrieval-record/provenance CONTRACT FREEZE: NEW `core-docs/MEMORY_CONTRACT.md` freezes the record+provenance envelope v0.1, embedding-provider 0.2, retriever 0.2 (resolves the i25 span object-vs-string + skipped-input null-vs-zero divergences), and catalog/evaluation/scale-privacy gates from the memory red-team; governs Wave 2. No module commits; doc-debt slim pass still deferred.
- i27 `fo-27-bab47060` (D-0084): the **WAVE 2 memory-RECORDS 3-lane CPU wave** -- #36 artifact.search 0.1.0->0.2.0 (`b57d328`; record-envelope + `ingest_records` SINK + schema_version 2 migration + retriever-0.2 hits + float32 BLOB vectors + catalog hardening; 113/113) + NEW #38 repo.intel 0.1.0 (`cd53565`; deterministic typed-record producer; 65/65+37/37) + NEW #39 episode.record 0.1.0 (`b381686`; episode+failure schema + recorder + failure-signature seam; 114/114); the D-0077 fold smoke PASSED (repo.intel 198 records + episode/failure -> #36 0.2 ingest_records -> retrieval + provenance + idempotent re-ingest) and CAUGHT+BRIDGED 2 divergences (episode.record `episode_stage` kind not in the s1 enum; status object-vs-string) -> follow-on: episode.record 0.1.1 conformance + a MEMORY_CONTRACT amendment.
- i28 `fo-28-45c4ad65` (D-0085): the **CONTRACT-SETTLE wave** (single CPU worker) -- MEMORY_CONTRACT Amendment A1 (record-envelope v0.1 -> v0.1.1: envelope status = a single s5 STRING [`{state,stale_reasons,verified}` retired]; `record_kind` enum CLOSED, `episode_stage` NOT a kind) + episode.record #39 0.1.0 -> **0.1.1** (`3dab699`; status -> the s5 string; per-stage detail folded into `episode.body.stage_sequence` + `has_stage` edges; suite 114 -> 123 green). The orchestrator D-0077 re-smoke PASSED 30/30 (episode.record 0.1.1 RAW into #36 0.2 `ingest_records`: would_bridge 0, 0 rejections, no `episode_stage`, status = the s5 string). The two i27 divergences RESOLVED.
- i29 `fo-29-87dbfa0b` (D-0086): the **WAVE 3 3-lane CPU wave** (context compiler + skill retrieval; GPU lane skipped, no model -- the 9B only at the fold) -- NEW context.compiler #40 0.1.0 (`b89eda0`; deterministic `lifeorch.context_packet/0.1`: normalize -> #36 retriever-0.2 seam -> rerank/diversity -> token budget -> packet + expand seam + eval hooks; 46/46+16/16 + 23/23 -Live) + retrieval.eval #37 0.1.0->**0.2.0** (`dc293ef`; s6 eval-0.2 gates + a DETERMINISTIC reranker MEASURED vs raw order; 119/119 cross-env) + NEW skill.card #41 0.1.0 (`1eafd2c`; section-9 cards + `sklcard_` s1 skill index + Stage-1 eligibility + Stage-2 lexical seam; 72/72+80/80). The D-0077 fold smoke PASSED on real data (#41->#36 ingest-records 40 accepted/0 rejected; #36 retriever-0.2->#40 packet 3 excerpts all provenance-reproduced; P0-5 sklcard_/derived vs skl_/canonical_source coexist NO collision; 0 orphans). Frontier design red-team (pack `d57fead3`) FOLDED: GO read-only build, NO-GO freezing the new contracts, NO-GO side-effecting until the safety-critical P0-1. NEXT = i30 CONTRACT-HARDENING.
- i30 `fo-30-dd453156` (D-0087/D-0088): the **CONTRACT-HARDENING wave** -- D-0087 committed the context_packet/0.2 contract (NEW `core-docs/CONTEXT_PACKET_CONTRACT.md` + MEMORY_CONTRACT A2/A3, folding frontier P0-1..P0-5 + P1-1); the 3-lane CPU conformance wave shipped context.compiler #40 0.1.0->**0.2.0** (`f06e6e7`; three-region control_plane/task_input/evidence packet + non_execution gate + P0-3 disposition + P0-4 consumer_profile/transport + P1-1 selpol seam + P1-5 lineage + A2 modes; 148/148+-Live) + retrieval.eval #37 0.2.0->**0.3.0** (`99bb627`; NEW `lib/selpol_rrf_v1.py` selection-policy library, rerank() a thin wrapper, eval-0.3) + skill.card #41 0.1.0->**0.2.0** (`54c2e79`; A3 record_kind skill->summary + derives_from edge to #38). The D-0077 fold PASSED the #41->#36->#40 chain (40/40 summary ingested; #38 sole skill owner; a valid context_packet/0.2) but CAUGHT a selpol producer/consumer divergence (#40 `selpol_reference` vs #37 canonical `selpol_rrf_v1` select differently: rank-RRF vs raw-score primary, weight scales, diversity, output, a mechanical AUTHORITY_POINTS break) -- NEITHER a defect. NEXT = i31 SELECTION-POLICY SETTLE.
- i31 `fo-31-eca37c08` (D-0089/D-0091): the **SELECTION-POLICY SETTLE wave** (single CPU worker). D-0089 PINNED CONTEXT_PACKET_CONTRACT s4 to #37's canonical `selpol_rrf_v1`/1.0.0 (raw-fused-score-primary composite; AUTHORITY_RANK/freshness ranks; source-MMR + occurrence-preserving display dedup; additive hit-copy output; AUTHORITY_POINTS + the rank-RRF-primary reference retired; pure-rank-RRF-primary = deferred P1-2). #40 context.compile 0.2.0->**0.3.0** (`b541df6`; DELETED selpol_reference.py + IMPORT #37's canonical by a resolved path; params.hard_filter from control_plane.permission_grants; regenerated fixtures; 162/162 off-machine incl the #40-vs-direct-select byte-identity + 34/34 entrypoint; -Live deferred to the fold). The orchestrator D-0077 selpol fold PASSED on real #36 data (#40's OWN compile stamps selpol_rrf_v1/1.0.0; valid context_packet/0.2; evaluation_hooks retrieved=49 canonical reason_codes; deterministic packet_id; 0 orphans; #41->#36 chain re-confirmed 40 accepted/0 rejected, integrity 15/15). The i30 pair-1 divergence RESOLVED; P1-1 'one selection owner' realized. Also this session: DECISION_LOG_INDEX slimmed to routing-only + maintenance rules (DOC_PROTOCOL s2; budget 12->20 KB); **D-0090 adopted the full MEMORY ARCHITECTURE as the design target** (`MEMORY_ARCHITECTURE.md` + `MEMORY_BENCHMARK.md` + seam audit).

- i32 `fo-32-0fb25203` (D-0092, IN FLIGHT): the **Tier-0 MEMORY-ARCHITECTURE seam-repair wave**. PART 1 (orchestrator): MEMORY_CONTRACT **A4** + CONTEXT_PACKET_CONTRACT **i32 amendment** committed (`b8c9a3d`; namespace HARD boundary U1; current_only mode + supersession-aware ranking + `contradicts` edge U4; reserved-additive `node`/`working` kinds + `member_of_node`/`child_of_node` edges U2/U3; frozen-open channels + query-classification seam U5; budgets 24->28 / 22->25 KB). PART 2 (3-lane CPU, GPU skipped, plan `fo-32-0fb25203`, dispatch_now 3 / 0 gpu / 0 doc-contention): #36 artifact.search 0.2->0.3 (namespace hard-filter + current_only mode + reserved kinds/edges + schema_version 2->3 migration; owns gate tests 1+2), #37 retrieval.eval selpol_rrf_v1 1.0->1.1 + eval 0.3->0.4 (namespace/current_only/supersession stages + query_class), #40 context.compiler 0.3->0.4 (namespace plumbing + query-classification stage + working_memory region + import selpol 1.1; gate test 3). Frontier Tier-0 red-team pack `159e9cb5` out (non-blocking). DISPATCHED -> awaiting worker reports -> the D-0077 MIXED-NAMESPACE fold smoke at close.

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` · artifacts `.../runtime/artifacts/<id>/`
· leases `.../29-resource-lease/runtime/leases/`. Waves + ad-hoc commits share one counter; **the next wave is
iteration 29** (i25 = Wave 1 substrate; i26 = contract freeze; i27 = Wave 2 records; i28 = the contract-settle conformance).

## 4. Current frontier -- i31 SELECTION-POLICY SETTLE DONE (D-0089/D-0091); DIRECTION shift D-0090; NEXT = i32 Tier-0 MEMORY-ARCHITECTURE seam repairs

**STATUS (i32, NEXT): Tier-0 MEMORY-ARCHITECTURE seam repairs.** D-0090 adopted the full long-horizon memory architecture as the design target -- `MEMORY_ARCHITECTURE.md` (target + Tier-0 invariants + typed memory + bounded-fanout hierarchy + query-aware retrieval + consolidation + procedural promotion + the T0-T3 roadmap) + `MEMORY_BENCHMARK.md` (foreign-corpus validation) + `research/2026-08-03-memory-architecture-seam-audit.md` (gap analysis). The immediate memory-side work is **Tier 0** (design-now invariants + the URGENT lock-in seam repairs, seam audit s3): (1) namespace as a HARD retrieval/partition boundary; (2) protect the hierarchy seam (#36 schema + retriever channel model + selpol/compiler admit a node layer + shortlist-and-descend WITHOUT a rewrite); (3) a per-task_id working-memory store seam; (4) current-over-stale as a real retrieval MODE + supersession-aware ranking + a contradicts edge; (5) keep the retriever channel model OPEN + a query-classification seam. Scope i32 from `MEMORY_ARCHITECTURE.md` s10 (Tier 0 -> Tier 1). Amend `MEMORY_CONTRACT.md` / `CONTEXT_PACKET_CONTRACT.md` (field-level authorities) to satisfy the seams. The supervisor/warm-pool freeze (D-0079) + generators + video.interpret + real-time perception stay FROZEN. The 4-lane wave model + the mechanics below are UNCHANGED. --- **i31 SELECTION-POLICY SETTLE (DONE, D-0089/D-0091):** #40 context.compile 0.3.0 (`b541df6`) imports #37's canonical selpol_rrf_v1/1.0.0 (reference retired); the D-0077 selpol fold PASSED on real #36 data; the i30 divergence RESOLVED. --- HISTORICAL i30 STATUS follows --- 

**STATUS (i30, D-0087+D-0088): CONTRACT-HARDENING SHIPPED + FOLDED.** D-0087 committed the context_packet/0.2 contract (NEW `core-docs/CONTEXT_PACKET_CONTRACT.md` [P0-1 control/evidence separation, P0-3 disposition, P0-4 consumer profile, P1-1 selection-policy interface, P1-5 lineage] + MEMORY_CONTRACT A2 [P0-2 provenance hash split] + A3 [P0-5 skill->summary]). The conformance wave (plan `fo-30-dd453156`, 3-lane CPU) shipped #40 context.compiler **0.2.0** (`f06e6e7`) + #37 retrieval.eval **0.3.0** (`99bb627`; NEW `lib/selpol_rrf_v1.py`) + #41 skill.card **0.2.0** (`54c2e79`; A3 skill->summary). The D-0077 fold PASSED the #41->#36->#40 chain (40/40 summary ingested, #38 sole skill owner, a valid context_packet/0.2 with control/evidence separation + disposition + consumer profile) but CAUGHT a MATERIAL selpol producer/consumer divergence: #40's in-module `selpol_reference.py` and #37's canonical `selpol_rrf_v1` select DIFFERENTLY (rank-RRF-primary vs raw-fused_score-primary; different weight scales; excerpt_hash-clustering vs source-MMR diversity; different output fields; a mechanical `AUTHORITY_POINTS` incompatibility). NEITHER is a defect -- s4 froze the interface + stages but not the weights/relevance-primary/diversity/output, so P1-1 'one selection owner' is NOT yet realized. **NEXT = i31 SELECTION-POLICY SETTLE:** amend CONTEXT_PACKET_CONTRACT s4 to pin the scoring/relevance-primary/diversity/output + retire the AUTHORITY_POINTS dependency, re-ship #40 to IMPORT #37's canonical `selpol_rrf_v1` (retire the reference) + #37 to conform, and re-run the D-0077 selpol smoke for byte-identical selection; then the DEFERRED P1-2..P1-9 + P2 + the shared cross-module fixture + the P0-1 adversarial injection SUITE (the action-capable gate release). Digest `research/2026-08-02-frontier-wave3-design-redteam.md`. --- HISTORICAL Wave-3 STATUS follows --- WAVE 3 (context compiler + skill retrieval) SHIPPED + FOLDED -- NEW context.compiler #40 0.1.0 (`b89eda0`; `lifeorch.context_packet/0.1`) + retrieval.eval #37 0.1.0->0.2.0 (`dc293ef`; s6 eval-0.2 + a DETERMINISTIC reranker) + NEW skill.card #41 0.1.0 (`1eafd2c`; section-9 cards + `sklcard_` s1 skill index + Stage-1 eligibility + Stage-2 lexical seam). The D-0077 fold smoke PASSED on real data (see section 11); the frontier design red-team (pack d57fead3) FOLDED -- GO for the read-only build, NO-GO for FREEZING the new contracts, NO-GO for side-effecting until the SAFETY-CRITICAL P0-1 (control-plane-vs-evidence separation). **NEXT = i30 CONTRACT-HARDENING** (fold P0-1..P0-5 + P1-1 into a MEMORY_CONTRACT/context_packet 0.2 amendment [control/evidence separation, provenance hash split, packet_disposition, consumer/tokenizer profile] + #41 skill->summary + one selection-policy lib; P0-1 a hard pre-execution gate; digest `research/2026-08-02-frontier-wave3-design-redteam.md`). --- HISTORICAL Wave-2 detail follows --- #36 artifact.search 0.1.0->0.2.0 (`b57d328`; record-envelope + generic `ingest_records` SINK + records/record_edges + schema_version 2 in-place migration + parser/chunker/extractor fingerprints + retriever-0.2 hits [span object+label, per-channel scores, opaque score retired] + s5 staleness enum + float32 LE BLOB vectors + catalog hardening; 113/113) + NEW #38 repo.intel 0.1.0 (`cd53565`; deterministic typed-record producer -- symbol/entity/relationship/skill/summary; 65/65+37/37) + NEW #39 episode.record 0.1.0 (`b381686`; episode+failure schema + deterministic recorder + failure-signature seam; 114/114). The D-0077 cross-module fold smoke PASSED (repo.intel 198 records + episode/failure -> #36 0.2 `ingest_records` -> `list-records`/`search` resolve the s1 envelope + the retriever-0.2 hit shape; provenance validated [content_hash==file sha256; cited span reproduces source]; idempotent re-ingest, catalog_digest stable) and CAUGHT+BRIDGED 2 producer/consumer divergences: episode.record emits `record_kind: episode_stage` (NOT in the frozen s1 enum) + `status` as an OBJECT (consumer enforces the s5 STRING enum) -> the orchestrator dropped the redundant episode_stage records (stages also live in `episode.body.stage_sequence`) + coerced status->state; repo.intel conformed. NEITHER is a #36 defect. **FOLLOW-ON (Nicholas's call, before/with Wave 3):** episode.record 0.1.1 conformance (status -> the s5 string; stages as edges/body) AND/OR a MEMORY_CONTRACT s0 amendment (add `episode_stage`; freeze the status representation). **(SUPERSEDED: Wave 3 is DONE (i29, D-0086); NEXT = i30 CONTRACT-HARDENING -- see the STATUS header above + section 11.)** The i28 CONTRACT-SETTLE wave is DONE (D-0085; MEMORY_CONTRACT A1 v0.1.1 + episode.record #39 0.1.1; the D-0077 re-smoke PASSED 30/30, 0 bridging -- see section 3). The Wave-1 (i25) + Wave-2 (i27) work orders below are kept for reference.

Nicholas's directive: up to FOUR lanes per wave; any lane may be skipped. Every lane is human-dispatched.

- **GPU lane (<=1 per wave -- HARD CLAMP).** One worker on a GPU-bound unit. ONLY this lane touches model modules
  / `models.json`. Leases gpu->git.
- **CPU lane (>=1).** One worker on a CPU-only module/infra unit. Lease git.
- **Coding lane (CPU, >=1).** A broad-remit CPU worker in a DISTINCT module/area from the CPU lane. Lease git.
- **Frontier-review lane (off-box, OPTIONAL).** NOT a Cowork worker: emit a frontier.bridge #31 `pack`
  (`{prompt, question?, paths?}`); Nicholas couriers it + pastes the answer back; run `read-return`, fold it. No
  lease; fully parallel. **FOLDED (D-0079):** the i23 as-built supervisor red-team (pack `ff24d3a4`) RETURNED **GATE = NO** -- the i23
  supervisor is NOT soak-ready (digest `research/2026-07-31-frontier-supervisor-asbuilt-redteam.md`): 9 P0/P1
  must-fixes + 18 deterministic tests precede a gating soak. **FOLDED (i25, D-0081):** the whole-project-DIRECTION pack
  (`817e52e9`) RETURNED; `read-return` captured + validated it (valid/captured/pack_id_match). The answer IS the
  D-0080 directive doc `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md` -- it RATIFIES
  D-0080 (no course change); no separate digest was needed. Wave 1 unchanged.

**Clamps.** <=1 GPU worker always. **1 GPU + 2 CPU = MaxParallel 3** is the validated ceiling. The `git` lease
serialises commits; `docs:[]` on all workers -> doc contention 0. Persistent llama-servers MUST launch DETACHED
(via the supervisor) + be reaped before finalize; reassert the 0-UNMANAGED-orphan check every wave. **Schema
producer/consumer pairs split across isolated workers REQUIRE the orchestrator cross-module smoke at fold
(D-0077).**

**Wave loop:** scope lanes (distinct modules) + an optional frontier topic -> fill `FANOUT_AGENT_00N` slots
(section 5) -> author `workers-i24.json` + `task-plan-i24.ps1` (copy `task-plan-i23.ps1`; `-Iteration 24
-MaxParallel <=3`; `gpu:true` only on the GPU worker) -> run `plan`; confirm `dispatch_now`, <=1 gpu, 0 doc
contention, clean preflight -> emit any frontier pack separately -> relay the check-in + every worker prompt +
the pack as FILES + slot docs -> workers run + report -> poll `-Action status -PlanId fo-24-<id>` until
`ready_for_handoff` -> `-Action handoff` -> verify commits via NATIVE git -> run any cross-module smoke the
wave's shape demands -> fold, mirror the core-docs under the `git` lease, archive the used briefs + reset the
slots -> iterate.

**Wave 1 work orders (D-0080 -- the Collective Agent memory substrate; workers NOT yet dispatched -- fill the
`FANOUT_AGENT_00N` slots only when Nicholas approves dispatch).** Distinct modules; `docs:[]`; <=1 GPU worker.

- **GPU lane -- Embedding adapter.** Turn the pre-provisioned `embedding.qwen3-0p6b` (staged + unwired) into a
  conforming, versioned, testable local capability. Scope: text + batch-text input; normalized vectors + dims +
  model/version/hash provenance; deterministic input-order preservation; empty/oversize handling; gpu lease;
  CPU-fallback feasibility probe. NO vector DB, NO ingestion, NO routing. Accept: stable schema; repeated-input
  consistency within tolerance; batch==single; 0 orphaned model procs; latency/memory measured;
  fixture/similarity-order tests; clean failure modes.
- **Coding lane -- `artifact.search` deterministic MVP** (arch #23; the authoritative catalog + hybrid lexical
  substrate). Scope: SQLite schema (sources/documents/versions/chunks + provenance); file inventory + content
  hash; Markdown-aware chunking + generic-text fallback; FTS; metadata filters; an embedding-provider interface
  with a MOCK; result->source provenance; incremental changed-file ingest; a CLI/skill contract. Non-goals:
  AST/call-graph, summaries, episodes, failure memory, context compiler, UI, web search. Accept: index a fixture
  repo + a bounded real-repo slice; exact + FTS retrieval; deterministic re-ingest; changed/deleted
  reconciliation; no duplicate chunks; DB integrity check; provenance to source; mock-embedding contract tests.
- **CPU lane -- Retrieval-evaluation harness** (make retrieval quality measurable BEFORE vector integration).
  Scope: benchmark schema; query + required-source labels; lexical baseline; recall@K / MRR / stale-source /
  provenance metrics; report artifact; fixture corpus + initial LO benchmark questions. NO production router.
  Accept: deterministic benchmark run; known lexical baseline; a FAILING test when a required source is absent;
  a version/staleness test; machine- + human-readable reports.
- **Frontier lane (optional, non-blocking) -- Memory-architecture red-team.** Design review of the SQLite schema,
  embedding-adapter contract, `artifact.search` boundaries, benchmark design, provenance, versioning, privacy,
  failure modes, and the 2080 Ti operating assumptions. The local wave does NOT block on it unless it flags a
  safety-critical issue.
- **Orchestrator fold (REQUIRED, D-0077 cross-module smoke).** A REAL producer->consumer smoke: embedding adapter
  produces vectors -> `artifact.search` ingests -> the benchmark runs hybrid retrieval -> results resolve to real
  source spans -> a repeat run is stable -> a changed-file re-index updates results -> all artifacts + model
  provenance captured. Parallel isolated worker tests are NOT sufficient.

**Later waves (pointer, not a menu):** Wave 2 = repository intelligence + episode/failure schema+recorder; Wave 3
= context compiler + skill-card/registry + retrieval reranker. Then read-only Collective Agent slice -> sandbox
coding worker -> sequential LOCAL orchestrator (D-0080 local coordinator; no human courier) -> domain slices ->
unified UI. Frozen: supervisor/warm-pool hardening (D-0079 GATE-NO), generators, `video.interpret`, real-time
perception, broad training. Full spec: `research/2026-07-31-roadmap-reprioritization-cognitive-virtual-memory.md`.

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template `FANOUT_AGENT_TEMPLATE.md`;
mirrored at `claude/fanout/`) decouple "what a worker must do" from chat pasting: fill a slot at wave scoping
(paste the `plan`-emitted worker prompt into its Unit section, or a tight summary pointing to the emitted copy +
the governing design doc; keep the slot within its 8 KB budget), mirror it, and Nicholas dispatches a fresh
session with "Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant
(section 10). Slot docs also travel to Nicholas as FILES. **The slots were RESET to EMPTY after i23** (used
brief archived to `archive/fanout-agents/i23-SUPERVISOR-HARDENING.md`; ship-state at
`core-docs/fanout/SUPERVISOR-HARDENING-i23-SHIP-STATE.md`). Lifecycle: `DOC_PROTOCOL.md` section 6.

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/`
  + `ops/` + `archive/`. Disk is canonical; the attached Claude Project mirrors `core-docs/` (mirror map in
  `DOC_PROTOCOL.md` section 8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-owning-module model
  homes; `_engines\llama.cpp` (b8661, default) + `_engines\llama.cpp-b10092` (CUDA 12.4; ONLY the 9B pins it).
- **Executor:** `modules\00-bootstrap-executor\runtime\`; driven via `exec-job.sh`. Heartbeat:
  `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Warm pool / supervisor** (`modules/07-model-gateway/`): `lib/PoolManager.psm1` + `lib/Supervisor.psm1` +
  `Start-GatewaySupervisor.ps1` + `lib/PoolEvictor.ps1` + `WARM_POOL_DESIGN.md` (0.6.0 as of i23: the 10 must-fix
  hardening; `tests/Invoke-ModelGatewayHardeningTests.ps1`).
- **Video spine:** `modules/32-media-decompose/` + `modules/33-track-objects/` (0.2.0; `SCHEMA_NOTES.md` = the
  emitter contract) + `modules/34-video-timeline/` (0.1.1; `SCHEMA_NOTES.md` notes 34-35 = the reconciliation).
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB (CC 7.5), i9-9900KF 8c/16t, 64 GB RAM, Win10 Pro; C: ~67 GB
  free, F: 3.72 TB. Full profile: `TOOL_MODEL_REGISTRY.md`.

## 7. Mechanics cheat-sheet

- **Run pwsh via the executor** (from `device_bash`, `~/mnt/LifeOrchestrator-Refresh`): write a `task.ps1` under
  `modules/30-orchestrate-fanout/runtime/`, then `bash modules/00-bootstrap-executor/exec-job.sh run <id>
  <timeout> <task.ps1> <maxwait> "<desc>"`. Long/GPU jobs: re-run `exec-job.sh wait <id>` (device_bash caps
  ~45 s). Verbs: `submit|wait|run|devship|status`; `EXEC_RT` overrides the runtime dir.
- **Cloud -> device:** gate off-machine FIRST, then `SendUserFile` + `device_commit_files` the changed files onto
  the repo (byte-exact; <=20 MB/file). Large binaries download ON the device via an executor `curl.exe` task.
  `device_bash` cannot delete -- `mv` unwanted files into a `_to_delete\` folder.
- **Device -> cloud bulk reads:** `device_stage_files` (fresh, never-staged paths only -- re-staging returns a
  STALE snapshot; can 403 `session_stale_relogin` -> tell Nicholas, don't retry). Fallback: `tar` + `base64 -w0`
  + cat on-device -> slice/decode in cloud bash. Cloud has NO pwsh by default -- a GitHub tarball install
  (`/opt/pwsh/pwsh`, chmod +x) runs the off-machine gates.
- **Ship a unit:** `exec-job.sh devship <id> <inputs.json> <timeout>` -- dev.ship verifies sha256 + AST + tests
  FAIL-CLOSED, then commits ONLY the named files under the `git` lease with trailers. **VERIFY the real HEAD via
  native `git log`/`git show --stat`, NOT the dev.ship `committed` field** (D-0072).
- **Author a plan:** write `workers-i<N>.json` + a `task-plan-i<N>.ps1` (copy `task-plan-i23.ps1`), run it,
  confirm `dispatch_now` / <=1 gpu / 0 conflicts / clean preflight. `-Action status -PlanId <id>` polls;
  `-Action handoff` emits the Verification Console packet + next prompts. If `status` returns no artifact, read
  the worker reports under `plans/<id>/reports/` directly -- they are the source of truth.
- **Frontier pack:** #31 `pack` op takes `{prompt, question?, paths?}`. Emit, stage, SendUserFile; Nicholas
  couriers + pastes the answer BETWEEN the pack's two `<<<FRONTIER-BRIDGE-ANSWER-...>>>` markers (keep the
  `<!-- pack_id: ... -->` line) into the `.answer.md` return file; run `-Action read-return -ReturnFile <path>
  -ExpectPackId <id>` (expect `captured/valid`, `pack_id_match`) to capture; fold into a research digest + docs.
- **Doc edits + mirror (EOL-safe, fail-closed; full rules in DOC_PROTOCOL.md):** core-docs are CRLF; SOME MODULE
  DOCS ARE LF (e.g. `WARM_POOL_DESIGN.md`, the #34 docs) -- PRESERVE PER-FILE EOL. Pull byte-exact doc bytes
  (stage a FRESH path or tar/base64), apply anchored replacements in cloud (assert each anchor count == 1),
  `device_commit_files` the whole file back, then commit via an executor `task.ps1`: acquire the `git` lease ->
  `git reset -q` -> `git add -- <named files>` -> assert the staged set -> `git commit -F <msg>` -> release.
  Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>` + `Claude-Session: <url>`. NEVER
  `git add -A`. Re-mirror via `project_write` `local_path` (inside the working dir).
- **DECISION_LOG upkeep:** append the new `D-00NN` entry at the bottom of `DECISION_LOG.md` AND append its one-row
  line to `DECISION_LOG_INDEX.md`; mark a superseded predecessor in its INDEX row only. Update `CURRENT_STATE.md`
  by REPLACING sections -- never append `[prior]` chains.
- **Deliver everything to Nicholas as FILES** (SendUserFile) -- prompts, packets, packs.

## 8. Worker-spec rules

- `docs:[]` on EVERY worker (the orchestrator mirrors core-docs; zeroes doc contention).
- <=1 GPU worker per wave; every model module is `parallel_safe:false`; ONLY the GPU lane touches `models.json` /
  model modules.
- Distinct module/area per worker -- never two workers in one module. **A schema PRODUCER and its CONSUMER may
  run as parallel isolated workers ONLY with (a) one governing design doc named as the shared contract, (b)
  per-module SCHEMA_NOTES.md recording every interpretation, and (c) the orchestrator cross-module smoke at
  fold (D-0077).**
- Correct `inputs` for any skill_id (match the skill.json op contract). A brand-new module has no skill.json yet
  -- OMIT `skill_id`/`skill_dir` for it.
- **Single-worker waves for core infra** (executor/watchdog, dev.ship, orchestrate.fanout itself, res.lease #29,
  the model.gateway durable supervisor + the in-proc res.lease client + the grown soak).
- Workers acquire leases in gpu -> git -> doc order, do ONE unit, ship via dev.ship, then `-Action report -State
  done`. A build-then-verify GPU unit may take git for the commit, RELEASE it, then take gpu ONLY for the live
  verify. A live proof whose harness itself acquires the real gpu exec/pin leases must NOT wrap an outer
  whole-task gpu lease around the proof (i21 lesson).

## 9. Gotchas (the load-bearing set -- full corpus: `CURRENT_STATE.md` -> Known failures)

- **The wedge (D-0055/56):** a task that BLOCKS holding a persistent llama-server orphans it + can livelock the
  executor while the heartbeat stays fresh. Launch persistent servers DETACHED (via the supervisor); reap before
  finalize; assert 0 UNMANAGED orphans. If wedged: kill the orphan OUT-OF-BAND (Task Manager -> `llama-server.exe`).
- **A long-running supervisor keeps OLD module code (i21):** RESTART the supervisor after shipping any
  supervisor-side change before the live check. Driver 591.74 SPILLS a too-big model to system RAM ("it loaded"
  != "it fits"); the measured-PEAK `required_vram` gate is the only real admission control.
- **`device_stage_files` stale snapshot:** re-staging a previously-staged path returns OLD bytes. Stage a FRESH
  never-staged path, or read via tar/base64 / an executor task. Staging can also 403 (`session_stale_relogin`).
- **Per-file EOL:** core-docs CRLF; some module docs (e.g. `WARM_POOL_DESIGN.md`, modules/34 docs) LF. Match the
  existing EOL.
- **Git discipline:** read-only git over the mount only (huge CRLF-noise M-list -- ignore it); ALL git writes
  through the executor under the `git` lease; NEVER `git add -A`; `project_write local_path` must be inside the
  working dir. `dev.ship` can FALSE-NEGATIVE `committed` (verify real HEAD via native git; clear a stale 0-byte
  `.git/index.lock` via an executor task, assert no `git.exe` running, then re-commit).
- **pwsh 7.4.6 determinism traps:** `[System.Array]::Sort(object[], Comparison[string])` sorts a CONVERTED COPY
  (silent no-op) -> cast to `[string[]]` first; empty-array unroll (`$x=@()` first); `,$out` double-wrap with
  `@()`; `@($list)` on a `List[object]` of pscustomobjects throws; `$var:` in a double-quoted string -> `${var}`;
  child-process pipe deadlock -> drain stdout+stderr async; `[Console]::Out` bypasses in-process capture. Keep
  double-run byte-identity gates in every canonical-bytes module.
- **Deliver files, not paths** (SendUserFile) -- and keep `-MaxParallel` at 3 until the heartbeat proves more.

## 10. Required access (grant at session start)

Every orchestrator AND worker session needs exactly ONE grant: **connect the repo folder
`C:\Users\just_\LifeOrchestrator-Refresh`** (desktop app "Add folder", or approve a
device_request_folder_access). That covers reading the repo, driving the executor, staging, and committing. F: is
reached natively by the Windows executor. Machine prerequisite: the executor running (`ops/start-executor.bat` or
the watchdog), heartbeat fresh + `degraded:false`. Computer-use (Task Manager) is only for out-of-band wedge
recovery.

## 11. Box state at handoff (2026-08-04, D-0092/D-0094/D-0095 -- i32 wave COMPLETE + frontier NO-GO -> i33 hardening; PROCESS_MANDATE 01 ACTIVE)

**UPDATE (post-dispatch; supersedes the box detail below until the fold rewrites it):** all 3 i32 workers reported DONE + shipped -- #36 artifact.search 0.3.0 (`ef667f7`; gate tests 1+2; 142/142+55/55), #37 retrieval.eval/selpol_rrf_v1 1.1.0 + eval 0.4 (`26224d7`; 56/56+171/171; native-git verified), #40 context.compile 0.4.0 (`31ebdf7`; 203/203+38/38; selpol-1.1.0 NEW-behavior + -Live DEFERRED). **HEAD = `26224d7`.** No held `res.lease`; heartbeat `degraded:false`; 0 UNMANAGED orphans. **The frontier Tier-0 red-team (pack `159e9cb5`, D-0095, digest `research/2026-08-04-tier0-amendment-redteam.md`) FOLDED = NO-GO to close i32 as-written** (SAFETY-CRITICAL U1 namespace-closure defect + U4 candidate-dependent supersession; the amendments are a correct ENVELOPE-level first layer but incomplete). **NEXT = i33 NAMESPACE-CLOSURE + SUPERSESSION-HARDENING** (re-amend both contracts per the digest's changes 1-5 + risk-6 -> re-conform #36/#37/#40 -> the D-0077 mixed-ns fold smoke on the HARDENED contracts, now testing the leakage paths -> close = PB-3 slim). **`PROCESS_MANDATE.md` (D-0094) ACTIVE -- address every session; sunset i40.**

--- superseded pre-completion i32 box detail follows: ---

**i32 IN FLIGHT (D-0092, plan `fo-32-0fb25203`).** PART 1 committed: MEMORY_CONTRACT A4 + CONTEXT_PACKET_CONTRACT i32 amendment + DOC_PROTOCOL budgets + D-0092, **HEAD = `b8c9a3d`** (native-git verified: 5 core-docs, no add -A). PART 2 dispatched: the 3-lane CPU conformance wave (#36/#37/#40) worker prompts + FANOUT_AGENT_001/002/003 (READY) delivered to Nicholas; frontier pack `159e9cb5` out (return file `modules/31-frontier-bridge/runtime/artifacts/159e9cb5-bfdf-4d55-bd54-bc9509b810a5/frontier-pack-i32-tier0-redteam.answer.md`; read-return with -ExpectPackId 159e9cb5). No LIVE `res.lease` held (durable `gpu-e3c5ba51.*` siblings persist by design -- NOT held); heartbeat `degraded:false`; 0 UNMANAGED llama-server/python. **NEXT = poll `-Action status -PlanId fo-32-0fb25203` -> `-Action handoff` -> the D-0077 MIXED-NAMESPACE fold smoke (section 4): build a #36 catalog with ns-A + ns-B records + a superseded/successor pair + a reserved `node` record -> a ns-A `current_only` compile via #40 importing #37's shipped selpol 1.1.0 -> assert zero ns-B leakage (retriever + selpol), superseded demoted below successor, stale excluded, node additive-ingested, every excerpt reconstructs to source, byte-identical #40-vs-direct-select, deterministic packet_id, 0 orphans -> fold + close i32 (snapshot+rewrite this handoff; slim the over-budget docs).** Start at section 2, then i32 (section 4).

--- superseded i31 box detail follows: ---

**i31 = SELECTION-POLICY SETTLE DONE (D-0089 s4 pin + D-0091 wave, plan `fo-31-eca37c08`, single CPU worker):** #40 context.compile 0.2.0->**0.3.0** (`b541df6`; RETIRED selpol_reference.py + IMPORT #37's canonical `selpol_rrf_v1`/1.0.0; params.hard_filter from control_plane). The orchestrator D-0077 selpol fold PASSED on real #36 data (#40's own compile stamps selpol_rrf_v1/1.0.0; valid context_packet/0.2; deterministic; 0 orphans; #41->#36 chain re-confirmed). **DIRECTION (D-0090):** the full long-horizon MEMORY ARCHITECTURE is the design target (`MEMORY_ARCHITECTURE.md` + `MEMORY_BENCHMARK.md` + seam audit); **NEXT = i32 Tier-0 seam repairs** (section 4). Also this session: DECISION_LOG_INDEX slimmed to routing-only + maintenance rules (budget 12->20 KB). **HEAD = the D-0091 fold-docs commit on top of `1289053` (chain `b541df6` #40 0.3.0 -> `1289053` D-0090 memory-arch -> <this fold-docs commit>; confirm with `git log -1`).** No LIVE `res.lease` held (durable `gpu-*.fence/.state/.txn` siblings persist by design -- NOT held); heartbeat `degraded:false`; 0 UNMANAGED `llama-server`/python. Slots 001/002/003 EMPTY (i31 brief archived at `archive/fanout-agents/i31-SELECTION-POLICY-SETTLE.md`; ship-state `fanout/SELECTION-POLICY-SETTLE-i31-SHIP-STATE.md`). Start at section 2, then i32 Tier-0 (section 4).

--- superseded i30 box detail follows: ---

Iterations 1-29 DONE; **i30 = the CONTRACT-HARDENING wave DONE (D-0087 contract + D-0088 conformance):** context_packet/0.2 (NEW `core-docs/CONTEXT_PACKET_CONTRACT.md` + MEMORY_CONTRACT A2/A3) + the 3-lane CPU conformance wave (plan `fo-30-dd453156`, GPU lane skipped) -- #40 context.compiler **0.2.0** (`f06e6e7`) + #37 retrieval.eval **0.3.0** (`99bb627`; NEW `lib/selpol_rrf_v1.py`) + #41 skill.card **0.2.0** (`54c2e79`). The D-0077 fold PASSED the #41->#36->#40 chain (40/40 summary ingested; a record_kind=skill search returns 0 #41 records; a valid context_packet/0.2 with P0-1 control/evidence separation, P0-3 disposition=answerable, P0-4 consumer_profile+transport, non_execution=true; 0 orphans) and CAUGHT the selpol pair-1 divergence (see section 4). **NEXT = i31 SELECTION-POLICY SETTLE** (pin CONTEXT_PACKET_CONTRACT s4 + re-ship #40 to import #37's canonical selpol; then the deferred P1-2..P1-9 + P2 + the P0-1 adversarial suite). HEAD = the i30 fold-docs commit on top of `99bb627` (chain `d4cfadc` i30-slots -> `54c2e79` #41 -> `f06e6e7` #40 -> `99bb627` #37 -> <this fold-docs commit>; confirm with `git log -1`). No LIVE `res.lease` held (durable `gpu-*.fence/.state/.txn` siblings persist by design -- NOT a held lease); heartbeat `degraded:false`; 0 UNMANAGED `llama-server`/python. Slots 001/002/003 EMPTY (i30 briefs archived at `archive/fanout-agents/i30-*.md`). Start at section 2, then i31 (section 4) on Nicholas's approval.

--- superseded i29 box detail: ---

Iterations 1-28 DONE; **i29 = the WAVE 3 wave DONE (D-0086):** context compiler + skill retrieval SHIPPED (plan fo-29-87dbfa0b; 3-lane CPU, GPU lane skipped) -- NEW context.compiler #40 0.1.0 (`b89eda0`; deterministic `lifeorch.context_packet/0.1`) + retrieval.eval #37 0.1.0->0.2.0 (`dc293ef`; s6 eval-0.2 + a deterministic reranker) + NEW skill.card #41 0.1.0 (`1eafd2c`). The orchestrator D-0077 fold smoke PASSED on real data: #41->#36 `ingest-records` 40 accepted/0 rejected (FTS text); #36 retriever-0.2->#40 `compile` a real context_packet/0.1 (3 excerpts, ALL provenance-reproduced against chunk_content_hash, budget 1190/1200); #36->#37 0.2 -Live recall@1/MRR/nDCG@3=1.0; P0-5 sklcard_/derived vs skl_/canonical_source COEXIST no collision; 0 orphans. The frontier design red-team (pack d57fead3) FOLDED -- GO for the read-only build, NO-GO for FREEZING the new contracts, NO-GO for side-effecting use until the SAFETY-CRITICAL P0-1 (control-plane-vs-evidence separation; a hard gate before Priority-8 action-capable integration). **NEXT = i30 CONTRACT-HARDENING** (fold P0-1..P0-5 + P1-1 into a MEMORY_CONTRACT/context_packet 0.2 amendment + #41 skill->summary + one selection-policy lib; digest `research/2026-08-02-frontier-wave3-design-redteam.md`). --- superseded i28 box detail: --- MEMORY_CONTRACT Amendment A1 (record-envelope v0.1 -> v0.1.1 -- envelope `status`/`currentness` = a single s5 STRING [`current` baseline; the `{state,stale_reasons,verified}` object RETIRED]; `record_kind` enum CLOSED, `episode_stage` NOT a kind) + episode.record #39 0.1.0 -> **0.1.1** (`3dab699`; status -> the s5 string; per-stage detail folded into `episode.body.stage_sequence` + `has_stage` child_edges; extractor+skill 0.1.1; suite 114 -> 123 green, byte-identical cross-env). The orchestrator D-0077 re-smoke PASSED 30/30: episode.record 0.1.1 fed RAW into #36 0.2 `ingest_records` -- would_bridge dropStage=0/coerceStatus=0 (0 bridging), episode+failure accepted with 0 rejections, NO `episode_stage` emitted or stored, provenance span reproduces source, idempotent (catalog_digest stable), 0 orphans. **The two i27 divergences are RESOLVED.** HEAD (i29) = the i29 fold-docs commit on top of `b89eda0` (chain `6d9da94` i29-slots -> `1eafd2c` #41 -> `dc293ef` #37 -> `b89eda0` #40 -> <this fold-docs commit>; confirm with `git log -1`). No LIVE `res.lease` held (durable `gpu-*.fence/.state/.txn` siblings persist by design -- NOT a held lease); heartbeat `degraded:false`; 0 UNMANAGED `llama-server`/python.

**Direction = the Collective Agent (cognitive virtual memory), D-0080.** Wave 1 (i25 D-0082) + the contract freeze (i26 D-0083, `MEMORY_CONTRACT.md` -> v0.1.1 via i28 A1) + Wave 2 (i27 D-0084) + the i28 contract-settle (D-0085) are DONE. **NEXT = Wave 3 (context compiler + skill-card/registry + retrieval reranker)** -- every Wave-3 producer/consumer split builds to MEMORY_CONTRACT 0.2/v0.1.1 and gets the D-0077 cross-module smoke at fold. **Warm pool + durable supervisor stay DEFAULT-OFF + FROZEN** (D-0079 GATE-NO). Also frozen: generators, `video.interpret` + live composition, real-time perception (arch 27-49), broad training. **Doc debt:** the hot docs (CURRENT_STATE / MODULE_ROADMAP / this handoff / DECISION_LOG_INDEX) remain over budget -- a full slim pass is still a named unit (i28 kept its edits tight but did not do a full slim). Slots 001/002/003 EMPTY (i28 brief archived at `archive/fanout-agents/i28-EPISODE-CONFORM.md`; ship-state `fanout/CONTRACT-SETTLE-i28-SHIP-STATE.md`). Start at section 2, then Wave 3 (section 4) on Nicholas's approval.
