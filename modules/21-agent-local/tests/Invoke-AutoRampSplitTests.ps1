#requires -Version 7.0
# OFF-MACHINE tests for the i21 R1b CONSUMER wave: agent.local governor -SplitLease adoption of the
# res.lease 0.4.0 GPU-lease split. Drives the REAL Invoke-AutoRamp.ps1 against the mock gateway (wrapped
# to CAPTURE child inputs) + the REAL Invoke-ResLease.ps1, so it runs on the cloud pre-ship gate AND,
# unchanged, live via the executor.
#
# Covers: (R1) DEFAULT-OFF byte-identity -- no split key, classic whole-task exec lease unchanged;
# (R2) -SplitLease ON: the model-affine segment holds a revocable RESIDENCY PIN (kind residency_pin in the
# lease file), the child gateway calls carry use_pool_lease_split + split_priority + owner_incarnation_id,
# and the pin is released by holder at segment end (leases dir clean); (R3) single-agent EQUALITY: the same
# scripted run with the flag OFF vs ON produces IDENTICAL epochs / final_status / swap counts / output.
# ASCII-only. Exit 0 iff all pass.
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$here       = $PSScriptRoot
$controller = (Resolve-Path -LiteralPath (Join-Path $here '..\Invoke-AutoRamp.ps1')).Path
$mockGw     = (Resolve-Path -LiteralPath (Join-Path $here 'mock-gateway.ps1')).Path
$mockTool   = (Resolve-Path -LiteralPath (Join-Path $here 'mock-tool.ps1')).Path
$reslease   = (Resolve-Path -LiteralPath (Join-Path $here '..\..\29-resource-lease\Invoke-ResLease.ps1')).Path
$models     = (Resolve-Path -LiteralPath (Join-Path $here '..\..\07-model-gateway\models.json')).Path

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ar-split-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
$leaseDir = Join-Path $TempRoot 'leases'; New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

# capture wrapper: records every child-gateway InputsJson line, then delegates to the shared mock gateway
$capFile = Join-Path $TempRoot 'gw-inputs.capture.jsonl'
$capGw = Join-Path $TempRoot 'capture-gateway.ps1'
$capBody = @'
[CmdletBinding()]
param([string]$InputsJson, [string]$ArtifactRoot, [string]$InvocationId)
$ErrorActionPreference = 'Stop'
try { [System.IO.File]::AppendAllText($env:ARSPLIT_CAPTURE, $InputsJson + "`n", [System.Text.UTF8Encoding]::new($false)) } catch { }
$fwd = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File', $env:ARSPLIT_REALMOCK, '-InputsJson', $InputsJson)
if (-not [string]::IsNullOrWhiteSpace($ArtifactRoot)) { $fwd += @('-ArtifactRoot', $ArtifactRoot) }
if (-not [string]::IsNullOrWhiteSpace($InvocationId)) { $fwd += @('-InvocationId', $InvocationId) }
& $env:ARSPLIT_PWSH @fwd
exit $LASTEXITCODE
'@
[System.IO.File]::WriteAllText($capGw, $capBody, $utf8)
$env:ARSPLIT_CAPTURE = $capFile
$env:ARSPLIT_REALMOCK = $mockGw
$env:ARSPLIT_PWSH = $PwshPath

