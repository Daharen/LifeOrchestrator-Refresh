#requires -Version 7.0
<#
  LifeorchConfig.psm1 -- STANDALONE config-resolution library for the Life Orchestrator
  portability / new-machine bring-up (ops/setup, FANOUT_AGENT_002, plan fo-14-5ea064b6).

  Purpose: give every module ONE place to resolve REPO-ROOT + DATA-ROOT + a machine profile
  (hostname / username / GPU name+VRAM), replacing the scattered hard-coded absolute paths
  (C:\Users\just_\LifeOrchestrator-Refresh and F:\My_Programs\...\_Large_Data) noted in
  MODULE_ROADMAP.md -> BACKLOG portability. Roots are DETECTED at runtime (from the module's
  own location, env vars, and probed candidates), never baked into code.

  This is a LIBRARY only. It is NOT wired into modules/* this wave (that path-surgery is a
  documented follow-on that would touch other modules). Modules adopt it LATER by importing
  this .psm1 and calling Resolve-LifeorchConfig instead of hard-coding paths.

  Windows-only probes (nvidia-smi, COMPUTERNAME) degrade to a reported 'unknown'/present:false
  OFF-Windows and NEVER throw, so all pure logic gates green in cloud pwsh 7.4.6 on Linux.

  ASCII-only on purpose (the 5.1-ANSI gotcha in CURRENT_STATE -> Known failures); pwsh 7 target.
#>

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------------------
# Small property helpers (PSCustomObject / hashtable safe under StrictMode Latest)
# ------------------------------------------------------------------------------------------
function LoHasProp($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    if ($obj -is [System.Collections.IDictionary]) { return $obj.Contains($name) }
    $ps = $obj.PSObject
    if ($null -eq $ps) { return $false }
    # Use the indexer, not '.Properties.Name -contains': member-enumerating .Name over an EMPTY
    # property set (e.g. a JSON {}) or a scalar throws under StrictMode Latest.
    return ($null -ne $ps.Properties[$name])
}
function LoGetProp($obj, [string]$name, $default = $null) {
    if (LoHasProp $obj $name) {
        $v = if ($obj -is [System.Collections.IDictionary]) { $obj[$name] } else { $obj.$name }
        if ($null -ne $v) { return $v }
    }
    return $default
}

# ------------------------------------------------------------------------------------------
# JSON-type classifier + a small JSON-Schema SUBSET validator.
# Supports: type (incl. unions + null), required, properties, items, enum, minimum.
# PowerShell ships no JSON-Schema validator; this makes "config / models.json is schema-valid"
# an actual, testable check without pulling an external dependency.
# ------------------------------------------------------------------------------------------
function Get-LoJsonType($v) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { return 'boolean' }
    if ($v -is [string]) { return 'string' }
    # ConvertFrom-Json coerces ISO-8601 date strings to [datetime]; in JSON they were strings, so
    # classify them as 'string' (otherwise a round-tripped generated_utc/updated_utc fails validation).
    if ($v -is [datetime] -or $v -is [datetimeoffset]) { return 'string' }
    if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte] -or $v -is [sbyte] -or $v -is [uint32] -or $v -is [uint64]) { return 'integer' }
    if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) {
        # An integer-valued float from JSON (rare) is still "number"; our schemas never require that coercion.
        return 'number'
    }
    if ($v -is [System.Collections.IDictionary]) { return 'object' }
    if ($v -is [System.Management.Automation.PSCustomObject]) { return 'object' }
    if ($v -is [System.Array] -or $v -is [System.Collections.IList]) { return 'array' }
    return 'unknown'
}

function LoValidateNode($Value, $Schema, [string]$Path, $Errors) {
    # ---- type ----
    if (LoHasProp $Schema 'type') {
        $types = @(LoGetProp $Schema 'type')
        $jt = Get-LoJsonType $Value
        $ok = $false
        foreach ($t in $types) {
            if ($t -eq $jt) { $ok = $true; break }
            if ($t -eq 'number' -and $jt -eq 'integer') { $ok = $true; break }
        }
        if (-not $ok) {
            $Errors.Add("${Path}: expected type [$($types -join '|')], got '$jt'")
            return   # a wrong-typed node cannot be recursed further
        }
    }

    $jt = Get-LoJsonType $Value
    if ($jt -eq 'object') {
        if (LoHasProp $Schema 'required') {
            foreach ($r in @(LoGetProp $Schema 'required')) {
                if (-not (LoHasProp $Value $r)) { $Errors.Add("${Path}: missing required property '$r'") }
            }
        }
        if (LoHasProp $Schema 'properties') {
            $props = LoGetProp $Schema 'properties'
            foreach ($pn in $props.PSObject.Properties.Name) {
                if (LoHasProp $Value $pn) {
                    LoValidateNode (LoGetProp $Value $pn) ($props.$pn) "${Path}.$pn" $Errors
                }
            }
        }
    }
    elseif ($jt -eq 'array') {
        if (LoHasProp $Schema 'items') {
            $items = LoGetProp $Schema 'items'
            $i = 0
            foreach ($el in @($Value)) { LoValidateNode $el $items "${Path}[$i]" $Errors; $i++ }
        }
    }

    # ---- enum ----
    if (LoHasProp $Schema 'enum') {
        $vals = @(LoGetProp $Schema 'enum')
        if ($vals -notcontains $Value) { $Errors.Add("${Path}: value '$Value' not in enum [$($vals -join ', ')]") }
    }
    # ---- minimum ----
    if ((LoHasProp $Schema 'minimum') -and ($jt -eq 'integer' -or $jt -eq 'number')) {
        $min = LoGetProp $Schema 'minimum'
        if ($Value -lt $min) { $Errors.Add("${Path}: $Value is below minimum $min") }
    }
}

function Test-JsonAgainstSchema {
    <# Validate a parsed JSON instance against a parsed JSON-Schema (subset). Returns {valid,errors[]}. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Instance,
        [Parameter(Mandatory)] $Schema
    )
    $errs = New-Object System.Collections.Generic.List[string]
    LoValidateNode $Instance $Schema '$' $errs
    return [pscustomobject]@{ valid = ($errs.Count -eq 0); errors = $errs.ToArray() }
}

# ------------------------------------------------------------------------------------------
# GPU detection: pure parser + guarded probe. Degrades to present:false off-Windows / no GPU.
# ------------------------------------------------------------------------------------------
function ConvertFrom-NvidiaSmi {
    <#
      Parse the output of:  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits
      e.g. "NVIDIA GeForce RTX 2080 Ti, 11264".  Robust to a units suffix ("11264 MiB") and to
      multiple GPUs (takes the first; reports all). Empty/whitespace -> present:false.
    #>
    [CmdletBinding()]
    param([string]$Text)
    $result = [ordered]@{ present = $false; name = $null; vram_total_mib = $null; all = @(); source = 'nvidia-smi' }
    if ([string]::IsNullOrWhiteSpace($Text)) { return [pscustomobject]$result }
    $gpus = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($Text -split "`r?`n")) {
        $l = $line.Trim()
        if ($l.Length -eq 0) { continue }
        # tolerate CSV header if the caller forgot noheader
        if ($l -match '^(?i)\s*name\s*,') { continue }
        $parts = $l -split ','
        if ($parts.Count -lt 2) { continue }
        $nm = $parts[0].Trim()
        $memRaw = ($parts[1..($parts.Count - 1)] -join ',').Trim()
        $digits = ($memRaw -replace '[^0-9]', '')
        if ([string]::IsNullOrWhiteSpace($digits)) { continue }
        $mib = [int]$digits
        $gpus.Add([pscustomobject]@{ name = $nm; vram_total_mib = $mib })
    }
    if ($gpus.Count -gt 0) {
        $result.present = $true
        $result.name = $gpus[0].name
        $result.vram_total_mib = $gpus[0].vram_total_mib
        $result.all = $gpus.ToArray()
    }
    return [pscustomobject]$result
}

function Get-LifeorchGpuInfo {
    <# Guarded nvidia-smi probe. -MockText feeds the parser directly (the cloud-gate seam). #>
    [CmdletBinding()]
    param([string]$MockText, [switch]$NoProbe)
    if ($PSBoundParameters.ContainsKey('MockText')) { return (ConvertFrom-NvidiaSmi -Text $MockText) }
    if ($NoProbe) { return (ConvertFrom-NvidiaSmi -Text '') }
    $cmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return (ConvertFrom-NvidiaSmi -Text '') }
    $raw = ''
    try {
        $raw = (& nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null | Out-String)
    } catch { $raw = '' }
    return (ConvertFrom-NvidiaSmi -Text $raw)
}

# ------------------------------------------------------------------------------------------
# Machine profile
# ------------------------------------------------------------------------------------------
function Get-LifeorchMachineProfile {
    [CmdletBinding()]
    param([string]$MockNvidiaSmiText)
    $isWin = $false
    try { $isWin = [bool]$IsWindows } catch { $isWin = $false }

    $hostName = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($hostName)) { try { $hostName = [System.Net.Dns]::GetHostName() } catch { $hostName = $null } }

    $userName = $env:USERNAME
    if ([string]::IsNullOrWhiteSpace($userName)) { $userName = $env:USER }
    if ([string]::IsNullOrWhiteSpace($userName)) { try { $userName = [Environment]::UserName } catch { $userName = $null } }

    $os = $null
    try { $os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription } catch { $os = $null }
    $platform = $null
    try { $platform = [string][System.Environment]::OSVersion.Platform } catch { $platform = $null }

    $gpu = if ($PSBoundParameters.ContainsKey('MockNvidiaSmiText')) { Get-LifeorchGpuInfo -MockText $MockNvidiaSmiText } else { Get-LifeorchGpuInfo }

    return [pscustomobject]@{
        hostname   = $hostName
        username   = $userName
        os         = $os
        platform   = $platform
        is_windows = $isWin
        gpu        = $gpu
    }
}

# ------------------------------------------------------------------------------------------
# Root detection helpers -- each returns {path, source}. source records HOW it was found.
# ------------------------------------------------------------------------------------------
function Get-LifeorchRepoRoot {
    [CmdletBinding()]
    param([string]$Hint, [string]$ModuleRoot = $PSScriptRoot)
    if (-not [string]::IsNullOrWhiteSpace($Hint) -and (Test-Path -LiteralPath $Hint -PathType Container)) {
        return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $Hint).Path; source = 'hint' }
    }
    $envRoot = $env:LIFEORCH_REPO_ROOT
    if (-not [string]::IsNullOrWhiteSpace($envRoot) -and (Test-Path -LiteralPath $envRoot -PathType Container)) {
        return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $envRoot).Path; source = 'env:LIFEORCH_REPO_ROOT' }
    }
    # This module lives at <repo>/ops/setup/ -> repo root is two levels up. DETECTED, not baked.
    if (-not [string]::IsNullOrWhiteSpace($ModuleRoot)) {
        $up2 = Split-Path -Parent (Split-Path -Parent $ModuleRoot)
        if (-not [string]::IsNullOrWhiteSpace($up2) -and (Test-Path -LiteralPath $up2 -PathType Container)) {
            $marker = (Test-Path -LiteralPath (Join-Path $up2 'modules') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $up2 '.git'))
            $src = if ($marker) { 'module-location' } else { 'module-location-unverified' }
            return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $up2).Path; source = $src }
        }
    }
    return [pscustomobject]@{ path = (Get-Location).Path; source = 'cwd-fallback' }
}

function Get-LifeorchDataRoot {
    [CmdletBinding()]
    param([string]$Hint, [string]$RepoRoot, [string[]]$Candidates)
    if (-not [string]::IsNullOrWhiteSpace($Hint) -and (Test-Path -LiteralPath $Hint -PathType Container)) {
        return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $Hint).Path; source = 'hint' }
    }
    $envRoot = $env:LIFEORCH_DATA_ROOT
    if (-not [string]::IsNullOrWhiteSpace($envRoot) -and (Test-Path -LiteralPath $envRoot -PathType Container)) {
        return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $envRoot).Path; source = 'env:LIFEORCH_DATA_ROOT' }
    }
    # Probed candidates (existence-tested at runtime -- NOT an assumed value). The known F: home is
    # only a candidate: if it exists on THIS box it is detected, otherwise the resolver reports unresolved.
    $probe = New-Object System.Collections.Generic.List[string]
    if ($Candidates) { foreach ($c in $Candidates) { $probe.Add($c) } }
    $probe.Add('F:\My_Programs\LifeOrchestrator-Refresh_Large_Data')
    $probe.Add('E:\My_Programs\LifeOrchestrator-Refresh_Large_Data')
    $probe.Add('D:\My_Programs\LifeOrchestrator-Refresh_Large_Data')
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $probe.Add((Join-Path $RepoRoot '_large_data'))
        $probe.Add((Join-Path $RepoRoot 'LifeOrchestrator-Refresh_Large_Data'))
    }
    foreach ($c in $probe) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Container)) {
            return [pscustomobject]@{ path = (Resolve-Path -LiteralPath $c).Path; source = 'probed-candidate' }
        }
    }
    return [pscustomobject]@{ path = $null; source = 'unresolved' }
}

# ------------------------------------------------------------------------------------------
# Resolve-LifeorchConfig -- the public resolver.
#   No config.json present -> detect everything.
#   config.json present    -> use it (params/-Detect can override / refresh).
# ------------------------------------------------------------------------------------------
function Resolve-LifeorchConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [string]$RepoRoot,
        [string]$DataRoot,
        [switch]$Detect,
        [string]$MockNvidiaSmiText
    )
    $moduleRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $moduleRoot 'config.json' }

    $fromFile = $null
    $fileValid = $null
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw
            $fromFile = $raw | ConvertFrom-Json
            $chk = Test-LifeorchConfig -Config $fromFile
            $fileValid = $chk.valid
        } catch {
            $fromFile = $null
            $fileValid = $false
        }
    }

    $useFile = ($null -ne $fromFile) -and (-not $Detect)

    if ($useFile) {
        $rrPath = if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot } else { [string](LoGetProp $fromFile 'repo_root') }
        $drPath = if (-not [string]::IsNullOrWhiteSpace($DataRoot)) { $DataRoot } else { [string](LoGetProp $fromFile 'data_root') }
        $machine = LoGetProp $fromFile 'machine'
        $prov = [pscustomobject]@{ repo_root = 'config.json'; data_root = 'config.json'; config_path = $ConfigPath; from_file = $true; file_valid = $fileValid }
    } else {
        $rr = Get-LifeorchRepoRoot -Hint $RepoRoot -ModuleRoot $moduleRoot
        $dr = Get-LifeorchDataRoot -Hint $DataRoot -RepoRoot $rr.path
        $machine = if ($PSBoundParameters.ContainsKey('MockNvidiaSmiText')) { Get-LifeorchMachineProfile -MockNvidiaSmiText $MockNvidiaSmiText } else { Get-LifeorchMachineProfile }
        $rrPath = $rr.path
        $drPath = $dr.path
        $prov = [pscustomobject]@{ repo_root = $rr.source; data_root = $dr.source; config_path = $ConfigPath; from_file = $false; file_valid = $fileValid }
    }

    return [pscustomobject]@{
        schema     = 'lifeorch.setup.config/0.1'
        repo_root  = $rrPath
        data_root  = $drPath
        machine    = $machine
        provenance = $prov
    }
}

function Test-LifeorchConfig {
    <# Validate a config object (or a path to config.json) against config.schema.json. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [string]$SchemaPath
    )
    $moduleRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($SchemaPath)) { $SchemaPath = Join-Path $moduleRoot 'config.schema.json' }
    $instance = $Config
    if ($Config -is [string]) {
        if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { return [pscustomobject]@{ valid = $false; errors = @("config file not found: $Config") } }
        $instance = (Get-Content -LiteralPath $Config -Raw) | ConvertFrom-Json
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) { return [pscustomobject]@{ valid = $false; errors = @("schema not found: $SchemaPath") } }
    $schema = (Get-Content -LiteralPath $SchemaPath -Raw) | ConvertFrom-Json
    return (Test-JsonAgainstSchema -Instance $instance -Schema $schema)
}

function Write-LifeorchConfig {
    <#
      Detect this machine's config and WRITE it to config.json (default ops/setup/config.json).
      Roots + machine profile are DETECTED at runtime. Returns {path, config, valid, errors}.
    #>
    [CmdletBinding()]
    param(
        [string]$OutPath,
        [string]$RepoRoot,
        [string]$DataRoot,
        [string]$MockNvidiaSmiText,
        [string]$GeneratedBy = 'ops/setup/setup.ps1 -Action detect'
    )
    $moduleRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($OutPath)) { $OutPath = Join-Path $moduleRoot 'config.json' }

    $resolveArgs = @{ Detect = $true }
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $resolveArgs['RepoRoot'] = $RepoRoot }
    if (-not [string]::IsNullOrWhiteSpace($DataRoot)) { $resolveArgs['DataRoot'] = $DataRoot }
    if ($PSBoundParameters.ContainsKey('MockNvidiaSmiText')) { $resolveArgs['MockNvidiaSmiText'] = $MockNvidiaSmiText }
    $resolved = Resolve-LifeorchConfig @resolveArgs

    $config = [ordered]@{
        schema        = 'lifeorch.setup.config/0.1'
        generated_utc = ([DateTime]::UtcNow.ToString('o'))
        generated_by  = $GeneratedBy
        repo_root     = $resolved.repo_root
        data_root     = $resolved.data_root
        machine       = [ordered]@{
            hostname   = $resolved.machine.hostname
            username   = $resolved.machine.username
            os         = $resolved.machine.os
            platform   = $resolved.machine.platform
            is_windows = $resolved.machine.is_windows
            gpu        = [ordered]@{
                present        = $resolved.machine.gpu.present
                name           = $resolved.machine.gpu.name
                vram_total_mib = $resolved.machine.gpu.vram_total_mib
                source         = $resolved.machine.gpu.source
            }
        }
        provenance    = [ordered]@{
            repo_root = $resolved.provenance.repo_root
            data_root = $resolved.provenance.data_root
        }
    }
    $chk = Test-LifeorchConfig -Config ([pscustomobject]$config)
    $json = ($config | ConvertTo-Json -Depth 8)
    $dir = Split-Path -Parent $OutPath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($OutPath, ($json -replace "`r`n", "`n"), $utf8)

    return [pscustomobject]@{ path = $OutPath; config = ([pscustomobject]$config); valid = $chk.valid; errors = $chk.errors }
}

Export-ModuleMember -Function @(
    'Test-JsonAgainstSchema',
    'ConvertFrom-NvidiaSmi',
    'Get-LifeorchGpuInfo',
    'Get-LifeorchMachineProfile',
    'Get-LifeorchRepoRoot',
    'Get-LifeorchDataRoot',
    'Resolve-LifeorchConfig',
    'Test-LifeorchConfig',
    'Write-LifeorchConfig',
    'Get-LoJsonType'
)
