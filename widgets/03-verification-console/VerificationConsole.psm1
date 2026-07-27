<#
    VerificationConsole.psm1 - driver core for the Verification Console (Widget 03).

    The human-AUDIT surface for the offload / verify-cost spine (DECISION_LOG D-0050). Claude writes a
    VERIFICATION PACKET (lifeorch.verification.packet/0.1) describing items to check; the console loads it,
    lets Nicholas RUN each 'run_module' item locally through the Module 1 generic wrapper
    (modules/01-skill-bootstrap/Invoke-Skill.ps1) and SEE inputs / outputs / artifacts, work through each
    item's CHECKLIST, and EXPORT a VERIFICATION RESULT (lifeorch.verification.result/0.1) that Claude reads
    back. A 'human_action' item carries a task for Nicholas to do by hand (the handed-subtask channel).

    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate (against
    tests/mock-invoke-skill.ps1 + a fixture packet) and on Windows. The UI (Show-VerificationConsole.ps1)
    is a thin shell over these functions. It reimplements nothing: a module is RUN via the canonical
    Module 1 wrapper and its lifeorch.skill.invocation_report/0.1 (nesting the skill's result envelope) is
    parsed, never re-derived. NOT a review-queue producer.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:VerificationWidgetRoot = $PSScriptRoot
$script:PacketSchema = 'lifeorch.verification.packet/0.1'
$script:ResultSchema = 'lifeorch.verification.result/0.1'

# ============================================================================
#  small helpers (shared shape with ModuleLauncher.psm1)
# ============================================================================

function Test-HasProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject -and $null -ne $Object.PSObject.Properties[$Name])
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    # Handle both JSON-sourced pscustomobjects AND internally-built [ordered]/hashtable dictionaries.
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
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

# ============================================================================
#  path resolution
# ============================================================================

function Resolve-VerificationPaths {
    [CmdletBinding()]
    param([string]$InvokeSkillPath, [string]$PwshPath, [string]$WidgetRoot)

    if (-not $WidgetRoot) { $WidgetRoot = $script:VerificationWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    $repoRoot = $null
    $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
    if ($rp) { $repoRoot = $rp.Path } else { $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }

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
        InvokeSkillPath = $InvokeSkillPath
        PwshPath        = $PwshPath
    }
}

# ============================================================================
#  packet import + validation
# ============================================================================

function ConvertTo-NormalizedChecklist {
    param($Raw)
    $out = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($c in @($Raw)) {
        if ($null -eq $c) { continue }
        $n++
        if ($c -is [string]) {
            $out.Add([pscustomobject]@{ id = ('c' + $n); text = [string]$c })
        }
        else {
            $cid = [string](Get-Prop $c 'id' ('c' + $n))
            if (-not $cid) { $cid = 'c' + $n }
            $out.Add([pscustomobject]@{ id = $cid; text = [string](Get-Prop $c 'text' '') })
        }
    }
    return $out.ToArray()
}

