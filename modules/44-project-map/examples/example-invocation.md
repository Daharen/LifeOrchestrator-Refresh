# project.map example invocations

Harvest the repo, then validate the map against it:

```
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action harvest  -Repo C:\Users\just_\LifeOrchestrator-Refresh -Out runtime/harvest.json
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action validate -Map map -Harvest runtime/harvest.json
```

Query the map for one entity's evidence and typed deeper pointers (progressive disclosure):

```
python3 project_map.py query --map map --q evidence:module:36/artifact.search
python3 project_map.py query --map map --q deeper:doc:core-docs/AUDIT_PIPELINE.md:failure
```

Render the bounded views at fold (refuses on any validation error, a dirty tree, or a remaining
skeleton), then re-render with --check as a drift gate:

```
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action render -Map map -Harvest runtime/harvest.json -Out generated
pwsh -NoProfile -File Invoke-ProjectMap.ps1 -Action render -Map map -Harvest runtime/harvest.json -Out generated -Check
```

Generic form (any caller): `-InputsJson '{"action":"query","map":"map","q":"stale"}'`.
