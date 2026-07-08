# AI Audit Workflow

Run one visible file:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1
```

The menu offers:

```text
1. Light audit (~5 minutes)
2. Deep audit (~10 hours / overnight)
3. Next fix/review prompt
4. Cancel
```

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
`git diff --check` before marking the queue item handled.
