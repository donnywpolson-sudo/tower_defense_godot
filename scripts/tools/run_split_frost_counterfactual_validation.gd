extends SceneTree

const OK_TOKEN := "SPLIT_FROST_COUNTERFACTUAL_VALIDATION_OK"
const OUTPUT_PATH := "res://logs/godot/split_frost_broader_paired_replay_2026_07_14.json"
const COST_MATCHED_OK_TOKEN := "SPLIT_FROST_COST_MATCHED_VALIDATION_OK"
const COST_MATCHED_OUTPUT_PATH := "res://logs/godot/split_frost_cost_matched_paired_replay_2026_07_14.json"
const STEP_DELTA := 0.2
const MAX_CYCLES := 900
const SETUP_MONEY := 5000
const SETUP_LIVES := 25
const MATRIX_WAVES := [6, 10]
const MATRIX_LAYOUTS := ["default", "active"]
const MATRIX_VARIANTS := ["glacier", "shatter", "no_frost"]
const MATRIX_REPEAT_COUNT := 2
const BROADER_MAP_NAMES := ["Classic Road", "Split Road", "Zigzag Road", "Spiral Road"]
const BROADER_WAVES := [1, 2, 3, 4, 5, 8, 9, 10]
const BROADER_BUILD_VARIANTS := ["mixed", "rotated_lane_priority"]
const SEED := 336
const MAP_CLASSIC := 0
const SPLIT_MAP_NAME := "Split Road"
const ACTIVE_CONTROL_SITE := Vector2(756, 405)
const MIXED_WITH_FROST := ["archer", "machine_gun", "cannon", "frost", "tesla", "sniper"]
const MIXED_WITHOUT_FROST := ["archer", "machine_gun", "cannon", "poison", "tesla", "sniper"]
const ROTATED_WITH_FROST := ["machine_gun", "archer", "frost", "cannon", "sniper", "tesla"]
const ROTATED_WITHOUT_FROST := ["machine_gun", "archer", "poison", "cannon", "sniper", "tesla"]
const COST_MATRIX_MAP_NAMES := ["Split Road", "Spiral Road"]
const COST_MATRIX_WAVES := [8]
const COST_MATRIX_LAYOUTS := ["default", "active"]
const COST_MATRIX_BUILD_VARIANT := "mixed"
const COST_MATRIX_VARIANTS := ["glacier", "shatter", "no_frost"]
const COST_MATRIX_CONTROL_MODES := ["baseline", "cost_matched"]
const COST_MATCH_EXPECTED_SPEND := 815
const COST_MATCH_TARGET_BRANCH_SPEND := 810
const COST_MATCH_ALLOWED_DELTA := 5
const COST_MATCH_UPGRADE_COSTS := [60, 125, 175]
const COST_MATCH_UPGRADE_TOWER := "archer"
const COST_MATCH_ARCHER_BRANCH := "deadeye"
const SHATTER_ABLATION_OK_TOKEN := "SPLIT_FROST_SHATTER_ABLATION_VALIDATION_OK"
const SHATTER_ABLATION_OUTPUT_PATH := "res://logs/godot/split_frost_shatter_burst_ablation_2026_07_14.json"
const SHATTER_ABLATION_RATIOS := [0.20, 0.18, 0.16]
const CANDIDATE_SITES := [
	Vector2(108, 108), Vector2(108, 540), Vector2(324, 108), Vector2(324, 540),
	Vector2(486, 162), Vector2(486, 486), Vector2(702, 108), Vector2(702, 540),
	Vector2(243, 351), Vector2(648, 351), Vector2(378, 405), Vector2(756, 405),
]

var _errors: Array = []
var _split_map_index := -1


