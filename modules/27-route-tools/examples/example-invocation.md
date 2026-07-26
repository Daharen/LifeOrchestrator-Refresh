# route.tools -- example invocation

Route a request against the default attachable-tools registry (`../21-agent-local/tools.json`), MID tier:

```powershell
pwsh -NoProfile -File .\Invoke-RouteTools.ps1 -Request "make an image of a dog and save it"
```

Or through the generic wrapper / a caller, with `-InputsJson`:

```powershell
pwsh -NoProfile -File .\Invoke-RouteTools.ps1 -InputsJson '{"request":"read notes.md and append its line count to stats.txt","tier":"mid"}'
```

Point it at a specific registry and skip the few-shot examples:

```powershell
pwsh -NoProfile -File .\Invoke-RouteTools.ps1 -Request "what does the text on my screen say" -ToolsPath ..\21-agent-local\tools.json
```

The router emits only a JSON array of tool ids; `result.tools` is that array **after** it is deterministically
gated against the catalog (any id not in the catalog is dropped). `tier=strong` is refused on purpose --
the 27B is a thinking model that returns empty output for this task (m27-router-001); use `mid`.
