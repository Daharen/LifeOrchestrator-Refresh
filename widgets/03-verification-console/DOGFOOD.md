# Verification Console — first-run dogfood (H-verif-console, fan-out fo-4-31706096)

First end-to-end exercise of the audit loop that the fan-out has been *generating* packets for but had never
*run*. Driven headlessly through the shipped driver core (`VerificationConsole.psm1`) exactly as the GUI drives
it — import a real packet → run each `run_module` item through the real Module 1 wrapper (`Invoke-Skill.ps1`)
→ work the checklist → assemble → export `lifeorch.verification.result/0.1` → read it back. Inputs: the two
real packets on disk, `vp-fo-1-20ed8a0b-i1` (3 items) and `vp-fo-3-cf4965fb-i3` (1 item).

## Outcome — the loop works

The audit loop is sound on its first real exercise. The driver core imported both real orchestrator-emitted
packets with zero gaps (object-form `inputs_json` normalized to a compact string, `expected` text and
`human_action` items handled, checklists normalized), ran a real non-fixture module both ways, assembled and
saved two valid result documents, and re-read them. No orphaned `llama-server` was left behind by the CPU run.

Exported results (dogfood evidence):

- `vp-fo-1-20ed8a0b-i1` → total 3: **B-git-lease pass**, **C-frontier-bridge partial**, **A-gpu-lease skipped**
  (GPU item, deferred — see below).
- `vp-fo-3-cf4965fb-i3` → total 1: **G-exec-harden pass**.

Human-action reviews were substantiated against git history: commits `0c6d5c9` (A), `5530418` (B), `f52f21d`
(C), `e5b93ab` (G) are all present.

## Findings

**F1 — packet input is stale (belongs to orchestrate.fanout, NOT the Console).** Running fo-1's
`C-frontier-bridge` item with the packet's own `inputs_json` returned a clean error envelope:
`missing_input — Input 'prompt' is required for action 'pack'`. The packet passes `"task"`, but
`frontier.bridge`'s `pack` action wants `"prompt"`. Re-running the same module with a corrected
`{"prompt": ..., "files": [...]}` input returned `status=ok` with 3 artifacts — so **worker C's module is
healthy; the packet's example input is wrong.** This is the audit loop doing its job: it caught a real defect,
and the Console surfaced the exact error message. The fix is in the packet emitter
(`modules/30-orchestrate-fanout`), which this worker does not edit — reported to the orchestrator. Until the
emitter is corrected, `run_module` items whose module expects `prompt` will error on their first run.

**F2 — latent teardown gap in the Console's run path (in scope; documented, not yet fixed).** The Console
starts a module via a raw `System.Diagnostics.Process` and tears it down with
`Stop-SkillProcess` → `Process.Kill($true)` (on Cancel and on form-close). That is the same whole-tree kill the
D-0055 / G-exec-harden work showed does **not** reliably reap a *detached* `llama-server` grandchild. The
`run_module` items that matter here are GPU items (`A-gpu-lease` → `model.gateway`), which spawn exactly that.
So if Nicholas runs the GPU item in the GUI and then cancels or closes the window mid-load, an orphaned
`llama-server` can survive — the very hazard the executor was just hardened against, but the Console has its own
separate run path that was not hardened. Not triggered in this pass (the CPU-only run left `llama-server`
before=0 after=0), so this is a reasoned latent gap, not an observed orphan. Recommended follow-on (kept out of
this CPU-only unit because it can only be *Live*-verified with a GPU run): port an orphan-name sweep into the
Console's run-teardown and add a `-Live` no-orphan assertion around a real GPU item.

**F3 — minor UX (acceptable for MVP).** The GUI checklist is tick=pass / untick=unchecked with no per-check
note field (only the item-level notes box), and that notes box is on the short side — already flagged in
`examples/example-result.json`. Fine for the MVP scope; a tri-state per-check verdict is already a listed
follow-on in the WORK_ORDER.

**A-gpu-lease deferred.** `model.gateway` is a GPU item and this worker is CPU-only, so it was not run here
(no `llama-server` spawned). It is recorded `skipped` with a note; Nicholas should run it in the live GUI pass
to confirm `status==ok` and that the gpu lease is held across the run and released after.

## Shipped this pass

The driver core and the WinForms shell needed **no code change** — they handled the real packets and the real
run correctly. Per the work order's "if none, ship the dogfood findings as a short report + a test/doc tweak",
this unit ships: this report, plus a regression fixture (`tests/fixtures/real-packet-fo-1.json`, the actual
orchestrator packet) and gate tests that pin the real packet shape so orchestrator↔Console drift is caught
off-machine. Gate: 84 passed / 0 failed / 3 skipped (Live).

## Residual human-in-the-loop pass (for Nicholas, live)

The interactive GUI itself still deserves eyes-on: open `launch.bat`, load each packet, and confirm the panes
render and are readable (the `human_action` fixture item), and run `A-gpu-lease` on the GPU to close that item.
Everything a headless driver can validate has been validated.
