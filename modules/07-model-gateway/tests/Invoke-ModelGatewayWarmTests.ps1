#requires -Version 7.0
# OFF-MACHINE warm/persistent-server tests for model.gateway (Governor Phase 2, D-0055 iter-2 worker E).
# Drives the REAL Invoke-ModelGateway.ps1 against a cross-platform MOCK llama-server (no GPU / no models),
# so it runs on the cloud pre-ship gate AND, unchanged, live via the executor. ASCII-only. Exit 0 iff all pass.
param([string]$PwshPath = (Join-Path $PSHOME 'pwsh'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PwshPath)) { $alt = "$PwshPath.exe"; if (Test-Path -LiteralPath $alt) { $PwshPath = $alt } }
$utf8 = [System.Text.UTF8Encoding]::new($false)

$moduleRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $moduleRoot 'Invoke-ModelGateway.ps1'
$mock  = Join-Path $PSScriptRoot 'mock-llama-server.ps1'

$pass = 0; $fail = 0
function Ok([bool]$c, [string]$n) { if ($c) { $script:pass++; Write-Output "  PASS  $n" } else { $script:fail++; Write-Output "  FAIL  $n" } }
function Has($o, [string]$n) { return ($null -ne $o -and $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }

# ---- scratch: mock registry (two llm models on the mock engine) + dummy model files + isolated warm registry ----
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gw-warm-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$modelA = Join-Path $scratch 'model-a.gguf'; [System.IO.File]::WriteAllText($modelA, 'x', $utf8)
$modelB = Join-Path $scratch 'model-b.gguf'; [System.IO.File]::WriteAllText($modelB, 'x', $utf8)
$reg = [ordered]@{
    schema   = 'lifeorch.model_registry/0.1'
    engines  = [ordered]@{ 'llama-server' = $mock }
    defaults = [ordered]@{ llm = 'mock.a' }
    tiers    = [ordered]@{ llm = [ordered]@{ tiny = 'mock.a' } }
    models   = @(
        [ordered]@{ model_id = 'mock.a'; type = 'llm'; wired = $true; engine = 'llama-server'; path = $modelA; context = 4096; gpu_layers = 99 },
        [ordered]@{ model_id = 'mock.b'; type = 'llm'; wired = $true; engine = 'llama-server'; path = $modelB; context = 4096; gpu_layers = 99 }
    )
}
$regPath = Join-Path $scratch 'models.json'
[System.IO.File]::WriteAllText($regPath, ($reg | ConvertTo-Json -Depth 8), $utf8)
$warmReg = Join-Path $scratch 'warm-server.json'

function RunGw([string[]]$extra) {
    $base = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $entry,
        '-Registry', $regPath, '-WarmRegistryPath', $warmReg, '-GpuLease', 'off', '-PwshPath', $PwshPath,
        '-MaxTokens', '8', '-Temperature', '0.1', '-Seed', '42')
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = & $PwshPath @base @extra 2>$null
    $ErrorActionPreference = $prev
    $txt = ([string]($o | Out-String)).Trim()
    $obj = $null; try { $obj = $txt | ConvertFrom-Json } catch { }
    return $obj
}
function ReadWarm { if (Test-Path -LiteralPath $warmReg) { try { return (Get-Content -LiteralPath $warmReg -Raw | ConvertFrom-Json) } catch { return $null } } return $null }
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }

Write-Output "==== model.gateway warm-server tests (mock engine) ===="
Write-Output "pwsh=$PwshPath"; Write-Output "entry=$entry"; Write-Output ""

# S1: cold start under -Warm -> resident server recorded + alive
$r1 = RunGw @('-Model', 'mock.a', '-Prompt', 'ping', '-Warm')
Ok ($null -ne $r1 -and $r1.status -eq 'ok') 'S1 warm cold-start status ok'
Ok ($null -ne $r1 -and $r1.result.output.text -eq 'PONG') 'S1 got mock completion (PONG)'
$w1 = if ($null -ne $r1) { $r1.result.server.warm } else { $null }
Ok ($null -ne $w1 -and $w1.enabled -eq $true -and $w1.reused -eq $false -and $w1.started_new -eq $true) 'S1 warm: enabled + started_new + not reused'
$reg1 = ReadWarm
$pid1 = if ($null -ne $reg1 -and (Has $reg1 'pid')) { [int]$reg1.pid } else { -1 }
Ok ($null -ne $reg1 -and (PidAlive $pid1)) 'S1 resident server recorded + alive'

