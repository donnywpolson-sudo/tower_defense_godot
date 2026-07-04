# Godot Migration Notes

## Project Shell

- Godot executable used for Step 2: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`
- Pinned Godot version: `4.7.stable.official.5b4e0cb0f`
- Godot project location: `C:\Users\donny\Desktop\tower_defense_godot`
- Python baseline repo: `C:\Users\donny\Desktop\tower_defense`

## Step 1 Baseline

- The Python game remains the reference baseline until parity and cutover are explicitly approved.
- Current Python baseline entry point: `tower_defense.py` -> `td_game.app.run()`.
- Current logical viewport: `1180x600` from `MAP_WIDTH=900`, `UI_WIDTH=280`, and `HEIGHT=600`.
- Main Python boundaries:
  - `td_game/config.py`: dimensions, tuning constants, starting values, render flags.
  - `td_game/data.py`: tower families, branches, upgrades, mutations, maps.
  - `td_game/waves.py`: wave schedule, modifiers, boss/commander counts.
  - `td_game/mapgen.py`: deterministic map generation and path/buildable-site checks.
  - `td_game/assets.py` and `td_game/audio.py`: asset and sound loading/fallbacks.
  - `td_game/rendering.py`: Pygame/OpenGL renderer selection and fallback.
  - `td_game/app.py`: current monolithic runtime loop, entities, combat, UI, audio, and rendering integration.

## Step 2 Scope

This step creates only the Godot project shell. It does not port gameplay.

Included in this shell:

- `project.godot`
- input actions matching the Python baseline shortcuts
- autoloads for migration config and parity harness
- placeholder bootstrap scene
- debug HUD
- placeholder-scene smoke check

## Parity Harness Status

Current harness scope:

- Confirms the placeholder scene can be loaded.
- Confirms the scene root uses the expected bootstrap script.
- Confirms the debug HUD node exists.
- Confirms project settings pin the expected viewport size and Godot minor version.

Future steps should extend this harness instead of replacing it.

## Step 2 Verification

Commands run from `C:\Users\donny\Desktop\tower_defense_godot`:

- `git status --short`
  - Result: failed because the folder is not a valid git repository. A `.git` directory exists, but Git does not recognize it as a repository.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --version`
  - Result: `4.7.stable.official.5b4e0cb0f`
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_verify.log --path C:\Users\donny\Desktop\tower_defense_godot --quit`
  - Result: project booted headless. Godot emitted a non-fatal Windows root-certificate warning.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_smoke.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_placeholder_smoke.gd`
  - Result: `PLACEHOLDER_SMOKE_OK`.

Temporary verification logs were removed after the run.

## Git Repository Status

- The empty/invalid `.git` directory was repaired with `git init`.
- Initial branch was renamed to `main`.
- `.gitignore` excludes Godot cache/output and local Codex metadata: `.godot/`, `.agents/`, `.codex/`, logs, temp files, `export/`, and `build/`.
- No files have been staged or committed yet.

## Step 3 Data Mirror

Added a Godot-side data mirror without editing the Python baseline.

Files:

- `data/python_baseline_data.json`
- `scripts/tools/export_python_baseline.py`
- `scripts/tools/validate_python_baseline_export.py`
- `scripts/autoload/game_data.gd`
- `scripts/tools/run_data_validation.gd`

Mirrored data:

- Python config values needed for parity checks.
- Tower shop order, root tower IDs, costs, tower metadata, branch definitions, target modes, and legacy aliases.
- Upgrade costs, mastery costs, research costs, and mutation traits.
- Reward card metadata and categories.
- Normalized map catalog data.
- Wave modifiers and wave 1-30 schedule rows.
- Enemy kind modifiers and boss rule formulas/overrides.

Deferred:

- Godot-side map authoring/export-import tooling. It is not needed for loading parity yet.

Step 3 verification:

- `python scripts\tools\export_python_baseline.py`
  - Result: wrote `data/python_baseline_data.json`.
- `python scripts\tools\validate_python_baseline_export.py`
  - Result: `PYTHON_BASELINE_EXPORT_OK`; compared towers, 27 branches, 4 maps, and 30 waves against the Python baseline.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_data_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_data_validation.gd`
  - Result: `DATA_VALIDATION_OK`; loaded and validated the Godot-side mirror.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_smoke.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_placeholder_smoke.gd`
  - Result: `PLACEHOLDER_SMOKE_OK`; Step 2 shell still boots with the new data autoload.

Known non-fatal environment warning:

- Godot emits `Failed to read the root certificate store` in this local headless environment.

Parity deltas:

