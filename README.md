# Tower Defense Godot

A Godot 4.7 tower defense game project.

This repo is set up so you can use Codex/ChatGPT to make game changes without needing to write code by hand.

## Start Here

Open PowerShell in this folder:

```text
C:\Users\donny\Desktop\tower_defense_godot
```

Launch the project:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\launch_godot.ps1
```

Godot should open this project. The main scene is:

```text
scenes/main.tscn
```

## Good Things To Ask Codex

Use plain English. Good requests are specific and small:

- Add a new tower with a clear strength and weakness.
- Make wave 5 harder, but still fair.
- Improve the upgrade panel so choices are easier to understand.
- Balance towers so no option is obviously best.
- Run the relevant Godot validation after changing gameplay or data.

For bigger ideas, ask Codex to make a short plan first.

## Important Files

- `data/game_data.json` controls towers, enemies, waves, prices, and upgrades.
- `scripts/game/vertical_slice_game.gd` contains the main gameplay behavior.
- `scenes/main.tscn` is the main game scene.
- `assets/` contains sprites, sounds, and license notes.
- `docs/CUTOVER_READINESS.md` tracks deeper technical status.

## AI Simulation Help

To create a Codex-ready balance report:

1. Double-click `RUN_AI_SIMULATION_PROMPT.bat`.
2. Wait for Notepad to open.
3. Copy the contents into Codex.

The generated prompt is saved here:

```text
codex_prompts\ai_simulation_latest.md
```

This is useful when you want Codex to review balance, wave difficulty, or tower performance.

## Checks

For README or documentation-only changes, this check is usually enough:

```powershell
git diff --check
```

For gameplay, data, scene, asset, or audio changes, ask Codex to run the relevant Godot validation script. The project uses this Godot executable:

```text
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe
```

Validation logs are written under:

```text
logs\godot\
```
