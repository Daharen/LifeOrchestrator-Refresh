# REPORT -- worker PCB-CD-i48 (plan fo-48-3d3a4e1b, iteration 48)

**Unit:** `modules/44-project-map` (`project.map`) **0.1.0 -> 0.2.0** -- the D-0133 CONDITIONAL
closures **CD-1** (boot-surface wave-mechanics canon) + **CD-3** (map query surface), as ONE bounded
increment. **State: DONE (with one out-of-scope blocker flagged for the fold -- see Open items).**

- WORK_ORDER.md sha256 built against (LF): `439261078ffeb0169e22de4829e9024081b50470187d78901dd9f2479a550725` (matches the recorded i46 build hash).
- Real HEAD read at (native `git rev-parse HEAD`): `f1de00c759bf390e53e1870450c086163d1c8f1e`; tree clean outside modules/44 (only gitignored `_to_delete/` touched).
- Model seat: Opus 4.8 Extra (per the D-0114 elevate note).

## 1. Suite counts

- **Cloud suite** (`tests/run_tests.py`, python 3.11): **93/93 GREEN** -- golden 3, determinism 3,
  drift 2, fmt 2, negative 33, parity 1, ingest 2, reaffirm 2, changed-since 1, **+ new: shortform 20,
  provenance 8, operations 12, ops-roundtrip 4**.
- **-Live suite** (same file, mount VM **python 3.10.12**): **93/93 GREEN** (cross-platform parity;
  identical class counts). `selftest` -Live = `SELFTEST_{CANON,CRLF,IDGRAMMAR,SORT,CODES,RESOLVE,OPS}_OK`.
  `render --check` on the shipped golden = **ok, 0 drift**. 0 UNMANAGED orphans (CPU-only; no servers).
- Prior baseline before the change: 49/49; the 44 added assertions are all new coverage.

## 2. CD-3 acceptance probes -- verbatim, -Live against the REAL committed `map/`

```
--q edges:module:42   -> {"q":"edges:module:42","edges":[],"resolved":"module:42/working.memory"}
--q edges:module:30   -> {"q":"edges:module:30","edges":["module:30/orchestrate.fanout-[depends-on]->module:29/res.lease","module:30/orchestrate.fanout-[persists]->store:plans-dir"],"resolved":"module:30/orchestrate.fanout"}
--q edges:module:37   -> {"q":"edges:module:37","edges":[],"resolved":"module:37/retrieval.eval"}
--q entity:widget:08  -> {"q":"entity:widget:08","resolved":"widget:08/live-run-audit-pathway", ...entity...}
```

- All four **resolve** (no silent `[]` from an unresolvable id, no `DANGLING_REF`): this is the exact
  failure B hit. Each short form's edge set is **byte-identical to its full-id form**.
- `edges:` is OUTBOUND-only (a 0.1.0 invariant preserved byte-for-byte). `module:30` is non-empty (2).
  `module:42` and `module:37` have **zero outbound edges in the committed map** -- their resolved sets
  therefore equal their full-id forms (`[]`), and their connectivity is INBOUND: `redges:module:42`=1,
  `redges:module:37`=2 (both short==full, -Live verified). See the acceptance note in Open items.
- Negative: `edges:module:99` (short-form miss) -> `DANGLING_REF`; `edges:module:99/ghost`
  (full-id-shape miss) -> `[]` (0.1.0-identical, NOT an error).
- **Provenance/currency on REAL data:** `evidence:ops:doc-commit-gate` with a real-HEAD harvest returns
  `currency={map_state_commit: fea1fd92..., harvest_commit: f1de00c7..., in_sync: false}` and
  `at_commit_drift_count: 3` -- CD-3 makes the real map-vs-tree split machine-visible (the B_PACK s7
  distrust), from harvest facts alone (no git in the worker, RT1-F21).

## 3. CD-1 OPERATIONS section

