#requires -Version 7.0
<#
 ops/close-refold.ps1 -- N7 close-time PCB currency driver (D-0143, i52; kills I51 F2).
 EVERY iteration close (INCLUDING doc-only closes) re-folds modules/44 so the shipped map + BOOT_PACKET
 are in-sync at HEAD. Run AFTER the last doc commit of the close, via the executor (tempdir/delete ops
 must not run from the mount VM); the map/ + generated/ commit is then the FINAL close commit (RT1-F11).
 This script runs NO git writes; the close flow commits under the git lease as usual.

 Modes:
   -Mode verify   harvest at HEAD + verify; prints the stale summary (orchestrator REVIEWS the list)
   -Mode fold     + reaffirms from -ReaffirmSpec (JSON array [{"entity":"<id>","fields":"<csv>"}]) --
                  an ORCHESTRATOR-REVIEWED judgment list, recorded via reaffirm's by/at-commit -- then
                  validate (0 errors required) + render + render -Check.
 Claims corrections (semantic drift, not mere restamps) go through ingest-claims BEFORE this script,
 in the normal fold order: overlay/claims edits first, then re-fold. Acceptance each close: verify
 reports 0 stale on the overlay boot_read set at HEAD (and validate 0 in fold mode).
#>
param(
  [ValidateSet('verify','fold')][string]$Mode = 'verify',
  [string]$Repo = 'C:\Users\just_\LifeOrchestrator-Refresh',
  [string]$By = 'orchestrator-close',
  [string]$ReaffirmSpec = '',
  [string]$Ledger = '',
  [int]$Iteration = 0,
  [string[]]$ArtifactsDirs = @('modules\44-project-map\runtime\artifacts','modules\30-orchestrate-fanout\runtime\artifacts'),
  [string]$GateOutDir = '',
  [double]$MinBoundedFraction = 0,
  [string]$Date = ''
)
$ErrorActionPreference = 'Stop'
Set-Location $Repo
$m44   = Join-Path $Repo 'modules\44-project-map'
$entry = Join-Path $m44 'Invoke-ProjectMap.ps1'
$mapD  = Join-Path $m44 'map'
$genD  = Join-Path $m44 'generated'
$work  = Join-Path $m44 'runtime\close-refold'
New-Item -ItemType Directory -Force -Path $work | Out-Null
# resolve python once (exclude WindowsApps Store stubs, D-0129); used by reaffirm/gate/manager-view/consistency.
$pyCands0 = @((Get-Command python3 -ErrorAction SilentlyContinue), (Get-Command python -ErrorAction SilentlyContinue)) |
  Where-Object { $_ -and ($_.Source -notmatch 'WindowsApps') }
$py = if ($pyCands0) { @($pyCands0)[0].Source } else { 'python' }

