<#
    Invoke-ProvenanceMapTests.ps1 - dual-mode test harness for the Provenance Map (Widget 05).

    Cloud pre-ship gate (Linux, no -Live): AST-parse + ASCII-guard every shipped script; drive the REAL core
    (ProvenanceMap.psm1) over the shipped fixture repo (core-docs + plans + verdicts) + an injected git-log
    fixture + synthetic temp trees -- doc-budget flagging (over-budget + nocap + missing + glob), the decision
    index, module/widget unit parse + status + name cleanup, the tests table (version/iteration/commit), the
    iteration ledger (single + range), the candidate menu, git-log parse (iteration/plan/D-refs/files/units),
    plan provenance (newest-first + a MALFORMED plan.json -> ok=false, no throw), verification verdicts, the
    full JOIN (Get-ProvenanceModel), the one-click Get-IterationBuild, Get-NewSince, the Format-* views, and
    the read-only guarantees: Get-ProvenanceModel leaves the repo byte-identical + Set-LastVisit writes ONLY
    under its own runtime dir. Defensive: every source degrades to a VISIBLE FLAG, never a throw.

    Live (Windows, via the executor, -Live): the same tests PLUS launch.bat shape, the WinForms form builds +
    drives (Show-ProvenanceMap.ps1 -SelfTest in an STA child, asserting the SELFTEST_*_OK markers incl.
    SELFTEST_LAYOUT_OK + SELFTEST_READONLY_OK), and -- if the production core-docs are present -- the model
    renders the REAL repo with no throw.
#>
[CmdletBinding()]
param([switch]$Live, [string]$PwshPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$widgetRoot = Split-Path $here -Parent
Import-Module (Join-Path $widgetRoot 'ProvenanceMap.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}

$fixtures = Join-Path $here 'fixtures'
$fxRepo = Join-Path $fixtures 'repo'
$fxCore = Join-Path $fxRepo 'core-docs'
$fxPlans = Join-Path $fixtures 'plans'
$fxVerdicts = Join-Path $fixtures 'verdicts'
$fxGitFile = Join-Path $fixtures 'git-log.fixture.txt'
$fxGit = ((Get-Content -LiteralPath $fxGitFile -Raw) -replace '<<RS>>', ([char]0x1E)) -replace '<<US>>', ([char]0x1F)

$script:pass = 0; $script:fail = 0; $script:skip = 0
function Ok([string]$name, $cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name   $detail" }
}
function Skip([string]$name, [string]$why) { $script:skip++; Write-Host "  [SKIP] $name ($why)" }
$script:tempRoots = New-Object System.Collections.Generic.List[string]
function Get-TreeSig([string]$Root) {
    $acc = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        [void]$acc.Add($f.FullName + '|' + [string]$f.Length + '|' + $f.LastWriteTimeUtc.ToString('o'))
    }
    return ($acc.ToArray() -join "`n")
}

Write-Host "=== Provenance Map tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist
foreach ($fn in 'Get-Prop', 'ConvertTo-Array', 'Read-TextFileSafe', 'Split-TableRow', 'Get-MatchList',
    'Resolve-ProvenancePaths', 'Get-DocBudgetFlags', 'Get-DecisionIndex', 'Get-ModuleUnits', 'Get-UnitName',
    'Get-TestTable', 'Get-IterationLedger', 'Get-HandoffCandidates', 'ConvertFrom-GitLog', 'Get-GitProvenance',
    'Get-PlanProvenance', 'Get-VerificationVerdicts', 'Get-ProvenanceModel', 'Get-IterationBuild', 'Get-NewSince',
    'Get-IterationList', 'Get-LastVisit', 'Set-LastVisit', 'Format-ProvenanceRows', 'Format-IterationBuild', 'Format-NewSince') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse + 2b. ASCII-only guard on every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'ProvenanceMap.psm1'),
    (Join-Path $widgetRoot 'Show-ProvenanceMap.ps1'),
    (Join-Path $here 'Invoke-ProvenanceMapTests.ps1'))
