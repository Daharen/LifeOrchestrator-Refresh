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
    'Get-PlanIdFromPacket', 'Get-DefaultPacketsDir', 'Get-RecentPackets', 'Format-RecentPacketLine',
    'Get-ReferencedPaths', 'Get-ItemActionModel',
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

# 8c. packet discovery + by-kind action model + rendering (D-0063 UX unit) --------------------------------
# plan-id derivation (emitted packets carry no plan_id field; it is embedded in packet_id vp-<plan>-i<N>)
Ok "planid: from packet_id vp-<plan>-i<N>" ((Get-PlanIdFromPacket -PacketId 'vp-fo-9-d4139304-i9') -eq 'fo-9-d4139304')
Ok "planid: explicit plan_id field wins" ((Get-PlanIdFromPacket -Packet ([pscustomobject]@{ plan_id = 'p-x'; packet_id = 'vp-y-i2' })) -eq 'p-x')
Ok "planid: non-vp id passes through" ((Get-PlanIdFromPacket -PacketId 'custom-123') -eq 'custom-123')
Ok "packetsdir: joins the fan-out artifacts path" ((Get-DefaultPacketsDir -RepoRoot 'C:\repo') -match 'modules[\\/]30-orchestrate-fanout[\\/]runtime[\\/]artifacts')