- No data-loading parity deltas found in the checked mirror.
- Runtime gameplay is still not ported.

## Step 4 Vertical Slice

Added one playable Godot vertical slice without editing the Python baseline.

Files:

- `scripts/game/vertical_slice_game.gd`
- `scripts/tools/run_vertical_slice_smoke.gd`
- `scenes/main.tscn`
- `scripts/main.gd`
- `scripts/autoload/parity_harness.gd`

Implemented slice:

- Map: `Classic Road`, loaded from `data/python_baseline_data.json`.
- Tower family: `archer`.
- Enemy family: `normal`.
- Player action: click to place an Archer or press Space to auto-place at the recommended build site and start the slice wave.
- Combat loop: spawn, path walking, Archer target selection, projectile firing, projectile hit damage, enemy death reward, leak handling.
- Reward loop: wave-completion money and research reward for wave 1.

Focused validation:

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd`
  - Result: `VERTICAL_SLICE_SMOKE_OK`.
  - Covered Archer placement, wave start, 3 normal enemy spawns, kills/leaks resolution, Classic Road wave-1 money reward, and wave-1 research reward.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_smoke.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_placeholder_smoke.gd`
  - Result: `PLACEHOLDER_SMOKE_OK`; now also checks `VerticalSliceGame` exists in the main scene.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_data_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_data_validation.gd`
  - Result: `DATA_VALIDATION_OK`.
- `python scripts\tools\validate_python_baseline_export.py`
  - Result: `PYTHON_BASELINE_EXPORT_OK`.

Step 4 parity deltas:

- This is a deliberately narrow vertical slice, not the full Python wave runtime.
- Python wave 1 has 13 regular enemies; the Godot slice currently uses `SLICE_SPAWN_LIMIT = 3` to keep the first playable loop and automated smoke test bounded.
- Reward-card milestones, upgrades, branches, target modes beyond first-progress priority, status effects, bosses, split/flying/shielded enemies, audio, persistence, and full UI panels remain unported.
- Archer level-2 baseline stats are mirrored for the slice: cost 50, damage 39, range 163, fire rate 0.50.

## Step 5 Targeting Subsystem

Ported exactly one combat subsystem: targeting.

Files:

- `scripts/game/vertical_slice_game.gd`
- `scripts/tools/run_targeting_validation.gd`

Implemented targeting behavior:

- `first`: deepest progress.
- `last`: shallowest progress.
- `strongest`: highest HP.
- `weakest`: lowest HP.
- `closest`: nearest target fallback.
- `flying`: nearest flying target, with marked/vulnerable flying priority.
- Marked and vulnerable enemies are preferred over plain enemies for first, last, strongest, weakest, and flying targeting, matching the Python priority behavior.
- Flying attack eligibility is bounded to the current mirrored Python rules for this slice: normal Archer cannot attack flying; Tesla level 4 and Sniper level 3 can.

Focused validation:

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_targeting.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_targeting_validation.gd`
  - Result: `TARGETING_VALIDATION_OK`.
  - Covered first, last, strongest, weakest, closest fallback, marked/vulnerable priority, flying priority, and Archer non-air fallback.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd`
  - Result: `VERTICAL_SLICE_SMOKE_OK`; the playable Step 4 loop still passes.

Step 5 parity deltas:

- Mortar minimum range is not ported because mortar/projectile subsystems are outside this step.
- Shared targeting from support mechanics is not active because support interactions are outside this step.
- Target mode UI controls are not ported yet; validation exercises targeting through the smoke harness.

## Step 6 Projectile Logic Subsystem

Ported exactly one combat subsystem: projectile logic.

Files:

- `scripts/game/vertical_slice_game.gd`
- `scripts/tools/run_projectile_validation.gd`

Implemented projectile behavior:

- Projectile speed by tower family:
  - Mortar: 300.
  - Sniper, Machine Gun, Tesla: 760.
  - Archer and other default projectile towers: 420.
- Projectile cleanup when the target no longer exists.
- Movement toward target using the projectile speed and frame delta.
- Hit threshold matching the Python baseline: projectile hits when distance is under 8 px.
- Damage application on hit.
- Projectile death after hit.
- Tower damage/mastery credit on hit.

Focused validation:

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_projectile.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_projectile_validation.gd`
  - Result: `PROJECTILE_VALIDATION_OK`.
  - Covered projectile speeds, movement toward target, under-8-px hit threshold, damage application, tower damage credit, and stale-target cleanup.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd`
  - Result: `VERTICAL_SLICE_SMOKE_OK`; playable slice still passes.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_targeting.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_targeting_validation.gd`
  - Result: `TARGETING_VALIDATION_OK`; targeting still passes after projectile changes.

