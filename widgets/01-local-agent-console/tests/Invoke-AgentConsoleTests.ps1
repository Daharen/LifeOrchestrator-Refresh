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
    [switch]$NoGpu,   # CPU-only live gate: run the WinForms SelfTest + the mock-driven console path, but SKIP the
    # real route.tools / real agent.local dry-run (both load a local model = GPU). Use when a
    # concurrent GPU worker holds the gpu lease; the real-model live pass is the orchestrator's item.
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

# 12d. Build-AgentLocalInputs: byte-identical when auto-ramp OFF; autoramp + contract only when ON
Ok "function exists: Build-AgentLocalInputs" ([bool](Get-Command Build-AgentLocalInputs -ErrorAction SilentlyContinue))
Ok "function exists: Format-GovernorTrace" ([bool](Get-Command Format-GovernorTrace -ErrorAction SilentlyContinue))

$offA = Build-AgentLocalInputs -Goal 'make a file' -MaxSteps 10 -DryRun:$false -Route -WorkingDir 'C:\repo' -GenTier 'mid'
$offB = Build-AgentLocalInputs -Goal 'make a file' -MaxSteps 10 -DryRun:$false -Route -WorkingDir 'C:\repo' -GenTier 'mid' -AutoRamp:$false -SuccessContractPath 'C:\ignored.json'
Ok "inputs OFF: no autoramp key" (-not ($offA -match 'autoramp'))
Ok "inputs OFF: no success_contract key" (-not ($offA -match 'success_contract'))
Ok "inputs OFF: identical whether or not a contract arg is passed" ($offA -eq $offB)
# the exact payload the console shipped BEFORE this option existed -- must match byte-for-byte
$today = ([ordered]@{ goal = 'make a file'; max_steps = 10; dry_run = $false; route = $true; working_dir = 'C:\repo'; gen_tier = 'mid' } | ConvertTo-Json -Compress -Depth 6)
Ok "inputs OFF: byte-identical to the pre-AutoRamp payload" ($offA -eq $today) ("got=$offA")

$onNoC = Build-AgentLocalInputs -Goal 'make a file' -MaxSteps 10 -Route -AutoRamp
Ok "inputs ON: autoramp:true present" ($onNoC -match '"autoramp":true')
Ok "inputs ON (no contract): no success_contract key" (-not ($onNoC -match 'success_contract'))

$onC = Build-AgentLocalInputs -Goal 'make a file' -MaxSteps 10 -DryRun:$false -Route -WorkingDir 'C:\repo' -GenTier 'mid' -AutoRamp -SuccessContractPath 'C:\c\contract.json'
Ok "inputs ON: success_contract_path present" ($onC -match 'success_contract_path')
Ok "inputs ON: autoramp appended AFTER the base keys" ($onC.IndexOf('gen_tier') -lt $onC.IndexOf('autoramp') -and $onC.IndexOf('autoramp') -lt $onC.IndexOf('success_contract_path'))

# 12e. AutoRamp run through the mock: envelope carries a governor trace; the transcript renders it
$ar = Invoke-AgentLocalRun -Goal 'RAMP create ramp_done.txt' -AgentLocalPath $mockPath -PwshPath $PwshPath -AutoRamp -MaxSteps 10
Ok "autoramp: envelope parsed" ($null -ne $ar.envelope -and (Get-Prop $ar.envelope 'skill_id') -eq 'agent.local') ("status=$($ar.status) exit=$($ar.exit_code) parse=$($ar.parse_error)")
$arRes = $ar.result
Ok "autoramp: result.autoramp true (passed through)" ((Get-Prop $arRes 'autoramp') -eq $true)
$gt = @(Get-Prop $arRes 'governor_trace')
Ok "autoramp: governor_trace has 3 steps (M0->M1->S0)" ($gt.Count -eq 3)
Ok "autoramp: final_status local_ceiling_reached" ((Get-Prop $arRes 'final_status') -eq 'local_ceiling_reached')
$art = Format-AgentTranscript -Run $ar
foreach ($needle in 'AUTO-RAMP', 'GOVERNOR TRACE', 'epoch M0', 'epoch S0', 'escalated_to', 'contract', 'residency', 'model_swaps') {
    Ok "autoramp transcript contains '$needle'" ($art -match [regex]::Escape($needle))
}