- Rendered ONLY from validated `ops:boot-*` map state (documented naming-convention selector), never
  renderer prose; every line pointer-backed with >=1 repo path. Golden render:
  **OPERATIONS section = 825 B**, **golden BOOT_PACKET total = 3,851 B** (HARD 20,000). The real BOOT_PACKET
  (13,124 B today) has ~6.9 KB of headroom for the section at fold.
- Content assertions (present + pointer-backed, tested): `<=1 GPU`, `MaxParallel 3`, `docs:[]`
  (clamps); `gpu -> git -> doc` (lease order); `NATIVE git` HEAD-verify + `never git add -A` (ship);
  `0 UNMANAGED orphans` (orphan discipline); D-0077 cross-module fold smoke.
- **Budget + degrade-LAST ladder (proven):** OPERATIONS has its own soft budget `SECTION_BUDGETS["ops"]`
  and fits 0->1->2 within it; against the 20,000 B HARD total it is the LAST section the total-guard
  degrades (section 3 hard-degrades first -- test `degrade-LAST(section3-before-OPERATIONS)`), and its
  **min floor (level 2) is a single collapsed pointer line that never vanishes** (test
  `minfloor-nonempty-with-pointer`; `OPERATIONS-survives-max-degrade` under a forced HARD=1).

## 4. Claims file (`claims/i48-ops-canon-claims.json`)

- schema `lifeorch.map_claims/0.1`; `by: cd-lane-i48`; `at_commit: f1de00c759...` (the real HEAD).
- **entities = 5, relationships = 0.** IDs: `ops:boot-wave-clamps`, `ops:boot-lease-order`,
  `ops:boot-ship-verify`, `ops:boot-orphan-discipline`, `ops:boot-fold-smoke`. Every field
  evidence-pointed to REAL tree paths (FANOUT_PROTOCOL.md, FANOUT_ORCHESTRATOR_HANDOFF.md,
  res.lease/README, exec-job.sh) + `deeper` decision descents (D-0072/0117/0055/0056/0077, all in
  DECISION_LOG_INDEX). `validate_claims_syntax.py` clean **twice**; `fmt --check` canonical;
  **fixture-map ingest round-trip green** (`test_ops_roundtrip`: ingest -> boot-ops upserted ->
  OPERATIONS rendered -> idempotent re-ingest). `sha256:null` throughout (ingest stamps at fold).

## 5. SCHEMA_NOTES sections added

- **OPERATIONS section -- boot-surface wave canon (i48 CD-1):** the `boot-` selection convention, the
  pointer-backing rule, the per-section budget, and the degrade-LAST / min-floor ladder position.
- **Short-form / alias id resolution (i48 CD-3):** `ns:NN` and `#NN`/`pos NN` rules; full-id
  byte-identity; unresolvable -> existing `DANGLING_REF`; no new query names / codes; the `resolved`
  echo; `edges:` stays outbound-only.
- **Provenance-at-SHA hygiene on `evidence:` (i48 CD-3):** the `_provenance` marking from harvest facts
  alone, `beyond_tree_count`/`at_commit_drift_count`, and the `currency` block (both commits) with the
  BOOT_PACKET freshness line stating `@ tree <sha> | map-state <sha> [in-sync|MAP-VS-TREE-SPLIT]`.

`skill.json` -> **0.2.0** + a purpose addendum naming OPERATIONS, short-form query resolution, and the
evidence beyond-tree marking.

## 6. Fixtures whose golden changed (each with a one-line why)

- `fixtures/golden-map/entities/ops.json` -- was `items:[]`; now carries the 5 boot-canon `ops:boot-*`
  entities (the fixture INPUT that exercises OPERATIONS rendering).
- `fixtures/golden-generated/BOOT_PACKET.md` -- gains the OPERATIONS section + the currency freshness line.
- `fixtures/golden-generated/{ALIASES,L0_SYSTEM_MAP,L1_CARDS_infra,L1_CARDS_modules,L1_CARDS_widgets}.md`
  -- the currency freshness line (both commits) now heads every generated file; L0 + L1_CARDS_infra also
  render the 5 new ops entities, and the capability plane member count rises by 5.

