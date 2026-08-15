# PB-6 DECISION RE-LAYER -- FROZEN RECORD + VERB CONTRACT (the D-0077 governing doc)

**Status: FROZEN at i56 scoping (orchestrator-inline). This is the ONE governing design doc the PB-6
producer lane (FANOUT_AGENT_001) and the retrieval-verb lane (FANOUT_AGENT_002) both build against.**
Per FANOUT_ORCHESTRATOR_HANDOFF s8, a schema PRODUCER + CONSUMER may run parallel-isolated ONLY with
(a) one governing design doc [THIS FILE], (b) per-module SCHEMA_NOTES records, (c) the orchestrator D-0077
fold smoke (s5 below). Authoritative spec sources: `research/2026-08-14-pb7-relayer-design.md` s2/s3 +
`-2.md` s7/s8/s9 (the s8 hardened ruleset SUPERSEDES the s4 naive rule); `MEMORY_CONTRACT.md` s1 record +
provenance envelope; `modules/36-artifact-search/SCHEMA_NOTES.md` (the s1 typed enum already contains
`decision`; the record_edges table; `ingest_records`); `modules/38-repo-intel/SCHEMA_NOTES.md` (the
producer determinism archetype). Nothing here forks a new arch: `record_kind=decision` is an EXISTING kind
in the #36 enum, and the verb REUSES #40+#37.

## 0. What PB-6 proves (why the schema carries these exact fields)

PB-6 is the first PB-7 increment: make `DECISION_LOG.md` (~640 KB, append-only) grow without bound while the
decision surface a session READS stays bounded (decoupling C1-C4, design s0). The three red-team breaks --
F1 (unbounded standing-constraint set), F3 (partial-supersession drop), F4 (between-wave currency) -- are why
`binding_scope`, `partially_superseded_by`, and `ingested_through` are REQUIRED, not optional.

## 1. Envelope conformance (reuse, don't fork)

