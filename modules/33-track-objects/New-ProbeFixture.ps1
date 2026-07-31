#requires -Version 7.0
<#
.SYNOPSIS
  Identity-LABELED probe-fixture generator for track.objects (Life Orchestrator, skill 0.2.0).
.DESCRIPTION
  Hand-authored, deterministic fixture set for the frontier design review's "first probe"
  (core-docs/research/2026-07-30-track-objects-design-review.md): tiny detection sequences in the
  detect.objects #16 shape PLUS per-frame integer-ms timestamps, a scenes[] list, and a ground-truth
  identity 'label' on every detection (an extra field the tracker ignores). tests/Invoke-TrackObjectsProbe.ps1
  runs -Mode greedy vs -Mode stable over every fixture and scores false_merges / id_switches /
  fragments_per_object / correct_links against these labels. Pure PowerShell, no binary, byte-identical
  regeneration in the cloud and on the Windows executor.

  Fixtures (tuned for the 0.2.0 stable defaults: iou>=0.3, max_gap_ms 5000, max_missed_samples 3,
  centroid base 0.25 + 0.25/s capped 1.0, max_area_ratio 4.0):
    * static          -- one static object; both modes keep ONE track.
    * zero_iou_move   -- one object whose 41 px step over 1200 ms gaps yields IoU 0 between consecutive
                         samples; greedy fragments into 5 tracks, stable links all 5 via the gated
                         centroid fallback (norm disp 0.525 <= allowance 0.55).
    * crossing        -- a same-class crossing engineered so greedy's IoU-descending tie-break consumes
                         the WRONG detection (a false merge) while global assignment (max cardinality)
                         resolves both identities correctly.
    * occlusion_miss  -- a near-static object with one missed sample; both modes re-link; stable records
                         a first-class gap (reacquired_by iou) instead of fabricating a coast box.
    * camera_shift    -- every box translates +60 px at one sample (pan); the fallback's hard allowance
                         cap correctly REFUSES the jump in both directions: fragmentation, NO false merge
                         (camera-motion compensation is a named follow-on).
    * zoom_reframe    -- (a) a gentle concentric zoom that stays IoU-linkable; (b) a vanished 40x40 object
                         with a nearby NEW 10x10 object whose displacement would pass the centroid gate but
                         whose 16x area ratio the cross-multiplied sanity gate REJECTS.
    * scene_cut       -- a static box across a HARD cut at 2000 ms; ground truth says the identity ENDS at
                         the cut; stable terminates (scene_boundary) + births a new id; greedy false-merges
                         straight across the cut.
    * label_flip      -- one physical object whose class flips car->truck; exact-class matching fragments
                         it in both modes (the review's accepted trade), never merges.
    * long_gap        -- a 6500 ms within-scene absence (> max_gap_ms); ground truth says identity is NOT
                         recoverable; stable terminates (max_gap) + births a new id; greedy's frame-count
                         aging is blind to elapsed time and false-merges across 6.5 s.
    * moderate_gap    -- a moving object missed for two samples (1500 ms); reappears displaced 42 px
                         (IoU 0); stable re-links via the time-grown centroid allowance (ONE track, a gap
                         record) while greedy ages out and fragments -- the within-scene moderate-gap win.
  Emits one JSON line to stdout: { ok, dir, tuned_for{...}, fixtures{name:path,...} }.
.EXAMPLE
  pwsh -NoProfile -File .\New-ProbeFixture.ps1 -OutputDir .\probe-fx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

function New-Det([string]$class, [int]$classId, [double]$score, [int]$x, [int]$y, [int]$w, [int]$h, [string]$label) {
    return [ordered]@{
        class = $class; class_id = $classId; score = $score
        box = [ordered]@{ x = $x; y = $y; width = $w; height = $h }
        label = $label
    }
}
function New-Frame([int]$frame, [int]$tsMs, [object[]]$dets, $sceneIndex = $null) {
    $f = [ordered]@{ frame = $frame; timestamp_ms = $tsMs; detections = @($dets) }
    if ($null -ne $sceneIndex) { $f['scene_index'] = [int]$sceneIndex }
    return $f
}
function New-Scene([int]$index, [double]$startS, [double]$endS) {
    return [ordered]@{ index = $index; start = $startS; end = $endS; score = 0.9 }
}
function Write-Fixture([string]$name, [object]$doc) {
    $path = Join-Path $OutputDir "$name.json"
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 20), $utf8)
    return (Resolve-Path -LiteralPath $path).Path
}

