# tower_defense_godot instructions

## 1. Project-Specific Guidance

### Project Facts

* Stack: Godot 4.7, GDScript, Godot native 2D rendering.
* Godot executable: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.
* Godot project root: `C:\Users\donny\Desktop\tower_defense_godot`.
* Main scene: `scenes/main.tscn`.
* Main gameplay surface: `scripts/game/vertical_slice_game.gd`.
* Autoloads: `scripts/autoload/`.
* Validation scripts: `scripts/tools/`.
* Current canonical game data target: `data/game_data.json`.
* Treat `data/game_data.json` as committed baseline only when it is tracked and clean in Git working-tree status.
* Project docs: `README.md`, `docs/GODOT_MIGRATION_NOTES.md`, and `docs/CUTOVER_READINESS.md`.

### Product Direction

Deepen the tower defense game with richer tower mechanics, meaningful tech/progression choices, and balance-first tuning. Every tower, upgrade, enemy interaction, and progression choice should feel useful.

Priority order:

1. Gameplay depth.
2. Player choice.
3. Balance.

Avoid obvious best-in-slot options, dead picks, and unintentional power outliers.

### Project Boundaries

* Work only in this repo unless the user explicitly asks otherwise.
* Do not depend on or edit external pre-migration project folders unless the user explicitly asks.
* Reuse existing Godot nodes, autoloads, canonical data, and validation harnesses before adding new structure.
* Keep gameplay logic, data loading, persistence, assets, audio, UI, and validation separate where existing files already draw those lines.
* Own game data through `data/game_data.json` and `res://` loading.
* Preserve generated Godot import sidecars, asset manifests, license files, and local data unless the task explicitly requires touching them.
* If validation incidentally changes generated or imported files, report the paths and do not stage them without explicit approval.

### Implementation Priorities

Prefer:

* Small playable Godot slices over broad rewrites.
* Extending `scripts/game/vertical_slice_game.gd` and existing autoloads when that matches the current subsystem boundary.
* Focused validation scripts that prove the touched behavior.
* Clear tower placement, upgrades, targeting, and wave feedback.
* Readable visuals at the pinned 1180x600 viewport.
* Smooth native Godot 2D performance before heavier effects.
* Boss waves, research upgrades, tower families, and progression clarity.
* Balance-first mechanics with useful tradeoffs and no dominant or dead choices.
* Fast manual verification in the running game when visuals, input, audio, or balance change.

Avoid:

* Broad rewrites, speculative refactors, unrelated cleanup, and new dependencies.
* Replacing the parity harness instead of extending it.
* Treating current Godot coverage as full gameplay parity.
* Restoring retired old-folder fallback paths, launch helpers, exporters, or dependency wording.
* Hardcoded one-off gameplay content when canonical data already provides the needed values.
* Ignoring or regenerating tracked assets/license metadata without a specific asset task.

### Assets And Licensing

* Use original generated assets or clearly licensed assets only.
* Preserve `assets/asset_manifest.json`, `assets/licenses/kenney_assets.md`, `assets/licenses/sfx_sources.md`, and `assets/licenses/sfx_replacement_map.json` when changing asset paths or imported media.
* Do not add ripped assets, trademarked game assets, Bloons assets, RuneScape assets, Pokemon assets, or assets with unclear licensing.
* Godot `.import` files are text sidecars and should stay with their source assets when relevant.

### Project Validation

