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
    'New-RunSummary', 'New-VerificationResultItem', 'Get-VerificationSummary', 'New-VerificationResult', 'Save-VerificationResult',
    'Get-NamedProcessMap', 'Get-NamedProcessIdSet', 'Get-ProcessCommandLine', 'Test-OrphanInScope',
    'Stop-ProcessHard', 'Invoke-OrphanSweep', 'Invoke-RunOrphanSweep') {
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

# 5b. REAL orchestrate.fanout packet shape (dogfood regression, H-verif-console): the first live audit-loop
#     exercise ran the ACTUAL fo-1 packet, not just the hand-authored fixture. Pin that shape so a future
#     orchestrator/Console drift (object inputs_json, expected text, a human_action item, the packet_id
#     pattern) is caught in the cloud gate -- import + normalize + render only (no module run, so stable).
$realPacket = Join-Path $here (Join-Path 'fixtures' 'real-packet-fo-1.json')
Ok "real packet: fixture exists" (Test-Path $realPacket)
$rp = Import-VerificationPacket -Path $realPacket
Ok "real packet: ok + 3 items" ([bool]$rp.ok -and $rp.item_count -eq 3) ("ok=$($rp.ok) count=$($rp.item_count) err=$($rp.error)")
Ok "real packet: packet_id + schema" ($rp.packet_id -eq 'vp-fo-1-20ed8a0b-i1' -and $rp.schema -eq 'lifeorch.verification.packet/0.1')
$rA = @($rp.items) | Where-Object { $_.id -eq 'A-gpu-lease' } | Select-Object -First 1
$rB = @($rp.items) | Where-Object { $_.id -eq 'B-git-lease' } | Select-Object -First 1
$rC = @($rp.items) | Where-Object { $_.id -eq 'C-frontier-bridge' } | Select-Object -First 1
Ok "real packet: A run_module + object inputs_json -> compact string" ($null -ne $rA -and $rA.kind -eq 'run_module' -and $rA.valid -and ($rA.inputs_json -is [string]) -and $rA.inputs_json -match '"tier"')
Ok "real packet: B human_action + action_text" ($null -ne $rB -and $rB.kind -eq 'human_action' -and $rB.valid -and [bool]$rB.action_text)
Ok "real packet: C run_module + object inputs_json normalized" ($null -ne $rC -and $rC.kind -eq 'run_module' -and $rC.valid -and ($rC.inputs_json -is [string]) -and $rC.inputs_json -match '"files"')
Ok "real packet: every item carries expected text" (@($rp.items | Where-Object { [bool]$_.expected }).Count -eq 3)
# rendering the real shape must not throw and must show the essentials
$rSum = Format-PacketSummary -Packet $rp
Ok "real packet: summary renders title" ($rSum -match 'fo-1')
$rADet = Format-ItemDetail -Item $rA
Ok "real packet: A detail shows MODULE + INPUTS + EXPECTED" ($rADet -match 'MODULE' -and $rADet -match 'INPUTS' -and $rADet -match 'EXPECTED')
Ok "real packet: B detail shows ACTION" ((Format-ItemDetail -Item $rB) -match 'ACTION')
# assemble + re-read a result from the real packet (mixed verdicts, one skipped GPU item)
$rrItems = @(
    (New-VerificationResultItem -Item $rA -Run $null -Checks $rA.checklist -Overall 'skipped' -Notes 'GPU item deferred'),
    (New-VerificationResultItem -Item $rB -Run $null -Checks $rB.checklist -Overall 'pass' -Notes ''),
    (New-VerificationResultItem -Item $rC -Run $null -Checks $rC.checklist -Overall 'partial' -Notes 'packet input stale')
)
$rrResult = New-VerificationResult -Packet $rp -Items $rrItems -VerifiedBy 'gate'
Ok "real packet: result summary counts (1 pass/1 partial/1 skipped)" ($rrResult.summary.total -eq 3 -and $rrResult.summary.pass -eq 1 -and $rrResult.summary.partial -eq 1 -and $rrResult.summary.skipped -eq 1)

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

# 8b. run-teardown orphan sweep (deterministic; no real llama-server needed) -----------------------------
#    Proves the safety contract of the name-based sweep WITHOUT a GPU: (a) empty names -> no-op; (b) the
#    scope guard (llama-server always ours; any other name needs a command-line marker); (c) a PID alive
#    BEFORE the run (this test's own pwsh) is NEVER a candidate; (d) a NEW, in-scope process IS reaped and
#    confirmed dead, while the pre-existing one is untouched. (d) launches a disposable child tagged with a
#    unique marker and scopes the sweep to that marker, so ONLY that child can ever match.
function PidAlive([int]$procId) { if ($procId -le 0) { return $false } try { $null = Get-Process -Id $procId -ErrorAction Stop; return $true } catch { return $false } }

$noop = Invoke-OrphanSweep -BeforeSet @{} -Names @() -SettleMs 0
Ok "sweep: empty names -> ran=false + all_clear" ((-not [bool]$noop.ran) -and [bool]$noop.all_clear)
Ok "sweep scope: llama-server always in scope" (Test-OrphanInScope -ProcId 999999 -Name 'llama-server' -ScopeMarkers @())
Ok "sweep scope: other name w/o markers refused" (-not (Test-OrphanInScope -ProcId 999999 -Name 'python' -ScopeMarkers @()))
Ok "sweep scope: other name w/ non-matching marker refused" (-not (Test-OrphanInScope -ProcId $PID -Name 'python' -ScopeMarkers @('no-such-marker-xyz')))

$selfSet = Get-NamedProcessIdSet -Names @('pwsh', 'pwsh-preview')
Ok "sweep snapshot: captures this pwsh pid" ($selfSet.ContainsKey($PID))
$sweepSelf = Invoke-OrphanSweep -BeforeSet $selfSet -Names @('pwsh', 'pwsh-preview') -ScopeMarkers @($widgetRoot) -SettleMs 0
Ok "sweep: pre-existing pwsh (self) is not a candidate + not reaped" ((@($sweepSelf.candidate_pids) -notcontains $PID) -and (@($sweepSelf.reaped_pids) -notcontains $PID) -and (PidAlive $PID))

$mk = 'orphansweep_' + [guid]::NewGuid().ToString('N')
$before = Get-NamedProcessIdSet -Names @('pwsh', 'pwsh-preview')
$child = Start-Process -FilePath $PwshPath -ArgumentList @('-NoProfile', '-Command', "Start-Sleep -Seconds 45; '$mk' | Out-Null") -PassThru
Start-Sleep -Milliseconds 800
Ok "sweep: disposable child launched" (PidAlive $child.Id)
$sweep = Invoke-OrphanSweep -BeforeSet $before -Names @('pwsh', 'pwsh-preview') -ScopeMarkers @($mk) -SettleMs 200
Ok "sweep: NEW in-scope child reaped + all_clear" ((@($sweep.reaped_pids) -contains $child.Id) -and [bool]$sweep.all_clear) ("reaped=[$($sweep.reaped_pids -join ',')] cands=[$($sweep.candidate_pids -join ',')]")
Ok "sweep: reaped child confirmed dead" (-not (PidAlive $child.Id))
Ok "sweep: pre-existing self pwsh still alive (never touched)" (PidAlive $PID)
if (PidAlive $child.Id) { try { Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue } catch { } }

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

    # --- REAL model.gateway (tier tiny, WARM) through the Console run path: Governor Phase 2 spawns the
    #     server DETACHED (Win32_Process.Create) so it ESCAPES the child-tree kill; the run-teardown orphan
    #     sweep must reap it -> 0 orphaned llama-server after teardown. This is the GPU worker's core check.
    #     The gpu lease is held by THIS holder; model.gateway (via LIFEORCH_INSTANCE) re-attaches it
    #     (already_held -> owned=false), so it never releases the lease out from under us. ---
    $mgDir = Join-Path $paths.RepoRoot (Join-Path 'modules' '07-model-gateway')
    $reslease = Join-Path $paths.RepoRoot (Join-Path 'modules' (Join-Path '29-resource-lease' 'Invoke-ResLease.ps1'))
    $mgReg = Join-Path $mgDir 'models.json'
    $engineOk = $false; $modelOk = $false; $tinyId = ''
    if ((Test-Path $mgDir) -and (Test-Path $mgReg) -and (Test-Path $reslease)) {
        try {
            $regObj = Get-Content -LiteralPath $mgReg -Raw | ConvertFrom-Json
            $eng = [string]$regObj.engines.'llama-server'
            $tinyId = [string]$regObj.tiers.llm.tiny
            $tinyModel = @($regObj.models | Where-Object { $_.model_id -eq $tinyId }) | Select-Object -First 1
            $engineOk = ($eng -and (Test-Path -LiteralPath $eng))
            $modelOk = ($null -ne $tinyModel -and (Test-Path -LiteralPath ([string]$tinyModel.path)))
        }
        catch { }
    }
    if ($engineOk -and $modelOk) {
        $holder = if (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_INSTANCE)) { $env:LIFEORCH_INSTANCE } else { 'vc-live-teardown' }
        $prevInstance = $env:LIFEORCH_INSTANCE
        $env:LIFEORCH_INSTANCE = $holder
        $mgBefore = @(); $mgAfter = @(); $leaseId = $null; $acqOwned = $false
        try {
            $acqRaw = & $PwshPath -NoProfile -File $reslease -Action acquire -Resource 'gpu' -Holder $holder -TtlSeconds 1800 -WaitSeconds 900 2>$null | Out-String
            $acq = $null; try { $acq = $acqRaw | ConvertFrom-Json } catch { }
            $acqResult = if ($null -ne $acq) { Get-Prop $acq 'result' $acq } else { $null }
            $gotLease = ($null -ne $acqResult -and [bool](Get-Prop $acqResult 'acquired' $false))
            if ($gotLease) { $leaseId = [string](Get-Prop $acqResult 'lease_id'); $acqOwned = (-not [bool](Get-Prop $acqResult 'already_held' $false)) }
            Ok "live orphan: gpu lease acquired (holder=$holder)" $gotLease ("acq=" + $acqRaw.Trim())

            $mgInputs = '{"tier":"tiny","prompt":"ping","max_tokens":8,"temperature":0.1,"warm":true}'
            $mgResolved = Resolve-ItemSkillDir -Item ([pscustomobject]@{ skill_dir = 'modules/07-model-gateway' }) -RepoRoot $paths.RepoRoot
            $mgBefore = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })
            $mgRun = Invoke-SkillRun -SkillDir $mgResolved -InputsJson $mgInputs -InvokeSkillPath $realWrap -PwshPath $PwshPath -WorkingDir $paths.RepoRoot
            Ok "live orphan: model.gateway tiny ran ok (tier=$tinyId)" ([bool]$mgRun.ok) ("status=$($mgRun.skill_status) wrap_exit=$($mgRun.wrapper_exit) err=" + [string](Get-Prop $mgRun.error 'message'))
            $sweep = Get-Prop $mgRun 'orphan_sweep'
            Ok "live orphan: teardown sweep reaped the detached warm llama-server" ($null -ne $sweep -and [bool]$sweep.ran -and @($sweep.reaped_pids).Count -ge 1 -and [bool]$sweep.all_clear) ("sweep=" + (ConvertTo-CompactJson $sweep))
            Start-Sleep -Seconds 2
            $mgAfter = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })
            $newRemaining = @($mgAfter | Where-Object { $mgBefore -notcontains $_ })
            Ok "live orphan: 0 orphaned llama-server after teardown" (@($newRemaining).Count -eq 0) ("before=[$($mgBefore -join ',')] after=[$($mgAfter -join ',')] new_remaining=[$($newRemaining -join ',')]")
        }
        finally {
            # belt-and-suspenders: reap anything NEW we somehow left, tidy a now-dead warm registry, release + restore
            try { foreach ($rid in @($mgAfter | Where-Object { $mgBefore -notcontains $_ })) { Stop-Process -Id $rid -Force -ErrorAction SilentlyContinue } } catch { }
            $warmReg = Join-Path $mgDir (Join-Path 'runtime' 'warm-server.json')
            try {
                if (Test-Path -LiteralPath $warmReg) {
                    $wr = Get-Content -LiteralPath $warmReg -Raw | ConvertFrom-Json
                    $wrPid = if ($null -ne $wr -and $wr.PSObject.Properties['pid']) { [int]$wr.pid } else { -1 }
                    $wrAlive = $false; if ($wrPid -gt 0) { try { $null = Get-Process -Id $wrPid -ErrorAction Stop; $wrAlive = $true } catch { } }
                    if (-not $wrAlive) { Remove-Item -LiteralPath $warmReg -Force -ErrorAction SilentlyContinue }  # our reaped server; never remove a LIVE resident
                }
            }
            catch { }
            if ($leaseId -and $acqOwned) { & $PwshPath -NoProfile -File $reslease -Action release -Resource 'gpu' -LeaseId $leaseId 2>$null | Out-Null }
            if ($null -eq $prevInstance) { Remove-Item Env:\LIFEORCH_INSTANCE -ErrorAction SilentlyContinue } else { $env:LIFEORCH_INSTANCE = $prevInstance }
        }
    }
    else {
        Skip "live orphan (model.gateway tiny warm)" "engine/model not present (engineOk=$engineOk modelOk=$modelOk tiny=$tinyId)"
    }
}
else {
    Skip "WinForms form self-test" "requires -Live on Windows"
    Skip "real fs.observer run" "requires -Live on Windows"
    Skip "no-orphan check" "requires -Live on Windows"
    Skip "live orphan (model.gateway tiny warm)" "requires -Live on Windows"
}

Write-Host ""
Write-Host "=== RESULT: $script:pass passed, $script:fail failed, $script:skip skipped ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
