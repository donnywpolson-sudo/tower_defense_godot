# AI Simulation Audit Workflow

This file is the durable audit workflow/spec for the Godot tower defense AI simulation audit. It defines what to inspect, how to choose evidence, how to classify coverage, and what the latest report must contain.

Do not store run-specific findings, metrics, scorecards, screenshots summaries, performance numbers, validation outcomes, or recommendations in this file. Write that output to `TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md`.

## Purpose

Audit the generated AI simulation prompt workflow and its supporting evidence packet so downstream Codex work does not over-trust bot telemetry, skip verification, or convert weak diagnostics into gameplay, balance, scene, UI, audio, or manual-play claims.

The audit is verification-first. If no confirmed implementation issue exists, make no gameplay or data changes and report why.

## Evidence Discovery Order

1. Run `git status --short` and record whether relevant files are dirty.
2. Prefer the newest timestamped packet in `.godot/ai_simulation/`:
   - `ai_simulation_report_YYYY_MM_DD_HHMM.md`
   - `ai_simulation_data_YYYY_MM_DD_HHMM.json`
   - `ai_simulation_codex_prompt_YYYY_MM_DD_HHMM.md`
3. If no root timestamped packet exists, use the newest complete packet under `.godot/ai_simulation/archive/` and state that fallback in the report.
4. Add supporting evidence from existing logs and artifacts when present:
   - `logs/godot/godot_playable_surface.log`
   - `logs/godot/visual_review/*.png`
   - `logs/godot/godot_performance_budget.log`
   - focused Godot validation logs under `logs/godot/`
5. Treat generated reports, handoffs, screenshots, logs, and memory as evidence to verify, not as proof of current implementation quality.

## Minimum Coverage Evidence Bundle

For a broad current audit, collect or explicitly mark missing each item below. Missing items are allowed, but the report must list them as coverage gaps instead of filling them with AI simulation inference.

```powershell
git status --short
.\TOWER_DEFENSE_AI_SIMULATION.bat medium --scenario-probes=auto
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_prompt_metadata_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_prompt_metadata_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_scenario_probe_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_scenario_probe_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_performance_budget.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_performance_budget_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --log-file logs/godot/godot_playable_surface.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_playable_surface_validation.gd
git diff --check
```

The playable-surface command needs a rendering-capable Godot session because it saves screenshots under `logs/godot/visual_review/`. Do not treat a headless or dummy-rendering failure to produce screenshots as visual proof.

## Required Checks

1. Identify exact report, JSON, and generated prompt paths audited.
2. Verify profile, evidence tier, run count, max waves, seed settings, strategy group, full-action-log mode, schema version, and scenario-probe mode.
3. Check whether smoke/custom evidence is marked as not balance-actionable and whether stronger same-folder evidence is surfaced.
4. Check whether generated prompts are verification-first and allow a no-code-change outcome.
5. Check whether known vertical-slice gaps are excluded from implementation scope unless explicitly requested.
6. Separate direct API simulation evidence from scene validation, screenshot review, audio/input proof, manual playtesting, and subjective balance claims.
7. Check regression comparability gates: schema, profile, evidence tier, run size, seeds, strategy list, strategy group, full-action-log mode, and scenario-probe mode.
8. Check whether balance findings avoid over-claiming when sample sizes or bot policy quality are insufficient.
9. For every implementation-driving finding, require report path, JSON path, schema version, evidence tier, profile, runs, max waves, seed details, strategy, run id or scenario id, wave, issue id, false-positive class, and exact rerun or validation command.

## Coverage Lanes

Keep coverage lanes separate. Passing one lane does not imply passing the others.