Every emitted object is a MEMORY_CONTRACT s1 record with `record_kind="decision"` (already valid in the #36
enum -- `#38 SCHEMA_NOTES` s2 lists `decision` as a "later waves" kind; PB-6 IS that wave). REQUIRED
envelope fields (unchanged): `record_id`, `record_version_id`, `record_kind`, `namespace`, `content_hash`,
`status`. The producer EMITS + VALIDATES record artifacts (`records.jsonl` / `ingest_records.json`); it does
NOT write the catalog DB -- **#36 owns storage; the orchestrator feeds the artifacts into #36 0.2
`ingest_records` at fold** (the #38->#36 D-0077 pattern verbatim). No change to the #36 envelope, the
`records` table, `records_fts`, or `record_edges`.

- `namespace` = `decisions` (single namespace for this class).
- `record_id` = `dec_<NNNN>` from the canonical D-number (e.g. `dec_0149`). Stable across re-ingest.
- `record_version_id` = content+source derived (s2 determinism), NEVER wall-clock.
- `status`: the ENVELOPE status conforms to the #36 STATUS_ENUM (current/superseded/deleted/*_stale/unverified -- NO folded/closed); the lifecycle {current|superseded|folded|closed} maps on (folded/closed -> superseded), kept losslessly in `payload.lifecycle` + edges; the verb demotes on the EDGE (D-0150).
- `content_hash` over the record's canonical field bytes (s2).

## 2. Determinism contract (inherit #38 verbatim -- READ FIRST)

Identical `DECISION_LOG.md` + `DECISION_LOG_INDEX.md` bytes => **byte-identical** `records.jsonl` /
`ingest_records.json` across runs AND machines (double-run byte-identity gate, cloud + -Live). All ids
content+path derived; canonical JSON = `json.dumps(obj, sort_keys=True, ensure_ascii=True,
separators=(",",":"))`; spans are BYTE offsets over raw file bytes (EOL-faithful -- core-docs are CRLF);
paths repo-relative forward-slash; NO absolute paths / timestamps / random ids in any canonical artifact.
`records_digest` = sha256 over sorted per-record lines (kind\tid\tversion\tcontent_hash\tsource_path\t
span.start\tspan.end). stdlib-only python3.10 (`json,hashlib,re,os`), CPU-only, no model, no network.
Skeleton (identity, status, edges, the typed fields below) is DETERMINISTIC; **no model-generated synopsis
in this increment** (a `synopsis` field is RESERVED null -- lazy generation is a later PB-7 increment,
design s2 layer 2).

## 3. The typed `decision` record (deterministic extraction)

Source of truth for each decision = its `DECISION_LOG.md` entry; the `DECISION_LOG_INDEX.md` row supplies
the compressed routing fields. Every field is extracted DETERMINISTICALLY (regex/marker rules the worker
documents in SCHEMA_NOTES); ambiguity resolves to the conservative, non-lossy default.

| field | type | derivation (deterministic) |
|---|---|---|
| `decision_id` | `D-####` | the entry's canonical D-number |
| `title` | string | the entry's heading text |
| `date` / `iteration` | ISO date / int | from the entry header |
| `affected_modules` | string[] | module refs (`#NN` / `module:NN`) in the entry + index row |
| `planes` | string[] | resolved from affected modules via the PCB plane map |
| `type` | enum | routing type from the index row (design/process/build/gate/...) |
| `authority` | enum | `nicholas` \| `orchestrator` \| `gate` \| `redteam` (from markers) |
| `binding_scope` | enum | **`standing_prohibition` \| `invariant` \| `ordinary`** -- deterministic from markers: `FROZEN`/`prohibited`/`PROHIBITION`->standing_prohibition; `never`/`always`/`inviolable`/`HARD`->invariant; else ordinary (design s8 rule 1) |
| `enforced_by` | string | `<gate-id>` if the entry binds to a deterministic gate (doc-commit-gate, dev.ship AST, lease wrapper, a monitor), else `none` (design s8 rule 2) |
| `ingested_through` | git SHA | HEAD of `DECISION_LOG.md` at this ingest (design s8 rule 5); identical for all records in one run |
| `source_span` | {path,start,end} | BYTE span of the entry in `DECISION_LOG.md` -> canonical expansion |
| `synopsis` | null | RESERVED (no model synopsis this increment) |

**Edges** (emitted into `record_edges`, kinds already free-text there):
- `supersedes` / `superseded_by` -- ONLY on an explicit TOTAL-replacement marker in the entry/index row
  ("supersedes D-####", "replaces D-####"). Drives demotion.
- `partially_superseded_by` / `partially_supersedes` -- the DEFAULT when a later entry revises one aspect
  without a total-replacement marker (design s8 rule 4). Does NOT demote the predecessor.
- `derives_from` -- provenance to a research digest / prior decision when the entry cites one.

## 4. The hot/cold predicate + the "compile task-relevant decision set" verb (FANOUT_AGENT_002)

**Hot/cold (the s8 hardened ruleset is AUTHORITATIVE; the s4 naive rule is dead):**
1. `binding_scope in {standing_prohibition, invariant}` records are EXEMPT from recency/relevance demotion;
   they leave hot only via explicit repeal / FULL supersession OR rule 2.
2. Demote-on-enforcement: a prohibition/gotcha stays hot only while `enforced_by=none`; once bound to a
   gate it demotes to cold carrying `enforced_by=<gate>`. Predicate:
   `hot <=> status=current AND enforced_by=none AND (cross_session_scope OR recurrence>=k)`.
3. The standing-constraint overlay pins the ROOT synopsis + child-category pointers + an ASSERTED COUNT
   (completeness proved without every leaf); below the budget cut it SPILLS to a cold query
   (`deeper:*:prohibition`) -- spill, never compress.
4. Demote to COLD only on a FULL `superseded_by`/fold/close edge; `partially_superseded_by` KEEPS the
   predecessor `status=current` (conservative over-inclusion; never silent loss).
5. Per-commit currency: compare `ingested_through` to canonical HEAD at boot/compile; if HEAD advanced,
   incrementally ingest the append delta BEFORE compiling; if deferred, degrade to "current as of <SHA>,
   K un-ingested appends" and mark `currentness=stale`.

**Verb contract (`compile_relevant_decisions`, routed via #40 context.compiler + #37 selpol_rrf_v1 -- NO new
retrieval arch):**
- INPUT signals: `{modules[], planes[], recency_window, action_class?, query_text?}`.
- OUTPUT: a bounded top-k set of `current` + task-relevant decision records (supersession-aware,
  current-only by default), plus the ALWAYS-included standing-constraint ROOT view (rule 3) with its
  asserted count, each row expandable to its `source_span` in `DECISION_LOG.md`. Global/full-history
  questions ("did we ever decide X?", oscillation) are the C4 EXPLICIT slow path -- never a fast query.
- Determinism: #37 `selpol_rrf_v1` treats `rank=index+1`, never re-sorts (frozen hit fields). Byte-identity
  over the compiled set for identical records + identical query.

## 5. The D-0077 fold smoke (orchestrator, before close -- MANDATORY)

The producer + verb are a schema producer/consumer split across parallel-isolated workers, so the close is
GATED on this cross-module smoke (handoff s4/s8; the #34/#36/#38 fold-smoke pattern):
1. Run the REAL producer over the REAL `DECISION_LOG.md` at a frozen HEAD -> `records.jsonl` +
   `ingest_records.json`; assert double-run byte-identity + coverage vs the index (every index row has a
   record; every record maps to a canonical span).
2. Ingest the artifacts into a #36 catalog via `ingest_records` (box python; the mount cannot delete).
3. Run the REAL verb over that catalog for >=3 probe queries (a module-scoped need; a standing-constraint
   action-class descend that MUST return the asserted full count with no silent drop -- F1; a
   partial-supersession case that MUST still surface the in-force predecessor -- F3).
4. Assert G1-G6 (design s9): bounded hot bytes/count as N grows (rehearsal shape, #37); completeness count
   asserted; every record expands to canonical; no partially-superseded aspect dropped; a mid-wave
   `ingested_through`<HEAD boot self-labels stale (F4); doc-commit-gate green; P0-1 `non_execution`
   untouched; boot_read 0-stale.

## 6. Guardrails (binding -- design s6)

No loss of history (git + `archive/` + the append-only `DECISION_LOG.md` stay complete + untouched; derived
records are drop+rebuildable). doc-commit-gate + budgets SURVIVE (the producer becomes a commit-time
ingestion trigger, F4/rule 5). P0-1 stays FROZEN -- retrieved memory is EVIDENCE (`can_instruct=false`),
never control/action authority; `non_execution:true` holds. Determinism: identity/status/edges/staleness +
the hot predicate are code, not judgement.
