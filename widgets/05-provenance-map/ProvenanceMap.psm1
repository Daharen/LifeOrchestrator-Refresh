<#
    ProvenanceMap.psm1 - driver core for the Provenance Map (Widget 05).

    The construction-map analogue of the Fan-out Wave Dashboard (Widget 04) and the Verification Console
    (Widget 03): a READ-ONLY view that JOINS what the process ALREADY maintains into one map of how the
    project was built. It parses the canonical on-disk docs + read-only git DIRECTLY -- the docs and git ARE
    the source of truth -- so the widget has ZERO new doc-upkeep and ZERO side effects: it never invokes a
    module, never drives a worker, never writes a doc, never runs a git write, never calls a model, and never
    submits an executor job. The ONLY thing it may write is its OWN "new since last visit" marker under
    widgets/05-provenance-map/runtime/ (acceptance c), guarded so it can never escape that dir.

    Sources joined (all read-only; each degrades gracefully to a VISIBLE FLAG, never a crash -- acceptance b):
      - MODULE_ROADMAP.md        : the numbered module + widget units, their status + D-refs (what EXISTS /
                                   planned-but-unbuilt).
      - CURRENT_STATE.md         : the tests table (verification state per unit: version, iteration, commit,
                                   result) + the doc's own currency.
      - DECISION_LOG_INDEX.md    : one routing row per decision (id, date, state, label).
      - FANOUT_ORCHESTRATOR_HANDOFF.md : the iteration ledger (iteration -> plan_id -> D-refs -> commits) +
                                   the candidate menu (planned-but-unbuilt).
      - DOC_PROTOCOL.md          : the per-doc size budgets -> over-budget hot-doc flags (auto-surfacing the
                                   PB-3 doc-debt) computed against the docs' ACTUAL byte sizes on disk.
      - git log (dev.ship trailers) : commit -> date -> subject -> files -> the module/widget it touched,
                                   with iteration + plan_id + D-refs parsed from the subject.
      - runtime/plans/<id>/      : the orchestrate.fanout (#30) plan dirs (iteration -> plan -> worker states).
      - widgets/03 .../runtime/results/ : Verification Console durable verdicts (per-packet pass/fail), where
                                   parseable.

    Contains NO WinForms dependency, so it runs unchanged on the cloud pre-ship gate (against a fixture repo +
    an injected git-log fixture) and on Windows. The UI (Show-ProvenanceMap.ps1) is a thin shell over these
    functions. Design mirrors WaveDashboard.psm1 / VerificationConsole.psm1: defensive Get-Prop, List[object]
    + .ToArray() (never a bare @() on a maybe-null / on a raw List), Sort-Object (never [Array]::Sort's
    silent copy no-op), [IO.Path]::Combine for a foreign-platform-safe join, ASCII-only source (the docs it
    PARSES contain non-ASCII, e.g. em dashes -- read as UTF-8 and matched structurally; this SOURCE stays
    ASCII per the 5.1-ANSI/BOM lesson).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProvWidgetRoot = $PSScriptRoot

# The status words MODULE_ROADMAP uses; a unit is "built" when its status is one of the built set (or it has
# a test-table row with a real commit). Match is case-insensitive and order matters (first hit wins).
$script:StatusVocab = @(
    'MVP complete', 'MVP shipped', 'In progress', 'Needs refactor', 'Deprecated', 'Replaced',
    'Proposed', 'Ready', 'Blocked', 'Active', 'DEFERRED', 'Deferred', 'SHIPPED', 'complete')
$script:BuiltStatuses = @('mvp complete', 'mvp shipped', 'active', 'shipped', 'complete')

# ============================================================================
#  small helpers (shared shape with WaveDashboard.psm1 / VerificationConsole.psm1)
# ============================================================================

function Test-HasProp {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject -and $null -ne $Object.PSObject.Properties[$Name])
}

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { $v = $Object[$Name]; if ($null -ne $v) { return $v } ; return $Default }
        return $Default
    }
    if (Test-HasProp $Object $Name) { $v = $Object.$Name; if ($null -ne $v) { return $v } }
    return $Default
}

function ConvertTo-Array {
    # Normalize a maybe-null / scalar / array value to plain elements WITHOUT the StrictMode empty-unroll or
    # array-double-wrap traps (a string stays one element). Callers ALWAYS wrap the call in @( ... ).
    param($Value)
    $acc = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Value) {
        if ($Value -is [string]) { [void]$acc.Add($Value) }
        elseif ($Value -is [System.Collections.IEnumerable]) { foreach ($v in $Value) { [void]$acc.Add($v) } }
        else { [void]$acc.Add($Value) }
    }
    return $acc.ToArray()
}

function Limit-Text {
    param($Text, [int]$Max = 90)
    if ($null -eq $Text) { return '' }
    $s = ([string]$Text) -replace '\s+', ' '
    $s = $s.Trim()
    if ($s.Length -le $Max) { return $s }
    if ($Max -le 3) { return $s.Substring(0, $Max) }
    return $s.Substring(0, $Max - 3) + '...'
}

function ConvertTo-UtcTime {
    # Parse an ISO-8601 'o' (or a [datetime] from ConvertFrom-Json) to a UTC [datetime]; $null on failure.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value }
        if ($Value.Kind -eq [System.DateTimeKind]::Local) { return $Value.ToUniversalTime() }
        return [System.DateTime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $dt = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dt)) {
        if ($dt.Kind -eq [System.DateTimeKind]::Local) { return $dt.ToUniversalTime() }
        if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) { return [System.DateTime]::SpecifyKind($dt, [System.DateTimeKind]::Utc) }
        return $dt
    }
    return $null
}

function Read-JsonFileSafe {
    # Read + parse a JSON file DEFENSIVELY (shared read/delete access, tolerant of a mid-write file). Returns
    # the parsed object, or $null on any problem (missing / locked / empty / unparseable). Never throws.
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $txt = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.UTF8Encoding]::new($false))
            try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
        }
        finally { $fs.Dispose() }
    }
    catch { return $null }
    if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
    try { return ($txt | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Read-TextFileSafe {
    # Read a UTF-8 text file DEFENSIVELY -> { ok, text, bytes, error }. Never throws. Docs are CRLF + may hold
    # non-ASCII (em dashes) -- read as UTF-8 (no BOM assumption; StreamReader auto-detects a BOM).
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ ok = $false; text = ''; bytes = 0; error = 'missing' }
    }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $sr = New-Object System.IO.StreamReader(
            (New-Object System.IO.MemoryStream(, $bytes)), [System.Text.Encoding]::UTF8, $true)
        try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
        return [pscustomobject]@{ ok = $true; text = $txt; bytes = $bytes.Length; error = '' }
    }
    catch { return [pscustomobject]@{ ok = $false; text = ''; bytes = 0; error = 'unreadable' } }
}

function Get-MatchList {
    # All match values for a capture group across a string -> plain string[] (0..n), de-duped preserving order.
    param([string]$Text, [string]$Pattern, [int]$Group = 1)
    $acc = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    if (-not [string]::IsNullOrEmpty($Text)) {
        foreach ($m in [regex]::Matches($Text, $Pattern)) {
            $v = [string]$m.Groups[$Group].Value
            if ($v -and $seen.Add($v)) { [void]$acc.Add($v) }
        }
    }
    return $acc.ToArray()
}

function Split-TableRow {
    # Split a Markdown table row on unescaped pipes -> trimmed cell strings (leading/trailing empty cells
    # from the border pipes dropped). Never throws.
    param([string]$Line)
    $s = [string]$Line
    $s = $s.Trim()
    if ($s.StartsWith('|')) { $s = $s.Substring(1) }
    if ($s.EndsWith('|')) { $s = $s.Substring(0, $s.Length - 1) }
    $cells = New-Object System.Collections.Generic.List[string]
    foreach ($c in ($s -split '\|')) { [void]$cells.Add(([string]$c).Trim()) }
    return $cells.ToArray()
}

# ============================================================================
#  path resolution
# ============================================================================

