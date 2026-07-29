<#
    VerificationConsole.psm1 - driver core for the Verification Console (Widget 03).

    The human-AUDIT surface for the offload / verify-cost spine (DECISION_LOG D-0050). Claude writes a
    VERIFICATION PACKET (lifeorch.verification.packet/0.1) describing items to check; the console loads it,
    lets Nicholas RUN each 'run_module' item locally through the Module 1 generic wrapper
    (modules/01-skill-bootstrap/Invoke-Skill.ps1) and SEE inputs / outputs / artifacts, work through each
    item's CHECKLIST, and EXPORT a VERIFICATION RESULT (lifeorch.verification.result/0.1) that Claude reads
    back. A 'human_action' item carries a task for Nicholas to do by hand (the handed-subtask channel).

    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate (against
    tests/mock-invoke-skill.ps1 + a fixture packet) and on Windows. The UI (Show-VerificationConsole.ps1)
    is a thin shell over these functions. It reimplements nothing: a module is RUN via the canonical
    Module 1 wrapper and its lifeorch.skill.invocation_report/0.1 (nesting the skill's result envelope) is
    parsed, never re-derived. NOT a review-queue producer.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:VerificationWidgetRoot = $PSScriptRoot
$script:PacketSchema = 'lifeorch.verification.packet/0.1'
$script:ResultSchema = 'lifeorch.verification.result/0.1'

# Process names reaped by the run-teardown orphan sweep. Governor Phase 2 (model.gateway #7) leaves a
# DETACHED llama-server that the child-tree kill misses; 'python' covers a detached model-worker. Both are
# gated by a before/after PID-set diff + a scope check (below), so a legitimately-resident warm server owned
# by ANOTHER run/holder is never killed.
$script:OrphanSweepNames = @('llama-server', 'python')

# ============================================================================
#  small helpers (shared shape with ModuleLauncher.psm1)
# ============================================================================

function Test-HasProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject -and $null -ne $Object.PSObject.Properties[$Name])
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    # Handle both JSON-sourced pscustomobjects AND internally-built [ordered]/hashtable dictionaries.
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    if (Test-HasProp $Object $Name) { return $Object.$Name }
    return $Default
}

function Limit-Text {
    param($Text, [int]$Max = 500)
    if ($null -eq $Text) { return '' }
    $s = [string]$Text
    if ($s.Length -le $Max) { return $s }
    return $s.Substring(0, $Max) + ' ...[truncated ' + ($s.Length - $Max) + ' chars]'
}

function ConvertTo-CompactJson {
    param($Value, [int]$Depth = 8)
    if ($null -eq $Value) { return '(none)' }
    try { return ($Value | ConvertTo-Json -Compress -Depth $Depth) }
    catch { return [string]$Value }
}

# Extract the first complete, balanced top-level JSON object from arbitrary text
# (tolerant of any leading/trailing diagnostic noise on stdout).
function ConvertFrom-EnvelopeJson {
    param([string]$Text, [ref]$ErrorRef)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = 'empty stdout' }
        return $null
    }
    try { return ($Text | ConvertFrom-Json -ErrorAction Stop) } catch { }

    $ob = [char]123; $cb = [char]125; $qt = [char]34; $bs = [char]92
    $start = $Text.IndexOf($ob)
    if ($start -lt 0) {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = 'no JSON object found in stdout' }
        return $null
    }
    $depth = 0; $inStr = $false; $esc = $false; $end = -1
    for ($i = $start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($c -eq $bs) { $esc = $true }
            elseif ($c -eq $qt) { $inStr = $false }
        }
        else {
            if ($c -eq $qt) { $inStr = $true }
            elseif ($c -eq $ob) { $depth++ }
            elseif ($c -eq $cb) { $depth--; if ($depth -eq 0) { $end = $i; break } }
        }
    }
    if ($end -lt 0) {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = 'unbalanced JSON object in stdout' }
        return $null
    }
    $fragment = $Text.Substring($start, $end - $start + 1)
    try { return ($fragment | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        if ($null -ne $ErrorRef) { $ErrorRef.Value = "JSON parse failed: $($_.Exception.Message)" }
        return $null
    }
}

# ============================================================================
#  path resolution
# ============================================================================

