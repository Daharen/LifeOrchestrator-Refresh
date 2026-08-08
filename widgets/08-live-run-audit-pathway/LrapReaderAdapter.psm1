<#
    LrapReaderAdapter.psm1 -- the Live-Run Audit Pathway (Widget 08) PINNED, VERSIONED reader adapter over the
    EXISTING public pure-read functions of the shipped Widgets 06 (Compile Trace Console) and 07 (Audit
    Timeline + Tournament). Design s5 / red-team finding F8.

    WHY AN ADAPTER (not a wholesale import): importing 06/07 wholesale would (a) couple LRAP to their internal
    signatures so a future 06/07 refactor breaks LRAP SILENTLY (their tests exercise their WINDOWS, not LRAP's
    consumption), and (b) drag in Widget-06's counterfactual RE-COMPILE entrypoints, which LRAP must NEVER call
    (LRAP is strictly read-only, renders pinned identities, NEVER recompiles). So Widget 08 OWNS this thin
    adapter: it imports 06/07 with a NAME PREFIX (so their readers are reused, never re-implemented, and never
    collide), re-exports ONLY the specific pure readers LRAP depends on, EXCLUDES the recompute entrypoints, and
    ships a CROSS-WIDGET CONTRACT TEST (Test-LrapAdapterContract) that fails when a depended-on 06/07 shape
    drifts. It does NOT modify Widgets 05/06/07.

    Pinned reader surface (the ONLY 06/07 functions LRAP consumes):
      Read-LrapPacket          <- 06 Read-ContextPacket        (load a context_packet/0.2 in any carrier shape)
      Get-LrapRouterBracket    <- 07 Get-RouterTournament      (router stage-trace reconcile: in-|removed|==out; chain)
      Get-LrapSelectionBracket <- 07 Get-SelectionTournament   (selpol reconcile: packet<=post<=raw; omit-reason presence)
      Test-LrapTraceSanitized  <- 06 Test-TraceSanitized       (i33: router trace removed[] is channel-only)
      Get-LrapRawModelView     <- 06 Get-Pane2ModelView        (raw expert pane -- behind "show raw trace" ONLY)
      Get-LrapRawRetrievalTrace<- 06 Get-Pane3RetrievalTrace   ("
      Get-LrapRawRuleStack     <- 06 Get-Pane4RuleStack        ("
      Get-LrapRawLedger        <- 06 Get-Pane6TokenLedger      ("
      Get-LrapRawStageTimeline <- 06 Get-Pane1Timeline         ("

    EXCLUDED (the recompute / counterfactual entrypoints -- LRAP must never call these):
      Invoke-CompileCounterfactual, Invoke-CtcCompileWorker, New-CounterfactualCase, Resolve-Python,
      Get-CounterfactualVariations, Get-PacketDiff. They are contained inside the prefixed import (module scope)
      and are NEVER re-exported by this adapter; Test-LrapAdapterContract asserts none is in the public surface.

    ASCII-only source (the 5.1-ANSI/BOM lesson). Contains NO WinForms dependency (runs on the cloud gate).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LrapAdapterVersion = '1.0.0'

# Resolve the shipped sibling widgets by path (pure string join, so a foreign-platform WidgetRoot in a cloud
# gate does not throw). $PSScriptRoot is widgets/08-live-run-audit-pathway.
$script:Lrap06Psm1 = [System.IO.Path]::Combine($PSScriptRoot, '..', '06-compile-trace-console', 'CompileTraceConsole.psm1')
$script:Lrap07Psm1 = [System.IO.Path]::Combine($PSScriptRoot, '..', '07-audit-timeline-tournament', 'AuditTimelineTournament.psm1')

if (-not (Test-Path -LiteralPath $script:Lrap06Psm1 -PathType Leaf)) { throw "LrapReaderAdapter: Widget 06 core not found at $script:Lrap06Psm1" }
if (-not (Test-Path -LiteralPath $script:Lrap07Psm1 -PathType Leaf)) { throw "LrapReaderAdapter: Widget 07 core not found at $script:Lrap07Psm1" }

# Import 06/07 into THIS module's scope with a name PREFIX. Nested import: the prefixed commands are usable by
# this module's functions but are NOT leaked to the adapter's importer, and NOT re-exported (proven in the
# suite). 06 -> *Ctc06*, 07 -> *Att07*.
Import-Module $script:Lrap06Psm1 -Prefix 'Ctc06' -Force
Import-Module $script:Lrap07Psm1 -Prefix 'Att07' -Force

# The PINNED contract: exactly which underlying 06/07 reader each wrapper depends on, and the members its
# result MUST carry. Test-LrapAdapterContract asserts every one still holds (drift -> fail).
$script:LrapPinnedReaders = @(
    [pscustomobject]@{ wrapper = 'Read-LrapPacket'; widget = '06'; underlying = 'Read-Ctc06ContextPacket'; shape = @('ok', 'packet', 'schema', 'packet_id', 'compiler_version') }
    [pscustomobject]@{ wrapper = 'Get-LrapRouterBracket'; widget = '07'; underlying = 'Get-Att07RouterTournament'; shape = @('present', 'rounds', 'reconciled', 'lines', 'flags') }
    [pscustomobject]@{ wrapper = 'Get-LrapSelectionBracket'; widget = '07'; underlying = 'Get-Att07SelectionTournament'; shape = @('present', 'reconciled', 'lines', 'flags', 'raw', 'post', 'packet') }
    [pscustomobject]@{ wrapper = 'Test-LrapTraceSanitized'; widget = '06'; underlying = 'Test-Ctc06TraceSanitized'; shape = @('sanitized', 'violations', 'trace_present', 'removed_entry_count') }
    [pscustomobject]@{ wrapper = 'Get-LrapRawModelView'; widget = '06'; underlying = 'Get-Ctc06Pane2ModelView'; shape = @('header', 'lines', 'flags') }
    [pscustomobject]@{ wrapper = 'Get-LrapRawRetrievalTrace'; widget = '06'; underlying = 'Get-Ctc06Pane3RetrievalTrace'; shape = @('header', 'lines', 'flags') }
    [pscustomobject]@{ wrapper = 'Get-LrapRawRuleStack'; widget = '06'; underlying = 'Get-Ctc06Pane4RuleStack'; shape = @('header', 'lines', 'flags') }
    [pscustomobject]@{ wrapper = 'Get-LrapRawLedger'; widget = '06'; underlying = 'Get-Ctc06Pane6TokenLedger'; shape = @('header', 'lines', 'flags') }
    [pscustomobject]@{ wrapper = 'Get-LrapRawStageTimeline'; widget = '06'; underlying = 'Get-Ctc06Pane1Timeline'; shape = @('header', 'lines', 'flags') }
)

# The recompute / counterfactual entrypoints LRAP must NEVER reach (noun fragments; matched against the public
# surface). These live (prefixed) inside the nested import but are never re-exported.
$script:LrapExcludedRecompute = @('Counterfactual', 'CompileWorker', 'PacketDiff', 'Python')

function _LrapHasMember {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject -and $null -ne $Object.PSObject.Properties[$Name])
}

# ---- the pinned wrappers (thin; each delegates to exactly one 06/07 pure reader) ----

function Read-LrapPacket { [CmdletBinding()] param([Parameter(Mandatory)][string]$Path) return (Read-Ctc06ContextPacket -Path $Path) }
function Get-LrapRouterBracket { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Get-Att07RouterTournament -Packet $Packet) }
function Get-LrapSelectionBracket { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Get-Att07SelectionTournament -Packet $Packet) }
function Test-LrapTraceSanitized { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Test-Ctc06TraceSanitized -Packet $Packet) }
function Get-LrapRawModelView { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Get-Ctc06Pane2ModelView -Packet $Packet) }
function Get-LrapRawRetrievalTrace { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Get-Ctc06Pane3RetrievalTrace -Packet $Packet) }
function Get-LrapRawRuleStack { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Get-Ctc06Pane4RuleStack -Packet $Packet) }
function Get-LrapRawLedger { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Get-Ctc06Pane6TokenLedger -Packet $Packet) }
function Get-LrapRawStageTimeline { [CmdletBinding()] param([Parameter(Mandatory)]$Packet) return (Get-Ctc06Pane1Timeline -Packet $Packet) }

