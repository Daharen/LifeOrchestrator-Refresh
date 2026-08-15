# decision.intel -- SCHEMA_NOTES (Module 45, skill `decision.intel` 0.1.0)

**Authority.** This file records EVERY schema/marker/regex interpretation this PRODUCER makes of the
FROZEN governing contract `core-docs/research/2026-08-14-pb6-decision-record-schema.md` (D-0077 fold
doc for the PB-6 producer/consumer pair: FANOUT_AGENT_001 = this producer, FANOUT_AGENT_002 = the
`compile_relevant_decisions` retrieval verb, s4/s5 of the frozen doc) plus `MEMORY_CONTRACT.md` s1
(the record envelope) and `modules/36-artifact-search/SCHEMA_NOTES.md` s4 (the `ingest_records` INPUT
shape this producer conforms `ingest_records.json` to exactly). Governing: the PB-6 frozen doc in full;
`research/2026-08-14-pb7-relayer-design.md` s2/s3 + `-2.md` s7/s8 (the hardened hot/cold ruleset this
schema exists to serve); `modules/38-repo-intel/SCHEMA_NOTES.md` (the producer determinism archetype
this module mirrors structurally).

Worker: `decision_intel.py` (Python **stdlib only**: `json`, `hashlib`, `re`, `os`, `time`, `sys`,
`traceback` -- NO third-party). Entrypoint: `Invoke-DecisionIntel.ps1` (pwsh-file). CPU-only, no model,
no network. `worker_version` = `0.1.0`; `schema_version` on every record =
`lifeorch.decision_intel.record/0.1`.

decision.intel is a **PRODUCER**: it EMITS record-envelope artifacts conforming to MEMORY_CONTRACT s1
(`record_kind="decision"`) and VALIDATES them; it does **NOT** write the catalog DB (#36 owns storage).
The orchestrator feeds `ingest_records.json` into #36 `ingest_records` at fold (the built #38->#36
D-0077 pattern, verbatim).

---

## 1. Determinism contract (READ FIRST)

- **Canonical artifacts** (`records.jsonl`, `records.json`, `ingest_records.json`, `index_manifest.json`,
  `coverage.json`, `summary.md`) contain **NO absolute paths, NO timestamps, NO random/wall-clock ids**.
  Identical `DECISION_LOG.md` + `DECISION_LOG_INDEX.md` byte **content** + the same `ingested_through`
  CALLER input => **byte-identical** canonical artifacts across runs AND machines. **Verified**: a
  double-run against the real `core-docs/DECISION_LOG.md` (649 KB, 149 entries) + `DECISION_LOG_INDEX.md`
  (149 rows) produced byte-identical `out1/` vs `out2/` trees (`diff -rq` empty) in both the pre-fix and
  final builds of this worker.
- **`ingested_through` is CALLER-SUPPLIED, never worker-computed.** The frozen contract s3 requires the
  `DECISION_LOG.md` HEAD sha "sourced deterministically -- NO git in the worker, take it from an input
  param the orchestrator/harness supplies" (mirrors #38's D-0072 no-git rule). `Invoke-DecisionIntel.ps1`
  REQUIRES `-IngestedThrough` (7-40 lowercase hex) on every `index` invocation and never shells out to
  git; the caller (this session, acting as the dispatched worker) resolved it via a NATIVE `git` read on
  the box (`git --no-optional-locks rev-parse HEAD`) BEFORE invoking the wrapper -- consistent with "no
  git in the worker" (the worker process itself never touches git).
- **All ids are content+path derived** (section 3). Same inputs => same ids + same order.
- **`created_by_ingest_run`** = `"ingest_" + sha256(namespace "\0" + "\n".join(sorted
  "decision_id\tsha256(entry_body_text)"))[:24]` -- a function of the corpus content ONLY (mirrors #38's
  formula at decision-entry granularity instead of per-file).
- **`records_digest`** = `sha256` over sorted lines, one per record:
  `{record_kind}\t{record_id}\t{record_version_id}\t{content_hash}\t{source_path}\t{span.start}\t{span.end}`
  -- IDENTICAL formula to #38 / the frozen contract s2.