# mock tools registry (doc.io -> the mock tool)
$toolsFile = Join-Path $TempRoot 'mock-tools.json'
@{ tools = @(
    @{ tool='doc.io'; skill_id='doc.io'; entrypoint=$mockTool; description='write a text file'; args_hint='op,path,content'; args_example=@{op='write';path='x.txt';content='hi'}; required=@('op','path'); side_effecting=$true }
) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $toolsFile -Encoding utf8

function Run-Ramp([string]$Name, [hashtable]$ExtraInputs) {
    $sc = Join-Path $TempRoot "sc-$Name"; New-Item -ItemType Directory -Path $sc -Force | Out-Null
    $f = Join-Path $sc 'ok.txt'
    $plan = @{ decisions=@(@{text='doc.io';finish_reason='stop'}, @{text='finish';finish_reason='stop'}); args=@{ 'doc.io'=@{op='write';path=$f;content='VERIFIED'} } }
    $planFile = Join-Path $TempRoot "plan-$Name.json"; ($plan | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $planFile -Encoding utf8
    $stateFile = Join-Path $TempRoot "state-$Name.txt"; if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
    $argStateFile = Join-Path $TempRoot "argstate-$Name.txt"; if (Test-Path $argStateFile) { Remove-Item $argStateFile -Force }
    $warmReg = Join-Path $TempRoot "warm-$Name.json"; if (Test-Path $warmReg) { Remove-Item $warmReg -Force }
    $env:AR_MOCK_PLAN = $planFile; $env:AR_MOCK_STATE = $stateFile; $env:AR_MOCK_ARGSTATE = $argStateFile
    $contract = @{ schema='lifeorch.goal_verification/0.1'; predicates=@(@{predicate='file_exists';path=$f}, @{predicate='artifact_nonempty';path=$f}) }
    $inp = [ordered]@{ goal='Write VERIFIED to ok.txt'; working_dir=$sc; gpu_lease='auto'; gpu_lease_holder=("ar-split-"+$Name); gpu_lease_ttl_s=120; max_total_steps=8; success_contract=$contract }
    if ($null -ne $ExtraInputs) { foreach ($k in $ExtraInputs.Keys) { $inp[$k] = $ExtraInputs[$k] } }
    $arts = Join-Path $TempRoot "arts-$Name"
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$controller,
        '-InputsJson',($inp | ConvertTo-Json -Depth 20 -Compress),
        '-GatewayPath',$capGw,'-ToolsPath',$toolsFile,'-ResLeasePath',$reslease,'-LeaseDir',$leaseDir,
        '-WarmRegistryPath',$warmReg,'-Registry',$models,'-PwshPath',$PwshPath,'-ArtifactRoot',$arts)
    $errf = Join-Path $TempRoot "err-$Name.txt"
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & $PwshPath @a 2> $errf
    $ErrorActionPreference = $prev
    $txt = ($out | Out-String).Trim()
    $envObj = $null; try { $envObj = $txt | ConvertFrom-Json } catch { }
    $errTxt = ''; try { $errTxt = Get-Content -LiteralPath $errf -Raw -ErrorAction SilentlyContinue } catch { }
    return @{ env=$envObj; result=$(if ($null -ne $envObj) { $envObj.result } else { $null }); stderr=$errTxt; file=$f }
}
function ReadLease {
    $f = Get-ChildItem -LiteralPath $leaseDir -Filter 'gpu-*.lease' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $f) { return $null }
    try { return (Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json) } catch { return $null }
}

Write-Output "==== agent.local -SplitLease tests (i21 R1b consumer adoption; mock gateway + real res.lease) ===="
Write-Output "pwsh=$PwshPath"; Write-Output "controller=$controller"; Write-Output ""

# R1: DEFAULT-OFF byte-identity
[System.IO.File]::WriteAllText($capFile, '', $utf8)
$r1 = Run-Ramp 'off' $null
Ok ($null -ne $r1.result) 'R1 OFF run produced an envelope'
Ok ($null -ne $r1.result -and $r1.result.final_status -eq 'verified_success') "R1 OFF verified_success (got $($r1.result.final_status))"
$gl1 = if ($null -ne $r1.result) { $r1.result.gpu_lease } else { $null }
Ok ($null -ne $gl1 -and -not (Has $gl1 'split')) 'R1 OFF: gpu_lease carries NO split key (byte-identical surface)'
$gl1Keys = if ($null -ne $gl1) { @($gl1.PSObject.Properties.Name) -join ',' } else { '' }
Ok ($gl1Keys -eq 'mode,available,acquired,owned,already_held,lease_id,holder,renew_count,released,lost') "R1 OFF: gpu_lease key set unchanged (got $gl1Keys)"
Ok ($null -ne $gl1 -and $gl1.acquired -eq $true -and $gl1.released -eq $true) 'R1 OFF: classic whole-task lease acquired + released'
$cap1 = Get-Content -LiteralPath $capFile -Raw -ErrorAction SilentlyContinue
Ok (-not [string]::IsNullOrWhiteSpace($cap1) -and ($cap1 -notmatch 'use_pool_lease_split')) 'R1 OFF: child gateway inputs carry NO split keys'
Ok ($null -eq (ReadLease)) 'R1 OFF: lease file released (leases dir clean)'

