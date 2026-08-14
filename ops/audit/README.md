# ops/audit -- doc-hygiene tooling (M2-A)

## doc-commit-gate.py -- the deterministic, fail-closed doc-commit gate

```
python ops/audit/doc-commit-gate.py --staged   [--repo PATH] [--message TEXT | --message-file PATH] [--date YYYY-MM-DD]
python ops/audit/doc-commit-gate.py --files F [F ...] [--repo PATH] [--message TEXT | --message-file PATH] [--date YYYY-MM-DD]
python ops/audit/doc-commit-gate.py --worktree [--repo PATH] [--message TEXT | --message-file PATH] [--date YYYY-MM-DD]
python ops/audit/doc-commit-gate.py --install-hook [--repo PATH]
```

- `--staged` -- what the installed `.git/hooks/pre-commit` calls: checks the current git INDEX
  (`git diff --cached`). PRIMARY enforcement; fires no matter which script performs the commit.
- `--files F [F ...]` -- checks a named list as if it were the staged set restricted to those
  paths. SECONDARY enforcement: the commit-task idiom calls this on the exact named files it is
  about to `git commit`, after its own staged-set assertion and before the commit itself.
- `--worktree` -- local dry run over the current working-tree bytes of `core-docs/**/*.md`
  (no commit needed; diff/added-line checks compare against HEAD). Never used by the hook.
- `--install-hook` -- idempotently (re)writes `.git/hooks/pre-commit` to the one canonical hook
  body and (re)writes `ops/audit/doc-gate-hook.sha256` with its digest. `ops/install-doc-gate.bat`
  is a thin ASCII wrapper that shells out to this exact command -- there is no second copy of the
  hook text anywhere to drift out of sync.

Exit codes: `0` pass (a WARN never changes this), `1` reject (see the report), `2` gate error
(fail-closed -- the gate could not complete its own checks; treat exactly like a reject).

The report is one JSON object per line on stdout, sorted by `(file, rule, severity)` so identical
input reproduces a byte-identical report. A short human-readable summary goes to stderr.

## Known limitation: commit-message visibility in the pre-commit path

