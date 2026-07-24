#requires -Version 7.0
<#
.SYNOPSIS
  uia.actor — perform one UI Automation control-pattern action on a located element (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Resolves a target window (by -Hwnd/-ProcessId/-Title, else the desktop root) and a single element within it
  (by -AutomationId/-Name/-ControlType and/or -Path from uia.inspector), then performs ONE action through a UIA
  control pattern: invoke | toggle | select | expand | collapse | setvalue | focus. UIA patterns only — no
  synthetic mouse/keyboard input. -DryRun (alias -WhatIf) resolves and reports the intended action WITHOUT
  performing it. Emits one lifeorch.skill.result/0.1 envelope on stdout and writes action.md + action.json.
  Diagnostics go to stderr. Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Calculator*' -Action invoke -AutomationId num5Button -WhatIf
  pwsh -NoProfile -File .\Invoke-UiaActor.ps1 -Title 'Calculator*' -Action setvalue -ControlType Edit -Value '42'
#>
[CmdletBinding()]
param(
    [long]$Hwnd = 0,
    [int]$ProcessId = 0,
    [string]$Title,
    [string]$Action,
    [string]$AutomationId,
    [string]$Name,
    [string]$ControlType,
    [string]$Path,
    [string]$Value,
    [Alias('WhatIf')][switch]$DryRun,
    [int]$Depth = 12,
    [int]$MaxElements = 3000,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'uia.actor'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[uia.actor] $m") }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$pathProvided = $false
$isDry = $false
$validActions = @('invoke','toggle','select','expand','collapse','setvalue','focus')

try {
    $jsonDry = $false
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            $n = $p.PSObject.Properties.Name
            if ($n -contains 'hwnd')          { $Hwnd = [long]$p.hwnd }
            if ($n -contains 'pid')           { $ProcessId = [int]$p.pid }
            if ($n -contains 'title')         { $Title = [string]$p.title }
            if ($n -contains 'action')        { $Action = [string]$p.action }
            if ($n -contains 'automation_id') { $AutomationId = [string]$p.automation_id }
            if ($n -contains 'name')          { $Name = [string]$p.name }
            if ($n -contains 'control_type')  { $ControlType = [string]$p.control_type }
            if ($n -contains 'path')          { $Path = [string]$p.path; $pathProvided = $true }
            if ($n -contains 'value')         { $Value = [string]$p.value }
            if ($n -contains 'depth')         { $Depth = [int]$p.depth }
            if ($n -contains 'max_elements')  { $MaxElements = [int]$p.max_elements }
            if ($n -contains 'dry_run')       { if ([bool]$p.dry_run) { $jsonDry = $true } }
        }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $pathProvided = $true }
    if ($DryRun.IsPresent -or $jsonDry) { $isDry = $true }

    $act = ''
    if (-not [string]::IsNullOrWhiteSpace($Action)) { $act = $Action.Trim().ToLowerInvariant() }
    if ($act -in @('set-value','set_value','value')) { $act = 'setvalue' }

    $normInputs = [ordered]@{ hwnd=$Hwnd; pid=$ProcessId; title=$Title; action=$act; automation_id=$AutomationId; name=$Name; control_type=$ControlType; path=$Path; path_provided=$pathProvided; value=$Value; dry_run=$isDry; depth=$Depth; max_elements=$MaxElements }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    $hasLocator = $pathProvided -or (-not [string]::IsNullOrWhiteSpace($AutomationId)) -or (-not [string]::IsNullOrWhiteSpace($Name)) -or (-not [string]::IsNullOrWhiteSpace($ControlType))

    if ([string]::IsNullOrWhiteSpace($act)) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_action'; message="action is required; one of: $($validActions -join ', ')"; retryable=$false }
    }
    elseif ($validActions -notcontains $act) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_action'; message="unknown action '$act'; expected one of: $($validActions -join ', ')"; retryable=$false }
    }
    elseif (-not $hasLocator) {
        $status = 'error'; $errorObj = [ordered]@{ code='no_locator'; message='provide at least one locator: automation_id, name, control_type, or path'; retryable=$false }
    }
    elseif ($act -eq 'setvalue' -and -not $isDry -and [string]::IsNullOrEmpty($Value)) {
        $status = 'error'; $errorObj = [ordered]@{ code='value_required'; message="action 'setvalue' requires -Value"; retryable=$false }
    }
    else {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
        $AET = [System.Windows.Automation.AutomationElement]
        $SCOPE = [System.Windows.Automation.TreeScope]::Children
        $condTrue = [System.Windows.Automation.Condition]::TrueCondition

        # ---- resolve target ----
        $target = $null; $targetErr = $null; $targetKind = 'desktop-root'
        if ($Hwnd -ne 0) {
            $targetKind = "hwnd:$Hwnd"; try { $target = $AET::FromHandle([IntPtr]$Hwnd) } catch { $targetErr = "hwnd $Hwnd not accessible: $($_.Exception.Message)" }
        }
        elseif ($ProcessId -ne 0) {
            $targetKind = "pid:$ProcessId"
            $pp = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if ($pp -and $pp.MainWindowHandle -ne 0) { try { $target = $AET::FromHandle([IntPtr]$pp.MainWindowHandle) } catch { $targetErr = "pid $ProcessId window not accessible" } }
            else { $targetErr = "pid $ProcessId has no main window" }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Title)) {
            $targetKind = "title:$Title"
            $tops = $AET::RootElement.FindAll($SCOPE, $condTrue)
            foreach ($w in $tops) { try { if ($w.Current.Name -like $Title) { $target = $w; break } } catch { } }
            if ($null -eq $target) { $targetErr = "no top-level window with title like '$Title'" }
        }
        else { $target = $AET::RootElement }

        if ($null -eq $target) {
            $status = 'error'; $errorObj = [ordered]@{ code='target_not_found'; message=$targetErr; retryable=$true }
        }
        else {
            function Get-Rect($el) {
                try {
                    $r = $el.Current.BoundingRectangle
                    if ($r.IsEmpty -or [double]::IsInfinity($r.X) -or [double]::IsInfinity($r.Y)) { return @(0,0,0,0) }
                    return @([int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)
                } catch { return @(0,0,0,0) }
            }
            function Read-El($el, $depth, $path, $refId) {
                $ct=''; $nm=''; $aid=''; $cls=''; $en=$false; $off=$false; $kf=$false
                try { $ct = $el.Current.ControlType.ProgrammaticName.Replace('ControlType.','') } catch { }
                try { $nm = [string]$el.Current.Name } catch { }
                try { $aid = [string]$el.Current.AutomationId } catch { }
                try { $cls = [string]$el.Current.ClassName } catch { }
                try { $en = [bool]$el.Current.IsEnabled } catch { }
                try { $off = [bool]$el.Current.IsOffscreen } catch { }
                try { $kf = [bool]$el.Current.IsKeyboardFocusable } catch { }
                $rect = Get-Rect $el
                $pats = New-Object System.Collections.Generic.List[string]
                try { foreach ($sp in $el.GetSupportedPatterns()) { $pats.Add(($sp.ProgrammaticName.Split('.')[0] -replace 'PatternIdentifiers$','')) } } catch { }
                [pscustomobject]@{ ref=$refId; path=$path; depth=$depth; control_type=$ct; name=$nm; automation_id=$aid; class_name=$cls; x=$rect[0]; y=$rect[1]; width=$rect[2]; height=$rect[3]; enabled=$en; offscreen=$off; keyboard_focusable=$kf; patterns=$pats.ToArray() }
            }
            function Get-Pat($el, $patId) {
                $o = $null
                try { if ($el.TryGetCurrentPattern($patId, [ref]$o)) { return $o } } catch { }
                return $null
            }
            function Read-State($el, $action) {
                $st = [ordered]@{}
                try {
                    if ($action -eq 'toggle') {
                        $q = Get-Pat $el ([System.Windows.Automation.TogglePattern]::Pattern)
                        if ($q) { $st.toggle_state = [string]([System.Windows.Automation.TogglePattern]$q).Current.ToggleState }
                    }
                    elseif ($action -eq 'select') {
                        $q = Get-Pat $el ([System.Windows.Automation.SelectionItemPattern]::Pattern)
                        if ($q) { $st.is_selected = [bool]([System.Windows.Automation.SelectionItemPattern]$q).Current.IsSelected }
                    }
                    elseif ($action -eq 'expand' -or $action -eq 'collapse') {
                        $q = Get-Pat $el ([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
                        if ($q) { $st.expand_collapse_state = [string]([System.Windows.Automation.ExpandCollapsePattern]$q).Current.ExpandCollapseState }
                    }
                    elseif ($action -eq 'setvalue') {
                        $q = Get-Pat $el ([System.Windows.Automation.ValuePattern]::Pattern)
                        if ($q) { $vv = [System.Windows.Automation.ValuePattern]$q; $st.value = [string]$vv.Current.Value; $st.is_read_only = [bool]$vv.Current.IsReadOnly }
                    }
                    elseif ($action -eq 'focus') {
                        try { $st.has_keyboard_focus = [bool]$el.Current.HasKeyboardFocus } catch { }
                        try { $st.is_keyboard_focusable = [bool]$el.Current.IsKeyboardFocusable } catch { }
                    }
                } catch { }
                return $st
            }

            $tHwnd=0; try { $tHwnd = [int64]$target.Current.NativeWindowHandle } catch { }
            $tName=''; try { $tName = [string]$target.Current.Name } catch { }
            $tCt=''; try { $tCt = $target.Current.ControlType.ProgrammaticName.Replace('ControlType.','') } catch { }
            $tCls=''; try { $tCls = [string]$target.Current.ClassName } catch { }
            $tPid=0; try { $tPid = [int]$target.Current.ProcessId } catch { }
            $targetObj = [ordered]@{ kind=$targetKind; hwnd=$tHwnd; name=$tName; control_type=$tCt; class_name=$tCls; pid=$tPid }

            # ---- resolve element ----
            $matchEl = $null; $candidates = @(); $candidateCount = 0; $resolveErr = $null; $resolveCode = $null; $resolvedRec = $null

            if ($pathProvided) {
                $el = $target; $okPath = $true
                if (-not [string]::IsNullOrEmpty($Path)) {
                    foreach ($seg in $Path.Split('.')) {
                        $idx = $seg -as [int]
                        if ($null -eq $idx) { $okPath = $false; $resolveErr = "path segment '$seg' is not an integer"; break }
                        $kids = $null
                        try { $kids = $el.FindAll($SCOPE, $condTrue) } catch { $okPath = $false; $resolveErr = "children unavailable while resolving path at segment '$seg'"; break }
                        $kc = 0; if ($null -ne $kids) { $kc = $kids.Count }
                        if ($idx -lt 0 -or $idx -ge $kc) { $okPath = $false; $resolveErr = "path index $idx out of range (child count $kc) at segment '$seg'"; break }
                        $el = $kids[$idx]
                    }
                }
                if ($okPath) { $matchEl = $el; $candidateCount = 1; $resolvedRec = Read-El $matchEl 0 $Path 0 }
                else { $resolveCode = 'path_not_resolvable' }
            }
            else {
                $nodes = New-Object System.Collections.Generic.List[object]
                $truncated = $false
                $stack = New-Object System.Collections.Generic.Stack[object]
                $stack.Push([pscustomobject]@{ El=$target; Depth=0; Path='' })
                $refc = 0
                while ($stack.Count -gt 0) {
                    if ($nodes.Count -ge $MaxElements) { $truncated = $true; break }
                    $node = $stack.Pop()
                    $rec = Read-El $node.El $node.Depth $node.Path $refc; $refc++
                    $nodes.Add([pscustomobject]@{ El=$node.El; Rec=$rec })
                    if ($node.Depth -lt $Depth) {
                        $kids = $null
                        try { $kids = $node.El.FindAll($SCOPE, $condTrue) } catch { $warnings.Add("children unavailable at path '$($node.Path)'") }
                        if ($null -ne $kids -and $kids.Count -gt 0) {
                            for ($i = $kids.Count - 1; $i -ge 0; $i--) {
                                $cp = if ($node.Path -eq '') { "$i" } else { "$($node.Path).$i" }
                                $stack.Push([pscustomobject]@{ El=$kids[$i]; Depth=$node.Depth+1; Path=$cp })
                            }
                        }
                    }
                }
                if ($truncated) { $warnings.Add("search truncated at max_elements=$MaxElements; refine the locator or raise depth/max_elements") }
                $nodeArr = $nodes.ToArray()
                $matched = @($nodeArr | Where-Object {
                    $r = $_.Rec; $ok = $true
                    if (-not [string]::IsNullOrWhiteSpace($AutomationId) -and $r.automation_id -ne $AutomationId) { $ok = $false }
                    if ($ok -and -not [string]::IsNullOrWhiteSpace($ControlType) -and $r.control_type -ne $ControlType) { $ok = $false }
                    if ($ok -and -not [string]::IsNullOrWhiteSpace($Name) -and ($r.name -notlike $Name)) { $ok = $false }
                    $ok
                })
                $candidateCount = $matched.Count
                if ($candidateCount -eq 1) { $matchEl = $matched[0].El; $resolvedRec = $matched[0].Rec }
                elseif ($candidateCount -eq 0) { $resolveCode = 'element_not_found'; $resolveErr = 'no element matched the locator under the target' }
                else {
                    $resolveCode = 'ambiguous_locator'; $resolveErr = "$candidateCount elements matched; refine the locator (add control_type/automation_id or use path)"
                    $candidates = @($matched | Select-Object -First 25 | ForEach-Object { [ordered]@{ ref=$_.Rec.ref; path=$_.Rec.path; control_type=$_.Rec.control_type; name=$_.Rec.name; automation_id=$_.Rec.automation_id } })
                    if ($candidateCount -gt 25) { $warnings.Add("candidates truncated to 25 of $candidateCount") }
                }
            }

            $locatorObj = [ordered]@{ automation_id=$AutomationId; name=$Name; control_type=$ControlType; path=$(if ($pathProvided) { $Path } else { $null }) }

            if ($null -eq $matchEl) {
                $status = 'error'; $errorObj = [ordered]@{ code=$resolveCode; message=$resolveErr; retryable=$true }
                $result = [ordered]@{
                    target=$targetObj; action=$act; dry_run=$isDry; performed=$false; actionable=$false
                    requested_pattern=$null; pattern_supported=$false; locator=$locatorObj; resolved_element=$null
                    candidate_count=$candidateCount; candidates=$candidates; before_state=$null; after_state=$null; blockers=@($resolveCode)
                }
            }
            else {
                # ---- map action -> pattern ----
                $patternName = $null; $patternId = $null
                if ($act -eq 'invoke')        { $patternName='Invoke';        $patternId=[System.Windows.Automation.InvokePattern]::Pattern }
                elseif ($act -eq 'toggle')    { $patternName='Toggle';        $patternId=[System.Windows.Automation.TogglePattern]::Pattern }
                elseif ($act -eq 'select')    { $patternName='SelectionItem'; $patternId=[System.Windows.Automation.SelectionItemPattern]::Pattern }
                elseif ($act -eq 'expand')    { $patternName='ExpandCollapse';$patternId=[System.Windows.Automation.ExpandCollapsePattern]::Pattern }
                elseif ($act -eq 'collapse')  { $patternName='ExpandCollapse';$patternId=[System.Windows.Automation.ExpandCollapsePattern]::Pattern }
                elseif ($act -eq 'setvalue')  { $patternName='Value';         $patternId=[System.Windows.Automation.ValuePattern]::Pattern }
                elseif ($act -eq 'focus')     { $patternName='(SetFocus)';    $patternId=$null }

                $patternSupported = $false
                if ($act -eq 'focus') { $patternSupported = $true }
                else { $patternSupported = ($null -ne (Get-Pat $matchEl $patternId)) }

                $elEnabled = $true; try { $elEnabled = [bool]$matchEl.Current.IsEnabled } catch { }
                $isReadOnly = $false
                if ($act -eq 'setvalue' -and $patternSupported) {
                    $vpChk = Get-Pat $matchEl $patternId
                    try { $isReadOnly = [bool]([System.Windows.Automation.ValuePattern]$vpChk).Current.IsReadOnly } catch { }
                }

                $beforeState = Read-State $matchEl $act

                $blockers = New-Object System.Collections.Generic.List[string]
                if (-not $patternSupported) { $blockers.Add('pattern_unsupported') }
                if (-not $elEnabled)        { $blockers.Add('element_disabled') }
                if ($act -eq 'setvalue' -and $isReadOnly) { $blockers.Add('value_readonly') }
                $actionable = ($blockers.Count -eq 0)

                $performed = $false; $afterState = $null

                if ($isDry) {
                    $status = 'ok'
                }
                elseif (-not $actionable) {
                    $status = 'error'
                    $code = $blockers[0]
                    $msg = switch ($code) {
                        'pattern_unsupported' { "element does not support the '$patternName' pattern required by action '$act'" }
                        'element_disabled'    { "element is disabled; cannot perform '$act'" }
                        'value_readonly'      { "value is read-only; cannot setvalue" }
                        default               { "cannot perform '$act': $code" }
                    }
                    $errorObj = [ordered]@{ code=$code; message=$msg; retryable=($code -eq 'element_disabled') }
                }
                else {
                    try {
                        if ($act -eq 'invoke')        { ([System.Windows.Automation.InvokePattern](Get-Pat $matchEl $patternId)).Invoke() }
                        elseif ($act -eq 'toggle')    { ([System.Windows.Automation.TogglePattern](Get-Pat $matchEl $patternId)).Toggle() }
                        elseif ($act -eq 'select')    { ([System.Windows.Automation.SelectionItemPattern](Get-Pat $matchEl $patternId)).Select() }
                        elseif ($act -eq 'expand')    { ([System.Windows.Automation.ExpandCollapsePattern](Get-Pat $matchEl $patternId)).Expand() }
                        elseif ($act -eq 'collapse')  { ([System.Windows.Automation.ExpandCollapsePattern](Get-Pat $matchEl $patternId)).Collapse() }
                        elseif ($act -eq 'setvalue')  { ([System.Windows.Automation.ValuePattern](Get-Pat $matchEl $patternId)).SetValue($Value) }
                        elseif ($act -eq 'focus')     { $matchEl.SetFocus() }
                        $performed = $true
                        Start-Sleep -Milliseconds 150
                        $afterState = Read-State $matchEl $act
                        $status = 'ok'
                    } catch {
                        $status = 'error'; $performed = $false
                        $errorObj = [ordered]@{ code='action_failed'; message="performing '$act' failed: $($_.Exception.Message)"; retryable=$true }
                    }
                }

                $result = [ordered]@{
                    target=$targetObj; action=$act; dry_run=$isDry; performed=$performed; actionable=$actionable
                    requested_pattern=$patternName; pattern_supported=$patternSupported; locator=$locatorObj
                    resolved_element=$resolvedRec; candidate_count=$candidateCount; candidates=$candidates
                    before_state=$beforeState; after_state=$afterState; blockers=$blockers.ToArray()
                }
                Write-Diag "target=$targetKind action=$act performed=$performed actionable=$actionable dry=$isDry -> $invDir"
            }
        }
    }

    if ($status -eq 'ok' -and $warnings.Count -gt 0) { $status = 'partial' }
}
catch {
    $status = 'error'; $errorObj = [ordered]@{ code='unhandled_exception'; message="$($_.Exception.Message)"; retryable=$false }
    Write-Diag "ERROR: $($_.Exception.Message)"
}

# ---- artifacts (only when we produced a result payload) ----
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    if ($null -ne $result) {
        $actionJson = [ordered]@{ schema='lifeorch.uia.action/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result }
        $ajPath = Join-Path $invDir 'action.json'
        [System.IO.File]::WriteAllText($ajPath, ($actionJson | ConvertTo-Json -Depth 12), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# uia.actor — $($result.action)  (dry_run=$($result.dry_run) performed=$($result.performed))")
        [void]$mb.AppendLine("target: $($result.target.kind)  `"$($result.target.name)`"  hwnd=$($result.target.hwnd) pid=$($result.target.pid)")
        $loc = $result.locator
        [void]$mb.AppendLine("locator: automation_id='$($loc.automation_id)' name='$($loc.name)' control_type='$($loc.control_type)' path='$($loc.path)'")
        if ($null -ne $result.resolved_element) {
            $re = $result.resolved_element
            [void]$mb.AppendLine("resolved: $($re.control_type) `"$($re.name)`" [aid=$($re.automation_id)] path=$($re.path)  patterns={$(@($re.patterns) -join ',')}")
        } else {
            [void]$mb.AppendLine("resolved: (none)  candidate_count=$($result.candidate_count)")
        }
        [void]$mb.AppendLine("requested_pattern=$($result.requested_pattern)  pattern_supported=$($result.pattern_supported)  actionable=$($result.actionable)")
        if (@($result.blockers).Count -gt 0) { [void]$mb.AppendLine("blockers: $(@($result.blockers) -join ', ')") }
        [void]$mb.AppendLine("before_state: $(($result.before_state | ConvertTo-Json -Compress -Depth 5))")
        [void]$mb.AppendLine("after_state:  $(($result.after_state  | ConvertTo-Json -Compress -Depth 5))")
        if (@($result.candidates).Count -gt 0) {
            [void]$mb.AppendLine("")
            [void]$mb.AppendLine("## candidates")
            foreach ($c in @($result.candidates)) { [void]$mb.AppendLine("- path=$($c.path) $($c.control_type) `"$($c.name)`" [aid=$($c.automation_id)]") }
        }
        $amPath = Join-Path $invDir 'action.md'
        [System.IO.File]::WriteAllText($amPath, $mb.ToString(), $utf8)

        foreach ($ap in @(@{p=$amPath;k='markdown'}, @{p=$ajPath;k='json'})) {
            $b = [System.IO.File]::ReadAllBytes($ap.p)
            $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $ap.p).Path; kind=$ap.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[uia.actor] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { }

$sw.Stop()
$envelope = [ordered]@{
    schema=$RESULT_SCHEMA; skill_id=$SKILL_ID; skill_version=$SKILL_VERSION; contract_version=$CONTRACT
    invocation_id=$InvocationId; status=$status
    started_at_utc=$startedAt.ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=[int]$sw.Elapsed.TotalMilliseconds; inputs_digest=$inputsDigest
    result=$result; confidence=$null; artifacts=$artifacts; model_provenance=@()
    diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$invDir }
    warnings=$warnings.ToArray(); error=$errorObj
}
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
