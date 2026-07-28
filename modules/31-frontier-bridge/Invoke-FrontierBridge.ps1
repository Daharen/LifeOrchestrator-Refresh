#!/usr/bin/env pwsh
<#
.SYNOPSIS
    frontier.bridge (Module 31) -- a deterministic, LOCAL-ONLY, NO-NETWORK context packager.

.DESCRIPTION
    Given a Claude-written prompt + a set of local files (explicit paths / globs, or a folder),
    this skill emits ONE copy-paste "pack": the prompt/instructions, the specific question, every
    included file's content concatenated with clear invocation-tagged delimiters, and a manifest of
    exactly what was included. It also declares a robust return-capture convention: the return file
    carries the pack_id + two ANSWER marker lines, the USER pastes the external model's answer BETWEEN
    the markers, and a second action (`read-return`) parses + VALIDATES that file back for Claude
    (marker extraction, optional pack_id match, and issue reporting; legacy dashed-separator files still
    parse).

    HARD BOUNDARY (DECISION_LOG D-0051 / D-0052): this is OUTBOUND LOCAL PACKAGING ONLY. It NEVER
    submits to, scrapes, or drives ChatGPT or any external AI UI or service. It performs local file
    I/O and nothing else -- no network calls of any kind. The human is the sole courier.

    Contract: SKILL_CONTRACT.md v0.2. Emits one lifeorch.skill.result/0.1 envelope on stdout (and to
    result.json in the artifact dir). Deterministic (confidence:null, no model provenance). Not a
    review-queue producer. parallel_safe (reads inputs; writes only into its own per-invocation
    artifact dir).

.NOTES
    Only file I/O is used. The presence of any network cmdlet in this file is a contract violation and
    is asserted against by tests/Test-FrontierBridge.ps1.
#>
[CmdletBinding()]
param(
    [string]$Action = 'pack',            # pack | read-return
    [string]$Prompt,                     # Claude-written instructions/context (required for pack)
    [string]$Question,                   # the specific question (emphasised at the end of the pack)
    [string[]]$Paths,                    # explicit file paths and/or globs to include
    [string]$Folder,                     # a folder to include
    [string[]]$Include,                  # include globs (folder mode)
    [string[]]$Exclude,                  # exclude globs (folder mode)
    [object]$Recurse,                    # recurse the folder (default true)
    [long]$MaxFileBytes,                 # skip any single file larger than this (default 2,000,000)
    [long]$MaxTotalBytes,                # stop including once the pack exceeds this (default 20,000,000)
    [string]$Title,                      # human title for the pack
    [string]$OutName,                    # base name for the pack file
    [string]$ReturnFile,                 # read-return: the file the user pasted the answer into
    [string]$ExpectPackId,               # read-return: optional pack_id to validate the return file belongs to
    [string]$ArtifactRoot,               # relocate the artifact root (contract 3.1)
    [string]$InputsJson,                 # generic input passing (contract 3.1)
    [string]$WrapperPath                 # (test aid only; unused at runtime)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------------------

function Write-Diag {
    param([string]$Message)
    [Console]::Error.WriteLine("[frontier.bridge] $Message")
}

function Get-UtcNow {
    return [DateTime]::UtcNow.ToString('o')
}

function ConvertTo-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-Sha256HexOfString {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (ConvertTo-Sha256Hex -Bytes $bytes)
}

function ConvertTo-Bool {
    param($Value, [bool]$Default)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }
    $s = "$Value".Trim().ToLowerInvariant()
    if ($s -in @('true', '1', 'yes', 'y', 'on'))  { return $true }
    if ($s -in @('false', '0', 'no', 'n', 'off')) { return $false }
    return $Default
}

function ConvertTo-StringArray {
    param($Value)
    $out = New-Object 'System.Collections.Generic.List[string]'
    if ($null -ne $Value) {
        if ($Value -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($Value)) { $out.Add($Value) }
        } else {
            foreach ($v in $Value) {
                if ($null -eq $v) { continue }
                $s = "$v"
                if (-not [string]::IsNullOrWhiteSpace($s)) { $out.Add($s) }
            }
        }
    }
    # unary comma prevents the pipeline from unwrapping an empty/1-element array
    return ,$out.ToArray()
}

