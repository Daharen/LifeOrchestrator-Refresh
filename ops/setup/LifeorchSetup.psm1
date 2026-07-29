#requires -Version 7.0
<#
  LifeorchSetup.psm1 -- bootstrap logic for the Life Orchestrator portability / new-machine
  bring-up (ops/setup, FANOUT_AGENT_002, plan fo-14-5ea064b6). Pure, unit-testable functions
  that setup.ps1 wires to real probes:

    ConvertTo-PrereqReport     judge a prereq PROBE (pure)      Get-LifeorchPrereqReport   probe + judge
    ConvertFrom-NvidiaSmi      (re-exported from LifeorchConfig) parse nvidia-smi
    New-MachineModelsJson      VRAM-size + data-root-repoint a base models.json (pure)
    Test-MachineModelsJson     validate a generated registry against models.schema.json
    New-StagingPlan            emit (NOT execute) curl.exe download commands + sha256s (pure)
    Get-HeartbeatStatus        read + judge the executor heartbeat (pure given text/now)
    Invoke-SetupVerify         the CPU-only verify pass

  It NEVER modifies modules/07-model-gateway/models.json: New-MachineModelsJson takes a base
  registry object and RETURNS a new one; setup.ps1 writes it only to ops/setup/out/models.machine.json.
  No GPU / model invocation anywhere here. ASCII-only; pwsh 7 target.
#>

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'LifeorchConfig.psm1') -DisableNameChecking -ErrorAction Stop