# R2: -SplitLease ON -- pin for the model-affine segment; split keys threaded to every child gateway call
[System.IO.File]::WriteAllText($capFile, '', $utf8)
$r2 = Run-Ramp 'on' @{ split_lease = $true }
Ok ($null -ne $r2.result) 'R2 ON run produced an envelope'
Ok ($null -ne $r2.result -and $r2.result.final_status -eq 'verified_success') "R2 ON verified_success (got $($r2.result.final_status))"
$gl2 = if ($null -ne $r2.result) { $r2.result.gpu_lease } else { $null }
Ok ($null -ne $gl2 -and (Has $gl2 'split') -and $gl2.split.on -eq $true) 'R2 ON: gpu_lease.split present + on'
Ok ($null -ne $gl2 -and ([string]$gl2.split.kind -eq 'residency_pin') -and ([int]$gl2.split.priority -eq 30)) 'R2 ON: the segment hold is a residency_pin at the mid-tier priority (30)'
Ok ($null -ne $gl2 -and -not [string]::IsNullOrWhiteSpace([string]$gl2.split.owner_incarnation_id)) 'R2 ON: a per-run owner_incarnation_id was minted (v0.4 ABA identity)'
Ok ($null -ne $gl2 -and $gl2.acquired -eq $true -and $gl2.released -eq $true) 'R2 ON: pin acquired for the segment + released at segment end'
$cap2 = Get-Content -LiteralPath $capFile -Raw -ErrorAction SilentlyContinue
$capLines = @($cap2 -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$llmLines = @($capLines | Where-Object { $_ -notmatch '"evict_warm"' })
$allSplit = ($llmLines.Count -gt 0)
foreach ($ln in $llmLines) {
    $o = $null; try { $o = $ln | ConvertFrom-Json } catch { }
    if ($null -eq $o -or -not (Has $o 'use_pool_lease_split') -or -not [bool]$o.use_pool_lease_split) { $allSplit = $false }
    if ($null -eq $o -or -not (Has $o 'split_priority') -or ([int]$o.split_priority -ne 30)) { $allSplit = $false }
    if ($null -eq $o -or -not (Has $o 'owner_incarnation_id') -or ([string]$o.owner_incarnation_id -ne [string]$gl2.split.owner_incarnation_id)) { $allSplit = $false }
}
Ok $allSplit "R2 ON: EVERY LLM child call carried use_pool_lease_split + split_priority + the run's owner_incarnation_id ($($llmLines.Count) calls)"
Ok ($null -eq (ReadLease)) 'R2 ON: pin released by holder (leases dir clean; no residual pin)'
Ok ($null -ne $r2.stderr -and $r2.stderr -match 'split_lease ON: residency pin priority=30') 'R2 ON: governor diag confirms the split path engaged'

# R3: single-agent EQUALITY -- flag OFF vs ON: identical epochs / final_status / swaps / accepted answer
$e1 = @($r1.result.governor_trace | ForEach-Object { $_.epoch }) -join ','
$e2 = @($r2.result.governor_trace | ForEach-Object { $_.epoch }) -join ','
Ok ($e1 -eq $e2) "R3 identical epoch sequences (off=$e1 on=$e2)"
Ok ([int]$r1.result.model_swaps -eq [int]$r2.result.model_swaps) "R3 identical model_swaps (off=$($r1.result.model_swaps) on=$($r2.result.model_swaps))"
Ok ([string]$r1.result.final_status -eq [string]$r2.result.final_status -and [string]$r1.result.accepted_epoch -eq [string]$r2.result.accepted_epoch) 'R3 identical final_status + accepted_epoch'
$f1 = Get-Content -LiteralPath $r1.file -Raw -ErrorAction SilentlyContinue
$f2 = Get-Content -LiteralPath $r2.file -Raw -ErrorAction SilentlyContinue
Ok (([string]$f1 -eq [string]$f2) -and -not [string]::IsNullOrWhiteSpace([string]$f1)) 'R3 identical produced artifact (same tool output byte-for-byte)'

# R4: split with -GpuLease off degrades safely (flag ignored + warning; no split block)
$r4 = Run-Ramp 'gloff' @{ split_lease = $true; gpu_lease = 'off' }
Ok ($null -ne $r4.result -and $r4.result.final_status -eq 'verified_success') 'R4 split_lease + gpu_lease=off still completes (flag ignored)'
$gl4 = if ($null -ne $r4.result) { $r4.result.gpu_lease } else { $null }
Ok ($null -ne $gl4 -and -not (Has $gl4 'split')) 'R4 no split block when the gpu lease is off (safe degrade, warned)'

Write-Output ""
Write-Output "==== AR-SPLIT RESULT pass=$pass fail=$fail ===="
try { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
if ($fail -gt 0) { Write-Output 'FAILURES PRESENT'; exit 1 }
Write-Output 'ALL PASS'
exit 0
