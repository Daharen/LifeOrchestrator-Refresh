#requires -Version 7.0
<#
.SYNOPSIS
  uia.inspector — read the UI Automation accessible control tree of a target window (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Resolves a target (by -Hwnd, -ProcessId, -Title, else the desktop root) and walks its UIA control tree
  (depth-bounded, element-capped) collecting per-element control type, name, automation id, class, bounds,
  supported patterns, and state. Read-only — no actions. Emits one lifeorch.skill.result/0.1 envelope to
  stdout and writes tree.md + elements.json. Diagnostics to stderr. Exits 0 whenever a valid envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-UiaInspector.ps1                      # desktop root
  pwsh -NoProfile -File .\Invoke-UiaInspector.ps1 -Title 'Calculator*' -Depth 6
#>
[CmdletBinding()]
param(
    [long]$Hwnd = 0,
    [int]$ProcessId = 0,
    [string]$Title,
    [int]$Depth = 4,
    [int]$MaxElements = 500,
    [string]$NameFilter,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'uia.inspector'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[uia.inspector] $m") }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$matchCount = 0; $matchesBounded = @()
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            $n = $p.PSObject.Properties.Name
            if ($n -contains 'hwnd')         { $Hwnd = [long]$p.hwnd }
            if ($n -contains 'pid')          { $ProcessId = [int]$p.pid }
            if ($n -contains 'title')        { $Title = [string]$p.title }
            if ($n -contains 'depth')        { $Depth = [int]$p.depth }
            if ($n -contains 'max_elements') { $MaxElements = [int]$p.max_elements }
            if ($n -contains 'name_filter')  { $NameFilter = [string]$p.name_filter }
        }
    }

    $normInputs = [ordered]@{ hwnd = $Hwnd; pid = $ProcessId; title = $Title; depth = $Depth; max_elements = $MaxElements; name_filter = $NameFilter }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
    $AE = [System.Windows.Automation.AutomationElement]
    $SCOPE = [System.Windows.Automation.TreeScope]::Children
    $condTrue = [System.Windows.Automation.Condition]::TrueCondition

    # --- resolve target ---
    $target = $null; $targetErr = $null; $targetKind = 'desktop-root'
    if ($Hwnd -ne 0) {
        $targetKind = "hwnd:$Hwnd"; try { $target = $AE::FromHandle([IntPtr]$Hwnd) } catch { $targetErr = "hwnd $Hwnd not accessible: $($_.Exception.Message)" }
    }
    elseif ($ProcessId -ne 0) {
        $targetKind = "pid:$ProcessId"
        $pp = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($pp -and $pp.MainWindowHandle -ne 0) { try { $target = $AE::FromHandle([IntPtr]$pp.MainWindowHandle) } catch { $targetErr = "pid $ProcessId window not accessible" } }
        else { $targetErr = "pid $ProcessId has no main window" }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Title)) {
        $targetKind = "title:$Title"
        $tops = $AE::RootElement.FindAll($SCOPE, $condTrue)
        foreach ($w in $tops) { try { if ($w.Current.Name -like $Title) { $target = $w; break } } catch { } }
        if ($null -eq $target) { $targetErr = "no top-level window with title like '$Title'" }
    }
    else { $target = $AE::RootElement }

    if ($null -eq $target) {
        $status = 'error'; $errorObj = [ordered]@{ code = 'target_not_found'; message = $targetErr; retryable = $false }
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
            $ct = ''; $nm = ''; $aid = ''; $cls = ''; $en = $false; $off = $false; $kf = $false
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
            [pscustomobject]@{ ref = $refId; path = $path; depth = $depth; control_type = $ct; name = $nm; automation_id = $aid; class_name = $cls; x = $rect[0]; y = $rect[1]; width = $rect[2]; height = $rect[3]; enabled = $en; offscreen = $off; keyboard_focusable = $kf; patterns = $pats.ToArray() }
        }

        $tHwnd = 0; try { $tHwnd = [int64]$target.Current.NativeWindowHandle } catch { }
        $tName = ''; try { $tName = [string]$target.Current.Name } catch { }
        $tCt = ''; try { $tCt = $target.Current.ControlType.ProgrammaticName.Replace('ControlType.','') } catch { }
        $tCls = ''; try { $tCls = [string]$target.Current.ClassName } catch { }
        $tPid = 0; try { $tPid = [int]$target.Current.ProcessId } catch { }
        $targetObj = [ordered]@{ kind = $targetKind; hwnd = $tHwnd; name = $tName; control_type = $tCt; class_name = $tCls; pid = $tPid }

        # DFS (pre-order), depth-bounded, element-capped
        $elements = New-Object System.Collections.Generic.List[object]
        $truncated = $false
        $stack = New-Object System.Collections.Generic.Stack[object]
        $stack.Push([pscustomobject]@{ El = $target; Depth = 0; Path = '' })
        while ($stack.Count -gt 0) {
            if ($elements.Count -ge $MaxElements) { $truncated = $true; break }
            $node = $stack.Pop()
            $elements.Add((Read-El $node.El $node.Depth $node.Path $elements.Count))
            if ($node.Depth -lt $Depth) {
                $kids = $null
                try { $kids = $node.El.FindAll($SCOPE, $condTrue) } catch { $warnings.Add("children unavailable at path '$($node.Path)'") }
                if ($null -ne $kids -and $kids.Count -gt 0) {
                    for ($i = $kids.Count - 1; $i -ge 0; $i--) {
                        $cp = if ($node.Path -eq '') { "$i" } else { "$($node.Path).$i" }
                        $stack.Push([pscustomobject]@{ El = $kids[$i]; Depth = $node.Depth + 1; Path = $cp })
                    }
                }
            }
        }
        $elArr = $elements.ToArray()

        # matches
        if (-not [string]::IsNullOrWhiteSpace($NameFilter)) {
            $matched = @($elArr | Where-Object { $_.name -like $NameFilter })
            $matchCount = $matched.Count
            $matchesBounded = @($matched | Select-Object -First 200 | ForEach-Object { [ordered]@{ ref = $_.ref; path = $_.path; control_type = $_.control_type; name = $_.name; automation_id = $_.automation_id } })
            if ($matchCount -gt 200) { $warnings.Add("matches truncated to 200 of $matchCount") }
        }

        # elements.json
        $elObj = [ordered]@{ schema = 'lifeorch.uia.tree/0.1'; target = $targetObj; generated_at_utc = $startedAt.ToString('o'); depth = $Depth; element_count = $elArr.Length; elements = $elArr }
        $elPath = Join-Path $invDir 'elements.json'
        [System.IO.File]::WriteAllText($elPath, ($elObj | ConvertTo-Json -Depth 8), $utf8)

        # tree.md
        $tb = [System.Text.StringBuilder]::new()
        [void]$tb.AppendLine("# uia.inspector — target: $targetKind")
        [void]$tb.AppendLine("$($targetObj.control_type) `"$($targetObj.name)`"  hwnd=$($targetObj.hwnd) pid=$($targetObj.pid) class=$($targetObj.class_name)")
        $hdr = "depth=$Depth  elements=$($elArr.Length)  truncated=$truncated"
        if (-not [string]::IsNullOrWhiteSpace($NameFilter)) { $hdr += "  name_filter=$NameFilter matches=$matchCount" }
        [void]$tb.AppendLine($hdr)
        [void]$tb.AppendLine("")
        foreach ($e in $elArr) {
            $indent = '  ' * [Math]::Max(0, $e.depth)
            $aidStr = if ($e.automation_id) { " [aid=$($e.automation_id)]" } else { "" }
            $patStr = if (@($e.patterns).Count) { "  {" + (@($e.patterns) -join ',') + "}" } else { "" }
            $offStr = if ($e.offscreen) { " (offscreen)" } else { "" }
            [void]$tb.AppendLine("$indent$($e.control_type) `"$($e.name)`"$aidStr  ($($e.width)x$($e.height) @ $($e.x),$($e.y))$patStr$offStr")
        }
        $treePath = Join-Path $invDir 'tree.md'
        [System.IO.File]::WriteAllText($treePath, $tb.ToString(), $utf8)

        foreach ($ap in @(@{p=$treePath;k='markdown'}, @{p=$elPath;k='json'})) {
            $b = [System.IO.File]::ReadAllBytes($ap.p)
            $artifacts += ,([ordered]@{ path = (Resolve-Path -LiteralPath $ap.p).Path; kind = $ap.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
        }

        $result = [ordered]@{
            target = $targetObj; depth = $Depth; element_count = $elArr.Length; truncated = $truncated
            name_filter = $NameFilter; match_count = $matchCount; matches = $matchesBounded
            elements = @($elArr | Select-Object -First 200)
        }
        if ($truncated -or $warnings.Count -gt 0) { $status = 'partial' }
        Write-Diag "target=$targetKind elements=$($elArr.Length) -> $invDir"
    }
}
catch {
    $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
    Write-Diag "ERROR: $($_.Exception.Message)"
}

try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[uia.inspector] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
} catch { }

$sw.Stop()
$envelope = [ordered]@{
    schema = $RESULT_SCHEMA; skill_id = $SKILL_ID; skill_version = $SKILL_VERSION; contract_version = $CONTRACT
    invocation_id = $InvocationId; status = $status
    started_at_utc = $startedAt.ToString('o'); finished_at_utc = ([DateTime]::UtcNow).ToString('o')
    duration_ms = [int]$sw.Elapsed.TotalMilliseconds; inputs_digest = $inputsDigest
    result = $result; confidence = $null; artifacts = $artifacts; model_provenance = @()
    diagnostics = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
    warnings = $warnings.ToArray(); error = $errorObj
}
$json = $envelope | ConvertTo-Json -Depth 20
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
