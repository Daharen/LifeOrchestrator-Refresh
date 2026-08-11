# FAN-OUT ORCHESTRATOR HANDOFF

**This is the ONE live handoff doc.** Rewritten IN PLACE at the end of every orchestrator session (snapshot the outgoing version to `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF-<tag>.md` FIRST -- `DOC_PROTOCOL.md` s5). Dated handoff docs are retired; content lives here + `CURRENT_STATE.md` + `archive/handoffs/`.

**You are the fan-out orchestrator** -- the ONE Claude instance that scopes work units, drives `orchestrate.fanout` (#30) to emit worker prompts, and hands them to Nicholas, who dispatches each into a FRESH Cowork session. You NEVER drive another *external/frontier* AI session (the hard D-0051 boundary, as amended by D-0080) -- every lane is human-dispatched; the frontier lane is a human-couriered pack (D-0052). In-session cloud subagents ARE inside the boundary (D-0119, Nicholas); the frontier lane stays human-couriered.

## 0. TL;DR

- **i46 CLOSED (D-0130/D-0131). HEAD = the i46 close pair: ONE docs commit + the FINAL map/eval commit (confirm `git log -2`).** i46 was DIRECTIVE-HIJACKED (Nicholas's comprehension/bootstrap reconstruction directive): SHIPPED NEW **`modules/44-project-map` (`project.map` 0.1.0) -- the Project Comprehension Bootstrap (PCB)**: deterministic fail-closed system map + L1 cards + a generated <=20 KB `BOOT_PACKET.md` (closed namespaces resolve the module-vs-arch-position collision; per-FIELD provenance; fail-closed; judgment ONLY via validated claims; 2 red-teams, 44 findings folded -- `modules/44-project-map/design/`). Wave `fo-46-6dd32d37`: Lane B claims `b4ce6ab` (142 entities/98 edges/11 uncertain); Lane A build ORCHESTRATOR-RECOVERED to `11416a8` (the i40 pattern; stale index.lock cleared; 2 fold-fixes: tests-wrapper $live/[switch]$Live case-collision + entrypoint WindowsApps python-stub). Independent on-box re-verify: 49/49 cloud + -Live smoke + selftest OK. Fold: refused-then-corrected ingest (the fail-closed path proven live) -> 143/98, validate **0 findings**; BOOT_PACKET rendered. **THE LEGACY BOOTSTRAP (this doc) REMAINS DEFAULT (control condition).** **NEXT = i47 in ORDER: the mandate-02 SUNSET REPORT, then the FROZEN legacy-vs-PCB migration-gate experiment (`modules/44-project-map/eval/I47_EVAL_PACKET.md`; EVAL_SHA `0bcb5e7`), then GO/CONDITIONAL/NO-GO for i48.** Open with Nicholas: the LRAP poser live-click confirm (D-0129) + _to_delete_w07 (D-0120). (Detail: s3 ledger.)
- **DIRECTION (D-0080/D-0090): build the Collective Agent (cognitive virtual memory)** over the Tier-0..3 plan (`MEMORY_ARCHITECTURE.md`). Tier-1 ACCEPTED (i36). FROZEN: supervisor/warm-pool (D-0079 GATE-NO), generators, `video.interpret` + live composition, real-time perception, broad training.
- **STANDING RULE (D-0077):** parallel isolated workers building a schema PRODUCER + CONSUMER against a shared design doc REQUIRE an orchestrator cross-module smoke at fold BEFORE close.
- **MANDATE 02 (live -- SUNSETS AT i47):** the i47 session sets current_iteration 47 -> REPORT_DUE and produces the s3 report BEFORE wave work (PROCESS_MANDATE s1/s3). Status at i46 close: M2-A SHIPPED + firing; M2-B held mechanically (INDEX at its cap = the standing re-layer signal); M2-C materially advanced by the PCB (design s6; FO-3 = map->#36 records); M2-D/M2-E RESOLVED. Countdown closed 46/1.
- Workers use `docs:[]`; YOU mirror core-docs under the `git` lease (s7); doc rules in `DOC_PROTOCOL.md`. Deliver prompts/packets/packs to Nicholas as FILES; briefs also go in `core-docs/fanout/FANOUT_AGENT_00N.md` (s5). Slots 001/002/003 EMPTY (002/003 filled + archived + reset at the i46 close; 001 unused).
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

**Now:** modules 0-34 + memory #35-#43 + NEW **#44 project.map (PCB)** + widgets 01-08 built; 46 fan-out iterations run; Tier-1 ACCEPTED (i36); the P0-1 gate is a RATIFIED DESIGN pass (`p0_1_gate_status=pass`, D-0118; activation PROHIBITED); the doc-gate LIVE (M2-A); `-AutoRamp` default-ON; the 9B GPU-resident on b10092; warm pool FROZEN (D-0079). **i46 SHIPPED the PCB (D-0130/31, TL;DR); i45 = LRAP + the poser arc (D-0122..D-0129); i44 = AUDIT_PIPELINE promotion (D-0121).**

**Iteration ledger** (one line each; detail = the D-entry; older lines in `archive/handoffs/`):

- **i1-i24 (D-0055..D-0081):** pre-memory infra + video arc -- res.lease + frontier.bridge + executor/watchdog + Governor + warm-pool arc (GATE-NO at i24) + video spine #32/#33/#34 + the GPU-lease split R1a/R1b/R1b' + widgets 01-04.
- **i25-i33 (D-0082..D-0097):** the memory-substrate arc -- Waves 1-3 (#35/#36/#37/#38/#39/#40/#41), MEMORY_CONTRACT + CONTEXT_PACKET_CONTRACT freezes + A1-A5, selpol settle, Tier-0 seam repairs (ns-closure + supersession).
- **i34-i35 (D-0098..D-0100):** Tier-1 hierarchy slice + NEW #42 (fold 38/38); consumer wiring #40 0.7.0 + the rehearsal harness.
- **i36 (D-0102):** **TIER-1 ACCEPTED** (11/11 s10 over a foreign corpus); #37 0.8.0 wired-descend + #36 0.6.0 get-record + NEW widgets/05.
- **i37 (D-0103/04):** ACTION_AUTHORIZATION_CONTRACT FROZEN + NEW #43 P0-1 monitor MVP + #40 0.8.0 R-1 router; fold 13/13.
- **i38 (D-0105/06/07):** #43 0.2.0 full-gate build + #40 0.9.0 wm-hydration + NEW widgets/06; fold 18/18; **pass over-claimed -> walked back (D-0107)**.
- **i39 (D-0108/09):** #43 0.3.0 gate-completion + #36 0.7.0 fast-beam (hpr 58823->117647 ppm) + NEW widgets/07 (audit A2); fold 18/18; **pass over-claimed AGAIN -> walked back (D-0109)**; #37 reconcile deferred = PB-5.
- **i40 (D-0110/11/12):** **SUNSET** -- mandate-01 report NO -> **mandate 02 licensed**; wave `fo-40-d42fd1ac`: #43 **0.4.0** the 7 D-0109 exact closures (orchestrator-recovered; M2-D held) + #37 **0.8.1** (PB-5 closed); round-3 pack couriered.
- **i41 (D-0114/15):** MODEL-TIERING (D-0114: Sonnet 5 High default lanes; Fable = orchestrator seat) + M2-A scoped; wave `fo-41-35be4fdc`: #43 **0.5.0** the 4 round-3 closures (M2-D held) + F7 pack rule MECHANIZED; round-4 post-close: FAIL, F1/F7 closed, 3 findings (D-0116).
- **i42 (D-0117):** the M2-A + round-4-closure wave -- 2-lane CPU coding (`fo-42-e5403d74`): Lane A SHIPPED **M2-A the doc-hygiene commit gate** (26/26 + 5/5; a real firing logged; the mandate HARD DEADLINE MET) + Lane B SHIPPED **#43 0.6.0** (the 3 round-4 closures; M2-D held); folds green; **round-5 review PASS -> s7 RATIFIED (D-0118, `p0_1_gate_status=pass`; the P0-1 arc closes)**.
- **i43 (D-0120):** NO code wave -- the Widget 05/06/07 human live-GUI confirm (technical PASS on real data; -Live pre-flight 113/98/93 all green + Nicholas confirmed the GUIs) + Nicholas's finding that the audit surface is expert-forensic/post-hoc, not phenomenological -> the **Live-Run Audit Pathway (LRAP)** reframed as the audit program's next target (A2 ride-along + A3 possession pulled forward; new legibility principle P9; design spec written, design only).
- **i44 (D-0121):** NO code wave -- PROMOTED the AUDIT_PIPELINE target doc to `core-docs/AUDIT_PIPELINE.md` (P9 legibility added; cadence i43/i47; next_increment LRAP; DOC_PROTOCOL s2/s8 + own budget 11->12 KB; source digest stubbed) + untracked `_to_delete_w07/` (the open i43 Nicholas ruling).
- **i45 (D-0122..D-0129):** the LRAP build wave (`fo-45-b17a531e`) -- NEW widgets/08 (87/0/0; leveled accept, whole auditor NOT complete) + the post-close poser arc (SHIPPED + 2 live-fix rounds; live-click confirm PENDING).
- **i46 (D-0130/31):** the PCB wave `fo-46-6dd32d37` (directive-hijacked; 2 CPU lanes) -- NEW modules/44 project.map 0.1.0 (Lane A orchestrator-recovered `11416a8` + 2 fold-fixes; Lane B claims `b4ce6ab`); D-0077 fold: refused-then-corrected ingest 143/98, validate 0 findings; BOOT_PACKET rendered; the I47 gate packet FROZEN (EVAL_SHA `0bcb5e7`).

Runtime paths: plans `.../30-orchestrate-fanout/runtime/plans/<plan_id>/` · artifacts `.../runtime/artifacts/<id>/` · leases `.../29-resource-lease/runtime/leases/`. Waves + ad-hoc commits share one counter; **the next wave is iteration 47.**

## 4. Current frontier -- NEXT = i47 (the MIGRATION GATE, after the mandate report)

**i46 SHIPPED the PCB (D-0130/31): `modules/44-project-map` -- deterministic map + claims + generated BOOT_PACKET, folded + verified.** This handoff REMAINS the default bootstrap (the control condition) until the gate passes.

**i47 runs IN ORDER: (1) the mandate-02 SUNSET REPORT** -- current_iteration hits sunset (47) -> REPORT_DUE; produce `research/<date>-process-mandate-02-report.md` BEFORE any wave work (PROCESS_MANDATE s1/s3; then archive per its s4). **(2) THE FROZEN EXPERIMENT** -- the legacy-vs-PCB side-by-side dry run per **`modules/44-project-map/eval/I47_EVAL_PACKET.md`** (READ IT FIRST; verify `eval/MANIFEST.sha256` first; EVAL_SHA `0bcb5e7` = the frozen pre-i46 worktree, OUTSIDE-repo eval folder; Nicholas picks T1/T2/T3 + holds the blind assignment; A/B/C1/C2 = HIS dispatches, eval-folder grant ONLY; the orchestrator stages, computes the s7 proxies, applies the s7 rules VERBATIM, commits C's verdicts byte-verbatim). **(3) deliver GO / CONDITIONAL / NO-GO** for i48 migration to Nicholas with evidence. NO other wave work unless Nicholas directs.

Post-gate candidates (i48+, skip freely): (a) on GO -- the migration unit (PCB default; FO-2; DOC_PROTOCOL rows; legacy = fallback until a retirement gate); (b) AUDIT_PIPELINE next_increment (front step + ride-along + OUTPUT side; design-first -> red-team; lease windows, P3/P6); (c) M2-C/FO-3 (map->#36 records); (d) #40 beam-WIDTH; (e) PB-2 (trigger-gated). **P0-1 ACTIVATION stays FROZEN** (no `non_execution=false` until Nicholas licenses).

**Lanes** (up to FOUR per wave; any may be skipped; every lane human-dispatched): GPU lane (<=1, HARD CLAMP; only it touches model modules / `models.json`; leases gpu->git) · CPU lane(s) + coding lane (distinct modules; lease git) · frontier-review lane (off-box, OPTIONAL; a #31 pack couriered by Nicholas; no lease).

**Clamps.** <=1 GPU worker; 1 GPU + 2 CPU = MaxParallel 3 validated ceiling; `git` lease serialises commits; `docs:[]` -> doc contention 0. Persistent llama-servers DETACHED + reaped; 0-UNMANAGED-orphan check every wave. Producer/consumer pairs across workers REQUIRE the D-0077 fold smoke.

**Wave loop:** mandate s1 check -> scope lanes (+ optional frontier topic) -> fill `FANOUT_AGENT_00N` slots (s5) -> author `workers-i<N>.json` + `task-plan-i<N>.ps1` (copy `task-plan-i40.ps1`; `-Iteration <N> -MaxParallel <=3`; `gpu:true` only on the GPU worker) -> run `plan`; confirm `dispatch_now` / <=1 gpu / 0 doc contention / clean preflight -> emit any frontier pack -> relay the check-in + worker prompts + pack as FILES + slot docs -> workers run + report -> poll `-Action status -PlanId <id>` until `ready_for_handoff` -> `-Action handoff` -> VERIFY commits via NATIVE git -> run the fold smoke the wave's shape demands -> fold, mirror core-docs under the `git` lease, archive used briefs + reset slots -> **regenerate the doc-health monitor** (`python ops/audit/gen-doc-health.py --date <today>`; SendUserFile + create_artifact the HTML) -> iterate.

## 5. Worker briefs: the FANOUT_AGENT slot system (D-0066)

Numbered brief docs (`FANOUT_AGENT_001..003` = GPU/CPU/coding lanes; template `FANOUT_AGENT_TEMPLATE.md`; mirrored at `claude/fanout/`): fill a slot at wave scoping (paste the `plan`-emitted worker prompt, or a tight summary + a pointer to the emitted copy when over the 8 KB slot budget -- the i40 Lane-A pattern), mirror it, and Nicholas dispatches a fresh session with "Read the Project doc `claude/fanout/FANOUT_AGENT_00N.md` and execute it" plus the one folder grant (s10). Slot docs also travel as FILES. On completion: archive to `archive/fanout-agents/i<N>-<slot>.md`, reset EMPTY, re-mirror (lifecycle: `DOC_PROTOCOL.md` s6). **Slots were archived + RESET at the i41 close.**

## 6. Locations

- **Repo (canonical, git):** `C:\Users\just_\LifeOrchestrator-Refresh\` -- `core-docs/` + `modules/` + `widgets/` + `ops/` + `archive/`. The Project mirrors `core-docs/` (map: `DOC_PROTOCOL.md` s8).
- **Large data (gitignored):** `F:\My_Programs\LifeOrchestrator-Refresh_Large_Data\` -- per-module model homes; `_engines\llama.cpp` (b8661 default) + `llama.cpp-b10092` (the 9B only).
- **Executor:** `modules\00-bootstrap-executor\runtime\`; driven via `exec-job.sh`. Heartbeat: `runtime/control/heartbeat.json`. Watchdog: `ops/start-watchdog.bat`.
- **Action layer:** `modules/43-action-authz/` (0.6.0; SCHEMA_NOTES = canonical views; tests/report/ = the regenerable evidence bundle; fixtures/real_packets/ = the authentic 0.7.0+0.9.0 packets).
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
- **Doc edits + mirror (EOL-safe, fail-closed):** core-docs are CRLF (some module docs LF -- preserve per-file EOL). Pull fresh bytes, edit in cloud, `device_commit_files` back, commit via an executor task: acquire `git` lease -> `git reset -q` -> `git add -- <named>` -> assert the staged set -> `git commit -F <msg>` -> release. Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>` + `Claude-Session: <url>`. NEVER `git add -A`. Re-mirror via `project_write local_path`. **Since i42 (D-0117) the fail-closed doc-gate runs on every core-doc commit** (pre-commit hook + `doc-commit-gate.py --files <named set>`): a hot doc over its s2 budget is REJECTED -- slim it or `GATE_OVERRIDE: D-####` (real D, logged).
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

## 11. Box state at handoff (2026-08-11, D-0131 -- i46 CLOSED)

**i46 closed: the PCB wave + this docs-close + the FINAL map/eval commit** (`d7619b4` freeze -> `b4ce6ab` Lane B -> `11416a8` Lane A recovered -> the docs commit -> the map/eval commit; confirm via `git log -2`). Orchestrator INDEPENDENT verify of #44: cloud 49/49 (negative 33/33, every error code) + `-Live -RepoState Skeleton` full-repo smoke + selftest ALL OK (box py3.12 + pwsh 7.4.6); fold validate **0 findings**; BOOT_PACKET rendered within budget (the render envelope records any ladder steps). Doc-gate PASS on staged budgets (CURRENT_STATE ~33.99 KB; INDEX ~19.99 KB, at cap = the standing M2-C signal). No held res.lease (durable `gpu-*.*` siblings persist by design); heartbeat `degraded:false`; 0 UNMANAGED orphans. Scratch NOW GITIGNORED: `.af_editor_tmp/` + `_to_delete_w07/` (still on disk; w07 disposition = Nicholas's open i43 ruling). A stale 0-byte `.git/index.lock` (Lane A's blocked mount git) was cleared via an assert-no-git executor task mid-fold. **Mandate 02 countdown = 46/1 done -> i47 = REPORT_DUE.** Slots EMPTY (002/003 archived + reset at this close). **NEXT = i47** (section 4: report -> experiment -> verdict).

## 12. Worker model tiering (D-0114 -- refresh roster/prices each session)

Nicholas picks each worker's model at dispatch; the orchestrator RECOMMENDS one per lane (check-in + brief header). Roster @2026-08-07 ($/MTok in/out; cache-read 0.1x in): Sonnet 5 High 2/10 (3/15 from Sep 1) | Opus 4.8 Extra 5/25 (Opus 5 = same price) | Fable 5 Max 10/50 (EXPLICIT Nicholas direction only -- D-0116).

- **DEFAULT lane = Sonnet 5 High:** exact-spec'd + suite-gated fail-closed + not ratification-critical (doc/registry currency, tooling w/ reference impl, widgets, bounded increments) -- the verification structure is model-independent.
- **ELEVATE to Opus 4.8 Extra** on ANY: prior review FAIL/walk-back on the module (#43 NOW); frozen-contract or core-infra semantics; design-vs-closure work; 2 in-lane gate failures. De-elevate after 2 first-pass ships.
- **ORCHESTRATOR SEAT = Opus 4.8 Extra by DEFAULT (D-0116, amends D-0114); Fable 5 Max only when Nicholas states it for a session.** Inline premium-demand units run on the seat model.
- **Fable 5 Max workers: effectively NEVER.** A premium-demand small-diff unit runs ORCHESTRATOR-INLINE (context already cached at 0.1x; a fresh premium worker re-pays orientation as novel input) -- the i40 recovered-ship shape; else an Opus worker.
- **FANOUT STAYS** (no serial consolidation): fresh narrow contexts + the independent-grader boundary caught D-0107/D-0109; only micro-units run inline. REWORK, not per-token price, dominates cost -- never downgrade the lane whose failure forces another review round.
