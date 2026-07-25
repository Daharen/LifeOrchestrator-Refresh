#requires -Version 7.0
# Regression tests for Module 19 (logic.escalator). Dual-mode / OS-portable:
#   default        -> runs the MOCK-gateway scenarios (the real escalator vs tests/mock-gateway.ps1) which need
#                     no GPU/Windows, so this whole block is the CLOUD pre-ship gate on Linux pwsh 7.4.6.
#   -Live          -> ALSO exercises the real model.gateway on the small tiers (needs the executor + GPU).
# The mock scenarios prove the ladder logic: self-consistency short-circuit, escalate-and-resolve, the
# DETERMINISTIC in-set gate overriding an LLM-judge ACCEPT (anti-rubber-stamp), needs_frontier, the
# child-review suppression (canonical queue untouched), provenance, batch, generic kind, envelope validity,
# and the Module 1 wrapper.
[CmdletBinding()]
param(
    [string]$PwshPath = 'C:\Users\just_\.dotnet\tools\pwsh.exe',
    [switch]$Live,
    [string]$RealGatewayPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Split-Path -Parent $moduleRoot
Import-Module (Join-Path $modulesDir '01-skill-bootstrap/lib/SkillContract.psm1') -Force
$entry   = Join-Path $moduleRoot 'Invoke-LogicEscalator.ps1'
$wrapper = Join-Path $modulesDir '01-skill-bootstrap/Invoke-Skill.ps1'
$mockGw  = Join-Path $PSScriptRoot 'mock-gateway.ps1'
$utf8    = [System.Text.UTF8Encoding]::new($false)
$script:fail = 0
function Check([string]$n, [bool]$c) { if ($c) { [Console]::Out.WriteLine("PASS  $n") } else { [Console]::Out.WriteLine("FAIL  $n"); $script:fail++ } }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("lo-le-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$artRoot = Join-Path $work 'art'

# Run the escalator against the MOCK gateway. Returns the parsed envelope object.
function RunMock([string]$inputsJson) {
    $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,
           '-GatewayPath',$mockGw,'-PwshPath',$PwshPath,'-ArtifactRoot',$artRoot,'-InputsJson',$inputsJson)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @a
    $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
    $txt = ([string]($o | Out-String)).Trim()
    return $txt
}
function Env2($txt) { return ($txt | ConvertFrom-Json) }
function Task0($env) { return @($env.result.tasks)[0] }

# ---- manifest ----
$mv = Test-SkillManifest -Path (Join-Path $moduleRoot 'skill.json')
Check 'manifest validates' ([bool]$mv.valid)
if (-not $mv.valid) { $mv.errors | ForEach-Object { [Console]::Out.WriteLine("      - $_") } }
$man = (Get-Content -LiteralPath (Join-Path $moduleRoot 'skill.json') -Raw) | ConvertFrom-Json
Check 'manifest flags mixed/batch=true/parallel_safe=false/streaming=false' ($man.determinism -eq 'mixed' -and $man.batch -eq $true -and $man.parallel_safe -eq $false -and $man.streaming -eq $false)
Check 'manifest skill_id + contract_version 0.2' ($man.skill_id -eq 'logic.escalator' -and $man.contract_version -eq '0.2')

# ---- scenario 2: short-circuit at tiny (K=3 self-consistency, in-set) ----
$sc = RunMock '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak","mid"],"samples":3,"tasks":[{"id":"easy","text":"MOCK a=tiny:animal jacc=animal | a golden retriever puppy"}]}'
$scE = Env2 $sc
Check 'short-circuit envelope validates + exit 0' ((Test-SkillResultEnvelope -Json $sc).valid -and $script:code -eq 0)
$scT = Task0 $scE
Check 'short-circuit accepted at tiny via consistency' ($scT.accepted_tier -eq 'tiny' -and $scT.accepted_via -eq 'consistency')
Check 'short-circuit no judge call (3 answer calls only)' ($scT.gateway_calls -eq 3 -and (@($scT.ladder | Where-Object { $_.role -eq 'judge' }).Count -eq 0))
Check 'short-circuit not flagged for frontier' ($scT.needs_frontier -eq $false -and $scT.gate.hard_pass -eq $true)

# ---- scenario 3: accept at tiny via a weak judge (K=1) ----
$ac = RunMock '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak"],"samples":1,"tasks":[{"id":"acc","text":"MOCK a=tiny:animal jacc=animal | a cat"}]}'
$acT = Task0 (Env2 $ac)
Check 'K=1 accept at tiny via judge, 2 calls' ($acT.accepted_tier -eq 'tiny' -and $acT.accepted_via -eq 'judge' -and $acT.gateway_calls -eq 2)

# ---- scenario 4: escalate past tiny, resolve at weak ----
$es = RunMock '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak","mid"],"samples":1,"tasks":[{"id":"esc","text":"MOCK a=tiny:vehicle,weak:animal jacc=animal | a puppy"}]}'
$esT = Task0 (Env2 $es)
Check 'escalate resolves at weak (via judge), 3 calls' ($esT.accepted_tier -eq 'weak' -and $esT.accepted_via -eq 'judge' -and $esT.gateway_calls -eq 3 -and [string]$esT.answer -eq 'animal')

# ---- scenario 5: DETERMINISTIC in-set gate overrides an LLM-judge ACCEPT (anti-rubber-stamp) ----
$ov = RunMock '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak","mid"],"samples":1,"tasks":[{"id":"ovr","text":"MOCK a=tiny:zzz,weak:animal,mid:animal jacc=animal jforce=accept | x"}]}'
$ovT = Task0 (Env2 $ov)
$tiny0 = @($ovT.ladder | Where-Object { $_.role -eq 'answer' -and $_.tier -eq 'tiny' })[0]
$weakJudge = @($ovT.ladder | Where-Object { $_.role -eq 'judge' -and $_.tier -eq 'weak' })[0]
Check 'override: tiny out-of-set answer NOT accepted despite judge accept=true' ($ovT.accepted_tier -ne 'tiny' -and $tiny0.hardpass -eq $false -and $weakJudge.accept -eq $true)
Check 'override: escalated and resolved at an in-set tier' ($ovT.accepted_tier -eq 'weak' -and $ovT.gate.hard_pass -eq $true -and [string]$ovT.answer -eq 'animal')

# ---- scenario 6: needs_frontier (every tier out-of-set) ----
$nf = RunMock '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak","mid","strong"],"samples":1,"tasks":[{"id":"nf","text":"MOCK a=tiny:zzz,weak:zzz,mid:zzz,strong:zzz jacc=none | x"}]}'
$nfT = Task0 (Env2 $nf)
Check 'needs_frontier when even the top tier hard-fails' ($nfT.needs_frontier -eq $true -and $nfT.gate.hard_pass -eq $false -and $nfT.accepted_tier -eq 'strong' -and $nfT.confidence -le 0.25)

# ---- scenario 7: child-review suppression (canonical queue untouched) ----
$canon = Join-Path $work 'canonical_review_queue.jsonl'
[System.IO.File]::WriteAllText($canon, '{"schema":"lifeorch.review.item/0.1","id":"seed-1","status":"open"}' + "`n", $utf8)
$before = @(Get-Content -LiteralPath $canon).Count
$sup = RunMock '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak"],"samples":1,"tasks":[{"id":"sup","text":"MOCK a=tiny:animal jacc=animal rq=1 | x"}]}'
$supE = Env2 $sup
$after = @(Get-Content -LiteralPath $canon).Count
Check 'canonical review queue untouched (not a producer)' ($before -eq 1 -and $after -eq 1)
$supSink = $supE.result.gateway_reviews_suppressed_to
Check 'child gateway review writes routed to the suppressed sink' ((Test-Path -LiteralPath $supSink) -and (@(Get-Content -LiteralPath $supSink).Count -ge 1))
Check 'result marks is_review_producer=false' ($supE.result.is_review_producer -eq $false)

# ---- scenario 8: provenance + resolve_distribution + batch ----
$batch = RunMock '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak","mid"],"samples":1,"tasks":[{"id":"b1","text":"MOCK a=tiny:animal jacc=animal | p"},{"id":"b2","text":"MOCK a=tiny:vehicle,weak:food jacc=food | q"}]}'
$batchE = Env2 $batch
Check 'batch: 2 tasks processed' (@($batchE.result.tasks).Count -eq 2 -and $batchE.result.count -eq 2)
$rdSum = 0; foreach ($k in $batchE.result.resolve_distribution.PSObject.Properties.Name) { $rdSum += [int]$batchE.result.resolve_distribution.$k }
Check 'batch: resolve_distribution sums to task count' ($rdSum -eq 2)
Check 'batch: per-tier provenance present + stage-tagged' (@($batchE.model_provenance).Count -ge 1 -and ($null -ne @($batchE.model_provenance)[0].tier))
Check 'batch: envelope confidence in 0..1' ($null -ne $batchE.confidence -and [double]$batchE.confidence -ge 0 -and [double]$batchE.confidence -le 1)

# ---- scenario 9: generic kind ----
$gen = RunMock '{"kind":"generic","tiers":["tiny","weak"],"samples":1,"tasks":[{"id":"g","text":"MOCK g=tiny:hello jacc=hello | say hi"}]}'
$genT = Task0 (Env2 $gen)
Check 'generic: resolves, hard_pass true, ungated confidence <= 0.7' ($genT.gate.hard_pass -eq $true -and [double]$genT.confidence -le 0.7 -and [string]$genT.answer -eq 'hello')

# ---- scenario 10: error paths ----
$e1 = RunMock '{"kind":"boguskind","tasks":[{"text":"x"}]}'
$e1o = Env2 $e1
Check 'invalid_kind error envelope + exit 0' ((Test-SkillResultEnvelope -Json $e1).valid -and $e1o.status -eq 'error' -and $e1o.error.code -eq 'invalid_kind' -and $script:code -eq 0)
$e2 = RunMock '{"kind":"classify","labels":["a","b"],"tiers":["tiny"],"tasks":[]}'
$e2o = Env2 $e2
Check 'no_tasks error envelope' ($e2o.status -eq 'error' -and $e2o.error.code -eq 'no_tasks')

# ---- scenario 11: Module 1 wrapper ----
$inJson = '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak"],"samples":1,"gateway_path":"' + ($mockGw -replace '\\','\\\\') + '","pwsh_path":"' + ($PwshPath -replace '\\','\\\\') + '","artifact_root":"' + ($artRoot -replace '\\','\\\\') + '","tasks":[{"id":"w","text":"MOCK a=tiny:animal jacc=animal | z"}]}'
$rep = & $PwshPath -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -SkillDir $moduleRoot -PwshPath $PwshPath -ArtifactRoot $artRoot -InputsJson $inJson
$repObj = ([string]($rep | Out-String)).Trim() | ConvertFrom-Json
Check 'wrapper manifest_valid + envelope_valid' ($repObj.manifest_valid -eq $true -and $repObj.envelope_valid -eq $true)
Check 'wrapper ran logic.escalator' ($repObj.envelope.skill_id -eq 'logic.escalator')

# ============================ LIVE (real gateway) ============================
if ($Live) {
    if ([string]::IsNullOrWhiteSpace($RealGatewayPath)) { $RealGatewayPath = Join-Path $modulesDir '07-model-gateway/Invoke-ModelGateway.ps1' }
    function RunLive([string]$inputsJson) {
        $a = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry,
               '-GatewayPath',$RealGatewayPath,'-PwshPath',$PwshPath,'-ArtifactRoot',(Join-Path $work 'live'),'-InputsJson',$inputsJson)
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $o = & $PwshPath @a
        $script:code = $LASTEXITCODE; $ErrorActionPreference = $prev
        return ([string]($o | Out-String)).Trim()
    }
    # a real, easy classify task through the two smallest real tiers
    $lv = RunLive '{"kind":"classify","labels":["animal","vehicle","food"],"tiers":["tiny","weak"],"samples":1,"tasks":[{"id":"lv1","text":"a golden retriever puppy playing in the yard"}]}'
    $lvE = Env2 $lv
    Check 'LIVE envelope validates' ([bool](Test-SkillResultEnvelope -Json $lv).valid)
    $lvT = Task0 $lvE
    Check 'LIVE task resolved to a real tier + a real answer' ($lvT.accepted_tier -in @('tiny','weak') -and -not [string]::IsNullOrWhiteSpace([string]$lvT.answer) -and $lvT.status -eq 'ok')
    Check 'LIVE provenance carries a real model_id' (@($lvE.model_provenance).Count -ge 1 -and -not [string]::IsNullOrWhiteSpace([string](@($lvE.model_provenance)[0].model_id)))
    Start-Sleep -Seconds 3
    $orphans = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue)
    Check 'LIVE no orphaned llama-server' ($orphans.Count -eq 0)
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
if ($script:fail -eq 0) { [Console]::Out.WriteLine('ALL TESTS PASSED'); exit 0 } else { [Console]::Out.WriteLine("$($script:fail) TEST(S) FAILED"); exit 1 }
