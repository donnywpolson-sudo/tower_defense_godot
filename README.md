# Tower Defense Godot

A Godot 4.7 tower defense game project.

This repo is set up so you can use Codex/ChatGPT to make game changes without needing to write code by hand.

## Start Here

Open PowerShell in the repository folder.

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

## Runtime Upgrades, Rewards, and Saves

Seven level-3 branches are currently selectable: Cannon Artillery and
Demolition; Frost Glacier and Shatter; and Poison Plague Mist, Venom Cask, and
Wildfire. Other branch definitions are design data only. The game hides them
and rejects direct attempts to purchase them without charging currency.

Reward cards start with three choices. Wave Intel adds one choice per rank, up
to the nine-choice cap. Damage, attack-speed, range, and pierce rewards are
cumulative run modifiers: existing towers are recomputed and new or upgraded
towers inherit the same modifiers. Current saves persist those modifiers,
pending reward choices, reward history, pierce state, and stable tower/source
IDs. Legacy saves remain supported and retain their stored tower statistics.

## AI Simulation Help

To create a Codex-ready balance report:

1. Run `_ai_audit_workflow\RUN_AUDIT.ps1`.
2. Press Enter for the default Medium report-only audit, or choose Smoke, Deep, or Overnight.
3. Review `_ai_audit_workflow\_internal\current\status.json`, `findings.json`, and `improvement_queue.json`.

The default path audits the game and produces a self-identifying packet plus an
evidence-backed queue. It is report-only. When the queue is valid, copy
`_ai_audit_workflow\_internal\current\next_improvement_prompt.md` into Codex
to pursue all queued findings autonomously; the prompt still requires current-
code verification and focused validation for every item. The explicit
`-NextFix` or `-AutoImprove` paths remain available for one-at-a-time guarded
application.

If the repo is dirty when the audit runs, results are diagnostics only by
default: the workflow writes evidence but does not create apply-ready queue
items. Use `-AllowDirtyQueue` only when intentionally queuing from the current
dirty worktree. This does not bypass the separate `-AllowDirtyApply` safety gate.

The authoritative profile contract is `_ai_audit_workflow\_internal\config.json`.
It defines Smoke, Medium, Deep, and Overnight; `Light` is a compatibility alias
for Medium. Every packet writes matching JSON, Markdown, prompt, and manifest
artifacts with one packet identity. Use `--record=flagged` for compact evidence
or `--record=full` when a complete action log is required.

Generated AI simulation files are saved under `.godot\ai_simulation` with a
packet identity and timestamp, for example:

```text
.godot\ai_simulation\ai_simulation_codex_prompt_2026_07_05_1532.md
.godot\ai_simulation\ai_simulation_report_2026_07_05_1532.md
.godot\ai_simulation\ai_simulation_data_2026_07_05_1532.json
.godot\ai_simulation\ai_simulation_manifest_2026_07_05_1532.json
```

This is useful when you want Codex to review balance, wave difficulty, or tower performance.

## Checks

For README or documentation-only changes, this check is usually enough:

```powershell
git diff --check
```

For gameplay, data, scene, asset, or audio changes, ask Codex to run the relevant
Godot validation script. `scripts\launch_godot.ps1` resolves Godot from an
explicit `-GodotExe`, then `GODOT4_EXE`, then the documented sibling fallback,
and finally `godot4` on `PATH`.

Validation logs are written under:

```text
logs\godot\
```
