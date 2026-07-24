#requires -Version 7.0
# mock-child.ps1 — a single stand-in for the three voice.live children (speech.stt / model.gateway /
# speech.tts) for OFF-GPU logic tests. It branches on the child-specific InputsJson keys and emits a valid
# lifeorch.skill.result/0.1 envelope (and, for the tts branch, writes a real minimal PCM16 WAV) so the REAL
# Invoke-VoiceLive.ps1 pipeline/parse/aggregate/envelope logic runs unchanged on the cloud box.
#   input  key present -> STT branch  (env: MOCK_STT_NOSPEECH -> zero segments)
#   prompt key present -> gateway branch
#   text   key present -> tts branch  (writes speech.wav)
[CmdletBinding()]
param([string]$InputsJson, [string]$ArtifactRoot, [string]$InvocationId)
$ErrorActionPreference = 'Continue'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$id = if ([string]::IsNullOrWhiteSpace($InvocationId)) { [Guid]::NewGuid().ToString() } else { $InvocationId }
$root = if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { Join-Path ([IO.Path]::GetTempPath()) 'mockchild' } else { $ArtifactRoot }
$dir = Join-Path $root $id
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$p = $null; if (-not [string]::IsNullOrWhiteSpace($InputsJson)) { try { $p = $InputsJson | ConvertFrom-Json } catch { } }
function Has($o,[string]$n){ return ($null -ne $o -and $null -ne $o.PSObject -and ($o.PSObject.Properties.Name -contains $n)) }
$nowo = [DateTime]::UtcNow.ToString('o')

function Emit($result,$conf,$prov){
    $env = [ordered]@{ schema='lifeorch.skill.result/0.1'; skill_id='mock.child'; skill_version='0.1.0'; contract_version='0.1';
        invocation_id=$id; status='ok'; started_at_utc=$nowo; finished_at_utc=$nowo; duration_ms=1;
        inputs_digest=('sha256:'+('0'*64)); result=$result; confidence=$conf; artifacts=@(); model_provenance=$prov;
        diagnostics=[ordered]@{ log='stderr.txt'; artifact_dir=$dir }; warnings=@(); error=$null }
    [Console]::Out.WriteLine(($env | ConvertTo-Json -Depth 12))
}

if (Has $p 'prompt') {
    # gateway branch
    $prov = @([ordered]@{ model_id='llm.weak.qwen2p5-1p5b'; engine='llama-server'; finish_reason='stop' })
    Emit ([ordered]@{ model='llm.weak.qwen2p5-1p5b'; engine='llama-server'; output=[ordered]@{ role='assistant'; text='The capital of France is Paris.' }; generation=[ordered]@{ finish_reason='stop'; completion_tokens=7 } }) 0.7 $prov
}
elseif (Has $p 'text') {
    # tts branch — write a real 0.1s 24 kHz mono PCM16 WAV
    $wav = Join-Path $dir 'speech.wav'
    $sr = 24000; $n = 2400; $dataLen = $n * 2; $riffLen = 36 + $dataLen
    $fs = [System.IO.File]::Open($wav, [System.IO.FileMode]::Create)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $asc = [System.Text.Encoding]::ASCII
    $bw.Write($asc.GetBytes('RIFF')); $bw.Write([int]$riffLen); $bw.Write($asc.GetBytes('WAVE'))
    $bw.Write($asc.GetBytes('fmt ')); $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
    $bw.Write([int]$sr); $bw.Write([int]($sr*2)); $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write($asc.GetBytes('data')); $bw.Write([int]$dataLen); $bw.Write((New-Object byte[] $dataLen))
    $bw.Flush(); $bw.Close(); $fs.Close()
    $prov = @([ordered]@{ model_id='tts.weak.qwen3-0p6b'; engine='transformers'; device='cuda:0' })
    Emit ([ordered]@{ audio=[ordered]@{ path=$wav; format='wav'; sample_rate=$sr; channels=1; samples=$n; duration_s=0.1; bytes=($dataLen+44) } }) 0.9 $prov
}
else {
    # stt branch
    $noSpeech = -not [string]::IsNullOrWhiteSpace($env:MOCK_STT_NOSPEECH)
    if ($noSpeech) { $text=''; $segs=0; $conf=$null } else { $text='And so my fellow Americans, ask not what your country can do for you.'; $segs=1; $conf=0.87 }
    @{ schema='lifeorch.stt.transcript/0.1'; text=$text; segment_count=$segs } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'transcript.json') -Encoding utf8
    $prov = @([ordered]@{ model_id='stt.whisper.base-en'; engine='whisper.cpp'; device='cuda:0' })
    Emit ([ordered]@{ text=$text; segment_count=$segs; language='en' }) $conf $prov
}
exit 0
