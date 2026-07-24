#requires -Version 7.0
<#
.SYNOPSIS
  ref.echo — trivial reference skill for Project Proteus (skill contract v0.1).
.DESCRIPTION
  Echoes a message N times and emits a single schema-valid proteus.skill.result/0.1
  envelope on stdout (and to <ArtifactRoot>/<InvocationId>/result.json). Deterministic.
  Only the JSON envelope is written to stdout; all human/diagnostic logging goes to stderr.
  Exits 0 whenever a valid envelope is produced (including logical status=error), per contract.
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-RefEcho.ps1 -Message "hello" -Repeat 3
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-RefEcho.ps1 -InputsJson '{"message":"hi","repeat":2}'
#>
[CmdletBinding()]
param(
    [string]$Message = 'ping',
    [int]$Repeat = 1,
    [string]$InputsJson,
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'runtime/artifacts'),
    [string]$InvocationId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SKILL_ID       = 'ref.echo'
$SKILL_VERSION  = '0.1.0'
$CONTRACT       = '0.1'
$RESULT_SCHEMA  = 'proteus.skill.result/0.1'

$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[ref.echo] $m") }
function Get-Sha256Hex([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$status       = 'ok'
$errorObj     = $null
$result       = $null
$inputsDigest = $null
$artifacts    = @()
$warnings     = New-Object System.Collections.Generic.List[string]
$invDir       = Join-Path $ArtifactRoot $InvocationId

try {
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        $parsed = $InputsJson | ConvertFrom-Json
        if ($null -ne $parsed) {
            if ($parsed.PSObject.Properties.Name -contains 'message') { $Message = [string]$parsed.message }
            if ($parsed.PSObject.Properties.Name -contains 'repeat')  { $Repeat  = [int]$parsed.repeat }
        }
    }

    $normInputs   = [ordered]@{ message = $Message; repeat = $Repeat }
    $normJson     = ($normInputs | ConvertTo-Json -Compress)
    $inputsDigest = 'sha256:' + (Get-Sha256Hex $utf8.GetBytes($normJson))

    New-Item -ItemType Directory -Path $invDir -Force | Out-Null

    if ($Repeat -lt 1) {
        $status   = 'error'
        $errorObj = [ordered]@{ code = 'invalid_input'; message = "repeat must be >= 1 (got $Repeat)"; retryable = $false }
        Write-Diag $errorObj.message
    }
    else {
        $lines  = for ($i = 0; $i -lt $Repeat; $i++) { $Message }
        $echoed = ($lines -join "`n")

        $echoPath = Join-Path $invDir 'echo.txt'
        [System.IO.File]::WriteAllText($echoPath, $echoed, $utf8)
        $echoBytes = [System.IO.File]::ReadAllBytes($echoPath)
        $artifacts = @([ordered]@{
            path   = (Resolve-Path -LiteralPath $echoPath).Path
            kind   = 'text'
            bytes  = $echoBytes.Length
            sha256 = (Get-Sha256Hex $echoBytes)
        })

        $result = [ordered]@{
            echoed       = $echoed
            message      = $Message
            repeat       = $Repeat
            host         = $env:COMPUTERNAME
            user         = $env:USERNAME
            pwsh_version = "$($PSVersionTable.PSVersion)"
            pid          = $PID
        }
        Write-Diag "echoed '$Message' x$Repeat -> $echoPath"
    }
}
catch {
    $status   = 'error'
    $errorObj = [ordered]@{ code = 'unhandled_exception'; message = "$($_.Exception.Message)"; retryable = $false }
    Write-Diag "ERROR: $($_.Exception.Message)"
}

# Best-effort stderr diagnostic artifact.
try {
    if (-not (Test-Path -LiteralPath $invDir)) { New-Item -ItemType Directory -Path $invDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $invDir 'stderr.txt'), "[ref.echo] invocation $InvocationId status=$status`n", $utf8)
} catch { }

$sw.Stop()
$finishedAt = [DateTime]::UtcNow

$envelope = [ordered]@{
    schema           = $RESULT_SCHEMA
    skill_id         = $SKILL_ID
    skill_version    = $SKILL_VERSION
    contract_version = $CONTRACT
    invocation_id    = $InvocationId
    status           = $status
    started_at_utc   = $startedAt.ToString('o')
    finished_at_utc  = $finishedAt.ToString('o')
    duration_ms      = [int]$sw.Elapsed.TotalMilliseconds
    inputs_digest    = $inputsDigest
    result           = $result
    confidence       = $null
    artifacts        = $artifacts
    model_provenance = @()
    diagnostics      = [ordered]@{ log = 'stderr.txt'; artifact_dir = $invDir }
    warnings         = $warnings.ToArray()
    error            = $errorObj
}

$json = $envelope | ConvertTo-Json -Depth 12
try { [System.IO.File]::WriteAllText((Join-Path $invDir 'result.json'), $json, $utf8) } catch { }
[Console]::Out.WriteLine($json)
exit 0