function Resolve-VerificationPaths {
    [CmdletBinding()]
    param([string]$InvokeSkillPath, [string]$PwshPath, [string]$WidgetRoot)

    if (-not $WidgetRoot) { $WidgetRoot = $script:VerificationWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    $repoRoot = $null
    $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
    if ($rp) { $repoRoot = $rp.Path } else { $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }

    if (-not $InvokeSkillPath) {
        $InvokeSkillPath = Join-Path $repoRoot (Join-Path 'modules' (Join-Path '01-skill-bootstrap' 'Invoke-Skill.ps1'))
    }
    if (-not $PwshPath) {
        # Self-referential pwsh path via $PSHOME dodges the dotnet-tool 'dotnet.exe' locator gotcha.
        $cand = Join-Path $PSHOME 'pwsh.exe'
        if (-not (Test-Path -LiteralPath $cand)) { $cand = Join-Path $PSHOME 'pwsh' }  # non-Windows (cloud gate)
        $PwshPath = $cand
    }
    return [pscustomobject]@{
        WidgetRoot      = $WidgetRoot
        RepoRoot        = $repoRoot
        InvokeSkillPath = $InvokeSkillPath
        PwshPath        = $PwshPath
    }
}

# ============================================================================
#  packet discovery (kill the GUID hunt -- D-0063)
# ============================================================================
# The fan-out orchestrator (#30) writes each verification packet to
# modules/30-orchestrate-fanout/runtime/artifacts/<invocation_id>/verification-packet.json -- a pile of
# GUID-named folders. Opening the right one via a raw file dialog is the D-0063 pain point. These CORE
# helpers (WinForms-free, disk-only, so the cloud gate tests them) let the shell offer 'Open latest packet'
# and a 'Recent packets' picker instead: scan that dir, parse each packet's plan_id/title/created_at/item
# count, and return them newest-first by file mtime.

function Get-PlanIdFromPacket {
    <#
        Derive the fan-out PLAN id for a packet. Emitted packets carry no explicit plan_id field; the plan id
        is embedded in packet_id as 'vp-<plan_id>-i<N>' (e.g. vp-fo-9-d4139304-i9 -> fo-9-d4139304). An
        explicit 'plan_id' field (future packets) wins if present. Returns '' when nothing is derivable.
    #>
    [CmdletBinding()]
    param($Packet, [string]$PacketId)
    if ($null -ne $Packet) {
        $explicit = [string](Get-Prop $Packet 'plan_id' '')
        if ($explicit) { return $explicit }
        if (-not $PacketId) { $PacketId = [string](Get-Prop $Packet 'packet_id' '') }
    }
    if ([string]::IsNullOrWhiteSpace($PacketId)) { return '' }
    $m = [regex]::Match($PacketId, '^vp-(?<plan>.+?)-i\d+$')
    if ($m.Success) { return $m.Groups['plan'].Value }
    if ($PacketId -like 'vp-*') { return $PacketId.Substring(3) }
    return $PacketId
}

function Get-DefaultPacketsDir {
    <# The fan-out artifacts dir (where orchestrate.fanout #30 writes verification-packet.json), repo-relative. #>
    [CmdletBinding()]
    param([string]$RepoRoot)
    if (-not $RepoRoot) { $RepoRoot = (Resolve-VerificationPaths).RepoRoot }
    # [IO.Path]::Combine is a pure string join (no PSDrive resolution) so a foreign-platform RepoRoot in a
    # cloud-gate test does not throw "Cannot find drive 'C'".
    return [System.IO.Path]::Combine($RepoRoot, 'modules', '30-orchestrate-fanout', 'runtime', 'artifacts')
}

function Get-RecentPackets {
    <#
        Scan -PacketsDir (default: the fan-out artifacts dir) for */verification-packet.json and return a
        normalized, NEWEST-FIRST (by file mtime) list so the console can offer 'Open latest' + a 'Recent
        packets' picker WITHOUT the user hunting through GUID-named folders. Each entry:
          { path, dir, invocation_id, mtime_utc, mtime_ms, ok, error, schema, packet_id, plan_id, title,
            created_at, created_by, report_back, item_count }
        A malformed packet is INCLUDED with ok=false + a short error (never throws) so the picker surfaces it
        rather than silently dropping it. Returns @() when the dir is absent/empty. WinForms-free + disk-only,
        so it is unit-tested off-machine against a temp fixture tree.
    #>
    [CmdletBinding()]
    param([string]$PacketsDir, [string]$RepoRoot, [int]$Max = 20)
    if (-not $PacketsDir) { $PacketsDir = Get-DefaultPacketsDir -RepoRoot $RepoRoot }
    if ([string]::IsNullOrWhiteSpace($PacketsDir) -or -not (Test-Path -LiteralPath $PacketsDir -PathType Container)) {
        return @()   # callers wrap in @(...) so an empty result is a 0-length array (no StrictMode .Count trip)
    }
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-ChildItem -LiteralPath $PacketsDir -Directory -ErrorAction SilentlyContinue)) {
        $pf = Join-Path $d.FullName 'verification-packet.json'
        if (Test-Path -LiteralPath $pf -PathType Leaf) {
            $fi = Get-Item -LiteralPath $pf -ErrorAction SilentlyContinue
            if ($null -ne $fi) { $files.Add($fi) }
        }
    }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($fi in ($files | Sort-Object -Property LastWriteTimeUtc -Descending)) {
        $dir = Split-Path -Parent $fi.FullName
        $invId = Split-Path -Leaf $dir
        $ok = $false; $errTxt = ''; $obj = $null
        try { $obj = ([System.IO.File]::ReadAllText($fi.FullName)) | ConvertFrom-Json -ErrorAction Stop; $ok = $true }
        catch { $errTxt = 'unreadable packet: ' + $_.Exception.Message }
        $schema = ''; $pkid = ''; $title = ''; $createdAt = ''; $createdBy = ''; $reportBack = ''; $count = 0; $planId = ''
        if ($ok -and $null -ne $obj) {
            $schema     = [string](Get-Prop $obj 'schema' '')
            $pkid       = [string](Get-Prop $obj 'packet_id' '')
            $title      = [string](Get-Prop $obj 'title' '')
            $createdAt  = [string](Get-Prop $obj 'created_at_utc' (Get-Prop $obj 'created_at' ''))
            $createdBy  = [string](Get-Prop $obj 'created_by' '')
            $reportBack = [string](Get-Prop $obj 'report_back' '')
            $rawItems   = Get-Prop $obj 'items'
            $count      = if ($null -eq $rawItems) { 0 } else { @($rawItems).Count }
            $planId     = Get-PlanIdFromPacket -Packet $obj
        }
        $entries.Add([pscustomobject]@{
                path          = $fi.FullName
                dir           = $dir
                invocation_id = $invId
                mtime_utc     = $fi.LastWriteTimeUtc
                mtime_ms      = ([System.DateTimeOffset]::new($fi.LastWriteTimeUtc)).ToUnixTimeMilliseconds()
                ok            = $ok
                error         = $errTxt
                schema        = $schema
                packet_id     = $pkid
                plan_id       = $planId
                title         = $title
                created_at    = $createdAt
                created_by    = $createdBy
                report_back   = $reportBack
                item_count    = $count
            })
        if ($entries.Count -ge $Max) { break }
    }
    return $entries.ToArray()   # callers wrap in @(...); a 0/1-length result stays correct after @()
}

function Format-RecentPacketLine {
    <# One display line for the 'Recent packets' picker: plan_id + title + item-count + created/mtime. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)
    if (-not [bool](Get-Prop $Entry 'ok' $true)) {
        return ('[unreadable]  ' + [string](Get-Prop $Entry 'invocation_id') + '  -  ' + [string](Get-Prop $Entry 'error'))
    }
    $plan = [string](Get-Prop $Entry 'plan_id'); if (-not $plan) { $plan = '(no plan id)' }
    $title = [string](Get-Prop $Entry 'title'); if (-not $title) { $title = '(untitled)' }
    $count = [string](Get-Prop $Entry 'item_count')
    $when = [string](Get-Prop $Entry 'created_at')
    if (-not $when) {
        $mt = Get-Prop $Entry 'mtime_utc'
        if ($mt -is [datetime]) { $when = $mt.ToString('yyyy-MM-dd HH:mm') + 'Z' }
    }
    else {
        try { $when = ([datetime]$when).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + 'Z' } catch { }
    }
    $plural = if ($count -eq '1') { '' } else { 's' }
    return ($plan.PadRight(18) + '  ' + $title + '   [' + $count + ' item' + $plural + ']   ' + $when)
}

# ============================================================================
#  packet import + validation
# ============================================================================

function ConvertTo-NormalizedChecklist {
    param($Raw)
    $out = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($c in @($Raw)) {
        if ($null -eq $c) { continue }
        $n++
        if ($c -is [string]) {
            $out.Add([pscustomobject]@{ id = ('c' + $n); text = [string]$c })
        }
        else {
            $cid = [string](Get-Prop $c 'id' ('c' + $n))
            if (-not $cid) { $cid = 'c' + $n }
            $out.Add([pscustomobject]@{ id = $cid; text = [string](Get-Prop $c 'text' '') })
        }
    }
    return $out.ToArray()
}