# ---- FOLD-MODE FAIL-CLOSED GUARD (i61, D-0158): the canonical close CANNOT run without a real session
#      retrieval ledger + a valid iteration. An omitted / nonexistent / malformed ledger or an invalid
#      iteration MUST fail BEFORE any render -- there is NO silent SKIPPED route through the close.
#      Verify-only mode stays ledger-independent (this guard is fold-only). ----
if ($Mode -eq 'fold') {
  if ([string]::IsNullOrWhiteSpace($Ledger)) {
    throw 'close-refold fold: -Ledger is MANDATORY (the session retrieval ledger). Refusing to close without measured retrieval evidence -- no silent SKIP.'
  }
  if (-not (Test-Path -LiteralPath $Ledger -PathType Leaf)) {
    throw "close-refold fold: -Ledger not found: $Ledger"
  }
  if ($Iteration -le 0) {
    throw "close-refold fold: -Iteration must be a positive integer (got $Iteration)."
  }
  # PRE-RENDER gate (fail-closed, NO write): parse the ledger (malformed -> abort) + assert the gate(s) --
  # the zero-bounded floor always; the meaningful-fraction raise when -MinBoundedFraction > 0. Runs BEFORE
  # harvest/render so a bad ledger or an un-adopted session aborts the close BEFORE it renders.
  $mon0 = Join-Path $Repo 'ops/audit/gen-retrieval-monitor.py'
  $pre = New-Object System.Collections.Generic.List[string]
  $pre.Add('--ledger'); $pre.Add($Ledger); $pre.Add('--iteration'); $pre.Add("$Iteration")
  $pre.Add('--gate'); $pre.Add('--check-only')
  if ($MinBoundedFraction -gt 0) { $pre.Add('--min-bounded-fraction'); $pre.Add("$MinBoundedFraction") }
  & $py $mon0 @pre 1> (Join-Path $work 'env-gate-precheck.json') 2> (Join-Path $work 'e-gate-precheck.err')
  if ($LASTEXITCODE -ne 0) {
    $pt = (Get-Content -Raw (Join-Path $work 'env-gate-precheck.json') -ErrorAction SilentlyContinue)
    $pe = (Get-Content -Raw (Join-Path $work 'e-gate-precheck.err') -ErrorAction SilentlyContinue)
    throw "close-refold fold: PRE-RENDER retrieval gate FAILED (exit $LASTEXITCODE) -- aborting BEFORE render. $pt $pe"
  }
  Write-Output 'close-refold: pre-render retrieval gate PASS (ledger valid; gate(s) satisfied).'
}
$hv   = Join-Path $work 'harvest-close.json'
$head = (& git -C $Repo rev-parse HEAD).Trim()

# 1. harvest at HEAD (entrypoint captures HEAD/dirty itself; envelope -> file, i48 capture lesson)
& $entry -Action harvest -Repo $Repo -Out $hv 1> (Join-Path $work 'env-harvest.json')
if ($LASTEXITCODE -ne 0) { throw "harvest crashed (exit $LASTEXITCODE)" }
$envH = Get-Content -Raw (Join-Path $work 'env-harvest.json') | ConvertFrom-Json
if ($envH.status -ne 'ok') { throw "harvest refused: $($envH.error.code)" }

