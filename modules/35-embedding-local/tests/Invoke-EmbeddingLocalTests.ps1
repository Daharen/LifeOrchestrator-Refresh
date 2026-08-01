#requires -Version 7.0
<#
  Tests for embedding.local (Module 35).

  DEFAULT (off-machine, portable): runs the skill in -Mock mode (deterministic seeded-numpy worker, NO
  torch/model/GPU/lease) and asserts the PORTABLE seams -- schema/shape/normalization/input-order/empty/
  oversize/batch==single/determinism. Runs anywhere pwsh 7 + a python3 exist (cloud Linux included).

  -Live (on the Windows executor / 2080 Ti): additionally runs the REAL model and asserts dim=1024,
  normalized unit vectors, model/sha/engine provenance, batch==single within tolerance, repeat-run
  determinism within tolerance, a similarity-ORDER fact (near pair ranks above a far pair), a CPU-fallback
  feasibility probe, and 0 UNMANAGED embed_worker orphans. Prints measured latency / peak VRAM / tolerances.

  Params: -Skill <Invoke-EmbeddingLocal.ps1>  -PythonExe <python>  -Live  -Device <cuda|cpu>  -Tol <double>
#>
[CmdletBinding()]
param(
    [string]$Skill,
    [string]$PythonExe = 'python3',
    [switch]$Live,
    [string]$Device = 'cuda',
    [double]$Tol = 1e-3,
    [string]$GpuLeaseHolder = 'EMBED-ADAPTER-i25-test'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Skill)) { $Skill = Join-Path (Split-Path $testDir -Parent) 'Invoke-EmbeddingLocal.ps1' }
$moduleDir = Split-Path $Skill -Parent
$manifest = Join-Path $moduleDir 'skill.json'

$PwshExe = try { (Get-Process -Id $PID).Path } catch { $null }
if ([string]::IsNullOrWhiteSpace($PwshExe) -or $PwshExe -match 'dotnet') {
    $exeName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $PwshExe = if ($PSHOME) { Join-Path $PSHOME $exeName } else { 'pwsh' }
}

$pass = 0; $fail = 0; $failed = [System.Collections.Generic.List[string]]::new()
function Ok([bool]$c, [string]$name) {
    if ($c) { $script:pass++; Write-Host "  PASS  $name" }
    else { $script:fail++; $script:failed.Add($name); Write-Host "  FAIL  $name" -ForegroundColor Red }
}
function Norm($v) { if ($null -eq $v) { return $null } $s = 0.0; foreach ($x in $v) { $s += [double]$x * [double]$x }; return [math]::Sqrt($s) }
function Dot($a, $b) { $s = 0.0; for ($i = 0; $i -lt $a.Count; $i++) { $s += [double]$a[$i] * [double]$b[$i] }; return $s }
function Cos($a, $b) { $na = Norm $a; $nb = Norm $b; if ($na -eq 0 -or $nb -eq 0) { return 0 } return (Dot $a $b) / ($na * $nb) }
function MaxAbsDiff($a, $b) { $m = 0.0; for ($i = 0; $i -lt $a.Count; $i++) { $d = [math]::Abs([double]$a[$i] - [double]$b[$i]); if ($d -gt $m) { $m = $d } }; return $m }

function Invoke-Embed([hashtable]$named) {
    $argv = @('-NoProfile', '-NonInteractive', '-File', $Skill)
    foreach ($k in $named.Keys) {
        $v = $named[$k]
        if ($v -is [switch] -or $v -is [bool]) { if ([bool]$v) { $argv += "-$k" } else { $argv += "-${k}:`$false" } }
        else { $argv += "-$k"; $argv += "$v" }
    }
    $tmpErr = New-TemporaryFile
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $PwshExe @argv 2> $tmpErr.FullName } finally { $ErrorActionPreference = $prev }
    Remove-Item -LiteralPath $tmpErr.FullName -Force -ErrorAction SilentlyContinue
    $text = ($out | Out-String)
    try { return ($text | ConvertFrom-Json) } catch { Write-Host "NON-JSON OUTPUT:`n$text" -ForegroundColor Yellow; return $null }
}
# Batch via -InputsJson so multi-text ordering is unambiguous.
function Embed-Texts([string[]]$texts, [bool]$normalize, [hashtable]$extra) {
    # mock vs real is decided EXPLICITLY by the caller via $extra['mock'] -- the mock SEAM section always sets
    # mock=true (even under -Live); the LIVE section passes $LV (no mock) for the real model.
    $body = @{ texts = $texts; normalize = $normalize }
    foreach ($k in $extra.Keys) { $body[$k] = $extra[$k] }
    $json = ($body | ConvertTo-Json -Depth 6 -Compress)
    return Invoke-Embed @{ InputsJson = $json; PythonExe = $PythonExe }
}

Write-Host "=== embedding.local tests (Live=$Live Device=$Device) ==="