function Resolve-ProvenancePaths {
    <#
        Resolve the widget root, the repo root, and every read-only data source. -RepoRoot (or the env
        override LIFEORCH_PROVENANCE_REPO) points the whole map at a fixture/other tree so the cloud gate runs
        without the production repo. [IO.Path]::Combine is a pure string join (no PSDrive resolution) so a
        foreign-platform RepoRoot ('C:\...') in a cloud-gate test does not throw "Cannot find drive 'C'".
    #>
    [CmdletBinding()]
    param([string]$WidgetRoot, [string]$RepoRoot, [string]$PlansDir, [string]$VerdictsDir)

    if (-not $WidgetRoot) { $WidgetRoot = $script:ProvWidgetRoot }
    if (-not $WidgetRoot) { $WidgetRoot = (Get-Location).Path }

    if (-not $RepoRoot) {
        if ($env:LIFEORCH_PROVENANCE_REPO) { $RepoRoot = $env:LIFEORCH_PROVENANCE_REPO }
        else {
            $rp = Resolve-Path -LiteralPath (Join-Path $WidgetRoot '..' | Join-Path -ChildPath '..') -ErrorAction SilentlyContinue
            if ($rp) { $RepoRoot = $rp.Path } else { $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $WidgetRoot '../..')) }
        }
    }

    # The live plan + verdict dirs default under the repo's (gitignored) runtime trees; env/param overrides let
    # the cloud gate + SelfTest point at COMMITTABLE fixture dirs that avoid the global **/runtime/ ignore.
    if (-not $PlansDir) {
        if ($env:LIFEORCH_PROVENANCE_PLANS) { $PlansDir = $env:LIFEORCH_PROVENANCE_PLANS }
        else { $PlansDir = [System.IO.Path]::Combine($RepoRoot, 'modules', '30-orchestrate-fanout', 'runtime', 'plans') }
    }
    if (-not $VerdictsDir) {
        if ($env:LIFEORCH_PROVENANCE_VERDICTS) { $VerdictsDir = $env:LIFEORCH_PROVENANCE_VERDICTS }
        else { $VerdictsDir = [System.IO.Path]::Combine($RepoRoot, 'widgets', '03-verification-console', 'runtime', 'results') }
    }

    $coreDocs = [System.IO.Path]::Combine($RepoRoot, 'core-docs')
    return [pscustomobject]@{
        WidgetRoot   = $WidgetRoot
        RepoRoot     = $RepoRoot
        CoreDocs     = $coreDocs
        Roadmap      = [System.IO.Path]::Combine($coreDocs, 'MODULE_ROADMAP.md')
        CurrentState = [System.IO.Path]::Combine($coreDocs, 'CURRENT_STATE.md')
        DecisionIndex = [System.IO.Path]::Combine($coreDocs, 'DECISION_LOG_INDEX.md')
        Handoff      = [System.IO.Path]::Combine($coreDocs, 'FANOUT_ORCHESTRATOR_HANDOFF.md')
        DocProtocol  = [System.IO.Path]::Combine($coreDocs, 'DOC_PROTOCOL.md')
        PlansDir     = $PlansDir
        VerdictsDir  = $VerdictsDir
        RuntimeDir   = [System.IO.Path]::Combine($WidgetRoot, 'runtime')
    }
}

# ============================================================================
#  parsers -- each returns a { ... ; flags[] } shape; a parse problem is a FLAG, never a throw
# ============================================================================

