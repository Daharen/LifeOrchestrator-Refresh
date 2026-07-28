<#
    AgentConsole.psm1 - driver core for the Local Agent Console (Widget 01).

    Holds ALL non-UI logic: resolve paths, spawn agent.local (#21) as a child process,
    parse its lifeorch.skill.result/0.1 envelope, and format a human transcript.
    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate
    (against tests/mock-agent-local.ps1) and on Windows. The UI (Show-AgentConsole.ps1)
    is a thin shell over these functions.

    It reimplements nothing: agent.local is invoked exactly as the executor / orchestrator
    skills invoke child skills, and its envelope is parsed, never re-derived.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AgentConsoleWidgetRoot = $PSScriptRoot

# ---------- small helpers ----------

function Test-HasProp {
    param($Object, [string]$Name)
    return ($null -ne $Object -and $null -ne $Object.PSObject -and $null -ne $Object.PSObject.Properties[$Name])
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if (Test-HasProp $Object $Name) { return $Object.$Name }
    return $Default
}

function Limit-Text {
    param($Text, [int]$Max = 500)
    if ($null -eq $Text) { return '' }
    $s = [string]$Text
    if ($s.Length -le $Max) { return $s }
    return $s.Substring(0, $Max) + ' ...[truncated ' + ($s.Length - $Max) + ' chars]'
}

function ConvertTo-CompactJson {
    param($Value, [int]$Depth = 6)
    if ($null -eq $Value) { return '(none)' }
    try { return ($Value | ConvertTo-Json -Compress -Depth $Depth) }
    catch { return [string]$Value }
}

# Extract the first complete, balanced top-level JSON object from arbitrary text
# (tolerant of any leading/trailing diagnostic noise on stdout).
function ConvertFrom-EnvelopeJson {
    param([string]$Text, [ref]$ErrorRef)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = 'empty stdout' }
        return $null
    }
    try { return ($Text | ConvertFrom-Json -ErrorAction Stop) } catch { }

    $ob = [char]123; $cb = [char]125; $qt = [char]34; $bs = [char]92
    $start = $Text.IndexOf($ob)
    if ($start -lt 0) {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = 'no JSON object found in stdout' }
        return $null
    }
    $depth = 0; $inStr = $false; $esc = $false; $end = -1
    for ($i = $start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($c -eq $bs) { $esc = $true }
            elseif ($c -eq $qt) { $inStr = $false }
        }
        else {
            if ($c -eq $qt) { $inStr = $true }
            elseif ($c -eq $ob) { $depth++ }
            elseif ($c -eq $cb) { $depth--; if ($depth -eq 0) { $end = $i; break } }
        }
    }
    if ($end -lt 0) {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = 'unbalanced JSON object in stdout' }
        return $null
    }
    $fragment = $Text.Substring($start, $end - $start + 1)
    try { return ($fragment | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = "JSON parse failed: $($_.Exception.Message)" }
        return $null
    }
}

# ---------- path resolution ----------

function Resolve-AgentConsolePaths {
    [CmdletBinding()]
    param(
        [string]$AgentLocalPath,
        [string]$RouteToolsPath,
        [string]$PwshPath,
        [string]$WidgetRoot
    )
    if (-not $WidgetRoot) { $WidgetRoot = $script:AgentConsoleWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    $repoRoot = $null
    $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
    if ($rp) { $repoRoot = $rp.Path } else { $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }

    if (-not $AgentLocalPath) {
        $AgentLocalPath = Join-Path $repoRoot (Join-Path 'modules' (Join-Path '21-agent-local' 'Invoke-AgentLocal.ps1'))
    }
    if (-not $RouteToolsPath) {
        $RouteToolsPath = Join-Path $repoRoot (Join-Path 'modules' (Join-Path '27-route-tools' 'Invoke-RouteTools.ps1'))
    }
    if (-not $PwshPath) {
        # Self-referential pwsh path via $PSHOME dodges the dotnet-tool 'dotnet.exe' locator gotcha.
        $cand = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $cand)) { $cand = Join-Path $PSHOME 'pwsh' }  # non-Windows (cloud gate)
        $PwshPath = $cand
    }
    return [pscustomobject]@{
        WidgetRoot     = $WidgetRoot
        RepoRoot       = $repoRoot
        AgentLocalPath = $AgentLocalPath
        RouteToolsPath = $RouteToolsPath
        PwshPath       = $PwshPath
    }
}

# ---------- input payload builder (pure; unit-testable) ----------

