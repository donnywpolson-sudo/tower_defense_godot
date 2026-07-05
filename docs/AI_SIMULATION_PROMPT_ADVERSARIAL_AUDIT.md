# AI Simulation Prompt Adversarial Audit

Audit target: `.godot/ai_simulation/latest/ai_simulation_latest_codex_prompt.md`

Related evidence:

- `.godot/ai_simulation/latest/ai_simulation_latest.md`
- `.godot/ai_simulation/latest/ai_simulation_latest.json`
- `RUN_AI_SIMULATION_PROMPT.bat`
- `scripts/tools/run_ai_simulation_batch.gd`
- `README.md`
- `.gitignore`
- `CODEX_HANDOFF.md`
- `git status --short`

This is an adversarial audit of the generated Markdown prompt and the workflow that creates it. It assumes a downstream Codex agent may over-trust the prompt, skip verification, or convert weak diagnostics into gameplay edits.

## Bottom Line

The generated prompt is useful as a local diagnostic packet, but it is not safe to treat as a direct implementation spec. Its strongest parts are the explicit verification constraints and canonical-data guardrails. Its weakest parts are evidence maturity, run-size ambiguity, stale path documentation, and the fact that `latest` can be overwritten by a much weaker smoke run.

The current latest prompt should be used for triage only. It should not drive balance changes or claims of gameplay correctness without fresh verification against the current worktree and a larger comparable run.

## Current State Snapshot

Observed repo state:

- Worktree is broadly dirty.
- `RUN_AI_SIMULATION_PROMPT.bat` is untracked.
- `scripts/tools/run_ai_simulation_batch.gd` is untracked.
- `data/game_data.json` is untracked.
- `CODEX_HANDOFF.md` is untracked.
- `logs/` and generated simulation outputs are untracked/generated local evidence.

Latest generated prompt/report:

- Latest prompt path: `.godot/ai_simulation/latest/ai_simulation_latest_codex_prompt.md`
- Latest report path: `.godot/ai_simulation/latest/ai_simulation_latest.md`
- Latest JSON path: `.godot/ai_simulation/latest/ai_simulation_latest.json`
- Filesystem timestamp: `2026-07-04 10:32 PM`
- Label: `telemetry_smoke`
- Profile shown: `medium`
- Actual run size: `14` runs, `2` max waves
- Strategy group: `standard_research`
- Completed / game over / failed: `13` / `1` / `0`
- Preflight: `data_validation` OK, `balance_sanity` OK
- Previous-report comparison: not comparable because previous schema was `3` and current schema is `4`

Important contradiction: the latest generated prompt displays profile `medium`, but the actual evidence packet is a smoke-sized run. The run count and max waves are explicit, so this is not hidden, but the profile label can mislead a reader into over-weighting the report.

## Findings

### A1. The prompt is too implementation-oriented for its evidence strength

Severity: high.

The title and opening sentence say to implement bugs, QoL fixes, balance improvements, and validation improvements implied by the report. In the current latest report, there are no high-severity bugs, no QoL annoyances, no balance outliers, and no validation issues. That creates a mismatch: the prompt starts as an implementation directive even when the report contains little or no actionable implementation work.

Adversarial failure mode:

- A downstream agent may invent fixes because it was asked to implement findings that do not exist.
- The agent may tune balance based on low-sample telemetry even though the prompt later says not to.

Safer wording:

- Start with "audit and verify the latest AI simulation report; implement only confirmed, evidence-backed issues."
- Make "no code changes" an acceptable outcome when no confirmed findings exist.

### A2. The profile label can overstate the run quality

Severity: high.

The latest prompt says profile `medium`, but the config shows `14` runs and `2` waves. The runner allows explicit `--runs` and `--max-waves` overrides while leaving `profile` as `medium` unless another profile is explicitly selected or inferred upward. This means "Profile: medium" is not enough to infer medium-quality evidence.

Adversarial failure mode:

- A reader treats a smoke report as a medium diagnostic run.
- "medium samples are intentionally moderate" appears in the recommendations even when this specific sample is only 14 runs.

Safer report behavior:

- Add a derived `evidence_tier` such as `smoke`, `custom`, `medium`, `deep`, or `overnight`.
- If `runs` or `max_waves` differ from profile defaults, render `Profile: medium (custom override: 14 runs / 2 waves)`.