func _initialize() -> void:
	var requested_shatter_ratio := _requested_shatter_burst_ratio()
	if _shatter_ablation_mode_requested() or requested_shatter_ratio >= 0.0:
		_run_shatter_ablation_validation([requested_shatter_ratio] if requested_shatter_ratio >= 0.0 else SHATTER_ABLATION_RATIOS)
		return
	if _cost_matched_mode_requested():
		_run_cost_matched_validation()
		return
	var map_probe_game := _create_game()
	map_probe_game.reset_slice(MAP_CLASSIC)
	_split_map_index = _resolve_map_index(map_probe_game, SPLIT_MAP_NAME)
	var broader_map_indices := _resolve_broader_map_indices(map_probe_game)
	_teardown_game(map_probe_game)
	if _split_map_index < 0:
		_errors.append("Could not resolve the canonical Split Road map by name.")
	for map_name in BROADER_MAP_NAMES:
		if int(broader_map_indices.get(map_name, -1)) < 0:
			_errors.append("Could not resolve broader matrix map: %s." % map_name)
	var lane_probe := _run_lane_probe()
	var branch_probe := _run_branch_probe()
	var cases: Array = []
	for wave in MATRIX_WAVES:
		for layout_id in MATRIX_LAYOUTS:
			for variant in MATRIX_VARIANTS:
				for repeat_index in range(MATRIX_REPEAT_COUNT):
					var branch_id: String = variant if variant in ["glacier", "shatter"] else ""
					var tower_types: Array = MIXED_WITH_FROST if branch_id != "" else MIXED_WITHOUT_FROST
					cases.append(_run_case({
						"case_id": "split_%s_wave%s_%s_repeat%s" % [layout_id, int(wave), variant, repeat_index + 1],
						"map_index": _split_map_index,
						"map_name_requested": SPLIT_MAP_NAME,
						"wave": int(wave),
						"layout_id": layout_id,
						"build_variant": "mixed",
						"tower_types": tower_types,
						"branch_id": branch_id,
						"repeat_index": repeat_index + 1,
						"control_site_override": ACTIVE_CONTROL_SITE if layout_id == "active" else null,
					}))

	var paired := _build_paired_comparisons(cases)
	var determinism_checks := _build_determinism_checks(cases)
	var case_by_id := _case_map(cases)
	var runtime_invariant_failures := _collect_runtime_invariant_failures(cases)
	_validate_results(cases, paired, determinism_checks, lane_probe, branch_probe)
	var broader_cases := _run_broader_matrix(broader_map_indices)
	var broader_paired := _build_broader_paired_comparisons(broader_cases)
	var broader_determinism := _build_broader_determinism_checks(broader_cases)
	_validate_broader_results(broader_cases, broader_paired, broader_determinism, broader_map_indices)
	var broader_summary := _build_broader_summary(broader_cases, broader_paired, broader_determinism)
	var report := {
		"schema_version": 3,
		"seed": SEED,
		"matrix_definition": {
			"map_name": SPLIT_MAP_NAME,
			"map_index": _split_map_index,
			"waves": MATRIX_WAVES,
			"layouts": MATRIX_LAYOUTS,
			"variants": MATRIX_VARIANTS,
			"repeat_count": MATRIX_REPEAT_COUNT,
			"expected_case_count": MATRIX_WAVES.size() * MATRIX_LAYOUTS.size() * MATRIX_VARIANTS.size() * MATRIX_REPEAT_COUNT,
		},
		"action_contract": {
			"setup_money": SETUP_MONEY,
			"setup_lives": SETUP_LIVES,
			"game_speed": 4.0,
			"placement_policy": "same deterministic candidate-site scan for every map/case",
			"tower_upgrade_policy": "only frost is upgraded to level 4 in branch cases; requested branch is selected before post-branch upgrades",
			"process_policy": "same scaled delta and bounded cycle limit for every paired case",
		},
		"lane_probe": lane_probe,
		"branch_probe": branch_probe,
		"paired_replays": {
			"format": "deterministic_action_trace_v2",
			"seed": SEED,
			"count": cases.size(),
			"case_ids": cases.map(func(result): return str(result.get("case_id", ""))),
		},
		"case_results": cases,
		"paired_deltas": paired,
		"determinism_checks": determinism_checks,
		"runtime_invariant_failures": runtime_invariant_failures,
		"findings": _build_findings(case_by_id, paired, lane_probe, branch_probe),
		"broader_matrix_definition": {
			"map_names": BROADER_MAP_NAMES,
			"waves": BROADER_WAVES,
			"layouts": MATRIX_LAYOUTS,
			"build_variants": BROADER_BUILD_VARIANTS,
			"variants": MATRIX_VARIANTS,
			"repeat_count": MATRIX_REPEAT_COUNT,
			"expected_case_count": BROADER_MAP_NAMES.size() * BROADER_WAVES.size() * MATRIX_LAYOUTS.size() * BROADER_BUILD_VARIANTS.size() * MATRIX_VARIANTS.size() * MATRIX_REPEAT_COUNT,
		},
		"broader_paired_replays": {
			"format": "deterministic_action_trace_v3",
			"seed": SEED,
			"count": broader_cases.size(),
			"case_ids": broader_cases.map(func(result): return str(result.get("case_id", ""))),
		},
		"broader_case_results": broader_cases,
		"broader_paired_deltas": broader_paired,
		"broader_determinism_checks": broader_determinism,
		"broader_summary": broader_summary,
		"no_code_change_if": "Do not tune Frost values unless a matched Glacier/Shatter/no-Frost advantage is reproduced across maps, representative enemy-kind waves, build variants, both repeats, and a survival, leak, life, or completion metric.",
	}
	_write_report(report)
	if _errors.is_empty():
		print(OK_TOKEN)
		print("  Evidence: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
		quit(0)
	else:
		push_error("SPLIT_FROST_COUNTERFACTUAL_VALIDATION_FAILED")
		for error in _errors:
			push_error(str(error))
		quit(1)


func _cost_matched_mode_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if str(argument) == "--control-mode=cost_matched":
			return true
	return false


func _shatter_ablation_mode_requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if str(argument) == "--shatter-burst-ratio-ablation":
			return true
	return false


func _requested_shatter_burst_ratio() -> float:
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if not text.begins_with("--shatter-burst-ratio="):
			continue
		var parsed := text.trim_prefix("--shatter-burst-ratio=").to_float()
		if SHATTER_ABLATION_RATIOS.has(parsed):
			return parsed
	return -1.0


func _run_cost_matched_validation() -> void:
	var map_probe_game := _create_game()
	map_probe_game.reset_slice(MAP_CLASSIC)
	var map_indices := {}
	for map_name in COST_MATRIX_MAP_NAMES:
		map_indices[map_name] = _resolve_map_index(map_probe_game, map_name)
	_teardown_game(map_probe_game)
	var cases: Array = []
	for map_name in COST_MATRIX_MAP_NAMES:
		var map_index := int(map_indices.get(map_name, -1))
		for wave in COST_MATRIX_WAVES:
			for layout_id in COST_MATRIX_LAYOUTS:
				for variant in ["glacier", "shatter"]:
					for repeat_index in range(MATRIX_REPEAT_COUNT):
						cases.append(_run_case({
							"case_id": "cost_%s_wave%s_%s_%s_baseline_repeat%s" % [_matrix_slug(map_name), int(wave), layout_id, variant, repeat_index + 1],
							"map_index": map_index,
							"map_name_requested": map_name,
							"wave": int(wave),
							"layout_id": layout_id,
							"build_variant": COST_MATRIX_BUILD_VARIANT,
							"tower_types": MIXED_WITH_FROST.duplicate(),
							"branch_id": variant,
							"control_mode": "baseline",
							"repeat_index": repeat_index + 1,
							"control_site_override": ACTIVE_CONTROL_SITE if layout_id == "active" else null,
						}))
				for control_mode in COST_MATRIX_CONTROL_MODES:
					for repeat_index in range(MATRIX_REPEAT_COUNT):
						cases.append(_run_case({
							"case_id": "cost_%s_wave%s_%s_no_frost_%s_repeat%s" % [_matrix_slug(map_name), int(wave), layout_id, control_mode, repeat_index + 1],
							"map_index": map_index,
							"map_name_requested": map_name,
							"wave": int(wave),
							"layout_id": layout_id,
							"build_variant": COST_MATRIX_BUILD_VARIANT,
							"tower_types": MIXED_WITHOUT_FROST.duplicate(),
							"branch_id": "",
							"control_mode": control_mode,
							"repeat_index": repeat_index + 1,
							"control_site_override": ACTIVE_CONTROL_SITE if layout_id == "active" else null,
						}))
	var paired := _build_cost_matched_comparisons(cases)
	var determinism_checks := _build_cost_matched_determinism_checks(cases)
	_validate_cost_matched_results(cases, paired, determinism_checks, map_indices)
	var report := {
		"schema_version": 1,
		"report_type": "cost_matched_split_frost_paired_replay",
		"seed": SEED,
		"control_mode": "cost_matched",
		"matrix_definition": {
			"map_names": COST_MATRIX_MAP_NAMES,
			"waves": COST_MATRIX_WAVES,
			"layouts": COST_MATRIX_LAYOUTS,
			"build_variant": COST_MATRIX_BUILD_VARIANT,
			"variants": COST_MATRIX_VARIANTS,
			"control_modes": COST_MATRIX_CONTROL_MODES,
			"repeat_count": MATRIX_REPEAT_COUNT,
			"expected_case_count": COST_MATRIX_MAP_NAMES.size() * COST_MATRIX_WAVES.size() * COST_MATRIX_LAYOUTS.size() * 4 * MATRIX_REPEAT_COUNT,
		},
		"cost_match_definition": {
			"upgrade_tower": COST_MATCH_UPGRADE_TOWER,
			"archer_branch": COST_MATCH_ARCHER_BRANCH,
			"upgrade_costs": COST_MATCH_UPGRADE_COSTS,
			"upgrade_total": COST_MATCH_UPGRADE_COSTS.reduce(func(total, cost): return int(total) + int(cost), 0),
			"expected_control_spend": COST_MATCH_EXPECTED_SPEND,
			"target_branch_spend": COST_MATCH_TARGET_BRANCH_SPEND,
			"allowed_spend_delta": COST_MATCH_ALLOWED_DELTA,
			"placement_topology_policy": "same deterministic placement sites; tower type may differ only at the Frost/poison slot",
		},
		"paired_replays": {
			"format": "deterministic_action_trace_cost_matched_v1",
			"seed": SEED,
			"count": cases.size(),
			"case_ids": cases.map(func(result): return str(result.get("case_id", ""))),
		},
		"case_results": cases,
		"paired_deltas": paired,
		"determinism_checks": determinism_checks,
		"runtime_invariant_failures": _collect_runtime_invariant_failures(cases),
		"validation_passed": _errors.is_empty(),
		"validation_errors": _errors.duplicate(),
		"no_code_change_if": "Do not tune Frost values unless the cost-matched normalized-damage and survival gates pass for a branch.",
	}
	_write_report_to(COST_MATCHED_OUTPUT_PATH, report)
	if _errors.is_empty():
		print(COST_MATCHED_OK_TOKEN)
		print("  Evidence: %s" % ProjectSettings.globalize_path(COST_MATCHED_OUTPUT_PATH))
		quit(0)
		return
	push_error("SPLIT_FROST_COST_MATCHED_VALIDATION_FAILED")
	for error in _errors:
		push_error(str(error))
	quit(1)


func _run_shatter_ablation_validation(ratios: Array) -> void:
	var map_probe_game := _create_game()
	map_probe_game.reset_slice(MAP_CLASSIC)
	var map_indices := {}
	for map_name in COST_MATRIX_MAP_NAMES:
		map_indices[map_name] = _resolve_map_index(map_probe_game, map_name)
	_teardown_game(map_probe_game)
	var arms := {}
	var all_cases: Array = []
	for ratio_value in ratios:
		var ratio: float = float(ratio_value)
		var arm_cases: Array = []
		for map_name in COST_MATRIX_MAP_NAMES:
			var map_index := int(map_indices.get(map_name, -1))
			for wave in COST_MATRIX_WAVES:
				for layout_id in COST_MATRIX_LAYOUTS:
					for variant in ["glacier", "shatter"]:
						for repeat_index in range(MATRIX_REPEAT_COUNT):
							arm_cases.append(_run_case({
								"case_id": "ablation_r%s_%s_wave%s_%s_%s_baseline_repeat%s" % [_shatter_ratio_key(ratio), _matrix_slug(map_name), int(wave), layout_id, variant, repeat_index + 1],
								"map_index": map_index,
								"map_name_requested": map_name,
								"wave": int(wave),
								"layout_id": layout_id,
								"build_variant": COST_MATRIX_BUILD_VARIANT,
								"tower_types": MIXED_WITH_FROST.duplicate(),
								"branch_id": variant,
								"control_mode": "baseline",
								"repeat_index": repeat_index + 1,
								"shatter_burst_ratio": ratio,
								"control_site_override": ACTIVE_CONTROL_SITE if layout_id == "active" else null,
							}))
					for control_mode in COST_MATRIX_CONTROL_MODES:
						for repeat_index in range(MATRIX_REPEAT_COUNT):
							arm_cases.append(_run_case({
								"case_id": "ablation_r%s_%s_wave%s_%s_no_frost_%s_repeat%s" % [_shatter_ratio_key(ratio), _matrix_slug(map_name), int(wave), layout_id, control_mode, repeat_index + 1],
								"map_index": map_index,
								"map_name_requested": map_name,
								"wave": int(wave),
								"layout_id": layout_id,
								"build_variant": COST_MATRIX_BUILD_VARIANT,
								"tower_types": MIXED_WITHOUT_FROST.duplicate(),
								"branch_id": "",
								"control_mode": control_mode,
								"repeat_index": repeat_index + 1,
								"shatter_burst_ratio": ratio,
								"control_site_override": ACTIVE_CONTROL_SITE if layout_id == "active" else null,
							}))
		var paired := _build_cost_matched_comparisons(arm_cases)
		var determinism_checks := _build_cost_matched_determinism_checks(arm_cases)
		var errors_before := _errors.size()
		_validate_cost_matched_results(arm_cases, paired, determinism_checks, map_indices)
		var arm_errors: Array = _errors.slice(errors_before)
		var arm_key := _shatter_ratio_key(ratio)
		arms[arm_key] = {
			"ratio": ratio,
			"case_results": arm_cases,
			"paired_deltas": paired,
			"determinism_checks": determinism_checks,
			"runtime_invariant_failures": _collect_runtime_invariant_failures(arm_cases),
			"validation_passed": arm_errors.is_empty(),
			"validation_errors": arm_errors,
		}
		all_cases.append_array(arm_cases)
	var report := {
		"schema_version": 1,
		"report_type": "split_frost_shatter_burst_ablation_replay",
		"seed": SEED,
		"evidence_only": true,
		"data_edit_authorized": false,
		"ablation_definition": {
			"override": "towers.branch_definitions.frost.shatter.runtime_effects.death_burst_damage_ratio",
			"baseline_ratio": 0.20,
			"candidate_ratios": [0.18, 0.16],
			"ratios": ratios,
			"cases_per_arm": COST_MATRIX_MAP_NAMES.size() * COST_MATRIX_WAVES.size() * COST_MATRIX_LAYOUTS.size() * 4 * MATRIX_REPEAT_COUNT,
			"expected_total_cases": ratios.size() * COST_MATRIX_MAP_NAMES.size() * COST_MATRIX_WAVES.size() * COST_MATRIX_LAYOUTS.size() * 4 * MATRIX_REPEAT_COUNT,
			"matrix_definition": {
				"map_names": COST_MATRIX_MAP_NAMES,
				"waves": COST_MATRIX_WAVES,
				"layouts": COST_MATRIX_LAYOUTS,
				"build_variant": COST_MATRIX_BUILD_VARIANT,
				"control_modes": COST_MATRIX_CONTROL_MODES,
				"repeat_count": MATRIX_REPEAT_COUNT,
			},
		},
		"arms": arms,
		"case_count": all_cases.size(),
		"runtime_invariant_failures": _collect_runtime_invariant_failures(all_cases),
		"validation_passed": _errors.is_empty(),
		"validation_errors": _errors.duplicate(),
		"no_code_change_if": "Keep canonical Frost values unchanged until the ablation evidence report recommends a candidate and a separate tuning edit is approved.",
	}
	_write_report_to(SHATTER_ABLATION_OUTPUT_PATH, report)
	if _errors.is_empty():
		print(SHATTER_ABLATION_OK_TOKEN)
		print("  Evidence: %s" % ProjectSettings.globalize_path(SHATTER_ABLATION_OUTPUT_PATH))
		quit(0)
	push_error("SPLIT_FROST_SHATTER_ABLATION_VALIDATION_FAILED")
	for error in _errors:
		push_error(str(error))
	quit(1)


func _shatter_ratio_key(ratio: float) -> String:
	return "%.2f" % ratio


func _build_cost_matched_comparisons(cases: Array) -> Dictionary:
	var grouped := {}
	for result in cases:
		var group_key := "%s|%s|%s|%s|%s" % [str(result.get("map_name", "")), int(result.get("wave_requested", 0)), str(result.get("layout_id", "")), str(result.get("build_variant", "")), int(result.get("repeat_index", 0))]
		if not grouped.has(group_key):
			grouped[group_key] = {}
		var result_key := "%s|%s" % [str(result.get("variant", "")), str(result.get("control_mode", "baseline"))]
		grouped[group_key][result_key] = result
	var comparisons := {}
	for group_key in grouped.keys():
		var parts: PackedStringArray = str(group_key).split("|")
		var variants: Dictionary = grouped[group_key]
		var repeat_index := int(parts[4])
		for branch in ["glacier", "shatter"]:
			for control_mode in ["baseline", "cost_matched"]:
				var left_key := "%s|baseline" % branch
				var right_key := "no_frost|%s" % control_mode
				if not variants.has(left_key) or not variants.has(right_key):
					continue
				var pair_label := "%s_%s_wave%s_%s_%s_vs_no_frost_%s" % [_matrix_slug(parts[0]), int(parts[1]), parts[2], parts[3], branch, control_mode]
				comparisons["%s_repeat%s" % [pair_label, repeat_index]] = _compare_cases(variants[left_key], variants[right_key])
	return comparisons


func _build_cost_matched_determinism_checks(cases: Array) -> Array:
	var grouped := {}
	for result in cases:
		var group_key := "%s|%s|%s|%s|%s|%s" % [str(result.get("map_name", "")), int(result.get("wave_requested", 0)), str(result.get("layout_id", "")), str(result.get("build_variant", "")), str(result.get("variant", "")), str(result.get("control_mode", "baseline"))]
		if not grouped.has(group_key):
			grouped[group_key] = []
		grouped[group_key].append(result)
	var checks: Array = []
	for group_key in grouped.keys():
		var group: Array = grouped[group_key]
		var signatures: Array = []
		for result in group:
			signatures.append(_normalized_case_signature(result))
		checks.append({
			"group": str(group_key),
			"case_ids": group.map(func(result): return str(result.get("case_id", ""))),
			"repeat_count": group.size(),
			"signatures_match": group.size() == MATRIX_REPEAT_COUNT and signatures.size() == MATRIX_REPEAT_COUNT and signatures[0] == signatures[1],
			"signatures": signatures,
		})
	return checks


func _validate_cost_matched_results(cases: Array, paired: Dictionary, determinism_checks: Array, map_indices: Dictionary) -> void:
	var expected_case_count := COST_MATRIX_MAP_NAMES.size() * COST_MATRIX_WAVES.size() * COST_MATRIX_LAYOUTS.size() * 4 * MATRIX_REPEAT_COUNT
	if cases.size() != expected_case_count:
		_errors.append("Cost-matched replay expected %d cases, got %d." % [expected_case_count, cases.size()])
	var setup_valid_count := 0
	var branch_ready_count := 0
	var cost_control_count := 0
	var cost_control_valid_count := 0
	for result in cases:
		var map_name := str(result.get("map_name", ""))
		var variant := str(result.get("variant", ""))
		var control_mode := str(result.get("control_mode", ""))
		if not COST_MATRIX_MAP_NAMES.has(map_name) or int(result.get("map_index", -1)) != int(map_indices.get(map_name, -1)) or int(result.get("wave_requested", 0)) not in COST_MATRIX_WAVES or str(result.get("layout_id", "")) not in COST_MATRIX_LAYOUTS or str(result.get("build_variant", "")) != COST_MATRIX_BUILD_VARIANT or not COST_MATRIX_VARIANTS.has(variant) or not COST_MATRIX_CONTROL_MODES.has(control_mode):
			_errors.append("Cost-matched case is outside the declared matrix: %s" % str(result.get("case_id", "")))
		if not bool(result.get("setup_valid", false)) or not bool(result.get("start_succeeded", false)):
			_errors.append("Cost-matched setup/start failed: %s" % str(result.get("case_id", "")))
		else:
			setup_valid_count += 1
		if not result.get("runtime_invariant_failures", []).is_empty():
			_errors.append("Cost-matched runtime invariants failed: %s" % str(result.get("case_id", "")))
		if variant in ["glacier", "shatter"]:
			if control_mode != "baseline" or not bool(result.get("branch_selection_succeeded", false)) or str(result.get("actual_selected_branch", "")) != variant or not bool(result.get("post_branch_upgrade_succeeded", false)):
				_errors.append("Cost-matched branch readiness failed: %s" % str(result.get("case_id", "")))
			else:
				branch_ready_count += 1
		else:
			if control_mode == "baseline" and (str(result.get("actual_selected_branch", "")) != "" or bool(result.get("branch_selection_succeeded", false))):
				_errors.append("No-Frost control unexpectedly selected a branch: %s" % str(result.get("case_id", "")))
			if control_mode == "cost_matched" and (not bool(result.get("control_branch_selection_succeeded", false)) or str(result.get("control_selected_branch", "")) != COST_MATCH_ARCHER_BRANCH):
				_errors.append("Cost-matched archer branch selection failed: %s" % str(result.get("case_id", "")))
			if control_mode == "cost_matched":
				cost_control_count += 1
				if bool(result.get("cost_match_valid", false)) and bool(result.get("control_branch_selection_valid", false)) and str(result.get("control_selected_branch", "")) == COST_MATCH_ARCHER_BRANCH and abs(int(result.get("branch_spend_delta", 999999))) <= COST_MATCH_ALLOWED_DELTA and int(result.get("total_spend", 0)) == COST_MATCH_EXPECTED_SPEND:
					cost_control_valid_count += 1
				else:
					_errors.append("Cost-matched spend or upgrade trace failed: %s" % str(result.get("case_id", "")))
	if setup_valid_count != expected_case_count:
		_errors.append("Cost-matched setup validity was %d/%d." % [setup_valid_count, expected_case_count])
	if branch_ready_count != 16:
		_errors.append("Cost-matched branch readiness was %d/16." % branch_ready_count)
	if cost_control_count != 8 or cost_control_valid_count != 8:
		_errors.append("Cost-matched controls were %d/%d valid; expected 8/8." % [cost_control_valid_count, cost_control_count])
	for check in determinism_checks:
		if not bool(check.get("signatures_match", false)):
			_errors.append("Cost-matched replay was not deterministic: %s" % str(check))
	if determinism_checks.size() != 16:
		_errors.append("Cost-matched determinism checks were %d/16." % determinism_checks.size())
	if paired.size() != 32:
		_errors.append("Cost-matched paired comparison count was %d/32." % paired.size())


func _run_lane_probe() -> Dictionary:
	var game := _create_game()
	game.reset_slice(max(0, _split_map_index))
	var lane_wave: int = int(MATRIX_WAVES[0])
	game.set_wave_for_test(lane_wave)
	var spawn_summary: Dictionary = game.spawn_regular_wave_for_test(lane_wave)
	var before_positions := {}
	var lane_counts := {}
	var lane_start_points := {}
	var lane_indices: Array = []
	for enemy in game.enemies:
		var lane_index: int = int(enemy.get("lane_index", -1))
		lane_indices.append(lane_index)
		lane_counts[lane_index] = int(lane_counts.get(lane_index, 0)) + 1
		if not before_positions.has(lane_index):
			before_positions[lane_index] = [enemy["position"].x, enemy["position"].y]
			lane_start_points[lane_index] = [enemy["position"].x, enemy["position"].y]
	game.wave_active = true
	game.process_step(0.1)
	var moved_lanes := {}
	for enemy in game.enemies:
		var lane_index := int(enemy.get("lane_index", -1))
		if not moved_lanes.has(lane_index) and before_positions.has(lane_index):
			var before: Array = before_positions[lane_index]
			var after: Vector2 = enemy["position"]
			moved_lanes[lane_index] = after.distance_to(Vector2(float(before[0]), float(before[1]))) > 0.0
	var state: Dictionary = game.serialize_run_state()
	var restored := _create_game()
	var restore_ok: bool = restored.restore_run_state(state)
	var restored_lane_indices: Array = []
	if restore_ok:
		for enemy in restored.enemies:
			restored_lane_indices.append(int(enemy.get("lane_index", -1)))
	var lane_probe := {
		"map_name": str(game.map_record.get("name", "")),
		"declared_lane_count": int(game.map_record.get("lane_count", 1)),
		"declared_path_count": game.map_record.get("paths", []).size(),
		"runtime_lane_count": game.lane_paths.size(),
		"runtime_path_point_counts": _path_point_counts(game.lane_paths),
		"spawn_summary": spawn_summary,
		"lane_counts": lane_counts,
		"lane_indices": lane_indices,
		"lane_start_points": lane_start_points,
		"moved_lanes": moved_lanes,
		"restore_ok": restore_ok,
		"restored_lane_indices": restored_lane_indices,
	}
	_teardown_game(restored)
	_teardown_game(game)
	return lane_probe


func _path_point_counts(paths: Array) -> Array:
	var counts: Array = []
	for path in paths:
		counts.append(path.size())
	return counts


func _run_branch_probe() -> Dictionary:
	var glacier_game := _create_game()
	glacier_game.reset_slice(MAP_CLASSIC)
	var glacier_tower: Dictionary = glacier_game.make_test_tower("first", "frost", 5)
	glacier_tower["selected_branch"] = "glacier"
	glacier_tower["damage"] = 10.0
	glacier_game.towers = [glacier_tower]
	var glacier_target: Dictionary = glacier_game.make_test_enemy("glacier_target", Vector2(180, 190), 0.5, 200.0)
	glacier_target["speed"] = 100.0
	glacier_game.enemies = [glacier_target]
	var glacier_projectile: Dictionary = glacier_game.make_test_projectile(glacier_tower, glacier_target, Vector2(173, 190))
	glacier_game.update_projectile_for_test(glacier_projectile, 0.02)
	var glacier_position_before: Vector2 = glacier_target["position"]
	glacier_game.update_enemy_for_test(glacier_target, 0.1)
	var glacier_position_after: Vector2 = glacier_target["position"]
	var glacier_result := {
		"freeze_timer": float(glacier_target.get("freeze_timer", 0.0)),
		"slow_multiplier": float(glacier_target.get("slow_multiplier", 1.0)),
		"frozen_position_delta": glacier_position_before.distance_to(glacier_position_after),
	}
	_teardown_game(glacier_game)

	var shatter_game := _create_game()
	shatter_game.reset_slice(MAP_CLASSIC)
	var shatter_tower: Dictionary = shatter_game.make_test_tower("first", "frost", 5)
	shatter_tower["selected_branch"] = "shatter"
	shatter_tower["damage"] = 10.0
	var followup_tower: Dictionary = shatter_game.make_test_tower("first", "archer", 1)
	followup_tower["damage"] = 10.0
	shatter_game.towers = [shatter_tower, followup_tower]
	var shatter_target: Dictionary = shatter_game.make_test_enemy("shatter_target", Vector2(180, 190), 0.5, 200.0)
	var nearby_target: Dictionary = shatter_game.make_test_enemy("nearby_target", Vector2(220, 190), 0.5, 200.0)
	shatter_game.enemies = [shatter_target, nearby_target]
	var shatter_projectile: Dictionary = shatter_game.make_test_projectile(shatter_tower, shatter_target, Vector2(173, 190))
	shatter_game.update_projectile_for_test(shatter_projectile, 0.02)
	var followup_before: float = float(shatter_target.get("hp", 0.0))
	var followup_projectile: Dictionary = shatter_game.make_test_projectile(followup_tower, shatter_target, Vector2(173, 190))
	shatter_game.update_projectile_for_test(followup_projectile, 0.02)
	var burst_before: float = float(nearby_target.get("hp", 0.0))
	shatter_game._apply_shatter_burst(shatter_target)
	var shatter_result := {
		"shatter_timer": float(shatter_target.get("shatter_timer", 0.0)),
		"slow_multiplier": float(shatter_target.get("slow_multiplier", 1.0)),
		"vulnerability_multiplier": float(shatter_target.get("shatter_vulnerability_multiplier", 1.0)),
		"followup_damage": followup_before - float(shatter_target.get("hp", 0.0)),
		"burst_damage": burst_before - float(nearby_target.get("hp", 0.0)),
	}
	_teardown_game(shatter_game)
	return {"glacier": glacier_result, "shatter": shatter_result}


func _resolve_broader_map_indices(game: Node) -> Dictionary:
	var result := {}
	for map_name in BROADER_MAP_NAMES:
		result[map_name] = _resolve_map_index(game, map_name)
	return result


func _run_broader_matrix(map_indices: Dictionary) -> Array:
	var cases: Array = []
	for map_name in BROADER_MAP_NAMES:
		var map_index := int(map_indices.get(map_name, -1))
		for wave in BROADER_WAVES:
			for layout_id in MATRIX_LAYOUTS:
				for build_variant in BROADER_BUILD_VARIANTS:
					for variant in MATRIX_VARIANTS:
						for repeat_index in range(MATRIX_REPEAT_COUNT):
							var branch_id: String = variant if variant in ["glacier", "shatter"] else ""
							cases.append(_run_case({
								"case_id": "broad_%s_wave%s_%s_%s_%s_repeat%s" % [_matrix_slug(map_name), int(wave), layout_id, build_variant, variant, repeat_index + 1],
								"map_index": map_index,
								"map_name_requested": map_name,
								"wave": int(wave),
								"layout_id": layout_id,
								"build_variant": build_variant,
								"tower_types": _tower_types_for_build_variant(build_variant, branch_id),
								"branch_id": branch_id,
								"repeat_index": repeat_index + 1,
								"control_site_override": ACTIVE_CONTROL_SITE if layout_id == "active" else null,
							}))
	return cases


func _tower_types_for_build_variant(build_variant: String, branch_id: String) -> Array:
	var with_frost: Array = MIXED_WITH_FROST
	var without_frost: Array = MIXED_WITHOUT_FROST
	if build_variant == "rotated_lane_priority":
		with_frost = ROTATED_WITH_FROST
		without_frost = ROTATED_WITHOUT_FROST
	return with_frost.duplicate() if not branch_id.is_empty() else without_frost.duplicate()


func _matrix_slug(value: String) -> String:
	return value.to_lower().replace(" ", "_")


func _apply_shatter_burst_ratio_override(game: Node, ratio: float) -> bool:
	var branch_definitions: Variant = game.game_data.get("towers", {}).get("branch_definitions", {})
	if not branch_definitions is Dictionary:
		_errors.append("Shatter ablation could not resolve branch definitions.")
		return false
	var frost_branches: Variant = branch_definitions.get("frost", {})
	if not frost_branches is Dictionary or not frost_branches.has("shatter"):
		_errors.append("Shatter ablation could not resolve the Frost Shatter branch.")
		return false
	var shatter_branch: Variant = frost_branches.get("shatter", {})
	if not shatter_branch is Dictionary:
		_errors.append("Shatter ablation branch definition is not a dictionary.")
		return false
	var runtime_effects: Variant = shatter_branch.get("runtime_effects", {})
	if not runtime_effects is Dictionary or not runtime_effects.has("death_burst_damage_ratio"):
		_errors.append("Shatter ablation could not resolve death_burst_damage_ratio.")
		return false
	runtime_effects["death_burst_damage_ratio"] = ratio
	return is_equal_approx(float(runtime_effects.get("death_burst_damage_ratio", -1.0)), ratio)


func _apply_cost_matched_control(game: Node, action_trace: Array) -> Dictionary:
	var trace: Array = []
	var archer_index := -1
	for index in range(game.towers.size()):
		if str(game.towers[index].get("type", "")) == COST_MATCH_UPGRADE_TOWER:
			archer_index = index
			break
	if archer_index < 0:
		action_trace.append({"action": "cost_match_control_failed", "reason": "missing_archer"})
		return {"valid": false, "trace": trace}
	var branch_enablement := _enable_cost_match_archer_branch(game)
	action_trace.append(branch_enablement)
	if not bool(branch_enablement.get("applied", false)):
		return {"valid": false, "trace": trace}
	game.selected_tower_index = archer_index
	var valid := true
	var branch_selection_succeeded := false
	var actual_selected_branch := ""
	for step_index in range(COST_MATCH_UPGRADE_COSTS.size()):
		if step_index == 1:
			branch_selection_succeeded = game.choose_selected_tower_branch(COST_MATCH_ARCHER_BRANCH)
			actual_selected_branch = str(game.towers[archer_index].get("selected_branch", ""))
			var branch_selection_valid: bool = branch_selection_succeeded and actual_selected_branch == COST_MATCH_ARCHER_BRANCH
			valid = valid and branch_selection_valid
			var branch_step := {
				"action": "choose_branch",
				"tower_type": COST_MATCH_UPGRADE_TOWER,
				"requested_branch": COST_MATCH_ARCHER_BRANCH,
				"actual_branch": actual_selected_branch,
				"selected": branch_selection_succeeded,
				"valid": branch_selection_valid,
			}
			trace.append(branch_step)
			action_trace.append(branch_step.duplicate())
		var expected_cost: int = int(COST_MATCH_UPGRADE_COSTS[step_index])
		var before_spend := int(game.towers[archer_index].get("money_spent", 0))
		var upgraded: bool = game.upgrade_selected_tower()
		var after_spend := int(game.towers[archer_index].get("money_spent", 0))
		var actual_cost := after_spend - before_spend
		var step_valid := upgraded and actual_cost == int(expected_cost)
		valid = valid and step_valid
		var step := {
			"action": "upgrade_tower",
			"tower_type": COST_MATCH_UPGRADE_TOWER,
			"expected_cost": expected_cost,
			"actual_cost": actual_cost,
			"upgraded": upgraded,
			"valid": step_valid,
		}
		trace.append(step)
		action_trace.append(step.duplicate())
	return {
		"valid": valid and trace.filter(func(step): return str(step.get("action", "")) == "upgrade_tower").size() == COST_MATCH_UPGRADE_COSTS.size() and branch_selection_succeeded and actual_selected_branch == COST_MATCH_ARCHER_BRANCH,
		"trace": trace,
		"branch_selection_succeeded": branch_selection_succeeded,
		"branch_selection_valid": branch_selection_succeeded and actual_selected_branch == COST_MATCH_ARCHER_BRANCH,
		"actual_selected_branch": actual_selected_branch,
	}


func _enable_cost_match_archer_branch(game: Node) -> Dictionary:
	var local_data: Dictionary = game.game_data.duplicate(true)
	var towers_value: Variant = local_data.get("towers", {})
	if not towers_value is Dictionary:
		return {"action": "enable_cost_match_branch", "tower_type": COST_MATCH_UPGRADE_TOWER, "branch_id": COST_MATCH_ARCHER_BRANCH, "applied": false, "reason": "missing_towers_data"}
	var towers: Dictionary = towers_value
	var definitions_value: Variant = towers.get("branch_definitions", {})
	var definitions: Dictionary = definitions_value if definitions_value is Dictionary else {}
	var archer_definitions_value: Variant = definitions.get(COST_MATCH_UPGRADE_TOWER, {})
	var archer_definitions: Dictionary = archer_definitions_value if archer_definitions_value is Dictionary else {}
	if not archer_definitions.has(COST_MATCH_ARCHER_BRANCH):
		return {"action": "enable_cost_match_branch", "tower_type": COST_MATCH_UPGRADE_TOWER, "branch_id": COST_MATCH_ARCHER_BRANCH, "applied": false, "reason": "missing_branch_definition"}
	var enabled_value: Variant = towers.get("runtime_enabled_branches", {})
	var enabled: Dictionary = enabled_value if enabled_value is Dictionary else {}
	var archer_enabled_value: Variant = enabled.get(COST_MATCH_UPGRADE_TOWER, [])
	var archer_enabled: Array = archer_enabled_value if archer_enabled_value is Array else []
	if not archer_enabled.has(COST_MATCH_ARCHER_BRANCH):
		archer_enabled.append(COST_MATCH_ARCHER_BRANCH)
	enabled[COST_MATCH_UPGRADE_TOWER] = archer_enabled
	towers["runtime_enabled_branches"] = enabled
	local_data["towers"] = towers
	game.game_data = local_data
	return {
		"action": "enable_cost_match_branch",
		"tower_type": COST_MATCH_UPGRADE_TOWER,
		"branch_id": COST_MATCH_ARCHER_BRANCH,
		"applied": true,
		"scope": "validator-local deep copy",
	}


func _run_case(spec: Dictionary) -> Dictionary:
	var game := _create_game()
	var map_index := int(spec.get("map_index", MAP_CLASSIC))
	var branch_id := str(spec.get("branch_id", ""))
	var tower_types: Array = spec.get("tower_types", []).duplicate()
	var control_site_override: Variant = spec.get("control_site_override", null)
	var requested_wave := int(spec.get("wave", MATRIX_WAVES[0]))
	var layout_id := str(spec.get("layout_id", "default"))
	var build_variant := str(spec.get("build_variant", "mixed"))
	var control_mode := str(spec.get("control_mode", "baseline"))
	var shatter_burst_ratio: Variant = spec.get("shatter_burst_ratio", null)
	var action_trace: Array = [
		{"action": "reset_slice", "map_index": map_index},
		{"action": "set_money", "money": SETUP_MONEY},
		{"action": "set_lives", "lives": SETUP_LIVES},
		{"action": "set_game_speed", "speed": 4.0},
		{"action": "set_wave_for_test", "wave": requested_wave},
		{"action": "set_build_variant", "build_variant": build_variant},
		{"action": "set_control_mode", "control_mode": control_mode},
	]
	game.reset_slice(map_index)
	if branch_id == "shatter" and shatter_burst_ratio != null:
		var ratio_applied := _apply_shatter_burst_ratio_override(game, float(shatter_burst_ratio))
		action_trace.append({"action": "set_shatter_burst_ratio", "ratio": float(shatter_burst_ratio), "applied": ratio_applied})
	game.money = SETUP_MONEY
	game.lives = SETUP_LIVES
	game.set_game_speed(4.0)
	game.set_wave_for_test(requested_wave)
	var requested_enemy_kind := str(game.snapshot().get("enemy_family", ""))
	var placement_results: Array = []
	var placed_indices: Array = []
	var candidate_sites: Array = _candidate_site_scan(build_variant)
	for tower_type in tower_types:
		var placed := false
		var selected_site := Vector2.INF
		var sites_to_try: Array = []
		if control_site_override is Vector2 and str(tower_type) in ["frost", "poison"]:
			sites_to_try.append(control_site_override)
		for site in candidate_sites:
			sites_to_try.append(site)
		for site in sites_to_try:
			var preview: Dictionary = game.placement_preview_snapshot(site, str(tower_type))
			if not bool(preview.get("can_place", false)):
				continue
			selected_site = preview.get("snapped_site", site)
			placed = game.place_selected_tower(selected_site, str(tower_type))
			if placed:
				candidate_sites.erase(site)
				placed_indices.append(game.towers.size() - 1)
				break
		placement_results.append({
				"tower_type": str(tower_type),
				"placed": placed,
				"site": [selected_site.x, selected_site.y] if placed else [],
			})
		action_trace.append({
			"action": "place_tower",
			"tower_type": str(tower_type),
			"placed": placed,
			"site": [selected_site.x, selected_site.y] if placed else [],
		})

	var frost_index := -1
	for index in range(game.towers.size()):
		if str(game.towers[index].get("type", "")) == "frost":
			frost_index = index
			break
	var branch_selection_succeeded := false
	var actual_selected_branch := ""
	var frost_upgrade_results: Array = []
	var post_branch_upgrade_succeeded := false
	if frost_index >= 0 and not branch_id.is_empty():
		game.selected_tower_index = frost_index
		frost_upgrade_results.append(game.upgrade_selected_tower())
		action_trace.append({"action": "upgrade_tower", "tower_type": "frost", "result": frost_upgrade_results.back()})
		branch_selection_succeeded = game.choose_selected_tower_branch(branch_id)
		action_trace.append({"action": "choose_branch", "requested": branch_id, "selected": branch_selection_succeeded})
		actual_selected_branch = str(game.towers[frost_index].get("selected_branch", ""))
		frost_upgrade_results.append(game.upgrade_selected_tower())
		post_branch_upgrade_succeeded = bool(frost_upgrade_results.back())
		action_trace.append({"action": "upgrade_tower", "tower_type": "frost", "result": frost_upgrade_results.back(), "post_branch": true})
		frost_upgrade_results.append(game.upgrade_selected_tower())
		action_trace.append({"action": "upgrade_tower", "tower_type": "frost", "result": frost_upgrade_results.back(), "post_branch": true})

	var control_upgrade_trace: Array = []
	var control_branch_selection: Dictionary = {}
	var control_branch_selection_succeeded := false
	var control_branch_selection_valid := false
	var control_selected_branch := ""
	var control_upgrade_valid := control_mode != "cost_matched"
	if branch_id.is_empty() and control_mode == "cost_matched":
		var control_upgrade_result := _apply_cost_matched_control(game, action_trace)
		control_upgrade_trace = control_upgrade_result.get("trace", [])
		control_upgrade_valid = bool(control_upgrade_result.get("valid", false))
		control_branch_selection_succeeded = bool(control_upgrade_result.get("branch_selection_succeeded", false))
		control_branch_selection_valid = bool(control_upgrade_result.get("branch_selection_valid", false))
		control_selected_branch = str(control_upgrade_result.get("actual_selected_branch", ""))
		for step in control_upgrade_trace:
			if str(step.get("action", "")) == "choose_branch":
				control_branch_selection = step.duplicate()
				break

	var start_succeeded: bool = game.start_wave()
	action_trace.append({"action": "start_wave", "wave": requested_wave, "started": start_succeeded})
	var cycles := 0
	var min_slow_multiplier := 1.0
	var slow_observations := 0
	var freeze_observations := 0
	var shatter_observations := 0
	var max_shatter_vulnerability := 1.0
	if start_succeeded:
		for cycle in range(MAX_CYCLES):
			cycles = cycle + 1
			game.set_game_speed(4.0)
			game._process_scaled_delta(STEP_DELTA)
			for enemy in game.enemies:
				var slow_timer := float(enemy.get("slow_timer", 0.0))
				if slow_timer > 0.0:
					slow_observations += 1
					min_slow_multiplier = min(min_slow_multiplier, float(enemy.get("slow_multiplier", 1.0)))
				if float(enemy.get("freeze_timer", 0.0)) > 0.0:
					freeze_observations += 1
				if float(enemy.get("shatter_timer", 0.0)) > 0.0:
					shatter_observations += 1
					max_shatter_vulnerability = max(max_shatter_vulnerability, float(enemy.get("shatter_vulnerability_multiplier", 1.0)))
			var snapshot: Dictionary = game.snapshot()
			if bool(snapshot.get("game_over", false)) or bool(snapshot.get("wave_complete", false)):
				break

	var final_state: Dictionary = game.serialize_run_state()
	var final_snapshot: Dictionary = game.snapshot()
	var declared_paths: Array = game.map_record.get("paths", [])
	var tower_summary: Array = []
	var total_damage := 0.0
	var total_spend := 0
	for tower in final_state.get("towers", []):
		var tower_damage := float(tower.get("total_damage", 0.0))
		var tower_spend := int(tower.get("money_spent", 0))
		total_damage += tower_damage
		total_spend += tower_spend
		tower_summary.append({
			"type": str(tower.get("type", "")),
			"level": int(tower.get("level", 0)),
			"selected_branch": str(tower.get("selected_branch", "")),
			"kills": int(tower.get("kills", 0)),
			"total_damage": tower_damage,
			"money_spent": tower_spend,
		})
	var spend_match_delta := total_spend - COST_MATCH_EXPECTED_SPEND if control_mode == "cost_matched" else 0
	var branch_spend_delta := total_spend - COST_MATCH_TARGET_BRANCH_SPEND if control_mode == "cost_matched" else 0
	var cost_match_valid: bool = control_upgrade_valid and control_mode == "cost_matched" and control_branch_selection_succeeded and control_selected_branch == COST_MATCH_ARCHER_BRANCH and abs(branch_spend_delta) <= COST_MATCH_ALLOWED_DELTA and spend_match_delta == 0 and total_spend == COST_MATCH_EXPECTED_SPEND
	var result := {
		"case_id": str(spec.get("case_id", "")),
		"replay_id": "%s_seed%s" % [str(spec.get("case_id", "")), SEED],
		"seed": SEED,
		"map_index": map_index,
		"map_name": str(final_state.get("map_name", "")),
		"map_name_requested": str(spec.get("map_name_requested", SPLIT_MAP_NAME)),
		"wave_requested": requested_wave,
		"enemy_kind_requested": requested_enemy_kind,
		"wave_reached": int(final_state.get("wave", requested_wave)),
		"layout_id": layout_id,
		"build_variant": build_variant,
		"control_mode": control_mode,
		"repeat_index": int(spec.get("repeat_index", 0)),
		"variant": "no_frost" if branch_id.is_empty() else branch_id,
		"declared_lane_count": int(game.map_record.get("lane_count", 1)),
		"declared_path_count": declared_paths.size(),
		"runtime_path_point_count": game.path_points.size(),
		"runtime_path_points": _vector_points(game.path_points),
		"branch_id_requested": branch_id,
		"actual_selected_branch": actual_selected_branch,
		"control_site_override": [control_site_override.x, control_site_override.y] if control_site_override is Vector2 else [],
		"branch_selection_succeeded": branch_selection_succeeded,
		"frost_upgrade_results": frost_upgrade_results,
		"post_branch_upgrade_succeeded": post_branch_upgrade_succeeded,
		"control_upgrade_trace": control_upgrade_trace,
		"control_upgrade_valid": control_upgrade_valid,
		"control_branch_selection": control_branch_selection,
		"control_branch_selection_succeeded": control_branch_selection_succeeded,
		"control_branch_selection_valid": control_branch_selection_valid,
		"control_selected_branch": control_selected_branch,
		"spend_match_target": COST_MATCH_EXPECTED_SPEND if control_mode == "cost_matched" else 0,
		"spend_match_delta": spend_match_delta,
		"target_branch_spend": COST_MATCH_TARGET_BRANCH_SPEND if control_mode == "cost_matched" else 0,
		"target_control_spend": COST_MATCH_EXPECTED_SPEND if control_mode == "cost_matched" else 0,
		"actual_control_spend": total_spend if control_mode == "cost_matched" else 0,
		"branch_spend_delta": branch_spend_delta,
		"control_spend_delta": spend_match_delta,
		"cost_match_valid": cost_match_valid,
		"placement_results": placement_results,
		"setup_valid": placement_results.size() == tower_types.size() and _all_placements_succeeded(placement_results),
		"start_succeeded": start_succeeded,
		"completed": bool(final_state.get("wave_complete", false)),
		"game_over": bool(final_state.get("game_over", false)),
		"cycles_to_resolution": cycles,
		"spawned": int(final_state.get("spawned_this_wave", 0)) + int(final_state.get("spawned_extra_this_wave", 0)),
		"kills": int(final_state.get("kills", 0)),
		"leaks": int(final_state.get("leaks", 0)),
		"lives": int(final_state.get("lives", 0)),
		"min_slow_multiplier": min_slow_multiplier,
		"slow_observations": slow_observations,
		"freeze_observations": freeze_observations,
		"shatter_observations": shatter_observations,
		"max_shatter_vulnerability": max_shatter_vulnerability,
		"total_damage": total_damage,
		"total_spend": total_spend,
		"damage_per_spend": total_damage / float(max(1, total_spend)),
		"tower_summary": tower_summary,
		"frost_effect_summary": {
			"min_slow_multiplier": min_slow_multiplier,
			"slow_observations": slow_observations,
			"freeze_observations": freeze_observations,
			"shatter_observations": shatter_observations,
			"max_shatter_vulnerability": max_shatter_vulnerability,
		},
		"action_trace": action_trace + [{"action": "process_scaled_delta", "delta": STEP_DELTA, "max_cycles": MAX_CYCLES, "until": "wave_complete_or_game_over"}],
		"final_snapshot": final_snapshot,
		"runtime_invariant_failures": game.runtime_invariant_failures(),
	}
	if shatter_burst_ratio != null:
		result["shatter_burst_ratio"] = float(shatter_burst_ratio)
	_teardown_game(game)
	return result


func _compare_cases(left: Dictionary, right: Dictionary) -> Dictionary:
	var keys := [
		"completed", "game_over", "wave_reached", "spawned", "kills", "leaks", "lives",
		"total_damage", "total_spend", "damage_per_spend", "min_slow_multiplier",
		"slow_observations", "freeze_observations", "shatter_observations", "max_shatter_vulnerability",
	]
	var deltas := {}
	for key in keys:
		var left_value = left.get(key, 0)
		var right_value = right.get(key, 0)
		if left_value is bool:
			deltas[key] = {"left": left_value, "right": right_value, "same": left_value == right_value}
		else:
			deltas[key] = {"left": left_value, "right": right_value, "delta": float(right_value) - float(left_value)}
	var left_frost_damage: float = _tower_total_damage(left, "frost")
	var right_frost_damage: float = _tower_total_damage(right, "frost")
	deltas["frost_total_damage"] = {
		"left": left_frost_damage,
		"right": right_frost_damage,
		"delta": right_frost_damage - left_frost_damage,
	}
	return {
		"left_case": str(left.get("case_id", "")),
		"right_case": str(right.get("case_id", "")),
		"wave": int(left.get("wave_requested", 0)),
		"layout_id": str(left.get("layout_id", "")),
		"build_variant": str(left.get("build_variant", "mixed")),
		"left_control_mode": str(left.get("control_mode", "baseline")),
		"right_control_mode": str(right.get("control_mode", "baseline")),
		"left_variant": str(left.get("variant", "")),
		"right_variant": str(right.get("variant", "")),
		"left_map": str(left.get("map_name", "")),
		"right_map": str(right.get("map_name", "")),
		"deltas": deltas,
		"left_towers": left.get("tower_summary", []),
		"right_towers": right.get("tower_summary", []),
	}


func _tower_total_damage(result: Dictionary, tower_type: String) -> float:
	var total: float = 0.0
	for tower in result.get("tower_summary", []):
		if str(tower.get("type", "")) == tower_type:
			total += float(tower.get("total_damage", 0.0))
	return total


func _resolve_map_index(game: Node, target_name: String) -> int:
	var maps: Array = game.game_data.get("maps", {}).get("catalog", [])
	for index in range(maps.size()):
		if str(maps[index].get("name", "")) == target_name:
			return index
	return -1


func _case_map(cases: Array) -> Dictionary:
	var result := {}
	for case_result in cases:
		result[str(case_result.get("case_id", ""))] = case_result
	return result


func _pair_key(wave: int, layout_id: String, left_variant: String, right_variant: String) -> String:
	return "wave_%s_%s_%s_vs_%s" % [wave, layout_id, left_variant, right_variant]


func _case_group_key(result: Dictionary) -> String:
	return "%s|%s|%s" % [int(result.get("wave_requested", 0)), str(result.get("layout_id", "")), str(result.get("variant", ""))]


func _build_paired_comparisons(cases: Array) -> Dictionary:
	var grouped := {}
	for result in cases:
		var group_key := "%s|%s|%s" % [int(result.get("wave_requested", 0)), str(result.get("layout_id", "")), int(result.get("repeat_index", 0))]
		if not grouped.has(group_key):
			grouped[group_key] = {}
		grouped[group_key][str(result.get("variant", ""))] = result
	var comparisons := {}
	for group_key in grouped.keys():
		var parts: PackedStringArray = str(group_key).split("|")
		var wave := int(parts[0])
		var layout_id := str(parts[1])
		var variants: Dictionary = grouped[group_key]
		var comparisons_for_group := [
			["glacier", "shatter"],
			["glacier", "no_frost"],
			["shatter", "no_frost"],
		]
		for pair in comparisons_for_group:
			var left_variant := str(pair[0])
			var right_variant := str(pair[1])
			if variants.has(left_variant) and variants.has(right_variant):
				var key := "%s_repeat%s" % [_pair_key(wave, layout_id, left_variant, right_variant), int(grouped[group_key][left_variant].get("repeat_index", 0))]
				comparisons[key] = _compare_cases(variants[left_variant], variants[right_variant])
	return comparisons


func _build_determinism_checks(cases: Array) -> Array:
	var grouped := {}
	for result in cases:
		var group_key := _case_group_key(result)
		if not grouped.has(group_key):
			grouped[group_key] = []
		grouped[group_key].append(result)
	var checks: Array = []
	for group_key in grouped.keys():
		var group: Array = grouped[group_key]
		var signatures: Array = []
		for result in group:
			signatures.append(_normalized_case_signature(result))
		checks.append({
			"group": str(group_key),
			"case_ids": group.map(func(result): return str(result.get("case_id", ""))),
			"repeat_count": group.size(),
			"signatures_match": group.size() == MATRIX_REPEAT_COUNT and signatures.size() == 2 and signatures[0] == signatures[1],
			"signatures": signatures,
		})
	return checks


func _build_broader_paired_comparisons(cases: Array) -> Dictionary:
	var grouped := {}
	for result in cases:
		var group_key := "%s|%s|%s|%s|%s" % [
			str(result.get("map_name", "")),
			int(result.get("wave_requested", 0)),
			str(result.get("layout_id", "")),
			str(result.get("build_variant", "mixed")),
			int(result.get("repeat_index", 0)),
		]
		if not grouped.has(group_key):
			grouped[group_key] = {}
		grouped[group_key][str(result.get("variant", ""))] = result
	var comparisons := {}
	for group_key in grouped.keys():
		var parts: PackedStringArray = str(group_key).split("|")
		var variants: Dictionary = grouped[group_key]
		var pair_definitions := [["glacier", "shatter"], ["glacier", "no_frost"], ["shatter", "no_frost"]]
		for pair in pair_definitions:
			var left_variant := str(pair[0])
			var right_variant := str(pair[1])
			if not variants.has(left_variant) or not variants.has(right_variant):
				continue
			var repeat_index := int(parts[4])
			var key := "%s_repeat%s" % [_broader_pair_base_key(parts[0], int(parts[1]), parts[2], parts[3], left_variant, right_variant), repeat_index]
			comparisons[key] = _compare_cases(variants[left_variant], variants[right_variant])
	return comparisons


func _broader_pair_base_key(map_name: String, wave: int, layout_id: String, build_variant: String, left_variant: String, right_variant: String) -> String:
	return "map_%s_wave_%s_%s_%s_%s_vs_%s" % [_matrix_slug(map_name), wave, layout_id, build_variant, left_variant, right_variant]


func _build_broader_determinism_checks(cases: Array) -> Array:
	var grouped := {}
	for result in cases:
		var group_key := "%s|%s|%s|%s|%s" % [
			str(result.get("map_name", "")),
			int(result.get("wave_requested", 0)),
			str(result.get("layout_id", "")),
			str(result.get("build_variant", "mixed")),
			str(result.get("variant", "")),
		]
		if not grouped.has(group_key):
			grouped[group_key] = []
		grouped[group_key].append(result)
	var checks: Array = []
	for group_key in grouped.keys():
		var group: Array = grouped[group_key]
		var signatures: Array = []
		for result in group:
			signatures.append(_normalized_case_signature(result))
		var signatures_match := group.size() == MATRIX_REPEAT_COUNT and signatures.size() == MATRIX_REPEAT_COUNT
		if signatures_match:
			for signature in signatures:
				if signature != signatures[0]:
					signatures_match = false
		checks.append({
			"group": str(group_key),
			"case_ids": group.map(func(result): return str(result.get("case_id", ""))),
			"repeat_count": group.size(),
			"signatures_match": signatures_match,
			"signatures": signatures,
		})
	return checks


func _validate_broader_results(cases: Array, paired: Dictionary, determinism_checks: Array, map_indices: Dictionary) -> void:
	var expected_case_count := BROADER_MAP_NAMES.size() * BROADER_WAVES.size() * MATRIX_LAYOUTS.size() * BROADER_BUILD_VARIANTS.size() * MATRIX_VARIANTS.size() * MATRIX_REPEAT_COUNT
	if cases.size() != expected_case_count:
		_errors.append("Broader paired replay expected %d cases, got %d." % [expected_case_count, cases.size()])
	for result in cases:
		var map_name := str(result.get("map_name", ""))
		var branch_id := str(result.get("branch_id_requested", ""))
		var variant := str(result.get("variant", ""))
		if not BROADER_MAP_NAMES.has(map_name) or int(result.get("map_index", -1)) != int(map_indices.get(map_name, -1)):
			_errors.append("Broader case resolved to the wrong canonical map: %s" % str(result))
		if int(result.get("wave_requested", 0)) not in BROADER_WAVES or str(result.get("layout_id", "")) not in MATRIX_LAYOUTS or str(result.get("build_variant", "")) not in BROADER_BUILD_VARIANTS or variant not in MATRIX_VARIANTS:
			_errors.append("Broader case is outside the declared matrix: %s" % str(result))
		if str(result.get("enemy_kind_requested", "")).is_empty():
			_errors.append("Broader case did not record an enemy kind: %s" % str(result.get("case_id", "")))
		if not bool(result.get("setup_valid", false)):
			_errors.append("Broader setup failed for %s: %s" % [str(result.get("case_id", "")), str(result.get("placement_results", []))])
		if not bool(result.get("start_succeeded", false)):
			_errors.append("Broader wave did not start for %s." % str(result.get("case_id", "")))
		if not result.get("runtime_invariant_failures", []).is_empty():
			_errors.append("Broader runtime invariants failed for %s: %s" % [str(result.get("case_id", "")), str(result.get("runtime_invariant_failures", []))])
		if result.get("action_trace", []).is_empty():
			_errors.append("Broader case has no replay action trace: %s" % str(result.get("case_id", "")))
		if branch_id.is_empty():
			if variant != "no_frost" or not str(result.get("actual_selected_branch", "")).is_empty():
				_errors.append("Broader no-Frost control unexpectedly selected a branch: %s" % str(result))
		else:
			if variant != branch_id or not bool(result.get("branch_selection_succeeded", false)) or str(result.get("actual_selected_branch", "")) != branch_id:
				_errors.append("Broader requested Frost branch was not selected: %s" % str(result))
			if not bool(result.get("post_branch_upgrade_succeeded", false)):
				_errors.append("Broader post-branch Frost upgrade failed: %s" % str(result))
	for check in determinism_checks:
		if not bool(check.get("signatures_match", false)):
			_errors.append("Broader paired replay was not deterministic: %s" % str(check))
	for map_name in BROADER_MAP_NAMES:
		for wave in BROADER_WAVES:
			for layout_id in MATRIX_LAYOUTS:
				for build_variant in BROADER_BUILD_VARIANTS:
					for pair in [["glacier", "shatter"], ["glacier", "no_frost"], ["shatter", "no_frost"]]:
						var base_key := _broader_pair_base_key(map_name, int(wave), layout_id, build_variant, str(pair[0]), str(pair[1]))
						for repeat_index in range(MATRIX_REPEAT_COUNT):
							if not paired.has("%s_repeat%s" % [base_key, repeat_index + 1]):
								_errors.append("Missing broader paired delta for %s repeat %s." % [base_key, repeat_index + 1])


func _build_broader_summary(cases: Array, paired: Dictionary, determinism_checks: Array) -> Dictionary:
	var summary := {
		"expected_case_count": BROADER_MAP_NAMES.size() * BROADER_WAVES.size() * MATRIX_LAYOUTS.size() * BROADER_BUILD_VARIANTS.size() * MATRIX_VARIANTS.size() * MATRIX_REPEAT_COUNT,
		"case_count": cases.size(),
		"paired_comparison_count": paired.size(),
		"setup_valid": 0,
		"branch_ready": 0,
		"no_frost_controls": 0,
		"completed": 0,
		"game_over": 0,
		"runtime_invariant_failure_count": 0,
		"determinism_all_match": true,
		"by_map": {},
		"by_enemy_kind": {},
		"candidate_branch_advantages": [],
		"tuning_authorized": false,
		"no_code_change_if": "Candidate branch signals require a separate decision; this matrix never authorizes Frost tuning automatically.",
	}
	for result in cases:
		var map_key := "%s:%s" % [str(result.get("map_name", "")), str(result.get("variant", ""))]
		var enemy_key := "%s:%s" % [str(result.get("enemy_kind_requested", "")), str(result.get("variant", ""))]
		for group_key in [map_key, enemy_key]:
			var target: Dictionary = summary["by_map"] if group_key == map_key else summary["by_enemy_kind"]
			if not target.has(group_key):
				target[group_key] = {"cases": 0, "setup_valid": 0, "completed": 0, "game_over": 0, "leaks": 0, "lives": 0.0, "damage": 0.0, "spend": 0}
			var row: Dictionary = target[group_key]
			row["cases"] = int(row["cases"]) + 1
			row["setup_valid"] = int(row["setup_valid"]) + (1 if bool(result.get("setup_valid", false)) else 0)
			row["completed"] = int(row["completed"]) + (1 if bool(result.get("completed", false)) else 0)
			row["game_over"] = int(row["game_over"]) + (1 if bool(result.get("game_over", false)) else 0)
			row["leaks"] = int(row["leaks"]) + int(result.get("leaks", 0))
			row["lives"] = float(row["lives"]) + float(result.get("lives", 0))
			row["damage"] = float(row["damage"]) + float(result.get("total_damage", 0.0))
			row["spend"] = int(row["spend"]) + int(result.get("total_spend", 0))
		summary["setup_valid"] = int(summary["setup_valid"]) + (1 if bool(result.get("setup_valid", false)) else 0)
		summary["branch_ready"] = int(summary["branch_ready"]) + (1 if not str(result.get("branch_id_requested", "")).is_empty() and bool(result.get("branch_selection_succeeded", false)) and bool(result.get("post_branch_upgrade_succeeded", false)) else 0)
		summary["no_frost_controls"] = int(summary["no_frost_controls"]) + (1 if str(result.get("variant", "")) == "no_frost" else 0)
		summary["completed"] = int(summary["completed"]) + (1 if bool(result.get("completed", false)) else 0)
		summary["game_over"] = int(summary["game_over"]) + (1 if bool(result.get("game_over", false)) else 0)
		summary["runtime_invariant_failure_count"] = int(summary["runtime_invariant_failure_count"]) + result.get("runtime_invariant_failures", []).size()
	for check in determinism_checks:
		if not bool(check.get("signatures_match", false)):
			summary["determinism_all_match"] = false
	for key in paired.keys():
		var comparison: Dictionary = paired[key]
		if str(comparison.get("right_variant", "")) != "no_frost" or not str(comparison.get("left_variant", "")) in ["glacier", "shatter"]:
			continue
		var deltas: Dictionary = comparison.get("deltas", {})
		var reasons: Array = []
		var completion_delta: Dictionary = deltas.get("completed", {})
		var game_over_delta: Dictionary = deltas.get("game_over", {})
		if bool(completion_delta.get("left", false)) and not bool(completion_delta.get("right", false)):
			reasons.append("completion_advantage")
		if not bool(game_over_delta.get("left", false)) and bool(game_over_delta.get("right", false)):
			reasons.append("survival_advantage")
		if float(deltas.get("leaks", {}).get("delta", 0.0)) < 0.0:
			reasons.append("leak_advantage")
		if float(deltas.get("lives", {}).get("delta", 0.0)) > 0.0:
			reasons.append("life_advantage")
		if not reasons.is_empty():
			summary["candidate_branch_advantages"].append({"pair_key": str(key), "branch": str(comparison.get("left_variant", "")), "reasons": reasons})
	return summary


func _collect_runtime_invariant_failures(cases: Array) -> Array:
	var failures: Array = []
	for result in cases:
		for failure in result.get("runtime_invariant_failures", []):
			failures.append({
				"case_id": str(result.get("case_id", "")),
				"failure": failure,
			})
	return failures


func _validate_results(cases: Array, paired: Dictionary, determinism_checks: Array, lane_probe: Dictionary, branch_probe: Dictionary) -> void:
	var expected_case_count := MATRIX_WAVES.size() * MATRIX_LAYOUTS.size() * MATRIX_VARIANTS.size() * MATRIX_REPEAT_COUNT
	if cases.size() != expected_case_count:
		_errors.append("Paired replay matrix expected %d cases, got %d." % [expected_case_count, cases.size()])
	for result in cases:
		var branch_id := str(result.get("branch_id_requested", ""))
		var variant := str(result.get("variant", ""))
		if int(result.get("map_index", -1)) != _split_map_index or str(result.get("map_name", "")) != SPLIT_MAP_NAME:
			_errors.append("Case did not resolve to the canonical Split Road map: %s" % str(result))
		if int(result.get("wave_requested", 0)) not in MATRIX_WAVES or str(result.get("layout_id", "")) not in MATRIX_LAYOUTS or variant not in MATRIX_VARIANTS:
			_errors.append("Case is outside the declared paired replay matrix: %s" % str(result))
		if not bool(result.get("setup_valid", false)):
			_errors.append("Setup failed for %s: %s" % [str(result.get("case_id", "")), str(result.get("placement_results", []))])
		if not bool(result.get("start_succeeded", false)):
			_errors.append("Wave did not start for %s." % str(result.get("case_id", "")))
		if not result.get("runtime_invariant_failures", []).is_empty():
			_errors.append("Runtime invariants failed for %s: %s" % [str(result.get("case_id", "")), str(result.get("runtime_invariant_failures", []))])
		if result.get("action_trace", []).is_empty():
			_errors.append("Case has no replay action trace: %s" % str(result.get("case_id", "")))
		if branch_id.is_empty():
			if variant != "no_frost" or not str(result.get("actual_selected_branch", "")).is_empty():
				_errors.append("No-Frost control unexpectedly selected a branch: %s" % str(result))
		else:
			if variant != branch_id or not bool(result.get("branch_selection_succeeded", false)) or str(result.get("actual_selected_branch", "")) != branch_id:
				_errors.append("Requested Frost branch was not selected: %s" % str(result))
			if not bool(result.get("post_branch_upgrade_succeeded", false)):
				_errors.append("Post-branch Frost upgrade failed: %s" % str(result))
	for check in determinism_checks:
		if not bool(check.get("signatures_match", false)):
			_errors.append("Paired replay was not deterministic: %s" % str(check))
	for wave in MATRIX_WAVES:
		for layout_id in MATRIX_LAYOUTS:
			for pair in [["glacier", "shatter"], ["glacier", "no_frost"], ["shatter", "no_frost"]]:
				var prefix := _pair_key(int(wave), layout_id, str(pair[0]), str(pair[1]))
				var found := false
				for repeat_index in range(MATRIX_REPEAT_COUNT):
					if paired.has("%s_repeat%s" % [prefix, repeat_index + 1]):
						found = true
				if not found:
					_errors.append("Missing paired delta for %s." % prefix)
	if int(lane_probe.get("declared_lane_count", 0)) != 2 or int(lane_probe.get("declared_path_count", 0)) != 2:
		_errors.append("Split lane probe did not see two declared lanes/paths: %s" % str(lane_probe))
	if int(lane_probe.get("runtime_lane_count", 0)) != 2:
		_errors.append("Split lane probe did not create two runtime lanes: %s" % str(lane_probe))
	var lane_counts: Dictionary = lane_probe.get("lane_counts", {})
	if int(lane_counts.get(0, 0)) <= 0 or int(lane_counts.get(1, 0)) <= 0:
		_errors.append("Split lane probe did not assign enemies to both lanes: %s" % str(lane_probe))
	var moved_lanes: Dictionary = lane_probe.get("moved_lanes", {})
	if not bool(moved_lanes.get(0, false)) or not bool(moved_lanes.get(1, false)):
		_errors.append("Split lane probe did not move enemies on both lanes: %s" % str(lane_probe))
	if not bool(lane_probe.get("restore_ok", false)):
		_errors.append("Split lane probe save/restore failed.")
	if JSON.stringify(lane_probe.get("lane_indices", [])) != JSON.stringify(lane_probe.get("restored_lane_indices", [])):
		_errors.append("Split lane probe did not preserve enemy lane identity across save/restore: %s" % str(lane_probe))
	var glacier_probe: Dictionary = branch_probe.get("glacier", {})
	var shatter_probe: Dictionary = branch_probe.get("shatter", {})
	if float(glacier_probe.get("freeze_timer", 0.0)) <= 0.0:
		_errors.append("Glacier probe did not apply a freeze timer: %s" % str(glacier_probe))
	if float(glacier_probe.get("slow_multiplier", 1.0)) >= float(shatter_probe.get("slow_multiplier", 1.0)):
		_errors.append("Glacier probe did not produce stronger control than Shatter probe: %s / %s" % [str(glacier_probe), str(shatter_probe)])
	if float(glacier_probe.get("frozen_position_delta", 1.0)) > 0.001:
		_errors.append("Glacier probe target moved during freeze: %s" % str(glacier_probe))
	if float(shatter_probe.get("shatter_timer", 0.0)) <= 0.0 or float(shatter_probe.get("vulnerability_multiplier", 1.0)) <= 1.0:
		_errors.append("Shatter probe did not apply vulnerability: %s" % str(shatter_probe))
	if float(shatter_probe.get("followup_damage", 0.0)) <= 10.0:
		_errors.append("Shatter probe follow-up damage did not exceed the unmarked hit: %s" % str(shatter_probe))
	if float(shatter_probe.get("burst_damage", 0.0)) <= 0.0:
		_errors.append("Shatter probe did not apply a death burst: %s" % str(shatter_probe))
	var branch_difference_observed := false
	for wave in MATRIX_WAVES:
		var active_branch_pair: Dictionary = paired.get("%s_repeat1" % _pair_key(int(wave), "active", "glacier", "shatter"), {})
		var active_deltas: Dictionary = active_branch_pair.get("deltas", {})
		var slow_delta: float = abs(float(active_deltas.get("min_slow_multiplier", {}).get("delta", 0.0)))
		var frost_damage_delta: float = abs(float(active_deltas.get("frost_total_damage", {}).get("delta", 0.0)))
		if slow_delta > 0.001 or frost_damage_delta > 0.001:
			branch_difference_observed = true
	if not branch_difference_observed:
		_errors.append("Active Glacier/Shatter matrix still has no observable branch difference: %s" % str(paired))


func _build_findings(case_by_id: Dictionary, paired: Dictionary, lane_probe: Dictionary, branch_probe: Dictionary) -> Array:
	var split: Dictionary = case_by_id.get("split_active_wave6_glacier_repeat1", {})
	var active_branch_key := "%s_repeat1" % _pair_key(6, "active", "glacier", "shatter")
	var active_no_frost_key := "%s_repeat1" % _pair_key(6, "active", "glacier", "no_frost")
	var active_no_frost_pair: Dictionary = paired.get(active_no_frost_key, {})
	return [
		{
			"lane": "validation",
			"finding_id": "split_two_lane_runtime_resolver_verified",
			"severity": "info",
			"subject": "Split Road path fidelity",
			"evidence": {
				"lane_probe": lane_probe,
				"split_case": str(split.get("case_id", "")),
				"split_runtime_path_point_count": int(split.get("runtime_path_point_count", 0)),
			},
			"current_code_location": "scripts/game/vertical_slice_game.gd:104-148 (lane-aware path loading and round-robin assignment)",
			"confidence": "high",
			"false_positive_class": "none",
			"recommended_validation": "Keep the two-lane spawn, movement, and save/restore probe in the focused validator.",
			"no_code_change_if": "Do not change Split Road balance until both lanes are covered by the broader placement and strategy matrix.",
		},
		{
			"lane": "validation",
			"finding_id": "glacier_and_shatter_runtime_effects_verified",
			"severity": "info",
			"subject": "Frost branch counterplay",
			"evidence": {
				"paired_cases": [active_branch_key],
				"comparison": paired.get(active_branch_key, {}),
				"glacier_branch_probe": branch_probe.get("glacier", {}),
				"shatter_branch_probe": branch_probe.get("shatter", {}),
				"glacier_vs_no_frost": active_no_frost_pair,
				"branch_selection_succeeded": bool(split.get("branch_selection_succeeded", false)),
			},
			"current_code_location": "scripts/game/vertical_slice_game.gd:2205-2325 (data-driven Glacier freeze and Shatter vulnerability/burst dispatch)",
			"confidence": "high",
			"false_positive_class": "none",
			"recommended_validation": "Keep the direct branch probe and active-path paired matrix in the focused validator.",
			"no_code_change_if": "Do not rebalance either branch until broader map, enemy-kind, and build-diversity runs measure control uptime and burst value.",
		},
	]


func _case_by_id(cases: Array, case_id: String) -> Dictionary:
	for result in cases:
		if str(result.get("case_id", "")) == case_id:
			return result
	return {}


func _normalized_case_signature(result: Dictionary) -> String:
	if result.is_empty():
		return ""
	return JSON.stringify({
		"map_index": result.get("map_index", -1),
		"wave_requested": result.get("wave_requested", 0),
		"layout_id": result.get("layout_id", ""),
		"build_variant": result.get("build_variant", "mixed"),
		"control_mode": result.get("control_mode", "baseline"),
		"variant": result.get("variant", ""),
		"branch_id_requested": result.get("branch_id_requested", ""),
		"actual_selected_branch": result.get("actual_selected_branch", ""),
		"branch_selection_succeeded": result.get("branch_selection_succeeded", false),
		"post_branch_upgrade_succeeded": result.get("post_branch_upgrade_succeeded", false),
		"frost_upgrade_results": result.get("frost_upgrade_results", []),
		"placement_results": result.get("placement_results", []),
		"setup_valid": result.get("setup_valid", false),
		"start_succeeded": result.get("start_succeeded", false),
		"completed": result.get("completed", false),
		"game_over": result.get("game_over", false),
		"cycles_to_resolution": result.get("cycles_to_resolution", 0),
		"spawned": result.get("spawned", 0),
		"kills": result.get("kills", 0),
		"leaks": result.get("leaks", 0),
		"lives": result.get("lives", 0),
		"total_damage": result.get("total_damage", 0.0),
		"total_spend": result.get("total_spend", 0),
		"damage_per_spend": result.get("damage_per_spend", 0.0),
		"control_upgrade_trace": result.get("control_upgrade_trace", []),
		"control_branch_selection": result.get("control_branch_selection", {}),
		"control_branch_selection_succeeded": result.get("control_branch_selection_succeeded", false),
		"control_branch_selection_valid": result.get("control_branch_selection_valid", false),
		"control_selected_branch": result.get("control_selected_branch", ""),
		"spend_match_target": result.get("spend_match_target", 0),
		"spend_match_delta": result.get("spend_match_delta", 0),
		"target_branch_spend": result.get("target_branch_spend", 0),
		"target_control_spend": result.get("target_control_spend", 0),
		"actual_control_spend": result.get("actual_control_spend", 0),
		"branch_spend_delta": result.get("branch_spend_delta", 0),
		"control_spend_delta": result.get("control_spend_delta", 0),
		"min_slow_multiplier": result.get("min_slow_multiplier", 1.0),
		"slow_observations": result.get("slow_observations", 0),
		"freeze_observations": result.get("freeze_observations", 0),
		"shatter_observations": result.get("shatter_observations", 0),
		"max_shatter_vulnerability": result.get("max_shatter_vulnerability", 1.0),
		"tower_summary": result.get("tower_summary", []),
		"action_trace": result.get("action_trace", []),
		"runtime_invariant_failures": result.get("runtime_invariant_failures", []),
	})


func _all_placements_succeeded(results: Array) -> bool:
	for result in results:
		if not bool(result.get("placed", false)):
			return false
	return true


func _vector_points(points: Array) -> Array:
	var result: Array = []
	for point in points:
		if point is Vector2:
			result.append([point.x, point.y])
	return result


func _candidate_site_scan(build_variant: String = "mixed") -> Array:
	var sites: Array = CANDIDATE_SITES.duplicate()
	if build_variant == "rotated_lane_priority":
		sites = [
			Vector2(702, 540), Vector2(702, 108), Vector2(486, 486), Vector2(486, 162),
			Vector2(324, 540), Vector2(324, 108), Vector2(108, 540), Vector2(108, 108),
			Vector2(648, 351), Vector2(243, 351), Vector2(756, 405), Vector2(378, 405),
		]
	for y in range(108, 574, 27):
		for x in range(81, 900, 27):
			var candidate := Vector2(x, y)
			if not sites.has(candidate):
				sites.append(candidate)
	return sites


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
	config.name = "SplitFrostConfig"
	data_loader.name = "SplitFrostData"
	game.name = "SplitFrostGame"
	return game


func _teardown_game(game: Node) -> void:
	game.set_process(false)
	game.set_physics_process(false)
	if game.get_parent() != null:
		game.get_parent().remove_child(game)
	game.free()


func _write_report(report: Dictionary) -> void:
	_write_report_to(OUTPUT_PATH, report)


func _write_report_to(path_value: String, report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(path_value)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_errors.append("Could not write evidence to %s." % path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