function Import-VerificationPacket {
    <#
        Read a verification packet (from -Path or -Json), validate it, and return a normalized object:
          { ok, error, path, schema, packet_id, title, intro, created_by, report_back, items[], item_count }
        Each normalized item:
          { index, id, kind, title, skill_id, skill_dir, inputs_json, expected, action_text, checklist[], valid, error }
        A malformed packet returns ok=false + error (never throws on content problems); a malformed ITEM is
        listed with valid=false so the console surfaces it rather than hiding it.
    #>
    [CmdletBinding()]
    param([string]$Path, [string]$Json)

    $raw = $Json
    if (-not $raw) {
        if (-not $Path) { return [pscustomobject]@{ ok = $false; error = 'no packet path or json supplied'; items = @(); item_count = 0 } }
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return [pscustomobject]@{ ok = $false; error = "packet file not found: $Path"; path = $Path; items = @(); item_count = 0 }
        }
        try { $raw = [System.IO.File]::ReadAllText($Path) } catch { return [pscustomobject]@{ ok = $false; error = "cannot read packet: $($_.Exception.Message)"; path = $Path; items = @(); item_count = 0 } }
    }

    $obj = $null
    try { $obj = $raw | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ ok = $false; error = "packet is not valid JSON: $($_.Exception.Message)"; path = $Path; items = @(); item_count = 0 } }

    $schema = [string](Get-Prop $obj 'schema' '')
    $rawItems = @(Get-Prop $obj 'items')
    $warn = New-Object System.Collections.Generic.List[string]
    if ($schema -and $schema -ne $script:PacketSchema) { $warn.Add("unexpected schema '$schema' (expected $($script:PacketSchema))") }

    $items = New-Object System.Collections.Generic.List[object]
    $idx = 0
    foreach ($it in $rawItems) {
        $idx++
        $iid = [string](Get-Prop $it 'id' ('item-' + $idx))
        if (-not $iid) { $iid = 'item-' + $idx }
        $kind = ([string](Get-Prop $it 'kind' 'run_module')).ToLowerInvariant().Trim()
        $skillId = [string](Get-Prop $it 'skill_id' '')
        $skillDir = [string](Get-Prop $it 'skill_dir' '')
        $inputsJson = Get-Prop $it 'inputs_json'
        if ($null -ne $inputsJson -and -not ($inputsJson -is [string])) { $inputsJson = ($inputsJson | ConvertTo-Json -Compress -Depth 12) }
        if ([string]::IsNullOrWhiteSpace([string]$inputsJson)) { $inputsJson = '{}' }
        $expected = [string](Get-Prop $it 'expected' '')
        $actionText = [string](Get-Prop $it 'action_text' '')
        $checklist = ConvertTo-NormalizedChecklist (Get-Prop $it 'checklist')

        $valid = $true; $ierr = ''
        if ($kind -ne 'run_module' -and $kind -ne 'human_action') { $valid = $false; $ierr = "unknown kind '$kind' (expected run_module|human_action)" }
        elseif ($kind -eq 'run_module' -and [string]::IsNullOrWhiteSpace($skillDir)) { $valid = $false; $ierr = 'run_module item is missing skill_dir' }

        $items.Add([pscustomobject]@{
                index       = $idx
                id          = $iid
                kind        = $kind
                title       = [string](Get-Prop $it 'title' $iid)
                skill_id    = $skillId
                skill_dir   = $skillDir
                inputs_json = [string]$inputsJson
                expected    = $expected
                action_text = $actionText
                checklist   = $checklist
                valid       = $valid
                error       = $ierr
            })
    }

    $ok = ($items.Count -gt 0)
    $err = if ($ok) { '' } else { 'packet has no items' }
    $packetId = [string](Get-Prop $obj 'packet_id' '')
    return [pscustomobject]@{
        ok          = $ok
        error       = $err
        path        = $Path
        packet_dir  = $(if ($Path) { Split-Path -Parent $Path } else { '' })
        schema      = $schema
        packet_id   = $packetId
        plan_id     = (Get-PlanIdFromPacket -Packet $obj -PacketId $packetId)
        title       = [string](Get-Prop $obj 'title' '')
        intro       = [string](Get-Prop $obj 'intro' '')
        created_by  = [string](Get-Prop $obj 'created_by' '')
        created_at  = [string](Get-Prop $obj 'created_at_utc' (Get-Prop $obj 'created_at' ''))
        report_back = ([string](Get-Prop $obj 'report_back' 'on_all')).ToLowerInvariant()
        warnings    = $warn.ToArray()
        items       = $items.ToArray()
        item_count  = $items.Count
    }
}

function Format-PacketSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Packet)
    $sb = [System.Text.StringBuilder]::new()
    function _addp([string]$line = '') { [void]$sb.AppendLine($line) }
    if (-not [bool](Get-Prop $Packet 'ok' $false)) {
        _addp 'PACKET NOT LOADED'
        _addp ('  ' + [string](Get-Prop $Packet 'error'))
        return $sb.ToString()
    }
    _addp ('PACKET: ' + [string](Get-Prop $Packet 'title'))
    $plan = [string](Get-Prop $Packet 'plan_id')
    if (-not $plan) { $plan = Get-PlanIdFromPacket -Packet $Packet }
    _addp ('plan: ' + $(if ($plan) { $plan } else { '(none)' }) +
        '   packet_id: ' + [string](Get-Prop $Packet 'packet_id') +
        '   report_back: ' + [string](Get-Prop $Packet 'report_back'))
    _addp ('by: ' + [string](Get-Prop $Packet 'created_by') +
        '   items: ' + [string](Get-Prop $Packet 'item_count') +
        $(if ([string](Get-Prop $Packet 'created_at')) { '   created: ' + [string](Get-Prop $Packet 'created_at') } else { '' }))
    $src = [string](Get-Prop $Packet 'path')
    if ($src) { _addp ('source: ' + $src) }
    $intro = [string](Get-Prop $Packet 'intro')
    if ($intro) { _addp ''; foreach ($ln in ($intro -split "`n")) { _addp ('  ' + $ln.TrimEnd()) } }
    $w = @(Get-Prop $Packet 'warnings')
    if ($w.Count -gt 0) { _addp ''; _addp 'WARNINGS:'; foreach ($x in $w) { _addp ('  - ' + [string]$x) } }
    return $sb.ToString()
}

function Format-ItemListLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item)
    $tag = if ([string](Get-Prop $Item 'kind') -eq 'human_action') { '[human]' } else { '[run]  ' }
    $flag = if ([bool](Get-Prop $Item 'valid' $true)) { '' } else { ' !' }
    return ($tag + ' ' + [string](Get-Prop $Item 'id') + '  -  ' + [string](Get-Prop $Item 'title') + $flag)
}