# ---- manifest ----
$mf = $null; try { $mf = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json } catch { }
Ok ($null -ne $mf) 'manifest: valid JSON'
if ($null -ne $mf) {
    Ok ($mf.skill_id -eq 'embedding.local') 'manifest: skill_id'
    Ok ($mf.version -eq '0.1.0') 'manifest: version 0.1.0'
    Ok ($mf.batch -eq $true) 'manifest: batch true'
    Ok ($mf.parallel_safe -eq $false) 'manifest: parallel_safe false (GPU/lease)'
    Ok ($null -ne $mf.invocation.python_worker) 'manifest: names python_worker'
}

$MOCK = @{ Mock = $true; GpuLease = 'off' }

# ---- 1: single text ----
$r = Invoke-Embed (@{ Text = 'hello world'; PythonExe = $PythonExe } + $MOCK)
Ok ($null -ne $r -and $r.schema -eq 'lifeorch.skill.result/0.1') 'single: envelope schema'
Ok ($r.status -eq 'ok') 'single: status ok'
Ok ($r.result.op -eq 'embed') 'single: op=embed'
Ok ($r.result.count -eq 1) 'single: count 1'
$v0 = @($r.result.vectors)
Ok ($v0.Count -eq 1) 'single: one vector'
Ok (@($v0[0]).Count -eq $r.result.dim -and $r.result.dim -gt 0) 'single: vector dim matches result.dim'
Ok ([math]::Abs((Norm $v0[0]) - 1.0) -lt 1e-6) 'single: normalized unit length'

# ---- 2: normalize:false raw ----
$r = Invoke-Embed (@{ Text = 'hello world'; Normalize = $false; PythonExe = $PythonExe } + $MOCK)
Ok ([math]::Abs((Norm @($r.result.vectors)[0]) - 1.0) -gt 0.01) 'raw: normalize:false not unit length'

# ---- 3: batch order + batch==single (mock deterministic => exact) ----
$texts = @('alpha one', 'bravo two words here', 'charlie')
$rb = Embed-Texts $texts $true @{ mock = $true }
Ok ($rb.result.count -eq 3) 'batch: count 3'
$vb = @($rb.result.vectors)
Ok ($vb.Count -eq 3) 'batch: three vectors'
$allExact = $true
for ($i = 0; $i -lt 3; $i++) {
    $rs = Invoke-Embed (@{ Text = $texts[$i]; PythonExe = $PythonExe } + $MOCK)
    $vs = @($rs.result.vectors)[0]
    if ((MaxAbsDiff $vb[$i] $vs) -gt 1e-12) { $allExact = $false }
}
Ok $allExact 'batch==single: each batched vector equals its single-call vector (input order preserved)'

# ---- 4: input-order with an interior empty ----
$rm = Embed-Texts @('x-ray text', '   ', 'yankee text') $true @{ mock = $true }
$vm = @($rm.result.vectors); $pm = @($rm.result.per_input)
Ok ($pm[0].status -eq 'ok' -and $pm[1].status -eq 'empty' -and $pm[2].status -eq 'ok') 'empty: statuses [ok,empty,ok]'
Ok ($null -eq $vm[1]) 'empty: skipped vector is null'
Ok ($null -ne $vm[0] -and $null -ne $vm[2]) 'empty: neighbors present'
Ok ($rm.status -eq 'partial') 'empty: envelope status partial'

# ---- 5: oversize skip ----
$ro = Embed-Texts @('a b c d e f g h') $true @{ max_tokens = 3; mock = $true }
$po = @($ro.result.per_input)
Ok ($po[0].status -eq 'oversize') 'oversize: status oversize'
Ok ($null -eq @($ro.result.vectors)[0]) 'oversize: vector null'

# ---- 6: empty single ----
$re = Invoke-Embed (@{ Text = '    '; PythonExe = $PythonExe } + $MOCK)
Ok (@($re.result.per_input)[0].status -eq 'empty') 'empty-single: status empty'
Ok ($null -eq @($re.result.vectors)[0]) 'empty-single: vector null'

# ---- 7: determinism across invocations (mock exact) ----
$d1 = Invoke-Embed (@{ Text = 'determinism probe'; PythonExe = $PythonExe } + $MOCK)
$d2 = Invoke-Embed (@{ Text = 'determinism probe'; PythonExe = $PythonExe } + $MOCK)
Ok ((MaxAbsDiff @($d1.result.vectors)[0] @($d2.result.vectors)[0]) -eq 0.0) 'determinism: identical across two invocations'