function Get-DocBudgetFlags {
    <#
        Parse DOC_PROTOCOL.md section 2's budget table + stat the docs' ACTUAL byte sizes -> per-doc rows:
          { doc, budget_kb (or $null for 'no cap'), actual_bytes, pct, status, over }
        status: ok (<90%) | warn (90-100%) | over (>100%) | nocap | missing | unknown.
        A 'KB each' glob row (research/*, fanout/*) expands to one row per matching file. Over-budget rows
        auto-surface the PB-3 doc-debt. Graceful: an unreadable DOC_PROTOCOL -> a single flag + empty rows.
    #>
    [CmdletBinding()]
    param([string]$DocProtocolPath, [string]$CoreDocsDir)
    $flags = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    $read = Read-TextFileSafe -Path $DocProtocolPath
    if (-not $read.ok) {
        [void]$flags.Add('DOC_PROTOCOL.md unreadable (' + $read.error + ') -- doc-budget flags unavailable')
        return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
    }
    $inTable = $false
    foreach ($rawLine in ($read.text -split "\r?\n")) {
        $line = [string]$rawLine
        if (-not $inTable) {
            if ($line -match '^\|\s*doc\s*\|\s*owns\s*\|\s*budget\s*\|') { $inTable = $true }
            continue
        }
        if ($line -notmatch '^\|') { break }                 # table ended
        if ($line -match '^\|\s*-{2,}') { continue }          # the |---|---|---| separator
        $cells = Split-TableRow -Line $line
        if ($cells.Count -lt 3) { continue }
        $doc = [string]$cells[0]
        $budgetCell = [string]$cells[2]
        # strip Markdown escapes used in the table (e.g. research/&lt;date&gt;-*.md)
        $doc = $doc -replace '&lt;', '<' -replace '&gt;', '>'
        $doc = $doc.Trim('`').Trim()
        if ([string]::IsNullOrWhiteSpace($doc) -or $doc -eq 'doc') { continue }

        $budgetKb = $null
        $isNoCap = ($budgetCell -match '(?i)no\s*cap')
        if (-not $isNoCap) {
            $bm = [regex]::Match($budgetCell, '(\d+)\s*KB')
            if ($bm.Success) { $budgetKb = [int]$bm.Groups[1].Value }
        }

        # resolve the target file(s): a glob (contains * or a stripped <date>) expands under core-docs.
        $targets = New-Object System.Collections.Generic.List[string]
        if ($doc -match '[\*<]') {
            $globName = ($doc -replace '<[^>]*>', '*')
            $sub = ''
            $leaf = $globName
            if ($globName.Contains('/')) { $sub = ($globName -split '/')[0]; $leaf = ($globName -split '/')[-1] }
            $searchDir = if ($sub) { [System.IO.Path]::Combine($CoreDocsDir, $sub) } else { $CoreDocsDir }
            if (Test-Path -LiteralPath $searchDir -PathType Container) {
                foreach ($fi in @(Get-ChildItem -LiteralPath $searchDir -Filter $leaf -File -ErrorAction SilentlyContinue)) {
                    $rel = if ($sub) { $sub + '/' + $fi.Name } else { $fi.Name }
                    [void]$targets.Add($rel)
                }
            }
        }
        else { [void]$targets.Add($doc) }

        if ($targets.Count -eq 0) {
            # a glob row with no matching files -> record the budget line itself, status unknown
            $rows.Add([pscustomobject]@{ doc = $doc; budget_kb = $budgetKb; actual_bytes = 0; pct = $null; status = 'unknown'; over = $false })
            continue
        }
        foreach ($rel in $targets) {
            $full = [System.IO.Path]::Combine($CoreDocsDir, ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar))
            $exists = Test-Path -LiteralPath $full -PathType Leaf
            $bytes = 0
            if ($exists) { $fi = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue; if ($fi) { $bytes = [int]$fi.Length } }
            $status = 'unknown'; $pct = $null; $over = $false
            if ($isNoCap) { $status = 'nocap' }
            elseif (-not $exists) { $status = 'missing' }
            elseif ($null -ne $budgetKb -and $budgetKb -gt 0) {
                $pct = [Math]::Round(($bytes / ($budgetKb * 1024.0)) * 100.0, 1)
                if ($pct -gt 100.0) { $status = 'over'; $over = $true }
                elseif ($pct -ge 90.0) { $status = 'warn' }
                else { $status = 'ok' }
            }
            if ($over) { [void]$flags.Add('OVER BUDGET: ' + $rel + ' at ' + [string]$pct + '% of ' + [string]$budgetKb + ' KB (PB-3 doc-debt)') }
            $rows.Add([pscustomobject]@{ doc = $rel; budget_kb = $budgetKb; actual_bytes = $bytes; pct = $pct; status = $status; over = $over })
        }
    }
    if ($rows.Count -eq 0) { [void]$flags.Add('DOC_PROTOCOL.md budget table not found or empty') }
    return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
}

function Get-DecisionIndex {
    <#
        Parse DECISION_LOG_INDEX.md's | id | date | state | decision | table -> rows:
          { id, num, date, state, decision, iterations[] }
        iterations[] = the 'iNN' hints in the decision text (e.g. 'i35 CLOSED'); the AUTHORITATIVE
        iteration<->D map comes from the handoff ledger, this is a hint. Graceful: unreadable -> a flag.
    #>
    [CmdletBinding()]
    param([string]$DecisionIndexPath)
    $flags = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    $read = Read-TextFileSafe -Path $DecisionIndexPath
    if (-not $read.ok) {
        [void]$flags.Add('DECISION_LOG_INDEX.md unreadable (' + $read.error + ')')
        return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
    }
    foreach ($rawLine in ($read.text -split "\r?\n")) {
        $line = [string]$rawLine
        if ($line -notmatch '^\|\s*D-\d+') { continue }
        $cells = Split-TableRow -Line $line
        if ($cells.Count -lt 4) { continue }
        $id = ([string]$cells[0]).Trim()
        $idm = [regex]::Match($id, 'D-(\d+)')
        $num = if ($idm.Success) { [int]$idm.Groups[1].Value } else { 0 }
        $decision = [string]$cells[3]
        $iters = @(Get-MatchList -Text $decision -Pattern '\bi(\d{1,3})\b' -Group 1 | ForEach-Object { [int]$_ })
        $rows.Add([pscustomobject]@{
                id = $id; num = $num; date = ([string]$cells[1]).Trim(); state = ([string]$cells[2]).Trim()
                decision = $decision.Trim(); iterations = $iters
            })
    }
    if ($rows.Count -eq 0) { [void]$flags.Add('DECISION_LOG_INDEX.md: no decision rows parsed') }
    $sorted = @($rows.ToArray() | Sort-Object -Property num -Descending)
    return [pscustomobject]@{ rows = $sorted; flags = $flags.ToArray() }
}

function Get-ModuleUnits {
    <#
        Parse MODULE_ROADMAP.md's built-modules ('**<NN> `id`** ... status ... (D-refs)') + widgets bullets
        ('- **<NN> <Name>** ... status ... (D-refs)') -> unit rows:
          { key, kind, num, id, name, status, built, d_refs[] }
        built = status in the built set. Numbered units only (prose menus are handled as planned elsewhere).
        Graceful: unreadable -> a flag + empty.
    #>
    [CmdletBinding()]
    param([string]$RoadmapPath)
    $flags = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    $read = Read-TextFileSafe -Path $RoadmapPath
    if (-not $read.ok) {
        [void]$flags.Add('MODULE_ROADMAP.md unreadable (' + $read.error + ')')
        return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
    }
    foreach ($rawLine in ($read.text -split "\r?\n")) {
        $line = [string]$rawLine
        $kind = ''; $num = ''; $id = ''; $name = ''
        # module: **0 `exec.bootstrap`** ...   (backtick-wrapped id)
        $mm = [regex]::Match($line, '^\*\*(\d[\d.]*)\s+`([a-z0-9._-]+)`\*\*(.*)$')
        if ($mm.Success) {
            $kind = 'module'; $num = $mm.Groups[1].Value; $id = $mm.Groups[2].Value
            $rest = $mm.Groups[3].Value
            $name = (Get-UnitName -Rest $rest)
        }
        else {
            # widget: - **01 Local Agent Console** ...   (numbered, name inside the bold)
            $wm = [regex]::Match($line, '^-\s*\*\*(\d[\d.]*)\s+([^*]+?)\*\*(.*)$')
            if ($wm.Success) {
                $kind = 'widget'; $num = $wm.Groups[1].Value; $name = ($wm.Groups[2].Value).Trim()
                $id = $name
                $rest = $wm.Groups[3].Value
            }
            else { continue }
        }
        $whole = $line
        $status = (Get-StatusWord -Text $whole)
        $drefs = @(Get-MatchList -Text $whole -Pattern '(D-\d+)' -Group 1)
        $built = ($script:BuiltStatuses -contains ([string]$status).ToLowerInvariant())
        $rows.Add([pscustomobject]@{
                key = ($kind + ':' + $num); kind = $kind; num = $num; id = $id
                name = $name; status = $status; built = $built; d_refs = $drefs
            })
    }
    if ($rows.Count -eq 0) { [void]$flags.Add('MODULE_ROADMAP.md: no numbered units parsed') }
    return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
}

function Get-UnitName {
    # Best-effort name from a module line remainder: text after the leading separator up to the first middot
    # (U+00B7) or '(' -- cleaned of em/en dashes + double-hyphen separators. Falls back to ''.
    param([string]$Rest)
    $s = [string]$Rest
    # cut at the first middot or open paren
    $cut = [regex]::Match($s, '^(.*?)(?:\u00B7|\()')
    if ($cut.Success) { $s = $cut.Groups[1].Value }
    $s = $s -replace '\u2014', ' ' -replace '\u2013', ' ' -replace '(^|\s)--(\s|$)', ' '
    $s = ($s -replace '\s+', ' ').Trim()
    return $s
}

function Get-StatusWord {
    # First status-vocabulary word present in a line (case-insensitive), else ''.
    param([string]$Text)
    foreach ($w in $script:StatusVocab) {
        if ([regex]::IsMatch($Text, [regex]::Escape($w), 'IgnoreCase')) { return $w }
    }
    return ''
}

function Get-TestTable {
    <#
        Parse CURRENT_STATE.md's | unit | last result | task / commit | date | table -> rows:
          { unit, kind, num, result, version, iteration, commit, date }
        The verification state per unit (test counts) + the version/iteration/commit embedded in the result +
        commit cells. Graceful: unreadable -> a flag.
    #>
    [CmdletBinding()]
    param([string]$CurrentStatePath)
    $flags = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    $read = Read-TextFileSafe -Path $CurrentStatePath
    if (-not $read.ok) {
        [void]$flags.Add('CURRENT_STATE.md unreadable (' + $read.error + ')')
        return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
    }
    $inTable = $false
    foreach ($rawLine in ($read.text -split "\r?\n")) {
        $line = [string]$rawLine
        if (-not $inTable) {
            if ($line -match '^\|\s*unit\s*\|\s*last result\s*\|') { $inTable = $true }
            continue
        }
        if ($line -notmatch '^\|') { if ($rows.Count -gt 0) { break } else { continue } }
        if ($line -match '^\|\s*-{2,}') { continue }
        $cells = Split-TableRow -Line $line
        if ($cells.Count -lt 4) { continue }
        $unit = [string]$cells[0]
        if ($unit -eq 'unit') { continue }
        $result = [string]$cells[1]
        $taskCommit = [string]$cells[2]
        $date = ([string]$cells[3]).Trim()
        $kind = ''; $num = ''
        $um = [regex]::Match($unit, '#(\d[\d.]*)')
        if ($um.Success) { $kind = 'module'; $num = $um.Groups[1].Value }
        else {
            $uw = [regex]::Match($unit, '(?i)widgets?/(\d[\d.]*)')
            if ($uw.Success) { $kind = 'widget'; $num = $uw.Groups[1].Value }
        }
        $ver = ''
        $vm = [regex]::Match($result, '(\d+\.\d+\.\d+)')
        if ($vm.Success) { $ver = $vm.Groups[1].Value }
        $iter = ''
        $im = [regex]::Match($result, '\bi(\d{1,3})\b')
        if ($im.Success) { $iter = $im.Groups[1].Value }
        $commit = ''
        $cm = [regex]::Match($taskCommit, '`([0-9a-f]{7,40})`')
        if ($cm.Success) { $commit = $cm.Groups[1].Value }
        $rows.Add([pscustomobject]@{
                unit = $unit.Trim(); kind = $kind; num = $num; result = $result.Trim()
                version = $ver; iteration = $iter; commit = $commit; date = $date
            })
    }
    if ($rows.Count -eq 0) { [void]$flags.Add('CURRENT_STATE.md: tests table not found or empty') }
    return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
}

function Get-IterationLedger {
    <#
        Parse FANOUT_ORCHESTRATOR_HANDOFF.md's iteration-ledger lines ('- iNN `fo-...` (D-...): ...', incl.
        a range '- **i1-i24 (D-...)**') -> per-iteration rows:
          { iteration, iter_end, is_range, plan_ids[], d_refs[], commits[], summary }
        The AUTHORITATIVE iteration<->{plan,D,commit} map. Graceful: unreadable -> a flag.
    #>
    [CmdletBinding()]
    param([string]$HandoffPath)
    $flags = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    $read = Read-TextFileSafe -Path $HandoffPath
    if (-not $read.ok) {
        [void]$flags.Add('FANOUT_ORCHESTRATOR_HANDOFF.md unreadable (' + $read.error + ')')
        return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
    }
    foreach ($rawLine in ($read.text -split "\r?\n")) {
        $line = [string]$rawLine
        $m = [regex]::Match($line, '^-\s*\*{0,2}i(\d{1,3})(?:-i(\d{1,3}))?\b')
        if (-not $m.Success) { continue }
        $iter = [int]$m.Groups[1].Value
        $isRange = $m.Groups[2].Success
        $iterEnd = if ($isRange) { [int]$m.Groups[2].Value } else { $iter }
        $plans = @(Get-MatchList -Text $line -Pattern '(fo-\d+-[0-9a-f]+)' -Group 1)
        $commits = @(Get-MatchList -Text $line -Pattern '`([0-9a-f]{7,10})`' -Group 1)
        $drefs = @(Get-MatchList -Text $line -Pattern '(D-\d+)' -Group 1)
        $rows.Add([pscustomobject]@{
                iteration = $iter; iter_end = $iterEnd; is_range = $isRange
                plan_ids = $plans; d_refs = $drefs; commits = $commits; summary = $line.Trim()
            })
    }
    if ($rows.Count -eq 0) { [void]$flags.Add('FANOUT_ORCHESTRATOR_HANDOFF.md: no iteration-ledger lines parsed') }
    $sorted = @($rows.ToArray() | Sort-Object -Property iteration -Descending)
    return [pscustomobject]@{ rows = $sorted; flags = $flags.ToArray() }
}

function Get-HandoffCandidates {
    <#
        Parse the handoff's numbered candidate-unit menu ('N. **<title>** ...') into planned-but-unbuilt
        rows: { label, d_refs[] }. Best-effort (the menu is prose); a miss is silent (not a flag).
    #>
    [CmdletBinding()]
    param([string]$HandoffPath)
    $rows = New-Object System.Collections.Generic.List[object]
    $read = Read-TextFileSafe -Path $HandoffPath
    if (-not $read.ok) { return $rows.ToArray() }
    $inMenu = $false
    foreach ($rawLine in ($read.text -split "\r?\n")) {
        $line = [string]$rawLine
        if ($line -match '(?i)candidate units') { $inMenu = $true; continue }
        if (-not $inMenu) { continue }
        if ($line -match '^\s*##\s') { break }
        $m = [regex]::Match($line, '^\d+\.\s+\*\*(.+?)\*\*')
        if ($m.Success) {
            $rows.Add([pscustomobject]@{
                    label = ($m.Groups[1].Value).Trim()
                    d_refs = @(Get-MatchList -Text $line -Pattern '(D-\d+)' -Group 1)
                })
        }
    }
    return $rows.ToArray()
}

# ============================================================================
#  git provenance (dev.ship trailers) -- read-only; injectable for the cloud gate
# ============================================================================

function ConvertFrom-GitLog {
    <#
        Parse the output of:
          git log --no-color --date=short --name-only --pretty=format:'<RS>%h<US>%ad<US>%s'
        (RS = 0x1E record separator, US = 0x1F field separator) into commit rows:
          { hash, date, subject, iteration, plan_id, d_refs[], files[], units[] }
        iteration: from the subject's 'fo-<N>-' plan id, else a leading 'i<N>' token. units: modules/widgets
        the files touched. Pure + deterministic; the SINGLE git seam so tests feed fixture text. Never throws.
    #>
    [CmdletBinding()]
    param([string]$LogText)
    $rows = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($LogText)) { return $rows.ToArray() }
    $RS = [char]0x1E; $US = [char]0x1F
    foreach ($rec in ($LogText -split $RS)) {
        if ([string]::IsNullOrWhiteSpace($rec)) { continue }
        $lines = @($rec -split "\r?\n")
        $head = [string]$lines[0]
        $parts = $head -split $US
        if ($parts.Count -lt 3) { continue }
        $hash = ([string]$parts[0]).Trim()
        if ($hash -notmatch '^[0-9a-f]{6,40}$') { continue }
        $date = ([string]$parts[1]).Trim()
        $subject = ([string]$parts[2]).Trim()
        $files = New-Object System.Collections.Generic.List[string]
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $f = ([string]$lines[$i]).Trim()
            if ($f) { [void]$files.Add($f) }
        }
        $iteration = ''
        $pm = [regex]::Match($subject, 'fo-(\d{1,3})-[0-9a-f]+')
        if ($pm.Success) { $iteration = $pm.Groups[1].Value }
        else { $im = [regex]::Match($subject, '(?i)(?:^|[^a-z])i(\d{1,3})\b'); if ($im.Success) { $iteration = $im.Groups[1].Value } }
        $planId = ''
        $pim = [regex]::Match($subject, '(fo-\d{1,3}-[0-9a-f]+)')
        if ($pim.Success) { $planId = $pim.Groups[1].Value }
        $drefs = @(Get-MatchList -Text $subject -Pattern '(D-\d+)' -Group 1)
        $units = New-Object System.Collections.Generic.List[string]
        $seen = New-Object System.Collections.Generic.HashSet[string]
        foreach ($f in $files.ToArray()) {
            $um = [regex]::Match($f, '^(modules|widgets)/(\d[\d.]*)-')
            if ($um.Success) {
                $ukind = if ($um.Groups[1].Value -eq 'widgets') { 'widget' } else { 'module' }
                $k = $ukind + ':' + $um.Groups[2].Value
                if ($seen.Add($k)) { [void]$units.Add($k) }
            }
        }
        $rows.Add([pscustomobject]@{
                hash = $hash; date = $date; subject = $subject; iteration = $iteration
                plan_id = $planId; d_refs = $drefs; files = $files.ToArray(); units = $units.ToArray()
            })
    }
    return $rows.ToArray()
}

function Get-GitProvenance {
    <#
        Return git commit provenance -> { rows[], ok, flags[] }. In production runs read-only `git -C <repo>
        log ...`; a test passes -LogText (fixture) to skip the process. Graceful: git absent / not a repo /
        error -> ok=false + a flag + empty rows (the widget renders everything else). NEVER a git write.
    #>
    [CmdletBinding()]
    param([string]$RepoRoot, [int]$Max = 400, [string]$LogText, [string]$GitExe = 'git')
    $flags = New-Object System.Collections.Generic.List[string]
    if ($PSBoundParameters.ContainsKey('LogText')) {
        return [pscustomobject]@{ rows = @(ConvertFrom-GitLog -LogText $LogText); ok = $true; flags = $flags.ToArray() }
    }
    if ([string]::IsNullOrWhiteSpace($RepoRoot) -or -not (Test-Path -LiteralPath ([System.IO.Path]::Combine($RepoRoot, '.git')))) {
        [void]$flags.Add('git provenance unavailable (no .git under repo root) -- commit view empty')
        return [pscustomobject]@{ rows = @(); ok = $false; flags = $flags.ToArray() }
    }
    $RS = [char]0x1E; $US = [char]0x1F
    $fmt = "${RS}%h${US}%ad${US}%s"
    $out = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $GitExe
        [void]$psi.ArgumentList.Add('-C'); [void]$psi.ArgumentList.Add($RepoRoot)
        [void]$psi.ArgumentList.Add('log'); [void]$psi.ArgumentList.Add('--no-color')
        [void]$psi.ArgumentList.Add('--date=short'); [void]$psi.ArgumentList.Add('--name-only')
        [void]$psi.ArgumentList.Add('-n'); [void]$psi.ArgumentList.Add([string]$Max)
        [void]$psi.ArgumentList.Add('--pretty=format:' + $fmt)
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        [void]$p.StandardError.ReadToEnd()
        $p.WaitForExit(20000) | Out-Null
        if (-not $p.HasExited) { try { $p.Kill() } catch { } ; [void]$flags.Add('git log timed out') }
    }
    catch {
        [void]$flags.Add('git log failed: ' + $_.Exception.Message)
        return [pscustomobject]@{ rows = @(); ok = $false; flags = $flags.ToArray() }
    }
    return [pscustomobject]@{ rows = @(ConvertFrom-GitLog -LogText $out); ok = $true; flags = $flags.ToArray() }
}

# ============================================================================
#  plan + verdict provenance (read-only)
# ============================================================================

function Get-PlanProvenance {
    <#
        Scan the orchestrate.fanout plans dir -> per-plan rows { iteration, plan_id, title, workers, done,
        failed, other }, newest-iteration first. Reads plan.json + reports/*.json READ-ONLY (never writes,
        never drives #30). Graceful: absent dir -> empty; a malformed plan.json -> a well-formed row.
    #>
    [CmdletBinding()]
    param([string]$PlansDir, [int]$Max = 200)
    $flags = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($PlansDir) -or -not (Test-Path -LiteralPath $PlansDir -PathType Container)) {
        return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $PlansDir -Directory -ErrorAction SilentlyContinue)) {
        $leaf = Split-Path -Leaf $d.FullName
        $pf = [System.IO.Path]::Combine($d.FullName, 'plan.json')
        $plan = Read-JsonFileSafe -Path $pf
        $iter = 0
        $im = [regex]::Match($leaf, '^fo-(\d{1,3})-')
        if ($im.Success) { $iter = [int]$im.Groups[1].Value }
        $planId = $leaf; $title = ''
        if ($null -ne $plan) {
            $planId = [string](Get-Prop $plan 'plan_id' $leaf)
            $title = [string](Get-Prop $plan 'title' '')
            if ($iter -eq 0) { $iter = [int](Get-Prop $plan 'iteration' 0) }
        }
        $workers = @(ConvertTo-Array (Get-Prop $plan 'workers'))
        # latest report state per worker
        $latest = @{}
        $reportsDir = [System.IO.Path]::Combine($d.FullName, 'reports')
        if (Test-Path -LiteralPath $reportsDir -PathType Container) {
            foreach ($rf in @(Get-ChildItem -LiteralPath $reportsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                $r = Read-JsonFileSafe -Path $rf.FullName
                if ($null -eq $r) { continue }
                $wid = [string](Get-Prop $r 'worker_id' '')
                if (-not $wid) { continue }
                $ra = [string](Get-Prop $r 'reported_at_utc' '')
                if ((-not $latest.ContainsKey($wid)) -or ($ra -gt [string]$latest[$wid].at)) {
                    $latest[$wid] = [ordered]@{ state = [string](Get-Prop $r 'state' ''); at = $ra }
                }
            }
        }
        $done = 0; $failed = 0; $other = 0
        foreach ($k in $latest.Keys) {
            switch ([string]$latest[$k].state) {
                'done' { $done++ }
                'failed' { $failed++ }
                default { $other++ }
            }
        }
        $rows.Add([pscustomobject]@{
                iteration = $iter; plan_id = $planId; title = $title
                workers = $workers.Count; done = $done; failed = $failed; other = $other; ok = ($null -ne $plan)
            })
    }
    $sorted = @($rows.ToArray() | Sort-Object -Property @{ Expression = 'iteration'; Descending = $true }, @{ Expression = 'plan_id'; Descending = $true })
    if ($sorted.Count -gt $Max) { $sorted = @($sorted[0..($Max - 1)]) }
    return [pscustomobject]@{ rows = $sorted; flags = $flags.ToArray() }
}

function Get-VerificationVerdicts {
    <#
        Scan the Verification Console durable-verdicts sidecar (widgets/03 .../runtime/results/*.json;
        lifeorch.verification.result/0.1) -> rows { packet_id, title, verified_by, verified_at, total, pass,
        fail, partial, skipped }, newest-verified first. READ-ONLY. Graceful: absent dir -> empty.
    #>
    [CmdletBinding()]
    param([string]$VerdictsDir, [int]$Max = 200)
    $flags = New-Object System.Collections.Generic.List[string]
    $rows = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($VerdictsDir) -or -not (Test-Path -LiteralPath $VerdictsDir -PathType Container)) {
        return [pscustomobject]@{ rows = $rows.ToArray(); flags = $flags.ToArray() }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $VerdictsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $v = Read-JsonFileSafe -Path $f.FullName
        if ($null -eq $v) {
            $rows.Add([pscustomobject]@{ packet_id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name); title = '<unreadable>'; verified_by = ''; verified_at = ''; total = $null; pass = $null; fail = $null; partial = $null; skipped = $null })
            continue
        }
        $sum = Get-Prop $v 'summary'
        $rows.Add([pscustomobject]@{
                packet_id  = [string](Get-Prop $v 'packet_id' ([System.IO.Path]::GetFileNameWithoutExtension($f.Name)))
                title      = [string](Get-Prop $v 'title' '')
                verified_by = [string](Get-Prop $v 'verified_by' '')
                verified_at = [string](Get-Prop $v 'verified_at_utc' '')
                total = [int](Get-Prop $sum 'total' 0); pass = [int](Get-Prop $sum 'pass' 0)
                fail = [int](Get-Prop $sum 'fail' 0); partial = [int](Get-Prop $sum 'partial' 0)
                skipped = [int](Get-Prop $sum 'skipped' 0)
            })
    }
    $sorted = @($rows.ToArray() | Sort-Object -Property verified_at -Descending)
    if ($sorted.Count -gt $Max) { $sorted = @($sorted[0..($Max - 1)]) }
    return [pscustomobject]@{ rows = $sorted; flags = $flags.ToArray() }
}

# ============================================================================
#  the ONE read: Get-ProvenanceModel (the whole join) -- WinForms-free, ZERO side effects
# ============================================================================

function Get-ProvenanceModel {
    <#
        Read every canonical source + read-only git and JOIN them into one plain object the shell renders +
        the SelfTest/gate assert on. ZERO side effects (reads only; the ONLY writer in this module is
        Set-LastVisit, never called here). -GitLogText injects fixture git output for the cloud gate.
    #>
    [CmdletBinding()]
    param([string]$RepoRoot, [string]$WidgetRoot, [string]$GitLogText, [string]$PlansDir, [string]$VerdictsDir)

    $paths = Resolve-ProvenancePaths -WidgetRoot $WidgetRoot -RepoRoot $RepoRoot -PlansDir $PlansDir -VerdictsDir $VerdictsDir
    $flags = New-Object System.Collections.Generic.List[string]

    $docFlags = Get-DocBudgetFlags -DocProtocolPath $paths.DocProtocol -CoreDocsDir $paths.CoreDocs
    $decisions = Get-DecisionIndex -DecisionIndexPath $paths.DecisionIndex
    $unitsParse = Get-ModuleUnits -RoadmapPath $paths.Roadmap
    $tests = Get-TestTable -CurrentStatePath $paths.CurrentState
    $ledger = Get-IterationLedger -HandoffPath $paths.Handoff
    $candidates = @(Get-HandoffCandidates -HandoffPath $paths.Handoff)
    $plans = Get-PlanProvenance -PlansDir $paths.PlansDir
    $verdicts = Get-VerificationVerdicts -VerdictsDir $paths.VerdictsDir
    if ($PSBoundParameters.ContainsKey('GitLogText')) { $git = Get-GitProvenance -LogText $GitLogText }
    else { $git = Get-GitProvenance -RepoRoot $paths.RepoRoot }

    foreach ($src in @($docFlags, $decisions, $unitsParse, $tests, $ledger, $plans, $verdicts, $git)) {
        foreach ($fl in @(Get-Prop $src 'flags')) { [void]$flags.Add([string]$fl) }
    }

    # index the test table by unit key for the join
    $testByKey = @{}
    foreach ($t in @($tests.rows)) {
        if ($t.kind -and $t.num) { $testByKey[($t.kind + ':' + $t.num)] = $t }
    }
    # index last commit touching each unit (git rows are newest-first as git log returns them)
    $commitByUnit = @{}
    foreach ($c in @($git.rows)) {
        foreach ($u in @($c.units)) { if (-not $commitByUnit.ContainsKey($u)) { $commitByUnit[$u] = $c } }
    }

    # JOIN units: the UNION of roadmap-parsed numbered units AND tests-table units (memory modules #35-#42 and
    # any newer unit live only in the tests table, not the roadmap's numbered built-modules list).
    $units = New-Object System.Collections.Generic.List[object]
    $unitKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($u in @($unitsParse.rows)) {
        $key = [string]$u.key
        [void]$unitKeys.Add($key)
        $t = if ($testByKey.ContainsKey($key)) { $testByKey[$key] } else { $null }
        $version = if ($t) { [string]$t.version } else { '' }
        $iter = if ($t) { [string]$t.iteration } else { '' }
        $commit = if ($t -and $t.commit) { [string]$t.commit } else { '' }
        $testResult = if ($t) { [string]$t.result } else { '' }
        $hasTestRow = ($null -ne $t)
        $lastCommit = if ($commitByUnit.ContainsKey($key)) { [string]$commitByUnit[$key].hash } else { '' }
        if (-not $commit) { $commit = $lastCommit }
        $built = [bool]$u.built -or ($hasTestRow -and $commit)
        $units.Add([pscustomobject]@{
                key = $key; kind = [string]$u.kind; num = [string]$u.num; id = [string]$u.id
                name = [string]$u.name; status = [string]$u.status; built = $built; planned = (-not $built)
                version = $version; iteration = $iter; d_refs = @($u.d_refs); commit = $commit
                test_result = $testResult; has_test_row = $hasTestRow; last_commit = $lastCommit
            })
    }
    # tests-table-only units (e.g. the memory modules) -- synthesize from the test row + last commit.
    foreach ($t in @($tests.rows)) {
        if (-not ($t.kind -and $t.num)) { continue }
        $key = ($t.kind + ':' + $t.num)
        if ($unitKeys.Contains($key)) { continue }
        [void]$unitKeys.Add($key)
        # id/name from the tests-table 'unit' cell, e.g. '#36 artifact.search' -> 'artifact.search'.
        $idName = ([string]$t.unit) -replace '^#\d[\d.]*\s*', '' -replace '(?i)^widgets?/\d[\d.]*\s*', ''
        $commit = if ($t.commit) { [string]$t.commit } elseif ($commitByUnit.ContainsKey($key)) { [string]$commitByUnit[$key].hash } else { '' }
        $lastCommit = if ($commitByUnit.ContainsKey($key)) { [string]$commitByUnit[$key].hash } else { '' }
        $units.Add([pscustomobject]@{
                key = $key; kind = [string]$t.kind; num = [string]$t.num; id = $idName.Trim()
                name = $idName.Trim(); status = 'tested'; built = $true; planned = $false
                version = [string]$t.version; iteration = [string]$t.iteration; d_refs = @(); commit = $commit
                test_result = [string]$t.result; has_test_row = $true; last_commit = $lastCommit
            })
    }
    $unitsArr = @($units.ToArray() | Sort-Object -Property @{ Expression = { $_.kind } }, @{ Expression = { [double]([regex]::Match([string]$_.num, '^\d+').Value) } }, @{ Expression = { [string]$_.num } })

    # planned-but-unbuilt = unbuilt numbered units + handoff candidate menu
    $planned = New-Object System.Collections.Generic.List[object]
    foreach ($u in $unitsArr) { if (-not $u.built) { $planned.Add([pscustomobject]@{ source = 'roadmap'; label = ($u.kind + ' ' + $u.num + ' ' + $u.name); status = $u.status; d_refs = @($u.d_refs) }) } }
    foreach ($c in $candidates) { $planned.Add([pscustomobject]@{ source = 'handoff-menu'; label = [string]$c.label; status = 'candidate'; d_refs = @($c.d_refs) }) }

    # iteration set (from the ledger; ranges contribute their end label)
    $iterations = @($ledger.rows)

    $moduleCount = @($unitsArr | Where-Object { $_.kind -eq 'module' }).Count
    $widgetCount = @($unitsArr | Where-Object { $_.kind -eq 'widget' }).Count
    $builtCount = @($unitsArr | Where-Object { $_.built }).Count
    $overBudget = @(@($docFlags.rows) | Where-Object { $_.over }).Count

    return [pscustomobject]@{
        ok            = $true
        error         = ''
        repo_root     = $paths.RepoRoot
        widget_root   = $paths.WidgetRoot
        runtime_dir   = $paths.RuntimeDir
        units         = $unitsArr
        planned       = $planned.ToArray()
        decisions     = @($decisions.rows)
        iterations    = $iterations
        commits       = @($git.rows)
        plans         = @($plans.rows)
        verdicts      = @($verdicts.rows)
        doc_flags     = @($docFlags.rows)
        git_ok        = [bool]$git.ok
        flags         = $flags.ToArray()
        counts        = [ordered]@{
            modules = $moduleCount; widgets = $widgetCount; units = $unitsArr.Count; built = $builtCount
            planned = $planned.Count; decisions = @($decisions.rows).Count; iterations = $iterations.Count
            commits = @($git.rows).Count; verdicts = @($verdicts.rows).Count; over_budget_docs = $overBudget
            degradation_flags = $flags.Count
        }
    }
}

# ============================================================================
#  derived views: the one-click "what did iteration N build" + "new since"
# ============================================================================

function Get-IterationBuild {
    <#
        The one-click answer (acceptance e): given iteration N, gather from the joined model everything that
        iteration built and under which decision:
          { iteration, found, ledger, decisions[], units[], commits[], plans[] }
        A ledger RANGE that covers N counts as covering it. Deterministic; pure over the model.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][int]$Iteration)

    $ledgerHits = New-Object System.Collections.Generic.List[object]
    foreach ($r in @(Get-Prop $Model 'iterations')) {
        $s = [int](Get-Prop $r 'iteration' 0); $e = [int](Get-Prop $r 'iter_end' $s)
        if ($Iteration -ge $s -and $Iteration -le $e) { $ledgerHits.Add($r) }
    }
    # D-refs named by any matching ledger line -> decisions
    $ledgerDrefs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($r in $ledgerHits.ToArray()) { foreach ($d in @(Get-Prop $r 'd_refs')) { [void]$ledgerDrefs.Add([string]$d) } }
    $decisions = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-Prop $Model 'decisions')) {
        $hit = $ledgerDrefs.Contains([string]$d.id)
        if (-not $hit) { foreach ($i in @(Get-Prop $d 'iterations')) { if ([int]$i -eq $Iteration) { $hit = $true } } }
        if ($hit) { $decisions.Add($d) }
    }
    $commits = New-Object System.Collections.Generic.List[object]
    $touchedKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($c in @(Get-Prop $Model 'commits')) {
        if ([string]$c.iteration -eq [string]$Iteration) {
            $commits.Add($c)
            foreach ($k in @(Get-Prop $c 'units')) { [void]$touchedKeys.Add([string]$k) }
        }
    }
    # units = those the tests table tags to iteration N, PLUS any unit a commit of iteration N touched (git
    # is authoritative for "touched"); de-duped by key.
    $units = New-Object System.Collections.Generic.List[object]
    $unitSeen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($u in @(Get-Prop $Model 'units')) {
        $hit = ([string]$u.iteration -eq [string]$Iteration) -or $touchedKeys.Contains([string]$u.key)
        if ($hit -and $unitSeen.Add([string]$u.key)) { $units.Add($u) }
    }
    $plans = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Get-Prop $Model 'plans')) { if ([int]$p.iteration -eq $Iteration) { $plans.Add($p) } }

    $found = ($ledgerHits.Count -gt 0) -or ($decisions.Count -gt 0) -or ($units.Count -gt 0) -or ($commits.Count -gt 0) -or ($plans.Count -gt 0)
    return [pscustomobject]@{
        iteration = $Iteration; found = $found
        ledger = $ledgerHits.ToArray(); decisions = $decisions.ToArray(); units = $units.ToArray()
        commits = $commits.ToArray(); plans = $plans.ToArray()
    }
}

function Get-NewSince {
    <#
        "New since iteration N" (acceptance c-adjacent): everything with an iteration STRICTLY GREATER than N.
          { since, units[], commits[], iterations[], decisions[] }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][int]$Since)
    $units = New-Object System.Collections.Generic.List[object]
    foreach ($u in @(Get-Prop $Model 'units')) { $iv = 0; if ([int]::TryParse([string]$u.iteration, [ref]$iv)) { if ($iv -gt $Since) { $units.Add($u) } } }
    $commits = New-Object System.Collections.Generic.List[object]
    foreach ($c in @(Get-Prop $Model 'commits')) { $iv = 0; if ([int]::TryParse([string]$c.iteration, [ref]$iv)) { if ($iv -gt $Since) { $commits.Add($c) } } }
    $iters = New-Object System.Collections.Generic.List[object]
    foreach ($r in @(Get-Prop $Model 'iterations')) { if ([int](Get-Prop $r 'iter_end' 0) -gt $Since) { $iters.Add($r) } }
    $decisions = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-Prop $Model 'decisions')) {
        $max = -1; foreach ($i in @(Get-Prop $d 'iterations')) { if ([int]$i -gt $max) { $max = [int]$i } }
        if ($max -gt $Since) { $decisions.Add($d) }
    }
    return [pscustomobject]@{ since = $Since; units = $units.ToArray(); commits = $commits.ToArray(); iterations = $iters.ToArray(); decisions = $decisions.ToArray() }
}

function Get-IterationList {
    <#
        Build the iteration-picker list: { num, label } from the ledger (a range -> one entry at its start) +
        any commit-only iteration, de-duped by num, NEWEST FIRST. Pure + UI-agnostic -- it lives in the tested
        core (NOT the shell) precisely because of the trap it must avoid: an [ordered] hashtable indexed by an
        INT key resolves the int as a POSITION (ArgumentOutOfRangeException for a key past Count), which -- if it
        reached a WinForms event handler -- pops a MODAL error dialog that hangs a headless SelfTest forever. A
        plain Hashtable indexes by KEY, so $byNum[$n] is always the value for key $n.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model)
    $byNum = @{}
    foreach ($r in @(Get-Prop $Model 'iterations')) {
        $n = [int](Get-Prop $r 'iteration' 0)
        if ($n -le 0 -or $byNum.ContainsKey($n)) { continue }
        if ([bool](Get-Prop $r 'is_range' $false)) { $byNum[$n] = 'i' + [string]$n + '-i' + [string](Get-Prop $r 'iter_end' $n) + ' (range)' }
        else { $byNum[$n] = 'i' + [string]$n }
    }
    foreach ($c in @(Get-Prop $Model 'commits')) {
        $iv = 0
        if ([int]::TryParse([string](Get-Prop $c 'iteration' ''), [ref]$iv) -and $iv -gt 0 -and -not $byNum.ContainsKey($iv)) {
            $byNum[$iv] = 'i' + [string]$iv + ' (git only)'
        }
    }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($n in @($byNum.Keys | Sort-Object -Descending)) {
        $items.Add([pscustomobject]@{ num = [int]$n; label = [string]$byNum[$n] })
    }
    return $items.ToArray()
}

# ============================================================================
#  the ONLY writer: the "new since last visit" marker (guarded to the widget's OWN runtime dir)
# ============================================================================

function Get-LastVisit {
    # Read the persisted marker (widgets/05-provenance-map/runtime/last-visit.json) -> { last_iteration,
    # last_seen_utc } or $null. Read-only.
    [CmdletBinding()]
    param([string]$RuntimeDir)
    if (-not $RuntimeDir) { $RuntimeDir = (Resolve-ProvenancePaths).RuntimeDir }
    $f = [System.IO.Path]::Combine($RuntimeDir, 'last-visit.json')
    $o = Read-JsonFileSafe -Path $f
    if ($null -eq $o) { return $null }
    return [pscustomobject]@{ last_iteration = [int](Get-Prop $o 'last_iteration' 0); last_seen_utc = [string](Get-Prop $o 'last_seen_utc' '') }
}

function Set-LastVisit {
    <#
        Persist the marker -- the ONLY write this module performs (acceptance c). GUARDED: the resolved target
        MUST live under the widget's OWN runtime dir, else it throws (acceptance d -- the widget can never
        write outside its runtime dir). Returns the written path.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Iteration, [string]$RuntimeDir, [string]$SeenUtc)
    if (-not $RuntimeDir) { $RuntimeDir = (Resolve-ProvenancePaths).RuntimeDir }
    $runtimeFull = [System.IO.Path]::GetFullPath($RuntimeDir)
    $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($runtimeFull, 'last-visit.json'))
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $guard = $runtimeFull.TrimEnd($sep) + $sep
    if (-not $target.StartsWith($guard, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Set-LastVisit refused: target '$target' is outside the widget runtime dir '$runtimeFull' (read-only guard)."
    }
    if (-not (Test-Path -LiteralPath $runtimeFull -PathType Container)) { New-Item -ItemType Directory -Path $runtimeFull -Force | Out-Null }
    if (-not $SeenUtc) { $SeenUtc = [datetime]::UtcNow.ToString('o') }
    $obj = [ordered]@{ schema = 'lifeorch.provenance.last_visit/0.1'; last_iteration = $Iteration; last_seen_utc = $SeenUtc }
    [System.IO.File]::WriteAllText($target, ($obj | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    return $target
}

# ============================================================================
#  Format-ProvenanceRows -- display strings for a monospace UI (and for the SelfTest/gate to assert on).
#  Pure string work; no WinForms. Mirrors Format-WaveRows (Widget 04).
# ============================================================================

function Format-ProvenanceRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model)

    $header = New-Object System.Collections.Generic.List[string]
    if (-not [bool](Get-Prop $Model 'ok' $false)) {
        $header.Add('NO PROVENANCE MODEL')
        $header.Add('  ' + [string](Get-Prop $Model 'error'))
        return [pscustomobject]@{
            header_lines = $header.ToArray(); exists_header = ''; exists_lines = @(); planned_lines = @()
            verify_lines = @(); commit_header = ''; commit_lines = @(); decision_lines = @()
            docflag_header = ''; docflag_lines = @(); flag_lines = @(); summary_line = 'no model'
        }
    }
    $c = Get-Prop $Model 'counts'
    $over = [int](Get-Prop $c 'over_budget_docs' 0)
    $degr = [int](Get-Prop $c 'degradation_flags' 0)
    $header.Add('PROVENANCE MAP -- ' + [string](Get-Prop $Model 'repo_root'))
    $header.Add('modules: ' + [string](Get-Prop $c 'modules') + '   widgets: ' + [string](Get-Prop $c 'widgets') +
        '   built: ' + [string](Get-Prop $c 'built') + '   planned: ' + [string](Get-Prop $c 'planned') +
        '   decisions: ' + [string](Get-Prop $c 'decisions') + '   iterations: ' + [string](Get-Prop $c 'iterations') +
        '   commits: ' + [string](Get-Prop $c 'commits'))
    $health = if ($over -gt 0 -or $degr -gt 0) { 'FLAGS: over-budget docs=' + [string]$over + '  degradation=' + [string]$degr } else { 'FLAGS: none (clean)' }
    $header.Add($health)

    # EXISTS -- unit table (kind/num/id/status/version/iter/commit/verified)
    $eh = ('{0,-7} {1,-4} {2,-26} {3,-13} {4,-8} {5,-5} {6,-9} {7}' -f 'KIND', 'NUM', 'ID / NAME', 'STATUS', 'VER', 'ITER', 'COMMIT', 'VERIFIED')
    $elines = New-Object System.Collections.Generic.List[string]
    foreach ($u in @(Get-Prop $Model 'units')) {
        $ver = [bool](Get-Prop $u 'has_test_row' $false)
        $verTxt = if ($ver) { 'yes' } else { 'no' }
        $eline = '{0,-7} {1,-4} {2,-26} {3,-13} {4,-8} {5,-5} {6,-9} {7}' -f `
            (Limit-Text (Get-Prop $u 'kind') 7), (Limit-Text (Get-Prop $u 'num') 4),
            (Limit-Text (Get-Prop $u 'id') 26), (Limit-Text (Get-Prop $u 'status') 13),
            (Limit-Text (Get-Prop $u 'version') 8), (Limit-Text (Get-Prop $u 'iteration') 5),
            (Limit-Text (Get-Prop $u 'commit') 9), $verTxt
        [void]$elines.Add($eline)
    }
    if ($elines.Count -eq 0) { $elines.Add('(no units parsed)') }

    # PLANNED-but-unbuilt
    $plines = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(Get-Prop $Model 'planned')) {
        $dr = @(Get-Prop $p 'd_refs'); $drTxt = if ($dr.Count -gt 0) { ' [' + ($dr -join ',') + ']' } else { '' }
        [void]$plines.Add(('[' + [string](Get-Prop $p 'source') + '] ' + (Limit-Text (Get-Prop $p 'label') 80) + '  <' + [string](Get-Prop $p 'status') + '>' + $drTxt))
    }
    if ($plines.Count -eq 0) { $plines.Add('(nothing planned-but-unbuilt parsed)') }

    # VERIFICATION per unit + a missing-test flag
    $vlines = New-Object System.Collections.Generic.List[string]
    foreach ($u in @(Get-Prop $Model 'units')) {
        if (-not [bool]$u.built) { continue }
        $res = [string](Get-Prop $u 'test_result')
        if ([bool](Get-Prop $u 'has_test_row' $false) -and $res) {
            [void]$vlines.Add((('{0,-5} {1,-24} ' -f (Get-Prop $u 'num'), (Limit-Text (Get-Prop $u 'id') 24)) + (Limit-Text $res 90)))
        }
        else {
            [void]$vlines.Add((('{0,-5} {1,-24} ' -f (Get-Prop $u 'num'), (Limit-Text (Get-Prop $u 'id') 24)) + 'NO TEST-TABLE ROW (verification unverified)'))
        }
    }
    foreach ($vd in @(Get-Prop $Model 'verdicts')) {
        [void]$vlines.Add(('verdict ' + (Limit-Text (Get-Prop $vd 'packet_id') 22) + '  pass=' + [string](Get-Prop $vd 'pass') + ' fail=' + [string](Get-Prop $vd 'fail') + ' partial=' + [string](Get-Prop $vd 'partial') + ' skip=' + [string](Get-Prop $vd 'skipped') + '  by ' + [string](Get-Prop $vd 'verified_by')))
    }
    if ($vlines.Count -eq 0) { $vlines.Add('(no verification rows)') }

    # COMMITS (git dev.ship trailers)
    $ch = ('{0,-9} {1,-11} {2,-5} {3}' -f 'COMMIT', 'DATE', 'ITER', 'SUBJECT')
    $clines = New-Object System.Collections.Generic.List[string]
    foreach ($cm in @(Get-Prop $Model 'commits')) {
        $cline = '{0,-9} {1,-11} {2,-5} {3}' -f `
            (Limit-Text (Get-Prop $cm 'hash') 9), (Limit-Text (Get-Prop $cm 'date') 11),
            (Limit-Text (Get-Prop $cm 'iteration') 5), (Limit-Text (Get-Prop $cm 'subject') 96)
        [void]$clines.Add($cline)
    }
    if ($clines.Count -eq 0) { $clines.Add('(no git commit provenance -- see FLAGS)') }

    # DECISIONS
    $dlines = New-Object System.Collections.Generic.List[string]
    foreach ($d in @(Get-Prop $Model 'decisions')) {
        [void]$dlines.Add(('{0,-8} {1,-11} {2,-13} {3}' -f (Get-Prop $d 'id'), (Get-Prop $d 'date'), (Limit-Text (Get-Prop $d 'state') 13), (Limit-Text (Get-Prop $d 'decision') 96)))
    }
    if ($dlines.Count -eq 0) { $dlines.Add('(no decisions parsed)') }

    # DOC-BUDGET flags
    $dfh = ('{0,-34} {1,-8} {2,-10} {3,-7} {4}' -f 'DOC', 'BUDGET', 'ACTUAL', 'PCT', 'STATUS')
    $dflines = New-Object System.Collections.Generic.List[string]
    foreach ($df in @(Get-Prop $Model 'doc_flags')) {
        $bk = Get-Prop $df 'budget_kb'; $bkTxt = if ($null -ne $bk) { [string]$bk + 'KB' } else { '-' }
        $pct = Get-Prop $df 'pct'; $pctTxt = if ($null -ne $pct) { [string]$pct + '%' } else { '-' }
        $mark = if ([bool](Get-Prop $df 'over' $false)) { 'OVER <<' } else { [string](Get-Prop $df 'status') }
        [void]$dflines.Add(('{0,-34} {1,-8} {2,-10} {3,-7} {4}' -f (Limit-Text (Get-Prop $df 'doc') 34), $bkTxt, ([string](Get-Prop $df 'actual_bytes') + 'B'), $pctTxt, $mark))
    }
    if ($dflines.Count -eq 0) { $dflines.Add('(no doc-budget rows)') }

    # degradation FLAGS
    $flines = New-Object System.Collections.Generic.List[string]
    foreach ($fl in @(Get-Prop $Model 'flags')) { [void]$flines.Add([string]$fl) }
    if ($flines.Count -eq 0) { $flines.Add('(no degradation flags -- all sources parsed cleanly)') }

    $summary = ('units: ' + [string](Get-Prop $c 'units') + '   built: ' + [string](Get-Prop $c 'built') +
        '   planned: ' + [string](Get-Prop $c 'planned') + '   commits: ' + [string](Get-Prop $c 'commits') +
        '   over-budget docs: ' + [string]$over + '   degradation flags: ' + [string]$degr)

    return [pscustomobject]@{
        header_lines  = $header.ToArray()
        exists_header = $eh; exists_lines = $elines.ToArray()
        planned_lines = $plines.ToArray()
        verify_lines  = $vlines.ToArray()
        commit_header = $ch; commit_lines = $clines.ToArray()
        decision_lines = $dlines.ToArray()
        docflag_header = $dfh; docflag_lines = $dflines.ToArray()
        flag_lines    = $flines.ToArray()
        summary_line  = $summary
    }
}

function Format-IterationBuild {
    <#
        Render Get-IterationBuild output as display lines (the one-click "what did iteration N build and under
        which decision?" answer). Returns { title, lines[] }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Build)
    $iter = [int](Get-Prop $Build 'iteration' 0)
    $lines = New-Object System.Collections.Generic.List[string]
    if (-not [bool](Get-Prop $Build 'found' $false)) {
        $lines.Add('No provenance found for iteration ' + [string]$iter + ' (no ledger line, decision, unit, or commit).')
        return [pscustomobject]@{ title = ('ITERATION ' + [string]$iter); lines = $lines.ToArray() }
    }
    foreach ($l in @(Get-Prop $Build 'ledger')) { [void]$lines.Add('LEDGER: ' + (Limit-Text (Get-Prop $l 'summary') 160)) }
    $lines.Add('')
    $lines.Add('DECISIONS:')
    $ds = @(Get-Prop $Build 'decisions')
    if ($ds.Count -eq 0) { $lines.Add('  (none named)') } else { foreach ($d in $ds) { [void]$lines.Add('  ' + [string](Get-Prop $d 'id') + ' (' + [string](Get-Prop $d 'state') + ')  ' + (Limit-Text (Get-Prop $d 'decision') 120)) } }
    $lines.Add('')
    $lines.Add('UNITS BUILT/TOUCHED:')
    $us = @(Get-Prop $Build 'units')
    if ($us.Count -eq 0) { $lines.Add('  (none tagged to this iteration in the tests table)') } else { foreach ($u in $us) { [void]$lines.Add('  ' + [string](Get-Prop $u 'kind') + ' ' + [string](Get-Prop $u 'num') + ' ' + [string](Get-Prop $u 'id') + '  v' + [string](Get-Prop $u 'version') + '  ' + [string](Get-Prop $u 'commit')) } }
    $lines.Add('')
    $lines.Add('COMMITS:')
    $cs = @(Get-Prop $Build 'commits')
    if ($cs.Count -eq 0) { $lines.Add('  (none parsed from git for this iteration)') } else { foreach ($cm in $cs) { [void]$lines.Add('  ' + [string](Get-Prop $cm 'hash') + '  ' + (Limit-Text (Get-Prop $cm 'subject') 110)) } }
    $ps = @(Get-Prop $Build 'plans')
    if ($ps.Count -gt 0) {
        $lines.Add('')
        $lines.Add('WAVE PLANS:')
        foreach ($p in $ps) { [void]$lines.Add('  ' + [string](Get-Prop $p 'plan_id') + '  workers=' + [string](Get-Prop $p 'workers') + ' done=' + [string](Get-Prop $p 'done') + ' failed=' + [string](Get-Prop $p 'failed') + '  ' + (Limit-Text (Get-Prop $p 'title') 70)) }
    }
    return [pscustomobject]@{ title = ('ITERATION ' + [string]$iter); lines = $lines.ToArray() }
}

function Format-NewSince {
    # Render Get-NewSince output as display lines. Returns { title, lines[] }.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$NewSince)
    $since = [int](Get-Prop $NewSince 'since' 0)
    $lines = New-Object System.Collections.Generic.List[string]
    $us = @(Get-Prop $NewSince 'units'); $cs = @(Get-Prop $NewSince 'commits'); $ds = @(Get-Prop $NewSince 'decisions')
    $lines.Add('NEW SINCE ITERATION ' + [string]$since + '  (units=' + [string]$us.Count + ' commits=' + [string]$cs.Count + ' decisions=' + [string]$ds.Count + ')')
    $lines.Add('')
    $lines.Add('UNITS:')
    if ($us.Count -eq 0) { $lines.Add('  (none)') } else { foreach ($u in $us) { [void]$lines.Add('  i' + [string](Get-Prop $u 'iteration') + '  ' + [string](Get-Prop $u 'kind') + ' ' + [string](Get-Prop $u 'num') + ' ' + [string](Get-Prop $u 'id') + '  v' + [string](Get-Prop $u 'version')) } }
    $lines.Add('')
    $lines.Add('COMMITS:')
    if ($cs.Count -eq 0) { $lines.Add('  (none)') } else { foreach ($cm in $cs) { [void]$lines.Add('  i' + [string](Get-Prop $cm 'iteration') + '  ' + [string](Get-Prop $cm 'hash') + '  ' + (Limit-Text (Get-Prop $cm 'subject') 100)) } }
    $lines.Add('')
    $lines.Add('DECISIONS:')
    if ($ds.Count -eq 0) { $lines.Add('  (none)') } else { foreach ($d in $ds) { [void]$lines.Add('  ' + [string](Get-Prop $d 'id') + '  ' + (Limit-Text (Get-Prop $d 'decision') 110)) } }
    return [pscustomobject]@{ title = ('NEW SINCE i' + [string]$since); lines = $lines.ToArray() }
}

Export-ModuleMember -Function `
    Test-HasProp, Get-Prop, ConvertTo-Array, Limit-Text, ConvertTo-UtcTime, Read-JsonFileSafe, Read-TextFileSafe, `
    Get-MatchList, Split-TableRow, Resolve-ProvenancePaths, `
    Get-DocBudgetFlags, Get-DecisionIndex, Get-ModuleUnits, Get-UnitName, Get-StatusWord, Get-TestTable, `
    Get-IterationLedger, Get-HandoffCandidates, ConvertFrom-GitLog, Get-GitProvenance, `
    Get-PlanProvenance, Get-VerificationVerdicts, Get-ProvenanceModel, Get-IterationBuild, Get-NewSince, `
    Get-IterationList, Get-LastVisit, Set-LastVisit, Format-ProvenanceRows, Format-IterationBuild, Format-NewSince