Step 6 parity deltas:

- Branch on-hit effects remain unported.
- Status effects, shields, splash, splitting, boss rules, and support interactions remain unported.
- Projectile trail/effect visuals and audio are not ported yet.

## Step 7 Shop UI/Flow Subsystem

Ported exactly one UI/flow subsystem: shop.

Files:

- `scripts/game/vertical_slice_game.gd`
- `scripts/tools/run_shop_validation.gd`

Implemented shop behavior:

- Sidebar shop panel with `Build Towers`, `Shop`, a tower button, cost display, affordable/selected visual state, and footer text matching the Python flow:
  - `Tap a tower to place`
  - `Selected: Archer`
- Click/tap on the shop button selects the build type without spending money.
- Map click places the selected tower only when a build type is selected, affordable, and the site is valid.
- Placement spends the Archer shop cost and clears the build selection.
- Start-wave input no longer silently auto-places the first tower; the player must use the shop placement flow first.

Focused validation:

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_shop.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_shop_validation.gd`
  - Result: `SHOP_VALIDATION_OK`.
  - Covered initial unselected state, Archer button/cost/affordability, selection without spending, selected map placement, cost deduction, selection clearing, and wave start after shop placement.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd`
  - Result: `VERTICAL_SLICE_SMOKE_OK`; playable slice still passes.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_targeting.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_targeting_validation.gd`
  - Result: `TARGETING_VALIDATION_OK`.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_projectile.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_projectile_validation.gd`
  - Result: `PROJECTILE_VALIDATION_OK`.

Step 7 parity deltas:

- Python's full shop currently exposes `machine_gun`, `cannon`, `frost`, `poison`, `support`, `sniper`, `tesla`, and `barracks`; the Godot slice exposes only the enabled Archer button because only the Archer combat family is playable so far.
- Python sprite icons, role icons, rounded chips, hover tooltips, and audio feedback remain unported.
- Upgrade panel, branch choice, map selector, wave forecast, reward cards, boss warning, and end screens remain unported.

## Step 8 Upgrade Panel UI/Flow Subsystem

Ported exactly one UI/flow subsystem: upgrade panel.

Files:

- `scripts/game/vertical_slice_game.gd`
- `scripts/tools/run_upgrade_panel_validation.gd`

Implemented upgrade-panel behavior:

- Newly placed towers become the selected tower, matching the Python placement flow.
- Clicking an existing tower selects it; clicking empty map space clears selection.
- Sidebar upgrade panel appears for the selected tower below the shop panel.
- Panel copy/state mirrors the Python selected-Archer baseline:
  - `Archer Tower`
  - `L2 | DMG 39 | Range 163`
  - `Ranger | Pick branch | Traits 0/2`
  - `Target First`
  - `Sell +$37`
- Target button cycles the selected tower target mode using the mirrored Python target-mode order.
- Sell button removes the selected tower, clears selection, and refunds `int(50 * 0.75) = 37`, matching Python sell-refund logic.

Focused validation:

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_upgrade_panel.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_upgrade_panel_validation.gd`
  - Result: `UPGRADE_PANEL_VALIDATION_OK`.
  - Covered selected-tower panel visibility, tower name, stats copy, branch-gate copy, target label, sell refund, target cycling, sell removal, refund money, and panel hiding after sell.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_shop.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_shop_validation.gd`
  - Result: `SHOP_VALIDATION_OK`; shop placement still passes with selected-tower state.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd`
  - Result: `VERTICAL_SLICE_SMOKE_OK`; playable slice still passes.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_targeting.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_targeting_validation.gd`
  - Result: `TARGETING_VALIDATION_OK`.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_projectile.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_projectile_validation.gd`
  - Result: `PROJECTILE_VALIDATION_OK`.

Step 8 parity deltas:

- Branch-choice buttons are intentionally not implemented in this run; the panel stops at the Python `Pick branch` gate for the Archer slice.
- Mutations, high-tier research upgrade gates, paragon/mastery upgrade rows, keyboard shortcuts, hover tooltips, icons, and audio feedback remain unported.
- Full upgrade application is deferred until branch choice and the broader tower progression model are ported.
- Map selector, wave forecast, reward cards, boss warning, and end screens remain unported.

## Step 9 Assets, Visuals, and Audio

Ported Godot-side asset/audio loading without changing Python rendering paths.

Files and directories:

- `assets/`
- `project.godot`
- `scripts/autoload/game_assets.gd`
- `scripts/autoload/game_audio.gd`
- `scripts/game/vertical_slice_game.gd`
- `scripts/tools/run_asset_audio_validation.gd`
- `scripts/visuals/asset_sprite_visual.gd`
- `scenes/visuals/asset_sprite_visual.tscn`
- `shaders/sprite_flash.gdshader`

Asset import/provenance:

- Copied the Python baseline `assets/` tree into the Godot project.
- Preserved:
  - `assets/asset_manifest.json`
  - `assets/licenses/kenney_assets.md`
  - `assets/licenses/sfx_sources.md`
  - `assets/licenses/sfx_replacement_map.json`
  - `assets/maps/map_catalog.json`
- Ran Godot 4.7 headless import:
  - `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --import --quit --log-file godot_import.log --path C:\Users\donny\Desktop\tower_defense_godot`
  - Result: Godot generated `.import` sidecars for 215 PNG/WAV/OGG source assets.
- Import settings now represented by generated Godot `.import` files:
  - PNG textures import as `CompressedTexture2D`, no mipmaps, alpha border fix enabled.
  - WAV files import as `AudioStreamWAV`, compressed mode 2.

Godot asset/audio behavior:

- `GameAssets` loads `res://assets/asset_manifest.json`, checks license files, loads textures by Python-relative asset path, and reports fallback status for missing textures.
- `GameAudio` mirrors Python audio lookup behavior:
  - Tries requested `.wav` first.
  - Falls back to same-name `.ogg`.
  - Generates an `AudioStreamWAV` tone if no file loads.