Use the narrowest relevant validation first. Common commands from the repo root write logs under `logs/godot/`:

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
```

* Run a Godot validation script when changing GDScript, scenes, project settings, assets, audio, or data-loading behavior.
* Do not write Godot logs into the project root. Every `--log-file` path, including one-off or diagnostic logs, must be under `logs/godot/`. If a root-level `godot_*.log` is created, move it under `logs/godot/` before finishing and report it.
* Run `git diff --check` before finishing doc or code changes.
* For docs-only or git-hygiene changes, `git diff --check` is usually enough unless the edit changes documented commands or validation expectations.
* Before relying on a listed validation command, verify the script path exists. If the script or required data/asset inputs are untracked or modified, report that status and treat results as active worktree evidence, not committed baseline.
* Report important failures and residual risk; do not paste long logs.

## 2. General Codex Repo Guidance

### Authority And Efficiency

* For work inside this repo, follow this `AGENTS.md` over broader repository or global guidance when allowed by higher-priority instructions.
* Minimize tokens, reads, edits, commands, and output. Make the smallest safe change.

### Work Style

* Prefer concrete findings, file paths, commands, test results, and next actions over narration.
* Do not produce filler, praise, or repeated status updates that do not add new information.
* Do not expose hidden chain-of-thought. Provide brief rationale, assumptions, evidence, and decisions instead.
* Stay scoped to the user's latest request.
* Implement directly when clear. Plan first for broad, risky, destructive, or ambiguous work.
* Ask only to avoid wrong, destructive, or unactionable changes.
* Read targeted files only; search before opening many files.
* Skip generated, vendor, cache, build, data, log, and binary files unless relevant.
* Read files directly by path instead of asking for pasted large files, reports, logs, or full test output.
* Use short summaries instead of long copied output.

### Repo Safety

* Work only in the active Git repo unless explicitly asked.
* Before editing, inspect the active path and run `git status --short`.
* Before editing files, state the intended edit briefly.
* If existing files are dirty, work with those changes and do not assume they are yours.
* Do not overwrite, revert, delete, move, rename, stage, commit, or push unless explicitly asked.
* Do not run destructive commands unless explicitly approved.
* Do not modify secrets, credentials, lockfiles, migrations, generated artifacts, or user work unless required or explicitly requested.
* Never store secrets, tokens, API keys, credentials, or private keys in repo files, prompts, memory, or config.
* After validations or commands likely to generate/import files, run `git status --short` when practical and report generated or imported paths that changed.

### Evidence And Accuracy

* Distinguish evidence from assumptions. Evidence includes inspected files, command output, tests, and cited documentation.
* Verify repo facts against current files, command output, user-provided sources, or official docs before stating them.
* Treat handoff docs, generated summaries, migration notes, Codex/OpenAI memory, and model output as clues until checked against evidence.
* Do not invent facts, files, commands, outputs, dependencies, APIs, metrics, or prior decisions.
* If evidence is missing, stale, conflicting, or inferred, say so plainly.

### Failure Handling

* Anti-loop rule: if the same approach fails twice, stop repeating it. Summarize the failure, change strategy, and proceed with a different diagnostic path.
* Blocker rule: after three unsuccessful attempts against the same blocker, stop and ask for the smallest missing input or approval needed to continue.
* If a check fails before Godot or the relevant checker starts due to sandbox, spawn, or permission handling, retry once with scoped approval if available.
* Do not treat pre-launch sandbox, spawn, or permission failures as project failures.
* Treat validation as failed only if Godot or the relevant checker launches and returns a script error, failed assertion, failed test, or nonzero exit code.

### Handoffs And State

* Keep durable repo guidance in `AGENTS.md`; update it only when durable project facts, project workflow, validation expectations, agent behavior, safety policy, output format, bounded-command policy, or coordination rules change.
* Keep mutable status, blockers, next steps, and continuation notes in repo-local `CODEX_HANDOFF.md`.
* Treat `CODEX_HANDOFF.md` as mutable status/state, not proof. Do not let it override repo evidence.
* For non-trivial work, inspect `CODEX_HANDOFF.md` if it exists after checking path and `git status --short`.
* Use `CODEX_HANDOFF.md` only when work will continue across prompts or a fresh thread.
* Do not create or update `CODEX_HANDOFF.md` for simple one-shot tasks.
* If `CODEX_HANDOFF.md` exists, reconcile it against current files, command output, and `git status`.
* If `CODEX_HANDOFF.md` is updated, keep status, changed files, commands run, validation, blockers, remaining work, and next step current.
* Keep normal project docs such as `README.md` and `docs/**` available for durable project documentation. Do not create parallel root handoff/state files such as `PROJECT_STATE.md` or `JOURNAL.md` unless explicitly requested.

### Bounded Execution

* Before broad, expensive, high-risk, or highly mutating commands, produce or confirm a bounded plan.
* A bounded plan must specify command family, scope limit, timeout or stop budget, expected artifacts or confirmation that none are expected, and stop condition.
* Include forbidden command patterns only when the command could delete, move, overwrite, import, regenerate, or mass-edit files.
* This gate applies to broad validation batches, asset/audio imports, cleanup/archive actions, dependency changes, codegen/import operations, and commands likely to touch many files.
* Routine targeted checks are exempt, including one existing listed Godot validation script, `git diff --check`, targeted searches, and narrow file reads.

### Final Response Format

* Output language has three levels. Default for this repo is `Level 1: Minimal / Plain English`.
* `Level 1`: shortest clear answer. Use plain English. Include only: result, real problems, and next action if needed.
* `Level 2`: normal answer. Include what changed, checked files/commands, problems, and one useful next step.
* `Level 3`: audit or planning answer. Include findings, evidence, risk, exact next action, and copy-paste prompt when useful.
* For messy user notes, first translate the request into one clear objective before acting.
* For copy-paste help, give one fenced prompt or command block. Do not give vague suggestions.
* Be concise and outcome-focused.
* Start with a concise opening outcome when there is a completed result to report. Include the concrete result, files touched, and checks run there instead of using a `Done` section. Omit the opening outcome only when nothing completed.
* Use concise prose for simple one-shot tasks.
* For normal implementation, status, and handoff runs, use only these real final sections in this order when structured output is needed:
  * `Problems`: write `None. Proceed status: yes.` when clear. Otherwise list only real problems or caveats as `Low`, `Medium`, or `Severe`, with concrete evidence where practical. End with `Proceed status: yes.`, `Proceed status: yes with medium problems.`, or `Proceed status: no.`
  * `Suggestions`: write `None.` only when the request is complete and no useful continuation remains. Otherwise give exactly one next action: one human decision, one bounded executable phase, or one fenced paste-ready prompt.
* Mention successful validation briefly in the opening outcome. Mention only unresolved failed checks, generated-artifact risks, or material caveats under `Problems`.
* Do not add extra final sections such as `Tests`, `Validation`, `Notes`, `Changed`, or `Next Steps` unless the user explicitly asks for that format.
* If the user asks for an audit, review, or prompt template with a specific structure, use the requested structure while preserving all repo safety rules.
* Required app directives, git directives, and memory citations may appear after the repo-local final sections, but keep them minimal.
* For `Suggestions`, use `None.` only for true terminal one-shot work. If any nontrivial, risky, broad, asset/audio import, generated-artifact, cleanup, mutating, or fresh-thread follow-up remains, prefer one fenced paste-ready prompt.
* Use a human decision only when the agent cannot safely choose.
* Use a bounded executable phase only when follow-up is ready to run. For expensive, broad, asset/audio import, generated-artifact, cleanup, or mutating work, include command family, scope limit, timeout or stop budget, artifacts, forbidden patterns, expected generated files, and stop condition.
* A paste-ready prompt must state whether the next agent should plan only or execute, name the target objective, require repo path and `git status --short` inspection, require reconciliation against `CODEX_HANDOFF.md` when it exists and current evidence, and include exact bounded scope, forbidden actions, artifacts, timeout or stop budget, stop condition, and validation expectations.
* If execution is not already safely bounded, the paste-ready prompt must request one implementable `<proposed_plan>` and explicitly say not to mutate files or run broad validation, asset/audio import, cleanup, or other mutating commands yet.
* When `CODEX_HANDOFF.md` was updated or fresh-thread continuation is likely, start the paste-ready prompt with `Continue from CODEX_HANDOFF.md.`
* Do not use vague suggestions such as `continue implementation`, `run next phase`, or `improve the game`; convert them into `None.`, one human decision, one bounded executable phase, or one fenced paste-ready prompt.
* When `CODEX_HANDOFF.md` is updated, final `Suggestions` must match its exact next recommended step.
