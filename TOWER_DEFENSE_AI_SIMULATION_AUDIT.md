# AI Simulation Prompt Adversarial Audit

Audit target: generated AI simulation Codex prompt workflow under `.godot/ai_simulation/`

Related evidence:

- `.godot/ai_simulation/ai_simulation_report_YYYY_MM_DD_HHMM.md`
- `.godot/ai_simulation/ai_simulation_data_YYYY_MM_DD_HHMM.json`
- `.godot/ai_simulation/ai_simulation_codex_prompt_YYYY_MM_DD_HHMM.md`
- `TOWER_DEFENSE_AI_SIMULATION.bat`
- `scripts/tools/run_ai_simulation_batch.gd`
- `scripts/tools/run_ai_prompt_metadata_validation.gd`
- `README.md`
- `.gitignore`
- `CODEX_HANDOFF.md`
- `git status --short`

This is an adversarial audit of the generated Markdown prompt and the workflow that creates it. It assumes a downstream Codex agent may over-trust the prompt, skip verification, or convert weak diagnostics into gameplay edits.

## Bottom Line

The generated prompt is useful as a local diagnostic packet, but it is not safe to treat as a direct implementation spec. Its strongest parts are the explicit verification constraints, canonical-data guardrails, runtime invariants, and active scenario-probe plumbing. Its weakest parts are evidence maturity, run-size ambiguity, stale path expectations in surrounding validation, and the fact that API-level simulation still does not prove the playable scene, visual clarity, audio feedback, or player comprehension.

The current generated prompt should be used for triage only. It should not drive balance changes or claims of gameplay correctness without fresh verification against the current worktree, a larger comparable run, focused scene/UI validation, screenshot review when visuals matter, and manual playtesting for feel.

## Current State Snapshot

Observed repo state:

- Worktree is broadly dirty.
- `TOWER_DEFENSE_AI_SIMULATION.bat` is untracked.
- `RUN_AI_SIMULATION_PROMPT.bat` is deleted in the active worktree.
- `scripts/tools/run_ai_simulation_batch.gd` is modified and now contains schema 6 scenario-probe plumbing.
- `README.md`, `CODEX_HANDOFF.md`, `project.godot`, gameplay/autoload scripts, and several validation scripts are modified.
- `data/game_data.json` is not shown as dirty in current `git status --short`; do not repeat older untracked claims without rechecking.
- `logs/` and generated simulation outputs are untracked/generated local evidence.
- Treat all of the above as active worktree evidence, not committed baseline.

Current runner/output evidence:

- `scripts/tools/run_ai_simulation_batch.gd` writes timestamped root outputs such as `ai_simulation_report_YYYY_MM_DD_HHMM.md`, `ai_simulation_data_YYYY_MM_DD_HHMM.json`, and `ai_simulation_codex_prompt_YYYY_MM_DD_HHMM.md`.
- Legacy root `ai_simulation_latest.*` files are archived by the runner, and previous-report loading still checks timestamped output plus legacy latest locations.
- `scripts/tools/run_ai_prompt_metadata_validation.gd` still expects `latest/ai_simulation_latest.*` paths, so metadata validation may be stale relative to current timestamped output behavior.
- Current script constants indicate schema 6 and `--scenario-probes=auto|off|smoke|full` support, but this remains modified worktree code until validated and committed.
- Scenario probes should therefore be treated as active/planned diagnostic coverage unless the current run artifacts and validation logs prove they executed successfully.

Important contradiction from earlier generated evidence: a prompt can display profile `medium` while the actual evidence packet is smoke-sized, such as `14` runs and `2` max waves. The run count and max waves may be explicit, but the profile label can still mislead a reader into over-weighting the report.

## Coverage Lanes

Use these lanes separately. Passing one lane does not imply passing the others.