# 12f. AutoRamp with a real contract FILE: the console resolves + passes the path through
$tmpContract = Join-Path ([IO.Path]::GetTempPath()) ("console-contract-" + [guid]::NewGuid().ToString('N') + ".json")
'{"schema":"lifeorch.goal_verification/0.1","predicates":[{"predicate":"file_exists","path":"ramp_ok.txt"}]}' | Set-Content -LiteralPath $tmpContract -Encoding utf8
try {
    $arv = Invoke-AgentLocalRun -Goal 'VERIFIED write ramp_ok.txt' -AgentLocalPath $mockPath -PwshPath $PwshPath -AutoRamp -SuccessContractPath $tmpContract -MaxSteps 8
    $arvRes = $arv.result
    Ok "autoramp contract: verified_success" ((Get-Prop $arvRes 'final_status') -eq 'verified_success')
    Ok "autoramp contract: contract.supplied true" ((Get-Prop (Get-Prop $arvRes 'contract') 'supplied') -eq $true)
    Ok "autoramp contract: mock received the resolved contract path" ((Get-Prop $arvRes 'success_contract_path') -eq (Resolve-Path -LiteralPath $tmpContract).Path)
    Ok "autoramp contract transcript shows verified_success" ((Format-AgentTranscript -Run $arv) -match 'verified_success')
}
finally { Remove-Item -LiteralPath $tmpContract -ErrorAction SilentlyContinue }

# 12g. missing contract file -> friendly error at spawn (surfaced to the UI, no silent pass-through)
$threwC = $false; $msgC = ''
try { [void](Start-AgentLocalProcess -Goal 'x' -AgentLocalPath $mockPath -PwshPath $PwshPath -AutoRamp -SuccessContractPath (Join-Path ([IO.Path]::GetTempPath()) 'definitely-not-here-xyz.json')) }
catch { $threwC = $true; $msgC = $_.Exception.Message }
Ok "autoramp: missing contract file throws a clear error" ($threwC -and $msgC -match 'success contract file not found') ("msg=$msgC")

# 12h. the STA shell surfaces the auto-ramp controls + passes them through (thin-shell contract)
$showSrc = Get-Content (Join-Path $widgetRoot 'Show-AgentConsole.ps1') -Raw
Ok "UI: Show-AgentConsole has an Auto-ramp control" ($showSrc -match 'Auto-ramp')
Ok "UI: Show-AgentConsole passes -AutoRamp through" ($showSrc -match '-AutoRamp:')
Ok "UI: Show-AgentConsole surfaces a success-contract field" (($showSrc -match 'contractBox') -and ($showSrc -match 'SuccessContractPath'))

# 13. launch.bat shape
$launch = Join-Path $widgetRoot 'launch.bat'
$lc = if (Test-Path $launch) { Get-Content $launch -Raw } else { '' }
Ok "launch.bat exists" (Test-Path $launch)
Ok "launch.bat uses -STA" ($lc -match '-STA')
Ok "launch.bat runs Show-AgentConsole.ps1" ($lc -match 'Show-AgentConsole\.ps1')

# ----- live / Windows-only -----
if ($Live -and $IsWindows) {
    # WinForms self-test is CPU-only -- always run it under -Live (proves the UI, incl. the new
    # auto-ramp toggle + contract field, builds on the real Windows box).
    $sta = & $PwshPath -NoProfile -STA -File (Join-Path $widgetRoot 'Show-AgentConsole.ps1') -SelfTest 2>&1
    Ok "WinForms form builds (SelfTest)" (($sta -join "`n") -match 'SELFTEST_FORM_OK') (($sta -join ' | '))

    if ($NoGpu) {
        # CPU-only live gate: drive the REAL console core on Windows against the MOCK agent.local
        # (spawn -> parse -> render, incl. the auto-ramp governor trace) -- no real model, no GPU.
        # The real route.tools / real agent.local dry-run DO load a local model (GPU) and are skipped
        # here to avoid contending with a concurrent GPU worker; they are covered by the orchestrator's live pass.
        $before = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
        $mlDry = Invoke-AgentLocalRun -Goal 'list the files' -AgentLocalPath $mockPath -PwshPath $PwshPath -DryRun -MaxSteps 2
        Ok "cpu-live: mock agent dry-run driven+parsed" ((Get-Prop $mlDry.result 'dry_run') -eq $true) ("status=$($mlDry.status) exit=$($mlDry.exit_code)")
        Ok "cpu-live: transcript renders" ((Format-AgentTranscript -Run $mlDry).Length -gt 0)
        $mlAr = Invoke-AgentLocalRun -Goal 'RAMP create ramp_done.txt' -AgentLocalPath $mockPath -PwshPath $PwshPath -AutoRamp -MaxSteps 6
        Ok "cpu-live: mock auto-ramp renders governor trace" ((Format-AgentTranscript -Run $mlAr) -match 'GOVERNOR TRACE')
        Start-Sleep -Seconds 1
        $after = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
        Ok "cpu-live: no orphaned llama-server (no model launched)" ($after -le $before) ("before=$before after=$after")
        Skip "real route.tools (GPU)" "NoGpu: deferred to the orchestrator live pass (GPU held by a concurrent worker)"
        Skip "real agent.local dry-run (GPU)" "NoGpu: deferred to the orchestrator live pass"
    }
    else {
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
}
else {
    Skip "WinForms form self-test" "requires -Live on Windows"
    Skip "real agent.local dry-run" "requires -Live on Windows"
    Skip "no-orphan check" "requires -Live on Windows"
}

Write-Host ""
Write-Host "=== RESULT: $script:pass passed, $script:fail failed, $script:skip skipped ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