function Build-AgentLocalInputs {
    <#
      Build the -InputsJson payload for the agent.local child, in the EXACT key order the console
      has always used. The Governor Phase 3 opt-in (-AutoRamp / -SuccessContractPath) is the ONLY
      addition and is appended LAST and ONLY when the toggle is on -- so with -AutoRamp OFF the
      returned JSON (and therefore the child's argv) is byte-for-byte identical to what the console
      shipped before this option existed. Pure: no filesystem / no process; unit-testable.

      autoramp:true is promoted to the -AutoRamp switch by Invoke-AgentLocal.ps1 (the same mechanism
      the console already uses for -Route via route:true), and success_contract_path is forwarded
      verbatim inside -InputsJson to Invoke-AutoRamp.ps1 (the shipped controller reads it and freezes
      the contract by hash). The widget reimplements none of that.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Goal,
        [int]$MaxSteps = 4,
        [switch]$DryRun,
        [switch]$Route,
        [string]$WorkingDir,
        [string[]]$DecisionTiers,
        [string]$GenTier,
        [switch]$AutoRamp,
        [string]$SuccessContractPath
    )
    $inputs = [ordered]@{ goal = $Goal; max_steps = $MaxSteps; dry_run = [bool]$DryRun }
    if ($Route) { $inputs['route'] = $true }
    if ($WorkingDir) { $inputs['working_dir'] = $WorkingDir }
    if ($DecisionTiers -and $DecisionTiers.Count -gt 0) { $inputs['decision_tiers'] = @($DecisionTiers) }
    if ($GenTier) { $inputs['gen_tier'] = $GenTier }
    # ---- Governor Phase 3 opt-in (caller-side ONLY; appended LAST so the OFF payload is unchanged) ----
    if ($AutoRamp) {
        $inputs['autoramp'] = $true
        if (-not [string]::IsNullOrWhiteSpace($SuccessContractPath)) { $inputs['success_contract_path'] = $SuccessContractPath }
    }
    return ($inputs | ConvertTo-Json -Compress -Depth 6)
}

# ---------- spawn / complete / run ----------

function Start-AgentLocalProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Goal,
        [string]$WorkingDir,
        [int]$MaxSteps = 4,
        [switch]$DryRun,
        [switch]$Route,
        [string[]]$DecisionTiers,
        [string]$GenTier,
        [string]$AgentLocalPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$InvocationId,
        [hashtable]$Sync,
        [string]$WidgetRoot,
        [switch]$AutoRamp,
        [string]$SuccessContractPath
    )
    $paths = Resolve-AgentConsolePaths -AgentLocalPath $AgentLocalPath -PwshPath $PwshPath -WidgetRoot $WidgetRoot
    # Resolve the entrypoint to an ABSOLUTE path: the child runs with WorkingDirectory=RepoRoot,
    # so a relative -File would otherwise resolve against the wrong directory.
    $agentPath = $paths.AgentLocalPath
    if (-not [System.IO.Path]::IsPathRooted($agentPath)) {
        $rp = Resolve-Path -LiteralPath $agentPath -ErrorAction SilentlyContinue
        if ($rp) { $agentPath = $rp.Path }
    }
    if (-not (Test-Path -LiteralPath $agentPath)) {
        throw "agent.local entrypoint not found: $agentPath"
    }
    if (-not $InvocationId) { $InvocationId = [guid]::NewGuid().ToString() }
    if (-not $ArtifactRoot) {
        $ArtifactRoot = Join-Path (Join-Path $paths.WidgetRoot (Join-Path 'runtime' 'artifacts')) $InvocationId
    }
    New-Item -ItemType Directory -Path $ArtifactRoot -Force -ErrorAction SilentlyContinue | Out-Null

    # Governor Phase 3 opt-in: resolve + validate the caller-supplied success-contract file (only when -AutoRamp).
    $contractPathResolved = $null
    if ($AutoRamp -and -not [string]::IsNullOrWhiteSpace($SuccessContractPath)) {
        if (-not (Test-Path -LiteralPath $SuccessContractPath -PathType Leaf)) {
            throw "success contract file not found: $SuccessContractPath"
        }
        $contractPathResolved = (Resolve-Path -LiteralPath $SuccessContractPath).Path
    }
    # Build the child -InputsJson. With -AutoRamp OFF this is byte-for-byte identical to what the console
    # has always sent (autoramp / success_contract_path are appended ONLY when the toggle is on).
    $inputsJson = Build-AgentLocalInputs -Goal $Goal -MaxSteps $MaxSteps -DryRun:$DryRun -Route:$Route `
        -WorkingDir $WorkingDir -DecisionTiers $DecisionTiers -GenTier $GenTier `
        -AutoRamp:$AutoRamp -SuccessContractPath $contractPathResolved

    $stdoutPath = Join-Path $ArtifactRoot 'agent.stdout.txt'
    $stderrPath = Join-Path $ArtifactRoot 'agent.stderr.txt'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $paths.PwshPath
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $agentPath, '-InputsJson', $inputsJson, '-ArtifactRoot', $ArtifactRoot)) {
        [void]$psi.ArgumentList.Add($a)   # per-arg escaping; safe with spaces/quotes in the JSON
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if (Test-Path -LiteralPath $paths.RepoRoot) { $psi.WorkingDirectory = $paths.RepoRoot }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    # Drain BOTH pipes concurrently (avoids the fill-deadlock gotcha) via async whole-stream reads.
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $startedUtc = [datetime]::UtcNow
    if ($Sync) {
        $Sync['child_pid'] = $proc.Id
        $Sync['stdout_path'] = $stdoutPath
        $Sync['stderr_path'] = $stderrPath
        $Sync['started_utc'] = $startedUtc
    }
    return [pscustomobject]@{
        Process      = $proc
        StdoutTask   = $outTask
        StderrTask   = $errTask
        StdoutPath   = $stdoutPath
        StderrPath   = $stderrPath
        ArtifactRoot = $ArtifactRoot
        InvocationId = $InvocationId
        InputsJson   = $inputsJson
        Args         = $psi.ArgumentList
        Paths        = $paths
        StartedUtc   = $startedUtc
        Goal         = $Goal
        AutoRamp     = [bool]$AutoRamp
        SuccessContractPath = $contractPathResolved
    }
}

