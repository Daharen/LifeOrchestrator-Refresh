# agent.local -- example invocations

`agent.local` takes a natural-language **goal** and drives a bounded local agent loop: it decides which
tool to call (through `logic.escalator` #19), generates that tool's arguments (through `model.gateway` #7),
invokes the tool as a child skill, observes the result, and repeats until it decides to `finish` or the
`max_steps` budget is reached. The default tool registry (`tools.json`) exposes `doc.io` (#20) and
`fs.observer` (#2).

## Direct (named params)

```powershell
# create a file
pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 `
  -Goal "Create hello.txt containing the text: hi from agent.local" `
  -WorkingDir C:\Users\just_\scratch

# read a file then derive an output from it (multi-step)
pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 `
  -Goal "Read notes.md and write its line count to stats.txt" `
  -WorkingDir C:\Users\just_\scratch -MaxSteps 5

# preview the plan WITHOUT running any tool (safe for side-effecting goals)
pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 `
  -Goal "Delete-and-rewrite the config" -WorkingDir C:\Users\just_\scratch -DryRun
```

## Generic (`-InputsJson`, the path an orchestrator/executor uses)

```powershell
pwsh -NoProfile -File .\Invoke-AgentLocal.ps1 -InputsJson '{
  "goal": "list the .md files in this folder and write their names to index.txt",
  "working_dir": "C:\\Users\\just_\\scratch",
  "max_steps": 5,
  "decision_tiers": ["tiny","weak","mid"],
  "gen_tier": "mid"
}'
```

## Wrapped (Module 1) or as an executor task package

```powershell
pwsh -NoProfile -File ..\01-skill-bootstrap\Invoke-Skill.ps1 -SkillDir . -InputsJson '{"goal":"create hello.txt with the text hi","working_dir":"C:\\Users\\just_\\scratch"}'
```

## Notes

- **Cost / speed:** each step is up to one escalator decision (a tiny->weak->mid ladder, one gateway call
  per tier) plus one gateway call for arguments, each currently a **cold** model load (no warm worker yet --
  D-0002). A multi-step goal therefore does several model loads; keep `max_steps` small and prefer cheap
  `decision_tiers` for routine work. A warm/persistent gateway worker is the shared follow-on that removes
  this cost.
- **Paths:** a relative `path`/`input`/`output`/`out`/`file`/`dest` argument the model emits is resolved
  against `-WorkingDir`. Give a `-WorkingDir` for reliable file work.
- **needs_frontier:** a status field, never a frontier call. It is set when a decision is low-confidence
  (below `frontier_threshold`) or the step budget was exhausted before finishing.
- **Safety:** the agent can do only what its registered tools allow -- there is no arbitrary-shell tool in
  the default registry. `-DryRun` previews a side-effecting plan without executing it.