# ==========================================================================================
# small helpers
# ==========================================================================================
function LoHas($o, [string]$n) {
    if ($null -eq $o) { return $false }
    if ($o -is [System.Collections.IDictionary]) { return $o.Contains($n) }
    $ps = $o.PSObject
    if ($null -eq $ps) { return $false }
    # Use the indexer, not '.Properties.Name -contains': member-enumerating .Name over an EMPTY
    # property set (e.g. a JSON {}) or a scalar throws under StrictMode Latest.
    return ($null -ne $ps.Properties[$n])
}
function LoProp($o, [string]$n, $d = $null) {
    if (LoHas $o $n) { $v = if ($o -is [System.Collections.IDictionary]) { $o[$n] } else { $o.$n }; if ($null -ne $v) { return $v } }
    return $d
}
function LoLeaf([string]$p) {
    # OS-separator-agnostic basename: [IO.Path]::GetFileName keys off the RUNNING OS separator, so a
    # Windows '\' path does not split on Linux (the cloud gate). Split on both.
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    $parts = $p -split '[\\/]'
    return $parts[$parts.Count - 1]
}
function LoExt([string]$p) {
    $leaf = LoLeaf $p
    $i = $leaf.LastIndexOf('.')
    if ($i -lt 0) { return '' }
    return $leaf.Substring($i).ToLowerInvariant()
}
function Get-LoVersionFromString([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $m = [regex]::Match($s, '(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?')
    if (-not $m.Success) { return $null }
    $parts = @($m.Groups[1].Value, $m.Groups[2].Value)
    if ($m.Groups[3].Success) { $parts += $m.Groups[3].Value }
    if ($m.Groups[4].Success) { $parts += $m.Groups[4].Value }
    try { return [version]($parts -join '.') } catch { return $null }
}

# ==========================================================================================
# Prereq check -- pure judge (ConvertTo-PrereqReport) + guarded probe (Get-LifeorchPrereqReport)
# ==========================================================================================
function ConvertTo-PrereqReport {
    <#
      Judge a PROBE object. Fields (all optional; missing -> unknown):
        is_windows(bool) pwsh_version(version/string) git_version(string/null)
        dotnet_version(string/null) curl_exe_present(bool/null) nvidia_smi_present(bool/null)
        gpu(parsed nvidia object/null)
      A required check that cannot be evaluated OFF-Windows degrades to status 'unknown'
      (NOT 'fail'), so the cloud gate stays green; ok = no required check FAILED.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Probe,
        [version]$MinPwsh = '7.4',
        [version]$MinDotnet = '8.0'
    )
    $isWin = [bool](LoProp $Probe 'is_windows' $false)
    $checks = New-Object System.Collections.Generic.List[object]
    function _add($name, $required, $status, $value, $detail) {
        $checks.Add([pscustomobject]@{ name = $name; required = [bool]$required; status = $status; ok = ($status -eq 'pass'); value = $value; detail = $detail })
    }

    # pwsh >= MinPwsh (evaluable everywhere)
    $pv = LoProp $Probe 'pwsh_version'
    $pver = if ($pv -is [version]) { $pv } else { Get-LoVersionFromString ([string]$pv) }
    if ($null -eq $pver) { _add 'pwsh' $true 'unknown' $null 'could not determine pwsh version' }
    elseif ($pver -ge $MinPwsh) { _add 'pwsh' $true 'pass' ([string]$pver) "pwsh $pver >= $MinPwsh" }
    else { _add 'pwsh' $true 'fail' ([string]$pver) "pwsh $pver < required $MinPwsh" }

    # git present (evaluable everywhere)
    $gv = LoProp $Probe 'git_version'
    if ([string]::IsNullOrWhiteSpace([string]$gv)) { _add 'git' $true 'fail' $null 'git not found on PATH' }
    else { _add 'git' $true 'pass' ([string]$gv) 'git present' }

    # .NET SDK >= MinDotnet (evaluable everywhere the SDK exists)
    $dv = LoProp $Probe 'dotnet_version'
    $dver = Get-LoVersionFromString ([string]$dv)
    if ([string]::IsNullOrWhiteSpace([string]$dv)) { _add 'dotnet_sdk' $true 'fail' $null '.NET SDK not found (dotnet --version)' }
    elseif ($null -ne $dver -and $dver -ge $MinDotnet) { _add 'dotnet_sdk' $true 'pass' ([string]$dv) ".NET SDK $dv >= $MinDotnet" }
    elseif ($null -ne $dver) { _add 'dotnet_sdk' $true 'fail' ([string]$dv) ".NET SDK $dv < required $MinDotnet" }
    else { _add 'dotnet_sdk' $true 'unknown' ([string]$dv) 'could not parse dotnet version' }

    # curl.exe (a Windows-shipped binary; OFF-Windows -> unknown, never fail)
    $curl = LoProp $Probe 'curl_exe_present'
    if (-not $isWin) { _add 'curl_exe' $true 'unknown' $null 'curl.exe is a Windows probe; skipped off-Windows' }
    elseif ($null -eq $curl) { _add 'curl_exe' $true 'unknown' $null 'curl.exe presence undetermined' }
    elseif ([bool]$curl) { _add 'curl_exe' $true 'pass' $true 'curl.exe present' }
    else { _add 'curl_exe' $true 'fail' $false 'curl.exe not found (needed to stage models to the data-root)' }

    # CUDA driver via nvidia-smi (OFF-Windows / no GPU here -> unknown, never fail)
    $smi = LoProp $Probe 'nvidia_smi_present'
    $gpu = LoProp $Probe 'gpu'
    $gpuPresent = [bool](LoProp $gpu 'present' $false)
    if (-not $isWin) { _add 'cuda_driver' $true 'unknown' $null 'nvidia-smi is a Windows/GPU probe; skipped off-Windows' }
    elseif ($null -eq $smi) { _add 'cuda_driver' $true 'unknown' $null 'nvidia-smi presence undetermined' }
    elseif ([bool]$smi -and $gpuPresent) { _add 'cuda_driver' $true 'pass' ([string](LoProp $gpu 'name')) "GPU detected: $(LoProp $gpu 'name') ($(LoProp $gpu 'vram_total_mib') MiB)" }
    elseif ([bool]$smi) { _add 'cuda_driver' $true 'unknown' $null 'nvidia-smi present but no GPU parsed' }
    else { _add 'cuda_driver' $true 'fail' $false 'nvidia-smi not found (no CUDA driver -> GPU tiers unavailable)' }

    $arr = $checks.ToArray()
    $fail = @($arr | Where-Object { $_.status -eq 'fail' }).Count
    $pass = @($arr | Where-Object { $_.status -eq 'pass' }).Count
    $unknown = @($arr | Where-Object { $_.status -eq 'unknown' }).Count
    return [pscustomobject]@{
        ok       = ($fail -eq 0)
        is_windows = $isWin
        checks   = $arr
        summary  = [pscustomobject]@{ total = $arr.Count; pass = $pass; fail = $fail; unknown = $unknown }
    }
}