$fixtures = [ordered]@{}

# ---- static: one static object, 5 samples @500 ms ----
$frames = @()
for ($i = 0; $i -lt 5; $i++) {
    $frames += , (New-Frame $i (500 * $i) @( (New-Det 'obj' 1 0.9 100 100 40 40 'A') ))
}
$fixtures['static'] = Write-Fixture 'static' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 3.0) ) })

# ---- zero_iou_move: 41 px steps over 1200 ms gaps (IoU 0; norm disp 0.525 <= allowance 0.55) ----
$frames = @()
$xs = @(40, 81, 122, 163, 204)
for ($i = 0; $i -lt 5; $i++) {
    $frames += , (New-Frame $i (1200 * $i) @( (New-Det 'obj' 1 0.9 $xs[$i] 50 40 40 'A') ))
}
$fixtures['zero_iou_move'] = Write-Fixture 'zero_iou_move' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 6.0) ) })

# ---- crossing: the greedy order-dependence trap (all pair IoUs equal 760/2440) ----
# Truth: A moves left 0 -> -21 -> -42; B moves left 42 -> 21 -> 0. At each step the WRONG pair ties the
# RIGHT pairs on IoU and greedy's det-order tie-break takes it; global assignment must keep both.
$frames = @(
    (New-Frame 0 0    @( (New-Det 'obj' 1 0.9 0 20 40 40 'A'), (New-Det 'obj' 1 0.9 42 20 40 40 'B') )),
    (New-Frame 1 400  @( (New-Det 'obj' 1 0.9 21 20 40 40 'B'), (New-Det 'obj' 1 0.9 -21 20 40 40 'A') )),
    (New-Frame 2 800  @( (New-Det 'obj' 1 0.9 0 20 40 40 'B'), (New-Det 'obj' 1 0.9 -42 20 40 40 'A') ))
)
$fixtures['crossing'] = Write-Fixture 'crossing' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 2.0) ) })

# ---- occlusion_miss: near-static, one missed sample; re-link by IoU + a first-class gap record ----
$frames = @(
    (New-Frame 0 0    @( (New-Det 'obj' 1 0.9 200 100 40 40 'A') )),
    (New-Frame 1 400  @( (New-Det 'obj' 1 0.9 205 100 40 40 'A') )),
    (New-Frame 2 800  @()),
    (New-Frame 3 1200 @( (New-Det 'obj' 1 0.9 215 100 40 40 'A') )),
    (New-Frame 4 1600 @( (New-Det 'obj' 1 0.9 220 100 40 40 'A') ))
)
$fixtures['occlusion_miss'] = Write-Fixture 'occlusion_miss' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 2.0) ) })

# ---- camera_shift: +60 px pan at sample 2; the capped fallback refuses; fragmentation, no merge ----
$frames = @(
    (New-Frame 0 0    @( (New-Det 'obj' 1 0.9 50 50 40 40 'P'),  (New-Det 'obj' 1 0.9 300 50 40 40 'Q') )),
    (New-Frame 1 400  @( (New-Det 'obj' 1 0.9 60 50 40 40 'P'),  (New-Det 'obj' 1 0.9 310 50 40 40 'Q') )),
    (New-Frame 2 800  @( (New-Det 'obj' 1 0.9 130 50 40 40 'P'), (New-Det 'obj' 1 0.9 380 50 40 40 'Q') )),
    (New-Frame 3 1200 @( (New-Det 'obj' 1 0.9 140 50 40 40 'P'), (New-Det 'obj' 1 0.9 390 50 40 40 'Q') ))
)
$fixtures['camera_shift'] = Write-Fixture 'camera_shift' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 2.0) ) })

