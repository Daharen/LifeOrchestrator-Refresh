# fs.manage — example invocation

Place a produced file on the Desktop (known folder → the real, possibly OneDrive-redirected, Desktop):

```powershell
pwsh -NoProfile -File .\Invoke-FsManage.ps1 -Op copy -Source "C:\...\image.png" -Dest desktop
```

Move + rename to a full path (with `~` expansion):

```powershell
pwsh -NoProfile -File .\Invoke-FsManage.ps1 -InputsJson '{"op":"move","source":"C:\\tmp\\a.png","dest":"~\\Downloads\\dog.png"}'
```

Make a folder:

```powershell
pwsh -NoProfile -File .\Invoke-FsManage.ps1 -Op mkdir -Path "desktop\dog-pics"
```

Driven by `agent.local` (the whole point): the goal *"generate an image of a dog and place it on my desktop"*
with `-Route` routes to `[gen.image, fs.manage]`; gen.image produces `image.png`; the agent then calls
`fs.manage` with `source` = that image's path (from the previous step's observation) and `dest` = `desktop`.
