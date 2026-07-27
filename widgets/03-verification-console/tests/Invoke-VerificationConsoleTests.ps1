<#
    Invoke-VerificationConsoleTests.ps1 - dual-mode test harness for the Verification Console (Widget 03).

    Cloud pre-ship gate (Linux, no -Live): AST-parse every script; drive the REAL core
    (VerificationConsole.psm1) - packet import + validation (the shipped fixture + inline malformed/invalid
    cases), item rendering, a run_module run against tests/mock-invoke-skill.ps1 across a scenario matrix,
    and result assembly + save/re-read. The WinForms + real-Module tests are Windows-only and skipped.

    Live (Windows, via the executor, -Live): the same tests plus the WinForms form builds
    (Show-VerificationConsole.ps1 -SelfTest in an STA child), launch.bat shape, and a REAL fs.observer run
    driven end-to-end through the real Module 1 wrapper from a packet item, with no orphaned llama-server.
#>
[CmdletBinding()]
param(
    [switch]$Live,
    [string]$PwshPath,
    [string]$InvokeSkillPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$widgetRoot = Split-Path $here -Parent
Import-Module (Join-Path $widgetRoot 'VerificationConsole.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}
$mockPath = Join-Path $here 'mock-invoke-skill.ps1'
$fixturePacket = Join-Path $here (Join-Path 'fixtures' 'packet.json')

$script:pass = 0; $script:fail = 0; $script:skip = 0
function Ok([string]$name, $cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name   $detail" }
}
function Skip([string]$name, [string]$why) { $script:skip++; Write-Host "  [SKIP] $name ($why)" }

Write-Host "=== Verification Console tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist
foreach ($fn in 'Resolve-VerificationPaths', 'Import-VerificationPacket', 'ConvertTo-NormalizedChecklist',
    'Format-PacketSummary', 'Format-ItemListLine', 'Format-ItemDetail', 'Resolve-ItemSkillDir',
    'Start-SkillProcess', 'Stop-SkillProcess', 'Complete-SkillRun', 'Invoke-SkillRun', 'Format-SkillResult',
    'New-RunSummary', 'New-VerificationResultItem', 'Get-VerificationSummary', 'New-VerificationResult', 'Save-VerificationResult') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'VerificationConsole.psm1'),
    (Join-Path $widgetRoot 'Show-VerificationConsole.ps1'),
    $mockPath,
    (Join-Path $here 'Invoke-VerificationConsoleTests.ps1')
)
foreach ($f in $toParse) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Ok "AST parse: $(Split-Path $f -Leaf)" ($errs.Count -eq 0) ("errors=" + ($errs -join '; '))
}

# 3. path resolution
$paths = Resolve-VerificationPaths
Ok "resolve: Invoke-Skill.ps1 path" ($paths.InvokeSkillPath -like '*01-skill-bootstrap*Invoke-Skill.ps1')
Ok "resolve: repo root exists" (Test-Path $paths.RepoRoot)

# 4. import the shipped fixture packet
Ok "fixture packet exists" (Test-Path $fixturePacket)
$pk = Import-VerificationPacket -Path $fixturePacket
Ok "packet: ok" ([bool]$pk.ok) ([string]$pk.error)
Ok "packet: 3 items" ($pk.item_count -eq 3) ("count=$($pk.item_count)")
Ok "packet: schema matches" ($pk.schema -eq 'lifeorch.verification.packet/0.1')
Ok "packet: packet_id vp-fixture-001" ($pk.packet_id -eq 'vp-fixture-001')
$fs = @($pk.items) | Where-Object { $_.id -eq 'fsobs-1' } | Select-Object -First 1
$hu = @($pk.items) | Where-Object { $_.id -eq 'human-1' } | Select-Object -First 1
$dc = @($pk.items) | Where-Object { $_.id -eq 'docio-1' } | Select-Object -First 1
Ok "packet: fsobs-1 is run_module + valid" ($null -ne $fs -and $fs.kind -eq 'run_module' -and $fs.valid)
Ok "packet: fsobs-1 skill_dir relative preserved" ($null -ne $fs -and $fs.skill_dir -eq 'modules/02-fs-observer')
Ok "packet: fsobs-1 object inputs_json -> compact string" ($null -ne $fs -and ($fs.inputs_json -is [string]) -and $fs.inputs_json -match '"path"')
Ok "packet: docio-1 string inputs_json preserved" ($null -ne $dc -and $dc.inputs_json -match '"op":"read"')
Ok "packet: fsobs-1 checklist normalized to 3 {id,text}" ($null -ne $fs -and @($fs.checklist).Count -eq 3 -and ($fs.checklist[2].text -match 'core-docs'))
Ok "packet: human-1 is human_action + valid + action_text" ($null -ne $hu -and $hu.kind -eq 'human_action' -and $hu.valid -and [bool]$hu.action_text)

