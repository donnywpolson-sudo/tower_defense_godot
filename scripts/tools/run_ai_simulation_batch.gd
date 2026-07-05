extends SceneTree

const SCHEMA_VERSION := 6
const DEFAULT_OUTPUT_DIR := "res://.godot/ai_simulation"
const DEFAULT_SEED := 12345
const DEFAULT_SEED_COUNT := 1
const DEFAULT_SEED_STEP := 1000003
const MEDIUM_RUNS := 420
const DEEP_RUNS := 2500
const OVERNIGHT_RUNS := 6000
const MEDIUM_MAX_WAVES := 6
const DEEP_MAX_WAVES := 20
const OVERNIGHT_MAX_WAVES := 50
const STEP_DELTA := 0.2
const SAMPLED_ACTION_LOG_LIMIT := 80
const SAMPLED_FLAGGED_RUN_LIMIT := 6
const COVERAGE_SCOPE := "direct_vertical_slice_api"
const SCHEMA_BASELINE_TEXT := "Schema 6 starts a new comparison baseline; deltas resume after the next matching schema 6 run."
const SCENARIO_PROBE_MODES := ["auto", "off", "smoke", "full"]
const SCENARIO_SMOKE_TOWERS := ["archer", "cannon", "tesla"]
const SCENARIO_SMOKE_ENEMY_KINDS := ["normal", "fast", "tank", "flying"]
const SCENARIO_FULL_SPECIAL_WAVES := [5, 8, 10, 12, 15, 16, 20, 24, 25, 28, 30]
const SCENARIO_SMOKE_SPECIAL_WAVES := [5, 8]
const SCENARIO_MIXED_DEFENSE := ["archer", "cannon", "sniper", "tesla"]
const SCENARIO_MAX_CYCLES_CAP := 900
const SCENARIO_SETUP_MONEY := 5000
const SCENARIO_SETUP_LIVES := 25
const PROFILE_DEFAULTS := {
	"medium": {"runs": MEDIUM_RUNS, "max_waves": MEDIUM_MAX_WAVES, "seed_count": 5, "seed_step": DEFAULT_SEED_STEP, "strategy_group": "standard_research", "full_action_log": false, "compare_previous": true},
	"deep": {"runs": DEEP_RUNS, "max_waves": DEEP_MAX_WAVES, "seed_count": 8, "seed_step": DEFAULT_SEED_STEP, "strategy_group": "deep_research", "full_action_log": false, "compare_previous": true},
	"overnight": {"runs": OVERNIGHT_RUNS, "max_waves": OVERNIGHT_MAX_WAVES, "seed_count": 12, "seed_step": DEFAULT_SEED_STEP, "strategy_group": "full_research", "full_action_log": false, "compare_previous": true},
}

const ENABLED_TOWER_TYPES := ["archer", "machine_gun", "cannon", "sniper", "tesla"]
const UNSUPPORTED_TOWER_TYPES := ["frost", "poison", "support", "barracks"]
const DEFAULT_STRATEGIES := ["balanced_builder", "tower_specialist", "upgrade_rusher", "wide_builder", "target_mode_tester", "edge_case_explorer", "speed_stress"]
const STRATEGY_GROUPS := {
	"default": DEFAULT_STRATEGIES,
	"standard_research": DEFAULT_STRATEGIES + ["economy_saver", "leak_recovery", "value_upgrader"],
	"deep_research": DEFAULT_STRATEGIES + ["economy_saver", "leak_recovery", "value_upgrader", "tower_rotation", "late_wave_scaler", "anti_leak_targeting"],
	"full_research": DEFAULT_STRATEGIES + ["economy_saver", "leak_recovery", "value_upgrader", "tower_rotation", "late_wave_scaler", "anti_leak_targeting", "stress_overbuilder", "stress_upgrade_spammer"],
}
const TARGET_MODES := ["first", "last", "strongest", "weakest", "closest", "flying"]
const BOT_POLICIES := {
	"balanced_builder": {
		"display_name": "Balanced Builder",
		"synthetic_stress": false,
		"initial_builds": 2,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.40, "build": 0.40, "target": 0.20},
		"mid_wave_weights": {"upgrade": 0.45, "build": 0.35, "target": 0.20},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.0, "cannon": 1.0, "sniper": 1.0, "tesla": 1.0},
		"site_bias": "balanced",
	},
	"tower_specialist": {
		"display_name": "Tower Specialist",
		"synthetic_stress": false,
		"initial_builds": 3,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.45, "build": 0.45, "target": 0.10},
		"mid_wave_weights": {"upgrade": 0.55, "build": 0.35, "target": 0.10},
		"tower_weights": {},
		"site_bias": "balanced",
	},
	"upgrade_rusher": {
		"display_name": "Upgrade Rusher",
		"synthetic_stress": false,
		"initial_builds": 1,
		"money_floor": 40,
		"action_weights": {"upgrade": 0.70, "build": 0.20, "target": 0.10},
		"mid_wave_weights": {"upgrade": 0.75, "build": 0.15, "target": 0.10},
		"tower_weights": {"archer": 1.0, "machine_gun": 0.9, "cannon": 1.1, "sniper": 1.1, "tesla": 0.9},
		"site_bias": "choke",
	},
	"wide_builder": {
		"display_name": "Wide Builder",
		"synthetic_stress": false,
		"initial_builds": 3,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.20, "build": 0.65, "target": 0.15},
		"mid_wave_weights": {"upgrade": 0.25, "build": 0.55, "target": 0.20},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.2, "cannon": 0.9, "sniper": 0.8, "tesla": 1.1},
		"site_bias": "spread",
	},
	"target_mode_tester": {
		"display_name": "Target Mode Tester",
		"synthetic_stress": false,
		"initial_builds": 2,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.25, "build": 0.25, "target": 0.50},
		"mid_wave_weights": {"upgrade": 0.25, "build": 0.20, "target": 0.55},
		"tower_weights": {"archer": 0.9, "machine_gun": 1.1, "cannon": 0.9, "sniper": 1.2, "tesla": 0.9},
		"site_bias": "mixed",
	},
	"edge_case_explorer": {
		"display_name": "Edge Case Explorer",
		"synthetic_stress": true,
		"initial_builds": 1,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.35, "build": 0.35, "target": 0.30},
		"mid_wave_weights": {"upgrade": 0.35, "build": 0.30, "target": 0.35},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.0, "cannon": 1.0, "sniper": 1.0, "tesla": 1.0},
		"site_bias": "edge",
	},
	"speed_stress": {
		"display_name": "Speed Stress",
		"synthetic_stress": true,
		"initial_builds": 4,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.30, "build": 0.55, "target": 0.15},
		"mid_wave_weights": {"upgrade": 0.35, "build": 0.45, "target": 0.20},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.0, "cannon": 1.0, "sniper": 1.0, "tesla": 1.0},
		"site_bias": "spread",
	},
	"economy_saver": {
		"display_name": "Economy Saver",
		"synthetic_stress": false,
		"initial_builds": 1,
		"money_floor": 90,
		"action_weights": {"upgrade": 0.45, "build": 0.25, "target": 0.30},
		"mid_wave_weights": {"upgrade": 0.50, "build": 0.20, "target": 0.30},
		"tower_weights": {"archer": 1.2, "machine_gun": 1.0, "cannon": 0.9, "sniper": 1.1, "tesla": 0.8},
		"site_bias": "choke",
		"upgrade_bias": "value",
		"target_bias": "strongest",
	},
	"leak_recovery": {
		"display_name": "Leak Recovery",
		"synthetic_stress": false,
		"initial_builds": 2,
		"money_floor": 20,
		"action_weights": {"upgrade": 0.30, "build": 0.55, "target": 0.15},
		"mid_wave_weights": {"upgrade": 0.25, "build": 0.50, "target": 0.25},
		"tower_weights": {"archer": 0.9, "machine_gun": 1.2, "cannon": 0.9, "sniper": 0.8, "tesla": 1.2},
		"site_bias": "spread",
		"upgrade_bias": "coverage",
		"target_bias": "last",
	},
	"value_upgrader": {
		"display_name": "Value Upgrader",
		"synthetic_stress": false,
		"initial_builds": 2,
		"money_floor": 35,
		"action_weights": {"upgrade": 0.65, "build": 0.25, "target": 0.10},
		"mid_wave_weights": {"upgrade": 0.70, "build": 0.20, "target": 0.10},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.0, "cannon": 1.1, "sniper": 1.1, "tesla": 0.9},
		"site_bias": "balanced",
		"upgrade_bias": "damage",
		"target_bias": "strongest",
	},
	"tower_rotation": {
		"display_name": "Tower Rotation",
		"synthetic_stress": false,
		"initial_builds": 3,
		"money_floor": 10,
		"action_weights": {"upgrade": 0.35, "build": 0.50, "target": 0.15},
		"mid_wave_weights": {"upgrade": 0.35, "build": 0.45, "target": 0.20},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.0, "cannon": 1.0, "sniper": 1.0, "tesla": 1.0},
		"site_bias": "mixed",
		"build_bias": "rotation",
		"upgrade_bias": "underused",
		"target_bias": "closest",
	},
	"late_wave_scaler": {
		"display_name": "Late Wave Scaler",
		"synthetic_stress": false,
		"initial_builds": 2,
		"money_floor": 60,
		"action_weights": {"upgrade": 0.55, "build": 0.35, "target": 0.10},
		"mid_wave_weights": {"upgrade": 0.65, "build": 0.25, "target": 0.10},
		"tower_weights": {"archer": 0.8, "machine_gun": 0.9, "cannon": 1.2, "sniper": 1.2, "tesla": 1.0},
		"site_bias": "choke",
		"upgrade_bias": "late",
		"target_bias": "strongest",
	},
	"anti_leak_targeting": {
		"display_name": "Anti-Leak Targeting",
		"synthetic_stress": false,
		"initial_builds": 2,
		"money_floor": 25,
		"action_weights": {"upgrade": 0.25, "build": 0.35, "target": 0.40},
		"mid_wave_weights": {"upgrade": 0.25, "build": 0.30, "target": 0.45},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.1, "cannon": 0.9, "sniper": 0.9, "tesla": 1.2},
		"site_bias": "spread",
		"upgrade_bias": "coverage",
		"target_bias": "last",
	},
	"stress_overbuilder": {
		"display_name": "Stress Overbuilder",
		"synthetic_stress": true,
		"initial_builds": 5,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.15, "build": 0.75, "target": 0.10},
		"mid_wave_weights": {"upgrade": 0.20, "build": 0.65, "target": 0.15},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.0, "cannon": 1.0, "sniper": 1.0, "tesla": 1.0},
		"site_bias": "spread",
		"build_bias": "rotation",
		"target_bias": "closest",
	},
	"stress_upgrade_spammer": {
		"display_name": "Stress Upgrade Spammer",
		"synthetic_stress": true,
		"initial_builds": 2,
		"money_floor": 0,
		"action_weights": {"upgrade": 0.85, "build": 0.10, "target": 0.05},
		"mid_wave_weights": {"upgrade": 0.85, "build": 0.10, "target": 0.05},
		"tower_weights": {"archer": 1.0, "machine_gun": 1.0, "cannon": 1.0, "sniper": 1.0, "tesla": 1.0},
		"site_bias": "choke",
		"upgrade_bias": "damage",
		"target_bias": "strongest",
	},
}
const KNOWN_LIMITATIONS := [
	"Godot is still a vertical slice, not the complete runtime.",
	"Unsupported shop towers are visible in canonical data but intentionally disabled in the current slice.",
	"Boss, commander, reward-card, mutation, mastery, and paragon systems are not fully ported.",
	"Balance findings use normal bot runs only; synthetic edge/stress runs are excluded.",
]

var _game_data: Dictionary = {}
var _preflight: Dictionary = {}


func _initialize() -> void:
	var batch_result: Dictionary = _run_batch()
	if not bool(batch_result.get("ok", false)):
		push_error("AI_SIMULATION_BATCH_FAILED")
		for error in batch_result.get("errors", []):
			push_error(str(error))
		quit(1)
		return

	print("AI_SIMULATION_BATCH_OK")
	print("  Report JSON %s" % str(batch_result.get("json_path", "")))
	print("  Report Markdown %s" % str(batch_result.get("markdown_path", "")))
	print("  Codex prompt %s" % str(batch_result.get("prompt_path", "")))
	print("  Archived previous files %s" % int(batch_result.get("archived_previous_count", 0)))
	print("  Archived legacy root files %s" % int(batch_result.get("archived_legacy_count", 0)))
	print("  Runs %s" % int(batch_result.get("run_count", 0)))
	quit(0)


func _run_batch() -> Dictionary:
	var options := _parse_options()
	if not str(options.get("error", "")).is_empty():
		return {"ok": false, "errors": [options["error"]]}
	if not str(options.get("metadata_fixture", "")).is_empty():
		return _run_metadata_fixture(options)

	var game := _create_game()
	game.reset_slice()

	var runs: Array = []
	var issues: Array = _preflight_issues(_preflight)
	var run_count: int = int(options["runs"])
	var base_seed: int = int(options["seed"])
	var seed_count: int = max(1, int(options["seed_count"]))
	var seed_step: int = max(1, int(options["seed_step"]))
	var strategies: Array = options["strategies"]
	var started_usec: int = Time.get_ticks_usec()
	var progress_interval: int = _progress_interval(run_count)
	_print_progress(0, run_count, started_usec)
	for index in range(run_count):
		var strategy_index: int = index % strategies.size()
		var seed_bucket: int = index % seed_count
		var seed_value: int = base_seed + seed_bucket * seed_step
		var strategy: String = str(strategies[strategy_index])
		var run_seed: int = seed_value + index * 104729 + strategy_index * 7919
		var run_result: Dictionary = _run_single_simulation(game, options, index + 1, run_seed, strategy, seed_bucket, seed_value)
		runs.append(run_result)
		for issue in run_result.get("issues", []):
			issues.append(issue)
		var completed: int = index + 1
		if completed == run_count or completed % progress_interval == 0:
			_print_progress(completed, run_count, started_usec)

	for issue in _build_balance_issues(runs):
		issues.append(issue)

	var scenario_probes := _run_scenario_probes(options)
	for issue in scenario_probes.get("issues", []):
		issues.append(issue)
	_assign_issue_ids(issues)
	_sync_scenario_issue_ids(scenario_probes, issues)

	var summary := _build_summary(runs, issues)
	var strategy_metrics := _build_strategy_metrics(runs)
	var wave_metrics := _build_wave_metrics(runs)
	var tower_metrics := _build_tower_metrics(runs)
	var blocked_action_metrics := _build_blocked_action_metrics(runs)
	var seed_metrics := _build_seed_metrics(runs)
	var economy_metrics := _build_economy_metrics(runs)
	var damage_metrics := _build_damage_metrics(runs)
	var enemy_kind_metrics := _build_enemy_kind_metrics(runs)
	var boss_commander_metrics := _build_boss_commander_metrics(runs)
	var upgrade_branch_metrics := _build_upgrade_branch_metrics(runs)
	var target_mode_metrics := _build_target_mode_metrics(runs)
	var progression_metrics := _build_progression_metrics(runs)
	var late_wave_metrics := _build_late_wave_metrics(runs)
	var report := {
		"schema_version": SCHEMA_VERSION,
		"config": _public_config(options),
		"preflight": _preflight,
		"known_limitations": KNOWN_LIMITATIONS.duplicate(),
		"telemetry_coverage": _build_telemetry_coverage(),
		"summary": summary,
		"runs": runs,
		"issues": issues,
		"strategy_metrics": strategy_metrics,
		"wave_metrics": wave_metrics,
		"tower_metrics": tower_metrics,
		"blocked_action_metrics": blocked_action_metrics,
		"seed_metrics": seed_metrics,
		"economy_metrics": economy_metrics,
		"damage_metrics": damage_metrics,
		"enemy_kind_metrics": enemy_kind_metrics,
		"boss_commander_metrics": boss_commander_metrics,
		"upgrade_branch_metrics": upgrade_branch_metrics,
		"target_mode_metrics": target_mode_metrics,
		"progression_metrics": progression_metrics,
		"late_wave_metrics": late_wave_metrics,
		"scenario_probes": scenario_probes,
		"regression": {},
		"recommendations": _build_recommendations(summary, issues),
	}
	_apply_late_report_metadata(report)
	_apply_evidence_warnings(report, str(options["output_dir"]))
	var previous_report: Dictionary = _load_previous_latest_report(str(options["output_dir"])) if bool(options["compare_previous"]) else {}
	report["regression"] = _build_regression(report, previous_report)

	var write_result := _write_reports(report, str(options["output_dir"]))
	if not bool(write_result.get("ok", false)):
		return {"ok": false, "errors": write_result.get("errors", [])}

	return {
		"ok": true,
		"json_path": write_result["json_path"],
		"markdown_path": write_result["markdown_path"],
		"prompt_path": write_result["prompt_path"],
		"visible_prompt_path": write_result["visible_prompt_path"],
		"archived_previous_count": write_result["archived_previous_count"],
		"archived_legacy_count": write_result["archived_legacy_count"],
		"run_count": run_count,
	}


func _create_game() -> Node:
	var config_script := load("res://scripts/autoload/game_config.gd")
	var data_script := load("res://scripts/autoload/game_data.gd")
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var config: Node = config_script.new()
	var data_loader: Node = data_script.new()
	var game: Node = slice_script.new()
	root.add_child(config)
	root.add_child(data_loader)
	root.add_child(game)
	config.name = "GameConfig"
	data_loader.name = "GameData"
	game.name = "VerticalSliceGame"
	_game_data = data_loader.load_game_data()
	_preflight = _build_preflight(data_loader)
	return game


func _build_preflight(data_loader: Node) -> Dictionary:
	var data_validation: Dictionary = data_loader.validate_game_data() if data_loader.has_method("validate_game_data") else {"ok": false, "errors": ["GameData.validate_game_data unavailable"], "warnings": [], "checks": []}
	var balance_sanity: Dictionary = data_loader.validate_balance_sanity() if data_loader.has_method("validate_balance_sanity") else {"ok": false, "errors": ["GameData.validate_balance_sanity unavailable"], "warnings": [], "checks": []}
	return {
		"data_validation": _validation_summary(data_validation),
		"balance_sanity": _validation_summary(balance_sanity),
	}


func _validation_summary(result: Dictionary) -> Dictionary:
	return {
		"ok": bool(result.get("ok", false)),
		"check_count": int(result.get("checks", []).size()),
		"error_count": int(result.get("errors", []).size()),
		"warning_count": int(result.get("warnings", []).size()),
		"errors": _string_values(result.get("errors", []), 20),
		"warnings": _string_values(result.get("warnings", []), 20),
	}


func _preflight_issues(preflight: Dictionary) -> Array:
	var issues: Array = []
	for key in ["data_validation", "balance_sanity"]:
		var summary: Dictionary = preflight.get(key, {})
		if bool(summary.get("ok", false)):
			continue
		issues.append(_batch_issue("validation", "high", "%s_failed" % key, "Canonical GameData preflight failed before AI simulation.", {
			"preflight": key,
			"error_count": int(summary.get("error_count", 0)),
			"errors": summary.get("errors", []),
		}))
	return issues


func _run_metadata_fixture(options: Dictionary) -> Dictionary:
	var fixture := str(options.get("metadata_fixture", "")).to_lower()
	var issues: Array = []
	if fixture == "known_gap":
		issues.append(_batch_issue("known_gap", "info", "unsupported_shop_tower", "Tower is present in canonical game data but disabled in the current Godot slice.", {"tower_type": "frost"}))
	elif fixture == "balance_empty":
		pass
	elif fixture not in ["smoke", "medium", "schema4_previous", "label_only_previous"]:
		return {"ok": false, "errors": ["Unsupported metadata fixture %s." % fixture]}

	_assign_issue_ids(issues)
	var summary := {
		"total_runs": int(options["runs"]),
		"completed_runs": int(options["runs"]),
		"game_over_runs": 0,
		"failed_runs": 0,
		"normal_runs": int(options["runs"]),
		"synthetic_runs": 0,
		"issue_counts": {},
		"severity_counts": {},
	}
	var blocked_action_metrics := {
		"total": 0,
		"expected_total": 0,
		"avoidable_total": 0,
		"by_action": {},
		"by_reason": {},
		"expected_by_action": {},
		"avoidable_by_action": {},
	}
	var report := {
		"schema_version": 4 if fixture == "schema4_previous" else SCHEMA_VERSION,
		"config": _public_config(options),
		"preflight": {},
		"known_limitations": KNOWN_LIMITATIONS.duplicate(),
		"telemetry_coverage": _build_telemetry_coverage(),
		"summary": summary,
		"runs": [],
		"issues": issues,
		"strategy_metrics": {},
		"wave_metrics": {},
		"tower_metrics": {},
		"blocked_action_metrics": blocked_action_metrics,
		"seed_metrics": {},
		"economy_metrics": {},
		"damage_metrics": {},
		"enemy_kind_metrics": {},
		"boss_commander_metrics": {},
		"upgrade_branch_metrics": {},
		"target_mode_metrics": {},
		"progression_metrics": {},
		"late_wave_metrics": {},
		"scenario_probes": _empty_scenario_probe_report("off", "metadata_fixture"),
		"regression": {},
		"recommendations": _build_recommendations(summary, issues),
	}
	_apply_late_report_metadata(report)
	_apply_evidence_warnings(report, str(options["output_dir"]))
	var previous_report: Dictionary = _load_previous_latest_report(str(options["output_dir"])) if bool(options["compare_previous"]) else {}
	report["regression"] = _build_regression(report, previous_report)
	var write_result := _write_reports(report, str(options["output_dir"]))
	if not bool(write_result.get("ok", false)):
		return {"ok": false, "errors": write_result.get("errors", [])}
	return {
		"ok": true,
		"json_path": write_result["json_path"],
		"markdown_path": write_result["markdown_path"],
		"prompt_path": write_result["prompt_path"],
		"visible_prompt_path": write_result["visible_prompt_path"],
		"archived_previous_count": write_result["archived_previous_count"],
		"archived_legacy_count": write_result["archived_legacy_count"],
		"run_count": int(options["runs"]),
	}


func _string_values(values: Array, limit: int) -> Array:
	var result: Array = []
	for index in range(min(limit, values.size())):
		result.append(str(values[index]))
	return result


func _progress_interval(run_count: int) -> int:
	if run_count <= 50:
		return 1
	return int(max(1.0, floor(float(run_count) / 50.0)))


func _print_progress(completed: int, total: int, started_usec: int) -> void:
	var safe_total: int = max(1, total)
	var ratio: float = clamp(float(completed) / float(safe_total), 0.0, 1.0)
	var width := 30
	var filled: int = int(round(ratio * float(width)))
	var bar := ""
	for index in range(width):
		bar += "#" if index < filled else "-"
	var elapsed_sec: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var eta_text := "--"
	if completed > 0 and completed < safe_total:
		var avg_sec: float = elapsed_sec / float(completed)
		eta_text = _format_duration(int(round(avg_sec * float(safe_total - completed))))
	elif completed >= safe_total:
		eta_text = "0s"
	print("  [%s] %d%% | %d/%d runs | elapsed %s | ETA %s" % [
		bar,
		int(round(ratio * 100.0)),
		completed,
		safe_total,
		_format_duration(int(round(elapsed_sec))),
		eta_text,
	])


func _format_duration(total_seconds: int) -> String:
	var safe_seconds: int = max(0, total_seconds)
	var hours: int = int(floor(float(safe_seconds) / 3600.0))
	var minutes: int = int(floor(float(safe_seconds % 3600) / 60.0))
	var seconds: int = safe_seconds % 60
	if hours > 0:
		return "%dh%02dm" % [hours, minutes]
	if minutes > 0:
		return "%dm%02ds" % [minutes, seconds]
	return "%ds" % seconds