# 2. verify (freshness sweep) -- full envelope stays on file for review
& $entry -Action verify -Map $mapD -Harvest $hv 1> (Join-Path $work 'env-verify.json')
if ($LASTEXITCODE -ne 0) { throw "verify crashed (exit $LASTEXITCODE)" }
$envV = Get-Content -Raw (Join-Path $work 'env-verify.json') | ConvertFrom-Json
$staleList = @()
if ($null -ne $envV.result -and $null -ne $envV.result.stale) { $staleList = @($envV.result.stale) }
Write-Output ("close-refold: mode={0} head={1} verify_status={2} stale_entries={3} envelope={4}" -f `
  $Mode, $head, $envV.status, $staleList.Count, (Join-Path $work 'env-verify.json'))

if ($Mode -eq 'verify') {
  Write-Output 'close-refold: VERIFY-ONLY -- review the stale list, then re-run -Mode fold with -ReaffirmSpec.'
  exit 0
}

# 3. reaffirms (reviewed list; empty spec = no restamps needed this close).
#    D-0147 follow-on: run the WHOLE reviewed spec in ONE process via reaffirm_batch.py. The prior
#    per-entity subprocess loop raced ACROSS PROCESSES on the whole-file map writes (a later reaffirm
#    reloaded a stale meta.json and clobbered earlier restamps), so most restamps silently did not
#    persist. One process = synchronous in-process load/write = correct accumulation.
$n = 0
if ($ReaffirmSpec -and (Test-Path -LiteralPath $ReaffirmSpec)) {
  $specRaw = Get-Content -Raw -LiteralPath $ReaffirmSpec | ConvertFrom-Json
  $n = @($specRaw).Count
  if ($n -gt 0) {
    # resolve python as Invoke-ProjectMap.ps1 does (exclude WindowsApps Store stubs, D-0129)
    $pyCands = @((Get-Command python3 -ErrorAction SilentlyContinue), (Get-Command python -ErrorAction SilentlyContinue)) |
      Where-Object { $_ -and ($_.Source -notmatch 'WindowsApps') }
    $py = if ($pyCands) { @($pyCands)[0].Source } else { 'python' }
    $batch = Join-Path $m44 'reaffirm_batch.py'
    $ef = Join-Path $work 'env-reaffirm-batch.json'
    & $py $batch --map $mapD --harvest $hv --spec $ReaffirmSpec --by $By --at-commit $head 1> $ef
    if ($LASTEXITCODE -ne 0) { throw "reaffirm-batch crashed (exit $LASTEXITCODE)" }
    $er = Get-Content -Raw $ef | ConvertFrom-Json
    if ($er.status -ne 'ok') { throw "reaffirm-batch refused: $($er.error.code)" }
  }
}
Write-Output ("close-refold: reaffirmed={0}" -f $n)

# 4. validate -- MUST be clean before any render
& $entry -Action validate -Map $mapD -Harvest $hv 1> (Join-Path $work 'env-validate.json')
if ($LASTEXITCODE -ne 0) { throw "validate crashed (exit $LASTEXITCODE)" }
$envVal = Get-Content -Raw (Join-Path $work 'env-validate.json') | ConvertFrom-Json
if ($envVal.status -ne 'ok') { throw "validate NOT clean: $($envVal.error.code) -- fix claims/overlay, re-run" }

# 5. render (non-draft, real generated/) + 6. drift check
& $entry -Action render -Map $mapD -Harvest $hv -Out $genD 1> (Join-Path $work 'env-render.json')
if ($LASTEXITCODE -ne 0) { throw "render crashed (exit $LASTEXITCODE)" }
$envR = Get-Content -Raw (Join-Path $work 'env-render.json') | ConvertFrom-Json
if ($envR.status -ne 'ok') { throw "render refused: $($envR.error.code)" }
& $entry -Action render -Map $mapD -Harvest $hv -Out $genD -Check 1> (Join-Path $work 'env-check.json')
if ($LASTEXITCODE -ne 0) { throw "render -Check crashed (exit $LASTEXITCODE)" }
$envC = Get-Content -Raw (Join-Path $work 'env-check.json') | ConvertFrom-Json
if ($envC.status -ne 'ok') { throw "render -Check drift: $($envC.error.code)" }

# 6c. MANAGER_VIEW currency (i61, D-0158): REGENERATE from the (possibly corrected) overlay so a corrected
#     overlay can NEVER leave MANAGER_VIEW stale (the i60 regression), then assert --check clean. MANAGER_VIEW
#     is thereby always part of the close/rebuild path.
$mgrGen = Join-Path $Repo 'ops/manager/gen-manager-view.py'
$mgrArgs = New-Object System.Collections.Generic.List[string]
$mgrArgs.Add('--repo'); $mgrArgs.Add($Repo)
if ($Date) { $mgrArgs.Add('--date'); $mgrArgs.Add($Date) }
& $py $mgrGen @mgrArgs 1> (Join-Path $work 'env-managerview.json') 2> (Join-Path $work 'e-managerview.err')
if ($LASTEXITCODE -ne 0) { throw "MANAGER_VIEW regenerate FAILED (exit $LASTEXITCODE): $(Get-Content -Raw (Join-Path $work 'e-managerview.err') -ErrorAction SilentlyContinue)" }
& $py $mgrGen @mgrArgs --check 1> (Join-Path $work 'env-managerview-check.json') 2> (Join-Path $work 'e-managerview-check.err')
if ($LASTEXITCODE -ne 0) { throw "MANAGER_VIEW --check drift after regenerate (exit $LASTEXITCODE)" }
Write-Output 'close-refold: MANAGER_VIEW regenerated + --check clean.'

# 6b. RETRIEVAL GATE (i60, D-0157): wire gen-retrieval-monitor --gate FAIL-CLOSED into the close path.
#     A session that whole-opened docs with ZERO bounded queries CANNOT close (the zero-bounded floor;
#     i61 raises it to a meaningful bounded fraction). Also emits the standing retrieval-bytes-log row.
#     Backward-compatible: skipped when -Ledger is not provided.
if ($Ledger -and (Test-Path -LiteralPath $Ledger)) {
  $pyG = @((Get-Command python3 -ErrorAction SilentlyContinue), (Get-Command python -ErrorAction SilentlyContinue)) |
    Where-Object { $_ -and ($_.Source -notmatch 'WindowsApps') }
  $pyG = if ($pyG) { @($pyG)[0].Source } else { 'python' }
  $mon = Join-Path $Repo 'ops\audit\gen-retrieval-monitor.py'
  $god = if ($GateOutDir) { $GateOutDir } else { Join-Path $Repo 'ops\out' }
  $adArgs = New-Object System.Collections.Generic.List[string]
  foreach ($d in $ArtifactsDirs) { $adArgs.Add('--artifacts-dir'); $adArgs.Add($d) }
  $gout = Join-Path $work 'env-retrieval-gate.json'
  $mbf = if ($MinBoundedFraction -gt 0) { @('--min-bounded-fraction', "$MinBoundedFraction") } else { @() }
  & $pyG $mon --ledger $Ledger --iteration $Iteration --gate --out-dir $god @mbf @adArgs 1> $gout 2> (Join-Path $work 'e-gate.err')
  $grc = $LASTEXITCODE
  $rowTxt = (Get-Content -Raw $gout -ErrorAction SilentlyContinue)
  if ($grc -ne 0) { throw "RETRIEVAL GATE FAILED (exit $grc): zero bounded queries alongside whole-doc opens -- bounded retrieval not adopted this session. Row: $rowTxt" }
  $jsonLine = ($rowTxt -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1)
  try { $row = $jsonLine | ConvertFrom-Json; Write-Output ("close-refold: retrieval-gate PASS gate={0} bounded_fraction={1} boot_packet={2}B" -f $row.gate.status, $row.bounded_fraction, $row.boot_packet_bytes) }
  catch { Write-Output "close-refold: retrieval-gate PASS (monitor exit 0); row summary unparsed" }
} else {
  Write-Output 'close-refold: retrieval-gate SKIPPED (no -Ledger provided)'
}

# 6d. CROSS-SURFACE AGREEMENT (i61, D-0158): overlay / BOOT_PACKET / MANAGER_VIEW / CURRENT_STATE / handoff
#     agree on current iteration, next iteration, retrieval-gate state; + COLD_BOOT_CARD stamp currency.
$cc = Join-Path $Repo 'ops/audit/close-consistency-check.py'
& $py $cc --repo $Repo 1> (Join-Path $work 'env-consistency.json') 2> (Join-Path $work 'e-consistency.err')
if ($LASTEXITCODE -ne 0) { throw "close-refold fold: CROSS-SURFACE CONSISTENCY FAILED (exit $LASTEXITCODE): $(Get-Content -Raw (Join-Path $work 'env-consistency.json') -ErrorAction SilentlyContinue)" }
Write-Output 'close-refold: cross-surface consistency PASS.'

$pkt = Join-Path $genD 'BOOT_PACKET.md'
$pktBytes = if (Test-Path $pkt) { (Get-Item $pkt).Length } else { -1 }
Write-Output ("close-refold: FOLD OK head={0} reaffirmed={1} validate=ok render=ok check=ok packet_bytes={2}" -f $head, $n, $pktBytes)
Write-Output 'close-refold: now commit map/ + generated/ + ops/manager/generated/MANAGER_VIEW.md + ops/out/retrieval-bytes-log.jsonl as the FINAL close commit (git lease; named paths).'
exit 0