# 5. malformed / invalid packets
$bad = Import-VerificationPacket -Json '{ not valid json '
Ok "packet malformed json: ok false" (-not [bool]$bad.ok)
$invItemsJson = '{"schema":"lifeorch.verification.packet/0.1","packet_id":"vp-x","title":"t","items":[' +
    '{"id":"a","kind":"run_module","title":"no skill_dir"},' +
    '{"id":"b","kind":"frobnicate","title":"bad kind","skill_dir":"modules/02-fs-observer"}]}'
$inv = Import-VerificationPacket -Json $invItemsJson
Ok "packet invalid items: loads (has items)" ([bool]$inv.ok -and $inv.item_count -eq 2)
$ia = @($inv.items) | Where-Object { $_.id -eq 'a' } | Select-Object -First 1
$ib = @($inv.items) | Where-Object { $_.id -eq 'b' } | Select-Object -First 1
Ok "packet invalid item a: run_module missing skill_dir -> valid=false" ($null -ne $ia -and -not $ia.valid -and $ia.error -match 'skill_dir')
Ok "packet invalid item b: unknown kind -> valid=false" ($null -ne $ib -and -not $ib.valid -and $ib.error -match 'kind')

# 6. checklist normalization directly
$nl = ConvertTo-NormalizedChecklist @('first', ([pscustomobject]@{ id = 'x'; text = 'second' }))
Ok "checklist: string -> {id,text}" (@($nl).Count -eq 2 -and $nl[0].text -eq 'first' -and $nl[0].id -eq 'c1' -and $nl[1].id -eq 'x')

# 7. rendering
Ok "packet summary contains title" ((Format-PacketSummary -Packet $pk) -match 'Fixture')
Ok "list line: run item tagged [run]" ((Format-ItemListLine -Item $fs) -match '\[run\]')
Ok "list line: human item tagged [human]" ((Format-ItemListLine -Item $hu) -match '\[human\]')
$fdet = Format-ItemDetail -Item $fs
foreach ($needle in 'MODULE', 'INPUTS', 'EXPECTED', 'CHECKLIST') { Ok "run detail contains '$needle'" ($fdet -match $needle) }
Ok "human detail contains ACTION" ((Format-ItemDetail -Item $hu) -match 'ACTION')

# 8. skill_dir resolution
Ok "resolve skill_dir: relative joins repo root" ((Resolve-ItemSkillDir -Item $fs -RepoRoot 'C:\repo') -match 'modules[\\/]02-fs-observer')
$absItem = [pscustomobject]@{ skill_dir = (Join-Path ([System.IO.Path]::GetTempPath()) 'abs-x') }
Ok "resolve skill_dir: absolute passes through" ((Resolve-ItemSkillDir -Item $absItem -RepoRoot 'C:\repo') -eq $absItem.skill_dir)

# ----- run a run_module item via the mock (temp fixture module dir) -----
$fixRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vc-fixture-" + [guid]::NewGuid().ToString('N'))
$modDir = Join-Path $fixRoot '02-fs-observer'
New-Item -ItemType Directory -Path $modDir -Force | Out-Null
([ordered]@{ schema = 'lifeorch.skill.manifest/0.1'; skill_id = 'fs.observer'; name = 'Filesystem Observer'; version = '0.1.0'; contract_version = '0.2'; invocation = [ordered]@{ method = 'pwsh-file'; entrypoint = 'Invoke-FsObserver.ps1' } } | ConvertTo-Json -Depth 6) |
    Set-Content -LiteralPath (Join-Path $modDir 'skill.json') -Encoding utf8
