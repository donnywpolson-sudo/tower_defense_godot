# AI Simulation Audit Report

Latest report generated from the audit workflow on 2026-07-07 local machine time.

## Evidence Packet Audited

Fresh root timestamped packet:

- Human report: `.godot/ai_simulation/ai_simulation_report_2026_07_07_1945.md`
- JSON data: `.godot/ai_simulation/ai_simulation_data_2026_07_07_1945.json`
- Generated Codex prompt: `.godot/ai_simulation/ai_simulation_codex_prompt_2026_07_07_1945.md`

Supporting evidence:

- AI simulation log: `logs/godot/godot_ai_simulation.log`
- AI simulation stdout: `logs/godot/godot_ai_simulation_stdout.log`
- Prompt metadata log: `logs/godot/godot_ai_prompt_metadata_validation.log`
- Scenario probe validation log: `logs/godot/godot_ai_scenario_probe_validation.log`
- Performance log: `logs/godot/godot_performance_budget.log`
- Playable-surface log: `logs/godot/godot_playable_surface.log`
- Screenshots: `logs/godot/visual_review/playable_surface_pinned_1180x600.png`, `logs/godot/visual_review/playable_surface_bottom_dock_1180x820.png`

The packet was generated from the active dirty worktree, so results are active worktree evidence rather than committed-baseline evidence.

## Current Repo State

Initial `git status --short` before the audit run:

```text
 M .gitignore
 M TOWER_DEFENSE_AI_SIMULATION.bat
 M scripts/tools/recommend_ai_audit_settings.gd
 M scripts/tools/run_ai_audit_recommendation_validation.gd
 M scripts/tools/run_ai_prompt_metadata_validation.gd
 M scripts/tools/run_ai_scenario_probe_validation.gd
 M scripts/tools/run_ai_simulation_batch.gd
```

Status after the evidence bundle and before this report rewrite:

```text
 M .gitignore
 M TOWER_DEFENSE_AI_SIMULATION.bat
 M logs/godot/visual_review/playable_surface_pinned_1180x600.png
 M scripts/tools/recommend_ai_audit_settings.gd
 M scripts/tools/run_ai_audit_recommendation_validation.gd
 M scripts/tools/run_ai_prompt_metadata_validation.gd
 M scripts/tools/run_ai_scenario_probe_validation.gd
 M scripts/tools/run_ai_simulation_batch.gd
```

No root-level `godot_*.log` files were created. The rendered validation refreshed `logs/godot/visual_review/playable_surface_pinned_1180x600.png`; `.godot/ai_simulation` packet files and Godot logs are ignored/generated artifacts.

## Run Stats

| Field | Value |
| --- | --- |
| Schema version | `6` |
| Profile | `medium` |
| Evidence tier | `medium` |
| Profile overridden | `no` |
| Balance actionable | `yes`, but only after finding-level verification |
| Coverage scope | `direct_vertical_slice_api` |
| Runs | `420` |
| Completed / game over / failed | `289` / `131` / `0` |
| Normal / synthetic runs | `336` / `84` |
| Max waves | `6` |
| Seed / count / step | `12345` / `5` / `1000003` |
| Strategy group | `standard_research` |
| Strategies | `balanced_builder`, `tower_specialist`, `upgrade_rusher`, `wide_builder`, `target_mode_tester`, `edge_case_explorer`, `speed_stress`, `economy_saver`, `leak_recovery`, `value_upgrader` |
| Scenario-probe mode | `full` |
| Full action log | `false` |
| Regression comparability | `yes`; compared against previous latest report, with zero deltas reported |
| Preflight | `data_validation` ok: `1121` checks, `0` errors, `0` warnings; `balance_sanity` ok: `252` checks, `0` errors, `0` warnings |

Telemetry coverage in the packet:

- Implemented: enabled towers, enemy kinds, persistence probe, target modes, upgrades, wave outcomes.
- Partial: boss/commander, mastery/mutation/paragon, progression.
- Unsupported shop towers: `frost`, `poison`, `support`, `barracks`.
- Unported systems: reward-card choices, mutation mechanics, mastery upgrade mechanics, paragon mechanics, dedicated boss/commander combat rules.