1. Direct API simulation: deterministic bot/runtime diagnostics through `VerticalSliceGame`. This catches stalls, impossible state, restore failures, leak spikes, rough tower usage imbalance, blocked actions, and batch-level regressions.
2. Scenario probes: curated tower-family, branch, enemy-kind, and scheduled-wave diagnostics. These improve coverage of specific mechanics, but active worktree scenario probes are not committed baseline unless validated in the current run artifacts.
3. Scene validation: focused Godot checks around `scenes/main.tscn`, autoload wiring, scene reload, input paths, layout snapshots, and viewport-specific UI geometry.
4. AI screenshot review: real Godot-rendered screenshots or frames reviewed for concrete visual defects only, including overlap, clipped text, contrast, missing assets, blank panels, bad z-order, confusing disabled/selected/hover states, and unclear gameplay feedback.
5. Manual playtesting: human review for feel, pacing, fun, learnability, player comprehension, subjective balance, and whether choices feel meaningful.

AI can help with UI and visual work only when it is anchored to rendered evidence or concrete UI specs. It should not be treated as proof that the game feels good.

## AI Simulation Capability Map

These concepts are realistic and useful for this project, but they should be treated as separate capabilities with different evidence strength. Add them to the audit vocabulary without assuming every capability is already implemented or balance-actionable.

| Concept | Meaning for this project | Audit use |
| --- | --- | --- |
| Automated playtesting | Bot-controlled runs exercise the tower defense loop without a human tester. | Core diagnostic lane for repeated runtime, economy, tower, wave, and upgrade checks. |
| Simulation harness | A runner loads project data, starts bot runs, applies scenarios, and writes reports. | Use to define the boundary between direct API simulation, scenario probes, generated prompts, and focused Godot validations. |
| Bot / agent controller | Code chooses player-like or adversarial actions such as tower placement, upgrades, target modes, speed changes, and wave starts. | Audit bot policy quality before trusting telemetry as balance or player-behavior evidence. |
| Monte Carlo simulation | Many seeded runs reveal statistical patterns such as win rate, failure rate, leak pressure, underused towers, and bad strategies. | Use only with comparable multi-seed medium/deep/overnight evidence, not smoke/custom runs. |
| Combinatorial testing | Runs or probes cover combinations of tower, branch, enemy kind, wave, seed, strategy, target mode, and economy state. | Track coverage gaps so untested combinations are not mistaken for healthy balance. |
| Deterministic seeds | Each run stores seed settings so a bug can be rerun and investigated. | Required for repro packets, regression comparison, and focused reruns with full action logs. |
| Headless testing | Godot runs without a visible window for fast local batches and CI-style checks. | Good for API, data, scenario, and invariant checks; not proof of visuals, audio timing, or player comprehension. |
| Fixed timestep simulation | Logic is advanced through stable tick steps rather than subjective visual frame timing. | Useful for reproducibility claims, especially when debugging stalls, projectiles, spawn timing, and speed controls. |
| Telemetry / instrumentation | Reports capture deaths, leaks, damage, economy, tower usage, upgrade choices, target modes, blocked actions, and failures. | Treat as raw evidence that needs interpretation, confidence, clustering, and false-positive classification. |
| Assertions / invariants | Rules that should never break, such as nonnegative state, clean wave resolution, valid restore state, and no impossible objective state. | Promote these to high-value bug checks because they can prove correctness failures more directly than aggregate balance metrics. |
| Replay system | A failed run can be reconstructed from seed, inputs, scenario config, and checkpoints. | High-value backlog item for shrinking failures and making bot reports easier to fix. |
| Coverage metrics | The report measures what towers, branches, enemies, waves, UI states, and edge cases the bot actually exercised. | Required to distinguish "not observed" from "tested and healthy." |
| Crash/softlock detection | The bot detects hard failures, stalls, infinite waves, impossible starts, unresolved objectives, or broken progression. | Treat as the most implementation-actionable bot output when reproducible. |
| Data mining / balance analysis | Aggregated telemetry identifies weak towers, dominant builds, unfair waves, underused mechanics, and boring routes. | Useful only after confidence, sample-size, trend, and manual/playable-game checks. |
| CI regression testing | A small stable subset of bot and validation runs executes after changes to catch regressions early. | Good future lane once local evidence packets and reproducible repro commands are stable. |

Randomized/fuzz testing is intentionally excluded from this audit expansion for now. If added later, it should be framed as bug-discovery evidence only, not balance evidence.

## Findings

### A1. The prompt is too implementation-oriented for its evidence strength

Severity: high.