foreach ($f in $toParse) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Ok "AST parse: $(Split-Path $f -Leaf)" (@($errs).Count -eq 0) ("errors=" + (@($errs) -join '; '))
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
    Ok "ASCII-only: $(Split-Path $f -Leaf)" ($nonAscii -eq 0) ("non-ascii bytes=$nonAscii")
}

# 3. path resolution smoke + env/param override
$paths = Resolve-ProvenancePaths -WidgetRoot $widgetRoot -RepoRoot $fxRepo
Ok "resolve: RepoRoot honored" ([string]$paths.RepoRoot -eq $fxRepo)
Ok "resolve: core-docs under repo" ([string]$paths.CoreDocs -match 'core-docs')
Ok "resolve: plans dir path" ([string]$paths.PlansDir -match '30-orchestrate-fanout' -and [string]$paths.PlansDir -match 'plans')
Ok "resolve: runtime dir under widget" ([string]$paths.RuntimeDir -match 'runtime')

# 4. StrictMode-trap helpers
Ok "ConvertTo-Array null -> 0" (@(ConvertTo-Array $null).Count -eq 0)
Ok "ConvertTo-Array string -> 1 (not chars)" (@(ConvertTo-Array 'abc').Count -eq 1)
Ok "ConvertTo-Array array -> n" (@(ConvertTo-Array @(1, 2, 3)).Count -eq 3)
Ok "Split-TableRow drops border pipes" (@(Split-TableRow '| a | b | c |').Count -eq 3)
Ok "Get-MatchList de-dupes preserving order" (((Get-MatchList -Text 'D-1 D-2 D-1' -Pattern '(D-\d+)') -join ',') -eq 'D-1,D-2')

# 5. doc-budget flags (over-budget + ok + nocap + missing + glob)
$db = Get-DocBudgetFlags -DocProtocolPath $paths.DocProtocol -CoreDocsDir $fxCore
$cs = @($db.rows) | Where-Object { $_.doc -eq 'CURRENT_STATE.md' } | Select-Object -First 1
$sh = @($db.rows) | Where-Object { $_.doc -eq 'START_HERE.md' } | Select-Object -First 1
$dl = @($db.rows) | Where-Object { $_.doc -eq 'DECISION_LOG.md' } | Select-Object -First 1
Ok "docbudget: CURRENT_STATE flagged OVER" ($null -ne $cs -and $cs.over -and $cs.status -eq 'over')
Ok "docbudget: START_HERE ok (under budget)" ($null -ne $sh -and -not $sh.over -and $sh.status -eq 'ok')
Ok "docbudget: DECISION_LOG nocap" ($null -ne $dl -and $dl.status -eq 'nocap')
Ok "docbudget: an OVER-BUDGET flag emitted (PB-3)" ((@($db.flags) -join "`n") -match 'OVER BUDGET' -and (@($db.flags) -join "`n") -match 'PB-3')

# 6. decision index
$di = Get-DecisionIndex -DecisionIndexPath $paths.DecisionIndex
Ok "decisions: >=5 rows parsed" (@($di.rows).Count -ge 5)
$d110 = @($di.rows) | Where-Object { $_.id -eq 'D-0110' } | Select-Object -First 1
Ok "decisions: D-0110 present with iteration hint i40" ($null -ne $d110 -and (@($d110.iterations) -contains 40))
Ok "decisions: newest-first (D-0110 before D-0002)" ([string]@($di.rows)[0].id -eq 'D-0110')

