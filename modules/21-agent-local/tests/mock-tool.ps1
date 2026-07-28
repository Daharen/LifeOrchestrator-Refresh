# Mock tool for the -AutoRamp off-machine gate: real filesystem side effects so the frozen contract
# predicates (file_exists / artifact_nonempty / ...) check REAL state. op=write writes a file; op=fail
# returns an error envelope (to exercise the tool_failed soft signal); anything else is a no-op ok.
[CmdletBinding()]
param([string]$InputsJson, [string]$ArtifactRoot, [string]$InvocationId)
$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = [Guid]::NewGuid().ToString() }
function Has($o,$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Sha([string]$path){ try { $b=[System.IO.File]::ReadAllBytes($path); $s=[System.Security.Cryptography.SHA256]::Create(); try { ([BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() } } catch { $null } }
$p = $InputsJson | ConvertFrom-Json
$op = if (Has $p 'op') { [string]$p.op } else { 'noop' }
$path = if (Has $p 'path') { [string]$p.path } else { '' }
$content = if (Has $p 'content') { [string]$p.content } else { '' }
$status='ok'; $err=$null; $result=$null
try {
    if ($op -eq 'write') {
        $dir = Split-Path -Parent $path
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($path, $content, $utf8)
        $result = [ordered]@{ op='write'; path=$path; bytes_written=$content.Length; file=[ordered]@{ sha256=(Sha $path) } }
    } elseif ($op -eq 'fail') {
        $status='error'; $err=[ordered]@{ code='forced_tool_failure'; message='mock tool forced failure'; retryable=$false }
    } else {
        $result = [ordered]@{ op=$op; path=$path }
    }
} catch { $status='error'; $err=[ordered]@{ code='mock_tool_exception'; message="$($_.Exception.Message)"; retryable=$false } }
$env = [ordered]@{
    schema='lifeorch.skill.result/0.1'; skill_id='mock.tool'; skill_version='mock'; contract_version='0.1'
    invocation_id=$InvocationId; status=$status; started_at_utc=([DateTime]::UtcNow).ToString('o'); finished_at_utc=([DateTime]::UtcNow).ToString('o')
    duration_ms=1; inputs_digest='sha256:mock'; result=$result; confidence=$null
    artifacts=@(); model_provenance=@(); diagnostics=[ordered]@{ log='none' }; warnings=@(); error=$err
}
[Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 20))
exit 0
