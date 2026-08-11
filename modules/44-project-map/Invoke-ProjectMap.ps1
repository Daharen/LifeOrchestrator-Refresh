<#
.SYNOPSIS
  project.map (module:44) entrypoint -- SKILL_CONTRACT v0.2 wrapper around project_map.py.

.DESCRIPTION
  Deterministic Project Comprehension Bootstrap. This entrypoint is a THIN wrapper: it captures git
  facts as INPUTS (rev-parse HEAD + status --porcelain; dirty EXCLUDES modules/44-project-map/ itself,
  RT1-F18), maps -Action + params to the worker argv, runs the stdlib Python 3.10-compatible worker,
  and re-emits the worker's lifeorch.skill.result/0.1 envelope on stdout (also to result.json in the
  artifact dir). A logical refusal is exit 0 + status:"error" + a machine error.code; nonzero = crash.
  stdout carries ONLY the envelope; human logging goes to stderr. parallel_safe:false.
#>
[CmdletBinding()]
param(
  [ValidateSet('harvest','validate','ingest-claims','render','verify','query','reaffirm','fmt','selftest')]
  [string]$Action = 'validate',
  [string]$Repo,
  [string]$Map,
  [string]$Harvest,
  [string]$Out,
  [string]$Claims,
  [string]$Q,
  [string]$Entity,
  [string]$Fields,
  [string]$By,
  [string]$AtCommit,
  [string]$PathsFile,
  [string]$Override,
  [string[]]$FmtPaths,
  [switch]$Check,
  [switch]$Draft,
  [switch]$NoHarvest,
  [string]$InputsJson,
  [string]$ArtifactRoot,
  [string]$InvocationId,
  [string]$PythonPath,
  [string]$WorkerPath
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $WorkerPath) { $WorkerPath = Join-Path $root 'project_map.py' }
if (-not $PythonPath) {
  # WindowsApps python/python3 are Store alias STUBS (exit 9009) -- exclude them (the D-0129 trap class).
  $pmCands = @((Get-Command python3 -ErrorAction SilentlyContinue), (Get-Command python -ErrorAction SilentlyContinue)) |
    Where-Object { $_ -and $_.Source -and ($_.Source -notmatch 'WindowsApps') }
  if ($pmCands) { $PythonPath = @($pmCands)[0].Source } else { $PythonPath = 'python' }
}
if (-not $InvocationId) { $InvocationId = [guid]::NewGuid().ToString() }
if (-not $ArtifactRoot) { $ArtifactRoot = Join-Path $root (Join-Path 'runtime/artifacts' $InvocationId) }

# ---- merge -InputsJson (named params override matching keys) --------------------------------
if ($InputsJson) {
  try { $ij = $InputsJson | ConvertFrom-Json } catch { $ij = $null }
  if ($ij) {
    foreach ($p in 'action','repo','map','harvest','out','claims','q','entity','fields','by','at_commit','paths_file','override') {
      $val = $ij.$p
      if ($null -ne $val) {
        switch ($p) {
          'action'     { if (-not $PSBoundParameters.ContainsKey('Action'))   { $Action   = $val } }
          'repo'       { if (-not $PSBoundParameters.ContainsKey('Repo'))      { $Repo     = $val } }
          'map'        { if (-not $PSBoundParameters.ContainsKey('Map'))       { $Map      = $val } }
          'harvest'    { if (-not $PSBoundParameters.ContainsKey('Harvest'))   { $Harvest  = $val } }
          'out'        { if (-not $PSBoundParameters.ContainsKey('Out'))       { $Out      = $val } }
          'claims'     { if (-not $PSBoundParameters.ContainsKey('Claims'))    { $Claims   = $val } }
          'q'          { if (-not $PSBoundParameters.ContainsKey('Q'))         { $Q        = $val } }
          'entity'     { if (-not $PSBoundParameters.ContainsKey('Entity'))    { $Entity   = $val } }
          'fields'     { if (-not $PSBoundParameters.ContainsKey('Fields'))    { $Fields   = $val } }
          'by'         { if (-not $PSBoundParameters.ContainsKey('By'))        { $By       = $val } }
          'at_commit'  { if (-not $PSBoundParameters.ContainsKey('AtCommit')) { $AtCommit = $val } }
          'paths_file' { if (-not $PSBoundParameters.ContainsKey('PathsFile')){ $PathsFile= $val } }
          'override'   { if (-not $PSBoundParameters.ContainsKey('Override')) { $Override = $val } }
        }
      }
    }
  }
}