- **Canonical JSON** = `json.dumps(obj, sort_keys=True, ensure_ascii=True, separators=(",",":"))`.
- **`source_path`** is always the constant repo-relative `core-docs/DECISION_LOG.md` (single source file
  for this record class). **Spans** are BYTE offsets over the raw `DECISION_LOG.md` bytes (EOL-faithful --
  core-docs are CRLF; verified 2105 CRLF pairs across the 648,841-byte file, zero bare LF).
- **`source_version_id`** = `"ver_" + sha256(doc_id "\0" ingested_through)[:24]` where
  `doc_id = "doc_" + sha256(namespace "\0" "core-docs/DECISION_LOG.md")[:24]` -- keyed to the WHOLE-FILE
  HEAD version (simpler than #38's per-file hashing since decisions all derive from one append-only
  file); identical for every record in a run.

## 2. record_kind + envelope

Only `record_kind="decision"` is emitted (the s1 enum already contains it; PB-6 IS "the later wave" #38's
SCHEMA_NOTES s2 named). `namespace="decisions"` (frozen contract s1; overridable via `-Namespace`, slugged).
`record_id = "dec_<NNNN>"` from the canonical `D-<NNNN>` heading number (stable across re-ingest).
`record_version_id = "rv_" + sha256(record_id "\0" content_hash)[:24]` (mirrors #38's formula).
`content_hash = sha256(canonical_json(payload))`. `authority_level="canonical_source"` (DECISION_LOG.md
IS the canonical source for a decision). `sensitivity_class="repo_internal"`. `valid_from`/`valid_to` =
`null` (decisions have no temporal expiry field in this increment). `synopsis` = RESERVED `null` (no
model-generated synopsis this increment, per frozen contract s2).

## 3. `DECISION_LOG.md` entry parsing (byte-exact spans)

**Heading detection** (line-scan, mirrors #38's `parse_markdown` line-byte-start approach):
`^(#{2,3})\s+(D-(\d{4}))\b(.*)$` matched per-line against `text.split("\n")`; both heading LEVELS
(`##` and `###`) are used across the corpus (the log's convention changed partway through its history --
verified: 76 `###` entries then 73 `##` entries, contiguous ids D-0001..D-0149, zero gaps, zero dupes).
`source_span = {start, end}` = byte offset of the heading's line start (via a `line_byte_starts(raw)`
table built from the RAW bytes, identical technique to #38) through the byte offset of the NEXT
`D-####` heading's line start, or EOF for the last entry. **Coverage-verified**: every one of the 149
spans is `0 <= start < end <= len(raw)` (`coverage.json.span_resolution_ok`).

**`title`** = the heading's trailing text with a leading separator/date PREFIX stripped (documented,
2-pass regex, deterministic): (1) strip a leading `—`/`–`/`-`/`--` run; (2) strip a leading
`(YYYY-MM-DD)` OR bare `YYYY-MM-DD` immediately followed by another `—`/`–`/`-` run. Handles all 3
observed heading shapes: `### D-0001 — Title` (D-0001..~D-0076), `## D-0077 — 2026-07-31 — Title`
(date sandwiched between two em-dashes), `## D-0149 (2026-08-14) -- Title` (parenthesized date). The
UN-stripped heading remainder (`raw_heading_rest`) is kept SEPARATELY for date fallback extraction
(section 4) -- title stripping must not destroy the date-recovery signal.

## 4. `date` (deterministic, 3-tier fallback)

1. **Primary**: `\*\*[Dd]ate:\*\*\s*(\d{4}-\d{2}-\d{2})` searched over the entry BODY (the
   `- **date:** YYYY-MM-DD` / `- **Date:** YYYY-MM-DD` bullet field; both capitalizations observed, 112/149
   entries carry this field).
2. **Fallback A** (37/149 entries lack the body field -- all are the `## D-00NN — date — Title` /
   `## D-00NN (date) -- Title` heading shapes): `\((\d{4}-\d{2}-\d{2})\)` against `raw_heading_rest`
   (3 entries: the parenthesized-date heading shape).
3. **Fallback B**: `[—–\-]{1,2}\s*(\d{4}-\d{2}-\d{2})\s*[—–\-]{1,2}` against `raw_heading_rest` (the
   remaining 34 entries: date sandwiched between two dash runs in the heading).
4. **If none resolve**: `date=null`, flagged `date_unresolved` in `ambiguous`. **Verified on the real
   corpus: 0 entries reach this branch** (all 149 resolve via tier 1 or 2).

## 5. `iteration` (deterministic, nullable -- many early/process decisions have none)

1. `\biteration\s+(\d{1,3})\b` (case-insensitive) searched title-then-body (first match wins,
   title-priority).
2. Else `(?<![A-Za-z0-9])i(\d{1,3})(?!\d)` (a lowercase `i` NOT preceded by a letter/digit, followed by
   1-3 digits not immediately followed by another digit -- avoids matching inside a longer token or the
   word "I") searched title-then-body.
3. Else `iteration=null` (NOT flagged ambiguous -- absence is expected and correct for pre-fanout /
   pure-process decisions; 65/149 entries have no iteration signal, e.g. D-0001..~D-0050).

## 6. `affected_modules` + `planes`

**`affected_modules`** = the sorted-unique union of FOUR deterministic patterns over `title + "\n" + body`:
`#(\d{1,2}(?:\.\d)?)\b` (e.g. `#38`, `#00.1`), `modules/(\d{1,2}(?:\.\d)?)-` (e.g. `modules/44-`),
`\bmodule:(\d{1,2}(?:\.\d)?)\b`, and `\bModule\s+(\d{1,2}(?:\.\d)?)\b` (the capitalized prose form used
in the earliest ~50 decisions, before the `#N` shorthand convention took hold -- e.g. D-0001 "Module 0").
**15/149 entries genuinely reference no specific module** (process/doc-protocol/audit-correction
decisions, e.g. D-0038 widget-delivery policy, D-0066 doc-consolidation, D-0093 PROCESS_BACKLOG
establishment, D-0121/124/125/126/128/129 the LRAP audit-acceptance arc) -- each is flagged
`no_affected_modules_found` in `ambiguous` (verified: zero false positives on manual spot-check of full
entry bodies for these 15 -- no `#NN`/`modules/NN-`/`module:NN`/`Module NN` token is present anywhere in
any of them).

**`planes`** = the sorted-unique set of plane names for every resolved `affected_modules` entry, via a
**STATIC documented lookup table** (`MODULE_PLANE_MAP` in the worker), NOT a live read of the real
`modules/44-project-map/map/` plane assignment. This is an explicit, honest INTERPRETATION GAP (not a
silent guess): the frozen contract s3 says planes are "resolved from affected modules via the PCB plane
map," but integrating the real #44 map schema (`map/entities/`, `relationships.json`) is out of scope
for this increment's time budget. The table groups modules by the CURRENT_STATE.md "Completed modules"
roster categories at i56 scoping time: `infra`(0,0.1,1,29,30,31), `observation`(2-6),
`model_core`(7,8,9,19,20,21,27,28), `audio`(10-13), `perception`(14-18), `generators`(22-25),
`video`(32-34), `memory`(35-43,45), `pcb`(44). **Named follow-on**: replace with a real query against
`modules/44-project-map/map/` once a stable programmatic plane-lookup surface exists there.

## 7. `type` (deterministic keyword priority; open enum)

Scanned title-then-body, FIRST matching pattern wins (checked in this exact order): `gate` (`\bGATE\b` /
`\bNO-GO\b` / `\bGO-GO\b` / `gate = `) -> `freeze` (`\bFROZEN\b` / `\bfreeze\b`) -> `build` (`\bSHIPPED\b`
/ `\bshipped\b` / `\bbuilt\b` / `\bBUILD\b`) -> `design` (`\bDESIGN\b` / `\bdesigned\b` / `design-first`)
-> `direction` (`directive` / `User-directed` / `\bpivot\b`) -> default `process`. This is an explicit
INTERPRETATION (the frozen contract names `type` as "routing type from the index row (design/process/
build/gate/...)" but the actual `DECISION_LOG_INDEX.md` table has NO type column -- verified: its 4
pipe-delimited cells are `id | date | state | decision` only) -- so `type` is derived from body/title
keyword classification instead, honestly documented as a deviation from the letter (not the intent) of
the frozen field description.

