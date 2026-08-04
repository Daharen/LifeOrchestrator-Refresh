#requires -Version 7.0
<#
  Test harness for context.compile 0.4 (Module 40, i32 Tier-0 seam repairs, D-0092). Exercises the
  Invoke-ContextCompiler.ps1 entrypoint END-TO-END with the deterministic MOCK retriever (off-machine +
  -Live), and -- when -Db/-RepoRoot are supplied -- the REAL artifact.search #36 retriever-0.2 seam
  (-Live acceptance). Validates the lifeorch.context_packet/0.2 shape: three regions (control_plane /
  task_input / evidence), packet_disposition, consumer_profile + transport, selpol selection, provenance
  modes, non_execution, byte-identical re-run, and the expand/0.2 immutable delta.

  Off-machine (cloud pwsh):   pwsh -NoProfile -File .\tests\Invoke-ContextCompilerTests.ps1
  -Live (real #36 retriever):  add  -Db <#36 catalog.db>  -RepoRoot <repo root>  [-Namespace core-docs]
#>
[CmdletBinding()]
param(
    [string]$DbPath,
    [string]$RepoRoot,
    [string]$Namespace = 'core-docs',
    [string]$PythonPath,
    [string]$PwshExe
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModuleDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$Entry = Join-Path $ModuleDir 'Invoke-ContextCompiler.ps1'
$Fix = Join-Path $ModuleDir 'fixtures'
$LauncherPwsh = if (-not [string]::IsNullOrWhiteSpace($PwshExe) -and (Test-Path -LiteralPath $PwshExe -PathType Leaf)) { $PwshExe }
                elseif (Test-Path -LiteralPath (Join-Path $PSHOME 'pwsh.exe') -PathType Leaf) { (Join-Path $PSHOME 'pwsh.exe') }
                elseif (Test-Path -LiteralPath 'C:\Users\just_\.dotnet\tools\pwsh.exe' -PathType Leaf) { 'C:\Users\just_\.dotnet\tools\pwsh.exe' }
                else { 'pwsh' }
$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  PASS  $name" }
    else { $script:fail++; Write-Host "  FAIL  $name  $detail" }
}
function Run-CC([string[]]$ccArgs) {
    $argv = @('-NoProfile','-File',$Entry) + $ccArgs
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) { $argv += @('-PythonPath',$PythonPath) }
    if (-not [string]::IsNullOrWhiteSpace($PwshExe)) { $argv += @('-PwshPath',$PwshExe) }
    $out = & $LauncherPwsh @argv 2>$null
    $text = ($out | Out-String).Trim()
    return $text | ConvertFrom-Json -Depth 60
}

Write-Host "== context.compile 0.4 entrypoint harness (i32 Tier-0 seam repairs) =="
Write-Host "[mock: compile end-to-end over fixtures/compile_case.json -> context_packet/0.2]"
$env1 = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix 'compile_case.json'))
Check "envelope status ok/partial" ($env1.status -in @('ok','partial')) "status=$($env1.status)"
Check "skill_id context.compile" ($env1.skill_id -eq 'context.compile')
Check "skill_version 0.4.0" ($env1.skill_version -eq '0.4.0') "ver=$($env1.skill_version)"
$packet = $env1.result.result.packet
Check "packet schema 0.2" ($packet.schema -eq 'lifeorch.context_packet/0.2')
Check "packet_id present" ($packet.packet_id -like 'cpkt_*')
Check "P0-1 non_execution true" ($packet.non_execution -eq $true)
Check "P0-1 three regions present" ($null -ne $packet.control_plane -and $null -ne $packet.task_input -and $null -ne $packet.evidence)
Check "control_plane descriptor-only provenance" ($packet.control_plane.provenance -eq 'descriptor_authority_fields_only')
Check "i32/U3 working_memory reserved region present + empty (no store)" ($null -ne $packet.working_memory -and $packet.working_memory.present -eq $false -and @($packet.working_memory.items).Count -eq 0)
Check "i32/U3 render order control->task->working_memory->evidence" (($packet.rendering.order -join ',') -eq 'control_plane,task_input,working_memory,evidence')
Check "i32/U5 query_class stamped in task_input + identity" ($null -ne $packet.task_input.query_class -and $packet.identity.query_class -eq $packet.task_input.query_class)
Check "i32/U1 allowed_namespaces stamped in task_input + identity" ($null -ne $packet.task_input.allowed_namespaces -and $null -ne $packet.identity.allowed_namespaces)
Check "evidence excerpts present" (@($packet.evidence.excerpts).Count -gt 0)
Check "every excerpt content_role=evidence/can_instruct=false" (@($packet.evidence.excerpts | Where-Object { $_.content_role -ne 'evidence' -or $_.can_instruct -ne $false }).Count -eq 0)
Check "P0-3 packet_disposition present" ($null -ne $packet.disposition.packet_disposition)
Check "P0-4 consumer_profile present" ($null -ne $packet.consumer_profile.max_context)
Check "P0-4 transport count_is_exact=false" ($packet.transport_accounting.count_is_exact -eq $false)
Check "P1-1 selection policy selpol_rrf_v1" ($packet.selection.policy_id -eq 'selpol_rrf_v1')
Check "P1-5 omission_manifest present (renamed)" ($null -ne $packet.omission_manifest)
Check "all provenance reproduced" ($packet.evaluation_hooks.packet_metrics.provenance_reproduced_all -eq $true)
Check "two artifacts emitted (packet + rendered_input)" ($env1.artifacts.Count -ge 2 -and $env1.artifacts[0].sha256.Length -eq 64)
$sha1 = (@($env1.artifacts | Where-Object { $_.path -like '*context_packet.json' })[0]).sha256

