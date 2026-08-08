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
