# FANOUT_AGENT_003 -- Coding lane: Widget-04 live-GUI confirm + bounded polish

## Header

- **Slot:** FANOUT_AGENT_003
- **Status:** DISPATCHED -- iteration 15, plan `fo-15-27a03513`.
- **Wave / iteration:** i15 (plan id `fo-15-27a03513`)
- **Lane:** CODING (CPU; a DISTINCT module/area from slot 002 -- `widgets/04` vs `ops/setup`)
- **Worker id / label:** WAVE-confirm -- "Widget-04 live-GUI confirm + bounded polish: human-confirm the Fan-out Wave Dashboard renders a real plan dir correctly, fix only what that surfaces"
- **Module/area (exclusive):** `widgets/04-fanout-wave-dashboard/` ONLY (+ its tests + `launch.bat` + README).
- **GPU:** false -- `gpu:true` ONLY on the GPU lane
- **Docs:** `[]` (always -- workers never edit core-docs; the orchestrator mirrors)

## Mission

Close the open live-GUI-confirm item on `widgets/04-fanout-wave-dashboard` (the read-only Fan-out Wave Dashboard shipped
i14, commit 333dac6, D-0067; 80/80 cloud + 90/90 `-Live` SelfTest, but its RENDERED UI has never had a human live-GUI
confirm -- the D-0049/D-0060/D-0064 lesson that mock + SelfTest gates miss rendered-UI defects). Launch it on the box
against a REAL plan dir (ideally THIS wave's own `fo-15-27a03513`, with 3 workers in mixed live states + the gpu/git
leases held), confirm every rendered element is correct, and apply ONLY the bounded polish the confirm surfaces. A
rendered-UI widget is not done until a human has seen it render correctly.

## Unit (the full worker prompt)

CLOSE the open live-GUI-confirm item on widgets/04-fanout-wave-dashboard (the read-only Fan-out Wave Dashboard shipped i14, commit 333dac6, D-0067; 80/80 cloud + 90/90 -Live SelfTest, but the RENDERED UI has never had a human live-GUI confirm -- D-0049/D-0060/D-0064: mock + SelfTest gates MISS rendered-UI defects). (Verbatim dispatched unit: `workers-i15.json` -> id WAVE-confirm + the emitted copy below.)

(1) LIVE-GUI CONFIRM: launch via launch.bat on the box against a REAL plan dir -- ideally THIS wave's fo-15-27a03513 (3 workers in mixed live states + the gpu/git leases held), else the archived fo-14-5ea064b6. Confirm every rendered element: the worker table (id/lane/GPU/state/summary) matches the actual reports/ files; the lease panel shows gpu/git/doc:<path> holders with correct ages; dispatch_now vs queued + ready_for_handoff are accurate; the plan picker lists newest-first + switching re-reads; Refresh re-reads. Capture a screenshot or a precise per-element confirm note.
(2) BOUNDED POLISH: fix ONLY what the confirm surfaces (rendering/layout/refresh/plan-picker/lease-age/empty-state) -- .GetNewClosure() on EVERY handler (the D-0060 bare-local-handler null-ref lesson); keep the WinForms-free core / thin STA shell split + defensive parsing (a missing/partial file -> a well-formed 'unknown' row, never throws; mind the pwsh 7.4.6 empty-array-unroll + array-double-wrap gotchas: List[object] + .ToArray(), guard @() on maybe-null). NO defects found is a VALID result -- record it, ship only the confirm note, force no changes.

OUT: no edits to orchestrate.fanout #30 / res.lease #29 / any module / any other widget / any core-doc; no writes to the plans/leases dirs; no driving/mutating (READ-ONLY, needs NO lease to read); no GPU/model calls; no new features beyond closing the confirm gap + its fallout.

READ FIRST: START_HERE + CURRENT_STATE + widgets/README + the shipped widgets/04 (WaveDashboard.psm1, Show-WaveDashboard.ps1, tests/, launch.bat, README) + widgets/03-verification-console as the reference pattern; obey SKILL_CONTRACT. GATE: the core .psm1 stays unit-tested in cloud pwsh 7.4.6 over tests/fixtures/; keep the on-device -Live STA SelfTest (SELFTEST_*_OK) green; AST-parse all .ps1/.psm1; if polish changes code, dev.ship the named widgets/04 files under the git lease (fail-closed; trailers) -- confirm-only => no commit. A rendered-UI widget is NOT done until a human has seen it render correctly.

**Plan-side spec (orchestrator):** dispatched in plan `fo-15-27a03513` at `-MaxParallel 3` (workers-i15.json id `WAVE-confirm`, `gpu:false`, `docs:[]`, `needs_git:true`); emitted convenience copy:
`modules\30-orchestrate-fanout\runtime\artifacts\dc1cc706-3e18-48f0-a48c-4ea501bbf9a2\workers\worker-WAVE-confirm.prompt.md`.

## Rails (standing rules -- keep in every brief)

- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` first; obey `SKILL_CONTRACT.md`.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]` (the orchestrator mirrors core-docs).
- Gate off-machine first (cloud pwsh 7.4.6 + a mock/seam harness), then `exec-job.sh devship` (sha256 + AST + tests, FAIL-CLOSED, named files only, trailers). Files reach the box via `SendUserFile` + `device_commit_files`.
- Acquire res.lease(s): **git** ONLY IF the polish changes code to dev.ship (the dashboard is READ-ONLY and needs NO lease to read); release on exit. NO gpu lease.
- READ-ONLY over the plans/leases dirs -- never write to or drive anything.
- Rendered-UI change => a **human live-GUI confirm** before "done" (D-0049/D-0060/D-0064). `.GetNewClosure()` on every handler.
- If the confirm finds NO defects, that is a valid result -- record it and ship only the confirm note (do NOT force changes).
- NO GPU/model calls.
- Report back: `-Action report -PlanId fo-15-27a03513 -WorkerId WAVE-confirm -State done` + a plain summary of measured results; negative results are first-class (the D-0061 ethos).

## Verification

The live-GUI confirm result -- a screenshot or a precise per-element human-confirm note against a real plan dir (the
worker table / lease panel / dispatch_now-vs-queued / ready_for_handoff / plan-picker / Refresh all render correctly);
cloud + on-device test counts if code changed; the list of defects found + fixed (or 'none found'). This unit CLOSES the
widget-04 live-GUI-confirm open item (CURRENT_STATE Unresolved questions / D-0067).

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)

(empty -- the worker reports via `-Action report`, never by editing this doc)
