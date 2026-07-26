<#
    mock-route-tools.ps1 - a stand-in for modules/27-route-tools/Invoke-RouteTools.ps1 used ONLY by the
    Local Agent Console cloud pre-ship gate (a GPU-bound real route.tools cannot run on the Linux cloud box).
    It accepts the same -InputsJson / -ArtifactRoot the console passes and emits a canned but shape-accurate
    lifeorch.skill.result/0.1 envelope (with result.tools) to stdout, so the console core's Plan path
    (spawn -> parse -> Format-RoutePlan) is exercised for real.

    Request keywords select the selection:
      (default)  -> ["doc.io"]
      image/dog  -> ["gen.image"]
      NONE       -> []
      NOISY      -> banner noise on stdout before the JSON (tests tolerant parsing)
#>
param(
    [string]$InputsJson,
    [string]$Request,
    [string]$ArtifactRoot,
    [Parameter(ValueFromRemainingArguments = $true)] $Rest
)
$ErrorActionPreference = 'Continue'

$request = $Request
if ($InputsJson) {
    try { $o = $InputsJson | ConvertFrom-Json; if ($o.PSObject.Properties['request']) { $request = [string]$o.request } } catch { }
}
if (-not $request) { $request = '(no request)' }

[Console]::Error.WriteLine('[mock-route-tools] loading mid tier ...')
if ($request -match 'NOISY') { Write-Output 'llama-server: loading model ... done' }

$sel = @('doc.io')
if ($request -match 'NONE') { $sel = @() }
elseif ($request -match '(?i)imag|picture|dog|draw|photo') { $sel = @('gen.image') }

$now = [datetime]::UtcNow.ToString('o')
$result = [ordered]@{
    request = $request; tier = 'mid'; model = 'llm.mid.qwen2p5-3b'
    catalog = @(
        [ordered]@{ tool = 'doc.io'; purpose = 'Read, write, edit, or append a text file.' },
        [ordered]@{ tool = 'gen.image'; purpose = 'Generate an image from a text prompt.' }
    )
    catalog_count = 2
    tools = $sel; planned_tools = $sel; count = @($sel).Count; tools_dropped = @()
    parsed_ok = $true; gated = $true; raw_output = ('[' + ((@($sel) | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']')
    finish_reason = 'stop'; cost = [ordered]@{ gateway_calls = 1; total_tokens = 41; runtime_ms = 420 }
    is_review_producer = $false
}
$envelope = [ordered]@{
    schema = 'lifeorch.skill.result/0.1'; skill_id = 'route.tools'; skill_version = '0.1.0'; contract_version = '0.2'
    invocation_id = [guid]::NewGuid().ToString(); status = 'ok'
    started_at_utc = $now; finished_at_utc = $now; duration_ms = 420
    inputs_digest = ('sha256:' + ('a' * 64))
    result = $result; confidence = 0.7; artifacts = @()
    model_provenance = @([ordered]@{ stage = 'route'; model_id = 'llm.mid.qwen2p5-3b'; runtime_ms = 400 })
    diagnostics = [ordered]@{ log = 'stderr.txt' }; warnings = @(); error = $null
}
($envelope | ConvertTo-Json -Depth 12)
exit 0