function Stop-AgentLocalProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) { $Handle.Process.Kill($true) }  # kill the whole tree
    } catch { }
}

function Complete-AgentLocalRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)

    $proc = $Handle.Process
    try { $proc.WaitForExit() } catch { }

    $stdout = ''
    $stderr = ''
    try { $stdout = $Handle.StdoutTask.GetAwaiter().GetResult() } catch { }
    try { $stderr = $Handle.StderrTask.GetAwaiter().GetResult() } catch { }
    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try { [System.IO.File]::WriteAllText($Handle.StdoutPath, $stdout, $utf8) } catch { }
    try { [System.IO.File]::WriteAllText($Handle.StderrPath, $stderr, $utf8) } catch { }

    $exit = $null
    try { $exit = $proc.ExitCode } catch { }

    $parseError = $null
    $envelope = ConvertFrom-EnvelopeJson -Text $stdout -ErrorRef ([ref]$parseError)
    $result = if ($envelope) { Get-Prop $envelope 'result' } else { $null }
    $status = if ($envelope) { [string](Get-Prop $envelope 'status' 'unknown') } else { 'error' }

    $stderrTail = if ($stderr.Length -gt 1200) { $stderr.Substring($stderr.Length - 1200) } else { $stderr }

    $ok = ($exit -eq 0 -and $null -ne $envelope -and ($status -eq 'ok' -or $status -eq 'partial'))

    $error = $null
    if (-not $ok) {
        if ($envelope -and (Get-Prop $envelope 'error')) {
            $e = Get-Prop $envelope 'error'
            $error = [pscustomobject]@{ code = [string](Get-Prop $e 'code' 'error'); message = [string](Get-Prop $e 'message' '') }
        }
        elseif ($null -eq $envelope) {
            $error = [pscustomobject]@{ code = 'no_envelope'; message = ("agent.local produced no valid result envelope (exit=$exit). " + [string]$parseError) }
        }
        else {
            $error = [pscustomobject]@{ code = 'not_ok'; message = "agent.local returned status '$status' (exit=$exit)." }
        }
    }

    $elapsedMs = [int]([datetime]::UtcNow - $Handle.StartedUtc).TotalMilliseconds

    return [pscustomobject]@{
        ok           = $ok
        status       = $status
        envelope     = $envelope
        result       = $result
        exit_code    = $exit
        stderr_tail  = $stderrTail
        raw_stdout   = $stdout
        parse_error  = $parseError
        error        = $error
        elapsed_ms   = $elapsedMs
        goal         = $Handle.Goal
        artifact_root = $Handle.ArtifactRoot
    }
}

