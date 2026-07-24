#requires -Version 7.0
<#
.SYNOPSIS
  capture.screen — capture a monitor / window / app / rectangle to an image artifact (Life Orchestrator, contract v0.1).
.DESCRIPTION
  Resolves a capture target to ONE rectangle in virtual-desktop pixel coordinates, then copies that
  rectangle of the screen (GDI CopyFromScreen) to a PNG (or JPG) artifact. Targets:
    -Target monitor  -Monitor <index|all|primary>            (default: primary)
    -Target window   -Hwnd|-ProcessId|-Title <glob>          (window's DWM frame; GetWindowRect fallback)
    -Target app      -App <process-name glob>                 (process main window)
    -Target region   -X -Y -Width -Height                     (explicit virtual-desktop rectangle)
  -Target is inferred from the supplied locator when omitted. Read-only: no window activation/management
  and no synthetic input. Emits one lifeorch.skill.result/0.1 envelope on stdout and writes
  capture.<png|jpg> + capture.json + capture.md. Diagnostics go to stderr. Exits 0 whenever a valid
  envelope is produced.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target monitor -Monitor primary
  pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -App notepad
  pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target region -X 0 -Y 0 -Width 800 -Height 600 -Format jpg
#>
[CmdletBinding()]
param(
    [string]$Target,
    [string]$Monitor,
    [long]$Hwnd = 0,
    [int]$ProcessId = 0,
    [string]$Title,
    [string]$App,
    [int]$X = 0,
    [int]$Y = 0,
    [int]$Width = 0,
    [int]$Height = 0,
    [string]$Format = 'png',
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID = 'capture.screen'; $SKILL_VERSION = '0.1.0'; $CONTRACT = '0.1'
$RESULT_SCHEMA = 'lifeorch.skill.result/0.1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[capture.screen] $m") }
function Get-Sha256Hex([byte[]]$b) {
    $s = [System.Security.Cryptography.SHA256]::Create()
    try { ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() }
}

$status = 'ok'; $errorObj = $null; $result = $null; $inputsDigest = $null; $artifacts = @()
$warnings = New-Object System.Collections.Generic.List[string]
$invDir = Join-Path $ArtifactRoot $InvocationId
$validTargets = @('monitor','window','app','region')
$captureObj = $null; $windowObj = $null; $monitorObj = $null; $environment = $null
$imgPath = $null; $fmt = 'png'

try {
    # ---- merge -InputsJson (named params still win where the caller set them explicitly) ----
    $xProvided = $PSBoundParameters.ContainsKey('X')
    $yProvided = $PSBoundParameters.ContainsKey('Y')
    $wProvided = $PSBoundParameters.ContainsKey('Width')
    $hProvided = $PSBoundParameters.ContainsKey('Height')
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $p = $InputsJson | ConvertFrom-Json
        if ($null -ne $p) {
            $n = $p.PSObject.Properties.Name
            if ($n -contains 'target')  { $Target = [string]$p.target }
            if ($n -contains 'monitor') { $Monitor = [string]$p.monitor }
            if ($n -contains 'hwnd')    { $Hwnd = [long]$p.hwnd }
            if ($n -contains 'pid')     { $ProcessId = [int]$p.pid }
            if ($n -contains 'title')   { $Title = [string]$p.title }
            if ($n -contains 'app')     { $App = [string]$p.app }
            if ($n -contains 'x')       { $X = [int]$p.x; $xProvided = $true }
            if ($n -contains 'y')       { $Y = [int]$p.y; $yProvided = $true }
            if ($n -contains 'width')   { $Width = [int]$p.width; $wProvided = $true }
            if ($n -contains 'height')  { $Height = [int]$p.height; $hProvided = $true }
            if ($n -contains 'format')  { $Format = [string]$p.format }
        }
    }

    # ---- normalize format ----
    if (-not [string]::IsNullOrWhiteSpace($Format)) { $fmt = $Format.Trim().ToLowerInvariant() }
    if ($fmt -eq 'jpeg') { $fmt = 'jpg' }
    if ([string]::IsNullOrWhiteSpace($fmt)) { $fmt = 'png' }

    # ---- normalize / infer target mode ----
    $mode = ''
    if (-not [string]::IsNullOrWhiteSpace($Target)) { $mode = $Target.Trim().ToLowerInvariant() }
    $hasWindowLoc = ($Hwnd -ne 0) -or ($ProcessId -ne 0) -or (-not [string]::IsNullOrWhiteSpace($Title))
    $hasRegion = $xProvided -or $yProvided -or $wProvided -or $hProvided
    if ([string]::IsNullOrWhiteSpace($mode)) {
        if ($hasWindowLoc) { $mode = 'window' }
        elseif (-not [string]::IsNullOrWhiteSpace($App)) { $mode = 'app' }
        elseif ($hasRegion) { $mode = 'region' }
        else { $mode = 'monitor' }
    }

    $monSel = ''
    if (-not [string]::IsNullOrWhiteSpace($Monitor)) { $monSel = $Monitor.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($monSel)) { $monSel = 'primary' }

    $normInputs = [ordered]@{ target=$mode; monitor=$monSel; hwnd=$Hwnd; pid=$ProcessId; title=$Title; app=$App; x=$X; y=$Y; width=$Width; height=$Height; format=$fmt }
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes(($normInputs | ConvertTo-Json -Compress)))
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    if ($validTargets -notcontains $mode) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_target'; message="unknown target '$mode'; expected one of: $($validTargets -join ', ')"; retryable=$false }
    }
    elseif (@('png','jpg') -notcontains $fmt) {
        $status = 'error'; $errorObj = [ordered]@{ code='invalid_format'; message="unknown format '$fmt'; expected png or jpg"; retryable=$false }
    }
    else {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        if (-not ([System.Management.Automation.PSTypeName]'LoCapture.Native').Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;
namespace LoCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static class Native {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT r, int size);
    public static List<string> ListWindows() {
      var list = new List<string>();
      EnumWindows((h, l) => {
        if (!IsWindowVisible(h)) return true;
        int len = GetWindowTextLength(h);
        if (len <= 0) return true;
        var sb = new StringBuilder(len + 2);
        GetWindowText(h, sb, sb.Capacity);
        uint pid; GetWindowThreadProcessId(h, out pid);
        list.Add(h.ToInt64().ToString() + "" + pid.ToString() + "" + sb.ToString());
        return true;
      }, IntPtr.Zero);
      return list;
    }
  }
}
'@
        }

        # ---- DPI awareness: prefer Per-Monitor-V2 (-4); fall back; ignore if already set ----
        try { [void][LoCapture.Native]::SetProcessDpiAwarenessContext([IntPtr](-4)) }
        catch { try { [void][LoCapture.Native]::SetProcessDPIAware() } catch { } }

        # ---- enumerate monitors (always reported) ----
        $screens = [System.Windows.Forms.Screen]::AllScreens
        $monList = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $screens.Length; $i++) {
            $b = $screens[$i].Bounds
            $monList.Add([pscustomobject]@{ index=$i; primary=[bool]$screens[$i].Primary; device_name=[string]$screens[$i].DeviceName; x=[int]$b.X; y=[int]$b.Y; width=[int]$b.Width; height=[int]$b.Height })
        }
        $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $virtualScreen = [ordered]@{ x=[int]$vs.X; y=[int]$vs.Y; width=[int]$vs.Width; height=[int]$vs.Height }
        $environment = [ordered]@{ virtual_screen=$virtualScreen; monitors=$monList.ToArray() }

        function Resolve-WindowRect([long]$h) {
            $hp = [IntPtr]$h
            if (-not [LoCapture.Native]::IsWindow($hp)) { return @{ ok=$false; code='target_not_found'; message="hwnd $h is not a valid window"; retryable=$true } }
            $pidOut = 0; [void][LoCapture.Native]::GetWindowThreadProcessId($hp, [ref]$pidOut)
            $ttl = ''
            $tl = [LoCapture.Native]::GetWindowTextLength($hp)
            if ($tl -gt 0) { $sb = New-Object System.Text.StringBuilder ($tl + 2); [void][LoCapture.Native]::GetWindowText($hp, $sb, $sb.Capacity); $ttl = $sb.ToString() }
            $pname = ''; try { $gp = Get-Process -Id ([int]$pidOut) -ErrorAction SilentlyContinue; if ($gp) { $pname = [string]$gp.ProcessName } } catch { }
            if ([bool][LoCapture.Native]::IsIconic($hp)) { return @{ ok=$false; code='window_minimized'; message='target window is minimized; restore it before capture'; retryable=$true; pid=[int]$pidOut; title=$ttl; process_name=$pname } }
            $r = New-Object LoCapture.RECT
            $src = 'dwm'
            $hr = [LoCapture.Native]::DwmGetWindowAttribute($hp, 9, [ref]$r, 16)   # DWMWA_EXTENDED_FRAME_BOUNDS
            if ($hr -ne 0 -or ($r.Right - $r.Left) -le 0 -or ($r.Bottom - $r.Top) -le 0) {
                $src = 'getwindowrect'
                [void][LoCapture.Native]::GetWindowRect($hp, [ref]$r)
            }
            $rw = [int]($r.Right - $r.Left); $rh = [int]($r.Bottom - $r.Top)
            if ($rw -le 0 -or $rh -le 0) { return @{ ok=$false; code='capture_failed'; message='window has a non-positive on-screen size'; retryable=$true; pid=[int]$pidOut; title=$ttl; process_name=$pname } }
            return @{ ok=$true; rect=[ordered]@{ x=[int]$r.Left; y=[int]$r.Top; width=$rw; height=$rh }; source=$src; pid=[int]$pidOut; title=$ttl; process_name=$pname }
        }

        $rect = $null

        switch ($mode) {
            'monitor' {
                if ($monSel -eq 'all') {
                    $rect = [ordered]@{ x=$virtualScreen.x; y=$virtualScreen.y; width=$virtualScreen.width; height=$virtualScreen.height }
                    $monitorObj = [ordered]@{ index=-1; selector='all'; primary=$false; device_name='(virtual)'; bounds=$rect }
                }
                elseif ($monSel -eq 'primary') {
                    $pi = 0; for ($i = 0; $i -lt $monList.Count; $i++) { if ($monList[$i].primary) { $pi = $i; break } }
                    $m = $monList[$pi]
                    $rect = [ordered]@{ x=$m.x; y=$m.y; width=$m.width; height=$m.height }
                    $monitorObj = [ordered]@{ index=$m.index; selector='primary'; primary=$true; device_name=$m.device_name; bounds=$rect }
                }
                else {
                    $idx = $monSel -as [int]
                    if ($null -eq $idx -or $idx -lt 0 -or $idx -ge $monList.Count) {
                        $status = 'error'; $errorObj = [ordered]@{ code='monitor_not_found'; message="monitor '$monSel' out of range (0..$($monList.Count - 1)); use an index, 'all', or 'primary'"; retryable=$false }
                    }
                    else {
                        $m = $monList[$idx]
                        $rect = [ordered]@{ x=$m.x; y=$m.y; width=$m.width; height=$m.height }
                        $monitorObj = [ordered]@{ index=$m.index; selector=$monSel; primary=$m.primary; device_name=$m.device_name; bounds=$rect }
                    }
                }
            }
            'region' {
                if (($Width -le 0) -or ($Height -le 0)) {
                    $status = 'error'; $errorObj = [ordered]@{ code='invalid_region'; message="region requires positive width and height (got width=$Width height=$Height)"; retryable=$false }
                }
                else {
                    $rect = [ordered]@{ x=[int]$X; y=[int]$Y; width=[int]$Width; height=[int]$Height }
                }
            }
            'window' {
                if (-not $hasWindowLoc) {
                    $status = 'error'; $errorObj = [ordered]@{ code='no_target'; message='window target requires a locator: -Hwnd, -ProcessId, or -Title'; retryable=$false }
                }
                else {
                    $rhwnd = 0
                    if ($Hwnd -ne 0) { $rhwnd = $Hwnd }
                    elseif ($ProcessId -ne 0) {
                        $pp = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
                        if ($null -eq $pp) { $status = 'error'; $errorObj = [ordered]@{ code='target_not_found'; message="no process with pid $ProcessId"; retryable=$true } }
                        elseif ([long]$pp.MainWindowHandle -eq 0) { $status = 'error'; $errorObj = [ordered]@{ code='target_not_found'; message="pid $ProcessId has no main window"; retryable=$true } }
                        else { $rhwnd = [long]$pp.MainWindowHandle }
                    }
                    else {
                        $wins = [LoCapture.Native]::ListWindows()
                        $matched = New-Object System.Collections.Generic.List[object]
                        foreach ($w in $wins) {
                            $parts = ([string]$w).Split([char]1)
                            if ($parts.Length -ge 3) {
                                $wt = $parts[2]
                                if ($wt -like $Title) { $matched.Add([pscustomobject]@{ hwnd=[long]$parts[0]; pid=[int]$parts[1]; title=$wt }) }
                            }
                        }
                        if ($matched.Count -eq 0) { $status = 'error'; $errorObj = [ordered]@{ code='target_not_found'; message="no visible top-level window with title like '$Title'"; retryable=$true } }
                        else {
                            $rhwnd = $matched[0].hwnd
                            if ($matched.Count -gt 1) { $warnings.Add("$($matched.Count) windows matched title '$Title'; captured the first (hwnd=$rhwnd)") }
                        }
                    }
                    if ($status -eq 'ok' -and $rhwnd -ne 0) {
                        $wr = Resolve-WindowRect $rhwnd
                        if ($wr.ok) {
                            $rect = $wr.rect
                            $windowObj = [ordered]@{ hwnd=[long]$rhwnd; pid=$wr.pid; process_name=$wr.process_name; title=$wr.title; minimized=$false; bounds_source=$wr.source }
                        }
                        else {
                            $status = 'error'; $errorObj = [ordered]@{ code=$wr.code; message=$wr.message; retryable=[bool]$wr.retryable }
                            $windowObj = [ordered]@{ hwnd=[long]$rhwnd; pid=$(if ($wr.ContainsKey('pid')) { $wr.pid } else { 0 }); process_name=$(if ($wr.ContainsKey('process_name')) { $wr.process_name } else { '' }); title=$(if ($wr.ContainsKey('title')) { $wr.title } else { '' }); minimized=($wr.code -eq 'window_minimized'); bounds_source=$null }
                        }
                    }
                }
            }
            'app' {
                if ([string]::IsNullOrWhiteSpace($App)) {
                    $status = 'error'; $errorObj = [ordered]@{ code='no_target'; message='app target requires -App <process-name glob>'; retryable=$false }
                }
                else {
                    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { ([long]$_.MainWindowHandle -ne 0) -and (($_.ProcessName -like $App) -or ("$($_.ProcessName).exe" -like $App)) } | Sort-Object Id)
                    if ($procs.Count -eq 0) { $status = 'error'; $errorObj = [ordered]@{ code='target_not_found'; message="no running application with a main window matching '$App'"; retryable=$true } }
                    else {
                        $chosen = $procs[0]
                        if ($procs.Count -gt 1) { $warnings.Add("$($procs.Count) processes matched app '$App'; captured the lowest pid ($($chosen.Id) $($chosen.ProcessName))") }
                        $wr = Resolve-WindowRect ([long]$chosen.MainWindowHandle)
                        if ($wr.ok) {
                            $rect = $wr.rect
                            $windowObj = [ordered]@{ hwnd=[long]$chosen.MainWindowHandle; pid=$wr.pid; process_name=$wr.process_name; title=$wr.title; minimized=$false; bounds_source=$wr.source }
                        }
                        else {
                            $status = 'error'; $errorObj = [ordered]@{ code=$wr.code; message=$wr.message; retryable=[bool]$wr.retryable }
                            $windowObj = [ordered]@{ hwnd=[long]$chosen.MainWindowHandle; pid=[int]$chosen.Id; process_name=[string]$chosen.ProcessName; title=$(if ($wr.ContainsKey('title')) { $wr.title } else { '' }); minimized=($wr.code -eq 'window_minimized'); bounds_source=$null }
                        }
                    }
                }
            }
        }

        # ---- capture (only if a rectangle was resolved without error) ----
        if ($status -eq 'ok' -and $null -ne $rect) {
            $imgPath = Join-Path $invDir ("capture." + $fmt)
            $bmp = $null; $g = $null
            try {
                $bmp = New-Object System.Drawing.Bitmap([int]$rect.width, [int]$rect.height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.CopyFromScreen([int]$rect.x, [int]$rect.y, 0, 0, (New-Object System.Drawing.Size([int]$rect.width, [int]$rect.height)), [System.Drawing.CopyPixelOperation]::SourceCopy)
                $g.Dispose(); $g = $null
                if ($fmt -eq 'png') {
                    $bmp.Save($imgPath, [System.Drawing.Imaging.ImageFormat]::Png)
                }
                else {
                    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
                    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
                    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]90)
                    $bmp.Save($imgPath, $codec, $ep)
                }
                $imgW = [int]$bmp.Width; $imgH = [int]$bmp.Height
                $bmp.Dispose(); $bmp = $null
                $imgBytes = [System.IO.File]::ReadAllBytes($imgPath)
                $captureObj = [ordered]@{
                    rectangle = [ordered]@{ x=[int]$rect.x; y=[int]$rect.y; width=[int]$rect.width; height=[int]$rect.height }
                    format = $fmt; image_width = $imgW; image_height = $imgH
                    path = (Resolve-Path -LiteralPath $imgPath).Path; bytes = $imgBytes.Length; sha256 = (Get-Sha256Hex $imgBytes)
                }
                Write-Diag "mode=$mode rect=($($rect.x),$($rect.y),$($rect.width),$($rect.height)) -> $imgPath ($($imgBytes.Length) bytes)"
            }
            catch {
                $status = 'error'; $errorObj = [ordered]@{ code='capture_failed'; message="screen copy/save failed: $($_.Exception.Message)"; retryable=$true }
                Write-Diag "capture_failed: $($_.Exception.Message)"
            }
            finally {
                if ($null -ne $g) { try { $g.Dispose() } catch { } }
                if ($null -ne $bmp) { try { $bmp.Dispose() } catch { } }
            }
        }

        $result = [ordered]@{
            mode = $mode
            requested = [ordered]@{ target=$mode; monitor=$monSel; hwnd=$Hwnd; pid=$ProcessId; title=$Title; app=$App; x=$X; y=$Y; width=$Width; height=$Height; format=$fmt }
            capture = $captureObj
            window = $windowObj
            monitor = $monitorObj
            environment = $environment
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
        $captureJson = [ordered]@{ schema='lifeorch.capture/0.1'; invocation_id=$InvocationId; generated_at_utc=$startedAt.ToString('o'); result=$result }
        $cjPath = Join-Path $invDir 'capture.json'
        [System.IO.File]::WriteAllText($cjPath, ($captureJson | ConvertTo-Json -Depth 12), $utf8)

        $mb = [System.Text.StringBuilder]::new()
        [void]$mb.AppendLine("# capture.screen — mode=$($result.mode)  captured=$([bool]($null -ne $result.capture))")
        $rq = $result.requested
        [void]$mb.AppendLine("requested: target=$($rq.target) monitor=$($rq.monitor) hwnd=$($rq.hwnd) pid=$($rq.pid) title='$($rq.title)' app='$($rq.app)' region=($($rq.x),$($rq.y),$($rq.width),$($rq.height)) format=$($rq.format)")
        if ($null -ne $result.capture) {
            $c = $result.capture
            [void]$mb.AppendLine("rectangle: ($($c.rectangle.x),$($c.rectangle.y)) $($c.rectangle.width)x$($c.rectangle.height)  image=$($c.image_width)x$($c.image_height) $($c.format)  bytes=$($c.bytes)")
            [void]$mb.AppendLine("image: $($c.path)")
        }
        if ($null -ne $result.window) {
            $wo = $result.window
            [void]$mb.AppendLine("window: hwnd=$($wo.hwnd) pid=$($wo.pid) `"$($wo.title)`" ($($wo.process_name)) minimized=$($wo.minimized) bounds_source=$($wo.bounds_source)")
        }
        if ($null -ne $result.monitor) {
            $mo = $result.monitor
            [void]$mb.AppendLine("monitor: index=$($mo.index) selector=$($mo.selector) primary=$($mo.primary) device=$($mo.device_name)")
        }
        if ($null -ne $result.environment) {
            $ev = $result.environment
            [void]$mb.AppendLine("virtual_screen: ($($ev.virtual_screen.x),$($ev.virtual_screen.y)) $($ev.virtual_screen.width)x$($ev.virtual_screen.height)  monitors=$(@($ev.monitors).Count)")
            foreach ($mm in @($ev.monitors)) { [void]$mb.AppendLine("  - [$($mm.index)] $($mm.device_name) ($($mm.x),$($mm.y)) $($mm.width)x$($mm.height) primary=$($mm.primary)") }
        }
        if ($null -ne $errorObj) { [void]$mb.AppendLine("error: $($errorObj.code) — $($errorObj.message)") }
        if ($warnings.Count -gt 0) { [void]$mb.AppendLine("warnings: $((@($warnings.ToArray())) -join '; ')") }
        $cmPath = Join-Path $invDir 'capture.md'
        [System.IO.File]::WriteAllText($cmPath, $mb.ToString(), $utf8)

        $artList = New-Object System.Collections.Generic.List[object]
        if ($null -ne $result.capture -and $null -ne $imgPath -and (Test-Path -LiteralPath $imgPath)) {
            $artList.Add([pscustomobject]@{ p=$imgPath; k=$(if ($fmt -eq 'png') { 'png' } else { 'jpeg' }) })
        }
        $artList.Add([pscustomobject]@{ p=$cmPath; k='markdown' })
        $artList.Add([pscustomobject]@{ p=$cjPath; k='json' })
        foreach ($a in $artList.ToArray()) {
            $b = [System.IO.File]::ReadAllBytes($a.p)
            $artifacts += ,([ordered]@{ path=(Resolve-Path -LiteralPath $a.p).Path; kind=$a.k; bytes=$b.Length; sha256=(Get-Sha256Hex $b) })
        }
    }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[capture.screen] invocation $InvocationId status=$status warnings=$($warnings.Count)`n", $utf8)
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
