# FANOUT_AGENT_002 -- CPU lane: PORT-interp (config-resolve the Python interpreter path in #15 + #16)

## Header

- **Slot:** FANOUT_AGENT_002
- **Status:** READY
- **Wave / iteration:** i17 (plan id `fo-17-3a115347`)
- **Lane:** CPU
- **Worker id / label:** `PORT-interp` -- portability: config-resolve the Python interpreter path in image.util #15 + detect.objects #16
- **Module/area (exclusive):** `ops/setup` + `modules/15-image-util` + `modules/16-detect-objects` ONLY
- **GPU:** false
- **Docs:** `[]`

## Mission

Extend the portability bring-up (MODULE_ROADMAP BACKLOG; the D-0068/D-0069 residual "interpreter paths in
#15/#16 = a config-schema extension"). image.util #15 (PIL/numpy/cv2) and detect.objects #16 (onnxruntime)
both invoke a HARD-CODED system-python path; a fresh box may put python elsewhere. Add a config-resolvable
interpreter path with a FALLBACK to the current literal -- additive+fallback, byte-identical on-box, the
proven i15/i16 shim pattern (`c0f8be0` / `8274b9f`).

## Unit (execute the full emitted prompt)

**Authoritative full prompt (execute it verbatim):**
`modules/30-orchestrate-fanout/runtime/artifacts/6dd619e0-8a9c-4cf8-a110-642f18ab7f0d/workers/worker-PORT-interp.prompt.md`
(also delivered to you as a file). Condensed scope:

**SCOPE IN (edit ONLY `ops/setup` + `modules/15-image-util` + `modules/16-detect-objects` + their tests):**
- (A) EXTEND the ops/setup config schema (`LifeorchConfig.psm1` + `config.json`) with an OPTIONAL
  interpreter-path section + a resolver returning the configured interpreter when present, FALLING BACK to
  the current literal when absent.
- (B) WIRE it into #15 + #16 ONLY where they hard-code the python path -- an ADDITIVE shim that falls back to
  the literal (byte-identical on-box). Per-module test: resolver-resolved interpreter == the current literal
  on THIS box; + a mock override-honored test.

**SCOPE OUT -- HARD:** do NOT touch modules/23 (GPU lane) or modules/33 (coding lane); do NOT touch
modules/07 or ANY core-infra (00 / 00.1 / 01 / 29 / 30 / 31 / dev.ship -- core-infra rewiring is a dedicated
single-worker wave); do NOT touch the model-bound SPEECH VENV interpreter (#12/#23/#24/#25 -- a GPU-lane-ride
follow-on); scope to the SYSTEM python of #15/#16 ONLY. No core-doc edits; no models.json; no GPU/model; no
big downloads.

## Rails (standing rules)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first (system python `…\Python312` for
  #15/#16; pwsh 7.4.6 array gotchas; the D-0021 meta-file hand-off) + `core-docs/MODULE_ROADMAP.md` BACKLOG
  portability + the shipped `ops/setup/` (`LifeorchConfig.psm1`, `config.json`, `VERIFY-RUNBOOK.md`) + how
  #14/#16 (data-root) and #20 doc.io were wired at i15/i16 as the additive+fallback reference; obey
  `SKILL_CONTRACT.md`.
- Lease: **git** only. Gate off-machine FIRST (cloud pwsh + mock): resolver logic green in cloud; Windows-only
  probes degrade to 'unknown', never throw. Extend `ops/setup/tests` + add per-module tests; AST-parse
  `.ps1/.psm1`. Then `exec-job.sh devship` (FAIL-CLOSED, named files only, trailers).
- Do ONE unit; `docs:[]`. Additive+fallback = byte-identical on-box, reversible; negative results are
  first-class -- ship what's solid and NAME what remains (the D-0061 ethos).
- Report: `-Action report -PlanId fo-17-3a115347 -WorkerId PORT-interp -State done -Summary "<one line>"`.

## Verification

Cloud mock + on-device `-Live` counts; proof resolver-resolved interpreter == the current literal on-box for
#15 + #16; the #15 + #16 suites STILL green with the shim (they run their real python workers on-device);
confirm modules/23, modules/33, modules/07, ALL core-infra, and the speech venv were NOT touched; the
follow-on list (speech venv = GPU-lane ride; `$PwshPath` across model-bound entrypoints; core-infra =
single-worker). NO GPU/model; not a review-queue producer.

## Report-back record (ORCHESTRATOR fills at close-out from `plans/fo-17-3a115347/reports/`)

_(pending)_
