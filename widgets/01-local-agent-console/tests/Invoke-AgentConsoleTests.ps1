<#
    Invoke-AgentConsoleTests.ps1 - dual-mode test harness for the Local Agent Console.

    Cloud pre-ship gate (Linux, no -Live): AST-parse every script; drive the REAL core
    (AgentConsole.psm1) against tests/mock-agent-local.ps1 across a scenario matrix; assert
    Format-AgentTranscript renders every section. The WinForms + real-agent tests are
    Windows-only and skipped off-Windows.

    Live (Windows, via the executor, -Live): the same tests plus the WinForms form builds
    (Show-AgentConsole.ps1 -SelfTest in an STA child), launch.bat shape, and a REAL
    agent.local dry-run driven end-to-end, parsed, and rendered, with no orphaned llama-server.
#>
[CmdletBinding()]
param(
    [switch]$Live,
    [string]$PwshPath,
    [string]$AgentLocalPath,
    [string]$RouteToolsPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$widgetRoot = Split-Path $here -Parent
Import-Module (Join-Path $widgetRoot 'AgentConsole.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}
$mockPath = Join-Path $here 'mock-agent-local.ps1'
$mockRoutePath = Join-Path $here 'mock-route-tools.ps1'

$script:pass = 0; $script:fail = 0; $script:skip = 0
function Ok([string]$name, $cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name   $detail" }
}
function Skip([string]$name, [string]$why) { $script:skip++; Write-Host "  [SKIP] $name ($why)" }

Write-Host "=== Local Agent Console tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist
foreach ($fn in 'Resolve-AgentConsolePaths', 'Start-AgentLocalProcess', 'Complete-AgentLocalRun', 'Invoke-AgentLocalRun', 'Format-AgentTranscript', 'ConvertFrom-EnvelopeJson', 'Stop-AgentLocalProcess', 'Start-RouteToolsProcess', 'Complete-RouteToolsRun', 'Invoke-RouteToolsRun', 'Format-RoutePlan') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'AgentConsole.psm1'),
    (Join-Path $widgetRoot 'Show-AgentConsole.ps1'),
    $mockPath,
    $mockRoutePath,
    (Join-Path $here 'Invoke-AgentConsoleTests.ps1')
)
foreach ($f in $toParse) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Ok "AST parse: $(Split-Path $f -Leaf)" ($errs.Count -eq 0) ("errors=" + ($errs -join '; '))
}

# 3. path resolution
$paths = Resolve-AgentConsolePaths
Ok "resolve: agent.local path" ($paths.AgentLocalPath -like '*21-agent-local*Invoke-AgentLocal.ps1')
Ok "resolve: route.tools path" ($paths.RouteToolsPath -like '*27-route-tools*Invoke-RouteTools.ps1')
Ok "resolve: repo root exists" (Test-Path $paths.RepoRoot)

# 4. completed run via the mock
$run = Invoke-AgentLocalRun -Goal 'list the files' -AgentLocalPath $mockPath -PwshPath $PwshPath -DryRun:$false -MaxSteps 4
Ok "mock completed: ok" ($run.ok) ("status=$($run.status) exit=$($run.exit_code) parse=$($run.parse_error)")
Ok "mock completed: skill_id agent.local" ((Get-Prop $run.envelope 'skill_id') -eq 'agent.local')
Ok "mock completed: final_answer present" (-not [string]::IsNullOrWhiteSpace([string](Get-Prop $run.result 'final_answer')))
$steps = @(Get-Prop $run.result 'steps')
Ok "mock completed: has >=1 step" ($steps.Count -ge 1)
Ok "mock completed: tool invoked (not dry)" ((Get-Prop (Get-Prop $steps[0] 'tool') 'invoked') -eq $true)

# 5. dry-run
$dry = Invoke-AgentLocalRun -Goal 'list the files' -AgentLocalPath $mockPath -PwshPath $PwshPath -DryRun -MaxSteps 2
Ok "mock dry-run: dry_run true" ((Get-Prop $dry.result 'dry_run') -eq $true)
$dsteps = @(Get-Prop $dry.result 'steps')
Ok "mock dry-run: tool not invoked" ((Get-Prop (Get-Prop $dsteps[0] 'tool') 'invoked') -eq $false)

# 6. stopped + needs_frontier
$stop = Invoke-AgentLocalRun -Goal 'do a thing STOPME' -AgentLocalPath $mockPath -PwshPath $PwshPath -DryRun:$false
Ok "mock stopped: agent status stopped" ((Get-Prop $stop.result 'status') -eq 'stopped')
Ok "mock stopped: needs_frontier true" ((Get-Prop $stop.result 'needs_frontier') -eq $true)

# 7. error envelope
$err = Invoke-AgentLocalRun -Goal 'break it ERRORME' -AgentLocalPath $mockPath -PwshPath $PwshPath
Ok "mock error: not ok" (-not $err.ok)
Ok "mock error: error surfaced" ($null -ne $err.error -and [bool](Get-Prop $err.error 'code'))

# 8. noisy stdout still parses
$noisy = Invoke-AgentLocalRun -Goal 'NOISY list files' -AgentLocalPath $mockPath -PwshPath $PwshPath -DryRun:$false
Ok "mock noisy: still parsed envelope" ($null -ne $noisy.envelope -and (Get-Prop $noisy.envelope 'skill_id') -eq 'agent.local')

# 9. transcript sections (completed)
$t = Format-AgentTranscript -Run $run
foreach ($needle in 'GOAL:', 'FINAL ANSWER', 'TRANSCRIPT', '[Step 1]', 'doc.io', 'COST') {
    Ok "transcript contains '$needle'" ($t -match [regex]::Escape($needle))
}