The title and opening sentence say to implement bugs, QoL fixes, balance improvements, and validation improvements implied by the report. In earlier smoke-sized evidence, there were no high-severity bugs, no QoL annoyances, no balance outliers, and no validation issues. That creates a mismatch: the prompt starts as an implementation directive even when the report contains little or no actionable implementation work.

Adversarial failure mode:

- A downstream agent may invent fixes because it was asked to implement findings that do not exist.
- The agent may tune balance based on low-sample telemetry even though the prompt later says not to.

Safer wording:

- Start with "audit and verify the latest AI simulation report; implement only confirmed, evidence-backed issues."
- Make "no code changes" an acceptable outcome when no confirmed findings exist.

### A2. The profile label can overstate the run quality

Severity: high.

Earlier generated evidence showed profile `medium`, but the config showed `14` runs and `2` waves. The runner allows explicit `--runs` and `--max-waves` overrides while leaving `profile` as `medium` unless another profile is explicitly selected or inferred upward. This means "Profile: medium" is not enough to infer medium-quality evidence.

Adversarial failure mode:

- A reader treats a smoke report as a medium diagnostic run.
- "medium samples are intentionally moderate" appears in the recommendations even when this specific sample is only 14 runs.

Safer report behavior:

- Add a derived `evidence_tier` such as `smoke`, `custom`, `medium`, `deep`, or `overnight`.
- If `runs` or `max_waves` differ from profile defaults, render `Profile: medium (custom override: 14 runs / 2 waves)`.

### A3. Ambiguous default evidence selection can downgrade confidence

Severity: high.

Older `latest` style output could be overwritten every run, and archive evidence showed previous larger reports, including 420-run medium reports. The current runner writes timestamped root outputs, which is safer, but default consumer behavior can still drift toward whichever prompt a launcher, Notepad window, metadata validator, or user refers to as "latest." A weaker smoke run can therefore become the de facto evidence packet even when stronger archived evidence exists.

Adversarial failure mode:

- A user asks Codex to act on the most recently opened prompt after a quick smoke run, unintentionally discarding the stronger medium report as the active evidence packet.
- Regression and balance interpretation become anchored on a smoke report.

Safer workflow:

- Keep timestamped outputs, and make the launcher tell the user which evidence tier it opened.
- If any `latest_*` convenience pointers are reintroduced, split them by tier such as `latest_smoke/`, `latest_medium/`, `latest_deep/`, and `latest_overnight/`.
- In the prompt header, include "This is not the strongest available archived report" when larger same-day archived reports exist.

### A4. README and metadata validation disagree about prompt paths

Severity: medium.

Current `README.md` describes timestamped root prompt paths under `.godot\ai_simulation`, matching the runner's current output behavior. `scripts/tools/run_ai_prompt_metadata_validation.gd` still expects `.godot/ai_simulation/.../latest/ai_simulation_latest_*` files in fixture output directories, so surrounding validation can still audit the wrong layout.

Adversarial failure mode:

- A user or validation helper copies an old or nonexistent prompt path.
- A downstream agent audits the wrong Markdown file.
- Documentation implies a stable visible prompt location that the current workflow does not write.

Safer workflow:

- Update `run_ai_prompt_metadata_validation.gd` to validate the current timestamped output paths, or restore an explicit generated stable pointer that both README and validation agree on.

### A5. Regression comparison is under-specified

Severity: medium.

The runner compares previous and current reports only after checking schema, profile, strategy group, and max waves. It does not appear to require matching run count, seed, seed count, strategy list, report label, or full action log mode before marking reports comparable.

Earlier generated evidence was not comparable because schema changed, so no false comparison was observed there. The risk remains in the comparison logic.

Adversarial failure mode:

- Future reports with different run counts or seeds could be marked comparable and emit misleading deltas.
- A small custom run could be compared against a larger run if the checked fields happen to match.

Safer comparison gate:

- Require matching `runs`, `seed`, `seed_count`, `seed_step`, `strategies`, `max_waves`, `profile`, `strategy_group`, and schema before declaring comparable.
- Otherwise render the comparison as "same family, not comparable."

### A6. "No balance outliers" does not mean "no balance concern"

Severity: medium.