### A3. The latest pointer can downgrade evidence

Severity: high.

The latest files are overwritten every run. Archive evidence shows previous larger reports exist, including 420-run medium reports. The current `latest` report is a 14-run smoke labeled `telemetry_smoke`. A weaker smoke run can therefore replace a stronger diagnostic packet as the default prompt source.

Adversarial failure mode:

- A user asks Codex to act on "latest" after a quick smoke run, unintentionally discarding the stronger medium report as the active evidence packet.
- Regression and balance interpretation become anchored on a smoke report.

Safer workflow:

- Keep `latest_smoke/`, `latest_medium/`, `latest_deep/`, and `latest_overnight/` separately, or make the launcher tell the user which evidence tier it opened.
- In the prompt header, include "This is not the strongest available archived report" when larger same-day archived reports exist.

### A4. README and launcher disagree about the prompt path

Severity: medium.

`README.md` tells the user the generated prompt is saved at `codex_prompts\ai_simulation_latest.md`. The current launcher opens `.godot\ai_simulation\latest\ai_simulation_latest_codex_prompt.md`. `.gitignore` also ignores `codex_prompts/ai_simulation_latest.md`, but the `codex_prompts` directory does not currently exist.

Adversarial failure mode:

- A user copies an old or nonexistent prompt path.
- A downstream agent audits the wrong Markdown file.
- Documentation implies a stable visible prompt location that the current workflow does not write.

Safer workflow:

- Update README to match `.godot\ai_simulation\latest\ai_simulation_latest_codex_prompt.md`, or copy the generated prompt to the documented `codex_prompts` path.

### A5. Regression comparison is under-specified

Severity: medium.

The runner compares previous and current reports only after checking schema, profile, strategy group, and max waves. It does not appear to require matching run count, seed, seed count, strategy list, report label, or full action log mode before marking reports comparable.

Current latest report is not comparable because schema changed, so no false comparison was observed here. The risk remains in the comparison logic.

Adversarial failure mode:

- Future reports with different run counts or seeds could be marked comparable and emit misleading deltas.
- A small custom run could be compared against a larger run if the checked fields happen to match.

Safer comparison gate:

- Require matching `runs`, `seed`, `seed_count`, `seed_step`, `strategies`, `max_waves`, `profile`, `strategy_group`, and schema before declaring comparable.
- Otherwise render the comparison as "same family, not comparable."

### A6. "No balance outliers" does not mean "no balance concern"

Severity: medium.

The report says no balance outliers. The current smoke run still shows high leak rates in some low-sample strategy rows, but the runner's balance issue thresholds require minimum sample sizes before raising outliers. That thresholding is reasonable, but the prompt does not make the distinction obvious enough.

Adversarial failure mode:

- A reader treats "no balance outliers" as evidence that balance is healthy.
- A reader ignores that the run is too small to raise robust balance findings.

Safer wording:

- Render "No balance outliers met reporting thresholds" instead of "None recorded."
- Add sample-size warnings when normal runs per strategy are below a minimum threshold.

### A7. The workflow validates data and direct gameplay APIs, not the full playable scene

Severity: medium.

The simulation script instantiates `GameConfig`, `GameData`, and `VerticalSliceGame` directly. It does not launch `scenes/main.tscn`. That is good for deterministic diagnostics, but it does not prove scene wiring, UI layout, input paths, audio, or full manual play behavior.

Adversarial failure mode:

- A downstream agent claims "gameplay validated" too broadly from this report.
- UI regressions or scene setup issues are missed.

Safer acceptance criteria:

- Say the AI simulation validates direct vertical-slice APIs only.
- Require the relevant focused Godot validation, and manual/playable verification when UI, input, scenes, audio, or visuals change.

### A8. The prompt can blur known gaps with active work

Severity: medium.

The prompt lists known gaps such as unsupported towers and unported systems. That is useful, but a downstream implementation pass may interpret these as requested scope unless the prompt is stricter.

Adversarial failure mode:

- The agent starts implementing boss, commander, reward cards, mutation, mastery, or paragon systems during a small remediation pass.
- Scope expands from diagnostics into feature-porting.

Safer wording:

- Move known gaps under a "do not implement from this prompt unless explicitly requested" heading.
- Require a separate plan before promoting known gaps into implementation scope.

### A9. Full action forensics are usually unavailable