try {
    # 9. clean ok run
    $run = Invoke-SkillRun -SkillDir $modDir -InputsJson '{"path":".","depth":1}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run ok: ok=true" ($run.ok) ("status=$($run.skill_status) parse=$($run.parse_error)")
    Ok "run ok: skill_id fs.observer" ($run.skill_id -eq 'fs.observer')
    Ok "run ok: manifest_valid + invoked + envelope_valid" ($run.manifest_valid -and $run.invoked -and $run.envelope_valid)
    $rt = Format-SkillResult -Run $run
    foreach ($needle in 'MODULE:', 'WRAPPER:', 'RESULT:', 'ARTIFACTS') { Ok "result transcript contains '$needle'" ($rt -match [regex]::Escape($needle)) }

    # 10. error scenarios via the mock
    $errRun = Invoke-SkillRun -SkillDir $modDir -InputsJson '{"path":"ERRORME"}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run error: not ok + surfaces code" (-not $errRun.ok -and $errRun.skill_status -eq 'error' -and $errRun.error.code -eq 'input_not_found')
    $badEnv = Invoke-SkillRun -SkillDir $modDir -InputsJson '{"path":"BADENV"}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run badenv: invoked true, envelope_valid false" ($badEnv.invoked -and -not $badEnv.envelope_valid -and $badEnv.error.code -eq 'envelope_invalid')
    $noisy = Invoke-SkillRun -SkillDir $modDir -InputsJson '{"path":"NOISY"}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run noisy: still parsed + ok" ($noisy.ok -and $null -ne $noisy.report)

    # 11. run summary is compact + JSON-safe
    $rs = New-RunSummary -Run $run
    Ok "run summary: ok + skill_id + artifacts" ($rs.ok -and $rs.skill_id -eq 'fs.observer' -and @($rs.artifacts).Count -ge 1)
    $rsJson = $rs | ConvertTo-Json -Depth 8
    Ok "run summary: serializes to JSON" ([bool]$rsJson -and $rsJson -match 'fs.observer')

    # 12. assemble + save + re-read a verification result
    $ri1 = New-VerificationResultItem -Item $fs -Run $run -Checks $fs.checklist -Overall 'pass' -Notes 'looks right'
    $ri2 = New-VerificationResultItem -Item $dc -Run $null -Checks $dc.checklist -Overall 'fail' -Notes 'content wrong'
    $ri3 = New-VerificationResultItem -Item $hu -Run $null -Checks $hu.checklist -Overall 'partial' -Notes ''
    Ok "result item: run item ran=true + run_summary" ($ri1.ran -and $null -ne $ri1.run_summary)
    Ok "result item: human item ran=false" (-not $ri3.ran)
    $result = New-VerificationResult -Packet $pk -Items @($ri1, $ri2, $ri3) -VerifiedBy 'nicholas'
    Ok "result: schema" ($result.schema -eq 'lifeorch.verification.result/0.1')
    Ok "result: summary counts" ($result.summary.total -eq 3 -and $result.summary.pass -eq 1 -and $result.summary.fail -eq 1 -and $result.summary.partial -eq 1)
    $outPath = Join-Path $fixRoot 'result.json'
    [void](Save-VerificationResult -Result $result -Path $outPath)
    Ok "result: saved to disk" (Test-Path $outPath)
    $reread = (Get-Content -LiteralPath $outPath -Raw) | ConvertFrom-Json
    Ok "result: re-reads as valid JSON" ($reread.schema -eq 'lifeorch.verification.result/0.1' -and @($reread.items).Count -eq 3)
    Ok "result: packet_id carried" ($reread.packet_id -eq 'vp-fixture-001')
    Ok "result: verified_by carried" ($reread.verified_by -eq 'nicholas')
    Ok "result: first item checks include verdict" (@($reread.items[0].checks).Count -ge 1 -and [bool]$reread.items[0].checks[0].verdict)
}
finally {
    Remove-Item -LiteralPath $fixRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# 13. launch.bat shape
$launch = Join-Path $widgetRoot 'launch.bat'
$lc = if (Test-Path $launch) { Get-Content $launch -Raw } else { '' }
Ok "launch.bat exists" (Test-Path $launch)
Ok "launch.bat uses -STA" ($lc -match '-STA')
Ok "launch.bat runs Show-VerificationConsole.ps1" ($lc -match 'Show-VerificationConsole\.ps1')

# ----- live / Windows-only -----
if ($Live -and $IsWindows) {
    $sta = & $PwshPath -NoProfile -STA -File (Join-Path $widgetRoot 'Show-VerificationConsole.ps1') -SelfTest 2>&1
    Ok "WinForms form builds (SelfTest)" (($sta -join "`n") -match 'SELFTEST_FORM_OK') (($sta -join ' | '))

    # REAL fs.observer run through the real Module 1 wrapper, driven from a packet item.
    $realWrap = if ($InvokeSkillPath) { $InvokeSkillPath } else { $paths.InvokeSkillPath }
    $realFsItem = @($pk.items) | Where-Object { $_.id -eq 'fsobs-1' } | Select-Object -First 1
    $realDir = Resolve-ItemSkillDir -Item $realFsItem -RepoRoot $paths.RepoRoot
    Ok "real: fsobs-1 skill dir resolves on disk" (Test-Path $realDir) ("dir=$realDir")
    $before = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
    $real = Invoke-SkillRun -SkillDir $realDir -InputsJson $realFsItem.inputs_json -InvokeSkillPath $realWrap -PwshPath $PwshPath -WorkingDir $paths.RepoRoot
    Ok "real fs.observer: invoked + envelope_valid" ($real.invoked -and $real.envelope_valid) ("status=$($real.skill_status) wrap_exit=$($real.wrapper_exit) parse=$($real.parse_error)")
    Ok "real fs.observer: skill_id fs.observer" ($real.skill_id -eq 'fs.observer')
    Ok "real fs.observer: ok" ($real.ok) ("status=$($real.skill_status)")
    $rsum = New-RunSummary -Run $real
    Ok "real fs.observer: run summary has artifacts" (@($rsum.artifacts).Count -ge 1)
    Start-Sleep -Seconds 2
    $after = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
    Ok "real run: no orphaned llama-server" ($after -le $before) ("before=$before after=$after")
}
else {
    Skip "WinForms form self-test" "requires -Live on Windows"
    Skip "real fs.observer run" "requires -Live on Windows"
    Skip "no-orphan check" "requires -Live on Windows"
}

Write-Host ""
Write-Host "=== RESULT: $script:pass passed, $script:fail failed, $script:skip skipped ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
