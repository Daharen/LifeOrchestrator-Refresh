# DOC_PROTOCOL -- how core-docs stay small, current, and lossless

Adopted 2026-07-29 (D-0066), after CURRENT_STATE hit 160 KB, DECISION_LOG 295 KB, and four overlapping
handoff docs accumulated. This is the anti-bloat contract for everyone who edits `core-docs/` (in practice:
the orchestrator -- workers run with `docs:[]` and never touch core-docs). The principle: **hot docs
describe NOW and stay ingestable whole; history is never deleted, it moves to layers built for it.**

## 1. The three layers

1. **Hot docs** (`core-docs/*.md`) -- compact, current, budgeted (section 2). An agent -- including a
   smaller-context local model -- must be able to read any hot doc whole.
2. **DECISION_LOG.md + DECISION_LOG_INDEX.md** -- append-only rationale, one entry per decision, with a
   SEPARATE small index doc (one row per decision). The log is never ingested whole; agents read
   `DECISION_LOG_INDEX.md`, then pull specific entries by ID (project_search / grep / ranged Read).
3. **Archive + git** -- `archive/` in the repo (git-tracked, indexed by `archive/ARCHIVE_INDEX.md`) holds
   full snapshots of superseded docs and retired briefs; git history holds everything else. Nothing is ever
   destroyed -- it is MOVED here.

## 2. The doc set: owner, budget, over-budget action

| doc | owns | budget |
|---|---|---|
| START_HERE.md | routing: what to read, what you may modify, session checklist | 6 KB |
| FANOUT_ORCHESTRATOR_HANDOFF.md | THE one live handoff: orchestrator ops + current frontier | 24 KB |
| CURRENT_STATE.md | reality NOW: phase, active work, box, deps, models, tests table, live gotchas | 34 KB |
| DECISION_LOG.md | append-only rationale | no cap (indexed; tool-pull only) |
| DECISION_LOG_INDEX.md | one compressed routing row per decision (id, date, state, one-line label; see its header rules) | 20 KB |
| MODULE_ROADMAP.md | build order, per-module status, deferred follow-ons, portability backlog | 37 KB |
| PROCESS_BACKLOG.md | cross-cutting process / tooling / doc-hygiene backlog (router; per-module follow-ons stay in MODULE_ROADMAP) | 8 KB |
| PROCESS_MANDATE.md | the live SUNSETTING process-hygiene mandate (mandate 01; self-deletes at its sunset_iteration after a report) | 12 KB |
| TOOL_MODEL_REGISTRY.md | tool/model/hardware/storage registry (lookup, not story) | 43 KB |
| REVIEW_QUEUE.md | queue schema, conventions, producer/consumer table, open design flags | 15 KB |
| PROJECT_DIRECTION.md | doctrine (stable) | 9 KB |
| ARCHITECTURE_MAP.md | long-horizon spine (stable) | 15 KB |
| SKILL_CONTRACT.md | the skill interface (versioned) | 12 KB |
| MEMORY_CONTRACT.md | the Collective Agent memory/retrieval contract (versioned): record+provenance envelope, embedding 0.2, retriever 0.2, catalog/eval/privacy gates + A6 Tier-1 hierarchy build | 48 KB |
| CONTEXT_PACKET_CONTRACT.md | the context-packet + selection contract (versioned): control/evidence separation, packet_disposition, consumer profile, the selection-policy library, packet identity/lineage + i34 hierarchy shortlist-and-descend | 37 KB |
| MEMORY_ARCHITECTURE.md | the long-horizon memory design (governing doctrine): target + Tier-0 invariants + typed memory + bounded-fanout hierarchy + query-aware retrieval + consolidation + procedural promotion + reconstructability + T0-T3 roadmap | 30 KB |
| MEMORY_BENCHMARK.md | the memory-quality + foreign-corpus validation architecture: corpora, independent mutation/withholding harness, executable + hidden ground truth, lifecycle measures | 14 KB |
| ADAPTIVE_RESOURCE_GOVERNOR.md | governor design + measured truth | 22 KB |
| MODULE_WORK_ORDER_TEMPLATE.md | work-order template | 4 KB |
| DOC_PROTOCOL.md | this contract | 11 KB |
| research/&lt;date&gt;-*.md | dated research digests | 10 KB each |
| fanout/FANOUT_AGENT_*.md | worker-brief template + numbered slots | 8 KB each |