| Lane | Evidence it can support | Evidence it cannot support alone |
| --- | --- | --- |
| Direct API simulation | Runtime invariants, economy, waves, tower use, upgrade paths, seeded bot telemetry, rough balance pressure, and repro candidates through `VerticalSliceGame`. | Scene wiring, rendered visuals, audio timing, manual input feel, player comprehension, export behavior, or release confidence. |
| Scenario probes | Curated tower-family, branch, enemy-kind, scheduled-wave, and edge-case diagnostics for the exact probe mode that ran. | Full-scene behavior, broad statistical balance, visual quality, audio quality, or manual play feel. |
| Scene/input validation | Main scene loading, autoload wiring, UI interaction paths, mouse/keyboard flows, speed controls, wave-start flow, and viewport geometry covered by validators. | Subjective feel, full visual QA, audio usefulness, or unaudited platform/export behavior. |
| Screenshot/visual review | Concrete defects visible in real Godot-rendered frames, including overlap, clipped text, blank panels, missing assets, bad z-order, contrast, and readability problems. | Gameplay correctness, audio, balance, invisible runtime state, or fun. |
| Performance/stress validation | Step-time budgets, enemy/projectile stress, speed-control stress, and clean runtime invariants under the validator's configured load. | Memory growth, export performance, manual-play smoothness on other machines, or visual clarity. |
| Audio/assets validation | Asset loadability, bus/routing checks, missing configured resources, and audio metadata covered by validators. | Timing, mix quality, cue usefulness, player comprehension, or music/SFX feel without scene or manual review. |
| Manual playtesting | Feel, pacing, learnability, player comprehension, subjective balance, and whether tower/progression choices feel meaningful. | Deterministic regression proof, statistical balance, or code-level root cause without supporting logs or repros. |

## Coverage Areas

For each area, classify current evidence as `proven`, `partially proven`, `not proven`, `not supported`, or `out of scope`. Assign a 0-100 score only when the area is relevant. Do not claim coverage from AI simulation alone when the area requires scene, visual, audio, platform, export, manual-play, or external validation.

| Audit area | What to check |
| --- | --- |
| Core gameplay rules | Win/loss states, scoring, damage, cooldowns, movement rules, resource use, wave progression, tower upgrades, research, and progression logic. |
| Player input | Mouse placement, hover, cancel, upgrade clicks, targeting selection, keyboard shortcuts, pause behavior, speed controls, rapid-input edge cases, and controller/rebinding only if supported. |
| Physics and collisions | Collision layers and masks, hitboxes, hurtboxes, raycasts, `Area2D`, projectile contact, path blocking, tunneling, stuck states, and any `RigidBody` or `CharacterBody` usage. |
| Scene and node lifecycle | Scene loading and unloading, duplicate nodes, orphaned nodes, `_ready`, `_process`, `_physics_process`, freed-node errors, restart flow, and scene reload behavior. |
| Signals and events | Missing or disconnected signals, duplicate signal connections, event order bugs, UI/gameplay sync issues, wave events, tower events, and upgrade events. |
| Autoloads / singletons | Global state bugs, reset behavior, scene transitions, stale data after death/restart/load, and autoload interaction boundaries. |
| Save/load systems | Corrupt saves, versioning, missing fields, local/cloud conflicts if supported, save during transitions, restore correctness, and save-scumming exploits. |
| Menus and UI | Pause menu, settings, shop, upgrade panel, tooltips, scaling, focus order, controller navigation if supported, screen-size adaptation, and bottom-dock behavior. |
| Game balance | Difficulty spikes, dominant strategies, dead picks, broken upgrades, economy inflation, enemy scaling, reward pacing, leak pressure, and wave fairness. |
| AI / enemy behavior | Path following, idle states, target selection, unreachable path cases, swarm behavior, stuck enemies, flying enemies, special enemy behavior, and unfair reactions. |
| Level/content validation | Missing assets, invalid map/path data, unreachable or invalid build sites, invalid spawn points, softlocks, bad checkpoints if supported, and malformed canonical data. |
| Performance | FPS drops, shader compilation stutter, excessive nodes, physics cost, particles, draw calls, pathfinding spikes, wave-size stress, and speed-control stress. |
| Memory and resource usage | Texture/audio bloat, leaks, unreleased scenes, preload/load misuse, scene transition memory growth, and generated/imported asset churn. |
| Rendering and visuals | Rendering correctness, missing sprites, broken textures, shader errors, lighting issues if used, invisible objects, animation states and transitions, camera bounds/clipping/shake/zoom, z-index and draw order, UI behind game objects, background/foreground overlap, particles and VFX spawn/lifetime/performance, UI text overflow, font readability, scaling, anchors, controller focus highlights if supported, 16:9/ultrawide/windowed/fullscreen/high-DPI/mobile scaling when relevant, enemy readability, projectile clarity, color contrast, important objects blending into background, and export visual parity only when an export lane is audited. |
| Audio | Missing sounds for footsteps if applicable, hits, UI clicks, enemy attacks, music triggers, wrong cues for actions/events, early/late/repeating/cut-off sounds, music/SFX/dialogue balance where applicable, Music/SFX/UI bus routing, volume sliders if supported, clean music loops, ambience stacking, pause behavior, scene-transition music changes, old sounds persisting incorrectly, 2D/3D positional distance/panning/falloff only if used, too many simultaneous sounds, and memory-heavy audio assets. |
| Build/export stability | Export presets, missing files, platform-specific crashes, permissions, icon/version metadata, and release/debug differences. Mark out of scope when no export lane is audited. |
| Platform compatibility | Windows, macOS, Linux, Web, mobile, controller support, fullscreen/windowed, high-DPI, and Steam Deck behavior only when those targets are supported or requested. |
| Networking, if multiplayer | Desync, lag compensation, authority bugs, reconnects, packet loss, duplicate actions, and host migration. Mark not supported for single-player-only builds. |
| Security / cheating | Save tampering, speed hacks, debug commands, client-authoritative multiplayer exploits if multiplayer exists, and whether cheats affect local-only progression. |
| Accessibility | Remapping, subtitles if audio cues carry meaning, colorblind readability, font size, screen shake toggle, hold-vs-toggle options, and readable feedback states. |
| Localization | Text overflow, missing translations if localization exists, font glyphs, right-to-left text if supported, and hardcoded strings that block future localization. |
| Crash/error logging | Godot errors, warnings, stack traces, failed resource loads, unhandled nulls, bad casts, and log paths under `logs/godot/`. |
| Telemetry / analytics | Funnel events, deaths, completion rates, bug reproduction logs, seed/run metadata, scenario-probe metadata, and whether telemetry is actionable without over-claiming. |

