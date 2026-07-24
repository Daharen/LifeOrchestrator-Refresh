# capture.screen — example invocations

## Capture the primary monitor (PNG)
```powershell
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target monitor -Monitor primary
```

## Capture the whole virtual desktop (all monitors)
```powershell
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target monitor -Monitor all
```

## Capture a specific monitor by index
```powershell
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target monitor -Monitor 1
```

## Capture a window by title glob
```powershell
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Title 'Calculator*'
```

## Capture an application's main window by process name
```powershell
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -App notepad
```

## Capture an explicit rectangle, as JPG
```powershell
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -Target region -X 0 -Y 0 -Width 800 -Height 600 -Format jpg
```

## Generic -InputsJson convention
```powershell
pwsh -NoProfile -File .\Invoke-CaptureScreen.ps1 -InputsJson '{"target":"monitor","monitor":"primary","format":"png"}'
```

## Through the generic wrapper (Module 1)
```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"target":"region","x":0,"y":0,"width":320,"height":240}'
```

Typical flow: when `uia.inspector` returns an empty/unhelpful tree (e.g. a Unity/game window), call
`capture.screen` on that window (`-Title`/`-App`/`-ProcessId`) or its monitor to obtain a PNG for a local
vision model or direct review. The single JSON envelope conforms to `lifeorch.skill.result/0.1` (see
`example-result.json`). Artifacts `capture.png` + `capture.json` + `capture.md` are written under
`runtime/artifacts/<invocation_id>/`.
