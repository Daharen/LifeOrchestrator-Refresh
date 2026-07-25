#requires -Version 7.0
# mock-child.ps1 -- a single stand-in for the image.index children (capture.screen / image.util / ocr.layout /
# detect.objects / image.interpret) for OFF-GPU logic tests. It branches on the -ArtifactRoot LEAF name that
# image.index assigns per stage (capture|image_util|ocr|detect|interpret) and emits a valid
# lifeorch.skill.result/0.1 envelope so the REAL Invoke-ImageIndex.ps1 fuse/aggregate/redirect/envelope logic runs
# unchanged on the cloud box. The capture branch writes a real 1x1 PNG; the image_util branch emits a real sha256 of
# its input + canned meta/hashes; the ocr/detect/interpret branches also append one review item to the passed
# review_queue_path so the child-review REDIRECT is exercised (image.index is not itself a producer).
[CmdletBinding()]
param([string]$InputsJson, [string]$ArtifactRoot, [string]$InvocationId)
$ErrorActionPreference = 'Continue'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$id = if ([string]::IsNullOrWhiteSpace($InvocationId)) { [Guid]::NewGuid().ToString() } else { $InvocationId }
$root = if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { Join-Path ([IO.Path]::GetTempPath()) 'mockchild' } else { $ArtifactRoot }
$dir = Join-Path $root $id
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$stage = (Split-Path -Leaf $ArtifactRoot)
$p = $null; if (-not [string]::IsNullOrWhiteSpace($InputsJson)) { try { $p = $InputsJson | ConvertFrom-Json } catch { } }
function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
function Prop($o,[string]$n,$d=$null){ if (Has $o $n) { return $o.$n } return $d }
$nowo = [DateTime]::UtcNow.ToString('o')

function Emit($result,$conf,$prov){
    $env = [ordered]@{ schema='lifeorch.skill.result/0.1'; skill_id="mock.$stage"; skill_version='0.1.0'; contract_version='0.1';
        invocation_id=$id; status='ok'; started_at_utc=$nowo; finished_at_utc=$nowo; duration_ms=1;
        inputs_digest=('sha256:'+('0'*64)); result=$result; confidence=$conf; artifacts=@(); model_provenance=$prov;
        diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$dir }; warnings=@(); error=$null }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 15))
}
function Write-Review($flaggedBy,$reason,$conf,$requested){
    $rq = [string](Prop $p 'review_queue_path' '')
    if ([string]::IsNullOrWhiteSpace($rq)) { return }
    $item = [ordered]@{ schema='lifeorch.review.item/0.1'; id="rq-mock-$stage"; created_at_utc=$nowo; flagged_by=$flaggedBy;
        reason=$reason; confidence=$conf; source_ref="artifact://$dir"; requested=$requested; status='open'; resolution=$null; escalated_to=$null }
    try { [System.IO.File]::AppendAllText($rq, (($item | ConvertTo-Json -Compress -Depth 6) + "`n"), $utf8) } catch { }
}
function Get-Sha256HexFile([string]$path){
    try { $b=[System.IO.File]::ReadAllBytes($path); $s=[System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($s.ComputeHash($b))).Replace('-','').ToLowerInvariant() } finally { $s.Dispose() } } catch { return ('0'*64) }
}

switch ($stage) {
    'capture' {
        # write a real 1x1 PNG the downstream stages can read
        $png = Join-Path $dir 'capture.png'
        $bytes = [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,0xDE,
            0x00,0x00,0x00,0x0C,0x49,0x44,0x41,0x54,0x08,0xD7,0x63,0xF8,0xCF,0xC0,0x00,0x00,0x00,0x03,0x01,0x01,0x00,0x18,0xDD,0x8D,0xB0,
            0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82)
        [System.IO.File]::WriteAllBytes($png, $bytes)
        Emit ([ordered]@{ capture=[ordered]@{ path=$png; image_width=800; image_height=600; format='png' }; target='monitor' }) $null @()
    }
    'image_util' {
        $inPath = [string](Prop $p 'input' '')
        $sha = if (-not [string]::IsNullOrWhiteSpace($inPath) -and (Test-Path -LiteralPath $inPath -PathType Leaf)) { Get-Sha256HexFile $inPath } else { ('0'*64) }
        $meta = [ordered]@{ format='PNG'; mode='RGB'; width=800; height=600; has_alpha=$false; dpi=$null; n_frames=1 }
        $hashes = [ordered]@{ sha256=$sha; phash='c3c3c3c3c3c3c3c3'; dhash='0f0f0f0f0f0f0f0f' }
        Emit ([ordered]@{ input=[ordered]@{ path=$inPath; bytes=0; sha256=$sha }; op='meta'; metadata=$meta; hashes=$hashes; outputs=@() }) $null @()
    }
    'ocr' {
        Write-Review 'ocr.layout' 'low_confidence' 0.9 'verify_ocr'
        $box = [ordered]@{ x=10; y=20; width=300; height=40 }
        $lines = @([ordered]@{ index=0; text='HELLO WORLD'; confidence=0.9; low_confidence=$false; bounding_rect=$box; words=@() })
        $res = [ordered]@{ text='HELLO WORLD'; word_count=2; line_count=1; lines=$lines;
            image=[ordered]@{ width=800; height=600; text_angle=0.0 }; confidence=[ordered]@{ overall=0.9; min_line=0.9; low_confidence_lines=0; reason='legible' } }
        $prov = @([ordered]@{ model_id='ocr.windows.media'; name='Windows.Media.Ocr'; engine='windows.media.ocr'; recognizer_language='en-US'; word_count=2; line_count=1 })
        Emit $res 0.9 $prov
    }
    'detect' {
        Write-Review 'detect.objects' 'low_confidence' 0.83 'verify_detections'
        $dets = @(
            [ordered]@{ index=0; class_id=16; class='dog'; score=0.83; low_confidence=$false; box=[ordered]@{ x=60; y=70; width=200; height=250 } },
            [ordered]@{ index=1; class_id=2;  class='car'; score=0.80; low_confidence=$false; box=[ordered]@{ x=300; y=120; width=180; height=140 } }
        )
        $res = [ordered]@{ detection_count=2; class_summary=[ordered]@{ dog=1; car=1 }; detections=$dets;
            confidence=[ordered]@{ overall=0.83; mean=0.815; min=0.80; low_confidence_count=0; reason='ok' } }
        $prov = @([ordered]@{ model_id='detect.yolox.nano'; name='YOLOX-Nano'; engine='onnxruntime'; provider='CPUExecutionProvider'; detection_count=2 })
        Emit $res 0.83 $prov
    }
    'interpret' {
        Write-Review 'image.interpret' 'low_confidence' 0.7 'verify_interpretation'
        $res = [ordered]@{ interpretation=[ordered]@{ text='A dog sitting next to a parked car.'; finish_reason='stop'; prompt_tokens=40; completion_tokens=9; total_tokens=49; timings=$null };
            confidence=[ordered]@{ value=0.7; reason='ok'; refusal=$false }; image=[ordered]@{ width=800; height=600; mime='image/png' }; request=[ordered]@{ mode='describe' } }
        $prov = @([ordered]@{ model_id='vlm.qwen2p5-vl-3b'; name='Qwen2.5-VL-3B-Instruct'; engine='llama-server'; device='cuda:0'; mode='describe'; completion_tokens=9; finish_reason='stop' })
        Emit $res 0.7 $prov
    }
    default {
        # unknown stage: emit a benign ok envelope
        Emit ([ordered]@{ note="mock: unrecognized stage '$stage'" }) $null @()
    }
}
exit 0
