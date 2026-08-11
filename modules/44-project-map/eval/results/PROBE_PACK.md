# i48 CD-1 acceptance probe -- PROBE_PACK (PROBE-ONLY dry run)

Boot source: `_bundle/BOOT_PACKET.md` (project.map render @ tree 2fc483f, in-sync). PROBE-ONLY: no writes
except this file; no leases/commits/dispatches/executor jobs taken -- where a procedure calls for one I state
what I *would* do; live checks ran the frozen-bundle tool and the envelope is recorded.

PCB-sufficiency (RT2-F9): all four answers derive from the PCB alone -- `BOOT_PACKET.md` OPERATIONS canon + the
five `--q entity:` queries (each returns a complete sha256-stamped, source-cited claim). I additionally opened
4 `tree\` files for exact-quote (seq 11-14); one (`FANOUT_ORCHESTRATOR_HANDOFF.md`) is a legacy-handoff open
that under the strict CD-1 bar ("complete answers + NO tree legacy-handoff open") would trigger RT2-F9. Flagged
so the bar can be scored; the answers stand on the PCB citations.

## 1 ANSWERS

### Q1 -- Wave concurrency clamps for a fan-out wave (workers, GPU, parallelism, doc contention)
- [known] **GPU: <=1 GPU worker per wave -- HARD clamp, always.** The #30 module caps dispatch to one GPU
  worker and the single `gpu` lease enforces it at runtime even if two are dispatched. Cite:
  `--q entity:ops:boot-wave-clamps` one_line "Wave clamps: <=1 GPU worker HARD; 1 GPU + 2 CPU => MaxParallel 3;
  workers run docs:[]; only the GPU lane edits models.json." (sources `FANOUT_ORCHESTRATOR_HANDOFF.md#s4` sha256
  0f7e8f..., `FANOUT_PROTOCOL.md` sha256 863a9c...); HANDOFF s1 ("<=1 GPU worker per wave, ALWAYS") + s4.
- [known] **Parallelism: MaxParallel = 3 validated ceiling = 1 GPU + 2 CPU.** Start MaxParallel = 2 (trial);
  scale up only as the box proves it keeps up (I/O + the single GPU are the ceilings); keep at 3 until the
  heartbeat proves more. Cite: `FANOUT_ORCHESTRATOR_HANDOFF.md` s2 ("MaxParallel 3 = 1 GPU + 2 CPU ceiling") +
  s4 + s9; `FANOUT_PROTOCOL.md` Sizing.
- [known] **Doc contention: workers run `docs:[]` -> doc contention 0; only the GPU lane edits `models.json`.**
  `plan` returns `conflicts` (GPU serialization + doc contention); resolve BEFORE dispatch -- re-scope so one
  worker owns a doc, or accept they serialize on `doc:<path>`. Preferred: workers do NOT edit shared core-docs
  -- they report, the orchestrator mirrors core-docs itself under the `git` lease. Cite:
  `--q entity:ops:boot-wave-clamps`; `FANOUT_ORCHESTRATOR_HANDOFF.md` s4 + s8; `FANOUT_PROTOCOL.md` steps 2, 6.

### Q2 -- Git-write rules + how a shipped unit's landing must be verified
- [known] **All git writes go through the executor under the single `git` res.lease; stage only NAMED files;
  NEVER `git add -A`.** Commit sequence: acquire `git` -> `git reset -q` -> `git add -- <named>` -> assert the
  staged set -> `git commit -F <msg>` -> release; commits serialize on the single lease. Cite:
  `--q entity:ops:boot-ship-verify` one_line "Ship via dev.ship (sha256 + AST + tests, FAIL-CLOSED, named files
  only); VERIFY the real HEAD with NATIVE git; never git add -A." (source `.../Invoke-DevShip.ps1` sha256
  7e1156...; deeper D-0072/D-0117); `FANOUT_ORCHESTRATOR_HANDOFF.md` s7 + s9.
- [known] **dev.ship = deterministic FAIL-CLOSED gate, in order:** (1) verify each file sha256 byte-exact;
  (2) AST-parse every *.ps1; (3) run tests; (4) COMMIT only if sha+ast+tests all green AND the index is clean
  of unrelated staged files (`git add -- <exactly commit_files>`, then `git commit -F <msg-with-trailers>`);
  (5) optional orphan count. A failed sha/ast/test NEVER commits (exit 1 gate-fail, exit 2 internal). Cite:
  `Invoke-DevShip.ps1` lines 8-18.
- [known] **Landing verification: verify the REAL HEAD with NATIVE git -- NOT the dev.ship `committed` field**
  (it can false-negative; D-0072). In practice `git --no-optional-locks log -1 --format='%h %s'` on the mount
  (read/log-only; plain `git status` strands `.git/index.lock`). If a worker lacks pwsh/executor (i48) or its
  bridge dies pre-push (i40), the orchestrator confirms what LANDED via native git and, if needed, runs the
  gates + devship + files the report on its behalf (recorded as a recovery). Cite:
  `FANOUT_ORCHESTRATOR_HANDOFF.md` s7 + s2 + s9.
