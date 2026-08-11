# i48 CD-1 acceptance probe -- dispatch (PROBE-ONLY dry run)

You are a fresh orchestration-planning agent for Life Orchestrator, running a PROBE-ONLY DRY RUN. Your working material is the folder `LifeOrch-i48-eval` (its `tree\` is a frozen repo snapshot; treat `_facts\` as given box/git state). HARD RULES: no writes anywhere except your single output file in `_out\`; no executor jobs; no leases; no commits; no dispatches; where a procedure would call for a write or a live check, STATE what you would do instead.

BOOT SOURCE: Your boot source is `_bundle\BOOT_PACKET.md`. STEP 0 (before reading it): from the folder root run, via your Linux shell: `python3 _bundle/tool/project_map.py validate --map _bundle/map-eval --harvest _bundle/harvest-eval.json` then `python3 _bundle/tool/project_map.py render --check --map _bundle/map-eval --harvest _bundle/harvest-eval.json --out _bundle/generated-eval` -- record both result envelopes in your pack (a refusal is a reportable result, not a dead end). Then follow the packet's retrieval protocol: expand via its pointers, L1 cards, and `--q` queries into `tree\`; every open/query is a ledger row. The legacy prose docs in `tree\core-docs\` are not forbidden, but each one you open is a ledger row like any other.

Deliver `_out\PROBE_PACK.md`, <=12,000 bytes, with EXACTLY these sections:
1 ANSWERS -- answer each question completely; every claim pointer-cited (a path or a `--q` query + what it said); mark each known/inferred/uncertain:
  Q1 What are the wave concurrency clamps for a fan-out wave (workers, GPU, parallelism, doc contention)?
  Q2 What are the rules for git writes on this project, and how must a shipped unit's landing be verified?
  Q3 What is the resource-lease acquire/release discipline?
  Q4 What is the orphan-process discipline for waves, and what standing rule applies to a schema producer+consumer pair split across parallel workers?
2 RETRIEVAL LEDGER -- one row per document/file/query you opened or ran: seq | path-or-query | bytes | why (<=1 line) | what it changed (<=1 line). Recording is measurement, not a limit -- open what the task needs and record it.
3 Model id + settings you are running on.
