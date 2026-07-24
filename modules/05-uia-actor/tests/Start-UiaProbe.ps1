#requires -Version 7.0
<#
.SYNOPSIS
  Test-only probe window for uia.actor. Creates a self-contained WinForms window on an STA runspace with a
  TextBox (probeEdit / Edit), a CheckBox (probeCheck / CheckBox) and a Button (probeButton / Button) so the
  actor's real Value/Toggle/Invoke patterns can be exercised and self-verified. NOT a skill; used only by
  Invoke-UiaActorTests.ps1. Auto-closes after -Seconds. Writes marker files into -SignalDir:
  ready.txt (window shown), clicked.txt (button invoked, contains the TextBox text), closed.txt (form closed).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$SignalDir,
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
$rs.SessionStateProxy.SetVariable('Seconds', $Seconds)

$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript({
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $enc = [System.Text.UTF8Encoding]::new($false)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "LO UIA Probe $Token"
    $form.Width = 360; $form.Height = 200
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true

    $edit = New-Object System.Windows.Forms.TextBox
    $edit.Name = 'probeEdit'; $edit.AccessibleName = 'probeEdit'
    $edit.Left = 20; $edit.Top = 20; $edit.Width = 300
    $form.Controls.Add($edit)

    $check = New-Object System.Windows.Forms.CheckBox
    $check.Name = 'probeCheck'; $check.AccessibleName = 'probeCheck'; $check.Text = 'probeCheck'
    $check.Left = 20; $check.Top = 60; $check.Width = 300
    $form.Controls.Add($check)

    $button = New-Object System.Windows.Forms.Button
    $button.Name = 'probeButton'; $button.AccessibleName = 'probeButton'; $button.Text = 'probeButton'
    $button.Left = 20; $button.Top = 100; $button.Width = 300
    $button.Add_Click({
        try { [System.IO.File]::WriteAllText((Join-Path $SignalDir 'clicked.txt'), [string]$edit.Text, $enc) } catch { }
        $form.Close()
    })
    $form.Controls.Add($button)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [int]([Math]::Max(1, $Seconds) * 1000)
    $timer.Add_Tick({ $timer.Stop(); $form.Close() })
    $timer.Start()

    $form.Add_Shown({ try { [System.IO.File]::WriteAllText((Join-Path $SignalDir 'ready.txt'), [string]$form.Text, $enc) } catch { } })
    $form.Add_FormClosed({ try { [System.IO.File]::WriteAllText((Join-Path $SignalDir 'closed.txt'), 'closed', $enc) } catch { } })

    [System.Windows.Forms.Application]::Run($form)
})
$ps.Invoke() | Out-Null
$ps.Dispose(); $rs.Dispose()
