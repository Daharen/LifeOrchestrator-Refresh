#requires -Version 7.0
<#
  LifeorchStagingConfirm.psm1 -- CONFIRM that an emitted ops/setup/out/staging-plan.txt is
  well-formed AND actionable, WITHOUT downloading the tens-of-GB payloads.
  (Life Orchestrator portability follow-on; FANOUT_AGENT_002, plan fo-15-27a03513, CPU lane.)

  What it does:
    * ConvertFrom-StagingPlan : PURE parser. Turns the plan text emitted by
      LifeorchSetup\New-StagingPlan into structured entries -- each single-file artifact parses
      to {id, dest (under the data-root), url, expected sha256}; multi-file/system/executable
      entries are classified too; the engines block + the data-root header are captured.
    * Invoke-LoHeadProbe      : GUARDED HTTP-HEAD reachability probe for one URL. Reports status +
      advertised size. Degrades to 'offline' on ANY network error and NEVER throws. A -MockResults
      seam feeds the judge without touching the network (the cloud gate); -Offline forces degrade;
      a 405 (HEAD not allowed) falls back to a tiny ranged GET (bytes=0-0) -- NOT a full download.
    * Confirm-StagingPlan     : orchestrates parse + per-URL probe -> a
      lifeorch.setup.staging_confirm/0.1 object: per-entry {url reachable? advertised size? sha
      present? actionable?} + a summary + blockers (TODO_CONFIRM URLs, missing sha, dead links).

  No GPU / model invocation. No tens-of-GB downloads. ASCII-only (the 5.1-ANSI gotcha in
  CURRENT_STATE -> Known failures); pwsh 7 target. Windows-only nothing here -- pure + net-guarded,
  so it all runs green in cloud pwsh 7.4.6 on Linux with mock inputs.
#>

Set-StrictMode -Version Latest

# ------------------------------------------------------------------------------------------
# self-contained small helpers (do not depend on which sibling module exports what)
# ------------------------------------------------------------------------------------------
function _ScHas($o, [string]$n) {
    if ($null -eq $o) { return $false }
    if ($o -is [System.Collections.IDictionary]) { return $o.Contains($n) }
    $ps = $o.PSObject
    if ($null -eq $ps) { return $false }
    return ($null -ne $ps.Properties[$n])
}
function _ScProp($o, [string]$n, $d = $null) {
    if (_ScHas $o $n) { $v = if ($o -is [System.Collections.IDictionary]) { $o[$n] } else { $o.$n }; if ($null -ne $v) { return $v } }
    return $d
}
function _ScLeaf([string]$p) {
    # OS-separator-agnostic basename (Windows '\' path must split on Linux too -- the cloud gate).
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    $parts = $p -split '[\\/]'
    return $parts[$parts.Count - 1]
}