Scenario probes:

- `39` total: `7` passed, `21` failed, `11` diagnostic, `0` stalled.
- Failed scenario groups: `3` tower-family leak probes, `15` branch leak probes, `3` enemy-kind leak probes.
- Diagnostic scheduled-wave issues: `11` scheduled special pressure probes reported boss/commander pressure not spawned by the current vertical slice.

Issue counts:

| Category | Count |
| --- | ---: |
| `known_gap` | 478 |
| `balance` | 13 |
| `scenario` | 35 |

Severity counts:

| Severity | Count |
| --- | ---: |
| `info` | 489 |
| `medium` | 27 |
| `low` | 10 |

Top issue labels:

| Label | Count |
| --- | ---: |
| `boss_commander_rules_unported` | 310 |
| `unsupported_shop_tower` | 168 |
| `scenario_leak_rate_out_of_range` | 24 |
| `scenario_scheduled_special_unspawned` | 11 |
| `upgrade_branch_unexercised` | 10 |
| `high_wave_leak_rate` | 1 |
| `high_enemy_kind_leak_rate` | 1 |
| `boss_commander_wave_diagnostic` | 1 |

## Minimum Coverage Evidence Bundle

| Item | Status | Result |
| --- | --- | --- |
| `git status --short` | fresh | Ran before and after the evidence bundle; dirty active-worktree files are listed above. |
| `.\_ai_audit_workflow\_internal\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto` | fresh | Passed. Produced the `2026_07_07_1945` packet with `420` runs and `526` issues. |
| `run_ai_prompt_metadata_validation.gd` | failed | Process exit was `0`, but the log says `AI_PROMPT_METADATA_VALIDATION_FAILED`; missing expected economy delta label text in both markdown and prompt. |
| `run_ai_scenario_probe_validation.gd` | fresh | Passed with `AI_SCENARIO_PROBE_VALIDATION_OK`. |
| `run_performance_budget_validation.gd` | fresh | Passed with `PERFORMANCE_BUDGET_VALIDATION_OK`. |
| `run_playable_surface_validation.gd` | fresh | Passed with `PLAYABLE_SURFACE_VALIDATION_OK`; console also printed Godot shutdown warnings about `2 ObjectDB` leaks and `1` resource still in use. |
| `git diff --check` | fresh | Passed after this report was written. |

## Scorecard

Scores estimate coverage from available evidence. They are not product-quality or release-confidence scores.

| Audit area | Evidence status | Score | Lane |
| --- | --- | ---: | --- |
| Core gameplay rules | partially proven | 72 | Direct API simulation plus preflight validators |
| Player input | partially proven | 70 | Scene/input validation |
| Physics and collisions | partially proven | 58 | Direct API simulation and projectile/runtime validators by implication |
| Scene and node lifecycle | partially proven | 66 | Scene/input validation |
| Signals and events | partially proven | 58 | Scene/input validation |
| Autoloads / singletons | partially proven | 60 | Direct API simulation and focused validators |
| Save/load systems | partially proven | 62 | Direct API simulation persistence probe; no fresh save/load torture in this bundle |
| Menus and UI | partially proven | 74 | Scene/input validation and screenshots |
| Game balance | partially proven | 63 | Direct API simulation and scenario probes |
| AI / enemy behavior | partially proven | 62 | Direct API simulation and scenario probes |
| Level/content validation | partially proven | 78 | Data/balance preflight and direct API simulation |
| Performance | partially proven | 85 | Performance/stress validation |
| Memory and resource usage | not proven | 35 | No memory-growth lane; playable-surface shutdown warnings remain |
| Rendering and visuals | partially proven | 76 | Screenshot/visual review and layout validation |
| Audio | partially proven | 45 | Existing asset/audio validation is outside the fresh minimum bundle; timing/mix not proven |
| Build/export stability | out of scope | N/A | No export lane audited |
| Platform compatibility | not proven | 30 | Windows local Godot only; other targets not audited |
| Networking, if multiplayer | not supported | N/A | Single-player slice; no multiplayer lane |
| Security / cheating | not proven | 35 | No dedicated tamper/exploit lane |
| Accessibility | not proven | 30 | Basic readability visible; remapping, colorblind, font scaling, and toggles not audited |
| Localization | not proven | 20 | No localization lane audited |
| Crash/error logging | partially proven | 68 | Logs captured under `logs/godot`; prompt metadata log reports failure despite process exit `0` |
| Telemetry / analytics | partially proven | 80 | Packet includes schema, seeds, strategies, scenario mode, and issue metadata |

