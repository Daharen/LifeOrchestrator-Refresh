# Example invocation -- `decision.intel`

```powershell
pwsh -NoProfile -File .\Invoke-DecisionIntel.ps1 `
  -DecisionLogPath ..\..\core-docs\DECISION_LOG.md `
  -DecisionLogIndexPath ..\..\core-docs\DECISION_LOG_INDEX.md `
  -IngestedThrough 7309520abcdef0123456789abcdef0123456789
```

Or the generic form:

```powershell
pwsh -NoProfile -File .\Invoke-DecisionIntel.ps1 -InputsJson '{
  "op": "index",
  "decision_log_path": "core-docs/DECISION_LOG.md",
  "decision_log_index_path": "core-docs/DECISION_LOG_INDEX.md",
  "namespace": "decisions",
  "ingested_through": "7309520abcdef0123456789abcdef0123456789"
}'
```

`-IngestedThrough` is REQUIRED for `op=index`: the `DECISION_LOG.md` HEAD sha for this run, resolved by
the CALLER via a native `git rev-parse HEAD` (this worker never shells out to git -- mirrors the #38
repo.intel D-0072 no-git-in-worker rule).