function Invoke-AgentLocalRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Goal,
        [string]$WorkingDir,
        [int]$MaxSteps = 4,
        [switch]$DryRun,
        [switch]$Route,
        [string[]]$DecisionTiers,
        [string]$GenTier,
        [string]$AgentLocalPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$WidgetRoot,
        [switch]$AutoRamp,
        [string]$SuccessContractPath
    )
    $h = Start-AgentLocalProcess -Goal $Goal -WorkingDir $WorkingDir -MaxSteps $MaxSteps -DryRun:$DryRun -Route:$Route `
        -DecisionTiers $DecisionTiers -GenTier $GenTier -AgentLocalPath $AgentLocalPath -PwshPath $PwshPath `
        -ArtifactRoot $ArtifactRoot -WidgetRoot $WidgetRoot -AutoRamp:$AutoRamp -SuccessContractPath $SuccessContractPath
    try { $h.Process.WaitForExit() } catch { }
    return Complete-AgentLocalRun -Handle $h
}

# ---------- route.tools (Plan path): spawn / complete / run ----------

function Start-RouteToolsProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Goal,
        [string]$RouteTier = 'mid',
        [string]$RouteToolsPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$InvocationId,
        [hashtable]$Sync,
        [string]$WidgetRoot
    )
    $paths = Resolve-AgentConsolePaths -RouteToolsPath $RouteToolsPath -PwshPath $PwshPath -WidgetRoot $WidgetRoot
    $routePath = $paths.RouteToolsPath
    if (-not [System.IO.Path]::IsPathRooted($routePath)) {
        $rp = Resolve-Path -LiteralPath $routePath -ErrorAction SilentlyContinue
        if ($rp) { $routePath = $rp.Path }
    }
    if (-not (Test-Path -LiteralPath $routePath)) { throw "route.tools entrypoint not found: $routePath" }
    if (-not $InvocationId) { $InvocationId = [guid]::NewGuid().ToString() }
    if (-not $ArtifactRoot) {
        $ArtifactRoot = Join-Path (Join-Path $paths.WidgetRoot (Join-Path 'runtime' 'artifacts')) $InvocationId
    }
    New-Item -ItemType Directory -Path $ArtifactRoot -Force -ErrorAction SilentlyContinue | Out-Null

    $inputs = [ordered]@{ request = $Goal; tier = $RouteTier }
    $inputsJson = ($inputs | ConvertTo-Json -Compress -Depth 6)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $paths.PwshPath
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $routePath, '-InputsJson', $inputsJson, '-ArtifactRoot', $ArtifactRoot)) {
        [void]$psi.ArgumentList.Add($a)
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if (Test-Path -LiteralPath $paths.RepoRoot) { $psi.WorkingDirectory = $paths.RepoRoot }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $startedUtc = [datetime]::UtcNow
    if ($Sync) { $Sync['child_pid'] = $proc.Id; $Sync['started_utc'] = $startedUtc }
    return [pscustomobject]@{
        Process      = $proc
        StdoutTask   = $outTask
        StderrTask   = $errTask
        ArtifactRoot = $ArtifactRoot
        InvocationId = $InvocationId
        InputsJson   = $inputsJson
        Paths        = $paths
        StartedUtc   = $startedUtc
        Goal         = $Goal
        Kind         = 'route'
    }
}

function Complete-RouteToolsRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)
    $proc = $Handle.Process
    try { $proc.WaitForExit() } catch { }
    $stdout = ''; $stderr = ''
    try { $stdout = $Handle.StdoutTask.GetAwaiter().GetResult() } catch { }
    try { $stderr = $Handle.StderrTask.GetAwaiter().GetResult() } catch { }
    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }
    $exit = $null; try { $exit = $proc.ExitCode } catch { }
    $parseError = $null
    $envelope = ConvertFrom-EnvelopeJson -Text $stdout -ErrorRef ([ref]$parseError)
    $result = if ($envelope) { Get-Prop $envelope 'result' } else { $null }
    $status = if ($envelope) { [string](Get-Prop $envelope 'status' 'unknown') } else { 'error' }
    $stderrTail = if ($stderr.Length -gt 1200) { $stderr.Substring($stderr.Length - 1200) } else { $stderr }
    $ok = ($exit -eq 0 -and $null -ne $envelope -and ($status -eq 'ok' -or $status -eq 'partial'))
    $error = $null
    if (-not $ok) {
        if ($envelope -and (Get-Prop $envelope 'error')) {
            $e = Get-Prop $envelope 'error'
            $error = [pscustomobject]@{ code = [string](Get-Prop $e 'code' 'error'); message = [string](Get-Prop $e 'message' '') }
        }
        elseif ($null -eq $envelope) { $error = [pscustomobject]@{ code = 'no_envelope'; message = ("route.tools produced no valid result envelope (exit=$exit). " + [string]$parseError) } }
        else { $error = [pscustomobject]@{ code = 'not_ok'; message = "route.tools returned status '$status' (exit=$exit)." } }
    }
    $elapsedMs = [int]([datetime]::UtcNow - $Handle.StartedUtc).TotalMilliseconds
    return [pscustomobject]@{
        ok = $ok; status = $status; envelope = $envelope; result = $result; exit_code = $exit
        stderr_tail = $stderrTail; raw_stdout = $stdout; parse_error = $parseError; error = $error
        elapsed_ms = $elapsedMs; goal = $Handle.Goal; artifact_root = $Handle.ArtifactRoot; kind = 'route'
    }
}

