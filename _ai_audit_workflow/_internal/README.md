# AI Audit Workflow

Run one visible file:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1
```

The menu offers:

```text
1. Medium report-only audit
2. Smoke report-only audit
3. Deep report-only audit
4. Overnight report-only audit
5. Apply next queued fix/review
6. Cancel
```

Press Enter to choose option 1. The default path audits the game and writes a
fresh self-identifying packet plus a report-only queue. It does not apply code
changes. Applying a queued item requires an explicit later command.

For a non-interactive automatic pass:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Medium -AutoImprove
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

The authoritative profile contract is `_internal/config.json`:

- Smoke: 14 runs, 2 waves.
- Medium: 420 runs, 6 waves.
- Deep: 2,500 runs, 20 waves.
- Overnight: 6,000 runs, 50 waves.
- Light is retained only as a compatibility alias for Medium.

The launcher and simulator read this contract instead of maintaining separate
run counts or timing claims. Every packet must contain matching JSON, Markdown,
prompt, and manifest artifacts with one packet identity.

Simulation resilience behavior:

- Each simulation attempt writes separate stdout/stderr and launcher logs under
  `logs/godot/ai_simulation/<run-id>/` and records process/memory diagnostics in
  the workflow state.
- Each profile retries one failed or timed-out run once.
- An unrecoverable failure stops before queue generation or Codex execution.
- Skipped validations remain skipped; stale logs cannot satisfy a fresh run.

For plumbing checks without a broad Godot run:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Light -SkipAudit
```

For the deterministic process-wrapper resilience check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\_ai_audit_workflow\_internal\run_resilience_validation.ps1
```

## Pursue-goal workflows

For the full hypothesis-to-alpha workflow, run the generic entrypoint. `-Goal`
accepts only a checked-in slug matching `[a-z0-9][a-z0-9_-]{0,63}` and resolves
it beneath `_ai_audit_workflow/goals`; rooted paths and traversal are rejected:

```powershell
.\_ai_audit_workflow\PURSUE_GOAL.ps1 -DryRun
```

The root goal accepts the current hypothesis, sequences the Frost and tower
balance child goals, runs data/gameplay/export/workflow validation, and then
requires an actual export artifact. Missing evidence, changed protected files,
missing export configuration, or any failed gate ends the goal as blocked. No
staging, commit, or push is performed. Mutation and export stages are blocked
unless their approval switches are supplied explicitly.

Child goals remain directly runnable when needed:

```powershell
.\_ai_audit_workflow\PURSUE_GOAL.ps1 -Goal frost_balance -DryRun
.\_ai_audit_workflow\PURSUE_GOAL.ps1 -Goal tower_balance_sweep -DryRun
```

After separate approval for the exact operation, pass only the required switch:

```powershell
.\_ai_audit_workflow\PURSUE_GOAL.ps1 -Goal frost_balance -ApproveMutation
.\_ai_audit_workflow\PURSUE_GOAL.ps1 -Goal hypothesis_to_alpha -ApproveMutation -ApproveExport
```

Validate the contract without running or changing anything:

```powershell
.\_ai_audit_workflow\PURSUE_GOAL.ps1 -Goal frost_balance -ValidateOnly
```

Preview stage decisions without applying the selected data value:

```powershell
.\_ai_audit_workflow\PURSUE_GOAL.ps1 -Goal frost_balance -DryRun
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
- `last_improvement_result.json`
- `latest_run.log`
- `run_logs/`

`status.json`, `findings.json`, and `improvement_queue.json` record whether the
audit evidence came from a dirty working tree. Dirty-baseline evidence is useful
for the current worktree, but it is not committed-baseline project health.

When items are queued, `next_improvement_prompt.md` contains one copy-pasteable
Pursue Goal prompt covering every queued finding. It requires current-code
verification, focused validation, and an explicit disposition for each item.
When no item is queued, it is overwritten with a non-actionable no-queued-item
message so stale apply prompts are not reused.

The apply-now path is guarded. It refuses a dirty repo unless
`-AllowDirtyApply` is passed. Every implementation item must declare nonempty
`allowedFiles` and a validator object with `script`, `args`, `expectedToken`,
and bounded `timeoutSeconds`. Codex must return structured JSON containing
`findingId`, `disposition`, `filesChanged`, and `reason`. The wrapper then
independently compares the actual diff with both file lists, runs the declared
validator, requires a fresh expected token and exit code zero, and runs
`git diff --check` before marking the item handled. `no_code_change` requires a
reason and zero new diff; `deferred` remains unresolved with its blocker.

## One-shot all-findings pursue-goal prompt

To run a broad audit and emit one autonomous remediation prompt, use:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Deep -PursueGoalPrompt -AllowDirtyQueue
```

`-PursueGoalPrompt` includes every distinct open finding plus every recorded
coverage/workflow gap in `next_improvement_prompt.md`, then prints the full
copy-pasteable prompt. It does not launch Codex or edit gameplay code. The
generated goal tells Codex to process the complete set without stopping after
the first fix, verify each candidate against current code, run focused tests,
and explicitly defer weak or non-reproducible items. Use `-Tier Overnight` for
the widest configured simulation sweep. `-AllowDirtyQueue` is required when
the audit starts from an intentionally dirty worktree; the prompt labels that
evidence as current-worktree-only and tells Codex to preserve unrelated edits.

For prompt generation from the latest existing audit state without rerunning
Godot:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -SkipAudit -PursueGoalPrompt -AllowDirtyQueue
```
