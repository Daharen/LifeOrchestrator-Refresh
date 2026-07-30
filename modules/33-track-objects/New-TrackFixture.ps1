#requires -Version 7.0
<#
.SYNOPSIS
  Deterministic test-fixture generator for track.objects (Life Orchestrator).
.DESCRIPTION
  Builds tiny, reproducible per-frame detection sequences (the detect.objects #16 output shape) as JSON --
  NO external binary, no model, pure PowerShell -- so the same fixtures regenerate byte-identically in the
  cloud and on the Windows executor. Each fixture exercises a tracker lifecycle case:
    * crossing   -- two same-class objects whose paths cross in x at different y (identities stay separate);
    * occlusion  -- one object that vanishes for a frame then reappears nearby (COAST then revive);
    * birth      -- an object that first appears mid-sequence (BIRTH of a new track);
    * death      -- one logical object with a gap longer than the default max_age -> the first track ages
                    out (DEATH) and the reappearance BIRTHS a new id (aged-out => new identity);
    * multiclass -- a car box then an identical person box: per-CLASS matching must NOT merge them;
    * empty      -- frames with no detections (zero tracks);
    * scenario   -- the combined 6-frame clip that contains crossing + occlusion + birth + death together.
  Emits one JSON line to stdout: { ok, dir, tuned_for{iou_threshold,max_age}, fixtures{name:path,...} }.
.EXAMPLE
  pwsh -NoProfile -File .\New-TrackFixture.ps1 -OutputDir .\fx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDir,
    [double]$Fps = 2.0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Assemble a { frames:[{frame,timestamp_s,detections:[{class,class_id,score,box}]}] } document from object
# specs. Each spec: @{ class; class_id; score; w; h; y; xs = @{ <frameIndex> = <x> } }. Detection order
# within a frame follows the spec declaration order (this fixes birth-id assignment deterministically).
function New-Sequence([int]$NumFrames, [object[]]$Objects) {
    $frames = New-Object System.Collections.Generic.List[object]
    for ($f = 0; $f -lt $NumFrames; $f++) {
        $dets = New-Object System.Collections.Generic.List[object]
        foreach ($o in $Objects) {
            if ($o.xs.ContainsKey($f)) {
                $x = [int]$o.xs[$f]
                $dets.Add([ordered]@{
                    class = [string]$o.class
                    class_id = [int]$o.class_id
                    score = [double]$o.score
                    box = [ordered]@{ x = $x; y = [int]$o.y; width = [int]$o.w; height = [int]$o.h }
                })
            }
        }
        $ts = [math]::Round($f / $Fps, 6)
        $frames.Add([ordered]@{ frame = $f; timestamp_s = $ts; detections = $dets.ToArray() })
    }
    return [ordered]@{ frames = $frames.ToArray() }
}

function Write-Fixture([string]$name, [object]$doc) {
    $path = Join-Path $OutputDir "$name.json"
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 20), $utf8)
    return (Resolve-Path -LiteralPath $path).Path
}

$W = 40; $H = 40  # box size; with a 15px/frame step this keeps consecutive-frame IoU ~= 0.45 (>= 0.3)

# --- object paths (box 40, step 15) ---
$carA = @{ class = 'car'; class_id = 2; score = 0.90; w = $W; h = $H; y = 20;  xs = @{ 0 = 20; 1 = 35; 2 = 50; 3 = 65; 4 = 80; 5 = 95 } }
$carB = @{ class = 'car'; class_id = 2; score = 0.85; w = $W; h = $H; y = 190; xs = @{ 0 = 95; 1 = 80; 2 = 65; 3 = 50; 4 = 35; 5 = 20 } }   # crosses A in x, different y
$p1   = @{ class = 'person'; class_id = 0; score = 0.80; w = $W; h = $H; y = 110; xs = @{ 0 = 40; 1 = 55; 3 = 70; 4 = 85; 5 = 100 } }        # gap at frame 2 (occlusion)
$p2   = @{ class = 'person'; class_id = 0; score = 0.70; w = $W; h = $H; y = 110; xs = @{ 1 = 200; 2 = 200 } }                                # born f1, then gone -> dies by f5

$fixtures = [ordered]@{}

# combined scenario: crossing (A,B) + occlusion (P1) + birth+death (P2)
$fixtures['scenario']   = (Write-Fixture 'scenario'   (New-Sequence 6 @($carA, $carB, $p1, $p2)))
# crossing only
$fixtures['crossing']   = (Write-Fixture 'crossing'   (New-Sequence 6 @($carA, $carB)))
# occlusion-coast only (one person, revived across a 1-frame gap)
$fixtures['occlusion']  = (Write-Fixture 'occlusion'  (New-Sequence 6 @($p1)))
# birth mid-sequence: X spans all frames, Y appears at frame 3
$bx = @{ class = 'car'; class_id = 2; score = 0.9; w = $W; h = $H; y = 20; xs = @{ 0 = 20; 1 = 35; 2 = 50; 3 = 65; 4 = 80; 5 = 95 } }
$by = @{ class = 'car'; class_id = 2; score = 0.8; w = $W; h = $H; y = 150; xs = @{ 3 = 100; 4 = 115; 5 = 130 } }
$fixtures['birth']      = (Write-Fixture 'birth'      (New-Sequence 6 @($bx, $by)))
# death + rebirth: one logical object with a gap > max_age(2) -> first track ages out, reappearance = new id
$z = @{ class = 'car'; class_id = 2; score = 0.9; w = $W; h = $H; y = 50; xs = @{ 0 = 50; 1 = 55; 5 = 60 } }
$fixtures['death']      = (Write-Fixture 'death'      (New-Sequence 6 @($z)))
# multiclass: identical box, different class across two frames -> per-class must NOT merge
$mc1 = @{ class = 'car';    class_id = 2; score = 0.9; w = $W; h = $H; y = 100; xs = @{ 0 = 100; 1 = 100 } }
$mc2 = @{ class = 'person'; class_id = 0; score = 0.9; w = $W; h = $H; y = 100; xs = @{ 0 = 100; 1 = 100 } }
$fixtures['multiclass'] = (Write-Fixture 'multiclass' (New-Sequence 2 @($mc1, $mc2)))
# empty: frames with no detections
$fixtures['empty']      = (Write-Fixture 'empty'      (New-Sequence 3 @()))

[Console]::Out.WriteLine(([ordered]@{
    ok = $true
    dir = (Resolve-Path -LiteralPath $OutputDir).Path
    tuned_for = [ordered]@{ iou_threshold = 0.3; max_age = 2 }
    fixtures = $fixtures
} | ConvertTo-Json -Depth 6 -Compress))
exit 0
