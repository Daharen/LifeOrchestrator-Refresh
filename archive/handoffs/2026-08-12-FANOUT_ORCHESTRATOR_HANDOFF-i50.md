# FAN-OUT ORCHESTRATOR HANDOFF

**This is the ONE live handoff doc.** Rewritten IN PLACE at the end of every orchestrator session (snapshot the outgoing version to `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF-<tag>.md` FIRST -- `DOC_PROTOCOL.md` s5). Dated handoff docs are retired; content lives here + `CURRENT_STATE.md` + `archive/handoffs/`.

**You are the fan-out orchestrator** -- the ONE Claude instance that scopes work units, drives `orchestrate.fanout` (#30) to emit worker prompts, and hands them to Nicholas, who dispatches each into a FRESH Cowork session. You NEVER drive another *external/frontier* AI session (the hard D-0051 boundary, as amended by D-0080) -- every lane is human-dispatched; the frontier lane is a human-couriered pack (D-0052). In-session cloud subagents ARE inside the boundary (D-0119, Nicholas); the frontier lane stays human-couriered.

## 0. TL;DR

- **i49 CLOSED (D-0138). HEAD = the i49 fold commit `c0c3abe` (map+generated; ship `5d46731`; confirm `git log -2`).** The N1 wave `fo-49-655c25df` (ONE coding lane, Opus, dispatched into the held i48-SPARE-W session) shipped **#44 `project.map` 0.2.0 -> 0.3.0** = the D-0136 efficiency mechanisms: **N1** the L2 narrative query surface (`entity --fields purpose --harvest` serves a manifest field FROM the harvest, bounded; NEW closed verb `section:<id>#<heading>` fetches ONE named SCHEMA_NOTES section, resolves a deeper[schema-notes] pointer), **N2** overlay `frontier.candidates[]` rich {item, gate, pointer} in the BOOT_PACKET OVERLAY (empty = byte-identical to 0.2.0; degrades BEFORE OPERATIONS), **N3** the RETRIEVAL PROTOCOL verb table from a single QUERY_VERBS declaration (test-asserted == dispatcher). Suite 130/130 x3 interpreters + the WindowsApps python-stub trap fixed. **ORCHESTRATOR FOLD:** 7 content-verified mechanical reaffirms + module:44 version harvest-synced 0.3.0 + the N2 overlay (iteration 49, 7 candidates) -> **VALIDATE 0**; render BOOT_PACKET 16,640 B <= 20,000 (authority-table trim only, OPERATIONS LAST); `-Live Folded` green; independent fold replays reproduced (purpose 5662/5659/5663 B <= 6000 vs the 478,784 B grep; #36 section 7684 B). **THE LEGACY BOOTSTRAP (this doc) REMAINS DEFAULT; N4 bar re-freeze = a Nicholas-ratification act before any fresh gate.** **Seat = Fable 5 until Nicholas declares settled (D-0134).**
- **DIRECTION (D-0080/D-0090): build the Collective Agent (cognitive virtual memory)** over the Tier-0..3 plan (`MEMORY_ARCHITECTURE.md`). Tier-1 ACCEPTED (i36). FROZEN: supervisor/warm-pool (D-0079 GATE-NO), generators, `video.interpret` + live composition, real-time perception, broad training.
- **STANDING RULE (D-0077):** parallel isolated workers building a schema PRODUCER + CONSUMER against a shared design doc REQUIRE an orchestrator cross-module smoke at fold BEFORE close.
- **NO live mandate** (mandate-02 SUNSET i47, D-0132, verdict YES). Surviving controls: the M2-A commit gate, deterministic PB triggers, cadence headers, the monitor, and **SEALED_CHECK_47** (evaluate ONLY at iteration >= 54; a pre-i54 session leaves it sealed). M2-D verification-before-ratification stays standing practice.
- Workers use `docs:[]`; YOU mirror core-docs under the `git` lease (s7); doc rules in `DOC_PROTOCOL.md`. Deliver prompts/packets/packs to Nicholas as FILES; briefs also go in `core-docs/fanout/FANOUT_AGENT_00N.md` (s5). Slots 001/002/003 EMPTY (003 filled + archived `i49-003` + reset at the i49 close).
- Box state at handoff: s11.

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit lock, `doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize). The module emits prompts; Nicholas starts a fresh session per worker; workers report; the orchestrator mirrors core-docs. <=1 GPU worker per wave, ALWAYS. Ship every unit via `dev.ship`. No automated external-AI access (D-0051/D-0052).

## 2. First 15 minutes: orient + verify the box

Read (Project mirrors these; disk is canonical): `core-docs/START_HERE.md`, `core-docs/CURRENT_STATE.md` (gotcha corpus = its Known failures), THIS doc, `core-docs/SEALED_CHECK_47.md` (SEALED -- act on it only at iteration >= 54), `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (MaxParallel 3 = 1 GPU + 2 CPU ceiling). Doc edits: `DOC_PROTOCOL.md`. Memory subsystem authorities: `MEMORY_CONTRACT.md` + `CONTEXT_PACKET_CONTRACT.md` + `MEMORY_ARCHITECTURE.md`. Action layer: `ACTION_AUTHORIZATION_CONTRACT.md` (FROZEN, D-0103; s7 = the gate-status record). PCB boot surface: `modules/44-project-map/generated/BOOT_PACKET.md` (0.2.0; NOT yet the default bootstrap).

Verify the box (`device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`, `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> no LIVE lease expected (durable `gpu-*.fence/.state/.txn` siblings persist by design).
- `git --no-optional-locks log -1 --format='%h %s'` -> HEAD matches s11 (read-only git over the mount; ALL git writes via the executor; plain `git status` on the mount can strand a `.git/index.lock` -- ALWAYS pass `--no-optional-locks` for mount-side reads).
- `pgrep -x llama-server; pgrep -x python` -> none (0 UNMANAGED orphans).
`device_bash` is a Linux VM (UTC timestamps; CANNOT run Windows pwsh -- use `exec-job.sh`, s7; CANNOT DELETE files -- `rm`/`rmtree` = EPERM on the mount, so any op that deletes or tempdirs, incl. #44 `ingest-claims`/`render --check`, runs via the executor). git log renders LOCAL (PDT) times -- do not mix with UTC `ls` when reasoning about recency (the i40 lesson).

## 3. Where things stand

**Now:** modules 0-34 + memory #35-#43 + **#44 project.map 0.3.0 (PCB)** + widgets 01-08 built; 49 fan-out iterations run; Tier-1 ACCEPTED (i36); the P0-1 gate is a RATIFIED DESIGN pass (`p0_1_gate_status=pass`, D-0118; activation PROHIBITED); the doc-gate LIVE; `-AutoRamp` default-ON; the 9B GPU-resident on b10092; warm pool FROZEN (D-0079). **i49 = the N1 efficiency mechanisms + fold (D-0138); i48 = the CD closures + re-check FAIL (D-0135/36); i47 = mandate-02 SUNSET + migration gate CONDITIONAL (D-0132/33).**

**Iteration ledger** (one line each; detail = the D-entry; older lines in `archive/handoffs/`):

- **i1-i37 (D-0055..D-0104):** pre-memory infra + video arc + the memory-substrate arc + **TIER-1 ACCEPTED i36 (D-0102)** + the ACTION_AUTHORIZATION freeze + NEW #43 MVP + widgets/05; detail in the D-entries + archive/handoffs/.
- **i38 (D-0105/06/07):** #43 0.2.0 + #40 0.9.0 + NEW widgets/06; **pass over-claimed -> walked back (D-0107)**.
- **i39 (D-0108/09):** #43 0.3.0 + #36 0.7.0 fast-beam + NEW widgets/07; **pass over-claimed AGAIN -> walked back (D-0109)**.
- **i40 (D-0110/11/12):** mandate-01 report NO -> **mandate 02 licensed**; `fo-40-d42fd1ac`: #43 **0.4.0** (7 exact closures, orchestrator-recovered) + #37 **0.8.1**; round-3 pack couriered.
- **i41 (D-0114/15):** MODEL-TIERING (D-0114) + M2-A scoped; `fo-41-35be4fdc`: #43 **0.5.0** (4 round-3 closures) + F7 MECHANIZED; round-4 post-close FAIL -> 3 findings (D-0116).
- **i42 (D-0117):** `fo-42-e5403d74`: **M2-A the doc-hygiene commit gate SHIPPED** + **#43 0.6.0** (3 round-4 closures); folds green; **round-5 PASS -> s7 RATIFIED (D-0118; P0-1 arc closes)**.
- **i43/i44 (D-0120/21):** NO code waves -- widgets 05/06/07 live-GUI confirm + the expert-forensic finding -> **LRAP** (P9); AUDIT_PIPELINE promoted to core-docs.
- **i45 (D-0122..D-0129):** LRAP wave `fo-45-b17a531e` -- NEW widgets/08 (87/0/0; leveled accept) + the poser arc.
- **i46 (D-0130/31):** the PCB wave `fo-46-6dd32d37` (2 CPU lanes) -- NEW modules/44 project.map 0.1.0; D-0077 fold 143/98, validate 0; the I47 gate packet FROZEN (EVAL_SHA `0bcb5e7`).
- **i47 (D-0132/33):** NO code wave -- mandate-02 SUNSET (YES -> SEALED_CHECK_47 armed, open i>=54) + the FROZEN migration gate EXECUTED (T1; blind KEEP C1/C2, swap-stable; B run-1 VOID wrong-grant -> one clean re-run; efficiency VOID via RT2-F9) -> **CONDITIONAL**: legacy STAYS default; CD-1/2/3 named in `modules/44-project-map/eval/results/I47_RESULTS.md`.
- **i48 (D-0135):** the CD-path wave `fo-48-3d3a4e1b` (1 coding lane, Opus) -- #44 **0.2.0**: CD-1 OPERATIONS boot canon + CD-3 query surface -- **ORCHESTRATOR-RECOVERED ship `c451890`** (worker session had no pwsh/executor; files independently verified pre-ship) + **the harvest sunset-fix `4055dc1`** (inline; 93->98) + fold (reaffirms/prunes/+6 entities/overlay i48/2 corrections) -> **VALIDATE 0**; render + `-Live Folded` green (fold commit); **re-check RUN + FAILED same-session (D-0136): void x2, B 1.24x A; legacy stays default**.
- **i49 (D-0138):** the N1 wave `fo-49-655c25df` (1 coding lane, Opus) -- #44 **0.2.0 -> 0.3.0**: N1 narrative query surface (purpose + SCHEMA_NOTES section) + N2 overlay frontier richness + N3 verb-table (single-source, dispatcher-asserted); ship `5d46731`; fold VALIDATE 0 (7 reaffirms + version-sync + iteration-49 overlay) + render 16,640 B + `-Live Folded` green (fold `c0c3abe`); independent replays reproduced. Legacy stays default; N4 (bar re-freeze) = a Nicholas-ratification act, not yet run.

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` · artifacts `.../runtime/artifacts/<id>/` · leases `.../29-resource-lease/runtime/leases/`. Waves + ad-hoc commits share one counter; **the next wave is iteration 50.**

## 4. Current frontier -- NEXT = i50 (N4 ratification staging / the deferred menu)

**i49 CLOSED (D-0138): the N1 wave shipped #44 0.3.0 and folded 0-findings** -- the D-0136 economics findings F1/F3/F4 are closed at query granularity (module purposes + SCHEMA_NOTES sections + the query verbs are now bounded queries, not raw-store fallback). Independent fold replays: module 36/37/40 purpose 5662/5659/5663 B (<= 6000; vs the 478,784 B harvest grep) + #36 fast-beam section 7684 B (<= 8000; 'beam' + the #40-ownership statement) + verb-table == dispatcher + CD-3 probes resolve. **The migration gate stays CONDITIONAL: the frozen s7 bars are arithmetically dead post-CD-1 (D-0136), so N4 = a BOOT/total-bar RE-FREEZE drafted for Nicholas ratification at the next gate staging -- NO fresh legacy-vs-PCB gate before N4; the LEGACY handoff stays the default bootstrap.** Both i48 A/B packs double as design input for the eventual #40 beam-width wave.

**Deferred menu (D-0134, deferred NOT dropped):** (b) AUDIT_PIPELINE next_increment (front step + ride-along + OUTPUT side; design-first -> red-team; **review_due i54, D-0137 override**; + the w08 explain-window-close defect rides the next w08 touch, D-0064 live-GUI cycle) · (c) M2-C/FO-3 + DECISION_MEMORY RE-LAYER (D-0139/PB-6): the INDEX is now GROWTH-EXEMPT (per-row density guards, no whole-file cap); scalable selective decision retrieval deferred, rides the memory re-layer · (d) #40 beam-WIDTH · (e) PB-2 (trigger-gated). **P0-1 ACTIVATION stays FROZEN. SEALED_CHECK_47 is NOT evaluated before i54.**

**Lanes** (up to FOUR per wave; any may be skipped; every lane human-dispatched): GPU lane (<=1, HARD CLAMP; only it touches model modules / `models.json`; leases gpu->git) · CPU lane(s) + coding lane (distinct modules; lease git) · frontier-review lane (off-box, OPTIONAL; a #31 pack couriered by Nicholas; no lease).

**Clamps.** <=1 GPU worker; 1 GPU + 2 CPU = MaxParallel 3 validated ceiling; `git` lease serialises commits; `docs:[]` -> doc contention 0. Persistent llama-servers DETACHED + reaped; 0-UNMANAGED-orphan check every wave. Producer/consumer pairs across workers REQUIRE the D-0077 fold smoke.

**Wave loop:** (iteration >= 54? run SEALED_CHECK_47 first) -> scope lanes (+ optional frontier topic) -> fill `FANOUT_AGENT_00N` slots (s5) -> author `workers-i<N>.json` + `task-plan-i<N>.ps1` (copy `task-plan-i48.ps1`; `-Iteration <N> -MaxParallel <=3`; `gpu:true` only on the GPU worker) -> run `plan`; confirm `dispatch_now` / <=1 gpu / 0 doc contention / clean preflight -> emit any frontier pack -> relay the check-in + worker prompts + pack as FILES + slot docs -> workers run + report -> poll `-Action status -PlanId <id>` until `ready_for_handoff` -> `-Action handoff` -> VERIFY commits via NATIVE git -> run the fold smoke the wave's shape demands -> fold, mirror core-docs under the `git` lease, archive used briefs + reset slots -> **regenerate the doc-health monitor** (`python ops/audit/gen-doc-health.py --date <today>`; SendUserFile + create_artifact the HTML) -> iterate.

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template `FANOUT_AGENT_TEMPLATE.md`; mirrored at `claude/fanout/`): fill a slot at wave scoping (paste the emitted worker prompt, or a summary + pointer when over the 8 KB budget -- i40/i48), mirror it, and Nicholas dispatches a fresh session with "Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant (s10). Slot docs also travel as FILES. On completion: archive to `archive/fanout-agents/i<N>-<slot>.md`, reset EMPTY, re-mirror (lifecycle: `DOC_PROTOCOL.md` s6). **Slots were archived + RESET at the i48 close.**

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/` + `ops/` + `archive/`. The Project mirrors `core-docs/` (map: `DOC_PROTOCOL.md` s8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-module model homes; `_engines\llama.cpp` (b8661 default) + `llama.cpp-b10092` (the 9B only).
- **Executor:** `modules\00-bootstrap-executor\runtime\`; driven via `exec-job.sh`. Heartbeat: `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Action layer:** `modules/43-action-authz/` (0.6.0; SCHEMA_NOTES = canonical views; tests/report/ = the regenerable evidence bundle; fixtures/real_packets/ = the authentic 0.7.0+0.9.0 packets).
- **Memory subsystem:** `modules/35-*..42-*`; per-module `SCHEMA_NOTES.md` = contract interpretation; `MEMORY_CONTRACT.md` + `CONTEXT_PACKET_CONTRACT.md` = field authorities.
- **PCB:** `modules/44-project-map/` (0.2.0; `map/` = canonical state, `generated/` = rendered views incl. BOOT_PACKET, `claims/` = the judgment layer, `eval/results/` = the I47 gate record).
- **Video spine:** `modules/32/33/34`. **Warm pool (FROZEN):** `modules/07-model-gateway/WARM_POOL_DESIGN.md` s10.
- **Box:** `DESKTOP-PF5FFMF` -- RTX 2080 Ti 11 GB, i9-9900KF, 64 GB RAM, Win10 Pro. Full profile: `TOOL_MODEL_REGISTRY.md`.

## 7. Mechanics cheat-sheet

- **Run pwsh via the executor** (from `device_bash`): write a `task.ps1` under `modules/30-orchestrate-fanout/runtime/`, then `bash modules/00-bootstrap-executor/exec-job.sh run <id> <timeout> <task.ps1> <maxwait> "<desc>"`. Long jobs: re-run `exec-job.sh wait <id>` (device_bash caps ~45 s). Verbs: `submit|wait|run|devship|status`. AVOID inline printf-quoting for ps1 with quotes/parens -- write the file in cloud, ship it (i40). **In executor-task pwsh, NEVER `Write-Output` diagnostics inside a function whose return you capture -- the pipeline swallows them (i48); redirect op envelopes to files (`1> runtime\x.json`) and print via python.**
- **Cloud -> device:** `SendUserFile` + `device_commit_files` (byte-exact; <=20 MB/file). **`device_bash` CANNOT delete** (mount EPERM) -- `mv` into `_to_delete\`; any deleting/tempdir op (incl. #44 ingest/render/--check, shutil.rmtree) runs via the executor python (i48).
- **Device -> cloud reads:** `device_stage_files` (FRESH never-staged paths only -- re-staging returns a STALE snapshot; can 403 `session_stale_relogin`). Fallback: tar+base64 via device_bash.
- **Ship a unit:** `exec-job.sh devship <id> <inputs.json> <timeout>` (sha256 + AST + tests FAIL-CLOSED, named files only, trailers). **VERIFY the real HEAD via native git, NOT the dev.ship `committed` field** (D-0072).
- **Author a plan:** `workers-i<N>.json` + `task-plan-i<N>.ps1`; `-Action status` polls; `-Action handoff` emits the Verification Console packet. If `status` returns no artifact, read `plans/<id>/reports/` directly.
- **Frontier pack:** #31 `pack` takes `{prompt, question?, paths?}`; Nicholas couriers; the answer goes BETWEEN the two `<<<FRONTIER-BRIDGE-ANSWER-...>>>` markers (keep the `<!-- pack_id -->` line); `read-return -ReturnFile <path> -ExpectPackId <id>` -> fold into a research digest. **A review pack that claims runnability must be GENERATED from the suite's own required-file manifest and EXTRACTED+RUN from an empty dir BEFORE couriering (D-0113).**
- **#44 map ops (fold):** run via the BOX python (s2 delete rule). Ingest FAIL-CLOSED on a full staged-tree validate -> order: overlay/reaffirms FIRST, then ingest; re-claiming a held field needs `--override '<reason>'` (recorded); fold corrections ship as `claims/<file>-foldfix.json`, never edits to the original (i46/i48).
- **Doc edits + mirror (EOL-safe, fail-closed):** core-docs are CRLF (some module docs LF -- preserve per-file EOL). Pull fresh bytes, edit in cloud, `device_commit_files` back, commit via an executor task: acquire `git` lease -> `git reset -q` -> `git add -- <named>` -> assert the staged set -> `git commit -F <msg>` -> release. Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>` + `Claude-Session: <url>`. NEVER `git add -A`. **The fail-closed doc-gate runs on every core-doc commit** (pre-commit hook + `doc-commit-gate.py --files <named set>`): a hot doc over its s2 budget is REJECTED -- slim it or `GATE_OVERRIDE: D-####` (real D, logged).
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
- **A worker session may lack pwsh/executor entirely (i48) or its bridge may die pre-push (i40):** verify what LANDED via NATIVE git; the orchestrator runs gates + devship + files the report on the worker's behalf, recording the recovery. An honest worker leaves the commit to the executor -- that is DONE-minus-ship, not failure.
- **`device_stage_files` stale snapshot:** re-staging a previously-staged path returns OLD bytes; stage FRESH paths only.
- **Mount git + deletes (i47/i48):** mount git = LOG-ONLY with `--no-optional-locks` (plain `git status` strands `.git/index.lock`); the mount VM CANNOT delete (EPERM) -- deleting/tempdir ops run via the executor.
- **A long-running supervisor keeps OLD module code (i21):** restart before live checks. Driver 591.74 SPILLS an over-size model to system RAM -- "it loaded" != "it fits"; the measured-PEAK `required_vram` gate is the only admission control.
- **Per-file EOL:** core-docs CRLF; some module docs LF. Match the existing EOL.
- **Git discipline:** all writes through the executor under the `git` lease; NEVER `git add -A`; dev.ship can FALSE-NEGATIVE `committed` (verify native HEAD; clear a stale 0-byte `.git/index.lock` via an executor task).
- **pwsh 7.4.6 determinism traps:** `[System.Array]::Sort(object[], Comparison[string])` sorts a COPY (cast `[string[]]` first); empty-array unroll (`$x=@()` first); `,$out` double-wrap; `@($list)` on a `List[object]` of pscustomobjects throws; `$var:` in double-quoted strings -> `${var}`; child-process pipe deadlock -> drain both async; `[Console]::Out` bypasses capture; function-return pipeline swallows Write-Output (i48). Keep double-run byte-identity gates in every canonical-bytes module.
- **Deliver files, not paths**; keep `-MaxParallel` at 3 until the heartbeat proves more.

## 10. Required access (grant at session start)

Every orchestrator AND worker session needs exactly ONE grant: **the repo folder `C:\Users\just_\LifeOrchestrator-Refresh`** (desktop "Add folder" or device_request_folder_access). F: is reached natively by the Windows executor. Machine prerequisite: the executor running (`ops/start-executor.bat` or the watchdog), heartbeat fresh + `degraded:false`. Computer-use (Task Manager) only for out-of-band wedge recovery. The i47/i48-style eval sessions instead get ONLY the eval-folder grant (packet s2 isolation).

## 11. Box state at handoff (2026-08-12, D-0138 -- i49 CLOSED)

**i49 closed: the ship `5d46731` (#44 0.2.0 -> 0.3.0, Opus worker in i48-SPARE-W) -> the fold commit `c0c3abe` (map+generated; confirm `git log -2`).** Plan `fo-49-655c25df`: 1 worker, report filed (`done`, honest, matches git). Orchestrator fold on-box: 7 reaffirms + version-sync + iteration-49 overlay -> VALIDATE 0; render + --check + verify green; 130/130 + -Live Folded. No held res.lease (durable `gpu-*` siblings persist by design); heartbeat `degraded:false`; 0 UNMANAGED orphans. Doc-gate PASS on the docs-close. Slots EMPTY (003 archived `i49-003`). **Open Nicholas items: N4 bar re-freeze ratification (before any fresh gate) + the deferred-menu pick for i50.** The w08 explain-window-close defect stays routed to the next w08 touch (D-0134).

## 12. Worker model tiering (D-0114 -- refresh roster/prices each session)

Nicholas picks each worker's model at dispatch; the orchestrator RECOMMENDS one per lane (check-in + brief header). Roster @2026-08-07 ($/MTok in/out; cache-read 0.1x in): Sonnet 5 High 2/10 (3/15 from Sep 1) | Opus 4.8 Extra 5/25 (Opus 5 = same price) | Fable 5 Max 10/50 (EXPLICIT Nicholas direction only -- D-0116).

- **DEFAULT lane = Sonnet 5 High:** exact-spec'd + suite-gated fail-closed + not ratification-critical (doc/registry currency, tooling w/ reference impl, widgets, bounded increments) -- the verification structure is model-independent.
- **ELEVATE to Opus 4.8 Extra** on ANY: prior review FAIL/walk-back on the module; frozen-contract or core-infra semantics; design-vs-closure work; 2 in-lane gate failures. De-elevate after 2 first-pass ships.
- **ORCHESTRATOR SEAT = Fable 5 UNTIL Nicholas declares settled (D-0134, standing); on "settled", revert to the D-0116 Opus 4.8 Extra default.** Inline premium-demand units run on the seat model.
- **Fable 5 Max workers: effectively NEVER.** A premium-demand small-diff unit runs ORCHESTRATOR-INLINE (context already cached at 0.1x; a fresh premium worker re-pays orientation as novel input) -- the i40/i48 recovered-ship + inline-fix shape; else an Opus worker.
- **FANOUT STAYS** (no serial consolidation): fresh narrow contexts + the independent-grader boundary caught D-0107/D-0109; only micro-units run inline. REWORK, not per-token price, dominates cost -- never downgrade the lane whose failure forces another review round.
