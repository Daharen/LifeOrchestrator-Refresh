#requires -Version 7.0
<#
 ops/frontdoor/Rebuild-FrontDoors.ps1 -- the UNIFORM REBUILD interface (i59, hardened s8 rule 1).
 The START_HERE boot kernel names THIS one verb (fixed O(1) text). It rebuilds + verifies every
 front-door class registered in ops/frontdoor/registry.json and asserts each boot_read class is
 0-stale. Non-vacuity floor (red-team A2-BREAK3): >=1 boot_read class, the named-required root-pcb
 present + boot_read + non-empty artifact. Prints ONE JSON envelope; exits non-zero on any failure.

   -VerifyOnly   harvest + verify each class (no render); serves the kernel Mode-A verify.
   (default)     harvest -> rebuild (validate/render/-Check) -> verify each class.

 Runs NO git writes. On the box, invoke via the executor (render/-Check tempdirs). This script is a
 RECOVERY rebuild (re-render the generated views from the committed map/), NOT a close-fold: it does
 no reviewed reaffirms (that judgment stays in ops/close-refold.ps1).
#>
param(
  [switch]$VerifyOnly,
  [string]$Repo = 'C:\Users\just_\LifeOrchestrator-Refresh',
  [string]$RegistryPath = ''
)
$ErrorActionPreference = 'Stop'
Set-Location $Repo
if (-not $RegistryPath) { $RegistryPath = Join-Path $Repo 'ops\frontdoor\registry.json' }

function Fail([string]$msg) {
  $env = [ordered]@{ status = 'error'; verify_only = [bool]$VerifyOnly; error = $msg; classes = @() }
  Write-Output ($env | ConvertTo-Json -Depth 6)
  exit 1
}

if (-not (Test-Path $RegistryPath)) { Fail "registry not found: $RegistryPath" }
$reg = Get-Content -Raw $RegistryPath | ConvertFrom-Json
$classes = @(); if ($null -ne $reg.classes) { $classes = @($reg.classes) }
if ($classes.Count -lt 1) { Fail 'registry has 0 classes (vacuous)' }

# non-vacuity: >=1 boot_read class + the named-required root-pcb present with boot_read:true
$bootRead = @($classes | Where-Object { $_.boot_read -eq $true })
if ($bootRead.Count -lt 1) { Fail 'no boot_read class registered (vacuous 0-stale)' }
$root = @($classes | Where-Object { $_.class_id -eq 'root-pcb' })
if ($root.Count -ne 1 -or $root[0].boot_read -ne $true) { Fail 'named-required class root-pcb absent or not boot_read' }

$work = Join-Path $Repo 'modules\44-project-map\runtime\frontdoor'
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Sub([string]$s, [hashtable]$tok) {
  foreach ($k in $tok.Keys) { $s = $s.Replace($k, $tok[$k]) }
  return $s
}
function RunStep($step, [hashtable]$tok, [string]$envFile) {
  $cmd  = Sub $step.cmd $tok
  $args = @(); foreach ($a in @($step.args)) { $args += (Sub $a $tok) }
  & pwsh -NoProfile -File $cmd @args 1> $envFile 2> (Join-Path $work 'stderr.txt')
  return $LASTEXITCODE
}

$results = @()
$allOk = $true
foreach ($c in $classes) {
  $entry = Join-Path $Repo ($c.entry -replace '/', '\')
  $mapD  = Join-Path $Repo ($c.map -replace '/', '\')
  $genD  = Join-Path $Repo ($c.generated -replace '/', '\')
  $hv    = Join-Path $work ("harvest-" + $c.class_id + ".json")
  $tok = @{ '{ENTRY}' = $entry; '{REPO}' = $Repo; '{MAP}' = $mapD; '{GENERATED}' = $genD; '{HARVEST}' = $hv }

  $classOk = $true
  $stale = -1
  $bytes = 0

  # 1. harvest
  $he = Join-Path $work ("env-harvest-" + $c.class_id + ".json")
  if ((RunStep $c.harvest $tok $he) -ne 0) { $classOk = $false }
  else { $eh = Get-Content -Raw $he | ConvertFrom-Json; if ($eh.status -ne 'ok') { $classOk = $false } }

  # 2. rebuild (unless VerifyOnly)
  if ($classOk -and -not $VerifyOnly) {
    foreach ($rs in @($c.rebuild)) {
      $re = Join-Path $work ("env-rebuild-" + $c.class_id + ".json")
      if ((RunStep $rs $tok $re) -ne 0) { $classOk = $false; break }
      $er = Get-Content -Raw $re | ConvertFrom-Json
      if ($er.status -ne 'ok') { $classOk = $false; break }
    }
  }

  # 3. verify -> stale count
  if ($classOk) {
    $ve = Join-Path $work ("env-verify-" + $c.class_id + ".json")
    if ((RunStep $c.verify $tok $ve) -ne 0) { $classOk = $false }
    else {
      $ev = Get-Content -Raw $ve | ConvertFrom-Json
      $sl = @(); if ($null -ne $ev.result -and $null -ne $ev.result.stale) { $sl = @($ev.result.stale) }
      $stale = $sl.Count
      if ($ev.status -ne 'ok' -or $stale -ne 0) { $classOk = $false }
    }
  }

  # 4. boot_read artifact present + non-empty (non-vacuity)
  if ($classOk -and $c.boot_read -eq $true) {
    $art = Join-Path $Repo ($c.boot_read_artifact -replace '/', '\')
    if (-not (Test-Path $art)) { $classOk = $false }
    else { $bytes = (Get-Item $art).Length; if ($bytes -le 0) { $classOk = $false } }
  }

  if (-not $classOk) { $allOk = $false }
  $results += [ordered]@{ class_id = $c.class_id; boot_read = [bool]$c.boot_read; ok = $classOk; stale = $stale; artifact_bytes = $bytes }
}

$envOut = [ordered]@{
  status      = $(if ($allOk) { 'ok' } else { 'error' })
  verify_only = [bool]$VerifyOnly
  class_count = $classes.Count
  boot_read_count = $bootRead.Count
  classes     = $results
}
Write-Output ($envOut | ConvertTo-Json -Depth 6)
if (-not $allOk) { exit 1 }
exit 0