- [known] **Trailers + doc gate.** Trailers: `Co-Authored-By: <acting model> <noreply@anthropic.com>` +
  `Claude-Session: <url>`. The fail-closed doc-commit-gate runs on every core-doc commit (pre-commit hook +
  `doc-commit-gate.py --files <named>`): a hot doc over budget is REJECTED -- slim it or `GATE_OVERRIDE: D-####`
  (real D, logged). Cite: `FANOUT_ORCHESTRATOR_HANDOFF.md` s7.

### Q3 -- Resource-lease acquire/release discipline
- [known] **A lease = named lock with a TTL.** Acquire writes the file atomically (`open(O_CREAT|O_EXCL)` /
  CREATE_NEW, fail-if-exists) -> `{acquired, lease_id, expires_at_utc}`; file existence = held; `expires_at_utc`
  = reclaimable. A crashed holder never deadlocks: on expiry the next acquirer reclaims via a source-rename CAS
  (`reclaimed_stale:true`, one winner). Release DELETES the file. Cite: `29-resource-lease/README.md` "Model".
- [known] **Acquire order (deadlock avoidance): `gpu` -> `git` -> `doc:<path>`; release in REVERSE.**
  Cite: `--q entity:ops:boot-lease-order` one_line "Lease order: acquire gpu -> git -> doc and release in
  reverse; the single git lease serializes every commit across the wave." (sources `29-resource-lease/README.md`
  sha256 442d59..., `FANOUT_PROTOCOL.md` sha256 863a9c...); README "Conventional resources".
- [known] **Single leases -> serialization.** `git` single -> every commit (dev.ship + the orchestrator doc
  mirror) serializes; `gpu` single -> one model/render at a time; `doc:<path>` -> one editor per shared doc.
  Cite: `FANOUT_PROTOCOL.md` "Resource discipline"; README "Conventional resources".
- [known] **Release/renew.** Release needs the `lease_id` (or matching `holder`); a wrong lease_id is refused
  (`lease_mismatch`) -- you cannot release a lease already reclaimed from you. `renew` extends `expires_at` by
  `ttl_seconds` (lost lease -> `lease_lost`). Set a STABLE holder per session (`$env:LIFEORCH_INSTANCE` or
  `-Holder`); every process MUST resolve the SAME lease dir (`$env:LIFEORCH_LEASE_DIR`, else `runtime/leases/`).
  Cite: `README.md` "Actions" + "Lifecycle".
- [known] **Build-then-verify (v0.2 finding 14).** For GPU build work do NOT hold the expensive `gpu` lease
  while blocking on `git`: take `git` for the commit, RELEASE `git`, then take `gpu` ONLY for the live verify.
  v0.2 rejects the lock-order inversion (acquiring a later-ranked resource while holding an earlier-ranked one;
  rank `gpu(0)->git(1)->doc(2)`) fail-closed `lock_order_violation`; genuine multi-hold uses `-AllowLockOrder
  -LockOrderReason '<why>'` (recorded). A live-proof harness that takes the real gpu leases must NOT wrap an
  outer whole-task gpu lease (i21). Cite: `README.md` "Build-then-verify"; `FANOUT_ORCHESTRATOR_HANDOFF.md` s8.
- [known] **Fencing (v0.2+).** Every fresh grant mints a strictly-increasing per-resource `fencing_token`
  (durable `<resource>.fence`, monotonic across release + stale reclaim); same-holder re-attach/renew keep it;
  `-FencingToken <n>` is a CAS guard on renew/release/check -- a superseded holder is fenced out
  (`fence_stale`), not merely TTL-abandoned. Cite: `README.md` v0.2.

### Q4 -- Orphan-process discipline + the schema producer+consumer standing rule
- [known] **Orphan discipline: launch persistent llama-servers DETACHED and reap them before finalize; assert
  0 UNMANAGED orphans every wave.** Failure mode "the wedge" (D-0055/56): a task BLOCKING while holding a
  persistent llama-server orphans it and livelocks the executor while the heartbeat stays fresh -> launch
  DETACHED, reap before finalize; if wedged, kill out-of-band (Task Manager). Wave check `pgrep -x
  llama-server; pgrep -x python` -> none. Cite: `--q entity:ops:boot-orphan-discipline` one_line "...launch
  persistent llama-servers DETACHED and reap them before finalize; assert 0 UNMANAGED orphans every wave."
  (source `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` sha256 0f7e8f...; deeper decision:D-0055/D-0056);
  `FANOUT_ORCHESTRATOR_HANDOFF.md` s9 + s2 + s4. dev.ship step 5 optionally counts named orphans
  (`Invoke-DevShip.ps1` line 17).
