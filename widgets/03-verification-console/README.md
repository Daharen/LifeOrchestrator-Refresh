# Widget 03 — Verification Console

The human-**audit** surface for the offload / verify-cost spine (DECISION_LOG **D-0050**). Where the Local
Agent Console (Widget 01) lets the *local model* drive `agent.local`, and the Module Launcher (Widget 02)
lets *you* run any Module by hand, the Verification Console closes the loop that makes offload viable on this
hardware: **Claude hands you work to check, you check it locally with everything visible, and you hand back a
structured verdict.**

The rule it serves: Claude offloads a task only when verifying its output is cheaper than doing it itself. On
this box the cheap verifier is often *you* — so this console is the channel that lets Claude offload more.

## What it does

1. **Open a verification packet** (`lifeorch.verification.packet/0.1`) — a JSON file Claude writes describing
   items to check.
2. For each **`run_module`** item: press **Run item** to run that Module locally through the Module 1 wrapper
   (`Invoke-Skill.ps1`), and see the inputs, status, result payload, and artifacts.
3. For each **`human_action`** item: do the described task by hand (the "handed subtask" channel).
4. Work the item's **checklist** (tick = pass), pick an **overall verdict** (pass / fail / partial / skipped),
   and add **notes**.
5. **Export result** — writes a `lifeorch.verification.result/0.1` JSON that Claude reads back.

It reimplements nothing (runs go through the canonical Module 1 wrapper and its envelope is parsed) and is
**not** a review-queue producer.

## Run it

Double-click **`launch.bat`** (runs `Show-VerificationConsole.ps1` under the per-user PowerShell 7, STA).
Optional: `launch.bat -PacketPath <packet.json>` to open a packet on start.

## Files

- `VerificationConsole.psm1` — WinForms-free driver core (packet import + validation, run-through-wrapper,
  result assembly + save). Cloud-gate-testable.
- `Show-VerificationConsole.ps1` — thin STA WinForms shell (Timer-polled; `-SelfTest` builds+disposes the form).
- `launch.bat` — double-click launcher.
- `tests/Invoke-VerificationConsoleTests.ps1` — dual-mode harness (cloud mock gate + `-Live` on Windows).
- `tests/mock-invoke-skill.ps1` — the Module 1 wrapper stand-in for the cloud gate.
- `tests/fixtures/packet.json` — an example verification packet.
- `examples/example-result.json` — an example exported result.

## Packet schema (`lifeorch.verification.packet/0.1`)

```
{ "schema","packet_id","title","created_by","report_back"("on_each"|"on_all"),"intro",
  "items":[ { "id","kind"("run_module"|"human_action"),"title",
              "skill_id","skill_dir"(repo-relative or absolute),   // run_module
              "inputs_json"(string or object),"expected",
              "action_text",                                        // human_action
              "checklist":[ {"id","text"} | "text" ] } ] }
```

## Result schema (`lifeorch.verification.result/0.1`)

```
{ "schema","packet_id","title","verified_by","verified_at_utc",
  "summary":{"total","pass","fail","partial","skipped"},
  "items":[ { "id","kind","title","ran","run_summary"{ok,skill_status,artifacts,...},
              "checks":[{"id","text","verdict"("pass"|"unchecked"),"note"}],
              "overall","notes" } ] }
```
