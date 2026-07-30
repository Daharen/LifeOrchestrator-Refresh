# FANOUT_AGENT_002 -- CPU lane: Portability / new-machine bring-up (ops/setup)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** DISPATCHED -- iteration 14, plan `fo-14-5ea064b6`.
- **Wave / iteration:** i14 (plan id `fo-14-5ea064b6`)
- **Lane:** CPU
- **Worker id / label:** `PORT-setup` -- "Portability / new-machine bring-up: config-driven ops/setup toolkit (config layer + setup.ps1 + CPU verify)"
- **Module/area (exclusive):** `ops/setup/` (NEW -- created this wave) + its tests. DISTINCT from the coding lane's `widgets/04`.
- **GPU:** false
- **Docs:** `[]`

## Mission

Ship Stage-1 of the portability / new-machine bring-up (`MODULE_ROADMAP.md` -> BACKLOG portability) as a NEW
self-contained `ops/setup/` toolkit: a repo-root + data-root config layer + resolver, a `setup.ps1` bootstrap
(prereq check, GPU detect, machine-specific `models.json` GENERATION to a staging path), and a CPU-only
verify pass. Scoped to ONE wave and to `ops/setup/` only -- it does NOT rewrite other modules' path
resolution (a follow-on) and MUST NOT touch `modules/07/models.json` (the GPU lane owns it this wave).

## Unit (the full worker prompt)

BUILD Stage-1 of the portability / new-machine bring-up as a NEW, self-contained ops/setup/ toolkit (MODULE_ROADMAP.md -> BACKLOG portability, scope items a/b/c), scoped so it ships in ONE wave and touches ONLY ops/setup/. GOAL: make relocating the whole stack to a fresh Windows box a config-driven, one-pass operation -- WITHOUT rewriting any existing module this wave.

SCOPE IN (edit ONLY ops/setup/ + its tests): (a) CONFIG LAYER -- define ops/setup/config.schema.json and a resolver Resolve-LifeorchConfig (a .psm1 function) that reads ops/setup/config.json giving REPO-ROOT + DATA-ROOT + a machine profile (hostname, username, GPU name/VRAM), with auto-detected defaults for THIS box; ship a generated config.json capturing the current machine's DETECTED roots (detected at runtime, NOT hard-coded). This is a STANDALONE library other modules adopt LATER -- do NOT wire it into modules/* this wave (that path-surgery is a follow-on that would touch other modules and collide). (b) ops/setup/setup.ps1 BOOTSTRAP: check prereqs (pwsh >= 7.4, git, .NET SDK, curl.exe, CUDA driver via nvidia-smi) and REPORT pass/fail per prereq; detect the GPU (parse nvidia-smi for name + total VRAM MiB, degrade gracefully if absent); GENERATE a machine-specific models.json sized to the detected VRAM (paths under the configured data-root + gpu_layers + quant picks) and WRITE IT TO A STAGING PATH ops/setup/out/models.machine.json -- it MUST NOT modify the live modules/07-model-gateway/models.json (the GPU lane owns modules/07 this wave; writing it is explicitly OUT OF SCOPE and would collide); EMIT (do not execute) a model/engine staging PLAN as a list of curl.exe download commands + expected sha256s for the data-root (downloading tens of GB is not a wave task). (c) VERIFY pass -- run the CPU-only checks NOW: executor heartbeat fresh + degraded:false, config resolves, repo-relative paths exist, the generated models.machine.json is schema-valid; and EMIT (as a documented runbook ops/setup/VERIFY-RUNBOOK.md) the GPU-dependent verify steps (a strong-tier smoke gen + the S0 6/6 calibration) for the operator to run AFTER this wave, because the single GPU is occupied by the concurrent GPU worker -- do NOT run any GPU/model job in this unit.

SCOPE OUT: no edits to any modules/* or widgets/* or core-docs; NO models.json change on modules/07; no GPU/model invocation; no tens-of-GB downloads; no rewrite of other modules' path resolution (that is the follow-on).

READ FIRST: core-docs/START_HERE.md + core-docs/CURRENT_STATE.md (installed deps + hardware profile + the ffprobe-shim / 5.1-ANSI / pwsh-array-unroll gotchas) + core-docs/MODULE_ROADMAP.md BACKLOG portability section; obey SKILL_CONTRACT.md; ops/README.txt + ops/start-executor.bat (existing ops conventions).

GATE off-machine FIRST (cloud pwsh 7.4.6 on Linux): all pure logic -- config resolve/validate, models.json generation, the prereq + GPU-detect parsers -- must be unit-tested with MOCK inputs (a fake nvidia-smi string, a fake prereq set) so it runs green in the cloud; Windows-only probes degrade to a reported 'unknown' off-Windows, never throw. Keep any PS 5.1-executed file ASCII-only (the 5.1-ANSI gotcha) -- prefer pwsh 7. Build tests into a dual-mode harness ops/setup/tests/Invoke-SetupTests.ps1 (mock/cloud + on-device -Live). AST-parse every shipped .ps1/.psm1. Then dev.ship the named ops/setup/ files under the git lease (fail-closed; named files only; trailers).

VERIFY / REPORT: test counts (cloud mock + on-device -Live); the detected GPU + generated models.machine.json summary (VRAM -> quant / gpu_layers picks); explicit confirmation that modules/07/models.json was NOT touched; the emitted download plan + VERIFY-RUNBOOK exist. Report done via -Action report with those results. Negative results are first-class -- if any scope item proves impractical in one slot, ship what is solid and say plainly what remains (the D-0061 ethos). NO GPU, no model calls, not a review-queue producer.

**Emitted convenience copy:** `runtime/artifacts/53985bb5-5c1e-4d62-b7d1-b9a1bf7d60ea/workers/worker-PORT-setup.prompt.md`.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease **git** for the dev.ship commit; release on exit. NO gpu lease (CPU-only, no model calls).
- ONE unit; `ops/setup/` only; `docs:[]`; do NOT touch any `modules/*` (esp. `modules/07/models.json`) or `widgets/*`.
- Gate off-machine first (cloud pwsh + MOCK nvidia-smi/prereq inputs), then `exec-job.sh devship` (FAIL-CLOSED; named files; trailers).
- NO GPU/model invocation this wave -- emit the GPU-dependent verify steps as a runbook (the single GPU is busy).
- Report: `-Action report -PlanId fo-14-5ea064b6 -WorkerId PORT-setup -State done` + test counts + the detected-GPU / models.json-gen summary.

## Verification

Cloud mock + on-device `-Live` test counts green (`ops/setup/tests/Invoke-SetupTests.ps1`); the generated
`ops/setup/out/models.machine.json` is schema-valid and sized to the detected VRAM; explicit confirmation
`modules/07-model-gateway/models.json` was NOT modified; the emitted download plan + `VERIFY-RUNBOOK.md`
exist. Negative results are first-class (D-0061 ethos) -- ship what is solid, name what remains.

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

(empty -- the worker reports via `-Action report`, never by editing this doc)