function Get-ReferencedPaths {
    <#
        Best-effort extract repo-relative / file-looking path tokens from free text (a human_action's
        action_text or a run item's expected text), so the console can offer an 'Open' affordance for the
        artifacts, packs, and docs an item references. Pure string work; existence is tested only when a
        -RepoRoot (or an absolute token) lets us resolve it, so it is unit-tested off-machine. Returns an
        array of { raw, path, exists, is_dir, label }, de-duplicated (case-insensitive), capped at -Max.
    #>
    [CmdletBinding()]
    param([string]$Text, [string]$RepoRoot, [int]$Max = 12)
    $out = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Text)) { return $out.ToArray() }

    $topDirs = 'modules|widgets|core-docs|ops|tests|runtime|examples'
    $exts = 'json|jsonl|md|ps1|psm1|psd1|txt|bat|csv|log'
    # (a) tokens that start at a known repo top-level dir and continue with path segments;
    # (b) tokens anywhere that end in a known file extension (segments may include dots, e.g. *.answer.md).
    $patterns = @(
        ('(?<![\w./\\])(?:' + $topDirs + ')(?:[\\/][\w.\-]+)+'),
        ('(?<![\w./\\])[\w.\-]+(?:[\\/][\w.\-]+)*\.(?:' + $exts + ')')
    )
    $seen = @{}
    foreach ($pat in $patterns) {
        foreach ($m in [regex]::Matches($Text, $pat)) {
            $raw = ([string]$m.Value).Trim().TrimEnd('.', ',', ')', ';', ':')
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $key = $raw.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $resolved = $raw
            if (-not [System.IO.Path]::IsPathRooted($raw) -and $RepoRoot) {
                $resolved = [System.IO.Path]::Combine($RepoRoot, ($raw -replace '/', [System.IO.Path]::DirectorySeparatorChar))
            }
            $exists = $false; $isDir = $false
            if ($RepoRoot -or [System.IO.Path]::IsPathRooted($raw)) {
                try { if (Test-Path -LiteralPath $resolved) { $exists = $true; $isDir = (Test-Path -LiteralPath $resolved -PathType Container) } } catch { }
            }
            $out.Add([pscustomobject]@{ raw = $raw; path = $resolved; exists = $exists; is_dir = $isDir; label = $raw })
            if ($out.Count -ge $Max) { break }
        }
        if ($out.Count -ge $Max) { break }
    }
    return $out.ToArray()
}

function Get-ItemActionModel {
    <#
        Decide, from an item's kind + validity, what the UI should do with it: whether the 'Run item' button
        is live (can_run), a plain-language reason, the hand-action text (human_action), a plain-language
        fix_hint for an INVALID item (replacing the cryptic '[INVALID: ...]'), and any referenced
        file/artifact/module paths to offer an 'Open' affordance for. ALL the enable/disable + plain-language
        logic lives HERE (WinForms-free) so it is unit-tested; the shell only reads these fields.
        Returns: { kind, can_run, invalid, reason, fix_hint, action_text, open_paths[] }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item, [string]$RepoRoot)
    $kind = ([string](Get-Prop $Item 'kind')).ToLowerInvariant()
    $valid = [bool](Get-Prop $Item 'valid' $true)
    $err = [string](Get-Prop $Item 'error')
    $actionText = [string](Get-Prop $Item 'action_text')
    $expected = [string](Get-Prop $Item 'expected')
    $skillDir = [string](Get-Prop $Item 'skill_dir')

    $canRun = $false; $invalid = $false; $reason = ''; $fix = ''

    if (-not $valid) {
        $invalid = $true
        if ($err -match 'skill_dir') {
            $reason = 'This item is marked as a module to run, but the packet did not say which module to run.'
            $fix = 'The module path (skill_dir) is missing. Ask Claude to re-issue the packet with the module''s skill_dir, or complete it by hand and record the verdict below.'
        }
        elseif ($err -match 'kind') {
            $reason = ('This item has an unrecognised kind (' + [string](Get-Prop $Item 'kind') + ').')
            $fix = 'Expected a module to run (run_module) or a hand action (human_action). Ask Claude to re-issue the packet.'
        }
        else {
            $reason = 'This item cannot be run as written.'
            $fix = $(if ($err) { $err } else { 'Ask Claude to re-issue the packet.' })
        }
    }
    elseif ($kind -eq 'human_action') {
        $reason = 'Hand task -- there is nothing to run here. Do it, then record the verdict below.'
    }
    elseif ($kind -eq 'run_module') {
        $canRun = $true
        $reason = 'Runs this module locally through the Module 1 wrapper.'
    }
    else {
        $reason = 'Unknown item kind.'
    }

    $paths = New-Object System.Collections.Generic.List[object]
    # a runnable module -> offer its module folder; then any files/artifacts named in the action/expected text.
    if ($kind -eq 'run_module' -and $skillDir) {
        $resolved = Resolve-ItemSkillDir -Item $Item -RepoRoot $RepoRoot
        $exists = $false; try { if ($resolved) { $exists = (Test-Path -LiteralPath $resolved) } } catch { }
        $paths.Add([pscustomobject]@{ raw = $skillDir; path = $resolved; exists = $exists; is_dir = $true; label = ('module folder: ' + $skillDir) })
    }
    foreach ($p in @(Get-ReferencedPaths -Text (($actionText + "`n" + $expected)) -RepoRoot $RepoRoot)) { $paths.Add($p) }

    return [pscustomobject]@{
        kind        = $kind
        can_run     = $canRun
        invalid     = $invalid
        reason      = $reason
        fix_hint    = $fix
        action_text = $actionText
        open_paths  = $paths.ToArray()
    }
}

function Format-ItemDetail {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item, [string]$RepoRoot)
    $sb = [System.Text.StringBuilder]::new()
    function _addi([string]$line = '') { [void]$sb.AppendLine($line) }
    $kind = [string](Get-Prop $Item 'kind')
    $am = Get-ItemActionModel -Item $Item -RepoRoot $RepoRoot
    _addi ([string](Get-Prop $Item 'id') + '   -   ' + [string](Get-Prop $Item 'title'))
    _addi ('kind: ' + $kind)
    if ([bool]$am.invalid) {
        _addi ''
        _addi 'CANNOT RUN:'
        _addi ('  ' + [string]$am.reason)
        if ([string]$am.fix_hint) { foreach ($ln in (([string]$am.fix_hint) -split "`n")) { _addi ('  ' + $ln.TrimEnd()) } }
    }
    _addi ''
    if ($kind -eq 'human_action') {
        _addi 'ACTION (do this by hand -- nothing to run):'
        foreach ($ln in (([string](Get-Prop $Item 'action_text')) -split "`n")) { _addi ('  ' + $ln.TrimEnd()) }
    }
    elseif ($kind -eq 'run_module') {
        _addi ('MODULE: ' + [string](Get-Prop $Item 'skill_id') + '   (' + [string](Get-Prop $Item 'skill_dir') + ')')
        _addi ''
        _addi 'INPUTS (JSON passed as -InputsJson):'
        _addi ('  ' + [string](Get-Prop $Item 'inputs_json'))
        _addi ''
        _addi 'OUTPUT LOCATION:'
        _addi '  After Run item, the run pane shows the produced artifacts + the artifact folder path'
        _addi '  (wrapper.stdout.txt / wrapper.stderr.txt live there too) so you can open the outputs.'
    }
    else {
        # unknown / invalid kind: still surface whatever the item carries.
        $at = [string](Get-Prop $Item 'action_text')
        if ($at) { _addi 'ACTION:'; foreach ($ln in ($at -split "`n")) { _addi ('  ' + $ln.TrimEnd()) } }
    }
    $exp = [string](Get-Prop $Item 'expected')
    if ($exp) {
        _addi ''
        _addi 'EXPECTED:'
        foreach ($ln in ($exp -split "`n")) { _addi ('  ' + $ln.TrimEnd()) }
    }
    $op = @($am.open_paths)
    if ($op.Count -gt 0) {
        _addi ''
        _addi ('REFERENCED FILES / FOLDERS (' + $op.Count + ') -- select one below and press Open:')
        foreach ($p in $op) {
            $mark = if ([bool](Get-Prop $p 'exists' $false)) { '' } else { '   (not found on disk)' }
            _addi ('  - ' + [string](Get-Prop $p 'label') + $mark)
        }
    }
    $cl = @(Get-Prop $Item 'checklist')
    _addi ''
    _addi ('CHECKLIST (' + $cl.Count + '):')
    if ($cl.Count -eq 0) { _addi '  (none)' }
    foreach ($c in $cl) { _addi ('  [ ] ' + [string](Get-Prop $c 'id') + ': ' + [string](Get-Prop $c 'text')) }
    return $sb.ToString()
}

