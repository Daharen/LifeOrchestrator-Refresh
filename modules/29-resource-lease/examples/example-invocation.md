# res.lease -- example invocations

Acquire the GPU lease for a 5-minute model run (non-blocking; fails fast if held):

```powershell
pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource gpu -Holder worker-A -TtlSeconds 300
# -> result.acquired = true, result.lease_id = "<guid>", result.expires_at_utc = "..."
```

Wait up to 30 s for the git commit lock, then commit, then release:

```powershell
$env = pwsh -NoProfile -File .\Invoke-ResLease.ps1 -InputsJson '{"action":"acquire","resource":"git","holder":"worker-A","wait_seconds":30}' | ConvertFrom-Json
if ($env.result.acquired) {
    # ... git add / git commit here ...
    pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action release -Resource git -LeaseId $env.result.lease_id
}
```

Renew a long-held lease before it expires, then check every lease on the box:

```powershell
pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action renew  -Resource gpu -LeaseId <id> -TtlSeconds 300
pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action list
```

Take doc-ownership of a shared core-doc before editing it:

```powershell
pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource "doc:CURRENT_STATE.md" -Holder worker-A -WaitSeconds 20
```