New fixtures added: `fixtures/i48-ops-canon-claims.fixture.json` (hermetic ingest round-trip) and
`fixtures/provenance/**` (the beyond-tree / map-vs-tree evidence-marking case: a ghost research path +
`decision:D-0130` + an at_commit drift).

## 7. WO-invariant preservation

SKILL_CONTRACT v0.2 envelopes (logical refusal = exit 0 + status:error + closed code); canonical bytes
(LF/UTF-8/sorted); CRLF->LF sha256; double-run + shuffle determinism; coverage/stale/skeleton/overlay
gates; drafts runtime-only; `render --check` drift gate; `parse_budgets` import parity; stdlib py3.10 --
**all preserved and green.** The closed **query-name set and the 30-code error table are UNCHANGED**
(short forms and provenance marking are additive; unresolved short forms reuse `DANGLING_REF`). No
derived field is authored. No file outside `modules/44-project-map/**` was written; **nothing under
`map/`, `generated/`, or `eval/`** (git-status verified).

## 8. Open items (honest; D-0061 / D-0107 / D-0109)

1. **[CRITICAL, out of CD-1/CD-3 scope -- for the fold] `harvest` crashes on the live tree:**
   `core-docs/PROCESS_MANDATE.md` was deleted at `53c211f` (i47 mandate-02 SUNSET -> archive), but the
   0.1.0 `harvest` op hard-reads it (`_parse_mandate_header`). So a real-tree `harvest` -- and thus the
   fold's re-harvest -> `validate` -> non-draft `render`, AND the standard `-RepoState Skeleton`
   full-repo smoke -- currently **crash** on the post-i47 tree, independent of this unit (harvest is
   untouched here). The orchestrator must resolve this before the CD-1 dry-run + CD-2 re-check can run
   (make the mandate parse tolerate an absent/sunset mandate, or keep a mandate stub). CD-1's OPERATIONS
   render is therefore proven via the hermetic fixture round-trip + real-map ops DATA, not a live
   `render` op.
2. **Acceptance-interpretation note (edges:42/37):** the accept text reads "SAME NON-EMPTY edge set as
   their full-id forms." `edges:` is outbound-only (0.1.0 invariant; changing it would break full-id
   byte-identity and is disallowed). `module:30` is non-empty; `module:42`/`module:37` have zero
   OUTBOUND edges in the committed map, so their resolved sets equal their full-id forms (empty) and
   their (non-empty) connectivity is via `redges:`. The testable core -- short-form resolves and yields
   the SAME set as the full id -- holds for all three, both directions. No `edges:` semantics change was
   made.
3. **Formal ship not run here (environment):** this Cowork session has no `pwsh` / `exec-job.sh` /
   `res.lease`, so `dev.ship`, the `git` lease, and the orchestrator `-Action report` were NOT executed.
   Per the very canon this unit ships (git writes executor-only, under the git lease, serialized by the
   orchestrator), the deliverable named files are **written to the working tree** and the git commit is
   left to the executor/orchestrator. Native-git HEAD verified read-only (`f1de00c7...`).
   Mount note: `git status`'s index refresh cannot unlink `.git/index.lock` on this FUSE mount (lock
   cleared via `mv`); use `git --no-optional-locks status`, and prefer commit/add (rename-based) which
   are unaffected.
4. **Pre-existing (not mine):** `claims/i46-overlay-meta-claims.json` (lane-B) is flagged non-canonical
   by `fmt --check`; untouched, out of scope, noted only for the record.

## 9. Verification Console item

`run_module project.map` selftest -> `SELFTEST_{CANON,CRLF,IDGRAMMAR,SORT,CODES,RESOLVE,OPS}_OK`
(the two new lines exercise CD-3 resolution and the CD-1 OPERATIONS min-floor).
