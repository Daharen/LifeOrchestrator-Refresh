# FAN-OUT ORCHESTRATOR HANDOFF

**This is the ONE live handoff doc.** Rewritten IN PLACE at the end of every orchestrator session (snapshot the outgoing version to `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF-<tag>.md` FIRST -- `DOC_PROTOCOL.md` s5). Dated handoff docs are retired; content lives here + `CURRENT_STATE.md` + `archive/handoffs/`.

**You are the fan-out orchestrator** -- the ONE Claude instance that scopes work units, drives `orchestrate.fanout` (#30) to emit worker prompts, and hands them to Nicholas, who dispatches each into a FRESH Cowork session. You NEVER drive another *external/frontier* AI session (the hard D-0051 boundary, as amended by D-0080) -- every lane is human-dispatched; the frontier lane is a human-couriered pack (D-0052). Whether in-session cloud subagents fall inside the boundary is an OPEN Nicholas ruling (mandate 02 M2-E).

## 0. TL;DR

- **i40 (the SUNSET session) CLOSED (D-0110/D-0111/D-0112). HEAD = the i40 close commit (confirm `git log -1`).** Pre-wave: **mandate 01 SUNSETTED** -- the mandatory metastability report was delivered BEFORE wave work (`core-docs/research/2026-08-06-process-mandate-01-report.md`, verdict **NO**) and Nicholas **LICENSED mandate 02** in place (opened i40, **sunset i47**; M2-A = BUILD the fail-closed doc gate, **DEADLINE the i42 close**; M2-D = **verification-before-ratification STRUCTURAL**; M2-E = the subagent-boundary ruling, open; D-0110). PB-3 acute slim executed (CURRENT_STATE 185%->96%, MODULE_ROADMAP 132%->77%, this handoff at this close; snapshots in `archive/doc-snapshots/2026-08-06/`). Wave `fo-40-d42fd1ac` (2-lane CPU, D-0111): **Lane B** #37 retrieval.eval **0.8.1** (`6c7269d`; PB-5 CLOSED -- WIRED_STRUCTURAL_DIGEST re-pinned `sha256:d0d54aba..e450`, wired rehearsal 11/11 + hpr 117647 ppm; version SINGLE SOURCE = skill.json w/ a permanent -Live envelope==manifest drift assertion proven-to-fire; orchestrator independent re-run ALL PASS). **Lane A** #43 action.authz **0.4.0** (`663145b`, 16 files) -- the 7 **D-0109 EXACT CLOSURES** built to the letter via an **ORCHESTRATOR-RECOVERED SHIP** (the worker's bridge died BEFORE PUSH; Nicholas resumed the session to re-push; the orchestrator ran gates + devship + filed the report). Verified: suite x2 exit 0 (fixtures 86/86, properties 26/26, mutations 67/67, fuzzer 400/0, oracle 149 rows not_run=0-GATING, role 30/30 over ALL 15 frozen sinks, completion 17/17, views 48/48, authentic 0.7.0+0.9.0 chain 7/7), DOUBLE-RUN bundle byte-identical, Finding-7 EMPTY-DIR SELF-VERIFY VERIFIED (bundle `f0964b53`), D-0077 fold harness exit 0, i34 smoke 38/38. **M2-D HELD: `p0_1_gate_status=incomplete` in every emitted artifact; `exact_closure_built` 7/7 carries the claim.** **The ROUND-3 review RETURNED FAIL (D-0113, pack `5807bc3e`, folded post-close): s7 NOT ratified -- and for the FIRST time nothing was walked back (M2-D meant no pass was claimed). F3 + F6 ACCEPTED CLOSED; F2/F4 partially accepted; 5 SUITE-BUILD findings remain -> i41 unit-0** (`research/2026-08-06-i40-p01gate-round3-redteam.md`): PermitStore WRITE-ONCE completion binding; a CONSUMED TargetHandle capability (+ kill the blind-copy+tag mutant); a LOSSLESS 0.9.0 adapter (per-identity-field mutation properties + round-trip); OPERATIONAL top-level GrantView enforcement; COMPLETE pack transport (the i40 pack omitted WORK_ORDER.md -- an ORCHESTRATOR packaging miss; re-pack from the suite's required-file manifest + empty-dir pre-verify before couriering).
- **DIRECTION (D-0080/D-0090): build the Collective Agent (cognitive virtual memory)** over the Tier-0..3 plan (`MEMORY_ARCHITECTURE.md`). Tier-1 ACCEPTED (i36). FROZEN: supervisor/warm-pool (D-0079 GATE-NO), generators, `video.interpret` + live composition, real-time perception, broad training.
- **STANDING RULE (D-0077):** parallel isolated workers building a schema PRODUCER + CONSUMER against a shared design doc REQUIRE an orchestrator cross-module smoke at fold BEFORE close.
- **MANDATE 02 (live):** at session start update the countdown (`current_iteration` / `iterations_to_sunset`; i41 -> 41/6) + a one-line status per M2-item; M2-A has a HARD i42 deadline -- **i41 must scope the doc-gate build or record why not**.
- Workers use `docs:[]`; YOU mirror core-docs under the `git` lease (s7); doc rules in `DOC_PROTOCOL.md`. Deliver prompts/packets/packs to Nicholas as FILES; briefs also go in `core-docs/fanout/FANOUT_AGENT_00N.md` (s5). Slots 001/002/003 RESET to EMPTY at this close (i40 briefs -> `archive/fanout-agents/i40-*.md`).
- Box state at handoff: s11.

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit lock, `doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize). The module emits prompts; Nicholas starts a fresh session per worker; workers report; the orchestrator mirrors core-docs. <=1 GPU worker per wave, ALWAYS. Ship every unit via `dev.ship`. No automated external-AI access (D-0051/D-0052).

## 2. First 15 minutes: orient + verify the box

Read (Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/CURRENT_STATE.md` (gotcha corpus = its Known failures), THIS doc, `core-docs/PROCESS_MANDATE.md` (mandate 02: run the s1 per-session check FIRST), `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (MaxParallel 3 = 1 GPU + 2 CPU ceiling). Doc edits: `DOC_PROTOCOL.md`. Memory subsystem authorities: `MEMORY_CONTRACT.md` + `CONTEXT_PACKET_CONTRACT.md` + `MEMORY_ARCHITECTURE.md`. Action layer: `ACTION_AUTHORIZATION_CONTRACT.md` (FROZEN, D-0103; s7 = the gate-status record).

Verify the box (`device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`, `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> no LIVE lease expected (durable `gpu-*.fence/.state/.txn` siblings persist by design).
- `git log -1 --format='%h %s'` -> HEAD matches s11 (read-only git over the mount; ALL git writes via the executor).
- `pgrep -x llama-server; pgrep -x python` -> none (0 UNMANAGED orphans).
`device_bash` is a Linux VM (UTC timestamps; CANNOT run Windows pwsh -- use `exec-job.sh`, s7). git log renders LOCAL (PDT) times -- do not mix the two when reasoning about recency (the i40 lesson).

## 3. Where things stand

**Now:** modules 0-34 + memory #35-#43 + widgets 01-07 built; 40 fan-out iterations run; Tier-1 ACCEPTED (i36); the P0-1 deny-by-default gate is BUILT + exact-closure-complete, `p0_1_gate_status=incomplete` PENDING the round-3 ratification review (M2-D); the Governor `-AutoRamp` default-ON; the 9B Q5_K_M strong tier GPU-resident on b10092; warm pool + durable supervisor default-OFF + FROZEN (D-0079).

**Iteration ledger** (one line each; detail = the D-entry; older lines in `archive/handoffs/`):

- **i1-i24 (D-0055..D-0081):** pre-memory infra + video arc -- res.lease + frontier.bridge + executor/watchdog + Governor + warm-pool arc (GATE-NO at i24) + video spine #32/#33/#34 + the GPU-lease split R1a/R1b/R1b' + widgets 01-04.
- **i25-i33 (D-0082..D-0097):** the memory-substrate arc -- Waves 1-3 (#35/#36/#37/#38/#39/#40/#41), MEMORY_CONTRACT + CONTEXT_PACKET_CONTRACT freezes + A1-A5, selpol settle, Tier-0 seam repairs (ns-closure + supersession).
- **i34 (D-0098/99):** Tier-1 hierarchy slice (#36 0.5.0 + #40 0.6.0 + #37 0.6.0) + NEW #42 working.memory; fold smoke 38/38.
- **i35 (D-0100):** consumer wiring -- #40 0.7.0 public hierarchy port + #37 0.7.0 rehearsal harness.
- **i36 (D-0102):** **TIER-1 ACCEPTED** (11/11 s10 over a foreign corpus); #37 0.8.0 wired-descend + #36 0.6.0 get-record + NEW widgets/05.
- **i37 (D-0103/04):** ACTION_AUTHORIZATION_CONTRACT FROZEN + NEW #43 P0-1 monitor MVP + #40 0.8.0 R-1 router; fold 13/13.
- **i38 (D-0105/06/07):** #43 0.2.0 full-gate build + #40 0.9.0 wm-hydration + NEW widgets/06; fold 18/18; **pass over-claimed -> walked back (D-0107)**.
- **i39 (D-0108/09):** #43 0.3.0 gate-completion + #36 0.7.0 fast-beam (hpr 58823->117647 ppm) + NEW widgets/07 (audit A2); fold 18/18; **pass over-claimed AGAIN -> walked back (D-0109)**; #37 reconcile deferred = PB-5.
- **i40 (D-0110/11/12):** **SUNSET** -- mandate-01 report (verdict NO) -> **mandate 02 licensed**; PB-3 slim; wave `fo-40-d42fd1ac`: #43 **0.4.0** the 7 D-0109 exact closures (orchestrator-recovered ship; M2-D held, gate stays `incomplete`) + #37 **0.8.1** (PB-5 closed); fold green; **round-3 ratification pack `5807bc3e` couriered**.

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` · artifacts `.../runtime/artifacts/<id>/` · leases `.../29-resource-lease/runtime/leases/`. Waves + ad-hoc commits share one counter; **the next wave is iteration 41.**

## 4. Current frontier -- NEXT = i41

**i41 unit-0 (BLOCKING for the gate): the 5-findings #43 lane (0.4.0 -> 0.5.0)** -- the round-3 review returned FAIL (D-0113; the digest `research/2026-08-06-i40-p01gate-round3-redteam.md` is the SPEC; build to its per-finding "Exact closure required" blocks): (1) PermitStore completion binding WRITE-ONCE per permit_id (reject ANY second recording incl. identical; immutable/defensive-copy representation; sentinel-overwrite / binding-overwrite / getter-mutation / duplicate-recording vectors); (2) the captured target = a distinct trusted TargetHandle object the effect-applicator API REQUIRES; the ledger generated from the handle-bound applicator result (never from `authorized_effect_set`); one-shot/observably-consumed handles; a KILLED blind-copy+tag mutant; (3) a LOSSLESS context_packet/0.2 adapter (complete packet or canonical bytes + validated view; per-identity-field mutation properties -- any change alters the preserved identity or fails closed; round-trip equivalence; overlay flips ONLY non_execution); (4) OPERATIONAL top-level GrantView closed-set enforcement (validate exact field set/types before matching; reject unknown/missing/mistyped; vectors; pin the validator); (5) the M2-D rule UNCHANGED (worker emits `incomplete` + per-finding flags; no pass claim). AT FOLD the orchestrator RE-PACKS from the suite's OWN required-file manifest (incl. `WORK_ORDER.md`, digest 36e713da..) and EXTRACTS+RUNS the pack from an EMPTY DIR before couriering; s7 ratifies ONLY on the next PASS, naming the pack id.

**i41 unit-1 (mandate M2-A -- HARD DEADLINE i42): scope the deterministic fail-closed doc-hygiene commit gate.** Wired into the executor doc-commit path; density check + proportional budget + re-layer trigger (D-0094); reuse `ops/audit/gen-doc-health.py` budget parsing; first real firing logged = acceptance. i41 must scope it (a lane or an orchestrator unit) or record why not at the mandate s1 check.

**Other i41 candidates** (<=1 GPU; MaxParallel <=3; distinct modules; docs:[]): (a) the #40 beam-WIDTH fast-beam follow-on (i39 Lane B measured upper-level Bloom saturation; a #40 unit, NOT #36); (b) the Widget 05/06/07 human live-GUI confirms (D-0064, Nicholas); (c) M2-C first increment -- the docs-into-memory re-layer design note (after M2-A ships); (d) MODULE_ROADMAP/registry currency touch-ups; (e) PB-4 next audit increment per its cadence header.

**Lanes** (up to FOUR per wave; any may be skipped; every lane human-dispatched): GPU lane (<=1, HARD CLAMP; only it touches model modules / `models.json`; leases gpu->git) · CPU lane(s) + coding lane (distinct modules; lease git) · frontier-review lane (off-box, OPTIONAL; a #31 pack couriered by Nicholas; no lease).

**Clamps.** <=1 GPU worker; 1 GPU + 2 CPU = MaxParallel 3 validated ceiling; `git` lease serialises commits; `docs:[]` -> doc contention 0. Persistent llama-servers DETACHED + reaped; 0-UNMANAGED-orphan check every wave. Producer/consumer pairs across workers REQUIRE the D-0077 fold smoke.

**Wave loop:** mandate s1 check -> scope lanes (+ optional frontier topic) -> fill `FANOUT_AGENT_00N` slots (s5) -> author `workers-i<N>.json` + `task-plan-i<N>.ps1` (copy `task-plan-i40.ps1`; `-Iteration <N> -MaxParallel <=3`; `gpu:true` only on the GPU worker) -> run `plan`; confirm `dispatch_now` / <=1 gpu / 0 doc contention / clean preflight -> emit any frontier pack -> relay the check-in + worker prompts + pack as FILES + slot docs -> workers run + report -> poll `-Action status -PlanId <id>` until `ready_for_handoff` -> `-Action handoff` -> VERIFY commits via NATIVE git -> run the fold smoke the wave's shape demands -> fold, mirror core-docs under the `git` lease, archive used briefs + reset slots -> **regenerate the doc-health monitor** (`python ops/audit/gen-doc-health.py --date <today>`; SendUserFile + create_artifact the HTML) -> iterate.

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template `FANOUT_AGENT_TEMPLATE.md`; mirrored at `claude/fanout/`): fill a slot at wave scoping (paste the `plan`-emitted worker prompt, or a tight summary + a pointer to the emitted copy when over the 8 KB slot budget -- the i40 Lane-A pattern), mirror it, and Nicholas dispatches a fresh session with "Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant (s10). Slot docs also travel as FILES. On completion: archive to `archive/fanout-agents/i<N>-<slot>.md`, reset EMPTY, re-mirror (lifecycle: `DOC_PROTOCOL.md` s6). **Slots were archived + RESET at the i40 close.**

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/` + `ops/` + `archive/`. The Project mirrors `core-docs/` (map: `DOC_PROTOCOL.md` s8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-module model homes; `_engines\llama.cpp` (b8661 default) + `llama.cpp-b10092` (the 9B only).
- **Executor:** `modules\00-bootstrap-executor\runtime\`; driven via `exec-job.sh`. Heartbeat: `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Action layer:** `modules/43-action-authz/` (0.4.0; SCHEMA_NOTES = canonical views; tests/report/ = the regenerable evidence bundle; fixtures/real_packets/ = the authentic 0.7.0+0.9.0 packets).
- **Memory subsystem:** `modules/35-*..42-*`; per-module `SCHEMA_NOTES.md` = contract interpretation; `MEMORY_CONTRACT.md` + `CONTEXT_PACKET_CONTRACT.md` = field authorities.
- **Video spine:** `modules/32/33/34`. **Warm pool (FROZEN):** `modules/07-model-gateway/WARM_POOL_DESIGN.md` s10.
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB, i9-9900KF, 64 GB RAM, Win10 Pro. Full profile: `TOOL_MODEL_REGISTRY.md`.

## 7. Mechanics cheat-sheet

- **Run pwsh via the executor** (from `device_bash`): write a `task.ps1` under `modules/30-orchestrate-fanout/runtime/`, then `bash modules/00-bootstrap-executor/exec-job.sh run <id> <timeout> <task.ps1> <maxwait> "<desc>"`. Long jobs: re-run `exec-job.sh wait <id>` (device_bash caps ~45 s). Verbs: `submit|wait|run|devship|status`. AVOID inline printf-quoting for ps1 with quotes/parens -- write the file in cloud, ship it (the i40 lesson).
- **Cloud -> device:** `SendUserFile` + `device_commit_files` (byte-exact; <=20 MB/file). `device_bash` cannot delete -- `mv` into a `_to_delete\` folder.
- **Device -> cloud reads:** `device_stage_files` (FRESH never-staged paths only -- re-staging returns a STALE snapshot; can 403 `session_stale_relogin`). Fallback: tar+base64 via device_bash.
- **Ship a unit:** `exec-job.sh devship <id> <inputs.json> <timeout>` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers). **VERIFY the real HEAD via native git, NOT the dev.ship `committed` field** (D-0072).
- **Author a plan:** `workers-i<N>.json` + `task-plan-i<N>.ps1`; `-Action status` polls; `-Action handoff` emits the Verification Console packet. If `status` returns no artifact, read `plans/<id>/reports/` directly.
- **Frontier pack:** #31 `pack` takes `{prompt, question?, paths?}`; Nicholas couriers; the answer goes BETWEEN the two `<<<FRONTIER-BRIDGE-ANSWER-...>>>` markers (keep the `<!-- pack_id -->` line); `read-return -ReturnFile <path> -ExpectPackId <id>` -> fold into a research digest. **A review pack that claims runnability must be GENERATED from the suite's own required-file manifest (never hand-enumerated -- the i40 pack omitted WORK_ORDER.md) and EXTRACTED+RUN from an empty dir BEFORE couriering (D-0113).**
- **Doc edits + mirror (EOL-safe, fail-closed):** core-docs are CRLF (some module docs LF -- preserve per-file EOL). Pull fresh bytes, edit in cloud, `device_commit_files` back, commit via an executor task: acquire `git` lease -> `git reset -q` -> `git add -- <named>` -> assert the staged set -> `git commit -F <msg>` -> release. Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>` + `Claude-Session: <url>`. NEVER `git add -A`. Re-mirror via `project_write local_path`.
- **DECISION_LOG upkeep:** append the D-entry at the bottom + ONE compressed routing row to `DECISION_LOG_INDEX.md`; mark superseded predecessors in the index row only. CURRENT_STATE: REPLACE sections, never `[prior]` chains.
- **Deliver everything to Nicholas as FILES** (SendUserFile).

## 8. Worker-spec rules

- `docs:[]` on EVERY worker; <=1 GPU worker; model modules `parallel_safe:false`; ONLY the GPU lane touches `models.json`.
- Distinct module/area per worker. A schema PRODUCER + CONSUMER may run parallel-isolated ONLY with (a) one governing design doc, (b) per-module SCHEMA_NOTES records, (c) the orchestrator D-0077 fold smoke.
- Correct `inputs` per skill_id; a brand-new module has no skill.json -- OMIT skill_id/skill_dir.
- **Single-worker waves for core infra** (executor/watchdog, dev.ship, orchestrate.fanout, res.lease, the gateway supervisor).
- Leases in gpu -> git -> doc order; ONE unit; ship via dev.ship; `-Action report -State done`. A live proof whose harness acquires the real gpu leases must NOT wrap an outer whole-task gpu lease (i21).

## 9. Gotchas (the load-bearing set -- full corpus: `CURRENT_STATE.md` -> Known failures)

- **The wedge (D-0055/56):** a task BLOCKING while holding a persistent llama-server orphans it + livelocks the executor while the heartbeat stays fresh. Launch DETACHED; reap before finalize; if wedged, kill out-of-band (Task Manager).
- **A worker's bridge can die BEFORE its first push (i40):** the work then exists ONLY in that worker's session -- the box shows NOTHING. Verify what actually LANDED via NATIVE git status/log (mount mtimes mislead: `ls` shows UTC, git log shows LOCAL/PDT). Recovery: Nicholas resumes the worker session to re-push its files; the orchestrator runs gates + devship + files the report on its behalf (record the recovery in the commit + report).
- **`device_stage_files` stale snapshot:** re-staging a previously-staged path returns OLD bytes; stage FRESH paths only.
- **A long-running supervisor keeps OLD module code (i21):** restart before live checks. Driver 591.74 SPILLS an over-size model to system RAM -- "it loaded" != "it fits"; the measured-PEAK `required_vram` gate is the only admission control.
- **Per-file EOL:** core-docs CRLF; some module docs LF. Match the existing EOL.
- **Git discipline:** read-only git over the mount (ignore the CRLF-noise M-list -- REAL tracked-file edits hide inside it; native git via the executor is the truth); all writes through the executor under the `git` lease; NEVER `git add -A`; dev.ship can FALSE-NEGATIVE `committed` (verify native HEAD; clear a stale 0-byte `.git/index.lock` via an executor task).
- **pwsh 7.4.6 determinism traps:** `[System.Array]::Sort(object[], Comparison[string])` sorts a COPY (cast `[string[]]` first); empty-array unroll (`$x=@()` first); `,$out` double-wrap; `@($list)` on a `List[object]` of pscustomobjects throws; `$var:` in double-quoted strings -> `${var}`; child-process pipe deadlock -> drain both async; `[Console]::Out` bypasses capture. Keep double-run byte-identity gates in every canonical-bytes module.
- **Deliver files, not paths**; keep `-MaxParallel` at 3 until the heartbeat proves more.

## 10. Required access (grant at session start)

Every orchestrator AND worker session needs exactly ONE grant: **the repo folder `C:\Users\just_\LifeOrchestrator-Refresh`** (desktop "Add folder" or device_request_folder_access). F: is reached natively by the Windows executor. Machine prerequisite: the executor running (`ops/start-executor.bat` or the watchdog), heartbeat fresh + `degraded:false`. Computer-use (Task Manager) only for out-of-band wedge recovery.

## 11. Box state at handoff (2026-08-06, D-0112 -- i40 CLOSED)

**i40 closed: the SUNSET session (mandate-01 report -> mandate 02 licensed, D-0110) + the 2-lane exact-closure wave (D-0111/D-0112) + the PB-3 slim.** HEAD = the i40 close commit (chain: `08c6812` sunset -> `7af1ac6` open -> `e3b1171` slim -> `6c7269d` #37 0.8.1 -> `663145b` #43 0.4.0 -> the D-0112 close commit; confirm the tip with `git log -1`). Shipped + verified (detail: D-0112): #43 **0.4.0** (16 files; the 7 D-0109 exact closures; orchestrator-recovered ship after the worker's bridge died pre-push; suite x2 exit 0 + double-run byte-identical + empty-dir self-verify VERIFIED; **taxonomy `build_complete | p0_1_gate_status=incomplete | activation=prohibited` -- M2-D held**) + #37 **0.8.1** (5 files; PB-5 CLOSED; digest re-pin + version single-source + the permanent drift assertion; independent re-run ALL PASS). Fold: D-0077 harness vs the 0.4.0 monitor exit 0 + i34 smoke 38/38 + plan handoff emitted (verification packet `artifacts/d1b92f18-*`). **The round-3 pack `5807bc3e` answer RETURNED + FOLDED post-close (D-0113): FAIL -- s7 NOT ratified; F3/F6 accepted closed; 5 suite-build findings -> i41 unit-0 (the #43 0.5.0 lane); contract s7 carries the D-0113 fold-block + updated footer; NO walk-back was needed (M2-D).** Doc-health regenerated post-slim (over-budget 4 -> 2 pre-close; this handoff rewrite closes the last red). No held res.lease (durable `gpu-e3c5ba51.*` siblings persist by design); heartbeat `degraded:false`; 0 UNMANAGED orphans; the only untracked scratch is `_to_delete_w07/` + `modules/43-action-authz/_to_delete/` (Nicholas deletes). **Mandate 02 countdown = 40/7 (i41 decrements to 41/6; M2-A deadline i42).** Slots 001/002/003 EMPTY (i40 briefs archived). **NEXT = i41** (section 4).

Prior box states + full historical iteration lines: `archive/handoffs/`.

## 12. Worker model tiering (D-0114 -- refresh roster/prices each session)

Nicholas picks each worker's model at dispatch; the orchestrator RECOMMENDS one per lane (check-in + brief header). Roster @2026-08-07 ($/MTok in/out; cache-read 0.1x in): Sonnet 5 High 2/10 (3/15 from Sep 1) | Opus 4.8 Extra 5/25 (Opus 5 = same price) | Fable 5 Max 10/50 (orchestrator seat).

- **DEFAULT lane = Sonnet 5 High:** exact-spec'd + suite-gated fail-closed + not ratification-critical (doc/registry currency, tooling w/ reference impl, widgets, bounded increments) -- the verification structure is model-independent.
- **ELEVATE to Opus 4.8 Extra** on ANY: prior review FAIL/walk-back on the module (#43 NOW); frozen-contract or core-infra semantics; design-vs-closure work; 2 in-lane gate failures. De-elevate after 2 first-pass ships.
- **Fable 5 Max workers: effectively NEVER.** A premium-demand small-diff unit runs ORCHESTRATOR-INLINE (context already cached at 0.1x; a fresh premium worker re-pays orientation as novel input) -- the i40 recovered-ship shape; else an Opus worker.
- **FANOUT STAYS** (no serial consolidation): fresh narrow contexts + the independent-grader boundary caught D-0107/D-0109; only micro-units run inline. REWORK, not per-token price, dominates cost -- never downgrade the lane whose failure forces another review round.
