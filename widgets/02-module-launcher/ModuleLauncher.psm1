<#
    ModuleLauncher.psm1 - driver core for the Module Launcher & Registry Browser (Widget 02).

    Holds ALL non-UI logic in two halves:
      REGISTRY BROWSER - scan modules/*/skill.json, parse each manifest, and render a
        browsable list + per-module detail (purpose, inputs, requirements, flags).
      LAUNCHER         - run any installed Module directly THROUGH the Module 1 generic
        wrapper (modules/01-skill-bootstrap/Invoke-Skill.ps1): spawn it as a child pwsh
        with -SkillDir/-InputsJson/-ArtifactRoot, parse the lifeorch.skill.invocation_report/0.1
        it emits (which nests the skill's own lifeorch.skill.result/0.1 envelope), and render it.

    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate (against
    tests/mock-invoke-skill.ps1 + a fixture modules tree) and on Windows. The UI
    (Show-ModuleLauncher.ps1) is a thin shell over these functions.

    It reimplements nothing: a Module is discovered from its skill.json manifest and RUN via
    the canonical Module 1 wrapper - the designated "run any installed skill" mechanism - exactly
    as the executor / orchestrator skills invoke child skills. Envelopes are parsed, never re-derived.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleLauncherWidgetRoot = $PSScriptRoot

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
    param($Value, [int]$Depth = 8)
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

function Resolve-ModuleLauncherPaths {
    [CmdletBinding()]
    param(
        [string]$ModulesDir,
        [string]$InvokeSkillPath,
        [string]$PwshPath,
        [string]$WidgetRoot
    )
    if (-not $WidgetRoot) { $WidgetRoot = $script:ModuleLauncherWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    $repoRoot = $null
    $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
    if ($rp) { $repoRoot = $rp.Path } else { $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }

    if (-not $ModulesDir) { $ModulesDir = Join-Path $repoRoot 'modules' }
    if (-not $InvokeSkillPath) {
        $InvokeSkillPath = Join-Path $repoRoot (Join-Path 'modules' (Join-Path '01-skill-bootstrap' 'Invoke-Skill.ps1'))
    }
    if (-not $PwshPath) {
        # Self-referential pwsh path via $PSHOME dodges the dotnet-tool 'dotnet.exe' locator gotcha.
        $cand = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $cand)) { $cand = Join-Path $PSHOME 'pwsh' }  # non-Windows (cloud gate)
        $PwshPath = $cand
    }
    return [pscustomobject]@{
        WidgetRoot      = $WidgetRoot
        RepoRoot        = $repoRoot
        ModulesDir      = $ModulesDir
        InvokeSkillPath = $InvokeSkillPath
        PwshPath        = $PwshPath
    }
}

# ---------- registry browser: discover installed Modules ----------

function Get-ModuleRegistry {
    <#
        Scan <ModulesDir>/*/skill.json and return one entry per module folder that ships a
        manifest (folders without a skill.json - e.g. the executor itself - are skipped as
        not directly launchable). A malformed manifest is STILL listed (manifest_ok=false)
        so the browser surfaces it rather than hiding it. Entries are sorted by skill_id.
    #>
    [CmdletBinding()]
    param([string]$ModulesDir, [string]$WidgetRoot)

    if (-not $ModulesDir) { $ModulesDir = (Resolve-ModuleLauncherPaths -WidgetRoot $WidgetRoot).ModulesDir }
    $entries = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $ModulesDir -PathType Container)) { return , $entries.ToArray() }

    $dirs = @(Get-ChildItem -LiteralPath $ModulesDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($d in $dirs) {
        $manifestPath = Join-Path $d.FullName 'skill.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }  # not directly launchable

        $manifest = $null; $err = ''
        try { $manifest = ([System.IO.File]::ReadAllText($manifestPath)) | ConvertFrom-Json -ErrorAction Stop }
        catch { $manifest = $null; $err = "skill.json invalid JSON: $($_.Exception.Message)" }

        if ($null -eq $manifest) {
            $entries.Add([pscustomobject]@{
                    folder = $d.FullName; folder_name = $d.Name; skill_dir = $d.FullName
                    manifest_ok = $false; manifest_error = $err
                    skill_id = $d.Name; name = '(unreadable manifest)'; version = ''; contract_version = ''
                    purpose = $err; determinism = ''; parallel_safe = $null; batch = $null; streaming = $null
                    entrypoint = ''; entrypoint_exists = $false; inputs = @(); required_inputs = @()
                    requirements = $null; timeout_seconds = $null
                })
            continue
        }

        $inv = Get-Prop $manifest 'invocation'
        $entrypoint = [string](Get-Prop $inv 'entrypoint' '')
        $entryExists = $false
        if ($entrypoint) { $entryExists = (Test-Path -LiteralPath (Join-Path $d.FullName $entrypoint) -PathType Leaf) }

        $inputs = @(); $iv = Get-Prop $manifest 'inputs'; if ($iv) { $inputs = @($iv) }
        $required = New-Object System.Collections.Generic.List[string]
        foreach ($inp in $inputs) { if ([bool](Get-Prop $inp 'required' $false)) { $required.Add([string](Get-Prop $inp 'name' '')) } }

        $timeout = Get-Prop (Get-Prop $manifest 'timeout') 'default_seconds'

        $entries.Add([pscustomobject]@{
                folder            = $d.FullName
                folder_name       = $d.Name
                skill_dir         = $d.FullName
                manifest_ok       = $true
                manifest_error    = ''
                skill_id          = [string](Get-Prop $manifest 'skill_id' $d.Name)
                name              = [string](Get-Prop $manifest 'name' '')
                version           = [string](Get-Prop $manifest 'version' '')
                contract_version  = [string](Get-Prop $manifest 'contract_version' '')
                purpose           = [string](Get-Prop $manifest 'purpose' '')
                determinism       = [string](Get-Prop $manifest 'determinism' '')
                parallel_safe     = Get-Prop $manifest 'parallel_safe'
                batch             = Get-Prop $manifest 'batch'
                streaming         = Get-Prop $manifest 'streaming'
                entrypoint        = $entrypoint
                entrypoint_exists = $entryExists
                inputs            = $inputs
                required_inputs   = $required.ToArray()
                requirements      = Get-Prop $manifest 'requirements'
                timeout_seconds   = $timeout
            })
    }

    $sorted = @($entries.ToArray() | Sort-Object { [string]$_.skill_id })
    return , $sorted
}