Budgets = actual size at adoption rounded up with ~10-15% headroom. **A budget rises only via a new
D-entry naming the current-truth content that needs the room** -- never by silently editing this table.

**Over-budget action ("you bust it, you slim it"):** the session whose edit pushes a doc over budget slims
it in that same session -- snapshot the pre-slim doc to `archive/doc-snapshots/<date>/`, compress history to
D-refs, re-check size. Check sizes at every mirror: `wc -c core-docs/*.md` (device_bash) takes seconds.

## 3. Accretion rules (hot docs)

- **REPLACE, don't append.** Updating a section means rewriting it to the new truth. `[prior]` chains,
  "Last updated" stacks, and per-iteration narrative accretion are forbidden. The displaced truth already
  lives in DECISION_LOG (rationale), git (bytes), and archive snapshots (browsable).
- **Newest state wins, stated once.** A fact appears in exactly one place at its current value; other docs
  point to the owner (section 2 table).
- **Iteration history = one ledger line** per iteration in FANOUT_ORCHESTRATOR_HANDOFF section 3 (plan id,
  what shipped, commits, D-ref). Detail belongs in the D-entry. The ledger keeps roughly the last 10-15
  iterations; collapse the oldest into one range line (e.g. "i1-i13: D-0055..D-0065, commits in git") at
  the session that pushes it past that.
- **Last updated** = a single replaced line (date + one clause), never a chain.
- **Test results** = one row per suite in CURRENT_STATE's table (suite, count, task id, date), not prose.

## 4. DECISION_LOG rules

- Append-only, newest last, IDs contiguous. Entry fields: id, date, decision, reason, alternatives,
  consequences, affects, state (provisional|locked), revisit-if. Keep an entry <= ~30 lines.
- Every append ALSO appends a COMPRESSED routing row to `DECISION_LOG_INDEX.md` (one distinctive fragment per that file's header rules -- NOT the entry's summary; two edits, one per file).
- A decision that reverses/supersedes an earlier one gets a new entry; mark the old row in the index row
  `[superseded by D-00yy]` — scope the marker if only part of the decision was superseded. Never edit old entries beyond that annotation.
- Consumers: read the index first; pull individual entries by ID. Never ingest the whole file.

## 5. Handoff lifecycle

- Exactly ONE live handoff doc: `FANOUT_ORCHESTRATOR_HANDOFF.md`. Dated handoff docs in core-docs are
  forbidden (D-0066 retired the last of them).