function Invoke-RouteToolsRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Goal,
        [string]$RouteTier = 'mid',
        [string]$RouteToolsPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$WidgetRoot
    )
    $h = Start-RouteToolsProcess -Goal $Goal -RouteTier $RouteTier -RouteToolsPath $RouteToolsPath -PwshPath $PwshPath -ArtifactRoot $ArtifactRoot -WidgetRoot $WidgetRoot
    try { $h.Process.WaitForExit() } catch { }
    return Complete-RouteToolsRun -Handle $h
}

function Format-RoutePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)
    $sb = [System.Text.StringBuilder]::new()
    function _addp([string]$line = '') { [void]$sb.AppendLine($line) }

    if ($null -eq (Get-Prop $Run 'envelope')) {
        _addp 'No valid selection envelope was returned by route.tools.'
        _addp ''
        _addp ("exit code : " + [string](Get-Prop $Run 'exit_code'))
        _addp ("parse note: " + [string](Get-Prop $Run 'parse_error'))
        $tail = [string](Get-Prop $Run 'stderr_tail')
        if ($tail) { _addp ''; _addp 'stderr (tail):'; _addp (Limit-Text $tail 1000) }
        return $sb.ToString()
    }
    $envObj = $Run.envelope
    $res = Get-Prop $Run 'result'
    _addp ('PLAN for goal: ' + [string](Get-Prop $res 'request' (Get-Prop $Run 'goal')))
    _addp ('ROUTER: ' + [string](Get-Prop $res 'tier' 'mid') + ' (' + [string](Get-Prop $res 'model' 'n/a') + ')' +
           '   confidence: ' + $(if ($null -eq (Get-Prop $envObj 'confidence')) { 'n/a' } else { [string](Get-Prop $envObj 'confidence') }) +
           '   ' + [string](Get-Prop $Run 'elapsed_ms') + ' ms')
    _addp ''
    $tools = @(Get-Prop $res 'tools')
    _addp ('SELECTED TOOLS (' + $tools.Count + '):')
    if ($tools.Count -eq 0) { _addp '  (none -- no catalog tool fits this request)' }
    else { foreach ($t in $tools) { _addp ('  - ' + [string]$t) } }
    $dropped = @(Get-Prop $res 'tools_dropped')
    if ($dropped.Count -gt 0) { _addp ''; _addp ('GATED OUT (unknown ids): ' + ($dropped -join ', ')) }
    _addp ''
    _addp '--- CATALOG considered ---'
    foreach ($c in @(Get-Prop $res 'catalog')) { _addp ('  ' + [string](Get-Prop $c 'tool') + ': ' + (Limit-Text ([string](Get-Prop $c 'purpose')) 120)) }
    _addp ''
    _addp 'Press Run to plan AND execute (the agent routes, then runs constrained to these tools).'
    $topErr = Get-Prop $envObj 'error'
    if ($topErr) { _addp ''; _addp ('ERROR: ' + [string](Get-Prop $topErr 'code' 'error') + ': ' + [string](Get-Prop $topErr 'message' '')) }
    return $sb.ToString()
}

# ---------- render ----------

