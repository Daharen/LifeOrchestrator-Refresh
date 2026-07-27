<#
    mock-invoke-skill.ps1 - a stand-in for modules/01-skill-bootstrap/Invoke-Skill.ps1 used ONLY by
    the Module Launcher cloud pre-ship gate (a real Module run may be GPU-bound / Windows-only and
    cannot run on the Linux cloud box). It accepts the same -SkillDir / -InputsJson / -ArtifactRoot /
    -PwshPath the launcher passes and emits a canned but shape-accurate lifeorch.skill.invocation_report/0.1
    (nesting a lifeorch.skill.result/0.1 envelope) to stdout, so the launcher core's
    spawn -> parse -> format path is exercised for real.

    Scenario is selected from the SkillDir folder leaf or the InputsJson text:
      (default)              -> a clean run: manifest valid, invoked, a valid ok envelope
      leaf ~ badmanifest     -> manifest invalid: not invoked, no envelope (wrapper exit 1)
      ERRORME / leaf errskill-> invoked, but the skill returned status=error (a valid envelope)
      BADENV  / leaf badenv  -> invoked, but the skill produced no valid envelope (wrapper exit 1)
      NOISY                  -> banner noise on stdout before the JSON (tests tolerant parsing)
#>
param(
    [string]$SkillDir,
    [string]$InputsJson,
    [string]$ArtifactRoot,
    [string]$PwshPath,
    [switch]$PassThruEnvelope,
    [Parameter(ValueFromRemainingArguments = $true)] $Rest
)
$ErrorActionPreference = 'Continue'

$leaf = ''
if ($SkillDir) { try { $leaf = [System.IO.Path]::GetFileName($SkillDir.TrimEnd('/', '\')) } catch { $leaf = [string]$SkillDir } }
$inp = [string]$InputsJson

# skill_id: read the fixture manifest if present, else derive from the leaf.
$skillId = $leaf
$manifestPath = if ($SkillDir) { Join-Path $SkillDir 'skill.json' } else { $null }
if ($manifestPath -and (Test-Path -LiteralPath $manifestPath)) {
    try { $m = (Get-Content -LiteralPath $manifestPath -Raw) | ConvertFrom-Json; if ($m.PSObject.Properties['skill_id']) { $skillId = [string]$m.skill_id } } catch { }
}
if (-not $skillId) { $skillId = 'mock.skill' }

# ML/child libraries print freely to stderr; the launcher must ignore it and parse only stdout.
[Console]::Error.WriteLine("[mock-invoke-skill] running $skillId ...")

$now = [datetime]::UtcNow.ToString('o')
$reportSchema = 'lifeorch.skill.invocation_report/0.1'

function Emit($obj) { ($obj | ConvertTo-Json -Depth 20) }

if ($leaf -match 'badmanifest') {
    Emit ([ordered]@{
        schema = $reportSchema; skill_dir = $SkillDir; skill_id = $null
        manifest_valid = $false; manifest_errors = @("missing required field: skill_id", "missing required field: invocation")
        invoked = $false; exit_code = $null
        envelope_valid = $false; envelope_errors = @('skill not invoked: manifest invalid')
        envelope = $null; stderr_tail = '[mock] manifest rejected'
    })
    exit 1
}

if ($inp -match 'BADENV' -or $leaf -match 'badenv') {
    Emit ([ordered]@{
        schema = $reportSchema; skill_dir = $SkillDir; skill_id = $skillId
        manifest_valid = $true; manifest_errors = @()
        invoked = $true; exit_code = 0
        envelope_valid = $false; envelope_errors = @('stdout is not valid JSON: Unexpected end of content')
        envelope = $null; stderr_tail = '[mock] the skill printed prose to stdout instead of an envelope'
    })
    exit 1
}

if ($inp -match 'NOISY') { Write-Output 'llama-server: loading model ... done' }  # stdout noise before the JSON

if ($inp -match 'ERRORME' -or $leaf -match 'errskill') {
    $envelope = [ordered]@{
        schema = 'lifeorch.skill.result/0.1'; skill_id = $skillId; skill_version = '0.1.0'; contract_version = '0.2'
        invocation_id = [guid]::NewGuid().ToString(); status = 'error'
        started_at_utc = $now; finished_at_utc = $now; duration_ms = 42
        result = $null; confidence = $null; artifacts = @(); model_provenance = @()
        diagnostics = [ordered]@{ log = 'stderr.txt' }; warnings = @()
        error = [ordered]@{ code = 'input_not_found'; message = 'the input file does not exist'; retryable = $false }
    }
    Emit ([ordered]@{
        schema = $reportSchema; skill_dir = $SkillDir; skill_id = $skillId
        manifest_valid = $true; manifest_errors = @()
        invoked = $true; exit_code = 0
        envelope_valid = $true; envelope_errors = @()
        envelope = $envelope; stderr_tail = '[mock] the skill reported a logical error'
    })
    exit 1
}

# ---- default: a clean, valid ok run ----
$envelope = [ordered]@{
    schema = 'lifeorch.skill.result/0.1'; skill_id = $skillId; skill_version = '0.1.0'; contract_version = '0.2'
    invocation_id = [guid]::NewGuid().ToString(); status = 'ok'
    started_at_utc = $now; finished_at_utc = $now; duration_ms = 118
    inputs_digest = ('sha256:' + ('a' * 64))
    result = [ordered]@{ ran = $skillId; note = 'mock module executed'; echoed_inputs = $inp }
    confidence = $null
    artifacts = @(
        [ordered]@{ path = (Join-Path ([string]$ArtifactRoot) 'output.txt'); kind = 'text'; bytes = 27; sha256 = ('b' * 64) }
    )
    model_provenance = @()
    diagnostics = [ordered]@{ log = 'stderr.txt' }; warnings = @(); error = $null
}
if ($PassThruEnvelope) { Emit $envelope; exit 0 }
Emit ([ordered]@{
    schema = $reportSchema; skill_dir = $SkillDir; skill_id = $skillId
    manifest_valid = $true; manifest_errors = @()
    invoked = $true; exit_code = 0
    envelope_valid = $true; envelope_errors = @()
    envelope = $envelope; stderr_tail = ''
})
exit 0