# Get-RecentPackets against a temp fixture tree: newest-first by mtime; parse plan/title/count; malformed kept.
$rpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vc-recent-" + [guid]::NewGuid().ToString('N'))
try {
    $mkPacket = {
        param($dir, $id, $title, $n, $when, $mtime)
        $d = Join-Path $rpRoot $dir; New-Item -ItemType Directory -Path $d -Force | Out-Null
        $its = @(); for ($k = 1; $k -le $n; $k++) { $its += @{ id = "i$k"; kind = 'run_module'; title = "t$k"; skill_dir = 'modules/02-fs-observer' } }
        $pk2 = [ordered]@{ schema = 'lifeorch.verification.packet/0.1'; packet_id = $id; title = $title; created_by = 'claude'; created_at_utc = $when; report_back = 'on_all'; items = $its }
        $p = Join-Path $d 'verification-packet.json'
        ($pk2 | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $p -Encoding utf8
        (Get-Item -LiteralPath $p).LastWriteTimeUtc = $mtime
    }
    & $mkPacket 'aaaa' 'vp-fo-1-abc-i1' 'Plan one' 2 '2026-07-01T10:00:00Z' ([datetime]::new(2026, 7, 1, 10, 0, 0, [System.DateTimeKind]::Utc))
    & $mkPacket 'bbbb' 'vp-fo-2-def-i2' 'Plan two' 3 '2026-07-05T10:00:00Z' ([datetime]::new(2026, 7, 5, 10, 0, 0, [System.DateTimeKind]::Utc))
    & $mkPacket 'cccc' 'vp-fo-3-ghi-i1' 'Plan three' 1 '2026-07-03T10:00:00Z' ([datetime]::new(2026, 7, 3, 10, 0, 0, [System.DateTimeKind]::Utc))
    $badDir = Join-Path $rpRoot 'dddd'; New-Item -ItemType Directory -Path $badDir -Force | Out-Null
    '{ not valid json ' | Set-Content -LiteralPath (Join-Path $badDir 'verification-packet.json') -Encoding utf8
    (Get-Item -LiteralPath (Join-Path $badDir 'verification-packet.json')).LastWriteTimeUtc = [datetime]::new(2026, 7, 2, 10, 0, 0, [System.DateTimeKind]::Utc)

    $recent = @(Get-RecentPackets -PacketsDir $rpRoot)
    Ok "recent: found all 4 (incl. malformed)" ($recent.Count -eq 4) ("count=$($recent.Count)")
    Ok "recent: newest first by mtime" ($recent[0].plan_id -eq 'fo-2-def' -and $recent[1].plan_id -eq 'fo-3-ghi')
    $bad = @($recent | Where-Object { -not $_.ok })
    Ok "recent: malformed packet kept as ok=false + error" ($bad.Count -eq 1 -and [bool]$bad[0].error)
    $good = @($recent | Where-Object { $_.ok })
    Ok "recent: parses plan_id/title/item_count" ((@($good | Where-Object { $_.plan_id -eq 'fo-1-abc' -and $_.title -eq 'Plan one' -and $_.item_count -eq 2 }).Count) -eq 1)
    Ok "recent: -Max caps the list" ((@(Get-RecentPackets -PacketsDir $rpRoot -Max 2)).Count -eq 2)
    Ok "recent: absent dir -> empty array (no throw)" ((@(Get-RecentPackets -PacketsDir (Join-Path $rpRoot 'nope'))).Count -eq 0)

    Ok "recent line: shows plan + item count" ((Format-RecentPacketLine -Entry $recent[0]) -match 'fo-2-def' -and (Format-RecentPacketLine -Entry $recent[0]) -match '\[3 items\]')
    Ok "recent line: singular '1 item'" ((Format-RecentPacketLine -Entry ($good | Where-Object { $_.item_count -eq 1 } | Select-Object -First 1)) -match '\[1 item\]')
    Ok "recent line: malformed shows [unreadable]" ((Format-RecentPacketLine -Entry $bad[0]) -match '\[unreadable\]')
}
finally { Remove-Item -LiteralPath $rpRoot -Recurse -Force -ErrorAction SilentlyContinue }

# referenced-path extraction from free text (for the Open affordance)
$refs = @(Get-ReferencedPaths -Text 'see modules/07-model-gateway and core-docs/HANDOFF.md plus a.answer.md; not_a_path here')
Ok "refs: extracts repo dir + doc + dotted file" ((@($refs | Where-Object { $_.raw -eq 'modules/07-model-gateway' }).Count -eq 1) -and (@($refs | Where-Object { $_.raw -eq 'core-docs/HANDOFF.md' }).Count -eq 1) -and (@($refs | Where-Object { $_.raw -eq 'a.answer.md' }).Count -eq 1))
Ok "refs: ignores prose words" ((@($refs | Where-Object { $_.raw -eq 'here' }).Count) -eq 0)
Ok "refs: none when text has no paths" ((@(Get-ReferencedPaths -Text 'no paths at all in this sentence')).Count -eq 0)

# action model: run_module valid / human_action / invalid missing skill_dir / unknown kind
$amFs = Get-ItemActionModel -Item $fs -RepoRoot 'C:\repo'
Ok "action model: run_module valid -> can_run + module folder offered" ([bool]$amFs.can_run -and -not [bool]$amFs.invalid -and (@($amFs.open_paths | Where-Object { $_.label -match 'module folder' }).Count -eq 1))
$amHu = Get-ItemActionModel -Item $hu -RepoRoot 'C:\repo'
Ok "action model: human_action -> cannot run + hand-task reason + action_text" ((-not [bool]$amHu.can_run) -and (-not [bool]$amHu.invalid) -and $amHu.reason -match 'hand task' -and [bool]$amHu.action_text)
$amA = Get-ItemActionModel -Item $ia -RepoRoot 'C:\repo'
Ok "action model: invalid missing skill_dir -> cannot run + plain-language fix" ((-not [bool]$amA.can_run) -and [bool]$amA.invalid -and $amA.fix_hint -match 'skill_dir')
$amB = Get-ItemActionModel -Item $ib -RepoRoot 'C:\repo'
Ok "action model: unknown kind -> cannot run + invalid + plain reason" ((-not [bool]$amB.can_run) -and [bool]$amB.invalid -and $amB.reason -match 'unrecognised')

# Format-ItemDetail: the cryptic '[INVALID: ...]' is replaced by a plain-language 'CANNOT RUN' block
$invDetail = Format-ItemDetail -Item $ia -RepoRoot 'C:\repo'
Ok "detail: invalid item shows plain-language CANNOT RUN + what to fix" ($invDetail -match 'CANNOT RUN' -and $invDetail -match 'skill_dir')
Ok "detail: invalid item drops the cryptic [INVALID: tag" (-not ($invDetail -match '\[INVALID:'))
$huDetail = Format-ItemDetail -Item $hu -RepoRoot 'C:\repo'
Ok "detail: human item shows ACTION + REFERENCED (launch.bat)" ($huDetail -match 'ACTION' -and $huDetail -match 'REFERENCED' -and $huDetail -match 'launch\.bat')
$runDetail = Format-ItemDetail -Item $fs -RepoRoot 'C:\repo'
Ok "detail: run item shows OUTPUT LOCATION + MODULE/INPUTS/EXPECTED/CHECKLIST" ($runDetail -match 'OUTPUT LOCATION' -and $runDetail -match 'MODULE' -and $runDetail -match 'INPUTS' -and $runDetail -match 'EXPECTED' -and $runDetail -match 'CHECKLIST')

# Format-PacketSummary surfaces the plan id + report_back prominently in the header
$sumReal = Format-PacketSummary -Packet $rp
Ok "summary: shows derived plan id + report_back" ($sumReal -match 'plan: fo-1-20ed8a0b' -and $sumReal -match 'report_back')

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
    Ok "result transcript surfaces OUTPUT LOCATION (artifact_root)" ($rt -match 'OUTPUT LOCATION')

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

# 12b. per-item verdict state (CORE) -- D-0064 regression --------------------------------------------------
#     The save/restore/currentId cycle used to live ONLY in the shell (Show-VerificationConsole.ps1),
#     untested, and a live GUI reset (checklist + Overall verdict revert on navigate-away-and-back) slipped
#     the 133/133 mock gate. The pure state logic now lives in the core (Initialize-ItemVerdictStore /
#     Save-ItemVerdictState / Get-ItemVerdictState); these tests drive the exact reported cycle -- a control
#     snapshot in, a restore out -- and assert the saved verdicts flow unchanged into the exported result JSON.
foreach ($fn in 'New-ItemVerdictState', 'Initialize-ItemVerdictStore', 'Get-ItemVerdictState', 'Save-ItemVerdictState') {
    Ok "verdict state: function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}
$vpJson = '{"schema":"lifeorch.verification.packet/0.1","packet_id":"vp-verdict-001","title":"Verdict",' +
    '"items":[' +
    '{"id":"A","kind":"human_action","title":"item A","action_text":"do A","checklist":["a1","a2","a3"]},' +
    '{"id":"B","kind":"human_action","title":"item B","action_text":"do B","checklist":["b1","b2"]}]}'
$vpk = Import-VerificationPacket -Json $vpJson
$store = Initialize-ItemVerdictStore -Items $vpk.items
Ok "verdict state: store seeded for every item" ($store.Contains('A') -and $store.Contains('B'))
$seedA = Get-ItemVerdictState -Store $store -ItemId 'A'
Ok "verdict state: seed defaults (skipped, 3 unchecked rows, no notes)" ([string]$seedA.overall -eq 'skipped' -and @($seedA.checks).Count -eq 3 -and (@($seedA.checks | Where-Object { $_.verdict -ne 'unchecked' }).Count -eq 0) -and [string]$seedA.notes -eq '')
Ok "verdict state: missing id -> default state (never null)" ($null -ne (Get-ItemVerdictState -Store $store -ItemId 'NOPE') -and [string](Get-ItemVerdictState -Store $store -ItemId 'NOPE').overall -eq 'skipped')

# the exact reported cycle: SAVE A (row1 = pass, Overall = pass, a note) -> SAVE B (defaults) -> re-read A
[void](Save-ItemVerdictState -Store $store -ItemId 'A' -Checked @($true, $false, $false) -Overall 'pass' -Notes 'A verified locally' -CheckTexts @('a1', 'a2', 'a3'))
[void](Save-ItemVerdictState -Store $store -ItemId 'B' -Checked @($false, $false) -Overall 'skipped' -Notes '' -CheckTexts @('b1', 'b2'))
$reA = Get-ItemVerdictState -Store $store -ItemId 'A'
Ok "verdict state: A Overall restored == pass (survives saving B)" ([string]$reA.overall -eq 'pass')
Ok "verdict state: A checklist restored (row1=pass, rest unchecked)" (@($reA.checks).Count -eq 3 -and [string]@($reA.checks)[0].verdict -eq 'pass' -and [string]@($reA.checks)[1].verdict -eq 'unchecked' -and [string]@($reA.checks)[2].verdict -eq 'unchecked')
Ok "verdict state: A notes restored" ([string]$reA.notes -eq 'A verified locally')
Ok "verdict state: A row id/text preserved through save" ([string]@($reA.checks)[0].id -eq 'c1' -and [string]@($reA.checks)[0].text -eq 'a1')
Ok "verdict state: B stays default after A saved (no cross-item bleed)" ([string](Get-ItemVerdictState -Store $store -ItemId 'B').overall -eq 'skipped')
# re-save A with the SAME snapshot (what the shell does on every navigation) -> stable, no drift
[void](Save-ItemVerdictState -Store $store -ItemId 'A' -Checked @($true, $false, $false) -Overall 'pass' -Notes 'A verified locally' -CheckTexts @('a1', 'a2', 'a3'))
$reA2 = Get-ItemVerdictState -Store $store -ItemId 'A'
Ok "verdict state: A stable across a second save/restore (no drift)" ([string]$reA2.overall -eq 'pass' -and [string]@($reA2.checks)[0].verdict -eq 'pass' -and [string]$reA2.notes -eq 'A verified locally')
# transitional EMPTY snapshot must NOT wipe a saved item's checks (data-loss guard)
[void](Save-ItemVerdictState -Store $store -ItemId 'A' -Checked @() -Overall 'pass' -Notes 'A verified locally' -CheckTexts @())
$reA3 = Get-ItemVerdictState -Store $store -ItemId 'A'
Ok "verdict state: empty control snapshot preserves prior checks (no clobber)" (@($reA3.checks).Count -eq 3 -and [string]@($reA3.checks)[0].verdict -eq 'pass')

# EXPORT-CONTAINS-VERDICTS: the saved verdicts flow unchanged into New-VerificationResult + the saved JSON
$expItems = New-Object System.Collections.Generic.List[object]
foreach ($vit in @($vpk.items)) {
    $vst = Get-ItemVerdictState -Store $store -ItemId ([string]$vit.id)
    $expItems.Add((New-VerificationResultItem -Item $vit -Run $vst.run -Checks $vst.checks -Overall $vst.overall -Notes $vst.notes))
}
$vres = New-VerificationResult -Packet $vpk -Items $expItems.ToArray() -VerifiedBy 'gate'
$vjsonPath = Join-Path ([System.IO.Path]::GetTempPath()) ("vc-verdict-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    [void](Save-VerificationResult -Result $vres -Path $vjsonPath)
    $vread = (Get-Content -LiteralPath $vjsonPath -Raw) | ConvertFrom-Json
    $vitemA = @($vread.items) | Where-Object { $_.id -eq 'A' } | Select-Object -First 1
    Ok "export verdicts: A overall = pass in exported JSON" ($null -ne $vitemA -and [string]$vitemA.overall -eq 'pass')
    Ok "export verdicts: A ticked check verdict = pass in exported JSON" ($null -ne $vitemA -and [string]@($vitemA.checks)[0].verdict -eq 'pass')
    Ok "export verdicts: A notes carried into exported JSON" ($null -ne $vitemA -and [string]$vitemA.notes -eq 'A verified locally')
    Ok "export verdicts: summary counts A as the 1 pass (1 pass / 1 skipped / 2 total)" ($vread.summary.pass -eq 1 -and $vread.summary.skipped -eq 1 -and $vread.summary.total -eq 2)
}
finally { Remove-Item -LiteralPath $vjsonPath -Force -ErrorAction SilentlyContinue }

# 12c. durable verdict persistence: autosave + auto-load (CORE) -- iteration 13 ----------------------------
#     'Save item verdict' now writes the verdict store to a result sidecar, and opening a packet auto-loads the
#     NEWEST saved result FOR that packet so re-opening shows prior progress instead of a blank checklist. The
#     packet file is never modified. The whole persistence path is disk-only + unit-tested here.
foreach ($fn in 'Get-VerdictResultsDir', 'Get-VerdictAutosavePath', 'Test-IsVerificationResult', 'Read-VerificationResultFile', 'Find-SavedResultPath', 'Import-ResultVerdicts', 'Build-VerificationResultFromStore', 'Save-VerdictStore') {
    Ok "persistence: function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}
Ok "persistence: autosave path is <packet_id>.json under runtime/results" ((Get-VerdictAutosavePath -PacketId 'vp-fixture-001' -WidgetRoot 'C:\w') -match 'runtime[\\/]results[\\/]vp-fixture-001\.json$')
Ok "persistence: a result is recognized; a packet is NOT" ((Test-IsVerificationResult -Obj ([pscustomobject]@{ schema = 'lifeorch.verification.result/0.1'; packet_id = 'p1'; items = @(); summary = @{} }) -PacketId 'p1') -and -not (Test-IsVerificationResult -Obj $pk -PacketId ''))
Ok "persistence: a result for a DIFFERENT packet is rejected" (-not (Test-IsVerificationResult -Obj ([pscustomobject]@{ schema = 'lifeorch.verification.result/0.1'; packet_id = 'other'; items = @(); summary = @{} }) -PacketId 'p1'))

$persistRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vc-persist-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $persistRoot 'runtime') -Force | Out-Null
try {
    $ppk = Import-VerificationPacket -Json ('{"schema":"lifeorch.verification.packet/0.1","packet_id":"vp-persist-1","title":"P","items":[' +
        '{"id":"A","kind":"human_action","title":"A","checklist":["a1","a2"]},{"id":"B","kind":"human_action","title":"B","checklist":["b1"]}]}')
    $pstore = Initialize-ItemVerdictStore -Items $ppk.items
    [void](Save-ItemVerdictState -Store $pstore -ItemId 'A' -Checked @($true, $false) -Overall 'pass' -Notes 'done A' -CheckTexts @('a1', 'a2'))
    $savedTo = Save-VerdictStore -Store $pstore -Items $ppk.items -Packet $ppk -WidgetRoot $persistRoot
    Ok "persistence: Save-VerdictStore wrote the autosave file" ([bool]$savedTo -and (Test-Path -LiteralPath $savedTo))
    $found = Find-SavedResultPath -PacketId 'vp-persist-1' -WidgetRoot $persistRoot
    Ok "persistence: Find-SavedResultPath finds the saved result" ([bool]$found -and (Test-Path -LiteralPath $found))
    Ok "persistence: Find-SavedResultPath returns '' for an unknown packet" ([string](Find-SavedResultPath -PacketId 'nope-xyz' -WidgetRoot $persistRoot) -eq '')

    # RE-OPEN: a fresh store seeded from the packet, then auto-loaded -> shows the saved verdicts (not blank)
    $freshStore = Initialize-ItemVerdictStore -Items $ppk.items
    Ok "persistence: fresh store starts blank (skipped)" ([string](Get-ItemVerdictState -Store $freshStore -ItemId 'A').overall -eq 'skipped')
    $loadedResult = Read-VerificationResultFile -Path $found
    $nLoaded = Import-ResultVerdicts -Store $freshStore -Items $ppk.items -Result $loadedResult
    $reA = Get-ItemVerdictState -Store $freshStore -ItemId 'A'
    Ok "persistence: auto-load restored A overall=pass across a fresh open" ([string]$reA.overall -eq 'pass' -and $nLoaded -ge 1)
    Ok "persistence: auto-load restored A checklist (a1=pass, a2=unchecked)" (@($reA.checks).Count -eq 2 -and [string]@($reA.checks)[0].verdict -eq 'pass' -and [string]@($reA.checks)[1].verdict -eq 'unchecked')
    Ok "persistence: auto-load restored A notes" ([string]$reA.notes -eq 'done A')
    Ok "persistence: unsaved item B stays default after auto-load" ([string](Get-ItemVerdictState -Store $freshStore -ItemId 'B').overall -eq 'skipped')

    # a packet that GAINED a check since the save still loads (structure stays authoritative; new check unchecked)
    $ppk2 = Import-VerificationPacket -Json ('{"schema":"lifeorch.verification.packet/0.1","packet_id":"vp-persist-1","title":"P","items":[' +
        '{"id":"A","kind":"human_action","title":"A","checklist":["a1","a2","a3-new"]}]}')
    $store2 = Initialize-ItemVerdictStore -Items $ppk2.items
    [void](Import-ResultVerdicts -Store $store2 -Items $ppk2.items -Result $loadedResult)
    $reA2 = Get-ItemVerdictState -Store $store2 -ItemId 'A'
    Ok "persistence: packet gained a check -> old verdicts kept, new check defaults unchecked" (@($reA2.checks).Count -eq 3 -and [string]@($reA2.checks)[0].verdict -eq 'pass' -and [string]@($reA2.checks)[2].verdict -eq 'unchecked')

    # newest-by-mtime wins when two results exist for the same packet (an older one next to the packet)
    $olderDir = Join-Path $persistRoot 'pkdir'; New-Item -ItemType Directory -Path $olderDir -Force | Out-Null
    $olderResult = Build-VerificationResultFromStore -Store (Initialize-ItemVerdictStore -Items $ppk.items) -Items $ppk.items -Packet $ppk
    [void](Save-VerificationResult -Result $olderResult -Path (Join-Path $olderDir 'verification-result-vp-persist-1.json'))
    (Get-Item -LiteralPath (Join-Path $olderDir 'verification-result-vp-persist-1.json')).LastWriteTimeUtc = [datetime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $foundNewest = Find-SavedResultPath -PacketPath (Join-Path $olderDir 'verification-packet.json') -PacketId 'vp-persist-1' -WidgetRoot $persistRoot
    Ok "persistence: newest-by-mtime result wins over an older one" ($foundNewest -eq $savedTo)
}
finally { Remove-Item -LiteralPath $persistRoot -Recurse -Force -ErrorAction SilentlyContinue }

# New-RunSummary idempotency (so a reloaded run_summary survives a re-export without losing artifacts/confidence)
$reSum = New-RunSummary -Run ([ordered]@{ ok = $true; skill_id = 'x.y'; skill_status = 'ok'; wrapper_exit = 0; confidence = 0.9; artifacts = @([ordered]@{ path = 'a.txt'; kind = 'file'; bytes = 5 }); artifact_root = 'root'; elapsed_ms = 12; error = $null })
Ok "persistence: New-RunSummary is idempotent (artifacts + confidence preserved)" ($reSum.ok -and $reSum.skill_id -eq 'x.y' -and @($reSum.artifacts).Count -eq 1 -and $reSum.confidence -eq 0.9)

# 13. launch.bat shape
$launch = Join-Path $widgetRoot 'launch.bat'
$lc = if (Test-Path $launch) { Get-Content $launch -Raw } else { '' }
Ok "launch.bat exists" (Test-Path $launch)
Ok "launch.bat uses -STA" ($lc -match '-STA')
Ok "launch.bat runs Show-VerificationConsole.ps1" ($lc -match 'Show-VerificationConsole\.ps1')

# ----- live / Windows-only -----
if ($Live -and $IsWindows) {
    $sta = & $PwshPath -NoProfile -STA -File (Join-Path $widgetRoot 'Show-VerificationConsole.ps1') -SelfTest 2>&1
    $staTxt = ($sta -join "`n")
    Ok "WinForms form builds (SelfTest)" ($staTxt -match 'SELFTEST_FORM_OK') (($sta -join ' | '))
    # the new discovery + by-kind rendering paths exercised on the real form under STA (D-0060: catch
    # rendered-UI/scope bugs the mock gate can't see).
    Ok "SelfTest: fixture packet loaded into the form" ($staTxt -match 'SELFTEST_PACKET_LOADED_OK') (($sta -join ' | '))
    Ok "SelfTest: by-kind render + Open affordance under STA" ($staTxt -match 'SELFTEST_ITEMRENDER_OK') (($sta -join ' | '))
    Ok "SelfTest: packets dir resolves in-shell" ($staTxt -match 'SELFTEST_PACKETSDIR_OK') (($sta -join ' | '))
    Ok "SelfTest: no rendered-UI scope failure" (-not ($staTxt -match 'SELFTEST_ITEMRENDER_FAIL')) (($sta -join ' | '))
    # D-0064: the verdict save/restore cycle exercised on the real controls (checklist + Overall + notes
    # survive navigate-away-and-back). This is the live check the human GUI pass still backstops.
    Ok "SelfTest: verdict persists across navigation (checklist + Overall + notes)" ($staTxt -match 'SELFTEST_VERDICT_PERSIST_OK') (($sta -join ' | '))
    Ok "SelfTest: no verdict-persistence regression" (-not ($staTxt -match 'SELFTEST_VERDICT_PERSIST_FAIL')) (($sta -join ' | '))
    # iteration 13: verdicts persist to disk on Save and auto-load when the packet is re-opened.
    Ok "SelfTest: verdicts auto-load on packet re-open (durable across sessions)" ($staTxt -match 'SELFTEST_AUTOLOAD_OK') (($sta -join ' | '))
    Ok "SelfTest: no auto-load regression" (-not ($staTxt -match 'SELFTEST_AUTOLOAD_FAIL')) (($sta -join ' | '))

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
    Skip "SelfTest: in-form discovery + by-kind render" "requires -Live on Windows"
    Skip "SelfTest: verdict persists across navigation" "requires -Live on Windows"
    Skip "SelfTest: verdicts auto-load on re-open" "requires -Live on Windows"
    Skip "real fs.observer run" "requires -Live on Windows"
    Skip "no-orphan check" "requires -Live on Windows"
    Skip "live orphan (model.gateway tiny warm)" "requires -Live on Windows"
}

Write-Host ""
Write-Host "=== RESULT: $script:pass passed, $script:fail failed, $script:skip skipped ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
