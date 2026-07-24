#requires -Version 7.0
# SkillContract.psm1 — validators for the Proteus skill contract (v0.1).
# Provides Test-SkillManifest and Test-SkillResultEnvelope. No external dependencies.
Set-StrictMode -Version Latest

$script:MANIFEST_SCHEMA = 'proteus.skill.manifest/0.1'
$script:RESULT_SCHEMA   = 'proteus.skill.result/0.1'

function Test-SkillManifest {
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object')] [object]$Manifest,
        [Parameter(Mandatory, ParameterSetName = 'Path')]   [string]$Path
    )
    $errors = New-Object System.Collections.Generic.List[string]
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $errors.Add("manifest file not found: $Path")
            return [ordered]@{ valid = $false; errors = $errors.ToArray() }
        }
        try { $Manifest = (Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json }
        catch {
            $errors.Add("manifest is not valid JSON: $($_.Exception.Message)")
            return [ordered]@{ valid = $false; errors = $errors.ToArray() }
        }
    }

    $required = @('schema','skill_id','name','version','contract_version','purpose','determinism',
        'invocation','inputs','outputs','requirements','artifacts','timeout','batch','streaming',
        'parallel_safe','example_invocation_file','example_result_file')
    $names = @()
    if ($null -ne $Manifest -and $Manifest.PSObject) { $names = @($Manifest.PSObject.Properties.Name) }
    foreach ($f in $required) { if ($names -notcontains $f) { $errors.Add("missing required field: $f") } }

    if ($names -contains 'schema' -and $Manifest.schema -ne $script:MANIFEST_SCHEMA) {
        $errors.Add("schema must be '$($script:MANIFEST_SCHEMA)' (got '$($Manifest.schema)')")
    }
    if ($names -contains 'skill_id' -and $Manifest.skill_id -notmatch '^[a-z0-9]+(\.[a-z0-9]+)*$') {
        $errors.Add("skill_id must be dotted lowercase (got '$($Manifest.skill_id)')")
    }
    if ($names -contains 'version' -and $Manifest.version -notmatch '^\d+\.\d+\.\d+$') {
        $errors.Add("version must be semver x.y.z (got '$($Manifest.version)')")
    }
    if ($names -contains 'determinism' -and @('deterministic','stochastic','mixed') -notcontains $Manifest.determinism) {
        $errors.Add("determinism must be deterministic|stochastic|mixed (got '$($Manifest.determinism)')")
    }
    if ($names -contains 'invocation' -and $null -ne $Manifest.invocation) {
        foreach ($k in @('method','entrypoint')) {
            if (-not ($Manifest.invocation.PSObject.Properties.Name -contains $k)) { $errors.Add("invocation.$k missing") }
        }
    }
    return [ordered]@{ valid = ($errors.Count -eq 0); errors = $errors.ToArray() }
}

function Test-SkillResultEnvelope {
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object')] [object]$Envelope,
        [Parameter(Mandatory, ParameterSetName = 'Json')]   [string]$Json
    )
    $errors = New-Object System.Collections.Generic.List[string]
    if ($PSCmdlet.ParameterSetName -eq 'Json') {
        try { $Envelope = $Json | ConvertFrom-Json }
        catch {
            $errors.Add("envelope is not valid JSON: $($_.Exception.Message)")
            return [ordered]@{ valid = $false; errors = $errors.ToArray() }
        }
    }

    $required = @('schema','skill_id','skill_version','contract_version','invocation_id','status',
        'started_at_utc','finished_at_utc','duration_ms','inputs_digest','result','confidence',
        'artifacts','model_provenance','diagnostics','warnings','error')
    $names = @()
    if ($null -ne $Envelope -and $Envelope.PSObject) { $names = @($Envelope.PSObject.Properties.Name) }
    foreach ($f in $required) { if ($names -notcontains $f) { $errors.Add("missing required field: $f") } }

    if ($names -contains 'schema' -and $Envelope.schema -ne $script:RESULT_SCHEMA) {
        $errors.Add("schema must be '$($script:RESULT_SCHEMA)' (got '$($Envelope.schema)')")
    }
    if ($names -contains 'status' -and @('ok','partial','error','cancelled') -notcontains $Envelope.status) {
        $errors.Add("status must be ok|partial|error|cancelled (got '$($Envelope.status)')")
    }
    foreach ($ts in @('started_at_utc','finished_at_utc')) {
        if ($names -contains $ts) {
            $dt = [datetime]::MinValue
            $ok = [datetime]::TryParse([string]$Envelope.$ts, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$dt)
            if (-not $ok) { $errors.Add("$ts is not a parseable ISO-8601 timestamp") }
        }
    }
    if ($names -contains 'duration_ms') {
        $d = $Envelope.duration_ms
        if (-not ($d -is [int] -or $d -is [long] -or $d -is [double]) -or [double]$d -lt 0) {
            $errors.Add("duration_ms must be a non-negative number")
        }
    }
    if ($names -contains 'inputs_digest' -and [string]$Envelope.inputs_digest -notmatch '^sha256:[0-9a-f]{64}$') {
        $errors.Add("inputs_digest must be 'sha256:<64 lowercase hex>'")
    }
    if ($names -contains 'confidence' -and $null -ne $Envelope.confidence) {
        $c = [double]$Envelope.confidence
        if ($c -lt 0 -or $c -gt 1) { $errors.Add("confidence must be null or within 0..1") }
    }
    if ($names -contains 'artifacts' -and $null -ne $Envelope.artifacts) {
        $i = 0
        foreach ($a in @($Envelope.artifacts)) {
            foreach ($k in @('path','kind','bytes','sha256')) {
                if (-not ($a.PSObject.Properties.Name -contains $k)) { $errors.Add("artifacts[$i].$k missing") }
            }
            $i++
        }
    }
    if (($names -contains 'status') -and ($Envelope.status -eq 'error')) {
        if ($null -eq $Envelope.error) { $errors.Add("status=error requires a non-null error object") }
        else {
            foreach ($k in @('code','message','retryable')) {
                if (-not ($Envelope.error.PSObject.Properties.Name -contains $k)) { $errors.Add("error.$k missing") }
            }
        }
    }
    return [ordered]@{ valid = ($errors.Count -eq 0); errors = $errors.ToArray() }
}

Export-ModuleMember -Function Test-SkillManifest, Test-SkillResultEnvelope