# S2: second -Warm call, same model -> REUSE the resident (same pid, no new process)
$r2 = RunGw @('-Model', 'mock.a', '-Prompt', 'ping', '-Warm')
$w2 = if ($null -ne $r2) { $r2.result.server.warm } else { $null }
Ok ($null -ne $r2 -and $r2.status -eq 'ok') 'S2 warm reuse status ok'
Ok ($null -ne $w2 -and $w2.reused -eq $true -and $w2.started_new -eq $false) 'S2 warm: reused, no new start'
$reg2 = ReadWarm
Ok ($null -ne $reg2 -and ([int]$reg2.pid -eq $pid1) -and (PidAlive $pid1)) 'S2 same resident pid across invocations (warm survived process exit)'

# S3: -Warm call for a DIFFERENT model -> evict old + reload (new pid); old pid dies
$r3 = RunGw @('-Model', 'mock.b', '-Prompt', 'ping', '-Warm')
$w3 = if ($null -ne $r3) { $r3.result.server.warm } else { $null }
Ok ($null -ne $r3 -and $r3.status -eq 'ok') 'S3 model-change status ok'
Ok ($null -ne $w3 -and $w3.evicted -eq $true -and $w3.started_new -eq $true -and $w3.reused -eq $false) 'S3 warm: evicted old + started new'
Start-Sleep -Milliseconds 400
Ok (-not (PidAlive $pid1)) 'S3 old resident pid is dead (evicted on model change)'
$reg3 = ReadWarm
$pid3 = if ($null -ne $reg3 -and (Has $reg3 'pid')) { [int]$reg3.pid } else { -1 }
Ok ($null -ne $reg3 -and ($reg3.model_id -eq 'mock.b') -and ($pid3 -ne $pid1) -and (PidAlive $pid3)) 'S3 new resident is mock.b, new pid, alive'

# S4: NON-warm call -> evicts the resident (one-server-on-GPU invariant), leaves NO resident
$r4 = RunGw @('-Model', 'mock.a', '-Prompt', 'ping')   # no -Warm
$w4 = if ($null -ne $r4) { $r4.result.server.warm } else { $null }
Ok ($null -ne $r4 -and $r4.status -eq 'ok') 'S4 non-warm status ok'
Ok ($null -ne $w4 -and $w4.enabled -eq $false) 'S4 warm not enabled on a plain call'
Start-Sleep -Milliseconds 400
Ok (-not (PidAlive $pid3)) 'S4 non-warm call evicted the resident (mock.b pid dead)'
Ok (-not (Test-Path -LiteralPath $warmReg)) 'S4 no resident registry after a non-warm call'

# S5: -EvictWarm shortcut -> tears down resident, returns action=evict_warm (no generation)
$r5a = RunGw @('-Model', 'mock.a', '-Prompt', 'ping', '-Warm')   # set up a resident
$reg5 = ReadWarm; $pid5 = if ($null -ne $reg5 -and (Has $reg5 'pid')) { [int]$reg5.pid } else { -1 }
Ok ($null -ne $reg5 -and (PidAlive $pid5)) 'S5 set up a resident to evict'
$r5b = RunGw @('-EvictWarm')
Ok ($null -ne $r5b -and $r5b.status -eq 'ok' -and $r5b.result.action -eq 'evict_warm') 'S5 EvictWarm returns action=evict_warm'
Ok ($null -ne $r5b -and $r5b.result.warm.evicted -eq $true) 'S5 EvictWarm reports evicted'
Start-Sleep -Milliseconds 400
Ok (-not (PidAlive $pid5)) 'S5 resident pid dead after EvictWarm'
Ok (-not (Test-Path -LiteralPath $warmReg)) 'S5 registry cleared after EvictWarm'

# S6: warm OFF (default) -> classic per-call spawn/kill; no resident, no registry
$r6 = RunGw @('-Model', 'mock.a', '-Prompt', 'ping')
$w6 = if ($null -ne $r6) { $r6.result.server.warm } else { $null }
Ok ($null -ne $r6 -and $r6.status -eq 'ok' -and $r6.result.output.text -eq 'PONG') 'S6 default (non-warm) still generates'
Ok ($null -ne $w6 -and $w6.enabled -eq $false -and $w6.started_new -eq $true) 'S6 non-warm started a per-call server'
Ok (-not (Test-Path -LiteralPath $warmReg)) 'S6 non-warm wrote no resident registry'

# ---- cleanup: leave no mock server behind ----
$leftover = ReadWarm
if ($null -ne $leftover -and (Has $leftover 'pid')) { try { Stop-Process -Id ([int]$leftover.pid) -Force -ErrorAction SilentlyContinue } catch { } }
foreach ($p in @($pid1, $pid3, $pid5)) { if ((PidAlive $p)) { try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch { } } }
Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "==== RESULT pass=$pass fail=$fail ===="
if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 } else { Write-Output 'FAILURES'; exit 1 }
