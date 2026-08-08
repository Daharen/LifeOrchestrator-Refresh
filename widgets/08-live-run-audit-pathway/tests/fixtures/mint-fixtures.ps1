<#
    mint-fixtures.ps1 -- deterministically mint the FIVE Live-Run Audit Pathway acceptance fixtures from two
    REAL #40 context_packet/0.2 seeds (the shipped widget-06/07 routed + flat compile artifacts).

    Each fixture is a real/minted #40 artifact carrying EXACTLY ONE injected condition, and each defect is
    machine-detectable from an EXISTING reconciliation identity (no smuggled semantic judgment):

      clean_routed.json           -- the routed seed, verbatim (valid run; must classify CONSISTENT).
      defect_mis_route.json       -- step 3: a routing_stage_trace chain break (out[n] != in[n+1]); every
                                     round's own in-removed==out still reconciles, so ONLY the chain breaks.
      defect_dropped_candidate.json-- step 4: a candidate present in raw_retrieval + retrieved[] but ABSENT
                                     from post_filter with NO omit_reason (MISSING, not "unjustified").
      defect_wrong_record.json    -- step 6: a record the current_only rule FIRED against (reason_codes carry
                                     hard_filter_stale) is STILL PRESENT in the packet (rule-fired AND present).
      quirk_flat.json             -- the flat (no-router) seed, verbatim (a legitimate flat compile that drops
                                     step 3; must NOT be false-flagged).

    This script is shipped for PROVENANCE + reproducibility (audit-pipeline 3.5: each breakpoint is a candidate
    #37 fixture). The committed fixtures are its STATIC outputs; the gate reads the static files, never re-mints.
    ASCII-only source (the 5.1-ANSI/BOM lesson). Run: pwsh -NoProfile -File mint-fixtures.ps1
#>
[CmdletBinding()]
param([string]$OutDir = $PSScriptRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Json([string]$Path) { (Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json -Depth 90 }
function Write-Json($Obj, [string]$Path) {
    $json = $Obj | ConvertTo-Json -Depth 90
    # LF, UTF-8 no BOM (project rule); deterministic
    $json = ($json -replace "`r`n", "`n")
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  wrote " + (Split-Path $Path -Leaf) + " (" + $json.Length + " chars)")
}
function Clone-Packet($Obj) { $Obj | ConvertTo-Json -Depth 90 | ConvertFrom-Json -Depth 90 }

$seedRouted = Join-Path $OutDir '_seed_routed.json'
$seedFlat = Join-Path $OutDir '_seed_flat.json'
if (-not (Test-Path -LiteralPath $seedRouted)) { throw "seed missing: $seedRouted" }
if (-not (Test-Path -LiteralPath $seedFlat)) { throw "seed missing: $seedFlat" }

$routed = Read-Json $seedRouted
$flat = Read-Json $seedFlat

# ---- 1. clean_routed.json (verbatim routed seed) ----
Write-Json (Clone-Packet $routed) (Join-Path $OutDir 'clean_routed.json')

# ---- 2. defect_mis_route.json (step-3 chain break) ----
$c = Clone-Packet $routed
$trace = $c.evaluation_hooks.routing_stage_trace
# classification emits out=4; make the routing round claim 5 in (chain break), keep its own count reconciling
$trace[1].candidates_in = 5     # routing: was 4  -> chain break vs classification.out=4
$trace[1].candidates_out = 3    # 5 - 2 removed == 3 (own count reconciles)
$trace[2].candidates_in = 3     # channel_selection: matches routing.out=3 (chain ok here)
$trace[2].candidates_out = 3    # 3 - 0 removed == 3 (own count reconciles)
Write-Json $c (Join-Path $OutDir 'defect_mis_route.json')

# ---- 3. defect_dropped_candidate.json (step-4 unexplained drop) ----
$c = Clone-Packet $routed
$orphan = 'occ_dropped_orphan_a1b2c3d4'
# add to raw_retrieval (it was retrieved) ...
$raw = @($c.evaluation_hooks.stages.raw_retrieval)
$raw += [pscustomobject]@{ record_version_id = $orphan; retrieval_rank = 4 }
$c.evaluation_hooks.stages.raw_retrieval = $raw
# ... and to retrieved[] so step-2 (retrieved count == raw count) still reconciles; NO omit_reason recorded
$ret = @($c.evaluation_hooks.retrieved)
$ret += [pscustomobject]@{
    record_id = 'srec_dropped_orphan'; record_kind = 'source_chunk'; record_version_id = $orphan
    retrieval_rank = 4; fused_rank = 4; lexical_rank = 4; vector_rank = $null
    selection_rank = 9999; selection_score = 0; selected = $true; included = $false
    omit_reason = $null; currentness = 'current'; epistemic_authority = 'source_material'
    reason_codes = @('fusion_rrf'); source_content_hash = 'deadbeef'; source_path = 'core-docs/alpha.md'
}
$c.evaluation_hooks.retrieved = $ret
# keep the retrieved-count readouts consistent with the new raw count (7)
$c.retrieval_provenance.candidate_count = 7
$c.evaluation_hooks.packet_metrics.candidate_count = 7
# NB: NOT added to post_filter / packet / selected_record_version_ids / excerpts -> a raw candidate absent
# from post with no omit_reason. selection subset chain (packet<=post<=raw) still holds.
Write-Json $c (Join-Path $OutDir 'defect_dropped_candidate.json')

# ---- 4. defect_wrong_record.json (step-6 rule-fired-yet-present) ----
$c = Clone-Packet $routed
$victim = 'occ_d73b3615a58ba5f1ab226020'   # selection_rank 6; present in packet/post/selected/excerpts
# mark it HARD-filtered by the current_only rule (the rule FIRED against it) in features_by_candidate ...
$f = $c.selection.features_by_candidate.$victim
$f.reason_codes = @('hard_filter_stale')
$f.hard_demote = $true; $f.is_stale = $true; $f.not_current = $true; $f.stale = $true
# ... and in the retrieved[] mirror, so the exclusion verdict is visible from either substrate array
foreach ($r in $c.evaluation_hooks.retrieved) {
    if ([string]$r.record_version_id -eq $victim) { $r.reason_codes = @('hard_filter_stale'); $r.currentness = 'stale' }
}
# it REMAINS in stages.packet / stages.post_filter / identity.selected_record_version_ids / evidence.excerpts
# (that is the defect: a record the current_only rule fired against is still present in the packet).
Write-Json $c (Join-Path $OutDir 'defect_wrong_record.json')

# ---- 5. quirk_flat.json (verbatim flat seed) ----
Write-Json (Clone-Packet $flat) (Join-Path $OutDir 'quirk_flat.json')

Write-Host 'mint-fixtures: done (5 fixtures).'
