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