Severity: low.

Profile defaults set `full_action_log` off. The runner still records summaries and sampled information, but the prompt does not warn that individual decision traces may be incomplete unless full logging is enabled.

Adversarial failure mode:

- A reader tries to explain a specific bot decision from aggregate metrics without enough trace data.

Safer workflow:

- For any surprising issue, rerun a targeted small batch with `--full-action-log=true` and the relevant strategy/seed before changing gameplay.

### A10. External shim is outside repo ownership

Severity: low.

The Desktop shim at `C:\Users\donny\Desktop\TOWER_DEFENSE_AI_SIMULATION.bat` calls the repo launcher. It is connected to the workflow but lives outside the repo, so changes to it are not tracked by repo Git status.

Adversarial failure mode:

- The repo appears consistent while the Desktop entrypoint points at a stale or moved launcher.

Safer workflow:

- Keep the repo launcher authoritative.
- Treat the Desktop shim as convenience only and verify it separately when auditing end-user launch behavior.

## Evidence Quality Matrix

| Claim | Current evidence | Verdict |
| --- | --- | --- |
| Latest prompt exists | `.godot/ai_simulation/latest/ai_simulation_latest_codex_prompt.md` exists | Proven locally |
| Latest report is medium strength | Profile says `medium`, but runs are `14` and max waves `2` | Contradicted |
| Data preflight passed | Latest Markdown and JSON show `data_validation` and `balance_sanity` OK | Proven for current generated run |
| No bugs/QoL/validation issues were detected | Latest Markdown says none recorded | Proven only within this smoke-sized run |
| No balance concerns exist | Latest Markdown says no outliers, but sample is too small for broad balance claims | Not proven |
| Prompt path in README is current | README points to `codex_prompts`, launcher writes `.godot/ai_simulation/latest` | Contradicted |
| Generated evidence is committed baseline | Git status shows key files untracked/dirty | Contradicted |
| Full playable scene is validated | Runner instantiates game nodes directly | Not proven |
| Regression comparison is meaningful | Current report says not comparable due schema mismatch | Not proven |

## Recommended Prompt Hardening

Change the prompt contract from implementation-first to verification-first:

```text
Audit and verify the latest AI simulation report. Implement only confirmed issues supported by the report and current code. If no confirmed issue exists, make no gameplay/data changes and report why.
```

Add an evidence tier:

```text
Evidence tier: smoke/custom/medium/deep/overnight
Profile: medium
Overrides: 14 runs, 2 waves
Balance-actionable: no
```

Change "None recorded" phrasing for balance:

```text
No balance outliers met reporting thresholds for this run size.
```

Make scene coverage explicit:

```text
This report exercises direct vertical-slice APIs in headless Godot. It does not prove main-scene wiring, UI layout, audio, or manual input behavior.
```

## Recommended Workflow Hardening

1. Split latest outputs by tier so smoke runs do not overwrite medium/deep evidence.
2. Align README and launcher prompt paths.
3. Include custom override warnings whenever run count or max wave count differs from profile defaults.
4. Tighten regression comparability to include run count, seed settings, strategy list, and action-log mode.
5. Add a "no-op allowed" acceptance criterion to generated prompts.
6. For surprising findings, rerun with `--full-action-log=true` and targeted strategies before editing gameplay.
7. Keep known gaps out of implementation scope unless a separate user request explicitly promotes them.

## Safe Consumer Checklist

Before using the generated prompt for implementation:

1. Run `git status --short`.
2. Confirm whether `data/game_data.json` and `scripts/tools/run_ai_simulation_batch.gd` are tracked and clean.
3. Check the report label, runs, max waves, seed count, and strategy group.
4. Treat reports under 420 runs or under 6 waves as smoke/custom diagnostics.
5. Compare against archived medium/deep reports before acting on balance.
6. Verify any finding against current gameplay code before editing.
7. Run focused Godot validations after edits.
8. Run `git diff --check`.

## Final Adversarial Verdict

The `.md` prompt is directionally good but too easy to over-trust. Its constraints are strong, but its framing still nudges an agent toward implementation even when the current report is smoke-sized and contains no confirmed fixes. The safest next improvement is to make the generated prompt explicitly verification-first, surface evidence tier and custom overrides, and prevent smoke reports from silently becoming the default "latest" implementation packet.
