#requires -Version 7.0
<#
.SYNOPSIS
  Test-only probe window for capture.screen. Creates a self-contained, brightly-filled WinForms window on
  an STA runspace with a unique title so a window/app capture can be located and its geometry/metadata
  verified. NOT a skill; used only by Invoke-CaptureScreenTests.ps1. Auto-closes after -Seconds. Writes
  ready.txt (window shown) and closed.txt (form closed) into -SignalDir.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$SignalDir,
    [int]$Width = 420,
    [int]$Height = 320,
    [int]$Seconds = 90
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $SignalDir -Force | Out-Null

$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = 'STA'
$rs.ThreadOptions = 'ReuseThread'
$rs.Open()
$rs.SessionStateProxy.SetVariable('Token', $Token)
$rs.SessionStateProxy.SetVariable('SignalDir', $SignalDir)
$rs.SessionStateProxy.SetVariable('WinW', $Width)
$rs.SessionStateProxy.SetVariable('WinH', $Height)
$rs.SessionStateProxy.SetVariable('Seconds', $Seconds)

$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript({
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $enc = [System.Text.UTF8Encoding]::new($false)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "LO Capture Probe $Token"
    $form.Width = [int]$WinW; $form.Height = [int]$WinH
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(32, 160, 220)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "capture probe $Token"
    $lbl.Dock = 'Fill'
    $lbl.TextAlign = 'MiddleCenter'
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::White
    $form.Controls.Add($lbl)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [int]([Math]::Max(1, $Seconds) * 1000)
    $timer.Add_Tick({ $timer.Stop(); $form.Close() })
    $timer.Start()

    $form.Add_Shown({ try { $form.Activate() } catch { }; try { [System.IO.File]::WriteAllText((Join-Path $SignalDir 'ready.txt'), [string]$form.Text, $enc) } catch { } })
    $form.Add_FormClosed({ try { [System.IO.File]::WriteAllText((Join-Path $SignalDir 'closed.txt'), 'closed', $enc) } catch { } })

    [System.Windows.Forms.Application]::Run($form)
})
$ps.Invoke() | Out-Null
$ps.Dispose(); $rs.Dispose()
