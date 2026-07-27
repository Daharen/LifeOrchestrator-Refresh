#requires -Version 7.0
<#
.SYNOPSIS
  dev.ship -- the Life Orchestrator UNIT-SHIP orchestrator (Module 0 job-runner, D-0047/D-0048).
.DESCRIPTION
  Collapses the repetitive per-unit "gate + commit" ceremony into ONE executor job that emits ONE
  compact JSON summary. Given a set of already-shipped files (with expected sha256), an optional test
  command, and an optional commit spec, it runs -- in order, FAIL-CLOSED --:
     1. VERIFY   each file's sha256 on disk matches the expected value (byte-exact ship check);
     2. AST      parse every *.ps1 among those files (syntax gate) when ast_check is on;
     3. TEST     run test_argv (argv-style; {PWSH}/{REPO} tokens) and capture exit code + a tail;
     4. COMMIT   ONLY IF sha+ast+tests are all green AND the index is clean of unrelated staged files:
                 git add -- <exactly commit_files>, then git commit -F <message-with-trailers>.
                 The index-check + add + commit run under the res.lease 'git' lease (Module 29) so
                 concurrent instances serialize their commits; ABSENT/disabled/contended -> proceed
                 (git's own .git/index.lock is the backstop, so behaviour is never worse than pre-lease).
     5. ORPHANS  optionally count named processes (e.g. llama-server) for the summary.
  The commit gate is deterministic and fail-closed: a failed sha/ast/test check NEVER commits. The
  index-clean guard refuses to commit when files outside commit_files are already staged (so it can
  never fold in an unrelated working edit -- e.g. the user's Show-AgentConsole.ps1).

  It is dev TOOLING (part of Module 0, like the executor itself), NOT a contract skill: it emits a
  single lifeorch.devship.result/0.1 JSON object on stdout; diagnostics go to stderr. Exit 0 iff the
  overall result is ok (so the executor's completed/failed status mirrors the gate); exit 1 on a gate
  failure; exit 2 on an internal error (with an error summary still on stdout).
.EXAMPLE
  pwsh -NoProfile -File .\Invoke-DevShip.ps1 -InputsJson '{"files":[{"path":"modules/21-agent-local/Invoke-AgentLocal.ps1","sha256":"..."}],"test_argv":["pwsh","-NoProfile","-File","modules/21-agent-local/tests/Invoke-AgentLocalTests.ps1","-PwshExe","{PWSH}"],"commit":false}'
#>
[CmdletBinding()]
param(
    [string]$InputsJson,
    [string]$RepoRoot,
    [switch]$NoCommit
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedAt = [DateTime]::UtcNow
$sw = [System.Diagnostics.Stopwatch]::StartNew()

function Write-Diag([string]$m) { [Console]::Error.WriteLine("[dev.ship] $m") }
function Has([object]$o, [string]$n) { return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o, [string]$n, $d = $null) { if (Has $o $n) { $v = $o.$n; if ($null -ne $v) { return $v } } return $d }
function Get-FileSha256([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
# Run res.lease (Module 29) as a CHILD process and return its parsed envelope, or $null on any failure
# (missing script / non-JSON / crash) so every caller can fall back gracefully. NEVER dot-source res.lease:
# it ends with `exit 0`, which would terminate dev.ship.
function Invoke-ResLeaseAction([string]$pwshExe, [string]$script, [string]$repoRoot, [string[]]$argv) {
    if ([string]::IsNullOrWhiteSpace($script) -or -not (Test-Path -LiteralPath $script -PathType Leaf)) { return $null }
    $out = $null
    Push-Location $repoRoot
    try {
        $global:LASTEXITCODE = 0
        $out = & $pwshExe -NoLogo -NoProfile -File $script @argv 2>$null | Out-String
    } catch { return $null } finally { Pop-Location }
    if ([string]::IsNullOrWhiteSpace($out)) { return $null }
    try { return ($out | ConvertFrom-Json) } catch { return $null }
}

$warnings = New-Object System.Collections.Generic.List[string]
$result = $null
$exitCode = 0

try {
    # ---- parse inputs ----
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try { $p = $InputsJson | ConvertFrom-Json } catch { throw "InputsJson is not valid JSON: $($_.Exception.Message)" }
    }

    # ---- resolve repo root ----
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $RepoRoot = if ($null -ne $p) { [string](Prop $p 'repo_root' '') } else { '' }
    }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        # Invoke-DevShip.ps1 lives at <repo>/modules/00-bootstrap-executor/ ; repo = up two.
        $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { throw "repo_root does not exist: $RepoRoot" }
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

    $astCheck = if ($null -ne $p) { [bool](Prop $p 'ast_check' $true) } else { $true }
    $commitRequested = if ($NoCommit) { $false } elseif ($null -ne $p) { [bool](Prop $p 'commit' $false) } else { $false }
    $allowDirtyIndex = if ($null -ne $p) { [bool](Prop $p 'allow_dirty_index' $false) } else { $false }
    # git-lease knobs (res.lease 'git'): serialize concurrent commits across instances. Default ON; degrades gracefully.
    $useGitLease    = if ($null -ne $p) { [bool](Prop $p 'git_lease' $true) } else { $true }
    $gitLeaseTtl    = if ($null -ne $p) { [int](Prop $p 'git_lease_ttl_seconds' 120) } else { 120 }
    $gitLeaseWait   = if ($null -ne $p) { [double](Prop $p 'git_lease_wait_seconds' 120) } else { 120 }
    $gitLeaseHolder = if ($null -ne $p) { [string](Prop $p 'git_lease_holder' '') } else { '' }

    # ---- 1) VERIFY sha256 of each shipped file ----
    $files = @(); if ($null -ne $p -and (Has $p 'files')) { $files = @($p.files) }
    $shaChecked = 0
    $mismatches = New-Object System.Collections.Generic.List[object]
    $psFiles = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $rel = [string](Prop $f 'path' '')
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        $shaChecked++
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            $mismatches.Add([ordered]@{ path = $rel; expected = [string](Prop $f 'sha256' ''); actual = $null; reason = 'missing' })
            continue
        }
        if ($rel -match '\.ps1$') { $psFiles.Add($full) }
        $expected = ([string](Prop $f 'sha256' '')).ToLowerInvariant().Trim()
        if ([string]::IsNullOrWhiteSpace($expected)) { continue }   # sha optional per file
        $actual = Get-FileSha256 $full
        if ($actual -ne $expected) {
            $mismatches.Add([ordered]@{ path = $rel; expected = $expected; actual = $actual; reason = 'sha_mismatch' })
        }
    }
    $shaOk = ($mismatches.Count -eq 0)

    # ---- 2) AST parse every *.ps1 ----
    $astChecked = 0
    $astErrors = New-Object System.Collections.Generic.List[object]
    if ($astCheck) {
        foreach ($full in $psFiles) {
            $astChecked++
            $tokens = $null; $errs = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$tokens, [ref]$errs)
            if ($null -ne $errs -and $errs.Count -gt 0) {
                foreach ($e in $errs) {
                    $astErrors.Add([ordered]@{ path = $full; line = $e.Extent.StartLineNumber; message = [string]$e.Message })
                }
            }
        }
    }
    $astOk = ($astErrors.Count -eq 0)

    # ---- 3) TEST (argv-style; {PWSH}/{REPO} substitution) ----
    $resolvedPwsh = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $resolvedPwsh)) { try { $resolvedPwsh = (Get-Process -Id $PID).Path } catch { $resolvedPwsh = 'pwsh' } }
    $testArgv = @(); if ($null -ne $p -and (Has $p 'test_argv')) { $testArgv = @($p.test_argv | ForEach-Object { [string]$_ }) }
    $testsRan = $false; $testsExit = $null; $testsPass = $true; $testsTail = $null
    if ($testArgv.Count -gt 0) {
        $testsRan = $true
        $argvS = @($testArgv | ForEach-Object { $_.Replace('{PWSH}', $resolvedPwsh).Replace('{REPO}', $RepoRoot) })
        $prog = $argvS[0]
        if ($prog -in @('pwsh', 'pwsh.exe', '')) { $prog = $resolvedPwsh }
        $rest = @(); if ($argvS.Count -gt 1) { $rest = $argvS[1..($argvS.Count - 1)] }
        Push-Location $RepoRoot
        try {
            $global:LASTEXITCODE = 0
            $out = & $prog @rest 2>&1 | Out-String
            $testsExit = $LASTEXITCODE
        } finally { Pop-Location }
        $testsPass = ($testsExit -eq 0)
        $lines = @($out -split "`r?`n")
        if ($lines.Count -gt 20) { $testsTail = ($lines[($lines.Count - 20)..($lines.Count - 1)] -join "`n") } else { $testsTail = ($lines -join "`n") }
        $testsTail = $testsTail.Trim()
        Write-Diag "tests exit=$testsExit pass=$testsPass"
    }

    # ---- gate ----
    $gateOk = $shaOk -and $astOk -and ((-not $testsRan) -or $testsPass)

    # ---- 4) COMMIT (fail-closed) ----
    $commitAttempted = $false; $committed = $false; $headSha = $null; $stagedFiles = @(); $reasonSkipped = $null
    # git-lease telemetry (additive to the result; always present so consumers can rely on it).
    $gitLease = [ordered]@{ used = $false; acquired = $false; lease_id = $null; waited_ms = $null; reason = $null }
    if ($commitRequested) {
        $commitFiles = @(); if ($null -ne $p -and (Has $p 'commit_files')) { $commitFiles = @($p.commit_files | ForEach-Object { [string]$_ }) }
        $commitMsg = if ($null -ne $p) { [string](Prop $p 'commit_message' '') } else { '' }
        if (-not $gateOk) {
            $reasonSkipped = 'gate_failed'; Write-Diag 'commit skipped: gate failed'
        } elseif ($commitFiles.Count -lt 1) {
            $reasonSkipped = 'no_commit_files'
        } elseif ([string]::IsNullOrWhiteSpace($commitMsg)) {
            $reasonSkipped = 'no_commit_message'
        } else {
            # ---- git critical section: serialize the index-check + add + commit across instances via the
            #      res.lease 'git' lease (Module 29). ADDITIVE to the index-clean guard below. GRACEFUL: if
            #      res.lease is absent, disabled, or the lease can't be acquired within the wait, we PROCEED --
            #      git's own .git/index.lock stays the backstop, so behaviour is never worse than pre-lease. ----
            $resleaseScript = Join-Path $RepoRoot 'modules/29-resource-lease/Invoke-ResLease.ps1'
            $leaseId = $null
            if (-not $useGitLease) {
                $gitLease.reason = 'disabled'
            } elseif (-not (Test-Path -LiteralPath $resleaseScript -PathType Leaf)) {
                $gitLease.reason = 'reslease_absent'; Write-Diag 'res.lease absent; committing without a git lease (behaviour unchanged)'
            } else {
                $gitLease.used = $true
                $holder = if (-not [string]::IsNullOrWhiteSpace($gitLeaseHolder)) { $gitLeaseHolder }
                          elseif (-not [string]::IsNullOrWhiteSpace($env:LIFEORCH_INSTANCE)) { $env:LIFEORCH_INSTANCE }
                          else { "dev.ship:$PID" }
                $acqArgv = @('-Action', 'acquire', '-Resource', 'git', '-Holder', $holder, '-TtlSeconds', "$gitLeaseTtl", '-WaitSeconds', "$gitLeaseWait")
                $acqEnv = Invoke-ResLeaseAction $resolvedPwsh $resleaseScript $RepoRoot $acqArgv
                if ($null -ne $acqEnv -and (Has $acqEnv 'result') -and [bool](Prop $acqEnv.result 'acquired' $false)) {
                    $leaseId = [string](Prop $acqEnv.result 'lease_id' '')
                    $gitLease.acquired = $true; $gitLease.lease_id = $leaseId; $gitLease.waited_ms = (Prop $acqEnv.result 'waited_ms' $null)
                    Write-Diag "git lease acquired (holder=$holder lease_id=$leaseId waited_ms=$($gitLease.waited_ms))"
                } else {
                    $gitLease.reason = 'acquire_unavailable_proceeding'
                    $warnings.Add('git lease not acquired within wait; proceeding (git index.lock is the backstop)')
                    Write-Diag 'git lease NOT acquired; proceeding (index.lock backstop)'
                }
            }
            try {
                $preStaged = @((& git -C $RepoRoot diff --cached --name-only) 2>$null | Where-Object { $_.Trim().Length -gt 0 })
                $normCommit = @($commitFiles | ForEach-Object { $_.Replace('\', '/') })
                $extra = @($preStaged | Where-Object { $normCommit -notcontains $_.Replace('\', '/') })
                if (-not $allowDirtyIndex -and $extra.Count -gt 0) {
                    $reasonSkipped = "index_not_clean: unrelated staged files: $([string]::Join(', ', $extra))"
                    Write-Diag $reasonSkipped
                } else {
                    $commitAttempted = $true
                    foreach ($cf in $commitFiles) { & git -C $RepoRoot add -- $cf | Out-Null }
                    $mf = Join-Path ([System.IO.Path]::GetTempPath()) ("devship-msg-" + [Guid]::NewGuid().ToString('N') + '.txt')
                    [System.IO.File]::WriteAllText($mf, ($commitMsg -replace "`r?`n", "`r`n"), $utf8)
                    $commitOut = (& git -C $RepoRoot commit -F $mf 2>&1 | Out-String)
                    $commitRc = $LASTEXITCODE
                    Remove-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue
                    if ($commitRc -eq 0) {
                        $committed = $true
                        $headSha = ((& git -C $RepoRoot rev-parse HEAD) | Out-String).Trim()
                        $stagedFiles = @((& git -C $RepoRoot show --pretty=format: --name-only HEAD) | Where-Object { $_.Trim().Length -gt 0 })
                    } else {
                        $tail3 = (($commitOut -split "`r?`n") | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -Last 3) -join ' '
                        $reasonSkipped = "git_commit_failed(rc=$commitRc): $tail3"
                        Write-Diag $reasonSkipped
                    }
                }
            } finally {
                if ($gitLease.acquired -and -not [string]::IsNullOrWhiteSpace($leaseId)) {
                    $relArgv = @('-Action', 'release', '-Resource', 'git', '-LeaseId', $leaseId)
                    $relEnv = Invoke-ResLeaseAction $resolvedPwsh $resleaseScript $RepoRoot $relArgv
                    $relOk = ($null -ne $relEnv -and (Has $relEnv 'result') -and [bool](Prop $relEnv.result 'released' $false))
                    if (-not $relOk) { $warnings.Add('git lease release did not confirm (the lease will expire via its TTL)') }
                    Write-Diag "git lease released=$relOk"
                }
            }
        }
    }

    # ---- 5) ORPHANS (informational) ----
    $orph = [ordered]@{}
    $orphNames = @(); if ($null -ne $p -and (Has $p 'check_orphans')) { $orphNames = @($p.check_orphans | ForEach-Object { [string]$_ }) }
    foreach ($n in $orphNames) {
        $cnt = @(Get-Process -Name $n -ErrorAction SilentlyContinue).Count
        $orph[$n] = $cnt
        if ($cnt -gt 0) { $warnings.Add("orphan process present: $n x$cnt") }
    }

    $okFinal = $gateOk -and ((-not $commitRequested) -or $committed)
    if (-not $okFinal) { $exitCode = 1 }

    $result = [ordered]@{
        schema         = 'lifeorch.devship.result/0.1'
        ok             = $okFinal
        repo_root      = $RepoRoot
        sha            = [ordered]@{ checked = $shaChecked; ok = $shaOk; mismatches = $mismatches.ToArray() }
        ast            = [ordered]@{ checked = $astChecked; ok = $astOk; errors = $astErrors.ToArray() }
        tests          = [ordered]@{ ran = $testsRan; exit_code = $testsExit; pass = $testsPass; tail = $testsTail }
        commit         = [ordered]@{ requested = $commitRequested; attempted = $commitAttempted; committed = $committed; head_sha = $headSha; staged = $stagedFiles; reason_skipped = $reasonSkipped }
        git_lease      = $gitLease
        orphans        = $orph
        warnings       = $warnings.ToArray()
        error          = $null
        started_at_utc = $startedAt.ToString('o')
        duration_ms    = 0
    }
}
catch {
    $exitCode = 2
    $result = [ordered]@{
        schema         = 'lifeorch.devship.result/0.1'
        ok             = $false
        repo_root      = $RepoRoot
        error          = [ordered]@{ code = 'devship_exception'; message = "$($_.Exception.Message)"; line = $_.InvocationInfo.ScriptLineNumber }
        warnings       = $warnings.ToArray()
        started_at_utc = $startedAt.ToString('o')
        duration_ms    = 0
    }
    Write-Diag "ERROR line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
}

$sw.Stop()
$result.duration_ms = [int]$sw.Elapsed.TotalMilliseconds
[Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 12))
exit $exitCode