function Format-ModuleListLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)
    if (-not [bool](Get-Prop $Entry 'manifest_ok' $false)) {
        return ('! ' + [string](Get-Prop $Entry 'folder_name') + '  -  (unreadable manifest)')
    }
    $id = [string](Get-Prop $Entry 'skill_id')
    $name = [string](Get-Prop $Entry 'name')
    return ($id + '  -  ' + $name)
}

function Get-ModuleInputTemplate {
    <# Build a JSON template (required inputs only) so the launcher can pre-fill the inputs box. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)
    $obj = [ordered]@{}
    foreach ($inp in @(Get-Prop $Entry 'inputs')) {
        if (-not [bool](Get-Prop $inp 'required' $false)) { continue }
        $n = [string](Get-Prop $inp 'name' '')
        if (-not $n) { continue }
        $t = ([string](Get-Prop $inp 'type' 'string')).ToLowerInvariant()
        switch -regex ($t) {
            'int|long|double|float|number|decimal' { $obj[$n] = 0 }
            'bool' { $obj[$n] = $false }
            default { $obj[$n] = '' }
        }
    }
    if ($obj.Count -eq 0) { return '{}' }
    return ($obj | ConvertTo-Json -Depth 4)
}

function Format-ModuleDetail {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)
    $sb = [System.Text.StringBuilder]::new()
    function _addd([string]$line = '') { [void]$sb.AppendLine($line) }

    if (-not [bool](Get-Prop $Entry 'manifest_ok' $false)) {
        _addd ('MODULE FOLDER: ' + [string](Get-Prop $Entry 'folder_name'))
        _addd ''
        _addd 'This module has a skill.json that could not be parsed:'
        _addd ('  ' + [string](Get-Prop $Entry 'manifest_error'))
        return $sb.ToString()
    }

    _addd ([string](Get-Prop $Entry 'skill_id') + '   -   ' + [string](Get-Prop $Entry 'name'))
    _addd ('folder: ' + [string](Get-Prop $Entry 'folder_name') +
        '   version: ' + [string](Get-Prop $Entry 'version') +
        '   contract: ' + [string](Get-Prop $Entry 'contract_version'))
    _addd ('determinism: ' + [string](Get-Prop $Entry 'determinism') +
        '   parallel_safe: ' + [string](Get-Prop $Entry 'parallel_safe') +
        '   batch: ' + [string](Get-Prop $Entry 'batch') +
        '   streaming: ' + [string](Get-Prop $Entry 'streaming'))
    $to = Get-Prop $Entry 'timeout_seconds'
    _addd ('entrypoint: ' + [string](Get-Prop $Entry 'entrypoint') +
        $(if ([bool](Get-Prop $Entry 'entrypoint_exists' $false)) { '' } else { '  [MISSING!]' }) +
        $(if ($null -ne $to) { '   timeout: ' + [string]$to + 's' } else { '' }))
    _addd ''
    _addd 'PURPOSE:'
    foreach ($ln in (([string](Get-Prop $Entry 'purpose')) -split "`n")) { _addd ('  ' + $ln.TrimEnd()) }
    _addd ''

    $req = Get-Prop $Entry 'requirements'
    if ($req) {
        $models = @(Get-Prop $req 'models')
        _addd ('REQUIREMENTS: gpu=' + [string](Get-Prop $req 'gpu' 'none') +
            '  filesystem=' + [string](Get-Prop $req 'filesystem' 'none') +
            '  network=' + [string](Get-Prop $req 'network' $false) +
            '  screen=' + [string](Get-Prop $req 'screen' $false) +
            '  audio=' + [string](Get-Prop $req 'audio' $false))
        if ($models.Count -gt 0) { _addd ('  models: ' + ($models -join ', ')) }
        _addd ''
    }

    _addd 'INPUTS:'
    $inputs = @(Get-Prop $Entry 'inputs')
    if ($inputs.Count -eq 0) { _addd '  (none declared)' }
    foreach ($inp in $inputs) {
        $reqd = if ([bool](Get-Prop $inp 'required' $false)) { 'required' } else { 'optional' }
        $def = Get-Prop $inp 'default'
        $defTxt = if ($null -ne $def) { '  default=' + (ConvertTo-CompactJson $def) } else { '' }
        _addd ('  - ' + [string](Get-Prop $inp 'name') + ' (' + [string](Get-Prop $inp 'type' 'string') + ', ' + $reqd + ')' + $defTxt)
        $desc = [string](Get-Prop $inp 'description' '')
        if ($desc) { _addd ('      ' + (Limit-Text $desc 220)) }
    }
    return $sb.ToString()
}