function Get-LifeorchPrereqReport {
    <# Gather a guarded probe on THIS machine, then judge it. Nothing here throws off-Windows. #>
    [CmdletBinding()]
    param([version]$MinPwsh = '7.4', [version]$MinDotnet = '8.0')
    $isWin = $false; try { $isWin = [bool]$IsWindows } catch { $isWin = $false }

    $gitVer = $null
    if ($null -ne (Get-Command git -ErrorAction SilentlyContinue)) { try { $gitVer = (& git --version 2>$null | Out-String).Trim() } catch { $gitVer = $null } }

    $dotnetVer = $null
    if ($null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)) { try { $dotnetVer = (& dotnet --version 2>$null | Out-String).Trim() } catch { $dotnetVer = $null } }

    $curlExe = $null
    if ($isWin) { $curlExe = ($null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)) }

    $smiCmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    $smiPresent = ($null -ne $smiCmd)
    $gpu = Get-LifeorchGpuInfo

    $probe = [pscustomobject]@{
        is_windows         = $isWin
        pwsh_version       = $PSVersionTable.PSVersion
        git_version        = $gitVer
        dotnet_version     = $dotnetVer
        curl_exe_present   = $curlExe
        nvidia_smi_present = $smiPresent
        gpu                = $gpu
    }
    return (ConvertTo-PrereqReport -Probe $probe -MinPwsh $MinPwsh -MinDotnet $MinDotnet)
}

# ==========================================================================================
# models.json generation -- VRAM sizing + data-root repointing (PURE)
# ==========================================================================================
function Get-LoEstLayers([double]$b) {
    if ($b -ge 20) { return 64 } elseif ($b -ge 7) { return 48 } elseif ($b -ge 2.5) { return 36 } elseif ($b -ge 1.0) { return 28 } else { return 24 }
}

