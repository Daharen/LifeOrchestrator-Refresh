# FANOUT_AGENT_003 -- EMPTY slot

## Header
- **Slot:** FANOUT_AGENT_003
- **Status:** EMPTY
- **Wave / iteration:** -- (fill at wave scoping; plan id `fo-<N>-<id>` once planned)
- **Lane:** -- (convention: CODING lane)
- **Worker id / label:** --
- **Module/area (exclusive):** --
- **GPU:** false (set true ONLY if this is the wave single GPU worker)
- **Docs:** `[]`

## Mission
_EMPTY -- no unit assigned._ Fill this slot at wave scoping from the candidate menu in `core-docs/FANOUT_ORCHESTRATOR_HANDOFF.md` section 4 (i38: the 7 P0-1 FREEZE AMENDMENTS -> a full gate [#43 + a contract amendment]; the #40<->#42 working_memory wiring; the fast-beam recall follow-on; Widget 06 Compile Trace Console; PB-3 doc slim). Paste the `orchestrate.fanout` `plan`-emitted worker prompt (or a tight summary pointing to it + the governing design doc) into the Unit section; keep within the 8 KB budget; mirror it.

## Unit (the full worker prompt)
_pending -- filled at wave scoping._

## Rails (standing rules -- keep in every brief)
- Read `core-docs/START_HERE.md` + `core-docs/CURRENT_STATE.md` 'Known failures' first; obey `SKILL_CONTRACT.md`.
- Acquire res.lease(s) in **gpu -> git -> doc** order; release on exit; a whole-task gpu lease for any resident-model work.
- Do ONE unit; never touch modules/areas outside the header's exclusive claim; `docs:[]`.
- Gate off-machine FIRST, then ship via `dev.ship` (sha256 + AST + tests, FAIL-CLOSED, named files only); VERIFY the real HEAD via native git (D-0072); assert 0 UNMANAGED orphans.
- Report: `-Action report -PlanId <plan> -WorkerId <id> -State done` + a plain measured summary (negative results are first-class, the D-0061 ethos).

## Verification
_pending -- filled at wave scoping._

## Report-back record (ORCHESTRATOR fills from `plans/<id>/reports/` before archiving)
_empty._
