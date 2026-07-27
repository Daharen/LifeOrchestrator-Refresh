#requires -Version 7.0
# Regression tests for Module 7 (model.gateway). Run through the executor (needs the GPU + staged models).
# Fast checks (manifest, error paths, wrapper-manifest) need no model load; live checks spin up llama-server
# on a small staged LLM (0.5B/1.5B), fully GPU-offloaded, and tear it down.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-ModelGateway.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function RunEntry([string[]]$a) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}

# ---- manifest ----
$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }

# ---- registry loads and declares all modalities ----
$reg = (Get-Content -LiteralPath (Join-Path $moduleRoot 'models.json') -Raw) | ConvertFrom-Json
$types = @($reg.models | ForEach-Object { $_.type }) | Sort-Object -Unique
Check 'registry declares llm+stt+tts+embedding' (($types -contains 'llm') -and ($types -contains 'stt') -and ($types -contains 'tts') -and ($types -contains 'embedding'))
$wiredLlms = @($reg.models | Where-Object { $_.type -eq 'llm' -and $_.wired })
# Registry wired LLMs: 3 weak tiers (0.5b/1.5b/3b) + strong 9b (D-0044) + demoted-but-wired 27b = 5.
Check 'wired LLMs match registry (5)' ($wiredLlms.Count -eq 5)

# ---- error paths (no model load; must be valid error envelopes, exit 0) ----
$e1 = RunEntry @('-Model','llm.bogus.does-not-exist','-Prompt','hi')
$ev1 = Test-SkillResultEnvelope -Json $e1
Check 'model_not_found valid envelope' ([bool]$ev1.valid)
$o1 = $e1 | ConvertFrom-Json
Check 'model_not_found error+exit0' ($o1.status -eq 'error' -and $o1.error.code -eq 'model_not_found' -and $script:code -eq 0)

$e2 = RunEntry @('-Model','stt.whisper.base-en','-Prompt','hi')
$o2 = $e2 | ConvertFrom-Json
Check 'model_not_wired error' ($o2.status -eq 'error' -and $o2.error.code -eq 'model_not_wired')

$e3 = RunEntry @('-Tier','weak','-Prompt','hi','-Registry','C:\nope\nomodels.json')
$o3 = $e3 | ConvertFrom-Json
Check 'registry_not_found error' ($o3.status -eq 'error' -and $o3.error.code -eq 'registry_not_found')

$e4 = RunEntry @('-Tier','frobnicate','-Prompt','hi')
$o4 = $e4 | ConvertFrom-Json
Check 'tier_not_found error' ($o4.status -eq 'error' -and $o4.error.code -eq 'tier_not_found')

$e5 = RunEntry @('-Tier','tiny')
$o5 = $e5 | ConvertFrom-Json
Check 'no_prompt error' ($o5.status -eq 'error' -and $o5.error.code -eq 'no_prompt')

# ---- LIVE: tier tiny (0.5B) normal generation ----
$g = RunEntry @('-Tier','tiny','-Prompt','Reply with exactly one word: PONG','-MaxTokens','16','-Temperature','0.1','-Seed','42')
$evg = Test-SkillResultEnvelope -Json $g
Check 'live envelope validates' ([bool]$evg.valid)
if (-not $evg.valid) { $evg.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$og = $g | ConvertFrom-Json
Check 'live status ok' ($og.status -eq 'ok')
Check 'live model resolved (0.5b)' ($og.result.model -eq 'llm.weak.qwen2p5-0p5b' -and $og.result.selected_from -eq 'tier:tiny')
Check 'live non-empty output' (-not [string]::IsNullOrWhiteSpace($og.result.output.text))
Check 'live finish_reason stop' ($og.result.generation.finish_reason -eq 'stop')
Check 'live confidence 0.7' ([double]$og.confidence -eq 0.7)
Check 'live provenance populated' (@($og.model_provenance).Count -ge 1 -and $og.model_provenance[0].model_id -eq 'llm.weak.qwen2p5-0p5b' -and $null -ne $og.model_provenance[0].completion_tokens)
Check 'live artifacts have sha256' (@($og.artifacts).Count -ge 2 -and ($og.artifacts | Where-Object { $_.kind -eq 'text' }).Count -ge 1)
$outArt = @($og.artifacts | Where-Object { $_.kind -eq 'text' })[0]
if ($null -ne $outArt) {
    Check 'live output.txt on disk' (Test-Path -LiteralPath $outArt.path)
    if (Test-Path -LiteralPath $outArt.path) {
        $b = [System.IO.File]::ReadAllBytes($outArt.path)
        $sha = ([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($b))).Replace('-','').ToLowerInvariant()
        Check 'live output sha256 matches' ($sha -eq $outArt.sha256)
    }
}

# ---- LIVE: explicit model via InputsJson through the WRAPPER (Module 1) ----
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson '{"model":"llm.weak.qwen2p5-1p5b","prompt":"Reply with exactly one word: PONG","max_tokens":16,"temperature":0.1,"seed":42}'
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)
Check 'wrapper ran 1.5B' ($repObj.envelope.result.model -eq 'llm.weak.qwen2p5-1p5b')

