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
    [ordered]@{ tool='fs.observer'; skill_id='fs.observer'; entrypoint=$MockPath; description='mock fs observer'; args_hint='path'; args_example=@{path='.'}; required=@('path'); side_effecting=$false },
    [ordered]@{ tool='fs.manage'; skill_id='fs.manage'; entrypoint=$MockPath; description='mock fs manage'; args_hint='op,source,dest'; args_example=@{op='copy';source='a';dest='desktop'}; required=@('op'); side_effecting=$true; resolve_paths=$false }
) }
$toolsPath = Join-Path $work 'mock-tools.json'
[System.IO.File]::WriteAllText($toolsPath, ($mockTools | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$name) { if ($c) { $script:pass++; Write-Output "  PASS  $name" } else { $script:fail++; Write-Output "  FAIL  $name" } }
function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

function Run-Agent([string]$goal, [string[]]$extra) {
    # D-0061: -AutoRamp is now DEFAULT-ON. These floor scenarios (S1-S18) exercise the STRICT FLOOR = the
    # explicit opt-out (-AutoRamp:$false), which reproduces the pre-D-0060 path byte-for-byte. The default
    # (controller) path is proven separately in S19/S20/S21 with the auto-ramp mock wiring.
    $callArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AgentPath,
        '-Goal',$goal,'-WorkingDir',$work,'-EscalatorPath',$MockPath,'-GatewayPath',$MockPath,
        '-ToolsPath',$toolsPath,'-PwshPath',$PwshExe,'-ArtifactRoot',$artRoot,'-AutoRamp:$false')
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
$out = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AgentPath -InputsJson '{"working_dir":"x"}' -EscalatorPath $MockPath -GatewayPath $MockPath -ToolsPath $toolsPath -PwshPath $PwshExe -ArtifactRoot $artRoot -AutoRamp:$false 2> $errF
$eng = $null; try { $eng = ($out | Out-String).Trim() | ConvertFrom-Json } catch { }
Write-Output "S9 missing-goal:"
Ok ($null -ne $eng -and $eng.status -eq 'error' -and $eng.error.code -eq 'missing_parameter') 'S9 missing goal -> error envelope'

# --- S10: through the Module 1 wrapper ---
if (-not [string]::IsNullOrWhiteSpace($WrapperPath) -and (Test-Path -LiteralPath $WrapperPath)) {
    $skillDir = Split-Path -Parent $AgentPath
    $ij = [ordered]@{ goal='FINISH_AFTER_ONE: wrapper path'; working_dir=$work; escalator_path=$MockPath; gateway_path=$MockPath; tools_path=$toolsPath; pwsh_path=$PwshExe; autoramp=$false } | ConvertTo-Json -Compress
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

# --- S11: -Route constrains the loop to the routed subset ---
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' @('-Route','-RouteToolsPath',$MockPath)
$e = $r.env; $res = if ($null -ne $e) { $e.result } else { $null }
Write-Output "S11 route-constrain:"
Ok ($null -ne $res -and $res.route_enabled -eq $true) 'S11 route_enabled true'
Ok ($null -ne $res -and @($res.planned_tools).Count -eq 1 -and @($res.planned_tools)[0] -eq 'doc.io') 'S11 planned_tools = [doc.io]'
Ok ($null -ne $res -and $res.route.applied -eq $true -and $res.route.fell_back -eq $false) 'S11 route applied (not fell back)'
Ok ($null -ne $res -and @($res.tools_available).Count -eq 1) 'S11 loop constrained to 1 tool'
Ok ($null -ne $res -and $res.status -eq 'completed') 'S11 still completes'
Ok ($null -ne $res -and @($res.outcome.succeeded_tools) -contains 'doc.io') 'S11 outcome grounds doc.io success'
Ok ($null -ne $e -and (@($e.model_provenance | Where-Object { $_.stage -eq 'route' }).Count -ge 1)) 'S11 route provenance stage present'

# --- S13: a resolve_paths=false tool receives an un-prefixed known-folder dest ---
$r = Run-Agent 'MANAGE_PATH: put the file on the desktop' @('-Route','-RouteToolsPath',$MockPath)
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S13 resolve_paths=false:"
Ok ($null -ne $res -and (@($res.planned_tools) -contains 'fs.manage')) 'S13 routed to fs.manage'
Ok ($null -ne $res -and @($res.steps)[0].decision.chosen_tool -eq 'fs.manage' -and @($res.steps)[0].tool.invoked -eq $true) 'S13 fs.manage invoked'
Ok ($null -ne $res -and [string](@($res.steps)[0].args.dest) -eq 'desktop') 'S13 dest NOT prefixed with working_dir (resolve_paths=false honored)'
Ok ($null -ne $res -and $res.status -eq 'completed') 'S13 completes'

# --- S12: -Route with an empty selection falls back to the full set ---
$r = Run-Agent 'ROUTE_EMPTY FINISH_AFTER_ONE: make a file' @('-Route','-RouteToolsPath',$MockPath)
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S12 route-empty-fallback:"
Ok ($null -ne $res -and @($res.planned_tools).Count -eq 0) 'S12 planned_tools empty'
Ok ($null -ne $res -and $res.route.fell_back -eq $true -and $res.route.applied -eq $false) 'S12 fell back to full set'
Ok ($null -ne $res -and @($res.tools_available).Count -eq 3) 'S12 full tool set restored'
Ok ($null -ne $res -and $res.status -eq 'completed') 'S12 still completes on the full set'

# --- S14: -Profile governor rungs (frugal|floor|max), default floor, and explicit-override precedence ---
Write-Output "S14 profile rungs:"
# default (no profile): the mid floor, 8 steps, no ladder
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' $null
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Ok ($null -ne $res -and $null -eq $res.profile) 'S14 default has no profile'
Ok ($null -ne $res -and ((@($res.decision_tiers) -join ',') -eq 'mid')) 'S14 default decision floor = mid (no tiny/weak)'
Ok ($null -ne $res -and $res.max_steps -eq 8) 'S14 default max_steps = 8'
# floor
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' @('-Profile','floor')
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Ok ($null -ne $res -and $res.profile -eq 'floor' -and (@($res.decision_tiers) -join ',') -eq 'mid' -and $res.max_steps -eq 8 -and $res.gen_tier -eq 'mid') 'S14 floor = {mid; gen mid; 8}'
# max: decide at the mid floor, generate with the 27B (gen strong); more headroom
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' @('-Profile','max')
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Ok ($null -ne $res -and $res.profile -eq 'max' -and (@($res.decision_tiers) -join ',') -eq 'mid' -and $res.gen_tier -eq 'strong' -and $res.max_steps -eq 10) 'S14 max = {mid; gen strong; 10}'
# precedence: an explicit -MaxSteps overrides the profile rung; the rest of the rung still fills in
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' @('-Profile','max','-MaxSteps','3')
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Ok ($null -ne $res -and $res.profile -eq 'max' -and $res.max_steps -eq 3 -and $res.gen_tier -eq 'strong' -and (@($res.decision_tiers) -join ',') -eq 'mid') 'S14 explicit -MaxSteps wins over the profile rung'
# invalid profile -> error envelope (fail closed)
$errF = Join-Path $work 'err-badprofile.txt'
$out = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AgentPath -Goal 'x' -WorkingDir $work -Profile 'bogus' -EscalatorPath $MockPath -GatewayPath $MockPath -ToolsPath $toolsPath -PwshPath $PwshExe -ArtifactRoot $artRoot -AutoRamp:$false 2> $errF
$eng = $null; try { $eng = ($out | Out-String).Trim() | ConvertFrom-Json } catch { }
Ok ($null -ne $eng -and $eng.status -eq 'error' -and $eng.error.code -eq 'invalid_profile') 'S14 invalid profile -> error envelope'

# --- S15: D-0032 terminator BLOCKS a premature finish and forces each unsatisfied planned tool (route/planned mode) ---
$r = Run-Agent 'PREMATURE_FINISH: generate a dog and place it on my desktop' @('-Route','-RouteToolsPath',$MockPath)
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S15 terminator-forces-planned:"
Ok ($null -ne $res -and $res.status -eq 'completed') 'S15 completed (did not stall or stop early)'
Ok ($null -ne $res -and @($res.planned_tools).Count -eq 2 -and (@($res.planned_tools) -contains 'doc.io') -and (@($res.planned_tools) -contains 'fs.manage')) 'S15 planned_tools = [doc.io, fs.manage]'
Ok ($null -ne $res -and $res.step_count -eq 3) 'S15 exactly 3 steps (forced doc.io, forced fs.manage, finish)'
Ok ($null -ne $res -and @($res.steps)[0].decision.chosen_tool -eq 'doc.io' -and @($res.steps)[0].tool.invoked -eq $true) 'S15 step1 forced doc.io despite finish decision'
Ok ($null -ne $res -and @($res.steps)[0].decision.terminator.finish_blocked -eq $true) 'S15 step1 terminator.finish_blocked recorded'
Ok ($null -ne $res -and @($res.steps)[1].decision.chosen_tool -eq 'fs.manage' -and @($res.steps)[1].tool.invoked -eq $true) 'S15 step2 forced the remaining planned tool fs.manage'
Ok ($null -ne $res -and @($res.steps)[2].decision.chosen_tool -eq 'finish') 'S15 step3 finish accepted once all planned tools succeeded'
Ok ($null -ne $res -and $res.terminator.enabled -eq $true -and $res.terminator.mode -eq 'planned') 'S15 terminator enabled in planned mode'
Ok ($null -ne $res -and $res.terminator.finish_blocked_count -ge 2) 'S15 finish blocked at least twice'
Ok ($null -ne $res -and (@($res.outcome.succeeded_tools) -contains 'doc.io') -and (@($res.outcome.succeeded_tools) -contains 'fs.manage')) 'S15 both planned tools actually succeeded (grounded)'

# --- S16: D-0032 repeat-action guard blocks re-running an already-succeeded (tool,args) and finishes deterministically ---
$r = Run-Agent 'REPEAT_LOOP: keep making the same file over and over' @('-Route','-RouteToolsPath',$MockPath,'-MaxSteps','6')
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S16 repeat-guard:"
Ok ($null -ne $res -and $res.status -eq 'completed') 'S16 completed (did NOT loop to max_steps)'
Ok ($null -ne $res -and $res.stop_reason -eq 'finish') 'S16 stop_reason=finish (deterministic finish)'
Ok ($null -ne $res -and $res.step_count -eq 2) 'S16 exactly 2 steps (run once, then repeat-blocked + finish)'
Ok ($null -ne $res -and @($res.steps)[0].decision.chosen_tool -eq 'doc.io' -and @($res.steps)[0].tool.invoked -eq $true) 'S16 step1 doc.io invoked'
Ok ($null -ne $res -and @($res.steps)[1].tool.invoked -eq $false -and @($res.steps)[1].tool.status -eq 'skipped_repeat') 'S16 step2 repeat NOT re-invoked'
Ok ($null -ne $res -and @($res.steps)[1].decision.terminator.repeat_blocked -eq $true) 'S16 step2 terminator.repeat_blocked recorded'
Ok ($null -ne $res -and $res.terminator.repeat_blocked_count -eq 1) 'S16 repeat_blocked_count = 1'
Ok ($null -ne $res -and $res.outcome.tools_invoked -eq 1) 'S16 doc.io invoked exactly once'

# --- S17: a well-behaved routed run is NOT spuriously blocked (terminator on, zero blocks) ---
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' @('-Route','-RouteToolsPath',$MockPath)
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S17 terminator-no-false-positive:"
Ok ($null -ne $res -and $res.status -eq 'completed') 'S17 completed'
Ok ($null -ne $res -and $res.terminator.enabled -eq $true) 'S17 terminator enabled (default ON under -Route)'
Ok ($null -ne $res -and $res.terminator.finish_blocked_count -eq 0) 'S17 no spurious finish blocks'
Ok ($null -ne $res -and $res.terminator.repeat_blocked_count -eq 0) 'S17 no spurious repeat blocks'
Ok ($null -ne $res -and $res.step_count -eq 2) 'S17 two steps (tool + finish)'

# --- S18: default OFF without -Route; routing-off heuristic (>=1 side-effecting) when explicitly enabled ---
$r = Run-Agent 'FINISH_AFTER_ONE: make a file' $null
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Write-Output "S18 default-off + heuristic fallback:"
Ok ($null -ne $res -and $res.terminator.enabled -eq $false) 'S18 terminator OFF by default when -Route absent'
$r = Run-Agent 'PREMATURE_FINISH: generate a dog and place it on my desktop' @('-RequirePlannedToolsBeforeFinish')
$res = if ($null -ne $r.env) { $r.env.result } else { $null }
Ok ($null -ne $res -and $res.status -eq 'completed') 'S18 heuristic run completes'
Ok ($null -ne $res -and $res.terminator.mode -eq 'heuristic') 'S18 heuristic mode (routing off, goal implies an output)'
Ok ($null -ne $res -and @($res.steps)[0].decision.chosen_tool -eq 'doc.io' -and @($res.steps)[0].tool.invoked -eq $true) 'S18 step1 forced a side-effecting tool (doc.io)'
Ok ($null -ne $res -and $res.terminator.finish_blocked_count -ge 1) 'S18 heuristic blocked the premature finish at least once'
Ok ($null -ne $res -and @($res.steps)[1].decision.chosen_tool -eq 'finish') 'S18 step2 finish accepted after one side-effecting success'

# ===================================================================================================
# D-0061: -AutoRamp is now DEFAULT-ON. S19-S21 prove the ENTRY-POINT flip using the auto-ramp controller's
# own mocks (mock-gateway + mock-tool, same tests dir). A default (no-flag) run must DELEGATE to the
# controller and, contract-less, fast-path at M0 (0 escalation, `completed`, not completed_unverified).
$testsDir = Split-Path -Parent $MockPath
$mockGw   = Join-Path $testsDir 'mock-gateway.ps1'
$mockTool = Join-Path $testsDir 'mock-tool.ps1'
$arTools  = Join-Path $work 'ar-tools.json'
@{ tools = @(@{ tool='doc.io'; skill_id='doc.io'; entrypoint=$mockTool; description='write a text file'; args_hint='op,path,content'; args_example=@{op='write';path='x.txt';content='hi'}; required=@('op','path'); side_effecting=$true }) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $arTools -Encoding utf8

function Run-DefaultController([string]$name, [string]$goal, $plan) {
    $planFile = Join-Path $work "arplan-$name.json"; ($plan | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $planFile -Encoding utf8
    $env:AR_MOCK_PLAN = $planFile
    $env:AR_MOCK_STATE = Join-Path $work "arstate-$name.txt"
    $env:AR_MOCK_ARGSTATE = Join-Path $work "arargstate-$name.txt"
    foreach ($p in @($env:AR_MOCK_STATE, $env:AR_MOCK_ARGSTATE)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
    $ij = [ordered]@{ goal=$goal; working_dir=$work; gpu_lease='off'; max_total_steps=6 } | ConvertTo-Json -Compress
    $errF = Join-Path $work "err-$name.txt"
    $out = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AgentPath -InputsJson $ij -GatewayPath $mockGw -ToolsPath $arTools -PwshPath $PwshExe -ArtifactRoot (Join-Path $artRoot $name) 2> $errF
    $env = $null; try { $env = ($out | Out-String).Trim() | ConvertFrom-Json } catch { }
    Remove-Item Env:\AR_MOCK_PLAN, Env:\AR_MOCK_STATE, Env:\AR_MOCK_ARGSTATE -ErrorAction SilentlyContinue
    return @{ env=$env; result=$(if ($null -ne $env) { $env.result } else { $null }); err=(Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue) }
}

# --- S19: default (no flag) delegates to the -AutoRamp controller; contract-less simple goal fast-paths at M0 ---
$s19f = Join-Path $work 's19.txt'
$r19 = Run-DefaultController 's19' 'make s19.txt (default autoramp)' @{ decisions=@(@{text='doc.io'}, @{text='finish'}); args=@{ 'doc.io'=@{op='write';path=$s19f;content='M0'} } }
$e19 = $r19.env; $res19 = $r19.result
Write-Output "S19 default-delegates-to-controller:"
Ok ($null -ne $e19 -and $e19.skill_id -eq 'agent.local.autoramp') 'S19 default (no flag) delegated to the -AutoRamp controller'
Ok ($null -ne $res19 -and $res19.autoramp -eq $true) 'S19 result.autoramp true'
Ok ($null -ne $res19 -and $res19.final_status -eq 'completed') 'S19 contract-less simple goal -> completed (terminator close)'
Ok ($null -ne $res19 -and $res19.final_status -ne 'completed_unverified') 'S19 NOT completed_unverified'
Ok ($null -ne $res19 -and $res19.accepted_epoch -eq 'M0') 'S19 resolved at epoch M0'
Ok ($null -ne $res19 -and [int]$res19.model_swaps -eq 0) 'S19 zero model swaps (no ramp)'
Ok ($null -ne $res19 -and (@($res19.epochs_visited) -notcontains 'S0') -and (@($res19.epochs_visited) -notcontains 'M1')) 'S19 never escalated past M0'
Ok (Test-Path -LiteralPath $s19f) 'S19 the tool actually ran (file written) at M0'

# --- S20: the contract-less default fast-path is behaviorally equal to an -AutoRamp:$false (strict floor) run ---
# (the two loops emit structurally different envelopes by design -- controller governor-trace vs floor steps --
#  so equality is asserted on the substantive OUTCOME: both complete, same tool succeeded, 0 escalation / same cost.)
$rFloor = Run-Agent 'FINISH_AFTER_ONE: make a file' $null
$resFloor = if ($null -ne $rFloor.env) { $rFloor.env.result } else { $null }
Write-Output "S20 default(controller) == opt-out(floor) for a simple goal (behavioral equality):"
Ok ($null -ne $rFloor.env -and $rFloor.env.skill_id -eq 'agent.local') 'S20 opt-out (-AutoRamp:$false) is the STRICT FLOOR (skill_id agent.local)'
Ok ($null -ne $resFloor -and $resFloor.status -eq 'completed') 'S20 opt-out completes'
Ok ($null -ne $resFloor -and (@($resFloor.outcome.succeeded_tools) -contains 'doc.io')) 'S20 opt-out succeeded doc.io'
Ok ($null -ne $res19 -and $res19.final_status -eq 'completed' -and [int]$res19.model_swaps -eq 0 -and (@($res19.completed_tools) -contains 'doc.io')) 'S20 default(controller) completed the same tool at M0 with 0 escalation (same cost)'

# --- S21: opt-out variants (-NoAutoRamp, InputsJson autoramp:false) both route to the strict floor ---
Write-Output "S21 opt-out variants -> strict floor:"
$s21a = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AgentPath -Goal 'FINISH_AFTER_ONE: make a file' -WorkingDir $work -EscalatorPath $MockPath -GatewayPath $MockPath -ToolsPath $toolsPath -PwshPath $PwshExe -ArtifactRoot $artRoot -NoAutoRamp 2> (Join-Path $work 'err-s21a.txt')
$e21a = $null; try { $e21a = ($s21a | Out-String).Trim() | ConvertFrom-Json } catch { }
Ok ($null -ne $e21a -and $e21a.skill_id -eq 'agent.local' -and $e21a.result.status -eq 'completed') 'S21 -NoAutoRamp -> strict floor (skill_id agent.local, completed)'
$ij21 = [ordered]@{ goal='FINISH_AFTER_ONE: make a file'; working_dir=$work; escalator_path=$MockPath; gateway_path=$MockPath; tools_path=$toolsPath; pwsh_path=$PwshExe; autoramp=$false } | ConvertTo-Json -Compress
$s21b = & $PwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AgentPath -InputsJson $ij21 -PwshPath $PwshExe -ArtifactRoot $artRoot 2> (Join-Path $work 'err-s21b.txt')
$e21b = $null; try { $e21b = ($s21b | Out-String).Trim() | ConvertFrom-Json } catch { }
Ok ($null -ne $e21b -and $e21b.skill_id -eq 'agent.local' -and $e21b.result.status -eq 'completed') 'S21 InputsJson autoramp:false -> strict floor'
Ok ($null -ne $e21b -and $null -ne $e21b.result -and $null -ne $e21b.result.terminator) 'S21 floor envelope shape (result.terminator present, not the controller governor trace)'

# cleanup
try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Output ""
Write-Output ("==== RESULT pass=$pass fail=$fail ====")
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