function Import-VerificationPacket {
    <#
        Read a verification packet (from -Path or -Json), validate it, and return a normalized object:
          { ok, error, path, schema, packet_id, title, intro, created_by, report_back, items[], item_count }
        Each normalized item:
          { index, id, kind, title, skill_id, skill_dir, inputs_json, expected, action_text, checklist[], valid, error }
        A malformed packet returns ok=false + error (never throws on content problems); a malformed ITEM is
        listed with valid=false so the console surfaces it rather than hiding it.
    #>
    [CmdletBinding()]
    param([string]$Path, [string]$Json)

    $raw = $Json
    if (-not $raw) {
        if (-not $Path) { return [pscustomobject]@{ ok = $false; error = 'no packet path or json supplied'; items = @(); item_count = 0 } }
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return [pscustomobject]@{ ok = $false; error = "packet file not found: $Path"; path = $Path; items = @(); item_count = 0 }
        }
        try { $raw = [System.IO.File]::ReadAllText($Path) } catch { return [pscustomobject]@{ ok = $false; error = "cannot read packet: $($_.Exception.Message)"; path = $Path; items = @(); item_count = 0 } }
    }

    $obj = $null
    try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ ok = $false; error = "packet is not valid JSON: $($_.Exception.Message)"; path = $Path; items = @(); item_count = 0 } }

    $schema = [string](Get-Prop $obj 'schema' '')
    $rawItems = @(Get-Prop $obj 'items')
    $warn = New-Object System.Collections.Generic.List[string]
    if ($schema -and $schema -ne $script:PacketSchema) { $warn.Add("unexpected schema '$schema' (expected $($script:PacketSchema))") }

    $items = New-Object System.Collections.Generic.List[object]
    $idx = 0
    foreach ($it in $rawItems) {
        $idx++
        $iid = [string](Get-Prop $it 'id' ('item-' + $idx))
        if (-not $iid) { $iid = 'item-' + $idx }
        $kind = ([string](Get-Prop $it 'kind' 'run_module')).ToLowerInvariant().Trim()
        $skillId = [string](Get-Prop $it 'skill_id' '')
        $skillDir = [string](Get-Prop $it 'skill_dir' '')
        $inputsJson = Get-Prop $it 'inputs_json'
        if ($null -ne $inputsJson -and -not ($inputsJson -is [string])) { $inputsJson = ($inputsJson | ConvertTo-Json -Compress -Depth 12) }
        if ([string]::IsNullOrWhiteSpace([string]$inputsJson)) { $inputsJson = '{}' }
        $expected = [string](Get-Prop $it 'expected' '')
        $actionText = [string](Get-Prop $it 'action_text' '')
        $checklist = ConvertTo-NormalizedChecklist (Get-Prop $it 'checklist')

        $valid = $true; $ierr = ''
        if ($kind -ne 'run_module' -and $kind -ne 'human_action') { $valid = $false; $ierr = "unknown kind '$kind' (expected run_module|human_action)" }
        elseif ($kind -eq 'run_module' -and [string]::IsNullOrWhiteSpace($skillDir)) { $valid = $false; $ierr = 'run_module item is missing skill_dir' }

        $items.Add([pscustomobject]@{
                index       = $idx
                id          = $iid
                kind        = $kind
                title       = [string](Get-Prop $it 'title' $iid)
                skill_id    = $skillId
                skill_dir   = $skillDir
                inputs_json = [string]$inputsJson
                expected    = $expected
                action_text = $actionText
                checklist   = $checklist
                valid       = $valid
                error       = $ierr
            })
    }

    $ok = ($items.Count -gt 0)
    $err = if ($ok) { '' } else { 'packet has no items' }
    return [pscustomobject]@{
        ok          = $ok
        error       = $err
        path        = $Path
        schema      = $schema
        packet_id   = [string](Get-Prop $obj 'packet_id' '')
        title       = [string](Get-Prop $obj 'title' '')
        intro       = [string](Get-Prop $obj 'intro' '')
        created_by  = [string](Get-Prop $obj 'created_by' '')
        report_back = ([string](Get-Prop $obj 'report_back' 'on_all')).ToLowerInvariant()
        warnings    = $warn.ToArray()
        items       = $items.ToArray()
        item_count  = $items.Count
    }
}

function Format-PacketSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet)
    $sb = [System.Text.StringBuilder]::new()
    function _addp([string]$line = '') { [void]$sb.AppendLine($line) }
    if (-not [bool](Get-Prop $Packet 'ok' $false)) {
        _addp 'PACKET NOT LOADED'
        _addp ('  ' + [string](Get-Prop $Packet 'error'))
        return $sb.ToString()
    }
    _addp ('PACKET: ' + [string](Get-Prop $Packet 'title'))
    _addp ('id: ' + [string](Get-Prop $Packet 'packet_id') +
        '   by: ' + [string](Get-Prop $Packet 'created_by') +
        '   items: ' + [string](Get-Prop $Packet 'item_count') +
        '   report_back: ' + [string](Get-Prop $Packet 'report_back'))
    $intro = [string](Get-Prop $Packet 'intro')
    if ($intro) { _addp ''; foreach ($ln in ($intro -split "`n")) { _addp ('  ' + $ln.TrimEnd()) } }
    $w = @(Get-Prop $Packet 'warnings')
    if ($w.Count -gt 0) { _addp ''; _addp 'WARNINGS:'; foreach ($x in $w) { _addp ('  - ' + [string]$x) } }
    return $sb.ToString()
}

function Format-ItemListLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item)
    $tag = if ([string](Get-Prop $Item 'kind') -eq 'human_action') { '[human]' } else { '[run]  ' }
    $flag = if ([bool](Get-Prop $Item 'valid' $true)) { '' } else { ' !' }
    return ($tag + ' ' + [string](Get-Prop $Item 'id') + '  -  ' + [string](Get-Prop $Item 'title') + $flag)
}

