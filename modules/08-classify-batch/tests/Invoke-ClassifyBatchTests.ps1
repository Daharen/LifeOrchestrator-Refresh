#requires -Version 7.0
# Regression tests for Module 8 (classify.batch). Run through the executor (the live checks need the GPU +
# staged models via model.gateway). Fast checks (manifest, error paths) need no model load; live checks make
# the skill call the real gateway, which spins up llama-server on a small staged LLM and tears it down.
[CmdletBinding()]
param([string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-ClassifyBatch.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$gateway = Join-Path $modulesDir '07-model-gateway/Invoke-ModelGateway.ps1'
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }
function RunJson([string]$inputs, [string[]]$extra) {
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,'-InputsJson',$inputs,'-PwshPath',$PwshPath)
    if ($extra) { $a += $extra }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    return ([string]($o | Out-String)).Trim()
}

# ---- manifest ----
$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$man = (Get-Content -LiteralPath (Join-Path $moduleRoot 'skill.json') -Raw) | ConvertFrom-Json
Check 'manifest batch=true parallel_safe=false determinism=mixed' ($man.batch -eq $true -and $man.parallel_safe -eq $false -and $man.determinism -eq 'mixed')

# ---- error paths (no model load; must be valid error envelopes, exit 0) ----
$e1 = RunJson '{"mode":"classify","labels":[],"items":[{"id":"a","text":"x"}]}' $null
$ev1 = Test-SkillResultEnvelope -Json $e1
Check 'no_labels valid envelope' ([bool]$ev1.valid)
$o1 = $e1 | ConvertFrom-Json
Check 'no_labels error+exit0' ($o1.status -eq 'error' -and $o1.error.code -eq 'no_labels' -and $script:code -eq 0)

$e2 = RunJson '{"mode":"classify","labels":["a"],"items":[]}' $null
$o2 = $e2 | ConvertFrom-Json
Check 'no_items error' ($o2.status -eq 'error' -and $o2.error.code -eq 'no_items')

$e3 = RunJson '{"mode":"frobnicate","labels":["a"],"items":[{"id":"a","text":"x"}]}' $null
$o3 = $e3 | ConvertFrom-Json
Check 'invalid_mode error' ($o3.status -eq 'error' -and $o3.error.code -eq 'invalid_mode')

$e4 = RunJson '{"mode":"extract","fields":[],"items":[{"id":"a","text":"x"}]}' $null
$o4 = $e4 | ConvertFrom-Json
Check 'no_fields error' ($o4.status -eq 'error' -and $o4.error.code -eq 'no_fields')

$e5 = RunJson '{"mode":"classify","labels":["a"],"items":[{"id":"a","text":"x"}]}' @('-GatewayPath','C:\nope\nogateway.ps1')
$o5 = $e5 | ConvertFrom-Json
Check 'gateway_not_found error' ($o5.status -eq 'error' -and $o5.error.code -eq 'gateway_not_found')