function Resolve-ItemSkillDir {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Item, [string]$RepoRoot)
    $sd = [string](Get-Prop $Item 'skill_dir')
    if ([string]::IsNullOrWhiteSpace($sd)) { return $sd }
    if ([System.IO.Path]::IsPathRooted($sd)) { return $sd }
    if (-not $RepoRoot) { $RepoRoot = (Resolve-VerificationPaths).RepoRoot }
    # [IO.Path]::Combine is a pure string join (no PSDrive resolution), so a foreign-platform RepoRoot
    # in a test does not throw "Cannot find drive 'C'"; on Windows it combines normally.
    return [System.IO.Path]::Combine($RepoRoot, $sd)
}

# ============================================================================
#  run-teardown orphan sweep (reap a DETACHED llama-server the child-tree kill misses)
# ============================================================================
# Governor Phase 2 (model.gateway #7) launches the warm/persistent llama-server DETACHED via
# Win32_Process.Create, parenting it OUTSIDE this run's process tree, so it SURVIVES Process.Kill($true).
# The sweep reaps -- BY NAME -- only a server THIS run started and the tree-kill missed: the set difference
# between a snapshot taken at run start (Start-SkillProcess) and the processes alive at teardown. A PID that
# was alive BEFORE the run (a resident warm server owned by another run/holder) is never in the candidate
# set, so it is never killed. For names other than llama-server (e.g. a python model-worker) an additional
# command-line scope check is required before killing, so an unrelated same-named process that merely
# started during the run window is left alone. On the cloud gate (no llama-server) both sets are empty and
# the sweep is a no-op.

function Get-NamedProcessMap {
    # A plain array of { id, name } for every live process whose name matches one of $Names.
    [CmdletBinding()]
    param([string[]]$Names)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($n in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            try { $out.Add([pscustomobject]@{ id = [int]$p.Id; name = [string]$n }) } catch { }
        }
    }
    return $out.ToArray()
}

function Get-NamedProcessIdSet {
    # Snapshot of currently-live PIDs for $Names as a hashtable (pid -> $true) for O(1) membership tests.
    [CmdletBinding()]
    param([string[]]$Names)
    $set = @{}
    foreach ($p in @(Get-NamedProcessMap -Names $Names)) { $set[[int]$p.id] = $true }
    return $set
}

function Get-ProcessCommandLine {
    # Best-effort command line for a pid (Windows CIM / Linux /proc); '' when unreadable.
    [CmdletBinding()]
    param([int]$ProcId)
    if ($ProcId -le 0) { return '' }
    try {
        if ($IsWindows) {
            $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcId" -ErrorAction SilentlyContinue
            if ($null -ne $ci) { return [string]$ci.CommandLine }
        }
        else {
            $cl = "/proc/$ProcId/cmdline"
            if (Test-Path -LiteralPath $cl) { return (([System.IO.File]::ReadAllText($cl)) -replace "`0", ' ') }
        }
    }
    catch { }
    return ''
}

function Test-OrphanInScope {
    # Is a NEW-since-run-start process OURS to reap? llama-server is a dedicated model-server binary, so any
    # instance that appeared during our (GPU-leased) run is ours. Any OTHER name must prove ownership via a
    # command-line match against a run-scope marker (the repo root / this run's module dir); if it cannot,
    # we refuse to kill it -- an unrelated same-named process is never touched.
    [CmdletBinding()]
    param([int]$ProcId, [string]$Name, [string[]]$ScopeMarkers)
    if ([string]$Name -like 'llama-server*') { return $true }
    $markers = @($ScopeMarkers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($markers.Count -eq 0) { return $false }
    $cmd = Get-ProcessCommandLine -ProcId $ProcId
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
    $lc = $cmd.ToLowerInvariant()
    foreach ($mk in $markers) { if ($lc.Contains(([string]$mk).ToLowerInvariant())) { return $true } }
    return $false
}

function Stop-ProcessHard {
    # Kill a pid and CONFIRM it is gone (Process.Kill can return before the OS reaps it). Bounded.
    [CmdletBinding()]
    param([int]$ProcId, [int]$ConfirmMs = 2000)
    if ($ProcId -le 0) { return $true }
    try { $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue; if ($null -ne $p) { $p.Kill($true) } } catch { }
    if ($IsWindows) { try { & taskkill.exe /PID $ProcId /T /F 2>$null | Out-Null } catch { } }
    $deadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max(200, $ConfirmMs))
    while ([datetime]::UtcNow -lt $deadline) {
        $still = $null; try { $still = Get-Process -Id $ProcId -ErrorAction SilentlyContinue } catch { $still = $null }
        if ($null -eq $still) { return $true }
        try { Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue } catch { }
        Start-Sleep -Milliseconds 100
    }
    $final = $null; try { $final = Get-Process -Id $ProcId -ErrorAction SilentlyContinue } catch { $final = $null }
    return ($null -eq $final)
}

function Invoke-OrphanSweep {
    <#
        Reap orphaned model processes THIS run started that a child-tree kill missed, WITHOUT touching a
        process that was already alive before the run (a foreign/resident warm server owned by another
        holder). $BeforeSet is the run-start snapshot (hashtable pid->$true from Get-NamedProcessIdSet).
        Returns a report: { ran, names, before_count, after_count, candidate_pids, reaped_pids,
        skipped_pids, remaining_pids, all_clear }. Deterministic + safe on the cloud gate (empty sets -> no-op).
    #>
    [CmdletBinding()]
    param(
        $BeforeSet,
        [string[]]$Names = $script:OrphanSweepNames,
        [string[]]$ScopeMarkers = @(),
        [int]$SettleMs = 250
    )
    $names2 = @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $report = [ordered]@{
        ran = $false; names = $names2; before_count = 0; after_count = 0
        candidate_pids = @(); reaped_pids = @(); skipped_pids = @(); remaining_pids = @(); all_clear = $true
    }
    if ($names2.Count -eq 0) { return $report }
    $report.ran = $true
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }   # let tree-killed children die + a detached server settle
    $before = @{}
    if ($BeforeSet -is [System.Collections.IDictionary]) { foreach ($k in $BeforeSet.Keys) { $before[[int]$k] = $true } }
    $report.before_count = $before.Count
    $nowMap = Get-NamedProcessMap -Names $names2
    $report.after_count = @($nowMap).Count
    $cands = @($nowMap | Where-Object { -not $before.ContainsKey([int]$_.id) })
    $report.candidate_pids = @($cands | ForEach-Object { [int]$_.id })
    $reaped = New-Object System.Collections.Generic.List[int]
    $skipped = New-Object System.Collections.Generic.List[int]
    $remaining = New-Object System.Collections.Generic.List[int]
    foreach ($c in $cands) {
        $pidN = [int]$c.id
        if (-not (Test-OrphanInScope -ProcId $pidN -Name ([string]$c.name) -ScopeMarkers $ScopeMarkers)) { $skipped.Add($pidN); continue }
        if (Stop-ProcessHard -ProcId $pidN) { $reaped.Add($pidN) } else { $remaining.Add($pidN) }
    }
    $report.reaped_pids = $reaped.ToArray()
    $report.skipped_pids = $skipped.ToArray()
    $report.remaining_pids = $remaining.ToArray()
    $report.all_clear = ($remaining.Count -eq 0)
    return $report
}

