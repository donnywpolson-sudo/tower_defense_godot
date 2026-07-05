# AI Simulation Audit Report

Latest report generated on 2026-07-05 after running the audit workflow bundle where available.

## Evidence Packet

No root timestamped packet currently exists under `.godot/ai_simulation/`. A fresh medium run was attempted, but Godot exited `-1` before writing a new report, JSON, or generated prompt. This report therefore uses the newest complete archived packet for simulation findings:

- Human report: `.godot/ai_simulation/archive/ai_simulation_deep_2500runs_20waves_seed12345_20260705_032839.md`
- JSON data: `.godot/ai_simulation/archive/ai_simulation_deep_2500runs_20waves_seed12345_20260705_032839.json`
- Generated Codex prompt: `.godot/ai_simulation/archive/ai_simulation_deep_2500runs_20waves_seed12345_20260705_032839_codex_prompt.md`

Fresh supporting evidence:

- AI batch log: `logs/godot/godot_ai_simulation.log`
- AI batch raw log: `logs/godot/godot_ai_simulation_raw.log`
- AI batch engine stderr: `logs/godot/godot_ai_simulation_engine_stderr.log`
- Prompt metadata log: `logs/godot/godot_ai_prompt_metadata_validation.log`
- Scenario probe validation log: `logs/godot/godot_ai_scenario_probe_validation.log`
- Performance log: `logs/godot/godot_performance_budget.log`
- Visual surface log: `logs/godot/godot_playable_surface.log`
- Visual screenshots: `logs/godot/visual_review/playable_surface_pinned_1180x600.png`, `logs/godot/visual_review/playable_surface_bottom_dock_1180x820.png`

Current repo state before running the bundle:

```text
 M TOWER_DEFENSE_AI_SIMULATION_AUDIT.md
?? TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md
```

Current repo state after running the bundle and rewriting this report:

```text
 M TOWER_DEFENSE_AI_SIMULATION_AUDIT.md
 M logs/godot/visual_review/playable_surface_pinned_1180x600.png
?? TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md
```

The modified audit spec and untracked report pre-existed this run. The pinned visual-review screenshot changed during fresh playable-surface validation.

## Run Stats

Archived simulation packet:

| Field | Value |
| --- | --- |
| Profile | `deep` |
| Evidence tier | `deep` |
| Profile overridden | `no` |
| Balance actionable | `yes`, but only after finding-level verification |
| Coverage scope | `direct_vertical_slice_api` |
| Schema | `5` |
| Runs | `2500` |
| Max waves | `20` |
| Seed / count / step | `12345` / `8` / `1000003` |
| Strategy group | `deep_research` |
| Scenario-probe mode | Not recorded in this archived schema 5 report |
| Full action log | Not recorded in the Markdown report |
| Completed / game over / failed | `0` / `2500` / `0` |
| Regression comparison | Not comparable: previous report had a different profile |
| Preflight | `data_validation` ok, `balance_sanity` ok |

Fresh attempted simulation:

| Field | Value |
| --- | --- |
| Command | `.\TOWER_DEFENSE_AI_SIMULATION.bat --test medium --scenario-probes=auto` |
| Effective profile | `medium` with scenario probes requested as `auto` |
| Intended runs | `420` |
| Last progress | `240/420` runs, `57%`, elapsed `5m52s` |
| Result | Failed with exit code `-1` |
| Packet output | Missing; no root report, JSON, or generated prompt was produced |
| Error detail | Logs show only progress and the known Windows root-certificate warning |

Archived key telemetry:

- Wave clear is uneven: early waves show major drops at waves 4, 7, 10, 15, and 17.
- All `2500` archived runs ended in game over by the configured target, with no failed harness runs.
- Boss and commander pressure was scheduled but not spawned: `1907` boss and `291` commander scheduled, `0` spawned.
- Blocked actions were all expected: `576` expected, `0` avoidable.
- High-severity issue volume is dominated by `wave_resolution_mismatch`: `615` total entries in the archived report summary.
- Balance outliers total `18` entries in the archived report summary, including tower-specialist no-completions, high leak rates, boss/commander diagnostics, and unexercised branches.

## Minimum Coverage Evidence Bundle

| Item | Status | Result |
| --- | --- | --- |
| `git status --short` | fresh | Ran before and after; dirty audit spec, untracked report, and refreshed pinned screenshot are reported above. |
| `.\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto` | failed | Noninteractive `--test` form reached `240/420` runs, then Godot exited `-1`; no new packet was produced. |
| `run_ai_prompt_metadata_validation.gd` | fresh | Passed with `AI_PROMPT_METADATA_VALIDATION_OK`. |
| `run_ai_scenario_probe_validation.gd` | fresh | Passed with `AI_SCENARIO_PROBE_VALIDATION_OK`. |
| `run_performance_budget_validation.gd` | fresh | Passed with `PERFORMANCE_BUDGET_VALIDATION_OK`. |
| `run_playable_surface_validation.gd` | fresh | Passed with `PLAYABLE_SURFACE_VALIDATION_OK`; console also printed Godot shutdown warnings about leaked ObjectDB/resource use. |
| `git diff --check` | fresh | Passed. |

