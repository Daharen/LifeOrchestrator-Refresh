<#
.SYNOPSIS
  Off-box cloud gate for ops/retrieval/retrieve.ps1 (i60 A; FANOUT_AGENT_001 / II-BOUND-i60).
  Self-contained pwsh 7 (no Pester dependency): the affordance dry-run over fixture query envelopes,
  charged-byte equality, kind derivation, fail-closed on non-ok, and append/determinism.
  Run: pwsh -NoProfile -File ops/retrieval/tests/Invoke-RetrieveTests.ps1
  Exit 0 = all pass; exit 1 = one or more failed.
#>
[CmdletBinding()]
param(
  [string]$PwshExe = 'pwsh',   # pwsh used to run the affordance under test (no PATH dependency on the box)
  [string]$PyExe = ''          # python (byte-oracle recompute); resolved from python3/python if empty
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$HEREPATH = Split-Path -Parent $MyInvocation.MyCommand.Path
$RETRIEVE = Join-Path (Split-Path -Parent $HEREPATH) 'retrieve.ps1'
$FIX = Join-Path $HEREPATH 'fixtures'
$script:pass = 0
$script:fail = 0

if (-not $PyExe) {
  $pyc = @((Get-Command python3 -ErrorAction SilentlyContinue),
           (Get-Command python  -ErrorAction SilentlyContinue)) |
    Where-Object { $_ -and $_.Source -and ($_.Source -notmatch 'WindowsApps') }
  $PyExe = if ($pyc) { @($pyc)[0].Source } else { 'python3' }
}

function Assert([bool]$cond, [string]$name) {
  if ($cond) { $script:pass++; Write-Host "  ok   $name" }
  else { $script:fail++; Write-Host "  FAIL $name" -ForegroundColor Red }
}

function New-Ledger { return (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.jsonl')) }

# recompute charged bytes with the CANONICAL BYTE ORACLE (python json.dumps, ensure_ascii=False, compact)
# -- the independent recomputation for the "bytes == recomputed length of the returned payload" assertion.
function Recompute-Bytes([string]$envFile) {
  $pyCode = @'
import sys, json
env = json.load(open(sys.argv[1], encoding="utf-8"))
r = env["result"]
sys.stdout.write(str(len(json.dumps(r, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))))
'@
  $out = (& $PyExe -c $pyCode $envFile)
  return [int](([string]$out).Trim())
}

function Invoke-Retrieve([string]$q, [string]$ledger, [string]$envFile) {
  $out = & $PwshExe -NoProfile -File $RETRIEVE -Q $q -Ledger $ledger -EnvelopeFile $envFile -PythonPath $PyExe 2>$null
  return @{ code = $LASTEXITCODE; stdout = ($out -join "`n") }
}

function Get-LastLedgerObj([string]$ledger) {
  $lines = @(Get-Content -LiteralPath $ledger | Where-Object { $_.Trim() -ne '' })
  if ($lines.Count -eq 0) { return $null }
  return ($lines[$lines.Count - 1] | ConvertFrom-Json)
}

Write-Host "== retrieve.ps1 dry-run acceptance =="

# --- card: (the named acceptance form) ---------------------------------------------------------
$led = New-Ledger
$r = Invoke-Retrieve 'card:module:40' $led (Join-Path $FIX 'card-ok.json')
Assert ($r.code -eq 0) 'card: exit 0'
$obj = Get-LastLedgerObj $led
Assert ($null -ne $obj) 'card: one ledger line appended'
Assert ($obj.kind -eq 'card') 'card: kind == card'
Assert ($obj.target -eq 'card:module:40') 'card: target == exact -Q form'
$expected = Recompute-Bytes (Join-Path $FIX 'card-ok.json')
Assert ($obj.bytes -eq $expected) "card: bytes == recomputed payload length ($($obj.bytes) == $expected)"
Assert ($obj.bytes -eq 420) 'card: bytes == golden 420 (independent python oracle)'
# envelope re-emitted unchanged (re-parses to the same status+q)
$echo = $r.stdout | ConvertFrom-Json
Assert ($echo.status -eq 'ok' -and $echo.result.q -eq 'card:module:40') 'card: envelope re-emitted unchanged'

# --- section: (proves passthrough+charge independent of the FO-6 fix) --------------------------
$led = New-Ledger
$r = Invoke-Retrieve 'section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header' $led (Join-Path $FIX 'section-ok.json')
Assert ($r.code -eq 0) 'section: exit 0'
$obj = Get-LastLedgerObj $led
Assert ($obj.kind -eq 'section') 'section: kind == section'
Assert ($obj.target -eq 'section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header') 'section: target exact'
$expected = Recompute-Bytes (Join-Path $FIX 'section-ok.json')
Assert ($obj.bytes -eq $expected) "section: bytes == recomputed ($($obj.bytes) == $expected)"
Assert ($obj.bytes -eq 491) 'section: bytes == golden 491'

# --- entity: (non-section/card prefix -> kind query) -------------------------------------------
$led = New-Ledger
$r = Invoke-Retrieve 'entity:module:36/artifact.search' $led (Join-Path $FIX 'entity-ok.json')
Assert ($r.code -eq 0) 'entity: exit 0'
$obj = Get-LastLedgerObj $led
Assert ($obj.kind -eq 'query') 'entity: kind == query (default)'
Assert ($obj.bytes -eq 338) 'entity: bytes == golden 338'

# --- byte-oracle regression: U+0085/U+2028/U+2029 text (pwsh ConvertTo-Json would OVERCOUNT these;
#     the python oracle must match exactly -- closes i60 red-team RT-B F1) -----------------------
$led = New-Ledger
$r = Invoke-Retrieve 'section:doc:core-docs/X.md#Edge' $led (Join-Path $FIX 'section-unicode-ok.json')
Assert ($r.code -eq 0) 'unicode: exit 0'
$obj = Get-LastLedgerObj $led
$expected = Recompute-Bytes (Join-Path $FIX 'section-unicode-ok.json')
Assert ($obj.bytes -eq $expected) "unicode: bytes == python oracle ($($obj.bytes) == $expected)"
Assert ($obj.bytes -eq 189) 'unicode: bytes == golden 189 (U+0085/2028/2029 not over-escaped)'

# --- FAIL-CLOSED: a non-ok envelope appends NOTHING + exits non-zero ---------------------------
$led = New-Ledger
'PRE' | Out-Null
Set-Content -LiteralPath $led -Value '{"kind":"card","target":"pre","bytes":10}' -NoNewline
$before = (Get-Content -Raw -LiteralPath $led)
$r = Invoke-Retrieve 'section:doc:core-docs/AUDIT_PIPELINE.md#Cadence header' $led (Join-Path $FIX 'section-error.json')
Assert ($r.code -ne 0) 'non-ok: exit non-zero (fail-closed)'
$after = (Get-Content -Raw -LiteralPath $led)
Assert ($before -eq $after) 'non-ok: ledger UNCHANGED (nothing appended)'
$echo = $r.stdout | ConvertFrom-Json
Assert ($echo.status -eq 'error') 'non-ok: error envelope still re-emitted'

# --- missing envelope file -> usage error exit 2 -----------------------------------------------
$led = New-Ledger
$r = Invoke-Retrieve 'card:module:40' $led (Join-Path $FIX 'does-not-exist.json')
Assert ($r.code -eq 2) 'missing envelope file: exit 2'
Assert (-not (Test-Path -LiteralPath $led)) 'missing envelope file: no ledger created'

# --- malformed (non-JSON) envelope -> fail-closed ----------------------------------------------
$led = New-Ledger
$badEnv = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.json')
Set-Content -LiteralPath $badEnv -Value '{ not valid json' -NoNewline
$r = Invoke-Retrieve 'card:module:40' $led $badEnv
Assert ($r.code -ne 0) 'malformed envelope: exit non-zero'
Assert (-not (Test-Path -LiteralPath $led)) 'malformed envelope: nothing appended'

# --- fail-closed on degenerate top-level envelopes (null / scalar / empty) -> clean exit, no append
#     (closes i60 red-team RT-B F4: these must not crash with an uncaught StrictMode error) -------
foreach ($bad in @('null', '42', '', '   ', '["a","b"]')) {
  $led = New-Ledger
  $badEnv = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.json')
  Set-Content -LiteralPath $badEnv -Value $bad -NoNewline
  $r = Invoke-Retrieve 'card:module:40' $led $badEnv
  Assert ($r.code -ne 0) "degenerate envelope '$bad': exit non-zero"
  Assert (-not (Test-Path -LiteralPath $led)) "degenerate envelope '$bad': nothing appended"
}

# --- case-SENSITIVE status: 'OK' (wrong case) must fail closed (closes RT-B F5) -----------------
$led = New-Ledger
$upEnv = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.json')
Set-Content -LiteralPath $upEnv -Value '{"schema":"lifeorch.skill.result/0.1","status":"OK","result":{"q":"card:module:40","card":{}}}' -NoNewline
$r = Invoke-Retrieve 'card:module:40' $led $upEnv
Assert ($r.code -eq 4) "uppercase status 'OK': exit 4 (fail-closed)"
Assert (-not (Test-Path -LiteralPath $led)) "uppercase status 'OK': nothing appended"

# --- ledger created if absent + append-only + double-run determinism ---------------------------
$led = New-Ledger
Assert (-not (Test-Path -LiteralPath $led)) 'determinism: ledger absent to start'
$null = Invoke-Retrieve 'card:module:40' $led (Join-Path $FIX 'card-ok.json')
$line1 = @(Get-Content -LiteralPath $led | Where-Object { $_.Trim() -ne '' })[-1]
$null = Invoke-Retrieve 'card:module:40' $led (Join-Path $FIX 'card-ok.json')
$lines = @(Get-Content -LiteralPath $led | Where-Object { $_.Trim() -ne '' })
Assert ($lines.Count -eq 2) 'append-only: two runs -> two lines'
Assert ($lines[0] -eq $lines[1]) 'determinism: two runs byte-identical ledger lines'

# --- ledger line is a valid entry the monitor accepts (keys subset {kind,target,bytes,note}) ---
$obj = $line1 | ConvertFrom-Json
$keys = @($obj.PSObject.Properties.Name | Sort-Object)
Assert (($keys -join ',') -eq 'bytes,kind,target') 'ledger line has exactly {bytes,kind,target}'

Write-Host ""
Write-Host ("retrieve.ps1: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
