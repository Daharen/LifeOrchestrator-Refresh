<#
    Invoke-ModuleLauncherTests.ps1 - dual-mode test harness for the Module Launcher & Registry Browser.

    Cloud pre-ship gate (Linux, no -Live): AST-parse every script; drive the REAL core
    (ModuleLauncher.psm1) - registry discovery against a generated fixture modules tree, and the
    launcher spawn/parse/format path against tests/mock-invoke-skill.ps1 across a scenario matrix.
    The WinForms + real-Module tests are Windows-only and skipped off-Windows.

    Live (Windows, via the executor, -Live): the same tests plus the WinForms form builds
    (Show-ModuleLauncher.ps1 -SelfTest in an STA child), launch.bat shape, a REAL registry scan of
    the actual modules/ tree, and a REAL fs.observer run driven end-to-end through the real
    Module 1 wrapper, parsed and rendered, with no orphaned llama-server.
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
Import-Module (Join-Path $widgetRoot 'ModuleLauncher.psm1') -Force

if (-not $PwshPath) {
    $PwshPath = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $PwshPath)) { $PwshPath = Join-Path $PSHOME 'pwsh' }
}
$mockPath = Join-Path $here 'mock-invoke-skill.ps1'

$script:pass = 0; $script:fail = 0; $script:skip = 0
function Ok([string]$name, $cond, [string]$detail = '') {
    if ($cond) { $script:pass++; Write-Host "  [PASS] $name" }
    else { $script:fail++; Write-Host "  [FAIL] $name   $detail" }
}
function Skip([string]$name, [string]$why) { $script:skip++; Write-Host "  [SKIP] $name ($why)" }

Write-Host "=== Module Launcher tests (Live=$Live, IsWindows=$IsWindows) ==="

# 1. exported functions exist
foreach ($fn in 'Resolve-ModuleLauncherPaths', 'Get-ModuleRegistry', 'Format-ModuleListLine', 'Get-ModuleInputTemplate', 'Format-ModuleDetail', 'Start-ModuleProcess', 'Stop-ModuleProcess', 'Complete-ModuleRun', 'Invoke-ModuleRun', 'Format-ModuleResult', 'ConvertFrom-EnvelopeJson') {
    Ok "function exists: $fn" ([bool](Get-Command $fn -ErrorAction SilentlyContinue))
}

# 2. AST-parse every shipped script
$toParse = @(
    (Join-Path $widgetRoot 'ModuleLauncher.psm1'),
    (Join-Path $widgetRoot 'Show-ModuleLauncher.ps1'),
    $mockPath,
    (Join-Path $here 'Invoke-ModuleLauncherTests.ps1')
)
foreach ($f in $toParse) {
    $errs = $null; $toks = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$toks, [ref]$errs)
    Ok "AST parse: $(Split-Path $f -Leaf)" ($errs.Count -eq 0) ("errors=" + ($errs -join '; '))
}

# 3. path resolution
$paths = Resolve-ModuleLauncherPaths
Ok "resolve: modules dir path" ($paths.ModulesDir -like '*modules')
Ok "resolve: Invoke-Skill.ps1 path" ($paths.InvokeSkillPath -like '*01-skill-bootstrap*Invoke-Skill.ps1')
Ok "resolve: repo root exists" (Test-Path $paths.RepoRoot)