# Resolve one logical input from (named param) -> (InputsJson key) -> (default).
function Resolve-Input {
    param(
        [System.Collections.IDictionary]$Bound,
        [System.Collections.IDictionary]$Ij,
        [string]$Param,
        [string]$Key,
        $Default
    )
    if ($null -ne $Bound -and $Bound.ContainsKey($Param)) { return $Bound[$Param] }
    if ($null -ne $Ij -and $Ij.ContainsKey($Key))         { return $Ij[$Key] }
    return $Default
}

# Detect whether a byte buffer looks like binary (NUL byte in the sampled prefix).
function Test-IsBinary {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return $false }
    $limit = [Math]::Min($Bytes.Length, 8000)
    for ($i = 0; $i -lt $limit; $i++) {
        if ($Bytes[$i] -eq 0) { return $true }
    }
    return $false
}

# Decode bytes to text honouring a BOM if present; default UTF-8 (no BOM).
function ConvertFrom-FileBytes {
    param([byte[]]$Bytes)
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return @{ text = [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3); encoding = 'utf-8-bom' }
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return @{ text = [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2); encoding = 'utf-16-le' }
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return @{ text = [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2); encoding = 'utf-16-be' }
    }
    return @{ text = [System.Text.Encoding]::UTF8.GetString($Bytes); encoding = 'utf-8' }
}

# Write text as UTF-8 without BOM.
function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function New-FileArtifact {
    param([string]$Path, [string]$Kind)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return [ordered]@{
        path   = (Resolve-Path -LiteralPath $Path).ProviderPath
        kind   = $Kind
        bytes  = $bytes.Length
        sha256 = (ConvertTo-Sha256Hex -Bytes $bytes)
    }
}

