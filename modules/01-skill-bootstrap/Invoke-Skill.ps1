#requires -Version 7.0
<#
.SYNOPSIS
  Invoke-Skill.ps1 — generic invocation wrapper for Proteus skills (contract v0.1).
.DESCRIPTION
  validate manifest -> run entrypoint in an isolated pwsh process -> validate result envelope.
  Emits a single lifeorch.skill.invocation_report/0.1 JSON object to stdout (or, with
  -PassThruEnvelope, the skill's raw result envelope). Exits 0 only when the manifest is
  valid, the skill exited 0, and the emitted envelope validates; otherwise exits 1.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-Skill.ps1 -SkillDir .\skills\ref.echo -InputsJson '{"message":"hi","repeat":2}'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SkillDir,
    [string]$InputsJson,
    [string]$ArtifactRoot,
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [switch]$PassThruEnvelope
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Import-Module (Join-Path $PSScriptRoot 'lib/SkillContract.psm1') -Force

$REPORT_SCHEMA = 'lifeorch.skill.invocation_report/0.1'
function Emit([object]$obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Depth 20)) }

$manifestPath  = Join-Path $SkillDir 'skill.json'
$manifest      = $null
$manifestValid = $false
$manifestErrors = @()

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $manifestErrors = @("skill.json not found in $SkillDir")
}
else {
    try { $manifest = (Get-Content -LiteralPath $manifestPath -Raw) | ConvertFrom-Json }
    catch { $manifest = $null; $manifestErrors = @("skill.json invalid JSON: $($_.Exception.Message)") }
    if ($null -ne $manifest) {
        $mv = Test-SkillManifest -Manifest $manifest
        $manifestValid  = [bool]$mv.valid
        $manifestErrors = $mv.errors
    }
}

$skillId = $null
if ($null -ne $manifest -and ($manifest.PSObject.Properties.Name -contains 'skill_id')) { $skillId = [string]$manifest.skill_id }

if (-not $manifestValid) {
    Emit ([ordered]@{
        schema = $REPORT_SCHEMA; skill_dir = $SkillDir; skill_id = $skillId
        manifest_valid = $false; manifest_errors = $manifestErrors
        invoked = $false; exit_code = $null
        envelope_valid = $false; envelope_errors = @('skill not invoked: manifest invalid')
        envelope = $null; stderr_tail = $null
    })
    exit 1
}

$entry = Join-Path $SkillDir ([string]$manifest.invocation.entrypoint)
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) {
    Emit ([ordered]@{
        schema = $REPORT_SCHEMA; skill_dir = $SkillDir; skill_id = $skillId
        manifest_valid = $true; manifest_errors = @()
        invoked = $false; exit_code = $null
        envelope_valid = $false; envelope_errors = @("entrypoint not found: $entry")
        envelope = $null; stderr_tail = $null
    })
    exit 1
}

$callArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry)
if (-not [string]::IsNullOrWhiteSpace($InputsJson))   { $callArgs += @('-InputsJson', $InputsJson) }
if (-not [string]::IsNullOrWhiteSpace($ArtifactRoot)) { $callArgs += @('-ArtifactRoot', $ArtifactRoot) }

$tmpErr = New-TemporaryFile
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$stdoutLines = & $PwshPath @callArgs 2> $tmpErr.FullName
$exit = $LASTEXITCODE
$ErrorActionPreference = $prevEAP

$stdoutText = ($stdoutLines | Out-String)
$stderrText = ''
try { $stderrText = Get-Content -LiteralPath $tmpErr.FullName -Raw -ErrorAction SilentlyContinue } catch { }
Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue

$envelope       = $null
$envelopeValid  = $false
$envelopeErrors = @()
$trimmed = ([string]$stdoutText).Trim()
if ([string]::IsNullOrWhiteSpace($trimmed)) {
    $envelopeErrors = @('skill produced no stdout envelope')
}
else {
    try { $envelope = $trimmed | ConvertFrom-Json }
    catch { $envelope = $null; $envelopeErrors = @("stdout is not valid JSON: $($_.Exception.Message)") }
    if ($null -ne $envelope) {
        $ev = Test-SkillResultEnvelope -Envelope $envelope
        $envelopeValid  = [bool]$ev.valid
        $envelopeErrors = $ev.errors
    }
}

if ($PassThruEnvelope -and $null -ne $envelope) {
    [Console]::Out.WriteLine($trimmed)
}
else {
    $stderrTail = ''
    if ($stderrText) { $stderrTail = if ($stderrText.Length -gt 800) { $stderrText.Substring($stderrText.Length - 800) } else { $stderrText } }
    Emit ([ordered]@{
        schema = $REPORT_SCHEMA; skill_dir = $SkillDir; skill_id = $skillId
        manifest_valid = $true; manifest_errors = @()
        invoked = $true; exit_code = $exit
        envelope_valid = $envelopeValid; envelope_errors = $envelopeErrors
        envelope = $envelope; stderr_tail = $stderrTail
    })
}

if ($manifestValid -and $envelopeValid -and $exit -eq 0) { exit 0 } else { exit 1 }