## Scorecard

Scores are adversarial coverage estimates from the available evidence, not proof of product quality.

| Audit area | Status | Score | Evidence basis |
| --- | --- | ---: | --- |
| Core gameplay rules | partially proven | 72 | Archived deep direct API run covers waves, damage, economy, upgrades, win/loss pressure, but has unresolved wave-state bugs. |
| Player input | partially proven | 67 | Fresh playable-surface validation covers mouse placement, cancel, selection, target, speed, wave-start, and keyboard speed/pause paths. |
| Physics and collisions | partially proven | 58 | Projectile/enemy behavior is indirectly exercised; no broad layer/mask or tunneling proof in latest packet. |
| Scene and node lifecycle | partially proven | 62 | Fresh main scene load/instantiate and key nodes passed; broader reload/orphan/freed-node coverage is not proven. |
| Signals and events | partially proven | 55 | Status signal and UI/gameplay interactions are touched; duplicate/disconnected signal audit is not proven. |
| Autoloads / singletons | partially proven | 60 | Game data/config/audio/assets are exercised by validations; stale global state across all transitions is not proven. |
| Save/load systems | partially proven | 64 | Persistence evidence exists, and archived AI telemetry includes persistence coverage; latest run did not refresh save/load torture. |
| Menus and UI | partially proven | 70 | Shop, upgrade/selected tower panel, speed controls, and viewport layouts are freshly validated and visible. |
| Game balance | partially proven | 66 | Archived deep run is balance-actionable in size, but findings need bot-quality and false-positive triage before tuning. |
| AI / enemy behavior | partially proven | 63 | Enemy kinds and waves are covered; boss/commander spawning and flying coverage remain weak. |
| Level/content validation | partially proven | 75 | Archived canonical data preflight passed with `1121` data checks and `252` balance sanity checks. |
| Performance | partially proven | 82 | Fresh performance-budget validation passed with 120 enemies and bounded step times. |
| Memory and resource usage | not proven | 35 | No latest memory-growth or leak-specific result was identified; playable-surface run printed shutdown leak warnings. |
| Rendering and visuals | partially proven | 74 | Fresh rendered screenshots exist and layout validation passed; this is not full visual QA. |
| Audio | partially proven | 52 | Asset/audio validation evidence exists, but timing, mix, and feedback usefulness are not proven here. |
| Build/export stability | out of scope | N/A | No export lane was audited. |
| Platform compatibility | partially proven | 35 | Windows local Godot evidence exists; other platforms and high-DPI behavior are not proven. |
| Networking, if multiplayer | not supported | N/A | Current game is treated as single-player; no multiplayer lane exists. |
| Security / cheating | partially proven | 40 | Debug commands and save tampering risk are audit topics; no dedicated exploit proof is present. |
| Accessibility | not proven | 30 | Visual readability is partially checked, but remapping, font scaling, toggles, subtitles, and colorblind checks are not proven. |
| Localization | not proven | 20 | Text overflow can be seen in screenshots, but translation/glyph/RTL support is not audited. |
| Crash/error logging | partially proven | 68 | Fresh Godot validations report OK logs under `logs/godot/`; shutdown warnings and the failed AI batch need follow-up. |
| Telemetry / analytics | partially proven | 76 | Archived AI report includes seed/run metadata and broad telemetry; fresh medium telemetry packet is missing due to failure. |

Overall estimate:

- Direct AI simulation coverage: `68/100` because the current medium run failed before producing a packet and this report falls back to archived schema 5 evidence.
- Direct simulation plus fresh scene/visual/performance logs: `78/100`.
- Playable-game confidence remains below release confidence because manual feel, full visual QA, audio feedback quality, export, platform, and memory lanes are incomplete.

## Visual Review Output

Fresh rendered evidence:

- `playable_surface_pinned_1180x600.png`: map, path, tower range, active wave state, shop, speed controls, and selected tower panel render. No blank canvas or major panel overlap was observed. The selected-tower stat row is dense but readable.
- `playable_surface_bottom_dock_1180x820.png`: bottom dock layout renders with build, wave, and selected tower panels separated. No obvious bottom-panel overlap was observed.

Fresh validator result:

- `PLAYABLE_SURFACE_VALIDATION_OK`
- Passed checks include main scene load/instantiate, vertical slice/debug HUD presence, keyboard speed/pause paths, mouse placement/cancel/selection, target button, speed button, wave start click path, pinned 1180x600 geometry, bottom-dock 1180x820 geometry, and screenshot saves.

Residual visual caveat: this is a concrete screenshot/layout review, not a full art, animation, contrast, accessibility, or player-comprehension review.

## Performance Metrics

Fresh performance-budget validation passed.