# 10. transcript on error run
$te = Format-AgentTranscript -Run $err
Ok "error transcript surfaces error" ($te -match 'ERROR' -or $te -match 'No valid result envelope')

# 11. transcript robust on a sparse envelope
$sparse = [pscustomobject]@{
    ok = $true; status = 'ok'; exit_code = 0; elapsed_ms = 1; goal = 'x'; parse_error = $null; stderr_tail = ''
    envelope = [pscustomobject]@{ schema = 'lifeorch.skill.result/0.1'; status = 'ok'; result = [pscustomobject]@{ goal = 'x' } }
    result = [pscustomobject]@{ goal = 'x' }
}
$threw = $false; $ts = ''
try { $ts = Format-AgentTranscript -Run $sparse } catch { $threw = $true }
Ok "transcript robust on sparse envelope" ((-not $threw) -and $ts.Length -gt 0)

# 12. tolerant JSON extraction
$e2 = ConvertFrom-EnvelopeJson -Text ("banner line`n{`"a`":1,`"b`":{`"c`":2}}`ntrailing junk")
Ok "envelope-json extracts from noise" ($null -ne $e2 -and $e2.a -eq 1 -and $e2.b.c -eq 2)

# 12b. Plan path (route.tools) via the mock
$plan = Invoke-RouteToolsRun -Goal 'make an image of a dog' -RouteToolsPath $mockRoutePath -PwshPath $PwshPath
Ok "plan: ok" ($plan.ok) ("status=$($plan.status) exit=$($plan.exit_code) parse=$($plan.parse_error)")
Ok "plan: skill_id route.tools" ((Get-Prop $plan.envelope 'skill_id') -eq 'route.tools')
$ptools = @(Get-Prop $plan.result 'tools')
Ok "plan: selected gen.image" ($ptools.Count -eq 1 -and $ptools[0] -eq 'gen.image')
$pf = Format-RoutePlan -Run $plan
foreach ($needle in 'PLAN for goal', 'SELECTED TOOLS', 'gen.image', 'CATALOG') {
    Ok "plan transcript contains '$needle'" ($pf -match [regex]::Escape($needle))
}
$planNone = Invoke-RouteToolsRun -Goal 'NONE tell me a joke' -RouteToolsPath $mockRoutePath -PwshPath $PwshPath
Ok "plan: empty selection renders" ((Format-RoutePlan -Run $planNone) -match 'none')

# 12c. Run with -Route: transcript surfaces planned_tools + what ran
$routed = Invoke-AgentLocalRun -Goal 'make a file' -AgentLocalPath $mockPath -PwshPath $PwshPath -Route -DryRun:$false
Ok "routed run: route_enabled" ((Get-Prop $routed.result 'route_enabled') -eq $true)
Ok "routed run: planned_tools present" (@(Get-Prop $routed.result 'planned_tools') -contains 'doc.io')
$rtt = Format-AgentTranscript -Run $routed
Ok "routed transcript shows ROUTED" ($rtt -match 'ROUTED')
Ok "routed transcript shows TOOLS RAN" ($rtt -match 'TOOLS RAN')

# 13. launch.bat shape
$launch = Join-Path $widgetRoot 'launch.bat'
$lc = if (Test-Path $launch) { Get-Content $launch -Raw } else { '' }
Ok "launch.bat exists" (Test-Path $launch)
Ok "launch.bat uses -STA" ($lc -match '-STA')
Ok "launch.bat runs Show-AgentConsole.ps1" ($lc -match 'Show-AgentConsole\.ps1')

# ----- live / Windows-only -----
if ($Live -and $IsWindows) {
    $sta = & $PwshPath -NoProfile -STA -File (Join-Path $widgetRoot 'Show-AgentConsole.ps1') -SelfTest 2>&1
    Ok "WinForms form builds (SelfTest)" (($sta -join "`n") -match 'SELFTEST_FORM_OK') (($sta -join ' | '))

    $realRoute = if ($RouteToolsPath) { $RouteToolsPath } else { $paths.RouteToolsPath }
    $rplan = Invoke-RouteToolsRun -Goal 'make an image of a dog' -RouteToolsPath $realRoute -PwshPath $PwshPath
    Ok "real route.tools: envelope skill_id" ((Get-Prop $rplan.envelope 'skill_id') -eq 'route.tools') ("status=$($rplan.status) exit=$($rplan.exit_code)")
    Ok "real route.tools: renders a plan" ((Format-RoutePlan -Run $rplan).Length -gt 0)

    $realAgent = if ($AgentLocalPath) { $AgentLocalPath } else { $paths.AgentLocalPath }
    $before = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
    $real = Invoke-AgentLocalRun -Goal 'list the markdown files in the core-docs folder' -AgentLocalPath $realAgent -PwshPath $PwshPath -DryRun -MaxSteps 1 -DecisionTiers @('tiny') -GenTier 'tiny' -WorkingDir $paths.RepoRoot
    Ok "real agent.local: envelope skill_id" ((Get-Prop $real.envelope 'skill_id') -eq 'agent.local') ("status=$($real.status) exit=$($real.exit_code) parse=$($real.parse_error)")
    Ok "real agent.local: renders a transcript" ((Format-AgentTranscript -Run $real).Length -gt 0)
    Start-Sleep -Seconds 2
    $after = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
    Ok "real agent.local: no orphaned llama-server" ($after -le $before) ("before=$before after=$after")
}
else {
    Skip "WinForms form self-test" "requires -Live on Windows"
    Skip "real agent.local dry-run" "requires -Live on Windows"
    Skip "no-orphan check" "requires -Live on Windows"
}

Write-Host ""
Write-Host "=== RESULT: $script:pass passed, $script:fail failed, $script:skip skipped ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
