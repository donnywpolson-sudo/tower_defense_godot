# AI Audit Workflow

Run one visible file:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1
```

The menu offers:

```text
1. Light audit + apply next safe improvement (~5 minutes + fix)
2. Light audit only (~5 minutes)
3. Deep audit + apply next safe improvement (~10 hours + fix)
4. Deep audit only (~10 hours / overnight)
5. Apply next queued fix/review
6. Cancel
```

Press Enter to choose option 1. The default path audits the game, queues the
highest-priority evidence-backed bug or review-backed gameplay/polish item, and
runs one bounded Codex improvement pass. The pass must produce its exact result
summary and pass `git diff --check`; otherwise the queue item remains available
for review.

For a non-interactive automatic pass:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Light -AutoImprove
```

Use `-MaxFixes 2` through `-MaxFixes 5` only when you intentionally want more
than one queued item handled in the same run and accept the separate dirty-apply
gate after the first change. Re-run the audit afterward so the simulation and
validation evidence reflects the applied changes.

This workflow owns the tower defense audit files in this internal folder:

- `_ai_audit_workflow/_internal/TOWER_DEFENSE_AI_SIMULATION.bat`
- `_ai_audit_workflow/_internal/TOWER_DEFENSE_AI_SIMULATION_AUDIT.md`
- `_ai_audit_workflow/_internal/TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md`
- `scripts/tools/run_ai_*.gd`

There are exactly two audit modes in `RUN_AUDIT.ps1`:

- Light audit is calibrated for about 5 minutes on this machine: 240 runs, 6
waves, 5 seeds, standard research strategies, scenario probes auto, with a
10-minute simulation stop budget.
- Deep audit is calibrated for about 10 hours on this machine: 15,000 runs, 20
waves, 8 seeds, deep research strategies, scenario probes auto, with a 12-hour
simulation stop budget.

Both tiers then run the focused validation matrix. The timeout budgets are for
the simulation launcher process tree; individual focused validations have their
own narrow caps.

Simulation resilience behavior:

- Each simulation attempt writes separate stdout/stderr and launcher logs under
  `logs/godot/ai_simulation/<run-id>/` and records process/memory diagnostics in
  the workflow state.
- Light retries one failed or timed-out full run once.
- If both full Light attempts fail, Light runs two 120-run chunks without
  another retry, then aggregates them into one schema-6 report. The aggregate
  runs scenario probes once and records its source packets and fallback mode.
- Deep does not use chunk fallback. An unrecoverable simulation failure stops
  before queue application or Codex execution.

Timing basis from local smoke probes on 2026-07-08:

- 60 runs / 6 waves: 91.84 seconds.
- 120 runs / 6 waves: 151.12 seconds.
- 40 runs / 20 waves: 104.60 seconds.
- 160 runs / 20 waves: 392.34 seconds.
- Focused validation matrix without playable-surface stopped at the existing
  `independence_validation` failure after 8.90 seconds, so simulation time is
  the dominant runtime budget.

For plumbing checks without a broad Godot run:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Light -SkipAudit
```

For the deterministic process-wrapper resilience check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_ai_audit_workflow\_internal\run_resilience_validation.ps1
```

Dirty working-tree audit output is evidence only by default. If the audit starts
or ends with `git status --short` rows, the workflow writes state files but does
not create apply-ready queue items. To intentionally queue from that dirty
baseline, pass:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Light -AllowDirtyQueue
```

`-AllowDirtyQueue` only affects queue generation. The apply-now path is still
guarded separately and refuses a dirty repo unless `-AllowDirtyApply` is passed.

Generated workflow state is written under `_internal/current/`:

- `status.json`
- `findings.json`
- `improvement_queue.json`
- `next_improvement_prompt.md`
- `last_improvement_result.md`
- `latest_run.log`
- `run_logs/`

`status.json`, `findings.json`, and `improvement_queue.json` record whether the
audit evidence came from a dirty working tree. Dirty-baseline evidence is useful
for the current worktree, but it is not committed-baseline project health.

When no item is queued, `next_improvement_prompt.md` is overwritten with a
non-actionable no-queued-item message so stale apply prompts are not reused.

The apply-now path is guarded. It refuses a dirty repo unless
`-AllowDirtyApply` is passed, handles one queued item, runs `codex exec`, checks
for exact `Files changed:` and `Validation run:` result lines, and runs
`git diff --check` before marking the queue item handled. Simulation findings
are investigation prompts until the exact current-code or current-data defect is
verified; if verification fails, the correct result is no code change.
