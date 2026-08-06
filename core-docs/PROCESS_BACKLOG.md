# PROCESS_BACKLOG -- cross-cutting process / tooling / doc-hygiene debt (router, not a spec)

Owns the deferred **process / orchestration / doc-hygiene** work that is NOT a single module's follow-on (those
live per-module in `MODULE_ROADMAP.md`) and NOT a runtime review item (`REVIEW_QUEUE.md`). ONE terse row per open
item: an id, one line, a deterministic **Trigger** (when to act), and a `D-ref` for the full rationale. Keep it a
ROUTER -- detail goes in the D-entry, NEVER here (same per-row discipline as `DECISION_LOG_INDEX.md`; budget in
`DOC_PROTOCOL.md` s2).

**Capture rule (ongoing):** anyone -- Nicholas, an orchestrator, a worker, a frontier reviewer -- who defers a
cross-cutting process/tooling/hygiene fix ADDS a one-line row here + a D-entry, instead of leaving it as a handoff
"named residual" (rewritten every session -> drifts) or a scattered "doc debt" mention. Close a row with `DONE
(D-00xx)` and move detail to the D-entry; compact closed rows periodically.

**Forcing function:** the durable pawl is the **mechanical commit gate (PB-1 = mandate-02 M2-A, DEADLINE the i42
close)**: it refuses a commit that violates a budget/brevity rule. The backlog is the memory; the gate is the
alarm; the MANDATE deadline is what forces the gate itself to exist (mandate-01's report proved prose triggers
do not fire action -- D-0110).

## Open

| id | item | trigger | D-ref |
|---|---|---|---|
| PB-1 | Doc-hygiene commit GATE (deterministic, fail-closed) -- now **mandate-02 M2-A with a HARD DEADLINE (shipped by the i42 close)**. THREE parts (D-0094): (a) a DENSITY check (bytes-per-state cap); (b) a PROPORTIONAL budget (density_cap x state_count x headroom -- never a static ceiling); (c) a RE-LAYER trigger at the ~40 KB bounded-read threshold -> shard + route to #36 retrieval (M2-C), not endless slimming. Wire into the executor doc-commit path; reuse `ops/audit/gen-doc-health.py` budget parsing (the monitor stays the dashboard; the gate is the pawl). First real firing logged = acceptance. | **i41 scopes the build (a lane or an orchestrator unit) or records why not at the mandate s1 check; ship by the i42 close.** | D-0093 / D-0094 / D-0110 |
| PB-2 | Reserved delegation seam: a `DELEGATION_PROTOCOL` + bounded delegation-index + subagent brief templates for recurring JUDGMENT doc-hygiene. RESERVE now, BUILD only if licensed. **+ (D-0101):** any spawn emits a versioned DELEGATION-DECISION event as a #39 episode STAGE. **Now mandate-02 M2-E: Nicholas rules whether in-session cloud subagents sit inside the D-0051-as-amended boundary** (the trigger conditions -- subagents available + >=3 recurring judgment tasks -- were MET at the i40 sunset, per the mandate-01 report). | Nicholas's M2-E ruling; if licensed AND the conditions still hold, build per this row; if declined, record the ruling and keep RESERVED. | D-0093 / D-0101 / D-0110 |
| PB-3 | Hold the hot docs under budget -- **the acute i40 slim is DONE** (CURRENT_STATE 185%->96%, MODULE_ROADMAP 132%->77%, the handoff at the i40 close rewrite; pre-slim snapshots `archive/doc-snapshots/2026-08-06/`; D-0110/D-0112). The row continues as **mandate-02 M2-B**: sizes recorded at each mandate s1 check (from the monitor log) until M2-A holds it mechanically; any doc still over the ~40 KB bounded-read threshold after a competent slim gets a recorded RE-LAYER plan (M2-C), not another slim. | Each mandate s1 check (record sizes); M2-A landing (mechanical hold); a doc over the bounded-read threshold (re-layer plan). | D-0093 / D-0110 / D-0112 |
| PB-4 | AUDIT_PIPELINE increment (D-0101): tier A2 SHIPPED i39 (widgets/07). Next increment gated on its cadence header (`research/2026-08-05-audit-pipeline-target.md`: last_reviewed / review_due / current_tier / next_increment) + a spare coding lane; A2/A3 follow-ons named there (ride-along pause s2.2 = design-first + red-team-gated; delegation possession s2.7 = needs the local coordinator). NON-DISPLACING (gate ratification, M2-A, and core memory sequencing outrank increments). | Every wave scoping: review_due reached OR a tier-gate flipped OR a new artifact class appeared; if a lane is spare, scope ONE increment; else bump review_due 1-2 + record why. | D-0101 |

## Closed

| id | item | closed |
|---|---|---|
| PB-5 | #37 retrieval.eval fold-reconciliation + version hygiene (D-0108): the WIRED_STRUCTURAL_DIGEST re-pin (`sha256:d0d54aba..e450`) + the manifest-version SINGLE SOURCE (skill.json; wrapper derives fail-closed; permanent -Live envelope==manifest drift assertion proven-to-fire) -> #37 -Live FULLY GREEN. Shipped as 0.8.1 (`6c7269d`, i40 Lane B); orchestrator independent re-run ALL PASS. | DONE (D-0112) |