# 7. module/widget units + name cleanup (strips the em-dash/middot around the name)
$mu = Get-ModuleUnits -RoadmapPath $paths.Roadmap
$m7 = @($mu.rows) | Where-Object { $_.kind -eq 'module' -and $_.num -eq '7' } | Select-Object -First 1
$w5 = @($mu.rows) | Where-Object { $_.kind -eq 'widget' -and $_.num -eq '05' } | Select-Object -First 1
Ok "units: module #7 parsed id=model.gateway status=MVP complete built" ($null -ne $m7 -and $m7.id -eq 'model.gateway' -and $m7.built)
Ok "units: module #7 name cleaned (no em-dash/middot)" ($null -ne $m7 -and $m7.name -eq 'Local Model Gateway')
Ok "units: module #7 carries D-refs" ($null -ne $m7 -and @($m7.d_refs).Count -ge 1)
Ok "units: widget 05 parsed status=Proposed NOT built" ($null -ne $w5 -and $w5.status -eq 'Proposed' -and -not $w5.built)

# 8. tests table (version/iteration/commit)
$tt = Get-TestTable -CurrentStatePath $paths.CurrentState
$t7 = @($tt.rows) | Where-Object { $_.kind -eq 'module' -and $_.num -eq '7' } | Select-Object -First 1
$t4 = @($tt.rows) | Where-Object { $_.kind -eq 'widget' -and $_.num -eq '04' } | Select-Object -First 1
Ok "tests: #7 version 0.7.0 + iteration 40 + commit a1a1a1a" ($null -ne $t7 -and $t7.version -eq '0.7.0' -and $t7.iteration -eq '40' -and $t7.commit -eq 'a1a1a1a')
Ok "tests: widgets/04 row parsed with commit" ($null -ne $t4 -and $t4.commit -eq 'b2b2b2b')

# 9. iteration ledger (single + range)
$il = Get-IterationLedger -HandoffPath $paths.Handoff
$i40 = @($il.rows) | Where-Object { $_.iteration -eq 40 -and -not $_.is_range } | Select-Object -First 1
$irange = @($il.rows) | Where-Object { $_.is_range } | Select-Object -First 1
Ok "ledger: i40 line -> D-0110 + commits a1a1a1a,b2b2b2b" ($null -ne $i40 -and (@($i40.d_refs) -contains 'D-0110') -and (@($i40.commits) -contains 'a1a1a1a') -and (@($i40.commits) -contains 'b2b2b2b'))
Ok "ledger: i39 plan id parsed (hex)" ((@($il.rows) | Where-Object { $_.iteration -eq 39 } | Select-Object -First 1).plan_ids -contains 'fo-39-abc123de')
Ok "ledger: a range line (i1-i38) parsed with iter_end" ($null -ne $irange -and $irange.iteration -eq 1 -and $irange.iter_end -eq 38)

# 10. handoff candidate menu
$cand = @(Get-HandoffCandidates -HandoffPath $paths.Handoff)
Ok "candidates: >=3 numbered items" ($cand.Count -ge 3)
Ok "candidates: names the query ROUTER" ((@($cand | ForEach-Object { $_.label }) -join "`n") -match 'router')

# 11. git-log parse
$gl = @(ConvertFrom-GitLog -LogText $fxGit)
$g1 = $gl | Where-Object { $_.hash -eq 'a1a1a1a' } | Select-Object -First 1
Ok "git: 4 commits parsed" ($gl.Count -eq 4)
Ok "git: a1a1a1a iter=40 D-0110 touched module:07" ($null -ne $g1 -and $g1.iteration -eq '40' -and (@($g1.d_refs) -contains 'D-0110') -and (@($g1.units) -contains 'module:07'))
$g3 = $gl | Where-Object { $_.hash -eq 'c3c3c3c' } | Select-Object -First 1
Ok "git: c3c3c3c plan_id fo-39-abc123de + files listed" ($null -ne $g3 -and $g3.plan_id -eq 'fo-39-abc123de' -and @($g3.files).Count -ge 1)