if (-not $Map -and $Action -ne 'harvest' -and $Action -ne 'selftest') { $Map = Join-Path $root 'map' }

# ---- git facts as INPUTS (RT1-F18): HEAD + dirty (dirty excludes modules/44-project-map/) ----
function Get-GitFacts([string]$repoRoot) {
  $head = 'unknown'; $dirty = $false
  if (-not $repoRoot) { return @{ head = $head; dirty = $dirty } }
  try {
    $head = (& git -C $repoRoot rev-parse HEAD 2>$null); if (-not $head) { $head = 'unknown' }
    $porcelain = (& git -C $repoRoot status --porcelain 2>$null)
    foreach ($line in $porcelain) {
      if (-not $line) { continue }
      $p = ($line.Substring(3)).Trim().Replace('\','/')
      if ($p -match '->') { $p = ($p -split '->')[-1].Trim() }
      if (-not $p.StartsWith('modules/44-project-map/')) { $dirty = $true; break }
    }
  } catch { }
  return @{ head = $head; dirty = $dirty }
}

# ---- build worker argv -----------------------------------------------------------------------
$argv = New-Object System.Collections.Generic.List[string]
$argv.Add($Action)
if ($Action -eq 'harvest') {
  if (-not $Repo) { throw 'harvest requires -Repo' }
  $facts = Get-GitFacts $Repo
  if (-not $AtCommit) { $AtCommit = $facts.head }
  $argv.AddRange([string[]]@('--repo', $Repo, '--at-commit', $AtCommit, '--dirty', ($facts.dirty.ToString().ToLower())))
  if ($Out) { $argv.AddRange([string[]]@('--out', $Out)) }
} else {
  if ($Map)      { $argv.AddRange([string[]]@('--map', $Map)) }
  if ($Harvest)  { $argv.AddRange([string[]]@('--harvest', $Harvest)) }
  if ($Out)      { $argv.AddRange([string[]]@('--out', $Out)) }
  if ($Claims)   { $argv.AddRange([string[]]@('--claims', $Claims)) }
  if ($Q)        { $argv.AddRange([string[]]@('--q', $Q)) }
  if ($Entity)   { $argv.AddRange([string[]]@('--entity', $Entity)) }
  if ($Fields)   { $argv.AddRange([string[]]@('--fields', $Fields)) }
  if ($By)       { $argv.AddRange([string[]]@('--by', $By)) }
  if ($AtCommit) { $argv.AddRange([string[]]@('--at-commit', $AtCommit)) }
  if ($PathsFile){ $argv.AddRange([string[]]@('--paths-file', $PathsFile)) }
  if ($Override) { $argv.AddRange([string[]]@('--override', $Override)) }
  if ($FmtPaths) { $argv.Add('--fmt-paths'); foreach ($fp in $FmtPaths) { $argv.Add($fp) } }
  if ($Check)    { $argv.Add('--check') }
  if ($Draft)    { $argv.Add('--draft') }
  if ($NoHarvest){ $argv.Add('--no-harvest') }
}

# ---- run worker; stdout is the envelope only -------------------------------------------------
[Console]::Error.WriteLine("project.map: $PythonPath $WorkerPath $($argv -join ' ')")
$stdout = & $PythonPath $WorkerPath @argv
$code = $LASTEXITCODE

if ($code -ne 0) {
  [Console]::Error.WriteLine("project.map worker crashed (exit $code) -- no valid envelope")
  exit $code
}

# persist result.json to the artifact dir (per SKILL_CONTRACT s3); stdout stays the single envelope
try {
  New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null
  $envelopeText = ($stdout | Select-Object -Last 1)
  Set-Content -Path (Join-Path $ArtifactRoot 'result.json') -Value $envelopeText -Encoding utf8 -NoNewline
} catch { }

$stdout | ForEach-Object { Write-Output $_ }
exit 0