## 8. `authority` (deterministic keyword priority)

Scanned title-then-body, FIRST matching pattern wins: `nicholas`
(`Nicholas('s)?\s+(directive|ratifie[sd]|declares?|decides?|priority|rules?|deferred)` / `ratified by
Nicholas` / `Nicholas:` / `User-directed`) -> `redteam` (`red-?team` / `adversar(y|ies)`) -> `gate`
(`\bGATE\b` / `\bNO-GO\b`) -> default `orchestrator`.

## 9. `binding_scope` (frozen contract s3 rule 1 -- verbatim priority order)

Scanned over `title + "\n" + body`, checked in this EXACT order (the order the frozen contract's field
table lists the marker families in): (1) `standing_prohibition` if `\bFROZEN\b` or `\bprohibit(ed|ion)\b`
(case-insensitive) matches; (2) else `invariant` if `\bnever\b` / `\balways\b` / `\binviolable\b` /
`\bHARD\b` (case-SENSITIVE for `HARD` -- avoids matching "hard" in casual prose) matches; (3) else
`ordinary`. **Real-corpus counts**: `standing_prohibition`=48, `invariant`=49, `ordinary`=52 (149 total).

## 10. `enforced_by` (deterministic allowlist scan, first match wins)

An ordered allowlist of known deterministic-gate name tokens, scanned over `title + "\n" + body`:
`doc-commit-gate` -> `"doc-commit-gate"`; `dev\.ship\b.*\bAST\b` (or the reverse order) -> `"dev.ship-ast"`;
`\bP0-1\b.*action[.\-]?authz` (or reverse) -> `"action-authz-p0-1"`; `res\.lease\b.*\bwrapper\b` / `lease
wrapper` -> `"res.lease-wrapper"`; `gen-retrieval-monitor\.py` -> `"gen-retrieval-monitor"`;
`gen-doc-health\.py` -> `"gen-doc-health-monitor"`; `close-refold\.ps1` -> `"close-refold"`. Else
`"none"`. This is a NAMED, extensible allowlist (not exhaustive) -- a decision bound to a gate not yet in
this list resolves `enforced_by="none"`, which is the CONSERVATIVE default per the frozen contract
(a false "none" keeps a record hot/undemoted rather than falsely claiming enforcement; a false gate-id
would be the unsafe direction).