function Get-LrapAdapterInfo {
    # The adapter's pinned identity: version + the reader surface + the excluded recompute set.
    return [pscustomobject]@{
        adapter_version = $script:LrapAdapterVersion
        widget06_core   = $script:Lrap06Psm1
        widget07_core   = $script:Lrap07Psm1
        pinned_readers  = $script:LrapPinnedReaders
        excluded_recompute = $script:LrapExcludedRecompute
    }
}

function Test-LrapAdapterContract {
    <#
        The CROSS-WIDGET CONTRACT TEST (design s5 / F8). Asserts, over a real sample packet:
          (1) every pinned underlying 06/07 reader still EXISTS and returns a result carrying its pinned members
              (a shape drift in 06/07 -> a failed check here, BEFORE it silently mis-renders a run);
          (2) the recompute / counterfactual entrypoints are NOT in the adapter's public surface.
        Returns { ok, checks[], drift[], excluded_ok, excluded_leaks[] }. Never throws.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SamplePacketPath)

    $checks = New-Object System.Collections.Generic.List[object]
    $drift = New-Object System.Collections.Generic.List[string]

    $rd = $null
    try { $rd = Read-LrapPacket -Path $SamplePacketPath } catch { }
    $packetOk = ($null -ne $rd -and $rd.ok -and $null -ne $rd.packet)
    [void]$checks.Add([pscustomobject]@{ name = 'sample packet loads via adapter'; ok = $packetOk })
    if (-not $packetOk) { [void]$drift.Add('sample packet did not load through Read-LrapPacket') }

    $pkt = if ($packetOk) { $rd.packet } else { $null }

    foreach ($pin in $script:LrapPinnedReaders) {
        $exists = [bool](Get-Command $pin.underlying -ErrorAction SilentlyContinue)
        if (-not $exists) { [void]$checks.Add([pscustomobject]@{ name = ('underlying exists: ' + $pin.underlying); ok = $false }); [void]$drift.Add('missing 06/07 function: ' + $pin.underlying); continue }

        # call the WRAPPER (which proves both the wrapper and the underlying) over the sample + assert shape
        $result = $null; $callOk = $false
        try {
            switch ($pin.wrapper) {
                'Read-LrapPacket' { $result = Read-LrapPacket -Path $SamplePacketPath }
                'Test-LrapTraceSanitized' { $result = Test-LrapTraceSanitized -Packet $pkt }
                default { $result = & $pin.wrapper -Packet $pkt }
            }
            $callOk = $true
        }
        catch { [void]$drift.Add($pin.wrapper + ' threw: ' + $_.Exception.Message) }

        $shapeOk = $callOk -and ($null -ne $result)
        if ($shapeOk) {
            foreach ($m in $pin.shape) {
                if (-not (_LrapHasMember $result $m)) { $shapeOk = $false; [void]$drift.Add($pin.wrapper + ' result missing member "' + $m + '" (06/07 shape drift)') }
            }
        }
        [void]$checks.Add([pscustomobject]@{ name = ('reader shape ok: ' + $pin.wrapper + ' <- ' + $pin.underlying); ok = $shapeOk })
    }

    # (2) recompute entrypoints must NOT be in the adapter's public surface
    $selfModule = $ExecutionContext.SessionState.Module
    $public = @()
    if ($null -ne $selfModule) { $public = @($selfModule.ExportedFunctions.Keys | ForEach-Object { [string]$_ }) }
    $leaks = New-Object System.Collections.Generic.List[string]
    foreach ($n in $public) {
        foreach ($frag in $script:LrapExcludedRecompute) {
            if ($n -like ('*' + $frag + '*')) { [void]$leaks.Add($n) }
        }
    }
    $excludedOk = ($leaks.Count -eq 0)
    [void]$checks.Add([pscustomobject]@{ name = 'recompute entrypoints excluded from public surface'; ok = $excludedOk })
    if (-not $excludedOk) { foreach ($l in $leaks) { [void]$drift.Add('recompute entrypoint leaked into adapter surface: ' + $l) } }

    $ok = ($drift.Count -eq 0) -and (@($checks | Where-Object { -not $_.ok }).Count -eq 0)
    return [pscustomobject]@{
        ok = $ok
        checks = $checks.ToArray()
        drift = $drift.ToArray()
        excluded_ok = $excludedOk
        excluded_leaks = $leaks.ToArray()
    }
}

Export-ModuleMember -Function `
    Read-LrapPacket, Get-LrapRouterBracket, Get-LrapSelectionBracket, Test-LrapTraceSanitized, `
    Get-LrapRawModelView, Get-LrapRawRetrievalTrace, Get-LrapRawRuleStack, Get-LrapRawLedger, `
    Get-LrapRawStageTimeline, Get-LrapAdapterInfo, Test-LrapAdapterContract