# ----- build a fixture modules tree -----
$fixRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ml-fixture-" + [guid]::NewGuid().ToString('N'))
$fixModules = Join-Path $fixRoot 'modules'
function New-FixtureModule([string]$folder, [hashtable]$manifest, [string]$entrypoint) {
    $d = Join-Path $fixModules $folder
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    ($manifest | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $d 'skill.json') -Encoding utf8
    if ($entrypoint) { Set-Content -LiteralPath (Join-Path $d $entrypoint) -Value '# fixture entrypoint' -Encoding utf8 }
    return $d
}
try {
    $docioDir = New-FixtureModule '20-doc-io' ([ordered]@{
            schema = 'lifeorch.skill.manifest/0.1'; skill_id = 'doc.io'; name = 'Local Document I/O'
            version = '0.1.0'; contract_version = '0.2'; purpose = 'Read, write, edit, and append UTF-8 text documents.'
            determinism = 'deterministic'
            invocation = [ordered]@{ method = 'pwsh-file'; entrypoint = 'Invoke-DocIo.ps1' }
            inputs = @(
                [ordered]@{ name = 'op'; type = 'string'; required = $true; description = 'read|write|edit|append' },
                [ordered]@{ name = 'path'; type = 'string'; required = $true; description = 'target file' },
                [ordered]@{ name = 'content'; type = 'string'; required = $false; description = 'new content' }
            )
            outputs = [ordered]@{ result_shape = 'object'; description = 'op result' }
            requirements = [ordered]@{ executables = @('pwsh>=7.4'); models = @(); gpu = 'none'; network = $false; filesystem = 'write'; screen = $false; audio = $false }
            artifacts = [ordered]@{ root = 'runtime/artifacts/<invocation_id>/' }
            timeout = [ordered]@{ default_seconds = 120; on_timeout = 'kill_tree_and_report' }
            batch = $false; streaming = $false; parallel_safe = $false
        }) 'Invoke-DocIo.ps1'

    $null = New-FixtureModule '02-fs-observer' ([ordered]@{
            schema = 'lifeorch.skill.manifest/0.1'; skill_id = 'fs.observer'; name = 'Filesystem Observer'
            version = '0.1.0'; contract_version = '0.1'; purpose = 'List and search a directory tree.'
            determinism = 'deterministic'
            invocation = [ordered]@{ method = 'pwsh-file'; entrypoint = 'Invoke-FsObserver.ps1' }
            inputs = @([ordered]@{ name = 'path'; type = 'string'; required = $true; description = 'root' },
                [ordered]@{ name = 'depth'; type = 'int'; required = $false; default = 3; description = 'max depth' })
            outputs = [ordered]@{ result_shape = 'object'; description = 'tree' }
            requirements = [ordered]@{ executables = @('pwsh>=7.4'); models = @(); gpu = 'none'; network = $false; filesystem = 'read'; screen = $false; audio = $false }
            artifacts = [ordered]@{ root = 'runtime/artifacts/<invocation_id>/' }
            timeout = [ordered]@{ default_seconds = 120; on_timeout = 'kill_tree_and_report' }
            batch = $false; streaming = $false; parallel_safe = $true
        }) 'Invoke-FsObserver.ps1'

    # a broken manifest (invalid JSON)
    $brokenDir = Join-Path $fixModules '99-broken'
    New-Item -ItemType Directory -Path $brokenDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $brokenDir 'skill.json') -Value '{ this is not valid json, ' -Encoding utf8

    # a folder with no manifest (should be skipped as not launchable)
    New-Item -ItemType Directory -Path (Join-Path $fixModules '98-nomanifest') -Force | Out-Null

    # 4. registry discovery
    $reg = Get-ModuleRegistry -ModulesDir $fixModules
    Ok "registry: 3 launchable modules (nomanifest skipped)" (@($reg).Count -eq 3) ("count=" + @($reg).Count)
    Ok "registry: nomanifest not listed" (-not (@($reg) | Where-Object { $_.folder_name -eq '98-nomanifest' }))
    $docE = @($reg) | Where-Object { $_.skill_id -eq 'doc.io' } | Select-Object -First 1
    Ok "registry: doc.io present + manifest_ok" ($null -ne $docE -and $docE.manifest_ok)
    Ok "registry: doc.io entrypoint" ($null -ne $docE -and $docE.entrypoint -eq 'Invoke-DocIo.ps1' -and $docE.entrypoint_exists)
    Ok "registry: doc.io required inputs op+path" ($null -ne $docE -and (@($docE.required_inputs) -contains 'op') -and (@($docE.required_inputs) -contains 'path'))
    Ok "registry: doc.io parallel_safe=false" ($null -ne $docE -and $docE.parallel_safe -eq $false)
    $brkE = @($reg) | Where-Object { $_.folder_name -eq '99-broken' } | Select-Object -First 1
    Ok "registry: broken manifest surfaced (manifest_ok=false)" ($null -ne $brkE -and -not $brkE.manifest_ok -and [bool]$brkE.manifest_error)
    # sorted by skill_id
    $ids = @($reg | ForEach-Object { [string]$_.skill_id })
    $sortedIds = @($ids | Sort-Object)
    Ok "registry: sorted by skill_id" (($ids -join '|') -eq ($sortedIds -join '|'))

    # 5. list line + input template + detail
    Ok "list line: doc.io renders" ((Format-ModuleListLine -Entry $docE) -match 'doc\.io')
    Ok "list line: broken flagged" ((Format-ModuleListLine -Entry $brkE) -match 'unreadable')
    $tpl = Get-ModuleInputTemplate -Entry $docE
    $tplObj = $tpl | ConvertFrom-Json
    Ok "input template: has required op+path keys" (($tplObj.PSObject.Properties.Name -contains 'op') -and ($tplObj.PSObject.Properties.Name -contains 'path'))
    Ok "input template: omits optional content" (-not ($tplObj.PSObject.Properties.Name -contains 'content'))
    $detail = Format-ModuleDetail -Entry $docE
    foreach ($needle in 'doc.io', 'PURPOSE', 'INPUTS', 'op', 'REQUIREMENTS') {
        Ok "detail contains '$needle'" ($detail -match [regex]::Escape($needle))
    }
    Ok "detail robust on broken manifest" ((Format-ModuleDetail -Entry $brkE) -match 'could not be parsed')

    # 6. launcher run via the mock -- clean ok run
    $run = Invoke-ModuleRun -SkillDir $docioDir -InputsJson '{"op":"read","path":"core-docs/START_HERE.md"}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run ok: ok=true" ($run.ok) ("status=$($run.skill_status) parse=$($run.parse_error) err=$(if($run.error){$run.error.message})")
    Ok "run ok: skill_id doc.io" ($run.skill_id -eq 'doc.io')
    Ok "run ok: manifest_valid + invoked + envelope_valid" ($run.manifest_valid -and $run.invoked -and $run.envelope_valid)
    Ok "run ok: skill_status ok" ($run.skill_status -eq 'ok')
    Ok "run ok: nested skill envelope present" ($null -ne $run.skill_envelope -and (Get-Prop $run.skill_envelope 'skill_id') -eq 'doc.io')
    $rt = Format-ModuleResult -Run $run
    foreach ($needle in 'MODULE:', 'WRAPPER:', 'RESULT:', 'RESULT PAYLOAD', 'ARTIFACTS') {
        Ok "result transcript contains '$needle'" ($rt -match [regex]::Escape($needle))
    }

    # 7. manifest-invalid scenario
    $badDir = Join-Path $fixModules 'badmanifest-x'
    New-Item -ItemType Directory -Path $badDir -Force | Out-Null
    $bad = Invoke-ModuleRun -SkillDir $badDir -InputsJson '{}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run badmanifest: not ok" (-not $bad.ok)
    Ok "run badmanifest: manifest_valid false" (-not $bad.manifest_valid)
    Ok "run badmanifest: error code manifest_invalid" ($null -ne $bad.error -and $bad.error.code -eq 'manifest_invalid')
    Ok "run badmanifest: renders manifest errors" ((Format-ModuleResult -Run $bad) -match 'MANIFEST ERRORS')

    # 8. skill returned status=error (a valid envelope)
    $errRun = Invoke-ModuleRun -SkillDir $docioDir -InputsJson '{"op":"read","path":"ERRORME"}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run error: not ok" (-not $errRun.ok)
    Ok "run error: skill_status error" ($errRun.skill_status -eq 'error')
    Ok "run error: surfaces skill error code" ($null -ne $errRun.error -and $errRun.error.code -eq 'input_not_found')
    Ok "run error: transcript shows ERROR" ((Format-ModuleResult -Run $errRun) -match 'ERROR')

    # 9. invoked but no valid envelope
    $badEnv = Invoke-ModuleRun -SkillDir $docioDir -InputsJson '{"op":"read","path":"BADENV"}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run badenv: not ok" (-not $badEnv.ok)
    Ok "run badenv: invoked true, envelope_valid false" ($badEnv.invoked -and -not $badEnv.envelope_valid)
    Ok "run badenv: error code envelope_invalid" ($null -ne $badEnv.error -and $badEnv.error.code -eq 'envelope_invalid')

    # 10. noisy stdout still parses
    $noisy = Invoke-ModuleRun -SkillDir $docioDir -InputsJson '{"op":"read","path":"NOISY"}' -InvokeSkillPath $mockPath -PwshPath $PwshPath
    Ok "run noisy: still parsed + ok" ($noisy.ok -and $null -ne $noisy.report)

    # 11. tolerant JSON extraction
    $e2 = ConvertFrom-EnvelopeJson -Text ("banner line`n{`"a`":1,`"b`":{`"c`":2}}`ntrailing junk")
    Ok "envelope-json extracts from noise" ($null -ne $e2 -and $e2.a -eq 1 -and $e2.b.c -eq 2)
}
finally {
    Remove-Item -LiteralPath $fixRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# 12. launch.bat shape
$launch = Join-Path $widgetRoot 'launch.bat'
$lc = if (Test-Path $launch) { Get-Content $launch -Raw } else { '' }
Ok "launch.bat exists" (Test-Path $launch)
Ok "launch.bat uses -STA" ($lc -match '-STA')
Ok "launch.bat runs Show-ModuleLauncher.ps1" ($lc -match 'Show-ModuleLauncher\.ps1')

# ----- live / Windows-only -----
if ($Live -and $IsWindows) {
    $sta = & $PwshPath -NoProfile -STA -File (Join-Path $widgetRoot 'Show-ModuleLauncher.ps1') -SelfTest 2>&1
    Ok "WinForms form builds (SelfTest)" (($sta -join "`n") -match 'SELFTEST_FORM_OK') (($sta -join ' | '))

    # real registry scan of the actual modules/ tree
    $realReg = Get-ModuleRegistry -ModulesDir $paths.ModulesDir
    Ok "real registry: >= 20 modules found" (@($realReg).Count -ge 20) ("count=" + @($realReg).Count)
    $rDoc = @($realReg) | Where-Object { $_.skill_id -eq 'doc.io' } | Select-Object -First 1
    $rFs = @($realReg) | Where-Object { $_.skill_id -eq 'fs.observer' } | Select-Object -First 1
    Ok "real registry: doc.io + fs.observer present, manifest_ok" ($null -ne $rDoc -and $rDoc.manifest_ok -and $null -ne $rFs -and $rFs.manifest_ok)
    Ok "real registry: entrypoints exist on disk" ($null -ne $rFs -and $rFs.entrypoint_exists)

    # a REAL fs.observer run through the real Module 1 wrapper (cheap, deterministic, no GPU)
    $realWrap = if ($InvokeSkillPath) { $InvokeSkillPath } else { $paths.InvokeSkillPath }
    $before = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
    $real = Invoke-ModuleRun -SkillDir $rFs.skill_dir -InputsJson '{"path":".","depth":1}' -InvokeSkillPath $realWrap -PwshPath $PwshPath -WorkingDir $paths.RepoRoot
    Ok "real fs.observer: invoked + valid envelope" ($real.invoked -and $real.envelope_valid) ("status=$($real.skill_status) wrap_exit=$($real.wrapper_exit) parse=$($real.parse_error)")
    Ok "real fs.observer: skill_id fs.observer" ($real.skill_id -eq 'fs.observer')
    Ok "real fs.observer: ok" ($real.ok) ("status=$($real.skill_status)")
    Ok "real fs.observer: renders a result" ((Format-ModuleResult -Run $real).Length -gt 0)
    Start-Sleep -Seconds 2
    $after = @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue).Count
    Ok "real run: no orphaned llama-server" ($after -le $before) ("before=$before after=$after")
}
else {
    Skip "WinForms form self-test" "requires -Live on Windows"
    Skip "real registry scan" "requires -Live on Windows"
    Skip "real fs.observer run" "requires -Live on Windows"
    Skip "no-orphan check" "requires -Live on Windows"
}

Write-Host ""
Write-Host "=== RESULT: $script:pass passed, $script:fail failed, $script:skip skipped ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
