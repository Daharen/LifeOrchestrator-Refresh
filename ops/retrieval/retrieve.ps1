<#
.SYNOPSIS
  retrieve.ps1 (ops/retrieval) -- i60 Increment A: the one-verb BOUNDED-QUERY affordance that makes the
  EASY retrieval path the MEASURED path (D-0146 F-i53-eff; PB-8; plan fo-60-d578e353, worker II-BOUND-i60).

.DESCRIPTION
  ONE verb. Given -Q <form> -Repo <root> [-Harvest <h>] -Ledger <path> it:
    (a) invokes modules/44-project-map/Invoke-ProjectMap.ps1 -Action query with those args (read-only),
    (b) on envelope status:ok computes charged_bytes = the UTF-8/LF-normalized byte length of the rendered
        result payload that entered context (the canonical minified serialization of the envelope's
        `result` object -- see BYTE-CHARGING below),
    (c) appends ONE valid ledger line {kind,target,bytes} to -Ledger (created if absent), where kind is
        derived from the --q prefix (section:->section, card:->card, everything else->query) and target is
        the exact -Q form,
    (d) re-emits the query envelope on stdout UNCHANGED.
  FAIL-CLOSED: a non-ok query (wrapper crash, or an envelope whose status != "ok") appends NOTHING and
  exits non-zero. The affordance writes ONLY to -Ledger (+ its parent dir if absent) and stdout; it is
  READ-ONLY everywhere else. Deterministic; no model; no network.

  BYTE-CHARGING (the charged-byte method, I53_RESULTS.md/EFFICIENCY-i53.md = "the size of what actually
  entered model-visible context, per open"): the retrieval-side analog of the monitor's whole_doc_open
  full-file byte size is the size of the QUERY OUTPUT that entered context -- the envelope's `result`
  payload (NOT the whole envelope: the envelope wrapper carries wall-clock started_at_utc/finished_at_utc
  timestamps, so charging it would be non-deterministic and break the double-run gate). charged_bytes is
  computed by the CANONICAL BYTE ORACLE: the UTF-8 byte length of
  json.dumps(result, ensure_ascii=False, separators=(",",":")), evaluated by python -- the SAME runtime the
  project.map query worker already runs under, so the affordance's self-charge is byte-identical to any
  independent python audit of the same payload (the i60 red-team showed a pure-pwsh ConvertTo-Json measure
  diverges from python on U+0085/U+2028/U+2029, out-of-range integers, and array-shaped payloads; delegating
  the count to python closes that gap and makes the cross-language claim true by construction). Deterministic
  + reproducible: the acceptance test recomputes it with the same oracle and asserts equality.

.PARAMETER Q
  The bounded query form passed to project.map, e.g. 'card:module:40', 'entity:module:36/artifact.search',
  'section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header'. Also the ledger `target`.

.PARAMETER Repo
  Repo root. Used to locate the project.map entrypoint and forwarded to the wrapper as -Repo (forward
  compatible with the FO-6 fix; harmless today where the wrapper's query branch drops it). Not required
  in -EnvelopeFile dry-run mode.

.PARAMETER Harvest
  Optional harvest.json passed through to the wrapper. card: and section: forms REQUIRE it (stale marking /
  file location are part of those contracts); plain entity:/edges:/deeper: forms do not.

.PARAMETER Ledger
  The append-only retrieval ledger (JSONL) this affordance writes to. Created (with parent dir) if absent.

.PARAMETER MapEntrypoint
  Override the project.map entrypoint path. Default: <Repo>/modules/44-project-map/Invoke-ProjectMap.ps1.

.PARAMETER EnvelopeFile
  DRY-RUN: read the query envelope from this file instead of invoking the wrapper. Everything else is
  identical (kind derivation, byte charging, fail-closed status check, ledger append, stdout re-emit).
  This is the path the off-box cloud gate uses over a fixture query envelope.

.PARAMETER PwshPath
  pwsh executable used to invoke the wrapper (default: the current pwsh, else 'pwsh').

.PARAMETER PythonPath
  python used as the canonical byte oracle (default: resolved python3/python, excluding the WindowsApps
  Store alias stubs). Read-only; computes a byte count and nothing else.

.NOTES
  Exit codes: 0 = ok (envelope re-emitted, ONE ledger line appended). Non-zero = FAIL-CLOSED, nothing
  appended: 2 = usage/input error; 3 = wrapper crashed (non-zero exit); 4 = envelope status != "ok"
  (logical refusal / error, case-sensitive); 5 = envelope unparseable / not a JSON object / missing
  `result` / the python byte oracle failed.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Q,
  [string]$Repo,
  [string]$Harvest,
  [Parameter(Mandatory = $true)][string]$Ledger,
  [string]$MapEntrypoint,
  [string]$EnvelopeFile,
  [string]$PwshPath,
  [string]$PythonPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Write-Err([string]$msg) { [Console]::Error.WriteLine("retrieve: $msg") }

# ---- kind from the --q prefix (section:/card: -> that kind; everything else -> query) ---------
function Get-KindFromQ([string]$q) {
  if ($q.StartsWith('section:')) { return 'section' }
  if ($q.StartsWith('card:'))    { return 'card' }
  return 'query'
}

# ---- resolve python (the byte oracle): exclude the WindowsApps Store alias stubs (D-0129 trap) -
function Resolve-Python([string]$override) {
  if ($override) { return $override }
  $cands = @((Get-Command python3 -ErrorAction SilentlyContinue),
             (Get-Command python  -ErrorAction SilentlyContinue)) |
    Where-Object { $_ -and $_.Source -and ($_.Source -notmatch 'WindowsApps') }
  if ($cands) { return @($cands)[0].Source }
  return 'python3'
}

# ---- charged_bytes via the CANONICAL BYTE ORACLE: python len(json.dumps(result,
#      ensure_ascii=False, separators=(",",":")).encode("utf-8")). Returns -1 on any failure so the
#      caller fails closed. The envelope emitted by the worker is pure ASCII (json.dumps default), but
#      set UTF-8 on the pipe so a UTF-8 dry-run fixture also survives intact. --------------------
function Get-ChargedBytes([string]$envelopeText, [string]$pythonExe) {
  # The envelope is handed to python as BASE64 over stdin (pure ASCII -> pipe-safe on every OS). Piping the
  # raw envelope text mangles Unicode line-separators (U+0085/U+2028/U+2029) through the Windows native-stdin
  # encoder (measured: +15 B); base64 sidesteps the native pipe's text handling entirely. python decodes,
  # extracts `result`, and returns the canonical-minified UTF-8 byte length.
  $pyCode = @'
import sys, json, base64
try:
    env = json.loads(base64.b64decode(sys.stdin.read()).decode("utf-8"))
except Exception:
    sys.exit(21)
if not isinstance(env, dict) or env.get("result") is None:
    sys.exit(22)
r = env["result"]
sys.stdout.write(str(len(json.dumps(r, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))))
'@
  $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($envelopeText))
  $prevEnc = $OutputEncoding
  try {
    $OutputEncoding = [System.Text.ASCIIEncoding]::new()
    $out = ($b64 | & $pythonExe -c $pyCode)
    if ($LASTEXITCODE -ne 0) { return -1 }
    $n = 0
    if ([int]::TryParse(([string]$out).Trim(), [ref]$n) -and $n -gt 0) { return $n }
    return -1
  } catch {
    return -1
  } finally {
    $OutputEncoding = $prevEnc
  }
}

# ---- obtain the raw envelope text (dry-run file, or a real wrapper invocation) -----------------
function Get-EnvelopeText {
  if ($EnvelopeFile) {
    if (-not (Test-Path -LiteralPath $EnvelopeFile -PathType Leaf)) {
      Write-Err "envelope file not found: $EnvelopeFile"; exit 2
    }
    return Get-Content -LiteralPath $EnvelopeFile -Raw
  }

  if (-not $Repo) { Write-Err "-Repo is required (or use -EnvelopeFile for a dry-run)"; exit 2 }
  $entry = $MapEntrypoint
  if (-not $entry) { $entry = Join-Path $Repo (Join-Path 'modules/44-project-map' 'Invoke-ProjectMap.ps1') }
  if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) {
    Write-Err "project.map entrypoint not found: $entry"; exit 2
  }
  $pwshExe = $PwshPath
  if (-not $pwshExe) {
    $pwshExe = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if (-not $pwshExe) { $pwshExe = 'pwsh' }
  }

  # Forward -Repo (forward-compatible with the FO-6 fix) and -Harvest when present.
  $wrapArgs = @('-NoProfile', '-File', $entry, '-Action', 'query', '-Q', $Q, '-Repo', $Repo)
  if ($Harvest) { $wrapArgs += @('-Harvest', $Harvest) }

  # Child stdout carries ONLY the envelope (the worker writes diagnostics to stderr); we keep the last
  # non-empty line, mirroring the wrapper's own Select-Object -Last 1.
  $stdout = & $pwshExe @wrapArgs
  $code = $LASTEXITCODE
  if ($code -ne 0) { Write-Err "project.map wrapper crashed (exit $code) -- fail-closed, nothing appended"; exit 3 }
  $lines = @()
  if ($null -ne $stdout) { $lines = @($stdout | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() -ne '' }) }
  if ($lines.Count -eq 0) { Write-Err "wrapper produced no envelope on stdout -- fail-closed"; exit 5 }
  return $lines[$lines.Count - 1]
}