# ---------- launcher: run a Module through the Module 1 wrapper ----------

function Start-ModuleProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SkillDir,
        [string]$InputsJson = '{}',
        [string]$WorkingDir,
        [string]$InvokeSkillPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$InvocationId,
        [hashtable]$Sync,
        [string]$WidgetRoot
    )
    $paths = Resolve-ModuleLauncherPaths -InvokeSkillPath $InvokeSkillPath -PwshPath $PwshPath -WidgetRoot $WidgetRoot

    $wrapper = $paths.InvokeSkillPath
    if (-not [System.IO.Path]::IsPathRooted($wrapper)) {
        $rp = Resolve-Path -LiteralPath $wrapper -ErrorAction SilentlyContinue
        if ($rp) { $wrapper = $rp.Path }
    }
    if (-not (Test-Path -LiteralPath $wrapper)) { throw "Invoke-Skill.ps1 (Module 1 wrapper) not found: $wrapper" }

    $skillDirAbs = $SkillDir
    if (-not [System.IO.Path]::IsPathRooted($skillDirAbs)) {
        $rp = Resolve-Path -LiteralPath $skillDirAbs -ErrorAction SilentlyContinue
        if ($rp) { $skillDirAbs = $rp.Path }
    }
    if (-not (Test-Path -LiteralPath $skillDirAbs -PathType Container)) { throw "module folder not found: $skillDirAbs" }

    if ([string]::IsNullOrWhiteSpace($InputsJson)) { $InputsJson = '{}' }
    if (-not $InvocationId) { $InvocationId = [guid]::NewGuid().ToString() }
    if (-not $ArtifactRoot) {
        $ArtifactRoot = Join-Path (Join-Path $paths.WidgetRoot (Join-Path 'runtime' 'artifacts')) $InvocationId
    }
    New-Item -ItemType Directory -Path $ArtifactRoot -Force -ErrorAction SilentlyContinue | Out-Null

    $stdoutPath = Join-Path $ArtifactRoot 'wrapper.stdout.txt'
    $stderrPath = Join-Path $ArtifactRoot 'wrapper.stderr.txt'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $paths.PwshPath
    $argv = @('-NoProfile', '-NonInteractive', '-File', $wrapper,
        '-SkillDir', $skillDirAbs, '-InputsJson', $InputsJson,
        '-ArtifactRoot', $ArtifactRoot, '-PwshPath', $paths.PwshPath)
    foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }   # per-arg escaping; safe with spaces/quotes in the JSON
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $wd = if ($WorkingDir) { $WorkingDir } else { $paths.RepoRoot }
    if (Test-Path -LiteralPath $wd) { $psi.WorkingDirectory = $wd }

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
        InputsJson   = $InputsJson
        Paths        = $paths
        StartedUtc   = $startedUtc
        SkillDir     = $skillDirAbs
    }
}

