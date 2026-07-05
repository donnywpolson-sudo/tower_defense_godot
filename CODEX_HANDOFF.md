# Codex Handoff

This file is mutable continuation state only. Treat it as a point-in-time
handoff for the active workspace, not as durable project proof or a validation
certificate.

## Current Git State

Captured during rewrite on 2026-07-04 from
`C:\Users\donny\Desktop\tower_defense_godot`.

Dirty and untracked paths below are active workspace evidence, not committed
baseline:

```text
 M .gitignore
 M AGENTS.md
 M README.md
 D data/python_baseline_data.json
 M docs/CUTOVER_READINESS.md
 M docs/GODOT_MIGRATION_NOTES.md
 M project.godot
 M scripts/autoload/game_config.gd
 M scripts/autoload/game_data.gd
 M scripts/autoload/parity_harness.gd
 M scripts/game/vertical_slice_game.gd
 D scripts/launch_python_baseline.ps1
 D scripts/tools/export_python_baseline.py
 M scripts/tools/run_data_validation.gd
 M scripts/tools/run_enemy_kind_validation.gd
 M scripts/tools/run_persistence_validation.gd
 M scripts/tools/run_shop_validation.gd
 M scripts/tools/run_upgrade_panel_validation.gd
 M scripts/tools/run_vertical_slice_smoke.gd
 D scripts/tools/validate_python_baseline_export.py
 M scripts/ui/debug_hud.gd
?? CODEX_HANDOFF.md
?? TOWER_DEFENSE_AI_SIMULATION.bat
?? codex_prompts/
?? data/game_data.json
?? logs/
?? scripts/autoload/game_progress.gd.uid
?? scripts/tools/run_ai_simulation_batch.gd
?? scripts/tools/run_enemy_kind_validation.gd.uid
?? scripts/tools/run_independence_validation.gd
?? scripts/tools/run_persistence_validation.gd.uid
?? scripts/tools/run_speed_wave_stress_validation.gd
?? scripts/tools/run_wave_schedule_validation.gd
?? scripts/tools/run_wave_schedule_validation.gd.uid
```

## Changed Surfaces

- Git/status state shows broad active work across Godot project settings, docs, autoloads, main gameplay, UI HUD, and validation scripts.
- Runtime/data ownership appears centered on `data/game_data.json`, but that file is untracked and must not be called committed baseline yet.
- Retired Python-baseline files are deleted in the working tree; treat those deletions as active work until reviewed or committed.
- Several new validation and simulation helper scripts are untracked; treat their results as dirty-worktree evidence.
- `logs/` and generated/latest AI simulation prompts exist locally; they are useful clues but not committed project state.
- Durable roadmap context belongs in `docs/GODOT_MIGRATION_NOTES.md` and `docs/CUTOVER_READINESS.md`, not in this handoff.

## Roadmap Phase Driver State

- Current phase completed: Phase 11, Defer deterministic replay, state snapshotting, and broad chaos mode.
- Phase 3 completed work: `scripts/game/vertical_slice_game.gd` has lightweight runtime invariant checks for global run state, towers, enemies, and projectiles. Checks run after key state transitions and are throttled during simulation ticks.
- Phase 4 completed work: `scripts/tools/run_golden_scenario_validation.gd` adds fixed opening-wave and upgrade-plus-mid-combat-restore golden scenarios.
- Phase 5 completed work: `scripts/autoload/game_data.gd` now exposes `validate_balance_sanity()`, and `scripts/tools/run_balance_sanity_validation.gd` runs conservative static checks for opening economy, upgrade ladders, enemy modifiers, wave pressure, modifier effect bounds, and map reward/path bounds.
- Phase 6 completed work: `scripts/tools/run_ai_simulation_batch.gd` now includes canonical preflight summaries from `GameData.validate_game_data()` and `GameData.validate_balance_sanity()`, reports preflight validation issues, and consumes `VerticalSliceGame.runtime_invariant_failures()` during wave simulation checks.
- Phase 7 completed work: `scripts/game/vertical_slice_game.gd` now has a disabled-by-default debug overlay toggle/API, `debug_overlay_snapshot()` for economy/wave/tower/enemy/projectile state, and map-space debug drawing for tower ranges, target lines, enemy labels, projectile target lines, and compact economy/wave counts. `scripts/ui/debug_hud.gd` now shows a compact debug status line only when the same overlay snapshot is enabled. `scripts/tools/run_debug_overlay_validation.gd` validates the debug gate, snapshot contents, and HUD visibility.
- Phase 8 completed work: `scripts/game/vertical_slice_game.gd` now exposes debug-gated commands through `run_debug_command()` and `debug_command_names()`. Commands currently include `give_money`, `set_wave`, `spawn_enemy`, `kill_all_enemies`, and `skip_wave`; they mutate the live game state and remain disabled unless the debug overlay/dev gate is enabled. `scripts/tools/run_debug_commands_validation.gd` validates disabled-state behavior, the command allowlist, money mutation, wave setting, canonical enemy spawning, enemy cleanup, skip-wave reward behavior, unknown-command rejection, and invariant cleanliness.
- Phase 9 completed work: `scripts/tools/run_save_load_torture_validation.gd` adds focused save/load torture coverage for active combat file roundtrip with live projectile target/tower links, upgrade and selected-tower state restore, debug-command skip-wave reward restore, and game-over restore. `scripts/tools/run_persistence_validation.gd` now derives the progressed archer damage expectation from the current gameplay formula and progression multiplier instead of a stale hardcoded value.
- Phase 10 completed work: `scripts/tools/run_performance_budget_validation.gd` adds a targeted headless simulation performance budget gate. It builds five towers, uses debug-gated canonical spawn commands to create 120 enemies on wave 10, measures 180 simulation steps, and gates average step time, max step time, total stress time, enemy count, projectile count, and runtime invariant cleanliness.
- Phase 11 completed work: deterministic replay, state snapshotting, and broad chaos mode remain intentionally deferred. Current inspected evidence shows useful prerequisites now exist: `scripts/game/vertical_slice_game.gd` has `serialize_run_state()` / `restore_run_state()`, runtime invariants, debug overlay snapshots, and debug-gated commands; `scripts/tools/run_ai_simulation_batch.gd` has seeded AI simulation and edge/speed-stress policies; `scripts/tools/run_save_load_torture_validation.gd` and `scripts/tools/run_performance_budget_validation.gd` cover save/load torture and stress budgets. However, there is still no dedicated recorder for player inputs/timing/build hashes/checkpoints, no rewindable state-snapshot timeline, and no broad chaos-mode runner that randomly combines gameplay, UI, persistence, settings, pause/speed, and debug-command mutations.
- Validation run: none; Phase 11 is an explicit defer-only roadmap phase and no gameplay/data code changed.
- Diff gate: `git diff --check` passed.
- Caveat: results are active dirty-worktree evidence because `data/game_data.json`, `scripts/tools/run_ai_simulation_batch.gd`, and several helper scripts remain untracked.
- Next phase: none; roadmap phases 1-11 have now been handled in this phase-driver pass.

