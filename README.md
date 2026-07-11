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

1. Run `_ai_audit_workflow\RUN_AUDIT.ps1`.
2. Press Enter for the default Light audit plus one bounded safe improvement, or choose an audit-only/deep option.
3. Review `_ai_audit_workflow\_internal\current\status.json`, `findings.json`, and `improvement_queue.json`.

The default path audits the game, diagnoses evidence-backed bugs or gameplay
gaps, asks Codex to implement the next scoped improvement, and checks the
result with `git diff --check`. It refuses to apply changes in a dirty
worktree unless `-AllowDirtyApply` is explicitly supplied.

If the repo is dirty when the audit runs, results are diagnostics only by
default: the workflow writes evidence but does not create apply-ready queue
items. Use `-AllowDirtyQueue` only when intentionally queuing from the current
dirty worktree. This does not bypass the separate `-AllowDirtyApply` safety gate.

The generated AI simulation files are saved under `.godot\ai_simulation` with a
`YYYY_MM_DD_HHMM` timestamp, for example:

```text
.godot\ai_simulation\ai_simulation_codex_prompt_2026_07_05_1532.md
.godot\ai_simulation\ai_simulation_report_2026_07_05_1532.md
.godot\ai_simulation\ai_simulation_data_2026_07_05_1532.json
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