# 12. git provenance graceful: -LogText path + missing .git flag
$gp = Get-GitProvenance -LogText $fxGit
Ok "gitprov: -LogText -> ok + rows" ([bool]$gp.ok -and @($gp.rows).Count -eq 4)
$tmpNoGit = Join-Path ([System.IO.Path]::GetTempPath()) ('prov-nogit-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmpNoGit -Force | Out-Null; $script:tempRoots.Add($tmpNoGit)
$gpn = Get-GitProvenance -RepoRoot $tmpNoGit
Ok "gitprov: no .git -> ok=false + a flag (graceful, no throw)" ((-not $gpn.ok) -and (@($gpn.flags) -join "`n") -match 'git provenance unavailable')

# 13. plan provenance (newest-first + malformed plan.json graceful)
$pp = Get-PlanProvenance -PlansDir $fxPlans
Ok "plans: >=3 dirs scanned" (@($pp.rows).Count -ge 3)
Ok "plans: newest iteration first (i40)" (@($pp.rows)[0].iteration -eq 40)
$broken = @($pp.rows) | Where-Object { $_.plan_id -match 'fo-38-broken' -or -not $_.ok } | Select-Object -First 1
Ok "plans: a MALFORMED plan.json -> ok=false row, no throw" ($null -ne $broken -and -not $broken.ok)
$p40 = @($pp.rows) | Where-Object { $_.iteration -eq 40 } | Select-Object -First 1
Ok "plans: i40 done=2" ($null -ne $p40 -and $p40.done -eq 2)

# 14. verification verdicts
$vv = Get-VerificationVerdicts -VerdictsDir $fxVerdicts
Ok "verdicts: fixture packet parsed pass=2 partial=1" (@($vv.rows).Count -ge 1 -and @($vv.rows)[0].pass -eq 2 -and @($vv.rows)[0].partial -eq 1)

# 15. FULL JOIN
$model = Get-ProvenanceModel -RepoRoot $fxRepo -WidgetRoot $widgetRoot -GitLogText $fxGit -PlansDir $fxPlans -VerdictsDir $fxVerdicts
Ok "model: ok" ([bool]$model.ok)
Ok "model: counts modules=2 widgets=2 built=3 planned>=1" ($model.counts.modules -eq 2 -and $model.counts.widgets -eq 2 -and $model.counts.built -eq 3 -and $model.counts.planned -ge 1)
Ok "model: over_budget_docs=1" ($model.counts.over_budget_docs -eq 1)
Ok "model: >=1 degradation flag (the over-budget doc)" ($model.counts.degradation_flags -ge 1)
$um7 = @($model.units) | Where-Object { $_.key -eq 'module:7' } | Select-Object -First 1
Ok "model: unit #7 joined version+iteration+commit+verified" ($null -ne $um7 -and $um7.version -eq '0.7.0' -and $um7.iteration -eq '40' -and $um7.commit -eq 'a1a1a1a' -and $um7.has_test_row)
$uw5 = @($model.units) | Where-Object { $_.key -eq 'widget:05' } | Select-Object -First 1
Ok "model: widget 05 planned (unbuilt, no test row)" ($null -ne $uw5 -and $uw5.planned -and -not $uw5.has_test_row)
Ok "model: planned includes widget 05 + handoff-menu candidates" ((@($model.planned | ForEach-Object { $_.source }) -contains 'roadmap') -and (@($model.planned | ForEach-Object { $_.source }) -contains 'handoff-menu'))

# 16. one-click iteration build
$b40 = Get-IterationBuild -Model $model -Iteration 40
Ok "iterbuild: i40 found" ([bool]$b40.found)
Ok "iterbuild: i40 names decision D-0110" ((@($b40.decisions | ForEach-Object { $_.id }) -contains 'D-0110'))
Ok "iterbuild: i40 units include #7 AND widget 04 (commit-touched)" ((@($b40.units | ForEach-Object { $_.key }) -contains 'module:7') -and (@($b40.units | ForEach-Object { $_.key }) -contains 'widget:04'))
Ok "iterbuild: i40 commits include a1a1a1a" ((@($b40.commits | ForEach-Object { $_.hash }) -contains 'a1a1a1a'))
$b999 = Get-IterationBuild -Model $model -Iteration 999
Ok "iterbuild: unknown iteration -> found=false (no throw)" (-not [bool]$b999.found)

# 17. new since
$ns = Get-NewSince -Model $model -Since 39
Ok "newsince: since 39 -> 1 unit (#7)" (@($ns.units).Count -eq 1 -and @($ns.units)[0].key -eq 'module:7')
Ok "newsince: since 39 -> 2 commits (i40)" (@($ns.commits).Count -eq 2)
Ok "newsince: since 39 -> D-0110 decision" ((@($ns.decisions | ForEach-Object { $_.id }) -contains 'D-0110'))

# 17b. Get-IterationList -- the picker list (moved out of the UI shell so it is TESTED: an [ordered] hashtable
#      indexed by an INT key resolves POSITIONALLY -> ArgumentOutOfRangeException -> a modal dialog that HANGS a
#      headless SelfTest. This asserts it neither throws nor mismaps.
$il2 = @(Get-IterationList -Model $model)
Ok "iterlist: newest-first nums (40 then 39)" ($il2.Count -ge 3 -and $il2[0].num -eq 40 -and $il2[1].num -eq 39)
Ok "iterlist: a range iteration is labelled 'range'" ((@($il2 | ForEach-Object { $_.label }) -join "`n") -match 'range')
Ok "iterlist: every label maps to its own num (no positional-index bug)" (@($il2 | Where-Object { ($_.label -eq ('i' + [string]$_.num)) -or ($_.label -match 'range|git only') }).Count -eq $il2.Count)

# 18. Format-* views
$rows = Format-ProvenanceRows -Model $model
Ok "format: header names PROVENANCE MAP + counts" ((@($rows.header_lines) -join ' ') -match 'PROVENANCE MAP' -and (@($rows.header_lines) -join ' ') -match 'modules:')
Ok "format: exists table lists model.gateway" ((@($rows.exists_lines) -join "`n") -match 'model.gateway')
Ok "format: doc-budget marks CURRENT_STATE OVER" ((@($rows.docflag_lines) -join "`n") -match 'CURRENT_STATE' -and (@($rows.docflag_lines) -join "`n") -match 'OVER')
Ok "format: planned lists widget 05" ((@($rows.planned_lines) -join "`n") -match 'Provenance Map')
$fb = Format-IterationBuild -Build $b40
Ok "format: iteration build lists DECISIONS + D-0110" ((@($fb.lines) -join "`n") -match 'DECISIONS' -and (@($fb.lines) -join "`n") -match 'D-0110')
$fns = Format-NewSince -NewSince $ns
Ok "format: new-since header" ((@($fns.lines) -join "`n") -match 'NEW SINCE ITERATION 39')

# 19. Set-LastVisit / Get-LastVisit round-trip + write-guard (writes ONLY under its runtime dir)
$tmpRt = Join-Path ([System.IO.Path]::GetTempPath()) ('prov-rt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$script:tempRoots.Add($tmpRt)
$wrote = Set-LastVisit -Iteration 41 -RuntimeDir $tmpRt -SeenUtc '2026-08-06T00:00:00Z'
Ok "lastvisit: write lands under the runtime dir" (([string]$wrote).StartsWith([System.IO.Path]::GetFullPath($tmpRt)))
Ok "lastvisit: exactly one file written" (@(Get-ChildItem -LiteralPath $tmpRt -Recurse -File).Count -eq 1)
$lv = Get-LastVisit -RuntimeDir $tmpRt
Ok "lastvisit: round-trips iteration 41" ($null -ne $lv -and $lv.last_iteration -eq 41)

# 20. graceful degradation: an EMPTY repo root -> model ok=true but every doc source flags (no throw)
$emptyRepo = Join-Path ([System.IO.Path]::GetTempPath()) ('prov-empty-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $emptyRepo -Force | Out-Null; $script:tempRoots.Add($emptyRepo)
$em = Get-ProvenanceModel -RepoRoot $emptyRepo -WidgetRoot $widgetRoot -GitLogText ''
Ok "graceful: empty repo -> model ok=true, no throw" ([bool]$em.ok)
Ok "graceful: empty repo -> flags name the unreadable docs" ((@($em.flags) -join "`n") -match 'MODULE_ROADMAP' -and (@($em.flags) -join "`n") -match 'DOC_PROTOCOL')
Ok "graceful: empty repo -> 0 units, no throw" (@($em.units).Count -eq 0)

# 21. READ-ONLY: Get-ProvenanceModel leaves the fixture repo byte-identical
$sigBefore = Get-TreeSig $fixtures
[void](Get-ProvenanceModel -RepoRoot $fxRepo -WidgetRoot $widgetRoot -GitLogText $fxGit -PlansDir $fxPlans -VerdictsDir $fxVerdicts)
[void](Format-ProvenanceRows -Model $model)
$sigAfter = Get-TreeSig $fixtures
Ok "readonly: fixture tree byte-identical after a full model build + render" ($sigBefore -eq $sigAfter)

# ---------- LIVE (Windows) ----------
if ($Live) {
    if (-not $IsWindows) {
        Skip 'live: WinForms self-test' 'not Windows'; Skip 'live: launch.bat' 'not Windows'; Skip 'live: real repo' 'not Windows'
    }
    else {
        $lb = Join-Path $widgetRoot 'launch.bat'
        Ok "live: launch.bat exists" (Test-Path $lb)
        if (Test-Path $lb) {
            $lbTxt = Get-Content -LiteralPath $lb -Raw
            Ok "live: launch.bat runs Show-ProvenanceMap.ps1 under -STA" ($lbTxt -match 'Show-ProvenanceMap\.ps1' -and $lbTxt -match '-STA')
        }
        $show = Join-Path $widgetRoot 'Show-ProvenanceMap.ps1'
        $out = & $PwshPath -NoProfile -STA -File $show -SelfTest 2>&1 | Out-String
        Write-Host "  --- self-test child output ---"
        foreach ($ln in ($out -split "`r?`n")) { if ($ln.Trim()) { Write-Host "    $ln" } }
        foreach ($marker in 'SELFTEST_FORM_OK', 'SELFTEST_MODEL_OK', 'SELFTEST_ITERATION_OK', 'SELFTEST_NEWSINCE_OK',
            'SELFTEST_FLAGS_OK', 'SELFTEST_READONLY_OK', 'SELFTEST_REFRESH_OK', 'SELFTEST_LAYOUT_OK') {
            Ok "live: self-test emitted $marker" ($out -match $marker)
        }
        Ok "live: self-test has no FAIL marker" (-not ($out -match 'SELFTEST_\w+_FAIL'))

        # render the REAL production repo (widget root's ../..) if its core-docs are present
        $realRepo = Resolve-Path -LiteralPath (Join-Path $widgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
        if ($realRepo -and (Test-Path -LiteralPath (Join-Path $realRepo.Path 'core-docs') -PathType Container)) {
            $realModel = Get-ProvenanceModel -RepoRoot $realRepo.Path -WidgetRoot $widgetRoot
            Ok "live: model renders the REAL repo (ok, >=20 units, >=1 commit)" ([bool]$realModel.ok -and @($realModel.units).Count -ge 20 -and @($realModel.commits).Count -ge 1) ("units=$(@($realModel.units).Count) commits=$(@($realModel.commits).Count) git_ok=$($realModel.git_ok)")
            Ok "live: REAL repo iteration build for a recent wave is found" ([bool](Get-IterationBuild -Model $realModel -Iteration 35).found -or [bool](Get-IterationBuild -Model $realModel -Iteration 34).found)
        }
        else { Skip 'live: real repo render' 'no production core-docs on this box' }
    }
}
else {
    Skip 'live: WinForms self-test' 'cloud gate (use -Live on Windows)'
    Skip 'live: launch.bat shape' 'cloud gate'
    Skip 'live: real repo render' 'cloud gate'
}

foreach ($t in $script:tempRoots) { try { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue } catch { } }

Write-Host ""
Write-Host "=== RESULT: pass=$($script:pass) fail=$($script:fail) skip=$($script:skip) ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