## Validation Commands

Use the narrowest relevant validation first. If the scripts exist and fresh validation is needed, run:

```powershell
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_prompt_metadata_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_prompt_metadata_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_scenario_probe_validation.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_ai_scenario_probe_validation.gd
C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_performance_budget.log --path C:\Users\donny\Desktop\tower_defense_godot --script res://scripts/tools/run_performance_budget_validation.gd
```

Run `scripts/tools/run_playable_surface_validation.gd` only with a rendering-capable Godot session when screenshot evidence needs refreshing. Do not write Godot logs into the project root.

Run `git diff --check` before finishing any doc or code changes.

## Report Schema

Write the latest report to `TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md`.

The report must include:

- Evidence packet audited, including exact report, JSON, and generated prompt paths.
- Current repo state summary.
- Run stats: profile, evidence tier, runs, max waves, seed settings, strategy group, scenario-probe mode, full-action-log mode when available, preflight status, and regression comparability.
- Minimum coverage evidence bundle status, with each command or artifact marked fresh, existing, missing, skipped, or failed.
- Scorecard: 0-100 coverage ratings for relevant coverage areas with evidence classification and the coverage lane that supports each row.
- Visual review output from rendered screenshots or an explicit missing-evidence statement.
- Performance metrics from performance logs or an explicit missing-evidence statement.
- Findings with severity and false-positive class.
- Recommended improvements.
- Validation commands and results, distinguishing fresh runs from existing logs.
- Deferred or rejected implementation actions.
- Residual gaps, including every missing or skipped bundle item, and exactly one next recommended action.

## Implementation Guardrails

Do not change gameplay, balance, data, UI, validation code, assets, scenes, or audio from aggregate telemetry alone. First verify the finding against current code and current generated evidence, confirm the false-positive class, and identify the narrow validation that will prove the fix.

Keep `TOWER_DEFENSE_AI_SIMULATION_AUDIT.md` durable and run-agnostic. Keep `TOWER_DEFENSE_AI_SIMULATION_AUDIT_REPORT.md` as the mutable latest report.