Overall current audit coverage estimate: `74/100`. The strongest lanes are direct API simulation, scenario probes, scene/input validation, screenshots, and performance. Manual play feel, audio usefulness, export/platform behavior, accessibility, localization, and memory growth are still weak or missing.

## Visual Review Output

Fresh rendered evidence:

- `playable_surface_pinned_1180x600.png`: nonblank, map/path/tower range render correctly, sidebar panels fit, selected tower panel is dense but readable, and no obvious panel overlap was observed.
- `playable_surface_bottom_dock_1180x820.png`: nonblank, bottom dock panels are separated and readable, and no obvious dock overlap was observed.

Fresh validator result:

- `PLAYABLE_SURFACE_VALIDATION_OK`.
- Passed checks included main scene load/instantiate, vertical slice/debug HUD presence, keyboard speed/pause, mouse shop selection, cancel, placement, tower selection, target button, speed button, wave-start click path, pinned 1180x600 layout, bottom-dock 1180x820 layout, and screenshot saves.

Residual visual gap: this is a validator-backed screenshot review, not full art, animation, contrast, accessibility, or manual comprehension QA.

## Performance Metrics

Fresh performance-budget validation passed.

| Metric | Observed | Budget | Result |
| --- | ---: | ---: | --- |
| Average step time | `901 usec` | `5000 usec` | pass |
| Max step time | `6100 usec` | `50000 usec` | pass |
| Total stress time | `162180 usec` | `900000 usec` | pass |
| Max enemies | `120` | `160` | pass |
| Max projectiles | `3` | `120` | pass |

The performance run also reported clean runtime invariants.

## Findings

### F1. Prompt metadata validator fails on economy table label drift

Severity: medium. False-positive class: validation/report contract mismatch.

Evidence: `logs/godot/godot_ai_prompt_metadata_validation.log` reports `AI_PROMPT_METADATA_VALIDATION_FAILED` and says the expected economy delta label text is missing from both the markdown report and generated prompt:

```text
| Wave | Runs | Avg money delta | Avg spend delta | Avg lives delta | Avg tech delta | Avg tower delta |
```

Manual inspection found an economy table with the same visible header in the generated report and prompt:

```text
| Wave | Runs | Avg money delta | Avg spend delta | Avg lives delta | Avg tech delta | Avg tower delta |
```

That means the displayed strings look identical in this report view, so the likely issue is whitespace, hidden characters, line-ending handling, stale validator expectation, or log/report generation timing. Do not change gameplay for this.

Exact rerun:

```powershell
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_prompt_metadata_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_prompt_metadata_validation.gd
```

### F2. Scenario probes show repeated leak-pressure failures

Severity: medium. False-positive class: scenario threshold or balance diagnostic, not confirmed implementation defect.

Evidence: `SCENARIO-0001` through `SCENARIO-0021` include `24` `scenario_leak_rate_out_of_range` issues. The clearest groups are:

- Tower families: `archer` at `35.7%`, `cannon` at `46.4%`, `sniper` at `46.4%` leak rate.
- Branch probes: all `15` branch probes failed at `73.5%` leak rate on wave `8`, while scheduled commander pressure was not spawned.
- Enemy kinds: `armored` at `41.7%`, `commander` at `50.0%`, `flying` at `41.7%` leak rate.
- Scheduled waves: `wave_8`, `wave_10`, and `wave_16` exceeded leak thresholds in diagnostic scheduled-wave probes.

These are not directly tune-ready because several branch and scheduled-wave failures overlap with the known boss/commander vertical-slice gap.

Exact rerun:

```powershell
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_scenario_probe_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_scenario_probe_validation.gd
```

### F3. Boss and commander scheduled pressure is still a known vertical-slice gap

Severity: medium. False-positive class: known unported feature.

Evidence: `boss_commander_rules_unported` appears `310` times, and `scenario_scheduled_special_unspawned` appears `11` times. The packet records scheduled boss/commander pressure but `0` spawned boss/commander units in those probes.

This should stay out of implementation scope unless boss/commander runtime behavior is explicitly requested.

### F4. Balance outliers are diagnostic, not implementation-driving proof

Severity: medium. False-positive class: bot-policy and sample-scope risk.

Evidence:

- `BALANCE-0001`: wave `4` high leak rate, `62.2%` over `297` normal runs.
- `BALANCE-0002`: `tank` high leak rate, `62.2%` over `297` waves.
- `BALANCE-0003`: boss/commander scheduled pressure diagnostic, `248` scheduled, `0` spawned.
- `BALANCE-0004` through `BALANCE-0013`: unexercised upgrade branches across archer, machine gun, cannon, sniper, and tesla.

These findings justify focused reproduction and bot-policy review before any cost, damage, economy, wave, or upgrade tuning.

### F5. Playable-surface validation passed but reported shutdown cleanup warnings

Severity: low. False-positive class: cleanup/resource-lifetime diagnostic.

Evidence: the playable-surface command returned exit `0` and wrote `PLAYABLE_SURFACE_VALIDATION_OK`, but the console printed:

```text
WARNING: 2 ObjectDB instances were leaked at exit
ERROR: 1 resources still in use at exit
```

This is not a scene/input failure, but it is a resource cleanup gap worth isolating if it repeats outside test-run teardown.

## Recommended Improvements

1. Fix or narrow the prompt metadata validator/report contract mismatch before relying on metadata validation as green.
2. Add a focused scenario-probe report section that separates branch failures caused by missing scheduled special spawns from pure tower/branch weakness.
3. Keep boss/commander, reward cards, mutation, mastery, and paragon as known gaps until explicitly scoped.
4. Before tuning balance, rerun a smaller targeted batch for wave `4`, `tank`, and the failing tower/branch probes with enough action detail to distinguish weak bot policy from actual data imbalance.
5. Add a dedicated cleanup or teardown validation only if the playable-surface shutdown warnings repeat in non-test gameplay or broader scene validation.

## Validation Commands And Results

Fresh commands run:

```powershell
git status --short
cmd /c .\_ai_audit_workflow\_internal\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_prompt_metadata_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_prompt_metadata_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_scenario_probe_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_scenario_probe_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_performance_budget.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_performance_budget_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --log-file logs/godot/godot_playable_surface.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_playable_surface_validation.gd
```

Results:

- AI simulation batch: passed, `420` runs, `526` issues, packet `2026_07_07_1945`.
- Prompt metadata validation: failed by log content; process returned exit `0`.
- Scenario probe validation: passed.
- Performance budget validation: passed.
- Playable surface validation: passed with shutdown cleanup warnings.
- Screenshot review: performed on both refreshed PNGs.

## Deferred Or Rejected Implementation Actions

- No gameplay, data, scene, UI, asset, audio, or validation code changes were made from aggregate telemetry.
- No balance tuning was made.
- No boss/commander implementation was started from the known-gap diagnostics.
- No export, platform, audio-mix, accessibility, localization, security, or memory claims are treated as proven.

## Residual Gaps

- The prompt metadata validator currently fails according to its log.
- Manual playtesting is not covered by this run.
- Audio timing, mix quality, and cue usefulness are not proven.
- Memory growth is not proven, and the playable-surface command printed shutdown cleanup warnings.
- Export stability and non-Windows platform compatibility are out of scope.
- Accessibility and localization remain mostly unaudited.
- Scenario and balance findings are diagnostic until verified against current code and bot policy.

## Next Recommended Action

Fix or diagnose the prompt metadata validator/report contract mismatch, then rerun the metadata validator so the evidence packet can be considered internally consistent before gameplay or balance work begins.