function Stop-ModuleProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)
    if ($null -eq $Handle) { return }
    try {
        if (-not $Handle.Process.HasExited) { $Handle.Process.Kill($true) }  # kill the whole tree
    } catch { }
}

function Complete-ModuleRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)

    $proc = $Handle.Process
    try { $proc.WaitForExit() } catch { }

    $stdout = ''; $stderr = ''
    try { $stdout = $Handle.StdoutTask.GetAwaiter().GetResult() } catch { }
    try { $stderr = $Handle.StderrTask.GetAwaiter().GetResult() } catch { }
    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try { [System.IO.File]::WriteAllText($Handle.StdoutPath, $stdout, $utf8) } catch { }
    try { [System.IO.File]::WriteAllText($Handle.StderrPath, $stderr, $utf8) } catch { }

    $wrapperExit = $null
    try { $wrapperExit = $proc.ExitCode } catch { }

    $parseError = $null
    $report = ConvertFrom-EnvelopeJson -Text $stdout -ErrorRef ([ref]$parseError)

    $manifestValid = $false; $invoked = $false; $reportExit = $null
    $envelopeValid = $false; $envelopeErrors = @(); $manifestErrors = @()
    $skillEnvelope = $null; $skillId = $null
    if ($report) {
        $manifestValid  = [bool](Get-Prop $report 'manifest_valid' $false)
        $invoked        = [bool](Get-Prop $report 'invoked' $false)
        $reportExit     = Get-Prop $report 'exit_code'
        $envelopeValid  = [bool](Get-Prop $report 'envelope_valid' $false)
        $envelopeErrors = @(Get-Prop $report 'envelope_errors')
        $manifestErrors = @(Get-Prop $report 'manifest_errors')
        $skillEnvelope  = Get-Prop $report 'envelope'
        $skillId        = Get-Prop $report 'skill_id'
    }
    if (-not $skillId) { $skillId = [System.IO.Path]::GetFileName($Handle.SkillDir) }

    $skillStatus = 'n/a'
    if ($skillEnvelope) { $skillStatus = [string](Get-Prop $skillEnvelope 'status' 'unknown') }
    $skillResult = if ($skillEnvelope) { Get-Prop $skillEnvelope 'result' } else { $null }

    $stderrTail = if ($stderr.Length -gt 1200) { $stderr.Substring($stderr.Length - 1200) } else { $stderr }

    $ok = ($null -ne $report -and $manifestValid -and $invoked -and $envelopeValid -and ($skillStatus -eq 'ok' -or $skillStatus -eq 'partial'))

    $error = $null
    if (-not $ok) {
        if ($null -eq $report) {
            $error = [pscustomobject]@{ code = 'no_report'; message = ("Invoke-Skill.ps1 produced no valid invocation_report (wrapper exit=$wrapperExit). " + [string]$parseError) }
        }
        elseif (-not $manifestValid) {
            $error = [pscustomobject]@{ code = 'manifest_invalid'; message = ('manifest failed validation: ' + (($manifestErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif (-not $invoked) {
            $error = [pscustomobject]@{ code = 'not_invoked'; message = ('module was not invoked: ' + (($envelopeErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif (-not $envelopeValid) {
            $error = [pscustomobject]@{ code = 'envelope_invalid'; message = ('the module did not return a valid result envelope: ' + (($envelopeErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif ($skillEnvelope -and (Get-Prop $skillEnvelope 'error')) {
            $e = Get-Prop $skillEnvelope 'error'
            $error = [pscustomobject]@{ code = [string](Get-Prop $e 'code' 'error'); message = [string](Get-Prop $e 'message' '') }
        }
        else {
            $error = [pscustomobject]@{ code = 'not_ok'; message = "the module returned status '$skillStatus'." }
        }
    }

    $elapsedMs = [int]([datetime]::UtcNow - $Handle.StartedUtc).TotalMilliseconds

    return [pscustomobject]@{
        ok               = $ok
        report           = $report
        skill_envelope   = $skillEnvelope
        skill_result     = $skillResult
        skill_status     = $skillStatus
        skill_id         = $skillId
        manifest_valid   = $manifestValid
        invoked          = $invoked
        wrapper_exit     = $wrapperExit
        report_exit_code = $reportExit
        envelope_valid   = $envelopeValid
        envelope_errors  = $envelopeErrors
        manifest_errors  = $manifestErrors
        stderr_tail      = $stderrTail
        raw_stdout       = $stdout
        parse_error      = $parseError
        error            = $error
        elapsed_ms       = $elapsedMs
        skill_dir        = $Handle.SkillDir
        artifact_root    = $Handle.ArtifactRoot
    }
}

function Invoke-ModuleRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SkillDir,
        [string]$InputsJson = '{}',
        [string]$WorkingDir,
        [string]$InvokeSkillPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$WidgetRoot
    )
    $h = Start-ModuleProcess -SkillDir $SkillDir -InputsJson $InputsJson -WorkingDir $WorkingDir `
        -InvokeSkillPath $InvokeSkillPath -PwshPath $PwshPath -ArtifactRoot $ArtifactRoot -WidgetRoot $WidgetRoot
    try { $h.Process.WaitForExit() } catch { }
    return Complete-ModuleRun -Handle $h
}

# ---------- render a run result ----------

function Format-ModuleResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    $sb = [System.Text.StringBuilder]::new()
    function _addr([string]$line = '') { [void]$sb.AppendLine($line) }

    if ($null -eq (Get-Prop $Run 'report')) {
        _addr 'No valid invocation report was returned by the Module 1 wrapper.'
        _addr ''
        _addr ('wrapper exit : ' + [string](Get-Prop $Run 'wrapper_exit'))
        _addr ('parse note   : ' + [string](Get-Prop $Run 'parse_error'))
        $tail = [string](Get-Prop $Run 'stderr_tail')
        if ($tail) { _addr ''; _addr 'stderr (tail):'; _addr (Limit-Text $tail 1000) }
        return $sb.ToString()
    }

    _addr ('MODULE: ' + [string](Get-Prop $Run 'skill_id'))
    _addr ('WRAPPER: manifest_valid=' + [string](Get-Prop $Run 'manifest_valid') +
        '  invoked=' + [string](Get-Prop $Run 'invoked') +
        '  envelope_valid=' + [string](Get-Prop $Run 'envelope_valid') +
        '  skill_exit=' + [string](Get-Prop $Run 'report_exit_code'))

    $skEnv = Get-Prop $Run 'skill_envelope'
    $conf = if ($skEnv) { Get-Prop $skEnv 'confidence' } else { $null }
    _addr ('RESULT: status=' + [string](Get-Prop $Run 'skill_status') +
        '   confidence=' + $(if ($null -eq $conf) { 'n/a' } else { [string]$conf }) +
        '   duration=' + [string]$(if ($skEnv) { Get-Prop $skEnv 'duration_ms' (Get-Prop $Run 'elapsed_ms') } else { Get-Prop $Run 'elapsed_ms' }) + ' ms')
    _addr ''

    if (-not [bool](Get-Prop $Run 'manifest_valid' $false)) {
        _addr 'MANIFEST ERRORS:'
        foreach ($m in @(Get-Prop $Run 'manifest_errors')) { if ($m) { _addr ('  - ' + [string]$m) } }
        _addr ''
    }
    if ([bool](Get-Prop $Run 'invoked' $false) -and -not [bool](Get-Prop $Run 'envelope_valid' $false)) {
        _addr 'ENVELOPE ERRORS:'
        foreach ($m in @(Get-Prop $Run 'envelope_errors')) { if ($m) { _addr ('  - ' + [string]$m) } }
        _addr ''
    }

    if ($skEnv) {
        $res = Get-Prop $skEnv 'result'
        _addr 'RESULT PAYLOAD:'
        if ($null -eq $res) { _addr '  (none)' }
        else { _addr ('  ' + (Limit-Text (ConvertTo-CompactJson $res 10) 1600)) }
        _addr ''

        $arts = @(Get-Prop $skEnv 'artifacts')
        _addr ('ARTIFACTS (' + $arts.Count + '):')
        if ($arts.Count -eq 0) { _addr '  (none)' }
        foreach ($a in $arts) {
            _addr ('  - ' + [string](Get-Prop $a 'path') +
                '  (' + [string](Get-Prop $a 'kind' '?') + ', ' + [string](Get-Prop $a 'bytes' '?') + ' bytes)')
        }

        $prov = @(Get-Prop $skEnv 'model_provenance')
        if ($prov.Count -gt 0) {
            _addr ''
            _addr 'MODEL PROVENANCE:'
            foreach ($p in $prov) {
                _addr ('  - ' + [string](Get-Prop $p 'stage' '') + ' ' + [string](Get-Prop $p 'model_id' (Get-Prop $p 'model' '')) +
                    '  ' + [string](Get-Prop $p 'runtime_ms' '?') + ' ms')
            }
        }

        $warn = @(Get-Prop $skEnv 'warnings')
        if ($warn.Count -gt 0) {
            _addr ''
            _addr 'WARNINGS:'
            foreach ($w in $warn) { _addr ('  - ' + (Limit-Text ([string]$w) 300)) }
        }
    }

    $err = Get-Prop $Run 'error'
    if ($err) {
        _addr ''
        _addr ('ERROR: ' + [string](Get-Prop $err 'code' 'error') + ': ' + (Limit-Text ([string](Get-Prop $err 'message' '')) 500))
    }

    $tail = [string](Get-Prop $Run 'stderr_tail')
    if ($tail -and -not [bool](Get-Prop $Run 'ok' $false)) {
        _addr ''
        _addr 'stderr (tail):'
        _addr (Limit-Text $tail 800)
    }
    return $sb.ToString()
}

Export-ModuleMember -Function `
    Resolve-ModuleLauncherPaths, Get-ModuleRegistry, Format-ModuleListLine, `
    Get-ModuleInputTemplate, Format-ModuleDetail, `
    Start-ModuleProcess, Stop-ModuleProcess, Complete-ModuleRun, Invoke-ModuleRun, Format-ModuleResult, `
    ConvertFrom-EnvelopeJson, Get-Prop, Test-HasProp, Limit-Text
