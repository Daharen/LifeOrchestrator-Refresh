#requires -Version 7.0
<#
  Invoke-SetupTests.ps1 -- dual-mode test harness for the ops/setup portability toolkit
  (FANOUT_AGENT_002, plan fo-14-5ea064b6).

    (default)  MOCK / cloud gate: all pure logic with MOCK inputs (fake nvidia-smi strings,
               fake prereq probes, a fixture base models.json). Runs green in cloud pwsh 7.4.6
               on Linux -- Windows-only probes degrade, never throw.
    -Live      ADD on-device checks: real prereq probe (expects Windows + GPU), the real
               executor heartbeat, real root detection.

  Also AST-parses every shipped .ps1 AND .psm1 (dev.ship only AST-checks .ps1).
  Emits a TEST SUMMARY line + a machine-readable trailer; exit code 0 iff all assertions pass.
#>
[CmdletBinding()]
param([switch]$Live, [string]$PwshExe, [string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleDir = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $moduleDir 'LifeorchConfig.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleDir 'LifeorchSetup.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleDir 'LifeorchStagingConfirm.psm1') -Force -DisableNameChecking

$script:pass = 0
$script:fail = 0
$script:failures = New-Object System.Collections.Generic.List[string]
function Ok([bool]$cond, [string]$name) {
    if ($cond) { $script:pass++ } else { $script:fail++; $script:failures.Add($name); [Console]::Error.WriteLine("  FAIL: $name") }
}
function Eq($actual, $expected, [string]$name) { Ok ($actual -eq $expected) ("$name (got '$actual' want '$expected')") }

$pwsh = if (-not [string]::IsNullOrWhiteSpace($PwshExe)) { $PwshExe } else {
    $exe = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $cand = Join-Path $PSHOME $exe
    if (Test-Path -LiteralPath $cand) { $cand } else { 'pwsh' }
}
$fixture = Join-Path $PSScriptRoot 'fixtures/base-models.sample.json'
function Run-Setup([string[]]$argv) {
    $setup = Join-Path $moduleDir 'setup.ps1'
    $out = & $pwsh -NoProfile -File $setup @argv 2>$null | Out-String
    if ([string]::IsNullOrWhiteSpace($out)) { return $null }
    return ($out | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# 1. JSON-schema subset validator
# ---------------------------------------------------------------------------
$schema = [pscustomobject]@{ type = 'object'; required = @('a', 'b'); properties = [pscustomobject]@{
        a = [pscustomobject]@{ type = 'string' }
        b = [pscustomobject]@{ type = @('integer', 'null'); minimum = 0 }
        c = [pscustomobject]@{ type = 'string'; enum = @('x', 'y') }
    } }
Ok ((Test-JsonAgainstSchema -Instance ([pscustomobject]@{ a = 'hi'; b = 5 }) -Schema $schema).valid) 'schema: valid object passes'
Ok (-not (Test-JsonAgainstSchema -Instance ([pscustomobject]@{ a = 'hi' }) -Schema $schema).valid) 'schema: missing required fails'
Ok (-not (Test-JsonAgainstSchema -Instance ([pscustomobject]@{ a = 5; b = 5 }) -Schema $schema).valid) 'schema: wrong type fails'
Ok ((Test-JsonAgainstSchema -Instance ([pscustomobject]@{ a = 'hi'; b = $null }) -Schema $schema).valid) 'schema: null in union passes'
Ok (-not (Test-JsonAgainstSchema -Instance ([pscustomobject]@{ a = 'hi'; b = 5; c = 'z' }) -Schema $schema).valid) 'schema: bad enum fails'
Ok (-not (Test-JsonAgainstSchema -Instance ([pscustomobject]@{ a = 'hi'; b = -1 }) -Schema $schema).valid) 'schema: below minimum fails'

# real schema files parse + validate a good instance
$cfgSchema = (Get-Content -LiteralPath (Join-Path $moduleDir 'config.schema.json') -Raw) | ConvertFrom-Json
Ok ($null -ne $cfgSchema) 'schema: config.schema.json parses'
$mdlSchema = (Get-Content -LiteralPath (Join-Path $moduleDir 'models.schema.json') -Raw) | ConvertFrom-Json
Ok ($null -ne $mdlSchema) 'schema: models.schema.json parses'

# ---------------------------------------------------------------------------
# 2. nvidia-smi parser
# ---------------------------------------------------------------------------
$g1 = ConvertFrom-NvidiaSmi -Text 'NVIDIA GeForce RTX 2080 Ti, 11264'
Ok ($g1.present) 'nvidia: present on normal line'
Eq $g1.name 'NVIDIA GeForce RTX 2080 Ti' 'nvidia: name parsed'
Eq $g1.vram_total_mib 11264 'nvidia: vram parsed'
$g2 = ConvertFrom-NvidiaSmi -Text ''
Ok (-not $g2.present) 'nvidia: empty -> not present'
$g3 = ConvertFrom-NvidiaSmi -Text "name, memory.total`nNVIDIA A, 8192`nNVIDIA B, 24576"
Ok ($g3.present) 'nvidia: header tolerated, multi-gpu present'
Eq $g3.vram_total_mib 8192 'nvidia: takes first gpu'
Eq (@($g3.all).Count) 2 'nvidia: reports all gpus'
$g4 = ConvertFrom-NvidiaSmi -Text 'Some GPU, 12288 MiB'
Eq $g4.vram_total_mib 12288 'nvidia: units suffix stripped'

# ---------------------------------------------------------------------------
# 3. machine profile (mock) never throws + carries gpu
# ---------------------------------------------------------------------------
$mp = Get-LifeorchMachineProfile -MockNvidiaSmiText 'NVIDIA GeForce RTX 2080 Ti, 11264'
Ok ($mp.gpu.present) 'profile: mock gpu present'
Ok ($mp.PSObject.Properties.Name -contains 'is_windows') 'profile: has is_windows'
$mp0 = Get-LifeorchMachineProfile -MockNvidiaSmiText ''
Ok (-not $mp0.gpu.present) 'profile: empty gpu mock -> not present'

# ---------------------------------------------------------------------------
# 4. root detection
# ---------------------------------------------------------------------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('lo-setup-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'repo/ops/setup') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'repo/modules/00-bootstrap-executor/runtime/control') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'data') | Out-Null
$fakeRepo = Join-Path $tmp 'repo'
$fakeData = Join-Path $tmp 'data'
$rr = Get-LifeorchRepoRoot -ModuleRoot (Join-Path $fakeRepo 'ops/setup')
Eq ((Resolve-Path -LiteralPath $rr.path).Path) ((Resolve-Path -LiteralPath $fakeRepo).Path) 'repo-root: derived from module location (up two)'
Ok ($rr.source -eq 'module-location') 'repo-root: source marker found (has modules/)'
$dr = Get-LifeorchDataRoot -Hint $fakeData
Eq ((Resolve-Path -LiteralPath $dr.path).Path) ((Resolve-Path -LiteralPath $fakeData).Path) 'data-root: hint honored'
# Invariant (environment-independent: on a box where the default F: candidate exists it resolves to it;
# where nothing exists it returns null): Get-LifeorchDataRoot NEVER returns a non-existent path.
$drU = Get-LifeorchDataRoot -Hint (Join-Path $tmp 'nope') -RepoRoot $fakeRepo
Ok (($null -eq $drU.path) -or (Test-Path -LiteralPath $drU.path -PathType Container)) 'data-root: never returns a non-existent path'

# ---------------------------------------------------------------------------
# 5. Resolve + Write + Test config
# ---------------------------------------------------------------------------
$cfgOut = Join-Path $tmp 'config.json'
$wc = Write-LifeorchConfig -OutPath $cfgOut -RepoRoot $fakeRepo -DataRoot $fakeData -MockNvidiaSmiText 'NVIDIA GeForce RTX 2080 Ti, 11264'
Ok ($wc.valid) 'config: written config.json is schema-valid'
Ok (Test-Path -LiteralPath $cfgOut) 'config: file written'
$readBack = (Get-Content -LiteralPath $cfgOut -Raw) | ConvertFrom-Json
Eq $readBack.repo_root ((Resolve-Path -LiteralPath $fakeRepo).Path) 'config: repo_root captured'
Eq $readBack.machine.gpu.vram_total_mib 11264 'config: gpu vram captured'
$rc = Resolve-LifeorchConfig -ConfigPath $cfgOut
Eq $rc.provenance.from_file $true 'config: Resolve reads existing config.json'
Ok ((Test-LifeorchConfig -Config $cfgOut).valid) 'config: Test-LifeorchConfig on file valid'
$badCfg = [pscustomobject]@{ schema = 'lifeorch.setup.config/0.1'; repo_root = 'x' }  # missing data_root+machine
Ok (-not (Test-LifeorchConfig -Config $badCfg).valid) 'config: invalid config rejected'

# ---------------------------------------------------------------------------
# 6. prereq judge (pure) -- mock probes
# ---------------------------------------------------------------------------
$winProbe = [pscustomobject]@{ is_windows = $true; pwsh_version = [version]'7.4.6'; git_version = 'git version 2.43'; dotnet_version = '9.0.100'; curl_exe_present = $true; nvidia_smi_present = $true; gpu = (ConvertFrom-NvidiaSmi -Text 'NVIDIA GeForce RTX 2080 Ti, 11264') }
$rp = ConvertTo-PrereqReport -Probe $winProbe
Ok ($rp.ok) 'prereq: full windows probe ok'
Eq $rp.summary.fail 0 'prereq: no fails on good windows probe'
$badProbe = [pscustomobject]@{ is_windows = $true; pwsh_version = [version]'7.2.0'; git_version = $null; dotnet_version = $null; curl_exe_present = $false; nvidia_smi_present = $false; gpu = (ConvertFrom-NvidiaSmi -Text '') }
$rpb = ConvertTo-PrereqReport -Probe $badProbe
Ok (-not $rpb.ok) 'prereq: bad windows probe fails'
Ok ($rpb.summary.fail -ge 4) 'prereq: multiple fails counted'
$linProbe = [pscustomobject]@{ is_windows = $false; pwsh_version = [version]'7.4.6'; git_version = 'git version 2.43'; dotnet_version = '9.0.100' }
$rpl = ConvertTo-PrereqReport -Probe $linProbe
Ok ($rpl.ok) 'prereq: off-windows ok (curl/cuda degrade to unknown, not fail)'
Ok ((@($rpl.checks | Where-Object { $_.name -in @('curl_exe', 'cuda_driver') -and $_.status -eq 'unknown' })).Count -eq 2) 'prereq: curl/cuda unknown off-windows'

# ---------------------------------------------------------------------------
# 7. gpu-layer plan
# ---------------------------------------------------------------------------
$p9full = Get-LoGpuLayerPlan -WeightMib 6782 -ContextTokens 8192 -BudgetMib 10240 -EstLayers 48 -ParamsB 9
Ok ($p9full.fits_fully -and $p9full.gpu_layers -eq 99) 'plan: 9B Q5 fits fully on 11GB budget (ngl 99)'
$p9small = Get-LoGpuLayerPlan -WeightMib 6782 -ContextTokens 8192 -BudgetMib 4096 -EstLayers 48 -ParamsB 9
Ok ((-not $p9small.fits_fully) -and $p9small.gpu_layers -lt 99 -and $p9small.gpu_layers -ge 0) 'plan: 9B partial on a small card'
$pTiny = Get-LoGpuLayerPlan -WeightMib 940 -ContextTokens 4096 -BudgetMib 10240 -EstLayers 28 -ParamsB 1.5
Ok ($pTiny.gpu_layers -eq 99) 'plan: small model always full on 11GB'

# ---------------------------------------------------------------------------
# 8. models.json generation (fixture)
# ---------------------------------------------------------------------------
$baseReg = (Get-Content -LiteralPath $fixture -Raw) | ConvertFrom-Json
$newRoot = 'G:\NewData\LifeOrch_Large'
$gen = New-MachineModelsJson -BaseRegistry $baseReg -VramMiB 11264 -DataRoot $newRoot -HostName 'NEWBOX'
Ok ((Test-MachineModelsJson -Registry $gen).valid) 'gen: machine registry schema-valid'
$nine = @($gen.models | Where-Object { $_.model_id -eq 'llm.strong.qwen3p5-9b' })[0]
Ok ($nine.path.StartsWith($newRoot)) 'gen: model path repointed to new data-root'
Ok ($nine.engine_path.StartsWith($newRoot)) 'gen: engine_path repointed'
Ok ($gen.engines.'llama-server'.StartsWith($newRoot)) 'gen: engines path repointed'
Eq $gen._generated.strong_pick 'llm.strong.qwen3p5-9b' 'gen: strong pick = Q5 on 11GB'
Eq $gen.tiers.llm.strong 'llm.strong.qwen3p5-9b' 'gen: tiers.llm.strong updated to pick'
Eq $nine.wired $true 'gen: Q5 wired true'
Eq (@($gen.models | Where-Object { $_.model_id -eq 'llm.strong.qwen3p5-9b-q4' })[0].wired) $false 'gen: Q4 wired false'
Ok ((@($gen.models | Where-Object { $_.model_id -eq 'llm.strong.qwen3p5-9b' })[0].gpu_layers) -eq 99) 'gen: 9B ngl 99 on 11GB'
Eq $gen.host 'NEWBOX' 'gen: host set'
Ok ($null -ne $gen._generated.sizing -and @($gen._generated.sizing).Count -ge 4) 'gen: sizing sidecar populated'
# input NOT mutated
Ok ($baseReg.models[0].path.StartsWith('F:\')) 'gen: input base registry NOT mutated (still F:)'
# C:\ path (ocr engine_env) untouched
$ocr = @($gen.models | Where-Object { $_.model_id -eq 'ocr.windows.media' })[0]
Ok ($ocr.engine_env.StartsWith('C:\')) 'gen: C:\ system path left untouched'
# small card -> Q4 pick + partial
$genSmall = New-MachineModelsJson -BaseRegistry $baseReg -VramMiB 6144 -DataRoot $newRoot
Eq $genSmall._generated.strong_pick 'llm.strong.qwen3p5-9b-q4' 'gen: small card falls back to Q4 strong pick'
Ok ((@($genSmall.models | Where-Object { $_.model_id -eq 'llm.strong.qwen3p5-9b-q4' })[0].gpu_layers) -lt 99) 'gen: small card 9B partial (<99)'

# ---------------------------------------------------------------------------
# 9. staging plan
# ---------------------------------------------------------------------------
$plan = New-StagingPlan -Registry $gen -DataRoot $newRoot
Ok ($plan -match 'curl\.exe') 'plan: emits curl.exe commands'
Ok ($plan -match 'Qwen_Qwen3\.5-9B-Q5_K_M\.gguf') 'plan: includes the 9B gguf filename'
Ok ($plan -match 'a686d88ec1e6881f9bf161526826cd6d6874b7f0e80e0f79acf6144a132c5d7e') 'plan: includes expected sha256'
Ok ($plan -match 'huggingface-cli') 'plan: multi-file diffusers model gets an hf-cli note'
Ok ($plan -match 'system component') 'plan: system OCR marked no-download'
Ok ($plan -match [regex]::Escape($newRoot)) 'plan: targets the new data-root'
Ok (-not ($plan -match 'TODO_CONFIRM_URL_for_[A-Za-z]:\\')) 'plan: TODO url uses bare filename, not a full path (separator-agnostic leaf)'
Ok ($plan -match 'huggingface\.co/ggml-org/Qwen2\.5-VL-3B-Instruct-GGUF/resolve/main/Qwen2\.5-VL-3B-Instruct-Q4_K_M\.gguf') 'plan: known VLM source map -> concrete resolve URL'
Ok ($plan -match 'mmproj-Qwen2\.5-VL-3B-Instruct-f16\.gguf') 'plan: VLM mmproj sidecar included'

# ---------------------------------------------------------------------------
# 10. heartbeat judge
# ---------------------------------------------------------------------------
$hbDir = Join-Path $fakeRepo 'modules/00-bootstrap-executor/runtime/control'
$hbPath = Join-Path $hbDir 'heartbeat.json'
$now = [datetime]::Parse('2026-07-29T12:00:30Z', $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
$freshHb = '{"instance_id":"abc","pid":1,"at_utc":"2026-07-29T12:00:00.0000000Z","degraded":false,"poll_error_streak":0,"stuck_finalize_count":0}'
[System.IO.File]::WriteAllText($hbPath, $freshHb, [System.Text.UTF8Encoding]::new($false))
$hb = Get-HeartbeatStatus -HeartbeatPath $hbPath -MaxAgeSeconds 120 -NowUtc $now
Ok ($hb.ok) 'heartbeat: fresh + healthy -> ok'
$hbStale = Get-HeartbeatStatus -HeartbeatPath $hbPath -MaxAgeSeconds 120 -NowUtc ([datetime]::Parse('2026-07-29T13:00:00Z', $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal))
Ok (-not $hbStale.ok -and -not $hbStale.fresh) 'heartbeat: stale -> not ok'
$degHb = '{"instance_id":"abc","pid":1,"at_utc":"2026-07-29T12:00:00.0000000Z","degraded":true,"poll_error_streak":0,"stuck_finalize_count":0}'
[System.IO.File]::WriteAllText($hbPath, $degHb, [System.Text.UTF8Encoding]::new($false))
$hbDeg = Get-HeartbeatStatus -HeartbeatPath $hbPath -MaxAgeSeconds 120 -NowUtc $now
Ok (-not $hbDeg.ok -and $hbDeg.degraded) 'heartbeat: degraded -> not ok'
$hbMiss = Get-HeartbeatStatus -HeartbeatPath (Join-Path $hbDir 'nope.json') -NowUtc $now
Ok (-not $hbMiss.ok -and -not $hbMiss.present) 'heartbeat: missing -> not present'

# ---------------------------------------------------------------------------
# 11. Invoke-SetupVerify (off-box, SkipHeartbeat) with a constructed repo
# ---------------------------------------------------------------------------
$genOutDir = Join-Path $fakeRepo 'ops/setup/out'
New-Item -ItemType Directory -Force -Path $genOutDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $genOutDir 'models.machine.json'), ($gen | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
$cfgObj = [pscustomobject]@{ schema = 'lifeorch.setup.config/0.1'; repo_root = (Resolve-Path -LiteralPath $fakeRepo).Path; data_root = (Resolve-Path -LiteralPath $fakeData).Path; machine = $mp; provenance = [pscustomobject]@{ repo_root = 'test'; data_root = 'test' } }
$vr = Invoke-SetupVerify -RepoRoot $fakeRepo -Config $cfgObj -SkipHeartbeat
Ok ($vr.ok) 'verify: constructed repo passes (SkipHeartbeat)'
Ok ((@($vr.checks | Where-Object { $_.name -eq 'repo_paths_exist' -and $_.status -eq 'pass' })).Count -eq 1) 'verify: repo paths exist'
Ok ((@($vr.checks | Where-Object { $_.name -eq 'models_machine_valid' -and $_.status -eq 'pass' })).Count -eq 1) 'verify: models.machine.json valid'

# ---------------------------------------------------------------------------
# 12. setup.ps1 end-to-end (child process, off-box)
# ---------------------------------------------------------------------------
$gres = Run-Setup @('-Action', 'gen', '-RepoRoot', $moduleDir, '-BaseModelsPath', $fixture, '-DataRoot', $newRoot, '-VramMiBOverride', '11264', '-MockNvidiaSmiText', 'NVIDIA GeForce RTX 2080 Ti, 11264', '-SkipHeartbeat')
Ok ($null -ne $gres) 'setup.ps1: gen emits JSON'
if ($null -ne $gres) {
    Ok ($gres.ok) 'setup.ps1: gen ok'
    Ok ($gres.generation.models_machine_valid) 'setup.ps1: generated models.machine.json valid'
    Eq $gres.generation.strong_pick 'llm.strong.qwen3p5-9b' 'setup.ps1: gen strong pick'
    Ok (Test-Path -LiteralPath $gres.generation.models_machine_path) 'setup.ps1: models.machine.json written'
    Ok (Test-Path -LiteralPath $gres.generation.staging_plan_path) 'setup.ps1: staging plan written'
}
$vres = Run-Setup @('-Action', 'verify', '-RepoRoot', $fakeRepo, '-DataRoot', $fakeData, '-SkipHeartbeat')
Ok ($null -ne $vres -and $vres.verify.ok) 'setup.ps1: verify ok on constructed repo'

# ---------------------------------------------------------------------------
# 13. AST-parse every shipped .ps1 AND .psm1 (mission requires both; dev.ship only does .ps1)
# ---------------------------------------------------------------------------
$astErrs = 0
foreach ($f in (Get-ChildItem -LiteralPath $moduleDir -Recurse -Include '*.ps1', '*.psm1' -File)) {
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    if ($null -ne $e -and $e.Count -gt 0) { $astErrs += $e.Count; [Console]::Error.WriteLine("  AST FAIL $($f.Name): $($e[0].Message)") }
}
Ok ($astErrs -eq 0) 'ast: all .ps1/.psm1 parse clean'

# ---------------------------------------------------------------------------
# 14. staging-plan CONFIRM -- parser + guarded HEAD probe + confirm object (mock/offline).
#     Reuses $plan (the real New-StagingPlan output from section 9); NO network here.
# ---------------------------------------------------------------------------
$parsedPlan = ConvertFrom-StagingPlan -Text $plan
Ok ($parsedPlan.well_formed) 'confirm: plan parses well-formed'
Ok (@($parsedPlan.entries).Count -ge 6) 'confirm: parses multiple entries'
Ok (-not [string]::IsNullOrWhiteSpace($parsedPlan.data_root)) 'confirm: data-root header parsed'
$vlmE = @($parsedPlan.entries | Where-Object { $_.id -eq 'vlm.qwen2p5-vl-3b' -and -not $_.sidecar })
Ok ($vlmE.Count -ge 1 -and (-not $vlmE[0].url_placeholder) -and ($vlmE[0].url -match '^https://')) 'confirm: VLM entry has a concrete https URL'
Ok ($vlmE[0].has_sha256) 'confirm: VLM entry carries an expected sha256'
Ok (@($parsedPlan.entries | Where-Object { $_.kind -eq 'single-file' -and $_.url_placeholder }).Count -ge 1) 'confirm: TODO_CONFIRM urls flagged as placeholder'
Ok (@($parsedPlan.entries | Where-Object { $_.kind -eq 'single-file' -and -not $_.has_sha256 }).Count -ge 1) 'confirm: missing-sha256 entries detected'
Ok (@($parsedPlan.entries | Where-Object { $_.kind -eq 'multi-file' }).Count -ge 1) 'confirm: multi-file diffusers entry parsed'
Ok (@($parsedPlan.entries | Where-Object { $_.kind -eq 'system' }).Count -ge 1) 'confirm: system OCR entry parsed (no download)'
Ok (@($parsedPlan.entries | Where-Object { $_.kind -eq 'executable' }).Count -ge 1) 'confirm: executable entry parsed'
Ok (@($parsedPlan.engines).Count -ge 1) 'confirm: engines block parsed'

# guarded HEAD probe judgments (no network: placeholder / mock / offline)
Eq (Invoke-LoHeadProbe -Url 'TODO_CONFIRM_URL_for_x.gguf').status 'placeholder' 'confirm: TODO url not probed (placeholder)'
Eq (Invoke-LoHeadProbe -Url 'https://example.invalid/x' -Offline).status 'offline' 'confirm: -Offline probe returns offline (degrade, no throw)'
$pm = Invoke-LoHeadProbe -Url 'https://h/f.gguf' -MockResults @{ 'https://h/f.gguf' = @{ status_code = 200; content_length = 123 } }
Ok ($pm.status -eq 'reachable' -and $pm.content_length -eq 123) 'confirm: mock 200 -> reachable + advertised size'
Eq (Invoke-LoHeadProbe -Url 'https://h/f.gguf' -MockResults @{ 'https://h/f.gguf' = @{ status_code = 404 } }).status 'dead' 'confirm: mock 404 -> dead'

# full confirm object: mock (reachable), dead-link (ok flips), offline (degrades)
$vlmUrl = $vlmE[0].url
$cfMock = Confirm-StagingPlan -PlanText $plan -MockResults @{ $vlmUrl = @{ status_code = 200; content_length = 1929000000 } }
Ok ($cfMock.well_formed -and $cfMock.ok) 'confirm: mock confirm well-formed + ok'
Ok ($cfMock.summary.url_reachable -ge 1) 'confirm: VLM counted reachable'
Ok ($cfMock.summary.url_placeholder -ge 1) 'confirm: placeholder urls counted in summary'
Ok ($cfMock.summary.actionable_now -ge 1) 'confirm: actionable_now computed (real url + sha + reachable)'
$cfDead = Confirm-StagingPlan -PlanText $plan -MockResults @{ $vlmUrl = @{ status_code = 404 } }
Ok (-not $cfDead.ok) 'confirm: a dead real URL flips ok=false'
Ok (@($cfDead.blockers).Count -ge 1) 'confirm: blockers listed'
$cfOff = Confirm-StagingPlan -PlanText $plan -Offline
Ok ($cfOff.well_formed -and $cfOff.probe_mode -eq 'offline') 'confirm: offline degrades cleanly (well-formed, mode=offline)'
Ok ($cfOff.ok) 'confirm: offline does NOT fail ok (degraded-but-valid)'
Ok ($cfOff.summary.url_offline -ge 1) 'confirm: offline urls counted, nothing thrown'

# ---------------------------------------------------------------------------
# 15. resolver adoption -- additive Resolve-LifeorchConfig shim wired into a bounded LEAF
#     batch (14-ocr-layout, 16-detect-objects). Proves: shim present + AST-clean + resolves
#     byte-identically to the untouched walk-up on this box + a config override genuinely wins.
# ---------------------------------------------------------------------------
$repoRootForTest = Split-Path -Parent (Split-Path -Parent $moduleDir)   # ops/setup -> ops -> repo
$wiredModules = @(
    (Join-Path $repoRootForTest 'modules/14-ocr-layout/Invoke-OcrLayout.ps1'),
    (Join-Path $repoRootForTest 'modules/16-detect-objects/Invoke-DetectObjects.ps1')
)
function Get-ResolveRepoRootText([string]$path) {
    $tk = $null; $er = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tk, [ref]$er)
    if ($null -ne $er -and $er.Count -gt 0) { return $null }
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-RepoRoot' }, $true)
    if ($null -eq $fn) { return $null }
    return $fn.Extent.Text
}
function Invoke-PureWalk([string]$s) {
    try { $d = Get-Item -LiteralPath $s -ErrorAction Stop; for ($i = 0; $i -lt 8 -and $null -ne $d; $i++) { if (Test-Path -LiteralPath (Join-Path $d.FullName 'core-docs')) { return $d.FullName }; $d = $d.Parent } } catch { }
    return $null
}
foreach ($wf in $wiredModules) {
    $tag = Split-Path -Leaf (Split-Path -Parent $wf)
    if (-not (Test-Path -LiteralPath $wf)) { Ok $false "resolver[$tag]: wired module file present"; continue }
    Ok $true "resolver[$tag]: wired module file present"
    $tk = $null; $er = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($wf, [ref]$tk, [ref]$er)
    Ok (($null -eq $er) -or ($er.Count -eq 0)) "resolver[$tag]: file AST-parses clean"
    $src = Get-Content -LiteralPath $wf -Raw
    Ok ($src -match 'Resolve-LifeorchConfig') "resolver[$tag]: Resolve-LifeorchConfig wired in (not reverted)"
    Ok ($src -match 'FANOUT_AGENT_002') "resolver[$tag]: additive-shim provenance marker present"
    $ftext = Get-ResolveRepoRootText $wf
    Ok ($null -ne $ftext) "resolver[$tag]: Resolve-RepoRoot extractable"
    if ($null -ne $ftext) {
        . ([scriptblock]::Create($ftext))
        $mdir = Split-Path -Parent $wf
        $resolved = Resolve-RepoRoot $mdir
        $walk = Invoke-PureWalk $mdir
        Ok (-not [string]::IsNullOrWhiteSpace($resolved)) "resolver[$tag]: resolves a repo-root"
        Eq $resolved $walk "resolver[$tag]: resolved == untouched walk-up (byte-identical on this box)"
        Ok (Test-Path -LiteralPath (Join-Path $resolved 'core-docs')) "resolver[$tag]: resolved root has the core-docs marker"
    }
}
# override proof: a machine config.json pointing at a DIFFERENT real repo WINS over the walk-up
# (proves Resolve-LifeorchConfig is genuinely consulted -- the portability seam, not dead code).
$ovr = Join-Path ([System.IO.Path]::GetTempPath()) ('lo-ovr-' + [Guid]::NewGuid().ToString('N'))
foreach ($r in @('repoA', 'repoB')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $ovr "$r/core-docs") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $ovr "$r/ops/setup") | Out-Null
    Copy-Item (Join-Path $moduleDir 'LifeorchConfig.psm1') (Join-Path $ovr "$r/ops/setup/LifeorchConfig.psm1")
}
New-Item -ItemType Directory -Force -Path (Join-Path $ovr 'repoA/modules/99-x') | Out-Null
$repoB = (Resolve-Path (Join-Path $ovr 'repoB')).Path
$cfgJson = ([pscustomobject]@{ schema = 'lifeorch.setup.config/0.1'; repo_root = $repoB; data_root = 'x'; machine = [pscustomobject]@{} } | ConvertTo-Json -Depth 6)
[System.IO.File]::WriteAllText((Join-Path $ovr 'repoA/ops/setup/config.json'), $cfgJson, [System.Text.UTF8Encoding]::new($false))
$modA = (Resolve-Path (Join-Path $ovr 'repoA/modules/99-x')).Path
$ovrResolved = Resolve-RepoRoot $modA   # Resolve-RepoRoot = the shim extracted just above
Eq $ovrResolved $repoB 'resolver: machine config repo_root OVERRIDES the walk-up (portability seam works)'
try { Remove-Item -LiteralPath $ovr -Recurse -Force -ErrorAction SilentlyContinue } catch { }

# ---------------------------------------------------------------------------
# LIVE (on-device) checks
# ---------------------------------------------------------------------------
if ($Live) {
    [Console]::Error.WriteLine('--- LIVE (on-device) ---')
    $lp = Get-LifeorchPrereqReport
    Ok ($lp.is_windows) 'live: running on Windows'
    Ok ((@($lp.checks | Where-Object { $_.name -eq 'pwsh' -and $_.status -eq 'pass' })).Count -eq 1) 'live: pwsh >= 7.4'
    Ok ((@($lp.checks | Where-Object { $_.name -eq 'git' -and $_.status -eq 'pass' })).Count -eq 1) 'live: git present'
    Ok ((@($lp.checks | Where-Object { $_.name -eq 'dotnet_sdk' -and $_.status -eq 'pass' })).Count -eq 1) 'live: .NET SDK present'
    Ok ((@($lp.checks | Where-Object { $_.name -eq 'curl_exe' -and $_.status -eq 'pass' })).Count -eq 1) 'live: curl.exe present'
    Ok ((@($lp.checks | Where-Object { $_.name -eq 'cuda_driver' -and $_.status -eq 'pass' })).Count -eq 1) 'live: CUDA/nvidia-smi + GPU detected'
    Ok ($lp.ok) 'live: prereq overall ok'

    $liveRepo = if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot } else { (Get-LifeorchRepoRoot).path }
    $lcfg = Resolve-LifeorchConfig -RepoRoot $liveRepo -Detect
    Ok (-not [string]::IsNullOrWhiteSpace($lcfg.repo_root)) 'live: repo_root resolves'
    $lhb = Join-Path $liveRepo 'modules/00-bootstrap-executor/runtime/control/heartbeat.json'
    $lhbs = Get-HeartbeatStatus -HeartbeatPath $lhb
    Ok ($lhbs.present -and -not $lhbs.degraded) 'live: executor heartbeat present + not degraded'
    $lv = Invoke-SetupVerify -RepoRoot $liveRepo
    Ok ($lv.ok) 'live: full verify (incl heartbeat) ok'

    # wired resolution == literal on this box: config repo_root == the actual repo location
    $cfgRepo = [string](Resolve-LifeorchConfig).repo_root
    Ok ((-not [string]::IsNullOrWhiteSpace($cfgRepo)) -and ((Get-Item -LiteralPath $cfgRepo).FullName -ieq (Get-Item -LiteralPath $repoRootForTest).FullName)) 'live: config repo_root == actual repo location (wired resolution == literal on this box)'
    # live staging-plan confirm on the emitted out/staging-plan.txt (offline: no multi-GB pulls in-test)
    $livePlan = Join-Path $repoRootForTest 'ops/setup/out/staging-plan.txt'
    if (Test-Path -LiteralPath $livePlan) {
        $cfLive = Confirm-StagingPlan -PlanPath $livePlan -Offline
        Ok ($cfLive.well_formed) 'live: emitted staging-plan.txt confirms well-formed (offline)'
    } else { Ok $true 'live: (no out/staging-plan.txt emitted yet -- run setup.ps1 -Action gen)' }
}

# cleanup
try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch {}

$total = $script:pass + $script:fail
[Console]::Out.WriteLine("TEST SUMMARY: $($script:pass)/$total passed; $($script:fail) failed. mode=$(if($Live){'live'}else{'mock'})")
[Console]::Out.WriteLine("SETUPTESTS_RESULT pass=$($script:pass) fail=$($script:fail) total=$total")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
