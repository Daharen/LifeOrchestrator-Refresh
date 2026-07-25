#requires -Version 7.0
<#
  Invoke-AgentLocalTests.ps1 -- drives the REAL Invoke-AgentLocal.ps1 against tests/mock-child.ps1
  (a deterministic mock for the escalator / gateway / tools, branching on the -ArtifactRoot leaf).
  This runs OFF-GPU on any box with pwsh 7 (the cloud pre-ship gate) and, unchanged, live via the executor.
  A mock tool registry points doc.io + fs.observer at the mock. Scenarios are driven by markers in the goal.
  ASCII-only. Exits 0 iff every assertion passes.
#>
[CmdletBinding()]
param(
    [string]$PwshExe = (Join-Path $PSHOME 'pwsh'),
    [string]$AgentPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-AgentLocal.ps1'),
    [string]$MockPath  = (Join-Path $PSScriptRoot 'mock-child.ps1'),
    [string]$WrapperPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshExe)) { $alt = "$PwshExe.exe"; if (Test-Path -LiteralPath $alt) { $PwshExe = $alt } }
$AgentPath = (Resolve-Path -LiteralPath $AgentPath).Path
$MockPath  = (Resolve-Path -LiteralPath $MockPath).Path

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("m21-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$artRoot = Join-Path $work 'art'

# ---- mock tool registry: doc.io + fs.observer both point at the mock child ----
$mockTools = [ordered]@{ schema='lifeorch.agent.tools/0.1'; tools=@(
    [ordered]@{ tool='doc.io'; skill_id='doc.io'; entrypoint=$MockPath; description='mock doc io'; args_hint='op,path'; args_example=@{op='write';path='x.txt';content='y'}; required=@('op','path'); side_effecting=$true },
    [ordered]@{ tool='fs.observer'; skill_id='fs.observer'; entrypoint=$MockPath; description='mock fs observer'; args_hint='path'; args_example=@{path='.'}; required=@('path'); side_effecting=$false }
) }
$toolsPath = Join-Path $work 'mock-tools.json'
[System.IO.File]::WriteAllText($toolsPath, ($mockTools | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$name) { if ($c) { $script:pass++; Write-Output "  PASS  $name" } else { $script:fail++; Write-Output "  FAIL  $name" } }
function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

function Run-Agent([string]$goal, [string[]]$extra) {
    $callArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AgentPath,
        '-Goal',$goal,'-WorkingDir',$work,'-EscalatorPath',$MockPath,'-GatewayPath',$MockPath,
        '-ToolsPath',$toolsPath,'-PwshPath',$PwshExe,'-ArtifactRoot',$artRoot)
    if ($null -ne $extra) { $callArgs += $extra }
    $errF = Join-Path $work ("err-" + [Guid]::NewGuid().ToString('N') + ".txt")
    $out = & $PwshExe @callArgs 2> $errF
    $txt = ($out | Out-String).Trim()
    $env = $null; try { $env = $txt | ConvertFrom-Json } catch { }
    return @{ env=$env; raw=$txt; err=(Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue) }
}

Write-Output "==== agent.local mock-children harness ===="
Write-Output ("pwsh=" + $PwshExe)
Write-Output ("agent=" + $AgentPath)
Write-Output ""

# --- S1: single tool then finish ---
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' $null
$e = $r.env; $res = if ($null -ne $e) { $e.result } else { $null }
Write-Output "S1 write-then-finish:"
Ok ($null -ne $e -and $e.schema -eq 'lifeorch.skill.result/0.1' -and $e.status -eq 'ok') 'S1 envelope valid + status ok'
Ok ($null -ne $res -and $res.status -eq 'completed') 'S1 run completed'
Ok ($null -ne $res -and $res.step_count -eq 2) 'S1 two steps (tool + finish)'
Ok ($null -ne $res -and @($res.steps)[0].decision.chosen_tool -eq 'doc.io' -and @($res.steps)[0].tool.invoked -eq $true) 'S1 step1 invoked doc.io'
Ok ($null -ne $res -and @($res.steps)[1].decision.chosen_tool -eq 'finish') 'S1 step2 chose finish'
Ok ($null -ne $res -and $res.needs_frontier -eq $false) 'S1 needs_frontier false'
Ok ($null -ne $e -and @($e.model_provenance).Count -ge 3) 'S1 model_provenance aggregated (decision+arggen+final)'
Ok ($null -ne $e -and $null -ne $e.confidence) 'S1 confidence populated'
Ok ($null -ne $res -and $res.is_review_producer -eq $false) 'S1 not a review producer'

# --- S2: two tools then finish ---
$r = Run-Agent 'TWO_TOOLS: explore then write' $null
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S2 two-tools:"
Ok ($null -ne $res -and $res.status -eq 'completed') 'S2 completed'
Ok ($null -ne $res -and $res.step_count -eq 3) 'S2 three steps'
Ok ($null -ne $res -and @($res.steps)[0].decision.chosen_tool -eq 'fs.observer') 'S2 step1 fs.observer'
Ok ($null -ne $res -and @($res.steps)[1].decision.chosen_tool -eq 'doc.io') 'S2 step2 doc.io'
Ok ($null -ne $res -and @($res.steps)[2].decision.chosen_tool -eq 'finish') 'S2 step3 finish'
Ok ($null -ne $res -and @($res.steps)[0].observation -match 'match_names') 'S2 fs.observer observation carries matches'

# --- S3: dry-run invokes no tool ---
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' @('-DryRun')
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S3 dry-run:"
Ok ($null -ne $res -and $res.dry_run -eq $true) 'S3 dry_run flagged'
Ok ($null -ne $res -and @($res.steps)[0].tool.invoked -eq $false -and @($res.steps)[0].tool.status -eq 'dry_run') 'S3 step1 tool NOT invoked'
Ok ($null -ne $res -and (@($res.steps)[0].observation -like '`[dry-run`]*')) 'S3 observation is a dry-run preview'
Ok ($null -ne $res -and $res.status -eq 'completed') 'S3 still completes'

# --- S4: budget exhausted ---
$r = Run-Agent 'LOOP_FOREVER: never done' @('-MaxSteps','2')
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S4 max-steps:"
Ok ($null -ne $res -and $res.status -eq 'stopped') 'S4 stopped'
Ok ($null -ne $res -and $res.stop_reason -eq 'max_steps') 'S4 stop_reason=max_steps'
Ok ($null -ne $res -and $res.step_count -eq 2) 'S4 exactly max_steps steps'
Ok ($null -ne $res -and $res.needs_frontier -eq $true) 'S4 needs_frontier true'

# --- S5: needs_frontier passthrough ---
$r = Run-Agent 'FINISH_AFTER_ONE NF_LOW: risky' $null
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S5 needs_frontier passthrough:"
Ok ($null -ne $res -and $res.status -eq 'completed') 'S5 completed'
Ok ($null -ne $res -and @($res.steps)[0].decision.needs_frontier -eq $true) 'S5 step1 decision needs_frontier'
Ok ($null -ne $res -and $res.needs_frontier -eq $true) 'S5 top-level needs_frontier true despite completed'

# --- S6: bad arg JSON ---
$r = Run-Agent 'FINISH_AFTER_ONE BAD_ARGS: make a file' $null
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S6 bad-args:"
Ok ($null -ne $res -and (@($res.steps)[0].error -match 'arg_parse_failed')) 'S6 step1 arg_parse_failed'
Ok ($null -ne $res -and @($res.steps)[0].tool.invoked -eq $false) 'S6 tool not invoked on bad args'
Ok ($null -ne $res -and $res.status -eq 'completed') 'S6 recovers and finishes'

# --- S7: tool returns error ---
$r = Run-Agent 'FINISH_AFTER_ONE TOOL_ERR: read a file' $null
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S7 tool-error:"
Ok ($null -ne $res -and @($res.steps)[0].tool.invoked -eq $true) 'S7 tool invoked'
Ok ($null -ne $res -and @($res.steps)[0].tool.status -eq 'error' -and (@($res.steps)[0].tool.error -match 'mock_tool_error')) 'S7 tool error captured'
Ok ($null -ne $res -and (@($res.steps)[0].observation -match 'FAILED')) 'S7 observation notes the failure'
Ok ($null -ne $res -and $res.status -eq 'completed') 'S7 loop continues past a tool error'

# --- S8: unknown tool (out-of-set escape) ---
$r = Run-Agent 'UNKNOWN_TOOL: do something weird' $null
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S8 unknown-tool:"
Ok ($null -ne $res -and (@($res.steps)[0].error -match 'unknown_tool')) 'S8 unknown_tool recorded'
Ok ($null -ne $res -and $res.status -eq 'stopped' -and $res.needs_frontier -eq $true) 'S8 stopped + needs_frontier'

# --- S9: missing goal error path ---
$errF = Join-Path $work 'err-nogoal.txt'
$out = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AgentPath -InputsJson '{"working_dir":"x"}' -EscalatorPath $MockPath -GatewayPath $MockPath -ToolsPath $toolsPath -PwshPath $PwshExe -ArtifactRoot $artRoot 2> $errF
$eng = $null; try { $eng = ($out | Out-String).Trim() | ConvertFrom-Json } catch { }
Write-Output "S9 missing-goal:"
Ok ($null -ne $eng -and $eng.status -eq 'error' -and $eng.error.code -eq 'missing_parameter') 'S9 missing goal -> error envelope'

# --- S10: through the Module 1 wrapper ---
if (-not [string]::IsNullOrWhiteSpace($WrapperPath) -and (Test-Path -LiteralPath $WrapperPath)) {
    $skillDir = Split-Path -Parent $AgentPath
    $ij = [ordered]@{ goal='FINISH_AFTER_ONE: wrapper path'; working_dir=$work; escalator_path=$MockPath; gateway_path=$MockPath; tools_path=$toolsPath; pwsh_path=$PwshExe } | ConvertTo-Json -Compress
    $wout = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WrapperPath -SkillDir $skillDir -InputsJson $ij -PwshPath $PwshExe 2> (Join-Path $work 'err-wrap.txt')
    $wcode = $LASTEXITCODE
    $rep = $null; try { $rep = ($wout | Out-String).Trim() | ConvertFrom-Json } catch { }
    Write-Output "S10 Module-1 wrapper:"
    Ok ($null -ne $rep -and $rep.manifest_valid -eq $true) 'S10 manifest valid'
    Ok ($null -ne $rep -and $rep.envelope_valid -eq $true -and $rep.exit_code -eq 0) 'S10 envelope valid + skill exit 0'
    Ok ($wcode -eq 0) 'S10 wrapper exit 0'
} else {
    Write-Output "S10 Module-1 wrapper: SKIPPED (no -WrapperPath)"
}

# cleanup
try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Output ""
Write-Output ("==== RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
