# Lane A report -- PCB-BUILD-i46 (plan fo-46-6dd32d37, iteration 46)

**Unit:** BUILD `modules/44-project-map` (`project.map` 0.1.0) -- the Project Comprehension Bootstrap
mechanism. **State:** BUILD COMPLETE + fully gated off-machine AND -Live on the mount VM; files placed
on disk; map/ seeded; generated/ empty. **Remaining:** the git devship commit is a Windows-box step
(see Open items) -- and per RT1-F11 the map+generated commit is the orchestrator's FINAL close commit at
fold. Honest status: the mechanism is built and green; it is NOT yet git-committed from this session.

## WORK_ORDER built against

sha256 (LF bytes) = `439261078ffeb0169e22de4829e9024081b50470187d78901dd9f2479a550725` -- **verified
match** before building (the FIRST gate). Build is to that exact frozen spec.

## Counts by namespace (real-repo harvest, seeded map/)

Harvest (real repo, HEAD b4ce6ab): modules **46** (incl 00.1), widgets **8**, core-docs **22**,
arch spine positions **51** (0-49 + 00.1 + fractional), decision ids **130**, DOC_PROTOCOL owner rows **24**.

Seeded `map/` entities (harvest ONLY; skeleton per WO s7) -- **132 entities, 0 edges**:

| ns | count | note |
|---|---|---|
| module | 46 | `skeleton:true`; one_line = manifest purpose FIRST sentence; scalar mechanical fields only |
| widget | 8 | `skeleton:true`; harvest-seeded placeholder one_line |
| doc | 22 | mechanical; one_line from the DOC_PROTOCOL owner column |
| arch | 51 | number-only keys `arch:NN` (RT1-F3); display/one_line from the spine |
| plane | 5 | fixed structural constants (boundary decision -- see Deviations) |
| contract/store/ops/meta | 0 | claims-lane / fold work; ship as empty entity files |

`validate` on the seeded map WITH harvest = **0 findings** (Skeleton state); **0 HARVEST_ORPHAN, 0
ENTITY_UNBACKED**; 54 `skeleton:true` entities remain (non-draft render correctly refuses
SKELETON_UNRESOLVED until the claims lane + fold resolve them). No judgment fields, no edges, no
overlay authored by this lane. `relationships.json` empty; `overlay/` empty; `generated/` = `.gitkeep`.

## Negative suite -- one fixture per error code, each failing with EXACTLY that code

Exercised through the CLI envelope (status:error + error.code). Every code in the closed s3.9 table is
covered (27 fixtures + UNSUPPORTED_QUERY & DRAFT_RENDER as behavior checks = 29/29):

| op | codes |
|---|---|
| validate | ID_GRAMMAR, UNKNOWN_NS, UNKNOWN_EDGE_TYPE, DUP_ID, DUP_EDGE, DANGLING_REF, MISSING_PROVENANCE, FIELD_UNCOVERED, DERIVED_FIELD_AUTHORED (+ member-of edge variant), SCHEMA_INVALID, CONFLICT_HARVEST, HARVEST_ORPHAN, ENTITY_UNBACKED, STALE_LOAD_BEARING, STALE_BUDGET, SKELETON_LOAD_BEARING, OVERLAY_MANDATE_DRIFT, OVERLAY_PROHIBITIONS_EMPTY, OVERLAY_DANGLING |
| render | SKELETON_UNRESOLVED, DIRTY_TREE, PACKET_OVER_BUDGET, GENERATED_DRIFT (+ DRAFT_RENDER, render-without-harvest behavior) |
| ingest-claims | CLAIM_RESTATES_HARVEST, CONFLICT_CLAIMS |
| harvest | PARSE_ROW_FAILED |
| fmt | FMT_NONCANONICAL |
| query | UNSUPPORTED_QUERY |

## Determinism evidence

- **Golden render digest = `0a1deec4619a4b29f1a545e5144d97b1feb018d2a799c3019e1a272139200b97`** -- byte-identical across the cloud (3.11), the mount VM box side (3.10), and the committed `fixtures/golden-generated/` (cloud-vs-box parity, RT1 F5/F17).
- Double-run render: byte-identical. Shuffle test (permuted FS/item order): byte-identical. CRLF vs LF copies of a map file: sha256-equal (all hashing over CRLF->LF-normalized bytes).
- Real seed determinism: double-seed of the real repo = byte-identical (`2c2f127a...`), and equals the on-disk `map/`.

## parse_budgets import parity

`parse_budgets()` is IMPORTED via importlib from `ops/audit/gen-doc-health.py` (no local
re-implementation; verifier grep-confirmed). Fixture-table parity green; `_parse_doc_owner_rows` adds
the WO owner-row parse contract and hard-errors PARSE_ROW_FAILED on a malformed s2 row.

## One refusal envelope (quoted)