Earlier smoke-sized evidence said no balance outliers. That same smoke evidence still showed high leak rates in some low-sample strategy rows, but the runner's balance issue thresholds require minimum sample sizes before raising outliers. That thresholding is reasonable, but the prompt does not make the distinction obvious enough.

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

### A8. Playable-surface confidence is still under-covered

Severity: high.

Even with scenario probes, the automation mostly exercises direct APIs and curated game-state setups. It does not prove the first screen, real scene startup, full input path, visual readability, audio timing, or whether the player understands what is happening.

Adversarial failure mode:

- A downstream agent raises the simulation score after adding scenario probes and then claims the playable game is broadly validated.
- A UI regression ships because direct API checks never render the actual screen.
- A mechanic is numerically valid but unreadable, confusing, or unfun in the real viewport.

Coverage still needed:

- Main scene launch and wiring: `scenes/main.tscn`, intended autoloads, node paths, signals, pause/restart flow, and save/load path.
- Real input path: mouse placement, right-click cancel, hover, upgrade clicks, keyboard shortcuts, speed buttons, wave start, and targeting selection.
- Visual readability: path clarity, buildable-vs-blocked tiles, projectile visibility, enemy crowding, tower selection rings, boss/status feedback.
- UI layout regressions: overlap, text clipping, disabled/selected/hover states, panel layout, and bottom-dock behavior at `1180x600` plus taller viewports.
- Audio/feedback: build, blocked build, upgrade, wave start, leak, boss, win/loss, and error cues.
- Player comprehension: whether branch choices, research, rewards, targeting modes, and tradeoffs make sense without reading data internals.
- Full-run scene flows: one or more scripted or recorded playable flows through the real scene, not only direct `VerticalSliceGame` calls.
- Statistical confidence: comparable larger runs, matching seed/config families, and confidence intervals before treating balance movement as actionable.

Safer workflow:

- Add a scene/screenshot validation lane alongside the AI simulation report.
- Generate real Godot-rendered screenshots or frames from representative flows and have AI review concrete visual defects only.
- Keep manual playtesting as the authority for feel, pacing, fun, and subjective balance.

### A9. The prompt can blur known gaps with active work

Severity: medium.

The prompt lists known gaps such as unsupported towers and unported systems. That is useful, but a downstream implementation pass may interpret these as requested scope unless the prompt is stricter.

Adversarial failure mode:

- The agent starts implementing boss, commander, reward cards, mutation, mastery, or paragon systems during a small remediation pass.
- Scope expands from diagnostics into feature-porting.

Safer wording:

- Move known gaps under a "do not implement from this prompt unless explicitly requested" heading.
- Require a separate plan before promoting known gaps into implementation scope.

### A10. Full action forensics are usually unavailable

Severity: low.

Profile defaults set `full_action_log` off. The runner still records summaries and sampled information, but the prompt does not warn that individual decision traces may be incomplete unless full logging is enabled.

Adversarial failure mode:

- A reader tries to explain a specific bot decision from aggregate metrics without enough trace data.

Safer workflow:

- For any surprising issue, rerun a targeted small batch with `--full-action-log=true` and the relevant strategy/seed before changing gameplay.

### A11. External shim is outside repo ownership

Severity: low.

The repo launcher at `C:\Users\donny\Desktop\tower_defense_godot\TOWER_DEFENSE_AI_SIMULATION.bat` is the authoritative entrypoint. It is connected to the workflow and lives inside the repo root, so Git status can track changes to it.

Adversarial failure mode:

- The repo appears consistent while the Desktop entrypoint points at a stale or moved launcher.

Safer workflow:

- Keep the repo launcher authoritative.
- Treat the Desktop shim as convenience only and verify it separately when auditing end-user launch behavior.

## Evidence Quality Matrix