# Parse a frontier.bridge return file into { format, pack_id, answer, markers_found, end_found }.
#   format: 'answer-markers' (current) | 'legacy-separator' (old dashed stub) | 'raw' (no recognised structure).
# The answer is the text BETWEEN the two ANSWER marker lines; falls back to the old 80-dash convention,
# then to a raw read (leading HTML-comment / blank lines dropped). Pure string work -- no network.
function ConvertFrom-ReturnFile {
    param([string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $packId = $null
    $pm = [regex]::Match($Text, '(?im)^\s*<!--\s*pack_id:\s*(\S+)\s*-->')
    if ($pm.Success) { $packId = $pm.Groups[1].Value }

    $bm = [regex]::Match($Text, '(?im)^<<<FRONTIER-BRIDGE-ANSWER-BEGIN\b.*$')
    if ($bm.Success) {
        $afterBegin = $Text.Substring($bm.Index + $bm.Length)
        $em = [regex]::Match($afterBegin, '(?im)^<<<FRONTIER-BRIDGE-ANSWER-END\b.*$')
        $answer = if ($em.Success) { $afterBegin.Substring(0, $em.Index) } else { $afterBegin }
        return @{ format = 'answer-markers'; pack_id = $packId; answer = $answer; markers_found = $true; end_found = $em.Success }
    }

    $sep = ('-' * 80)
    $idx = $Text.IndexOf($sep)
    if ($idx -ge 0) {
        return @{ format = 'legacy-separator'; pack_id = $packId; answer = $Text.Substring($idx + $sep.Length); markers_found = $false; end_found = $false }
    }

    $keep = New-Object 'System.Collections.Generic.List[string]'
    $started = $false
    foreach ($ln in ($Text -split "`r?`n")) {
        if (-not $started -and ($ln.TrimStart().StartsWith('<!--') -or [string]::IsNullOrWhiteSpace($ln))) { continue }
        $started = $true
        $keep.Add($ln)
    }
    return @{ format = 'raw'; pack_id = $packId; answer = ($keep -join "`n"); markers_found = $false; end_found = $false }
}

# ---------------------------------------------------------------------------------------------------
# Envelope construction / emission
# ---------------------------------------------------------------------------------------------------

$Script:SkillId         = 'frontier.bridge'
$Script:SkillVersion    = '0.1.0'
$Script:ContractVersion = '0.2'
$Script:AnswerBeginPrefix = '<<<FRONTIER-BRIDGE-ANSWER-BEGIN'
$Script:AnswerEndPrefix   = '<<<FRONTIER-BRIDGE-ANSWER-END'

function New-Envelope {
    param(
        [string]$Status,
        [string]$InvocationId,
        [string]$StartedUtc,
        [string]$InputsDigest,
        $Result,
        [object[]]$Artifacts,
        [string[]]$Warnings,
        $ErrorObj,
        [long]$DurationMs
    )
    if ($null -eq $Artifacts) { $Artifacts = @() }
    if ($null -eq $Warnings)  { $Warnings  = @() }
    return [ordered]@{
        schema           = 'lifeorch.skill.result/0.1'
        skill_id         = $Script:SkillId
        skill_version    = $Script:SkillVersion
        contract_version = $Script:ContractVersion
        invocation_id    = $InvocationId
        status           = $Status
        started_at_utc   = $StartedUtc
        finished_at_utc  = (Get-UtcNow)
        duration_ms      = $DurationMs
        inputs_digest    = "sha256:$InputsDigest"
        result           = $Result
        confidence       = $null
        artifacts        = $Artifacts
        model_provenance = @()
        diagnostics      = [ordered]@{ log = 'stderr.txt' }
        warnings         = $Warnings
        error            = $ErrorObj
    }
}

function Write-EnvelopeAndExit {
    param($Envelope, [string]$ArtifactDir)
    $json = $Envelope | ConvertTo-Json -Depth 24
    if ($ArtifactDir -and (Test-Path -LiteralPath $ArtifactDir)) {
        try { Write-Utf8NoBom -Path (Join-Path $ArtifactDir 'result.json') -Text $json } catch { Write-Diag "could not write result.json: $($_.Exception.Message)" }
    }
    # stdout: exactly the envelope JSON, nothing else.
    [Console]::Out.WriteLine($json)
    exit 0
}

# ---------------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------------

$sw            = [System.Diagnostics.Stopwatch]::StartNew()
$startedUtc    = Get-UtcNow
$invocationId  = [Guid]::NewGuid().ToString()
$shortId       = $invocationId.Substring(0, 8)
$artifactDir   = $null

try {
    # ----- parse InputsJson -----
    $ij = $null
    if (-not [string]::IsNullOrWhiteSpace($InputsJson)) {
        try {
            $ij = $InputsJson | ConvertFrom-Json -AsHashtable
        } catch {
            throw "InputsJson is not valid JSON: $($_.Exception.Message)"
        }
        if ($ij -isnot [System.Collections.IDictionary]) {
            throw 'InputsJson must be a JSON object.'
        }
    }
    $bound = $PSBoundParameters

    # ----- resolve inputs (named param overrides InputsJson key overrides default) -----
    $rAction       = "$(Resolve-Input -Bound $bound -Ij $ij -Param 'Action'        -Key 'action'         -Default 'pack')".Trim().ToLowerInvariant()
    $rArtifactRoot =    Resolve-Input -Bound $bound -Ij $ij -Param 'ArtifactRoot'  -Key 'artifact_root'  -Default $null

    # ----- artifact dir -----
    if ([string]::IsNullOrWhiteSpace($rArtifactRoot)) {
        $rArtifactRoot = Join-Path $PSScriptRoot 'runtime/artifacts'
    }
    $artifactDir = Join-Path $rArtifactRoot $invocationId
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

    $warnings = New-Object 'System.Collections.Generic.List[string]'

    if ($rAction -eq 'pack') {
        # ===== PACK =====
        $rPrompt       = Resolve-Input -Bound $bound -Ij $ij -Param 'Prompt'        -Key 'prompt'         -Default $null
        $rQuestion     = Resolve-Input -Bound $bound -Ij $ij -Param 'Question'      -Key 'question'       -Default ''
        $rPaths        = ConvertTo-StringArray (Resolve-Input -Bound $bound -Ij $ij -Param 'Paths'   -Key 'paths'   -Default @())
        $rFolder       = Resolve-Input -Bound $bound -Ij $ij -Param 'Folder'        -Key 'folder'         -Default $null
        $rInclude      = ConvertTo-StringArray (Resolve-Input -Bound $bound -Ij $ij -Param 'Include' -Key 'include' -Default @())
        $rExclude      = ConvertTo-StringArray (Resolve-Input -Bound $bound -Ij $ij -Param 'Exclude' -Key 'exclude' -Default @())
        $rRecurse      = ConvertTo-Bool (Resolve-Input -Bound $bound -Ij $ij -Param 'Recurse' -Key 'recurse' -Default $true) $true
        $rMaxFileBytes = [long](Resolve-Input -Bound $bound -Ij $ij -Param 'MaxFileBytes'  -Key 'max_file_bytes'  -Default 2000000)
        $rMaxTotal     = [long](Resolve-Input -Bound $bound -Ij $ij -Param 'MaxTotalBytes' -Key 'max_total_bytes' -Default 20000000)
        $rTitle        = "$(Resolve-Input -Bound $bound -Ij $ij -Param 'Title'   -Key 'title'    -Default '')"
        $rOutName      = Resolve-Input -Bound $bound -Ij $ij -Param 'OutName' -Key 'out_name' -Default $null
        $rReturnName   = Resolve-Input -Bound $bound -Ij $ij -Param 'ReturnFile' -Key 'return_file' -Default $null

        if ([string]::IsNullOrWhiteSpace($rPrompt)) {
            $err = [ordered]@{ code = 'missing_input'; message = "Input 'prompt' is required for action 'pack'."; retryable = $false }
            $envx = New-Envelope -Status 'error' -InvocationId $invocationId -StartedUtc $startedUtc -InputsDigest (ConvertTo-Sha256HexOfString 'missing_prompt') -Result $null -Artifacts @() -Warnings @() -ErrorObj $err -DurationMs $sw.ElapsedMilliseconds
            Write-EnvelopeAndExit -Envelope $envx -ArtifactDir $artifactDir
        }

        if ([string]::IsNullOrWhiteSpace($rOutName)) { $rOutName = "frontier-pack-$shortId" }
        # sanitise out name (basename only)
        $rOutName = [System.IO.Path]::GetFileName($rOutName)
        if ([string]::IsNullOrWhiteSpace($rOutName)) { $rOutName = "frontier-pack-$shortId" }

        # ----- collect candidate files (deterministic order) -----
        $candidates = New-Object 'System.Collections.Generic.List[string]'

        function Add-Candidate {
            param([System.Collections.Generic.List[string]]$List, [string]$FullPath)
            $rp = $null
            try { $rp = (Resolve-Path -LiteralPath $FullPath -ErrorAction Stop).ProviderPath } catch { return }
            if (Test-Path -LiteralPath $rp -PathType Leaf) {
                if (-not $List.Contains($rp)) { $List.Add($rp) }
            }
        }

        $selectionRequested = ($rPaths.Count -gt 0) -or (-not [string]::IsNullOrWhiteSpace($rFolder))

        foreach ($p in $rPaths) {
            $matched = $false
            # Glob / wildcard support via -Path; literal fall-back for names with [] etc.
            $items = @()
            try { $items = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue) } catch { $items = @() }
            if ($items.Count -eq 0) {
                # maybe it's a directory -> include its files
                if (Test-Path -LiteralPath $p -PathType Container) {
                    $items = @(Get-ChildItem -LiteralPath $p -File -Recurse:$rRecurse -ErrorAction SilentlyContinue)
                } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
                    $items = @(Get-Item -LiteralPath $p -ErrorAction SilentlyContinue)
                }
            }
            foreach ($it in $items) {
                if ($null -ne $it) { Add-Candidate -List $candidates -FullPath $it.FullName; $matched = $true }
            }
            if (-not $matched) { $warnings.Add("no files matched path/glob: $p") }
        }

        if (-not [string]::IsNullOrWhiteSpace($rFolder)) {
            if (Test-Path -LiteralPath $rFolder -PathType Container) {
                $gci = @(Get-ChildItem -LiteralPath $rFolder -File -Recurse:$rRecurse -ErrorAction SilentlyContinue)
                foreach ($it in $gci) {
                    $name = $it.Name
                    $incOk = $true
                    if ($rInclude.Count -gt 0) {
                        $incOk = $false
                        foreach ($g in $rInclude) { if ($name -like $g) { $incOk = $true; break } }
                    }
                    if ($incOk -and $rExclude.Count -gt 0) {
                        foreach ($g in $rExclude) { if ($name -like $g) { $incOk = $false; break } }
                    }
                    if ($incOk) { Add-Candidate -List $candidates -FullPath $it.FullName }
                }
            } else {
                $warnings.Add("folder not found or not a directory: $rFolder")
            }
        }

        # deterministic ordering (ordinal, culture-independent)
        $ordered = $candidates.ToArray()
        [Array]::Sort($ordered, [System.StringComparer]::Ordinal)

        # ----- build the pack -----
        $included = New-Object 'System.Collections.Generic.List[object]'
        $skipped  = New-Object 'System.Collections.Generic.List[object]'
        $sb       = New-Object System.Text.StringBuilder
        $totalContentBytes = [long]0
        $fileNum = 0

        foreach ($fp in $ordered) {
            $len = ([System.IO.FileInfo]$fp).Length
            if ($len -gt $rMaxFileBytes) {
                $skipped.Add([ordered]@{ path = $fp; reason = 'too_large'; bytes = $len }) | Out-Null
                $warnings.Add("skipped (too_large > $rMaxFileBytes bytes): $fp")
                continue
            }
            if (($totalContentBytes + $len) -gt $rMaxTotal) {
                $skipped.Add([ordered]@{ path = $fp; reason = 'total_cap'; bytes = $len }) | Out-Null
                $warnings.Add("skipped (would exceed max_total_bytes $rMaxTotal): $fp")
                continue
            }
            $bytes = [System.IO.File]::ReadAllBytes($fp)
            if (Test-IsBinary -Bytes $bytes) {
                $skipped.Add([ordered]@{ path = $fp; reason = 'binary'; bytes = $bytes.Length }) | Out-Null
                $warnings.Add("skipped (binary): $fp")
                continue
            }
            $decoded  = ConvertFrom-FileBytes -Bytes $bytes
            $sha      = ConvertTo-Sha256Hex -Bytes $bytes
            $fileNum++
            $totalContentBytes += $len

            [void]$sb.AppendLine("")
            [void]$sb.AppendLine(">>>>> FBRIDGE::$shortId::FILE $fileNum : $fp >>>>>")
            [void]$sb.AppendLine($decoded.text)
            [void]$sb.AppendLine("<<<<< FBRIDGE::$shortId::END  $fileNum : $fp <<<<<")

            $included.Add([ordered]@{ path = $fp; bytes = $bytes.Length; sha256 = $sha; encoding = $decoded.encoding }) | Out-Null
        }

        if ($selectionRequested -and $included.Count -eq 0) {
            $warnings.Add('file selection was requested but no files were included.')
        }
        if (-not $selectionRequested) {
            $warnings.Add('no paths or folder supplied; produced a prompt-only pack.')
        }

        # ----- return file -----
        if ([string]::IsNullOrWhiteSpace($rReturnName)) {
            $returnFile = Join-Path $artifactDir "$rOutName.answer.md"
        } else {
            $returnFile = $rReturnName
            if (-not [System.IO.Path]::IsPathRooted($returnFile)) {
                $returnFile = Join-Path $artifactDir ([System.IO.Path]::GetFileName($returnFile))
            }
        }
        $answerBegin = "$($Script:AnswerBeginPrefix) pack=$shortId>>>"
        $answerEnd   = "$($Script:AnswerEndPrefix) pack=$shortId>>>"
        $stub = @(
            '<!-- FRONTIER-BRIDGE RETURN FILE -->',
            "<!-- pack_id: $invocationId -->",
            "<!-- short_id: $shortId -->",
            '<!-- Paste the external model''s FULL answer BETWEEN the two ANSWER marker lines below. -->',
            '<!-- Keep the two marker lines and the pack_id line intact; do not paste the pack itself back. -->',
            "<!--   Then have Claude run:  Invoke-FrontierBridge.ps1 -Action read-return -ReturnFile `"$returnFile`" -->",
            $answerBegin,
            '',
            $answerEnd,
            ''
        ) -join "`n"
        Write-Utf8NoBom -Path $returnFile -Text $stub

        # ----- assemble pack text -----
        $head = New-Object System.Text.StringBuilder
        [void]$head.AppendLine("# FRONTIER-BRIDGE PACK")
        if (-not [string]::IsNullOrWhiteSpace($rTitle)) { [void]$head.AppendLine("# $rTitle") }
        [void]$head.AppendLine("# invocation_id: $invocationId")
        [void]$head.AppendLine("# generated_utc: $startedUtc")
        [void]$head.AppendLine("# LOCAL-ONLY packaging: no network was contacted. You (the human) are the sole courier.")
        [void]$head.AppendLine("")
        [void]$head.AppendLine("## INSTRUCTIONS")
        [void]$head.AppendLine($rPrompt)
        [void]$head.AppendLine("")
        if (-not [string]::IsNullOrWhiteSpace($rQuestion)) {
            [void]$head.AppendLine("## QUESTION")
            [void]$head.AppendLine($rQuestion)
            [void]$head.AppendLine("")
        }
        [void]$head.AppendLine("## INCLUDED FILES ($($included.Count) files, $totalContentBytes bytes)")
        if ($included.Count -eq 0) {
            [void]$head.AppendLine("(none)")
        } else {
            foreach ($f in $included) { [void]$head.AppendLine("  - $($f.path)  [$($f.bytes) bytes, sha256:$($f.sha256.Substring(0,12))..., $($f.encoding)]") }
        }
        if ($skipped.Count -gt 0) {
            [void]$head.AppendLine("")
            [void]$head.AppendLine("## SKIPPED ($($skipped.Count))")
            foreach ($s in $skipped) { [void]$head.AppendLine("  - $($s.path)  [$($s.reason), $($s.bytes) bytes]") }
        }
        [void]$head.AppendLine("")
        [void]$head.AppendLine("## FILE CONTENTS")
        $packText = $head.ToString() + $sb.ToString()
        $packText += "`n`n## HOW TO RETURN THE ANSWER`n"
        $packText += "1. Paste this ENTIRE pack into your OWN external model session (e.g. your ChatGPT).`n"
        $packText += "2. Copy the model's FULL answer.`n"
        $packText += "3. Paste it into this local return file, BETWEEN the two ANSWER marker lines:`n     $returnFile`n"
        $packText += "     (markers:  $answerBegin  ...  $answerEnd )`n"
        $packText += "4. Have Claude read + validate it:`n     Invoke-FrontierBridge.ps1 -Action read-return -ReturnFile `"$returnFile`"`n"

        $packPath = Join-Path $artifactDir "$rOutName.md"
        Write-Utf8NoBom -Path $packPath -Text $packText

        # ----- manifest -----
        $manifest = [ordered]@{
            schema        = 'lifeorch.frontier.pack_manifest/0.1'
            invocation_id = $invocationId
            title         = $rTitle
            generated_utc = $startedUtc
            boundary      = 'outbound-local-only; no network contacted; the human is the sole courier (D-0052)'
            pack_id       = $invocationId
            return_capture = [ordered]@{ file = [System.IO.Path]::GetFileName($returnFile); format = 'answer-markers'; begin = $answerBegin; end = $answerEnd }
            prompt_chars  = $rPrompt.Length
            question      = $rQuestion
            file_count    = $included.Count
            total_bytes   = $totalContentBytes
            files         = $included.ToArray()
            skipped       = $skipped.ToArray()
        }
        $manifestPath = Join-Path $artifactDir 'manifest.json'
        Write-Utf8NoBom -Path $manifestPath -Text (($manifest | ConvertTo-Json -Depth 12))

        # ----- inputs digest (normalised effective inputs) -----
        # Note: out_name / artifact_root / return_file are excluded -- they are output-naming
        # preferences, not semantic inputs (and the auto out_name embeds the random invocation id).
        $norm = [ordered]@{
            action = 'pack'; prompt = $rPrompt; question = $rQuestion;
            paths = $rPaths; folder = $rFolder; include = $rInclude; exclude = $rExclude;
            recurse = $rRecurse; max_file_bytes = $rMaxFileBytes; max_total_bytes = $rMaxTotal;
            title = $rTitle
        }
        $digest = ConvertTo-Sha256HexOfString (($norm | ConvertTo-Json -Depth 12 -Compress))

        # ----- artifacts -----
        $artifacts = @(
            (New-FileArtifact -Path $packPath     -Kind 'markdown'),
            (New-FileArtifact -Path $manifestPath -Kind 'json'),
            (New-FileArtifact -Path $returnFile   -Kind 'markdown')
        )

        $status = if ($selectionRequested -and $included.Count -eq 0) { 'partial' } else { 'ok' }

        $result = [ordered]@{
            action              = 'pack'
            pack_path           = (Resolve-Path -LiteralPath $packPath).ProviderPath
            manifest_path       = (Resolve-Path -LiteralPath $manifestPath).ProviderPath
            return_file         = (Resolve-Path -LiteralPath $returnFile).ProviderPath
            file_count          = $included.Count
            total_bytes         = $totalContentBytes
            skipped_count       = $skipped.Count
            boundary            = 'outbound-local-only; no network contacted; the human is the sole courier (D-0052)'
            instructions_for_user = "Copy the contents of the pack file into your OWN external model session (e.g. ChatGPT), paste the answer into the return file, then have Claude run action 'read-return' on the return file. frontier.bridge itself never contacts any external service."
        }

        $env1 = New-Envelope -Status $status -InvocationId $invocationId -StartedUtc $startedUtc -InputsDigest $digest -Result $result -Artifacts $artifacts -Warnings $warnings.ToArray() -ErrorObj $null -DurationMs $sw.ElapsedMilliseconds
        Write-EnvelopeAndExit -Envelope $env1 -ArtifactDir $artifactDir
    }
    elseif ($rAction -eq 'read-return') {
        # ===== READ-RETURN =====
        $rReturnFile = Resolve-Input -Bound $bound -Ij $ij -Param 'ReturnFile' -Key 'return_file' -Default $null
        if ([string]::IsNullOrWhiteSpace($rReturnFile)) {
            $err = [ordered]@{ code = 'missing_input'; message = "Input 'return_file' is required for action 'read-return'."; retryable = $false }
            $envx = New-Envelope -Status 'error' -InvocationId $invocationId -StartedUtc $startedUtc -InputsDigest (ConvertTo-Sha256HexOfString 'missing_return_file') -Result $null -Artifacts @() -Warnings @() -ErrorObj $err -DurationMs $sw.ElapsedMilliseconds
            Write-EnvelopeAndExit -Envelope $envx -ArtifactDir $artifactDir
        }
        if (-not (Test-Path -LiteralPath $rReturnFile -PathType Leaf)) {
            $err = [ordered]@{ code = 'not_found'; message = "Return file not found: $rReturnFile"; retryable = $true }
            $envx = New-Envelope -Status 'error' -InvocationId $invocationId -StartedUtc $startedUtc -InputsDigest (ConvertTo-Sha256HexOfString "missing:$rReturnFile") -Result $null -Artifacts @() -Warnings @() -ErrorObj $err -DurationMs $sw.ElapsedMilliseconds
            Write-EnvelopeAndExit -Envelope $envx -ArtifactDir $artifactDir
        }

        $rExpect = Resolve-Input -Bound $bound -Ij $ij -Param 'ExpectPackId' -Key 'expect_pack_id' -Default $null
        if ([string]::IsNullOrWhiteSpace($rExpect)) { $rExpect = $null }

        $bytes    = [System.IO.File]::ReadAllBytes($rReturnFile)
        $decoded  = ConvertFrom-FileBytes -Bytes $bytes
        $parsed   = ConvertFrom-ReturnFile -Text $decoded.text
        $answerTrim = ([string]$parsed.answer).Trim()
        $captured   = ($answerTrim.Length -gt 0)

        # ----- validate the returned file -----
        $issues = New-Object 'System.Collections.Generic.List[string]'
        if (-not $parsed.markers_found -and $parsed.format -ne 'legacy-separator') { $issues.Add('answer_markers_missing') }
        if ($parsed.markers_found -and -not $parsed.end_found) { $issues.Add('end_marker_missing') }
        if (-not $captured) { $issues.Add('answer_empty') }
        if ($captured -and (($answerTrim -match 'FRONTIER-BRIDGE PACK') -or ($answerTrim -match 'FBRIDGE::') -or ($answerTrim -match 'FRONTIER-BRIDGE-ANSWER-BEGIN'))) {
            $issues.Add('answer_looks_like_pack_or_markers')
        }
        $packIdMatch = $null
        if ($null -ne $rExpect) {
            $packIdMatch = ($parsed.pack_id -eq $rExpect)
            if (-not $packIdMatch) { $issues.Add('pack_id_mismatch') }
        }
        foreach ($iss in $issues) { $warnings.Add("return-validate: $iss") }

        # valid = content captured via a recognised structure and (if an id was expected) the id matched.
        $valid = $captured -and ($parsed.markers_found -or ($parsed.format -eq 'legacy-separator')) -and ($packIdMatch -ne $false)

        $digest = ConvertTo-Sha256HexOfString "read-return:$((Resolve-Path -LiteralPath $rReturnFile).ProviderPath)"
        $result = [ordered]@{
            action           = 'read-return'
            return_file      = (Resolve-Path -LiteralPath $rReturnFile).ProviderPath
            bytes            = $bytes.Length
            sha256           = (ConvertTo-Sha256Hex -Bytes $bytes)
            encoding         = $decoded.encoding
            format           = $parsed.format
            pack_id          = $parsed.pack_id
            expected_pack_id = $rExpect
            pack_id_match    = $packIdMatch
            captured         = $captured
            valid            = $valid
            char_count       = $answerTrim.Length
            issues           = $issues.ToArray()
            content          = $answerTrim
        }
        $status = if ($valid) { 'ok' } else { 'partial' }
        $env2 = New-Envelope -Status $status -InvocationId $invocationId -StartedUtc $startedUtc -InputsDigest $digest -Result $result -Artifacts @() -Warnings $warnings.ToArray() -ErrorObj $null -DurationMs $sw.ElapsedMilliseconds
        Write-EnvelopeAndExit -Envelope $env2 -ArtifactDir $artifactDir
    }
    else {
        $err = [ordered]@{ code = 'bad_action'; message = "Unknown action '$rAction'. Expected 'pack' or 'read-return'."; retryable = $false }
        $envx = New-Envelope -Status 'error' -InvocationId $invocationId -StartedUtc $startedUtc -InputsDigest (ConvertTo-Sha256HexOfString "bad_action:$rAction") -Result $null -Artifacts @() -Warnings @() -ErrorObj $err -DurationMs $sw.ElapsedMilliseconds
        Write-EnvelopeAndExit -Envelope $envx -ArtifactDir $artifactDir
    }
}
catch {
    $err = [ordered]@{ code = 'internal_error'; message = "$($_.Exception.Message)"; retryable = $false }
    $envx = New-Envelope -Status 'error' -InvocationId $invocationId -StartedUtc $startedUtc -InputsDigest (ConvertTo-Sha256HexOfString 'internal_error') -Result $null -Artifacts @() -Warnings @() -ErrorObj $err -DurationMs $sw.ElapsedMilliseconds
    try {
        Write-EnvelopeAndExit -Envelope $envx -ArtifactDir $artifactDir
    } catch {
        [Console]::Error.WriteLine("[frontier.bridge] fatal: could not emit envelope: $($_.Exception.Message)")
        exit 1
    }
}