# ------------------------------------------------------------------------------------------
# ConvertFrom-StagingPlan -- PURE parser of the New-StagingPlan text format.
# ------------------------------------------------------------------------------------------
function ConvertFrom-StagingPlan {
    <#
      Parse the emitted staging plan into structured entries. Returns:
        { schema, data_root, entries[], engines[], warnings[], well_formed }
      Entry kinds: 'single-file' {id,name,type,format,dest,url,url_placeholder,expected_sha256,
      has_sha256,size_mib,sidecar}; 'multi-file' {id,name,format,dest,repo,repo_placeholder};
      'system'; 'executable' {path}; 'declared-only'. The parser is tolerant of extra comment
      lines and blank lines; it keys single-file entries off the 'curl.exe ... -o "<dest>" "<url>"'
      line and attaches the '#   expected sha256:' / '#   size ~N MiB' comments around it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Text)

    $entries = New-Object System.Collections.Generic.List[object]
    $engines = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $dataRoot = $null
    $wellFormed = $true

    $curId = $null; $curName = $null; $curType = $null; $curFmt = $null
    $inEngines = $false
    $pendingSize = $null
    $lastSingle = $null   # the most recent single-file entry (to attach a following sha comment)

    $lines = $Text -split "`r?`n"
    foreach ($raw in $lines) {
        $line = $raw.TrimEnd()
        $t = $line.Trim()
        if ($t.Length -eq 0) { continue }

        # data-root header
        $mDr = [regex]::Match($t, '^#\s*Data-root:\s*(.+?)\s*$')
        if ($mDr.Success) { $dataRoot = $mDr.Groups[1].Value; continue }

        # section header: "## <id>  (<name>)  type=<type> format=<fmt>"
        $mSec = [regex]::Match($t, '^##\s+(?<id>\S+)\s*(?:\((?<name>.*?)\))?\s*(?:type=(?<type>\S+))?\s*(?:format=(?<fmt>\S+))?\s*$')
        if ($mSec.Success -and -not $t.StartsWith('## engines')) {
            $curId = $mSec.Groups['id'].Value
            $curName = if ($mSec.Groups['name'].Success) { $mSec.Groups['name'].Value } else { $null }
            $curType = if ($mSec.Groups['type'].Success) { $mSec.Groups['type'].Value } else { $null }
            $curFmt = if ($mSec.Groups['fmt'].Success) { $mSec.Groups['fmt'].Value } else { $null }
            $pendingSize = $null; $lastSingle = $null; $inEngines = $false
            continue
        }
        if ($t.StartsWith('## engines')) { $inEngines = $true; $curId = $null; $lastSingle = $null; continue }

        if ($inEngines) {
            $mEng = [regex]::Match($t, '^#\s+(?<name>[^:]+):\s+(?<path>.+?)\s*$')
            if ($mEng.Success) { $engines.Add([pscustomobject]@{ name = $mEng.Groups['name'].Value.Trim(); path = $mEng.Groups['path'].Value.Trim() }) }
            continue
        }

        # size comment "#   size ~N MiB"
        $mSize = [regex]::Match($t, '^#\s*size\s*~\s*(\d+)\s*MiB')
        if ($mSize.Success) { $pendingSize = [int]$mSize.Groups[1].Value; continue }

        # single-file curl line
        $mCurl = [regex]::Match($t, '^curl\.exe\s+.*-o\s+"(?<dest>[^"]+)"\s+"(?<url>[^"]+)"')
        if ($mCurl.Success) {
            $dest = $mCurl.Groups['dest'].Value
            $url = $mCurl.Groups['url'].Value
            $isSidecar = ($null -ne $lastSingle)   # a 2nd+ curl in the same section = mmproj/adapter sidecar
            $ph = ($url -match '^(?i)TODO_CONFIRM')
            $e = [pscustomobject]@{
                kind            = 'single-file'
                id              = $curId
                name            = $curName
                type            = $curType
                format          = $curFmt
                dest            = $dest
                leaf            = (_ScLeaf $dest)
                url             = $url
                url_placeholder = [bool]$ph
                expected_sha256 = $null
                has_sha256      = $false
                size_mib        = $pendingSize
                sidecar         = [bool]$isSidecar
            }
            $entries.Add($e)
            $lastSingle = $e
            $pendingSize = $null
            continue
        }

        # sha comment "#   expected sha256: <hex>"
        $mSha = [regex]::Match($t, '^#\s*expected\s+sha256:\s*(?<sha>[0-9a-fA-F]{16,})\s*$')
        if ($mSha.Success -and $null -ne $lastSingle) {
            $lastSingle.expected_sha256 = $mSha.Groups['sha'].Value.ToLowerInvariant()
            $lastSingle.has_sha256 = $true
            continue
        }
        if ($t -match '^#\s*\(no expected sha256 recorded\)' -and $null -ne $lastSingle) { continue }

        # multi-file "huggingface-cli download <repo> --local-dir "<dest>""
        $mHf = [regex]::Match($t, 'huggingface-cli\s+download\s+(?<repo>\S+)\s+--local-dir\s+"(?<dest>[^"]+)"')
        if ($mHf.Success) {
            $repo = $mHf.Groups['repo'].Value
            $entries.Add([pscustomobject]@{
                    kind             = 'multi-file'
                    id               = $curId
                    name             = $curName
                    format           = $curFmt
                    dest             = $mHf.Groups['dest'].Value
                    repo             = $repo
                    repo_placeholder = [bool]($repo -match '^(?i)TODO_CONFIRM')
                })
            $lastSingle = $null
            continue
        }

        # system component / executable / declared-only markers
        if ($t -match 'system component \(no download\)') { $entries.Add([pscustomobject]@{ kind = 'system'; id = $curId; name = $curName }); continue }
        $mExe = [regex]::Match($t, 'installed executable \(install separately\):\s*(?<path>.+?)\s*$')
        if ($mExe.Success) { $entries.Add([pscustomobject]@{ kind = 'executable'; id = $curId; name = $curName; path = $mExe.Groups['path'].Value }); continue }
        if ($t -match 'no path \(declared-only\)') { $entries.Add([pscustomobject]@{ kind = 'declared-only'; id = $curId; name = $curName }); continue }
    }

    if ($entries.Count -eq 0) { $wellFormed = $false; $warnings.Add('no entries parsed from the plan text') }

    return [pscustomobject]@{
        schema      = 'lifeorch.setup.staging_parse/0.1'
        data_root   = $dataRoot
        entries     = $entries.ToArray()
        engines     = $engines.ToArray()
        warnings    = $warnings.ToArray()
        well_formed = $wellFormed
    }
}