Write-Host "[mock: byte-identical re-run (deterministic packet artifact + packet_id)]"
$env2 = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix 'compile_case.json'))
$sha2 = (@($env2.artifacts | Where-Object { $_.path -like '*context_packet.json' })[0]).sha256
Check "packet artifact sha256 identical across runs" ($sha2 -eq $sha1) "$sha2 vs $sha1"
Check "packet_id identical across runs" ($env2.result.result.packet.packet_id -eq $packet.packet_id)

Write-Host "[mock: P0-3 packet_disposition across fixtures]"
foreach ($pair in @(@('disposition_needs_expansion.json','needs_expansion'),
                    @('disposition_abstain.json','abstain'),
                    @('disposition_conflicted.json','conflicted'),
                    @('disposition_provenance_failed.json','provenance_failed'))) {
    $e = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix $pair[0]))
    $d = $e.result.result.packet.disposition.packet_disposition
    Check "disposition $($pair[0]) == $($pair[1])" ($d -eq $pair[1]) "got=$d"
}

Write-Host "[mock: P0-4 fail-closed transport drops oversize evidence -> needs_expansion, control_plane intact]"
$envt = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix 'transport_overflow_case.json'))
$tp = $envt.result.result.packet
Check "transport dropped >=1 for overflow" (@($tp.omission_manifest | Where-Object { $_.reason -eq 'transport_overflow' }).Count -ge 1)
Check "transport disposition needs_expansion" ($tp.disposition.packet_disposition -eq 'needs_expansion')
Check "completion_contract intact after transport drop" ($null -ne $tp.control_plane.completion_contract)

Write-Host "[mock: diversity cap protects a distinct required source]"
$divCase = Get-Content -LiteralPath (Join-Path $Fix 'diversity_case.json') -Raw | ConvertFrom-Json -Depth 60
$envd = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix 'diversity_case.json'))
$dp = $envd.result.result.packet
$reqRvid = $divCase.'_required_rvid'
$exRvids = @($dp.evidence.excerpts | ForEach-Object { $_.record_version_id })
Check "required distinct source included" ($exRvids -contains $reqRvid) "excerpts=$($exRvids -join ',')"
$nearCount = @($dp.evidence.excerpts | Where-Object { $_.source_path -eq $divCase.'_near_source' }).Count
Check "near-dup source capped" ($nearCount -le $divCase.task.config.per_source_cap) "nearCount=$nearCount"

Write-Host "[mock: expand -> lifeorch.context_expansion/0.2 immutable locked-snapshot delta]"
$envx = Run-CC @('-Op','expand','-Retriever','mock','-CaseFile',(Join-Path $Fix 'expand_case_full.json'))
$exp = $envx.result.result.expansion
Check "expand ok" ($envx.status -in @('ok','partial')) "status=$($envx.status)"
Check "expansion schema 0.2" ($exp.schema -eq 'lifeorch.context_expansion/0.2')
Check "expansion immutable + locked snapshot" ($exp.immutable -eq $true -and $exp.corpus_snapshot.locked_to_parent -eq $true)
Check "expansion bounded within budget" ($exp.token_estimate -le $exp.budget_tokens)