function Format-ItemDetail {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item)
    $sb = [System.Text.StringBuilder]::new()
    function _addi([string]$line = '') { [void]$sb.AppendLine($line) }
    $kind = [string](Get-Prop $Item 'kind')
    _addi ([string](Get-Prop $Item 'id') + '   -   ' + [string](Get-Prop $Item 'title'))
    _addi ('kind: ' + $kind + $(if (-not [bool](Get-Prop $Item 'valid' $true)) { '   [INVALID: ' + [string](Get-Prop $Item 'error') + ']' } else { '' }))
    _addi ''
    if ($kind -eq 'human_action') {
        _addi 'ACTION (do this by hand):'
        foreach ($ln in (([string](Get-Prop $Item 'action_text')) -split "`n")) { _addi ('  ' + $ln.TrimEnd()) }
    }
    else {
        _addi ('MODULE: ' + [string](Get-Prop $Item 'skill_id') + '   (' + [string](Get-Prop $Item 'skill_dir') + ')')
        _addi ''
        _addi 'INPUTS (JSON passed as -InputsJson):'
        _addi ('  ' + [string](Get-Prop $Item 'inputs_json'))
    }
    $exp = [string](Get-Prop $Item 'expected')
    if ($exp) {
        _addi ''
        _addi 'EXPECTED:'
        foreach ($ln in ($exp -split "`n")) { _addi ('  ' + $ln.TrimEnd()) }
    }
    $cl = @(Get-Prop $Item 'checklist')
    _addi ''
    _addi ('CHECKLIST (' + $cl.Count + '):')
    if ($cl.Count -eq 0) { _addi '  (none)' }
    foreach ($c in $cl) { _addi ('  [ ] ' + [string](Get-Prop $c 'id') + ': ' + [string](Get-Prop $c 'text')) }
    return $sb.ToString()
}

function Resolve-ItemSkillDir {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item, [string]$RepoRoot)
    $sd = [string](Get-Prop $Item 'skill_dir')
    if ([string]::IsNullOrWhiteSpace($sd)) { return $sd }
    if ([System.IO.Path]::IsPathRooted($sd)) { return $sd }
    if (-not $RepoRoot) { $RepoRoot = (Resolve-VerificationPaths).RepoRoot }
    # [IO.Path]::Combine is a pure string join (no PSDrive resolution), so a foreign-platform RepoRoot
    # in a test does not throw "Cannot find drive 'C'"; on Windows it combines normally.
    return [System.IO.Path]::Combine($RepoRoot, $sd)
}

# ============================================================================
#  run a run_module item through the Module 1 wrapper
# ============================================================================

function Start-SkillProcess {
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
    $paths = Resolve-VerificationPaths -InvokeSkillPath $InvokeSkillPath -PwshPath $PwshPath -WidgetRoot $WidgetRoot

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

function Stop-SkillProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)
    if ($null -eq $Handle) { return }
    try { if (-not $Handle.Process.HasExited) { $Handle.Process.Kill($true) } } catch { }
}

