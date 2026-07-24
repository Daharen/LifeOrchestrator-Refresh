#requires -Version 7.0
<#
.SYNOPSIS
  proc.observer — snapshot running processes + top-level windows for Life Orchestrator (contract v0.1).
.DESCRIPTION
  Structured, point-in-time snapshot of live OS state: running processes (pid, name, path, start time,
  working set, main window) and top-level windows (title, owning pid/name, position/size, min/max, the
  foreground window) via Win32 (no screenshots, no image processing). Emits one lifeorch.skill.result/0.1
  envelope to stdout and writes processes.json + windows.json + report.md. Diagnostics to stderr.
  Exits 0 whenever a valid envelope is produced. Deterministic read of current state (sorted output).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ProcObserver.ps1
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-ProcObserver.ps1 -NameFilter 'pwsh*'
#>
[CmdletBinding()]
param(
    [bool]$VisibleOnly = $true,
    [string]$NameFilter,
    [int]$MaxItems = 2000,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'proc.observer'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[proc.observer] $m") }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId

try {
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            $names = $p.PSObject.Properties.Name
            if ($names -contains 'visible_only') { $VisibleOnly = [bool]$p.visible_only }
            if ($names -contains 'name_filter')  { $NameFilter = [string]$p.name_filter }
            if ($names -contains 'max_items')    { $MaxItems = [int]$p.max_items }
        }
    }

    $normInputs = [ordered]@{ visible_only = $VisibleOnly; name_filter = $NameFilter; max_items = $MaxItems }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    # --- processes ---
    $allProcs = @(Get-Process)
    $pidName = @{}
    foreach ($pr in $allProcs) { $pidName[[uint32]$pr.Id] = $pr.ProcessName }

    $procs = New-Object System.Collections.Generic.List[object]
    foreach ($pr in $allProcs) {
        $path = $null;    try { $path = $pr.Path } catch { }
        $started = $null; try { if ($pr.StartTime) { $started = $pr.StartTime.ToUniversalTime().ToString('o') } } catch { }
        $mwt = '';         try { $mwt = [string]$pr.MainWindowTitle } catch { }
        $mwh = 0;          try { $mwh = [int64]$pr.MainWindowHandle } catch { }
        $procs.Add([pscustomobject]@{
            pid = $pr.Id; name = $pr.ProcessName; path = $path; started_utc = $started
            working_set_bytes = [int64]$pr.WorkingSet64; main_window_title = $mwt; main_window_hwnd = $mwh
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($NameFilter)) { $procs = [System.Collections.Generic.List[object]]@($procs | Where-Object { $_.name -like $NameFilter }) }
    $procArr = @($procs | Sort-Object -Property name, pid)
    if ($procArr.Count -gt $MaxItems) { $procArr = @($procArr | Select-Object -First $MaxItems); $warnings.Add("processes truncated to $MaxItems") ; $procTrunc = $true } else { $procTrunc = $false }

    # --- windows (Win32) ---
    $wins = @()
    try {
        if (-not ([System.Management.Automation.PSTypeName]'LoWin32').Type) {
            $cs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class LoWin32 {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public class Win { public long hwnd; public string title; public uint pid; public int x, y, width, height; public bool visible, minimized, maximized, foreground; }
  public static List<Win> Windows(bool visibleOnly) {
    var list = new List<Win>();
    IntPtr fg = GetForegroundWindow();
    EnumWindows((h, l) => {
      bool vis = IsWindowVisible(h);
      if (visibleOnly && !vis) return true;
      int len = GetWindowTextLength(h);
      if (visibleOnly && len == 0) return true;
      var sb = new StringBuilder(len + 1);
      GetWindowText(h, sb, sb.Capacity);
      uint pid; GetWindowThreadProcessId(h, out pid);
      RECT r; GetWindowRect(h, out r);
      list.Add(new Win { hwnd = h.ToInt64(), title = sb.ToString(), pid = pid, x = r.Left, y = r.Top, width = r.Right - r.Left, height = r.Bottom - r.Top, visible = vis, minimized = IsIconic(h), maximized = IsZoomed(h), foreground = (h == fg) });
      return true;
    }, IntPtr.Zero);
    return list;
  }
}
'@
            Add-Type -TypeDefinition $cs -ErrorAction Stop
        }
        $raw = [LoWin32]::Windows($VisibleOnly)
        $wlist = New-Object System.Collections.Generic.List[object]
        foreach ($w in $raw) {
            $pn = $null; if ($pidName.ContainsKey([uint32]$w.pid)) { $pn = $pidName[[uint32]$w.pid] }
            $wlist.Add([pscustomobject]@{
                hwnd = $w.hwnd; title = $w.title; pid = [int]$w.pid; process_name = $pn
                x = $w.x; y = $w.y; width = $w.width; height = $w.height
                visible = $w.visible; minimized = $w.minimized; maximized = $w.maximized; foreground = $w.foreground
            })
        }
        if (-not [string]::IsNullOrWhiteSpace($NameFilter)) { $wlist = [System.Collections.Generic.List[object]]@($wlist | Where-Object { $_.process_name -and ($_.process_name -like $NameFilter) }) }
        $wins = @($wlist | Sort-Object -Property pid, hwnd)
    } catch {
        $warnings.Add("window enumeration failed: $($_.Exception.Message)")
        $wins = @()
    }

    $fgWin = @($wins | Where-Object { $_.foreground })
    $fgObj = $null
    if ($fgWin.Count -gt 0) { $f = $fgWin[0]; $fgObj = [ordered]@{ hwnd = $f.hwnd; title = $f.title; pid = $f.pid; process_name = $f.process_name } }

    # --- artifacts ---
    $host2 = $env:COMPUTERNAME
    $procObj = [ordered]@{ schema = 'lifeorch.proc.list/0.1'; host = $host2; generated_at_utc = $startedAt.ToString('o'); count = $procArr.Count; processes = @($procArr) }
    $procPath = Join-Path $invDir 'processes.json'
    [System.IO.File]::WriteAllText($procPath, ($procObj | ConvertTo-Json -Depth 6), $utf8)

    $winObj = [ordered]@{ schema = 'lifeorch.proc.windows/0.1'; host = $host2; generated_at_utc = $startedAt.ToString('o'); count = @($wins).Count; windows = @($wins) }
    $winPath = Join-Path $invDir 'windows.json'
    [System.IO.File]::WriteAllText($winPath, ($winObj | ConvertTo-Json -Depth 6), $utf8)

    $tb = [System.Text.StringBuilder]::new()
    [void]$tb.AppendLine("# proc.observer — $host2 @ $($startedAt.ToString('o'))")
    if ($null -ne $fgObj) { [void]$tb.AppendLine("foreground: `"$($fgObj.title)`"  (pid $($fgObj.pid), $($fgObj.process_name))") } else { [void]$tb.AppendLine("foreground: (none/untitled)") }
    [void]$tb.AppendLine("processes: $($procArr.Count)   windows: $(@($wins).Count)   visible_only: $VisibleOnly" + $(if ($NameFilter) { "   name_filter: $NameFilter" } else { "" }))
    [void]$tb.AppendLine("")
    [void]$tb.AppendLine("## Windows")
    foreach ($w in $wins) {
        $flag = if ($w.foreground) { '[F]' } else { '   ' }
        $state = @(); if ($w.minimized) { $state += 'min' }; if ($w.maximized) { $state += 'max' }
        $st = if ($state.Count) { '  [' + ($state -join ',') + ']' } else { '' }
        [void]$tb.AppendLine("$flag `"$($w.title)`"  pid=$($w.pid) $($w.process_name)  $($w.width)x$($w.height) @ ($($w.x),$($w.y))$st")
    }
    [void]$tb.AppendLine("")
    [void]$tb.AppendLine("## Top processes by working set (full list in processes.json)")
    foreach ($pr in @($procArr | Sort-Object -Property working_set_bytes -Descending | Select-Object -First 15)) {
        $mb = [Math]::Round($pr.working_set_bytes / 1MB, 1)
        [void]$tb.AppendLine("$($pr.name)  pid=$($pr.pid)  ws=$mb MB")
    }
    $reportPath = Join-Path $invDir 'report.md'
    [System.IO.File]::WriteAllText($reportPath, $tb.ToString(), $utf8)

    foreach ($ap in @(@{p=$reportPath;k='markdown'}, @{p=$procPath;k='json'}, @{p=$winPath;k='json'})) {
        $b = [System.IO.File]::ReadAllBytes($ap.p)
        $artifacts += ,([ordered]@{ path = (Resolve-Path -LiteralPath $ap.p).Path; kind = $ap.k; bytes = $b.Length; sha256 = (Get-Sha256Hex $b) })
    }

    $result = [ordered]@{
        host = $host2; generated_at_utc = $startedAt.ToString('o'); name_filter = $NameFilter; visible_only = $VisibleOnly
        process_count = $procArr.Count; window_count = @($wins).Count; foreground = $fgObj
        windows = @(@($wins) | Select-Object -First 200)
    }
    if ($procTrunc -or $warnings.Count -gt 0) { $status = 'partial' }
    Write-Diag "processes=$($procArr.Count) windows=$(@($wins).Count) foreground='$(if($fgObj){$fgObj.title})' -> $invDir"
}
catch {
    $status = 'error'; $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
    Write-Diag "ERROR: $($_.Exception.Message)"
}

try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[proc.observer] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
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