func _parse_options() -> Dictionary:
	var options := {
		"profile": "medium",
		"runs": -1,
		"max_waves": -1,
		"seed": DEFAULT_SEED,
		"seed_count": -1,
		"seed_step": DEFAULT_SEED_STEP,
		"strategy_group": "",
		"output_dir": DEFAULT_OUTPUT_DIR,
		"full_action_log": null,
		"compare_previous": null,
		"strategies": [],
		"report_label": "",
		"metadata_fixture": "",
		"scenario_probes": "auto",
		"profile_explicit": false,
		"raw_user_args": [],
		"error": "",
	}
	var pending_key := ""
	for arg in OS.get_cmdline_user_args():
		options["raw_user_args"].append(str(arg))
		var normalized_arg := _normalized_arg(str(arg))
		if not pending_key.is_empty():
			_apply_option_value(options, pending_key, str(arg))
			pending_key = ""
			continue
		if normalized_arg == "medium":
			options["profile"] = "medium"
			options["profile_explicit"] = true
		elif normalized_arg == "deep":
			options["profile"] = "deep"
			options["profile_explicit"] = true
		elif normalized_arg == "overnight":
			options["profile"] = "overnight"
			options["profile_explicit"] = true
		elif normalized_arg in ["profile", "ai-profile", "ai_profile", "mode", "batch-profile", "batch_profile", "runs", "max-waves", "max_waves", "seed", "seed-count", "seed_count", "seed-step", "seed_step", "strategy-group", "strategy_group", "output-dir", "output_dir", "full-action-log", "full_action_log", "compare-previous", "compare_previous", "strategies", "report-label", "report_label", "metadata-fixture", "metadata_fixture", "scenario-probes", "scenario_probes"]:
			pending_key = normalized_arg
		elif normalized_arg.begins_with("profile=") or normalized_arg.begins_with("ai-profile=") or normalized_arg.begins_with("ai_profile=") or normalized_arg.begins_with("mode=") or normalized_arg.begins_with("batch-profile=") or normalized_arg.begins_with("batch_profile="):
			options["profile"] = _arg_value(normalized_arg)
			options["profile_explicit"] = true
		elif normalized_arg.begins_with("runs="):
			options["runs"] = int(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("max-waves=") or normalized_arg.begins_with("max_waves="):
			options["max_waves"] = int(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("seed="):
			options["seed"] = int(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("seed-count=") or normalized_arg.begins_with("seed_count="):
			options["seed_count"] = int(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("seed-step=") or normalized_arg.begins_with("seed_step="):
			options["seed_step"] = int(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("strategy-group=") or normalized_arg.begins_with("strategy_group="):
			options["strategy_group"] = _arg_value(normalized_arg)
		elif normalized_arg.begins_with("output-dir=") or normalized_arg.begins_with("output_dir="):
			options["output_dir"] = _arg_value(normalized_arg)
		elif normalized_arg.begins_with("full-action-log=") or normalized_arg.begins_with("full_action_log="):
			options["full_action_log"] = _parse_bool(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("compare-previous=") or normalized_arg.begins_with("compare_previous="):
			options["compare_previous"] = _parse_bool(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("strategies="):
			options["strategies"] = _parse_csv(_arg_value(normalized_arg))
		elif normalized_arg.begins_with("report-label=") or normalized_arg.begins_with("report_label="):
			options["report_label"] = _arg_value(str(arg))
		elif normalized_arg.begins_with("metadata-fixture=") or normalized_arg.begins_with("metadata_fixture="):
			options["metadata_fixture"] = _arg_value(normalized_arg)
		elif normalized_arg.begins_with("scenario-probes=") or normalized_arg.begins_with("scenario_probes="):
			options["scenario_probes"] = _arg_value(normalized_arg)
	if not pending_key.is_empty():
		options["error"] = "Missing value for --%s." % pending_key
		return options

	var profile := str(options["profile"])
	if not PROFILE_DEFAULTS.has(profile):
		options["error"] = "Unsupported --profile=%s; expected medium, deep, or overnight." % profile
		return options
	if not bool(options["profile_explicit"]):
		if int(options["runs"]) > DEEP_RUNS or int(options["max_waves"]) > DEEP_MAX_WAVES:
			options["profile"] = "overnight"
			profile = "overnight"
		elif int(options["runs"]) > MEDIUM_RUNS or int(options["max_waves"]) > MEDIUM_MAX_WAVES:
			options["profile"] = "deep"
			profile = "deep"
	var profile_defaults: Dictionary = PROFILE_DEFAULTS[profile]
	if int(options["runs"]) <= 0:
		options["runs"] = int(profile_defaults["runs"])
	if int(options["max_waves"]) <= 0:
		options["max_waves"] = int(profile_defaults["max_waves"])
	if int(options["seed_count"]) <= 0:
		options["seed_count"] = int(profile_defaults.get("seed_count", DEFAULT_SEED_COUNT))
	if int(options["seed_step"]) <= 0:
		options["seed_step"] = int(profile_defaults.get("seed_step", DEFAULT_SEED_STEP))
	if str(options["strategy_group"]).is_empty():
		options["strategy_group"] = str(profile_defaults.get("strategy_group", "default"))
	if str(options["output_dir"]).is_empty():
		options["output_dir"] = DEFAULT_OUTPUT_DIR
	if options["full_action_log"] == null:
		options["full_action_log"] = bool(profile_defaults["full_action_log"])
	if options["compare_previous"] == null:
		options["compare_previous"] = bool(profile_defaults.get("compare_previous", true))
	if options["strategies"].is_empty():
		options["strategies"] = _strategies_for_group(str(options["strategy_group"]))
		if options["strategies"].is_empty():
			options["error"] = "Unsupported --strategy-group=%s; expected one of %s." % [str(options["strategy_group"]), _join_strings(STRATEGY_GROUPS.keys(), ", ")]
			return options
	for strategy in options["strategies"]:
		if not BOT_POLICIES.has(str(strategy)):
			options["error"] = "Unsupported --strategies entry '%s'; expected one of %s." % [str(strategy), _join_strings(BOT_POLICIES.keys(), ", ")]
			return options
	if not SCENARIO_PROBE_MODES.has(str(options["scenario_probes"])):
		options["error"] = "Unsupported --scenario-probes=%s; expected one of %s." % [str(options["scenario_probes"]), _join_strings(SCENARIO_PROBE_MODES, ", ")]
		return options
	return options


func _normalized_arg(arg: String) -> String:
	var normalized := arg.strip_edges()
	while normalized.begins_with("-"):
		normalized = normalized.substr(1)
	return normalized


func _arg_value(arg: String) -> String:
	var parts := arg.split("=", false, 1)
	return parts[1] if parts.size() > 1 else ""


func _parse_bool(value: String) -> bool:
	var normalized := value.strip_edges().to_lower()
	return normalized in ["1", "true", "yes", "on"]


func _apply_option_value(options: Dictionary, key: String, value: String) -> void:
	var normalized_value := value.strip_edges()
	if key in ["profile", "ai-profile", "ai_profile", "mode", "batch-profile", "batch_profile"]:
		options["profile"] = normalized_value
		options["profile_explicit"] = true
	elif key == "runs":
		options["runs"] = int(normalized_value)
	elif key in ["max-waves", "max_waves"]:
		options["max_waves"] = int(normalized_value)
	elif key == "seed":
		options["seed"] = int(normalized_value)
	elif key in ["seed-count", "seed_count"]:
		options["seed_count"] = int(normalized_value)
	elif key in ["seed-step", "seed_step"]:
		options["seed_step"] = int(normalized_value)
	elif key in ["strategy-group", "strategy_group"]:
		options["strategy_group"] = normalized_value
	elif key in ["output-dir", "output_dir"]:
		options["output_dir"] = normalized_value
	elif key in ["full-action-log", "full_action_log"]:
		options["full_action_log"] = _parse_bool(normalized_value)
	elif key in ["compare-previous", "compare_previous"]:
		options["compare_previous"] = _parse_bool(normalized_value)
	elif key == "strategies":
		options["strategies"] = _parse_csv(normalized_value)
	elif key in ["report-label", "report_label"]:
		options["report_label"] = normalized_value
	elif key in ["metadata-fixture", "metadata_fixture"]:
		options["metadata_fixture"] = normalized_value
	elif key in ["scenario-probes", "scenario_probes"]:
		options["scenario_probes"] = normalized_value


func _parse_csv(value: String) -> Array:
	var parsed: Array = []
	for item in value.split(",", false):
		var trimmed := item.strip_edges()
		if not trimmed.is_empty():
			parsed.append(trimmed)
	return parsed


func _strategies_for_group(group: String) -> Array:
	if not STRATEGY_GROUPS.has(group):
		return []
	return STRATEGY_GROUPS[group].duplicate()


func _evidence_tier(runs: int, max_waves: int) -> String:
	if runs >= OVERNIGHT_RUNS and max_waves >= OVERNIGHT_MAX_WAVES:
		return "overnight"
	if runs >= DEEP_RUNS and max_waves >= DEEP_MAX_WAVES:
		return "deep"
	if runs >= MEDIUM_RUNS and max_waves >= MEDIUM_MAX_WAVES:
		return "medium"
	return "smoke"


func _resolve_scenario_probe_mode(options: Dictionary) -> String:
	var requested := str(options.get("scenario_probes", "auto"))
	if requested == "off":
		return "off"
	if requested in ["smoke", "full"]:
		return requested
	var tier := _evidence_tier(int(options.get("runs", 0)), int(options.get("max_waves", 0)))
	return "full" if tier in ["medium", "deep", "overnight"] else "smoke"


func _default_strategies_for_profile(profile: String) -> Array:
	var defaults: Dictionary = PROFILE_DEFAULTS.get(profile, {})
	return _strategies_for_group(str(defaults.get("strategy_group", "default")))


func _arrays_equal(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if str(left[index]) != str(right[index]):
			return false
	return true


func _profile_overridden(options: Dictionary) -> bool:
	var profile := str(options.get("profile", ""))
	var defaults: Dictionary = PROFILE_DEFAULTS.get(profile, {})
	if defaults.is_empty():
		return true
	for key in ["runs", "max_waves", "seed_count"]:
		if int(options.get(key, 0)) != int(defaults.get(key, 0)):
			return true
	if str(options.get("strategy_group", "")) != str(defaults.get("strategy_group", "")):
		return true
	return not _arrays_equal(options.get("strategies", []), _default_strategies_for_profile(profile))


func _public_config(options: Dictionary) -> Dictionary:
	return {
		"profile": str(options["profile"]),
		"runs": int(options["runs"]),
		"max_waves": int(options["max_waves"]),
		"seed": int(options["seed"]),
		"seed_count": int(options["seed_count"]),
		"seed_step": int(options["seed_step"]),
		"strategy_group": str(options["strategy_group"]),
		"output_dir": str(options["output_dir"]),
		"full_action_log": bool(options["full_action_log"]),
		"compare_previous": bool(options["compare_previous"]),
		"report_label": str(options.get("report_label", "")),
		"evidence_tier": _evidence_tier(int(options["runs"]), int(options["max_waves"])),
		"profile_overridden": _profile_overridden(options),
		"scenario_probes": str(options.get("scenario_probes", "auto")),
		"scenario_probe_mode": _resolve_scenario_probe_mode(options),
		"coverage_scope": COVERAGE_SCOPE,
		"profile_defaults": PROFILE_DEFAULTS.duplicate(true),
		"strategy_groups": STRATEGY_GROUPS.duplicate(true),
		"raw_user_args": options.get("raw_user_args", []).duplicate(),
		"strategies": options.get("strategies", DEFAULT_STRATEGIES).duplicate(),
		"policy_names": _policy_names(options.get("strategies", DEFAULT_STRATEGIES)),
		"enabled_tower_types": ENABLED_TOWER_TYPES.duplicate(),
		"unsupported_tower_types": UNSUPPORTED_TOWER_TYPES.duplicate(),
	}


func _apply_late_report_metadata(report: Dictionary) -> void:
	var config: Dictionary = report.get("config", {})
	var evidence_tier := str(config.get("evidence_tier", "smoke"))
	var avoidable_total := int(report.get("blocked_action_metrics", {}).get("avoidable_total", 0))
	var balance_actionable := evidence_tier in ["medium", "deep", "overnight"] and avoidable_total == 0
	report["balance_actionable"] = balance_actionable
	config["balance_actionable"] = balance_actionable
	config["coverage_scope"] = str(config.get("coverage_scope", COVERAGE_SCOPE))
	report["config"] = config


func _apply_evidence_warnings(report: Dictionary, output_dir: String) -> void:
	var warnings := _build_evidence_warnings(report, output_dir)
	report["evidence_warnings"] = warnings
	var config: Dictionary = report.get("config", {})
	config["evidence_warnings"] = warnings.duplicate()
	report["config"] = config


func _build_evidence_warnings(report: Dictionary, output_dir: String) -> Array:
	var config: Dictionary = report.get("config", {})
	var current_tier := str(config.get("evidence_tier", "smoke"))
	if _evidence_tier_rank(current_tier) >= _evidence_tier_rank("medium"):
		return []
	var stronger := _stronger_evidence_reports(output_dir, current_tier)
	if stronger.is_empty():
		return []
	var strongest: Dictionary = stronger[0]
	return [
		"Stronger %s evidence exists in this output folder (%s runs / %s waves at `%s`); do not treat this smoke/custom run as the strongest balance packet." % [
			str(strongest.get("evidence_tier", "")),
			int(strongest.get("runs", 0)),
			int(strongest.get("max_waves", 0)),
			str(strongest.get("path", "")),
		]
	]


func _stronger_evidence_reports(output_dir: String, current_tier: String) -> Array:
	var reports: Array = []
	for dir_path in [output_dir, _join_path(output_dir, "archive")]:
		reports.append_array(_evidence_reports_in_dir(str(dir_path), current_tier))
	reports.sort_custom(func(left, right): return _evidence_report_sort_key(left) > _evidence_report_sort_key(right))
	return reports


func _evidence_reports_in_dir(dir_path: String, current_tier: String) -> Array:
	var reports: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return reports
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and _is_evidence_report_file(file_name):
			var path := _join_path(dir_path, file_name)
			var config := _evidence_config_from_file_name(file_name)
			if config.is_empty() and file_name.ends_with(".json"):
				config = _load_report_config(path)
			var tier := str(config.get("evidence_tier", ""))
			if _evidence_tier_rank(tier) > _evidence_tier_rank(current_tier):
				reports.append({
					"path": path,
					"evidence_tier": tier,
					"runs": int(config.get("runs", 0)),
					"max_waves": int(config.get("max_waves", 0)),
					"seed": int(config.get("seed", 0)),
				})
		file_name = dir.get_next()
	dir.list_dir_end()
	return reports


func _is_evidence_report_file(file_name: String) -> bool:
	if file_name.ends_with("_codex_prompt.md"):
		return false
	return file_name.ends_with(".json") or file_name.ends_with(".md")


func _evidence_config_from_file_name(file_name: String) -> Dictionary:
	var tier := ""
	for candidate in ["overnight", "deep", "medium", "smoke"]:
		if file_name.contains("ai_simulation_%s_" % candidate):
			tier = candidate
			break
	if tier.is_empty():
		return {}
	return {
		"evidence_tier": tier,
		"runs": _number_before_token(file_name, "runs"),
		"max_waves": _number_before_token(file_name, "waves"),
		"seed": _number_after_token(file_name, "seed"),
	}


func _number_before_token(text: String, token: String) -> int:
	var index := text.find(token)
	if index <= 0:
		return 0
	var start := index - 1
	while start >= 0 and text.substr(start, 1).is_valid_int():
		start -= 1
	return int(text.substr(start + 1, index - start - 1))


func _number_after_token(text: String, token: String) -> int:
	var index := text.find(token)
	if index < 0:
		return 0
	var start := index + token.length()
	var end := start
	while end < text.length() and text.substr(end, 1).is_valid_int():
		end += 1
	return int(text.substr(start, end - start))


func _evidence_report_sort_key(report: Dictionary) -> String:
	return "%s_%010d_%010d_%s" % [
		_evidence_tier_rank(str(report.get("evidence_tier", ""))),
		int(report.get("runs", 0)),
		int(report.get("max_waves", 0)),
		str(report.get("path", "")),
	]


func _evidence_tier_rank(tier: String) -> int:
	match tier:
		"overnight":
			return 4
		"deep":
			return 3
		"medium":
			return 2
		"smoke":
			return 1
		_:
			return 0


func _policy_names(strategies: Array) -> Dictionary:
	var names := {}
	for strategy in strategies:
		var policy: Dictionary = BOT_POLICIES.get(str(strategy), {})
		names[str(strategy)] = str(policy.get("display_name", str(strategy)))
	return names


func _run_single_simulation(game: Node, options: Dictionary, run_id: int, seed: int, strategy: String, seed_bucket: int, seed_value: int) -> Dictionary:
	game.reset_slice()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var policy: Dictionary = BOT_POLICIES.get(strategy, BOT_POLICIES["balanced_builder"])
	var synthetic := bool(policy.get("synthetic_stress", false))
	var run := {
		"run_id": run_id,
		"seed": seed,
		"run_seed": seed,
		"seed_bucket": seed_bucket,
		"seed_value": seed_value,
		"strategy": strategy,
		"policy_name": str(policy.get("display_name", strategy)),
		"synthetic_stress": synthetic,
		"status": "running",
		"failure_reason": "",
		"focus_tower_type": "",
		"wave_outcomes": [],
		"wave_decisions": [],
		"action_counts": {},
		"blocked_actions": [],
		"tower_usage": {},
		"upgrade_usage": {},
		"upgrade_events": [],
		"target_mode_events": [],
		"issues": [],
		"action_log": [],
		"_sampled_action_log": [],
		"_runtime_invariant_labels": {},
	}

	if not bool(options["full_action_log"]):
		run.erase("action_log")

	if strategy == "tower_specialist":
		run["focus_tower_type"] = ENABLED_TOWER_TYPES[(run_id - 1) % ENABLED_TOWER_TYPES.size()]
	elif strategy == "speed_stress":
		game.money = max(game.money, 1000)

	if strategy == "edge_case_explorer":
		_run_edge_case_setup(game, rng, run, policy, bool(options["full_action_log"]))
	else:
		_prepare_initial_build(game, rng, run, policy, bool(options["full_action_log"]))

	var max_waves: int = int(options["max_waves"])
	for _wave_index in range(max_waves):
		var before_start: Dictionary = game.snapshot()
		if bool(before_start.get("game_over", false)):
			break
		_pre_wave_actions(game, rng, run, policy, bool(options["full_action_log"]))
		var target_wave: int = int(before_start["wave"]) + 1 if bool(before_start.get("wave_complete", false)) else int(before_start["wave"])
		_record_known_wave_gaps(game, run, target_wave)

		var started: bool = game.start_wave()
		_record_action(run, "start_wave", {"wave": target_wave, "started": started}, bool(options["full_action_log"]))
		if not started:
			var wave_control: Dictionary = game.wave_control_snapshot()
			_record_blocked_action(run, "start_wave", str(wave_control.get("disabled_reason", "wave could not start")), {"wave": target_wave, "wave_control": wave_control})
			_add_issue(run, "qol", "medium", "start_wave_blocked", "Bot could not start the next wave.", {"wave": target_wave, "wave_control": wave_control})
			run["failure_reason"] = "start_wave_blocked"
			break

		var outcome := _simulate_current_wave(game, rng, run, policy, bool(options["full_action_log"]), strategy == "speed_stress")
		run["wave_outcomes"].append(outcome)
		if str(outcome.get("status", "")) == "stalled":
			run["failure_reason"] = "wave_stall"
			break
		if bool(game.snapshot().get("game_over", false)):
			break

	var final_snapshot: Dictionary = game.snapshot()
	_finalize_upgrade_events(game, run)
	run["final_snapshot"] = final_snapshot
	run["compact_run_state"] = _compact_run_state(game)
	if not str(run.get("failure_reason", "")).is_empty():
		run["status"] = "failed"
	elif bool(final_snapshot.get("game_over", false)):
		run["status"] = "game_over"
	elif run["wave_outcomes"].is_empty():
		run["status"] = "no_wave_started"
	else:
		run["status"] = "completed"
	_finalize_sampled_action_log(run)
	run.erase("_runtime_invariant_labels")
	run.erase("_sampled_action_log")
	return run


func _prepare_initial_build(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool) -> void:
	var target_count: int = int(policy.get("initial_builds", 2))
	if game.money < 100:
		target_count = min(target_count, 1)
	for _i in range(target_count):
		var tower_type := _choose_build_tower(game, rng, run, policy)
		if tower_type.is_empty():
			break
		if not _place_first_valid(game, tower_type, rng, run, policy, full_action_log):
			break


func _run_edge_case_setup(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool) -> void:
	var start_without_tower: bool = game.start_wave()
	var wave_control: Dictionary = game.wave_control_snapshot()
	_record_action(run, "edge_start_without_tower", {"started": start_without_tower, "wave_control": wave_control}, full_action_log)
	if not start_without_tower:
		var reason := str(wave_control.get("disabled_reason", ""))
		_record_blocked_action(run, "start_without_tower", "start button correctly blocked without towers", {"wave_control": wave_control}, true)
		if reason.is_empty():
			_add_issue(run, "qol", "low", "start_without_tower_blocked", "Starting a wave without towers is blocked but should stay clearly communicated.", {"wave_control": wave_control})

	for tower_type in UNSUPPORTED_TOWER_TYPES:
		var selected: bool = game.select_shop_tower(tower_type)
		_record_action(run, "edge_select_unsupported", {"tower_type": tower_type, "selected": selected}, full_action_log)
		if not selected:
			_add_issue(run, "known_gap", "info", "unsupported_shop_tower", "Tower is present in canonical game data but disabled in the current Godot slice.", {"tower_type": tower_type})

	game.money = max(game.money, 300)
	var invalid_site := Vector2(-32, -32)
	var invalid_preview: Dictionary = game.placement_preview_snapshot(invalid_site, "archer")
	var invalid_place: bool = game.place_selected_tower(invalid_site, "archer")
	_record_action(run, "edge_invalid_placement", {"placed": invalid_place, "site": [-32, -32], "placement_preview": invalid_preview}, full_action_log)
	if not invalid_place:
		_record_blocked_action(run, "invalid_placement", "off-map placement blocked", {"site": [-32, -32], "placement_preview": invalid_preview}, true)

	var placed: bool = _place_first_valid(game, "archer", rng, run, policy, full_action_log)
	if placed:
		var state: Dictionary = game.serialize_run_state()
		var towers: Array = state.get("towers", [])
		var position: Array = towers[0].get("position", []) if towers.size() > 0 else []
		var occupied_preview: Dictionary = game.placement_preview_snapshot(Vector2(float(position[0]), float(position[1])), "archer") if position.size() == 2 else {}
		var repeated: bool = game.place_selected_tower(Vector2(float(position[0]), float(position[1])), "archer") if position.size() == 2 else false
		_record_action(run, "edge_occupied_placement", {"placed": repeated, "position": position, "placement_preview": occupied_preview}, full_action_log)
		if not repeated:
			_record_blocked_action(run, "occupied_placement", "occupied tile placement blocked", {"position": position, "placement_preview": occupied_preview}, true)

		game.selected_tower_index = 0
		var target_changed: bool = game.set_tower_target_mode(0, "last")
		_record_action(run, "edge_target_mode", {"changed": target_changed}, full_action_log)
		var upgraded: bool = _upgrade_selected_with_branch_if_needed(game, run, policy, full_action_log)
		_record_action(run, "edge_upgrade_probe", {"upgraded": upgraded}, full_action_log)
		var sold: bool = game.sell_selected_tower()
		_record_action(run, "edge_sell_probe", {"sold": sold}, full_action_log)

	game.money = max(game.money, 150)
	if int(game.snapshot().get("tower_count", 0)) == 0:
		_place_first_valid(game, "archer", rng, run, policy, full_action_log)


func _pre_wave_actions(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool) -> void:
	if int(game.snapshot().get("tower_count", 0)) == 0:
		if _can_build_any_tower(game, policy):
			_place_first_valid(game, _choose_build_tower(game, rng, run, policy), rng, run, policy, full_action_log)
		return
	var action := _weighted_viable_action(game, rng, policy, policy.get("action_weights", {}))
	if action == "upgrade":
		_upgrade_random_tower(game, rng, run, policy, full_action_log)
	elif action == "build":
		_place_first_valid(game, _choose_build_tower(game, rng, run, policy), rng, run, policy, full_action_log)
	elif action == "target":
		_cycle_random_target_mode(game, rng, run, policy, full_action_log)


func _mid_wave_action(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool) -> void:
	if int(game.snapshot().get("tower_count", 0)) == 0:
		return
	var action := _weighted_viable_action(game, rng, policy, policy.get("mid_wave_weights", {}))
	if action == "upgrade":
		_upgrade_random_tower(game, rng, run, policy, full_action_log)
	elif action == "build":
		_place_first_valid(game, _choose_build_tower(game, rng, run, policy), rng, run, policy, full_action_log)
	elif action == "target":
		_cycle_random_target_mode(game, rng, run, policy, full_action_log)


func _simulate_current_wave(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool, speed_stress: bool) -> Dictionary:
	var start_snapshot: Dictionary = game.snapshot()
	var start_tower_totals: Dictionary = _tower_totals_by_type(game)
	var start_tower_state: Array = game.serialize_run_state().get("towers", [])
	var action_counts_before: Dictionary = run.get("action_counts", {}).duplicate(true)
	var wave_number: int = int(start_snapshot["wave"])
	var wave_schedule: Dictionary = _wave_schedule_row(wave_number)
	var enemy_kind := str(start_snapshot.get("enemy_family", wave_schedule.get("enemy_kind", "")))
	var spawn_limit: int = int(start_snapshot["spawn_limit"])
	var max_cycles: int = max(320, spawn_limit * 35 + wave_number * 30)
	var issue_count_before: int = run["issues"].size()
	var status := "stalled"
	var speed_cycle := [1.0, 2.0, 4.0]
	var cycles_elapsed := max_cycles

	for cycle in range(max_cycles):
		cycles_elapsed = cycle + 1
		if cycle > 0 and cycle % 40 == 0:
			_mid_wave_action(game, rng, run, policy, full_action_log)
		if speed_stress:
			var speed: float = float(speed_cycle[cycle % speed_cycle.size()])
			game.set_game_speed(speed)
			if cycle % 60 == 0:
				_record_action(run, "speed_change", {"wave": wave_number, "speed": speed}, full_action_log)
		else:
			game.set_game_speed(4.0)

		game._process_scaled_delta(STEP_DELTA)
		if cycle % 20 == 0:
			_check_state_invariants(game, run, wave_number)

		var snapshot: Dictionary = game.snapshot()
		if bool(snapshot.get("game_over", false)):
			status = "game_over"
			break
		if bool(snapshot.get("wave_complete", false)):
			status = "complete"
			break

	var final_snapshot: Dictionary = game.snapshot()
	var final_tower_totals: Dictionary = _tower_totals_by_type(game)
	var final_tower_state: Array = game.serialize_run_state().get("towers", [])
	if status == "stalled":
		_add_issue(run, "bug", "high", "wave_stall", "Wave did not resolve within the simulation step budget.", {
			"wave": wave_number,
			"max_cycles": max_cycles,
			"snapshot": _trim_snapshot(final_snapshot),
		})
	else:
		_check_wave_resolution(game, run, wave_number, final_snapshot)

	var start_damage: float = float(start_tower_totals.get("total_damage", 0.0))
	var end_damage: float = float(final_tower_totals.get("total_damage", 0.0))
	var damage_delta: float = max(0.0, end_damage - start_damage)
	var spawned_regular := int(final_snapshot.get("spawned_this_wave", 0))
	var spawned_extra := int(final_snapshot.get("spawned_extra_this_wave", 0))
	var spawned := int(final_snapshot.get("spawned_total_this_wave", spawned_regular + spawned_extra))
	var leaks := int(final_snapshot.get("leaks", 0))
	var outcome := {
		"wave": wave_number,
		"enemy_kind": enemy_kind,
		"wave_label": str(wave_schedule.get("label", start_snapshot.get("enemy_family", ""))),
		"status": status,
		"cycles": cycles_elapsed,
		"spawn_limit": spawn_limit,
		"scheduled_regular_count": int(wave_schedule.get("regular_enemy_count", spawn_limit)),
		"scheduled_boss_count": int(wave_schedule.get("boss_count", 0)),
		"scheduled_commander_count": int(wave_schedule.get("commander_count", 0)),
		"spawned_boss_count": _spawned_special_count(enemy_kind, spawned_regular, "boss"),
		"spawned_commander_count": _spawned_special_count(enemy_kind, spawned_regular, "commander"),
		"spawned_regular": spawned_regular,
		"spawned_extra": spawned_extra,
		"spawned": spawned,
		"kills": int(final_snapshot.get("kills", 0)),
		"leaks": leaks,
		"lives": int(final_snapshot.get("lives", 0)),
		"money": int(final_snapshot.get("money", 0)),
		"start_money": int(start_snapshot.get("money", 0)),
		"end_money": int(final_snapshot.get("money", 0)),
		"money_delta": int(final_snapshot.get("money", 0)) - int(start_snapshot.get("money", 0)),
		"start_research": int(start_snapshot.get("research_points", 0)),
		"end_research": int(final_snapshot.get("research_points", 0)),
		"research_delta": int(final_snapshot.get("research_points", 0)) - int(start_snapshot.get("research_points", 0)),
		"start_lives": int(start_snapshot.get("lives", 0)),
		"end_lives": int(final_snapshot.get("lives", 0)),
		"lives_delta": int(final_snapshot.get("lives", 0)) - int(start_snapshot.get("lives", 0)),
		"start_tower_count": int(start_snapshot.get("tower_count", 0)),
		"end_tower_count": int(final_snapshot.get("tower_count", 0)),
		"tower_count_delta": int(final_snapshot.get("tower_count", 0)) - int(start_snapshot.get("tower_count", 0)),
		"start_money_spent": int(start_tower_totals.get("money_spent", 0)),
		"end_money_spent": int(final_tower_totals.get("money_spent", 0)),
		"spend_delta": int(final_tower_totals.get("money_spent", 0)) - int(start_tower_totals.get("money_spent", 0)),
		"start_damage": start_damage,
		"end_damage": end_damage,
		"damage_delta": damage_delta,
		"damage_per_spawned": damage_delta / float(max(1, spawned)),
		"damage_per_leak": damage_delta / float(max(1, leaks)),
		"rough_dps": damage_delta / max(0.001, float(cycles_elapsed) * STEP_DELTA),
		"tower_damage_delta": _tower_damage_delta_by_type(start_tower_totals.get("by_type", {}), final_tower_totals.get("by_type", {})),
		"tower_level_delta": _tower_level_delta_by_type(start_tower_state, final_tower_state),
		"decision_summary": _wave_decision_summary(run, action_counts_before, start_snapshot, final_snapshot, final_tower_state),
		"issues_added": run["issues"].size() - issue_count_before,
	}
	run["wave_decisions"].append(outcome["decision_summary"])
	return outcome


func _choose_build_tower(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary) -> String:
	var strategy := str(run.get("strategy", ""))
	if strategy == "tower_specialist":
		var focus := str(run.get("focus_tower_type", "archer"))
		return focus if _can_afford_tower(game, focus, policy) else ""
	if strategy == "speed_stress":
		var tower_count: int = int(game.snapshot().get("tower_count", 0))
		for offset in range(ENABLED_TOWER_TYPES.size()):
			var tower_type := str(ENABLED_TOWER_TYPES[(tower_count + offset) % ENABLED_TOWER_TYPES.size()])
			if _can_afford_tower(game, tower_type, policy):
				return tower_type
		return ""
	var tower_weights: Dictionary = policy.get("tower_weights", {})
	var candidates: Array = []
	var snapshot: Dictionary = game.snapshot()
	var wave_pressure := 1.0 + float(max(0, int(snapshot.get("wave", 1)) - 2)) * 0.05
	var leak_pressure := 1.0 + float(max(0, 25 - int(snapshot.get("lives", 25)))) * 0.03
	var build_bias := str(policy.get("build_bias", ""))
	for tower_type in ENABLED_TOWER_TYPES:
		if not _can_afford_tower(game, tower_type, policy):
			continue
		var count := _tower_count(game, tower_type)
		var base_weight := float(tower_weights.get(tower_type, 1.0))
		var diversity_weight := 1.0 / float(count + 1)
		var rotation_weight := 1.0
		if build_bias == "rotation" and count == 0:
			rotation_weight = 1.85
		candidates.append({"tower_type": tower_type, "weight": max(0.01, base_weight * diversity_weight * wave_pressure * leak_pressure * rotation_weight)})
	if candidates.is_empty():
		return ""
	return str(_weighted_pick(rng, candidates, "tower_type"))


func _weighted_viable_action(game: Node, rng: RandomNumberGenerator, policy: Dictionary, weights: Dictionary) -> String:
	var candidates: Array = []
	if _can_upgrade_any_tower(game, policy):
		candidates.append({"action": "upgrade", "weight": float(weights.get("upgrade", 0.40))})
	if _can_build_any_tower(game, policy):
		candidates.append({"action": "build", "weight": float(weights.get("build", 0.40))})
	if int(game.snapshot().get("tower_count", 0)) > 0:
		candidates.append({"action": "target", "weight": float(weights.get("target", 0.20))})
	if candidates.is_empty():
		return ""
	return str(_weighted_pick(rng, candidates, "action"))


func _weighted_pick(rng: RandomNumberGenerator, candidates: Array, value_key: String) -> Variant:
	var total := 0.0
	for candidate in candidates:
		total += max(0.0, float(candidate.get("weight", 0.0)))
	if total <= 0.0:
		return candidates[0].get(value_key, "")
	var roll := rng.randf() * total
	var cursor := 0.0
	for candidate in candidates:
		cursor += max(0.0, float(candidate.get("weight", 0.0)))
		if roll <= cursor:
			return candidate.get(value_key, "")
	return candidates[candidates.size() - 1].get(value_key, "")


func _tower_cost(tower_type: String) -> int:
	return int(_game_data.get("towers", {}).get("shop_costs", {}).get(tower_type, 50))


func _policy_money_floor(policy: Dictionary) -> int:
	return max(0, int(policy.get("money_floor", 0)))


func _available_money_for_action(game: Node, policy: Dictionary) -> int:
	return int(game.money) - _policy_money_floor(policy)


func _can_afford_tower(game: Node, tower_type: String, policy: Dictionary) -> bool:
	return _available_money_for_action(game, policy) >= _tower_cost(tower_type)


func _can_build_any_tower(game: Node, policy: Dictionary) -> bool:
	if bool(game.snapshot().get("game_over", false)):
		return false
	for tower_type in ENABLED_TOWER_TYPES:
		if _can_afford_tower(game, str(tower_type), policy) and _has_valid_build_site_for_tower(game, str(tower_type)):
			return true
	return false


func _has_valid_build_site_for_tower(game: Node, tower_type: String) -> bool:
	var original_build_type := str(game.selected_build_type)
	var original_selection: int = int(game.selected_tower_index)
	if not game.select_shop_tower(tower_type):
		return false
	var has_site := false
	for y in range(108, 570, 27):
		for x in range(54, 864, 27):
			if game.can_place_tower(Vector2(float(x), float(y))):
				has_site = true
				break
		if has_site:
			break
	game.selected_build_type = original_build_type
	game.selected_tower_index = original_selection
	return has_site


func _tower_count(game: Node, tower_type: String) -> int:
	var count := 0
	for tower in game.serialize_run_state().get("towers", []):
		if str(tower.get("type", "")) == tower_type:
			count += 1
	return count


func _choose_build_site(game: Node, rng: RandomNumberGenerator, policy: Dictionary) -> Vector2:
	var candidates: Array = []
	var bias := str(policy.get("site_bias", "balanced"))
	for y in range(108, 570, 27):
		for x in range(54, 864, 27):
			var site := Vector2(float(x), float(y))
			if game.can_place_tower(site):
				candidates.append({
					"site": site,
					"weight": _build_site_score(game, site, bias) + rng.randf() * 0.10,
				})
	if candidates.is_empty():
		return Vector2.INF
	var picked: Variant = _weighted_pick(rng, candidates, "site")
	return picked if picked is Vector2 else Vector2.INF


func _build_site_score(game: Node, site: Vector2, bias: String) -> float:
	var center := Vector2(459.0, 318.0)
	var center_score: float = 1.0 / (1.0 + site.distance_to(center) / 220.0)
	var spread_score: float = _site_spread_score(game, site)
	var path_score: float = _site_path_score(game, site)
	var edge_score: float = max(abs(site.x - center.x) / 459.0, abs(site.y - center.y) / 318.0)
	if bias == "choke":
		return 0.45 + path_score * 2.20 + center_score * 0.45 + spread_score * 0.30
	if bias == "spread":
		return 0.45 + path_score * 1.70 + spread_score * 0.85 + center_score * 0.25
	if bias == "edge":
		return 0.45 + path_score * 1.55 + edge_score * 0.45 + spread_score * 0.25
	if bias == "mixed":
		return 0.45 + path_score * 1.85 + center_score * 0.35 + spread_score * 0.45 + edge_score * 0.20
	return 0.45 + path_score * 1.95 + center_score * 0.45 + spread_score * 0.45


func _site_path_score(game: Node, site: Vector2) -> float:
	var path_points: Array = game.path_points
	if path_points.size() < 2:
		return 0.0
	var best_segment_score: float = 0.0
	var coverage_score: float = 0.0
	for index in range(1, path_points.size()):
		var distance: float = _distance_to_segment(site, path_points[index - 1], path_points[index])
		var segment_score: float = clamp(1.0 - abs(distance - 88.0) / 120.0, 0.0, 1.0)
		best_segment_score = max(best_segment_score, segment_score)
		if distance <= 170.0:
			coverage_score += 0.10
	return clamp(best_segment_score + coverage_score, 0.0, 1.6)


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	if segment.length_squared() == 0.0:
		return point.distance_to(start)
	var t: float = clamp((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _site_spread_score(game: Node, site: Vector2) -> float:
	var min_distance := 9999.0
	var towers: Array = game.serialize_run_state().get("towers", [])
	if towers.is_empty():
		return 1.0
	for tower in towers:
		var position: Array = tower.get("position", [])
		if position.size() == 2:
			min_distance = min(min_distance, site.distance_to(Vector2(float(position[0]), float(position[1]))))
	return clamp(min_distance / 180.0, 0.20, 1.25)


func _place_first_valid(game: Node, tower_type: String, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool) -> bool:
	if tower_type.is_empty():
		return false
	if not _can_afford_tower(game, tower_type, policy):
		_record_action(run, "place_tower", {"tower_type": tower_type, "placed": false, "reason": "reserved_cash_floor"}, full_action_log)
		return false
	var selected: bool = game.select_shop_tower(tower_type)
	if not selected:
		_record_blocked_action(run, "select_tower", "tower could not be selected", {"tower_type": tower_type})
		_record_action(run, "select_tower", {"tower_type": tower_type, "selected": false}, full_action_log)
		return false
	var site: Vector2 = _choose_build_site(game, rng, policy)
	if site != Vector2.INF:
		var placed: bool = game.place_selected_tower(site, tower_type)
		_record_action(run, "place_tower", {"tower_type": tower_type, "placed": placed, "site": [site.x, site.y], "site_bias": str(policy.get("site_bias", "balanced"))}, full_action_log)
		if placed:
			_increment_count(run["tower_usage"], tower_type)
			return true
	_record_blocked_action(run, "place_tower", "no affordable valid build site found", {"tower_type": tower_type})
	_add_issue(run, "qol", "medium", "no_valid_build_action", "Bot could not find an affordable valid build site.", {"tower_type": tower_type})
	_record_action(run, "place_tower", {"tower_type": tower_type, "placed": false}, full_action_log)
	return false


func _upgrade_random_tower(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool) -> bool:
	var candidates: Array = _upgrade_candidate_indices(game, policy)
	if candidates.is_empty():
		return false
	var scored: Array = []
	for candidate_index in candidates:
		scored.append({"index": int(candidate_index), "weight": _upgrade_candidate_score(game, int(candidate_index), policy)})
	var index := int(_weighted_pick(rng, scored, "index"))
	game.selected_tower_index = index
	return _upgrade_selected_with_branch_if_needed(game, run, policy, full_action_log)


func _upgrade_candidate_score(game: Node, index: int, policy: Dictionary) -> float:
	var towers: Array = game.serialize_run_state().get("towers", [])
	if index < 0 or index >= towers.size():
		return 0.01
	var tower: Dictionary = towers[index]
	var bias := str(policy.get("upgrade_bias", ""))
	var level := int(tower.get("level", 1))
	var kills := int(tower.get("kills", 0))
	var damage := float(tower.get("total_damage", 0.0))
	var money_spent := int(tower.get("money_spent", 0))
	var base := 1.0 + float(kills) * 0.12 + damage / 650.0
	if bias == "value":
		base += 80.0 / float(max(40, money_spent))
	elif bias == "damage":
		base += damage / 350.0 + float(kills) * 0.08
	elif bias == "coverage":
		base += 1.0 / float(level + 1)
	elif bias == "late":
		base += float(level) * 0.35 + damage / 500.0
	elif bias == "underused":
		base += 1.0 / float(_tower_count(game, str(tower.get("type", ""))) + 1)
	return max(0.01, base)


func _can_upgrade_any_tower(game: Node, policy: Dictionary) -> bool:
	return not _upgrade_candidate_indices(game, policy).is_empty()


func _upgrade_candidate_indices(game: Node, policy: Dictionary) -> Array:
	var candidates: Array = []
	var original_selection: int = int(game.selected_tower_index)
	var tower_count: int = int(game.snapshot().get("tower_count", 0))
	for index in range(tower_count):
		game.selected_tower_index = index
		var panel: Dictionary = game.upgrade_panel_snapshot()
		if _panel_has_viable_upgrade(panel, game, policy):
			candidates.append(index)
	game.selected_tower_index = original_selection
	return candidates


func _panel_has_viable_upgrade(panel: Dictionary, game: Node, policy: Dictionary) -> bool:
	if not bool(panel.get("visible", false)):
		return false
	if bool(panel.get("needs_branch_choice", false)):
		return not panel.get("branch_options", []).is_empty()
	for option in panel.get("upgrade_options", []):
		var cost := int(option.get("cost", 0))
		if bool(option.get("enabled", false)) and int(game.money) - cost >= _policy_money_floor(policy):
			return true
	return false


func _upgrade_selected_with_branch_if_needed(game: Node, run: Dictionary, policy: Dictionary, full_action_log: bool) -> bool:
	var selected_index: int = int(game.selected_tower_index)
	var panel: Dictionary = game.upgrade_panel_snapshot()
	if not bool(panel.get("visible", false)):
		_record_blocked_action(run, "upgrade_tower", "no selected tower upgrade panel", {})
		return false
	if bool(panel.get("needs_branch_choice", false)):
		var branches: Array = panel.get("branch_options", [])
		if branches.is_empty():
			_record_blocked_action(run, "choose_branch", "branch choice required but no options available", panel)
			_add_issue(run, "bug", "medium", "missing_branch_options", "A tower required a branch choice but exposed no branch options.", _panel_detail(panel))
			return false
		var chosen_branch_id := str(branches[0].get("id", ""))
		var chose: bool = game.choose_selected_tower_branch(chosen_branch_id)
		_record_action(run, "choose_branch", {"tower_type": panel.get("tower_type", ""), "branch_id": chosen_branch_id, "chosen": chose}, full_action_log)
		if not chose:
			_record_blocked_action(run, "choose_branch", "branch choice was rejected", {"branch_id": chosen_branch_id})
			return false

	var before: Dictionary = game.upgrade_panel_snapshot()
	if not _panel_has_viable_upgrade(before, game, policy):
		_record_action(run, "upgrade_tower", {
			"tower_type": before.get("tower_type", ""),
			"upgraded": false,
			"reason": "reserved_cash_floor_or_unavailable",
		}, full_action_log)
		return false
	var tower_type := str(before.get("tower_type", ""))
	var before_tower: Dictionary = _tower_record_at(game, selected_index)
	var before_money: int = int(game.money)
	var before_options: Array = before.get("upgrade_options", [])
	var upgrade_cost: int = int(before_options[0].get("cost", 0)) if not before_options.is_empty() else 0
	var branch_id := str(before_tower.get("selected_branch", ""))
	var upgraded: bool = game.upgrade_selected_tower()
	var after: Dictionary = game.upgrade_panel_snapshot()
	var after_tower: Dictionary = _tower_record_at(game, selected_index)
	_record_action(run, "upgrade_tower", {
		"tower_type": tower_type,
		"upgraded": upgraded,
		"branch_id": branch_id,
		"cost": upgrade_cost,
		"before_level": int(before_tower.get("level", 0)),
		"after_level": int(after_tower.get("level", 0)),
	}, full_action_log)
	run["upgrade_events"].append({
		"wave": int(game.snapshot().get("wave", 0)),
		"tower_index": selected_index,
		"tower_type": tower_type,
		"branch_id": branch_id,
		"attempted": true,
		"succeeded": upgraded,
		"cost": upgrade_cost,
		"money_before": before_money,
		"money_after": int(game.money),
		"before_level": int(before_tower.get("level", 0)),
		"after_level": int(after_tower.get("level", 0)),
		"level_gain": int(after_tower.get("level", 0)) - int(before_tower.get("level", 0)),
		"before_money_spent": int(before_tower.get("money_spent", 0)),
		"after_money_spent": int(after_tower.get("money_spent", 0)),
		"before_damage": float(before_tower.get("total_damage", 0.0)),
		"before_kills": int(before_tower.get("kills", 0)),
		"final_damage": float(after_tower.get("total_damage", 0.0)),
		"final_kills": int(after_tower.get("kills", 0)),
		"damage_after_upgrade": 0.0,
		"kills_after_upgrade": 0,
	})
	if upgraded:
		_increment_count(run["upgrade_usage"], tower_type)
		return true
	_record_blocked_action(run, "upgrade_tower", "upgrade was unavailable or unaffordable", _panel_detail(before))
	return false


func _cycle_random_target_mode(game: Node, rng: RandomNumberGenerator, run: Dictionary, policy: Dictionary, full_action_log: bool) -> bool:
	var tower_count: int = int(game.snapshot().get("tower_count", 0))
	if tower_count <= 0:
		return false
	var index := rng.randi_range(0, tower_count - 1)
	var preferred := str(policy.get("target_bias", ""))
	var mode_weights: Array = []
	for target_mode in TARGET_MODES:
		var weight := 1.0
		if str(target_mode) == preferred:
			weight = 4.0
		elif preferred == "last" and str(target_mode) == "closest":
			weight = 2.0
		elif preferred == "strongest" and str(target_mode) == "flying":
			weight = 1.6
		mode_weights.append({"mode": target_mode, "weight": weight})
	var mode: String = str(_weighted_pick(rng, mode_weights, "mode"))
	var before_tower: Dictionary = _tower_record_at(game, index)
	var tower_type := str(before_tower.get("type", ""))
	var previous_mode := str(before_tower.get("target_mode", ""))
	var changed: bool = game.set_tower_target_mode(index, mode)
	_record_action(run, "set_target_mode", {"index": index, "tower_type": tower_type, "previous_mode": previous_mode, "mode": mode, "changed": changed}, full_action_log)
	run["target_mode_events"].append({
		"wave": int(game.snapshot().get("wave", 0)),
		"tower_index": index,
		"tower_type": tower_type,
		"previous_mode": previous_mode,
		"mode": mode,
		"changed": changed,
	})
	if not changed:
		_record_blocked_action(run, "set_target_mode", "target mode rejected", {"index": index, "mode": mode})
	return changed


func _record_known_wave_gaps(_game: Node, run: Dictionary, wave_number: int) -> void:
	var schedule: Array = _game_data.get("waves", {}).get("schedule", [])
	if wave_number < 1 or wave_number > schedule.size():
		return
	var row: Dictionary = schedule[wave_number - 1]
	var boss_count := int(row.get("boss_count", 0))
	var commander_count := int(row.get("commander_count", 0))
	if boss_count > 0 or commander_count > 0:
		_add_issue(run, "known_gap", "info", "boss_commander_rules_unported", "Canonical wave has boss or commander pressure that the current slice does not spawn.", {
			"wave": wave_number,
			"canonical_boss_count": boss_count,
			"canonical_commander_count": commander_count,
		})


func _check_state_invariants(game: Node, run: Dictionary, wave_number: int) -> void:
	if game.has_method("runtime_invariant_failures"):
		var runtime_failures: Array = game.runtime_invariant_failures()
		var seen: Dictionary = run.get("_runtime_invariant_labels", {})
		for failure in runtime_failures:
			var key := str(failure)
			if seen.has(key):
				continue
			seen[key] = true
			_add_issue(run, "bug", "high", "runtime_invariant_failed", "Game runtime invariant failed during AI simulation.", {
				"wave": wave_number,
				"failure": key,
				"snapshot": _trim_snapshot(game.snapshot()),
			})
		run["_runtime_invariant_labels"] = seen
	var snapshot: Dictionary = game.snapshot()
	for key in ["money", "lives", "research_points", "spawned_this_wave", "spawned_extra_this_wave", "spawned_total_this_wave", "kills", "leaks", "tower_count", "enemy_count", "projectile_count"]:
		if int(snapshot.get(key, 0)) < 0:
			_add_issue(run, "bug", "high", "negative_state_value", "Snapshot contains a negative state value.", {"wave": wave_number, "key": key, "value": int(snapshot.get(key, 0))})
	if bool(snapshot.get("wave_complete", false)) and int(snapshot.get("enemy_count", 0)) > 0:
		_add_issue(run, "bug", "high", "complete_with_enemies", "Wave is complete while enemies remain.", {"wave": wave_number, "snapshot": _trim_snapshot(snapshot)})


func _check_wave_resolution(game: Node, run: Dictionary, wave_number: int, snapshot: Dictionary) -> void:
	var spawned_regular := int(snapshot.get("spawned_this_wave", 0))
	var spawned_extra := int(snapshot.get("spawned_extra_this_wave", 0))
	var has_total_accounting := snapshot.has("spawned_total_this_wave")
	var spawned := int(snapshot.get("spawned_total_this_wave", spawned_regular))
	var resolved := int(snapshot.get("kills", 0)) + int(snapshot.get("leaks", 0))
	if bool(snapshot.get("wave_complete", false)) and not has_total_accounting and _wave_has_death_spawns(wave_number):
		_add_issue(run, "validation", "medium", "wave_total_accounting_unavailable", "Completed split-capable wave could not verify total spawned participants from this snapshot.", {
			"wave": wave_number,
			"spawned_regular": spawned_regular,
			"resolved": resolved,
		})
		return
	if bool(snapshot.get("wave_complete", false)) and resolved != spawned:
		_add_issue(run, "bug", "high", "wave_resolution_mismatch", "Completed wave has unresolved kills/leaks count.", {
			"wave": wave_number,
			"spawned_regular": spawned_regular,
			"spawned_extra": spawned_extra,
			"spawned_total": spawned,
			"resolved": resolved,
		})
	if bool(snapshot.get("wave_complete", false)) and int(snapshot.get("projectile_count", 0)) > 0:
		_add_issue(run, "bug", "medium", "complete_with_projectiles", "Wave completed with projectiles still active.", {
			"wave": wave_number,
			"projectile_count": int(snapshot.get("projectile_count", 0)),
		})
	var restored_game := _create_restore_probe(game)
	if restored_game != null:
		var restored: bool = restored_game.restore_run_state(game.serialize_run_state())
		if not restored:
			_add_issue(run, "bug", "high", "invalid_state_restore", "Serialized run state could not be restored.", {"wave": wave_number})
		restored_game.queue_free()


func _wave_has_death_spawns(wave_number: int) -> bool:
	var schedule: Array = _game_data.get("waves", {}).get("schedule", [])
	if wave_number < 1 or wave_number > schedule.size():
		return false
	var row: Variant = schedule[wave_number - 1]
	if not (row is Dictionary):
		return false
	var modifier_data: Variant = row.get("modifier_data", {})
	if not (modifier_data is Dictionary):
		return false
	var effects: Variant = modifier_data.get("effects", {})
	return effects is Dictionary and int(effects.get("death_spawns", 0)) > 0


func _create_restore_probe(game: Node) -> Node:
	var script: Script = game.get_script()
	if script == null:
		return null
	var probe: Node = script.new()
	root.add_child(probe)
	probe.name = "SimulationRestoreProbe"
	probe.reset_slice()
	return probe


func _record_action(run: Dictionary, action: String, detail: Dictionary, full_action_log: bool) -> void:
	_increment_count(run["action_counts"], action)
	if run.has("_sampled_action_log") and run["_sampled_action_log"].size() < SAMPLED_ACTION_LOG_LIMIT:
		run["_sampled_action_log"].append({
			"action": action,
			"detail": _safe_detail(detail),
		})
	if full_action_log and run.has("action_log"):
		run["action_log"].append({
			"action": action,
			"detail": detail.duplicate(true),
		})


func _record_blocked_action(run: Dictionary, action: String, reason: String, detail: Dictionary, expected: bool = false) -> void:
	run["blocked_actions"].append({
		"action": action,
		"reason": reason,
		"detail": _safe_detail(detail),
		"expected": expected,
	})


func _add_issue(run: Dictionary, category: String, severity: String, label: String, message: String, detail: Dictionary) -> void:
	run["issues"].append({
		"category": category,
		"severity": severity,
		"label": label,
		"message": message,
		"detail": _safe_detail(detail),
		"run_id": int(run.get("run_id", 0)),
		"seed": int(run.get("seed", 0)),
		"strategy": str(run.get("strategy", "")),
		"synthetic_stress": bool(run.get("synthetic_stress", false)),
	})


func _safe_detail(detail: Dictionary) -> Dictionary:
	var safe := {}
	for key in detail.keys():
		var value: Variant = detail[key]
		if value is Vector2:
			safe[key] = [value.x, value.y]
		elif value is Rect2:
			safe[key] = {
				"position": [value.position.x, value.position.y],
				"size": [value.size.x, value.size.y],
			}
		elif value is Dictionary:
			safe[key] = _safe_detail(value)
		elif value is Array:
			safe[key] = _safe_array(value)
		else:
			safe[key] = value
	return safe


func _safe_array(values: Array) -> Array:
	var safe: Array = []
	for value in values:
		if value is Vector2:
			safe.append([value.x, value.y])
		elif value is Rect2:
			safe.append({"position": [value.position.x, value.position.y], "size": [value.size.x, value.size.y]})
		elif value is Dictionary:
			safe.append(_safe_detail(value))
		elif value is Array:
			safe.append(_safe_array(value))
		else:
			safe.append(value)
	return safe


func _finalize_sampled_action_log(run: Dictionary) -> void:
	var categories := {}
	for issue in run.get("issues", []):
		categories[str(issue.get("category", ""))] = true
	if not (categories.has("bug") or categories.has("qol") or categories.has("balance")):
		run.erase("sampled_action_log")
		return
	run["sampled_action_log"] = run.get("_sampled_action_log", []).duplicate(true).slice(0, SAMPLED_ACTION_LOG_LIMIT)


func _finalize_upgrade_events(game: Node, run: Dictionary) -> void:
	var towers: Array = game.serialize_run_state().get("towers", [])
	for event in run.get("upgrade_events", []):
		var index := int(event.get("tower_index", -1))
		if index < 0 or index >= towers.size():
			event["final_missing"] = true
			continue
		var tower: Dictionary = towers[index]
		var final_damage := float(tower.get("total_damage", 0.0))
		var final_kills := int(tower.get("kills", 0))
		event["final_damage"] = final_damage
		event["final_kills"] = final_kills
		event["damage_after_upgrade"] = max(0.0, final_damage - float(event.get("before_damage", 0.0)))
		event["kills_after_upgrade"] = max(0, final_kills - int(event.get("before_kills", 0)))


func _tower_record_at(game: Node, index: int) -> Dictionary:
	var towers: Array = game.serialize_run_state().get("towers", [])
	if index < 0 or index >= towers.size():
		return {}
	return towers[index].duplicate(true)


func _panel_detail(panel: Dictionary) -> Dictionary:
	return {
		"tower_type": str(panel.get("tower_type", "")),
		"stats": str(panel.get("stats", "")),
		"needs_branch_choice": bool(panel.get("needs_branch_choice", false)),
		"upgrade_options": int(panel.get("upgrade_options", []).size()),
		"money": int(panel.get("money", 0)),
	}


func _trim_snapshot(snapshot: Dictionary) -> Dictionary:
	return {
		"money": int(snapshot.get("money", 0)),
		"lives": int(snapshot.get("lives", 0)),
		"wave": int(snapshot.get("wave", 0)),
		"wave_active": bool(snapshot.get("wave_active", false)),
		"wave_complete": bool(snapshot.get("wave_complete", false)),
		"game_over": bool(snapshot.get("game_over", false)),
		"spawned_this_wave": int(snapshot.get("spawned_this_wave", 0)),
		"spawned_extra_this_wave": int(snapshot.get("spawned_extra_this_wave", 0)),
		"spawned_total_this_wave": int(snapshot.get("spawned_total_this_wave", snapshot.get("spawned_this_wave", 0))),
		"spawn_limit": int(snapshot.get("spawn_limit", 0)),
		"kills": int(snapshot.get("kills", 0)),
		"leaks": int(snapshot.get("leaks", 0)),
		"tower_count": int(snapshot.get("tower_count", 0)),
		"enemy_count": int(snapshot.get("enemy_count", 0)),
		"projectile_count": int(snapshot.get("projectile_count", 0)),
	}


func _compact_run_state(game: Node) -> Dictionary:
	var state: Dictionary = game.serialize_run_state()
	var towers: Array = []
	for tower in state.get("towers", []):
		towers.append({
			"type": str(tower.get("type", "")),
			"level": int(tower.get("level", 0)),
			"target_mode": str(tower.get("target_mode", "")),
			"selected_branch": str(tower.get("selected_branch", "")),
			"money_spent": int(tower.get("money_spent", 0)),
			"kills": int(tower.get("kills", 0)),
			"total_damage": float(tower.get("total_damage", 0.0)),
			"mastery_xp": float(tower.get("mastery_xp", 0.0)),
			"mutations": tower.get("mutations", []).duplicate(true),
			"is_paragon": bool(tower.get("is_paragon", false)),
		})
	return {
		"schema_version": int(state.get("schema_version", 0)),
		"money": int(state.get("money", 0)),
		"lives": int(state.get("lives", 0)),
		"research_points": int(state.get("research_points", 0)),
		"wave": int(state.get("wave", 0)),
		"wave_active": bool(state.get("wave_active", false)),
		"wave_complete": bool(state.get("wave_complete", false)),
		"game_over": bool(state.get("game_over", false)),
		"towers": towers,
		"enemy_count": state.get("enemies", []).size(),
		"projectile_count": state.get("projectiles", []).size(),
	}


func _tower_totals_by_type(game: Node) -> Dictionary:
	var totals := {
		"money_spent": 0,
		"total_damage": 0.0,
		"by_type": {},
	}
	for tower in game.serialize_run_state().get("towers", []):
		var tower_type := str(tower.get("type", "unknown"))
		if not totals["by_type"].has(tower_type):
			totals["by_type"][tower_type] = {"money_spent": 0, "total_damage": 0.0, "kills": 0, "count": 0}
		var row: Dictionary = totals["by_type"][tower_type]
		var money_spent := int(tower.get("money_spent", 0))
		var total_damage := float(tower.get("total_damage", 0.0))
		row["money_spent"] = int(row["money_spent"]) + money_spent
		row["total_damage"] = float(row["total_damage"]) + total_damage
		row["kills"] = int(row["kills"]) + int(tower.get("kills", 0))
		row["count"] = int(row["count"]) + 1
		totals["money_spent"] = int(totals["money_spent"]) + money_spent
		totals["total_damage"] = float(totals["total_damage"]) + total_damage
	return totals


func _tower_damage_delta_by_type(start_by_type: Dictionary, end_by_type: Dictionary) -> Dictionary:
	var result := {}
	for tower_type in ENABLED_TOWER_TYPES:
		var start_row: Dictionary = start_by_type.get(tower_type, {})
		var end_row: Dictionary = end_by_type.get(tower_type, {})
		var delta: float = float(end_row.get("total_damage", 0.0)) - float(start_row.get("total_damage", 0.0))
		if delta > 0.0:
			result[tower_type] = delta
	return result


func _tower_level_delta_by_type(start_towers: Array, end_towers: Array) -> Dictionary:
	var start_levels := {}
	var end_levels := {}
	for tower in start_towers:
		var tower_type := str(tower.get("type", "unknown"))
		start_levels[tower_type] = int(start_levels.get(tower_type, 0)) + int(tower.get("level", 0))
	for tower in end_towers:
		var tower_type := str(tower.get("type", "unknown"))
		end_levels[tower_type] = int(end_levels.get(tower_type, 0)) + int(tower.get("level", 0))
	var result := {}
	for tower_type in end_levels.keys():
		var delta := int(end_levels.get(tower_type, 0)) - int(start_levels.get(tower_type, 0))
		if delta != 0:
			result[str(tower_type)] = delta
	return result


func _wave_decision_summary(run: Dictionary, action_counts_before: Dictionary, start_snapshot: Dictionary, final_snapshot: Dictionary, final_towers: Array) -> Dictionary:
	return {
		"wave": int(final_snapshot.get("wave", start_snapshot.get("wave", 0))),
		"strategy": str(run.get("strategy", "")),
		"action_delta": _count_delta(action_counts_before, run.get("action_counts", {})),
		"start_towers": int(start_snapshot.get("tower_count", 0)),
		"end_towers": int(final_snapshot.get("tower_count", 0)),
		"start_money": int(start_snapshot.get("money", 0)),
		"end_money": int(final_snapshot.get("money", 0)),
		"target_modes": _target_mode_counts(final_towers),
		"tower_levels": _tower_level_counts(final_towers),
	}


func _count_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key in after.keys():
		var delta := int(after.get(key, 0)) - int(before.get(key, 0))
		if delta != 0:
			result[str(key)] = delta
	return result


func _target_mode_counts(towers: Array) -> Dictionary:
	var counts := {}
	for tower in towers:
		_increment_count(counts, "%s:%s" % [str(tower.get("type", "")), str(tower.get("target_mode", ""))])
	return counts


func _tower_level_counts(towers: Array) -> Dictionary:
	var counts := {}
	for tower in towers:
		_increment_count(counts, "%s:L%s" % [str(tower.get("type", "")), int(tower.get("level", 0))])
	return counts


func _wave_schedule_row(wave_number: int) -> Dictionary:
	var schedule: Array = _game_data.get("waves", {}).get("schedule", [])
	if wave_number < 1 or wave_number > schedule.size():
		return {}
	var row: Variant = schedule[wave_number - 1]
	return row if row is Dictionary else {}


func _spawned_special_count(enemy_kind: String, spawned: int, flag: String) -> int:
	var modifiers: Dictionary = _game_data.get("enemies", {}).get("kind_modifiers", {})
	var modifier: Variant = modifiers.get(enemy_kind, {})
	if modifier is Dictionary and bool(modifier.get(flag, false)):
		return spawned
	return 0


func _build_balance_issues(runs: Array) -> Array:
	var issues: Array = []
	var balanced_success_runs: Array = []
	var normal_runs: Array = []
	var specialist_by_tower := {}
	var leak_by_wave := {}
	var leak_by_enemy_kind := {}
	var special_wave_record := {"waves": 0, "completed": 0, "scheduled": 0, "spawned": 0}
	var branch_successes := {}
	var target_mode_records := {}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		normal_runs.append(run)
		if str(run.get("strategy", "")) == "balanced_builder" and str(run.get("status", "")) == "completed":
			balanced_success_runs.append(run)
		if str(run.get("strategy", "")) == "tower_specialist":
			var focus := str(run.get("focus_tower_type", ""))
			if not specialist_by_tower.has(focus):
				specialist_by_tower[focus] = {"runs": 0, "completed": 0}
			specialist_by_tower[focus]["runs"] = int(specialist_by_tower[focus]["runs"]) + 1
			if str(run.get("status", "")) == "completed":
				specialist_by_tower[focus]["completed"] = int(specialist_by_tower[focus]["completed"]) + 1
		for outcome in run.get("wave_outcomes", []):
			var wave := str(outcome.get("wave", 0))
			if not leak_by_wave.has(wave):
				leak_by_wave[wave] = {"runs": 0, "leaks": 0, "spawned": 0}
			leak_by_wave[wave]["runs"] = int(leak_by_wave[wave]["runs"]) + 1
			leak_by_wave[wave]["leaks"] = int(leak_by_wave[wave]["leaks"]) + int(outcome.get("leaks", 0))
			leak_by_wave[wave]["spawned"] = int(leak_by_wave[wave]["spawned"]) + int(outcome.get("spawned", 0))
			var enemy_kind := str(outcome.get("enemy_kind", "unknown"))
			if not leak_by_enemy_kind.has(enemy_kind):
				leak_by_enemy_kind[enemy_kind] = {"waves": 0, "leaks": 0, "spawned": 0}
			leak_by_enemy_kind[enemy_kind]["waves"] = int(leak_by_enemy_kind[enemy_kind]["waves"]) + 1
			leak_by_enemy_kind[enemy_kind]["leaks"] = int(leak_by_enemy_kind[enemy_kind]["leaks"]) + int(outcome.get("leaks", 0))
			leak_by_enemy_kind[enemy_kind]["spawned"] = int(leak_by_enemy_kind[enemy_kind]["spawned"]) + int(outcome.get("spawned", 0))
			var scheduled_special := int(outcome.get("scheduled_boss_count", 0)) + int(outcome.get("scheduled_commander_count", 0))
			if scheduled_special > 0:
				special_wave_record["waves"] = int(special_wave_record["waves"]) + 1
				special_wave_record["scheduled"] = int(special_wave_record["scheduled"]) + scheduled_special
				special_wave_record["spawned"] = int(special_wave_record["spawned"]) + int(outcome.get("spawned_boss_count", 0)) + int(outcome.get("spawned_commander_count", 0))
				if str(outcome.get("status", "")) == "complete":
					special_wave_record["completed"] = int(special_wave_record["completed"]) + 1
		for event in run.get("upgrade_events", []):
			if bool(event.get("succeeded", false)):
				var branch_key := "%s:%s" % [str(event.get("tower_type", "")), str(event.get("branch_id", "unbranched"))]
				_increment_count(branch_successes, branch_key)
		for event in run.get("target_mode_events", []):
			var target_key := "%s:%s" % [str(event.get("tower_type", "")), str(event.get("mode", ""))]
			if not target_mode_records.has(target_key):
				target_mode_records[target_key] = {"selections": 0, "waves": 0, "completed": 0, "leaks": 0, "spawned": 0}
			var target_row: Dictionary = target_mode_records[target_key]
			target_row["selections"] = int(target_row["selections"]) + 1
			var event_wave := int(event.get("wave", 0))
			for outcome in run.get("wave_outcomes", []):
				if int(outcome.get("wave", 0)) < event_wave:
					continue
				target_row["waves"] = int(target_row["waves"]) + 1
				if str(outcome.get("status", "")) == "complete":
					target_row["completed"] = int(target_row["completed"]) + 1
				target_row["leaks"] = int(target_row["leaks"]) + int(outcome.get("leaks", 0))
				target_row["spawned"] = int(target_row["spawned"]) + int(outcome.get("spawned", 0))

	if balanced_success_runs.size() >= 5:
		var tower_totals := {}
		var total_towers := 0
		for run in balanced_success_runs:
			for tower_type in run.get("tower_usage", {}).keys():
				var count := int(run["tower_usage"][tower_type])
				_increment_count(tower_totals, str(tower_type), count)
				total_towers += count
		for tower_type in ENABLED_TOWER_TYPES:
			var count := int(tower_totals.get(tower_type, 0))
			if count == 0:
				issues.append(_batch_issue("balance", "medium", "tower_unused_by_successful_balanced_bots", "Successful balanced bots never selected this enabled tower.", {"tower_type": tower_type, "sample_runs": balanced_success_runs.size()}))
			elif total_towers > 0 and float(count) / float(total_towers) > 0.55:
				issues.append(_batch_issue("balance", "medium", "tower_overrepresented_by_successful_balanced_bots", "Successful balanced bots leaned heavily on one tower type.", {"tower_type": tower_type, "share": float(count) / float(total_towers), "sample_runs": balanced_success_runs.size()}))

	for tower_type in specialist_by_tower.keys():
		var record: Dictionary = specialist_by_tower[tower_type]
		if int(record.get("runs", 0)) >= 3 and int(record.get("completed", 0)) == 0:
			issues.append(_batch_issue("balance", "medium", "tower_specialist_no_completions", "Tower-specialist bots could not complete the configured wave target with this focus tower.", {"tower_type": str(tower_type), "runs": int(record["runs"])}))

	for wave_key in leak_by_wave.keys():
		var wave_record: Dictionary = leak_by_wave[wave_key]
		var wave_spawned := int(wave_record.get("spawned", 0))
		if int(wave_record.get("runs", 0)) >= 5 and wave_spawned > 0:
			var wave_leak_rate := float(wave_record.get("leaks", 0)) / float(wave_spawned)
			if wave_leak_rate > 0.35:
				issues.append(_batch_issue("balance", "medium", "high_wave_leak_rate", "Normal bot runs leaked a high share of spawned enemies on this wave.", {"wave": int(wave_key), "leak_rate": wave_leak_rate, "runs": int(wave_record["runs"])}))

	for enemy_kind in leak_by_enemy_kind.keys():
		var enemy_record: Dictionary = leak_by_enemy_kind[enemy_kind]
		var enemy_spawned := int(enemy_record.get("spawned", 0))
		if int(enemy_record.get("waves", 0)) >= 5 and enemy_spawned >= 100:
			var enemy_leak_rate := _safe_ratio(int(enemy_record.get("leaks", 0)), enemy_spawned)
			if enemy_leak_rate > 0.35:
				issues.append(_batch_issue("balance", "medium", "high_enemy_kind_leak_rate", "Normal bot runs leaked heavily against this enemy kind.", {"enemy_kind": str(enemy_kind), "leak_rate": enemy_leak_rate, "waves": int(enemy_record["waves"])}))

	if int(special_wave_record.get("waves", 0)) >= 5:
		var special_completion := _safe_ratio(int(special_wave_record.get("completed", 0)), int(special_wave_record.get("waves", 0)))
		if int(special_wave_record.get("spawned", 0)) < int(special_wave_record.get("scheduled", 0)) or special_completion < 0.75:
			issues.append(_batch_issue("balance", "medium", "boss_commander_wave_diagnostic", "Boss/commander scheduled pressure needs diagnostic review before balance tuning.", special_wave_record))

	var available_branches := _available_branch_catalog()
	var total_branch_successes := 0
	for key in branch_successes.keys():
		total_branch_successes += int(branch_successes[key])
	if total_branch_successes >= 10:
		for tower_type in available_branches.keys():
			for branch_id in available_branches[tower_type]:
				var branch_catalog_key := "%s:%s" % [str(tower_type), str(branch_id)]
				if int(branch_successes.get(branch_catalog_key, 0)) == 0:
					issues.append(_batch_issue("balance", "low", "upgrade_branch_unexercised", "Normal bot upgrade choices never exercised this available branch.", {"tower_type": str(tower_type), "branch_id": str(branch_id), "successful_branch_upgrades": total_branch_successes}))

	for key in target_mode_records.keys():
		var target_record: Dictionary = target_mode_records[key]
		if int(target_record.get("selections", 0)) >= 10 and int(target_record.get("spawned", 0)) >= 100:
			var target_leak_rate := _safe_ratio(int(target_record.get("leaks", 0)), int(target_record.get("spawned", 0)))
			var completion_rate := _safe_ratio(int(target_record.get("completed", 0)), int(target_record.get("waves", 0)))
			if target_leak_rate > 0.30 and completion_rate < 0.85:
				issues.append(_batch_issue("balance", "low", "target_mode_poor_outcome", "A target mode had weak downstream outcomes in normal bot telemetry.", {"tower_mode": str(key), "leak_rate": target_leak_rate, "completion_rate": completion_rate, "selections": int(target_record["selections"])}))

	var upgrade_total := 0
	for run in normal_runs:
		for tower_type in run.get("upgrade_usage", {}).keys():
			upgrade_total += int(run["upgrade_usage"][tower_type])
	if normal_runs.size() >= 5 and upgrade_total == 0:
		issues.append(_batch_issue("balance", "medium", "upgrade_path_underused", "Normal bots completed their attempts without any successful upgrades.", {"sample_runs": normal_runs.size()}))
	return issues


func _batch_issue(category: String, severity: String, label: String, message: String, detail: Dictionary) -> Dictionary:
	return {
		"category": category,
		"severity": severity,
		"label": label,
		"message": message,
		"detail": _safe_detail(detail),
		"run_id": 0,
		"seed": 0,
		"strategy": "batch_analysis",
		"synthetic_stress": false,
	}


func _assign_issue_ids(issues: Array) -> void:
	var counters := {}
	for issue in issues:
		var category := str(issue.get("category", "issue"))
		_increment_count(counters, category)
		issue["id"] = "%s-%04d" % [category.to_upper(), int(counters[category])]


func _build_summary(runs: Array, issues: Array) -> Dictionary:
	var summary := {
		"total_runs": runs.size(),
		"completed_runs": 0,
		"game_over_runs": 0,
		"failed_runs": 0,
		"normal_runs": 0,
		"synthetic_runs": 0,
		"issue_counts": {},
		"severity_counts": {},
		"tower_usage_totals": {},
		"upgrade_usage_totals": {},
		"blocked_action_count": 0,
	}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			summary["synthetic_runs"] = int(summary["synthetic_runs"]) + 1
		else:
			summary["normal_runs"] = int(summary["normal_runs"]) + 1
		if str(run.get("status", "")) == "completed":
			summary["completed_runs"] = int(summary["completed_runs"]) + 1
		elif str(run.get("status", "")) == "game_over":
			summary["game_over_runs"] = int(summary["game_over_runs"]) + 1
		elif str(run.get("status", "")) == "failed":
			summary["failed_runs"] = int(summary["failed_runs"]) + 1
		summary["blocked_action_count"] = int(summary["blocked_action_count"]) + run.get("blocked_actions", []).size()
		for tower_type in run.get("tower_usage", {}).keys():
			_increment_count(summary["tower_usage_totals"], str(tower_type), int(run["tower_usage"][tower_type]))
		for tower_type in run.get("upgrade_usage", {}).keys():
			_increment_count(summary["upgrade_usage_totals"], str(tower_type), int(run["upgrade_usage"][tower_type]))
	for issue in issues:
		_increment_count(summary["issue_counts"], str(issue.get("category", "issue")))
		_increment_count(summary["severity_counts"], str(issue.get("severity", "unknown")))
	return summary


func _build_strategy_metrics(runs: Array) -> Dictionary:
	var metrics := {}
	for run in runs:
		var strategy := str(run.get("strategy", "unknown"))
		if not metrics.has(strategy):
			metrics[strategy] = {
				"runs": 0,
				"synthetic_runs": 0,
				"completed_runs": 0,
				"game_over_runs": 0,
				"failed_runs": 0,
				"waves_attempted": 0,
				"waves_completed": 0,
				"spawned": 0,
				"kills": 0,
				"leaks": 0,
				"survival_rate": 0.0,
				"wave_completion_rate": 0.0,
				"leak_rate": 0.0,
			}
		var row: Dictionary = metrics[strategy]
		row["runs"] = int(row["runs"]) + 1
		if bool(run.get("synthetic_stress", false)):
			row["synthetic_runs"] = int(row["synthetic_runs"]) + 1
		var status := str(run.get("status", ""))
		if status == "completed":
			row["completed_runs"] = int(row["completed_runs"]) + 1
		elif status == "game_over":
			row["game_over_runs"] = int(row["game_over_runs"]) + 1
		elif status == "failed":
			row["failed_runs"] = int(row["failed_runs"]) + 1
		for outcome in run.get("wave_outcomes", []):
			row["waves_attempted"] = int(row["waves_attempted"]) + 1
			if str(outcome.get("status", "")) == "complete":
				row["waves_completed"] = int(row["waves_completed"]) + 1
			row["spawned"] = int(row["spawned"]) + int(outcome.get("spawned", 0))
			row["kills"] = int(row["kills"]) + int(outcome.get("kills", 0))
			row["leaks"] = int(row["leaks"]) + int(outcome.get("leaks", 0))
	for strategy in metrics.keys():
		var row: Dictionary = metrics[strategy]
		row["survival_rate"] = _safe_ratio(int(row["completed_runs"]), int(row["runs"]))
		row["wave_completion_rate"] = _safe_ratio(int(row["waves_completed"]), int(row["waves_attempted"]))
		row["leak_rate"] = _safe_ratio(int(row["leaks"]), int(row["spawned"]))
	return metrics


func _build_wave_metrics(runs: Array) -> Dictionary:
	var metrics := {}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		for outcome in run.get("wave_outcomes", []):
			var wave_key := str(outcome.get("wave", 0))
			if not metrics.has(wave_key):
				metrics[wave_key] = {
					"runs": 0,
					"completed": 0,
					"game_over": 0,
					"stalled": 0,
					"spawned": 0,
					"kills": 0,
					"leaks": 0,
					"completion_rate": 0.0,
					"leak_rate": 0.0,
				}
			var row: Dictionary = metrics[wave_key]
			row["runs"] = int(row["runs"]) + 1
			var status := str(outcome.get("status", ""))
			if status == "complete":
				row["completed"] = int(row["completed"]) + 1
			elif status == "game_over":
				row["game_over"] = int(row["game_over"]) + 1
			elif status == "stalled":
				row["stalled"] = int(row["stalled"]) + 1
			row["spawned"] = int(row["spawned"]) + int(outcome.get("spawned", 0))
			row["kills"] = int(row["kills"]) + int(outcome.get("kills", 0))
			row["leaks"] = int(row["leaks"]) + int(outcome.get("leaks", 0))
	for wave_key in metrics.keys():
		var row: Dictionary = metrics[wave_key]
		row["completion_rate"] = _safe_ratio(int(row["completed"]), int(row["runs"]))
		row["leak_rate"] = _safe_ratio(int(row["leaks"]), int(row["spawned"]))
	return metrics


func _build_tower_metrics(runs: Array) -> Dictionary:
	var metrics := {}
	for tower_type in ENABLED_TOWER_TYPES:
		metrics[tower_type] = {
			"placements": 0,
			"upgrades": 0,
			"normal_placements": 0,
			"successful_run_placements": 0,
			"specialist_runs": 0,
			"specialist_completed_runs": 0,
		}
	for run in runs:
		var synthetic := bool(run.get("synthetic_stress", false))
		var completed := str(run.get("status", "")) == "completed"
		if str(run.get("strategy", "")) == "tower_specialist":
			var focus := str(run.get("focus_tower_type", ""))
			if metrics.has(focus):
				metrics[focus]["specialist_runs"] = int(metrics[focus]["specialist_runs"]) + 1
				if completed:
					metrics[focus]["specialist_completed_runs"] = int(metrics[focus]["specialist_completed_runs"]) + 1
		for tower_type in run.get("tower_usage", {}).keys():
			var key := str(tower_type)
			if not metrics.has(key):
				continue
			var count := int(run["tower_usage"][key])
			metrics[key]["placements"] = int(metrics[key]["placements"]) + count
			if not synthetic:
				metrics[key]["normal_placements"] = int(metrics[key]["normal_placements"]) + count
			if completed:
				metrics[key]["successful_run_placements"] = int(metrics[key]["successful_run_placements"]) + count
		for tower_type in run.get("upgrade_usage", {}).keys():
			var key := str(tower_type)
			if metrics.has(key):
				metrics[key]["upgrades"] = int(metrics[key]["upgrades"]) + int(run["upgrade_usage"][key])
	return metrics


func _build_blocked_action_metrics(runs: Array) -> Dictionary:
	var metrics := {
		"total": 0,
		"expected_total": 0,
		"avoidable_total": 0,
		"by_action": {},
		"by_reason": {},
		"expected_by_action": {},
		"avoidable_by_action": {},
	}
	for run in runs:
		for blocked in run.get("blocked_actions", []):
			var expected := bool(blocked.get("expected", false))
			metrics["total"] = int(metrics["total"]) + 1
			if expected:
				metrics["expected_total"] = int(metrics["expected_total"]) + 1
				_increment_count(metrics["expected_by_action"], str(blocked.get("action", "")))
			else:
				metrics["avoidable_total"] = int(metrics["avoidable_total"]) + 1
				_increment_count(metrics["avoidable_by_action"], str(blocked.get("action", "")))
			_increment_count(metrics["by_action"], str(blocked.get("action", "")))
			_increment_count(metrics["by_reason"], str(blocked.get("reason", "")))
	return metrics


func _build_seed_metrics(runs: Array) -> Dictionary:
	var metrics := {}
	for run in runs:
		var seed_key := str(run.get("seed_bucket", 0))
		if not metrics.has(seed_key):
			metrics[seed_key] = {
				"seed_bucket": int(run.get("seed_bucket", 0)),
				"seed_value": int(run.get("seed_value", 0)),
				"runs": 0,
				"completed_runs": 0,
				"game_over_runs": 0,
				"failed_runs": 0,
				"waves_attempted": 0,
				"waves_completed": 0,
				"spawned": 0,
				"kills": 0,
				"leaks": 0,
				"blocked_actions": 0,
				"survival_rate": 0.0,
				"wave_completion_rate": 0.0,
				"leak_rate": 0.0,
			}
		var row: Dictionary = metrics[seed_key]
		row["runs"] = int(row["runs"]) + 1
		var status := str(run.get("status", ""))
		if status == "completed":
			row["completed_runs"] = int(row["completed_runs"]) + 1
		elif status == "game_over":
			row["game_over_runs"] = int(row["game_over_runs"]) + 1
		elif status == "failed":
			row["failed_runs"] = int(row["failed_runs"]) + 1
		row["blocked_actions"] = int(row["blocked_actions"]) + run.get("blocked_actions", []).size()
		for outcome in run.get("wave_outcomes", []):
			row["waves_attempted"] = int(row["waves_attempted"]) + 1
			if str(outcome.get("status", "")) == "complete":
				row["waves_completed"] = int(row["waves_completed"]) + 1
			row["spawned"] = int(row["spawned"]) + int(outcome.get("spawned", 0))
			row["kills"] = int(row["kills"]) + int(outcome.get("kills", 0))
			row["leaks"] = int(row["leaks"]) + int(outcome.get("leaks", 0))
	for seed_key in metrics.keys():
		var row: Dictionary = metrics[seed_key]
		row["survival_rate"] = _safe_ratio(int(row["completed_runs"]), int(row["runs"]))
		row["wave_completion_rate"] = _safe_ratio(int(row["waves_completed"]), int(row["waves_attempted"]))
		row["leak_rate"] = _safe_ratio(int(row["leaks"]), int(row["spawned"]))
	return metrics


func _build_economy_metrics(runs: Array) -> Dictionary:
	var metrics := {"by_wave": {}, "by_strategy": {}}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		var strategy := str(run.get("strategy", "unknown"))
		for outcome in run.get("wave_outcomes", []):
			_accumulate_economy_row(metrics["by_wave"], str(outcome.get("wave", 0)), outcome)
			_accumulate_economy_row(metrics["by_strategy"], strategy, outcome)
	for group in ["by_wave", "by_strategy"]:
		for key in metrics[group].keys():
			_finalize_economy_row(metrics[group][key])
	return metrics


func _accumulate_economy_row(target: Dictionary, key: String, outcome: Dictionary) -> void:
	if not target.has(key):
		target[key] = {
			"runs": 0,
			"money_delta_total": 0,
			"research_delta_total": 0,
			"lives_delta_total": 0,
			"tower_count_delta_total": 0,
			"spend_delta_total": 0,
			"avg_money_delta": 0.0,
			"avg_research_delta": 0.0,
			"avg_lives_delta": 0.0,
			"avg_tower_count_delta": 0.0,
			"avg_spend_delta": 0.0,
		}
	var row: Dictionary = target[key]
	row["runs"] = int(row["runs"]) + 1
	row["money_delta_total"] = int(row["money_delta_total"]) + int(outcome.get("money_delta", 0))
	row["research_delta_total"] = int(row["research_delta_total"]) + int(outcome.get("research_delta", 0))
	row["lives_delta_total"] = int(row["lives_delta_total"]) + int(outcome.get("lives_delta", 0))
	row["tower_count_delta_total"] = int(row["tower_count_delta_total"]) + int(outcome.get("tower_count_delta", 0))
	row["spend_delta_total"] = int(row["spend_delta_total"]) + int(outcome.get("spend_delta", 0))


func _finalize_economy_row(row: Dictionary) -> void:
	var runs: int = max(1, int(row.get("runs", 0)))
	row["avg_money_delta"] = float(row.get("money_delta_total", 0)) / float(runs)
	row["avg_research_delta"] = float(row.get("research_delta_total", 0)) / float(runs)
	row["avg_lives_delta"] = float(row.get("lives_delta_total", 0)) / float(runs)
	row["avg_tower_count_delta"] = float(row.get("tower_count_delta_total", 0)) / float(runs)
	row["avg_spend_delta"] = float(row.get("spend_delta_total", 0)) / float(runs)


func _build_damage_metrics(runs: Array) -> Dictionary:
	var metrics := {"by_wave": {}, "by_strategy": {}, "by_tower_type": {}}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		var strategy := str(run.get("strategy", "unknown"))
		for outcome in run.get("wave_outcomes", []):
			_accumulate_damage_row(metrics["by_wave"], str(outcome.get("wave", 0)), outcome)
			_accumulate_damage_row(metrics["by_strategy"], strategy, outcome)
			for tower_type in outcome.get("tower_damage_delta", {}).keys():
				_accumulate_tower_damage_row(metrics["by_tower_type"], str(tower_type), float(outcome["tower_damage_delta"][tower_type]))
	for group in ["by_wave", "by_strategy"]:
		for key in metrics[group].keys():
			_finalize_damage_row(metrics[group][key])
	for tower_type in metrics["by_tower_type"].keys():
		var row: Dictionary = metrics["by_tower_type"][tower_type]
		row["avg_damage"] = float(row.get("damage_total", 0.0)) / float(max(1, int(row.get("waves", 0))))
	return metrics


func _accumulate_damage_row(target: Dictionary, key: String, outcome: Dictionary) -> void:
	if not target.has(key):
		target[key] = {
			"waves": 0,
			"spawned": 0,
			"leaks": 0,
			"cycles": 0,
			"damage_total": 0.0,
			"avg_damage": 0.0,
			"damage_per_spawned": 0.0,
			"damage_per_leak": 0.0,
			"rough_dps": 0.0,
		}
	var row: Dictionary = target[key]
	row["waves"] = int(row["waves"]) + 1
	row["spawned"] = int(row["spawned"]) + int(outcome.get("spawned", 0))
	row["leaks"] = int(row["leaks"]) + int(outcome.get("leaks", 0))
	row["cycles"] = int(row["cycles"]) + int(outcome.get("cycles", 0))
	row["damage_total"] = float(row["damage_total"]) + float(outcome.get("damage_delta", 0.0))


func _accumulate_tower_damage_row(target: Dictionary, tower_type: String, damage: float) -> void:
	if not target.has(tower_type):
		target[tower_type] = {"waves": 0, "damage_total": 0.0, "avg_damage": 0.0}
	var row: Dictionary = target[tower_type]
	row["waves"] = int(row["waves"]) + 1
	row["damage_total"] = float(row["damage_total"]) + damage


func _finalize_damage_row(row: Dictionary) -> void:
	var waves: int = max(1, int(row.get("waves", 0)))
	var spawned: int = max(1, int(row.get("spawned", 0)))
	var leaks: int = max(1, int(row.get("leaks", 0)))
	var seconds: float = max(0.001, float(row.get("cycles", 0)) * STEP_DELTA)
	row["avg_damage"] = float(row.get("damage_total", 0.0)) / float(waves)
	row["damage_per_spawned"] = float(row.get("damage_total", 0.0)) / float(spawned)
	row["damage_per_leak"] = float(row.get("damage_total", 0.0)) / float(leaks)
	row["rough_dps"] = float(row.get("damage_total", 0.0)) / seconds


func _build_enemy_kind_metrics(runs: Array) -> Dictionary:
	var metrics := {}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		var seen_in_run := {}
		for outcome in run.get("wave_outcomes", []):
			var key := str(outcome.get("enemy_kind", "unknown"))
			if not metrics.has(key):
				metrics[key] = _new_rate_damage_row()
			var row: Dictionary = metrics[key]
			if not seen_in_run.has(key):
				row["runs"] = int(row["runs"]) + 1
				seen_in_run[key] = true
			_accumulate_rate_damage_outcome(row, outcome)
	for key in metrics.keys():
		_finalize_rate_damage_row(metrics[key])
	return metrics


func _build_boss_commander_metrics(runs: Array) -> Dictionary:
	var metrics := {"summary": _new_special_wave_row(), "by_wave": {}}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		for outcome in run.get("wave_outcomes", []):
			var scheduled_boss := int(outcome.get("scheduled_boss_count", 0))
			var scheduled_commander := int(outcome.get("scheduled_commander_count", 0))
			var spawned_boss := int(outcome.get("spawned_boss_count", 0))
			var spawned_commander := int(outcome.get("spawned_commander_count", 0))
			if scheduled_boss + scheduled_commander + spawned_boss + spawned_commander <= 0:
				continue
			var wave_key := str(outcome.get("wave", 0))
			if not metrics["by_wave"].has(wave_key):
				metrics["by_wave"][wave_key] = _new_special_wave_row()
			_accumulate_special_wave_row(metrics["summary"], outcome)
			_accumulate_special_wave_row(metrics["by_wave"][wave_key], outcome)
	_finalize_special_wave_row(metrics["summary"])
	for wave_key in metrics["by_wave"].keys():
		_finalize_special_wave_row(metrics["by_wave"][wave_key])
	return metrics


func _build_upgrade_branch_metrics(runs: Array) -> Dictionary:
	var metrics := {"by_tower_branch": {}, "available_branches": _available_branch_catalog()}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		for event in run.get("upgrade_events", []):
			var tower_type := str(event.get("tower_type", "unknown"))
			var branch_id := str(event.get("branch_id", "unbranched"))
			if branch_id.is_empty():
				branch_id = "unbranched"
			var key := "%s:%s" % [tower_type, branch_id]
			if not metrics["by_tower_branch"].has(key):
				metrics["by_tower_branch"][key] = {
					"tower_type": tower_type,
					"branch_id": branch_id,
					"attempts": 0,
					"successes": 0,
					"spend": 0,
					"level_gain": 0,
					"damage_after_upgrade": 0.0,
					"kills_after_upgrade": 0,
					"avg_damage_per_spend": 0.0,
				}
			var row: Dictionary = metrics["by_tower_branch"][key]
			row["attempts"] = int(row["attempts"]) + 1
			if bool(event.get("succeeded", false)):
				row["successes"] = int(row["successes"]) + 1
				row["spend"] = int(row["spend"]) + int(event.get("cost", 0))
				row["level_gain"] = int(row["level_gain"]) + int(event.get("level_gain", 0))
				row["damage_after_upgrade"] = float(row["damage_after_upgrade"]) + float(event.get("damage_after_upgrade", 0.0))
				row["kills_after_upgrade"] = int(row["kills_after_upgrade"]) + int(event.get("kills_after_upgrade", 0))
	for key in metrics["by_tower_branch"].keys():
		var row: Dictionary = metrics["by_tower_branch"][key]
		row["avg_damage_per_spend"] = float(row.get("damage_after_upgrade", 0.0)) / float(max(1, int(row.get("spend", 0))))
	return metrics


func _build_target_mode_metrics(runs: Array) -> Dictionary:
	var metrics := {"by_tower_mode": {}}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		var run_completed := str(run.get("status", "")) == "completed"
		for event in run.get("target_mode_events", []):
			var tower_type := str(event.get("tower_type", "unknown"))
			var mode := str(event.get("mode", "unknown"))
			var key := "%s:%s" % [tower_type, mode]
			if not metrics["by_tower_mode"].has(key):
				metrics["by_tower_mode"][key] = {
					"tower_type": tower_type,
					"mode": mode,
					"selections": 0,
					"changed": 0,
					"completed_runs": 0,
					"waves_observed": 0,
					"waves_completed": 0,
					"spawned": 0,
					"leaks": 0,
					"damage": 0.0,
					"survival_rate": 0.0,
					"wave_completion_rate": 0.0,
					"leak_rate": 0.0,
				}
			var row: Dictionary = metrics["by_tower_mode"][key]
			row["selections"] = int(row["selections"]) + 1
			if bool(event.get("changed", false)):
				row["changed"] = int(row["changed"]) + 1
			if run_completed:
				row["completed_runs"] = int(row["completed_runs"]) + 1
			var event_wave := int(event.get("wave", 0))
			for outcome in run.get("wave_outcomes", []):
				if int(outcome.get("wave", 0)) < event_wave:
					continue
				row["waves_observed"] = int(row["waves_observed"]) + 1
				if str(outcome.get("status", "")) == "complete":
					row["waves_completed"] = int(row["waves_completed"]) + 1
				row["spawned"] = int(row["spawned"]) + int(outcome.get("spawned", 0))
				row["leaks"] = int(row["leaks"]) + int(outcome.get("leaks", 0))
				row["damage"] = float(row["damage"]) + float(outcome.get("damage_delta", 0.0))
	for key in metrics["by_tower_mode"].keys():
		var row: Dictionary = metrics["by_tower_mode"][key]
		row["survival_rate"] = _safe_ratio(int(row.get("completed_runs", 0)), int(row.get("selections", 0)))
		row["wave_completion_rate"] = _safe_ratio(int(row.get("waves_completed", 0)), int(row.get("waves_observed", 0)))
		row["leak_rate"] = _safe_ratio(int(row.get("leaks", 0)), int(row.get("spawned", 0)))
	return metrics


func _build_progression_metrics(runs: Array) -> Dictionary:
	var result := {
		"runs": 0,
		"research_earned": 0,
		"ending_research_total": 0,
		"avg_ending_research": 0.0,
		"mastery_xp_total": 0.0,
		"towers_with_mastery_xp": 0,
		"paragon_towers": 0,
		"mutated_towers": 0,
		"reward_card_data": _reward_card_data_summary(),
	}
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		result["runs"] = int(result["runs"]) + 1
		for outcome in run.get("wave_outcomes", []):
			result["research_earned"] = int(result["research_earned"]) + max(0, int(outcome.get("research_delta", 0)))
		var final_state: Dictionary = run.get("compact_run_state", {})
		result["ending_research_total"] = int(result["ending_research_total"]) + int(final_state.get("research_points", 0))
		for tower in final_state.get("towers", []):
			var mastery_xp := float(tower.get("mastery_xp", 0.0))
			result["mastery_xp_total"] = float(result["mastery_xp_total"]) + mastery_xp
			if mastery_xp > 0.0:
				result["towers_with_mastery_xp"] = int(result["towers_with_mastery_xp"]) + 1
			if bool(tower.get("is_paragon", false)):
				result["paragon_towers"] = int(result["paragon_towers"]) + 1
			if tower.get("mutations", []).size() > 0:
				result["mutated_towers"] = int(result["mutated_towers"]) + 1
	result["avg_ending_research"] = float(result.get("ending_research_total", 0)) / float(max(1, int(result.get("runs", 0))))
	return result


func _build_late_wave_metrics(runs: Array) -> Dictionary:
	var metrics := {}
	for bucket in ["1-6", "7-12", "13-20", "21-30", "31+"]:
		metrics[bucket] = _new_rate_damage_row()
	for run in runs:
		if bool(run.get("synthetic_stress", false)):
			continue
		var seen_in_run := {}
		for outcome in run.get("wave_outcomes", []):
			var bucket := _late_wave_bucket(int(outcome.get("wave", 0)))
			var row: Dictionary = metrics[bucket]
			if not seen_in_run.has(bucket):
				row["runs"] = int(row["runs"]) + 1
				seen_in_run[bucket] = true
			_accumulate_rate_damage_outcome(row, outcome)
	for bucket in metrics.keys():
		_finalize_rate_damage_row(metrics[bucket])
	return metrics


func _new_rate_damage_row() -> Dictionary:
	return {
		"runs": 0,
		"waves": 0,
		"waves_completed": 0,
		"game_over": 0,
		"spawned": 0,
		"kills": 0,
		"leaks": 0,
		"cycles": 0,
		"damage": 0.0,
		"completion_rate": 0.0,
		"leak_rate": 0.0,
		"rough_dps": 0.0,
	}


func _accumulate_rate_damage_outcome(row: Dictionary, outcome: Dictionary) -> void:
	row["waves"] = int(row["waves"]) + 1
	if str(outcome.get("status", "")) == "complete":
		row["waves_completed"] = int(row["waves_completed"]) + 1
	elif str(outcome.get("status", "")) == "game_over":
		row["game_over"] = int(row["game_over"]) + 1
	row["spawned"] = int(row["spawned"]) + int(outcome.get("spawned", 0))
	row["kills"] = int(row["kills"]) + int(outcome.get("kills", 0))
	row["leaks"] = int(row["leaks"]) + int(outcome.get("leaks", 0))
	row["cycles"] = int(row["cycles"]) + int(outcome.get("cycles", 0))
	row["damage"] = float(row["damage"]) + float(outcome.get("damage_delta", 0.0))


func _finalize_rate_damage_row(row: Dictionary) -> void:
	row["completion_rate"] = _safe_ratio(int(row.get("waves_completed", 0)), int(row.get("waves", 0)))
	row["leak_rate"] = _safe_ratio(int(row.get("leaks", 0)), int(row.get("spawned", 0)))
	row["rough_dps"] = float(row.get("damage", 0.0)) / max(0.001, float(row.get("cycles", 0)) * STEP_DELTA)


func _new_special_wave_row() -> Dictionary:
	return {
		"waves": 0,
		"completed": 0,
		"game_over": 0,
		"scheduled_boss": 0,
		"scheduled_commander": 0,
		"spawned_boss": 0,
		"spawned_commander": 0,
		"spawned": 0,
		"leaks": 0,
		"damage": 0.0,
		"completion_rate": 0.0,
		"leak_rate": 0.0,
	}


func _accumulate_special_wave_row(row: Dictionary, outcome: Dictionary) -> void:
	row["waves"] = int(row["waves"]) + 1
	if str(outcome.get("status", "")) == "complete":
		row["completed"] = int(row["completed"]) + 1
	elif str(outcome.get("status", "")) == "game_over":
		row["game_over"] = int(row["game_over"]) + 1
	row["scheduled_boss"] = int(row["scheduled_boss"]) + int(outcome.get("scheduled_boss_count", 0))
	row["scheduled_commander"] = int(row["scheduled_commander"]) + int(outcome.get("scheduled_commander_count", 0))
	row["spawned_boss"] = int(row["spawned_boss"]) + int(outcome.get("spawned_boss_count", 0))
	row["spawned_commander"] = int(row["spawned_commander"]) + int(outcome.get("spawned_commander_count", 0))
	row["spawned"] = int(row["spawned"]) + int(outcome.get("spawned", 0))
	row["leaks"] = int(row["leaks"]) + int(outcome.get("leaks", 0))
	row["damage"] = float(row["damage"]) + float(outcome.get("damage_delta", 0.0))


func _finalize_special_wave_row(row: Dictionary) -> void:
	row["completion_rate"] = _safe_ratio(int(row.get("completed", 0)), int(row.get("waves", 0)))
	row["leak_rate"] = _safe_ratio(int(row.get("leaks", 0)), int(row.get("spawned", 0)))


func _late_wave_bucket(wave: int) -> String:
	if wave <= 6:
		return "1-6"
	if wave <= 12:
		return "7-12"
	if wave <= 20:
		return "13-20"
	if wave <= 30:
		return "21-30"
	return "31+"


func _available_branch_catalog() -> Dictionary:
	var result := {}
	var branch_defs: Dictionary = _game_data.get("towers", {}).get("branch_definitions", {})
	for tower_type in ENABLED_TOWER_TYPES:
		var tower_branches: Variant = branch_defs.get(tower_type, {})
		if tower_branches is Dictionary:
			result[tower_type] = _sorted_string_keys(tower_branches)
	return result


func _reward_card_data_summary() -> Dictionary:
	var progression: Dictionary = _game_data.get("progression", {})
	var card_pool: Dictionary = progression.get("card_pool", {})
	return {
		"available": not card_pool.is_empty(),
		"card_count": card_pool.size(),
		"max_choices": int(progression.get("max_reward_card_choices", 0)),
		"categories": progression.get("reward_card_categories", {}).duplicate(true),
		"runtime_exercised": false,
	}


func _empty_scenario_probe_report(mode: String, reason: String = "") -> Dictionary:
	return {
		"mode": mode,
		"enabled": false,
		"reason": reason,
		"summary": {
			"total": 0,
			"passed": 0,
			"failed": 0,
			"diagnostic": 0,
			"stalled": 0,
		},
		"tower_family_probes": [],
		"branch_probes": [],
		"enemy_kind_probes": [],
		"scheduled_wave_probes": [],
		"issues": [],
	}


func _run_scenario_probes(options: Dictionary) -> Dictionary:
	var mode := _resolve_scenario_probe_mode(options)
	if mode == "off":
		return _empty_scenario_probe_report(mode, "disabled")
	var report := _empty_scenario_probe_report(mode)
	report["enabled"] = true
	report["reason"] = ""
	report["tower_family_probes"] = _run_tower_family_probes(mode)
	report["branch_probes"] = _run_branch_probes(mode)
	report["enemy_kind_probes"] = _run_enemy_kind_probes(mode)
	report["scheduled_wave_probes"] = _run_scheduled_wave_probes(mode)
	report["issues"] = _scenario_issues_from_report(report)
	report["summary"] = _scenario_summary(report)
	return report


func _scenario_summary(report: Dictionary) -> Dictionary:
	var summary := {
		"total": 0,
		"passed": 0,
		"failed": 0,
		"diagnostic": 0,
		"stalled": 0,
	}
	for group in ["tower_family_probes", "branch_probes", "enemy_kind_probes", "scheduled_wave_probes"]:
		for probe in report.get(group, []):
			summary["total"] = int(summary["total"]) + 1
			if bool(probe.get("diagnostic_only", false)):
				summary["diagnostic"] = int(summary["diagnostic"]) + 1
			elif bool(probe.get("passed", false)):
				summary["passed"] = int(summary["passed"]) + 1
			else:
				summary["failed"] = int(summary["failed"]) + 1
			if bool(probe.get("stalled", false)):
				summary["stalled"] = int(summary["stalled"]) + 1
	return summary


func _scenario_issues_from_report(report: Dictionary) -> Array:
	var issues: Array = []
	for group in ["tower_family_probes", "branch_probes", "enemy_kind_probes", "scheduled_wave_probes"]:
		for probe in report.get(group, []):
			for failure in probe.get("failures", []):
				var label := str(failure.get("label", "scenario_probe_failed"))
				var severity := str(failure.get("severity", "medium"))
				var message := str(failure.get("message", "Scenario probe failed."))
				var detail: Dictionary = probe.duplicate(true)
				detail.erase("failures")
				detail["failure"] = failure
				issues.append(_batch_issue("scenario", severity, label, message, detail))
	return issues


func _sync_scenario_issue_ids(_scenario_probes: Dictionary, _issues: Array) -> void:
	return


func _run_tower_family_probes(mode: String) -> Array:
	var towers := SCENARIO_SMOKE_TOWERS if mode == "smoke" else ENABLED_TOWER_TYPES
	var probes: Array = []
	for tower_type in towers:
		var game := _create_probe_game()
		var probe := _new_scenario_probe("tower_family", str(tower_type))
		probe["tower_type"] = str(tower_type)
		probe["wave"] = 6
		_prepare_scenario_game(game)
		game.set_wave_for_test(6)
		var built := _scenario_place_towers(game, str(tower_type), 3)
		if built.size() > 0:
			game.selected_tower_index = 0
			_upgrade_selected_with_branch_if_needed(game, probe, {}, false)
		probe["setup"] = {"requested_towers": 3, "placed_towers": built.size(), "sites": built}
		if built.size() < 3:
			_add_probe_failure(probe, "scenario_probe_stalled", "medium", "Scenario probe could not place the required towers.", {"required": 3, "placed": built.size()})
		else:
			var result := _run_started_wave_probe(game, 6)
			_merge_probe_result(probe, result)
			_apply_probe_expectations(probe, 0.35, 0.15)
		_finalize_probe(probe)
		probes.append(probe)
		_teardown_probe_game(game)
	return probes


func _run_branch_probes(mode: String) -> Array:
	var catalog := _available_branch_catalog()
	var tower_types := SCENARIO_SMOKE_TOWERS if mode == "smoke" else ENABLED_TOWER_TYPES
	var probes: Array = []
	for tower_type in tower_types:
		var branches: Array = catalog.get(str(tower_type), [])
		if mode == "smoke" and not branches.is_empty():
			branches = [branches[0]]
		for branch_id in branches:
			var game := _create_probe_game()
			var probe := _new_scenario_probe("branch", "%s:%s" % [str(tower_type), str(branch_id)])
			probe["tower_type"] = str(tower_type)
			probe["branch_id"] = str(branch_id)
			probe["wave"] = 8
			_prepare_scenario_game(game)
			game.set_wave_for_test(8)
			var built := _scenario_place_towers(game, str(tower_type), 1)
			var selected_branch := ""
			var post_branch_upgrade := false
			if built.size() > 0:
				game.selected_tower_index = 0
				_upgrade_selected_with_branch_if_needed(game, probe, {}, false)
				var chose: bool = game.choose_selected_tower_branch(str(branch_id))
				selected_branch = str(branch_id) if chose else ""
				post_branch_upgrade = _upgrade_selected_with_branch_if_needed(game, probe, {}, false)
				var extra := _scenario_place_towers(game, str(tower_type), 2)
				for site in extra:
					built.append(site)
			probe["selected_branch"] = selected_branch
			probe["post_branch_upgrade_succeeded"] = post_branch_upgrade
			probe["setup"] = {"placed_towers": built.size(), "sites": built}
			if selected_branch != str(branch_id) or not post_branch_upgrade:
				_add_probe_failure(probe, "scenario_branch_not_exercised", "medium", "Scenario branch probe did not select and upgrade the requested branch.", {
					"target_branch": str(branch_id),
					"selected_branch": selected_branch,
					"post_branch_upgrade_succeeded": post_branch_upgrade,
				})
			else:
				var result := _run_started_wave_probe(game, 8)
				_merge_probe_result(probe, result)
				_apply_probe_expectations(probe, 0.40, 0.0)
			_finalize_probe(probe)
			probes.append(probe)
			_teardown_probe_game(game)
	return probes


func _run_enemy_kind_probes(mode: String) -> Array:
	var kinds := SCENARIO_SMOKE_ENEMY_KINDS if mode == "smoke" else _sorted_string_keys(_game_data.get("enemies", {}).get("kind_modifiers", {}))
	var probes: Array = []
	for enemy_kind in kinds:
		var game := _create_probe_game()
		var probe := _new_scenario_probe("enemy_kind", str(enemy_kind))
		probe["enemy_kind"] = str(enemy_kind)
		probe["wave"] = 1
		_prepare_scenario_game(game)
		game.set_wave_for_test(1)
		_scenario_place_mixed_defense(game, SCENARIO_MIXED_DEFENSE)
		if str(enemy_kind) == "flying":
			_scenario_set_target_mode_for_tower(game, "tesla", "flying")
		var result := _run_direct_enemy_probe(game, str(enemy_kind), 12)
		_merge_probe_result(probe, result)
		_apply_probe_expectations(probe, 0.35, 0.15)
		_finalize_probe(probe)
		probes.append(probe)
		_teardown_probe_game(game)
	return probes


func _run_scheduled_wave_probes(mode: String) -> Array:
	var waves := SCENARIO_SMOKE_SPECIAL_WAVES if mode == "smoke" else SCENARIO_FULL_SPECIAL_WAVES
	var probes: Array = []
	for wave_number in waves:
		var game := _create_probe_game()
		var probe := _new_scenario_probe("scheduled_wave", "wave_%s" % int(wave_number))
		probe["wave"] = int(wave_number)
		_prepare_scenario_game(game)
		game.set_wave_for_test(int(wave_number))
		_scenario_place_mixed_defense(game, ["archer", "cannon", "sniper", "tesla", "machine_gun"])
		for index in range(min(2, int(game.snapshot().get("tower_count", 0)))):
			game.selected_tower_index = index
			_upgrade_selected_with_branch_if_needed(game, probe, {}, false)
		var result := _run_started_wave_probe(game, int(wave_number))
		_merge_probe_result(probe, result)
		_apply_probe_expectations(probe, 0.50, 0.0)
		var scheduled_special := int(probe.get("scheduled_boss_count", 0)) + int(probe.get("scheduled_commander_count", 0))
		var spawned_special := int(probe.get("spawned_boss_count", 0)) + int(probe.get("spawned_commander_count", 0))
		if scheduled_special > 0 and spawned_special == 0:
			probe["diagnostic_only"] = true
			_add_probe_failure(probe, "scenario_scheduled_special_unspawned", "info", "Scheduled boss or commander pressure is not spawned by the current vertical slice.", {
				"scheduled_special": scheduled_special,
				"spawned_special": spawned_special,
			})
		_finalize_probe(probe)
		probes.append(probe)
		_teardown_probe_game(game)
	return probes


func _create_probe_game() -> Node:
	var slice_script := load("res://scripts/game/vertical_slice_game.gd")
	var game: Node = slice_script.new()
	root.add_child(game)
	game.name = "ScenarioProbeGame"
	game.reset_slice()
	return game


func _teardown_probe_game(game: Node) -> void:
	if game != null:
		game.queue_free()


func _prepare_scenario_game(game: Node) -> void:
	game.reset_slice()
	game.money = SCENARIO_SETUP_MONEY
	game.lives = SCENARIO_SETUP_LIVES
	game.set_game_speed(4.0)


func _new_scenario_probe(kind: String, probe_id: String) -> Dictionary:
	return {
		"id": probe_id,
		"kind": kind,
		"passed": false,
		"diagnostic_only": false,
		"stalled": false,
		"failures": [],
		"action_counts": {},
		"blocked_actions": [],
		"upgrade_events": [],
		"upgrade_usage": {},
	}


func _scenario_place_mixed_defense(game: Node, tower_types: Array) -> Array:
	var sites: Array = []
	for tower_type in tower_types:
		var placed := _scenario_place_towers(game, str(tower_type), 1)
		for site in placed:
			sites.append(site)
	return sites


func _scenario_place_towers(game: Node, tower_type: String, count: int) -> Array:
	var placed: Array = []
	for _index in range(count):
		var site := _scenario_next_build_site(game, tower_type)
		if site == Vector2.INF:
			break
		if game.place_selected_tower(site, tower_type):
			placed.append([site.x, site.y])
	return placed


func _scenario_set_target_mode_for_tower(game: Node, tower_type: String, target_mode: String) -> void:
	var towers: Array = game.serialize_run_state().get("towers", [])
	for index in range(towers.size()):
		if str(towers[index].get("type", "")) == tower_type:
			game.set_tower_target_mode(index, target_mode)


func _scenario_next_build_site(game: Node, tower_type: String) -> Vector2:
	var candidates: Array = []
	for y in range(108, 568, 27):
		for x in range(54, 838, 27):
			var site := Vector2(float(x), float(y))
			var preview: Dictionary = game.placement_preview_snapshot(site, tower_type)
			if not bool(preview.get("can_place", false)):
				continue
			candidates.append({
				"site": site,
				"score": _build_site_score(game, site, "mixed"),
				"x": x,
				"y": y,
			})
	if candidates.is_empty():
		return Vector2.INF
	candidates.sort_custom(func(a, b):
		var score_delta := float(b["score"]) - float(a["score"])
		if abs(score_delta) > 0.0001:
			return float(a["score"]) > float(b["score"])
		if int(a["x"]) != int(b["x"]):
			return int(a["x"]) < int(b["x"])
		return int(a["y"]) < int(b["y"])
	)
	return candidates[0]["site"]


func _run_started_wave_probe(game: Node, wave_number: int) -> Dictionary:
	var before_totals := _tower_totals_by_type(game)
	var started: bool = game.start_wave()
	if not started:
		return {
			"stalled": true,
			"completed": false,
			"game_over": false,
			"failures": [{
				"label": "scenario_probe_stalled",
				"severity": "medium",
				"message": "Scenario probe could not start the configured wave.",
				"detail": game.wave_control_snapshot(),
			}],
		}
	return _simulate_probe_resolution(game, wave_number, before_totals, false, 0)


func _run_direct_enemy_probe(game: Node, enemy_kind: String, count: int) -> Dictionary:
	var before_totals := _tower_totals_by_type(game)
	for _index in range(count):
		game.enemies.append(game.create_enemy(enemy_kind, 1))
	return _simulate_probe_resolution(game, 1, before_totals, true, count)


func _simulate_probe_resolution(game: Node, wave_number: int, before_totals: Dictionary, direct_enemy_probe: bool, direct_spawned: int) -> Dictionary:
	var spawn_limit: int = direct_spawned if direct_enemy_probe else int(game.snapshot().get("spawn_limit", 0))
	var max_cycles: int = min(SCENARIO_MAX_CYCLES_CAP, max(360, spawn_limit * 40 + wave_number * 35))
	var invariant_failures: Array = []
	var cycles_elapsed := max_cycles
	var completed := false
	var game_over := false
	for cycle in range(max_cycles):
		cycles_elapsed = cycle + 1
		game.set_game_speed(4.0)
		game._process_scaled_delta(STEP_DELTA)
		if cycle % 20 == 0 and game.has_method("runtime_invariant_failures"):
			for failure in game.runtime_invariant_failures():
				if not invariant_failures.has(str(failure)):
					invariant_failures.append(str(failure))
		var snapshot: Dictionary = game.snapshot()
		game_over = bool(snapshot.get("game_over", false))
		if game_over:
			break
		if direct_enemy_probe:
			if int(snapshot.get("enemy_count", 0)) == 0 and int(snapshot.get("projectile_count", 0)) == 0:
				completed = true
				break
		elif bool(snapshot.get("wave_complete", false)):
			completed = true
			break
	var final_snapshot: Dictionary = game.snapshot()
	var after_totals: Dictionary = _tower_totals_by_type(game)
	var spawned: int = direct_spawned if direct_enemy_probe else int(final_snapshot.get("spawned_total_this_wave", final_snapshot.get("spawned_this_wave", 0)))
	var leaks: int = int(final_snapshot.get("leaks", 0))
	var damage_delta: float = max(0.0, float(after_totals.get("total_damage", 0.0)) - float(before_totals.get("total_damage", 0.0)))
	var spend_delta: int = int(after_totals.get("money_spent", 0))
	var result: Dictionary = {
		"completed": completed,
		"game_over": game_over,
		"stalled": not completed and not game_over,
		"cycles_to_resolution": cycles_elapsed,
		"max_cycles": max_cycles,
		"spawned": spawned,
		"kills": int(final_snapshot.get("kills", 0)),
		"leaks": leaks,
		"leak_rate": _safe_ratio(leaks, spawned),
		"damage_delta": damage_delta,
		"spend_delta": spend_delta,
		"damage_per_spend": damage_delta / float(max(1, spend_delta)),
		"runtime_invariant_failures": invariant_failures,
		"scheduled_boss_count": int(_wave_schedule_row(wave_number).get("boss_count", 0)),
		"scheduled_commander_count": int(_wave_schedule_row(wave_number).get("commander_count", 0)),
		"spawned_boss_count": 0,
		"spawned_commander_count": 0,
		"final_snapshot": _trim_snapshot(final_snapshot),
		"failures": [],
	}
	if not invariant_failures.is_empty():
		result["failures"].append({
			"label": "scenario_probe_stalled",
			"severity": "high",
			"message": "Scenario probe hit runtime invariant failures.",
			"detail": invariant_failures,
		})
	return result


func _merge_probe_result(probe: Dictionary, result: Dictionary) -> void:
	for key in result.keys():
		if key == "failures":
			for failure in result.get("failures", []):
				probe["failures"].append(failure)
		else:
			probe[key] = result[key]


func _apply_probe_expectations(probe: Dictionary, max_leak_rate: float, min_damage_per_spend: float) -> void:
	if bool(probe.get("stalled", false)):
		_add_probe_failure(probe, "scenario_probe_stalled", "medium", "Scenario probe did not resolve within its bounded cycle budget.", {
			"cycles_to_resolution": int(probe.get("cycles_to_resolution", 0)),
			"max_cycles": int(probe.get("max_cycles", 0)),
		})
	if float(probe.get("leak_rate", 0.0)) > max_leak_rate:
		_add_probe_failure(probe, "scenario_leak_rate_out_of_range", "medium", "Scenario probe leak rate exceeded its conservative v1 range.", {
			"leak_rate": float(probe.get("leak_rate", 0.0)),
			"max_leak_rate": max_leak_rate,
		})
	if int(probe.get("cycles_to_resolution", 0)) <= 0 or int(probe.get("cycles_to_resolution", 0)) > int(probe.get("max_cycles", 0)):
		_add_probe_failure(probe, "scenario_kill_time_out_of_range", "medium", "Scenario probe kill time was outside its bounded range.", {
			"cycles_to_resolution": int(probe.get("cycles_to_resolution", 0)),
			"max_cycles": int(probe.get("max_cycles", 0)),
		})
	if min_damage_per_spend > 0.0 and float(probe.get("damage_per_spend", 0.0)) < min_damage_per_spend:
		_add_probe_failure(probe, "scenario_spend_efficiency_out_of_range", "medium", "Scenario probe damage per spend was below its conservative v1 floor.", {
			"damage_per_spend": float(probe.get("damage_per_spend", 0.0)),
			"min_damage_per_spend": min_damage_per_spend,
		})


func _add_probe_failure(probe: Dictionary, label: String, severity: String, message: String, detail: Dictionary) -> void:
	probe["failures"].append({
		"label": label,
		"severity": severity,
		"message": message,
		"detail": detail,
	})
	if label == "scenario_probe_stalled":
		probe["stalled"] = true


func _finalize_probe(probe: Dictionary) -> void:
	var hard_failures := 0
	for failure in probe.get("failures", []):
		if str(failure.get("severity", "")) != "info":
			hard_failures += 1
	probe["passed"] = hard_failures == 0


func _build_telemetry_coverage() -> Dictionary:
	return {
		"implemented": {
			"enabled_towers": ENABLED_TOWER_TYPES.duplicate(),
			"wave_outcomes": "spawn, kill, leak, economy, damage, and completion metrics are collected from current runtime snapshots.",
			"enemy_kinds": "scheduled enemy kind metrics are collected for waves reached by the simulation.",
			"upgrades": "upgrade attempts, branch id, cost, level gain, and post-upgrade value signals are collected from current tower APIs.",
			"target_modes": "target mode selections and downstream wave outcomes are collected from current targeting APIs.",
			"persistence_probe": "wave-resolution checks still probe serialize/restore behavior.",
		},
		"partial": {
			"boss_commander": "canonical schedule counts are recorded, but current wave runtime does not spawn dedicated boss/commander units.",
			"progression": "research and mastery XP fields are recorded; reward-card data is cataloged but not exercised by runtime choices.",
			"mastery_mutation_paragon": "serialized fields are measured for presence, but full systems remain unported.",
		},
		"unsupported": {
			"shop_towers": UNSUPPORTED_TOWER_TYPES.duplicate(),
		},
		"unported": [
			"full reward-card choices",
			"mutation mechanics",
			"mastery upgrade mechanics",
			"paragon mechanics",
			"dedicated boss and commander combat rules",
		],
	}


func _load_previous_latest_report(output_dir: String) -> Dictionary:
	for candidate in [
		_latest_timestamped_report_json(output_dir),
		_join_path(output_dir, "ai_simulation_latest.json"),
		_join_path(_join_path(output_dir, "latest"), "ai_simulation_latest.json"),
	]:
		if str(candidate).is_empty() or not FileAccess.file_exists(str(candidate)):
			continue
		var parsed := _load_json_dictionary(str(candidate))
		if not parsed.is_empty():
			return parsed
	return {}


func _latest_timestamped_report_json(output_dir: String) -> String:
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return ""
	var latest_name := ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.begins_with("ai_simulation_data_") and file_name.ends_with(".json"):
			if latest_name.is_empty() or file_name > latest_name:
				latest_name = file_name
		file_name = dir.get_next()
	dir.list_dir_end()
	return "" if latest_name.is_empty() else _join_path(output_dir, latest_name)


func _load_json_dictionary(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _build_regression(current: Dictionary, previous: Dictionary) -> Dictionary:
	var result := {
		"enabled": true,
		"comparable": false,
		"reason": "",
		"previous_label": "",
		"current_label": str(current.get("config", {}).get("report_label", "")),
		"deltas": {},
		"warnings": [],
	}
	if previous.is_empty():
		result["reason"] = "No previous latest report was available."
		return result
	var current_config: Dictionary = current.get("config", {})
	var previous_config: Dictionary = previous.get("config", {})
	result["previous_label"] = str(previous_config.get("report_label", ""))
	if int(previous.get("schema_version", 0)) != SCHEMA_VERSION:
		result["reason"] = "schema migration: establish a new schema 6 baseline."
		return result
	for key in ["profile", "evidence_tier", "strategy_group"]:
		if str(previous_config.get(key, "")) != str(current_config.get(key, "")):
			result["reason"] = "same family, not comparable: previous report has different %s." % key
			return result
	for key in ["runs", "max_waves", "seed", "seed_count", "seed_step"]:
		if int(previous_config.get(key, 0)) != int(current_config.get(key, 0)):
			result["reason"] = "same family, not comparable: previous report has different %s." % key
			return result
	if bool(previous_config.get("full_action_log", false)) != bool(current_config.get("full_action_log", false)):
		result["reason"] = "same family, not comparable: previous report has different full_action_log."
		return result
	if not _arrays_equal(previous_config.get("strategies", []), current_config.get("strategies", [])):
		result["reason"] = "same family, not comparable: previous report has different strategies."
		return result
	result["comparable"] = true
	result["reason"] = "Compared against previous latest report."
	var current_summary: Dictionary = current.get("summary", {})
	var previous_summary: Dictionary = previous.get("summary", {})
	var current_strategy: Dictionary = _aggregate_rate_metrics(current.get("strategy_metrics", {}))
	var previous_strategy: Dictionary = _aggregate_rate_metrics(previous.get("strategy_metrics", {}))
	var current_blocked_per_run := _safe_ratio(int(current.get("blocked_action_metrics", {}).get("total", 0)), int(current_summary.get("total_runs", 0)))
	var previous_blocked_per_run := _safe_ratio(int(previous.get("blocked_action_metrics", {}).get("total", 0)), int(previous_summary.get("total_runs", 0)))
	var current_high := int(current_summary.get("severity_counts", {}).get("high", 0))
	var previous_high := int(previous_summary.get("severity_counts", {}).get("high", 0))
	result["deltas"] = {
		"survival_rate": float(current_strategy.get("survival_rate", 0.0)) - float(previous_strategy.get("survival_rate", 0.0)),
		"wave_completion_rate": float(current_strategy.get("wave_completion_rate", 0.0)) - float(previous_strategy.get("wave_completion_rate", 0.0)),
		"leak_rate": float(current_strategy.get("leak_rate", 0.0)) - float(previous_strategy.get("leak_rate", 0.0)),
		"failed_runs": int(current_summary.get("failed_runs", 0)) - int(previous_summary.get("failed_runs", 0)),
		"blocked_actions_per_run": current_blocked_per_run - previous_blocked_per_run,
		"high_severity_issues": current_high - previous_high,
	}
	if float(result["deltas"].get("survival_rate", 0.0)) < -0.05:
		result["warnings"].append("Survival rate dropped by more than 5 percentage points.")
	if float(result["deltas"].get("leak_rate", 0.0)) > 0.05:
		result["warnings"].append("Leak rate rose by more than 5 percentage points.")
	if int(result["deltas"].get("failed_runs", 0)) > 0:
		result["warnings"].append("Failed run count increased.")
	if int(result["deltas"].get("high_severity_issues", 0)) > 0:
		result["warnings"].append("High-severity issue count increased.")
	return result


func _aggregate_rate_metrics(strategy_metrics: Dictionary) -> Dictionary:
	var totals := {"runs": 0, "completed": 0, "waves_attempted": 0, "waves_completed": 0, "spawned": 0, "leaks": 0}
	for strategy in strategy_metrics.keys():
		var row: Dictionary = strategy_metrics[strategy]
		if int(row.get("synthetic_runs", 0)) >= int(row.get("runs", 0)):
			continue
		totals["runs"] = int(totals["runs"]) + int(row.get("runs", 0))
		totals["completed"] = int(totals["completed"]) + int(row.get("completed_runs", 0))
		totals["waves_attempted"] = int(totals["waves_attempted"]) + int(row.get("waves_attempted", 0))
		totals["waves_completed"] = int(totals["waves_completed"]) + int(row.get("waves_completed", 0))
		totals["spawned"] = int(totals["spawned"]) + int(row.get("spawned", 0))
		totals["leaks"] = int(totals["leaks"]) + int(row.get("leaks", 0))
	return {
		"survival_rate": _safe_ratio(int(totals["completed"]), int(totals["runs"])),
		"wave_completion_rate": _safe_ratio(int(totals["waves_completed"]), int(totals["waves_attempted"])),
		"leak_rate": _safe_ratio(int(totals["leaks"]), int(totals["spawned"])),
	}


func _safe_ratio(numerator: int, denominator: int) -> float:
	if denominator <= 0:
		return 0.0
	return float(numerator) / float(denominator)


func _build_recommendations(summary: Dictionary, issues: Array) -> Dictionary:
	var recommendations := {
		"gameplay": [],
		"ui_qol": [],
		"balance": [],
		"validation": [],
	}
	if int(summary.get("issue_counts", {}).get("bug", 0)) > 0:
		recommendations["gameplay"].append("Fix high-severity simulation bugs first, especially stalls, impossible state values, and unresolved wave states.")
	else:
		recommendations["gameplay"].append("No simulation-blocking gameplay bugs were detected in this batch; treat findings as bot diagnostics until blocked-action noise is acceptably low.")
	if int(summary.get("issue_counts", {}).get("qol", 0)) > 0:
		recommendations["ui_qol"].append("Review blocked-action clusters and make disabled starts, invalid placements, and unaffordable upgrades clearer.")
	else:
		recommendations["ui_qol"].append("No repeated QoL blockers were detected beyond expected vertical-slice limits.")
	if int(summary.get("issue_counts", {}).get("balance", 0)) > 0:
		recommendations["balance"].append("Compare tower usage, leak rates, and specialist outcomes as diagnostic signals; verify bot quality before changing costs or damage.")
	else:
		recommendations["balance"].append("Run deep or overnight diagnostics after bot-quality checks before making balance changes; medium samples are intentionally moderate.")
	if int(summary.get("issue_counts", {}).get("validation", 0)) > 0:
		recommendations["validation"].append("Fix canonical data validation or balance sanity failures before trusting bot balance outliers.")
	recommendations["validation"].append("Keep this runner additive to focused validations; it should report findings without failing the build for gameplay balance issues.")
	if _has_label(issues, "boss_commander_rules_unported"):
		recommendations["validation"].append("Promote boss and commander behavior from known_gap to bug checks once those systems are ported.")
	return recommendations


func _has_label(issues: Array, label: String) -> bool:
	for issue in issues:
		if str(issue.get("label", "")) == label:
			return true
	return false


func _write_reports(report: Dictionary, output_dir: String) -> Dictionary:
	var errors: Array = []
	var archive_dir := _join_path(output_dir, "archive")
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if dir_error != OK:
		return {"ok": false, "errors": ["Could not create AI simulation output directory %s: %s" % [output_dir, dir_error]]}
	var archive_dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(archive_dir))
	if archive_dir_error != OK:
		return {"ok": false, "errors": ["Could not create archive output directory %s: %s" % [archive_dir, archive_dir_error]]}

	var timestamp := _timestamp()
	var output_paths := _timestamped_output_paths(output_dir, timestamp)
	var latest_json := str(output_paths["json"])
	var latest_md := str(output_paths["markdown"])
	var latest_prompt := str(output_paths["prompt"])
	var legacy_result := _archive_legacy_root_outputs(output_dir, archive_dir)
	for error in legacy_result.get("errors", []):
		errors.append(error)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var json_text := JSON.stringify(report, "\t")
	var markdown_text := _render_markdown(report)
	var prompt_text := _render_codex_prompt(report, latest_json, latest_md)
	for target in [
		{"path": latest_json, "text": json_text},
		{"path": latest_md, "text": markdown_text},
		{"path": latest_prompt, "text": prompt_text},
	]:
		var write_error := _write_text(str(target["path"]), str(target["text"]))
		if not write_error.is_empty():
			errors.append(write_error)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {
		"ok": true,
		"json_path": latest_json,
		"markdown_path": latest_md,
		"prompt_path": latest_prompt,
		"visible_prompt_path": latest_prompt,
		"archived_previous_count": 0,
		"archived_legacy_count": int(legacy_result.get("paths", []).size()),
	}


func _timestamped_output_paths(output_dir: String, timestamp: String) -> Dictionary:
	var suffix := timestamp
	var collision_index := 2
	while true:
		var paths := {
			"json": _join_path(output_dir, "ai_simulation_data_%s.json" % suffix),
			"markdown": _join_path(output_dir, "ai_simulation_report_%s.md" % suffix),
			"prompt": _join_path(output_dir, "ai_simulation_codex_prompt_%s.md" % suffix),
		}
		if not FileAccess.file_exists(str(paths["json"])) and not FileAccess.file_exists(str(paths["markdown"])) and not FileAccess.file_exists(str(paths["prompt"])):
			return paths
		suffix = "%s_%s" % [timestamp, collision_index]
		collision_index += 1
	return {}


func _write_text(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not open %s for writing: %s" % [path, FileAccess.get_open_error()]
	file.store_string(text)
	file.close()
	return ""


func _archive_previous_latest(latest_json: String, latest_md: String, latest_prompt: String, archive_dir: String, timestamp: String) -> Dictionary:
	var result := {"errors": [], "paths": []}
	var targets := [
		{"source": latest_json, "suffix": ".json"},
		{"source": latest_md, "suffix": ".md"},
		{"source": latest_prompt, "suffix": "_codex_prompt.md"},
	]
	var has_latest := false
	for target in targets:
		if FileAccess.file_exists(str(target["source"])):
			has_latest = true
			break
	if not has_latest:
		return result

	var config := _load_report_config(latest_json)
	var archive_stem := _archive_file_stem_from_config(config, timestamp)
	for target in targets:
		var source := str(target["source"])
		if not FileAccess.file_exists(source):
			continue
		var archive_path := _unique_archive_path(_join_path(archive_dir, "%s%s" % [archive_stem, str(target["suffix"])]))
		var error := _move_file(source, archive_path)
		if error.is_empty():
			result["paths"].append(archive_path)
		else:
			result["errors"].append(error)
	return result


func _archive_legacy_root_outputs(output_dir: String, archive_dir: String) -> Dictionary:
	var result := {"errors": [], "paths": []}
	var timestamp := _timestamp()
	var root_latest_json := _join_path(output_dir, "ai_simulation_latest.json")
	var root_latest_md := _join_path(output_dir, "ai_simulation_latest.md")
	var root_latest_prompt := _join_path(output_dir, "ai_simulation_latest_codex_prompt.md")
	var root_latest_result := _archive_previous_latest(root_latest_json, root_latest_md, root_latest_prompt, archive_dir, timestamp)
	for path in root_latest_result.get("paths", []):
		result["paths"].append(path)
	for error in root_latest_result.get("errors", []):
		result["errors"].append(error)

	var dir := DirAccess.open(output_dir)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and _is_legacy_root_output_name(file_name):
			var source := _join_path(output_dir, file_name)
			if FileAccess.file_exists(source):
				var archive_path := _unique_archive_path(_join_path(archive_dir, file_name))
				var error := _move_file(source, archive_path)
				if error.is_empty():
					result["paths"].append(archive_path)
				else:
					result["errors"].append(error)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


func _is_legacy_root_output_name(file_name: String) -> bool:
	return file_name in [
		"ai_simulation_latest.json",
		"ai_simulation_latest.md",
		"ai_simulation_latest_codex_prompt.md",
	]


func _move_file(source: String, target: String) -> String:
	var move_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target))
	if move_error != OK:
		return "Could not move %s to %s: %s" % [source, target, move_error]
	return ""


func _unique_archive_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var extension_index := path.rfind(".")
	var base := path
	var extension := ""
	if extension_index >= 0:
		base = path.substr(0, extension_index)
		extension = path.substr(extension_index)
	var index := 2
	var candidate := "%s_%s%s" % [base, index, extension]
	while FileAccess.file_exists(candidate):
		index += 1
		candidate = "%s_%s%s" % [base, index, extension]
	return candidate


func _load_report_config(json_path: String) -> Dictionary:
	if not FileAccess.file_exists(json_path):
		return {}
	var text := FileAccess.get_file_as_string(json_path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var report: Dictionary = parsed
	var config = report.get("config", {})
	return config if typeof(config) == TYPE_DICTIONARY else {}


func _render_markdown(report: Dictionary) -> String:
	var config: Dictionary = report.get("config", {})
	var preflight: Dictionary = report.get("preflight", {})
	var summary: Dictionary = report.get("summary", {})
	var issues: Array = report.get("issues", [])
	var recommendations: Dictionary = report.get("recommendations", {})
	var lines: Array = []
	lines.append("# AI Simulation Batch Report")
	lines.append("")
	if not str(config.get("report_label", "")).is_empty():
		lines.append("- Label: `%s`" % str(config.get("report_label", "")))
	lines.append("## Run configuration")
	lines.append("- Profile: `%s`" % str(config.get("profile", "")))
	lines.append("- Evidence tier: `%s`" % str(config.get("evidence_tier", "")))
	lines.append("- Profile overridden: `%s`" % ("yes" if bool(config.get("profile_overridden", false)) else "no"))
	lines.append("- Balance actionable: `%s`" % ("yes" if bool(config.get("balance_actionable", false)) else "no"))
	lines.append("- Coverage scope: `%s`" % str(config.get("coverage_scope", "")))
	lines.append("- Scope note: this report exercises direct vertical-slice APIs, not `scenes/main.tscn`, full UI wiring, audio, or manual input behavior.")
	lines.append("- Profile defaults: %s" % _profile_defaults_inline(config.get("profile_defaults", {})))
	lines.append("- Runs: `%s`" % int(config.get("runs", 0)))
	lines.append("- Max waves: `%s`" % int(config.get("max_waves", 0)))
	lines.append("- Seed: `%s`" % int(config.get("seed", 0)))
	lines.append("- Seed count / step: `%s` / `%s`" % [int(config.get("seed_count", 1)), int(config.get("seed_step", 0))])
	lines.append("- Strategy group: `%s`" % str(config.get("strategy_group", "")))
	lines.append("- Output dir: `%s`" % str(config.get("output_dir", "")))
	lines.append("- Strategies: `%s`" % _join_strings(config.get("strategies", []), "`, `"))
	lines.append("- Completed/game over/failed: `%s` / `%s` / `%s`" % [int(summary.get("completed_runs", 0)), int(summary.get("game_over_runs", 0)), int(summary.get("failed_runs", 0))])
	lines.append("- Diagnostic note: audit and verify this report against current code before making changes.")
	lines.append("- %s" % SCHEMA_BASELINE_TEXT)
	if str(config.get("evidence_tier", "")) == "smoke":
		lines.append("- Warning: This is smoke/custom diagnostic evidence and is not balance-actionable.")
	for warning in report.get("evidence_warnings", []):
		lines.append("- Evidence warning: %s" % str(warning))
	lines.append("")
	lines.append("## Canonical preflight")
	_append_preflight_lines(lines, preflight)
	lines.append("")
	lines.append("## Telemetry coverage")
	_append_telemetry_coverage(lines, report.get("telemetry_coverage", {}))
	lines.append("")
	lines.append("## Scenario probes")
	_append_scenario_probe_lines(lines, report.get("scenario_probes", {}))
	lines.append("")
	lines.append("## Strategy metrics")
	_append_strategy_metrics_table(lines, report.get("strategy_metrics", {}))
	lines.append("")
	lines.append("## Wave metrics")
	_append_wave_metrics_table(lines, report.get("wave_metrics", {}))
	lines.append("")
	lines.append("## Enemy kind metrics")
	_append_enemy_kind_metrics_table(lines, report.get("enemy_kind_metrics", {}))
	lines.append("")
	lines.append("## Boss and commander metrics")
	_append_boss_commander_metrics(lines, report.get("boss_commander_metrics", {}))
	lines.append("")
	lines.append("## Late-wave buckets")
	_append_late_wave_metrics_table(lines, report.get("late_wave_metrics", {}))
	lines.append("")
	lines.append("## Seed metrics")
	_append_seed_metrics_table(lines, report.get("seed_metrics", {}))
	lines.append("")
	lines.append("## Economy curve")
	_append_economy_metrics(lines, report.get("economy_metrics", {}))
	lines.append("")
	lines.append("## Damage curve")
	_append_damage_metrics(lines, report.get("damage_metrics", {}))
	lines.append("")
	lines.append("## Tower metrics")
	_append_tower_metrics_table(lines, report.get("tower_metrics", {}))
	lines.append("")
	lines.append("## Upgrade branch metrics")
	_append_upgrade_branch_metrics(lines, report.get("upgrade_branch_metrics", {}))
	lines.append("")
	lines.append("## Target mode metrics")
	_append_target_mode_metrics(lines, report.get("target_mode_metrics", {}))
	lines.append("")
	lines.append("## Progression metrics")
	_append_progression_metrics(lines, report.get("progression_metrics", {}))
	lines.append("")
	lines.append("## Previous-report comparison")
	_append_regression_lines(lines, report.get("regression", {}))
	lines.append("")
	lines.append("## Blocked action metrics")
	_append_blocked_action_metrics(lines, report.get("blocked_action_metrics", {}))
	lines.append("")
	lines.append("## High-severity bugs")
	_append_issue_lines(lines, issues, "bug", 12)
	lines.append("")
	lines.append("## QoL annoyances by frequency")
	_append_frequency_lines(lines, issues, "qol", 12)
	lines.append("")
	lines.append("## Balance outliers")
	_append_issue_lines_with_empty(lines, issues, "balance", 12, "- No balance outliers met reporting thresholds for this run size.")
	lines.append("")
	lines.append("## Validation issues")
	_append_issue_lines(lines, issues, "validation", 12)
	lines.append("")
	lines.append("## Do Not Implement From This Prompt Unless Explicitly Requested")
	for limitation in report.get("known_limitations", []):
		lines.append("- %s" % str(limitation))
	_append_frequency_lines(lines, issues, "known_gap", 12)
	lines.append("")
	lines.append("## Recommended improvement plan")
	for group in ["gameplay", "ui_qol", "balance", "validation"]:
		lines.append("### %s" % str(group).capitalize().replace("_", " / "))
		for item in recommendations.get(group, []):
			lines.append("- %s" % str(item))
		lines.append("")
	return _join_strings(lines, "\n")


func _render_codex_prompt(report: Dictionary, json_path: String, markdown_path: String) -> String:
	var config: Dictionary = report.get("config", {})
	var preflight: Dictionary = report.get("preflight", {})
	var summary: Dictionary = report.get("summary", {})
	var issues: Array = report.get("issues", [])
	var recommendations: Dictionary = report.get("recommendations", {})
	var repo_root := _trim_trailing_slashes(ProjectSettings.globalize_path("res://"))
	var lines: Array = []
	lines.append("# Codex Prompt: Audit AI Simulation Findings")
	lines.append("")
	lines.append("You are working in `%s` on the Godot tower defense project. Audit and verify the latest AI simulation report. Implement only confirmed issues supported by the report and current code." % repo_root)
	lines.append("")
	lines.append("This report is a diagnostic packet from a simulation bot. Treat findings as evidence to verify, not proof. No gameplay or data changes are acceptable when no confirmed issue exists.")
	lines.append("")
	lines.append("Use these generated files as the evidence packet:")
	lines.append("- Full JSON findings: `%s`" % ProjectSettings.globalize_path(json_path))
	lines.append("- Human report: `%s`" % ProjectSettings.globalize_path(markdown_path))
	lines.append("")
	lines.append("Important constraints:")
	lines.append("- First inspect the current repo state with `git status --short`.")
	lines.append("- Treat simulation findings as evidence to verify against current code, not as unquestioned truth.")
	lines.append("- This report exercises direct vertical-slice APIs, not `scenes/main.tscn`, full UI wiring, audio, or manual input behavior.")
	lines.append("- Keep changes small, playable, and reviewable. Do not stage, commit, push, delete, or revert unrelated files.")
	lines.append("- Keep `data/game_data.json` and current gameplay code as the source of truth. Do not move tower, enemy, wave, upgrade, economy, or progression rules into the AI simulation bot.")
	lines.append("- Use the AI simulation bot for diagnostics, telemetry-style reporting, balance/stress sweeps, save/load torture coverage, and edge-case exploration that consume the current game APIs.")
	lines.append("- Keep content validators, runtime invariants, golden scenario tests, debug overlays, and debug commands in the main game project unless a small bot-side probe is explicitly diagnostic.")
	lines.append("- Preserve known vertical-slice gaps as known gaps unless you intentionally implement that missing feature.")
	lines.append("- If a generated finding is noisy, conflicting, or not directly implementable, document why and implement the nearest safe improvement.")
	lines.append("")
	lines.append("## Run Configuration")
	if not str(config.get("report_label", "")).is_empty():
		lines.append("- Label: `%s`" % str(config.get("report_label", "")))
	lines.append("- Profile: `%s`" % str(config.get("profile", "")))
	lines.append("- Evidence tier: `%s`" % str(config.get("evidence_tier", "")))
	lines.append("- Profile overridden: `%s`" % ("yes" if bool(config.get("profile_overridden", false)) else "no"))
	lines.append("- Balance actionable: `%s`" % ("yes" if bool(config.get("balance_actionable", false)) else "no"))
	lines.append("- Coverage scope: `%s`" % str(config.get("coverage_scope", "")))
	lines.append("- Profile defaults: %s" % _profile_defaults_inline(config.get("profile_defaults", {})))
	lines.append("- Runs: `%s`" % int(config.get("runs", 0)))
	lines.append("- Max waves: `%s`" % int(config.get("max_waves", 0)))
	lines.append("- Seed: `%s`" % int(config.get("seed", 0)))
	lines.append("- Seed count / step: `%s` / `%s`" % [int(config.get("seed_count", 1)), int(config.get("seed_step", 0))])
	lines.append("- Strategy group: `%s`" % str(config.get("strategy_group", "")))
	lines.append("- Strategies: `%s`" % _join_strings(config.get("strategies", []), "`, `"))
	lines.append("- Completed/game over/failed: `%s` / `%s` / `%s`" % [int(summary.get("completed_runs", 0)), int(summary.get("game_over_runs", 0)), int(summary.get("failed_runs", 0))])
	lines.append("- Diagnostic note: audit and verify this report against current code before making changes.")
	lines.append("- %s" % SCHEMA_BASELINE_TEXT)
	if str(config.get("evidence_tier", "")) == "smoke":
		lines.append("- Warning: This is smoke/custom diagnostic evidence and is not balance-actionable.")
	for warning in report.get("evidence_warnings", []):
		lines.append("- Evidence warning: %s" % str(warning))
	lines.append("")
	lines.append("## Canonical Preflight")
	_append_preflight_lines(lines, preflight)
	lines.append("")
	lines.append("## Telemetry Coverage")
	_append_telemetry_coverage(lines, report.get("telemetry_coverage", {}))
	lines.append("")
	lines.append("## Scenario Probes")
	_append_scenario_probe_lines(lines, report.get("scenario_probes", {}))
	lines.append("")
	lines.append("## Metrics Snapshot")
	lines.append("### Strategy Metrics")
	_append_strategy_metrics_table(lines, report.get("strategy_metrics", {}))
	lines.append("")
	lines.append("### Wave Metrics")
	_append_wave_metrics_table(lines, report.get("wave_metrics", {}))
	lines.append("")
	lines.append("### Enemy Kind Metrics")
	_append_enemy_kind_metrics_table(lines, report.get("enemy_kind_metrics", {}))
	lines.append("")
	lines.append("### Boss And Commander Metrics")
	_append_boss_commander_metrics(lines, report.get("boss_commander_metrics", {}))
	lines.append("")
	lines.append("### Late-Wave Buckets")
	_append_late_wave_metrics_table(lines, report.get("late_wave_metrics", {}))
	lines.append("")
	lines.append("### Seed Metrics")
	_append_seed_metrics_table(lines, report.get("seed_metrics", {}))
	lines.append("")
	lines.append("### Economy Curve")
	_append_economy_metrics(lines, report.get("economy_metrics", {}))
	lines.append("")
	lines.append("### Damage Curve")
	_append_damage_metrics(lines, report.get("damage_metrics", {}))
	lines.append("")
	lines.append("### Tower Metrics")
	_append_tower_metrics_table(lines, report.get("tower_metrics", {}))
	lines.append("")
	lines.append("### Upgrade Branch Metrics")
	_append_upgrade_branch_metrics(lines, report.get("upgrade_branch_metrics", {}))
	lines.append("")
	lines.append("### Target Mode Metrics")
	_append_target_mode_metrics(lines, report.get("target_mode_metrics", {}))
	lines.append("")
	lines.append("### Progression Metrics")
	_append_progression_metrics(lines, report.get("progression_metrics", {}))
	lines.append("")
	lines.append("### Blocked Actions")
	_append_blocked_action_metrics(lines, report.get("blocked_action_metrics", {}))
	lines.append("")
	lines.append("### Previous-Report Comparison")
	_append_regression_lines(lines, report.get("regression", {}))
	lines.append("")
	lines.append("## Priority Order")
	lines.append("1. Fix high-severity bugs or impossible states first.")
	lines.append("2. Reduce repeated QoL friction that blocks valid player intent.")
	lines.append("3. Investigate regressions versus the previous comparable report.")
	lines.append("4. Tune clear balance outliers only when supported by multi-seed normal bot evidence.")
	lines.append("5. Add or update focused validation so each implemented fix is covered.")
	lines.append("6. Keep bot changes additive to canonical data/gameplay behavior unless the report proves a bot harness bug.")
	lines.append("7. Leave broader progression or parity gaps out of scope unless the report and code make a small safe slice obvious.")
	lines.append("")
	lines.append("## High-Severity Bugs To Fix First")
	_append_issue_lines(lines, issues, "bug", 10)
	lines.append("")
	lines.append("## QoL Annoyances To Address")
	_append_frequency_lines(lines, issues, "qol", 12)
	lines.append("")
	lines.append("## Balance Outliers To Tune")
	_append_issue_lines_with_empty(lines, issues, "balance", 12, "- No balance outliers met reporting thresholds for this run size.")
	lines.append("")
	lines.append("## Validation Issues To Fix First")
	_append_issue_lines(lines, issues, "validation", 12)
	lines.append("")
	lines.append("## Do Not Implement From This Prompt Unless Explicitly Requested")
	for limitation in report.get("known_limitations", []):
		lines.append("- %s" % str(limitation))
	_append_frequency_lines(lines, issues, "known_gap", 10)
	lines.append("")
	lines.append("## Recommended Implementation Plan")
	for group in ["gameplay", "ui_qol", "balance", "validation"]:
		lines.append("### %s" % str(group).capitalize().replace("_", " / "))
		for item in recommendations.get(group, []):
			lines.append("- %s" % str(item))
		lines.append("")
	lines.append("## Acceptance Criteria")
	lines.append("- Implement all confirmed fixes and improvements that are supported by the report and current code.")
	lines.append("- If no confirmed issue exists, make no gameplay or data changes and report why.")
	lines.append("- Update or add focused validation for changed behavior.")
	lines.append("- If the change touches data rules, update `GameData.validate_game_data()` or a focused validator instead of adding one-off bot-only checks.")
	lines.append("- If the change touches simulation diagnostics only, keep the bot consuming canonical data and current gameplay APIs.")
	lines.append("- Rerun the AI simulation medium batch after edits:")
	lines.append("```powershell")
	lines.append("C:/Users/donny/Desktop/Godot_v4.7-stable_win64.exe --headless --log-file logs/godot/godot_ai_simulation.log --path C:/Users/donny/Desktop/tower_defense_godot --script res://scripts/tools/run_ai_simulation_batch.gd -- medium --output-dir=res://.godot/ai_simulation")
	lines.append("```")
	lines.append("- Rerun the narrow Godot validation scripts relevant to any touched gameplay/UI systems.")
	lines.append("- Run `git diff --check` before finishing.")
	lines.append("- Final response should summarize changed files, validation run, remaining known gaps, and any findings intentionally deferred.")
	lines.append("")
	return _join_strings(lines, "\n")


func _append_strategy_metrics_table(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Strategy | Runs | Survival | Wave clear | Leak rate | Failed | Synthetic |")
	lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
	for strategy in _sorted_string_keys(metrics):
		var row: Dictionary = metrics[strategy]
		lines.append("| `%s` | %s | %s | %s | %s | %s | %s |" % [
			strategy,
			int(row.get("runs", 0)),
			_percent(float(row.get("survival_rate", 0.0))),
			_percent(float(row.get("wave_completion_rate", 0.0))),
			_percent(float(row.get("leak_rate", 0.0))),
			int(row.get("failed_runs", 0)),
			int(row.get("synthetic_runs", 0)),
		])


func _profile_defaults_inline(defaults: Dictionary) -> String:
	if defaults.is_empty():
		return "`unavailable`"
	var parts: Array = []
	for profile in ["medium", "deep", "overnight"]:
		if defaults.has(profile):
			var row: Dictionary = defaults[profile]
			parts.append("`%s=%s runs/%s waves/%s seeds/%s/action_log %s`" % [
				profile,
				int(row.get("runs", 0)),
				int(row.get("max_waves", 0)),
				int(row.get("seed_count", 1)),
				str(row.get("strategy_group", "default")),
				"on" if bool(row.get("full_action_log", false)) else "off",
			])
	return _join_strings(parts, ", ")


func _append_preflight_lines(lines: Array, preflight: Dictionary) -> void:
	if preflight.is_empty():
		lines.append("- Preflight unavailable.")
		return
	lines.append("| Check | Result | Checks | Errors | Warnings |")
	lines.append("| --- | --- | ---: | ---: | ---: |")
	for key in ["data_validation", "balance_sanity"]:
		var row: Dictionary = preflight.get(key, {})
		lines.append("| `%s` | `%s` | %s | %s | %s |" % [
			key,
			"ok" if bool(row.get("ok", false)) else "failed",
			int(row.get("check_count", 0)),
			int(row.get("error_count", 0)),
			int(row.get("warning_count", 0)),
		])


func _append_scenario_probe_lines(lines: Array, scenario: Dictionary) -> void:
	if scenario.is_empty() or not bool(scenario.get("enabled", false)):
		lines.append("- Scenario probes disabled: `%s`." % str(scenario.get("reason", "unavailable")))
		return
	var summary: Dictionary = scenario.get("summary", {})
	lines.append("- Mode: `%s`" % str(scenario.get("mode", "")))
	lines.append("- Summary: `%s` total, `%s` passed, `%s` failed, `%s` diagnostic, `%s` stalled." % [
		int(summary.get("total", 0)),
		int(summary.get("passed", 0)),
		int(summary.get("failed", 0)),
		int(summary.get("diagnostic", 0)),
		int(summary.get("stalled", 0)),
	])
	lines.append("- Scope note: deterministic scenario probes use direct vertical-slice APIs and do not prove scene wiring, visuals, audio, or manual play.")
	_append_scenario_probe_group(lines, "Tower families", scenario.get("tower_family_probes", []), "tower_type")
	_append_scenario_probe_group(lines, "Branches", scenario.get("branch_probes", []), "branch_id")
	_append_scenario_probe_group(lines, "Pure enemy kinds", scenario.get("enemy_kind_probes", []), "enemy_kind")
	_append_scenario_probe_group(lines, "Scheduled waves", scenario.get("scheduled_wave_probes", []), "wave")


func _append_scenario_probe_group(lines: Array, label: String, probes: Array, detail_key: String) -> void:
	lines.append("### %s" % label)
	if probes.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Probe | Detail | Result | Leak | Cycles | Damage/spend | Failures |")
	lines.append("| --- | --- | --- | ---: | ---: | ---: | --- |")
	for probe in probes:
		var result := "diagnostic" if bool(probe.get("diagnostic_only", false)) else "pass" if bool(probe.get("passed", false)) else "fail"
		var failures := _scenario_failure_labels(probe.get("failures", []), 3)
		lines.append("| `%s` | `%s` | `%s` | %s | %s | %.3f | %s |" % [
			str(probe.get("id", "")),
			str(probe.get(detail_key, "")),
			result,
			_percent(float(probe.get("leak_rate", 0.0))),
			int(probe.get("cycles_to_resolution", 0)),
			float(probe.get("damage_per_spend", 0.0)),
			failures,
		])


func _scenario_failure_labels(failures: Array, limit: int) -> String:
	if failures.is_empty():
		return "`none`"
	var labels: Array = []
	for index in range(min(limit, failures.size())):
		labels.append("`%s`" % str(failures[index].get("label", "")))
	if failures.size() > limit:
		labels.append("`+%s more`" % (failures.size() - limit))
	return _join_strings(labels, ", ")


func _append_wave_metrics_table(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Wave | Runs | Complete | Game over | Stalled | Leak rate | Spawned |")
	lines.append("| ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for wave_key in _sorted_numeric_string_keys(metrics):
		var row: Dictionary = metrics[wave_key]
		lines.append("| %s | %s | %s | %s | %s | %s | %s |" % [
			wave_key,
			int(row.get("runs", 0)),
			_percent(float(row.get("completion_rate", 0.0))),
			int(row.get("game_over", 0)),
			int(row.get("stalled", 0)),
			_percent(float(row.get("leak_rate", 0.0))),
			int(row.get("spawned", 0)),
		])


func _append_enemy_kind_metrics_table(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Enemy kind | Runs | Waves | Complete | Leak rate | Spawned | Rough DPS |")
	lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
	for enemy_kind in _sorted_string_keys(metrics):
		var row: Dictionary = metrics[enemy_kind]
		lines.append("| `%s` | %s | %s | %s | %s | %s | %.1f |" % [
			enemy_kind,
			int(row.get("runs", 0)),
			int(row.get("waves", 0)),
			_percent(float(row.get("completion_rate", 0.0))),
			_percent(float(row.get("leak_rate", 0.0))),
			int(row.get("spawned", 0)),
			float(row.get("rough_dps", 0.0)),
		])


func _append_boss_commander_metrics(lines: Array, metrics: Dictionary) -> void:
	var summary: Dictionary = metrics.get("summary", {})
	if summary.is_empty() or int(summary.get("waves", 0)) == 0:
		lines.append("- None scheduled or spawned in this run scope.")
		return
	lines.append("- Scheduled boss / commander: `%s` / `%s`" % [int(summary.get("scheduled_boss", 0)), int(summary.get("scheduled_commander", 0))])
	lines.append("- Spawned boss / commander: `%s` / `%s`" % [int(summary.get("spawned_boss", 0)), int(summary.get("spawned_commander", 0))])
	lines.append("- Completion / leak rate: `%s` / `%s`" % [_percent(float(summary.get("completion_rate", 0.0))), _percent(float(summary.get("leak_rate", 0.0)))])
	var by_wave: Dictionary = metrics.get("by_wave", {})
	if by_wave.is_empty():
		return
	lines.append("| Wave | Waves | Scheduled | Spawned | Complete | Leak rate |")
	lines.append("| ---: | ---: | ---: | ---: | ---: | ---: |")
	for wave_key in _sorted_numeric_string_keys(by_wave):
		var row: Dictionary = by_wave[wave_key]
		lines.append("| %s | %s | %s | %s | %s | %s |" % [
			wave_key,
			int(row.get("waves", 0)),
			int(row.get("scheduled_boss", 0)) + int(row.get("scheduled_commander", 0)),
			int(row.get("spawned_boss", 0)) + int(row.get("spawned_commander", 0)),
			_percent(float(row.get("completion_rate", 0.0))),
			_percent(float(row.get("leak_rate", 0.0))),
		])


func _append_late_wave_metrics_table(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Bucket | Runs | Waves | Complete | Leak rate | Spawned | Rough DPS |")
	lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
	for bucket in ["1-6", "7-12", "13-20", "21-30", "31+"]:
		var row: Dictionary = metrics.get(bucket, {})
		lines.append("| `%s` | %s | %s | %s | %s | %s | %.1f |" % [
			bucket,
			int(row.get("runs", 0)),
			int(row.get("waves", 0)),
			_percent(float(row.get("completion_rate", 0.0))),
			_percent(float(row.get("leak_rate", 0.0))),
			int(row.get("spawned", 0)),
			float(row.get("rough_dps", 0.0)),
		])


func _append_seed_metrics_table(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Seed bucket | Seed | Runs | Survival | Wave clear | Leak rate | Blocked | Failed |")
	lines.append("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for seed_key in _sorted_numeric_string_keys(metrics):
		var row: Dictionary = metrics[seed_key]
		lines.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % [
			int(row.get("seed_bucket", 0)),
			int(row.get("seed_value", 0)),
			int(row.get("runs", 0)),
			_percent(float(row.get("survival_rate", 0.0))),
			_percent(float(row.get("wave_completion_rate", 0.0))),
			_percent(float(row.get("leak_rate", 0.0))),
			int(row.get("blocked_actions", 0)),
			int(row.get("failed_runs", 0)),
		])


func _append_economy_metrics(lines: Array, metrics: Dictionary) -> void:
	var by_wave: Dictionary = metrics.get("by_wave", {})
	if by_wave.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Wave | Runs | Avg money | Avg spend | Avg lives | Avg tech | Avg towers |")
	lines.append("| ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for wave_key in _sorted_numeric_string_keys(by_wave):
		var row: Dictionary = by_wave[wave_key]
		lines.append("| %s | %s | %.1f | %.1f | %.1f | %.1f | %.1f |" % [
			wave_key,
			int(row.get("runs", 0)),
			float(row.get("avg_money_delta", 0.0)),
			float(row.get("avg_spend_delta", 0.0)),
			float(row.get("avg_lives_delta", 0.0)),
			float(row.get("avg_research_delta", 0.0)),
			float(row.get("avg_tower_count_delta", 0.0)),
		])


func _append_damage_metrics(lines: Array, metrics: Dictionary) -> void:
	var by_wave: Dictionary = metrics.get("by_wave", {})
	if by_wave.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Wave | Waves | Avg damage | Damage/spawn | Damage/leak | Rough DPS |")
	lines.append("| ---: | ---: | ---: | ---: | ---: | ---: |")
	for wave_key in _sorted_numeric_string_keys(by_wave):
		var row: Dictionary = by_wave[wave_key]
		lines.append("| %s | %s | %.1f | %.1f | %.1f | %.1f |" % [
			wave_key,
			int(row.get("waves", 0)),
			float(row.get("avg_damage", 0.0)),
			float(row.get("damage_per_spawned", 0.0)),
			float(row.get("damage_per_leak", 0.0)),
			float(row.get("rough_dps", 0.0)),
		])
	var by_tower: Dictionary = metrics.get("by_tower_type", {})
	if not by_tower.is_empty():
		lines.append("- Tower damage totals: %s" % _top_damage_inline(by_tower, 6))


func _append_regression_lines(lines: Array, regression: Dictionary) -> void:
	if regression.is_empty() or not bool(regression.get("enabled", false)):
		lines.append("- Previous-report comparison disabled.")
		return
	lines.append("- Comparable: `%s`" % ("yes" if bool(regression.get("comparable", false)) else "no"))
	lines.append("- Reason: %s" % str(regression.get("reason", "")))
	if not bool(regression.get("comparable", false)):
		return
	var deltas: Dictionary = regression.get("deltas", {})
	lines.append("- Deltas: survival `%s`, wave clear `%s`, leak `%s`, failed `%s`, blocked/run `%s`, high severity `%s`" % [
		_signed_percent(float(deltas.get("survival_rate", 0.0))),
		_signed_percent(float(deltas.get("wave_completion_rate", 0.0))),
		_signed_percent(float(deltas.get("leak_rate", 0.0))),
		_signed_int(int(deltas.get("failed_runs", 0))),
		_signed_float(float(deltas.get("blocked_actions_per_run", 0.0))),
		_signed_int(int(deltas.get("high_severity_issues", 0))),
	])
	var warnings: Array = regression.get("warnings", [])
	if warnings.is_empty():
		lines.append("- Warnings: none.")
	else:
		lines.append("- Warnings: %s" % _join_strings(warnings, "; "))


func _append_tower_metrics_table(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Tower | Placements | Normal placements | Upgrades | Specialist clears |")
	lines.append("| --- | ---: | ---: | ---: | ---: |")
	for tower_type in ENABLED_TOWER_TYPES:
		if not metrics.has(tower_type):
			continue
		var row: Dictionary = metrics[tower_type]
		lines.append("| `%s` | %s | %s | %s | %s/%s |" % [
			tower_type,
			int(row.get("placements", 0)),
			int(row.get("normal_placements", 0)),
			int(row.get("upgrades", 0)),
			int(row.get("specialist_completed_runs", 0)),
			int(row.get("specialist_runs", 0)),
		])


func _append_upgrade_branch_metrics(lines: Array, metrics: Dictionary) -> void:
	var by_branch: Dictionary = metrics.get("by_tower_branch", {})
	if by_branch.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Tower branch | Attempts | Successes | Spend | Level gain | Damage/spend |")
	lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
	for key in _top_metric_keys(by_branch, "successes", 10):
		var row: Dictionary = by_branch[key]
		lines.append("| `%s` | %s | %s | %s | %s | %.2f |" % [
			key,
			int(row.get("attempts", 0)),
			int(row.get("successes", 0)),
			int(row.get("spend", 0)),
			int(row.get("level_gain", 0)),
			float(row.get("avg_damage_per_spend", 0.0)),
		])


func _append_target_mode_metrics(lines: Array, metrics: Dictionary) -> void:
	var by_mode: Dictionary = metrics.get("by_tower_mode", {})
	if by_mode.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("| Tower mode | Selections | Changed | Wave clear | Leak rate | Damage |")
	lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
	for key in _top_metric_keys(by_mode, "selections", 10):
		var row: Dictionary = by_mode[key]
		lines.append("| `%s` | %s | %s | %s | %s | %.1f |" % [
			key,
			int(row.get("selections", 0)),
			int(row.get("changed", 0)),
			_percent(float(row.get("wave_completion_rate", 0.0))),
			_percent(float(row.get("leak_rate", 0.0))),
			float(row.get("damage", 0.0)),
		])


func _append_progression_metrics(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty():
		lines.append("- None recorded.")
		return
	lines.append("- Research earned / avg ending: `%s` / `%.1f`" % [int(metrics.get("research_earned", 0)), float(metrics.get("avg_ending_research", 0.0))])
	lines.append("- Mastery XP / towers with XP: `%.1f` / `%s`" % [float(metrics.get("mastery_xp_total", 0.0)), int(metrics.get("towers_with_mastery_xp", 0))])
	lines.append("- Paragon / mutated towers observed: `%s` / `%s`" % [int(metrics.get("paragon_towers", 0)), int(metrics.get("mutated_towers", 0))])
	var reward_cards: Dictionary = metrics.get("reward_card_data", {})
	lines.append("- Reward-card data available / exercised: `%s` / `%s` (`%s` cards)" % [
		"yes" if bool(reward_cards.get("available", false)) else "no",
		"yes" if bool(reward_cards.get("runtime_exercised", false)) else "no",
		int(reward_cards.get("card_count", 0)),
	])


func _append_telemetry_coverage(lines: Array, coverage: Dictionary) -> void:
	if coverage.is_empty():
		lines.append("- Coverage summary unavailable.")
		return
	lines.append("- Implemented: %s" % _join_strings(_sorted_string_keys(coverage.get("implemented", {})), ", "))
	lines.append("- Partial: %s" % _join_strings(_sorted_string_keys(coverage.get("partial", {})), ", "))
	var unsupported: Dictionary = coverage.get("unsupported", {})
	lines.append("- Unsupported towers: `%s`" % _join_strings(unsupported.get("shop_towers", []), "`, `"))
	lines.append("- Unported systems: `%s`" % _join_strings(coverage.get("unported", []), "`, `"))


func _append_blocked_action_metrics(lines: Array, metrics: Dictionary) -> void:
	if metrics.is_empty() or int(metrics.get("total", 0)) == 0:
		lines.append("- None recorded.")
		return
	lines.append("- Total blocked actions: `%s`" % int(metrics.get("total", 0)))
	lines.append("- Expected / avoidable blocked actions: `%s` / `%s`" % [int(metrics.get("expected_total", 0)), int(metrics.get("avoidable_total", 0))])
	lines.append("- Top blocked actions: %s" % _top_counts_inline(metrics.get("by_action", {}), 6))
	lines.append("- Top blocked reasons: %s" % _top_counts_inline(metrics.get("by_reason", {}), 6))


func _top_damage_inline(rows: Dictionary, limit: int) -> String:
	var sorted_rows: Array = []
	for key in rows.keys():
		sorted_rows.append({"key": str(key), "damage": float(rows[key].get("damage_total", 0.0))})
	sorted_rows.sort_custom(func(a, b): return float(a["damage"]) > float(b["damage"]))
	var values: Array = []
	for index in range(min(limit, sorted_rows.size())):
		values.append("`%s` %.1f" % [str(sorted_rows[index]["key"]), float(sorted_rows[index]["damage"])])
	return _join_strings(values, ", ")


func _signed_percent(value: float) -> String:
	return "%+.1f%%" % (value * 100.0)


func _signed_float(value: float) -> String:
	return "%+.3f" % value


func _signed_int(value: int) -> String:
	if value >= 0:
		return "+%s" % value
	return str(value)


func _top_counts_inline(counts: Dictionary, limit: int) -> String:
	if counts.is_empty():
		return "`none`"
	var rows: Array = []
	for key in counts.keys():
		rows.append({"key": str(key), "count": int(counts[key])})
	rows.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	var values: Array = []
	for index in range(min(limit, rows.size())):
		values.append("`%s` x%s" % [str(rows[index]["key"]), int(rows[index]["count"])])
	return _join_strings(values, ", ")


func _top_metric_keys(rows: Dictionary, metric: String, limit: int) -> Array:
	var sorted_rows: Array = []
	for key in rows.keys():
		sorted_rows.append({"key": str(key), "value": float(rows[key].get(metric, 0.0))})
	sorted_rows.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	var result: Array = []
	for index in range(min(limit, sorted_rows.size())):
		result.append(str(sorted_rows[index]["key"]))
	return result


func _percent(value: float) -> String:
	return "%.1f%%" % (value * 100.0)


func _sorted_string_keys(values: Dictionary) -> Array:
	var keys: Array = values.keys()
	keys.sort()
	return keys


func _sorted_numeric_string_keys(values: Dictionary) -> Array:
	var keys: Array = values.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	return keys


func _append_issue_lines(lines: Array, issues: Array, category: String, limit: int) -> void:
	_append_issue_lines_with_empty(lines, issues, category, limit, "- None recorded.")


func _append_issue_lines_with_empty(lines: Array, issues: Array, category: String, limit: int, empty_text: String) -> void:
	var count := 0
	for issue in issues:
		if str(issue.get("category", "")) != category:
			continue
		count += 1
		if count <= limit:
			lines.append("- `%s` %s: %s" % [str(issue.get("id", "")), str(issue.get("label", "")), str(issue.get("message", ""))])
	if count == 0:
		lines.append(empty_text)
	elif count > limit:
		lines.append("- ...and `%s` more. See JSON for details." % (count - limit))


func _append_frequency_lines(lines: Array, issues: Array, category: String, limit: int) -> void:
	var counts := {}
	for issue in issues:
		if str(issue.get("category", "")) == category:
			_increment_count(counts, str(issue.get("label", "")))
	if counts.is_empty():
		lines.append("- None recorded.")
		return
	var rows: Array = []
	for label in counts.keys():
		rows.append({"label": str(label), "count": int(counts[label])})
	rows.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	for index in range(min(limit, rows.size())):
		lines.append("- `%s` x%s" % [str(rows[index]["label"]), int(rows[index]["count"])])
	if rows.size() > limit:
		lines.append("- ...and `%s` more categories. See JSON for details." % (rows.size() - limit))


func _increment_count(counts: Dictionary, key: String, amount: int = 1) -> void:
	counts[key] = int(counts.get(key, 0)) + amount


func _join_path(dir_path: String, file_name: String) -> String:
	var normalized := dir_path
	while normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	return "%s/%s" % [normalized, file_name]


func _trim_trailing_slashes(path: String) -> String:
	var normalized := path
	while normalized.ends_with("/") or normalized.ends_with("\\"):
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized


func _timestamp() -> String:
	var now := Time.get_datetime_dict_from_system(false)
	return "%04d_%02d_%02d_%02d%02d" % [
		int(now.get("year", 0)),
		int(now.get("month", 0)),
		int(now.get("day", 0)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
	]


func _archive_file_stem_from_config(config: Dictionary, timestamp: String) -> String:
	var parts: Array = ["ai_simulation"]
	var label := _slug_part(str(config.get("report_label", "")))
	if not label.is_empty():
		parts.append(label)
	var profile := _slug_part(str(config.get("profile", "custom")))
	if profile.is_empty():
		profile = "custom"
	parts.append(profile)
	parts.append("%sruns" % _archive_value(config, "runs"))
	parts.append("%swaves" % _archive_value(config, "max_waves"))
	parts.append("seed%s" % _archive_value(config, "seed"))
	parts.append(timestamp)
	return _join_strings(parts, "_")


func _archive_value(config: Dictionary, key: String) -> String:
	if not config.has(key):
		return "unknown"
	return str(int(config.get(key, 0)))


func _slug_part(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	var result := ""
	var last_was_separator := false
	for index in range(normalized.length()):
		var code := normalized.unicode_at(index)
		var character := normalized.substr(index, 1)
		var is_letter := code >= 97 and code <= 122
		var is_number := code >= 48 and code <= 57
		if is_letter or is_number:
			result += character
			last_was_separator = false
		elif not last_was_separator and not result.is_empty():
			result += "_"
			last_was_separator = true
	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)
	return result


func _join_strings(values: Array, separator: String) -> String:
	var text := ""
	for index in range(values.size()):
		if index > 0:
			text += separator
		text += str(values[index])
	return text