Verified empirically against real git (no env var, argv, or a current `.git/COMMIT_EDITMSG`
carries the message-in-progress at pre-commit time -- that file, when present at all, holds the
PREVIOUS attempt's stale text): a git pre-commit hook runs *before* the commit message exists.
Consequence -- when this gate runs via `--staged` with no `--message`/`--message-file` (the
installed hook's normal mode), `GATE_OVERRIDE:` and the re-layer note reference can never be
honored; an over-budget or over-40KB staged doc is rejected unconditionally there, fail-closed.
Those escape hatches are only reachable through the SECONDARY `--files --message` invocation
(the caller already knows the message it is about to commit) or by re-running the gate by hand
with `--message` before committing for real. This is a deliberate resolution of a real git
constraint, not a missing feature, and it keeps the "no silent bypass" property intact: a hook
that cannot see the message cannot be fooled by one either.

## gen-doc-health.py -- hook-presence assertion (read-only)

`gen-doc-health.py` now also reports whether the M2-A hook is installed and current: it compares
the sha256 of the installed `.git/hooks/pre-commit` against the manifest written by
`--install-hook` (`ops/audit/doc-gate-hook.sha256`). Missing manifest, missing hook, or a hash
mismatch (stale hook) all read RED, both in the regenerated monitor HTML and as a
`doc_gate_hook: {status, detail}` field in each `doc-health-log.jsonl` row. The monitor stays
read-only and everything else about its output is unchanged.

## Tests

```
python ops/audit/tests/test_doc_commit_gate.py
python ops/audit/tests/test_gen_doc_health_hook.py
```

Pure stdlib (`unittest` + a throwaway real git repo per test, no fixtures outside these files).

## gen-retrieval-monitor.py -- standing per-wave retrieval-byte monitor (i55, PB-7 observability half)

Turns the migration gate's one-shot A/B charged-retrieval-byte number (D-0146 F-i53-eff; the byte-charging
method in `modules/44-project-map/eval/results/I53_RESULTS.md` + `EFFICIENCY-i53.md`) into a STANDING
per-wave measurement: one row per close in `ops/out/retrieval-bytes-log.jsonl`, mirroring
`gen-doc-health.py`'s row-per-close pattern. Read-only over its input; writes nothing but the appended row.

It does not observe retrieval itself (an agent's opens aren't filesystem state the way doc sizes are) -- it
rolls up a session's self-reported LEDGER (one JSON line per open; the RETRIEVAL PROTOCOL: "RECORD every
open in your ledger"). The rollup arithmetic is deterministic (sums + a fraction), no model judgement.

```
python ops/audit/gen-retrieval-monitor.py --ledger <path> --iteration <N> [--date YYYY-MM-DD]
                                           [--repo PATH] [--out-dir PATH]
```

**Ledger schema** (JSONL, one open per line, written by the agent as it works):
`{"kind": "boot_packet"|"section"|"card"|"query"|"whole_doc_open", "target": "<id/path/query form>",
"bytes": <int > 0>, "note": "<optional>"}`. `boot_packet` = the PCB BOOT_PACKET.md read (N4 BOOT bar
20,000 B). `section`/`card`/`query` = a bounded `project_map.py query --q` fetch -- the retrieval the
RETRIEVAL PROTOCOL steers agents toward. `whole_doc_open` = a full-file ingest, charged its on-disk byte
size. Unknown keys/kind, a non-object line, or a non-positive-int `bytes` are FAIL-CLOSED: the whole run
rejects (exit 1) and nothing is appended -- a bad ledger must not silently mis-count.

**Output row:** `{date, iteration, boot_packet_bytes, total_charged_bytes, whole_doc_open_bytes,
bounded_query_bytes, bounded_fraction, whole_doc_opens[{target,bytes,warnings?}], n_queries,
boot_packet_bar{limit_bytes,status}, warnings[{target,bytes,reasons}], ledger_entries, ledger_source}`.
`bounded_fraction` = bounded-query bytes / total charged bytes (null when total is 0). A `whole_doc_open` of
a re-layer-eligible cumulative doc (`DECISION_LOG.md`/`DECISION_LOG_INDEX.md`) or of anything > 40,000 B
(the DOC_PROTOCOL s2 re-layer trigger) is a WARN in `warnings`, never a reject -- exit code stays 0.

**Exit codes:** `0` row emitted; `1` ledger content rejected (fail-closed, nothing written); `2` usage/I-O
error (e.g. ledger file not found).

**Run at wave close, alongside `gen-doc-health.py`** (see `FANOUT_ORCHESTRATOR_HANDOFF.md` s4 wave loop):
after the wave's per-session ledgers land under `ops/audit/retrieval-ledger/i<N>-<worker>.jsonl`, run this
script once per ledger (or a merged per-wave ledger) with `--iteration <N>`. `ops/gen-retrieval-monitor.bat`
is the click-to-run wrapper (mirrors `ops/gen-doc-health.bat`). First real row: i55, FANOUT_AGENT_002's own
construction session -- `ops/audit/retrieval-ledger/i55-agent002.jsonl` (14 opens, all `whole_doc_open` +
one `boot_packet`, 0 bounded queries; `bounded_fraction=0.0`). Honest first finding: this build session
reproduced F-i53-eff's pattern -- it defaulted to whole-doc opens (including of the BOOT_PACKET itself)
rather than `section:`/`card:` fetches, even though PB-7/i53 both flag bounded fetches as the cheaper path.
No WARN fired (nothing here is a cumulative doc or over 40 KB) but the 0% bounded fraction is the kind of
drift this monitor exists to catch early, wave over wave, rather than only at the next migration gate.

### Tests

```
python ops/audit/tests/test_retrieval_byte_monitor.py
```

Pure stdlib (`unittest` + a checked-in fixture ledger at `ops/audit/tests/fixtures/retrieval-ledger-fixture.jsonl`,
covering all 5 kinds, a blank-line skip, and a double-WARN case). Includes a double-run byte-identical gate
(two independent runs against the same fixture ledger produce the identical row).
