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

## v0.2 -- fencing + the GPU-lease split (all additive, default-off)

Hold a **revocable residency pin** on the GPU between exec ops, and learn (via `check`) if a higher-priority
demand revoked it -- the pin's `fencing_token` is your proof of authority:

```powershell
$e = pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource gpu -Holder governor -Kind residency_pin -Priority 1 -TtlSeconds 120 | ConvertFrom-Json
# ... between LLM calls ...
$c = pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action check -Resource gpu -FencingToken $e.result.fencing_token | ConvertFrom-Json
if ($c.result.fence_status -ne 'current') { <# revoked/fenced out -> stop issuing calls, evict cleanly, release #> }
```

A **prepared / evict-before-grant** acquire for a higher-priority GPU op: revoke the resident pin, confirm headroom
via the evictor seam, then grant. A `mock` evictor for tests; `command` mode plugs in the real PoolManager evictor:

```powershell
pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource gpu -Holder swapper -RequiredVramMiB 6700 -Priority 5 `
    -EvictorMode mock -MockEvictorResult needs_evict -MockFreeVramMiB 9000
# -> result.prepared=true, evict_performed=true, headroom_confirmed=true, revoked_pin={holder:governor,...}, fencing_token=<n>
```

**Build-then-verify** (finding 14): the lock service rejects holding `gpu` idle while taking `git`. Commit under
`git`, release it, then take `gpu` for the live verify -- or override with a recorded reason:

```powershell
# holding gpu, this is rejected: status=error, error.code=lock_order_violation
pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource git -Holder builder
# the rare genuine multi-hold:
pwsh -NoProfile -File .\Invoke-ResLease.ps1 -Action acquire -Resource git -Holder builder -AllowLockOrder -LockOrderReason "atomic commit+verify"
```