function Format-GovernorTrace {
    <#
      Render the auto-ramp (Governor Phase 3) governor trace carried by an agent.local -AutoRamp
      result envelope (result.governor_trace + the auto-ramp summary fields). Read-only + tolerant:
      every field is looked up defensively so a partial trace still renders. Lines mirror the existing
      transcript style (newline-delimited, long fields truncated via Limit-Text) so they read the same
      in the word-wrapped Console panels.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result)
    $sb = [System.Text.StringBuilder]::new()
    function _addg([string]$line = '') { [void]$sb.AppendLine($line) }

    $trace = @(Get-Prop $Result 'governor_trace')
    $verified = Get-Prop $Result 'verified_success'
    $acceptedEpoch = Get-Prop $Result 'accepted_epoch'
    $epochs = @(Get-Prop $Result 'epochs_visited')

    _addg '--- GOVERNOR TRACE (auto-ramp / Governor Phase 3) ---'
    _addg ('  final_status: ' + [string](Get-Prop $Result 'final_status' 'n/a') +
           '   verified: ' + $(if ($null -eq $verified) { 'n/a' } else { [string]$verified }) +
           '   accepted_epoch: ' + $(if ($null -eq $acceptedEpoch) { 'none' } else { [string]$acceptedEpoch }) +
           '   model_swaps: ' + [string](Get-Prop $Result 'model_swaps' 0))
    if ($epochs.Count -gt 0) { _addg ('  epochs_visited: [' + ($epochs -join ' -> ') + ']') }

    $contract = Get-Prop $Result 'contract'
    if ($contract) {
        $last = Get-Prop $contract 'last'
        $passed = if ($last) { Get-Prop $last 'passed' } else { $null }
        $hash = [string](Get-Prop $contract 'hash' '')
        $hashShort = if ($hash.Length -gt 26) { $hash.Substring(0, 26) + '...' } else { $hash }
        _addg ('  contract: supplied=' + [string](Get-Prop $contract 'supplied' $false) +
               '  checkable=' + [string](Get-Prop $contract 'checkable' $false) +
               '  last_passed=' + $(if ($null -eq $passed) { 'n/a' } else { [string]$passed }) +
               $(if ($hashShort) { '  ' + $hashShort } else { '' }))
    }

    if ($trace.Count -eq 0) { _addg '  (no governor steps recorded)'; return $sb.ToString() }

    foreach ($gs in $trace) {
        _addg ''
        $line = '  [gov step ' + [string](Get-Prop $gs 'step' '?') +
                '] epoch ' + [string](Get-Prop $gs 'epoch' '?') +
                '  model ' + [string](Get-Prop $gs 'model' '?') +
                '  decide -> ' + [string](Get-Prop $gs 'decision' '?')
        $meta = @()
        $dc = Get-Prop $gs 'decision_conf'
        if ($null -ne $dc) { $meta += ('conf ' + [string]$dc) }
        $inset = Get-Prop $gs 'decision_in_set'
        if ($null -ne $inset) { $meta += ('in_set=' + [string]$inset) }
        $fr = Get-Prop $gs 'decision_finish_reason'
        if ($fr) { $meta += ('finish=' + [string]$fr) }
        if (Get-Prop $gs 'decision_empty' $false) { $meta += 'EMPTY' }
        if ($meta.Count -gt 0) { $line += '  (' + ($meta -join ', ') + ')' }
        _addg $line

        if (Get-Prop $gs 'tool_invoked' $false) {
            _addg ('           tool: invoked  status=' + [string](Get-Prop $gs 'tool_status' '?') +
                   $(if (Get-Prop $gs 'skipped_repeat' $false) { '  (skipped_repeat)' } else { '' }))
        }
        elseif (Get-Prop $gs 'skipped_repeat' $false) {
            _addg '           tool: skipped_repeat (duplicate side-effect guard)'
        }

        if (Get-Prop $gs 'contract_evaluated' $false) {
            $cp = Get-Prop $gs 'contract_passed'
            $cf = @(Get-Prop $gs 'contract_failed')
            $cl = '           contract: evaluated  passed=' + $(if ($null -eq $cp) { 'n/a' } else { [string]$cp })
            if ($cf.Count -gt 0) { $cl += '  failed=[' + (Limit-Text (($cf -join ', ')) 300) + ']' }
            _addg $cl
        }

        if (((Get-Prop $gs 'residency_match' $true) -eq $false) -or (Get-Prop $gs 'residency_evicted' $false)) {
            $rr = Get-Prop $gs 'residency_mismatch_reason'
            _addg ('           residency: match=' + [string](Get-Prop $gs 'residency_match' $true) +
                   '  evicted=' + [string](Get-Prop $gs 'residency_evicted' $false) +
                   $(if ($rr) { '  (' + [string]$rr + ')' } else { '' }))
        }

        $trip = @()
        $hard = Get-Prop $gs 'hard_trigger'
        if ($hard) { $trip += ('HARD=' + [string]$hard) }
        $softThis = Get-Prop $gs 'soft_strikes_this_step'
        $softWin = Get-Prop $gs 'soft_strikes_window'
        if (($null -ne $softThis) -or ($null -ne $softWin)) { $trip += ('soft_strikes=' + [string]$softThis + '/win' + [string]$softWin) }
        $sr = @(Get-Prop $gs 'soft_reasons')
        if ($sr.Count -gt 0) { $trip += ('reasons=[' + (Limit-Text ($sr -join ', ') 200) + ']') }
        $escal = Get-Prop $gs 'escalated_to'
        if ($escal) { $trip += ('-> escalated_to ' + [string]$escal) }
        if ($trip.Count -gt 0) { _addg ('           trigger: ' + ($trip -join '  ')) }
    }
    return $sb.ToString()
}