# ---- zoom_reframe: (a) gentle concentric zoom Z stays tier-1-linkable; (b) A2 vanishes and a 10x10 B2
#      appears nearby -- displacement passes (0.281 <= 0.35) but the 16x area ratio is REJECTED ----
$frames = @(
    (New-Frame 0 0    @( (New-Det 'obj' 1 0.9 100 300 40 40 'Z'), (New-Det 'obj' 1 0.9 100 100 40 40 'A2') )),
    (New-Frame 1 400  @( (New-Det 'obj' 1 0.9 96 296 48 48 'Z'),  (New-Det 'obj' 1 0.9 145 115 10 10 'B2') )),
    (New-Frame 2 800  @( (New-Det 'obj' 1 0.9 92 292 56 56 'Z'),  (New-Det 'obj' 1 0.9 146 115 10 10 'B2') ))
)
$fixtures['zoom_reframe'] = Write-Fixture 'zoom_reframe' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 2.0) ) })

# ---- scene_cut: static box across a HARD cut at 2000 ms; identity ENDS at the cut (labels S1 -> S2) ----
$frames = @()
foreach ($t in @(0, 500, 1000, 1500)) { $frames += , (New-Frame ([int]($t / 500)) $t @( (New-Det 'obj' 1 0.9 400 200 40 40 'S1') )) }
foreach ($t in @(2000, 2500, 3000)) { $frames += , (New-Frame ([int]($t / 500)) $t @( (New-Det 'obj' 1 0.9 400 200 40 40 'S2') )) }
$fixtures['scene_cut'] = Write-Fixture 'scene_cut' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 2.0), (New-Scene 1 2.0 3.5) ) })

# ---- label_flip: one physical object (label F) whose class flips car -> truck; fragments, never merges ----
$frames = @(
    (New-Frame 0 0    @( (New-Det 'car' 2 0.9 500 50 40 40 'F') )),
    (New-Frame 1 400  @( (New-Det 'car' 2 0.9 505 50 40 40 'F') )),
    (New-Frame 2 800  @( (New-Det 'truck' 7 0.9 510 50 40 40 'F') )),
    (New-Frame 3 1200 @( (New-Det 'truck' 7 0.9 515 50 40 40 'F') ))
)
$fixtures['label_flip'] = Write-Fixture 'label_flip' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 2.0) ) })

# ---- long_gap: a 6500 ms within-scene absence (> max_gap_ms 5000); identity NOT recoverable (L -> L2) ----
$frames = @(
    (New-Frame 0 0    @( (New-Det 'obj' 1 0.9 600 400 40 40 'L') )),
    (New-Frame 1 500  @( (New-Det 'obj' 1 0.9 605 400 40 40 'L') )),
    (New-Frame 2 7000 @( (New-Det 'obj' 1 0.9 610 400 40 40 'L2') )),
    (New-Frame 3 7500 @( (New-Det 'obj' 1 0.9 615 400 40 40 'L2') ))
)
$fixtures['long_gap'] = Write-Fixture 'long_gap' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 8.0) ) })

# ---- moderate_gap: missed for two samples (1500 ms), reappears displaced 42 px (IoU 0); the time-grown
#      allowance (0.25 + 0.375 = 0.625 >= 0.551) re-links it; greedy's MaxAge 2 ages out + fragments ----
$frames = @(
    (New-Frame 0 0    @( (New-Det 'obj' 1 0.9 40 60 40 40 'M') )),
    (New-Frame 1 500  @( (New-Det 'obj' 1 0.9 55 60 40 40 'M') )),
    (New-Frame 2 1000 @()),
    (New-Frame 3 1500 @()),
    (New-Frame 4 2000 @( (New-Det 'obj' 1 0.9 97 60 40 40 'M') )),
    (New-Frame 5 2500 @( (New-Det 'obj' 1 0.9 112 60 40 40 'M') ))
)
$fixtures['moderate_gap'] = Write-Fixture 'moderate_gap' ([ordered]@{ frames = $frames; scenes = @( (New-Scene 0 0.0 3.0) ) })

[Console]::Out.WriteLine(([ordered]@{
    ok = $true
    dir = (Resolve-Path -LiteralPath $OutputDir).Path
    tuned_for = [ordered]@{
        mode = 'stable'; iou_threshold = 0.3; max_gap_ms = 5000; max_missed_samples = 3
        centroid_base_allowance = 0.25; centroid_allowance_per_second = 0.25; centroid_max_allowance = 1.0
        max_area_ratio = 4.0; greedy_max_age = 2
    }
    fixtures = $fixtures
} | ConvertTo-Json -Depth 6 -Compress))
exit 0