# ---- LIVE: truncation -> low confidence -> review queue append ----
$rq = Join-Path $env:TEMP ("lo-rq-" + [Guid]::NewGuid().ToString('N') + '.jsonl')
$t = RunEntry @('-Tier','tiny','-Prompt','Write a long paragraph about the ocean.','-MaxTokens','1','-Seed','7','-ReviewQueuePath',$rq)
$ot = $t | ConvertFrom-Json
Check 'truncation finish_reason length' ($ot.result.generation.finish_reason -eq 'length')
Check 'truncation confidence 0.4' ([double]$ot.confidence -eq 0.4)
Check 'review queue file written' (Test-Path -LiteralPath $rq)
if (Test-Path -LiteralPath $rq) {
    $lines = @(Get-Content -LiteralPath $rq)
    Check 'review queue has an item' ($lines.Count -ge 1)
    $item = $lines[0] | ConvertFrom-Json
    Check 'review item schema+reason' ($item.schema -eq 'lifeorch.review.item/0.1' -and $item.reason -eq 'low_confidence' -and $item.flagged_by -eq 'model.gateway')
    Remove-Item -LiteralPath $rq -Force -ErrorAction SilentlyContinue
}

# ---- LIVE: GPU lease wiring (res.lease #29) -- acquire before run, release after teardown ----
$reslease = Join-Path $modulesDir '29-resource-lease/Invoke-ResLease.ps1'
function RunRl([string[]]$a) { $o = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $reslease @a; return (([string]($o | Out-String)).Trim() | ConvertFrom-Json) }
Check 'reslease present' (Test-Path -LiteralPath $reslease)
$ld = Join-Path $env:TEMP ("gw-lease-" + [Guid]::NewGuid().ToString('N'))

# (a) wait mode, lease FREE -> gateway acquires (owns) it across the run and releases after teardown
$gl  = RunEntry @('-Tier','tiny','-Prompt','Reply with exactly one word: PONG','-MaxTokens','8','-Temperature','0.1','-Seed','42','-GpuLease','wait','-GpuLeaseWaitSeconds','60','-LeaseDir',$ld,'-PwshPath',$PwshPath)
$ogl = $gl | ConvertFrom-Json
Check 'lease(a): run ok (wait mode, free)' ($ogl.status -eq 'ok')
$gll = $ogl.result.server.gpu_lease
Check 'lease(a): acquired + owned' ($gll.acquired -eq $true -and $gll.owned -eq $true)
Check 'lease(a): has lease_id' (-not [string]::IsNullOrWhiteSpace([string]$gll.lease_id))
Check 'lease(a): released after teardown' ($gll.released -eq $true)
Check 'lease(a): free after run (status not held)' ((RunRl @('-Action','status','-Resource','gpu','-LeaseDir',$ld)).result.held -eq $false)

# (b) contended -> auto mode logs + proceeds and does NOT touch the other holder's lease
$pre = RunRl @('-Action','acquire','-Resource','gpu','-Holder','other-holder','-TtlSeconds','120','-LeaseDir',$ld)
Check 'lease(b): pre-acquired by other holder' ($pre.result.acquired -eq $true)
$gc  = RunEntry @('-Tier','tiny','-Prompt','Reply with exactly one word: PONG','-MaxTokens','8','-Temperature','0.1','-Seed','42','-GpuLease','auto','-LeaseDir',$ld,'-PwshPath',$PwshPath)
$ogc = $gc | ConvertFrom-Json
$gcl = $ogc.result.server.gpu_lease
Check 'lease(b): proceeds while contended' ($ogc.status -eq 'ok')
Check 'lease(b): not owned when contended' ($gcl.acquired -eq $false -and $gcl.owned -eq $false)
Check 'lease(b): reports held_by' ($gcl.held_by -eq 'other-holder')
Check 'lease(b): other holder still holds after run' ((RunRl @('-Action','status','-Resource','gpu','-LeaseDir',$ld)).result.holder -eq 'other-holder')
RunRl @('-Action','release','-Resource','gpu','-Holder','other-holder','-LeaseDir',$ld) | Out-Null

# (c) res.lease ABSENT -> graceful proceed (bad -ResLeasePath), generation unaffected
$ga  = RunEntry @('-Tier','tiny','-Prompt','Reply with exactly one word: PONG','-MaxTokens','8','-Temperature','0.1','-Seed','42','-GpuLease','auto','-ResLeasePath','C:\nope\no-reslease.ps1','-LeaseDir',$ld,'-PwshPath',$PwshPath)
$oga = $ga | ConvertFrom-Json
Check 'lease(c): graceful when res.lease absent' ($oga.status -eq 'ok' -and $oga.result.server.gpu_lease.available -eq $false -and $oga.result.server.gpu_lease.acquired -eq $false)

# (d) off mode -> no lease interaction, generation unchanged
$gf  = RunEntry @('-Tier','tiny','-Prompt','Reply with exactly one word: PONG','-MaxTokens','8','-Temperature','0.1','-Seed','42','-GpuLease','off','-LeaseDir',$ld,'-PwshPath',$PwshPath)
$ogf = $gf | ConvertFrom-Json
Check 'lease(d): off mode still generates' ($ogf.status -eq 'ok')
Check 'lease(d): off mode not requested/acquired' ($ogf.result.server.gpu_lease.requested -eq $false -and $ogf.result.server.gpu_lease.acquired -eq $false)
Remove-Item -LiteralPath $ld -Recurse -Force -ErrorAction SilentlyContinue

# ---- no orphaned server processes ----
Start-Sleep -Milliseconds 500
$orphans = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue)
Check 'no orphaned llama-server' ($orphans.Count -eq 0)

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