# ---- main --------------------------------------------------------------------------------------
$kind = Get-KindFromQ $Q
$pythonExe = Resolve-Python $PythonPath
$envelopeText = Get-EnvelopeText
if ($null -eq $envelopeText) { Write-Err "empty envelope -- fail-closed, nothing appended"; exit 5 }
$envelopeText = ([string]$envelopeText -replace "`r`n", "`n") -replace "`r", "`n"
$envelopeTrimmed = $envelopeText.Trim()
if ($envelopeTrimmed -eq '') { Write-Err "blank envelope -- fail-closed, nothing appended"; exit 5 }

try {
  $envObj = $envelopeTrimmed | ConvertFrom-Json
} catch {
  Write-Err "envelope is not valid JSON -- fail-closed, nothing appended"; exit 5
}

# Re-emit whatever project.map returned on stdout UNCHANGED (contract step d) -- for ok AND non-ok.
Write-Output $envelopeTrimmed

# A well-formed envelope is a single JSON object; a null/array/scalar top level is malformed.
if ($null -eq $envObj -or $envObj -is [System.Array] -or $envObj -isnot [pscustomobject]) {
  Write-Err "envelope is not a JSON object -- fail-closed, nothing appended"; exit 5
}

$status = $null
if ($envObj.PSObject.Properties.Name -contains 'status') { $status = [string]$envObj.status }
# Case-SENSITIVE: the worker emits lowercase "ok"; anything else (incl. "OK"/"Ok") fails closed.
if ($status -cne 'ok') {
  Write-Err "envelope status is '$status' (not ok) -- fail-closed, nothing appended"; exit 4
}
if (-not ($envObj.PSObject.Properties.Name -contains 'result') -or $null -eq $envObj.result) {
  Write-Err "ok envelope has no result payload -- fail-closed, nothing appended"; exit 5
}

$charged = Get-ChargedBytes $envelopeTrimmed $pythonExe
if ($charged -le 0) {
  Write-Err "charged_bytes could not be computed (python byte oracle failed) -- fail-closed"; exit 5
}

# Build ONE canonical ledger line the monitor accepts: {kind,target,bytes} (compact, sorted keys, LF).
$entry = [ordered]@{ bytes = [int]$charged; kind = $kind; target = $Q }
$line = ($entry | ConvertTo-Json -Compress -Depth 5)

# Append LAST (only after every check passed), atomically, LF-terminated, UTF-8 no BOM. Create parent dir.
$parent = Split-Path -Parent $Ledger
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::AppendAllText($Ledger, $line + "`n", $utf8NoBom)

exit 0
