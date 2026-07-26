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
        PwshPath       = $PwshPath
    }
}

# ---------- spawn / complete / run ----------

function Start-AgentLocalProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Goal,
        [string]$WorkingDir,
        [int]$MaxSteps = 4,
        [switch]$DryRun,
        [string[]]$DecisionTiers,
        [string]$GenTier,
        [string]$AgentLocalPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$InvocationId,
        [hashtable]$Sync,
        [string]$WidgetRoot
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

    $inputs = [ordered]@{ goal = $Goal; max_steps = $MaxSteps; dry_run = [bool]$DryRun }
    if ($WorkingDir) { $inputs['working_dir'] = $WorkingDir }
    if ($DecisionTiers -and $DecisionTiers.Count -gt 0) { $inputs['decision_tiers'] = @($DecisionTiers) }
    if ($GenTier) { $inputs['gen_tier'] = $GenTier }
    $inputsJson = ($inputs | ConvertTo-Json -Compress -Depth 6)

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
        [string[]]$DecisionTiers,
        [string]$GenTier,
        [string]$AgentLocalPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$WidgetRoot
    )
    $h = Start-AgentLocalProcess -Goal $Goal -WorkingDir $WorkingDir -MaxSteps $MaxSteps -DryRun:$DryRun `
        -DecisionTiers $DecisionTiers -GenTier $GenTier -AgentLocalPath $AgentLocalPath -PwshPath $PwshPath `
        -ArtifactRoot $ArtifactRoot -WidgetRoot $WidgetRoot
    try { $h.Process.WaitForExit() } catch { }
    return Complete-AgentLocalRun -Handle $h
}

# ---------- render ----------

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
    Resolve-AgentConsolePaths, Start-AgentLocalProcess, Stop-AgentLocalProcess, `
    Complete-AgentLocalRun, Invoke-AgentLocalRun, Format-AgentTranscript, `
    ConvertFrom-EnvelopeJson, Get-Prop, Test-HasProp
