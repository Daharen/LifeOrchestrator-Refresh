<#
    Invoke-LrapPoserQuery.ps1 -- the Live-Run Audit Pathway (Widget 08) POSER worker (D-0126).

    The OUT-OF-BAND piece: given a request file the read-only widget wrote under its runtime\poser\ dir, it makes
    the ONE model.gateway (#7) call -- on the resident local 9B (llm.strong.qwen3p5-9b) -- and writes the answer
    back under runtime\poser\. The widget spawns THIS script DETACHED (Start-Process, hidden) and polls for the
    answer, so the widget PROCESS itself never calls a model and never holds a lease. The gateway owns the gpu
    lease (res.lease #29) for the single call and releases it -- the existing lease-managed path (D-0126: the 9B
    "rides the gateway/lease path", not a fresh direct invocation).

    FAIL-SILENT contract (D-0126: a failure must not impede functionality): this worker NEVER throws to its
    caller and ALWAYS tries to write an answer -- ok=true with the completion, or ok=false with a short note
    (empty model output, gateway missing, timeout, parse error). The pop-up then shows "explanation unavailable"
    instead of hanging. It writes NOTHING outside the widget runtime dir (LrapPoser's runtime guard).

    Test seam: -GatewayPath (or $env:LIFEORCH_LRAP_POSER_GATEWAY) swaps the real gateway for a mock, so the whole
    read-request -> invoke -> parse -> write-answer path (incl. the fail branches) runs on the cloud gate with no
    GPU. ASCII-only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RequestPath,
    [string]$RuntimeDir,
    [string]$GatewayPath,
    [string]$PwshPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# best-effort breadcrumb so a spawn / import failure is diagnosable (the request's dir always exists). Never throws.
$script:__wlog = ''
try { $script:__wlog = Join-Path (Split-Path -Parent $RequestPath) '_worker.log' } catch { }
function _WL([string]$m) { if ($script:__wlog) { try { Add-Content -LiteralPath $script:__wlog -Value ('[' + (Get-Date).ToString('HH:mm:ss') + '] ' + $m) -ErrorAction SilentlyContinue } catch { } } }
_WL ("ENTER pid=$PID host=" + $(try { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { '?' }))

Import-Module (Join-Path $PSScriptRoot 'LrapPoser.psm1') -Force
_WL 'imported LrapPoser'

$reqId = ''
if (-not $RuntimeDir) {
    # RequestPath = <runtime>\poser\<id>.request.json  ->  RuntimeDir = <runtime>
    try { $RuntimeDir = Split-Path -Parent (Split-Path -Parent $RequestPath) } catch { $RuntimeDir = '' }
}

function _AnswerFail {
    param([string]$Id, [string]$Message)
    if ([string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($RuntimeDir)) { return }
    try { [void](Write-LrapPoserAnswer -RuntimeDir $RuntimeDir -RequestId $Id -Ok:$false -ErrorText $Message) } catch { }
}

try {
    $req = Read-LrapPoserRequest -RequestPath $RequestPath
    $reqId = [string]$req.request_id
    if ([string]::IsNullOrWhiteSpace($reqId)) { throw 'request carried no request_id' }
    _WL "read request reqId=$reqId"

    # compose the gateway messages = [system] + the pop-up turns
    $msgs = New-Object System.Collections.Generic.List[object]
    [void]$msgs.Add([ordered]@{ role = 'system'; content = [string]$req.system })
    foreach ($t in @($req.messages)) { [void]$msgs.Add([ordered]@{ role = [string]$t.role; content = [string]$t.content }) }

    # qwen3.5-9b is a REASONING model that does NOT honor /no_think here (it emits a <think> block regardless and
    # puts it in reasoning_content, leaving `content` empty). Observed: at 1280 tokens it hits finish_reason=length
    # still inside the think block -> empty content. So give it enough budget to FINISH thinking AND emit the answer
    # (floor 4096; it usually stops well before). no_think stays on (harmless; helps if a future build honors it).
    $maxTok = [Math]::Max([int]$req.max_tokens, 4096)
    $inputs = [ordered]@{
        model       = [string]$req.model
        messages    = $msgs.ToArray()
        max_tokens  = $maxTok
        temperature = 0
        no_think    = $true
        warm        = $true       # reuse the resident 9B if the pool has it (else a cold ~60-90s load)
        gpu_lease   = 'auto'      # non-blocking acquire; proceed-with-warning if contended (never blocks other GPU work)
    }
    $inputsJson = $inputs | ConvertTo-Json -Depth 8 -Compress

    $poserDir = Split-Path -Parent $RequestPath
    $gwDir = Join-Path $poserDir ($reqId + '-gw')
    if (-not (Test-Path -LiteralPath $gwDir)) { [void](New-Item -ItemType Directory -Path $gwDir -Force) }

    # locate the gateway (real by default; a mock for the cloud gate)
    $gw = $GatewayPath
    if ([string]::IsNullOrWhiteSpace($gw)) { $gw = $env:LIFEORCH_LRAP_POSER_GATEWAY }
    if ([string]::IsNullOrWhiteSpace($gw)) {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' | Join-Path -ChildPath '..'))
        $gw = [System.IO.Path]::Combine($repoRoot, 'modules', '07-model-gateway', 'Invoke-ModelGateway.ps1')
    }
    if (-not (Test-Path -LiteralPath $gw)) { throw ("model gateway not found: " + $gw) }

    $pwsh = if ($PwshPath) { $PwshPath } elseif ($env:LIFEORCH_PWSH) { $env:LIFEORCH_PWSH } else { (Get-Process -Id $PID).Path }
    # NEVER spawn the gateway with dotnet.exe / a non-pwsh host (the dotnet-tool apphost trap): fall back to PATH.
    if ([string]::IsNullOrWhiteSpace($pwsh) -or ((Split-Path $pwsh -Leaf) -inotmatch '^pwsh(\.exe)?$')) { $pwsh = 'pwsh' }
    _WL ("calling gateway=[$gw] pwsh=[$pwsh] maxtok=$maxTok")

    # THE ONE CALL. The gateway exits 0 whenever it wrote a valid envelope; it manages the gpu lease itself.
    $gwErr = Join-Path $gwDir 'gw.stderr.txt'
    & $pwsh -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $gw -InputsJson $inputsJson -ArtifactRoot $gwDir 2>$gwErr | Out-Null
    _WL ("gateway call returned exit=$LASTEXITCODE")

    # read the completion: prefer output.txt (raw completion), fall back to the result.json envelope
    $text = ''
    $finish = ''
    $outTxt = Get-ChildItem -LiteralPath $gwDir -Recurse -Filter 'output.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
    $resJson = Get-ChildItem -LiteralPath $gwDir -Recurse -Filter 'result.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $outTxt) { try { $text = [string](Get-Content -LiteralPath $outTxt.FullName -Raw) } catch { } }
    if ($null -ne $resJson) {
        try {
            $env = Get-Content -LiteralPath $resJson.FullName -Raw | ConvertFrom-Json
            $inner = if ($null -ne $env.PSObject.Properties['result']) { $env.result } else { $env }
            if ([string]::IsNullOrEmpty($text) -and $null -ne $inner.PSObject.Properties['output']) { $text = [string]$inner.output.text }
            if ($null -ne $inner.PSObject.Properties['generation'] -and $null -ne $inner.generation) { $finish = [string]$inner.generation.finish_reason }
        }
        catch { }
    }
    if ($null -eq $resJson -and $null -eq $outTxt) { throw 'gateway produced no result artifact (output.txt / result.json)' }

    $text = ([string]$text).Trim()
    if ([string]::IsNullOrEmpty($text)) {
        _AnswerFail -Id $reqId -Message ('the local model produced only reasoning and no answer (finish_reason=' + $finish + ', ' + $maxTok + ' tok). Try again, or open the raw trace for this step.')
    }
    else {
        [void](Write-LrapPoserAnswer -RuntimeDir $RuntimeDir -RequestId $reqId -Ok:$true -Text $text -FinishReason $finish)
    }
}
catch {
    _WL ('CATCH: ' + [string]$_.Exception.Message)
    _AnswerFail -Id $reqId -Message ('poser query failed: ' + [string]$_.Exception.Message)
}

# fail-silent: always exit 0; the answer file (ok=true|false) is the only channel.
exit 0