# ------------------------------------------------------------------------------------------
# Invoke-LoHeadProbe -- guarded HTTP-HEAD reachability. Degrades to 'offline'; NEVER throws.
# ------------------------------------------------------------------------------------------
function Invoke-LoHeadProbe {
    <#
      status: reachable | dead | offline | placeholder | skipped | error.
        placeholder  URL is a TODO_CONFIRM_* stub (not probed).
        reachable    HTTP status 200-399 (or a 405 HEAD that a ranged GET confirms).
        dead         HTTP status >= 400 (records the code; 401/403 noted as gated/forbidden).
        offline      any network error OR -Offline (a fresh box with no internet still 'confirms').
      -MockResults @{ '<url>' = @{ status_code = 200; content_length = 12345 } } feeds the judge
      with no network (the cloud gate).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string]$Url,
        [int]$TimeoutSec = 20,
        $MockResults,
        [switch]$Offline
    )
    $res = [ordered]@{ url = $Url; status = 'unknown'; http_status = $null; content_length = $null; final_url = $null; reason = $null }

    if ([string]::IsNullOrWhiteSpace($Url)) { $res.status = 'error'; $res.reason = 'empty url'; return [pscustomobject]$res }
    if ($Url -match '^(?i)TODO_CONFIRM') { $res.status = 'placeholder'; $res.reason = 'URL not confirmed (TODO_CONFIRM stub)'; return [pscustomobject]$res }

    # mock seam (cloud gate): resolve from the supplied table without any network
    if ($null -ne $MockResults -and (_ScHas $MockResults $Url)) {
        $m = if ($MockResults -is [System.Collections.IDictionary]) { $MockResults[$Url] } else { $MockResults.$Url }
        $code = [int](_ScProp $m 'status_code' 0)
        $res.http_status = $code
        $res.content_length = _ScProp $m 'content_length' $null
        $res.final_url = _ScProp $m 'final_url' $Url
        if ($code -ge 200 -and $code -lt 400) { $res.status = 'reachable'; $res.reason = "mock $code" }
        elseif ($code -ge 400) { $res.status = 'dead'; $res.reason = "mock HTTP $code" }
        else { $res.status = 'offline'; $res.reason = 'mock: no status' }
        return [pscustomobject]$res
    }

    if ($Offline) { $res.status = 'offline'; $res.reason = 'offline mode (no probe performed)'; return [pscustomobject]$res }

    # real guarded probe
    $client = $null
    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $true
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('lifeorch-setup-confirm/0.1')

        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, $Url)
        $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $code = [int]$resp.StatusCode
        $res.http_status = $code
        $res.final_url = if ($null -ne $resp.RequestMessage -and $null -ne $resp.RequestMessage.RequestUri) { [string]$resp.RequestMessage.RequestUri } else { $Url }
        if ($null -ne $resp.Content -and $null -ne $resp.Content.Headers.ContentLength) { $res.content_length = [long]$resp.Content.Headers.ContentLength }

        if ($code -eq 405 -or $code -eq 501) {
            # HEAD not allowed -> tiny ranged GET (NOT a full download)
            $resp.Dispose()
            $g = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Url)
            $g.Headers.Range = [System.Net.Http.Headers.RangeHeaderValue]::new(0, 0)
            $gr = $client.SendAsync($g, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $code = [int]$gr.StatusCode
            $res.http_status = $code
            if ($null -ne $gr.Content -and $null -ne $gr.Content.Headers.ContentLength) { $res.content_length = [long]$gr.Content.Headers.ContentLength }
            $gr.Dispose()
        }

        if ($code -ge 200 -and $code -lt 400) { $res.status = 'reachable'; $res.reason = "HTTP $code" }
        elseif ($code -eq 401 -or $code -eq 403) { $res.status = 'dead'; $res.reason = "HTTP $code (gated/forbidden -- may need auth/licence acceptance)" }
        else { $res.status = 'dead'; $res.reason = "HTTP $code" }
    }
    catch {
        $res.status = 'offline'
        $res.reason = "probe failed (degraded to offline): $($_.Exception.Message)"
    }
    finally { if ($null -ne $client) { $client.Dispose() } }

    return [pscustomobject]$res
}