- At the end of an orchestrator session: copy the outgoing handoff to
  `archive/handoffs/<date>-FANOUT_ORCHESTRATOR_HANDOFF.md` (same commit), then rewrite the live doc in
  place for the next orchestrator: update the TL;DR, ledger (add this session's line), frontier section,
  box state; keep it under budget.

## 6. Fan-out agent briefs (slots)

- Template: `core-docs/fanout/FANOUT_AGENT_TEMPLATE.md`. Slots `FANOUT_AGENT_001..003` (GPU / CPU / coding
  lanes; add slots only if the wave model grows). Mirrored to the Project under `claude/fanout/`.
- Fill at wave scoping; a slot is EMPTY, READY, or DISPATCHED (header field). Candidate-unit menus live
  ONLY in FANOUT_ORCHESTRATOR_HANDOFF section 4 (empty slots point there, never copy the menu). Nicholas dispatches a worker
  by telling a fresh session to read the slot doc (plus the one folder grant); the emitted prompt file via
  SendUserFile remains the convenience copy.
- On completion: copy the brief to `archive/fanout-agents/i<N>-<slot-id>.md`, reset the slot to EMPTY,
  re-mirror. Never edit a used brief in place; never leave a stale READY slot mirrored.

## 7. archive/ rules

- Layout: `archive/handoffs/` (retired + snapshot handoffs), `archive/doc-snapshots/<date>/` (pre-slim
  full docs), `archive/fanout-agents/` (used briefs), `archive/drafts/` (retired drafts/one-offs).
- Every add gets a line in `archive/ARCHIVE_INDEX.md`: path, what it was, why archived, date, D-ref.
- Git-tracked (it is small text). NOT mirrored to the Project -- the Project stays lean; desktop-less
  sessions that need an archived doc ask for it or read the index via a connected session.
- Nothing in archive/ is ever edited -- it is a record. Recovering content = copy OUT of archive.

## 8. Mirror rules (disk <-> Claude Project)

- Disk is canonical; the Project mirrors `core-docs/` so desktop-less (scheduled/mobile/pre-grant) sessions
  have context. If they disagree, disk wins -- re-mirror disk -> Project.
- Docs cite DISK paths only (the mirror map below is what makes them resolvable from the Project); the
  one exception is a dispatch instruction aimed at a Project-only session (`claude/fanout/...`).
- Mirror map: `CURRENT_STATE.md`, `DECISION_LOG.md`, `MODULE_ROADMAP.md`, `TOOL_MODEL_REGISTRY.md`,
  `REVIEW_QUEUE.md`, `PROJECT_DIRECTION.md`, `SKILL_CONTRACT.md`, `MODULE_WORK_ORDER_TEMPLATE.md`,
  `START_HERE.md` -> Project top-level. `FANOUT_ORCHESTRATOR_HANDOFF.md`, `ARCHITECTURE_MAP.md`,
  `ADAPTIVE_RESOURCE_GOVERNOR.md`, `DOC_PROTOCOL.md`, `PROCESS_BACKLOG.md`, `PROCESS_MANDATE.md`, `DECISION_LOG_INDEX.md`, `MEMORY_CONTRACT.md`, `CONTEXT_PACKET_CONTRACT.md`, `MEMORY_ARCHITECTURE.md`, `MEMORY_BENCHMARK.md` -> `claude/` (the Project
  places new agent-written docs under `claude/`). `research/*` -> `claude/research/`.
  `fanout/*` -> `claude/fanout/`. `archive/` -> NOT mirrored.
- Mirror at session end (START_HERE checklist). Only the frontier agent touches the Project; the executor
  cannot. Deleting a Project doc is allowed ONLY for a doc retired to archive/ in the same pass (verify the
  archive commit landed first).
- Mechanics (stale-stage gotcha, CRLF, git lease) live in FANOUT_ORCHESTRATOR_HANDOFF section 7.

## 9. End-of-session doc checklist (the enforced version)

1. Update CURRENT_STATE.md by REPLACEMENT (active work, executor, models/deps if changed, tests table row,
   gotchas if new, unresolved questions (add/close), next action, the single Last-updated line).
2. Update MODULE_ROADMAP.md status for anything you touched; TOOL_MODEL_REGISTRY.md for anything installed/
   wrapped/verified; REVIEW_QUEUE.md only if the queue contract or table changed.
3. Append DECISION_LOG entry + index row for any significant decision.
4. Orchestrator sessions: snapshot + rewrite FANOUT_ORCHESTRATOR_HANDOFF.md (section 5); archive used
   fanout briefs (section 6).
5. Size check: `wc -c core-docs/*.md` -- anything over budget gets slimmed NOW (section 2).
6. Commit named docs via the executor under the `git` lease (trailers; never `git add -A`).
7. Re-mirror changed docs to the Project (section 8 map); delete Project mirrors only per section 8.
8. Stop. One scoped unit per session.
