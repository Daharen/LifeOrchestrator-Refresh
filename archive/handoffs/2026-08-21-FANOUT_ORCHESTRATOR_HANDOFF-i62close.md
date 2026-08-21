# FAN-OUT ORCHESTRATOR HANDOFF

**This is the ONE live handoff doc.** Rewritten IN PLACE at the end of every orchestrator session (snapshot the outgoing version to `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF-<tag>.md` FIRST -- `DOC_PROTOCOL.md` s5). Dated handoff docs are retired; content lives here + `CURRENT_STATE.md` + `archive/handoffs/`.

**You are the fan-out orchestrator** -- the ONE Claude instance that scopes work units, drives `orchestrate.fanout` (#30) to emit worker prompts, and hands them to Nicholas, who dispatches each into a FRESH Cowork session. You NEVER drive another *external/frontier* AI session (the hard D-0051 boundary, as amended by D-0080) -- every lane is human-dispatched; the frontier lane is a human-couriered pack (D-0052). In-session cloud subagents ARE inside the boundary (D-0119, Nicholas); the frontier lane stays human-couriered.

## 0. TL;DR

- **i61 CLOSED (D-0160): bounded-ingest ADOPTION PROVED (rigorously session-bound) + the close-path gate RAISED** -- a genuinely fresh PCB-booted subagent (immutable manifest sha256-sealed before its first read) did representative work bounded-by-default (discretionary fraction 1.0 >= 0.80 frozen; ZERO whole-doc opens; trial-binding-check bound=true, unbacked=0) -> **F-i53-eff CLOSED**; supersedes the D-0158 proof (reopened D-0159). `ops/close-refold.ps1` hardened (fail-closed `-Ledger`/`-Iteration`/`-MinBoundedFraction` before render; MANAGER_VIEW + cross-surface consistency wired into the close). i60 delivered A/B/C/D (D-0156). **NEXT = i62 = PB-9 resumable close TRANSACTION** (first class migration -> i68). Slots 001/002/003 EMPTY. AUDIT review_due i62. Seat = Opus 4.8 (settled).
- **DIRECTION (D-0080/D-0090): build the Collective Agent (cognitive virtual memory)** over the Tier-0..3 plan (`MEMORY_ARCHITECTURE.md`). Tier-1 ACCEPTED (i36). FROZEN: supervisor/warm-pool (D-0079 GATE-NO), generators, `video.interpret` + live composition, real-time perception, broad training.
- **STANDING RULE (D-0077):** parallel isolated workers building a schema PRODUCER + CONSUMER against a shared design doc REQUIRE an orchestrator cross-module smoke at fold BEFORE close.
- **NO live mandate** (mandate-02 SUNSET i47, D-0132, verdict YES). Surviving controls: the M2-A commit gate, deterministic PB triggers, cadence headers, the monitor, and **SEALED_CHECK_47** (evaluate ONLY at iteration >= 54; a pre-i54 session leaves it sealed). M2-D verification-before-ratification stays standing practice.
- Workers use `docs:[]`; YOU mirror core-docs under the `git` lease (s7); doc rules in `DOC_PROTOCOL.md`. Deliver prompts/packets/packs to Nicholas as FILES; briefs also go in `core-docs/fanout/FANOUT_AGENT_00N.md` (s5). Slots 001/002/003 EMPTY (PB-7 design shipped i55; PB-6 built+wired i56/i57; i60 = bounded-ingest + control-plane hardening).
- Box state at handoff: s11.

## 1. Role + hard boundary (non-negotiable)

`orchestrate.fanout` (#30) is deterministic scaffolding on `res.lease` (#29): a `gpu` lease, a `git` commit lock, `doc:<path>` ownership. YOU supply judgement (what the units are, when to fan out vs serialize). The module emits prompts; Nicholas starts a fresh session per worker; workers report; the orchestrator mirrors core-docs. <=1 GPU worker per wave, ALWAYS. Ship every unit via `dev.ship`. No automated external-AI access (D-0051/D-0052).

## 2. First 15 minutes: orient + verify the box

BOOT via the kernel (`START_HERE.md` -> verify the PCB -> open `BOOT_PACKET.md` -> progressive disclosure); open a whole doc ONLY with an explicit reason (F-i53-eff). Deeper refs as needed (Project mirrors these; disk canonical): `core-docs/CURRENT_STATE.md`, `core-docs/CURRENT_STATE.md` (gotcha corpus = its Known failures), THIS doc, `core-docs/SEALED_CHECK_47.md` (SEALED -- act on it only at iteration >= 54), `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` (MaxParallel 3 = 1 GPU + 2 CPU ceiling). Doc edits: `DOC_PROTOCOL.md`. Memory subsystem authorities: `MEMORY_CONTRACT.md` + `CONTEXT_PACKET_CONTRACT.md` + `MEMORY_ARCHITECTURE.md`. Action layer: `ACTION_AUTHORIZATION_CONTRACT.md` (FROZEN, D-0103; s7 = the gate-status record). PCB boot surface: the START_HERE KERNEL -> `BOOT_PACKET.md`, the DEFAULT bootstrap since i53 (D-0146); expand by progressive disclosure (`card:`/`section:`/`--q`), NOT whole-doc reads (F-i53-eff -- a whole-doc open needs an explicit reason).

Verify the box (`device_bash`, `cd ~/mnt/LifeOrchestrator-Refresh`):
- `cat modules/00-bootstrap-executor/runtime/control/heartbeat.json` -> `at_utc` fresh, `degraded:false`, `poll_error_streak:0`, `stuck_finalize_count:0`.
- `ls modules/29-resource-lease/runtime/leases/` -> no LIVE lease expected (durable `gpu-*.fence/.state/.txn` siblings persist by design).
- `git --no-optional-locks log -1 --format='%h %s'` -> HEAD matches s11 (read-only git over the mount; ALL git writes via the executor; plain `git status` on the mount can strand a `.git/index.lock` -- ALWAYS pass `--no-optional-locks` for mount-side reads).
- `pgrep -x llama-server; pgrep -x python` -> none (0 UNMANAGED orphans).
`device_bash` is a Linux VM (UTC timestamps; CANNOT run Windows pwsh -- use `exec-job.sh`, s7; CANNOT DELETE files -- `rm`/`rmtree` = EPERM on the mount, so any op that deletes or tempdirs, incl. #44 `ingest-claims`/`render --check`, runs via the executor). git log renders LOCAL (PDT) times -- do not mix with UTC `ls` when reasoning about recency (the i40 lesson).

## 3. Where things stand

**Now:** modules 0-34 + memory #35-#43 + **#44 project.map 0.4.1 (PCB)** + widgets 01-08 built; 60 fan-out iterations run; Tier-1 ACCEPTED (i36); the P0-1 gate is a RATIFIED DESIGN pass (`p0_1_gate_status=pass`, D-0118; activation PROHIBITED); the doc-gate LIVE; `-AutoRamp` default-ON; the 9B GPU-resident on b10092; warm pool FROZEN (D-0079). **i49 = the N1 efficiency mechanisms + fold (D-0138); i48 = the CD closures + re-check FAIL (D-0135/36); i47 = mandate-02 SUNSET + migration gate CONDITIONAL (D-0132/33).**

**Iteration ledger** (one line each; detail = the D-entry; older lines in `archive/handoffs/`):

- **i1-i45 (D-0055..D-0129):** pre-memory infra + video arc + memory-substrate arc (**TIER-1 ACCEPTED i36, D-0102**) + the ACTION_AUTHORIZATION freeze + #43 MVP->0.6.0 (**round-5 PASS / s7 RATIFIED, D-0118**) + M2-A doc gate + MODEL-TIERING (D-0114) + widgets/05-08 + LRAP/poser + the P0-1 over-claim/walk-back arc (D-0107/09); detail in the D-entries + archive/handoffs/.
- **i46-i57 (D-0130..D-0151) -- the PCB build + PB-6 arc (detail = D-entries):** #44 built 0.1.0->0.4.0 (i47 mandate-02 SUNSET; i51 gate NO-GO; i52 N5-N8 fix); **i53 fresh two-class gate GO (D-0146): the PCB packet is the DEFAULT bootstrap (F-i53-eff: prefer `section:`/`card:`);** i54 SEALED_CHECK_47 evaluated (SP3 FAIL, seal RETAINED, M-03 DEFERRED); i55-i57 PB-6 decision re-layer DESIGNED->BUILT->BOOT-WIRED (COMPLETE; #45 + #40 verb 0.10.0, `d16cdc0`).
- **i58 (D-0153): the universal derived-front-door contract FROZEN + 3-adversary red-teamed** -> hardened s8 AUTHORITATIVE (7 breaks; CB1 kernel-recovery + CB4 cross-front-door-currency ratification-blocking); 3 digests `research/2026-08-15-i58-*.md`. Design/freeze wave, no module code.
- **i59 (D-0154): the ROOT front-door migration SHIPPED** -- START_HERE -> boot KERNEL + NEW `COLD_BOOT_CARD.md` (generator-independent survivor) + NEW `ops/frontdoor/` uniform rebuild interface (registry + driver + frontdoor-gate) + the migration gate; 3-adversary red-teamed (architecture HELD, 13 gaps folded: rebuild-once->Mode-B, pinned survivor slot, frozen-redirect active-work, K_max doc bound, fail-closed-by-DETECTION close); DOC_PROTOCOL s2 front-door amendment; driver proven green (root-pcb 0-stale). Doc/ops close, no module code. **+ i59 reconciliation (D-0155): control-plane truth reconciled + the i60-i79 rolling roadmap; i60 = bounded-ingest + control-plane hardening; first class migration -> i68.**

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` * artifacts `.../runtime/artifacts/<id>/` * leases `.../29-resource-lease/runtime/leases/`. Waves + ad-hoc commits share one counter; **the next wave is iteration 62.**

## 4. Current frontier -- i61 CLOSED (D-0160): NEXT = i62 = PB-9 resumable close transaction; AUDIT review_due i62; SP3/M-03 open (M-03 NOT licensed)

**i61 CLOSED (D-0160): bounded-ingest ADOPTION PROVED + the close-path gate RAISED.** A genuinely fresh PCB-booted subagent (immutable manifest sha256-sealed BEFORE its first read) answered the frozen Q1-Q6 suite bounded-by-default: discretionary fraction **1.0 >= 0.80** (frozen), **ZERO whole-doc opens**, evidence rigorously bound (`trial-binding-check.py` bound=true over a session-unique artifact root; unbacked=0, no foreign-HEAD) -> **F-i53-eff CLOSED**, superseding D-0158 (query-string matching across accumulated artifacts; reopened D-0159) and RESOLVING that reconciliation residual. The wired close-path gate is RAISED off the zero floor to the meaningful-fraction gate (`-MinBoundedFraction`), failing the close BEFORE render on a missing/malformed/zero-bounded/sub-threshold ledger; MANAGER_VIEW + consistency WIRED into the fold. **NEXT = i62 = PB-9 resumable close TRANSACTION (D-0155):** consolidate the close into ONE manifest-driven resumable transaction so it cannot half-land; design-first -> red-team. First PB-7 class migration DEFERS to **i68**. Roadmap: `research/2026-08-15-i59-roadmap-reconciliation.md`. AUDIT review_due i62; SEALED_CHECK_47 retained; #40 beam-width / PB-2 / w08 deferred (D-0134).

**Lanes** (up to FOUR per wave; any may be skipped; every lane human-dispatched): GPU lane (<=1, HARD CLAMP; only it touches model modules / `models.json`; leases gpu->git) · CPU lane(s) + coding lane (distinct modules; lease git) · frontier-review lane (off-box, OPTIONAL; a #31 pack couriered by Nicholas; no lease).

**Clamps.** <=1 GPU worker; 1 GPU + 2 CPU = MaxParallel 3 validated ceiling; `git` lease serialises commits; `docs:[]` -> doc contention 0. Persistent llama-servers DETACHED + reaped; 0-UNMANAGED-orphan check every wave. Producer/consumer pairs across workers REQUIRE the D-0077 fold smoke.

**Wave loop:** (iteration >= 54? run SEALED_CHECK_47 first) -> scope lanes (+ optional frontier topic) -> fill `FANOUT_AGENT_00N` slots (s5) -> author `workers-i<N>.json` + `task-plan-i<N>.ps1` (copy `task-plan-i48.ps1`; `-Iteration <N> -MaxParallel <=3`; `gpu:true` only on the GPU worker) -> run `plan`; confirm `dispatch_now` / <=1 gpu / 0 doc contention / clean preflight -> emit any frontier pack -> relay the check-in + worker prompts + pack as FILES + slot docs -> workers run + report -> poll `-Action status -PlanId <id>` until `ready_for_handoff` -> `-Action handoff` -> VERIFY commits via NATIVE git -> run the fold smoke the wave's shape demands -> fold, mirror core-docs under the `git` lease, archive used briefs + reset slots -> **N7 close-refold (D-0143): after the LAST doc commit, `ops/close-refold.ps1` verify->review->fold via the executor; map/+generated/ = the FINAL close commit; accept 0 stale on boot_read at HEAD** -> **regenerate BOTH monitors** (`python ops/audit/gen-doc-health.py --date <today>` + the retrieval `--gate` fail-closed via `ops/close-refold.ps1 -Ledger <session-ledger> -Iteration <N>` (D-0157 -- emits the retrieval-bytes-log row + ABORTS a zero-bounded close), D-0149; SendUserFile + create_artifact the doc-health HTML) -> re-mirror core-docs to the Project -> **re-push the GitHub mirror** (`git push --force-with-lease origin main` via the executor, D-0149) -> iterate.

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template `FANOUT_AGENT_TEMPLATE.md`; mirrored at `claude/fanout/`): fill a slot at wave scoping (paste the emitted worker prompt, or a summary + pointer when over the 8 KB budget -- i40/i48), mirror it, and Nicholas dispatches a fresh session with "Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant (s10). Slot docs also travel as FILES. On completion: archive to `archive/fanout-agents/i<N>-<slot>.md`, reset EMPTY, re-mirror (lifecycle: `DOC_PROTOCOL.md` s6). **Slot 003 archived (`i52-003`) + RESET at the i52 close.**

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

## 11. Box state at handoff (2026-08-17, D-0160 i61 re-close)

**i61 CLOSED (D-0160): bounded-ingest ADOPTION proved (F-i53-eff CLOSED, rigorously session-bound) + the close-path retrieval gate RAISED to the meaningful-fraction gate; close-refold hardened + MANAGER_VIEW/consistency wired.** No module code changed by the i61 close (ops/doc). iteration 61/next 62. The proof binds to an immutable manifest + session-unique root (trial-binding-check bound=true, unbacked=0). Prior: i60 delivered bounded-ingest A/B/C/D (D-0156); the i60-i79 roadmap stands; first class migration DEFERS to i68.

**i59: the ROOT front-door migration SHIPPED (orchestrator-inline, Opus 4.8 seat) -- D-0154.** Doc/ops close (no module code, no GPU): START_HERE -> boot kernel; NEW `core-docs/COLD_BOOT_CARD.md`; NEW `ops/frontdoor/` uniform rebuild interface (registry + driver + frontdoor-gate) + the migration gate; DOC_PROTOCOL s2 front-door amendment. 3-adversary red-teamed (architecture HELD; 13 gaps folded); driver proven GREEN (root-pcb 0-stale, 18033 B packet) via the executor. The map claim added the `COLD_BOOT_CARD` doc entity + updated `START_HERE` one_line (--override); the N7 close-refold restamped the map at HEAD (0 stale on boot_read); overlay frontier -> i60; both monitors regenerated; core-docs re-mirrored; GitHub mirror re-pushed. No held res.lease; heartbeat degraded:false; 0 UNMANAGED orphans; doc-gate + frontdoor-gate PASS on the boot-surface commit. **Open Nicholas items: i62 = PB-9 resumable close TRANSACTION (design-first -> red-team); the first class migration DEFERS to i68. SP3/M-03: SP3 FAIL (integrity intact); M-03 NOT licensed (P0-1 FROZEN).** The w08 window-close defect stays routed to the next w08 touch (D-0134).

## 12. Worker model tiering (D-0114 -- refresh roster/prices each session)

Nicholas picks each worker's model at dispatch; the orchestrator RECOMMENDS one per lane (check-in + brief header). Roster @2026-08-07 ($/MTok in/out; cache-read 0.1x in): Sonnet 5 High 2/10 (3/15 from Sep 1) | Opus 4.8 Extra 5/25 | Fable 5 Max 10/50 (EXPLICIT Nicholas direction only -- D-0116). **Opus 5: effectively NEVER (Nicholas i52/D-0144 -- marginal gain over 4.8 Extra at ~2x tokens); escalation above Opus 4.8 Extra = Fable 5 ONLY, explicitly justified (for a gate: frozen at staging).**

- **DEFAULT lane = Sonnet 5 High:** exact-spec'd + suite-gated fail-closed + not ratification-critical (doc/registry currency, tooling w/ reference impl, widgets, bounded increments) -- the verification structure is model-independent.
- **ELEVATE to Opus 4.8 Extra** on ANY: prior review FAIL/walk-back on the module; frozen-contract or core-infra semantics; design-vs-closure work; 2 in-lane gate failures. De-elevate after 2 first-pass ships.
- **ORCHESTRATOR SEAT = Fable 5 UNTIL Nicholas declares settled (D-0134, standing); on "settled", revert to the D-0116 Opus 4.8 Extra default.** Inline premium-demand units run on the seat model.
- **Fable 5 Max workers: effectively NEVER.** A premium-demand small-diff unit runs ORCHESTRATOR-INLINE (context already cached at 0.1x; a fresh premium worker re-pays orientation as novel input) -- the i40/i48 recovered-ship + inline-fix shape; else an Opus worker.
- **FANOUT STAYS** (no serial consolidation): fresh narrow contexts + the independent-grader boundary caught D-0107/D-0109; only micro-units run inline. REWORK, not per-token price, dominates cost -- never downgrade the lane whose failure forces another review round.
