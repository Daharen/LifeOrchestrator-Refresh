# doc.io — example invocations

## read a line range

```powershell
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op read -Path C:\Users\just_\LifeOrchestrator-Refresh\core-docs\CURRENT_STATE.md -StartLine 1 -EndLine 20
```

Returns the first 20 lines in `result.content`, with `result.file` = `{encoding, bom, eol, line_count,
byte_count, char_count, sha256}` for the whole file and `result.returned` describing the slice.

## write (create or overwrite) a document

```powershell
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op write -Path C:\tmp\report.md -Content "# Report`n`nBody text." -Eol lf
```

Atomic write; `result.created` is true on first write. To refuse overwriting an existing file:
`-Overwrite:$false` (→ `already_exists`). To guard against a lost update, pass the sha256 you last read:
`-ExpectSha256 <hash>` (→ `precondition_failed` on mismatch).

## edit — exact-string replacement (unique by default)

```powershell
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op edit -Path C:\tmp\report.md -OldString "Body text." -NewString "Revised body."
```

Requires exactly one occurrence (`not_found` / `not_unique` otherwise). `-ReplaceAll` replaces every
occurrence; `-ExpectCount 3` requires exactly three. The file's EOL is preserved (a CRLF file stays CRLF).

## append — add to the end

```powershell
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -Op append -Path C:\tmp\log.md -Content "- 2026-07-25 entry"
```

`-EnsureNewline` (default true) inserts a separating newline when the file does not already end with one;
`-Create` (default true) creates the file if missing. The appended newlines match the file's EOL.

## generic input (an orchestrator / the escalator / a local model)

```powershell
pwsh -NoProfile -File .\Invoke-DocIo.ps1 -InputsJson '{"op":"edit","path":"C:\\tmp\\report.md","old_string":"foo","new_string":"bar","replace_all":true}'
```

## through the Module 1 wrapper

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"op":"read","path":"C:\\tmp\\report.md"}'
```
