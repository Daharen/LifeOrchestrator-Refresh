# Module 36 -- artifact.search

**Deterministic SQLite catalog + hybrid LEXICAL (FTS5) search substrate.** The Collective Agent's
authoritative catalog (D-0080 Wave 1, arch position 23). A thin PowerShell entrypoint
(`Invoke-ArtifactSearch.ps1`, `pwsh-file`) over a stdlib-only Python worker (`artifact_search.py`) that owns
a SQLite database with SQLite FTS5. CPU-only, no model, no network, `determinism=deterministic`.

Contract: `SKILL_CONTRACT.md` (v0.2). Schema + both D-0077 interfaces: `SCHEMA_NOTES.md` (authoritative for
the fold). Work order: `WORK_ORDER.md`.

## Ops

| op | purpose |
|---|---|
| `ingest` | walk a root, content-hash inventory, detect new/changed/moved/deleted, Markdown-aware chunk (+ text fallback), FTS5 index, MOCK-embed (the D-0077 seam), reconcile with NO dup chunks, DB integrity check, deterministic `catalog_digest` |
| `search` | hybrid retrieval (`mode fts` \| `exact`); ranked, provenance-complete hits in DETERMINISTIC order -- the retriever interface (#37 consumes) |
| `embed` | the embedding-provider envelope (mock hashed pseudo-vectors); shape matches the real adapter #35 |
| `integrity` | PRAGMA integrity_check + catalog invariants |
| `catalog` | `catalog_digest` + counts |
| `export-chunk-texts` | ordered `[{chunk_id, rel_path, content_hash, span, text}]` -- fold input |
| `store-embeddings` | load externally-produced vectors by `chunk_id` -- fold drop-in for #35 |

## Invocation

```powershell
# index a corpus (creates the db)
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op ingest -Source core-docs -Root ..\..\core-docs -DbPath .\runtime\catalog\as.db

# search it
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op search -Query "resource lease" -Mode fts -K 5 -DbPath .\runtime\catalog\as.db
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -Op search -Query "D-0077" -Mode exact -DbPath .\runtime\catalog\as.db

# generic InputsJson (filters, batch texts, etc.)
pwsh -NoProfile -File .\Invoke-ArtifactSearch.ps1 -InputsJson '{"op":"search","query":"frobnicate","mode":"exact","db":"...","filters":{"type":"markdown_section","path_prefix":"docs/"}}'
```

Also callable through the Module 1 wrapper (`modules/01-skill-bootstrap/Invoke-Skill.ps1 -SkillDir <this dir>
-InputsJson '<...>'`). Every invocation emits one `lifeorch.skill.result/0.1` envelope on stdout and writes
`result.json` + op artifacts (`ingest_report.json`, `search_results.json`, ...) under
`runtime/artifacts/<invocation_id>/`. Exits 0 whenever a valid envelope is produced.

## Requirements

- `pwsh >= 7.4`.
- A `python >= 3.8` whose stdlib `sqlite3` has **FTS5** (probed by the wrapper: `CREATE VIRTUAL TABLE ...
  USING fts5`). On this box that is `C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe`;
  the wrapper resolves it (config shim -> literal -> `where.exe` fallbacks) or takes `-PythonPath`.

## Determinism

Chunk/document/version ids are content+path derived; `catalog_digest` is byte-identical for identical corpus
**content** across runs AND machines (repo-relative paths + byte spans). The SQLite file itself is NOT
byte-reproducible. See `SCHEMA_NOTES.md` section 1.

## Tests

```
pwsh -NoProfile -File tests\Invoke-ArtifactSearchTests.ps1 [-PythonPath <python>] [-PwshPath <pwsh>]
```

Runs the REAL wrapper -> worker (no mock) over the bundled `fixtures/repo` and, when present, a bounded slice
of the real `core-docs`. The same harness is the cloud off-machine gate and the live Windows/executor gate.

## Layout

```
Invoke-ArtifactSearch.ps1   entrypoint (pwsh-file)
artifact_search.py          worker (SQLite + FTS5, stdlib only)
skill.json                  manifest (contract v0.2)
SCHEMA_NOTES.md             schema + D-0077 interfaces (fold-authoritative)
WORK_ORDER.md               work order
fixtures/repo/              bundled fixture corpus (markdown + text)
tests/                      Invoke-ArtifactSearchTests.ps1
examples/                   example-invocation.md, example-result.json
runtime/                    gitignored: catalog/*.db, artifacts/<id>/
```

## Non-goals (later waves)

AST/call-graph/symbol index, summaries, episodes, failure memory, context compiler, UI, web search, REAL
embeddings (#35 ships the real adapter). No filesystem watcher (ingest is invoked + incremental).