```json
{ "status": "error",
  "result": { "findings": [
     { "code": "DANGLING_REF",
       "where": "edge module:90/alpha.tool -[invokes]-> module:99/missing",
       "message": "edge 'to' 'module:99/missing' does not resolve" } ] },
  "error": { "code": "DANGLING_REF", "message": "validation failed", "retryable": false } }
```

Exit code 0 (logical refusal), status `error`, machine `error.code` from the closed table,
`result.findings` lists every finding. Nonzero exit is reserved for crashes only (verified).

## BOOT_PACKET golden size + ladder behavior

Golden BOOT_PACKET = **2,030 bytes** (well under the 20,000 B HARD cap), ladder `[]` (no degradation
needed), 0 stale, KB=1000. The ladder is exercised by the PACKET_OVER_BUDGET fixture (320 entities):
recorded steps `['one_line truncation -> 72', '-> 56', 'collapse mvp-complete widgets to counts']`,
then still 27,705 B > 20,000 B -> refuses `PACKET_OVER_BUDGET` (ladder steps recorded in the envelope,
never silent, RT1-F16).

## Cloud suite (WO s6) -- 49/49 GREEN on BOTH python3 3.11 (cloud) and 3.10 (mount VM)

golden 3/3 (validate + render + byte-identity), determinism 3/3 (double-run + shuffle + CRLF),
negative 33/33 (full-table coverage), drift 2/2, parse_budgets parity 1/1, ingest 2/2 (idempotent
double-ingest + interrupted-ingest leaves map/ untouched), reaffirm 2/2 (restamp + refuses derived),
fmt 2/2, changed-since 1/1. -Live full-repo smoke (`-RepoState Skeleton`): counts sanity all pass, 0
orphans, 0 unbacked, validate 0 findings.

## Independent verification

An independent adversarial subagent re-ran the suite and spot-checked RT1 F2/F3/F4/F5/F9/F12/F13/F15/
F16/F24 against the source: all PASS, no functional defects. It surfaced two low-severity deviations
which have since been FIXED and re-gated: (A) the discrete manifest `side_effects` field (WO s5) was
missing -> added; (B) ingest atomic-swap staged/backup dirs landed at the module root -> now staged
under `runtime/` (declared, gitignored write scope). Fixture #0 is accepted byte-verbatim.

## Deviations from the WORK_ORDER (with reasons)

1. **pwsh gate not run in THIS session (run on python3 instead).** The mount VM this cloud session
   bridges to is Linux with Python 3.10.12 and NO pwsh; pwsh 7.4.6 is Windows-box-only. ALL substantive
   logic lives in the stdlib `project_map.py` (the pwsh entrypoint + test file are thin wrappers), and
   the full WO s6 suite was run green via python3 on BOTH 3.11 (cloud) and 3.10 (mount VM), plus the
   -Live full-repo smoke. `Invoke-ProjectMap.ps1` + `Invoke-ProjectMapTests.ps1` are written and ready
   to smoke-run on the box; they were not executed here for lack of pwsh. Reason: environment, not
   design -- the mechanism-under-test is fully exercised.
2. **5 plane entities seeded as structural constants.** WO s7 says "harvest ONLY", but plane entities
   must exist as `member-of`/edge endpoints and the 5-plane set is a fixed closed enum (D-0080
   doctrine), not judgment. Seeded with one_line sourced to `doc:core-docs/ARCHITECTURE_MAP.md`. No
   per-module plane assignment was authored (that is the claims lane's). Recorded here per WO s7/s8.

## Open items (honest)

- **devship / git commit is a Windows-box step, NOT done from this session.** Git in the connected
  folder is lock-blocked from the Linux mount VM (stale `.git/index.lock`, "Operation not permitted"),
  and there is no pwsh/executor/res.lease here. All named module files are on disk under
  `modules/44-project-map/` (WORK_ORDER/design/eval left intact; nothing under `claims/`). Per RT1-F11
  the map+generated commit is the orchestrator's FINAL close commit at fold, and the fold re-runs the
  suite -- so the commit is downstream by design. The code files can be devshipped on the box if a
  worker-level commit is wanted.
- The `-Live` cloud-vs-box **pwsh** smoke + digest parity and the ps1 wrappers should be smoke-run on
  the box (the python digest parity is already proven: cloud == box == committed golden).
- Fold (orchestrator-owned): ingest Lane B's `claims/i46-repo-claims.json`, author the real overlay
  (verbatim handoff-s4 frontier), full validate to 0 with skeletons cleared, land i46 close core-doc
  edits, re-harvest, non-draft render, `--check`/double-run gates, then the final map+generated commit.

- Transfer artifact `_to_delete/pcb_build.tar.gz` can be deleted (device_bash cannot rm; left in the
  repo's existing `_to_delete/` staging dir).