function Invoke-RunOrphanSweep {
    # Convenience: run Invoke-OrphanSweep from the snapshot + scope captured on a run Handle (Start-SkillProcess).
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle, [int]$SettleMs = 250)
    $names = Get-Prop $Handle 'OrphanNames' $script:OrphanSweepNames
    if ($null -eq $names) { $names = $script:OrphanSweepNames }
    $before = Get-Prop $Handle 'OrphanBefore'
    $scope = @(Get-Prop $Handle 'OrphanScope')
    return (Invoke-OrphanSweep -BeforeSet $before -Names $names -ScopeMarkers $scope -SettleMs $SettleMs)
}

# ============================================================================
#  run a run_module item through the Module 1 wrapper
# ============================================================================

function Start-SkillProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SkillDir,
        [string]$InputsJson = '{}',
        [string]$WorkingDir,
        [string]$InvokeSkillPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$InvocationId,
        [hashtable]$Sync,
        [string]$WidgetRoot
    )
    $paths = Resolve-VerificationPaths -InvokeSkillPath $InvokeSkillPath -PwshPath $PwshPath -WidgetRoot $WidgetRoot

    $wrapper = $paths.InvokeSkillPath
    if (-not [System.IO.Path]::IsPathRooted($wrapper)) {
        $rp = Resolve-Path -LiteralPath $wrapper -ErrorAction SilentlyContinue
        if ($rp) { $wrapper = $rp.Path }
    }
    if (-not (Test-Path -LiteralPath $wrapper)) { throw "Invoke-Skill.ps1 (Module 1 wrapper) not found: $wrapper" }

    $skillDirAbs = $SkillDir
    if (-not [System.IO.Path]::IsPathRooted($skillDirAbs)) {
        $rp = Resolve-Path -LiteralPath $skillDirAbs -ErrorAction SilentlyContinue
        if ($rp) { $skillDirAbs = $rp.Path }
    }
    if (-not (Test-Path -LiteralPath $skillDirAbs -PathType Container)) { throw "module folder not found: $skillDirAbs" }

    if ([string]::IsNullOrWhiteSpace($InputsJson)) { $InputsJson = '{}' }
    if (-not $InvocationId) { $InvocationId = [guid]::NewGuid().ToString() }
    if (-not $ArtifactRoot) {
        $ArtifactRoot = Join-Path (Join-Path $paths.WidgetRoot (Join-Path 'runtime' 'artifacts')) $InvocationId
    }
    New-Item -ItemType Directory -Path $ArtifactRoot -Force -ErrorAction SilentlyContinue | Out-Null

    $stdoutPath = Join-Path $ArtifactRoot 'wrapper.stdout.txt'
    $stderrPath = Join-Path $ArtifactRoot 'wrapper.stderr.txt'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $paths.PwshPath
    $argv = @('-NoProfile', '-NonInteractive', '-File', $wrapper,
        '-SkillDir', $skillDirAbs, '-InputsJson', $InputsJson,
        '-ArtifactRoot', $ArtifactRoot, '-PwshPath', $paths.PwshPath)
    foreach ($a in $argv) { [void]$psi.ArgumentList.Add($a) }   # per-arg escaping; safe with spaces/quotes in the JSON
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $wd = if ($WorkingDir) { $WorkingDir } else { $paths.RepoRoot }
    if (Test-Path -LiteralPath $wd) { $psi.WorkingDirectory = $wd }

    # Snapshot the model-process PIDs alive BEFORE this run so teardown reaps ONLY what this run adds
    # (Governor Phase 2's detached warm llama-server escapes the child-tree kill) and never a
    # resident/foreign server. Scope marker = repo root + this run's module dir, so a non-llama worker
    # must prove (by command line) that it is ours before it can be killed.
    $orphanNames = $script:OrphanSweepNames
    $orphanBefore = Get-NamedProcessIdSet -Names $orphanNames
    $orphanScope = @($paths.RepoRoot, $skillDirAbs)

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    # Drain BOTH pipes concurrently (avoids the fill-deadlock gotcha) via async whole-stream reads.
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    $startedUtc = [datetime]::UtcNow
    if ($Sync) {
        $Sync['child_pid'] = $proc.Id
        $Sync['stdout_path'] = $stdoutPath
        $Sync['started_utc'] = $startedUtc
    }
    return [pscustomobject]@{
        Process      = $proc
        StdoutTask   = $outTask
        StderrTask   = $errTask
        StdoutPath   = $stdoutPath
        StderrPath   = $stderrPath
        ArtifactRoot = $ArtifactRoot
        InvocationId = $InvocationId
        InputsJson   = $InputsJson
        Paths        = $paths
        StartedUtc   = $startedUtc
        SkillDir     = $skillDirAbs
        OrphanBefore = $orphanBefore
        OrphanNames  = $orphanNames
        OrphanScope  = $orphanScope
    }
}

function Stop-SkillProcess {
    # Tear a run down: kill the child tree (Process.Kill) AND run the name-based orphan sweep, so a DETACHED
    # warm llama-server (parented outside the tree) is not left resident. Returns the sweep report (or $null).
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)
    if ($null -eq $Handle) { return $null }
    try { if (-not $Handle.Process.HasExited) { $Handle.Process.Kill($true) } } catch { }
    return (Invoke-RunOrphanSweep -Handle $Handle)
}