| Claim | Current evidence | Verdict |
| --- | --- | --- |
| Generated prompt workflow exists | Runner writes timestamped `ai_simulation_codex_prompt_YYYY_MM_DD_HHMM.md` files | Proven from current script |
| Latest report is medium strength | Earlier evidence showed profile `medium`, but runs were `14` and max waves `2` | Contradicted for that generated run |
| Data preflight passed | Latest Markdown and JSON show `data_validation` and `balance_sanity` OK | Proven for current generated run |
| No bugs/QoL/validation issues were detected | Latest Markdown says none recorded | Proven only within this smoke-sized run |
| No balance concerns exist | Latest Markdown says no outliers, but sample is too small for broad balance claims | Not proven |
| Prompt metadata validation matches current output layout | Metadata validator still expects `latest/ai_simulation_latest.*` while runner writes timestamped root files | Contradicted in current worktree |
| Scenario probes are implemented in committed baseline | Current dirty runner contains schema 6 and `scenario_probes`, but validation/commit status is not established here | Not proven |
| Generated evidence is committed baseline | Git status shows broad dirty worktree and untracked launcher | Contradicted |
| Full playable scene is validated | Runner instantiates game nodes directly | Not proven |
| Main scene wiring is validated | Some focused validators load `scenes/main.tscn`, but the AI simulation report does not launch the full playable flow | Partially proven outside AI sim only |
| Real input path is validated | Targeted validations can call input handlers, but no full real-player flow is proven by the simulation report | Partially proven |
| Visual readability is validated | No screenshot/rendered-frame review is part of the AI simulation report | Not proven |
| Audio/feedback is validated | Asset/audio checks can prove loading, not timing, clarity, or player feedback quality | Partially proven |
| Player comprehension is validated | No human or AI review of understandability is part of the direct simulation | Not proven |
| Statistical confidence supports balance action | Smoke/custom runs and non-comparable reports do not support broad balance claims | Not proven |
| Regression comparison is meaningful | Current report says not comparable due schema mismatch | Not proven |

## Adversarial Coverage Estimates

These scores are adversarial estimates, not measured validation results. They summarize what each lane is likely to catch if implemented and run correctly against the current worktree.

| Area | Current direct API sim | With scenario probes | With AI visual/scene lane | Remaining manual gaps |
| --- | ---: | ---: | ---: | --- |
| Runtime/gameplay bugs | 82 | 88 | 90 | rare manual timing bugs |
| Wave difficulty | 72 | 82 | 84 | why pressure feels unfair |
| Tower balance | 63 | 76 | 78 | player preference and long-term meta |
| Upgrade choices | 43 | 70 | 73 | subjective tradeoff quality |
| Targeting modes | 55 | 68 | 72 | high-skill timing and intent |
| Economy/progression | 46 | 62 | 66 | reward and tech excitement |
| Boss/commander pressure | 38 | 60 | 65 | real boss identity until mechanics exist |
| QoL/action friction | 67 | 72 | 84 | learnability without human testing |
| Regression detection | 58 | 70 | 76 | statistical certainty without larger samples |
| Full playable game confidence | 30 | 42 | 68 | human feel, pacing, and fun |

Overall estimate:

- Current direct AI simulation: about `59/100`.
- With validated scenario probes: about `75/100`.
- With scene validation plus AI screenshot review: about `82/100`.
- Manual playtesting remains required and is not replaced by any AI lane.

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

Make scenario-probe status explicit:

```text
Scenario probes are diagnostic coverage, not full-scene or manual-play proof. Treat them as active worktree evidence unless the report and validations were generated from a clean committed baseline.
```

Make AI visual review bounded:

```text
AI screenshot review may flag concrete visual defects from real Godot-rendered frames. It does not validate feel, pacing, fun, or subjective balance.
```

## Recommended Coverage Expansion

1. Keep direct API simulation as the fast diagnostic lane for runtime invariants, batch telemetry, and rough balance pressure.
2. Add or validate scenario probes for deterministic tower-family, branch, enemy-kind, and scheduled-wave coverage.
3. Add scene validation for `scenes/main.tscn`, autoload wiring, scene reloads, real input paths, and viewport layout snapshots.
4. Add an AI screenshot review lane using real Godot-rendered screenshots at the pinned viewport and any taller viewport supported by the bottom dock.
5. Use manual playtesting for comprehension, feel, pacing, fun, and subjective balance before claiming playable-game confidence.

## Recommended Workflow Hardening

