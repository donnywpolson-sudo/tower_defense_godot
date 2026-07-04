# tower_defense_godot instructions

## Project Facts

* Stack: Godot 4.7, GDScript, Godot native 2D rendering.
* Godot executable: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.
* Godot project root: `C:\Users\donny\Desktop\tower_defense_godot`.
* Python baseline root: `C:\Users\donny\Desktop\tower_defense`.
* Main scene: `scenes/main.tscn`.
* Main gameplay surface: `scripts/game/vertical_slice_game.gd`.
* Autoloads: `scripts/autoload/`.
* Validation scripts: `scripts/tools/`.
* Project docs: `README.md`, `docs/GODOT_MIGRATION_NOTES.md`, and `docs/CUTOVER_READINESS.md`.

## Project Goal

Deepen the tower defense game with richer tower mechanics, meaningful tech/progression choices, and balance-first tuning. Every tower, upgrade, enemy interaction, and progression choice should feel useful. Avoid obvious best-in-slot options, dead picks, and unintentional power outliers.

Priority: gameplay depth, then player choice, then balance.

## Workflow

* Focus on the user's latest request.
* Confirm the active workspace path before editing.
* Check `git status --short` before editing.
* Read only the files needed for the current task.
* Make one small, safe, reviewable change at a time.
* Verify repo facts against current files, command output, user-provided sources, or official docs before stating them.
* Treat handoff docs, generated summaries, and old Python notes as clues, not proof.
* Do not invent facts; if evidence is missing, stale, conflicting, or inferred, say so.
* Ask only when needed to avoid a wrong, unsafe, or destructive change.

## Scope Control

* Work only in this repo unless the user explicitly asks otherwise.
* Preserve the Python baseline until full parity and final cutover are explicitly approved.
* Reuse existing Godot nodes, autoloads, data mirrors, and validation harnesses before adding new structure.
* Avoid broad rewrites, speculative refactors, unrelated cleanup, and new dependencies.
* Do not overwrite, revert, delete, move, rename, stage, commit, or push unless explicitly asked.
* Preserve user work, generated Godot import sidecars, asset manifests, license files, and local data unless the task explicitly requires touching them.
* If validation incidentally changes generated or imported files, report the paths and do not stage them without explicit approval.

## Multi-Step Work

Use repo-local `CODEX_HANDOFF.md` only when work will continue across prompts or a fresh thread.

* Do not create or update it for simple one-shot tasks.
* If it exists, reconcile it against current files, command output, and `git status`.
* If you update it, keep status, changed files, commands run, validation, blockers, remaining work, and next step current.

## Implementation Rules

Prefer:

* Small playable Godot slices over broad rewrites.
* Extending `scripts/game/vertical_slice_game.gd` and existing autoloads only when that matches the current subsystem boundary.
* Keeping gameplay logic, data loading, persistence, assets, audio, UI, and validation separate where existing files already draw those lines.
* Data parity through `data/python_baseline_data.json` and `scripts/tools/export_python_baseline.py` until Godot owns canonical game data.
* Focused validation scripts that prove the touched behavior.

Avoid:

* Replacing the parity harness instead of extending it.
* Treating current Godot coverage as full gameplay parity.
* Removing Python fallback paths, launch helpers, or baseline references before approved cutover.
* Ignoring or regenerating tracked assets/license metadata without a specific asset task.
* Hardcoded one-off gameplay content when the mirrored data already provides the needed values.

## Gameplay And UI Priorities

When choosing implementation details, prioritize:

1. Clear tower placement, upgrades, targeting, and wave feedback.
2. Readable visuals at the pinned 1180x600 viewport.
3. Smooth native Godot 2D performance before heavier effects.
4. Boss waves, research upgrades, tower families, and progression clarity.
5. Balance-first mechanics with useful tradeoffs and no dominant or dead choices.
6. Fast manual verification in the running game when visuals, input, audio, or balance change.

## Asset And Licensing Rules

* Use original generated assets or clearly licensed assets only.
* Preserve `assets/asset_manifest.json`, `assets/licenses/kenney_assets.md`, `assets/licenses/sfx_sources.md`, and `assets/licenses/sfx_replacement_map.json` when changing asset paths or imported media.
* Do not add ripped assets, trademarked game assets, Bloons assets, RuneScape assets, Pokemon assets, or assets with unclear licensing.
* Godot `.import` files are text sidecars and should stay with their source assets when relevant.

## Validation Rules

Use the narrowest relevant validation first. Common commands from the repo root:

```powershell
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_smoke.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_placeholder_smoke.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_data_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_data_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_vertical_slice.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_vertical_slice_smoke.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_targeting.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_targeting_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_projectile.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_projectile_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_shop.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_shop_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_upgrade_panel.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_upgrade_panel_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_asset_audio.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_asset_audio_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file godot_persistence.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_persistence_validation.gd
python scripts\tools\validate_python_baseline_export.py
```

* Run `git diff --check` before finishing doc or code changes.
* Run a Godot validation script when changing GDScript, scenes, project settings, assets, audio, or data-loading behavior.
* For docs-only or git-hygiene changes, `git diff --check` is usually enough unless the edit changes documented commands or validation expectations.
* Report important failures and residual risk; do not paste long logs.

## Output Style

* Be concise and outcome-focused.
* Report what changed, what was verified, and what remains.
* State blockers concretely, with the next required action.