## Evidence

The rows below are observed local log evidence from dirty/untracked worktree
state. Existing logs were inspected during this rewrite; no Godot validation
was rerun here. Command provenance is not reconstructed when the exact command
was not recorded.

| Provenance | Log path | Observed token | Log file modified timestamp | Caveat |
| --- | --- | --- | --- | --- |
| script inferred from log filename | `logs/godot/godot_smoke.log` | `PLACEHOLDER_SMOKE_OK` | 2026-07-04 3:35:41 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_data_validation_root_20260704_151020.log` | `DATA_VALIDATION_OK` | 2026-07-04 3:10:20 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_vertical_slice_root_20260704_151227.log` | `VERTICAL_SLICE_SMOKE_OK` | 2026-07-04 3:12:27 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_targeting_root_20260704_151020.log` | `TARGETING_VALIDATION_OK` | 2026-07-04 3:10:20 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_projectile_root_20260704_151020.log` | `PROJECTILE_VALIDATION_OK` | 2026-07-04 3:10:20 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_shop_root_20260704_151232.log` | `SHOP_VALIDATION_OK` | 2026-07-04 3:12:32 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_upgrade_panel.log` | `UPGRADE_PANEL_VALIDATION_OK` | 2026-07-04 3:12:39 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_asset_audio.log` | `ASSET_AUDIO_VALIDATION_OK` | 2026-07-04 3:10:20 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_persistence_root_20260704_151020.log` | `PERSISTENCE_VALIDATION_OK` | 2026-07-04 3:10:20 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_enemy_kind_root_20260704_151020.log` | `ENEMY_KIND_VALIDATION_OK` | 2026-07-04 3:10:20 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_wave_schedule_root_20260704_151244.log` | `WAVE_SCHEDULE_VALIDATION_OK` | 2026-07-04 3:12:44 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_speed_wave_stress.log` | `SPEED_WAVE_STRESS_VALIDATION_OK` | 2026-07-04 3:10:21 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_independence.log` | `INDEPENDENCE_VALIDATION_OK` | 2026-07-04 3:10:20 PM | observed local log evidence from dirty/untracked worktree |
| script inferred from log filename | `logs/godot/godot_ai_simulation.log` | `AI_SIMULATION_BATCH_OK` | 2026-07-04 3:35:00 PM | observed local log evidence from dirty/untracked worktree |

Known local warning seen in several logs: Godot headless may emit
`Failed to read the root certificate store` on this Windows machine.

## Known Risks

- `data/game_data.json` is untracked in the captured status and must not be
  described as committed baseline until Git state proves that.
- Generated/latest AI simulation files are non-durable evidence and can go
  stale; verify them against current code before acting on them.
- Logs under `logs/` may be ignored/generated and are not committed project
  state. Stale or missing logs are not proof.
- Static scan claims were omitted because exact command/result provenance was
  not retained in the old handoff and no current continuation need required
  rerunning them during this rewrite.

## Blockers

- Destructive cleanup of the external pre-migration folder still requires
  explicit user approval after a no-reference validation run with that folder
  unavailable.

## Recommended Next Action

Roadmap phases 1-11 have now been handled. Recommended next action is to review, group, and commit the dirty worktree intentionally before starting a new roadmap.
