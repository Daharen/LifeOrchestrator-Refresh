<#
    mock-poser-gateway.ps1 -- a deterministic stand-in for modules/07-model-gateway/Invoke-ModelGateway.ps1, so
    the poser WORKER (Invoke-LrapPoserQuery.ps1) can be driven end-to-end on the cloud gate with NO GPU. It
    mirrors the real gateway's OUTPUT contract only: given -InputsJson + -ArtifactRoot it writes
    <ArtifactRoot>\<inv>\output.txt (raw completion) + result.json (the envelope carrying generation.finish_reason).

    It branches on a marker in the user message so the worker's THREE paths are all exercised:
      MOCK_EMPTY -> writes an EMPTY completion (the 9B-returns-no-content case: worker must answer ok=false)
      MOCK_FAIL  -> exits 1 and writes NO artifact (the gateway-crash case: worker must answer ok=false, no hang)
      otherwise  -> a canned, well-formed completion (worker must answer ok=true with the text)
    ASCII-only.
#>
[CmdletBinding()]
param([string]$InputsJson, [string]$ArtifactRoot, [Parameter(ValueFromRemainingArguments = $true)]$Rest)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$inv = Join-Path $ArtifactRoot 'mockinv'
$body = ''
try { $body = [string]$InputsJson } catch { $body = '' }

if ($body -match 'MOCK_FAIL') { Write-Error 'mock gateway: simulated failure (no artifact)'; exit 1 }

[void](New-Item -ItemType Directory -Path $inv -Force)

if ($body -match 'MOCK_EMPTY') {
    $text = ''
    $finish = 'length'
    $status = 'partial'
}
else {
    $text = 'This step normalizes the request. The recorded facts show the counts reconcile at this point. This is an explanation of the instrument and the recorded facts only; whether the run is correct is for you to judge.'
    $finish = 'stop'
    $status = 'ok'
}

[System.IO.File]::WriteAllText((Join-Path $inv 'output.txt'), $text, (New-Object System.Text.UTF8Encoding($false)))
$envelope = [ordered]@{
    schema        = 'lifeorch.skill.result/0.1'
    invocation_id = 'mockinv'
    status        = $status
    result        = [ordered]@{
        model      = 'llm.strong.qwen3p5-9b'
        output     = [ordered]@{ role = 'assistant'; text = $text }
        generation = [ordered]@{ finish_reason = $finish; completion_tokens = ($text.Length) }
    }
}
[System.IO.File]::WriteAllText((Join-Path $inv 'result.json'), ($envelope | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
exit 0
