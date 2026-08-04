#requires -Version 7.0
<#
  Test suite for working.memory (module 42, 0.1.0). Two layers:
   (1) the deterministic Python worker gate  -- tests/test_working_memory.py (all A5 U3' invariants);
   (2) pwsh SKILL-level invocations through Invoke-WorkingMemory.ps1 on a fresh temp store (envelope shape,
       the persistent-store contract, conjunctive access fail-closed, search rejection, promote non-relabel).
  Deterministic, CPU-only, no model, no network. Exit 0 iff every check passes.
#>
[CmdletBinding()]
param([switch]$Live, [string]$PwshPath = 'pwsh')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$entry = Join-Path $root 'Invoke-WorkingMemory.ps1'
$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "ok   - $name" }
    else { $script:fail++; Write-Host "FAIL - $name" }
}
function Resolve-Python {
    foreach ($n in @('python3', 'python', 'py')) {
        try { $w = & where.exe $n 2>$null; foreach ($l in @([string[]]$w)) { if ($l -and (& $l.Trim() -c 'import sys;print(sys.version_info[0])' 2>$null).Trim() -eq '3') { return $l.Trim() } } } catch {}
    }
    foreach ($c in @('C:\Users\just_\AppData\Local\Programs\Python\Python312\python.exe','/usr/bin/python3')) { if (Test-Path $c) { return $c } }
    return $null
}
$py = Resolve-Python
if (-not $py) { Write-Host 'FAIL - no python 3 found'; exit 1 }

# ---- (1) the python worker gate ----
$pyTest = Join-Path $here 'test_working_memory.py'
$prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$out = & $py $pyTest 2>&1
$pyExit = $LASTEXITCODE
$ErrorActionPreference = $prev
$out | ForEach-Object { Write-Host "    [py] $_" }
Check 'python worker gate: exit 0 (all invariants)' ($pyExit -eq 0)
Check 'python worker gate: reports 0 failed' ([bool]("$out" -match '0 failed'))

# ---- (2) pwsh skill-level invocations on a fresh temp store ----
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wm-pwsh-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$store = Join-Path $tmp 'wm.db'
$art = Join-Path $tmp 'art'
function Invoke-WM([hashtable]$named) {
    $args = @{ StorePath = $store; ArtifactRoot = $art }
    foreach ($k in $named.Keys) { $args[$k] = $named[$k] }
    $json = & $PwshPath -NoProfile -File $entry @args
    return ($json | ConvertFrom-Json)
}
try {
    $r1 = Invoke-WM @{ Op = 'put_state'; TaskId = 'T1'; NamespaceScope = 'projA'; Body = '{"step":1}'; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'put_state v1 -> status ok'            ($r1.status -eq 'ok')
    Check 'put_state v1 -> state_version 1'       ($r1.result.state_version -eq 1)

    $r2 = Invoke-WM @{ Op = 'get_active_head'; TaskId = 'T1'; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'get_active_head (persistent store) finds v1' ([bool]$r2.result.found -and $r2.result.state_version -eq 1)

    $r3 = Invoke-WM @{ Op = 'put_state'; TaskId = 'T1'; Body = '{"step":2}'; ParentStateVersion = 1; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'put_state v2 (correct CAS) advances head' ($r3.result.state_version -eq 2)

    $r4 = Invoke-WM @{ Op = 'put_state'; TaskId = 'T1'; Body = '{"step":9}'; ParentStateVersion = 1; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'stale-parent CAS is fail-closed (status error, cas_conflict)' ($r4.status -eq 'error' -and $r4.error.code -eq 'cas_conflict')

    $r5 = Invoke-WM @{ Op = 'get_active_head'; TaskId = 'T1'; AllowedNamespaces = @('projB'); PermissionGrants = @('projB') }
    Check 'wrong-namespace get_active_head is fail-closed (not found)' ($r5.result.found -eq $false -and $r5.result.reason -eq 'namespace_denied')
    Check 'wrong-namespace surfaces a violation COUNT only' ($r5.result.namespace_violation_count -eq 1)

    $r6 = Invoke-WM @{ Op = 'search'; RecordKind = 'working'; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'search rejects record_kind=working' ($r6.result.count -eq 0 -and [bool]$r6.result.working_excluded_from_search)

    $r7 = Invoke-WM @{ Op = 'promote'; TaskId = 'T1'; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'promote emits a summary derived record' ($r7.result.promoted_record_kind -eq 'summary' -and [bool]$r7.result.derives_from)
    $r8 = Invoke-WM @{ Op = 'get_active_head'; TaskId = 'T1'; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'promote did NOT re-label the working record (still retrievable)' ([bool]$r8.result.found)

    $r9 = Invoke-WM @{ Op = 'close'; TaskId = 'T1'; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    $r10 = Invoke-WM @{ Op = 'get_active_head'; TaskId = 'T1'; AllowedNamespaces = @('projA'); PermissionGrants = @('projA') }
    Check 'close removes the task from get_active_head' ($r10.result.found -eq $false)

    Check 'ns policy id stamped (ns_closed_v1)' ($r1.result.ns_policy_id -eq 'ns_closed_v1')
}
finally {
    try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ""
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
