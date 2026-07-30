# FANOUT_AGENT_002 -- CPU lane: Portability follow-ons (ops/setup staging-plan confirm + resolver wiring)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** DISPATCHED -- iteration 15, plan `fo-15-27a03513`.
- **Wave / iteration:** i15 (plan id `fo-15-27a03513`)
- **Lane:** CPU
- **Worker id / label:** PORT-wire -- "Portability follow-ons: staging-plan URL/sha confirm + additive+fallback Resolve-LifeorchConfig wiring into a bounded set of LEAF modules"
- **Module/area (exclusive):** `ops/setup/` (+ its tests) + a bounded batch of **LEAF** modules (non-infra, non-07, non-widget-04) whose path-resolution is wired. DISTINCT from the coding lane's `widgets/04` and the GPU lane's `modules/07`.
- **GPU:** false -- `gpu:true` ONLY on the GPU lane
- **Docs:** `[]` (always -- workers never edit core-docs; the orchestrator mirrors)

## Mission

Advance the portability / new-machine bring-up (the `ops/setup` Stage-1 toolkit shipped i14, commit 821da16, D-0067)
with the two follow-ons that do NOT collide with the concurrent GPU + coding lanes: (A) CONFIRM the emitted
`ops/setup/out/staging-plan.txt` model/engine download plan is actionable (URL reachability + sha + well-formed), and
(B) begin ADOPTING `Resolve-LifeorchConfig` as the single source of truth for repo-root + data-root path resolution
across a bounded, SAFE set of LEAF modules -- an ADDITIVE shim that falls back to the current literal so on-box
behavior is byte-identical. Turns the standalone Stage-1 library into real wiring WITHOUT a giant blast radius.

## Unit (the full worker prompt)

ADVANCE the portability / new-machine bring-up (the ops/setup Stage-1 toolkit shipped i14, commit 821da16, D-0067) with two follow-ons that do NOT collide with the concurrent GPU + coding lanes. (Verbatim dispatched unit: `workers-i15.json` -> id PORT-wire + the emitted copy below.)

(A) STAGING-PLAN CONFIRM (inside ops/setup/ + its tests): verify ops/setup/out/staging-plan.txt is well-formed + ACTIONABLE -- each entry parses to {url, dest-under-data-root, expected sha256}; an HTTP-HEAD reachability check per URL (report status + advertised size; a tiny smoke download is OK; DO NOT pull the tens-of-GB payloads); flag any dead/moved URL or missing sha. Emit ops/setup/out/staging-plan-confirm.json.
(B) RESOLVER ADOPTION (bounded, additive, reversible): wire Resolve-LifeorchConfig into path resolution ONLY where a module HARD-CODES the repo-root literal (C:\Users\just_\LifeOrchestrator-Refresh) or the F: data-root literal, as an ADDITIVE shim that FALLS BACK to the current literal when no config is present (byte-identical on-box behavior; NOT a rewrite). Prove the pattern on a concrete, explicitly-named batch of LEAF modules + a per-module test that the resolved path == the current literal on this box.

HARD OUT (collision + infra safety): do NOT touch modules/07-model-gateway (GPU lane), widgets/04 (coding lane), or ANY core-infra (modules/00, 00.1, 01, 29, 30, 31, dev.ship) -- core-infra rewiring needs a dedicated single-worker wave (it is live-exercised by THIS wave). No core-doc edits; no models.json change; no GPU/model calls; no tens-of-GB downloads.

READ FIRST: START_HERE + CURRENT_STATE (deps + hardware + the ffprobe-shim / 5.1-ANSI / pwsh-array-unroll gotchas) + MODULE_ROADMAP BACKLOG portability + the shipped ops/setup/ (LifeorchConfig.psm1, setup.ps1, config.json, out/); obey SKILL_CONTRACT. First grep the repo for the repo-root + data-root literals to build the candidate set, pick the safe LEAF batch (non-infra, non-07, non-widget-04), list the remainder as a follow-on. GATE off-machine FIRST (cloud pwsh + mock inputs; the HEAD check degrades to 'offline', never throws; keep any PS 5.1 file ASCII-only). Extend ops/setup/tests/Invoke-SetupTests.ps1 (mock + -Live) + per-wired-module tests; AST-parse all .ps1/.psm1; dev.ship the named files under the git lease (fail-closed; named files; trailers). Negative results first-class -- ship what's solid, name what remains (D-0061).

**Plan-side spec (orchestrator):** dispatched in plan `fo-15-27a03513` at `-MaxParallel 3` (workers-i15.json id `PORT-wire`, `gpu:false`, `docs:[]`, `needs_git:true`); emitted convenience copy:
`modules\30-orchestrate-fanout\runtime\artifacts\dc1cc706-3e18-48f0-a48c-4ea501bbf9a2\workers\worker-PORT-wire.prompt.md`.

## Rails (standing rules -- keep in every brief)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine first (cloud pwsh 7.4.6 + a mock/seam harness), then `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers). Files reach the box via `SendUserFile` + `device_commit_files`.
- Acquire res.lease(s): **git** for the dev.ship commit; release on exit. NO gpu lease (CPU-only, no model calls).
- **HARD exclusions:** do NOT touch `modules/07-model-gateway` (GPU lane), `widgets/04` (coding lane), or ANY core-infra
  (`modules/00`, `00.1`, `01`, `29`, `30`, `31`, `dev.ship`) -- core-infra rewiring is a SEPARATE single-worker wave and
  is live-exercised by THIS wave's machinery. Enumerate the excluded sites as a follow-on.
- Additive + fallback: every wired site must resolve to the SAME path as the current literal on this box (prove it in a test).
- NO GPU/model invocation; no tens-of-GB downloads (HTTP-HEAD reachability only); keep any PS 5.1-executed file ASCII-only.
- Report back: `-Action report -PlanId fo-15-27a03513 -WorkerId PORT-wire -State done` + a plain summary of measured results; negative results are first-class (the D-0061 ethos).

## Verification

Cloud mock + on-device `-Live` test counts green (`ops/setup/tests/Invoke-SetupTests.ps1` extended + per-wired-module
tests); `ops/setup/out/staging-plan-confirm.json` summarises URL reachability / sizes / any dead link; the EXACT list of
modules wired + proof each resolver path == the current literal on this box; explicit confirmation `modules/07/models.json`
and ALL core-infra were NOT touched; a follow-on list of the remaining hard-coded-path sites (esp. infra + modules/07).
Negative results are first-class -- if the safe batch is small, ship what is solid and name what remains (D-0061 ethos).

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

(empty -- the worker reports via `-Action report`, never by editing this doc)