## 11. Edges (frozen contract s3 -- supersedes / superseded_by / partially_superseded_by / derives_from)

**Two independent signal sources are UNIONED, never either one alone:**

**(a) `DECISION_LOG_INDEX.md` bracket annotations** (DOC_PROTOCOL.md s4 rule 4 -- "mark the old row in
the index row `[superseded by D-00yy]`"): `\[(?:\w+\s+)?superseded by (D-\d{4})\]`,
`\[(?:\w+\s+)?folded by (D-\d{4})\]`, and (an OBSERVED corpus variant not named in DOC_PROTOCOL)
`\[(?:\w+\s+)?retired by (D-\d{4})\]` -- e.g. D-0045's row reads `[handoff retired by D-0066]`; treated
as an alias for `superseded by` (a retired handoff doc IS a full replacement, documented interpretation).

**(b) An entry's own EXPLICIT "supersedes/replaces D-####" declaration in DECISION_LOG.md** (frozen
contract s3: "ONLY on an explicit TOTAL-replacement marker ... 'supersedes D-####', 'replaces D-####'"):
a bounded cue-window regex `\b(supersedes?|replaces?)\b(.{0,80}?)(?=[.,;\n]|$)` (stops at the first
sentence/clause boundary -- period, comma, semicolon, or newline -- to avoid false positives from an
unrelated `D-####` mention drifting into a longer lookahead window; an EARLIER 160-char/period-only
window produced exactly one false positive on the real corpus: D-0080's "replace-don't-append ... the
D-0077\n cross-module smoke" matched `\breplaces?\b` on "replace" and pulled in the UNRELATED "D-0077"
reference 100+ chars later -- FIXED by tightening to 80 chars + comma/semicolon stops, re-verified zero
false positives via full-corpus regex audit of every `supersed*`/`replac*` occurrence). Within the cue
window, EVERY `D-####` token is extracted via `D-(\d{4})((?:/\d{2}(?!\d))*)`, which uniformly handles: a
compact citation shorthand (`D-0140/42/45` -- subsequent `/NN` reuse the first number's leading 2 digits),
a fully-repeated list (`D-0140/D-0142/D-0145` -- each `D-####` is its own independent match since
`/D` never matches the compact-suffix pattern `/\d{2}`), and a comma/and-joined list (each `D-####`
matches independently regardless of the joining word).

**Target resolution is fail-closed-honest**: a token resolving to a KNOWN decision id becomes an edge;
an unresolved token (typo, a decision id outside 0001-0149, or a malformed shorthand) is surfaced in
`unresolved_supersession_targets`, NEVER silently dropped and NEVER invented as a synthetic edge.
**Verified on the real corpus: 0 unresolved targets** (every declared supersession target parses to a
valid known decision id).

**`status` is EDGE-DRIVEN** (frozen contract s8 rule 4: "Demote to COLD only on a FULL
supersession/fold/close edge"), not copied from the index row's state cell in isolation: a resolved
`superseded_by` edge (from either signal source) demotes `status="superseded"`; a resolved `folded_into`
edge demotes `status="folded"`; else the index row's OWN state cell is consulted as a fallback (handles
a `superseded`/`folded` state-cell annotation whose bracket target didn't parse); else `status="current"`.
A MISMATCH between the two signal sources (an edge exists but the index-row state cell was never
hand-updated to match, OR vice versa) is flagged `supersession_edge_without_index_state_annotation` /
`superseded_index_state_without_resolved_target` / `folded_index_state_without_resolved_target` in
`ambiguous` -- honest surfacing of a REAL gap in how this corpus was hand-maintained (verified: D-0140,
D-0142, D-0145 are named ONLY in D-0146's own prose ("Supersedes the legacy-default state of
D-0140/D-0142/D-0145") -- their OWN index rows were never annotated with `[superseded by D-0146]`, per
DOC_PROTOCOL.md's own rule that the PREDECESSOR row carries the marker. This module still correctly
demotes their `status`, and flags the maintenance gap rather than silently trusting only one signal).

**`partially_supersedes`** (the DEFAULT when a later entry revises one aspect without a full-replacement
marker, frozen contract s8 rule 4) fires ONLY when NO full supersession was already found for that entry,
via a softer cue: `\b(revises?|refines?|amend(s|ed)?|RE-FROZEN|reconciles?|folds? the .*? into)\b.{0,80}?
(D-\d{4})` -- and ONLY when the captured `D-####` resolves to a known id. This is intentionally
CONSERVATIVE: absence of an explicit textual cue + explicit target id means NO edge is emitted (never a
guessed partial-supersession), matching "ambiguity resolves to the conservative, non-lossy default."

**`derives_from`** (external) fires on any cited `research/[\w.\-/]+\.md` digest path found in the entry
(e.g. D-0079 -> `research/2026-07-31-frontier-supervisor-asbuilt-redteam.md`). Internal (decision-to-
decision) `derives_from` beyond what supersession already captures is a NAMED NON-GOAL this increment
(scope decision, documented) -- citation-style "(per D-####)" / "governed by D-####" mentions are NOT
separately classified to avoid a second class of false-positive-prone heuristics on top of section 11(b).

## 12. `ingest_records` drop-in (the D-0077 fold seam) -- I PRODUCE; #36 0.2 CONSUMES

Unlike #38 repo.intel (which re-wraps its full s1-envelope records as-is into `ingest_records.json`,
deferring exact-shape reconciliation to the orchestrator at fold, because #36's `ingest_records` op
signature didn't exist yet when #38 shipped), **this producer conforms `ingest_records.json` EXACTLY to
the now-frozen #36 `ingest_records` INPUT shape** (`modules/36-artifact-search/SCHEMA_NOTES.md` s4,
verbatim): `{op:"ingest-records", db, ingest_run:{producer,producer_version,namespace}, records:[{
record_id, record_version_id, record_kind, text, namespace, status, authority_level, sensitivity_class,
source_version_id, source_path, source_span, derivation_refs, parser_fingerprint, extractor_fingerprint,
schema_version, token_count, attrs:{decision_id,title,date,iteration,affected_modules,planes,type,
authority,binding_scope,enforced_by,ingested_through,synopsis}, edges:[{edge_kind,dst_ref,dst_kind}] }...]}`.
`text` = `"<decision_id> <title>"` (a compact FTS-indexable surrogate). `edges[].edge_kind` is free text
(per #36 SCHEMA_NOTES s4) carrying `superseded_by`/`supersedes`/`folded_into`/`partially_supersedes`/
`derives_from`; `dst_kind` is `"record"` for internal targets, `"external"` for research-digest refs.
**`db` is left `null`** (the orchestrator supplies the target catalog path at fold; this producer has no
opinion on where #36's DB lives). `records.jsonl`/`records.json` separately carry the FULLER MEMORY_CONTRACT
s1 envelope (with `parent_edges`/`child_edges` edge-object form) for byte-identity gating, coverage
validation, and standalone `validate` re-checks -- both representations share the same `record_id` /
`record_version_id` / `content_hash` so they never diverge in identity, only in edge-encoding SHAPE.

## 13. Coverage validation (`coverage.json`)

Asserts: (a) every `DECISION_LOG_INDEX.md` routing row (149) has a corresponding emitted record
(`missing_records_for_index_rows` must be empty); (b) every emitted record has a corresponding index row
(`extra_records_without_index_row` must be empty -- catches a DECISION_LOG.md entry with no index row,
a real maintenance defect this producer would need to surface); (c) every record's `source_span` resolves
within `[0, len(raw DECISION_LOG.md bytes))` with `start < end` (`span_resolution_ok`). **Verified on the
real corpus: `coverage.ok=true`** (149 index rows, 149 log entries, 1:1, zero missing, zero extra, all
spans valid).

## 14. Validator (s1-adapted -- op `validate`, and run inline on every `index`)

`validate_records(records)` checks, per record: all s1-required fields present; `record_kind=="decision"`;
`status` in `{current,superseded,folded,closed}`; `content_hash == sha256(canonical_json(payload))`;
`record_version_id` derivation integrity; `payload.binding_scope` in
`{standing_prohibition,invariant,ordinary}`; `source_span` is a `{start,end}` object with `start<end`;
every `parent_edges`/`child_edges` target resolves to an emitted `record_id` OR is an `external` edge
with an `external_ref`. Returns `{ok, checked, errors[], edge_summary{total,resolved_internal,external}}`.
**Verified on the real corpus: `validation.ok=true`, 0 errors, 149/149 checked, 0 unresolved internal
edge targets.**

## 14a. Two bugs found + fixed during `-Live` shipping (both pwsh wrapper/harness, NOT the python worker)

The python worker (`decision_intel.py`) was correct throughout both of these -- `tests/test_decision_intel.py`
(off-machine, drives the worker directly via `subprocess`, separate stdout/stderr pipes) passed 29/29 on
every run, including before either fix below. Both bugs were in PowerShell-side process-output/JSON
handling and only showed up once the real entrypoint was driven through a NESTED pwsh process on the
`-Live` executor.

**Bug 1 -- stderr/stdout stream merge corrupted JSON parsing (`tests/Invoke-DecisionIntelTests.ps1`).**
`Invoke-Run` originally invoked the entrypoint as `& $PwshExe @argv 2>&1 | Out-String` to grab the JSON
envelope. Because the target is a NESTED pwsh.exe (a native process from the caller's point of view),
PowerShell wraps each line the child writes to STDERR as an `ErrorRecord` object and interleaves those
objects into the SAME captured pipeline ahead of the child's plain-text STDOUT lines -- so
`Invoke-DecisionIntel.ps1`'s own `Write-Diag` calls (`[Console]::Error.WriteLine(...)`, by design writing
progress notes to stderr, never mixed into the JSON on stdout) resurfaced as leading non-JSON lines in the
merged string, and `ConvertFrom-Json` failed even though the worker's actual JSON output was well-formed.
First caught live on `-Live` executor shipping: `dev.ship`'s own `test_argv` run showed `RESULT: 7 passed,
2 failed` (`run1 envelope parses` / `run2 envelope parses` both FAIL) while the embedded python harness in
the same run showed `RESULT: 29 passed, 0 failed` -- the discrepancy pointed straight at the ps1 harness's
stream handling, confirmed by a raw diagnostic task.ps1 that dumped `& $pwshExe @argv 2>&1`'s per-line
`.GetType().FullName` and found the first lines typed `System.Management.Automation.ErrorRecord` ahead of
the JSON's opening `{`. **Fix**: `Invoke-Run` (and the standalone `op=validate` invocation) now redirect
stderr to a temp file (`2>$errFile`) instead of merging it into the pipeline, keeping stdout capture pure
text; the file is read back for diagnostics on failure and removed afterward.

**Bug 2 -- an empty array field silently became `null` in the emitted envelope (`Invoke-DecisionIntel.ps1`).**
With bug 1 fixed, the harness's own assertions could finally run for real -- and one FAILED for real:
`run1 unresolved_supersession_targets empty`. The python worker's `meta.json` genuinely has
`"unresolved_supersession_targets": []` (0 unresolved, confirmed by the python harness's own passing
assertion of the exact same fact), but the wrapper's wire envelope had it as `null`. Root cause: the
wrapper's `Prop($o,$n,$d)` helper does `return $o.$n`; PowerShell UNROLLS an array's elements onto the
pipeline when a function returns it, so an EMPTY array returns ZERO pipeline objects, and a plain scalar
capture (`$x = Prop ...`) of zero objects collapses to `$null` -- never a real empty array. This is a
well-known PowerShell pipeline-enumeration pitfall, not a data or logic error: the underlying
`unresolved_supersession_targets` and `ambiguous` counts/values were always correct, only their JSON
*shape* was wrong when empty (`null` instead of `[]`), which would have broken any downstream consumer
doing `for x in unresolved_supersession_targets` without a null-guard. Confirmed via an isolated
round-trip diagnostic (`ConvertFrom-Json '{"a":[]}'` -> `Prop` -> `$val = ...` -> `$val` is `$null`, not
`@()`). **Fix**: wrap both array-typed `Prop` call sites in `@(...)` at the assignment site
(`@(Prop $meta 'unresolved_supersession_targets' @())`, same for `ambiguous`) -- `@()` re-collects a
function's (possibly zero-item) pipeline output into a real array, which `ConvertTo-Json` then renders as
`[]`. Fixed `ambiguous` too even though it wasn't observed failing on this corpus (18 non-empty entries
never triggered it) -- it is the identical latent bug and WOULD misfire on any future corpus with zero
ambiguous decisions.

Re-verified end to end after both fixes: `RESULT: 39 passed, 0 failed` (pwsh harness, including
`unresolved_supersession_targets empty` now genuinely passing on a REAL parsed envelope) with the embedded
python harness still `RESULT: 29 passed, 0 failed` inside it, and a subsequent `dev.ship -Live` run gated
green and committed. Documented per D-0107/D-0109 discipline: an honest bug-found-and-fixed beats a
silently-passing report that never actually exercised the assertions it claimed to run.

## 15. Non-goals (NOT built -- later waves / other modules / named follow-ons)

Model-generated `synopsis` (RESERVED null, a later PB-7 layer-2 increment per the design doc); the
`compile_relevant_decisions` retrieval verb + hot/cold predicate (FANOUT_AGENT_002's lane, routed via
#40 context.compiler + #37 `selpol_rrf_v1` -- no new retrieval arch, per frozen contract s4); real #44
`project.map` plane integration (section 6 -- a static table stands in); internal decision-to-decision
`derives_from` beyond supersession citations (section 11); ingestion into the real #36 catalog (the
orchestrator runs `ingest_records` at fold, D-0077); any UI; incremental/append-only re-ingest (this
increment always re-parses the WHOLE `DECISION_LOG.md`, which is safe/idempotent per `record_version_id`
content-addressing, but is not yet optimized for a per-commit incremental delta as frozen-contract s8
rule 5 eventually wants -- a named PB-7 follow-on).
