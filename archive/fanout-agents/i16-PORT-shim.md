# FANOUT_AGENT_002 -- CPU lane: PORT-shim (portability resolver wiring)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i16 (plan id `fo-16-f125365c`)
- **Lane:** CPU
- **Worker id / label:** `PORT-shim` -- extend the additive+fallback `Resolve-LifeorchConfig` shim to remaining leaf modules
- **Module/area (exclusive):** `ops/setup/` + a bounded batch of NON-model, NON-infra LEAF modules
- **GPU:** false
- **Docs:** `[]`

## Mission

Advance the portability / new-machine bring-up (`MODULE_ROADMAP.md` -> BACKLOG portability). The `ops/setup`
Stage-1 toolkit shipped i14 (`821da16`); i15 (`c0f8be0`) wired the additive+fallback `Resolve-LifeorchConfig`
resolver into `modules/14` + `16` (byte-identical on-box). KEY FINDING: repo-root is already portable (every
leaf uses a `$PSScriptRoot` walk-up; the data-root lives centrally in `modules/07/models.json`). Extend the
shim to the remaining NON-model walk-up LEAF modules -- real wiring, small blast radius, fully reversible.

## Unit (execute the full emitted prompt)

**Authoritative full prompt (execute it verbatim):**
`modules/30-orchestrate-fanout/runtime/artifacts/b6ef5fb3-88a7-4dab-8bad-058bc1d90e03/workers/worker-PORT-shim.prompt.md`
(also delivered to you as a file). Condensed scope:

**SCOPE IN (edit ONLY the named leaf modules + their tests + `ops/setup` as needed):**
- **(A) DISCOVER FIRST:** grep the repo for the repo-root literal (`C:\Users\just_\LifeOrchestrator-Refresh`)
  and the F: data-root literal to enumerate every remaining hard-coded-path site. From that set pick the
  NON-model, NON-infra, non-GPU-lane, non-coding-lane LEAF modules you can wire + test in ONE wave. Likely
  candidates: `02-fs-observer, 03-proc-observer, 04-uia-inspector, 05-uia-actor, 06-capture-screen,
  10-audio-ingest, 15-image-util, 20-doc-io, 22-gen-audio, 28-fs-manage` (14+16 already wired). Wire the batch
  you can COMPLETE; list the remainder as a follow-on.
- **(B) ADDITIVE+FALLBACK WIRING:** wire `Resolve-LifeorchConfig` only where a module hard-codes the repo-root
  or data-root literal, as an additive shim that FALLS BACK to the current literal when no config is present
  (byte-identical on-box, breaks nothing if config absent). Add a per-module test that the resolver path ==
  the current literal on this box.

**SCOPE OUT -- HARD exclusions:** do NOT touch `modules/07-model-gateway` (GPU lane) or
`modules/32-media-decompose` (coding lane); do NOT touch ANY core-infra (`00 / 00.1 / 01 / 29 / 30 / 31 /
dev.ship`) -- core-infra rewiring needs its own single-worker wave; do NOT touch the MODEL/GPU-bound leaf
modules (`08/09/11/12/13/17/19/23/24/25/27` + 21's governor) -- enumerate them as GPU-lane-ride follow-ons;
no core-doc edits; no `models.json` change; no GPU/model; no tens-of-GB downloads.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first (installed deps + hardware; the
  ffprobe-shim / 5.1-ANSI / pwsh-7.4.6-array-unroll gotchas) + `MODULE_ROADMAP.md` BACKLOG portability + the
  shipped `ops/setup/` + how `modules/14`+`16` were wired at i15; obey `SKILL_CONTRACT.md`.
- Acquire the **git** lease for the commit; release on exit. No GPU lease (no GPU/model).
- Gate off-machine FIRST (cloud pwsh 7.4.6; Windows-only path probes degrade to reported 'unknown', never
  throw; any PS 5.1-executed file stays ASCII-only). Extend the dual-mode `ops/setup/tests/Invoke-SetupTests.ps1`
  + add per-wired-module tests. AST-parse every shipped `.ps1/.psm1`. `dev.ship` the named files (FAIL-CLOSED;
  named files; trailers). Do ONE unit; `docs:[]`; report and let the orchestrator mirror core-docs.
- Report: `-Action report -PlanId fo-16-f125365c -WorkerId PORT-shim -State done -Summary "<one line>"`
  (`progress`/`blocked -Needs`/`failed` as needed). Negative results are first-class (D-0061 ethos).

## Verification

Cloud mock + on-device `-Live` test counts; the EXACT list of modules wired + proof each resolver path == the
current literal on this box; explicit confirmation that `modules/07`, `modules/32`, ALL core-infra, and ALL
model-bound modules were NOT touched; the follow-on list of remaining hard-coded-path sites (esp. infra +
model-bound needing their own waves). Not a review-queue producer; no GPU/model.

## Report-back record (ORCHESTRATOR fills from `plans/fo-16-f125365c/reports/` before archiving)

_(pending)_