# ------------------------------------------------------------------------------------------
# Confirm-StagingPlan -- parse + probe -> a lifeorch.setup.staging_confirm/0.1 object.
# ------------------------------------------------------------------------------------------
function Confirm-StagingPlan {
    [CmdletBinding()]
    param(
        [string]$PlanPath,
        [string]$PlanText,
        [int]$TimeoutSec = 20,
        $MockResults,
        [switch]$Offline,
        [switch]$NoProbe,
        [datetime]$NowUtc
    )
    if (-not $PSBoundParameters.ContainsKey('NowUtc')) { $NowUtc = [DateTime]::UtcNow }
    if ([string]::IsNullOrWhiteSpace($PlanText)) {
        if ([string]::IsNullOrWhiteSpace($PlanPath) -or -not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) {
            return [pscustomobject]@{
                schema = 'lifeorch.setup.staging_confirm/0.1'; ok = $false; well_formed = $false
                plan_path = $PlanPath; error = "staging plan not found: $PlanPath"
                generated_utc = $NowUtc.ToString('o'); entries = @(); summary = $null
            }
        }
        $PlanText = Get-Content -LiteralPath $PlanPath -Raw
    }

    $parsed = ConvertFrom-StagingPlan -Text $PlanText

    $probeMode = if ($NoProbe) { 'noprobe' } elseif ($null -ne $MockResults) { 'mock' } elseif ($Offline) { 'offline' } else { 'live' }

    $out = New-Object System.Collections.Generic.List[object]
    $blockers = New-Object System.Collections.Generic.List[string]
    foreach ($e in $parsed.entries) {
        $issues = New-Object System.Collections.Generic.List[string]
        $probe = $null
        $actionable = $false

        if ($e.kind -eq 'single-file') {
            if ($e.url_placeholder) { $issues.Add('url_todo_confirm') }
            if (-not $e.has_sha256) { $issues.Add('missing_sha256') }
            if ($NoProbe) { $probe = [pscustomobject]@{ url = $e.url; status = 'skipped'; http_status = $null; content_length = $null; reason = 'probe skipped' } }
            else { $probe = Invoke-LoHeadProbe -Url $e.url -TimeoutSec $TimeoutSec -MockResults $MockResults -Offline:$Offline }
            if ($probe.status -eq 'dead') { $issues.Add('url_unreachable') }
            if ($probe.status -eq 'offline') { $issues.Add('url_offline') }
            $actionable = ((-not $e.url_placeholder) -and $e.has_sha256 -and ($probe.status -eq 'reachable'))
        }
        elseif ($e.kind -eq 'multi-file') {
            if ($e.repo_placeholder) { $issues.Add('repo_todo_confirm') }
            $probeUrl = $e.repo
            if ($NoProbe -or $e.repo_placeholder) { $probe = [pscustomobject]@{ url = $probeUrl; status = $(if ($e.repo_placeholder) { 'placeholder' } else { 'skipped' }); http_status = $null; content_length = $null; reason = $null } }
            else { $probe = Invoke-LoHeadProbe -Url $probeUrl -TimeoutSec $TimeoutSec -MockResults $MockResults -Offline:$Offline }
            if ($probe.status -eq 'dead') { $issues.Add('repo_unreachable') }
            if ($probe.status -eq 'offline') { $issues.Add('repo_offline') }
            $actionable = ((-not $e.repo_placeholder) -and ($probe.status -eq 'reachable'))
        }
        else {
            # system / executable / declared-only -- informational, no download to confirm
            $probe = [pscustomobject]@{ url = $null; status = 'n/a'; http_status = $null; content_length = $null; reason = "$($e.kind) (no download)" }
            $actionable = $true
        }

        $out.Add([pscustomobject]@{
                id          = $e.id
                name        = $e.name
                kind        = $e.kind
                dest        = (_ScProp $e 'dest')
                url         = $(if ($e.kind -eq 'multi-file') { (_ScProp $e 'repo') } else { (_ScProp $e 'url') })
                expected_sha256 = (_ScProp $e 'expected_sha256')
                has_sha256  = [bool](_ScProp $e 'has_sha256' $false)
                size_mib    = (_ScProp $e 'size_mib')
                sidecar     = [bool](_ScProp $e 'sidecar' $false)
                probe       = $probe
                actionable  = [bool]$actionable
                issues      = $issues.ToArray()
            })
    }

    $arr = $out.ToArray()
    $single = @($arr | Where-Object { $_.kind -eq 'single-file' })
    $multi = @($arr | Where-Object { $_.kind -eq 'multi-file' })
    $deadN = @($arr | Where-Object { $_.probe.status -eq 'dead' }).Count
    $offlineN = @($arr | Where-Object { $_.probe.status -eq 'offline' }).Count
    $reachN = @($arr | Where-Object { $_.probe.status -eq 'reachable' }).Count
    $phN = @($single | Where-Object { $_.issues -contains 'url_todo_confirm' }).Count + @($multi | Where-Object { $_.issues -contains 'repo_todo_confirm' }).Count
    $missShaN = @($single | Where-Object { -not $_.has_sha256 }).Count
    $actionableN = @($arr | Where-Object { $_.kind -in @('single-file', 'multi-file') -and $_.actionable }).Count

    foreach ($x in $arr) {
        if ($x.issues -contains 'url_todo_confirm' -or $x.issues -contains 'repo_todo_confirm') { $blockers.Add("$($x.id): confirm URL before download") }
        if ($x.issues -contains 'missing_sha256') { $blockers.Add("$($x.id): no expected sha256 (integrity uncheckable)") }
        if ($x.issues -contains 'url_unreachable' -or $x.issues -contains 'repo_unreachable') { $blockers.Add("$($x.id): URL unreachable ($($x.probe.reason))") }
    }

    # ok = the plan parsed AND no confirmed-dead real URL. Placeholders + offline do NOT fail ok
    # (a TODO_CONFIRM url is an expected pre-download step; offline is a degraded-but-valid confirm).
    $ok = ($parsed.well_formed -and $deadN -eq 0)

    return [pscustomobject]@{
        schema         = 'lifeorch.setup.staging_confirm/0.1'
        generated_utc  = $NowUtc.ToString('o')
        plan_path      = $PlanPath
        plan_data_root = $parsed.data_root
        probe_mode     = $probeMode
        well_formed    = $parsed.well_formed
        ok             = $ok
        summary        = [pscustomobject]@{
            entries          = $arr.Count
            single_file      = $single.Count
            multi_file       = $multi.Count
            system           = @($arr | Where-Object { $_.kind -eq 'system' }).Count
            executable       = @($arr | Where-Object { $_.kind -eq 'executable' }).Count
            declared_only    = @($arr | Where-Object { $_.kind -eq 'declared-only' }).Count
            url_reachable    = $reachN
            url_dead         = $deadN
            url_offline      = $offlineN
            url_placeholder  = $phN
            missing_sha256   = $missShaN
            actionable_now   = $actionableN
            engines          = @($parsed.engines).Count
        }
        entries        = $arr
        engines        = $parsed.engines
        blockers       = $blockers.ToArray()
        warnings       = $parsed.warnings
    }
}

Export-ModuleMember -Function @(
    'ConvertFrom-StagingPlan',
    'Invoke-LoHeadProbe',
    'Confirm-StagingPlan'
)