function Complete-SkillRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Handle)

    $proc = $Handle.Process
    try { $proc.WaitForExit() } catch { }

    $stdout = ''; $stderr = ''
    try { $stdout = $Handle.StdoutTask.GetAwaiter().GetResult() } catch { }
    try { $stderr = $Handle.StderrTask.GetAwaiter().GetResult() } catch { }
    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    try { [System.IO.File]::WriteAllText($Handle.StdoutPath, $stdout, $utf8) } catch { }
    try { [System.IO.File]::WriteAllText($Handle.StderrPath, $stderr, $utf8) } catch { }

    $wrapperExit = $null
    try { $wrapperExit = $proc.ExitCode } catch { }

    $parseError = $null
    $report = ConvertFrom-EnvelopeJson -Text $stdout -ErrorRef ([ref]$parseError)

    $manifestValid = $false; $invoked = $false; $reportExit = $null
    $envelopeValid = $false; $envelopeErrors = @(); $manifestErrors = @()
    $skillEnvelope = $null; $skillId = $null
    if ($report) {
        $manifestValid  = [bool](Get-Prop $report 'manifest_valid' $false)
        $invoked        = [bool](Get-Prop $report 'invoked' $false)
        $reportExit     = Get-Prop $report 'exit_code'
        $envelopeValid  = [bool](Get-Prop $report 'envelope_valid' $false)
        $envelopeErrors = @(Get-Prop $report 'envelope_errors')
        $manifestErrors = @(Get-Prop $report 'manifest_errors')
        $skillEnvelope  = Get-Prop $report 'envelope'
        $skillId        = Get-Prop $report 'skill_id'
    }
    if (-not $skillId) { $skillId = [System.IO.Path]::GetFileName($Handle.SkillDir) }

    $skillStatus = 'n/a'
    if ($skillEnvelope) { $skillStatus = [string](Get-Prop $skillEnvelope 'status' 'unknown') }
    $skillResult = if ($skillEnvelope) { Get-Prop $skillEnvelope 'result' } else { $null }

    $stderrTail = if ($stderr.Length -gt 1200) { $stderr.Substring($stderr.Length - 1200) } else { $stderr }

    $ok = ($null -ne $report -and $manifestValid -and $invoked -and $envelopeValid -and ($skillStatus -eq 'ok' -or $skillStatus -eq 'partial'))

    $err = $null
    if (-not $ok) {
        if ($null -eq $report) {
            $err = [pscustomobject]@{ code = 'no_report'; message = ("Invoke-Skill.ps1 produced no valid invocation_report (wrapper exit=$wrapperExit). " + [string]$parseError) }
        }
        elseif (-not $manifestValid) {
            $err = [pscustomobject]@{ code = 'manifest_invalid'; message = ('manifest failed validation: ' + (($manifestErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif (-not $invoked) {
            $err = [pscustomobject]@{ code = 'not_invoked'; message = ('module was not invoked: ' + (($envelopeErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif (-not $envelopeValid) {
            $err = [pscustomobject]@{ code = 'envelope_invalid'; message = ('the module did not return a valid result envelope: ' + (($envelopeErrors | Where-Object { $_ }) -join '; ')) }
        }
        elseif ($skillEnvelope -and (Get-Prop $skillEnvelope 'error')) {
            $e = Get-Prop $skillEnvelope 'error'
            $err = [pscustomobject]@{ code = [string](Get-Prop $e 'code' 'error'); message = [string](Get-Prop $e 'message' '') }
        }
        else {
            $err = [pscustomobject]@{ code = 'not_ok'; message = "the module returned status '$skillStatus'." }
        }
    }

    $elapsedMs = [int]([datetime]::UtcNow - $Handle.StartedUtc).TotalMilliseconds

    # Run-teardown orphan sweep: the wrapper process has exited, but a warm/persistent llama-server that
    # model.gateway launched DETACHED (Win32_Process.Create) is NOT a child and so outlives it. Reap any
    # such server THIS run started (before/after PID-set diff), leaving foreign/resident servers untouched.
    $orphanSweep = Invoke-RunOrphanSweep -Handle $Handle

    return [pscustomobject]@{
        ok               = $ok
        report           = $report
        skill_envelope   = $skillEnvelope
        skill_result     = $skillResult
        skill_status     = $skillStatus
        skill_id         = $skillId
        manifest_valid   = $manifestValid
        invoked          = $invoked
        wrapper_exit     = $wrapperExit
        report_exit_code = $reportExit
        envelope_valid   = $envelopeValid
        envelope_errors  = $envelopeErrors
        manifest_errors  = $manifestErrors
        stderr_tail      = $stderrTail
        raw_stdout       = $stdout
        parse_error      = $parseError
        error            = $err
        elapsed_ms       = $elapsedMs
        skill_dir        = $Handle.SkillDir
        artifact_root    = $Handle.ArtifactRoot
        orphan_sweep     = $orphanSweep
    }
}

function Invoke-SkillRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SkillDir,
        [string]$InputsJson = '{}',
        [string]$WorkingDir,
        [string]$InvokeSkillPath,
        [string]$PwshPath,
        [string]$ArtifactRoot,
        [string]$WidgetRoot
    )
    $h = Start-SkillProcess -SkillDir $SkillDir -InputsJson $InputsJson -WorkingDir $WorkingDir `
        -InvokeSkillPath $InvokeSkillPath -PwshPath $PwshPath -ArtifactRoot $ArtifactRoot -WidgetRoot $WidgetRoot
    try { $h.Process.WaitForExit() } catch { }
    return Complete-SkillRun -Handle $h
}

function Format-SkillResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run)

    $sb = [System.Text.StringBuilder]::new()
    function _addr([string]$line = '') { [void]$sb.AppendLine($line) }

    if ($null -eq (Get-Prop $Run 'report')) {
        _addr 'No valid invocation report was returned by the Module 1 wrapper.'
        _addr ''
        _addr ('wrapper exit : ' + [string](Get-Prop $Run 'wrapper_exit'))
        _addr ('parse note   : ' + [string](Get-Prop $Run 'parse_error'))
        $tail = [string](Get-Prop $Run 'stderr_tail')
        if ($tail) { _addr ''; _addr 'stderr (tail):'; _addr (Limit-Text $tail 1000) }
        return $sb.ToString()
    }

    _addr ('MODULE: ' + [string](Get-Prop $Run 'skill_id'))
    _addr ('WRAPPER: manifest_valid=' + [string](Get-Prop $Run 'manifest_valid') +
        '  invoked=' + [string](Get-Prop $Run 'invoked') +
        '  envelope_valid=' + [string](Get-Prop $Run 'envelope_valid') +
        '  skill_exit=' + [string](Get-Prop $Run 'report_exit_code'))

    $skEnv = Get-Prop $Run 'skill_envelope'
    $conf = if ($skEnv) { Get-Prop $skEnv 'confidence' } else { $null }
    _addr ('RESULT: status=' + [string](Get-Prop $Run 'skill_status') +
        '   confidence=' + $(if ($null -eq $conf) { 'n/a' } else { [string]$conf }) +
        '   duration=' + [string]$(if ($skEnv) { Get-Prop $skEnv 'duration_ms' (Get-Prop $Run 'elapsed_ms') } else { Get-Prop $Run 'elapsed_ms' }) + ' ms')
    _addr ''

    if (-not [bool](Get-Prop $Run 'manifest_valid' $false)) {
        _addr 'MANIFEST ERRORS:'
        foreach ($m in @(Get-Prop $Run 'manifest_errors')) { if ($m) { _addr ('  - ' + [string]$m) } }
        _addr ''
    }
    if ([bool](Get-Prop $Run 'invoked' $false) -and -not [bool](Get-Prop $Run 'envelope_valid' $false)) {
        _addr 'ENVELOPE ERRORS:'
        foreach ($m in @(Get-Prop $Run 'envelope_errors')) { if ($m) { _addr ('  - ' + [string]$m) } }
        _addr ''
    }

    $artRoot = [string](Get-Prop $Run 'artifact_root')
    if ($artRoot) {
        _addr ('OUTPUT LOCATION: ' + $artRoot)
        _addr '  (this run''s wrapper.stdout.txt / wrapper.stderr.txt + any artifacts below live under here)'
        _addr ''
    }

    if ($skEnv) {
        $res = Get-Prop $skEnv 'result'
        _addr 'RESULT PAYLOAD:'
        if ($null -eq $res) { _addr '  (none)' }
        else { _addr ('  ' + (Limit-Text (ConvertTo-CompactJson $res 10) 1600)) }
        _addr ''

        $arts = @(Get-Prop $skEnv 'artifacts')
        _addr ('ARTIFACTS (' + $arts.Count + '):')
        if ($arts.Count -eq 0) { _addr '  (none)' }
        foreach ($a in $arts) {
            _addr ('  - ' + [string](Get-Prop $a 'path') +
                '  (' + [string](Get-Prop $a 'kind' '?') + ', ' + [string](Get-Prop $a 'bytes' '?') + ' bytes)')
        }

        $prov = @(Get-Prop $skEnv 'model_provenance')
        if ($prov.Count -gt 0) {
            _addr ''
            _addr 'MODEL PROVENANCE:'
            foreach ($pp in $prov) {
                _addr ('  - ' + [string](Get-Prop $pp 'stage' '') + ' ' + [string](Get-Prop $pp 'model_id' (Get-Prop $pp 'model' '')) +
                    '  ' + [string](Get-Prop $pp 'runtime_ms' '?') + ' ms')
            }
        }
    }

    $err = Get-Prop $Run 'error'
    if ($err) {
        _addr ''
        _addr ('ERROR: ' + [string](Get-Prop $err 'code' 'error') + ': ' + (Limit-Text ([string](Get-Prop $err 'message' '')) 500))
    }

    $tail = [string](Get-Prop $Run 'stderr_tail')
    if ($tail -and -not [bool](Get-Prop $Run 'ok' $false)) {
        _addr ''
        _addr 'stderr (tail):'
        _addr (Limit-Text $tail 800)
    }
    return $sb.ToString()
}

# ============================================================================
#  assemble + save the verification result
# ============================================================================

function New-RunSummary {
    <# Compact, JSON-safe summary of a Complete-SkillRun result for embedding in the verification result. #>
    [CmdletBinding()]
    param($Run)
    if ($null -eq $Run) { return $null }
    $skEnv = Get-Prop $Run 'skill_envelope'
    $arts = New-Object System.Collections.Generic.List[object]
    foreach ($a in @(if ($skEnv) { Get-Prop $skEnv 'artifacts' } else { @() })) {
        $arts.Add([ordered]@{ path = [string](Get-Prop $a 'path'); kind = [string](Get-Prop $a 'kind' ''); bytes = (Get-Prop $a 'bytes') })
    }
    $errObj = $null
    $e = Get-Prop $Run 'error'
    if ($e) { $errObj = [ordered]@{ code = [string](Get-Prop $e 'code' ''); message = [string](Get-Prop $e 'message' '') } }
    return [ordered]@{
        ok            = [bool](Get-Prop $Run 'ok' $false)
        skill_id      = [string](Get-Prop $Run 'skill_id')
        skill_status  = [string](Get-Prop $Run 'skill_status')
        wrapper_exit  = (Get-Prop $Run 'wrapper_exit')
        confidence    = $(if ($skEnv) { Get-Prop $skEnv 'confidence' } else { $null })
        artifacts     = $arts.ToArray()
        artifact_root = [string](Get-Prop $Run 'artifact_root')
        elapsed_ms    = (Get-Prop $Run 'elapsed_ms')
        error         = $errObj
    }
}

function New-VerificationResultItem {
    <#
        Build one result item. $Checks is a list of { id, text, verdict, note } (verdict pass|fail|na|unchecked).
        $Overall is pass|fail|partial|skipped. $Run (optional) is a Complete-SkillRun result to summarize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        $Run,
        $Checks,
        [string]$Overall = 'skipped',
        [string]$Notes = ''
    )
    $checkOut = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($Checks)) {
        if ($null -eq $c) { continue }
        $checkOut.Add([ordered]@{
                id      = [string](Get-Prop $c 'id' '')
                text    = [string](Get-Prop $c 'text' '')
                verdict = ([string](Get-Prop $c 'verdict' 'unchecked')).ToLowerInvariant()
                note    = [string](Get-Prop $c 'note' '')
            })
    }
    return [ordered]@{
        id          = [string](Get-Prop $Item 'id')
        kind        = [string](Get-Prop $Item 'kind')
        title       = [string](Get-Prop $Item 'title')
        ran         = ($null -ne $Run)
        run_summary = (New-RunSummary -Run $Run)
        checks      = $checkOut.ToArray()
        overall     = $Overall.ToLowerInvariant()
        notes       = $Notes
    }
}

function Get-VerificationSummary {
    [CmdletBinding()]
    param($Items)
    $total = 0; $pass = 0; $fail = 0; $partial = 0; $skipped = 0
    foreach ($it in @($Items)) {
        $total++
        switch (([string](Get-Prop $it 'overall' 'skipped')).ToLowerInvariant()) {
            'pass' { $pass++ }
            'fail' { $fail++ }
            'partial' { $partial++ }
            default { $skipped++ }
        }
    }
    return [ordered]@{ total = $total; pass = $pass; fail = $fail; partial = $partial; skipped = $skipped }
}

function New-VerificationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Packet,
        [Parameter(Mandatory)]$Items,
        [string]$VerifiedBy = 'nicholas'
    )
    $itemArr = @($Items)
    return [ordered]@{
        schema          = $script:ResultSchema
        packet_id       = [string](Get-Prop $Packet 'packet_id')
        title           = [string](Get-Prop $Packet 'title')
        verified_by     = $VerifiedBy
        verified_at_utc = ([datetime]::UtcNow.ToString('o'))
        summary         = (Get-VerificationSummary -Items $itemArr)
        items           = $itemArr
    }
}

function Save-VerificationResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = $Result | ConvertTo-Json -Depth 20
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
    return $Path
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Prop, Limit-Text, ConvertTo-CompactJson, ConvertFrom-EnvelopeJson, `
    Resolve-VerificationPaths, Get-PlanIdFromPacket, Get-DefaultPacketsDir, Get-RecentPackets, Format-RecentPacketLine, `
    Import-VerificationPacket, ConvertTo-NormalizedChecklist, `
    Format-PacketSummary, Format-ItemListLine, Format-ItemDetail, Get-ReferencedPaths, Get-ItemActionModel, Resolve-ItemSkillDir, `
    Get-NamedProcessMap, Get-NamedProcessIdSet, Get-ProcessCommandLine, Test-OrphanInScope, `
    Stop-ProcessHard, Invoke-OrphanSweep, Invoke-RunOrphanSweep, `
    Start-SkillProcess, Stop-SkillProcess, Complete-SkillRun, Invoke-SkillRun, Format-SkillResult, `
    New-RunSummary, New-VerificationResultItem, Get-VerificationSummary, New-VerificationResult, Save-VerificationResult
