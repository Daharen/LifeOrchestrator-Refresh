# START_HERE -- boot kernel (STABLE, hand-maintained, NOT generated; holds no changing state)

A fresh instance reads THIS first. The kernel only ROUTES; substance lives in generated front doors (the PCB
packet) and the raw core-docs behind them. It carries no iteration/active-work/roster/changing state -- the one
hand-maintained exception to "everything generated," so a broken generator still leaves a trustworthy recovery
entrypoint (D-0152/D-0153/D-0154). It changes ONLY if the boot mechanism itself changes.

Canonical repo: `C:\Users\just_\LifeOrchestrator-Refresh` (disk wins; the Claude Project mirrors core-docs/).

## BOOT

1. **verify:** `python3 modules/44-project-map/project_map.py verify --map modules/44-project-map/map --repo .`
   (on-box: `pwsh -File modules\44-project-map\Invoke-ProjectMap.ps1 -Action verify`)
2. **verify OK, packet current** -> open `modules/44-project-map/generated/BOOT_PACKET.md`; expand by
   progressive disclosure (L0 map -> L1 `card:` -> L2 `section:`/`--q`). **[Mode A -- done]**
3. **verify FAILS / packet missing or behind, and you CAN run the generator** -> rebuild ONCE, re-open:
   `pwsh -File ops/frontdoor/Rebuild-FrontDoors.ps1` (uniform rebuild over all registered classes; asserts
   boot_read 0-stale). If it still fails, go to 4. **Do NOT rebuild twice.**
4. **cannot run the generator** (read-only mount / mobile / Project-mirror / generator down) -> read
   `core-docs/COLD_BOOT_CARD.md`. If the card is absent here, use its raw read order: `PROJECT_DIRECTION.md` ->
   `CURRENT_STATE.md` -> `FANOUT_ORCHESTRATOR_HANDOFF.md` -> `DECISION_LOG_INDEX.md` (pull by ID). **[Mode B]**

Mount / mobile / Project-mirror sessions take **Mode B** unconditionally. {kernel + cold-boot card} is the
closed recovery set; what to read / what you may modify / the session checklist now live in the packet OVERLAY
+ `CURRENT_STATE.md` + `FANOUT_ORCHESTRATOR_HANDOFF.md`.