| Metric | Observed | Budget | Result |
| --- | ---: | ---: | --- |
| Average step time | `1242.6 usec` | `5000 usec` | pass |
| Max step time | `7277 usec` | `50000 usec` | pass |
| Total stress time | `223668 usec` | `900000 usec` | pass |
| Max enemies | `120` | `160` | pass |
| Max projectiles | `3` | `120` | pass |

The stress run also reported clean runtime invariants.

## Findings

### F1. Fresh medium AI simulation failed before producing a packet

Severity: high. False-positive class: validation infrastructure or runtime failure.

The audit-required medium batch reached `240/420` runs and then Godot exited `-1`. No current root report, JSON, or generated prompt was produced, so this report cannot use fresh medium simulation telemetry. The logs do not include a script assertion or stack trace; they contain progress output and the known Windows root-certificate warning.

Recommended verification: run a smaller current-code AI batch that preserves output and narrows whether the failure is run-count, scenario-probe, or long-duration related.

### F2. Archived deep evidence contains high-severity wave accounting mismatches

Severity: high. False-positive class: likely game or telemetry accounting bug.

The archived deep report lists `615` high-severity `wave_resolution_mismatch` entries. This is implementation-actionable only after a focused reproduction against current code, because the archive is schema 5 and the fresh medium run failed before producing comparable telemetry.

Recommended verification: rerun a small focused AI batch with full action logging for a representative failing seed/strategy, then inspect wave resolution counters against current `VerticalSliceGame`.

### F3. Boss and commander pressure is scheduled but not spawned

Severity: medium. False-positive class: known vertical-slice gap.

The archived deep report scheduled boss/commander pressure but spawned `0`. Keep this out of gameplay-fix scope unless the user explicitly promotes boss/commander implementation.

### F4. Balance signals are real but not directly tune-ready

Severity: medium. False-positive class: diagnostic balance signal.

The archived deep run is large enough to ask balance questions, but tower-specialist failures, high wave/enemy leak rates, and unexercised branches still require bot-policy triage and targeted validation before cost, damage, or wave tuning.

### F5. Playable-surface validation passes but emits shutdown warnings

Severity: low. False-positive class: cleanup/resource-lifetime diagnostic.

The rendering-capable validator passed and saved screenshots, but the Godot process printed shutdown warnings for `2 ObjectDB instances` and `1 resources still in use at exit`. Treat this as a resource-lifetime follow-up, not as a scene/input failure.

## Recommended Improvements

1. Add a narrower AI simulation diagnostic profile for long-run failure triage, such as 260 runs with scenario probes enabled and explicit output preservation.
2. Reproduce `wave_resolution_mismatch` on current code with a small full-action-log batch before editing gameplay.
3. Add scenario-probe mode to comparability reporting for future reports where scenario probes are present.
4. Preserve boss/commander, reward cards, mutation, mastery, and paragon as known gaps until explicitly scoped.
5. Keep visual review tied to rendered screenshots and manual play notes, not bot telemetry.
6. Add a memory/resource lane only when a validator or profiler can produce concrete memory-growth evidence.

## Validation Results

Fresh commands run:

```powershell
git status --short
.\TOWER_DEFENSE_AI_SIMULATION.bat --test medium --scenario-probes=auto
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_prompt_metadata_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_prompt_metadata_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_scenario_probe_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_scenario_probe_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_performance_budget.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_performance_budget_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --log-file logs/godot/godot_playable_surface.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_playable_surface_validation.gd
git diff --check
git status --short
```

Fresh results:

- AI simulation batch: failed with exit code `-1` after `240/420` runs.
- `logs/godot/godot_ai_prompt_metadata_validation.log`: `AI_PROMPT_METADATA_VALIDATION_OK`.
- `logs/godot/godot_ai_scenario_probe_validation.log`: `AI_SCENARIO_PROBE_VALIDATION_OK`.
- `logs/godot/godot_performance_budget.log`: `PERFORMANCE_BUDGET_VALIDATION_OK`.
- `logs/godot/godot_playable_surface.log`: `PLAYABLE_SURFACE_VALIDATION_OK`.
- `git diff --check`: passed.

## Deferred Or Rejected Actions

- No gameplay, data, scene, asset, audio, or validation code changes were made.
- No balance tuning was made from aggregate telemetry.
- No gameplay change was made from the failed medium run.
- No export/platform/security/accessibility/localization claims are treated as proven.

## Residual Gaps

- The fresh medium AI batch failed and produced no current root packet.
- The latest complete AI packet is archived schema 5 evidence, not a current root timestamped packet.
- Scenario-probe mode is not present in the archived report.
- Full action logs are not available from the archived Markdown report.
- Visual review is limited to two refreshed screenshots and validator assertions.
- Manual playtesting, audio feedback quality, memory growth, export, and platform compatibility remain incomplete.
- Playable-surface validation passed but printed shutdown resource warnings.

## Next Recommended Action

Run one bounded AI simulation diagnostic that reproduces or clears the medium-run exit `-1`, then update this report with the exact current-code packet before making any gameplay or balance changes.