- The vertical slice now uses imported assets when available:
  - grass texture for map background
  - spawn/base gate sprites
  - Archer idle animation frames
  - normal enemy walk animation frames
  - Archer projectile sprite
- Shape/circle drawing remains as the visual fallback when textures are unavailable.
- Build, sell, wave-start, and wave-complete events route through `GameAudio` with generated-tone fallback.
- Added `asset_sprite_visual.tscn` with `Sprite2D`, `AnimationPlayer`, and `sprite_flash.gdshader` as the reusable scene/shader/animation scaffold for the Python sprite/flash behavior.

Focused validation:

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_asset_audio.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_asset_audio_validation.gd`
  - Result: `ASSET_AUDIO_VALIDATION_OK`.
  - Covered manifest load, license-file presence, CC0 provenance, key texture loads, missing texture fallback reporting, key sound loads, missing sound generated-tone fallback, and visual scene/shader scaffold load.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd`
  - Result: `VERTICAL_SLICE_SMOKE_OK`.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_shop.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_shop_validation.gd`
  - Result: `SHOP_VALIDATION_OK`.
- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_upgrade_panel.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_upgrade_panel_validation.gd`
  - Result: `UPGRADE_PANEL_VALIDATION_OK`.
- Additional guardrails after adding the asset/audio autoloads:
  - `PLACEHOLDER_SMOKE_OK`
  - `DATA_VALIDATION_OK`
  - `TARGETING_VALIDATION_OK`
  - `PROJECTILE_VALIDATION_OK`

Step 9 parity deltas:

- Godot now consumes the current asset files, but only the vertical-slice visuals are wired into gameplay.
- Python OpenGL/Pygame renderer selection remains unported; Godot uses its native 2D renderer.
- Python particle/glow caches and many effect sprites are imported but not yet attached to gameplay effects.
- Python music loop/boss-loop state, audio toggles, per-tower firing cooldowns, and full sound event coverage remain incomplete.
- Terrain road rendering still uses drawn path lines over a texture background rather than textured road segments.
- Branch choice, map selector, wave forecast, reward cards, boss warning, and end screens remain unported.

## Step 10 Persistence and Progression

Added Godot-side persistence/progression without editing the Python baseline.

Files:

- `scripts/autoload/game_progress.gd`
- `scripts/game/vertical_slice_game.gd`
- `scripts/tools/run_persistence_validation.gd`
- `project.godot`

Implemented state:

- `GameProgress` autoload with schema version `1`.
- Default production save path: `user://tower_defense_godot_save.json`.
- Non-overwrite save behavior: `save_to_path(..., overwrite=false)` refuses to replace an existing file.
- Progression fields mirroring the Python meta-upgrade state:
  - stars
  - starting money bonus
  - tower damage bonus
  - starting research bonus
  - reward card choice bonus
  - starting lives bonus
- Settings scaffold:
  - `sfx_enabled`
  - `music_enabled`
  - `game_speed`
- Vertical-slice run state serialization/restoration for the currently ported surface:
  - money, lives, research, wave state, spawn state, rewards, selected build/selected tower
  - towers
  - enemies
  - projectiles, restored through tower/enemy indices so live references are rebuilt safely

Python parity covered:

- Starting money upgrade: `STARTING_MONEY + level * 25`.
- Starting lives upgrade: `STARTING_LIVES + level * 2`.
- Starting research upgrade: `level * 2`.
- Tower damage upgrade: `1.0 + level * 0.05`.
- Intel upgrade maxes at level 6 and returns no further cost.
- Intel max copy mirrors Python: `Wave Intel`, `Lv 6 | MAX`.

Focused validation:

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_persistence.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_persistence_validation.gd`
  - Result: `PERSISTENCE_VALIDATION_OK`.
  - Covered progression purchases, Python-aligned starting defaults, tower damage bonus, save/load, non-overwrite behavior, run-state restore, process-step survival after restore, and main scene reload survival.
- The validation used a unique ignored temp file under `res://.godot/` and removed it afterward. It did not overwrite player/local save data. The production default remains `user://tower_defense_godot_save.json`; this local sandbox blocks writing to the Godot AppData `user://` path.

Step 10 parity deltas:

- Python currently keeps these meta-progression/run-state values in memory; Godot now has a durable save/load scaffold for the migrated state.
- Full Python crash-state coverage is not complete because many systems are still unported.
- No profile UI, manual save slot UI, settings menu, map selector persistence, reward-card state, boss state, branch state, or end-screen flow is ported yet.
- The persistence harness only covers the current vertical slice surface.

## Step 11 Cutover Preparation

Prepared cutover documentation and launch helpers without deleting, moving, renaming, retiring, or editing Python baseline files.

Files:

- `README.md`
- `docs/CUTOVER_READINESS.md`
- `scripts/launch_godot.ps1`
- `scripts/launch_python_baseline.ps1`
- `project.godot`

Cutover decision:

- Full cutover is not approved yet because parity is not complete.
- The Godot project is now documented as the primary migrated run path for continued migration work.
- The Python baseline remains available through `scripts/launch_python_baseline.ps1` and remains the source-of-truth fallback at `C:\Users\donny\Desktop\tower_defense`.

Launcher behavior:

- `scripts/launch_godot.ps1` validates `C:\Users\donny\Desktop\tower_defense_godot` and `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`, then runs Godot with `--path`.
- `scripts/launch_python_baseline.ps1` validates `C:\Users\donny\Desktop\tower_defense\tower_defense.py`, then runs the Python baseline from its own repo root.

Cleanup list:

- `docs/CUTOVER_READINESS.md` now lists Python-only glue/dead-path candidates to review after full parity and explicit approval.
- No Python files were removed or modified in this step.

Step 11 release risks:

- Current Godot coverage is still a vertical slice and smoke harness set, not full gameplay parity.
- No exported Godot desktop build has been produced or tested.
- Save/load lacks a player-facing UI and real profile migration path.
- The worktree remains uncommitted.

## Step 12 Checkpoint And Publish

Prepared a validation-backed GitHub checkpoint without retiring Python files or performing final cutover.

Checkpoint scope:

- No Python baseline files were deleted, moved, renamed, retired, or edited.
- Python cleanup remains explicitly unapproved for this run.
- Godot remains the primary migrated path for continued work, while Python remains the baseline fallback.
- Publish target: `https://github.com/donnywpolson-sudo/tower_defense_godot.git` on branch `main`.
- Commit message: `Add Godot migration checkpoint`.

Launcher verification:

- `scripts/launch_godot.ps1` parsed successfully.
- `scripts/launch_python_baseline.ps1` parsed successfully.
- Verified local path presence for:
  - `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`
  - `C:\Users\donny\Desktop\tower_defense_godot`
  - `C:\Users\donny\Desktop\tower_defense`
  - `C:\Users\donny\Desktop\tower_defense\tower_defense.py`

Validation results:

- `PLACEHOLDER_SMOKE_OK`
- `DATA_VALIDATION_OK`
- `VERTICAL_SLICE_SMOKE_OK`
- `TARGETING_VALIDATION_OK`
- `PROJECTILE_VALIDATION_OK`
- `SHOP_VALIDATION_OK`
- `UPGRADE_PANEL_VALIDATION_OK`
- `ASSET_AUDIO_VALIDATION_OK`
- `PERSISTENCE_VALIDATION_OK`

Known non-fatal warning:

- Godot headless emitted `Failed to read the root certificate store` on this Windows machine.

Step 12 remaining risks:

- Full cutover remains blocked by the parity gaps listed in `docs/CUTOVER_READINESS.md`.
- Current validations are smoke/regression checks, not full playthrough or exported-build release validation.
- Production `user://` persistence still needs a real desktop/editor run check outside this sandbox.