Write-Host "[mock: normalize op]"
$envn = Run-CC @('-Op','normalize','-Task',(Join-Path $Fix 'task_only.json'))
Check "normalize returns a query_set" ($envn.result.result.query_set.Count -gt 0)
Check "original_goal preserved verbatim" ($envn.result.result.original_goal.Length -gt 0)

if (-not [string]::IsNullOrWhiteSpace($DbPath)) {
    Write-Host "[-Live: REAL artifact.search #36 retriever-0.2 seam]"
    Check "db exists" (Test-Path -LiteralPath $DbPath -PathType Leaf) $DbPath
    $liveTask = Join-Path $Fix 'live_task.json'
    $envL = Run-CC @('-Op','compile','-Retriever','artifact_search','-Task',$liveTask,'-DbPath',$DbPath,'-RepoRoot',$RepoRoot)
    $envLerr = if ($null -ne $envL.error) { [string]$envL.error.message } else { '' }
    Check "live compile ok/partial" ($envL.status -in @('ok','partial')) "status=$($envL.status) err=$envLerr"
    $lp = if ($null -ne $envL.result) { $envL.result.result.packet } else { $null }
    Check "live packet schema 0.2 + non_execution" ($null -ne $lp -and $lp.schema -eq 'lifeorch.context_packet/0.2' -and $lp.non_execution -eq $true)
    Check "live packet has evidence excerpts" ($null -ne $lp -and @($lp.evidence.excerpts).Count -gt 0) "excerpts=$(if($lp){@($lp.evidence.excerpts).Count})"
    Check "live excerpts provenance reproduced" ($null -ne $lp -and $lp.evaluation_hooks.packet_metrics.provenance_reproduced_all -eq $true) "reproduced=$(if($lp){"$($lp.evaluation_hooks.packet_metrics.provenance_reproduced_count)/$(@($lp.evidence.excerpts).Count)"})"
    Check "live packet within excerpt budget" ($null -ne $lp -and $lp.token_budget.used -le $lp.token_budget.budget)
    Check "live packet disposition present" ($null -ne $lp -and $null -ne $lp.disposition.packet_disposition)
    Check "live packet corpus_version pinned" ($null -ne $lp -and $null -ne $lp.identity.corpus_version)
    $lsha = (@($envL.artifacts | Where-Object { $_.path -like '*context_packet.json' })[0]).sha256
    $envL2 = Run-CC @('-Op','compile','-Retriever','artifact_search','-Task',$liveTask,'-DbPath',$DbPath,'-RepoRoot',$RepoRoot)
    $lsha2 = (@($envL2.artifacts | Where-Object { $_.path -like '*context_packet.json' })[0]).sha256
    Check "live packet byte-identical re-run" ($lsha2 -eq $lsha) "$lsha2 vs $lsha"
    if ($null -ne $lp -and @($lp.evidence.excerpts).Count -gt 0) {
        $top = @($lp.evidence.excerpts)[0]
        $reqJson = (@{ type='raw_source'; target=@{ record_version_id=$top.record_version_id }; budget=@{ max_tokens=40 } } | ConvertTo-Json -Depth 20 -Compress)
        $pf = Join-Path $env:TEMP ("cc_live_packet_" + [Guid]::NewGuid().ToString('N') + '.json')
        ($lp | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $pf -Encoding utf8
        $envE = Run-CC @('-Op','expand','-Retriever','artifact_search','-PacketFile',$pf,'-Request',$reqJson,'-DbPath',$DbPath,'-RepoRoot',$RepoRoot)
        $le = if ($null -ne $envE.result) { $envE.result.result.expansion } else { $null }
        Check "live expand returns bounded evidence, locked snapshot" ($null -ne $le -and $le.evidence_count -ge 1 -and $le.token_estimate -le $le.budget_tokens -and $le.corpus_snapshot.locked_to_parent -eq $true) "count=$(if($le){$le.evidence_count})"
        Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue
    }
}

$total = $script:pass + $script:fail
Write-Host ""
Write-Host "== $($script:pass)/$total passed, $($script:fail) failed =="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