1. Keep timestamped outputs as the primary evidence, and split any future latest-style convenience pointers by tier so smoke runs do not overwrite medium/deep evidence.
2. Align README, launcher, and metadata validation prompt paths.
3. Include custom override warnings whenever run count or max wave count differs from profile defaults.
4. Tighten regression comparability to include run count, seed settings, strategy list, and action-log mode.
5. Add a "no-op allowed" acceptance criterion to generated prompts.
6. For surprising findings, rerun with `--full-action-log=true` and targeted strategies before editing gameplay.
7. Keep known gaps out of implementation scope unless a separate user request explicitly promotes them.
8. Keep scenario probes separate from scene/UI/audio proof; report them as curated diagnostics.
9. Require screenshots or rendered frames before asking AI to judge visual/UI quality.
10. Require manual play before claiming changes improve feel, pacing, fun, or comprehension.

## Actionable Finding Requirements

Before any AI simulation finding can drive gameplay, data, UI, or balance changes, the report or follow-up triage must provide an actionable finding packet. If any required field is missing, the correct outcome is verification or rerun, not implementation.

Required fields:

1. Repro packet: include report path, JSON path, schema version, evidence tier, profile, runs, max waves, seed, seed count, seed step, strategy group, strategy, run id, wave, issue id, and exact rerun command. For decision-level bugs, include whether `--full-action-log=true` is required.
2. State evidence: include the relevant final snapshot, trimmed wave snapshot, tower/enemy/projectile state when available, blocked-action detail, sampled action log, and the exact code/data paths that should be inspected.
3. Confidence and effect size: include sample size, affected strategies or seeds, baseline/comparison eligibility, observed rate or delta, practical impact, and whether the result is smoke-only, diagnostic-only, or balance-actionable.
4. Bot-policy coverage: state which bot policies exercised the behavior, which useful player behaviors remain untested, and whether the finding could be caused by bot weakness rather than game rules.
5. False-positive class: classify the finding as confirmed game bug, likely game bug, bot weakness, known vertical-slice gap, low-sample noise, expected blocked action, validation/tooling issue, or visual/manual-play concern.
6. Exact validation: name the narrow Godot validation, scene/screenshot review, full-action-log rerun, or manual playtest needed before and after a fix. Balance changes require comparable multi-seed normal bot evidence plus focused gameplay validation.

Implementation rule:

- Do not change gameplay, balance, data, UI, or validation code from aggregate telemetry alone. First verify the finding against current code and current generated evidence, confirm the false-positive class, and identify the narrow validation that will prove the fix.

## AI Bot Quality Metrics

Track the bot as a data product, not just as a test runner. The goal is not more output; it is more confirmed, reproducible, player-relevant findings per run.

Bot success metrics:

1. Confirmed bug rate: percentage of bot findings that reproduce against current code and become accepted fixes.
2. False-positive rate: percentage of findings reclassified as bot weakness, known gap, low-sample noise, expected blocked action, or stale evidence.
3. Repro success rate: percentage of findings that include enough seed, strategy, wave, snapshot, and command data to reproduce in one targeted rerun.
4. Coverage completeness: percent of enabled towers, upgrade branches, target modes, enemy kinds, special waves, economy states, and UI/input lanes exercised by normal bot runs and scenario probes.
5. Balance-signal stability: whether leak rates, tower usage, branch outcomes, and blocked-action rates remain directionally stable across comparable multi-seed runs.
6. Fix usefulness: whether bot-driven fixes reduce repeated failures, improve validation coverage, or clarify player-facing feedback without creating new dominant strategies.

Human-vs-bot calibration:

- Compare bot behavior against short manual play notes before treating telemetry as player-representative. Record where the bot is intentionally adversarial, where it approximates normal play, and where it behaves unrealistically.
- Maintain at least one "reasonable player" policy and one "adversarial tester" policy so balance signals are not mixed with stress-test behavior.
- Treat bot-only strategies as bug-finding tools unless manual play or scene evidence shows the same issue affects real players.

Minimal repro reduction:

- For every high-value bug, shrink the finding to the smallest rerun that still fails: one seed, one strategy, one wave range, one scenario probe, or one saved state.
- Include the exact focused command and whether full action logging, scene validation, screenshot capture, or manual input is required.
- Prefer a small confirmed repro over a large aggregate report when assigning implementation work.

Finding priority score:

- Rank findings by player impact, severity, confidence, repro stability, affected systems, fix risk, and validation availability.
- Fix confirmed high-severity runtime bugs first, then reproducible scene/input/UI blockers, then stable balance outliers from comparable multi-seed evidence.
- Defer low-confidence balance movement, bot-only weaknesses, known gaps, and subjective feel claims until they have stronger evidence.

Trend / regression history:

- Track comparable historical drift for leak rate, tower usage, upgrade-branch usage, target-mode outcomes, failed runs, stalled runs, blocked actions, and high-severity issue counts.
- Define when movement is meaningfully worse, such as repeated same-direction drift across comparable multi-seed runs or a threshold breach that survives targeted rerun.
- Keep trend claims separate from one-off report findings. A single smoke/custom run can flag a question, but it should not reset the long-term balance narrative.

Bot blind spots matrix:

| Blind spot | Why it matters | Required non-bot evidence |
| --- | --- | --- |
| Human hesitation | Real players pause, misread, and delay decisions. | Manual play notes or recorded scene flow. |
| Bad placements | New players build inefficiently or misunderstand valid sites. | Manual play, scripted scene input, or beginner-policy bot lane. |
| First-time-player behavior | A player may not understand towers, waves, targeting, or upgrades. | Fresh-playtest notes or comprehension checklist. |
| UI misunderstanding | Aggregate telemetry cannot prove labels, disabled states, or panel layout are clear. | Screenshot review and focused UI validation. |
| Audio clarity | Asset loading does not prove timing, priority, or usefulness of feedback. | Manual/audio review in the running scene. |
| Visual clutter | API success does not prove enemies, projectiles, ranges, and warnings are readable. | Rendered screenshots or frame review. |
| Save/load during real play | Direct serialization tests may miss player timing and scene state. | Scene-flow validation or manual save/load pass. |
| Pause/speed abuse | Players may hammer controls in ways normal bot policies do not. | Stress validation or adversarial input flow. |

Issue clustering:

- Group repeated similar findings before assigning work. For example, many blocked upgrade attempts should become one "upgrade affordability feedback" cluster instead of dozens of separate issues.
- Cluster by label, action, tower type, wave, strategy, false-positive class, and likely owning subsystem.
- Report cluster size, representative repro, worst severity, and whether the cluster is growing across comparable runs.

Oracle / expected behavior checks:

- The bot should assert known rules, not only collect telemetry. Examples: wave 5 should load the expected schedule row, target mode should prefer the expected enemy, sell refund should match canonical data, and known boss gaps should be classified as known gaps instead of bugs.
- Add oracle checks for canonical data contracts, runtime invariants, reward/economy math, targeting expectations, upgrade branch gates, wave schedule rows, save/load round trips, and known unsupported systems.
- When an oracle fails, the report should identify whether the failure is game logic, data, validation tooling, or a stale expectation.

## Safe Consumer Checklist

Before using the generated prompt for implementation:

1. Run `git status --short`.
2. Confirm whether `data/game_data.json` and `scripts/tools/run_ai_simulation_batch.gd` are tracked and clean.
3. Check the report label, runs, max waves, seed count, and strategy group.
4. Treat reports under 420 runs or under 6 waves as smoke/custom diagnostics.
5. Compare against archived medium/deep reports before acting on balance.
6. Verify any finding against current gameplay code before editing.
7. Identify which validation lane produced each claim: direct API simulation, scenario probes, scene validation, AI screenshot review, or manual playtesting.
8. For UI/visual claims, inspect real Godot-rendered screenshots or frames; do not rely on aggregate metrics alone.
9. For audio/input/scene claims, run focused Godot validations or manual scene checks.
10. Run focused Godot validations after edits.
11. Run `git diff --check`.

## Final Adversarial Verdict

The generated prompt workflow is directionally good but still easy to over-trust. Its constraints are strong, and the active worktree now shows scenario-probe plumbing, but the report remains a diagnostic packet rather than proof of playable-game quality.

The safest next improvement is to keep the prompt explicitly verification-first, surface evidence tier and custom overrides, validate scenario probes as report-only diagnostics, separate scene/screenshot/manual-play lanes from direct API simulation, and prevent smoke or dirty-worktree evidence from becoming the default basis for gameplay or balance claims.
