# Godot Migration Notes

## Current State

The project is now organized around Godot-owned runtime code and project-local canonical data.

- Godot executable: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`
- Pinned Godot version: `4.7.stable.official.5b4e0cb0f`
- Project root: `C:\Users\donny\Desktop\tower_defense_godot`
- Main scene: `scenes/main.tscn`
- Main gameplay surface: `scripts/game/vertical_slice_game.gd`
- Canonical data: `data/game_data.json`

`GameData` loads `res://data/game_data.json`; active validation and launch workflows are repo-local.

## Retired Migration Links

The repo no longer carries the old-folder launcher, external data exporter, or external export checker. Active Godot code should not import external project modules, use an absolute retired project path, or regenerate canonical data from an outside folder.

The old external project itself is intentionally untouched. Deleting or archiving it remains a separate destructive action that requires explicit approval after the no-dependency gate passes.

## Implemented Godot Surface

- Godot project shell, main scene, autoloads, and debug HUD.
- Project-local data schema for config, maps, towers, branches, rewards, waves, enemy kinds, and boss-rule metadata.
- Playable `Classic Road` surface with tower placement, wave start, enemies, projectiles, leaks, rewards, game over, and victory state.
- Targeting modes, projectile movement/hit behavior, shop flow, selected tower panel, sell/refund flow, branch choice scaffolding, speed controls, and bottom-dock responsive layout.
- Asset/audio loading from `res://assets`, license checks, imported texture/audio fallback handling, and visual scene scaffold.
- Progression and run-state persistence scaffold with focused validation.
- Wave schedule, enemy kind, and speed/wave stress validation for the currently ported systems.

## Remaining Parity Work

- Finish playable mechanics for every tower family, support interaction, barracks unit, high-tier upgrade, mastery/paragon path, mutation trait, and branch-specific effect.
- Finish full enemy runtime behavior for shields, flying, splits, commanders, bosses, status effects, reward modifiers, and protocol-specific wave events.
- Add map selector, random map generation, map preview, buildability helpers, map metadata display, restart/map persistence, reward cards, research/meta-upgrade UI, wave forecast, boss panels, end screens, settings UI, and keyboard shortcut coverage.
- Add layout overlap validation for the 1180x600 viewport and bottom-dock sizes.
- Add deterministic full-playthrough smoke once the backing systems are complete.
- Test an exported desktop build and a real `user://` save path outside the sandbox.

## Validation Commands

Run from the project root. Headless Godot logs are written under `logs/godot/`.

```powershell
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_smoke.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_placeholder_smoke.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_data_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_data_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_targeting.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_targeting_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_projectile.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_projectile_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_shop.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_shop_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_upgrade_panel.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_upgrade_panel_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_asset_audio.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_asset_audio_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_persistence.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_persistence_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_enemy_kind.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_enemy_kind_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_wave_schedule.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_wave_schedule_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_speed_wave_stress.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_speed_wave_stress_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_independence.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_independence_validation.gd
git diff --check
```