- [known] **Standing rule (D-0077): parallel isolated workers building a schema PRODUCER + CONSUMER against a
  shared design doc REQUIRE an orchestrator cross-module fold smoke BEFORE close.** Such a pair may run
  parallel-isolated ONLY with (a) one governing design doc, (b) per-module SCHEMA_NOTES records, (c) the
  orchestrator D-0077 fold smoke. Cite: `--q entity:ops:boot-fold-smoke` one_line "D-0077: a schema
  producer+consumer pair split across parallel workers requires the orchestrator cross-module fold smoke before
  close." (source `modules/30-orchestrate-fanout/FANOUT_PROTOCOL.md` sha256 863a9c...; deeper decision:D-0077);
  `FANOUT_ORCHESTRATOR_HANDOFF.md` s0 STANDING RULE + s8.

## 2 RETRIEVAL LEDGER

STEP 0 envelopes (frozen bundle; tool `_bundle/tool/project_map.py`, project.map 0.2.0, contract 0.2):
- `validate --map _bundle/map-eval --harvest _bundle/harvest-eval.json` -> **status ok**;
  `{ok:true, error_count:0, findings:[], warnings:[], stale:[]}`.
- `render --check ... --out _bundle/generated-eval` -> **status ok, checked:true, stale_count:0**; all 6
  generated files byte-match (boot_packet_bytes 14908). NOTE: an earlier run reported GENERATED_DRIFT ("missing
  committed file" x6) -- a staging artifact (the committed `generated-eval/` files were not yet in my working
  tree); clean once they were present. Recorded per "a refusal is a reportable result."

seq | path-or-query | bytes | why | what it changed
1 | `_dispatch/PROBE.md` | 2186 | the dispatch | defined the 4 Qs, hard rules, output spec
2 | run: `project_map.py validate` | envelope | STEP 0 trust-the-packet | map validates, 0 errors
3 | run: `project_map.py render --check` (pre-stage) | envelope | STEP 0 | GENERATED_DRIFT x6 = staging artifact
4 | run: `project_map.py render --check` (committed present) | envelope | STEP 0 re-run | ok, 0 stale, 6 byte-match
5 | `_bundle/BOOT_PACKET.md` | 15111 | boot source | planes/overlay/OPERATIONS canon + owner-doc pointers for Q1-Q4
6 | `--q entity:ops:boot-wave-clamps` | env | Q1 canon | one_line + sources HANDOFF#s4, FANOUT_PROTOCOL
7 | `--q entity:ops:boot-ship-verify` | env | Q2 canon | one_line + source Invoke-DevShip.ps1, D-0072/D-0117
8 | `--q entity:ops:boot-lease-order` | env | Q3 canon | one_line + sources res.lease README, FANOUT_PROTOCOL
9 | `--q entity:ops:boot-orphan-discipline` | env | Q4 canon | one_line + source HANDOFF, D-0055/56
10 | `--q entity:ops:boot-fold-smoke` | env | Q4 prod/consumer | one_line + source FANOUT_PROTOCOL, D-0077
11 | `tree\...\30-orchestrate-fanout\FANOUT_PROTOCOL.md` | 5528 | Q1/Q3 quote | loop, acquire-order, sizing/clamps, doc-contention
12 | `tree\core-docs\FANOUT_ORCHESTRATOR_HANDOFF.md` | 23891 | Q1/Q2/Q4 quote | clamps s4, git s7/s9, wedge s9, D-0077 s0/s8 (LEGACY OPEN -> RT2-F9)
13 | `tree\...\29-resource-lease\README.md` | 23106 | Q3 quote | TTL/atomic model, actions, acquire-order, build-then-verify, fencing
14 | `tree\...\00-bootstrap-executor\Invoke-DevShip.ps1` | 17333 | Q2 code | fail-closed sha256->AST->test->commit; named files; no add -A

Note: seq 5-10 (PCB) fully answer Q1-Q4; seq 11-14 are tree exact-quote corroboration. Only seq 12 is a legacy
core-docs handoff open (RT2-F9).

## 3 Model id + settings
- Model id: `claude-opus-4-8` (Claude Opus 4.8) [known].
- Session: Cowork PROBE-ONLY dry-run in the Anthropic cloud sandbox; device bridge to `desktop-pf5ffmf`, grant
  = `LifeOrch-i48-eval` folder only (i47/i48 eval-folder isolation). The frozen `_bundle` tool ran in the cloud
  Linux shell (python 3.11.15); `tree\` files read via the device bridge. [known]
- Decoding params (temperature/top_p/reasoning-effort/max_tokens): not exposed to me in-session [uncertain] --
  not asserting values I cannot read.
