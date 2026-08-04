# working.memory -- example invocations

All access-controlled ops take the caller's namespace authorization: `-AllowedNamespaces` (the request) AND
`-PermissionGrants` (the control-plane grant). The effective set = their intersection. The store persists across
invocations at `-StorePath` (default `runtime/store/working_memory.db`).

Create a task's first state (v1):

```powershell
pwsh -NoProfile -File .\Invoke-WorkingMemory.ps1 -Op put_state -TaskId T1 -NamespaceScope projA `
  -Body '{"goal":"refactor","step":1}' -AllowedNamespaces projA -PermissionGrants projA
```

Advance under CAS (parent must equal the current head; a stale parent fails closed):

```powershell
pwsh -NoProfile -File .\Invoke-WorkingMemory.ps1 -Op put_state -TaskId T1 -Body '{"goal":"refactor","step":2}' `
  -ParentStateVersion 1 -AllowedNamespaces projA -PermissionGrants projA
```

Read the single active head (the #40 compiler consults this for the packet `working_memory` region):

```powershell
pwsh -NoProfile -File .\Invoke-WorkingMemory.ps1 -InputsJson '{"op":"get_active_head","task_id":"T1","allowed_namespaces":["projA"],"permission_grants":["projA"]}'
```

Promote the current state to a long-term `summary` record (the working record is not re-labeled):

```powershell
pwsh -NoProfile -File .\Invoke-WorkingMemory.ps1 -Op promote -TaskId T1 -AllowedNamespaces projA -PermissionGrants projA
```
