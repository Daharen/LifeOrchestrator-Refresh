# ops/setup -- portability / new-machine bring-up (Stage-1)

A config-driven, CPU-only toolkit for relocating the whole Life Orchestrator stack to a fresh Windows box
in one pass. Stage-1 of `MODULE_ROADMAP.md -> BACKLOG portability` (FANOUT_AGENT_002, plan fo-14-5ea064b6).

This is a **self-contained toolkit under `ops/setup/` only**. It does **not** rewrite any module's path
resolution (that is the documented follow-on) and it **never** modifies `modules/07-model-gateway/models.json`
(the GPU lane owns it) -- it writes a staging copy under `out/`.

## What it does

1. **Config layer** -- one place to resolve **repo-root + data-root + a machine profile** (hostname,
   username, GPU name/VRAM), replacing the hard-coded `C:\Users\just_\LifeOrchestrator-Refresh` and
   `F:\My_Programs\...\_Large_Data` absolute paths. Roots are **detected at runtime** (from the module's own
   location, env vars `LIFEORCH_REPO_ROOT` / `LIFEORCH_DATA_ROOT`, and probed candidates), never baked in.
2. **`setup.ps1` bootstrap** -- checks prereqs, detects the GPU, generates a machine-specific `models.json`
   sized to the detected VRAM, and emits a model/engine download plan.
3. **Verify pass** -- the CPU-only checks now; the GPU-dependent steps are documented in `VERIFY-RUNBOOK.md`.

## Files

| file | role |
|---|---|
| `LifeorchConfig.psm1` | STANDALONE config library: `Resolve-LifeorchConfig`, `Write-LifeorchConfig`, `Test-LifeorchConfig`, machine/GPU detection, and a JSON-Schema-subset validator (`Test-JsonAgainstSchema`). Modules adopt this LATER. |
| `LifeorchSetup.psm1` | bootstrap logic: prereq judge, VRAM sizing (`New-MachineModelsJson`), staging-plan emitter, heartbeat judge, `Invoke-SetupVerify`. |
| `setup.ps1` | CLI over the two modules (`-Action prereq|detect|gen|verify|all`). Emits one `lifeorch.setup.result/0.1` JSON object on stdout. |
| `config.schema.json` | schema for `config.json`. |
| `models.schema.json` | structural schema for the generated `out/models.machine.json`. |
| `config.json` | this machine's DETECTED config (regenerate on a new box via `setup.ps1 -Action detect`). |
| `VERIFY-RUNBOOK.md` | the GPU-dependent verify steps to run after this wave. |
| `tests/Invoke-SetupTests.ps1` | dual-mode harness (mock/cloud + `-Live`). |
| `out/` | generated (gitignored): `models.machine.json`, `staging-plan.txt`. |

## Usage

```powershell
# Detect + (re)write this box's config.json
pwsh -NoProfile -File ops\setup\setup.ps1 -Action detect

# Check prereqs (pwsh>=7.4, git, .NET SDK, curl.exe, CUDA via nvidia-smi)
pwsh -NoProfile -File ops\setup\setup.ps1 -Action prereq

# Generate the VRAM-sized, data-root-repointed models.json + download plan into out/
pwsh -NoProfile -File ops\setup\setup.ps1 -Action gen

# CPU-only verify pass
pwsh -NoProfile -File ops\setup\setup.ps1 -Action verify

# Everything (add -WriteConfig to also rewrite config.json)
pwsh -NoProfile -File ops\setup\setup.ps1 -Action all -WriteConfig
```

Off-box (cloud pwsh on Linux) all Windows-only probes degrade to `unknown` and nothing throws; drive
generation with `-VramMiBOverride <MiB>` and `-MockNvidiaSmiText '<name>, <MiB>'`, and `-BaseModelsPath`
a fixture. On the box, VRAM is detected from `nvidia-smi`.

## VRAM sizing heuristic

For each GPU-served (`engine=llama-server`) entry, `gpu_layers` is chosen for a card of
`VRAM - DisplayReserve` (default reserve 1024 MiB) usable budget: full-resident need = `weight * 1.05 + KV`
(KV scales with context and model size). If it fits, `gpu_layers = 99` (full offload); otherwise a partial
count `floor((budget - KV) / per-layer) - 2` (a small display-headroom margin, the Module-9 "chose 32 < the
36 that fit" ethos). The strong **9B** tier picks the richest quant (Q5_K_M > Q4_K_M) that fits fully; if
none fit fully it falls back to the smallest quant with partial offload. On the reference 11 GB RTX 2080 Ti
every wired LLM fits fully at `ngl 99` and the strong pick is **Q5_K_M** -- matching the live registry.

**Partial-offload `gpu_layers` are a STARTING POINT** the `VERIFY-RUNBOOK.md` sweep finalizes on a new box
(exactly as Module 9 tuned the 27B). The download plan's URLs marked `TODO_CONFIRM_URL` must be confirmed
against the source repo before a multi-GB download.

## Scope + follow-ons (NOT in Stage-1)

- **Wiring the config layer into `modules/*`** (replacing their hard-coded paths with
  `Resolve-LifeorchConfig`) -- a follow-on that touches every module and would collide this wave.
- **Applying `out/models.machine.json`** into the live `modules/07-model-gateway/models.json` -- a
  model-gateway (#7) / GPU-lane action under the gpu lease.
- **Actually downloading** the tens of GB of models/engines -- run `out/staging-plan.txt` deliberately.
- **The GPU-dependent verify** (strong-tier smoke gen + S0 6/6 calibration) -- see `VERIFY-RUNBOOK.md`.

ASCII-only, pwsh 7 target (the 5.1-ANSI gotcha). No GPU/model invocation anywhere in this toolkit.