function Format-AgentTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    $sb = [System.Text.StringBuilder]::new()
    $nl = [Environment]::NewLine
    function _add([string]$line = '') { [void]$sb.AppendLine($line) }

    if ($null -eq (Get-Prop $Run 'envelope')) {
        _add 'No valid result envelope was returned by agent.local.'
        _add ''
        _add ("exit code : " + [string](Get-Prop $Run 'exit_code'))
        _add ("parse note: " + [string](Get-Prop $Run 'parse_error'))
        $tail = [string](Get-Prop $Run 'stderr_tail')
        if ($tail) { _add ''; _add 'stderr (tail):'; _add (Limit-Text $tail 1000) }
        return $sb.ToString()
    }

    $envObj = $Run.envelope
    $res = Get-Prop $Run 'result'
    $goal = if ($res) { [string](Get-Prop $res 'goal' (Get-Prop $Run 'goal')) } else { [string](Get-Prop $Run 'goal') }

    # auto-ramp (Governor Phase 3) is detected from the envelope the console already parses -- no extra file read.
    $govTrace = if ($res) { Get-Prop $res 'governor_trace' } else { $null }
    $isAutoRamp = ($null -ne $res) -and (($null -ne $govTrace) -or ((Get-Prop $res 'autoramp' $false) -eq $true) -or ($null -ne (Get-Prop $res 'final_status')))

    _add ('GOAL: ' + $goal)
    _add ('STATUS: ' + [string](Get-Prop $envObj 'status' 'unknown') + '   (agent: ' + [string](Get-Prop $res 'status' 'n/a') + ')')
    $needsFrontier = Get-Prop $res 'needs_frontier' $false
    $steps = @()
    $sv = Get-Prop $res 'steps'
    if ($sv) { $steps = @($sv) }
    _add ('STEPS: ' + [string](Get-Prop $res 'step_count' $steps.Count) + '/' + [string](Get-Prop $res 'max_steps' '?') +
          '   DRY-RUN: ' + [string](Get-Prop $res 'dry_run' $false) +
          '   NEEDS-FRONTIER: ' + [string]$needsFrontier)
    $conf = Get-Prop $envObj 'confidence'
    _add ('CONFIDENCE: ' + $(if ($null -eq $conf) { 'n/a' } else { [string]$conf }) +
          '   DURATION: ' + [string](Get-Prop $envObj 'duration_ms' (Get-Prop $Run 'elapsed_ms')) + ' ms')
    if ($isAutoRamp) {
        _add ('AUTO-RAMP: final_status=' + [string](Get-Prop $res 'final_status' 'n/a') +
              '   verified=' + [string](Get-Prop $res 'verified_success' $false) +
              '   accepted_epoch=' + $(if ($null -eq (Get-Prop $res 'accepted_epoch')) { 'none' } else { [string](Get-Prop $res 'accepted_epoch') }) +
              '   model_swaps=' + [string](Get-Prop $res 'model_swaps' 0))
    }
    if (Get-Prop $res 'route_enabled' $false) {
        $planned = @(Get-Prop $res 'planned_tools')
        $rt = Get-Prop $res 'route'
        _add ('ROUTED (route.tools): planned=[' + ($planned -join ', ') + ']' +
              '   applied=' + [string](Get-Prop $rt 'applied' $false) +
              '   fell_back=' + [string](Get-Prop $rt 'fell_back' $false))
    }
    $oc = Get-Prop $res 'outcome'
    if ($oc) {
        $succ = @(Get-Prop $oc 'succeeded_tools'); $fail = @(Get-Prop $oc 'failed_tools')
        _add ('TOOLS RAN: ' + [string](Get-Prop $oc 'tools_invoked' 0) +
              '  (ok: ' + $(if ($succ.Count) { $succ -join ', ' } else { 'none' }) +
              '; failed: ' + $(if ($fail.Count) { $fail -join ', ' } else { 'none' }) + ')')
    }
    _add ''

    $finalAnswer = Get-Prop $res 'final_answer'
    _add 'FINAL ANSWER:'
    if ([string]::IsNullOrWhiteSpace([string]$finalAnswer)) { _add '  (none)' }
    else { foreach ($ln in ([string]$finalAnswer -split "`n")) { _add ('  ' + $ln.TrimEnd()) } }
    _add ''

    _add '--- TRANSCRIPT (child steps) ---'
    if ($steps.Count -eq 0) { _add '  (no steps recorded)' }
    foreach ($st in $steps) {
        $idx = Get-Prop $st 'index' '?'
        _add ''
        _add ("[Step $idx]")
        $dec = Get-Prop $st 'decision'
        if ($dec) {
            $line = '  decide -> ' + [string](Get-Prop $dec 'chosen_tool' '?')
            $dc = Get-Prop $dec 'confidence'
            if ($null -ne $dc) { $line += '  (conf ' + [string]$dc }
            $via = Get-Prop $dec 'accepted_via'
            $tier = Get-Prop $dec 'accepted_tier'
            if ($via -or $tier) { $line += ', via ' + [string]$via + '/' + [string]$tier }
            if ($null -ne $dc) { $line += ')' }
            _add $line
            if (Get-Prop $dec 'needs_frontier' $false) { _add '         (needs frontier)' }
        }
        $stepArgs = Get-Prop $st 'args'
        if ($null -ne $stepArgs) { _add ('  args: ' + (Limit-Text (ConvertTo-CompactJson $stepArgs) 400)) }
        $tool = Get-Prop $st 'tool'
        if ($tool) {
            if (Get-Prop $tool 'invoked' $false) {
                $tl = '  tool ' + [string](Get-Prop $tool 'skill_id' '?') + ': ' + [string](Get-Prop $tool 'status' '?')
                $te = Get-Prop $tool 'error'
                if ($te) { $tl += '  error=' + (Limit-Text ([string]$te) 200) }
                _add $tl
                $ad = Get-Prop $tool 'artifact_dir'
                if ($ad) { _add ('       artifacts: ' + [string]$ad) }
            }
            else { _add '  tool: not invoked (dry run / no action)' }
        }
        $obs = Get-Prop $st 'observation'
        if ($null -ne $obs -and [string]$obs -ne '') { _add ('  obs: ' + (Limit-Text ([string]$obs) 500)) }
        $serr = Get-Prop $st 'error'
        if ($serr) { _add ('  STEP ERROR: ' + (Limit-Text ([string]$serr) 300)) }
    }
    _add ''

    if ($isAutoRamp) {
        _add (Format-GovernorTrace -Result $res)
    }

    $cost = Get-Prop $res 'cost'
    if ($cost) {
        _add '--- COST ---'
        _add ('  gateway calls: ' + [string](Get-Prop $cost 'total_gateway_calls' '?') +
              '  (decision ' + [string](Get-Prop $cost 'decision_calls' '?') +
              ', gen ' + [string](Get-Prop $cost 'gen_calls' '?') +
              ', tool ' + [string](Get-Prop $cost 'tool_calls' '?') + ')')
        _add ('  tokens: ' + [string](Get-Prop $cost 'total_tokens' '?') +
              '   runtime: ' + [string](Get-Prop $cost 'total_runtime_ms' '?') + ' ms')
    }

    $topErr = Get-Prop $envObj 'error'
    if ($topErr) {
        _add ''
        _add ('ERROR: ' + [string](Get-Prop $topErr 'code' 'error') + ': ' + [string](Get-Prop $topErr 'message' ''))
    }

    return $sb.ToString()
}

Export-ModuleMember -Function `
    Resolve-AgentConsolePaths, Build-AgentLocalInputs, Start-AgentLocalProcess, Stop-AgentLocalProcess, `
    Complete-AgentLocalRun, Invoke-AgentLocalRun, Format-AgentTranscript, Format-GovernorTrace, `
    Start-RouteToolsProcess, Complete-RouteToolsRun, Invoke-RouteToolsRun, Format-RoutePlan, `
    ConvertFrom-EnvelopeJson, Get-Prop, Test-HasProp
