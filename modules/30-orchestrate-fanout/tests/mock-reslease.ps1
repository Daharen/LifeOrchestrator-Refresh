#requires -Version 7.0
# mock-reslease.ps1 -- a stand-in for res.lease #29 used by the orchestrate.fanout preflight seam.
# It answers `-Action list` with a canned lifeorch.skill.result/0.1 envelope reporting a HELD 'gpu'
# lease, so the plan preflight has a real child to spawn + parse off the box. ASCII-only, deterministic.
[CmdletBinding()]
param(
    [string]$Action = 'list',
    [string]$Resource,
    [string]$Holder,
    [string]$LeaseDir,
    [int]$TtlSeconds = 120,
    [double]$WaitSeconds = 0,
    [string]$LeaseId,
    [string]$InputsJson
)
$now = [DateTime]::UtcNow
$leases = @(
    [ordered]@{ resource = 'gpu'; holder = 'worker-busy'; lease_id = 'mock-gpu-1'; expires_at_utc = $now.AddSeconds(300).ToString('o'); held = $true; stale = $false; seconds_remaining = 300; file = 'gpu.lease' }
)
$result = [ordered]@{ action = 'list'; lease_dir = $(if ($LeaseDir) { $LeaseDir } else { 'mock' }); count = $leases.Count; leases = $leases }
$env = [ordered]@{
    schema = 'lifeorch.skill.result/0.1'; skill_id = 'res.lease'; skill_version = '0.1.0'; contract_version = '0.2'
    invocation_id = [Guid]::NewGuid().ToString(); status = 'ok'
    started_at_utc = $now.ToString('o'); finished_at_utc = $now.ToString('o'); duration_ms = 1
    inputs_digest = 'sha256:' + ('0' * 64)
    result = $result; confidence = $null; artifacts = @(); model_provenance = @()
    diagnostics = [ordered]@{ log = 'stderr.txt' }; warnings = @(); error = $null
}
[Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20))
exit 0