# ================= LIVE (real model on the box) =================
if ($Live) {
    Write-Host "--- LIVE real-model checks ---"
    $LV = @{ Device = $Device; PythonExe = $PythonExe; GpuLeaseHolder = $GpuLeaseHolder }
    if ($Device -eq 'cpu') { $LV['GpuLease'] = 'off' }

    $r = Invoke-Embed (@{ Text = 'The Life Orchestrator indexes its own repository.' } + $LV)
    Ok ($null -ne $r -and $r.status -eq 'ok') 'live: single status ok'
    Ok ($r.result.dim -eq 1024) "live: dim 1024 (got $($r.result.dim))"
    Ok ($r.result.pooling -eq 'last_token') 'live: pooling last_token'
    Ok ([math]::Abs((Norm @($r.result.vectors)[0]) - 1.0) -lt 1e-4) 'live: normalized unit length'
    Ok (-not [string]::IsNullOrWhiteSpace($r.result.model_sha256)) 'live: model_sha256 recorded'
    Ok ($r.result.engine_build -like 'transformers-*') "live: engine_build recorded ($($r.result.engine_build))"
    Ok (@($r.model_provenance).Count -ge 1) 'live: model_provenance populated'
    Write-Host ("  MEASURE latency load_ms=$($r.result.timings.load_ms) embed_ms=$($r.result.timings.embed_ms) peak_vram_bytes=$($r.result.peak_vram_bytes) peak_ram_bytes=$($r.result.peak_ram_bytes)")

    # determinism repeat (two invocations)
    $a = Invoke-Embed (@{ Text = 'repeatable embedding input' } + $LV)
    $b = Invoke-Embed (@{ Text = 'repeatable embedding input' } + $LV)
    $dd = MaxAbsDiff @($a.result.vectors)[0] @($b.result.vectors)[0]
    $cosdd = 1.0 - (Cos @($a.result.vectors)[0] @($b.result.vectors)[0])
    Write-Host ("  MEASURE determinism max_abs_diff=$dd cos_dist=$cosdd")
    Ok ($cosdd -lt $Tol) "live: repeat-run determinism cos_dist < $Tol"

    # batch == single tolerance
    $bt = @('semantic memory retrieval', 'vector index over source chunks', 'the quick brown fox')
    $rB = Embed-Texts $bt $true $LV
    $okBatch = $true; $maxDiff = 0.0
    for ($i = 0; $i -lt $bt.Count; $i++) {
        $rs = Invoke-Embed (@{ Text = $bt[$i] } + $LV)
        $cd = 1.0 - (Cos @($rB.result.vectors)[$i] @($rs.result.vectors)[0])
        if ($cd -gt $maxDiff) { $maxDiff = $cd }
        if ($cd -ge $Tol) { $okBatch = $false }
    }
    Write-Host ("  MEASURE batch_vs_single max_cos_dist=$maxDiff")
    Ok $okBatch "live: batch==single per input (cos_dist < $Tol)"

    # similarity ORDER: near pair ranks above far pair
    $q = Invoke-Embed (@{ Text = 'The cat sat on the mat.' } + $LV)
    $near = Invoke-Embed (@{ Text = 'A feline rested on the rug.' } + $LV)
    $far = Invoke-Embed (@{ Text = 'Quarterly revenue exceeded the analysts forecast.' } + $LV)
    $cosNear = Cos @($q.result.vectors)[0] @($near.result.vectors)[0]
    $cosFar = Cos @($q.result.vectors)[0] @($far.result.vectors)[0]
    Write-Host ("  MEASURE similarity cos_near=$cosNear cos_far=$cosFar")
    Ok ($cosNear -gt $cosFar) 'live: similarity order (near > far)'

    # empty + oversize real
    $re2 = Invoke-Embed (@{ Text = '   ' } + $LV)
    Ok (@($re2.result.per_input)[0].status -eq 'empty') 'live: empty flagged'
    $ro2 = Embed-Texts @('one two three four five six seven eight nine ten') $true ($LV + @{ max_tokens = 4 })
    Ok (@($ro2.result.per_input)[0].status -eq 'oversize') 'live: oversize flagged'

    # CPU-fallback feasibility probe (governing sec 16.2): device=cpu, no gpu lease
    $rc = Invoke-Embed @{ Text = 'cpu fallback feasibility probe'; Device = 'cpu'; GpuLease = 'off'; PythonExe = $PythonExe }
    Ok ($null -ne $rc -and $rc.status -eq 'ok') 'live: CPU-fallback status ok'
    Ok ($rc.result.dim -eq 1024) 'live: CPU-fallback dim 1024'
    Ok ($null -ne @($rc.result.vectors)[0]) 'live: CPU-fallback returns a vector'
    Write-Host ("  MEASURE cpu_fallback embed_ms=$($rc.result.timings.embed_ms) load_ms=$($rc.result.timings.load_ms)")

    # 0 orphans
    if ($IsWindows) {
        $orph = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.CommandLine -match 'embed_worker\.py' })
        Ok ($orph.Count -eq 0) "live: 0 UNMANAGED embed_worker orphans (got $($orph.Count))"
    }
}

Write-Host ""
Write-Host "RESULT: $pass passed, $fail failed"
if ($fail -gt 0) { Write-Host ("FAILED: " + ($failed -join '; ')) -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS"
exit 0