function Get-LoGpuLayerPlan {
    <#
      Decide gpu_layers for one GPU-served model on a card of BudgetMib usable VRAM.
      Heuristic (documented in README + VERIFY-RUNBOOK): full-resident need = weight*1.05 + KV
      reserve (KV scales with context and model size). Fits fully -> ngl 99. Otherwise partial:
      floor((budget - kv) / per-layer) minus a small display-headroom margin (the Module-9 "chose
      32 < the 36 that fit" ethos). Partial values are a STARTING POINT the VERIFY-RUNBOOK sweep
      finalizes on a new box.
    #>
    [CmdletBinding()]
    param([int]$WeightMib, [int]$ContextTokens = 8192, [int]$BudgetMib, [int]$EstLayers = 48, [double]$ParamsB = 9)
    if ($ContextTokens -le 0) { $ContextTokens = 8192 }
    $kv = [int][math]::Round(($ContextTokens / 8192.0) * ($ParamsB / 9.0) * 1600.0)
    if ($kv -lt 384) { $kv = 384 }
    $fullNeed = [int][math]::Round($WeightMib * 1.05) + $kv
    if ($fullNeed -le $BudgetMib) {
        return [pscustomobject]@{ gpu_layers = 99; fits_fully = $true; full_need_mib = $fullNeed; kv_reserve_mib = $kv; est_layers = $EstLayers }
    }
    $perLayer = if ($EstLayers -gt 0) { [double]$WeightMib / $EstLayers } else { [double]$WeightMib }
    $avail = $BudgetMib - $kv
    $layers = if ($perLayer -gt 0) { [int][math]::Floor($avail / $perLayer) - 2 } else { 0 }
    if ($layers -lt 0) { $layers = 0 }
    if ($layers -gt $EstLayers) { $layers = $EstLayers }
    return [pscustomobject]@{ gpu_layers = $layers; fits_fully = $false; full_need_mib = $fullNeed; kv_reserve_mib = $kv; est_layers = $EstLayers }
}

function LoReplaceRootPrefix([string]$s, [string]$old, [string]$new) {
    if ([string]::IsNullOrWhiteSpace($s) -or [string]::IsNullOrWhiteSpace($old) -or [string]::IsNullOrWhiteSpace($new)) { return $s }
    $oldN = $old.TrimEnd('\', '/')
    $newN = $new.TrimEnd('\', '/')
    if ($s.Length -ge $oldN.Length -and $s.Substring(0, $oldN.Length).Equals($oldN, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($newN + $s.Substring($oldN.Length))
    }
    return $s
}
function LoRepointValue($v, [string]$old, [string]$new) {
    $t = Get-LoJsonType $v
    if ($t -eq 'string') { return (LoReplaceRootPrefix $v $old $new) }
    if ($t -eq 'array') {
        $acc = New-Object System.Collections.Generic.List[object]
        foreach ($e in @($v)) { $acc.Add((LoRepointValue $e $old $new)) }
        return , ($acc.ToArray())
    }
    if ($t -eq 'object') {
        foreach ($p in @($v.PSObject.Properties)) {
            if ($p.MemberType -eq 'NoteProperty' -or $p.MemberType -eq 'Property') {
                $v.($p.Name) = LoRepointValue $p.Value $old $new
            }
        }
        return $v
    }
    return $v
}
function Get-LoInferOldDataRoot($reg) {
    $pat = 'LifeOrchestrator-Refresh_Large_Data'
    $probe = $null
    try { $probe = [string]$reg.engines.'llama-server' } catch { $probe = $null }
    if (-not [string]::IsNullOrWhiteSpace($probe)) {
        $idx = $probe.IndexOf($pat, [System.StringComparison]::OrdinalIgnoreCase)
        if ($idx -ge 0) { return $probe.Substring(0, $idx + $pat.Length) }
    }
    return 'F:\My_Programs\LifeOrchestrator-Refresh_Large_Data'
}

function New-MachineModelsJson {
    <#
      Return a machine-specific registry (a NEW object; the input is not mutated):
        * every DATA-ROOT-relative absolute path repointed old-data-root -> DataRoot;
        * gpu_layers on every GPU-served (engine=llama-server) entry re-sized for VramMiB;
        * the strong 9B tier: the richest quant that fits fully is wired; tiers.llm.strong points at it.
      Emits a _generated sidecar (sizing decisions, strong pick) for the report + runbook.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $BaseRegistry,
        [Parameter(Mandatory)] [int]$VramMiB,
        [Parameter(Mandatory)] [string]$DataRoot,
        [string]$OldDataRoot,
        [int]$DisplayReserveMiB = 1024,
        [string]$HostName,
        [string]$GeneratedBy = 'ops/setup/setup.ps1 -Action gen'
    )
    $reg = ($BaseRegistry | ConvertTo-Json -Depth 40) | ConvertFrom-Json   # deep clone
    if ([string]::IsNullOrWhiteSpace($OldDataRoot)) { $OldDataRoot = Get-LoInferOldDataRoot $reg }
    $budget = $VramMiB - $DisplayReserveMiB
    if ($budget -lt 0) { $budget = 0 }

    # 1) repoint every data-root-anchored path (engines + all model fields). C:\ paths untouched.
    $reg = LoRepointValue $reg $OldDataRoot $DataRoot

    $sizing = New-Object System.Collections.Generic.List[object]
    $models = @(LoProp $reg 'models')

    # 2) strong 9B quant pick -- collect 9B candidates (family qwen3.5, params_b==9), richest-fits-fully.
    $nineB = @($models | Where-Object {
            $fam = [string](LoProp $_ 'family'); $pb = [double](LoProp (LoProp $_ 'params') 'params_b' 0)
            ($fam -eq 'qwen3.5') -and ($pb -ge 8.5 -and $pb -lt 20)
        })
    $strongPick = $null
    if ($nineB.Count -gt 0) {
        $ranked = @($nineB | Sort-Object -Property @{ Expression = { [double](LoProp (LoProp $_ 'params') 'size_bytes' 0) } } -Descending)
        foreach ($m in $ranked) {
            $wb = [double](LoProp (LoProp $m 'params') 'size_bytes' 0)
            $wmib = [int][math]::Round($wb / 1048576.0)
            $ctx = [int](LoProp $m 'context' 8192)
            $plan = Get-LoGpuLayerPlan -WeightMib $wmib -ContextTokens $ctx -BudgetMib $budget -EstLayers (Get-LoEstLayers 9) -ParamsB 9
            if ($plan.fits_fully) { $strongPick = $m; break }
        }
        if ($null -eq $strongPick) { $strongPick = $ranked[$ranked.Count - 1] }   # none fully fit -> smallest quant, partial
        $pickId = [string](LoProp $strongPick 'model_id')
        foreach ($m in $nineB) { $m.wired = ($([string](LoProp $m 'model_id')) -eq $pickId) }
        if (LoHas $reg 'tiers') { if (LoHas $reg.tiers 'llm') { $reg.tiers.llm.strong = $pickId } }
    }

    # 3) size gpu_layers on every GPU-served entry
    foreach ($m in $models) {
        if (-not (LoHas $m 'gpu_layers')) { continue }
        $engine = [string](LoProp $m 'engine')
        if ($engine -ne 'llama-server') { continue }
        $pr = LoProp $m 'params'
        $wb = [double](LoProp $pr 'size_bytes' 0)
        $pb = [double](LoProp $pr 'params_b' 0)
        if ($wb -le 0 -and $pb -gt 0) { $wb = $pb * 1e9 * 0.6 }   # rough fallback if size unknown
        $wmib = [int][math]::Round($wb / 1048576.0)
        $ctx = [int](LoProp $m 'context' 8192)
        $plan = Get-LoGpuLayerPlan -WeightMib $wmib -ContextTokens $ctx -BudgetMib $budget -EstLayers (Get-LoEstLayers $pb) -ParamsB $pb
        $m.gpu_layers = $plan.gpu_layers
        $sizing.Add([pscustomobject]@{
                model_id      = [string](LoProp $m 'model_id')
                quant         = [string](LoProp $m 'quant')
                weight_mib    = $wmib
                context       = $ctx
                gpu_layers    = $plan.gpu_layers
                fits_fully    = $plan.fits_fully
                full_need_mib = $plan.full_need_mib
                wired         = [bool](LoProp $m 'wired' $false)
            })
    }

    # 4) top-level metadata
    if (-not [string]::IsNullOrWhiteSpace($HostName)) { $reg.host = $HostName }
    $reg | Add-Member -NotePropertyName 'updated_utc' -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $gen = [pscustomobject]@{
        by                 = $GeneratedBy
        utc                = ([DateTime]::UtcNow.ToString('o'))
        vram_mib           = $VramMiB
        display_reserve_mib = $DisplayReserveMiB
        budget_mib         = $budget
        data_root          = $DataRoot
        old_data_root      = $OldDataRoot
        strong_pick        = if ($null -ne $strongPick) { [string](LoProp $strongPick 'model_id') } else { $null }
        note               = 'STAGING copy only. Never replaces modules/07-model-gateway/models.json. gpu_layers for partial-offload models are a starting point; finalize with the VERIFY-RUNBOOK sweep.'
        sizing             = $sizing.ToArray()
    }
    $reg | Add-Member -NotePropertyName '_generated' -NotePropertyValue $gen -Force
    return $reg
}

function Test-MachineModelsJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Registry, [string]$SchemaPath)
    if ([string]::IsNullOrWhiteSpace($SchemaPath)) { $SchemaPath = Join-Path $PSScriptRoot 'models.schema.json' }
    $instance = $Registry
    if ($Registry -is [string]) {
        if (-not (Test-Path -LiteralPath $Registry -PathType Leaf)) { return [pscustomobject]@{ valid = $false; errors = @("models file not found: $Registry") } }
        $instance = (Get-Content -LiteralPath $Registry -Raw) | ConvertFrom-Json
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { return [pscustomobject]@{ valid = $false; errors = @("schema not found: $SchemaPath") } }
    $schema = (Get-Content -LiteralPath $SchemaPath -Raw) | ConvertFrom-Json
    return (Test-JsonAgainstSchema -Instance $instance -Schema $schema)
}

# ==========================================================================================
# Staging plan -- EMIT (do not execute) curl.exe download commands + expected sha256s
# ==========================================================================================
function Get-LoDefaultSourceMap {
    # Best-effort source repos derived from the models.json notes. UNKNOWN/uncertain ones are TODO
    # so the operator confirms the exact URL BEFORE a multi-GB download (D-0061 honesty).
    return @{
        'vlm.qwen2p5-vl-3b'          = 'https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/'
        'video.animatediff-lightning' = 'https://huggingface.co/ByteDance/AnimateDiff-Lightning/resolve/main/'
        'stt.whisper.base-en'        = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
    }
}
function New-StagingPlan {
    <#
      Build a human-runnable, NON-executed staging plan for the data-root: one curl.exe command +
      an expected-sha256 verify per SINGLE-FILE artifact (gguf/onnx/bin/safetensors); a hf-cli/git
      note per multi-file directory model (diffusers/transformers-dir/safetensors-dir); an engine
      note for the llama.cpp builds. Returns the plan text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Registry, [Parameter(Mandatory)] [string]$DataRoot, [hashtable]$SourceMap)
    if ($null -eq $SourceMap) { $SourceMap = Get-LoDefaultSourceMap }
    $singleExt = @('.gguf', '.onnx', '.bin', '.safetensors', '.ggml')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Life Orchestrator -- model/engine STAGING PLAN (EMITTED, NOT EXECUTED)')
    $lines.Add('# Generated by ops/setup/setup.ps1 (LifeorchSetup New-StagingPlan).')
    $lines.Add("# Data-root: $DataRoot")
    $lines.Add('# Downloading tens of GB is NOT a wave task -- run this deliberately on the target box.')
    $lines.Add('# Each single-file artifact: curl.exe download + a Get-FileHash sha256 verify against the expected value.')
    $lines.Add('# Multi-file (diffusers/transformers) models: use huggingface-cli / git-lfs (a single curl cannot fetch a folder).')
    $lines.Add('# URLs marked TODO_CONFIRM_URL must be confirmed against the source repo before downloading.')
    $lines.Add('')

    $totalBytes = [long]0
    $models = @(LoProp $Registry 'models')
    foreach ($m in $models) {
        $id = [string](LoProp $m 'model_id')
        $fmt = [string](LoProp $m 'format')
        $path = [string](LoProp $m 'path')
        $engine = [string](LoProp $m 'engine')
        $pr = LoProp $m 'params'
        $sha = [string](LoProp $pr 'sha256')
        $size = [long](LoProp $pr 'size_bytes' 0)
        $base = if ($SourceMap.ContainsKey($id)) { [string]$SourceMap[$id] } else { $null }

        $lines.Add("## $id  ($([string](LoProp $m 'name')))  type=$([string](LoProp $m 'type')) format=$fmt")
        if ($engine -in @('windows.media.ocr')) { $lines.Add('#   system component (no download).'); $lines.Add(''); continue }
        if ($fmt -eq 'executable') { $lines.Add("#   installed executable (install separately): $path"); $lines.Add(''); continue }
        if ([string]::IsNullOrWhiteSpace($path)) { $lines.Add('#   no path (declared-only).'); $lines.Add(''); continue }

        $ext = LoExt $path
        $isSingle = ($singleExt -contains $ext)
        if ($isSingle) {
            $fname = LoLeaf $path
            $url = if ($base) { ($base.TrimEnd('/') + '/' + $fname) } else { "TODO_CONFIRM_URL_for_$fname" }
            if ($size -gt 0) { $totalBytes += $size; $lines.Add("#   size ~$([int][math]::Round($size/1048576.0)) MiB") }
            $lines.Add("curl.exe -L --fail --create-dirs -o `"$path`" `"$url`"")
            if (-not [string]::IsNullOrWhiteSpace($sha)) {
                $lines.Add("#   expected sha256: $sha")
                $lines.Add("powershell -NoProfile -Command `"if((Get-FileHash -Algorithm SHA256 '$path').Hash -ieq '$sha'){'OK $id'}else{'SHA MISMATCH $id'}`"")
            } else { $lines.Add('#   (no expected sha256 recorded)') }
            # extra single-file sidecars (mmproj / adapter)
            foreach ($side in @('mmproj', 'adapter')) {
                if (LoHas $m $side) {
                    $sp = [string](LoProp $m $side)
                    if (-not [string]::IsNullOrWhiteSpace($sp)) {
                        $sfn = LoLeaf $sp
                        $surl = if ($base) { ($base.TrimEnd('/') + '/' + $sfn) } else { "TODO_CONFIRM_URL_for_$sfn" }
                        $ssha = [string](LoProp $pr ($side + '_sha256'))
                        $lines.Add("curl.exe -L --fail --create-dirs -o `"$sp`" `"$surl`"")
                        if (-not [string]::IsNullOrWhiteSpace($ssha)) { $lines.Add("#   expected sha256: $ssha") }
                    }
                }
            }
        } else {
            $repo = if ($base) { $base } else { 'TODO_CONFIRM_HF_REPO' }
            $lines.Add("#   multi-file $fmt model -> stage the whole folder:")
            $lines.Add("#   huggingface-cli download $repo --local-dir `"$path`"    # or: git lfs clone <repo> `"$path`"")
        }
        $lines.Add('')
    }

    # engines
    $lines.Add('## engines (llama.cpp CUDA builds)')
    $eng = LoProp $Registry 'engines'
    if ($null -ne $eng) {
        foreach ($p in @($eng.PSObject.Properties)) {
            if ($p.Name -like '_*') { continue }
            $lines.Add("#   $($p.Name): $($p.Value)")
        }
    }
    $lines.Add('#   b8661 (default, every tier but the 9B) + b10092 (the 9B strong tier only, CUDA 12.4, self-contained).')
    $lines.Add('#   Download the matching CUDA release zip from the llama.cpp GitHub releases and extract to the engine path above,')
    $lines.Add('#   OR rebuild from source. Confirm the build tags against TOOL_MODEL_REGISTRY.md before staging.')
    $lines.Add('')
    $lines.Add("# Approx single-file download total: ~$([int][math]::Round($totalBytes/1048576.0)) MiB (excludes multi-file dirs + engines).")
    return ($lines.ToArray() -join "`n")
}

# ==========================================================================================
# Verify pass (CPU-only)
# ==========================================================================================
function Get-HeartbeatStatus {
    <# Read + judge the executor heartbeat. -NowUtc lets tests judge a fixture against a fixed clock. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$HeartbeatPath, [int]$MaxAgeSeconds = 120, [datetime]$NowUtc)
    if (-not $PSBoundParameters.ContainsKey('NowUtc')) { $NowUtc = [DateTime]::UtcNow }
    if (-not (Test-Path -LiteralPath $HeartbeatPath -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; present = $false; reason = 'heartbeat file missing'; path = $HeartbeatPath }
    }
    $hb = $null
    try { $hb = (Get-Content -LiteralPath $HeartbeatPath -Raw) | ConvertFrom-Json } catch {
        return [pscustomobject]@{ ok = $false; present = $true; reason = 'heartbeat not valid JSON'; path = $HeartbeatPath }
    }
    $atUtc = LoProp $hb 'at_utc'
    $age = $null; $fresh = $false
    if ($null -ne $atUtc) {
        try {
            $atDt = if ($atUtc -is [datetime]) { $atUtc.ToUniversalTime() }
                    elseif ($atUtc -is [datetimeoffset]) { $atUtc.UtcDateTime }
                    else { [datetime]::Parse([string]$atUtc, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal) }
            $age = ($NowUtc.ToUniversalTime() - $atDt).TotalSeconds
            $fresh = ($age -le $MaxAgeSeconds -and $age -ge -30)
        } catch { $age = $null; $fresh = $false }
    }
    $degraded = [bool](LoProp $hb 'degraded' $true)
    $pes = [int](LoProp $hb 'poll_error_streak' 0)
    $sfc = [int](LoProp $hb 'stuck_finalize_count' 0)
    $ok = ($fresh -and -not $degraded -and $pes -eq 0 -and $sfc -eq 0)
    return [pscustomobject]@{
        ok = $ok; present = $true; fresh = $fresh; age_seconds = $age; max_age_seconds = $MaxAgeSeconds
        degraded = $degraded; poll_error_streak = $pes; stuck_finalize_count = $sfc
        at_utc = [string]$atUtc; instance_id = [string](LoProp $hb 'instance_id'); pid = (LoProp $hb 'pid'); path = $HeartbeatPath
    }
}

function Invoke-SetupVerify {
    <#
      CPU-only verify pass: config resolves + is schema-valid; repo-relative paths exist; the
      generated models.machine.json is schema-valid; (unless -SkipHeartbeat) the executor
      heartbeat is fresh + degraded:false. Returns {ok, checks[], summary}. No GPU/model calls.
    #>
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        $Config,
        [string]$MachineModelsPath,
        [int]$MaxHeartbeatAgeSeconds = 120,
        [switch]$SkipHeartbeat,
        [datetime]$NowUtc
    )
    $checks = New-Object System.Collections.Generic.List[object]
    function _c($name, $status, $detail) { $checks.Add([pscustomobject]@{ name = $name; status = $status; ok = ($status -eq 'pass'); detail = $detail }) }

    if ($null -eq $Config) {
        $ra = @{}; if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $ra['RepoRoot'] = $RepoRoot }
        $Config = Resolve-LifeorchConfig @ra
    }
    $rr = [string](LoProp $Config 'repo_root')
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = $rr }

    # 1) config resolves
    if (-not [string]::IsNullOrWhiteSpace($rr)) { _c 'config_resolves' 'pass' "repo_root=$rr data_root=$([string](LoProp $Config 'data_root'))" }
    else { _c 'config_resolves' 'fail' 'repo_root did not resolve' }

    # 1b) config.json (if present) is schema-valid
    $cfgFile = if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { Join-Path $RepoRoot 'ops/setup/config.json' } else { $null }
    if ($cfgFile -and (Test-Path -LiteralPath $cfgFile -PathType Leaf)) {
        $cv = Test-LifeorchConfig -Config $cfgFile
        if ($cv.valid) { _c 'config_schema_valid' 'pass' 'config.json valid' } else { _c 'config_schema_valid' 'fail' ("config.json invalid: " + ($cv.errors -join '; ')) }
    } else { _c 'config_schema_valid' 'skipped' 'no config.json on disk' }

    # 2) repo-relative paths exist
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot) -and (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($rel in @('modules', 'ops', 'ops/setup', 'modules/00-bootstrap-executor')) {
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $rel))) { $missing.Add($rel) }
        }
        if ($missing.Count -eq 0) { _c 'repo_paths_exist' 'pass' 'modules/, ops/, ops/setup/, modules/00-bootstrap-executor present' }
        else { _c 'repo_paths_exist' 'fail' ('missing: ' + ($missing.ToArray() -join ', ')) }
    } else { _c 'repo_paths_exist' 'fail' "repo_root not a directory: $RepoRoot" }

    # 2b) data-root (warn, not fail -- a fresh box may not have staged data yet)
    $dr = [string](LoProp $Config 'data_root')
    if ([string]::IsNullOrWhiteSpace($dr)) { _c 'data_root_exists' 'warn' 'data_root unresolved (stage data + set LIFEORCH_DATA_ROOT / config.json)' }
    elseif (Test-Path -LiteralPath $dr -PathType Container) { _c 'data_root_exists' 'pass' "data_root present: $dr" }
    else { _c 'data_root_exists' 'warn' "data_root not present yet: $dr" }

    # 3) generated models.machine.json is schema-valid
    if ([string]::IsNullOrWhiteSpace($MachineModelsPath) -and -not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $cand = Join-Path $RepoRoot 'ops/setup/out/models.machine.json'
        if (Test-Path -LiteralPath $cand -PathType Leaf) { $MachineModelsPath = $cand }
    }
    if (-not [string]::IsNullOrWhiteSpace($MachineModelsPath) -and (Test-Path -LiteralPath $MachineModelsPath -PathType Leaf)) {
        $mv = Test-MachineModelsJson -Registry $MachineModelsPath
        if ($mv.valid) { _c 'models_machine_valid' 'pass' 'models.machine.json schema-valid' } else { _c 'models_machine_valid' 'fail' ('invalid: ' + ($mv.errors -join '; ')) }
    } else { _c 'models_machine_valid' 'skipped' 'no models.machine.json yet (run setup.ps1 -Action gen)' }

    # 4) heartbeat (CPU-only, no model calls)
    if ($SkipHeartbeat) { _c 'executor_heartbeat' 'skipped' 'heartbeat check skipped (off-box / -SkipHeartbeat)' }
    elseif (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $hbPath = Join-Path $RepoRoot 'modules/00-bootstrap-executor/runtime/control/heartbeat.json'
        $hbArgs = @{ HeartbeatPath = $hbPath; MaxAgeSeconds = $MaxHeartbeatAgeSeconds }
        if ($PSBoundParameters.ContainsKey('NowUtc')) { $hbArgs['NowUtc'] = $NowUtc }
        $hb = Get-HeartbeatStatus @hbArgs
        if ($hb.ok) { _c 'executor_heartbeat' 'pass' "fresh (age $([int]([math]::Round(([double]($hb.age_seconds))))) s), degraded:false" }
        elseif (-not $hb.present) { _c 'executor_heartbeat' 'fail' 'heartbeat missing (executor not running?)' }
        else { _c 'executor_heartbeat' 'fail' "unhealthy: fresh=$($hb.fresh) degraded=$($hb.degraded) poll_error_streak=$($hb.poll_error_streak) stuck_finalize_count=$($hb.stuck_finalize_count)" }
    } else { _c 'executor_heartbeat' 'fail' 'no repo_root to locate heartbeat' }

    $arr = $checks.ToArray()
    $fail = @($arr | Where-Object { $_.status -eq 'fail' }).Count
    $warn = @($arr | Where-Object { $_.status -eq 'warn' }).Count
    $pass = @($arr | Where-Object { $_.status -eq 'pass' }).Count
    return [pscustomobject]@{
        ok      = ($fail -eq 0)
        checks  = $arr
        summary = [pscustomobject]@{ total = $arr.Count; pass = $pass; fail = $fail; warn = $warn }
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-PrereqReport',
    'Get-LifeorchPrereqReport',
    'Get-LoGpuLayerPlan',
    'New-MachineModelsJson',
    'Test-MachineModelsJson',
    'New-StagingPlan',
    'Get-HeartbeatStatus',
    'Invoke-SetupVerify'
)