function Complete-SkillRun {
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

    $err = $null
    if (-not $ok) {
        if ($null -eq $report) {
            $err = [pscustomobject]@{ code = 'no_report'; message = ("Invoke-Skill.ps1 produced no valid invocation_report (wrapper exit=$wrapperExit). " + [string]$parseError) }
        }
        elseif (-not $manifestValid) {
            $err = [pscustomobject]@{ code = 'manifest_invalid'; message = ('manifest failed validation: ' + (($manifestErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif (-not $invoked) {
            $err = [pscustomobject]@{ code = 'not_invoked'; message = ('module was not invoked: ' + (($envelopeErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif (-not $envelopeValid) {
            $err = [pscustomobject]@{ code = 'envelope_invalid'; message = ('the module did not return a valid result envelope: ' + (($envelopeErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif ($skillEnvelope -and (Get-Prop $skillEnvelope 'error')) {
            $e = Get-Prop $skillEnvelope 'error'
            $err = [pscustomobject]@{ code = [string](Get-Prop $e 'code' 'error'); message = [string](Get-Prop $e 'message' '') }
        }
        else {
            $err = [pscustomobject]@{ code = 'not_ok'; message = "the module returned status '$skillStatus'." }
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
        error            = $err
        elapsed_ms       = $elapsedMs
        skill_dir        = $Handle.SkillDir
        artifact_root    = $Handle.ArtifactRoot
    }
}

function Invoke-SkillRun {
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
    $h = Start-SkillProcess -SkillDir $SkillDir -InputsJson $InputsJson -WorkingDir $WorkingDir `
        -InvokeSkillPath $InvokeSkillPath -PwshPath $PwshPath -ArtifactRoot $ArtifactRoot -WidgetRoot $WidgetRoot
    try { $h.Process.WaitForExit() } catch { }
    return Complete-SkillRun -Handle $h
}

function Format-SkillResult {
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
            foreach ($pp in $prov) {
                _addr ('  - ' + [string](Get-Prop $pp 'stage' '') + ' ' + [string](Get-Prop $pp 'model_id' (Get-Prop $pp 'model' '')) +
                    '  ' + [string](Get-Prop $pp 'runtime_ms' '?') + ' ms')
            }
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

# ============================================================================
#  assemble + save the verification result
# ============================================================================

function New-RunSummary {
    <# Compact, JSON-safe summary of a Complete-SkillRun result for embedding in the verification result. #>
    [CmdletBinding()]
    param($Run)
    if ($null -eq $Run) { return $null }
    $skEnv = Get-Prop $Run 'skill_envelope'
    $arts = New-Object System.Collections.Generic.List[object]
    foreach ($a in @(if ($skEnv) { Get-Prop $skEnv 'artifacts' } else { @() })) {
        $arts.Add([ordered]@{ path = [string](Get-Prop $a 'path'); kind = [string](Get-Prop $a 'kind' ''); bytes = (Get-Prop $a 'bytes') })
    }
    $errObj = $null
    $e = Get-Prop $Run 'error'
    if ($e) { $errObj = [ordered]@{ code = [string](Get-Prop $e 'code' ''); message = [string](Get-Prop $e 'message' '') } }
    return [ordered]@{
        ok            = [bool](Get-Prop $Run 'ok' $false)
        skill_id      = [string](Get-Prop $Run 'skill_id')
        skill_status  = [string](Get-Prop $Run 'skill_status')
        wrapper_exit  = (Get-Prop $Run 'wrapper_exit')
        confidence    = $(if ($skEnv) { Get-Prop $skEnv 'confidence' } else { $null })
        artifacts     = $arts.ToArray()
        artifact_root = [string](Get-Prop $Run 'artifact_root')
        elapsed_ms    = (Get-Prop $Run 'elapsed_ms')
        error         = $errObj
    }
}

function New-VerificationResultItem {
    <#
        Build one result item. $Checks is a list of { id, text, verdict, note } (verdict pass|fail|na|unchecked).
        $Overall is pass|fail|partial|skipped. $Run (optional) is a Complete-SkillRun result to summarize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        $Run,
        $Checks,
        [string]$Overall = 'skipped',
        [string]$Notes = ''
    )
    $checkOut = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($Checks)) {
        if ($null -eq $c) { continue }
        $checkOut.Add([ordered]@{
                id      = [string](Get-Prop $c 'id' '')
                text    = [string](Get-Prop $c 'text' '')
                verdict = ([string](Get-Prop $c 'verdict' 'unchecked')).ToLowerInvariant()
                note    = [string](Get-Prop $c 'note' '')
            })
    }
    return [ordered]@{
        id          = [string](Get-Prop $Item 'id')
        kind        = [string](Get-Prop $Item 'kind')
        title       = [string](Get-Prop $Item 'title')
        ran         = ($null -ne $Run)
        run_summary = (New-RunSummary -Run $Run)
        checks      = $checkOut.ToArray()
        overall     = $Overall.ToLowerInvariant()
        notes       = $Notes
    }
}

function Get-VerificationSummary {
    [CmdletBinding()]
    param($Items)
    $total = 0; $pass = 0; $fail = 0; $partial = 0; $skipped = 0
    foreach ($it in @($Items)) {
        $total++
        switch (([string](Get-Prop $it 'overall' 'skipped')).ToLowerInvariant()) {
            'pass' { $pass++ }
            'fail' { $fail++ }
            'partial' { $partial++ }
            default { $skipped++ }
        }
    }
    return [ordered]@{ total = $total; pass = $pass; fail = $fail; partial = $partial; skipped = $skipped }
}

function New-VerificationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Packet,
        [Parameter(Mandatory)]$Items,
        [string]$VerifiedBy = 'nicholas'
    )
    $itemArr = @($Items)
    return [ordered]@{
        schema          = $script:ResultSchema
        packet_id       = [string](Get-Prop $Packet 'packet_id')
        title           = [string](Get-Prop $Packet 'title')
        verified_by     = $VerifiedBy
        verified_at_utc = ([datetime]::UtcNow.ToString('o'))
        summary         = (Get-VerificationSummary -Items $itemArr)
        items           = $itemArr
    }
}

function Save-VerificationResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = $Result | ConvertTo-Json -Depth 20
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
    return $Path
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Prop, Limit-Text, ConvertTo-CompactJson, ConvertFrom-EnvelopeJson, `
    Resolve-VerificationPaths, Import-VerificationPacket, ConvertTo-NormalizedChecklist, `
    Format-PacketSummary, Format-ItemListLine, Format-ItemDetail, Resolve-ItemSkillDir, `
    Start-SkillProcess, Stop-SkillProcess, Complete-SkillRun, Invoke-SkillRun, Format-SkillResult, `
    New-RunSummary, New-VerificationResultItem, Get-VerificationSummary, New-VerificationResult, Save-VerificationResult
