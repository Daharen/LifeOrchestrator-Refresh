# WORK ORDER — Widget 03: Verification Console

- **id:** `widgets/03-verification-console` · **Phase:** B (Widget layer) #3 · **Status:** MVP (this session)
- **Realizes:** DECISION_LOG **D-0050** (the audit-loop spine); reorients the roadmap's old "Review /
  Escalation Dashboard" slot. Delivery per **D-0038** (native WinForms + `launch.bat`), architecture per the
  Widget 01/02 pattern (**D-0039 / D-0049**).

## Purpose

The human-audit surface that makes offload viable on current hardware. Under the D-0050 verify-cost rule,
Claude offloads a task only when verifying its output is cheaper than doing it itself; on this box the cheap
verifier is often Nicholas. This console is the channel: Claude writes a **verification packet**, Nicholas runs
and checks each item locally with inputs/outputs visible, and exports a **verification result** Claude reads
back. It doubles as the channel for Claude to hand Nicholas human-doable subtasks (`human_action` items) — "a
test script while Claude runs updates in the background."

## Scope (tight MVP)

Load one packet → per item: run (for `run_module`) or read the hand task (for `human_action`) → tick the
checklist, set an overall verdict, add notes → export one result JSON.

**Non-goals:** no agent / decision loop (that is Widget 01); no packet authoring in-UI (Claude writes packets);
no multi-packet history; no tri-state per-check UI (tick = pass, untick = not-yet/failed + note — the overall
verdict is the authoritative signal); no artifact preview beyond path/size (open artifacts via the Module
Launcher or the filesystem). Not a review-queue producer.

## Architecture (mirrors Widget 01/02)

- `VerificationConsole.psm1` — **WinForms-free driver core** (so the cloud gate tests it for real):
  - Packet: `Import-VerificationPacket` (parse + validate + normalize items; malformed packet → `ok=false`, a
    malformed item → `valid=false`, surfaced not hidden), `ConvertTo-NormalizedChecklist`,
    `Format-PacketSummary` / `Format-ItemListLine` / `Format-ItemDetail`, `Resolve-ItemSkillDir`.
  - Run: `Start-SkillProcess` / `Complete-SkillRun` / `Invoke-SkillRun` / `Format-SkillResult` (spawn the
    Module 1 wrapper `Invoke-Skill.ps1`, parse `lifeorch.skill.invocation_report/0.1` nesting the skill's
    `lifeorch.skill.result/0.1`, render) — the exact Widget 02 machinery.
  - Result: `New-RunSummary`, `New-VerificationResultItem`, `Get-VerificationSummary`, `New-VerificationResult`,
    `Save-VerificationResult`.
- `Show-VerificationConsole.ps1` — **thin STA WinForms shell**: open packet → item list + detail (left),
  run bar + run output (top-right), checklist + overall verdict + notes (bottom-right), export. The run starts
  off the UI thread and is polled by a `Timer` (control updates stay on the UI thread). `-SelfTest` builds and
  disposes the form (`SELFTEST_FORM_OK`). Splitters are set in `Add_Shown` (the D-0049 layout fix).
- `launch.bat` — `pwsh -NoProfile -STA -File Show-VerificationConsole.ps1 %*`.

## Data contracts

Packet `lifeorch.verification.packet/0.1` and result `lifeorch.verification.result/0.1` — see `README.md`.
`inputs_json` accepts a string or an object (normalized to a compact string). Checklist entries accept
`{id,text}` or a bare string (auto-`id`). Verdicts: per-check `pass|unchecked`; per-item overall
`pass|fail|partial|skipped`.

## Test plan

Dual-mode `tests/Invoke-VerificationConsoleTests.ps1`:
- **Cloud gate (no `-Live`):** AST-parse all scripts; import the shipped fixture packet + inline
  malformed/invalid-item cases; checklist normalization; rendering; `run_module` runs against
  `tests/mock-invoke-skill.ps1` (ok / error / bad-envelope / noisy); run-summary JSON-safety; assemble +
  save + re-read a result with mixed verdicts (summary counts).
- **Live (`-Live`, Windows/executor):** WinForms `SelfTest`; launch.bat shape; a **real `fs.observer` run**
  driven from the fixture packet item through the real `Invoke-Skill.ps1`; no orphaned `llama-server`.

## Ship

Through the job-runner (`dev.ship`): sha-verify the shipped files, AST-parse, run the tests `-Live`, commit
exactly the widget files with trailers. Then live-verify (SelfTest + a real run).

## Follow-ons (not this session)

`report_back:on_each` streaming back; tri-state per-check verdicts; inline artifact preview; a packet index /
history; a "reject → re-queue to Claude" action; and — once the multi-instance resource-arbitration layer
exists — a fan-out orchestrator whose final handoff emits worker packets + one check-in packet for Nicholas
(the D-0050 multi-instance direction).
