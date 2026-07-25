# image.util -- example invocation

Probe an image (metadata + content/perceptual hashes -- computed for every op):

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile 'C:\Users\just_\Pictures\photo.jpg' -Op meta
```

Downscale so the longest side is <= 1024 (the `ocr.layout` MaxImageDimension case -- the result reports
`resize.scale_x`/`scale_y` so a caller can rescale boxes by `1/scale`):

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\big-screenshot.png -Op resize -MaxDimension 1024
```

Make a WebP thumbnail that fits inside 256x256 (aspect preserved):

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\photo.png -Op resize -Width 256 -Height 256 -Mode fit -Format webp -Quality 80
```

Crop the center half, or an explicit pixel rectangle:

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\page.png -Op crop -Region center -RegionFraction 0.5
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\page.png -Op crop -X 100 -Y 80 -CropWidth 640 -CropHeight 480
```

Convert a format:

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\image.bmp -Op convert -Format png
```

Split a large page into a 2x2 grid (each tile is its own image artifact):

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\page.png -Op tile -TileCols 2 -TileRows 2
```

Compare two images for near-duplicate detection (perceptual-hash Hamming distance + a similarity score):

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputFile .\a.png -Op similarity -CompareTo .\b.jpg
```

Via `-InputsJson` (the generic channel the Module 1 wrapper uses):

```powershell
pwsh -NoProfile -File .\Invoke-ImageUtil.ps1 -InputsJson '{
  "input": "C:\\Users\\just_\\Pictures\\photo.jpg",
  "op": "resize",
  "max_dimension": 2000,
  "format": "jpg",
  "quality": 88
}'
```

Through the Module 1 wrapper:

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . `
    -InputsJson '{"input":"photo.png","op":"meta"}'
```

Through the executor: submit a task package whose `task.ps1` calls `Invoke-ImageUtil.ps1` and read the
envelope from `runtime/completed/<task_id>/stdout.txt`.

The envelope goes to **stdout** (a single JSON object); diagnostics go to **stderr**. The structured result is
also written as `image.json` / `image.md`, alongside any produced image files, under
`runtime/artifacts/<invocation_id>/`. See `example-result.json` for a real result.
