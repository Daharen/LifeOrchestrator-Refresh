#requires -Version 7.0
<#
  Test harness for context.compile (Module 40). Exercises the Invoke-ContextCompiler.ps1 entrypoint
  END-TO-END with the deterministic MOCK retriever (off-machine + -Live), and -- when -Db/-RepoRoot are
  supplied -- the REAL artifact.search #36 retriever-0.2 seam (-Live acceptance).

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
# resolve a launcher pwsh (dev.ship substitutes {PWSH}; the dotnet-tool shim reports as dotnet.exe)
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

Write-Host "== context.compile entrypoint harness =="
Write-Host "[mock: compile end-to-end over fixtures/compile_case.json]"
$env1 = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix 'compile_case.json'))
Check "envelope status ok/partial" ($env1.status -in @('ok','partial')) "status=$($env1.status)"
Check "skill_id context.compile" ($env1.skill_id -eq 'context.compile')
$packet = $env1.result.result.packet
Check "packet schema 0.1" ($packet.schema -eq 'lifeorch.context_packet/0.1')
Check "packet_id present" ($packet.packet_id -like 'cpkt_*')
Check "excerpts present" ($packet.excerpts.Count -gt 0)
Check "all provenance reproduced" ($packet.evaluation_hooks.packet_metrics.provenance_reproduced_all -eq $true)
Check "one artifact emitted + hashed" ($env1.artifacts.Count -ge 1 -and $env1.artifacts[0].sha256.Length -eq 64)
$sha1 = $env1.artifacts[0].sha256

Write-Host "[mock: byte-identical re-run (deterministic packet artifact)]"
$env2 = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix 'compile_case.json'))
Check "packet artifact sha256 identical across runs" ($env2.artifacts[0].sha256 -eq $sha1) "$($env2.artifacts[0].sha256) vs $sha1"
Check "packet_id identical across runs" ($env2.result.result.packet.packet_id -eq $packet.packet_id)

Write-Host "[mock: diversity cap protects a distinct required source]"
$divCase = Get-Content -LiteralPath (Join-Path $Fix 'diversity_case.json') -Raw | ConvertFrom-Json -Depth 60
$envd = Run-CC @('-Op','compile','-Retriever','mock','-CaseFile',(Join-Path $Fix 'diversity_case.json'))
$dp = $envd.result.result.packet
$reqRvid = $divCase.'_required_rvid'
$exRvids = @($dp.excerpts | ForEach-Object { $_.record_version_id })
Check "required distinct source included" ($exRvids -contains $reqRvid) "excerpts=$($exRvids -join ',')"
$nearCount = @($dp.excerpts | Where-Object { $_.source_path -eq $divCase.'_near_source' }).Count
Check "near-dup source capped" ($nearCount -le $divCase.task.config.per_source_cap) "nearCount=$nearCount"

Write-Host "[mock: expand returns bounded raw source behind a summary]"
$envx = Run-CC @('-Op','expand','-Retriever','mock','-CaseFile',(Join-Path $Fix 'expand_case_full.json'))
$exp = $envx.result.result.expansion
Check "expand ok" ($envx.status -in @('ok','partial')) "status=$($envx.status)"
Check "expansion bounded within budget" ($exp.token_estimate -le $exp.budget_tokens)
Check "expansion truncated (raw bigger than budget)" ($exp.truncated -eq $true)

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
    Check "live packet has excerpts" ($null -ne $lp -and @($lp.excerpts).Count -gt 0) "excerpts=$(if($lp){@($lp.excerpts).Count})"
    Check "live excerpts provenance reproduced" ($null -ne $lp -and $lp.evaluation_hooks.packet_metrics.provenance_reproduced_all -eq $true) "reproduced=$(if($lp){"$($lp.evaluation_hooks.packet_metrics.provenance_reproduced_count)/$(@($lp.excerpts).Count)"})"
    Check "live packet within budget" ($null -ne $lp -and $lp.token_budget.used -le $lp.token_budget.budget)
    $lsha = $envL.artifacts[0].sha256
    $envL2 = Run-CC @('-Op','compile','-Retriever','artifact_search','-Task',$liveTask,'-DbPath',$DbPath,'-RepoRoot',$RepoRoot)
    Check "live packet byte-identical re-run" ($envL2.artifacts[0].sha256 -eq $lsha) "$($envL2.artifacts[0].sha256) vs $lsha"
    # live expand: raw_source behind the top excerpt (resolve directly from repo_root)
    if ($null -ne $lp -and @($lp.excerpts).Count -gt 0) {
        $top = @($lp.excerpts)[0]
        $reqJson = (@{ type='raw_source'; target=@{ record_version_id=$top.record_version_id }; budget=@{ max_tokens=40 } } | ConvertTo-Json -Depth 20 -Compress)
        $pf = Join-Path $env:TEMP ("cc_live_packet_" + [Guid]::NewGuid().ToString('N') + '.json')
        ($lp | ConvertTo-Json -Depth 60) | Set-Content -LiteralPath $pf -Encoding utf8
        $envE = Run-CC @('-Op','expand','-Retriever','artifact_search','-PacketFile',$pf,'-Request',$reqJson,'-DbPath',$DbPath,'-RepoRoot',$RepoRoot)
        $le = if ($null -ne $envE.result) { $envE.result.result.expansion } else { $null }
        Check "live expand returns bounded evidence" ($null -ne $le -and $le.evidence_count -ge 1 -and $le.token_estimate -le $le.budget_tokens) "count=$(if($le){$le.evidence_count})"
        Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue
    }
}

$total = $script:pass + $script:fail
Write-Host ""
Write-Host "== $($script:pass)/$total passed, $($script:fail) failed =="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