# ---- LIVE: classify batch on tier tiny (0.5B), obvious taxonomy ----
$inC = '{"mode":"classify","tier":"tiny","temperature":0.0,"seed":42,"labels":["animal","vehicle","food"],"items":[{"id":"a","text":"a golden retriever puppy playing in the yard"},{"id":"b","text":"a red pickup truck on the highway"},{"id":"c","text":"a steaming bowl of ramen noodles"}]}'
$gC = RunJson $inC $null
$evC = Test-SkillResultEnvelope -Json $gC
Check 'live classify envelope validates' ([bool]$evC.valid)
if (-not $evC.valid) { $evC.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$oC = $gC | ConvertFrom-Json
Check 'live classify status ok' ($oC.status -eq 'ok')
Check 'live classify 3 items' ($oC.result.count -eq 3)
Check 'live classify tier tiny resolved (0.5b)' ($oC.result.model -eq 'llm.weak.qwen2p5-0p5b' -and $oC.result.selected_from -eq 'tier:tiny')
Check 'live classify every item labeled in-set' (@($oC.result.items | Where-Object { $_.status -eq 'ok' -and $_.in_set -and $null -ne $_.label }).Count -eq 3)
Check 'live classify confidence in 0..1' (@($oC.result.items | Where-Object { $_.confidence -ge 0 -and $_.confidence -le 1 }).Count -eq 3)
Check 'live classify groups partition all ids' ((@($oC.result.groups.PSObject.Properties | ForEach-Object { @($_.Value).Count } | Measure-Object -Sum).Sum) -eq 3)
Check 'live classify envelope confidence set' ($null -ne $oC.confidence -and $oC.confidence -gt 0)
Check 'live classify provenance aggregate calls=3' (@($oC.model_provenance).Count -eq 1 -and $oC.model_provenance[0].calls -eq 3 -and $oC.model_provenance[0].completion_tokens_total -ge 3)
$cjArt = @($oC.artifacts | Where-Object { $_.kind -eq 'json' })
Check 'live classify has json+md artifacts' (@($oC.artifacts).Count -ge 2 -and $cjArt.Count -ge 1 -and @($oC.artifacts | Where-Object { $_.kind -eq 'markdown' }).Count -ge 1)
if ($cjArt.Count -ge 1) {
    $p = $cjArt[0].path
    Check 'live classify classified.json on disk' (Test-Path -LiteralPath $p)
    if (Test-Path -LiteralPath $p) {
        $b = [System.IO.File]::ReadAllBytes($p)
        $sha = ([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($b))).Replace('-','').ToLowerInvariant()
        Check 'live classify classified.json sha256 matches' ($sha -eq $cjArt[0].sha256)
    }
}

# ---- LIVE: explicit model id resolves (proves model + tier both work) ----
$inM = '{"mode":"classify","model":"llm.weak.qwen2p5-1p5b","temperature":0.0,"seed":42,"labels":["animal","vehicle"],"items":[{"id":"z","text":"a small kitten"}]}'
$oM = (RunJson $inM $null) | ConvertFrom-Json
Check 'live explicit model 1.5B resolves' ($oM.result.model -eq 'llm.weak.qwen2p5-1p5b' -and $oM.result.selected_from -eq 'model_id')

# ---- LIVE: extract mode ----
$inE = '{"mode":"extract","tier":"tiny","temperature":0.0,"seed":42,"max_tokens":120,"fields":[{"name":"animal","description":"the animal mentioned"},{"name":"color","description":"its color"}],"items":[{"id":"e1","text":"The brown dog ran fast."}]}'
$oE = (RunJson $inE $null) | ConvertFrom-Json
Check 'live extract envelope validates' ([bool](Test-SkillResultEnvelope -Json ($oE | ConvertTo-Json -Depth 24)).valid)
Check 'live extract item has requested keys' ($null -ne $oE.result.items[0].extracted -and ($oE.result.items[0].extracted.PSObject.Properties.Name -contains 'animal') -and ($oE.result.items[0].extracted.PSObject.Properties.Name -contains 'color'))

# ---- Review routing + gateway-review suppression ----
$rq = Join-Path $env:TEMP ("lo-cb-rq-" + [Guid]::NewGuid().ToString('N') + '.jsonl')
$tmpArt = Join-Path $env:TEMP ("lo-cb-art-" + [Guid]::NewGuid().ToString('N'))
$inR = '{"mode":"classify","tier":"tiny","temperature":0.0,"seed":42,"confidence_threshold":0.99,"labels":["animal","vehicle","food"],"items":[{"id":"r1","text":"a bright yellow school bus"}]}'
$oR = (RunJson $inR @('-ReviewQueuePath',$rq,'-ArtifactRoot',$tmpArt)) | ConvertFrom-Json
Check 'review: item flagged under threshold 0.99' ($oR.result.items[0].flagged -eq $true -and $oR.result.flagged_count -ge 1)
Check 'review: canonical queue file written' (Test-Path -LiteralPath $rq)
if (Test-Path -LiteralPath $rq) {
    $lines = @(Get-Content -LiteralPath $rq)
    Check 'review: queue has an item' ($lines.Count -ge 1)
    $item = $lines[0] | ConvertFrom-Json
    Check 'review: item schema+flagged_by+source_ref' ($item.schema -eq 'lifeorch.review.item/0.1' -and $item.flagged_by -eq 'classify.batch' -and $item.source_ref -match 'classified.json#r1')
    $byWho = @($lines | ForEach-Object { ($_ | ConvertFrom-Json).flagged_by } | Sort-Object -Unique)
    Check 'review: gateway did NOT write to canonical queue (suppressed)' ($byWho.Count -eq 1 -and $byWho[0] -eq 'classify.batch')
    Remove-Item -LiteralPath $rq -Force -ErrorAction SilentlyContinue
}
$supFile = Join-Path (Join-Path $tmpArt $oR.invocation_id) '_gateway_review_suppressed.jsonl'
Check 'review: gateway suppressed-review path is under the artifact dir' ($oR.diagnostics.gateway_reviews_suppressed_to -eq $supFile)
Remove-Item -LiteralPath $tmpArt -Recurse -Force -ErrorAction SilentlyContinue

# ---- Wrapper (Module 1) ----
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -InputsJson '{"mode":"classify","tier":"tiny","temperature":0.0,"seed":42,"labels":["animal","vehicle"],"items":[{"id":"w","text":"a spotted horse"}]}'
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid' ($repObj.manifest_valid -eq $true)
Check 'wrapper envelope_valid' ($repObj.envelope_valid -eq $true)
Check 'wrapper ran classify.batch' ($repObj.envelope.skill_id -eq 'classify.batch')

# ---- no orphaned server processes ----
Start-Sleep -Milliseconds 500
$orphans = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue)
Check 'no orphaned llama-server' ($orphans.Count -eq 0)

if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
